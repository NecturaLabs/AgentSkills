#!/usr/bin/env python3
"""Claude Code status line: the model and how full the context is against the auto-compact window,
so a compaction can be seen coming. Newer models are not told their own token count, so this is
the only running view of it.

Used tokens follow Claude Code's own `used_percentage` formula: input, cache-creation and
cache-read tokens of the last API call. The window is CLAUDE_CODE_AUTO_COMPACT_WINDOW (a plain
token count) when set, else `autoCompactWindow` from the user settings (under CLAUDE_CONFIG_DIR
or ~/.claude), capped at the model's context window, else the model's context window. A window set by the `--autocompact`
flag or in project settings is not visible here. The count turns yellow at 70% of the window and
red at 90%.
"""
import json
import os
import re
import sys
from pathlib import Path

WARN = 0.70
ALERT = 0.90
YELLOW = "\033[33m"
RED = "\033[31m"
RESET = "\033[0m"
SIZE = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*([kKmM]?)\s*$")


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
    window = int(env) if env.isdigit() and int(env) > 0 else None  # the variable takes a plain count
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


def line(data):
    model = (data.get("model") or {}).get("display_name") or "Claude"
    ctx = data.get("context_window") or {}
    usage = ctx.get("current_usage")
    window = compact_window(ctx.get("context_window_size") or 0)
    if not usage or not window:
        return f"{model} · ctx —"
    used = sum(usage.get(k) or 0 for k in
               ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
    share = used / window
    text = f"ctx {tokens(used)} / {tokens(window)} ({round(share * 100)}%)"
    colour = RED if share >= ALERT else YELLOW if share >= WARN else ""
    return f"{model} · {colour}{text}{RESET if colour else ''}"


def main():
    try:
        data = json.load(sys.stdin)
        text = line(data if isinstance(data, dict) else {})
    except (ValueError, AttributeError, TypeError):
        text = line({})
    print(text)


if __name__ == "__main__":
    main()
