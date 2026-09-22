---
name: agent-instructions-negative
description: A request to explain what an AGENTS.md says, not to create, audit or change one.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

This is our repository's AGENTS.md. Tell me what it requires before a change can be called done.
I'm not asking you to change the file — I just want to know what it says.

```markdown
# Ledger service

## Commands
- Test: `make test`
- Lint: `make lint`

## Done means
- `make test` and `make lint` both pass, and you say what they printed.
- A schema change ships with its migration and a tested rollback.
- The changelog entry under "Unreleased" is updated in the same change.
- Anything left unfinished is listed in the pull request description.
```
