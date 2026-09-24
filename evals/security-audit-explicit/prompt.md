---
name: security-audit-explicit
description: The user names the job directly — a security assessment of a refresh-token rotation change.
tags: [routing]
plugins: ["../..", "security-audit@necturalabs"]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Review this change to refresh-token rotation for security problems before I put it up for review.
The diff replaces the single long-lived refresh token with a rotating family: each refresh issues a
new token, stores it, and marks the previous one used.
