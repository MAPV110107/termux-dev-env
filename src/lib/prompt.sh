# Centralized prompt: returns the default immediately under --dry-run
# without touching the terminal. Every interactive read in phases 3/4
# goes through this, so a future refactor that calls a prompt function
# directly (bypassing a *_run guard) still can't make dry-run interactive.
#
# Lives in its own always-sourced lib on purpose. It used to be defined
# in lib/validate_env.sh, which core.sh only sources inside the
# "PHASE1_DONE != 1" branch — so on any *resumed* run (the exact case
# the state machine exists for: phase 1 done, install died later, user
# re-runs) create_user.sh / dev_toolchain.sh / fs_utils.sh called it and
# got "_prompt: command not found", which under 'set -euo pipefail'
# aborts the whole installer. Sourcing it unconditionally from core.sh's
# preamble is what makes those three call sites safe on every path.

[ -n "${TDE_PROMPT_LOADED:-}" ] && return 0
TDE_PROMPT_LOADED=1

_prompt() {
  local prompt_text="$1" default_value="${2:-}"
  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    echo "$default_value"
    return 0
  fi
  local input
  read -r -p "$prompt_text" input
  echo "${input:-$default_value}"
}
