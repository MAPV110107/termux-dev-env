# termux-dev-env

[![Architecture](https://img.shields.io/badge/architecture-aarch64-blue.svg)](#part-0--before-you-begin)
[![Platform](https://img.shields.io/badge/platform-Termux%20%2F%20Android-green.svg)](#part-2--installing-and-preparing-termux)
[![Distribution](https://img.shields.io/badge/distro-Arch%20Linux%20ARM-red.svg)](#phase-3--rootfs-user-launcher)
[![Shell](https://img.shields.io/badge/shell-ZSH%20Everywhere%20(Oh%20My%20Zsh)-yellow.svg)](#phase-4--dev-environment)
[![Editor](https://img.shields.io/badge/editor-LazyVim%20%2B%20LSP%20%2B%20Mason-purple.svg)](#part-5--day-to-day-usage)

Turn a stock Android phone into a full-featured **Arch Linux ARM** development workstation running natively inside `proot-distro` under Termux.

Features a tuned **LazyVim** IDE with complete **LSP support** (Bash, Markdown, Python, TypeScript, JavaScript, Rust, C/C++, Go, Kotlin, HTML, and CSS) powered by `mason.nvim`, `nvim-lspconfig`, and `blink.cmp`, universal **ZSH + Oh My Zsh + agnoster** across all host and internal terminal panes, parallel package downloads, memory-cached git credentials, Reticulum/Nomad Network, and speed-tuned `aria2` parallel downloads.

---

## ⚡ Quick Start (If you already have Termux)

```bash
# 1. Update Termux packages & install git/curl
pkg update -y && pkg install -y git curl

# 2. Clone and enter repo
git clone https://github.com/MAPV110107/termux-dev-env
cd termux-dev-env
chmod +x core.sh

# 3. Run the installer (or preview with --dry-run)
./core.sh
```

---

## Table of Contents

- [Part 0 — Before You Begin](#part-0--before-you-begin)
- [Part 1 — Installing F-Droid](#part-1--installing-f-droid)
- [Part 2 — Installing & Preparing Termux](#part-2--installing--preparing-termux)
- [Part 3 — Installing termux-dev-env](#part-3--installing-termux-dev-env)
- [Part 4 — Installation Phases Explained](#part-4--installation-phases-explained)
- [Part 5 — Day-to-Day Usage & Keymaps](#part-5--day-to-day-usage--keymaps)
- [Part 6 — Maintenance Commands](#part-6--maintenance-commands)
- [Part 7 — CLI Flags & Options](#part-7--cli-flags--options)
- [Known Limitations](#known-limitations)

---

## Part 0 — Before You Begin

### Requirements
- **Android phone running `aarch64` (64-bit ARM)**: Standard for Android devices manufactured since 2017.
- **Wi-Fi connection**: The installer downloads ~1.5–2.5 GB of rootfs, compiler toolchains, and LSP runtimes.
- **Storage**: At least **6 GB of free storage** (hard minimum is 3 GB).
- **Time**: ~15–35 minutes depending on CPU performance and internet speed.

> [!IMPORTANT]
> **Source of Termux**: Do **not** install Termux from Google Play. The Play Store version is obsolete and cannot reach active package repositories. Always install from [F-Droid](https://f-droid.org) or direct GitHub releases.

> [!NOTE]
> **Android Verification Policies**: Google's Play Store developer policy shifts do not restrict F-Droid or direct APK side-loading.

---

## Part 1 — Installing F-Droid

1. Open your mobile browser and go to **[f-droid.org](https://f-droid.org)**.
2. Tap **Download F-Droid** to save `F-Droid.apk`.
3. Open the downloaded file from your notification shade or Downloads folder.
4. Allow app installs from this source if prompted, then tap **Install**.
5. Open F-Droid and allow it to initialize its package repository index.

---

## Part 2 — Installing & Preparing Termux

### 2.1 Install Termux
1. In F-Droid, search for **Termux**.
2. Tap **Install** and open Termux once ready.

### 2.2 First-Run Initialization & Upgrades
```bash
pkg update -y && pkg upgrade -y
```
*(Press `Enter` to keep default configuration files when prompted).*

### 2.3 Grant Storage Permission
```bash
termux-setup-storage
```
Tap **Allow** on the permission prompt to bind `~/storage/shared`.

### 2.4 Install Git & Curl
```bash
pkg install -y git curl
```

---

## Part 3 — Installing termux-dev-env

### 3.1 Clone Repository
```bash
git clone https://github.com/MAPV110107/termux-dev-env
cd termux-dev-env
chmod +x core.sh
```

### 3.2 (Optional) Preview with Dry Run
```bash
./core.sh --dry-run
```
Simulates every phase without modifying packages or writing persistent state.

### 3.3 Run the Installer
```bash
./core.sh
```
- Prompts for your desired **Arch username**, **Git commit author identity**, and optional **SSH remote keys**.
- **Resumable**: If interrupted by network drops or Android background management, rerun `./core.sh` to resume seamlessly.

---

## Part 4 — Installation Phases Explained

The installation executes an idempotent, sequential 6-phase pipeline:

```
[Phase 1: Validation] ──> [Phase 2: Diagnostics] ──> [Phase 3: Rootfs & Shell]
                                                              │
[Phase 6: Maintenance] <── [Phase 5: Audit & Self-Heal] <── [Phase 4: Toolchain & LazyVim]
```

### Phase 1 — Bootstrap Validation
- Verifies Termux runtime, `aarch64` CPU architecture, and free disk space.
- Checks storage permissions and automatically triggers `termux-setup-storage` polling if needed.
- Holds `termux-wake-lock` during installation to prevent Android deep sleep.
- Installs base dependencies (`proot-distro`, `git`, `curl`, `wget`, `python`).
- Automates background battery optimizations if **Shizuku** (`rish`) is detected.

### Phase 2 — Diagnostics & Compatibility
- Captures RAM, CPU core count, filesystem type, and Android SDK level.
- Tests proot execution compatibility against kernel ptrace constraints.
- Persists baseline metrics to `~/.config/termux-dev-env/diagnostics.env`.

### Phase 3 — Rootfs, User & Shell Integration
- Downloads official Arch Linux ARM rootfs with **GPG signature verification**.
- Initializes pacman keyring with smartcard daemons disabled (`disable-scdaemon`) and configures `DisableSandbox` and `ParallelDownloads = 5` in `/etc/pacman.conf`.
- Creates your user account with `/usr/bin/zsh` as default shell and passwordless `sudo` (`wheel` group).
- Installs and configures ZSH + Oh My Zsh + agnoster on the Termux host with auto-login hooks in `.bashrc` and `.zshrc`.
- Deploys `archkill` into `$PREFIX/bin`.

### Phase 4 — Toolchains, LSPs & LazyVim
- **Development Toolchains**: Installs `base-devel` (gcc), `clang`, `rust`, `go`, `nodejs`, `npm`, `python`, `python-pip`, `tree-sitter-cli`, `marksman`, `nano`, `wget`, `curl`.
- **Git Identity**: Configures global user/email and 24-hour in-memory credential caching (`git credential-cache`).
- **AUR Helper**: Installs `paru-bin` with non-interactive optimization.
- **Typography**: Installs JetBrainsMono Nerd Font (Mono variant) to `~/.termux/font.ttf`.
- **ZSH Everywhere**: Configures ZSH as the universal default across Termux host, container userland, and LazyVim terminals.
- **LazyVim & LSP Suite**:
  - Full **LSP support** pre-configured via `nvim-lspconfig` and `mason.nvim` for:
    - **Bash**: `bashls` (`bash-language-server`)
    - **Markdown**: `marksman`
    - **Python**: `pyright`
    - **TypeScript / JavaScript**: `ts_ls` / `vtsls`
    - **Rust**: `rust_analyzer`
    - **C / C++**: `clangd`
    - **Go**: `gopls`
    - **Kotlin**: `kotlin_language_server`
    - **HTML / CSS**: `html`, `cssls` (`vscode-langservers-extracted`)
  - Fast autocomplete via `blink.cmp` wired with LSP, snippet, path, and buffer providers.
  - Pre-compiled Treesitter parsers for all supported languages.
  - File management via `oil.nvim` (`-` key).
  - Internal terminal (`Ctrl + /`) explicitly bound to `/usr/bin/zsh`.
- **Telecom & Utilities**: Reticulum Network Stack (RNS), Nomad Network, tuned `aria2` parallel downloader, and optional OpenSSH server.

### Phase 5 — Functional Audit, Self-Heal & Cleanup
- Verifies live post-conditions for all critical tools and language servers.
- Automatically retries non-blocking items (fonts, telecom) if transient errors occurred.
- Cleans verified download tarballs from `~/.cache/termux-dev-env/rootfs`.
- Writes full timestamped audit logs to `~/.config/termux-dev-env/logs/`.

### Phase 6 — Maintenance Commands
- Installs standalone maintenance commands to `$PREFIX/bin`.
- Syncs a permanent shared copy of installer libraries to `$PREFIX/share/termux-dev-env`.

---

## Part 5 — Day-to-Day Usage & Keymaps

### Navigation & Terminals
- **Launch**: Opening Termux drops you directly into your Arch Linux ZSH environment inside tmux.
- **Internal Terminal**: Press `Ctrl + /` inside LazyVim to toggle an embedded floating/split ZSH terminal pane.
- **Exit**: Type `exit` to close your session.
- **Force Kill**: If a container process hangs, open a new Termux session and run `archkill`.
- **Bypass Auto-Login**: Run `TDE_SKIP_LAUNCHER=1 zsh` to land in a plain Termux host shell.

### Editor Keymaps & LSP Workflows

| Keymap / Command | Function |
|---|---|
| `nvim <file>` | Open LazyVim (fast startup, LSP diagnostics, syntax tree parsing) |
| `gd` | Go to definition (LSP) |
| `gr` | Find references (LSP) |
| `K` | Hover symbol documentation (LSP) |
| `<leader>cr` | Rename symbol across project (LSP) |
| `<leader>ca` | Code action (LSP) |
| `<leader>cd` | Line diagnostic detail (LSP) |
| `<leader>lc` | **On-demand lint check**: runs `tsc --noEmit` on active buffer |
| `-` | Open `oil.nvim` filesystem editor |
| `Ctrl + /` | Toggle embedded **ZSH terminal pane** |
| `git push` | Push commits (token cached in memory for 24 hours) |

---

## Part 6 — Maintenance Commands

Accessible directly from any Termux shell:

| Command | Description |
|---|---|
| `archhealth` | Quick pass/fail component audit across container, LSPs, and host hooks. |
| `archdiag [--quick]` | Full system diagnostics: hardware drift, state flags, and component check. |
| `archupdate [--with-backup]` | Snapshots package list, runs `pacman -Syu`, optionally backs up full container, and re-audits health. |
| `archreset --soft` | Wipes and reinstalls the Arch container from Phase 3 onward (preserves validated bootstrap). |
| `archreset --hard` | Complete reset: wipes container, configuration, launcher hooks, and state. |
| `archreapply` | Reinstalls launcher snippets into `.bashrc`/`.zshrc` and refreshes `archkill`. |
| `archbridge [port] [user]` | Connects outbound SSH tunnel to a computer over `adb reverse` (e.g. `adb reverse tcp:8022 tcp:22`). |

---

## Part 7 — CLI Flags & Options

```bash
# Standard run (or resume from last checkpoint)
./core.sh

# Dry-run: preview all actions without executing
./core.sh --dry-run

# Force reinstall from a specific phase onward (cascades forward 1-6)
./core.sh --reinstall=3

# Combine dry-run with targeted phase reinstall
./core.sh --dry-run --reinstall=4
```

### Advanced Environment Variables
- `TDE_ROOTFS_URL_OVERRIDE`: Supply a custom URL to a verified Arch ARM rootfs tarball (accompanied by `<url>.sig`).
- `TDE_SKIP_LAUNCHER=1`: Bypasses the auto-login hook when launching a Termux session.

---

## Known Limitations

- **Isolated Storage**: Container runs with `--isolated` (proot filesystem isolation). Android `/sdcard` is not mounted inside the container by default.
- **Font Rendering Cache**: After installing Nerd Fonts, force-stop Termux in Android Settings and relaunch if glyphs appear as boxes.
- **Architecture**: Exclusively supports 64-bit ARM (`aarch64`). 32-bit ARM (`armv7l`) and x86_64 devices are not supported.

For detailed debugging steps, mirror selection, and edge cases, see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).
