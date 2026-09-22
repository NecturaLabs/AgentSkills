<!--
EXAMPLE FILE — not an active instruction file.

Copy this to a repository's own AGENTS.md and replace every fact with one that is true of your
repo. The repository described here — "Meridian", a payments service — is fictional.

Commands below are illustrative. In a real file every command must be run and confirmed first: an
unverified command is obeyed with full confidence and fails in a way the agent works around rather
than questions.

What this example is demonstrating: a project file is a map, not a manual. It carries what an
agent cannot recover by reading the repo, and nothing else. Generic engineering doctrine belongs
in the global file; procedure belongs in skills. Compare its size to examples/global-agents.md —
a project file should be a fraction of it, because the project chain is capped and truncated
silently, and because almost everything true of good engineering is already stated once globally.
-->

# Meridian — Agent Guidelines

Payment authorization and ledger service. Go 1.24 API, TypeScript 5.7 operator console, Postgres 17.
Handles live card authorizations: treat every change as production-affecting.

## Commands

- Build: `make build`
- Test: `make test` (unit + integration; starts a throwaway Postgres in Docker)
- Single test: `go test ./ledger -run TestReconcileSettlement`
- Console tests: `pnpm -C console test`
- Lint: `make lint` (`golangci-lint` + `eslint`; `make lint-fix` applies)
- Migrations, new: `make migrate-new name=<slug>` — never hand-create the file, the timestamp
  prefix has to match the sequence table

`make test` needs Docker running. Without it the integration tests fail on connection refused,
which looks like a code failure and is not.

## Structure

- `ledger/` — Double-entry core. Pure; no HTTP, no SQL, no clock access. Everything here must be
  deterministic and unit-testable without a database.
- `adapters/` — Everything touching the network, the database or a card network.
- `internal/pb/` — Protobuf output. Regenerate with `make proto`; never hand-edit.
- `console/src/api/generated/` — OpenAPI client, generated from `openapi.yaml` by `make client`;
  never hand-edit.
- `infra/` — Terraform for all environments. Has its own AGENTS.md; different toolchain and a
  different safety boundary.

The `ledger/` and `adapters/` split is load-bearing, not cosmetic: a change that puts an SQL query
or a `time.Now()` call into `ledger/` breaks the determinism the whole test suite depends on, and
the compiler will not catch it.

## Conventions

- Money is `ledger.Amount` — minor units plus an ISO-4217 currency. A bare `int64` or any float in
  a monetary position is a bug; `make lint` has a custom analyzer for this, so trust its finding
  over your reading.
- Errors carry a stable `Code` field. Callers switch on the code, never on message text; messages
  are user-visible and get reworded.
- Every ledger mutation takes an idempotency key and must be safe to replay. There is no
  "just this once" exception — the card networks retry on their own schedule.

## Testing

Route test work through the `testing` skill. Project-specific:

- Ledger invariants are property-tested in `ledger/prop_test.go`. A new posting rule needs a
  property there, not only a table test — the table tests have historically missed asymmetric
  rounding.
- Integration tests run against the real schema, not a mock. If a test needs a new table, it needs
  a migration.
- The clock and ID generator are injected everywhere. Never call `time.Now()` or `uuid.New()`
  inside `ledger/`.

## Boundaries

- **Always**: run `make test` and `make lint` before claiming done. State what they printed.
- **Ask first**: schema migrations, dependency additions, anything changing an API response shape,
  anything under `infra/`.
- **Never**: hand-edit `internal/pb/` or `console/src/api/generated/`; log a card number, CVV or
  full PAN anywhere, at any level, including debug; weaken an idempotency check to make a test
  pass.
- **Security-sensitive**: `adapters/cardnet/` and `internal/auth/`. Changes there get a security
  pass before the general review, whichever harness or skill runs it. Never log request or response
  bodies in either.

## Authoritative docs

Read these rather than inferring; they are maintained and this file is not a summary of them.

- `docs/architecture.md` — service boundaries and why the ledger core is pure.
- `docs/adr/` — decision records. `0012` explains the idempotency model; read it before changing
  replay behavior.
- `docs/runbooks/settlement-failure.md` — what to do when settlement reconciliation diverges.
