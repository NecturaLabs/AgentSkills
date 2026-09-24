---
name: security-audit-implicit
description: A natural request with an obvious threat surface that should route without naming the skill.
tags: [routing]
plugins: [".plugins/security-audit"]
# The setup reaches security-audit through this row of its global AGENTS.md; the eval sandbox loads
# no user instruction files, so the case carries the row.
append_system_prompt: "Working agreement: when a change touches auth, sessions, tokens, crypto, secrets, external input, deserialization, file or network boundaries, permissions or dependencies, load `security-audit:security-audit` before the review."
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I added a link-preview endpoint. It takes a URL from the request body, fetches it server-side,
parses the page for a title and an image, and returns them. Can you look over what I wrote before I
merge it?
