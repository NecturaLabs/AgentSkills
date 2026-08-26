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
# returns, which is what makes rewording a rule here a change that gets checked.
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

# The severity ladder is duplicated into comment-manager/SKILL.md and the review-side
# checklist, and lives in neither rule copy, so it needs its own pass. Drift here is worse
# than a missing rule: two loops scoring the same leaked credential differently is how a
# CRITICAL gets triaged as a MEDIUM and shipped.
SEVERITY_REQUIRED=(
    "credential, key, token, connection string or private key in a comment"
    "Internal hostname, internal path, infrastructure detail or PII in a comment"
    "security-scanner suppression with no justification and no tracked reference"
)

# Deleting a leaked secret is not remediating it. If this instruction is lost, Fix mode
# quietly becomes a tool that removes the evidence and reports clean over a live key.
SKILL_REQUIRED=(
    "A secret in a comment is never fixed by deleting it."
    "never present that removal as the remediation"
)

CANON_REQUIRED=(
    "Removing the line is cleanup after remediation, never the remediation itself."
    "A caller obligation is a fact about the contract, not an instruction to the reader."
)

# review-checklist.md is the FIRST of the three paths handed to a dispatched reviewer, so a
# severity stated only in the other two is a severity the reviewer never reads. It carries the
# ladder in its own wording, hence its own list.
REVIEW_CHECKLIST_REQUIRED=(
    "credential, key, token, connection string or private key in a comment"
    "Internal hostname, internal path, infrastructure detail or PII in a comment"
    "A leaked secret is rotated and its history scrubbed, not merely deleted"
)

# The doc-required surface is inlined into the review checklist because a dispatched subagent
# cannot resolve a path under another skill. Two copies of a table drift; these anchors are the
# rows most likely to be silently softened, and they must read identically in both.
DOC_SURFACE_REQUIRED=(
    "All top-level exports"
    "Every exported (capitalized) name"
    "Every public item"
)

# The severity ladder also appears as prose in the review checklist's step 3, and the table
# anchors above do not cover it: the prose was silently revertible to CRITICAL while every
# table stayed correct. The rotate-before-delete instruction lives only in that prose, and
# this is the copy that runs on every change.
REVIEW_PROSE_REQUIRED=(
    "A credential, key, token, connection string or private key in a comment is CRITICAL."
    "An internal hostname, internal path, infrastructure detail or PII in a comment is HIGH."
    "Never accept a diff that presents deleting the line as the remediation."
)

CANON="$PROJECT_ROOT/skills/comment-manager/references/comment-rules.md"
REVIEW="$PROJECT_ROOT/skills/iterative-code-review/references/comment-checklist.md"
MATRIX="$PROJECT_ROOT/skills/comment-manager/references/language-matrix.md"
SKILL="$PROJECT_ROOT/skills/comment-manager/SKILL.md"
REVIEW_CHECKLIST="$PROJECT_ROOT/skills/iterative-code-review/references/review-checklist.md"

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

check_phrases "comment-rules.md" "$CANON" "the secret and caller-obligation carve-outs" "${CANON_REQUIRED[@]}"
check_phrases "comment-manager SKILL.md" "$SKILL" "the secret-handling gate" "${SKILL_REQUIRED[@]}"
check_phrases "comment-manager SKILL.md" "$SKILL" "the severity ladder" "${SEVERITY_REQUIRED[@]}"
check_phrases "comment-checklist.md" "$REVIEW" "the severity ladder" "${SEVERITY_REQUIRED[@]}"
check_phrases "review-checklist.md" "$REVIEW_CHECKLIST" "the severity ladder" "${REVIEW_CHECKLIST_REQUIRED[@]}"
check_phrases "language-matrix.md" "$MATRIX" "the doc-required surface" "${DOC_SURFACE_REQUIRED[@]}"
check_phrases "comment-checklist.md" "$REVIEW" "the doc-required surface" "${DOC_SURFACE_REQUIRED[@]}"
check_phrases "comment-checklist.md" "$REVIEW" "the step 3 leak prose" "${REVIEW_PROSE_REQUIRED[@]}"

print_summary
