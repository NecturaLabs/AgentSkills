---
name: backlog-maintenance
description: Create and maintain a project's backlog as GitHub issues — search before filing, write issues to a fixed standard, keep labels, priority and size consistent, record progress and close only on verified acceptance criteria — and convert any Markdown or text backlog (TODO.md, BACKLOG.md, roadmap and handoff lists) into filed issues. Use when work needs filing, an issue needs writing, grooming or triage, a task finishes and its issue needs updating, or a repository still keeps its backlog in a file. Not for planning how to split or delegate work (agent-orchestration), not for durable design or decision docs (project-docs), and not for saved-memory or handoff-note cleanup (memory-hygiene).
---

# Backlog maintenance

GitHub issues are the one backlog. A backlog kept in a Markdown file rots, forks into copies and
cannot be searched, labelled or linked to the change that fixed it, so it is converted and then
retired, never kept beside the issues.

## Invariants

1. **One backlog.** Issues are the only task list. Never add a task to a Markdown backlog or keep
   a mirror of the issues in a file. A project's own instruction files win where they define
   labels, forms or priority rules; this skill supplies the defaults where they do not.
2. **Search first.** Before filing, search open and closed issues for the same problem. Update the
   existing issue instead of filing a duplicate; link related ones.
3. **Evidence, not invention.** Never write a test result, reproduction or acceptance claim that
   was not observed. A criterion not yet run is left unchecked and named as unrun.
4. **Preserve what is unresolved.** Conversion and edits keep every open requirement, constraint
   and piece of evidence from the source; trim only filler, praise, repetition and canned summaries.
5. **Close on proof.** Close an issue only when each acceptance criterion is verified and the
   result is recorded on it; record partial progress and the remaining subparts on an issue that
   stays open. A compound issue with parts left stays open.
6. **Stay inside the task.** A problem found while doing other work becomes its own issue (after
   searching), not a fix in the current change.
7. **No secrets.** Issues are readable by others: no credentials, tokens, private paths or personal
   data, and no unredacted logs.
8. **The remote decides.** Work through the repository's own GitHub remote with the platform CLI.
   A repository with no GitHub remote keeps its backlog nowhere else: say so, and file nothing.

## Modes

Pick the one that fits; a request can span several.

- **File** — new work or a newly found problem. Search, then write the issue to
  `references/issue-standards.md` and apply its labels.
- **Maintain** — after work on an issue: link the change, record progress, tests run and
  follow-ups, correct labels, and close or leave open per invariant 5. Grooming: re-check
  priority and size, merge duplicates (close with a link to the canonical issue), split issues
  that bundle independent work.
- **Convert** — a backlog kept in a file. Follow `references/md-conversion.md`.
- **Next item** — read the open issues before starting work; take them by priority, then by
  issue number within a priority, honouring any project rule that orders them differently.

## Process

1. Read the project's instruction files and `CONTRIBUTING.md` for its label catalogue, forms and
   priority rules, and list the live labels with the platform CLI. Use them as they are; only
   when the repository has none, create the minimal catalogue in `references/issue-standards.md`.
2. Do the mode's work. Prefer the platform CLI for every read and write.
3. Verify the result by reading the issue back: title, body, labels and links as filed.
4. Report counts and links: issues filed, updated and closed, duplicates found, anything left
   unconverted and why.

## Output

Lead with the outcome in a sentence, then the issue numbers with one-line titles. Name what was
not done or could not be verified.
