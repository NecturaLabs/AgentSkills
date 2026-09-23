//! The approval and money boundary.
//!
//! Three rules, enforced here rather than scattered through commands:
//!
//! 1. Every operation declares an [`ActionClass`]. Read operations never ask
//!    for anything.
//! 2. Account mutations obey [`ApprovalPolicy`]; the default is `require`, so
//!    an agent must pass `--approve` (having asked its human) before one runs.
//! 3. Monetary operations are refused unconditionally. There is no policy, no
//!    flag and no configuration key that permits one.

use crate::config::ApprovalPolicy;
use crate::error::{ActionClass, ErrorCode, FabError, Result};
use crate::model::Asset;
use serde::Serialize;
use serde_json::Value;

/// What an operation will do, in a form an agent can show a human before
/// approving it.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActionPlan {
    /// Operation name, e.g. `claim`.
    pub operation: String,
    /// Risk class.
    pub class: ActionClass,
    /// What the operation acts on.
    pub target: Option<String>,
    /// Plain-language effects, one per line.
    pub effects: Vec<String>,
    /// Whether the effects can be undone by the user afterwards.
    pub reversible: bool,
    /// Whether this call needs explicit approval it does not yet have.
    pub requires_approval: bool,
    /// Whether approval was supplied.
    pub approved: bool,
}

impl ActionPlan {
    /// A read-only operation.
    pub fn read(operation: &str) -> Self {
        Self {
            operation: operation.to_string(),
            class: ActionClass::Read,
            target: None,
            effects: Vec::new(),
            reversible: true,
            requires_approval: false,
            approved: true,
        }
    }

    /// The action plan a command declares before it runs, used where a
    /// command fails before building its own (the failure envelope still
    /// states the class of what was attempted).
    pub fn for_command(command: &str) -> Self {
        let class = crate::commands::capabilities::class_of(command);
        let mut plan = Self::read(command);
        plan.class = class;
        if class == ActionClass::AccountMutation {
            plan.reversible = false;
        }
        plan
    }

    /// A local filesystem write.
    pub fn local_write(operation: &str, target: impl Into<String>, effects: Vec<String>) -> Self {
        Self {
            operation: operation.to_string(),
            class: ActionClass::LocalWrite,
            target: Some(target.into()),
            effects,
            reversible: true,
            requires_approval: false,
            approved: true,
        }
    }

    /// An account mutation, subject to policy.
    pub fn account_mutation(
        operation: &str,
        target: impl Into<String>,
        effects: Vec<String>,
    ) -> Self {
        Self {
            operation: operation.to_string(),
            class: ActionClass::AccountMutation,
            target: Some(target.into()),
            effects,
            // A claim adds an entitlement to a Fab account; Fab offers no
            // self-service removal, so treat it as one-way.
            reversible: false,
            requires_approval: true,
            approved: false,
        }
    }
}

/// Apply `policy` to a planned action.
///
/// Returns the plan with its approval fields resolved, or an error the caller
/// should surface verbatim: exit 8 for "ask your human" (or "disabled by
/// policy"), exit 9 for a monetary action.
pub fn gate(mut plan: ActionPlan, policy: ApprovalPolicy, approved: bool) -> Result<ActionPlan> {
    if plan.class == ActionClass::Monetary {
        return Err(monetary_refusal(&plan.operation));
    }
    if plan.class == ActionClass::Read {
        return Ok(plan);
    }

    match policy {
        ApprovalPolicy::Deny => Err(FabError::new(
            ErrorCode::ApprovalRequired,
            format!("'{}' is disabled by the approval policy", plan.operation),
        )
        .with_hint("change approval settings in the necturalabs-fab config to permit it")
        .with_detail("plan", serde_json::to_value(&plan).unwrap_or(Value::Null))
        .with_detail("policy", Value::String("deny".into()))),
        ApprovalPolicy::Allow => {
            plan.requires_approval = false;
            plan.approved = true;
            Ok(plan)
        }
        ApprovalPolicy::Require => {
            if approved {
                plan.requires_approval = false;
                plan.approved = true;
                return Ok(plan);
            }
            plan.requires_approval = true;
            plan.approved = false;
            Err(FabError::new(
                ErrorCode::ApprovalRequired,
                format!(
                    "'{}' changes your Fab account and needs explicit approval",
                    plan.operation
                ),
            )
            .with_hint("confirm with the person you are working for, then re-run with --approve")
            .with_detail("plan", serde_json::to_value(&plan).unwrap_or(Value::Null))
            .with_detail("policy", Value::String("require".into())))
        }
    }
}

/// The refusal used for every monetary request.
pub fn monetary_refusal(operation: &str) -> FabError {
    FabError::new(
        ErrorCode::MonetaryBlocked,
        format!("'{operation}' would spend money; necturalabs-fab never performs monetary actions"),
    )
    .with_hint("buy the asset yourself on fab.com, then use `necturalabs-fab download`")
}

/// Refuse to treat an asset as claimable unless it is unambiguously free.
///
/// Fails closed: an asset whose price the provider did not report is *not*
/// assumed free. This duplicates the provider's own check on purpose — the
/// guarantee must not depend on a single implementation's correctness.
pub fn ensure_claimable(asset: &Asset) -> Result<()> {
    match asset.price.free {
        Some(true) => Ok(()),
        Some(false) => Err(FabError::new(
            ErrorCode::AssetNotFree,
            format!(
                "'{}' costs {}{} — necturalabs-fab will not buy it",
                asset.title.as_deref().unwrap_or(&asset.id),
                asset
                    .price
                    .amount
                    .map(|a| format!("{a} "))
                    .unwrap_or_default(),
                asset.price.currency.as_deref().unwrap_or("")
            ),
        )
        .with_hint("purchase it on fab.com yourself, then run `necturalabs-fab download`")
        .with_detail("listingId", Value::String(asset.id.clone()))
        .with_detail(
            "price",
            asset
                .price
                .amount
                .map(|a| Value::String(a.to_string()))
                .unwrap_or(Value::Null),
        )),
        None => Err(FabError::new(
            ErrorCode::AssetNotFree,
            format!(
                "price for '{}' is unknown, so it cannot be treated as free",
                asset.id
            ),
        )
        .with_hint("run `necturalabs-fab inspect <listing>` and confirm the price before claiming")
        .with_detail("listingId", Value::String(asset.id.clone()))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Price;

    fn claim_plan() -> ActionPlan {
        ActionPlan::account_mutation(
            "claim",
            "listing-1",
            vec!["adds listing-1 to the library".into()],
        )
    }

    #[test]
    fn reads_never_require_approval() {
        let plan = gate(ActionPlan::read("search"), ApprovalPolicy::Require, false).unwrap();
        assert!(!plan.requires_approval);
        assert!(plan.approved);
    }

    #[test]
    fn account_mutation_without_approval_is_exit_8_and_carries_the_plan() {
        let err = gate(claim_plan(), ApprovalPolicy::Require, false).unwrap_err();
        assert_eq!(err.code, ErrorCode::ApprovalRequired);
        assert_eq!(err.code.exit_code(), 8);
        assert_eq!(err.details["plan"]["requiresApproval"], true);
        assert_eq!(err.details["plan"]["class"], "account-mutation");
        assert_eq!(err.details["plan"]["reversible"], false);
    }

    #[test]
    fn account_mutation_with_approval_proceeds() {
        let plan = gate(claim_plan(), ApprovalPolicy::Require, true).unwrap();
        assert!(plan.approved);
        assert!(!plan.requires_approval);
    }

    #[test]
    fn deny_policy_cannot_be_overridden_by_the_approve_flag() {
        let err = gate(claim_plan(), ApprovalPolicy::Deny, true).unwrap_err();
        assert_eq!(err.code, ErrorCode::ApprovalRequired);
        assert_eq!(err.details["policy"], "deny");
    }

    #[test]
    fn allow_policy_runs_without_a_flag() {
        let plan = gate(claim_plan(), ApprovalPolicy::Allow, false).unwrap();
        assert!(plan.approved);
    }

    #[test]
    fn monetary_actions_are_refused_under_every_policy() {
        for policy in [
            ApprovalPolicy::Allow,
            ApprovalPolicy::Require,
            ApprovalPolicy::Deny,
        ] {
            let mut plan = claim_plan();
            plan.class = ActionClass::Monetary;
            let err = gate(plan, policy, true).unwrap_err();
            assert_eq!(err.code, ErrorCode::MonetaryBlocked);
            assert_eq!(err.code.exit_code(), 9);
        }
    }

    #[test]
    fn claimable_requires_a_known_free_price() {
        let mut asset = Asset::new("u", "fabcli");
        asset.price = Price {
            free: Some(true),
            ..Default::default()
        };
        assert!(ensure_claimable(&asset).is_ok());

        asset.price.free = Some(false);
        asset.price.amount = crate::model::Amount::parse("19.99");
        assert_eq!(
            ensure_claimable(&asset).unwrap_err().code,
            ErrorCode::AssetNotFree
        );

        asset.price = Price::default();
        let err = ensure_claimable(&asset).unwrap_err();
        assert_eq!(err.code, ErrorCode::AssetNotFree);
        assert!(
            err.message.contains("unknown"),
            "unknown price must fail closed: {err}"
        );
    }
}
