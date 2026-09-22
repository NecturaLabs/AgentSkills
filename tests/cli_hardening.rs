//! Regression tests for the independent security review's findings.

mod support;

use support::{code, stderr, Harness};

const FREE: &str = "11111111-1111-4111-8111-111111111111";

#[test]
fn a_project_config_cannot_choose_the_provider_executable() {
    let harness = Harness::new("base").with_project_config("[fabcli]\npath = \"./evil.sh\"\n");
    let (value, output) = harness.json(&["search", "castle"]);
    assert_eq!(code(&output), 6);
    assert_eq!(value["error"]["code"], "FAB_CONFIG_INVALID");
    assert!(value["error"]["message"]
        .as_str()
        .unwrap()
        .contains("fabcli.path"));
    assert!(
        harness.calls().is_empty(),
        "no provider may run under a rejected config"
    );
}

#[test]
fn a_project_config_cannot_switch_off_claim_approval() {
    let harness = Harness::new("base").with_project_config("[approval]\nclaim = \"allow\"\n");
    let (value, output) = harness.json(&["claim", FREE]);
    assert_eq!(code(&output), 6);
    assert_eq!(value["error"]["code"], "FAB_CONFIG_INVALID");
    assert!(!harness.called("claim"));
}

#[test]
fn a_project_config_cannot_force_overwrites_or_escape_the_project() {
    for body in [
        "[download]\noverwrite = \"force\"\n",
        "[download]\ndirectory = \"/etc\"\n",
        "[download]\ndirectory = \"../outside\"\n",
        "provider = \"fabcli\"\n[fabcli]\nversion-requirement = \">=0\"\n",
    ] {
        let harness = Harness::new("base").with_project_config(body);
        let (value, output) = harness.json(&["search", "castle"]);
        assert_eq!(code(&output), 6, "{body}");
        assert_eq!(value["error"]["code"], "FAB_CONFIG_INVALID", "{body}");
    }
}

#[test]
fn a_project_config_may_still_set_project_defaults() {
    let harness = Harness::new("base").with_project_config(
        "[defaults]\nengine = \"unreal\"\n[download]\ndirectory = \"Content/Fab\"\n",
    );
    let (_, output) = harness.json(&["search", "castle"]);
    assert_eq!(code(&output), 0);
}

#[cfg(unix)]
#[test]
fn download_never_writes_through_a_planted_symlink() {
    let harness = Harness::new("base");
    let victim = harness.write("victim.txt", "precious");
    std::fs::create_dir_all(harness.work().join("assets")).unwrap();
    std::os::unix::fs::symlink(
        &victim,
        harness.work().join("assets/necturalabs-fab.asset.json"),
    )
    .unwrap();
    std::os::unix::fs::symlink(
        &victim,
        harness.work().join("assets/.necturalabs-fab-write-probe"),
    )
    .unwrap();
    let (_, output) = harness.json(&["download", FREE, "--out", "assets"]);
    assert_ne!(code(&output), 0, "a symlinked sidecar must be refused");
    assert_eq!(std::fs::read_to_string(&victim).unwrap(), "precious");
}

#[test]
fn another_listings_download_is_not_overwritten_by_default() {
    let harness = Harness::new("base");
    harness.write(
        "assets/necturalabs-fab.asset.json",
        r#"{"schema":"necturalabs-fab/asset@1","listingId":"some-other-listing"}"#,
    );
    let (value, output) = harness.json(&["download", FREE, "--out", "assets"]);
    assert_eq!(code(&output), 10);
    assert_eq!(value["error"]["code"], "FAB_OUTPUT_CONFLICT");
    assert!(!harness.called("download"));
}

#[test]
fn listing_ids_that_look_like_flags_never_reach_the_provider() {
    for args in [
        vec!["download", "--out", "assets", "--", "--force"],
        vec!["inspect", "--", "-x"],
        vec!["ownership", "--", "--batch"],
        vec!["claim", "--", "--help"],
    ] {
        let harness = Harness::new("base");
        let (value, output) = harness.json(&args);
        assert_eq!(code(&output), 6, "{args:?}");
        assert_eq!(value["error"]["code"], "FAB_INVALID_INPUT", "{args:?}");
        assert!(harness.calls().is_empty(), "{args:?} reached the provider");
    }
}

#[test]
fn marketplace_rows_with_unsafe_ids_are_dropped() {
    let harness = Harness::new("base");
    harness.write_fixture(
        "search.json",
        r#"{"results":[{"uid":"--force","title":"Evil"},{"uid":"ok-listing","title":"Fine"}],"count":2}"#,
    );
    let (value, _) = harness.json(&["search", "castle", "--hydrate", "5"]);
    let ids: Vec<&str> = value["data"]["results"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["id"].as_str().unwrap())
        .collect();
    assert_eq!(ids, vec!["ok-listing"]);
    assert!(!harness.calls().iter().any(|c| c.contains("--force")));
}

#[test]
fn secrets_in_a_structured_provider_error_are_redacted_without_breaking_it() {
    let harness = Harness::new("base")
        .env("MOCK_FABCLI_FAIL", "auth_required:2")
        .env(
            "MOCK_FABCLI_FAIL_MESSAGE",
            "refresh failed token=abcDEF1234567890abcDEF1234567890",
        );
    let (value, output) = harness.json(&["search", "castle"]);
    assert_eq!(
        code(&output),
        2,
        "the structured error must still be recognised"
    );
    assert_eq!(value["error"]["code"], "FAB_AUTH_REQUIRED");
    let text = serde_json::to_string(&value).unwrap();
    assert!(!text.contains("abcDEF1234567890"), "{text}");
}

#[test]
fn an_expired_session_is_still_reported_as_expired() {
    let harness = Harness::new("base")
        .env("MOCK_FABCLI_FAIL", "auth_required:2")
        .env("MOCK_FABCLI_FAIL_MESSAGE", "Fab session expired. Run login");
    let (value, _) = harness.json(&["search", "castle"]);
    assert_eq!(value["error"]["code"], "FAB_AUTH_EXPIRED");
    assert!(value["error"]["message"]
        .as_str()
        .unwrap()
        .contains("session expired"));
}

#[test]
fn progress_echo_strips_terminal_escape_sequences() {
    let harness = Harness::new("base").env("MOCK_FABCLI_NOISE_ESCAPES", "1");
    let output = harness.run(&["--human", "download", FREE, "--out", "assets"]);
    assert_eq!(code(&output), 0);
    let err = stderr(&output);
    assert!(err.contains("progress 50%"), "{err:?}");
    assert!(
        !err.contains('\u{1b}'),
        "escape reached the terminal: {err:?}"
    );
}

#[test]
fn approval_download_accepts_only_allow_or_deny() {
    let harness = Harness::new("base");
    let user = harness.home().join(".config/necturalabs-fab");
    std::fs::create_dir_all(&user).unwrap();
    std::fs::write(
        user.join("config.toml"),
        "[approval]\ndownload = \"require\"\n",
    )
    .unwrap();
    let (value, output) = harness.json(&["search", "castle"]);
    assert_eq!(code(&output), 6);
    assert_eq!(value["error"]["code"], "FAB_CONFIG_INVALID");
}

#[test]
fn security_settings_are_still_accepted_from_the_user_config() {
    let harness = Harness::new("base");
    let user = harness.home().join(".config/necturalabs-fab");
    std::fs::create_dir_all(&user).unwrap();
    std::fs::write(user.join("config.toml"), "[approval]\nclaim = \"allow\"\n").unwrap();
    let (value, output) = harness.json(&["claim", FREE]);
    assert_eq!(code(&output), 0, "{value}");
}

#[test]
fn provider_error_json_is_not_echoed_as_progress() {
    let harness = Harness::new("base").env("MOCK_FABCLI_FAIL", "auth_required:2");
    let output = harness.run(&["--human", "doctor"]);
    let err = stderr(&output);
    assert!(
        !err.contains("{\"error\""),
        "raw provider JSON leaked: {err}"
    );
}

#[test]
fn usage_errors_are_invalid_input_with_an_envelope_not_exit_2() {
    let harness = Harness::new("base");
    for args in [
        vec!["--json", "search", "--count", "abc"],
        vec!["--json", "no-such-command"],
        vec!["--json", "find", "castle", "--max-price", "cheap"],
    ] {
        let output = harness.run(&args);
        assert_eq!(
            code(&output),
            6,
            "{args:?} must not collide with the auth exit code"
        );
        let stdout = String::from_utf8_lossy(&output.stdout);
        let value: serde_json::Value = serde_json::from_str(stdout.trim())
            .unwrap_or_else(|_| panic!("{args:?}: no envelope in {stdout:?}"));
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], "FAB_INVALID_INPUT");
    }
    assert!(harness.calls().is_empty());
}

#[test]
fn help_and_version_still_exit_zero() {
    let harness = Harness::new("base");
    assert_eq!(code(&harness.run(&["--help"])), 0);
    assert_eq!(code(&harness.run(&["--json", "--version"])), 0);
    assert_eq!(code(&harness.run(&["search", "--help"])), 0);
}

#[test]
fn an_explicit_config_file_does_not_discard_environment_overrides() {
    let harness = Harness::new("base");
    let config = harness.write("custom.toml", "[defaults]\nengine = \"unity\"\n");
    let harness = harness.env("NECTURALABS_FAB_ENGINE", "godot");
    let (value, output) = harness.json(&["--config", config.to_str().unwrap(), "config", "show"]);
    assert_eq!(code(&output), 0);
    assert_eq!(
        value["data"]["config"]["defaults"]["engine"], "godot",
        "env must beat the file"
    );
    assert!(
        value["data"]["config"]["fabcli"]["path"]
            .as_str()
            .unwrap()
            .contains("mock-fabcli"),
        "env provider path must survive --config"
    );
}

#[test]
fn find_marks_hydration_by_what_was_fetched_not_by_rank() {
    let harness = Harness::new("base");
    // The owned promo (third in provider order) outranks the first result, so
    // rank order and provider order differ.
    let (value, _) = harness.json(&["find", "keep props", "--hydrate", "1"]);
    for candidate in value["data"]["candidates"].as_array().unwrap() {
        let detailed = candidate["asset"]["detailLevel"] == "detail";
        assert_eq!(candidate["hydrated"], detailed, "{candidate}");
    }
}

#[test]
fn library_entries_with_unsafe_ids_are_dropped() {
    let harness = Harness::new("base");
    harness.write_fixture(
        "library.json",
        r#"{"cursors":{"next":null},"results":[
            {"assetId":"a","assetNamespace":"n","title":"Evil","description":"","url":"","distributionMethod":"ASSET_PACK","source":"fab","categories":[],"customAttributes":[{"ListingIdentifier":"--force"}],"images":[],"projectVersions":[]},
            {"assetId":"b","assetNamespace":"n","title":"Fine","description":"","url":"","distributionMethod":"ASSET_PACK","source":"fab","categories":[],"customAttributes":[{"ListingIdentifier":"ok-listing"}],"images":[],"projectVersions":[]}
        ]}"#,
    );
    let (value, _) = harness.json(&["library"]);
    let ids: Vec<&str> = value["data"]["results"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["id"].as_str().unwrap())
        .collect();
    assert_eq!(ids, vec!["ok-listing"]);
}

#[test]
fn a_missing_account_session_tells_the_agent_exactly_what_to_ask_for() {
    let harness = Harness::new("base")
        .env("MOCK_FABCLI_FAIL", "auth_required:2")
        .env(
            "MOCK_FABCLI_FAIL_MESSAGE",
            "claim needs a Fab session. Run 'fabcli auth login' first.",
        );
    let (value, output) = harness.json(&["ownership", FREE]);
    assert_eq!(code(&output), 2);
    assert_eq!(value["error"]["details"]["session"], "account");
    assert!(value["error"]["hint"]
        .as_str()
        .unwrap()
        .contains("auth login --run --account"));
    assert!(
        !value["error"]["message"]
            .as_str()
            .unwrap()
            .contains("fabcli auth login"),
        "agents must never be pointed at the provider"
    );
}

#[test]
fn auth_login_without_a_terminal_describes_instead_of_starting() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["auth", "login", "--run"]);
    assert_eq!(code(&output), 0);
    assert_eq!(value["data"]["ran"], false);
    assert_eq!(
        value["data"]["loginCommand"],
        "necturalabs-fab auth login --run"
    );
    assert!(
        !harness.called("auth"),
        "no sign-in may start without a terminal"
    );
    let (value, _) = harness.json(&["auth", "login", "--run", "--account"]);
    assert_eq!(value["data"]["scope"], "account");
}

#[test]
fn a_broken_config_does_not_block_doctor_or_its_own_repair() {
    let harness = Harness::new("base").with_project_config("[defaults]\nengien = true\n");
    let (value, output) = harness.json(&["doctor"]);
    assert_eq!(code(&output), 0);
    let check = value["data"]["checks"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == "config.valid")
        .cloned()
        .expect("config.valid check");
    assert_eq!(check["status"], "fail");
    let (_, output) = harness.json(&["config", "init", "--project", "--force"]);
    assert_eq!(code(&output), 0, "the repair command must run");
    let (_, output) = harness.json(&["search", "castle"]);
    assert_eq!(code(&output), 0, "the rewritten file must load");
}

#[test]
fn failure_envelopes_carry_the_action_and_the_provider() {
    let harness = Harness::new("base").env("MOCK_FABCLI_FAIL", "auth_required:2");
    let (value, _) = harness.json(&["claim", FREE, "--approve"]);
    assert_eq!(value["action"]["class"], "account-mutation");
    assert_eq!(value["meta"]["provider"], "fabcli");
}
