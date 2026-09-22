//! `search` — deterministic marketplace retrieval.

use super::{apply_client_filters, build_query, hydrate, Ctx};
use crate::cli::SearchArgs;
use crate::error::Result;
use crate::output::{cell, owned_cell, price_cell, table, Outcome};
use serde_json::json;

/// Run `search`.
pub fn run(ctx: &Ctx, args: &SearchArgs) -> Result<Outcome> {
    let mut query = build_query(args.query.clone(), &args.filters, &ctx.config)?;
    query.cursor = args.cursor.clone();
    query.validate()?;

    let mut warnings = Vec::new();

    // Owned-only is a library intersection, not a marketplace filter: the
    // search index has no notion of who owns what.
    let (mut assets, total, next_cursor) = if query.owned_only {
        let (assets, library_total) = super::library::fetch_filtered(
            ctx,
            query.text.as_deref(),
            query.engine.as_ref(),
            query.engine_version.as_deref(),
            Some(query.count as usize),
        )?;
        warnings.push(format!(
            "--owned-only searched the {library_total}-entry library, not the marketplace"
        ));
        let count = assets.len() as u64;
        (assets, Some(count), None)
    } else {
        if query.with_ownership && !ctx.provider.capabilities().search_ownership {
            warnings.push("provider cannot decorate results with ownership".to_string());
        }
        let page = ctx.provider.search(&query)?;
        (page.assets, page.total, page.next_cursor)
    };

    let hydrate_limit = (args.hydrate as usize).min(assets.len());
    warnings.extend(hydrate(ctx, &mut assets, hydrate_limit));

    // Only assets whose metadata was actually fetched can be filtered on it.
    let (kept, dropped) = apply_client_filters(assets, &query);
    let filtered_out: Vec<_> = dropped
        .iter()
        .map(|(id, reason)| json!({"id": id, "reason": reason}))
        .collect();

    let data = json!({
        "query": query,
        "results": kept,
        "returned": kept.len(),
        "total": total,
        "nextCursor": next_cursor,
        "hydrated": hydrate_limit,
        "filteredOut": filtered_out,
    });

    let rows: Vec<Vec<String>> = kept
        .iter()
        .map(|asset| {
            vec![
                asset.id.clone(),
                cell(asset.title.as_deref(), 44),
                price_cell(&asset.price),
                owned_cell(asset.owned),
                asset
                    .rating
                    .average
                    .map(|r| format!("{r:.1}"))
                    .unwrap_or_else(|| "-".into()),
                cell(asset.publisher.as_ref().and_then(|p| p.name.as_deref()), 24),
            ]
        })
        .collect();

    let human = if rows.is_empty() {
        "No results.".to_string()
    } else {
        let mut text = table(
            &["LISTING", "TITLE", "PRICE", "OWNED", "RATING", "SELLER"],
            &rows,
        );
        text.push_str(&format!(
            "\n{} shown{}{}",
            kept.len(),
            total
                .map(|t| format!(" of {t} matches"))
                .unwrap_or_default(),
            next_cursor
                .as_ref()
                .map(|c| format!("; next page: --cursor {c}"))
                .unwrap_or_default()
        ));
        text
    };

    let mut outcome = Outcome::read("search", data, human);
    outcome.warnings = warnings;
    Ok(outcome)
}
