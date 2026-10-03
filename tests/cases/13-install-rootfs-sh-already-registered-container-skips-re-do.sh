# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== install_rootfs.sh (already-registered container skips re-download) ==="
assert_pass "install_rootfs_run does not attempt gpg/import/download when the container already exists" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/network.sh'
  PREFIX='$PREFIX'
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/lib/container_paths.sh'
  mkdir -p \"\$TDE_ROOTFS_PATH/etc\"
  source '$SCRIPT_DIR/components/install_rootfs.sh'
  proot-distro() {
    case \"\$*\" in
      *\"grep -q ^DisableSandbox\"*) return 0 ;;
      *) return 0 ;;
    esac
  }
  phase3_install_gpg_tool() { echo 'SHOULD NOT BE CALLED' >&2; exit 1; }
  phase3_download_and_verify() { echo 'SHOULD NOT BE CALLED' >&2; exit 1; }
  phase3_install_rootfs_run
"
