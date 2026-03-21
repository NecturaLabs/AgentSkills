# Installing NecturaLabs Skills for Codex

## Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/NecturaLabs/AgentSkills.git ~/.codex/necturalabs
   ```

2. Symlink skills into Codex's skill discovery directory:
   ```bash
   mkdir -p ~/.agents/skills
   ln -s ~/.codex/necturalabs/skills ~/.agents/skills/necturalabs
   ```

3. Ensure [superpowers](https://github.com/obra/superpowers) is also installed — NecturaLabs skills require it for code review and security audit.

## Tool Mapping

| Claude Code Tool | Codex Equivalent |
|-----------------|------------------|
| `Skill` | Native skill discovery |
| `Task` (Agent) | `spawn_agent` |
| `Read` | `read_file` |
| `Grep` | `grep` |
| `Bash` | `shell` |

## Updating

```bash
cd ~/.codex/necturalabs && git pull
```
