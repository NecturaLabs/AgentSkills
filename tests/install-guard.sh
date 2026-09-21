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
  mkdir -p "$h/.claude" "$h/.agents" "$h/.codex"
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
  for root in .claude .agents; do
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

# 10. a clean install never creates or populates the compatibility root ($CODEX_HOME/skills):
#     it is report-only and is not written to on a fresh install.
H=$(new_home)
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
check "clean-install-no-codex-skills-dir" "no" "$([ -d "$H/.codex/skills" ] && echo yes || echo no)"
check "clean-install-no-codex-links" "0" "$(link_count "$H/.codex")"

# 11. a stale AgentSkills-owned link already sitting in the compatibility root and pointing at a
#     DIFFERENT AgentSkills checkout is refreshed to this checkout only with --force; an unrelated
#     foreign link sitting in that same root is left alone either way.
OTHER_PLUGIN_NAME=$(grep -m1 '"name"' "$REPO_ROOT/.claude-plugin/plugin.json" | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
mkdir -p "$SANDBOX/other-checkout/skills/testing" "$SANDBOX/other-checkout/.claude-plugin"
printf 'other checkout skill\n' > "$SANDBOX/other-checkout/skills/testing/SKILL.md"
printf '{"name": "%s"}\n' "$OTHER_PLUGIN_NAME" > "$SANDBOX/other-checkout/.claude-plugin/plugin.json"

H=$(new_home)
mkdir -p "$H/.codex/skills"
ln -s "$SANDBOX/other-checkout/skills/testing" "$H/.codex/skills/testing"
ln -s "$SANDBOX/unrelated/some-skill" "$H/.codex/skills/security-review"
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
check "codex-other-checkout-untouched-without-force" "$SANDBOX/other-checkout/skills/testing" "$(readlink -- "$H/.codex/skills/testing")"
check "codex-foreign-untouched-without-force" "$SANDBOX/unrelated/some-skill" "$(readlink -- "$H/.codex/skills/security-review")"
bash "$INSTALL" --prefix "$H" --force >/dev/null 2>&1
check "codex-other-checkout-refreshed-with-force" "$REPO_ROOT/skills/testing" "$(readlink -- "$H/.codex/skills/testing")"
check "codex-foreign-survives-force" "$SANDBOX/unrelated/some-skill" "$(readlink -- "$H/.codex/skills/security-review")"

# --- global policy bootstrap ---------------------------------------------------------------
# Installing skills and installing an operating policy are separate operations. These assert the
# second never happens by accident, and never destroys an instruction file that is already in force.

policy_snapshot() {
  # Every instruction file and backup under the sandbox home, with content, so any silent rewrite
  # shows up as a diff rather than as a passing test.
  find "$1" \( -name 'AGENTS.md' -o -name 'AGENTS.override.md' -o -name 'CLAUDE.md' \
    -o -name 'CLAUDE.local.md' -o -name '*.backup-*' \) -printf '%y %p ' -exec cat {} \; 2>/dev/null | sort
}
backup_count() { find "$1" -name '*.backup-*' 2>/dev/null | wc -l | tr -d ' '; }

# 12. an ordinary install writes no instruction file at all, even next to an existing one
H=$(new_home)
printf 'MY OWN GLOBAL POLICY\n' > "$H/.claude/CLAUDE.md"
snap=$(policy_snapshot "$H")
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
check "plain-install-touches-no-policy" "$snap" "$(policy_snapshot "$H")"
check "plain-install-creates-no-canonical" "no" "$([ -e "$H/.claude/AGENTS.md" ] && echo yes || echo no)"

# 13. --global-agents on a clean home produces the canonical file plus both adapters
H=$(new_home)
bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
check "bootstrap-canonical-is-regular-file" "yes" "$([ -f "$H/.claude/AGENTS.md" ] && [ ! -L "$H/.claude/AGENTS.md" ] && echo yes || echo no)"
check "bootstrap-canonical-matches-source" "" "$(diff -q "$REPO_ROOT/examples/global-agents.md" "$H/.claude/AGENTS.md" >/dev/null 2>&1 || echo differs)"
check "bootstrap-claude-adapter" "@AGENTS.md" "$(cat "$H/.claude/CLAUDE.md" 2>/dev/null)"
check "bootstrap-codex-adapter-is-link" "$H/.claude/AGENTS.md" "$(readlink -f -- "$H/.codex/AGENTS.md" 2>/dev/null)"
check "bootstrap-no-spurious-backups" "0" "$(backup_count "$H")"

# 14. re-running changes nothing and still creates no backup
snap=$(policy_snapshot "$H")
bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
check "bootstrap-idempotent" "$snap" "$(policy_snapshot "$H")"

# 15. --dry-run writes no policy file
H=$(new_home)
snap=$(policy_snapshot "$H")
bash "$INSTALL" --prefix "$H" --global-agents --dry-run >/dev/null 2>&1
check "bootstrap-dry-run-writes-nothing" "$snap" "$(policy_snapshot "$H")"
check "bootstrap-dry-run-no-canonical" "no" "$([ -e "$H/.claude/AGENTS.md" ] && echo yes || echo no)"

# 16. a CLAUDE.md carrying real policy is never rewritten without --replace-global, and an
#     existing canonical file and codex doc are left exactly as found
H=$(new_home)
printf 'MY REAL GLOBAL POLICY\nrule one\n' > "$H/.claude/CLAUDE.md"
printf 'MY EXISTING CANONICAL\n' > "$H/.claude/AGENTS.md"
printf 'MY EXISTING CODEX DOC\n' > "$H/.codex/AGENTS.md"
snap=$(policy_snapshot "$H")
bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
check "bootstrap-refuses-existing-policy" "$snap" "$(policy_snapshot "$H")"
check "bootstrap-refusal-makes-no-backup" "0" "$(backup_count "$H")"

# 17. with --replace-global each conflict is backed up first, and the backup holds the old content
bash "$INSTALL" --prefix "$H" --global-agents --replace-global >/dev/null 2>&1
check "replace-global-claude-adapter" "@AGENTS.md" "$(cat "$H/.claude/CLAUDE.md" 2>/dev/null)"
check "replace-global-canonical-replaced" "" "$(diff -q "$REPO_ROOT/examples/global-agents.md" "$H/.claude/AGENTS.md" >/dev/null 2>&1 || echo differs)"
check "replace-global-codex-relinked" "$H/.claude/AGENTS.md" "$(readlink -f -- "$H/.codex/AGENTS.md" 2>/dev/null)"
check "replace-global-backed-up-three" "3" "$(backup_count "$H")"
check "replace-global-backup-keeps-claude-policy" "MY REAL GLOBAL POLICY" "$(cat "$H"/.claude/CLAUDE.md.backup-* 2>/dev/null | head -1)"
check "replace-global-backup-keeps-canonical" "MY EXISTING CANONICAL" "$(cat "$H"/.claude/AGENTS.md.backup-* 2>/dev/null | head -1)"
check "replace-global-backup-keeps-codex-doc" "MY EXISTING CODEX DOC" "$(cat "$H"/.codex/AGENTS.md.backup-* 2>/dev/null | head -1)"

# 18. --replace-global is meaningless on its own and must be rejected before anything is written
H=$(new_home)
snap=$(policy_snapshot "$H")
bash "$INSTALL" --prefix "$H" --replace-global >/dev/null 2>&1
check "replace-global-alone-rejected" "2" "$?"
check "replace-global-alone-writes-nothing" "$snap" "$(policy_snapshot "$H")"

# 19. a custom source file is what lands, so a personalized policy can be installed instead
H=$(new_home)
printf 'PERSONALIZED POLICY\n' > "$H/mine.md"
bash "$INSTALL" --prefix "$H" --global-agents "$H/mine.md" >/dev/null 2>&1
check "bootstrap-custom-source" "PERSONALIZED POLICY" "$(cat "$H/.claude/AGENTS.md" 2>/dev/null)"

# 20. an AGENTS.override.md is reported but never removed -- doctor and install both leave it
printf 'override rules\n' > "$H/.codex/AGENTS.override.md"
bash "$INSTALL" --prefix "$H" --global-agents "$H/mine.md" >/dev/null 2>&1
check "override-survives-bootstrap" "override rules" "$(cat "$H/.codex/AGENTS.override.md" 2>/dev/null)"
doctor_out=$(bash "$DOCTOR" --prefix "$H" 2>&1)
check "doctor-reports-override-shadowing" "1" "$(printf '%s\n' "$doctor_out" | grep -c 'never read' || true)"

# 21. doctor detects a skill name resolving to different targets across the two Codex roots.
#     Both roots are live for some Codex versions, so a stale link in the compatibility root
#     shadowing the real one in .agents/skills is a genuine version-skew bug, not cosmetic.
H=$(new_home)
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
mkdir -p "$H/.codex/skills"
ln -s "$SANDBOX/other-checkout/skills/testing" "$H/.codex/skills/testing"
doctor_out=$(bash "$DOCTOR" --prefix "$H" 2>&1)
check "doctor-detects-cross-root-shadow" "1" "$(printf '%s\n' "$doctor_out" | grep -c 'resolves to different targets across roots' || true)"
check "doctor-shadow-is-an-error" "1" "$(printf '%s\n' "$doctor_out" | grep -c '\[error\].*testing resolves to different targets' || true)"
# ...and stays quiet when every root agrees.
rm -f "$H/.codex/skills/testing"
doctor_out=$(bash "$DOCTOR" --prefix "$H" 2>&1)
check "doctor-no-false-shadow" "1" "$(printf '%s\n' "$doctor_out" | grep -c 'no skill name resolves to conflicting targets' || true)"

# 22. a refused --global-agents run is all-or-nothing. The three destinations are one mechanism:
#      writing the adapters while refusing the canonical file would point both harnesses at a
#      policy the run explicitly declined to install. Each case below puts a conflict at exactly
#      one destination and leaves the other two absent, so a partial write cannot hide.
assert_nothing_written() {
  local label=$1 H=$2
  check "allornothing-$label-nothing-written" "$3" "$(policy_snapshot "$H")"
  check "allornothing-$label-no-backups" "0" "$(backup_count "$H")"
}

# 22a. conflict at the canonical file only
H=$(new_home)
printf 'THE USERS OWN PRIVATE POLICY\n' > "$H/.claude/AGENTS.md"
snap=$(policy_snapshot "$H")
bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
check "allornothing-canonical-exit" "1" "$?"
assert_nothing_written "canonical" "$H" "$snap"
check "allornothing-canonical-no-claude-adapter" "no" "$([ -e "$H/.claude/CLAUDE.md" ] && echo yes || echo no)"
check "allornothing-canonical-no-codex-adapter" "no" "$([ -e "$H/.codex/AGENTS.md" ] || [ -L "$H/.codex/AGENTS.md" ] && echo yes || echo no)"

# 22b. conflict at the Claude adapter only
H=$(new_home)
printf 'MY REAL GLOBAL POLICY\n' > "$H/.claude/CLAUDE.md"
snap=$(policy_snapshot "$H")
bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
check "allornothing-claude-exit" "1" "$?"
assert_nothing_written "claude" "$H" "$snap"
check "allornothing-claude-no-canonical" "no" "$([ -e "$H/.claude/AGENTS.md" ] && echo yes || echo no)"
check "allornothing-claude-no-codex-adapter" "no" "$([ -e "$H/.codex/AGENTS.md" ] || [ -L "$H/.codex/AGENTS.md" ] && echo yes || echo no)"

# 22c. conflict at the Codex adapter only
H=$(new_home)
printf 'MY EXISTING CODEX DOC\n' > "$H/.codex/AGENTS.md"
snap=$(policy_snapshot "$H")
bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
check "allornothing-codex-exit" "1" "$?"
assert_nothing_written "codex" "$H" "$snap"
check "allornothing-codex-no-canonical" "no" "$([ -e "$H/.claude/AGENTS.md" ] && echo yes || echo no)"
check "allornothing-codex-no-claude-adapter" "no" "$([ -e "$H/.claude/CLAUDE.md" ] && echo yes || echo no)"

# 22d. conflicts at all three: every one is reported, and still nothing is written
H=$(new_home)
printf 'A\n' > "$H/.claude/AGENTS.md"
printf 'B\n' > "$H/.claude/CLAUDE.md"
printf 'C\n' > "$H/.codex/AGENTS.md"
snap=$(policy_snapshot "$H")
out=$(bash "$INSTALL" --prefix "$H" --global-agents 2>&1)
assert_nothing_written "multi" "$H" "$snap"
check "allornothing-multi-reports-all-three" "3" "$(printf '%s\n' "$out" | grep -c 'already exists and differs\|carries its own content\|is not a link to')"

# 22e. the same conflicts under --replace-global are all applied, so the gate is not just refusing
bash "$INSTALL" --prefix "$H" --global-agents --replace-global >/dev/null 2>&1
check "allornothing-replace-applies-all" "3" "$(backup_count "$H")"
check "allornothing-replace-canonical" "" "$(diff -q "$REPO_ROOT/examples/global-agents.md" "$H/.claude/AGENTS.md" >/dev/null 2>&1 || echo differs)"

# 23. the Claude adapter is a shim only when its one non-blank line is the @AGENTS.md import.
#      CLAUDE.md is Markdown with no comment syntax, so a '# note' line is a heading the model
#      reads, and a second import pulls in policy the bootstrap does not control. Both are
#      content of their own, and because the run is all-or-nothing each must leave every
#      destination untouched.
shim_case() {
  local label=$1 body=$2 want_exit=$3 want_writes=$4 H before after writes
  H=$(new_home)
  printf '%b' "$body" > "$H/.claude/CLAUDE.md"
  before=$(policy_snapshot "$H")
  bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
  check "shim-$label-exit" "$want_exit" "$?"
  after=$(policy_snapshot "$H")
  writes=$([ "$before" = "$after" ] && echo no || echo yes)
  check "shim-$label-writes" "$want_writes" "$writes"
  if [ "$want_writes" = no ]; then
    check "shim-$label-no-canonical" "no" "$([ -e "$H/.claude/AGENTS.md" ] && echo yes || echo no)"
    check "shim-$label-no-codex-adapter" "no" "$([ -e "$H/.codex/AGENTS.md" ] || [ -L "$H/.codex/AGENTS.md" ] && echo yes || echo no)"
    check "shim-$label-no-backups" "0" "$(backup_count "$H")"
  fi
}
shim_case "import-only"      '@AGENTS.md\n'            "0" "yes"
shim_case "blank-lines"      '\n\n@AGENTS.md\n\n'      "0" "yes"
shim_case "markdown-heading" '# note\n@AGENTS.md\n'    "1" "no"
shim_case "second-import"    '@AGENTS.md\n@OTHER.md\n' "1" "no"
shim_case "foreign-import"   '@OTHER.md\n'             "1" "no"

# 24. the default bootstrapped policy must be usable before any customization: no unfilled
#     placeholder may survive as an active instruction, because an agent obeys what it says.
H=$(new_home)
bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
check "bootstrapped-policy-no-active-placeholders" "0" \
  "$(grep -cE '^[[:space:]]*[-*][^<]*<your ' "$H/.claude/AGENTS.md" 2>/dev/null || true)"

printf '\nGuard summary: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
