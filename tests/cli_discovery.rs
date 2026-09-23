//! `find` and `recommend`: ranking, enrichment and what the agent is told.

mod support;

use support::{code, Harness};

#[test]
fn find_ranks_candidates_and_shows_every_signal() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["find", "dark gothic ruined castle environment"]);
    assert_eq!(code(&output), 0);

    let candidates = value["data"]["candidates"].as_array().unwrap();
    assert!(!candidates.is_empty());
    let first = &candidates[0];
    assert_eq!(first["rank"], 1);
    assert!(first["score"].as_f64().unwrap() > 0.0);
    for signal in [
        "relevance",
        "engine",
        "ownership",
        "price",
        "quality",
        "recency",
        "technical",
    ] {
        assert!(
            first["signals"][signal].is_number(),
            "missing signal {signal}"
        );
    }
    assert!(!first["reasons"].as_array().unwrap().is_empty());
    assert_eq!(value["data"]["interpretation"]["tokens"][0], "dark");
}

#[test]
fn find_is_deterministic() {
    let harness = Harness::new("base");
    let (first, _) = harness.json(&["find", "castle"]);
    let (second, _) = harness.json(&["find", "castle"]);
    assert_eq!(first["data"]["candidates"], second["data"]["candidates"]);
}

#[test]
fn owned_and_free_candidates_outrank_an_equivalent_paid_one() {
    let harness = Harness::new("base");
    let (value, _) = harness.json(&["find", "castle"]);
    let candidates = value["data"]["candidates"].as_array().unwrap();
    let ids: Vec<&str> = candidates
        .iter()
        .map(|c| c["asset"]["id"].as_str().unwrap())
        .collect();
    let paid = ids
        .iter()
        .position(|id| id.starts_with("22222222"))
        .expect("paid candidate present");
    let owned = ids
        .iter()
        .position(|id| id.starts_with("33333333"))
        .expect("owned candidate present");
    assert!(
        owned < paid,
        "owned asset should outrank the paid one: {ids:?}"
    );
}

#[test]
fn find_enriches_only_the_top_candidates() {
    let harness = Harness::new("base");
    let (value, _) = harness.json(&["find", "castle", "--hydrate", "1"]);
    assert_eq!(value["data"]["hydrated"], 1);
    let candidates = value["data"]["candidates"].as_array().unwrap();
    let hydrated: Vec<bool> = candidates
        .iter()
        .map(|c| c["hydrated"].as_bool().unwrap())
        .collect();
    assert!(hydrated[0]);
    assert!(hydrated[1..].iter().all(|h| !h));
    // One listing call and one formats call for the single hydrated candidate.
    assert_eq!(
        harness
            .calls()
            .iter()
            .filter(|c| c.starts_with("listing"))
            .count(),
        1
    );
}

#[test]
fn requiring_an_engine_excludes_incompatible_candidates_with_reasons() {
    let harness = Harness::new("base");
    // Every fixture listing hydrates to an Unreal asset, so requiring Unity
    // must exclude exactly the hydrated ones and keep the unknown remainder.
    let (value, output) = harness.json(&[
        "find",
        "castle",
        "--engine",
        "unity",
        "--require-engine",
        "--hydrate",
        "3",
    ]);
    assert_eq!(code(&output), 0);
    let excluded = value["data"]["excluded"].as_array().unwrap();
    assert_eq!(
        excluded.len(),
        3,
        "all hydrated candidates ship for unreal only"
    );
    assert!(excluded[0]["reason"].as_str().unwrap().contains("unity"));
    assert!(value["data"]["candidates"].as_array().unwrap().is_empty());
}

#[test]
fn unknown_engine_support_is_never_silently_excluded() {
    let harness = Harness::new("base");
    let (value, _) = harness.json(&[
        "find",
        "castle",
        "--engine",
        "unity",
        "--require-engine",
        "--hydrate",
        "0",
    ]);
    assert_eq!(value["data"]["excluded"].as_array().unwrap().len(), 0);
    assert_eq!(value["data"]["candidates"].as_array().unwrap().len(), 3);
}

#[test]
fn a_budget_excludes_paid_candidates_above_it() {
    let harness = Harness::new("base");
    let (value, _) = harness.json(&["find", "castle", "--max-price", "20"]);
    let excluded = value["data"]["excluded"].as_array().unwrap();
    assert_eq!(excluded.len(), 1);
    assert!(excluded[0]["reason"].as_str().unwrap().contains("budget"));
}

#[test]
fn recommend_names_one_candidate_with_a_deterministic_confidence() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["recommend", "ruined castle for unreal"]);
    assert_eq!(code(&output), 0);
    let recommendation = &value["data"]["recommendation"];
    assert!(recommendation["listingId"].is_string());
    assert!(["high", "medium", "low"].contains(&recommendation["confidence"].as_str().unwrap()));
    assert!(!recommendation["why"].as_array().unwrap().is_empty());
    assert!(recommendation["scoreGapToRunnerUp"].is_number());
}

#[test]
fn next_steps_route_an_agent_to_the_right_follow_up() {
    let harness = Harness::new("base");
    let (value, _) = harness.json(&["find", "castle"]);
    let steps = value["data"]["nextSteps"].as_array().unwrap();
    let joined = steps
        .iter()
        .map(|s| s.as_str().unwrap())
        .collect::<Vec<_>>()
        .join(" | ");
    assert!(joined.contains("necturalabs-fab inspect"), "{joined}");
    assert!(
        joined.contains("download") || joined.contains("claim"),
        "{joined}"
    );
}

#[test]
fn ownership_decoration_degrades_to_a_warning_when_signed_out() {
    // search --with-ownership fails with auth_required; find must still rank.
    let harness = Harness::new("base").env("MOCK_FABCLI_FAIL", "auth_required:2");
    let (value, output) = harness.json(&["find", "castle"]);
    // Both attempts fail here, so the command surfaces the auth error rather
    // than pretending it has results.
    assert_eq!(code(&output), 2);
    assert_eq!(value["error"]["code"], "FAB_AUTH_REQUIRED");
}

#[test]
fn owned_only_searches_the_library_and_says_so() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["find", "keep", "--owned-only"]);
    assert_eq!(code(&output), 0);
    let warnings = value["warnings"].as_array().unwrap();
    assert!(warnings
        .iter()
        .any(|w| w.as_str().unwrap().contains("library")));
    assert!(harness.called("library"));
    // Licence lookups are licence-filtered searches; the results themselves
    // must not come from one.
    assert!(!harness
        .calls()
        .iter()
        .any(|c| c.starts_with("search ") && !c.contains("--filter=licenses=")));
}

#[test]
fn search_hydration_applies_engine_version_filtering() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&[
        "search",
        "castle",
        "--hydrate",
        "3",
        "--engine-version",
        "4.27",
    ]);
    assert_eq!(code(&output), 0);
    // Fixtures ship UE_5.4/5.5 only, so every hydrated row is filtered out.
    assert_eq!(value["data"]["returned"], 0);
    let filtered = value["data"]["filteredOut"].as_array().unwrap();
    assert_eq!(filtered.len(), 3);
    assert!(filtered[0]["reason"].as_str().unwrap().contains("4.27"));
}
