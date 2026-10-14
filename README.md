<div align="center">

# termux-dev-env

**Automated, self-healing Arch Linux ARM workstation for Termux on Android.**  
GPG-verified rootfs · Zsh + Oh My Zsh · LazyVim + LSP · Atomic Nerd Font rendering · No root required.

<br>

![Version](https://img.shields.io/badge/version-1.0.0-0d1117?style=flat-square&labelColor=b91c1c)
![Platform](https://img.shields.io/badge/platform-Termux%20%7C%20Android-0d1117?style=flat-square&labelColor=21262d)
![Architecture](https://img.shields.io/badge/arch-aarch64-0d1117?style=flat-square&labelColor=21262d)
![Distro](https://img.shields.io/badge/distro-Arch%20Linux%20ARM-0d1117?style=flat-square&labelColor=21262d)
![License](https://img.shields.io/badge/license-MIT-0d1117?style=flat-square&labelColor=21262d)

</div>

---

## Overview

`termux-dev-env` is a 6-phase, idempotent, and resumable provisioning system that transforms an Android (`aarch64`) device into a complete Linux development environment under `proot-distro`. Every phase validates its post-conditions before recording state, allowing interrupted runs to resume cleanly without duplicating configuration or re-downloading verified assets.

| Layer | Specification |
|:--|:--|
| **Container OS** | Official Arch Linux ARM (`aarch64`), GPG-verified against the upstream signing keyring |
| **Shell** | Zsh + Oh My Zsh (`agnoster`), `zsh-autosuggestions`, `fzf` keybindings, `fastfetch` login banner, strict `en_US.UTF-8` locale |
| **Editor** | LazyVim (`neovim`) preconfigured with `mason.nvim`, `nvim-lspconfig`, `blink.cmp`, `oil.nvim`, and pre-compiled Treesitter parsers |
| **Toolchain & CLI** | `base-devel` (`gcc`, `make`), `git`, `gh`, `nodejs`, `npm`, `python`, `ripgrep`, `fd`, `fzf`, `bat`, `jq`, `lazygit`, `openssh`, `paru-bin` |
| **Typography** | Atomic inode-replacing installation of `JetBrainsMono Nerd Font Mono (Regular)` validated via TTF/OTF magic bytes |
| **Resilience** | `flock` concurrency locking, exponential network backoff, self-healing audit (`Phase 5`), and standalone `arch*` CLI utilities |

---

## System Requirements

| Resource | Minimum | Recommended | Notes |
|:--|:--|:--|:--|
| **Architecture** | `aarch64` (ARM64) | `aarch64` (ARM64) | `armv7l` (32-bit) and `x86_64` are not supported |
| **Free Storage** | **3 GB** (`3072 MB`) | **6 GB+** (`6144 MB+`) | Checked on `$PREFIX` prior to rootfs download |
| **Total RAM** | **3 GB** (`3072 MB`) | **6 GB+** (`6144 MB+`) | Lower RAM works; opt-in Rust source builds require more headroom |
| **Available RAM** | **1.2 GB** (`1228 MB`) | **2.5 GB+** (`2560 MB+`) | Free memory before launching heavy LSPs or compilers |
| **CPU Cores** | **4 cores** | **8 cores** | Affects Treesitter parser compilation and package extraction |
| **Android Version** | **Android 7.0** (API 24) | **Android 10+** (API 29+) | Kernel must permit `ptrace` for `proot` execution |

---

## Quick Start

> [!NOTE]
> Install Termux exclusively from **[F-Droid](https://f-droid.org/en/packages/com.termux/)** or **[GitHub Releases](https://github.com/termux/termux-app/releases)**. The Google Play Store build is deprecated and incompatible with current Termux repositories.

### Step 1 · Update Termux Base System

Run the following command to synchronize package repositories and upgrade core libraries:

```bash
pkg update -y && pkg upgrade -y
```

> [!IMPORTANT]
> **Mandatory Restart:** Once the command above finishes, **close Termux completely** (exit the session or swipe it away from recent apps) and **open it again** before proceeding to Step 2. Upgrading core libraries (`bash`, `openssl`, `readline`, `termux-tools`) requires a fresh shell process. If prompted about configuration files during the upgrade, press `Enter` to keep the defaults.

### Step 2 · Install Bootstrap Dependencies

Install `git` and `curl` to fetch the repository:

```bash
pkg install -y git curl
```

### Step 3 · Clone the Repository

Clone `termux-dev-env` and enter the project directory:

```bash
git clone [https://github.com/MAPV110107/termux-dev-env.git](https://github.com/MAPV110107/termux-dev-env.git) && cd termux-dev-env
```

### Step 4 · Launch the Installer

Grant execution permissions and start the orchestrator:

```bash
chmod +x launcher.sh && ./launcher.sh
```

When installation completes, the installer releases its lock, resets the terminal scrollback, and drops you directly into your new Arch Linux ARM Zsh session.

---

## Optional Installation Flags

Preview the entire execution plan without modifying packages or state:

```bash
./launcher.sh --dry-run
```

Include heavy compiled language toolchains (`rust`, `go`, `clang`) and their respective LSP servers during installation:

```bash
./launcher.sh --with-rust --with-go --with-clang
```

Compile the extended Treesitter grammar suite (~30 languages) instead of the core set:

```bash
./launcher.sh --full-treesitter
```

Force a specific phase (and all subsequent dependent phases) to re-run from scratch:

```bash
./launcher.sh --reinstall=4
```

---

## Architecture & Execution Pipeline

```text
  [1. Validation] ──► [2. Diagnostics] ──► [3. Rootfs, User & Launcher]
                                                        │
  [6. Maintenance CLI] ◄── [5. Audit & Self-Heal] ◄── [4. Toolchain, Fonts, Shell & LazyVim]
```

| Phase | Module | Operations & Post-Conditions |
|:--|:--|:--|
| **1 · Validation** | `src/lib/validate.sh` | Verifies `$PREFIX`, `aarch64`, and free disk space (`df -k`). Acquires `termux-wake-lock`. Installs host bootstrap tools (`proot-distro`, `git`, `curl`, `gnupg`). Configures battery whitelist automatically if Shizuku (`rish`) is active. |
| **2 · Diagnostics** | `src/lib/validate.sh` | Records RAM, free storage, CPU cores, filesystem type, zram, and Android SDK level to `~/.config/termux-dev-env/diagnostics.env`. Verifies `proot` execution against kernel `ptrace` restrictions. |
| **3 · Core Container** | `src/modules/rootfs.sh`<br>`src/modules/user.sh`<br>`src/modules/launcher.sh` | Downloads the Arch Linux ARM tarball (`https` first, `http` fallback) and verifies its GPG signature. Configures `DisableSandbox`, `ParallelDownloads = 10`, and `IgnorePkg = linux-aarch64`. Creates a non-root user in `wheel` with `visudo -c` validated passwordless `sudo`. Configures Termux `extra-keys` and `.bashrc`/`.zshrc` auto-login hooks with a 25s smoke-test guard. |
| **4 · Workstation** | `src/modules/toolchain.sh`<br>`src/modules/nerdfonts.sh`<br>`src/modules/shell.sh`<br>`src/modules/neovim.sh` | Installs compilers, CLI utilities, and Neovim in a single `pacman` transaction. Configures Git globals and `paru-bin`. Installs `JetBrainsMonoNerdFontMono-Regular.ttf` with atomic inode replacement. Generates `en_US.UTF-8` locale and configures Oh My Zsh + LazyVim + Treesitter. |
| **5 · Audit & Heal** | `src/lib/audit.sh` | Runs functional post-condition checks across all critical and visual components. Automatically retries recoverable warnings, cleans verified download caches, and writes a timestamped report to `~/.config/termux-dev-env/logs/`. |
| **6 · Maintenance** | `src/modules/maintenance.sh` | Syncs runtime libraries to `$PREFIX/share/termux-dev-env` and deploys standalone `arch*` management commands into `$PREFIX/bin`. |

---

## Editor & Language Server Stack

LazyVim is preconfigured with `have_nerd_font = true`, `termguicolors = true`, `emoji = false`, and `ambiwidth = "single"` to prevent Android font fallback from misaligning terminal buffers.

### Configured LSP Servers

| Language | Server | Installation Mode |
|:--|:--|:--|
| **Bash / Shell** | `bashls` (`bash-language-server`) | Default (via Mason) |
| **Markdown** | `marksman` | Default (via Mason) |
| **Python** | `pyright` | Default (via Mason) |
| **TypeScript / JS** | `ts_ls`, `vtsls` | Default (via Mason) |
| **HTML / CSS** | `html`, `cssls` | Default (via Mason) |
| **Rust** | `rust_analyzer` | Automatic when `--with-rust` is passed or `rustc` is present |
| **C / C++** | `clangd` | Automatic when `--with-clang` is passed or `clang` is present |
| **Go** | `gopls` | Automatic when `--with-go` is passed or `go` is present |

> [!NOTE]
> Mason installs the configured language servers on your **first interactive `nvim` launch**. Allow the initial Mason sync window to complete before closing Neovim.

### Essential Keybindings

| Keymap | Mode | Action |
|:--|:--|:--|
| `gd` / `gr` | Normal | Go to definition / Find references |
| `K` | Normal | Show hover documentation |
| `<leader>cr` | Normal | Rename symbol across project |
| `<leader>ca` | Normal / Visual | Trigger code actions |
| `<leader>cd` | Normal | Inspect line diagnostics |
| `<leader>lc` | Normal | Save buffer and run `tsc --noEmit %` type-check on demand |
| `-` | Normal | Open parent directory in `oil.nvim` buffer editor |
| `Ctrl + /` | Normal / Terminal | Toggle floating/split Zsh terminal inside Neovim |

---

## Daily Workflow & Maintenance CLI

All maintenance commands are installed globally in Termux (`$PREFIX/bin`) and operate independently of the cloned repository.

### Session Control

Bypass automatic container login for a single Termux session:

```bash
TDE_SKIP_LAUNCHER=1 bash
```

Force-terminate a hung container instance from a second Termux session:

```bash
archkill
```

### Health & Diagnostics

Run a fast pass/fail functional audit of all container components:

```bash
archhealth
```

Generate a full diagnostic report (last recorded error code, hardware baseline, component audit, and state flags):

```bash
archdiag
```

### System Updates & Backups

Snapshot the package list, run a resilient `pacman -Syu` with automatic retries, and re-verify health:

```bash
archupdate
```

Create a full `.tar.xz` backup of the container rootfs before upgrading:

```bash
archupdate --with-backup
```

### Component Repair & Extensions

Reinstall and validate the patched `JetBrainsMono Nerd Font Mono`:

```bash
archfont --force
```

Install or repair the `paru` AUR helper (add `--from-source` to compile from source if `paru-bin` lags behind a `libalpm` soname bump):

```bash
archparu
```

Compile the full ~30-language Treesitter parser suite on demand:

```bash
archtreesitter
```

Re-apply Termux `extra-keys`, `.bashrc`/`.zshrc` launcher hooks, and `archkill`:

```bash
archreapply
```

Re-run Phase 5 self-healing and functional verification:

```bash
archselfheal
```

### Container Reset

Remove the Arch container and reset Phases 3–6 while keeping Termux bootstrap packages intact:

```bash
archreset --soft
```

Wipe the container, state files, snapshots, and all configuration:

```bash
archreset --hard
```

### ADB SSH Bridge

Connect outbound from the phone to a host computer over an active `adb reverse tcp:8022 tcp:22` tunnel:

```bash
archbridge 8022 root
```

---

## Environment Variables

Pass environment variables inline before `./launcher.sh` to customize installation behavior:

| Variable | Default | Description |
|:--|:--|:--|
| `TDE_DISTRO_NAME` | `archarm` | Custom `proot-distro` container alias |
| `TDE_DRY_RUN=1` | `0` | Simulate execution without modifying files or state |
| `TDE_WITH_RUST=1` | `0` | Install `rust` and enable `rust_analyzer` in LazyVim |
| `TDE_WITH_GO=1` | `0` | Install `go` and enable `gopls` in LazyVim |
| `TDE_WITH_CLANG=1` | `0` | Install `clang` and enable `clangd` in LazyVim |
| `TDE_TREESITTER_FULL=1` | `0` | Pre-compile the extended Treesitter parser set |
| `TDE_PREINSTALL_NPM_LSP=1` | `0` | Pre-install global npm language servers during Phase 4 |
| `TDE_PARU_FROM_SOURCE=1` | `0` | Allow compiling `paru` from Rust source during Phase 4 if `paru-bin` fails |
| `TDE_ROOTFS_URL_OVERRIDE` | *unset* | Custom URL for a pinned Arch Linux ARM tarball (requires matching `.sig`) |
| `TDE_TERMUX_EXTRA_KEYS` | *2-row layout* | Custom `extra-keys` layout for `~/.termux/termux.properties` |
| `TDE_TERMUX_BLACK_UI=1` | `0` | Write `use-black-ui = true` to `termux.properties` |
| `TDE_LAUNCHER_SMOKE_TIMEOUT` | `25` | Timeout (seconds) for the pre-login container health check |
| `TDE_NO_AUTO_RESTART=1` | `0` | Do not `exec` into Arch automatically when `./launcher.sh` finishes |

---

## Repository Structure

```text
termux-dev-env/
├── launcher.sh              # Root entry point
├── VERSION                  # Release version (1.0.0)
├── docs/
│   ├── ARCHITECTURE.md      # Internal design and state machine overview
│   ├── ERROR_CODES.md       # Reference table for [Exxx] fatal error codes
│   └── TROUBLESHOOTING.md   # Solutions for platform and proot edge cases
├── src/
│   ├── orchestrator.sh      # Phase coordinator and state migration engine
│   ├── lib/
│   │   ├── core.sh          # Error traps, E-code reporting, log rotation
│   │   ├── state.sh         # Atomic KEY=VALUE store and phase state flags
│   │   ├── lock.sh          # Dynamic-FD flock concurrency guard
│   │   ├── system.sh        # Network backoff, prompts, idempotent file blocks
│   │   ├── validate.sh      # Phase 1 bootstrap & Phase 2 hardware matrix
│   │   └── audit.sh         # Phase 5 functional verification & self-heal
│   └── modules/
│       ├── rootfs.sh        # GPG rootfs download, keyring, pacman tuning
│       ├── user.sh          # User creation and visudo-verified sudoers
│       ├── launcher.sh      # Termux UI extra-keys and auto-login hooks
│       ├── toolchain.sh     # Compilers, CLI tools, Git config, paru-bin
│       ├── nerdfonts.sh     # Atomic Nerd Font installer & magic-byte validator
│       ├── shell.sh         # UTF-8 locale generation and Oh My Zsh setup
│       ├── neovim.sh        # LazyVim, dynamic LSP specs, Treesitter compiler
│       └── maintenance.sh   # Generator for global arch* CLI commands
└── tests/
    ├── test_suite.sh        # Unit and regression assertions
    └── verify_all.sh        # Full static analysis, syntax, and dry-run runner
```

---

## Verification & Testing

Run the complete verification suite (syntax check, ShellCheck, unit tests, tilde-expansion audit, error code coverage, and CLI generation check):

```bash
./tests/verify_all.sh
```

---

## Troubleshooting

If an installation step aborts with a tagged code such as `[FATAL] [E411]`:

1. Run `archdiag` to inspect `last_error.env` and component status.
2. Consult **[docs/ERROR_CODES.md](docs/ERROR_CODES.md)** for the exact error code definition.
3. See **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** for recovery steps (such as force-stopping Termux in Android Settings if Nerd Font icons still appear as boxes after initial installation).

---

## License

Released under the [MIT License](LICENSE).