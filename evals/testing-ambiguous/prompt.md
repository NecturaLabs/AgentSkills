---
name: testing-ambiguous
description: Genuinely borderline request between routine verification and testing work.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I just merged the payment retry backoff logic. Before I ship it, can you make sure it's solid?

```ts
// payments/retry.ts
export function nextDelayMs(attempt: number, random = Math.random): number {
  const base = 500 * 2 ** attempt;           // 500, 1000, 2000, ...
  const capped = Math.min(base, 30_000);
  return Math.floor(capped / 2 + random() * (capped / 2));
}

export async function chargeWithRetry(charge: () => Promise<Result>, maxAttempts = 5) {
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const result = await charge();
    if (result.ok || !result.retryable) return result;
    await sleep(nextDelayMs(attempt));
  }
  return { ok: false, retryable: false, reason: 'exhausted' };
}
```

```ts
// payments/retry.test.ts
test('first retry waits between 250 and 500 ms', () => {
  expect(nextDelayMs(0, () => 0)).toBe(250);
  expect(nextDelayMs(0, () => 0.999)).toBeLessThan(500);
});
```
