#!/usr/bin/env bash
# Guards the suite manifest that run-all.sh registers from.
#
# Matching suite names as text inside run-all.sh was defeatable six ways -- an
# inline comment, a dead string, a here-doc, a broken `-f` guard, `if false &&`,
# a `true #` prefix -- each leaving the name in the file while the suite stopped
# running. Source text is the wrong evidence for execution, so this checks the
# manifest and checks the runner by running it in --list-suites mode.
#
# Asserted: every required suite is declared; every declared suite exists inside
# tests/ once symlinks are resolved; no row carries a flag, since none is
# defined and an unrestricted bypass switch is how the zero-test hole was
# reopened once; every shell script under tests/ bar the runner and its helpers
# is declared; and run-all.sh executes exactly the declared set.
#
# Residuals: this script is a manifest row, so deleting that row would stop it
# running -- CI runs it as its own step, because a guard registered only in the
# artifact it guards cannot enforce its own registration. A suite reporting a
# count it did not earn is believed by the aggregator.

set -euo pipefail

# `cd` and $PWD are builtins, so this derives an absolute path without the
# fork a `$(cd ... && pwd)` substitution costs, and CDPATH is cleared because
# a set one sends `cd` somewhere else and echoes where it landed.
# test-helpers.sh states what one process costs in this suite.
#
# `set +f` for the same reason: bash imports SHELLOPTS from its environment,
# and an inherited `noglob` leaves the `**` sweep below matching nothing --
# an undeclared suite invisible with this check still reporting green. The
# `find` that sweep replaced could not be switched off that way.
CDPATH=""
set +f
_PREV_PWD=$PWD
cd "${BASH_SOURCE[0]%/*}" 2>/dev/null || cd "$_PREV_PWD"
TESTS_DIR=$PWD
cd "$_PREV_PWD"
cd -P "$TESTS_DIR"
TESTS_REAL=$PWD
cd "$_PREV_PWD"
source "$TESTS_DIR/test-helpers.sh"

echo "Validating test suite manifest..."

MANIFEST="$TESTS_DIR/required-suites.txt"
RUNNER="$TESTS_DIR/run-all.sh"

# A suite listed here must be declared in the manifest. Removing one is a
# deliberate decision that shows up in review; forgetting one is caught by the
# suite-shaped-file sweep below.
REQUIRED_SUITES=(
    "validate-skills.sh"
    "validate-house-rules.sh"
    "house-rules-guard.sh"
    "validate-comment-rules.sh"
    "comment-rules-guard.sh"
    "comment-compliance.sh"
    "comment-compliance-guard.sh"
    "hook-guard.sh"
    "validate-suite-manifest.sh"
    "runner-guard.sh"
)

# The "/" and ".." checks below inspect the literal string only, while `[ -f ]`
# follows symlinks: a declared tests/x.sh -> ../outside/evil.sh passed every
# string test and ran.
resolves_inside_tests() {
    local target="$1" resolved
    # A file that is not itself a link, named directly inside tests/, cannot
    # reach outside it. The resolver costs a process, so it runs only where a
    # link can be: on the target itself, or on a directory component of a
    # nested row -- which the manifest has carried before and may again.
    #
    # The fast path anchors on TESTS_DIR and the slow path on TESTS_REAL. They
    # cannot disagree: TESTS_REAL is defined as TESTS_DIR resolved, so a tests/
    # reached through a symlink lands inside either way.
    if [ ! -L "$target" ] && [ "${target%/*}" = "$TESTS_DIR" ]; then
        return 0
    fi
    resolved=$(readlink -f "$target" 2>/dev/null \
        || realpath "$target" 2>/dev/null \
        || printf '%s' "$target")
    case "$resolved" in
        "$TESTS_REAL"/*) return 0 ;;
        *) return 1 ;;
    esac
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

if [ ! -f "$MANIFEST" ]; then
    fail "required-suites.txt is missing at $MANIFEST"
    # `|| true` then an explicit exit: print_summary returns 1 with FAIL_COUNT
    # set, and under `set -e` that would terminate here, making a bare `exit 1`
    # below it dead code.
    print_summary || true
    exit 1
fi

if [ ! -f "$RUNNER" ]; then
    fail "run-all.sh is missing at $RUNNER"
    print_summary || true
    exit 1
fi

# Deliberately NOT a text match. An earlier version grepped run-all.sh for the
# manifest filename, and run-all.sh's own header comment satisfied that grep:
# repointing MANIFEST= at a different file left the string present, this check
# green, and five suites silently not running. --list-suites reports the paths
# the runner would actually execute, so the two lists diverge the moment it
# stops using this manifest.
RUNNER_LIST_STATUS=0
RUNNER_LISTED=$(bash "$RUNNER" --list-suites 2>/dev/null) \
    || RUNNER_LIST_STATUS=$?

# A runner that fails in list mode is a finding in its own right. Swallowing the
# status left an unsafe-path row registering only as a list mismatch, and a
# duplicated row registering as nothing at all -- the duplicate is `continue`d
# before it reaches the comparison list.
if [ "$RUNNER_LIST_STATUS" -ne 0 ]; then
    fail "run-all.sh --list-suites exited $RUNNER_LIST_STATUS -- it cannot enumerate its own suites"
else
    pass "run-all.sh enumerates its suites without error"
fi

# ASCII-only case fold. Both `${x,,}` and `tr` go through the C library, and
# under a Turkish locale `I` folds to a dotless `i`, so two rows naming one file
# on a case-insensitive filesystem stopped comparing equal and the duplicate
# went undetected. The alphabet is spelled out here so the comparison cannot
# depend on a locale at all.
ascii_lower() {
    local s="$1" ch head i
    local up=ABCDEFGHIJKLMNOPQRSTUVWXYZ
    local lo=abcdefghijklmnopqrstuvwxyz

    ASCII_LOWER=""
    for ((i = 0; i < ${#s}; i++)); do
        ch=${s:i:1}
        head=${up%%"$ch"*}
        if [ "${#head}" -lt "${#up}" ]; then
            ch=${lo:${#head}:1}
        fi
        ASCII_LOWER="$ASCII_LOWER$ch"
    done
}

# Defined before the loop that calls it: bash resolves functions at call time,
# so a definition placed after its first call leaves that call exiting 127 --
# the duplicate-row check below was dead code printing "command not found" once
# per row while failing nothing.
key_declared() {
    local needle="$1" entry
    for entry in ${DECLARED_KEYS+"${DECLARED_KEYS[@]}"}; do
        [ "$entry" = "$needle" ] && return 0
    done
    return 1
}

declared_contains() {
    local needle="$1" entry
    for entry in ${DECLARED_PATHS+"${DECLARED_PATHS[@]}"}; do
        [ "$entry" = "$needle" ] && return 0
    done
    return 1
}

DECLARED_PATHS=()
DECLARED_KEYS=()
DECLARED_COUNT=0

while IFS='|' read -r suite_name suite_path suite_flags \
        || [ -n "${suite_name:-}" ]; do
    suite_name=${suite_name%$'\r'}
    suite_path=${suite_path:-}
    suite_path=${suite_path%$'\r'}
    suite_flags=${suite_flags:-}
    suite_flags=${suite_flags%$'\r'}

    # Trim and BOM handling mirror run-all.sh exactly. When they differed, an
    # indented '#' was a comment to the runner and a malformed row to its own
    # guard -- one manifest, two readings, and a build red for the wrong reason.
    suite_name=${suite_name#$'\xef\xbb\xbf'}
    suite_name=${suite_name#"${suite_name%%[![:space:]]*}"}
    suite_name=${suite_name%"${suite_name##*[![:space:]]}"}

    case "$suite_name" in
        ''|'#'*) continue ;;
    esac

    DECLARED_COUNT=$((DECLARED_COUNT + 1))

    if [ -z "$suite_path" ]; then
        fail "manifest row '$suite_name' declares no script path"
        continue
    fi

    # A row names a suite inside tests/. An absolute path or one containing ".."
    # would run code from outside the directory this manifest governs.
    case "$suite_path" in
        /*|*..*)
            fail "$suite_path -- row '$suite_name' uses an absolute path or escapes tests/"
            continue
            ;;
    esac

    # Case-insensitive, matching run-all.sh: on Windows and macOS two rows
    # differing only by case name one file. When only the runner folded case,
    # the variant reached this script's happy path and failed elsewhere,
    # incidentally.
    ascii_lower "$suite_path"
    suite_key=$ASCII_LOWER
    if key_declared "$suite_key"; then
        fail "$suite_path -- declared more than once; the run would execute it twice and double-count it"
        continue
    fi

    if [ ! -f "$TESTS_DIR/$suite_path" ]; then
        fail "$suite_path -- declared in the manifest but missing on disk"
        continue
    fi

    if ! resolves_inside_tests "$TESTS_DIR/$suite_path"; then
        fail "$suite_path -- resolves outside the tests directory once symlinks are followed"
        continue
    fi

    if [ -n "$suite_flags" ]; then
        fail "$suite_path -- unknown manifest flag '$suite_flags'; no flag is defined"
        continue
    fi

    DECLARED_PATHS+=("$suite_path")
    DECLARED_KEYS+=("$suite_key")
    pass "$suite_path -- declared and present"
done < "$MANIFEST"

if [ "$DECLARED_COUNT" -eq 0 ]; then
    fail "the manifest declares no suites"
fi

for suite in "${REQUIRED_SUITES[@]}"; do
    if declared_contains "$suite"; then
        pass "$suite -- required and declared"
    else
        fail "$suite -- required by this repo but absent from the manifest"
    fi
done

# The runner must execute exactly what this manifest declares.
#
# Compared as sets in the shell, not by sorting both lists: `printf | sed |
# sort` twice cost six processes to order ten rows, and runner-guard.sh runs
# this script once per case. Membership each way plus a length check catches
# what ordering caught -- a row the runner skips, one it invents, a manifest
# it is not reading, and a row it would run twice.
LISTED_PATHS=()
listed_remaining="$RUNNER_LISTED"
while [ -n "$listed_remaining" ]; do
    listed_line="${listed_remaining%%$'\n'*}"
    if [ "$listed_line" = "$listed_remaining" ]; then
        listed_remaining=""
    else
        listed_remaining="${listed_remaining#*$'\n'}"
    fi
    if [ -n "$listed_line" ]; then
        LISTED_PATHS+=("$listed_line")
    fi
done

listed_contains() {
    local needle="$1" entry
    for entry in ${LISTED_PATHS+"${LISTED_PATHS[@]}"}; do
        [ "$entry" = "$needle" ] && return 0
    done
    return 1
}

LIST_MISMATCH=0
for entry in ${DECLARED_PATHS+"${DECLARED_PATHS[@]}"}; do
    listed_contains "$entry" || LIST_MISMATCH=1
done
for entry in ${LISTED_PATHS+"${LISTED_PATHS[@]}"}; do
    declared_contains "$entry" || LIST_MISMATCH=1
done
if [ "${#LISTED_PATHS[@]}" -ne "${#DECLARED_PATHS[@]}" ]; then
    LIST_MISMATCH=1
fi

if [ "${#LISTED_PATHS[@]}" -eq 0 ]; then
    fail "run-all.sh --list-suites produced nothing -- the runner is not reading this manifest"
elif [ "$LIST_MISMATCH" = "1" ]; then
    fail "run-all.sh executes a different set of suites than this manifest declares"
    echo "    manifest declares:"
    printf '      %s\n' ${DECLARED_PATHS+"${DECLARED_PATHS[@]}"}
    echo "    runner would execute:"
    printf '      %s\n' ${LISTED_PATHS+"${LISTED_PATHS[@]}"}
else
    pass "run-all.sh executes exactly the declared suites"
fi

# Sweep every shell script under tests/, not two filename shapes. The previous
# two-glob allowlist missed tests/check-thing.sh and tests/sub/validate-thing.sh
# entirely: a suite added and never declared never runs, which is the same end
# state as deleting it.
NON_SUITE_FILES=(
    "run-all.sh"
    "test-helpers.sh"
)

# `**` with globstar reaches the same files `find` did, at no process. It
# matches a nested path and a top-level one alike, and it matches by name, so
# a symlink -- which `find -type f` misses and a declared row can still be --
# is still offered here.
#
# `dotglob` is not optional: without it neither a dot-named `.evil.sh` nor
# anything under a dot-directory is swept, and an undeclared suite hidden
# either way ran with this check still green. `nullglob` stops an empty tests/
# iterating the pattern itself. All three are dropped again below so no later
# glob in this file inherits them.
shopt -s globstar nullglob dotglob
for candidate in "$TESTS_DIR"/**/*.sh; do
    [ -f "$candidate" ] || [ -L "$candidate" ] || continue
    rel=${candidate#"$TESTS_DIR/"}

    skip=0
    for allowed in "${NON_SUITE_FILES[@]}"; do
        if [ "$rel" = "$allowed" ]; then
            skip=1
            break
        fi
    done
    [ "$skip" = "1" ] && continue

    if declared_contains "$rel"; then
        continue
    fi

    fail "$rel -- a shell script under tests/ that no manifest row declares"
done
shopt -u globstar nullglob dotglob

print_summary
