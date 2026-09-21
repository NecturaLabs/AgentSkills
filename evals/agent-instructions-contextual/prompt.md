---
name: agent-instructions-contextual
description: The instruction-file trigger is embedded in a list of other quarter-close chores.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I'm closing out the Q3 cleanup ticket before we cut the release tag. Update the CONTRIBUTORS list,
confirm the version in package.json matches the tag we're about to cut, and then take a pass
through AGENTS.md — it's picked up a lot of one-off notes from individual PRs over the quarter and
I want it trimmed back to what's actually load-bearing before we ship.
