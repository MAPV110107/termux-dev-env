# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== lock.sh: dynamically allocated file descriptor (review 2026-10-03, item 5.6) ==="
assert_pass "lock_acquire allocates a free fd (>=10) instead of hardcoding 200" bash -c "
  export TDE_LOCK_FILE='$TESTROOT/fd_alloc.lock' TMPDIR='$TESTROOT'
  source '$SCRIPT_DIR/lib/lock.sh'
  lock_acquire
  [ -n \"\$TDE_LOCK_FD\" ] && [ \"\$TDE_LOCK_FD\" -ge 10 ]
"
assert_pass "the lock still excludes a second process" bash -c "
  export TDE_LOCK_FILE='$TESTROOT/fd_excl.lock' TMPDIR='$TESTROOT'
  source '$SCRIPT_DIR/lib/lock.sh'
  lock_acquire
  bash -c \"export TDE_LOCK_FILE='$TESTROOT/fd_excl.lock'; source '$SCRIPT_DIR/lib/lock.sh'; lock_acquire\" 2>/dev/null && exit 1
  exit 0
"
assert_pass "core.sh's pre-exec 'exec \${TDE_LOCK_FD}>&-' closes the dynamic fd" bash -c "
  export TDE_LOCK_FILE='$TESTROOT/fd_close.lock' TMPDIR='$TESTROOT'
  source '$SCRIPT_DIR/lib/lock.sh'
  lock_acquire
  lock_release
  eval \"exec \${TDE_LOCK_FD}>&-\"
  bash -c \"export TDE_LOCK_FILE='$TESTROOT/fd_close.lock'; source '$SCRIPT_DIR/lib/lock.sh'; lock_acquire\"
"
assert_pass "lock_release is a no-op when the lock was never acquired" bash -c "
  export TDE_LOCK_FILE='$TESTROOT/never.lock' TMPDIR='$TESTROOT'
  source '$SCRIPT_DIR/lib/lock.sh'
  lock_release
"
assert_eq "lock.sh no longer hardcodes fd 200 at load time" "0" \
  "$(grep -c '^TDE_LOCK_FD=200' "$SCRIPT_DIR/lib/lock.sh")"
