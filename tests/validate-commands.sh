#!/usr/bin/env bash
# Validate all commands have correct structure and align with skills

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/test-helpers.sh"

echo "Validating command structure..."

COMMANDS_DIR="$PROJECT_ROOT/commands"
SKILLS_DIR="$PROJECT_ROOT/skills"

if [ ! -d "$COMMANDS_DIR" ]; then
    echo -e "${RED}FAIL${NC}: commands/ directory not found"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    print_summary
    exit 1
fi

for cmd_file in "$COMMANDS_DIR"/*.md; do
    [ -f "$cmd_file" ] || continue
    cmd_name=$(basename "$cmd_file" .md)

    # Must have YAML frontmatter
    if ! head -1 "$cmd_file" | grep -q "^---"; then
        echo -e "${RED}FAIL${NC}: $cmd_name -- missing YAML frontmatter"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Must have description field
    if ! grep -q "^description:" "$cmd_file"; then
        echo -e "${RED}FAIL${NC}: $cmd_name -- missing 'description' in frontmatter"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Must have disable-model-invocation: true
    if ! grep -q "^disable-model-invocation: true" "$cmd_file"; then
        echo -e "${RED}FAIL${NC}: $cmd_name -- missing 'disable-model-invocation: true'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Must reference a necturalabs skill
    if ! grep -q "necturalabs:" "$cmd_file"; then
        echo -e "${RED}FAIL${NC}: $cmd_name -- does not reference a necturalabs skill"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Extract the skill name referenced in the command body
    skill_ref=$(grep -oE "necturalabs:[a-z-]+" "$cmd_file" | head -1 | sed 's/necturalabs://')

    # Referenced skill must exist
    if [ ! -d "$SKILLS_DIR/$skill_ref" ]; then
        echo -e "${RED}FAIL${NC}: $cmd_name -- references skill '$skill_ref' which does not exist"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    echo -e "${GREEN}PASS${NC}: $cmd_name -- valid structure, references skill '$skill_ref'"
    PASS_COUNT=$((PASS_COUNT + 1))
done

# Check that every skill with a command has one (informational — not all skills need commands)
echo ""
echo "Checking skill-to-command coverage..."
for skill_dir in "$SKILLS_DIR"/*/; do
    skill_name=$(basename "$skill_dir")
    # Look for any command that references this skill
    if grep -rql "necturalabs:$skill_name" "$COMMANDS_DIR" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $skill_name -- has command"
    else
        echo -e "  ${YELLOW}—${NC} $skill_name -- no command (auto-invoked or manual only)"
    fi
done

print_summary
