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

# Parameter expansion instead of `dirname` in its own subshell, `|| pwd` for a
# source path with no directory part, and, where a parent is wanted, a prefix
# of the canonical result rather than a second `cd`. test-helpers.sh states
# what one process costs in this suite.
TESTS_DIR="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd || pwd)"
PROJECT_ROOT="${TESTS_DIR%/*}"
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
#
# Two splits, the same two the awk pass here made before a process was measured
# against the work it does: the row into `|` fields, then field two into its
# `*` spans. Every second span is an emphasised term.
#
# `${parts[i],,}` folds through the C library, where `I` is the one letter whose
# result depends on the locale. That direction fails closed here: a Turkish fold
# yields a dotless `i`, which the plain-word gate below then rejects by name.
extract_banned_words() {
    local line field parts=() i
    # The result is emptied BEFORE the early return, or a missing file leaves
    # it unset and the floor below reads an unbound variable under `set -u` --
    # an abort with no summary, where the point is a named failure. A bare
    # redirection would abort as well, which is why the return is here at all.
    BANNED_WORDS=()
    [ -f "$1" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            '| Speculation and hedging:'*) ;;
            '| Time-anchored language:'*) ;;
            *) continue ;;
        esac

        field="${line#|}"
        field="${field%%|*}"
        IFS='*' read -ra parts <<< "$field"
        for ((i = 1; i < ${#parts[@]}; i += 2)); do
            if [ -n "${parts[i]}" ]; then
                BANNED_WORDS+=("${parts[i],,}")
            fi
        done
    done < "$1"
}

CANON="$PROJECT_ROOT/skills/comment-manager/references/comment-rules.md"

extract_banned_words "$CANON"

# Under eight means the canon lost a term or the rows were reshaped, and a
# derived list would otherwise pass by banning less than it did before.
if [ "${#BANNED_WORDS[@]}" -lt 8 ]; then
    echo -e "${RED}FAIL${NC}: comment-rules.md -- ${#BANNED_WORDS[@]} banned words, expected 8+"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    print_summary
    exit 1
fi

# Each term is concatenated into a regex in the sweep below, so a metacharacter
# in one would match nothing at all while the floor above still counted it --
# a term lost in silence, which is what that floor exists to prevent. The canon
# writes these as plain words, and anything else is a malformed row.
TERM_RE='^[a-z][a-z -]*$'
for term in "${BANNED_WORDS[@]}"; do
    if ! [[ $term =~ $TERM_RE ]]; then
        echo -e "${RED}FAIL${NC}: comment-rules.md -- banned term is not a plain word: '$term'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        print_summary
        exit 1
    fi
done

# Handed to the sweep through the environment rather than `awk -v`, which
# applies backslash-escape processing to what it is given. These terms are read
# out of a file, and PROJECT_ROOT is a path, so neither may be reinterpreted:
# one backslash in the root turned every label into an absolute path the lookup
# below could not match, and every file then reported clean.
BANNED_LIST=$(printf '%s\n' "${BANNED_WORDS[@]}")

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
    local line in_sh=0
    local mll_re='^[[:space:]]*max_line_length[[:space:]]*='

    WIDTH=""
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            '['*)
                if [ "$line" = "[*.sh]" ]; then
                    in_sh=1
                else
                    in_sh=0
                fi
                continue
                ;;
        esac

        [ "$in_sh" = "1" ] || continue
        [[ $line =~ $mll_re ]] || continue

        WIDTH="${line#*=}"
        WIDTH="${WIDTH//[[:space:]]/}"
        break
    done < "$1"
}

WIDTH=""
if [ -f "$EDITORCONFIG" ]; then
    read_width "$EDITORCONFIG"
fi

WIDTH_RE='^[0-9]{2,3}$'
if [ -z "$WIDTH" ] || ! [[ $WIDTH =~ $WIDTH_RE ]]; then
    echo -e "${RED}FAIL${NC}: .editorconfig declares no [*.sh] max_line_length"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    print_summary
    exit 1
fi
echo -e "${GREEN}PASS${NC}: .editorconfig declares [*.sh] width $WIDTH"
PASS_COUNT=$((PASS_COUNT + 1))

# Readability is settled before the sweep, not inside it: awk on a file it
# cannot open warns and exits non-zero, which under `set -euo pipefail` would
# end the run with no counted failure and no summary -- silent where it should
# be loud. The verdicts below still print in FILES order, so a file that has
# gone missing keeps its place in the report.
READABLE=()
declare -A UNREADABLE=()
for file in "${FILES[@]}"; do
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        UNREADABLE[$file]=1
    else
        READABLE+=("$file")
    fi
done

# Every mechanical rule, for every file, in one awk pass. It was one process
# per LINE once, which put the sibling checks at two minutes on Windows. One
# process per file replaced that, and a dozen of those is still most of a run
# that comment-compliance-guard.sh repeats once per mutation.
#
# Findings come back as `<label> TAB <message>` and are grouped by label below,
# so one file yields one PASS or one FAIL listing everything wrong with it
# rather than a wall of near-identical rows.
#
# The comment rules and the code-width carve-out share the pass because they
# read the same lines and must agree on which of them are comments.
SWEEP=""
SWEEP_STATUS=0
if [ "${#READABLE[@]}" -gt 0 ]; then
    SWEEP=$(BANNED_LIST="$BANNED_LIST" SWEEP_ROOT="$PROJECT_ROOT" \
            awk -v w="$WIDTH" -v header_max="$HEADER_MAX" \
            -v para_max="$PARAGRAPH_MAX" '
        function labelof(f,   n) {
            n = length(root)
            if (substr(f, 1, n + 1) == root "/") return substr(f, n + 2)
            return f
        }

        function report(line, msg) {
            printf "%s\t%s:%d -- %s\n", label, label, line, msg
        }

        # A paragraph ends at a bare separator, at the first line that is not a
        # comment, and at end-of-file. While header_done is 0 the run is still
        # the file header, which answers to the 20-line carve-out instead.
        function end_paragraph() {
            if (header_done && para > para_max) {
                report(para_start,
                    sprintf("block comment is %d lines, over %d",
                        para, para_max))
            }
            para = 0
        }

        # Called when the reader crosses into the next file and once at the
        # end, because both ceilings can close only there. A comment run at
        # end-of-file meets no following line, and both passed silently before:
        # a 25-line header with no code after it, and a 10-line block at the
        # tail of a file, were reported clean.
        function end_file() {
            if (label == "") return
            end_paragraph()
            if (!header_done && run > 0 && run_start <= 2) header_len = run
            if (header_len > header_max) {
                report(2, sprintf("header is %d lines, over %d",
                    header_len, header_max))
            }
        }

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

        BEGIN {
            root = ENVIRON["SWEEP_ROOT"]
            nbanned = split(ENVIRON["BANNED_LIST"], banned, "\n")
        }

        FNR == 1 {
            end_file()
            label = labelof(FILENAME)
            run = 0
            run_start = 0
            header_len = 0
            header_done = 0
            para = 0
            para_start = 0
        }

        FNR == 1 && substr($0, 1, 2) == "#!" { next }

        # A bare `#` separates two paragraphs while staying inside the same
        # comment run: it splits the prose the 7-line ceiling applies to, and
        # still counts toward the 20 lines the header is allowed.
        /^[[:space:]]*#[[:space:]]*$/ {
            if (run > 0) run++
            end_paragraph()
            next
        }

        /^[[:space:]]*#/ {
            if (run == 0) run_start = FNR
            run++
            if (para == 0) para_start = FNR
            para++

            # gawk counts characters here and mawk counts bytes, and CI runs
            # on a distribution whose default awk is mawk. Every file in
            # scope is ASCII, where the two agree; a non-ASCII comment would
            # be measured differently by the two and is worth knowing about.
            if (length($0) > w) {
                report(FNR, sprintf("%d cols, over %d", length($0), w))
            }

            text = $0
            sub(/^[[:space:]]*/, "", text)
            sub(/^#/, "", text)
            sub(/^ /, "", text)

            # Clean Code bans position markers and ASCII rules. The text either
            # informs or decorates; a run of dashes only decorates.
            if (text ~ /(---|===|\*\*\*|###)/) {
                report(FNR, "decorative marker in a comment")
            }

            # Word boundaries, not substring. Two of the canon terms are three
            # letters long and sit inside ordinary words a shell script uses
            # constantly, so a substring test would fire on those. A guard that
            # cries wolf gets muted, which costs more than it catches.
            lower = tolower(text)
            for (i = 1; i <= nbanned; i++) {
                if (banned[i] == "") continue
                if (lower ~ ("(^|[^a-z])" banned[i] "([^a-z]|$)")) {
                    report(FNR,
                        "time-anchored or hedging: \047" banned[i] "\047")
                }
            }

            # An annotation needs an owner or a resolvable reference. Without
            # one it is a note nobody owns and nothing will ever close.
            if (text ~ /(TODO|FIXME|HACK|XXX)/ &&
                    text !~ /\([^)]+\)/ &&
                    text !~ /https?:\/\// &&
                    text !~ /#[0-9]+/) {
                report(FNR, "annotation with no owner or reference")
            }

            # Commented-out code, detected only where it is unambiguous: a lone
            # block terminator or the tail of an opener. A looser pattern would
            # flag prose that quotes shell, and a guard that cries wolf gets
            # muted.
            stripped = text
            sub(/[[:space:]]+$/, "", stripped)
            if (stripped ~ /^(fi|done|esac|else|[}]|;;)$/ ||
                    stripped ~ /;[[:space:]]*(then|do)$/) {
                report(FNR, "commented-out code")
            }
            next
        }

        # The run just ended. A run that began at line 2 is the file header and
        # is measured whole against the 20-line design-rationale carve-out;
        # every later paragraph is a block comment and gets 7.
        #
        # Code lines take the same ceiling, minus the carve-out the Google
        # shell guide grants: a line that is long because of a string literal
        # which cannot sensibly be split is allowed. Deciding that by removing
        # quoted spans keeps a long call failing while a long message string
        # passes.
        {
            end_paragraph()
            if (run > 0) {
                if (!header_done && run_start <= 2) header_len = run
                run = 0
            }
            header_done = 1

            # `} # end of if`. The brace already says where the block closed.
            if ($0 ~ /^[[:space:]]*[}][[:space:]]*#/) {
                report(FNR, "label on a closing brace")
            }

            if (length($0) > w && length(strip($0)) > w) {
                report(FNR,
                    sprintf("%d cols of code, over %d", length($0), w))
            }
        }

        END { end_file() }
    ' "${READABLE[@]}") || SWEEP_STATUS=$?
fi

# Fail closed. Two things end the sweep early: a file awk cannot open, which
# the readability loop above has already ruled out, and a term that does not
# compile as a regex, which gawk treats as fatal and the plain-word check above
# rules out. No case in comment-compliance-guard.sh reaches this branch, and it
# is here because a sweep that dies silently would report every file clean.
if [ "$SWEEP_STATUS" -ne 0 ]; then
    echo -e "${RED}FAIL${NC}: the comment sweep exited $SWEEP_STATUS -- nothing was measured"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    print_summary
    exit 1
fi

declare -A FINDINGS=()
while IFS=$'\t' read -r found_label found_text; do
    [ -n "$found_label" ] || continue
    FINDINGS[$found_label]="${FINDINGS[$found_label]:-}\n    $found_text"
done <<< "$SWEEP"

for file in "${FILES[@]}"; do
    label="${file#"$PROJECT_ROOT/"}"

    if [ -n "${UNREADABLE[$file]+set}" ]; then
        echo -e "${RED}FAIL${NC}: $label -- missing or unreadable"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    findings="${FINDINGS[$label]:-}"
    if [ -n "$findings" ]; then
        echo -e "${RED}FAIL${NC}: $label -- comment rule violations:$findings"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo -e "${GREEN}PASS${NC}: $label -- comments within every ceiling"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
done

print_summary
