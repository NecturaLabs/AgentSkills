---
name: fab-contextual
description: The need for an asset emerges from project context during other work.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I'm wiring up footstep audio for the player controller, but we don't have any footstep sounds for
gravel or wood yet. Check whether we already own something suitable before we record our own.
