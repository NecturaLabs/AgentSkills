---
name: security-review-contextual
description: The trigger is embedded in a larger merge-readiness task rather than stated as a security request.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Help me get this branch to merge-ready. It adds a CSV export: an admin picks a report, the handler
writes the file under the export directory using the report name the admin typed, and a new
third-party CSV library landed in the lock file. Tests pass and the changelog is updated. Walk it
through whatever still needs doing.
