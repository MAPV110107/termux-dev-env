# Phase 3, step 2 — user creation. Validates the username before it ever
# reaches useradd, so a typo fails here with a clear message instead of
# breaking useradd silently mid-installation.

[ -n "${TDE_CREATE_USER_LOADED:-}" ] && return 0
TDE_CREATE_USER_LOADED=1

TDE_RESERVED_USERNAMES="root bin daemon sys adm lp mail news uucp man proxy www-data backup list irc gnats nobody systemd-network systemd-resolve messagebus sshd admin"

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
  log_info "Installing sudo inside $TDE_DISTRO_NAME"
  proot-distro login "$TDE_DISTRO_NAME" -- pacman -Sy --noconfirm sudo || \
    log_fatal "Could not install sudo inside $TDE_DISTRO_NAME"
}

phase3_create_user_run() {
  log_info "=== Phase 3, step 2: user creation ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would prompt for a username, useradd -m -G wheel inside $TDE_DISTRO_NAME, install sudo, enable passwordless sudo for wheel"
    return 0
  fi

  local username
  username="$(phase3_prompt_username)"
  state_set ARCH_USERNAME "$username"

  # Idempotent: if a previous run already created the user but failed on a
  # later step (sudo install, sudoers.d write), a naive retry would call
  # useradd again on the same name and crash with "user already exists".
  if proot-distro login "$TDE_DISTRO_NAME" -- id -u "$username" >/dev/null 2>&1; then
    log_info "User '$username' already exists, skipping useradd"
  else
    log_info "Creating user '$username' inside $TDE_DISTRO_NAME"
    proot-distro login "$TDE_DISTRO_NAME" -- useradd -m -G wheel -s /bin/bash "$username" || \
      log_fatal "useradd failed for '$username'"
  fi

  phase3_ensure_sudo_installed

  proot-distro login "$TDE_DISTRO_NAME" -- sh -c \
    "echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel-nopasswd && chown root:root /etc/sudoers.d/wheel-nopasswd && chmod 0440 /etc/sudoers.d/wheel-nopasswd" || \
    log_fatal "Could not configure passwordless sudo for wheel"

  log_info "User '$username' created with passwordless sudo (wheel group)"
}

# Post-condition, checked by core.sh before marking PHASE3_USER_CREATED.
phase3_user_ok() {
  local username uid
  username="$(state_get ARCH_USERNAME)"
  [ -n "$username" ] || return 1
  uid="$(proot-distro login "$TDE_DISTRO_NAME" -- id -u "$username" 2>/dev/null)"
  [[ "$uid" =~ ^[0-9]+$ ]] && [ "$uid" -ge 1000 ]
}
