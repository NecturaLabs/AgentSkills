---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?security-review"'
min: 0
max: 0
weight: 1
---

Retry and backoff on a queue consumer touches none of the security-sensitive surfaces, so
the security review must not fire. The two skills have to stay distinguishable.
