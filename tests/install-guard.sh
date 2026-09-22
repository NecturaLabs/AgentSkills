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
SKILLS=(agent-instructions agent-orchestration independent-review threat-review testing project-docs)

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
check "clean-install-link-count" "$(( ${#SKILLS[@]} * 2 ))" "$(link_count "$H")"
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
ln -s "$SANDBOX/unrelated/some-skill" "$H/.codex/skills/threat-review"
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
check "codex-other-checkout-untouched-without-force" "$SANDBOX/other-checkout/skills/testing" "$(readlink -- "$H/.codex/skills/testing")"
check "codex-foreign-untouched-without-force" "$SANDBOX/unrelated/some-skill" "$(readlink -- "$H/.codex/skills/threat-review")"
bash "$INSTALL" --prefix "$H" --force >/dev/null 2>&1
check "codex-other-checkout-refreshed-with-force" "$REPO_ROOT/skills/testing" "$(readlink -- "$H/.codex/skills/testing")"
check "codex-foreign-survives-force" "$SANDBOX/unrelated/some-skill" "$(readlink -- "$H/.codex/skills/threat-review")"

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
check "plain-install-creates-no-canonical" "no" "$([ -e "$H/.agents/AGENTS.md" ] && echo yes || echo no)"

# 13. --global-agents on a clean home produces the canonical file plus both adapters
H=$(new_home)
bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
check "bootstrap-canonical-is-regular-file" "yes" "$([ -f "$H/.agents/AGENTS.md" ] && [ ! -L "$H/.agents/AGENTS.md" ] && echo yes || echo no)"
check "bootstrap-canonical-matches-source" "" "$(diff -q "$REPO_ROOT/examples/global-agents.md" "$H/.agents/AGENTS.md" >/dev/null 2>&1 || echo differs)"
check "bootstrap-claude-adapter" "@$H/.agents/AGENTS.md" "$(cat "$H/.claude/CLAUDE.md" 2>/dev/null)"
check "bootstrap-codex-adapter-is-link" "$H/.agents/AGENTS.md" "$(readlink -f -- "$H/.codex/AGENTS.md" 2>/dev/null)"
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
check "bootstrap-dry-run-no-canonical" "no" "$([ -e "$H/.agents/AGENTS.md" ] && echo yes || echo no)"

# 16. a CLAUDE.md carrying real policy is never rewritten without --replace-global, and an
#     existing canonical file and codex doc are left exactly as found
H=$(new_home)
printf 'MY REAL GLOBAL POLICY\nrule one\n' > "$H/.claude/CLAUDE.md"
printf 'MY EXISTING CANONICAL\n' > "$H/.agents/AGENTS.md"
printf 'MY EXISTING CODEX DOC\n' > "$H/.codex/AGENTS.md"
snap=$(policy_snapshot "$H")
bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
check "bootstrap-refuses-existing-policy" "$snap" "$(policy_snapshot "$H")"
check "bootstrap-refusal-makes-no-backup" "0" "$(backup_count "$H")"

# 17. with --replace-global each conflict is backed up first, and the backup holds the old content
bash "$INSTALL" --prefix "$H" --global-agents --replace-global >/dev/null 2>&1
check "replace-global-claude-adapter" "@$H/.agents/AGENTS.md" "$(cat "$H/.claude/CLAUDE.md" 2>/dev/null)"
check "replace-global-canonical-replaced" "" "$(diff -q "$REPO_ROOT/examples/global-agents.md" "$H/.agents/AGENTS.md" >/dev/null 2>&1 || echo differs)"
check "replace-global-codex-relinked" "$H/.agents/AGENTS.md" "$(readlink -f -- "$H/.codex/AGENTS.md" 2>/dev/null)"
check "replace-global-backed-up-three" "3" "$(backup_count "$H")"
check "replace-global-backup-keeps-claude-policy" "MY REAL GLOBAL POLICY" "$(cat "$H"/.claude/CLAUDE.md.backup-* 2>/dev/null | head -1)"
check "replace-global-backup-keeps-canonical" "MY EXISTING CANONICAL" "$(cat "$H"/.agents/AGENTS.md.backup-* 2>/dev/null | head -1)"
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
check "bootstrap-custom-source" "PERSONALIZED POLICY" "$(cat "$H/.agents/AGENTS.md" 2>/dev/null)"

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
printf 'THE USERS OWN PRIVATE POLICY\n' > "$H/.agents/AGENTS.md"
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
check "allornothing-claude-no-canonical" "no" "$([ -e "$H/.agents/AGENTS.md" ] && echo yes || echo no)"
check "allornothing-claude-no-codex-adapter" "no" "$([ -e "$H/.codex/AGENTS.md" ] || [ -L "$H/.codex/AGENTS.md" ] && echo yes || echo no)"

# 22c. conflict at the Codex adapter only
H=$(new_home)
printf 'MY EXISTING CODEX DOC\n' > "$H/.codex/AGENTS.md"
snap=$(policy_snapshot "$H")
bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
check "allornothing-codex-exit" "1" "$?"
assert_nothing_written "codex" "$H" "$snap"
check "allornothing-codex-no-canonical" "no" "$([ -e "$H/.agents/AGENTS.md" ] && echo yes || echo no)"
check "allornothing-codex-no-claude-adapter" "no" "$([ -e "$H/.claude/CLAUDE.md" ] && echo yes || echo no)"

# 22d. conflicts at all three: every one is reported, and still nothing is written
H=$(new_home)
printf 'A\n' > "$H/.agents/AGENTS.md"
printf 'B\n' > "$H/.claude/CLAUDE.md"
printf 'C\n' > "$H/.codex/AGENTS.md"
snap=$(policy_snapshot "$H")
out=$(bash "$INSTALL" --prefix "$H" --global-agents 2>&1)
assert_nothing_written "multi" "$H" "$snap"
check "allornothing-multi-reports-all-three" "3" "$(printf '%s\n' "$out" | grep -c 'already exists and differs\|does not hold exactly\|is not a link to')"

# 22e. the same conflicts under --replace-global are all applied, so the gate is not just refusing
bash "$INSTALL" --prefix "$H" --global-agents --replace-global >/dev/null 2>&1
check "allornothing-replace-applies-all" "3" "$(backup_count "$H")"
check "allornothing-replace-canonical" "" "$(diff -q "$REPO_ROOT/examples/global-agents.md" "$H/.agents/AGENTS.md" >/dev/null 2>&1 || echo differs)"

# 23. the Claude adapter is a shim only when its one non-blank line is the @AGENTS.md import.
#      CLAUDE.md is Markdown with no comment syntax, so a '# note' line is a heading the model
#      reads, and a second import pulls in policy the bootstrap does not control. Both are
#      content of their own, and because the run is all-or-nothing each must leave every
#      destination untouched.
# $2 is the adapter body, with the token %%IMPORT%% standing in for the neutral import this
# sandbox expects -- the call sites cannot name it, because it contains the sandbox's own path.
shim_case() {
  local label=$1 body=$2 want_exit=$3 want_writes=$4 H before after writes
  H=$(new_home)
  body=${body//%%IMPORT%%/@$H/.agents/AGENTS.md}
  printf '%b' "$body" > "$H/.claude/CLAUDE.md"
  before=$(policy_snapshot "$H")
  bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
  check "shim-$label-exit" "$want_exit" "$?"
  after=$(policy_snapshot "$H")
  writes=$([ "$before" = "$after" ] && echo no || echo yes)
  check "shim-$label-writes" "$want_writes" "$writes"
  if [ "$want_writes" = no ]; then
    check "shim-$label-no-canonical" "no" "$([ -e "$H/.agents/AGENTS.md" ] && echo yes || echo no)"
    check "shim-$label-no-codex-adapter" "no" "$([ -e "$H/.codex/AGENTS.md" ] || [ -L "$H/.codex/AGENTS.md" ] && echo yes || echo no)"
    check "shim-$label-no-backups" "0" "$(backup_count "$H")"
  fi
}
shim_case "import-only"        '%%IMPORT%%\n'            "0" "yes"
shim_case "blank-lines"        '\n\n%%IMPORT%%\n\n'      "0" "yes"
shim_case "markdown-heading"   '# note\n%%IMPORT%%\n'    "1" "no"
shim_case "second-import"      '%%IMPORT%%\n@OTHER.md\n' "1" "no"
shim_case "foreign-import"     '@OTHER.md\n'             "1" "no"
# the pre-release adapter imported @AGENTS.md, pointing back into Claude's own directory
shim_case "pre-release-import" '@AGENTS.md\n'            "1" "no"

# 24. the default bootstrapped policy must be usable before any customization: no unfilled
#     placeholder may survive as an active instruction, because an agent obeys what it says.
H=$(new_home)
bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
check "bootstrapped-policy-no-active-placeholders" "0" \
  "$(grep -cE '^[[:space:]]*[-*][^<]*<your ' "$H/.agents/AGENTS.md" 2>/dev/null || true)"

# 25. the two Claude destinations must be regular files, never symlinks, even when the bytes
#      behind the link are exactly what we would have written. The canonical policy is copied
#      rather than linked precisely so nothing outside the user's own file can change their live
#      instructions later; accepting a link into a checkout hands that control back to `git pull`.
#      `-f` follows symlinks, so this is the case a contents comparison alone cannot catch.
entry_type() { find "$1" -maxdepth 0 -printf '%y' 2>/dev/null || printf 'none'; }
# A byte-for-byte copy taken before the run, kept in the sandbox, is what proves the checkout was
# never written to. Asking git instead would conflate the two things it cannot tell apart: an
# installer that rewrote the file, and an ordinary uncommitted edit made before the suite started.
snapshot_file() {
  local dst
  dst=$(mktemp "$SANDBOX/snapshot.XXXXXX")
  cp -- "$1" "$dst"
  printf '%s' "$dst"
}
same_bytes() { cmp -s -- "$1" "$2" && printf 'identical' || printf 'differs'; }

H=$(new_home)
source_snap=$(snapshot_file "$REPO_ROOT/examples/global-agents.md")
ln -s "$REPO_ROOT/examples/global-agents.md" "$H/.agents/AGENTS.md"
printf '@AGENTS.md\n' > "$H/shim-target.md"
ln -s "$H/shim-target.md" "$H/.claude/CLAUDE.md"
snap=$(policy_snapshot "$H")
out=$(bash "$INSTALL" --prefix "$H" --global-agents 2>&1)
check "symlink-canonical-exit" "1" "$?"
check "symlink-canonical-still-a-link" "l" "$(entry_type "$H/.agents/AGENTS.md")"
check "symlink-shim-still-a-link" "l" "$(entry_type "$H/.claude/CLAUDE.md")"
check "symlink-nothing-written" "$snap" "$(policy_snapshot "$H")"
check "symlink-no-codex-adapter" "no" "$([ -e "$H/.codex/AGENTS.md" ] || [ -L "$H/.codex/AGENTS.md" ] && echo yes || echo no)"
check "symlink-no-backups" "0" "$(backup_count "$H")"
# install.sh runs doctor afterwards, and doctor reports the same two states, so count only
# within install's own Global policy section.
check "symlink-both-reported" "2" "$(printf '%s\n' "$out" | sed -n '/^Global policy/,/^Running doctor/p' | grep -c 'is a symlink ->')"
# doctor must report both states rather than following the links and calling them healthy
doctor_out=$(bash "$DOCTOR" --prefix "$H" 2>&1)
check "symlink-doctor-reports-both" "2" "$(printf '%s\n' "$doctor_out" | grep -c 'is a symlink ->.*must be a regular file')"
check "symlink-doctor-not-ok" "0" "$(printf '%s\n' "$doctor_out" | grep -c 'canonical global policy: ')"

# 25b. --replace-global turns both into regular files and keeps the old symlinks as backups
bash "$INSTALL" --prefix "$H" --global-agents --replace-global >/dev/null 2>&1
check "symlink-replaced-canonical-is-regular" "f" "$(entry_type "$H/.agents/AGENTS.md")"
check "symlink-replaced-shim-is-regular" "f" "$(entry_type "$H/.claude/CLAUDE.md")"
check "symlink-replaced-shim-content" "@$H/.agents/AGENTS.md" "$(cat "$H/.claude/CLAUDE.md" 2>/dev/null)"
check "symlink-replaced-canonical-matches" "" "$(diff -q "$REPO_ROOT/examples/global-agents.md" "$H/.agents/AGENTS.md" >/dev/null 2>&1 || echo differs)"
check "symlink-backup-canonical-kept-as-link" "l" "$(entry_type "$H"/.agents/AGENTS.md.backup-*)"
check "symlink-backup-shim-kept-as-link" "l" "$(entry_type "$H"/.claude/CLAUDE.md.backup-*)"
check "symlink-backup-canonical-target" "$REPO_ROOT/examples/global-agents.md" "$(readlink "$H"/.agents/AGENTS.md.backup-* 2>/dev/null)"
# the checkout the old link pointed into must be untouched by any of this
check "symlink-source-untouched" "identical" \
  "$(same_bytes "$source_snap" "$REPO_ROOT/examples/global-agents.md")"
# ...and that comparison is only worth having if it can fail. A stand-in copy plays the part of
# the checkout, so the failing half is exercised without ever writing into the real one.
decoy=$(mktemp "$SANDBOX/decoy-source.XXXXXX")
cp -- "$REPO_ROOT/examples/global-agents.md" "$decoy"
decoy_snap=$(snapshot_file "$decoy")
printf 'rewritten behind the symlink\n' >> "$decoy"
check "symlink-source-guard-detects-a-rewrite" "differs" "$(same_bytes "$decoy_snap" "$decoy")"
# and the one legitimate symlink in the layout is still the Codex adapter
check "symlink-codex-adapter-is-link" "l" "$(entry_type "$H/.codex/AGENTS.md")"

# 26. the canonical policy lives in neither harness's directory. A clean bootstrap must not
#      create the pre-release path at all, and both adapters must point at the neutral file.
H=$(new_home)
bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
check "neutral-canonical-is-regular" "f" "$(entry_type "$H/.agents/AGENTS.md")"
check "neutral-no-claude-canonical" "no" "$([ -e "$H/.claude/AGENTS.md" ] || [ -L "$H/.claude/AGENTS.md" ] && echo yes || echo no)"
check "neutral-claude-adapter-import" "@$H/.agents/AGENTS.md" "$(cat "$H/.claude/CLAUDE.md" 2>/dev/null)"
check "neutral-codex-resolves-to-canonical" "$H/.agents/AGENTS.md" "$(readlink -f -- "$H/.codex/AGENTS.md" 2>/dev/null)"
doctor_out=$(bash "$DOCTOR" --prefix "$H" 2>&1)
check "neutral-doctor-healthy" "0" "$(printf '%s\n' "$doctor_out" | grep -c '\[warn\].*\(canonical policy\|adapter\|pre-release\)')"
check "neutral-doctor-names-canonical" "1" "$(printf '%s\n' "$doctor_out" | grep -c "canonical global policy: $H/.agents/AGENTS.md")"

# 26b. doctor reports a wrong adapter import and a Codex adapter still aimed at the old path
printf '@~/somewhere-else.md\n' > "$H/.claude/CLAUDE.md"
check "doctor-detects-wrong-import" "1" "$(bash "$DOCTOR" --prefix "$H" 2>&1 | grep -c "imports '@~/somewhere-else.md'")"
printf 'OLD\n' > "$H/.claude/AGENTS.md"
rm -f "$H/.codex/AGENTS.md"
ln -s "$H/.claude/AGENTS.md" "$H/.codex/AGENTS.md"
check "doctor-detects-legacy-codex-target" "1" "$(bash "$DOCTOR" --prefix "$H" 2>&1 | grep -c 'the pre-release canonical path')"

# 27. migrating the pre-release layout. The user's policy must end up at the neutral path with
#      its bytes intact, the old file must be preserved as a backup rather than deleted, and an
#      ordinary run must refuse to do any of it.
make_legacy_home() {
  local h
  h=$(new_home)
  printf 'MY REAL PRE-RELEASE POLICY\nrule one\n' > "$h/.claude/AGENTS.md"
  printf '@AGENTS.md\n' > "$h/.claude/CLAUDE.md"
  ln -s "$h/.claude/AGENTS.md" "$h/.codex/AGENTS.md"
  printf '%s' "$h"
}

# 27a. doctor names it as the pre-release layout needing migration, and changes nothing
H=$(make_legacy_home)
snap=$(policy_snapshot "$H")
doctor_out=$(bash "$DOCTOR" --prefix "$H" 2>&1)
check "legacy-doctor-reports-migration" "1" "$(printf '%s\n' "$doctor_out" | grep -c 'holds the pre-release canonical policy')"
check "legacy-doctor-reports-old-adapter" "1" "$(printf '%s\n' "$doctor_out" | grep -c "pre-release adapter importing '@AGENTS.md'")"
check "legacy-doctor-writes-nothing" "$snap" "$(policy_snapshot "$H")"

# 27b. an ordinary --global-agents run refuses the whole thing and writes nothing
bash "$INSTALL" --prefix "$H" --global-agents >/dev/null 2>&1
check "legacy-refused-exit" "1" "$?"
check "legacy-refused-writes-nothing" "$snap" "$(policy_snapshot "$H")"
check "legacy-refused-no-neutral-canonical" "no" "$([ -e "$H/.agents/AGENTS.md" ] && echo yes || echo no)"

# 27c. --replace-global migrates: the policy moves to the neutral path with its bytes intact,
#      the adapter is rewritten, Codex is relinked, and the old file survives as a backup
bash "$INSTALL" --prefix "$H" --global-agents --replace-global >/dev/null 2>&1
check "legacy-migrated-exit" "0" "$?"
check "legacy-migrated-canonical-is-regular" "f" "$(entry_type "$H/.agents/AGENTS.md")"
check "legacy-migrated-policy-bytes-kept" "MY REAL PRE-RELEASE POLICY" "$(head -1 "$H/.agents/AGENTS.md" 2>/dev/null)"
check "legacy-migrated-not-the-example" "differs" "$(diff -q "$REPO_ROOT/examples/global-agents.md" "$H/.agents/AGENTS.md" >/dev/null 2>&1 && echo same || echo differs)"
check "legacy-migrated-adapter" "@$H/.agents/AGENTS.md" "$(cat "$H/.claude/CLAUDE.md" 2>/dev/null)"
check "legacy-migrated-codex-relinked" "$H/.agents/AGENTS.md" "$(readlink -f -- "$H/.codex/AGENTS.md" 2>/dev/null)"
check "legacy-migrated-old-path-retired" "no" "$([ -e "$H/.claude/AGENTS.md" ] || [ -L "$H/.claude/AGENTS.md" ] && echo yes || echo no)"
check "legacy-migrated-old-policy-backed-up" "MY REAL PRE-RELEASE POLICY" "$(head -1 "$H"/.claude/AGENTS.md.backup-* 2>/dev/null)"
check "legacy-migrated-old-adapter-backed-up" "@AGENTS.md" "$(cat "$H"/.claude/CLAUDE.md.backup-* 2>/dev/null)"
check "legacy-migrated-doctor-clean" "0" "$(bash "$DOCTOR" --prefix "$H" 2>&1 | grep -c 'pre-release')"

# 27d. naming a source explicitly still wins over carrying the pre-release policy over
H=$(make_legacy_home)
printf 'AN EXPLICIT CHOICE\n' > "$H/chosen.md"
bash "$INSTALL" --prefix "$H" --global-agents "$H/chosen.md" --replace-global >/dev/null 2>&1
check "legacy-explicit-source-wins" "AN EXPLICIT CHOICE" "$(cat "$H/.agents/AGENTS.md" 2>/dev/null)"
check "legacy-explicit-source-still-backs-up" "MY REAL PRE-RELEASE POLICY" "$(head -1 "$H"/.claude/AGENTS.md.backup-* 2>/dev/null)"

# 28. backup feasibility is preflighted, not discovered mid-write. Backups are named from one
#      timestamp fixed at the start of the run, so every path the run needs is knowable before
#      the first write; finding a taken one halfway through would leave the policy half
#      migrated -- canonical replaced, adapter not, the two harnesses on different rules.
occupy_backup_slots() {
  # The run's timestamp is whatever second it starts in, so occupy a few to make the collision
  # deterministic rather than a race with the clock.
  local target=$1 off
  for off in 0 1 2 3 4; do
    printf 'pre-existing backup\n' > "$target.backup-$(date -u -d "+$off seconds" +%Y%m%dT%H%M%SZ)"
  done
}

# 28a. a collision at the SECOND destination must stop the first from being touched
H=$(new_home)
printf 'MY CANONICAL\n' > "$H/.agents/AGENTS.md"
printf 'MY REAL CLAUDE POLICY\n' > "$H/.claude/CLAUDE.md"
occupy_backup_slots "$H/.claude/CLAUDE.md"
out=$(bash "$INSTALL" --prefix "$H" --global-agents --replace-global 2>&1)
check "backupclash-exit" "1" "$?"
check "backupclash-canonical-untouched" "MY CANONICAL" "$(cat "$H/.agents/AGENTS.md" 2>/dev/null)"
check "backupclash-adapter-untouched" "MY REAL CLAUDE POLICY" "$(cat "$H/.claude/CLAUDE.md" 2>/dev/null)"
check "backupclash-no-codex-adapter" "no" "$([ -e "$H/.codex/AGENTS.md" ] || [ -L "$H/.codex/AGENTS.md" ] && echo yes || echo no)"
check "backupclash-reported" "1" "$(printf '%s\n' "$out" | grep -c "cannot be backed up under this run's timestamp")"
# the occupied backups are someone else's files and must survive untouched
check "backupclash-existing-backups-intact" "pre-existing backup" "$(cat "$H"/.claude/CLAUDE.md.backup-* 2>/dev/null | sort -u)"

# 28b. the same during a pre-release migration
H=$(make_legacy_home)
occupy_backup_slots "$H/.claude/AGENTS.md"
bash "$INSTALL" --prefix "$H" --global-agents --replace-global >/dev/null 2>&1
check "backupclash-migration-exit" "1" "$?"
check "backupclash-migration-policy-intact" "MY REAL PRE-RELEASE POLICY" "$(head -1 "$H/.claude/AGENTS.md" 2>/dev/null)"
check "backupclash-migration-adapter-intact" "@AGENTS.md" "$(cat "$H/.claude/CLAUDE.md" 2>/dev/null)"
check "backupclash-migration-no-neutral" "no" "$([ -e "$H/.agents/AGENTS.md" ] && echo yes || echo no)"

# 28c. when every backup path is free, --replace-global still does the whole job, and every
#      backup shares the one timestamp the run fixed at the start
H=$(new_home)
printf 'OLD CANON\n' > "$H/.agents/AGENTS.md"
printf 'OLD ADAPTER\n' > "$H/.claude/CLAUDE.md"
printf 'OLD CODEX\n' > "$H/.codex/AGENTS.md"
bash "$INSTALL" --prefix "$H" --global-agents --replace-global >/dev/null 2>&1
check "backupfree-exit" "0" "$?"
check "backupfree-canonical-replaced" "" "$(diff -q "$REPO_ROOT/examples/global-agents.md" "$H/.agents/AGENTS.md" >/dev/null 2>&1 || echo differs)"
check "backupfree-adapter" "@$H/.agents/AGENTS.md" "$(cat "$H/.claude/CLAUDE.md" 2>/dev/null)"
check "backupfree-three-backups" "3" "$(backup_count "$H")"
check "backupfree-one-timestamp" "1" "$(find "$H" -name '*.backup-*' -printf '%f\n' | sed 's/.*backup-//' | sort -u | wc -l | tr -d ' ')"

# 29. a directory or other special object at any destination is never moved, even with
#      --replace-global: renaming one is not the same operation as replacing a file, and nothing
#      here knows what it holds.
for tgt in .agents/AGENTS.md .claude/CLAUDE.md .claude/AGENTS.md .codex/AGENTS.md; do
  H=$(new_home)
  mkdir -p "$H/$tgt"
  printf 'someone else\n' > "$H/$tgt/keep.txt"
  out=$(bash "$INSTALL" --prefix "$H" --global-agents --replace-global 2>&1)
  rc=$?
  label=${tgt//\//-}
  check "dirblock-$label-exit" "1" "$rc"
  check "dirblock-$label-still-a-dir" "yes" "$([ -d "$H/$tgt" ] && [ ! -L "$H/$tgt" ] && echo yes || echo no)"
  check "dirblock-$label-contents-kept" "someone else" "$(cat "$H/$tgt/keep.txt" 2>/dev/null)"
  check "dirblock-$label-reported" "1" "$(printf '%s\n' "$out" | grep -c 'directory or other special object')"
  check "dirblock-$label-no-backup" "0" "$(backup_count "$H")"
done

# 29. upgrading from the names earlier releases installed. A link under a retired name that
#     resolves into an AgentSkills checkout is ours and is retired; anything else under that name
#     belongs to someone else and survives.
tree_snapshot() { find "$1" -printf '%y %p -> %l\n' 2>/dev/null | sort; }
H=$(new_home)
mkdir -p "$H/.claude/skills" "$H/.agents/skills"
ln -s "$REPO_ROOT/skills/change-review" "$H/.claude/skills/change-review"
ln -s "$REPO_ROOT/skills/security-review" "$H/.agents/skills/security-review"
ln -s "$SANDBOX/unrelated/some-skill" "$H/.claude/skills/security-review"
mkdir -p "$H/.agents/skills/change-review"
printf 'hand written\n' > "$H/.agents/skills/change-review/SKILL.md"
doctor_out=$(bash "$DOCTOR" --prefix "$H" 2>&1)
check "retired-doctor-reports-ours" "2" "$(printf '%s\n' "$doctor_out" | grep -c '\[error\].*renamed to')"
snap=$(tree_snapshot "$H")
bash "$INSTALL" --prefix "$H" --dry-run >/dev/null 2>&1
check "retired-dry-run-writes-nothing" "$snap" "$(tree_snapshot "$H")"
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
check "retired-claude-link-removed" "no" "$([ -e "$H/.claude/skills/change-review" ] || [ -L "$H/.claude/skills/change-review" ] && echo yes || echo no)"
check "retired-agents-link-removed" "no" "$([ -e "$H/.agents/skills/security-review" ] || [ -L "$H/.agents/skills/security-review" ] && echo yes || echo no)"
check "retired-foreign-link-survives" "$SANDBOX/unrelated/some-skill" "$(readlink -- "$H/.claude/skills/security-review")"
check "retired-real-dir-survives" "hand written" "$(cat "$H/.agents/skills/change-review/SKILL.md" 2>/dev/null)"
missing=''
for s in independent-review threat-review; do
  for root in .claude .agents; do
    [ "$(readlink -f -- "$H/$root/skills/$s" 2>/dev/null)" = "$REPO_ROOT/skills/$s" ] || missing="$missing $root/$s"
  done
done
check "retired-new-names-installed" "" "$missing"
doctor_out=$(bash "$DOCTOR" --prefix "$H" 2>&1)
check "retired-doctor-clean-after-install" "0" "$(printf '%s\n' "$doctor_out" | grep -c '\[error\].*renamed to')"

# 29b. an old-name link into a different checkout that still carries the old skill is that
#      checkout's live install: it needs --force, like repointing, and its target is never touched
mkdir -p "$SANDBOX/old-checkout/skills/change-review" "$SANDBOX/old-checkout/.claude-plugin"
printf 'old release\n' > "$SANDBOX/old-checkout/skills/change-review/SKILL.md"
printf '{"name": "%s"}\n' "$OTHER_PLUGIN_NAME" > "$SANDBOX/old-checkout/.claude-plugin/plugin.json"
H=$(new_home)
mkdir -p "$H/.claude/skills"
ln -s "$SANDBOX/old-checkout/skills/change-review" "$H/.claude/skills/change-review"
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
check "retired-other-checkout-exit" "1" "$?"
check "retired-other-checkout-kept-without-force" "$SANDBOX/old-checkout/skills/change-review" "$(readlink -- "$H/.claude/skills/change-review")"
bash "$INSTALL" --prefix "$H" --force >/dev/null 2>&1
check "retired-other-checkout-removed-with-force" "no" "$([ -L "$H/.claude/skills/change-review" ] && echo yes || echo no)"
check "retired-other-checkout-target-intact" "old release" "$(cat "$SANDBOX/old-checkout/skills/change-review/SKILL.md" 2>/dev/null)"

# 29c. uninstall treats retired names as this project's own
H=$(new_home)
mkdir -p "$H/.claude/skills"
ln -s "$REPO_ROOT/skills/change-review" "$H/.claude/skills/change-review"
ln -s "$SANDBOX/unrelated/some-skill" "$H/.claude/skills/security-review"
bash "$UNINSTALL" --prefix "$H" >/dev/null 2>&1
check "uninstall-removes-retired-link" "no" "$([ -L "$H/.claude/skills/change-review" ] && echo yes || echo no)"
check "uninstall-keeps-foreign-retired-name" "$SANDBOX/unrelated/some-skill" "$(readlink -- "$H/.claude/skills/security-review")"

# 30. doctor reads Codex's system skills live and reports one sharing a name with ours; a clean
#     home reports no collision
H=$(new_home)
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
doctor_out=$(bash "$DOCTOR" --prefix "$H" 2>&1)
check "native-doctor-clean" "1" "$(printf '%s\n' "$doctor_out" | grep -c 'no skill of this plugin reuses a harness-native name')"
mkdir -p "$H/.codex/skills/.system/testing" "$H/.codex/skills/.system/imagegen"
printf -- '---\nname: "testing"\ndescription: x\n---\n' > "$H/.codex/skills/.system/testing/SKILL.md"
printf -- '---\nname: imagegen\ndescription: x\n---\n' > "$H/.codex/skills/.system/imagegen/SKILL.md"
doctor_out=$(bash "$DOCTOR" --prefix "$H" 2>&1)
check "native-doctor-detects-codex-system" "1" "$(printf '%s\n' "$doctor_out" | grep -c '\[error\] testing is also a Codex system skill')"
check "native-doctor-counts-codex-system" "1" "$(printf '%s\n' "$doctor_out" | grep -c 'read 2 Codex system skill(s)')"
check "native-doctor-no-false-codex" "0" "$(printf '%s\n' "$doctor_out" | grep -c 'imagegen is also')"

# 31. with this plugin installed in Claude Code, its skills already load as <plugin>:<skill>: install
#     makes no personal Claude links (they would load everything twice), still links Codex, and
#     doctor accepts the plugin and warns about a personal link that duplicates it
plugin_home() {
  local h
  h=$(new_home)
  mkdir -p "$h/.claude/plugins"
  printf '{"version": 2, "plugins": {"%s@%s": [{"scope": "user"}]}}\n' "$OTHER_PLUGIN_NAME" "$OTHER_PLUGIN_NAME" \
    > "$h/.claude/plugins/installed_plugins.json"
  printf '%s' "$h"
}
H=$(plugin_home)
bash "$INSTALL" --prefix "$H" >/dev/null 2>&1
check "plugin-install-no-claude-links" "0" "$(link_count "$H/.claude")"
check "plugin-install-still-links-codex" "${#SKILLS[@]}" "$(link_count "$H/.agents")"
doctor_out=$(bash "$DOCTOR" --prefix "$H" 2>&1)
check "plugin-doctor-accepts-plugin" "1" "$(printf '%s\n' "$doctor_out" | grep -c "installed as the $OTHER_PLUGIN_NAME plugin")"
check "plugin-doctor-no-missing-claude" "0" "$(printf '%s\n' "$doctor_out" | sed -n '/^Claude Code/,/^$/p' | grep -c 'is not installed')"
mkdir -p "$H/.claude/skills"
ln -s "$REPO_ROOT/skills/testing" "$H/.claude/skills/testing"
doctor_out=$(bash "$DOCTOR" --prefix "$H" 2>&1)
check "plugin-doctor-warns-duplicate" "1" "$(printf '%s\n' "$doctor_out" | grep -c "loads both $OTHER_PLUGIN_NAME:testing and testing")"

printf '\nGuard summary: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
