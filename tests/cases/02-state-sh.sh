# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== state.sh ==="
state_set PHASE1_DONE 1
assert_eq "state_set/get roundtrip" "1" "$(state_get PHASE1_DONE)"
TDE_DRY_RUN=1 state_set PHASE2_DONE 1
assert_eq "state_set no-ops under dry-run" "" "$(state_get PHASE2_DONE)"
state_set PHASE3_ROOTFS_INSTALLED 1
state_set PHASE3_DONE 1
state_set PHASE4_TOOLCHAIN 1
state_set ARCH_USERNAME "kattze"
state_del ARCH_USERNAME
assert_eq "state_del clears key" "" "$(state_get ARCH_USERNAME)"
state_clear_prefix "PHASE3"
assert_eq "state_clear_prefix removes only the targeted phase" "1" "$(state_get PHASE4_TOOLCHAIN)"
assert_eq "state_clear_prefix actually cleared it" "" "$(state_get PHASE3_DONE)"
