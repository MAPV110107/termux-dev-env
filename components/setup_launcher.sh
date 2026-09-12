# Phase 3, step 3 — launcher setup. Sets up zsh+oh-my-zsh in TERMUX ITSELF
# first (order matters: oh-my-zsh's installer overwrites .zshrc, so it must
# run before anything appends to it), then writes the launcher config and
# appends the launcher snippet idempotently to both .bashrc and .zshrc,
# and installs archkill as a real $PREFIX/bin script.

[ -n "${TDE_SETUP_LAUNCHER_LOADED:-}" ] && return 0
TDE_SETUP_LAUNCHER_LOADED=1

TDE_LAUNCHER_CONFIG="$HOME/.config/termux-dev-env/config.env"
TDE_BASHRC="$HOME/.bashrc"
TDE_ZSHRC="$HOME/.zshrc"
TDE_OHMYZSH_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

phase3_install_termux_zsh_packages() {
  log_info "Installing zsh in Termux"
  retry_with_backoff 3 5 pkg install -y zsh || log_fatal "Could not install zsh in Termux"
}

phase3_install_termux_ohmyzsh() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    log_info "oh-my-zsh already installed in Termux, skipping"
    return 0
  fi
  local install_script
  install_script="$(retry_with_backoff 3 5 curl -fsSL "$TDE_OHMYZSH_INSTALL_URL")" || \
    log_fatal "Could not download the oh-my-zsh installer for Termux"
  [ -n "$install_script" ] || log_fatal "oh-my-zsh installer download for Termux returned empty content"
  RUNZSH=no CHSH=no KEEP_ZSHRC=no sh -c "$install_script" || \
    log_fatal "oh-my-zsh install failed in Termux"
}

phase3_install_termux_autosuggestions() {
  local plugin_dir="$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  if [ -d "$plugin_dir" ]; then
    log_info "zsh-autosuggestions already present in Termux"
    return 0
  fi
  git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$plugin_dir" || \
    log_warn "Could not install zsh-autosuggestions in Termux"
}

# agnoster is bundled with oh-my-zsh itself — no extra download needed,
# just pointing ZSH_THEME at it. It renders correctly because phase 4
# already installs a Nerd Font (Mono variant) for the powerline glyphs.
phase3_configure_termux_zshrc() {
  grep -q "zsh-autosuggestions" "$TDE_ZSHRC" 2>/dev/null || \
    sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions)/' "$TDE_ZSHRC"
  sed -i 's/^ZSH_THEME=.*/ZSH_THEME="agnoster"/' "$TDE_ZSHRC"
}

# chsh needs the FULL path in Termux ("chsh -s zsh" fails with "not an
# executable file"). Non-fatal: the .bashrc copy of the launcher snippet
# already covers the case where chsh doesn't take effect on some device.
phase3_set_termux_default_shell() {
  chsh -s "$PREFIX/bin/zsh" < /dev/null 2>/dev/null || \
    log_warn "Could not set zsh as Termux's default shell via chsh — the .bashrc fallback still enters Arch automatically"
}

phase3_write_launcher_config() {
  local username
  username="$(state_get ARCH_USERNAME)"
  kv_set "$TDE_LAUNCHER_CONFIG" ARCH_USERNAME "$username"
  kv_set "$TDE_LAUNCHER_CONFIG" ARCH_DISTRO_ALIAS "$TDE_DISTRO_NAME"
  kv_set "$TDE_LAUNCHER_CONFIG" TDE_ROOT "$TDE_ROOT"
}

# Idempotent: safe to re-run without duplicating the block. Written to
# both rc files — Termux's actual default shell may be bash on some
# devices even after chsh, zsh only lives inside the Arch container
# unconditionally, never assumed for Termux itself.
phase3_install_zshrc_snippet() {
  local content
  content="$(cat << EOF
# Escape hatch: TDE_SKIP_LAUNCHER=1 zsh   (or export it before opening Termux)
if [ -f "$TDE_LAUNCHER_CONFIG" ] && [ -z "\${PROOT_ACTIVE:-}" ] && [ -z "\${TDE_SKIP_LAUNCHER:-}" ]; then
  . "$TDE_LAUNCHER_CONFIG"
  proot-distro login "\$ARCH_DISTRO_ALIAS" --user "\$ARCH_USERNAME" --isolated
fi
EOF
)"
  idempotent_append "$TDE_BASHRC" "launcher" "$content"
  idempotent_append "$TDE_ZSHRC" "launcher" "$content"
}

phase3_install_archkill() {
  local target="$PREFIX/bin/archkill"
  cat > "$target" << EOF
#!$PREFIX/bin/bash
# Force-closes the Arch container without saving unsaved work.
[ -f "$TDE_LAUNCHER_CONFIG" ] && . "$TDE_LAUNCHER_CONFIG"
echo "Active tmux sessions inside Arch (these will be lost):"
proot-distro login "$TDE_DISTRO_NAME" --user "\${ARCH_USERNAME:-user}" -- tmux list-sessions 2>/dev/null || echo "  (none found)"
echo "This will close Arch without saving unsaved sessions. Continue? [y/N]"
read -r confirm
[ "\$confirm" = "y" ] || exit 0
proot-distro login "$TDE_DISTRO_NAME" --user "\${ARCH_USERNAME:-user}" -- tmux kill-server 2>/dev/null
proot-distro kill "$TDE_DISTRO_NAME"
echo "Arch closed."
EOF
  chmod +x "$target"
}

phase3_setup_launcher_run() {
  log_info "=== Phase 3, step 3: launcher setup ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would install zsh+oh-my-zsh+agnoster+autosuggestions in Termux, set it as default shell, write launcher config, append idempotent snippet to .bashrc and .zshrc, install archkill to \$PREFIX/bin"
    return 0
  fi

  phase3_install_termux_zsh_packages
  phase3_install_termux_ohmyzsh
  phase3_install_termux_autosuggestions
  phase3_configure_termux_zshrc
  phase3_set_termux_default_shell

  phase3_write_launcher_config
  phase3_install_zshrc_snippet
  phase3_install_archkill
  log_info "Launcher installed — a new Termux session logs into Arch automatically. Escape hatch: TDE_SKIP_LAUNCHER=1"
}

# Post-condition, checked by core.sh before marking PHASE3_LAUNCHER_SETUP.
phase3_launcher_ok() {
  [ -f "$TDE_LAUNCHER_CONFIG" ] && \
    grep -q "^ARCH_USERNAME=" "$TDE_LAUNCHER_CONFIG" && \
    grep -qF -- "termux-dev-env: launcher" "$TDE_BASHRC" 2>/dev/null && \
    grep -qF -- "termux-dev-env: launcher" "$TDE_ZSHRC" 2>/dev/null && \
    [ -x "$PREFIX/bin/archkill" ] && \
    [ -d "$HOME/.oh-my-zsh" ] && \
    grep -q 'ZSH_THEME="agnoster"' "$TDE_ZSHRC" 2>/dev/null
}
