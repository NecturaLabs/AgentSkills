---
name: change-review-contextual
description: The review trigger is embedded in a list of other release chores.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I'm wrapping up the ticket for the CSV export pipeline. Please update the changelog entry
for it, check that the package version got bumped, and then go over the finished change
end to end — it spans the exporter, the column mapper and the batch writer — before I hand
it to the release branch.
