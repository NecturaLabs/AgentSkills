---
name: open-project-terminal-negative
description: Reading a file from a project is not opening a session; the skill must not fire.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Open the Canopy project's README.md and tell me what the install steps are.
