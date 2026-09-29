#!/usr/bin/env bash
# Asserts what scripts/tools.sh promises: a pinned revision is built in its own worktree with our
# patches applied, the bin link swaps only to a finished build, the previous build survives one
# update, and a file it did not make is never overwritten.
#
# Everything runs offline in a mktemp sandbox: the "upstream" is a local git repository, and npm
# and python3 are stand-ins on PATH that produce the file a real build would, so the suite checks
# the script's own logic without the network or a real toolchain.
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=${SCRIPT_DIR%/*}
TOOLS=$REPO_ROOT/scripts/tools.sh

PASS=0
FAIL=0
# A space in the sandbox path, as on the disk this setup comes from, so quoting bugs fail here.
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/agentskills tools-guard.XXXXXX")
trap 'rm -rf -- "$SANDBOX"' EXIT

ok()  { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s -- %s\n' "$1" "$2"; }
check() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi
}

export HOME=$SANDBOX/home
export AGENTSKILLS_TOOLS_DIR=$SANDBOX/tools
export AGENTSKILLS_BIN_DIR=$SANDBOX/bin
export AGENTSKILLS_TOOLS_MANIFEST=$SANDBOX/tools.tsv
export GIT_CONFIG_GLOBAL=$SANDBOX/gitconfig GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$SANDBOX/fakebin"
git config --global protocol.file.allow always
git config --global init.defaultBranch main

# Stand-in npm: `run build` writes the bin the package names; every other command succeeds.
cat > "$SANDBOX/fakebin/npm" <<'EOF'
#!/usr/bin/env bash
if [ "$1 ${2:-}" = "run build" ]; then
  [ -n "${FAKE_NPM_FAIL:-}" ] && exit 1
  mkdir -p dist && printf '#!/bin/sh\necho built\n' > dist/index.js
fi
printf '%s\n' "$*" >> "${NPM_LOG:-/dev/null}"
EOF
# Stand-in python3: `-m venv venv` makes a pip that installs the package's one console script.
cat > "$SANDBOX/fakebin/python3" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "-m venv" ] || exit 1
mkdir -p "$3/bin"
printf '#!/bin/sh\nprintf "#!/bin/sh\\necho py\\n" > "%s/bin/fake-py"\n' "$PWD/$3" > "$3/bin/pip"
chmod +x "$3/bin/pip"
EOF
chmod +x "$SANDBOX/fakebin/npm" "$SANDBOX/fakebin/python3"
export PATH=$SANDBOX/fakebin:$PATH
export NPM_LOG=$SANDBOX/npm.log

# The upstream: two commits of a node package, plus a python package in a subdirectory.
UP=$SANDBOX/upstream
git init --quiet "$UP"
cat > "$UP/package.json" <<'EOF'
{ "name": "fake", "bin": { "fake-tool": "dist/index.js" }, "scripts": { "build": "x" } }
EOF
mkdir -p "$UP/py" && printf 'x\n' > "$UP/py/pyproject.toml"
git -C "$UP" add -A && git -C "$UP" -c user.name=t -c user.email=t@t commit --quiet -m one
REV1=$(git -C "$UP" rev-parse HEAD)
printf 'two\n' > "$UP/CHANGES" && git -C "$UP" add -A && git -C "$UP" -c user.name=t -c user.email=t@t commit --quiet -m two
REV2=$(git -C "$UP" rev-parse HEAD)
printf 'three\n' >> "$UP/CHANGES" && git -C "$UP" -c user.name=t -c user.email=t@t commit --quiet -am three
REV3=$(git -C "$UP" rev-parse HEAD)
printf 'four\n' >> "$UP/CHANGES" && git -C "$UP" -c user.name=t -c user.email=t@t commit --quiet -am four
REV4=$(git -C "$UP" rev-parse HEAD)
printf 'five\n' >> "$UP/CHANGES" && git -C "$UP" -c user.name=t -c user.email=t@t commit --quiet -am five
REV5=$(git -C "$UP" rev-parse HEAD)

# Our patch: adds a file, so a build with it applied can be told apart.
PATCHES=$SANDBOX/patches
mkdir -p "$PATCHES"
git -C "$UP" checkout --quiet "$REV1"
printf 'patched\n' > "$UP/PATCHED" && git -C "$UP" add PATCHED
git -C "$UP" -c user.name=t -c user.email=t@t commit --quiet -m 'fix: ours'
git -C "$UP" format-patch --quiet -1 -o "$PATCHES"
git -C "$UP" checkout --quiet main

manifest() { # rev patches
  printf '# test manifest\n' > "$AGENTSKILLS_TOOLS_MANIFEST"
  printf 'fake-tool\tnode\t%s\t%s\t.\t%s\t-\n' "$UP" "$1" "$2" >> "$AGENTSKILLS_TOOLS_MANIFEST"
  printf 'fake-py\tpython\t%s\t%s\tpy\t-\t-\n' "$UP" "$REV1" >> "$AGENTSKILLS_TOOLS_MANIFEST"
}
target() { readlink "$AGENTSKILLS_BIN_DIR/$1" 2>/dev/null; }
builds() { ls -1 "$AGENTSKILLS_TOOLS_DIR/fake-tool/builds" 2>/dev/null | wc -l | tr -d ' '; }

# 1. A fresh install clones, applies the patch, builds and links.
manifest "$REV1" "$PATCHES"
bash "$TOOLS" install > "$SANDBOX/out1" 2>&1
check "install-exit" 0 $?
case $(target fake-tool) in
  "$AGENTSKILLS_TOOLS_DIR/fake-tool/builds/${REV1:0:12}-p"*/dist/index.js) ok "install-links-patched-build" ;;
  *) bad "install-links-patched-build" "link is '$(target fake-tool)'" ;;
esac
check "install-applied-patch" patched "$(cat "$(dirname "$(dirname "$(target fake-tool)")")/PATCHED" 2>/dev/null)"
check "install-entry-runs" built "$("$AGENTSKILLS_BIN_DIR/fake-tool" 2>/dev/null)"
check "install-full-clone" false "$(git -C "$AGENTSKILLS_TOOLS_DIR/fake-tool/repo" rev-parse --is-shallow-repository)"
check "install-python-entry" py "$("$AGENTSKILLS_BIN_DIR/fake-py" 2>/dev/null)"
check "status-up-to-date" 1 "$(bash "$TOOLS" status fake-tool | grep -c 'up to date')"

# 2. Re-running with nothing changed rebuilds nothing.
: > "$NPM_LOG"
bash "$TOOLS" install fake-tool > /dev/null 2>&1
check "install-idempotent" 0 "$(grep -c 'run build' "$NPM_LOG")"

# 3. A new pin: status reports the gap, update swaps the link and keeps the previous build.
manifest "$REV2" -
check "status-behind" 1 "$(bash "$TOOLS" status fake-tool | grep -c 'run: scripts/tools.sh update fake-tool')"
bash "$TOOLS" update fake-tool > /dev/null 2>&1
check "update-exit" 0 $?
case $(target fake-tool) in
  "$AGENTSKILLS_TOOLS_DIR/fake-tool/builds/${REV2:0:12}/dist/index.js") ok "update-links-new-build" ;;
  *) bad "update-links-new-build" "link is '$(target fake-tool)'" ;;
esac
check "update-keeps-previous" 2 "$(builds)"

# 4. A third pin removes the oldest build and keeps one previous.
manifest "$REV3" -
bash "$TOOLS" update fake-tool > /dev/null 2>&1
check "update-prunes-oldest" 2 "$(builds)"
check "update-pruned-worktree" 0 "$(git -C "$AGENTSKILLS_TOOLS_DIR/fake-tool/repo" worktree list | grep -c "${REV1:0:12}")"

# 5. A failed build leaves the link where it was, and the next good build keeps that one, not the
#    failed partial, as the previous build.
manifest "$REV4" -
FAKE_NPM_FAIL=1 bash "$TOOLS" update fake-tool > /dev/null 2>&1
check "failed-build-exit" 1 $?
case $(target fake-tool) in
  */builds/${REV3:0:12}/*) ok "failed-build-keeps-link" ;;
  *) bad "failed-build-keeps-link" "link is '$(target fake-tool)'" ;;
esac
manifest "$REV5" -
bash "$TOOLS" update fake-tool > /dev/null 2>&1
check "after-failure-kept" "$(printf '%s\n' "${REV3:0:12}" "${REV5:0:12}" | sort | tr '\n' ' ')" \
  "$(ls -1 "$AGENTSKILLS_TOOLS_DIR/fake-tool/builds" | sort | tr '\n' ' ')"

# 6. An entry that names patches never builds without them.
before=$(target fake-tool)
manifest "$REV1" "$SANDBOX/no such patches"
bash "$TOOLS" install fake-tool > /dev/null 2>&1
check "missing-patch-dir-fails" 1 $?
mkdir -p "$SANDBOX/empty patches"
manifest "$REV1" "$SANDBOX/empty patches"
bash "$TOOLS" install fake-tool > /dev/null 2>&1
check "empty-patch-dir-fails" 1 $?
check "patch-failures-keep-link" "$before" "$(target fake-tool)"

# 7. An unreachable upstream is reported, and status goes on to the next tool.
printf 'gone-tool\tnode\t%s\t%s\t.\t-\t-\n' "$SANDBOX/no-such-repo" "$REV1" > "$AGENTSKILLS_TOOLS_MANIFEST"
printf 'fake-tool\tnode\t%s\t%s\t.\t-\t-' "$UP" "$REV5" >> "$AGENTSKILLS_TOOLS_MANIFEST"
bash "$TOOLS" status --remote > "$SANDBOX/out7r" 2>&1
check "remote-status-exit" 0 $?
check "remote-unreachable-reported" 1 "$(grep -c 'upstream unreachable' "$SANDBOX/out7r")"
check "last-line-without-newline-read" 1 "$(grep -c '^fake-tool' "$SANDBOX/out7r")"

# 8. A relative tools directory still yields working absolute links.
manifest "$REV5" -
( cd "$SANDBOX" && AGENTSKILLS_TOOLS_DIR="rel tools" AGENTSKILLS_BIN_DIR="rel bin" bash "$TOOLS" install fake-tool > /dev/null 2>&1 )
check "relative-dirs-link-works" built "$("$SANDBOX/rel bin/fake-tool" 2>/dev/null)"

# 9. A file it did not make is never replaced.
rm "$AGENTSKILLS_BIN_DIR/fake-py"
printf 'mine\n' > "$AGENTSKILLS_BIN_DIR/fake-py"
bash "$TOOLS" install fake-py > "$SANDBOX/out5" 2>&1
check "foreign-file-refused" 1 $?
check "foreign-file-untouched" mine "$(cat "$AGENTSKILLS_BIN_DIR/fake-py")"

# 10. Malformed pins and unknown names are rejected before anything runs.
printf 'fake-tool\tnode\t%s\tv1.0\t.\t-\t-\n' "$UP" > "$AGENTSKILLS_TOOLS_MANIFEST"
bash "$TOOLS" status > /dev/null 2>&1
check "tag-pin-rejected" 1 $?
manifest "$REV3" -
bash "$TOOLS" install nope > /dev/null 2>&1
check "unknown-name-rejected" 1 $?

# 11. The shipped manifest is well formed.
AGENTSKILLS_TOOLS_MANIFEST=$REPO_ROOT/setup/tools.tsv AGENTSKILLS_BIN_DIR=$SANDBOX/empty \
  bash "$TOOLS" status > "$SANDBOX/out7" 2>&1
check "shipped-manifest-parses" 0 $?
check "shipped-manifest-lists-all" 3 "$(grep -c 'NOT INSTALLED' "$SANDBOX/out7")"

printf '\nTools summary: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
