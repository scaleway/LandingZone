#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# tests/run-tests.sh -- offline regression suite (no cloud, no network).
#
# Covers, without any credentials or live infrastructure:
#   1. test_fw_tool.py     fw-tool.sh export/probe paths       (mocked ssh/rclone/http)
#   2. test_driver.sh      apply/destroy CLI orchestration     (fake terraform)
#
# Run from anywhere:  make test   or   ./tests/run-tests.sh
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

FAILS=0
run() {
  local label="$1"; shift
  local out
  out="$(mktemp)"
  if "$@" >"$out" 2>&1; then
    printf 'PASS: %s\n' "$label"
  else
    printf 'FAIL: %s\n' "$label"
    tail -20 "$out" | sed 's/^/    /'
    FAILS=$((FAILS+1))
  fi
  rm -f "$out"
}

run "fw-tool (mocked ssh/rclone/http)" python3 test_fw_tool.py
run "CLI driver (fake terraform)"      ./test_driver.sh

if [ "$FAILS" -eq 0 ]; then
  echo ""
  echo "ALL TEST SUITES PASSED"
  exit 0
else
  echo ""
  echo "TEST SUITES FAILED: ${FAILS}"
  exit 1
fi
