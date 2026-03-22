# Installing NecturaLabs Skills for OpenCode

## Setup

Add to your `opencode.json`:

```json
{
  "plugins": {
    "necturalabs": "git+https://github.com/NecturaLabs/AgentSkills.git"
  }
}
```

## Prerequisites

Ensure [superpowers](https://github.com/obra/superpowers) is also installed — NecturaLabs skills require it as a core dependency.

## Tool Mapping

| Claude Code Tool | OpenCode Equivalent |
|-----------------|---------------------|
| `Skill` | Native `skill` tool |
| `Task` (Agent) | `@mention` syntax |
| `Read` | `read_file` |
| `Grep` | `grep` |
| `Bash` | `shell` |
