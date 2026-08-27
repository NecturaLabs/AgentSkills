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

# Built once. The hook reads exactly one file, so SKILL.md is all a case has
# to control -- and every case below sets it or removes it explicitly, so none
# can inherit the previous one's fixture. Rebuilding the tree instead cost a
# `mktemp`, a `mkdir` and a `cp` on each of eight cases, for a directory whose
# other two files never vary.
SANDBOX=$(mktemp -d)
SKILL_DIR="$SANDBOX/skills/using-necturalabs"
mkdir -p "$SANDBOX/hooks" "$SKILL_DIR"
read_file "$PROJECT_ROOT/hooks/session-start"
PRISTINE_HOOK="$READ_RESULT"
write_file "$SANDBOX/hooks/session-start" "$PRISTINE_HOOK"

# The one file a case varies. Written rather than copied, so a case costs no
# process before the hook itself runs.
set_skill_body() {
    write_file "$SKILL_DIR/SKILL.md" "$1"
}

# Invoked by path rather than from a `cd` inside a subshell: the hook derives
# its own root from $0, so the two are equivalent and the subshell was a
# second fork on every case.
HOOK_OUT=""
HOOK_STATUS=0

run_hook() {
    HOOK_STATUS=0
    HOOK_OUT=$(CLAUDE_PLUGIN_ROOT="$SANDBOX" \
        bash "$SANDBOX/hooks/session-start" 2>&1) || HOOK_STATUS=$?
}

set_skill_body 'plain skill body'
run_hook
assert_contains "$HOOK_OUT" '"hookSpecificOutput"' \
    "CLAUDE_PLUGIN_ROOT set -- emits the Claude Code wrapper" || true
assert_contains "$HOOK_OUT" '"hookEventName": "SessionStart"' \
    "CLAUDE_PLUGIN_ROOT set -- names the event" || true
assert_contains "$HOOK_OUT" 'plain skill body' \
    "the skill body reaches the injected context" || true

# Cursor and Claude Code read different keys. Emitting both would inject the
# skill twice into whichever host accepted them.
set_skill_body 'plain skill body'
CURSOR_OUT=$(CURSOR_PLUGIN_ROOT="$SANDBOX" \
    bash "$SANDBOX/hooks/session-start" 2>&1)
assert_contains "$CURSOR_OUT" '"additional_context"' \
    "CURSOR_PLUGIN_ROOT set -- emits the Cursor key" || true
assert_not_contains "$CURSOR_OUT" '"hookSpecificOutput"' \
    "CURSOR_PLUGIN_ROOT set -- does not also emit the Claude Code key" || true

# RFC 8259 requires every U+0000-U+001F be escaped. The hook escapes five and
# drops the rest; either way none may reach the output raw, or the host gets
# JSON it cannot parse and silently loads no skills.
printf 'before\001\007\013\037after\n' > "$SKILL_DIR/SKILL.md"
run_hook
CONTROL_OUT="$HOOK_OUT"
# Counted in the shell, where `tr -dc | wc -c` cost a fork and two processes:
# removing the same set and subtracting the lengths counts exactly what `tr`
# kept.
CONTROL_STRIPPED="${CONTROL_OUT//[$'\x01'$'\x07'$'\x0b'$'\x0c'$'\x0e'-$'\x1f']/}"
RAW_CONTROLS=$(( ${#CONTROL_OUT} - ${#CONTROL_STRIPPED} ))
assert_exit_status "$RAW_CONTROLS" 0 \
    "control characters -- none survive into the output" || true
assert_contains "$CONTROL_OUT" 'beforeafter' \
    "control characters -- the surrounding text is preserved" || true

# Tab, newline and return are the three controls that must survive, as escapes
# rather than raw bytes.
printf 'first\tcolumn\nsecond line\n' > "$SKILL_DIR/SKILL.md"
run_hook
ESCAPE_OUT="$HOOK_OUT"
assert_contains "$ESCAPE_OUT" 'first\tcolumn' \
    "a tab -- escaped rather than dropped" || true
assert_contains "$ESCAPE_OUT" 'column\nsecond' \
    "a newline -- escaped rather than dropped" || true

# A quote or backslash reaching the output unescaped would terminate the JSON
# string early, which is the difference between a broken hook and an injection.
printf 'a "quoted" word and a \\ backslash\n' > "$SKILL_DIR/SKILL.md"
run_hook
QUOTE_OUT="$HOOK_OUT"
assert_contains "$QUOTE_OUT" 'a \"quoted\" word' \
    "a double quote -- escaped" || true
assert_contains "$QUOTE_OUT" 'a \\ backslash' \
    "a backslash -- escaped" || true

# The shape run-hook.cmd's batch half actually hands this hook. `%~dp0` is
# always backslash-separated, so on Windows $0 arrives as
# C:\...\hooks\session-start; a derivation that splits on `/` alone finds no
# separator and resolves to the caller's directory, and the hook exits 0
# having injected nothing on every install. Every other case here invokes
# through a POSIX path, which is the one shape that bug does not reach.
#
# Run through `bash -c` with a synthetic $0 rather than a real Windows path.
# Gating on `cygpath` skipped this on Linux -- the only platform CI runs --
# so the guard for a Windows-only break never ran anywhere that mattered.
# Folding `plug\hooks\session-start` yields a path that resolves on both.
#
# The marker below is what holds the case: a derivation that falls back to
# the caller's directory can land on a real plugin root and emit a real
# SKILL.md, so the cwd alone would not catch it. Only this sandbox carries
# this string.
mkdir -p "$SANDBOX/plug/hooks" "$SANDBOX/plug/skills/using-necturalabs"
write_file "$SANDBOX/plug/skills/using-necturalabs/SKILL.md" \
    'backslash entrypoint marker'
BACKSLASH_OUT=$(cd "$SANDBOX" && CLAUDE_PLUGIN_ROOT="$SANDBOX/plug" \
    bash -c "$PRISTINE_HOOK" 'plug\hooks\session-start' 2>&1)
assert_contains "$BACKSLASH_OUT" 'backslash entrypoint marker' \
    "a backslash entrypoint path -- the hook still finds its skill" || true

# The other half of that derivation. An unfolded split has to be IN the
# chain, or a Unix directory name that legitimately contains a backslash gets
# folded into a path that does not exist -- something `dirname` never did.
# Mutating the chain to fold-only left the whole suite green on both
# platforms, so this branch had nothing holding it in place either.
#
# What this case pins is presence, not order: folding first and falling back
# to the unfolded split resolves the same directory, and it passes. Order
# decides only where both `a\b` and `a/b` exist, and trying unfolded first is
# what `dirname` settles on there.
#
# Skipped where the filesystem treats `\` as a separator: MSYS turns
# `lit\slash` into `lit/slash` at mkdir, so the shape cannot be built and the
# gate below sees the split directory. CI is Linux, where it runs.
BS_ROOT="$SANDBOX/lit\\slash"
mkdir -p "$BS_ROOT/hooks" "$BS_ROOT/skills/using-necturalabs" 2>/dev/null || true
if [ -d "$SANDBOX/lit" ]; then
    echo -e "  ${YELLOW}SKIP${NC}: literal backslash directory -- a path separator on this filesystem"
    SKIP_COUNT=$((SKIP_COUNT + 1))
else
    write_file "$BS_ROOT/skills/using-necturalabs/SKILL.md" \
        'literal backslash directory marker'
    LITERAL_BS_OUT=$(CLAUDE_PLUGIN_ROOT="$BS_ROOT" \
        bash -c "$PRISTINE_HOOK" "$BS_ROOT/hooks/session-start" 2>&1)
    assert_contains "$LITERAL_BS_OUT" 'literal backslash directory marker' \
        "a plugin dir named with a backslash -- the unfolded split wins" || true
fi

# The read-failure branch, and the `2>/dev/null` that keeps the absolute
# plugin path out of anything the hook emits. Every other case leaves both
# halves deletable with the whole suite still green, so neither had anything
# holding it in place.
#
# chmod 000 is the only way to make `[ -f ]` true while the read fails: a
# directory and a dangling link both fail `-f` and exit the hook early. It is
# a no-op for the owner on Windows and MSYS, so this skips there and runs on
# Linux, where CI runs it. Skipping honestly beats a green that proves
# nothing.
set_skill_body 'unreadable body'
chmod 000 "$SKILL_DIR/SKILL.md" 2>/dev/null || true
if [ -r "$SKILL_DIR/SKILL.md" ]; then
    echo -e "  ${YELLOW}SKIP${NC}: unreadable skill file -- chmod 000 is a no-op for the owner here"
    SKIP_COUNT=$((SKIP_COUNT + 1))
else
    run_hook
    assert_contains "$HOOK_OUT" 'Error reading using-necturalabs skill' \
        "an unreadable skill file -- the fallback reaches the host" || true
    # stdout and stderr are merged by run_hook, so an unsuppressed read error
    # lands here carrying the absolute path it names.
    assert_not_contains "$HOOK_OUT" "$SANDBOX" \
        "an unreadable skill file -- the plugin path is not disclosed" || true
fi
chmod 644 "$SKILL_DIR/SKILL.md" 2>/dev/null || true

# A missing skill file is the uninstalled case, not an error. Emitting a partial
# object there would hand the host malformed JSON on every session start.
rm -f "$SKILL_DIR/SKILL.md"
run_hook
MISSING_OUT="$HOOK_OUT"
assert_exit_status "$HOOK_STATUS" 0 \
    "no skill file -- exits 0 rather than failing the session" || true
assert_contains "${MISSING_OUT:-empty}" "empty" \
    "no skill file -- emits nothing at all" || true

# hooks.json invokes the wrapper, so the wrapper is the entrypoint every install
# runs. Its bash half skips the batch half through a `: << 'CMDBLOCK'` heredoc,
# and a CRLF checkout leaves `CMDBLOCK` plus a CR on disk: the heredoc never
# closes, `shift` plus a CR is a command rather than a builtin, and SCRIPT_NAME
# ends in a CR so the hook looks for a file that does not exist.
read_file "$PROJECT_ROOT/hooks/run-hook.cmd"
PRISTINE_WRAPPER="$READ_RESULT"
write_file "$SANDBOX/hooks/run-hook.cmd" "$PRISTINE_WRAPPER"
set_skill_body 'wrapper reaches the hook'
WRAPPER_STATUS=0
WRAPPER_OUT=$(cd "$SANDBOX" && CLAUDE_PLUGIN_ROOT="$SANDBOX" \
    bash hooks/run-hook.cmd session-start 2>&1) || WRAPPER_STATUS=$?
assert_exit_status "$WRAPPER_STATUS" 0 \
    "the wrapper -- its bash half runs rather than failing to parse" || true
assert_contains "$WRAPPER_OUT" 'wrapper reaches the hook' \
    "the wrapper -- reaches session-start and returns its output" || true

# The case above passes on Windows either way, because MSYS bash tolerates a
# stray CR where Linux and macOS bash do not. The byte count is what fails on
# every platform once the LF pin in .gitattributes is lost.
# Counted in the shell for the reason the control-character case states.
WRAPPER_CR_STRIPPED="${PRISTINE_WRAPPER//$'\r'/}"
WRAPPER_CR=$(( ${#PRISTINE_WRAPPER} - ${#WRAPPER_CR_STRIPPED} ))
assert_exit_status "$WRAPPER_CR" 0 \
    "the wrapper -- checked out with no CR bytes" || true

# One line reading exactly CMDBLOCK, or the heredoc hiding the batch half never
# closes. The opening `: << 'CMDBLOCK'` does not match this pattern.
WRAPPER_TERMINATORS=0
while IFS= read -r wrapper_line || [ -n "$wrapper_line" ]; do
    if [ "$wrapper_line" = "CMDBLOCK" ]; then
        WRAPPER_TERMINATORS=$((WRAPPER_TERMINATORS + 1))
    fi
done < "$PROJECT_ROOT/hooks/run-hook.cmd"
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
        INDEX_ENTRY=$(git -C "$PROJECT_ROOT" ls-files -s -- "$hook_path")
        INDEX_MODE="${INDEX_ENTRY%% *}"
        assert_contains "$INDEX_MODE" "100755" \
            "$hook_path -- recorded executable in the index" || true
    done
else
    echo -e "  ${YELLOW}SKIP${NC}: index modes -- this tree has no git index"
    SKIP_COUNT=$((SKIP_COUNT + 1))
fi

print_summary
