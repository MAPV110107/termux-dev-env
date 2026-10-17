# Core error handling, strict mode, and centralized logging with rotation.

[ -n "${TDE_CORE_LOADED:-}" ] && return 0
TDE_CORE_LOADED=1

set -euo pipefail

export EXIT_OK=0
export EXIT_FATAL=1
export EXIT_WARN=2

TDE_CONFIG_DIR="${TDE_CONFIG_DIR:-$HOME/.config/termux-dev-env}"
TDE_LOG_DIR="$TDE_CONFIG_DIR/logs"
TDE_LOG_KEEP="${TDE_LOG_KEEP:-20}"

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

tde_soft_begin() {
  TDE_SOFT_FAIL=1
  set +e
}

tde_soft_end() {
  TDE_SOFT_FAIL=0
  set -e
}

log_rotate() {
  local pattern="$1" keep="${2:-$TDE_LOG_KEEP}" listing count
  # shellcheck disable=SC2086
  listing="$(ls -1t "$TDE_LOG_DIR"/$pattern 2>/dev/null || true)"
  [ -n "$listing" ] || return 0
  count="$(printf '%s\n' "$listing" | wc -l)"
  [ "${count:-0}" -gt "$keep" ] || return 0
  printf '%s\n' "$listing" | tail -n +"$((keep + 1))" | while IFS= read -r old; do
    [ -n "$old" ] && rm -f "$old"
  done
  return 0
}

log_init() {
  mkdir -p "$TDE_LOG_DIR"
  TDE_LOG_FILE="$TDE_LOG_DIR/install_$(date +%Y%m%d_%H%M%S).log"
  export TDE_LOG_FILE
  : > "$TDE_LOG_FILE"
  log_rotate "install_*.log"
  log_rotate "install_report_*.log"
}

_log() {
  local level="$1"; shift
  local ts line
  printf -v ts '%(%H:%M:%S)T' -1 2>/dev/null || ts="$(date '+%H:%M:%S')"
  line="[$ts] [$level] $*"
  echo "$line"
  [ -n "${TDE_LOG_FILE:-}" ] && echo "$line" >> "$TDE_LOG_FILE"
}

log_info() { _log INFO "$@"; }
log_warn() { _log WARN "$@"; }

log_fatal() {
  _log FATAL "$@"
  exit "${EXIT_FATAL:-1}"
}

log_fatal_code() {
  local code="$1"; shift
  _log FATAL "[E$code] $*"
  mkdir -p "$TDE_CONFIG_DIR" 2>/dev/null || true
  {
    echo "CODE=E$code"
    echo "MESSAGE=$*"
    echo "TIMESTAMP=$(date -Iseconds 2>/dev/null || date)"
    echo "LOG_FILE=${TDE_LOG_FILE:-}"
  } > "$TDE_CONFIG_DIR/last_error.env" 2>/dev/null || true
  exit "${EXIT_FATAL:-1}"
}