#!/usr/bin/env bash
# Holds this repo's own shell to the comment rules it ships in
# skills/comment-manager. A rulebook its author does not follow is the first
# thing a reader checks, and every violation fixed here was found by hand once.
#
# The width is READ from .editorconfig, not hardcoded. That is the resolution
# order the skill specifies -- a project's own configuration outranks the
# matrix -- and hardcoding 80 would let the two disagree silently.
#
# Comment lines take the width absolutely. Code lines take it with the carve-out
# Google's shell guide states: a line long because of a literal that cannot
# sensibly be split is allowed, decided by removing quoted spans and measuring
# what is left.
#
# Scope is bash this repo owns that carries comments. hooks/run-hook.cmd is
# excluded on purpose: it is a batch/bash polyglot whose batch half uses REM,
# and the matrix has no row for Batch.
#
# Not checked: whether a comment is TRUE, necessary, or free of invented
# rationale. Gates 1 to 3 need a reader. This covers only what a machine can
# decide, so a green run means no mechanical violation, never a good comment.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/test-helpers.sh"

echo "Validating this repo's own comment compliance..."

EDITORCONFIG="$PROJECT_ROOT/.editorconfig"

# Ceilings from comment-rules.md. The width is configuration; these two are the
# rules themselves and are stated here.
HEADER_MAX=20
PARAGRAPH_MAX=7

# Time-anchored and hedging words, read out of comment-rules.md rather than
# copied here. The hand-kept list had drifted from the canon in both
# directions, carrying one term the canon does not list and omitting three that
# it does, with no check binding the two. Terms are not quoted in this comment:
# this file is checked against the list it builds.
extract_banned_words() {
    awk -F'|' '
        /^\| Speculation and hedging:/ || /^\| Time-anchored language:/ {
            n = split($2, parts, /\*/)
            for (i = 2; i <= n; i += 2) {
                if (parts[i] != "") print tolower(parts[i])
            }
        }
    ' "$1"
}

CANON="$PROJECT_ROOT/skills/comment-manager/references/comment-rules.md"

BANNED_WORDS=()
while IFS= read -r banned; do
    [ -n "$banned" ] && BANNED_WORDS+=("$banned")
done < <(extract_banned_words "$CANON")

# Under eight means the canon lost a term or the rows were reshaped, and a
# derived list would otherwise pass by banning less than it did before.
if [ "${#BANNED_WORDS[@]}" -lt 8 ]; then
    echo -e "${RED}FAIL${NC}: comment-rules.md -- ${#BANNED_WORDS[@]} banned words, expected 8+"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    print_summary
    exit 1
fi

# `find`, not a glob: validate-suite-manifest.sh sweeps tests/** for exactly
# this reason, and runner-guard.sh covers a suite living in a subdirectory. A
# glob forces tests/sub/foo.sh into the manifest yet never comment-checks it.
FILES=()
while IFS= read -r f; do
    [ -n "$f" ] && FILES+=("$f")
done < <(find "$TESTS_DIR" -type f -name '*.sh' | sort)
FILES+=("$PROJECT_ROOT/hooks/session-start")

# The width the whole suite measures against. Absent, this file has no rule to
# apply, which is a failure rather than a pass over an unmeasured tree.
read_width() {
    awk '
        /^\[/ { in_sh = ($0 == "[*.sh]") ; next }
        in_sh && /^[[:space:]]*max_line_length[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, "")
            gsub(/[[:space:]]/, "")
            print
            exit
        }
    ' "$EDITORCONFIG"
}

WIDTH=""
if [ -f "$EDITORCONFIG" ]; then
    WIDTH=$(read_width)
fi

if [ -z "$WIDTH" ] || ! printf '%s' "$WIDTH" | grep -qE '^[0-9]{2,3}$'; then
    echo -e "${RED}FAIL${NC}: .editorconfig declares no [*.sh] max_line_length"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    print_summary
    exit 1
fi
echo -e "${GREEN}PASS${NC}: .editorconfig declares [*.sh] width $WIDTH"
PASS_COUNT=$((PASS_COUNT + 1))

# Every mechanical rule, applied to one file. Findings accumulate into $findings
# so one file yields one PASS or one FAIL listing everything wrong with it,
# rather than a wall of near-identical rows.
check_file() {
    local path="$1"
    local label="${path#"$PROJECT_ROOT/"}"
    local findings=""
    local n=0 run=0 run_start=0 header_len=0 header_done=0
    local para=0 para_start=0
    local line text stripped

    # Held in variables because `[[ =~ ]]` parses an unquoted parenthesis as
    # shell grouping before the regex engine ever sees it.
    local marker_re='(---|===|\*\*\*|###)'
    local annotation_re='(TODO|FIXME|HACK|XXX)'
    local owner_re='\([^)]+\)'
    local url_re='https?://'
    local issue_re='#[0-9]+'
    local terminator_re='^(fi|done|esac|else|\}|;;)$'
    local opener_re=';[[:space:]]*(then|do)$'
    local brace_label_re='^[[:space:]]*\}[[:space:]]*#'

    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))

        if [ "$n" = "1" ] && [ "${line:0:2}" = "#!" ]; then
            continue
        fi

        # A bare `#` separates two paragraphs while staying inside the same
        # comment run: it splits the prose the 7-line ceiling applies to, and
        # still counts toward the header's 20.
        if [[ $line =~ ^[[:space:]]*#[[:space:]]*$ ]]; then
            if [ "$run" -gt 0 ]; then
                run=$((run + 1))
            fi
            if [ "$header_done" = "1" ] && [ "$para" -gt "$PARAGRAPH_MAX" ]; then
                findings="$findings\n    $label:$para_start -- block comment is $para lines, over $PARAGRAPH_MAX"
            fi
            para=0
            continue
        fi

        if [[ $line =~ ^[[:space:]]*# ]]; then
            if [ "$run" = "0" ]; then
                run_start=$n
            fi
            run=$((run + 1))
            if [ "$para" = "0" ]; then
                para_start=$n
            fi
            para=$((para + 1))

            if [ "${#line}" -gt "$WIDTH" ]; then
                findings="$findings\n    $label:$n -- ${#line} cols, over $WIDTH"
            fi

            text=${line#"${line%%[![:space:]]*}"}
            text=${text#\#}
            text=${text# }

            # Clean Code bans position markers and ASCII rules. The text either
            # informs or decorates; a run of dashes only decorates.
            if [[ $text =~ $marker_re ]]; then
                findings="$findings\n    $label:$n -- decorative marker in a comment"
            fi

            # Word boundaries, not substring. Two of the canon's terms are
            # three letters long and sit inside ordinary words a shell script
            # uses constantly, so a substring test would fire on those. A guard
            # that cries wolf gets muted, which costs more than it catches.
            for word in "${BANNED_WORDS[@]}"; do
                if [[ ${text,,} =~ (^|[^a-z])${word}([^a-z]|$) ]]; then
                    findings="$findings\n    $label:$n -- time-anchored or hedging: '$word'"
                fi
            done

            # An annotation needs an owner or a resolvable reference. Without
            # one it is a note nobody owns and nothing will ever close.
            if [[ $text =~ $annotation_re ]]; then
                if ! [[ $text =~ $owner_re ]] && ! [[ $text =~ $url_re ]] \
                        && ! [[ $text =~ $issue_re ]]; then
                    findings="$findings\n    $label:$n -- annotation with no owner or reference"
                fi
            fi

            # Commented-out code, detected only where it is unambiguous: a lone
            # block terminator or an opener's tail. A looser pattern would flag
            # prose that quotes shell, and a guard that cries wolf gets muted.
            stripped=${text%"${text##*[![:space:]]}"}
            if [[ $stripped =~ $terminator_re ]] \
                    || [[ $stripped =~ $opener_re ]]; then
                findings="$findings\n    $label:$n -- commented-out code"
            fi
            continue
        fi

        # The run just ended. A run that began at line 2 is the file header and
        # is measured whole against the 20-line design-rationale carve-out;
        # every later paragraph is a block comment and gets 7.
        if [ "$header_done" = "1" ] && [ "$para" -gt "$PARAGRAPH_MAX" ]; then
            findings="$findings\n    $label:$para_start -- block comment is $para lines, over $PARAGRAPH_MAX"
        fi
        para=0

        if [ "$run" -gt 0 ]; then
            if [ "$header_done" = "0" ] && [ "$run_start" -le 2 ]; then
                header_len=$run
            fi
            run=0
        fi
        header_done=1

        # `} # end of if`. The brace already says where the block closed.
        if [[ $line =~ $brace_label_re ]]; then
            findings="$findings\n    $label:$n -- label on a closing brace"
        fi
    done < "$path"

    # A comment run at end-of-file never meets a following non-comment line, so
    # the in-loop flush above never fires for it. Both ceilings passed silently
    # there: a 25-line header with no code after it, and a 10-line block at the
    # tail of a file, were both reported clean.
    if [ "$header_done" = "1" ] && [ "$para" -gt "$PARAGRAPH_MAX" ]; then
        findings="$findings\n    $label:$para_start -- block comment is $para lines, over $PARAGRAPH_MAX"
    fi
    if [ "$header_done" = "0" ] && [ "$run" -gt 0 ] && [ "$run_start" -le 2 ]; then
        header_len=$run
    fi

    # Code lines take the same ceiling, minus the carve-out Google's own shell
    # guide grants: a line that is long because of a string literal which
    # cannot sensibly be split is allowed. Deciding that by removing quoted
    # spans keeps a long call failing while a long message string passes.
    # One awk pass per file, not per line -- a subprocess per line put the
    # sibling checks at two minutes on Windows.
    local offender
    while IFS= read -r offender; do
        [ -n "$offender" ] && findings="$findings\n    $offender"
    done <<< "$(awk -v w="$WIDTH" -v label="$label" '
        function strip(s,   out, i, c, inq, q) {
            out = ""; inq = 0; q = ""
            for (i = 1; i <= length(s); i++) {
                c = substr(s, i, 1)
                # A backslash escape outside single quotes consumes the next
                # character, so `\"` is a quote CHARACTER and not the start of
                # a literal. Without this, one `\"` made the rest of the line
                # read as a string and an 88-column all-code line passed.
                if (c == "\\" && !(inq && q == "\047")) {
                    if (!inq) out = out "\\" substr(s, i + 1, 1)
                    i++
                    continue
                }
                if (inq) { if (c == q) inq = 0; continue }
                if (c == "\"" || c == "\047") { inq = 1; q = c; continue }
                out = out c
            }
            # An unterminated span means the line is not the shape this
            # heuristic assumes. Measure it raw and fail closed, rather than
            # exempting whatever followed the stray quote.
            #
            # The known cost: an apostrophe in a trailing comment opens a span
            # that never closes, so a genuinely literal-dominated line over the
            # width gets reported. That is a loud false positive, and it is the
            # direction to err in; the other direction hides real defects. A
            # line that trips it is a line to rewrite or split.
            #
            # No apostrophe appears in this awk program on purpose: the whole
            # program is a single-quoted shell string, so one would close it and
            # silently drop characters from what awk receives.
            if (inq) return s
            return out
        }
        /^[ \t]*#/ { next }
        length($0) > w && length(strip($0)) > w {
            printf "%s:%d -- %d cols of code, over %d\n", label, FNR, length($0), w
        }
    ' "$path")"

    if [ "$header_len" -gt "$HEADER_MAX" ]; then
        findings="$findings\n    $label:2 -- header is $header_len lines, over $HEADER_MAX"
    fi

    if [ -n "$findings" ]; then
        echo -e "${RED}FAIL${NC}: $label -- comment rule violations:$findings"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo -e "${GREEN}PASS${NC}: $label -- comments within every ceiling"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
}

for file in "${FILES[@]}"; do
    # Readability is checked here, not inside check_file: `done < "$path"` on an
    # unreadable file aborts the whole run under `set -euo pipefail`, with no
    # counted failure and no summary -- silent where it should be loud.
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        echo -e "${RED}FAIL${NC}: ${file#"$PROJECT_ROOT/"} -- missing or unreadable"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    check_file "$file"
done

print_summary
