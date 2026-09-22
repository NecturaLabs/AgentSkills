---
name: threat-review-ambiguous
description: A patch bump of a date-formatting library — a genuine dependency surface, but a small one; the assertion is proportionality.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I bumped our date-formatting library from 3.4.1 to 3.4.2 and regenerated the lock file. The lock
diff is two lines. Anything I should think about before I push?
