---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?(?:threat-review|security-review)"'
min: 1
weight: 1
---

Refresh-token rotation is an identity and secrets surface, and the user asked for a security pass.
Either this skill or the harness's own security-review capability satisfies it: native-first means
the harness's reviewer is a legitimate route for this surface.
