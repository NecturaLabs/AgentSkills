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

# --- Case 4: a suite that reads stdin ---
# The manifest used to be the loop's stdin, so one suite calling `cat` consumed the remaining
# rows and every later suite silently left the run while the aggregator exited 0. The manifest
# is now on fd 3 and suites are invoked with stdin detached.
make_fixture 0 0
printf 'cat >/dev/null\necho "Results: 3 passed, 0 failed, 0 skipped"\n' > "$WORK_DIR/skill-triggering/run-all.sh"
run_fixture
assert_contains "$FIXTURE_OUTPUT" "Total: 2 suites passed, 0 suites failed (8 individual tests)" \
    "a suite that drains stdin -- every later suite still runs" || true

cleanup_fixture

# --- Case 5: a zero-padded test count ---
# "08" matches the count pattern but is an invalid octal literal. The arithmetic error used to
# end the manifest loop outright, dropping that suite and every one after it while still
# exiting 0 -- a wider blast radius than the bug it replaced.
make_fixture 0 0
printf 'echo "Results: 08 passed, 0 failed, 0 skipped"\n' > "$WORK_DIR/skill-triggering/run-all.sh"
run_fixture
assert_exit_status "$FIXTURE_STATUS" 0 "a zero-padded count -- the run still completes" || true
assert_contains "$FIXTURE_OUTPUT" "Total: 2 suites passed, 0 suites failed (13 individual tests)" \
    "a zero-padded count -- read as decimal 8, no suite dropped" || true

cleanup_fixture

# --- Case 6: the manifest guard actually fails ---
# validate-suite-manifest.sh is what stops a deleted or undeclared suite vanishing in silence,
# and a guard that cannot fail is worse than none. These cases cover each way the manifest can
# stop describing what actually runs: a declared suite missing from disk, a required suite
# dropped from the manifest, the allow_zero bypass switch applied to a row not entitled to it,
# a suite-shaped file nobody declared, and run-all.sh no longer reading the manifest at all.
#
# The earlier version of that guard matched suite names as text inside run-all.sh and was
# defeated six ways -- inline comments, dead strings, here-docs, a broken `-f` guard, an
# unreachable call, a `true #` prefix. Suite names no longer appear in run-all.sh at all, so
# those particular expressions have nowhere to live; what replaced them is a check on what the
# runner reports it would execute, and the cases below are what hold that honest.
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

# Status alone cannot tell which check fired, and several checks in that script reject the
# same malformed manifest. A case asserting only exit 1 stayed green after its branch was
# deleted outright, so cases that name a specific branch assert on its message instead.
manifest_output() {
    ( cd "$MANIFEST_DIR" && bash validate-suite-manifest.sh 2>&1 ) || true
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

# check-thing.sh matches neither `validate-*.sh` nor `*-guard.sh`. The previous two-glob
# sweep missed it and a copy in a subdirectory entirely, so both are named here.
reset_manifest_dir
printf '#!/usr/bin/env bash\necho "Results: 1 passed"\n' > "$MANIFEST_DIR/check-thing.sh"
assert_exit_status "$(manifest_exit)" 1 \
    "an undeclared suite whose name matches no glob -- manifest check fails" || true

reset_manifest_dir
mkdir -p "$MANIFEST_DIR/sub"
printf '#!/usr/bin/env bash\necho "Results: 1 passed"\n' > "$MANIFEST_DIR/sub/validate-thing.sh"
assert_exit_status "$(manifest_exit)" 1 \
    "an undeclared suite in a subdirectory -- manifest check fails" || true

# Repointing MANIFEST= leaves the filename present in run-all.sh's header comment, which is
# exactly what defeated the previous text-match check while five suites stopped running.
reset_manifest_dir
sed -i 's#^MANIFEST=.*#MANIFEST="$TESTS_DIR/somewhere-else.txt"#' "$MANIFEST_DIR/run-all.sh"
assert_exit_status "$(manifest_exit)" 1 \
    "run-all.sh repointed at another manifest -- manifest check fails" || true

reset_manifest_dir
printf 'Escapes|../outside-suite.sh\n' >> "$MANIFEST_DIR/required-suites.txt"
assert_exit_status "$(manifest_exit)" 1 \
    "a row escaping tests/ -- manifest check fails" || true

reset_manifest_dir
printf 'Duplicate|validate-skills.sh\n' >> "$MANIFEST_DIR/required-suites.txt"
assert_exit_status "$(manifest_exit)" 1 \
    "a duplicated row -- manifest check fails" || true
assert_contains "$(manifest_output)" "declared more than once"     "a duplicated row -- caught by the dedupe branch, not incidentally" || true

# A symlinked suite satisfies every literal-path test while executing code from outside the
# tree, and `find -type f` never matches one, so the declared case gets its own check.
reset_manifest_dir
OUTSIDE_DIR=$(mktemp -d)
printf '#!/usr/bin/env bash
echo "Results: 1 passed"
' > "$OUTSIDE_DIR/evil.sh"
# MSYS=winsymlinks:nativestrict asks MSYS for a real symlink instead of its default copy, so
# this case actually runs on Windows rather than skipping. `-L` still gates it: where the
# filesystem genuinely has no symlinks the attack is unexpressible, and skipping honestly
# beats a green that proves nothing.
MSYS=winsymlinks:nativestrict ln -s "$OUTSIDE_DIR/evil.sh" "$MANIFEST_DIR/escaped.sh" 2>/dev/null || true
if [ -L "$MANIFEST_DIR/escaped.sh" ]; then
    printf 'Escaped|escaped.sh
' >> "$MANIFEST_DIR/required-suites.txt"
    assert_contains "$(manifest_output)" "resolves outside the tests directory"         "a symlinked suite pointing outside tests/ -- manifest check fails" || true
else
    rm -f "$MANIFEST_DIR/escaped.sh"
    echo -e "  ${YELLOW}SKIP${NC}: symlink case -- this filesystem has no real symlinks (ln -s copied)"
    SKIP_COUNT=$((SKIP_COUNT + 1))
fi
rm -rf "$OUTSIDE_DIR"

# The same escape against run-all.sh, whose guard is a separate implementation and had no test
# of its own -- removing it would have gone unnoticed.
make_fixture 0 0
RUNNER_OUTSIDE=$(mktemp -d)
printf '#!/usr/bin/env bash
echo "Results: 9 passed"
' > "$RUNNER_OUTSIDE/evil.sh"
MSYS=winsymlinks:nativestrict ln -s "$RUNNER_OUTSIDE/evil.sh" "$WORK_DIR/escaped.sh" 2>/dev/null || true
if [ -L "$WORK_DIR/escaped.sh" ]; then
    printf 'Escaped|escaped.sh
' >> "$WORK_DIR/required-suites.txt"
    run_fixture
    assert_contains "$FIXTURE_OUTPUT" "resolves outside the tests directory"         "a symlinked suite -- the runner rejects it too, not just the manifest guard" || true
else
    rm -f "$WORK_DIR/escaped.sh"
    echo -e "  ${YELLOW}SKIP${NC}: runner symlink case -- no real symlinks on this filesystem"
    SKIP_COUNT=$((SKIP_COUNT + 1))
fi
rm -rf "$RUNNER_OUTSIDE"
cleanup_fixture


cleanup_manifest

print_summary
