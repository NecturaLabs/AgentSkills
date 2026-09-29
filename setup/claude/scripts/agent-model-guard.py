#!/usr/bin/env python3
"""PreToolUse hook for Agent: name each spawned subagent after the model and
effort it will actually run on (e.g. "sonnet-high"), whatever its type.

Resolution mirrors Claude Code's (docs, "Choose a model", v2.1.251 on): an
explicit `model` argument, else the agent definition's `model` frontmatter,
else CLAUDE_CODE_SUBAGENT_MODEL, else the caller's model. `inherit`, forks and
the built-in Explore and Plan agents take the caller's model. Effort is the
definition's `effort` frontmatter, else the caller's effort.

A spawn that would run on Fable is refused: this setup never uses Fable.

A `model` argument that contradicts a `<model>-<effort>` type is rewritten to
the matching type when one exists, so the type column cannot lie either.
"""
import fcntl
import json
import os
import re
import sys
from pathlib import Path

FAMILIES = ("opus", "sonnet", "haiku", "fable")
TYPED = re.compile(r"^(%s)-(low|medium|high|xhigh|max)$" % "|".join(FAMILIES))
FOLLOW_CALLER = {"Explore", "Plan"}
HOME = Path.home()


def family(model):
    if not model:
        return None
    m = model.lower()
    for f in FAMILIES:
        if f in m:
            return f
    return None


def frontmatter(path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    fields = {}
    for line in text[3:end].splitlines():
        k, sep, v = line.partition(":")
        if sep:
            fields[k.strip()] = v.strip().strip("\"'")
    return fields


def plugin_agent_dirs(plugin):
    try:
        data = json.loads((HOME / ".claude/plugins/installed_plugins.json").read_text())
    except (OSError, ValueError):
        return []
    dirs = []
    for key, installs in data.get("plugins", {}).items():
        if key.split("@")[0] != plugin:
            continue
        for inst in installs if isinstance(installs, list) else [installs]:
            p = inst.get("installPath")
            if p:
                dirs.append(Path(p) / "agents")
    return dirs


def definition(agent_type, cwd):
    if not agent_type:
        return {}
    if ":" in agent_type:
        plugin, _, name = agent_type.partition(":")
        dirs = plugin_agent_dirs(plugin)
    else:
        name = agent_type
        dirs = [Path(d) / ".claude/agents" for d in [cwd, *Path(cwd).parents]]
        dirs.append(HOME / ".claude/agents")
    for d in dirs:
        if not d.is_dir():
            continue
        for f in d.rglob("*.md"):
            fm = frontmatter(f)
            if fm and fm.get("name") == name:
                return fm
    return {}


def caller_model(transcript):
    try:
        with open(transcript, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            fh.seek(max(0, fh.tell() - 2_000_000))
            tail = fh.read().decode("utf-8", "replace")
    except (OSError, TypeError):
        return None
    found = re.findall(r'"model":"(claude-[^"]+)"', tail)
    return found[-1] if found else None


def unique(data, label):
    """A name held by a live agent is not reassigned, so number repeats per session."""
    state = Path(data.get("scratchpad_dir") or os.environ.get("CLAUDE_CODE_TMPDIR") or "/tmp") / f"agent-names-{data.get('session_id', 'none')}.json"
    with open(state, "a+") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        fh.seek(0)
        try:
            counts = json.loads(fh.read() or "{}")
        except ValueError:
            counts = {}
        n = counts.get(label, 0) + 1
        counts[label] = n
        fh.seek(0)
        fh.truncate()
        json.dump(counts, fh)
    return label if n == 1 else f"{label}-{n}"


def main():
    data = json.load(sys.stdin)
    ti = dict(data.get("tool_input") or {})
    agent_type = ti.get("subagent_type") or "general-purpose"
    cwd = data.get("cwd") or os.getcwd()
    parent_effort = (data.get("effort") or {}).get("level")
    parent_model = caller_model(data.get("transcript_path"))

    m = TYPED.match(agent_type)
    requested = family(ti.get("model"))
    if m and requested and requested != m.group(1):
        swapped = f"{requested}-{m.group(2)}"
        if definition(swapped, cwd):
            ti["subagent_type"] = agent_type = swapped
            ti.pop("model", None)

    if agent_type == "fork":
        model, effort = family(parent_model), parent_effort
    else:
        fm = definition(agent_type, cwd)
        chosen = ti.get("model") or fm.get("model")
        if chosen == "inherit" or (not chosen and agent_type in FOLLOW_CALLER):
            chosen = parent_model
        elif not chosen:
            chosen = os.environ.get("CLAUDE_CODE_SUBAGENT_MODEL") or parent_model
        model = family(chosen)
        effort = fm.get("effort") or parent_effort

    if model == "fable":
        json.dump({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "Fable is never used: pick a sonnet-* or opus-* type.",
        }}, sys.stdout)
        return
    if not model:
        return
    ti["name"] = unique(data, f"{model}-{effort}" if effort and model != "haiku" else model)
    json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": ti}}, sys.stdout)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # never block a spawn over a naming failure
        print(f"agent-model-guard: {exc}", file=sys.stderr)
