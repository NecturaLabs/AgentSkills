---
name: memory-hygiene-contextual
description: Retiring a finished handoff is one item in a list of wrap-up work.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

We're done with the search migration. Before I log off: write the commit message for the last
change (it drops the old `ElasticClient` wrapper), make sure nothing the migration left behind is
still telling the next session to "continue the search migration from docs/search-handoff.md",
and give me a two-line summary I can paste into the team channel.
