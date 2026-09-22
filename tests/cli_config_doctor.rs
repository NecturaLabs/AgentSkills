//! Configuration precedence, diagnostics and skill status.

mod support;

use support::{code, Harness};

#[test]
fn configuration_precedence_is_flags_then_env_then_project_then_user() {
    // user config
    let harness = Harness::new("base");
    let user_dir = harness.home().join(".config").join("necturalabs-fab");
    std::fs::create_dir_all(&user_dir).unwrap();
    std::fs::write(
        user_dir.join("config.toml"),
        "[defaults]\nengine = \"unity\"\ncount = 11\n",
    )
    .unwrap();

    let (value, output) = harness.json(&["config", "show"]);
    assert_eq!(code(&output), 0);
    assert_eq!(value["data"]["config"]["defaults"]["engine"], "unity");
    assert_eq!(value["data"]["config"]["defaults"]["count"], 11);

    // project config overrides one field, leaves the rest
    std::fs::write(
        harness.work().join(".necturalabs-fab.toml"),
        "[defaults]\nengine = \"unreal\"\n",
    )
    .unwrap();
    let (value, _) = harness.json(&["config", "show"]);
    assert_eq!(value["data"]["config"]["defaults"]["engine"], "unreal");
    assert_eq!(value["data"]["config"]["defaults"]["count"], 11);

    // env beats both
    let harness = harness.env("NECTURALABS_FAB_ENGINE", "godot");
    let (value, _) = harness.json(&["config", "show"]);
    assert_eq!(value["data"]["config"]["defaults"]["engine"], "godot");

    // and a flag beats everything
    let (value, _) = harness.json(&["--provider", "fabcli", "config", "show"]);
    assert_eq!(value["data"]["config"]["provider"], "fabcli");
}

#[test]
fn config_layers_are_reported_with_their_paths() {
    let harness = Harness::new("base").with_project_config("[defaults]\nengine = \"unreal\"\n");
    let (value, _) = harness.json(&["config", "show"]);
    let layers = value["data"]["layers"].as_array().unwrap();
    let names: Vec<&str> = layers
        .iter()
        .map(|l| l["layer"].as_str().unwrap())
        .collect();
    assert_eq!(names, vec!["defaults", "user", "project", "env"]);
    let project = layers.iter().find(|l| l["layer"] == "project").unwrap();
    assert_eq!(project["applied"], true);
    assert!(project["path"]
        .as_str()
        .unwrap()
        .ends_with(".necturalabs-fab.toml"));
}

#[test]
fn config_init_writes_a_template_that_parses() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["config", "init", "--project"]);
    assert_eq!(code(&output), 0);
    let path = value["data"]["written"].as_str().unwrap();
    let body = std::fs::read_to_string(path).unwrap();
    assert!(body.contains("[defaults]"));
    assert!(
        !body.contains("[approval]"),
        "a project template must not offer keys the project layer refuses"
    );

    // A second run refuses rather than clobbering.
    let (value, output) = harness.json(&["config", "init", "--project"]);
    assert_eq!(code(&output), 10);
    assert_eq!(value["error"]["code"], "FAB_OUTPUT_CONFLICT");

    let (_, output) = harness.json(&["config", "init", "--project", "--force"]);
    assert_eq!(code(&output), 0);
}

#[test]
fn a_project_config_is_found_from_a_subdirectory() {
    let harness = Harness::new("base").with_project_config("[defaults]\nengine = \"godot\"\n");
    std::fs::create_dir_all(harness.work().join("src").join("deep")).unwrap();
    let mut command = std::process::Command::new(assert_cmd::cargo::cargo_bin("necturalabs-fab"));
    command
        .args(["--json", "config", "show"])
        .current_dir(harness.work().join("src").join("deep"))
        .env("HOME", harness.home())
        .env("XDG_CONFIG_HOME", harness.home().join(".config"))
        .env(
            "NECTURALABS_FAB_FABCLI_PATH",
            assert_cmd::cargo::cargo_bin("mock-fabcli"),
        )
        .env("MOCK_FABCLI_DIR", harness.fixtures())
        .env_remove("NECTURALABS_FAB_ENGINE");
    let output = command.output().unwrap();
    let value: serde_json::Value = serde_json::from_slice(&output.stdout).expect("json envelope");
    assert_eq!(value["data"]["config"]["defaults"]["engine"], "godot");
}

#[test]
fn doctor_reports_a_healthy_installation() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["doctor"]);
    assert_eq!(code(&output), 0);
    let checks = value["data"]["checks"].as_array().unwrap();
    let ids: Vec<&str> = checks.iter().map(|c| c["id"].as_str().unwrap()).collect();
    for expected in [
        "necturalabs-fab.version",
        "provider.selected",
        "provider.executable",
        "provider.version",
        "auth.reads",
        "auth.account-actions",
        "config.layers",
        "download.directory",
    ] {
        assert!(
            ids.contains(&expected),
            "missing check {expected} in {ids:?}"
        );
    }
    assert_eq!(value["data"]["provider"]["version"], "0.1.0");
    assert_eq!(value["data"]["provider"]["capabilities"]["purchase"], false);
}

#[test]
fn doctor_still_reports_when_the_provider_is_missing() {
    let harness = Harness::new("base").env("NECTURALABS_FAB_FABCLI_PATH", "/nonexistent/fabcli");
    let (value, output) = harness.json(&["doctor"]);
    assert_eq!(code(&output), 0, "doctor diagnoses, it does not fail");
    assert_eq!(value["data"]["status"], "fail");
    let provider_check = value["data"]["checks"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == "provider.executable")
        .unwrap()
        .clone();
    assert_eq!(provider_check["status"], "fail");
    assert!(provider_check["hint"].is_string());
}

#[test]
fn doctor_warns_when_signed_out() {
    let harness = Harness::new("base").env("MOCK_FABCLI_FAIL", "auth_required:2");
    let (value, output) = harness.json(&["doctor"]);
    assert_eq!(code(&output), 0);
    let auth = value["data"]["checks"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == "auth.reads")
        .unwrap()
        .clone();
    assert_eq!(auth["status"], "warn");
    assert!(auth["hint"].as_str().unwrap().contains("auth login"));
}

#[test]
fn doctor_output_contains_no_secrets() {
    let harness = Harness::new("base");
    let (value, _) = harness.json(&["doctor"]);
    let text = serde_json::to_string(&value).unwrap().to_lowercase();
    for forbidden in ["token", "cookie", "sessionid", "password", "bearer"] {
        assert!(!text.contains(forbidden), "doctor mentioned {forbidden}");
    }
}

#[test]
fn skill_status_reads_marketplace_installs_for_both_harnesses() {
    let harness = Harness::new("base");
    let plugins = harness.home().join(".claude").join("plugins");
    std::fs::create_dir_all(&plugins).unwrap();
    std::fs::write(
        plugins.join("installed_plugins.json"),
        r#"{"version":2,"plugins":{"necturalabs-fab@necturalabs-fab":[{"installPath":"/c","version":"0.1.0"}]}}"#,
    )
    .unwrap();
    let codex = harness.home().join(".codex");
    std::fs::create_dir_all(codex.join("plugins/cache/necturalabs-fab/necturalabs-fab/0.1.0"))
        .unwrap();
    std::fs::write(
        codex.join("config.toml"),
        "[plugins.\"necturalabs-fab@necturalabs-fab\"]\nenabled = true\n",
    )
    .unwrap();
    let harness = harness.env("CODEX_HOME", codex.to_str().unwrap());

    let (value, output) = harness.json(&["skill", "status"]);
    assert_eq!(code(&output), 0);
    let harnesses = value["data"]["harnesses"].as_array().unwrap();
    assert!(
        harnesses.iter().all(|h| h["installed"] == true),
        "{harnesses:?}"
    );
}

#[test]
fn skill_status_warns_about_a_hand_placed_duplicate() {
    let harness = Harness::new("base");
    std::fs::create_dir_all(harness.home().join(".agents/skills/necturalabs-fab")).unwrap();
    let (value, _) = harness.json(&["skill", "status"]);
    let warnings = value["warnings"].as_array().unwrap();
    assert!(warnings
        .iter()
        .any(|w| w.as_str().unwrap().contains(".agents")));
}

#[test]
fn doctor_warns_when_the_installed_skill_is_from_another_release() {
    let harness = Harness::new("base");
    let plugins = harness.home().join(".claude").join("plugins");
    std::fs::create_dir_all(&plugins).unwrap();
    std::fs::write(
        plugins.join("installed_plugins.json"),
        r#"{"version":2,"plugins":{"necturalabs-fab@necturalabs-fab":[{"installPath":"/c","version":"0.0.9"}]}}"#,
    )
    .unwrap();

    let (value, _) = harness.json(&["doctor"]);
    let check = value["data"]["checks"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == "skill.claude-code")
        .unwrap()
        .clone();
    assert_eq!(check["status"], "warn", "{check}");
    assert!(
        check["detail"].as_str().unwrap().contains("0.0.9"),
        "{check}"
    );
}
