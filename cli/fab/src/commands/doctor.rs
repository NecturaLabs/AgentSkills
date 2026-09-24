//! `doctor` — is this installation going to work?
//!
//! Every check is read-only and safe to run signed out. Nothing here prints a
//! token, a cookie, an account id or a file's contents: the questions are
//! "does it exist", "does it parse", "is it in range" and "is the session
//! usable", never "what is it".

use super::Ctx;
use crate::config;
use crate::error::Result;
use crate::output::{table, Outcome};
use serde_json::{json, Value};

/// Outcome of a single check.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Status {
    /// Working.
    Ok,
    /// Usable, but something needs attention.
    Warn,
    /// Broken; commands depending on it will fail.
    Fail,
}

impl Status {
    fn as_str(self) -> &'static str {
        match self {
            Self::Ok => "ok",
            Self::Warn => "warn",
            Self::Fail => "fail",
        }
    }
}

/// One diagnostic.
#[derive(Debug, Clone)]
pub struct Check {
    /// Stable identifier, e.g. `provider.version`.
    pub id: &'static str,
    /// Result.
    pub status: Status,
    /// What was found.
    pub detail: String,
    /// What to do about it.
    pub hint: Option<String>,
}

impl Check {
    fn new(id: &'static str, status: Status, detail: impl Into<String>) -> Self {
        Self {
            id,
            status,
            detail: detail.into(),
            hint: None,
        }
    }

    fn hint(mut self, hint: impl Into<String>) -> Self {
        self.hint = Some(hint.into());
        self
    }

    fn json(&self) -> Value {
        json!({
            "id": self.id,
            "status": self.status.as_str(),
            "detail": self.detail,
            "hint": self.hint,
        })
    }
}

/// Run `doctor`.
pub fn run(ctx: &Ctx) -> Result<Outcome> {
    let mut checks = vec![Check::new(
        "necturalabs-fab.version",
        Status::Ok,
        format!("necturalabs-fab {}", crate::VERSION),
    )];

    let mut provider_version = None;
    checks.push(Check::new(
        "provider.selected",
        Status::Ok,
        format!("provider '{}'", ctx.provider.id()),
    ));

    match ctx.provider.health() {
        Ok(health) => {
            provider_version.clone_from(&health.version);
            checks.push(Check::new(
                "provider.executable",
                Status::Ok,
                health
                    .executable
                    .clone()
                    .unwrap_or_else(|| "resolved".to_string()),
            ));
            let version_detail = format!(
                "{} (supported: {})",
                health.version.clone().unwrap_or_else(|| "unknown".into()),
                health.supported_range.clone().unwrap_or_default()
            );
            match health.version_supported {
                Some(true) => {
                    checks.push(Check::new("provider.version", Status::Ok, version_detail))
                }
                Some(false) => checks.push(
                    Check::new("provider.version", Status::Fail, version_detail).hint(
                        "install a supported provider version, or set fabcli.version-requirement \
                         once the newer output has been verified",
                    ),
                ),
                None => checks.push(Check::new("provider.version", Status::Warn, version_detail)),
            }
            for note in health.notes {
                checks.push(Check::new("provider.note", Status::Warn, note));
            }
        }
        Err(err) => {
            checks.push(
                Check::new(
                    "provider.executable",
                    Status::Fail,
                    format!("{} ({})", err.message, err.code),
                )
                .hint(
                    err.hint
                        .clone()
                        .unwrap_or_else(|| "install the provider and put it on PATH".to_string()),
                ),
            );
        }
    }

    match ctx.provider.auth_status() {
        Ok(status) => {
            checks.push(if status.authenticated {
                Check::new("auth.reads", Status::Ok, "signed in for marketplace reads")
            } else {
                Check::new("auth.reads", Status::Warn, "signed out").hint(
                    "run `necturalabs-fab auth login` — search, library and download all need a session",
                )
            });
            let account_detail = match status.account_session_days_remaining {
                Some(days) => format!(
                    "account actions {} ({days} days left)",
                    if status.account_actions_available {
                        "available"
                    } else {
                        "unavailable"
                    }
                ),
                None => format!(
                    "account actions {}",
                    if status.account_actions_available {
                        "available"
                    } else {
                        "unavailable"
                    }
                ),
            };
            checks.push(
                match (status.account_actions_available, status.needs_reauth) {
                    (true, false) => Check::new("auth.account-actions", Status::Ok, account_detail),
                    (true, true) => {
                        Check::new("auth.account-actions", Status::Warn, account_detail)
                            .hint("re-run the provider sign-in before the session lapses")
                    }
                    (false, _) => Check::new("auth.account-actions", Status::Warn, account_detail)
                        .hint("claim and ownership need the provider's account session"),
                },
            );
        }
        Err(err) => checks.push(
            Check::new(
                "auth.reads",
                Status::Fail,
                format!("session state unavailable: {} ({})", err.message, err.code),
            )
            .hint("run `necturalabs-fab auth login`"),
        ),
    }

    if let Some(err) = &ctx.config_error {
        checks.push(
            Check::new("config.valid", Status::Fail, err.message.clone()).hint(
                "fix or remove the file named above (`necturalabs-fab config init --force` rewrites it); \
                 these checks ran on defaults",
            ),
        );
    }

    let layer_summary = ctx
        .layers
        .iter()
        .filter(|layer| layer.applied)
        .map(|layer| {
            layer
                .path
                .as_ref()
                .map(|p| format!("{} ({})", layer.layer, p.display()))
                .unwrap_or_else(|| layer.layer.clone())
        })
        .collect::<Vec<_>>()
        .join(", ");
    checks.push(Check::new("config.layers", Status::Ok, layer_summary));

    let download_dir = if ctx.config.download.directory.is_absolute() {
        ctx.config.download.directory.clone()
    } else {
        ctx.cwd.join(&ctx.config.download.directory)
    };
    checks.push(match super::download::inspect_dir(&download_dir) {
        Ok(state) if state.exists => Check::new(
            "download.directory",
            Status::Ok,
            format!("{} exists", download_dir.display()),
        ),
        Ok(_) => Check::new(
            "download.directory",
            Status::Warn,
            format!(
                "{} does not exist yet (created on first download)",
                download_dir.display()
            ),
        ),
        Err(err) => Check::new(
            "download.directory",
            Status::Fail,
            format!("{}: {}", download_dir.display(), err.message),
        )
        .hint("set download.directory in the config, or pass --out"),
    });

    let mut installations_json = Vec::new();
    for status in super::skill::inspect() {
        let id: &'static str = if status.harness == "claude-code" {
            "skill.claude-code"
        } else {
            "skill.codex"
        };
        let check = if !status.installed {
            Check::new(id, Status::Warn, "plugin not installed")
                .hint("install the necturalabs plugin: https://github.com/NecturaLabs/AgentSkills#install-by-hand")
        } else if let Some(duplicate) = status.duplicates.first() {
            Check::new(
                id,
                Status::Warn,
                format!(
                    "installed, but a hand-placed copy at {} also loads",
                    duplicate.display()
                ),
            )
            .hint("remove the hand-placed copy so the marketplace install is the only one")
        } else if let Some(version) = status.version.as_deref().filter(|v| *v != crate::VERSION) {
            // The skill documents this binary's flags and codes; another
            // release's skill can steer an agent wrong.
            Check::new(
                id,
                Status::Warn,
                format!(
                    "plugin {version} does not match necturalabs-fab {}",
                    crate::VERSION
                ),
            )
            .hint("update the necturalabs plugin and re-run scripts/install-fab.sh so both come from the same release")
        } else {
            Check::new(
                id,
                Status::Ok,
                format!("plugin {}", status.version.clone().unwrap_or_default())
                    .trim()
                    .to_string(),
            )
        };
        installations_json.push(serde_json::to_value(&status).unwrap_or(Value::Null));
        checks.push(check);
    }

    let overall = checks.iter().map(|c| c.status).max().unwrap_or(Status::Ok);
    let data = json!({
        "status": overall.as_str(),
        "checks": checks.iter().map(Check::json).collect::<Vec<_>>(),
        "provider": {
            "id": ctx.provider.id(),
            "version": provider_version,
            "capabilities": ctx.provider.capabilities(),
        },
        "config": {
            "paths": {
                "user": config::user_config_path(),
                "project": config::find_project_config(&ctx.cwd),
            },
            "downloadDirectory": download_dir,
            "approval": ctx.config.approval,
        },
        "skills": installations_json,
    });

    let rows: Vec<Vec<String>> = checks
        .iter()
        .map(|check| {
            vec![
                check.status.as_str().to_uppercase(),
                check.id.to_string(),
                check.detail.clone(),
            ]
        })
        .collect();
    let mut human = table(&["STATUS", "CHECK", "DETAIL"], &rows);
    for check in checks.iter().filter(|c| c.status != Status::Ok) {
        if let Some(hint) = &check.hint {
            human.push_str(&format!("\n{}: {hint}", check.id));
        }
    }
    human.push_str(&format!("\n\noverall: {}", overall.as_str()));

    Ok(Outcome::read("doctor", data, human))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn overall_status_is_the_worst_check() {
        let statuses = [Status::Ok, Status::Warn, Status::Ok];
        assert_eq!(statuses.iter().copied().max().unwrap(), Status::Warn);
        let statuses = [Status::Warn, Status::Fail];
        assert_eq!(statuses.iter().copied().max().unwrap(), Status::Fail);
        let statuses = [Status::Ok];
        assert_eq!(statuses.iter().copied().max().unwrap(), Status::Ok);
    }
}
