# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== regression: informe de auditoría 2026-09-29 (no tmux, mason-org, nerd font via pacman, telecom opt-in) ==="
# Mandatory design decision: tmux is not a dependency, never auto-attaches,
# and nothing written to .zshrc/.bashrc references it at all.
assert_pass "the generated .zshrc/.bashrc runtime blocks never mention tmux" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  CHOME='$TESTROOT/notmux_home'; mkdir -p \"\$CHOME\"
  proot-distro() {
    while [ \"\$#\" -gt 0 ]; do case \"\$1\" in --env) shift; export \"\$1\"; shift ;; --) shift; break ;; *) shift ;; esac; done
    HOME=\"\$CHOME\" \"\$@\"
  }
  phase4_write_zshrc_extras
  ! grep -qi tmux \"\$CHOME/.zshrc\" \"\$CHOME/.bashrc\"
"
assert_pass "zsh packages install never includes tmux" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/shell_setup.sh'
  SEEN=''
  proot-distro() { SEEN=\"\$*\"; return 0; }
  phase4_install_zsh_packages
  ! grep -qi tmux <<< \"\$SEEN\"
"
assert_pass "archkill never references tmux sessions" bash -c "
  grep -qi tmux '$SCRIPT_DIR/components/setup_launcher.sh' && exit 1
  exit 0
"
# mason.nvim/mason-lspconfig.nvim transferred williamboman -> mason-org
# (upstream, v2.0.0) — the old org still resolves via GitHub's repo
# transfer redirect today, but relying on that forever is fragile.
assert_pass "LazyVim LSP spec uses the current mason-org/* plugin paths" bash -c "
  grep -q 'mason-org/mason.nvim' '$SCRIPT_DIR/components/lazyvim.sh' &&
  grep -q 'mason-org/mason-lspconfig.nvim' '$SCRIPT_DIR/components/lazyvim.sh' &&
  ! grep -q 'williamboman' '$SCRIPT_DIR/components/lazyvim.sh'
"
# automatic_installation was removed in mason-lspconfig v2 — a config
# using it is silently ignored at best, a hard error at worst depending
# on version; automatic_enable is the real v2 option.
assert_pass "LazyVim LSP spec does not use the removed automatic_installation option" bash -c "
  ! grep -qE '^\s*automatic_installation\s*=' '$SCRIPT_DIR/components/lazyvim.sh' &&
  grep -qE '^\s*automatic_enable\s*=' '$SCRIPT_DIR/components/lazyvim.sh'
"
assert_pass "options.lua declares have_nerd_font and termguicolors" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'; source '$SCRIPT_DIR/lib/idempotent_append.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  CHOME='$TESTROOT/nf_home'; mkdir -p \"\$CHOME\"
  proot-distro() {
    while [ \"\$#\" -gt 0 ]; do case \"\$1\" in --env) shift; export \"\$1\"; shift ;; --) shift; break ;; *) shift ;; esac; done
    HOME=\"\$CHOME\" \"\$@\"
  }
  phase4_write_options_overrides
  grep -q 'have_nerd_font = true' \"\$CHOME/.config/nvim/lua/config/options.lua\" &&
  grep -q 'termguicolors = true' \"\$CHOME/.config/nvim/lua/config/options.lua\"
"
# Nerd Font: pacman package first (official, 'any' arch, ~10.5MB),
# zip-download fallback only if that fails — not the other way around.
assert_pass "nerdfonts_run tries the pacman package before the zip fallback" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/network.sh'
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/nerdfonts.sh'
  ZIP_TRIED=0
  phase4_install_nerdfont_pkg() { return 0; }
  phase4_ensure_unzip() { ZIP_TRIED=1; return 1; }
  phase4_nerdfonts_run >/dev/null 2>&1 || true
  [ \"\$ZIP_TRIED\" = 0 ]
"
assert_pass "nerdfonts_run falls back to the zip when the pacman package path fails" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/network.sh'
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/nerdfonts.sh'
  ZIP_TRIED=0
  phase4_install_nerdfont_pkg() { return 1; }
  phase4_ensure_unzip() { ZIP_TRIED=1; return 1; }
  phase4_nerdfonts_run >/dev/null 2>&1 || true
  [ \"\$ZIP_TRIED\" = 1 ]
"
assert_pass "nerdfont_ok rejects a tiny/truncated font file, not just its existence" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  export HOME='$TESTROOT/font_home'; mkdir -p \"\$HOME/.termux\"
  source '$SCRIPT_DIR/lib/verify_functional.sh'
  printf 'x' > \"\$HOME/.termux/font.ttf\"
  ! phase5_nerdfont_ok
"
# Telecom is opt-in (TDE_WITH_TELECOM=1) — core.sh must not even source
# telecom.sh, let alone run it, without that flag.
assert_pass "core.sh never calls phase4_telecom_run unless TDE_WITH_TELECOM is checked first" bash -c "
  grep -n 'phase4_telecom_run' '$SCRIPT_DIR/core.sh' | while read -r line; do
    n=\"\${line%%:*}\"
    sed -n \"\$((n-8)),\${n}p\" '$SCRIPT_DIR/core.sh' | grep -q 'TDE_WITH_TELECOM' || exit 1
  done
"
assert_pass "self_heal does not retry telecom unless TDE_WITH_TELECOM=1" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/lib/verify_functional.sh'
  phase5_nerdfont_ok() { return 0; }
  phase5_rns_ok() { return 1; }
  phase5_aria2_ok() { return 1; }
  phase4_telecom_run() { echo 'SHOULD NOT RUN' >&2; return 1; }
  unset TDE_WITH_TELECOM
  phase5_self_heal
"
# Storage permission: warns, never blocks — nothing in the real install
# flow reads/writes ~/storage/shared (see lib/validate_env.sh's comment).
assert_pass "missing storage permission warns but does not FATAL the install" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  export HOME='$TESTROOT/nostorage_home'; mkdir -p \"\$HOME\"
  source '$SCRIPT_DIR/lib/validate_env.sh'
  phase1_check_storage_permission
"
# paru: a prebuilt paru-bin that doesn't actually run (libalpm mismatch)
# triggers a source rebuild instead of silently leaving a broken binary.
assert_pass "a non-functional paru-bin triggers a source rebuild (paru, not paru-bin)" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  REBUILT=0
  proot-distro() {
    case \"\$*\" in
      *'command -v paru'*) return 1 ;;
      *'command -v makepkg'*) return 0 ;;
      *'paru --version'*) return 1 ;;
      *'aur.archlinux.org/paru.git'*) return 0 ;;
      *'--user'*'bash -c'*'/tmp/paru'*) REBUILT=1; return 0 ;;
      *'--user'*'bash -c'*) return 0 ;;
      *'bash -c'*) return 0 ;;
      *) return 0 ;;
    esac
  }
  phase4_install_paru
  [ \"\$REBUILT\" = 1 ]
"
