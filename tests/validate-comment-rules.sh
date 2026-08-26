#!/usr/bin/env bash
# The seven comment rules are deliberately duplicated: the authoring canon lives in
# comment-manager, and a review-side copy lives in iterative-code-review because a dispatched
# reviewer subagent can only resolve absolute paths under the skill that dispatched it. Pointing
# the reviewer at another skill's directory would resolve to nothing and yield a confident clean
# pass over rules it never read.
#
# Duplication without a check drifts. Each rule is guarded by TWO disjoint phrases -- the headline
# and the actionable tail -- so truncating to the headline drops the tail, dropping the headline
# fails the headline check, and inverting a rule fails whichever half it rewrote. The two size
# limits are guarded too: they are the numbers a reviewer acts on, and a silently widened ceiling
# is indistinguishable from no ceiling.
#
# tests/comment-rules-guard.sh mutation-tests this script and fails if any of those blind spots
# returns. Run it after rewording a rule.
#
# Matching is done in-process with bash pattern tests rather than by piping to grep. The guard runs
# this script a dozen times, and a subprocess per phrase per file put the sibling house-rules check
# at two minutes on Windows; in-process it is instant, and the semantics are identical.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/test-helpers.sh"

echo "Validating comment-rule consistency..."

# Two phrases per rule -- headline, then actionable tail -- followed by the two size limits.
REQUIRED=(
    "A comment carries what the code cannot."
    "Restating the code is a defect, not documentation."
    "Write no comment that fails the admission test."
    "All three gates, in order, or no comment."
    "Interface comments and implementation comments never mix."
    "Implementation detail in an interface comment is a finding."
    "A language's comment convention comes from its own creators."
    "Never inherit it from the language it resembles."
    "Never write a rationale you have not verified."
    "An unknown why is silence, never an invention."
    "A wrong comment is worse than no comment."
    "Editing code means you own every comment on it."
    "A comment states facts about the code."
    "It never instructs its reader, human or agent."
    "one paragraph, at most 7 lines"
    "exactly one sentence on one physical line"
)

# The matrix carries what the two rule copies deliberately do not: the per-language deltas. These
# four anchors cover the sections that exist only there, so a matrix gutted down to a width table
# fails rather than passing on the strength of the rules living elsewhere.
MATRIX_REQUIRED=(
    "Derived-Language Traps"
    "Doc Comment Required On"
    "Never emit a comment"
    "dropped by the type system"
    "Do not infer a convention from a language this one resembles"
)

CANON="$PROJECT_ROOT/skills/comment-manager/references/comment-rules.md"
REVIEW="$PROJECT_ROOT/skills/iterative-code-review/references/comment-checklist.md"
MATRIX="$PROJECT_ROOT/skills/comment-manager/references/language-matrix.md"

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

# The canon must carry every phrase, or it cannot be the reference the review copy is checked
# against -- and a reword there that is not propagated fails here first.
check_phrases "comment-rules.md" "$CANON" "all seven rules and both size limits" "${REQUIRED[@]}"
check_phrases "comment-checklist.md" "$REVIEW" "all seven rules and both size limits" "${REQUIRED[@]}"
check_phrases "language-matrix.md" "$MATRIX" "derived-language traps and the fallback rule" "${MATRIX_REQUIRED[@]}"

print_summary
