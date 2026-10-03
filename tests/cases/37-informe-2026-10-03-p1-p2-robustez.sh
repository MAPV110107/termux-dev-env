# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== informe 2026-10-03 P1: telecom, lock, env limits, self-heal ==="

# --- 3.1 telecom is still opt-in, but no longer silently so ---
TELE="$TESTROOT/telecom"; mkdir -p "$TELE"
# Each assertion gets its own state file: these run in the same
# $TESTROOT, and a recorded TELECOM_WANTED from one assert would
# otherwise decide the outcome of the next one.
_telecom_env() {
  echo "
    export HOME='$TELE' PREFIX='$TELE/usr' TDE_DISTRO_NAME=archarm
    export TDE_STATE_FILE='$TELE/state_shared.env'
    source '$SCRIPT_DIR/lib/error_handling.sh'
    source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
    source '$SCRIPT_DIR/lib/prompt.sh'
    source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'; state_init
    source '$SCRIPT_DIR/lib/container_paths.sh'
    source '$SCRIPT_DIR/components/telecom.sh'
  "
}
assert_pass "TDE_WITH_TELECOM=1 still selects telecom" bash -c "$(_telecom_env)
  TDE_WITH_TELECOM=1 phase4_telecom_wanted"
assert_fail "TDE_SKIP_TELECOM=1 wins over everything" bash -c "$(_telecom_env)
  TDE_WITH_TELECOM=1 TDE_SKIP_TELECOM=1 phase4_telecom_wanted"
assert_fail "a non-interactive run without a preference skips telecom" bash -c "$(_telecom_env)
  export TDE_STATE_FILE=\"$TELE/state_noninter_\$\$.env\"; state_init
  phase4_telecom_wanted < /dev/null"
assert_pass "a non-interactive skip is loud, not a single buried log line" bash -c "$(_telecom_env)
  export TDE_STATE_FILE=\"$TELE/state_loud_\$\$.env\"; state_init
  out=\"\$(phase4_telecom_wanted < /dev/null 2>&1 || true)\"
  grep -q 'TDE_WITH_TELECOM=1' <<< \"\$out\""
assert_pass "a recorded 'yes' is honoured without asking again" bash -c "$(_telecom_env)
  export TDE_STATE_FILE=\"$TELE/state_rec_yes_\$\$.env\"; state_init
  state_set TELECOM_WANTED 1 >/dev/null
  phase4_telecom_wanted < /dev/null"
assert_fail "a recorded 'no' is honoured without asking again" bash -c "$(_telecom_env)
  export TDE_STATE_FILE=\"$TELE/state_rec_no_\$\$.env\"; state_init
  state_set TELECOM_WANTED 0 >/dev/null
  phase4_telecom_wanted < /dev/null"
assert_fail "the interactive prompt defaults to No on a bare Enter" bash -c "$(_telecom_env)
  export TDE_STATE_FILE=\"$TELE/state_enter_\$\$.env\"; state_init
  _telecom_can_ask() { return 0; }
  echo '' | phase4_telecom_wanted"
# _telecom_can_ask is stubbed because a test harness cannot hand a
# piped shell a controlling terminal; the real check is [ -t 0 ].
assert_pass "answering y at the prompt selects telecom and records it" bash -c "$(TDE_CASE=yes _telecom_env)
  export TDE_STATE_FILE=\"$TELE/state_yes_\$\$.env\"; state_init
  _telecom_can_ask() { return 0; }
  echo 'y' | phase4_telecom_wanted
  [ \"\$(state_get TELECOM_WANTED)\" = 1 ]"
assert_fail "--dry-run never blocks on the telecom question" bash -c "$(_telecom_env)
  TDE_DRY_RUN=1 phase4_telecom_wanted < /dev/null"
assert_pass "the audit reports telecom as selected/skipped without ever prompting" bash -c "$(_telecom_env)
  export TDE_STATE_FILE=\"$TELE/state_audit_\$\$.env\"; state_init
  source '$SCRIPT_DIR/lib/verify_functional.sh'
  state_set TELECOM_WANTED 1 >/dev/null
  phase5_telecom_selected < /dev/null"

# --- 3.2 lock: names the holder, never breaks a live lock ---
LOCKT="$TESTROOT/locks"; mkdir -p "$LOCKT"
assert_pass "the lock file records the holder's PID" bash -c "
  export TDE_LOCK_FILE='$LOCKT/pid.lock' TMPDIR='$LOCKT'
  source '$SCRIPT_DIR/lib/lock.sh'; lock_acquire
  [ \"\$(cat '$LOCKT/pid.lock')\" = \"\$\$\" ]
"
assert_pass "a second process is refused and told which PID holds the lock" bash -c "
  export TDE_LOCK_FILE='$LOCKT/busy.lock' TMPDIR='$LOCKT'
  source '$SCRIPT_DIR/lib/lock.sh'; lock_acquire
  out=\"\$(bash -c \"export TDE_LOCK_FILE='$LOCKT/busy.lock' TMPDIR='$LOCKT'; source '$SCRIPT_DIR/lib/lock.sh'; lock_acquire\" 2>&1 || true)\"
  grep -q \"PID \$\$\" <<< \"\$out\"
"
# Regression: opening the lock with > truncated the file at open() time,
# before flock was even attempted, so a failing second process wiped the
# holder's PID on its way to printing an error that then could not name it.
assert_pass "a refused attempt does not wipe the holder's PID from the lock file" bash -c "
  export TDE_LOCK_FILE='$LOCKT/keep.lock' TMPDIR='$LOCKT'
  source '$SCRIPT_DIR/lib/lock.sh'; lock_acquire
  bash -c \"export TDE_LOCK_FILE='$LOCKT/keep.lock' TMPDIR='$LOCKT'; source '$SCRIPT_DIR/lib/lock.sh'; lock_acquire\" >/dev/null 2>&1 || true
  [ \"\$(cat '$LOCKT/keep.lock')\" = \"\$\$\" ]
"
# Regression: `exec {fd}>file 2>/dev/null` redirects the SHELL's stderr
# permanently, which silently swallowed every later error message.
assert_pass "acquiring the lock does not redirect the shell's stderr to /dev/null" bash -c "
  export TDE_LOCK_FILE='$LOCKT/stderr.lock' TMPDIR='$LOCKT'
  source '$SCRIPT_DIR/lib/lock.sh'; lock_acquire
  out=\"\$(echo 'still visible' >&2 2>&1)\" || true
  echo 'probe' >&2
" 2>&1
assert_pass "a stale PID with the lock free is simply taken over" bash -c "
  echo 999999 > '$LOCKT/stale.lock'
  export TDE_LOCK_FILE='$LOCKT/stale.lock' TMPDIR='$LOCKT'
  source '$SCRIPT_DIR/lib/lock.sh'; lock_acquire
  [ \"\$(cat '$LOCKT/stale.lock')\" = \"\$\$\" ]
"
assert_pass "a locked-out message always offers a manual way out" bash -c "
  export TDE_LOCK_FILE='$LOCKT/manual.lock' TMPDIR='$LOCKT'
  source '$SCRIPT_DIR/lib/lock.sh'; lock_acquire
  out=\"\$(bash -c \"export TDE_LOCK_FILE='$LOCKT/manual.lock' TMPDIR='$LOCKT'; source '$SCRIPT_DIR/lib/lock.sh'; lock_acquire\" 2>&1 || true)\"
  grep -qE 'kill |rm -f' <<< \"\$out\"
"

# --- 3.3 big blocks go over stdin, never through the environment ---
assert_pass "idempotent_append_container does not pass content via --env" bash -c "
  ! grep -q 'TDE_IA_CONTENT' '$SCRIPT_DIR/lib/idempotent_append.sh'
"
assert_pass "idempotent_append_container pipes the content in on stdin" bash -c "
  sed -n '/^idempotent_append_container()/,/^}/p' '$SCRIPT_DIR/lib/idempotent_append.sh' | grep -q '| proot-distro'
"
# The point of the change: a block far larger than a single environment
# variable may safely carry still lands intact.
BIGHOME="$TESTROOT/bigblock"; mkdir -p "$BIGHOME"
# Written to a script file instead of a deeply nested bash -c string:
# this needs an awk program, a 200 KB value and a grep regex, and the
# quoting required to nest all three inside the assert was its own
# source of bugs.
cat > "$TESTROOT/bigblock_test.sh" << 'BIGEOF'
set -u
BIGHOME="$1"; LIB="$2"
mkdir -p "$BIGHOME"
source "$LIB/lib/error_handling.sh"
source "$LIB/lib/logging.sh"; log_init >/dev/null
source "$LIB/lib/idempotent_append.sh"
proot-distro() {
  while [ "$#" -gt 0 ]; do
    case "$1" in --env) shift; export "${1?}"; shift ;; --) shift; break ;; *) shift ;; esac
  done
  HOME="$BIGHOME" "$@"
}
big="$(awk 'BEGIN{while(i++<200000)printf "x"}')"
[ "${#big}" = 200000 ] || { echo "generator produced ${#big}"; exit 0; }
idempotent_append_container archarm kattze ".bigrc" "big" "$big" >/dev/null 2>&1
line="$(grep -m1 '^x' "$BIGHOME/.bigrc" 2>/dev/null || true)"
if [ "${#line}" = 200000 ]; then echo ok; else echo "truncated (${#line})"; fi
BIGEOF
assert_eq "a 200 KB block survives intact (a single env var caps out at 128 KB)" "ok" \
  "$(bash "$TESTROOT/bigblock_test.sh" "$TESTROOT/bigblock" "$SCRIPT_DIR")"
assert_pass "an empty block is refused instead of wiping a good one" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/idempotent_append.sh'
  proot-distro() {
    while [ \"\$#\" -gt 0 ]; do
      case \"\$1\" in --env) shift; export \"\${1?}\"; shift ;; --) shift; break ;; *) shift ;; esac
    done
    HOME='$BIGHOME' \"\$@\"
  }
  ! idempotent_append_container archarm kattze '.bigrc' 'empty' '' 2>/dev/null
"

# --- 3.6 self-heal reachable outside phase 5 ---
assert_pass "a WARNING-level audit failure is recorded as such" bash -c "
  export HOME='$TESTROOT/warnhome'; mkdir -p \"\$HOME\"
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/generate_report.sh'
  _audit_check 'thing' WARNING false >/dev/null 2>&1
  [ \"\$TDE_AUDIT_HAD_WARNING\" = 1 ] && [ \"\$TDE_AUDIT_HAD_CRITICAL_FAILURE\" = 0 ]
"
assert_pass "a CRITICAL failure is not reported as a mere warning" bash -c "
  export HOME='$TESTROOT/crithome'; mkdir -p \"\$HOME\"
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/generate_report.sh'
  _audit_check 'thing' CRITICAL false >/dev/null 2>&1
  [ \"\$TDE_AUDIT_HAD_CRITICAL_FAILURE\" = 1 ] && [ \"\$TDE_AUDIT_HAD_WARNING\" = 0 ]
"
assert_pass "core.sh re-runs phase 5 while recoverable warnings remain" bash -c "
  grep -q 'PHASE5_WARNINGS' '$SCRIPT_DIR/core.sh'
"
assert_pass "TDE_NO_SELF_HEAL=1 stops the phase-5 retry loop" bash -c "
  grep -q 'TDE_NO_SELF_HEAL' '$SCRIPT_DIR/core.sh'
"
assert_pass "archselfheal exists as a standalone entry point to self-heal" bash -c "
  grep -q 'phase6_write_archselfheal' '$SCRIPT_DIR/components/install_maintenance.sh' &&
  grep -q 'phase5_self_heal' '$SCRIPT_DIR/components/install_maintenance.sh'
"

echo ""
echo "=== informe 2026-10-03 P2 + deuda técnica ==="

# --- 4.1 paru ---
assert_pass "archparu is installed as the documented paru retry path" bash -c "
  grep -q 'phase6_write_archparu' '$SCRIPT_DIR/components/install_maintenance.sh'
"
assert_pass "cleanup gates on 'paru --version', not merely 'command -v paru'" bash -c "
  grep -q 'paru --version' '$SCRIPT_DIR/lib/cleanup.sh'
"

# --- 4.3 locale verified, not assumed ---
assert_pass "the locale step verifies the result with locale -a" bash -c "
  grep -q 'locale -a' '$SCRIPT_DIR/components/shell_setup.sh'
"
assert_pass "a missing UTF-8 locale is named as a locale problem, not a font one" bash -c "
  grep -A6 'locale -a' '$SCRIPT_DIR/components/shell_setup.sh' | grep -qi 'not a font problem'
"

# --- 4.4 parallel downloads ---
assert_pass "pacman is configured for 10 parallel downloads" bash -c "
  grep -q 'ParallelDownloads = 10' '$SCRIPT_DIR/components/install_rootfs.sh'
"
assert_pass "the ParallelDownloads edit also rewrites an already-uncommented value" bash -c "
  sed -n '/phase3_disable_pacman_sandbox()/,/^}/p' '$SCRIPT_DIR/components/install_rootfs.sh' | grep -qF 's/^#\\?ParallelDownloads'
"

# --- 4.5 log rotation ---
assert_eq "log_rotate keeps only the newest N logs" "5" \
  "$(bash -c "
     export HOME='$TESTROOT/rotate'; mkdir -p \"\$HOME\"
     source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'
     mkdir -p \"\$TDE_LOG_DIR\"
     for i in \$(seq 10 40); do : > \"\$TDE_LOG_DIR/install_202601\${i}_000000.log\"; done
     TDE_LOG_KEEP=5 log_rotate 'install_*.log'
     ls -1 \"\$TDE_LOG_DIR\" | wc -l")"
assert_pass "log_rotate on an empty log dir does not abort the run under set -e" bash -c "
  export HOME='$TESTROOT/rotate_empty'; mkdir -p \"\$HOME\"
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'
  log_init
  log_rotate 'install_report_*.log'
"

# --- 4.6 config migration on version change ---
assert_pass "core.sh re-applies generated config when the version changes" bash -c "
  grep -q '_tde_migrate_config' '$SCRIPT_DIR/core.sh' &&
  grep -q 'INSTALLED_VERSION' '$SCRIPT_DIR/core.sh'
"
assert_pass "migration never clears state that cannot be regenerated" bash -c "
  ! sed -n '/_tde_migrate_config()/,/^}/p' '$SCRIPT_DIR/core.sh' | grep -qE 'ARCH_USERNAME|PHASE3_ROOTFS|PHASE3_USER'
"

# --- 4.7 the ERR trap says what failed ---
assert_pass "the ERR trap reports the failing command and its exit status" bash -c "
  out=\"\$(bash -c \"source '$SCRIPT_DIR/lib/error_handling.sh'; false\" 2>&1 || true)\"
  grep -q \"'false' exited 1\" <<< \"\$out\"
"
# A trap alone cannot rescue a failing command: set -e exits the shell
# regardless of what the ERR trap returns. tde_soft_begin suspends both.
assert_pass "tde_soft_begin lets a region fail without aborting the run" bash -c "
  out=\"\$(bash -c \"source '$SCRIPT_DIR/lib/error_handling.sh'; tde_soft_begin; false; echo SURVIVED; tde_soft_end\" 2>&1 || true)\"
  grep -q SURVIVED <<< \"\$out\"
"
assert_pass "tde_soft_end restores the abort-on-error behaviour" bash -c "
  out=\"\$(bash -c \"source '$SCRIPT_DIR/lib/error_handling.sh'; tde_soft_begin; tde_soft_end; false; echo SHOULD_NOT_PRINT\" 2>&1 || true)\"
  ! grep -q SHOULD_NOT_PRINT <<< \"\$out\"
"

# --- 5.x technical debt ---
assert_pass "the audit label no longer claims to have verified paru" bash -c "
  ! grep -q 'gcc/git/paru' '$SCRIPT_DIR/lib/verify_functional.sh'
"
assert_fail "reserved usernames now cover real Arch service accounts (http)" _username_is_valid http
assert_fail "reserved usernames now cover real Arch service accounts (wheel)" _username_is_valid wheel
assert_fail "reserved usernames now cover real Arch service accounts (ftp)"   _username_is_valid ftp
assert_pass "the default username 'user' is still accepted"                   _username_is_valid user
assert_pass "a normal username is still accepted"                             _username_is_valid kattze
assert_eq "retry_with_backoff does not retry after Ctrl+C" "1" \
  "$(bash -c "
     source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
     source '$SCRIPT_DIR/lib/network.sh'
     N=0
     interrupted() { N=\$((N+1)); return 130; }
     retry_with_backoff 3 1 interrupted >/dev/null 2>&1 || true
     echo \$N")"
assert_eq "retry_with_backoff still retries a normal failure" "3" \
  "$(bash -c "
     source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
     source '$SCRIPT_DIR/lib/network.sh'
     N=0
     broken() { N=\$((N+1)); return 1; }
     retry_with_backoff 3 0 broken >/dev/null 2>&1 || true
     echo \$N")"
assert_pass "state_del is a no-op under --dry-run, like state_set" bash -c "
  export TDE_STATE_FILE='$TESTROOT/drydel.env'
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'; state_init
  state_set KEEPME 1 >/dev/null
  TDE_DRY_RUN=1 state_del KEEPME >/dev/null
  [ \"\$(state_get KEEPME)\" = 1 ]
"

# --- 4.1 paru: OOM-aware, and "installed" must mean "runs" ---
assert_pass "the paru skip-if-present check requires paru to actually run" bash -c "
  sed -n '/^phase4_install_paru()/,/^}/p' '$SCRIPT_DIR/components/dev_toolchain.sh' |
    head -20 | grep -q 'paru --version'
"
assert_pass "the Rust rebuild is serialised to survive Android's memory limits" bash -c "
  grep -q 'CARGO_BUILD_JOBS=1' '$SCRIPT_DIR/components/dev_toolchain.sh'
"
assert_pass "an OOM-killed paru build (137) is reported as out of memory" bash -c "
  sed -n '/^phase4_install_paru()/,/^}/p' '$SCRIPT_DIR/components/dev_toolchain.sh' |
    grep -A2 'eq 137' | grep -qi 'out of memory'
"
assert_pass "a failed paru points at archparu rather than a manual makepkg" bash -c "
  sed -n '/^phase4_install_paru()/,/^}/p' '$SCRIPT_DIR/components/dev_toolchain.sh' | grep -q 'archparu'
"

# --- the container name is a variable, not a literal, everywhere ---
# Every mention must be a ":-archarm" fallback (core.sh, the shared
# helpers, and the generated commands each need their own default
# because they run standalone) — never a bare literal that would ignore
# TDE_DISTRO_NAME.
assert_eq "no source uses a bare 'archarm' literal instead of the variable" "0" \
  "$(grep -rno 'archarm' "$SCRIPT_DIR"/core.sh "$SCRIPT_DIR"/lib/*.sh "$SCRIPT_DIR"/components/*.sh |
     while IFS=: read -r f n _; do
       sed -n "${n}p" "$f" | grep -q -- ':-archarm' || echo "$f:$n"
     done | wc -l)"
assert_pass "TDE_DISTRO_NAME set in the environment is honoured" bash -c "
  grep -q 'TDE_DISTRO_NAME:-archarm' '$SCRIPT_DIR/core.sh'
"
