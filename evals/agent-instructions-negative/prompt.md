---
name: agent-instructions-negative
description: A request to explain what an AGENTS.md says, not to create, audit or change one.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Read this repository's AGENTS.md and tell me what it requires before a change can be
called done. I'm not asking you to change the file — I just want to know what it says.
