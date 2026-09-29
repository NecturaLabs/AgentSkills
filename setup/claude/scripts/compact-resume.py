#!/usr/bin/env python3
"""SessionStart hook for source "compact": put the session's own record back in front of it, so a
session resumes from what it wrote down rather than from the compaction summary's paraphrase.

After a compaction it prints, for the context:
- the session's checklist, `checklist.md` in its scratchpad (the hook input's `scratchpad_dir`,
  else <CLAUDE_CODE_TMPDIR or the system temp dir>/claude-*/<project>/<session id>/scratchpad); a
  long one keeps its head (the task and its requests) and its tail (the latest state and the next
  step) and drops the middle;
- the names of the other files in that scratchpad, where saved findings and evidence live
  (hidden ones, such as the context meter's state, left out);
- `git status --short --branch` of the session's working directory, as much as fits.
The whole stays under Claude Code's 10,000-character cap on hook output: past it, the context
gets only the first 2,000 characters and a file path.
It prints facts only; what to do with them is the working agreement's rule, not this hook's.
Any other SessionStart source is silent. A broken or slow check never blocks the session.
"""
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

CHECKLIST = "checklist.md"
OUTPUT_MAX_CHARS = 9500
CHECKLIST_HEAD_CHARS = 1500
CHECKLIST_TAIL_CHARS = 5000
OTHER_FILES_MAX = 20
OTHER_FILES_MAX_CHARS = 600
GIT_LINE_MAX_CHARS = 200
GIT_TIMEOUT_S = 3
TIME_LIMIT_S = 8
SESSION_ID = re.compile(r"^[A-Za-z0-9_-]+$")


def scratchpad(data):
    given = data.get("scratchpad_dir")
    if given and Path(given).is_dir():
        return Path(given)
    session_id = str(data.get("session_id") or "")
    if not SESSION_ID.match(session_id):
        return None
    root = Path(os.environ.get("CLAUDE_CODE_TMPDIR") or tempfile.gettempdir())
    for path in sorted(root.glob(f"claude-*/*/{session_id}/scratchpad")):
        if path.is_dir():
            return path
    return None


def checklist_section(pad):
    if pad is None:
        return ["No scratchpad found for this session, so no checklist."]
    path = pad / CHECKLIST
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return [f"No {CHECKLIST} in this session's scratchpad ({pad})."]
    except OSError as exc:
        return [f"{path} could not be read: {exc.strerror or exc}"]
    text = text.strip()
    if len(text) <= CHECKLIST_HEAD_CHARS + CHECKLIST_TAIL_CHARS:
        return [f"Session checklist ({path}):", "", text]
    omitted = len(text) - CHECKLIST_HEAD_CHARS - CHECKLIST_TAIL_CHARS
    return [
        f"Session checklist ({path}):", "",
        text[:CHECKLIST_HEAD_CHARS],
        f"[... {omitted} of {len(text)} characters omitted here]",
        text[-CHECKLIST_TAIL_CHARS:],
    ]


def other_files_section(pad):
    if pad is None:
        return []
    try:
        names = sorted(
            str(rel) for rel in (p.relative_to(pad) for p in pad.rglob("*") if p.is_file())
            if rel != Path(CHECKLIST) and not any(part.startswith(".") for part in rel.parts)
        )
    except OSError:
        return []
    if not names:
        return []
    shown = ", ".join(names[:OTHER_FILES_MAX])
    if len(shown) > OTHER_FILES_MAX_CHARS:
        shown = shown[:OTHER_FILES_MAX_CHARS] + "..."
    more = f" (and {len(names) - OTHER_FILES_MAX} more)" if len(names) > OTHER_FILES_MAX else ""
    return [f"Other files in the scratchpad: {shown}{more}"]


def git_section(cwd, budget):
    """`git status` lines that fit in `budget` characters, noting how many were left out."""
    try:
        result = subprocess.run(
            ["git", "-C", cwd, "status", "--short", "--branch"],
            capture_output=True, text=True, timeout=GIT_TIMEOUT_S,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    if result.returncode != 0:
        return []
    lines = [line[:GIT_LINE_MAX_CHARS] for line in result.stdout.rstrip().splitlines()]
    header = f"git status ({cwd}):"
    reserve = len("[... and 99999 more]") + 1
    if len(header) + 1 + reserve > budget:
        return []
    out = [header]
    used = len(header) + 1
    for n, line in enumerate(lines):
        last = n == len(lines) - 1
        if used + len(line) + 1 + (0 if last else reserve) > budget:
            out.append(f"[... and {len(lines) - n} more]")
            break
        out.append(line)
        used += len(line) + 1
    return out


def main():
    if hasattr(signal, "SIGALRM"):
        signal.signal(signal.SIGALRM, lambda *_: sys.exit(0))
        signal.alarm(TIME_LIMIT_S)
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    if data.get("source") != "compact":
        return
    pad = scratchpad(data)
    out = ["Context compacted.", *checklist_section(pad)]
    others = other_files_section(pad)
    if others:
        out += ["", *others]
    cwd = data.get("cwd") or os.getcwd()
    budget = OUTPUT_MAX_CHARS - len("\n".join(out)) - 2
    git = git_section(cwd, budget) if Path(cwd).is_dir() else []
    if git:
        out += ["", *git]
    print("\n".join(out))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # a broken check must never block a session from resuming
        print(f"compact-resume: {exc}", file=sys.stderr)
