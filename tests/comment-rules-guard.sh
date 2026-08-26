#!/usr/bin/env bash
# Mutation guard for validate-comment-rules.sh.
#
# A consistency check that cannot fail is worse than no check: it reports green over drift and
# nobody looks again. The sibling house-rules validator proved this the hard way -- an earlier
# one-phrase-per-rule version passed 5 of 7 mutations, including a rule rewritten to its own
# opposite, while still reporting all-clear.
#
# This copies the tree to a temp dir, mutates one phrase in one file per case, and asserts the
# validator fails each time and passes the unmutated copy. Coverage is deliberate:
#   - the full matrix runs against the canon, exercising one phrase from each of the seven rules
#     plus the block-comment ceiling -- alternating headline and tail across rules, so a validator
#     that only ever checked one half of a rule is caught;
#   - the review-side copy gets two canaries, one rule phrase and one size limit, so a validator
#     that silently stopped checking that file is caught rather than reported green;
#   - the language matrix gets its own case, since it is checked by a separate call with a
#     separate phrase list.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/test-helpers.sh"

echo "Mutation-testing validate-comment-rules.sh..."

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

cp -r "$PROJECT_ROOT/skills" "$SANDBOX/skills"
cp -r "$PROJECT_ROOT/tests" "$SANDBOX/tests"

run_validator() {
    # Never let the validator's own non-zero exit abort this script -- it is the expected result.
    ( cd "$SANDBOX" && bash tests/validate-comment-rules.sh >/dev/null 2>&1 ) && echo 0 || echo 1
}

# Negative control. If an unmutated copy fails, the harness is broken and every "detected" below
# would be meaningless.
if [ "$(run_validator)" = "0" ]; then
    echo -e "  ${GREEN}PASS${NC}: unmutated copy passes (negative control)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}FAIL${NC}: unmutated copy FAILS -- the harness is broken, not the rules"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    print_summary
    exit 1
fi

# label|sed-expression. `|` is the delimiter, so no pattern may contain one. sed matches within a
# line, so every anchor must sit unbroken on one line in every copy -- a phrase spanning a line
# break silently matches nothing. The cmp check in check_mutation catches an anchor gone stale.
#
# Headline and tail alternate across the seven rules on purpose: guarding both halves is the whole
# point of the duplication check, and a matrix that only ever mutated headlines would not prove the
# tails are checked at all.
MUTATIONS=(
    "rule 1 headline removed|s|A comment carries what the code cannot.||"
    "rule 2 tail removed|s|All three gates, in order, or no comment.||"
    "rule 3 tail removed|s|Implementation detail in an interface comment is a finding.||"
    "rule 4 tail inverted|s|Never inherit it from the language it resembles.|Inherit it from the language it resembles.|"
    "rule 5 headline inverted|s|Never write a rationale you have not verified.|Write whichever rationale seems plausible.|"
    "rule 6 tail removed|s|Editing code means you own every comment on it.||"
    "rule 7 tail removed|s|It never instructs its reader, human or agent.||"
    "block ceiling widened|s|one paragraph, at most 7 lines|one paragraph, at most 70 lines|"
)

# One rule phrase, one size limit: the validator checks this file on its own pass, and a canary
# from only one category leaves the other unproven for this copy.
CANARIES=(
    "rule 1 tail removed|s|Restating the code is a defect, not documentation.||"
    "doc summary limit removed|s|exactly one sentence on one physical line||"
)

# The matrix is checked by a third call with its own phrase list, so it needs its own case.
MATRIX_CASES=(
    "trap table heading removed|s|Derived-Language Traps|Language Notes|"
    "doc-required table heading removed|s|Doc Comment Required On|Documentation Notes|"
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
        echo -e "  ${RED}FAIL${NC}: $label -- NOT detected; validate-comment-rules.sh has a blind spot"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    cp "$pristine" "$target"
}

run_cases() {
    local file_label="$1" target="$2" pristine="$3"
    shift 3
    local cases=("$@")

    cp "$target" "$pristine"
    for entry in "${cases[@]}"; do
        check_mutation "$file_label / ${entry%%|*}" "$target" "$pristine" "${entry#*|}"
    done
}

run_cases "comment-rules.md" \
    "$SANDBOX/skills/comment-manager/references/comment-rules.md" \
    "$SANDBOX/pristine-comment-rules.md" \
    "${MUTATIONS[@]}"

run_cases "comment-checklist.md" \
    "$SANDBOX/skills/iterative-code-review/references/comment-checklist.md" \
    "$SANDBOX/pristine-comment-checklist.md" \
    "${CANARIES[@]}"

run_cases "language-matrix.md" \
    "$SANDBOX/skills/comment-manager/references/language-matrix.md" \
    "$SANDBOX/pristine-language-matrix.md" \
    "${MATRIX_CASES[@]}"

print_summary
