---
name: agent-instructions-implicit
description: A natural request to set an agent up for a repo, without naming AGENTS.md or the skill.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

We're about to let a coding agent loose on this repository for the first time and I don't want it
guessing at the build command, wandering into the generated protobuf directory, or missing that the
billing module needs a human in the loop. Can you set it up so the next agent that opens this repo
actually gets that right from the start?
