# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== shell_setup.sh (regression: reporte 2026-09-25, host-side .zshrc checks disagreed with what proot actually wrote) ==="
# The bug: oh-my-zsh's own installer reported "adding it to
# /home/<user>/.zshrc" and exited successfully, yet a direct host-side
# `[ -f "$(container_home ...)/.zshrc" ]` right after still read the
# file as missing — so a previous fix that only made the check "safe"
# (warn instead of crash) still left the underlying disagreement, and
# every later step kept treating a real .zshrc as absent. All the
# checks below now go through the same access path as the write
# (proot-distro login --user), not a host-side path into the rootfs.
assert_pass "install_ohmyzsh re-runs (does not skip) when .oh-my-zsh exists but .zshrc doesn't, checked container-side" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'; source '$SCRIPT_DIR/lib/network.sh'
  export TDE_STATE_FILE='$TESTROOT/ohmyzsh_state.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  INSTALLER_RAN=0
  proot-distro() {
    case \"\$*\" in
      *'&&'*'.zshrc'*) return 1 ;;              # combined [-d .oh-my-zsh] && [-f .zshrc] check: not both present
      *'test -d'*'.oh-my-zsh'*) return 0 ;;     # dir-only check: exists
      *'bash -c'*) INSTALLER_RAN=1; return 0 ;; # the actual (re-)install run
      *'test -f'*'.zshrc'*) return 0 ;;         # post-install check: now exists, no fallback needed
      *) return 0 ;;
    esac
  }
  phase4_install_ohmyzsh
  [ \"\$INSTALLER_RAN\" = 1 ]
"
assert_pass "enable_autosuggestions_plugin warns and skips instead of erroring on a missing .zshrc, checked container-side" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ohmyzsh_state2.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  proot-distro() { case \"\$*\" in *'test -f'*'.zshrc'*) return 1 ;; *) echo 'SHOULD NOT RUN sed' >&2; return 1 ;; esac; }
  phase4_enable_autosuggestions_plugin
"
assert_pass "set_zsh_theme warns and skips instead of erroring on a missing .zshrc, checked container-side" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ohmyzsh_state3.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  proot-distro() { case \"\$*\" in *'test -f'*'.zshrc'*) return 1 ;; *) echo 'SHOULD NOT RUN sed' >&2; return 1 ;; esac; }
  phase4_set_zsh_theme
"
assert_pass "enable_autosuggestions_plugin and set_zsh_theme actually edit .zshrc container-side when it exists" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ohmyzsh_state5.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  SED_RAN=0
  proot-distro() {
    case \"\$*\" in
      *'test -f'*'.zshrc'*) return 0 ;;
      *'sh -c'*) SED_RAN=1; return 0 ;;
      *'sed -i'*) SED_RAN=1; return 0 ;;
      *) return 0 ;;
    esac
  }
  phase4_enable_autosuggestions_plugin
  phase4_set_zsh_theme
  [ \"\$SED_RAN\" = 1 ]
"
assert_fail "shell_ok reports which sub-check failed instead of a bare failure" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ohmyzsh_state4.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  proot-distro() { case \"\$*\" in *'getent passwd'*) echo 'kattze:x:1000:1000::/home/kattze:/bin/bash' ;; *) return 0 ;; esac; }
  out=\"\$(phase4_shell_ok 2>&1 || true)\"
  grep -q 'not /usr/bin/zsh' <<< \"\$out\"
  phase4_shell_ok
"
