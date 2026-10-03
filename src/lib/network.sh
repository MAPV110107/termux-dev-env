# Retries a command with exponential backoff. Used by phase 1 (pkg update/
# install) and phase 3 (rootfs download) — both hit the network and both
# need to survive a mobile connection dropping mid-request, not just abort.

[ -n "${TDE_NETWORK_LOADED:-}" ] && return 0
TDE_NETWORK_LOADED=1

retry_with_backoff() {
  local max_attempts="$1" delay="$2"
  shift 2
  local attempt=1

  local status
  while [ "$attempt" -le "$max_attempts" ]; do
    # `"$@" && return 0` rather than `if "$@"; then return 0; fi`: an
    # `if` whose condition fails and which has no else branch exits
    # with status 0, so reading $? after it always gave 0 and the
    # interrupt check below could never fire. With && the status of the
    # failed command survives.
    "$@" && return 0
    status=$?
    # Ctrl+C (130) and SIGTERM (143) are the person (or Android's
    # low-memory killer) saying stop — retrying them turned a single
    # Ctrl+C into "press it three more times, each after a longer
    # sleep". Any other non-zero status is a real failure worth retrying.
    if [ "$status" -eq 130 ] || [ "$status" -eq 143 ]; then
      log_warn "Interrupted (exit $status) — not retrying: $*"
      return "$status"
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
