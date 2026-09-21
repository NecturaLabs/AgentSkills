---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?agent-instructions"'
min: 0
max: 0
weight: 1
---

Fixing a 500 in one endpoint touches no instruction file and raises no question of what belongs in
one. The agent-instructions skill must not fire.
