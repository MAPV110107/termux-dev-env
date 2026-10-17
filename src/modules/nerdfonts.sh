# Phase 4, step 2 — Bulletproof Nerd Font installation and verification.
# Specifically selects JetBrainsMonoNerdFontMono-Regular.ttf (strictly 1-cell
# monospace glyphs) so terminal icons never clip or break cursor alignment.

[ -n "${TDE_MODULE_NERDFONTS_LOADED:-}" ] && return 0
TDE_MODULE_NERDFONTS_LOADED=1

TDE_NERDFONT_PKG="ttf-jetbrains-mono-nerd"
TDE_NERDFONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
TDE_NERDFONT_TMPDIR="$HOME/.cache/termux-dev-env/nerdfont"
TDE_NERDFONT_ATTEMPTS="${TDE_NERDFONT_ATTEMPTS:-3}"
TDE_NERDFONT_MIN_BYTES="${TDE_NERDFONT_MIN_BYTES:-1000000}"

# Verifies both minimum plausible size (>100KB) and TrueType/OpenType magic bytes.
nerdfont_file_ok() {
  local f="${1:-$HOME/.termux/font.ttf}" magic
  [ -f "$f" ] || return 1
  [ "$(wc -c < "$f" 2>/dev/null || echo 0)" -gt 102400 ] || return 1
  magic="$(od -An -tx1 -N4 "$f" 2>/dev/null | tr -d ' \n')"
  case "$magic" in
    00010000|4f54544f|74727565|74746366) return 0 ;;
    *) return 1 ;;
  esac
}

# Distinguishes a full patched Nerd Font (~2.4 MB) from an unpatched TTF (~300 KB).
nerdfont_is_patched() {
  local f="${1:-$HOME/.termux/font.ttf}"
  nerdfont_file_ok "$f" || return 1
  [ "$(wc -c < "$f" 2>/dev/null || echo 0)" -gt "$TDE_NERDFONT_MIN_BYTES" ]
}

_nerdfont_smoke_test() {
  printf '  Glyph check: \ue0b0 \u00b1 \ue0a0 \u27a6 \u2718 \u26a1 \u2699 \uf115 \ue795 \uf07c\n'
}

_nerdfont_print_forcestop_banner() {
  local b="" r="" line="============================================================"
  if [ -t 2 ]; then b=$'\033[1;33m'; r=$'\033[0m'; fi
  {
    printf '\n%s%s\n' "$b" "$line"
    printf '[IMPORTANT] JetBrainsMono Nerd Font (Mono Regular) installed.\n'
    printf 'If any icons above still appear as empty boxes or question marks:\n'
    printf '  1. Open Android Settings > Apps > Termux > Force stop\n'
    printf '  2. Reopen Termux (Android caches font.ttf in app memory)\n'
    printf 'Or via ADB/Shizuku: adb shell am force-stop com.termux\n'
    printf '%s%s\n\n' "$line" "$r"
  } >&2
  return 0
}

# Atomic inode-replacing installation: writes to font.ttf.tmp, validates magic bytes
# and patched size, removes old font.ttf so Android's mmap cannot stay attached to
# the old inode, and moves the validated font into place.
_nerdfont_atomic_install() {
  local src_stream_cmd="$1"
  mkdir -p "$HOME/.termux"
  local tmp_font="$HOME/.termux/font.ttf.tmp"
  rm -f "$tmp_font"

  if ! eval "$src_stream_cmd" > "$tmp_font" 2>/dev/null; then
    rm -f "$tmp_font"
    return 1
  fi

  if ! nerdfont_is_patched "$tmp_font"; then
    log_warn "Candidate font file failed patched Nerd Font validation (size/magic bytes) — discarding"
    rm -f "$tmp_font"
    return 1
  fi

  rm -f "$HOME/.termux/font.ttf"
  mv "$tmp_font" "$HOME/.termux/font.ttf"
  chmod 644 "$HOME/.termux/font.ttf"
  return 0
}

phase4_install_nerdfont_pkg() {
  proot-distro login "$TDE_DISTRO_NAME" -- pacman -S --noconfirm --needed "$TDE_NERDFONT_PKG" 2>>"$TDE_LOG_FILE" || return 1

  local rel_path
  rel_path="$(proot-distro login "$TDE_DISTRO_NAME" -- pacman -Ql "$TDE_NERDFONT_PKG" 2>/dev/null \
    | awk '{print $2}' | grep -iE 'JetBrainsMonoNerdFontMono-Regular\.ttf$|NerdFontMono-Regular\.ttf$' | head -n1)"
  if [ -z "$rel_path" ]; then
    rel_path="$(proot-distro login "$TDE_DISTRO_NAME" -- pacman -Ql "$TDE_NERDFONT_PKG" 2>/dev/null \
      | awk '{print $2}' | grep -iE '\.ttf$' | grep -iE 'mono' | grep -iE 'regular' | head -n1)"
  fi
  [ -n "$rel_path" ] || return 1

  _nerdfont_atomic_install "proot-distro login \"$TDE_DISTRO_NAME\" -- cat \"$rel_path\""
}

phase4_install_nerdfont_zip_fallback() {
  if ! command -v unzip >/dev/null 2>&1; then
    retry_with_backoff 3 5 pkg install -y unzip || return 1
  fi
  mkdir -p "$TDE_NERDFONT_TMPDIR"
  retry_with_backoff 3 5 curl -fL -o "$TDE_NERDFONT_TMPDIR/JetBrainsMono.zip" "$TDE_NERDFONT_URL" || return 1
  unzip -o -q "$TDE_NERDFONT_TMPDIR/JetBrainsMono.zip" -d "$TDE_NERDFONT_TMPDIR" || return 1

  local mono_ttf="" pattern
  for pattern in '*NerdFontMono-Regular.ttf' '*NerdFont-Regular.ttf' '*JetBrainsMono*Regular*.ttf'; do
    mono_ttf="$(find "$TDE_NERDFONT_TMPDIR" -iname "$pattern" | head -n1)"
    [ -n "$mono_ttf" ] && break
  done
  [ -n "$mono_ttf" ] || return 1

  _nerdfont_atomic_install "cat \"$mono_ttf\""
}

phase4_nerdfonts_run() {
  log_info "=== Phase 4, step 2: Nerd Font installation & glyph verification ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would install $TDE_NERDFONT_PKG (or zip fallback) to ~/.termux/font.ttf with fresh inode and reload Termux style"
    return 0
  fi

  if nerdfont_is_patched "$HOME/.termux/font.ttf"; then
    log_info "Patched Nerd Font already installed and valid at ~/.termux/font.ttf — skipping download"
    if command -v termux-reload-settings >/dev/null 2>&1; then
      termux-reload-settings 2>/dev/null || true
    fi
    _nerdfont_smoke_test >&2 || true
    log_info "If any glyphs above appear as boxes, force-stop Termux in Android Settings and reopen it."
    return 0
  fi

  local installed=0 attempt=1
  while [ "$attempt" -le "$TDE_NERDFONT_ATTEMPTS" ]; do
    if phase4_install_nerdfont_pkg; then
      installed=1
    elif phase4_install_nerdfont_zip_fallback; then
      installed=1
    fi

    if [ "$installed" = "1" ] && nerdfont_is_patched "$HOME/.termux/font.ttf"; then
      break
    fi
    installed=0
    if [ "$attempt" -lt "$TDE_NERDFONT_ATTEMPTS" ]; then
      log_warn "Nerd Font attempt $attempt/$TDE_NERDFONT_ATTEMPTS did not produce a valid patched ~/.termux/font.ttf — retrying"
      sleep 2
    fi
    attempt=$((attempt + 1))
  done

  if [ "$installed" = "1" ]; then
    if command -v termux-reload-settings >/dev/null 2>&1; then
      termux-reload-settings 2>/dev/null || log_warn "termux-reload-settings returned non-zero"
    fi
    export TDE_FONT_INSTALLED_THIS_RUN=1
    log_info "Nerd Font installed and verified at ~/.termux/font.ttf"
    _nerdfont_smoke_test >&2 || true
    _nerdfont_print_forcestop_banner
    return 0
  else
    log_warn "Nerd Font installation failed after $TDE_NERDFONT_ATTEMPTS attempts — run 'archfont --force' later."
    return 1
  fi
}