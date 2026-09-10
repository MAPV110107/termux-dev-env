#!/usr/bin/env bash
# Regression suite for logic that doesn't need a real Termux/proot
# environment: kv.sh, state.sh, idempotent_append.sh, username
# validation, compat_matrix, retry_with_backoff, and the proot version
# gate. Each of these was manually verified at least once during
# development after a real bug was found in it — this formalizes those
# checks so they don't silently regress on a future edit.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
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
source "$SCRIPT_DIR/lib/kv.sh"
export TDE_STATE_FILE="$TESTROOT/state.env"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/idempotent_append.sh"
source "$SCRIPT_DIR/lib/network.sh"
source "$SCRIPT_DIR/lib/compat_matrix.sh"
source "$SCRIPT_DIR/lib/validate_env.sh"
source "$SCRIPT_DIR/components/create_user.sh"

echo "=== kv.sh ==="
kv_set "$TESTROOT/kv.env" FOO bar
assert_eq "existing key" "bar" "$(kv_get "$TESTROOT/kv.env" FOO)"
assert_eq "missing key, no default" "" "$(kv_get "$TESTROOT/kv.env" MISSING)"
assert_eq "missing key, with default" "42" "$(kv_get "$TESTROOT/kv.env" MISSING 42)"
assert_pass "kv_get survives a missing key called directly (not just via \$())" \
  kv_get "$TESTROOT/kv.env" MISSING
kv_set "$TESTROOT/kv.env" FOO baz
assert_eq "overwrite replaces, no duplicate line" "1" "$(grep -c '^FOO=' "$TESTROOT/kv.env")"

echo ""
echo "=== state.sh ==="
state_set PHASE1_DONE 1
assert_eq "state_set/get roundtrip" "1" "$(state_get PHASE1_DONE)"
TDE_DRY_RUN=1 state_set PHASE2_DONE 1
assert_eq "state_set no-ops under dry-run" "" "$(state_get PHASE2_DONE)"
state_set PHASE3_ROOTFS_INSTALLED 1
state_set PHASE3_DONE 1
state_set PHASE4_TOOLCHAIN 1
state_clear_prefix "PHASE3"
assert_eq "state_clear_prefix removes only the targeted phase" "1" "$(state_get PHASE4_TOOLCHAIN)"
assert_eq "state_clear_prefix actually cleared it" "" "$(state_get PHASE3_DONE)"

echo ""
echo "=== idempotent_append.sh ==="
f="$TESTROOT/test.sh"
echo "existing content" > "$f"
idempotent_append "$f" "blk" "line one"
idempotent_append "$f" "blk" "line one"
idempotent_append "$f" "blk" "line one"
assert_eq "3x run stays idempotent (shell comment)" "1" "$(grep -c -- 'blk >>>' "$f")"
lf="$TESTROOT/test.lua"
echo "-- lua content" > "$lf"
idempotent_append "$lf" "opts" "vim.opt.x = 1" "--"
idempotent_append "$lf" "opts" "vim.opt.x = 1" "--"
assert_eq "idempotent with -- comment prefix" "1" "$(grep -c -- 'opts >>>' "$lf")"
assert_eq "no bare # lines leak into a lua file" "0" "$(grep -c '^#' "$lf")"

echo ""
echo "=== network.sh (retry_with_backoff) ==="
attempt=0
flaky() { attempt=$((attempt + 1)); [ "$attempt" -ge 2 ]; }
assert_pass "succeeds within max attempts" retry_with_backoff 3 1 flaky
always_fail() { return 1; }
assert_fail "returns failure after exhausting attempts" retry_with_backoff 2 1 always_fail

echo ""
echo "=== compat_matrix.sh ==="
diag="$TESTROOT/diag.env"
kv_set "$diag" CPU_CORES 8
out="$(_compat_check "cores" "8" 4 8 2>&1)"
case "$out" in *"OK"*) echo "  OK    recommended value reports OK" ;; *) echo "  FAIL  recommended value"; FAILURES=$((FAILURES+1));; esac
out="$(_compat_check "cores" "" 4 8 2>&1)"
case "$out" in *"not available"*) echo "  OK    empty value handled without crashing" ;; *) echo "  FAIL  empty value"; FAILURES=$((FAILURES+1));; esac
out="$(_compat_check "api" "unknown" 24 29 2>&1)"
case "$out" in *"not available"*) echo "  OK    non-numeric value handled without crashing" ;; *) echo "  FAIL  non-numeric value"; FAILURES=$((FAILURES+1));; esac

echo ""
echo "=== validate_env.sh ==="
assert_eq "_prompt returns default under dry-run" "def" "$(TDE_DRY_RUN=1 _prompt 'never shown: ' def)"
assert_pass "proot version 5.x is accepted" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/validate_env.sh'
  proot() { echo 'proot version 5.4.0'; }
  phase1_check_proot_version
"
assert_fail "proot version 2.x is rejected" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/validate_env.sh'
  proot() { echo 'proot version 2.0.1'; }
  phase1_check_proot_version
"
assert_pass "unparseable proot version output doesn't crash" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/validate_env.sh'
  proot() { echo 'no digits here at all'; }
  phase1_check_proot_version
"

echo ""
echo "=== create_user.sh (username validation) ==="
for name in kattze user _test a1-2; do
  assert_pass "valid: $name" _username_is_valid "$name"
done
for name in root Root "with space" "" "123start"; do
  assert_fail "invalid/reserved: [$name]" _username_is_valid "$name"
done

echo ""
echo "=== install_rootfs.sh (phase3_rootfs_ok with pacman-key/DisableSandbox) ==="
source "$SCRIPT_DIR/components/install_rootfs.sh"
proot-distro() {
  case "$*" in
    "list") echo "archarm" ;;
    *"test -d /etc/pacman.d/gnupg"*) return 0 ;;
    *"grep -q ^DisableSandbox"*) return 0 ;;
    *) return 0 ;;
  esac
}
assert_pass "rootfs_ok passes when keyring+sandbox fix are both present" phase3_rootfs_ok
proot-distro() {
  case "$*" in
    "list") echo "archarm" ;;
    *"test -d /etc/pacman.d/gnupg"*) return 0 ;;
    *"grep -q ^DisableSandbox"*) return 1 ;;
    *) return 0 ;;
  esac
}
assert_fail "rootfs_ok fails when DisableSandbox is missing" phase3_rootfs_ok

echo ""
echo "=== install_maintenance.sh (archbridge) ==="
source "$SCRIPT_DIR/components/install_maintenance.sh"
phase6_write_archbridge
assert_pass "archbridge is generated with valid syntax" bash -n "$PREFIX/bin/archbridge"
assert_eq "archbridge is executable" "yes" "$([ -x "$PREFIX/bin/archbridge" ] && echo yes)"

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
