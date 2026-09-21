# termux-dev-env

[![Architecture](https://img.shields.io/badge/architecture-aarch64-blue.svg)](#part-0--before-you-begin)
[![Platform](https://img.shields.io/badge/platform-Termux%20%2F%20Android-green.svg)](#part-2--installing-and-preparing-termux)
[![Distribution](https://img.shields.io/badge/distro-Arch%20Linux%20ARM-red.svg)](#phase-3--rootfs-user-launcher)
[![Shell](https://img.shields.io/badge/shell-zsh%20%2B%20oh--my--zsh-yellow.svg)](#phase-4--dev-environment)
[![Editor](https://img.shields.io/badge/editor-LazyVim%20(no--LSP)-purple.svg)](#part-5--day-to-day-usage)

Turn a stock Android phone into a high-performance **Arch Linux ARM** development workstation running natively inside `proot-distro` under Termux.

Features a freeze-free **LazyVim** setup configured specifically for mobile hardware (no persistent memory-hogging LSP daemon; on-demand linting via `<leader>lc`), **zsh + Oh My Zsh + agnoster**, global git identity with memory-cached credentials, Reticulum/Nomad Network, and tuned `aria2` parallel downloads.

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
- [Part 5 — Day-to-Day Usage](#part-5--day-to-day-usage)
- [Part 6 — Maintenance Commands](#part-6--maintenance-commands)
- [Part 7 — CLI Flags & Options](#part-7--cli-flags--options)
- [Known Limitations](#known-limitations)

---

## Part 0 — Before You Begin

### Requirements
- **Android phone running `aarch64` (64-bit ARM)**: Virtually every Android device released since 2017.
- **Wi-Fi connection**: The installer downloads ~1–2 GB of packages and rootfs assets.
- **Storage**: At least **6 GB of free storage** (hard minimum is 3 GB).
- **Time**: ~15–35 minutes depending on CPU speed and internet bandwidth.

> [!IMPORTANT]
> **Source of Termux**: Do **not** install Termux from Google Play. The Play Store version was deprecated years ago and cannot update repositories. Always use [F-Droid](https://f-droid.org) or direct GitHub APKs.

> [!NOTE]
> **Android Developer Verification**: Google's Play Store policy changes starting September 2026 apply strictly to participating app stores (Google Play, Galaxy Store). F-Droid and direct APK installs remain completely unaffected.

---

## Part 1 — Installing F-Droid

F-Droid is an open-source catalog of verified Android applications.

1. Open your browser on Android and navigate to **[f-droid.org](https://f-droid.org)**.
2. Tap **Download F-Droid** to get `F-Droid.apk`.
3. Open the downloaded file from your notification tray or Downloads app.
4. If prompted to allow installs from this source, tap **Settings**, enable the toggle, then tap **Install**.
5. Launch F-Droid and wait for it to download its package index.

---

## Part 2 — Installing & Preparing Termux

### 2.1 Install Termux
1. In F-Droid, search for **Termux**.
2. Tap **Install** and open Termux once finished.

### 2.2 First-Run Initialization & Upgrades
Run the package updater to sync to the latest mirrors:
```bash
pkg update -y && pkg upgrade -y
```
*(Press `Enter` to keep default config files when prompted).*

### 2.3 Grant Storage Permission
```bash
termux-setup-storage
```
Tap **Allow** on the Android permission popup to map `~/storage/shared`.

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
Prints every phase and action without touching packages, writing files, or saving state.

### 3.3 Run the Installer
```bash
./core.sh
```
- Prompts for your desired **Arch username**, **Git user/email**, and optional **SSH host keys**.
- **Resumable**: If Android kills the session or your Wi-Fi disconnects, rerun `./core.sh` to resume exactly where it left off.

---

## Part 4 — Installation Phases Explained

The installation operates as an idempotent 6-phase state machine:

```
[Phase 1: Validation] ──> [Phase 2: Diagnostics] ──> [Phase 3: Rootfs & Launcher]
                                                              │
[Phase 6: Maintenance] <── [Phase 5: Self-Heal & Audit] <── [Phase 4: Dev Toolchain]
```

### Phase 1 — Bootstrap Validation
- Verifies Termux runtime, `aarch64` CPU architecture, and free disk space.
- Manages storage permissions and acquires a `termux-wake-lock` to prevent Android from sleeping.
- Installs base dependencies (`proot-distro`, `git`, `curl`, `wget`, `python`).
- Optionally automates background exemptions if **Shizuku** (`rish`) is present.

### Phase 2 — Diagnostics & Compatibility
- Probes total/available RAM, CPU cores, filesystem type, and Android API level.
- Tests proot execution compatibility against kernel ptrace constraints.
- Persists baseline metrics to `~/.config/termux-dev-env/diagnostics.env`.

### Phase 3 — Rootfs, User & Launcher
- Downloads official Arch Linux ARM rootfs from active mirrors with **GPG signature verification**.
- Initializes pacman keyring (`pacman-key --init` with `disable-scdaemon`) and disables pacman sandboxing (`DisableSandbox`) required under proot.
- Creates your user account with passwordless `sudo` (`wheel` group).
- Installs and configures zsh + Oh My Zsh + agnoster in Termux, writing the auto-login hook into `.bashrc` and `.zshrc`.
- Installs the emergency `archkill` command in `$PREFIX/bin`.

### Phase 4 — Dev Environment
- Installs development toolchain (`base-devel`, `git`, `nodejs`, `npm`, `tree-sitter-cli`, `python-pip`, `nano`, `wget`, `curl`).
- Configures git credential caching (in-memory 24h cache; never written to plaintext storage).
- Installs `paru-bin` (AUR helper) with pre-tuned non-interactive configuration.
- Installs JetBrainsMono Nerd Font (Mono variant) to `~/.termux/font.ttf`.
- Preconfigures **LazyVim**:
  - Disabled persistent LSP daemons to eliminate mobile memory locks, ghost-text lag, and buffer freezing.
  - Replaced neo-tree with `oil.nvim` (`-` key).
  - Configured on-demand linting via `<leader>lc` (`tsc --noEmit`).
  - Pre-compiled core Treesitter parsers (JS/TS, Lua, Bash, JSON, Markdown, YAML, TOML).
- Installs Reticulum Network Stack (RNS), Nomad Network, and speed-optimized `aria2` config (non-blocking).
- Configures optional OpenSSH server host keys.

### Phase 5 — Functional Audit, Self-Heal & Cleanup
- Verifies live post-conditions for all critical and optional components.
- Automatically retries non-blocking items (fonts, telecom) once before concluding.
- Safely cleans verified tarballs and temporary caches from `~/.cache/termux-dev-env/rootfs`.
- Writes full timestamped audit logs to `~/.config/termux-dev-env/logs/`.

### Phase 6 — Maintenance Commands
- Installs standalone maintenance commands to `$PREFIX/bin`.
- Syncs a permanent copy of installer libraries to `$PREFIX/share/termux-dev-env`.

---

## Part 5 — Day-to-Day Usage

### Entering & Leaving
- **Launch**: Opening Termux automatically drops you into your Arch Linux zsh environment inside tmux.
- **Exit**: Type `exit` to close your session.
- **Force Kill**: If a container process hangs, open a new Termux tab and run `archkill`.
- **Bypass Auto-Login**: Run `TDE_SKIP_LAUNCHER=1 zsh` to drop directly into a plain Termux host shell.

### Editor Keymaps & Workflow

| Shortcut / Command | Action |
|---|---|
| `nvim <file>` | Open LazyVim (instant startup, syntax highlighting, snippet completion) |
| `<leader>lc` | **On-demand lint/typecheck**: runs `tsc` / `eslint` against current buffer |
| `-` | Open `oil.nvim` file manager to edit filesystem as a buffer |
| `Ctrl-/` | Toggle embedded zsh terminal pane |
| `git push` | Push to remote (token cached securely in memory for 24 hours) |

---

## Part 6 — Maintenance Commands

Accessible from any Termux shell after installation:

| Command | Description |
|---|---|
| `archhealth` | Quick pass/fail component audit across the container and host hooks. |
| `archdiag [--quick]` | Full system diagnostics: hardware drift (then vs. now), state flags, and component check. |
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
