# Implementing another provider

A provider is anything that implements `FabProvider` (`src/provider/mod.rs`). Agents, the skill
and every command stay unchanged when one is added or swapped.

## Steps

1. Create `src/provider/<id>/mod.rs` with a struct implementing `FabProvider`.
2. Implement `id`, `capabilities` and `health`; these three are required.
3. Implement the operations the backend supports. Leave the rest at their defaults — they return
   `FAB_UNSUPPORTED_CAPABILITY` — and set the matching `Capabilities` fields to `false`. Commands
   check capabilities before calling, so a partial provider degrades cleanly.
4. Map backend payloads into `src/model.rs` types in one module, the way
   `src/provider/fabcli/map.rs` does. Rules that callers depend on:
   - Never invent a value. Unknown is `None`/empty, and `coverage` says whether the group was
     fetched (`available`), skipped (`not-requested`) or failed (`unavailable`).
   - Pass every marketplace-authored string through `sanitize::text`/`sanitize::short`.
   - `Price::free` must mean *claimable at no cost now*, `temporarilyFree` distinguishes promos.
   - Asset `id` is the Fab listing uid.
   - `listings` (several ids at once) defaults to calling `listing` for each; override it when the
     backend can fetch concurrently, as the FabCLI provider does for hydration and descriptions.
   - `licenses` holds the licences a listing is offered under, named as `src/model.rs` documents;
     `coverage.licenses` says whether they were established. `search` and `listing` fill them.
5. Map backend failures onto `ErrorCode` (`src/error.rs`). Authentication problems must be
   `AuthRequired`/`AuthExpired`; unexpected shapes must be `ProviderProtocol`, never a panic.
6. Register the id in `commands::build_provider` and `KNOWN_PROVIDERS` (`src/commands/mod.rs`),
   plus any settings it needs in `src/config.rs`.
7. Add contract tests: mapping tests against recorded payloads, and CLI tests that run the real
   binary against a test double, as `tests/` does with `mock-fabcli`.

## Rules that are not negotiable

- **No purchase method.** The trait has none on purpose; adding one is a change to the contract
  and to ADR 0003, not an implementation detail. `capabilities().purchase` stays `false`.
- **`claim_free` verifies the price itself**, even though the claim command already did.
- **Credentials stay inside the provider** and never appear in any returned value, error message
  or log line.
- **`download` honours `OverwritePolicy`** and `dry_run` (write nothing on a dry run).

## Selecting it

`provider = "<id>"` in config, `NECTURALABS_FAB_PROVIDER=<id>`, or `--provider <id>`.
`necturalabs-fab capabilities --json` and `necturalabs-fab doctor --json` show what is active.
