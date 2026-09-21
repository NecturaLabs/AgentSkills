---
name: project-docs-ambiguous
description: A borderline case — a config tweak with a plausible but small rationale; the assertion is proportional behavior, not that a particular skill fires.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I bumped the HTTP client's connection-pool size from 10 to 25 to fix some request timeouts we were
seeing under load. It's a one-line config change and easy to revert if it turns out to be wrong.
Should I write this up somewhere, or is that overkill?
