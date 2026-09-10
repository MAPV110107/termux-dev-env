# Phase 3, step 1 — rootfs install. Uses proot-distro's own OCI pull
# mechanism (which SHA-256-verifies every layer automatically) instead of
# a custom download+GPG dance. This specific image is proot-distro's own
# documented example for installing Arch on ARM — Arch Linux ARM itself
# doesn't publish an official Docker Hub image, so the community image
# is what the tool's own maintainers point to.

[ -n "${TDE_INSTALL_ROOTFS_LOADED:-}" ] && return 0
TDE_INSTALL_ROOTFS_LOADED=1

# :latest floats. Pin to a dated tag (e.g. danhunsaker/archlinuxarm:20260517)
# once a specific version is verified working on your device.
TDE_ROOTFS_IMAGE="danhunsaker/archlinuxarm:latest"

phase3_install_rootfs() {
  log_info "Installing Arch Linux ARM ($TDE_ROOTFS_IMAGE) into proot-distro as '$TDE_DISTRO_NAME'"
  proot-distro install "$TDE_ROOTFS_IMAGE" --name "$TDE_DISTRO_NAME" || \
    log_fatal "proot-distro install failed"
}

phase3_smoke_test_rootfs() {
  proot-distro login "$TDE_DISTRO_NAME" -- true || \
    log_fatal "Rootfs installed but failed to log in — installation is broken"
}

# Without this, pacman signature checks fail on a freshly pulled rootfs —
# scdaemon in particular can hang pacman-key inside proot since there's no
# real smartcard device for it to talk to.
phase3_init_pacman_keyring() {
  log_info "Initializing pacman keyring (pacman-key --init, --populate archlinuxarm)"
  proot-distro login "$TDE_DISTRO_NAME" -- sh -c '
    set -e
    pacman-key --init
    echo "disable-scdaemon" > /etc/pacman.d/gnupg/gpg-agent.conf
    pacman-key --populate archlinuxarm
  ' < /dev/null || log_fatal "Could not initialize pacman keyring"
}

# pacman's sandboxed download/hook execution needs Linux namespaces proot
# doesn't provide — without this, pacman operations can hang or fail
# inside the container.
phase3_disable_pacman_sandbox() {
  proot-distro login "$TDE_DISTRO_NAME" -- sh -c '
    grep -q "^DisableSandbox" /etc/pacman.conf || \
    sed -i "/^\[options\]/a DisableSandbox" /etc/pacman.conf
  ' || log_warn "Could not set DisableSandbox in pacman.conf — pacman operations may hang or fail inside proot"
}

# Post-condition, checked by core.sh before marking PHASE3_ROOTFS_INSTALLED —
# the container is registered, logs in, AND the keyring/sandbox setup this
# step is responsible for actually landed, not just "install exited zero".
phase3_rootfs_ok() {
  proot-distro list 2>/dev/null | grep -q "$TDE_DISTRO_NAME" && \
    proot-distro login "$TDE_DISTRO_NAME" -- test -d /etc/pacman.d/gnupg 2>/dev/null && \
    proot-distro login "$TDE_DISTRO_NAME" -- grep -q "^DisableSandbox" /etc/pacman.conf 2>/dev/null
}

phase3_install_rootfs_run() {
  log_info "=== Phase 3, step 1: rootfs install ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would run: proot-distro install $TDE_ROOTFS_IMAGE --name $TDE_DISTRO_NAME, smoke test, initialize pacman keyring, disable pacman sandbox"
    return 0
  fi

  phase3_install_rootfs
  phase3_smoke_test_rootfs
  phase3_init_pacman_keyring
  phase3_disable_pacman_sandbox
  log_info "Rootfs installed and verified"
}
