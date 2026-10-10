---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?estimate-time"'
min: 0
max: 0
weight: 1
---

The user asks how long a past CI run took, which is reading a log, not estimating remaining project time. The estimate-time skill must not fire.
