# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== dev_toolchain.sh (paru.conf written container-side; regression: informe 2026-09-25) ==="
assert_pass "write_paru_conf writes container-side, not a host-side container_home path" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  LOGGED_IN=0
  proot-distro() { LOGGED_IN=1; return 0; }
  phase4_write_paru_conf
  [ \"\$LOGGED_IN\" = 1 ]
"
