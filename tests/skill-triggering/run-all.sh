#!/usr/bin/env bash
# Test that natural language prompts trigger the correct NecturaLabs skills

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/../test-helpers.sh"

echo "Testing skill triggering..."

# These tests shell out to a live `claude -p` session, so they need the CLI, network,
# and credentials. Set SKIP_LIVE_TESTS=1 to skip them (CI does this) while still
# exercising the aggregator in tests/run-all.sh.
if [ "${SKIP_LIVE_TESTS:-0}" != "0" ]; then
    for prompt_file in "$TESTS_DIR"/prompts/*.txt; do
        [ -f "$prompt_file" ] || continue
        SKIP_COUNT=$((SKIP_COUNT + 1))
    done
    echo -e "  ${YELLOW}SKIP${NC}: SKIP_LIVE_TESTS set -- requires a live 'claude' CLI"
    print_summary
    exit 0
fi

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
