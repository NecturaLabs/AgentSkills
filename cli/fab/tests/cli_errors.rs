//! Error paths: every failure an agent can hit, with its code and exit status.

mod support;

use support::{code, stderr, stdout, Harness};

fn error_of(value: &serde_json::Value) -> String {
    value["error"]["code"]
        .as_str()
        .unwrap_or_default()
        .to_string()
}

#[test]
fn missing_provider_executable_is_exit_7() {
    let harness =
        Harness::new("base").env("NECTURALABS_FAB_FABCLI_PATH", "/nonexistent/fabcli-xyz");
    let (value, output) = harness.json(&["search", "castle"]);
    assert_eq!(code(&output), 7);
    assert_eq!(error_of(&value), "FAB_PROVIDER_NOT_INSTALLED");
    assert_eq!(value["ok"], false);
    assert!(value["error"]["hint"].as_str().unwrap().contains("PATH"));
}

#[test]
fn unsupported_provider_version_fails_loudly_rather_than_guessing() {
    let harness = Harness::new("base").env("MOCK_FABCLI_VERSION", "fabcli 0.9.0");
    let (value, output) = harness.json(&["search", "castle"]);
    assert_eq!(code(&output), 7);
    assert_eq!(error_of(&value), "FAB_PROVIDER_UNSUPPORTED_VERSION");
    assert_eq!(value["error"]["details"]["detected"], "0.9.0");
    assert!(
        !harness.called("search"),
        "no data call may run against an unmapped version"
    );
}

#[test]
fn a_supported_patch_release_is_accepted() {
    let harness = Harness::new("base").env("MOCK_FABCLI_VERSION", "fabcli 0.1.7");
    let (_, output) = harness.json(&["search", "castle"]);
    assert_eq!(code(&output), 0);
}

#[test]
fn an_overridden_version_requirement_is_honoured() {
    let harness = Harness::new("base")
        .env("MOCK_FABCLI_VERSION", "fabcli 0.9.0")
        .env("NECTURALABS_FAB_VERSION_REQUIREMENT", ">=0.1.0");
    let (_, output) = harness.json(&["search", "castle"]);
    assert_eq!(code(&output), 0);
}

#[test]
fn authentication_failures_map_to_exit_2_and_a_recoverable_error() {
    for (kind, expected) in [
        ("auth_required", "FAB_AUTH_REQUIRED"),
        ("rate_limited", "FAB_RATE_LIMITED"),
        ("network", "FAB_NETWORK"),
        ("not_found", "FAB_NOT_FOUND"),
    ] {
        let harness = Harness::new("base").env("MOCK_FABCLI_FAIL", &format!("{kind}:1"));
        let (value, output) = harness.json(&["search", "castle"]);
        assert_eq!(error_of(&value), expected, "kind {kind}");
        let code = code(&output);
        let expected_exit = match expected {
            "FAB_AUTH_REQUIRED" => 2,
            "FAB_NOT_FOUND" => 3,
            "FAB_RATE_LIMITED" => 4,
            _ => 5,
        };
        assert_eq!(code, expected_exit, "kind {kind}");
        assert_eq!(value["error"]["recoverable"], true);
    }
}

#[test]
fn retryability_is_reported_per_error_class() {
    let harness = Harness::new("base").env("MOCK_FABCLI_FAIL", "rate_limited:4");
    let (value, _) = harness.json(&["search", "castle"]);
    assert_eq!(value["error"]["retryable"], true);

    let harness = Harness::new("base").env("MOCK_FABCLI_FAIL", "auth_required:2");
    let (value, _) = harness.json(&["search", "castle"]);
    assert_eq!(value["error"]["retryable"], false);
}

#[test]
fn malformed_provider_output_is_a_protocol_error_not_a_crash() {
    let harness = Harness::new("base").env("MOCK_FABCLI_GARBAGE", "1");
    let (value, output) = harness.json(&["search", "castle"]);
    assert_eq!(code(&output), 7);
    assert_eq!(error_of(&value), "FAB_PROVIDER_PROTOCOL");
    assert!(value["error"]["details"]["stdoutPreview"].is_string());
    assert_eq!(value["error"]["recoverable"], false);
}

#[test]
fn empty_provider_output_is_a_protocol_error() {
    let harness = Harness::new("base").env("MOCK_FABCLI_EMPTY", "1");
    let (value, output) = harness.json(&["search", "castle"]);
    assert_eq!(code(&output), 7);
    assert_eq!(error_of(&value), "FAB_PROVIDER_PROTOCOL");
}

#[test]
fn a_provider_that_rejects_our_command_line_reports_a_contract_break() {
    let harness = Harness::new("base").env("MOCK_FABCLI_USAGE_ERROR", "1");
    let (value, output) = harness.json(&["search", "castle"]);
    assert_eq!(code(&output), 7);
    assert_eq!(error_of(&value), "FAB_PROVIDER_PROTOCOL");
    assert!(value["error"]["details"]["stderr"]
        .as_str()
        .unwrap()
        .contains("Usage"));
}

#[test]
fn a_hung_provider_is_killed_at_the_timeout() {
    let harness = Harness::new("base").env("MOCK_FABCLI_HANG_MS", "8000");
    let started = std::time::Instant::now();
    let (value, output) = harness.json(&["--timeout", "1", "search", "castle"]);
    assert_eq!(code(&output), 14);
    assert_eq!(error_of(&value), "FAB_TIMEOUT");
    assert!(
        started.elapsed() < std::time::Duration::from_secs(7),
        "kill was not prompt"
    );
}

#[test]
fn invalid_input_is_rejected_before_the_provider_is_called() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["search", "castle", "--sort", "sideways"]);
    assert_eq!(code(&output), 6);
    assert_eq!(error_of(&value), "FAB_INVALID_INPUT");
    assert!(
        harness.calls().is_empty(),
        "provider must not run for bad input"
    );

    let harness = Harness::new("base");
    let (value, output) = harness.json(&["search", "castle", "--published-since", "last-week"]);
    assert_eq!(code(&output), 6);
    assert_eq!(error_of(&value), "FAB_INVALID_INPUT");

    let harness = Harness::new("base");
    let (value, output) = harness.json(&["search", "castle", "--filter", "nonsense"]);
    assert_eq!(code(&output), 6);
    assert_eq!(error_of(&value), "FAB_INVALID_INPUT");
}

#[test]
fn listing_ids_that_could_escape_a_path_are_rejected() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["download", "../../etc/passwd", "--out", "assets"]);
    assert_eq!(code(&output), 6);
    assert_eq!(error_of(&value), "FAB_INVALID_INPUT");
    assert!(harness.calls().is_empty());
}

#[test]
fn a_broken_config_file_reports_where_and_why() {
    let harness = Harness::new("base").with_project_config("[defaults]\nengien = true\n");
    let (value, output) = harness.json(&["search", "castle"]);
    assert_eq!(code(&output), 6);
    assert_eq!(error_of(&value), "FAB_CONFIG_INVALID");
    assert!(value["error"]["message"]
        .as_str()
        .unwrap()
        .contains("engien"));
}

#[test]
fn an_unknown_provider_lists_the_known_ones() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["--provider", "telepathy", "search", "castle"]);
    assert_eq!(code(&output), 6);
    assert_eq!(error_of(&value), "FAB_CONFIG_INVALID");
    assert!(value["error"]["message"]
        .as_str()
        .unwrap()
        .contains("fabcli"));
}

#[test]
fn usage_errors_follow_the_output_mode() {
    let harness = Harness::new("base");
    // Machine mode: the failure is an envelope on stdout, exit 6.
    let output = harness.run(&["--json", "nonsense-command"]);
    assert_eq!(code(&output), 6);
    let value: serde_json::Value = serde_json::from_str(stdout(&output).trim()).unwrap();
    assert_eq!(value["error"]["code"], "FAB_INVALID_INPUT");
    // Human mode: clap's message on stderr, nothing on stdout, still exit 6.
    let output = harness.run(&["--human", "nonsense-command"]);
    assert_eq!(code(&output), 6);
    assert!(stdout(&output).is_empty());
    assert!(stderr(&output).contains("nonsense-command"));
}

#[test]
fn human_mode_sends_failures_to_stderr_and_leaves_stdout_empty() {
    let harness = Harness::new("base").env("MOCK_FABCLI_FAIL", "auth_required:2");
    let output = harness.run(&["--human", "search", "castle"]);
    assert_eq!(code(&output), 2);
    assert!(stdout(&output).is_empty());
    let text = stderr(&output);
    assert!(text.contains("FAB_AUTH_REQUIRED"), "{text}");
    assert!(text.contains("hint:"), "{text}");
}

#[test]
fn a_lost_keyring_key_asks_for_sign_in_instead_of_reporting_a_crash() {
    let harness = Harness::new("base")
        .env("MOCK_FABCLI_FAIL", "generic:1")
        .env(
            "MOCK_FABCLI_FAIL_MESSAGE",
            "no encryption key in OS keystore for FabCLI. The token may have been written on a different machine or under a different user account. Re-run 'fabcli auth login'.",
        );
    let (value, output) = harness.json(&["search", "castle"]);
    assert_eq!(code(&output), 2, "{value}");
    assert_eq!(value["error"]["code"], "FAB_AUTH_REQUIRED");
    assert!(
        value["error"]["hint"]
            .as_str()
            .unwrap()
            .contains("necturalabs-fab auth login --run"),
        "{value}"
    );
}
