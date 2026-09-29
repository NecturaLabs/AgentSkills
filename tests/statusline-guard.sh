#!/usr/bin/env bash
# Asserts what setup/claude/scripts/statusline.py promises: context used, counted as Claude Code
# counts it, against the auto-compact window from the environment, else the user settings, else the
# model's window; the warning colours at 70% and 90%; and a placeholder rather than a failure when
# there is nothing to count yet.
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=${SCRIPT_DIR%/*}
LINE=$REPO_ROOT/setup/claude/scripts/statusline.py

PASS=0
FAIL=0
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/agentskills statusline.XXXXXX")
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
out=$(right 80 "$(payload 0 0 450000 0)")
plain=$(sed "s/${ESC}\[[0-9;]*m//g" <<< "$out")
check "colour-not-counted" 76 "${#plain}"
out=$(right 10 "$(payload 0 0 100000 0)")
check "narrow-not-padded" "Opus · ctx 100k / 500k (20%)" "$out"

printf '\nStatusline summary: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
