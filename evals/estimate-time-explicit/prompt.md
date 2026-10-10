---
name: estimate-time-explicit
description: The user names the job directly: an ETA and percent done for a port.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

How long until the Unity port is done, and what percent are we at? The checklist is in `docs/port-checklist.md`.
