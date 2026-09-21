---
name: testing-negative
description: Close neighbour that must not fire the testing skill — explaining an existing test, not authoring one.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Can you explain what this existing test is actually verifying? I'm about to touch the code
nearby and want to understand what it covers before I start.

```js
test('handles concurrent checkout requests', async () => {
  const cart = await seedCart({ items: 1, stock: 1 });
  const [first, second] = await Promise.all([
    checkout(cart.id),
    checkout(cart.id),
  ]);
  const outcomes = [first.status, second.status].sort();
  expect(outcomes).toEqual(['conflict', 'ok']);
  expect(await stockFor(cart.items[0].sku)).toBe(0);
});
```
