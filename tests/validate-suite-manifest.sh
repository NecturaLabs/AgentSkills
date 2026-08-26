#!/usr/bin/env bash
# Every suite in run-all.sh is registered behind `if [ -f ... ]`, so deleting or renaming one
# removes it from the run silently: the aggregator still exits 0 and still prints a Total
# line, just with fewer tests counted in it. Nobody reads that count, so a suite can stop
# running for months without anyone noticing -- the same "a consistency check that cannot
# fail is worse than no check" failure that house-rules-guard.sh and comment-rules-guard.sh
# exist to prevent, one level up.
#
# This asserts TWO things per required suite, because either alone is insufficient: the file
# exists, and run-all.sh actually registers it. A file nobody calls never runs; a
# registration whose file is gone is skipped in silence.
#
# The guard cannot live inside run-all.sh: runner-guard.sh executes a copy of run-all.sh
# against a fixture holding only two stub suites, so an inline requirement for the full set
# would fail that fixture rather than any real regression.
#
# Residual, stated rather than hidden: this script cannot detect its own deletion.
# .github/workflows/ci.yml asserts the file is present before running the suite, which is
# what closes that hole.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/test-helpers.sh"

echo "Validating test suite manifest..."

# A suite listed here is required. Adding a suite to tests/ without adding it here leaves it
# unprotected; removing one from here is a deliberate decision that shows up in review.
REQUIRED_SUITES=(
    "validate-skills.sh"
    "validate-house-rules.sh"
    "house-rules-guard.sh"
    "validate-comment-rules.sh"
    "comment-rules-guard.sh"
    "runner-guard.sh"
    "validate-suite-manifest.sh"
)

# Registered by directory rather than by file, so it is checked separately.
REQUIRED_SUITE_DIRS=(
    "skill-triggering"
)

RUNNER="$TESTS_DIR/run-all.sh"

if [ ! -f "$RUNNER" ]; then
    echo -e "${RED}FAIL${NC}: run-all.sh is missing at $RUNNER"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    print_summary
    exit 1
fi

runner_text=$(<"$RUNNER")

for suite in "${REQUIRED_SUITES[@]}"; do
    if [ ! -f "$TESTS_DIR/$suite" ]; then
        echo -e "${RED}FAIL${NC}: $suite -- required suite file is missing"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    if [[ $runner_text != *"$suite"* ]]; then
        echo -e "${RED}FAIL${NC}: $suite -- file exists but run-all.sh never registers it"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    echo -e "${GREEN}PASS${NC}: $suite -- present and registered"
    PASS_COUNT=$((PASS_COUNT + 1))
done

for suite_dir in "${REQUIRED_SUITE_DIRS[@]}"; do
    if [ ! -d "$TESTS_DIR/$suite_dir" ]; then
        echo -e "${RED}FAIL${NC}: $suite_dir/ -- required suite directory is missing"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    if [[ $runner_text != *"$suite_dir"* ]]; then
        echo -e "${RED}FAIL${NC}: $suite_dir/ -- exists but run-all.sh never registers it"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    echo -e "${GREEN}PASS${NC}: $suite_dir/ -- present and registered"
    PASS_COUNT=$((PASS_COUNT + 1))
done

print_summary
