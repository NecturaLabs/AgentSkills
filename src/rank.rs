//! Deterministic candidate ranking.
//!
//! `find` and `recommend` order candidates with the arithmetic in this module
//! and nothing else. No model call, no hidden heuristics, no network: the same
//! inputs always produce the same order, and every contributing signal is
//! emitted alongside the score so the calling agent can disagree with it.
//!
//! Signals are normalised to 0..1 and combined with the fixed weights in
//! [`WEIGHTS`]. A signal that cannot be computed scores [`NEUTRAL`] rather
//! than zero: unknown is not the same as bad, and punishing missing metadata
//! would systematically bury assets whose sellers wrote less prose.

use crate::model::{Asset, Availability, Engine};
use serde::Serialize;

/// Score used when a signal cannot be computed.
pub const NEUTRAL: f64 = 0.5;

/// Per-place decay applied to the marketplace's own result ordering.
pub const POSITION_DECAY: f64 = 0.9;

/// Signal weights. They sum to 1.0; `Weights::validate` is asserted in tests.
#[derive(Debug, Clone, Copy)]
pub struct Weights {
    /// Query/category/tag match plus the marketplace's own ordering.
    pub relevance: f64,
    /// Engine and engine-version fit.
    pub engine: f64,
    /// Already owned.
    pub ownership: f64,
    /// Free, or within budget.
    pub price: f64,
    /// Rating quality, smoothed by review volume.
    pub quality: f64,
    /// How recently the listing was published.
    pub recency: f64,
    /// Whether the technical metadata needed to judge fitness exists.
    pub technical: f64,
}

/// The shipped weighting.
pub const WEIGHTS: Weights = Weights {
    relevance: 0.30,
    engine: 0.20,
    ownership: 0.15,
    price: 0.15,
    quality: 0.12,
    recency: 0.05,
    technical: 0.03,
};

impl Weights {
    /// Sum of all weights; 1.0 for a well-formed set.
    pub fn total(&self) -> f64 {
        self.relevance
            + self.engine
            + self.ownership
            + self.price
            + self.quality
            + self.recency
            + self.technical
    }
}

/// What the caller is looking for.
#[derive(Debug, Clone, Default)]
pub struct Preferences {
    /// Significant query tokens, lowercase.
    pub tokens: Vec<String>,
    /// Engine the project uses.
    pub engine: Option<Engine>,
    /// Engine version the project uses.
    pub engine_version: Option<String>,
    /// Drop candidates that positively do not support the engine/version.
    pub require_engine: bool,
    /// Prefer assets already in the library.
    pub prefer_owned: bool,
    /// Prefer free assets.
    pub prefer_free: bool,
    /// Budget ceiling; candidates above it are excluded.
    pub max_price: Option<crate::model::Amount>,
    /// Technical features that must be present, e.g. `rigged`.
    pub required_features: Vec<String>,
    /// Days since the Unix epoch, for recency. Injected so ranking is testable
    /// and reproducible.
    pub today: i64,
}

/// Per-signal scores for one candidate.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Signals {
    /// Query match.
    pub relevance: f64,
    /// Engine fit.
    pub engine: f64,
    /// Ownership.
    pub ownership: f64,
    /// Price fit.
    pub price: f64,
    /// Rating quality.
    pub quality: f64,
    /// Publication recency.
    pub recency: f64,
    /// Technical-metadata completeness and feature match.
    pub technical: f64,
}

/// A ranked candidate.
#[derive(Debug, Clone)]
pub struct Scored {
    /// The candidate.
    pub asset: Asset,
    /// Weighted total, 0..1.
    pub score: f64,
    /// Contributing signals.
    pub signals: Signals,
    /// Short, factual statements about why it ranked where it did.
    pub reasons: Vec<String>,
}

/// A candidate removed before ranking.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Excluded {
    /// Listing id.
    pub id: String,
    /// Title, when known.
    pub title: Option<String>,
    /// Why it was dropped.
    pub reason: String,
}

/// The outcome of ranking a candidate set.
#[derive(Debug, Clone)]
pub struct Ranking {
    /// Candidates, best first.
    pub ranked: Vec<Scored>,
    /// Candidates hard-filtered out, with reasons.
    pub excluded: Vec<Excluded>,
}

/// Rank `assets`, which must be in the provider's own result order.
pub fn rank(assets: Vec<Asset>, prefs: &Preferences) -> Ranking {
    let mut ranked = Vec::new();
    let mut excluded = Vec::new();

    for (index, asset) in assets.into_iter().enumerate() {
        if let Some(reason) = hard_filter(&asset, prefs) {
            excluded.push(Excluded {
                id: asset.id.clone(),
                title: asset.title.clone(),
                reason,
            });
            continue;
        }
        let signals = score_signals(&asset, prefs, index);
        let score = weighted(&signals);
        let reasons = reasons(&asset, prefs, &signals);
        ranked.push(Scored {
            asset,
            score,
            signals,
            reasons,
        });
    }

    // Deterministic order: score, then the tie-breaks a human would apply, and
    // finally the id so equal candidates never swap between runs.
    ranked.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| {
                b.asset
                    .owned
                    .unwrap_or(false)
                    .cmp(&a.asset.owned.unwrap_or(false))
            })
            .then_with(|| b.asset.price.is_free().cmp(&a.asset.price.is_free()))
            .then_with(|| {
                b.asset
                    .rating
                    .count
                    .unwrap_or(0)
                    .cmp(&a.asset.rating.count.unwrap_or(0))
            })
            .then_with(|| a.asset.id.cmp(&b.asset.id))
    });

    Ranking { ranked, excluded }
}

/// Reasons a candidate is not eligible at all. Only positive incompatibility
/// excludes: unknown metadata never does.
fn hard_filter(asset: &Asset, prefs: &Preferences) -> Option<String> {
    if let Some(max) = prefs.max_price {
        if let Some(amount) = asset.price.amount {
            if amount > max && !asset.price.is_free() {
                return Some(format!("price {amount} exceeds the {max} budget"));
            }
        }
    }
    if prefs.require_engine {
        if let Some(engine) = &prefs.engine {
            if asset.supports_engine(engine) == Some(false) {
                return Some(format!("does not ship for {}", engine.as_str()));
            }
            if let Some(version) = &prefs.engine_version {
                if asset.supports_engine_version(version) == Some(false) {
                    return Some(format!("does not ship for engine version {version}"));
                }
            }
        }
    }
    for feature in &prefs.required_features {
        if feature_state(asset, feature) == Some(false) {
            return Some(format!("is not {feature}"));
        }
    }
    None
}

fn score_signals(asset: &Asset, prefs: &Preferences, index: usize) -> Signals {
    Signals {
        relevance: relevance(asset, prefs, index),
        engine: engine_fit(asset, prefs),
        ownership: ownership_fit(asset, prefs),
        price: price_fit(asset, prefs),
        quality: quality(asset),
        recency: recency(asset, prefs.today),
        technical: technical_fit(asset, prefs),
    }
}

fn weighted(signals: &Signals) -> f64 {
    let w = WEIGHTS;
    let raw = signals.relevance * w.relevance
        + signals.engine * w.engine
        + signals.ownership * w.ownership
        + signals.price * w.price
        + signals.quality * w.quality
        + signals.recency * w.recency
        + signals.technical * w.technical;
    (raw / w.total()).clamp(0.0, 1.0)
}

/// Half the marketplace's own ordering, half literal token overlap.
///
/// The positional part decays geometrically rather than linearly across the
/// page, so it does not depend on how many results were requested and one
/// place of provider ordering cannot outweigh ownership or price.
fn relevance(asset: &Asset, prefs: &Preferences, index: usize) -> f64 {
    let position = POSITION_DECAY.powi(index as i32);
    if prefs.tokens.is_empty() {
        return position;
    }
    let mut haystack = String::new();
    if let Some(title) = &asset.title {
        haystack.push_str(&title.to_ascii_lowercase());
    }
    haystack.push(' ');
    haystack.push_str(&asset.tags.join(" ").to_ascii_lowercase());
    haystack.push(' ');
    if let Some(category) = &asset.category {
        if let Some(name) = &category.name {
            haystack.push_str(&name.to_ascii_lowercase());
        }
        haystack.push(' ');
        if let Some(slug) = &category.slug {
            haystack.push_str(&slug.to_ascii_lowercase());
        }
    }
    let matched = prefs
        .tokens
        .iter()
        .filter(|token| haystack.contains(token.as_str()))
        .count();
    let overlap = matched as f64 / prefs.tokens.len() as f64;
    0.5 * overlap + 0.5 * position
}

fn engine_fit(asset: &Asset, prefs: &Preferences) -> f64 {
    let Some(engine) = &prefs.engine else {
        return NEUTRAL;
    };
    match asset.supports_engine(engine) {
        None => NEUTRAL,
        Some(false) => 0.0,
        Some(true) => match prefs.engine_version.as_deref() {
            None => 1.0,
            Some(version) => match asset.supports_engine_version(version) {
                Some(true) => 1.0,
                // Ships for the engine but not the exact version: usually
                // still usable after an editor upgrade prompt.
                Some(false) => 0.4,
                None => 0.8,
            },
        },
    }
}

fn ownership_fit(asset: &Asset, prefs: &Preferences) -> f64 {
    if !prefs.prefer_owned {
        return NEUTRAL;
    }
    match asset.owned {
        Some(true) => 1.0,
        Some(false) => 0.3,
        None => NEUTRAL,
    }
}

fn price_fit(asset: &Asset, prefs: &Preferences) -> f64 {
    if asset.price.is_free() {
        return if prefs.prefer_free { 1.0 } else { 0.8 };
    }
    match (asset.price.amount, prefs.max_price) {
        (Some(amount), Some(max)) if !max.is_zero() => {
            (1.0 - amount.hundredths() as f64 / max.hundredths() as f64).clamp(0.0, 0.9)
        }
        // Paid with no stated budget: a known cost, so below free and below an
        // unknown price (which stays neutral rather than being assumed paid).
        (Some(_), None) => 0.4,
        _ => NEUTRAL,
    }
}

/// Bayesian-smoothed rating, so one five-star review does not outrank a
/// hundred four-star ones.
fn quality(asset: &Asset) -> f64 {
    const PRIOR_MEAN: f64 = 3.8;
    const PRIOR_WEIGHT: f64 = 5.0;
    let Some(average) = asset.rating.average else {
        return NEUTRAL;
    };
    let count = asset.rating.count.unwrap_or(0) as f64;
    if count == 0.0 {
        return NEUTRAL;
    }
    let smoothed = (average * count + PRIOR_MEAN * PRIOR_WEIGHT) / (count + PRIOR_WEIGHT);
    (smoothed / 5.0).clamp(0.0, 1.0)
}

/// Linear decay over two years, from the publication date.
fn recency(asset: &Asset, today: i64) -> f64 {
    const HORIZON_DAYS: f64 = 730.0;
    let Some(published) = asset.published_at.as_deref().and_then(days_from_iso8601) else {
        return NEUTRAL;
    };
    if today <= 0 {
        return NEUTRAL;
    }
    let age = (today - published) as f64;
    if age < 0.0 {
        return 1.0;
    }
    (1.0 - age / HORIZON_DAYS).clamp(0.0, 1.0)
}

fn technical_fit(asset: &Asset, prefs: &Preferences) -> f64 {
    if !prefs.required_features.is_empty() {
        let satisfied = prefs
            .required_features
            .iter()
            .filter(|f| feature_state(asset, f) == Some(true))
            .count();
        return satisfied as f64 / prefs.required_features.len() as f64;
    }
    match asset.coverage.technical {
        Availability::Available if !asset.technical.is_empty() => 1.0,
        Availability::Unavailable => 0.3,
        _ => NEUTRAL,
    }
}

/// Tri-state answer for a named technical feature.
fn feature_state(asset: &Asset, feature: &str) -> Option<bool> {
    match feature.trim().to_ascii_lowercase().as_str() {
        "rigged" => asset.technical.rigged,
        "animated" => asset.technical.animated,
        "skeletal" => asset.technical.skeletal,
        "static" => asset.technical.skeletal.map(|s| !s),
        other => {
            // Unmodelled features fall back to the marketplace's own tags.
            if asset.tags.iter().any(|t| t.eq_ignore_ascii_case(other)) {
                Some(true)
            } else {
                None
            }
        }
    }
}

fn reasons(asset: &Asset, prefs: &Preferences, signals: &Signals) -> Vec<String> {
    let mut reasons = Vec::new();
    if asset.owned == Some(true) {
        reasons.push("already in your library".into());
    }
    if asset.price.is_free() {
        if asset.price.temporarily_free == Some(true) {
            reasons.push("free right now (limited-time 100% discount)".into());
        } else {
            reasons.push("permanently free".into());
        }
    } else if let Some(amount) = asset.price.amount {
        reasons.push(format!(
            "costs {amount:.2} {}",
            asset.price.currency.as_deref().unwrap_or("")
        ));
    }
    if let Some(engine) = &prefs.engine {
        match asset.supports_engine(engine) {
            Some(true) => reasons.push(format!("ships for {}", engine.as_str())),
            Some(false) => reasons.push(format!("does not ship for {}", engine.as_str())),
            None => reasons.push("engine support not stated in search results".into()),
        }
    }
    if let (Some(avg), Some(count)) = (asset.rating.average, asset.rating.count) {
        if count > 0 {
            reasons.push(format!("rated {avg:.1} from {count} ratings"));
        }
    }
    if signals.relevance >= 0.75 {
        reasons.push("strong query match".into());
    }
    reasons
}

/// Days since 1970-01-01 for an ISO-8601 timestamp's date part.
pub fn days_from_iso8601(raw: &str) -> Option<i64> {
    let date = raw.split(['T', ' ']).next()?;
    let mut parts = date.split('-');
    let year: i64 = parts.next()?.parse().ok()?;
    let month: i64 = parts.next()?.parse().ok()?;
    let day: i64 = parts.next()?.parse().ok()?;
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    Some(days_from_civil(year, month, day))
}

/// Howard Hinnant's days-from-civil algorithm. Exact for the proleptic
/// Gregorian calendar and dependency-free.
pub fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// Today, as days since the Unix epoch. `0` when the clock is unreadable.
pub fn today_days() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| (d.as_secs() / 86_400) as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Price, Rating};

    fn asset(id: &str) -> Asset {
        let mut asset = Asset::new(id, "test");
        asset.title = Some(format!("{id} pack"));
        asset
    }

    fn prefs() -> Preferences {
        Preferences {
            prefer_owned: true,
            prefer_free: true,
            today: days_from_civil(2026, 9, 22),
            ..Default::default()
        }
    }

    #[test]
    fn price_signal_orders_free_then_unknown_then_paid() {
        let prefs = prefs();
        let mut free = asset("free");
        free.price = Price {
            free: Some(true),
            amount: crate::model::Amount::parse("0.0"),
            ..Default::default()
        };
        let unknown = asset("unknown");
        let mut paid = asset("paid");
        paid.price = Price {
            free: Some(false),
            amount: crate::model::Amount::parse("25.0"),
            ..Default::default()
        };
        assert!(price_fit(&free, &prefs) > price_fit(&unknown, &prefs));
        assert!(price_fit(&unknown, &prefs) > price_fit(&paid, &prefs));
    }

    #[test]
    fn weights_sum_to_one() {
        assert!((WEIGHTS.total() - 1.0).abs() < 1e-9, "{}", WEIGHTS.total());
    }

    #[test]
    fn ranking_is_stable_for_identical_input() {
        let assets: Vec<Asset> = (0..5).map(|i| asset(&format!("a{i}"))).collect();
        let first = rank(assets.clone(), &prefs());
        let second = rank(assets, &prefs());
        let ids: Vec<&str> = first.ranked.iter().map(|s| s.asset.id.as_str()).collect();
        let ids2: Vec<&str> = second.ranked.iter().map(|s| s.asset.id.as_str()).collect();
        assert_eq!(ids, ids2);
    }

    #[test]
    fn owned_beats_unowned_when_all_else_matches() {
        let mut owned = asset("owned");
        owned.owned = Some(true);
        let mut unowned = asset("unowned");
        unowned.owned = Some(false);
        let ranking = rank(vec![unowned, owned], &prefs());
        assert_eq!(ranking.ranked[0].asset.id, "owned");
    }

    #[test]
    fn free_beats_paid_when_all_else_matches() {
        let mut free = asset("free");
        free.price = Price {
            free: Some(true),
            amount: crate::model::Amount::parse("0.0"),
            ..Default::default()
        };
        let mut paid = asset("paid");
        paid.price = Price {
            free: Some(false),
            amount: crate::model::Amount::parse("49.0"),
            ..Default::default()
        };
        let ranking = rank(vec![paid, free], &prefs());
        assert_eq!(ranking.ranked[0].asset.id, "free");
    }

    #[test]
    fn unknown_metadata_scores_neutral_not_zero() {
        let bare = asset("bare");
        let ranking = rank(vec![bare], &prefs());
        let signals = &ranking.ranked[0].signals;
        assert_eq!(signals.ownership, NEUTRAL);
        assert_eq!(signals.quality, NEUTRAL);
        assert_eq!(signals.recency, NEUTRAL);
    }

    #[test]
    fn engine_mismatch_only_excludes_when_required() {
        let mut wrong = asset("unity-only");
        wrong.engines = vec![Engine::Unity];
        let mut prefs = prefs();
        prefs.engine = Some(Engine::Unreal);

        let soft = rank(vec![wrong.clone()], &prefs);
        assert_eq!(soft.ranked.len(), 1, "soft mode keeps it, ranked low");
        assert_eq!(soft.ranked[0].signals.engine, 0.0);

        prefs.require_engine = true;
        let hard = rank(vec![wrong], &prefs);
        assert!(hard.ranked.is_empty());
        assert_eq!(hard.excluded.len(), 1);
        assert!(hard.excluded[0].reason.contains("unreal"));
    }

    #[test]
    fn unknown_engine_support_is_never_excluded() {
        let unknown = asset("unknown-engine");
        let mut prefs = prefs();
        prefs.engine = Some(Engine::Unreal);
        prefs.require_engine = true;
        let ranking = rank(vec![unknown], &prefs);
        assert_eq!(ranking.ranked.len(), 1);
        assert_eq!(ranking.ranked[0].signals.engine, NEUTRAL);
    }

    #[test]
    fn over_budget_paid_assets_are_excluded_but_free_ones_are_not() {
        let mut expensive = asset("expensive");
        expensive.price = Price {
            free: Some(false),
            amount: crate::model::Amount::parse("120.0"),
            ..Default::default()
        };
        let mut free = asset("free");
        free.price = Price {
            free: Some(true),
            amount: crate::model::Amount::parse("0.0"),
            ..Default::default()
        };
        let mut prefs = prefs();
        prefs.max_price = crate::model::Amount::parse("20.0");
        let ranking = rank(vec![expensive, free], &prefs);
        assert_eq!(ranking.ranked.len(), 1);
        assert_eq!(ranking.ranked[0].asset.id, "free");
        assert!(ranking.excluded[0].reason.contains("budget"));
    }

    #[test]
    fn rating_quality_is_smoothed_by_review_volume() {
        let mut lucky = asset("one-five-star");
        lucky.rating = Rating {
            average: Some(5.0),
            count: Some(1),
        };
        let mut proven = asset("many-four-star");
        proven.rating = Rating {
            average: Some(4.6),
            count: Some(200),
        };
        // A single five-star review must not beat a well-reviewed 4.6.
        assert!(quality(&proven) > quality(&lucky));
        // And an unrated asset sits between them at neutral.
        let unrated = asset("unrated");
        assert!(quality(&lucky) > quality(&unrated));
    }

    #[test]
    fn provider_ordering_never_outweighs_ownership_or_price() {
        // One place of marketplace ordering is worth less than being owned.
        let position_gap = (1.0 - POSITION_DECAY) * WEIGHTS.relevance;
        let ownership_gap = (1.0 - 0.3) * WEIGHTS.ownership;
        assert!(
            position_gap < ownership_gap,
            "{position_gap} vs {ownership_gap}"
        );
    }

    #[test]
    fn recency_decays_and_future_dates_are_clamped() {
        let today = days_from_civil(2026, 9, 22);
        let mut fresh = asset("fresh");
        fresh.published_at = Some("2026-09-01T00:00:00Z".into());
        let mut old = asset("old");
        old.published_at = Some("2019-01-01T00:00:00Z".into());
        assert!(recency(&fresh, today) > 0.9);
        assert_eq!(recency(&old, today), 0.0);
        let mut future = asset("future");
        future.published_at = Some("2030-01-01T00:00:00Z".into());
        assert_eq!(recency(&future, today), 1.0);
    }

    #[test]
    fn required_features_exclude_only_a_stated_no() {
        let mut not_rigged = asset("static");
        not_rigged.technical.rigged = Some(false);
        let mut rigged = asset("rigged");
        rigged.technical.rigged = Some(true);
        let unknown = asset("unstated");
        let mut prefs = prefs();
        prefs.required_features = vec!["rigged".into()];
        let ranking = rank(vec![not_rigged, rigged, unknown], &prefs);
        let ids: Vec<&str> = ranking.ranked.iter().map(|s| s.asset.id.as_str()).collect();
        assert!(ids.contains(&"rigged") && ids.contains(&"unstated"));
        assert_eq!(ranking.excluded.len(), 1);
        assert_eq!(ranking.excluded[0].id, "static");
    }

    #[test]
    fn query_tokens_lift_matching_titles() {
        let mut castle = asset("x");
        castle.title = Some("Gothic Ruined Castle".into());
        let mut chair = asset("y");
        chair.title = Some("Office Chair".into());
        let mut prefs = prefs();
        prefs.tokens = vec!["gothic".into(), "castle".into()];
        // Give the unrelated asset the better provider position to prove
        // token overlap actually moves the result.
        let ranking = rank(vec![chair, castle], &prefs);
        assert_eq!(ranking.ranked[0].asset.id, "x");
    }

    #[test]
    fn civil_days_matches_known_dates() {
        assert_eq!(days_from_civil(1970, 1, 1), 0);
        assert_eq!(days_from_civil(2000, 3, 1), 11017);
        assert_eq!(
            days_from_iso8601("2026-09-22T12:00:00Z"),
            Some(days_from_civil(2026, 9, 22))
        );
        assert_eq!(days_from_iso8601("not-a-date"), None);
    }

    #[test]
    fn scores_stay_within_zero_and_one() {
        let mut best = asset("best");
        best.owned = Some(true);
        best.price = Price {
            free: Some(true),
            ..Default::default()
        };
        best.engines = vec![Engine::Unreal];
        best.engine_versions = vec!["UE_5.4".into()];
        best.rating = Rating {
            average: Some(5.0),
            count: Some(500),
        };
        best.published_at = Some("2026-09-20T00:00:00Z".into());
        best.technical.rigged = Some(true);
        best.coverage.technical = Availability::Available;
        let mut prefs = prefs();
        prefs.engine = Some(Engine::Unreal);
        prefs.engine_version = Some("5.4".into());
        let ranking = rank(vec![best], &prefs);
        assert!(ranking.ranked[0].score <= 1.0 && ranking.ranked[0].score > 0.9);
    }
}
