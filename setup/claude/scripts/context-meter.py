#!/usr/bin/env python3
"""How full the context is against the auto-compact window, shown to the user and told to the model.
Newer models are not told their own token count, so without this a compaction arrives unannounced.

One script, two roles, told apart by the input:
- Status line (input without `hook_event_name`): the model and the count, right-aligned in the
  status line's row. Claude Code draws that row above the footer and has no setting to move it, so
  the text is padded with spaces against COLUMNS (the terminal width Claude Code passes in),
  leaving RIGHT_MARGIN for the row's own padding. Yellow from 70% of the window, red from 90%.
- Hook: on UserPromptSubmit it always adds one line of context with the count; on PostToolUse it
  adds that line only when the count first reaches 60%, 80%, 90% or 95% of the window, once per
  step, and again after a compaction brings the count back down. Main session and each subagent
  are counted separately.

Used tokens follow Claude Code's own `used_percentage` formula: input, cache-creation and
cache-read tokens of the last API call. The status line reads them from its input; the hook reads
the last assistant entry of the transcript (the subagent's own transcript for a subagent), which
can lag by one call, and says nothing when a compaction is newer than that entry. Synthetic entries
(an interruption or an API error), which carry zero usage, are skipped.

The window is CLAUDE_CODE_AUTO_COMPACT_WINDOW (a plain token count) when set, else
`autoCompactWindow` from the user settings (under CLAUDE_CONFIG_DIR or ~/.claude), capped at the
model's context window, else the model's context window. A window set by the `--autocompact` flag
or in project settings is not visible here. The hook takes the model's window from the entry's
model: 200k for Haiku and the 4.5 models, else 1M, as every Claude 5 model has. It never fails in a
way that could block a prompt or a tool call.
"""
import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path

THRESHOLDS = (0.60, 0.80, 0.90, 0.95)
WARN = 0.70
ALERT = 0.90
YELLOW = "\033[33m"
RED = "\033[31m"
RESET = "\033[0m"
RIGHT_MARGIN = 4
LARGE_WINDOW = 1_000_000
SMALL_WINDOW = 200_000
SMALL_WINDOW_MODELS = re.compile(r"haiku|-4-5|claude-3")
MARKER_MAX_AGE_S = 7 * 24 * 3600
SCAN_CHUNK = 256 * 1024
SCAN_MAX = 16 * 1024 * 1024
ANSI = re.compile(r"\033\[[0-9;]*m")
SIZE = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*([kKmM]?)\s*$")
SAFE_KEY = re.compile(r"[^A-Za-z0-9_-]")
USAGE_KEYS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")
NOT_USAGE = object()


def parse_size(value):
    """Tokens from 500000, "500000", "500k" or "1M"; a bare 100-1000 means thousands."""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        number, suffix = float(value), ""
    else:
        m = SIZE.match(str(value))
        if not m:
            return None
        number, suffix = float(m.group(1)), m.group(2).lower()
    if suffix == "k" or (not suffix and 100 <= number <= 1000):
        number *= 1000
    elif suffix == "m":
        number *= 1_000_000
    return int(number) if number > 0 else None


def compact_window(context_size):
    env = os.environ.get("CLAUDE_CODE_AUTO_COMPACT_WINDOW", "").strip()
    window = int(env) if env.isdigit() and int(env) > 0 else None  # a plain count only
    if window is None:
        config = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
        try:
            settings = json.loads((config / "settings.json").read_text(encoding="utf-8"))
            window = parse_size(settings.get("autoCompactWindow"))
        except (OSError, ValueError, AttributeError):
            window = None
    if context_size and (window is None or window > context_size):
        return context_size
    return window


def tokens(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}".rstrip("0").rstrip(".") + "M"
    return f"{round(n / 1000)}k"


def used_tokens(usage):
    return sum(usage.get(k) or 0 for k in USAGE_KEYS)


# Status line


def status_text(data):
    model = (data.get("model") or {}).get("display_name") or "Claude"
    ctx = data.get("context_window") or {}
    usage = ctx.get("current_usage")
    window = compact_window(ctx.get("context_window_size") or 0)
    if not usage or not window:
        return f"{model} · ctx —"
    used = used_tokens(usage)
    share = used / window
    text = f"ctx {tokens(used)} / {tokens(window)} ({round(share * 100)}%)"
    colour = RED if share >= ALERT else YELLOW if share >= WARN else ""
    return f"{model} · {colour}{text}{RESET if colour else ''}"


def right_aligned(text, columns):
    width = len(ANSI.sub("", text))
    if not columns.isdigit():
        return text
    return " " * max(0, int(columns) - RIGHT_MARGIN - width) + text


def status_line(data):
    try:
        text = status_text(data)
    except (AttributeError, TypeError):
        text = status_text({})
    return right_aligned(text, os.environ.get("COLUMNS", ""))


# Hook


def transcript_for(data):
    """The transcript that holds this context: the session's, or the subagent's own."""
    path = data.get("transcript_path")
    if not path:
        return None
    path = Path(path)
    agent = data.get("agent_id")
    if agent:
        name = f"agent-{agent}.jsonl"
        if path.name != name:
            path = path.with_suffix("") / "subagents" / name
    return path if path.is_file() else None


def entry_usage(raw, main):
    """(used tokens, model) for an assistant entry, None for a compaction marker, else NOT_USAGE."""
    try:
        entry = json.loads(raw)
    except ValueError:
        return NOT_USAGE
    if not isinstance(entry, dict) or (main and entry.get("isSidechain")):
        return NOT_USAGE
    if entry.get("type") == "system" and entry.get("subtype") == "compact_boundary":
        return None
    message = entry.get("message")
    if entry.get("type") == "assistant" and isinstance(message, dict):
        usage = message.get("usage")
        model = str(message.get("model") or "")
        if isinstance(usage, dict) and model != "<synthetic>":
            used = used_tokens(usage)
            if used:
                return used, model
    return NOT_USAGE


def last_usage(path, main):
    """(used tokens, model) of the newest assistant entry, read backwards from the end of the
    transcript; None when there is none or a compaction is newer."""
    with open(path, "rb") as f:
        pos = f.seek(0, os.SEEK_END)
        carry = b""
        scanned = 0
        while pos > 0 and scanned < SCAN_MAX:
            step = min(SCAN_CHUNK, pos)
            pos -= step
            f.seek(pos)
            lines = (f.read(step) + carry).split(b"\n")
            carry = lines.pop(0) if pos > 0 else b""
            scanned += step
            for raw in reversed(lines):
                if raw.strip():
                    found = entry_usage(raw, main)
                    if found is not NOT_USAGE:
                        return found
    return None


def model_window(model):
    return SMALL_WINDOW if SMALL_WINDOW_MODELS.search(model) else LARGE_WINDOW


def state_dir(data):
    """Where the step markers live: the session's scratchpad, which goes with the session, else
    a shared temp folder, where markers older than a week are cleared."""
    pad = data.get("scratchpad_dir")
    if pad and Path(pad).is_dir():
        return Path(pad) / ".context-meter"
    root = Path(os.environ.get("CLAUDE_CODE_TMPDIR") or tempfile.gettempdir())
    folder = root / "claude-context-meter"
    if folder.is_dir():
        cutoff = time.time() - MARKER_MAX_AGE_S
        for old in folder.iterdir():
            try:
                if old.stat().st_mtime < cutoff:
                    old.unlink()
            except OSError:
                pass
    return folder


def newly_reached(data, band):
    """Record the steps reached; True when `band` is reached for the first time since the last
    compaction. Markers are created exclusively, so parallel tool calls announce a step once."""
    folder = state_dir(data)
    folder.mkdir(parents=True, exist_ok=True)
    session = data.get("session_id") or "session"
    key = SAFE_KEY.sub("_", f"{session}-{data.get('agent_id') or 'main'}")
    fresh = False
    for step in range(1, len(THRESHOLDS) + 1):
        marker = folder / f"{key}.{step}"
        if step > band:
            marker.unlink(missing_ok=True)
            continue
        try:
            os.close(os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
            fresh = fresh or step == band
        except FileExistsError:
            pass
    return fresh


def hook_output(data):
    event = data.get("hook_event_name")
    if event not in ("UserPromptSubmit", "PostToolUse"):
        return None
    transcript = transcript_for(data)
    found = last_usage(transcript, main=not data.get("agent_id")) if transcript else None
    if found is None:
        return None
    used, model = found
    window = compact_window(model_window(model))
    if not window:
        return None
    share = used / window
    band = sum(share >= t for t in THRESHOLDS)
    fresh = newly_reached(data, band)
    if event == "PostToolUse" and not fresh:
        return None
    text = (f"Context: {tokens(used)} used of the {tokens(window)} auto-compact window"
            f" ({round(share * 100)}%).")
    return json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": text}})


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        data = {}
    if not isinstance(data, dict):
        data = {}
    if "hook_event_name" not in data:
        print(status_line(data))
        return
    try:
        out = hook_output(data)
    except Exception as exc:  # a broken meter must never block a prompt or a tool call
        print(f"context-meter: {exc}", file=sys.stderr)
        return
    if out:
        print(out)


if __name__ == "__main__":
    main()
