#!/usr/bin/env bash
# Mutation guard for validate-comment-rules.sh.
#
# A consistency check that cannot fail is worse than no check: it reports green
# over drift and nobody looks again. The sibling house-rules validator proved
# this -- an earlier one-phrase-per-rule version passed 5 of 7 mutations, one of
# them a rule rewritten to its own opposite, while reporting all-clear.
#
# Each case copies the tree to a temp dir, mutates one phrase in one file, and
# asserts the validator fails, then that it passes the unmutated copy. Coverage:
#   - the full matrix against the canon, one phrase from each of the seven
#     rules plus the block ceiling, alternating headline and tail so a
#     validator checking only one half of a rule is caught;
#   - one case minimum for every other file the validator reads, so a validator
#     that silently stopped checking one is caught rather than reported green;
#   - within a file, cases span each phrase list, since a pass covering one
#     list can be deleted while the others keep the file looking guarded. A
#     doc-surface pass added in one round was provably unguarded until a case
#     was written for it.

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

echo "Mutation-testing validate-comment-rules.sh..."

# Guarded cleanup rather than `trap 'rm -rf "$SANDBOX"' EXIT` on a bare
# variable: an unguarded `rm -rf` on a variable is one editing accident away
# from being destructive, and runner-guard.sh already establishes this pattern
# in this suite.
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
    bash "$SANDBOX/tests/validate-comment-rules.sh" >/dev/null 2>&1 \
        || VALIDATOR_STATUS=1
}

# Negative control. If an unmutated copy fails, the harness is broken and every
# "detected" below would be meaningless.
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

# A newline inside a case, where the `sed` expressions these replaced wrote
# `\n`. Two cases insert one.
NL=$'\n'

# label|needle|replacement, split at the FIRST two `|`, so only the label and
# the needle are barred from containing one; the replacement is whatever
# follows the second and may contain any. An empty replacement deletes the
# phrase.
#
# Matching is literal, so markdown emphasis is written plainly -- `sed` needed
# `\*\*` because it read a bare `*` as a quantifier. Every occurrence is
# replaced, where `sed s|||` took the first on each line, which differs only
# in the direction of a more thorough mutation. A phrase must still sit
# unbroken on one line in every copy, since a phrase spanning a line break
# matches nothing; the REPLACE_COUNT check in check_mutation catches an anchor
# gone stale.
#
# Headline and tail alternate across the seven rules on purpose: guarding both
# halves is the whole point of the duplication check, and a matrix that only
# ever mutated headlines would not prove the tails are checked at all.
MUTATIONS=(
    "rule 1 headline removed|A comment carries what the code cannot.|"
    "rule 2 tail removed|All three gates, in order, or no comment.|"
    "rule 3 tail removed|Implementation detail in an interface comment is a finding.|"
    "rule 4 tail inverted|Never inherit it from the language it resembles.|Inherit it from the language it resembles."
    "rule 5 headline inverted|Never write a rationale you have not verified.|Write whichever rationale seems plausible."
    "rule 6 tail removed|Editing code means you own every comment on it.|"
    "rule 7 tail removed|It never instructs its reader, human or agent.|"
    "block ceiling widened|one paragraph, at most 7 lines|one paragraph, at most 70 lines"
    "canon strength distinction removed|Never report a recommendation as a violated rule.|"
    "eighth rule not propagated|## The Admission Test|**8. Every rule reaches the review copy.**${NL}Adding one here requires adding it there.${NL}${NL}## The Admission Test"
    "caller-obligation carve-out removed|A caller obligation is a fact about the contract, not an instruction to the reader.|"
)

# One rule phrase, one size limit: the validator checks this file on its own
# pass, and a canary from only one category leaves the other unproven for this
# copy.
CANARIES=(
    "width strength distinction removed|Never report a recommendation as a violated rule.|"
    "rule 1 tail removed|Restating the code is a defect, not documentation.|"
    "doc summary limit removed|exactly one sentence on one physical line|"
    "severity ladder row removed|Internal hostname, internal path, infrastructure detail or PII in a comment|"
    "doc-required surface softened|Every exported (capitalized) name|Exported things"
    "step 3 prose severity reverted|or PII in a comment is HIGH.|or PII in a comment is CRITICAL."
    "rotate-before-delete prose removed|Never accept a diff that presents deleting the line as the remediation.|"
    "GDScript spot check inverted|\`##\` above the member|a docstring inside the body"
    "sentinel dropped from the ladder|thread-safety or sentinel contract|thread-safety contract"
    "width ceiling widened|Python is 72 even where code is allowed 99|Python is 99 like its code"
    "Kotlin and C sharp fallbacks dropped|120 and 100 respectively|whatever the project prefers"
)

# review-checklist.md is the first path the dispatched reviewer is handed, and
# it was the copy left at the wrong severity by an earlier remediation, so its
# own pass gets a canary too.
REVIEW_CHECKLIST_CASES=(
    "rotate-and-scrub row removed|A leaked secret is rotated and its history scrubbed, not merely deleted|"
)

# The matrix is checked by a third call with its own phrase list, so it needs
# its own case.
MATRIX_CASES=(
    "trap table heading removed|Derived-Language Traps|Language Notes"
    "doc-required table heading removed|Doc Comment Required On|Documentation Notes"
    "matrix doc surface softened|All top-level exports|Whatever seems useful"
    "GDScript trap row inverted|\`##\` doc comments **above** the member|a docstring inside the body"
    "unlisted-language doc branch removed|surface was **derived, not looked up**|"
    "matrix Rust width widened|80 (\`comment_width\`) while code is 100|100, same as its code"
    "new trap row with no worked pair|## Unlisted Languages|| **Zig** | C | a wrong instinct | what it specifies |${NL}${NL}## Unlisted Languages"
    "nil doc-obligation rule removed|That is a nil obligation, not a missing row|Their absence is simply an oversight"
)

# The matrix promises a worked pair per trap row, so a dropped section is a
# broken promise the reader only discovers mid-task. Two rows are mutated
# because one deleted section could be the single one a lone case covered.
# The replacement must not still contain the anchor: "## Rust notes " keeps
# "## Rust " inside it and the phrase check goes on matching, so the heading is
# renamed without a space instead.
TRAP_EXAMPLE_CASES=(
    "Rust pair removed|## Rust |## RustNotes "
    "JSON pair removed|## JSON |## JSONNotes "
)

# The secret-handling gate is duplicated across SKILL.md, comment-rules.md and
# both review checklists, and each copy is checked on its own pass. Losing the
# rotate-first instruction turns Fix mode into a tool that deletes a live key
# and reports clean, so every copy that carries it gets a mutation case.
SKILL_CASES=(
    "secret gate headline removed|A secret in a comment is never fixed by deleting it.|"
    "rotate-first instruction removed|never present that removal as the remediation|"
    "CRITICAL severity row downgraded|credential, key, token, connection string or private key in a comment|assorted sensitive values in a comment"
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
        echo -e "  ${RED}FAIL${NC}: $label -- NOT detected; validate-comment-rules.sh has a blind spot"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    write_file "$target" "$pristine"
}

run_cases() {
    local file_label="$1" rel="$2"
    shift 2
    local entry rest

    for entry in "$@"; do
        rest="${entry#*|}"
        check_mutation "$file_label / ${entry%%|*}" "$rel" \
            "${rest%%|*}" "${rest#*|}"
    done
}

run_cases "comment-rules.md" \
    "skills/comment-manager/references/comment-rules.md" \
    "${MUTATIONS[@]}"

run_cases "comment-checklist.md" \
    "skills/iterative-code-review/references/comment-checklist.md" \
    "${CANARIES[@]}"

run_cases "language-matrix.md" \
    "skills/comment-manager/references/language-matrix.md" \
    "${MATRIX_CASES[@]}"

run_cases "comment-manager SKILL.md" \
    "skills/comment-manager/SKILL.md" \
    "${SKILL_CASES[@]}"

run_cases "review-checklist.md" \
    "skills/iterative-code-review/references/review-checklist.md" \
    "${REVIEW_CHECKLIST_CASES[@]}"

run_cases "trap-examples.md" \
    "skills/comment-manager/references/trap-examples.md" \
    "${TRAP_EXAMPLE_CASES[@]}"

# Every case above rewrites a file in place, so a file that disappears
# entirely was never exercised. That is how the extractors came to initialise
# their result array only after the early return: a missing file left the
# array unset, `set -u` aborted before print_summary, and the floor message
# each check was built around never printed. These assert that message, not
# just a non-zero exit, because an abort exits non-zero too.
#
# The matrix case is the odd one: its call site expands the array with
# `${TRAP_LANGUAGES+...}`, so it survives an unset array either way. What it
# pins is the floor itself, and it goes red when that floor is removed.
validator_output() {
    VALIDATOR_OUTPUT=$(bash "$SANDBOX/tests/validate-comment-rules.sh" 2>&1 \
        || true)
}

check_deleted() {
    local label="$1" rel="$2" anchor="$3"

    read_file "$PROJECT_ROOT/$rel"
    rm -f "$SANDBOX/$rel"
    validator_output
    assert_contains "$VALIDATOR_OUTPUT" "$anchor" "$label" || true
    write_file "$SANDBOX/$rel" "$READ_RESULT"
}

check_deleted "comment-rules.md deleted -- the rule floor reports it" \
    "skills/comment-manager/references/comment-rules.md" \
    "rule halves, expected 14+"

check_deleted "language-matrix.md deleted -- the trap-row floor reports it" \
    "skills/comment-manager/references/language-matrix.md" \
    "trap rows, expected 22+"

# The worked-pair check has no floor of its own: an absent file carries no
# incomplete sections and it passes. What must not happen is an abort, so this
# asserts a line printed after it that only a run reaching the end can produce.
check_deleted "trap-examples.md deleted -- the run still reaches the end" \
    "skills/comment-manager/references/trap-examples.md" \
    "every rule half derived from the canon"

print_summary
