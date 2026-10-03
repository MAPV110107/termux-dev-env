#!/usr/bin/env bash
# One verification round. Exit 0 only if every check is clean.
# Usage: tests/verify_all.sh            (run once)
#        tests/verify_all.sh --loop 5   (repeat up to N rounds, stop after 2 clean in a row)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ "${1:-}" = "--loop" ]; then
  max="${2:-5}"; clean=0
  for round in $(seq 1 "$max"); do
    echo "################ ROUND $round/$max ################"
    if bash "$0"; then clean=$((clean + 1)); else clean=0; fi
    [ "$clean" -ge 2 ] && { echo "STABLE: 2 consecutive clean rounds"; exit 0; }
  done
  echo "NOT STABLE after $max rounds"; exit 1
fi

FAILS=0
fail() { echo "  FAIL  $*"; FAILS=$((FAILS + 1)); }
ok()   { echo "  OK    $*"; }

echo "== 1. syntax (bash -n) =="
bad=0
while IFS= read -r f; do bash -n "$f" 2>/dev/null || { fail "syntax: $f"; bad=1; }; done < <(find . -name '*.sh' -not -path './.git/*')
[ "$bad" = 0 ] && ok "all scripts parse"

echo "== 1b. shellcheck (-S warning) =="
# Skipped, not failed, when shellcheck isn't installed: this suite has to
# stay runnable on the target device (Termux), where shellcheck is an
# extra package nobody needs just to install a dev environment. CI always
# has it, so the gate is still enforced on every push.
if command -v shellcheck >/dev/null 2>&1; then
  sc_out="$(shellcheck -S warning -s bash core.sh lib/*.sh components/*.sh tests/*.sh tests/cases/*.sh 2>&1)"
  if [ -z "$sc_out" ]; then ok "shellcheck clean ($(shellcheck --version | awk '/version:/{print $2}'))"
  else fail "shellcheck"; echo "$sc_out" | head -40; fi
else
  echo "  SKIP  shellcheck not installed (pkg install shellcheck / pip install shellcheck-py)"
fi

echo "== 2. unit tests =="
out="$(bash tests/test_pure_logic.sh 2>&1)"
if grep -q "ALL CHECKS PASSED" <<< "$out"; then ok "$(grep -c '^  OK ' <<< "$out") unit checks"; else fail "unit tests"; grep 'FAIL' <<< "$out" | head; fi

echo "== 3. source order trace =="
# Captured into a variable, not grep -q'd off a live pipe: this script
# prints one more line after its "ALL CHECKS PASSED" summary, and
# under `set -o pipefail`, grep -q closing its end early on the first
# match sends SIGPIPE to the still-writing producer — its exit status
# (141) then wins the pipeline's exit code even though the check itself
# genuinely passed. Bit by this exact gotcha writing this file.
trace_out="$(bash tests/trace_source_order.sh 2>&1)"
grep -q "ALL CHECKS PASSED" <<< "$trace_out" && ok "no function used before sourced" || fail "trace_source_order"

echo "== 4. every function that is called is defined somewhere =="
python3 - << 'PY' || FAILS=$((FAILS + 1))
import re, glob, sys
files = [f for f in glob.glob('**/*.sh', recursive=True)]
defs, code = set(), ""
for f in files:
    t = open(f).read()
    defs |= set(re.findall(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{', t, re.M))
    if not f.startswith('tests/'):
        code += "\n".join(l for l in t.splitlines() if not l.lstrip().startswith('#'))
called = set(re.findall(r'\b((?:phase[0-9]_[a-z0-9_]+|log_[a-z_]+|state_[a-z_]+|kv_[a-z_]+|idempotent_append\w*|retry_with_backoff|lock_\w+|diagnose_\w+|container_home|compat_\w+|_[a-z]+_[a-z_]+))\b', code))
# names that are only strings/vars, not calls
ignore = {'log_init','TDE_LOG_FILE'}
missing = sorted(n for n in called - defs - ignore if not n.isupper())
# only report names used as commands (start of a statement or after && || ; ( ! if/then)
real = []
for n in missing:
    if re.search(r'(^|[;&|(!]|\bthen\b|\bif\b|\belse\b|\bdo\b)\s*' + re.escape(n) + r'\b(?!\s*=)', code, re.M):
        real.append(n)
if real:
    print("  FAIL  called but never defined:", ", ".join(real)); sys.exit(1)
print("  OK    no undefined function calls")
PY

echo "== 5. bare ~/ passed to proot-distro (would expand on the Termux side) =="
python3 - << 'PY' || FAILS=$((FAILS + 1))
import re, glob, sys
bad = []
for f in glob.glob('components/*.sh') + glob.glob('lib/*.sh') + ['core.sh']:
    txt = open(f).read()
    # join backslash continuations, then look at each logical proot-distro command line
    txt = re.sub(r'\\\n\s*', ' ', txt)
    for i, line in enumerate(txt.splitlines(), 1):
        if 'proot-distro' not in line or line.lstrip().startswith('#'): continue
        # strip single-quoted spans (protected: expanded remotely)
        stripped = re.sub(r"'[^']*'", "''", line)
        # ignore double-quoted spans too (tilde is not expanded inside them)
        stripped = re.sub(r'"[^"]*"', '""', stripped)
        if re.search(r'(?<![\w"\'/])~/', stripped):
            bad.append(f"{f}: {line.strip()[:110]}")
if bad:
    print("  FAIL  unprotected ~/ in proot-distro calls:"); [print("       ", b) for b in bad]; sys.exit(1)
print("  OK    no unprotected ~/ reaches proot-distro")
PY

echo "== 6. generated maintenance scripts: syntax + every function they call is sourced =="
TMPP="$(mktemp -d)"; export PREFIX="$TMPP/usr" HOME="$TMPP/home"; mkdir -p "$PREFIX/bin" "$HOME"
(
  source lib/error_handling.sh; source lib/logging.sh; log_init >/dev/null
  source lib/kv.sh; source lib/state.sh; source lib/network.sh; source lib/idempotent_append.sh
  source lib/container_paths.sh
  source components/install_maintenance.sh
  phase6_write_archhealth; phase6_write_archdiag; phase6_write_archupdate
  phase6_write_archreset; phase6_write_archreapply; phase6_write_archbridge
  phase6_write_archfont; phase6_write_archselfheal; phase6_write_archparu
) >/dev/null 2>&1
for s in archhealth archdiag archupdate archreset archreapply archbridge archfont archselfheal archparu; do
  [ -f "$PREFIX/bin/$s" ] || { fail "$s not generated"; continue; }
  bash -n "$PREFIX/bin/$s" 2>/dev/null || fail "$s syntax"
done
# closure: only the functions actually REACHABLE from what archhealth/
# archdiag call (phase5_run_audit, transitively phase5_self_heal) — not
# every phaseN_ name anywhere in verify_functional.sh, which would also
# catch phase5_run's own phase5_cleanup even though archhealth/archdiag
# never call phase5_run at all (only phase5_run_audit). A first version
# of this check did exactly that and flagged a function that was never
# actually going to be invoked.
python3 - "$PREFIX/bin" "$ROOT" << 'PY' || FAILS=$((FAILS + 1))
import re, sys, os
binp, root = sys.argv[1:3]

def all_defs():
    d = {}
    for sub in ('components', 'lib'):
        for fn in os.listdir(os.path.join(root, sub)):
            if not fn.endswith('.sh'): continue
            rel = f'{sub}/{fn}'
            for name in re.findall(r'^\s*([A-Za-z_]\w*)\s*\(\)\s*\{', open(os.path.join(root, rel)).read(), re.M):
                d[name] = rel
    return d

def body_of(name, text):
    m = re.search(r'^\s*' + re.escape(name) + r'\s*\(\)\s*\{', text, re.M)
    if not m: return ''
    depth, i = 0, m.end()
    start = i
    depth = 1
    while depth > 0 and i < len(text):
        if text[i] == '{': depth += 1
        elif text[i] == '}': depth -= 1
        i += 1
    return text[start:i]

DEFS = all_defs()
vf_text = open(os.path.join(root, 'lib/verify_functional.sh')).read()

def reachable_from(entry, seen=None):
    seen = seen or set()
    if entry in seen: return seen
    seen.add(entry)
    src = DEFS.get(entry)
    text = vf_text if entry not in DEFS else open(os.path.join(root, src)).read()
    body = body_of(entry, text)
    for called in set(re.findall(r'\b(phase[0-9]_\w+|_audit_\w+|_cleanup_\w+)\b', body)):
        if called != entry:
            reachable_from(called, seen)
    return seen

needed = reachable_from('phase5_run_audit')
bad = []
for script in ('archhealth', 'archdiag'):
    txt = open(os.path.join(binp, script)).read()
    sourced = re.findall(r'^\s*source\s+((?:lib|components)/[\w.]+)', txt, re.M)
    known = set()
    for s in sourced:
        known |= set(re.findall(r'^\s*([A-Za-z_]\w*)\s*\(\)\s*\{', open(os.path.join(root, s)).read(), re.M))
    for n in sorted(needed):
        if n in DEFS and n not in known:
            bad.append(f"{script} does not source {DEFS[n]} but needs {n} (reachable from phase5_run_audit)")
if bad:
    print("  FAIL  self-heal closure:"); [print("       ", b) for b in sorted(set(bad))]; sys.exit(1)
print(f"  OK    archhealth/archdiag source everything phase5_run_audit can reach ({len(needed)} functions checked)")
PY
rm -rf "$TMPP"

echo "== 7. every E-code is documented, none duplicated for different messages =="
python3 - << 'PY' || FAILS=$((FAILS + 1))
import re, glob, sys
codes = {}
for f in glob.glob('components/*.sh') + glob.glob('lib/*.sh') + ['core.sh']:
    for m in re.finditer(r'log_fatal_code (\d+) "([^"]{0,40})', open(f).read()):
        codes.setdefault(m.group(1), set()).add(f)
doc = open('docs/ERROR_CODES.md').read()
missing = [c for c in codes if f"E{c}" not in doc]
dup = {c: fs for c, fs in codes.items() if len(fs) > 1}
if missing: print("  FAIL  undocumented:", missing); sys.exit(1)
if dup: print("  FAIL  same code in several files:", dup); sys.exit(1)
print(f"  OK    {len(codes)} codes, all documented, all unique")
PY

echo "== 8. full dry-run of core.sh (fake aarch64 Termux), plain and each --reinstall =="
FAKE="$(mktemp -d)"; export PREFIX="$FAKE/usr" HOME="$FAKE/home"; mkdir -p "$PREFIX/bin" "$PREFIX/tmp" "$HOME"
for c in pkg termux-wake-lock proot-distro; do printf '#!/bin/sh\nexit 0\n' > "$PREFIX/bin/$c"; done
printf '#!/bin/sh\ncase "$1" in -m) echo aarch64;; *) exec /usr/bin/uname "$@";; esac\n' > "$PREFIX/bin/uname"
chmod +x "$PREFIX/bin/"*
# phase 1 insists on the real Termux prefix path; skip that single check by making a matching path if possible
if mkdir -p /data/data/com.termux/files/usr/bin /data/data/com.termux/files/usr/tmp /data/data/com.termux/files/home 2>/dev/null; then
  cp "$PREFIX/bin/"* /data/data/com.termux/files/usr/bin/
  export PREFIX=/data/data/com.termux/files/usr HOME=/data/data/com.termux/files/home
  rm -rf "$HOME/.config"
  for args in "--dry-run" "--dry-run --reinstall=3" "--dry-run --reinstall=6"; do
    o="$(PATH="$PREFIX/bin:$PATH" timeout 120 bash core.sh $args 2>&1)"; rc=$?
    if [ $rc -eq 0 ] && grep -q "installation complete" <<< "$o" && ! grep -q "FATAL" <<< "$o"; then ok "core.sh $args"; else fail "core.sh $args (rc=$rc)"; grep FATAL <<< "$o" | head -3; fi
  done
  rm -rf /data/data/com.termux
else
  echo "  SKIP  cannot create /data/data/com.termux here"
fi
rm -rf "$FAKE"

echo "== 9. idempotency: helpers applied 3x change nothing after the first =="
T="$(mktemp -d)"; export HOME="$T"
(
  source lib/idempotent_append.sh
  f="$T/x.conf"; echo base > "$f"
  idempotent_append "$f" blk "content"; h1="$(md5sum < "$f")"
  idempotent_append "$f" blk "content"; idempotent_append "$f" blk "content"; h3="$(md5sum < "$f")"
  [ "$h1" = "$h3" ]
) && ok "idempotent_append stable" || fail "idempotent_append not idempotent"
rm -rf "$T"

echo
if [ "$FAILS" -eq 0 ]; then echo "ROUND CLEAN"; exit 0; else echo "ROUND FOUND $FAILS PROBLEM(S)"; exit 1; fi
