---
name: open-project-terminal-implicit
description: A request for a fresh Claude session in a project without saying terminal.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I want a new Claude session going in the Arcade project, on workspace 1, bypass permissions, so I can start it on something else while you finish here.
