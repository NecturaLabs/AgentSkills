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

**Expect fifty seconds to a minute and a half on an idle Windows/Git Bash box**, down from two and a half minutes, and longer when the machine is busy. Measure on an idle box before quoting a number, and quote a range rather than a point.

**The currency is the number of processes the run creates, not the work they do.** Measured on Windows and Git Bash: a fork alone costs about a sixth of a second, an external binary about a fifth, and `bash script` about a third. Reading a whole file through a redirect costs a fiftieth of that, and a string operation nothing at all. Every check in this suite is cheaper than the process that would carry it out.

That cost parallelises far short of the core count. `run-all.sh` starts every suite at once, but MSYS process creation is largely serialised: eight validator runs together measured between 1.3x and 2x faster than in sequence on a sixteen-core box -- about a halving at best, and which validator it is matters as much as what else is running. Running a guard's own cases concurrently measured slower still, since each worker pays for a tree of its own. So the way to make this suite faster is to spawn less, never to spread it wider.

What that means in practice:
- Derive a directory with `cd` and `$PWD`, not `$(cd ... && pwd)`, `dirname` or `basename`.
- Read a file with `IFS= read -r -d ''`, which keeps it byte for byte; drop the `IFS=` and it strips the surrounding whitespace, while `$(<file)` strips trailing newlines — and the guards write back what they read. Mutate it with the shell's own string operations, not `cp`, `sed -i` and `cmp`.
- Leave a result in a variable; a caller writing `x=$(helper ...)` forks for it.
- Where a command's output is captured in a loop, write it to a file and read it back, rather than `$(...)`, which forks before it can exec. A one-off capture does not earn a scratch file, and several here are still `$(...)`.
- Invoke a script by path. Every suite under `tests/` derives its own root from `BASH_SOURCE`, so a `cd` inside a subshell buys nothing and costs a fork. The two files under `hooks/` derive theirs from `$0`, which arrives backslash-separated on Windows: keep an unfolded split in the chain and fold to `/` as a fallback. Folding with no unfolded attempt mangles a Unix directory name that legitimately contains a backslash; not folding at all leaves the hook silently resolving to the caller's directory on every Windows install.
- A pipeline that reads clean and costs one process is fine; one that costs a process per line, per phrase or per file is not.

The slowest are still the guards, because each one runs a real validator once per mutation — ~40, ~24 and ~16 times — and `runner-guard.sh` runs the runner and the manifest guard per case. That is the price of guards proven able to fail. For a faster signal while iterating, run the single suite you are changing, and the whole set before you push.

## Boundaries
- **Always**: Run the suite as documented under Commands; bump the version per Plugin Versioning
- **Ask first**: Adding or removing a skill, changing `tests/run-all.sh` aggregation, editing the root `CLAUDE.md`
- **Never**: Write anything under `.claude/worktrees/` — sibling branches live there with their own uncommitted state, and the shell's working directory persists between commands
- **Never**: Add a test needing the network, credentials, or the `claude` CLI. No API key belongs in this repo or its CI, so such a test can only ever be skipped, and a permanently skipped test reads as coverage while providing none
- **Never**: Let a suite write inside `tests/` or depend on another suite having run. `run-all.sh` starts them all at once, so anything two suites share is a race, and one suite reading what another wrote would pass or fail on timing. A suite that needs to write builds its own sandbox under `mktemp -d`; the ones that only read the repo write nothing at all
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
