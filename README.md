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

## License

MIT
