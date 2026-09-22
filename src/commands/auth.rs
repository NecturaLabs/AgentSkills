//! `auth` — session state and sign-in.
//!
//! necturalabs-fab never handles credentials. It reports what the provider
//! says about its own sessions and, on a human's explicit `--run`, starts the
//! provider's interactive sign-in:
//!
//! * the default scope signs in for marketplace reads through the user's own
//!   browser — enough for search, inspect, library and download;
//! * `--account` opens the provider's sign-in window for the account session
//!   that claiming and ownership checks need, and only those.

use super::Ctx;
use crate::cli::{AuthArgs, AuthCommand};
use crate::error::Result;
use crate::output::Outcome;
use crate::provider::{AuthStatus, LoginScope};
use serde_json::json;
use std::io::IsTerminal;

/// Run `auth`.
pub fn run(ctx: &Ctx, args: &AuthArgs) -> Result<Outcome> {
    match &args.command {
        AuthCommand::Status => status(ctx),
        AuthCommand::Login { run, account } => login(
            ctx,
            *run,
            if *account {
                LoginScope::Account
            } else {
                LoginScope::Reads
            },
        ),
    }
}

/// The command a human runs to sign in for `scope`.
pub fn login_command(scope: LoginScope) -> &'static str {
    match scope {
        LoginScope::Reads => "necturalabs-fab auth login --run",
        LoginScope::Account => "necturalabs-fab auth login --run --account",
    }
}

fn summary(status: &AuthStatus) -> String {
    format!(
        "marketplace reads: {}\naccount actions (claim, ownership): {}",
        if status.authenticated {
            "signed in"
        } else {
            "signed out"
        },
        match (
            status.account_actions_available,
            status.account_session_days_remaining
        ) {
            (true, Some(days)) => format!("signed in ({days} days left)"),
            (true, None) => "signed in".to_string(),
            (false, _) => format!(
                "not signed in (only needed to claim or check ownership: {})",
                login_command(LoginScope::Account)
            ),
        }
    )
}

fn status(ctx: &Ctx) -> Result<Outcome> {
    let status = ctx.provider.auth_status()?;
    let data = json!({
        "auth": status,
        "loginCommands": {
            "reads": login_command(LoginScope::Reads),
            "account": login_command(LoginScope::Account),
        },
        "provider": ctx.provider.id(),
    });
    let mut outcome = Outcome::read("auth", data, summary(&status));
    if status.needs_reauth {
        outcome = outcome.warn(format!(
            "a session needs renewing; run `{}`",
            if status.authenticated {
                login_command(LoginScope::Account)
            } else {
                login_command(LoginScope::Reads)
            }
        ));
    }
    Ok(outcome)
}

fn login(ctx: &Ctx, run_it: bool, scope: LoginScope) -> Result<Outcome> {
    let hint = ctx.provider.login_hint(scope);

    // Without --run, or without a terminal to interact on, sign-in is described
    // rather than started: an agent calling this must never open a window or
    // block on input nobody can give.
    let interactive = std::io::stdin().is_terminal();
    if !run_it || !interactive {
        let data = json!({
            "ran": false,
            "scope": scope,
            "loginCommand": login_command(scope),
            "instructions": hint,
        });
        let human = format!(
            "Run this in a terminal to sign in:\n  {}\n{}",
            login_command(scope),
            hint.map(|h| format!("\n{h}")).unwrap_or_default()
        );
        let mut outcome = Outcome::read("auth", data, human);
        if run_it && !interactive {
            outcome = outcome.warn("sign-in needs an interactive terminal; nothing was started");
        }
        return Ok(outcome);
    }

    if let Some(hint) = &hint {
        if !ctx.renderer.is_json() {
            eprintln!("{hint}\n");
        }
    }
    let status = ctx.provider.login(scope)?;
    let complete = match scope {
        LoginScope::Reads => status.authenticated,
        LoginScope::Account => status.account_actions_available,
    };
    let data = json!({"ran": true, "scope": scope, "complete": complete, "auth": status});
    let mut outcome = Outcome::read(
        "auth",
        data,
        format!(
            "{}\n{}",
            if complete {
                "Sign-in complete."
            } else {
                "Sign-in did not complete."
            },
            summary(&status)
        ),
    );
    if !complete {
        outcome = outcome.warn(format!(
            "the {} session was not established; run `{}` to try again",
            match scope {
                LoginScope::Reads => "marketplace",
                LoginScope::Account => "account",
            },
            login_command(scope)
        ));
    }
    Ok(outcome)
}
