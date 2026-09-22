---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?project-docs"'
min: 1
weight: 1
---

Alongside a PR description, the user asks for an explanation of how three components fit together
and an on-call restart procedure: an architecture note and a runbook. The project-docs skill must
fire for that part of the work.
