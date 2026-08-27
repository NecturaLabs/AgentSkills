: << 'CMDBLOCK'
@echo off
REM Cross-platform polyglot wrapper for hook scripts.
REM On Windows: cmd.exe runs the batch portion, which finds and calls bash.
REM On Unix: the shell interprets this as a script (: is a no-op in bash).
REM
REM Usage: run-hook.cmd <script-name> [args...]

if "%~1"=="" (
    echo run-hook.cmd: missing script name >&2
    exit /b 1
)

set "HOOK_DIR=%~dp0"

REM Try Git for Windows bash in standard locations
if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    "C:\Program Files (x86)\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)

REM Try bash on PATH
where bash >nul 2>nul
if %ERRORLEVEL% equ 0 (
    bash "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)

REM No bash found - emit warning to stderr
echo run-hook.cmd: bash not found, hooks disabled >&2
exit /b 0
CMDBLOCK

# Unix: run the named script directly.
#
# `cd` and $PWD are builtins, where `$(cd "$(dirname "$0")" && pwd)` cost two
# processes, one of them a `dirname`. hooks.json invokes this wrapper rather
# than the hook, so this is the path every install actually runs. CDPATH is
# cleared because a set one sends `cd` elsewhere and echoes where it landed.
#
# The unfolded split is tried first, then a backslash-folded one, for the
# reason session-start states: a $0 using backslashes finds no `/` to split
# on and silently resolves to the caller's directory, while a Unix directory
# name may legitimately contain one.
CDPATH=""
PREV_PWD=$PWD
SELF=${0//\\//}
cd "${0%/*}" 2>/dev/null || cd "${SELF%/*}" 2>/dev/null || cd "$PREV_PWD"
SCRIPT_DIR=$PWD
cd "$PREV_PWD"
SCRIPT_NAME="$1"
shift
exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
