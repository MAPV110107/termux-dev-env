# Fails fast and loud: any unhandled error aborts with the failing line
# instead of continuing on a half-broken environment.

[ -n "${TDE_ERROR_HANDLING_LOADED:-}" ] && return 0
TDE_ERROR_HANDLING_LOADED=1

set -euo pipefail

# Exit code convention used across every script in this project.
export EXIT_OK=0
export EXIT_FATAL=1
export EXIT_WARN=2

# Reports the command and its exit status, not just a line number — a
# bare "command failed" on line N meant reading the source to find out
# what had even run.
#
# For a region that is genuinely allowed to fail, use the pair below
# rather than setting TDE_SOFT_FAIL by hand: the ERR trap alone cannot
# rescue anything, because `set -e` exits the shell regardless of what
# the trap returns. tde_soft_begin suspends both.
_error_trap() {
  local line="$1" status="$2" cmd="$3" src="${BASH_SOURCE[1]:-$0}"
  if [ "${TDE_SOFT_FAIL:-0}" = "1" ]; then
    echo "[WARN] ${src}:${line} — '${cmd}' exited ${status} (TDE_SOFT_FAIL=1, continuing)" >&2
    return 0
  fi
  echo "[FATAL] ${src}:${line} — '${cmd}' exited ${status}, aborting" >&2
  exit "$EXIT_FATAL"
}

trap '_error_trap "$LINENO" "$?" "$BASH_COMMAND"' ERR

# Bracket a block that is allowed to fail:
#   tde_soft_begin; risky_thing; tde_soft_end
# Nothing in this project enables it globally — it exists so a future
# caller does not reach for `set +e` and forget to restore it.
tde_soft_begin() {
  TDE_SOFT_FAIL=1
  set +e
}
tde_soft_end() {
  TDE_SOFT_FAIL=0
  set -e
}
