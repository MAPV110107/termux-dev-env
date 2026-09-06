# termux-dev-env

Automated, repeatable installer that turns a Termux install into a working
Arch Linux ARM (via proot-distro) development environment: LazyVim, git,
Reticulum/Nomad Network, and a tuned aria2 setup — optimized for low
latency inside proot.

## Status

Phase 1 (bootstrap validation) implemented. Phases 2-6 in progress —
see `docs/CHANGELOG.md` as it gets added.

## Usage

```bash
./core.sh            # run/resume the installer
./core.sh --dry-run   # print what would happen, change nothing
```

State persists in `~/.config/termux-dev-env/`. Re-running `core.sh`
resumes from the last completed phase instead of starting over.
