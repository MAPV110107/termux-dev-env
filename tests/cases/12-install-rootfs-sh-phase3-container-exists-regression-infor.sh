# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
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
