//! The FabCLI provider: necturalabs-fab's first implementation of
//! [`crate::provider::FabProvider`].
//!
//! FabCLI is an unofficial CLI over Epic's and Fab's undocumented, unversioned
//! APIs. It is executed as a child process and never linked, so:
//!
//! * its GPL-3.0 licence stays at arm's length (see `docs/licensing.md`);
//! * the credential handling stays entirely inside FabCLI — necturalabs-fab never
//!   reads, writes, forwards or logs a token;
//! * an upstream break shows up as a mapped error, not as corrupted output.

pub mod exec;
pub mod map;
pub mod version;

use crate::error::{ErrorCode, FabError, Result};
use crate::model::{validate_listing_id, Asset, Availability, Ownership};
use crate::provider::{
    AuthStatus, Capabilities, ClaimOutcome, DownloadReceipt, DownloadRequest, FabProvider,
    LoginScope, OverwritePolicy, ProviderHealth, SearchPage,
};
use crate::query::{FreeMode, SearchQuery, SortOrder};
use exec::{Exec, Output, StderrMode};
use serde_json::Value;
use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::time::Duration;

/// Page size used for library enumeration. FabCLI's own guidance: 500 keeps
/// payloads reliable while cutting round-trips roughly threefold versus 100.
const LIBRARY_PAGE_SIZE: &str = "500";

/// Cap on an interactive sign-in: long enough for a slow 2FA, short enough that
/// a forgotten window cannot wedge a session forever.
const LOGIN_TIMEOUT: Duration = Duration::from_secs(900);

/// Epic's sign-in page for the launcher client FabCLI uses. Its redirect shows
/// the authorization code as JSON instead of returning it to a local app, which
/// is why the browser flow needs one paste.
const EPIC_LOGIN_URL: &str = "https://www.epicgames.com/id/login?redirectUrl=https%3A%2F%2Fwww.epicgames.com%2Fid%2Fapi%2Fredirect%3FclientId%3D34a02cf8f4414e29b15921876da36f9a%26responseType%3Dcode";

/// Floor for the library timeout: a cold 1k-item library takes ~100s.
const LIBRARY_MIN_TIMEOUT: Duration = Duration::from_secs(300);

/// Settings the provider needs from configuration.
#[derive(Debug, Clone)]
pub struct FabCliSettings {
    /// Executable to run.
    pub program: PathBuf,
    /// Timeout for ordinary calls.
    pub timeout: Duration,
    /// Timeout for downloads, which are unbounded in size.
    pub download_timeout: Duration,
    /// Semver range this provider accepts.
    pub version_requirement: String,
    /// Enable FabCLI's on-disk library cache.
    pub library_cache: bool,
    /// Echo provider progress to stderr as it arrives.
    pub progress: bool,
}

impl Default for FabCliSettings {
    fn default() -> Self {
        Self {
            program: PathBuf::from("fabcli"),
            timeout: Duration::from_secs(120),
            download_timeout: Duration::from_secs(7200),
            version_requirement: version::SUPPORTED_RANGE.to_string(),
            library_cache: true,
            progress: false,
        }
    }
}

/// FabCLI-backed provider.
pub struct FabCliProvider {
    settings: FabCliSettings,
    /// Version check result, memoised for the process lifetime. A single
    /// necturalabs-fab run must not pay for `--version` more than once.
    verified: RefCell<Option<std::result::Result<semver::Version, FabError>>>,
    /// Include untouched provider payloads on produced assets.
    include_raw: bool,
}

impl FabCliProvider {
    /// Build a provider from settings.
    pub fn new(settings: FabCliSettings) -> Self {
        Self {
            settings,
            verified: RefCell::new(None),
            include_raw: false,
        }
    }

    /// Ask produced assets to carry their untouched provider payload.
    pub fn with_raw(mut self, include_raw: bool) -> Self {
        self.include_raw = include_raw;
        self
    }

    fn exec(&self, timeout: Duration) -> Exec {
        let mut exec = Exec::new(self.settings.program.clone(), timeout)
            // Keep the provider's stderr free of anything but real diagnostics:
            // its update nag and usage tips would otherwise look like errors.
            .with_env("FABCLI_NO_UPDATE_CHECK", "1")
            .with_env("FABCLI_NO_TIPS", "1");
        if self.settings.library_cache {
            exec = exec.with_env("FABCLI_LIBRARY_CACHE", "1");
        }
        if self.settings.progress {
            exec = exec.with_stderr(StderrMode::Tee);
        }
        exec
    }

    /// Run a command and parse its stdout as JSON, mapping any failure.
    fn run_json(&self, args: &[String], timeout: Duration) -> Result<Value> {
        self.ensure_supported_version()?;
        let output = self.exec(timeout).run(args)?;
        self.parse(output, args)
    }

    fn parse(&self, output: Output, args: &[String]) -> Result<Value> {
        if !output.success() {
            return Err(self.error_from(&output, args));
        }
        if output.stdout.trim().is_empty() {
            return Err(FabError::new(
                ErrorCode::ProviderProtocol,
                format!("provider returned no output for '{}'", args.join(" ")),
            )
            .with_provider("fabcli"));
        }
        serde_json::from_str(&output.stdout).map_err(|err| {
            FabError::new(
                ErrorCode::ProviderProtocol,
                format!("provider output was not valid JSON: {err}"),
            )
            .with_hint(
                "run `necturalabs-fab doctor` — this usually means the FabCLI version changed",
            )
            .with_detail(
                "stdoutPreview",
                Value::String(exec::quote_stderr(&output.stdout)),
            )
            .with_provider("fabcli")
        })
    }

    /// Translate a failed invocation into necturalabs-fab's error vocabulary.
    ///
    /// FabCLI reports failures as `{"error":{"kind":...}}` on stderr with a
    /// meaningful exit code. Anything else on a failing exit — a clap usage
    /// error, a panic — means the command line we built is not the one this
    /// FabCLI understands, which is a broken provider contract rather than bad
    /// user input.
    fn error_from(&self, output: &Output, args: &[String]) -> FabError {
        let parsed: Option<Value> = output
            .stderr
            .lines()
            .rev()
            .find(|line| line.trim_start().starts_with('{'))
            .and_then(|line| serde_json::from_str(line).ok());

        let Some(body) = parsed.as_ref().and_then(|v| v.get("error")) else {
            return FabError::new(
                ErrorCode::ProviderProtocol,
                format!(
                    "provider rejected `{} {}` (exit {})",
                    self.settings.program.display(),
                    args.first().cloned().unwrap_or_default(),
                    output
                        .status
                        .map(|c| c.to_string())
                        .unwrap_or_else(|| "signal".into())
                ),
            )
            .with_hint("run `necturalabs-fab doctor` to check the installed FabCLI version")
            .with_detail("stderr", Value::String(exec::quote_stderr(&output.stderr)))
            .with_provider("fabcli");
        };

        let kind = body
            .get("kind")
            .and_then(Value::as_str)
            .unwrap_or("generic");
        // Classification reads the raw message ("expired"); everything that
        // leaves this function is redacted first.
        let raw_message = body
            .get("message")
            .and_then(Value::as_str)
            .unwrap_or("provider reported a failure");
        let lower = raw_message.to_ascii_lowercase();
        let expired = lower.contains("expired");
        let account_session = lower.contains("fab session");
        // FabCLI reports some lost sessions (a keystore key gone, a token from
        // another account) as generic failures whose remedy is signing in.
        let kind = if kind == "generic" && lower.contains("fabcli auth login") {
            "auth_required"
        } else {
            kind
        };
        // Agents must never be told to run the provider directly.
        let message = crate::sanitize::text(&crate::sanitize::redact(raw_message), 400)
            .unwrap_or_else(|| "provider reported a failure".into())
            .replace("'fabcli auth login'", "`necturalabs-fab auth login --run`")
            .replace("fabcli auth login", "necturalabs-fab auth login --run");

        let mut error = match kind {
            "auth_required" => FabError::new(
                if expired {
                    ErrorCode::AuthExpired
                } else {
                    ErrorCode::AuthRequired
                },
                message.clone(),
            )
            .with_hint(if account_session {
                "claiming and ownership need the account session: ask the user to run \
                 `necturalabs-fab auth login --run --account` (it opens a sign-in window)"
            } else {
                "ask the user to run `necturalabs-fab auth login --run` (it opens their browser)"
            })
            .with_detail(
                "session",
                Value::String(if account_session { "account" } else { "reads" }.into()),
            ),
            "not_found" => FabError::new(ErrorCode::NotFound, message.clone())
                .with_hint("check the listing id with `necturalabs-fab search`"),
            "rate_limited" => FabError::new(ErrorCode::RateLimited, message.clone())
                .with_hint("wait ~30s before retrying; avoid parallel provider calls"),
            "network" => FabError::new(ErrorCode::Network, message.clone()),
            // A structured rejection is the provider validating a value we
            // forwarded (a raw --filter, a cursor, a platform name); a flag it
            // does not know arrives as unstructured prose and is handled above.
            "invalid_args" => FabError::new(ErrorCode::InvalidInput, message.clone()).with_hint(
                "the marketplace rejected an argument: check --filter, --cursor, --platform and \
                 --engine-version values",
            ),
            "not_owned" => FabError::new(ErrorCode::NotOwned, message.clone())
                .with_hint("claim it if it is free, or buy it on fab.com, then retry the download"),
            "ambiguous_artifact" => FabError::new(ErrorCode::AmbiguousVariant, message.clone())
                .with_hint("re-run with --engine-version (and --platform if needed)"),
            "output_collision" => FabError::new(ErrorCode::OutputConflict, message.clone())
                .with_hint("use --overwrite force, or choose an empty --out directory"),
            "output_not_empty" => FabError::new(ErrorCode::OutputNotEmpty, message.clone())
                .with_hint("choose an empty --out directory, or drop --overwrite require-empty"),
            _ => FabError::new(ErrorCode::ProviderFailed, message.clone()),
        };

        for key in [
            "uid",
            "available",
            "conflicts",
            "total_conflicts",
            "output_dir",
            "unexpected_entries",
        ] {
            if let Some(value) = body.get(key) {
                let mut value = value.clone();
                crate::sanitize::redact_json(&mut value);
                error = error.with_detail(&camelize(key), value);
            }
        }
        error.with_provider("fabcli")
    }

    /// Verify the installed FabCLI is one we have mapped, once per process.
    fn ensure_supported_version(&self) -> Result<()> {
        if let Some(cached) = self.verified.borrow().as_ref() {
            return cached.as_ref().map(|_| ()).map_err(Clone::clone);
        }
        let result = self.detect_version();
        let stored = match &result {
            Ok(version) => Ok(version.clone()),
            Err(err) => Err(err.clone()),
        };
        *self.verified.borrow_mut() = Some(stored);
        result.map(|_| ())
    }

    fn detect_version(&self) -> Result<semver::Version> {
        let output = self
            .exec(Duration::from_secs(30))
            .with_stderr(StderrMode::Capture)
            .run(&["--version".to_string()])?;
        if !output.success() {
            return Err(FabError::new(
                ErrorCode::ProviderNotInstalled,
                format!(
                    "`{} --version` failed: {}",
                    self.settings.program.display(),
                    exec::quote_stderr(&output.stderr)
                ),
            )
            .with_provider("fabcli"));
        }
        let detected = version::parse_version_output(&output.stdout)?;
        version::check(&detected, &self.settings.version_requirement)?;
        Ok(detected)
    }

    /// Fetch and merge listing formats onto an asset. A formats failure is
    /// recorded as missing coverage, not propagated: a listing is still useful
    /// without its engine matrix.
    fn hydrate_formats(&self, asset: &mut Asset) {
        let args = vec!["formats".to_string(), asset.id.clone()];
        match self.run_json(&args, self.settings.timeout) {
            Ok(formats) => map::apply_formats(asset, &formats),
            Err(_) => {
                asset.coverage.formats = Availability::Unavailable;
                asset.coverage.technical = Availability::Unavailable;
            }
        }
    }

    fn search_args(&self, query: &SearchQuery, free: FreeMode) -> Vec<String> {
        let mut args = vec!["search".to_string()];
        if let Some(text) = &query.text {
            args.push(format!("--query={text}"));
        }
        args.push(format!("--count={}", query.count));
        if let Some(cursor) = &query.cursor {
            args.push(format!("--cursor={cursor}"));
        }
        if let Some(sort) = query.sort {
            args.push(format!("--sort={}", sort_slug(sort)));
        }
        if query.with_ownership {
            args.push("--with-ownership".into());
        }

        let mut filters: Vec<(String, String)> = Vec::new();
        if let Some(engine) = &query.engine {
            match engine.channel_slug() {
                Some(channel) => filters.push(("channels".into(), channel.into())),
                // Engines Fab models as a format rather than a channel.
                None => {
                    if let Some(format) = engine.format_slug() {
                        filters.push(("asset_formats".into(), format.into()));
                    }
                }
            }
        }
        for format in &query.formats {
            filters.push(("asset_formats".into(), format.clone()));
        }
        for category in &query.categories {
            filters.push(("categories".into(), category.clone()));
        }
        for listing_type in &query.listing_types {
            filters.push(("listing_types".into(), listing_type.clone()));
        }
        for style in &query.styles {
            filters.push(("styles".into(), style.clone()));
        }
        for feature in &query.technical_features {
            filters.push(("technical_features".into(), feature.clone()));
        }
        for license in &query.licenses {
            filters.push(("licenses".into(), license.clone()));
        }
        if let Some(seller) = &query.seller {
            filters.push(("seller".into(), seller.clone()));
        }
        match free {
            FreeMode::Permanent => filters.push(("is_free".into(), "1".into())),
            FreeMode::LimitedTime => filters.push(("min_discount_percentage".into(), "100".into())),
            FreeMode::Any | FreeMode::Either => {}
        }
        if let Some(min) = query.min_price {
            filters.push(("min_price".into(), format_price(min)));
        }
        if let Some(max) = query.max_price {
            filters.push(("max_price".into(), format_price(max)));
        }
        if let Some(rating) = query.min_rating {
            filters.push(("min_average_rating".into(), format_rating(rating)));
        }
        if let Some(date) = &query.published_since {
            filters.push(("published_since".into(), date.clone()));
        }
        filters.extend(query.raw_filters.iter().cloned());

        for (key, value) in filters {
            args.push(format!("--filter={key}={value}"));
        }
        args
    }

    fn search_once(&self, query: &SearchQuery, free: FreeMode) -> Result<SearchPage> {
        let args = self.search_args(query, free);
        let raw = self.run_json(&args, self.settings.timeout)?;
        map::search_page(&raw, self.include_raw)
    }
}

/// FabCLI's sort vocabulary. Kept in one place so a provider swap only touches
/// this function.
fn sort_slug(sort: SortOrder) -> &'static str {
    match sort {
        SortOrder::Relevance => "-relevance",
        SortOrder::Newest => "-createdAt",
        SortOrder::Oldest => "createdAt",
        SortOrder::PriceAsc => "price",
        SortOrder::PriceDesc => "-price",
        SortOrder::RatingDesc => "-ratings.averageRating",
        SortOrder::DiscountDesc => "-min_discount_percentage",
        SortOrder::TitleAsc => "title",
    }
}

fn format_rating(value: f64) -> String {
    if (value.fract()).abs() < f64::EPSILON {
        format!("{}", value as i64)
    } else {
        format!("{value}")
    }
}

fn format_price(value: crate::model::Amount) -> String {
    let text = value.to_string();
    let trimmed = text.trim_end_matches('0').trim_end_matches('.');
    trimmed.to_string()
}

fn camelize(key: &str) -> String {
    let mut out = String::with_capacity(key.len());
    let mut upper = false;
    for ch in key.chars() {
        if ch == '_' {
            upper = true;
            continue;
        }
        if upper {
            out.extend(ch.to_uppercase());
            upper = false;
        } else {
            out.push(ch);
        }
    }
    out
}

/// FabCLI's `--engine` expects Epic's `UE_x.y` label.
pub fn epic_engine_label(version: &str) -> String {
    let trimmed = version.trim();
    if trimmed.to_ascii_uppercase().starts_with("UE_") {
        return trimmed.to_ascii_uppercase();
    }
    let digits = crate::model::normalize_engine_version(trimmed);
    if digits.is_empty() {
        trimmed.to_string()
    } else {
        format!("UE_{digits}")
    }
}

impl FabProvider for FabCliProvider {
    fn id(&self) -> &'static str {
        "fabcli"
    }

    fn capabilities(&self) -> Capabilities {
        Capabilities {
            search: true,
            search_ownership: true,
            listing_detail: true,
            formats: true,
            technical_metadata: true,
            ownership: true,
            library: true,
            download: true,
            // FabCLI fetches chunks to a temp directory and reassembles; an
            // interrupted run restarts. Do not advertise resume.
            download_resume: false,
            claim_free: true,
            purchase: false,
            auth_status: true,
            interactive_login: true,
        }
    }

    fn health(&self) -> Result<ProviderHealth> {
        let executable = exec::which(&self.settings.program)
            .map(|p| p.display().to_string())
            .or_else(|| Some(self.settings.program.display().to_string()));
        let mut health = ProviderHealth {
            provider: "fabcli".into(),
            supported_range: Some(self.settings.version_requirement.clone()),
            executable,
            ..Default::default()
        };
        match self.detect_version() {
            Ok(version) => {
                health.version = Some(version.to_string());
                health.version_supported = Some(true);
            }
            Err(err) if err.code == ErrorCode::ProviderUnsupportedVersion => {
                health.version = err
                    .details
                    .get("detected")
                    .and_then(Value::as_str)
                    .map(str::to_string);
                health.version_supported = Some(false);
                health.notes.push(err.message.clone());
            }
            Err(err) => {
                health.version_supported = None;
                health.notes.push(err.message.clone());
                return Err(err);
            }
        }
        Ok(health)
    }

    fn auth_status(&self) -> Result<AuthStatus> {
        match self.run_json(
            &["auth".to_string(), "status".to_string()],
            self.settings.timeout,
        ) {
            Ok(raw) => Ok(map::auth_status(&raw)),
            // Signed out is a state, not a failure, for a status query.
            Err(err) if matches!(err.code, ErrorCode::AuthRequired | ErrorCode::AuthExpired) => {
                Ok(AuthStatus {
                    authenticated: false,
                    needs_reauth: true,
                    ..Default::default()
                })
            }
            Err(err) => Err(err),
        }
    }

    /// Marketplace search.
    ///
    /// `owned_only` is not handled here: it is a library intersection, which
    /// the command layer resolves. `engine_version` is likewise a post-filter,
    /// because Fab exposes no server-side engine-version filter.
    fn search(&self, query: &SearchQuery) -> Result<SearchPage> {
        query.validate()?;
        if query.free != FreeMode::Either {
            return self.search_once(query, query.free);
        }

        // "Free" spans two disjoint marketplace buckets. Query both and merge
        // deterministically: permanently-free first, then limited-time, each
        // in provider order, duplicates dropped.
        let mut page = self.search_once(query, FreeMode::Permanent)?;
        let promos = self.search_once(query, FreeMode::LimitedTime)?;
        let seen: std::collections::HashSet<String> =
            page.assets.iter().map(|a| a.id.clone()).collect();
        page.assets
            .extend(promos.assets.into_iter().filter(|a| !seen.contains(&a.id)));
        page.total = None;
        page.next_cursor = None;
        Ok(page)
    }

    fn listing(&self, listing_id: &str, with_formats: bool) -> Result<Asset> {
        let listing_id = &validate_listing_id(listing_id)?;
        let args = vec!["listing".to_string(), listing_id.to_string()];
        let raw = self.run_json(&args, self.settings.timeout)?;
        let mut asset = map::listing_detail(&raw, self.include_raw)?;
        if with_formats {
            self.hydrate_formats(&mut asset);
        }
        Ok(asset)
    }

    fn ownership(&self, listing_ids: &[String]) -> Result<Vec<Ownership>> {
        let listing_ids = listing_ids
            .iter()
            .map(|id| validate_listing_id(id))
            .collect::<Result<Vec<_>>>()?;
        if listing_ids.is_empty() {
            return Ok(Vec::new());
        }
        let args = if listing_ids.len() == 1 {
            vec!["ownership".to_string(), listing_ids[0].clone()]
        } else {
            vec![
                "ownership".to_string(),
                format!("--batch={}", listing_ids.join(",")),
            ]
        };
        let raw = self.run_json(&args, self.settings.timeout)?;
        map::ownership_response(&raw)
    }

    fn library(&self) -> Result<Vec<Asset>> {
        let timeout = self.settings.timeout.max(LIBRARY_MIN_TIMEOUT);
        let args = vec![
            "library".to_string(),
            "--count".to_string(),
            LIBRARY_PAGE_SIZE.to_string(),
        ];
        let raw = self.run_json(&args, timeout)?;
        map::library_assets(&raw, self.include_raw)
    }

    fn download(&self, request: &DownloadRequest) -> Result<DownloadReceipt> {
        validate_listing_id(&request.listing_id)?;
        if request.dry_run {
            return self.plan_download(request);
        }
        let mut args = vec![
            "download".to_string(),
            request.listing_id.clone(),
            format!("--output={}", request.output_dir.display()),
        ];
        if let Some(version) = &request.engine_version {
            args.push(format!("--engine={}", epic_engine_label(version)));
        }
        if let Some(platform) = &request.platform {
            args.push(format!("--platform={platform}"));
        }
        if let Some(jobs) = request.jobs {
            args.push(format!("--jobs={jobs}"));
        }
        match request.overwrite {
            OverwritePolicy::Force => args.push("--force".into()),
            OverwritePolicy::RequireEmpty => args.push("--into-empty".into()),
            OverwritePolicy::Refuse => {}
        }

        let raw = self.run_json(&args, self.settings.download_timeout)?;
        let sidecar = raw
            .get("sidecar")
            .and_then(Value::as_str)
            .map(str::to_string);
        let mut receipt = DownloadReceipt {
            listing_id: request.listing_id.clone(),
            output_dir: request.output_dir.clone(),
            files: raw.get("files").and_then(Value::as_u64),
            bytes: raw.get("total_bytes").and_then(Value::as_u64),
            elapsed_seconds: raw.get("elapsed_seconds").and_then(Value::as_f64),
            provider_sidecar: sidecar.clone(),
            ..Default::default()
        };
        // Only a bare file name inside the output directory is trusted.
        if let Some(name) =
            sidecar.filter(|n| Path::new(n).file_name() == Some(std::ffi::OsStr::new(n)))
        {
            read_provider_sidecar(&request.output_dir.join(name), &mut receipt);
        }
        Ok(receipt)
    }

    fn claim_free(&self, listing_id: &str) -> Result<ClaimOutcome> {
        let listing_id = &validate_listing_id(listing_id)?;
        let args = vec!["claim".to_string(), listing_id.to_string()];
        let raw = self.run_json(&args, self.settings.timeout)?;
        map::claim_outcome(&raw, listing_id)
    }

    fn login(&self, scope: LoginScope) -> Result<AuthStatus> {
        self.ensure_supported_version()?;
        let args: Vec<String> = match scope {
            // FabCLI's paste flow: opens the default browser on Epic's
            // sign-in page and reads the authorization code from the terminal.
            LoginScope::Reads => vec!["auth".into(), "login".into(), "--manual".into()],
            // FabCLI's embedded window, the only way to obtain the Fab web
            // session that claiming and ownership need.
            LoginScope::Account => vec!["auth".into(), "login".into()],
        };
        let output = self
            .exec(LOGIN_TIMEOUT)
            .with_stderr(StderrMode::Tee)
            .with_inherited_stdin()
            .run(&args)?;
        if !output.success() {
            return Err(self.error_from(&output, &args));
        }
        self.auth_status()
    }

    fn login_hint(&self, scope: LoginScope) -> Option<String> {
        Some(match scope {
            LoginScope::Reads => format!(
                "Your browser opens Epic's sign-in page. After signing in, the page shows a short \
                 JSON response: copy the value of \"authorizationCode\" and paste it here.\n\
                 If no browser opens, visit: {EPIC_LOGIN_URL}"
            ),
            LoginScope::Account => "A sign-in window opens for Fab. Sign in to Epic in it, and \
                 approve Fab if it asks. Claiming and ownership checks need this session; it lasts \
                 about 90 days."
                .to_string(),
        })
    }
}

impl FabCliProvider {
    /// Dry-run support.
    ///
    /// FabCLI has no dry-run mode and will not reveal a manifest for a listing
    /// without downloading it, so the plan reports what can be established
    /// without writing: that the listing resolves, which variants exist, and
    /// what the output directory's current state means for the chosen
    /// overwrite policy. File and byte counts stay `None` rather than guessed.
    fn plan_download(&self, request: &DownloadRequest) -> Result<DownloadReceipt> {
        let asset = self.listing(&request.listing_id, true)?;
        Ok(DownloadReceipt {
            listing_id: request.listing_id.clone(),
            output_dir: request.output_dir.clone(),
            files: None,
            bytes: None,
            elapsed_seconds: None,
            provider_sidecar: None,
            title: asset.title.clone(),
            engine_versions: asset.engine_versions.clone(),
            platforms: asset.platforms.clone(),
        })
    }
}

/// Fold FabCLI's `.fabcli-asset.json` sidecar into the receipt.
fn read_provider_sidecar(path: &Path, receipt: &mut DownloadReceipt) {
    let Ok(text) = std::fs::read_to_string(path) else {
        return;
    };
    let Ok(value) = serde_json::from_str::<Value>(&text) else {
        return;
    };
    receipt.title = value
        .get("title")
        .and_then(Value::as_str)
        .and_then(crate::sanitize::short);
    if let Some(versions) = value.get("engine_versions").and_then(Value::as_array) {
        receipt.engine_versions = versions
            .iter()
            .filter_map(|v| v.as_str().and_then(crate::sanitize::short))
            .collect();
    }
    if let Some(platforms) = value.get("platforms").and_then(Value::as_array) {
        receipt.platforms = platforms
            .iter()
            .filter_map(|v| v.as_str().and_then(crate::sanitize::short))
            .collect();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Engine;

    fn provider() -> FabCliProvider {
        FabCliProvider::new(FabCliSettings::default())
    }

    #[test]
    fn search_args_map_the_whole_query_vocabulary() {
        let mut query = SearchQuery::new().with_text("ruined castle");
        query.engine = Some(Engine::Unreal);
        query.free = FreeMode::Permanent;
        query.styles = vec!["realistic".into()];
        query.technical_features = vec!["rigged".into()];
        query.licenses = vec!["cc-by".into()];
        query.listing_types = vec!["3d-model".into()];
        query.categories = vec!["environments".into()];
        query.seller = Some("ACME".into());
        query.min_price = crate::model::Amount::parse("0");
        query.max_price = crate::model::Amount::parse("20.5");
        query.min_rating = Some(4.0);
        query.published_since = Some("2026-04-01".into());
        query.sort = Some(SortOrder::Newest);
        query.count = 10;
        query.with_ownership = true;
        query.raw_filters = vec![("experimental_key".into(), "1".into())];

        let args = provider().search_args(&query, query.free);
        // Every value travels in `--flag=value` form, so none can be read as a
        // flag of its own even if it starts with '-'.
        assert!(
            args.iter()
                .skip(1)
                .all(|a| a.starts_with("--") && (a.contains('=') || a == "--with-ownership")),
            "{args:?}"
        );
        let joined = args.join(" ");
        assert!(joined.contains("--query=ruined castle"));
        assert!(joined.contains("--count=10"));
        assert!(joined.contains("--sort=-createdAt"));
        assert!(joined.contains("--with-ownership"));
        assert!(joined.contains("channels=unreal-engine"));
        assert!(joined.contains("is_free=1"));
        assert!(joined.contains("styles=realistic"));
        assert!(joined.contains("technical_features=rigged"));
        assert!(joined.contains("licenses=cc-by"));
        assert!(joined.contains("listing_types=3d-model"));
        assert!(joined.contains("categories=environments"));
        assert!(joined.contains("seller=ACME"));
        assert!(joined.contains("min_price=0"));
        assert!(joined.contains("max_price=20.5"));
        assert!(joined.contains("min_average_rating=4"));
        assert!(joined.contains("published_since=2026-04-01"));
        assert!(joined.contains("experimental_key=1"));
    }

    #[test]
    fn engines_without_a_channel_become_a_format_filter() {
        let mut query = SearchQuery::new();
        query.engine = Some(Engine::Godot);
        let args = provider().search_args(&query, FreeMode::Any).join(" ");
        assert!(args.contains("asset_formats=godot"), "{args}");
        assert!(!args.contains("channels="), "{args}");
    }

    #[test]
    fn limited_time_free_uses_the_discount_filter_not_is_free() {
        let query = SearchQuery::new();
        let args = provider()
            .search_args(&query, FreeMode::LimitedTime)
            .join(" ");
        assert!(args.contains("min_discount_percentage=100"));
        assert!(!args.contains("is_free"));
    }

    #[test]
    fn epic_engine_labels_are_normalized() {
        assert_eq!(epic_engine_label("5.4"), "UE_5.4");
        assert_eq!(epic_engine_label("UE_5.4"), "UE_5.4");
        assert_eq!(epic_engine_label("ue5.4"), "UE_5.4");
    }

    #[test]
    fn provider_never_advertises_purchase() {
        assert!(!provider().capabilities().purchase);
    }

    #[test]
    fn structured_provider_errors_map_to_our_codes() {
        let cases = [
            (
                "auth_required",
                "no session — run 'fabcli auth login' first",
                ErrorCode::AuthRequired,
            ),
            (
                "auth_required",
                "Fab session expired. Run login",
                ErrorCode::AuthExpired,
            ),
            ("not_found", "listing missing", ErrorCode::NotFound),
            ("rate_limited", "slow down", ErrorCode::RateLimited),
            ("network", "dns failure", ErrorCode::Network),
            ("not_owned", "not in library", ErrorCode::NotOwned),
            (
                "ambiguous_artifact",
                "pick one",
                ErrorCode::AmbiguousVariant,
            ),
            ("output_collision", "3 conflicts", ErrorCode::OutputConflict),
            (
                "output_not_empty",
                "dir has content",
                ErrorCode::OutputNotEmpty,
            ),
            ("generic", "something broke", ErrorCode::ProviderFailed),
            ("invalid_args", "bad flag", ErrorCode::InvalidInput),
        ];
        for (kind, message, expected) in cases {
            let output = Output {
                status: Some(1),
                stdout: String::new(),
                stderr: format!("{{\"error\":{{\"kind\":\"{kind}\",\"message\":\"{message}\"}}}}"),
                elapsed: Duration::from_millis(1),
            };
            let err = provider().error_from(&output, &["search".to_string()]);
            assert_eq!(err.code, expected, "kind {kind}");
            assert_eq!(err.provider.as_deref(), Some("fabcli"));
        }
    }

    #[test]
    fn structured_error_details_are_carried_over_camelized() {
        let stderr = r#"{"error":{"kind":"ambiguous_artifact","message":"pick","uid":"u1","available":[{"engine_versions":["UE_5.4"],"target_platforms":["Windows"]}]}}"#;
        let output = Output {
            status: Some(6),
            stdout: String::new(),
            stderr: stderr.to_string(),
            elapsed: Duration::from_millis(1),
        };
        let err = provider().error_from(&output, &["download".to_string()]);
        assert_eq!(err.code, ErrorCode::AmbiguousVariant);
        assert_eq!(err.details["uid"], "u1");
        assert_eq!(err.details["available"][0]["engine_versions"][0], "UE_5.4");
    }

    #[test]
    fn unstructured_failure_is_a_contract_break_not_user_error() {
        let output = Output {
            status: Some(6),
            stdout: String::new(),
            stderr: "error: unrecognized subcommand 'searchh'\n\nUsage: fabcli [OPTIONS]".into(),
            elapsed: Duration::from_millis(1),
        };
        let err = provider().error_from(&output, &["searchh".to_string()]);
        assert_eq!(err.code, ErrorCode::ProviderProtocol);
        assert_eq!(err.code.exit_code(), 7);
        assert!(err.details.contains_key("stderr"));
    }

    #[test]
    fn empty_stdout_on_success_is_a_protocol_error() {
        let output = Output {
            status: Some(0),
            stdout: "   \n".into(),
            stderr: String::new(),
            elapsed: Duration::from_millis(1),
        };
        let err = provider()
            .parse(output, &["search".to_string()])
            .unwrap_err();
        assert_eq!(err.code, ErrorCode::ProviderProtocol);
    }

    #[test]
    fn malformed_json_on_success_is_a_protocol_error_with_a_preview() {
        let output = Output {
            status: Some(0),
            stdout: "{not json".into(),
            stderr: String::new(),
            elapsed: Duration::from_millis(1),
        };
        let err = provider()
            .parse(output, &["search".to_string()])
            .unwrap_err();
        assert_eq!(err.code, ErrorCode::ProviderProtocol);
        assert!(err.details.contains_key("stdoutPreview"));
    }
}
