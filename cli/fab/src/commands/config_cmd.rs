//! `config` — show, locate and scaffold configuration.

use super::Ctx;
use crate::cli::{ConfigArgs, ConfigCommand};
use crate::config;
use crate::error::{ErrorCode, FabError, Result};
use crate::output::Outcome;
use serde_json::json;
use std::path::PathBuf;

/// Starter config, commented so a human can see every knob at once.
pub const TEMPLATE: &str = r#"# necturalabs-fab configuration.
# Precedence: CLI flags > NECTURALABS_FAB_* env vars > project config > user config > defaults.

# provider = "fabcli"

[fabcli]
# path = "fabcli"
# timeout-seconds = 120
# download-timeout-seconds = 7200
# version-requirement = ">=0.1.0, <0.2.0"
# library-cache = true

[download]
# directory = "Assets/Fab"
# overwrite = "refuse"      # refuse | force | require-empty
# jobs = 8

[defaults]
# engine = "unreal"         # unreal | unity | godot | blender | uefn | metahuman
# engine-version = "5.4"
# prefer-owned = true
# prefer-free = true
# count = 24
# hydrate = 6

[approval]
# claim = "require"         # require | allow | deny   (account mutation)
# download = "allow"        # allow | deny             (local write)
# Purchases are never possible and have no setting.

[output]
# mode = "auto"             # auto | json | human
"#;

/// Starter project config: only the keys a repository is allowed to set.
pub const PROJECT_TEMPLATE: &str = r#"# necturalabs-fab project configuration, committed with the repository.
# A project config may set project defaults only. Provider, executable, approval and overwrite
# settings belong in your user config (`necturalabs-fab config path`) and are refused here.

[defaults]
# engine = "unreal"         # unreal | unity | godot | blender | uefn | metahuman
# engine-version = "5.4"
# prefer-owned = true
# prefer-free = true

[download]
# directory = "Content/Fab" # relative to the project; downloads go to <directory>/<listing id>
"#;

/// Run `config`.
pub fn run(ctx: &Ctx, args: &ConfigArgs) -> Result<Outcome> {
    let outcome = match &args.command {
        ConfigCommand::Show => show(ctx),
        ConfigCommand::Path => paths(ctx),
        ConfigCommand::Init { project, force } => init(ctx, *project, *force),
    }?;
    Ok(match &ctx.config_error {
        Some(err) => outcome.warn(format!("configuration is invalid: {}", err.message)),
        None => outcome,
    })
}

fn show(ctx: &Ctx) -> Result<Outcome> {
    let data = json!({
        "config": ctx.config,
        "layers": ctx.layers,
    });
    let human = format!(
        "{}\nlayers: {}",
        toml_like(&ctx.config),
        ctx.layers
            .iter()
            .map(|layer| format!(
                "{}{}{}",
                layer.layer,
                layer
                    .path
                    .as_ref()
                    .map(|p| format!(" ({})", p.display()))
                    .unwrap_or_default(),
                if layer.applied { "" } else { " [absent]" }
            ))
            .collect::<Vec<_>>()
            .join(", ")
    );
    Ok(Outcome::read("config", data, human))
}

fn paths(ctx: &Ctx) -> Result<Outcome> {
    let user = config::user_config_path();
    let project = config::find_project_config(&ctx.cwd);
    let data = json!({
        "user": user,
        "project": project,
        "searchedNames": [".necturalabs-fab.toml", "necturalabs-fab.toml", ".necturalabs/fab.toml"],
    });
    let human = format!(
        "user:    {}\nproject: {}",
        user.as_ref()
            .map(|p| p.display().to_string())
            .unwrap_or_else(|| "-".into()),
        project
            .as_ref()
            .map(|p| p.display().to_string())
            .unwrap_or_else(|| "-".into())
    );
    Ok(Outcome::read("config", data, human))
}

fn init(ctx: &Ctx, project: bool, force: bool) -> Result<Outcome> {
    let target: PathBuf = if project {
        ctx.cwd.join(".necturalabs-fab.toml")
    } else {
        config::user_config_path().ok_or_else(|| {
            FabError::new(
                ErrorCode::ConfigInvalid,
                "this platform has no user config directory; use --project",
            )
        })?
    };

    if target.exists() && !force {
        return Err(FabError::new(
            ErrorCode::OutputConflict,
            format!("{} already exists", target.display()),
        )
        .with_hint("pass --force to overwrite it"));
    }
    if let Some(parent) = target.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&target, if project { PROJECT_TEMPLATE } else { TEMPLATE })?;

    let data = json!({"written": target});
    let human = format!("Wrote {}", target.display());
    Ok(
        Outcome::read("config", data, human).with_action(crate::approval::ActionPlan::local_write(
            "config init",
            target.display().to_string(),
            vec!["writes a starter configuration file".into()],
        )),
    )
}

fn toml_like(config: &crate::config::Config) -> String {
    toml::to_string_pretty(&serde_json::to_value(config).unwrap_or_default())
        .unwrap_or_else(|_| format!("{config:#?}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_template_parses_as_toml_and_documents_every_section() {
        let parsed: toml::Value = toml::from_str(TEMPLATE).expect("template must be valid TOML");
        assert!(parsed.get("fabcli").is_some());
        for section in [
            "[fabcli]",
            "[download]",
            "[defaults]",
            "[approval]",
            "[output]",
        ] {
            assert!(TEMPLATE.contains(section), "missing {section}");
        }
        assert!(TEMPLATE.contains("Purchases are never possible"));
    }

    #[test]
    fn the_project_template_is_accepted_by_the_project_layer() {
        let tmp = tempfile::tempdir().unwrap();
        // Uncomment every setting to prove none of them is refused.
        let body: String = PROJECT_TEMPLATE
            .lines()
            .map(|l| {
                l.strip_prefix("# ")
                    .filter(|r| r.contains(" = "))
                    .unwrap_or(l)
            })
            .map(|l| format!("{l}\n"))
            .collect();
        std::fs::write(tmp.path().join(".necturalabs-fab.toml"), body).unwrap();
        let env = crate::config::EnvReader::fixed(&[(
            "NECTURALABS_FAB_CONFIG",
            "/nonexistent/none.toml",
        )]);
        let loaded =
            crate::config::load_with_env(tmp.path(), &env).expect("project template must load");
        assert_eq!(loaded.config.defaults.engine.as_deref(), Some("unreal"));
    }
}
