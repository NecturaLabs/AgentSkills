#!/usr/bin/env bash
# Behaviour guard for hooks/session-start.
#
# That hook runs on every session start for every installed user and is the only
# thing that injects using-necturalabs into a session. It had no test at any
# level while carrying three separate pieces of logic: JSON escaping, a
# control-character strip, and a two-host output shape.
#
# Assertions here are dependency-free on purpose. A real JSON parse would be
# stronger, but it would put node or python between this repo and a green run,
# and AGENTS.md commits the suite to running offline with nothing installed.
# What is checked instead is every byte-level property the escaping must hold.
#
# The sandbox carries no .git, so the update-check branch is skipped and no
# `git ls-remote` reaches the network.
#
# hooks/run-hook.cmd is covered too. hooks.json invokes the wrapper, not the
# hook, so the wrapper is the entrypoint every install actually runs, and its
# bash half is what a CRLF checkout or a missing exec bit breaks. Neither had a
# test at any level.

set -euo pipefail

# Parameter expansion instead of `dirname` in its own subshell, `|| pwd` for a
# source path with no directory part, and, where a parent is wanted, a prefix
# of the canonical result rather than a second `cd`. test-helpers.sh states
# what one process costs in this suite.
TESTS_DIR="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd || pwd)"
PROJECT_ROOT="${TESTS_DIR%/*}"
source "$TESTS_DIR/test-helpers.sh"

echo "Validating the session-start hook..."

SANDBOX=""

cleanup_sandbox() {
    if [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ]; then
        rm -rf "$SANDBOX"
    fi
    SANDBOX=""
}
trap cleanup_sandbox EXIT

SKILL_DIR=""

# Rebuild from scratch per case: the hook reads exactly one file, so a leftover
# fixture from a previous case would be the thing under test.
reset_hook_sandbox() {
    cleanup_sandbox
    SANDBOX=$(mktemp -d)
    SKILL_DIR="$SANDBOX/skills/using-necturalabs"
    mkdir -p "$SANDBOX/hooks" "$SKILL_DIR"
    cp "$PROJECT_ROOT/hooks/session-start" "$SANDBOX/hooks/session-start"
}

run_hook() {
    ( cd "$SANDBOX" && CLAUDE_PLUGIN_ROOT="$SANDBOX" bash hooks/session-start 2>&1 )
}

reset_hook_sandbox
printf 'plain skill body\n' > "$SKILL_DIR/SKILL.md"
HOOK_OUT=$(run_hook)
assert_contains "$HOOK_OUT" '"hookSpecificOutput"' \
    "CLAUDE_PLUGIN_ROOT set -- emits the Claude Code wrapper" || true
assert_contains "$HOOK_OUT" '"hookEventName": "SessionStart"' \
    "CLAUDE_PLUGIN_ROOT set -- names the event" || true
assert_contains "$HOOK_OUT" 'plain skill body' \
    "the skill body reaches the injected context" || true

# Cursor and Claude Code read different keys. Emitting both would inject the
# skill twice into whichever host accepted them.
reset_hook_sandbox
printf 'plain skill body\n' > "$SKILL_DIR/SKILL.md"
CURSOR_OUT=$( cd "$SANDBOX" && CURSOR_PLUGIN_ROOT="$SANDBOX" bash hooks/session-start 2>&1 )
assert_contains "$CURSOR_OUT" '"additional_context"' \
    "CURSOR_PLUGIN_ROOT set -- emits the Cursor key" || true
assert_not_contains "$CURSOR_OUT" '"hookSpecificOutput"' \
    "CURSOR_PLUGIN_ROOT set -- does not also emit the Claude Code key" || true

# RFC 8259 requires every U+0000-U+001F be escaped. The hook escapes five and
# drops the rest; either way none may reach the output raw, or the host gets
# JSON it cannot parse and silently loads no skills.
reset_hook_sandbox
printf 'before\001\007\013\037after\n' > "$SKILL_DIR/SKILL.md"
CONTROL_OUT=$(run_hook)
RAW_CONTROLS=$(printf '%s' "$CONTROL_OUT" | tr -dc '\001\007\013\014\016-\037' | wc -c)
assert_exit_status "$RAW_CONTROLS" 0 \
    "control characters -- none survive into the output" || true
assert_contains "$CONTROL_OUT" 'beforeafter' \
    "control characters -- the surrounding text is preserved" || true

# Tab, newline and return are the three controls that must survive, as escapes
# rather than raw bytes.
reset_hook_sandbox
printf 'first\tcolumn\nsecond line\n' > "$SKILL_DIR/SKILL.md"
ESCAPE_OUT=$(run_hook)
assert_contains "$ESCAPE_OUT" 'first\tcolumn' \
    "a tab -- escaped rather than dropped" || true
assert_contains "$ESCAPE_OUT" 'column\nsecond' \
    "a newline -- escaped rather than dropped" || true

# A quote or backslash reaching the output unescaped would terminate the JSON
# string early, which is the difference between a broken hook and an injection.
reset_hook_sandbox
printf 'a "quoted" word and a \\ backslash\n' > "$SKILL_DIR/SKILL.md"
QUOTE_OUT=$(run_hook)
assert_contains "$QUOTE_OUT" 'a \"quoted\" word' \
    "a double quote -- escaped" || true
assert_contains "$QUOTE_OUT" 'a \\ backslash' \
    "a backslash -- escaped" || true

# A missing skill file is the uninstalled case, not an error. Emitting a partial
# object there would hand the host malformed JSON on every session start.
reset_hook_sandbox
MISSING_STATUS=0
MISSING_OUT=$(run_hook) || MISSING_STATUS=$?
assert_exit_status "$MISSING_STATUS" 0 \
    "no skill file -- exits 0 rather than failing the session" || true
assert_contains "${MISSING_OUT:-empty}" "empty" \
    "no skill file -- emits nothing at all" || true

# hooks.json invokes the wrapper, so the wrapper is the entrypoint every install
# runs. Its bash half skips the batch half through a `: << 'CMDBLOCK'` heredoc,
# and a CRLF checkout leaves `CMDBLOCK` plus a CR on disk: the heredoc never
# closes, `shift` plus a CR is a command rather than a builtin, and SCRIPT_NAME
# ends in a CR so the hook looks for a file that does not exist.
reset_hook_sandbox
cp "$PROJECT_ROOT/hooks/run-hook.cmd" "$SANDBOX/hooks/run-hook.cmd"
printf 'wrapper reaches the hook\n' > "$SKILL_DIR/SKILL.md"
WRAPPER_STATUS=0
WRAPPER_OUT=$( cd "$SANDBOX" && CLAUDE_PLUGIN_ROOT="$SANDBOX" \
    bash hooks/run-hook.cmd session-start 2>&1 ) || WRAPPER_STATUS=$?
assert_exit_status "$WRAPPER_STATUS" 0 \
    "the wrapper -- its bash half runs rather than failing to parse" || true
assert_contains "$WRAPPER_OUT" 'wrapper reaches the hook' \
    "the wrapper -- reaches session-start and returns its output" || true

# The case above passes on Windows either way, because MSYS bash tolerates a
# stray CR where Linux and macOS bash do not. The byte count is what fails on
# every platform once the LF pin in .gitattributes is lost.
WRAPPER_CR=$(tr -dc '\r' < "$PROJECT_ROOT/hooks/run-hook.cmd" | wc -c)
assert_exit_status "$WRAPPER_CR" 0 \
    "the wrapper -- checked out with no CR bytes" || true

# One line reading exactly CMDBLOCK, or the heredoc hiding the batch half never
# closes. The opening `: << 'CMDBLOCK'` does not match this pattern.
WRAPPER_TERMINATORS=$(grep -c '^CMDBLOCK$' "$PROJECT_ROOT/hooks/run-hook.cmd" \
    || true)
assert_exit_status "$WRAPPER_TERMINATORS" 1 \
    "the wrapper -- exactly one bare heredoc terminator" || true

# The index is the authority on the exec bit, not the working tree: Windows
# checkouts set core.filemode false, and `[ -x ]` is true for everything there.
# A 100644 wrapper is the `Permission denied` a Unix install hits on its first
# session. Reading the index is local; nothing here contacts a remote.
#
# A tree with no index cannot answer the question, so that is a skip rather than
# a pass. It is not a permanently skipped test: every checkout and every CI run
# has an index.
if git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    for hook_path in hooks/run-hook.cmd hooks/session-start; do
        INDEX_MODE=$(git -C "$PROJECT_ROOT" ls-files -s -- "$hook_path" \
            | cut -d' ' -f1)
        assert_contains "$INDEX_MODE" "100755" \
            "$hook_path -- recorded executable in the index" || true
    done
else
    echo -e "  ${YELLOW}SKIP${NC}: index modes -- this tree has no git index"
    SKIP_COUNT=$((SKIP_COUNT + 1))
fi

print_summary
