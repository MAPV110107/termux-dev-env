# termux-dev-env

Turns a stock Android phone into a working Arch Linux ARM development
environment — LazyVim with no persistent LSP, zsh + oh-my-zsh + agnoster,
git, Reticulum/Nomad Network, and a tuned aria2 setup, all running inside
`proot-distro` under Termux.

This guide starts from **absolute zero**: no F-Droid, no Termux, nothing
installed. Every step is explained, not just listed — if you already have
Termux set up, skip ahead to [Part 3](#part-3--installing-termux-dev-env).

---

## Table of contents

- [Part 0 — Before you begin](#part-0--before-you-begin)
- [Part 1 — Installing F-Droid](#part-1--installing-f-droid)
- [Part 2 — Installing and preparing Termux](#part-2--installing-and-preparing-termux)
- [Part 3 — Installing termux-dev-env](#part-3--installing-termux-dev-env)
- [Part 4 — What each phase actually does](#part-4--what-each-phase-actually-does)
- [Part 5 — Day-to-day usage](#part-5--day-to-day-usage)
- [Part 6 — Maintenance commands](#part-6--maintenance-commands)
- [Part 7 — Flags reference](#part-7--flags-reference)
- [Known limitations](#known-limitations)

---

## Part 0 — Before you begin

**What you need:**
- An Android phone, aarch64 (64-bit ARM) — this is virtually every phone
  sold since ~2017. If you genuinely don't know, you almost certainly
  have one.
- A Wi-Fi connection (the install downloads roughly 1-2 GB total).
- At least 6 GB of free storage (3 GB is the hard minimum the installer
  checks for; 6 GB avoids running close to the edge).
- About 20-40 minutes, depending on your connection and device.

**A note on where apps come from.** This guide installs Termux via
F-Droid, not the Google Play Store. The Play Store version of Termux was
discontinued years ago and no longer receives updates — it's actively
broken for this purpose. F-Droid is the correct, current source.

**A note on Android's new developer verification rules.** Starting
September 30, 2026, Google requires apps distributed through certain
*participating app stores* (Google Play, Samsung Galaxy Store, and a
handful of others) to come from a registered developer, in four
countries initially (Brazil, Indonesia, Singapore, Thailand), expanding
globally in 2027. This does **not** apply to F-Droid or to installing an
APK directly — both are explicitly outside that requirement. Nothing in
this guide is affected, anywhere.

---

## Part 1 — Installing F-Droid

F-Droid is a catalog of open-source Android apps, distributed as a
direct APK install rather than through Google Play. Termux is published
there because Play Store's policies are incompatible with what Termux
needs to do (unrestricted package management, no forced updates outside
its own control).

1. Open a browser on your phone and go to **https://f-droid.org**.
2. Tap the **Download F-Droid** button. This downloads `F-Droid.apk` to
   your Downloads folder.
3. Open the downloaded file (from your notification shade, or your
   Downloads app).
4. Android will prompt you to allow installing from this source (the
   browser or file manager you're using). This permission is granted
   per-app on modern Android, not as a single global toggle — you're
   only allowing *this specific app* to install APKs, not opening your
   phone up broadly. Tap **Settings** in the prompt, enable it, then go
   back and tap **Install**.
5. Once installed, open F-Droid. On first launch it downloads its app
   index — this can take a couple of minutes depending on your
   connection. Let it finish.

You now have F-Droid. You won't need to browse it manually — the next
step tells you exactly what to search for.

*(If you'd rather use a different F-Droid-compatible client like
Droid-ify or Neo Store, any of them work the same way for this guide —
install it the same way, then search for Termux inside it instead of
step 2 below.)*

---

## Part 2 — Installing and preparing Termux

### 2.1 Install Termux

1. Open F-Droid, tap the search icon, and search for **Termux**.
2. Tap the Termux result, then **Install**.
3. Open Termux once it's installed. You'll land on a black screen with a
   command prompt — this is a real Linux shell running on your phone.

### 2.2 Let Termux finish its own first-run setup

The first time you open it, Termux sets up its own internal storage.
Just wait a few seconds until you get a stable prompt (it'll look like
`~ $`).

### 2.3 Update Termux's own packages

Termux ships with an older package index than what's actually available.
Update it before anything else:

```bash
pkg update -y && pkg upgrade -y
```

You may be asked to confirm keeping/replacing config files during the
upgrade — the default option is fine, press Enter.

### 2.4 Grant storage permission

This lets Termux read/write Android's shared storage (Downloads,
`/sdcard`, etc.):

```bash
termux-setup-storage
```

Android will show a permission dialog — tap **Allow**. This creates a
`~/storage/shared` symlink you can browse from Termux.

### 2.5 Install git and curl

These are what you need to actually get the installer onto your phone:

```bash
pkg install -y git curl
```

Termux is now ready. Everything from here on is `termux-dev-env`'s own
job.

---

## Part 3 — Installing termux-dev-env

### 3.1 Clone the repository

```bash
git clone https://github.com/MAPV110107/termux-dev-env
cd termux-dev-env
chmod +x core.sh
```

The `chmod +x` makes `core.sh` directly runnable as `./core.sh`. If you
ever see `Permission denied` when running it, that's this bit missing —
run that command again, or just use `bash core.sh` instead of `./core.sh`
anywhere in this guide, which works regardless of the executable bit.

### 3.2 (Optional) Preview what will happen

Before touching anything real, you can see exactly what the installer
would do:

```bash
./core.sh --dry-run
```

This prints every action for every phase without executing any of them
— no packages installed, no files written, no state saved. Safe to run
as many times as you like.

### 3.3 Run the installer

```bash
./core.sh
```

This is the real run. It will:
- Ask a handful of questions along the way (your Arch username, your git
  name/email for commits, whether you want an SSH server).
- Take somewhere between 15 and 40 minutes depending on your connection
  and device — most of that time is package downloads and the LazyVim
  plugin sync.
- **Resume automatically if interrupted.** If your connection drops, the
  screen locks and Android kills the session, or you just need to stop —
  running `./core.sh` again picks up exactly where it left off. Nothing
  earlier gets redone.

When it's done, you'll see:

```
termux-dev-env: installation complete. Maintenance commands available:
archhealth, archdiag, archupdate, archreset, archreapply, archbridge.
```

That's it — the environment is ready. Part 5 covers how to actually use
it day to day.

---

## Part 4 — What each phase actually does

The installer runs in six phases, each one resumable independently. This
section explains what's actually happening during each one, so the wait
isn't a black box.

### Phase 1 — Bootstrap validation

Checks that you're really on Termux, on aarch64, that storage permission
is really granted (by test-writing a file, not just checking the folder
looks non-empty), that there's enough free space, and that `proot` is a
recent enough version. Installs the handful of Termux packages the
installer itself depends on (`proot-distro`, `git`, `curl`, `wget`,
`python`). If you have Shizuku installed, it's used here to automate the
battery-optimization exemption; if not, that step is just skipped
(non-blocking).

### Phase 2 — Diagnostics

Captures your RAM, storage, CPU cores, and Android API level, and
compares them against a compatibility matrix. Below the recommended
values just prints a warning and continues — this never blocks the
install, it just tells you what to expect.

### Phase 3 — Rootfs, user, launcher

The biggest phase. Downloads the official Arch Linux ARM rootfs
(aarch64-specific) directly from archlinuxarm.org, verifies it with GPG
before doing anything with it, and installs it via `proot-distro`. Then:
- Initializes pacman's keyring and disables its sandboxed download mode
  (proot doesn't support the Linux namespaces that sandbox needs — this
  is required for pacman to work at all inside proot, not optional
  hardening being skipped).
- Prompts for a username, validates it, creates the user with
  passwordless `sudo` access.
- Installs zsh + oh-my-zsh + the agnoster theme + autosuggestions in
  **Termux itself** (not just inside Arch), and tries to make it your
  default Termux shell.
- Writes the auto-login snippet to both `.bashrc` and `.zshrc` — so
  opening Termux drops you straight into Arch, regardless of which shell
  ends up as your actual default.
- Installs `archkill`, a command to force-close Arch if something ever
  gets stuck.

### Phase 4 — Dev environment

Everything that makes the environment actually usable:
- Compiler toolchain (`base-devel`, `git`, `nodejs`, `npm`, and a few
  basics like `nano`/`wget`/`curl`), your git identity, and `paru`
  (prebuilt, not compiled on-device — building it yourself would be slow
  and isn't necessary).
- A Nerd Font (needed for the editor/prompt icons to render — this step
  is non-blocking, since a font failing doesn't break anything
  functional, just cosmetics).
- zsh + oh-my-zsh + agnoster **inside Arch** too, so both sides of the
  launcher match.
- LazyVim, configured deliberately **without** a persistent language
  server. That's not a missing feature — it's the actual fix for the
  freezes, ghost text, and buftype bugs that motivated this whole
  project in the first place. In its place: `oil.nvim` as the file
  explorer, and an on-demand `<leader>lc` keymap that runs `tsc`/`eslint`
  only when you ask for it. Treesitter parsers for the languages you'll
  actually use are pre-installed so there's no first-open compile delay.
- Reticulum/Nomad Network and a speed-tuned `aria2` config (non-blocking
  — a failure here doesn't stop the rest of the install, and retries
  automatically on your next run).
- Optionally, an SSH server inside Arch (opt-in — you're asked).

### Phase 5 — Audit, self-heal, cleanup, report

Re-verifies every single component that was just installed — not just
"did the command exit zero", but the actual real-world condition (is the
user's UID really there, is the theme really set, can `tsc` really be
found). Anything non-critical that failed (the font, the telecom
packages) gets one automatic retry here. Everything is cleaned up
(downloaded tarballs, build directories) — but only what passed
verification; anything that failed its check is kept on disk so you can
inspect what went wrong. A full report lands in
`~/.config/termux-dev-env/logs/`.

### Phase 6 — Maintenance commands

Installs five commands to `$PREFIX/bin` (covered in detail in
[Part 6](#part-6--maintenance-commands)), and copies the installer's own
`core.sh` + `lib/` + `components/` to `$PREFIX/share/termux-dev-env` — so
those commands, and even a full reinstall, keep working even if you
later move or delete the folder you cloned in step 3.1.

---

## Part 5 — Day-to-day usage

**Opening Termux** drops you straight into Arch automatically (via the
launcher installed in Phase 3). You'll land in a tmux session with your
zsh prompt.

**Editing a file:**
```bash
nvim yourfile.ts
```
Opens instantly — there's no language server loading in the background.
Syntax highlighting and completion (buffer/path/snippets) work
immediately.

**Checking your code** (on demand, not automatic):
```
<leader>lc
```
Runs `tsc`/`eslint` against the current file and shows the result. This
is deliberately not automatic — it costs nothing while you're just
editing.

**File explorer** — press `-` to open `oil.nvim`. Creating, renaming, and
deleting files happens by editing the directory listing itself and
saving, not through a separate menu.

**Committing:**
```bash
git add -A
git commit -m "message"
git push
```
Your git identity was already configured during Phase 4. The first push
to a private remote will ask for credentials once (cached for 24 hours,
never written to disk).

**Terminal inside Neovim** — `Ctrl-/` opens a terminal that's explicitly
set to zsh, matching your shell outside the editor.

**Leaving** — type `exit`, or if Arch is ever stuck, run `archkill` from
a fresh Termux session (it lists your active tmux sessions first so you
know what you're about to lose, then asks for confirmation).

**Escape hatch** — if the auto-login into Arch is ever the problem
itself (a broken container you need to get past), run:
```bash
TDE_SKIP_LAUNCHER=1 zsh
```
or export `TDE_SKIP_LAUNCHER=1` before opening Termux, to land in a
plain Termux shell instead.

---

## Part 6 — Maintenance commands

Available from any Termux session after installation:

| Command | What it does |
|---|---|
| `archhealth` | Quick pass/fail check of every component |
| `archdiag [--quick]` | Hardware diff (now vs. install time) + component health + state dump |
| `archupdate [--with-backup]` | Snapshots installed packages, runs `pacman -Syu`, optionally backs up the whole rootfs first, re-checks health afterward |
| `archreset --soft` | Reinstalls just the Arch container, keeps Phase 1-2 (bootstrap/diagnostics already validated) |
| `archreset --hard` | Wipes everything — container, launcher, all state — for a completely clean start |
| `archreapply` | Reinstalls the launcher snippet + `archkill`, safe to run anytime |
| `archbridge [port] [user]` | SSH into a computer through an `adb reverse` tunnel (default port 8022, user root) — run `adb reverse tcp:8022 tcp:22` on the computer first |

---

## Part 7 — Flags reference

```bash
./core.sh                        # run or resume the installer
./core.sh --dry-run               # preview every phase, change nothing
./core.sh --reinstall=4           # clear phase 4 AND every phase after it (1-6), then redo
./core.sh --dry-run --reinstall=3 # combine: preview what redoing phase 3 onward would touch
```

`--reinstall` cascades forward deliberately — reinstalling an early
phase (say, phase 3, which can produce a different Arch username)
without redoing the phases after it would leave them configured against
a now-stale state.

Advanced: `TDE_ROOTFS_URL_OVERRIDE` lets you pin the Arch Linux ARM
rootfs to a specific, personally-verified copy instead of always
fetching the current `latest` — see `docs/TROUBLESHOOTING.md` for how
and why.

---

## Known limitations

- **No file bridge yet** between Android's shared storage and the Arch
  container. The login session uses `--isolated`, which intentionally
  doesn't bind `/sdcard`. Everything currently lives inside the
  container's own filesystem.
- The Nerd Font install can't be verified from a script — if icons show
  as boxes after install, force-stop Termux from Android's app settings
  and reopen it (see `docs/TROUBLESHOOTING.md`).
- 32-bit ARM (`armv7`) devices aren't supported — this targets aarch64
  specifically.

For anything not covered here, see `docs/TROUBLESHOOTING.md`.
