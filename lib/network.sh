# Retries a command with exponential backoff. Used by phase 1 (pkg update/
# install) and phase 3 (rootfs download) — both hit the network and both
# need to survive a mobile connection dropping mid-request, not just abort.

[ -n "${TDE_NETWORK_LOADED:-}" ] && return 0
TDE_NETWORK_LOADED=1

retry_with_backoff() {
  local max_attempts="$1" delay="$2"
  shift 2
  local attempt=1

  while [ "$attempt" -le "$max_attempts" ]; do
    if "$@"; then
      return 0
    fi
    if [ "$attempt" -eq "$max_attempts" ]; then
      log_warn "Command failed after $max_attempts attempts: $*"
      return 1
    fi
    log_warn "Attempt $attempt/$max_attempts failed, retrying in ${delay}s: $*"
    sleep "$delay"
    delay=$((delay * 2))
    attempt=$((attempt + 1))
  done
}
