# Auditing and shrinking an instruction file

Two related jobs: checking whether an existing file is still healthy, and cutting one down once it
has grown past what it should carry. Both start from the same measurements and the same test —
shrinking is what an audit turns into once it finds the file is oversized or stale enough that
patching individual lines isn't enough.

## Measure first, don't estimate

Before judging a file, measure it: line count, word count, byte size. All three, not just lines — a
file with short lines can still be well over a harness's byte budget, and a file that looks short in
an editor can be wide enough per line to matter. These are one command away in any shell; run it
rather than eyeballing whether the file "feels big."

Compare the byte size against whatever budget the target harness applies to the instruction chain,
if the repository or any of its subtrees carries more than one instruction file feeding the same
discovery walk. Sum the nested chain,
root to the deepest one in scope, before deciding the chain is fine; a root file well under budget
can still push a deep chain over it.

## Staleness detection

Treat any of these as a trigger to re-verify, not just re-read:

- A command, flag or path in the file doesn't match what the manifests, task runner or CI config
  say today.
- The project structure changed enough that a described directory no longer means what the file
  says it means, or a new top-level directory exists that the file's structure section should but
  doesn't cover.
- A section claims something the code now contradicts — a convention that used to hold, a boundary
  that moved.
- The user asks for a refresh, or a task the file should have prevented went wrong anyway.

For every command the file documents, re-run the terminating, read-only form and confirm the output
still matches what's written — build, test, lint, single-test. Apply the same rules as writing one
fresh: never run what doesn't terminate or what rewrites tracked source, prefer a bounded probe
(`--help`, `--dry-run`, list-only) where the documented form is destructive, and drop what fails
unless the failure is only a missing local credential or service, in which case keep it and name the
prerequisite. Never assume a command still works because it's written down — a declared script can
exist in the manifest and still be broken.

A stale entry found during an audit gets fixed in the same pass, not flagged for later — the file
is small enough that "fix the section you're already auditing" costs little, and a wrong command
left in place is actively worse than no command at all.

## Deciding what earns its place

Run every section through the placement test in `SKILL.md`. A section that fails every row of that
test — its absence wouldn't change a frontier agent's decisions on most tasks, it isn't a portable
skill either, it isn't a fact this project's own code or docs already state, and no tool could
enforce it instead — is dead weight regardless of how the file got that way. Delete it rather than
trimming its prose.

Common patterns that inflate a file past what it earns:

- **Restated documentation.** A paragraph that repeats the README's opening, a dependency list
  already in the manifest, an API surface already documented elsewhere. Link to the source instead
  of copying it — the copy goes stale the moment the source changes and the file doesn't.
- **Derivable structure.** A directory listing or module map an agent gets for free from navigating
  the tree. Keep only the entries whose name doesn't predict its contents, whose boundary against a
  similar-looking directory is load-bearing, or that would be wrong to hand-edit.
- **Rules a tool already enforces.** Formatting, import order, anything a linter or type checker
  already fails the build on. Sending a model to do a linter's job spends context to duplicate an
  enforcement that already exists and never drifts.
- **Vague principle statements** — "write clean code," "follow best practices" — that carry no
  verifiable action and get silently ignored precisely because there's nothing to check them
  against.
- **Content specific to one subproject, written at the root.** Move it into a nested file for the
  subtree it actually describes — a nested file exists only where a subtree's conventions genuinely
  differ, never as a place to relocate overflow.

## Shrinking without losing what holds

1. Measure the current size (lines, words, bytes) and record it — the report needs a before and
   after.
2. Walk the file section by section against the placement test. For each section, decide: keeps its
   place, moves to a skill or reference, moves to project docs or code, moves to tooling, or is
   deleted outright.
3. For anything that moves rather than deletes, make the move — write it into the destination named
   by the test, not just remove it and hope someone notices it's missing. A rule that mattered
   enough to keep somewhere still needs a home; deleting it and moving it are different outcomes.
4. Re-measure. The report states both numbers and what moved where, not just the smaller count —
   a shrink that only deletes without preserving what held is a regression dressed as a cleanup.
5. Confirm the file still loads for its intended scope, using the harness's own record of what it
   resolved rather than a model's summary of its instructions, especially after a nested-file split
   changes which file a given subtree actually reads.

Never shrink by weakening a rule that prevents a real safety or correctness failure — vague-ing it
down, hedging it, or cutting the part that made it enforceable. If a section is both large and
load-bearing, the fix is usually to extract detail into a reference or a skill the file then points
to, not to compress the rule until it stops being actionable.
