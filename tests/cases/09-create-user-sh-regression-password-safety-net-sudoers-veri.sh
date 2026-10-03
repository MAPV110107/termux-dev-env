# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
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
