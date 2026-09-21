---
name: testing-explicit
description: User names the testing job directly, asking for a regression test for a named defect.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Our CSV import parser mishandles quoted commas — a value like `"Smith, John"` gets split into two
columns instead of staying together. Add a regression test that reproduces this defect before we fix
the parser.
