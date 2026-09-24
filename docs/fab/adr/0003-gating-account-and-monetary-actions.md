# ADR: How account-changing and money-spending actions are gated

**Status:** accepted
**Date:** 2026-09-22

## Context and problem statement

Autonomous agents drive necturalabs-fab with the user's real Epic/Fab account. Claiming a free asset
adds a permanent entitlement to that account; purchasing would spend money. An agent acting on a
prompt-injected listing description, or simply on a misread request, must not be able to do
either without a human decision. The gate has to be something an agent can detect and relay, not
just refuse.

## Considered options

1. Classify every command (read, local write, account mutation, monetary) and gate account
   mutations on a configurable policy plus an explicit `--approve` flag; make monetary actions
   unrepresentable.
2. Allow everything and rely on FabCLI's own free-asset check.
3. Require an interactive confirmation prompt.

## Decision outcome

Chosen option: "Classify and gate", because it gives agents a machine-readable signal
(`requiresApproval`, exit code 8, the plan in `error.details.plan`) to ask their human, keeps the
default safe (`approval.claim = "require"`), and lets a user choose `allow` or `deny` in config.
Monetary actions have no command, no flag, no config key and no provider method; a provider
advertising `purchase` is still refused. The claim path re-checks the listing price itself and
treats an unknown price as not free, so the guarantee does not rest on one implementation. An
interactive prompt would hang non-interactive agents; relying solely on FabCLI leaves a single
point of failure over an API whose semantics can change.

### Consequences

- **Good:** an agent cannot claim without either configuration or an explicit per-call approval,
  and cannot buy at all.
- **Bad:** agents must make a second call after asking; a user who wants unattended claiming must
  change configuration deliberately.

## Related

- `docs/fab/security.md`
