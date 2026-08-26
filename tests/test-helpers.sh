#!/usr/bin/env bash
# Test helper functions for NecturaLabs skill tests

set -euo pipefail

_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$_HELPERS_DIR/.." && pwd)"

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

    # -F: callers pass literal expected text, not patterns
    if echo "$output" | grep -qF -- "$expected"; then
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

    # -F: callers pass literal unexpected text, not patterns
    if echo "$output" | grep -qF -- "$unexpected"; then
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
