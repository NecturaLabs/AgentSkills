---
name: agent-instructions-explicit
description: The user names the job directly — audit the repo's AGENTS.md and remove stale guidance.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Our AGENTS.md hasn't been touched since we refactored the billing service months ago and I don't
trust it anymore. Audit it: check that the commands it documents still work, flag anything that's
gone stale against the current codebase, and remove guidance that no longer holds.
