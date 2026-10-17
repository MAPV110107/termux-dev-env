# Phase 1 (Bootstrap validation) and Phase 2 (Hardware diagnostics & compatibility matrix).

[ -n "${TDE_VALIDATE_LOADED:-}" ] && return 0
TDE_VALIDATE_LOADED=1

TDE_MIN_FREE_MB=3072
TDE_DIAG_FILE="${TDE_DIAG_FILE:-$HOME/.config/termux-dev-env/diagnostics.env}"

TDE_RAM_TOTAL_MIN=3072;  TDE_RAM_TOTAL_REC=6144
TDE_RAM_AVAIL_MIN=1228;  TDE_RAM_AVAIL_REC=2560
TDE_STORAGE_MIN=3072;    TDE_STORAGE_REC=6144
TDE_CORES_MIN=4;         TDE_CORES_REC=8
TDE_API_MIN=24;          TDE_API_REC=29

_run() {
  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] $*"
  else
    "$@"
  fi
}

phase1_check_termux() {
  if [ -z "${PREFIX:-}" ] || [ ! -d "$PREFIX" ]; then
    if [ -d "/data/data/com.termux/files/usr" ]; then
      PREFIX="/data/data/com.termux/files/usr"
      export PREFIX
    else
      log_fatal_code 101 "Not running inside Termux (\$PREFIX unset or missing)"
    fi
  fi
  case "$PREFIX" in
    */com.termux/files/usr) ;;
    *) log_fatal_code 101 "\$PREFIX does not look like a Termux install: $PREFIX" ;;
  esac
}

phase1_check_arch() {
  local arch
  arch="$(uname -m)"
  [ "$arch" = "aarch64" ] || log_fatal_code 102 "Unsupported architecture: $arch (aarch64 required)"
}

phase1_check_storage_permission() {
  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] checking storage permissions"
    return 0
  fi
  local test_file="$HOME/storage/shared/.termux-dev-env-write-test"
  if ! [ -d "$HOME/storage/shared" ] || ! ( touch "$test_file" 2>/dev/null && rm -f "$test_file" ); then
    if command -v termux-setup-storage >/dev/null 2>&1; then
      log_info "Requesting Termux storage permission via termux-setup-storage (optional)..."
      termux-setup-storage || true
    fi
    log_warn "Storage permission not yet active — continuing (container runs in isolated storage)."
  fi
}

phase1_check_free_space() {
  local avail_mb
  avail_mb="$(df -k "$PREFIX" | awk 'NR==2 {print int($4/1024)}')"
  [ "$avail_mb" -ge "$TDE_MIN_FREE_MB" ] || \
    log_fatal_code 103 "Only ${avail_mb}MB free, need at least ${TDE_MIN_FREE_MB}MB"
  log_info "Free space check passed: ${avail_mb}MB available"
}

phase1_update_packages() {
  log_info "Updating Termux package index"
  retry_with_backoff 3 5 _run pkg update -y || \
    log_fatal_code 104 "Package index update failed after retries — check network connectivity"
  retry_with_backoff 3 5 _run pkg upgrade -y || \
    log_fatal_code 104 "Package upgrade failed after retries — check network connectivity"
}

# Lightweight host dependencies: python is NOT installed in Termux host
# because all development tools run inside the Arch Linux ARM container.
phase1_install_base_packages() {
  local packages=(proot-distro git curl gnupg)
  log_info "Installing Termux host base packages: ${packages[*]}"
  retry_with_backoff 3 5 _run pkg install -y "${packages[@]}" || \
    log_fatal_code 105 "Base package install failed after retries"

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    return 0
  fi

  local bin
  for bin in proot-distro git curl gpg; do
    command -v "$bin" >/dev/null 2>&1 || \
      log_fatal_code 105 "Expected binary not found after install: $bin"
  done
}

phase1_install_host_adb() {
  if ! command -v adb >/dev/null 2>&1; then
    log_info "Attempting to install android-tools in Termux host (optional host ADB support)..."
    _run pkg install -y android-tools 2>/dev/null || log_warn "Could not install android-tools in Termux host — container provides android-tools"
  fi
}

phase1_check_proot_version() {
  local proot_version_str major
  if ! command -v proot >/dev/null 2>&1; then
    log_warn "proot not found on PATH — proot-distro manages it"
    return 0
  fi

  proot_version_str="$(proot --version 2>&1 | head -n1 || true)"
  log_info "proot version: ${proot_version_str:-unknown}"
  major="$(printf '%s' "$proot_version_str" |
           grep -oiE '(proot[[:space:]]+|version[[:space:]]+)?v?[0-9]+\.[0-9]+' |
           head -n1 | grep -oE '[0-9]+' | head -n1 || true)"
  if [ -z "$major" ]; then
    log_warn "Could not parse proot version from: ${proot_version_str:-<no output>} — continuing"
    return 0
  fi
  if [ "$major" -lt 5 ]; then
    log_fatal_code 106 "proot version too old ($proot_version_str) — run 'pkg upgrade proot' first"
  fi
}

phase1_check_shizuku_optional() {
  if command -v rish >/dev/null 2>&1 && rish -c true 2>/dev/null; then
    log_info "Shizuku detected — automating battery and process management exemptions"
    state_set SHIZUKU_AVAILABLE 1
    _run rish -c "cmd deviceidle whitelist +com.termux" || \
      log_warn "Shizuku present but the battery whitelist command failed — set battery exemption manually"
    _run rish -c "/system/bin/device_config put activity_manager max_phantom_processes 2147483647" 2>/dev/null || true
  else
    state_set SHIZUKU_AVAILABLE 0
    log_info "Shizuku not detected — set battery exemption manually: Android Settings > Apps > Termux > Battery > Unrestricted"
  fi
}

phase1_run() {
  log_info "=== Phase 1: bootstrap validation ==="
  phase1_check_termux
  phase1_check_arch
  phase1_check_storage_permission
  phase1_check_free_space
  phase1_update_packages
  phase1_install_base_packages
  phase1_install_host_adb
  phase1_check_proot_version
  phase1_check_shizuku_optional
  log_info "Phase 1 passed"
}

diagnose_ram_total_mb()    { awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo; }
diagnose_ram_avail_mb()    { awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo; }
diagnose_storage_free_mb() { df -k "$PREFIX" | awk 'NR==2 {print int($4/1024)}'; }
diagnose_cpu_cores()       { nproc; }
diagnose_android_api()     { getprop ro.build.version.sdk 2>/dev/null || echo unknown; }

diagnose_fs_type() {
  local mount_bin
  mount_bin="$(command -v mount 2>/dev/null || echo /system/bin/mount)"
  "$mount_bin" 2>/dev/null | awk -v p="$PREFIX" '$0 ~ ("(^|[[:space:]])" p "([[:space:]]|$)") {print $5; exit}' || true
}

diagnose_proot_functional() {
  if proot true >/dev/null 2>&1; then echo ok; else echo failed; fi
}

diagnose_zram_mb() {
  local disksize
  if [ -r /sys/block/zram0/disksize ]; then
    disksize="$(cat /sys/block/zram0/disksize 2>/dev/null)"
    [ -n "$disksize" ] && [ "$disksize" -gt 0 ] 2>/dev/null && echo "$((disksize / 1024 / 1024))" && return 0
  fi
  echo "none"
}

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

phase2_run() {
  log_info "=== Phase 2: environment diagnostics ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would gather system diagnostics, test proot execution, evaluate compatibility matrix, and save to $TDE_DIAG_FILE"
    return 0
  fi

  local ram_total ram_avail storage_free fs_type cores api proot_ok zram_mb

  ram_total="$(diagnose_ram_total_mb)"
  ram_avail="$(diagnose_ram_avail_mb)"
  storage_free="$(diagnose_storage_free_mb)"
  fs_type="$(diagnose_fs_type)"
  cores="$(diagnose_cpu_cores)"
  api="$(diagnose_android_api)"
  proot_ok="$(diagnose_proot_functional)"
  zram_mb="$(diagnose_zram_mb)"

  kv_set "$TDE_DIAG_FILE" RAM_TOTAL_MB "$ram_total"
  kv_set "$TDE_DIAG_FILE" RAM_AVAIL_MB "$ram_avail"
  kv_set "$TDE_DIAG_FILE" STORAGE_FREE_MB "$storage_free"
  kv_set "$TDE_DIAG_FILE" FS_TYPE "${fs_type:-unknown}"
  kv_set "$TDE_DIAG_FILE" CPU_CORES "$cores"
  kv_set "$TDE_DIAG_FILE" ANDROID_API "$api"
  kv_set "$TDE_DIAG_FILE" PROOT_FUNCTIONAL "$proot_ok"
  kv_set "$TDE_DIAG_FILE" ZRAM_MB "$zram_mb"
  kv_set "$TDE_DIAG_FILE" DIAG_TIMESTAMP "$(date +%Y%m%d_%H%M%S)"

  log_info "RAM: ${ram_avail}MB available / ${ram_total}MB total | Free disk: ${storage_free}MB | Cores: ${cores} | API: ${api}"
  [ "$proot_ok" = "ok" ] || \
    log_fatal_code 201 "proot cannot execute on this device (ptrace likely blocked by the kernel) — cannot continue"

  compat_evaluate
  log_info "Phase 2 passed"
}