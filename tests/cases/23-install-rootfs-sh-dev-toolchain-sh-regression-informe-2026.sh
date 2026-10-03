# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== install_rootfs.sh / dev_toolchain.sh (regression: informe 2026-09-24, mirror timeouts / mkinitcpio noise) ==="
proot-distro() { return 0; }
assert_pass "phase3_write_pacman_mirrorlist writes one Server line per TDE_ARM_MIRRORS entry" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/install_rootfs.sh'
  WRITTEN=''
  proot-distro() {
    case \"\$*\" in
      *'sh -c'*) WRITTEN=\"\${*: -1}\" ;;
    esac
  }
  phase3_write_pacman_mirrorlist
  [ \"\$(grep -c '^Server = http://' <<< \"\$WRITTEN\")\" = \"\${#TDE_ARM_MIRRORS[@]}\" ]
"
assert_pass "phase3_write_pacman_mirrorlist doesn't abort the run if the write fails (best-effort)" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/install_rootfs.sh'
  proot-distro() { return 1; }
  phase3_write_pacman_mirrorlist
"
assert_pass "phase3_ignore_kernel_pkg doesn't abort the run if the write fails (best-effort)" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/install_rootfs.sh'
  proot-distro() { return 1; }
  phase3_ignore_kernel_pkg
"
# The bug from the report: a single transient DNS/timeout blip against
# mirror.archlinuxarm.org (the tarball's single default mirror) took the
# whole toolchain phase down with no retry at all.
assert_pass "phase4_sync_and_install_toolchain retries pacman -Syu on a transient failure" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/network.sh'
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  ATTEMPT=0
  proot-distro() {
    case \"\$*\" in
      *'pacman -Syu'*)
        ATTEMPT=\$((ATTEMPT + 1))
        [ \"\$ATTEMPT\" -ge 2 ]  # fails once, then succeeds — simulates a transient timeout
        ;;
      *'pacman -S'*) return 0 ;;
      *) return 0 ;;
    esac
  }
  phase4_sync_and_install_toolchain
"
assert_fail "phase4_sync_and_install_toolchain still fails after exhausting retries, with an actionable message" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/network.sh'
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  proot-distro() { case \"\$*\" in *'pacman -Syu'*) return 1 ;; *) return 0 ;; esac; }
  phase4_sync_and_install_toolchain 2>&1 | grep -q 'network/mirror issue'
"
