# Phase 6 — maintenance commands. Each script is a thin wrapper: it loads
# config.env, cd's into the repo, and sources the SAME lib/component files
# phases 1-5 already use — no logic is duplicated here. Quoted heredocs
# ('EOF') are used for every script body so nothing expands at generation
# time by accident; only the shebang line is substituted deliberately.

[ -n "${TDE_INSTALL_MAINTENANCE_LOADED:-}" ] && return 0
TDE_INSTALL_MAINTENANCE_LOADED=1

_write_shebang() {
  echo "#!$PREFIX/bin/bash" > "$1"
}

# Copies lib/ + components/ to a stable, fixed location. archhealth/
# archdiag/archreapply source from here instead of $TDE_ROOT, so moving
# or deleting the cloned repo doesn't break them. Re-run with
# --reinstall=6 to re-sync after editing the live repo.
TDE_SHARE_DIR="$PREFIX/share/termux-dev-env"

phase6_install_shared_copy() {
  mkdir -p "$TDE_SHARE_DIR"
  rm -rf "$TDE_SHARE_DIR/lib" "$TDE_SHARE_DIR/components"
  cp -r "$TDE_ROOT/lib" "$TDE_SHARE_DIR/lib"
  cp -r "$TDE_ROOT/components" "$TDE_SHARE_DIR/components"
  cp "$TDE_ROOT/VERSION" "$TDE_SHARE_DIR/VERSION" 2>/dev/null || true
}

phase6_write_archhealth() {
  local target="$PREFIX/bin/archhealth"
  _write_shebang "$target"
  cat >> "$target" << 'EOF'
set -euo pipefail
CONF="$HOME/.config/termux-dev-env/config.env"
[ -f "$CONF" ] || { echo "termux-dev-env config not found — is it installed?"; exit 1; }
. "$CONF"
cd "$PREFIX/share/termux-dev-env" || { echo "termux-dev-env shared files not found — re-run phase 6 (./core.sh --reinstall=6)"; exit 1; }

source lib/error_handling.sh
source lib/logging.sh
log_init
source lib/kv.sh
source lib/state.sh
source lib/container_paths.sh
source components/install_rootfs.sh
source components/create_user.sh
source components/setup_launcher.sh
source components/dev_toolchain.sh
source components/shell_setup.sh
source components/lazyvim.sh
source lib/generate_report.sh
source lib/verify_functional.sh

phase5_run_audit
echo ""
if [ "$TDE_AUDIT_HAD_CRITICAL_FAILURE" = "1" ]; then
  echo "STATUS: something critical is broken — see $TDE_REPORT_FILE"
  exit 1
fi
echo "STATUS: healthy"
EOF
  chmod +x "$target"
}

phase6_write_archdiag() {
  local target="$PREFIX/bin/archdiag"
  _write_shebang "$target"
  cat >> "$target" << 'EOF'
set -euo pipefail
CONF="$HOME/.config/termux-dev-env/config.env"
[ -f "$CONF" ] || { echo "termux-dev-env config not found — is it installed?"; exit 1; }
. "$CONF"
cd "$PREFIX/share/termux-dev-env" || { echo "termux-dev-env shared files not found — re-run phase 6 (./core.sh --reinstall=6)"; exit 1; }

source lib/error_handling.sh
source lib/logging.sh
log_init
source lib/kv.sh
source lib/state.sh

if [ "${1:-}" != "--quick" ]; then
  echo "=== Hardware/environment: then vs now ==="
  source lib/diagnose.sh
  CURRENT_FILE="$(mktemp)"
  {
    echo "RAM_TOTAL_MB=$(diagnose_ram_total_mb)"
    echo "RAM_AVAIL_MB=$(diagnose_ram_avail_mb)"
    echo "STORAGE_FREE_MB=$(diagnose_storage_free_mb)"
    echo "FS_TYPE=$(diagnose_fs_type)"
    echo "CPU_CORES=$(diagnose_cpu_cores)"
    echo "ANDROID_API=$(diagnose_android_api)"
  } > "$CURRENT_FILE"

  if diff "$TDE_DIAG_FILE" "$CURRENT_FILE" > "/tmp/archdiag_diff.$$"; then
    echo "No changes detected since install."
  else
    echo "Changes since install:"
    cat "/tmp/archdiag_diff.$$"
  fi
  rm -f "$CURRENT_FILE" "/tmp/archdiag_diff.$$"
  echo ""
fi

echo "=== Component health ==="
source lib/container_paths.sh
source components/install_rootfs.sh
source components/create_user.sh
source components/setup_launcher.sh
source components/dev_toolchain.sh
source components/shell_setup.sh
source components/lazyvim.sh
source lib/generate_report.sh
source lib/verify_functional.sh
phase5_run_audit

if [ "${1:-}" = "--quick" ]; then
  exit 0
fi

echo ""
echo "=== State flags ==="
cat "$TDE_STATE_FILE"
EOF
  chmod +x "$target"
}

phase6_write_archupdate() {
  local target="$PREFIX/bin/archupdate"
  _write_shebang "$target"
  cat >> "$target" << 'EOF'
set -euo pipefail
CONF="$HOME/.config/termux-dev-env/config.env"
[ -f "$CONF" ] || { echo "termux-dev-env config not found — is it installed?"; exit 1; }
. "$CONF"

SNAP_DIR="$HOME/.config/termux-dev-env/snapshots"
mkdir -p "$SNAP_DIR"

echo "Snapshotting installed packages..."
proot-distro login "$ARCH_DISTRO_ALIAS" -- pacman -Q > "$SNAP_DIR/packages_$(date +%Y%m%d_%H%M%S).txt"

if [ "${1:-}" = "--with-backup" ]; then
  echo "Creating full rootfs backup (can take a while, uses several GB)..."
  proot-distro backup "$ARCH_DISTRO_ALIAS" --output "$SNAP_DIR/rootfs_$(date +%Y%m%d_%H%M%S).tar.xz"
fi

echo "Updating system packages..."
proot-distro login "$ARCH_DISTRO_ALIAS" -- pacman -Syu --noconfirm

echo ""
echo "Re-checking system health after update..."
archhealth || echo "Update finished, but archhealth flagged an issue above — investigate before relying on the editor."
EOF
  chmod +x "$target"
}

phase6_write_archreset() {
  local target="$PREFIX/bin/archreset"
  _write_shebang "$target"
  cat >> "$target" << 'EOF'
set -euo pipefail
CONF="$HOME/.config/termux-dev-env/config.env"
[ -f "$CONF" ] || { echo "termux-dev-env config not found — is it installed?"; exit 1; }
. "$CONF"

STATE_FILE="$HOME/.config/termux-dev-env/state.env"

case "${1:-}" in
  --soft)
    echo "Removes the Arch Linux ARM container and reinstalls it, keeping bootstrap/diagnostics already validated. Continue? [y/N]"
    read -r c
    [ "$c" = "y" ] || exit 0
    proot-distro remove "$ARCH_DISTRO_ALIAS" 2>/dev/null || true
    if [ -f "$STATE_FILE" ]; then
      grep -Ev '^(PHASE3|PHASE4|PHASE5|ARCH_USERNAME)' "$STATE_FILE" > "$STATE_FILE.tmp" || true
      mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
    echo "Container removed. Run the installer again (cd $TDE_ROOT && ./core.sh) to reinstall from phase 3 onward."
    ;;
  --hard)
    echo "Removes EVERYTHING: the container, launcher, and all termux-dev-env state. Continue? [y/N]"
    read -r c
    [ "$c" = "y" ] || exit 0
    proot-distro remove "$ARCH_DISTRO_ALIAS" 2>/dev/null || true
    rm -rf "$HOME/.config/termux-dev-env"
    echo "Fully reset. Run the installer from scratch (cd $TDE_ROOT && ./core.sh)."
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
  cat >> "$target" << 'EOF'
set -euo pipefail
CONF="$HOME/.config/termux-dev-env/config.env"
[ -f "$CONF" ] || { echo "termux-dev-env config not found — is it installed?"; exit 1; }
. "$CONF"
cd "$PREFIX/share/termux-dev-env" || { echo "termux-dev-env shared files not found — re-run phase 6 (./core.sh --reinstall=6)"; exit 1; }

source lib/error_handling.sh
source lib/logging.sh
log_init
source lib/kv.sh
source lib/state.sh
source lib/idempotent_append.sh
source components/setup_launcher.sh

phase3_install_zshrc_snippet
phase3_install_archkill
echo "Launcher snippet and archkill reinstalled/verified."
EOF
  chmod +x "$target"
}

# openssh gives Termux the ssh CLIENT needed to reach back into a computer
# through an 'adb reverse' tunnel — this is the opposite direction from
# fs_utils.sh's optional sshd (which lets something connect INTO Arch).
phase6_install_bridge_deps() {
  log_info "Installing openssh (ssh client) in Termux for the ADB bridge"
  retry_with_backoff 3 5 pkg install -y openssh || \
    log_warn "Could not install openssh in Termux — archbridge will not work until this is retried"
}

# adb reverse itself must run on the computer (adb is a host-side tool
# connected to the phone over USB) — this script only handles the phone's
# side of the workflow: connecting through the tunnel once it exists.
phase6_write_archbridge() {
  local target="$PREFIX/bin/archbridge"
  _write_shebang "$target"
  cat >> "$target" << 'EOF'
set -euo pipefail
PORT="${1:-8022}"
REMOTE_USER="${2:-root}"
echo "Connecting to ${REMOTE_USER}@localhost:${PORT}"
echo "(if this fails: run 'adb devices' then 'adb reverse tcp:${PORT} tcp:22' on the computer first)"
exec ssh -p "$PORT" "${REMOTE_USER}@localhost"
EOF
  chmod +x "$target"
}

phase6_maintenance_ok() {
  local cmd
  for cmd in archhealth archdiag archupdate archreset archreapply archbridge; do
    [ -x "$PREFIX/bin/$cmd" ] || return 1
  done
  [ -d "$TDE_SHARE_DIR/lib" ] && [ -d "$TDE_SHARE_DIR/components" ]
}

phase6_install_maintenance_run() {
  log_info "=== Phase 6: maintenance commands ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would copy lib/+components/ to \$PREFIX/share/termux-dev-env, install archhealth, archdiag, archupdate, archreset, archreapply, archbridge to \$PREFIX/bin, install openssh in Termux"
    return 0
  fi

  phase6_install_shared_copy
  phase6_write_archhealth
  phase6_write_archdiag
  phase6_write_archupdate
  phase6_write_archreset
  phase6_write_archreapply
  phase6_install_bridge_deps
  phase6_write_archbridge
  log_info "Maintenance commands installed: archhealth, archdiag, archupdate, archreset, archreapply, archbridge"
}
