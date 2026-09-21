#!/usr/bin/env bash
# Asserts the safety properties of install.sh, uninstall.sh and doctor.sh.
#
# These three are the only scripts here that write into a real home directory, and the properties
# below are what stops them damaging one. Every case runs against a throwaway home built under
# mktemp -d and passed with --prefix, so nothing outside the sandbox is ever a candidate for
# writing. A regression in any single guarded branch -- the pre-delete symlink re-check, the
# real-directory refusal, the foreign-link refusal -- turns one of these red.
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=${SCRIPT_DIR%/*}
INSTALL=$REPO_ROOT/scripts/install.sh
UNINSTALL=$REPO_ROOT/scripts/uninstall.sh
DOCTOR=$REPO_ROOT/scripts/doctor.sh
SKILLS=(agent-instructions change-review security-review testing project-docs)

PASS=0
FAIL=0
SANDBOX=''

cleanup() {
  [ -n "$SANDBOX" ] || return 0
  find "$SANDBOX" -type l -delete 2>/dev/null
  find "$SANDBOX" -type f -delete 2>/dev/null
  find "$SANDBOX" -depth -type d -exec rmdir {} + 2>/dev/null
}
trap cleanup EXIT

ok()   { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL  %s -- %s\n' "$1" "$2"; }

check() {
  local name=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then ok "$name"; else bad "$name" "expected '$expected', got '$actual'"; fi
}

# A fresh home for every case, so no case can pass because of what a previous one left behind.
new_home() {
  local h
  h=$(mktemp -d "$SANDBOX/home.XXXXXX")
  mkdir -p "$h/.claude" "$h/.codex"
  printf '%s' "$h"
}

link_count() { find "$1" -type l 2>/dev/null | wc -l | tr -d ' '; }

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/agentskills-install-guard.XXXXXX")
mkdir -p "$SANDBOX/unrelated/some-skill"
printf 'not ours\n' > "$SANDBOX/unrelated/some-skill/SKILL.md"

printf '=== install-guard ===\n'

# 1. clean install links every skill into both scanned roots, and nowhere else
H=$(new_home)
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
check "clean-install-link-count" "10" "$(link_count "$H")"
missing=''
for s in "${SKILLS[@]}"; do
  for root in .claude .codex; do
    [ -L "$H/$root/skills/$s" ] || missing="$missing $root/$s"
    [ "$(readlink -f -- "$H/$root/skills/$s" 2>/dev/null)" = "$REPO_ROOT/skills/$s" ] || missing="$missing $root/$s(target)"
  done
done
check "clean-install-targets" "" "$missing"

# 2. re-running changes nothing
before=$(link_count "$H")
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
check "install-idempotent" "$before" "$(link_count "$H")"

# 3. a real directory is never replaced, with or without --force
H=$(new_home)
mkdir -p "$H/.claude/skills/testing"
printf 'user content\n' > "$H/.claude/skills/testing/SKILL.md"
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
check "realdir-survives-install" "user content" "$(cat "$H/.claude/skills/testing/SKILL.md" 2>/dev/null)"
bash "$INSTALL" --prefix "$H" --force >/dev/null 2>&1
check "realdir-survives-force" "user content" "$(cat "$H/.claude/skills/testing/SKILL.md" 2>/dev/null)"
check "realdir-still-a-dir" "yes" "$([ -d "$H/.claude/skills/testing" ] && [ ! -L "$H/.claude/skills/testing" ] && echo yes || echo no)"

# 4. a link pointing outside any AgentSkills checkout is never replaced, with or without --force
H=$(new_home)
mkdir -p "$H/.claude/skills"
ln -s "$SANDBOX/unrelated/some-skill" "$H/.claude/skills/testing"
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
check "foreign-link-survives-install" "$SANDBOX/unrelated/some-skill" "$(readlink -- "$H/.claude/skills/testing")"
bash "$INSTALL" --prefix "$H" --force >/dev/null 2>&1
check "foreign-link-survives-force" "$SANDBOX/unrelated/some-skill" "$(readlink -- "$H/.claude/skills/testing")"

# 5. a dangling managed link is refused without --force and repaired with it
H=$(new_home)
mkdir -p "$H/.claude/skills"
ln -s "$SANDBOX/gone/skills/testing" "$H/.claude/skills/testing"
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
check "dangling-untouched-without-force" "$SANDBOX/gone/skills/testing" "$(readlink -- "$H/.claude/skills/testing")"
bash "$INSTALL" --prefix "$H" --force >/dev/null 2>&1
check "dangling-repaired-with-force" "$REPO_ROOT/skills/testing" "$(readlink -- "$H/.claude/skills/testing")"

# 6. uninstall removes only this project's links
H=$(new_home)
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
ln -s "$SANDBOX/unrelated/some-skill" "$H/.claude/skills/unrelated-link"
mkdir -p "$H/.codex/skills/local-real-skill"
printf 'hand written\n' > "$H/.codex/skills/local-real-skill/SKILL.md"
bash "$UNINSTALL" --prefix "$H" >/dev/null 2>&1
check "uninstall-removes-ours" "0" "$(for s in "${SKILLS[@]}"; do [ -e "$H/.claude/skills/$s" ] && echo x; done | wc -l | tr -d ' ')"
check "uninstall-keeps-foreign-link" "yes" "$([ -L "$H/.claude/skills/unrelated-link" ] && echo yes || echo no)"
check "uninstall-keeps-real-dir" "hand written" "$(cat "$H/.codex/skills/local-real-skill/SKILL.md" 2>/dev/null)"
check "uninstall-keeps-roots" "yes" "$([ -d "$H/.claude/skills" ] && [ -d "$H/.codex/skills" ] && echo yes || echo no)"
check "uninstall-keeps-target-dir" "not ours" "$(cat "$SANDBOX/unrelated/some-skill/SKILL.md" 2>/dev/null)"

# 7. --dry-run writes nothing, on either script
H=$(new_home)
snap_before=$(find "$H" -printf '%y %p -> %l\n' 2>/dev/null | sort)
bash "$INSTALL" --prefix "$H" --dry-run >/dev/null 2>&1
check "install-dry-run-writes-nothing" "$snap_before" "$(find "$H" -printf '%y %p -> %l\n' 2>/dev/null | sort)"
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
snap_installed=$(find "$H" -printf '%y %p -> %l\n' 2>/dev/null | sort)
bash "$UNINSTALL" --prefix "$H" --dry-run >/dev/null 2>&1
check "uninstall-dry-run-writes-nothing" "$snap_installed" "$(find "$H" -printf '%y %p -> %l\n' 2>/dev/null | sort)"

# 8. doctor never writes, and reports a clean install as healthy
H=$(new_home)
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
snap=$(find "$H" -printf '%y %p -> %l\n' 2>/dev/null | sort)
doctor_out=$(bash "$DOCTOR" --prefix "$H" 2>&1)
check "doctor-writes-nothing" "$snap" "$(find "$H" -printf '%y %p -> %l\n' 2>/dev/null | sort)"
check "doctor-sees-install" "0" "$(printf '%s\n' "$doctor_out" | grep -c 'is not installed' || true)"

# 9. no recursive delete may ever appear in the three scripts
check "no-recursive-rm" "0" "$(grep -cE '\brm\b[^|]*-[a-zA-Z]*[rR]' "$INSTALL" "$UNINSTALL" "$DOCTOR" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')"

printf '\nGuard summary: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
