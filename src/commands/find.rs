//! `find` and `recommend` — higher-level discovery.
//!
//! One deterministic pipeline: retrieve, enrich the strongest few, score with
//! [`crate::rank`], and hand the calling agent the candidates *with* the
//! signals behind them. Nothing here asks a model anything; the final
//! contextual judgement stays with the caller.

use super::{build_query, hydrate, Ctx};
use crate::cli::FindArgs;
use crate::config::ApprovalPolicy;
use crate::error::{ErrorCode, Result};
use crate::model::Asset;
use crate::output::{cell, license_cell, status_cell, table, Outcome};
use crate::rank::{self, Preferences, Ranking};
use serde_json::{json, Value};
use std::fmt::Write;

/// Candidates returned by `find` unless `--top` says otherwise.
const DEFAULT_TOP_FIND: u32 = 5;

/// Candidates returned by `recommend`.
const DEFAULT_TOP_RECOMMEND: u32 = 3;

/// Run `find`.
pub fn run_find(ctx: &Ctx, args: &FindArgs) -> Result<Outcome> {
    let outcome = run(ctx, args, DEFAULT_TOP_FIND, false)?;
    Ok(outcome)
}

/// Run `recommend`.
pub fn run_recommend(ctx: &Ctx, args: &FindArgs) -> Result<Outcome> {
    run(ctx, args, DEFAULT_TOP_RECOMMEND, true)
}

fn run(ctx: &Ctx, args: &FindArgs, default_top: u32, recommending: bool) -> Result<Outcome> {
    let command = if recommending { "recommend" } else { "find" };
    let mut warnings = Vec::new();

    let prefer_owned = resolve_flag(
        args.prefer_owned,
        args.no_prefer_owned,
        ctx.config.defaults.prefer_owned,
    );
    let prefer_free = resolve_flag(
        args.prefer_free,
        args.no_prefer_free,
        ctx.config.defaults.prefer_free,
    );

    let mut query = build_query(Some(args.intent.clone()), &args.filters, &ctx.config)?;
    // Ownership is the strongest ranking signal available, so ask for it
    // whenever the provider can supply it cheaply.
    if prefer_owned && ctx.provider.capabilities().search_ownership && !query.owned_only {
        query.with_ownership = true;
    }
    query.validate()?;

    let mut assets: Vec<Asset> = if query.owned_only {
        let (assets, total) = super::library::fetch_filtered(
            ctx,
            query.text.as_deref(),
            query.engine.as_ref(),
            query.engine_version.as_deref(),
            Some(query.count as usize),
        )?;
        warnings.push(format!(
            "searched the {total}-entry library, not the marketplace"
        ));
        assets
    } else {
        match ctx.provider.search(&query) {
            Ok(page) => page.assets,
            // An expired session must not turn discovery into a dead end:
            // retry without the ownership decoration and say so.
            Err(err)
                if query.with_ownership
                    && matches!(err.code, ErrorCode::AuthRequired | ErrorCode::AuthExpired) =>
            {
                warnings.push(format!(
                    "ownership could not be checked ({}); ranking without it",
                    err.code
                ));
                query.with_ownership = false;
                ctx.provider.search(&query)?.assets
            }
            Err(err) => return Err(err),
        }
    };

    let considered = assets.len();
    let hydrate_limit = args
        .hydrate
        .unwrap_or(ctx.config.defaults.hydrate)
        .min(assets.len() as u32) as usize;
    warnings.extend(hydrate(ctx, &mut assets, hydrate_limit));

    let prefs = Preferences {
        tokens: query.tokens(),
        engine: query.engine.clone(),
        engine_version: query.engine_version.clone(),
        require_engine: args.require_engine,
        prefer_owned,
        prefer_free,
        max_price: query.max_price,
        required_features: query.technical_features.clone(),
        today: rank::today_days(),
    };
    let ranking = rank::rank(assets, &prefs);

    let top = args.top.unwrap_or(default_top) as usize;
    warnings.extend(super::license_warning(
        ranking.ranked.iter().take(top).map(|s| &s.asset),
    ));
    let candidates: Vec<Value> = ranking
        .ranked
        .iter()
        .take(top)
        .enumerate()
        .map(|(index, scored)| {
            json!({
                "rank": index + 1,
                "score": round2(scored.score),
                "signals": round_signals(&scored.signals),
                "reasons": scored.reasons,
                // What was fetched, not where it ranked: ranking reorders.
                "hydrated": scored.asset.detail_level == Some(crate::model::DetailLevel::Detail),
                "asset": scored.asset,
            })
        })
        .collect();

    let mut data = json!({
        "intent": args.intent,
        "interpretation": {
            "tokens": prefs.tokens,
            "engine": prefs.engine.as_ref().map(|e| e.as_str().to_string()),
            "engineVersion": prefs.engine_version,
            "preferOwned": prefer_owned,
            "preferFree": prefer_free,
            "requireEngine": args.require_engine,
            "free": query.free,
            "maxPrice": query.max_price,
        },
        "considered": considered,
        "hydrated": hydrate_limit,
        "candidates": candidates,
        "excluded": ranking.excluded,
        "nextSteps": next_steps(&ranking, ctx),
    });

    if recommending {
        if let Some(value) = recommendation(&ranking, ctx) {
            data["recommendation"] = value;
        }
    }

    let human = render(&ranking, top, recommending);
    let mut outcome = Outcome::read(command, data, human);
    outcome.warnings = warnings;
    Ok(outcome)
}

fn resolve_flag(on: bool, off: bool, default: bool) -> bool {
    if on {
        return true;
    }
    if off {
        return false;
    }
    default
}

fn round2(value: f64) -> f64 {
    (value * 100.0).round() / 100.0
}

fn round_signals(signals: &rank::Signals) -> Value {
    json!({
        "relevance": round2(signals.relevance),
        "engine": round2(signals.engine),
        "ownership": round2(signals.ownership),
        "price": round2(signals.price),
        "quality": round2(signals.quality),
        "recency": round2(signals.recency),
        "technical": round2(signals.technical),
    })
}

fn next_steps(ranking: &Ranking, ctx: &Ctx) -> Vec<String> {
    let Some(best) = ranking.ranked.first() else {
        return vec!["broaden the query, or drop a filter, and search again".into()];
    };
    let id = &best.asset.id;
    let mut steps = vec![format!("necturalabs-fab inspect {id} --json")];
    match (best.asset.owned, best.asset.price.is_free()) {
        (Some(true), _) => steps.push(format!("necturalabs-fab download {id} --out <dir> --json")),
        (_, true) if ctx.config.approval.claim == ApprovalPolicy::Deny => steps.push(
            "adding it to the library is disabled here (approval.claim = deny); the user can add it on fab.com"
                .into(),
        ),
        (_, true) => {
            steps.push(format!(
                "necturalabs-fab claim {id} --dry-run --json  # then --approve once the user agrees"
            ));
        }
        _ => steps.push(format!(
            "buy {} on fab.com if the user approves the cost, then download it",
            best.asset
                .url
                .clone()
                .unwrap_or_else(|| crate::model::Asset::fab_url(id))
        )),
    }
    if !ctx.provider.capabilities().ownership {
        steps.push("ownership is unavailable from this provider; confirm manually".into());
    }
    steps
}

/// The single strongest candidate, with a deterministic confidence label.
fn recommendation(ranking: &Ranking, ctx: &Ctx) -> Option<Value> {
    let best = ranking.ranked.first()?;
    let runner_up = ranking.ranked.get(1).map(|s| s.score).unwrap_or(0.0);
    let gap = best.score - runner_up;
    let engine_known = !best.asset.engines.is_empty();

    // Confidence is arithmetic, not opinion: a clear leader with known engine
    // support is "high"; a narrow win, or one decided on missing metadata,
    // is not.
    let confidence = if best.score >= 0.7 && gap >= 0.08 && engine_known {
        "high"
    } else if best.score >= 0.5 {
        "medium"
    } else {
        "low"
    };

    let needs_claim = best.asset.owned != Some(true) && best.asset.price.is_free();
    let requires_approval = needs_claim && ctx.config.approval.claim == ApprovalPolicy::Require;

    Some(json!({
        "listingId": best.asset.id,
        "title": best.asset.title,
        "score": round2(best.score),
        "confidence": confidence,
        "scoreGapToRunnerUp": round2(gap),
        "why": best.reasons,
        "requiresApproval": requires_approval,
        "blockers": blockers(best, ctx.config.approval.claim),
    }))
}

fn blockers(scored: &rank::Scored, claim_policy: ApprovalPolicy) -> Vec<String> {
    let mut blockers = Vec::new();
    if scored.asset.owned != Some(true)
        && scored.asset.price.is_free()
        && claim_policy == ApprovalPolicy::Deny
    {
        blockers
            .push("free but not owned, and claiming is disabled (approval.claim = deny)".into());
    }
    if scored.asset.owned != Some(true) && !scored.asset.price.is_free() {
        blockers.push("not owned and not free: a purchase the user must make themselves".into());
    }
    if scored.asset.engines.is_empty() {
        blockers.push("engine support unverified: inspect the listing before committing".into());
    }
    blockers
}

fn render(ranking: &Ranking, top: usize, recommending: bool) -> String {
    if ranking.ranked.is_empty() {
        return format!(
            "No candidates.{}",
            if ranking.excluded.is_empty() {
                String::new()
            } else {
                format!(" {} excluded by filters.", ranking.excluded.len())
            }
        );
    }
    let rows: Vec<Vec<String>> = ranking
        .ranked
        .iter()
        .take(top)
        .enumerate()
        .map(|(index, scored)| {
            vec![
                format!("{}", index + 1),
                format!("{:.2}", scored.score),
                scored.asset.id.clone(),
                cell(scored.asset.title.as_deref(), 40),
                status_cell(scored.asset.owned, &scored.asset.price),
                license_cell(&scored.asset.licenses),
            ]
        })
        .collect();

    let mut text = table(
        &["#", "SCORE", "LISTING", "TITLE", "STATUS", "LICENCE"],
        &rows,
    );
    if recommending {
        if let Some(best) = ranking.ranked.first() {
            let _ = write!(
                text,
                "\nRecommended: {} ({})\n  because: {}\n",
                best.asset.title.as_deref().unwrap_or(&best.asset.id),
                best.asset.id,
                best.reasons.join("; ")
            );
        }
    }
    if !ranking.excluded.is_empty() {
        let _ = write!(text, "\n{} excluded:", ranking.excluded.len());
        for excluded in ranking.excluded.iter().take(5) {
            let _ = write!(text, "\n  {} — {}", excluded.id, excluded.reason);
        }
        text.push('\n');
    }
    text
}
