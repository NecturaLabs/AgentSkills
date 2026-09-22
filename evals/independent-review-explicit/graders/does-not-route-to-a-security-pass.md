---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?(?:threat-review|security-review)"'
min: 0
max: 0
weight: 1
---

Retry and backoff on a queue consumer touches none of the security-sensitive surfaces, so no
security pass may fire, neither this plugin's nor the harness's own. The two skills have to stay
distinguishable.
