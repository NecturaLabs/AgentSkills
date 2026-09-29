---
name: memory-hygiene-ambiguous
description: A vague "our docs are out of date" request — the assertion is that it is routed to a documentation audit rather than treated as memory upkeep.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I think a lot of our docs are out of date — the runbook still mentions the old deploy script and
the architecture page shows a service we deleted. Can you check them?
