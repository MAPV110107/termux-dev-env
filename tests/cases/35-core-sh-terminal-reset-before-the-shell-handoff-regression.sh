# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== core.sh terminal reset before the shell handoff (regression: review 2026-10-03) ==="
# printf '\\033c' (two backslashes inside single quotes) prints the
# literal text \033c instead of resetting the terminal — the scrollback
# the comment above it promises to clear stays on screen.
assert_eq "core.sh's pre-handoff printf emits a real ESC-c reset, not literal text" \
  "1" \
  "$(grep -c "printf '\\\\033c'" "$SCRIPT_DIR/core.sh")"
assert_eq "core.sh never double-escapes that reset sequence" \
  "0" \
  "$(grep -c "printf '\\\\\\\\033c'" "$SCRIPT_DIR/core.sh")"
