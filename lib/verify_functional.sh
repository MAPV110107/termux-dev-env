# Phase 5 — final audit. Order matters: self-heal runs BEFORE the audit
# that gets recorded, so the report reflects the post-heal state instead
# of a transient failure that a retry would have fixed anyway.

[ -n "${TDE_VERIFY_FUNCTIONAL_LOADED:-}" ] && return 0
TDE_VERIFY_FUNCTIONAL_LOADED=1

phase5_nerdfont_ok() { [ -f "$HOME/.termux/font.ttf" ]; }

phase5_rns_ok() {
  local username
  username="$(state_get ARCH_USERNAME)"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- command -v rnsd >/dev/null 2>&1
}

phase5_aria2_ok() {
  proot-distro login "$TDE_DISTRO_NAME" -- command -v aria2c >/dev/null 2>&1
}

# Only touches non-critical, best-effort components. Critical infra is
# never silently retried here — if it's broken, the audit below reports
# it plainly instead of spending time on an automatic fix that might mask
# a deeper problem.
phase5_self_heal() {
  if ! phase5_nerdfont_ok; then
    log_info "Self-heal: retrying Nerd Font install"
    phase4_nerdfonts_run || log_warn "Self-heal did not fix the Nerd Font install"
  fi
  if ! phase5_rns_ok || ! phase5_aria2_ok; then
    log_info "Self-heal: retrying telecom install"
    phase4_telecom_run || log_warn "Self-heal did not fully fix telecom"
  fi
}

phase5_run_audit() {
  mkdir -p "$(dirname "$TDE_REPORT_FILE")"
  {
    echo "=== termux-dev-env install report — $(date) ==="
    echo "Critical components:"
  } | tee -a "$TDE_REPORT_FILE"

  _audit_check "Rootfs (Arch Linux ARM)"      CRITICAL phase3_rootfs_ok
  _audit_check "User account + sudo"          CRITICAL phase3_user_ok
  _audit_check "Launcher"                     CRITICAL phase3_launcher_ok
  _audit_check "Dev toolchain (gcc/git/paru)" CRITICAL phase4_toolchain_ok
  _audit_check "Shell (zsh default)"          CRITICAL phase4_shell_ok
  _audit_check "LazyVim"                      CRITICAL phase4_lazyvim_ok

  echo "Optional components:" | tee -a "$TDE_REPORT_FILE"
  _audit_check "Nerd Font"               WARNING phase5_nerdfont_ok
  _audit_check "Reticulum/Nomad Network" WARNING phase5_rns_ok
  _audit_check "aria2"                   WARNING phase5_aria2_ok
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
