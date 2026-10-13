# Issue standards

The bar: someone with no memory of the conversation can build, verify and close the issue from the
issue alone. Everything the writer learned goes in. Length is not the goal; completeness and
accuracy are, and a long issue stays scannable through its fixed sections.

## Title

Specific and action-oriented, no type or priority prefix ("Select the row a context menu acts on
when right-clicking", not "Bug: menu"). It names the outcome, not the symptom or the area.
Retitle when the scope changes.

## Body sections

In this order. Omit a section only when it has nothing true to say; never pad.

1. **Problem** or **Deliverable** — what is wrong or what must exist, in plain terms, with the
   user-visible consequence. A feature states every behaviour it must have (states, filters, sorts,
   empty and error states, defaults, persistence), not only the headline.
2. **Observed behaviour**, **Expected behaviour** and **Steps to reproduce** for a bug, with the
   environment (version, platform, configuration) when it matters. Quote exact strings and error
   text.
3. **Cause** (bugs) — what the code does, read from the code: the function or symbol, the file, why
   the output is wrong. Facts and hypotheses are separated; an unverified hypothesis says so and
   names what would confirm it.
4. **What the code shows** (anything non-trivial) — the current behaviour and structure the change
   builds on: the modules, types and functions involved, the existing mechanism the change
   extends, defaults and their values, counts. Replace "about 50 places" with the number and the
   places.
5. **Inventory** — when the work covers a set (every call site, setting, producer, state, theme,
   platform), the set itself as a list or table with a verdict per row, or the exact search that
   produces it when it is too long to paste. A deliverable that says "audit X" lists what X is as
   far as it can be derived cheaply and verifiably.
6. **Decisions** — owner decisions with their date, stated as rules ("A key that is unset is set
   to the recommendation"), then the decisions still open, each with a recommendation and the
   alternatives. Decisions survive every rewrite; a superseded one is marked as such, with the new
   one beside it.
7. **Constraints** — everything the change must respect, by name: the project's product rules and
   instruction files, ADRs and the ones to amend or add, legal and privacy text and its version
   fields, security-sensitive areas and the security pass they require, platform and accessibility
   limits, performance limits, keyboard rules, theme and token rules, documentation that must
   change in the same change. Related issues with the nature of the relation (blocks, depends on,
   supersedes in part, shares code with).
8. **Where to see it** — how an agent renders or reproduces the view or behaviour itself, instead
   of a description of a screenshot: the project's documented fixture, the exact commands with
   options (screenshot or run script, overlay or view names, demo scenarios, themes), and, for
   what the script cannot stage (an open menu, a live workflow, an environment variable), the
   other route (a driven session, a unit test on a fake environment) or the overlay or flag the
   change must add. Every command and option named was checked against the script or its help.
9. **Acceptance criteria** — a checklist of checkable outcomes, each passing or failing on
   evidence: tests (a regression test written first for a bug), the exact behaviours, the
   documentation updated, the screenshots required (each theme and size that matters), live checks
   against the real system, privacy and security checks. Each criterion names how it is shown. A
   criterion not yet run stays unchecked.

Voice: concise and direct, plain nouns and verbs, no praise, no restating the title, no summary
of the issue at its end, no filler. Quote and link, do not paraphrase from memory.

## Facts

A wrong reference is worse than none. Every factual claim in an issue — whoever wrote it, the
filer or the owner's request — is checked in the current tree before the issue is filed or passed
by a review, and gets one of four outcomes: verified, corrected, removed, or kept under a
"Not verified: <claim>; looked in <where>" line.

### What counts as verified

Only output seen during this task counts. The filer's text, the owner's wording, memory, an older
issue and a code comment are claims to check, never evidence.

| Claim | Verified when |
|---|---|
| File path | The file exists at that path in the current tree. |
| Symbol (function, type, constant, setting key, test name) | A search finds its definition in the named file, and the code there does what the issue says it does. A name found only in a comment or a string is not that symbol. |
| Line number | Replaced by the enclosing symbol. Kept only where no symbol can be named, after reading that line, and marked as drifting. |
| Behaviour ("X happens when Y", "only Z is shown", "nothing de-duplicates") | The path from trigger to visible result was read, and the issue names the symbol where the behaviour is decided. A filter, guard or condition along that path that changes the claim is written down. |
| Something the issue asks to add | The code was searched for it under its likely names. When it exists in full or in part (an overlay, a dedupe, a setting, a test), the issue says so and narrows to what is missing. |
| Count or inventory | Produced by a search or a read whose scope is stated in the issue: what was included, what was excluded (tests, the defining module, generated code, fixtures) and what text matching can miss (indirect calls, helpers). "About N" becomes the number, or the exact search. |
| Values defined in two places (defaults and recommendations, a table and its mirror, code and docs) | Both places were read, both are named, and the issue requires they agree. |
| Quoted string, UI text, documented rule | Found verbatim in the source or the document that holds it; the issue names that document so the change updates it. |
| Command, script option, overlay, flag, demo scenario | Read in the script's help text and in the source that parses it, not remembered. |
| A route to see or stage a state | The route was read end to end and can stage that state: the script passes the needed environment through, the renderer shows pointer, hover and tooltip states, the fixture has the needed remote or data. When it cannot, the issue says why and names what the change must add. |
| Issue reference (#N) | Its title and state were fetched and match what the text says it is. A closed duplicate is never cited as related. |
| Owner decision | Matches the owner's own words. Where those words and the code disagree (the owner says "author", the code shows the committer), both facts go in and the choice becomes an open decision. |

- Refer to code by file and symbol, never by line range alone.
- Never write what was not observed: no results, no "works", no reproduction that was not run.
- Never leave a check to the reader ("verify", "probably", "maybe a bigger bug") when it can be
  done now by reading or searching. Do it and write the result; when it cannot be done, write the
  "Not verified" line.
- A defect found while checking (a misleading label, a wrong default) goes into the issue it
  belongs to, in Cause or What the code shows, with the symbol and a criterion that tests it; when
  no issue covers it, search, then file one.
- Evidence from other tools and attachments the platform cannot carry is replaced by how to
  produce it (section 8); never refer to an attachment the reader cannot open, nor say that one is
  missing.
- No credentials, tokens, private paths, personal data or pointers to a person's private notes.

## Shape and scope

- One issue, one deliverable that can ship and be verified on its own. Work that is independent,
  or that someone can ship earlier, is split into its own issue; work that is only a piece of a
  larger deliverable stays a checklist inside it.
- A split is complete when: the new issue meets this whole standard on its own (its own Where to
  see it, criteria and labels, the moved requirements carried over verbatim); the source issue's
  body no longer repeats the moved part but states it by reference ("uses the toggle from #N") and
  keeps only what is its own; a comment on the source records the split; and every issue that
  pointed at the moved part gets a short comment naming the new issue.
- An issue that changes or supersedes another says so, and the other one says so too (a short
  comment on it, so its history shows when the decision changed). The body of an issue is the
  current truth; comments are the history. Never leave an old body contradicting a newer decision.
- Cite only issues that still matter: a closed duplicate is not a related issue. Search closed
  issues for earlier decisions on the same subject and link them.
- Read the bodies, not only the titles, of the open issues an issue cites or that a search turns
  up. When the new work makes part of one moot or changes it, comment on that issue.
- Issues on the same subject (the same code, setting, wording or tokens) use the same terms and
  values, say which of them owns which part, and link each other.
- Reversing something the project documented as intended is a design change, not a defect: it is
  an enhancement and the issue names the document that changes.

## Labels

Every triaged issue has exactly one of each, except closed duplicates (`duplicate` and a link to
the canonical issue are enough):

- **Type**: `bug`, `enhancement`, `maintenance`, `documentation`, `verification`, `owner-action`
  (decisions and external-account tasks only the owner can do). A bug is behaviour that departs
  from what the project documents or intends; reversing documented intent is an `enhancement`.
- **Area**: one `area:*` label naming the part of the project (git, ui, settings, hosting, ...).
- **Priority** (open issues): `priority:p0-critical`, `priority:p1-high`, `priority:p2-normal`,
  `priority:p3-low`.
- **Size** (open issues, remaining work): `size:small`, `size:medium`, `size:large`,
  `size:needs-estimate`; say why when no estimate is possible. Size follows what the investigation
  found, and is raised when the inventory turns out bigger than the title suggested.

Extra labels, when they apply: `needs-triage` (new, not yet confirmed; a maintainer removes it after
confirming scope, area, priority and size), `needs-verification` (live, platform or owner checks
remain), `security` (credential, trust, privacy or code-execution risk).

A label change after triage says why, in the report or a comment ("size raised: three platform
lists, an ADR and a new select state").

Keep any label catalogue file in the repository (for example `.github/labels.json`) and the live
labels identical.

## Priority

P0 critical: data loss, security exposure or a broken release. P1 high: a core workflow is
wrong or missing, or a trust problem. P2 normal: the default. P3 low: polish and wishes. Work the
open issues P0 first, then in issue-number order within a priority. When the owner says an area
matters more, raise the priority of that area's issues and say why in a comment.

## Linking

Reference the issue from the change that implements it (`Closes #N` only when every criterion is
verified, else `Refs #N`), and record on the issue what shipped, what was tested and what remains.
