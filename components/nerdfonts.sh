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
  proot-distro login "$TDE_DISTRO_NAME" -- cat "$rel_path" > "$HOME/.termux/font.ttf" 2>/dev/null || return 1
  [ -s "$HOME/.termux/font.ttf" ]
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
  cp "$mono_ttf" "$HOME/.termux/font.ttf"
  log_info "Nerd Font installed to ~/.termux/font.ttf (fallback zip download)"
}

phase4_nerdfonts_run() {
  log_info "=== Phase 4: Nerd Font install ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would install $TDE_NERDFONT_PKG via pacman (fallback: download+extract JetBrainsMono Nerd Font zip), install to ~/.termux/font.ttf"
    return 0
  fi

  local installed=0
  if phase4_install_nerdfont_pkg; then
    installed=1
  elif phase4_ensure_unzip && phase4_download_nerdfont && phase4_extract_and_install_nerdfont; then
    installed=1
  fi

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
    return 0
  else
    log_warn "Nerd Font install skipped — the editor still works, just without icons. Re-run later to retry."
    return 1
  fi
}
