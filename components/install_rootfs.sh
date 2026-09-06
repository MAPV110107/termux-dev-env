# Phase 3, step 1 — rootfs install. Downloads the official Arch Linux ARM
# tarball, verifies it with GPG (not just a checksum — confirms origin, not
# just byte integrity), then hands the already-verified file to
# proot-distro so it never re-downloads something we already checked.

[ -n "${TDE_INSTALL_ROOTFS_LOADED:-}" ] && return 0
TDE_INSTALL_ROOTFS_LOADED=1

TDE_ARM_MIRRORS=(os.archlinuxarm.org ca.us.mirror.archlinuxarm.org eu.mirror.archlinuxarm.org)
TDE_ARM_KEYRING_URL="https://raw.githubusercontent.com/archlinuxarm/archlinuxarm-keyring/master/archlinuxarm.gpg"
TDE_ROOTFS_TMPDIR="$HOME/.cache/termux-dev-env"
TDE_ROOTFS_TARBALL="$TDE_ROOTFS_TMPDIR/ArchLinuxARM-aarch64-latest.tar.gz"
TDE_ROOTFS_SIG="${TDE_ROOTFS_TARBALL}.sig"

phase3_install_gpg_tool() {
  command -v gpg >/dev/null 2>&1 && return 0
  log_info "Installing gnupg (needed to verify the rootfs signature)"
  retry_with_backoff 3 5 pkg install -y gnupg || \
    log_fatal "Could not install gnupg — cannot verify rootfs integrity"
}

phase3_import_signing_key() {
  log_info "Importing Arch Linux ARM signing key"
  retry_with_backoff 3 5 curl -fsSL "$TDE_ARM_KEYRING_URL" -o "$TDE_ROOTFS_TMPDIR/archlinuxarm.gpg" || \
    log_fatal "Could not download the Arch Linux ARM signing key"
  gpg --import "$TDE_ROOTFS_TMPDIR/archlinuxarm.gpg" || \
    log_fatal "Could not import the Arch Linux ARM signing key"
}

# Tries each mirror in order; a corrupted download or a failed signature
# both discard the file and move to the next mirror rather than aborting
# on the first one — a single bad mirror should not block the install.
phase3_download_and_verify() {
  local mirror tarball_url sig_url

  for mirror in "${TDE_ARM_MIRRORS[@]}"; do
    tarball_url="http://${mirror}/os/ArchLinuxARM-aarch64-latest.tar.gz"
    sig_url="${tarball_url}.sig"
    log_info "Trying mirror: $mirror"

    if ! retry_with_backoff 3 5 curl -fL -C - -o "$TDE_ROOTFS_TARBALL" "$tarball_url"; then
      log_warn "Download failed from $mirror, trying next mirror"
      continue
    fi
    if ! retry_with_backoff 2 3 curl -fL -o "$TDE_ROOTFS_SIG" "$sig_url"; then
      log_warn "Signature download failed from $mirror, trying next mirror"
      continue
    fi
    if gpg --verify "$TDE_ROOTFS_SIG" "$TDE_ROOTFS_TARBALL" >>"$TDE_LOG_FILE" 2>&1; then
      log_info "GPG signature verified against $mirror"
      return 0
    fi
    log_warn "GPG verification failed for $mirror — discarding, trying next mirror"
    rm -f "$TDE_ROOTFS_TARBALL" "$TDE_ROOTFS_SIG"
  done

  log_fatal "Could not download and verify the Arch Linux ARM rootfs from any mirror"
}

phase3_install_rootfs() {
  log_info "Installing Arch Linux ARM into proot-distro as '$TDE_DISTRO_NAME'"
  proot-distro install "$TDE_ROOTFS_TARBALL" --name "$TDE_DISTRO_NAME" --architecture aarch64 || \
    log_fatal "proot-distro install failed"
}

phase3_smoke_test_rootfs() {
  proot-distro login "$TDE_DISTRO_NAME" -- true || \
    log_fatal "Rootfs installed but failed to log in — installation is broken"
}

# Post-condition, checked by core.sh before marking PHASE3_ROOTFS_INSTALLED —
# the container is registered AND actually logs in, not just "the install
# command exited zero".
phase3_rootfs_ok() {
  proot-distro list 2>/dev/null | grep -q "$TDE_DISTRO_NAME" && \
    proot-distro login "$TDE_DISTRO_NAME" -- true 2>/dev/null
}

phase3_install_rootfs_run() {
  log_info "=== Phase 3, step 1: rootfs install ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would install gnupg, download+GPG-verify the rootfs from ${TDE_ARM_MIRRORS[*]}, run 'proot-distro install', smoke test with 'proot-distro login $TDE_DISTRO_NAME -- true'"
    return 0
  fi

  mkdir -p "$TDE_ROOTFS_TMPDIR"
  phase3_install_gpg_tool
  phase3_import_signing_key
  phase3_download_and_verify
  phase3_install_rootfs
  phase3_smoke_test_rootfs
  log_info "Rootfs installed and verified"
}
