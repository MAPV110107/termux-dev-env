# Generic KEY=VALUE file reader/writer. state.env and diagnostics.env are
# both flat files of this shape — one implementation, two callers.

[ -n "${TDE_KV_LOADED:-}" ] && return 0
TDE_KV_LOADED=1

kv_init() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || : > "$file"
}

# NOTE: a key explicitly set to the empty string is reported as absent,
# i.e. kv_get returns the default for both "KEY=" and no KEY line at all.
# Every value this project stores is a 0/1 flag or a non-empty string
# (usernames, paths), so the two cases are equivalent today. If a caller
# ever needs to store a meaningful "", use kv_has to disambiguate rather
# than changing this function's contract — callers like state_get rely on
# the current "missing or empty -> default" behaviour.
kv_get() {
  local file="$1" key="$2" default="${3:-}"
  local val
  val="$(grep -m1 "^${key}=" "$file" 2>/dev/null | cut -d= -f2- || true)"
  echo "${val:-$default}"
}

# True when the key line exists at all, regardless of its value — the
# "is it set?" question kv_get deliberately cannot answer.
kv_has() {
  local file="$1" key="$2"
  [ -f "$file" ] && grep -q "^${key}=" "$file" 2>/dev/null
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

kv_del() {
  local file="$1" key="$2" tmp
  [ -f "$file" ] || return 0
  tmp="$(mktemp "${file}.XXXXXX")"
  grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$file"
}
