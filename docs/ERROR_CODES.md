# Error codes

Every deliberate `FATAL` in the installer carries a stable code, printed as
`[FATAL] [E<code>] <message>` and also saved to
`~/.config/termux-dev-env/last_error.env` (shown by `archdiag`). Quote the
code when reporting a problem — it identifies the failing step without
needing the full log.

The first digit is the phase: **1xx** CLI / bootstrap, **3xx** Phase 3
(rootfs, user, launcher), **4xx** Phase 4 (toolchain, shell, LazyVim),
**6xx** Phase 6 (maintenance commands).

| Code | Meaning | Where to look |
|------|---------|---------------|
| E100 | Invalid `--reinstall` value | Use `--reinstall=1` … `6` |
| E301 | Rootfs post-condition failed | TROUBLESHOOTING → "Phase 3 says installed and then FATAL" |
| E302 | User creation post-condition failed | TROUBLESHOOTING → "sudo asks for a password" |
| E303 | Launcher setup post-condition failed | `TDE_SKIP_LAUNCHER=1`, re-run `./core.sh` |
| E310 | Could not install `gnupg` (needed to verify the rootfs) | Network; re-run |
| E311 | Could not download the Arch Linux ARM signing key | Network; re-run |
| E312 | Could not import the signing key | Re-run; check `gpg` |
| E313 | Pinned rootfs override (`TDE_ROOTFS_URL_OVERRIDE`) failed | Check the URL/signature |
| E314 | Rootfs download/verify failed on every mirror | Network; TROUBLESHOOTING → "mirror timeouts" |
| E315 | `proot-distro install` failed | Free space; `proot-distro remove archarm`, re-run |
| E316 | Rootfs installed but login failed | `proot-distro remove archarm`, re-run |
| E317 | `pacman-key --init/--populate` failed | Re-run; network |
| E318 | `DisableSandbox` could not be written to `pacman.conf` | Manual `sed` in the message |
| E320 | Could not install `sudo`/`zsh` in the container | Network; re-run |
| E321 | `useradd` failed | Username taken/invalid |
| E322 | `visudo` rejected the sudoers rule | Message has the manual fix |
| E401 | Toolchain post-condition failed | `archhealth`; TROUBLESHOOTING |
| E402 | Shell setup post-condition failed | TROUBLESHOOTING → ".zshrc" sections |
| E403 | LazyVim post-condition failed | TROUBLESHOOTING → "TSInstallSync" |
| E410 | `pacman -Syu` failed after retries | TROUBLESHOOTING → "mirror timeouts" |
| E411 | Toolchain package install failed after retries | TROUBLESHOOTING → "mirror timeouts" |
| E420 | Could not install `zsh`/`tmux` (Termux side) | `pkg update`, re-run |
| E421 | oh-my-zsh install failed | Network; re-run |
| E422 | `.zshrc` could not be created even as a fallback | `--reinstall=4` |
| E430 | Could not install neovim/ripgrep/fd/lazygit | Network; re-run |
| E431 | Could not configure the npm global prefix | Re-run |
| E432 | Could not clone the LazyVim starter | Network; re-run |
| E433 | Could not prepare the nvim plugins directory | Re-run |
| E434 | `lazy.nvim` plugin sync failed | Network; re-run |
| E601 | Maintenance commands post-condition failed | `./core.sh --reinstall=6` |

Warnings (`[WARN]`) have no code: they are non-blocking and the phase
continues (fonts, telecom, `paru`, `fastfetch` cosmetics).
