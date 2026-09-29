#!/usr/bin/env bash
# Asserts what setup/claude/scripts/compact-resume.py promises: after a compaction it prints the
# session's checklist, the other scratchpad files and git status; it is silent for every other
# SessionStart source; it caps what it prints; and it never fails in a way that could block a
# session.
#
# Everything runs in a mktemp sandbox with a made-up scratchpad and repository, and a space in its
# path, as on the disk this setup comes from.
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=${SCRIPT_DIR%/*}
HOOK=$REPO_ROOT/setup/claude/scripts/compact-resume.py

PASS=0
FAIL=0
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/agentskills compact-resume.XXXXXX")
trap 'rm -rf -- "$SANDBOX"' EXIT

ok()  { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s -- %s\n' "$1" "$2"; }
check() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi
}

SID=0f3c9a1e-1111-2222-3333-444455556666
TMPROOT="$SANDBOX/tmp root"
PAD="$TMPROOT/claude-1000/-my-project/$SID/scratchpad"
PROJECT="$SANDBOX/my project"
mkdir -p "$PAD" "$PROJECT"
git -C "$PROJECT" init -q -b main
: > "$PROJECT/changed.txt"

run() { # source [session id]
  printf '{"session_id":"%s","cwd":"%s","source":"%s"}' "${2:-$SID}" "$PROJECT" "$1" |
    CLAUDE_CODE_TMPDIR="$TMPROOT" python3 "$HOOK"
}

# 1. Only a compaction speaks.
printf -- '- [x] step one\n- [ ] step two\nNext: step two\n' > "$PAD/checklist.md"
for src in startup resume clear; do
  out=$(run "$src" 2>&1)
  check "silent-on-$src" "" "$out"
done

# 2. After a compaction: the checklist in full, the other files by name, and git status.
printf 'findings\n' > "$PAD/research.md"
mkdir -p "$PAD/logs"; printf 'x\n' > "$PAD/logs/run.log"
out=$(run compact 2>&1); rc=$?
check "compact-exit" 0 "$rc"
check "prints-checklist-path" 1 "$(grep -cF "Session checklist ($PAD/checklist.md)" <<< "$out")"
check "prints-checklist-body" 1 "$(grep -c '^Next: step two$' <<< "$out")"
check "lists-other-files" 1 "$(grep -c '^Other files in the scratchpad: logs/run.log, research.md$' <<< "$out")"
check "checklist-not-listed-twice" 0 "$(grep -c 'scratchpad:.*checklist.md' <<< "$out")"
check "prints-git-branch" 1 "$(grep -c '^## ' <<< "$out")"
check "prints-git-change" 1 "$(grep -c '^?? changed.txt$' <<< "$out")"

# 3. A long checklist keeps its head (the task) and its tail (the next step), drops the middle.
python3 -c 'print("Task: the goal\n" + "y" * 9000 + "\nNext: the final step")' > "$PAD/checklist.md"
out=$(run compact 2>&1)
check "long-keeps-head" 1 "$(grep -c '^Task: the goal$' <<< "$out")"
check "long-keeps-next-step" 1 "$(grep -c '^Next: the final step$' <<< "$out")"
check "long-marks-omission" 1 "$(grep -c '^\[... [0-9]* of 9036 characters omitted here\]$' <<< "$out")"

# 4. A long checklist and a very dirty tree together stay under Claude Code's 10,000-character
#    hook-output cap, past which the context would get only a 2,000-character preview.
for n in $(seq 1 400); do : > "$PROJECT/a-rather-long-untracked-file-name-number-$n.txt"; done
out=$(run compact 2>&1)
check "output-under-cap" 1 "$([ "${#out}" -le 10000 ] && echo 1 || echo "${#out}")"
check "output-keeps-next-step" 1 "$(grep -c '^Next: the final step$' <<< "$out")"
check "git-overflow-counted" 1 "$(grep -c '^\[... and [0-9]* more\]$' <<< "$out")"
rm -f "$PROJECT"/a-rather-long-untracked-file-name-number-*.txt

# 5. Without CLAUDE_CODE_TMPDIR the scratchpad is looked for under the system temp dir.
out=$(printf '{"session_id":"%s","cwd":"%s","source":"compact"}' "$SID" "$PROJECT" |
  env -u CLAUDE_CODE_TMPDIR TMPDIR="$TMPROOT" python3 "$HOOK" 2>&1)
check "system-temp-fallback" 1 "$(grep -c '^Next: the final step$' <<< "$out")"

# 6. No checklist, or no scratchpad at all, is stated rather than silent.
rm "$PAD/checklist.md"
out=$(run compact 2>&1)
check "missing-checklist-stated" 1 "$(grep -c '^No checklist.md in this session' <<< "$out")"
out=$(run compact 11111111-aaaa-bbbb-cccc-000000000000 2>&1)
check "missing-scratchpad-stated" 1 "$(grep -c '^No scratchpad found' <<< "$out")"

# 7. A session id that could escape the glob is not searched.
out=$(run compact '../*' 2>&1)
check "odd-session-id-not-searched" 1 "$(grep -c '^No scratchpad found' <<< "$out")"

# 8. Outside a repository there is no git section, and bad input is silent; never a failure.
out=$(printf '{"session_id":"%s","cwd":"%s","source":"compact"}' "$SID" "$SANDBOX" |
  CLAUDE_CODE_TMPDIR="$TMPROOT" python3 "$HOOK" 2>&1); rc=$?
check "no-repo-no-git" 0 "$(grep -c '^git status' <<< "$out")"
check "no-repo-exit" 0 "$rc"
out=$(printf 'not json' | python3 "$HOOK" 2>&1); rc=$?
check "bad-input-silent" "" "$out"
check "bad-input-exit" 0 "$rc"

printf '\nCompact-resume summary: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
