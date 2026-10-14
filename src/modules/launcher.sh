# Phase 3, step 3 — Lightweight Termux host launcher setup, Termux extra-keys UI,
# UTF-8 environment propagation, and archkill helper.
# Note: Oh My Zsh is installed ONLY inside Arch (not duplicated on the Termux host)
# because opening Termux execs straight into the Arch container.

[ -n "${TDE_MODULE_LAUNCHER_LOADED:-}" ] && return 0
TDE_MODULE_LAUNCHER_LOADED=1

TDE_LAUNCHER_CONFIG="$HOME/.config/termux-dev-env/config.env"
TDE_BASHRC="$HOME/.bashrc"
TDE_ZSHRC="$HOME/.zshrc"

_TDE_DEFAULT_EXTRA_KEYS="[['ESC','/','-','HOME','UP','END','PGUP'],['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN']]"
TDE_TERMUX_EXTRA_KEYS="${TDE_TERMUX_EXTRA_KEYS:-$_TDE_DEFAULT_EXTRA_KEYS}"

phase3_configure_termux_ui() {
  local props="$HOME/.termux/termux.properties"
  mkdir -p "$HOME/.termux"
  touch "$props"

  if grep -q "^[[:space:]]*extra-keys" "$props" 2>/dev/null; then
    if grep -qE "^[[:space:]]*extra-keys[[:space:]]*=[[:space:]]*\[\][[:space:]]*$" "$props" 2>/dev/null; then
      log_warn "Your Termux extra-keys row is set to [] (empty) in $props. Delete that line and run 'archreapply' to restore the ESC/CTRL/arrows bar."
    else
      log_info "Keeping existing Termux extra-keys row untouched"
    fi
  else
    log_info "Configuring default Termux extra-keys row (ESC/CTRL/TAB/arrows)"
    echo "extra-keys = $TDE_TERMUX_EXTRA_KEYS" >> "$props"
  fi

  if [ "${TDE_TERMUX_BLACK_UI:-0}" = "1" ] && ! grep -q "^[[:space:]]*use-black-ui" "$props" 2>/dev/null; then
    echo "use-black-ui = true" >> "$props"
  fi

  if command -v termux-reload-settings >/dev/null 2>&1; then
    termux-reload-settings || log_warn "termux-reload-settings failed — settings will apply on next Termux restart"
  fi
  return 0
}

phase3_write_launcher_config() {
  local username
  username="$(state_get ARCH_USERNAME)"
  kv_set "$TDE_LAUNCHER_CONFIG" ARCH_USERNAME "$username"
  kv_set "$TDE_LAUNCHER_CONFIG" ARCH_DISTRO_ALIAS "$TDE_DISTRO_NAME"
  kv_set "$TDE_LAUNCHER_CONFIG" TDE_DISTRO_NAME "$TDE_DISTRO_NAME"
  kv_set "$TDE_LAUNCHER_CONFIG" TDE_ROOT "$TDE_ROOT"
}

phase3_install_zshrc_snippet() {
  local content
  content="$(cat << EOF
# Escape hatch: TDE_SKIP_LAUNCHER=1 bash  (or export it before opening Termux)
export LANG="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"
if [ -f "$TDE_LAUNCHER_CONFIG" ] && [ -z "\${PROOT_ACTIVE:-}" ] && [ -z "\${TDE_SKIP_LAUNCHER:-}" ]; then
  . "$TDE_LAUNCHER_CONFIG"
  if command -v timeout >/dev/null 2>&1; then
    _tde_smoke() { timeout "\${TDE_LAUNCHER_SMOKE_TIMEOUT:-25}" "\$@"; }
  else
    _tde_smoke() { "\$@"; }
  fi
  _tde_smoke_cmd='test -d "\$HOME" && test -x /usr/bin/zsh && [ "\$(getent passwd "\$(id -un)" | cut -d: -f7)" = /usr/bin/zsh ]'
  if _tde_smoke proot-distro login "\$ARCH_DISTRO_ALIAS" --user "\$ARCH_USERNAME" -- sh -c "\$_tde_smoke_cmd" 2>/dev/null; then
    unset -f _tde_smoke
    unset _tde_smoke_cmd
    exec proot-distro login "\$ARCH_DISTRO_ALIAS" --user "\$ARCH_USERNAME" --isolated
  else
    _tde_rc=\$?
    unset -f _tde_smoke
    unset _tde_smoke_cmd
    echo "termux-dev-env: could not start Arch session as '\$ARCH_USERNAME' in '\$ARCH_DISTRO_ALIAS' — staying in Termux."
    if [ "\$_tde_rc" = "124" ]; then
      echo "(container timed out after \${TDE_LAUNCHER_SMOKE_TIMEOUT:-25}s — run 'archkill' then open a new session)"
    else
      echo "(verified: home directory exists, /usr/bin/zsh is executable, login shell is /usr/bin/zsh)"
    fi
    echo "Try: archdiag   |   archhealth   |   TDE_SKIP_LAUNCHER=1 bash"
    unset _tde_rc
  fi
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
echo "Arch container closed."
EOF
  chmod +x "$target"
}

phase3_setup_launcher_run() {
  log_info "=== Phase 3, step 3: Termux launcher & UI setup ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would configure Termux extra-keys row, write launcher config, append auto-login snippet to .bashrc and .zshrc, and install archkill"
    return 0
  fi

  phase3_configure_termux_ui
  phase3_write_launcher_config
  phase3_install_zshrc_snippet
  phase3_install_archkill
  log_info "Launcher configured — new Termux sessions auto-enter Arch Linux. Escape hatch: TDE_SKIP_LAUNCHER=1"
}

phase3_launcher_ok() {
  [ -f "$TDE_LAUNCHER_CONFIG" ] && \
    grep -q "^ARCH_USERNAME=" "$TDE_LAUNCHER_CONFIG" && \
    grep -qF -- "termux-dev-env: launcher" "$TDE_BASHRC" 2>/dev/null && \
    grep -qF -- "termux-dev-env: launcher" "$TDE_ZSHRC" 2>/dev/null && \
    [ -x "$PREFIX/bin/archkill" ] && \
    [ -f "$HOME/.termux/termux.properties" ]
}