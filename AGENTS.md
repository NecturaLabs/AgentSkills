# AgentSkills — Agent Guidelines

## Plugin Versioning
- **Always bump the version in `.claude-plugin/plugin.json`** when making changes — no exceptions
- Follow semver: **patch** (bug fixes, typos), **minor** (new skills, new features), **major** (breaking changes, removed skills, restructured config)
- Bump the version in the same commit as the change, not as a separate commit
- Also update `.cursor-plugin/plugin.json` to keep versions in sync
