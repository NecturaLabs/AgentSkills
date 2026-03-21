#!/usr/bin/env bash
# Test that natural language prompts trigger the correct NecturaLabs skills

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/../test-helpers.sh"

echo "Testing skill triggering..."

for prompt_file in "$TESTS_DIR"/prompts/*.txt; do
    [ -f "$prompt_file" ] || continue

    test_name=$(basename "$prompt_file" .txt)
    expected_skill=$(head -1 "$prompt_file" | sed 's/^# *//')
    prompt=$(tail -n +2 "$prompt_file")

    echo "  Testing: $test_name (expects: $expected_skill)"

    output=$(run_claude "$prompt" 60)
    assert_skill_invoked "$output" "$expected_skill" "$test_name" || true
done

print_summary
