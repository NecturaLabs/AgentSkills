# Security model

## What is protected

- **The user's money.** necturalabs-fab has no purchase capability of any kind.
- **The user's account.** The only account-changing operation, `claim`, needs approval by default.
- **The user's credentials.** necturalabs-fab never handles them.
- **The user's files.** Downloads refuse to overwrite by default.

## Action classes and approval

Every command declares a class, returned as `action.class` in each response.

| Class | Commands | Default policy |
|---|---|---|
| `read` | search, find, recommend, inspect, ownership, library, auth status, doctor, capabilities | automatic |
| `local-write` | download, config init | automatic (`approval.download`: `allow` or `deny`) |
| `account-mutation` | claim | **approval required** (`approval.claim`) |
| monetary | none exist | never |

With `approval.claim = "require"`, `claim` without `--approve` exits 8 with
`FAB_APPROVAL_REQUIRED`, `requiresApproval: true`, and the plan in `error.details.plan` (target,
effects, `reversible: false`). `"deny"` refuses even with `--approve`; `"allow"` runs without it.

Before any claim reaches the provider, necturalabs-fab fetches the listing and requires
`price.free == true`. A paid listing and a listing whose price is unknown both exit 9
(`FAB_ASSET_NOT_FREE`). FabCLI then applies its own independent free check before its
`add-to-library` request. See ADR 0003.

**Residual risk.** Both checks read the marketplace's current fields. If Fab changed what those
fields mean, or made its free-claim endpoint charge a saved card, the checks could pass on a
charged claim. FabCLI's maintainer recommends removing saved payment methods from the Epic/Fab
account if claims must be risk-free; necturalabs-fab cannot remove this risk.

## Credentials

FabCLI stores the Epic OAuth token (auto-refreshed, ~1 year refresh token) and the Fab web session
(~90 days, not refreshable) in its config directory (`~/.config/fabcli/token.json` on Linux,
`%APPDATA%\fabcli\token.json` on Windows), AES-256-GCM encrypted with a key held in the OS
keystore (libsecret / DPAPI). Its trust boundary is "this user on this machine": any process
running as the user can ask FabCLI to act. necturalabs-fab does not widen that:

- it never reads, writes, copies or passes the token file, and passes no credential on a command
  line or in an environment variable;
- it runs FabCLI with the inherited environment (FabCLI needs the keystore session) plus three
  harmless variables: `FABCLI_NO_UPDATE_CHECK=1`, `FABCLI_NO_TIPS=1`, and
  `FABCLI_LIBRARY_CACHE=1` when `fabcli.library-cache` is on;
- every byte of FabCLI stderr is passed through `sanitize::redact` (JWTs, long opaque tokens,
  `*token*=`/`*session*=`/`*cookie*=` values) before it is echoed or quoted in an error;
- `auth status` and `doctor` report session state (present, expiry, days left), never identity or
  secret material.

Sign-in is interactive by design. `auth login` only describes the steps. `auth login --run`, run by
a human in a terminal, starts FabCLI's sign-in: Epic's page opens in the default browser and the
authorization code is pasted into FabCLI's own prompt, never through necturalabs-fab. `--account`
opens FabCLI's window for the account session. Without an interactive terminal `--run` starts
nothing, so an agent can never open a sign-in or block on input.

## Configuration trust

A `.necturalabs-fab.toml` arrives with whatever repository an agent is working in, so the project
layer may set only project defaults (engine, version, preferences, counts, output mode, and a
download directory that must be a relative path inside the project). It may not set `provider`,
`fabcli.path`, `fabcli.version-requirement`, `approval.*` or `download.overwrite`; a project file
that tries fails with `FAB_CONFIG_INVALID` before anything runs. Those keys come only from the
user config, `NECTURALABS_FAB_*` environment variables or flags.

## Untrusted input

- **Marketplace text** — titles, descriptions, seller names, tags — is third-party content an agent
  will read. It is stripped of control characters, ANSI sequences and bidi/zero-width characters
  and length-capped. The skill tells agents to treat any instruction inside it as a red flag.
- **Listing ids** become directory names and provider arguments, so only `[A-Za-z0-9._-]{1,128}`
  is accepted — not starting with `-` or `.`, not ending with `.`, and not a Windows device name.
  The check runs on input, again at the provider boundary, and on every id the marketplace
  returns; rows with an unsafe id are dropped.
- **Provider arguments** carry every value in `--flag=value` form, so no value can be read as a
  flag.
- **Provider output** is parsed as data only; an unexpected shape is `FAB_PROVIDER_PROTOCOL`.
- **Child processes** get argument arrays, never a shell; every call has a deadline and is killed
  when it passes. Output is read with a bounded grace period, so a background process the
  provider leaves holding its pipes cannot stall a call.
- **Provider stderr** is kept verbatim only in memory. FabCLI's structured errors are parsed from it
  and then redacted; anything quoted or echoed as progress is redacted and stripped of control
  characters and escape sequences.

## Filesystem writes

Downloads go to `--out` or `<download.directory>/<listing id>`. The default policy `refuse` stops
if any previous necturalabs-fab download is present in the directory, and FabCLI itself refuses to
overwrite any file the download would replace; `force` and `require-empty` are explicit opt-ins.
The licence cache (`licenses.json` in the user cache directory) holds listing ids and licence
verdicts only; it is read with size and schema limits, and every entry is validated before use.
necturalabs-fab's own writes cannot be redirected through a planted symlink: the writability probe is
created with `create_new`, the sidecar is written to a fresh file and renamed into place, and a
sidecar path that is a link is refused.

## CI

CI runs on NecturaLabs' self-hosted runners. For `pull_request` events GitHub runs the workflow
file from the pull request itself, so no condition in a workflow can keep a fork's code off the
runners; the workflows therefore have no `pull_request` trigger, only pushes to `main`, tags and
manual dispatch. The runner group serving this public repository must also be restricted to this
repository's workflow files on `refs/heads/main` and version tags, and fork pull-request
workflows must require approval (organization settings, not files in this repository).

## Account-suspension risk

FabCLI drives undocumented endpoints, which may breach Epic's and Fab's terms of service. Keep
usage modest and sequential; do not share one account between several automation drivers.
