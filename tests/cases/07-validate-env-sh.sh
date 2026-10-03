# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
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
