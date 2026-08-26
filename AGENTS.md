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
