---
name: backlog-maintenance-explicit
description: The user names the job: convert a TODO.md backlog into GitHub issues.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Convert the backlog in `TODO.md` into GitHub issues, filed properly, and retire the file.
