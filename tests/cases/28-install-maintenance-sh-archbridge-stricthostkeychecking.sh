# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== install_maintenance.sh (archbridge StrictHostKeyChecking) ==="
phase6_write_archbridge
assert_pass "archbridge sets StrictHostKeyChecking=accept-new" \
  bash -c "grep -q 'StrictHostKeyChecking=accept-new' '$PREFIX/bin/archbridge'"
