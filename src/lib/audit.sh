# Phase 5 — functional verification, self-healing, cache cleanup, and reporting.

[ -n "${TDE_AUDIT_LOADED:-}" ] && return 0
TDE_AUDIT_LOADED=1

TDE_REPORT_FILE="$HOME/.config/termux-dev-env/logs/install_report_$(date +%Y%m%d_%H%M%S).log"
export TDE_AUDIT_HAD_CRITICAL_FAILURE=0
export TDE_AUDIT_HAD_WARNING=0

TDE_ROOTFS_TMPDIR="${TDE_ROOTFS_TMPDIR:-$HOME/.cache/termux-dev-env/rootfs}"
TDE_NERDFONT_TMPDIR="${TDE_NERDFONT_TMPDIR:-$HOME/.cache/termux-dev-env/nerdfont}"

_audit_check() {
  local label="$1" severity_on_fail="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    echo "  [OK]       $label" | tee -a "$TDE_REPORT_FILE"
  else
    echo "  [$severity_on_fail] $label" | tee -a "$TDE_REPORT_FILE"
    if [ "$severity_on_fail" = "CRITICAL" ]; then
      export TDE_AUDIT_HAD_CRITICAL_FAILURE=1
    else
      export TDE_AUDIT_HAD_WARNING=1
    fi
  fi
  return 0
}

phase5_nerdfont_ok() {
  if command -v nerdfont_is_patched >/dev/null 2>&1; then
    nerdfont_is_patched "$HOME/.termux/font.ttf"
  elif command -v nerdfont_file_ok >/dev/null 2>&1; then
    nerdfont_file_ok "$HOME/.termux/font.ttf"
  else
    [ -f "$HOME/.termux/font.ttf" ] && [ "$(wc -c < "$HOME/.termux/font.ttf")" -gt 1000000 ]
  fi
}

phase5_self_heal() {
  if ! phase5_nerdfont_ok; then
    log_info "Self-heal: retrying Nerd Font installation"
    phase4_nerdfonts_run || log_warn "Self-heal did not fix the Nerd Font installation"
  fi
}

_cleanup_if() {
  local check_fn="$1" target="$2" label="$3"
  [ -e "$target" ] || return 0
  if "$check_fn" >/dev/null 2>&1; then
    rm -rf "$target"
    log_info "Cleaned up: $label"
  else
    log_warn "Kept (verification failed, preserved for debugging): $label"
  fi
}

phase5_cleanup() {
  _cleanup_if phase3_rootfs_ok "$TDE_ROOTFS_TMPDIR" "rootfs tarball + GPG key cache"
  _cleanup_if phase5_nerdfont_ok "$TDE_NERDFONT_TMPDIR" "Nerd Font download cache"

  local username
  username="$(state_get ARCH_USERNAME)"
  if [ -n "$username" ] && \
     proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- paru --version >/dev/null 2>&1; then
    proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- rm -rf /tmp/paru-bin /tmp/paru 2>/dev/null || true
    log_info "Cleaned up: paru build directories inside container"
  elif [ -n "$username" ]; then
    log_warn "Kept (paru does not run — preserved so 'archparu' can retry): /tmp/paru-bin"
  fi
}

phase5_run_audit() {
  mkdir -p "$(dirname "$TDE_REPORT_FILE")"
  export TDE_AUDIT_HAD_CRITICAL_FAILURE=0
  export TDE_AUDIT_HAD_WARNING=0

  {
    echo "=== termux-dev-env install report — $(date) ==="
    echo "Critical components:"
  } | tee -a "$TDE_REPORT_FILE"

  _audit_check "Rootfs (Arch Linux ARM)"   CRITICAL phase3_rootfs_ok
  _audit_check "User account + sudo"       CRITICAL phase3_user_ok
  _audit_check "Launcher"                  CRITICAL phase3_launcher_ok
  _audit_check "Dev toolchain (gcc/git)"   CRITICAL phase4_toolchain_ok
  _audit_check "Shell (zsh + UTF-8)"       CRITICAL phase4_shell_ok
  _audit_check "LazyVim"                   CRITICAL phase4_lazyvim_ok

  echo "Visual & optional components:" | tee -a "$TDE_REPORT_FILE"
  _audit_check "Nerd Font (Patched Mono)"  WARNING  phase5_nerdfont_ok
  if ! phase5_nerdfont_ok >/dev/null 2>&1; then
    echo "           Run: archfont --force   then force-stop Termux from Android Settings and reopen it." | tee -a "$TDE_REPORT_FILE"
  fi
}

phase5_print_summary() {
  echo "" | tee -a "$TDE_REPORT_FILE"
  if [ "$TDE_AUDIT_HAD_CRITICAL_FAILURE" = "1" ]; then
    echo "STATUS: NOT READY — a critical component failed verification. Report: $TDE_REPORT_FILE" | tee -a "$TDE_REPORT_FILE"
    log_fatal "Phase 5 audit found a critical failure — see the report above"
  else
    echo "STATUS: READY TO USE" | tee -a "$TDE_REPORT_FILE"
    log_info "Full report: $TDE_REPORT_FILE"
  fi
}

phase5_run() {
  log_info "=== Phase 5: final audit, self-heal, cleanup, report ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would self-heal recoverable failures, audit every component, clean up verified temp files, write the final report"
    return 0
  fi

  phase5_self_heal
  phase5_run_audit
  phase5_cleanup
  phase5_print_summary
}