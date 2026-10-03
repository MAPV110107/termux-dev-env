# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== idempotent_append.sh ==="
f="$TESTROOT/test.sh"
echo "existing content" > "$f"
idempotent_append "$f" "blk" "line one"
idempotent_append "$f" "blk" "line one"
idempotent_append "$f" "blk" "line one"
assert_eq "3x run stays idempotent (shell comment)" "1" "$(grep -c -- 'blk >>>' "$f")"
lf="$TESTROOT/test.lua"
echo "-- lua content" > "$lf"
idempotent_append "$lf" "opts" "vim.opt.x = 1" "--"
idempotent_append "$lf" "opts" "vim.opt.x = 1" "--"
assert_eq "idempotent with -- comment prefix" "1" "$(grep -c -- 'opts >>>' "$lf")"
assert_eq "no bare # lines leak into a lua file" "0" "$(grep -c '^#' "$lf")"
# Regression: each re-run used to leave its blank separator behind, so
# .zshrc/.bashrc/lua configs grew by a line per run. Counting markers
# (above) can't see that — compare the whole file's size instead.
sf="$TESTROOT/stable.sh"; printf 'base\n\nuser text\n' > "$sf"
idempotent_append "$sf" "blk" "line one"; size1="$(wc -c < "$sf")"
idempotent_append "$sf" "blk" "line one"; idempotent_append "$sf" "blk" "line one"; idempotent_append "$sf" "blk" "line one"
assert_eq "file size is stable after the first run (no blank-line growth)" "$size1" "$(wc -c < "$sf")"
assert_eq "user's own blank lines around the block are preserved" "1" "$(head -3 "$sf" | grep -c '^$')"
