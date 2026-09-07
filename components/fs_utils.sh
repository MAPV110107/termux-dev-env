# Phase 4 — filesystem tools + SSH. openssh is always installed (it's the
# ssh client too, needed for git-over-SSH); the server is opt-in since
# there's no init system in proot to auto-start it — the user runs sshd
# by hand the moment they actually want remote access.

[ -n "${TDE_FS_UTILS_LOADED:-}" ] && return 0
TDE_FS_UTILS_LOADED=1

phase4_install_fs_tools() {
  log_info "Installing filesystem utilities (e2fsprogs, dosfstools)"
  proot-distro login "$TDE_DISTRO_NAME" -- pacman -S --noconfirm --needed e2fsprogs dosfstools openssh || \
    log_warn "Filesystem utilities / openssh install failed"
}

phase4_prompt_ssh_server() {
  local answer
  answer="$(_prompt "Generate SSH host keys for remote access (sshd)? [y/N]: " "N")"
  if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    proot-distro login "$TDE_DISTRO_NAME" -- ssh-keygen -A || log_warn "Could not generate SSH host keys"
    log_info "SSH host keys generated — start the server manually with 'sudo /usr/bin/sshd' when you want remote access (no init system to auto-start it)"
  else
    log_info "SSH server skipped — the ssh client is still installed for git-over-SSH"
  fi
}

phase4_fs_utils_run() {
  log_info "=== Phase 4: filesystem utilities and optional SSH ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would install e2fsprogs/dosfstools/openssh, prompt to generate SSH host keys"
    return 0
  fi

  phase4_install_fs_tools
  phase4_prompt_ssh_server
  log_info "Filesystem utilities step complete"
}
