# Code review — termux-dev-env v0.5.0

Reviewed at commit `3b354a4`. **All findings below have since been fixed — see
§7 Resolution.**

Reviewed at commit `3b354a4`. ~5,650 lines of Bash across `core.sh`, `lib/` (14 files),
`components/` (10 files), `tests/` (3 files), plus README + 2 docs.

## 1. What it is

A phased, resumable installer that turns a Termux/Android (aarch64) device into an
Arch Linux ARM dev box under `proot-distro`:

| Phase | Does | Key files |
|---|---|---|
| 1 | Bootstrap validation (Termux, arch, disk, `pkg` update, proot version, optional Shizuku) | `lib/validate_env.sh` |
| 2 | Hardware diagnostics + compatibility matrix (warn-only) | `lib/diagnose.sh`, `lib/compat_matrix.sh` |
| 3 | GPG-verified rootfs download → `proot-distro install` → user + sudo → launcher | `components/install_rootfs.sh`, `create_user.sh`, `setup_launcher.sh` |
| 4 | Toolchain, Nerd Font, zsh/OMZ, LazyVim, opt-in telecom, fs utils | `dev_toolchain.sh`, `nerdfonts.sh`, `shell_setup.sh`, `lazyvim.sh`, `telecom.sh`, `fs_utils.sh` |
| 5 | Self-heal → audit → cleanup → report | `lib/verify_functional.sh`, `generate_report.sh`, `cleanup.sh` |
| 6 | Installs `archhealth`/`archdiag`/`archupdate`/`archreset`/`archreapply`/`archbridge` | `components/install_maintenance.sh` |

## 2. Verification I ran

| Check | Result |
|---|---|
| `bash -n` on all 28 scripts | pass |
| `tests/test_pure_logic.sh` | 125 checks, **ALL PASSED** (~70 s) |
| `tests/trace_source_order.sh` | pass |
| `tests/verify_all.sh` (9 rounds) | **ROUND CLEAN** (round 8, the full dry-run, auto-SKIPs off-device) |
| `shellcheck` | not available in this sandbox, and not wired into `verify_all.sh` |

## 3. Strengths

- **Genuinely idempotent.** `state.env` + per-step post-conditions (`phaseN_*_ok`) mean a
  step is only marked done if its *effect* is observable, not because a command exited 0.
  `--reinstall=N` correctly cascades forward through later phases.
- **Atomic, marker-based edits.** `kv_set` writes to a temp file then renames;
  `idempotent_append` strips its own previous block *and* the blank separator line, so
  re-runs don't grow `.zshrc` by a line each time. There's a container-side variant that
  goes through `proot-distro login` rather than a raw host path — a correct and
  non-obvious choice.
- **Supply chain.** The rootfs is GPG-verified against the ArchLinuxARM keyring, with
  per-mirror fallback that discards and retries on a bad signature, and a
  `TDE_ROOTFS_URL_OVERRIDE` escape hatch for pinning. No `curl | bash` anywhere.
- **Failure ergonomics.** 30 unique, documented `[Exxx]` codes, `last_error.env` for
  `archdiag`, a 662-line TROUBLESHOOTING.md, process locking via `flock`.
- **The comments are the best part.** Nearly every non-obvious line explains *why*,
  usually citing the real-device bug behind it (toybox `df` has no `-m`;
  `sed -i '/x/a y'` exits 0 when `x` never matches; `exec` leaking the lock FD into the
  new shell). Rare in shell projects.
- **Tests are regression-driven**, each tied to a dated field report, and `verify_all.sh`
  round 4 ("every called function is defined") and round 5 ("no bare `~/` reaches
  proot-distro") are clever static checks.

## 4. Bugs found

### 4.1 `_prompt` is undefined on any resumed run — install aborts (high)

`_prompt()` is defined in `lib/validate_env.sh`, which `core.sh:79-80` sources **only
inside the `PHASE1_DONE != 1` branch**. Three later components call it:

- `components/create_user.sh:22` (username prompt)
- `components/dev_toolchain.sh:37-38` (git name/email)
- `components/fs_utils.sh:17` (sshd host keys)

So the very scenario the state machine exists for — a run that got past Phase 1, died in
Phase 3, and is re-run — hits `_prompt: command not found`, and with `set -euo pipefail`
+ the ERR trap that kills the installer. Reproduced here:

```
components/create_user.sh: line 22: _prompt: command not found   (exit 127)
```

It passes CI because `verify_all.sh` round 4 and `trace_source_order.sh` both check
definitions across the *union* of sourced files, not per execution path.

**Fix:** move `_prompt` into its own always-sourced lib (e.g. `lib/prompt.sh`, or
`lib/logging.sh`) and source it unconditionally from `core.sh`'s preamble. Then add a
test that sources only the unconditional preamble + one component and asserts every
function it calls resolves.

### 4.2 The terminal reset before the shell handoff prints literal text (low)

`core.sh:272`:

```bash
printf '\\033c'      # inside single quotes this is \ \ 0 3 3 c
```

printf collapses `\\` to one literal backslash and then prints `033c`, so the user sees
`\033c` on screen and the scrollback is never cleared — the exact thing the six-line
comment above it says it's for. Should be `printf '\033c'`.

## 5. Smaller observations

1. **No `shellcheck` in the test suite.** `verify_all.sh` does `bash -n` only. Adding
   `shellcheck -S warning` (skipped gracefully when absent) would be the single highest
   value addition, and would likely have caught 4.2.
2. **No CI.** There's no `.github/workflows/`; `verify_all.sh` runs clean in ~2 minutes
   on a plain Ubuntu runner (round 8 self-skips), so a workflow is nearly free.
3. **No file is executable** (`100644`, including `core.sh`), which is why the README has
   to say `chmod +x core.sh`. `git update-index --chmod=+x core.sh` removes that step.
4. **Mirrors are fetched over `http://`** (`install_rootfs.sh:63`). Defensible — the
   tarball is GPG-verified and the mirrors do serve http — but `https://` first with an
   http fallback costs nothing and avoids the question entirely.
5. **`kv_get` can't distinguish empty from absent**: `echo "${val:-$default}"` returns the
   default for a key explicitly set to the empty string. Harmless for current callers
   (all values are `0`/`1`/usernames), worth a comment before someone stores `""`.
6. **`TDE_LOCK_FD=200` is hardcoded.** Fine in practice, but if anything ever sources
   `lock.sh` twice in nested shells it'll stomp itself; `exec {TDE_LOCK_FD}>` (bash 4.1+)
   would allocate one.
7. **`tests/test_pure_logic.sh` is 1,407 lines in one file.** It's well-organised by
   section, but it's the one file here that would benefit from being split per component.
8. **README is excellent but long** (~14 KB) and duplicates parts of TROUBLESHOOTING.md;
   the badge version (`0.5.0`) does correctly match `VERSION`.

## 6. Verdict

Unusually disciplined for a shell project of this size: real state machine, real
post-conditions, real regression tests, and documentation that explains intent rather
than restating code. The only thing I'd call a must-fix before another release is 4.1 —
it breaks the resume path, which is the project's headline feature. 4.2 and items 1-3 are
quick, mechanical wins.

---

## 7. Resolution (applied)

| # | Finding | Fix |
|---|---|---|
| 4.1 | `_prompt` undefined on resumed runs | Moved to new **`lib/prompt.sh`**, sourced unconditionally from `core.sh`'s preamble (before the Phase 1 gate). `lib/validate_env.sh` now sources it too, so it stays usable standalone. |
| 4.2 | `printf '\\033c'` printed literal text | Now `printf '\033c'` — a real terminal reset. |
| 5.1 | No `shellcheck` in the suite | New **round 1b** in `tests/verify_all.sh` (`-S warning`), which *skips* gracefully when shellcheck is absent so the suite still runs on-device. All 6 pre-existing warnings fixed; the tree is now shellcheck-clean. |
| 5.2 | No CI | **`.github/workflows/verify.yml`** installs shellcheck and runs `tests/verify_all.sh` on every push/PR. |
| 5.3 | Nothing executable | `core.sh` and the three test scripts are now mode `100755`. |

Pre-existing shellcheck warnings fixed along the way:

- `install_maintenance.sh:22` — **SC2115**, a genuine footgun: `rm -rf "$TDE_SHARE_DIR/lib"`
  would expand to `rm -rf /lib /components` if `TDE_SHARE_DIR` were ever empty (unset
  `PREFIX` in a future caller). Now `"${TDE_SHARE_DIR:?}/lib"`.
- `generate_report.sh` — SC2034: `TDE_AUDIT_HAD_CRITICAL_FAILURE` is exported, since its
  only reader (`phase5_print_summary`) lives in another file.
- `install_rootfs.sh:204` — unused `local line` removed.
- `test_pure_logic.sh` ×2 — SC2163: `export "${1?}"`.
- `verify_all.sh:25` — SC2044: `while IFS= read -r` over `find` instead of a word-split loop.

Suite after the fixes: **round clean, 133 unit checks** (up from 125), including 7 new
regression tests that reproduce 4.1 by sourcing *only* `core.sh`'s unconditional preamble
and then each interactive component, and assert 4.2's escape sequence byte-for-byte.

Items deliberately left alone: the `http://` mirrors (GPG-verified, mirrors do serve
http), `kv_get`'s empty-vs-absent conflation (no current caller stores `""`), the
hardcoded `TDE_LOCK_FD=200`, and the size of `test_pure_logic.sh` — all judgement calls,
none of them bugs.
