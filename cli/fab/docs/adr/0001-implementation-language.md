# ADR: Which language and runtime necturalabs-fab is built in

**Status:** accepted
**Date:** 2026-09-22

## Context and problem statement

necturalabs-fab is invoked by agents many times per task, on Linux, Windows and macOS, often inside
game repositories that have no JavaScript or Python toolchain. The repository started empty, so no
existing stack constrained the choice. The requirements that decide it: fast startup, a single
easy-to-install artifact, strongly typed internal models, a small dependency footprint, and no
heavyweight runtime.

## Considered options

1. Rust, single static binary.
2. TypeScript on Node.js.
3. Python.
4. Go.

## Decision outcome

Chosen option: "Rust", because it produces one self-contained binary with millisecond startup and
no runtime to install, gives exhaustive enums and serde-typed models for the stable contract, and
matches the ecosystem FabCLI and its API library already live in, which keeps a future native
provider in the same language. Node and Python need a runtime and a dependency install on every
machine an agent runs on; Go would satisfy the deployment requirements but is not installed in the
NecturaLabs environment and offers no advantage over Rust here.

### Consequences

- **Good:** one release binary per platform (or a `cargo` build); seven runtime crates, no
  async runtime (marketplace I/O happens in the provider process).
- **Bad:** contributors need a Rust toolchain; release binaries must be built per target.
