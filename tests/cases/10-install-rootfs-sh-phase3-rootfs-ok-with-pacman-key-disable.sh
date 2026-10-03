# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== install_rootfs.sh (phase3_rootfs_ok with pacman-key/DisableSandbox) ==="
source "$SCRIPT_DIR/components/install_rootfs.sh"
rm -rf "$TDE_ROOTFS_PATH"
mkdir -p "$TDE_ROOTFS_PATH/etc"
proot-distro() {
  case "$*" in
    *"test -d /etc/pacman.d/gnupg"*) return 0 ;;
    *"grep -q ^DisableSandbox"*) return 0 ;;
    *) return 0 ;;
  esac
}
assert_pass "rootfs_ok passes when keyring+sandbox fix are both present" phase3_rootfs_ok
proot-distro() {
  case "$*" in
    *"test -d /etc/pacman.d/gnupg"*) return 0 ;;
    *"grep -q ^DisableSandbox"*) return 1 ;;
    *) return 0 ;;
  esac
}
assert_fail "rootfs_ok fails when DisableSandbox is missing" phase3_rootfs_ok
