# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== informe 2026-10-03 P0: extra-keys, Nerd Font, launcher exec, fastfetch banner ==="

# --- 2.1 the Termux extra-keys row must never be emptied or overwritten ---
# Only actual writes count — the file legitimately *mentions* the empty
# row in a comment and in the warning that tells people an older version
# left them with one.
assert_eq "setup_launcher.sh never writes an empty extra-keys row" "0" \
  "$(grep -v '^[[:space:]]*#' "$SCRIPT_DIR/components/setup_launcher.sh" | grep -c 'echo "extra-keys = \[\]"')"
assert_pass "the default extra-keys row contains ESC, CTRL and the arrow keys" bash -c "
  source '$SCRIPT_DIR/components/setup_launcher.sh' 2>/dev/null || true
  for k in ESC CTRL TAB LEFT RIGHT UP DOWN; do
    case \"\$TDE_TERMUX_EXTRA_KEYS\" in *\"'\$k'\"*) ;; *) echo \"missing \$k\" >&2; exit 1 ;; esac
  done
"
UIT="$TESTROOT/ui_test"; mkdir -p "$UIT"
assert_eq "a fresh install gets a usable extra-keys row written" "1" \
  "$(HOME="$UIT/fresh" bash -c "
     mkdir -p \"\$HOME\"
     source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
     source '$SCRIPT_DIR/components/setup_launcher.sh'
     phase3_configure_termux_ui >/dev/null 2>&1
     grep -c \"^extra-keys = \\[\\['ESC'\" \"\$HOME/.termux/termux.properties\"")"
assert_eq "an extra-keys row the user already configured is left untouched" "extra-keys = [['F1']]" \
  "$(HOME="$UIT/existing" bash -c "
     mkdir -p \"\$HOME/.termux\"
     echo \"extra-keys = [['F1']]\" > \"\$HOME/.termux/termux.properties\"
     source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
     source '$SCRIPT_DIR/components/setup_launcher.sh'
     phase3_configure_termux_ui >/dev/null 2>&1
     cat \"\$HOME/.termux/termux.properties\"")"
assert_pass "an extra-keys row emptied by an older version is reported, not silently kept" bash -c "
  export HOME='$UIT/emptied'; mkdir -p \"\$HOME/.termux\"
  echo 'extra-keys = []' > \"\$HOME/.termux/termux.properties\"
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/components/setup_launcher.sh'
  # Captured into a variable instead of piped into grep -q: this file
  # sources error_handling.sh (set -o pipefail), and grep -q exiting on
  # the first match SIGPIPEs the producer, whose 141 then wins the
  # pipeline — the same gotcha documented in tests/verify_all.sh round 3.
  out=\"\$(phase3_configure_termux_ui 2>&1)\"
  grep -q 'archreapply' <<< \"\$out\"
"
assert_eq "use-black-ui is opt-in and not written by default" "0" \
  "$(HOME="$UIT/blackui" bash -c "
     mkdir -p \"\$HOME\"
     source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
     source '$SCRIPT_DIR/components/setup_launcher.sh'
     phase3_configure_termux_ui >/dev/null 2>&1
     grep -c 'use-black-ui' \"\$HOME/.termux/termux.properties\" || true")"
assert_eq "use-black-ui IS written when TDE_TERMUX_BLACK_UI=1" "1" \
  "$(HOME="$UIT/blackui_on" TDE_TERMUX_BLACK_UI=1 bash -c "
     mkdir -p \"\$HOME\"
     source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
     source '$SCRIPT_DIR/components/setup_launcher.sh'
     phase3_configure_termux_ui >/dev/null 2>&1
     grep -c 'use-black-ui' \"\$HOME/.termux/termux.properties\"")"
assert_pass "phase3_launcher_ok no longer requires an extra-keys line to exist" bash -c "
  ! grep -A12 'phase3_launcher_ok()' '$SCRIPT_DIR/components/setup_launcher.sh' | grep -q 'grep -q \"\\^extra-keys\"'
"

# --- 2.2 Nerd Font: validate the file, not just its existence ---
FONTDIR="$TESTROOT/fontcheck"; mkdir -p "$FONTDIR"
: > "$FONTDIR/empty.ttf"
head -c 2000 /dev/zero > "$FONTDIR/tiny.ttf"
{ printf '\x00\x01\x00\x00'; head -c 200000 /dev/zero; } > "$FONTDIR/real.ttf"
{ printf 'OTTO'; head -c 200000 /dev/zero; } > "$FONTDIR/otf.ttf"
{ printf 'NOPE'; head -c 200000 /dev/zero; } > "$FONTDIR/bogus.ttf"
source "$SCRIPT_DIR/components/nerdfonts.sh"
assert_fail "nerdfont_file_ok rejects an empty font file"            nerdfont_file_ok "$FONTDIR/empty.ttf"
assert_fail "nerdfont_file_ok rejects a truncated font file"         nerdfont_file_ok "$FONTDIR/tiny.ttf"
assert_fail "nerdfont_file_ok rejects a big file that is not a font" nerdfont_file_ok "$FONTDIR/bogus.ttf"
assert_fail "nerdfont_file_ok rejects a path that does not exist"    nerdfont_file_ok "$FONTDIR/missing.ttf"
assert_pass "nerdfont_file_ok accepts a real TrueType file"          nerdfont_file_ok "$FONTDIR/real.ttf"
assert_pass "nerdfont_file_ok accepts an OpenType (OTTO) file"       nerdfont_file_ok "$FONTDIR/otf.ttf"
assert_pass "phase5_nerdfont_ok delegates to nerdfont_file_ok (magic bytes, not just size)" bash -c "
  grep -q 'nerdfont_file_ok' '$SCRIPT_DIR/lib/verify_functional.sh'
"
assert_pass "phase5_nerdfont_ok rejects a big non-font where the old size-only check passed" bash -c "
  export HOME='$FONTDIR/home'; mkdir -p \"\$HOME/.termux\"
  cp '$FONTDIR/bogus.ttf' \"\$HOME/.termux/font.ttf\"
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/components/nerdfonts.sh'; source '$SCRIPT_DIR/lib/verify_functional.sh'
  ! phase5_nerdfont_ok
"
assert_pass "the font install retries instead of giving up after one attempt" bash -c "
  grep -q 'TDE_NERDFONT_ATTEMPTS' '$SCRIPT_DIR/components/nerdfonts.sh'
"
assert_pass "a failed font install tells the person about Android's force-stop" bash -c "
  grep -qi 'force-stop' '$SCRIPT_DIR/components/nerdfonts.sh'
"
assert_pass "an already-valid font is not re-downloaded" bash -c "
  export HOME='$FONTDIR/home_ok'; mkdir -p \"\$HOME/.termux\"
  cp '$FONTDIR/real.ttf' \"\$HOME/.termux/font.ttf\"
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'
  source '$SCRIPT_DIR/components/nerdfonts.sh'
  phase4_install_nerdfont_pkg() { echo 'SHOULD NOT REINSTALL' >&2; return 1; }
  phase4_download_nerdfont()    { echo 'SHOULD NOT DOWNLOAD' >&2; return 1; }
  phase4_nerdfonts_run >/dev/null
"

# --- 2.3 launcher: a real smoke test, with a timeout, expanded in the container ---
LSIM="$TESTROOT/launcher_sim"
assert_pass "the launcher snippet is generated with valid syntax" bash -c "
  export HOME='$LSIM' PREFIX='$LSIM/usr' TDE_DISTRO_NAME=archarm TDE_ROOT='$SCRIPT_DIR'
  export TDE_STATE_FILE='$LSIM/state.env'
  mkdir -p \"\$HOME\" \"\$PREFIX/bin\"
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/kv.sh'; source '$SCRIPT_DIR/lib/state.sh'; state_init
  state_set ARCH_USERNAME kattze >/dev/null
  source '$SCRIPT_DIR/lib/idempotent_append.sh'; source '$SCRIPT_DIR/lib/container_paths.sh'
  source '$SCRIPT_DIR/components/setup_launcher.sh'
  phase3_write_launcher_config; phase3_install_zshrc_snippet
  bash -n \"\$HOME/.bashrc\"
"
assert_pass "the smoke test checks home, login shell and zsh — not just 'true'" bash -c "
  grep -q 'getent passwd' '$LSIM/.bashrc' && grep -q 'usr/bin/zsh' '$LSIM/.bashrc'
"
assert_pass "the smoke test runs under a timeout" bash -c "
  grep -q 'TDE_LAUNCHER_SMOKE_TIMEOUT' '$LSIM/.bashrc'
"
# The regression that matters: \$HOME and \$(getent ...) must reach the
# container unexpanded. If the Termux-side shell expanded them while
# writing the snippet, the test would compare Termux's own bash against
# /usr/bin/zsh and could never succeed.
assert_pass "the smoke test is expanded inside the container, not by the Termux shell" bash -c "
  grep -q 'test -d \"\\\$HOME\"' '$LSIM/.bashrc' && ! grep -q 'test -d \"$LSIM\"' '$LSIM/.bashrc'
"
assert_pass "a healthy container is entered with exec (one exit closes Termux)" bash -c "
  grep -q 'exec proot-distro login' '$LSIM/.bashrc'
"
assert_pass "a healthy container really execs into Arch" bash -c "
  export HOME='$LSIM'
  mkdir -p '$LSIM/fakebin'
  printf '#!/bin/sh\ncase \"\$*\" in *isolated*) echo ENTERED_ARCH; exit 0 ;; esac\nexit 0\n' > '$LSIM/fakebin/proot-distro'
  chmod +x '$LSIM/fakebin/proot-distro'
  out=\"\$(PATH='$LSIM/fakebin':\$PATH bash --noprofile --rcfile '$LSIM/.bashrc' -i -c 'echo NOT_REACHED' 2>&1)\"
  grep -q ENTERED_ARCH <<< \"\$out\" && ! grep -q NOT_REACHED <<< \"\$out\"
"
assert_pass "a broken container leaves the person in Termux with a next step" bash -c "
  export HOME='$LSIM'
  printf '#!/bin/sh\nexit 1\n' > '$LSIM/fakebin/proot-distro'; chmod +x '$LSIM/fakebin/proot-distro'
  out=\"\$(PATH='$LSIM/fakebin':\$PATH bash --noprofile --rcfile '$LSIM/.bashrc' -i -c 'echo STAYED_IN_TERMUX' 2>&1)\"
  grep -q STAYED_IN_TERMUX <<< \"\$out\" && grep -q 'archdiag' <<< \"\$out\"
"
assert_pass "a container that times out says so specifically" bash -c "
  export HOME='$LSIM'
  printf '#!/bin/sh\nexit 124\n' > '$LSIM/fakebin/proot-distro'; chmod +x '$LSIM/fakebin/proot-distro'
  PATH='$LSIM/fakebin':\$PATH bash --noprofile --rcfile '$LSIM/.bashrc' -i -c true 2>&1 | grep -qi 'did not respond'
"
assert_pass "TDE_SKIP_LAUNCHER=1 still bypasses the launcher entirely" bash -c "
  export HOME='$LSIM'
  printf '#!/bin/sh\necho SHOULD_NOT_RUN; exit 0\n' > '$LSIM/fakebin/proot-distro'; chmod +x '$LSIM/fakebin/proot-distro'
  out=\"\$(TDE_SKIP_LAUNCHER=1 PATH='$LSIM/fakebin':\$PATH bash --noprofile --rcfile '$LSIM/.bashrc' -i -c 'echo BYPASSED' 2>&1)\"
  grep -q BYPASSED <<< \"\$out\" && ! grep -q SHOULD_NOT_RUN <<< \"\$out\"
"
assert_pass "phase 6 re-asserts the launcher snippet at the end of every install" bash -c "
  grep -q 'phase3_install_zshrc_snippet' '$SCRIPT_DIR/components/install_maintenance.sh'
"

# --- 2.4 fastfetch must not print under the previous scrollback ---
assert_pass "the container .zshrc clears the screen before the fastfetch banner" bash -c "
  grep -B4 'fastfetch' '$SCRIPT_DIR/components/shell_setup.sh' | grep -q 'printf \"' 
"
assert_eq "the banner reset is a real ESC sequence once written to .zshrc" "1" \
  "$(python3 - "$SCRIPT_DIR/components/shell_setup.sh" <<'PYEOF'
import re, subprocess, sys
src = open(sys.argv[1]).read()
block = re.search(r"runtime_block='(.*?)'\n\n", src, re.S).group(1)
line = [l for l in block.split('\n') if l.strip().startswith('printf')][0]
out = subprocess.run(['bash','-c',line.strip()], capture_output=True).stdout
print(1 if out == b'\x1bc' else 0)
PYEOF
)"
