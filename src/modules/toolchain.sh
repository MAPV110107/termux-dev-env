# Phase 4, step 1 — Unified development toolchain, daily CLI utilities,
# Git configuration, optional SSH host keys, and fast paru-bin AUR helper.

[ -n "${TDE_MODULE_TOOLCHAIN_LOADED:-}" ] && return 0
TDE_MODULE_TOOLCHAIN_LOADED=1

phase4_sync_and_install_toolchain() {
  log_info "Syncing pacman and installing unified development toolchain & daily CLI utilities"

  local extra_pkgs=""
  [ "${TDE_WITH_RUST:-0}" = "1" ]  && extra_pkgs="$extra_pkgs rust"
  [ "${TDE_WITH_GO:-0}" = "1" ]    && extra_pkgs="$extra_pkgs go"
  [ "${TDE_WITH_CLANG:-0}" = "1" ] && extra_pkgs="$extra_pkgs clang"

  # Single consolidated pacman transaction for sync, update, toolchain, and daily CLI tools
  # shellcheck disable=SC2086
  retry_with_backoff 3 15 \
    proot-distro login "$TDE_DISTRO_NAME" -- pacman -Syu --noconfirm --needed \
    base-devel git github-cli neovim tree-sitter-cli \
    ripgrep fd fzf bat jq lazygit \
    nodejs npm python python-pip \
    openssh unzip zip tar wget curl nano fastfetch $extra_pkgs || \
    log_fatal_code 411 "Toolchain and CLI package installation failed after 3 attempts."
}

phase4_configure_git() {
  local username git_name git_email
  username="$(state_get ARCH_USERNAME)"
  git_name="$(_prompt "Git user.name for commits (leave blank to skip): " "")"
  git_email="$(_prompt "Git user.email for commits (leave blank to skip): " "")"

  # Batched git configuration in a single container login
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" \
    --env TDE_GIT_NAME="$git_name" \
    --env TDE_GIT_EMAIL="$git_email" -- sh -c '
    [ -n "$TDE_GIT_NAME" ] && git config --global user.name "$TDE_GIT_NAME"
    [ -n "$TDE_GIT_EMAIL" ] && git config --global user.email "$TDE_GIT_EMAIL"
    git config --global init.defaultBranch main
    git config --global core.editor nvim
    git config --global pull.rebase false
    git config --global color.ui auto
    git config --global http.postBuffer 524288000
    git config --global credential.helper "cache --timeout=86400"
  ' || log_warn "Could not apply all git global defaults"
}

phase4_install_paru() {
  local username="$1" from_source="${2:-0}"
  [ -n "$username" ] || username="$(state_get ARCH_USERNAME)"

  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- paru --version >/dev/null 2>&1; then
    log_info "paru already installed and working, skipping"
    return 0
  fi

  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- command -v makepkg >/dev/null 2>&1; then
    log_warn "makepkg not found — skipping paru"
    return 1
  fi

  log_info "Installing paru-bin (prebuilt binary, fast)"
  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- bash -c '
    set -e
    rm -rf /tmp/paru-bin
    git clone --depth 1 https://aur.archlinux.org/paru-bin.git /tmp/paru-bin
    cd /tmp/paru-bin
    makepkg -s --noconfirm
  ' < /dev/null && proot-distro login "$TDE_DISTRO_NAME" -- bash -c '
    set -e
    shopt -s nullglob
    pkgs=(/tmp/paru-bin/*.pkg.tar.*)
    [ "${#pkgs[@]}" -gt 0 ]
    pacman -U --noconfirm "${pkgs[@]}"
  ' < /dev/null; then
    if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- paru --version >/dev/null 2>&1; then
      log_info "paru-bin installed and verified"
      return 0
    fi
  fi

  if [ "$from_source" != "1" ]; then
    log_warn "paru-bin is unavailable or mismatched with current libalpm. Skipping slow source compilation during main setup — run 'archparu --from-source' anytime if you need AUR packages."
    return 1
  fi

  log_info "Building paru from source (MAKEFLAGS=-j1 CARGO_BUILD_JOBS=1 to prevent Android OOM)..."
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- bash -c '
    set -e
    export MAKEFLAGS="-j1" CARGO_BUILD_JOBS=1
    rm -rf /tmp/paru
    git clone --depth 1 https://aur.archlinux.org/paru.git /tmp/paru
    cd /tmp/paru
    makepkg -s --noconfirm
  ' < /dev/null && proot-distro login "$TDE_DISTRO_NAME" -- bash -c '
    set -e
    shopt -s nullglob
    pkgs=(/tmp/paru/*.pkg.tar.*)
    [ "${#pkgs[@]}" -gt 0 ]
    pacman -U --noconfirm "${pkgs[@]}"
  ' < /dev/null
}

phase4_write_paru_conf() {
  local username
  username="$(state_get ARCH_USERNAME)"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- sh -c '
    mkdir -p ~/.config/paru
    cat > ~/.config/paru/paru.conf << "EOF"
[options]
BottomUp
SkipReview
NoUpgradeMenu
CombinedUpgrade
EOF
  ' || log_warn "Could not write paru.conf"
}

phase4_prompt_ssh_server() {
  local answer
  answer="$(_prompt "Generate SSH host keys for remote access (sshd)? [y/N]: " "N")"
  if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    proot-distro login "$TDE_DISTRO_NAME" -- ssh-keygen -A || log_warn "Could not generate SSH host keys"
    log_info "SSH host keys generated — start manually with 'sudo /usr/bin/sshd' when needed"
  fi
}

phase4_dev_toolchain_run() {
  log_info "=== Phase 4, step 1: dev toolchain & daily CLI utilities ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would pacman -Syu, install base-devel/git/gh/neovim/ripgrep/fd/fzf/bat/jq/lazygit/nodejs/npm/python/openssh/fastfetch, configure git, install paru-bin, and prompt for SSH keys"
    return 0
  fi

  local username
  username="$(state_get ARCH_USERNAME)"

  phase4_sync_and_install_toolchain
  phase4_configure_git
  phase4_install_paru "$username" "${TDE_PARU_FROM_SOURCE:-0}" || true
  phase4_write_paru_conf
  phase4_prompt_ssh_server
  log_info "Dev toolchain and daily CLI utilities installed"
}

phase4_toolchain_ok() {
  local username
  username="$(state_get ARCH_USERNAME)"
  [ -n "$username" ] || return 1
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    sh -c 'command -v gcc >/dev/null && command -v git >/dev/null && command -v fzf >/dev/null && command -v rg >/dev/null' 2>/dev/null
}