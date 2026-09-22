---
name: independent-review-contextual
description: The review trigger is embedded in a list of other release chores.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I'm wrapping up the ticket for the CSV export pipeline. Please draft the changelog entry for it,
check that the package version got bumped, and then go over the finished change end to end — it
spans the exporter, the column mapper and the batch writer — before I hand it to the release branch.
Nothing is committed yet; this is the whole diff.

```diff
--- a/package.json
+++ b/package.json
-  "version": "2.3.1",
+  "version": "2.4.0",
--- a/src/export/exporter.ts
+++ b/src/export/exporter.ts
 export async function exportReport(reportId: string, out: Writable) {
-  const rows = await loadRows(reportId);
-  out.write(toCsv(rows));
+  const columns = mapColumns(await loadSchema(reportId));
+  for await (const batch of loadRowsInBatches(reportId, 500)) {
+    await writeBatch(out, columns, batch);
+  }
 }
--- a/src/export/columnMapper.ts
+++ b/src/export/columnMapper.ts
+export function mapColumns(schema: Field[]): Column[] {
+  return schema
+    .filter((f) => !f.hidden)
+    .map((f) => ({ key: f.name, header: f.label ?? f.name }));
+}
--- a/src/export/batchWriter.ts
+++ b/src/export/batchWriter.ts
+export async function writeBatch(out: Writable, columns: Column[], rows: Row[]) {
+  const lines = rows.map((r) => columns.map((c) => String(r[c.key] ?? '')).join(','));
+  if (!out.write(lines.join('\n') + '\n')) await once(out, 'drain');
+}
```
