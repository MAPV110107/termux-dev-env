# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== network.sh (retry_with_backoff) ==="
attempt=0
flaky() { attempt=$((attempt + 1)); [ "$attempt" -ge 2 ]; }
assert_pass "succeeds within max attempts" retry_with_backoff 3 1 flaky
always_fail() { return 1; }
assert_fail "returns failure after exhausting attempts" retry_with_backoff 2 1 always_fail
