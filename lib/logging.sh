# Centralized logging: every phase writes through here so phase 5's final
# report can consolidate logs that already exist, instead of generating
# them for the first time at the end.

[ -n "${TDE_LOGGING_LOADED:-}" ] && return 0
TDE_LOGGING_LOADED=1

TDE_CONFIG_DIR="${TDE_CONFIG_DIR:-$HOME/.config/termux-dev-env}"
TDE_LOG_DIR="$TDE_CONFIG_DIR/logs"

log_init() {
  mkdir -p "$TDE_LOG_DIR"
  TDE_LOG_FILE="$TDE_LOG_DIR/install_$(date +%Y%m%d_%H%M%S).log"
  export TDE_LOG_FILE
  : > "$TDE_LOG_FILE"
}

_log() {
  local level="$1"; shift
  local line
  line="[$(date '+%H:%M:%S')] [$level] $*"
  echo "$line"
  [ -n "${TDE_LOG_FILE:-}" ] && echo "$line" >> "$TDE_LOG_FILE"
}

log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }

# Logs, then aborts. Distinct from _error_trap: this is a deliberate check
# failing (bad input, missing dependency), not an unexpected command error.
log_fatal() {
  _log FATAL "$@"
  exit "${EXIT_FATAL:-1}"
}

# Same as log_fatal, but tags the failure with a stable, documented error
# code (see docs/ERROR_CODES.md) — lets a failure be identified from a
# screenshot alone, without needing the full log, and gives a fixed
# string to search TROUBLESHOOTING.md for. Also drops a small
# machine-readable marker (last_error.env) that `archdiag` reads, so a
# bug report can quote the exact code + message even after the terminal
# scrollback is gone.
log_fatal_code() {
  local code="$1"; shift
  _log FATAL "[E$code] $*"
  {
    echo "CODE=E$code"
    echo "MESSAGE=$*"
    echo "TIMESTAMP=$(date -Iseconds 2>/dev/null || date)"
    echo "LOG_FILE=${TDE_LOG_FILE:-}"
  } > "$TDE_CONFIG_DIR/last_error.env" 2>/dev/null || true
  exit "${EXIT_FATAL:-1}"
}
