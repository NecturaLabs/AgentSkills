---
name: testing-implicit
description: Natural request that should route to the testing skill without naming it.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I just fixed a bug where discount codes with trailing whitespace weren't being trimmed before the
lookup, so `"SAVE10 "` was silently treated as invalid. Make sure this doesn't come back.
