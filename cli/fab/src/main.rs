//! necturalabs-fab entry point.
//!
//! Parses arguments, loads configuration, runs one command and renders the
//! result. All output and every exit code passes through here, so the
//! machine contract is decided in one place.

use clap::Parser;
use necturalabs_fab::approval::ActionPlan;
use necturalabs_fab::cli::{Cli, Command};
use necturalabs_fab::commands::{self, Ctx};
use necturalabs_fab::config;
use necturalabs_fab::error::{ErrorCode, FabError, Result};
use necturalabs_fab::output::{Meta, Outcome, Renderer};
use std::path::PathBuf;
use std::time::Instant;

fn main() {
    let started = Instant::now();
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(err) => usage_error(err, started),
    };
    let command_name = command_name(&cli.command);

    match run(&cli, started) {
        Ok((renderer, outcome, meta)) => {
            renderer.write_warnings(&outcome.warnings);
            renderer.write_stdout(&renderer.success(command_name, &outcome, &meta));
            std::process::exit(0);
        }
        Err(failure) => {
            let meta = Meta {
                version: necturalabs_fab::VERSION.to_string(),
                provider: failure.provider,
                provider_version: None,
                elapsed_ms: started.elapsed().as_millis() as u64,
            };
            let action = ActionPlan::for_command(command_name);
            failure.renderer.write_failure(&failure.renderer.failure(
                command_name,
                &action,
                &failure.error,
                &meta,
            ));
            std::process::exit(failure.error.code.exit_code());
        }
    }
}

/// Help and version are successes; every other parse failure is invalid
/// input (exit 6) — never clap's own exit 2, which agents would read as
/// "sign in". Under `--json` the failure is a normal envelope.
fn usage_error(err: clap::Error, started: Instant) -> ! {
    use clap::error::ErrorKind;
    if matches!(
        err.kind(),
        ErrorKind::DisplayHelp | ErrorKind::DisplayVersion
    ) {
        let _ = err.print();
        std::process::exit(0);
    }
    let raw: Vec<String> = std::env::args().collect();
    let json = raw.iter().any(|a| a == "--json" || a == "--output=json")
        || raw.windows(2).any(|w| w[0] == "--output" && w[1] == "json")
        || std::env::var("NECTURALABS_FAB_OUTPUT").is_ok_and(|v| v.eq_ignore_ascii_case("json"));
    if !json {
        let _ = err.print();
        std::process::exit(ErrorCode::InvalidInput.exit_code());
    }
    let rendered = err.render().to_string();
    let first_line = rendered
        .lines()
        .find(|l| !l.trim().is_empty())
        .unwrap_or("invalid arguments")
        .trim_start_matches("error: ")
        .to_string();
    let error =
        FabError::invalid(first_line).with_hint("run with --help for the accepted arguments");
    let renderer = Renderer::new(config::OutputMode::Json, true);
    let meta = Meta {
        version: necturalabs_fab::VERSION.to_string(),
        provider: "unknown".to_string(),
        provider_version: None,
        elapsed_ms: started.elapsed().as_millis() as u64,
    };
    renderer.write_failure(&renderer.failure("usage", &ActionPlan::read("usage"), &error, &meta));
    std::process::exit(error.code.exit_code());
}

struct Failure {
    renderer: Renderer,
    error: FabError,
    provider: String,
}

fn run(cli: &Cli, started: Instant) -> std::result::Result<(Renderer, Outcome, Meta), Failure> {
    // A renderer that works before configuration is loaded, so a config error
    // is still reported in the right format.
    let bootstrap = Renderer::new(
        if cli.json {
            config::OutputMode::Json
        } else if cli.human {
            config::OutputMode::Human
        } else {
            config::OutputMode::Auto
        },
        cli.quiet,
    );
    let fail = |renderer: Renderer, error: FabError, provider: &str| Failure {
        renderer,
        error,
        provider: provider.to_string(),
    };

    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let (loaded, config_error) = match load_config(cli, &cwd) {
        Ok(loaded) => (loaded, None),
        // The commands that diagnose or repair configuration must still run
        // when it is broken; they run on defaults and report the problem.
        Err(err) if repairs_config(&cli.command) => (
            config::LoadedConfig {
                config: config::Config::default(),
                layers: Vec::new(),
            },
            Some(err),
        ),
        Err(err) => return Err(fail(bootstrap, err, "unknown")),
    };
    let provider_id = loaded.config.provider.clone();

    let mut ctx = match Ctx::new(cli, loaded.config, loaded.layers, cwd) {
        Ok(ctx) => ctx,
        Err(err) => return Err(fail(bootstrap, err, &provider_id)),
    };
    ctx.started = started;
    ctx.config_error = config_error;

    let outcome = match dispatch(&ctx, cli) {
        Ok(outcome) => outcome,
        Err(err) => {
            let renderer = Renderer::new(ctx.renderer_mode(), cli.quiet);
            return Err(fail(renderer, err, ctx.provider.id()));
        }
    };
    let meta = ctx.meta(None);
    let renderer = Renderer::new(ctx.renderer_mode(), cli.quiet);
    Ok((renderer, outcome, meta))
}

fn repairs_config(command: &Command) -> bool {
    matches!(
        command,
        Command::Doctor
            | Command::Config(necturalabs_fab::cli::ConfigArgs {
                command: necturalabs_fab::cli::ConfigCommand::Path
                    | necturalabs_fab::cli::ConfigCommand::Init { .. },
            })
    )
}

fn load_config(cli: &Cli, cwd: &std::path::Path) -> Result<config::LoadedConfig> {
    let env = match &cli.config {
        Some(path) => {
            if !path.is_file() {
                return Err(FabError::new(
                    ErrorCode::ConfigInvalid,
                    format!("config file {} does not exist", path.display()),
                ));
            }
            // --config replaces the user config file only; every other
            // environment variable still applies.
            config::EnvReader::process()
                .with_override("NECTURALABS_FAB_CONFIG", &path.display().to_string())
        }
        None => config::EnvReader::process(),
    };
    let mut loaded = config::load_with_env(cwd, &env)?;

    // Global flags are the highest-precedence layer.
    if let Some(provider) = &cli.provider {
        loaded.config.provider = provider.clone();
    }
    if let Some(path) = &cli.fabcli_path {
        loaded.config.fabcli.path = path.clone();
    }
    if let Some(timeout) = cli.timeout {
        if timeout == 0 {
            return Err(FabError::invalid("--timeout must be greater than zero"));
        }
        loaded.config.fabcli.timeout_seconds = timeout;
    }
    Ok(loaded)
}

fn dispatch(ctx: &Ctx, cli: &Cli) -> Result<Outcome> {
    match &cli.command {
        Command::Search(args) => commands::search::run(ctx, args),
        Command::Find(args) => commands::find::run_find(ctx, args),
        Command::Recommend(args) => commands::find::run_recommend(ctx, args),
        Command::Inspect(args) => commands::inspect::run(ctx, args),
        Command::Ownership(args) => commands::ownership::run(ctx, args),
        Command::Library(args) => commands::library::run(ctx, args),
        Command::Download(args) => commands::download::run(ctx, args),
        Command::Claim(args) => commands::claim::run(ctx, args),
        Command::Promos(args) => commands::promos::run(ctx, args),
        Command::Auth(args) => commands::auth::run(ctx, args),
        Command::Doctor => commands::doctor::run(ctx),
        Command::Capabilities => commands::capabilities::run(ctx),
        Command::Config(args) => commands::config_cmd::run(ctx, args),
        Command::Skill(args) => commands::skill::run(ctx, args),
    }
}

fn command_name(command: &Command) -> &'static str {
    match command {
        Command::Search(_) => "search",
        Command::Find(_) => "find",
        Command::Recommend(_) => "recommend",
        Command::Inspect(_) => "inspect",
        Command::Ownership(_) => "ownership",
        Command::Library(_) => "library",
        Command::Download(_) => "download",
        Command::Claim(_) => "claim",
        Command::Promos(args) => match args.command {
            Some(necturalabs_fab::cli::PromosCommand::Claim { .. }) => "promos claim",
            None => "promos",
        },
        Command::Auth(_) => "auth",
        Command::Doctor => "doctor",
        Command::Capabilities => "capabilities",
        Command::Config(_) => "config",
        Command::Skill(_) => "skill",
    }
}
