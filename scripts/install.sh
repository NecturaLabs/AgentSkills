#!/usr/bin/env bash
set -euo pipefail

V2_SKILLS=(agent-instructions change-review security-review testing project-docs)

usage() {
  cat <<'USAGE'
Usage: install.sh [--force] [--dry-run] [--prefix <dir>]
                  [--global-agents [<file>]] [--replace-global]

Links this checkout's v2 skills into the Claude Code and Codex skill roots.
Installing skills and installing a global operating policy are separate
operations: without --global-agents this script touches no instruction file.

  --force       Replace a skill link that points into a different AgentSkills
                checkout. Never replaces a real directory, and never replaces a
                link whose target lies outside an AgentSkills checkout.
  --dry-run     Print every action; change nothing.
  --prefix DIR  Use DIR instead of $HOME as the base holding .claude, .agents
                and .codex.

  --global-agents [FILE]
                Additionally bootstrap the canonical global instruction file at
                <prefix>/.claude/AGENTS.md from FILE, defaulting to this
                checkout's examples/global-agents.md. Also writes the Claude
                adapter <prefix>/.claude/CLAUDE.md containing only '@AGENTS.md',
                and points Codex at the same canonical file by symlinking
                <codex home>/AGENTS.md to it, so there is never a second
                independently maintained copy. Anything already present that
                would conflict is left untouched and reported.
  --replace-global
                Only with --global-agents. Replace a conflicting file after
                backing it up alongside itself. Never used implicitly.
USAGE
}

die() { printf 'install: %s\n' "$*" >&2; exit 2; }

FORCE=0
DRY_RUN=0
PREFIX=${HOME:-}
PREFIX_GIVEN=0
GLOBAL_AGENTS=0
REPLACE_GLOBAL=0
GLOBAL_SRC=''

while [ "$#" -gt 0 ]; do
  case $1 in
    --force) FORCE=1 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --prefix) [ "$#" -ge 2 ] || die "--prefix needs a directory"; PREFIX=$2; PREFIX_GIVEN=1; shift ;;
    --prefix=*) PREFIX=${1#--prefix=}; PREFIX_GIVEN=1 ;;
    --global-agents)
      GLOBAL_AGENTS=1
      # The optional value must not swallow the next flag.
      case ${2:-} in
        ''|-*) ;;
        *) GLOBAL_SRC=$2; shift ;;
      esac
      ;;
    --global-agents=*) GLOBAL_AGENTS=1; GLOBAL_SRC=${1#--global-agents=} ;;
    --replace-global) REPLACE_GLOBAL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

if [ "$REPLACE_GLOBAL" -eq 1 ] && [ "$GLOBAL_AGENTS" -eq 0 ]; then
  die "--replace-global only means something with --global-agents"
fi

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

# --- global policy bootstrap -------------------------------------------------
# Runs only under --global-agents. Installing skills and installing an operating policy are
# different operations, and the second one overwrites how every future session behaves, so it is
# never implied by the first. The layout it produces keeps exactly one canonical file:
#
#   <prefix>/.claude/AGENTS.md   the policy itself, a regular file the user owns and edits
#   <prefix>/.claude/CLAUDE.md   '@AGENTS.md' -- the adapter Claude Code needs, because its
#                                AGENTS.md discovery walks the working directory's ancestors and
#                                so never reaches the home directory
#   <codex home>/AGENTS.md       a symlink to the canonical file, so Codex reads the same bytes
#                                rather than a second copy that drifts
#
# The canonical file is a copy of the source, never a link into this checkout: a link would make
# `git pull` silently rewrite the user's own policy.
GLOBAL_ACTIONS=()
g_note() { GLOBAL_ACTIONS+=("$1"); }

timestamp_utc() { date -u +%Y%m%dT%H%M%SZ; }

# A shim carries exactly one substantive line, and that line is the @AGENTS.md import. Blank
# lines and comments are still a shim. A second import is not: `@AGENTS.md` plus `@OTHER.md`
# pulls in policy this bootstrap does not control, so it is a conflict, not a shim to leave alone.
is_import_only_shim() {
  local substantive
  [ -f "$1" ] || return 1
  substantive=$(grep -vE '^[[:space:]]*(#.*)?$' "$1" 2>/dev/null || true)
  [ "$(printf '%s\n' "$substantive" | grep -c .)" -eq 1 ] || return 1
  printf '%s\n' "$substantive" | grep -qE '^[[:space:]]*@AGENTS\.md[[:space:]]*$'
}

# Moves an existing file aside. Never overwrites a backup, and never touches the original on
# failure, so a conflicting name aborts that one action instead of destroying anything.
backup_path_for() {
  local target=$1 stamp candidate
  stamp=$(timestamp_utc)
  candidate=$target.backup-$stamp
  if [ -e "$candidate" ] || [ -L "$candidate" ]; then
    return 1
  fi
  printf '%s' "$candidate"
}

# Each destination is classified before anything is written: "create" (nothing there), "ok"
# (already exactly what we would write) or "conflict" with a reason. A --global-agents run is
# all-or-nothing with respect to conflicts, because the three destinations are one mechanism:
# writing the adapters while refusing the canonical file would point both harnesses at a policy
# this run explicitly declined to install.
classify_canonical() {
  local src=$1 dst=$2
  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then printf 'create'; return 0; fi
  if [ -f "$dst" ] && cmp -s -- "$src" "$dst"; then printf 'ok'; return 0; fi
  printf 'conflict|%s already exists and differs from %s' "$dst" "$src"
}

classify_claude_adapter() {
  local dst=$1
  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then printf 'create'; return 0; fi
  if is_import_only_shim "$dst"; then printf 'ok'; return 0; fi
  printf 'conflict|%s carries its own content, not just the import' "$dst"
}

classify_codex_adapter() {
  local dst=$1 canonical=$2 cur
  if [ -L "$dst" ]; then
    cur=$(readlink -f -- "$dst" 2>/dev/null || true)
    if [ -n "$cur" ] && [ "$cur" = "$canonical" ]; then printf 'ok'; return 0; fi
    printf 'conflict|%s is a symlink that does not point at %s' "$dst" "$canonical"
    return 0
  fi
  if [ ! -e "$dst" ]; then printf 'create'; return 0; fi
  printf 'conflict|%s already exists and is not a link to %s' "$dst" "$canonical"
}

# Moves a conflicting entry aside. Only ever called under --replace-global.
move_aside() {
  local dst=$1 backup
  backup=$(backup_path_for "$dst") || {
    g_note "$dst not replaced: a backup from this second already exists; left untouched"
    return 1
  }
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s' "$backup"
    return 0
  fi
  mv -- "$dst" "$backup" || { g_note "FAILED to back up $dst; left untouched"; return 1; }
  printf '%s' "$backup"
}

apply_canonical() {
  local src=$1 dst=$2 action=$3 backup=''
  if [ "$action" = replace ]; then
    backup=$(move_aside "$dst") || return 1
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -n "$backup" ]; then g_note "would back up $dst to $backup, then write it from $src"
    else g_note "would create $dst from $src"; fi
    return 0
  fi
  mkdir -p -- "${dst%/*}"
  cp -- "$src" "$dst" || { g_note "FAILED to write $dst${backup:+ (previous contents are at $backup)}"; return 1; }
  if [ -n "$backup" ]; then g_note "backed up $dst to $backup and wrote it from $src"
  else g_note "created $dst from $src"; fi
}

apply_claude_adapter() {
  local dst=$1 action=$2 backup=''
  if [ "$action" = replace ]; then
    backup=$(move_aside "$dst") || return 1
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -n "$backup" ]; then g_note "would back up $dst to $backup, then replace it with '@AGENTS.md'"
    else g_note "would create $dst containing '@AGENTS.md'"; fi
    return 0
  fi
  mkdir -p -- "${dst%/*}"
  printf '@AGENTS.md\n' > "$dst" || { g_note "FAILED to write $dst${backup:+ (previous contents are at $backup)}"; return 1; }
  if [ -n "$backup" ]; then g_note "backed up $dst to $backup and replaced it with '@AGENTS.md'"
  else g_note "created $dst containing '@AGENTS.md'"; fi
}

apply_codex_adapter() {
  local dst=$1 canonical=$2 action=$3 backup=''
  if [ "$action" = replace ]; then
    backup=$(move_aside "$dst") || return 1
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -n "$backup" ]; then g_note "would back up $dst to $backup, then link it -> $canonical"
    else g_note "would link $dst -> $canonical"; fi
    return 0
  fi
  mkdir -p -- "${dst%/*}"
  ln -s -- "$canonical" "$dst" || { g_note "FAILED to link $dst${backup:+ (previous entry is at $backup)}"; return 1; }
  if [ -n "$backup" ]; then g_note "backed up $dst to $backup and linked it -> $canonical"
  else g_note "linked $dst -> $canonical"; fi
}

bootstrap_global_agents() {
  local src=$GLOBAL_SRC
  local canonical=$PREFIX/.claude/AGENTS.md
  local claude_adapter=$PREFIX/.claude/CLAUDE.md
  local codex_adapter=$CODEX_HOME_DIR/AGENTS.md
  local rc=0 c_can c_cla c_cod conflicts=()

  [ -n "$src" ] || src=$REPO_ROOT/examples/global-agents.md
  case $src in
    /*) ;;
    *) src=$PWD/$src ;;
  esac
  [ -f "$src" ] || die "global agents source is not a readable file: $src"
  [ -s "$src" ] || die "global agents source is empty: $src"
  src=$(cd -- "${src%/*}" && printf '%s/%s' "$(pwd -P)" "${src##*/}")

  printf 'Global policy\n'
  printf '  source    : %s\n' "$src"
  printf '  canonical : %s\n' "$canonical"
  [ "$REPLACE_GLOBAL" -eq 1 ] && printf '  mode      : --replace-global (conflicts are backed up, then replaced)\n'
  [ "$DRY_RUN" -eq 1 ] && printf '  mode      : dry run (nothing will be changed)\n'

  c_can=$(classify_canonical "$src" "$canonical")
  c_cla=$(classify_claude_adapter "$claude_adapter")
  c_cod=$(classify_codex_adapter "$codex_adapter" "$canonical")

  local entry
  for entry in "$c_can" "$c_cla" "$c_cod"; do
    case $entry in conflict\|*) conflicts+=("${entry#conflict|}") ;; esac
  done

  if [ "${#conflicts[@]}" -gt 0 ] && [ "$REPLACE_GLOBAL" -eq 0 ]; then
    for entry in "${conflicts[@]}"; do
      g_note "$entry"
    done
    g_note "nothing was written: a --global-agents run is all-or-nothing, so one conflict leaves every destination untouched (rerun with --replace-global to replace the conflicting entries, which backs each one up first)"
    printf '%s\n' "${GLOBAL_ACTIONS[@]/#/  }"
    printf '\n'
    return 1
  fi

  # Codex prefers an override file, so it would shadow the canonical policy. Reported, never removed.
  if [ -e "${codex_adapter%/*}/AGENTS.override.md" ]; then
    g_note "${codex_adapter%/*}/AGENTS.override.md takes precedence over $codex_adapter for Codex; left untouched, but it shadows the canonical policy"
  fi

  case $c_can in
    create) apply_canonical "$src" "$canonical" create || rc=1 ;;
    ok) g_note "$canonical already matches $src; left alone" ;;
    conflict\|*) apply_canonical "$src" "$canonical" replace || rc=1 ;;
  esac
  case $c_cla in
    create) apply_claude_adapter "$claude_adapter" create || rc=1 ;;
    ok) g_note "$claude_adapter is already an import-only shim; left alone" ;;
    conflict\|*) apply_claude_adapter "$claude_adapter" replace || rc=1 ;;
  esac
  case $c_cod in
    create) apply_codex_adapter "$codex_adapter" "$canonical" create || rc=1 ;;
    ok) g_note "$codex_adapter already points at $canonical; left alone" ;;
    conflict\|*) apply_codex_adapter "$codex_adapter" "$canonical" replace || rc=1 ;;
  esac

  printf '%s\n' "${GLOBAL_ACTIONS[@]/#/  }"
  printf '\n'
  return "$rc"
}

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

if [ "$GLOBAL_AGENTS" -eq 1 ]; then
  bootstrap_global_agents || status=1
else
  printf 'Global policy\n'
  printf '  not requested; no instruction file was read or written (pass --global-agents to bootstrap one)\n\n'
fi

if [ -x "$SCRIPT_DIR/doctor.sh" ]; then
  printf 'Running doctor\n'
  "$SCRIPT_DIR/doctor.sh" --prefix "$PREFIX" || true
elif [ -f "$SCRIPT_DIR/doctor.sh" ]; then
  printf 'Running doctor\n'
  bash "$SCRIPT_DIR/doctor.sh" --prefix "$PREFIX" || true
fi

exit "$status"
