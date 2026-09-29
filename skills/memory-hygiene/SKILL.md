---
name: memory-hygiene
description: Keep an agent's saved memories and session handoff notes true — verify each against the repository, merge duplicates, retire finished handoffs, fix the memory index, and route drifted docs to an audit. Use when a startup check or a user flags stale memories, at a checkpoint after a batch of work, when a handoff's work is finished, or when a memory turns out to be wrong. Not for saving a new memory, not for writing or auditing project documentation (project-docs), and not for instruction files such as AGENTS.md (agent-instructions).
---

# Memory hygiene

A saved memory is read at the start of every session as if it were still true. One that has gone
stale is worse than none: it names a file that moved, a branch that merged, a handoff already
finished, or a rule the owner has since changed, and the next session acts on it with full
confidence. Handoff notes — a file left for the next session, usually with a memory pointing at it
— rot the same way once their work is done. This skill keeps both true. It is maintenance, not
authorship: it verifies, corrects, merges and retires what exists, and saves nothing new beyond
the correction itself.

## What it covers

- **Memories**: the harness's persistent memory store for the project and its index, wherever the
  harness keeps them (its own memory instructions name the location and file format). Follow that
  format exactly; do not restructure a memory beyond what the fix needs.
- **Handoff notes**: files a session left for a later one (often `*handoff*.md` in the docs tree),
  and the memories that point at them.
- **Everything else is routed, not tended here.** Project documentation that may have drifted goes
  to the `project-docs` skill's audit mode; instruction files (`AGENTS.md`, `CLAUDE.md`, rule files)
  go to `agent-instructions`. Note what you find for them in the report.

## Invariants

1. **The owner's word outlives its age.** A preference, rule or decision the owner stated stays
   until the owner changes it or its subject no longer exists. Age alone never retires one. When a
   newer statement from the owner contradicts it, keep the newer and record the change.
2. **Verify against the repository, never against memory.** A path is checked by looking for it, a
   branch or commit with git, a command by reading the script or manifest that defines it, a
   backlog item by reading the backlog. A claim that cannot be checked is left as it is and listed
   as unverified, not deleted on suspicion.
3. **A finished handoff is retired whole.** When every step of a handoff note is done, or has
   moved into the project's tracker, delete the note, the memory that points at it, and the
   memory's index line together. A half-finished one is updated to say what is left.
4. **One fact, one place.** Two memories that say the same thing are merged into the better one and
   every link to the other is repointed. A memory that repeats what the repository already records
   (code structure, git history, a doc) is cut to the non-obvious part, or deleted when none is
   left.
5. **Other sessions' work is not yours.** Memories and handoffs another running session is using,
   and repository files with uncommitted changes you did not make, are reported, never edited. If
   the request includes committing, commit only the paths this pass changed, by name.
6. **Delete only what is proven, and keep a copy.** Memories live outside version control, so a
   deletion cannot be undone from history. Delete or merge away a memory or handoff note only when
   the evidence is conclusive — its file, branch or handoff is gone, it duplicates another word for
   word in substance, or the owner has recorded that it is superseded — and copy each file to a
   dated backup outside the memory directory first. Where the harness's rules ask for confirmation
   before deleting files you did not create, a request to tend memories covers these proven cases;
   anything resting on judgment goes under **Needs you** instead.
7. **Secrets stay where they are.** Never copy a credential or personal detail from a memory into a
   report, a commit or another file.

## Procedure

1. **Inventory.** List every memory file and every index line. Flag index lines whose file is
   missing, files the index does not list, and links (`[[name]]` or the harness's form) that name
   no memory. Find handoff notes in the repository and the memories that point at them.
2. **Check each memory** against invariant 2: paths, branches, commits, commands, backlog items,
   versions, dates written as "today" or "next session", and statuses ("paused", "in progress",
   "on hold"). Note its type — owner preference, project fact, reference — because invariant 1
   applies only to the first.
3. **Decide per memory**: current (leave it), stale but fixable (correct the fact, keep the rest),
   superseded (the owner or the repository replaced it: delete, repoint links), duplicate (merge),
   finished handoff (retire whole), or unverifiable (leave, list).
4. **Apply** the edits in the harness's memory format and keep the index to one line per memory.
   Edit only what the decision named. A relative date ("today", "next week") in a memory you are
   already correcting means the day it was written: resolve it from the memory's own recorded date
   (a `modified` field, or the file's history) or leave it and list it under **Left**; never resolve
   it against today.
5. **Route** what belongs elsewhere: drifted docs to `project-docs` (audit), stale instruction
   files to `agent-instructions`. Run those only if the request covers them.

## Output

- **Changed** — each memory or handoff edited, merged or deleted, with the one-line reason and the
  evidence (the command or file that showed it stale).
- **Left** — memories kept as they are only because they could not be verified, with where you
  looked.
- **Routed** — docs or instruction files that look stale, for their own pass.
- **Needs you** — any memory whose truth depends on the owner's intent rather than the repository.
