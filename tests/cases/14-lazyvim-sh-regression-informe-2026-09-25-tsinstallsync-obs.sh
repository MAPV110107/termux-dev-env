# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== lazyvim.sh (regression: informe 2026-09-25, TSInstallSync obsolete / host-side checks) ==="
# TSInstallSync belonged to nvim-treesitter's frozen 'master' branch;
# LazyVim's starter pins 'main', which removed it entirely
# ("E492: Not an editor command: TSInstallSync") — confirmed against
# nvim-treesitter/LazyVim's own current docs. Locks in the modern Lua
# API is what's actually sent to nvim, not the old ex-command.
assert_pass "install_treesitter_parsers writes a Lua script using main's API (no TSInstallSync) and runs it via luafile" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ts_state.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  LUA_F='$TESTROOT/ts_lua_seen'; NVIM_F='$TESTROOT/ts_nvim_seen'
  : > \"\$LUA_F\"; : > \"\$NVIM_F\"
  # proot-distro runs inside a 'out=\$(...)' command substitution in the
  # real code — plain variable assignments there don't survive back to
  # the caller, so capture into files instead.
  proot-distro() {
    case \"\$*\" in
      *'nvim --headless'*) echo \"\$*\" >> \"\$NVIM_F\"; echo 'TS_MISSING=' ;;
      *tee*) cat > \"\$LUA_F\" ;;
    esac
    return 0
  }
  phase4_install_treesitter_parsers >/dev/null 2>&1
  ! grep -q 'TSInstallSync' \"\$LUA_F\" \"\$NVIM_F\" &&
  grep -q \"require('nvim-treesitter')\" \"\$LUA_F\" && grep -q 'ts.install(' \"\$LUA_F\" &&
  grep -q 'luafile /home/kattze/.cache/tde/ts_install.lua' \"\$NVIM_F\"
"
# Regression for the race seen on a real device: LazyVim's own startup
# ensure_installed and our pre-install both built the same parsers at
# once ("multiple processes building to the same output location").
assert_pass "every installer-driven nvim run disables LazyVim's own parser auto-install" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ts_state2.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  SEEN_F='$TESTROOT/ts_ensure_seen'; : > \"\$SEEN_F\"
  proot-distro() { case \"\$*\" in *'nvim --headless'*) echo \"\$*\" >> \"\$SEEN_F\" ;; esac; return 0; }
  phase4_sync_plugins; _tde_lazy_loaded >/dev/null
  [ \"\$(grep -c 'TDE_SKIP_TS_ENSURE=1' \"\$SEEN_F\")\" -ge 2 ]
"
assert_pass "the LazyVim override empties ensure_installed only when TDE_SKIP_TS_ENSURE=1" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ts_state3.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  ALL=''
  proot-distro() { case \"\$*\" in *tee*treesitter.lua*) ALL=\"\$(cat)\" ;; *tee*) cat >/dev/null ;; esac; return 0; }
  phase4_write_plugin_overrides
  grep -q 'TDE_SKIP_TS_ENSURE' <<< \"\$ALL\" && grep -q 'ensure_installed = {}' <<< \"\$ALL\" && grep -q 'nvim-treesitter/nvim-treesitter' <<< \"\$ALL\"
"
assert_pass "parsers are reported missing (warn, not fatal) and never abort the phase" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ts_state4.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  proot-distro() { case \"\$*\" in *'nvim --headless'*) echo 'TS_MISSING=vim,go' ;; *tee*) cat >/dev/null ;; esac; return 0; }
  out=\"\$(phase4_install_treesitter_parsers 2>&1)\"
  grep -q 'still missing after a retry: vim,go' <<< \"\$out\"
"
# The E403 root cause: headless nvim's print() goes to stderr, so a check
# reading stdout with 2>/dev/null could never see the plugin count.
assert_pass "lazy count is read from stdout (works even when stderr is discarded)" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ts_state5.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  # stderr carries noise (parser progress with no trailing newline); stdout carries only the number
  proot-distro() { case \"\$*\" in *'io.stdout:write'*) printf 'Language installed' >&2; echo 6 ;; esac; return 0; }
  [ \"\$(_tde_lazy_loaded)\" = 6 ]
"
assert_pass "lazy count falls back to stderr print() when stdout gives nothing" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ts_state6.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  proot-distro() { case \"\$*\" in *'lua print'*) echo 4 >&2 ;; esac; return 0; }
  [ \"\$(_tde_lazy_loaded)\" = 4 ]
"
assert_fail "lazyvim_ok fails, saying why, when no plugin count can be read" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ts_state7.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  proot-distro() { return 0; }
  out=\"\$(phase4_lazyvim_ok 2>&1 || true)\"
  grep -q 'could not read a plugin count' <<< \"\$out\"
  phase4_lazyvim_ok
"
# checkhealth's own wording is nvim-treesitter's UI copy, free to change
# across versions (and did, moving 'master' -> 'main') — this checks
# for the compiler directly instead of grepping that text.
assert_pass "verify_treesitter_cc checks for gcc/cc directly, not checkhealth text" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  proot-distro() { case \"\$*\" in *'command -v gcc'*) return 0 ;; *) return 1 ;; esac; }
  phase4_verify_treesitter_cc
"
# The bug: the old idempotency check for the LazyVim starter clone was a
# host-side path via container_home — a false negative there (the same
# class of bug as .zshrc) fell through to 'rm -rf' the whole nvim config
# and re-clone from scratch, which would silently destroy a user's own
# customizations on every single run. Confirms the check and the
# destructive rm both now go through the container, not a host path.
assert_pass "clone_lazyvim_starter skips (no destructive rm, no re-clone) when already present and clean" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  proot-distro() {
    case \"\$*\" in
      *'sh -c'*) return 0 ;;  # combined [-d nvim] && [!-d .git] && [!-f example.lua] check: clean
      *'rm -rf'*) echo 'SHOULD NOT DELETE' >&2; return 1 ;;
      *'git clone'*) echo 'SHOULD NOT RE-CLONE' >&2; return 1 ;;
      *) return 0 ;;
    esac
  }
  phase4_clone_lazyvim_starter
"
assert_pass "lazyvim_ok checks options.lua container-side, not a host-side container_home path" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  proot-distro() {
    case \"\$*\" in
      *'test -f'*'options.lua'*) return 0 ;;
      *'io.stdout:write'*) echo 12 ;;
      *'command -v nvim'*) return 0 ;;
      *) return 0 ;;
    esac
  }
  phase4_lazyvim_ok
"
assert_fail "lazyvim_ok still fails when options.lua is missing container-side" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  proot-distro() { case \"\$*\" in *'test -f'*'options.lua'*) return 1 ;; *) return 0 ;; esac; }
  phase4_lazyvim_ok
"
assert_pass "write_options_overrides uses idempotent_append_container, not a host-side path" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'; source '$SCRIPT_DIR/lib/idempotent_append.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  LOGGED_IN=0
  proot-distro() { LOGGED_IN=1; return 0; }
  phase4_write_options_overrides
  [ \"\$LOGGED_IN\" = 1 ]
"
