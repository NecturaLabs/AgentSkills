#!/usr/bin/env bash
# Asserts what setup/claude/scripts/memory-check.py promises: silence on a clean memory, one line per
# real problem otherwise, no complaint about paths from other repositories, and never a failure
# that could block a session from starting.
#
# Everything runs in a mktemp sandbox with a made-up project, transcript and memory directory, and a
# space in its path, as on the disk this setup comes from.
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=${SCRIPT_DIR%/*}
CHECK=$REPO_ROOT/setup/claude/scripts/memory-check.py

PASS=0
FAIL=0
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/agentskills memory-check.XXXXXX")
trap 'rm -rf -- "$SANDBOX"' EXIT

ok()  { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s -- %s\n' "$1" "$2"; }
check() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi
}

PROJECT="$SANDBOX/my project"
SESSIONS=$SANDBOX/claude/projects/my-project
MEM=$SESSIONS/memory
mkdir -p "$PROJECT/docs" "$PROJECT/src" "$MEM"
: > "$PROJECT/docs/guide.md"
: > "$SESSIONS/session.jsonl"

run() {
  printf '{"transcript_path":"%s","cwd":"%s"}' "$SESSIONS/session.jsonl" "$PROJECT" |
    python3 "$CHECK"
}

memory() { # name body
  printf -- '---\nname: %s\ndescription: x\nmetadata:\n  type: project\n---\n\n%s\n' "$1" "$2" > "$MEM/$1.md"
}

# 1. A clean memory prints nothing.
memory alpha 'See `docs/guide.md`, `other-repo/plugins/x.md` and [[beta]].'
memory beta 'Lives in `src/`.'
printf -- '- [Alpha](alpha.md) — a\n- [Beta](beta.md) — b\n' > "$MEM/MEMORY.md"
out=$(run 2>&1)
check "clean-is-silent" "" "$out"

# 2. Each kind of drift is reported once.
memory gamma 'Points at `docs/handoff.md`, at `~/no-such-agentskills-file.md` and at [[delta]].'
printf -- '- [Alpha](alpha.md) — a\n- [Beta](beta.md) — b\n- [Gone](gone.md) — g\n' > "$MEM/MEMORY.md"
out=$(run 2>&1)
check "reports-missing-index-file" 1 "$(grep -c 'MEMORY.md lists gone.md' <<< "$out")"
check "reports-unlisted-file" 1 "$(grep -c 'gamma.md is not listed' <<< "$out")"
check "reports-broken-link" 1 "$(grep -c 'links \[\[delta\]\]' <<< "$out")"
check "reports-missing-project-path" 1 "$(grep -c 'names docs/handoff.md' <<< "$out")"
check "reports-missing-home-path" 1 "$(grep -c 'no-such-agentskills-file.md' <<< "$out")"
check "ignores-other-repo-path" 0 "$(grep -c 'other-repo' <<< "$out")"
check "counts-issues" 1 "$(grep -c '^Memory check: 5 saved-memory issue' <<< "$out")"
check "points-at-skill" 1 "$(grep -c 'memory-hygiene' <<< "$out")"

# 3. Index and link forms a real memory uses are understood, not reported.
rm -f "$MEM"/*.md
memory alpha 'Branch `docs/new-thing` merged; see [[beta|the beta note]], [[beta#usage]] and [[Pretty Name]].'
printf -- '---\nname: Pretty Name\ndescription: x\n---\n\nbody\n' > "$MEM/pretty.md"
memory beta 'Lives in `src/`.'
cat > "$MEM/MEMORY.md" <<'IDX'
- [Alpha](alpha.md) — a
* [Beta](beta.md#usage) — b
1. [Pretty](./pretty.md) — p
- [Docs](https://example.com/guide.md) — external
IDX
out=$(run 2>&1)
check "real-forms-are-silent" "" "$out"

# 4. An entry that cannot be read is reported, and the rest is still checked.
mkdir "$MEM/broken.md"
printf -- '- [Broken](broken.md) — x\n' >> "$MEM/MEMORY.md"
memory gamma 'Points at `docs/gone.md`.'
printf -- '- [Gamma](gamma.md) — g\n' >> "$MEM/MEMORY.md"
out=$(run 2>&1); rc=$?
check "unreadable-reported" 1 "$(grep -c 'broken.md could not be read' <<< "$out")"
check "unreadable-rest-checked" 1 "$(grep -c 'names docs/gone.md' <<< "$out")"
check "unreadable-exit" 0 "$rc"
rmdir "$MEM/broken.md"

# 5. Past twelve findings the rest are counted, not listed.
for n in $(seq 1 15); do printf -- '- [G%s](gone-%s.md) — g\n' "$n" "$n" >> "$MEM/MEMORY.md"; done
out=$(run 2>&1)
check "truncation-line" 1 "$(grep -c '^- and [0-9]* more$' <<< "$out")"
check "truncation-cap" 13 "$(grep -c '^- ' <<< "$out")"

# 6. No memory directory, a missing transcript path or bad input: silent, and never a failure.
rm -rf "$MEM"
out=$(run 2>&1); rc=$?
check "no-memory-dir-silent" "" "$out"
check "no-memory-dir-exit" 0 "$rc"
out=$(printf 'not json' | python3 "$CHECK" 2>&1); rc=$?
check "bad-input-silent" "" "$out"
check "bad-input-exit" 0 "$rc"

printf '\nMemory-check summary: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
