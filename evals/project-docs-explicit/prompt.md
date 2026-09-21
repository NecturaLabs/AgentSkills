---
name: project-docs-explicit
description: The user names the job directly — record the decision to replace polling with SSE.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Record the decision to replace polling with SSE for the notifications feed. We evaluated polling
every 5 seconds, long-polling, and SSE; we picked SSE because it cuts server load under high client
counts and we don't need bidirectional messages. This is a real architectural commitment — reverting
it means rewriting both the client and the gateway — so write it up somewhere it'll survive past this
conversation.
