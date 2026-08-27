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
# accounted for equals suites declared; output and accounting follow manifest
# order however the concurrent suites finish; `--list-suites` prints exactly the
# paths it would attempt, diagnostics to stderr so they cannot be mistaken for
# one. Not guaranteed: that a suite's self-reported "N passed" was earned -- the
# per-suite mutation guards cover that.

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
cd -P "$TESTS_DIR"
TESTS_REAL=$PWD
cd "$_PREV_PWD"
MANIFEST="$TESTS_DIR/required-suites.txt"

# The literal-path check below rejects "/" and "..", but `[ -f ]` follows
# symlinks, so a declared tests/x.sh -> ../outside/evil.sh satisfied every
# string test and executed code from outside this directory. Resolve the link
# and require the result to stay inside.
resolves_inside_tests() {
    local target="$1" resolved
    # A file that is not itself a link, named directly inside tests/, cannot
    # reach outside it. The resolver costs a process, so it runs only where a
    # link can be: on the target itself, or on a directory component of a
    # nested row -- which the manifest has carried before and may again.
    #
    # The fast path anchors on TESTS_DIR and the slow path on TESTS_REAL. They
    # cannot disagree: TESTS_REAL is defined as TESTS_DIR resolved, so a tests/
    # reached through a symlink lands inside either way.
    if [ ! -L "$target" ] && [ "${target%/*}" = "$TESTS_DIR" ]; then
        return 0
    fi
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

# Suites are started together and collected in manifest order. Serially the
# run took nine minutes on Windows, nearly all of it waiting on process
# creation rather than on any check. No suite writes anywhere inside tests/ --
# the ones that need to write build a sandbox under `mktemp -d` -- so running
# them at once is safe, and AGENTS.md makes that a rule rather than a habit.
RUN_DIR=""
PIDS=()
BLOCKED=()

# INT and TERM as well as EXIT. A signal otherwise kills this shell without
# running the EXIT trap, leaving the temp directory behind and the suites
# running -- and each of those holds a sandbox of its own. The arrays are
# initialised above the traps, or a signal arriving in between would find
# ${#PIDS[@]} unbound under `set -u` and the handler would fail.
#
# Killing an already-collected job is the normal case here, so the complaint
# goes to /dev/null.
cleanup_run_dir() {
    # `${PIDS[@]+...}`, not `${PIDS+...}`: PIDS is sparse, because a row that
    # is missing or resolves outside tests/ is never started. The shorter form
    # tests index 0 alone, so a first row in that state expanded to nothing
    # here and no child was signalled.
    if [ "${#PIDS[@]}" -gt 0 ]; then
        kill ${PIDS[@]+"${PIDS[@]}"} 2>/dev/null || true
    fi
    if [ -n "$RUN_DIR" ] && [ -d "$RUN_DIR" ]; then
        rm -rf "$RUN_DIR"
    fi
    RUN_DIR=""
}
trap cleanup_run_dir EXIT
trap 'cleanup_run_dir; exit 130' INT
trap 'cleanup_run_dir; exit 143' TERM

# Called once per manifest index, before any index is collected. It either
# records why the row cannot run or starts it; both are the caller's promise
# that collect_suite will find one or the other.
start_suite() {
    local idx="$1"
    local suite_name="${SUITE_NAMES[$idx]}"
    local suite_script="$TESTS_DIR/${SUITE_PATHS[$idx]}"

    BLOCKED[$idx]=""

    # A declared suite that is not on disk is a failure, never a skip. The old
    # SKIP path returned 0 and incremented no counter, so a moved entrypoint
    # left the run in silence. The verdict is recorded rather than printed,
    # because rows print in manifest order once every suite has been started.
    if [ -f "$suite_script" ] && ! resolves_inside_tests "$suite_script"; then
        BLOCKED[$idx]="FAIL: $suite_name -- resolves outside the tests directory: $suite_script"
        return 0
    fi

    if [ ! -f "$suite_script" ]; then
        BLOCKED[$idx]="FAIL: $suite_name -- declared in the manifest but not found at $suite_script"
        return 0
    fi

    # Backgrounded WITHOUT a wrapping subshell, so $! is the suite itself. With
    # `( cd ... && bash ... ) &` the recorded pid was the wrapper, so the trap
    # signalled that and not the suite -- and where killing a wrapper does not
    # take its child with it, the suite goes on running with its sandbox open.
    # The caller cds into TESTS_DIR once instead, which is where the subshell
    # used to go.
    #
    # stdin detached and stderr kept out of the stdout file: a suite echoing
    # "Results: 500 passed" to stderr was credited 500 tests and cleared the
    # zero-test gate. $VERBOSE is deliberately unquoted so empty passes no
    # argument.
    bash "$suite_script" $VERBOSE </dev/null \
        >"$RUN_DIR/$idx.out" 2>"$RUN_DIR/$idx.err" &
    PIDS[$idx]=$!
}

# Leaves the last "<digits> passed" of the last Results: line in LAST_PASSED,
# and the empty string when there is none. Digits are the run immediately
# before a " passed", which is what `grep -oE '[0-9]+ passed'` matched; every
# such match on every Results: line is scanned and the last one wins, which is
# what `tail -1` chose. Defined here rather than sourced, because run-all.sh
# is copied into runner-guard.sh's fixtures on its own.
LAST_PASSED=""

read_last_passed() {
    local text="$1" line rest head digits ch

    LAST_PASSED=""
    while [ -n "$text" ]; do
        line="${text%%$'\n'*}"
        if [ "$line" = "$text" ]; then
            text=""
        else
            text="${text#*$'\n'}"
        fi

        case "$line" in
            'Results:'*) ;;
            *) continue ;;
        esac

        rest="$line"
        while [[ $rest == *' passed'* ]]; do
            head="${rest%%' passed'*}"
            rest="${rest#*' passed'}"

            digits=""
            while [ -n "$head" ]; do
                ch="${head: -1}"
                case "$ch" in
                    [0-9]) digits="$ch$digits"; head="${head%?}" ;;
                    *) break ;;
                esac
            done
            if [ -n "$digits" ]; then
                LAST_PASSED="$digits"
            fi
        done
    done
}

# Exactly once per index, and only after start_suite has run for every index.
# A second call `wait`s a pid bash has already reaped, which returns 127 and
# would turn a suite that passed into one that failed. Prints the row and
# lands it in exactly one counter.
collect_suite() {
    local idx="$1"
    local suite_name="${SUITE_NAMES[$idx]}"

    echo "--- $suite_name ---"

    if [ -n "${BLOCKED[$idx]}" ]; then
        echo "${BLOCKED[$idx]}"
        TOTAL_SUITES_FAIL=$((TOTAL_SUITES_FAIL + 1))
        echo ""
        return 0
    fi

    local output
    local suite_ok=1
    local status=0
    # A suite whose row comes up while it is still running is waited for here,
    # so no row is ever decided on a half-written file.
    wait "${PIDS[$idx]}" || status=$?
    # Reaped, so no longer this shell's to signal. Dropping it keeps the exit
    # trap from TERMing a pid the system is free to hand to something else.
    unset 'PIDS[$idx]'
    [ "$status" -eq 0 ] || suite_ok=0

    local errfd
    output=$(<"$RUN_DIR/$idx.out")
    echo "$output"
    # Open the file, then unlink the name: a suite that unlinks its own stderr
    # target would otherwise make the content unreachable and its diagnostics
    # vanish silently.
    exec {errfd}<"$RUN_DIR/$idx.err"
    rm -f "$RUN_DIR/$idx.err"
    # `read` rather than `cat`, for the reason read_last_passed replaced its
    # grep pipeline: this runs once per suite, and stderr here is a handful of
    # lines.
    #
    # Looped, because `-d ''` stops at a NUL and reports it exactly as it
    # reports EOF. Read once, a suite emitting a single NUL byte would have
    # hidden every diagnostic after it -- output a suite controls silencing
    # part of the report is the failure this aggregator exists to prevent.
    local errtext="" errchunk=""
    while IFS= read -r -d '' errchunk; do
        errtext="$errtext$errchunk"
    done <&"$errfd"
    printf '%s' "$errtext$errchunk"
    exec {errfd}<&-

    # The count, read in the shell. `printf | grep | grep -oE | grep -oE |
    # tail` cost five processes and a fork on every suite of every run, to
    # pull one number out of one line. The reading is unchanged: only lines
    # beginning "Results:" are considered, the digits immediately before each
    # " passed" are candidates, and the last candidate wins.
    local suite_tests=0
    read_last_passed "$output"

    # Force base 10, and treat anything non-numeric as zero. "08" is a valid
    # match but an invalid octal literal, and the arithmetic error it caused
    # used to end the manifest loop outright -- dropping this suite and every
    # suite after it while still exiting 0. A count longer than 9 digits is
    # rejected rather than converted: $(( )) wraps silently, and
    # "9223372036854775808 passed" produced a negative grand total on an exit-0
    # run.
    if [ -n "$LAST_PASSED" ] && [ "${#LAST_PASSED}" -le 9 ]; then
        suite_tests=$((10#$LAST_PASSED))
    fi
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

# ASCII-only case fold. Both `${x,,}` and `tr` go through the C library, and
# under a Turkish locale `I` folds to a dotless `i`, so two rows naming one file
# on a case-insensitive filesystem stopped comparing equal and the duplicate
# went undetected. The alphabet is spelled out here so the comparison cannot
# depend on a locale at all.
ascii_lower() {
    local s="$1" ch head i
    local up=ABCDEFGHIJKLMNOPQRSTUVWXYZ
    local lo=abcdefghijklmnopqrstuvwxyz

    ASCII_LOWER=""
    for ((i = 0; i < ${#s}; i++)); do
        ch=${s:i:1}
        head=${up%%"$ch"*}
        if [ "${#head}" -lt "${#up}" ]; then
            ch=${lo:${#head}:1}
        fi
        ASCII_LOWER="$ASCII_LOWER$ch"
    done
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
        ascii_lower "$suite_path"
        suite_key=$ASCII_LOWER
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
    RUN_DIR=$(mktemp -d) || {
        echo "ERROR: cannot create a temp directory for suite output" >&2
        exit 1
    }

    # The cwd every suite runs with, set once here rather than in a subshell
    # around each start -- that subshell is what used to hide the suite from
    # the pid this script records. Nothing after this point uses a relative
    # path.
    cd "$TESTS_DIR" || {
        echo "ERROR: cannot enter $TESTS_DIR" >&2
        exit 1
    }

    for idx in ${SUITE_PATHS+"${!SUITE_PATHS[@]}"}; do
        start_suite "$idx"
    done

    for idx in ${SUITE_PATHS+"${!SUITE_PATHS[@]}"}; do
        # Fail closed: if the runner itself errors while handling a suite, that
        # suite is counted as failed rather than vanishing from both counters.
        if ! collect_suite "$idx"; then
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
