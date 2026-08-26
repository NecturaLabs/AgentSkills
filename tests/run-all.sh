#!/usr/bin/env bash
# Run all NecturaLabs skill tests.
#
# Suites are declared in required-suites.txt, not by if-guarded blocks in this file. When each
# registration was its own `if [ -f ... ]` block, a suite could leave the run without failing
# anything, and every one of these was reproduced against this harness: delete the file; point
# the `-f` guard at a path that does not exist while leaving the call intact; make the call
# unreachable with `if false &&`; prefix it with `true #`; or delete it and leave any text
# elsewhere in the file that still mentioned the name. The aggregator exited 0 each time, with
# a smaller total that nobody reads.
#
# Driving registration from the manifest removes that whole class: a declared suite either
# runs, or the run fails. There is no second place where a suite is named, so there is no
# mismatch to exploit.
#
# Residual, stated rather than hidden: the per-suite test count is self-reported, so a suite
# printing a count it had not earned would still be believed here. What proves an individual
# suite can actually fail is its own mutation guard, not this aggregator.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE="${1:-}"
MANIFEST="$TESTS_DIR/required-suites.txt"

echo "==================================="
echo "NecturaLabs Agent Skills Test Suite"
echo "==================================="
echo ""

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: suite manifest missing at $MANIFEST"
    exit 1
fi

TOTAL_SUITES_PASS=0
TOTAL_SUITES_FAIL=0
TOTAL_TESTS=0

run_test_suite() {
    local suite_name="$1"
    local suite_script="$2"
    local flags="${3:-}"

    echo "--- $suite_name ---"

    # A declared suite that is not on disk is a failure, never a skip. The old SKIP path
    # returned 0 and incremented no counter, so moving or renaming an entrypoint removed the
    # suite from the run in silence.
    if [ ! -f "$suite_script" ]; then
        echo "FAIL: $suite_name -- declared in the manifest but not found at $suite_script"
        TOTAL_SUITES_FAIL=$((TOTAL_SUITES_FAIL + 1))
        echo ""
        return 0
    fi

    local output
    local suite_ok=1
    # $VERBOSE is deliberately unquoted: empty must pass no argument at all, where "$VERBOSE"
    # would pass one empty argument instead.
    output=$(bash "$suite_script" $VERBOSE 2>&1) || suite_ok=0
    echo "$output"

    # `pipefail` is load-bearing here, not `tail -1`: when grep matches nothing its non-zero
    # status propagates through the pipe, `|| echo "0"` fires, and suite_tests stays numeric.
    # Without pipefail suite_tests would be empty, and `[ "" -eq 0 ]` exits 2 -- silently
    # disabling the zero-test check below rather than failing loudly. `tail -1` is what keeps
    # a multi-match result a single integer.
    local suite_tests
    suite_tests=$(echo "$output" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1 || echo "0")
    TOTAL_TESTS=$((TOTAL_TESTS + suite_tests))

    # A suite that exits cleanly while reporting no tests is indistinguishable from one that
    # was emptied: truncating a suite to zero bytes used to pass every gate and move only the
    # total. Existence and registration are not execution.
    if [ "$suite_tests" -eq 0 ] && [ "$flags" != "allow_zero" ]; then
        echo "FAIL: $suite_name -- exited cleanly but reported zero tests (emptied or gutted suite?)"
        suite_ok=0
    fi

    # $(( )) assignment, never (( x++ )) -- post-increment from 0 evaluates to 0, which is a
    # non-zero exit status and aborts the script under `set -e`.
    if [ "$suite_ok" = "1" ]; then
        TOTAL_SUITES_PASS=$((TOTAL_SUITES_PASS + 1))
    else
        TOTAL_SUITES_FAIL=$((TOTAL_SUITES_FAIL + 1))
    fi
    echo ""
}

DECLARED=0
# `|| [ -n "$suite_name" ]` keeps a final line with no trailing newline. CR is stripped from
# every field so a CRLF checkout does not turn a path into one that cannot be found.
while IFS='|' read -r suite_name suite_path suite_flags || [ -n "${suite_name:-}" ]; do
    suite_name=${suite_name%$'\r'}
    suite_path=${suite_path:-}
    suite_path=${suite_path%$'\r'}
    suite_flags=${suite_flags:-}
    suite_flags=${suite_flags%$'\r'}

    case "$suite_name" in
        ''|'#'*) continue ;;
    esac

    if [ -z "$suite_path" ]; then
        echo "ERROR: manifest row '$suite_name' declares no script path"
        exit 1
    fi

    DECLARED=$((DECLARED + 1))
    run_test_suite "$suite_name" "$TESTS_DIR/$suite_path" "$suite_flags"
done < "$MANIFEST"

if [ "$DECLARED" -eq 0 ]; then
    echo "ERROR: the suite manifest declares no suites"
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
