#!/usr/bin/env bash
# Regression suite for logic that doesn't need a real Termux/proot
# environment: kv.sh, state.sh, idempotent_append.sh, username
# validation, compat_matrix, retry_with_backoff, and the proot version
# gate. Each of these was manually verified at least once during
# development after a real bug was found in it — this formalizes those
# checks so they don't silently regress on a future edit.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The sources moved under src/ (see the 2026-10-03 report). SCRIPT_DIR
# points at src/ so every "$SCRIPT_DIR/lib/..." and
# "$SCRIPT_DIR/components/..." path in the cases keeps working, and
# TDE_PROJECT_ROOT is there for the few things that live above it
# (VERSION, README, the ./core.sh launcher).
TDE_PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
SCRIPT_DIR="$TDE_PROJECT_ROOT/src"
export TDE_ROOT="$SCRIPT_DIR"
export TDE_DISTRO_NAME="archarm"

FAILURES=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  OK    $desc"
  else
    echo "  FAIL  $desc (expected [$expected], got [$actual])"
    FAILURES=$((FAILURES + 1))
  fi
}
assert_pass() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  OK    $desc"
  else
    echo "  FAIL  $desc (expected success, got failure)"
    FAILURES=$((FAILURES + 1))
  fi
}
assert_fail() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  FAIL  $desc (expected failure, got success)"
    FAILURES=$((FAILURES + 1))
  else
    echo "  OK    $desc"
  fi
}

TESTROOT="/tmp/pure_logic_test_$$"
rm -rf "$TESTROOT"
mkdir -p "$TESTROOT"
export HOME="$TESTROOT/home"
export PREFIX="$TESTROOT/usr"
mkdir -p "$HOME" "$PREFIX/bin"

source "$SCRIPT_DIR/lib/error_handling.sh"
source "$SCRIPT_DIR/lib/logging.sh"
log_init >/dev/null
source "$SCRIPT_DIR/lib/container_paths.sh"
source "$SCRIPT_DIR/lib/kv.sh"
export TDE_STATE_FILE="$TESTROOT/state.env"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/idempotent_append.sh"
source "$SCRIPT_DIR/lib/network.sh"
source "$SCRIPT_DIR/lib/compat_matrix.sh"
source "$SCRIPT_DIR/lib/validate_env.sh"
source "$SCRIPT_DIR/components/create_user.sh"

# Each "=== section ===" below lives in its own file under tests/cases/.
# They are *sourced*, in order, into this shell on purpose: the suite is
# one continuous harness — later cases legitimately depend on stubs,
# variables and state set up by earlier ones, and every assert_* updates
# the shared $FAILURES counter. Splitting them into separately executed
# scripts would change behaviour; splitting them into sourced files only
# changes where the lines live.
for _case in "$TESTS_DIR"/cases/*.sh; do
  # shellcheck source=/dev/null
  source "$_case"
done

echo ""
echo "================================================"
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
else
  echo "$FAILURES CHECK(S) FAILED"
fi
echo "================================================"
rm -rf "$TESTROOT"
exit "$FAILURES"
