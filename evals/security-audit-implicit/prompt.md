---
name: security-audit-implicit
description: A natural request with an obvious threat surface that should route without naming the skill.
tags: [routing]
plugins: ["../..", "security-audit@necturalabs"]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I added a link-preview endpoint. It takes a URL from the request body, fetches it server-side,
parses the page for a title and an image, and returns them. Can you look over what I wrote before I
merge it?
