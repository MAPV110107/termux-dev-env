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
  # Opened with >> and not >: plain > truncates the file at open()
  # time, before flock is even attempted — so a second process trying
  # (and failing) to take the lock would wipe the holder's PID out of
  # the file on its way to the error message, leaving that message
  # unable to name who actually holds it. Append never truncates, and
  # flock behaves identically either way.
  #
  # Version-gated rather than "try it and fall back on error": a bare
  # `exec {fd}>file 2>/dev/null` sends the *shell's* stderr to
  # /dev/null permanently (exec's redirections apply to the shell
  # itself, not to a child), which silently swallowed every later
  # error message including this function's own FATAL output.
  if [ "${BASH_VERSINFO[0]:-0}" -gt 4 ] || \
     { [ "${BASH_VERSINFO[0]:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -ge 1 ]; }; then
    exec {TDE_LOCK_FD}>>"$TDE_LOCK_FILE"
  else
    TDE_LOCK_FD=200
    eval "exec ${TDE_LOCK_FD}>>\"$TDE_LOCK_FILE\""
  fi
  export TDE_LOCK_FD
  if ! flock -n "$TDE_LOCK_FD"; then
    # flock's advisory lock is released by the kernel when the holding
    # process dies — even on SIGKILL — so reaching here normally means a
    # live process really does hold it, and the lock file itself can
    # never go "stale" the way a plain lockfile would. But Android's
    # low-memory killer makes people suspect exactly that, so name the
    # holder and give an explicit escape hatch instead of just refusing.
    local holder=""
    [ -s "$TDE_LOCK_FILE" ] && holder="$(head -n1 "$TDE_LOCK_FILE" 2>/dev/null)"
    if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
      echo "[FATAL] Another termux-dev-env process is already running (PID $holder)." >&2
      echo "        Wait for it to finish, or stop it with: kill $holder" >&2
    else
      # The recorded PID is gone but the lock is still held: another
      # process inherited the descriptor, or the file predates it.
      # Never break the lock automatically — doing that is how two
      # installers end up writing state.env at the same time.
      echo "[FATAL] termux-dev-env is locked${holder:+ (recorded PID $holder is no longer running)}." >&2
      echo "        If you are certain nothing else is running: rm -f \"$TDE_LOCK_FILE\"" >&2
    fi
    exit "${EXIT_FATAL:-1}"
  fi
  # Record the holder for the message above, only once the lock is
  # actually held — so the file always names the real owner, and the
  # truncation here can never race another process.
  printf '%s\n' "$$" > "$TDE_LOCK_FILE" 2>/dev/null || true
}

lock_release() {
  [ -n "${TDE_LOCK_FD:-}" ] || return 0
  flock -u "$TDE_LOCK_FD" 2>/dev/null || true
}
