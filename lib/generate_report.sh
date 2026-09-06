# Phase 5 — report file + the generic check-and-record helper the audit
# uses for every component. One place decides what "critical" means for
# the exit behavior; the audit itself just labels each check's severity.

[ -n "${TDE_GENERATE_REPORT_LOADED:-}" ] && return 0
TDE_GENERATE_REPORT_LOADED=1

TDE_REPORT_FILE="$HOME/.config/termux-dev-env/logs/install_report_$(date +%Y%m%d_%H%M%S).log"
TDE_AUDIT_HAD_CRITICAL_FAILURE=0

_audit_check() {
  local label="$1" severity_on_fail="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    echo "  [OK]       $label" | tee -a "$TDE_REPORT_FILE"
  else
    echo "  [$severity_on_fail] $label" | tee -a "$TDE_REPORT_FILE"
    if [ "$severity_on_fail" = "CRITICAL" ]; then
      TDE_AUDIT_HAD_CRITICAL_FAILURE=1
    fi
  fi
  return 0
}
