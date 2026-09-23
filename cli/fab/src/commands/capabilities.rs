//! `capabilities` — what the active provider can do.

use super::Ctx;
use crate::config::ApprovalPolicy;
use crate::error::{ActionClass, Result};
use crate::output::{table, Outcome};
use serde_json::json;

/// Every command, with the risk class that governs it.
pub const COMMAND_CLASSES: &[(&str, ActionClass)] = &[
    ("search", ActionClass::Read),
    ("find", ActionClass::Read),
    ("recommend", ActionClass::Read),
    ("inspect", ActionClass::Read),
    ("ownership", ActionClass::Read),
    ("library", ActionClass::Read),
    ("auth status", ActionClass::Read),
    ("doctor", ActionClass::Read),
    ("download", ActionClass::LocalWrite),
    ("config init", ActionClass::LocalWrite),
    ("claim", ActionClass::AccountMutation),
    ("promos", ActionClass::Read),
    ("promos claim", ActionClass::AccountMutation),
];

/// Risk class of a top-level command, by name.
pub fn class_of(command: &str) -> ActionClass {
    COMMAND_CLASSES
        .iter()
        .find(|(name, _)| *name == command)
        .map(|(_, class)| *class)
        .unwrap_or(ActionClass::Read)
}

/// The configured policy governing a command: claims follow `approval.claim`,
/// downloads `approval.download`; everything else is allowed.
fn policy_of(ctx: &Ctx, name: &str, class: ActionClass) -> ApprovalPolicy {
    match class {
        ActionClass::AccountMutation => ctx.config.approval.claim,
        ActionClass::LocalWrite if name == "download" => ctx.config.approval.download,
        _ => ApprovalPolicy::Allow,
    }
}

/// Run `capabilities`.
pub fn run(ctx: &Ctx) -> Result<Outcome> {
    let capabilities = ctx.provider.capabilities();
    let commands: Vec<_> = COMMAND_CLASSES
        .iter()
        .map(|(name, class)| {
            let policy = policy_of(ctx, name, *class);
            json!({
                "command": name,
                "actionClass": class,
                "policy": policy,
                "allowed": policy != ApprovalPolicy::Deny,
                "requiresApproval": policy == ApprovalPolicy::Require,
            })
        })
        .collect();

    let data = json!({
        "provider": ctx.provider.id(),
        "capabilities": capabilities,
        "commands": commands,
        "monetaryActions": {
            "supported": false,
            "note": "necturalabs-fab never purchases; a provider advertising purchase is still refused",
        },
    });

    let rows: Vec<Vec<String>> = COMMAND_CLASSES
        .iter()
        .map(|(name, class)| {
            vec![
                (*name).to_string(),
                format!("{class:?}"),
                match policy_of(ctx, name, *class) {
                    ApprovalPolicy::Allow => "no".into(),
                    ApprovalPolicy::Require => "yes".into(),
                    ApprovalPolicy::Deny => "denied".into(),
                },
            ]
        })
        .collect();
    let human = format!(
        "provider: {}\n{}",
        ctx.provider.id(),
        table(&["COMMAND", "CLASS", "NEEDS APPROVAL"], &rows)
    );

    Ok(Outcome::read("capabilities", data, human))
}
