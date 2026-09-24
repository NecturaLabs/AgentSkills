---
name: security-audit-ambiguous
description: A patch bump of a date-formatting library — a genuine dependency surface, but a small one; the assertion is proportionality.
tags: [routing]
plugins: [".plugins/security-audit"]
# The setup reaches security-audit through this row of its global AGENTS.md; the eval sandbox loads
# no user instruction files, so the case carries the row.
append_system_prompt: "Working agreement: when a change touches auth, sessions, tokens, crypto, secrets, external input, deserialization, file or network boundaries, permissions or dependencies, load `security-audit:security-audit` before the review."
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I bumped our date-formatting library from 3.4.1 to 3.4.2 and regenerated the lock file. The lock
diff is two lines. Anything I should think about before I push?
