# Compatibility matrix for the actual workload: proot + Arch Linux ARM +
# LazyVim (no persistent LSP) + git + Reticulum/Nomad + aria2. Below
# "minimum" still works, just degraded — this warns, it does not abort.
# Hard blockers (unsupported architecture, proot not executable) are
# already handled in phase 1 / phase 2 before this runs.

[ -n "${TDE_COMPAT_LOADED:-}" ] && return 0
TDE_COMPAT_LOADED=1

TDE_RAM_TOTAL_MIN=3072;  TDE_RAM_TOTAL_REC=6144
TDE_RAM_AVAIL_MIN=1228;  TDE_RAM_AVAIL_REC=2560
TDE_STORAGE_MIN=3072;    TDE_STORAGE_REC=6144
TDE_CORES_MIN=4;         TDE_CORES_REC=8
TDE_API_MIN=24;          TDE_API_REC=29

_compat_check() {
  local label="$1" value="$2" min="$3" rec="$4"

  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    log_warn "WARN  $label: value not available ('${value:-empty}') — skipping check"
    return 0
  fi

  if [ "$value" -ge "$rec" ]; then
    log_info "  OK    $label: $value (recommended: ${rec}+)"
  elif [ "$value" -ge "$min" ]; then
    log_warn "WARN  $label: $value (below recommended $rec, above minimum $min)"
  else
    log_warn "WARN  $label: $value (below minimum $min — expect degraded performance)"
  fi
}

compat_evaluate() {
  log_info "--- Compatibility matrix ---"
  _compat_check "RAM total (MB)"     "$(kv_get "$TDE_DIAG_FILE" RAM_TOTAL_MB)"    "$TDE_RAM_TOTAL_MIN" "$TDE_RAM_TOTAL_REC"
  _compat_check "RAM available (MB)" "$(kv_get "$TDE_DIAG_FILE" RAM_AVAIL_MB)"    "$TDE_RAM_AVAIL_MIN" "$TDE_RAM_AVAIL_REC"
  _compat_check "Storage free (MB)"  "$(kv_get "$TDE_DIAG_FILE" STORAGE_FREE_MB)" "$TDE_STORAGE_MIN"   "$TDE_STORAGE_REC"
  _compat_check "CPU cores"          "$(kv_get "$TDE_DIAG_FILE" CPU_CORES)"       "$TDE_CORES_MIN"     "$TDE_CORES_REC"
  _compat_check "Android API level"  "$(kv_get "$TDE_DIAG_FILE" ANDROID_API)"     "$TDE_API_MIN"       "$TDE_API_REC"
}
