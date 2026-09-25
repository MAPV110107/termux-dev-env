# Phase 4 — dev toolchain. base-devel (gcc) is installed via pacman INSIDE
# the container, never via Termux's pkg — a Termux-built compiler is a
# different binary ABI and is invisible/unusable from inside the proot,
# which is exactly the treesitter/cc bug this project exists to prevent.

[ -n "${TDE_DEV_TOOLCHAIN_LOADED:-}" ] && return 0
TDE_DEV_TOOLCHAIN_LOADED=1

phase4_sync_and_install_toolchain() {
  log_info "Syncing pacman and installing base toolchain and language runtimes"
  # Mobile networks drop mid-request often enough that a single pacman
  # attempt isn't reliable — same reasoning as the rootfs tarball
  # download (lib/network.sh), just applied to pacman itself.
  retry_with_backoff 3 15 \
    proot-distro login "$TDE_DISTRO_NAME" -- pacman -Syu --noconfirm || \
    log_fatal "pacman -Syu failed inside $TDE_DISTRO_NAME after 3 attempts — likely a network/mirror issue (mirror.archlinuxarm.org timeouts are common on mobile connections), not a package problem. See docs/TROUBLESHOOTING.md's 'mirror timeouts' section, then re-run ./core.sh to retry."
  # marksman deliberately NOT in this list: it's built by upstream Arch as
  # an x86_64-specific package (not "any" — its own package page confirms
  # this changed from "any" to "x86_64" between the 20251125-1 and
  # 20260208-1 builds), and Arch Linux ARM has no confirmed aarch64 build
  # of it. A hard `pacman -S` dependency on a package that may not exist
  # for this architecture turns "target not found: marksman" into a FATAL
  # that kills the whole toolchain phase after a long download. Mason.nvim
  # (see lazyvim.sh's ensure_installed) already installs marksman itself
  # on first Neovim launch, independent of the system package manager, so
  # nothing is lost by not hard-depending on it here.
  retry_with_backoff 3 15 \
    proot-distro login "$TDE_DISTRO_NAME" -- pacman -S --noconfirm --needed \
    base-devel git tree-sitter-cli nodejs npm python python-pip clang rust go nano wget curl || \
    log_fatal "Toolchain package install failed after 3 attempts — likely a network/mirror issue, not a package problem (these packages exist on Arch Linux ARM aarch64). See docs/TROUBLESHOOTING.md's 'mirror timeouts' section, then re-run ./core.sh to retry."
}

phase4_prompt_git_identity() {
  local username git_name git_email
  username="$(state_get ARCH_USERNAME)"
  git_name="$(_prompt "Git user.name for commits: " "")"
  git_email="$(_prompt "Git user.email for commits: " "")"

  [ -n "$git_name" ] && proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- git config --global user.name "$git_name"
  [ -n "$git_email" ] && proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- git config --global user.email "$git_email"
  # Large postBuffer avoids failed pushes on mobile connections. cache (not
  # store) keeps the credential in memory only, never written to disk —
  # costs a re-auth once a day, in exchange for never touching the disk.
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- git config --global http.postBuffer 524288000
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- git config --global credential.helper "cache --timeout=86400"
}

phase4_install_paru() {
  local username
  username="$(state_get ARCH_USERNAME)"

  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- command -v paru >/dev/null 2>&1; then
    log_info "paru already installed, skipping"
    return 0
  fi

  # paru-bin ships a prebuilt binary — paru itself is Rust, and compiling
  # it on-device would be slow and defeats the project's speed goal.
  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- command -v makepkg >/dev/null 2>&1; then
    log_warn "makepkg not found — base-devel install may have failed. Skipping paru (AUR packages won't be available; gcc/git/npm toolchain is unaffected)"
    return 1
  fi
  log_info "Installing paru-bin (prebuilt, no on-device Rust compile)"
  # Build as the user with `makepkg -s` (no -i) — never invokes sudo at
  # all — then install the resulting package as root directly via
  # `pacman -U`, which needs no authentication under proot in the first
  # place (plain `proot-distro login` without --user already IS root).
  # `makepkg -si`'s internal `sudo pacman -U` was the actual failure
  # point in the wild ("is not in the sudoers file" / password prompts
  # even with a correct NOPASSWD rule) — sudo inside proot is unreliable
  # (namespace/capability/PAM quirks), and this sidesteps needing it to
  # work at all for this one step, without touching how sudo is used
  # anywhere else (which still gets the NOPASSWD safety net from
  # create_user.sh, for actual interactive use inside Arch).
  # None of the core toolchain (gcc, git, npm, LazyVim/Mason) depends on
  # paru existing, so losing it shouldn't cost the whole phase.
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- bash -c '
    set -e
    rm -rf /tmp/paru-bin
    git clone --depth 1 https://aur.archlinux.org/paru-bin.git /tmp/paru-bin
    cd /tmp/paru-bin
    makepkg -s --noconfirm
  ' < /dev/null || {
    log_warn "paru build failed — AUR packages won't be available, but the rest of the toolchain is unaffected. Retry later with: proot-distro login $TDE_DISTRO_NAME --user $username -- sh -c 'cd /tmp/paru-bin && makepkg -s --noconfirm'"
    return 1
  }
  proot-distro login "$TDE_DISTRO_NAME" -- bash -c '
    set -e
    shopt -s nullglob
    pkgs=(/tmp/paru-bin/*.pkg.tar.*)
    [ "${#pkgs[@]}" -gt 0 ]
    pacman -U --noconfirm "${pkgs[@]}"
  ' < /dev/null || {
    log_warn "paru package built but install failed (pacman -U) — retry later with: proot-distro login $TDE_DISTRO_NAME -- sh -c 'pacman -U --noconfirm /tmp/paru-bin/*.pkg.tar.*'"
    return 1
  }
}

phase4_write_paru_conf() {
  local username conf_dir
  username="$(state_get ARCH_USERNAME)"
  conf_dir="$(container_home "$username")/.config/paru"
  mkdir -p "$conf_dir"
  cat > "$conf_dir/paru.conf" << 'EOF'
[options]
BottomUp
SkipReview
NoUpgradeMenu
CombinedUpgrade
EOF
}

phase4_dev_toolchain_run() {
  log_info "=== Phase 4: dev toolchain (compiler, git, paru) ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would pacman -Syu, install base-devel/git/tree-sitter-cli/nodejs/npm, prompt for git identity, install paru-bin (non-blocking), write paru.conf"
    return 0
  fi

  phase4_sync_and_install_toolchain
  phase4_prompt_git_identity
  # Non-blocking: see phase4_install_paru's own comment. A failed AUR
  # helper install must not take the whole toolchain phase down with it.
  phase4_install_paru || log_warn "Continuing without paru — see the warning above for how to retry it later"
  phase4_write_paru_conf
  log_info "Dev toolchain installed"
}

# Post-condition, checked by core.sh before marking PHASE4_TOOLCHAIN.
# Only requires what the rest of the pipeline actually depends on — gcc
# (compiling treesitter parsers) and git. paru is genuinely optional (see
# phase4_install_paru): requiring it here would fail this post-condition,
# and therefore the whole toolchain phase, over something non-essential.
phase4_toolchain_ok() {
  local username
  username="$(state_get ARCH_USERNAME)"
  [ -n "$username" ] || return 1
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    sh -c 'command -v gcc >/dev/null && command -v git >/dev/null' 2>/dev/null
}
