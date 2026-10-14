# Phase 3, step 2 — Container user creation, password fallback, and passwordless sudo.

[ -n "${TDE_MODULE_USER_LOADED:-}" ] && return 0
TDE_MODULE_USER_LOADED=1

TDE_RESERVED_USERNAMES="root bin daemon sys sync games man lp mail news uucp proxy www-data backup list irc gnats nobody adm tty disk floppy dialout cdrom audio video utmp usbmus plugdev staff users wheel sudo ftp http dbus messagebus polkitd systemd-network systemd-resolve systemd-timesync systemd-journal systemd-coredump systemd-oom nscd avahi colord git svn rtkit usbmux geoclue sshd ssh openssh nvidia docker named ntp uuidd admin administrator operator guest default test user0 halt shutdown"

_username_is_valid() {
  local name="$1" reserved
  [[ "$name" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || return 1
  for reserved in $TDE_RESERVED_USERNAMES; do
    [ "$name" = "$reserved" ] && return 1
  done
  return 0
}

phase3_prompt_username() {
  local input
  while true; do
    input="$(_prompt "Arch Linux username [user]: " "user")"
    if _username_is_valid "$input"; then
      echo "$input"
      return 0
    fi
    echo "Invalid username: lowercase, starts with a letter or underscore, no spaces, not a reserved system name. Try again." >&2
  done
}

phase3_ensure_sudo_installed() {
  log_info "Installing sudo and zsh inside $TDE_DISTRO_NAME"
  retry_with_backoff 3 10 \
    proot-distro login "$TDE_DISTRO_NAME" -- pacman -Sy --noconfirm --needed sudo zsh || \
    log_fatal_code 320 "Could not install sudo/zsh inside $TDE_DISTRO_NAME"
}

phase3_set_user_password() {
  local username="$1" status
  status="$(proot-distro login "$TDE_DISTRO_NAME" -- passwd -S "$username" 2>/dev/null | awk '{print $2}')"
  if [ "$status" = "P" ]; then
    log_info "Password already set for '$username', skipping"
    return 0
  fi
  if [ "${TDE_DRY_RUN:-0}" = "1" ] || [ ! -t 0 ]; then
    return 0
  fi

  echo ""
  echo "Set a login password for '$username' (sudo fallback safety net):"
  proot-distro login "$TDE_DISTRO_NAME" -- passwd "$username" || \
    log_warn "Could not set a password for '$username' — passwordless sudo is configured below."
}

phase3_create_user_run() {
  log_info "=== Phase 3, step 2: user creation ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would prompt for a username, create user with zsh and wheel group, configure passwordless sudo"
    return 0
  fi

  phase3_ensure_sudo_installed

  local username
  username="$(phase3_prompt_username)"
  state_set ARCH_USERNAME "$username"

  # Batched user creation + sudoers setup + visudo validation in a single proot login
  proot-distro login "$TDE_DISTRO_NAME" -- env TDE_USER="$username" sh -c '
    set -e
    if id -u "$TDE_USER" >/dev/null 2>&1; then
      usermod -s /usr/bin/zsh -aG wheel "$TDE_USER" 2>/dev/null || true
    else
      useradd -m -G wheel -s /usr/bin/zsh "$TDE_USER" || exit 21
    fi
    mkdir -p /etc/sudoers.d
    grep -qE "^[#@]includedir[[:space:]]+/etc/sudoers\.d" /etc/sudoers || \
      echo "@includedir /etc/sudoers.d" >> /etc/sudoers
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-nopasswd
    chown root:root /etc/sudoers.d/wheel-nopasswd
    chmod 0440 /etc/sudoers.d/wheel-nopasswd
    echo "$TDE_USER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/user-$TDE_USER"
    chown root:root "/etc/sudoers.d/user-$TDE_USER"
    chmod 0440 "/etc/sudoers.d/user-$TDE_USER"
    visudo -c || exit 22
  ' >>"$TDE_LOG_FILE" 2>&1 || {
    local rc=$?
    [ "$rc" -eq 21 ] && log_fatal_code 321 "useradd failed for '$username'"
    log_fatal_code 322 "Could not configure passwordless sudo for user '$username' (visudo validation failed)"
  }

  phase3_set_user_password "$username"
  log_info "User '$username' configured with zsh shell and passwordless sudo"
}

phase3_user_ok() {
  local username uid
  username="$(state_get ARCH_USERNAME)"
  [ -n "$username" ] || return 1
  uid="$(proot-distro login "$TDE_DISTRO_NAME" -- id -u "$username" 2>/dev/null)"
  [[ "$uid" =~ ^[0-9]+$ ]] && [ "$uid" -ge 1000 ]
}