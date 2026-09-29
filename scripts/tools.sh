#!/usr/bin/env bash
# Installs, updates and reports the agent tools that no marketplace or official installer ships:
# the MCP servers listed in setup/tools.tsv, each built from a full git clone at its pinned
# revision, with our own patches applied.
#
#   scripts/tools.sh status [--remote] [name ...]   pinned vs installed build; --remote also
#                                                   lists upstream's newest tags (network)
#   scripts/tools.sh install [name ...]             build the pinned revision and link it;
#                                                   `update` is the same command
#
# Layout, under AGENTSKILLS_TOOLS_DIR (default ${XDG_DATA_HOME:-~/.local/share}/agentskills-tools):
#   <name>/repo              the full clone; `git -C <name>/repo fetch` sees every new upstream tag
#   <name>/builds/<id>/      one worktree per pinned revision (and patch set), built in place
# and AGENTSKILLS_BIN_DIR/<name> (default ~/.local/bin) links to the current build. A new build is
# made beside the old one and the link is swapped only once it succeeds, so a running server keeps
# the files it started with; the previous build is kept, older ones are removed.
set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=${SCRIPT_DIR%/*}
MANIFEST=${AGENTSKILLS_TOOLS_MANIFEST:-$REPO_ROOT/setup/tools.tsv}
TOOLS_DIR=${AGENTSKILLS_TOOLS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/agentskills-tools}
BIN_DIR=${AGENTSKILLS_BIN_DIR:-$HOME/.local/bin}
# Absolute, so the links stay valid and the build steps' cd works from anywhere.
case $TOOLS_DIR in /*) ;; *) TOOLS_DIR=$PWD/$TOOLS_DIR ;; esac
case $BIN_DIR in /*) ;; *) BIN_DIR=$PWD/$BIN_DIR ;; esac

die() { printf 'tools.sh: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

usage() {
  sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# Reads the manifest into parallel arrays, skipping comments and blank lines.
NAMES=() KINDS=() URLS=() REVS=() SUBDIRS=() PATCHES=() AUDITS=()
load_manifest() {
  [ -f "$MANIFEST" ] || die "no manifest at $MANIFEST"
  local name kind url rev subdir patches audit extra
  while IFS=$'\t' read -r name kind url rev subdir patches audit extra || [ -n "${name:-}" ]; do
    case $name in '' | '#'*) continue ;; esac
    [ -z "${extra:-}" ] && [ -n "${audit:-}" ] || die "malformed manifest line for '$name'"
    case $kind in node | python) ;; *) die "$name: unknown kind '$kind'" ;; esac
    [[ $rev =~ ^[0-9a-f]{40}$ ]] || die "$name: rev must be a full commit SHA, not '$rev'"
    [[ $name =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "bad tool name '$name'"
    NAMES+=("$name") KINDS+=("$kind") URLS+=("$url") REVS+=("$rev")
    SUBDIRS+=("$subdir") PATCHES+=("$patches") AUDITS+=("$audit")
  done < "$MANIFEST"
}

# The patch directory of a manifest entry, absolute; fails when it is missing or has no patch, since
# an entry that names patches must never build without them.
patch_dir() {
  local dir=$1
  case $dir in /*) ;; *) dir=$REPO_ROOT/$dir ;; esac
  [ -d "$dir" ] || die "patch directory $1 is missing"
  find "$dir" -maxdepth 1 -type f -name '*.patch' | grep -q . || die "patch directory $1 has no *.patch file"
  printf '%s' "$dir"
}

# Fills the array named by $2 with the entry's patch files, in the order git am applies them. It
# runs in the calling shell, so a missing patch directory stops the script rather than a subshell.
patch_files() {
  local -n out=$2
  out=()
  [ "$1" = - ] && return 0
  local dir
  dir=$(patch_dir "$1") || exit 1
  mapfile -t out < <(find "$dir" -maxdepth 1 -type f -name '*.patch' | LC_ALL=C sort)
}

# A build's id: the revision, plus a hash of its patches so a changed patch set rebuilds.
build_id() {
  local rev=$1 patches=$2 files=()
  patch_files "$patches" files
  if [ ${#files[@]} -eq 0 ]; then
    printf '%s' "${rev:0:12}"
  else
    printf '%s-p%s' "${rev:0:12}" "$(cat "${files[@]}" | sha256sum | cut -c1-8)"
  fi
}

# The file the bin link points at, relative to a build's worktree.
entry_of() {
  local kind=$1 name=$2 subdir=$3 build=$4
  if [ "$kind" = python ]; then
    printf '%s' "${subdir%/}/venv/bin/$name" | sed 's#^\./##'
    return
  fi
  local pkg=$build/$subdir/package.json bin
  bin=$(node -e '
    const b = require(process.argv[1]).bin;
    const v = typeof b === "string" ? b : (b || {})[process.argv[2]];
    if (!v) process.exit(1);
    process.stdout.write(v);' "$pkg" "$name") || die "$name: package.json names no bin '$name'"
  printf '%s' "${subdir%/}/${bin#./}" | sed 's#^\./##'
}

# The build a bin link currently points at, or nothing.
linked_build() {
  local link=$BIN_DIR/$1 target
  [ -L "$link" ] || return 0
  target=$(readlink "$link")
  case $target in
    "$TOOLS_DIR/$1/builds/"*)
      target=${target#"$TOOLS_DIR/$1/builds/"}
      printf '%s' "${target%%/*}"
      ;;
  esac
}

build_node() {
  local dir=$1 audit=$2
  ( cd "$dir"
    npm ci --ignore-scripts
    # audit fix exits non-zero while any advisory it cannot fix in range remains; the report
    # below shows those, and the manifest's `fix` accepts them.
    if [ "$audit" = fix ]; then npm audit fix --ignore-scripts || true; fi
    if node -e 'process.exit(require("./package.json").scripts?.["test:unit"] ? 0 : 1)'; then
      npm run test:unit
    fi
    npm run build
    npm prune --omit=dev --ignore-scripts
    # Informational: an advisory the manifest has accepted still shows here.
    npm audit --omit=dev || true
  )
}

build_python() {
  local dir=$1
  ( cd "$dir"
    python3 -m venv venv
    venv/bin/pip install --quiet .
  )
}

install_one() {
  local i=$1 name=${NAMES[$1]} kind=${KINDS[$1]} url=${URLS[$1]} rev=${REVS[$1]}
  local subdir=${SUBDIRS[$1]} patches=${PATCHES[$1]} audit=${AUDITS[$1]}
  local home=$TOOLS_DIR/$name repo=$TOOLS_DIR/$name/repo link=$BIN_DIR/$name id build entry
  id=$(build_id "$rev" "$patches")
  build=$home/builds/$id

  if [ -e "$link" ] || [ -L "$link" ]; then
    case $(readlink "$link" 2>/dev/null || true) in
      "$home/builds/"*) ;;
      *) die "$link exists and is not one of our builds; move it aside first" ;;
    esac
  fi

  mkdir -p "$home/builds" "$BIN_DIR"
  if [ ! -d "$repo/.git" ]; then
    say "$name: cloning $url"
    git clone --quiet --no-checkout "$url" "$repo"
  fi
  if ! git -C "$repo" cat-file -e "$rev^{commit}" 2>/dev/null; then
    git -C "$repo" fetch --quiet --tags origin
  fi
  git -C "$repo" cat-file -e "$rev^{commit}" 2>/dev/null || die "$name: $rev is not in $url"

  if [ ! -f "$build/.agentskills-built" ]; then
    if [ -d "$build" ]; then
      git -C "$repo" worktree remove --force "$build" 2>/dev/null || rm -rf -- "$build"
    fi
    git -C "$repo" worktree prune
    if [ "$patches" = - ]; then say "$name: building ${rev:0:12}"; else say "$name: building ${rev:0:12} with $patches"; fi
    git -C "$repo" worktree add --quiet --detach "$build" "$rev"
    local files=()
    patch_files "$patches" files
    if [ ${#files[@]} -gt 0 ]; then
      git -C "$build" -c user.name=agentskills -c user.email=agentskills@localhost \
        am --quiet --committer-date-is-author-date "${files[@]}"
    fi
    case $kind in
      node) build_node "$build/$subdir" "$audit" ;;
      python) build_python "$build/$subdir" ;;
    esac
    : > "$build/.agentskills-built"
  fi

  entry=$(entry_of "$kind" "$name" "$subdir" "$build")
  [ -f "$build/$entry" ] || die "$name: the build has no $entry"
  chmod +x "$build/$entry"
  local previous
  previous=$(linked_build "$name")
  ln -sfn "$build/$entry" "$link.agentskills-new"
  mv -Tf "$link.agentskills-new" "$link"
  say "$name: $link -> builds/$id"

  # Keep the current build and the one the link pointed at before, which a running server may
  # still use; remove every other build, finished or not.
  local old
  while IFS= read -r old; do
    [ "$old" = "$id" ] && continue
    [ -n "$previous" ] && [ "$old" = "$previous" ] && continue
    git -C "$repo" worktree remove --force "$home/builds/$old" 2>/dev/null || rm -rf -- "${home:?}/builds/$old"
  done < <(ls -1 "$home/builds")
  git -C "$repo" worktree prune
}

status_one() {
  local i=$1 remote=$2 name=${NAMES[$1]} rev=${REVS[$1]} want have
  want=$(build_id "$rev" "${PATCHES[$1]}")
  have=$(linked_build "$name")
  if [ -z "$have" ]; then
    printf '%-20s pinned %-24s NOT INSTALLED\n' "$name" "$want"
  elif [ "$have" = "$want" ]; then
    printf '%-20s pinned %-24s up to date\n' "$name" "$want"
  else
    printf '%-20s pinned %-24s installed %s (run: scripts/tools.sh update %s)\n' "$name" "$want" "$have" "$name"
  fi
  if [ "$remote" = 1 ]; then
    local tags
    if tags=$(git ls-remote --tags --refs "${URLS[$1]}" 2>/dev/null); then
      printf '%s\n' "$tags" | sed 's#.*refs/tags/##' | sort -V | tail -n 3 | sed 's/^/    upstream tag /'
    else
      say "    upstream unreachable: ${URLS[$1]}"
    fi
  fi
}

selected() {
  local want=("$@") i n
  for i in "${!NAMES[@]}"; do
    if [ ${#want[@]} -eq 0 ]; then printf '%s\n' "$i"; continue; fi
    for n in "${want[@]}"; do [ "$n" = "${NAMES[$i]}" ] && printf '%s\n' "$i"; done
  done
}

main() {
  [ $# -ge 1 ] || usage 2
  local cmd=$1 remote=0 i
  shift
  load_manifest
  local args=()
  for i in "$@"; do
    case $i in
      --remote) remote=1 ;;
      -h | --help) usage 0 ;;
      -*) die "unknown option $i" ;;
      *) args+=("$i") ;;
    esac
  done
  local n
  for n in "${args[@]}"; do
    printf '%s\n' "${NAMES[@]}" | grep -qxF -- "$n" || die "no tool named '$n' in $MANIFEST"
  done
  case $cmd in
    status) for i in $(selected "${args[@]}"); do status_one "$i" "$remote"; done ;;
    install | update) for i in $(selected "${args[@]}"); do install_one "$i"; done ;;
    -h | --help | help) usage 0 ;;
    *) usage 2 ;;
  esac
}

main "$@"
