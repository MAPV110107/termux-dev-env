# Architecture

`termux-dev-env` is structured into two layers under `src/`:

1. **`src/lib/` (Core Infrastructure):**
   - `core.sh`: Strict error trapping (`set -euo pipefail`), error code recording (`last_error.env`), and log rotation.
   - `state.sh`: Atomic `KEY=VALUE` persistence (`mktemp` + `mv`) and `--dry-run` state guards.
   - `lock.sh`: Process mutual exclusion using `flock` with dynamic file descriptor allocation.
   - `system.sh`: Network backoff retries (`retry_with_backoff`), non-blocking prompts, and `stdin`-piped idempotent file blocks (`idempotent_append_container`).
   - `validate.sh`: Phase 1 Termux bootstrap checks and Phase 2 hardware compatibility matrix.
   - `audit.sh`: Phase 5 post-install verification, automatic self-healing, and cache cleanup.

2. **`src/modules/` (Installation Phases):**
   - `rootfs.sh`: GPG-verified Arch Linux ARM rootfs installation, keyring initialization, `DisableSandbox`, and `ParallelDownloads = 10`.
   - `user.sh`: Batched user creation, `wheel` membership, and `visudo -c` verified passwordless sudo.
   - `launcher.sh`: Lightweight Termux host integration (`extra-keys` bar, UTF-8 environment handoff, timed container smoke check, and `archkill`).
   - `toolchain.sh`: Single-transaction installation of compilers, Neovim, and daily CLI tools (`fzf`, `bat`, `jq`, `gh`, `ripgrep`, `fd`, `lazygit`), batched Git config, and `paru-bin`.
   - `nerdfonts.sh`: Atomic inode-replacing installation of `JetBrainsMonoNerdFontMono-Regular.ttf` with magic-byte and file-size verification.
   - `shell.sh`: Container `en_US.UTF-8` locale generation and Oh My Zsh (`agnoster` + `zsh-autosuggestions` + `fzf` keybindings).
   - `neovim.sh`: LazyVim configuration tuned for Termux glyph rendering, dynamic LSP registration, and headless Treesitter compilation.
   - `maintenance.sh`: Standalone `arch*` CLI commands deployed to `$PREFIX/bin`.