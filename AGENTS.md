# AgentSkills — Agent Guidelines

## Plugin Versioning
- **Always bump the version** in all config files when making changes — no exceptions
- Follow semver: **patch** (bug fixes, typos), **minor** (new skills, new features), **major** (breaking changes, removed skills, restructured config)
- Bump the version in the same commit as the change, not as a separate commit
- Files requiring version bumps: `.claude-plugin/plugin.json`, `.cursor-plugin/plugin.json`, `package.json`, `gemini-extension.json`
