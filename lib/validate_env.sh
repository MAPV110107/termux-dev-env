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

# _prompt now lives in lib/prompt.sh, sourced unconditionally by core.sh
# (phase 3/4 components call it on resumed runs where this file never
# gets sourced at all). Sourced here too so this file stays usable on
# its own, e.g. from a maintenance script that only wants phase 1.
# shellcheck source=lib/prompt.sh
. "$(dirname "${BASH_SOURCE[0]}")/prompt.sh"

phase1_check_termux() {
  if [ -z "${PREFIX:-}" ] || [ ! -d "$PREFIX" ]; then
    if [ -d "/data/data/com.termux/files/usr" ]; then
      PREFIX="/data/data/com.termux/files/usr"
      export PREFIX
    else
      log_fatal "Not running inside Termux (\$PREFIX unset or missing)"
    fi
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
  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] checking storage permissions"
    return 0
  fi
  local test_file="$HOME/storage/shared/.termux-dev-env-write-test"
  if ! [ -d "$HOME/storage/shared" ] || ! ( touch "$test_file" 2>/dev/null && rm -f "$test_file" ); then
    # Non-blocking: the Arch container lives entirely under
    # $PREFIX/var/lib/proot-distro/..., and the launcher logs in with
    # --isolated (which doesn't mount /sdcard inside the container
    # either way) — nothing in the current install actually reads or
    # writes ~/storage/shared. This used to be a log_fatal that blocked
    # the whole install over a permission nothing here needs yet; a
    # future file-bridge feature (see components/telecom.sh) would be
    # the thing to gate on this, not Phase 1 itself.
    if command -v termux-setup-storage >/dev/null 2>&1; then
      log_info "Requesting Termux storage permission via termux-setup-storage (optional — nothing in this install needs it yet)..."
      termux-setup-storage
      local retries=5
      while [ "$retries" -gt 0 ]; do
        sleep 2
        if [ -d "$HOME/storage/shared" ] && ( touch "$test_file" 2>/dev/null && rm -f "$test_file" ); then
          log_info "Storage permission granted"
          return 0
        fi
        retries=$((retries - 1))
      done
    fi
    log_warn "Storage permission not granted — continuing anyway, nothing in this install needs it. Run 'termux-setup-storage' later if a future feature needs /sdcard access."
  fi
}

phase1_check_free_space() {
  local avail_mb
  # `df -m` doesn't exist on a real Termux device: Termux's coreutils
  # package deliberately excludes df ("df does not work either, let
  # system binary prevail" — termux-packages/packages/coreutils/build.sh),
  # so `df` on PATH is Android's own toybox, which only understands
  # `-P`/`-k` (POSIX/1024-byte-block output), not GNU's `-m`. `-k` is the
  # one flag both GNU coreutils and toybox agree on, so convert from KB.
  avail_mb="$(df -k "$PREFIX" | awk 'NR==2 {print int($4/1024)}')"
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

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    return 0
  fi

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
