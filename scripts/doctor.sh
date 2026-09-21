#!/usr/bin/env bash
set -euo pipefail

V2_SKILLS=(agent-instructions change-review security-review testing project-docs)

V1_SKILLS=(using-necturalabs agent-context-loader iterative-code-review \
           iterative-security-audit test-manager unit-test-manager \
           integration-test-manager e2e-test-manager agents-md-manager \
           docs-manager git-workflow comment-manager update-plugins)

DEFAULT_DOC_BUDGET=32768

usage() {
  cat <<'USAGE'
Usage: doctor.sh [--prefix <dir>]

Reports on this checkout, the installed skill links and AGENTS.md health.
Changes nothing. Exits 0 when healthy, 1 when a problem was found.

  --prefix DIR  Use DIR instead of $HOME as the base holding .claude, .agents
                and .codex.
USAGE
}

die() { printf 'doctor: %s\n' "$*" >&2; exit 2; }

PREFIX=${HOME:-}
PREFIX_GIVEN=0

while [ "$#" -gt 0 ]; do
  case $1 in
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
PLUGIN_MANIFEST=$REPO_ROOT/.claude-plugin/plugin.json

ERRORS=0
WARNINGS=0
ok()   { printf '  [ok]    %s\n' "$*"; }
info() { printf '  [info]  %s\n' "$*"; }
warn() { WARNINGS=$((WARNINGS + 1)); printf '  [warn]  %s\n' "$*"; }
err()  { ERRORS=$((ERRORS + 1));  printf '  [error] %s\n' "$*"; }

json_string_value() {
  local file=$1 key=$2 line rest
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      *"\"$key\""*)
        rest=${line#*"\"$key\""}
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
  done < "$file"
  return 1
}

PLUGIN_NAME=''
PLUGIN_VERSION=''
if [ -f "$PLUGIN_MANIFEST" ]; then
  PLUGIN_NAME=$(json_string_value "$PLUGIN_MANIFEST" name || true)
  PLUGIN_VERSION=$(json_string_value "$PLUGIN_MANIFEST" version || true)
fi

checkout_root_of() {
  local d=$1 name
  [ -n "$PLUGIN_NAME" ] || return 1
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -d "$d/skills" ] && [ -f "$d/.claude-plugin/plugin.json" ]; then
      name=$(json_string_value "$d/.claude-plugin/plugin.json" name || true)
      if [ "$name" = "$PLUGIN_NAME" ]; then
        printf '%s' "$d"
        return 0
      fi
    fi
    d=${d%/*}
  done
  return 1
}

CLAUDE_HOME=$PREFIX/.claude
AGENTS_HOME=$PREFIX/.agents
CODEX_HOME_DIR=$PREFIX/.codex
if [ "$PREFIX_GIVEN" -eq 0 ] && [ -n "${CODEX_HOME:-}" ]; then
  CODEX_HOME_DIR=$CODEX_HOME
fi
CLAUDE_ROOT=$CLAUDE_HOME/skills
AGENTS_ROOT=$AGENTS_HOME/skills
CODEX_ROOT=$CODEX_HOME_DIR/skills

printf 'Checkout\n'
info "path: $REPO_ROOT"
if [ -d "$REPO_ROOT/skills" ]; then
  ok "skills/ present"
else
  err "no skills/ directory in $REPO_ROOT"
fi
if [ -f "$PLUGIN_MANIFEST" ]; then
  info "plugin: ${PLUGIN_NAME:-<no name>} ${PLUGIN_VERSION:-<no version>}"
else
  err "missing plugin manifest: $PLUGIN_MANIFEST"
fi
if command -v git >/dev/null 2>&1 && [ -e "$REPO_ROOT/.git" ]; then
  commit=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || true)
  info "git commit: ${commit:-<none>}"
  dirty=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null || true)
  if [ -n "$dirty" ]; then
    info "git tree: dirty ($(printf '%s\n' "$dirty" | wc -l) changed paths)"
  else
    info "git tree: clean"
  fi
else
  info "git: not a git checkout or git unavailable"
fi
printf '\n'

printf 'Harnesses\n'
report_cli() {
  local name=$1 version
  if command -v "$name" >/dev/null 2>&1; then
    if command -v timeout >/dev/null 2>&1; then
      version=$(timeout 20 "$name" --version 2>/dev/null | head -n 1 || true)
    else
      version=$("$name" --version 2>/dev/null | head -n 1 || true)
    fi
    info "$name on PATH: $(command -v "$name") (${version:-version unavailable})"
  else
    info "$name not on PATH"
  fi
}
report_cli claude
report_cli codex
printf '\n'

claude_active=0
codex_active=0
[ -d "$CLAUDE_HOME" ] && claude_active=1
command -v claude >/dev/null 2>&1 && claude_active=1
{ [ -d "$CODEX_HOME_DIR" ] || [ -d "$AGENTS_HOME" ]; } && codex_active=1
command -v codex >/dev/null 2>&1 && codex_active=1

entry_state() {
  # Prints "<state>\t<target>" for a skill path.
  local path=$1 target owner
  if [ -L "$path" ]; then
    target=$(readlink -f -- "$path" 2>/dev/null || true)
    if [ -n "$target" ] && [ "$target" = "$REPO_ROOT/skills/${path##*/}" ]; then
      printf 'correct\t%s' "$target"
    elif [ -z "$target" ] || [ ! -e "$path" ]; then
      printf 'broken\t%s' "${target:-unresolvable}"
    else
      owner=$(checkout_root_of "$target" || true)
      if [ -n "$owner" ]; then
        printf 'other-checkout\t%s' "$target"
      else
        printf 'foreign\t%s' "$target"
      fi
    fi
  elif [ -d "$path" ]; then
    printf 'realdir\t%s' "$path"
  elif [ -e "$path" ]; then
    printf 'realfile\t%s' "$path"
  else
    printf 'missing\t'
  fi
}

check_root() {
  local root=$1 label=$2 required=$3 name state target line
  printf '%s (%s)\n' "$label" "$root"
  if [ ! -d "$root" ]; then
    if [ "$required" -eq 1 ]; then
      err "skills root does not exist"
    else
      info "skills root does not exist"
    fi
    printf '\n'
    return 0
  fi
  for name in "${V2_SKILLS[@]}"; do
    line=$(entry_state "$root/$name")
    state=${line%%$'\t'*}
    target=${line#*$'\t'}
    case $state in
      correct) ok "$name -> $target" ;;
      broken)
        if [ "$required" -eq 1 ]; then err "$name is a broken symlink -> $target"
        else warn "$name is a broken symlink -> $target"; fi ;;
      other-checkout)
        if [ "$required" -eq 1 ]; then err "$name points at a different AgentSkills checkout -> $target"
        else warn "$name points at a different AgentSkills checkout -> $target"; fi ;;
      foreign)
        if [ "$required" -eq 1 ]; then err "$name points outside any AgentSkills checkout -> $target"
        else warn "$name points outside any AgentSkills checkout -> $target"; fi ;;
      realdir)
        if [ "$required" -eq 1 ]; then err "$name is shadowed by a real directory"
        else warn "$name is a real directory, not a link"; fi ;;
      realfile)
        if [ "$required" -eq 1 ]; then err "$name exists as a plain file"
        else warn "$name exists as a plain file"; fi ;;
      missing)
        if [ "$required" -eq 1 ]; then err "$name is not installed"
        else info "$name is not installed here (this root is report-only)"; fi ;;
    esac
  done
  printf '\n'
}

printf 'Installed skills\n'
if [ "$claude_active" -eq 1 ]; then
  check_root "$CLAUDE_ROOT" "Claude Code" 1
else
  printf 'Claude Code (%s)\n' "$CLAUDE_ROOT"
  info "harness not present; skipped"
  printf '\n'
fi
if [ "$codex_active" -eq 1 ]; then
  check_root "$AGENTS_ROOT" "Codex (user scope)" 1
else
  printf 'Codex (user scope) (%s)\n' "$AGENTS_ROOT"
  info "harness not present; skipped"
  printf '\n'
fi
# Codex 0.155.1 scans both $CODEX_HOME/skills and $HOME/.agents/skills; .agents/skills is
# HOME-derived and is the required install root checked above. $CODEX_HOME/skills is kept as a
# report-only compatibility/older root: still checked, but never required.
check_root "$CODEX_ROOT" "Codex (compatibility root, \$CODEX_HOME)" 0

printf 'v1 artifacts\n'
legacy_found=0
for root in "$CLAUDE_ROOT" "$AGENTS_ROOT" "$CODEX_ROOT"; do
  [ -d "$root" ] || continue
  for name in "${V1_SKILLS[@]}"; do
    path=$root/$name
    [ -e "$path" ] || [ -L "$path" ] || continue
    legacy_found=1
    if [ -L "$path" ]; then
      target=$(readlink -f -- "$path" 2>/dev/null || true)
      owner=''
      [ -n "$target" ] && owner=$(checkout_root_of "$target" || true)
      if [ -n "$owner" ]; then
        err "$path -> $target (v1 link from an AgentSkills checkout; remove with uninstall.sh --include-legacy)"
      else
        warn "$path -> ${target:-unresolvable} (v1 skill name, not owned by this plugin)"
      fi
    else
      warn "$path (v1 skill name as a real directory, not owned by this plugin)"
    fi
  done
done
[ "$legacy_found" -eq 0 ] && ok "none installed"
printf '\n'

printf 'Shadowing\n'
shadow_found=0
for name in "${V2_SKILLS[@]}"; do
  seen=''
  distinct=0
  where=''
  for root in "$CLAUDE_ROOT" "$AGENTS_ROOT" "$CODEX_ROOT"; do
    path=$root/$name
    [ -e "$path" ] || [ -L "$path" ] || continue
    target=$(readlink -f -- "$path" 2>/dev/null || true)
    [ -n "$target" ] || target='<unresolvable>'
    where="$where $root"
    case " $seen " in
      *" $target "*) ;;
      *) seen="$seen $target"; distinct=$((distinct + 1)) ;;
    esac
  done
  if [ "$distinct" -gt 1 ]; then
    shadow_found=1
    err "$name resolves to different targets across roots:$seen (seen in$where)"
  fi
done
[ "$shadow_found" -eq 0 ] && ok "no skill name resolves to conflicting targets across roots"
printf '\n'

printf 'AGENTS.md health\n'

# Claude Code reaches a user-scope AGENTS.md through no native path: its discovery walks the
# ancestors of the working directory, which never reaches ~/.claude for a project stored elsewhere.
# So ~/.claude/CLAUDE.md holding exactly the import is correct here, and its absence is the fault.
# "Policy" is anything beyond the import, a comment or blank space.
# The canonical global policy. install.sh --global-agents puts a regular file here and points both
# harnesses at it; doctor only reports what it finds and never changes any of it.
canonical_policy=$CLAUDE_HOME/AGENTS.md
if [ -f "$canonical_policy" ]; then
  ok "canonical global policy: $canonical_policy ($(wc -c < "$canonical_policy") bytes)"
elif [ -e "$canonical_policy" ] || [ -L "$canonical_policy" ]; then
  warn "$canonical_policy exists but is not a regular file"
else
  info "no $canonical_policy; no canonical global policy installed (bootstrap one with install.sh --global-agents)"
fi

global_shim=$CLAUDE_HOME/CLAUDE.md
if [ ! -e "$global_shim" ]; then
  if [ -e "$CLAUDE_HOME/AGENTS.md" ]; then
    err "$CLAUDE_HOME/AGENTS.md exists but $global_shim does not; Claude Code loads no global instructions (it does not read a user-scope AGENTS.md natively)"
  else
    info "$global_shim absent and no $CLAUDE_HOME/AGENTS.md; no global instructions configured"
  fi
else
  # Exactly one substantive line, and it is the @AGENTS.md import. A second import such as
  # @OTHER.md pulls in policy outside the canonical file, so it is not an import-only shim.
  shim_body=$(grep -vE '^[[:space:]]*(#.*)?$' "$global_shim" 2>/dev/null || true)
  substantive=$(printf '%s\n' "$shim_body" | grep -c . || true)
  substantive=${substantive:-0}
  if [ "$substantive" -eq 1 ] && printf '%s\n' "$shim_body" | grep -qE '^[[:space:]]*@AGENTS\.md[[:space:]]*$'; then
    ok "$global_shim is an import-only shim (no policy of its own)"
  else
    warn "$global_shim carries $substantive substantive line(s); it should hold only '@AGENTS.md' so AGENTS.md stays the single maintained source"
  fi
fi
if [ -e "$CLAUDE_HOME/CLAUDE.local.md" ]; then
  warn "$CLAUDE_HOME/CLAUDE.local.md exists; it competes with AGENTS.md for the global instruction slot"
else
  ok "$CLAUDE_HOME/CLAUDE.local.md absent"
fi

# Native project AGENTS.md support arrived in 2.1.277 and is additionally gated by a remote feature
# flag that defaults off in the binary, so a version check is necessary but not sufficient.
if command -v claude >/dev/null 2>&1; then
  claude_ver=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
  if [ -n "$claude_ver" ]; then
    oldest=$(printf '%s\n2.1.277\n' "$claude_ver" | sort -V | head -1)
    if [ "$oldest" = "2.1.277" ]; then
      info "Claude Code $claude_ver supports native project AGENTS.md (2.1.277+), subject to a remote feature flag that can be off for an account"
    else
      warn "Claude Code $claude_ver predates native project AGENTS.md support (2.1.277+); project instructions need a CLAUDE.md on this version"
    fi
  fi
fi
project_claude=0
for f in "$REPO_ROOT/CLAUDE.md" "$REPO_ROOT/.claude/CLAUDE.md" "$REPO_ROOT/CLAUDE.local.md"; do
  if [ -e "$f" ]; then
    project_claude=1
    warn "$f exists; Claude Code reads it instead of a project AGENTS.md under the default instructionFiles setting"
  fi
done
[ "$project_claude" -eq 0 ] && ok "no project-level CLAUDE.md in this checkout"

settings=$CLAUDE_HOME/settings.json
if [ -f "$settings" ]; then
  instruction_files=''
  if command -v jq >/dev/null 2>&1; then
    instruction_files=$(jq -r '.pluginConfigs["agents-md@builtin"].options.instructionFiles // empty' "$settings" 2>/dev/null || true)
  fi
  if [ -z "$instruction_files" ]; then
    instruction_files=$(json_string_value "$settings" instructionFiles || true)
  fi
  if [ -n "$instruction_files" ]; then
    info "pluginConfigs[\"agents-md@builtin\"].options.instructionFiles = $instruction_files"
  else
    info "instructionFiles not set in $settings (default: claude-md-or-agents-md)"
  fi
else
  info "no $settings (instructionFiles default: claude-md-or-agents-md)"
fi

doc_budget=$DEFAULT_DOC_BUDGET
budget_source='default'
codex_config=$CODEX_HOME_DIR/config.toml
if [ -f "$codex_config" ]; then
  section=''
  while IFS= read -r line || [ -n "$line" ]; do
    trimmed=${line#"${line%%[![:space:]]*}"}
    case $trimmed in
      '['*) section=$trimmed; continue ;;
      project_doc_max_bytes*'='*)
        [ -z "$section" ] || continue
        value=${trimmed#*=}
        value=${value%%#*}
        value=${value//[[:space:]]/}
        case $value in
          ''|*[!0-9]*) warn "project_doc_max_bytes in $codex_config is not a plain integer ('$value'); using the default" ;;
          *) doc_budget=$value; budget_source="$codex_config" ;;
        esac
        break
        ;;
    esac
  done < "$codex_config"
fi
info "Codex project_doc_max_bytes budget: $doc_budget bytes (from $budget_source)"

codex_doc=''
if [ -e "$CODEX_HOME_DIR/AGENTS.override.md" ]; then
  codex_doc=$CODEX_HOME_DIR/AGENTS.override.md
elif [ -e "$CODEX_HOME_DIR/AGENTS.md" ]; then
  codex_doc=$CODEX_HOME_DIR/AGENTS.md
fi
if [ -z "$codex_doc" ]; then
  warn "no $CODEX_HOME_DIR/AGENTS.md (nor AGENTS.override.md); Codex has no global instructions"
else
  if [ -L "$codex_doc" ]; then
    info "$codex_doc is a symlink -> $(readlink -f -- "$codex_doc" 2>/dev/null || printf '<unresolvable>')"
  else
    info "$codex_doc is a regular file"
  fi
  # Reported, never scored. The global file is loaded through its own code path and does not draw
  # on project_doc_max_bytes, so its size cannot starve a project of instructions; that budget is
  # consumed only by the project-level documents found walking up from the working directory.
  if [ -r "$codex_doc" ] && [ -f "$codex_doc" ]; then
    info "$codex_doc is $(wc -c < "$codex_doc") bytes (loaded separately; does not consume the $doc_budget-byte project budget)"
  else
    err "$codex_doc is not a readable regular file"
  fi
  # One canonical source: Codex should read the same bytes as Claude Code, not a second copy that
  # drifts. Reported, never repaired -- install.sh --global-agents is what changes it.
  if [ -f "$canonical_policy" ]; then
    codex_target=$(readlink -f -- "$codex_doc" 2>/dev/null || true)
    canonical_real=$(readlink -f -- "$canonical_policy" 2>/dev/null || printf '%s' "$canonical_policy")
    if [ "$codex_target" = "$canonical_real" ]; then
      ok "Codex reads the canonical policy ($codex_doc -> $canonical_real)"
    elif cmp -s -- "$codex_doc" "$canonical_policy"; then
      warn "$codex_doc is a separate copy of $canonical_policy with identical contents; it will drift (install.sh --global-agents --replace-global relinks it)"
    else
      warn "$codex_doc is a second, independently maintained global policy that differs from $canonical_policy; the two harnesses are running different rules"
    fi
  fi
  if [ "$codex_doc" = "$CODEX_HOME_DIR/AGENTS.override.md" ] && [ -e "$CODEX_HOME_DIR/AGENTS.md" ]; then
    warn "$codex_doc takes precedence for Codex, so $CODEX_HOME_DIR/AGENTS.md is never read"
  fi
fi
printf '\n'

printf 'Result: %d error(s), %d warning(s)\n' "$ERRORS" "$WARNINGS"
[ "$ERRORS" -eq 0 ] || exit 1
exit 0
