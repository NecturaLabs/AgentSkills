# Checking that an asset fits the project

Run `necturalabs-fab inspect <id> --json` and check each item below against the project.
Report every item you could not verify; do not treat silence as a pass.

## Engine and version

- Find the project's engine version from the project itself:
  - Unreal: `EngineAssociation` in the `.uproject` (e.g. `"5.4"`).
  - Unity: `m_EditorVersion` in `ProjectSettings/ProjectVersion.txt`.
  - Godot: `config/features` in `project.godot`.
- `asset.engines` lists engines the listing ships for; `asset.engineVersions` uses Epic labels
  (`UE_5.4`). `5.4` and `UE_5.4` are the same version.
- Unreal content packaged for an older 5.x version usually opens in a newer 5.x editor; content
  for a newer version than the project does not open in an older editor. Say which case applies.
- A listing with an `fbx`, `obj`, `gltf` or `blender` format is engine-neutral source art: usable
  in any engine after import, with materials rebuilt. Name that cost.
- `coverage.formats: "unavailable"` means the format data could not be fetched: the listing is
  unverified, not incompatible.

## Formats and platforms

- `formats[].distributionMethod`: `asset-pack` adds to an existing project; `complete-project`
  is a standalone project to migrate from; `engine-plugin` / `tool-and-plugin` installs into the
  engine and may need a compiled binary for the target platform.
- For plugins, `platforms` must include every platform the project ships on.

## Technical fit

`technical` fields come from the seller's free text (`source: "parsed-text"`). Use them to
screen — triangle counts for a mobile budget, `rigged`/`animated` for characters, texture sizes
for memory — and say they are seller-stated.

## Licence

- `licenses` names what the listing is offered under: `Standard License (Personal)`,
  `Standard License (Professional)` or `CC BY 4.0`. The Fab Standard License permits commercial use.
  Its Personal and Professional tiers grant the same rights and differ only by the buyer's gross
  revenue over the last 12 months (under or over US$100,000); a paid listing may price the tiers
  differently, so name the tier when reporting a price
  (<https://dev.epicgames.com/documentation/fab/licenses-and-pricing-in-fab>).
- `CC BY 4.0` requires crediting the creator wherever the asset is used; tell the user.
- An owned asset reports the tiers the listing offers, not the tier the user acquired.
- If `licenses` is absent, open `asset.url` and tell the user you could not confirm the licence
  from the CLI: `coverage.licenses: "available"` means a licence Fab's filter does not name (such
  as the legacy UE Marketplace License), `"unavailable"` that it could not be established. Never
  state a licence you did not see.
- `price.highest`, when present, is the dearest tier; a company over the Personal tier's revenue
  limit may owe that one.
- A limited-time free claim grants the same licence as a purchase, but only if claimed before
  the promotion ends.

## Free vs paid

- Prefer owned, then free, when quality and fit are comparable. A paid asset is only worth
  mentioning when it is clearly better; present it with its price and let the user decide.
- Never describe a limited-time-free asset as permanently free.
