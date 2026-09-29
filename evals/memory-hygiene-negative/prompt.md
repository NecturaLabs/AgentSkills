---
name: memory-hygiene-negative
description: Saving a new preference is not tending existing memories; the skill must not fire.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Remember for next time: in this repo I want integration tests to hit a real Postgres container,
never a mocked database. We got burned last quarter when the mocks passed and the migration failed
in production.
