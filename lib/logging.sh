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
