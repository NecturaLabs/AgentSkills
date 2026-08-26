#!/usr/bin/env bash
# Regression guard for the suite aggregation in tests/run-all.sh.
#
# run-all.sh runs under `set -euo pipefail`, where `(( COUNTER++ ))` on a counter
# still holding 0 evaluates to 0 -- a non-zero exit status that silently aborts the
# entire run partway through. That bug shipped once and went unnoticed because CI
# executed validate-skills.sh directly and never ran the aggregator itself.
#
# These tests execute run-all.sh against stub suites whose outcomes we control,
# covering BOTH counter branches: the pass counter (all suites green) and the fail
# counter (first suite red). Asserting only the green path would let a regression in
# the fail branch ship, and it would surface only once a suite legitimately failed --
# exactly when the swallowed diagnostics hurt most.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/test-helpers.sh"

echo "Validating runner aggregation..."

WORK_DIR=""

cleanup_fixture() {
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
    WORK_DIR=""
}
trap cleanup_fixture EXIT

# Build a throwaway tests/ tree: a copy of the real runner plus stub suites with
# controlled exit statuses. run-all.sh locates suites by fixed relative path, so the
# stubs stand in for the real ones. runner-guard.sh is deliberately NOT copied, so
# the runner copy skips it and cannot recurse into this file.
make_fixture() {
    local triggering_exit="$1"
    local validation_exit="$2"

    cleanup_fixture
    WORK_DIR=$(mktemp -d)
    mkdir -p "$WORK_DIR/skill-triggering"
    cp "$TESTS_DIR/run-all.sh" "$WORK_DIR/run-all.sh"

    cat > "$WORK_DIR/skill-triggering/run-all.sh" <<EOF
echo "Results: 3 passed, 0 failed, 0 skipped"
exit $triggering_exit
EOF

    cat > "$WORK_DIR/validate-skills.sh" <<EOF
echo "Results: 5 passed, 0 failed, 0 skipped"
exit $validation_exit
EOF
}

run_fixture() {
    local status=0
    FIXTURE_OUTPUT=$(bash "$WORK_DIR/run-all.sh" 2>&1) || status=$?
    FIXTURE_STATUS=$status
}

# Every assert is `|| true`: the helpers return 1 on failure, and under `set -e` that
# would abort this suite at the first failing assertion -- skipping the remaining checks
# and print_summary, so run-all.sh would find no "N passed" line and silently count 0.
# That is the very failure mode this file exists to catch. print_summary still returns
# non-zero when FAIL_COUNT > 0, so a real regression still fails the suite and CI.

# --- Case 1: every suite passes (exercises the pass-counter branch) ---
make_fixture 0 0
run_fixture
assert_exit_status "$FIXTURE_STATUS" 0 "all suites pass -- runner exits 0" || true
assert_contains "$FIXTURE_OUTPUT" "Total: 2 suites passed, 0 suites failed (8 individual tests)" \
    "all suites pass -- reaches the total line and sums both suites" || true

# --- Case 2: first suite fails (exercises the fail-counter branch) ---
make_fixture 1 0
run_fixture
# This exit-status check alone cannot discriminate: an aborted run also exits 1.
# The total-line assertion below it is what actually catches a counter regression.
assert_exit_status "$FIXTURE_STATUS" 1 "a suite fails -- runner exits 1" || true
assert_contains "$FIXTURE_OUTPUT" "Total: 1 suites passed, 1 suites failed (8 individual tests)" \
    "a suite fails -- still reaches the total line and counts both suites" || true
assert_contains "$FIXTURE_OUTPUT" "Results: 3 passed" \
    "a suite fails -- the failing suite's own output is not swallowed" || true

cleanup_fixture

# --- Case 3: a required suite is deleted (manifest guard) ---
# validate-suite-manifest.sh is what stops a deleted suite from vanishing silently from the
# run. That guard is itself only worth having if it actually fails, so prove it does: copy
# the real tests tree, remove one required suite, and assert a non-zero exit. The negative
# control on the untouched copy is what distinguishes "detected the deletion" from "the
# script is broken and always fails".
MANIFEST_DIR=$(mktemp -d)
trap 'cleanup_fixture; rm -rf "$MANIFEST_DIR"' EXIT
cp -r "$TESTS_DIR"/. "$MANIFEST_DIR"/

manifest_status=0
( cd "$MANIFEST_DIR" && bash validate-suite-manifest.sh >/dev/null 2>&1 ) || manifest_status=$?
assert_exit_status "$manifest_status" 0 \
    "untouched tests tree -- manifest check passes (negative control)" || true

rm -f "$MANIFEST_DIR/validate-comment-rules.sh"
manifest_status=0
( cd "$MANIFEST_DIR" && bash validate-suite-manifest.sh >/dev/null 2>&1 ) || manifest_status=$?
assert_exit_status "$manifest_status" 1 \
    "a required suite is deleted -- manifest check fails" || true

print_summary
