# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== compat_matrix.sh ==="
diag="$TESTROOT/diag.env"
kv_set "$diag" CPU_CORES 8
out="$(_compat_check "cores" "8" 4 8 2>&1)"
case "$out" in *"OK"*) echo "  OK    recommended value reports OK" ;; *) echo "  FAIL  recommended value"; FAILURES=$((FAILURES+1));; esac
out="$(_compat_check "cores" "" 4 8 2>&1)"
case "$out" in *"not available"*) echo "  OK    empty value handled without crashing" ;; *) echo "  FAIL  empty value"; FAILURES=$((FAILURES+1));; esac
out="$(_compat_check "api" "unknown" 24 29 2>&1)"
case "$out" in *"not available"*) echo "  OK    non-numeric value handled without crashing" ;; *) echo "  FAIL  non-numeric value"; FAILURES=$((FAILURES+1));; esac
