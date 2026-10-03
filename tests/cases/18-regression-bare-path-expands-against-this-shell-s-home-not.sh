# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== regression: bare '~/path' expands against THIS shell's \$HOME, not the container user's ==="
# The actual bug hit in the wild: 'proot-distro login ... --user X -- tee
# ~/path' looks like it targets the container user's home, but tilde
# expansion happens in the CALLING (Termux-side) shell BEFORE
# proot-distro ever runs — so an unquoted ~/path silently resolves
# against THIS process's own $HOME, not the container's. Every function
# below is asserted with $HOME deliberately set to something that must
# NEVER appear in what reaches proot-distro; only sh -c '...ARGS WITH ~...'
# (protected by single quotes, expanded remotely instead) or an absolute
# /home/<user>/... path is safe.
export HOME="$TESTROOT/host_home_should_never_be_used"
mkdir -p "$HOME"

assert_pass "install_ohmyzsh's .zshrc-repair check never leaks the host \$HOME" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'; source '$SCRIPT_DIR/lib/network.sh'
  export HOME='$HOME'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'&&'*) return 1 ;;
      *'bash -c'*) return 0 ;;
      *'test -f'*) SEEN=\"\$*\"; return 1 ;;
      *) return 0 ;;
    esac
  }
  phase4_install_ohmyzsh 2>/dev/null
  ! grep -qF \"\$HOME\" <<< \"\$SEEN\" && grep -q '/home/kattze/.zshrc' <<< \"\$SEEN\"
"
assert_pass "set_zsh_theme's sed target never leaks the host \$HOME" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export HOME='$HOME'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'test -f'*) return 0 ;;
      *'sh -c'*) SEEN=\"\${*: -1}\"; return 0 ;;
      *) return 0 ;;
    esac
  }
  phase4_set_zsh_theme
  ! grep -qF \"\$HOME\" <<< \"\$SEEN\"
"
assert_pass "shell_ok's ZSH_THEME grep never leaks the host \$HOME" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export HOME='$HOME'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'getent passwd'*) echo 'kattze:x:1000:1000::/home/kattze:/usr/bin/zsh' ;;
      *'test -f'*) return 0 ;;
      *'sh -c'*) SEEN=\"\${*: -1}\"; return 0 ;;
      *) return 0 ;;
    esac
  }
  phase4_shell_ok
  ! grep -qF \"\$HOME\" <<< \"\$SEEN\"
"
assert_pass "clone_lazyvim_starter's cleanup rm never leaks the host \$HOME" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export HOME='$HOME'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'sh -c'*'[ -d'*) return 1 ;;             # not-clean check specifically
      *'sh -c'*) return 0 ;;                    # the (protected) cleanup rm -rf .git — not under test here
      *'rm -rf'*) SEEN=\"\$*\"; return 0 ;;       # the bare, direct rm -rf — this is what's under test
      *) return 0 ;;
    esac
  }
  phase4_clone_lazyvim_starter
  ! grep -qF \"\$HOME\" <<< \"\$SEEN\" && grep -q '/home/kattze/.config/nvim' <<< \"\$SEEN\"
"
assert_pass "write_plugin_overrides' tee targets never leak the host \$HOME" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export HOME='$HOME'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'tee'*) SEEN=\"\${SEEN} \$*\" ;;
    esac
    return 0
  }
  phase4_write_plugin_overrides < /dev/null
  ! grep -qF \"\$HOME\" <<< \"\$SEEN\" && grep -q '/home/kattze/.config/nvim/lua/plugins/lsp.lua' <<< \"\$SEEN\"
"
assert_pass "lazyvim_ok's options.lua check never leaks the host \$HOME" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export HOME='$HOME'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'test -f'*) SEEN=\"\$*\"; return 0 ;;
      *'io.stdout:write'*) echo 12 ;;
      *) return 0 ;;
    esac
  }
  phase4_lazyvim_ok
  ! grep -qF \"\$HOME\" <<< \"\$SEEN\" && grep -q '/home/kattze/.config/nvim/lua/config/options.lua' <<< \"\$SEEN\"
"
assert_pass "write_paru_conf's tee target never leaks the host \$HOME" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export HOME='$HOME'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'tee'*) SEEN=\"\$*\" ;;
    esac
    return 0
  }
  phase4_write_paru_conf < /dev/null
  ! grep -qF \"\$HOME\" <<< \"\$SEEN\" && grep -q '/home/kattze/.config/paru/paru.conf' <<< \"\$SEEN\"
"
unset HOME
export HOME="$TESTROOT/home"
