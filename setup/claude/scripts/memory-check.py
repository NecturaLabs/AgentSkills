#!/usr/bin/env python3
"""SessionStart hook: flag saved memories that no longer match the disk, so a session does not
start by trusting them. Deterministic, read-only and silent when everything checks out.

It reads the project's memory directory beside the session transcript (<project>/memory, with its
MEMORY.md index) and reports:
- index lines whose file is missing, and memory files the index does not list;
- [[links]] that name no memory;
- paths a memory names in backticks that no longer exist: absolute and ~ paths always; a path
  relative to the project only when its first directory exists there (a path from another
  repository is not this project's to judge) and it looks like a file or directory rather than a
  branch name (a file extension, or a trailing slash);
- memory files it cannot read.
Anything it prints is added to the session's context, with a pointer to the memory-hygiene skill.
A memory directory moved elsewhere with the autoMemoryDirectory setting is not followed. The check
gives up after a few seconds rather than hold a session's start (a hung network mount, say).
"""
import json
import os
import re
import signal
import sys
from pathlib import Path

MAX_LINES = 12
TIME_LIMIT_S = 5
INDEX_LINE = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\[[^\]]*\]\(([^)\s]+)[^)]*\)")
LINK = re.compile(r"\[\[([^\]]+)\]\]")
CODE = re.compile(r"`([^`\n]+)`")
NAME = re.compile(r"^name:\s*(.+?)\s*$", re.M)
PATHISH = re.compile(r"^(~/|/)?[\w.@+-]+(/[\w.@+ -]+)*/?$")


def memory_files(mem):
    return sorted(p for p in mem.glob("*.md") if p.name != "MEMORY.md")


def index_target(raw):
    """The memory file an index link names, or None when it names something else."""
    if "://" in raw or raw.startswith("mailto:"):
        return None
    target = raw.split("#", 1)[0]
    if target.startswith("./"):
        target = target[2:]
    if not target or "/" in target:
        return None
    return target


def looks_like_file_or_dir(text):
    last = text.rstrip("/").rsplit("/", 1)[-1]
    return text.endswith("/") or "." in last.lstrip(".")


def looks_like_path(text):
    if any(c in text for c in "<>*$|{}()[],;=") or "://" in text:
        return False
    if not PATHISH.match(text) or "/" not in text:
        return False
    return True


def check(mem, project):
    issues = []
    files = {p.name: p for p in memory_files(mem)}
    index = mem / "MEMORY.md"
    listed = set()
    try:
        index_lines = index.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        index_lines = []
        if index.exists():
            issues.append("MEMORY.md could not be read")
    if index_lines:
        for line in index_lines:
            m = INDEX_LINE.match(line)
            if not m:
                continue
            target = index_target(m.group(1).strip())
            if target is None:
                continue
            listed.add(target)
            if not (mem / target).is_file():
                issues.append(f"MEMORY.md lists {target}, which does not exist")
    for name in sorted(set(files) - listed):
        issues.append(f"{name} is not listed in MEMORY.md")

    names = set()
    texts = {}
    for name, path in files.items():
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            issues.append(f"{name} could not be read")
            continue
        texts[name] = text
        names.add(path.stem)
        m = NAME.search(text)
        if m:
            names.add(m.group(1).strip().strip("\"'"))
    home = Path.home()
    for name, text in texts.items():
        for raw_link in sorted(set(LINK.findall(text))):
            link = raw_link.split("|", 1)[0].split("#", 1)[0].strip()
            if link and link not in names:
                issues.append(f"{name} links [[{link}]], which names no memory")
        seen = set()
        for raw in CODE.findall(text):
            candidate = raw.strip().rstrip(".,:")
            if candidate in seen or not looks_like_path(candidate):
                continue
            seen.add(candidate)
            if candidate.startswith("~/"):
                path = home / candidate[2:]
            elif candidate.startswith("/"):
                path = Path(candidate)
            else:
                first = candidate.split("/", 1)[0]
                if not project or not (project / first).is_dir():
                    continue
                if not looks_like_file_or_dir(candidate):
                    continue
                path = project / candidate
            if not path.exists():
                issues.append(f"{name} names {candidate}, which does not exist")
    return issues


def main():
    if hasattr(signal, "SIGALRM"):
        signal.signal(signal.SIGALRM, lambda *_: sys.exit(0))
        signal.alarm(TIME_LIMIT_S)
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    transcript = data.get("transcript_path")
    if not transcript:
        return
    mem = Path(transcript).parent / "memory"
    if not mem.is_dir():
        return
    cwd = data.get("cwd") or os.getcwd()
    project = Path(cwd) if Path(cwd).is_dir() else None
    issues = check(mem, project)
    if not issues:
        return
    print(f"Memory check: {len(issues)} saved-memory issue(s) in {mem}. Treat the affected memories"
          " as unverified, and tend them with the memory-hygiene skill before relying on them.")
    for line in issues[:MAX_LINES]:
        print(f"- {line}")
    if len(issues) > MAX_LINES:
        print(f"- and {len(issues) - MAX_LINES} more")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # a broken check must never block a session from starting
        print(f"memory-check: {exc}", file=sys.stderr)
