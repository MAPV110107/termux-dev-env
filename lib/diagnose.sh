# Phase 2 — environment diagnostics. Captures the hardware/OS picture once
# and persists it to diagnostics.env so: (a) phase 5's report can quote it,
# and (b) a future `archdiag` can diff "now" against "at install time" to
# spot what changed (Android revoked zram, storage filled up, etc).

[ -n "${TDE_DIAGNOSE_LOADED:-}" ] && return 0
TDE_DIAGNOSE_LOADED=1

TDE_DIAG_FILE="${TDE_DIAG_FILE:-$HOME/.config/termux-dev-env/diagnostics.env}"

diagnose_ram_total_mb() {
  awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo
}

# A single reading can look worse than the device really is if a background
# app is mid-spike; median of three short-spaced samples smooths that out.
diagnose_ram_avail_mb() {
  local samples=() val
  for _ in 1 2 3; do
    val="$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)"
    samples+=("$val")
    sleep 1
  done
  printf '%s\n' "${samples[@]}" | sort -n | awk 'NR==2'
}

diagnose_storage_free_mb() {
  df -m "$PREFIX" | awk 'NR==2 {print $4}'
}

diagnose_fs_type() {
  mount | awk -v p="$PREFIX" '$0 ~ ("(^|[[:space:]])" p "([[:space:]]|$)") {print $5; exit}'
}

diagnose_cpu_cores() {
  nproc
}

diagnose_android_api() {
  getprop ro.build.version.sdk 2>/dev/null || echo unknown
}

# proot itself (not proot-distro, no container yet) must be able to run at
# all — some kernels block the ptrace calls proot depends on. Better to find
# out now than after downloading a multi-GB rootfs in phase 3.
diagnose_proot_functional() {
  if proot true >/dev/null 2>&1; then echo ok; else echo failed; fi
}

phase2_run() {
  log_info "=== Phase 2: environment diagnostics ==="
  local ram_total ram_avail storage_free fs_type cores api proot_ok

  ram_total="$(diagnose_ram_total_mb)"
  kv_set "$TDE_DIAG_FILE" RAM_TOTAL_MB "$ram_total"
  log_info "RAM total: ${ram_total}MB"

  ram_avail="$(diagnose_ram_avail_mb)"
  kv_set "$TDE_DIAG_FILE" RAM_AVAIL_MB "$ram_avail"
  log_info "RAM available (median of 3 samples): ${ram_avail}MB"

  storage_free="$(diagnose_storage_free_mb)"
  kv_set "$TDE_DIAG_FILE" STORAGE_FREE_MB "$storage_free"
  log_info "Storage free: ${storage_free}MB"

  fs_type="$(diagnose_fs_type)"
  kv_set "$TDE_DIAG_FILE" FS_TYPE "${fs_type:-unknown}"
  log_info "Filesystem: ${fs_type:-unknown}"

  cores="$(diagnose_cpu_cores)"
  kv_set "$TDE_DIAG_FILE" CPU_CORES "$cores"
  log_info "CPU cores: ${cores}"

  api="$(diagnose_android_api)"
  kv_set "$TDE_DIAG_FILE" ANDROID_API "$api"
  log_info "Android API level: ${api}"

  proot_ok="$(diagnose_proot_functional)"
  kv_set "$TDE_DIAG_FILE" PROOT_FUNCTIONAL "$proot_ok"
  log_info "proot functional test: ${proot_ok}"
  [ "$proot_ok" = "ok" ] || \
    log_fatal "proot cannot execute on this device (ptrace likely blocked by the kernel) — cannot continue"

  kv_set "$TDE_DIAG_FILE" DIAG_TIMESTAMP "$(date +%Y%m%d_%H%M%S)"

  compat_evaluate
  log_info "Phase 2 passed"
}
