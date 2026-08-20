#!/usr/bin/env bash
# The six house rules are deliberately duplicated across the test-skill family so each skill is
# usable standalone. Duplication without a check drifts: a rule gets truncated in one copy, and the
# skill that loses the actionable half stops binding behavior.
#
# Each rule is guarded by TWO disjoint phrases -- one from the headline, one from the actionable
# tail. Guarding a single phrase per rule is not enough, and was not: an earlier one-phrase version
# of this script passed 5 of 7 mutations, including a rule 4 rewritten to "Weakening a test to get
# green is fine." Requiring both halves means truncating to the headline drops the tail, dropping
# the headline fails the headline check, and inverting a rule fails whichever half it rewrote.
#
# tests/house-rules-guard.sh mutation-tests this script and fails if any of those blind spots
# returns. Run it after rewording a rule.
#
# Level-specific tailoring IS allowed: a skill may insert clauses into a rule and may add rules 7+.
# What is not allowed is dropping, truncating, or inverting any of the six.
#
# Matching is done in-process with bash pattern tests rather than by piping to grep. The guard runs
# this script a dozen times, and a subprocess per phrase per file put that at two minutes on
# Windows; in-process it is instant, and the semantics are identical.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/test-helpers.sh"

echo "Validating house-rule consistency..."

# Derived, not hardcoded: a fifth family skill added later is covered automatically, and a skill
# quietly dropped from a hardcoded list cannot silently stop being checked.
SKILLS=()
for skill_dir in "$PROJECT_ROOT"/skills/*test-manager/; do
    [ -d "$skill_dir" ] || continue
    SKILLS+=("$(basename "$skill_dir")")
done

if [ "${#SKILLS[@]}" -lt 4 ]; then
    echo -e "${RED}FAIL${NC}: expected at least 4 skills matching skills/*test-manager/, found ${#SKILLS[@]}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    print_summary
    exit 1
fi

# Two phrases per rule, plus a third for rule 6 covering the fix-or-report triage, which is the
# half most likely to be lost when someone "simplifies" it back to an absolute.
REQUIRED=(
    "Test our code, never a library or framework."
    "Wrap the dependency and test our wrapper's behavior instead."
    "Never assert on human-readable copy."
    "never a duplicated literal sentence."
    "Every new test must be observed failing"
    "before it counts as passing."
    "Never weaken a test to get green."
    "or the requirement changed (see the upsert matrix below)."
    "Never encode a known bug as expected behavior."
    "A green test that pins a bug in place is worse than no test."
    "You ran it, you own it."
    "The only question is whether you fix it or report it"
    "citing the evidence for that."
)

# The upsert matrix and its two carve-outs live in SKILL.md only -- house-rules.md carries the six
# rules and nothing else -- so they are checked separately from REQUIRED.
MATRIX_REQUIRED=(
    "the only case where editing an existing test is legitimate"
    "Repairing a test that is itself"
    "Deleting a test is legitimate in four cases:"
)

CANONICAL="$PROJECT_ROOT/skills/test-manager/references/house-rules.md"

# Collapse every run of whitespace to a single space so a rule wrapped at a different column, or
# split across lines, still matches.
normalize() {
    local text
    text=$(<"$1")
    text=${text//$'\r'/ }
    text=${text//$'\n'/ }
    text=${text//$'\t'/ }
    while [[ $text == *"  "* ]]; do
        text=${text//  / }
    done
    printf '%s' "$text"
}

check_phrases() {
    local label="$1" path="$2" kind="$3"
    shift 3
    local phrases=("$@")
    local normalized missing=""

    if [ ! -f "$path" ]; then
        echo -e "${RED}FAIL${NC}: $label -- file missing at $path"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi

    normalized=$(normalize "$path")

    for phrase in "${phrases[@]}"; do
        if [[ $normalized != *"$phrase"* ]]; then
            missing="$missing\n    - $phrase"
        fi
    done

    if [ -n "$missing" ]; then
        echo -e "${RED}FAIL${NC}: $label -- $kind missing or altered:$missing"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo -e "${GREEN}PASS${NC}: $label -- $kind intact"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
}

# The canonical copy must carry every phrase, or it cannot be the reference the skills are checked
# against -- and a reword there that is not propagated fails here first.
check_phrases "house-rules.md" "$CANONICAL" "all six house rules" "${REQUIRED[@]}"

for skill in "${SKILLS[@]}"; do
    check_phrases "$skill" "$PROJECT_ROOT/skills/$skill/SKILL.md" "all six house rules" "${REQUIRED[@]}"
done

# Every skill must carry the upsert matrix inline: an agent dispatched into one never loads a
# sibling, so a matrix that lives only in unit-test-manager binds only unit-test-manager.
for skill in "${SKILLS[@]}"; do
    check_phrases "$skill" "$PROJECT_ROOT/skills/$skill/SKILL.md" \
        "upsert matrix, repair carve-out and deletion cases" "${MATRIX_REQUIRED[@]}"
done

print_summary
