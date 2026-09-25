# Troubleshooting

## Pinning the Arch Linux ARM rootfs to a known-good version

archlinuxarm.org only serves `latest` — unlike LazyVim's starter (a git
repo you can pin to a commit), there's no dated/historical tarball URL
to point at. If you've verified a specific install works well and want
to avoid picking up a future upstream change:

1. Keep a copy of the exact tarball + its `.sig` file you verified
   (from that install's cache before Phase 5 cleaned it up, or
   downloaded fresh from the mirror you used).
2. Host both files anywhere reachable (your own server, cloud storage,
   a GitHub release).
3. Set `TDE_ROOTFS_URL_OVERRIDE` to the tarball's URL before running
   `./core.sh` (the `.sig` is expected at the same URL with `.sig`
   appended). GPG verification still applies — this only changes where
   the file comes from, not whether it's checked.

## The Nerd Font install ran but icons still show as boxes

This is expected right after install. Android caches font rendering at
the app level — force-stop Termux from Android's app settings and
reopen it. There's no way to verify from a script that Android actually
picked up the new font; this is an inherent platform limitation, not a
bug in the installer.

## `chsh` didn't make zsh the default shell in Termux

Some Termux/Android combinations don't accept `chsh -s $PREFIX/bin/zsh`
cleanly. This is non-fatal by design — the launcher snippet is written
to **both** `.bashrc` and `.zshrc`, so entering Arch automatically still
works from bash. Run `archreapply` to retry writing the snippets if
needed; `chsh` itself isn't retried automatically since it's a one-time
system change, not a file write.

## The launcher won't stop trying to enter a broken container

Use the escape hatch: `TDE_SKIP_LAUNCHER=1 zsh` (or `bash`), or export
`TDE_SKIP_LAUNCHER=1` before opening Termux. This skips the auto-login
for that session only.

## `<leader>lc` (on-demand lint) says "tsc: command not found"

`typescript`/`eslint` are installed via a user-writable npm prefix and
symlinked into `/usr/local/bin` during phase 4. If this step failed
silently (check the phase 4 log), re-run `./core.sh --reinstall=4` to
redo the whole dev-environment phase, or `archdiag` to see which
specific check is failing.

## RNS/Nomad Network or aria2 never got installed

These are intentionally non-blocking — a failure logs a warning and the
rest of the install continues. They retry automatically on the next
`./core.sh` run (their state flag is only set on real success). Phase
5's self-heal also retries them once automatically right after install.

## Reticulum/aria2 can't reach files in Android's shared storage

Expected for now — the login session uses `--isolated`, which does not
bind `/sdcard`. `aria2.conf`'s `dir=` points inside the container's own
filesystem (`/home/<user>/downloads`). The file bridge between Android
storage and the container isn't implemented yet.

## Maintenance commands (`archhealth`, `archdiag`, `archreapply`) stopped working

They source `lib/`+`components/` from `$PREFIX/share/termux-dev-env`,
copied there once during phase 6 — not from wherever you originally
cloned this repo. If you've edited the live repo and want the
maintenance commands to pick up the changes, re-sync with:

```bash
./core.sh --reinstall=6
```

## `git push` keeps asking for a token

`credential.helper` is set to `cache --timeout=86400` (24h) — memory
only, never written to disk. This is intentional: it costs one re-auth
per day in exchange for the token never touching disk. If you want a
longer cache (or a different tradeoff), edit the container's
`~/.gitconfig` directly.

## A phase failed partway through

Re-run `./core.sh` — every phase and sub-step is resumable and only
redoes what didn't already pass its own verification. If a specific
phase needs to be forced to redo even though it's marked done, use
`./core.sh --reinstall=<phase number>`.

## `proot-distro` says the `archarm` container "already exists"

This can happen if a previous run got as far as creating the container
but failed a later check in Phase 3 (for example, a `DisableSandbox`
verification failure — see the next section). As of this version,
`./core.sh` detects this itself and repairs the existing container
in place instead of trying to reinstall it — just re-run `./core.sh`.

If you hit the raw `proot-distro` error directly (e.g. running
`proot-distro install` by hand), **do not run `proot-distro reset
archarm`** — this project installs from a tarball, not an OCI image,
and `reset` only works for OCI-based installs (`Reset is supported for
OCI images only.`). The correct recovery is:

```bash
proot-distro remove archarm
./core.sh
```

## Phase 3 says "Rootfs installed and verified" and then immediately fails FATAL

This means `phase3_install_rootfs_run` finished, but the post-condition
check (`phase3_rootfs_ok`) found something missing. As of this version
the FATAL message names the specific sub-check that failed (container
not listed / pacman keyring missing / `DisableSandbox` missing) instead
of a bare failure — check the log line just above the `[FATAL]` for
which one it was, then just re-run `./core.sh`: the container is
detected as already existing and only the missing piece gets repaired,
not a full reinstall.

If it's specifically `DisableSandbox` and it keeps failing after
several `./core.sh` runs, verify by hand:

```bash
proot-distro login archarm -- grep DisableSandbox /etc/pacman.conf
```

If that comes back empty, `/etc/pacman.conf` inside the container may
not have the standard `[options]` header `sed` looks for. Insert it
manually and re-run:

```bash
proot-distro login archarm -- sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
./core.sh
```

## `df: unknown option 'm'` or Phase 1/2 fail right at the free-space / diagnostics check

Termux's own `coreutils` package deliberately ships **without** `df`
(`termux-packages/packages/coreutils/build.sh`: `--enable-no-install-program=...,df,...`
with the comment `# df does not work either, let system binary prevail`).
So on a real device, `df` on `$PATH` is Android's own **toybox** `df`,
which only understands `-P`/`-k` (1024-byte-block output) — not GNU
coreutils' `-m`. As of this version the installer uses `df -k` and
converts to MB itself, which both toybox and GNU coreutils support
identically, so this should no longer come up. If you're on an old
clone and still hit it, `git pull` (or apply the fix by hand: replace
`df -m "$PREFIX" | awk 'NR==2 {print $4}'` with
`df -k "$PREFIX" | awk 'NR==2 {print int($4/1024)}'` in both
`lib/validate_env.sh` and `lib/diagnose.sh`).

The same root cause affects a bare `mount` call: it's not a Termux
package either (`termux-packages` issues #14495, #10207), and
`/system/bin` is deliberately never added to Termux's `$PATH` (it would
shadow Termux's own tools). `diagnose_fs_type` now falls back to
`/system/bin/mount` directly when nothing named `mount` is found, and
never blocks the install even if that still can't be parsed — the
filesystem type is informational only, logged as `unknown` rather than
failing Phase 2.

## `proot-distro list` shows the container but Phase 3 still says "not listed", or the installer loops forever after a run that visually succeeded

This was a false negative in the post-condition check itself, not a real
problem with the rootfs. The old check parsed plain `proot-distro list`
with `awk '{print $1}'`, assuming the container's alias is always the
first column — which breaks on a distro/alias table header, an
install-marker `*` prefix, or ANSI color codes, depending on the
`proot-distro` version. As of this version, the check instead looks
directly at the same directory `proot-distro` itself uses to decide
"already installed" (`$PREFIX/var/lib/proot-distro/installed-rootfs/<alias>/etc`),
with `proot-distro list -q` and a login smoke test as fallbacks — so it
can no longer be thrown off by list-output formatting, and a container
that's genuinely on disk is recognized immediately without needing to
reinstall or edit `state.env` by hand.

## The installer (or a later `archhealth`/`archupdate`) seems to hang with no error, after Phase 4 shell setup

The container's `.zshrc` auto-attaches tmux on login
(`tmux attach -t main || tmux new -s main`). Older versions of this
snippet ran that unconditionally, which could take over the terminal on
any of the many `proot-distro login --user <name> -- <command>` calls
phases 4 through 6 make to run things inside the container as that user
— not just a real interactive session. As of this version the snippet
only fires for an actually-interactive shell (zsh's own `-o interactive`,
which is off for a `-c command` invocation regardless of whether a TTY
happens to be attached), so scripted logins are unaffected. If you're on
an old clone and hit this, check `~/termux-dev-env/.git` is up to date,
or edit the container's `~/.zshrc` by hand: wrap the `tmux attach ...`
line in `if [[ -o interactive ]] && [ -t 0 ] && ...`.

## `error: target not found: marksman` — Phase 4 toolchain install FATALs

As of this version `marksman` is no longer a hard `pacman` dependency.
Upstream Arch rebuilt it as an `x86_64`-specific package (it used to be
architecture-independent, `any`), and Arch Linux ARM has no confirmed
`aarch64` build of it — so a hard dependency on it could FATAL the
entire toolchain phase over one Markdown LSP server. Mason.nvim's own
`ensure_installed` list (see `lazyvim.sh`) already installs `marksman`
itself the first time Neovim starts, independent of the system package
manager, so nothing is lost. If you're on an old clone and still hit
this, remove `marksman` from the `pacman -S` line in
`components/dev_toolchain.sh` and re-run `./core.sh`.

## `paru install failed` stops the whole toolchain phase

As of this version a failed `paru-bin` build (common on low-RAM phones
or a slow mirror — it still runs through `makepkg`, which can be slow
or OOM even for a prebuilt package) is a warning, not a FATAL, and the
toolchain post-check no longer requires `paru` to be present — only
`gcc` and `git`, which is what the rest of the pipeline (LazyVim,
treesitter, Mason) actually depends on. To install `paru` later:
```bash
proot-distro login archarm --user <your-username> -- sh -c \
  'cd /tmp/paru-bin && makepkg -si --noconfirm'
```
(or `git clone --depth 1 https://aur.archlinux.org/paru-bin.git /tmp/paru-bin` first if that directory is gone).

## `sudo` asks for a password I never set, or rejects it ("Sorry, try again")

`useradd` never sets a password on its own, and as of this version
`wheel` gets passwordless sudo (`NOPASSWD: ALL` in
`/etc/sudoers.d/wheel-nopasswd`) — so `sudo` normally shouldn't prompt
at all. If it does, and you're on an install from before this version,
your account genuinely has no valid password (the account was locked),
so no password you type will work. As of this version, user creation
prompts you to set one as a fallback (used only if the NOPASSWD rule
doesn't apply for some reason — it does **not** affect opening Arch
from Termux, which never checks a password either way), and the
sudoers.d write is verified with `visudo -c` so a malformed rule FATALs
immediately instead of silently not applying. On an older install, fix
it directly:
```bash
proot-distro login archarm -- passwd <your-username>
```
That's a real root shell (no password needed to get it), so it works
regardless of the sudo issue. To check why NOPASSWD isn't applying:
```bash
proot-distro login archarm -- cat /etc/sudoers.d/wheel-nopasswd
proot-distro login archarm -- visudo -c
proot-distro login archarm -- id <your-username>   # confirm you're actually in the wheel group
```

## `pacman` fails with "Resolving timed out" or mirror timeouts inside Arch

Mobile connections (DNS instability, CGNAT, rate-limiting) can make the
tarball's default single GeoIP mirror (`mirror.archlinuxarm.org`) time
out mid-transaction, especially for large Phase 4 packages like `rust`,
`clang`, or `go`. As of this version, Phase 3 writes a multi-mirror
`/etc/pacman.d/mirrorlist` (reusing the same mirrors already trusted for
the rootfs tarball download) and both `pacman` calls in Phase 4 retry
up to 3 times with backoff — so a single transient timeout no longer
takes the whole toolchain phase down. If it still fails after 3
attempts, it's worth checking your connection or switching networks
(mobile data vs. Wi-Fi) before re-running `./core.sh` — pacman resumes
partially-downloaded packages on its own, so nothing already fetched is
wasted. To check or fix the mirrorlist by hand:
```bash
proot-distro login archarm -- cat /etc/pacman.d/mirrorlist
proot-distro login archarm -- bash -c '
  echo "Server = http://mirror.archlinuxarm.org/\$arch/\$repo" > /etc/pacman.d/mirrorlist
  pacman -Syyu --noconfirm
'
```

## `mkinitcpio` warnings ("Permission denied", "missing firmware") during Phase 4

This container never boots its own kernel — it always runs under the
host Android kernel via `proot` — so these warnings from installing
`linux-aarch64` (pulled in as a `base-devel`/toolchain dependency) are
expected noise, not a real problem: `autodetect`'s `/sys/devices` scan
fails under `proot` (no real device nodes), and most listed firmware is
for server/RAID hardware nothing here has. As of this version, Phase 3
sets `IgnorePkg = linux-aarch64` in `pacman.conf` so `pacman -Syu`
skips the kernel package entirely — avoiding both the noise and the
wasted bandwidth of downloading a kernel this environment never uses.
This is best-effort (a `log_warn`, not fatal, if it can't be set), so if
you still see this noise it's harmless either way — let `mkinitcpio`
finish, it doesn't block package installation.

## `pacman` hangs or fails with signature errors inside Arch

Phase 3 runs `pacman-key --init` + `--populate archlinuxarm` and sets
`DisableSandbox` in `/etc/pacman.conf` — both are required for pacman to
work correctly inside proot (its sandboxed hook/download execution needs
Linux namespaces proot doesn't provide, and gpg-agent's scdaemon can hang
with no real smartcard device to talk to). If pacman still misbehaves,
check these landed: `archdiag` reports rootfs health, or manually verify
with `proot-distro login archarm -- grep DisableSandbox /etc/pacman.conf`.

## `archbridge` can't connect

`archbridge` only handles the phone side (the `ssh` call). The tunnel
itself is set up **on the computer**, over USB debugging:

```bash
adb devices                    # confirm the phone shows up
adb reverse tcp:8022 tcp:22    # forward phone:8022 -> computer:22
```

Do this before running `archbridge` on the phone. When done, run
`adb reverse --remove-all` on the computer to tear the tunnel down.

## `Permission denied` running `./core.sh`

`chmod +x core.sh` and try again — git doesn't always preserve the
executable bit through every clone/transfer path. Or just run
`bash core.sh` instead of `./core.sh` anywhere in this project's docs;
it works the same way regardless of that permission bit.

## `lib/lock.sh: ... /tmp/termux-dev-env.lock: No such file or directory`

Fixed as of this version — the lock file used to assume a real,
writable `/tmp` at the filesystem root, which Termux's Android sandbox
doesn't guarantee (unlike a normal Linux install). It now uses
`$TMPDIR` if set, or `$PREFIX/tmp` (Termux's own, always-present temp
directory) otherwise. If you still hit this on an old clone, `git pull`
to get the fix.

## Something is broken and you're not sure what

```bash
archdiag           # full diagnostic: hardware diff + component health + state dump
archdiag --quick   # just the component health check, faster
```

Reports also land in `~/.config/termux-dev-env/logs/` with a
timestamp — useful for comparing against a previous known-good run.
