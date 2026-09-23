//! Layered configuration.
//!
//! Precedence, highest first:
//!
//! 1. command-line flags (applied by the CLI layer, not here);
//! 2. `NECTURALABS_FAB_*` environment variables;
//! 3. the nearest project config, found by walking up from the working
//!    directory (`.necturalabs-fab.toml`, `necturalabs-fab.toml`, `.necturalabs/fab.toml`);
//! 4. the user config (`~/.config/necturalabs-fab/config.toml`, or the platform
//!    equivalent);
//! 5. built-in defaults.
//!
//! Each layer overrides individual fields, never whole sections, so a project
//! that sets one value keeps the user's other preferences.
//!
//! The project layer is not trusted like the others. It arrives with whatever
//! repository an agent happens to be working in, so it may only set project
//! defaults. Keys that choose what runs or what is allowed — the provider and
//! its executable, the version gate, approval policy, overwrite policy — are
//! refused there, and its download directory must stay inside the project.

use crate::error::{ErrorCode, FabError, Result};
use crate::provider::OverwritePolicy;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// File names recognised as a project config, in priority order.
const PROJECT_FILES: [&str; 3] = [
    ".necturalabs-fab.toml",
    "necturalabs-fab.toml",
    ".necturalabs/fab.toml",
];

/// What approval an account-mutating action needs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ApprovalPolicy {
    /// Allowed without asking.
    Allow,
    /// Allowed only when the caller passes an explicit approval flag.
    Require,
    /// Never allowed, whatever the caller passes.
    Deny,
}

impl ApprovalPolicy {
    /// Parse a config/env value.
    pub fn parse(raw: &str) -> Result<Self> {
        Ok(match raw.trim().to_ascii_lowercase().as_str() {
            "allow" | "auto" => Self::Allow,
            "require" | "ask" | "approval-required" => Self::Require,
            "deny" | "never" | "block" => Self::Deny,
            other => {
                return Err(FabError::new(
                    ErrorCode::ConfigInvalid,
                    format!("unknown approval policy '{other}' (expected: allow, require, deny)"),
                ))
            }
        })
    }
}

/// How output is rendered.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum OutputMode {
    /// JSON when stdout is not a terminal, human-readable when it is.
    Auto,
    /// Always the machine envelope.
    Json,
    /// Always the human rendering.
    Human,
}

impl OutputMode {
    /// Parse a config/env/flag value.
    pub fn parse(raw: &str) -> Result<Self> {
        Ok(match raw.trim().to_ascii_lowercase().as_str() {
            "auto" => Self::Auto,
            "json" | "machine" => Self::Json,
            "human" | "text" | "pretty" => Self::Human,
            other => {
                return Err(FabError::new(
                    ErrorCode::ConfigInvalid,
                    format!("unknown output mode '{other}' (expected: auto, json, human)"),
                ))
            }
        })
    }
}

/// Provider settings.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FabCliConfig {
    /// Executable name or path.
    pub path: PathBuf,
    /// Timeout for ordinary calls, seconds.
    pub timeout_seconds: u64,
    /// Timeout for downloads, seconds.
    pub download_timeout_seconds: u64,
    /// Accepted provider version range (semver requirement syntax).
    pub version_requirement: String,
    /// Let the provider use its on-disk library cache.
    pub library_cache: bool,
}

/// Download behaviour.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DownloadConfig {
    /// Default destination root. Relative paths resolve against the working
    /// directory at call time.
    pub directory: PathBuf,
    /// Default collision policy.
    pub overwrite: OverwritePolicy,
    /// Parallel chunk workers, when the provider supports tuning it.
    pub jobs: Option<u32>,
}

/// Discovery defaults.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DefaultsConfig {
    /// Target engine for this project, e.g. `unreal`.
    pub engine: Option<String>,
    /// Target engine version, e.g. `5.4`.
    pub engine_version: Option<String>,
    /// Rank owned assets above equivalent unowned ones.
    pub prefer_owned: bool,
    /// Rank free assets above equivalent paid ones.
    pub prefer_free: bool,
    /// Results requested per search.
    pub count: u32,
    /// How many top candidates `find` enriches with listing detail.
    pub hydrate: u32,
}

/// Approval policy per action class.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ApprovalConfig {
    /// Claiming a free asset (an account mutation).
    pub claim: ApprovalPolicy,
    /// Writing downloaded files to disk.
    pub download: ApprovalPolicy,
}

/// Output behaviour.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OutputConfig {
    /// Rendering mode.
    pub mode: OutputMode,
}

/// Fully resolved configuration.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Config {
    /// Active provider id.
    pub provider: String,
    /// FabCLI provider settings.
    pub fabcli: FabCliConfig,
    /// Download settings.
    pub download: DownloadConfig,
    /// Discovery defaults.
    pub defaults: DefaultsConfig,
    /// Approval policy.
    pub approval: ApprovalConfig,
    /// Output settings.
    pub output: OutputConfig,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            provider: "fabcli".into(),
            fabcli: FabCliConfig {
                path: PathBuf::from("fabcli"),
                timeout_seconds: 120,
                download_timeout_seconds: 7200,
                version_requirement: crate::provider::fabcli::version::SUPPORTED_RANGE.into(),
                library_cache: true,
            },
            download: DownloadConfig {
                directory: PathBuf::from("."),
                overwrite: OverwritePolicy::Refuse,
                jobs: None,
            },
            defaults: DefaultsConfig {
                engine: None,
                engine_version: None,
                prefer_owned: true,
                prefer_free: true,
                count: crate::query::DEFAULT_COUNT,
                hydrate: 6,
            },
            approval: ApprovalConfig {
                // An account mutation is never automatic by default.
                claim: ApprovalPolicy::Require,
                download: ApprovalPolicy::Allow,
            },
            output: OutputConfig {
                mode: OutputMode::Auto,
            },
        }
    }
}

/// One config layer as read from a file: every field optional.
#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct PartialConfig {
    provider: Option<String>,
    #[serde(default)]
    fabcli: PartialFabCli,
    #[serde(default)]
    download: PartialDownload,
    #[serde(default)]
    defaults: PartialDefaults,
    #[serde(default)]
    approval: PartialApproval,
    #[serde(default)]
    output: PartialOutput,
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct PartialFabCli {
    path: Option<PathBuf>,
    timeout_seconds: Option<u64>,
    download_timeout_seconds: Option<u64>,
    version_requirement: Option<String>,
    library_cache: Option<bool>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct PartialDownload {
    directory: Option<PathBuf>,
    overwrite: Option<String>,
    jobs: Option<u32>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct PartialDefaults {
    engine: Option<String>,
    engine_version: Option<String>,
    prefer_owned: Option<bool>,
    prefer_free: Option<bool>,
    count: Option<u32>,
    hydrate: Option<u32>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct PartialApproval {
    claim: Option<String>,
    download: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct PartialOutput {
    mode: Option<String>,
}

/// Where a resolved value came from, for `doctor` and `config show`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LayerRecord {
    /// Layer name: `defaults`, `user`, `project`, `env`.
    pub layer: String,
    /// File that supplied it, when the layer is a file.
    pub path: Option<PathBuf>,
    /// Whether the layer contributed anything.
    pub applied: bool,
}

/// A resolved configuration plus its provenance.
#[derive(Debug, Clone)]
pub struct LoadedConfig {
    /// Effective settings.
    pub config: Config,
    /// Layers consulted, in application order.
    pub layers: Vec<LayerRecord>,
}

/// Load configuration for `cwd`, honouring `NECTURALABS_FAB_CONFIG` when set.
pub fn load(cwd: &Path) -> Result<LoadedConfig> {
    load_with_env(cwd, &EnvReader::process())
}

/// Load configuration against an explicit environment. Exposed for tests.
pub fn load_with_env(cwd: &Path, env: &EnvReader) -> Result<LoadedConfig> {
    let mut config = Config::default();
    let mut layers = vec![LayerRecord {
        layer: "defaults".into(),
        path: None,
        applied: true,
    }];

    let user_path = match env.get("NECTURALABS_FAB_CONFIG") {
        Some(explicit) => Some(PathBuf::from(explicit)),
        None => user_config_path(),
    };
    if let Some(path) = user_path {
        let applied = apply_file(&mut config, &path, false)?;
        layers.push(LayerRecord {
            layer: "user".into(),
            path: Some(path),
            applied,
        });
    }

    if let Some(path) = find_project_config(cwd) {
        let applied = apply_file(&mut config, &path, true)?;
        layers.push(LayerRecord {
            layer: "project".into(),
            path: Some(path),
            applied,
        });
    }

    let env_applied = apply_env(&mut config, env)?;
    layers.push(LayerRecord {
        layer: "env".into(),
        path: None,
        applied: env_applied,
    });

    validate(&config)?;
    Ok(LoadedConfig { config, layers })
}

/// The user-scope config path for this platform.
///
/// An absolute `XDG_CONFIG_HOME` is honoured on every platform, not only on
/// Linux, so one setting relocates the config the same way everywhere.
pub fn user_config_path() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
        .or_else(dirs::config_dir)?;
    Some(base.join("necturalabs-fab").join("config.toml"))
}

/// The user-scope cache directory for this platform, honouring an absolute
/// `XDG_CACHE_HOME` everywhere the way [`user_config_path`] honours
/// `XDG_CONFIG_HOME`.
pub fn user_cache_dir() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
        .or_else(dirs::cache_dir)?;
    Some(base.join("necturalabs-fab"))
}

/// The nearest project config at or above `cwd`.
pub fn find_project_config(cwd: &Path) -> Option<PathBuf> {
    let mut dir = Some(cwd);
    while let Some(current) = dir {
        for name in PROJECT_FILES {
            let candidate = current.join(name);
            if candidate.is_file() {
                return Some(candidate);
            }
        }
        dir = current.parent();
    }
    None
}

fn apply_file(config: &mut Config, path: &Path, project: bool) -> Result<bool> {
    let text = match std::fs::read_to_string(path) {
        Ok(text) => text,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(err) => {
            return Err(FabError::new(
                ErrorCode::ConfigInvalid,
                format!("could not read config {}: {err}", path.display()),
            ))
        }
    };
    let partial: PartialConfig = toml::from_str(&text).map_err(|err| {
        FabError::new(
            ErrorCode::ConfigInvalid,
            // toml's messages span several lines with a source excerpt; the
            // error contract is one line.
            format!(
                "invalid config {}: {}",
                path.display(),
                crate::sanitize::text(&err.to_string(), 300).unwrap_or_default()
            ),
        )
        .with_hint("see docs/configuration.md for the accepted keys")
    })?;
    if project {
        check_project_layer(&partial, path)?;
    }
    merge(config, partial)?;
    Ok(true)
}

/// Refuse the keys a repository must not be able to set for its reader.
fn check_project_layer(partial: &PartialConfig, path: &Path) -> Result<()> {
    let mut refused = Vec::new();
    if partial.provider.is_some() {
        refused.push("provider");
    }
    if partial.fabcli.path.is_some() {
        refused.push("fabcli.path");
    }
    if partial.fabcli.version_requirement.is_some() {
        refused.push("fabcli.version-requirement");
    }
    if partial.approval.claim.is_some() {
        refused.push("approval.claim");
    }
    if partial.approval.download.is_some() {
        refused.push("approval.download");
    }
    if partial.download.overwrite.is_some() {
        refused.push("download.overwrite");
    }
    if !refused.is_empty() {
        return Err(FabError::new(
            ErrorCode::ConfigInvalid,
            format!(
                "{} may not set {}: a project config cannot change what runs or what is allowed",
                path.display(),
                refused.join(", ")
            ),
        )
        .with_hint(
            "set these in your user config (`necturalabs-fab config path`), an env var, or a flag",
        ));
    }
    if let Some(directory) = &partial.download.directory {
        let contained = directory.components().all(|c| {
            matches!(
                c,
                std::path::Component::Normal(_) | std::path::Component::CurDir
            )
        });
        if !contained {
            return Err(FabError::new(
                ErrorCode::ConfigInvalid,
                format!(
                    "{}: download.directory must be a relative path inside the project (got {})",
                    path.display(),
                    directory.display()
                ),
            ));
        }
    }
    Ok(())
}

fn merge(config: &mut Config, partial: PartialConfig) -> Result<()> {
    if let Some(provider) = partial.provider {
        config.provider = provider;
    }
    if let Some(path) = partial.fabcli.path {
        config.fabcli.path = path;
    }
    if let Some(value) = partial.fabcli.timeout_seconds {
        config.fabcli.timeout_seconds = value;
    }
    if let Some(value) = partial.fabcli.download_timeout_seconds {
        config.fabcli.download_timeout_seconds = value;
    }
    if let Some(value) = partial.fabcli.version_requirement {
        config.fabcli.version_requirement = value;
    }
    if let Some(value) = partial.fabcli.library_cache {
        config.fabcli.library_cache = value;
    }
    if let Some(value) = partial.download.directory {
        config.download.directory = value;
    }
    if let Some(value) = partial.download.overwrite {
        config.download.overwrite = OverwritePolicy::parse(&value)
            .map_err(|err| FabError::new(ErrorCode::ConfigInvalid, err.message))?;
    }
    if let Some(value) = partial.download.jobs {
        config.download.jobs = Some(value);
    }
    if let Some(value) = partial.defaults.engine {
        config.defaults.engine = Some(value);
    }
    if let Some(value) = partial.defaults.engine_version {
        config.defaults.engine_version = Some(value);
    }
    if let Some(value) = partial.defaults.prefer_owned {
        config.defaults.prefer_owned = value;
    }
    if let Some(value) = partial.defaults.prefer_free {
        config.defaults.prefer_free = value;
    }
    if let Some(value) = partial.defaults.count {
        config.defaults.count = value;
    }
    if let Some(value) = partial.defaults.hydrate {
        config.defaults.hydrate = value;
    }
    if let Some(value) = partial.approval.claim {
        config.approval.claim = ApprovalPolicy::parse(&value)?;
    }
    if let Some(value) = partial.approval.download {
        config.approval.download = parse_download_policy(&value)?;
    }
    if let Some(value) = partial.output.mode {
        config.output.mode = OutputMode::parse(&value)?;
    }
    Ok(())
}

/// Environment access, indirected so tests need not mutate the process.
pub struct EnvReader {
    vars: Option<std::collections::HashMap<String, String>>,
    overrides: std::collections::HashMap<String, String>,
}

impl EnvReader {
    /// Read from the real process environment.
    pub fn process() -> Self {
        Self {
            vars: None,
            overrides: Default::default(),
        }
    }

    /// Replace one variable, leaving the rest of the environment readable.
    pub fn with_override(mut self, key: &str, value: &str) -> Self {
        self.overrides.insert(key.to_string(), value.to_string());
        self
    }

    /// Read from a fixed map.
    pub fn fixed(vars: &[(&str, &str)]) -> Self {
        Self {
            vars: Some(
                vars.iter()
                    .map(|(k, v)| ((*k).to_string(), (*v).to_string()))
                    .collect(),
            ),
            overrides: Default::default(),
        }
    }

    /// Look up one variable.
    pub fn get(&self, key: &str) -> Option<String> {
        if let Some(value) = self.overrides.get(key) {
            return Some(value.clone());
        }
        match &self.vars {
            Some(map) => map.get(key).cloned(),
            None => std::env::var(key).ok(),
        }
    }
}

fn apply_env(config: &mut Config, env: &EnvReader) -> Result<bool> {
    let mut applied = false;
    if let Some(value) = env.get("NECTURALABS_FAB_PROVIDER") {
        config.provider = value;
        applied = true;
    }
    if let Some(value) = env.get("NECTURALABS_FAB_FABCLI_PATH") {
        config.fabcli.path = PathBuf::from(value);
        applied = true;
    }
    if let Some(value) = env.get("NECTURALABS_FAB_TIMEOUT_SECONDS") {
        config.fabcli.timeout_seconds = parse_u64("NECTURALABS_FAB_TIMEOUT_SECONDS", &value)?;
        applied = true;
    }
    if let Some(value) = env.get("NECTURALABS_FAB_DOWNLOAD_TIMEOUT_SECONDS") {
        config.fabcli.download_timeout_seconds =
            parse_u64("NECTURALABS_FAB_DOWNLOAD_TIMEOUT_SECONDS", &value)?;
        applied = true;
    }
    if let Some(value) = env.get("NECTURALABS_FAB_VERSION_REQUIREMENT") {
        config.fabcli.version_requirement = value;
        applied = true;
    }
    if let Some(value) = env.get("NECTURALABS_FAB_LIBRARY_CACHE") {
        config.fabcli.library_cache = parse_bool("NECTURALABS_FAB_LIBRARY_CACHE", &value)?;
        applied = true;
    }
    if let Some(value) = env.get("NECTURALABS_FAB_DOWNLOAD_DIR") {
        config.download.directory = PathBuf::from(value);
        applied = true;
    }
    if let Some(value) = env.get("NECTURALABS_FAB_OVERWRITE") {
        config.download.overwrite = OverwritePolicy::parse(&value)?;
        applied = true;
    }
    if let Some(value) = env.get("NECTURALABS_FAB_ENGINE") {
        config.defaults.engine = Some(value);
        applied = true;
    }
    if let Some(value) = env.get("NECTURALABS_FAB_ENGINE_VERSION") {
        config.defaults.engine_version = Some(value);
        applied = true;
    }
    if let Some(value) = env.get("NECTURALABS_FAB_PREFER_OWNED") {
        config.defaults.prefer_owned = parse_bool("NECTURALABS_FAB_PREFER_OWNED", &value)?;
        applied = true;
    }
    if let Some(value) = env.get("NECTURALABS_FAB_PREFER_FREE") {
        config.defaults.prefer_free = parse_bool("NECTURALABS_FAB_PREFER_FREE", &value)?;
        applied = true;
    }
    if let Some(value) = env.get("NECTURALABS_FAB_COUNT") {
        config.defaults.count = u32::try_from(parse_u64("NECTURALABS_FAB_COUNT", &value)?)
            .map_err(|_| {
                FabError::new(
                    ErrorCode::ConfigInvalid,
                    format!("NECTURALABS_FAB_COUNT is out of range (got '{value}')"),
                )
            })?;
        applied = true;
    }
    if let Some(value) = env.get("NECTURALABS_FAB_APPROVAL_CLAIM") {
        config.approval.claim = ApprovalPolicy::parse(&value)?;
        applied = true;
    }
    if let Some(value) = env.get("NECTURALABS_FAB_OUTPUT") {
        config.output.mode = OutputMode::parse(&value)?;
        applied = true;
    }
    Ok(applied)
}

/// Downloads have no per-call approval flag, so `require` would silently mean
/// `allow`; only the two policies that do what they say are accepted.
fn parse_download_policy(value: &str) -> Result<ApprovalPolicy> {
    match ApprovalPolicy::parse(value)? {
        ApprovalPolicy::Require => Err(FabError::new(
            ErrorCode::ConfigInvalid,
            "approval.download accepts `allow` or `deny`",
        )),
        policy => Ok(policy),
    }
}

fn parse_u64(key: &str, value: &str) -> Result<u64> {
    value.trim().parse().map_err(|_| {
        FabError::new(
            ErrorCode::ConfigInvalid,
            format!("{key} must be a whole number (got '{value}')"),
        )
    })
}

fn parse_bool(key: &str, value: &str) -> Result<bool> {
    match value.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Ok(true),
        "0" | "false" | "no" | "off" => Ok(false),
        other => Err(FabError::new(
            ErrorCode::ConfigInvalid,
            format!("{key} must be a boolean (got '{other}')"),
        )),
    }
}

fn validate(config: &Config) -> Result<()> {
    if config.fabcli.timeout_seconds == 0 || config.fabcli.download_timeout_seconds == 0 {
        return Err(FabError::new(
            ErrorCode::ConfigInvalid,
            "timeouts must be greater than zero",
        ));
    }
    if config.defaults.count == 0 || config.defaults.count > crate::query::MAX_COUNT {
        return Err(FabError::new(
            ErrorCode::ConfigInvalid,
            format!(
                "defaults.count must be between 1 and {} (got {})",
                crate::query::MAX_COUNT,
                config.defaults.count
            ),
        ));
    }
    semver::VersionReq::parse(&config.fabcli.version_requirement).map_err(|err| {
        FabError::new(
            ErrorCode::ConfigInvalid,
            format!(
                "fabcli.version-requirement '{}' is not a semver range: {err}",
                config.fabcli.version_requirement
            ),
        )
    })?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn write(dir: &Path, name: &str, body: &str) {
        let path = dir.join(name);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        fs::write(path, body).unwrap();
    }

    #[test]
    fn defaults_are_safe() {
        let config = Config::default();
        assert_eq!(config.approval.claim, ApprovalPolicy::Require);
        assert_eq!(config.download.overwrite, OverwritePolicy::Refuse);
        assert_eq!(config.provider, "fabcli");
    }

    #[test]
    fn project_config_overrides_user_config_field_by_field() {
        let tmp = tempfile::tempdir().unwrap();
        let user = tmp.path().join("user.toml");
        fs::write(
            &user,
            "[defaults]\nengine = \"unity\"\ncount = 50\n[approval]\nclaim = \"allow\"\n",
        )
        .unwrap();
        // (the user layer may set approval; the project layer may not)
        let project_dir = tmp.path().join("project");
        write(
            &project_dir,
            ".necturalabs-fab.toml",
            "[defaults]\nengine = \"unreal\"\n",
        );

        let env = EnvReader::fixed(&[("NECTURALABS_FAB_CONFIG", user.to_str().unwrap())]);
        let loaded = load_with_env(&project_dir, &env).unwrap();
        // Project wins for engine ...
        assert_eq!(loaded.config.defaults.engine.as_deref(), Some("unreal"));
        // ... and the user's other values survive.
        assert_eq!(loaded.config.defaults.count, 50);
        assert_eq!(loaded.config.approval.claim, ApprovalPolicy::Allow);
    }

    #[test]
    fn env_overrides_both_files() {
        let tmp = tempfile::tempdir().unwrap();
        let user = tmp.path().join("user.toml");
        fs::write(&user, "[defaults]\nengine = \"unity\"\n").unwrap();
        write(
            tmp.path(),
            ".necturalabs-fab.toml",
            "[defaults]\nengine = \"unreal\"\n",
        );
        let env = EnvReader::fixed(&[
            ("NECTURALABS_FAB_CONFIG", user.to_str().unwrap()),
            ("NECTURALABS_FAB_ENGINE", "godot"),
        ]);
        let loaded = load_with_env(tmp.path(), &env).unwrap();
        assert_eq!(loaded.config.defaults.engine.as_deref(), Some("godot"));
    }

    #[test]
    fn project_config_is_found_by_walking_up() {
        let tmp = tempfile::tempdir().unwrap();
        write(
            tmp.path(),
            ".necturalabs-fab.toml",
            "[defaults]\nengine = \"unreal\"\n",
        );
        let nested = tmp.path().join("a").join("b").join("c");
        fs::create_dir_all(&nested).unwrap();
        let found = find_project_config(&nested).unwrap();
        assert_eq!(found, tmp.path().join(".necturalabs-fab.toml"));
    }

    #[test]
    fn unknown_keys_are_rejected_rather_than_silently_ignored() {
        let tmp = tempfile::tempdir().unwrap();
        write(
            tmp.path(),
            ".necturalabs-fab.toml",
            "[defaults]\nengien = \"unreal\"\n",
        );
        let env = EnvReader::fixed(&[("NECTURALABS_FAB_CONFIG", "/nonexistent/none.toml")]);
        let err = load_with_env(tmp.path(), &env).unwrap_err();
        assert_eq!(err.code, ErrorCode::ConfigInvalid);
        assert!(err.message.contains("engien"), "{err}");
    }

    #[test]
    fn invalid_values_are_config_errors() {
        let tmp = tempfile::tempdir().unwrap();
        write(
            tmp.path(),
            ".necturalabs-fab.toml",
            "[approval]\nclaim = \"maybe\"\n",
        );
        let env = EnvReader::fixed(&[("NECTURALABS_FAB_CONFIG", "/nonexistent/none.toml")]);
        let err = load_with_env(tmp.path(), &env).unwrap_err();
        assert_eq!(err.code, ErrorCode::ConfigInvalid);

        let env = EnvReader::fixed(&[("NECTURALABS_FAB_TIMEOUT_SECONDS", "soon")]);
        let err = load_with_env(tmp.path(), &env).unwrap_err();
        assert_eq!(err.code, ErrorCode::ConfigInvalid);
    }

    #[test]
    fn layers_are_reported_in_application_order() {
        let tmp = tempfile::tempdir().unwrap();
        write(
            tmp.path(),
            ".necturalabs-fab.toml",
            "[defaults]\nengine = \"unreal\"\n",
        );
        let env = EnvReader::fixed(&[("NECTURALABS_FAB_CONFIG", "/nonexistent/none.toml")]);
        let loaded = load_with_env(tmp.path(), &env).unwrap();
        let names: Vec<&str> = loaded.layers.iter().map(|l| l.layer.as_str()).collect();
        assert_eq!(names, vec!["defaults", "user", "project", "env"]);
        assert!(
            !loaded.layers[1].applied,
            "missing user file must not count as applied"
        );
        assert!(loaded.layers[2].applied);
    }

    #[test]
    fn out_of_range_count_is_rejected() {
        let tmp = tempfile::tempdir().unwrap();
        let env = EnvReader::fixed(&[("NECTURALABS_FAB_COUNT", "9999")]);
        let err = load_with_env(tmp.path(), &env).unwrap_err();
        assert_eq!(err.code, ErrorCode::ConfigInvalid);
    }
}
