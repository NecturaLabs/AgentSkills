//! `claim` — add a free asset to the account library.
//!
//! This is the only command that changes the user's account, and the only one
//! that can be refused for approval reasons. Three gates stand in front of the
//! provider call, in this order:
//!
//! 1. the listing's own price, re-checked here and failing closed;
//! 2. the configured approval policy plus the caller's `--approve`;
//! 3. the provider's own free-asset guard.

use super::{validate_listing_id, Ctx};
use crate::approval::{ensure_claimable, gate, ActionPlan};
use crate::cli::ClaimArgs;
use crate::error::Result;
use crate::model::Asset;
use crate::output::{price_cell, Outcome};
use crate::provider::Capabilities;
use serde_json::json;

/// Re-read a listing's price and refuse unless it is unambiguously free.
///
/// Every claim path goes through this before the account-mutating call, so an
/// agent can never reach that call for a paid listing whatever the approval
/// policy says, and a promotion that ended since it was listed is refused.
pub fn fetch_claimable(ctx: &Ctx, listing_id: &str) -> Result<Asset> {
    let asset = ctx.provider.listing(listing_id, false)?;
    ensure_claimable(&asset)?;
    Ok(asset)
}

/// Run `claim`.
pub fn run(ctx: &Ctx, args: &ClaimArgs) -> Result<Outcome> {
    let listing_id = validate_listing_id(&args.listing)?;
    if !ctx.provider.capabilities().claim_free {
        return Err(Capabilities::unsupported(ctx.provider.id(), "claiming"));
    }

    let asset = fetch_claimable(ctx, &listing_id)?;

    let title = asset.title.clone().unwrap_or_else(|| listing_id.clone());
    let mut effects = vec![
        format!("adds '{title}' ({listing_id}) to your Fab library"),
        "does not spend money: the listing is free".to_string(),
    ];
    if asset.price.temporarily_free == Some(true) {
        effects.push("this listing is free only while its 100% discount lasts".to_string());
    }
    let plan = ActionPlan::account_mutation("claim", listing_id.clone(), effects);

    if args.dry_run {
        let data = json!({
            "dryRun": true,
            "plan": plan,
            "asset": {
                "id": asset.id,
                "title": asset.title,
                "price": asset.price,
                "url": asset.url,
            },
            "approvalPolicy": ctx.config.approval.claim,
        });
        let human = format!(
            "Dry run: claiming '{title}' ({listing_id}, {}) would add it to your library. \
Nothing changed.",
            price_cell(&asset.price)
        );
        return Ok(Outcome::read("claim", data, human).with_action(plan));
    }

    let plan = gate(plan, ctx.config.approval.claim, args.approve)?;
    let outcome = ctx.provider.claim_free(&listing_id)?;

    let human = if outcome.already_owned {
        format!("'{title}' was already in your library; nothing changed.")
    } else {
        format!("Claimed '{title}' ({listing_id}) into your library.")
    };
    let data = json!({
        "claim": outcome,
        "asset": {
            "id": asset.id,
            "title": asset.title,
            "price": asset.price,
            "url": asset.url,
        },
    });
    Ok(Outcome::read("claim", data, human).with_action(plan))
}
