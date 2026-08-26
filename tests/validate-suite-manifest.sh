#!/usr/bin/env bash
# Guards the suite manifest that run-all.sh registers from.
#
# Matching suite names as text inside run-all.sh was defeatable six ways -- an inline
# comment, a dead string, a here-doc, a broken `-f` guard, `if false &&`, a `true #` prefix
# -- each leaving the name in the file while the suite stopped running. Source text is the
# wrong evidence for execution, so this checks the manifest and checks the runner by running
# it in --list-suites mode.
#
# Asserted: every required suite is declared; every declared suite exists inside tests/ once
# symlinks are resolved; allow_zero appears only on the row entitled to it, an unrestricted
# bypass switch being how the hole it closed got reopened; every shell script under tests/
# bar the runner and its helpers is declared; and run-all.sh executes exactly the declared
# set.
#
# Residuals: this script is a manifest row, so deleting that row would stop it running -- CI
# runs it as its own step, because a guard registered only in the artifact it guards cannot
# enforce its own registration. A suite reporting a count it did not earn is believed by the
# aggregator.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_REAL="$(cd "$TESTS_DIR" && pwd -P)"
source "$TESTS_DIR/test-helpers.sh"

echo "Validating test suite manifest..."

MANIFEST="$TESTS_DIR/required-suites.txt"
RUNNER="$TESTS_DIR/run-all.sh"

# A suite listed here must be declared in the manifest. Removing one is a deliberate decision
# that shows up in review; forgetting one is caught by the suite-shaped-file sweep below.
REQUIRED_SUITES=(
    "skill-triggering/run-all.sh"
    "validate-skills.sh"
    "validate-house-rules.sh"
    "house-rules-guard.sh"
    "validate-comment-rules.sh"
    "comment-rules-guard.sh"
    "validate-suite-manifest.sh"
    "runner-guard.sh"
)

# The only row permitted to carry allow_zero, and only because SKIP_LIVE_TESTS skips every
# case in it.
ZERO_EXEMPT="skill-triggering/run-all.sh"

# The "/" and ".." checks below inspect the literal string only, while `[ -f ]` follows
# symlinks: a declared tests/x.sh -> ../outside/evil.sh passed every string test and ran.
resolves_inside_tests() {
    local target="$1" resolved
    resolved=$(readlink -f "$target" 2>/dev/null || realpath "$target" 2>/dev/null || printf '%s' "$target")
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
    # `|| true` then an explicit exit: print_summary returns 1 with FAIL_COUNT set, and under
    # `set -e` that would terminate here, making a bare `exit 1` below it dead code.
    print_summary || true
    exit 1
fi

if [ ! -f "$RUNNER" ]; then
    fail "run-all.sh is missing at $RUNNER"
    print_summary || true
    exit 1
fi

# Deliberately NOT a text match. An earlier version grepped run-all.sh for the manifest
# filename, and run-all.sh's own header comment satisfied that grep: repointing MANIFEST= at
# a different file left the string present, this check green, and five suites silently not
# running. --list-suites reports the paths the runner would actually execute, so the two lists
# diverge the moment it stops using this manifest.
RUNNER_LIST_STATUS=0
RUNNER_LISTED=$(bash "$RUNNER" --list-suites 2>/dev/null) || RUNNER_LIST_STATUS=$?

# A runner that fails in list mode is a finding in its own right. Swallowing the status left an
# unsafe-path row registering only as a list mismatch, and a duplicated row registering as
# nothing at all -- the duplicate is `continue`d before it reaches the comparison list.
if [ "$RUNNER_LIST_STATUS" -ne 0 ]; then
    fail "run-all.sh --list-suites exited $RUNNER_LIST_STATUS -- it cannot enumerate its own suites"
else
    pass "run-all.sh enumerates its suites without error"
fi

# Defined before the loop that calls it: bash resolves functions at call time, so a definition
# placed after its first call leaves that call exiting 127 -- the duplicate-row check below was
# dead code printing "command not found" once per row while failing nothing.
declared_contains() {
    local needle="$1" entry
    for entry in ${DECLARED_PATHS+"${DECLARED_PATHS[@]}"}; do
        [ "$entry" = "$needle" ] && return 0
    done
    return 1
}

DECLARED_PATHS=()
DECLARED_COUNT=0

while IFS='|' read -r suite_name suite_path suite_flags || [ -n "${suite_name:-}" ]; do
    suite_name=${suite_name%$'\r'}
    suite_path=${suite_path:-}
    suite_path=${suite_path%$'\r'}
    suite_flags=${suite_flags:-}
    suite_flags=${suite_flags%$'\r'}

    case "$suite_name" in
        ''|'#'*) continue ;;
    esac

    DECLARED_COUNT=$((DECLARED_COUNT + 1))

    if [ -z "$suite_path" ]; then
        fail "manifest row '$suite_name' declares no script path"
        continue
    fi

    # A row names a suite inside tests/. An absolute path or one containing ".." would run
    # code from outside the directory this manifest governs.
    case "$suite_path" in
        /*|*..*)
            fail "$suite_path -- row '$suite_name' uses an absolute path or escapes tests/"
            continue
            ;;
    esac

    # Case-insensitive, matching run-all.sh: on Windows and macOS two rows differing only by
    # case name one file. When only the runner folded case, the variant reached this script's
    # happy path and failed elsewhere, incidentally.
    suite_key=$(printf '%s' "$suite_path" | tr '[:upper:]' '[:lower:]')
    if declared_contains "$suite_key"; then
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

    if [ -n "$suite_flags" ] && [ "$suite_flags" != "allow_zero" ]; then
        fail "$suite_path -- unknown manifest flag '$suite_flags'"
        continue
    fi

    if [ "$suite_flags" = "allow_zero" ] && [ "$suite_path" != "$ZERO_EXEMPT" ]; then
        fail "$suite_path -- carries allow_zero, which only $ZERO_EXEMPT may have"
        continue
    fi

    DECLARED_PATHS+=("$suite_key")
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

# The runner must execute exactly what this manifest declares. Comparing the two sorted lists
# catches a runner reading a different manifest, a row it skips, and a row it invents.
DECLARED_SORTED=$(printf '%s\n' ${DECLARED_PATHS+"${DECLARED_PATHS[@]}"} | sed '/^$/d' | sort)
LISTED_SORTED=$(printf '%s\n' "$RUNNER_LISTED" | sed '/^$/d' | sort)

if [ -z "$LISTED_SORTED" ]; then
    fail "run-all.sh --list-suites produced nothing -- the runner is not reading this manifest"
elif [ "$DECLARED_SORTED" != "$LISTED_SORTED" ]; then
    fail "run-all.sh executes a different set of suites than this manifest declares"
    echo "    manifest declares:"
    printf '      %s\n' $DECLARED_SORTED
    echo "    runner would execute:"
    printf '      %s\n' $LISTED_SORTED
else
    pass "run-all.sh executes exactly the declared suites"
fi

# Sweep every shell script under tests/, not two filename shapes. The previous two-glob
# allowlist missed tests/check-thing.sh and tests/sub/validate-thing.sh entirely: a suite
# added and never declared never runs, which is the same end state as deleting it.
NON_SUITE_FILES=(
    "run-all.sh"
    "test-helpers.sh"
)

while IFS= read -r candidate; do
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
done < <(find "$TESTS_DIR" \( -type f -o -type l \) -name '*.sh' | sort)

print_summary
