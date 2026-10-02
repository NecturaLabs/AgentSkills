#!/usr/bin/env bash
# Asserts what setup/claude/scripts/skill-dupes-check.py promises: silence on a clean setup, one
# line per duplicate or leftover otherwise, and never a failure that could block a session.
#
# Runs in a mktemp sandbox used as HOME, with a space in its path, and without `codex` on PATH
# unless a fake one is provided.
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=${SCRIPT_DIR%/*}
CHECK=$REPO_ROOT/setup/claude/scripts/skill-dupes-check.py

PASS=0
FAIL=0
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/agentskills skill-dupes.XXXXXX")
trap 'rm -rf -- "$SANDBOX"' EXIT

ok()  { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s -- %s\n' "$1" "$2"; }

H="$SANDBOX/home"
BIN="$SANDBOX/bin"
mkdir -p "$H/.claude/plugins/cache/mkt" "$H/.claude/skills" "$H/.agents/skills" "$BIN" \
  "$H/plug/skills/alpha" "$H/.codex/plugins/cache/mkt/tool/1.0/skills/beta"
echo x > "$H/plug/skills/alpha/SKILL.md"
echo x > "$H/.codex/plugins/cache/mkt/tool/1.0/skills/beta/SKILL.md"
printf '{"plugins": {"tool@mkt": [{"installPath": "%s"}]}}' "$H/plug" > "$H/.claude/plugins/installed_plugins.json"
printf '{"mkt": {}}' > "$H/.claude/plugins/known_marketplaces.json"
printf '#!/bin/sh\necho "tool@mkt  installed, enabled  1.0  local"\n' > "$BIN/codex"
chmod +x "$BIN/codex"

run() { HOME="$H" PATH="$BIN:/usr/bin:/bin" python3 "$CHECK" </dev/null 2>&1; }

out=$(run)
[ -z "$out" ] && ok "clean setup is silent" || bad "clean setup is silent" "$out"

mkdir -p "$H/.claude/skills/alpha" "$H/.agents/skills/beta" "$H/.claude/plugins/cache/gone"
echo x > "$H/.claude/skills/alpha/SKILL.md"
echo x > "$H/.agents/skills/beta/SKILL.md"
printf '{"plugins": {"tool@mkt": [{"installPath": "%s"}], "tool@other": []}}' "$H/plug" > "$H/.claude/plugins/installed_plugins.json"
out=$(run)
for want in "installed from mkt, other" "skills/alpha duplicates skill alpha" \
  "skills/beta duplicates skill beta from Codex plugin tool@mkt" "cache/gone belongs to no configured marketplace"; do
  case $out in *"$want"*) ok "reports: $want" ;; *) bad "reports: $want" "$out" ;; esac
done

echo '{broken' > "$H/.claude/plugins/installed_plugins.json"
rm "$BIN/codex"
if HOME="$H" PATH="/usr/bin:/bin" python3 "$CHECK" </dev/null >/dev/null 2>&1; then
  ok "broken registry and no codex never fail"
else
  bad "broken registry and no codex never fail" "non-zero exit"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
