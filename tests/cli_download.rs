//! Downloads: where files land, what is refused, and what the caller is told.

mod support;

use support::{code, stderr, stdout, Harness};

const FREE: &str = "11111111-1111-4111-8111-111111111111";

#[test]
fn download_writes_files_and_reports_the_exact_path() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["download", FREE, "--out", "assets/castle"]);
    assert_eq!(code(&output), 0);

    let dir = harness.work().join("assets").join("castle");
    assert!(dir.join("Asset.uasset").is_file(), "asset files must exist");
    assert_eq!(value["data"]["receipt"]["files"], 1);
    assert_eq!(value["data"]["receipt"]["bytes"], 18);
    assert_eq!(value["data"]["outputDir"], dir.display().to_string());
    assert_eq!(value["action"]["class"], "local-write");

    // Metadata from the provider's own sidecar is normalized into ours.
    assert_eq!(value["data"]["receipt"]["title"], "Mock Castle Pack");
    assert_eq!(value["data"]["receipt"]["engineVersions"][0], "UE_5.4");
}

#[test]
fn a_provider_independent_sidecar_records_what_was_downloaded() {
    let harness = Harness::new("base");
    let (value, _) = harness.json(&["download", FREE, "--out", "assets/castle"]);
    let sidecar = value["data"]["sidecar"].as_str().unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(sidecar).unwrap()).unwrap();
    assert_eq!(body["schema"], "necturalabs-fab/asset@1");
    assert_eq!(body["listingId"], FREE);
    assert_eq!(body["provider"], "fabcli");
    assert_eq!(body["engineVersions"][0], "UE_5.4");
}

#[test]
fn the_sidecar_can_be_suppressed() {
    let harness = Harness::new("base");
    let (value, _) = harness.json(&["download", FREE, "--out", "assets/castle", "--no-sidecar"]);
    assert!(value["data"]["sidecar"].is_null());
    assert!(!harness
        .work()
        .join("assets/castle/necturalabs-fab.asset.json")
        .exists());
}

#[test]
fn downloading_twice_into_the_same_directory_is_refused_by_default() {
    let harness = Harness::new("base");
    let (_, first) = harness.json(&["download", FREE, "--out", "assets/castle"]);
    assert_eq!(code(&first), 0);

    let (value, second) = harness.json(&["download", FREE, "--out", "assets/castle"]);
    assert_eq!(code(&second), 10);
    assert_eq!(value["error"]["code"], "FAB_OUTPUT_CONFLICT");
    assert!(value["error"]["hint"]
        .as_str()
        .unwrap()
        .contains("--overwrite force"));

    let (_, forced) = harness.json(&[
        "download",
        FREE,
        "--out",
        "assets/castle",
        "--overwrite",
        "force",
    ]);
    assert_eq!(code(&forced), 0);
}

#[test]
fn require_empty_refuses_a_directory_with_unrelated_content() {
    let harness = Harness::new("base");
    harness.write("assets/castle/README.md", "not ours");
    let (value, output) = harness.json(&[
        "download",
        FREE,
        "--out",
        "assets/castle",
        "--overwrite",
        "require-empty",
    ]);
    assert_eq!(code(&output), 10);
    assert_eq!(value["error"]["code"], "FAB_OUTPUT_NOT_EMPTY");
    assert!(!harness.called("download"));
}

#[test]
fn dry_run_reports_the_plan_and_writes_nothing() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["download", FREE, "--out", "assets/castle", "--dry-run"]);
    assert_eq!(code(&output), 0);
    assert_eq!(value["data"]["dryRun"], true);
    assert_eq!(value["data"]["plan"]["outputDirExists"], false);
    assert_eq!(value["data"]["plan"]["engineVersions"][0], "UE_5.4");
    assert!(
        !harness.work().join("assets/castle").exists(),
        "dry run must not create anything"
    );
    assert!(!harness.called("download"));
}

#[test]
fn the_default_destination_is_one_directory_per_listing() {
    let harness =
        Harness::new("base").with_project_config("[download]\ndirectory = \"Assets/Fab\"\n");
    let (value, output) = harness.json(&["download", FREE]);
    assert_eq!(code(&output), 0);
    let expected = harness.work().join("Assets").join("Fab").join(FREE);
    assert_eq!(value["data"]["outputDir"], expected.display().to_string());
    assert!(expected.join("Asset.uasset").is_file());
}

#[test]
fn a_file_where_the_output_directory_belongs_is_rejected() {
    let harness = Harness::new("base");
    harness.write("assets", "i am a file");
    let (value, output) = harness.json(&["download", FREE, "--out", "assets"]);
    assert_eq!(code(&output), 6);
    assert_eq!(value["error"]["code"], "FAB_INVALID_INPUT");
}

#[test]
fn provider_progress_never_corrupts_the_json_response() {
    let harness = Harness::new("base").env("MOCK_FABCLI_NOISE", "1");
    let (value, output) = harness.json(&["download", FREE, "--out", "assets/castle"]);
    assert_eq!(code(&output), 0);
    assert_eq!(value["ok"], true);
    // In machine mode the provider's chatter is captured, not echoed.
    assert!(
        !stderr(&output).contains("chunk 199"),
        "machine mode must stay quiet on stderr"
    );
}

#[test]
fn human_mode_streams_provider_progress_to_stderr_only() {
    let harness = Harness::new("base").env("MOCK_FABCLI_NOISE", "1");
    let output = harness.run(&["--human", "download", FREE, "--out", "assets/castle"]);
    assert_eq!(code(&output), 0);
    assert!(
        stderr(&output).contains("chunk 199"),
        "progress belongs on stderr"
    );
    let text = stdout(&output);
    assert!(text.contains("Downloaded"), "{text}");
    assert!(!text.contains("chunk"), "progress must not reach stdout");
}

#[test]
fn quiet_mode_suppresses_progress() {
    let harness = Harness::new("base").env("MOCK_FABCLI_NOISE", "1");
    let output = harness.run(&[
        "--human",
        "--quiet",
        "download",
        FREE,
        "--out",
        "assets/castle",
    ]);
    assert_eq!(code(&output), 0);
    assert!(
        !stderr(&output).contains("chunk"),
        "quiet mode must not stream progress"
    );
}

#[test]
fn provider_download_failures_keep_their_classification() {
    let harness = Harness::new("base").env("MOCK_FABCLI_FAIL", "not_owned:2");
    let (value, output) = harness.json(&["download", FREE, "--out", "assets/castle"]);
    assert_eq!(code(&output), 12);
    assert_eq!(value["error"]["code"], "FAB_NOT_OWNED");
    assert!(value["error"]["hint"].as_str().unwrap().contains("claim"));
}

#[test]
fn ambiguous_variants_are_reported_with_the_choices() {
    let harness = Harness::new("base");
    // A real FabCLI attaches the available variants; the mock's generic
    // failure path proves the mapping, the unit tests prove the details.
    let harness = harness.env("MOCK_FABCLI_FAIL", "ambiguous_artifact:6");
    let (value, output) = harness.json(&["download", FREE, "--out", "assets/castle"]);
    assert_eq!(code(&output), 11);
    assert_eq!(value["error"]["code"], "FAB_AMBIGUOUS_VARIANT");
    assert!(value["error"]["hint"]
        .as_str()
        .unwrap()
        .contains("--engine-version"));
}

#[test]
fn a_failed_download_removes_the_empty_directories_it_created() {
    let harness = Harness::new("base").env("MOCK_FABCLI_FAIL", "not_owned:2");
    std::fs::create_dir_all(harness.work().join("assets")).unwrap();
    let (_, output) = harness.json(&["download", FREE, "--out", "assets/new/castle"]);
    assert_eq!(code(&output), 12);
    assert!(
        !harness.work().join("assets/new").exists(),
        "directories created for the failed download are left behind"
    );
    assert!(
        harness.work().join("assets").is_dir(),
        "a directory that existed before must stay"
    );
}
