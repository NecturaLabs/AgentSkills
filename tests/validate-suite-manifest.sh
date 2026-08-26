#!/usr/bin/env bash
# Guards the suite manifest that run-all.sh registers from.
#
# The previous version of this check matched suite names as text inside run-all.sh, and every
# text match was defeatable: an inline trailing comment naming the suite, a dead string
# assignment, a here-doc, a registration whose `-f` guard pointed at a path that did not
# exist, a call made unreachable with `if false &&`, or one disabled with a `true #` prefix.
# Each left the name present in the file while the suite no longer ran. Matching source text
# for evidence of execution is the wrong instrument; run-all.sh is now driven by
# required-suites.txt, and this checks that manifest instead.
#
# What is asserted:
#   - every suite this repo requires is declared;
#   - every declared suite exists on disk;
#   - allow_zero, which suppresses the "reported zero tests" failure, appears only on the one
#     row entitled to it -- it is a bypass switch, and an unrestricted bypass switch is how
#     the hole it was written to close got reopened;
#   - every suite-shaped file in tests/ is declared, so adding a suite and forgetting to
#     register it fails rather than passing quietly;
#   - run-all.sh still reads the manifest, so it cannot be swapped back for hardcoded blocks.
#
# Residual, stated rather than hidden: this cannot detect its own deletion.
# .github/workflows/ci.yml asserts the file is present before running the suite.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/test-helpers.sh"

echo "Validating test suite manifest..."

MANIFEST="$TESTS_DIR/required-suites.txt"
RUNNER="$TESTS_DIR/run-all.sh"

# A suite listed here must be declared in the manifest. Removing one is a deliberate decision
# that shows up in review; forgetting one is caught by the suite-shaped-file sweep below.
REQUIRED_SUITES=(
    "skill-triggering/run-all.sh"
    "validate-skills.sh"
    "validate-house-rules.sh"
    "house-rules-guard.sh"
    "validate-comment-rules.sh"
    "comment-rules-guard.sh"
    "validate-suite-manifest.sh"
    "runner-guard.sh"
)

# The only row permitted to carry allow_zero, and only because SKIP_LIVE_TESTS skips every
# case in it.
ZERO_EXEMPT="skill-triggering/run-all.sh"

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

if [ ! -f "$MANIFEST" ]; then
    fail "required-suites.txt is missing at $MANIFEST"
    # `|| true` then an explicit exit: print_summary returns 1 with FAIL_COUNT set, and under
    # `set -e` that would terminate here, making a bare `exit 1` below it dead code.
    print_summary || true
    exit 1
fi

if [ ! -f "$RUNNER" ]; then
    fail "run-all.sh is missing at $RUNNER"
    print_summary || true
    exit 1
fi

# run-all.sh must still be manifest-driven. If someone reintroduces hardcoded registrations,
# this manifest stops describing what actually runs and every check below becomes decorative.
if ! grep -q 'required-suites.txt' "$RUNNER"; then
    fail "run-all.sh no longer reads required-suites.txt -- the manifest is not driving the run"
else
    pass "run-all.sh is manifest-driven"
fi

DECLARED_PATHS=()
DECLARED_COUNT=0

while IFS='|' read -r suite_name suite_path suite_flags || [ -n "${suite_name:-}" ]; do
    suite_name=${suite_name%$'\r'}
    suite_path=${suite_path:-}
    suite_path=${suite_path%$'\r'}
    suite_flags=${suite_flags:-}
    suite_flags=${suite_flags%$'\r'}

    case "$suite_name" in
        ''|'#'*) continue ;;
    esac

    DECLARED_COUNT=$((DECLARED_COUNT + 1))
    DECLARED_PATHS+=("$suite_path")

    if [ -z "$suite_path" ]; then
        fail "manifest row '$suite_name' declares no script path"
        continue
    fi

    if [ ! -f "$TESTS_DIR/$suite_path" ]; then
        fail "$suite_path -- declared in the manifest but missing on disk"
        continue
    fi

    if [ -n "$suite_flags" ] && [ "$suite_flags" != "allow_zero" ]; then
        fail "$suite_path -- unknown manifest flag '$suite_flags'"
        continue
    fi

    if [ "$suite_flags" = "allow_zero" ] && [ "$suite_path" != "$ZERO_EXEMPT" ]; then
        fail "$suite_path -- carries allow_zero, which only $ZERO_EXEMPT may have"
        continue
    fi

    pass "$suite_path -- declared and present"
done < "$MANIFEST"

if [ "$DECLARED_COUNT" -eq 0 ]; then
    fail "the manifest declares no suites"
fi

declared_contains() {
    local needle="$1" entry
    for entry in ${DECLARED_PATHS+"${DECLARED_PATHS[@]}"}; do
        [ "$entry" = "$needle" ] && return 0
    done
    return 1
}

for suite in "${REQUIRED_SUITES[@]}"; do
    if declared_contains "$suite"; then
        pass "$suite -- required and declared"
    else
        fail "$suite -- required by this repo but absent from the manifest"
    fi
done

# Sweep for suite-shaped files that nobody declared. Without this, adding a suite and
# forgetting to register it leaves it silently never running -- the same end state as
# deleting it, which is the failure this whole file exists to prevent.
for candidate in "$TESTS_DIR"/validate-*.sh "$TESTS_DIR"/*-guard.sh; do
    [ -f "$candidate" ] || continue
    name=$(basename "$candidate")
    if declared_contains "$name"; then
        continue
    fi
    fail "$name -- looks like a suite but is not declared in the manifest"
done

print_summary
