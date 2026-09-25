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
  log_info "Installing sudo and zsh inside $TDE_DISTRO_NAME"
  proot-distro login "$TDE_DISTRO_NAME" -- pacman -Sy --noconfirm sudo zsh || \
    log_fatal "Could not install sudo/zsh inside $TDE_DISTRO_NAME"
}

# Safety net, not the primary mechanism: wheel already gets passwordless
# sudo below, and 'proot-distro login --user' (both the interactive
# launcher and every scripted phase 4-6 step) never checks a password at
# all — proot execs directly as that UID, so this does not make opening
# Arch from Termux need a password either. This exists only so the
# account isn't left completely unauthenticatable (useradd never sets
# one on its own) if the NOPASSWD sudoers rule below doesn't take effect
# for some reason (seen in the wild — sudo still prompted despite it).
# Runs passwd's own interactive prompt directly rather than _prompt (which
# echoes input to the screen) so the password is never visible or passed
# through a shell variable.
phase3_set_user_password() {
  local username="$1" status
  status="$(proot-distro login "$TDE_DISTRO_NAME" -- passwd -S "$username" 2>/dev/null | awk '{print $2}')"
  if [ "$status" = "P" ]; then
    log_info "Password already set for '$username', skipping"
    return 0
  fi

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would prompt to set a login password for '$username' (sudo safety net only — not needed to open Arch from Termux)"
    return 0
  fi
  if [ ! -t 0 ]; then
    log_warn "No interactive terminal — skipping password prompt for '$username'. Set one later with: proot-distro login $TDE_DISTRO_NAME -- passwd $username"
    return 0
  fi

  echo ""
  echo "Set a login password for '$username' (used only as a sudo fallback —"
  echo "wheel already has passwordless sudo, and opening Arch from Termux"
  echo "never needs this password either):"
  proot-distro login "$TDE_DISTRO_NAME" -- passwd "$username" || \
    log_warn "Could not set a password for '$username' — if passwordless sudo doesn't work either, you'll be locked out of sudo until you set one: proot-distro login $TDE_DISTRO_NAME -- passwd $username"
}

phase3_create_user_run() {
  log_info "=== Phase 3, step 2: user creation ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would prompt for a username, useradd -m -G wheel -s /usr/bin/zsh inside $TDE_DISTRO_NAME, install sudo/zsh, prompt for a password (sudo fallback only), enable passwordless sudo for wheel"
    return 0
  fi

  phase3_ensure_sudo_installed

  local username
  username="$(phase3_prompt_username)"
  state_set ARCH_USERNAME "$username"

  # Idempotent: if a previous run already created the user but failed on a
  # later step (sudo install, sudoers.d write), a naive retry would call
  # useradd again on the same name and crash with "user already exists".
  if proot-distro login "$TDE_DISTRO_NAME" -- id -u "$username" >/dev/null 2>&1; then
    log_info "User '$username' already exists, ensuring shell is zsh"
    proot-distro login "$TDE_DISTRO_NAME" -- usermod -s /usr/bin/zsh "$username" 2>/dev/null || true
  else
    log_info "Creating user '$username' inside $TDE_DISTRO_NAME"
    proot-distro login "$TDE_DISTRO_NAME" -- useradd -m -G wheel -s /usr/bin/zsh "$username" || \
      log_fatal "useradd failed for '$username'"
  fi

  phase3_set_user_password "$username"

  # @includedir defensively re-added in case this sudo package's default
  # /etc/sudoers doesn't ship it (seen on some distros/base installs) —
  # without it, sudoers.d is silently never read at all, no error either
  # way. visudo -c at the end validates the whole config (main file +
  # every sudoers.d include) and fails loud on a syntax problem, instead
  # of leaving a rule that looks written but sudo silently never applies.
  proot-distro login "$TDE_DISTRO_NAME" -- sh -c '
    set -e
    grep -qE "^[#@]includedir[[:space:]]+/etc/sudoers\.d" /etc/sudoers || \
      echo "@includedir /etc/sudoers.d" >> /etc/sudoers
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-nopasswd
    chown root:root /etc/sudoers.d/wheel-nopasswd
    chmod 0440 /etc/sudoers.d/wheel-nopasswd
    visudo -c
  ' >>"$TDE_LOG_FILE" 2>&1 || \
    log_fatal "Could not configure passwordless sudo for wheel — visudo reported a syntax problem, see $TDE_LOG_FILE. A password was set above as a fallback: proot-distro login $TDE_DISTRO_NAME -- passwd $username"

  log_info "User '$username' created with zsh shell and passwordless sudo (wheel group)"
}

# Post-condition, checked by core.sh before marking PHASE3_USER_CREATED.
phase3_user_ok() {
  local username uid
  username="$(state_get ARCH_USERNAME)"
  [ -n "$username" ] || return 1
  uid="$(proot-distro login "$TDE_DISTRO_NAME" -- id -u "$username" 2>/dev/null)"
  [[ "$uid" =~ ^[0-9]+$ ]] && [ "$uid" -ge 1000 ]
}
