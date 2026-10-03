# Phase 5 — cleanup. Deletes a target only if its check passes; anything
# that failed verification is left on disk on purpose, for debugging.

[ -n "${TDE_CLEANUP_LOADED:-}" ] && return 0
TDE_CLEANUP_LOADED=1

TDE_ROOTFS_TMPDIR="${TDE_ROOTFS_TMPDIR:-$HOME/.cache/termux-dev-env/rootfs}"
TDE_NERDFONT_TMPDIR="${TDE_NERDFONT_TMPDIR:-$HOME/.cache/termux-dev-env/nerdfont}"

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

  # Gated on paru itself being present, not phase4_toolchain_ok (which
  # only requires gcc/git — paru is optional and non-blocking, see
  # dev_toolchain.sh). Deleting /tmp/paru-bin whenever the core toolchain
  # merely looked fine, regardless of whether paru's own build+install
  # actually succeeded, wiped out the exact directory this project's own
  # TROUBLESHOOTING.md tells people to retry from after a failed paru
  # install — leaving nothing left to retry.
  # Gated on paru actually RUNNING (`paru --version`), not merely being
  # on PATH: the known failure here is paru-bin installing fine and then
  # dying on a libalpm version mismatch, which `command -v` happily
  # reports as present. Deleting the build directories in that state
  # removes exactly what TROUBLESHOOTING.md (and `archparu`) tell people
  # to retry from.
  local username
  username="$(state_get ARCH_USERNAME)"
  if [ -n "$username" ] && \
     proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- paru --version >/dev/null 2>&1; then
    proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- rm -rf /tmp/paru-bin /tmp/paru 2>/dev/null
    log_info "Cleaned up: paru build directories inside container"
  elif [ -n "$username" ]; then
    log_warn "Kept (paru does not run — preserved so 'archparu' can retry from them): /tmp/paru-bin, /tmp/paru"
  fi
}
