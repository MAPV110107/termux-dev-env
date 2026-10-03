# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== lock.sh (real-device bug: bare /tmp not guaranteed in Termux) ==="
assert_pass "lock_acquire works without a real /tmp, using \$PREFIX/tmp" bash -c "
  export PREFIX='$TESTROOT/usr'
  unset TMPDIR
  source '$SCRIPT_DIR/lib/error_handling.sh'
  source '$SCRIPT_DIR/lib/lock.sh'
  lock_acquire
  [ -f \"\$TDE_LOCK_FILE\" ]
"
assert_pass "lock.sh loads safely when PREFIX and TMPDIR are unset" bash -c "
  unset PREFIX
  unset TMPDIR
  source '$SCRIPT_DIR/lib/error_handling.sh'
  source '$SCRIPT_DIR/lib/lock.sh'
"
