# Prevents two instances (e.g. the installer and update.sh, or two Termux
# sessions) from touching state.env or the rootfs at the same time.

[ -n "${TDE_LOCK_LOADED:-}" ] && return 0
TDE_LOCK_LOADED=1

TDE_LOCK_FILE="${TDE_LOCK_FILE:-/tmp/termux-dev-env.lock}"
TDE_LOCK_FD=200

lock_acquire() {
  eval "exec ${TDE_LOCK_FD}>\"$TDE_LOCK_FILE\""
  if ! flock -n "$TDE_LOCK_FD"; then
    echo "[FATAL] Another termux-dev-env process is already running" >&2
    exit "${EXIT_FATAL:-1}"
  fi
}

lock_release() {
  flock -u "$TDE_LOCK_FD" 2>/dev/null || true
}
