---
name: agent-instructions
description: Create, audit, shrink or restructure an AGENTS.md instruction file. Use when writing a repository's AGENTS.md, auditing one for stale or oversized guidance, deciding what belongs in persistent instructions versus a skill, a document or a lint rule, or migrating instruction files between agent harnesses. Not for editing ordinary project documentation.
---

# Agent instructions

An instruction file is configuration the agent obeys with full confidence, not documentation a
human skims. A stale command in it is followed to the letter; an oversized one dilutes every rule
in it on every task. This skill covers the whole lifecycle: writing one, checking one's health,
cutting one down, and deciding where a given rule actually belongs.

## Task classification

| Signal | Mode | Reference |
|---|---|---|
| The repository has no instruction file, or what exists is a stub that doesn't cover the sections below | **Create** | `references/patterns.md` |
| A file exists and needs a health check — stale commands or paths, drift from the repo, missing coverage, unclear whether it earns its cost | **Audit** | `references/audit.md` |
| A file has grown into an encyclopedia and needs cutting down without losing what actually holds | **Shrink** | `references/audit.md` |
| A specific rule needs a home, independent of touching the file itself | **Place** | the test below |

Not for editing ordinary project documentation — a README, an ARCHITECTURE.md, an ADR — unless the
question in front of you is specifically whether content belongs there instead of in the
instruction file.

## The placement test

Ask in this order and stop at the first yes:

| Question | Destination |
|---|---|
| Would its absence make a current frontier agent decide materially worse on *most* tasks? | The instruction file |
| Is it a recurring procedure with a sharp trigger, needed on a minority of tasks? | A skill |
| Is it detail only one mode of that skill needs? | That skill's references |
| Is it a fact about *this* project rather than a portable practice? | The project's code, config, an architecture doc, an ADR, a runbook |
| Can a script, linter, type checker, test or CI job decide it? | Tooling |
| None of the above | Nothing — leave it out |

The decisive framing: *if this rule disappeared, would current agents get it wrong often enough to
justify paying for it repeatedly?* If no, delete it. If the answer is "only in one narrow
situation," that is a skill or a reference, not a persistent rule.

Do not weaken a rule that prevents a real safety or correctness failure merely because it costs
tokens. The two failure modes are not symmetric — an agent that skips a rule because it was cut for
brevity fails the same way whether the rule was five words or fifty.

## Invariants

These hold across all four modes.

1. **Verify commands before documenting them.** Run the terminating, read-only form — build, test,
   lint, single-test — and record what it actually printed. Never run what doesn't exit, can't be
   undone, or rewrites tracked source (dev servers, migrations, deploys, `--fix` linters); use a
   bounded probe (`--help`, `--dry-run`, a list-only mode) instead, or mark the entry inferred and
   say so. Drop a command that fails unless it failed only for a missing local credential or
   service — then keep it and name the prerequisite inline.
2. **A stale command or path is a defect, not cosmetic.** The file is obeyed with full confidence,
   so wrong is worse than missing. Fix it in the same change that touches the section, or report it
   with file and line if fixing it is out of scope for the current task.
3. **Distinguish portable practice from a fact about this project.** A rule that would still be
   true in a different project belongs in a skill, not copied into this file. A rule that would
   stop being true under a different agent is specific to this repo and belongs here. Where a rule
   fails both tests — true only of this repo *and* only for one agent or harness — it belongs in
   that harness's own narrower file (`references/harness-loading.md` covers where each harness
   looks), never duplicated into the shared root file.
4. **The root file must be true for its entire scope.** Nothing in it may hold for one subproject
   and not another; move what doesn't generalize into a nested file for the subtree it actually
   describes.
5. **Nested files exist only for a genuine scope difference, never as pagination.** A nested file
   must be self-contained for its subtree, must never contradict the root, and the root holds only
   what is true everywhere. Splitting a file because it got long, rather than because two subtrees
   genuinely differ, produces files that don't stand alone and a root that stops being universally
   true.
6. **Never duplicate the README, the code, or another instruction file.** Restating something
   readable elsewhere costs tokens on every task and goes stale the moment the source changes
   without the copy following. Link or point instead.
7. **Measure the file's real cost — don't guess it.** Line count, word count and byte size are one
   command away; use them, especially against the harness budgets in
   `references/harness-loading.md`, rather than eyeballing whether a file "feels big."

## Harness loading

Where an instruction file is discovered and how much of it survives varies by harness, and both
failure modes are silent: a file in the wrong location never loads, and a file past a harness's
byte budget gets truncated with no error the user sees. `references/harness-loading.md` has the
verified facts for the two harnesses this repository targets, marked clearly where something is
confirmed versus inferred — read it before creating an adapter, sizing a global file, or explaining
why a rule isn't being followed. The one fact to carry into every mode without opening the
reference: keep a file that is read at the global or user scope especially small, because
project-level files can share a budget that truncates silently, and silent truncation is
indistinguishable from a rule the agent chose to ignore.

## Output contract

Whichever mode ran, report:

- What changed, section by section, and why — citing the placement test or the audit finding that
  drove it, not just "cleaned up."
- Every command verified versus every command inferred, called out separately. Never present an
  inferred command as verified.
- Before and after size (lines, words, bytes) for create, audit and shrink modes.
- For **place** mode: the destination the rule landed in and the one-line reason, quoting which row
  of the test matched.
- Any file this change makes an adapter necessary for, and whether that adapter was created — see
  `references/harness-loading.md`.
- Anything left unresolved and why: a command that couldn't be verified in this environment, a
  section whose placement is genuinely ambiguous, a nested file whose scope boundary needs the
  user's call.

## References

- `references/harness-loading.md` — where each targeted harness discovers an instruction file, what
  gates or truncates it, and how to confirm what actually loaded.
- `references/audit.md` — what to measure, how to detect staleness, and how to shrink a file that
  has grown past what it should carry.
- `references/patterns.md` — what a good instruction file contains, section by section, the
  anti-patterns that inflate one, and how to write a nested file that survives on its own.
