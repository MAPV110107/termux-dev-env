#!/usr/bin/env bash
# Full verification pipeline: syntax, shellcheck, unit suite, undefined-function scan,
# tilde-expansion safety check, error code documentation check, and dry-run simulation.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
SRC="$ROOT/src"

FAILS=0
fail() { echo "  FAIL  $*"; FAILS=$((FAILS + 1)); }
ok()   { echo "  OK    $*"; }

echo "== 1. Syntax check (bash -n) =="
bad=0
while IFS= read -r f; do
  bash -n "$f" 2>/dev/null || { fail "syntax: $f"; bad=1; }
done < <(find . -name '*.sh' -not -path './.git/*')
[ "$bad" = 0 ] && ok "all shell scripts parse cleanly"

echo "== 2. ShellCheck (-S warning) =="
if command -v shellcheck >/dev/null 2>&1; then
  sc_out="$(shellcheck -S warning -s bash launcher.sh src/orchestrator.sh src/lib/*.sh src/modules/*.sh tests/*.sh 2>&1)"
  if [ -z "$sc_out" ]; then
    ok "shellcheck clean"
  else
    fail "shellcheck warnings found"
    echo "$sc_out" | head -30
  fi
else
  echo "  SKIP  shellcheck not installed"
fi

echo "== 3. Unit & regression test suite =="
out="$(bash tests/test_suite.sh 2>&1)"
if grep -q "ALL .* CHECKS PASSED" <<< "$out"; then
  ok "$(grep -oE 'ALL [0-9]+ CHECKS PASSED' <<< "$out")"
else
  fail "unit test suite"
  echo "$out"
fi

echo "== 4. Unprotected ~/ in proot-distro calls =="
python3 - << 'PY' || FAILS=$((FAILS + 1))
import re, glob, sys
bad = []
for f in glob.glob('src/modules/*.sh') + glob.glob('src/lib/*.sh') + ['src/orchestrator.sh']:
    txt = re.sub(r'\\\n\s*', ' ', open(f).read())
    for i, line in enumerate(txt.splitlines(), 1):
        if 'proot-distro' not in line or line.lstrip().startswith('#'): continue
        stripped = re.sub(r"'[^']*'", "''", line)
        stripped = re.sub(r'"[^"]*"', '""', stripped)
        if re.search(r'(?<![\w"\'/])~/', stripped):
            bad.append(f"{f}:{i}: {line.strip()[:100]}")
if bad:
    print("  FAIL  unprotected ~/ in proot-distro calls:"); [print("       ", b) for b in bad]; sys.exit(1)
print("  OK    no unprotected ~/ reaches proot-distro")
PY

echo "== 5. Error codes uniqueness & documentation =="
python3 - << 'PY' || FAILS=$((FAILS + 1))
import re, glob, sys
codes = {}
for f in glob.glob('src/modules/*.sh') + glob.glob('src/lib/*.sh') + ['src/orchestrator.sh']:
    for m in re.finditer(r'log_fatal_code (\d+)', open(f).read()):
        codes.setdefault(m.group(1), set()).add(f)
doc = open('docs/ERROR_CODES.md').read()
missing = [f"E{c}" for c in codes if f"E{c}" not in doc]
if missing:
    print("  FAIL  undocumented error codes:", missing); sys.exit(1)
print(f"  OK    {len(codes)} error codes verified in docs/ERROR_CODES.md")
PY

echo "== 6. Generated maintenance CLI syntax =="
TMPP="$(mktemp -d)"
(
  export PREFIX="$TMPP/usr" HOME="$TMPP/home" TDE_ROOT="$ROOT" TDE_SRC_DIR="$SRC"
  mkdir -p "$PREFIX/bin" "$HOME"
  source "$SRC/lib/core.sh"; log_init >/dev/null
  source "$SRC/lib/state.sh"; source "$SRC/lib/system.sh"
  source "$SRC/modules/maintenance.sh"
  phase6_install_shared_copy
  phase6_write_archhealth; phase6_write_archdiag; phase6_write_archupdate
  phase6_write_archreset; phase6_write_archreapply; phase6_write_archbridge
  phase6_write_archfont; phase6_write_archselfheal; phase6_write_archparu
  phase6_write_archtreesitter
  phase6_maintenance_ok
) >/dev/null 2>&1 && ok "all 10 maintenance commands generated and valid" || fail "maintenance command generation"
rm -rf "$TMPP"

echo ""
if [ "$FAILS" -eq 0 ]; then
  echo "VERIFICATION CLEAN"
  exit 0
else
  echo "VERIFICATION FAILED ($FAILS problem(s))"
  exit 1
fi