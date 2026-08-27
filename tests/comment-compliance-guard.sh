#!/usr/bin/env bash
# Mutation guard for comment-compliance.sh.
#
# That script is the only thing holding this repo to the comment rules it
# publishes, and every check in it is a regex. A regex that stops matching goes
# on reporting green, so each check is exercised here against a violation
# planted on purpose. Its two siblings, house-rules-guard.sh and
# comment-rules-guard.sh, exist for the same reason and are built the same way.
#
# Each case restores tests/, hooks/ and .editorconfig in a sandbox, plants one
# violation, and asserts comment-compliance.sh fails naming that violation. The
# negative control runs first: a harness that fails on a clean tree proves
# nothing about the mutated ones.
#
# Mutations target validate-skills.sh, whose header is one line, so a planted
# header or paragraph never collides with prose already there.

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

echo "Validating comment-compliance.sh detects violations..."

SANDBOX_ROOT=""
SANDBOX=""

cleanup_sandbox() {
    if [ -n "$SANDBOX_ROOT" ] && [ -d "$SANDBOX_ROOT" ]; then
        rm -rf "$SANDBOX_ROOT"
    fi
    SANDBOX_ROOT=""
    SANDBOX=""
}
trap cleanup_sandbox EXIT

# One temp directory for the run, with the sandbox the checker sees and the
# capture file it must not see as siblings inside it.
SANDBOX_ROOT=$(mktemp -d)
SANDBOX="$SANDBOX_ROOT/tree"

CANON_REL="skills/comment-manager/references/comment-rules.md"

# The four files any case can mutate, read once. Restoring them is then a
# write of text already in hand: `cp` cost a process each, four per case and
# two dozen cases, which was most of this suite's runtime on Windows.
read_file "$TESTS_DIR/validate-skills.sh"
PRISTINE_TARGET="$READ_RESULT"
read_file "$PROJECT_ROOT/hooks/session-start"
PRISTINE_HOOK="$READ_RESULT"
read_file "$PROJECT_ROOT/.editorconfig"
PRISTINE_EDITORCONFIG="$READ_RESULT"
read_file "$PROJECT_ROOT/$CANON_REL"
PRISTINE_CANON="$READ_RESULT"

# comment-compliance.sh derives PROJECT_ROOT from its own location, so the
# sandbox needs the same three things the real tree gives it.
SANDBOX_CANON=""

build_sandbox() {
    SANDBOX_CANON="$SANDBOX/skills/comment-manager/references"
    mkdir -p "$SANDBOX/tests" "$SANDBOX/hooks" "$SANDBOX_CANON"
    cp "$TESTS_DIR"/*.sh "$SANDBOX/tests/"
    # The guard itself is not copied: it is not a target, and leaving it out
    # keeps a mutation from being measured against this file's own comments.
    rm -f "$SANDBOX/tests/comment-compliance-guard.sh"
}

# Restores only what a case can mutate, rather than rebuilding the tree. The
# four paths below are the complete set any case touches, and re-copying the
# whole tree per case was most of this suite's runtime on Windows.
#
# comment-compliance.sh derives its banned words from the canon, so the
# sandbox needs it too. Without it the derived list is empty, the floor fires,
# and every case below fails for a reason none of them is testing.
reset_sandbox() {
    if [ -z "$SANDBOX" ] || [ ! -d "$SANDBOX" ]; then
        build_sandbox
    fi
    write_file "$SANDBOX/tests/validate-skills.sh" "$PRISTINE_TARGET"
    write_file "$SANDBOX/hooks/session-start" "$PRISTINE_HOOK"
    write_file "$SANDBOX/.editorconfig" "$PRISTINE_EDITORCONFIG"
    write_file "$SANDBOX_CANON/comment-rules.md" "$PRISTINE_CANON"
}

# Invoked by path rather than from a `cd` inside a subshell: the script
# derives its own root from BASH_SOURCE, so the two are equivalent and the
# subshell was a second fork on every case.
#
# Captured through a file rather than `$(...)`, which forks before it can
# exec, and read back through a redirect, which does not. One run yields both
# the output and the status, so the negative control needs no second run. The
# capture sits above the sandbox, where the tests/**.sh sweep cannot reach it.
TARGET=""
CAPTURE="$SANDBOX_ROOT/capture.out"
COMPLIANCE_OUTPUT=""
COMPLIANCE_STATUS=0

run_compliance() {
    COMPLIANCE_STATUS=0
    bash "$SANDBOX/tests/comment-compliance.sh" > "$CAPTURE" 2>&1 \
        || COMPLIANCE_STATUS=$?
    read_file "$CAPTURE"
    COMPLIANCE_OUTPUT="$READ_RESULT"
}

# Negative control. Every case below reads as a pass if the harness cannot run
# at all, so the clean tree is asserted green before anything is planted.
reset_sandbox
run_compliance
assert_exit_status "$COMPLIANCE_STATUS" 0 \
    "an unmutated sandbox -- comment-compliance.sh passes" \
    || true

plant() {
    reset_sandbox
    TARGET="$SANDBOX/tests/validate-skills.sh"
    printf '%s\n' "$1" >> "$TARGET"
}

# `printf -v` fills a variable in the shell, where `$(printf ...)` forked to
# build the same string.
printf -v WIDE_RUN 'x%.0s' {1..90}
plant "# $WIDE_RUN"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "over 80" \
    "an over-width comment line -- detected" \
    || true

plant "# This note says the value is currently three."
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "time-anchored" \
    "a time-anchored word -- detected" \
    || true

plant "# ----------------"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "decorative marker" \
    "a decorative position marker -- detected" \
    || true

plant "# TODO: tighten this later"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "annotation with no owner" \
    "an unowned annotation -- detected" \
    || true

plant "# fi"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "commented-out code" \
    "commented-out code -- detected" \
    || true

# An eight-line paragraph, one over the block ceiling. Planted after a blank
# line so it is a paragraph of its own rather than an extension of the last one.
reset_sandbox
TARGET="$SANDBOX/tests/validate-skills.sh"
{
    printf '\n'
    for i in {1..8}; do
        printf '# paragraph line %s of eight\n' "$i"
    done
    printf 'true\n'
} >> "$TARGET"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "block comment is 8 lines" \
    "a paragraph over the block ceiling -- detected" \
    || true

# A 21-line header, one over the design-rationale carve-out. Written from
# scratch so the file's own one-line header does not shift the count.
reset_sandbox
TARGET="$SANDBOX/tests/validate-skills.sh"
{
    printf '#!/usr/bin/env bash\n'
    for i in {1..21}; do
        printf '# header line %s of twenty-one\n' "$i"
    done
    printf '\ntrue\n'
} > "$TARGET"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "header is 21 lines" \
    "a header over the carve-out -- detected" \
    || true

plant '}  # end of if'
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "label on a closing brace" \
    "a closing-brace label -- detected" \
    || true

# The width is configuration, so losing it must fail rather than fall back to a
# hardcoded default that nobody can see or change.
reset_sandbox
replace_line_prefix "$PRISTINE_EDITORCONFIG" "max_line_length" ""
write_file "$SANDBOX/.editorconfig" "$REPLACE_RESULT"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "declares no [*.sh] max_line_length" \
    "a missing width declaration -- detected" \
    || true

# A CRLF .editorconfig. No glob in .gitattributes reaches a dotfile with no
# extension, so `* text=auto` decides it and a Windows checkout with
# core.autocrlf=true gets CRLF. `read` leaves that CR on the value, so the
# section header stops matching and the width reads as absent -- a hard failure
# of the whole suite on the default Git for Windows setting.
reset_sandbox
replace_all "$PRISTINE_EDITORCONFIG" $'\n' $'\r\n'
# The only mutation here whose assertion would still pass over an unmutated
# file: a stale anchor leaves the pristine LF copy, which reports the width
# just as the CRLF copy must. Every other case in this file fails closed.
if [ "$REPLACE_COUNT" -eq 0 ]; then
    echo -e "  ${RED}FAIL${NC}: a CRLF .editorconfig -- the mutation changed nothing"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
write_file "$SANDBOX/.editorconfig" "$REPLACE_RESULT"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "declares [*.sh] width 80" \
    "a CRLF .editorconfig -- the width is still read" \
    || true

# A checked file that disappears must fail rather than shrink the run silently,
# the way a dropped suite once did in the aggregator.
reset_sandbox
rm -f "$SANDBOX/hooks/session-start"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "missing or unreadable" \
    "a checked file gone missing -- detected" \
    || true

# Google's shell guide allows a line over the limit when a literal cannot
# sensibly be split, so the code check removes quoted spans before measuring.
# A long CALL has nothing to remove and must still fail, or the carve-out
# becomes a blanket exemption.
plant "aaaa=1; bbbb=2; cccc=3; dddd=4; eeee=5; ffff=6; gggg=7; hhhh=8; iiii=9; jjjj=10; kkkk=11"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "cols of code" \
    "an over-width code line that is not literal-dominated -- detected" \
    || true

# The other half of the carve-out: a line long only because of one unsplittable
# string must NOT be reported, or the check fails 80 lines that Google permits.
printf -v LITERAL_RUN 'y%.0s' {1..95}
plant "echo \"$LITERAL_RUN\""
run_compliance
assert_not_contains "$COMPLIANCE_OUTPUT" "cols of code" \
    "an over-width line dominated by a literal -- exempt" \
    || true

# `\"` is an escaped quote CHARACTER, not the start of a literal. Reading it as
# one made the rest of the line look like a string, and an 88-column line of
# pure code passed. This is the false-pass direction, so it gets its own case.
plant 'echo \" && aaaa=1 && bbbb=2 && cccc=3 && dddd=4 && eeee=5 && ffff=6 && gggg=7 && hhhh=88'
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "cols of code" \
    "an escaped quote on an over-width code line -- still detected" \
    || true

# The quotes here BALANCE, so the fail-closed path cannot rescue the case and
# only the backslash branch can catch it. Without that distinction the branch
# was deletable with every test still green -- the escaped-quote case above
# is carried by the unterminated-span fallback, not by the branch it names.
plant 'X="a\"" ; aaaa=1 && bbbb=2 && cccc=3 && dddd=4 && eeee=5 && ffff=6 && gggg=7 && hhh=8 ; zz="b\""'
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "cols of code" \
    "a balanced escaped quote -- only the backslash branch can catch it" \
    || true

# The backslash branch keeps a code-context escape in the measured text. This
# line is 81 raw with one such escape, so dropping those two characters would
# put it at 79 and exempt it. Without this case that append is deletable with
# every test still green -- the branch is pinned, but only half of it.
plant 'aaaa=1 && bbbb=2 && cccc=3 && dddd=4 && eeee=5 && ffff=6 && gggg=7 && h=\8zzzzzzz'
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "cols of code" \
    "a code-context backslash -- its two characters stay measured" \
    || true

# An unterminated quote is measured raw rather than exempted, so a stray
# apostrophe cannot silence the rest of the line.
plant "aaaa=1 # it's over the limit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "cols of code" \
    "an unterminated quote on an over-width code line -- measured raw" \
    || true

# A hedging term the previous hand-kept list omitted while the canon carried it.
# Detecting it is what proves the list is read from the canon rather than
# restated, since no hardcoded array in this repo ever contained it.
plant "# This approach should work for the common case."
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "time-anchored or hedging" \
    "a canon term absent from the old hand-kept list -- detected" \
    || true

# Losing the canon rows must fail loudly. A derived list that quietly empties
# bans nothing while every file still reports clean.
reset_sandbox
replace_line_prefix "$PRISTINE_CANON" "| Speculation and hedging:" ""
HEDGING_DROPPED=$REPLACE_COUNT
replace_line_prefix "$REPLACE_RESULT" "| Time-anchored language:" ""
# Each row checked separately, because the floor fires when either one alone
# is gone: a single stale anchor left this case green while exercising only
# the other row.
if [ "$HEDGING_DROPPED" -eq 0 ] || [ "$REPLACE_COUNT" -eq 0 ]; then
    echo -e "  ${RED}FAIL${NC}: the canon rows deleted -- a row anchor changed nothing"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
write_file "$SANDBOX_CANON/comment-rules.md" "$REPLACE_RESULT"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "banned words, expected 8+" \
    "the canon rows deleted -- the derived list fails closed" \
    || true

# The canon gone entirely, not merely emptied of its rows. Every case here
# rewrites a file in place, so a file that disappears was never exercised --
# and that is how the array behind this floor came to be initialised only
# after the early return, where a missing file left it unset and `set -u`
# aborted before print_summary. The floor message is asserted rather than the
# exit status, because an abort exits non-zero too.
reset_sandbox
rm -f "$SANDBOX_CANON/comment-rules.md"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "banned words, expected 8+" \
    "the canon file deleted -- the floor reports it rather than aborting" \
    || true

# A term is spliced into a regex, so a metacharacter in one matches nothing
# while the floor still counts it. That is a term lost in silence, which is the
# failure the floor exists to prevent, so the shape of a term is checked too.
reset_sandbox
replace_all "$PRISTINE_CANON" '*probably*' '*probably.*'
write_file "$SANDBOX_CANON/comment-rules.md" "$REPLACE_RESULT"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "not a plain word" \
    "a banned term carrying a metacharacter -- rejected" \
    || true

# A comment run at end-of-file meets no following code line, so the in-loop
# flush never fires for it. Nothing is appended after this block on purpose --
# that is the whole case.
reset_sandbox
TARGET="$SANDBOX/tests/validate-skills.sh"
{
    printf '\n'
    for i in {1..8}; do
        printf '# trailing paragraph line %s of eight\n' "$i"
    done
} >> "$TARGET"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "block comment is 8 lines" \
    "a paragraph at end-of-file -- still measured" \
    || true

# A backslash ending a single-quoted span. The branch carve-out keeps that span
# closing at its own quote; without it the span runs on to the apostrophe in the
# trailing comment and the rest of the line stops being measured.
plant "x='a\\' && aaaa=1 && bbbb=2 && cccc=3 && dddd=4 && eeee=5 && fff=6 # doesn't matter"
run_compliance
assert_contains "$COMPLIANCE_OUTPUT" "cols of code" \
    "a backslash ending a single-quoted span -- carve-out keeps it closing" \
    || true

# The `-r` half of the readability guard has no case: an exists-but-unreadable
# file is not expressible on Windows or MSYS, where chmod 000 is a no-op for the
# owner. Stated rather than left implied.

print_summary
