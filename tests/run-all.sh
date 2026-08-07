#!/usr/bin/env bash
# Run all NecturaLabs skill tests

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE="${1:-}"

echo "==================================="
echo "NecturaLabs Agent Skills Test Suite"
echo "==================================="
echo ""

TOTAL_SUITES_PASS=0
TOTAL_SUITES_FAIL=0
TOTAL_TESTS=0

run_test_suite() {
    local suite_name="$1"
    local suite_script="$2"

    if [ ! -f "$suite_script" ]; then
        echo "SKIP: $suite_name -- script not found"
        return 0
    fi

    echo "--- $suite_name ---"
    local output
    if output=$(bash "$suite_script" $VERBOSE 2>&1); then
        # $(( )) assignment, never (( x++ )) -- post-increment from 0 evaluates to 0,
        # which is a non-zero exit status and aborts the script under `set -e`.
        TOTAL_SUITES_PASS=$((TOTAL_SUITES_PASS + 1))
    else
        TOTAL_SUITES_FAIL=$((TOTAL_SUITES_FAIL + 1))
    fi
    echo "$output"

    # Extract individual test count from suite output (matches "X passed" pattern).
    # tail -1 keeps this a single integer -- a multi-line value would make the
    # $(( )) below a bash syntax error and abort the run under `set -e`.
    local suite_tests
    suite_tests=$(echo "$output" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1 || echo "0")
    TOTAL_TESTS=$((TOTAL_TESTS + suite_tests))
    echo ""
}

# Skill triggering tests
if [ -d "$TESTS_DIR/skill-triggering" ]; then
    run_test_suite "Skill Triggering" "$TESTS_DIR/skill-triggering/run-all.sh"
fi

# Skill content validation
if [ -f "$TESTS_DIR/validate-skills.sh" ]; then
    run_test_suite "Skill Validation" "$TESTS_DIR/validate-skills.sh"
fi

# Command structure validation
if [ -f "$TESTS_DIR/validate-commands.sh" ]; then
    run_test_suite "Command Validation" "$TESTS_DIR/validate-commands.sh"
fi

# Aggregation self-check (runs this script against stub suites -- see runner-guard.sh)
if [ -f "$TESTS_DIR/runner-guard.sh" ]; then
    run_test_suite "Runner Guard" "$TESTS_DIR/runner-guard.sh"
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
