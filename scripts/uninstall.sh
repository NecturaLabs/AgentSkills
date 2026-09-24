#!/usr/bin/env bash
set -euo pipefail

SKILLS=(agent-instructions agent-orchestration independent-review testing project-docs fab)
# Skills earlier releases shipped. Uninstall still removes their links, so an upgrade never
# leaves one dangling.
RETIRED_SKILLS=(threat-review)

usage() {
  cat <<'USAGE'
Usage: uninstall.sh [--dry-run] [--prefix <dir>]

Removes only the skill symlinks this project created: a symlink in a skills
root whose name is one of this plugin's skills and whose target resolves
inside an AgentSkills checkout. Real directories, foreign links, unrelated
entries and the skills directories themselves are never touched.

  --dry-run     Print every action; change nothing.
  --prefix DIR  Use DIR instead of $HOME as the base holding .claude and
                .agents.
USAGE
}

die() { printf 'uninstall: %s\n' "$*" >&2; exit 2; }

DRY_RUN=0
PREFIX=${HOME:-}

while [ "$#" -gt 0 ]; do
  case $1 in
    --dry-run|-n) DRY_RUN=1 ;;
    --prefix) [ "$#" -ge 2 ] || die "--prefix needs a directory"; PREFIX=$2; shift ;;
    --prefix=*) PREFIX=${1#--prefix=} ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

[ -n "$PREFIX" ] || die "no HOME set; pass --prefix <dir>"
[ -d "$PREFIX" ] || die "prefix is not a directory: $PREFIX"
PREFIX=$(cd -- "$PREFIX" && pwd -P)

SCRIPT_DIR=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)
REPO_ROOT=${SCRIPT_DIR%/*}
PLUGIN_MANIFEST=$REPO_ROOT/.claude-plugin/plugin.json

plugin_name_in() {
  local line rest
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      *'"name"'*)
        rest=${line#*'"name"'}
        rest=${rest#*:}
        case $rest in
          *'"'*) ;;
          *) continue ;;
        esac
        rest=${rest#*'"'}
        printf '%s' "${rest%%'"'*}"
        return 0
        ;;
    esac
  done < "$1"
  return 1
}

PLUGIN_NAME=''
if [ -f "$PLUGIN_MANIFEST" ]; then
  PLUGIN_NAME=$(plugin_name_in "$PLUGIN_MANIFEST" || true)
fi
# Without a manifest nothing can be recognised as ours, and an unrecognised
# link is never removed, so refuse rather than appear to have uninstalled.
[ -n "$PLUGIN_NAME" ] || die "cannot read plugin name from $PLUGIN_MANIFEST; refusing to remove anything"

checkout_root_of() {
  local d=$1 name
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -d "$d/skills" ] && [ -f "$d/.claude-plugin/plugin.json" ]; then
      name=$(plugin_name_in "$d/.claude-plugin/plugin.json" || true)
      if [ "$name" = "$PLUGIN_NAME" ]; then
        printf '%s' "$d"
        return 0
      fi
    fi
    d=${d%/*}
  done
  return 1
}

MANAGED=("${SKILLS[@]}" "${RETIRED_SKILLS[@]}")

is_managed_name() {
  local candidate=$1 n
  for n in "${MANAGED[@]}"; do
    [ "$n" = "$candidate" ] && return 0
  done
  return 1
}

REMOVED=()
KEPT=()

ROOTS=("$PREFIX/.claude/skills" "$PREFIX/.agents/skills")

status=0
shopt -s nullglob dotglob

for root in "${ROOTS[@]}"; do
  if [ ! -d "$root" ]; then
    printf 'skills root absent, nothing to do: %s\n' "$root"
    continue
  fi
  printf 'scanning %s\n' "$root"
  for entry in "$root"/*; do
    name=${entry##*/}
    if [ ! -L "$entry" ]; then
      if [ -d "$entry" ]; then
        KEPT+=("$entry (a real directory, never removed)")
      else
        KEPT+=("$entry (not a symlink, never removed)")
      fi
      continue
    fi
    if ! is_managed_name "$name"; then
      KEPT+=("$entry (not a skill of this plugin)")
      continue
    fi
    target=$(readlink -f -- "$entry" 2>/dev/null || true)
    owner=''
    if [ -n "$target" ]; then
      owner=$(checkout_root_of "$target" || true)
    fi
    if [ -z "$owner" ]; then
      KEPT+=("$entry (target ${target:-unresolvable} is outside any AgentSkills checkout)")
      continue
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      REMOVED+=("$entry -> $target (would remove)")
      continue
    fi
    # Re-check the type at the last possible moment; rm only ever unlinks a
    # symlink, so a directory swapped in underneath us survives.
    if [ ! -L "$entry" ]; then
      KEPT+=("$entry (changed type during the run; left alone)")
      status=1
      continue
    fi
    rm -- "$entry" || { KEPT+=("$entry (could not be unlinked; left alone)"); status=1; continue; }
    REMOVED+=("$entry -> $target")
  done
done

shopt -u nullglob dotglob

print_group() {
  local label=$1
  shift
  [ "$#" -gt 0 ] || return 0
  printf '%s\n' "$label"
  printf '  %s\n' "$@"
}

printf '\nSummary\n'
print_group "removed:" ${REMOVED[@]+"${REMOVED[@]}"}
print_group "left alone:" ${KEPT[@]+"${KEPT[@]}"}
if [ "${#REMOVED[@]}" -eq 0 ]; then
  printf 'removed: nothing\n'
fi

exit "$status"
