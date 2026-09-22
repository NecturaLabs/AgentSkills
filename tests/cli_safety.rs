//! The approval boundary and the money boundary.
//!
//! These are the tests that matter most: they assert what necturalabs-fab refuses
//! to do, and that a refusal happens *before* the provider is invoked.

mod support;

use support::{code, stderr, Harness};

const FREE: &str = "11111111-1111-4111-8111-111111111111";
const PAID: &str = "22222222-2222-4222-8222-222222222222";

#[test]
fn claiming_without_approval_is_refused_and_nothing_is_called() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["claim", FREE]);
    assert_eq!(code(&output), 8);
    assert_eq!(value["error"]["code"], "FAB_APPROVAL_REQUIRED");
    assert_eq!(value["requiresApproval"], true);
    assert_eq!(
        value["error"]["details"]["plan"]["class"],
        "account-mutation"
    );
    assert_eq!(value["error"]["details"]["plan"]["reversible"], false);
    assert!(
        !harness.called("claim"),
        "the provider's claim command must never run without approval"
    );
}

#[test]
fn claiming_with_approval_proceeds() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["claim", FREE, "--approve"]);
    assert_eq!(code(&output), 0);
    assert_eq!(value["data"]["claim"]["claimed"], true);
    assert_eq!(value["action"]["approved"], true);
    assert!(harness.called("claim"));
}

#[test]
fn a_paid_listing_can_never_be_claimed_even_with_approval() {
    let harness = Harness::new("paid");
    let (value, output) = harness.json(&["claim", PAID, "--approve"]);
    assert_eq!(code(&output), 9);
    assert_eq!(value["error"]["code"], "FAB_ASSET_NOT_FREE");
    assert!(
        !harness.called("claim"),
        "no account call may run for a paid listing"
    );
    assert!(value["error"]["message"]
        .as_str()
        .unwrap()
        .contains("89.99"));
}

#[test]
fn an_unknown_price_fails_closed() {
    let harness = Harness::new("base");
    harness.write_fixture(
        "listing.json",
        r#"{"uid":"11111111-1111-4111-8111-111111111111","title":"Mystery"}"#,
    );
    let (value, output) = harness.json(&["claim", FREE, "--approve"]);
    assert_eq!(code(&output), 9);
    assert_eq!(value["error"]["code"], "FAB_ASSET_NOT_FREE");
    assert!(value["error"]["message"]
        .as_str()
        .unwrap()
        .contains("unknown"));
    assert!(!harness.called("claim"));
}

#[test]
fn claim_dry_run_shows_the_plan_and_changes_nothing() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["claim", FREE, "--dry-run"]);
    assert_eq!(code(&output), 0);
    assert_eq!(value["data"]["dryRun"], true);
    assert_eq!(value["data"]["plan"]["requiresApproval"], true);
    assert_eq!(value["data"]["approvalPolicy"], "require");
    assert!(!harness.called("claim"));
}

fn with_user_config(harness: Harness, body: &str) -> Harness {
    let dir = harness.home().join(".config").join("necturalabs-fab");
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("config.toml"), body).unwrap();
    harness
}

#[test]
fn the_approval_policy_can_be_relaxed_or_hardened_in_the_user_config() {
    let allow = with_user_config(Harness::new("base"), "[approval]\nclaim = \"allow\"\n");
    let (value, output) = allow.json(&["claim", FREE]);
    assert_eq!(code(&output), 0, "allow policy runs without --approve");
    assert_eq!(value["data"]["claim"]["claimed"], true);

    let deny = with_user_config(Harness::new("base"), "[approval]\nclaim = \"deny\"\n");
    let (value, output) = deny.json(&["claim", FREE, "--approve"]);
    assert_eq!(code(&output), 8, "deny policy outranks --approve");
    assert_eq!(value["error"]["details"]["policy"], "deny");
    assert!(!deny.called("claim"));
}

#[test]
fn no_command_exposes_a_purchase() {
    let harness = Harness::new("base");
    let help = String::from_utf8_lossy(&harness.run(&["--help"]).stdout).to_lowercase();
    for word in ["purchase", "buy ", "checkout", "payment"] {
        assert!(!help.contains(word), "help advertises '{word}'");
    }
    let output = harness.run(&["purchase", FREE]);
    assert_ne!(code(&output), 0);
    assert!(stderr(&output).contains("unrecognized subcommand"));
}

#[test]
fn read_commands_never_ask_for_approval() {
    let harness = Harness::new("base");
    for args in [
        vec!["search", "castle"],
        vec!["inspect", FREE],
        vec!["library"],
        vec!["ownership", FREE],
    ] {
        let (value, output) = harness.json(&args);
        assert_eq!(code(&output), 0, "{args:?}");
        assert_eq!(value["requiresApproval"], false, "{args:?}");
        assert_eq!(value["action"]["class"], "read", "{args:?}");
    }
}

#[test]
fn provider_stderr_is_redacted_before_it_can_reach_a_log() {
    let harness = Harness::new("base").env("MOCK_FABCLI_USAGE_ERROR", "1");
    let (value, _) = harness.json(&["search", "castle"]);
    let text = serde_json::to_string(&value).unwrap();
    assert!(!text.contains("eyJ"), "no JWT shaped strings may survive");
}

#[test]
fn a_deny_policy_is_reported_as_a_blocker_not_as_a_question() {
    let harness = with_user_config(Harness::new("base"), "[approval]\nclaim = \"deny\"\n");

    let (value, output) = harness.json(&[
        "recommend",
        "medieval castle ruins gothic kit",
        "--prefer-free",
    ]);
    assert_eq!(code(&output), 0, "{value}");
    let recommendation = &value["data"]["recommendation"];
    assert_eq!(
        recommendation["listingId"], FREE,
        "fixture premise: the free kit wins"
    );
    assert_eq!(recommendation["requiresApproval"], false);
    let blockers = recommendation["blockers"].to_string();
    assert!(blockers.contains("deny"), "{blockers}");
    let steps = value["data"]["nextSteps"].to_string();
    assert!(
        !steps.contains("necturalabs-fab claim"),
        "no claim command under deny: {steps}"
    );

    let (value, output) = harness.json(&["capabilities"]);
    assert_eq!(code(&output), 0);
    let claim = value["data"]["commands"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["command"] == "claim")
        .unwrap()
        .clone();
    assert_eq!(claim["policy"], "deny");
    assert_eq!(claim["allowed"], false);
    assert_eq!(claim["requiresApproval"], false);
}
