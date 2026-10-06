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

To tell "file is fine, Android has not applied it" apart from "file is
broken":

```bash
ls -lh ~/.termux/font.ttf          # exists, > 100 KB
od -An -tx1 -N4 ~/.termux/font.ttf # 00 01 00 00  or  4f 54 54 4f
printf '\ue0b0 \uf07c \n'          # boxes here = not loaded yet: force-stop
```

The installer deletes `font.ttf` before writing the new one, so a fresh
inode is always created; if boxes remain, run `archfont --force`, then
force-stop Termux (`adb shell am force-stop com.termux` also works).

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

## After a failed `paru` install, retrying from `/tmp/paru-bin` says the directory is gone

`phase5_cleanup` used to delete `/tmp/paru-bin` whenever the core
toolchain looked fine (`gcc`/`git` present) — but that's true regardless
of whether `paru`'s own build actually succeeded, since paru became
non-blocking. As of this version, that cleanup only runs once `paru` is
confirmed actually installed, so a failed build leaves the directory in
place for the manual retry command below (or in the previous section)
to actually work.

## `archhealth`/`archdiag` print "command not found" for a self-heal step involving fonts, telecom, or a retried package install

Older versions of the maintenance scripts didn't source
`components/telecom.sh`, `components/nerdfonts.sh`, `lib/network.sh`
(`retry_with_backoff`), or `lib/idempotent_append.sh`
(`idempotent_append_container`) — even though `phase5_self_heal` (which
both commands run) can call into all of them. As of this version all
four are sourced. If you're on an old clone and hit this, `git pull`
(or re-run `./core.sh --reinstall=6` to regenerate the maintenance
commands from the current source).

## `paru` build fails with "is not in the sudoers file" or a password prompt

As of this version, `paru-bin` is built with `makepkg -s` (build only,
never invokes `sudo`) as your user, then installed as root directly via
`pacman -U` — `proot-distro login` without `--user` is already
unauthenticated root, so this needs no sudo at all. sudo inside `proot`
is genuinely unreliable (namespace/capability/PAM quirks can make it
reject an otherwise-correct NOPASSWD rule), so this sidesteps the
question entirely for this one step rather than depending on it working.
If you're on an old clone and still hit this:
```bash
proot-distro login archarm --user <your-username> -- sh -c 'cd /tmp/paru-bin && makepkg -s --noconfirm'
proot-distro login archarm -- sh -c 'pacman -U --noconfirm /tmp/paru-bin/*.pkg.tar.*'
```

## `.zshrc` missing / `sed: can't read ... .zshrc: No such file or directory`

`phase4_install_ohmyzsh`'s old "already installed" check only looked for
the `.oh-my-zsh/` directory — if a previous run's install was interrupted
(network drop mid-clone) after that directory was created but before
`.zshrc` was generated, every later run would see the directory, skip
reinstalling, and leave `.zshrc` permanently missing, surfacing later as
an opaque `sed` error in the theme/plugin steps. As of this version, the
check requires both to exist (re-running the installer to repair just
`.zshrc` if only that's missing), the installer writes a minimal
fallback `.zshrc` if the upstream oh-my-zsh script still doesn't produce
one, and the theme/plugin steps warn and skip cleanly instead of
erroring if `.zshrc` is somehow still missing. To repair an existing
install stuck in this state:
```bash
./core.sh --reinstall=4
```
or manually:
```bash
proot-distro login archarm --user <your-username> -- sh -c '[ -f ~/.zshrc ] || cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc'
```

## Theme/plugins not applied, `tee: /data/data/com.termux/files/home/.config/nvim/...: No such file or directory`, or nvim says `No specs found for module "plugins"` (silently checked the wrong home)

Symptom: `agnoster` never shows up, zsh suggestions don't work, LazyVim
opens with `Error in init.lua: No specs found for module "plugins"`, or
the installer prints a `tee`/`sed` error whose path starts with
`/data/data/com.termux/files/home/` (Termux's home, not the container's).

Cause: `proot-distro login --user X -- tee ~/path` does **not** target
the container user's home. `~` is expanded by the shell that *calls*
`proot-distro` (Termux) before `proot-distro` even runs, so an unquoted
`~/path` silently resolves to Termux's own `$HOME`. Edits and checks went
to the wrong place: the LSP plugin files were written to Termux while
`example.lua` had already been deleted inside the container (leaving
`lua/plugins/` empty → "No specs found"), and `sed` for the theme/plugin
edited Termux's `.zshrc`. As of 0.4.0 every such call uses an absolute
`/home/<user>/...` path or keeps `~` inside a single-quoted `sh -c '...'`
(expanded by the container's shell). A regression test fails if any of
these ever leaks the host `$HOME` again.

To repair an existing install, re-run the affected phase:
```bash
./core.sh --reinstall=4
```

## `[E403] LazyVim did not pass its post-condition check`, even though the log shows plugins loading fine

Two independent bugs on a real device, both fixed as of 0.4.1:

**Race between LazyVim's own parser install and this project's own.**
`nvim-treesitter` on the `main` branch installs its configured parser
list itself, on every startup (`opts.ensure_installed`). The installer
*also* pre-installs parsers, in a separate headless `nvim` run — two
processes could end up building the same parser to the same
`~/.cache/nvim/<lang>/parser.so` at once:
```
Dynamic library `.../tree-sitter-vim/parser.so` not found after build attempt.
Are you running multiple processes building to the same output location?
```
As of 0.4.1, an override (`lua/plugins/treesitter.lua`) empties
`ensure_installed` specifically when `TDE_SKIP_TS_ENSURE=1` is set —
which every installer-driven `nvim --headless` call sets, and only
those, so a normal interactive session still gets LazyVim's own
behavior unchanged. Parser installs are also now verified afterward
(`get_installed()`) and retried once for anything still missing,
instead of trusting `:wait()` finishing without error.

**Headless `print()` goes to stderr, not stdout.** The post-condition
used to read the loaded-plugin count with
`nvim --headless -c "lua print(...)" -c "qa" 2>/dev/null`. In
`--headless` mode Neovim's `print()`/`:echo` write to **stderr**, so
discarding stderr discarded the only place the number was ever
printed — the check could FATAL with `E403` even when the log showed
LazyVim working correctly (`Lazy plugins loaded: 6`). As of 0.4.1 this
uses `io.stdout:write(...)` instead (with a `print()`-from-stderr
fallback for anything still expecting the old behavior). To check by
hand:
```bash
proot-distro login archarm --user <your-username> -- \
  nvim --headless -c "lua io.stdout:write(tostring(require('lazy').stats().loaded))" -c "qa"
```

## `E492: Not an editor command: TSInstallSync`, or `[FATAL] LazyVim did not pass its post-condition check`

`TSInstallSync` belonged to `nvim-treesitter`'s old (now frozen)
`master` branch. LazyVim's starter pins `nvim-treesitter` to `main`,
which removed the `TSInstall*` ex-commands entirely in its leaner
rewrite — using the old command is exactly this error, and it can drag
down the plugin-loaded count `phase4_lazyvim_ok` checks along with it.
As of this version, parser pre-install uses `main`'s actual Lua API
(`require('nvim-treesitter').install({...}):wait(300000)`) instead. If
you're on an old clone and still hit this:
```bash
proot-distro login archarm --user <your-username> -- \
  nvim --headless -c "lua require('nvim-treesitter').install({'bash','lua','python'}):wait(300000)" -c "qa"
```
(swap in whichever languages you use; see `components/lazyvim.sh` for
the full list this project installs by default).

Separately, `phase4_lazyvim_ok`'s options.lua check and
`phase4_verify_treesitter_cc`'s C-compiler detection now go through the
container (not a host-side path, and not grepping `:checkhealth`'s own
UI text, which is free to change across `nvim-treesitter` versions) —
see the next section for why that pattern matters generally.

## Design change: tmux is no longer part of the login flow (as of 0.5.0)

Earlier versions had `.zshrc` auto-attach a tmux session on login
(guarded to only fire on an interactive TTY). As of 0.5.0 **tmux is not
installed by this project at all**, and nothing it writes into
`.zshrc`/`.bashrc` references it. The flow is strictly
Termux → `exec proot-distro login <distro> --user <user> --isolated` →
Arch zsh, with a single `exit` closing the whole Termux session.

Why: tmux added a process in between (Termux → proot → zsh → tmux →
zsh) that needed two or three `exit`s to actually leave, and on a
device where a `--reinstall=4` ran before the interactive-shell guard
existed, exiting tmux could drop into a bare, theme-less `localhost%% `
zsh with no Oh My Zsh loaded — confusing given `archhealth` reported
everything `[OK]`.

If you installed an older version and still have tmux auto-attaching:
```bash
proot-distro login archarm --user <your-username> -- sh -c '
  sed -i "/tmux attach\|tmux new\|exec tmux/d" ~/.zshrc
'
```
Then re-run `./core.sh --reinstall=4` to pick up the current (tmux-free)
runtime block. tmux itself, if already installed, is left alone — this
only removes the auto-attach, never uninstalls the package.

## `exec proot-distro login` leaves me stuck with no Termux shell when the container is broken

As of 0.5.0 the launcher runs `proot-distro login ... --user ... -- true`
as a quick smoke test *before* committing to `exec` — if that fails, you
stay in a normal Termux prompt with a one-line hint (`archdiag`, or
`TDE_SKIP_LAUNCHER=1 zsh`) instead of `exec`-ing into a login that
immediately errors out with no shell left behind. If you're on an older
clone and already stuck: open a **new** Termux session (the stuck one
doesn't block new ones) and run `TDE_SKIP_LAUNCHER=1 zsh`.

## Prompt is a bare `localhost%% ` instead of agnoster, even though `archhealth` says Shell is `[OK]`

Two things can cause this, both fixed as of 0.5.0:
- `ZSH_THEME=` genuinely missing from `.zshrc` (the old `sed` silently
  does nothing if the line to replace isn't there — same footgun as
  `DisableSandbox` in `pacman.conf`, documented above). The theme step
  now inserts the line if it's missing, rather than only ever replacing
  an existing one.
- `source $ZSH/oh-my-zsh.sh` missing from `.zshrc` — zsh starts fine,
  the theme line can even be *correct*, but oh-my-zsh (and therefore the
  theme and plugins) never actually loads. `phase4_shell_ok` now runs a
  real interactive `zsh -ic` and checks the live `$ZSH_THEME`/`$ZSH`
  afterward, not just a text search, so this can't silently pass anymore.

Also likely present on the same install: `fastfetch` printing
`character not in range` and box-drawing glyphs failing — Arch Linux
ARM's rootfs ships with `LANG=C`, no UTF-8 locale generated at all. This
is a locale problem, not a missing-font problem. As of 0.5.0,
`en_US.UTF-8` is generated and exported automatically. To fix an
existing install by hand:
```bash
proot-distro login archarm -- sh -c '
  echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
  locale-gen
  printf "LANG=en_US.UTF-8\nLC_ALL=en_US.UTF-8\n" > /etc/locale.conf
'
```

## Mason shows a rename dialog for `williamboman/mason.nvim`, or install aborts mid-way through Mason

`mason.nvim` and `mason-lspconfig.nvim` moved from the `williamboman`
GitHub org to `mason-org` in their v2.0.0 release — the old URLs still
redirect today but relying on a redirect forever is fragile, and v2 also
**removed** the `automatic_installation` option entirely (replaced by
`automatic_enable`, which only auto-*enables* an already-installed
server, not installs one). As of 0.5.0 the LSP plugin spec uses
`mason-org/*` and `automatic_enable`.

Separately: `mason-lspconfig.nvim` deliberately does **not** run its
installer at all when Neovim is running `--headless` (upstream #175,
added specifically to stop a headless run's own install racing against
something else building in the same session and getting killed mid-way
by `-c "qa"`). That means Mason-managed servers install the first time
you open `nvim` for real, not during `./core.sh` itself — expected, not
a bug. If you want them ready immediately: open `nvim`, `:Lazy sync`,
and let Mason finish before closing it.

## Extra-keys row (ESC/TAB/CTRL/ALT/arrows) always visible in Termux

As of 0.5.0 the installer writes `extra-keys = []` and
`use-black-ui = true` to `~/.termux/termux.properties` (only filling in
whichever of the two isn't already set — never overwrites your own
customization) and reloads Termux's settings immediately. To change it
by hand:
```bash
echo 'extra-keys = []' >> ~/.termux/termux.properties
termux-reload-settings
```

## `paru` is installed but fails with `libalpm.so.1X: cannot open shared object file`

`paru-bin` is a prebuilt binary someone else compiled once against
whatever `libalpm` existed at the time — a later `pacman -Syu` (which
Phase 4 runs as its own first step) can move the system to a newer
`libalpm` soname the binary never knew about. As of 0.5.0, after
installing `paru-bin` the installer checks that it actually runs
(`paru --version`); if not, it rebuilds the plain `paru` AUR package
from source instead, which links against whatever `libalpm` is
genuinely installed right now and can't go stale that way (slower —
it's a real Rust compile — but only runs as a fallback). To do the same
by hand:
```bash
proot-distro login archarm --user <your-username> -- sh -c '
  rm -rf /tmp/paru && git clone --depth 1 https://aur.archlinux.org/paru.git /tmp/paru &&
  cd /tmp/paru && makepkg -s --noconfirm
'
proot-distro login archarm -- sh -c 'pacman -U --noconfirm /tmp/paru/*.pkg.tar.*'
```

## Nerd Font download is huge (~127MB) or "Termux isn't responding" during font/paru install

As of 0.5.0 the Nerd Font installs via Arch's own `ttf-jetbrains-mono-nerd`
package (official `extra` repo, architecture `any` — confirmed synced
to Arch Linux ARM — about 10.5MB) instead of downloading nerd-fonts'
own release zip, which bundles every style and width variant of the
font together for the one file this project actually uses (~127MB).
That download, running at the same time as `paru`'s build and Mason/
treesitter work, was a real contributor to Termux ANRs on a phone. The
zip download is kept only as a fallback if the package is ever
unavailable, with the `find` pattern broadened
(`*NerdFontMono-Regular.ttf`, then `*NerdFont-Regular.ttf`, then
`*JetBrainsMono*Regular*.ttf`) so a nerd-fonts asset rename doesn't
silently skip the install. `phase5_nerdfont_ok` also now checks the
file is over 100KB, not just that it exists — a 0-byte or truncated
copy used to pass silently.

## Install stops asking for storage permission, or `termux-setup-storage` prompt appears unnecessarily

As of 0.5.0 this is a warning, not a FATAL that blocks the whole
install — nothing in the current install flow reads or writes
`~/storage/shared` (the Arch container lives entirely under
`$PREFIX/var/lib/proot-distro/...`, and the launcher logs in with
`--isolated`, which doesn't mount `/sdcard` inside the container
either way). Grant it later with `termux-setup-storage` only if a
future file-bridge feature needs it.

## Reticulum/Nomad Network/aria2 ("telecom") didn't install, or I don't want it

As of 0.5.0 telecom is opt-in: set `TDE_WITH_TELECOM=1` before running
`./core.sh` to include it. Without that, `core.sh` doesn't even run
that step, `archdiag`/`archhealth` show it as `SKIP` rather than a
warning, and self-heal won't try to install it either. To add it to an
already-completed install:
```bash
TDE_WITH_TELECOM=1 ./core.sh --reinstall=4
```

## `.zshrc` still reads as missing even after the "writing a minimal fallback" warning, or theme/plugin steps keep skipping

An earlier version of this project's fix for the ".zshrc missing" issue
(see the section below) only made the *check* safe — it still compared
a direct host-side path into the rootfs
(`$PREFIX/var/lib/proot-distro/installed-rootfs/<distro>/home/<user>/.zshrc`)
against what oh-my-zsh had just written *from inside* `proot`. In the
wild, oh-my-zsh's own installer reported success and explicitly printed
"adding it to /home/&lt;user&gt;/.zshrc", yet that host-side path still read
as not existing immediately afterward — so every later step (theme,
plugin, the post-condition) kept treating a real, present `.zshrc` as
missing. As of this version, every `.zshrc` check and edit in
`shell_setup.sh` (`phase4_install_ohmyzsh`, `phase4_enable_autosuggestions_plugin`,
`phase4_set_zsh_theme`, `phase4_write_zshrc_extras`, `phase4_shell_ok`)
goes through `proot-distro login --user <you> -- test`/`grep`/`sed`
instead — the same access path the file was actually written through —
which matches how every other functional check in this project already
works (`phase3_rootfs_ok`, `phase4_toolchain_ok`, etc.).

This is now also fixed in `components/lazyvim.sh` (LazyVim starter
clone, its idempotency check, `options.lua`/`keymaps.lua`/
`autocmds.lua`/`lsp.lua`/`terminal.lua`/`file-explorer.lua`, and the
`phase4_lazyvim_ok` post-condition) and `components/dev_toolchain.sh`'s
`paru.conf` — all previously used the same host-side `container_home`
path pattern. The LazyVim starter clone was the riskiest of these: its
old idempotency check being a host-side false negative would fall
through to `rm -rf`-ing the whole nvim config and re-cloning from
scratch on every single run, silently destroying any customization to
your own LazyVim setup. `lib/idempotent_append.sh` now has a
container-side counterpart (`idempotent_append_container`) that these
all use instead of a host-side path, so this doesn't need reinventing
per call site.

**This same class of issue may still affect** the one remaining
host-side path construction from `container_home`, in
`components/telecom.sh` (`.aria2/`, `downloads/`) — not reported as
broken, so not changed yet, but if you hit a similarly inexplicable
"file missing right after something just wrote it" there, this is the
pattern to suspect. Report it and it'll get the same fix.

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

## The extra-keys row (ESC, CTRL, arrows) disappeared from my keyboard

Versions up to 0.5.0 wrote `extra-keys = []` into
`~/.termux/termux.properties`, which hides the row entirely. From 0.6.0
the installer never writes an empty row and never touches a row you
configured yourself, but it cannot safely guess whether an existing
`extra-keys = []` was your choice or its own old bug — so it warns
instead of overwriting.

To get the row back:

```bash
# delete the 'extra-keys = []' line, then:
archreapply
```

`archreapply` rewrites `termux.properties` (adding the default
ESC/CTRL/TAB/arrows row only when no row is configured) and reloads the
settings. To use your own layout instead, set `TDE_TERMUX_EXTRA_KEYS`
before running `./core.sh`.

## Icons are still boxes after the install (Nerd Font)

Two different causes, in order of likelihood:

1. **Android cached the old font.** The font is applied with
   `termux-reload-settings`, but Android caches a per-app font and
   sometimes ignores the reload. Force-stop Termux from
   Android Settings > Apps > Termux > Force stop, then reopen it.
2. **The font never installed, or installed truncated.** Run
   `archfont` — it validates the file (size *and* TTF/OTF magic bytes)
   and reinstalls it if it is missing or damaged. `archfont --force`
   replaces a font that already looks valid.

If glyphs are broken *inside* the container but fine in Termux, it is a
locale problem rather than a font one — see the locale warning the
installer prints, or run `archhealth`.

## Something broke after the install finished

`archselfheal` re-runs Phase 5's self-heal and audit on demand: it
retries the recoverable components (Nerd Font, telecom if you selected
it) and prints the full component report. The installer also leaves
Phase 5 eligible to run again on the next `./core.sh` while any
recoverable warning remains; `TDE_NO_SELF_HEAL=1` turns that off.

## "Another termux-dev-env process is already running"

The lock file now records the PID of the process holding it, and the
message names it. If that PID is alive, wait for it or `kill <pid>`. If
the message instead says the recorded process is gone (an OOM kill, a
closed Termux session), it tells you the exact `rm -f` to run — the
lock is never broken automatically, because doing so during a real
concurrent run is how a half-installed container happens.

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
