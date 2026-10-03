# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== create_user.sh (username validation) ==="
for name in kattze user _test a1-2; do
  assert_pass "valid: $name" _username_is_valid "$name"
done
for name in root Root "with space" "" "123start"; do
  assert_fail "invalid/reserved: [$name]" _username_is_valid "$name"
done
