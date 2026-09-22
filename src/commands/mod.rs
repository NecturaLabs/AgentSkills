//! Command implementations.
//!
//! Every command takes a [`Ctx`], returns an [`Outcome`], and never touches
//! stdout itself: rendering and exit codes belong to `main`. That keeps the
//! JSON contract in exactly one place.

pub mod auth;
pub mod capabilities;
pub mod claim;
pub mod config_cmd;
pub mod doctor;
pub mod download;
pub mod find;
pub mod inspect;
pub mod library;
pub mod ownership;
pub mod promos;
pub mod search;
pub mod skill;

use crate::cli::{Cli, FilterArgs};
use crate::config::{Config, LayerRecord, OutputMode};
use crate::error::{ErrorCode, FabError, Result};
use crate::model::{Asset, Engine};
use crate::output::{Meta, Outcome, Renderer};
use crate::provider::fabcli::{FabCliProvider, FabCliSettings};
use crate::provider::FabProvider;
use crate::query::{FreeMode, SearchQuery, SortOrder};
use std::path::PathBuf;
use std::time::{Duration, Instant};

/// Providers this build can construct.
pub const KNOWN_PROVIDERS: &[&str] = &["fabcli"];

/// Everything a command needs.
pub struct Ctx {
    /// Effective configuration.
    pub config: Config,
    /// Where each configuration layer came from.
    pub layers: Vec<LayerRecord>,
    /// Active provider.
    pub provider: Box<dyn FabProvider>,
    /// Output renderer.
    pub renderer: Renderer,
    /// Include provider payloads on assets.
    pub raw: bool,
    /// Working directory the command runs against.
    pub cwd: PathBuf,
    /// Start of the process, for `meta.elapsedMs`.
    pub started: Instant,
    /// Why configuration failed to load, when a repair command is running on
    /// defaults instead.
    pub config_error: Option<FabError>,
}

impl Ctx {
    /// Build a context from parsed arguments and loaded configuration.
    pub fn new(cli: &Cli, config: Config, layers: Vec<LayerRecord>, cwd: PathBuf) -> Result<Self> {
        let mode = resolve_output_mode(cli, &config)?;
        let renderer = Renderer::new(mode, cli.quiet);
        let provider = build_provider(&config, cli.raw, renderer.wants_progress())?;
        Ok(Self {
            config,
            layers,
            provider,
            renderer,
            raw: cli.raw,
            cwd,
            started: Instant::now(),
            config_error: None,
        })
    }

    /// The output mode this context resolved to.
    pub fn renderer_mode(&self) -> OutputMode {
        if self.renderer.is_json() {
            OutputMode::Json
        } else {
            OutputMode::Human
        }
    }

    /// Envelope metadata. `provider_version` is only filled when a command
    /// already knows it: discovering it costs a subprocess call.
    pub fn meta(&self, provider_version: Option<String>) -> Meta {
        Meta {
            version: crate::VERSION.to_string(),
            provider: self.provider.id().to_string(),
            provider_version,
            elapsed_ms: self.started.elapsed().as_millis() as u64,
        }
    }
}

fn resolve_output_mode(cli: &Cli, config: &Config) -> Result<OutputMode> {
    if cli.json {
        return Ok(OutputMode::Json);
    }
    if cli.human {
        return Ok(OutputMode::Human);
    }
    if let Some(mode) = &cli.output {
        return OutputMode::parse(mode);
    }
    Ok(config.output.mode)
}

/// Construct the configured provider.
pub fn build_provider(config: &Config, raw: bool, progress: bool) -> Result<Box<dyn FabProvider>> {
    match config.provider.as_str() {
        "fabcli" => {
            let settings = FabCliSettings {
                program: config.fabcli.path.clone(),
                timeout: Duration::from_secs(config.fabcli.timeout_seconds),
                download_timeout: Duration::from_secs(config.fabcli.download_timeout_seconds),
                version_requirement: config.fabcli.version_requirement.clone(),
                library_cache: config.fabcli.library_cache,
                progress,
            };
            Ok(Box::new(FabCliProvider::new(settings).with_raw(raw)))
        }
        other => Err(FabError::new(
            ErrorCode::ConfigInvalid,
            format!(
                "unknown provider '{other}' (available: {})",
                KNOWN_PROVIDERS.join(", ")
            ),
        )
        .with_hint("set `provider` in the config, or drop --provider")),
    }
}

/// Translate CLI filters into a provider-independent query.
pub fn build_query(
    text: Option<String>,
    filters: &FilterArgs,
    config: &Config,
) -> Result<SearchQuery> {
    let mut query = SearchQuery::new();
    if let Some(text) = text {
        query = query.with_text(text);
    }
    query.count = filters.count.unwrap_or(config.defaults.count);

    let engine = filters
        .engine
        .clone()
        .or_else(|| config.defaults.engine.clone());
    query.engine = engine.as_deref().map(Engine::parse);
    query.engine_version = filters
        .engine_version
        .clone()
        .or_else(|| config.defaults.engine_version.clone());

    query.formats = filters.formats.clone();
    query.categories = filters.categories.clone();
    query.listing_types = filters.listing_types.clone();
    query.styles = filters.styles.clone();
    query.technical_features = filters.features.clone();
    query.licenses = filters.licenses.clone();
    query.seller = filters.seller.clone();
    query.owned_only = filters.owned_only;
    query.with_ownership = filters.with_ownership;
    query.min_price = filters.min_price;
    query.max_price = filters.max_price;
    query.min_rating = filters.min_rating;
    query.published_since = filters.published_since.clone();

    query.free = if filters.free_only {
        FreeMode::Permanent
    } else {
        match &filters.free {
            Some(mode) => FreeMode::parse(mode)?,
            None => FreeMode::Any,
        }
    };

    if let Some(sort) = &filters.sort {
        query.sort = Some(SortOrder::parse(sort)?);
    }

    for raw in &filters.raw_filters {
        let (key, value) = raw.split_once('=').ok_or_else(|| {
            FabError::invalid(format!("--filter expects KEY=VALUE (got '{raw}')"))
        })?;
        if key.trim().is_empty() || value.trim().is_empty() {
            return Err(FabError::invalid(format!(
                "--filter expects a non-empty key and value (got '{raw}')"
            )));
        }
        query
            .raw_filters
            .push((key.trim().to_string(), value.to_string()));
    }

    query.validate()?;
    Ok(query)
}

/// Fetch listing detail for the first `limit` assets and merge it in.
///
/// Search results carry no engine, format or technical data — Fab's search
/// index does not return it — so anything that needs to judge compatibility
/// has to pay for detail calls. Failures are reported as warnings: a partially
/// enriched result set is more useful than none.
pub fn hydrate(ctx: &Ctx, assets: &mut [Asset], limit: usize) -> Vec<String> {
    let mut warnings = Vec::new();
    if limit == 0 || !ctx.provider.capabilities().listing_detail {
        return warnings;
    }
    for asset in assets.iter_mut().take(limit) {
        match ctx.provider.listing(&asset.id, true) {
            Ok(detail) => merge_detail(asset, detail),
            Err(err) => warnings.push(format!(
                "could not fetch detail for {}: {} ({})",
                asset.id, err.message, err.code
            )),
        }
    }
    warnings
}

/// Fold a detail record into a summary record, keeping whatever the summary
/// knew and the detail did not (ownership decoration, mainly).
pub fn merge_detail(summary: &mut Asset, detail: Asset) {
    let owned = summary.owned.or(detail.owned);
    let ownership_coverage = summary.coverage.ownership;
    let id = summary.id.clone();
    let mut merged = detail;
    // Identity is the caller's, not the provider's: a detail response that
    // came back with a different uid must not silently relabel the asset an
    // agent is about to download.
    merged.id = id;
    merged.owned = owned;
    merged.coverage.ownership = ownership_coverage;
    if merged.rating.average.is_none() {
        merged.rating = summary.rating.clone();
    }
    // Listing detail prices in the account's local currency while search uses
    // the marketplace list currency. Ranking compares candidates, so the list
    // price stays authoritative and the local one is kept alongside.
    if summary.price.amount.is_some() && summary.price.currency.is_some() {
        let local = std::mem::replace(&mut merged.price, summary.price.clone());
        if local.currency.is_some() && local.currency != merged.price.currency {
            merged.local_price = Some(local);
        }
    }
    if merged.thumbnail.is_none() {
        merged.thumbnail.clone_from(&summary.thumbnail);
    }
    *summary = merged;
}

/// Apply the post-retrieval filters Fab cannot evaluate server-side.
///
/// Returns the assets that survive, plus a reason for each drop. Only a
/// positive mismatch drops an asset; unknown metadata never does.
pub fn apply_client_filters(
    assets: Vec<Asset>,
    query: &SearchQuery,
) -> (Vec<Asset>, Vec<(String, String)>) {
    let mut kept = Vec::new();
    let mut dropped = Vec::new();
    for asset in assets {
        if let Some(version) = &query.engine_version {
            if asset.supports_engine_version(version) == Some(false) {
                dropped.push((
                    asset.id.clone(),
                    format!("does not ship for engine version {version}"),
                ));
                continue;
            }
        }
        if let Some(engine) = &query.engine {
            if asset.supports_engine(engine) == Some(false) {
                dropped.push((
                    asset.id.clone(),
                    format!("does not ship for {}", engine.as_str()),
                ));
                continue;
            }
        }
        kept.push(asset);
    }
    (kept, dropped)
}

/// Lowercase words from a free-text filter, for library matching.
pub fn match_tokens(text: &str) -> Vec<String> {
    text.split(|c: char| !c.is_alphanumeric())
        .filter(|t| t.len() > 1)
        .map(|t| t.to_ascii_lowercase())
        .collect()
}

/// Whether an asset's searchable text contains every token.
pub fn matches_tokens(asset: &Asset, tokens: &[String]) -> bool {
    if tokens.is_empty() {
        return true;
    }
    let mut haystack = String::new();
    for part in [
        Some(asset.id.as_str()),
        asset.url.as_deref(),
        asset.title.as_deref(),
        asset.description.as_deref(),
        asset.category.as_ref().and_then(|c| c.name.as_deref()),
        asset.category.as_ref().and_then(|c| c.slug.as_deref()),
    ]
    .into_iter()
    .flatten()
    {
        haystack.push_str(&part.to_ascii_lowercase());
        haystack.push(' ');
    }
    haystack.push_str(&asset.tags.join(" ").to_ascii_lowercase());
    tokens.iter().all(|token| haystack.contains(token.as_str()))
}

pub use crate::model::validate_listing_id;

/// Shorthand for a read-only outcome.
pub fn read_outcome(command: &str, data: serde_json::Value, human: String) -> Outcome {
    Outcome::read(command, data, human)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Category;

    fn config() -> Config {
        Config::default()
    }

    #[test]
    fn filters_translate_into_the_query_vocabulary() {
        let filters = FilterArgs {
            engine: Some("unity".into()),
            free_only: true,
            styles: vec!["lowpoly".into()],
            max_price: crate::model::Amount::parse("25"),
            sort: Some("newest".into()),
            count: Some(10),
            raw_filters: vec!["experimental=1".into()],
            ..Default::default()
        };
        let query = build_query(Some("castle".into()), &filters, &config()).unwrap();
        assert_eq!(query.text.as_deref(), Some("castle"));
        assert_eq!(query.engine, Some(Engine::Unity));
        assert_eq!(query.free, FreeMode::Permanent);
        assert_eq!(query.styles, vec!["lowpoly"]);
        assert_eq!(query.max_price, crate::model::Amount::parse("25"));
        assert_eq!(query.sort, Some(SortOrder::Newest));
        assert_eq!(query.count, 10);
        assert_eq!(
            query.raw_filters,
            vec![("experimental".to_string(), "1".to_string())]
        );
    }

    #[test]
    fn config_defaults_fill_unset_filters() {
        let mut config = config();
        config.defaults.engine = Some("unreal".into());
        config.defaults.engine_version = Some("5.4".into());
        config.defaults.count = 7;
        let query = build_query(None, &FilterArgs::default(), &config).unwrap();
        assert_eq!(query.engine, Some(Engine::Unreal));
        assert_eq!(query.engine_version.as_deref(), Some("5.4"));
        assert_eq!(query.count, 7);
    }

    #[test]
    fn explicit_flags_beat_config_defaults() {
        let mut config = config();
        config.defaults.engine = Some("unreal".into());
        let filters = FilterArgs {
            engine: Some("godot".into()),
            ..Default::default()
        };
        let query = build_query(None, &filters, &config).unwrap();
        assert_eq!(query.engine, Some(Engine::Godot));
    }

    #[test]
    fn malformed_raw_filters_are_rejected() {
        let filters = FilterArgs {
            raw_filters: vec!["bogus".into()],
            ..Default::default()
        };
        let err = build_query(None, &filters, &config()).unwrap_err();
        assert_eq!(err.code, ErrorCode::InvalidInput);
    }

    #[test]
    fn unknown_provider_is_a_config_error_listing_the_known_ones() {
        let mut config = config();
        config.provider = "telepathy".into();
        let err = build_provider(&config, false, false)
            .err()
            .expect("unknown provider must be rejected");
        assert_eq!(err.code, ErrorCode::ConfigInvalid);
        assert!(err.message.contains("fabcli"));
    }

    #[test]
    fn client_filters_drop_only_positive_mismatches() {
        let mut compatible = Asset::new("ok", "t");
        compatible.engines = vec![Engine::Unreal];
        compatible.engine_versions = vec!["UE_5.4".into()];
        let mut wrong_version = Asset::new("bad-version", "t");
        wrong_version.engines = vec![Engine::Unreal];
        wrong_version.engine_versions = vec!["UE_4.27".into()];
        let unknown = Asset::new("unknown", "t");

        let mut query = SearchQuery::new();
        query.engine = Some(Engine::Unreal);
        query.engine_version = Some("5.4".into());
        let (kept, dropped) =
            apply_client_filters(vec![compatible, wrong_version, unknown], &query);
        let ids: Vec<&str> = kept.iter().map(|a| a.id.as_str()).collect();
        assert_eq!(ids, vec!["ok", "unknown"]);
        assert_eq!(dropped.len(), 1);
        assert_eq!(dropped[0].0, "bad-version");
    }

    #[test]
    fn merge_detail_keeps_search_only_knowledge() {
        let mut summary = Asset::new("uid", "t");
        summary.owned = Some(true);
        summary.coverage.ownership = crate::model::Availability::Available;
        summary.thumbnail = Some("https://thumb".into());

        let mut detail = Asset::new("uid", "t");
        detail.description = Some("full text".into());
        merge_detail(&mut summary, detail);

        assert_eq!(summary.owned, Some(true));
        assert_eq!(summary.thumbnail.as_deref(), Some("https://thumb"));
        assert_eq!(summary.description.as_deref(), Some("full text"));
    }

    #[test]
    fn merge_detail_keeps_the_list_price_and_records_the_local_one() {
        let mut summary = Asset::new("uid", "t");
        summary.price.amount = crate::model::Amount::parse("149.99");
        summary.price.currency = Some("USD".into());
        let mut detail = Asset::new("uid", "t");
        detail.price.amount = crate::model::Amount::parse("452.14");
        detail.price.currency = Some("ILS".into());
        merge_detail(&mut summary, detail);
        assert_eq!(
            summary.price.currency.as_deref(),
            Some("USD"),
            "ranking needs one currency"
        );
        let local = summary.local_price.expect("local price kept");
        assert_eq!(local.currency.as_deref(), Some("ILS"));
        assert_eq!(local.amount, crate::model::Amount::parse("452.14"));
    }

    #[test]
    fn merge_detail_never_changes_the_asset_identity() {
        let mut summary = Asset::new("requested-uid", "t");
        let detail = Asset::new("some-other-uid", "t");
        merge_detail(&mut summary, detail);
        assert_eq!(summary.id, "requested-uid");
    }

    #[test]
    fn library_matching_requires_every_token() {
        let mut asset = Asset::new("uid", "t");
        asset.title = Some("Gothic Castle Ruins".into());
        asset.category = Some(Category {
            name: Some("Environments".into()),
            slug: Some("environments".into()),
            path: None,
        });
        assert!(matches_tokens(&asset, &match_tokens("castle ruins")));
        assert!(matches_tokens(&asset, &match_tokens("gothic environments")));
        assert!(!matches_tokens(&asset, &match_tokens("castle spaceship")));
        assert!(matches_tokens(&asset, &[]));
    }
}
