# Appends content between named markers, stripping any previous block with
# that name first — safe to call on every run without ever duplicating
# the block. comment_prefix defaults to "#" (shell files); pass "--" for
# Lua files, or the marker lines would break Lua syntax.

[ -n "${TDE_IDEMPOTENT_APPEND_LOADED:-}" ] && return 0
TDE_IDEMPOTENT_APPEND_LOADED=1

idempotent_append() {
  local file="$1" marker_name="$2" content="$3" comment="${4:-#}"
  local start="$comment >>> termux-dev-env: $marker_name >>>"
  local end="$comment <<< termux-dev-env: $marker_name <<<"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -qF -- "$start" "$file"; then
    local tmp
    tmp="$(mktemp "${file}.XXXXXX")"
    awk -v s="$start" -v e="$end" '$0==s{skip=1} !skip{print} $0==e{skip=0}' "$file" > "$tmp"
    mv "$tmp" "$file"
  fi

  {
    echo ""
    echo "$start"
    echo "$content"
    echo "$end"
  } >> "$file"
}
