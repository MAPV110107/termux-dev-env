# Phase 4 — shell setup, INSIDE the container. Order matters: oh-my-zsh's
# installer overwrites .zshrc with its own template, so our PROOT_ACTIVE +
# tmux snippet must be appended AFTER it installs, never before.

[ -n "${TDE_SHELL_SETUP_LOADED:-}" ] && return 0
TDE_SHELL_SETUP_LOADED=1

TDE_OHMYZSH_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

phase4_install_zsh_packages() {
  log_info "Installing zsh and tmux"
  proot-distro login "$TDE_DISTRO_NAME" -- pacman -S --noconfirm --needed zsh tmux || \
    log_fatal "Could not install zsh/tmux"
}

phase4_install_ohmyzsh() {
  local username home_dir
  username="$(state_get ARCH_USERNAME)"
  home_dir="$(container_home "$username")"

  if [ -d "$home_dir/.oh-my-zsh" ]; then
    log_info "oh-my-zsh already installed, skipping"
    return 0
  fi

  retry_with_backoff 3 5 proot-distro login "$TDE_DISTRO_NAME" --user "$username" \
    --env OHMYZSH_URL="$TDE_OHMYZSH_INSTALL_URL" -- bash -c '
    set -e
    install_script="$(curl -fsSL "$OHMYZSH_URL")"
    [ -n "$install_script" ]
    RUNZSH=no CHSH=no KEEP_ZSHRC=no sh -c "$install_script"
  ' || log_fatal "oh-my-zsh install failed"
}

phase4_install_zsh_autosuggestions() {
  local username plugin_dir
  username="$(state_get ARCH_USERNAME)"
  plugin_dir="$(container_home "$username")/.oh-my-zsh/custom/plugins/zsh-autosuggestions"

  if [ -d "$plugin_dir" ]; then
    log_info "zsh-autosuggestions already present"
    return 0
  fi

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions \
    "/home/$username/.oh-my-zsh/custom/plugins/zsh-autosuggestions" || \
    log_warn "Could not install zsh-autosuggestions — shell works, just without suggestions"
}

phase4_enable_autosuggestions_plugin() {
  local username zshrc
  username="$(state_get ARCH_USERNAME)"
  zshrc="$(container_home "$username")/.zshrc"
  grep -q "zsh-autosuggestions" "$zshrc" 2>/dev/null && return 0
  sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions)/' "$zshrc"
}

# agnoster ships with oh-my-zsh itself, no extra download — matches the
# theme now set for Termux's own shell too, for a consistent look on both
# sides of the launcher.
phase4_set_zsh_theme() {
  local username zshrc
  username="$(state_get ARCH_USERNAME)"
  zshrc="$(container_home "$username")/.zshrc"
  sed -i 's/^ZSH_THEME=.*/ZSH_THEME="agnoster"/' "$zshrc"
}

phase4_set_default_shell() {
  local username
  username="$(state_get ARCH_USERNAME)"
  proot-distro login "$TDE_DISTRO_NAME" -- usermod -s /usr/bin/zsh "$username" || \
    log_warn "Could not set zsh as default shell — the launcher will still work, just drops into bash first"
}

phase4_write_zshrc_extras() {
  local username zshrc
  username="$(state_get ARCH_USERNAME)"
  zshrc="$(container_home "$username")/.zshrc"

  idempotent_append "$zshrc" "runtime" '
export PROOT_ACTIVE=1
if command -v tmux >/dev/null 2>&1 && [ -z "$TMUX" ]; then
  tmux attach -t main 2>/dev/null || tmux new -s main
fi'
}

phase4_shell_setup_run() {
  log_info "=== Phase 4: shell setup (zsh + oh-my-zsh) ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would install zsh+tmux, oh-my-zsh, zsh-autosuggestions, agnoster theme, set zsh as default shell, append PROOT_ACTIVE + tmux auto-attach"
    return 0
  fi

  phase4_install_zsh_packages
  phase4_install_ohmyzsh
  phase4_install_zsh_autosuggestions
  phase4_enable_autosuggestions_plugin
  phase4_set_zsh_theme
  phase4_set_default_shell
  phase4_write_zshrc_extras
  log_info "Shell configured"
}

# Post-condition, checked by core.sh before marking PHASE4_SHELL.
phase4_shell_ok() {
  local username shell zshrc
  username="$(state_get ARCH_USERNAME)"
  zshrc="$(container_home "$username")/.zshrc"
  shell="$(proot-distro login "$TDE_DISTRO_NAME" -- getent passwd "$username" 2>/dev/null | cut -d: -f7)"
  [ "$shell" = "/usr/bin/zsh" ] || return 1
  grep -q 'ZSH_THEME="agnoster"' "$zshrc" 2>/dev/null
}
