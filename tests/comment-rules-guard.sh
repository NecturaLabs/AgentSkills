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

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
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

run_validator() {
    # The validator's own non-zero exit is the expected result here, so it must
    # not abort this script; the status is captured rather than propagated.
    ( cd "$SANDBOX" && bash tests/validate-comment-rules.sh >/dev/null 2>&1 ) \
        && echo 0 || echo 1
}

# Negative control. If an unmutated copy fails, the harness is broken and every
# "detected" below would be meaningless.
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

# label|sed-expression, split at the FIRST `|`, so only the label is barred from
# containing one; the expression may, provided sed's own delimiter differs. sed
# matches within a line, so every anchor must sit unbroken on one line in every
# copy -- a phrase spanning a line break silently matches nothing. Markdown
# emphasis must be escaped (\*\*), since sed reads a bare * as a quantifier. The
# cmp check in check_mutation catches an anchor gone stale.
#
# `sed -i` with no backup suffix is GNU syntax, so this suite targets Linux and
# Windows/Git Bash only. On BSD sed (macOS) the expression is consumed as the
# backup suffix and the script aborts under `set -e` -- loud, not a silent pass,
# which is why it is a stated constraint rather than a hidden failure mode.
#
# Headline and tail alternate across the seven rules on purpose: guarding both
# halves is the whole point of the duplication check, and a matrix that only
# ever mutated headlines would not prove the tails are checked at all.
MUTATIONS=(
    "rule 1 headline removed|s|A comment carries what the code cannot.||"
    "rule 2 tail removed|s|All three gates, in order, or no comment.||"
    "rule 3 tail removed|s|Implementation detail in an interface comment is a finding.||"
    "rule 4 tail inverted|s|Never inherit it from the language it resembles.|Inherit it from the language it resembles.|"
    "rule 5 headline inverted|s|Never write a rationale you have not verified.|Write whichever rationale seems plausible.|"
    "rule 6 tail removed|s|Editing code means you own every comment on it.||"
    "rule 7 tail removed|s|It never instructs its reader, human or agent.||"
    "block ceiling widened|s|one paragraph, at most 7 lines|one paragraph, at most 70 lines|"
    "canon strength distinction removed|s|Never report a recommendation as a violated rule.||"
    "eighth rule not propagated|s|## The Admission Test|**8. Every rule reaches the review copy.**\nAdding one here requires adding it there.\n\n## The Admission Test|"
    "caller-obligation carve-out removed|s|A caller obligation is a fact about the contract, not an instruction to the reader.||"
)

# One rule phrase, one size limit: the validator checks this file on its own
# pass, and a canary from only one category leaves the other unproven for this
# copy.
CANARIES=(
    "width strength distinction removed|s|Never report a recommendation as a violated rule.||"
    "rule 1 tail removed|s|Restating the code is a defect, not documentation.||"
    "doc summary limit removed|s|exactly one sentence on one physical line||"
    "severity ladder row removed|s|Internal hostname, internal path, infrastructure detail or PII in a comment||"
    "doc-required surface softened|s|Every exported (capitalized) name|Exported things|"
    "step 3 prose severity reverted|s|or PII in a comment is HIGH.|or PII in a comment is CRITICAL.|"
    "rotate-before-delete prose removed|s|Never accept a diff that presents deleting the line as the remediation.||"
    "GDScript spot check inverted|s|\`##\` above the member|a docstring inside the body|"
    "sentinel dropped from the ladder|s|thread-safety or sentinel contract|thread-safety contract|"
    "width ceiling widened|s|Python is 72 even where code is allowed 99|Python is 99 like its code|"
    "Kotlin and C sharp fallbacks dropped|s|120 and 100 respectively|whatever the project prefers|"
)

# review-checklist.md is the first path the dispatched reviewer is handed, and
# it was the copy left at the wrong severity by an earlier remediation, so its
# own pass gets a canary too.
REVIEW_CHECKLIST_CASES=(
    "rotate-and-scrub row removed|s|A leaked secret is rotated and its history scrubbed, not merely deleted||"
)

# The matrix is checked by a third call with its own phrase list, so it needs
# its own case.
MATRIX_CASES=(
    "trap table heading removed|s|Derived-Language Traps|Language Notes|"
    "doc-required table heading removed|s|Doc Comment Required On|Documentation Notes|"
    "matrix doc surface softened|s|All top-level exports|Whatever seems useful|"
    "GDScript trap row inverted|s|\`##\` doc comments \*\*above\*\* the member|a docstring inside the body|"
    "unlisted-language doc branch removed|s|surface was \*\*derived, not looked up\*\*||"
    "matrix Rust width widened|s|80 (\`comment_width\`) while code is 100|100, same as its code|"
    "new trap row with no worked pair|s@^## Unlisted Languages@| **Zig** | C | a wrong instinct | what it specifies |\n\n## Unlisted Languages@"
    "nil doc-obligation rule removed|s|That is a nil obligation, not a missing row|Their absence is simply an oversight|"
)

# The matrix promises a worked pair per trap row, so a dropped section is a
# broken promise the reader only discovers mid-task. Two rows are mutated
# because one deleted section could be the single one a lone case covered.
# The replacement must not still contain the anchor: "## Rust notes " keeps
# "## Rust " inside it and the phrase check goes on matching, so the heading is
# renamed without a space instead.
TRAP_EXAMPLE_CASES=(
    "Rust pair removed|s|## Rust |## RustNotes |"
    "JSON pair removed|s|## JSON |## JSONNotes |"
)

# The secret-handling gate is duplicated across SKILL.md, comment-rules.md and
# both review checklists, and each copy is checked on its own pass. Losing the
# rotate-first instruction turns Fix mode into a tool that deletes a live key
# and reports clean, so every copy that carries it gets a mutation case.
SKILL_CASES=(
    "secret gate headline removed|s|A secret in a comment is never fixed by deleting it.||"
    "rotate-first instruction removed|s|never present that removal as the remediation||"
    "CRITICAL severity row downgraded|s|credential, key, token, connection string or private key in a comment|assorted sensitive values in a comment|"
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
        check_mutation "$file_label / ${entry%%|*}" "$target" "$pristine" \
            "${entry#*|}"
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

run_cases "comment-manager SKILL.md" \
    "$SANDBOX/skills/comment-manager/SKILL.md" \
    "$SANDBOX/pristine-skill.md" \
    "${SKILL_CASES[@]}"

run_cases "review-checklist.md" \
    "$SANDBOX/skills/iterative-code-review/references/review-checklist.md" \
    "$SANDBOX/pristine-review-checklist.md" \
    "${REVIEW_CHECKLIST_CASES[@]}"

run_cases "trap-examples.md" \
    "$SANDBOX/skills/comment-manager/references/trap-examples.md" \
    "$SANDBOX/pristine-trap-examples.md" \
    "${TRAP_EXAMPLE_CASES[@]}"

print_summary
