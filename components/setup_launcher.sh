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
  # sed's s/// silently does nothing if ZSH_THEME= isn't there to match
  # (same footgun as phase3_disable_pacman_sandbox) — insert it instead
  # of leaving a themeless prompt that looks like it "should" have worked.
  if grep -q "^ZSH_THEME=" "$TDE_ZSHRC" 2>/dev/null; then
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="agnoster"/' "$TDE_ZSHRC"
  else
    echo 'ZSH_THEME="agnoster"' >> "$TDE_ZSHRC"
  fi
  grep -q "DEFAULT_USER=" "$TDE_ZSHRC" 2>/dev/null || \
    echo 'export DEFAULT_USER="$USER"' >> "$TDE_ZSHRC"
}

# The extra-keys row (ESC/TAB/CTRL/ALT/arrows) is Termux's only way to
# type keys an Android soft keyboard simply does not have. This used to
# write "extra-keys = []", deliberately hiding it to save vertical
# space — which left people in a zsh+LazyVim environment with no ESC,
# no CTRL and no arrow keys, reported as "the bottom bar disappeared
# after installing". A terminal IDE needs those keys far more than it
# needs the two lines of screen they cost.
#
# Now: never hide the row, and never overwrite a row the person already
# configured. If the key is absent entirely, write a two-row layout
# covering what this environment actually needs (ESC and CTRL for zsh
# and Neovim, arrows for both, PGUP/PGDN for scrollback, HOME/END for
# line editing, and '/' and '-' which are awkward on most soft
# keyboards). Set TDE_TERMUX_EXTRA_KEYS to override the default layout.
_TDE_DEFAULT_EXTRA_KEYS="[['ESC','/','-','HOME','UP','END','PGUP'],['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN']]"
TDE_TERMUX_EXTRA_KEYS="${TDE_TERMUX_EXTRA_KEYS:-$_TDE_DEFAULT_EXTRA_KEYS}"

phase3_configure_termux_ui() {
  local props="$HOME/.termux/termux.properties"
  mkdir -p "$HOME/.termux"
  touch "$props"

  if grep -q "^[[:space:]]*extra-keys" "$props" 2>/dev/null; then
    # Someone (Termux's own default file, or the person) already has a
    # row configured. Leave it exactly as it is — but if a previous
    # version of this installer is the one that emptied it, say so
    # instead of silently leaving them without an ESC key.
    if grep -qE "^[[:space:]]*extra-keys[[:space:]]*=[[:space:]]*\[\][[:space:]]*$" "$props" 2>/dev/null; then
      log_warn "Your Termux extra-keys row is set to [] (empty) in $props — an earlier version of this installer did that. Delete that line and run 'archreapply' to get the ESC/CTRL/arrow row back."
    else
      log_info "Keeping your existing Termux extra-keys row untouched"
    fi
  else
    log_info "Setting a default Termux extra-keys row (ESC/CTRL/arrows — override with TDE_TERMUX_EXTRA_KEYS)"
    echo "extra-keys = $TDE_TERMUX_EXTRA_KEYS" >> "$props"
  fi

  # Opt-in (TDE_TERMUX_BLACK_UI=1): this is a pure appearance preference
  # and writing it unasked overrode what people had chosen in Termux's
  # own style settings.
  if [ "${TDE_TERMUX_BLACK_UI:-0}" = "1" ] && ! grep -q "^[[:space:]]*use-black-ui" "$props" 2>/dev/null; then
    echo "use-black-ui = true" >> "$props"
  fi

  # '|| true': as the last statement of the function its exit status
  # becomes the function's, and under the project-wide `set -e` + ERR
  # trap a missing termux-reload-settings (any non-Termux environment,
  # a stripped install) aborted the entire installer here. Reloading is
  # a convenience — the settings file is already written either way.
  if command -v termux-reload-settings >/dev/null 2>&1; then
    termux-reload-settings || log_warn "termux-reload-settings failed — your termux.properties is written, it applies on the next Termux restart"
  else
    log_info "termux-reload-settings not available — termux.properties written, it applies on the next Termux restart"
  fi
  return 0
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
  kv_set "$TDE_LAUNCHER_CONFIG" TDE_DISTRO_NAME "$TDE_DISTRO_NAME"
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
  # exec, not a plain call: replaces this Termux shell instead of
  # spawning Arch as its child, so a single 'exit' from inside Arch
  # closes the whole session (no more needing 'exit' twice). Trade-off:
  # if the container login itself fails to even start (broken rootfs,
  # missing user), there's no Termux shell left to fall back into — the
  # session just ends. Recover with a fresh Termux session and
  # TDE_SKIP_LAUNCHER=1, or use a second session and 'archkill'.
  # Smoke test before committing to exec: if the container or the user
  # account is broken, this fails fast into a normal Termux prompt with
  # a clear next step, instead of exec-ing into a login that errors out
  # and leaves nothing behind (see the trade-off note above).
  #
  # '-- true' alone was too weak: it succeeds on a container whose user
  # has no home directory or whose login shell is missing or not zsh,
  # which are exactly the states that produce a broken-looking session
  # after the exec. It also had no timeout, so a container wedged under
  # memory pressure would hang every new Termux session indefinitely.
  # Now it verifies the three things the session actually depends on —
  # home exists, login shell is /usr/bin/zsh, zsh is executable — under
  # a hard timeout (timeout(1) ships with Termux's coreutils; if it is
  # somehow missing the check still runs, just untimed).
  if command -v timeout >/dev/null 2>&1; then
    _tde_smoke() { timeout "\${TDE_LAUNCHER_SMOKE_TIMEOUT:-25}" "\$@"; }
  else
    _tde_smoke() { "\$@"; }
  fi
  # Every \$ here is escaped so the heredoc writing this file emits them
  # literally: they must be expanded by the shell INSIDE the container
  # at login time, not by the Termux-side shell that wrote the snippet.
  # Without the escapes this baked Termux's own \$HOME and login shell
  # into the test, which then compared Termux's bash against
  # /usr/bin/zsh and refused to ever enter Arch.
  _tde_smoke_cmd='test -d "\$HOME" && test -x /usr/bin/zsh && [ "\$(getent passwd "\$(id -un)" | cut -d: -f7)" = /usr/bin/zsh ]'
  if _tde_smoke proot-distro login "\$ARCH_DISTRO_ALIAS" --user "\$ARCH_USERNAME" -- sh -c "\$_tde_smoke_cmd" 2>/dev/null; then
    unset -f _tde_smoke
    exec proot-distro login "\$ARCH_DISTRO_ALIAS" --user "\$ARCH_USERNAME" --isolated
  else
    _tde_rc=\$?
    unset -f _tde_smoke
    echo "termux-dev-env: could not start a usable Arch session as '\$ARCH_USERNAME' in '\$ARCH_DISTRO_ALIAS' — staying in Termux."
    if [ "\$_tde_rc" = "124" ]; then
      echo "(the container did not respond within \${TDE_LAUNCHER_SMOKE_TIMEOUT:-25}s — it may be under memory pressure; try 'archkill' then open a new session)"
    else
      echo "(checked: home directory exists, /usr/bin/zsh is executable, login shell is /usr/bin/zsh)"
    fi
    echo "Try: archdiag   |   archhealth   |   TDE_SKIP_LAUNCHER=1 zsh   to always land in Termux"
    unset _tde_rc
  fi
  unset _tde_smoke_cmd
fi
EOF
)"
  idempotent_append "$TDE_BASHRC" "launcher" "$content"
  idempotent_append "$TDE_ZSHRC" "launcher" "$content"
}

phase3_install_archkill() {
  mkdir -p "$PREFIX/bin"
  local target="$PREFIX/bin/archkill"
  cat > "$target" << EOF
#!$PREFIX/bin/bash
# Force-closes the Arch container without saving unsaved work.
[ -f "$TDE_LAUNCHER_CONFIG" ] && . "$TDE_LAUNCHER_CONFIG"
DISTRO="\${TDE_DISTRO_NAME:-\${ARCH_DISTRO_ALIAS:-${TDE_DISTRO_NAME:-archarm}}}"
echo "This will close Arch without saving unsaved work (open editors, running commands). Continue? [y/N]"
read -r confirm
[ "\$confirm" = "y" ] || exit 0
proot-distro kill "\$DISTRO"
echo "Arch closed."
EOF
  chmod +x "$target"
}

phase3_setup_launcher_run() {
  log_info "=== Phase 3, step 3: launcher setup ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would install zsh+oh-my-zsh+agnoster+autosuggestions in Termux, add a default extra-keys row only if none is configured (never overwriting yours, never emptying it), set zsh as default shell, write launcher config, append idempotent snippet to .bashrc and .zshrc, install archkill to \$PREFIX/bin"
    return 0
  fi

  phase3_install_termux_zsh_packages
  phase3_install_termux_ohmyzsh
  phase3_install_termux_autosuggestions
  phase3_configure_termux_zshrc
  phase3_configure_termux_ui
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
    grep -q 'ZSH_THEME="agnoster"' "$TDE_ZSHRC" 2>/dev/null && \
    [ -f "$HOME/.termux/termux.properties" ]
}
