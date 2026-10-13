# Independent review of filed issues

A reviewer that did not write the issues checks them against the standard and the code, then fixes
what it finds. The writer's own read-back is not this review; it is step 3 of the process.

## When

After filing or substantially rewriting a batch of issues, before anyone builds from them. One
review covers a batch. Also when an issue's facts look stale, or an owner decision changed what
several issues say.

## Who

A separate context with no part in writing the issues: a subagent or reviewer the harness provides,
at a strong tier for the depth this needs. When no separate context is allowed, the writer reviews
against this file and labels the result a self-review, never an independent one. A reviewer
receives the issue numbers, the standards, the owner's decisions as the owner stated them, and
pointers to the code and docs; it does not receive the writer's conclusions about whether the
issues are right.

## Brief

State: the repository and the issue numbers (and related issues touched); that it edits issues,
labels, titles and comments only, never code or documentation, and builds or runs nothing;
which files to read first (the project's instruction files, its contribution guide, this skill's
standards, its ADRs and design docs); the owner decisions to keep, verbatim; what it may do
(edit bodies, titles, labels, link and comment, split into a new issue, close an exact duplicate
as not planned with a link and `duplicate`) and may not (close anything else, change the owner's
decisions); where to put its working files (outside the repository); and the report it returns.

## What the reviewer checks, per issue

1. **Standard** — title, section order, depth bar, voice; labels complete and right (type, area,
   priority, size, `security`, `needs-verification`); priority and size fit the evidence; type
   fits (reversing documented intent is an enhancement).
2. **Facts** — every path, symbol, command, option, overlay or flag, setting name, count and
   quoted string, verified by reading or searching the code. Wrong ones are corrected, drifting
   line numbers become symbol names, unverifiable ones are removed or marked unverified.
3. **Cause and inventories** — a bug's cause matches the code; every "audit X" deliverable that
   can be derived cheaply and verifiably is replaced by the list or table itself; counts are
   recomputed.
4. **Where to see it** — each command and option exists (the script's help and source are read,
   not remembered); what cannot be staged says so and names the other route or the flag to add.
5. **Product rules and records** — the proposal respects the project's rules; missing constraints
   (legal text and versions, ADRs to add or amend, security pass, documentation to update, the
   rules a decision overrides) are added.
6. **Overlap and consistency** — related and duplicate issues found by search (open and closed);
   overlapping scopes are split or merged sensibly; issues that touch the same behaviour agree in
   wording, terms and decisions; supersessions are recorded on both sides; closed duplicates are
   not cited as related.
7. **Decisions** — recorded with dates and kept; open ones are listed with a recommendation;
   anything the issue decided on its own that was the owner's to decide becomes an open decision.
8. **Leaks** — no private paths, secrets, personal notes, references to unavailable attachments,
   or model and tool attribution.

## Working notes

The reviewer keeps its notes outside the repository so a stop loses nothing: the original body of
every issue before any edit, the edited body it pushed, and a checklist that records per issue what
was verified, what was corrected and why, what is still to do and the findings it has derived but
not yet written into an issue. It updates the checklist after each issue, not at the end, so a
later reviewer, or the same one resumed, continues from it.

## How it edits

Edit the issue so the body is the current truth, in the standard's section order. Apply changes
as exact-match replacements that fail loudly when the expected text is missing, so a stale read
never overwrites a newer body. Keep the
owner's decisions and every unresolved requirement; trim only filler. A new issue only for a clean
split. After editing, re-read each issue and confirm body and labels.

## Report

Per issue: `ok`, or the list of changes (title, labels, sections, links) with every factual
correction and what was wrong. Then: issues split, merged or closed; what could not be verified
and where it looked; open owner decisions with the recommendation. The writer relays this report
and does not resend what the reviewer fixed.

## Stopping

A reviewer that stops early reports what is done and what remains. Resume the same reviewer for
the rest rather than starting another that rebuilds the context, unless the owner says otherwise.
A reviewer the owner has stopped, resumed or messaged is theirs: leave it alone and wait for its
report.
