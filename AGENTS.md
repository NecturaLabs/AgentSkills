# AgentSkills — Agent Guidelines

## Plugin Versioning
- **Always bump the version** in all config files when making changes — no exceptions
- Follow semver: **patch** (bug fixes, typos), **minor** (new skills, new features), **major** (breaking changes, removed skills, restructured config)
- Bump the version in the same commit as the change, not as a separate commit
- Files requiring version bumps: `.claude-plugin/plugin.json`, `.cursor-plugin/plugin.json`, `package.json`, `gemini-extension.json`

## Comments
- All work on comments, doc comments, docstrings and in-source API documentation goes through `necturalabs:comment-manager` — writing them, auditing them, or cleaning them up. Reading the code and writing what looks right is not a substitute.
- Both review loops enforce the rules. `iterative-code-review` carries `references/comment-checklist.md` and dispatches it to the reviewer as a third checklist path; `iterative-security-audit` carries the comment-borne disclosure category (CWE-615/540/546, OWASP SCP). Comment findings are ordinary blocking findings under the no-deferral rule.
- A language's comment convention comes from its own creators. Never inherit it from the language it resembles — check the derived-language trap table before commenting in a language that resembles one you know.
