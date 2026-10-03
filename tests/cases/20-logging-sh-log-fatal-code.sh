# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== logging.sh (log_fatal_code) ==="
assert_fail "log_fatal_code aborts with a nonzero exit" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'
  export TDE_CONFIG_DIR='$TESTROOT/errcode_cfg'; TDE_LOG_DIR='$TESTROOT/errcode_cfg/logs'
  mkdir -p \"\$TDE_CONFIG_DIR\"
  log_fatal_code 999 'boom' >/dev/null
"
assert_pass "log_fatal_code tags the message and writes last_error.env" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'
  TDE_CONFIG_DIR='$TESTROOT/errcode_cfg2'; mkdir -p \"\$TDE_CONFIG_DIR\"
  out=\"\$( (log_fatal_code 321 'useradd failed') 2>&1 || true)\"
  grep -q '\[E321\] useradd failed' <<< \"\$out\" &&
  grep -q '^CODE=E321' \"\$TDE_CONFIG_DIR/last_error.env\"
"
# Every E-code in the source must be documented in docs/ERROR_CODES.md.
assert_pass "every log_fatal_code used in the source is documented in ERROR_CODES.md" bash -c "
  # Sources live in src/ (SCRIPT_DIR); the docs stay at the project root.
  cd '$SCRIPT_DIR'
  for c in \$(grep -rhoE 'log_fatal_code [0-9]+' core.sh components lib | awk '{print \$2}' | sort -u); do
    grep -q \"E\$c\" '$TDE_PROJECT_ROOT/docs/ERROR_CODES.md' || { echo \"undocumented: E\$c\" >&2; exit 1; }
  done
"
