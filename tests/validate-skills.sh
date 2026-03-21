#!/usr/bin/env bash
# Validate all skills have correct structure and frontmatter

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/test-helpers.sh"

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

    # Must have name field
    if ! grep -q "^name:" "$skill_file"; then
        echo -e "${RED}FAIL${NC}: $skill_name -- missing 'name' in frontmatter"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Must have description field
    if ! grep -q "^description:" "$skill_file"; then
        echo -e "${RED}FAIL${NC}: $skill_name -- missing 'description' in frontmatter"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Name must match directory name
    frontmatter_name=$(grep "^name:" "$skill_file" | sed 's/^name: *//')
    if [ "$frontmatter_name" != "$skill_name" ]; then
        echo -e "${RED}FAIL${NC}: $skill_name -- frontmatter name '$frontmatter_name' doesn't match directory"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Description must start with "Use when" or "Use at" or "Use automatically"
    description=$(grep "^description:" "$skill_file" | sed 's/^description: *//')
    if ! echo "$description" | grep -qi "^Use "; then
        echo -e "${YELLOW}WARN${NC}: $skill_name -- description should start with 'Use when...'"
    fi

    # Frontmatter must be under 1024 chars total
    frontmatter=$(sed -n '/^---$/,/^---$/p' "$skill_file")
    frontmatter_len=${#frontmatter}
    if [ "$frontmatter_len" -gt 1024 ]; then
        echo -e "${RED}FAIL${NC}: $skill_name -- frontmatter exceeds 1024 chars ($frontmatter_len)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    echo -e "${GREEN}PASS${NC}: $skill_name -- valid structure"
    PASS_COUNT=$((PASS_COUNT + 1))
done

print_summary
