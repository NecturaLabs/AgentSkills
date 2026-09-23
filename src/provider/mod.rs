//! The provider contract.
//!
//! Everything above this module depends only on these types. A provider is any
//! implementation that can answer them — today the FabCLI subprocess, tomorrow
//! a native Fab client — and swapping one for another must not change a single
//! byte of what agents parse.
//!
//! Providers advertise what they can do through [`Capabilities`] rather than
//! being assumed to implement everything; the default trait methods return
//! [`ErrorCode::UnsupportedCapability`] so a partial provider is legal.

pub mod fabcli;

use crate::error::{ErrorCode, FabError, Result};
use crate::model::{Asset, Ownership};
use crate::query::SearchQuery;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// What a provider implementation supports.
///
/// `purchase` exists so the contract can *say* that nothing may buy anything.
/// necturalabs-fab refuses to route a monetary operation regardless of what a
/// provider claims here; see `crate::approval`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Capabilities {
    /// Marketplace search.
    pub search: bool,
    /// Search results can be decorated with ownership state in one call.
    pub search_ownership: bool,
    /// Single-listing detail lookup.
    pub listing_detail: bool,
    /// Per-listing format/engine-version data.
    pub formats: bool,
    /// Technical metadata (poly counts, texture sizes, ...) in any form.
    pub technical_metadata: bool,
    /// Ownership lookup for arbitrary listing ids.
    pub ownership: bool,
    /// Full library enumeration.
    pub library: bool,
    /// Download of an owned asset.
    pub download: bool,
    /// Downloads resume after an interruption.
    pub download_resume: bool,
    /// Claiming a free asset into the library.
    pub claim_free: bool,
    /// Purchasing. Always false for every shipped provider.
    pub purchase: bool,
    /// Session status reporting.
    pub auth_status: bool,
    /// Interactive sign-in.
    pub interactive_login: bool,
}

impl Capabilities {
    /// No capabilities at all — a starting point for new providers.
    pub const NONE: Self = Self {
        search: false,
        search_ownership: false,
        listing_detail: false,
        formats: false,
        technical_metadata: false,
        ownership: false,
        library: false,
        download: false,
        download_resume: false,
        claim_free: false,
        purchase: false,
        auth_status: false,
        interactive_login: false,
    };

    /// Error for an operation this provider does not implement.
    pub fn unsupported(provider: &str, operation: &str) -> FabError {
        FabError::new(
            ErrorCode::UnsupportedCapability,
            format!("provider '{provider}' does not support {operation}"),
        )
        .with_hint("run `necturalabs-fab capabilities` to see what the active provider supports")
        .with_provider(provider)
    }
}

/// One page of search results.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchPage {
    /// Results in provider order (the marketplace's own relevance ranking).
    pub assets: Vec<Asset>,
    /// Total matches the marketplace reports, when it reports one.
    pub total: Option<u64>,
    /// Cursor for the next page, when there is one.
    pub next_cursor: Option<String>,
}

/// What to do when the download target already holds files.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum OverwritePolicy {
    /// Fail if any file would be overwritten. The default.
    #[default]
    Refuse,
    /// Overwrite colliding files.
    Force,
    /// Fail unless the directory is empty.
    RequireEmpty,
}

impl OverwritePolicy {
    /// Parse a CLI/config value.
    pub fn parse(raw: &str) -> Result<Self> {
        Ok(match raw.trim().to_ascii_lowercase().as_str() {
            "refuse" | "never" => Self::Refuse,
            "force" | "overwrite" => Self::Force,
            "require-empty" | "into-empty" | "empty" => Self::RequireEmpty,
            other => {
                return Err(FabError::invalid(format!(
                    "unknown overwrite policy '{other}' (expected: refuse, force, require-empty)"
                )))
            }
        })
    }
}

/// A request to place an owned asset's files on disk.
#[derive(Debug, Clone)]
pub struct DownloadRequest {
    /// Listing to download.
    pub listing_id: String,
    /// Destination directory. Created if missing.
    pub output_dir: PathBuf,
    /// Engine version to pick when the listing ships several.
    pub engine_version: Option<String>,
    /// Platform to pick when the listing ships several.
    pub platform: Option<String>,
    /// Collision handling.
    pub overwrite: OverwritePolicy,
    /// Parallel chunk workers, when the provider supports tuning it.
    pub jobs: Option<u32>,
    /// Report what would happen and write nothing.
    pub dry_run: bool,
}

/// The result of a completed download.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DownloadReceipt {
    /// Listing that was downloaded.
    pub listing_id: String,
    /// Absolute output directory.
    pub output_dir: PathBuf,
    /// Number of files written.
    pub files: Option<u64>,
    /// Bytes written.
    pub bytes: Option<u64>,
    /// Wall-clock seconds the provider reported.
    pub elapsed_seconds: Option<f64>,
    /// Provider-written metadata file inside `output_dir`, if any.
    pub provider_sidecar: Option<String>,
    /// Asset title as recorded by the provider.
    pub title: Option<String>,
    /// Engine versions the downloaded files target.
    pub engine_versions: Vec<String>,
    /// Platforms the downloaded files target.
    pub platforms: Vec<String>,
    /// Licences the listing is offered under, when established.
    pub licenses: Vec<String>,
}

/// The result of a free-asset claim.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaimOutcome {
    /// Listing that was claimed.
    pub listing_id: String,
    /// True when this call added the asset to the library.
    pub claimed: bool,
    /// True when the asset was already in the library and nothing changed.
    pub already_owned: bool,
    /// Asset title, when the provider reported one.
    pub title: Option<String>,
}

/// Session state, with no secret material in it.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthStatus {
    /// Whether read operations will work.
    pub authenticated: bool,
    /// Expiry of the read session, as the provider reports it.
    pub expires_at: Option<String>,
    /// Whether account-mutating operations (claim, rich ownership) will work.
    pub account_actions_available: bool,
    /// Expiry of the account-action session.
    pub account_session_expires_at: Option<String>,
    /// Days left on the account-action session.
    pub account_session_days_remaining: Option<i64>,
    /// Whether the provider wants the user to sign in again soon.
    pub needs_reauth: bool,
}

/// Which session a sign-in establishes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum LoginScope {
    /// Marketplace reads: search, listing detail, library, download.
    Reads,
    /// Account actions: claiming free assets and ownership checks.
    Account,
}

/// Provider identity and reachability, for `doctor`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderHealth {
    /// Provider id.
    pub provider: String,
    /// Backing implementation version, when discoverable.
    pub version: Option<String>,
    /// Version range necturalabs-fab supports.
    pub supported_range: Option<String>,
    /// Whether `version` satisfies `supported_range`.
    pub version_supported: Option<bool>,
    /// Resolved executable or endpoint, when the provider has one.
    pub executable: Option<String>,
    /// Non-fatal observations.
    pub notes: Vec<String>,
}

/// The operations necturalabs-fab knows how to ask for.
///
/// Implementations must be side-effect free except for [`Self::download`]
/// (local writes) and [`Self::claim_free`] (account mutation). There is
/// deliberately no purchase method: adding one would be a change to this
/// contract, reviewable on its own.
pub trait FabProvider {
    /// Stable provider id, e.g. `fabcli`.
    fn id(&self) -> &'static str;

    /// What this implementation supports.
    fn capabilities(&self) -> Capabilities;

    /// Identity, version and reachability. Must not fail merely because the
    /// user is signed out.
    fn health(&self) -> Result<ProviderHealth>;

    /// Session state.
    fn auth_status(&self) -> Result<AuthStatus> {
        Err(Capabilities::unsupported(self.id(), "auth status"))
    }

    /// Search the marketplace.
    fn search(&self, _query: &SearchQuery) -> Result<SearchPage> {
        Err(Capabilities::unsupported(self.id(), "search"))
    }

    /// Full detail for one listing. `with_formats` asks for the extra
    /// round-trip that fills engines, versions and technical metadata.
    fn listing(&self, _listing_id: &str, _with_formats: bool) -> Result<Asset> {
        Err(Capabilities::unsupported(self.id(), "listing detail"))
    }

    /// Ownership state for one or more listings.
    fn ownership(&self, _listing_ids: &[String]) -> Result<Vec<Ownership>> {
        Err(Capabilities::unsupported(self.id(), "ownership lookup"))
    }

    /// Every asset in the authenticated account's library.
    fn library(&self) -> Result<Vec<Asset>> {
        Err(Capabilities::unsupported(self.id(), "library enumeration"))
    }

    /// Place an owned asset's files on disk.
    fn download(&self, _request: &DownloadRequest) -> Result<DownloadReceipt> {
        Err(Capabilities::unsupported(self.id(), "download"))
    }

    /// Add a free asset to the library. Implementations must verify the asset
    /// is free themselves; the caller has already done so, and both checks are
    /// intentional.
    fn claim_free(&self, _listing_id: &str) -> Result<ClaimOutcome> {
        Err(Capabilities::unsupported(self.id(), "claim"))
    }

    /// Sign in interactively. Only ever called on a human's explicit request:
    /// it opens a browser or window and may read from the terminal.
    fn login(&self, _scope: LoginScope) -> Result<AuthStatus> {
        Err(Capabilities::unsupported(self.id(), "interactive sign-in"))
    }

    /// What the human should expect before [`Self::login`] runs.
    fn login_hint(&self, _scope: LoginScope) -> Option<String> {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Minimal;

    impl FabProvider for Minimal {
        fn id(&self) -> &'static str {
            "minimal"
        }
        fn capabilities(&self) -> Capabilities {
            Capabilities {
                search: true,
                ..Capabilities::NONE
            }
        }
        fn health(&self) -> Result<ProviderHealth> {
            Ok(ProviderHealth {
                provider: "minimal".into(),
                ..Default::default()
            })
        }
    }

    #[test]
    fn unimplemented_operations_report_unsupported_not_failure() {
        let provider = Minimal;
        let err = provider.library().unwrap_err();
        assert_eq!(err.code, ErrorCode::UnsupportedCapability);
        assert_eq!(err.code.exit_code(), 13);
        assert!(err.message.contains("minimal"));
    }

    #[test]
    fn a_provider_may_implement_only_part_of_the_contract() {
        let provider = Minimal;
        assert!(provider.capabilities().search);
        assert!(!provider.capabilities().purchase);
        assert!(provider.health().is_ok());
    }

    #[test]
    fn overwrite_policy_parsing_is_closed() {
        assert_eq!(
            OverwritePolicy::parse("force").unwrap(),
            OverwritePolicy::Force
        );
        assert_eq!(
            OverwritePolicy::parse("into-empty").unwrap(),
            OverwritePolicy::RequireEmpty
        );
        assert!(OverwritePolicy::parse("yolo").is_err());
    }
}
