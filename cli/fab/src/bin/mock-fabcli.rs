//! A stand-in for the FabCLI binary.
//!
//! It reproduces the parts of FabCLI's surface necturalabs-fab depends on —
//! compact JSON on stdout, structured errors on stderr, the documented exit
//! codes — from fixture files, so the whole CLI can be exercised without a Fab
//! account, a network, or any risk of touching a real library.
//!
//! Driven entirely by environment variables:
//!
//! | Variable | Effect |
//! |---|---|
//! | `MOCK_FABCLI_DIR` | Directory holding `<command>.json` fixtures. Required for data commands. |
//! | `MOCK_FABCLI_VERSION` | What `--version` prints. Default `fabcli 0.1.0`. |
//! | `MOCK_FABCLI_FAIL` | `<kind>:<exit>`, e.g. `auth_required:2`. Fails every data command. |
//! | `MOCK_FABCLI_GARBAGE` | Print non-JSON on stdout and exit 0. |
//! | `MOCK_FABCLI_EMPTY` | Print nothing and exit 0. |
//! | `MOCK_FABCLI_USAGE_ERROR` | Emit a clap-style prose error and exit 6. |
//! | `MOCK_FABCLI_HANG_MS` | Sleep this long before answering. |
//! | `MOCK_FABCLI_NOISE` | Write progress lines to stderr before answering. |
//! | `MOCK_FABCLI_NOISE_ESCAPES` | Write a progress line carrying terminal escape sequences. |
//! | `MOCK_FABCLI_FAIL_MESSAGE` | Message used by `MOCK_FABCLI_FAIL`. |
//! | `MOCK_FABCLI_LICENSE_FAIL` | `<kind>:<exit>`. Fails only licence-filtered searches. |
//!
//! A search filtered to one licence (`--filter=licenses=<slug>`) answers from
//! `search-license-<slug>.json`, and with no results when that fixture is
//! absent, so a fixture set says which listings carry which licence.
//!
//! Every invocation's argv is appended to `$MOCK_FABCLI_DIR/calls.log`, which
//! is how tests assert that a command was — or was not — issued.

use std::fs;
use std::io::Write;
use std::path::PathBuf;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    log_call(&args);

    if args.iter().any(|a| a == "--version" || a == "-V") {
        println!(
            "{}",
            std::env::var("MOCK_FABCLI_VERSION").unwrap_or_else(|_| "fabcli 0.1.0".into())
        );
        std::process::exit(0);
    }

    if let Ok(ms) = std::env::var("MOCK_FABCLI_HANG_MS") {
        if let Ok(ms) = ms.parse::<u64>() {
            std::thread::sleep(std::time::Duration::from_millis(ms));
        }
    }
    if std::env::var("MOCK_FABCLI_NOISE").is_ok() {
        for index in 0..200 {
            eprintln!("[download] chunk {index} of 200 — padding padding padding padding");
        }
    }
    if std::env::var("MOCK_FABCLI_NOISE_ESCAPES").is_ok() {
        eprintln!("\u{1b}]0;pwned-title\u{7}\u{1b}[2J\u{1b}[31mprogress 50%\u{1b}[0m");
    }
    if std::env::var("MOCK_FABCLI_USAGE_ERROR").is_ok() {
        eprintln!(
            "error: unrecognized subcommand '{}'",
            args.first().cloned().unwrap_or_default()
        );
        eprintln!("\nUsage: fabcli [OPTIONS] <COMMAND>");
        std::process::exit(6);
    }
    if let Ok(spec) = std::env::var("MOCK_FABCLI_FAIL") {
        let (kind, code) = spec.split_once(':').unwrap_or((spec.as_str(), "1"));
        let message = std::env::var("MOCK_FABCLI_FAIL_MESSAGE")
            .unwrap_or_else(|_| format!("mock failure: {kind}"));
        eprintln!("{{\"error\":{{\"kind\":\"{kind}\",\"message\":\"{message}\"}}}}");
        std::process::exit(code.parse().unwrap_or(1));
    }
    if std::env::var("MOCK_FABCLI_GARBAGE").is_ok() {
        println!("<html>upstream returned a login page</html>");
        std::process::exit(0);
    }
    if std::env::var("MOCK_FABCLI_EMPTY").is_ok() {
        std::process::exit(0);
    }

    let (name, ident) = fixture_name(&args);
    if name == "download" {
        return download(&args);
    }
    if name == "search" {
        if let Some(slug) = args
            .iter()
            .find_map(|a| a.strip_prefix("--filter=licenses="))
        {
            if let Ok(spec) = std::env::var("MOCK_FABCLI_LICENSE_FAIL") {
                let (kind, code) = spec.split_once(':').unwrap_or((spec.as_str(), "1"));
                eprintln!(
                    "{{\"error\":{{\"kind\":\"{kind}\",\"message\":\"mock failure: {kind}\"}}}}"
                );
                std::process::exit(code.parse().unwrap_or(1));
            }
            let body = read_fixture(&format!("search-license-{slug}"))
                .unwrap_or_else(|| r#"{"results":[],"cursors":{"next":null}}"#.to_string());
            println!("{}", body.trim_end());
            std::process::exit(0);
        }
    }

    // A per-id fixture wins, so a test can give each listing its own record
    // the way the real marketplace does.
    let by_id = ident
        .as_ref()
        .and_then(|id| read_fixture(&format!("{name}-{id}")));
    match by_id.or_else(|| read_fixture(&name)) {
        Some(body) => {
            println!("{}", body.trim_end());
            std::process::exit(0);
        }
        None => {
            eprintln!(
                "{{\"error\":{{\"kind\":\"not_found\",\"message\":\"mock has no fixture '{name}'\"}}}}"
            );
            std::process::exit(3);
        }
    }
}

/// Map argv onto a fixture name and, where there is one, the id it acts on.
///
/// `auth status` -> (`auth-status`, None); `listing <uid>` -> (`listing`, uid).
fn fixture_name(args: &[String]) -> (String, Option<String>) {
    let mut parts: Vec<&str> = Vec::new();
    for arg in args {
        if arg.starts_with('-') {
            break;
        }
        parts.push(arg.as_str());
        if parts.len() == 2 {
            break;
        }
    }
    match parts.as_slice() {
        ["auth", sub] => (format!("auth-{sub}"), None),
        [command, ident, ..] => ((*command).to_string(), Some((*ident).to_string())),
        [command] => ((*command).to_string(), None),
        _ => ("unknown".to_string(), None),
    }
}

fn fixture_dir() -> Option<PathBuf> {
    std::env::var_os("MOCK_FABCLI_DIR").map(PathBuf::from)
}

fn read_fixture(name: &str) -> Option<String> {
    let dir = fixture_dir()?;
    fs::read_to_string(dir.join(format!("{name}.json"))).ok()
}

fn log_call(args: &[String]) {
    let Some(dir) = fixture_dir() else {
        return;
    };
    let _ = fs::create_dir_all(&dir);
    if let Ok(mut file) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(dir.join("calls.log"))
    {
        // One write per line: licence lookups run several mocks at once, and
        // O_APPEND keeps a single write whole where `writeln!` may split it.
        let _ = file.write_all(format!("{}\n", args.join(" ")).as_bytes());
    }
}

/// Write plausible files so download behaviour can be tested end to end.
fn download(args: &[String]) {
    let mut output = None;
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if let Some(value) = arg.strip_prefix("--output=") {
            output = Some(value.to_string());
        } else if arg == "--output" || arg == "-o" {
            output = iter.next().cloned();
        }
    }
    let Some(output) = output else {
        eprintln!(
            "{{\"error\":{{\"kind\":\"invalid_args\",\"message\":\"--output is required\"}}}}"
        );
        std::process::exit(6);
    };

    let dir = PathBuf::from(&output);
    if let Err(err) = fs::create_dir_all(&dir) {
        eprintln!("{{\"error\":{{\"kind\":\"generic\",\"message\":\"{err}\"}}}}");
        std::process::exit(1);
    }
    let _ = fs::write(dir.join("Asset.uasset"), b"mock asset payload");
    let _ = fs::write(
        dir.join(".fabcli-asset.json"),
        r#"{"fabcli_version":"0.1.0","title":"Mock Castle Pack","engine_versions":["UE_5.4","UE_5.5"],"platforms":["Windows"],"file_count":1,"total_bytes":18}"#,
    );
    println!(
        r#"{{"ok":true,"files":1,"total_bytes":18,"elapsed_seconds":0.1,"output_dir":"{}","sidecar":".fabcli-asset.json"}}"#,
        output.replace('\\', "\\\\")
    );
}
