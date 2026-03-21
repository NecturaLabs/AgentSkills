# AgentSkills

A curated collection of AI agent skills for Claude Code. Layers on top of [superpowers](https://github.com/obra/superpowers) to add industry-standard code review, security auditing, and project management.

## Prerequisites

- [superpowers](https://github.com/obra/superpowers) plugin installed (required for code review and security audit skills)

## Installation

### Add Marketplace
```
/plugin marketplace add NecturaLabs/AgentSkills
```

### Install Skills
```
/plugin install necturalabs@necturalabs
```

After installation, skills are available as `necturalabs:<skill-name>`.

## Available Skills

| Skill | Description | Auto-triggers |
|-------|-------------|---------------|
| `necturalabs:using-necturalabs` | Initializes all NecturaLabs skills, verifies dependencies, registers auto-triggers | Conversation start, agent changes |
| `necturalabs:iterative-code-review` | Industry-standard code review (Google, Clean Code, SOLID, Fowler) — iterates until clean pass | After any agent changes |
| `necturalabs:iterative-security-audit` | Security audit (OWASP, CWE, NIST, CERT) — iterates until clean pass, then triggers code review | When changes are security-related |
| `necturalabs:agent-context-loader` | Loads global CLAUDE.md and project AGENTS.md into full context | Conversation start, agent changes |
| `necturalabs:agents-md-manager` | Auto-creates or updates project AGENTS.md from codebase analysis | Conversation start, when project changes |

## How It Works

1. **`using-necturalabs`** runs at conversation start — checks superpowers dependency, loads context, manages AGENTS.md
2. **Code review** runs automatically after every change the agent makes
3. **Security audit** runs automatically when changes touch security-related code (auth, crypto, input validation, etc.)
4. When both apply: **security audit first → code review second → combined summary**
5. Both produce a **score (1-100)** with positives, negatives, and informational findings

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

Install the language servers you need:

| Language | Install Command |
|----------|----------------|
| TypeScript/JS | `npm i -g typescript-language-server typescript` |
| Python | `npm i -g pyright` or `pip install pyright` |
| Go | `go install golang.org/x/tools/gopls@latest` |
| Rust | `rustup component add rust-analyzer` |
| C# | `dotnet tool install -g csharp-ls` |
| C/C++ | Install `clangd` via LLVM (`brew install llvm` / `choco install llvm` / `apt install clangd`) |
| Lua | Install `lua-language-server` (`brew install lua-language-server` / download from GitHub releases) |

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
| LSP tool not available | Ensure `ENABLE_LSP_TOOL=1` in settings.json, restart |
| Plugin not found | Run `claude plugin marketplace update claude-plugins-official` |
| Plugin disabled after install | Run `claude plugin enable <name>`, restart |
| Binary not found | Verify with `which <binary>` (e.g. `which pyright-langserver`), ensure it's in PATH |

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
