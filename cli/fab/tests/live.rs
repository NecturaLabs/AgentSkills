//! Optional checks against a real, installed and signed-in FabCLI.
//!
//! Ignored by default: they need a Fab account and the network, which CI must
//! never require. Every command here is read-only — nothing is claimed,
//! downloaded or changed. Run them with:
//!
//! ```text
//! cargo test --test live -- --ignored --nocapture
//! ```
//!
//! `NECTURALABS_FAB_FABCLI_PATH` selects a FabCLI other than the one on `PATH`.

use assert_cmd::cargo::cargo_bin;
use serde_json::Value;
use std::process::Command;

fn run(args: &[&str]) -> (i32, Value) {
    let output = Command::new(cargo_bin("necturalabs-fab"))
        .arg("--json")
        .args(args)
        .output()
        .expect("necturalabs-fab runs");
    let stdout = String::from_utf8_lossy(&output.stdout);
    let value: Value = serde_json::from_str(stdout.trim())
        .unwrap_or_else(|err| panic!("not a JSON envelope ({err}): {stdout}"));
    (output.status.code().unwrap_or(-1), value)
}

#[test]
#[ignore = "needs an installed FabCLI; run with --ignored"]
fn doctor_accepts_the_installed_fabcli() {
    let (code, value) = run(&["doctor"]);
    assert_eq!(code, 0);
    let version = value["data"]["checks"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == "provider.version")
        .cloned()
        .expect("provider.version check present");
    eprintln!("provider.version: {version}");
    assert_eq!(
        version["status"], "ok",
        "installed FabCLI is not a supported version"
    );
}

#[test]
#[ignore = "needs a signed-in FabCLI and network; run with --ignored"]
fn search_and_inspect_round_trip_against_the_live_marketplace() {
    let (code, status) = run(&["auth", "status"]);
    assert_eq!(code, 0);
    assert_eq!(
        status["data"]["auth"]["authenticated"], true,
        "sign in first: necturalabs-fab auth login --run"
    );

    let (code, search) = run(&["search", "castle", "--count", "3"]);
    assert_eq!(code, 0, "{search}");
    let results = search["data"]["results"].as_array().unwrap();
    assert!(!results.is_empty(), "live search returned no results");
    let id = results[0]["id"].as_str().unwrap().to_string();
    assert!(results[0]["url"].as_str().unwrap().contains(&id));

    // Licences come from Fab's licence search facets; a castle search's top
    // hits are ordinary Standard License or CC BY listings.
    assert!(
        results.iter().any(|r| r["licenses"].is_array()),
        "no live search result carried a licence: {search}"
    );

    let (code, inspected) = run(&["inspect", &id]);
    assert_eq!(code, 0, "{inspected}");
    assert_eq!(inspected["data"]["asset"]["id"], id.as_str());
    assert_eq!(
        inspected["data"]["asset"]["licenses"], results[0]["licenses"],
        "inspect and search disagree on the licence"
    );
    eprintln!(
        "inspected {} — coverage {}",
        inspected["data"]["asset"]["title"], inspected["data"]["asset"]["coverage"]
    );
}
