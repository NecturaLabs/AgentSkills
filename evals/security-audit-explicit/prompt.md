---
name: security-audit-explicit
description: The user names the job directly — a security assessment of a refresh-token rotation change.
tags: [routing]
plugins: [".plugins/security-audit"]
# The setup reaches security-audit through this row of its global AGENTS.md; the eval sandbox loads
# no user instruction files, so the case carries the row.
append_system_prompt: "Working agreement: when a change touches auth, sessions, tokens, crypto, secrets, external input, deserialization, file or network boundaries, permissions or dependencies, load `security-audit:security-audit` before the review."
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Review this change to refresh-token rotation for security problems before I put it up for review.
The diff replaces the single long-lived refresh token with a rotating family: each refresh issues a
new token, stores it, and marks the previous one used.
