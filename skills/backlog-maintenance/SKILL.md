---
name: backlog-maintenance
description: Create and maintain a project's backlog as GitHub issues — investigate the code first, write each issue to an exhaustive standard (root cause, file and symbol references, inventories, decisions, how to see it, checkable criteria), keep labels, priority and size consistent, independently review every filed batch, record progress and close only on verified acceptance criteria — and convert any Markdown or text backlog (TODO.md, BACKLOG.md, roadmap and handoff lists) into filed issues. Use when work needs filing, an issue needs writing, reviewing, grooming or triage, a task finishes and its issue needs updating, or a repository still keeps its backlog in a file. Not for planning how to split or delegate work (agent-orchestration), not for durable design or decision docs (project-docs), and not for saved-memory or handoff-note cleanup (memory-hygiene).
---

# Backlog maintenance

GitHub issues are the one backlog. A backlog kept in a Markdown file rots, forks into copies and
cannot be searched, labelled or linked to the change that fixed it, so it is converted and then
retired, never kept beside the issues.

An issue is the whole brief for whoever builds it, often a different agent with no memory of the
conversation that produced it. It is written to that reader: everything known is written down,
checked against the code, and nothing has to be asked again. A one-paragraph issue that restates
the request is unfinished work, not a backlog item.

## Invariants

1. **One backlog.** Issues are the only task list. Never add a task to a Markdown backlog or keep
   a mirror of the issues in a file. A project's own instruction files win where they define
   labels, forms or priority rules; this skill supplies the defaults where they do not.
2. **Search first.** Before filing, search open and closed issues for the same problem. Update the
   existing issue instead of filing a duplicate; link related ones, in both directions where one
   issue changes or supersedes another.
3. **Investigate before writing.** Read the code, docs and decisions the request touches, and write
   what was found, not only what was asked: the cause of a bug, the files and symbols involved,
   the current behaviour, the rules and records the change must respect. Facts stay separate from
   hypotheses, and an unverified claim is labelled unverified.
4. **Evidence, not invention.** Never write a test result, reproduction or acceptance claim that
   was not observed. A criterion not yet run is left unchecked and named as unrun. Every claim in
   an issue — path, symbol, behaviour, count, quoted string, command, issue reference — is
   verified, corrected, removed or marked "Not verified" by the table in
   `references/issue-standards.md`, whoever wrote it; the requester's wording and the filer's
   text are claims, not evidence. Name symbols and files rather than line numbers, which drift.
5. **Write everything down.** The depth bar in `references/issue-standards.md` applies to every
   issue: problem, causes, inventories, constraints, owner decisions, where to see it, acceptance
   criteria. Detail that took research to find belongs in the issue, not in the conversation.
6. **Preserve what is unresolved.** Conversion and edits keep every open requirement, constraint,
   decision and piece of evidence from the source; trim only filler, praise, repetition and canned
   summaries.
7. **Decisions are recorded.** A decision the owner makes is written into the issue with its date,
   in a Decisions section, and kept through every later rewrite. A decision still open is listed
   there too, with the recommendation and the alternatives, so it can be answered in one line.
8. **Close on proof.** Close an issue only when each acceptance criterion is verified and the
   result is recorded on it; record partial progress and the remaining subparts on an issue that
   stays open. A compound issue with parts left stays open.
9. **Stay inside the task.** A problem found while doing other work becomes its own issue (after
   searching), not a fix in the current change.
10. **No secrets, no private references.** Issues are readable by others: no credentials, tokens,
    private paths, personal data, unredacted logs, or pointers to a person's private notes or
    saved memories.
11. **The remote decides.** Work through the repository's own GitHub remote with the platform CLI.
    A repository with no GitHub remote keeps its backlog nowhere else: say so, and file nothing.
12. **Filed issues are reviewed independently.** After filing or substantially rewriting issues
    (several in one task share one review), a reviewer that did not write them checks every claim
    against the code and fixes the issues (`references/review-pass.md`). The writer never presents
    its own check as the review. Progress notes, label corrections and closing need the read-back
    only.

## Modes

Pick the one that fits; a request can span several.

- **File** — new work or a newly found problem. Search, investigate, then write the issue to
  `references/issue-standards.md` (all of it, including the depth bar) and apply its labels.
  Before filing, check every claim in the draft against its "What counts as verified" table and
  settle each one; a draft that still says "verify" or "about N" where a search would answer is
  not ready.
- **Review** — filed issues, before anyone builds from them: the procedure in
  `references/review-pass.md`, applying `references/issue-standards.md` as the standard and its
  table as the definition of verified. Mandatory after filing (invariant 12); also run it on an
  issue whose facts look stale.
- **Maintain** — after work on an issue: link the change, record progress, tests run and
  follow-ups, correct labels, and close or leave open per invariant 8. Grooming: re-check
  priority and size, merge duplicates (close with a link to the canonical issue), split issues
  that bundle independent work.
- **Convert** — a backlog kept in a file. Follow `references/md-conversion.md`; each converted
  issue still meets the full standard.
- **Next item** — read the open issues before starting work; take them by priority, then by
  issue number within a priority, honouring any project rule that orders them differently.

## Process

1. Read the project's instruction files and `CONTRIBUTING.md` for its label catalogue, forms,
   priority rules and product rules, and list the live labels with the platform CLI. Use them as
   they are; only when the repository has none, create the minimal catalogue in
   `references/issue-standards.md`.
2. Do the mode's work, investigating the code as invariant 3 says. Prefer the platform CLI for
   every read and write.
3. Verify the result by reading the issue back: title, body, labels and links as filed, compared
   with the text you meant to file.
4. For filed or rewritten issues, run the review pass (invariant 12) and apply its outcome.
5. Report counts and links: issues filed, updated, split and closed, duplicates found, anything
   left unconverted, unverified or awaiting an owner decision, and why.

## Output

Lead with the outcome in a sentence, then the issue numbers with one-line titles. Name what was
not done or could not be verified, and every open decision with its recommendation.
