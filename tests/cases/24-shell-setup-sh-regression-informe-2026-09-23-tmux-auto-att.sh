# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== shell_setup.sh (regression: informe 2026-09-23, tmux auto-attach hangs scripted logins) ==="
# zsh only sets its own "interactive" option off for a "-c command"
# invocation — regardless of whether a TTY happens to be attached to
# that process, which is why checking '-o interactive' (not just '-t 0')
# is what actually distinguishes a real interactive login from one of
# the many 'proot-distro login --user <name> -- <cmd>' calls every
# phase 4-6 step makes to run something inside the container. '-o
# interactive' is portable shell-option syntax (same semantics in bash),
# so bash stands in here for a real container zsh, which this sandbox
# doesn't have installed.
source "$SCRIPT_DIR/lib/idempotent_append.sh"
# Written via the real phase4_write_zshrc_extras (not a hand-copied
# snippet) so this can't silently drift from the actual code — the
# mocked proot-distro stands in for the container, same pattern as the
# idempotent_append_container test above.
ZSHRC_TEST="$TESTROOT/zshrc_snippet_test2"
mkdir -p "$ZSHRC_TEST"
proot-distro() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env) shift; export "${1?}"; shift ;;
      --) shift; break ;;
      *) shift ;;
    esac
  done
  HOME="$ZSHRC_TEST" "$@"
}
(
  source "$SCRIPT_DIR/lib/error_handling.sh"; source "$SCRIPT_DIR/lib/logging.sh"; log_init >/dev/null
  source "$SCRIPT_DIR/lib/kv.sh"; source "$SCRIPT_DIR/lib/state.sh"
  export TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source "$SCRIPT_DIR/components/shell_setup.sh"
  phase4_write_zshrc_extras
) >/dev/null 2>&1
unset -f proot-distro
assert_pass "a scripted non-interactive shell -c login does not try to run tmux or fastfetch" \
  bash -c "tmux() { echo 'TMUX SHOULD NOT RUN' >&2; exit 1; }; fastfetch() { echo 'FASTFETCH SHOULD NOT RUN' >&2; exit 1; }; source '$ZSHRC_TEST/.zshrc'; true"
assert_eq "fastfetch is guarded by interactive + TTY" "1" \
  "$(grep -c '\[\[ -o interactive \]\] && \[ -t 0 \]' "$ZSHRC_TEST/.zshrc")"
