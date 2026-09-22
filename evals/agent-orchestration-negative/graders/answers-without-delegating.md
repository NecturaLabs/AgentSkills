---
type: llm
weight: 1
---

PASS if the response explains the difference — fan-out/fan-in splits work into independent branches
and recombines them at a barrier; a pipeline passes each item downstream as soon as it is ready — in
a few sentences, and stops.

FAIL if the response plans a delegation, spawns or proposes subagents, produces a topology for the
user's own work, or turns a conceptual question into an orchestration exercise.
