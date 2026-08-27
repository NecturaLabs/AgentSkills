#!/usr/bin/env bash
# Mutation guard for comment-compliance.sh.
#
# That script is the only thing holding this repo to the comment rules it
# publishes, and every check in it is a regex. A regex that stops matching goes
# on reporting green, so each check is exercised here against a violation
# planted on purpose. Its two siblings, house-rules-guard.sh and
# comment-rules-guard.sh, exist for the same reason and are built the same way.
#
# Each case copies tests/, hooks/ and .editorconfig into a sandbox, plants one
# violation, and asserts comment-compliance.sh fails naming that violation. The
# negative control runs first: a harness that fails on a clean tree proves
# nothing about the mutated ones.
#
# Mutations target validate-skills.sh, whose header is one line, so a planted
# header or paragraph never collides with prose already there.

set -euo pipefail

# Parameter expansion instead of `dirname` in its own subshell, `|| pwd` for a
# source path with no directory part, and, where a parent is wanted, a prefix
# of the canonical result rather than a second `cd`. test-helpers.sh states
# what one process costs in this suite.
TESTS_DIR="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd || pwd)"
PROJECT_ROOT="${TESTS_DIR%/*}"
source "$TESTS_DIR/test-helpers.sh"

echo "Validating comment-compliance.sh detects violations..."

SANDBOX=""

cleanup_sandbox() {
    if [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ]; then
        rm -rf "$SANDBOX"
    fi
    SANDBOX=""
}
trap cleanup_sandbox EXIT

# comment-compliance.sh derives PROJECT_ROOT from its own location, so the
# sandbox needs the same three things the real tree gives it.
SANDBOX_CANON=""

build_sandbox() {
    SANDBOX=$(mktemp -d)
    SANDBOX_CANON="$SANDBOX/skills/comment-manager/references"
    mkdir -p "$SANDBOX/tests" "$SANDBOX/hooks" "$SANDBOX_CANON"
    cp "$TESTS_DIR"/*.sh "$SANDBOX/tests/"
    cp "$PROJECT_ROOT/hooks/session-start" "$SANDBOX/hooks/"
    # comment-compliance.sh derives its banned words from the canon, so the
    # sandbox needs it too. Without it the derived list is empty, the floor
    # fires, and every case below fails for a reason none of them is testing.
    cp "$PROJECT_ROOT/skills/comment-manager/references/comment-rules.md" \
        "$SANDBOX_CANON/comment-rules.md"
    # The guard itself is not copied: it is not a target, and leaving it out
    # keeps a mutation from being measured against this file's own comments.
    rm -f "$SANDBOX/tests/comment-compliance-guard.sh"
}

# Restores only what a case can mutate, rather than rebuilding the tree. The
# four paths below are the complete set any case touches, and re-copying the
# whole tree per case was most of this suite's runtime on Windows.
reset_sandbox() {
    if [ -z "$SANDBOX" ] || [ ! -d "$SANDBOX" ]; then
        build_sandbox
    fi
    cp "$TESTS_DIR/validate-skills.sh" "$SANDBOX/tests/validate-skills.sh"
    cp "$PROJECT_ROOT/hooks/session-start" "$SANDBOX/hooks/session-start"
    cp "$PROJECT_ROOT/.editorconfig" "$SANDBOX/.editorconfig"
    cp "$PROJECT_ROOT/skills/comment-manager/references/comment-rules.md" \
        "$SANDBOX_CANON/comment-rules.md"
}

TARGET=""
compliance_output() {
    ( cd "$SANDBOX/tests" && bash comment-compliance.sh 2>&1 ) || true
}

compliance_status() {
    local status=0
    ( cd "$SANDBOX/tests" && bash comment-compliance.sh >/dev/null 2>&1 ) \
        || status=$?
    echo "$status"
}

# Negative control. Every case below reads as a pass if the harness cannot run
# at all, so the clean tree is asserted green before anything is planted.
reset_sandbox
assert_exit_status "$(compliance_status)" 0 \
    "an unmutated sandbox -- comment-compliance.sh passes" \
    || true

plant() {
    reset_sandbox
    TARGET="$SANDBOX/tests/validate-skills.sh"
    printf '%s\n' "$1" >> "$TARGET"
}

plant "# $(printf 'x%.0s' {1..90})"
assert_contains "$(compliance_output)" "over 80" \
    "an over-width comment line -- detected" \
    || true

plant "# This note says the value is currently three."
assert_contains "$(compliance_output)" "time-anchored" \
    "a time-anchored word -- detected" \
    || true

plant "# ----------------"
assert_contains "$(compliance_output)" "decorative marker" \
    "a decorative position marker -- detected" \
    || true

plant "# TODO: tighten this later"
assert_contains "$(compliance_output)" "annotation with no owner" \
    "an unowned annotation -- detected" \
    || true

plant "# fi"
assert_contains "$(compliance_output)" "commented-out code" \
    "commented-out code -- detected" \
    || true

# An eight-line paragraph, one over the block ceiling. Planted after a blank
# line so it is a paragraph of its own rather than an extension of the last one.
reset_sandbox
TARGET="$SANDBOX/tests/validate-skills.sh"
printf '\n' >> "$TARGET"
for i in 1 2 3 4 5 6 7 8; do
    printf '# paragraph line %s of eight\n' "$i" >> "$TARGET"
done
printf 'true\n' >> "$TARGET"
assert_contains "$(compliance_output)" "block comment is 8 lines" \
    "a paragraph over the block ceiling -- detected" \
    || true

# A 21-line header, one over the design-rationale carve-out. Written from
# scratch so the file's own one-line header does not shift the count.
reset_sandbox
TARGET="$SANDBOX/tests/validate-skills.sh"
{
    printf '#!/usr/bin/env bash\n'
    for i in $(seq 1 21); do
        printf '# header line %s of twenty-one\n' "$i"
    done
    printf '\ntrue\n'
} > "$TARGET"
assert_contains "$(compliance_output)" "header is 21 lines" \
    "a header over the carve-out -- detected" \
    || true

reset_sandbox
TARGET="$SANDBOX/tests/validate-skills.sh"
printf '}  # end of if\n' >> "$TARGET"
assert_contains "$(compliance_output)" "label on a closing brace" \
    "a closing-brace label -- detected" \
    || true

# The width is configuration, so losing it must fail rather than fall back to a
# hardcoded default that nobody can see or change.
reset_sandbox
sed -i '/max_line_length/d' "$SANDBOX/.editorconfig"
assert_contains "$(compliance_output)" "declares no [*.sh] max_line_length" \
    "a missing width declaration -- detected" \
    || true

# A CRLF .editorconfig. No glob in .gitattributes reaches a dotfile with no
# extension, so `* text=auto` decides it and a Windows checkout with
# core.autocrlf=true gets CRLF. `read` leaves that CR on the value, so the
# section header stops matching and the width reads as absent -- a hard failure
# of the whole suite on the default Git for Windows setting.
reset_sandbox
sed -i 's/$/\r/' "$SANDBOX/.editorconfig"
assert_contains "$(compliance_output)" "declares [*.sh] width 80" \
    "a CRLF .editorconfig -- the width is still read" \
    || true

# A checked file that disappears must fail rather than shrink the run silently,
# the way a dropped suite once did in the aggregator.
reset_sandbox
rm -f "$SANDBOX/hooks/session-start"
assert_contains "$(compliance_output)" "missing or unreadable" \
    "a checked file gone missing -- detected" \
    || true

# Google's shell guide allows a line over the limit when a literal cannot
# sensibly be split, so the code check removes quoted spans before measuring.
# A long CALL has nothing to remove and must still fail, or the carve-out
# becomes a blanket exemption.
plant "aaaa=1; bbbb=2; cccc=3; dddd=4; eeee=5; ffff=6; gggg=7; hhhh=8; iiii=9; jjjj=10; kkkk=11"
assert_contains "$(compliance_output)" "cols of code" \
    "an over-width code line that is not literal-dominated -- detected" \
    || true

# The other half of the carve-out: a line long only because of one unsplittable
# string must NOT be reported, or the check fails 80 lines that Google permits.
plant "echo \"$(printf 'y%.0s' {1..95})\""
assert_not_contains "$(compliance_output)" "cols of code" \
    "an over-width line dominated by a literal -- exempt" \
    || true

# `\"` is an escaped quote CHARACTER, not the start of a literal. Reading it as
# one made the rest of the line look like a string, and an 88-column line of
# pure code passed. This is the false-pass direction, so it gets its own case.
plant 'echo \" && aaaa=1 && bbbb=2 && cccc=3 && dddd=4 && eeee=5 && ffff=6 && gggg=7 && hhhh=88'
assert_contains "$(compliance_output)" "cols of code" \
    "an escaped quote on an over-width code line -- still detected" \
    || true

# The quotes here BALANCE, so the fail-closed path cannot rescue the case and
# only the backslash branch can catch it. Without that distinction the branch
# was deletable with every test still green -- the escaped-quote case above
# is carried by the unterminated-span fallback, not by the branch it names.
plant 'X="a\"" ; aaaa=1 && bbbb=2 && cccc=3 && dddd=4 && eeee=5 && ffff=6 && gggg=7 && hhh=8 ; zz="b\""'
assert_contains "$(compliance_output)" "cols of code" \
    "a balanced escaped quote -- only the backslash branch can catch it" \
    || true

# The backslash branch keeps a code-context escape in the measured text. This
# line is 81 raw with one such escape, so dropping those two characters would
# put it at 79 and exempt it. Without this case that append is deletable with
# every test still green -- the branch is pinned, but only half of it.
plant 'aaaa=1 && bbbb=2 && cccc=3 && dddd=4 && eeee=5 && ffff=6 && gggg=7 && h=\8zzzzzzz'
assert_contains "$(compliance_output)" "cols of code" \
    "a code-context backslash -- its two characters stay measured" \
    || true

# An unterminated quote is measured raw rather than exempted, so a stray
# apostrophe cannot silence the rest of the line.
plant "aaaa=1 # it's over the limit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
assert_contains "$(compliance_output)" "cols of code" \
    "an unterminated quote on an over-width code line -- measured raw" \
    || true

# A hedging term the previous hand-kept list omitted while the canon carried it.
# Detecting it is what proves the list is read from the canon rather than
# restated, since no hardcoded array in this repo ever contained it.
plant "# This approach should work for the common case."
assert_contains "$(compliance_output)" "time-anchored or hedging" \
    "a canon term absent from the old hand-kept list -- detected" \
    || true

# Losing the canon rows must fail loudly. A derived list that quietly empties
# bans nothing while every file still reports clean.
reset_sandbox
sed -i '/^| Speculation and hedging:/d; /^| Time-anchored language:/d' \
    "$SANDBOX_CANON/comment-rules.md"
assert_contains "$(compliance_output)" "banned words, expected 8+" \
    "the canon rows deleted -- the derived list fails closed" \
    || true

# The canon gone entirely, not merely emptied of its rows. Every case here
# mutates with `sed -i`, so a file that disappears was never exercised -- and
# that is how the array behind this floor came to be initialised only after
# the early return, where a missing file left it unset and `set -u` aborted
# before print_summary. The floor message is asserted rather than the exit
# status, because an abort exits non-zero too.
reset_sandbox
rm -f "$SANDBOX_CANON/comment-rules.md"
assert_contains "$(compliance_output)" "banned words, expected 8+" \
    "the canon file deleted -- the floor reports it rather than aborting" \
    || true

# A term is spliced into a regex, so a metacharacter in one matches nothing
# while the floor still counts it. That is a term lost in silence, which is the
# failure the floor exists to prevent, so the shape of a term is checked too.
reset_sandbox
sed -i 's/\*probably\*/*probably.*/' "$SANDBOX_CANON/comment-rules.md"
assert_contains "$(compliance_output)" "not a plain word" \
    "a banned term carrying a metacharacter -- rejected" \
    || true

# A comment run at end-of-file meets no following code line, so the in-loop
# flush never fires for it. Nothing is appended after this block on purpose --
# that is the whole case.
reset_sandbox
TARGET="$SANDBOX/tests/validate-skills.sh"
printf '\n' >> "$TARGET"
for i in 1 2 3 4 5 6 7 8; do
    printf '# trailing paragraph line %s of eight\n' "$i" >> "$TARGET"
done
assert_contains "$(compliance_output)" "block comment is 8 lines" \
    "a paragraph at end-of-file -- still measured" \
    || true

# A backslash ending a single-quoted span. The branch carve-out keeps that span
# closing at its own quote; without it the span runs on to the apostrophe in the
# trailing comment and the rest of the line stops being measured.
plant "x='a\\' && aaaa=1 && bbbb=2 && cccc=3 && dddd=4 && eeee=5 && fff=6 # doesn't matter"
assert_contains "$(compliance_output)" "cols of code" \
    "a backslash ending a single-quoted span -- carve-out keeps it closing" \
    || true

# The `-r` half of the readability guard has no case: an exists-but-unreadable
# file is not expressible on Windows or MSYS, where chmod 000 is a no-op for the
# owner. Stated rather than left implied.

print_summary
