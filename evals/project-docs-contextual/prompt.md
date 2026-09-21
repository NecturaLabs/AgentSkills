---
name: project-docs-contextual
description: The documentation trigger is embedded in a list of other wrap-up work.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I just finished wiring the new event-bus consumer into the checkout service — it replaces the old
cron-based reconciliation job. Before I hand this off: rebase onto main, make sure the tests still
pass, and then put together something that explains how the consumer, the bus and checkout fit
together for whoever touches this next, plus the steps for restarting a stuck consumer since that's
going to come up on-call.
