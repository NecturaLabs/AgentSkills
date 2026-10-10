---
name: estimate-time-negative
description: Timing a command is not estimating project progress; the skill must not fire.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

How long did the last full test run take? Check the CI log and tell me the slowest three suites.
