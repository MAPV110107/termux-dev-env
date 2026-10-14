# System helpers: container paths, network retries, interactive prompts,
# and marker-based idempotent file updates (host and container).

[ -n "${TDE_SYSTEM_LOADED:-}" ] && return 0
TDE_SYSTEM_LOADED=1

export TDE_DISTRO_NAME="${TDE_DISTRO_NAME:-${ARCH_DISTRO_ALIAS:-archarm}}"
TDE_ROOTFS_PATH="${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/installed-rootfs/$TDE_DISTRO_NAME"

container_home() {
  echo "$TDE_ROOTFS_PATH/home/$1"
}

_prompt() {
  local prompt_text="$1" default_value="${2:-}"
  if [ "${TDE_DRY_RUN:-0}" = "1" ] || [ ! -t 0 ]; then
    echo "$default_value"
    return 0
  fi
  local input
  read -r -p "$prompt_text" input
  echo "${input:-$default_value}"
}

retry_with_backoff() {
  local max_attempts="$1" delay="$2"
  shift 2
  local attempt=1 status

  while [ "$attempt" -le "$max_attempts" ]; do
    "$@" && return 0
    status=$?
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

_TDE_IA_AWK='$0==s{skip=1;pend=0;next} skip{if($0==e)skip=0;next} {if(pend){print x;pend=0} if(length($0)==0){pend=1}else{print}} END{if(pend)print x}'

idempotent_append() {
  local file="$1" marker_name="$2" content="$3" comment="${4:-#}"
  local start="$comment >>> termux-dev-env: $marker_name >>>"
  local end="$comment <<< termux-dev-env: $marker_name <<<"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -qF -- "$start" "$file"; then
    local tmp
    tmp="$(mktemp "${file}.XXXXXX")"
    awk -v s="$start" -v e="$end" "$_TDE_IA_AWK" "$file" > "$tmp"
    mv "$tmp" "$file"
  fi

  {
    echo ""
    echo "$start"
    echo "$content"
    echo "$end"
  } >> "$file"
}

idempotent_append_container() {
  local distro="$1" username="$2" container_path="$3" marker_name="$4" content="$5" comment="${6:-#}"
  printf '%s\n' "$content" | proot-distro login "$distro" --user "$username" \
    --env TDE_IA_PATH="$container_path" \
    --env TDE_IA_MARKER="$marker_name" \
    --env TDE_IA_COMMENT="$comment" \
    --env TDE_IA_AWK="$_TDE_IA_AWK" -- sh -c '
    f="$HOME/$TDE_IA_PATH"
    mkdir -p "$(dirname "$f")"
    touch "$f"
    start="$TDE_IA_COMMENT >>> termux-dev-env: $TDE_IA_MARKER >>>"
    end="$TDE_IA_COMMENT <<< termux-dev-env: $TDE_IA_MARKER <<<"
    ia_content="$(cat)"
    [ -n "$ia_content" ] || { echo "idempotent_append_container: empty stdin for $TDE_IA_MARKER" >&2; exit 1; }
    if grep -qF -- "$start" "$f"; then
      awk -v s="$start" -v e="$end" "$TDE_IA_AWK" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    fi
    { echo ""; echo "$start"; printf "%s\n" "$ia_content"; echo "$end"; } >> "$f"
  '
}