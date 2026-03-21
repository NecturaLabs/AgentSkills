#!/usr/bin/env bash
# Test helper functions for NecturaLabs skill tests

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Run claude with a prompt and capture output
run_claude() {
    local prompt="$1"
    local timeout="${2:-120}"
    timeout "$timeout" claude -p "$prompt" --output-format stream-json 2>/dev/null || true
}

# Assert output contains a string
assert_contains() {
    local output="$1"
    local expected="$2"
    local test_name="${3:-assertion}"

    if echo "$output" | grep -q "$expected"; then
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

    if echo "$output" | grep -q "$unexpected"; then
        echo -e "${RED}FAIL${NC}: $test_name -- should not contain: $unexpected"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    else
        echo -e "${GREEN}PASS${NC}: $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    fi
}

# Assert a skill was invoked
assert_skill_invoked() {
    local output="$1"
    local skill_name="$2"
    local test_name="${3:-skill invocation}"

    if echo "$output" | grep -q "\"name\":\"Skill\"" && echo "$output" | grep -q "$skill_name"; then
        echo -e "${GREEN}PASS${NC}: $test_name -- skill '$skill_name' was invoked"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $test_name -- skill '$skill_name' was NOT invoked"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

# Assert skill was invoked BEFORE any other tool
assert_skill_invoked_first() {
    local output="$1"
    local skill_name="$2"
    local test_name="${3:-skill priority}"

    local first_tool
    first_tool=$(echo "$output" | grep -o '"name":"[^"]*"' | head -1)

    if echo "$first_tool" | grep -q "Skill"; then
        echo -e "${GREEN}PASS${NC}: $test_name -- skill invoked before other tools"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $test_name -- other tools invoked before skill: $first_tool"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

# Create a temporary test project
create_test_project() {
    local project_name="${1:-test-project}"
    local test_dir
    test_dir=$(mktemp -d)
    mkdir -p "$test_dir/$project_name"
    cd "$test_dir/$project_name"
    git init -q
    echo "$test_dir/$project_name"
}

# Clean up test project
cleanup_test_project() {
    local project_dir="$1"
    if [ -d "$project_dir" ]; then
        rm -rf "$project_dir"
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
