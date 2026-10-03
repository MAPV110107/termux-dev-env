# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo "=== kv.sh ==="
kv_set "$TESTROOT/kv.env" FOO bar
assert_eq "existing key" "bar" "$(kv_get "$TESTROOT/kv.env" FOO)"
assert_eq "missing key, no default" "" "$(kv_get "$TESTROOT/kv.env" MISSING)"
assert_eq "missing key, with default" "42" "$(kv_get "$TESTROOT/kv.env" MISSING 42)"
assert_pass "kv_get survives a missing key called directly (not just via \$())" \
  kv_get "$TESTROOT/kv.env" MISSING
kv_set "$TESTROOT/kv.env" FOO baz
assert_eq "overwrite replaces, no duplicate line" "1" "$(grep -c '^FOO=' "$TESTROOT/kv.env")"
kv_del "$TESTROOT/kv.env" FOO
assert_eq "kv_del removes key" "" "$(kv_get "$TESTROOT/kv.env" FOO)"
