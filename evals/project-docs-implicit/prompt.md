---
name: project-docs-implicit
description: Natural request that should route to the project-docs skill without naming it.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

We just agreed to drop our self-hosted job queue in favor of the managed queue service, mostly
because on-call kept getting paged for queue-worker crashes at 3am and nobody wants to keep
maintaining that. It's a real commitment — migrating back would mean rebuilding the worker fleet —
and people are going to ask in six months why we did this. Somebody should write down what we
considered and why we landed here before it's forgotten.
