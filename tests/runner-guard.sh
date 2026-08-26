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

    # run-all.sh registers from the manifest, so the fixture needs its own. Neither stub
    # carries allow_zero, which keeps the zero-test check live for both.
    cat > "$WORK_DIR/required-suites.txt" <<'EOF'
Skill Triggering|skill-triggering/run-all.sh
Skill Validation|validate-skills.sh
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

# --- Case 3: a suite runs but reports nothing ---
# Emptying a suite file makes it exit 0 with no output at all. Before run-all.sh checked the
# per-suite count, that was a fully green run: every gate passed and only the total moved,
# which nobody reads. Truncating the real validate-skills.sh reproduced exactly that.
make_fixture 0 0
: > "$WORK_DIR/validate-skills.sh"
run_fixture
assert_exit_status "$FIXTURE_STATUS" 1 "an emptied suite -- runner exits 1" || true
assert_contains "$FIXTURE_OUTPUT" "reported zero tests" \
    "an emptied suite -- runner says why rather than just failing" || true

cleanup_fixture

# --- Case 4: the manifest guard actually fails ---
# validate-suite-manifest.sh is what stops a deleted or undeclared suite vanishing in silence,
# and a guard that cannot fail is worse than none. These cases cover each way the manifest can
# stop describing what actually runs: a declared suite missing from disk, a required suite
# dropped from the manifest, the allow_zero bypass switch applied to a row not entitled to it,
# a suite-shaped file nobody declared, and run-all.sh no longer reading the manifest at all.
#
# The earlier version of that guard matched suite names as text inside run-all.sh and was
# defeated six ways -- inline comments, dead strings, here-docs, a broken `-f` guard, an
# unreachable call, a `true #` prefix. None of those are expressible any more, because there
# is no second place where a suite is named.
#
# Unlike make_fixture this copies the whole tests tree, runner-guard.sh included. Safe here
# because nothing runs run-all.sh from the copy: only the manifest script executes, and it
# never recurses.
MANIFEST_DIR=""

cleanup_manifest() {
    if [ -n "$MANIFEST_DIR" ] && [ -d "$MANIFEST_DIR" ]; then
        rm -rf "$MANIFEST_DIR"
    fi
    MANIFEST_DIR=""
}
trap 'cleanup_fixture; cleanup_manifest' EXIT

reset_manifest_dir() {
    cleanup_manifest
    MANIFEST_DIR=$(mktemp -d)
    cp -r "$TESTS_DIR"/. "$MANIFEST_DIR"/
}

manifest_exit() {
    local status=0
    ( cd "$MANIFEST_DIR" && bash validate-suite-manifest.sh >/dev/null 2>&1 ) || status=$?
    echo "$status"
}

reset_manifest_dir
assert_exit_status "$(manifest_exit)" 0 \
    "untouched tests tree -- manifest check passes (negative control)" || true

reset_manifest_dir
rm -f "$MANIFEST_DIR/validate-comment-rules.sh"
assert_exit_status "$(manifest_exit)" 1 \
    "a declared suite file is deleted -- manifest check fails" || true

reset_manifest_dir
sed -i '/^Comment Rules Guard|/d' "$MANIFEST_DIR/required-suites.txt"
assert_exit_status "$(manifest_exit)" 1 \
    "a required suite is dropped from the manifest -- manifest check fails" || true

# allow_zero suppresses the "reported zero tests" failure. Applied to an arbitrary row it
# reopens exactly the hole that check was written to close, which is why only one row may
# carry it and why that restriction is tested.
# `#` delimiter, not `|`: the manifest's own field separator is `|`, so a `|`-delimited
# expression here would be parsed as extra sed fields rather than as content.
reset_manifest_dir
sed -i 's#^Comment Rules Guard|comment-rules-guard\.sh$#&|allow_zero#' "$MANIFEST_DIR/required-suites.txt"
assert_exit_status "$(manifest_exit)" 1 \
    "allow_zero on a row not entitled to it -- manifest check fails" || true

reset_manifest_dir
printf '#!/usr/bin/env bash\necho "Results: 1 passed"\n' > "$MANIFEST_DIR/validate-undeclared-thing.sh"
assert_exit_status "$(manifest_exit)" 1 \
    "a suite-shaped file nobody declared -- manifest check fails" || true

reset_manifest_dir
sed -i 's|required-suites.txt|somewhere-else.txt|g' "$MANIFEST_DIR/run-all.sh"
assert_exit_status "$(manifest_exit)" 1 \
    "run-all.sh stops reading the manifest -- manifest check fails" || true

cleanup_manifest

print_summary
