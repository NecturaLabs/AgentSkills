#!/usr/bin/env bash
# Regression guard for the suite aggregation in tests/run-all.sh, and for
# tests/validate-suite-manifest.sh where the two must agree. Many of the
# assertions below run the manifest guard rather than the runner, deliberately:
# several cases assert that BOTH implementations reject the same input, and
# splitting the file would break that pairing. The count of them was written
# here twice and was wrong both times, so the reason is stated and the number
# is not.
#
# run-all.sh runs under `set -euo pipefail`, where `(( COUNTER++ ))` on a
# counter still holding 0 evaluates to 0 -- a non-zero exit status that silently
# aborts the entire run partway through. That bug shipped once and went
# unnoticed because CI executed validate-skills.sh directly and never ran the
# aggregator itself.
#
# These tests execute run-all.sh against stub suites whose outcomes we control,
# covering BOTH counter branches: the pass counter (all suites green) and the
# fail counter (first suite red). Asserting only the green path would let a
# regression in the fail branch ship, and it would surface only once a suite
# legitimately failed -- exactly when the swallowed diagnostics hurt most.

set -euo pipefail

# `cd` and $PWD are builtins, so this derives an absolute path without the
# fork a `$(cd ... && pwd)` substitution costs, and CDPATH is cleared because
# a set one sends `cd` somewhere else and echoes where it landed.
# test-helpers.sh states what one process costs in this suite.
CDPATH=""
_PREV_PWD=$PWD
cd "${BASH_SOURCE[0]%/*}" 2>/dev/null || cd "$_PREV_PWD"
TESTS_DIR=$PWD
cd "$_PREV_PWD"
source "$TESTS_DIR/test-helpers.sh"

echo "Validating runner aggregation..."

# One temp directory for the whole run, with the fixture, the manifest copy and
# the outside-the-tree target as siblings inside it. Each was its own `mktemp`
# and its own `rm -rf` before, which is two processes per case for directories
# that could have been created once.
WORK_ROOT=""

cleanup_work_root() {
    if [ -n "$WORK_ROOT" ] && [ -d "$WORK_ROOT" ]; then
        rm -rf "$WORK_ROOT"
    fi
    WORK_ROOT=""
}
trap cleanup_work_root EXIT

WORK_ROOT=$(mktemp -d)
WORK_DIR="$WORK_ROOT/fixture"
MANIFEST_DIR="$WORK_ROOT/manifest"
OUTSIDE_DIR="$WORK_ROOT/outside"
# Output is captured through a file rather than `$(...)`, which forks before
# it can exec, and read back through a redirect, which does not. The capture
# sits beside the two trees rather than in either, so neither the runner's
# manifest nor the guard's tests/ sweep can see it.
CAPTURE="$WORK_ROOT/capture.out"

# Every file of tests/, read once. Rebuilding either tree is then a write of
# text already in hand, where `cp` and `cp -r` cost a process per case.
#
# Top-level regular files only, and written back without their mode, where
# `cp -r "$TESTS_DIR"/.` also carried subdirectories, dotfiles and the exec
# bit. tests/ is flat with no dotfiles and every invocation here is `bash
# <path>`, so the two agree today -- and the negative control below goes red
# rather than quiet if they ever stop agreeing.
declare -A PRISTINE_TESTS=()
shopt -s nullglob
for pristine_path in "$TESTS_DIR"/*; do
    [ -f "$pristine_path" ] || continue
    read_file "$pristine_path"
    PRISTINE_TESTS["${pristine_path##*/}"]="$READ_RESULT"
done
shopt -u nullglob

mkdir -p "$MANIFEST_DIR" "$OUTSIDE_DIR"

# Build a throwaway tests/ tree: a copy of the real runner plus stub suites with
# controlled exit statuses. run-all.sh locates suites by fixed relative path, so
# the stubs stand in for the real ones. runner-guard.sh is deliberately NOT
# copied, so the runner copy skips it and cannot recurse into this file.
#
# Removed and remade rather than restored in place, which keeps a file a case
# added out of the next case. It is two processes for a four-file tree, where
# a `mktemp`, a `cp` and three `cat` heredocs were seven.
make_fixture() {
    local nested_exit="$1"
    local validation_exit="$2"

    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
    mkdir -p "$WORK_DIR/nested"

    write_file "$WORK_DIR/run-all.sh" "${PRISTINE_TESTS[run-all.sh]}"

    printf '%s\n' \
        'echo "Results: 3 passed, 0 failed, 0 skipped"' \
        "exit $nested_exit" \
        > "$WORK_DIR/nested/run-all.sh"

    printf '%s\n' \
        'echo "Results: 5 passed, 0 failed, 0 skipped"' \
        "exit $validation_exit" \
        > "$WORK_DIR/validate-skills.sh"

    # run-all.sh registers from the manifest, so the fixture needs its own. One
    # stub sits in a subdirectory so the nested-path case stays covered, and no
    # row carries a flag, so the zero-test check is live for both.
    printf '%s\n' \
        'Nested Suite|nested/run-all.sh' \
        'Skill Validation|validate-skills.sh' \
        > "$WORK_DIR/required-suites.txt"
}

run_fixture() {
    FIXTURE_STATUS=0
    bash "$WORK_DIR/run-all.sh" > "$CAPTURE" 2>&1 || FIXTURE_STATUS=$?
    read_file "$CAPTURE"
    FIXTURE_OUTPUT="$READ_RESULT"
}

# Every assert is `|| true`: the helpers return 1 on failure, and under `set -e`
# that would abort this suite at the first failing assertion -- skipping the
# remaining checks and print_summary, so run-all.sh would find no "N passed"
# line and silently count 0. That is the very failure mode this file exists to
# catch. print_summary still returns non-zero when FAIL_COUNT > 0, so a real
# regression still fails the suite and CI.

# Case 1: every suite passes (exercises the pass-counter branch)
make_fixture 0 0
run_fixture
assert_exit_status "$FIXTURE_STATUS" 0 \
    "all suites pass -- runner exits 0" \
    || true
assert_contains "$FIXTURE_OUTPUT" \
    "Total: 2 suites passed, 0 suites failed (8 individual tests)" \
    "all suites pass -- reaches the total line and sums both suites" || true

# Case 2: first suite fails (exercises the fail-counter branch)
make_fixture 1 0
run_fixture
# This exit-status check alone cannot discriminate: an aborted run also exits 1.
# The total-line assertion below it is what actually catches a counter
# regression.
assert_exit_status "$FIXTURE_STATUS" 1 "a suite fails -- runner exits 1" || true
assert_contains "$FIXTURE_OUTPUT" \
    "Total: 1 suites passed, 1 suites failed (8 individual tests)" \
    "a suite fails -- still reaches the total line and counts both suites" \
        || true
assert_contains "$FIXTURE_OUTPUT" "Results: 3 passed" \
    "a suite fails -- the failing suite's own output is not swallowed" || true

# Case 3: a suite runs but reports nothing
# Emptying a suite file makes it exit 0 with no output at all. Before run-all.sh
# checked the per-suite count, that was a fully green run: every gate passed and
# only the total moved, which nobody reads. Truncating the real
# validate-skills.sh reproduced exactly that.
make_fixture 0 0
: > "$WORK_DIR/validate-skills.sh"
run_fixture
assert_exit_status "$FIXTURE_STATUS" 1 \
    "an emptied suite -- runner exits 1" \
    || true
assert_contains "$FIXTURE_OUTPUT" "reported zero tests" \
    "an emptied suite -- runner says why rather than just failing" || true

# Case 4: a suite that reads stdin
# The manifest used to be the loop's stdin, so one suite calling `cat` consumed
# the remaining rows and every later suite silently left the run while the
# aggregator exited 0. The manifest is read to completion before any suite runs,
# and suites are invoked with stdin detached.
make_fixture 0 0
printf '%s\n' 'cat >/dev/null' \
    'echo "Results: 3 passed, 0 failed, 0 skipped"' \
    > "$WORK_DIR/nested/run-all.sh"
run_fixture
assert_contains "$FIXTURE_OUTPUT" \
    "Total: 2 suites passed, 0 suites failed (8 individual tests)" \
    "a suite that drains stdin -- every later suite still runs" || true

# Case 5: a zero-padded test count
# "08" matches the count pattern but is an invalid octal literal. The arithmetic
# error used to end the manifest loop outright, dropping that suite and every
# one after it while still exiting 0 -- a wider blast radius than the bug it
# replaced.
make_fixture 0 0
printf '%s\n' 'echo "Results: 08 passed, 0 failed, 0 skipped"' \
    > "$WORK_DIR/nested/run-all.sh"
run_fixture
assert_exit_status "$FIXTURE_STATUS" 0 \
    "a zero-padded count -- the run still completes" \
    || true
assert_contains "$FIXTURE_OUTPUT" \
    "Total: 2 suites passed, 0 suites failed (13 individual tests)" \
    "a zero-padded count -- read as decimal 8, no suite dropped" || true

# Case 6: a CRLF manifest
# `read` consumes the newline but leaves the CR on the last field. This parser
# stripped a literal newline instead -- a no-op -- so every suite failed "not
# found" here while validate-suite-manifest.sh, which strips $'\r', passed the
# same rows. Two parsers disagreeing about the same file is the whole failure
# mode the manifest guard exists to catch, so it is asserted rather than
# assumed.
make_fixture 0 0
printf 'Nested Suite|nested/run-all.sh\r\nSkill Validation|validate-skills.sh\r\n' \
    > "$WORK_DIR/required-suites.txt"
run_fixture
assert_contains "$FIXTURE_OUTPUT" \
    "Total: 2 suites passed, 0 suites failed (8 individual tests)" \
    "a CRLF manifest -- the runner strips CR as the guard does" || true

# Case 7: the manifest guard actually fails
# validate-suite-manifest.sh is what stops a deleted or undeclared suite
# vanishing in silence, and a guard that cannot fail is worse than none. These
# cases cover each way the manifest can stop describing what actually runs: a
# declared suite missing from disk, a required suite dropped from the manifest,
# a flag on a row when none is defined, a suite-shaped file nobody declared, and
# run-all.sh no longer reading the manifest at all.

# Unlike make_fixture this holds the whole tests tree, runner-guard.sh
# included. Safe because nothing runs run-all.sh from the copy: only the
# manifest script executes, and it never recurses.
#
# Restored rather than rebuilt, and complete by construction rather than by an
# enumerated list: everything the pristine set does not name is removed --
# which covers the files, the subdirectory and the symlink the cases below add
# -- and then every pristine file is written back. Only a case that actually
# left something behind costs a process here, where `rm -rf` plus `mktemp`
# plus `cp -r` cost three every time.
reset_manifest_dir() {
    local path name

    shopt -s nullglob dotglob
    for path in "$MANIFEST_DIR"/*; do
        name="${path##*/}"
        if [ -z "${PRISTINE_TESTS[$name]+set}" ]; then
            rm -rf "$path"
        fi
    done
    shopt -u nullglob dotglob

    for name in "${!PRISTINE_TESTS[@]}"; do
        write_file "$MANIFEST_DIR/$name" "${PRISTINE_TESTS[$name]}"
    done
}

# Invoked by path rather than from a `cd` inside a subshell: the script derives
# its own root from BASH_SOURCE, so the two are equivalent and the subshell was
# a second fork on every case.
#
# Status alone cannot tell which check fired, and several checks in that script
# reject the same malformed manifest. A case asserting only exit 1 stayed green
# after its branch was deleted outright, so cases that name a specific branch
# assert on its message instead. One run yields both, where asserting on each
# meant running the guard twice over one tree.
MANIFEST_STATUS=0
MANIFEST_OUTPUT=""

run_manifest_guard() {
    MANIFEST_STATUS=0
    bash "$MANIFEST_DIR/validate-suite-manifest.sh" > "$CAPTURE" 2>&1 \
        || MANIFEST_STATUS=$?
    read_file "$CAPTURE"
    MANIFEST_OUTPUT="$READ_RESULT"
}

# The manifest file and the runner, mutated by several cases and restored by
# reset_manifest_dir from these.
PRISTINE_MANIFEST="${PRISTINE_TESTS[required-suites.txt]}"

reset_manifest_dir
run_manifest_guard
assert_exit_status "$MANIFEST_STATUS" 0 \
    "untouched tests tree -- manifest check passes (negative control)" || true

reset_manifest_dir
rm -f "$MANIFEST_DIR/validate-comment-rules.sh"
run_manifest_guard
assert_exit_status "$MANIFEST_STATUS" 1 \
    "a declared suite file is deleted -- manifest check fails" || true

reset_manifest_dir
replace_line_prefix "$PRISTINE_MANIFEST" "Comment Rules Guard|" ""
write_file "$MANIFEST_DIR/required-suites.txt" "$REPLACE_RESULT"
run_manifest_guard
assert_exit_status "$MANIFEST_STATUS" 1 \
    "a required suite is dropped from the manifest -- manifest check fails" \
        || true

# No manifest flag is defined. A row carrying one used to suppress the zero-test
# failure, which is the hole that check was written to close, so a third field
# is rejected outright rather than interpreted.
reset_manifest_dir
replace_line_prefix "$PRISTINE_MANIFEST" \
    "Comment Rules Guard|comment-rules-guard.sh" \
    "Comment Rules Guard|comment-rules-guard.sh|allow_zero"
write_file "$MANIFEST_DIR/required-suites.txt" "$REPLACE_RESULT"
run_manifest_guard
assert_exit_status "$MANIFEST_STATUS" 1 \
    "a flag on a manifest row -- manifest check fails" || true

# The same row against run-all.sh, whose parser is a separate implementation. A
# guard that rejects it while the runner shrugs leaves the bypass working
# wherever the aggregator runs without the guard.
make_fixture 0 0
printf '%s\n' \
    'Nested Suite|nested/run-all.sh|allow_zero' \
    'Skill Validation|validate-skills.sh' \
    > "$WORK_DIR/required-suites.txt"
run_fixture
assert_exit_status "$FIXTURE_STATUS" 1 \
    "a flag on a manifest row -- the runner rejects it too" || true
assert_contains "$FIXTURE_OUTPUT" "unknown flag" \
    "a flag on a manifest row -- the runner names what it rejected" || true

# check-thing.sh matches neither `validate-*.sh` nor `*-guard.sh`. The previous
# two-glob sweep missed it and a copy in a subdirectory entirely, so both are
# named here.
reset_manifest_dir
printf '%s\n' '#!/usr/bin/env bash' 'echo "Results: 1 passed"' \
    > "$MANIFEST_DIR/check-thing.sh"
run_manifest_guard
assert_exit_status "$MANIFEST_STATUS" 1 \
    "an undeclared suite whose name matches no glob -- manifest check fails" \
        || true

reset_manifest_dir
mkdir -p "$MANIFEST_DIR/sub"
printf '%s\n' '#!/usr/bin/env bash' 'echo "Results: 1 passed"' \
    > "$MANIFEST_DIR/sub/validate-thing.sh"
run_manifest_guard
assert_exit_status "$MANIFEST_STATUS" 1 \
    "an undeclared suite in a subdirectory -- manifest check fails" || true

# A dot-named suite, and one under a dot-directory. `find` matched both by
# default; a `**` glob matches neither without `dotglob`, and an undeclared
# suite hidden either way ran with the sweep still reporting green. Both
# shapes get a case, because one setting covers them and one case would not
# prove it.
reset_manifest_dir
printf '%s\n' '#!/usr/bin/env bash' 'echo "Results: 1 passed"' \
    > "$MANIFEST_DIR/.hidden-thing.sh"
run_manifest_guard
assert_exit_status "$MANIFEST_STATUS" 1 \
    "an undeclared dot-named suite -- manifest check fails" || true

reset_manifest_dir
mkdir -p "$MANIFEST_DIR/.hidden"
printf '%s\n' '#!/usr/bin/env bash' 'echo "Results: 1 passed"' \
    > "$MANIFEST_DIR/.hidden/validate-thing.sh"
run_manifest_guard
assert_exit_status "$MANIFEST_STATUS" 1 \
    "an undeclared suite under a dot-directory -- manifest check fails" || true

# Repointing MANIFEST= leaves the filename present in run-all.sh's header
# comment, which is exactly what defeated the previous text-match check while
# five suites stopped running.
reset_manifest_dir
replace_line_prefix "${PRISTINE_TESTS[run-all.sh]}" "MANIFEST=" \
    'MANIFEST="$TESTS_DIR/somewhere-else.txt"'
write_file "$MANIFEST_DIR/run-all.sh" "$REPLACE_RESULT"
run_manifest_guard
assert_exit_status "$MANIFEST_STATUS" 1 \
    "run-all.sh repointed at another manifest -- manifest check fails" || true

reset_manifest_dir
write_file "$MANIFEST_DIR/required-suites.txt" \
    "$PRISTINE_MANIFEST"'Escapes|../outside-suite.sh'$'\n'
run_manifest_guard
assert_exit_status "$MANIFEST_STATUS" 1 \
    "a row escaping tests/ -- manifest check fails" || true

reset_manifest_dir
write_file "$MANIFEST_DIR/required-suites.txt" \
    "$PRISTINE_MANIFEST"'Duplicate|validate-skills.sh'$'\n'
run_manifest_guard
assert_exit_status "$MANIFEST_STATUS" 1 \
    "a duplicated row -- manifest check fails" || true
assert_contains "$MANIFEST_OUTPUT" "declared more than once" \
    "a duplicated row -- caught by the dedupe branch, not incidentally" || true

# A symlinked suite satisfies every literal-path test while executing code from
# outside the tree, and `find -type f` never matches one, so the declared case
# gets its own check. The target sits beside the two trees rather than inside
# either, which is what makes it outside tests/ for both.
reset_manifest_dir
printf '%s\n' '#!/usr/bin/env bash' 'echo "Results: 1 passed"' \
    > "$OUTSIDE_DIR/evil.sh"
# MSYS=winsymlinks:nativestrict asks MSYS for a real symlink instead of its
# default copy, so this case actually runs on Windows rather than skipping. `-L`
# still gates it: where the filesystem genuinely has no symlinks the attack is
# unexpressible, and skipping honestly beats a green that proves nothing.
MSYS=winsymlinks:nativestrict \
    ln -s "$OUTSIDE_DIR/evil.sh" "$MANIFEST_DIR/escaped.sh" 2>/dev/null || true
if [ -L "$MANIFEST_DIR/escaped.sh" ]; then
    write_file "$MANIFEST_DIR/required-suites.txt" \
        "$PRISTINE_MANIFEST"'Escaped|escaped.sh'$'\n'
    run_manifest_guard
    assert_contains "$MANIFEST_OUTPUT" "resolves outside the tests directory" \
        "a symlinked suite pointing outside tests/ -- manifest check fails" \
            || true
else
    rm -f "$MANIFEST_DIR/escaped.sh"
    echo -e "  ${YELLOW}SKIP${NC}: symlink case -- this filesystem has no real symlinks (ln -s copied)"
    SKIP_COUNT=$((SKIP_COUNT + 1))
fi

# The same escape against run-all.sh, whose guard is a separate implementation
# and had no test of its own -- removing it would have gone unnoticed.
make_fixture 0 0
printf '%s\n' '#!/usr/bin/env bash' 'echo "Results: 9 passed"' \
    > "$OUTSIDE_DIR/evil.sh"
MSYS=winsymlinks:nativestrict \
    ln -s "$OUTSIDE_DIR/evil.sh" "$WORK_DIR/escaped.sh" 2>/dev/null || true
if [ -L "$WORK_DIR/escaped.sh" ]; then
    printf '%s\n' \
        'Nested Suite|nested/run-all.sh' \
        'Skill Validation|validate-skills.sh' \
        'Escaped|escaped.sh' \
        > "$WORK_DIR/required-suites.txt"
    run_fixture
    assert_contains "$FIXTURE_OUTPUT" "resolves outside the tests directory" \
        "a symlinked suite -- the runner rejects it too, not just the manifest guard" \
            || true
else
    rm -f "$WORK_DIR/escaped.sh"
    echo -e "  ${YELLOW}SKIP${NC}: runner symlink case -- no real symlinks on this filesystem"
    SKIP_COUNT=$((SKIP_COUNT + 1))
fi

print_summary
