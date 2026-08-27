#!/usr/bin/env bash
# Validate all skills have correct structure and frontmatter

set -euo pipefail

# `cd` and $PWD are builtins, so this derives an absolute path without the
# fork a `$(cd ... && pwd)` substitution costs, and CDPATH is cleared because
# a set one sends `cd` somewhere else and echoes where it landed. A parent is
# a prefix of the result rather than a second `cd`. test-helpers.sh states
# what one process costs in this suite.
CDPATH=""
_PREV_PWD=$PWD
cd "${BASH_SOURCE[0]%/*}" 2>/dev/null || cd "$_PREV_PWD"
TESTS_DIR=$PWD
cd "$_PREV_PWD"
PROJECT_ROOT="${TESTS_DIR%/*}"
source "$TESTS_DIR/test-helpers.sh"

# A description must open with an actionable verb. Held in a variable because
# `[[ =~ ]]` parses an unquoted parenthesis as shell grouping before the regex
# engine sees it, and matched against a lowercased line so the test stays
# case-insensitive without `shopt`. `I` is the one letter whose fold is
# locale-dependent, and no verb here contains one, so the fold is safe.
VERB_RE='^(use |must |create |update )'

# Every references/<file>.md a SKILL.md names is handed to a dispatched subagent
# as a literal path. A typo there fails silently in the worst direction: the
# subagent cannot read the file, says nothing about it, and still returns a
# confident clean review. Nothing else in this suite catches it, because the
# skill markdown stays well-formed.
#
# Three path shapes appear across the skills, all resolving against the skill
# directory: a bare `references/x.md`, the tail of an `<announced
# base>/references/x.md` instruction, and a sibling `../<skill>/references/x.md`
# form. One pattern covers them: the optional `../` group is the only part that
# leaves the skill directory. A sibling path is the supported way to name
# another skill's reference; an announced-base path crossing skills resolves
# against the wrong directory and is reported as missing.
#
# Leaves the paths that do not resolve in MISSING_REFS, space-separated, and
# the empty string when they all do. Matching is in-process: `grep -oE | sort
# -u` cost three processes per skill, which on Windows outweighs the whole
# scan. Each path is reported once, in the order the file names it, rather
# than sorted.
#
# The result is left in a variable rather than echoed for the reason the
# matching is in-process at all: `x=$(missing_references_for ...)` forks once
# per skill, and there are more skills here than there are checks in this
# function.
missing_references_for() {
    local dir="$1" file="$2" line rest ref
    local ref_re='(\.\./[A-Za-z0-9_-]+/)?references/[A-Za-z0-9_.-]+\.md'
    local -A seen=()

    MISSING_REFS=""
    while IFS= read -r line || [ -n "$line" ]; do
        rest="$line"
        while [[ $rest =~ $ref_re ]]; do
            ref="${BASH_REMATCH[0]}"
            rest="${rest#*"$ref"}"
            if [ -z "${seen[$ref]+set}" ]; then
                seen[$ref]=1
                [ -f "$dir/$ref" ] || MISSING_REFS="$MISSING_REFS $ref"
            fi
        done
    done < "$file"
}

echo "Validating skill structure..."

for skill_dir in "$PROJECT_ROOT"/skills/*/; do
    skill_name="${skill_dir%/}"
    skill_name="${skill_name##*/}"
    skill_file="$skill_dir/SKILL.md"

    # SKILL.md must exist
    if [ ! -f "$skill_file" ]; then
        echo -e "${RED}FAIL${NC}: $skill_name -- missing SKILL.md"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # One read, then every check in the shell. `head`, four `grep` calls, three
    # `sed` calls and a `basename` per skill were most of this suite's runtime.
    mapfile -t SKILL_LINES < "$skill_file"

    # Must have YAML frontmatter
    if [[ ${SKILL_LINES[0]-} != ---* ]]; then
        echo -e "${RED}FAIL${NC}: $skill_name -- missing YAML frontmatter"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # `name:` and `description:` are collected the way `grep | sed` collected
    # them: every line that opens with the key, not the first, so a file
    # carrying two of either is still measured whole.
    #
    # FRONTMATTER reproduces the `sed -n` range this replaced: it opens on a
    # fence line, closes on the next, and can open again further down. The
    # 1024-char ceiling is applied to that whole span, so a second range has to
    # count here exactly as it counted there.
    NAME_VALUES=()
    DESC_VALUES=()
    FRONTMATTER=""
    in_range=0

    for line in ${SKILL_LINES+"${SKILL_LINES[@]}"}; do
        if [ "$in_range" = "0" ]; then
            if [ "$line" = "---" ]; then
                in_range=1
                FRONTMATTER="$FRONTMATTER$line"$'\n'
            fi
        else
            FRONTMATTER="$FRONTMATTER$line"$'\n'
            if [ "$line" = "---" ]; then
                in_range=0
            fi
        fi

        case "$line" in
            name:*)
                value="${line#name:}"
                NAME_VALUES+=("${value#"${value%%[! ]*}"}")
                ;;
            description:*)
                value="${line#description:}"
                DESC_VALUES+=("${value#"${value%%[! ]*}"}")
                ;;
        esac
    done

    # Must have description field
    if [ "${#DESC_VALUES[@]}" -eq 0 ]; then
        echo -e "${RED}FAIL${NC}: $skill_name -- missing 'description' in frontmatter"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Name must match directory name (if present)
    if [ "${#NAME_VALUES[@]}" -gt 0 ]; then
        old_ifs=$IFS
        IFS=$'\n'
        frontmatter_name="${NAME_VALUES[*]}"
        IFS=$old_ifs
        if [ "$frontmatter_name" != "$skill_name" ]; then
            echo -e "${RED}FAIL${NC}: $skill_name -- frontmatter name '$frontmatter_name' doesn't match directory"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            continue
        fi
    fi

    # Description must start with an actionable verb phrase
    verb_ok=0
    for value in "${DESC_VALUES[@]}"; do
        if [[ ${value,,} =~ $VERB_RE ]]; then
            verb_ok=1
            break
        fi
    done
    if [ "$verb_ok" = "0" ]; then
        echo -e "${YELLOW}WARN${NC}: $skill_name -- description should start with an actionable verb (Use/MUST/Create/Update)"
    fi

    # Frontmatter must be under 1024 chars total. The trailing newlines go
    # first, because the command substitution this replaced stripped them and
    # the ceiling is stated against that length.
    while [[ $FRONTMATTER == *$'\n' ]]; do
        FRONTMATTER="${FRONTMATTER%$'\n'}"
    done
    frontmatter_len=${#FRONTMATTER}
    if [ "$frontmatter_len" -gt 1024 ]; then
        echo -e "${RED}FAIL${NC}: $skill_name -- frontmatter exceeds 1024 chars ($frontmatter_len)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    missing_references_for "$skill_dir" "$skill_file"
    if [ -n "$MISSING_REFS" ]; then
        echo -e "${RED}FAIL${NC}: $skill_name -- SKILL.md names reference file(s) that do not exist:$MISSING_REFS"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    echo -e "${GREEN}PASS${NC}: $skill_name -- valid structure"
    PASS_COUNT=$((PASS_COUNT + 1))
done

# The loop above only ever runs missing_references_for against a tree where
# every reference resolves, so on its own it proves the check exists, not that
# it works -- and testing-rules.md is explicit that a check never seen red is
# not yet a test. These two cases run the same function against a sandbox built
# to fail and one built to pass, which is what makes a later rewrite of the
# pattern detectable. Sandboxes live outside skills/, so the loop cannot see
# them.

# Guarded cleanup rather than `trap 'rm -rf "$SANDBOX"' EXIT`: an unguarded
# `rm -rf` on a variable is one editing accident away from being destructive.
# The other guards in this suite already use this form.
SANDBOX=""

cleanup_sandbox() {
    if [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ]; then
        rm -rf "$SANDBOX"
    fi
    SANDBOX=""
}
trap cleanup_sandbox EXIT

SANDBOX=$(mktemp -d)

# One `mkdir` for both cases, and a `printf` heredoc rather than `cat`:
# `printf` is a builtin where `cat` is a process, and `mkdir` is one either
# way.
mkdir -p "$SANDBOX/absent-ref" "$SANDBOX/present-ref/references"
printf '%s\n' \
    '---' \
    'description: Use as the red case for missing_references_for.' \
    '---' \
    'Read `references/absent.md` before starting.' \
    > "$SANDBOX/absent-ref/SKILL.md"

missing_references_for "$SANDBOX/absent-ref" "$SANDBOX/absent-ref/SKILL.md"
if [ -n "$MISSING_REFS" ]; then
    echo -e "${GREEN}PASS${NC}: a SKILL.md naming an absent reference -- reported as missing"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}FAIL${NC}: a SKILL.md naming an absent reference -- went undetected"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

printf 'present\n' > "$SANDBOX/present-ref/references/present.md"
printf '%s\n' \
    '---' \
    'description: Use as the green case for missing_references_for.' \
    '---' \
    'Read `references/present.md` before starting.' \
    > "$SANDBOX/present-ref/SKILL.md"

missing_references_for "$SANDBOX/present-ref" "$SANDBOX/present-ref/SKILL.md"
if [ -z "$MISSING_REFS" ]; then
    echo -e "${GREEN}PASS${NC}: a SKILL.md whose reference resolves -- reported nothing"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}FAIL${NC}: a SKILL.md whose reference resolves -- falsely reported missing"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

print_summary
