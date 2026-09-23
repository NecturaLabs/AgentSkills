//! Licences: recovered from Fab's licence search facets, reported per listing.

mod support;

use serde_json::Value;
use support::{code, Harness};

const CASTLE: &str = "11111111-1111-4111-8111-111111111111";
const DARK: &str = "22222222-2222-4222-8222-222222222222";
const KEEP: &str = "33333333-3333-4333-8333-333333333333";

/// Make the licence-filtered search for `slug` return `ids`.
fn facet(harness: &Harness, slug: &str, ids: &[&str]) {
    let rows: Vec<String> = ids
        .iter()
        .map(|id| format!(r#"{{"uid": "{id}", "title": "t"}}"#))
        .collect();
    harness.write_fixture(
        &format!("search-license-{slug}.json"),
        &format!(
            r#"{{"results": [{}], "cursors": {{"next": null}}}}"#,
            rows.join(",")
        ),
    );
}

fn result<'a>(value: &'a Value, id: &str) -> &'a Value {
    value["data"]["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["id"] == id)
        .unwrap_or_else(|| panic!("{id} missing from results"))
}

/// Licence lookups the mock saw: licence-filtered searches, and the
/// per-listing searches by seller.
fn licence_lookups(harness: &Harness) -> usize {
    harness
        .calls()
        .iter()
        .filter(|c| c.contains("--filter=licenses=") || c.contains("--filter=seller="))
        .count()
}

fn warnings(value: &Value) -> Vec<String> {
    value["warnings"]
        .as_array()
        .unwrap()
        .iter()
        .map(|w| w.as_str().unwrap().to_string())
        .collect()
}

fn probes_for(harness: &Harness, seller: &str) -> Vec<String> {
    harness
        .calls()
        .into_iter()
        .filter(|c| c.contains(&format!("--filter=seller={seller}")))
        .collect()
}

#[test]
fn search_reports_each_listings_licences_and_one_the_filter_does_not_name() {
    let harness = Harness::new("base");
    facet(&harness, "personal", &[DARK]);
    facet(&harness, "cc-by", &[CASTLE]);

    let (value, output) = harness.json(&["search", "castle"]);
    assert_eq!(code(&output), 0);

    let castle = result(&value, CASTLE);
    assert_eq!(castle["licenses"], serde_json::json!(["CC BY 4.0"]));
    assert_eq!(castle["coverage"]["licenses"], "available");

    let dark = result(&value, DARK);
    assert_eq!(
        dark["licenses"],
        serde_json::json!([
            "Standard License (Personal)",
            "Standard License (Professional)"
        ])
    );

    // Found by an unfiltered search, by no licence filter: a licence the
    // filter does not name, which the caller is told to check.
    let keep = result(&value, KEEP);
    assert!(keep.get("licenses").is_none());
    assert_eq!(keep["coverage"]["licenses"], "available");
    assert!(
        warnings(&value)
            .iter()
            .any(|w| w.starts_with("1 listing(s) use a licence")),
        "{:?}",
        warnings(&value)
    );
}

#[test]
fn only_listings_the_page_left_open_are_asked_about_individually() {
    let harness = Harness::new("base");
    facet(&harness, "personal", &[DARK]);
    facet(&harness, "cc-by", &[CASTLE]);

    harness.json(&["search", "castle"]);

    assert!(probes_for(&harness, "Stonewright").is_empty());
    assert!(probes_for(&harness, "GrimforgeArt").is_empty());
    // Standard first; then CC BY and an unfiltered search together.
    let keep = probes_for(&harness, "KeepWorks");
    assert_eq!(keep.len(), 3, "{keep:?}");
    assert!(keep.iter().all(|c| c.contains("--query=Ruined Keep Props")));
}

#[test]
fn the_personal_tier_alone_establishes_both_standard_tiers() {
    // Fab requires both tiers on every Standard listing, so the Professional
    // filter is never worth a search.
    let harness = Harness::new("base");
    facet(&harness, "personal", &[DARK]);

    let (value, _) = harness.json(&["search", "castle"]);

    assert_eq!(
        result(&value, DARK)["licenses"],
        serde_json::json!([
            "Standard License (Personal)",
            "Standard License (Professional)"
        ])
    );
    assert!(probes_for(&harness, "GrimforgeArt").is_empty());
    assert!(!harness
        .calls()
        .iter()
        .any(|c| c.contains("licenses=professional")));
}

#[test]
fn a_licence_filter_on_the_search_is_not_taken_as_evidence() {
    // Fab may combine licence filters with OR, so the lookup must not stack
    // its own facet on top of the caller's.
    let harness = Harness::new("base");
    facet(&harness, "cc-by", &[CASTLE, KEEP]);
    let (value, _) = harness.json(&["search", "castle", "--license", "cc-by"]);
    assert_eq!(value["data"]["returned"], 2);
    let stacked = harness
        .calls()
        .into_iter()
        .filter(|c| c.matches("--filter=licenses=").count() > 1)
        .collect::<Vec<_>>();
    assert!(stacked.is_empty(), "{stacked:?}");
}

#[test]
fn a_listing_title_cannot_add_parameters_to_its_licence_lookup() {
    // FabCLI forwards --query unencoded, so `&` in a title would start a new
    // marketplace parameter.
    let harness = Harness::new("base");
    let search = std::fs::read_to_string(harness.fixtures().join("search.json")).unwrap();
    harness.write_fixture(
        "search.json",
        &search.replace("Ruined Keep Props", "Keep & Props&licenses=cc-by#x"),
    );

    harness.json(&["search", "castle"]);

    let keep = probes_for(&harness, "KeepWorks");
    assert!(!keep.is_empty());
    for call in keep {
        let query = call
            .split(" --")
            .find_map(|arg| arg.strip_prefix("query="))
            .expect("probe carries a query");
        assert!(!query.contains(['&', '=', '#', '?', '%', '+']), "{query}");
        assert!(query.contains("Keep") && query.contains("Props"), "{query}");
    }
}

#[test]
fn inspect_reports_the_licence_of_one_listing() {
    let harness = Harness::new("base");
    facet(&harness, "cc-by", &[CASTLE]);

    let (value, output) = harness.json(&["inspect", CASTLE]);
    assert_eq!(code(&output), 0);
    assert_eq!(
        value["data"]["asset"]["licenses"],
        serde_json::json!(["CC BY 4.0"])
    );
    assert_eq!(value["data"]["asset"]["coverage"]["licenses"], "available");
}

#[test]
fn hydration_reuses_licences_the_search_already_established() {
    let harness = Harness::new("base");
    facet(&harness, "personal", &[DARK]);
    facet(&harness, "cc-by", &[CASTLE]);

    let (value, _) = harness.json(&["search", "castle", "--hydrate", "3"]);
    assert_eq!(
        result(&value, CASTLE)["licenses"],
        serde_json::json!(["CC BY 4.0"])
    );
    // Two page-wide searches plus three for the one listing left open.
    assert_eq!(licence_lookups(&harness), 5);
}

fn warned_about_licences(value: &Value) -> bool {
    warnings(value).iter().any(|w| w.contains("licen"))
}

#[test]
fn a_failed_licence_lookup_is_reported_not_passed_off_as_no_licence() {
    let harness = Harness::new("base").env("MOCK_FABCLI_LICENSE_FAIL", "network:5");
    let (value, output) = harness.json(&["search", "castle"]);
    assert_eq!(
        code(&output),
        0,
        "a licence failure must not fail the search"
    );
    assert_eq!(
        result(&value, CASTLE)["coverage"]["licenses"],
        "unavailable"
    );
    assert!(warned_about_licences(&value), "{}", value["warnings"]);
}

#[test]
fn a_rate_limit_stops_further_licence_lookups() {
    let harness = Harness::new("base").env("MOCK_FABCLI_LICENSE_FAIL", "rate_limited:4");
    let (value, _) = harness.json(&["search", "castle", "--hydrate", "3"]);
    // The first round is the page-wide one; nothing more is sent after the
    // marketplace asked us to slow down.
    assert_eq!(licence_lookups(&harness), 2);
    assert!(warned_about_licences(&value));
}

#[test]
fn licence_lookups_per_run_are_bounded() {
    let harness = Harness::new("base");
    let rows: Vec<String> = (0..80)
        .map(|i| {
            format!(
                r#"{{"uid": "44444444-4444-4444-8444-{i:012}", "title": "Asset {i}",
                    "user": {{"sellerName": "Seller{i}"}}, "isFree": true}}"#
            )
        })
        .collect();
    harness.write_fixture(
        "search.json",
        &format!(
            r#"{{"results": [{}], "cursors": {{"next": null}}}}"#,
            rows.join(",")
        ),
    );
    let (value, output) = harness.json(&["search", "asset"]);
    assert_eq!(code(&output), 0);
    let lookups = licence_lookups(&harness);
    assert!(
        lookups <= 200,
        "over the documented bound: {lookups} lookups"
    );
    assert!(warned_about_licences(&value));
}

#[test]
fn licences_are_remembered_between_runs() {
    let harness = Harness::new("base");
    facet(&harness, "personal", &[DARK]);
    facet(&harness, "cc-by", &[CASTLE]);
    harness.json(&["search", "castle"]);
    let first = licence_lookups(&harness);
    assert!(harness
        .home()
        .join(".cache/necturalabs-fab/licenses.json")
        .is_file());

    // The page-wide searches still run alongside the page (they cost no
    // time), but no listing is asked about again.
    let (value, _) = harness.json(&["search", "castle"]);
    let per_listing = harness
        .calls()
        .iter()
        .filter(|c| c.contains("--filter=seller="))
        .count();
    assert_eq!(
        per_listing, 3,
        "only the first run's three per-listing searches"
    );
    assert!(licence_lookups(&harness) - first <= 2);
    assert_eq!(
        result(&value, KEEP)["coverage"]["licenses"],
        "available",
        "the remembered verdict is reported"
    );
}

#[test]
fn library_and_ownership_show_licences_already_established() {
    let harness = Harness::new("base");
    facet(&harness, "personal", &[KEEP]);
    facet(&harness, "cc-by", &[CASTLE]);
    harness.json(&["inspect", KEEP]);
    harness.json(&["inspect", CASTLE]);
    let before = licence_lookups(&harness);

    let (library, _) = harness.json(&["library", "keep", "--no-details"]);
    let entry = &library["data"]["results"][0];
    assert_eq!(entry["id"], KEEP);
    assert_eq!(entry["licenses"][0], "Standard License (Personal)");

    // The fixture's ownership rows carry no licence for this listing.
    let (ownership, _) = harness.json(&["ownership", CASTLE]);
    let record = ownership["data"]["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["listingId"] == CASTLE)
        .expect("ownership row");
    assert_eq!(record["licenses"][0], "CC BY 4.0");
    assert_eq!(licence_lookups(&harness), before, "no new lookups");
}

#[test]
fn inspect_reports_the_price_range_across_licence_tiers() {
    let harness = Harness::new("base");
    harness.write_fixture(
        &format!("prices-{DARK}.json"),
        r#"{"offers": [{"currencyCode": "USD", "price": 89.99, "offerId": "a"},
                       {"currencyCode": "USD", "price": 159.99, "offerId": "b"}]}"#,
    );
    let (value, output) = harness.json(&["inspect", DARK]);
    assert_eq!(code(&output), 0);
    let price = &value["data"]["asset"]["price"];
    assert_eq!(price["amount"], "89.99");
    assert_eq!(price["highest"], "159.99");
}

#[test]
fn a_download_records_the_licence_in_its_sidecar() {
    let harness = Harness::new("base");
    facet(&harness, "cc-by", &[CASTLE]);
    let (value, output) = harness.json(&["download", CASTLE, "--out", "assets/castle"]);
    assert_eq!(code(&output), 0, "{value}");
    assert_eq!(value["data"]["receipt"]["licenses"][0], "CC BY 4.0");
    let sidecar = value["data"]["sidecar"].as_str().unwrap();
    let body: Value = serde_json::from_str(&std::fs::read_to_string(sidecar).unwrap()).unwrap();
    assert_eq!(body["licenses"][0], "CC BY 4.0");
}

#[test]
fn the_callers_search_text_cannot_add_marketplace_parameters() {
    let harness = Harness::new("base");
    harness.json(&["search", "castle & dungeon=1"]);
    let main = harness
        .calls()
        .into_iter()
        .find(|c| {
            c.starts_with("search ")
                && !c.contains("--filter=licenses=")
                && !c.contains("--filter=seller=")
        })
        .expect("the page's own search ran");
    assert!(main.contains("--query=castle dungeon 1 "), "{main}");
}

#[test]
fn search_adds_ownership_without_being_asked() {
    // Ownership is the library's membership, read alongside the search.
    let harness = Harness::new("base");
    let (value, _) = harness.json(&["search", "castle"]);
    assert!(harness.called("library"));
    assert_eq!(result(&value, KEEP)["owned"], true);
    assert_eq!(result(&value, CASTLE)["owned"], false);
}
