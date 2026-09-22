//! `library` — what the account already owns.

use super::{match_tokens, matches_tokens, Ctx};
use crate::cli::LibraryArgs;
use crate::error::Result;
use crate::model::{Asset, Engine};
use crate::output::{cell, table, Outcome};
use serde_json::json;

/// Fetch the library and apply client-side filters.
///
/// The marketplace exposes no query interface over a library, so filtering is
/// ours: full enumeration, then token and engine matching. The provider caches
/// the enumeration, which is why repeated calls are cheap after the first.
pub fn fetch_filtered(
    ctx: &Ctx,
    query: Option<&str>,
    engine: Option<&Engine>,
    engine_version: Option<&str>,
    limit: Option<usize>,
) -> Result<(Vec<Asset>, usize)> {
    let all = ctx.provider.library()?;
    let total = all.len();
    let tokens = query.map(match_tokens).unwrap_or_default();

    let mut matched: Vec<Asset> = all
        .into_iter()
        .filter(|asset| matches_tokens(asset, &tokens))
        .filter(|asset| match engine {
            Some(engine) => asset.supports_engine(engine) != Some(false),
            None => true,
        })
        .filter(|asset| match engine_version {
            Some(version) => asset.supports_engine_version(version) != Some(false),
            None => true,
        })
        .collect();

    if let Some(limit) = limit {
        matched.truncate(limit);
    }
    Ok((matched, total))
}

/// Run `library`.
pub fn run(ctx: &Ctx, args: &LibraryArgs) -> Result<Outcome> {
    let engine = args
        .engine
        .as_deref()
        .or(ctx.config.defaults.engine.as_deref())
        .map(Engine::parse);
    let engine_version = args
        .engine_version
        .clone()
        .or_else(|| ctx.config.defaults.engine_version.clone());

    let (assets, total) = fetch_filtered(
        ctx,
        args.query.as_deref(),
        engine.as_ref(),
        engine_version.as_deref(),
        args.limit.map(|l| l as usize),
    )?;

    let data = json!({
        "results": assets,
        "returned": assets.len(),
        "libraryTotal": total,
        "query": args.query,
        "engine": engine.as_ref().map(|e| e.as_str().to_string()),
        "engineVersion": engine_version,
    });

    let rows: Vec<Vec<String>> = assets
        .iter()
        .map(|asset| {
            vec![
                asset.id.clone(),
                cell(asset.title.as_deref(), 48),
                if asset.engine_versions.is_empty() {
                    "-".into()
                } else {
                    asset.engine_versions.join(",")
                },
            ]
        })
        .collect();
    let human = if rows.is_empty() {
        format!("No library entries matched (library holds {total}).")
    } else {
        format!(
            "{}\n{} of {} library entries.",
            table(&["LISTING", "TITLE", "ENGINE VERSIONS"], &rows),
            assets.len(),
            total
        )
    };

    Ok(Outcome::read("library", data, human))
}
