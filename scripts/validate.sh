#!/usr/bin/env bash
# Structural validator for the AgentSkills v2 repository layout.
# See AGENTS.md / the plugin spec for the contract this enforces.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

PERMITTED_KEYS=" name description license compatibility metadata allowed-tools "
EVAL_SUFFIXES=(explicit implicit contextual negative ambiguous)
# A second always-loaded instruction file competes with AGENTS.md; a hooks/ directory is how a
# session-start hook that reinjects instruction text would arrive. Neither belongs in this repo.
FORBIDDEN_FILES=(CLAUDE.md CLAUDE.local.md GEMINI.md)
FORBIDDEN_DIRS=(hooks)
EXAMPLE_FILES=(global-agents.md project-agents.md nested-agents.md)
# Names a harness discovers as instruction files. Under examples/ any of these would stop being an
# example and start being scoped instructions for an agent whose working directory is in there.
EXAMPLE_FORBIDDEN_NAMES=(AGENTS.md AGENTS.override.md .cursorrules)

# Read from beside this script rather than from the repo root under validation, so a sandboxed
# copy of skills/ is checked against the same list the real repository is.
NATIVE_NAMES_FILE="$SCRIPT_DIR/native-names.tsv"

STRICT=0
QUIET=0
repo_root=""

FINDINGS=()
FAIL_COUNT=0
WARN_COUNT=0

declare -A NAME_SEEN=()
declare -A NATIVE_NAME=()
declare -a FM_KEYS=()
declare -A FM_LINE=()
declare -A FM_VALUE=()
FM_END_LINE=0
FM_TOTAL_LINES=0

record() {
  local severity="$1" check="$2" message="$3" path="${4:-}"
  local entry="$severity $check: $message"
  if [[ -n "$path" ]]; then
    entry+=" — $path"
  fi
  FINDINGS+=("$entry")
  if [[ "$severity" == "FAIL" ]]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
}

# A skill that reuses a harness-native name silently displaces that harness's own maintained
# capability wherever it is installed unnamespaced -- in Claude Code it replaces the bundled command
# but not its aliases, and Codex lists both under one name. The list and its provenance live in
# native-names.tsv.
load_native_names() {
  local harness kind name ver
  if [[ ! -f "$NATIVE_NAMES_FILE" ]]; then
    record FAIL "native-name-list" "list of harness-native names not found" "$NATIVE_NAMES_FILE"
    return
  fi
  while IFS=$'\t' read -r harness kind name ver || [[ -n "$harness" ]]; do
    if [[ -z "$harness" || "$harness" == \#* ]]; then
      continue
    fi
    if [[ -z "$kind" || -z "$name" || -z "$ver" ]]; then
      record FAIL "native-name-list" "malformed entry '$harness $kind $name $ver' (want harness, kind, name, version)" "$NATIVE_NAMES_FILE"
      continue
    fi
    NATIVE_NAME["$name"]="$harness $kind, verified on $ver"
  done < "$NATIVE_NAMES_FILE"
}

rel_path() {
  local p="$1"
  printf '%s' "${p#"$repo_root"/}"
}

_strip_quotes() {
  local s="$1"
  s="${s%"${s##*[![:space:]]}"}"
  if [[ ${#s} -ge 2 && "${s:0:1}" == '"' && "${s: -1}" == '"' ]]; then
    s="${s:1:-1}"
  elif [[ ${#s} -ge 2 && "${s:0:1}" == "'" && "${s: -1}" == "'" ]]; then
    s="${s:1:-1}"
  fi
  printf '%s' "$s"
}

# Parses YAML frontmatter between the leading '---' fences of $1. Populates the
# global FM_* variables. Handles flat scalars plus '|'/'>' block scalars, which
# covers every form this repo's SKILL.md and eval frontmatter actually use;
# nested mappings/lists (metadata, allowed-tools) are recognized as keys but
# their content is not parsed since no check needs it.
parse_frontmatter() {
  local file="$1"
  FM_KEYS=()
  FM_LINE=()
  FM_VALUE=()
  FM_END_LINE=0
  FM_TOTAL_LINES=0

  local -a lines=()
  mapfile -t lines < "$file"
  FM_TOTAL_LINES=${#lines[@]}

  if [[ ${#lines[@]} -eq 0 ]]; then
    return 1
  fi
  local first="${lines[0]%$'\r'}"
  if [[ "$first" != "---" ]]; then
    return 1
  fi

  local i=1 cur_key="" block_mode="" closed=0
  local -a block_buf=()

  while [[ $i -lt ${#lines[@]} ]]; do
    local line="${lines[$i]%$'\r'}"

    if [[ "$line" == "---" ]]; then
      if [[ -n "$block_mode" && -n "$cur_key" ]]; then
        FM_VALUE["$cur_key"]="$(_join_block "$block_mode" "${block_buf[@]:-}")"
      fi
      FM_END_LINE=$((i + 1))
      closed=1
      break
    fi

    if [[ "$line" =~ ^([A-Za-z0-9_-]+):(.*)$ ]]; then
      if [[ -n "$block_mode" && -n "$cur_key" ]]; then
        FM_VALUE["$cur_key"]="$(_join_block "$block_mode" "${block_buf[@]:-}")"
      fi
      cur_key="${BASH_REMATCH[1]}"
      local rest="${BASH_REMATCH[2]}"
      while [ "${rest# }" != "$rest" ]; do rest="${rest# }"; done
      FM_KEYS+=("$cur_key")
      FM_LINE["$cur_key"]=$((i + 1))
      block_buf=()
      if [[ "$rest" == "|"* || "$rest" == ">"* ]]; then
        block_mode="${rest:0:1}"
      elif [[ -z "$rest" ]]; then
        block_mode=""
        FM_VALUE["$cur_key"]=""
      else
        block_mode=""
        FM_VALUE["$cur_key"]="$(_strip_quotes "$rest")"
      fi
    else
      if [[ -n "$block_mode" ]]; then
        block_buf+=("$line")
      fi
    fi
    i=$((i + 1))
  done

  [[ $closed -eq 1 ]] || return 2
  return 0
}

_join_block() {
  local mode="$1"
  shift
  local out="" part first=1
  for part in "$@"; do
    part="${part#"${part%%[![:space:]]*}"}"
    if [[ "$mode" == "|" ]]; then
      if [[ $first -eq 1 ]]; then out="$part"; first=0; else out+=$'\n'"$part"; fi
    else
      if [[ -z "$part" ]]; then
        continue
      fi
      if [[ $first -eq 1 ]]; then out="$part"; first=0; else out+=" $part"; fi
    fi
  done
  printf '%s' "$out"
}

has_fm_key() {
  local k="$1" x found=1
  for x in "${FM_KEYS[@]:-}"; do
    if [[ "$x" == "$k" ]]; then
      found=0
      break
    fi
  done
  return "$found"
}

# Prints "lineno:path" for every markdown link target and every bare
# references/, templates/ or scripts/ mention in $1, deduplication left to callers.
collect_candidates() {
  local file="$1"
  {
    grep -noP '\[[^\]]*\]\(\K[^)[:space:]]+' "$file" 2>/dev/null || true
    grep -noP '(?<![A-Za-z0-9_./-])(references|templates|scripts)/[A-Za-z0-9_./-]+' "$file" 2>/dev/null || true
  }
}

resolve_candidate() {
  local file="$1" path="$2" skill_root="$3"
  case "$path" in
    references/* | templates/*) printf '%s/%s' "$skill_root" "$path" ;;
    scripts/*) printf '%s/%s' "$repo_root" "$path" ;;
    *) printf '%s/%s' "$(dirname -- "$file")" "$path" ;;
  esac
}

check_link_targets() {
  local file="$1" skill_root="$2"
  local seen=$'\n' lineno path resolved
  while IFS=: read -r lineno path; do
    if [[ -z "$path" ]]; then
      continue
    fi
    case "$path" in
      http://* | https://* | mailto:* | \#*) continue ;;
    esac
    if [[ "$seen" == *$'\n'"$path"$'\n'* ]]; then
      continue
    fi
    seen+="$path"$'\n'
    resolved="$(resolve_candidate "$file" "$path" "$skill_root")"
    if [[ ! -f "$resolved" ]]; then
      record FAIL "broken-link" "unresolved path '$path'" "$(rel_path "$file"):$lineno"
    fi
  done < <(collect_candidates "$file")
}

# Every reference/template must be reachable from SKILL.md, and none may point at another
# reference in the same skill (one level deep; a warning that --strict promotes).
process_skill_references() {
  local skill_dir_name="$1"
  local skill_dir="$repo_root/skills/$skill_dir_name"
  local skill_md="$skill_dir/SKILL.md"
  local refs_dir="$skill_dir/references"
  local tmpl_dir="$skill_dir/templates"

  declare -A reachable=()
  local lineno path
  while IFS=: read -r lineno path; do
    case "$path" in
      references/* | templates/*)
        if [[ -f "$skill_dir/$path" ]]; then
          reachable["$path"]=1
        fi
        ;;
    esac
  done < <(collect_candidates "$skill_md")

  local rp
  for rp in "${!reachable[@]}"; do
    local lineno2 path2
    while IFS=: read -r lineno2 path2; do
      case "$path2" in
        references/* | templates/*)
          if [[ -f "$skill_dir/$path2" ]]; then
            reachable["$path2"]=1
          fi
          ;;
      esac
    done < <(collect_candidates "$skill_dir/$rp")
  done

  local f rel
  if [[ -d "$refs_dir" ]]; then
    while IFS= read -r -d '' f; do
      rel="references/${f#"$refs_dir"/}"
      if [[ -z "${reachable[$rel]:-}" ]]; then
        record FAIL "unreferenced-file" "not referenced from SKILL.md" "$(rel_path "$f")"
      fi
      case "$f" in
        *.md) check_link_targets "$f" "$skill_dir" ;;
      esac
    done < <(find "$refs_dir" -type f -print0)
  fi
  if [[ -d "$tmpl_dir" ]]; then
    while IFS= read -r -d '' f; do
      rel="templates/${f#"$tmpl_dir"/}"
      if [[ -z "${reachable[$rel]:-}" ]]; then
        record FAIL "unreferenced-file" "not referenced from SKILL.md" "$(rel_path "$f")"
      fi
    done < <(find "$tmpl_dir" -type f -print0)
  fi

  if [[ -d "$refs_dir" ]]; then
    while IFS= read -r -d '' f; do
      local self="${f#"$refs_dir"/}" lineno3 path3
      local -A seen_depth=()
      while IFS=: read -r lineno3 path3; do
        case "$path3" in
          references/*)
            local target="${path3#references/}"
            # One line can yield both a markdown-link hit and a bare-path hit for the same target;
            # reporting it twice double-counts the warning total.
            if [[ "$target" != "$self" && -z "${seen_depth[$lineno3:$target]:-}" ]]; then
              seen_depth[$lineno3:$target]=1
              record WARN "reference-depth" "reference file points at another reference 'references/$target'" "$(rel_path "$f"):$lineno3"
            fi
            ;;
        esac
      done < <(collect_candidates "$f")
    done < <(find "$refs_dir" -type f -name '*.md' -print0)
  fi
}

check_skill() {
  local skill_dir_name="$1"
  local skill_dir="$repo_root/skills/$skill_dir_name"
  local skill_md="$skill_dir/SKILL.md"
  local rel; rel="$(rel_path "$skill_md")"

  if ! parse_frontmatter "$skill_md"; then
    record FAIL "frontmatter-parse" "SKILL.md frontmatter missing or unterminated" "$rel"
    return
  fi

  has_fm_key name || record FAIL "frontmatter-required" "missing required key 'name'" "$rel"
  has_fm_key description || record FAIL "frontmatter-required" "missing required key 'description'" "$rel"

  local k
  for k in "${FM_KEYS[@]:-}"; do
    [[ "$PERMITTED_KEYS" == *" $k "* ]] ||
      record FAIL "frontmatter-unknown-key" "key '$k' is not permitted" "$rel:${FM_LINE[$k]:-0}"
  done

  if has_fm_key name; then
    local name_val="${FM_VALUE[name]:-}"
    if [[ ! "$name_val" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ || ${#name_val} -lt 1 || ${#name_val} -gt 64 ]]; then
      record FAIL "name-format" "invalid name '$name_val' (lowercase alphanumeric segments joined by single hyphens, 1-64 chars)" "$rel:${FM_LINE[name]}"
    fi
    if [[ "$name_val" != "$skill_dir_name" ]]; then
      record FAIL "name-dir-mismatch" "name '$name_val' does not match directory '$skill_dir_name'" "$rel:${FM_LINE[name]}"
    fi
    if [[ -n "${NATIVE_NAME[$name_val]:-}" ]]; then
      record FAIL "native-name-collision" "name '$name_val' is already a harness-native capability (${NATIVE_NAME[$name_val]}); name the guarantee this skill adds instead" "$rel:${FM_LINE[name]}"
    fi
    if [[ -n "${NAME_SEEN[$name_val]:-}" ]]; then
      record FAIL "duplicate-name" "name '$name_val' also declared by ${NAME_SEEN[$name_val]}" "$rel"
    else
      NAME_SEEN["$name_val"]="skills/$skill_dir_name"
    fi
  fi

  if has_fm_key description; then
    local desc_val="${FM_VALUE[description]:-}"
    if [[ ${#desc_val} -lt 1 || ${#desc_val} -gt 1024 ]]; then
      record FAIL "description-length" "description length ${#desc_val} out of range 1-1024" "$rel:${FM_LINE[description]}"
    fi
  fi

  if has_fm_key compatibility; then
    local compat_val="${FM_VALUE[compatibility]:-}"
    if [[ ${#compat_val} -gt 500 ]]; then
      record FAIL "compatibility-length" "compatibility length ${#compat_val} exceeds 500" "$rel:${FM_LINE[compatibility]}"
    fi
  fi

  local body_lines=$((FM_TOTAL_LINES - FM_END_LINE))
  if [[ $body_lines -gt 500 ]]; then
    record FAIL "body-length" "SKILL.md body is $body_lines lines (max 500)" "$rel"
  fi

  check_link_targets "$skill_md" "$skill_dir"
  process_skill_references "$skill_dir_name"
}

check_evals() {
  local skill_dir_name="$1"
  local suf case_name case_dir
  for suf in "${EVAL_SUFFIXES[@]}"; do
    case_name="${skill_dir_name}-${suf}"
    case_dir="$repo_root/evals/$case_name"
    if [[ ! -d "$case_dir" ]]; then
      record FAIL "eval-case-missing" "missing eval case directory" "evals/$case_name"
      continue
    fi
    if [[ ! -f "$case_dir/prompt.md" ]]; then
      record FAIL "eval-case-missing" "missing prompt.md" "evals/$case_name/prompt.md"
    elif ! parse_frontmatter "$case_dir/prompt.md"; then
      record FAIL "eval-frontmatter" "prompt.md frontmatter missing or unterminated" "evals/$case_name/prompt.md"
    fi

    if [[ ! -d "$case_dir/graders" ]]; then
      record FAIL "eval-case-missing" "missing graders directory" "evals/$case_name/graders"
      continue
    fi
    local -a grader_files=()
    local gf
    while IFS= read -r -d '' gf; do grader_files+=("$gf"); done \
      < <(find "$case_dir/graders" -maxdepth 1 -type f -name '*.md' -print0)
    if [[ ${#grader_files[@]} -eq 0 ]]; then
      record FAIL "eval-case-missing" "graders directory is empty" "evals/$case_name/graders"
      continue
    fi
    for gf in "${grader_files[@]}"; do
      if ! parse_frontmatter "$gf"; then
        record FAIL "eval-frontmatter" "grader frontmatter missing or unterminated" "$(rel_path "$gf")"
      elif ! has_fm_key type; then
        record FAIL "eval-frontmatter" "grader missing required 'type' key" "$(rel_path "$gf")"
      elif ! awk -v end="$FM_END_LINE" 'NR > end && /[^[:space:]]/ { found = 1 } END { exit !found }' "$gf"; then
        record FAIL "eval-grader-description" "grader body does not describe the prompt it grades" "$(rel_path "$gf")"
      fi
    done
  done
}

check_version_consistency() {
  local pkg="$repo_root/package.json"
  local plugin="$repo_root/.claude-plugin/plugin.json"
  if [[ ! -f "$pkg" ]]; then
    record FAIL "version-mismatch" "package.json not found" "package.json"
    return
  fi
  if [[ ! -f "$plugin" ]]; then
    record FAIL "version-mismatch" "plugin.json not found" ".claude-plugin/plugin.json"
    return
  fi
  local v1 v2
  v1="$(grep -m1 -oP '"version"\s*:\s*"\K[^"]*' "$pkg" 2>/dev/null || true)"
  v2="$(grep -m1 -oP '"version"\s*:\s*"\K[^"]*' "$plugin" 2>/dev/null || true)"
  if [[ -z "$v1" ]]; then
    record FAIL "version-mismatch" "no version field found" "package.json"
  fi
  if [[ -z "$v2" ]]; then
    record FAIL "version-mismatch" "no version field found" ".claude-plugin/plugin.json"
  fi
  if [[ -n "$v1" && ! "$v1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    record FAIL "version-mismatch" "package.json version '$v1' is not plain X.Y.Z" "package.json"
  fi
  if [[ -n "$v2" && ! "$v2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    record FAIL "version-mismatch" "plugin.json version '$v2' is not plain X.Y.Z" ".claude-plugin/plugin.json"
  fi
  if [[ -n "$v1" && -n "$v2" && "$v1" != "$v2" ]]; then
    record FAIL "version-mismatch" "package.json ($v1) and plugin.json ($v2) disagree" "package.json"
  fi
  return 0
}

check_forbidden_artifacts() {
  local prune=( \( -path "$repo_root/.git" \
    -o -path "$repo_root/.claude/worktrees" \
    -o -path "$repo_root/node_modules" \
    -o -path "$repo_root/evals/results" \) -prune -o )
  local name f

  # -type l as well: a symlinked CLAUDE.md loads just the same.
  for name in "${FORBIDDEN_FILES[@]}"; do
    while IFS= read -r -d '' f; do
      record FAIL "forbidden-artifact" "competing instruction file '$name' present" "$(rel_path "$f")"
    done < <(find "$repo_root" "${prune[@]}" \( -type f -o -type l \) -name "$name" -print0)
  done

  for name in "${FORBIDDEN_DIRS[@]}"; do
    while IFS= read -r -d '' f; do
      record FAIL "forbidden-artifact" "session hook directory '$name' present" "$(rel_path "$f")"
    done < <(find "$repo_root" "${prune[@]}" -type d -name "$name" -print0)
  done
}

# examples/ ships finished instruction files for users to copy. Two properties matter: they exist
# (a broken example is worse than none, since the README points at them), and they stay inert.
# Harnesses discover instruction files by name, so an example named AGENTS.md would be loaded as
# real policy by any agent working under examples/ -- which is exactly what the naming avoids.
check_examples() {
  local dir="$repo_root/examples" name f rel base

  if [[ ! -d "$dir" ]]; then
    record FAIL "example-missing" "examples/ directory not found" "examples"
    return
  fi

  for name in "${EXAMPLE_FILES[@]}"; do
    if [[ ! -f "$dir/$name" ]]; then
      record FAIL "example-missing" "required example not found" "examples/$name"
    elif [[ ! -s "$dir/$name" ]]; then
      record FAIL "example-missing" "example file is empty" "examples/$name"
    fi
  done

  while IFS= read -r -d '' f; do
    base="${f##*/}"
    rel="$(rel_path "$f")"
    for name in "${EXAMPLE_FORBIDDEN_NAMES[@]}"; do
      if [[ "$base" == "$name" ]]; then
        record FAIL "example-not-inert" \
          "'$name' under examples/ would load as scoped instructions, not as an example" "$rel"
      fi
    done
  done < <(find "$dir" -type f -print0 2>/dev/null)
}

check_shell_syntax() {
  local f err
  while IFS= read -r -d '' f; do
    err="$(bash -n "$f" 2>&1 1>/dev/null || true)"
    if [[ -n "$err" ]]; then
      record FAIL "shell-syntax" "bash -n failed: ${err//$'\n'/ }" "$(rel_path "$f")"
    fi
  done < <(find "$repo_root/scripts" "$repo_root/tests" -type f -name '*.sh' -print0 2>/dev/null)
}

# install, uninstall and doctor each carry the skill list as a literal, and so does the install
# guard. One that falls behind installs, reports or removes the wrong set without failing anything.
check_skill_lists() {
  local f line list want have
  [[ -d "$repo_root/skills" ]] || return 0
  want="$(find "$repo_root/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tr '\n' ' ')"
  for f in "$repo_root/scripts/install.sh" "$repo_root/scripts/uninstall.sh" \
    "$repo_root/scripts/doctor.sh" "$repo_root/tests/install-guard.sh"; do
    [[ -f "$f" ]] || continue
    line="$(grep -m1 -E '^SKILLS=\(' "$f" || true)"
    if [[ -z "$line" ]]; then
      record FAIL "skill-list-drift" "no SKILLS=(...) list found" "$(rel_path "$f")"
      continue
    fi
    list="${line#SKILLS=(}"
    list="${list%)}"
    # shellcheck disable=SC2086 -- word splitting of the literal list is the point
    have="$(printf '%s\n' $list | sort | tr '\n' ' ')"
    if [[ "$have" != "$want" ]]; then
      record FAIL "skill-list-drift" "lists '${have% }' but skills/ holds '${want% }'" "$(rel_path "$f")"
    fi
  done
}

check_skills_and_evals() {
  if [[ ! -d "$repo_root/skills" ]]; then
    record FAIL "skills-structure" "skills/ directory not found" "skills"
  else
    local sd d
    while IFS= read -r -d '' d; do
      sd="$(basename -- "$d")"
      if [[ ! -d "$d" ]]; then
        record FAIL "skills-structure" "stray non-directory entry under skills/" "skills/$sd"
        continue
      fi
      if [[ ! -f "$d/SKILL.md" ]]; then
        record FAIL "skills-structure" "missing SKILL.md" "skills/$sd"
        continue
      fi
      check_skill "$sd"
      check_evals "$sd"
    done < <(find "$repo_root/skills" -mindepth 1 -maxdepth 1 -print0)
    # A symlink in a skill ships whatever it points at on the author's machine, and dangles
    # everywhere else.
    while IFS= read -r -d '' d; do
      record FAIL "skills-structure" "symlink inside skills/" "$(rel_path "$d")"
    done < <(find "$repo_root/skills" -mindepth 1 -type l -print0)
  fi

  [[ -d "$repo_root/evals" ]] ||
    record FAIL "eval-case-missing" "evals/ directory not found" "evals"
}

usage() {
  cat <<'EOF'
Usage: validate.sh [repo_root] [--strict] [--quiet]
EOF
}

main() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --strict) STRICT=1 ;;
      --quiet) QUIET=1 ;;
      -h | --help) usage; exit 0 ;;
      -*) echo "unknown option: $arg" >&2; usage >&2; exit 2 ;;
      *) repo_root="$arg" ;;
    esac
  done

  repo_root="${repo_root:-$DEFAULT_REPO_ROOT}"
  if [[ ! -d "$repo_root" ]]; then
    echo "repo root not found: $repo_root" >&2
    exit 2
  fi
  repo_root="$(cd -- "$repo_root" && pwd)"

  load_native_names
  check_shell_syntax
  check_version_consistency
  check_forbidden_artifacts
  check_examples
  check_skills_and_evals
  check_skill_lists

  if [[ $QUIET -eq 0 ]]; then
    local entry
    for entry in "${FINDINGS[@]:-}"; do
      if [[ -n "$entry" ]]; then
        printf '%s\n' "$entry"
      fi
    done
  fi

  local mode=""
  if [[ $STRICT -eq 1 ]]; then
    mode=" (strict)"
  fi
  printf 'Summary: %d failure(s), %d warning(s)%s\n' "$FAIL_COUNT" "$WARN_COUNT" "$mode"

  if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
  fi
  if [[ $STRICT -eq 1 && $WARN_COUNT -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

main "$@"
