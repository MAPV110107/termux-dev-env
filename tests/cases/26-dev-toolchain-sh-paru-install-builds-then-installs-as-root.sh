# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== dev_toolchain.sh (paru install builds then installs as root, never needs sudo; regression: reporte 2026-09-25) ==="
assert_pass "install_paru builds with makepkg -s (no -i) as the user" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  BUILD_CMD=''
  proot-distro() {
    case \"\$*\" in
      *'paru --version'*) return 1 ;;      # the skip-if-present gate: paru does not run
      *'command -v paru'*) return 1 ;;
      *'command -v makepkg'*) return 0 ;;
      *'--user'*'bash -c'*) BUILD_CMD=\"\${*: -1}\"; return 0 ;;
      *'bash -c'*) return 0 ;;  # the root install-as-pacman-U step
      *) return 0 ;;
    esac
  }
  phase4_install_paru
  ! grep -q -- '-si ' <<< \"\$BUILD_CMD\" && grep -q -- '-s --noconfirm' <<< \"\$BUILD_CMD\"
"
assert_pass "install_paru installs the built package as root via pacman -U, not sudo" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  ROOT_INSTALL_CMD=''
  proot-distro() {
    case \"\$*\" in
      *'paru --version'*) return 1 ;;      # the skip-if-present gate: paru does not run
      *'command -v paru'*) return 1 ;;
      *'command -v makepkg'*) return 0 ;;
      *'--user'*'bash -c'*) return 0 ;;  # build step, as the user
      *'bash -c'*) ROOT_INSTALL_CMD=\"\${*: -1}\"; return 0 ;;  # root install step
      *) return 0 ;;
    esac
  }
  phase4_install_paru
  grep -q 'pacman -U' <<< \"\$ROOT_INSTALL_CMD\" && ! grep -q sudo <<< \"\$ROOT_INSTALL_CMD\"
"
