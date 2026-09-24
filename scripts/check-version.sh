#!/bin/sh
# Fails unless package.json, the plugin manifest and the necturalabs-fab crate carry the same
# version and, given a tag, unless the tag is v<that version>. Every release bumps all three: the
# CLI follows the AgentSkills version, and Claude Code and Codex only refresh an installed plugin
# whose version changed.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
package=$(sed -n 's/^ *"version": *"\([^"]*\)".*$/\1/p' "$ROOT/package.json" | head -n 1)
plugin=$(sed -n 's/^ *"version": *"\([^"]*\)".*$/\1/p' "$ROOT/.claude-plugin/plugin.json" | head -n 1)
crate=$(sed -n 's/^version = "\(.*\)"$/\1/p' "$ROOT/cli/fab/Cargo.toml" | head -n 1)

if [ -z "$crate" ] || [ "$crate" != "$plugin" ] || [ "$crate" != "$package" ]; then
  printf 'version mismatch: package.json has %s, .claude-plugin/plugin.json has %s, cli/fab/Cargo.toml has %s\n' \
    "${package:-none}" "${plugin:-none}" "${crate:-none}" >&2
  exit 1
fi
if [ "$#" -gt 0 ] && [ "$1" != "v$crate" ]; then
  printf 'tag %s does not match version %s; bump every manifest before tagging\n' "$1" "$crate" >&2
  exit 1
fi
printf 'version %s\n' "$crate"
