# Process concurrency lock using flock and dynamic file descriptors.

[ -n "${TDE_LOCK_LOADED:-}" ] && return 0
TDE_LOCK_LOADED=1

TDE_LOCK_DIR="${TMPDIR:-${PREFIX:-/tmp}/tmp}"
mkdir -p "${TDE_LOCK_DIR:-/tmp}" 2>/dev/null || true
[ -d "$TDE_LOCK_DIR" ] || TDE_LOCK_DIR="/tmp"
TDE_LOCK_FILE="${TDE_LOCK_FILE:-$TDE_LOCK_DIR/termux-dev-env.lock}"
TDE_LOCK_FD="${TDE_LOCK_FD:-}"

lock_acquire() {
  if [ "${BASH_VERSINFO[0]:-0}" -gt 4 ] || \
     { [ "${BASH_VERSINFO[0]:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -ge 1 ]; }; then
    exec {TDE_LOCK_FD}>>"$TDE_LOCK_FILE"
  else
    TDE_LOCK_FD=200
    eval "exec ${TDE_LOCK_FD}>>\"$TDE_LOCK_FILE\""
  fi
  export TDE_LOCK_FD

  if ! flock -n "$TDE_LOCK_FD"; then
    local holder=""
    [ -s "$TDE_LOCK_FILE" ] && holder="$(head -n1 "$TDE_LOCK_FILE" 2>/dev/null)"
    if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
      echo "[FATAL] Another termux-dev-env process is already running (PID $holder)." >&2
      echo "        Wait for it to finish, or stop it with: kill $holder" >&2
    else
      echo "[FATAL] termux-dev-env is locked${holder:+ (recorded PID $holder is no longer running)}." >&2
      echo "        If you are certain nothing else is running: rm -f \"$TDE_LOCK_FILE\"" >&2
    fi
    exit "${EXIT_FATAL:-1}"
  fi
  printf '%s\n' "$$" > "$TDE_LOCK_FILE" 2>/dev/null || true
}

lock_release() {
  [ -n "${TDE_LOCK_FD:-}" ] || return 0
  flock -u "$TDE_LOCK_FD" 2>/dev/null || true
}