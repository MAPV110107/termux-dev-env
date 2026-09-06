# Fails fast and loud: any unhandled error aborts with the failing line
# instead of continuing on a half-broken environment.

[ -n "${TDE_ERROR_HANDLING_LOADED:-}" ] && return 0
TDE_ERROR_HANDLING_LOADED=1

set -euo pipefail

# Exit code convention used across every script in this project.
export EXIT_OK=0
export EXIT_FATAL=1
export EXIT_WARN=2

_error_trap() {
  local line="$1"
  echo "[FATAL] ${BASH_SOURCE[1]:-$0}:${line} — command failed, aborting" >&2
  exit "$EXIT_FATAL"
}

trap '_error_trap $LINENO' ERR
