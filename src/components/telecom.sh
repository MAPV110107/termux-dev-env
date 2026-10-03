# Phase 4 — telecom. Non-blocking: RNS/Nomad Network and aria2 are useful
# but not required for the core edit-commit workflow, so a failure here
# logs a warning and continues instead of aborting the whole phase.

[ -n "${TDE_TELECOM_LOADED:-}" ] && return 0
TDE_TELECOM_LOADED=1

# Decides whether the telecom stack (Reticulum/Nomad Network + aria2)
# gets installed on this run. It stays opt-in — it is a mesh-networking
# and download stack most people installing a dev environment do not
# want, and it pulls real weight (a pip install, an AUR build, aria2).
# What changed: it is no longer *silently* opt-in. Before, someone who
# had never heard of TDE_WITH_TELECOM got one log line among hundreds
# and no telecom, with no idea a choice had even been made for them.
#
# Order of precedence:
#   1. TDE_WITH_TELECOM=1 / TDE_SKIP_TELECOM=1 in the environment — explicit, always wins.
#   2. A previously recorded answer in state (TELECOM_WANTED), so the
#      question is asked once per install, not on every resumed run.
#   3. An interactive prompt, defaulting to No.
#   4. Non-interactive with no preference recorded: skip, loudly.
# Its own function purely so the interactive path is testable: a test
# harness cannot give a piped shell a controlling terminal, but it can
# stub this.
_telecom_can_ask() { [ -t 0 ]; }

phase4_telecom_wanted() {
  if [ "${TDE_SKIP_TELECOM:-0}" = "1" ]; then
    log_info "Telecom skipped (TDE_SKIP_TELECOM=1)"
    return 1
  fi
  if [ "${TDE_WITH_TELECOM:-0}" = "1" ]; then
    return 0
  fi

  local recorded
  recorded="$(state_get TELECOM_WANTED)"
  case "$recorded" in
    1) return 0 ;;
    0) log_info "Telecom skipped (you declined earlier — re-run with TDE_WITH_TELECOM=1 to add it)"; return 1 ;;
  esac

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would ask whether to install the optional telecom stack (Reticulum/Nomad Network + aria2), defaulting to No"
    return 1
  fi

  if ! _telecom_can_ask; then
    log_warn "Optional telecom stack (Reticulum/Nomad Network + aria2) NOT installed — no terminal to ask on. Re-run with TDE_WITH_TELECOM=1 ./core.sh to include it."
    return 1
  fi

  echo ""
  echo "──────────────────────────────────────────────────────────────"
  echo " Optional: Reticulum / Nomad Network + aria2"
  echo ""
  echo "   Reticulum and Nomad Network are a mesh-networking stack"
  echo "   (off-grid, encrypted messaging over LoRa/TCP/packet radio)."
  echo "   aria2 is a parallel download accelerator."
  echo ""
  echo "   Most people installing a dev environment do not need these."
  echo "   They add an AUR build and a pip install to the run, and can"
  echo "   always be added later with:  TDE_WITH_TELECOM=1 ./core.sh"
  echo "──────────────────────────────────────────────────────────────"
  local answer
  answer="$(_prompt "Install the telecom stack now? [y/N]: " "N")"
  case "$answer" in
    y|Y|yes|YES) state_set TELECOM_WANTED 1; return 0 ;;
    *) state_set TELECOM_WANTED 0; log_info "Skipping telecom — add it later with TDE_WITH_TELECOM=1 ./core.sh"; return 1 ;;
  esac
}

phase4_install_rns_nomadnet() {
  local username
  username="$(state_get ARCH_USERNAME)"
  log_info "Installing Reticulum (RNS) and Nomad Network via AUR"
  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- paru -S --noconfirm python-rns nomadnet < /dev/null; then
    return 0
  fi
  log_warn "AUR install failed, trying pip as a fallback"
  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
     pip install --user --break-system-packages rns nomadnet; then
    return 0
  fi
  log_warn "RNS/Nomad Network install failed via AUR and pip — continuing without it"
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
  # ~/.local/bin prepended explicitly — see phase5_rns_ok's comment:
  # rnsd can land there (pip --user fallback) and a non-interactive
  # login doesn't source .zshrc's PATH addition for it.
  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
       sh -c 'PATH="$HOME/.local/bin:$PATH" rnsd --version' >>"$TDE_LOG_FILE" 2>&1; then
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
