# Usage examples

Human output is the default in a terminal; `--json` gives the machine envelope. Agents should
always pass `--json`. Command and flag reference: `plugin/skills/necturalabs-fab/references/commands.md`.

## Search

```bash
necturalabs-fab search "medieval village"
necturalabs-fab search "medieval village" --engine unreal --count 10 --json
necturalabs-fab search "stylized trees" --style stylized --listing-type 3d-model --sort rating
necturalabs-fab search "castle" --hydrate 5 --engine-version 5.4   # verify versions on the top 5
```

## Owned assets

```bash
necturalabs-fab library
necturalabs-fab library "castle" --engine-version 5.4 --json
necturalabs-fab search "castle" --owned-only
necturalabs-fab ownership 1a2b3c4d-… 5e6f7a8b-… --json
```

## Free assets

```bash
necturalabs-fab search "footsteps" --free permanent        # always free
necturalabs-fab search "footsteps" --free limited-time     # paid, currently 100% off
necturalabs-fab search "footsteps" --free either           # both (two searches)
```

## Find and recommend

```bash
necturalabs-fab find "dark gothic ruined castle environment" \
  --engine unreal --engine-version 5.4 --prefer-owned --prefer-free --json

necturalabs-fab recommend "rigged low-poly zombie with walk and attack animations" \
  --engine unity --feature rigged --max-price 30 --require-engine --json
```

## Inspect

```bash
necturalabs-fab inspect 1a2b3c4d-… --ownership
```

## Download

```bash
necturalabs-fab download 1a2b3c4d-… --out Content/Fab/Castle --dry-run --json
necturalabs-fab download 1a2b3c4d-… --out Content/Fab/Castle --engine-version 5.4 --json
```

The response's `data.outputDir` is the absolute path written; `data.sidecar` points at
`necturalabs-fab.asset.json` inside it.

## Claim (approval required)

```bash
necturalabs-fab claim 1a2b3c4d-… --dry-run --json   # show the plan to the user
necturalabs-fab claim 1a2b3c4d-… --json             # exit 8, FAB_APPROVAL_REQUIRED
necturalabs-fab claim 1a2b3c4d-… --approve --json   # after the user agrees
```

## JSON in scripts

```bash
id=$(necturalabs-fab find "ruined castle" --engine unreal --json | jq -r '.data.candidates[0].asset.id')
necturalabs-fab download "$id" --out "Content/Fab/$id" --json | jq '.data.receipt'
```

Branch on the exit code first, then `error.code`: `plugin/skills/necturalabs-fab/references/errors.md`.

## Per-project defaults

```bash
necturalabs-fab config init --project     # writes .necturalabs-fab.toml
```

```toml
[defaults]
engine = "unreal"
engine-version = "5.4"

[download]
directory = "Content/Fab"
```

With that file, `necturalabs-fab find "castle"` already targets Unreal 5.4 and downloads land in
`Content/Fab/<listing id>`.
