//! FabCLI version detection and compatibility.
//!
//! FabCLI drives undocumented Epic/Fab endpoints and is pre-1.0, so its output
//! contract can change on any minor release. necturalabs-fab pins the range it has
//! actually been tested against and fails loudly outside it rather than
//! silently mapping fields that moved.

use crate::error::{ErrorCode, FabError, Result};
use semver::{Version, VersionReq};

/// FabCLI releases necturalabs-fab is tested against.
///
/// 0.1.0 is the only published release as of 2026-05-03; the range admits
/// future 0.1.x patches, which cannot change the contract under semver, and
/// refuses 0.2 until the mapping layer has been re-verified against it.
pub const SUPPORTED_RANGE: &str = ">=0.1.0, <0.2.0";

/// Extract a semantic version from `fabcli --version` output.
///
/// FabCLI prints `fabcli 0.1.0`. The parser accepts any leading program name
/// and an optional `v` prefix so a rename or tag-style output still works.
pub fn parse_version_output(raw: &str) -> Result<Version> {
    let token = raw
        .split_whitespace()
        .find_map(|token| {
            let candidate = token.trim_start_matches('v');
            Version::parse(candidate).ok()
        })
        .ok_or_else(|| {
            FabError::new(
                ErrorCode::ProviderProtocol,
                format!(
                    "could not read a version from the provider's output: '{}'",
                    crate::sanitize::text(raw, 120).unwrap_or_default()
                ),
            )
            .with_provider("fabcli")
        })?;
    Ok(token)
}

/// Check a detected version against a requirement string.
///
/// Returns `Ok(())` when compatible. An unparseable requirement is a
/// configuration error, not a provider error.
pub fn check(version: &Version, requirement: &str) -> Result<()> {
    let req = VersionReq::parse(requirement).map_err(|err| {
        FabError::new(
            ErrorCode::ConfigInvalid,
            format!("invalid fabcli version requirement '{requirement}': {err}"),
        )
    })?;
    if req.matches(version) {
        return Ok(());
    }
    Err(FabError::new(
        ErrorCode::ProviderUnsupportedVersion,
        format!("FabCLI {version} is outside the supported range '{requirement}'"),
    )
    .with_hint(
        "install a supported FabCLI (`fabcli update --to <version>`), or override \
         fabcli.version_requirement in the config once the newer output has been verified",
    )
    .with_detail("detected", serde_json::Value::String(version.to_string()))
    .with_detail(
        "supported",
        serde_json::Value::String(requirement.to_string()),
    )
    .with_provider("fabcli"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_the_real_fabcli_banner() {
        let version = parse_version_output("fabcli 0.1.0\n").unwrap();
        assert_eq!(version, Version::new(0, 1, 0));
    }

    #[test]
    fn parses_v_prefixed_and_renamed_output() {
        assert_eq!(
            parse_version_output("fab-cli v1.2.3").unwrap(),
            Version::new(1, 2, 3)
        );
        assert_eq!(
            parse_version_output("0.4.1").unwrap(),
            Version::new(0, 4, 1)
        );
    }

    #[test]
    fn unparseable_output_is_a_protocol_error() {
        let err = parse_version_output("command not found").unwrap_err();
        assert_eq!(err.code, ErrorCode::ProviderProtocol);
        assert_eq!(err.code.exit_code(), 7);
    }

    #[test]
    fn supported_range_admits_patches_and_rejects_the_next_minor() {
        let req = SUPPORTED_RANGE;
        assert!(check(&Version::new(0, 1, 0), req).is_ok());
        assert!(check(&Version::new(0, 1, 9), req).is_ok());
        let err = check(&Version::new(0, 2, 0), req).unwrap_err();
        assert_eq!(err.code, ErrorCode::ProviderUnsupportedVersion);
        assert!(check(&Version::new(0, 0, 9), req).is_err());
    }

    #[test]
    fn a_broken_requirement_is_a_config_error_not_a_provider_error() {
        let err = check(&Version::new(0, 1, 0), "not a range").unwrap_err();
        assert_eq!(err.code, ErrorCode::ConfigInvalid);
    }
}
