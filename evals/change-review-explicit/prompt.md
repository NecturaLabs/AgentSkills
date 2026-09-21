---
name: change-review-explicit
description: The user names the job directly — review a finished multi-file behavioral diff before merge.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I've finished the retry-and-backoff work on the queue consumer. It touches six files and
changes how failed messages are requeued, and nothing is committed yet. Review this
multi-file behavioral diff before I merge it.
