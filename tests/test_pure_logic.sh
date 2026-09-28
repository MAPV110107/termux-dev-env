#!/usr/bin/env bash
# Regression suite for logic that doesn't need a real Termux/proot
# environment: kv.sh, state.sh, idempotent_append.sh, username
# validation, compat_matrix, retry_with_backoff, and the proot version
# gate. Each of these was manually verified at least once during
# development after a real bug was found in it — this formalizes those
# checks so they don't silently regress on a future edit.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
export TDE_ROOT="$SCRIPT_DIR"
export TDE_DISTRO_NAME="archarm"

FAILURES=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  OK    $desc"
  else
    echo "  FAIL  $desc (expected [$expected], got [$actual])"
    FAILURES=$((FAILURES + 1))
  fi
}
assert_pass() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  OK    $desc"
  else
    echo "  FAIL  $desc (expected success, got failure)"
    FAILURES=$((FAILURES + 1))
  fi
}
assert_fail() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  FAIL  $desc (expected failure, got success)"
    FAILURES=$((FAILURES + 1))
  else
    echo "  OK    $desc"
  fi
}

TESTROOT="/tmp/pure_logic_test_$$"
rm -rf "$TESTROOT"
mkdir -p "$TESTROOT"
export HOME="$TESTROOT/home"
export PREFIX="$TESTROOT/usr"
mkdir -p "$HOME" "$PREFIX/bin"

source "$SCRIPT_DIR/lib/error_handling.sh"
source "$SCRIPT_DIR/lib/logging.sh"
log_init >/dev/null
source "$SCRIPT_DIR/lib/container_paths.sh"
source "$SCRIPT_DIR/lib/kv.sh"
export TDE_STATE_FILE="$TESTROOT/state.env"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/idempotent_append.sh"
source "$SCRIPT_DIR/lib/network.sh"
source "$SCRIPT_DIR/lib/compat_matrix.sh"
source "$SCRIPT_DIR/lib/validate_env.sh"
source "$SCRIPT_DIR/components/create_user.sh"

echo "=== kv.sh ==="
kv_set "$TESTROOT/kv.env" FOO bar
assert_eq "existing key" "bar" "$(kv_get "$TESTROOT/kv.env" FOO)"
assert_eq "missing key, no default" "" "$(kv_get "$TESTROOT/kv.env" MISSING)"
assert_eq "missing key, with default" "42" "$(kv_get "$TESTROOT/kv.env" MISSING 42)"
assert_pass "kv_get survives a missing key called directly (not just via \$())" \
  kv_get "$TESTROOT/kv.env" MISSING
kv_set "$TESTROOT/kv.env" FOO baz
assert_eq "overwrite replaces, no duplicate line" "1" "$(grep -c '^FOO=' "$TESTROOT/kv.env")"
kv_del "$TESTROOT/kv.env" FOO
assert_eq "kv_del removes key" "" "$(kv_get "$TESTROOT/kv.env" FOO)"

echo ""
echo "=== state.sh ==="
state_set PHASE1_DONE 1
assert_eq "state_set/get roundtrip" "1" "$(state_get PHASE1_DONE)"
TDE_DRY_RUN=1 state_set PHASE2_DONE 1
assert_eq "state_set no-ops under dry-run" "" "$(state_get PHASE2_DONE)"
state_set PHASE3_ROOTFS_INSTALLED 1
state_set PHASE3_DONE 1
state_set PHASE4_TOOLCHAIN 1
state_set ARCH_USERNAME "kattze"
state_del ARCH_USERNAME
assert_eq "state_del clears key" "" "$(state_get ARCH_USERNAME)"
state_clear_prefix "PHASE3"
assert_eq "state_clear_prefix removes only the targeted phase" "1" "$(state_get PHASE4_TOOLCHAIN)"
assert_eq "state_clear_prefix actually cleared it" "" "$(state_get PHASE3_DONE)"

echo ""
echo "=== idempotent_append.sh ==="
f="$TESTROOT/test.sh"
echo "existing content" > "$f"
idempotent_append "$f" "blk" "line one"
idempotent_append "$f" "blk" "line one"
idempotent_append "$f" "blk" "line one"
assert_eq "3x run stays idempotent (shell comment)" "1" "$(grep -c -- 'blk >>>' "$f")"
lf="$TESTROOT/test.lua"
echo "-- lua content" > "$lf"
idempotent_append "$lf" "opts" "vim.opt.x = 1" "--"
idempotent_append "$lf" "opts" "vim.opt.x = 1" "--"
assert_eq "idempotent with -- comment prefix" "1" "$(grep -c -- 'opts >>>' "$lf")"
assert_eq "no bare # lines leak into a lua file" "0" "$(grep -c '^#' "$lf")"

echo ""
echo "=== idempotent_append.sh (idempotent_append_container) ==="
# proot-distro login --user is mocked to just run the given command
# directly against a real fake $HOME on disk, standing in for "inside
# the container" — this asserts the function's own logic (marker
# dedup, --env passthrough of multi-line content) without needing a
# real proot-distro.
CONTAINER_HOME_TEST="$TESTROOT/container_home_test"
mkdir -p "$CONTAINER_HOME_TEST"
proot-distro() {
  # Drop "login DISTRO --user USER", actually export "--env NAME=VALUE"
  # pairs (idempotent_append_container's whole content passthrough
  # depends on these reaching the sh -c script as real env vars), then
  # run whatever follows "--".
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env) shift; export "$1"; shift ;;
      --) shift; break ;;
      *) shift ;;
    esac
  done
  HOME="$CONTAINER_HOME_TEST" "$@"
}
idempotent_append_container archarm kattze ".config/nvim/lua/config/options.lua" "options" "vim.opt.x = 1" "--"
idempotent_append_container archarm kattze ".config/nvim/lua/config/options.lua" "options" "vim.opt.x = 1" "--"
idempotent_append_container archarm kattze ".config/nvim/lua/config/options.lua" "options" "vim.opt.x = 1" "--"
assert_eq "idempotent_append_container stays idempotent across 3 calls" "1" \
  "$(grep -c -- 'options >>>' "$CONTAINER_HOME_TEST/.config/nvim/lua/config/options.lua")"
assert_eq "idempotent_append_container preserves multi-line content intact" "vim.opt.x = 1" \
  "$(grep 'vim.opt.x' "$CONTAINER_HOME_TEST/.config/nvim/lua/config/options.lua")"
unset -f proot-distro

echo ""
echo "=== network.sh (retry_with_backoff) ==="
attempt=0
flaky() { attempt=$((attempt + 1)); [ "$attempt" -ge 2 ]; }
assert_pass "succeeds within max attempts" retry_with_backoff 3 1 flaky
always_fail() { return 1; }
assert_fail "returns failure after exhausting attempts" retry_with_backoff 2 1 always_fail

echo ""
echo "=== compat_matrix.sh ==="
diag="$TESTROOT/diag.env"
kv_set "$diag" CPU_CORES 8
out="$(_compat_check "cores" "8" 4 8 2>&1)"
case "$out" in *"OK"*) echo "  OK    recommended value reports OK" ;; *) echo "  FAIL  recommended value"; FAILURES=$((FAILURES+1));; esac
out="$(_compat_check "cores" "" 4 8 2>&1)"
case "$out" in *"not available"*) echo "  OK    empty value handled without crashing" ;; *) echo "  FAIL  empty value"; FAILURES=$((FAILURES+1));; esac
out="$(_compat_check "api" "unknown" 24 29 2>&1)"
case "$out" in *"not available"*) echo "  OK    non-numeric value handled without crashing" ;; *) echo "  FAIL  non-numeric value"; FAILURES=$((FAILURES+1));; esac

echo ""
echo "=== validate_env.sh ==="
assert_eq "_prompt returns default under dry-run" "def" "$(TDE_DRY_RUN=1 _prompt 'never shown: ' def)"
assert_pass "proot version 5.x is accepted" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/validate_env.sh'
  proot() { echo 'proot version 5.4.0'; }
  phase1_check_proot_version
"
assert_fail "proot version 2.x is rejected" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/validate_env.sh'
  proot() { echo 'proot version 2.0.1'; }
  phase1_check_proot_version
"
assert_pass "unparseable proot version output doesn't crash" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/validate_env.sh'
  proot() { echo 'no digits here at all'; }
  phase1_check_proot_version
"

echo ""
echo "=== create_user.sh (username validation) ==="
for name in kattze user _test a1-2; do
  assert_pass "valid: $name" _username_is_valid "$name"
done
for name in root Root "with space" "" "123start"; do
  assert_fail "invalid/reserved: [$name]" _username_is_valid "$name"
done

echo ""
echo "=== create_user.sh (regression: password safety net + sudoers verification) ==="
# useradd never sets a password on its own — without this, an account is
# unauthenticatable via sudo if NOPASSWD ever doesn't take effect (seen
# in the wild: sudo still prompted despite the sudoers.d rule existing).
assert_pass "set_user_password skips prompting when a password is already set" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/create_user.sh'
  proot-distro() { case \"\$*\" in *'passwd -S'*) echo 'kattze P 2026-09-25 0 99999 7 -1' ;; *) echo 'SHOULD NOT RUN passwd itself' >&2; return 1 ;; esac; }
  phase3_set_user_password kattze
"
assert_pass "set_user_password does not prompt in dry-run" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  TDE_DISTRO_NAME=archarm
  TDE_DRY_RUN=1
  source '$SCRIPT_DIR/components/create_user.sh'
  proot-distro() { case \"\$*\" in *'passwd -S'*) echo 'kattze NP' ;; *) echo 'SHOULD NOT RUN passwd itself' >&2; return 1 ;; esac; }
  phase3_set_user_password kattze
"
# This test's own stdin isn't a TTY either (it runs under a test
# harness), which doubles as coverage for that exact guard: passwd
# needs a real TTY to hide input, so skip (warn, non-blocking) rather
# than let it fail or hang.
assert_pass "set_user_password skips (non-blocking) without a TTY, doesn't hang or abort" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/create_user.sh'
  proot-distro() { case \"\$*\" in *'passwd -S'*) echo 'kattze NP' ;; *) echo 'SHOULD NOT RUN passwd itself' >&2; return 1 ;; esac; }
  phase3_set_user_password kattze < /dev/null
"

# The bug the user actually hit: the sudoers.d write "succeeded" (no
# error) but sudo still prompted for a password. visudo -c catches a
# malformed sudoers.d file at write time instead of leaving a rule that
# looks written but silently never applies.
assert_pass "create_user_run's sudoers write adds @includedir when missing" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/create_user_state.env'
  TDE_DISTRO_NAME=archarm
  TDE_LOG_FILE='$TESTROOT/create_user_sudoers.log'; : > \"\$TDE_LOG_FILE\"
  source '$SCRIPT_DIR/components/create_user.sh'
  SUDOERS_SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'id -u'*) return 0 ;;
      *'usermod'*) return 0 ;;
      *'passwd -S'*) echo 'kattze P' ;;
      *'sh -c'*) SUDOERS_SEEN=\"\${*: -1}\"; return 0 ;;
      *) return 0 ;;
    esac
  }
  phase3_prompt_username() { echo kattze; }
  phase3_ensure_sudo_installed() { :; }
  phase3_create_user_run
  grep -q '@includedir /etc/sudoers.d' <<< \"\$SUDOERS_SEEN\"
"
assert_fail "create_user_run FATALs (not silent) when visudo reports a syntax problem" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/create_user_state2.env'
  TDE_DISTRO_NAME=archarm
  TDE_LOG_FILE='$TESTROOT/create_user_sudoers2.log'; : > \"\$TDE_LOG_FILE\"
  source '$SCRIPT_DIR/components/create_user.sh'
  proot-distro() {
    case \"\$*\" in
      *'id -u'*) return 0 ;;
      *'usermod'*) return 0 ;;
      *'passwd -S'*) echo 'kattze P' ;;
      *'sh -c'*) return 1 ;;  # simulates visudo -c failing
      *) return 0 ;;
    esac
  }
  phase3_prompt_username() { echo kattze; }
  phase3_ensure_sudo_installed() { :; }
  phase3_create_user_run
"

echo ""
echo "=== install_rootfs.sh (phase3_rootfs_ok with pacman-key/DisableSandbox) ==="
source "$SCRIPT_DIR/components/install_rootfs.sh"
rm -rf "$TDE_ROOTFS_PATH"
mkdir -p "$TDE_ROOTFS_PATH/etc"
proot-distro() {
  case "$*" in
    *"test -d /etc/pacman.d/gnupg"*) return 0 ;;
    *"grep -q ^DisableSandbox"*) return 0 ;;
    *) return 0 ;;
  esac
}
assert_pass "rootfs_ok passes when keyring+sandbox fix are both present" phase3_rootfs_ok
proot-distro() {
  case "$*" in
    *"test -d /etc/pacman.d/gnupg"*) return 0 ;;
    *"grep -q ^DisableSandbox"*) return 1 ;;
    *) return 0 ;;
  esac
}
assert_fail "rootfs_ok fails when DisableSandbox is missing" phase3_rootfs_ok

echo ""
echo "=== validate_env.sh / diagnose.sh (regression: informe 2026-09-23, df -m / bare mount fail on real Termux) ==="
# Termux's own coreutils package ships without df (confirmed against
# termux-packages/packages/coreutils/build.sh: "df does not work either,
# let system binary prevail"), so `df` on a real device is Android's
# toybox, which only understands -P/-k, not GNU's -m. These mocks mimic
# toybox's df -k column layout (Filesystem 1K-blocks Used Available
# Use% Mounted) to lock in that the KB->MB conversion is correct without
# needing an actual Termux device to test on.
assert_pass "phase1_check_free_space accepts toybox-style 'df -k' output above the minimum" bash -c "
  df() { echo 'Filesystem     1K-blocks    Used Available Use% Mounted on'; echo \"/dev/fake 8000000 1000000 7000000 13% \$1\"; }
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/validate_env.sh'
  PREFIX='$PREFIX'
  phase1_check_free_space
"
assert_fail "phase1_check_free_space still rejects toybox-style output below the minimum" bash -c "
  df() { echo 'Filesystem     1K-blocks    Used Available Use% Mounted on'; echo \"/dev/fake 8000000 7900000 100000 98% \$1\"; }
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/validate_env.sh'
  PREFIX='$PREFIX'
  phase1_check_free_space
"
assert_eq "diagnose_storage_free_mb converts toybox-style 'df -k' KB to MB" "6835" "$(bash -c "
  df() { echo 'Filesystem     1K-blocks    Used Available Use% Mounted on'; echo \"/dev/fake 8000000 1000000 7000000 13% \$1\"; }
  source '$SCRIPT_DIR/lib/error_handling.sh'
  PREFIX='$PREFIX'
  source '$SCRIPT_DIR/lib/diagnose.sh'
  diagnose_storage_free_mb
")"

# mount is not a Termux package (termux-packages#14495/#10207) and
# /system/bin is deliberately never on Termux's \$PATH — so a bare
# 'mount' call is "command not found" on a real device, not merely a
# formatting mismatch.
assert_eq "diagnose_fs_type extracts the fs type from a mocked mount listing on PATH" "ext4" "$(bash -c "
  mount() { echo \"/dev/fake on \$PREFIX type ext4 (rw,relatime)\"; }
  source '$SCRIPT_DIR/lib/error_handling.sh'
  PREFIX='$PREFIX'
  source '$SCRIPT_DIR/lib/diagnose.sh'
  diagnose_fs_type
")"
assert_pass "diagnose_fs_type does not abort the script (set -e) when mount is entirely missing" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'
  PREFIX='$PREFIX'
  PATH='/nonexistent'
  source '$SCRIPT_DIR/lib/diagnose.sh'
  out=\"\$(diagnose_fs_type)\"
  echo \"got: [\$out]\"
"

echo ""
echo "=== install_rootfs.sh (phase3_container_exists — regression: informe 2026-09-23, fragile 'proot-distro list' parsing) ==="
# Filesystem check is now primary, matching proot-distro's own definition
# of "installed" (upstream command_install() tests exactly this path —
# see lib/container_paths.sh for the verified INSTALLED_ROOTFS_DIR match).
rm -rf "$TDE_ROOTFS_PATH"
mkdir -p "$TDE_ROOTFS_PATH/etc"
proot-distro() { echo "SHOULD NOT BE CALLED" >&2; return 1; }
assert_pass "phase3_container_exists trusts the filesystem, never even calling proot-distro" phase3_container_exists
rm -rf "$TDE_ROOTFS_PATH"

# No rootfs on disk yet, but 'proot-distro list -q' (script-friendly mode:
# one alias per line, no table/color formatting) reports it — still counts.
proot-distro() {
  case "$*" in
    "list -q") echo "archarm" ;;
    *) return 1 ;;
  esac
}
assert_pass "phase3_container_exists falls back to 'proot-distro list -q'" phase3_container_exists

# The bug from the report: the *old* code parsed plain 'proot-distro list'
# with awk '{print $1}', which breaks on a distro/alias table header, an
# install-marker '*' prefix, or ANSI color codes. Simulate exactly that
# kind of output on 'list' while 'list -q' (never consulted by the old
# code) correctly has nothing — login still proves the container is real.
proot-distro() {
  case "$*" in
    "list") echo "* archarm    installed"; return 0 ;;  # old code's $1 would be '*', not 'archarm'
    "list -q") return 1 ;;
    "login archarm -- true") return 0 ;;
    *) return 1 ;;
  esac
}
assert_pass "phase3_container_exists falls back to a working login when list -q misses" phase3_container_exists

proot-distro() { return 1; }  # nothing on disk, not listed, login fails too
assert_fail "phase3_container_exists correctly reports absence when nothing confirms it" phase3_container_exists

# The bug from the informe técnico (2026-09-22): sed -i "/pattern/a text"
# exits 0 even when the pattern never matches, so the old code could
# reach "installed and verified" while DisableSandbox silently never
# landed. This locks in that phase3_rootfs_ok actually notices that,
# once the container itself is confirmed present on disk.
mkdir -p "$TDE_ROOTFS_PATH/etc"
proot-distro() {
  case "$*" in
    *"test -d /etc/pacman.d/gnupg"*) return 0 ;;
    *"grep -q ^DisableSandbox"*) return 1 ;;  # sed silently didn't insert it
    *) return 0 ;;
  esac
}
out="$(phase3_rootfs_ok 2>&1 || true)"
assert_fail "rootfs_ok still fails when DisableSandbox silently didn't land" phase3_rootfs_ok
case "$out" in
  *"DisableSandbox missing"*) echo "  OK    post-check names DisableSandbox specifically, not a bare failure" ;;
  *) echo "  FAIL  post-check did not name which sub-check failed"; FAILURES=$((FAILURES+1)) ;;
esac
rm -rf "$TDE_ROOTFS_PATH"

# phase3_disable_pacman_sandbox must re-check the file, not trust sed's
# exit code — confirm it retries and then fails loud (not a silent warn)
# when the insert never actually takes.
TDE_LOG_FILE="$TESTROOT/rootfs_sandbox.log"
: > "$TDE_LOG_FILE"
assert_fail "disable_pacman_sandbox goes fatal (not just warn) when the file never actually gets fixed" \
  bash -c "
    source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
    TDE_DISTRO_NAME=archarm
    TDE_LOG_FILE='$TDE_LOG_FILE'
    source '$SCRIPT_DIR/components/install_rootfs.sh'
    # 'sh -c ...' is the edit attempt (mimics sed exiting 0 even though it
    # inserted nothing, per the report); the separate 'grep -q' call is the
    # verification, which must be what actually decides pass/fail here.
    proot-distro() {
      case \"\$*\" in
        *'sh -c'*) return 0 ;;
        *'grep -q ^DisableSandbox'*) return 1 ;;
        *) return 0 ;;
      esac
    }
    phase3_disable_pacman_sandbox
  "
ATTEMPTS_LOGGED="$(grep -c "still missing after attempt" "$TDE_LOG_FILE" 2>/dev/null || echo 0)"
assert_eq "disable_pacman_sandbox actually retries 3 times before giving up" "3" "$ATTEMPTS_LOGGED"

echo ""
echo "=== install_rootfs.sh (already-registered container skips re-download) ==="
assert_pass "install_rootfs_run does not attempt gpg/import/download when the container already exists" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/network.sh'
  PREFIX='$PREFIX'
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/lib/container_paths.sh'
  mkdir -p \"\$TDE_ROOTFS_PATH/etc\"
  source '$SCRIPT_DIR/components/install_rootfs.sh'
  proot-distro() {
    case \"\$*\" in
      *\"grep -q ^DisableSandbox\"*) return 0 ;;
      *) return 0 ;;
    esac
  }
  phase3_install_gpg_tool() { echo 'SHOULD NOT BE CALLED' >&2; exit 1; }
  phase3_download_and_verify() { echo 'SHOULD NOT BE CALLED' >&2; exit 1; }
  phase3_install_rootfs_run
"

echo ""
echo "=== lazyvim.sh (regression: informe 2026-09-25, TSInstallSync obsolete / host-side checks) ==="
# TSInstallSync belonged to nvim-treesitter's frozen 'master' branch;
# LazyVim's starter pins 'main', which removed it entirely
# ("E492: Not an editor command: TSInstallSync") — confirmed against
# nvim-treesitter/LazyVim's own current docs. Locks in the modern Lua
# API is what's actually sent to nvim, not the old ex-command.
assert_pass "install_treesitter_parsers uses the modern Lua API, not TSInstallSync" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  SEEN=''
  proot-distro() { SEEN=\"\$*\"; return 0; }
  phase4_install_treesitter_parsers
  ! grep -q 'TSInstallSync' <<< \"\$SEEN\" && grep -q \"require('nvim-treesitter').install\" <<< \"\$SEEN\"
"
# checkhealth's own wording is nvim-treesitter's UI copy, free to change
# across versions (and did, moving 'master' -> 'main') — this checks
# for the compiler directly instead of grepping that text.
assert_pass "verify_treesitter_cc checks for gcc/cc directly, not checkhealth text" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  proot-distro() { case \"\$*\" in *'command -v gcc'*) return 0 ;; *) return 1 ;; esac; }
  phase4_verify_treesitter_cc
"
# The bug: the old idempotency check for the LazyVim starter clone was a
# host-side path via container_home — a false negative there (the same
# class of bug as .zshrc) fell through to 'rm -rf' the whole nvim config
# and re-clone from scratch, which would silently destroy a user's own
# customizations on every single run. Confirms the check and the
# destructive rm both now go through the container, not a host path.
assert_pass "clone_lazyvim_starter skips (no destructive rm, no re-clone) when already present and clean" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  proot-distro() {
    case \"\$*\" in
      *'sh -c'*) return 0 ;;  # combined [-d nvim] && [!-d .git] && [!-f example.lua] check: clean
      *'rm -rf'*) echo 'SHOULD NOT DELETE' >&2; return 1 ;;
      *'git clone'*) echo 'SHOULD NOT RE-CLONE' >&2; return 1 ;;
      *) return 0 ;;
    esac
  }
  phase4_clone_lazyvim_starter
"
assert_pass "lazyvim_ok checks options.lua container-side, not a host-side container_home path" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  proot-distro() {
    case \"\$*\" in
      *'test -f'*'options.lua'*) return 0 ;;
      *'lua print'*) echo 12 ;;
      *'command -v nvim'*) return 0 ;;
      *) return 0 ;;
    esac
  }
  phase4_lazyvim_ok
"
assert_fail "lazyvim_ok still fails when options.lua is missing container-side" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  proot-distro() { case \"\$*\" in *'test -f'*'options.lua'*) return 1 ;; *) return 0 ;; esac; }
  phase4_lazyvim_ok
"
assert_pass "write_options_overrides uses idempotent_append_container, not a host-side path" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'; source '$SCRIPT_DIR/lib/idempotent_append.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  LOGGED_IN=0
  proot-distro() { LOGGED_IN=1; return 0; }
  phase4_write_options_overrides
  [ \"\$LOGGED_IN\" = 1 ]
"

echo ""
echo "=== dev_toolchain.sh (paru.conf written container-side; regression: informe 2026-09-25) ==="
assert_pass "write_paru_conf writes container-side, not a host-side container_home path" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  LOGGED_IN=0
  proot-distro() { LOGGED_IN=1; return 0; }
  phase4_write_paru_conf
  [ \"\$LOGGED_IN\" = 1 ]
"

echo ""
echo "=== cleanup.sh (regression: informe 2026-09-25, paru-bin deleted before it could be retried) ==="
# The bug: phase5_cleanup deleted /tmp/paru-bin whenever
# phase4_toolchain_ok passed — which only requires gcc+git since paru
# became non-blocking, so it deleted the build directory even when
# paru's OWN build/install had failed, wiping out exactly what
# TROUBLESHOOTING.md tells people to retry from.
assert_pass "cleanup does NOT delete /tmp/paru-bin when paru itself isn't actually installed" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  TDE_ROOTFS_TMPDIR='$TESTROOT/nonexistent_rootfs_tmp'
  TDE_NERDFONT_TMPDIR='$TESTROOT/nonexistent_nerdfont_tmp'
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/lib/cleanup.sh'
  phase4_toolchain_ok() { return 0; }   # gcc+git fine
  phase5_nerdfont_ok() { return 0; }
  phase3_rootfs_ok() { return 0; }
  proot-distro() {
    case \"\$*\" in
      *'command -v paru'*) return 1 ;;   # paru itself never actually got installed
      *'rm -rf /tmp/paru-bin'*) echo 'SHOULD NOT DELETE /tmp/paru-bin' >&2; return 1 ;;
      *) return 0 ;;
    esac
  }
  phase5_cleanup
"
assert_pass "cleanup DOES delete /tmp/paru-bin once paru is actually present" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  TDE_ROOTFS_TMPDIR='$TESTROOT/nonexistent_rootfs_tmp2'
  TDE_NERDFONT_TMPDIR='$TESTROOT/nonexistent_nerdfont_tmp2'
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/lib/cleanup.sh'
  phase4_toolchain_ok() { return 0; }
  phase5_nerdfont_ok() { return 0; }
  phase3_rootfs_ok() { return 0; }
  DELETED=0
  proot-distro() {
    case \"\$*\" in
      *'command -v paru'*) return 0 ;;
      *'rm -rf /tmp/paru-bin'*) DELETED=1; return 0 ;;
      *) return 0 ;;
    esac
  }
  phase5_cleanup
  [ \"\$DELETED\" = 1 ]
"

echo ""
echo "=== install_maintenance.sh (regression: informe 2026-09-25, archhealth/archdiag missing sources for self-heal) ==="
assert_pass "archhealth sources network.sh, idempotent_append.sh, telecom.sh, nerdfonts.sh (needed by phase5_self_heal)" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export PREFIX='$TESTROOT/maint_prefix1'; mkdir -p \"\$PREFIX/bin\"
  source '$SCRIPT_DIR/components/install_maintenance.sh'
  phase6_write_archhealth
  grep -q '^source lib/network.sh' \"\$PREFIX/bin/archhealth\" &&
  grep -q '^source lib/idempotent_append.sh' \"\$PREFIX/bin/archhealth\" &&
  grep -q '^source components/telecom.sh' \"\$PREFIX/bin/archhealth\" &&
  grep -q '^source components/nerdfonts.sh' \"\$PREFIX/bin/archhealth\"
"
assert_pass "archdiag sources network.sh, idempotent_append.sh, telecom.sh, nerdfonts.sh (needed by phase5_self_heal)" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export PREFIX='$TESTROOT/maint_prefix2'; mkdir -p \"\$PREFIX/bin\"
  source '$SCRIPT_DIR/components/install_maintenance.sh'
  phase6_write_archdiag
  grep -q '^source lib/network.sh' \"\$PREFIX/bin/archdiag\" &&
  grep -q '^source lib/idempotent_append.sh' \"\$PREFIX/bin/archdiag\" &&
  grep -q '^source components/telecom.sh' \"\$PREFIX/bin/archdiag\" &&
  grep -q '^source components/nerdfonts.sh' \"\$PREFIX/bin/archdiag\"
"
assert_pass "archupdate retries pacman -Syu instead of a single unguarded attempt" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export PREFIX='$TESTROOT/maint_prefix3'; mkdir -p \"\$PREFIX/bin\"
  source '$SCRIPT_DIR/components/install_maintenance.sh'
  phase6_write_archupdate
  grep -q 'retry_with_backoff' \"\$PREFIX/bin/archupdate\" && grep -q '^source lib/network.sh' \"\$PREFIX/bin/archupdate\"
"
assert_pass "archhealth, archdiag, archupdate all still generate with valid bash syntax" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export PREFIX='$TESTROOT/maint_prefix4'; mkdir -p \"\$PREFIX/bin\"
  source '$SCRIPT_DIR/components/install_maintenance.sh'
  phase6_write_archhealth; phase6_write_archdiag; phase6_write_archupdate
  bash -n \"\$PREFIX/bin/archhealth\" && bash -n \"\$PREFIX/bin/archdiag\" && bash -n \"\$PREFIX/bin/archupdate\"
"

echo ""
echo "=== regression: bare '~/path' expands against THIS shell's \$HOME, not the container user's ==="
# The actual bug hit in the wild: 'proot-distro login ... --user X -- tee
# ~/path' looks like it targets the container user's home, but tilde
# expansion happens in the CALLING (Termux-side) shell BEFORE
# proot-distro ever runs — so an unquoted ~/path silently resolves
# against THIS process's own $HOME, not the container's. Every function
# below is asserted with $HOME deliberately set to something that must
# NEVER appear in what reaches proot-distro; only sh -c '...ARGS WITH ~...'
# (protected by single quotes, expanded remotely instead) or an absolute
# /home/<user>/... path is safe.
export HOME="$TESTROOT/host_home_should_never_be_used"
mkdir -p "$HOME"

assert_pass "install_ohmyzsh's .zshrc-repair check never leaks the host \$HOME" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'; source '$SCRIPT_DIR/lib/network.sh'
  export HOME='$HOME'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'&&'*) return 1 ;;
      *'bash -c'*) return 0 ;;
      *'test -f'*) SEEN=\"\$*\"; return 1 ;;
      *) return 0 ;;
    esac
  }
  phase4_install_ohmyzsh 2>/dev/null
  ! grep -qF \"\$HOME\" <<< \"\$SEEN\" && grep -q '/home/kattze/.zshrc' <<< \"\$SEEN\"
"
assert_pass "set_zsh_theme's sed target never leaks the host \$HOME" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export HOME='$HOME'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'test -f'*) return 0 ;;
      *'sh -c'*) SEEN=\"\${*: -1}\"; return 0 ;;
      *) return 0 ;;
    esac
  }
  phase4_set_zsh_theme
  ! grep -qF \"\$HOME\" <<< \"\$SEEN\"
"
assert_pass "shell_ok's ZSH_THEME grep never leaks the host \$HOME" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export HOME='$HOME'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'getent passwd'*) echo 'kattze:x:1000:1000::/home/kattze:/usr/bin/zsh' ;;
      *'test -f'*) return 0 ;;
      *'sh -c'*) SEEN=\"\${*: -1}\"; return 0 ;;
      *) return 0 ;;
    esac
  }
  phase4_shell_ok
  ! grep -qF \"\$HOME\" <<< \"\$SEEN\"
"
assert_pass "clone_lazyvim_starter's cleanup rm never leaks the host \$HOME" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export HOME='$HOME'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'sh -c'*'[ -d'*) return 1 ;;             # not-clean check specifically
      *'sh -c'*) return 0 ;;                    # the (protected) cleanup rm -rf .git — not under test here
      *'rm -rf'*) SEEN=\"\$*\"; return 0 ;;       # the bare, direct rm -rf — this is what's under test
      *) return 0 ;;
    esac
  }
  phase4_clone_lazyvim_starter
  ! grep -qF \"\$HOME\" <<< \"\$SEEN\" && grep -q '/home/kattze/.config/nvim' <<< \"\$SEEN\"
"
assert_pass "write_plugin_overrides' tee targets never leak the host \$HOME" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export HOME='$HOME'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'tee'*) SEEN=\"\${SEEN} \$*\" ;;
    esac
    return 0
  }
  phase4_write_plugin_overrides < /dev/null
  ! grep -qF \"\$HOME\" <<< \"\$SEEN\" && grep -q '/home/kattze/.config/nvim/lua/plugins/lsp.lua' <<< \"\$SEEN\"
"
assert_pass "lazyvim_ok's options.lua check never leaks the host \$HOME" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export HOME='$HOME'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/lazyvim.sh'
  SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'test -f'*) SEEN=\"\$*\"; return 0 ;;
      *'lua print'*) echo 5 ;;
      *) return 0 ;;
    esac
  }
  phase4_lazyvim_ok
  ! grep -qF \"\$HOME\" <<< \"\$SEEN\" && grep -q '/home/kattze/.config/nvim/lua/config/options.lua' <<< \"\$SEEN\"
"
assert_pass "write_paru_conf's tee target never leaks the host \$HOME" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export HOME='$HOME'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  SEEN=''
  proot-distro() {
    case \"\$*\" in
      *'tee'*) SEEN=\"\$*\" ;;
    esac
    return 0
  }
  phase4_write_paru_conf < /dev/null
  ! grep -qF \"\$HOME\" <<< \"\$SEEN\" && grep -q '/home/kattze/.config/paru/paru.conf' <<< \"\$SEEN\"
"
unset HOME
export HOME="$TESTROOT/home"

echo ""
echo "=== dev_toolchain.sh (git defaults, non-blocking) ==="
assert_pass "git_defaults never aborts the phase, even if git config fails" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/gitdef_state.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  proot-distro() { return 1; }
  phase4_git_defaults
"

echo ""
echo "=== logging.sh (log_fatal_code) ==="
assert_fail "log_fatal_code aborts with a nonzero exit" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'
  export TDE_CONFIG_DIR='$TESTROOT/errcode_cfg'; TDE_LOG_DIR='$TESTROOT/errcode_cfg/logs'
  mkdir -p \"\$TDE_CONFIG_DIR\"
  log_fatal_code 999 'boom' >/dev/null
"
assert_pass "log_fatal_code tags the message and writes last_error.env" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'
  TDE_CONFIG_DIR='$TESTROOT/errcode_cfg2'; mkdir -p \"\$TDE_CONFIG_DIR\"
  out=\"\$( (log_fatal_code 321 'useradd failed') 2>&1 || true)\"
  grep -q '\[E321\] useradd failed' <<< \"\$out\" &&
  grep -q '^CODE=E321' \"\$TDE_CONFIG_DIR/last_error.env\"
"
# Every E-code in the source must be documented in docs/ERROR_CODES.md.
assert_pass "every log_fatal_code used in the source is documented in ERROR_CODES.md" bash -c "
  cd '$SCRIPT_DIR'
  for c in \$(grep -rhoE 'log_fatal_code [0-9]+' core.sh components lib | awk '{print \$2}' | sort -u); do
    grep -q \"E\$c\" docs/ERROR_CODES.md || { echo \"undocumented: E\$c\" >&2; exit 1; }
  done
"

echo ""
echo "=== install_maintenance.sh (archbridge) ==="
source "$SCRIPT_DIR/components/install_maintenance.sh"
phase6_write_archbridge
assert_pass "archbridge is generated with valid syntax" bash -n "$PREFIX/bin/archbridge"
assert_eq "archbridge is executable" "yes" "$([ -x "$PREFIX/bin/archbridge" ] && echo yes)"

echo ""
echo "=== install_rootfs.sh (TDE_ROOTFS_URL_OVERRIDE pinning) ==="
TDE_ROOTFS_TARBALL="$TESTROOT/pinned.tar.gz"
TDE_ROOTFS_SIG="$TESTROOT/pinned.tar.gz.sig"
export TDE_ROOTFS_TARBALL TDE_ROOTFS_SIG
curl() { touch "$3"; return 0; }
gpg() { return 0; }
TDE_ROOTFS_URL_OVERRIDE="https://example.com/verified.tar.gz" assert_pass \
  "pinned override is used and verified when set" phase3_download_and_verify
unset TDE_ROOTFS_URL_OVERRIDE

echo ""
echo "=== install_rootfs.sh / dev_toolchain.sh (regression: informe 2026-09-24, mirror timeouts / mkinitcpio noise) ==="
proot-distro() { return 0; }
assert_pass "phase3_write_pacman_mirrorlist writes one Server line per TDE_ARM_MIRRORS entry" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/install_rootfs.sh'
  WRITTEN=''
  proot-distro() {
    case \"\$*\" in
      *'sh -c'*) WRITTEN=\"\${*: -1}\" ;;
    esac
  }
  phase3_write_pacman_mirrorlist
  [ \"\$(grep -c '^Server = http://' <<< \"\$WRITTEN\")\" = \"\${#TDE_ARM_MIRRORS[@]}\" ]
"
assert_pass "phase3_write_pacman_mirrorlist doesn't abort the run if the write fails (best-effort)" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/install_rootfs.sh'
  proot-distro() { return 1; }
  phase3_write_pacman_mirrorlist
"
assert_pass "phase3_ignore_kernel_pkg doesn't abort the run if the write fails (best-effort)" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/install_rootfs.sh'
  proot-distro() { return 1; }
  phase3_ignore_kernel_pkg
"
# The bug from the report: a single transient DNS/timeout blip against
# mirror.archlinuxarm.org (the tarball's single default mirror) took the
# whole toolchain phase down with no retry at all.
assert_pass "phase4_sync_and_install_toolchain retries pacman -Syu on a transient failure" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/network.sh'
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  ATTEMPT=0
  proot-distro() {
    case \"\$*\" in
      *'pacman -Syu'*)
        ATTEMPT=\$((ATTEMPT + 1))
        [ \"\$ATTEMPT\" -ge 2 ]  # fails once, then succeeds — simulates a transient timeout
        ;;
      *'pacman -S'*) return 0 ;;
      *) return 0 ;;
    esac
  }
  phase4_sync_and_install_toolchain
"
assert_fail "phase4_sync_and_install_toolchain still fails after exhausting retries, with an actionable message" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/network.sh'
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  proot-distro() { case \"\$*\" in *'pacman -Syu'*) return 1 ;; *) return 0 ;; esac; }
  phase4_sync_and_install_toolchain 2>&1 | grep -q 'network/mirror issue'
"

echo ""
echo "=== shell_setup.sh (regression: informe 2026-09-23, tmux auto-attach hangs scripted logins) ==="
# zsh only sets its own "interactive" option off for a "-c command"
# invocation — regardless of whether a TTY happens to be attached to
# that process, which is why checking '-o interactive' (not just '-t 0')
# is what actually distinguishes a real interactive login from one of
# the many 'proot-distro login --user <name> -- <cmd>' calls every
# phase 4-6 step makes to run something inside the container. '-o
# interactive' is portable shell-option syntax (same semantics in bash),
# so bash stands in here for a real container zsh, which this sandbox
# doesn't have installed.
source "$SCRIPT_DIR/lib/idempotent_append.sh"
# Written via the real phase4_write_zshrc_extras (not a hand-copied
# snippet) so this can't silently drift from the actual code — the
# mocked proot-distro stands in for the container, same pattern as the
# idempotent_append_container test above.
ZSHRC_TEST="$TESTROOT/zshrc_snippet_test2"
mkdir -p "$ZSHRC_TEST"
proot-distro() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env) shift; export "$1"; shift ;;
      --) shift; break ;;
      *) shift ;;
    esac
  done
  HOME="$ZSHRC_TEST" "$@"
}
(
  source "$SCRIPT_DIR/lib/error_handling.sh"; source "$SCRIPT_DIR/lib/logging.sh"; log_init >/dev/null
  source "$SCRIPT_DIR/lib/kv.sh"; source "$SCRIPT_DIR/lib/state.sh"
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source "$SCRIPT_DIR/components/shell_setup.sh"
  phase4_write_zshrc_extras
) >/dev/null 2>&1
unset -f proot-distro
assert_pass "a scripted non-interactive shell -c login does not try to run tmux or fastfetch" \
  bash -c "tmux() { echo 'TMUX SHOULD NOT RUN' >&2; exit 1; }; fastfetch() { echo 'FASTFETCH SHOULD NOT RUN' >&2; exit 1; }; source '$ZSHRC_TEST/.zshrc'; true"
assert_eq "fastfetch is guarded the same way as tmux (interactive + TTY)" "2" \
  "$(grep -c '\[\[ -o interactive \]\] && \[ -t 0 \]' "$ZSHRC_TEST/.zshrc")"

echo ""
echo "=== shell_setup.sh (regression: reporte 2026-09-25, host-side .zshrc checks disagreed with what proot actually wrote) ==="
# The bug: oh-my-zsh's own installer reported "adding it to
# /home/<user>/.zshrc" and exited successfully, yet a direct host-side
# `[ -f "$(container_home ...)/.zshrc" ]` right after still read the
# file as missing — so a previous fix that only made the check "safe"
# (warn instead of crash) still left the underlying disagreement, and
# every later step kept treating a real .zshrc as absent. All the
# checks below now go through the same access path as the write
# (proot-distro login --user), not a host-side path into the rootfs.
assert_pass "install_ohmyzsh re-runs (does not skip) when .oh-my-zsh exists but .zshrc doesn't, checked container-side" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'; source '$SCRIPT_DIR/lib/network.sh'
  export TDE_STATE_FILE='$TESTROOT/ohmyzsh_state.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  INSTALLER_RAN=0
  proot-distro() {
    case \"\$*\" in
      *'&&'*'.zshrc'*) return 1 ;;              # combined [-d .oh-my-zsh] && [-f .zshrc] check: not both present
      *'test -d'*'.oh-my-zsh'*) return 0 ;;     # dir-only check: exists
      *'bash -c'*) INSTALLER_RAN=1; return 0 ;; # the actual (re-)install run
      *'test -f'*'.zshrc'*) return 0 ;;         # post-install check: now exists, no fallback needed
      *) return 0 ;;
    esac
  }
  phase4_install_ohmyzsh
  [ \"\$INSTALLER_RAN\" = 1 ]
"
assert_pass "enable_autosuggestions_plugin warns and skips instead of erroring on a missing .zshrc, checked container-side" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ohmyzsh_state2.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  proot-distro() { case \"\$*\" in *'test -f'*'.zshrc'*) return 1 ;; *) echo 'SHOULD NOT RUN sed' >&2; return 1 ;; esac; }
  phase4_enable_autosuggestions_plugin
"
assert_pass "set_zsh_theme warns and skips instead of erroring on a missing .zshrc, checked container-side" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ohmyzsh_state3.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  proot-distro() { case \"\$*\" in *'test -f'*'.zshrc'*) return 1 ;; *) echo 'SHOULD NOT RUN sed' >&2; return 1 ;; esac; }
  phase4_set_zsh_theme
"
assert_pass "enable_autosuggestions_plugin and set_zsh_theme actually edit .zshrc container-side when it exists" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ohmyzsh_state5.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  SED_RAN=0
  proot-distro() {
    case \"\$*\" in
      *'test -f'*'.zshrc'*) return 0 ;;
      *'sh -c'*) SED_RAN=1; return 0 ;;
      *'sed -i'*) SED_RAN=1; return 0 ;;
      *) return 0 ;;
    esac
  }
  phase4_enable_autosuggestions_plugin
  phase4_set_zsh_theme
  [ \"\$SED_RAN\" = 1 ]
"
assert_fail "shell_ok reports which sub-check failed instead of a bare failure" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  export TDE_STATE_FILE='$TESTROOT/ohmyzsh_state4.env'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/shell_setup.sh'
  proot-distro() { case \"\$*\" in *'getent passwd'*) echo 'kattze:x:1000:1000::/home/kattze:/bin/bash' ;; *) return 0 ;; esac; }
  out=\"\$(phase4_shell_ok 2>&1 || true)\"
  grep -q 'not /usr/bin/zsh' <<< \"\$out\"
  phase4_shell_ok
"

echo ""
echo "=== dev_toolchain.sh (paru install builds then installs as root, never needs sudo; regression: reporte 2026-09-25) ==="
assert_pass "install_paru builds with makepkg -s (no -i) as the user" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  BUILD_CMD=''
  proot-distro() {
    case \"\$*\" in
      *'command -v paru'*) return 1 ;;
      *'command -v makepkg'*) return 0 ;;
      *'--user'*'bash -c'*) BUILD_CMD=\"\${*: -1}\"; return 0 ;;
      *'bash -c'*) return 0 ;;  # the root install-as-pacman-U step
      *) return 0 ;;
    esac
  }
  phase4_install_paru
  ! grep -q -- '-si ' <<< \"\$BUILD_CMD\" && grep -q -- '-s --noconfirm' <<< \"\$BUILD_CMD\"
"
assert_pass "install_paru installs the built package as root via pacman -U, not sudo" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  ROOT_INSTALL_CMD=''
  proot-distro() {
    case \"\$*\" in
      *'command -v paru'*) return 1 ;;
      *'command -v makepkg'*) return 0 ;;
      *'--user'*'bash -c'*) return 0 ;;  # build step, as the user
      *'bash -c'*) ROOT_INSTALL_CMD=\"\${*: -1}\"; return 0 ;;  # root install step
      *) return 0 ;;
    esac
  }
  phase4_install_paru
  grep -q 'pacman -U' <<< \"\$ROOT_INSTALL_CMD\" && ! grep -q sudo <<< \"\$ROOT_INSTALL_CMD\"
"

echo ""
echo "=== dev_toolchain.sh (makepkg guard before paru install; regression: Grok analysis 2026-09-24, marksman/paru hard-fail) ==="
assert_fail "install_paru fails (non-fatal) when makepkg is missing" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  proot-distro() {
    case \"\$*\" in
      *'command -v paru'*) return 1 ;;
      *'command -v makepkg'*) return 1 ;;
      *) return 0 ;;
    esac
  }
  phase4_install_paru
"
# The bug from the report: phase4_install_paru used to call log_fatal
# directly on a failed makepkg/git-clone, and was invoked as a bare
# top-level statement — under this project's set -euo pipefail, that
# combination takes the whole installer down over a missing AUR helper,
# even though paru was never required by anything else in the toolchain.
assert_pass "dev_toolchain_run does not abort the whole phase when paru install fails" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/network.sh'; source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  proot-distro() {
    case \"\$*\" in
      *'command -v paru'*) return 1 ;;
      *'command -v makepkg'*) return 0 ;;
      *'bash -c'*) return 1 ;;  # simulates a failed git clone / makepkg -si
      *) return 0 ;;
    esac
  }
  phase4_sync_and_install_toolchain() { :; }
  phase4_prompt_git_identity() { :; }
  phase4_write_paru_conf() { :; }
  phase4_dev_toolchain_run
"
# marksman is upstream-Arch's own x86_64-specific package (not "any"),
# with no confirmed aarch64 build — a hard 'pacman -S ... marksman' turns
# a missing-on-this-arch package into a FATAL that kills the whole
# toolchain phase. Mason.nvim's own ensure_installed already gets it.
assert_pass "marksman is not a hard pacman dependency (Mason.nvim installs it instead)" bash -c "
  ! grep -q 'marksman' <<< \"\$(grep 'pacman -S' '$SCRIPT_DIR/components/dev_toolchain.sh')\"
"
# paru is genuinely optional — the toolchain post-check must not fail
# the entire phase over an AUR helper nothing else in the pipeline needs.
assert_pass "phase4_toolchain_ok passes on gcc+git alone, without requiring paru" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  TDE_DISTRO_NAME=archarm
  export TDE_STATE_FILE='$TESTROOT/toolchain_ok_state.env'
  state_set ARCH_USERNAME devuser >/dev/null
  source '$SCRIPT_DIR/components/dev_toolchain.sh'
  proot-distro() {
    case \"\$*\" in
      *'command -v gcc'*) return 0 ;;
      *'command -v git'*) return 0 ;;
      *'command -v paru'*) return 1 ;;
      *) return 0 ;;
    esac
  }
  phase4_toolchain_ok
"

echo ""
echo "=== install_maintenance.sh (archbridge StrictHostKeyChecking) ==="
phase6_write_archbridge
assert_pass "archbridge sets StrictHostKeyChecking=accept-new" \
  bash -c "grep -q 'StrictHostKeyChecking=accept-new' '$PREFIX/bin/archbridge'"

echo ""
echo "=== lock.sh (real-device bug: bare /tmp not guaranteed in Termux) ==="
assert_pass "lock_acquire works without a real /tmp, using \$PREFIX/tmp" bash -c "
  export PREFIX='$TESTROOT/usr'
  unset TMPDIR
  source '$SCRIPT_DIR/lib/error_handling.sh'
  source '$SCRIPT_DIR/lib/lock.sh'
  lock_acquire
  [ -f \"\$TDE_LOCK_FILE\" ]
"
assert_pass "lock.sh loads safely when PREFIX and TMPDIR are unset" bash -c "
  unset PREFIX
  unset TMPDIR
  source '$SCRIPT_DIR/lib/error_handling.sh'
  source '$SCRIPT_DIR/lib/lock.sh'
"

echo ""
echo "================================================"
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
else
  echo "$FAILURES CHECK(S) FAILED"
fi
echo "================================================"
rm -rf "$TESTROOT"
exit "$FAILURES"
