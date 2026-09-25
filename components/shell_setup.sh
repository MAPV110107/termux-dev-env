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

  # Checking only .oh-my-zsh/ used to be enough to skip re-running — but
  # if a previous attempt got interrupted (network drop mid-clone) after
  # creating that directory but before the installer reached its final
  # "copy the .zshrc template" step, every future run would see the
  # directory, skip entirely, and leave .zshrc permanently missing. Both
  # must exist for this to count as done.
  if [ -d "$home_dir/.oh-my-zsh" ] && [ -f "$home_dir/.zshrc" ]; then
    log_info "oh-my-zsh already installed, skipping"
    return 0
  fi
  if [ -d "$home_dir/.oh-my-zsh" ] && [ ! -f "$home_dir/.zshrc" ]; then
    log_warn ".oh-my-zsh exists but .zshrc is missing (interrupted previous install) — re-running the installer to repair it"
  fi

  retry_with_backoff 3 5 proot-distro login "$TDE_DISTRO_NAME" --user "$username" \
    --env OHMYZSH_URL="$TDE_OHMYZSH_INSTALL_URL" -- bash -c '
    set -e
    install_script="$(curl -fsSL "$OHMYZSH_URL")"
    [ -n "$install_script" ]
    RUNZSH=no CHSH=no KEEP_ZSHRC=no sh -c "$install_script"
  ' || log_fatal "oh-my-zsh install failed"

  # Belt and suspenders: the upstream installer has historically had edge
  # cases where it exits 0 without actually placing .zshrc (a bad $HOME,
  # a template-copy step that silently no-ops). Every later step in this
  # phase (theme, plugin, the PROOT_ACTIVE/tmux snippet) assumes .zshrc
  # exists, so make sure of it right here instead of letting a "sed: No
  # such file" surface three functions later with no context.
  if [ ! -f "$home_dir/.zshrc" ]; then
    log_warn ".zshrc still missing after oh-my-zsh install reported success — writing a minimal fallback so the rest of Phase 4 has something to work with"
    proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- sh -c \
      'cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc 2>/dev/null || printf "export ZSH=\"\$HOME/.oh-my-zsh\"\nZSH_THEME=\"robbyrussell\"\nplugins=(git)\nsource \$ZSH/oh-my-zsh.sh\n" > ~/.zshrc' || \
      log_fatal "Could not create .zshrc even as a fallback — oh-my-zsh install is unrecoverable, check $TDE_LOG_FILE"
  fi
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
  # phase4_install_ohmyzsh guarantees .zshrc exists by the time this runs
  # (repairing it if the upstream installer didn't), but this stays
  # defensive rather than assuming that always holds — a noisy
  # "sed: can't read ... No such file" with no context is worse than a
  # clear warning naming exactly what's missing and why this step is
  # being skipped.
  if [ ! -f "$zshrc" ]; then
    log_warn "$zshrc missing — skipping zsh-autosuggestions plugin enable (shell will still work, just without suggestions)"
    return 0
  fi
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
  if [ ! -f "$zshrc" ]; then
    log_warn "$zshrc missing — skipping theme set (shell will still work, just with oh-my-zsh's default theme)"
    return 0
  fi
  sed -i 's/^ZSH_THEME=.*/ZSH_THEME="agnoster"/' "$zshrc"
}

phase4_set_default_shell() {
  local username
  username="$(state_get ARCH_USERNAME)"
  proot-distro login "$TDE_DISTRO_NAME" -- usermod -s /usr/bin/zsh "$username" || \
    log_warn "Could not set zsh as default shell — the launcher will still work, just drops into bash first"
}

phase4_write_zshrc_extras() {
  local username zshrc bashrc
  username="$(state_get ARCH_USERNAME)"
  zshrc="$(container_home "$username")/.zshrc"
  bashrc="$(container_home "$username")/.bashrc"

  # tmux only auto-attaches for a genuinely interactive login (zsh's own
  # "interactive" option, which is off for any "-c command" invocation
  # regardless of whether a TTY happens to be attached to that process —
  # e.g. proot-distro login --user <name> -- <cmd>, which every phase 4-6
  # postcondition and setup step after this point uses to run things
  # inside the container as this user). Without this guard tmux would try
  # to take over the terminal on every one of those calls too, not just a
  # real interactive session from setup_launcher.sh, and hang scripted
  # steps that have no TTY loop to break out of it.
  idempotent_append "$zshrc" "runtime" '
export PROOT_ACTIVE=1
export PATH="$HOME/.local/bin:$PATH"
if [[ -o interactive ]] && [ -t 0 ] && command -v tmux >/dev/null 2>&1 && [ -z "$TMUX" ]; then
  tmux attach -t main 2>/dev/null || tmux new -s main
fi'

  idempotent_append "$bashrc" "runtime" '
if [ -z "$PROOT_ACTIVE" ] && [ -x /usr/bin/zsh ]; then
  export PROOT_ACTIVE=1
  exec /usr/bin/zsh
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
  local username shell zshrc ok=1
  username="$(state_get ARCH_USERNAME)"
  [ -n "$username" ] || { log_warn "post-check: no ARCH_USERNAME in state"; return 1; }
  zshrc="$(container_home "$username")/.zshrc"

  shell="$(proot-distro login "$TDE_DISTRO_NAME" -- getent passwd "$username" 2>/dev/null | cut -d: -f7)"
  if [ "$shell" != "/usr/bin/zsh" ]; then
    log_warn "post-check: '$username's login shell is '${shell:-unknown}', not /usr/bin/zsh"
    ok=0
  fi
  if [ ! -f "$zshrc" ]; then
    log_warn "post-check: $zshrc does not exist"
    ok=0
  elif ! grep -q 'ZSH_THEME="agnoster"' "$zshrc" 2>/dev/null; then
    log_warn "post-check: ZSH_THEME=\"agnoster\" missing from $zshrc"
    ok=0
  fi

  [ "$ok" = "1" ]
}
