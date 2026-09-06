# Phase 3, step 3 — launcher setup. Writes the config the .zshrc snippet
# reads, appends that snippet idempotently (safe to re-run), and installs
# archkill as a real $PREFIX/bin script so it works regardless of shell.

[ -n "${TDE_SETUP_LAUNCHER_LOADED:-}" ] && return 0
TDE_SETUP_LAUNCHER_LOADED=1

TDE_LAUNCHER_CONFIG="$HOME/.config/termux-dev-env/config.env"
TDE_ZSHRC="$HOME/.zshrc"

phase3_write_launcher_config() {
  local username
  username="$(state_get ARCH_USERNAME)"
  kv_set "$TDE_LAUNCHER_CONFIG" ARCH_USERNAME "$username"
  kv_set "$TDE_LAUNCHER_CONFIG" ARCH_DISTRO_ALIAS "$TDE_DISTRO_NAME"
}

# Idempotent: safe to re-run without duplicating the block in .zshrc.
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
  idempotent_append "$TDE_ZSHRC" "launcher" "$content"
}

phase3_install_archkill() {
  local target="$PREFIX/bin/archkill"
  cat > "$target" << EOF
#!$PREFIX/bin/bash
# Force-closes the Arch container without saving unsaved work.
[ -f "$TDE_LAUNCHER_CONFIG" ] && . "$TDE_LAUNCHER_CONFIG"
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
    log_info "[dry-run] would write launcher config, append idempotent .zshrc snippet, install archkill to \$PREFIX/bin"
    return 0
  fi

  phase3_write_launcher_config
  phase3_install_zshrc_snippet
  phase3_install_archkill
  log_info "Launcher installed — a new Termux session logs into Arch automatically once zsh is the default shell (phase 4). Escape hatch: TDE_SKIP_LAUNCHER=1"
}

# Post-condition, checked by core.sh before marking PHASE3_LAUNCHER_SETUP.
phase3_launcher_ok() {
  [ -f "$TDE_LAUNCHER_CONFIG" ] && \
    grep -q "^ARCH_USERNAME=" "$TDE_LAUNCHER_CONFIG" && \
    grep -qF -- "termux-dev-env: launcher" "$TDE_ZSHRC" 2>/dev/null && \
    [ -x "$PREFIX/bin/archkill" ]
}
