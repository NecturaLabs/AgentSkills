---
name: threat-review-negative
description: A copy change on a sign-in page — adjacent to a sensitive area but with no threat surface, so the skill must not fire.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Change the text on the sign-in page. The heading should read "Welcome back" instead of "Sign in to
your account", and the link under the form should say "Forgot your password?" instead of "Reset
password". Copy only — nothing else on the page changes.
