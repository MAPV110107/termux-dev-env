# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR). Run: bash tests/test_pure_logic.sh
echo ""
echo "=== informe 2026-10-04: Nerd Font rm-before-write + force-stop banner ==="

NF4="$TESTROOT/nf4"; mkdir -p "$NF4"
head -c 200000 /dev/zero > "$NF4/body.bin"
{ printf '\x00\x01\x00\x00'; cat "$NF4/body.bin"; } > "$NF4/real.ttf"
{ printf 'OTTO'; cat "$NF4/body.bin"; } > "$NF4/otf.ttf"
_nf4_env() {
  echo "
    export HOME=\"$NF4/home_\$\$\"; rm -rf \"\$HOME\"; mkdir -p \"\$HOME/.termux\"
    source '$SCRIPT_DIR/lib/error_handling.sh'
    source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
    source '$SCRIPT_DIR/components/nerdfonts.sh'
  "
}

assert_pass "zip path: an existing font.ttf is replaced, never overwritten in place" bash -c "$(_nf4_env)
  export TDE_NERDFONT_TMPDIR='$NF4/zipwork'; mkdir -p \"\$TDE_NERDFONT_TMPDIR\"
  cp '$NF4/real.ttf' \"\$TDE_NERDFONT_TMPDIR/JetBrainsMonoNerdFontMono-Regular.ttf\"
  unzip() { return 0; }
  cp '$NF4/otf.ttf' \"\$HOME/.termux/font.ttf\"
  ln \"\$HOME/.termux/font.ttf\" \"\$HOME/old_inode\"
  phase4_extract_and_install_nerdfont >/dev/null 2>&1
  [ \"\$(head -c4 \"\$HOME/old_inode\")\" = OTTO ] && [ \"\$(od -An -tx1 -N4 \"\$HOME/.termux/font.ttf\" | tr -d ' \\n')\" = 00010000 ]
"
assert_pass "pacman path: an existing font.ttf is replaced, never overwritten in place" bash -c "$(_nf4_env)
  export TDE_DISTRO_NAME=archarm TDE_NERDFONT_PKG=x TDE_LOG_FILE=/dev/null
  proot-distro() {
    case \"\$*\" in
      *'pacman -Ql'*) echo 'x /usr/share/fonts/X/NerdFontMono-Regular.ttf' ;;
      *' cat '*)      cat '$NF4/real.ttf' ;;
      *)              return 0 ;;
    esac
  }
  cp '$NF4/otf.ttf' \"\$HOME/.termux/font.ttf\"
  ln \"\$HOME/.termux/font.ttf\" \"\$HOME/old_inode\"
  phase4_install_nerdfont_pkg >/dev/null 2>&1
  nerdfont_file_ok && [ \"\$(head -c4 \"\$HOME/old_inode\")\" = OTTO ]
"
assert_pass "no font write onto font.ttf is left without a preceding rm -f" bash -c "
  awk '
    /rm -f \"\\\$HOME\\/\\.termux\\/font\\.ttf\"\$/ { rm=1; next }
    /^[[:space:]]*(mv|cp) .*\"\\\$HOME\\/\\.termux\\/font\\.ttf\"/ { if (!rm) bad=1; rm=0 }
    END { exit bad }
  ' '$SCRIPT_DIR/components/nerdfonts.sh'
"
assert_pass "the force-stop banner is loud, names both steps and ADB, and returns 0" bash -c "$(_nf4_env)
  set -e
  out=\"\$(_nerdfont_print_forcestop_banner 2>&1)\"
  grep -q 'IMPORTANT' <<< \"\$out\" && grep -q 'Force stop' <<< \"\$out\" && grep -q 'am force-stop com.termux' <<< \"\$out\"
"
assert_pass "a successful install prints the banner, not just the one-line hint" bash -c "
  grep -A2 'installed\" = \"1\" \]; then' '$SCRIPT_DIR/components/nerdfonts.sh' >/dev/null &&
  grep -q '_nerdfont_print_forcestop_banner' '$SCRIPT_DIR/components/nerdfonts.sh'
"
assert_pass "the audit warning for a bad Nerd Font names archfont --force" bash -c "
  grep -q 'archfont --force' '$SCRIPT_DIR/lib/verify_functional.sh'
"
