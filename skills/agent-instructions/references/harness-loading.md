# Harness loading facts

Where an instruction file lives decides whether it loads at all, and how much of it survives
decides whether the back half of a long file is ever seen. Both failures are silent — no error, no
warning, just guidance that was never read. This reference states what is empirically verified on
this machine (Claude Code 2.1.278, Codex 0.155.1) separately from what is inferred, so a claim here
can be traced back to which kind of evidence backs it. Verify against the harness's own docs and,
where possible, its own diagnostic output before relying on a fact here for a version this wasn't
checked against.

## Claude Code (2.1.278) — verified

- Discovers `AGENTS.md` and `.claude/AGENTS.md` by walking **ancestors of the working directory** —
  project-root discovery, not a fixed location.
- By default it reads those files only when **no** `CLAUDE.md`, `.claude/CLAUDE.md` or
  `CLAUDE.local.md` exists at or above the working directory. Any of those three present switches
  the repository back to `CLAUDE.md`-only loading.
- The behavior is governed by the settings key `instructionFiles` (nested under
  `pluginConfigs["agents-md@builtin"].options` in the settings schema), with values:
  - `claude-md` — `CLAUDE.md` only, `AGENTS.md` never read
  - `claude-md-or-agents-md` — the default described above
  - `claude-md-and-agents-md` — both, always
  - `managed-only` — only an organization-managed file
- **Consequence:** a user-scope file at `~/.claude/AGENTS.md` is **not** reached by an ancestors walk
  from a project rooted elsewhere on disk — the walk starts at the working directory and climbs, it
  does not also check the home directory. Nothing loads it natively. A `~/.claude/CLAUDE.md`
  containing `@AGENTS.md` is what actually loads it, because `CLAUDE.md`'s own import mechanism —
  not the `AGENTS.md` discovery path — pulls the file in.
- Support for native `AGENTS.md` reading is additionally gated by a remote feature flag whose
  code-level default is off. It can be unavailable on another account even at the same client
  version, independent of the `instructionFiles` setting.

## Codex (0.155.1)

- **Verified:** reads `$CODEX_HOME/AGENTS.md` (default `~/.codex/AGENTS.md`) through one code path,
  and separately discovers project-level `AGENTS.override.md`, then `AGENTS.md`, then any
  configured fallback filenames, walking **up** from the working directory to the project root.
- **Verified:** `project_doc_max_bytes` (default **32768**, i.e. 32 KiB) is a single cumulative
  budget consumed across every **project-level** document found in that upward walk. Once the
  running total would exceed the budget, the document that would cross it is truncated — silently,
  with no error surfaced to the user. Because the walk concatenates root-first, what gets cut is
  whichever file is deepest, meaning the most specific file, the one closest to the work actually
  being done.
- **Verified:** the global `$CODEX_HOME/AGENTS.md` is read through its own code path and does *not*
  draw on `project_doc_max_bytes`. Its size therefore cannot starve a project of its own
  instructions. Re-check this against the installed version before relying on it, since it is a
  property of the implementation rather than of a documented contract.

## The practical rule

The budget binds the project chain, not the global file. Size each accordingly: a global file is
constrained by the attention it costs on every task, a project chain by a cap that truncates it. A
file that is silently truncated is indistinguishable, from the agent's behavior, from one whose
rules it chose to ignore — which is why the project chain is where size discipline actually
matters.

The same reasoning applies one level down: in a monorepo, a chain of nested `AGENTS.md` files
concatenated root-to-leaf can hit the same cap. Keep every file in a nested chain short, not only
the root, and measure the chain's cumulative size — root through the deepest file in scope —
before assuming a deep chain of them costs nothing.

## Confirming what actually loaded

Do not ask a model to summarize its own instructions and treat that as verification — a model can
omit a truncated or unloaded file from its summary without saying so. Prefer the harness's own
record of what it resolved:

- **Claude Code** lists the memory files it loaded for the current session, and where each one came
  from, in its own context/status output.
- **Codex** can log its resolved instruction chain to a file when started with logging directed at
  a local path, and that log is the authoritative record of what was actually concatenated and
  whether anything was truncated.

Where neither is available, a prompted check ("summarize your current instructions") is a weaker
fallback — it reflects the model's account, not the loader's, and a silently dropped file will not
necessarily show up as a gap in the summary. Never disable approval prompts or sandboxing just to
run a diagnostic read.

After creating or editing an instruction file — root or nested — confirm it loads before reporting
the work done. A chain that silently exceeded a byte cap looks identical, from the outside, to one
that loaded cleanly, and that is exactly the failure a model's own summary is least able to catch.
