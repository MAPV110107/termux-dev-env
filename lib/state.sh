# Persists phase progress so a crash or closed session resumes instead of
# re-running everything. Thin wrapper over kv.sh bound to state.env — kept
# as its own file because callers (core.sh, every phaseN_run) read it by
# this name, not by a generic kv_get/kv_set call.

[ -n "${TDE_STATE_LOADED:-}" ] && return 0
TDE_STATE_LOADED=1

TDE_STATE_FILE="${TDE_STATE_FILE:-$HOME/.config/termux-dev-env/state.env}"

state_init() { kv_init "$TDE_STATE_FILE"; }
state_get()  { kv_get "$TDE_STATE_FILE" "$1"; }

# Never persists under --dry-run. core.sh calls this unconditionally after
# every phase; without this guard, a dry-run marks every phase done and
# the next real run silently skips everything.
state_set() {
  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] state_set $1=$2 (skipped, not persisted)"
    return 0
  fi
  kv_set "$TDE_STATE_FILE" "$1" "$2"
}
