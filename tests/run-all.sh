#!/usr/bin/env bash
# Run all NecturaLabs skill tests

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE="${1:-}"

echo "==================================="
echo "NecturaLabs Agent Skills Test Suite"
echo "==================================="
echo ""

TOTAL_PASS=0
TOTAL_FAIL=0

run_test_suite() {
    local suite_name="$1"
    local suite_script="$2"

    if [ ! -f "$suite_script" ]; then
        echo "SKIP: $suite_name -- script not found"
        return 0
    fi

    echo "--- $suite_name ---"
    if bash "$suite_script" $VERBOSE; then
        ((TOTAL_PASS++))
    else
        ((TOTAL_FAIL++))
    fi
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

echo "==================================="
echo "Total: $TOTAL_PASS suites passed, $TOTAL_FAIL suites failed"
echo "==================================="

[ "$TOTAL_FAIL" -eq 0 ]
