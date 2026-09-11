# termux-dev-env

Automated, resumable installer that turns a fresh Termux install into a
working Arch Linux ARM (via proot-distro) development environment:
LazyVim with no persistent LSP, zsh + oh-my-zsh + agnoster on both sides
of the launcher, git, Reticulum/Nomad Network, and a tuned aria2 setup —
built around low latency inside proot and a resumable, self-verifying
install.

## Quick start

```bash
git clone <this-repo>
cd termux-dev-env
./core.sh
```

Answers a few prompts along the way (Arch username, git identity,
whether to enable an SSH server). Safe to re-run if interrupted — it
resumes from the last completed step, it doesn't start over.

## Flags

```bash
./core.sh --dry-run              # print what each phase would do, change nothing
./core.sh --reinstall=4          # clear phase 4 AND every phase after it (1-6), then redo
./core.sh --dry-run --reinstall=3   # combine: preview what redoing phase 3 onward would touch
```

## What gets installed, phase by phase

1. **Bootstrap** — validates Termux/aarch64/storage/proot version, installs
   base packages, optional Shizuku hook for the battery-exemption command.
2. **Diagnostics** — RAM/storage/cores/API level captured, compared
   against a compatibility matrix (warns, never blocks).
3. **Rootfs + user + launcher** — GPG-verified Arch Linux ARM (aarch64)
   install direct from archlinuxarm.org, pacman keyring init +
   `DisableSandbox` (both needed for pacman to work correctly inside
   proot), validated user with passwordless sudo (wheel),
   zsh+oh-my-zsh+agnoster in Termux itself, and the auto-login snippet
   in both `.bashrc` and `.zshrc`.
4. **Dev environment** — compiler toolchain, Nerd Font, zsh+oh-my-zsh+
   agnoster inside Arch, LazyVim (no LSP, oil.nvim instead of neo-tree,
   on-demand `<leader>lc` lint, pre-installed treesitter parsers),
   Reticulum/Nomad Network + aria2, optional SSH.
5. **Audit, self-heal, cleanup, report** — re-verifies every component,
   retries recoverable failures, deletes only what's confirmed good,
   writes a timestamped report to `~/.config/termux-dev-env/logs/`.
6. **Maintenance commands** — installs `archhealth`, `archdiag`,
   `archupdate`, `archreset`, `archreapply`, `archbridge` to `$PREFIX/bin`,
   and copies `core.sh`+`lib/`+`components/` to
   `$PREFIX/share/termux-dev-env` so those commands — including a full
   reinstall via `archreset` — keep working even if this cloned repo is
   later moved or deleted.

## Maintenance commands (after install)

| Command | Purpose |
|---|---|
| `archhealth` | Quick pass/fail check of every component |
| `archdiag [--quick]` | Hardware diff (then vs. now) + component health + state dump |
| `archupdate [--with-backup]` | Snapshots packages, `pacman -Syu`, optional full rootfs backup, re-checks health |
| `archreset --soft\|--hard` | `--soft` reinstalls just the container (keeps bootstrap validated); `--hard` wipes everything |
| `archreapply` | Reinstalls the launcher snippet + `archkill`, idempotent |
| `archbridge [port] [user]` | SSH into a computer through an `adb reverse` tunnel (default port 8022, user root) — run `adb reverse tcp:8022 tcp:22` on the computer first |

Escape hatch if the launcher ever traps you in a broken container:
`TDE_SKIP_LAUNCHER=1 zsh` (or export it before opening Termux).

## Known open items

See `docs/TROUBLESHOOTING.md` for known limitations and gotchas. The
file bridge between Android storage and the Arch container is not yet
implemented — everything currently lives inside the container's own
filesystem.

## Repo layout

```
core.sh                  entry point, resumable phase orchestration
lib/                      shared infrastructure (logging, state, retries, etc.)
components/               phase 3-6 actions, one file per concern
tests/                     trace_source_order.sh, test_pure_logic.sh
docs/                      this file, TROUBLESHOOTING.md
```
