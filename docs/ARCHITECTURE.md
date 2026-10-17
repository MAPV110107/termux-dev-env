# Architecture — termux-dev-env v1.5.0

`termux-dev-env` is an idempotent, self-healing provisioning architecture that turns Android (`aarch64`) into a complete Arch Linux ARM development workstation running under `proot-distro`.

```text
               ┌────────────────────────────────────────────────────────┐
               │                      launcher.sh                       │
               └──────────────────────────┬─────────────────────────────┘
                                          │
                                          ▼
               ┌────────────────────────────────────────────────────────┐
               │             Phase 1: Bootstrap Validation              │
               │   $PREFIX check, storage, memory, proot, host ADB,     │
               │             Shizuku battery/process limits             │
               └──────────────────────────┬─────────────────────────────┘
                                          │
                                          ▼
               ┌────────────────────────────────────────────────────────┐
               │            Phase 2: Environment Diagnostics            │
               │   Hardware matrix: RAM, zram, CPU cores, ptrace check  │
               └──────────────────────────┬─────────────────────────────┘
                                          │
                                          ▼
               ┌────────────────────────────────────────────────────────┐
               │           Phase 3: Core Container & User               │
               │   GPG Arch ARM rootfs, DisableSandbox, user creation,  │
               │    wheel sudo, Termux extra-keys, auto-login launcher  │
               └──────────────────────────┬─────────────────────────────┘
                                          │
                                          ▼
               ┌────────────────────────────────────────────────────────┐
               │       Phase 4: Toolchain, Fonts, Shell & LazyVim       │
               │  Consolidated pacman (compilers, git, gh, tmux, adb),  │
               │  npm global stack (serve, pm2, pnpm), paru-bin, font,  │
               │        Oh My Zsh agnoster, LazyVim + Mason LSPs        │
               └──────────────────────────┬─────────────────────────────┘
                                          │
                                          ▼
               ┌────────────────────────────────────────────────────────┐
               │            Phase 5: Audit, Self-Heal & Report          │
               │   Post-condition verification, auto-recovery for font  │
               │      and npm tools, cache cleanup, execution report    │
               └──────────────────────────┬─────────────────────────────┘
                                          │
                                          ▼
               ┌────────────────────────────────────────────────────────┐
               │             Phase 6: Global Maintenance CLI            │
               │   Standalone arch* tools deployed to $PREFIX/bin       │
               │ (archhealth, archdiag, archupdate, archreset, etc.)    │
               └────────────────────────────────────────────────────────┘
```

---

## 1. Core Infrastructure (`src/lib/`)

The infrastructure layer provides common facilities and safety primitives used across all installation modules:

- **`core.sh`**:
  - Enforces strict shell execution (`set -euo pipefail`).
  - Implements tagged fatal exit logging with stable `[Exxx]` codes.
  - Automatically records error context (`last_error.env`) for diagnostic retrieval via `archdiag`.
  - Manages timestamped log rotation (`install_*.log`).
- **`state.sh`**:
  - Implements atomic `KEY=VALUE` persistence using `mktemp` and atomic `mv`.
  - Maintains installation phase flags (`PHASE1_DONE`, `PHASE4_TOOLCHAIN`, etc.) to support safe resumability.
  - Honours `--dry-run` guards to prevent state modification during simulations.
  - Provides prefix-based state invalidation for `--reinstall=<phase>`.
- **`lock.sh`**:
  - Mutual exclusion using `flock` with dynamic file descriptor allocation (`TDE_LOCK_FD >= 10`).
  - Prevents concurrent installer executions and releases locks on EXIT or trap signals.
- **`system.sh`**:
  - Exponential backoff retry loop (`retry_with_backoff`) handling transient network failures.
  - Terminal-aware interactive prompts with non-interactive default fallbacks.
  - Idempotent container file injection (`idempotent_append_container`) with marker tags.
- **`validate.sh`**:
  - Phase 1: Environment sanity checks (Termux `$PREFIX`, `aarch64` architecture, disk space).
  - Optional Shizuku (`rish`) integration to automatically grant background battery exemptions and disable Android phantom process killing (`max_phantom_processes 2147483647`).
  - Phase 2: Hardware compatibility profiling (Total RAM, Available RAM, Storage, CPU cores, Android API level, kernel `ptrace` support).
- **`audit.sh`**:
  - Phase 5: Functional verification of critical runtime components (Rootfs, User, Launcher, Dev toolchain, Shell, LazyVim) and optional components (Nerd Font, npm global developer stack).
  - Self-healing engine that automatically repairs recoverable faults (re-downloading corrupted fonts, re-running npm global provisioning).
  - Cache cleanup of verified temporary assets (tarballs, GPG signatures, build trees).

---

## 2. Modular Installation Phases (`src/modules/`)

The workstation provisioning logic is decomposed into single-responsibility modules:

### `rootfs.sh` (Phase 3a)
- Fetches the official Arch Linux ARM rootfs tarball over HTTPS (with HTTP fallback).
- Verifies integrity against upstream GPG signatures and initializes the pacman keyring (`pacman-key --init && pacman-key --populate archlinuxarm`).
- Injects `DisableSandbox` into `pacman.conf` to accommodate proot syscall limitations.
- Optimizes download speeds with `ParallelDownloads = 10` and masks kernel updates (`IgnorePkg = linux-aarch64`).

### `user.sh` (Phase 3b)
- Provisions a regular, non-root user account inside the container with `zsh` as default shell.
- Assigns the user to the `wheel` group.
- Safely configures passwordless sudo privileges verified using `visudo -c`.

### `launcher.sh` (Phase 3c)
- Configures Termux UI enhancements (`~/.termux/termux.properties` extra-keys row with `ESC`, `TAB`, `CTRL`, `ALT`, directional arrows).
- Installs transparent auto-login hooks into `.bashrc` and `.zshrc` with container smoke-test timeouts.
- Provides `archkill` to terminate hung proot container processes.

### `toolchain.sh` (Phase 4a)
Provisions the complete developer workstation stack in a unified, single-transaction execution:
1. **Core Development & Compilers:**
   - `base-devel` (`gcc`, `make`, `patch`, etc.), `git`, `tree-sitter-cli`.
   - Optional heavy compilers via flags: `--with-rust` (`rust`), `--with-go` (`go`), `--with-clang` (`clang`).
2. **Terminal Multiplexing & Sessions:**
   - `tmux` terminal multiplexer for managing multi-window, persistent background terminal sessions inside the container.
3. **Android SDK Platform Tools:**
   - `android-tools` (`adb`, `fastboot`) for Android on-device debugging, wireless debugging (`adb connect`), and port forwarding / reverse tunnels (`adb reverse tcp:8022 tcp:22`).
4. **GitHub CLI:**
   - `github-cli` (`gh`) for command-line GitHub authentication, pull requests, repository management, and issue tracking.
5. **Node.js & Web Developer Ecosystem:**
   - `nodejs`, `npm`, and `python` (`python-pip`).
   - Configures a user-owned, non-root global npm prefix (`~/.npm-global`) added to `$PATH`.
   - Automatically installs essential global utilities:
     - `serve`: Fast, zero-configuration local static file web server.
     - `pm2`: Production process manager and daemon monitor for background services and Node.js applications.
     - `pnpm`: Fast, disk space-efficient package manager.
6. **Modern CLI Productivity Suite:**
   - `ripgrep` (`rg`), `fd`, `fzf`, `bat`, `jq`, `lazygit`, `fastfetch`, `nano`, `openssh`, compression tools (`zip`, `unzip`, `tar`).
7. **Git Configuration & AUR:**
   - Batched Git global configuration (`init.defaultBranch main`, `core.editor nvim`, credentials caching).
   - Fast pre-built AUR helper (`paru-bin`) with automatic fallback guidance.
   - Interactive SSH host key generation for remote container access.

### `nerdfonts.sh` (Phase 4b)
- Installs `JetBrainsMono Nerd Font Mono` directly into `~/.termux/font.ttf`.
- Validates downloaded fonts against TTF/OTF magic bytes (`\x00\x01\x00\x00` / `OTTO`) and file size thresholds (> 1 MB).
- Performs atomic inode replacement using temporary staging files and `mv` to avoid file corruption while Termux is running.

### `shell.sh` (Phase 4c)
- Generates `en_US.UTF-8` locale inside the container to prevent cursor drift and rendering artifacts.
- Installs Oh My Zsh with the `agnoster` theme, `zsh-autosuggestions`, and `fzf` keybindings.
- Injects environment defaults (`EDITOR=nvim`, `VISUAL=nvim`, `PATH` including `~/.npm-global/bin` and `~/.local/bin`).

### `neovim.sh` (Phase 4d)
- Preconfigures LazyVim with full Nerd Font glyph support.
- Registers dynamic LSP servers via Mason (`bashls`, `marksman`, `pyright`, `ts_ls`, `html`, `cssls`, and conditional compilers).
- Pre-compiles Treesitter grammars headlessly to guarantee zero-lag syntax highlighting on first buffer open.

### `maintenance.sh` (Phase 6)
- Copies operational modules to `$PREFIX/share/termux-dev-env`.
- Generates 10 standalone management commands in `$PREFIX/bin`:
  - `archhealth`: Quick pass/fail system check.
  - `archdiag`: Comprehensive system, state, and baseline report.
  - `archupdate`: Resilient pacman upgrade with optional rootfs snapshotting.
  - `archreset`: Soft or hard container wipe and re-provisioning.
  - `archreapply`: Re-installs launcher hooks, extra-keys, and UI configs.
  - `archbridge`: Reverse-tunnel SSH client to computer over ADB.
  - `archfont`: Force-reinstalls and verifies the Nerd Font.
  - `archselfheal`: Triggers Phase 5 self-repair procedures.
  - `archparu`: Installs or repairs the `paru` AUR helper.
  - `archtreesitter`: Compiles the extended Treesitter parser grammar suite.

---

## 3. State & Configuration Hierarchy

```text
~/.config/termux-dev-env/
├── config.env          # Static configuration (distro name, architecture, username)
├── state.env           # Atomic phase completion flags (PHASE1_DONE .. PHASE6_DONE)
├── diagnostics.env     # Hardware baseline (RAM, CPU cores, Android SDK level)
├── last_error.env      # Context from the most recent [Exxx] fatal exception
├── snapshots/          # Package manifests and rootfs .tar.xz backups
└── logs/               # Timestamped installation and audit reports
```

All state modifications are transactional and guarded by `--dry-run` simulation modes.