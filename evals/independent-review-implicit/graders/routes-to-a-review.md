---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?(?:independent-review|code-review)"'
min: 1
weight: 1
---

A finished cross-file refactor with changed public signatures, checked before a pull request, needs
a review even though the user never says "review". Either this skill or the harness's own
code-review capability satisfies it: native-first means the harness's reviewer is a legitimate
route, and this skill is the procedure around it.
