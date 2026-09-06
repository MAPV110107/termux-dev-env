# Phase 4 — Nerd Font. Uses the Mono variant specifically: the full/Propo
# variants break monospace alignment, which is what causes cut-off or
# missing icon glyphs. Failure here never blocks the rest of phase 4 —
# it's cosmetic, not functional.

[ -n "${TDE_NERDFONTS_LOADED:-}" ] && return 0
TDE_NERDFONTS_LOADED=1

TDE_NERDFONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
TDE_NERDFONT_TMPDIR="$HOME/.cache/termux-dev-env/nerdfont"

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

  local mono_ttf
  mono_ttf="$(find "$TDE_NERDFONT_TMPDIR" -iname '*NerdFontMono-Regular.ttf' | head -n1)"
  if [ -z "$mono_ttf" ]; then
    log_warn "Mono variant not found in the archive — skipping font install"
    return 1
  fi

  mkdir -p "$HOME/.termux"
  cp "$mono_ttf" "$HOME/.termux/font.ttf"
  log_info "Nerd Font (Mono variant) installed to ~/.termux/font.ttf"
}

phase4_nerdfonts_run() {
  log_info "=== Phase 4: Nerd Font install ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would download JetBrainsMono Nerd Font, extract the Mono variant, install to ~/.termux/font.ttf"
    return 0
  fi

  if phase4_ensure_unzip && phase4_download_nerdfont && phase4_extract_and_install_nerdfont; then
    command -v termux-reload-settings >/dev/null 2>&1 && termux-reload-settings
    log_warn "Font installed, but Android caches it at the app level — force-stop Termux from Android's app settings and reopen it for icons to render correctly"
    return 0
  else
    log_warn "Nerd Font install skipped — the editor still works, just without icons. Re-run later to retry."
    return 1
  fi
}
