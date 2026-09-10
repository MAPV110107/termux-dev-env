# Phase 1 — bootstrap validation. Nothing in later phases runs until every
# check here passes. Each failure names the exact reason, never a bare
# "something went wrong".

[ -n "${TDE_VALIDATE_ENV_LOADED:-}" ] && return 0
TDE_VALIDATE_ENV_LOADED=1

TDE_MIN_FREE_MB=3072

# Wraps commands that change the system so --dry-run can print instead of
# execute, without duplicating every call site.
_run() {
  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] $*"
  else
    "$@"
  fi
}

# Centralized prompt: returns the default immediately under --dry-run
# without touching the terminal. Every interactive read in phases 3/4
# goes through this, so a future refactor that calls a prompt function
# directly (bypassing a *_run guard) still can't make dry-run interactive.
_prompt() {
  local prompt_text="$1" default_value="${2:-}"
  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    echo "$default_value"
    return 0
  fi
  local input
  read -r -p "$prompt_text" input
  echo "${input:-$default_value}"
}

phase1_check_termux() {
  if [ -z "${PREFIX:-}" ] || [ ! -d "$PREFIX" ]; then
    log_fatal "Not running inside Termux (\$PREFIX unset or missing)"
  fi
  case "$PREFIX" in
    */com.termux/files/usr) ;;
    *) log_fatal "\$PREFIX does not look like a Termux install: $PREFIX" ;;
  esac
}

phase1_check_arch() {
  local arch
  arch="$(uname -m)"
  [ "$arch" = "aarch64" ] || log_fatal "Unsupported architecture: $arch (aarch64 required)"
}

phase1_check_storage_permission() {
  local test_file="$HOME/storage/shared/.termux-dev-env-write-test"
  if ! [ -d "$HOME/storage/shared" ] || ! ( touch "$test_file" 2>/dev/null && rm -f "$test_file" ); then
    log_fatal "Storage permission not granted — run 'termux-setup-storage' first"
  fi
}

phase1_check_free_space() {
  local avail_mb
  avail_mb="$(df -m "$PREFIX" | awk 'NR==2 {print $4}')"
  [ "$avail_mb" -ge "$TDE_MIN_FREE_MB" ] || \
    log_fatal "Only ${avail_mb}MB free, need at least ${TDE_MIN_FREE_MB}MB"
  log_info "Free space check passed: ${avail_mb}MB available"
}

phase1_update_packages() {
  log_info "Updating Termux package index"
  retry_with_backoff 3 5 _run pkg update -y || \
    log_fatal "Package index update failed after retries — check network connectivity"
  retry_with_backoff 3 5 _run pkg upgrade -y || \
    log_fatal "Package upgrade failed after retries — check network connectivity"
}

phase1_install_base_packages() {
  local packages=(proot-distro git curl wget python)
  log_info "Installing base packages: ${packages[*]}"
  retry_with_backoff 3 5 _run pkg install -y "${packages[@]}" || \
    log_fatal "Base package install failed after retries"

  local bin
  for bin in proot-distro git curl wget python; do
    command -v "$bin" >/dev/null 2>&1 || \
      log_fatal "Expected binary not found after install: $bin"
  done
}

phase1_check_proot_version() {
  # proot-distro v5 needs a recent proot; an old one fails later with an
  # unrelated-looking "unknown program 'loader'" error instead of here.
  local proot_version_str major
  proot_version_str="$(proot --version 2>&1 | head -n1 || true)"
  log_info "proot version: ${proot_version_str:-unknown}"
  major="$(echo "$proot_version_str" | grep -oE '[0-9]+' | head -n1 || true)"
  if [[ "$major" =~ ^[0-9]+$ ]] && [ "$major" -lt 5 ]; then
    log_fatal "proot version too old ($proot_version_str) — run 'pkg upgrade proot' first"
  fi
}

# Shizuku is optional and never required — without it the user just sets
# the battery exemption by hand. When present, it can run the one Android
# shell command that saves that manual step.
phase1_check_shizuku_optional() {
  if command -v rish >/dev/null 2>&1 && rish -c true 2>/dev/null; then
    log_info "Shizuku detected — automating battery optimization exemption"
    state_set SHIZUKU_AVAILABLE 1
    _run rish -c "cmd deviceidle whitelist +com.termux" || \
      log_warn "Shizuku present but the command failed — set the battery exemption manually"
  else
    state_set SHIZUKU_AVAILABLE 0
    log_info "Shizuku not detected — set battery optimization exemption manually: Android Settings > Apps > Termux > Battery > Unrestricted"
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
  phase1_check_proot_version
  phase1_check_shizuku_optional
  log_info "Phase 1 passed"
}
