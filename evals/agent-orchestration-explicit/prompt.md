---
name: agent-orchestration-explicit
description: The user asks directly for a delegation plan across parallel subagents.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I want to split the database-driver migration across parallel subagents. Eight repositories each
need the same driver swapped, two of them share a generated client, and one final pass has to
confirm the whole fleet still builds. Plan the orchestration: which agents run in parallel, who owns
which files, what each one is told, and what happens if one of them fails.
