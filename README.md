# AgentSkills

A curated collection of AI agent skills for Claude Code and other AI assistants.

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

| Skill | Description |
|-------|-------------|
| `necturalabs:iterative-code-review` | Iterative code review that runs until a clean pass — reviews changes, branch commits, or full codebase |
| `necturalabs:iterative-security-audit` | Iterative security audit (OWASP top 10) that runs until a clean pass — audits changes, branch commits, or full codebase |
| `necturalabs:agent-context-loader` | Ensures global CLAUDE.md and project AGENTS.md are always fully loaded in agent context |

## Recommended CLAUDE.md

This repo includes a recommended global `CLAUDE.md` with best-practice instructions for Claude Code agents. To use it:

1. Copy `CLAUDE.md` from this repo to your global Claude config:
   ```
   ~/.claude/CLAUDE.md
   ```
   On Windows: `C:\Users\<YourUsername>\.claude\CLAUDE.md`

2. Edit as needed for your environment and preferences.

This file is loaded by Claude Code at the start of every conversation and provides persistent instructions across all projects — code intelligence preferences, token efficiency rules, and agent behavior guidelines.

## License

MIT
