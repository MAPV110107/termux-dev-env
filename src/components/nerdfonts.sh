# Phase 4 — Nerd Font. Uses the Mono variant specifically: the full/Propo
# variants break monospace alignment, which is what causes cut-off or
# missing icon glyphs. Failure here never blocks the rest of phase 4 —
# it's cosmetic, not functional.

[ -n "${TDE_NERDFONTS_LOADED:-}" ] && return 0
TDE_NERDFONTS_LOADED=1

# Primary: ttf-jetbrains-mono-nerd, Arch's own official package (extra
# repo, architecture "any" — confirmed synced to Arch Linux ARM, same as
# the plain, non-Nerd ttf-jetbrains-mono). ~10.5 MB versus downloading
# nerd-fonts' own release zip, which bundles every style and width
# variant of the font together for the one file this project actually
# installs (~127 MB) — that size alone made the download a real
# contributor to Termux ANRs on a phone alongside paru/Mason/treesitter
# all running at once. Falls back to the old zip download only if the
# package is ever unavailable.
TDE_NERDFONT_PKG="ttf-jetbrains-mono-nerd"
TDE_NERDFONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
TDE_NERDFONT_TMPDIR="$HOME/.cache/termux-dev-env/nerdfont"
# How many times phase4_nerdfonts_run retries the whole install (pacman
# path, then zip fallback) before giving up for this run. The font is
# cosmetic in the sense that nothing crashes without it, but "every icon
# is a box" is the single most visible defect in the finished
# environment, so it is worth more than one attempt — unlike the old
# behaviour, which tried once and moved on.
TDE_NERDFONT_ATTEMPTS="${TDE_NERDFONT_ATTEMPTS:-3}"

# A real TrueType/OpenType file, not just "a file that exists and is
# big". Checks both the size and the magic bytes, because the actual
# failure seen in the wild is a *truncated or empty* font.ttf (an
# interrupted `proot-distro login -- cat > font.ttf`, a disk-full
# write): Termux silently falls back to its built-in font and every
# icon renders as a box, with no error anywhere to explain it.
#
# Valid first four bytes: 00 01 00 00 (TrueType), "OTTO" (CFF/OpenType),
# "true"/"ttcf" (Apple variants). 100KB is well under any real Nerd Font
# (single-digit MB) and well over a truncated file.
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

# Android caches the terminal font at the app level: termux-reload-settings
# re-reads font.ttf, but a Termux process that has already rendered with
# the old font sometimes keeps it until the app itself is restarted.
# That is not a failure of the install and there is nothing the script
# can do about it from inside — so say it plainly, once, instead of
# leaving the person thinking the font install did not work.
_nerdfont_print_forcestop_hint() {
  log_info "If icons still show as empty boxes: force-stop Termux (Android Settings > Apps > Termux > Force stop) and open it again — Android caches the terminal font per app, and a reload cannot always evict it."
}

# The same advice as above, but impossible to miss in the install
# scrollback: a separated block on stderr, in colour on a terminal. This
# is the single most common "it looks broken" report, and a one-line
# log_info between dozens of install lines does not get read. Always
# returns 0 so a caller under set -e is never aborted by a notice.
_nerdfont_print_forcestop_banner() {
  local b="" r="" line="============================================================"
  if [ -t 2 ]; then b=$'\033[1;33m'; r=$'\033[0m'; fi
  {
    printf '\n%s%s\n' "$b" "$line"
    printf '[IMPORTANT] Nerd Font installed.\n'
    printf 'If icons still show as boxes:\n'
    printf '  1. Android Settings > Apps > Termux > Force stop\n'
    printf '  2. Open Termux again\n'
    printf 'Or from a computer: adb shell am force-stop com.termux\n'
    printf '%s%s\n\n' "$line" "$r"
  } >&2
  return 0
}
phase4_install_nerdfont_pkg() {
  proot-distro login "$TDE_DISTRO_NAME" -- pacman -S --noconfirm --needed "$TDE_NERDFONT_PKG" 2>>"$TDE_LOG_FILE" || return 1

  # Read the real installed path from the package itself (pacman -Ql)
  # rather than assuming Arch's font-packaging layout matches
  # nerd-fonts' own upstream zip structure — they don't have to agree.
  local rel_path
  rel_path="$(proot-distro login "$TDE_DISTRO_NAME" -- pacman -Ql "$TDE_NERDFONT_PKG" 2>/dev/null \
    | awk '{print $2}' | grep -iE 'NerdFontMono-Regular\.ttf$' | head -n1)"
  if [ -z "$rel_path" ]; then
    rel_path="$(proot-distro login "$TDE_DISTRO_NAME" -- pacman -Ql "$TDE_NERDFONT_PKG" 2>/dev/null \
      | awk '{print $2}' | grep -iE '\.ttf$' | grep -iE 'regular' | head -n1)"
  fi
  [ -n "$rel_path" ] || return 1

  mkdir -p "$HOME/.termux"
  # rel_path is already absolute (pacman -Ql's own output) — no ~, so no
  # risk of the host-side tilde-expansion bug documented in
  # docs/TROUBLESHOOTING.md. The '>' redirect is deliberately host-side
  # here: ~/.termux/font.ttf is a real Termux path, not a container one.
  # Written to a temp file and moved into place only once it validates:
  # a half-written font.ttf is worse than no font.ttf, because it still
  # passes a bare -f/-s check while rendering nothing.
  local tmp_font="$HOME/.termux/font.ttf.tmp"
  if ! proot-distro login "$TDE_DISTRO_NAME" -- cat "$rel_path" > "$tmp_font" 2>/dev/null; then
    rm -f "$tmp_font"
    return 1
  fi
  if ! nerdfont_file_ok "$tmp_font"; then
    log_warn "The font extracted from $TDE_NERDFONT_PKG is truncated or not a TTF — discarding it"
    rm -f "$tmp_font"
    return 1
  fi
  # Delete first, then move: Android's font renderer mmaps font.ttf, and
  # replacing the file in place can leave it looking at the old inode
  # until the renderer is reinitialised. A fresh inode cannot be confused
  # with the old mapping.
  rm -f "$HOME/.termux/font.ttf"
  mv "$tmp_font" "$HOME/.termux/font.ttf"
}

phase4_ensure_unzip() {
  command -v unzip >/dev/null 2>&1 && return 0
  log_info "Installing unzip (needed to extract the Nerd Font archive)"
  retry_with_backoff 3 5 pkg install -y unzip || {
    log_warn "Could not install unzip — skipping Nerd Font install"
    return 1
  }
}

phase4_download_nerdfont() {
  mkdir -p "$TDE_NERDFONT_TMPDIR"
  retry_with_backoff 3 5 curl -fL -o "$TDE_NERDFONT_TMPDIR/JetBrainsMono.zip" "$TDE_NERDFONT_URL" || {
    log_warn "Could not download Nerd Font — icons will show as blank boxes until installed manually"
    return 1
  }
}

phase4_extract_and_install_nerdfont() {
  unzip -o -q "$TDE_NERDFONT_TMPDIR/JetBrainsMono.zip" -d "$TDE_NERDFONT_TMPDIR" || {
    log_warn "Could not extract the Nerd Font archive"
    return 1
  }

  # In priority order: the Mono variant specifically (monospace-safe icon
  # width), then any NerdFont-patched regular, then a last-resort loose
  # match on the family name — broadened from a single fixed pattern so
  # a nerd-fonts release renaming its assets doesn't silently skip the
  # install entirely.
  local mono_ttf pattern
  mono_ttf=""
  for pattern in '*NerdFontMono-Regular.ttf' '*NerdFont-Regular.ttf' '*JetBrainsMono*Regular*.ttf'; do
    mono_ttf="$(find "$TDE_NERDFONT_TMPDIR" -iname "$pattern" | head -n1)"
    [ -n "$mono_ttf" ] && break
  done
  if [ -z "$mono_ttf" ]; then
    log_warn "No matching font file found in the archive — skipping font install"
    return 1
  fi

  mkdir -p "$HOME/.termux"
  if ! nerdfont_file_ok "$mono_ttf"; then
    log_warn "The font extracted from the zip ($mono_ttf) is truncated or not a TTF — skipping"
    return 1
  fi
  # Same reason as the pacman path: new inode, never an in-place overwrite.
  rm -f "$HOME/.termux/font.ttf"
  cp "$mono_ttf" "$HOME/.termux/font.ttf"
  log_info "Nerd Font installed to ~/.termux/font.ttf (fallback zip download)"
}

phase4_nerdfonts_run() {
  log_info "=== Phase 4: Nerd Font install ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would install $TDE_NERDFONT_PKG via pacman (fallback: download+extract JetBrainsMono Nerd Font zip), install to ~/.termux/font.ttf"
    return 0
  fi

  # Already good from an earlier run? Don't re-download several hundred
  # MB of package/zip to replace a font that already renders.
  if nerdfont_file_ok; then
    log_info "A valid Nerd Font is already installed at ~/.termux/font.ttf — skipping"
    return 0
  fi

  local installed=0 attempt=1
  while [ "$attempt" -le "$TDE_NERDFONT_ATTEMPTS" ]; do
    if phase4_install_nerdfont_pkg; then
      installed=1
    elif phase4_ensure_unzip && phase4_download_nerdfont && phase4_extract_and_install_nerdfont; then
      installed=1
    fi
    # The install path can report success and still leave an unusable
    # file behind, so the loop condition is the *file*, not the exit
    # status of whatever wrote it.
    if [ "$installed" = "1" ] && nerdfont_file_ok; then
      break
    fi
    installed=0
    if [ "$attempt" -lt "$TDE_NERDFONT_ATTEMPTS" ]; then
      log_warn "Nerd Font attempt $attempt/$TDE_NERDFONT_ATTEMPTS did not produce a valid ~/.termux/font.ttf — retrying"
      sleep 3
    fi
    attempt=$((attempt + 1))
  done

  if [ "$installed" = "1" ]; then
    # termux-reload-settings (part of termux-tools) broadcasts
    # com.termux.app.reload_style, which Termux's own app listens for —
    # it applies font.ttf/colors.properties changes immediately, no
    # restart needed. It doesn't require the separate Termux:API app.
    if command -v termux-reload-settings >/dev/null 2>&1; then
      termux-reload-settings
      log_info "Nerd Font installed and applied — icons should render right away"
    else
      log_warn "Nerd Font installed, but 'termux-reload-settings' wasn't found — restart Termux for icons to render"
    fi
    _nerdfont_print_forcestop_banner
    return 0
  else
    log_warn "Nerd Font install failed after $TDE_NERDFONT_ATTEMPTS attempts — the editor still works, just with boxes instead of icons. Phase 5 self-heal retries it, or run 'archfont --force' later (then force-stop Termux from Android Settings and reopen it)."
    return 1
  fi
}
