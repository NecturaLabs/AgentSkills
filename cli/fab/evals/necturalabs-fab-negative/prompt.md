---
name: necturalabs-fab-negative
description: Asset-adjacent engine work that must not trigger marketplace discovery.
tags: [routing]
plugins: ["../../plugin"]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

The imported castle meshes under Content/Environments/Castle have their LODs set up wrong: LOD1
kicks in far too early. Fix the LOD screen sizes on those static meshes.
