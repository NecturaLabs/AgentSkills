#!/bin/sh
# necturalabs-fab installer and uninstaller for Linux and macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/NecturaLabs/FabCLI/main/scripts/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/NecturaLabs/FabCLI/main/scripts/install.sh | sh -s -- --uninstall
#
# Installs FabCLI (pinned, checksum-verified) and necturalabs-fab into one bin directory, installs the
# agent skill as a plugin through the Claude Code and Codex plugin marketplaces, and offers to sign
# in. Everything it creates is recorded in a manifest; --uninstall removes exactly that, plus the
# caches those harnesses leave behind for it, and nothing else.

set -eu

REPO="NecturaLabs/FabCLI"
MARKETPLACE="necturalabs-fab"
PLUGIN="necturalabs-fab@necturalabs-fab"

# FabCLI release necturalabs-fab is verified against. Its checksum is pinned here rather than read
# from the release page, so a replaced release asset cannot slip through.
FABCLI_VERSION="0.1.0"
FABCLI_LINUX_ASSET="fabcli-v${FABCLI_VERSION}-linux64.tar.gz"
FABCLI_LINUX_SHA256="cee5d93250428c7f899d46ff5a58705c71c0cbf8c24f97e47d357a2a008efd70"
FABCLI_SUPPORTED_PREFIX="fabcli 0.1."

usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Install:
  --bin-dir DIR     Where fabcli and necturalabs-fab go (default: ~/.local/bin,
                    or $NECTURALABS_FAB_BIN_DIR).
  --version TAG     Release to install, e.g. v0.1.0 (default: the latest release,
                    or $NECTURALABS_FAB_VERSION). The binary and the skill come
                    from the same release.
  --source DIR      Build necturalabs-fab from this checkout and install the skill
                    from it. Default when the script runs from a checkout.
  --no-plugin       Skip installing the skill plugin into Claude Code and Codex
                    ($NECTURALABS_FAB_NO_PLUGIN=1).
  --no-login        Do not offer to sign in afterwards ($NECTURALABS_FAB_NO_LOGIN=1).
  -y, --yes         Answer yes to every question (sign-in included).

Uninstall:
  --uninstall       Remove everything the installer recorded, sign FabCLI out
                    (token, keyring entry, browser data) and delete its state.
  --keep-config     With --uninstall: keep ~/.config/necturalabs-fab.

  -h, --help        Show this help.
USAGE
}

ACTION=install
BIN_DIR=${NECTURALABS_FAB_BIN_DIR:-${HOME}/.local/bin}
SOURCE=""
TAG=${NECTURALABS_FAB_VERSION:-}
DO_PLUGIN=1
DO_LOGIN=1
[ "${NECTURALABS_FAB_NO_PLUGIN:-0}" = 1 ] && DO_PLUGIN=0
[ "${NECTURALABS_FAB_NO_LOGIN:-0}" = 1 ] && DO_LOGIN=0
ASSUME_YES=0
KEEP_CONFIG=0

die() { printf 'necturalabs-fab: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

while [ "$#" -gt 0 ]; do
  case $1 in
    --uninstall) ACTION=uninstall ;;
    --keep-config) KEEP_CONFIG=1 ;;
    --bin-dir) [ "$#" -ge 2 ] || die "--bin-dir needs a directory"; BIN_DIR=$2; shift ;;
    --bin-dir=*) BIN_DIR=${1#--bin-dir=} ;;
    --source) [ "$#" -ge 2 ] || die "--source needs a directory"; SOURCE=$2; shift ;;
    --source=*) SOURCE=${1#--source=} ;;
    --version) [ "$#" -ge 2 ] || die "--version needs a release tag"; TAG=$2; shift ;;
    --version=*) TAG=${1#--version=} ;;
    --no-plugin) DO_PLUGIN=0 ;;
    --no-login) DO_LOGIN=0 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

[ -n "${HOME:-}" ] || die "HOME is not set"
case $BIN_DIR in /*) ;; *) die "--bin-dir must be an absolute path" ;; esac
case $TAG in "" | v[0-9]*) ;; *) die "--version must be a release tag such as v0.1.0" ;; esac
case $TAG in *[!A-Za-z0-9.+-]*) die "--version contains unexpected characters" ;; esac

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/necturalabs-fab"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
# Where necturalabs-fab keeps its licence cache: an absolute XDG_CACHE_HOME wins on every
# platform, as it does in the binary.
case ${XDG_CACHE_HOME:-} in
  /*) CACHE_DIR="$XDG_CACHE_HOME/necturalabs-fab" ;;
  *) if [ "$(uname -s)" = Darwin ]; then CACHE_DIR="$HOME/Library/Caches/necturalabs-fab"
     else CACHE_DIR="$HOME/.cache/necturalabs-fab"; fi ;;
esac
MANIFEST="$DATA_DIR/install.manifest"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"

WORK=""
cleanup() { if [ -n "$WORK" ]; then rm -rf "$WORK"; fi; }
trap cleanup EXIT
trap 'cleanup; trap - EXIT; exit 130' INT
trap 'cleanup; trap - EXIT; exit 143' TERM

# --- manifest -----------------------------------------------------------------------------

record() {
  mkdir -p "$DATA_DIR"
  {
    if [ -f "$MANIFEST" ]; then grep -v "^$1=" "$MANIFEST" || true; fi
    printf '%s=%s\n' "$1" "$2"
  } > "$MANIFEST.tmp"
  mv "$MANIFEST.tmp" "$MANIFEST"
}

recorded() {
  [ -f "$MANIFEST" ] || return 0
  sed -n "s/^$1=//p" "$MANIFEST" | tail -n 1
}

forget() {
  [ -f "$MANIFEST" ] || return 0
  { grep -v "^$1=" "$MANIFEST" || true; } > "$MANIFEST.tmp"
  mv "$MANIFEST.tmp" "$MANIFEST"
}

# --- helpers ------------------------------------------------------------------------------

fetch() {
  if have curl; then
    curl -fsSL --proto '=https' --tlsv1.2 -o "$2" "$1"
  elif have wget; then
    wget -q -O "$2" "$1"
  else
    die "curl or wget is required"
  fi
}

sha256_of() {
  if have sha256sum; then sha256sum "$1" | cut -d ' ' -f 1
  elif have shasum; then shasum -a 256 "$1" | cut -d ' ' -f 1
  else die "sha256sum or shasum is required"; fi
}

# True when a controlling terminal can actually be opened (a readable /dev/tty node is not enough).
have_tty() { ( : < /dev/tty ) 2>/dev/null; }

# Questions go to the terminal, not stdin: under `curl ... | sh` stdin is the script itself.
confirm() {
  [ "$ASSUME_YES" = 1 ] && return 0
  if have_tty; then
    printf '%s [Y/n] ' "$1" > /dev/tty
    answer=""
    read -r answer < /dev/tty || answer=n
    case $answer in n|N|no|NO|No) return 1 ;; *) return 0 ;; esac
  fi
  return 1
}

claude_has_marketplace() {
  claude plugin marketplace list --json 2>/dev/null | grep -q "\"name\": *\"$MARKETPLACE\""
}

claude_has_plugin() {
  claude plugin list --json 2>/dev/null | grep -q "\"id\": *\"$PLUGIN\""
}

codex_has_marketplace() {
  codex plugin marketplace list 2>/dev/null | awk '{ print $1 }' | grep -qx "$MARKETPLACE"
}

codex_has_plugin() {
  [ -f "$CODEX_DIR/config.toml" ] && grep -q "^\[plugins\.\"$PLUGIN\"\]" "$CODEX_DIR/config.toml"
}

detect_checkout() {
  [ -n "$SOURCE" ] && return 0
  case $0 in */*) ;; *) return 0 ;; esac
  dir=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd) || return 0
  if [ -f "$dir/Cargo.toml" ] && grep -q '^name = "necturalabs-fab"' "$dir/Cargo.toml"; then
    SOURCE=$dir
  fi
}

# The release every remote artifact comes from, so the binary and the skill always match.
resolve_tag() {
  [ -n "$SOURCE" ] && return 0
  [ -n "$TAG" ] && return 0
  url=""
  if have curl; then
    url=$(curl -fsSLI --proto '=https' --tlsv1.2 -o /dev/null -w '%{url_effective}' \
      "https://github.com/$REPO/releases/latest" 2>/dev/null) || url=""
  fi
  TAG=${url##*/}
  # A private repository answers anonymous requests with 404; a signed-in gh can still see it.
  case $TAG in
    v[0-9]*) ;;
    *) if have gh; then
         TAG=$(gh release view -R "$REPO" --json tagName -q .tagName 2>/dev/null || true)
         VIA_GH=1
       fi ;;
  esac
  case $TAG in v[0-9]*) ;; *) die "no release of $REPO found (got '$TAG'); pass --version" ;; esac
  case $TAG in *[!A-Za-z0-9.+-]*) die "unexpected release tag '$TAG'" ;; esac
}

# Download one asset of the pinned release: anonymously, or through a signed-in gh for a private
# repository.
fetch_release_asset() {
  fetch "https://github.com/$REPO/releases/download/$TAG/$1" "$2" 2>/dev/null && return 0
  have gh && gh release download "$TAG" -R "$REPO" -p "$1" -O "$2" --clobber >/dev/null 2>&1
}

# Where both harnesses add the marketplace from: this checkout, or the pinned release tag.
claude_marketplace_source() { if [ -n "$SOURCE" ]; then printf '%s' "$SOURCE"; else printf '%s#%s' "$REPO" "$TAG"; fi; }

ensure_bin_dir() {
  if [ ! -d "$BIN_DIR" ]; then
    mkdir -p "$BIN_DIR"
    [ -n "$(recorded bin_dir)" ] || record bin_dir "created:$BIN_DIR"
  fi
}

# --- install steps ------------------------------------------------------------------------

install_fabcli() {
  existing=$(command -v fabcli 2>/dev/null || true)
  ours=$(recorded fabcli)
  if [ -n "$existing" ] && [ "installed:$existing" != "$ours" ]; then
    if "$existing" --version 2>/dev/null | grep -q "^$FABCLI_SUPPORTED_PREFIX"; then
      say "FabCLI: using the one already at $existing"
      [ -n "$ours" ] || record fabcli "preexisting:$existing"
      FABCLI_PATH=$existing
      return 0
    fi
    warn "$existing is not FabCLI ${FABCLI_SUPPORTED_PREFIX#fabcli }x; installing $FABCLI_VERSION into $BIN_DIR"
  fi

  if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
    warn "FabCLI publishes builds for Linux x86-64 and Windows x86-64 only; install it manually"
    warn "and necturalabs-fab will pick it up (see docs/installation.md)"
    FABCLI_PATH=""
    return 0
  fi

  if { [ -e "$BIN_DIR/fabcli" ] || [ -L "$BIN_DIR/fabcli" ]; } && [ "$ours" != "installed:$BIN_DIR/fabcli" ]; then
    die "$BIN_DIR/fabcli exists and was not installed by necturalabs-fab; remove it or choose --bin-dir"
  fi

  say "FabCLI: downloading $FABCLI_VERSION"
  fetch "https://github.com/zirklerite/FabCLI/releases/download/v$FABCLI_VERSION/$FABCLI_LINUX_ASSET" \
    "$WORK/$FABCLI_LINUX_ASSET"
  actual=$(sha256_of "$WORK/$FABCLI_LINUX_ASSET")
  [ "$actual" = "$FABCLI_LINUX_SHA256" ] || die "FabCLI checksum mismatch (got $actual); refusing to install"
  tar -xzf "$WORK/$FABCLI_LINUX_ASSET" -C "$WORK"
  ensure_bin_dir
  # FabCLI keeps its sign-in state here. State that predates us belongs to the user: uninstall
  # must then neither sign it out nor delete it.
  if [ -z "$(recorded fabcli_state)" ]; then
    if [ -e "$CONFIG_HOME/fabcli" ]; then record fabcli_state preexisting; else record fabcli_state ours; fi
  fi
  install -m 755 "$WORK/fabcli-v$FABCLI_VERSION-linux64/fabcli" "$BIN_DIR/fabcli"
  record fabcli "installed:$BIN_DIR/fabcli"
  FABCLI_PATH="$BIN_DIR/fabcli"
  say "FabCLI: installed $BIN_DIR/fabcli (checksum verified)"

  if have ldd; then
    missing=$(ldd "$BIN_DIR/fabcli" 2>/dev/null | awk '/not found/ { print $1 }' | tr '\n' ' ')
    if [ -n "$missing" ]; then
      warn "FabCLI's sign-in window needs libraries that are missing: $missing"
      warn "Arch: pacman -S webkit2gtk-4.1 | Debian/Ubuntu: apt install libwebkit2gtk-4.1-0 libsoup-3.0-0"
    fi
  fi
}

install_necturalabs_fab() {
  ensure_bin_dir
  if [ -n "$SOURCE" ]; then
    have cargo || die "building from a checkout needs Rust: https://rustup.rs"
    say "necturalabs-fab: building from $SOURCE"
    (cd "$SOURCE" && cargo build --release --locked --bin necturalabs-fab --quiet)
    install -m 755 "$SOURCE/target/release/necturalabs-fab" "$BIN_DIR/necturalabs-fab"
  else
    case "$(uname -s)-$(uname -m)" in
      Linux-x86_64) target=x86_64-unknown-linux-musl ;;
      *) target="" ;;
    esac
    asset="necturalabs-fab-$target.tar.gz"
    if [ -n "$target" ] && fetch_release_asset "$asset" "$WORK/$asset" \
        && fetch_release_asset SHA256SUMS "$WORK/SHA256SUMS"; then
      expected=$(awk -v f="$asset" '$2 == f || $2 == "*" f { print $1 }' "$WORK/SHA256SUMS")
      [ -n "$expected" ] || die "release SHA256SUMS has no entry for $asset"
      [ "$(sha256_of "$WORK/$asset")" = "$expected" ] || die "necturalabs-fab checksum mismatch; refusing to install"
      tar -xzf "$WORK/$asset" -C "$WORK"
      install -m 755 "$WORK/necturalabs-fab" "$BIN_DIR/necturalabs-fab"
      say "necturalabs-fab: installed $TAG (checksum verified)"
    elif have cargo; then
      say "necturalabs-fab: no release build for this platform; compiling with cargo"
      cargo install --quiet --locked --git "https://github.com/$REPO" --tag "$TAG" --root "$WORK/cargo" necturalabs-fab --bin necturalabs-fab
      install -m 755 "$WORK/cargo/bin/necturalabs-fab" "$BIN_DIR/necturalabs-fab"
    else
      die "no release build for this platform and no Rust toolchain; install Rust from https://rustup.rs and re-run"
    fi
  fi
  record necturalabs_fab "installed:$BIN_DIR/necturalabs-fab"
  say "necturalabs-fab: installed $BIN_DIR/necturalabs-fab"
}

# The plugin source is this checkout's root (its marketplace.json points at ./plugin) or the GitHub
# repository. Both harnesses read the same .claude-plugin/marketplace.json.
install_claude_plugin() {
  if ! have claude; then
    say "skill: Claude Code not found; skipped"
    return 0
  fi
  src=$(claude_marketplace_source)
  # A marketplace we added earlier points at the release installed then; move it to this one.
  if claude_has_marketplace && [ "$(recorded claude_marketplace)" = added ] \
      && [ "$(recorded claude_marketplace_source)" != "$src" ]; then
    claude plugin marketplace remove "$MARKETPLACE" >/dev/null 2>&1 \
      || die "could not re-point the Claude Code marketplace; run: claude plugin marketplace remove $MARKETPLACE"
  fi
  if claude_has_marketplace; then
    [ -n "$(recorded claude_marketplace)" ] || record claude_marketplace preexisting
    claude plugin marketplace update "$MARKETPLACE" >/dev/null 2>&1 || warn "could not refresh the Claude Code marketplace"
  else
    claude plugin marketplace add "$src" >/dev/null || die "could not add the Claude Code marketplace from $src"
    record claude_marketplace added
    record claude_marketplace_source "$src"
  fi
  if claude_has_plugin; then
    [ -n "$(recorded claude_plugin)" ] || record claude_plugin preexisting
    claude plugin update "$PLUGIN" >/dev/null 2>&1 || true
    say "skill: Claude Code plugin up to date"
  else
    claude plugin install "$PLUGIN" >/dev/null || die "could not install the Claude Code plugin $PLUGIN"
    record claude_plugin installed
    say "skill: installed for Claude Code"
  fi
}

install_codex_plugin() {
  if ! have codex; then
    say "skill: Codex not found; skipped"
    return 0
  fi
  if [ ! -d "$CODEX_DIR" ]; then
    mkdir -p "$CODEX_DIR"
    record codex_dir "created:$CODEX_DIR"
  fi
  if [ -n "$SOURCE" ]; then src=$SOURCE; else src="$REPO@$TAG"; fi
  if codex_has_marketplace && [ "$(recorded codex_marketplace)" = added ] \
      && [ "$(recorded codex_marketplace_source)" != "$src" ]; then
    codex plugin marketplace remove "$MARKETPLACE" >/dev/null 2>&1 \
      || die "could not re-point the Codex marketplace; run: codex plugin marketplace remove $MARKETPLACE"
  fi
  if codex_has_marketplace; then
    [ -n "$(recorded codex_marketplace)" ] || record codex_marketplace preexisting
    codex plugin marketplace upgrade "$MARKETPLACE" >/dev/null 2>&1 || warn "could not refresh the Codex marketplace"
  else
    out=$(codex plugin marketplace add "$src" 2>&1) || die "could not add the Codex marketplace from $src: $out"
    record codex_marketplace added
    record codex_marketplace_source "$src"
  fi
  if codex_has_plugin; then
    [ -n "$(recorded codex_plugin)" ] || record codex_plugin preexisting
  else
    record codex_plugin installed
  fi
  # `add` also refreshes an installed plugin to the marketplace's current version.
  out=$(codex plugin add "$PLUGIN" 2>&1) || die "could not install the Codex plugin $PLUGIN: $out"
  say "skill: installed for Codex"
}

offer_login() {
  nf="$BIN_DIR/necturalabs-fab"
  status=$("$nf" ${FABCLI_PATH:+--fabcli-path "$FABCLI_PATH"} --json auth status 2>/dev/null || true)
  case $status in
    *'"authenticated":true'*) say "Fab: already signed in"; return 0 ;;
  esac
  [ -n "${FABCLI_PATH:-}" ] || return 0
  if [ "$DO_LOGIN" = 1 ] && have_tty && confirm "Sign in to Fab now? Epic's sign-in page opens in your browser; paste the code it shows back here."; then
    # The code is pasted into this terminal.
    "$nf" --fabcli-path "$FABCLI_PATH" --human auth login --run < /dev/tty \
      || warn "sign-in did not complete; run 'necturalabs-fab auth login --run' later"
  else
    say "Sign in later with: necturalabs-fab auth login --run"
  fi
}

do_install() {
  detect_checkout
  WORK=$(mktemp -d)
  FABCLI_PATH=""
  resolve_tag
  say "Installing necturalabs-fab${TAG:+ $TAG} into $BIN_DIR"
  install_fabcli
  install_necturalabs_fab
  if [ "$DO_PLUGIN" = 1 ]; then
    install_claude_plugin
    install_codex_plugin
  fi
  offer_login

  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not on PATH; add it to your shell profile: export PATH=\"$BIN_DIR:\$PATH\"" ;;
  esac
  say ""
  "$BIN_DIR/necturalabs-fab" ${FABCLI_PATH:+--fabcli-path "$FABCLI_PATH"} --human doctor || true
  say ""
  if [ "${VIA_GH:-0}" = 1 ]; then
    say "Done. Uninstall with: gh api -H 'Accept: application/vnd.github.raw' repos/$REPO/contents/scripts/install.sh | sh -s -- --uninstall"
  else
    say "Done. Uninstall with: curl -fsSL https://raw.githubusercontent.com/$REPO/main/scripts/install.sh | sh -s -- --uninstall"
  fi
}

# --- uninstall ----------------------------------------------------------------------------

FAILED=0

# Report a step that could not be undone. Its manifest entry stays, so a re-run retries it.
failed() { warn "$*"; FAILED=1; }

remove_file() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    rm -f "$1" || { failed "could not remove $1"; return 1; }
    say "removed $1"
  fi
}

do_uninstall() {
  if [ ! -f "$MANIFEST" ]; then
    say "Nothing to uninstall: no install record at $MANIFEST"
    return 0
  fi

  if [ "$(recorded claude_plugin)" = installed ]; then
    if have claude && claude plugin uninstall "$PLUGIN" >/dev/null 2>&1; then
      say "removed the Claude Code plugin"; forget claude_plugin
    else
      failed "could not uninstall; run: claude plugin uninstall $PLUGIN"
    fi
  else
    forget claude_plugin
  fi
  if [ "$(recorded claude_marketplace)" = added ]; then
    if have claude && claude plugin marketplace remove "$MARKETPLACE" >/dev/null 2>&1; then
      say "removed the Claude Code marketplace entry"; forget claude_marketplace; forget claude_marketplace_source
    else
      failed "could not remove; run: claude plugin marketplace remove $MARKETPLACE"
    fi
  else
    forget claude_marketplace; forget claude_marketplace_source
  fi
  # Claude marks an uninstalled plugin's cache as orphaned and deletes it later; delete it now,
  # but only once the plugin is really gone.
  if have claude && ! claude_has_plugin && [ -d "$CLAUDE_DIR/plugins/cache/$MARKETPLACE" ]; then
    if rm -rf "$CLAUDE_DIR/plugins/cache/$MARKETPLACE"; then
      say "removed $CLAUDE_DIR/plugins/cache/$MARKETPLACE"
    else
      failed "could not remove $CLAUDE_DIR/plugins/cache/$MARKETPLACE"
    fi
  fi

  if [ "$(recorded codex_plugin)" = installed ]; then
    if have codex && codex plugin remove "$PLUGIN" >/dev/null 2>&1; then
      say "removed the Codex plugin"; forget codex_plugin
    else
      failed "could not uninstall; run: codex plugin remove $PLUGIN"
    fi
  else
    forget codex_plugin
  fi
  if [ "$(recorded codex_marketplace)" = added ]; then
    if have codex && codex plugin marketplace remove "$MARKETPLACE" >/dev/null 2>&1; then
      say "removed the Codex marketplace entry"; forget codex_marketplace; forget codex_marketplace_source
    else
      failed "could not remove; run: codex plugin marketplace remove $MARKETPLACE"
    fi
  else
    forget codex_marketplace; forget codex_marketplace_source
  fi
  # Codex leaves the plugin's (emptied) cache directory behind.
  if have codex && ! codex_has_plugin && [ -d "$CODEX_DIR/plugins/cache/$MARKETPLACE" ]; then
    if rm -rf "$CODEX_DIR/plugins/cache/$MARKETPLACE"; then
      say "removed $CODEX_DIR/plugins/cache/$MARKETPLACE"
    else
      failed "could not remove $CODEX_DIR/plugins/cache/$MARKETPLACE"
    fi
  fi
  codex_dir=$(recorded codex_dir)
  case $codex_dir in
    created:*) rmdir "${codex_dir#created:}" 2>/dev/null || true; forget codex_dir ;;
  esac

  fabcli=$(recorded fabcli)
  case $fabcli in
    installed:*)
      path=${fabcli#installed:}
      if [ "$(recorded fabcli_state)" = ours ]; then
        if [ -x "$path" ]; then
          # FabCLI's own logout deletes the token, its keyring entry, the sign-in browser data
          # and the library cache, and stops its background daemon.
          "$path" auth logout >/dev/null 2>&1 || true
          say "signed FabCLI out (token, keyring entry and browser data removed)"
        fi
        if [ -d "$CONFIG_HOME/fabcli" ]; then
          if rm -rf "$CONFIG_HOME/fabcli"; then say "removed $CONFIG_HOME/fabcli"; else failed "could not remove $CONFIG_HOME/fabcli"; fi
        fi
      else
        say "kept FabCLI's sign-in state in $CONFIG_HOME/fabcli (it predates necturalabs-fab)"
      fi
      remove_file "$path" && forget fabcli && forget fabcli_state
      ;;
    preexisting:*)
      say "kept FabCLI at ${fabcli#preexisting:} (it was installed before necturalabs-fab)"
      forget fabcli; forget fabcli_state
      ;;
    *) forget fabcli_state ;;
  esac

  nf=$(recorded necturalabs_fab)
  case $nf in installed:*) remove_file "${nf#installed:}" && forget necturalabs_fab ;; esac

  bin_dir=$(recorded bin_dir)
  case $bin_dir in
    created:*) rmdir "${bin_dir#created:}" 2>/dev/null && say "removed ${bin_dir#created:}"; forget bin_dir ;;
  esac

  if [ "$KEEP_CONFIG" = 0 ] && [ -d "$CONFIG_HOME/necturalabs-fab" ]; then
    if rm -rf "$CONFIG_HOME/necturalabs-fab"; then
      say "removed $CONFIG_HOME/necturalabs-fab"
    else
      failed "could not remove $CONFIG_HOME/necturalabs-fab"
    fi
  fi

  if [ -d "$CACHE_DIR" ]; then
    if rm -rf "$CACHE_DIR"; then say "removed $CACHE_DIR"; else failed "could not remove $CACHE_DIR"; fi
  fi

  if [ "$FAILED" = 1 ]; then
    warn "some steps failed; their record is kept in $MANIFEST, so running --uninstall again retries them"
    exit 1
  fi
  rm -rf "$DATA_DIR" && say "removed $DATA_DIR"

  say ""
  say "necturalabs-fab is uninstalled. Not touched: project .necturalabs-fab.toml files and assets you downloaded."
}

if [ "$ACTION" = uninstall ]; then do_uninstall; else do_install; fi
