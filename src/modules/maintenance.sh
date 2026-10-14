# Phase 6 — Maintenance CLI commands deployed to $PREFIX/bin and shared libraries
# synced to $PREFIX/share/termux-dev-env.

[ -n "${TDE_MODULE_MAINTENANCE_LOADED:-}" ] && return 0
TDE_MODULE_MAINTENANCE_LOADED=1

TDE_SHARE_DIR="$PREFIX/share/termux-dev-env"

_write_shebang() {
  echo "#!$PREFIX/bin/bash" > "$1"
}

_write_cli_preamble() {
  cat >> "$1" << 'EOF'
set -euo pipefail
CONF="$HOME/.config/termux-dev-env/config.env"
[ -f "$CONF" ] || { echo "termux-dev-env config not found — run ./launcher.sh first."; exit 1; }
. "$CONF"
export TDE_DISTRO_NAME="${TDE_DISTRO_NAME:-${ARCH_DISTRO_ALIAS:-archarm}}"
cd "$PREFIX/share/termux-dev-env" || { echo "Shared files missing — run './launcher.sh --reinstall=6'"; exit 1; }

source lib/core.sh
log_init
source lib/state.sh
source lib/system.sh
EOF
}

phase6_install_shared_copy() {
  mkdir -p "$TDE_SHARE_DIR"
  rm -rf "${TDE_SHARE_DIR:?}/lib" "${TDE_SHARE_DIR:?}/modules"
  cp -r "$TDE_SRC_DIR/lib" "$TDE_SHARE_DIR/lib"
  cp -r "$TDE_SRC_DIR/modules" "$TDE_SHARE_DIR/modules"
  cp "$TDE_ROOT/VERSION" "$TDE_SHARE_DIR/VERSION" 2>/dev/null || true
  cp "$TDE_SRC_DIR/orchestrator.sh" "$TDE_SHARE_DIR/orchestrator.sh" 2>/dev/null || true
  chmod +x "$TDE_SHARE_DIR/orchestrator.sh" 2>/dev/null || true
  cat > "$TDE_SHARE_DIR/launcher" << 'EOF'
#!/usr/bin/env bash
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/orchestrator.sh" "$@"
EOF
  chmod +x "$TDE_SHARE_DIR/launcher" 2>/dev/null || true
}

phase6_write_archhealth() {
  local target="$PREFIX/bin/archhealth"
  _write_shebang "$target"
  _write_cli_preamble "$target"
  cat >> "$target" << 'EOF'
source modules/rootfs.sh
source modules/user.sh
source modules/launcher.sh
source modules/toolchain.sh
source modules/nerdfonts.sh
source modules/shell.sh
source modules/neovim.sh
source lib/audit.sh

phase5_run_audit
echo ""
if [ "$TDE_AUDIT_HAD_CRITICAL_FAILURE" = "1" ]; then
  echo "STATUS: critical failure detected — see $TDE_REPORT_FILE"
  exit 1
fi
echo "STATUS: healthy"
EOF
  chmod +x "$target"
}

phase6_write_archdiag() {
  local target="$PREFIX/bin/archdiag"
  _write_shebang "$target"
  _write_cli_preamble "$target"
  cat >> "$target" << 'EOF'
source lib/validate.sh
source modules/rootfs.sh
source modules/user.sh
source modules/launcher.sh
source modules/toolchain.sh
source modules/nerdfonts.sh
source modules/shell.sh
source modules/neovim.sh
source lib/audit.sh

if [ -f "$TDE_CONFIG_DIR/last_error.env" ]; then
  echo "=== Last recorded error ==="
  cat "$TDE_CONFIG_DIR/last_error.env"
  echo ""
fi

if [ "${1:-}" != "--quick" ] && [ -f "$TDE_DIAG_FILE" ]; then
  echo "=== Hardware/environment baseline ==="
  cat "$TDE_DIAG_FILE"
  echo ""
fi

echo "=== Component health ==="
phase5_run_audit

if [ "${1:-}" != "--quick" ] && [ -f "$TDE_STATE_FILE" ]; then
  echo ""
  echo "=== State flags ==="
  cat "$TDE_STATE_FILE"
fi
EOF
  chmod +x "$target"
}

phase6_write_archupdate() {
  local target="$PREFIX/bin/archupdate"
  _write_shebang "$target"
  _write_cli_preamble "$target"
  cat >> "$target" << 'EOF'
SNAP_DIR="$HOME/.config/termux-dev-env/snapshots"
mkdir -p "$SNAP_DIR"

echo "Snapshotting installed packages..."
proot-distro login "$TDE_DISTRO_NAME" -- pacman -Q > "$SNAP_DIR/packages_$(date +%Y%m%d_%H%M%S).txt"

if [ "${1:-}" = "--with-backup" ]; then
  echo "Creating full rootfs backup..."
  proot-distro backup "$TDE_DISTRO_NAME" --output "$SNAP_DIR/rootfs_$(date +%Y%m%d_%H%M%S).tar.xz"
fi

echo "Updating Arch Linux ARM packages..."
retry_with_backoff 3 15 proot-distro login "$TDE_DISTRO_NAME" -- pacman -Syu --noconfirm || {
  echo "pacman -Syu failed after 3 attempts."
  exit 1
}

echo ""
archhealth
EOF
  chmod +x "$target"
}

phase6_write_archreset() {
  local target="$PREFIX/bin/archreset"
  _write_shebang "$target"
  cat >> "$target" << 'EOF'
set -euo pipefail
CONF="$HOME/.config/termux-dev-env/config.env"
[ -f "$CONF" ] || { echo "termux-dev-env config not found."; exit 1; }
. "$CONF"
STATE_FILE="$HOME/.config/termux-dev-env/state.env"

case "${1:-}" in
  --soft)
    echo "Removes the Arch container and resets phases 3-6. Continue? [y/N]"
    read -r c
    [ "$c" = "y" ] || exit 0
    proot-distro remove "$ARCH_DISTRO_ALIAS" 2>/dev/null || true
    if [ -f "$STATE_FILE" ]; then
      grep -Ev '^(PHASE[3-6]|ARCH_USERNAME)' "$STATE_FILE" > "$STATE_FILE.tmp" || true
      mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
    echo "Container removed. Re-run '$PREFIX/share/termux-dev-env/launcher' to reinstall."
    ;;
  --hard)
    echo "Removes EVERYTHING: container, state, and configuration. Continue? [y/N]"
    read -r c
    [ "$c" = "y" ] || exit 0
    proot-distro remove "$ARCH_DISTRO_ALIAS" 2>/dev/null || true
    rm -rf "$HOME/.config/termux-dev-env"
    echo "Full reset complete."
    ;;
  *)
    echo "Usage: archreset --soft | --hard"
    exit 1
    ;;
esac
EOF
  chmod +x "$target"
}

phase6_write_archreapply() {
  local target="$PREFIX/bin/archreapply"
  _write_shebang "$target"
  _write_cli_preamble "$target"
  cat >> "$target" << 'EOF'
source modules/launcher.sh
phase3_install_zshrc_snippet
phase3_install_archkill
phase3_configure_termux_ui
echo "Launcher snippet, archkill, and Termux extra-keys UI settings re-applied."
EOF
  chmod +x "$target"
}

phase6_write_archfont() {
  local target="$PREFIX/bin/archfont"
  _write_shebang "$target"
  _write_cli_preamble "$target"
  cat >> "$target" << 'EOF'
source modules/nerdfonts.sh

if [ "${1:-}" = "--force" ]; then
  rm -f "$HOME/.termux/font.ttf"
elif nerdfont_is_patched "$HOME/.termux/font.ttf"; then
  echo "A valid patched Nerd Font is already installed (~/.termux/font.ttf). Use 'archfont --force' to replace it."
  _nerdfont_smoke_test
  echo "If icons still show as boxes, force-stop Termux in Android Settings and reopen it."
  exit 0
fi

phase4_nerdfonts_run
EOF
  chmod +x "$target"
}

phase6_write_archselfheal() {
  local target="$PREFIX/bin/archselfheal"
  _write_shebang "$target"
  _write_cli_preamble "$target"
  cat >> "$target" << 'EOF'
source modules/rootfs.sh
source modules/user.sh
source modules/launcher.sh
source modules/toolchain.sh
source modules/nerdfonts.sh
source modules/shell.sh
source modules/neovim.sh
source lib/audit.sh

echo "Running self-heal for recoverable components..."
phase5_self_heal
echo ""
phase5_run_audit
if [ "$TDE_AUDIT_HAD_CRITICAL_FAILURE" = "1" ]; then
  exit 1
fi
if [ "${TDE_AUDIT_HAD_WARNING:-0}" = "0" ]; then
  state_del PHASE5_WARNINGS
fi
EOF
  chmod +x "$target"
}

phase6_write_archparu() {
  local target="$PREFIX/bin/archparu"
  _write_shebang "$target"
  _write_cli_preamble "$target"
  cat >> "$target" << 'EOF'
source modules/toolchain.sh
USERNAME="$(state_get ARCH_USERNAME)"
[ -n "$USERNAME" ] || { echo "No ARCH_USERNAME recorded."; exit 1; }

FROM_SRC=0
[ "${1:-}" = "--from-source" ] && FROM_SRC=1

if proot-distro login "$TDE_DISTRO_NAME" --user "$USERNAME" -- paru --version >/dev/null 2>&1; then
  proot-distro login "$TDE_DISTRO_NAME" --user "$USERNAME" -- paru --version
  exit 0
fi

phase4_install_paru "$USERNAME" "$FROM_SRC"
EOF
  chmod +x "$target"
}

phase6_write_archtreesitter() {
  local target="$PREFIX/bin/archtreesitter"
  _write_shebang "$target"
  _write_cli_preamble "$target"
  cat >> "$target" << 'EOF'
source modules/neovim.sh
export TDE_TREESITTER_FULL=1
phase4_install_treesitter_parsers
EOF
  chmod +x "$target"
}

phase6_write_archbridge() {
  local target="$PREFIX/bin/archbridge"
  _write_shebang "$target"
  cat >> "$target" << 'EOF'
set -euo pipefail
PORT="${1:-8022}"
REMOTE_USER="${2:-root}"
echo "Connecting to ${REMOTE_USER}@localhost:${PORT} (ensure 'adb reverse tcp:${PORT} tcp:22' is active on host)"
exec ssh -o StrictHostKeyChecking=accept-new -p "$PORT" "${REMOTE_USER}@localhost"
EOF
  chmod +x "$target"
}

phase6_install_bridge_deps() {
  command -v ssh >/dev/null 2>&1 && return 0
  log_info "Installing openssh client in Termux for archbridge"
  retry_with_backoff 3 5 pkg install -y openssh || \
    log_warn "Could not install openssh in Termux — archbridge will require 'pkg install openssh'"
}

phase6_maintenance_ok() {
  local cmd
  for cmd in archhealth archdiag archupdate archreset archreapply archbridge archfont archselfheal archparu archtreesitter; do
    [ -x "$PREFIX/bin/$cmd" ] || return 1
  done
  [ -d "$TDE_SHARE_DIR/lib" ] && [ -d "$TDE_SHARE_DIR/modules" ]
}

phase6_install_maintenance_run() {
  log_info "=== Phase 6: maintenance commands ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would copy lib/ and modules/ to $TDE_SHARE_DIR and generate archhealth, archdiag, archupdate, archreset, archreapply, archfont, archselfheal, archparu, archtreesitter, archbridge"
    return 0
  fi

  phase6_install_shared_copy
  phase6_write_archhealth
  phase6_write_archdiag
  phase6_write_archupdate
  phase6_write_archreset
  phase6_write_archreapply
  phase6_write_archfont
  phase6_write_archselfheal
  phase6_write_archparu
  phase6_write_archtreesitter
  phase6_install_bridge_deps
  phase6_write_archbridge

  if command -v phase3_install_zshrc_snippet >/dev/null 2>&1; then
    phase3_install_zshrc_snippet
  fi

  log_info "Maintenance commands installed: archhealth, archdiag, archupdate, archreset, archreapply, archfont, archselfheal, archparu, archtreesitter, archbridge"
}