<!--
EXAMPLE FILE — not an active instruction file.

This is the nested file for the `infra/` subtree of the fictional repository in
examples/project-agents.md. In a real repo it would live at `infra/AGENTS.md`.

What this example is demonstrating: a nested file exists for a genuine scope difference, never as
pagination. Every rule below would be false or actively harmful if applied to the Go and
TypeScript code at the repository root, which is exactly the test. The subtree has:

  - a different toolchain      — Terraform and OpenTofu, not Go and pnpm
  - a different command set    — plan/apply against live cloud state, not build/test
  - a different safety boundary— commands here can destroy production infrastructure
  - a different generated rule — lockfiles and state are machine-owned in a different way
  - a different architecture   — declarative desired state, not imperative code paths

Note what it does NOT do: it never contradicts the root file, and it never restates the root's
generic rules just to look complete. It is self-contained for its own subtree, because some
harnesses give a nested file to an agent without the root, and none of them guarantee a merge
order you can depend on.
-->

# Meridian Infrastructure — Agent Guidelines

Terraform for every Meridian environment. Applies to `infra/` only; the root `AGENTS.md` governs
the Go service and the TypeScript console and still holds for anything it covers.

## Commands

Run from `infra/<env>/`, never from `infra/`:

- Init: `terraform init -backend-config=backend.hcl`
- Validate: `terraform validate`
- Format: `terraform fmt -recursive` (the formatting authority here; `make lint` does not cover
  this subtree)
- Plan: `terraform plan -out=tfplan` — **this is the verification command in this subtree**
- Lint: `tflint --config=../.tflint.hcl`
- Security scan: `tfsec .`

`terraform apply` is never run by an agent, in any environment, including `dev`. Produce the plan,
report what it would change, and stop. Applies are performed by a human through CI.

## The verification rule here

There is no test suite. A change is verified by `terraform validate`, `tflint`, `tfsec` and a
`terraform plan` whose output you actually read and report — specifically the resource counts and
every destroy or replace line. "Plan succeeded" is not a report; the plan's own summary line and
any `must be replaced` entry are.

A plan that shows an unexpected destroy or replace is a blocker, not a detail. Stop and report it.
Replacement of a database, a load balancer or anything holding state means downtime even when the
plan exits zero.

## Structure

- `modules/` — Reusable modules. A change here affects every environment at once; plan all three.
- `dev/`, `staging/`, `prod/` — Per-environment roots. Each has its own state; they are never
  shared.
- `*.tfstate`, `*.tfstate.backup` — Never read, never write, never commit. State lives in the
  remote backend; a local state file in a diff means something went wrong.
- `.terraform.lock.hcl` — Committed and machine-owned. Change it only via
  `terraform providers lock`, never by hand.

## Boundaries

- **Always**: run `validate`, `tflint`, `tfsec` and `plan` before claiming done, and quote the
  plan summary.
- **Ask first**: any change under `prod/`; any provider version bump; anything that adds a public
  ingress or widens a security group.
- **Never**: run `apply`, `destroy`, `taint`, `import`, `state rm` or `state mv`; commit a
  `.tfvars` file containing a secret; hand-edit the lockfile or any state file; move a resource
  between environments by editing state.
- **Security-sensitive**: `modules/network/` and `modules/iam/`. Route through `threat-review`
  before `independent-review`. An IAM policy widened by a wildcard is the failure mode to look for, and
  `tfsec` does not catch all of them.

## Secrets

Values come from the secrets manager at plan time. Never inline a secret, never echo one into plan
output, and never add a `variable` with a sensitive default. If a plan would print a secret, mark
the variable `sensitive = true` and re-run before reporting anything.
