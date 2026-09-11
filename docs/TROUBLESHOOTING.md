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

## Something is broken and you're not sure what

```bash
archdiag           # full diagnostic: hardware diff + component health + state dump
archdiag --quick   # just the component health check, faster
```

Reports also land in `~/.config/termux-dev-env/logs/` with a
timestamp — useful for comparing against a previous known-good run.
