# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== install_maintenance.sh (regression: informe 2026-09-25, archhealth/archdiag missing sources for self-heal) ==="
assert_pass "archhealth sources network.sh, idempotent_append.sh, telecom.sh, nerdfonts.sh (needed by phase5_self_heal)" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export PREFIX='$TESTROOT/maint_prefix1'; mkdir -p \"\$PREFIX/bin\"
  source '$SCRIPT_DIR/components/install_maintenance.sh'
  phase6_write_archhealth
  grep -q '^source lib/network.sh' \"\$PREFIX/bin/archhealth\" &&
  grep -q '^source lib/idempotent_append.sh' \"\$PREFIX/bin/archhealth\" &&
  grep -q '^source components/telecom.sh' \"\$PREFIX/bin/archhealth\" &&
  grep -q '^source components/nerdfonts.sh' \"\$PREFIX/bin/archhealth\"
"
assert_pass "archdiag sources network.sh, idempotent_append.sh, telecom.sh, nerdfonts.sh (needed by phase5_self_heal)" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export PREFIX='$TESTROOT/maint_prefix2'; mkdir -p \"\$PREFIX/bin\"
  source '$SCRIPT_DIR/components/install_maintenance.sh'
  phase6_write_archdiag
  grep -q '^source lib/network.sh' \"\$PREFIX/bin/archdiag\" &&
  grep -q '^source lib/idempotent_append.sh' \"\$PREFIX/bin/archdiag\" &&
  grep -q '^source components/telecom.sh' \"\$PREFIX/bin/archdiag\" &&
  grep -q '^source components/nerdfonts.sh' \"\$PREFIX/bin/archdiag\"
"
assert_pass "archupdate retries pacman -Syu instead of a single unguarded attempt" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export PREFIX='$TESTROOT/maint_prefix3'; mkdir -p \"\$PREFIX/bin\"
  source '$SCRIPT_DIR/components/install_maintenance.sh'
  phase6_write_archupdate
  grep -q 'retry_with_backoff' \"\$PREFIX/bin/archupdate\" && grep -q '^source lib/network.sh' \"\$PREFIX/bin/archupdate\"
"
assert_pass "archhealth, archdiag, archupdate all still generate with valid bash syntax" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export PREFIX='$TESTROOT/maint_prefix4'; mkdir -p \"\$PREFIX/bin\"
  source '$SCRIPT_DIR/components/install_maintenance.sh'
  phase6_write_archhealth; phase6_write_archdiag; phase6_write_archupdate
  bash -n \"\$PREFIX/bin/archhealth\" && bash -n \"\$PREFIX/bin/archdiag\" && bash -n \"\$PREFIX/bin/archupdate\"
"
