# Migration: v1 to v2

Superseded for current installs by `docs/migration-v2-to-v3.md`; the skill names below are the v2
names as they were at the time.

v2 is a rebuild, not a refactor. The working tree was treated as greenfield; git history is the
archive, so there is no `legacy/` directory and no compatibility layer for a version nobody is
running.

If you used v1, the short version: the plugin no longer requires the superpowers plugin, no longer
injects anything at session start, and thirteen skills became five.

## What changed and why

**Thirteen skills became five.** v1 split work by artifact (`unit-test-manager`,
`integration-test-manager`, `e2e-test-manager`, `test-manager`) and by iteration style
(`iterative-code-review`, `iterative-security-audit`). Both splits cost metadata in every session
while routing between them was ambiguous. v2 splits by *job*, and pushes the artifact distinction
down into references that load only when the job needs them.

**No session-start injection.** v1 shipped a `SessionStart` hook that read
`using-necturalabs/SKILL.md` and injected its full text into every session, and ran a `git ls-remote`
against the network each time to check for updates. Skill discovery is native in both supported
harnesses, so the hook bought nothing and cost context and a network round trip per session. The
entire `hooks/` directory is gone.

**One instruction system.** v1 carried `AGENTS.md`, a root `CLAUDE.md` that shipped to users as
their global config, a `.claude/CLAUDE.md` bridge, and a `GEMINI.md` — four files whose job was to
say how the agent should behave. v2 has `AGENTS.md` and nothing else. `scripts/validate.sh` fails the
build if a competing instruction file reappears.

**No iteration architecture.** v1's review and audit skills looped until a pass came back clean.
That is unbounded by construction, rewards a reviewer that stops finding things, and escalates
severity when a finding reappears. v2 runs one broad independent review, verifies disputed findings,
fixes confirmed ones, and re-verifies only the affected surface.

**Two harnesses, not five.** v1 shipped packaging for Claude Code, Cursor, Gemini and OpenCode, plus
per-harness tool-name mapping tables inside the skills. The tables went stale and the extra manifests
multiplied the version-sync surface. v2 targets Claude Code and Codex, and fixes the problem at the
root: skill bodies name capabilities rather than one product's tool names, so no mapping is needed.
The skills follow the open Agent Skills specification and work in any conforming harness.

## Disposition

| v1 component | Lines | Disposition | Destination |
|---|---|---|---|
| `using-necturalabs` | 133 | remove | — skill discovery is native; bootstrap ceremony deleted |
| `agent-context-loader` | 81 | remove | — harnesses load instruction files natively |
| `iterative-code-review` | 225 | rewrite | `change-review` |
| `iterative-code-review/references/review-checklist.md` | 216 | salvage reference | `change-review/references/` |
| `iterative-code-review/references/naming-and-layout.md` | 359 | salvage selectively | `change-review/references/` — traps kept, bulk restatement dropped |
| `iterative-code-review/references/comment-checklist.md` | 205 | salvage reference | `change-review/references/comment-checklist.md` |
| `iterative-code-review/references/testing-rules.md` | 129 | salvage concept | split: reviewer's view to `change-review`, authoring to `testing` |
| `iterative-security-audit` | 207 | rewrite | `security-review` |
| `iterative-security-audit/references/security-checklist.md` | 250 | salvage reference | `security-review/references/`, reorganized by threat surface |
| `test-manager` (+ 2 references) | 382 | consolidate | `testing` |
| `unit-test-manager` (+ 2 references) | 591 | consolidate | `testing/references/unit.md` |
| `integration-test-manager` (+ 1 reference) | 349 | consolidate | `testing/references/integration.md` |
| `e2e-test-manager` (+ 1 reference) | 325 | consolidate | `testing/references/e2e.md` |
| `agents-md-manager` | 302 | rewrite | `agent-instructions` |
| `docs-manager` (+ 2 templates) | 414 | rewrite | `project-docs` |
| `comment-manager` (+ 3 references) | 1121 | salvage selectively | `change-review/references/comment-checklist.md` — the derived-language trap material; the rest dropped |
| `git-workflow` | 249 | remove | current models handle Conventional Commits; essential safety stays an `AGENTS.md` invariant |
| `update-plugins` | 51 | remove | a personal utility, not core engineering capability |
| `hooks/` (3 files) | — | remove | session-start injection and per-session network check |
| `CLAUDE.md`, `.claude/CLAUDE.md`, `GEMINI.md` | 136 | remove | competing instruction layers |
| `gemini-extension.json`, `.cursor-plugin/`, `.opencode/`, `.codex/` | — | remove | unsupported harness packaging |
| `CONCEPTS.md` | 101 | remove | a general explainer, not truth about this project; the relevant part is now `docs/architecture.md` |
| `docs/superpowers/` | 4 files | remove | v1 planning artifacts; git history holds them |
| `tests/*` (12 scripts) | — | rewrite | `scripts/validate.sh` + `tests/` — the *idea* that a validator needs a guard proving it can fail is kept |
| `.github/workflows/ci.yml` | — | rewrite | simplified to one branch and two manifests |

## What was deliberately not carried forward

Beyond the components above, these v1 *mechanisms* were rejected on principle:

- review-until-clean and fixed multi-round loops;
- 1–100 numeric quality scores;
- raising a finding's severity because it reappeared;
- a broad re-review after every fix;
- the superpowers plugin dependency;
- mandatory repository-wide exploration before starting;
- per-harness tool-name mapping tables;
- stylistic nit-hunting the formatter and linter already own;
- deliberate semantic mutation of every ordinary new test (the principle that a new test must be
  observed failing for the reason it claims is kept; the ritual is not);
- hard-coded annual OWASP/CWE ranking tables, which go stale on a schedule.

Each was cheap to write and expensive to run, and each was compensating for a weaker model than the
ones this repository now targets. The test applied throughout was: *if this rule disappeared, would
current agents get it wrong often enough to justify paying for it repeatedly?*

## Upgrading

v1 installed as a plugin from a marketplace. v2 additionally supports linking the checkout directly,
which is the recommended setup because it keeps one editable canonical source for both harnesses:

```bash
git clone https://github.com/NecturaLabs/AgentSkills.git
cd AgentSkills
bash scripts/install.sh --dry-run   # preview
bash scripts/install.sh
bash scripts/doctor.sh
```

`scripts/uninstall.sh --include-legacy` removes v1 skill links left behind by an older install. It
removes only symlinks whose target resolves inside an AgentSkills checkout, and never a real
directory — anything it declines to remove is reported with the reason.

If you previously relied on the session-start hook to load `using-necturalabs`, nothing replaces it:
the skills are discovered natively and route from their descriptions.
