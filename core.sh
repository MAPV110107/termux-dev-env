#!/usr/bin/env bash
# termux-dev-env entry point. Reads state.env to resume from the last
# completed phase instead of re-running everything on every invocation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TDE_ROOT="$SCRIPT_DIR"
export TDE_ROOT
export TDE_DISTRO_NAME="archarm"

# shellcheck source=lib/error_handling.sh
source "$SCRIPT_DIR/lib/error_handling.sh"
# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
# shellcheck source=lib/network.sh
source "$SCRIPT_DIR/lib/network.sh"
# shellcheck source=lib/lock.sh
source "$SCRIPT_DIR/lib/lock.sh"
# shellcheck source=lib/kv.sh
source "$SCRIPT_DIR/lib/kv.sh"
# shellcheck source=lib/state.sh
source "$SCRIPT_DIR/lib/state.sh"

log_init
lock_acquire
trap lock_release EXIT

state_init

TDE_DRY_RUN=0
for arg in "$@"; do
  [ "$arg" = "--dry-run" ] && TDE_DRY_RUN=1
done
export TDE_DRY_RUN

log_info "termux-dev-env v$(cat "$TDE_ROOT/VERSION" 2>/dev/null || echo "unknown") starting"
[ "$TDE_DRY_RUN" = "1" ] && log_info "dry-run mode: no changes will be made"

if [ "$(state_get PHASE1_DONE)" != "1" ]; then
  # shellcheck source=lib/validate_env.sh
  source "$SCRIPT_DIR/lib/validate_env.sh"
  phase1_run
  state_set PHASE1_DONE 1
else
  log_info "Phase 1 already completed, skipping"
fi

if [ "$(state_get PHASE2_DONE)" != "1" ]; then
  # shellcheck source=lib/compat_matrix.sh
  source "$SCRIPT_DIR/lib/compat_matrix.sh"
  # shellcheck source=lib/diagnose.sh
  source "$SCRIPT_DIR/lib/diagnose.sh"
  phase2_run
  state_set PHASE2_DONE 1
else
  log_info "Phase 2 already completed, skipping"
fi

log_info "Phase 2 complete."

if [ "$(state_get PHASE3_DONE)" != "1" ]; then
  if [ "$(state_get PHASE3_ROOTFS_INSTALLED)" != "1" ]; then
    # shellcheck source=components/install_rootfs.sh
    source "$SCRIPT_DIR/components/install_rootfs.sh"
    phase3_install_rootfs_run
    if [ "$TDE_DRY_RUN" = "1" ] || phase3_rootfs_ok; then
      state_set PHASE3_ROOTFS_INSTALLED 1
    else
      log_fatal "Rootfs install did not pass its post-condition check"
    fi
  fi
  if [ "$(state_get PHASE3_USER_CREATED)" != "1" ]; then
    # shellcheck source=components/create_user.sh
    source "$SCRIPT_DIR/components/create_user.sh"
    phase3_create_user_run
    if [ "$TDE_DRY_RUN" = "1" ] || phase3_user_ok; then
      state_set PHASE3_USER_CREATED 1
    else
      log_fatal "User creation did not pass its post-condition check"
    fi
  fi
  if [ "$(state_get PHASE3_LAUNCHER_SETUP)" != "1" ]; then
    # shellcheck source=components/setup_launcher.sh
    source "$SCRIPT_DIR/components/setup_launcher.sh"
    phase3_setup_launcher_run
    if [ "$TDE_DRY_RUN" = "1" ] || phase3_launcher_ok; then
      state_set PHASE3_LAUNCHER_SETUP 1
    else
      log_fatal "Launcher setup did not pass its post-condition check"
    fi
  fi
  state_set PHASE3_DONE 1
else
  log_info "Phase 3 already completed, skipping"
fi

log_info "Phase 3 complete."

if [ "$(state_get PHASE4_DONE)" != "1" ]; then
  # shellcheck source=lib/container_paths.sh
  source "$SCRIPT_DIR/lib/container_paths.sh"
  # shellcheck source=lib/idempotent_append.sh
  source "$SCRIPT_DIR/lib/idempotent_append.sh"

  if [ "$(state_get PHASE4_TOOLCHAIN)" != "1" ]; then
    # shellcheck source=components/dev_toolchain.sh
    source "$SCRIPT_DIR/components/dev_toolchain.sh"
    phase4_dev_toolchain_run
    if [ "$TDE_DRY_RUN" = "1" ] || phase4_toolchain_ok; then
      state_set PHASE4_TOOLCHAIN 1
    else
      log_fatal "Toolchain did not pass its post-condition check"
    fi
  fi
  if [ "$(state_get PHASE4_FONTS)" != "1" ]; then
    # shellcheck source=components/nerdfonts.sh
    source "$SCRIPT_DIR/components/nerdfonts.sh"
    if phase4_nerdfonts_run; then
      state_set PHASE4_FONTS 1
    else
      log_warn "Font install incomplete — will retry on the next run"
    fi
  fi
  if [ "$(state_get PHASE4_SHELL)" != "1" ]; then
    # shellcheck source=components/shell_setup.sh
    source "$SCRIPT_DIR/components/shell_setup.sh"
    phase4_shell_setup_run
    if [ "$TDE_DRY_RUN" = "1" ] || phase4_shell_ok; then
      state_set PHASE4_SHELL 1
    else
      log_fatal "Shell setup did not pass its post-condition check"
    fi
  fi
  if [ "$(state_get PHASE4_LAZYVIM)" != "1" ]; then
    # shellcheck source=components/lazyvim.sh
    source "$SCRIPT_DIR/components/lazyvim.sh"
    phase4_lazyvim_run
    if [ "$TDE_DRY_RUN" = "1" ] || phase4_lazyvim_ok; then
      state_set PHASE4_LAZYVIM 1
    else
      log_fatal "LazyVim did not pass its post-condition check"
    fi
  fi
  if [ "$(state_get PHASE4_TELECOM)" != "1" ]; then
    # shellcheck source=components/telecom.sh
    source "$SCRIPT_DIR/components/telecom.sh"
    if phase4_telecom_run; then
      state_set PHASE4_TELECOM 1
    else
      log_warn "Telecom step incomplete — will retry on the next run"
    fi
  fi
  if [ "$(state_get PHASE4_FSUTILS)" != "1" ]; then
    # shellcheck source=components/fs_utils.sh
    source "$SCRIPT_DIR/components/fs_utils.sh"
    phase4_fs_utils_run
    state_set PHASE4_FSUTILS 1
  fi
  state_set PHASE4_DONE 1
else
  log_info "Phase 4 already completed, skipping"
fi

log_info "Phase 4 complete."

if [ "$(state_get PHASE5_DONE)" != "1" ]; then
  # shellcheck source=components/install_rootfs.sh
  source "$SCRIPT_DIR/components/install_rootfs.sh"
  # shellcheck source=components/create_user.sh
  source "$SCRIPT_DIR/components/create_user.sh"
  # shellcheck source=components/setup_launcher.sh
  source "$SCRIPT_DIR/components/setup_launcher.sh"
  # shellcheck source=lib/container_paths.sh
  source "$SCRIPT_DIR/lib/container_paths.sh"
  # shellcheck source=lib/idempotent_append.sh
  source "$SCRIPT_DIR/lib/idempotent_append.sh"
  # shellcheck source=components/dev_toolchain.sh
  source "$SCRIPT_DIR/components/dev_toolchain.sh"
  # shellcheck source=components/nerdfonts.sh
  source "$SCRIPT_DIR/components/nerdfonts.sh"
  # shellcheck source=components/shell_setup.sh
  source "$SCRIPT_DIR/components/shell_setup.sh"
  # shellcheck source=components/lazyvim.sh
  source "$SCRIPT_DIR/components/lazyvim.sh"
  # shellcheck source=components/telecom.sh
  source "$SCRIPT_DIR/components/telecom.sh"
  # shellcheck source=lib/generate_report.sh
  source "$SCRIPT_DIR/lib/generate_report.sh"
  # shellcheck source=lib/cleanup.sh
  source "$SCRIPT_DIR/lib/cleanup.sh"
  # shellcheck source=lib/verify_functional.sh
  source "$SCRIPT_DIR/lib/verify_functional.sh"

  phase5_run
  state_set PHASE5_DONE 1
else
  log_info "Phase 5 already completed, skipping"
fi

log_info "Phase 5 complete."

if [ "$(state_get PHASE6_DONE)" != "1" ]; then
  # shellcheck source=components/install_maintenance.sh
  source "$SCRIPT_DIR/components/install_maintenance.sh"
  phase6_install_maintenance_run
  if [ "$TDE_DRY_RUN" = "1" ] || phase6_maintenance_ok; then
    state_set PHASE6_DONE 1
  else
    log_fatal "Maintenance command install did not pass its post-condition check"
  fi
else
  log_info "Phase 6 already completed, skipping"
fi

log_info "termux-dev-env: installation complete. Maintenance commands available: archhealth, archdiag, archupdate, archreset, archreapply."
