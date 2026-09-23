#!/bin/sh
# Round-trip test for scripts/install.sh in a throwaway HOME.
#
# Installs from this checkout (FabCLI is downloaded and checksum-verified), checks every artifact
# landed, uninstalls, and fails if anything named after necturalabs-fab or FabCLI — or any reference to
# them in Claude Code or Codex state — is left behind. Claude Code and Codex are exercised when their
# CLIs are on PATH. The real HOME is never touched; sign-in is skipped.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SANDBOX=$(mktemp -d)
trap '[ -n "${KEEP_SANDBOX:-}" ] || rm -rf "$SANDBOX"' EXIT INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$*"; }

# Keep the real Rust toolchain reachable once HOME moves.
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
# Version-manager shims (mise, asdf) resolve through HOME, so call cargo directly. The real
# ~/.local/bin is dropped: a fabcli or necturalabs-fab installed there must not stand in for the
# sandbox's own.
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vx "$HOME/.local/bin" | paste -sd: -)
export PATH="$CARGO_HOME/bin:$PATH"
export HOME="$SANDBOX"
# The OS keyring is per user, not per HOME: uninstall's `fabcli auth logout` would delete the real
# user's FabCLI key. Cut the sandbox off from the session bus so no keyring is reachable.
if [ "$(uname -s)" = Darwin ]; then
  fail "macOS keychains are not isolated by HOME; run this test on Linux or in a VM"
fi
export DBUS_SESSION_BUS_ADDRESS="unix:path=$SANDBOX/no-session-bus"
unset DBUS_SYSTEM_BUS_ADDRESS || true
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME CODEX_HOME CLAUDE_CONFIG_DIR NECTURALABS_FAB_BIN_DIR || true
BIN="$SANDBOX/bin"

sh "$ROOT/scripts/install.sh" --no-login --bin-dir "$BIN" --source "$ROOT"

[ -x "$BIN/necturalabs-fab" ] || fail "necturalabs-fab not installed"
pass "necturalabs-fab installed"
if [ "$(uname -s)-$(uname -m)" = Linux-x86_64 ]; then
  [ -x "$BIN/fabcli" ] || fail "fabcli not installed"
  "$BIN/fabcli" --version | grep -q '^fabcli 0\.1\.' || fail "unexpected fabcli version"
  pass "fabcli installed"
fi
[ -f "$SANDBOX/.local/share/necturalabs-fab/install.manifest" ] || fail "no install manifest"
pass "manifest written"

status=$(NECTURALABS_FAB_FABCLI_PATH="$BIN/fabcli" "$BIN/necturalabs-fab" --json skill status)
if command -v claude >/dev/null 2>&1; then
  printf '%s' "$status" | grep -q '"harness":"claude-code","installed":true' || fail "Claude Code plugin missing: $status"
  pass "Claude Code plugin installed"
fi
if command -v codex >/dev/null 2>&1; then
  printf '%s' "$status" | grep -q '"harness":"codex","installed":true' || fail "Codex plugin missing: $status"
  pass "Codex plugin installed"
fi
NECTURALABS_FAB_FABCLI_PATH="$BIN/fabcli" "$BIN/necturalabs-fab" --json doctor | grep -q '"ok":true' || fail "doctor failed"
pass "doctor ran"

# The licence cache necturalabs-fab writes as it runs goes with it.
mkdir -p "$SANDBOX/.cache/necturalabs-fab"
printf '{"version":1,"entries":{}}\n' > "$SANDBOX/.cache/necturalabs-fab/licenses.json"

sh "$ROOT/scripts/install.sh" --uninstall

leftovers=$(find "$SANDBOX" \( -iname '*nectura*' -o -iname '*fabcli*' \) -print)
[ -z "$leftovers" ] || fail "files left behind:
$leftovers"
references=$(grep -rIl -e 'necturalabs-fab' -e 'fabcli' "$SANDBOX" 2>/dev/null || true)
[ -z "$references" ] || fail "references left behind in:
$references"
pass "uninstall left nothing behind"
[ ! -e "$BIN" ] || fail "the bin directory the installer created was left behind"
pass "created bin directory removed"

# A fabcli the installer did not put there is never overwritten.
FOREIGN="$SANDBOX/foreign-bin"
mkdir -p "$FOREIGN"
printf '#!/bin/sh\necho not-fabcli\n' > "$FOREIGN/fabcli"
chmod +x "$FOREIGN/fabcli"
if [ "$(uname -s)-$(uname -m)" = Linux-x86_64 ]; then
  if sh "$ROOT/scripts/install.sh" --no-login --no-plugin --bin-dir "$FOREIGN" --source "$ROOT" 2>/dev/null; then
    fail "installer overwrote a foreign fabcli"
  fi
  grep -q not-fabcli "$FOREIGN/fabcli" || fail "foreign fabcli was modified"
  pass "foreign fabcli left alone"
fi
rm -rf "$FOREIGN" "$SANDBOX/.local"

# FabCLI state that predates the install survives uninstall.
mkdir -p "$SANDBOX/.config/fabcli"
printf 'user-owned\n' > "$SANDBOX/.config/fabcli/marker"
sh "$ROOT/scripts/install.sh" --no-login --no-plugin --bin-dir "$BIN" --source "$ROOT" >/dev/null
sh "$ROOT/scripts/install.sh" --uninstall >/dev/null
[ -f "$SANDBOX/.config/fabcli/marker" ] || fail "uninstall deleted FabCLI state it did not create"
[ ! -e "$BIN/fabcli" ] || fail "fabcli binary left behind"
pass "pre-existing FabCLI state kept"
