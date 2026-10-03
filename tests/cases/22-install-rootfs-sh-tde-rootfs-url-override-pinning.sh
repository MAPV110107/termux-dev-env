# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== install_rootfs.sh (TDE_ROOTFS_URL_OVERRIDE pinning) ==="
TDE_ROOTFS_TARBALL="$TESTROOT/pinned.tar.gz"
TDE_ROOTFS_SIG="$TESTROOT/pinned.tar.gz.sig"
export TDE_ROOTFS_TARBALL TDE_ROOTFS_SIG
curl() { touch "$3"; return 0; }
gpg() { return 0; }
TDE_ROOTFS_URL_OVERRIDE="https://example.com/verified.tar.gz" assert_pass \
  "pinned override is used and verified when set" phase3_download_and_verify
unset TDE_ROOTFS_URL_OVERRIDE
