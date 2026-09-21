---
name: project-docs-negative
description: A request to explain the event stream in conversation, not to document it — one word away from the explicit case, and must not fire the skill.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Explain how this event stream works. I'm looking at the notifications feed and I don't understand
how updates get from the server to the client — just walk me through the mechanism.
