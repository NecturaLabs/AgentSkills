#!/usr/bin/env bash
# Asserts what setup/claude/scripts/context-meter.py promises.
# As the status line: context used, counted as Claude Code counts it, against the auto-compact
# window from the environment, else the user settings, else the model's window; the warning colours
# at 70% and 90%; right alignment; a placeholder rather than a failure when there is nothing to
# count yet.
# As the hook: one line of context on every prompt; after a tool call, a line only when 60%, 80%,
# 90% or 95% is first reached, again after a compaction lowers the count; nothing while the newest
# transcript entry is a compaction; subagents counted from their own transcript; never a failure.
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=${SCRIPT_DIR%/*}
LINE=$REPO_ROOT/setup/claude/scripts/context-meter.py

PASS=0
FAIL=0
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/agentskills context-meter.XXXXXX")
trap 'rm -rf -- "$SANDBOX"' EXIT

ok()  { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s -- %s\n' "$1" "$2"; }
check() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi
}

CONFIG="$SANDBOX/claude config"
mkdir -p "$CONFIG"
ESC=$(printf '\033')

payload() { # input cache_creation cache_read output
  printf '{"model":{"display_name":"Opus"},"context_window":{"context_window_size":1000000,'
  printf '"current_usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,' "$1" "$2"
  printf '"cache_read_input_tokens":%s,"output_tokens":%s}}}' "$3" "$4"
}
run() { # env-window payload
  env -u COLUMNS CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_CODE_AUTO_COMPACT_WINDOW="$1" python3 "$LINE" <<< "$2"
}

# 1. Window from the user settings; output tokens are not counted.
printf '{"autoCompactWindow": 500000}' > "$CONFIG/settings.json"
check "settings-window" "Opus · ctx 100k / 500k (20%)" "$(run '' "$(payload 1000 9000 90000 70000)")"

# 2. The settings value may carry a suffix; the environment beats the settings.
printf '{"autoCompactWindow": "400k"}' > "$CONFIG/settings.json"
check "settings-suffix" "Opus · ctx 100k / 400k (25%)" "$(run '' "$(payload 0 0 100000 0)")"
check "env-beats-settings" "Opus · ctx 100k / 200k (50%)" "$(run 200000 "$(payload 0 0 100000 0)")"

# 3. No setting falls back to the model's window, and a window above it is capped to it.
rm "$CONFIG/settings.json"
check "model-window" "Opus · ctx 100k / 1M (10%)" "$(run '' "$(payload 0 0 100000 0)")"
check "window-capped" "Opus · ctx 100k / 1M (10%)" "$(run 2000000 "$(payload 0 0 100000 0)")"

# 4. Yellow from 70% of the window, red from 90%, plain below.
out=$(run 500000 "$(payload 0 0 349000 0)")
check "plain-below-70" 0 "$(grep -c "$ESC" <<< "$out")"
out=$(run 500000 "$(payload 0 0 350000 0)")
check "yellow-at-70" 1 "$(grep -cF "${ESC}[33m" <<< "$out")"
out=$(run 500000 "$(payload 0 0 450000 0)")
check "red-at-90" 1 "$(grep -cF "${ESC}[31m" <<< "$out")"

# 5. Before the first call, right after a compaction, or on bad input: a placeholder, exit 0.
out=$(run '' '{"model":{"display_name":"Opus"},"context_window":{"context_window_size":1000000,"current_usage":null}}'); rc=$?
check "no-usage-placeholder" "Opus · ctx —" "$out"
check "no-usage-exit" 0 "$rc"
out=$(run '' 'not json'); rc=$?
check "bad-input-placeholder" "Claude · ctx —" "$out"
check "bad-input-exit" 0 "$rc"
out=$(run '' '{"model":"x","context_window":[]}'); rc=$?
check "odd-shapes-placeholder" "Claude · ctx —" "$out"
check "odd-shapes-exit" 0 "$rc"

# 6. The environment variable takes only a plain count; anything else falls through.
printf '{"autoCompactWindow": 500000}' > "$CONFIG/settings.json"
check "env-suffix-ignored" "Opus · ctx 100k / 500k (20%)" "$(run 400k "$(payload 0 0 100000 0)")"
printf '[]' > "$CONFIG/settings.json"
check "odd-settings-ignored" "Opus · ctx 100k / 1M (10%)" "$(run '' "$(payload 0 0 100000 0)")"

# 7. Right-aligned against COLUMNS, colour codes not counted as width; too narrow is not padded.
printf '{"autoCompactWindow": 500000}' > "$CONFIG/settings.json"
right() { # columns payload
  COLUMNS="$1" CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_CODE_AUTO_COMPACT_WINDOW='' python3 "$LINE" <<< "$2"
}
out=$(right 80 "$(payload 0 0 100000 0)")
check "right-aligned-width" 76 "${#out}"
check "right-aligned-tail" "(20%)" "${out##* }"
check "padding-survives-trim" "$(printf '\u2800')" "${out:0:1}" # Claude Code trims leading spaces
out=$(right 80 "$(payload 0 0 450000 0)")
plain=$(sed "s/${ESC}\[[0-9;]*m//g" <<< "$out")
check "colour-not-counted" 76 "${#plain}"
out=$(right 10 "$(payload 0 0 100000 0)")
check "narrow-not-padded" "Opus · ctx 100k / 500k (20%)" "$out"

# --- The hook -------------------------------------------------------------------------------------

SID=0f3c9a1e-1111-2222-3333-444455556666
SESSIONS="$SANDBOX/projects/my project"
MAIN="$SESSIONS/$SID.jsonl"
SUB="$SESSIONS/$SID/subagents/agent-abc123.jsonl"
PAD="$SANDBOX/scratch pad"
mkdir -p "$SESSIONS/$SID/subagents" "$PAD"
printf '{"autoCompactWindow": 500000}' > "$CONFIG/settings.json"
: > "$MAIN"

said() { # usage-in-thousands [file] [sidechain]
  printf '{"type":"assistant","isSidechain":%s,"message":{"usage":{"input_tokens":1000,' "${3:-false}" >> "${2:-$MAIN}"
  printf '"cache_creation_input_tokens":0,"cache_read_input_tokens":%s,"output_tokens":5000}}}\n' \
    "$(( $1 * 1000 - 1000 ))" >> "${2:-$MAIN}"
}
compacted() { printf '{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}\n' >> "$MAIN"; }
hook() { # event [agent-id]
  local agent=""
  [ -n "${2:-}" ] && agent=",\"agent_id\":\"$2\",\"agent_type\":\"sonnet-high\""
  printf '{"hook_event_name":"%s","session_id":"%s","transcript_path":"%s","scratchpad_dir":"%s"%s}' \
    "$1" "$SID" "$MAIN" "$PAD" "$agent" |
    env -u COLUMNS CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_CODE_AUTO_COMPACT_WINDOW='' python3 "$LINE"
}
context() { # the additionalContext of a hook's output, or "" when it said nothing
  python3 -c 'import json,sys; s=sys.stdin.read(); print(json.loads(s)["hookSpecificOutput"]["additionalContext"] if s.strip() else "")'
}
event_of() { python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["hookSpecificOutput"]["hookEventName"])'; }

# 8. Every prompt gets the count; output tokens are not counted.
said 100
check "prompt-line" "Context: 100k used of the 500k auto-compact window (20%)." "$(hook UserPromptSubmit | context)"
check "prompt-event-name" "UserPromptSubmit" "$(hook UserPromptSubmit | event_of)"

# 9. After a tool call: silent below 60%, once on reaching each step (60, 80, 90, 95%), silent
#    again after.
check "tool-below-60-silent" "" "$(hook PostToolUse)"
said 320
out=$(hook PostToolUse)
check "tool-at-60" "Context: 320k used of the 500k auto-compact window (64%)." "$(context <<< "$out")"
check "tool-event-name" "PostToolUse" "$(event_of <<< "$out")"
said 330
check "tool-60-once" "" "$(hook PostToolUse)"
said 460
check "tool-jump-to-90" "Context: 460k used of the 500k auto-compact window (92%)." "$(hook PostToolUse | context)"
check "tool-90-once" "" "$(hook PostToolUse)"
said 480
check "tool-at-95" "Context: 480k used of the 500k auto-compact window (96%)." "$(hook PostToolUse | context)"
check "tool-95-once" "" "$(hook PostToolUse)"
check "prompt-always" "Context: 480k used of the 500k auto-compact window (96%)." "$(hook UserPromptSubmit | context)"
check "state-in-scratchpad" 4 "$(ls "$PAD/.context-meter" | wc -l | tr -d ' ')"

# 10. A compaction newer than any usage: nothing. After it the steps fire again.
compacted
check "after-compaction-prompt-silent" "" "$(hook UserPromptSubmit)"
check "after-compaction-tool-silent" "" "$(hook PostToolUse)"
said 50
check "compacted-low-silent" "" "$(hook PostToolUse)"
said 310
check "step-fires-again" "Context: 310k used of the 500k auto-compact window (62%)." "$(hook PostToolUse | context)"

# 11. The main session ignores sidechain entries; a subagent is counted from its own transcript.
said 490 "$MAIN" true
check "main-ignores-sidechain" "" "$(hook PostToolUse)"
said 360 "$SUB"
check "subagent-own-count" "Context: 360k used of the 500k auto-compact window (72%)." "$(hook PostToolUse abc123 | context)"
check "subagent-once" "" "$(hook PostToolUse abc123)"
check "subagent-missing-silent" "" "$(hook PostToolUse nosuchagent)"

# 12. A partial last line is skipped, and usage far behind a large entry is still found.
printf '{"type":"assistant","message":{"usage":{"cache_read' >> "$MAIN"
check "partial-line-skipped" "Context: 310k used of the 500k auto-compact window (62%)." "$(hook UserPromptSubmit | context)"
printf '\n{"type":"user","message":{"content":"%s"}}\n' "$(head -c 600000 /dev/zero | tr '\0' 'x')" >> "$MAIN"
check "found-behind-large-entry" "Context: 310k used of the 500k auto-compact window (62%)." "$(hook UserPromptSubmit | context)"

# 12b. An entry split across the script's 256 KiB read boundary is joined, not lost.
STRADDLE="$SESSIONS/straddle.jsonl"
: > "$STRADDLE"
said 222 "$STRADDLE"
python3 - "$STRADDLE" <<'FILL'
import sys
path = sys.argv[1]
entry = len(open(path, "rb").read())
wrapper = len('{"type":"user","message":{"content":""}}\n')
fill = 256 * 1024 - entry // 2
with open(path, "a") as f:
    f.write('{"type":"user","message":{"content":"' + "x" * (fill - wrapper) + '"}}\n')
FILL
out=$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"straddle","transcript_path":"%s","scratchpad_dir":"%s"}' \
  "$STRADDLE" "$PAD" | CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_CODE_AUTO_COMPACT_WINDOW='' python3 "$LINE" | context)
check "entry-across-chunks" "Context: 222k used of the 500k auto-compact window (44%)." "$out"

# 12c. Synthetic entries (an interruption or an API error) carry zero usage: never read as 0% used,
#      and they do not reset the steps already announced.
: > "$MAIN"; rm -rf "$PAD/.context-meter"
said 420
check "before-synthetic" "Context: 420k used of the 500k auto-compact window (84%)." "$(hook PostToolUse | context)"
printf '{"type":"assistant","message":{"model":"<synthetic>","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}\n' >> "$MAIN"
check "synthetic-skipped" "Context: 420k used of the 500k auto-compact window (84%)." "$(hook UserPromptSubmit | context)"
said 425
check "synthetic-no-repeat" "" "$(hook PostToolUse)"

# 12d. A context on a 200k model (Haiku, or any 4.5 model) is counted against that window.
: > "$MAIN"; rm -rf "$PAD/.context-meter"
printf '{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":149000}}}\n' >> "$MAIN"
check "small-model-window" "Context: 150k used of the 200k auto-compact window (75%)." "$(hook UserPromptSubmit | context)"

# 12e. Without a scratchpad the markers go to a shared temp folder, where week-old ones are cleared.
TMPROOT="$SANDBOX/tmp root"
mkdir -p "$TMPROOT/claude-context-meter"
: > "$TMPROOT/claude-context-meter/old-session-main.1"; touch -d '8 days ago' "$TMPROOT/claude-context-meter/old-session-main.1"
: > "$TMPROOT/claude-context-meter/recent-session-main.1"
printf '{"hook_event_name":"UserPromptSubmit","session_id":"fallback","transcript_path":"%s"}' "$MAIN" |
  CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_CODE_TMPDIR="$TMPROOT" CLAUDE_CODE_AUTO_COMPACT_WINDOW='' python3 "$LINE" > /dev/null
check "fallback-old-cleared" 0 "$(ls "$TMPROOT/claude-context-meter" | grep -c '^old-session')"
check "fallback-recent-kept" 1 "$(ls "$TMPROOT/claude-context-meter" | grep -c '^recent-session')"
check "fallback-marker-written" 1 "$(ls "$TMPROOT/claude-context-meter" | grep -c '^fallback-main\.')"

# 13. Other events, a missing transcript and bad input: silent, and never a failure.
check "other-event-silent" "" "$(hook SessionStart)"
out=$(printf '{"hook_event_name":"PostToolUse","session_id":"x","transcript_path":"%s/none.jsonl"}' "$SANDBOX" |
  python3 "$LINE" 2>&1); rc=$?
check "missing-transcript-silent" "" "$out"
check "missing-transcript-exit" 0 "$rc"
out=$(printf '{"hook_event_name":"PostToolUse","transcript_path":["odd"]}' | python3 "$LINE" 2>/dev/null); rc=$?
check "odd-input-silent" "" "$out"
check "odd-input-exit" 0 "$rc"

printf '\nContext-meter summary: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
