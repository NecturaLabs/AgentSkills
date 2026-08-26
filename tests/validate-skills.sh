#!/usr/bin/env bash
# Validate all skills have correct structure and frontmatter

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/test-helpers.sh"

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
# Echoes the paths that do not resolve, space-separated, and nothing when they
# all do. `|| true` is load-bearing under `set -euo pipefail`: grep exits 1 when
# a skill names no reference at all, which is legal -- 6 of the 13 skills do --
# and must not abort the run.
missing_references_for() {
    local dir="$1" file="$2" refs ref_path missing=""

    refs=$(grep -oE '(\.\./[A-Za-z0-9_-]+/)?references/[A-Za-z0-9_.-]+\.md' "$file" | sort -u || true)
    [ -n "$refs" ] || return 0

    while IFS= read -r ref_path; do
        [ -n "$ref_path" ] || continue
        [ -f "$dir/$ref_path" ] || missing="$missing $ref_path"
    done <<< "$refs"

    printf '%s' "$missing"
}

echo "Validating skill structure..."

for skill_dir in "$PROJECT_ROOT"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    skill_file="$skill_dir/SKILL.md"

    # SKILL.md must exist
    if [ ! -f "$skill_file" ]; then
        echo -e "${RED}FAIL${NC}: $skill_name -- missing SKILL.md"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Must have YAML frontmatter
    if ! head -1 "$skill_file" | grep -q "^---"; then
        echo -e "${RED}FAIL${NC}: $skill_name -- missing YAML frontmatter"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Must have description field
    if ! grep -q "^description:" "$skill_file"; then
        echo -e "${RED}FAIL${NC}: $skill_name -- missing 'description' in frontmatter"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Name must match directory name (if present)
    if grep -q "^name:" "$skill_file"; then
        frontmatter_name=$(grep "^name:" "$skill_file" | sed 's/^name: *//')
        if [ "$frontmatter_name" != "$skill_name" ]; then
            echo -e "${RED}FAIL${NC}: $skill_name -- frontmatter name '$frontmatter_name' doesn't match directory"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            continue
        fi
    fi

    # Description must start with an actionable verb phrase
    description=$(grep "^description:" "$skill_file" \
        | sed 's/^description: *//')
    if ! echo "$description" | grep -qiE "^(Use |MUST |Create |Update )"; then
        echo -e "${YELLOW}WARN${NC}: $skill_name -- description should start with an actionable verb (Use/MUST/Create/Update)"
    fi

    # Frontmatter must be under 1024 chars total
    frontmatter=$(sed -n '/^---$/,/^---$/p' "$skill_file")
    frontmatter_len=${#frontmatter}
    if [ "$frontmatter_len" -gt 1024 ]; then
        echo -e "${RED}FAIL${NC}: $skill_name -- frontmatter exceeds 1024 chars ($frontmatter_len)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    missing_refs=$(missing_references_for "$skill_dir" "$skill_file")
    if [ -n "$missing_refs" ]; then
        echo -e "${RED}FAIL${NC}: $skill_name -- SKILL.md names reference file(s) that do not exist:$missing_refs"
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

mkdir -p "$SANDBOX/absent-ref"
cat > "$SANDBOX/absent-ref/SKILL.md" <<'ABSENT_REF'
---
description: Use as the red case for missing_references_for.
---
Read `references/absent.md` before starting.
ABSENT_REF

if [ -n "$(missing_references_for "$SANDBOX/absent-ref" "$SANDBOX/absent-ref/SKILL.md")" ]; then
    echo -e "${GREEN}PASS${NC}: a SKILL.md naming an absent reference -- reported as missing"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}FAIL${NC}: a SKILL.md naming an absent reference -- went undetected"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

mkdir -p "$SANDBOX/present-ref/references"
printf 'present\n' > "$SANDBOX/present-ref/references/present.md"
cat > "$SANDBOX/present-ref/SKILL.md" <<'PRESENT_REF'
---
description: Use as the green case for missing_references_for.
---
Read `references/present.md` before starting.
PRESENT_REF

if [ -z "$(missing_references_for "$SANDBOX/present-ref" "$SANDBOX/present-ref/SKILL.md")" ]; then
    echo -e "${GREEN}PASS${NC}: a SKILL.md whose reference resolves -- reported nothing"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}FAIL${NC}: a SKILL.md whose reference resolves -- falsely reported missing"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

print_summary
