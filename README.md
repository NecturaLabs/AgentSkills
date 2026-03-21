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

## Recommended CLAUDE.md

This repo includes a recommended global `CLAUDE.md`. Copy it to your global Claude config:

```
~/.claude/CLAUDE.md
```

On Windows: `C:\Users\<YourUsername>\.claude\CLAUDE.md`

## License

MIT
