---
name: agent-orchestration-implicit
description: A natural request that implies fanning work out to parallel workers without naming orchestration.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

We have fourteen independent API client modules that all need porting from the old HTTP library to
the new one. They share no code with each other. Get several workers going on them at once so this
finishes today, and make sure nobody steps on anyone else's files.
