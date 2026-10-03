# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== dev_toolchain.sh (makepkg guard before paru install; regression: Grok analysis 2026-09-24, marksman/paru hard-fail) ==="
assert_fail "install_paru fails (non-fatal) when makepkg is missing" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  proot-distro() {
    case \"\$*\" in
      *'paru --version'*) return 1 ;;
      *'command -v paru'*) return 1 ;;
      *'command -v makepkg'*) return 1 ;;
      *) return 0 ;;
    esac
  }
  phase4_install_paru
"
# The bug from the report: phase4_install_paru used to call log_fatal
# directly on a failed makepkg/git-clone, and was invoked as a bare
# top-level statement — under this project's set -euo pipefail, that
# combination takes the whole installer down over a missing AUR helper,
# even though paru was never required by anything else in the toolchain.
assert_pass "dev_toolchain_run does not abort the whole phase when paru install fails" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/network.sh'; source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  proot-distro() {
    case \"\$*\" in
      *'command -v paru'*) return 1 ;;
      *'command -v makepkg'*) return 0 ;;
      *'bash -c'*) return 1 ;;  # simulates a failed git clone / makepkg -si
      *) return 0 ;;
    esac
  }
  phase4_sync_and_install_toolchain() { :; }
  phase4_prompt_git_identity() { :; }
  phase4_write_paru_conf() { :; }
  phase4_dev_toolchain_run
"
# marksman is upstream-Arch's own x86_64-specific package (not "any"),
# with no confirmed aarch64 build — a hard 'pacman -S ... marksman' turns
# a missing-on-this-arch package into a FATAL that kills the whole
# toolchain phase. Mason.nvim's own ensure_installed already gets it.
assert_pass "marksman is not a hard pacman dependency (Mason.nvim installs it instead)" bash -c "
  ! grep -q 'marksman' <<< \"\$(grep 'pacman -S' '$SCRIPT_DIR/components/dev_toolchain.sh')\"
"
# paru is genuinely optional — the toolchain post-check must not fail
# the entire phase over an AUR helper nothing else in the pipeline needs.
assert_pass "phase4_toolchain_ok passes on gcc+git alone, without requiring paru" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  export TDE_STATE_FILE='$TESTROOT/toolchain_ok_state.env'
  state_set ARCH_USERNAME devuser >/dev/null
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  proot-distro() {
    case \"\$*\" in
      *'command -v gcc'*) return 0 ;;
      *'command -v git'*) return 0 ;;
      *'command -v paru'*) return 1 ;;
      *) return 0 ;;
    esac
  }
  phase4_toolchain_ok
"
