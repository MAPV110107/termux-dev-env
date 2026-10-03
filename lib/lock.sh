# Prevents two instances (e.g. the installer and update.sh, or two Termux
# sessions) from touching state.env or the rootfs at the same time.

[ -n "${TDE_LOCK_LOADED:-}" ] && return 0
TDE_LOCK_LOADED=1

TDE_LOCK_DIR="${TMPDIR:-${PREFIX:-/tmp}/tmp}"
[ -d "$TDE_LOCK_DIR" ] || TDE_LOCK_DIR="/tmp"
mkdir -p "$TDE_LOCK_DIR" 2>/dev/null || true
TDE_LOCK_FILE="${TDE_LOCK_FILE:-$TDE_LOCK_DIR/termux-dev-env.lock}"
# Left unset here on purpose: lock_acquire allocates it below. It used to
# be hardcoded to 200, which silently stomps any other fd 200 in the same
# shell (a nested source of this file, or a caller that picked the same
# well-known number). core.sh reads TDE_LOCK_FD after lock_acquire to
# close the descriptor before its final exec, so it must still end up
# exported under that name.
TDE_LOCK_FD="${TDE_LOCK_FD:-}"

lock_acquire() {
  # {var}> asks bash (4.1+, and Termux ships 5.x) for a free descriptor
  # >= 10 and assigns its number to the variable — no fixed number to
  # collide with. Falls back to the historical 200 on a shell too old to
  # support it, which keeps this file usable if it is ever sourced by
  # something other than core.sh.
  if ! exec {TDE_LOCK_FD}>"$TDE_LOCK_FILE" 2>/dev/null; then
    TDE_LOCK_FD=200
    eval "exec ${TDE_LOCK_FD}>\"$TDE_LOCK_FILE\""
  fi
  export TDE_LOCK_FD
  if ! flock -n "$TDE_LOCK_FD"; then
    echo "[FATAL] Another termux-dev-env process is already running" >&2
    exit "${EXIT_FATAL:-1}"
  fi
}

lock_release() {
  [ -n "${TDE_LOCK_FD:-}" ] || return 0
  flock -u "$TDE_LOCK_FD" 2>/dev/null || true
}
