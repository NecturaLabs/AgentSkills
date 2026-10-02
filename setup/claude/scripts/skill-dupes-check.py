#!/usr/bin/env python3
"""SessionStart hook: flag skills and plugins installed twice, so duplicates are caught the session
after they appear instead of piling up. Deterministic, read-only and silent when nothing is wrong.

It reports, for Claude Code:
- a plugin installed from more than one marketplace (installed_plugins.json);
- a loose skill in ~/.claude/skills whose name an installed plugin also ships;
- plugin cache or data folders for a marketplace that is no longer configured (leftovers such as
  a removed `local` marketplace);
and for Codex, when the `codex` command is available:
- a loose skill in ~/.agents/skills or ~/.codex/skills whose name an installed Codex plugin ships;
- one skill name in both of those folders resolving to different files.
Anything it prints is added to the session's context. The check gives up after a few seconds
rather than hold a session's start.
"""
import json
import os
import re
import signal
import subprocess
import sys
from pathlib import Path

MAX_LINES = 12
TIME_LIMIT_S = 5
HOME = Path.home()
CLAUDE_PLUGINS = HOME / ".claude" / "plugins"
CODEX_PLUGIN_CACHE = HOME / ".codex" / "plugins" / "cache"
INSTALLED = re.compile(r"^(\S+)@(\S+)\s+installed, enabled\b")


def load_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def loose_skills(root):
    """Skill folders (or links to them) directly under root, by name."""
    if not root.is_dir():
        return {}
    return {
        p.name: p
        for p in root.iterdir()
        if not p.name.startswith(".") and p.name != "synced" and (p / "SKILL.md").exists()
    }


def skill_names(plugin_root):
    return {p.parent.name for p in plugin_root.glob("**/skills/*/SKILL.md")}


def check_claude():
    issues = []
    installed = load_json(CLAUDE_PLUGINS / "installed_plugins.json") or {}
    installed = installed.get("plugins", installed)
    by_name = {}
    for key in installed:
        name, _, market = key.partition("@")
        by_name.setdefault(name, []).append(market)
    for name, markets in sorted(by_name.items()):
        if len(markets) > 1:
            issues.append(f"Claude plugin {name} is installed from {', '.join(sorted(markets))}")
    shipped = {}
    for key, entries in installed.items():
        for entry in entries if isinstance(entries, list) else [entries]:
            path = entry.get("installPath") if isinstance(entry, dict) else None
            if path:
                for skill in skill_names(Path(path)):
                    shipped.setdefault(skill, key)
    for name, path in sorted(loose_skills(HOME / ".claude" / "skills").items()):
        if name in shipped:
            issues.append(f"{path} duplicates skill {name} from plugin {shipped[name]}")
    markets = set((load_json(CLAUDE_PLUGINS / "known_marketplaces.json") or {}).keys())
    if markets:
        cache = CLAUDE_PLUGINS / "cache"
        for d in sorted(cache.iterdir()) if cache.is_dir() else []:
            if d.is_dir() and d.name not in markets:
                issues.append(f"{d} belongs to no configured marketplace (leftover)")
        data = CLAUDE_PLUGINS / "data"
        for d in sorted(data.iterdir()) if data.is_dir() else []:
            if not any(d.name.endswith("-" + m) for m in markets):
                issues.append(f"{d} belongs to no configured marketplace (leftover)")
    return issues


def check_codex():
    try:
        out = subprocess.run(
            ["codex", "plugin", "list"], capture_output=True, text=True, timeout=3, check=False
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    shipped = {}
    for line in out.splitlines():
        m = INSTALLED.match(line.strip())
        if m:
            plugin, market = m.groups()
            for skill in skill_names(CODEX_PLUGIN_CACHE / market / plugin):
                shipped.setdefault(skill, f"{plugin}@{market}")
    issues = []
    roots = [loose_skills(HOME / ".agents" / "skills"), loose_skills(HOME / ".codex" / "skills")]
    for skills in roots:
        for name, path in sorted(skills.items()):
            if name in shipped:
                issues.append(f"{path} duplicates skill {name} from Codex plugin {shipped[name]}")
    for name in sorted(set(roots[0]) & set(roots[1])):
        if roots[0][name].resolve() != roots[1][name].resolve():
            issues.append(f"skill {name} is in ~/.agents/skills and ~/.codex/skills as different files")
    return issues


def main():
    if hasattr(signal, "SIGALRM"):
        signal.signal(signal.SIGALRM, lambda *_: sys.exit(0))
        signal.alarm(TIME_LIMIT_S)
    issues = check_claude() + check_codex()
    if not issues:
        return
    print(f"Skill duplicates: {len(issues)} issue(s). A skill or plugin installed twice loads twice."
          " Tell the user and offer to remove the loose copy or leftover (back it up first).")
    for line in issues[:MAX_LINES]:
        print(f"- {line}")
    if len(issues) > MAX_LINES:
        print(f"- and {len(issues) - MAX_LINES} more")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # a broken check must never block a session from starting
        print(f"skill-dupes-check: {exc}", file=sys.stderr)
