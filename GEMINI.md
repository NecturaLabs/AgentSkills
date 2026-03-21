# NecturaLabs Agent Skills

@skills/using-necturalabs/SKILL.md

## Gemini Tool Mapping

When NecturaLabs skills reference Claude Code tools, use these Gemini equivalents:

| Claude Code Tool | Gemini Equivalent |
|-----------------|-------------------|
| `Read` | `read_file` |
| `Grep` | `search_files` |
| `Glob` | `list_files` |
| `Bash` | `run_shell_command` |
| `Edit` | `edit_file` |
| `Write` | `write_file` |
| `Skill` | `activate_skill` |
| `Agent` (Task) | Not supported — use sequential execution |
