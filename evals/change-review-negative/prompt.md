---
name: change-review-negative
description: A one-word typo fix — a trivial diff that must not pull in review machinery.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

There's a typo in this line of our install guide — "recieve" should be "receive". Give me the
corrected line.

    After installation you will recieve a confirmation message.
