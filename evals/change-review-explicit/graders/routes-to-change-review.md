---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?change-review"'
min: 1
weight: 1
---

The change-review skill must fire: the user asked for a finished, uncommitted, multi-file
behavioral diff to be reviewed before merge.
