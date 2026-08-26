# AgentSkills

A curated collection of AI agent skills for Claude Code. Layers on top of [superpowers](https://github.com/obra/superpowers) to add industry-standard code review, security auditing, test management, and project management.

## Prerequisites

- [superpowers](https://github.com/obra/superpowers) plugin installed (core dependency — all NecturaLabs skills require it)

## Installation

### Add Marketplace
```
/plugin marketplace add NecturaLabs/AgentSkills
```

### Install Skills
```
/plugin install necturalabs@necturalabs
```

After installation, skills are available as `necturalabs:<skill-name>`. Slash commands (e.g., `/necturalabs:code-review`) appear in auto-complete.

## Update

```
/plugin marketplace update necturalabs
```

## Uninstall

### Remove the Plugin
```
/plugin uninstall necturalabs@necturalabs
```

### Remove the Marketplace (optional)
```
/plugin marketplace remove necturalabs
```

## Available Skills

| Skill | When to invoke |
|-------|----------------|
| **`using-necturalabs`** — Initializes all skills, verifies dependencies, sets up review triggers | Conversation start, agent handoffs |
| **`iterative-code-review`** — Code review (Google, Clean Code, SOLID, Fowler) until clean pass | After any code changes, before commit/merge |
| **`iterative-security-audit`** — Security audit (OWASP, CWE, NIST, CERT) until clean, then code review | When changes touch security-sensitive code |
| **`agent-context-loader`** — Loads global CLAUDE.md and project AGENTS.md into context | On init, after context switches |
| **`agents-md-manager`** — Creates or updates project AGENTS.md from codebase analysis | Manual (`/agents-md-manager`) or after plan execution |
| **`git-workflow`** — Conventional Commits format and git worktree isolation | When committing or starting multi-commit work |
| **`update-plugins`** — Concurrently updates plugin marketplaces and installed plugins | Manual (`/update-plugins`) or when user asks to update |
| **`docs-manager`** — Creates and maintains project docs/ with ADRs, design docs, guides | Manual (`/docs-manager`) or when user asks to document |
| **`test-manager`** — Classifies and triages a project's tests, routes work to the level specialists | Test work with no obvious level, spanning levels, or suite-wide |
| **`comment-manager`** — Comment and doc-comment rules across languages, with a per-language matrix and a worked example per derived-language trap | Writing or changing code that carries comments |
| **`unit-test-manager`** — Unit tests: one unit, one process, no I/O | Writing or fixing unit tests |
| **`integration-test-manager`** — Tests across a process boundary: DB, HTTP, queue, filesystem | Writing or fixing integration tests |
| **`e2e-test-manager`** — End-to-end and browser tests of critical user journeys | Writing or fixing E2E/browser tests |

## How It Works

1. **`using-necturalabs`** runs at conversation start — checks superpowers dependency, loads context, sets up mandatory review triggers
2. **Code review** must run after every code change, before committing or claiming work is done
3. **Security audit** must run when changes touch security-related code (auth, crypto, input validation, etc.)
4. When both apply: **security audit first → code review second → combined summary**
5. Both produce a **score (1-100)** with positives, negatives, and informational findings

### Documentation (`docs-manager`)

The `docs-manager` skill creates and maintains a `docs/` folder following industry standards:

- **ADRs** (Architecture Decision Records, MADR 4.0) — append-only records of significant technical decisions with context, alternatives, and rationale
- **Design docs** (Google-style) — living documents for designs with goals, non-goals, alternatives, and cross-cutting concerns
- **How-to guides** — task-oriented step-by-step procedures (deployment, onboarding, debugging)
- **Reference material** — research, specs, and data models that informed decisions

Structure is scale-adaptive — directories are created only when the first document of that type is written. Every document has YAML frontmatter with status and `last-reviewed` date for staleness tracking. Invoke with `/docs-manager` or ask Claude to document a decision or design.

### Testing (`test-manager` and the level specialists)

Test work is split across four skills so each stays expert in its own level:

- **`test-manager`** — classifies every test in a project, routes work to the right specialist, triages defects (flaky, skipped, duplicated, obsolete, assertion-free, change-detector, copy-asserting), and runs the full suite before the work is called done. Fans out to per-level subagents only when the work spans levels or covers the whole suite.
- **`unit-test-manager`** — one unit, one process, no I/O.
- **`integration-test-manager`** — our code against a real database, HTTP server, queue, or filesystem.
- **`e2e-test-manager`** — critical user journeys through the assembled system.

All four enforce the same six house rules, duplicated in each skill so every one is usable standalone — verbatim apart from clauses a level adds for its own failure modes: never test a library or framework; never assert on human-readable copy; observe every new test failing before trusting it; never weaken a test to get green; never encode a known bug as expected behavior; and own every test defect your own run surfaces — fix it, or report it with file:line, never silently leave it. The add/update/leave decision follows Google's "strive for unchanging tests" rule — refactorings and new features never edit existing tests; only a deliberate behavior change does, or repairing a test that is itself defective.

Rules are sourced from Google's *Software Engineering at Google* and Testing Blog, Martin Fowler, Microsoft Learn, Kent Beck's Test Desiderata, Khorikov's four pillars, and the official docs of pytest, JUnit 5, Jest/Vitest, Go, Playwright, Cypress, Testcontainers, and MSW.

## New to AI Agent Tooling?

See **[CONCEPTS.md](CONCEPTS.md)** for a guide on Skills, MCP, LSP, and RAG — what they are, when to use each, and how they work together.

## Recommended: LSP Setup

LSP gives Claude Code IDE-level code intelligence — semantic navigation instead of text-based grep. Highly recommended for code review and security audit accuracy.

### 1. Enable the LSP Tool

Add to `~/.claude/settings.json`:
```json
{
  "env": {
    "ENABLE_LSP_TOOL": "1"
  }
}
```

Also add to your shell profile (`.bashrc` / `.zshrc` / PowerShell `$PROFILE`) as a fallback:
```bash
export ENABLE_LSP_TOOL=1
```

### 2. Install Language Server Binaries

| Language | Install |
|----------|---------|
| **TypeScript/JS** | `npm i -g typescript-language-server typescript` |
| **Python** | `npm i -g pyright` or `pip install pyright` |
| **Go** | `go install golang.org/x/tools/gopls@latest` |
| **Rust** | `rustup component add rust-analyzer` |
| **C#** | `dotnet tool install -g csharp-ls` |
| **C/C++** | Install `clangd` via LLVM (`brew install llvm` / `choco install llvm` / `apt install clangd`) |
| **Lua** | `brew install lua-language-server` or download from GitHub releases |

### 3. Install and Enable Plugins

```bash
claude plugin marketplace update claude-plugins-official
claude plugin install typescript-lsp@claude-plugins-official
claude plugin install pyright-lsp@claude-plugins-official
# ... repeat for each language you need
```

Verify they're enabled:
```bash
claude plugin list
```

If any show `Status: disabled`:
```bash
claude plugin enable <plugin-name>
```

### 4. Restart Claude Code

Restart for changes to take effect. Verify in debug logs at `~/.claude/debug/latest` — look for `Total LSP servers loaded: N`.

### Troubleshooting

| Problem | Fix |
|---------|-----|
| **LSP tool not available** | Ensure `ENABLE_LSP_TOOL=1` in settings.json, restart |
| **Plugin not found** | Run `claude plugin marketplace update claude-plugins-official` |
| **Plugin disabled** | Run `claude plugin enable <name>`, restart |
| **Binary not found** | Verify with `which <binary>`, ensure it's in PATH |

### LSP Capabilities

Once configured, Claude Code gains these tools:
- `goToDefinition` / `goToImplementation` — jump to source
- `findReferences` — all usages across the codebase
- `workspaceSymbol` — find any symbol by name
- `documentSymbol` — list all symbols in a file
- `hover` — type info without reading the file
- `incomingCalls` / `outgoingCalls` — call hierarchy

## Recommended CLAUDE.md

This repo includes a recommended global `CLAUDE.md`. Copy it to your global Claude config:

```
~/.claude/CLAUDE.md
```

On Windows: `C:\Users\<YourUsername>\.claude\CLAUDE.md`

It is a **global** file — keep it free of anything specific to one repository. It follows you across every project, and a relative `@import` written there resolves against `~/.claude/`, not against whatever repo you happen to be in. (Working in this repo, Claude Code also loads it as the project's instructions, since it sits at the root. That's why repo-specific wiring lives in `.claude/CLAUDE.md` instead.)

## CLAUDE.md vs AGENTS.md

Two files, two different jobs. The split is **scope**, not who wrote them.

| | `~/.claude/CLAUDE.md` | `AGENTS.md` |
|---|---|---|
| **Answers** | How *you* want an agent to work | What is true of *this codebase* |
| **Travels with** | You, across every project | The repo, to every contributor |
| **Contains** | Standards of care, review gates, commit conventions, shell and OS rules, model choices | Build/test/lint commands, project structure, code conventions, boundaries |
| **Read by** | Claude Code | Codex, Cursor, Copilot and 20+ other tools — [and Claude Code only via an import](#making-agentsmd-load-in-claude-code) |
| **Checked in** | No — it's yours | Yes |

Two questions settle almost every case:

- *Would this still be true if I switched to a different project?* → global `CLAUDE.md`
- *Would this still be true if I switched to a different agent?* → `AGENTS.md`
- *Neither — specific to this repo **and** only meaningful to Claude Code?* → the project's `.claude/CLAUDE.md`, below the import

So "always run the review skill before committing" is global CLAUDE.md — it's how you work. "Run the suite from Git Bash, not PowerShell" is AGENTS.md — it's a fact about this repo, and a Codex or Cursor user needs it just as much as you do.

Never duplicate between them. Anything written twice goes stale in one place first, and a contradiction between two loaded instruction files gets resolved arbitrarily.

### Making AGENTS.md load in Claude Code

Claude Code reads `CLAUDE.md`, not `AGENTS.md`. To have both load without duplicating content, add a one-line import. Claude Code loads `./CLAUDE.md` and `./.claude/CLAUDE.md` both, so either works — but **the path is relative to the file holding it**, and getting it wrong loads nothing and reports nothing:

| Import lives in | Write |
|---|---|
| `./CLAUDE.md` | `@AGENTS.md` |
| `./.claude/CLAUDE.md` | `@../AGENTS.md` |

Use `.claude/CLAUDE.md` when the root `CLAUDE.md` is one you distribute — as this repo's is. Repo-specific wiring stays in `.claude/` and the portable file stays portable.

Then confirm it worked: run `/context` in a fresh session and check that both files appear under **Memory files**, and that something only `AGENTS.md` says is actually in context. A broken import looks identical to a working one until you check.

Run `/agents-md-manager` to have this set up for you, including the equivalent adapter for Gemini CLI.

## License

MIT
