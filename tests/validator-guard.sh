#!/usr/bin/env bash
# Proves scripts/validate.sh can actually fail: copies this repo's skills/,
# evals/, examples/, package.json and .claude-plugin/ into a sandbox, then
# applies one minimal mutation per check and asserts validate.sh reports it.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
VALIDATE="$REPO_ROOT/scripts/validate.sh"


SANDBOX_ROOT="$(mktemp -d)"
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

BASELINE="$SANDBOX_ROOT/baseline"
mkdir -p "$BASELINE"
for item in skills evals examples package.json .claude-plugin; do
  if [[ -e "$REPO_ROOT/$item" ]]; then
    cp -r "$REPO_ROOT/$item" "$BASELINE/$item"
  fi
done
mkdir -p "$BASELINE/skills" "$BASELINE/evals"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

report() {
  local status="$1" name="$2" detail="${3:-}"
  case "$status" in
    PASS)
      PASS_COUNT=$((PASS_COUNT + 1))
      printf 'PASS  %s\n' "$name"
      ;;
    FAIL)
      FAIL_COUNT=$((FAIL_COUNT + 1))
      printf 'FAIL  %s -- %s\n' "$name" "$detail"
      ;;
    SKIP)
      SKIP_COUNT=$((SKIP_COUNT + 1))
      printf 'SKIP  %s -- %s\n' "$name" "$detail"
      ;;
  esac
}

fresh_copy() {
  local wd
  wd="$(mktemp -d "$SANDBOX_ROOT/case.XXXXXX")"
  cp -r "$BASELINE/." "$wd/"
  printf '%s' "$wd"
}

# Sets LAST_OUT and LAST_EXIT from running validate.sh --strict against $1.
run_validate() {
  local dir="$1"
  if LAST_OUT="$(bash "$VALIDATE" --strict "$dir" 2>&1)"; then
    LAST_EXIT=0
  else
    LAST_EXIT=$?
  fi
}

# Picks the name of the $2'th skill directory (1-indexed) under $1/skills.
pick_skill() {
  local wd="$1" idx="$2" n=0 name="" d
  while IFS= read -r -d '' d; do
    n=$((n + 1))
    if [[ $n -eq $idx ]]; then
      name="$(basename -- "$d")"
      break
    fi
  done < <(find "$wd/skills" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
  printf '%s' "$name"
}

# --- one mutation function per check, each self-sufficient: it creates
# whatever minimal structure it needs before breaking it, so the guard works
# whether the source content is already v2-compliant or not. Returns 1 to
# signal the test should be skipped (no usable target at all).

mutate_skills_structure() {
  local wd="$1"
  mkdir -p "$wd/skills"
  touch "$wd/skills/__stray_file.md"
}

mutate_frontmatter_parse() {
  local wd="$1" s
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" && -f "$wd/skills/$s/SKILL.md" ]] || return 1
  sed -i '1d' "$wd/skills/$s/SKILL.md"
}

mutate_frontmatter_required() {
  local wd="$1" s
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" && -f "$wd/skills/$s/SKILL.md" ]] || return 1
  sed -i '/^description:/d' "$wd/skills/$s/SKILL.md"
}

mutate_frontmatter_unknown_key() {
  local wd="$1" s
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" && -f "$wd/skills/$s/SKILL.md" ]] || return 1
  sed -i '1a bogus-extension-key: not-allowed' "$wd/skills/$s/SKILL.md"
}

mutate_name_format() {
  local wd="$1" s
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" && -f "$wd/skills/$s/SKILL.md" ]] || return 1
  sed -i 's/^name:.*/name: Bad--Name_/' "$wd/skills/$s/SKILL.md"
}

mutate_name_dir_mismatch() {
  local wd="$1" s
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" && -f "$wd/skills/$s/SKILL.md" ]] || return 1
  sed -i 's/^name:.*/name: totally-different-skill-name/' "$wd/skills/$s/SKILL.md"
}

mutate_duplicate_name() {
  local wd="$1" s1 s2
  s1="$(pick_skill "$wd" 1)"
  s2="$(pick_skill "$wd" 2)"
  [[ -n "$s1" && -n "$s2" && -f "$wd/skills/$s2/SKILL.md" ]] || return 1
  sed -i "s/^name:.*/name: $s1/" "$wd/skills/$s2/SKILL.md"
}

# Reusing a harness-native name displaces that harness's own capability, so it must not validate.
mutate_native_name_collision() {
  local wd="$1" s
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" && -f "$wd/skills/$s/SKILL.md" ]] || return 1
  mv "$wd/skills/$s" "$wd/skills/code-review"
  sed -i 's/^name:.*/name: code-review/' "$wd/skills/code-review/SKILL.md"
}

# An alias counts: Claude Code keeps routing a bundled alias to the bundled skill.
mutate_native_alias_collision() {
  local wd="$1" s
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" && -f "$wd/skills/$s/SKILL.md" ]] || return 1
  mv "$wd/skills/$s" "$wd/skills/review"
  sed -i 's/^name:.*/name: review/' "$wd/skills/review/SKILL.md"
}

mutate_description_length() {
  local wd="$1" s
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" && -f "$wd/skills/$s/SKILL.md" ]] || return 1
  sed -i 's/^description:.*/description: /' "$wd/skills/$s/SKILL.md"
}

mutate_compatibility_length() {
  local wd="$1" s big
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" && -f "$wd/skills/$s/SKILL.md" ]] || return 1
  printf -v big 'x%.0s' {1..600}
  sed -i "1a compatibility: $big" "$wd/skills/$s/SKILL.md"
}

mutate_body_length() {
  local wd="$1" s
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" && -f "$wd/skills/$s/SKILL.md" ]] || return 1
  { for ((i = 0; i < 510; i++)); do printf 'filler line %d\n' "$i"; done; } \
    >> "$wd/skills/$s/SKILL.md"
}

mutate_broken_link() {
  local wd="$1" s
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" && -f "$wd/skills/$s/SKILL.md" ]] || return 1
  printf '\nSee [missing](references/does-not-exist.md) for details.\n' \
    >> "$wd/skills/$s/SKILL.md"
}

mutate_unreferenced_file() {
  local wd="$1" s
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" ]] || return 1
  mkdir -p "$wd/skills/$s/references"
  printf '# Orphan\n' > "$wd/skills/$s/references/__orphan.md"
}

mutate_reference_depth() {
  local wd="$1" s
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" && -f "$wd/skills/$s/SKILL.md" ]] || return 1
  mkdir -p "$wd/skills/$s/references"
  printf '# A\nSee references/__guard-dep-b.md for more.\n' > "$wd/skills/$s/references/__guard-dep-a.md"
  printf '# B\n' > "$wd/skills/$s/references/__guard-dep-b.md"
  printf '\nSee references/__guard-dep-a.md.\n' >> "$wd/skills/$s/SKILL.md"
}

mutate_eval_case_missing() {
  local wd="$1" s case_dir
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" ]] || return 1
  case_dir="$wd/evals/${s}-explicit"
  mkdir -p "$case_dir/graders"
  printf -- '---\nid: %s-explicit\n---\nDo the thing explicitly.\n' "$s" > "$case_dir/prompt.md"
  printf -- '---\ntype: rubric\n---\nCheck it worked.\n' > "$case_dir/graders/main.md"
  rm -rf "$case_dir/graders"
}

mutate_eval_frontmatter() {
  local wd="$1" s case_dir
  s="$(pick_skill "$wd" 1)"
  [[ -n "$s" ]] || return 1
  case_dir="$wd/evals/${s}-implicit"
  mkdir -p "$case_dir/graders"
  printf -- '---\nid: %s-implicit\n---\nDo the thing implicitly.\n' "$s" > "$case_dir/prompt.md"
  printf -- '---\ntype: rubric\n---\nCheck it worked.\n' > "$case_dir/graders/main.md"
  sed -i '/^type:/d' "$case_dir/graders/main.md"
}

mutate_version_mismatch() {
  local wd="$1"
  [[ -f "$wd/package.json" ]] || return 1
  sed -i -E 's/"version"[[:space:]]*:[[:space:]]*"[^"]*"/"version": "0.0.1-bad"/' "$wd/package.json"
}

mutate_legacy_artifact() {
  local wd="$1"
  mkdir -p "$wd/hooks"
  printf '#!/bin/sh\n' > "$wd/hooks/dummy.sh"
}

mutate_shell_syntax() {
  local wd="$1"
  mkdir -p "$wd/scripts"
  printf '#!/usr/bin/env bash\nif [ true; then\n' > "$wd/scripts/__broken.sh"
}

mutate_example_missing() {
  local wd="$1"
  [[ -f "$wd/examples/nested-agents.md" ]] || return 1
  rm -f "$wd/examples/nested-agents.md"
}

# An example named like a real instruction file stops being an example: a harness working under
# examples/ would discover it and load it as scoped policy.
mutate_example_not_inert() {
  local wd="$1"
  [[ -d "$wd/examples" ]] || return 1
  printf '# not an example any more\n' > "$wd/examples/AGENTS.md"
}

assert_check_fails() {
  local name="$1" check_id="$2" mutate_fn="$3"
  local wd
  wd="$(fresh_copy)"
  if ! "$mutate_fn" "$wd"; then
    report SKIP "$name" "no usable target in the source content"
    return
  fi
  run_validate "$wd"
  if [[ $LAST_EXIT -eq 0 ]]; then
    report FAIL "$name" "expected a non-zero exit, got 0"
    return
  fi
  if [[ "$LAST_OUT" != *"$check_id"* ]]; then
    report FAIL "$name" "expected check id '$check_id' in output, got: $LAST_OUT"
    return
  fi
  report PASS "$name"
}

echo "=== validator-guard: baseline ==="
wd="$(fresh_copy)"
run_validate "$wd"
if [[ $LAST_EXIT -eq 0 ]]; then
  report PASS "unmutated-sandbox-passes"
else
  report FAIL "unmutated-sandbox-passes" "the unmutated sandbox must pass, or every mutation below proves nothing: $LAST_OUT"
fi

echo "=== validator-guard: per-check mutations ==="
assert_check_fails "skills-structure"       "skills-structure"       mutate_skills_structure
assert_check_fails "frontmatter-parse"      "frontmatter-parse"      mutate_frontmatter_parse
assert_check_fails "frontmatter-required"   "frontmatter-required"   mutate_frontmatter_required
assert_check_fails "frontmatter-unknown-key" "frontmatter-unknown-key" mutate_frontmatter_unknown_key
assert_check_fails "name-format"            "name-format"            mutate_name_format
assert_check_fails "name-dir-mismatch"      "name-dir-mismatch"      mutate_name_dir_mismatch
assert_check_fails "duplicate-name"         "duplicate-name"         mutate_duplicate_name
assert_check_fails "native-name-collision"  "native-name-collision"  mutate_native_name_collision
assert_check_fails "native-alias-collision" "native-name-collision"  mutate_native_alias_collision
assert_check_fails "description-length"     "description-length"    mutate_description_length
assert_check_fails "compatibility-length"   "compatibility-length"  mutate_compatibility_length
assert_check_fails "body-length"            "body-length"            mutate_body_length
assert_check_fails "broken-link"            "broken-link"            mutate_broken_link
assert_check_fails "unreferenced-file"      "unreferenced-file"      mutate_unreferenced_file
assert_check_fails "reference-depth"        "reference-depth"        mutate_reference_depth
assert_check_fails "eval-case-missing"      "eval-case-missing"      mutate_eval_case_missing
assert_check_fails "eval-frontmatter"       "eval-frontmatter"       mutate_eval_frontmatter
assert_check_fails "version-mismatch"       "version-mismatch"       mutate_version_mismatch
assert_check_fails "legacy-artifact"        "legacy-artifact"        mutate_legacy_artifact
assert_check_fails "shell-syntax"           "shell-syntax"           mutate_shell_syntax
assert_check_fails "example-missing"        "example-missing"        mutate_example_missing
assert_check_fails "example-not-inert"      "example-not-inert"      mutate_example_not_inert

printf '\nGuard summary: %d passed, %d failed, %d skipped\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
if [[ $FAIL_COUNT -eq 0 ]]; then
  exit 0
fi
exit 1
