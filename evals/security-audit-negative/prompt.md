---
name: security-audit-negative
description: A copy change on a sign-in page — adjacent to a sensitive area but with no threat surface, so the skill must not fire.
tags: [routing]
plugins: [".plugins/security-audit"]
# The setup reaches security-audit through this row of its global AGENTS.md; the eval sandbox loads
# no user instruction files, so the case carries the row.
append_system_prompt: "Working agreement: when a change touches auth, sessions, tokens, crypto, secrets, external input, deserialization, file or network boundaries, permissions or dependencies, load `security-audit:security-audit` before the review."
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Change the text on the sign-in page. The heading should read "Welcome back" instead of "Sign in to
your account", and the link under the form should say "Forgot your password?" instead of "Reset
password". Copy only — nothing else on the page changes.
