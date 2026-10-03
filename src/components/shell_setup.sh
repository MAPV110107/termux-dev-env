# Phase 4 — shell setup, INSIDE the container. Order matters: oh-my-zsh's
# installer overwrites .zshrc with its own template, so our PROOT_ACTIVE
# snippet must be appended AFTER it installs, never before.
#
# Design decision: no tmux. It used to auto-attach on login, adding a
# process between Termux and the Arch zsh (Termux -> proot -> zsh ->
# tmux -> zsh) that the person had to `exit` out of twice, and — if a
# `--reinstall=4` ever ran before the interactive-shell guard existed —
# could leave a bare, un-Oh-My-Zsh'd `localhost%% ` prompt behind after
# the last `exit`. tmux is not installed by this project and nothing it
# writes into `.zshrc` references it; if a person installs tmux
# themselves, it is never auto-launched.

[ -n "${TDE_SHELL_SETUP_LOADED:-}" ] && return 0
TDE_SHELL_SETUP_LOADED=1

TDE_OHMYZSH_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

phase4_install_zsh_packages() {
  log_info "Installing zsh"
  proot-distro login "$TDE_DISTRO_NAME" -- pacman -S --noconfirm --needed zsh || \
    log_fatal_code 420 "Could not install zsh"
}

phase4_install_ohmyzsh() {
  local username
  username="$(state_get ARCH_USERNAME)"

  # Checked from INSIDE the container (proot-distro login --user), not
  # as a direct host-side path into the rootfs. In the wild, oh-my-zsh's
  # own installer printed "adding it to /home/<user>/.zshrc" and exited
  # successfully, yet a direct host-side `[ -f "$(container_home ...)"
  # ]` right after still read the file as missing. Whatever the exact
  # proot/storage mechanism behind that is, checking through the same
  # access path the file was written through (login as the user) sees
  # it correctly, matching how every functional post-condition elsewhere
  # in this project (phase3_rootfs_ok, phase4_toolchain_ok, ...) already
  # verifies things — this function just wasn't consistent with that
  # yet. See docs/TROUBLESHOOTING.md's ".zshrc missing" section.
  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
       sh -c '[ -d ~/.oh-my-zsh ] && [ -f ~/.zshrc ]' 2>/dev/null; then
    log_info "oh-my-zsh already installed, skipping"
    return 0
  fi
  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- test -d "/home/$username/.oh-my-zsh" 2>/dev/null; then
    log_warn ".oh-my-zsh exists but .zshrc is missing (interrupted previous install) — re-running the installer to repair it"
  fi

  retry_with_backoff 3 5 proot-distro login "$TDE_DISTRO_NAME" --user "$username" \
    --env OHMYZSH_URL="$TDE_OHMYZSH_INSTALL_URL" -- bash -c '
    set -e
    install_script="$(curl -fsSL "$OHMYZSH_URL")"
    [ -n "$install_script" ]
    RUNZSH=no CHSH=no KEEP_ZSHRC=no sh -c "$install_script"
  ' || log_fatal_code 421 "oh-my-zsh install failed"

  # Belt and suspenders: the upstream installer has historically had edge
  # cases where it exits 0 without actually placing .zshrc (a bad $HOME,
  # a template-copy step that silently no-ops). Every later step in this
  # phase (theme, plugin, the PROOT_ACTIVE snippet) assumes .zshrc
  # exists, so make sure of it right here instead of letting a "sed: No
  # such file" surface three functions later with no context.
  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- test -f "/home/$username/.zshrc" 2>/dev/null; then
    log_warn ".zshrc still missing after oh-my-zsh install reported success — writing a minimal fallback so the rest of Phase 4 has something to work with"
    proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- sh -c \
      'cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc 2>/dev/null || printf "export ZSH=\"\$HOME/.oh-my-zsh\"\nZSH_THEME=\"robbyrussell\"\nplugins=(git)\nsource \$ZSH/oh-my-zsh.sh\n" > ~/.zshrc' || \
      log_fatal_code 422 "Could not create .zshrc even as a fallback — oh-my-zsh install is unrecoverable, check $TDE_LOG_FILE"
  fi
}

phase4_install_zsh_autosuggestions() {
  local username
  username="$(state_get ARCH_USERNAME)"

  # Container-side check, same reasoning as phase4_install_ohmyzsh above.
  # Absolute path, not ~/... — a bare tilde here would be expanded by
  # THIS (Termux-side) shell before proot-distro ever sees it, testing
  # Termux's own home instead of the container user's (see
  # docs/TROUBLESHOOTING.md's "silently checked the wrong home" section).
  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
       test -d "/home/$username/.oh-my-zsh/custom/plugins/zsh-autosuggestions" 2>/dev/null; then
    log_info "zsh-autosuggestions already present"
    return 0
  fi

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions \
    "/home/$username/.oh-my-zsh/custom/plugins/zsh-autosuggestions" || \
    log_warn "Could not install zsh-autosuggestions — shell works, just without suggestions"
}

phase4_enable_autosuggestions_plugin() {
  local username
  username="$(state_get ARCH_USERNAME)"
  # phase4_install_ohmyzsh guarantees .zshrc exists by the time this runs
  # (repairing it if the upstream installer didn't), but this stays
  # defensive rather than assuming that always holds — a noisy
  # "sed: can't read ... No such file" with no context is worse than a
  # clear warning naming exactly what's missing and why this step is
  # being skipped. Checked and edited from inside the container (not a
  # host-side path) — see phase4_install_ohmyzsh's comment for why.
  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- test -f "/home/$username/.zshrc" 2>/dev/null; then
    log_warn ".zshrc missing for '$username' — skipping zsh-autosuggestions plugin enable (shell will still work, just without suggestions)"
    return 0
  fi
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- sh -c '
    grep -q "zsh-autosuggestions" ~/.zshrc && exit 0
    sed -i "s/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions)/" ~/.zshrc
  ' || log_warn "Could not enable zsh-autosuggestions plugin in .zshrc"
}

# agnoster ships with oh-my-zsh itself, no extra download — matches the
# theme now set for Termux's own shell too, for a consistent look on both
# sides of the launcher.
phase4_set_zsh_theme() {
  local username
  username="$(state_get ARCH_USERNAME)"
  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- test -f "/home/$username/.zshrc" 2>/dev/null; then
    log_warn ".zshrc missing for '$username' — skipping theme set (shell will still work, just with oh-my-zsh's default theme)"
    return 0
  fi
  # Replaces ZSH_THEME= if present, inserts it if the line is somehow
  # missing entirely (grep -q guard — sed's own s/// silently does
  # nothing if the pattern never matches, the same footgun documented
  # in phase3_disable_pacman_sandbox, so a missing line must not be
  # allowed to look like success). Wrapped in sh -c so ~ is expanded
  # remotely by the container's shell, not by this (Termux-side) one —
  # see phase4_install_ohmyzsh's comment for why that distinction matters.
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- sh -c '
    if grep -q "^ZSH_THEME=" ~/.zshrc; then
      sed -i "s/^ZSH_THEME=.*/ZSH_THEME=\"agnoster\"/" ~/.zshrc
    else
      echo "ZSH_THEME=\"agnoster\"" >> ~/.zshrc
    fi
  ' || log_warn "Could not set ZSH_THEME in .zshrc"
}

# oh-my-zsh's installer always writes `source $ZSH/oh-my-zsh.sh` into its
# template — but a person's own edits, an interrupted install repaired
# by the minimal fallback in phase4_install_ohmyzsh, or a future
# oh-my-zsh template change could leave it out, which is exactly what a
# theme-less, plugin-less `localhost%% ` prompt with no error looks
# like: zsh started fine, oh-my-zsh (and therefore the theme and
# plugins) just never loaded. Idempotent — checked before appending.
phase4_ensure_ohmyzsh_sourced() {
  local username
  username="$(state_get ARCH_USERNAME)"
  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- test -f "/home/$username/.zshrc" 2>/dev/null; then
    return 0
  fi
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- sh -c '
    grep -q "oh-my-zsh\.sh" ~/.zshrc || echo "source \$ZSH/oh-my-zsh.sh" >> ~/.zshrc
  ' || log_warn "Could not confirm oh-my-zsh.sh is sourced in .zshrc"
}

# Arch Linux ARM's rootfs ships with LANG=C — no UTF-8 locale generated
# at all — so fastfetch and agnoster's box-drawing/powerline glyphs
# fail ("character not in range") even with a Nerd Font installed and
# the theme set correctly; it is a locale problem, not a font problem.
# Idempotent: locale-gen and the file writes are safe to repeat.
# locale-gen exits 0 even when it generated nothing usable, so the
# result is verified against `locale -a` instead of the command's exit
# status. A missing UTF-8 locale is what makes fastfetch and the
# agnoster prompt render boxes and "character not in range" even with a
# perfectly good Nerd Font installed — worth naming explicitly, because
# it sends people hunting a font problem that is really a locale one.
phase4_configure_locale() {
  proot-distro login "$TDE_DISTRO_NAME" -- sh -c '
    grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen 2>/dev/null || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    printf "LANG=en_US.UTF-8\\nLC_ALL=en_US.UTF-8\\n" > /etc/locale.conf
  ' || log_warn "locale-gen reported a failure — verifying the result anyway"

  if proot-distro login "$TDE_DISTRO_NAME" -- sh -c 'locale -a 2>/dev/null | tr "[:upper:]" "[:lower:]" | tr -d "-" | grep -q "^en_us.utf8$"'; then
    log_info "Locale en_US.UTF-8 generated and available"
    return 0
  fi

  log_warn "en_US.UTF-8 is NOT available inside the container after locale-gen — fastfetch and the agnoster prompt will show broken glyphs even with the Nerd Font installed. This is a locale problem, not a font problem. Fix: proot-distro login $TDE_DISTRO_NAME -- sh -c 'echo en_US.UTF-8 UTF-8 >> /etc/locale.gen && locale-gen'"
  return 0
}

phase4_set_default_shell() {
  local username
  username="$(state_get ARCH_USERNAME)"
  proot-distro login "$TDE_DISTRO_NAME" -- usermod -s /usr/bin/zsh "$username" || \
    log_warn "Could not set zsh as default shell — the launcher will still work, just drops into bash first"
}

phase4_write_zshrc_extras() {
  local username runtime_block bashrc_block

  # No tmux here — see the file header. fastfetch is guarded the same
  # way tmux used to be (interactive + TTY): this must never fire on a
  # scripted "proot-distro login -- <command>" call (every phase 4-6
  # step and archhealth/archdiag/archupdate use exactly that), only on
  # a real session.
  runtime_block='export PROOT_ACTIVE=1
export PATH="$HOME/.local/bin:$PATH"
export EDITOR=nvim
export VISUAL=nvim
export DEFAULT_USER="$USER"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
alias vi=nvim
alias vim=nvim
alias ll="ls -lah --color=auto"
if [[ -o interactive ]] && [ -t 0 ] && command -v fastfetch >/dev/null 2>&1; then
  # Clear first: without this the banner prints underneath whatever was
  # already on screen (the installer log, the previous Termux session),
  # which looks like a glitch rather than a login screen. printf "\\033c"
  # is a full terminal reset — closer to how a fresh session starts than
  # clear, which only scrolls the old content out of view.
  printf "\\033c"
  fastfetch
fi'

  bashrc_block='if [ -z "$PROOT_ACTIVE" ] && [ -x /usr/bin/zsh ]; then
  export PROOT_ACTIVE=1
  exec /usr/bin/zsh
fi'

  username="$(state_get ARCH_USERNAME)"

  # Appended and de-duplicated from inside the container, not against a
  # host-side path into the rootfs — see phase4_install_ohmyzsh's comment
  # above and lib/idempotent_append.sh for why.
  idempotent_append_container "$TDE_DISTRO_NAME" "$username" ".zshrc" "runtime" "$runtime_block" || \
    log_warn "Could not append the PROOT_ACTIVE runtime snippet to .zshrc"
  idempotent_append_container "$TDE_DISTRO_NAME" "$username" ".bashrc" "runtime" "$bashrc_block" || \
    log_warn "Could not append PROOT_ACTIVE/zsh-exec snippet to .bashrc"
}

phase4_shell_setup_run() {
  log_info "=== Phase 4: shell setup (zsh + oh-my-zsh) ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would install zsh, set locale to en_US.UTF-8, oh-my-zsh, zsh-autosuggestions, agnoster theme, DEFAULT_USER, set zsh as default shell, append PROOT_ACTIVE + EDITOR/aliases + fastfetch banner (no tmux)"
    return 0
  fi

  phase4_install_zsh_packages
  phase4_configure_locale
  phase4_install_ohmyzsh
  phase4_ensure_ohmyzsh_sourced
  phase4_install_zsh_autosuggestions
  phase4_enable_autosuggestions_plugin
  phase4_set_zsh_theme
  phase4_set_default_shell
  phase4_write_zshrc_extras
  log_info "Shell configured"
}

# Post-condition, checked by core.sh before marking PHASE4_SHELL. .zshrc
# checks run through the container (proot-distro login --user), not a
# host-side path — see phase4_install_ohmyzsh's comment for why.
phase4_shell_ok() {
  local username shell ok=1
  username="$(state_get ARCH_USERNAME)"
  [ -n "$username" ] || { log_warn "post-check: no ARCH_USERNAME in state"; return 1; }

  shell="$(proot-distro login "$TDE_DISTRO_NAME" -- getent passwd "$username" 2>/dev/null | cut -d: -f7)"
  if [ "$shell" != "/usr/bin/zsh" ]; then
    log_warn "post-check: '$username's login shell is '${shell:-unknown}', not /usr/bin/zsh"
    ok=0
  fi
  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- test -f "/home/$username/.zshrc" 2>/dev/null; then
    log_warn "post-check: .zshrc does not exist for '$username'"
    ok=0
  else
    # Behavioral, not textual: runs an actual interactive zsh (-i, so
    # .zshrc really gets sourced) and reads the live variables
    # afterward, instead of grepping the file for a string that could
    # be present but never take effect (oh-my-zsh not sourced, a syntax
    # error earlier in the file, etc. — exactly how a real device ended
    # up with a themeless `localhost%% ` prompt despite the file
    # containing the right ZSH_THEME line).
    if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
         zsh -ic 'set -e; [ "$ZSH_THEME" = "agnoster" ] && [ -n "$ZSH" ]' >/dev/null 2>&1; then
      log_warn "post-check: an interactive zsh login did not actually end up with ZSH_THEME=agnoster and oh-my-zsh loaded (\$ZSH set) — .zshrc may have the right lines but something earlier in it is failing, or oh-my-zsh.sh isn't sourced"
      ok=0
    fi
  fi

  [ "$ok" = "1" ]
}
