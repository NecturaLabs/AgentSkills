---
name: independent-review-ambiguous
description: A one-line behavioral change with a test — borderline between a trivial edit and a reviewable change.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I changed the default timeout in our HTTP client from 30 seconds to 10, and added a test
for the new value. That's the whole diff — one constant and one test. Is there anything I
should do before I merge it?

```diff
--- a/src/http/client.ts
+++ b/src/http/client.ts
@@ -3,7 +3,7 @@ import { withRetry } from './retry';
-export const DEFAULT_TIMEOUT_MS = 30_000;
+export const DEFAULT_TIMEOUT_MS = 10_000;

 export function createClient(opts: ClientOptions = {}) {
   const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
   return withRetry({ timeoutMs, attempts: opts.attempts ?? 3 });
 }
--- a/src/http/client.test.ts
+++ b/src/http/client.test.ts
@@ -12,3 +12,7 @@ describe('createClient', () => {
+  test('defaults to a 10 second timeout', () => {
+    expect(createClient().timeoutMs).toBe(10_000);
+  });
 });
```
