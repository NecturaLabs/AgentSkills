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

# `cd` and $PWD are builtins, so this derives an absolute path without the
# fork a `$(cd ... && pwd)` substitution costs, and CDPATH is cleared because
# a set one sends `cd` somewhere else and echoes where it landed. A parent is
# a prefix of the result rather than a second `cd`. test-helpers.sh states
# what one process costs in this suite.
CDPATH=""
_PREV_PWD=$PWD
cd "${BASH_SOURCE[0]%/*}" 2>/dev/null || cd "$_PREV_PWD"
TESTS_DIR=$PWD
cd "$_PREV_PWD"
PROJECT_ROOT="${TESTS_DIR%/*}"
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

# The validator's own non-zero exit is the expected result here, so it must not
# abort this script; the status is captured rather than propagated. It is left
# in a variable rather than echoed, because `x=$(run_validator)` forks a
# subshell on top of the one the validator already needs, once per mutation.
#
# Invoked by path rather than from a `cd` inside a subshell: the validator
# derives its own root from BASH_SOURCE, so the two are equivalent and the
# subshell was a second fork on every case.
VALIDATOR_STATUS=0

run_validator() {
    VALIDATOR_STATUS=0
    bash "$SANDBOX/tests/validate-house-rules.sh" >/dev/null 2>&1 \
        || VALIDATOR_STATUS=1
}

# Negative control. If an unmutated copy fails, the harness is broken and every
# "detected" below would be meaningless -- which is exactly what happens when
# `bash` resolves to a shim that exits non-zero without running anything.
run_validator
if [ "$VALIDATOR_STATUS" = "0" ]; then
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

# label|needle|replacement, split at the first two `|`. An empty replacement
# deletes the phrase. Only the label and the needle are barred from carrying a
# `|`; the replacement is whatever follows the second one.
#
# Matching is literal and every occurrence is replaced, where the `sed s|||`
# this replaced took the first on each line -- a difference only in the
# direction of a more thorough mutation. A phrase must still sit unbroken on
# one line to match, and the rules wrap at different columns, so an anchor
# spanning a line break silently matches nothing. The REPLACE_COUNT check in
# check_mutation catches an anchor that has gone stale.
MUTATIONS=(
    "rule 1 tail removed|wrapper's behavior|"
    "rule 2 headline removed|Never assert on human-readable copy.|"
    "rule 3 tail removed|before it counts as passing.|"
    "rule 4 inverted, tail kept|Never weaken a test to get green.|Weakening a test to get green is fine."
    "rule 5 tail removed|A green test that pins a bug in place is worse than no test.|"
    "rule 6 triage half removed|The only question is whether you fix it or report it|"
    "repair carve-out removed|Repairing a test that is itself|Fixing a test that is itself"
    "deletion cases removed|Deleting a test is legitimate in four cases:|Tests may be deleted freely:"
)

# One from the rule phrases, one from the matrix phrases: the validator checks
# those on separate passes, and a canary from only one leaves the other pass
# unproven for this file.
CANARIES=(
    "rule 2 headline removed|Never assert on human-readable copy.|"
    "deletion cases removed|Deleting a test is legitimate in four cases:|Tests may be deleted freely:"
)

# The pristine text is the repo's own file: `cp -r` copies byte for byte, so
# the sandbox copy and the original are the same bytes. Mutating and restoring
# in the shell costs nothing, where `cp`, `sed -i` and `cmp` cost a process
# each once per case -- which on Windows was most of this suite's runtime.
#
# A zero REPLACE_COUNT is the stale-anchor check `cmp` used to make. The result
# is compared as well, since a replacement equal to its needle would move the
# count without changing the file.
check_mutation() {
    local label="$1" rel="$2" needle="$3" replacement="$4"
    local target="$SANDBOX/$rel" pristine

    read_file "$PROJECT_ROOT/$rel"
    pristine="$READ_RESULT"
    replace_all "$pristine" "$needle" "$replacement"

    if [ "$REPLACE_COUNT" -eq 0 ] || [ "$REPLACE_RESULT" = "$pristine" ]; then
        echo -e "  ${RED}FAIL${NC}: $label -- mutation changed nothing; the anchor no longer matches"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        write_file "$target" "$pristine"
        return
    fi

    write_file "$target" "$REPLACE_RESULT"
    run_validator
    if [ "$VALIDATOR_STATUS" = "1" ]; then
        echo -e "  ${GREEN}PASS${NC}: $label -- detected"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "  ${RED}FAIL${NC}: $label -- NOT detected; validate-house-rules.sh has a blind spot"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    write_file "$target" "$pristine"
}

first=1
for skill_dir in "$PROJECT_ROOT"/skills/*test-manager/; do
    # Parameter expansion, not `basename`: the reason validate-house-rules.sh
    # states, in a loop this file also runs.
    skill="${skill_dir%/}"
    skill="${skill##*/}"

    if [ "$first" = "1" ]; then
        cases=("${MUTATIONS[@]}")
        first=0
    else
        cases=("${CANARIES[@]}")
    fi

    for entry in "${cases[@]}"; do
        rest="${entry#*|}"
        check_mutation "$skill / ${entry%%|*}" "skills/$skill/SKILL.md" \
            "${rest%%|*}" "${rest#*|}"
    done
done

# The canonical copy is validated by its own call, on the rule phrases only.
check_mutation "house-rules.md / rule 5 tail removed" \
    "skills/test-manager/references/house-rules.md" \
    "A green test that pins a bug in place is worse than no test." ""

print_summary
