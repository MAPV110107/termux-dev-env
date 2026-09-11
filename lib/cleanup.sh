# Phase 5 — cleanup. Deletes a target only if its check passes; anything
# that failed verification is left on disk on purpose, for debugging.

[ -n "${TDE_CLEANUP_LOADED:-}" ] && return 0
TDE_CLEANUP_LOADED=1

_cleanup_if() {
  local check_fn="$1" target="$2" label="$3"
  if [ ! -e "$target" ]; then
    return 0
  fi
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

  if phase4_toolchain_ok; then
    local username
    username="$(state_get ARCH_USERNAME)"
    proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- rm -rf /tmp/paru-bin 2>/dev/null
    log_info "Cleaned up: paru build directory inside container"
  fi
}
