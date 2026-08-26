#!/usr/bin/env bash
# Run all NecturaLabs skill tests.
#
# Suites are declared in required-suites.txt rather than by if-guarded blocks in this file.
# When each registration was its own `if [ -f ... ]` block, a suite could leave the run
# without failing anything -- delete the file, point the guard at a missing path, make the
# call unreachable, comment it out -- and the aggregator still exited 0 with a smaller total
# that nobody reads.
#
# What this file guarantees, stated precisely because an earlier version of this comment
# claimed more than the code delivered:
#   - every declared row is executed, or the run fails;
#   - a declared suite that is missing, empty, or reports no tests fails the run;
#   - the number of suites accounted for at the end equals the number declared, so a loop
#     that ends early cannot leave suites silently unrun;
#   - `--list-suites` prints exactly the paths that would be executed, so a caller can check
#     the run against the manifest without parsing this file for evidence.
#
# What it does NOT guarantee: that a suite's self-reported "N passed" was earned. A suite
# printing a count it did not run is believed here. Per-suite mutation guards cover that.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$TESTS_DIR/required-suites.txt"

MODE="run"
VERBOSE=""
case "${1:-}" in
    --list-suites) MODE="list" ;;
    *) VERBOSE="${1:-}" ;;
esac

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: suite manifest missing at $MANIFEST"
    exit 1
fi

if [ "$MODE" = "run" ]; then
    echo "==================================="
    echo "NecturaLabs Agent Skills Test Suite"
    echo "==================================="
    echo ""
fi

TOTAL_SUITES_PASS=0
TOTAL_SUITES_FAIL=0
TOTAL_TESTS=0
DECLARED=0
SEEN_PATHS=""

run_test_suite() {
    local suite_name="$1"
    local suite_script="$2"
    local flags="${3:-}"

    echo "--- $suite_name ---"

    # A declared suite that is not on disk is a failure, never a skip. The old SKIP path
    # returned 0 and incremented no counter, so a moved entrypoint left the run in silence.
    if [ ! -f "$suite_script" ]; then
        echo "FAIL: $suite_name -- declared in the manifest but not found at $suite_script"
        TOTAL_SUITES_FAIL=$((TOTAL_SUITES_FAIL + 1))
        echo ""
        return 0
    fi

    local output
    local suite_ok=1
    # `</dev/null`: the manifest is read on fd 3, but a suite that reads stdin would still
    # inherit whatever the runner was invoked with. Detaching it keeps a suite from consuming
    # input the runner depends on. $VERBOSE is deliberately unquoted so empty passes no
    # argument, where "$VERBOSE" would pass one empty argument.
    output=$(bash "$suite_script" $VERBOSE </dev/null 2>&1) || suite_ok=0
    echo "$output"

    # `pipefail` is what keeps this numeric when grep matches nothing: its status propagates
    # through the pipe, `|| echo "0"` fires, and suite_tests stays a digit string. `tail -1`
    # keeps a multi-match result single-valued.
    local suite_tests
    suite_tests=$(echo "$output" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1 || echo "0")

    # Force base 10, and treat anything non-numeric as zero. "08" is a valid match but an
    # invalid octal literal, and the arithmetic error it caused used to end the manifest loop
    # outright -- dropping this suite and every suite after it while still exiting 0.
    if ! printf '%s' "$suite_tests" | grep -qE '^[0-9]+$'; then
        suite_tests=0
    fi
    suite_tests=$((10#$suite_tests))
    TOTAL_TESTS=$((TOTAL_TESTS + suite_tests))

    # A suite that exits cleanly while reporting no tests is indistinguishable from one that
    # was emptied. Existence and registration are not execution.
    if [ "$suite_tests" -eq 0 ] && [ "$flags" != "allow_zero" ]; then
        echo "FAIL: $suite_name -- exited cleanly but reported zero tests (emptied or gutted suite?)"
        suite_ok=0
    fi

    # $(( )) assignment, never (( x++ )) -- post-increment from 0 evaluates to 0, a non-zero
    # exit status, which aborts the script under `set -e`.
    if [ "$suite_ok" = "1" ]; then
        TOTAL_SUITES_PASS=$((TOTAL_SUITES_PASS + 1))
    else
        TOTAL_SUITES_FAIL=$((TOTAL_SUITES_FAIL + 1))
    fi
    echo ""
    return 0
}

# fd 3 carries the manifest so that a suite reading stdin cannot consume the remaining rows.
# When the loop read from stdin directly, one suite calling `cat` removed every later suite
# from the run and the aggregator still exited 0.
while IFS='|' read -r suite_name suite_path suite_flags <&3 || [ -n "${suite_name:-}" ]; do
    suite_name=${suite_name%$'\r'}
    suite_path=${suite_path:-}
    suite_path=${suite_path%$'\r'}
    suite_flags=${suite_flags:-}
    suite_flags=${suite_flags%$'\r'}

    # Trim surrounding whitespace so an indented `#` reads as a comment rather than running
    # as a row, and so a padded name does not silently become a different name.
    suite_name=${suite_name#"${suite_name%%[![:space:]]*}"}
    suite_name=${suite_name%"${suite_name##*[![:space:]]}"}

    case "$suite_name" in
        ''|'#'*) continue ;;
    esac

    if [ -z "$suite_path" ]; then
        echo "ERROR: manifest row '$suite_name' declares no script path"
        exit 1
    fi

    # A row names a suite inside tests/. An absolute path, or one containing "..", would
    # execute code outside this directory, which no legitimate row needs.
    case "$suite_path" in
        /*|*..*)
            echo "ERROR: manifest row '$suite_name' has an unsafe path: $suite_path"
            exit 1
            ;;
    esac

    case "$SEEN_PATHS" in
        *"|$suite_path|"*)
            echo "ERROR: manifest declares $suite_path more than once"
            exit 1
            ;;
    esac
    SEEN_PATHS="$SEEN_PATHS|$suite_path|"

    DECLARED=$((DECLARED + 1))

    if [ "$MODE" = "list" ]; then
        echo "$suite_path"
        continue
    fi

    # Fail closed: if the runner itself errors while handling a suite, that suite is counted
    # as failed rather than vanishing from both counters.
    if ! run_test_suite "$suite_name" "$TESTS_DIR/$suite_path" "$suite_flags"; then
        echo "FAIL: $suite_name -- the runner errored while running this suite"
        TOTAL_SUITES_FAIL=$((TOTAL_SUITES_FAIL + 1))
    fi
done 3< "$MANIFEST"

if [ "$DECLARED" -eq 0 ]; then
    echo "ERROR: the suite manifest declares no suites"
    exit 1
fi

if [ "$MODE" = "list" ]; then
    exit 0
fi

# The invariant that makes an early loop exit impossible to miss: every declared suite must
# have landed in exactly one counter.
ACCOUNTED=$((TOTAL_SUITES_PASS + TOTAL_SUITES_FAIL))
if [ "$ACCOUNTED" -ne "$DECLARED" ]; then
    echo "ERROR: $DECLARED suites declared but only $ACCOUNTED accounted for -- the run ended early"
    exit 1
fi

echo "==================================="
echo "Total: $TOTAL_SUITES_PASS suites passed, $TOTAL_SUITES_FAIL suites failed ($TOTAL_TESTS individual tests)"
echo "==================================="

if [ "$TOTAL_SUITES_FAIL" -gt 0 ]; then
    exit 1
fi

if [ "$TOTAL_TESTS" -eq 0 ]; then
    echo "ERROR: Zero tests ran across all suites"
    exit 1
fi
