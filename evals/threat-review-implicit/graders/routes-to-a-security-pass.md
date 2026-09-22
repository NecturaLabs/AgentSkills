---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?(?:threat-review|security-review)"'
min: 1
weight: 1
---

Fetching a caller-supplied URL server-side is an outbound-request boundary, even though the user
never says "security". Either this skill or the harness's own security-review capability satisfies
it: native-first means the harness's reviewer is a legitimate route for this surface.
