# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== resumed-run safety: every interactive component works when Phase 1 is skipped (regression: review 2026-10-03) ==="
# core.sh sources lib/validate_env.sh ONLY inside its "PHASE1_DONE != 1"
# branch. _prompt used to live there, so on a resumed run (phase 1 done,
# install died later, user re-runs) create_user.sh / dev_toolchain.sh /
# fs_utils.sh called an undefined function and 'set -euo pipefail' killed
# the installer. This reproduces that exact path: source ONLY core.sh's
# unconditional preamble, then each component, and call it.
_preamble_only() {
  local component="$1" call="$2"
  bash -c "
    set -euo pipefail
    export HOME='$TESTROOT/home' PREFIX='$TESTROOT/usr' TDE_DRY_RUN=1
    export TDE_STATE_FILE='$TESTROOT/resume_state.env'
    # exactly what core.sh sources before any phase runs
    source '$SCRIPT_DIR/lib/error_handling.sh'
    source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
    source '$SCRIPT_DIR/lib/network.sh'
    source '$SCRIPT_DIR/lib/prompt.sh'
    source '$SCRIPT_DIR/lib/kv.sh'
    source '$SCRIPT_DIR/lib/state.sh'; state_init
    source '$SCRIPT_DIR/lib/container_paths.sh'
    source '$SCRIPT_DIR/lib/idempotent_append.sh'
    source '$SCRIPT_DIR/$component'
    $call
  " >/dev/null 2>&1
}
assert_pass "core.sh's preamble alone defines _prompt (no validate_env.sh)" \
  _preamble_only lib/prompt.sh '_prompt "x" d'
assert_pass "create_user.sh's username prompt works on a resumed run" \
  _preamble_only components/create_user.sh 'phase3_prompt_username'
assert_eq "resumed-run username prompt still returns the default under dry-run" \
  "user" \
  "$(bash -c "
    set -euo pipefail
    export HOME='$TESTROOT/home' PREFIX='$TESTROOT/usr' TDE_DRY_RUN=1
    export TDE_STATE_FILE='$TESTROOT/resume_state.env'
    source '$SCRIPT_DIR/lib/error_handling.sh'
    source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
    source '$SCRIPT_DIR/lib/prompt.sh'
    source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
    source '$SCRIPT_DIR/components/create_user.sh'
    phase3_prompt_username
  " 2>/dev/null)"
assert_pass "dev_toolchain.sh and fs_utils.sh load and reach _prompt on a resumed run" \
  _preamble_only components/dev_toolchain.sh 'command -v _prompt'
assert_eq "core.sh sources lib/prompt.sh unconditionally, before the Phase 1 gate" \
  "1" \
  "$(awk '/state_get PHASE1_DONE/{exit} /source "\$SCRIPT_DIR\/lib\/prompt.sh"/{n++} END{print n+0}' "$SCRIPT_DIR/core.sh")"
assert_pass "validate_env.sh still provides _prompt when sourced on its own" \
  bash -c "
    set -euo pipefail
    export HOME='$TESTROOT/home' PREFIX='$TESTROOT/usr'
    source '$SCRIPT_DIR/lib/error_handling.sh'
    source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
    source '$SCRIPT_DIR/lib/validate_env.sh'
    command -v _prompt
  "
