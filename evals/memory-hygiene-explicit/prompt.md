---
name: memory-hygiene-explicit
description: The user names the job directly — clean up the project's stale saved memories.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Go through the saved memories for this project and clean out the stale ones. A few of them still
talk about the `feature/payments-v2` branch, which was merged and deleted last week, and one says
the billing rewrite is "on hold", which stopped being true when we restarted it on Monday.
