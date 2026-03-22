### Basic Information
- We are on Windows, not Linux, use the correct OS terminal commands
- Online research must be extensive and thorough — use only top reputable sources (official docs, authoritative blogs, established standards bodies), never shallow summaries or low-quality aggregators

### Code Intelligence
Prefer LSP over Grep/Read for code navigation — it's faster, precise, and avoids reading entire files:
- `workspaceSymbol` to find where something is defined
- `findReferences` to see all usages across the codebase
- `goToDefinition` / `goToImplementation` to jump to source
- `hover` for type info without reading the file
Use Grep only when LSP isn't available or for text/pattern searches (comments, strings, config).
After writing or editing code, check LSP diagnostics and fix errors before proceeding.

### Token Efficiency
- Never re-read files you just wrote or edited. You know the contents.
- Never re-run commands to "verify" unless the outcome was uncertain.
- Don't echo back large blocks of code or file contents unless asked.
- Batch related edits into single operations. Don't make 5 edits when 1 handles it.
- Skip confirmations like "I'll continue..." Just do it.
- If a task needs 1 tool call, don't use 3. Plan before acting.
- Do not summarize what you just did unless the result is ambiguous or you need additional input.

### Issue Handling
- If you discover bugs, dead code, messy code, code smells, type errors, lint warnings, deprecation warnings, or broken tests during implementation, builds, or tests, fix them as part of the current work. Do not dismiss them as "existing issues" or defer them for later. If you touched it or it affects what you're building, own it and resolve it properly — clean it up, refactor it, or remove it.
- This takes priority over token efficiency — fixing discovered issues is never "extra work" to be batched away or skipped.

### Task Tracking
- Always keep TODOs updated during changes — mark tasks in-progress when starting, completed when done, and create new tasks as work is discovered. Never let the task list go stale.

### Code Review
- After ANY code changes, invoke `necturalabs:iterative-code-review` before committing, merging, or claiming done — no exceptions
- If changes are security-related, invoke `necturalabs:iterative-security-audit` first (it chains into code review)
- An informal "looks good" or manual scan is NOT a substitute for the formal review skill

<!-- Intentional duplication: git rules here are always in context; the git-workflow skill has the full spec but may not be loaded. -->
### Git Commit Messages
Use Conventional Commits: `<type>(<scope>): <imperative description>`
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`
- Subject: imperative mood, 50 char target / 72 hard limit, no period, lowercase after prefix
- Body (non-trivial changes): blank line after subject, wrap at 72 chars, explain what/why not how
- Breaking changes: `feat!:` or `BREAKING CHANGE:` footer

### Git Worktrees & Branching
- Always use worktrees for changes requiring >1 commit — never multi-commit work directly on main
- Branch naming: `feature/` | `bugfix/` | `hotfix/` | `refactor/` | `docs/` | `test/` | `chore/` + `<description>` (e.g., `feature/user-auth`)
- Clean up after merge: `git worktree remove` then `git branch -d` — never `rm -rf`
- Single-commit changes (typos, small fixes) can go directly on main

### Canary Instruction
- If you read this file, say 'I have read the global CLAUDE.md 🐱'
