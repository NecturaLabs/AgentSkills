#!/usr/bin/env bash
# Mutation guard for validate-house-rules.sh.
#
# A consistency check that cannot fail is worse than no check: it reports green
# over drift and nobody looks again. An earlier one-phrase-per-rule version of
# validate-house-rules.sh passed 5 of 7 mutations -- including a rule 4
# rewritten to "Weakening a test to get green is fine." -- while still reporting
# all-clear.
#
# Each case copies the tree to a temp dir, mutates one phrase in one file, and
# asserts the validator fails, then that it passes the unmutated copy. Coverage:
#   - the full matrix against the first skill, one phrase from each of the six
#     rules plus the matrix carve-outs -- not every guarded phrase, since they
#     share one loop and a single one going unchecked is unreachable;
#   - two canaries for every other skill, one from the rule phrases and one
#     from the matrix phrases, so a validator that silently stopped checking a
#     skill on either code path is caught rather than reported green;
#   - a case of its own for the canonical house-rules.md, which a separate call
#     checks.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/test-helpers.sh"

echo "Mutation-testing validate-house-rules.sh..."

# Guarded cleanup rather than `trap 'rm -rf "$SANDBOX"' EXIT`: an unguarded
# `rm -rf` on a variable is one editing accident away from being destructive.
# comment-rules-guard.sh already established this form in this suite.
SANDBOX=""

cleanup_sandbox() {
    if [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ]; then
        rm -rf "$SANDBOX"
    fi
    SANDBOX=""
}
trap cleanup_sandbox EXIT

SANDBOX=$(mktemp -d)

cp -r "$PROJECT_ROOT/skills" "$SANDBOX/skills"
cp -r "$PROJECT_ROOT/tests" "$SANDBOX/tests"

run_validator() {
    # The validator's own non-zero exit is the expected result here, so it must
    # not abort this script; the status is captured rather than propagated.
    ( cd "$SANDBOX" && bash tests/validate-house-rules.sh >/dev/null 2>&1 ) \
        && echo 0 || echo 1
}

# Negative control. If an unmutated copy fails, the harness is broken and every
# "detected" below would be meaningless -- which is exactly what happens when
# `bash` resolves to a shim that exits non-zero without running anything.
if [ "$(run_validator)" = "0" ]; then
    echo -e "  ${GREEN}PASS${NC}: unmutated copy passes (negative control)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}FAIL${NC}: unmutated copy FAILS -- the harness is broken, not the rules"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    # `|| true` then an explicit exit: print_summary returns 1 with FAIL_COUNT
    # set, and under `set -e` that would terminate here, making a bare `exit 1`
    # below it dead code that only looks like the thing producing the exit
    # status.
    print_summary || true
    exit 1
fi

# label|sed-expression. `|` is the delimiter, so no pattern may contain one. sed
# matches within a line, so every anchor must be short enough to sit on one line
# in every copy -- the rules wrap at different columns, and a phrase spanning a
# line break silently matches nothing. The cmp check in check_mutation catches
# an anchor that has gone stale.
MUTATIONS=(
    "rule 1 tail removed|s|wrapper's behavior||"
    "rule 2 headline removed|s|Never assert on human-readable copy.||"
    "rule 3 tail removed|s|before it counts as passing.||"
    "rule 4 inverted, tail kept|s|Never weaken a test to get green.|Weakening a test to get green is fine.|"
    "rule 5 tail removed|s|A green test that pins a bug in place is worse than no test.||"
    "rule 6 triage half removed|s|The only question is whether you fix it or report it||"
    "repair carve-out removed|s|Repairing a test that is itself|Fixing a test that is itself|"
    "deletion cases removed|s|Deleting a test is legitimate in four cases:|Tests may be deleted freely:|"
)

# One from the rule phrases, one from the matrix phrases: the validator checks
# those on separate passes, and a canary from only one leaves the other pass
# unproven for this file.
CANARIES=(
    "rule 2 headline removed|s|Never assert on human-readable copy.||"
    "deletion cases removed|s|Deleting a test is legitimate in four cases:|Tests may be deleted freely:|"
)

check_mutation() {
    local label="$1" target="$2" pristine="$3" expression="$4"

    cp "$pristine" "$target"
    sed -i "$expression" "$target"

    if cmp -s "$pristine" "$target"; then
        echo -e "  ${RED}FAIL${NC}: $label -- mutation changed nothing; the anchor no longer matches"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        cp "$pristine" "$target"
        return
    fi

    if [ "$(run_validator)" = "1" ]; then
        echo -e "  ${GREEN}PASS${NC}: $label -- detected"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "  ${RED}FAIL${NC}: $label -- NOT detected; validate-house-rules.sh has a blind spot"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    cp "$pristine" "$target"
}

first=1
for skill_dir in "$SANDBOX"/skills/*test-manager/; do
    skill=$(basename "$skill_dir")
    target="$skill_dir/SKILL.md"
    pristine="$SANDBOX/pristine-$skill.md"
    cp "$target" "$pristine"

    if [ "$first" = "1" ]; then
        cases=("${MUTATIONS[@]}")
        first=0
    else
        cases=("${CANARIES[@]}")
    fi

    for entry in "${cases[@]}"; do
        check_mutation "$skill / ${entry%%|*}" "$target" "$pristine" \
            "${entry#*|}"
    done
done

# The canonical copy is validated by its own call, on the rule phrases only.
canonical="$SANDBOX/skills/test-manager/references/house-rules.md"
canonical_pristine="$SANDBOX/pristine-house-rules.md"
cp "$canonical" "$canonical_pristine"
check_mutation "house-rules.md / rule 5 tail removed" \
    "$canonical" "$canonical_pristine" \
    "s|A green test that pins a bug in place is worse than no test.||"

print_summary
