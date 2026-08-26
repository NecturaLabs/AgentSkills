#!/usr/bin/env bash
# Run all NecturaLabs skill tests.
#
# Suites are declared in required-suites.txt, not by if-guarded blocks here.
# When each registration was its own `if [ -f ]` block, a suite could leave the
# run without failing anything and the aggregator still exited 0.
#
# The manifest is parsed once into arrays before any suite runs. Read
# incrementally it stayed open at an offset the parent returned to after every
# suite, so a suite rewriting it in place substituted every later row and one
# truncating it ended the run early -- both at exit 0. Closing the descriptor
# stopped a suite consuming rows; only reading to completion first stops it
# rewriting them.
#
# Guarantees: every declared row runs or the run fails; a suite that is missing,
# empty, reporting no tests, or resolving outside tests/ fails the run; suites
# accounted for equals suites declared; `--list-suites` prints exactly the paths
# it would attempt, diagnostics to stderr so they cannot be mistaken for one.
# Not guaranteed: that a suite's self-reported "N passed" was earned -- the
# per-suite mutation guards cover that.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_REAL="$(cd "$TESTS_DIR" && pwd -P)"
MANIFEST="$TESTS_DIR/required-suites.txt"

# The literal-path check below rejects "/" and "..", but `[ -f ]` follows
# symlinks, so a declared tests/x.sh -> ../outside/evil.sh satisfied every
# string test and executed code from outside this directory. Resolve the link
# and require the result to stay inside.
resolves_inside_tests() {
    local target="$1" resolved
    resolved=$(readlink -f "$target" 2>/dev/null \
        || realpath "$target" 2>/dev/null \
        || printf '%s' "$target")
    case "$resolved" in
        "$TESTS_REAL"/*) return 0 ;;
        *) return 1 ;;
    esac
}

MODE="run"
VERBOSE=""
case "${1:-}" in
    --list-suites) MODE="list" ;;
    *) VERBOSE="${1:-}" ;;
esac

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: suite manifest missing at $MANIFEST" >&2
    exit 1
fi

if [ "$MODE" = "run" ]; then
    echo "==================================="
    echo "NecturaLabs Agent Skills Test Suite"
    echo "==================================="
    echo ""
fi

TOTAL_SUITES_PASS=0
TOTAL_SUITES_FAIL=0
TOTAL_TESTS=0
DECLARED=0
SEEN_PATHS=""

run_test_suite() {
    local suite_name="$1"
    local suite_script="$2"

    echo "--- $suite_name ---"

    # A declared suite that is not on disk is a failure, never a skip. The old
    # SKIP path returned 0 and incremented no counter, so a moved entrypoint
    # left the run in silence.
    if [ -f "$suite_script" ] && ! resolves_inside_tests "$suite_script"; then
        echo "FAIL: $suite_name -- resolves outside the tests directory: $suite_script"
        TOTAL_SUITES_FAIL=$((TOTAL_SUITES_FAIL + 1))
        echo ""
        return 0
    fi

    if [ ! -f "$suite_script" ]; then
        echo "FAIL: $suite_name -- declared in the manifest but not found at $suite_script"
        TOTAL_SUITES_FAIL=$((TOTAL_SUITES_FAIL + 1))
        echo ""
        return 0
    fi

    local output
    local suite_ok=1
    # stdin detached, cwd fixed, and stderr kept out of $output: a suite echoing
    # "Results: 500 passed" to stderr was credited 500 tests and cleared the
    # zero-test gate. $VERBOSE is deliberately unquoted so empty passes no
    # argument.
    local errfile errfd
    errfile=$(mktemp) || {
        echo "ERROR: cannot create a temp file for suite stderr" >&2
        exit 1
    }
    output=$( cd "$TESTS_DIR" && bash "$suite_script" $VERBOSE </dev/null \
        2>"$errfile" ) || suite_ok=0
    echo "$output"
    # Open the file, then unlink the name: a suite that unlinks its own stderr
    # target would otherwise make the content unreachable and its diagnostics
    # vanish silently.
    exec {errfd}<"$errfile"
    rm -f "$errfile"
    cat <&"$errfd"
    exec {errfd}<&-

    # `pipefail` is what keeps this numeric when grep matches nothing: its
    # status propagates through the pipe, `|| echo "0"` fires, and suite_tests
    # stays a digit string. `tail -1` keeps a multi-match result single-valued.
    local suite_tests
    suite_tests=$(printf '%s\n' "$output" | grep '^Results:' \
        | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1 || echo "0")

    # Force base 10, and treat anything non-numeric as zero. "08" is a valid
    # match but an invalid octal literal, and the arithmetic error it caused
    # used to end the manifest loop outright -- dropping this suite and every
    # suite after it while still exiting 0. A count longer than 9 digits is
    # rejected rather than converted: $(( )) wraps silently, and
    # "9223372036854775808 passed" produced a negative grand total on an exit-0
    # run.
    if ! printf '%s' "$suite_tests" | grep -qE '^[0-9]{1,9}$'; then
        suite_tests=0
    fi
    suite_tests=$((10#$suite_tests))
    TOTAL_TESTS=$((TOTAL_TESTS + suite_tests))

    # A suite that exits cleanly while reporting no tests is indistinguishable
    # from one that was emptied. Existence and registration are not execution.
    if [ "$suite_tests" -eq 0 ]; then
        echo "FAIL: $suite_name -- exited cleanly but reported zero tests (emptied or gutted suite?)"
        suite_ok=0
    fi

    # $(( )) assignment, never (( x++ )) -- post-increment from 0 evaluates to
    # 0, a non-zero exit status, which aborts the script under `set -e`.
    if [ "$suite_ok" = "1" ]; then
        TOTAL_SUITES_PASS=$((TOTAL_SUITES_PASS + 1))
    else
        TOTAL_SUITES_FAIL=$((TOTAL_SUITES_FAIL + 1))
    fi
    echo ""
    return 0
}

SUITE_NAMES=()
SUITE_PATHS=()

parse_manifest() {
    local suite_name suite_path suite_flags suite_key
    while IFS='|' read -r suite_name suite_path suite_flags \
            || [ -n "${suite_name:-}" ]; do
        # A UTF-8 BOM on line 1 otherwise makes the first row malformed and
        # reports it as a missing script path, which sends the reader looking at
        # the wrong thing.
        suite_name=${suite_name#$'\xef\xbb\xbf'}
        # $'\r', not a literal newline: `read` has already consumed the
        # newline, so stripping one is a no-op, and this parser was then doing
        # no CR handling at all while validate-suite-manifest.sh did. A CRLF
        # manifest made every suite fail "not found" here and pass there.
        suite_name=${suite_name%$'\r'}
        suite_path=${suite_path:-}
        suite_path=${suite_path%$'\r'}
        suite_flags=${suite_flags:-}
        suite_flags=${suite_flags%$'\r'}

        # Trim so an indented `#` reads as a comment rather than running as a
        # row, and a padded name does not silently become a different name.
        suite_name=${suite_name#"${suite_name%%[![:space:]]*}"}
        suite_name=${suite_name%"${suite_name##*[![:space:]]}"}

        case "$suite_name" in
            ''|'#'*) continue ;;
        esac

        if [ -z "$suite_path" ]; then
            echo "ERROR: manifest row '$suite_name' declares no script path" >&2
            exit 1
        fi

        # A row names a suite inside tests/. An absolute path, or one containing
        # "..", would execute code outside this directory, which no legitimate
        # row needs.
        case "$suite_path" in
            /*|*..*)
                echo "ERROR: manifest row '$suite_name' has an unsafe path: $suite_path" >&2
                exit 1
                ;;
        esac

        # No flag is defined. Rejecting a third field rather than ignoring it
        # keeps this parser in step with validate-suite-manifest.sh, and stops a
        # bypass switch reappearing on a row nobody reads.
        if [ -n "$suite_flags" ]; then
            echo "ERROR: manifest row '$suite_name' has an unknown flag: $suite_flags" >&2
            exit 1
        fi

        # Compared case-insensitively: on Windows and macOS "suite.sh" and
        # "SUITE.SH" are one file, and two rows for it ran it twice and
        # double-counted its tests.
        suite_key=$(printf '%s' "$suite_path" | tr '[:upper:]' '[:lower:]')
        case "$SEEN_PATHS" in
            *"|$suite_key|"*)
                echo "ERROR: manifest declares $suite_path more than once" >&2
                exit 1
                ;;
        esac
        SEEN_PATHS="$SEEN_PATHS|$suite_key|"

        SUITE_NAMES+=("$suite_name")
        SUITE_PATHS+=("$suite_path")
    done < "$MANIFEST"
}

parse_manifest
DECLARED=${#SUITE_PATHS[@]}

if [ "$MODE" = "list" ]; then
    for idx in ${SUITE_PATHS+"${!SUITE_PATHS[@]}"}; do
        echo "${SUITE_PATHS[$idx]}"
    done
fi

if [ "$MODE" = "run" ]; then
    for idx in ${SUITE_PATHS+"${!SUITE_PATHS[@]}"}; do
        # Fail closed: if the runner itself errors while handling a suite, that
        # suite is counted as failed rather than vanishing from both counters.
        if ! run_test_suite "${SUITE_NAMES[$idx]}" \
                "$TESTS_DIR/${SUITE_PATHS[$idx]}"; then
            echo "FAIL: ${SUITE_NAMES[$idx]} -- the runner errored while running this suite"
            TOTAL_SUITES_FAIL=$((TOTAL_SUITES_FAIL + 1))
        fi
    done
fi

if [ "$DECLARED" -eq 0 ]; then
    echo "ERROR: the suite manifest declares no suites" >&2
    exit 1
fi

if [ "$MODE" = "list" ]; then
    exit 0
fi

# A real invariant, because DECLARED is fixed before any suite runs: every
# declared suite must have landed in exactly one counter.
ACCOUNTED=$((TOTAL_SUITES_PASS + TOTAL_SUITES_FAIL))
if [ "$ACCOUNTED" -ne "$DECLARED" ]; then
    echo "ERROR: $DECLARED suites declared but only $ACCOUNTED accounted for -- the run ended early" >&2
    exit 1
fi

echo "==================================="
echo "Total: $TOTAL_SUITES_PASS suites passed, $TOTAL_SUITES_FAIL suites failed ($TOTAL_TESTS individual tests)"
echo "==================================="

if [ "$TOTAL_SUITES_FAIL" -gt 0 ]; then
    exit 1
fi

if [ "$TOTAL_TESTS" -eq 0 ]; then
    echo "ERROR: Zero tests ran across all suites" >&2
    exit 1
fi
