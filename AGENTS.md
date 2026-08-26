# AgentSkills — Agent Guidelines

## Commands
Run these from Git Bash:
- Full suite: `SKIP_LIVE_TESTS=1 npm test`
- Skill structure only: `bash tests/validate-skills.sh`

From PowerShell, call Git Bash by full path — `npm test` shells out to `bash`, which PowerShell resolves to the WSL launcher (`C:\WINDOWS\system32\bash.exe`) and fails with `execvpe(/bin/bash)`:
```powershell
$env:SKIP_LIVE_TESTS=1; & "C:\Program Files\Git\bin\bash.exe" tests/run-all.sh
```

**Always set `SKIP_LIVE_TESTS=1`.** Without it, `tests/skill-triggering` shells out to 13 live `claude -p` sessions — it needs the CLI, network, credentials and the plugin installed, it costs real tokens, and those sessions can write to this repo. CI sets the variable; local runs should too.

## Boundaries
- **Always**: Run the suite as documented under Commands; bump the version per Plugin Versioning
- **Ask first**: Adding or removing a skill, changing `tests/run-all.sh` aggregation, editing the root `CLAUDE.md`
- **Never**: Write anything under `.claude/worktrees/` — sibling branches live there with their own uncommitted state, and the shell's working directory persists between commands
- **Distribution-sensitive**: The root `CLAUDE.md` ships to users as their global config (see README). Nothing repo-specific goes in it, and a relative `@import` written there resolves against the user's `~/.claude/`, not this repo. Repo-specific wiring belongs in `.claude/CLAUDE.md`.

## Plugin Versioning
- **Always bump the version** in all config files when making changes — no exceptions
- Follow semver: **patch** (bug fixes, typos), **minor** (new skills, new features), **major** (breaking changes, removed skills, restructured config)
- Bump the version in the same commit as the change, not as a separate commit
- Files requiring version bumps: `.claude-plugin/plugin.json`, `.cursor-plugin/plugin.json`, `package.json`, `gemini-extension.json`

## Comments
- All work on comments, doc comments, docstrings and in-source API documentation goes through `necturalabs:comment-manager` — writing them, auditing them, or cleaning them up. Reading the code and writing what looks right is not a substitute.
- Both review loops enforce the rules. `iterative-code-review` carries `references/comment-checklist.md` and dispatches it to the reviewer as a third checklist path; `iterative-security-audit` carries the comment-borne disclosure category (CWE-615/540/546, OWASP SCP). Comment findings are ordinary blocking findings under the no-deferral rule.
- A language's comment convention comes from its own creators. Never inherit it from the language it resembles — check the derived-language trap table before commenting in a language that resembles one you know.
