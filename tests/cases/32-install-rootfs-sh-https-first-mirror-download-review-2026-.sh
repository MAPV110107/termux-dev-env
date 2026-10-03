# Test case file for tests/test_pure_logic.sh — sourced by the runner,
# not executed on its own: it relies on the runner's harness
# (assert_eq / assert_pass / assert_fail, $FAILURES, $TESTROOT,
# $SCRIPT_DIR and the libs it has already sourced), and on the shell
# state earlier case files leave behind. Run: bash tests/test_pure_logic.sh
echo ""
echo "=== install_rootfs.sh https-first mirror download (review 2026-10-03, item 5.4) ==="
# GPG verification is what makes the tarball trustworthy, but plain http
# lets a captive portal or transparent proxy hand back an error page /
# truncated body. https is tried first per mirror; http stays as a
# fallback for a skewed device clock or stale ca-certificates.
assert_pass "the first download attempt for a mirror uses https" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/network.sh'
  source '$SCRIPT_DIR/components/install_rootfs.sh'
  TDE_ROOTFS_TARBALL='$TESTROOT/https_first.tar.gz'; TDE_ROOTFS_SIG=\"\$TDE_ROOTFS_TARBALL.sig\"
  FIRST=''
  curl() { for a in \"\$@\"; do case \"\$a\" in http*) [ -z \"\$FIRST\" ] && FIRST=\"\$a\" ;; esac; done; touch \"\$3\"; return 0; }
  gpg() { return 0; }
  phase3_download_and_verify >/dev/null 2>&1
  case \"\$FIRST\" in https://*) exit 0 ;; *) echo \"first URL was \$FIRST\" >&2; exit 1 ;; esac
"
assert_pass "a mirror that fails over https is retried over http before moving on" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/network.sh'
  source '$SCRIPT_DIR/components/install_rootfs.sh'
  TDE_ROOTFS_TARBALL='$TESTROOT/http_fallback.tar.gz'; TDE_ROOTFS_SIG=\"\$TDE_ROOTFS_TARBALL.sig\"
  TDE_ARM_MIRRORS=(only.example.org)
  SCHEMES=''
  curl() {
    local url=''
    for a in \"\$@\"; do case \"\$a\" in http*) url=\"\$a\" ;; esac; done
    case \"\$url\" in
      https://*) SCHEMES=\"\$SCHEMES https\"; return 1 ;;
      http://*)  SCHEMES=\"\$SCHEMES http\";  touch \"\$3\"; return 0 ;;
    esac
  }
  gpg() { return 0; }
  phase3_download_and_verify >/dev/null 2>&1
  grep -q 'https' <<< \"\$SCHEMES\" && grep -q ' http' <<< \"\$SCHEMES\"
"
assert_fail "a bad signature moves to the next mirror instead of retrying the same one over http" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/network.sh'
  source '$SCRIPT_DIR/components/install_rootfs.sh'
  TDE_ROOTFS_TARBALL='$TESTROOT/badsig.tar.gz'; TDE_ROOTFS_SIG=\"\$TDE_ROOTFS_TARBALL.sig\"
  TDE_ARM_MIRRORS=(only.example.org)
  ATTEMPTS=0
  curl() { ATTEMPTS=\$((ATTEMPTS + 1)); touch \"\$3\"; return 0; }
  gpg() { return 1; }
  log_fatal_code() { [ \"\$ATTEMPTS\" -le 2 ] && exit 7; exit 1; }
  phase3_download_and_verify >/dev/null 2>&1
"
assert_pass "the pinned TDE_ROOTFS_URL_OVERRIDE scheme is still used verbatim" bash -c "
  source '$SCRIPT_DIR/lib/error_handling.sh'; source '$SCRIPT_DIR/lib/logging.sh'; log_init >/dev/null
  source '$SCRIPT_DIR/lib/network.sh'
  source '$SCRIPT_DIR/components/install_rootfs.sh'
  TDE_ROOTFS_TARBALL='$TESTROOT/pin2.tar.gz'; TDE_ROOTFS_SIG=\"\$TDE_ROOTFS_TARBALL.sig\"
  SEEN=''
  curl() { for a in \"\$@\"; do case \"\$a\" in http*) SEEN=\"\$SEEN \$a\" ;; esac; done; touch \"\$3\"; return 0; }
  gpg() { return 0; }
  TDE_ROOTFS_URL_OVERRIDE='http://pinned.example.org/my.tar.gz' phase3_download_and_verify >/dev/null 2>&1
  grep -q 'http://pinned.example.org/my.tar.gz' <<< \"\$SEEN\"
"
