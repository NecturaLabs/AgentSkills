---
name: testing-contextual
description: Realistic feature task where the test-authoring work is embedded in other work.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Add a `formatCurrency(cents, currencyCode)` helper to the invoicing module and wire it into the PDF
export so totals render with the right symbol and decimal places. Once it's in, make sure the
rounding and currency-symbol edge cases are covered so a future refactor doesn't silently break them.
