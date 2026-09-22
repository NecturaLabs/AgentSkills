---
name: agent-orchestration-contextual
description: The delegation decision is embedded among ordinary release chores.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Before Friday's release: bump the changelog, then take the security-advisory upgrades across the
six services in the monorepo — each service has its own lockfile and test suite, and they can be done
side by side by separate agents as long as they don't collide on the shared build config — and
finally write me a short summary of what changed.
