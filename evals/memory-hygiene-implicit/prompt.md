---
name: memory-hygiene-implicit
description: A startup notice flags broken memory entries and a missing handoff file; the user asks to sort it out without naming the skill.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

This came up when the session started:

```
memory check: 3 issues
- MEMORY.md lists release-checklist.md, which does not exist
- deploy-handoff.md points at docs/deploy-handoff.md, which is gone
- api-conventions.md names src/api/v1/, which does not exist
```

Can you sort that out?
