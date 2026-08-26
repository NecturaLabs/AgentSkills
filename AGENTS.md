# AgentSkills — Agent Guidelines

## Commands
Run these from Git Bash:
- Full suite: `npm test`
- Skill structure only: `bash tests/validate-skills.sh`

From PowerShell, call Git Bash by full path — `npm test` shells out to `bash`, which PowerShell resolves to the WSL launcher (`C:\WINDOWS\system32\bash.exe`) and fails with `execvpe(/bin/bash)`:
```powershell
& "C:\Program Files\Git\bin\bash.exe" tests/run-all.sh
```

The suite runs entirely offline — every check reads files in this repo. Nothing needs the `claude` CLI, the network, or credentials, and nothing that does may be added.

**Expect roughly 5-7 minutes on Windows/Git Bash**, most of it in the three mutation guards. Each of those runs its validator once per mutation — ~36, ~21 and ~16 times — and a process spawn costs far more than the check itself. That is the price of guards that are proven able to fail; if you need a fast signal while iterating, run the single suite you are changing and the whole set before you push.

## Boundaries
- **Always**: Run the suite as documented under Commands; bump the version per Plugin Versioning
- **Ask first**: Adding or removing a skill, changing `tests/run-all.sh` aggregation, editing the root `CLAUDE.md`
- **Never**: Write anything under `.claude/worktrees/` — sibling branches live there with their own uncommitted state, and the shell's working directory persists between commands
- **Never**: Add a test needing the network, credentials, or the `claude` CLI. No API key belongs in this repo or its CI, so such a test can only ever be skipped, and a permanently skipped test reads as coverage while providing none
- **Distribution-sensitive**: The root `CLAUDE.md` ships to users as their global config (see README). Nothing repo-specific goes in it, and a relative `@import` written there resolves against the user's `~/.claude/`, not this repo. Repo-specific wiring belongs in `.claude/CLAUDE.md`.

## Plugin Versioning
- **Bump once per branch, not once per commit.** Work lands on `beta` first and is promoted to `main` when it is ready, so one branch carries one version across its whole change set. This is what CI enforces: that the four files agree on every push, and that the version advances past the base on a pull request **into `main`**. A feature → `beta` PR is deliberately not gated, so the rule below and the workflow agree. A per-commit rule was written here once and never held; it produced churn, not signal.
- Follow semver: **patch** (bug fixes, typos), **minor** (new skills, new features), **major** (breaking changes, removed skills, restructured config)
- **Only the integration branch bumps.** A feature branch merging into `beta` does not bump its own version; `beta` bumps once after the merge. Two branches bumping at the same time is how the version went 1.6.0 → 1.5.0 → 1.7.0 → 1.6.1 in a single day, and the tip being correct is luck, not a property of the process.
- All four files carry the same version and change together: `.claude-plugin/plugin.json`, `.cursor-plugin/plugin.json`, `package.json`, `gemini-extension.json`

## Comments
- All work on comments, doc comments, docstrings and in-source API documentation goes through `necturalabs:comment-manager` — writing them, auditing them, or cleaning them up. Reading the code and writing what looks right is not a substitute.
- Both review loops enforce the rules. `iterative-code-review` carries `references/comment-checklist.md` and dispatches it to the reviewer as a third checklist path; `iterative-security-audit` carries the comment-borne disclosure category (CWE-615/540/546, OWASP SCP). Comment findings are ordinary blocking findings under the no-deferral rule.
- A language's comment convention comes from its own creators. Never inherit it from the language it resembles — check the derived-language trap table before commenting in a language that resembles one you know.
