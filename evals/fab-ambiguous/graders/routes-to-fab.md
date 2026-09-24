---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?fab"'
min: 1
weight: 1
---

The user asks to "get" a named marketplace pack, which may be paid; the fab skill must fire so it
can check ownership and price and refuse any purchase.
