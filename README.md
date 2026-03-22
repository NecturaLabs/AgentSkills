# AgentSkills

A curated collection of AI agent skills for Claude Code. Layers on top of [superpowers](https://github.com/obra/superpowers) to add industry-standard code review, security auditing, and project management.

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

## License

MIT
