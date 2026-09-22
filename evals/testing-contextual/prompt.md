---
name: testing-contextual
description: Realistic feature task where the test-authoring work is embedded in other work.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I added a `formatCurrency(cents, currencyCode)` helper to the invoicing module and wired it into the
PDF export so totals render with the right symbol and decimal places. Tidy its doc comment so it
says the amount is in minor units, and make sure the rounding and currency-symbol edge cases are
covered so a future refactor doesn't silently break them.

```ts
// invoicing/formatCurrency.ts
/** Formats a money amount for display. */
export function formatCurrency(cents: number, currencyCode: string, locale = 'en-US'): string {
  const digits = new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
    .resolvedOptions().maximumFractionDigits ?? 2;
  return new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
    .format(cents / 10 ** digits);
}
```

There are no tests for it yet.
