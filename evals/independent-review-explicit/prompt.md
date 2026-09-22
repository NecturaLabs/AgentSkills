---
name: independent-review-explicit
description: The user asks for the independence guarantees by name — a reviewer that did not write the change, and adjudication of disputed findings.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I've finished the retry-and-backoff work on the queue consumer. It touches six files and changes how
failed messages are requeued, and nothing is committed yet. I want an independent review: a reviewer
that hasn't seen my reasoning, findings backed by evidence, and if it flags something I think is
deliberate, get that one finding adjudicated rather than just taking my word for it.
