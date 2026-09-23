<!--
EXAMPLE FILE — not an active instruction file.

This is the nested file for the `infra/` subtree of the fictional repository in
examples/project-agents.md. In a real repo it would live at `infra/AGENTS.md`.

What this example is demonstrating: a nested file exists for a genuine scope difference, never as
pagination. Every rule below would be false or actively harmful if applied to the Go and
TypeScript code at the repository root, which is exactly the test. The subtree has:

  - a different toolchain      — Terraform, Trivy and TFLint, not Go and pnpm
  - a different command set    — plan/apply against live cloud state, not build/test
  - a different safety boundary— commands here can destroy production infrastructure
  - a different generated rule — lockfiles and state are machine-owned in a different way
  - a different architecture   — declarative desired state, not imperative code paths

Note what it does NOT do: it never contradicts the root file, and it never restates the root's
generic rules just to look complete. It is still self-contained for its own subtree, because
harnesses assemble the chain differently — nearest-wins in one, root-to-leaf concatenation in
another, truncated silently past a byte budget — and none of them guarantees a merge order you can
depend on.
-->

# Meridian Infrastructure — Agent Guidelines

Terraform for every Meridian environment. Applies to `infra/` only; the root `AGENTS.md` governs
the Go service and the TypeScript console and still holds for anything it covers.

## Commands

Run from `infra/<env>/` — each environment is its own root with its own state — unless noted:

- Init: `terraform init -backend-config=backend.hcl`
- Validate: `terraform validate`
- Format: `terraform fmt -recursive`, run from `infra/` so it covers `modules/` too (the
  formatting authority here; `make lint` does not cover this subtree)
- Plan: `terraform plan` — **this is the verification command in this subtree**. No `-out`:
  nothing here applies a saved plan, and a plan file holds every value in plaintext, sensitive
  ones included
- Lint: `tflint --config=../.tflint.hcl`
- Security scan: `trivy config .`

`init` and `plan` need cloud credentials for that environment. Without them they fail on
authentication, which is a missing prerequisite, not a code failure — report it rather than working
around it.

`terraform apply` is never run by an agent, in any environment, including `dev`. Produce the plan,
report what it would change, and stop. Applies are performed by a human through CI.

## The verification rule here

There is no test suite. A change is verified by `terraform validate`, `tflint`, `trivy config` and a
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
- `.terraform.lock.hcl` — Committed and machine-owned. It changes only through
  `terraform init -upgrade` or `terraform providers lock`, and only as part of a provider bump.

## Boundaries

- **Always**: run `validate`, `tflint`, `trivy config` and `plan` before claiming done, and quote
  the plan summary.
- **Ask first**: any change under `prod/` or `modules/` — a module change reaches `prod` too; any
  provider version bump; anything that adds a public ingress or widens a security group.
- **Never**: run `terraform apply`, `destroy`, `import`, `taint` or any `terraform state`
  subcommand; commit a `.tfvars` file containing a secret; hand-edit the lockfile or any state
  file.
- **Security-sensitive**: `modules/network/` and `modules/iam/`. Changes there get a security pass
  before the general review. An IAM policy widened by a wildcard is the failure mode to look for, and
  `trivy config` does not catch all of them.

## Secrets

Values come from the secrets manager at plan time. Never inline a secret, never echo one into plan
output, and never add a `variable` with a sensitive default. If a plan would print a secret, mark
the variable `sensitive = true` and re-run before reporting anything.
