# Error Codes

Every fatal error in `termux-dev-env` logs a stable `[E<code>]` identifier and saves machine-readable details to `~/.config/termux-dev-env/last_error.env` (inspected via `archdiag`).

| Code | Phase / Module | Meaning | Resolution |
|:--|:--|:--|:--|
| `E100` | CLI (`orchestrator.sh`) | Invalid `--reinstall` phase number | Use `--reinstall=1` through `6` |
| `E101` | Phase 1 (`validate.sh`) | Not running inside Termux (`$PREFIX` invalid) | Run inside Termux (F-Droid / GitHub build) |
| `E102` | Phase 1 (`validate.sh`) | Unsupported CPU architecture | `aarch64` (64-bit ARM) is required |
| `E103` | Phase 1 (`validate.sh`) | Insufficient free disk space | Free at least 3 GB (`3072 MB`) in internal storage |
| `E104` | Phase 1 (`validate.sh`) | Termux `pkg update`/`upgrade` failed | Check network connection and Termux mirrors |
| `E105` | Phase 1 (`validate.sh`) | Termux base package installation failed | Run `pkg update -y` and retry `./launcher.sh` |
| `E106` | Phase 1 (`validate.sh`) | `proot` version is older than v5 | Run `pkg upgrade proot` |
| `E201` | Phase 2 (`validate.sh`) | `proot` execution failed (`ptrace` blocked) | Kernel blocks `ptrace`; cannot run `proot` on this device |
| `E301` | Phase 3 (`orchestrator.sh`) | Rootfs post-condition check failed | Re-run `./launcher.sh` to repair keyring/pacman config |
| `E302` | Phase 3 (`orchestrator.sh`) | User creation post-condition check failed | Re-run `./launcher.sh --reinstall=3` |
| `E303` | Phase 3 (`orchestrator.sh`) | Launcher setup post-condition check failed | Run `archreapply` or `./launcher.sh --reinstall=3` |
| `E310` | Phase 3 (`rootfs.sh`) | Could not install `gnupg` in Termux | Check network connectivity and retry |
| `E311` | Phase 3 (`rootfs.sh`) | Could not download Arch Linux ARM signing key | Check internet access and retry |
| `E312` | Phase 3 (`rootfs.sh`) | Could not import Arch Linux ARM signing key | Verify `gpg` works in Termux and retry |
| `E313` | Phase 3 (`rootfs.sh`) | Custom `TDE_ROOTFS_URL_OVERRIDE` failed | Verify custom URL and `.sig` file |
| `E314` | Phase 3 (`rootfs.sh`) | Rootfs download/verification failed on all mirrors | Check network connection and retry |
| `E315` | Phase 3 (`rootfs.sh`) | `proot-distro install` failed | Check free disk space; `proot-distro remove archarm` |
| `E316` | Phase 3 (`rootfs.sh`) | Container installed but smoke login failed | Run `archreset --soft` and retry |
| `E317` | Phase 3 (`rootfs.sh`) | `pacman-key --init` or `--populate` failed | Re-run `./launcher.sh` |
| `E318` | Phase 3 (`rootfs.sh`) | `DisableSandbox` could not be added to `pacman.conf` | Check `/etc/pacman.conf` inside the container |
| `E320` | Phase 3 (`user.sh`) | Could not install `sudo` and `zsh` in container | Check network connection and re-run `./launcher.sh` |
| `E321` | Phase 3 (`user.sh`) | `useradd` failed inside container | Choose a valid lowercase username |
| `E322` | Phase 3 (`user.sh`) | `visudo -c` rejected the sudoers configuration | Re-run `./launcher.sh --reinstall=3` |
| `E401` | Phase 4 (`orchestrator.sh`) | Toolchain post-condition check failed | Run `archhealth` or `./launcher.sh --reinstall=4` |
| `E402` | Phase 4 (`orchestrator.sh`) | Shell post-condition check failed | Re-run `./launcher.sh --reinstall=4` |
| `E403` | Phase 4 (`orchestrator.sh`) | LazyVim post-condition check failed | Re-run `./launcher.sh --reinstall=4` |
| `E410` | Phase 4 (`toolchain.sh`) | `pacman -Syu` failed after 3 attempts | Switch network or retry `./launcher.sh` |
| `E411` | Phase 4 (`toolchain.sh`) | Toolchain & CLI package install failed | Re-run `./launcher.sh` (pacman resumes partial downloads) |
| `E421` | Phase 4 (`shell.sh`) | Oh My Zsh installation failed in container | Check network connectivity and retry |
| `E422` | Phase 4 (`shell.sh`) | Could not configure `.zshrc` inside container | Re-run `./launcher.sh --reinstall=4` |
| `E431` | Phase 4 (`neovim.sh`) | Could not configure npm global prefix | Re-run `./launcher.sh --reinstall=4` |
| `E432` | Phase 4 (`neovim.sh`) | Could not clone LazyVim starter repository | Check GitHub connectivity and retry |
| `E433` | Phase 4 (`neovim.sh`) | Could not prepare `~/.config/nvim/lua/plugins` | Check container home permissions |
| `E434` | Phase 4 (`neovim.sh`) | Headless `lazy.nvim` plugin sync failed | Re-run `./launcher.sh --reinstall=4` |
| `E601` | Phase 6 (`orchestrator.sh`) | Maintenance commands failed verification | Run `./launcher.sh --reinstall=6` |