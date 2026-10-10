---
name: open-project-terminal
description: Open a new Claude Code session in its own terminal window for a named project, when the user asks to open up a session, terminal or Claude for a project (for example "open a terminal for Canopy"). Launches the terminal on a chosen workspace, in the project's directory, with the project's name and a first message. Not for opening files or an editor, not for running commands in the current session, and not for starting subagents (agent-orchestration).
compatibility: Claude Code, launched from a Hyprland desktop with kitty; adapt the launch command for another terminal or window manager.
---

# Open a project session terminal

The defaults below are this setup's; a value the user states overrides its default, and you change
the projects root, terminal and workspace once for your machine.

| Setting | Default |
|---|---|
| Terminal | `kitty`, window title = project name |
| Directory | the project's path under your projects root, `<projects-root>/<Name>` (find it with `ls <projects-root>`; if no folder matches, say so and stop) |
| Permissions | `--dangerously-skip-permissions` (bypass) |
| Model, effort | `--model haiku --effort low` |
| Session name | project name, `--name <Name>` |
| First message | `hi`, passed as the prompt argument |
| Workspace | `1`, opened silently so focus does not move |

## Command

Recent Hyprland takes Lua dispatch (the old `exec [workspace 1 silent] ...` syntax errors):

```bash
hyprctl dispatch 'hl.dsp.exec_cmd("kitty --title <Name> --directory <path> claude --dangerously-skip-permissions --model haiku --effort low --name <Name> hi", {workspace="1 silent"})'
```

Then confirm the window exists on the workspace:

```bash
hyprctl clients -j | python3 -c "import json,sys;[print(c['class'],c['workspace']['id'],c['title']) for c in json.load(sys.stdin) if c['class']=='kitty']"
```

Report the project, path and workspace in one line. Do not touch other windows.
