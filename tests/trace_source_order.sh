#!/usr/bin/env bash
# Reproduces core.sh's exact source sequence and, at each point a function
# would be called, verifies it's actually defined yet. This is the test
# that would have caught the idempotent_append ordering bug — isolated
# function tests can't see it because they source whatever they need
# manually, masking real source-order problems in core.sh itself.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
export TDE_ROOT="$SCRIPT_DIR"
export TDE_DISTRO_NAME="archarm"
export PREFIX="/tmp/trace_test/usr"
export HOME="/tmp/trace_test/home"
mkdir -p "$PREFIX/bin" "$HOME"

FAILURES=0
check() {
  local fn="$1" after="$2"
  if declare -F "$fn" >/dev/null; then
    echo "  OK    $fn (available after: $after)"
  else
    echo "  MISSING  $fn — NOT defined after sourcing: $after"
    FAILURES=$((FAILURES + 1))
  fi
}

echo "=== Level 0 ==="
source "$SCRIPT_DIR/lib/error_handling.sh"
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/network.sh"
source "$SCRIPT_DIR/lib/lock.sh"
source "$SCRIPT_DIR/lib/kv.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/container_paths.sh"
source "$SCRIPT_DIR/lib/idempotent_append.sh"
check retry_with_backoff "network.sh"
check kv_get "kv.sh"
check state_get "state.sh"
check container_home "container_paths.sh"
check idempotent_append "idempotent_append.sh"

echo ""
echo "=== Phase 1 ==="
source "$SCRIPT_DIR/lib/validate_env.sh"
check phase1_run "validate_env.sh"
check _prompt "validate_env.sh"

echo ""
echo "=== Phase 2 ==="
source "$SCRIPT_DIR/lib/compat_matrix.sh"
source "$SCRIPT_DIR/lib/diagnose.sh"
check phase2_run "compat_matrix.sh + diagnose.sh"
check compat_evaluate "compat_matrix.sh"

echo ""
echo "=== Phase 3, step 1 (rootfs) ==="
source "$SCRIPT_DIR/components/install_rootfs.sh"
check phase3_install_rootfs_run "install_rootfs.sh"
check phase3_rootfs_ok "install_rootfs.sh"

echo ""
echo "=== Phase 3, step 2 (user) ==="
source "$SCRIPT_DIR/components/create_user.sh"
check phase3_create_user_run "create_user.sh"
check phase3_user_ok "create_user.sh"

echo ""
echo "=== Phase 3, step 3 (launcher) — THIS is where the bug was ==="
source "$SCRIPT_DIR/components/setup_launcher.sh"
check phase3_setup_launcher_run "setup_launcher.sh"
check phase3_launcher_ok "setup_launcher.sh"
# setup_launcher.sh's own functions call idempotent_append and
# retry_with_backoff internally — verify those are ALREADY available
# at this exact point in the sequence (they must be, from Level 0 above)
check idempotent_append "Level 0 (must already be loaded before phase 3 runs)"
check retry_with_backoff "Level 0 (must already be loaded before phase 3 runs)"

echo ""
echo "=== Phase 4, step 1 (toolchain) ==="
source "$SCRIPT_DIR/components/dev_toolchain.sh"
check phase4_dev_toolchain_run "dev_toolchain.sh"
check phase4_toolchain_ok "dev_toolchain.sh"
check _prompt "Level 0/Phase 1 (dev_toolchain.sh's git identity prompt needs this)"

echo ""
echo "=== Phase 4, step 2 (fonts) ==="
source "$SCRIPT_DIR/components/nerdfonts.sh"
check phase4_nerdfonts_run "nerdfonts.sh"

echo ""
echo "=== Phase 4, step 3 (shell) ==="
source "$SCRIPT_DIR/components/shell_setup.sh"
check phase4_shell_setup_run "shell_setup.sh"
check phase4_shell_ok "shell_setup.sh"
check idempotent_append "Level 0 (shell_setup.sh's tmux/PROOT_ACTIVE append needs this)"

echo ""
echo "=== Phase 4, step 4 (lazyvim) ==="
source "$SCRIPT_DIR/components/lazyvim.sh"
check phase4_lazyvim_run "lazyvim.sh"
check phase4_lazyvim_ok "lazyvim.sh"
check container_home "Level 0 (lazyvim.sh needs this for every config write)"

echo ""
echo "=== Phase 4, step 5 (telecom) ==="
source "$SCRIPT_DIR/components/telecom.sh"
check phase4_telecom_run "telecom.sh"

echo ""
echo "=== Phase 4, step 6 (fs_utils) ==="
source "$SCRIPT_DIR/components/fs_utils.sh"
check phase4_fs_utils_run "fs_utils.sh"
check _prompt "Level 0/Phase 1 (fs_utils.sh's ssh prompt needs this)"

echo ""
echo "=== Phase 5 (re-sources everything defensively, then its own libs) ==="
source "$SCRIPT_DIR/lib/generate_report.sh"
source "$SCRIPT_DIR/lib/cleanup.sh"
source "$SCRIPT_DIR/lib/verify_functional.sh"
check phase5_run "verify_functional.sh"
check _audit_check "generate_report.sh"
check _cleanup_if "cleanup.sh"

echo ""
echo "=== Phase 6 ==="
source "$SCRIPT_DIR/components/install_maintenance.sh"
check phase6_install_maintenance_run "install_maintenance.sh"
check phase6_maintenance_ok "install_maintenance.sh"

echo ""
echo "================================================"
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL CHECKS PASSED — no function is called before it's sourced."
else
  echo "$FAILURES CHECK(S) FAILED — source-order bug(s) present."
fi
echo "================================================"
rm -rf /tmp/trace_test
exit "$FAILURES"
