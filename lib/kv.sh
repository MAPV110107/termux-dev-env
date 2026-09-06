# Generic KEY=VALUE file reader/writer. state.env and diagnostics.env are
# both flat files of this shape — one implementation, two callers.

[ -n "${TDE_KV_LOADED:-}" ] && return 0
TDE_KV_LOADED=1

kv_init() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || : > "$file"
}

kv_get() {
  local file="$1" key="$2" default="${3:-}"
  local val
  val="$(grep -m1 "^${key}=" "$file" 2>/dev/null | cut -d= -f2-)"
  echo "${val:-$default}"
}

# Atomic write-then-rename so a crash mid-write never truncates the file.
kv_set() {
  local file="$1" key="$2" value="$3" tmp
  kv_init "$file"
  tmp="$(mktemp "${file}.XXXXXX")"
  grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null || true
  echo "${key}=${value}" >> "$tmp"
  mv "$tmp" "$file"
}
