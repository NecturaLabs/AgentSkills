#!/usr/bin/env bash
set -euo pipefail

V2_SKILLS=(agent-instructions change-review security-review testing project-docs)

usage() {
  cat <<'USAGE'
Usage: install.sh [--force] [--dry-run] [--prefix <dir>]

Links this checkout's v2 skills into the Claude Code and Codex skill roots.

  --force       Replace a skill link that points into a different AgentSkills
                checkout. Never replaces a real directory, and never replaces a
                link whose target lies outside an AgentSkills checkout.
  --dry-run     Print every action; change nothing.
  --prefix DIR  Use DIR instead of $HOME as the base holding .claude, .agents
                and .codex.
USAGE
}

die() { printf 'install: %s\n' "$*" >&2; exit 2; }

FORCE=0
DRY_RUN=0
PREFIX=${HOME:-}
PREFIX_GIVEN=0

while [ "$#" -gt 0 ]; do
  case $1 in
    --force) FORCE=1 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --prefix) [ "$#" -ge 2 ] || die "--prefix needs a directory"; PREFIX=$2; PREFIX_GIVEN=1; shift ;;
    --prefix=*) PREFIX=${1#--prefix=}; PREFIX_GIVEN=1 ;;
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
[ -d "$REPO_ROOT/skills" ] || die "no skills/ directory in $REPO_ROOT; not an AgentSkills checkout"

PLUGIN_MANIFEST=$REPO_ROOT/.claude-plugin/plugin.json

# First "name" key in a plugin manifest; the top-level name precedes author.name.
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

# Walks up from a resolved path to the checkout that owns it. Only a directory
# holding skills/ and a plugin manifest naming this same plugin counts, so a
# link into an unrelated tree can never be mistaken for ours.
checkout_root_of() {
  local d=$1 name
  [ -n "$PLUGIN_NAME" ] || return 1
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

CREATED=()
CORRECT=()
UPDATED=()
SKIPPED=()
FAILED=()

record() {
  case $1 in
    created) CREATED+=("$2") ;;
    correct) CORRECT+=("$2") ;;
    updated) UPDATED+=("$2") ;;
    skipped) SKIPPED+=("$2") ;;
    failed)  FAILED+=("$2") ;;
  esac
}

link_into_place() {
  local src=$1 dst=$2 root=$3 verb=$4
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$verb" = updated ]; then
      record updated "$dst -> $src (would replace existing AgentSkills link)"
    else
      record created "$dst -> $src (would create)"
    fi
    return 0
  fi
  mkdir -p -- "$root"
  if [ "$verb" = updated ]; then
    # Re-check immediately before the delete: only ever unlink a symlink.
    if [ ! -L "$dst" ]; then
      record failed "$dst (vanished or changed type before replacement; left alone)"
      return 1
    fi
    rm -- "$dst" || { record failed "$dst (could not be unlinked; left alone)"; return 1; }
  fi
  ln -s -- "$src" "$dst"
  record "$verb" "$dst -> $src"
}

install_one() {
  local root=$1 name=$2
  local src=$REPO_ROOT/skills/$name
  local dst=$root/$name
  local cur other

  if [ ! -d "$src" ]; then
    record failed "$dst (no source skill at $src)"
    return 1
  fi

  if [ -L "$dst" ]; then
    cur=$(readlink -f -- "$dst" 2>/dev/null || true)
    if [ -n "$cur" ] && [ "$cur" = "$src" ]; then
      record correct "$dst -> $src"
      return 0
    fi
    other=''
    if [ -n "$cur" ]; then
      other=$(checkout_root_of "$cur" || true)
    fi
    if [ -n "$other" ]; then
      if [ "$FORCE" -eq 1 ]; then
        link_into_place "$src" "$dst" "$root" updated
        return $?
      fi
      if [ "$other" = "$REPO_ROOT" ]; then
        record skipped "$dst (symlink to $cur in this checkout, but not to $src; rerun with --force to repoint)"
      else
        record skipped "$dst (symlink into another AgentSkills checkout: $cur; rerun with --force to repoint)"
      fi
      return 1
    fi
    if [ -z "$cur" ]; then
      # A dangling link has no target to protect, and it shadows the real skill for as long as it
      # survives -- which is what moving or renaming a checkout leaves behind. --force repairs it;
      # without --force say so, because nothing else in this script can.
      if [ "$FORCE" -eq 1 ]; then
        link_into_place "$src" "$dst" "$root" updated
        return $?
      fi
      record skipped "$dst (dangling symlink -> $(readlink -- "$dst" 2>/dev/null || printf '?'); rerun with --force to repair)"
      return 1
    fi
    record skipped "$dst (symlink to $cur, outside any AgentSkills checkout; never replaced)"
    return 1
  fi

  if [ -e "$dst" ]; then
    if [ -d "$dst" ]; then
      record skipped "$dst (a real directory, not a link; never replaced)"
    else
      record skipped "$dst (an existing file, not a link; never replaced)"
    fi
    return 1
  fi

  link_into_place "$src" "$dst" "$root" created
}

CLAUDE_ROOT=$PREFIX/.claude/skills
AGENTS_ROOT=$PREFIX/.agents/skills
# $CODEX_HOME relocates Codex's whole config root, skills included, but only the report-only
# CODEX_ROOT below follows it; AGENTS_ROOT is always $PREFIX/.agents/skills. Honoured only when
# --prefix was not given, so a sandboxed run stays inside its prefix; doctor.sh applies the same rule.
CODEX_HOME_DIR=$PREFIX/.codex
if [ "$PREFIX_GIVEN" -eq 0 ] && [ -n "${CODEX_HOME:-}" ]; then
  CODEX_HOME_DIR=$CODEX_HOME
fi
CODEX_ROOT=$CODEX_HOME_DIR/skills

claude_present=0
codex_present=0
[ -d "$PREFIX/.claude" ] && claude_present=1
command -v claude >/dev/null 2>&1 && claude_present=1
{ [ -d "$PREFIX/.codex" ] || [ -d "$PREFIX/.agents" ]; } && codex_present=1
command -v codex >/dev/null 2>&1 && codex_present=1

printf 'AgentSkills install\n'
printf '  checkout : %s\n' "$REPO_ROOT"
printf '  plugin   : %s\n' "${PLUGIN_NAME:-<unreadable manifest>}"
printf '  base     : %s\n' "$PREFIX"
[ "$DRY_RUN" -eq 1 ] && printf '  mode     : dry run (nothing will be changed)\n'
[ "$FORCE" -eq 1 ] && printf '  mode     : --force (may repoint links owned by another AgentSkills checkout)\n'
if [ "$FORCE" -eq 1 ] && [ -z "$PLUGIN_NAME" ]; then
  printf '  note     : plugin manifest unreadable, so no foreign link can be recognised; --force has no effect\n'
fi

if [ "$claude_present" -eq 1 ]; then
  printf '  found    : Claude Code -> %s\n' "$CLAUDE_ROOT"
else
  printf '  skipped  : Claude Code not found (no %s/.claude and no claude on PATH)\n' "$PREFIX"
fi
if [ "$codex_present" -eq 1 ]; then
  printf '  found    : Codex -> %s\n' "$AGENTS_ROOT"
else
  printf '  skipped  : Codex not found (no %s/.codex, no %s/.agents and no codex on PATH)\n' "$PREFIX" "$PREFIX"
fi
if [ -d "$CODEX_ROOT" ]; then
  printf '  detected : %s exists; only links already owned by an AgentSkills checkout are refreshed there\n' "$CODEX_ROOT"
fi
printf '\n'

status=0
for name in "${V2_SKILLS[@]}"; do
  if [ "$claude_present" -eq 1 ]; then
    install_one "$CLAUDE_ROOT" "$name" || status=1
  fi
  if [ "$codex_present" -eq 1 ]; then
    install_one "$AGENTS_ROOT" "$name" || status=1
  fi
  # Codex 0.155.1 scans both $CODEX_HOME/skills and $HOME/.agents/skills. .agents/skills is
  # HOME-derived (never relocated by $CODEX_HOME) and is the portable spec root, so it is the
  # install target above. $CODEX_HOME/skills is kept as a report-only compatibility root,
  # refreshed solely when it already carries one of our links and leaving it stale would shadow
  # the real install.
  if [ -L "$CODEX_ROOT/$name" ]; then
    cur=$(readlink -f -- "$CODEX_ROOT/$name" 2>/dev/null || true)
    if [ -n "$cur" ] && [ -n "$(checkout_root_of "$cur" || true)" ]; then
      install_one "$CODEX_ROOT" "$name" || status=1
    fi
  fi
done

print_group() {
  local label=$1
  shift
  [ "$#" -gt 0 ] || return 0
  printf '%s\n' "$label"
  printf '  %s\n' "$@"
}

printf 'Summary\n'
print_group "created:" ${CREATED[@]+"${CREATED[@]}"}
print_group "already correct:" ${CORRECT[@]+"${CORRECT[@]}"}
print_group "replaced:" ${UPDATED[@]+"${UPDATED[@]}"}
print_group "skipped:" ${SKIPPED[@]+"${SKIPPED[@]}"}
print_group "failed:" ${FAILED[@]+"${FAILED[@]}"}
if [ "${#CREATED[@]}" -eq 0 ] && [ "${#CORRECT[@]}" -eq 0 ] && [ "${#UPDATED[@]}" -eq 0 ] \
   && [ "${#SKIPPED[@]}" -eq 0 ] && [ "${#FAILED[@]}" -eq 0 ]; then
  printf '  nothing to do\n'
fi
printf '\n'

if [ -x "$SCRIPT_DIR/doctor.sh" ]; then
  printf 'Running doctor\n'
  "$SCRIPT_DIR/doctor.sh" --prefix "$PREFIX" || true
elif [ -f "$SCRIPT_DIR/doctor.sh" ]; then
  printf 'Running doctor\n'
  bash "$SCRIPT_DIR/doctor.sh" --prefix "$PREFIX" || true
fi

exit "$status"
