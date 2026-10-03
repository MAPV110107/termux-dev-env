# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
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
