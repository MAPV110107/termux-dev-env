# Appends content between named markers, stripping any previous block with
# that name first — safe to call on every run without ever duplicating
# the block. comment_prefix defaults to "#" (shell files); pass "--" for
# Lua files, or the marker lines would break Lua syntax.

[ -n "${TDE_IDEMPOTENT_APPEND_LOADED:-}" ] && return 0
TDE_IDEMPOTENT_APPEND_LOADED=1

# Drops the previous block for marker s..e AND the single blank separator
# line that was written immediately before it. Without that second part,
# every re-run left its separator behind and the file grew by one blank
# line per run (a real leak into .zshrc/.bashrc/lua configs on every
# archreapply / --reinstall). "print x" prints an empty line (x is
# unset) so the program needs no quotes and survives shell nesting.
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

# Container-side equivalent, for files that live inside the proot rootfs
# (dotfiles, LazyVim's lua/config/*.lua, etc.) — checks and writes
# through 'proot-distro login --user', never a host-side path built from
# container_home(). See docs/TROUBLESHOOTING.md's ".zshrc missing"
# section: a direct host-side path into the rootfs did not reliably
# reflect what had just been written from inside proot in the wild, so
# every container file this project touches repeatedly (not just
# one-shot installer output) should go through this, not a raw path.
#
# container_path is relative to the user's $HOME inside the container
# (e.g. ".config/nvim/lua/config/options.lua", no leading ~/ or /).
idempotent_append_container() {
  local distro="$1" username="$2" container_path="$3" marker_name="$4" content="$5" comment="${6:-#}"
  proot-distro login "$distro" --user "$username" \
    --env TDE_IA_PATH="$container_path" \
    --env TDE_IA_MARKER="$marker_name" \
    --env TDE_IA_CONTENT="$content" \
    --env TDE_IA_COMMENT="$comment" \
    --env TDE_IA_AWK="$_TDE_IA_AWK" -- sh -c '
    f="$HOME/$TDE_IA_PATH"
    mkdir -p "$(dirname "$f")"
    touch "$f"
    start="$TDE_IA_COMMENT >>> termux-dev-env: $TDE_IA_MARKER >>>"
    end="$TDE_IA_COMMENT <<< termux-dev-env: $TDE_IA_MARKER <<<"
    if grep -qF -- "$start" "$f"; then
      awk -v s="$start" -v e="$end" "$TDE_IA_AWK" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    fi
    { echo ""; echo "$start"; printf "%s\n" "$TDE_IA_CONTENT"; echo "$end"; } >> "$f"
  '
}
