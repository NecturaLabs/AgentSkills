//! `promos`: Fab's limited-time free listings, and claiming them.

mod support;

use support::{code, Harness};

const PROMO: &str = "33333333-3333-4333-8333-333333333333";
const PERMANENT_FREE: &str = "11111111-1111-4111-8111-111111111111";

/// The base fixtures mark the promo as owned; most promo tests need it unowned.
fn unowned_promo() -> Harness {
    let harness = Harness::new("base");
    let search = std::fs::read_to_string(harness.fixtures().join("search.json"))
        .unwrap()
        .replace("\"owned\": true", "\"owned\": false");
    harness.write_fixture("search.json", &search);
    harness
}

#[test]
fn promos_you_already_own_are_not_claimed() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["promos", "claim", "--approve"]);
    assert_eq!(code(&output), 0);
    assert_eq!(value["data"]["toClaim"].as_array().unwrap().len(), 0);
    assert!(!harness.called("claim"));
}

#[test]
fn promos_lists_only_limited_time_free_listings() {
    let harness = Harness::new("base");
    let (value, output) = harness.json(&["promos"]);
    assert_eq!(code(&output), 0);
    let ids: Vec<&str> = value["data"]["promos"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["id"].as_str().unwrap())
        .collect();
    assert_eq!(
        ids,
        vec![PROMO],
        "permanently free and paid listings are not promos"
    );
    assert!(harness
        .calls()
        .iter()
        .any(|c| c.contains("--filter=min_discount_percentage=100")));
    assert_eq!(value["action"]["class"], "read");
}

#[test]
fn claiming_promos_needs_approval_and_calls_nothing_without_it() {
    let harness = unowned_promo();
    let (value, output) = harness.json(&["promos", "claim"]);
    assert_eq!(code(&output), 8);
    assert_eq!(value["error"]["code"], "FAB_APPROVAL_REQUIRED");
    let plan_targets = value["error"]["details"]["plan"]["target"]
        .as_str()
        .unwrap();
    assert!(plan_targets.contains(PROMO), "{plan_targets}");
    assert!(!harness.called("claim"));
}

#[test]
fn promo_dry_run_lists_what_would_be_claimed() {
    let harness = unowned_promo();
    let (value, output) = harness.json(&["promos", "claim", "--dry-run"]);
    assert_eq!(code(&output), 0);
    assert_eq!(value["data"]["dryRun"], true);
    assert_eq!(value["data"]["toClaim"][0]["id"], PROMO);
    assert_eq!(value["data"]["plan"]["requiresApproval"], true);
    assert!(!harness.called("claim"));
}

#[test]
fn approved_promo_claims_run_through_the_free_check() {
    let harness = unowned_promo();
    let (value, output) = harness.json(&["promos", "claim", "--approve"]);
    assert_eq!(code(&output), 0, "{value}");
    let results = value["data"]["results"].as_array().unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0]["id"], PROMO);
    assert_eq!(results[0]["claimed"], true);
    // The listing was re-read for its price before the claim was sent.
    let calls = harness.calls();
    let listing = calls
        .iter()
        .position(|c| c.starts_with(&format!("listing {PROMO}")));
    let claim = calls
        .iter()
        .position(|c| c.starts_with(&format!("claim {PROMO}")));
    assert!(
        listing.is_some() && claim.is_some() && listing < claim,
        "{calls:?}"
    );
}

#[test]
fn naming_ids_claims_only_those_that_are_still_promos() {
    let harness = unowned_promo();
    let (value, output) = harness.json(&["promos", "claim", "--approve", PERMANENT_FREE, PROMO]);
    assert_eq!(code(&output), 0, "{value}");
    let results = value["data"]["results"].as_array().unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0]["id"], PROMO);
    let skipped = value["data"]["skipped"].as_array().unwrap();
    assert_eq!(skipped[0]["id"], PERMANENT_FREE);
    assert!(!harness
        .calls()
        .iter()
        .any(|c| c.starts_with(&format!("claim {PERMANENT_FREE}"))));
}

#[test]
fn a_promo_that_turned_paid_is_refused_not_claimed() {
    let harness = unowned_promo();
    harness.write_fixture(
        &format!("listing-{PROMO}.json"),
        &format!(r#"{{"uid":"{PROMO}","title":"Ruined Keep Props","isFree":false,"startingPrice":{{"price":19.99,"currencyCode":"USD"}}}}"#),
    );
    let (value, output) = harness.json(&["promos", "claim", "--approve"]);
    assert_eq!(code(&output), 0);
    let results = value["data"]["results"].as_array().unwrap();
    assert_eq!(results[0]["claimed"], false);
    assert_eq!(results[0]["error"]["code"], "FAB_ASSET_NOT_FREE");
    assert!(!harness.called("claim"));
}

/// Live search rows say only `isDiscounted`; the discount itself is in the
/// listing detail, in the account's local currency.
#[test]
fn promos_confirm_the_discount_from_listing_detail_when_search_omits_it() {
    let harness = unowned_promo();
    let search = std::fs::read_to_string(harness.fixtures().join("search.json"))
        .unwrap()
        .replace(
            r#""discountedPrice": 0.0, "discountPercentage": 100, "currencyCode": "USD","#,
            r#""priceTierId": "abc_USD_1999_1701881420881","#,
        );
    assert!(
        search.contains("abc_USD_1999"),
        "fixture rewrite did not apply"
    );
    harness.write_fixture("search.json", &search);
    harness.write_fixture(
        &format!("listing-{PROMO}.json"),
        &format!(
            r#"{{"uid": "{PROMO}", "title": "Ruined Keep Props", "listingType": "3d-model", "isFree": false,
            "startingPrice": {{"price": 60.29, "discountedPrice": 0.0, "effectiveDiscountPercentage": 100,
            "currencyCode": "ILS", "discountEndDate": "2026-10-06T13:59:00Z"}}}}"#
        ),
    );

    let (value, output) = harness.json(&["promos"]);
    assert_eq!(code(&output), 0, "{value}");
    let promos = value["data"]["promos"].as_array().unwrap();
    let ids: Vec<&str> = promos.iter().map(|p| p["id"].as_str().unwrap()).collect();
    assert_eq!(ids, vec![PROMO]);
    assert_eq!(promos[0]["freeUntil"], "2026-10-06T13:59:00Z");
}
