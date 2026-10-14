#!/usr/bin/env bash
# Unified unit and regression test suite for termux-dev-env v1.0.0.
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TDE_PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
SCRIPT_DIR="$TDE_PROJECT_ROOT/src"
export TDE_ROOT="$TDE_PROJECT_ROOT"
export TDE_DISTRO_NAME="archarm"

FAILURES=0
PASSED=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  OK    $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL  $desc (expected [$expected], got [$actual])"
    FAILURES=$((FAILURES + 1))
  fi
}
assert_pass() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  OK    $desc"
    PASSED=$((PASSED + 1))
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
    PASSED=$((PASSED + 1))
  fi
}

TESTROOT="$(mktemp -d "${TMPDIR:-/tmp}/tde_test.XXXXXX")"
export HOME="$TESTROOT/home"
export PREFIX="$TESTROOT/usr"
mkdir -p "$HOME" "$PREFIX/bin" "$PREFIX/tmp"
export TDE_STATE_FILE="$TESTROOT/state.env"

source "$SCRIPT_DIR/lib/core.sh"
log_init >/dev/null
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/lock.sh"
source "$SCRIPT_DIR/lib/system.sh"
source "$SCRIPT_DIR/lib/validate.sh"
source "$SCRIPT_DIR/modules/rootfs.sh"
source "$SCRIPT_DIR/modules/user.sh"
source "$SCRIPT_DIR/modules/launcher.sh"
source "$SCRIPT_DIR/modules/toolchain.sh"
source "$SCRIPT_DIR/modules/nerdfonts.sh"
source "$SCRIPT_DIR/modules/shell.sh"
source "$SCRIPT_DIR/modules/neovim.sh"
source "$SCRIPT_DIR/modules/maintenance.sh"
source "$SCRIPT_DIR/lib/audit.sh"

echo "=== 1. State & KV Store ==="
kv_set "$TESTROOT/kv.env" KEY1 val1
assert_eq "kv_get retrieves value" "val1" "$(kv_get "$TESTROOT/kv.env" KEY1)"
assert_eq "kv_get returns default on missing" "def" "$(kv_get "$TESTROOT/kv.env" MISSING def)"
kv_set "$TESTROOT/kv.env" EMPTY_KEY ""
assert_pass "kv_has detects empty key" kv_has "$TESTROOT/kv.env" EMPTY_KEY
state_set PHASE1_DONE 1
assert_eq "state_set/get roundtrip" "1" "$(state_get PHASE1_DONE)"
TDE_DRY_RUN=1 state_set PHASE2_DONE 1
assert_eq "state_set honours dry-run" "" "$(state_get PHASE2_DONE)"
TDE_DRY_RUN=1 state_del PHASE1_DONE
assert_eq "state_del honours dry-run" "1" "$(state_get PHASE1_DONE)"

echo "=== 2. Lock & Network ==="
assert_pass "lock_acquire allocates dynamic FD >= 10" bash -c "
  export TDE_LOCK_FILE='$TESTROOT/dyn.lock' TMPDIR='$TESTROOT'
  source '$SCRIPT_DIR/lib/lock.sh'
  lock_acquire
  [ \"\${TDE_LOCK_FD:-0}\" -ge 10 ] && [ \"\$(cat '$TESTROOT/dyn.lock')\" = \"\$\$\" ]
"
assert_eq "retry_with_backoff aborts immediately on SIGINT (130)" "1" "$(bash -c "
  source '$SCRIPT_DIR/lib/core.sh'; log_init >/dev/null; source '$SCRIPT_DIR/lib/system.sh'
  N=0; int_fn() { N=\$((N+1)); return 130; }
  retry_with_backoff 3 1 int_fn >/dev/null 2>&1 || true
  echo \$N
")"

echo "=== 3. Idempotent Append (Host & Container) ==="
f="$TESTROOT/rc.sh"; printf 'base\n\nuser\n' > "$f"
idempotent_append "$f" "blk" "line 1"; sz1="$(wc -c < "$f")"
idempotent_append "$f" "blk" "line 1"; idempotent_append "$f" "blk" "line 1"
assert_eq "idempotent_append does not grow blank lines across re-runs" "$sz1" "$(wc -c < "$f")"

echo "=== 4. Username & Validation ==="
assert_pass "valid username accepted" _username_is_valid "kattze"
assert_fail "reserved username rejected (root)" _username_is_valid "root"
assert_fail "reserved username rejected (wheel)" _username_is_valid "wheel"
assert_fail "invalid syntax rejected" _username_is_valid "123user"

echo "=== 5. Nerd Fonts Verification & Inode Replacement ==="
NF_DIR="$TESTROOT/nf"; mkdir -p "$NF_DIR"
: > "$NF_DIR/empty.ttf"
{ printf '\x00\x01\x00\x00'; head -c 300000 /dev/zero; } > "$NF_DIR/unpatched.ttf"
{ printf '\x00\x01\x00\x00'; head -c 2200000 /dev/zero; } > "$NF_DIR/patched.ttf"
{ printf 'NOPE'; head -c 2200000 /dev/zero; } > "$NF_DIR/bogus.ttf"
assert_fail "empty file rejected" nerdfont_file_ok "$NF_DIR/empty.ttf"
assert_fail "non-font magic bytes rejected" nerdfont_file_ok "$NF_DIR/bogus.ttf"
assert_pass "unpatched TTF passes basic file check" nerdfont_file_ok "$NF_DIR/unpatched.ttf"
assert_fail "unpatched TTF rejected by nerdfont_is_patched" nerdfont_is_patched "$NF_DIR/unpatched.ttf"
assert_pass "patched Nerd Font (>1MB + valid magic) passes nerdfont_is_patched" nerdfont_is_patched "$NF_DIR/patched.ttf"
assert_pass "_nerdfont_atomic_install creates a fresh inode (replaces existing file)" bash -c "
  export HOME='$NF_DIR/home'; mkdir -p \"\$HOME/.termux\"
  source '$SCRIPT_DIR/lib/core.sh'; log_init >/dev/null; source '$SCRIPT_DIR/modules/nerdfonts.sh'
  cp '$NF_DIR/unpatched.ttf' \"\$HOME/.termux/font.ttf\"
  ln \"\$HOME/.termux/font.ttf\" \"\$HOME/old_inode\"
  _nerdfont_atomic_install \"cat '$NF_DIR/patched.ttf'\"
  [ \"\$(wc -c < \"\$HOME/old_inode\")\" -lt 500000 ] && nerdfont_is_patched \"\$HOME/.termux/font.ttf\"
"

echo "=== 6. Treesitter & Neovim Configs ==="
assert_pass "TDE_TREESITTER_FULL=1 expands parser list" bash -c "
  source '$SCRIPT_DIR/modules/neovim.sh'
  c1=\"\$(TDE_TREESITTER_FULL=0 _tde_resolve_ts_parsers | wc -w)\"
  c2=\"\$(TDE_TREESITTER_FULL=1 _tde_resolve_ts_parsers | wc -w)\"
  [ \"\$c2\" -gt \"\$c1\" ]
"

echo ""
echo "================================================"
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL $PASSED CHECKS PASSED"
else
  echo "$FAILURES CHECK(S) FAILED"
fi
echo "================================================"
rm -rf "$TESTROOT"
exit "$FAILURES"