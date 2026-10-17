# Phase 3, step 1 — Arch Linux ARM rootfs download, GPG verification,
# proot-distro registration, keyring setup, and pacman tuning.

[ -n "${TDE_MODULE_ROOTFS_LOADED:-}" ] && return 0
TDE_MODULE_ROOTFS_LOADED=1

TDE_ARM_MIRRORS=(os.archlinuxarm.org ca.us.mirror.archlinuxarm.org eu.mirror.archlinuxarm.org)
TDE_ARM_KEYRING_URL="https://raw.githubusercontent.com/archlinuxarm/archlinuxarm-keyring/master/archlinuxarm.gpg"
TDE_ROOTFS_TMPDIR="$HOME/.cache/termux-dev-env/rootfs"
TDE_ROOTFS_TARBALL="$TDE_ROOTFS_TMPDIR/ArchLinuxARM-aarch64-latest.tar.gz"
TDE_ROOTFS_SIG="${TDE_ROOTFS_TARBALL}.sig"

phase3_install_gpg_tool() {
  command -v gpg >/dev/null 2>&1 && return 0
  log_info "Installing gnupg (needed to verify the rootfs signature)"
  retry_with_backoff 3 5 pkg install -y gnupg || \
    log_fatal_code 310 "Could not install gnupg — cannot verify rootfs integrity"
}

phase3_import_signing_key() {
  log_info "Importing Arch Linux ARM signing key"
  mkdir -p "$TDE_ROOTFS_TMPDIR"
  retry_with_backoff 3 5 curl -fsSL "$TDE_ARM_KEYRING_URL" -o "$TDE_ROOTFS_TMPDIR/archlinuxarm.gpg" || \
    log_fatal_code 311 "Could not download the Arch Linux ARM signing key"
  gpg --import "$TDE_ROOTFS_TMPDIR/archlinuxarm.gpg" || \
    log_fatal_code 312 "Could not import the Arch Linux ARM signing key"
}

phase3_download_and_verify() {
  local mirror scheme tarball_url sig_url
  mkdir -p "$TDE_ROOTFS_TMPDIR"

  if [ -n "${TDE_ROOTFS_URL_OVERRIDE:-}" ]; then
    tarball_url="$TDE_ROOTFS_URL_OVERRIDE"
    sig_url="${tarball_url}.sig"
    log_info "Using pinned rootfs override: $tarball_url"
    if retry_with_backoff 3 5 curl -fL -C - -o "$TDE_ROOTFS_TARBALL" "$tarball_url" && \
       retry_with_backoff 2 3 curl -fL -o "$TDE_ROOTFS_SIG" "$sig_url" && \
       gpg --verify "$TDE_ROOTFS_SIG" "$TDE_ROOTFS_TARBALL" >>"$TDE_LOG_FILE" 2>&1; then
      log_info "GPG signature verified for pinned override"
      return 0
    fi
    log_fatal_code 313 "Pinned rootfs override failed to download or verify: $tarball_url"
  fi

  for mirror in "${TDE_ARM_MIRRORS[@]}"; do
    for scheme in https http; do
      tarball_url="${scheme}://${mirror}/os/ArchLinuxARM-aarch64-latest.tar.gz"
      sig_url="${tarball_url}.sig"
      log_info "Trying mirror: $mirror over $scheme"

      if ! retry_with_backoff 3 5 curl -fL -C - -o "$TDE_ROOTFS_TARBALL" "$tarball_url"; then
        log_warn "Download failed from $mirror over $scheme"
        rm -f "$TDE_ROOTFS_TARBALL" "$TDE_ROOTFS_SIG"
        continue
      fi
      if ! retry_with_backoff 2 3 curl -fL -o "$TDE_ROOTFS_SIG" "$sig_url"; then
        log_warn "Signature download failed from $mirror over $scheme"
        rm -f "$TDE_ROOTFS_TARBALL" "$TDE_ROOTFS_SIG"
        continue
      fi
      if gpg --verify "$TDE_ROOTFS_SIG" "$TDE_ROOTFS_TARBALL" >>"$TDE_LOG_FILE" 2>&1; then
        log_info "GPG signature verified against $mirror ($scheme)"
        return 0
      fi
      log_warn "GPG verification failed for $mirror — discarding, trying next mirror"
      rm -f "$TDE_ROOTFS_TARBALL" "$TDE_ROOTFS_SIG"
      break
    done
  done

  log_fatal_code 314 "Could not download and verify the Arch Linux ARM rootfs from any mirror"
}

phase3_container_exists() {
  if [ -d "$TDE_ROOTFS_PATH/etc" ]; then
    return 0
  fi
  if proot-distro list -q 2>/dev/null | grep -qx "$TDE_DISTRO_NAME"; then
    return 0
  fi
  proot-distro login "$TDE_DISTRO_NAME" -- true >/dev/null 2>&1
}

phase3_install_rootfs() {
  log_info "Installing Arch Linux ARM into proot-distro as '$TDE_DISTRO_NAME'"
  proot-distro install "$TDE_ROOTFS_TARBALL" --name "$TDE_DISTRO_NAME" --architecture aarch64 || \
    log_fatal_code 315 "proot-distro install failed"
}

phase3_smoke_test_rootfs() {
  proot-distro login "$TDE_DISTRO_NAME" -- true || \
    log_fatal_code 316 "Rootfs installed but failed to log in — installation is broken"
}

phase3_init_pacman_keyring() {
  log_info "Initializing pacman keyring (pacman-key --init, --populate archlinuxarm)"
  proot-distro login "$TDE_DISTRO_NAME" -- sh -c '
    set -e
    pacman-key --init
    mkdir -p /etc/pacman.d/gnupg
    echo "disable-scdaemon" > /etc/pacman.d/gnupg/gpg-agent.conf
    pacman-key --populate archlinuxarm
  ' < /dev/null || log_fatal_code 317 "Could not initialize pacman keyring"
}

phase3_disable_pacman_sandbox() {
  local attempt
  for attempt in 1 2 3; do
    proot-distro login "$TDE_DISTRO_NAME" -- sh -c '
      grep -q "^DisableSandbox" /etc/pacman.conf || \
        sed -i "/^\[options\]/a DisableSandbox" /etc/pacman.conf
      sed -i "s/^#\?ParallelDownloads = .*/ParallelDownloads = 10/" /etc/pacman.conf
      grep -q "^ParallelDownloads" /etc/pacman.conf || \
        sed -i "/^\[options\]/a ParallelDownloads = 10" /etc/pacman.conf
      grep -q "^IgnorePkg" /etc/pacman.conf || \
        sed -i "/^\[options\]/a IgnorePkg = linux-aarch64" /etc/pacman.conf
    ' >>"$TDE_LOG_FILE" 2>&1

    if proot-distro login "$TDE_DISTRO_NAME" -- grep -q "^DisableSandbox" /etc/pacman.conf 2>/dev/null; then
      log_info "DisableSandbox and ParallelDownloads=10 confirmed in pacman.conf (attempt $attempt/3)"
      return 0
    fi
    log_warn "DisableSandbox still missing after attempt $attempt/3 — retrying"
    sleep 2
  done
  log_fatal_code 318 "Could not write DisableSandbox into /etc/pacman.conf inside $TDE_DISTRO_NAME after 3 attempts."
}

phase3_write_pacman_mirrorlist() {
  local mirror mirrorlist_body=""
  for mirror in "${TDE_ARM_MIRRORS[@]}"; do
    mirrorlist_body="${mirrorlist_body}Server = https://${mirror}/\$arch/\$repo
Server = http://${mirror}/\$arch/\$repo
"
  done
  proot-distro login "$TDE_DISTRO_NAME" -- sh -c "cat > /etc/pacman.d/mirrorlist << 'MIRROREOF'
${mirrorlist_body}MIRROREOF" >>"$TDE_LOG_FILE" 2>&1 || {
    log_warn "Could not write multi-mirror pacman mirrorlist — keeping default mirror"
    return 0
  }
  log_info "pacman mirrorlist configured with ${#TDE_ARM_MIRRORS[@]} mirrors (HTTPS prioritized)"
}

phase3_rootfs_ok() {
  local ok=1
  if ! phase3_container_exists; then
    log_warn "post-check: container '$TDE_DISTRO_NAME' not found"
    ok=0
  fi
  if ! proot-distro login "$TDE_DISTRO_NAME" -- test -d /etc/pacman.d/gnupg 2>/dev/null; then
    log_warn "post-check: /etc/pacman.d/gnupg missing"
    ok=0
  fi
  if ! proot-distro login "$TDE_DISTRO_NAME" -- grep -q "^DisableSandbox" /etc/pacman.conf 2>/dev/null; then
    log_warn "post-check: DisableSandbox missing from /etc/pacman.conf"
    ok=0
  fi
  [ "$ok" = "1" ]
}

phase3_install_rootfs_run() {
  log_info "=== Phase 3, step 1: rootfs install ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would install gnupg, download+GPG-verify the aarch64 rootfs, install into proot-distro, initialize keyring, configure pacman.conf and mirrorlist"
    return 0
  fi

  mkdir -p "$TDE_ROOTFS_TMPDIR"

  if phase3_container_exists; then
    log_info "Container '$TDE_DISTRO_NAME' already exists — skipping download, verifying keyring and pacman config"
  else
    phase3_install_gpg_tool
    phase3_import_signing_key
    phase3_download_and_verify
    phase3_install_rootfs
  fi

  phase3_smoke_test_rootfs
  phase3_init_pacman_keyring
  phase3_disable_pacman_sandbox
  phase3_write_pacman_mirrorlist
  log_info "Rootfs installed and verified"
}