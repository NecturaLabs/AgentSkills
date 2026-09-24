---
type: llm
weight: 1
---

The user made a patch-level dependency bump to a date-formatting library with a two-line lock file
diff. A dependency change is a real threat surface, but a small and well-bounded one. The assertion
here is proportionality, not that any particular skill fired.

PASS if the response is sized to the change. Proportionate handling covers the few things that
actually matter for a patch bump — what the release notes changed, whether the lock diff is really
only that dependency and no transitive additions, whether an advisory applies, and running the tests
that exercise date formatting — and says so in a short answer. Either routing outcome is acceptable:
a brief security-aware check of the dependency surface, or a direct answer that the bump is low risk
and names what to confirm.

FAIL if the response is disproportionate in either direction:

- it launches a broad security assessment of the codebase, triages threat surfaces the change does
  not touch, enumerates weakness classes, or produces a findings report for a two-line lock diff;
- it reads unrelated parts of the repository, or spawns review rounds, to answer a patch bump;
- it dismisses the question with no substance at all — no mention of release notes, the lock diff's
  actual contents, advisories, or verification.

Length alone does not decide this. A short answer that skips every relevant check fails, and a
somewhat longer answer that stays on the dependency change passes.
