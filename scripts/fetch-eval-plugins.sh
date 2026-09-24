#!/usr/bin/env bash
# Fetches the third-party plugins the routing evals load, at the revisions the marketplace pins,
# into evals/<case>/.plugins/<name> for every case whose prompt.md lists that path (the eval runner
# only loads a case-shipped plugin from inside its case). They are fetched from upstream, never
# committed: evals/*/.plugins/ is ignored. Needs git and the network; run it before
# `claude plugin eval .`.
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# name, upstream repository, pinned commit, skill directory inside it
PLUGINS=(
  "security-audit https://github.com/cloudflare/security-audit-skill.git c1c8a8c1471069fb0e188eeaff69b8e8db6564a8 skills/security-audit"
)

for entry in "${PLUGINS[@]}"; do
  read -r name url sha skill <<<"$entry"
  work=$(mktemp -d)
  git -C "$work" init -q
  git -C "$work" fetch -q --depth 1 "$url" "$sha"
  git -C "$work" checkout -q FETCH_HEAD
  for prompt in "$REPO_ROOT"/evals/*/prompt.md; do
    grep -q "^plugins:.*\"\.plugins/$name\"" "$prompt" || continue
    dest=${prompt%/prompt.md}/.plugins/$name
    rm -rf "$dest"
    mkdir -p "$dest/skills" "$dest/.claude-plugin"
    cp -R "$work/$skill" "$dest/skills/"
    printf '{"name": "%s", "version": "0.0.0+%s"}\n' "$name" "${sha:0:7}" > "$dest/.claude-plugin/plugin.json"
    printf 'fetched %s at %s into %s\n' "$name" "${sha:0:7}" "${dest#"$REPO_ROOT"/}"
  done
  rm -rf "$work"
done
