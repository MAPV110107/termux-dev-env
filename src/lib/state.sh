# Atomic KEY=VALUE store and phase state persistence.

[ -n "${TDE_STATE_LOADED:-}" ] && return 0
TDE_STATE_LOADED=1

TDE_STATE_FILE="${TDE_STATE_FILE:-$HOME/.config/termux-dev-env/state.env}"

kv_init() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || : > "$file"
}

kv_get() {
  local file="$1" key="$2" default="${3:-}" val
  val="$(grep -m1 "^${key}=" "$file" 2>/dev/null | cut -d= -f2- || true)"
  echo "${val:-$default}"
}

kv_has() {
  local file="$1" key="$2"
  [ -f "$file" ] && grep -q "^${key}=" "$file" 2>/dev/null
}

kv_set() {
  local file="$1" key="$2" value="$3" tmp
  kv_init "$file"
  tmp="$(mktemp "${file}.XXXXXX")"
  grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null || true
  echo "${key}=${value}" >> "$tmp"
  mv "$tmp" "$file"
}

kv_del() {
  local file="$1" key="$2" tmp
  [ -f "$file" ] || return 0
  tmp="$(mktemp "${file}.XXXXXX")"
  grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$file"
}

state_init() { kv_init "$TDE_STATE_FILE"; }
state_get()  { kv_get "$TDE_STATE_FILE" "$1" "${2:-}"; }
state_has()  { kv_has "$TDE_STATE_FILE" "$1"; }

state_set() {
  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] state_set $1=$2 (skipped, not persisted)"
    return 0
  fi
  kv_set "$TDE_STATE_FILE" "$1" "$2"
}

state_del() {
  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] state_del $1 (skipped, not persisted)"
    return 0
  fi
  kv_del "$TDE_STATE_FILE" "$1"
}

state_clear_prefix() {
  local prefix="$1" tmp
  [ -f "$TDE_STATE_FILE" ] || return 0
  tmp="$(mktemp "${TDE_STATE_FILE}.XXXXXX")"
  grep -v "^${prefix}_" "$TDE_STATE_FILE" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$TDE_STATE_FILE"
}