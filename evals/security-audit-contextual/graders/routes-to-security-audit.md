---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?security-audit"'
min: 1
weight: 1
---

A new third-party library landed in the lock file. Dependency and supply-chain changes are a surface
a native security review commonly excludes, so the security-audit skill must fire even where the
harness has one.
