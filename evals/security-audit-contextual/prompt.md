---
name: security-audit-contextual
description: The trigger is embedded in a larger merge-readiness task rather than stated as a security request.
tags: [routing]
plugins: [".plugins/security-audit"]
# The setup reaches security-audit through this row of its global AGENTS.md; the eval sandbox loads
# no user instruction files, so the case carries the row.
append_system_prompt: "Working agreement: when a change touches auth, sessions, tokens, crypto, secrets, external input, deserialization, file or network boundaries, permissions or dependencies, load `security-audit:security-audit` before the review."
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Help me get this branch to merge-ready. It adds a CSV export: an admin picks a report, the handler
writes the file under the export directory using the report name the admin typed, and a new
third-party CSV library landed in the lock file. Tests pass and the changelog is updated. Walk it
through whatever still needs doing.

```diff
--- a/server/admin/exportReport.js
+++ b/server/admin/exportReport.js
+const { stringify } = require('fast-csv-writer');
+router.post('/admin/reports/export', requireAdmin, async (req, res) => {
+  const rows = await reports.rows(req.body.reportId);
+  const file = path.join(EXPORT_DIR, `${req.body.reportName}.csv`);
+  await fs.promises.writeFile(file, stringify(rows));
+  res.json({ file });
+});
--- a/package-lock.json
+++ b/package-lock.json
+    "node_modules/fast-csv-writer": {
+      "version": "0.3.1",
+      "resolved": "https://registry.npmjs.org/fast-csv-writer/-/fast-csv-writer-0.3.1.tgz",
+      "hasInstallScript": true
+    },
```
