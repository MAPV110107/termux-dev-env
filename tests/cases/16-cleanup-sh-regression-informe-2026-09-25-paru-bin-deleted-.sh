# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== cleanup.sh (regression: informe 2026-09-25, paru-bin deleted before it could be retried) ==="
# The bug: phase5_cleanup deleted /tmp/paru-bin whenever
# phase4_toolchain_ok passed — which only requires gcc+git since paru
# became non-blocking, so it deleted the build directory even when
# paru's OWN build/install had failed, wiping out exactly what
# TROUBLESHOOTING.md tells people to retry from.
assert_pass "cleanup does NOT delete /tmp/paru-bin when paru itself isn't actually installed" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  TDE_ROOTFS_TMPDIR='$TESTROOT/nonexistent_rootfs_tmp'
  TDE_NERDFONT_TMPDIR='$TESTROOT/nonexistent_nerdfont_tmp'
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/lib/cleanup.sh'
  phase4_toolchain_ok() { return 0; }   # gcc+git fine
  phase5_nerdfont_ok() { return 0; }
  phase3_rootfs_ok() { return 0; }
  proot-distro() {
    case \"\$*\" in
      *'command -v paru'*) return 1 ;;   # paru itself never actually got installed
      *'rm -rf /tmp/paru-bin'*) echo 'SHOULD NOT DELETE /tmp/paru-bin' >&2; return 1 ;;
      *) return 0 ;;
    esac
  }
  phase5_cleanup
"
assert_pass "cleanup DOES delete /tmp/paru-bin once paru is actually present" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  TDE_ROOTFS_TMPDIR='$TESTROOT/nonexistent_rootfs_tmp2'
  TDE_NERDFONT_TMPDIR='$TESTROOT/nonexistent_nerdfont_tmp2'
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/lib/cleanup.sh'
  phase4_toolchain_ok() { return 0; }
  phase5_nerdfont_ok() { return 0; }
  phase3_rootfs_ok() { return 0; }
  DELETED=0
  proot-distro() {
    case \"\$*\" in
      *'command -v paru'*) return 0 ;;
      *'rm -rf /tmp/paru-bin'*) DELETED=1; return 0 ;;
      *) return 0 ;;
    esac
  }
  phase5_cleanup
  [ \"\$DELETED\" = 1 ]
"
