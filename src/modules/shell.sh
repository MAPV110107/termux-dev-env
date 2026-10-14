# Phase 4, step 3 — Container UTF-8 locale generation and Zsh + Oh My Zsh setup.
# Ensures UTF-8 is active across both login and non-interactive shells so
# Nerd Font glyphs, agnoster powerline arrows, and fastfetch render cleanly.

[ -n "${TDE_MODULE_SHELL_LOADED:-}" ] && return 0
TDE_MODULE_SHELL_LOADED=1

TDE_OHMYZSH_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

phase4_configure_locale() {
  log_info "Generating en_US.UTF-8 locale inside $TDE_DISTRO_NAME"
  proot-distro login "$TDE_DISTRO_NAME" -- sh -c '
    grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen 2>/dev/null || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    printf "LANG=en_US.UTF-8\nLC_ALL=en_US.UTF-8\n" > /etc/locale.conf
    mkdir -p /etc/profile.d
    cat > /etc/profile.d/tde-locale.sh << "EOF"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
EOF
    chmod +x /etc/profile.d/tde-locale.sh
  ' >>"$TDE_LOG_FILE" 2>&1 || log_warn "locale-gen reported a warning — verifying output"

  if proot-distro login "$TDE_DISTRO_NAME" -- sh -c 'locale -a 2>/dev/null | tr "[:upper:]" "[:lower:]" | tr -d "-" | grep -q "^en_us.utf8$"'; then
    log_info "Locale en_US.UTF-8 verified active"
  else
    log_warn "en_US.UTF-8 locale could not be verified — UTF-8 glyphs may degrade until 'locale-gen' succeeds"
  fi
}

phase4_install_ohmyzsh_and_plugins() {
  local username
  username="$(state_get ARCH_USERNAME)"

  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
       sh -c '[ -d ~/.oh-my-zsh ] && [ -f ~/.zshrc ]' 2>/dev/null; then
    retry_with_backoff 3 5 proot-distro login "$TDE_DISTRO_NAME" --user "$username" \
      --env OHMYZSH_URL="$TDE_OHMYZSH_INSTALL_URL" -- bash -c '
      set -e
      install_script="$(curl -fsSL "$OHMYZSH_URL")"
      [ -n "$install_script" ]
      RUNZSH=no CHSH=no KEEP_ZSHRC=no sh -c "$install_script"
    ' || log_fatal_code 421 "oh-my-zsh installation failed"
  fi

  # Batched .zshrc verification, autosuggestions clone, theme setup, and default shell assignment
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- sh -c '
    set -e
    if [ ! -f ~/.zshrc ]; then
      cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc 2>/dev/null || \
        printf "export ZSH=\"\$HOME/.oh-my-zsh\"\nZSH_THEME=\"agnoster\"\nplugins=(git)\nsource \$ZSH/oh-my-zsh.sh\n" > ~/.zshrc
    fi
    if [ ! -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]; then
      git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions \
        ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions 2>/dev/null || true
    fi
    grep -q "zsh-autosuggestions" ~/.zshrc || \
      sed -i "s/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions)/" ~/.zshrc
    if grep -q "^ZSH_THEME=" ~/.zshrc; then
      sed -i "s/^ZSH_THEME=.*/ZSH_THEME=\"agnoster\"/" ~/.zshrc
    else
      echo "ZSH_THEME=\"agnoster\"" >> ~/.zshrc
    fi
    grep -q "oh-my-zsh\.sh" ~/.zshrc || echo "source \$ZSH/oh-my-zsh.sh" >> ~/.zshrc
  ' || log_fatal_code 422 "Could not configure .zshrc inside container"

  proot-distro login "$TDE_DISTRO_NAME" -- usermod -s /usr/bin/zsh "$username" || \
    log_warn "Could not set zsh via usermod"
}

phase4_write_zshrc_extras() {
  local username runtime_block bashrc_block
  username="$(state_get ARCH_USERNAME)"

  runtime_block='export PROOT_ACTIVE=1
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
export EDITOR=nvim
export VISUAL=nvim
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
alias vi=nvim
alias vim=nvim
alias ll="ls -lah --color=auto"
command -v bat >/dev/null 2>&1 && alias cat="bat --paging=never --style=plain"
[ -f /usr/share/fzf/key-bindings.zsh ] && source /usr/share/fzf/key-bindings.zsh
[ -f /usr/share/fzf/completion.zsh ] && source /usr/share/fzf/completion.zsh
prompt_context() {
  prompt_segment black default "%(!.%{%F{yellow}%}.)$USER@%m "
}
if [[ -o interactive ]] && [ -t 0 ] && command -v fastfetch >/dev/null 2>&1; then
  printf "\033c"
  fastfetch
fi'

  bashrc_block='if [ -z "${PROOT_ACTIVE:-}" ] && [ -x /usr/bin/zsh ]; then
  export PROOT_ACTIVE=1
  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8
  exec /usr/bin/zsh
fi'

  idempotent_append_container "$TDE_DISTRO_NAME" "$username" ".zshrc" "runtime" "$runtime_block" || \
    log_warn "Could not append runtime block to container .zshrc"
  idempotent_append_container "$TDE_DISTRO_NAME" "$username" ".bashrc" "runtime" "$bashrc_block" || \
    log_warn "Could not append runtime block to container .bashrc"
}

phase4_shell_setup_run() {
  log_info "=== Phase 4, step 3: container shell & UTF-8 locale setup ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would generate en_US.UTF-8 locale, install oh-my-zsh + zsh-autosuggestions + agnoster theme, and append runtime configuration"
    return 0
  fi

  phase4_configure_locale
  phase4_install_ohmyzsh_and_plugins
  phase4_write_zshrc_extras
  log_info "Container shell configured"
}

phase4_shell_ok() {
  local username shell ok=1
  username="$(state_get ARCH_USERNAME)"
  [ -n "$username" ] || return 1

  shell="$(proot-distro login "$TDE_DISTRO_NAME" -- getent passwd "$username" 2>/dev/null | cut -d: -f7)"
  if [ "$shell" != "/usr/bin/zsh" ]; then
    log_warn "post-check: login shell for '$username' is '${shell:-unknown}', expected /usr/bin/zsh"
    ok=0
  fi
  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
       zsh -ic 'set -e; [ "$ZSH_THEME" = "agnoster" ] && [ -n "$ZSH" ]' >/dev/null 2>&1; then
    log_warn "post-check: interactive zsh login did not load ZSH_THEME=agnoster and Oh My Zsh"
    ok=0
  fi
  [ "$ok" = "1" ]
}