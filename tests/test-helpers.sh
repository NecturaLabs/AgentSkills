#!/usr/bin/env bash
# Test helper functions for NecturaLabs skill tests.
#
# What a process costs here, measured on Windows and Git Bash: a fork alone
# about a sixth of a second, an external binary about a fifth, and `bash
# script` about a third. Reading a whole file through a redirect costs a
# fiftieth of that and a string operation nothing at all. Four dozen
# assertions and scores of validator runs per guard is what turns those
# fractions into minutes.
#
# So: no `dirname`, no `basename`, no `grep` for a substring the shell can
# test, and the file helpers below in place of `cp`, `sed` and `cmp`. A
# pipeline that reads clean and costs one process is fine; one that costs a
# process per line, per phrase or per file is not.

set -euo pipefail

# `cd` and $PWD are builtins, so an absolute path costs no process here, where
# the `$(cd ... && pwd)` substitution this replaces forked once per source.
# CDPATH is cleared because a set one sends `cd` somewhere else and echoes
# where it landed.
#
# Derived from BASH_SOURCE every time, never from an inherited TESTS_DIR. That
# reuse saved nothing once this became fork-free, and it let an exported
# TESTS_DIR from outside the suite repoint PROJECT_ROOT for every file that
# sources this.
CDPATH=""
_HELPERS_PREV_PWD=$PWD
cd "${BASH_SOURCE[0]%/*}" 2>/dev/null || cd "$_HELPERS_PREV_PWD"
_HELPERS_DIR=$PWD
cd "$_HELPERS_PREV_PWD"
PROJECT_ROOT="${_HELPERS_DIR%/*}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Assert output contains a string
assert_contains() {
    local output="$1"
    local expected="$2"
    local test_name="${3:-assertion}"

    # A literal substring test in the shell, not `echo | grep -qF`: that forked
    # twice on each of the four dozen assertions a run makes through these two
    # helpers. Quoting $expected inside the pattern is what keeps the match
    # literal, which is the job -F did.
    if [[ $output == *"$expected"* ]]; then
        echo -e "${GREEN}PASS${NC}: $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $test_name -- expected to contain: $expected"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

# Assert output does NOT contain a string
assert_not_contains() {
    local output="$1"
    local unexpected="$2"
    local test_name="${3:-assertion}"

    # Literal, for the reason assert_contains states. The two must decide
    # containment the same way, or one of them reports on a string the other
    # never saw.
    if [[ $output == *"$unexpected"* ]]; then
        echo -e "${RED}FAIL${NC}: $test_name -- should not contain: $unexpected"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    else
        echo -e "${GREEN}PASS${NC}: $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    fi
}

# Assert a command exited with an expected status
assert_exit_status() {
    local actual="$1"
    local expected="$2"
    local test_name="${3:-exit status}"

    if [ "$actual" -eq "$expected" ]; then
        echo -e "${GREEN}PASS${NC}: $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $test_name -- expected exit $expected, got $actual"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

# Read a whole file into READ_RESULT.
#
# `$(<file)` is bash's own no-fork read but strips trailing newlines, and the
# guards write back what they read. `read -d ''` keeps them, and reports EOF
# as a failure on every file with no NUL in it, so the status is discarded.
#
# Looped rather than read once, because `read -d ''` also stops AT a NUL and
# reports that the same way: a single one would have truncated the result in
# silence, and write_file writes that result back as a guard's restore. The
# NUL bytes themselves are the only thing dropped, and no file this suite
# reads carries one.
read_file() {
    local chunk=""

    READ_RESULT=""
    while IFS= read -r -d '' chunk; do
        READ_RESULT="$READ_RESULT$chunk"
    done < "$1"
    READ_RESULT="$READ_RESULT$chunk"
}

# Write text to a file, replacing what was there.
write_file() {
    printf '%s' "$2" > "$1"
}

# Replace every occurrence of a literal needle, into REPLACE_RESULT.
#
# `${var//pat/rep}` reads its pattern as a glob, so an anchor carrying `*` or
# `[` would match the wrong text. Consuming the input keeps the match literal,
# and appending to the output rather than rescanning it lets a replacement
# contain the needle -- which one mutation case does on purpose.
#
# REPLACE_COUNT replaces the `cmp` the guards used to run: zero means the
# anchor no longer matches anything, which is a stale case rather than a
# passing one. A caller whose assertion would still pass over an unchanged
# file has to check it; one whose assertion fails closed need not.
replace_all() {
    local haystack="$1" needle="$2" replacement="$3"

    REPLACE_RESULT="$haystack"
    REPLACE_COUNT=0
    # An empty needle matches at every position and consumes nothing, so the
    # loop below would never end -- a hung guard times CI out instead of
    # reporting. A caller reaching this has a malformed case, and a zero count
    # is already what the guards report as an anchor that no longer matches.
    if [ -z "$needle" ]; then
        return 0
    fi

    REPLACE_RESULT=""
    while [[ $haystack == *"$needle"* ]]; do
        REPLACE_RESULT="$REPLACE_RESULT${haystack%%"$needle"*}$replacement"
        haystack="${haystack#*"$needle"}"
        REPLACE_COUNT=$((REPLACE_COUNT + 1))
    done
    REPLACE_RESULT="$REPLACE_RESULT$haystack"
}

# Rewrite whole lines starting with a literal prefix, into REPLACE_RESULT.
#
# This is `sed`'s `/^x/c` and, for an empty replacement, its `/^x/d`. Every
# line of the result ends in a newline, so a file whose last line carried none
# gains one -- true of no file any caller passes here.
replace_line_prefix() {
    local text="$1" prefix="$2" replacement="$3" line out=""

    REPLACE_COUNT=0
    while [ -n "$text" ]; do
        line="${text%%$'\n'*}"
        if [ "$line" = "$text" ]; then
            text=""
        else
            text="${text#*$'\n'}"
        fi

        if [ "${line#"$prefix"}" != "$line" ]; then
            REPLACE_COUNT=$((REPLACE_COUNT + 1))
            if [ -z "$replacement" ]; then
                continue
            fi
            line="$replacement"
        fi
        out="$out$line"$'\n'
    done
    REPLACE_RESULT="$out"
}

# Print test summary
print_summary() {
    echo ""
    echo "================================"
    echo -e "Results: ${GREEN}$PASS_COUNT passed${NC}, ${RED}$FAIL_COUNT failed${NC}, ${YELLOW}$SKIP_COUNT skipped${NC}"
    echo "================================"

    if [ "$FAIL_COUNT" -gt 0 ]; then
        return 1
    fi
    return 0
}
