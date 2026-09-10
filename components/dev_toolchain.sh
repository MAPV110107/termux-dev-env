# Phase 4 — dev toolchain. base-devel (gcc) is installed via pacman INSIDE
# the container, never via Termux's pkg — a Termux-built compiler is a
# different binary ABI and is invisible/unusable from inside the proot,
# which is exactly the treesitter/cc bug this project exists to prevent.

[ -n "${TDE_DEV_TOOLCHAIN_LOADED:-}" ] && return 0
TDE_DEV_TOOLCHAIN_LOADED=1

phase4_sync_and_install_toolchain() {
  log_info "Syncing pacman and installing base toolchain"
  proot-distro login "$TDE_DISTRO_NAME" -- pacman -Syu --noconfirm || \
    log_fatal "pacman -Syu failed inside $TDE_DISTRO_NAME"
  proot-distro login "$TDE_DISTRO_NAME" -- pacman -S --noconfirm --needed \
    base-devel git tree-sitter-cli nodejs npm python-pip nano wget curl || \
    log_fatal "Toolchain package install failed"
}

phase4_prompt_git_identity() {
  local username git_name git_email
  username="$(state_get ARCH_USERNAME)"
  git_name="$(_prompt "Git user.name for commits: " "")"
  git_email="$(_prompt "Git user.email for commits: " "")"

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- git config --global user.name "$git_name"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- git config --global user.email "$git_email"
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
  log_info "Installing paru-bin (prebuilt, no on-device Rust compile)"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- bash -c '
    set -e
    rm -rf /tmp/paru-bin
    git clone --depth 1 https://aur.archlinux.org/paru-bin.git /tmp/paru-bin
    cd /tmp/paru-bin
    makepkg -si --noconfirm
  ' < /dev/null || log_fatal "paru install failed"
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
    log_info "[dry-run] would pacman -Syu, install base-devel/git/tree-sitter-cli/nodejs/npm, prompt for git identity, install paru-bin, write paru.conf"
    return 0
  fi

  phase4_sync_and_install_toolchain
  phase4_prompt_git_identity
  phase4_install_paru
  phase4_write_paru_conf
  log_info "Dev toolchain installed"
}

# Post-condition, checked by core.sh before marking PHASE4_TOOLCHAIN.
phase4_toolchain_ok() {
  local username
  username="$(state_get ARCH_USERNAME)"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    sh -c 'command -v gcc >/dev/null && command -v git >/dev/null && command -v paru >/dev/null' 2>/dev/null
}
