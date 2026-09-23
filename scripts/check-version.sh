#!/bin/sh
# Fails unless Cargo.toml and the plugin manifest carry the same version and, given a tag, unless
# the tag is v<that version>. Every release bumps both: Claude Code and Codex only refresh an
# installed plugin whose version changed.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
crate=$(sed -n 's/^version = "\(.*\)"$/\1/p' "$ROOT/Cargo.toml" | head -n 1)
plugin=$(sed -n 's/^ *"version": *"\([^"]*\)".*$/\1/p' "$ROOT/plugin/.claude-plugin/plugin.json" | head -n 1)

if [ -z "$crate" ] || [ "$crate" != "$plugin" ]; then
  printf 'version mismatch: Cargo.toml has %s, plugin/.claude-plugin/plugin.json has %s\n' \
    "${crate:-none}" "${plugin:-none}" >&2
  exit 1
fi
if [ "$#" -gt 0 ] && [ "$1" != "v$crate" ]; then
  printf 'tag %s does not match version %s; bump both files before tagging\n' "$1" "$crate" >&2
  exit 1
fi
printf 'version %s\n' "$crate"
