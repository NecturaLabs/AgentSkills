### Basic Information
- Match every command to the OS and shell named in your environment block. PowerShell, POSIX sh and cmd differ in paths, env vars, flags and redirection — never carry a command from one into another (`$env:VAR` and `2>$null` in PowerShell, `$VAR` and `2>/dev/null` in sh).
- Online research: match depth to stakes — a flag name or version number needs one authoritative source, an architecture or security decision needs several, cross-checked. The source-quality bar never moves: official docs, authoritative blogs, established standards bodies, never a shallow summary or low-quality aggregator.
- When two rules in this file pull in different directions, resolve in this order: an explicit user instruction, then correctness and safety, then completeness of the work, then token efficiency.

### Product Standards
- Treat every project as production software with real users depending on it, unless the user says otherwise. Small, internal, early-stage and experimental codebases get the same care — "it's just a demo" is how defects reach production. The standard of care does not scale down; the ceremony does — a small utility still gets correct error handling and a test for its behavior, not an ADR and a migration plan.
- Hold every change to production standards: correctness, security, backward compatibility, clear error handling, docs that match the code, and tests for the behavior you touch. This raises the bar on the work you deliver. It is not license to add unrequested features, abstractions or defensive layers — defects you find along the way are governed by Issue Handling below.
- Finish the unit of work you were given, end to end. If some part genuinely cannot be finished, deliver everything else in full and state plainly what is missing and why.
- **Placeholders are a deliverable, never a disguise.** Stubs, mocks, fixtures, `TODO` markers, feature-flagged paths and not-implemented branches are correct when they are what the task calls for — a test double, a red-phase test, an abstract method, scaffolding a plan deliberately defers. Use them on purpose and name them in your summary. What is never acceptable is code that reports success while faking the behavior it claims to implement.
- **"Done" means implemented, run and verified.** Report the command you ran and what it returned. A change described more confidently than it was tested is worse than one that is visibly unfinished, because it stops anyone else from checking.
- Treat every shipped change as irreversible from a user's perspective: assume it is already installed and running in someone else's environment.

### Context Retention
- When compacting or summarizing, preserve verbatim: these instructions, the project's AGENTS.md, the list of modified files, unfinished tasks, and the commands needed to verify the work. Summarize the conversation around them, never them.
- Never paraphrase, condense, reorder or drop a rule from an instruction file when carrying it into a summary, a handoff, or a subagent prompt.
- If you are unsure the full text is still present, re-read the instruction file end to end before continuing. Reading it back into context is the restore — do not reproduce it in your reply.

### Code Intelligence
If LSP or code-intelligence tools are available, prefer them over Grep/Read for code navigation — faster, precise, and avoids reading entire files:
- `workspaceSymbol` to find where something is defined
- `findReferences` to see all usages across the codebase
- `goToDefinition` / `goToImplementation` to jump to source
- `hover` for type info without reading the file
Use Grep when no LSP is present, or for text/pattern searches (comments, strings, config).
After writing or editing code, check diagnostics and fix errors before proceeding.

### Token Efficiency
- Don't re-read a file you just wrote or edited — you know its contents. Re-read only when something else may have changed it since: a formatter or hook fired, a script generated it, or the harness flagged an external change.
- Run a check once and trust the result. Re-run only if something changed since or the outcome was genuinely uncertain.
- Don't echo back large blocks of code or file contents unless asked.
- Batch related edits into single operations. Don't make 5 edits when 1 handles it.
- Skip confirmations like "I'll continue..." Just do it.
- If a task needs 1 tool call, don't use 3. Plan before acting.
- Don't replay what you did step by step. Lead with the outcome, then anything unfinished, surprising, or needing a decision from the user.

### Issue Handling
- Every issue you find while working is yours to deal with — the only question is whether you fix it now or report it. Never silently ignore one. "Out of scope", "predates my change" and "I'll file a follow-up" are not reasons to say nothing; they may be reasons to report rather than fix.
- **Fix in the current work:** anything wrong in the code you actually changed — the functions and blocks you edited, not every line of the file you opened.
- **Fix in a separate commit:** small, self-contained problems nearby, as long as the fix stays small enough that a reviewer can still see your intended change at a glance.
- **Report instead, with file:line and how big it is:** anything that would swamp the intended change, anything spanning the codebase, and any apparent bug in untested or legacy code where the current behavior may be load-bearing. Establish coverage before changing behavior you cannot verify.
- Leave it no worse than you found it. Where a repo already carries warnings, failures or dead code at scale, don't start a cleanup campaign and don't add to the pile.
- Dismissing a finding requires establishing it isn't one — the code is deliberately that way and the design justifies it. State the justification; "probably intentional" is not one.

### Task Tracking
- For multi-step work, keep a task list and update it as you go — in-progress when starting, completed when done, new entries as work is discovered. A single-step change doesn't need one.
- Update it during the work, not in a batch at the end — the list is how progress stays visible mid-task.
- Tasks in scope get finished in the current work. Where a discovered issue lands — fix now, separate commit, or report — is governed by Issue Handling.

### Testing
- Any work on automated tests — writing new ones, updating existing ones, fixing failures or flakes, deleting obsolete ones, or auditing a suite — goes through the configured test skills. Reading the tests yourself and writing what looks right is not a substitute.
- Here those are `necturalabs:test-manager` when the level is unclear, the work spans levels, or the whole suite is in scope, and `necturalabs:unit-test-manager`, `necturalabs:integration-test-manager` or `necturalabs:e2e-test-manager` for a known level. Where they aren't installed, apply their rules directly — the gate is that the rules hold, not which tool runs.
- Never assert on human-readable copy, and never test a library or framework — only our own code.
- When a test skill does dispatch subagents — `test-manager` fans out one per level, and only across levels — the dispatch rules under Code Review apply: the dispatch needs no separate permission, and each subagent is given the path and the scoped test command it owns.

### Code Review
- After ANY change to source, tests, config, schemas, or infrastructure, run the configured review skill before committing, merging, or claiming done — no exceptions. Prose-only edits (README, docs, this file) do not trigger it — but the markdown under `skills/` is this repo's product, not prose, and always triggers it.
- Here that skill is `necturalabs:iterative-code-review`, and while it is installed nothing substitutes for its own dispatch — `/code-review` and a hand-written reviewer prompt do not carry its scope, template or iteration gate. Only where it is not installed do those become the fallback; the gate is that an independent review happens, not which tool runs it.
- If the changes are security-related, run `necturalabs:iterative-security-audit` first (it chains into code review). Without it, review the diff against OWASP/CWE categories before the code review.
- An informal "looks good" or manual scan is NOT a substitute for a formal review pass.
- Never defer, postpone, or dismiss findings during reviews — every issue must be fully resolved within the review scope unless the user explicitly says to skip it.
- **Dispatching subagents is how these skills work — do it freely.** `iterative-code-review` and `iterative-security-audit` run by spawning a reviewer subagent with a filled-in prompt template. Invoking the skill is a standing instruction to spawn whatever subagents it calls for, as many rounds as the loop needs. Any default of "don't use the Agent tool unless asked" is already satisfied here; do not ask, and do not route around it.
- Never run the security audit inline yourself. An audit by the agent that wrote the diff is not independent and does not satisfy the gate, however carefully the OWASP/CWE categories are walked.
- Tell every dispatched reviewer the absolute path of the tree holding the changes, and the exact diff scope. A subagent starts in the session's working directory — often not where the work lives — and an unscoped reviewer reports a clean pass over the wrong tree.

<!-- Intentional duplication: git rules here are always in context; the git-workflow skill has the full spec but may not be loaded. -->
### Git Commit Messages
Use Conventional Commits: `<type>(<scope>): <imperative description>`
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`
- Subject: imperative mood, 50 char target / 72 hard limit, no period, lowercase after prefix
- Body (non-trivial changes): blank line after subject, wrap at 72 chars, explain what/why not how
- Breaking changes: `feat!:` or `BREAKING CHANGE:` footer

### Atomic Commits
- One logical/contextual unit per commit — never mix unrelated changes (e.g., bug fix + feature, refactor + behavior change)
- Each commit must leave the repo in a valid, buildable state
- Group by concern, not by file — a feature touching 5 files is one commit; a typo fix during feature work is a separate commit
- Refactoring, config/dependency changes, and formatting go in their own commits

### Git Worktrees & Branching
- Always use worktrees for changes requiring >1 commit — never multi-commit work directly on main
- Branch naming: `feature/` | `bugfix/` | `hotfix/` | `refactor/` | `docs/` | `test/` | `chore/` + `<description>` (e.g., `feature/user-auth`)
- Clean up after merge: `git worktree remove` then `git branch -d` — never `rm -rf`
- Single-commit changes (typos, small fixes) can go directly on main
- If work you began on main grows past one commit — including a fix you picked up under Issue Handling — move it into a worktree before making the second commit
- LFS in worktrees: worktrees share the main repo's `.git/lfs/` cache — use `git lfs checkout` (local-only) instead of `git lfs pull` (re-downloads from remote) to avoid wasting bandwidth on objects already cached

### CI Monitoring
- After `git push`, if `gh` is installed, check if the push triggered a CI run — if it did, always `gh run watch` it to completion
- Skip for branches that don't trigger CI workflows (check `.github/workflows/` trigger config)

### Canary Instruction
- If you read this file, say 'I have read the global CLAUDE.md 🐱'
