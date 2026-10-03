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
  # ${var:?} guard: if TDE_SHARE_DIR were ever empty (an unset PREFIX in a
  # future caller), the bare form would expand to "rm -rf /lib /components".
  rm -rf "${TDE_SHARE_DIR:?}/lib" "${TDE_SHARE_DIR:?}/components"
  # Source now lives under src/, but the installed copy keeps the flat
  # lib/ + components/ layout the generated commands expect — they cd
  # into $TDE_SHARE_DIR and `source lib/...`, so nothing in them has to
  # know about the repository's directory structure.
  cp -r "$TDE_SRC_DIR/lib" "$TDE_SHARE_DIR/lib"
  cp -r "$TDE_SRC_DIR/components" "$TDE_SHARE_DIR/components"
  cp "$TDE_ROOT/VERSION" "$TDE_SHARE_DIR/VERSION" 2>/dev/null || true
  cp "$TDE_SRC_DIR/core.sh" "$TDE_SHARE_DIR/core.sh" 2>/dev/null || true
  chmod +x "$TDE_SHARE_DIR/core.sh" 2>/dev/null || true
}

phase6_write_archhealth() {
  local target="$PREFIX/bin/archhealth"
  _write_shebang "$target"
  cat >> "$target" << 'EOF'
set -euo pipefail
CONF="$HOME/.config/termux-dev-env/config.env"
[ -f "$CONF" ] || { echo "termux-dev-env config not found — is it installed?"; exit 1; }
. "$CONF"
export TDE_DISTRO_NAME="${TDE_DISTRO_NAME:-${ARCH_DISTRO_ALIAS:-archarm}}"
cd "$PREFIX/share/termux-dev-env" || { echo "termux-dev-env shared files not found — re-run phase 6 (./core.sh --reinstall=6)"; exit 1; }

source lib/error_handling.sh
source lib/logging.sh
log_init
source lib/network.sh
source lib/kv.sh
source lib/state.sh
source lib/container_paths.sh
source lib/idempotent_append.sh
source components/install_rootfs.sh
source components/create_user.sh
source components/setup_launcher.sh
source components/dev_toolchain.sh
source components/shell_setup.sh
source components/lazyvim.sh
source components/telecom.sh
source components/nerdfonts.sh
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
export TDE_DISTRO_NAME="${TDE_DISTRO_NAME:-${ARCH_DISTRO_ALIAS:-archarm}}"
cd "$PREFIX/share/termux-dev-env" || { echo "termux-dev-env shared files not found — re-run phase 6 (./core.sh --reinstall=6)"; exit 1; }

source lib/error_handling.sh
source lib/logging.sh
log_init
source lib/network.sh
source lib/kv.sh
source lib/state.sh
source lib/idempotent_append.sh

# Last error code recorded by log_fatal_code (see docs/ERROR_CODES.md) —
# quote this in a bug report; it survives the terminal scrollback.
if [ -f "$TDE_CONFIG_DIR/last_error.env" ]; then
  echo "=== Last recorded error ==="
  cat "$TDE_CONFIG_DIR/last_error.env"
  echo ""
fi

if [ "${1:-}" != "--quick" ]; then
  echo "=== Hardware/environment: then vs now ==="
  source lib/diagnose.sh
  TDE_TMP_DIR="${TMPDIR:-${PREFIX:-/tmp}/tmp}"
  mkdir -p "$TDE_TMP_DIR"
  CURRENT_FILE="$(mktemp "$TDE_TMP_DIR/archdiag_current.XXXXXX")"
  DIFF_FILE="$(mktemp "$TDE_TMP_DIR/archdiag_diff.XXXXXX")"
  {
    echo "RAM_TOTAL_MB=$(diagnose_ram_total_mb)"
    echo "RAM_AVAIL_MB=$(diagnose_ram_avail_mb)"
    echo "STORAGE_FREE_MB=$(diagnose_storage_free_mb)"
    echo "FS_TYPE=$(diagnose_fs_type)"
    echo "CPU_CORES=$(diagnose_cpu_cores)"
    echo "ANDROID_API=$(diagnose_android_api)"
    echo "PROOT_FUNCTIONAL=$(diagnose_proot_functional)"
    echo "DIAG_TIMESTAMP=$(kv_get "$TDE_DIAG_FILE" DIAG_TIMESTAMP)"
  } > "$CURRENT_FILE"

  if diff "$TDE_DIAG_FILE" "$CURRENT_FILE" > "$DIFF_FILE"; then
    echo "No changes detected since install."
  else
    echo "Changes since install:"
    cat "$DIFF_FILE"
  fi
  rm -f "$CURRENT_FILE" "$DIFF_FILE"
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
source components/telecom.sh
source components/nerdfonts.sh
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
cd "$PREFIX/share/termux-dev-env" || { echo "termux-dev-env shared files not found — re-run phase 6 (./core.sh --reinstall=6)"; exit 1; }
source lib/error_handling.sh
source lib/logging.sh
log_init
source lib/network.sh

SNAP_DIR="$HOME/.config/termux-dev-env/snapshots"
mkdir -p "$SNAP_DIR"

echo "Snapshotting installed packages..."
proot-distro login "$ARCH_DISTRO_ALIAS" -- pacman -Q > "$SNAP_DIR/packages_$(date +%Y%m%d_%H%M%S).txt"

if [ "${1:-}" = "--with-backup" ]; then
  echo "Creating full rootfs backup (can take a while, uses several GB)..."
  proot-distro backup "$ARCH_DISTRO_ALIAS" --output "$SNAP_DIR/rootfs_$(date +%Y%m%d_%H%M%S).tar.xz"
fi

echo "Updating system packages..."
# Same reasoning as phase4_sync_and_install_toolchain — mobile networks
# drop mid-request often enough that a single pacman attempt isn't
# reliable, and archupdate hits the exact same mirror.archlinuxarm.org
# timeout mode as the initial install would.
retry_with_backoff 3 15 proot-distro login "$ARCH_DISTRO_ALIAS" -- pacman -Syu --noconfirm || {
  echo "pacman -Syu failed after 3 attempts — likely a network/mirror issue, see docs/TROUBLESHOOTING.md's 'mirror timeouts' section"
  exit 1
}

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
      grep -Ev '^(PHASE[3-6]|ARCH_USERNAME)' "$STATE_FILE" > "$STATE_FILE.tmp" || true
      mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
    echo "Container removed. Run the installer again ($PREFIX/share/termux-dev-env/core.sh) to reinstall from phase 3 onward."
    ;;
  --hard)
    echo "Removes EVERYTHING: the container, launcher, and all termux-dev-env state. Continue? [y/N]"
    read -r c
    [ "$c" = "y" ] || exit 0
    proot-distro remove "$ARCH_DISTRO_ALIAS" 2>/dev/null || true
    rm -rf "$HOME/.config/termux-dev-env"
    echo "Fully reset. Run the installer from scratch ($PREFIX/share/termux-dev-env/core.sh)."
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
export TDE_DISTRO_NAME="${TDE_DISTRO_NAME:-${ARCH_DISTRO_ALIAS:-archarm}}"
cd "$PREFIX/share/termux-dev-env" || { echo "termux-dev-env shared files not found — re-run phase 6 (./core.sh --reinstall=6)"; exit 1; }

source lib/error_handling.sh
source lib/logging.sh
log_init
source lib/kv.sh
source lib/state.sh
source lib/idempotent_append.sh
source lib/network.sh
source lib/container_paths.sh
source components/setup_launcher.sh

phase3_install_zshrc_snippet
phase3_install_archkill
# Also re-applies termux.properties, because that is what the warning
# about an emptied extra-keys row tells people to run. It never
# overwrites a row that is actually configured — see
# phase3_configure_termux_ui.
phase3_configure_termux_ui
echo "Launcher snippet, archkill and Termux UI settings reinstalled/verified."
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
exec ssh -o StrictHostKeyChecking=accept-new -p "$PORT" "${REMOTE_USER}@localhost"
EOF
  chmod +x "$target"
}

# Retries just the Nerd Font, without re-running an entire phase. The
# font is the component most likely to be missing on a finished install
# (a flaky mobile download, a truncated write) and the one people most
# want a one-liner for — it is referenced by name in nerdfonts.sh's own
# failure message.
phase6_write_archfont() {
  local target="$PREFIX/bin/archfont"
  _write_shebang "$target"
  cat >> "$target" << 'EOF'
set -euo pipefail
CONF="$HOME/.config/termux-dev-env/config.env"
[ -f "$CONF" ] || { echo "termux-dev-env config not found — is it installed?"; exit 1; }
. "$CONF"
export TDE_DISTRO_NAME="${TDE_DISTRO_NAME:-${ARCH_DISTRO_ALIAS:-archarm}}"
cd "$PREFIX/share/termux-dev-env" || { echo "termux-dev-env shared files not found — re-run phase 6 (./core.sh --reinstall=6)"; exit 1; }

source lib/error_handling.sh
source lib/logging.sh
log_init
source lib/network.sh
source lib/kv.sh
source lib/state.sh
source lib/container_paths.sh
source components/nerdfonts.sh

if [ "${1:-}" = "--force" ]; then
  rm -f "$HOME/.termux/font.ttf"
fi

if nerdfont_file_ok; then
  echo "A valid Nerd Font is already installed (~/.termux/font.ttf). Use 'archfont --force' to reinstall it."
  echo "If icons still show as boxes, force-stop Termux (Android Settings > Apps > Termux > Force stop) and reopen it."
  exit 0
fi

phase4_nerdfonts_run
EOF
  chmod +x "$target"
}

# Re-runs phase 5's self-heal + audit on demand, without the installer
# and without --reinstall=5. Self-heal used to be reachable only from
# inside a phase-5 run, so a component that failed after the install was
# finished had no supported way back.
phase6_write_archselfheal() {
  local target="$PREFIX/bin/archselfheal"
  _write_shebang "$target"
  cat >> "$target" << 'EOF'
set -euo pipefail
CONF="$HOME/.config/termux-dev-env/config.env"
[ -f "$CONF" ] || { echo "termux-dev-env config not found — is it installed?"; exit 1; }
. "$CONF"
export TDE_DISTRO_NAME="${TDE_DISTRO_NAME:-${ARCH_DISTRO_ALIAS:-archarm}}"
cd "$PREFIX/share/termux-dev-env" || { echo "termux-dev-env shared files not found — re-run phase 6 (./core.sh --reinstall=6)"; exit 1; }

source lib/error_handling.sh
source lib/logging.sh
log_init
source lib/network.sh
source lib/kv.sh
source lib/state.sh
source lib/container_paths.sh
source lib/idempotent_append.sh
source components/install_rootfs.sh
source components/create_user.sh
source components/setup_launcher.sh
source components/dev_toolchain.sh
source components/shell_setup.sh
source components/lazyvim.sh
source components/telecom.sh
source components/nerdfonts.sh
source lib/generate_report.sh
source lib/verify_functional.sh

echo "Re-running self-heal for recoverable components (Nerd Font, telecom if selected)..."
phase5_self_heal
echo ""
phase5_run_audit
echo ""
if [ "$TDE_AUDIT_HAD_CRITICAL_FAILURE" = "1" ]; then
  echo "STATUS: something critical is still broken — see $TDE_REPORT_FILE"
  exit 1
fi
if [ "${TDE_AUDIT_HAD_WARNING:-0}" = "1" ]; then
  echo "STATUS: usable, but optional components are still missing (see above)"
  exit 0
fi
# Nothing left to heal — let the installer stop re-running phase 5.
state_del PHASE5_WARNINGS
echo "STATUS: healthy"
EOF
  chmod +x "$target"
}

# paru is optional and non-blocking during the install, so a failed AUR
# helper leaves the environment working but without AUR access. This is
# the documented retry path (TROUBLESHOOTING.md pointed at a manual
# makepkg invocation that lib/cleanup.sh could previously delete).
phase6_write_archparu() {
  local target="$PREFIX/bin/archparu"
  _write_shebang "$target"
  cat >> "$target" << 'EOF'
set -euo pipefail
CONF="$HOME/.config/termux-dev-env/config.env"
[ -f "$CONF" ] || { echo "termux-dev-env config not found — is it installed?"; exit 1; }
. "$CONF"
export TDE_DISTRO_NAME="${TDE_DISTRO_NAME:-${ARCH_DISTRO_ALIAS:-archarm}}"
cd "$PREFIX/share/termux-dev-env" || { echo "termux-dev-env shared files not found — re-run phase 6 (./core.sh --reinstall=6)"; exit 1; }

source lib/error_handling.sh
source lib/logging.sh
log_init
source lib/network.sh
source lib/kv.sh
source lib/state.sh
source lib/container_paths.sh
source components/dev_toolchain.sh

USERNAME="$(state_get ARCH_USERNAME)"
[ -n "$USERNAME" ] || { echo "No ARCH_USERNAME recorded — run the installer first."; exit 1; }

if proot-distro login "$TDE_DISTRO_NAME" --user "$USERNAME" -- paru --version >/dev/null 2>&1; then
  echo "paru already works:"
  proot-distro login "$TDE_DISTRO_NAME" --user "$USERNAME" -- paru --version
  exit 0
fi

echo "paru is missing or not runnable — reinstalling (this may compile Rust and take a while)..."
phase4_install_paru
if proot-distro login "$TDE_DISTRO_NAME" --user "$USERNAME" -- paru --version >/dev/null 2>&1; then
  echo "paru is working now."
else
  echo "paru still does not run — see the log above and $TDE_LOG_FILE."
  exit 1
fi
EOF
  chmod +x "$target"
}

phase6_maintenance_ok() {
  local cmd
  for cmd in archhealth archdiag archupdate archreset archreapply archbridge archfont archselfheal archparu; do
    [ -x "$PREFIX/bin/$cmd" ] || return 1
  done
  [ -d "$TDE_SHARE_DIR/lib" ] && [ -d "$TDE_SHARE_DIR/components" ]
}

phase6_install_maintenance_run() {
  log_info "=== Phase 6: maintenance commands ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would copy lib/+components/ to \$PREFIX/share/termux-dev-env, install archhealth, archdiag, archupdate, archreset, archreapply, archbridge, archfont, archselfheal, archparu to \$PREFIX/bin, install openssh in Termux, re-assert the launcher snippet"
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
  phase6_install_bridge_deps
  phase6_write_archbridge

  # Re-assert the launcher block here, at the end of every install: it
  # is what makes a new Termux session enter Arch, and a person whose
  # .bashrc/.zshrc got edited (or whose phase 3 ran before a config
  # change) would otherwise have no way back short of --reinstall=3.
  # idempotent_append makes this a no-op when the block is already
  # correct. Guarded because phase 6 can run without phase 3's file
  # being sourced in this shell.
  if command -v phase3_install_zshrc_snippet >/dev/null 2>&1; then
    phase3_install_zshrc_snippet
    log_info "Launcher snippet re-asserted in .bashrc/.zshrc"
  fi

  log_info "Maintenance commands installed: archhealth, archdiag, archupdate, archreset, archreapply, archbridge, archfont, archselfheal, archparu"
}
