---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?agent-orchestration"'
min: 1
weight: 1
---

Between a changelog bump and a summary, the user asks for six services to be upgraded side by side
by separate agents without colliding on a shared build config. The orchestration skill must fire
for that part of the work.
