//! The machine contract: envelope shape, stdout cleanliness, exit codes.

mod support;

use support::{code, stderr, stdout, Harness};

#[test]
fn search_returns_normalized_assets_in_one_clean_json_line() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["search", "ruined castle"]);
    assert_eq!(code(&output), 0);
    assert_eq!(value["ok"], true);
    assert_eq!(value["command"], "search");
    assert_eq!(value["requiresApproval"], false);
    assert_eq!(value["meta"]["provider"], "fabcli");

    let results = value["data"]["results"].as_array().unwrap();
    assert_eq!(results.len(), 3);
    let first = &results[0];
    assert_eq!(first["id"], "11111111-1111-4111-8111-111111111111");
    assert_eq!(first["price"]["free"], true);
    assert_eq!(first["owned"], false);
    assert_eq!(first["publisher"]["name"], "Stonewright");
    assert_eq!(
        first["url"],
        "https://www.fab.com/listings/11111111-1111-4111-8111-111111111111"
    );
    assert_eq!(value["data"]["nextCursor"], "cD0y");

    // The limited-time promo is free now but flagged as temporary.
    let promo = &results[2];
    assert_eq!(promo["price"]["free"], true);
    assert_eq!(promo["price"]["temporarilyFree"], true);
    // Money is an exact decimal string, never a binary float.
    assert_eq!(promo["price"]["original"], "19.99");
    assert_eq!(promo["price"]["amount"], "0.00");
}

#[test]
fn raw_provider_payloads_are_opt_in() {
    let harness = Harness::new("base");
    let (plain, _) = harness.json(&["search", "castle"]);
    assert!(plain["data"]["results"][0].get("raw").is_none());

    let (raw, _) = harness.json(&["--raw", "search", "castle"]);
    assert!(raw["data"]["results"][0]["raw"].is_object());
}

#[test]
fn human_mode_prints_a_table_and_no_json() {
    let harness = Harness::new("base");
    let output = harness.run(&["--human", "search", "castle"]);
    assert_eq!(code(&output), 0);
    let text = stdout(&output);
    assert!(text.contains("LISTING"), "{text}");
    assert!(text.contains("Medieval Castle Ruins"), "{text}");
    assert!(!text.contains("\"ok\""), "human mode must not emit JSON");
    assert!(!text.contains('\u{1b}'), "no ANSI escapes");
}

#[test]
fn marketplace_text_cannot_smuggle_escapes_or_newlines_into_output() {
    let harness = Harness::new("base");
    let (value, _) = harness.json(&["inspect", "11111111-1111-4111-8111-111111111111"]);
    let description = value["data"]["asset"]["description"].as_str().unwrap();
    assert!(!description.contains('\u{1b}'), "{description}");
    assert!(!description.contains('\n'));
    assert!(description.contains("modular ruined castle kit"));
}

#[test]
fn inspect_merges_formats_engines_and_parsed_technical_data() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["inspect", "11111111-1111-4111-8111-111111111111"]);
    assert_eq!(code(&output), 0);
    let asset = &value["data"]["asset"];
    assert_eq!(asset["engines"][0], "unreal");
    assert_eq!(asset["engineVersions"][0], "UE_5.4");
    assert_eq!(asset["platforms"][0], "Linux");
    assert_eq!(asset["technical"]["triangles"], 184000);
    assert_eq!(asset["technical"]["vertices"], 96500);
    assert_eq!(asset["technical"]["lods"], 3);
    assert_eq!(asset["technical"]["rigged"], false);
    assert_eq!(asset["technical"]["skeletal"], false);
    assert_eq!(asset["technical"]["source"], "parsed-text");
    assert_eq!(asset["coverage"]["formats"], "available");
    assert_eq!(asset["detailLevel"], "detail");
}

#[test]
fn inspect_without_formats_says_so_rather_than_implying_no_engines() {
    let harness = Harness::new("base");
    let (value, _) = harness.json(&[
        "inspect",
        "11111111-1111-4111-8111-111111111111",
        "--no-formats",
    ]);
    let asset = &value["data"]["asset"];
    assert_eq!(asset["coverage"]["formats"], "not-requested");
    assert!(asset.get("engines").is_none());
}

#[test]
fn ownership_maps_licences_and_entitlements() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&[
        "ownership",
        "11111111-1111-4111-8111-111111111111",
        "33333333-3333-4333-8333-333333333333",
    ]);
    assert_eq!(code(&output), 0);
    let results = value["data"]["results"].as_array().unwrap();
    assert_eq!(results.len(), 2);
    assert_eq!(results[0]["owned"], false);
    assert_eq!(results[1]["owned"], true);
    assert_eq!(results[1]["entitlementId"], "ent-33");
    assert_eq!(results[1]["licenses"][0], "Standard License");
    assert_eq!(value["data"]["owned"], 1);
}

#[test]
fn library_filters_client_side_by_text_and_engine_version() {
    let harness = Harness::new("base");
    let (all, _) = harness.json(&["library"]);
    assert_eq!(all["data"]["returned"], 2);

    let (filtered, _) = harness.json(&["library", "keep"]);
    assert_eq!(filtered["data"]["returned"], 1);
    assert_eq!(filtered["data"]["results"][0]["title"], "Ruined Keep Props");

    let (by_version, _) = harness.json(&["library", "--engine-version", "5.4"]);
    assert_eq!(by_version["data"]["returned"], 1);
    assert_eq!(
        by_version["data"]["results"][0]["engineVersions"][0],
        "UE_5.4"
    );
}

#[test]
fn library_entries_are_reported_as_owned() {
    let harness = Harness::new("base");
    let (value, _) = harness.json(&["library"]);
    for entry in value["data"]["results"].as_array().unwrap() {
        assert_eq!(entry["owned"], true);
    }
}

#[test]
fn version_and_help_work_without_a_provider() {
    let harness = Harness::new("base").env("NECTURALABS_FAB_FABCLI_PATH", "/nonexistent/fabcli");
    let output = harness.run(&["--version"]);
    assert_eq!(code(&output), 0);
    assert!(stdout(&output).contains("necturalabs-fab"));

    let output = harness.run(&["--help"]);
    assert_eq!(code(&output), 0);
    assert!(stdout(&output).contains("search"));
    assert!(stderr(&output).is_empty());
}

#[test]
fn capabilities_never_advertise_purchasing() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["capabilities"]);
    assert_eq!(code(&output), 0);
    assert_eq!(value["data"]["capabilities"]["purchase"], false);
    assert_eq!(value["data"]["monetaryActions"]["supported"], false);
    let claim = value["data"]["commands"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["command"] == "claim")
        .unwrap()
        .clone();
    assert_eq!(claim["actionClass"], "account-mutation");
    assert_eq!(claim["requiresApproval"], true);
}

#[test]
fn auth_status_reports_both_sessions_without_leaking_anything() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["auth", "status"]);
    assert_eq!(code(&output), 0);
    assert_eq!(value["data"]["auth"]["authenticated"], true);
    assert_eq!(value["data"]["auth"]["accountActionsAvailable"], true);
    assert_eq!(value["data"]["auth"]["accountSessionDaysRemaining"], 88);
    let text = serde_json::to_string(&value).unwrap();
    for forbidden in ["token", "cookie", "sessionid", "Bearer"] {
        assert!(
            !text.to_lowercase().contains(&forbidden.to_lowercase()),
            "auth output mentioned {forbidden}"
        );
    }
}

#[test]
fn auth_login_prints_the_command_instead_of_opening_a_window() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["auth", "login"]);
    assert_eq!(code(&output), 0);
    assert_eq!(value["data"]["ran"], false);
    assert!(value["data"]["loginCommand"]
        .as_str()
        .unwrap()
        .contains("auth login"));
    assert!(
        !harness.called("auth"),
        "login must not run anything by itself"
    );
}

/// Fab's library endpoint repeats the title as the description; the real one
/// is on the listing. A short result fetches it without being asked.
fn library_with_title_as_description() -> Harness {
    let harness = Harness::new("base");
    let library = std::fs::read_to_string(harness.fixtures().join("library.json"))
        .unwrap()
        .replace("\"Props for ruined keeps.\"", "\"Ruined Keep Props\"");
    assert!(
        library.contains("\"description\": \"Ruined Keep Props\""),
        "fixture rewrite did not apply"
    );
    harness.write_fixture("library.json", &library);
    harness.write_fixture(
        "listing-33333333-3333-4333-8333-333333333333.json",
        r#"{"uid": "33333333-3333-4333-8333-333333333333", "title": "Ruined Keep Props",
            "description": "Forty modular props for ruined keeps, with LODs.", "listingType": "3d-model"}"#,
    );
    harness
}

#[test]
fn library_fetches_real_descriptions_for_a_short_result() {
    let harness = library_with_title_as_description();
    let (value, output) = harness.json(&["library", "keep"]);
    assert_eq!(code(&output), 0, "{value}");
    let entry = &value["data"]["results"][0];
    assert_eq!(
        entry["description"],
        "Forty modular props for ruined keeps, with LODs."
    );
    assert_eq!(
        entry["url"],
        "https://www.fab.com/listings/33333333-3333-4333-8333-333333333333"
    );
}

#[test]
fn library_never_passes_the_title_off_as_a_description() {
    let harness = library_with_title_as_description();
    let (value, output) = harness.json(&["library", "keep", "--no-details"]);
    assert_eq!(code(&output), 0, "{value}");
    assert_eq!(value["data"]["results"][0]["title"], "Ruined Keep Props");
    assert!(
        value["data"]["results"][0].get("description").is_none(),
        "{value}"
    );
    assert!(!harness.called("listing"));
}

#[test]
fn library_human_view_shows_title_link_description_and_download_command() {
    let harness = library_with_title_as_description();
    let output = harness.run(&["--human", "library", "keep"]);
    assert_eq!(code(&output), 0);
    let text = stdout(&output);
    for expected in [
        "Ruined Keep Props",
        "https://www.fab.com/listings/33333333-3333-4333-8333-333333333333",
        "Forty modular props for ruined keeps, with LODs.",
        "necturalabs-fab download 33333333-3333-4333-8333-333333333333",
    ] {
        assert!(text.contains(expected), "missing {expected:?} in:\n{text}");
    }
}

#[test]
fn library_pages_through_every_entry() {
    let harness = Harness::new("base");
    let (first, output) = harness.json(&["library", "--limit", "1", "--no-details"]);
    assert_eq!(code(&output), 0, "{first}");
    assert_eq!(first["data"]["page"], 1);
    assert_eq!(first["data"]["pages"], 2);
    assert_eq!(first["data"]["matched"], 2);
    assert_eq!(first["data"]["nextPage"], 2);
    let (second, _) = harness.json(&["library", "--limit", "1", "--page", "2", "--no-details"]);
    assert_eq!(second["data"]["returned"], 1);
    assert!(second["data"]["nextPage"].is_null());
    assert_ne!(
        first["data"]["results"][0]["id"],
        second["data"]["results"][0]["id"]
    );

    let text = stdout(&harness.run(&["--human", "library", "--limit", "1", "--no-details"]));
    let next = text
        .lines()
        .find_map(|l| l.split_once("Next: ").map(|(_, c)| c))
        .unwrap_or_else(|| panic!("no next-page command in:\n{text}"));
    assert!(next.starts_with("necturalabs-fab library"), "{next}");
    assert!(
        next.contains("--limit 1") && next.ends_with("--page 2"),
        "{next}"
    );
}

#[test]
fn library_finds_an_entry_by_its_listing_id_or_a_prefix_of_it() {
    let harness = Harness::new("base");
    for query in ["44444444-4444-4444-8444-444444444444", "44444444"] {
        let (value, output) = harness.json(&["library", query, "--no-details"]);
        assert_eq!(code(&output), 0, "{value}");
        assert_eq!(value["data"]["matched"], 1, "{query}: {value}");
        assert_eq!(value["data"]["results"][0]["title"], "Sci-Fi Corridor Kit");
    }
}
