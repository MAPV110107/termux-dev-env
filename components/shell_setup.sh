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
  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- test -d ~/.oh-my-zsh 2>/dev/null; then
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
  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- test -f ~/.zshrc 2>/dev/null; then
    log_warn ".zshrc still missing after oh-my-zsh install reported success — writing a minimal fallback so the rest of Phase 4 has something to work with"
    proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- sh -c \
      'cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc 2>/dev/null || printf "export ZSH=\"\$HOME/.oh-my-zsh\"\nZSH_THEME=\"robbyrussell\"\nplugins=(git)\nsource \$ZSH/oh-my-zsh.sh\n" > ~/.zshrc' || \
      log_fatal "Could not create .zshrc even as a fallback — oh-my-zsh install is unrecoverable, check $TDE_LOG_FILE"
  fi
}

phase4_install_zsh_autosuggestions() {
  local username
  username="$(state_get ARCH_USERNAME)"

  # Container-side check, same reasoning as phase4_install_ohmyzsh above.
  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
       test -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions 2>/dev/null; then
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
  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- test -f ~/.zshrc 2>/dev/null; then
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
  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- test -f ~/.zshrc 2>/dev/null; then
    log_warn ".zshrc missing for '$username' — skipping theme set (shell will still work, just with oh-my-zsh's default theme)"
    return 0
  fi
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="agnoster"/' ~/.zshrc || \
    log_warn "Could not set ZSH_THEME in .zshrc"
}

phase4_set_default_shell() {
  local username
  username="$(state_get ARCH_USERNAME)"
  proot-distro login "$TDE_DISTRO_NAME" -- usermod -s /usr/bin/zsh "$username" || \
    log_warn "Could not set zsh as default shell — the launcher will still work, just drops into bash first"
}

phase4_write_zshrc_extras() {
  local username runtime_block bashrc_block

  # tmux only auto-attaches for a genuinely interactive login (zsh's own
  # "interactive" option, which is off for any "-c command" invocation
  # regardless of whether a TTY happens to be attached to that process —
  # e.g. proot-distro login --user <name> -- <cmd>, which every phase 4-6
  # postcondition and setup step after this point uses to run things
  # inside the container as this user). Without this guard tmux would try
  # to take over the terminal on every one of those calls too, not just a
  # real interactive session from setup_launcher.sh, and hang scripted
  # steps that have no TTY loop to break out of it.
  runtime_block='export PROOT_ACTIVE=1
export PATH="$HOME/.local/bin:$PATH"
if [[ -o interactive ]] && [ -t 0 ] && command -v tmux >/dev/null 2>&1 && [ -z "$TMUX" ]; then
  tmux attach -t main 2>/dev/null || tmux new -s main
fi'

  bashrc_block='if [ -z "$PROOT_ACTIVE" ] && [ -x /usr/bin/zsh ]; then
  export PROOT_ACTIVE=1
  exec /usr/bin/zsh
fi'

  username="$(state_get ARCH_USERNAME)"

  # Appended and de-duplicated from inside the container (not
  # idempotent_append's usual host-side path into the rootfs) — see
  # phase4_install_ohmyzsh's comment above for why: a host-side path did
  # not reliably reflect what had just been written from inside proot in
  # the wild. Mirrors idempotent_append's own marker format and
  # strip-old-block-then-append logic, just run as the user via login
  # instead of directly against the host path, with the block content
  # passed through --env so no nested-quoting mess is needed to get a
  # multi-line, dollar-sign-and-bracket-heavy shell snippet through intact.
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" \
    --env TDE_BLOCK="$runtime_block" -- sh -c '
    f=~/.zshrc
    start="# >>> termux-dev-env: runtime >>>"
    end="# <<< termux-dev-env: runtime <<<"
    touch "$f"
    if grep -qF -- "$start" "$f"; then
      awk -v s="$start" -v e="$end" "\$0==s{skip=1} !skip{print} \$0==e{skip=0}" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    fi
    { echo ""; echo "$start"; printf "%s\n" "$TDE_BLOCK"; echo "$end"; } >> "$f"
  ' || log_warn "Could not append PROOT_ACTIVE/tmux snippet to .zshrc"

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" \
    --env TDE_BLOCK="$bashrc_block" -- sh -c '
    f=~/.bashrc
    start="# >>> termux-dev-env: runtime >>>"
    end="# <<< termux-dev-env: runtime <<<"
    touch "$f"
    if grep -qF -- "$start" "$f"; then
      awk -v s="$start" -v e="$end" "\$0==s{skip=1} !skip{print} \$0==e{skip=0}" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    fi
    { echo ""; echo "$start"; printf "%s\n" "$TDE_BLOCK"; echo "$end"; } >> "$f"
  ' || log_warn "Could not append PROOT_ACTIVE/zsh-exec snippet to .bashrc"
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
  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- test -f ~/.zshrc 2>/dev/null; then
    log_warn "post-check: .zshrc does not exist for '$username'"
    ok=0
  elif ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- grep -q 'ZSH_THEME="agnoster"' ~/.zshrc 2>/dev/null; then
    log_warn "post-check: ZSH_THEME=\"agnoster\" missing from .zshrc"
    ok=0
  fi

  [ "$ok" = "1" ]
}
