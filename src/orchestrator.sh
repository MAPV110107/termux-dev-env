#!/usr/bin/env bash
# termux-dev-env orchestrator. Coordinates the 6 installation phases with
# state persistence, config migration, and automatic container handoff.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TDE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TDE_SRC_DIR="$SCRIPT_DIR"
export TDE_ROOT TDE_SRC_DIR
export TDE_DISTRO_NAME="${TDE_DISTRO_NAME:-archarm}"
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export TMPDIR="${TMPDIR:-$PREFIX/tmp}"
mkdir -p "$TMPDIR" 2>/dev/null || true

# shellcheck source=lib/core.sh
source "$SCRIPT_DIR/lib/core.sh"
# shellcheck source=lib/state.sh
source "$SCRIPT_DIR/lib/state.sh"
# shellcheck source=lib/lock.sh
source "$SCRIPT_DIR/lib/lock.sh"
# shellcheck source=lib/system.sh
source "$SCRIPT_DIR/lib/system.sh"

log_init
lock_acquire
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock 2>/dev/null || true
_core_cleanup() {
  lock_release
  command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock 2>/dev/null || true
}
trap _core_cleanup EXIT

state_init

TDE_DRY_RUN=0
TDE_REINSTALL_PHASE=""
for arg in "$@"; do
  case "$arg" in
    --dry-run)        TDE_DRY_RUN=1 ;;
    --reinstall=*)    TDE_REINSTALL_PHASE="${arg#--reinstall=}" ;;
    --with-rust)      export TDE_WITH_RUST=1 ;;
    --with-go)        export TDE_WITH_GO=1 ;;
    --with-clang)     export TDE_WITH_CLANG=1 ;;
    --full-treesitter) export TDE_TREESITTER_FULL=1 ;;
  esac
done
export TDE_DRY_RUN

if [ -n "$TDE_REINSTALL_PHASE" ]; then
  case "$TDE_REINSTALL_PHASE" in
    1|2|3|4|5|6)
      if [ "$TDE_DRY_RUN" = "1" ]; then
        log_info "[dry-run] would clear state for phase $TDE_REINSTALL_PHASE and every phase after it"
      else
        local_phase="$TDE_REINSTALL_PHASE"
        while [ "$local_phase" -le 6 ]; do
          state_clear_prefix "PHASE${local_phase}"
          [ "$local_phase" -le 3 ] && state_del "ARCH_USERNAME"
          [ "$local_phase" -le 1 ] && state_del "SHIZUKU_AVAILABLE"
          local_phase=$((local_phase + 1))
        done
        log_info "Cleared state for phase $TDE_REINSTALL_PHASE onward"
      fi
      ;;
    *) log_fatal_code 100 "Invalid --reinstall value: '$TDE_REINSTALL_PHASE' (must be 1-6)" ;;
  esac
fi

TDE_VERSION="$(cat "$TDE_ROOT/VERSION" 2>/dev/null || echo "1.0.0")"
export TDE_VERSION
log_info "termux-dev-env v${TDE_VERSION} starting"

_tde_migrate_config() {
  local previous
  previous="$(state_get INSTALLED_VERSION)"
  [ "$previous" = "$TDE_VERSION" ] && return 0
  if [ -n "$previous" ]; then
    log_info "Version changed ($previous -> $TDE_VERSION) — refreshing launcher, shell blocks, and maintenance CLI"
    state_del PHASE3_LAUNCHER_SETUP
    state_del PHASE4_SHELL
    state_del PHASE6_DONE
  fi
  state_set INSTALLED_VERSION "$TDE_VERSION"
}
_tde_migrate_config
[ "$TDE_DRY_RUN" = "1" ] && log_info "dry-run mode: no changes will be written"

# --- Phase 1 & 2: Validation & Diagnostics ---
if [ "$(state_get PHASE1_DONE)" != "1" ] || [ "$(state_get PHASE2_DONE)" != "1" ]; then
  # shellcheck source=lib/validate.sh
  source "$SCRIPT_DIR/lib/validate.sh"
fi

if [ "$(state_get PHASE1_DONE)" != "1" ]; then
  phase1_run
  state_set PHASE1_DONE 1
else
  log_info "Phase 1 already completed, skipping"
fi

if [ "$(state_get PHASE2_DONE)" != "1" ]; then
  phase2_run
  state_set PHASE2_DONE 1
else
  log_info "Phase 2 already completed, skipping"
fi

# --- Phase 3: Rootfs, User & Termux Launcher ---
if [ "$(state_get PHASE3_ROOTFS_INSTALLED)" != "1" ]; then
  # shellcheck source=modules/rootfs.sh
  source "$SCRIPT_DIR/modules/rootfs.sh"
  phase3_install_rootfs_run
  if [ "$TDE_DRY_RUN" = "1" ] || phase3_rootfs_ok; then
    state_set PHASE3_ROOTFS_INSTALLED 1
  else
    log_fatal_code 301 "Rootfs install did not pass its post-condition check"
  fi
fi

if [ "$(state_get PHASE3_USER_CREATED)" != "1" ]; then
  # shellcheck source=modules/user.sh
  source "$SCRIPT_DIR/modules/user.sh"
  phase3_create_user_run
  if [ "$TDE_DRY_RUN" = "1" ] || phase3_user_ok; then
    state_set PHASE3_USER_CREATED 1
  else
    log_fatal_code 302 "User creation did not pass its post-condition check"
  fi
fi

if [ "$(state_get PHASE3_LAUNCHER_SETUP)" != "1" ]; then
  # shellcheck source=modules/launcher.sh
  source "$SCRIPT_DIR/modules/launcher.sh"
  phase3_setup_launcher_run
  if [ "$TDE_DRY_RUN" = "1" ] || phase3_launcher_ok; then
    state_set PHASE3_LAUNCHER_SETUP 1
  else
    log_fatal_code 303 "Launcher setup did not pass its post-condition check"
  fi
fi
state_set PHASE3_DONE 1

# --- Phase 4: Toolchain, Nerd Fonts, Shell & LazyVim ---
if [ "$(state_get PHASE4_TOOLCHAIN)" != "1" ]; then
  # shellcheck source=modules/toolchain.sh
  source "$SCRIPT_DIR/modules/toolchain.sh"
  phase4_dev_toolchain_run
  if [ "$TDE_DRY_RUN" = "1" ] || phase4_toolchain_ok; then
    state_set PHASE4_TOOLCHAIN 1
  else
    log_fatal_code 401 "Toolchain did not pass its post-condition check"
  fi
fi

if [ "$(state_get PHASE4_FONTS)" != "1" ]; then
  # shellcheck source=modules/nerdfonts.sh
  source "$SCRIPT_DIR/modules/nerdfonts.sh"
  if phase4_nerdfonts_run; then
    state_set PHASE4_FONTS 1
  else
    log_warn "Nerd Font install incomplete — will retry during Phase 5 self-heal"
  fi
fi

if [ "$(state_get PHASE4_SHELL)" != "1" ]; then
  # shellcheck source=modules/shell.sh
  source "$SCRIPT_DIR/modules/shell.sh"
  phase4_shell_setup_run
  if [ "$TDE_DRY_RUN" = "1" ] || phase4_shell_ok; then
    state_set PHASE4_SHELL 1
  else
    log_fatal_code 402 "Shell setup did not pass its post-condition check"
  fi
fi

if [ "$(state_get PHASE4_LAZYVIM)" != "1" ]; then
  # shellcheck source=modules/neovim.sh
  source "$SCRIPT_DIR/modules/neovim.sh"
  phase4_lazyvim_run
  if [ "$TDE_DRY_RUN" = "1" ] || phase4_lazyvim_ok; then
    state_set PHASE4_LAZYVIM 1
  else
    log_fatal_code 403 "LazyVim did not pass its post-condition check"
  fi
fi
state_set PHASE4_DONE 1

# --- Phase 5: Audit, Self-Heal & Cleanup ---
if [ "$(state_get PHASE5_DONE)" != "1" ] || \
   { [ "$(state_get PHASE5_WARNINGS)" = "1" ] && [ -z "${TDE_NO_SELF_HEAL:-}" ]; }; then
  # shellcheck source=modules/rootfs.sh
  source "$SCRIPT_DIR/modules/rootfs.sh"
  # shellcheck source=modules/user.sh
  source "$SCRIPT_DIR/modules/user.sh"
  # shellcheck source=modules/launcher.sh
  source "$SCRIPT_DIR/modules/launcher.sh"
  # shellcheck source=modules/toolchain.sh
  source "$SCRIPT_DIR/modules/toolchain.sh"
  # shellcheck source=modules/nerdfonts.sh
  source "$SCRIPT_DIR/modules/nerdfonts.sh"
  # shellcheck source=modules/shell.sh
  source "$SCRIPT_DIR/modules/shell.sh"
  # shellcheck source=modules/neovim.sh
  source "$SCRIPT_DIR/modules/neovim.sh"
  # shellcheck source=lib/audit.sh
  source "$SCRIPT_DIR/lib/audit.sh"

  phase5_run
  state_set PHASE5_DONE 1
  if [ "${TDE_AUDIT_HAD_WARNING:-0}" = "1" ]; then
    state_set PHASE5_WARNINGS 1
    log_info "Phase 5 finished with recoverable warnings — run 'archselfheal' or 'archfont --force' if needed"
  else
    state_del PHASE5_WARNINGS
  fi
else
  log_info "Phase 5 already completed cleanly, skipping"
fi

# --- Phase 6: Maintenance Commands ---
if [ "$(state_get PHASE6_DONE)" != "1" ]; then
  # shellcheck source=modules/launcher.sh
  source "$SCRIPT_DIR/modules/launcher.sh"
  # shellcheck source=modules/maintenance.sh
  source "$SCRIPT_DIR/modules/maintenance.sh"
  phase6_install_maintenance_run
  if [ "$TDE_DRY_RUN" = "1" ] || phase6_maintenance_ok; then
    state_set PHASE6_DONE 1
  else
    log_fatal_code 601 "Maintenance command install did not pass its post-condition check"
  fi
else
  log_info "Phase 6 already completed, skipping"
fi

log_info "termux-dev-env: installation complete. Commands: archhealth, archdiag, archselfheal, archupdate, archreset, archreapply, archfont, archparu, archtreesitter, archbridge."
log_info "Note: On your first interactive 'nvim' launch, Mason will automatically install the configured LSP servers."

if [ "$TDE_DRY_RUN" != "1" ] && [ -z "${TDE_NO_AUTO_RESTART:-}" ] && [ -t 0 ] && [ -t 1 ]; then
  log_info "Entering Arch Linux ARM in 3s (Ctrl+C to stay in Termux)..."
  sleep 3
  lock_release
  command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock 2>/dev/null || true
  eval "exec ${TDE_LOCK_FD}>&-"
  printf '\033c'
  exec "${SHELL:-bash}" -l
fi