# Phase 4 — telecom. Non-blocking: RNS/Nomad Network and aria2 are useful
# but not required for the core edit-commit workflow, so a failure here
# logs a warning and continues instead of aborting the whole phase.

[ -n "${TDE_TELECOM_LOADED:-}" ] && return 0
TDE_TELECOM_LOADED=1

phase4_install_rns_nomadnet() {
  local username
  username="$(state_get ARCH_USERNAME)"
  log_info "Installing Reticulum (RNS) and Nomad Network via AUR"
  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- paru -S --noconfirm python-rns nomadnet; then
    return 0
  fi
  log_warn "RNS/Nomad Network install failed — continuing without it"
  return 1
}

phase4_install_aria2() {
  log_info "Installing aria2"
  if proot-distro login "$TDE_DISTRO_NAME" -- pacman -S --noconfirm --needed aria2; then
    return 0
  fi
  log_warn "aria2 install failed — continuing without it"
  return 1
}

# dir= points inside the container's own filesystem, not shared Android
# storage — the login session uses --isolated, which does not bind
# /sdcard, and the file bridge is still an open design question.
phase4_write_aria2_conf() {
  local username aria_dir download_dir
  username="$(state_get ARCH_USERNAME)"
  aria_dir="$(container_home "$username")/.aria2"
  download_dir="/home/$username/downloads"
  mkdir -p "$aria_dir" "$(container_home "$username")/downloads"

  cat > "$aria_dir/aria2.conf" << EOF
dir=$download_dir
continue=true
max-connection-per-server=16
split=16
min-split-size=1M
max-concurrent-downloads=5
max-tries=0
retry-wait=3
timeout=60
connect-timeout=10
enable-http-pipelining=true
max-file-not-found=3
auto-file-renaming=true
allow-overwrite=false
check-integrity=true
file-allocation=falloc
disk-cache=64M
console-log-level=warn
summary-interval=0
EOF
}

phase4_smoke_test_telecom() {
  local username
  username="$(state_get ARCH_USERNAME)"
  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- rnsd --version >>"$TDE_LOG_FILE" 2>&1; then
    log_info "rnsd responds"
  else
    log_warn "rnsd smoke test failed"
  fi
  if proot-distro login "$TDE_DISTRO_NAME" -- aria2c --version >>"$TDE_LOG_FILE" 2>&1; then
    log_info "aria2c responds"
  else
    log_warn "aria2c smoke test failed"
  fi
}

phase4_telecom_run() {
  log_info "=== Phase 4: telecom (RNS/Nomad Network, aria2) ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would install python-rns/nomadnet via AUR, aria2 via pacman, write tuned aria2.conf"
    return 0
  fi

  local ok=0
  phase4_install_rns_nomadnet || ok=1
  phase4_install_aria2 || ok=1
  phase4_write_aria2_conf
  phase4_smoke_test_telecom
  log_info "Telecom step complete (failures above are non-blocking warnings)"
  return "$ok"
}
