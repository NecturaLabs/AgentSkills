//! `library` — what the account already owns.

use super::{match_tokens, matches_tokens, Ctx};
use crate::cli::LibraryArgs;
use crate::error::Result;
use crate::model::{Asset, Engine};
use crate::output::{license_cell, Outcome};
use serde_json::json;
use std::fmt::Write;

/// Results this small get their descriptions without being asked.
const AUTO_DETAILS: usize = 10;

/// Most listings `--details` fetches in one call.
const MAX_DETAILS: usize = 100;

/// Entries per page unless `--limit` says otherwise.
const DEFAULT_PAGE: usize = 100;

/// Largest page, the same bound as a marketplace search.
const MAX_PAGE: usize = crate::query::MAX_COUNT as usize;

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

    let per_page = args.limit.map_or(DEFAULT_PAGE, |l| l as usize);
    if per_page == 0 || per_page > MAX_PAGE {
        return Err(crate::error::FabError::invalid(format!(
            "--limit must be between 1 and {MAX_PAGE} (got {per_page})"
        )));
    }
    if args.page == 0 {
        return Err(crate::error::FabError::invalid("--page starts at 1"));
    }
    let (matched, total) = fetch_filtered(
        ctx,
        args.query.as_deref(),
        engine.as_ref(),
        engine_version.as_deref(),
        None,
    )?;
    let matched_count = matched.len();
    let pages = matched_count.div_ceil(per_page).max(1);
    let page = args.page as usize;
    let mut assets: Vec<Asset> = matched
        .into_iter()
        .skip((page - 1) * per_page)
        .take(per_page)
        .collect();
    let next_page = (page < pages).then_some(page + 1);

    let wanted = if args.no_details {
        0
    } else if args.details {
        MAX_DETAILS
    } else if assets.len() <= AUTO_DETAILS {
        AUTO_DETAILS
    } else {
        0
    };
    let mut warnings = describe(ctx, &mut assets, wanted);
    warnings.extend(super::license_warnings(&assets));
    if args.details && assets.len() > MAX_DETAILS {
        warnings.push(format!(
            "descriptions fetched for the first {MAX_DETAILS} of {} entries; narrow with a query or --limit",
            assets.len()
        ));
    }

    let data = json!({
        "results": assets,
        "returned": assets.len(),
        "matched": matched_count,
        "page": page,
        "pages": pages,
        "pageSize": per_page,
        "nextPage": next_page,
        "libraryTotal": total,
        "query": args.query,
        "engine": engine.as_ref().map(|e| e.as_str().to_string()),
        "engineVersion": engine_version,
    });

    let mut human = render(&assets, total, wanted == 0 && !args.no_details);
    if assets.is_empty() && page > 1 {
        human =
            format!("Page {page} is past the end: {matched_count} entries fit on {pages} page(s).");
    } else if pages > 1 {
        let _ = write!(human, "\nPage {page} of {pages}.");
        if let Some(next) = next_page {
            let _ = write!(human, " Next: {}", next_command(args, per_page, next));
        }
    }
    let mut outcome = Outcome::read("library", data, human);
    outcome.warnings = warnings;
    Ok(outcome)
}

/// Replace missing descriptions with the listing's own, for Fab listings
/// among the first `limit` entries. Other library entries (engine builds,
/// Epic's own plugins) have no listing to ask.
fn describe(ctx: &Ctx, assets: &mut [Asset], limit: usize) -> Vec<String> {
    let mut warnings = Vec::new();
    if limit == 0 || !ctx.provider.capabilities().listing_detail {
        return warnings;
    }
    for asset in assets.iter_mut().filter(|a| a.url.is_some()).take(limit) {
        match ctx.provider.listing(&asset.id, false) {
            Ok(detail) => {
                if detail.description.is_some() {
                    asset.description = detail.description;
                }
                if asset.publisher.is_none() {
                    asset.publisher = detail.publisher;
                }
                if asset.tags.is_empty() {
                    asset.tags = detail.tags;
                }
                asset.licenses = detail.licenses;
                asset.coverage.licenses = detail.coverage.licenses;
            }
            Err(err) => warnings.push(format!(
                "could not fetch the description of {}: {}",
                asset.id, err.code
            )),
        }
    }
    warnings
}

/// The command that shows page `next` with the same query and filters.
fn next_command(args: &LibraryArgs, per_page: usize, next: usize) -> String {
    let mut command = String::from("necturalabs-fab library");
    if let Some(query) = &args.query {
        let _ = write!(command, " '{}'", query.replace('\'', "'\\''"));
    }
    if let Some(engine) = &args.engine {
        let _ = write!(command, " --engine {engine}");
    }
    if let Some(version) = &args.engine_version {
        let _ = write!(command, " --engine-version {version}");
    }
    if args.limit.is_some() {
        let _ = write!(command, " --limit {per_page}");
    }
    if args.details {
        command.push_str(" --details");
    }
    if args.no_details {
        command.push_str(" --no-details");
    }
    let _ = write!(command, " --page {next}");
    command
}

/// One block per entry: what a person browsing needs, with the command that
/// downloads it.
fn render(assets: &[Asset], total: usize, offer_details: bool) -> String {
    if assets.is_empty() {
        return format!("No library entries matched (library holds {total}).");
    }
    let mut text = String::new();
    for asset in assets {
        let _ = writeln!(text, "{}", asset.title.as_deref().unwrap_or("(untitled)"));
        match &asset.url {
            Some(url) => {
                let _ = writeln!(text, "  link:        {url}");
            }
            None => {
                let _ = writeln!(text, "  link:        none (not a Fab listing)");
            }
        }
        if let Some(description) = &asset.description {
            let one_line: String = description.split_whitespace().collect::<Vec<_>>().join(" ");
            let short: String = one_line.chars().take(300).collect();
            let ellipsis = if one_line.chars().count() > 300 {
                "…"
            } else {
                ""
            };
            let _ = writeln!(text, "  description: {short}{ellipsis}");
        }
        if asset.coverage.licenses != crate::model::Availability::NotRequested {
            let _ = writeln!(text, "  licence:     {}", license_cell(asset));
        }
        if !asset.engine_versions.is_empty() {
            let _ = writeln!(text, "  engines:     {}", asset.engine_versions.join(", "));
        }
        if asset.url.is_some() {
            let _ = writeln!(text, "  download:    necturalabs-fab download {}", asset.id);
        }
        text.push('\n');
    }
    let _ = write!(text, "{} shown, library holds {}.", assets.len(), total);
    if offer_details {
        text.push_str(
            " Add --details for descriptions and licences (or narrow the search to 10 or fewer).",
        );
    }
    text
}
