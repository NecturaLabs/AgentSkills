//! Stable error contract.
//!
//! Every failure an agent can observe is one of [`ErrorCode`]'s variants. The
//! string form of a code and its exit code are part of the public interface:
//! changing either is a breaking change for callers that branch on them.

use serde::Serialize;
use serde_json::{Map, Value};
use std::fmt;

/// Machine-readable failure classes. The `FAB_` string is what agents branch on.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorCode {
    /// Unexpected internal failure in necturalabs-fab itself.
    Internal,
    /// No credentials at all; the user must sign in.
    AuthRequired,
    /// Credentials exist but are no longer valid.
    AuthExpired,
    /// The listing, library entry or resource does not exist.
    NotFound,
    /// The listing exists but the provider cannot serve it right now.
    ListingUnavailable,
    /// Upstream asked us to slow down.
    RateLimited,
    /// Transport-level failure reaching the marketplace.
    Network,
    /// The caller passed something necturalabs-fab rejects.
    InvalidInput,
    /// Configuration file or environment is malformed.
    ConfigInvalid,
    /// The provider executable is not installed or not on PATH.
    ProviderNotInstalled,
    /// The provider is installed but its version is outside the supported range.
    ProviderUnsupportedVersion,
    /// The provider emitted something we cannot parse: broken contract.
    ProviderProtocol,
    /// The provider ran and failed for a reason it did not classify.
    ProviderFailed,
    /// The provider did not finish inside the configured timeout.
    Timeout,
    /// An account-mutating action was requested without approval.
    ApprovalRequired,
    /// A monetary action was requested. Never permitted.
    MonetaryBlocked,
    /// A claim was attempted against a listing that is not free.
    AssetNotFree,
    /// The asset must be in the account's library before this action.
    NotOwned,
    /// Several asset variants match; the caller must disambiguate.
    AmbiguousVariant,
    /// Writing would overwrite existing files.
    OutputConflict,
    /// `--overwrite require-empty` was requested and the directory has content.
    OutputNotEmpty,
    /// The filesystem refused the write.
    PermissionDenied,
    /// A local write failed for another reason.
    DownloadFailed,
    /// The active provider does not implement this operation.
    UnsupportedCapability,
}

impl ErrorCode {
    /// Stable string form, e.g. `FAB_AUTH_REQUIRED`.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Internal => "FAB_INTERNAL",
            Self::AuthRequired => "FAB_AUTH_REQUIRED",
            Self::AuthExpired => "FAB_AUTH_EXPIRED",
            Self::NotFound => "FAB_NOT_FOUND",
            Self::ListingUnavailable => "FAB_LISTING_UNAVAILABLE",
            Self::RateLimited => "FAB_RATE_LIMITED",
            Self::Network => "FAB_NETWORK",
            Self::InvalidInput => "FAB_INVALID_INPUT",
            Self::ConfigInvalid => "FAB_CONFIG_INVALID",
            Self::ProviderNotInstalled => "FAB_PROVIDER_NOT_INSTALLED",
            Self::ProviderUnsupportedVersion => "FAB_PROVIDER_UNSUPPORTED_VERSION",
            Self::ProviderProtocol => "FAB_PROVIDER_PROTOCOL",
            Self::ProviderFailed => "FAB_PROVIDER_FAILED",
            Self::Timeout => "FAB_TIMEOUT",
            Self::ApprovalRequired => "FAB_APPROVAL_REQUIRED",
            Self::MonetaryBlocked => "FAB_MONETARY_BLOCKED",
            Self::AssetNotFree => "FAB_ASSET_NOT_FREE",
            Self::NotOwned => "FAB_NOT_OWNED",
            Self::AmbiguousVariant => "FAB_AMBIGUOUS_VARIANT",
            Self::OutputConflict => "FAB_OUTPUT_CONFLICT",
            Self::OutputNotEmpty => "FAB_OUTPUT_NOT_EMPTY",
            Self::PermissionDenied => "FAB_PERMISSION_DENIED",
            Self::DownloadFailed => "FAB_DOWNLOAD_FAILED",
            Self::UnsupportedCapability => "FAB_UNSUPPORTED_CAPABILITY",
        }
    }

    /// Process exit code. The published table is
    /// `skills/fab/references/errors.md`.
    pub const fn exit_code(self) -> i32 {
        match self {
            Self::Internal | Self::ProviderFailed | Self::DownloadFailed => 1,
            Self::AuthRequired | Self::AuthExpired => 2,
            Self::NotFound | Self::ListingUnavailable => 3,
            Self::RateLimited => 4,
            Self::Network => 5,
            Self::InvalidInput | Self::ConfigInvalid => 6,
            Self::ProviderNotInstalled
            | Self::ProviderUnsupportedVersion
            | Self::ProviderProtocol => 7,
            Self::ApprovalRequired => 8,
            Self::MonetaryBlocked | Self::AssetNotFree => 9,
            Self::OutputConflict | Self::OutputNotEmpty | Self::PermissionDenied => 10,
            Self::AmbiguousVariant => 11,
            Self::NotOwned => 12,
            Self::UnsupportedCapability => 13,
            Self::Timeout => 14,
        }
    }

    /// Whether a human or agent can plausibly fix this and retry.
    pub const fn recoverable(self) -> bool {
        !matches!(self, Self::Internal | Self::ProviderProtocol)
    }

    /// Whether repeating the identical call later may succeed without any change.
    pub const fn retryable(self) -> bool {
        matches!(
            self,
            Self::RateLimited | Self::Network | Self::Timeout | Self::ListingUnavailable
        )
    }
}

impl fmt::Display for ErrorCode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// A failure with everything a caller needs to decide what to do next.
#[derive(Debug, Clone)]
pub struct FabError {
    /// Machine-readable class.
    pub code: ErrorCode,
    /// One sentence, no ANSI, no secrets.
    pub message: String,
    /// Concrete next action, when one exists.
    pub hint: Option<String>,
    /// Structured extras (available variants, conflicting paths, ...). Boxed
    /// so `Result<T, FabError>` stays small on the happy path.
    pub details: Box<Map<String, Value>>,
    /// Which provider produced it, when it came from one.
    pub provider: Option<String>,
}

impl FabError {
    /// Build an error with just a code and message.
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            hint: None,
            details: Box::default(),
            provider: None,
        }
    }

    /// Attach the recommended next action.
    pub fn with_hint(mut self, hint: impl Into<String>) -> Self {
        self.hint = Some(hint.into());
        self
    }

    /// Attach one structured detail field.
    pub fn with_detail(mut self, key: &str, value: Value) -> Self {
        self.details.insert(key.to_string(), value);
        self
    }

    /// Record which provider the failure came from.
    pub fn with_provider(mut self, provider: impl Into<String>) -> Self {
        self.provider = Some(provider.into());
        self
    }

    /// Convenience constructor for the common invalid-input case.
    pub fn invalid(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::InvalidInput, message)
    }

    /// Convenience constructor for internal invariants.
    pub fn internal(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::Internal, message)
    }

    /// Serialized error body used inside the response envelope.
    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("code".into(), Value::String(self.code.as_str().into()));
        map.insert("message".into(), Value::String(self.message.clone()));
        map.insert("recoverable".into(), Value::Bool(self.code.recoverable()));
        map.insert("retryable".into(), Value::Bool(self.code.retryable()));
        if let Some(hint) = &self.hint {
            map.insert("hint".into(), Value::String(hint.clone()));
        }
        if let Some(provider) = &self.provider {
            map.insert("provider".into(), Value::String(provider.clone()));
        }
        if !self.details.is_empty() {
            map.insert("details".into(), Value::Object((*self.details).clone()));
        }
        Value::Object(map)
    }
}

impl fmt::Display for FabError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.code, self.message)
    }
}

impl std::error::Error for FabError {}

impl From<std::io::Error> for FabError {
    fn from(err: std::io::Error) -> Self {
        let code = match err.kind() {
            std::io::ErrorKind::PermissionDenied => ErrorCode::PermissionDenied,
            // A missing local path is a problem with what was asked for, not a
            // missing marketplace listing (FAB_NOT_FOUND).
            std::io::ErrorKind::NotFound => ErrorCode::InvalidInput,
            _ => ErrorCode::Internal,
        };
        Self::new(code, err.to_string())
    }
}

impl From<serde_json::Error> for FabError {
    fn from(err: serde_json::Error) -> Self {
        Self::new(ErrorCode::Internal, format!("JSON handling failed: {err}"))
    }
}

/// Result alias used throughout the crate.
pub type Result<T> = std::result::Result<T, FabError>;

/// How a command's effects are classified for the approval model.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum ActionClass {
    /// Reads marketplace or account state. No side effects.
    Read,
    /// Writes to the local filesystem only.
    LocalWrite,
    /// Changes the Fab/Epic account (library membership, wishlist, ...).
    AccountMutation,
    /// Spends money. necturalabs-fab never performs one.
    Monetary,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_code_has_a_distinct_string() {
        let codes = [
            ErrorCode::Internal,
            ErrorCode::AuthRequired,
            ErrorCode::AuthExpired,
            ErrorCode::NotFound,
            ErrorCode::ListingUnavailable,
            ErrorCode::RateLimited,
            ErrorCode::Network,
            ErrorCode::InvalidInput,
            ErrorCode::ConfigInvalid,
            ErrorCode::ProviderNotInstalled,
            ErrorCode::ProviderUnsupportedVersion,
            ErrorCode::ProviderProtocol,
            ErrorCode::ProviderFailed,
            ErrorCode::Timeout,
            ErrorCode::ApprovalRequired,
            ErrorCode::MonetaryBlocked,
            ErrorCode::AssetNotFree,
            ErrorCode::NotOwned,
            ErrorCode::AmbiguousVariant,
            ErrorCode::OutputConflict,
            ErrorCode::OutputNotEmpty,
            ErrorCode::PermissionDenied,
            ErrorCode::DownloadFailed,
            ErrorCode::UnsupportedCapability,
        ];
        let mut seen = std::collections::HashSet::new();
        for code in codes {
            assert!(code.as_str().starts_with("FAB_"), "{code}");
            assert!(seen.insert(code.as_str()), "duplicate string for {code}");
            assert!(
                (1..=14).contains(&code.exit_code()),
                "{code} exit out of range"
            );
        }
    }

    #[test]
    fn error_json_carries_the_branching_fields() {
        let err = FabError::new(ErrorCode::AuthRequired, "no session")
            .with_hint("run necturalabs-fab auth login")
            .with_provider("fabcli")
            .with_detail("uid", Value::String("abc".into()));
        let json = err.to_json();
        assert_eq!(json["code"], "FAB_AUTH_REQUIRED");
        assert_eq!(json["recoverable"], true);
        assert_eq!(json["retryable"], false);
        assert_eq!(json["details"]["uid"], "abc");
        assert_eq!(json["provider"], "fabcli");
    }

    #[test]
    fn protocol_errors_are_not_recoverable_but_network_is_retryable() {
        assert!(!ErrorCode::ProviderProtocol.recoverable());
        assert!(ErrorCode::Network.retryable());
        assert!(!ErrorCode::AuthRequired.retryable());
        assert!(ErrorCode::AuthRequired.recoverable());
    }
}
