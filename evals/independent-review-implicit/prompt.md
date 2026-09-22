---
name: independent-review-implicit
description: A natural request to check finished work before a pull request, without naming review.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

The refactor of the payment reconciliation module is done and the tests are green. It
moved the rounding logic out of the ledger writer and changed two public method
signatures. Before I open the pull request, take a proper look at what changed and tell me
whether it is actually ready.
