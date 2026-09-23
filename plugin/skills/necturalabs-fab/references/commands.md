# necturalabs-fab command reference

All commands accept these global flags: `--json` (machine envelope), `--human`,
`--output json|human` (same as the two before), `--quiet`,
`--config <path>`, `--provider <id>`, `--fabcli-path <path>`, `--timeout <seconds>`, `--raw`
(adds untouched provider payloads; large, unstable, debugging only).

## Envelope

```json
{"ok": true, "command": "search", "requiresApproval": false,
 "action": {"operation": "search", "class": "read", "requiresApproval": false, "approved": true, "...": "..."},
 "data": {}, "warnings": [], "meta": {"version": "0.1.0", "provider": "fabcli", "elapsedMs": 412}}
```

On failure `ok` is `false`, `data` is absent and `error` holds `code`, `message`, `recoverable`,
`retryable`, and optionally `hint`, `details`, `provider`.

`action.class` is one of `read`, `local-write`, `account-mutation`. There is no monetary class
in any response: those actions do not exist.

## Asset shape

Prices (`amount`, `original`, `localPrice`) are exact decimal **strings** with two decimals
(`"19.99"`), in `currency`; compare them as decimals, never as floats. `--max-price` and
`--min-price` take the same form (`30`, `29.99`).

Fields that are unknown are **omitted**, not null. `coverage` says why:
`available`, `not-requested` (cheap path skipped it) or `unavailable` (asked, no answer).

```json
{"id": "uuid", "provider": "fabcli", "title": "…", "url": "https://www.fab.com/listings/uuid",
 "publisher": {"name": "…"}, "category": {"name": "…", "slug": "…"}, "listingType": "3d-model",
 "kind": "model3d", "tags": ["castle"],
 "price": {"amount": "0.00", "original": "19.99", "currency": "USD", "discountPercent": 100,
           "free": true, "temporarilyFree": true, "freeUntil": "2026-10-06T13:59:00Z"},
 "owned": false, "licenses": ["Standard License (Personal)", "Standard License (Professional)"],
 "formats": [{"code": "unreal-engine", "distributionMethod": "asset-pack",
              "engineVersions": ["UE_5.4"], "platforms": ["Windows"]}],
 "engines": ["unreal"], "engineVersions": ["UE_5.4"], "platforms": ["Windows"],
 "technical": {"triangles": 184000, "lods": 3, "textureResolutions": ["4096x4096"],
               "rigged": false, "source": "parsed-text"},
 "rating": {"average": 4.6, "count": 128}, "publishedAt": "2026-06-01T10:00:00Z",
 "detailLevel": "detail",
 "coverage": {"formats": "available", "ownership": "not-requested",
              "technical": "available", "pricing": "available", "licenses": "available"}}
```

`technical` with `source: "parsed-text"` was extracted from the seller's free text: advisory.

`licenses` lists the licences the listing is offered under: `Standard License (Personal)`,
`Standard License (Professional)` or `CC BY 4.0`. `search`, `find`, `recommend`, `promos` and
`inspect` fill it for every row; `library` for the entries whose details it fetches. Each one was
confirmed by Fab returning that listing for that licence, so a licence Fab's filter does not name
(the legacy UE Marketplace License, for one) leaves `licenses` absent with
`coverage.licenses: "unavailable"`, meaning unknown, not unlicensed, and adds a warning counting
those listings. A run sends at most 150 licence searches and stops after a rate limit, so the
listings past that are unknown too.

## Discovery

| Command | Purpose |
|---|---|
| `search "<query>"` | Marketplace retrieval in marketplace order, with `owned` whenever a session allows and `licenses` for every row. `--hydrate N` fetches detail for the first N rows. `--cursor` pages. |
| `find "<need>"` | Search + enrich top `--hydrate` (default 6) + deterministic ranking; returns `--top` (default 5). |
| `recommend "<need>"` | `find` with top 3 and a `recommendation` object (`listingId`, `confidence`, `why`, `blockers`, `requiresApproval`). |
| `library ["<words or id>"]` | Owned assets, matched client-side on title, description, tags, listing id (or its first segment) and link; `--engine`, `--engine-version`. Paged: `--limit` (default 100, max 500), `--page N`; data has `matched`, `page`, `pages`, `pageSize`, `nextPage`. Real descriptions and `licenses` are fetched from listings when 10 or fewer match, or for the page with `--details`; `--no-details` never. Entries without `url` are engine builds or Epic plugins, not Fab listings. |

Filters shared by `search`/`find`/`recommend`:

| Flag | Meaning |
|---|---|
| `--engine unreal\|unity\|godot\|blender\|uefn\|metahuman` | Target engine (server-side filter). |
| `--engine-version 5.4` | Checked against listing detail, so only enriched rows can be filtered. |
| `--format fbx` | Required asset format. Repeatable. |
| `--category`, `--listing-type`, `--style`, `--license` | Marketplace slugs. Repeatable. `--style` values are ANDed by Fab. |
| `--feature rigged` | Required technical feature. Repeatable. |
| `--seller NAME` | One seller. |
| `--free permanent\|limited-time\|either\|any`, `--free-only` | Which "free" (see SKILL.md). `either` costs two searches. |
| `--owned-only` | Search the library instead of the marketplace. |
| `--with-ownership` | Require `owned` on rows: without a session the command fails instead of leaving it out. `search` and `find` add it on their own whenever a session allows. |
| `--min-price`, `--max-price`, `--min-rating` | Numeric bounds. `find` also excludes paid candidates above `--max-price`. |
| `--published-since YYYY-MM-DD` | Absolute date only. Compute it yourself. |
| `--sort relevance\|newest\|oldest\|price-asc\|price-desc\|rating\|discount\|title` | Order. |
| `--count N` | Results requested (1–500, default 24). |
| `--filter KEY=VALUE` | Raw marketplace filter. Unvalidated escape hatch: a typo silently returns nothing. |

`find`/`recommend` extras: `--top N`, `--hydrate N`, `--require-engine` (drop candidates that
*positively* lack the engine/version; unknown support is never dropped),
`--prefer-owned`/`--no-prefer-owned`, `--prefer-free`/`--no-prefer-free`.

`find` data: `interpretation`, `considered`, `hydrated`, `candidates[]` (`rank`, `score` 0–1,
`signals` per factor 0–1, `reasons`, `hydrated`, `asset`), `excluded[]` (`id`, `reason`),
`nextSteps[]`.

## Single listing

| Command | Purpose |
|---|---|
| `inspect <id>` | Detail plus formats, ownership and licences. `--no-formats` skips the formats call; a missing account session leaves `owned` out with a warning (`--ownership` is accepted and changes nothing); `--full-description` disables truncation (600 chars). |
| `ownership <id>...` | `results[]` of `{listingId, owned, entitlementId, licenses, wishlisted}`. Needs the account session. |

## Acquisition

| Command | Class | Notes |
|---|---|---|
| `download <id> --out DIR` | local-write | `--engine-version`, `--platform`, `--overwrite refuse\|force\|require-empty` (default refuse), `--jobs N`, `--dry-run`, `--no-sidecar`. Without `--out`, writes to `<download.directory>/<id>`. For an owned asset with several engine versions or platforms and none given, picks the configured engine version if shipped, else the newest, and this machine's platform (Windows on Linux); each choice is a warning. |
| `claim <id>` | account-mutation | Refused unless `--approve` (default policy). `--dry-run` returns the plan. Paid or unknown-price listings are always refused. |
| `promos` | read | Fab's current limited-time free listings: `promos[]` of `{id, title, url, owned, listPrice, currency, freeUntil, licenses, publisher}`, `count`. A discount the search omits is confirmed from the listing detail. |
| `promos claim [<id>...]` | account-mutation | Claims every current promo not yet owned (or only the ids given; others land in `skipped`). One approval covers the listed batch; `--dry-run` returns `plan`, `toClaim`, `skipped`. Each listing is re-checked as free right before its claim; per-item failures are in `results`. |

Download data: `receipt` (`files`, `bytes`, `elapsedSeconds`, `title`, `engineVersions`,
`platforms`), `outputDir` (absolute), `sidecar` (path to `necturalabs-fab.asset.json`). Under the
default `refuse` policy, a directory that already holds a `necturalabs-fab.asset.json` is refused
whatever listing it names; pick another `--out` or ask the user before forcing.

## Operations

| Command | Purpose |
|---|---|
| `auth status` | `auth.authenticated` (reads), `auth.accountActionsAvailable` (claim, ownership), days remaining. |
| `auth login` | Describes how to sign in and starts nothing. A human runs `auth login --run` in a terminal: Epic's sign-in page opens in the default browser and the code it shows is pasted back. `--account` signs in the account session (claim, ownership) through FabCLI's window. Without a terminal, `--run` starts nothing and says so. |
| `doctor` | Read-only health checks with `status` ok/warn/fail per check and hints. |
| `capabilities` | What the active provider supports, and per command its `actionClass`, the configured `policy` (`allow`/`require`/`deny`), `allowed` and `requiresApproval`. |
| `config show\|path\|init` | Effective config with layer provenance; `init --project` writes `.necturalabs-fab.toml` (project defaults only — approval, overwrite and provider settings are user-config only). |
| `skill status` | Whether the plugin is installed for Claude Code and Codex, and any hand-placed duplicate. |
