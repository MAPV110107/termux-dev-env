# Phase 5 — final audit. Order matters: self-heal runs BEFORE the audit
# that gets recorded, so the report reflects the post-heal state instead
# of a transient failure that a retry would have fixed anyway.

[ -n "${TDE_VERIFY_FUNCTIONAL_LOADED:-}" ] && return 0
TDE_VERIFY_FUNCTIONAL_LOADED=1

# Delegates to nerdfont_file_ok (components/nerdfonts.sh), which checks
# size AND TrueType/OpenType magic bytes — a truncated font.ttf passes a
# bare -f check but renders nothing, and Termux falls back silently with
# no error either way. The inline fallback keeps this usable if only
# this file is sourced (nerdfonts.sh is always sourced alongside it by
# core.sh phase 5, archhealth and archdiag).
phase5_nerdfont_ok() {
  if command -v nerdfont_file_ok >/dev/null 2>&1; then
    nerdfont_file_ok "$HOME/.termux/font.ttf"
  else
    [ -f "$HOME/.termux/font.ttf" ] && [ "$(wc -c < "$HOME/.termux/font.ttf")" -gt 102400 ]
  fi
}

# Was the telecom stack actually asked for? Reads the environment and
# the recorded answer directly instead of calling phase4_telecom_wanted,
# which can prompt — the audit and the self-heal must never block on a
# question, and archhealth/archdiag run non-interactively.
phase5_telecom_selected() {
  [ "${TDE_SKIP_TELECOM:-0}" = "1" ] && return 1
  [ "${TDE_WITH_TELECOM:-0}" = "1" ] && return 0
  [ "$(state_get TELECOM_WANTED)" = "1" ]
}

phase5_rns_ok() {
  local username
  username="$(state_get ARCH_USERNAME)"
  [ -n "$username" ] || return 1
  # rnsd can land in ~/.local/bin (the pip --user fallback in
  # telecom.sh's phase4_install_rns_nomadnet) or in the normal
  # pacman/system PATH (the paru/AUR path) — a bare, non-interactive
  # 'proot-distro login --user -- command -v rnsd' doesn't source
  # .zshrc's PATH additions (those only apply to an interactive shell),
  # so it only ever sees the second case. Prepend it explicitly instead
  # of depending on login sourcing anything.
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    sh -c 'PATH="$HOME/.local/bin:$PATH" command -v rnsd >/dev/null 2>&1'
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
  # Gated the same way core.sh's own Phase 4 step is: telecom is opt-in
  # (TDE_WITH_TELECOM=1). Without this, self-heal would try installing
  # it even for someone who never asked for it in the first place, since
  # phase5_rns_ok/phase5_aria2_ok naturally read as "not ok" when it was
  # never installed at all.
  if phase5_telecom_selected && { ! phase5_rns_ok || ! phase5_aria2_ok; }; then
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
  # Label matches what phase4_toolchain_ok actually requires: paru is
  # optional and non-blocking (see components/dev_toolchain.sh), so
  # naming it here made a passing check look like it had verified paru.
  _audit_check "Dev toolchain (gcc/git)"      CRITICAL phase4_toolchain_ok
  _audit_check "Shell (zsh default)"          CRITICAL phase4_shell_ok
  _audit_check "LazyVim"                      CRITICAL phase4_lazyvim_ok

  echo "Optional components:" | tee -a "$TDE_REPORT_FILE"
  _audit_check "Nerd Font" WARNING phase5_nerdfont_ok
  if phase5_telecom_selected; then
    _audit_check "Reticulum/Nomad Network" WARNING phase5_rns_ok
    _audit_check "aria2"                   WARNING phase5_aria2_ok
  else
    echo "  SKIP    Reticulum/Nomad Network, aria2 (opt-in — TDE_WITH_TELECOM=1 ./core.sh to add it)" | tee -a "$TDE_REPORT_FILE"
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
