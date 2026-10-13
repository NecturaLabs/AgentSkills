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

- Every path, symbol, function, type, command, option, setting name, count and quoted string was
  checked against the current code or output. A wrong reference is worse than none.
- Refer to code by file and symbol; use a line number only when the symbol cannot be named, and
  say it may drift.
- Counts and lists come from a search or a read, not from memory. Say what was searched when a
  number could be off (text matching misses indirect calls).
- Never write what was not observed: no results, no "works", no reproduction that was not run.
  What could not be checked is named under its own line ("Not verified: ...").
- Evidence from other tools and attachments the platform cannot carry is replaced by how to
  produce it (section 8); never refer to an attachment the reader cannot open.
- No credentials, tokens, private paths, personal data or pointers to a person's private notes.

## Shape and scope

- One issue, one deliverable that can ship and be verified on its own. Work that is independent,
  or that someone can ship earlier, is split into its own issue and linked both ways; work that is
  only a piece of a larger deliverable stays a checklist inside it.
- An issue that changes or supersedes another says so, and the other one says so too (a short
  comment on it, so its history shows when the decision changed). The body of an issue is the
  current truth; comments are the history. Never leave an old body contradicting a newer decision.
- Cite only issues that still matter: a closed duplicate is not a related issue. Search closed
  issues for earlier decisions on the same subject and link them.
- Reversing something the project documented as intended is a design change, not a defect: it is
  an enhancement and the issue names the document that changes.

## Labels

Every triaged issue has exactly one of each, except closed duplicates (`duplicate` and a link to
the canonical issue are enough):

- **Type**: `bug`, `enhancement`, `maintenance`, `documentation`, `verification`, `owner-action`.
- **Area**: one `area:*` label naming the part of the project (git, ui, settings, hosting, ...).
- **Priority** (open issues): `priority:p0-critical`, `priority:p1-high`, `priority:p2-normal`,
  `priority:p3-low`.
- **Size** (open issues, remaining work): `size:small`, `size:medium`, `size:large`,
  `size:needs-estimate`; say why when no estimate is possible. Size follows what the investigation
  found, and is raised when the inventory turns out bigger than the title suggested.

Extra labels, when they apply: `needs-triage` (new, not yet confirmed; a maintainer removes it after
confirming scope, area, priority and size), `needs-verification` (live, platform or owner checks
remain), `security` (credential, trust, privacy or code-execution risk), `owner-action` (decisions
and external-account tasks only the owner can do).

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
