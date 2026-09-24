//! `skill status` — is the agent skill installed where each harness looks?
//!
//! The skill ships in the `necturalabs` plugin. Claude Code installs that
//! plugin from its marketplace, and Codex either installs it the same way or
//! reads the skill through the link AgentSkills' `scripts/install.sh` makes in
//! `~/.agents/skills`, so this command only reads harness state. It never writes: a second, hand-placed copy of a skill is
//! exactly the drift the marketplace install exists to prevent, and this
//! command reports one when it finds it.

use super::Ctx;
use crate::cli::{SkillArgs, SkillCommand};
use crate::error::Result;
use crate::output::{table, Outcome};
use serde::Serialize;
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};

/// Skill name in every harness, listed as `necturalabs:fab`.
pub const SKILL_NAME: &str = "fab";

/// Plugin and marketplace name.
pub const PLUGIN_NAME: &str = "necturalabs";

/// Plugin id as `plugin@marketplace`.
pub const PLUGIN_ID: &str = "necturalabs@necturalabs";

/// What one harness has installed.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HarnessStatus {
    /// `claude-code` or `codex`.
    pub harness: &'static str,
    /// The plugin is installed and enabled, or the skill is linked in.
    pub installed: bool,
    /// Installed plugin version, when the harness records one.
    pub version: Option<String>,
    /// Where the harness keeps the installed copy.
    pub location: Option<PathBuf>,
    /// Hand-placed copies of the skill that would load alongside the plugin.
    pub duplicates: Vec<PathBuf>,
}

/// Run `skill`.
pub fn run(_ctx: &Ctx, args: &SkillArgs) -> Result<Outcome> {
    match &args.command {
        SkillCommand::Status => status(),
    }
}

fn status() -> Result<Outcome> {
    let statuses = inspect();
    let rows: Vec<Vec<String>> = statuses
        .iter()
        .map(|s| {
            vec![
                s.harness.to_string(),
                if s.installed {
                    format!("installed {}", s.version.as_deref().unwrap_or(""))
                        .trim()
                        .to_string()
                } else {
                    "not installed".into()
                },
                s.location
                    .as_ref()
                    .map(|p| p.display().to_string())
                    .unwrap_or_else(|| "-".into()),
            ]
        })
        .collect();
    let mut outcome = Outcome::read(
        "skill",
        json!({ "plugin": PLUGIN_ID, "harnesses": statuses }),
        table(&["HARNESS", "STATE", "LOCATION"], &rows),
    );
    for status in &statuses {
        for duplicate in &status.duplicates {
            outcome = outcome.warn(format!(
                "{}: a hand-placed copy at {} loads alongside the plugin; remove it",
                status.harness,
                duplicate.display()
            ));
        }
    }
    Ok(outcome)
}

/// Inspect both harnesses under the current home directory.
pub fn inspect() -> Vec<HarnessStatus> {
    let Some(home) = home_dir() else {
        return Vec::new();
    };
    let claude_dir = std::env::var_os("CLAUDE_CONFIG_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".claude"));
    let codex_dir = std::env::var_os("CODEX_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".codex"));
    vec![claude(&claude_dir), codex(&codex_dir, &home)]
}

/// An absolute `HOME` wins on every platform, so sandboxed runs (tests, CI)
/// never read the real profile on Windows, where `dirs` ignores `HOME`.
fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .filter(|home| home.is_absolute())
        .or_else(dirs::home_dir)
}

/// Claude Code records installs in `plugins/installed_plugins.json`.
pub fn claude(claude_dir: &Path) -> HarnessStatus {
    let record = fs::read_to_string(claude_dir.join("plugins").join("installed_plugins.json"))
        .ok()
        .and_then(|text| serde_json::from_str::<Value>(&text).ok())
        .and_then(|v| {
            v.get("plugins")?
                .get(PLUGIN_ID)?
                .as_array()?
                .first()
                .cloned()
        });
    let manual = claude_dir.join("skills").join(SKILL_NAME);
    // Without the plugin, a link from AgentSkills' install.sh is the install.
    let linked = record.is_none() && is_link(&manual);
    HarnessStatus {
        harness: "claude-code",
        installed: record.is_some() || linked,
        version: record
            .as_ref()
            .and_then(|r| r.get("version")?.as_str().map(str::to_string)),
        location: record
            .as_ref()
            .and_then(|r| r.get("installPath")?.as_str().map(PathBuf::from))
            .or_else(|| linked.then(|| manual.clone())),
        duplicates: if linked {
            Vec::new()
        } else {
            exists(&manual).into_iter().collect()
        },
    }
}

/// Codex records installs in `config.toml` under `[plugins."<id>"]` and keeps
/// the files in `plugins/cache/<marketplace>/<plugin>/<version>`.
pub fn codex(codex_dir: &Path, home: &Path) -> HarnessStatus {
    let enabled = fs::read_to_string(codex_dir.join("config.toml"))
        .ok()
        .and_then(|text| text.parse::<toml::Table>().ok())
        .and_then(|table| {
            table
                .get("plugins")?
                .get(PLUGIN_ID)?
                .get("enabled")?
                .as_bool()
        })
        .unwrap_or(false);
    let cache = codex_dir
        .join("plugins")
        .join("cache")
        .join(PLUGIN_NAME)
        .join(PLUGIN_NAME);
    let version_dir = fs::read_dir(&cache).ok().and_then(|entries| {
        let mut dirs: Vec<PathBuf> = entries
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter(|p| p.is_dir())
            .collect();
        dirs.sort();
        dirs.pop()
    });
    let agents = home.join(".agents").join("skills").join(SKILL_NAME);
    // Without the plugin, a link from AgentSkills' install.sh is the install.
    let linked = !enabled && is_link(&agents);
    let duplicates = [agents.clone(), codex_dir.join("skills").join(SKILL_NAME)]
        .iter()
        .filter(|p| !(linked && **p == agents))
        .filter_map(|p| exists(p))
        .collect();
    HarnessStatus {
        harness: "codex",
        installed: enabled || linked,
        version: version_dir
            .as_ref()
            .filter(|_| enabled)
            .and_then(|d| d.file_name()?.to_str().map(str::to_string)),
        location: if linked { Some(agents) } else { version_dir },
        duplicates,
    }
}

fn is_link(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok_and(|m| m.file_type().is_symlink())
}

fn exists(path: &Path) -> Option<PathBuf> {
    fs::symlink_metadata(path).ok().map(|_| path.to_path_buf())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn claude_install_is_read_from_installed_plugins() {
        let tmp = tempfile::tempdir().unwrap();
        let plugins = tmp.path().join("plugins");
        fs::create_dir_all(&plugins).unwrap();
        fs::write(
            plugins.join("installed_plugins.json"),
            r#"{"version":2,"plugins":{"necturalabs@necturalabs":[{"scope":"user","installPath":"/x/cache/necturalabs/necturalabs/0.1.0","version":"0.1.0"}]}}"#,
        )
        .unwrap();
        let status = claude(tmp.path());
        assert!(status.installed);
        assert_eq!(status.version.as_deref(), Some("0.1.0"));
        assert!(status.duplicates.is_empty());
    }

    #[test]
    fn a_hand_placed_claude_copy_is_reported_as_a_duplicate() {
        let tmp = tempfile::tempdir().unwrap();
        fs::create_dir_all(tmp.path().join("skills").join(SKILL_NAME)).unwrap();
        let status = claude(tmp.path());
        assert!(!status.installed);
        assert_eq!(status.duplicates.len(), 1);
    }

    #[test]
    fn codex_install_is_read_from_config_and_cache() {
        let tmp = tempfile::tempdir().unwrap();
        let codex_dir = tmp.path().join(".codex");
        fs::create_dir_all(codex_dir.join("plugins/cache/necturalabs/necturalabs/0.1.0")).unwrap();
        fs::write(
            codex_dir.join("config.toml"),
            "[plugins.\"necturalabs@necturalabs\"]\nenabled = true\n",
        )
        .unwrap();
        let status = codex(&codex_dir, tmp.path());
        assert!(status.installed);
        assert_eq!(status.version.as_deref(), Some("0.1.0"));
    }

    #[test]
    fn nothing_installed_reads_as_not_installed() {
        let tmp = tempfile::tempdir().unwrap();
        assert!(!claude(tmp.path()).installed);
        assert!(!codex(&tmp.path().join(".codex"), tmp.path()).installed);
    }
}
