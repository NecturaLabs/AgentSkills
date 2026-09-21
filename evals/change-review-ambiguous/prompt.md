---
name: change-review-ambiguous
description: A one-line behavioral change with a test — borderline between a trivial edit and a reviewable change.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I changed the default timeout in our HTTP client from 30 seconds to 10, and added a test
for the new value. That's the whole diff — one constant and one test. Is there anything I
should do before I merge it?
