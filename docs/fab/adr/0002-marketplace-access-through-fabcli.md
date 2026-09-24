# ADR: How necturalabs-fab reaches the Fab marketplace

**Status:** accepted
**Date:** 2026-09-22

## Context and problem statement

Fab has no public, versioned API. The endpoints that exist are undocumented and change without
notice, and signing in needs an embedded browser for Epic's OAuth flow and a second Fab web
session. FabCLI (<https://github.com/zirklerite/FabCLI>, GPL-3.0-or-later, v0.1.0 released
2026-05-03) already implements this with compact JSON output, structured errors and meaningful
exit codes. Agents need a stable interface that survives both upstream API changes and a later
change of backend.

## Considered options

1. Execute FabCLI as a child process behind a provider trait, and map its JSON into our own model.
2. Link FabCLI's code (or its `egs-api-rs` dependency) into necturalabs-fab.
3. Write a native Fab client now.
4. Expose FabCLI to agents directly with a skill.

## Decision outcome

Chosen option: "Execute FabCLI as a child process behind a provider trait", because it reuses a
working implementation of the hard parts (sign-in, the Fab session, chunked downloads with SHA-1
verification) while keeping its GPL licence at arm's length — separate programs communicating
through a command line and JSON are not a combined work — and keeping credentials entirely inside
FabCLI. The provider trait means agents never depend on FabCLI; replacing it is a new
`FabProvider` implementation, not an interface change. Linking would make necturalabs-fab a derivative
of GPL code; a native client now would duplicate working code against moving targets; exposing
FabCLI directly would couple every agent and skill to its flags and field names.

The supported FabCLI range is pinned (`>=0.1.0, <0.2.0` in
`src/provider/fabcli/version.rs`). FabCLI is pre-1.0 over an unversioned upstream, so each new
minor version is verified against the mapping layer before the range widens. Outside the range,
every data command fails with `FAB_PROVIDER_UNSUPPORTED_VERSION` before any call is made.

### Consequences

- **Good:** upstream breakage surfaces as a mapped error; a native provider can replace FabCLI
  without touching agents; necturalabs-fab's own licence is unconstrained by the GPL.
- **Bad:** one extra process per operation (a few milliseconds plus FabCLI's own startup); features
  FabCLI lacks — dry-run downloads with file counts, resumable downloads — are unavailable or
  partial; necturalabs-fab must track FabCLI releases.

## Related

- `docs/fab/licensing.md` — what the GPL means for distribution.
- `docs/fab/providers.md` — how a replacement provider plugs in.
