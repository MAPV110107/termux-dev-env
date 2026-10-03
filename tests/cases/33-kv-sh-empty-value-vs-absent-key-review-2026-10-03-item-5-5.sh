# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== kv.sh: empty value vs absent key (review 2026-10-03, item 5.5) ==="
KVT="$TESTROOT/kv_has.env"
kv_init "$KVT"
kv_set "$KVT" SET_EMPTY ""
kv_set "$KVT" SET_VALUE hello
assert_pass "kv_has is true for a key explicitly set to the empty string" kv_has "$KVT" SET_EMPTY
assert_pass "kv_has is true for a key with a value"                      kv_has "$KVT" SET_VALUE
assert_fail "kv_has is false for a key that was never written"           kv_has "$KVT" NEVER_WRITTEN
assert_fail "kv_has is false after the key is deleted"                   bash -c "
  source '$SCRIPT_DIR/lib/kv.sh'; kv_del '$KVT' SET_VALUE; kv_has '$KVT' SET_VALUE"
assert_eq "kv_get still returns the default for an empty value (documented contract)" \
  "fallback" "$(kv_get "$KVT" SET_EMPTY fallback)"
assert_fail "kv_has is false on a file that does not exist at all" kv_has "$TESTROOT/no_such_kv.env" ANY
