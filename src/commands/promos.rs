//! `promos` — Fab's limited-time free listings.
//!
//! Fab regularly makes a few paid listings free for a limited time. Claiming
//! one while it is free keeps it in the library permanently. `promos` lists
//! the current ones; `promos claim` claims those not yet owned. Claiming is an
//! account mutation, approved once for the whole enumerated batch, and every
//! listing is re-checked as free immediately before its own claim.

use super::claim::fetch_claimable;
use super::{validate_listing_id, Ctx};
use crate::approval::{gate, ActionPlan};
use crate::cli::{PromosArgs, PromosCommand};
use crate::error::Result;
use crate::model::Asset;
use crate::output::{cell, license_cell, status_cell, table, Outcome};
use crate::provider::Capabilities;
use crate::query::{FreeMode, SearchQuery};
use serde_json::{json, Value};

/// How many promo listings to request. Fab runs a handful at a time; this
/// leaves room without paging.
const PROMO_PAGE: u32 = 48;

/// Run `promos`.
pub fn run(ctx: &Ctx, args: &PromosArgs) -> Result<Outcome> {
    match &args.command {
        None => list(ctx),
        Some(PromosCommand::Claim {
            listings,
            approve,
            dry_run,
        }) => claim(ctx, listings, *approve, *dry_run),
    }
}

/// Current limited-time free listings, with ownership when the account
/// session allows it, plus any warnings about what could not be determined.
fn current(ctx: &Ctx) -> Result<(Vec<Asset>, Vec<String>)> {
    let mut query = SearchQuery::new();
    query.free = FreeMode::LimitedTime;
    query.count = PROMO_PAGE;
    query.with_ownership = ctx.provider.capabilities().search_ownership;
    let mut warnings = Vec::new();

    let page = match ctx.provider.search(&query) {
        Ok(page) => page,
        Err(err)
            if query.with_ownership
                && matches!(
                    err.code,
                    crate::error::ErrorCode::AuthRequired | crate::error::ErrorCode::AuthExpired
                ) =>
        {
            warnings.push(format!(
                "ownership unknown without the account session (`{}`)",
                super::auth::login_command(crate::provider::LoginScope::Account)
            ));
            query.with_ownership = false;
            ctx.provider.search(&query)?
        }
        Err(err) => return Err(err),
    };

    // The discount filter can also match listings that are free anyway; only
    // a paid listing that is free right now is a promotion. Search rows may
    // not carry the discount itself, so an unknown one is read from the
    // listing detail.
    let mut promos = Vec::new();
    for mut asset in page.assets {
        if asset.price.temporarily_free.is_none() {
            match ctx.provider.listing(&asset.id, false) {
                Ok(detail) if detail.price.temporarily_free == Some(true) => {
                    asset.price.original = asset.price.amount.or(asset.price.original);
                    asset.price.amount = Some(crate::model::Amount::ZERO);
                    asset.price.free = Some(true);
                    asset.price.temporarily_free = Some(true);
                    asset.price.discount_percent = detail.price.discount_percent;
                    asset.price.free_until = detail.price.free_until;
                }
                Ok(_) => {}
                Err(err) => warnings.push(format!(
                    "{}: discount could not be confirmed ({})",
                    asset.id, err.code
                )),
            }
        }
        if asset.price.temporarily_free == Some(true) {
            promos.push(asset);
        }
    }
    warnings.extend(super::license_warning(&promos));
    Ok((promos, warnings))
}

fn summary(asset: &Asset) -> Value {
    json!({
        "id": asset.id,
        "title": asset.title,
        "url": asset.url,
        "owned": asset.owned,
        "listPrice": asset.price.original,
        "currency": asset.price.currency,
        "freeUntil": asset.price.free_until,
        "licenses": asset.licenses,
        "publisher": asset.publisher.as_ref().and_then(|p| p.name.clone()),
    })
}

fn list(ctx: &Ctx) -> Result<Outcome> {
    let (promos, warnings) = current(ctx)?;
    let rows: Vec<Vec<String>> = promos
        .iter()
        .map(|a| {
            vec![
                a.id.clone(),
                cell(a.title.as_deref(), 48),
                status_cell(a.owned, &a.price),
                license_cell(&a.licenses),
            ]
        })
        .collect();
    let human = if rows.is_empty() {
        "No limited-time free listings right now.".to_string()
    } else {
        format!(
            "{}\nClaim the ones you do not own with: necturalabs-fab promos claim --dry-run",
            table(&["LISTING", "TITLE", "STATUS", "LICENCE"], &rows)
        )
    };
    let data = json!({
        "promos": promos.iter().map(summary).collect::<Vec<_>>(),
        "count": promos.len(),
    });
    let mut outcome = Outcome::read("promos", data, human);
    outcome.warnings = warnings;
    Ok(outcome)
}

fn claim(ctx: &Ctx, requested: &[String], approve: bool, dry_run: bool) -> Result<Outcome> {
    if !ctx.provider.capabilities().claim_free {
        return Err(Capabilities::unsupported(ctx.provider.id(), "claiming"));
    }
    let requested = requested
        .iter()
        .map(|id| validate_listing_id(id))
        .collect::<Result<Vec<_>>>()?;
    let (promos, mut warnings) = current(ctx)?;

    // Named ids narrow the batch to what the human approved; an id that is no
    // longer a promotion is skipped, never claimed.
    let mut skipped = Vec::new();
    let candidates: Vec<Asset> = if requested.is_empty() {
        promos
            .into_iter()
            .filter(|a| a.owned != Some(true))
            .collect()
    } else {
        for id in &requested {
            if !promos.iter().any(|p| &p.id == id) {
                skipped
                    .push(json!({"id": id, "reason": "not a current limited-time free listing"}));
            }
        }
        promos
            .into_iter()
            .filter(|a| requested.contains(&a.id) && a.owned != Some(true))
            .collect()
    };

    let ids: Vec<String> = candidates.iter().map(|a| a.id.clone()).collect();
    let effects = candidates
        .iter()
        .map(|a| {
            format!(
                "adds '{}' ({}) to your Fab library at no cost",
                a.title.as_deref().unwrap_or(&a.id),
                a.id
            )
        })
        .collect();
    let plan = ActionPlan::account_mutation("promos claim", ids.join(","), effects);

    if dry_run || candidates.is_empty() {
        let data = json!({
            "dryRun": dry_run,
            "plan": plan,
            "toClaim": candidates.iter().map(summary).collect::<Vec<_>>(),
            "skipped": skipped,
            "approvalPolicy": ctx.config.approval.claim,
        });
        let human = if candidates.is_empty() {
            "Nothing to claim: you own every current limited-time free listing (or there are none)."
                .to_string()
        } else {
            format!(
                "Dry run: would claim {} listing(s): {}. Nothing changed.",
                ids.len(),
                ids.join(", ")
            )
        };
        let mut outcome = Outcome::read("promos claim", data, human).with_action(plan);
        outcome.warnings = warnings;
        return Ok(outcome);
    }

    let plan = gate(plan, ctx.config.approval.claim, approve)?;

    // One listing failing (it stopped being free, a transient error) must not
    // abandon the rest; each result says what happened to it.
    let mut results = Vec::new();
    for asset in &candidates {
        let outcome =
            fetch_claimable(ctx, &asset.id).and_then(|_| ctx.provider.claim_free(&asset.id));
        results.push(match outcome {
            Ok(done) => json!({
                "id": asset.id,
                "title": asset.title,
                "claimed": done.claimed,
                "alreadyOwned": done.already_owned,
            }),
            Err(err) => json!({
                "id": asset.id,
                "title": asset.title,
                "claimed": false,
                "error": err.to_json(),
            }),
        });
    }
    let claimed = results.iter().filter(|r| r["claimed"] == true).count();
    let failed = results.iter().filter(|r| r.get("error").is_some()).count();
    if failed > 0 {
        warnings.push(format!(
            "{failed} listing(s) could not be claimed; see results"
        ));
    }
    let human = format!(
        "Claimed {claimed} of {} limited-time free listing(s).",
        results.len()
    );
    let data = json!({"results": results, "skipped": skipped, "claimed": claimed});
    let mut outcome = Outcome::read("promos claim", data, human).with_action(plan);
    outcome.warnings = warnings;
    Ok(outcome)
}
