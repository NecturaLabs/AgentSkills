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
#   - every shell script under tests/, other than the runner and its helpers, is declared, so
#     adding a suite and forgetting to register it fails rather than passing quietly;
#   - run-all.sh executes exactly the declared set -- checked by running it in --list-suites
#     mode, not by matching its source text, because the previous text match was satisfied by
#     run-all.sh's own header comment while five suites had stopped running.
#
# Residuals, stated rather than hidden:
#   - this script is itself a manifest row, so deleting its row would stop it running.
#     .github/workflows/ci.yml runs it as its own step, independent of the aggregator, which
#     is what closes that. A guard registered only in the artifact it guards cannot enforce
#     its own registration.
#   - a suite reporting a count it did not earn is believed by the aggregator; per-suite
#     mutation guards are what cover that.

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

# Deliberately NOT a text match. An earlier version grepped run-all.sh for the manifest
# filename, and run-all.sh's own header comment satisfied that grep: repointing MANIFEST= at
# a different file left the string present, this check green, and five suites silently not
# running. --list-suites reports the paths the runner would actually execute, so the two lists
# diverge the moment it stops using this manifest.
RUNNER_LISTED=$(bash "$RUNNER" --list-suites 2>/dev/null || true)

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

    if [ -z "$suite_path" ]; then
        fail "manifest row '$suite_name' declares no script path"
        continue
    fi

    # A row names a suite inside tests/. An absolute path or one containing ".." would run
    # code from outside the directory this manifest governs.
    case "$suite_path" in
        /*|*..*)
            fail "$suite_path -- row '$suite_name' uses an absolute path or escapes tests/"
            continue
            ;;
    esac

    if declared_contains "$suite_path"; then
        fail "$suite_path -- declared more than once; the run would execute it twice and double-count it"
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

    DECLARED_PATHS+=("$suite_path")
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

# The runner must execute exactly what this manifest declares. Comparing the two sorted lists
# catches a runner reading a different manifest, a row it skips, and a row it invents.
DECLARED_SORTED=$(printf '%s\n' ${DECLARED_PATHS+"${DECLARED_PATHS[@]}"} | sed '/^$/d' | sort)
LISTED_SORTED=$(printf '%s\n' "$RUNNER_LISTED" | sed '/^$/d' | sort)

if [ -z "$LISTED_SORTED" ]; then
    fail "run-all.sh --list-suites produced nothing -- the runner is not reading this manifest"
elif [ "$DECLARED_SORTED" != "$LISTED_SORTED" ]; then
    fail "run-all.sh executes a different set of suites than this manifest declares"
    echo "    manifest declares:"
    printf '      %s\n' $DECLARED_SORTED
    echo "    runner would execute:"
    printf '      %s\n' $LISTED_SORTED
else
    pass "run-all.sh executes exactly the declared suites"
fi

# Sweep every shell script under tests/, not two filename shapes. The previous two-glob
# allowlist missed tests/check-thing.sh and tests/sub/validate-thing.sh entirely: a suite
# added and never declared never runs, which is the same end state as deleting it.
NON_SUITE_FILES=(
    "run-all.sh"
    "test-helpers.sh"
)

while IFS= read -r candidate; do
    rel=${candidate#"$TESTS_DIR/"}

    skip=0
    for allowed in "${NON_SUITE_FILES[@]}"; do
        if [ "$rel" = "$allowed" ]; then
            skip=1
            break
        fi
    done
    [ "$skip" = "1" ] && continue

    if declared_contains "$rel"; then
        continue
    fi

    fail "$rel -- a shell script under tests/ that no manifest row declares"
done < <(find "$TESTS_DIR" -type f -name '*.sh' | sort)

print_summary
