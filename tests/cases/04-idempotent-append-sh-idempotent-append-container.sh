# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== idempotent_append.sh (idempotent_append_container) ==="
# proot-distro login --user is mocked to just run the given command
# directly against a real fake $HOME on disk, standing in for "inside
# the container" — this asserts the function's own logic (marker
# dedup, --env passthrough of multi-line content) without needing a
# real proot-distro.
CONTAINER_HOME_TEST="$TESTROOT/container_home_test"
mkdir -p "$CONTAINER_HOME_TEST"
proot-distro() {
  # Drop "login DISTRO --user USER", actually export "--env NAME=VALUE"
  # pairs (idempotent_append_container's whole content passthrough
  # depends on these reaching the sh -c script as real env vars), then
  # run whatever follows "--".
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env) shift; export "${1?}"; shift ;;
      --) shift; break ;;
      *) shift ;;
    esac
  done
  HOME="$CONTAINER_HOME_TEST" "$@"
}
idempotent_append_container archarm kattze ".config/nvim/lua/config/options.lua" "options" "vim.opt.x = 1" "--"
idempotent_append_container archarm kattze ".config/nvim/lua/config/options.lua" "options" "vim.opt.x = 1" "--"
idempotent_append_container archarm kattze ".config/nvim/lua/config/options.lua" "options" "vim.opt.x = 1" "--"
assert_eq "idempotent_append_container stays idempotent across 3 calls" "1" \
  "$(grep -c -- 'options >>>' "$CONTAINER_HOME_TEST/.config/nvim/lua/config/options.lua")"
SIZE_C1="$(wc -c < "$CONTAINER_HOME_TEST/.config/nvim/lua/config/options.lua")"
idempotent_append_container archarm kattze ".config/nvim/lua/config/options.lua" "options" "vim.opt.x = 1" "--"
assert_eq "idempotent_append_container file size is stable (no blank-line growth)" "$SIZE_C1" \
  "$(wc -c < "$CONTAINER_HOME_TEST/.config/nvim/lua/config/options.lua")"
assert_eq "idempotent_append_container preserves multi-line content intact" "vim.opt.x = 1" \
  "$(grep 'vim.opt.x' "$CONTAINER_HOME_TEST/.config/nvim/lua/config/options.lua")"
unset -f proot-distro
