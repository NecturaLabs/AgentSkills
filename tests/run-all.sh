#!/usr/bin/env bash
# Runs every offline verification suite and reports a combined total.
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=${SCRIPT_DIR%/*}

total_pass=0
total_fail=0

# Each suite runs inside an `if` so a non-zero exit is recorded rather than propagated: the total
# must print even when a suite fails, or a failed check reads as a crashed harness. CI derives its
# expected count from the `run_suite` lines below, so adding one here raises the bar there too.
run_suite() {
  local name=$1
  shift
  printf '\n=== %s ===\n' "$name"
  if "$@"; then
    printf '[PASS] %s\n' "$name"
    total_pass=$((total_pass + 1))
  else
    printf '[FAIL] %s\n' "$name"
    total_fail=$((total_fail + 1))
  fi
}

run_suite "validate" bash "$REPO_ROOT/scripts/validate.sh" --strict
run_suite "validator-guard" bash "$REPO_ROOT/tests/validator-guard.sh"
run_suite "install-guard" bash "$REPO_ROOT/tests/install-guard.sh"

printf '\nTotal: %d suites passed, %d suites failed\n' "$total_pass" "$total_fail"
[ "$total_fail" -eq 0 ]
