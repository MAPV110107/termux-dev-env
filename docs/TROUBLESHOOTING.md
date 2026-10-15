# Troubleshooting Guide

Quick solutions for common platform limitations, network issues, and container edge cases in `termux-dev-env`.

---

## 1. Nerd Font & Icon Rendering

### Icons still appear as empty boxes (`□`) or question marks after install

Android caches terminal fonts in memory per application process. Even after `termux-reload-settings` runs, an active Termux process may continue using the old memory-mapped font until the app is completely restarted.

**Step 1 · Force-stop Termux**
Close Termux completely from **Android Settings > Apps > Termux > Force stop**, then reopen it. If you have ADB or Shizuku connected, run:

```bash
adb shell am force-stop com.termux
```

**Step 2 · Verify the installed font file**
Confirm that `~/.termux/font.ttf` is a valid, patched TrueType/OpenType font (> 1 MB) and test Private Use Area (PUA) glyph rendering:

```bash
ls -lh ~/.termux/font.ttf
```

```bash
od -An -tx1 -N4 ~/.termux/font.ttf
```

```bash
printf '\ue0b0 \u00b1 \ue0a0 \u27a6 \u2718 \u26a1 \u2699 \uf115 \ue795 \uf07c\n'
```

> A valid font outputs `00 01 00 00` (TrueType) or `4f 54 54 4f` (OpenType) on the `od` check.

**Step 3 · Force a clean inode replacement**
If the font file is missing or corrupted, reinstall it with a fresh inode and reload Termux settings:

```bash
archfont --force
```

---

### Glyphs work in Termux, but break inside Arch (`character not in range`)

If icons render properly in Termux's host shell but break inside the Arch container (or `fastfetch` prints `character not in range`), the container's UTF-8 locale was not generated.

Verify that `en_US.utf8` is listed inside the container:

```bash
proot-distro login archarm -- locale -a
```

Regenerate and export the `en_US.UTF-8` locale manually if missing:

```bash
proot-distro login archarm -- sh -c '
  grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
  locale-gen
  printf "LANG=en_US.UTF-8\nLC_ALL=en_US.UTF-8\n" > /etc/locale.conf
'
```

---

## 2. Termux Keyboard & UI

### The `ESC`, `CTRL`, `TAB`, and arrow keys row is missing

Earlier configurations or manual edits may have set `extra-keys = []` in `~/.termux/termux.properties`. `termux-dev-env` never overwrites an existing `extra-keys` line automatically, to respect custom user layouts.

Remove the empty definition and re-apply the default two-row developer layout:

```bash
sed -i '/^[[:space:]]*extra-keys[[:space:]]*=[[:space:]]*\[\]/d' ~/.termux/termux.properties && archreapply
```

---

## 3. Container Login & Session Control

### Termux refuses to enter Arch or stays in the host shell on startup

Before executing `proot-distro login`, the launcher snippet runs a 25-second smoke test verifying that your container home directory exists, `/usr/bin/zsh` is executable, and your login shell is set to `/usr/bin/zsh`.

If the container timed out (`exit 124` due to Android memory pressure), terminate the hung container processes and open a new session:

```bash
archkill
```

If a component check failed, inspect the exact cause:

```bash
archdiag
```

### Bypassing auto-login (Escape Hatch)

To open a plain Termux host shell without entering the Arch container:

```bash
TDE_SKIP_LAUNCHER=1 bash
```

---

## 4. Package Manager (`pacman`) & Network Mirrors

### `pacman` fails with `Resolving timed out` or slow downloads

Mobile networks (CGNAT, flaky DNS, carrier rate limits) can cause transient timeouts against Arch Linux ARM mirrors. `termux-dev-env` configures a multi-mirror `/etc/pacman.d/mirrorlist`, sets `ParallelDownloads = 10`, and retries `pacman` operations automatically.

If all retries fail, switch networks (Wi-Fi vs. mobile data) and re-run the installer (`pacman` resumes partial downloads automatically):

```bash
./launcher.sh
```

To inspect or reset `/etc/pacman.d/mirrorlist` manually inside the container:

```bash
proot-distro login archarm -- cat /etc/pacman.d/mirrorlist
```

```bash
proot-distro login archarm -- sh -c '
  echo "Server = http://os.archlinuxarm.org/\$arch/\$repo" > /etc/pacman.d/mirrorlist
  pacman -Syyu --noconfirm
'
```

---

### `pacman` hangs on signature verification or sandbox errors

Running `pacman` inside `proot` requires two specific configurations in the container:
1. `DisableSandbox` in `/etc/pacman.conf` (since `proot` does not emulate kernel namespaces for `pacman`'s download sandbox).
2. `disable-scdaemon` in `/etc/pacman.d/gnupg/gpg-agent.conf` (prevents `gpg-agent` from hanging while polling for physical smartcards).

Verify that `DisableSandbox` is active:

```bash
proot-distro login archarm -- grep "^DisableSandbox" /etc/pacman.conf
```

If missing, insert it and re-run the installer:

```bash
proot-distro login archarm -- sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf && ./launcher.sh
```

---

### `mkinitcpio` or firmware warnings during system updates

The Arch container runs atop the host Android kernel via `proot` and never boots its own kernel. `termux-dev-env` adds `IgnorePkg = linux-aarch64` to `/etc/pacman.conf` to save bandwidth and skip unnecessary initramfs generation. Any remaining `systemd`, `udev`, or `firmware` hook warnings printed during `pacman -Syu` are harmless under `proot`.

---

## 5. AUR Helper (`paru`)

### `paru` fails with `libalpm.so.XX: cannot open shared object file`

`paru-bin` is a precompiled binary linked against the `libalpm` version present when it was built. When a rolling `pacman -Syu` upgrades `pacman` to a newer `libalpm` soname, `paru-bin` may stop running until upstream rebuilds the binary package.

Reinstall `paru-bin` using the maintenance command:

```bash
archparu
```

If `paru-bin` is still out of sync with the latest `libalpm`, compile `paru` from source linked directly against your current system libraries (uses single-threaded `CARGO_BUILD_JOBS=1` to prevent Android OOM kills):

```bash
archparu --from-source
```

> **Note on Exit Code 137 (OOM):** If a source build fails with exit code `137`, Android's Low Memory Killer terminated `rustc`. Close background Android apps, keep Termux in the foreground, and run `archparu --from-source` again.

---

## 6. Neovim, LazyVim, Mason & Treesitter

### First launch of `nvim` is slow or opens installer windows

`mason-lspconfig.nvim` intentionally skips server installation during `--headless` runs to prevent background build races. The first time you open `nvim` interactively, Mason automatically downloads the configured LSP servers (`bashls`, `marksman`, `pyright`, `ts_ls`, `html`, `cssls`, plus any enabled compiled language servers). Let Mason finish before closing the editor.

### `<leader>lc` reports `tsc: command not found`

By default, TypeScript language servers are managed by Mason inside Neovim's data directory. If you want global CLI access to `tsc`, `eslint`, `pyright`, and `bash-language-server` in your shell and via `!<cmd>`, run Phase 4 with `TDE_PREINSTALL_NPM_LSP=1`:

```bash
TDE_PREINSTALL_NPM_LSP=1 ./launcher.sh --reinstall=4
```

### Compiling the full Treesitter parser suite

By default, `termux-dev-env` pre-compiles a core set of 16 Treesitter parsers so installation stays fast. To compile the extended ~30-language parser suite at any time:

```bash
archtreesitter
```

---

## 7. User Account & `sudo` Permissions

### `sudo` prompts for a password or rejects authentication

The installer configures passwordless `sudo` for the `wheel` group (`/etc/sudoers.d/wheel-nopasswd`) and validates the syntax with `visudo -c`. If `sudo` ever prompts for a password and you did not set one during installation, set or reset your container user's password directly from Termux (root login via `proot-distro` requires no password):

```bash
proot-distro login archarm -- passwd <your-username>
```

Verify your `sudoers` configuration and group membership:

```bash
proot-distro login archarm -- visudo -c
```

```bash
proot-distro login archarm -- id <your-username>
```

---

## 8. Process Locking (`flock`)

### `[FATAL] Another termux-dev-env process is already running (PID ...)`

`termux-dev-env` uses an advisory `flock` lock (`$TMPDIR/termux-dev-env.lock`) to prevent concurrent processes from corrupting `state.env` or the container rootfs.

If another instance is genuinely running, wait for it to finish or terminate it using the PID shown in the message:

```bash
kill <pid>
```

If Android killed a previous session and a child process still holds the descriptor, remove the lock file only after confirming no `launcher.sh` or `archupdate` process is active:

```bash
rm -f "${TMPDIR:-$PREFIX/tmp}/termux-dev-env.lock"
```

---

## 9. Pinning the Arch Linux ARM Rootfs

Upstream Arch Linux ARM only publishes a rolling `ArchLinuxARM-aarch64-latest.tar.gz` image. To pin your environment to a specific verified snapshot:

1. Host a copy of your verified `ArchLinuxARM-aarch64-latest.tar.gz` and its matching `.sig` file on a server or GitHub Release.
2. Run the installer with `TDE_ROOTFS_URL_OVERRIDE` (GPG signature verification against the Arch Linux ARM keyring remains enforced):

```bash
TDE_ROOTFS_URL_OVERRIDE="https://example.com/ArchLinuxARM-aarch64-latest.tar.gz" ./launcher.sh
```

---

## 10. ADB SSH Bridge (`archbridge`)

`archbridge` connects from your phone back to an SSH server on your computer over USB debugging. Before running `archbridge` in Termux, set up the reverse tunnel on your computer:

```bash
adb devices
```

```bash
adb reverse tcp:8022 tcp:22
```

Then connect from Termux:

```bash
archbridge 8022 <computer-username>
```

To remove the USB tunnel on your computer when finished:

```bash
adb reverse --remove-all
```

---

## 11. Diagnostics, Self-Heal & Full Reset

Run a quick component health audit:

```bash
archhealth
```

Retry recoverable components (such as the Nerd Font) and re-audit the system:

```bash
archselfheal
```

Inspect the last recorded `[Exxx]` error code, hardware baseline, and phase state flags:

```bash
archdiag
```

Reinstall the Arch container from Phase 3 onward while keeping Termux host packages intact:

```bash
archreset --soft
```

Completely remove the Arch container, configuration, and all state files:

```bash
archreset --hard
```