---
name: agent-instructions-ambiguous
description: A single-rule placement question, borderline between a quick answer and a full audit.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

We just started pinning our Node version with a `.nvmrc`. Someone on the team wants to add a
reminder to AGENTS.md telling agents to use it. Worth adding, or is that redundant with the file
already being there?
