#!/usr/bin/env bash
# Compile every C++ translation unit this branch touches with -Werror.
#
# The local build is configured LLVM_ENABLE_WERROR=OFF while premerge builds
# with it on, so warnings that fail CI compile silently here. This is
# syntax-only and takes seconds, unlike reconfiguring and rebuilding.
#
# Usage: bash gnustep-build/werror_sweep.sh [upstream-ref]
set -u
ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/llvm-project}"
BASE="${1:-upstream/main}"
cd "$ROOT" || exit 1

[ -f build/compile_commands.json ] || {
    echo "no build/compile_commands.json - configure with CMAKE_EXPORT_COMPILE_COMMANDS=ON" >&2
    exit 1
}

mapfile -t CMDS < <(python3 - "$BASE" <<'PY'
import json, re, subprocess, sys
base = sys.argv[1]
ours = set(subprocess.run(['git','diff',base,'--name-only'],
                          capture_output=True, text=True).stdout.split())
db = json.load(open('build/compile_commands.json'))
seen = set()
for e in db:
    f = e['file']
    rel = f[f.find('lldb/'):] if 'lldb/' in f else f
    if rel in ours and rel not in seen and rel.endswith('.cpp'):
        seen.add(rel)
        # syntax-only: no object file, no link, just the diagnostics
        print(re.sub(r'-o \S+', '', e['command']).replace(' -c ', ' -fsyntax-only ') + ' -Werror')
PY
)

fail=0
for cmd in "${CMDS[@]}"; do
    file=$(grep -oE '[^ ]+\.cpp' <<<"$cmd" | tail -1)
    out=$(bash -c "$cmd" 2>&1 | grep -E 'error:' | head -3)
    if [ -n "$out" ]; then
        printf 'FAIL %s\n%s\n' "${file##*/lldb/}" "$(sed 's/^/     /' <<<"$out")"
        fail=1
    fi
done
printf '%d translation units swept with -Werror: %s\n' "${#CMDS[@]}" \
       "$([ $fail -eq 0 ] && echo 'all clean' || echo 'FAILURES ABOVE')"

# LLVM's code_formatter job runs darker (black, restricted to changed lines) as
# well as clang-format, and a C++-only sweep misses it - that is how a wrapped
# self.expect() reached CI. darker is often not installed; say so rather than
# pretend the check ran.
if ! command -v darker >/dev/null 2>&1; then
    echo "darker not found - Python formatting NOT checked (pip install darker)" >&2
else
    PYFILES=()
    while IFS= read -r f; do PYFILES+=("$f"); done \
        < <(git diff --name-only "$BASE"...HEAD | grep '\.py$')
    if [ "${#PYFILES[@]}" -gt 0 ]; then
        if darker --check --diff -r "$BASE"...HEAD "${PYFILES[@]}" >/dev/null 2>&1; then
            printf '%d Python files checked with darker: all clean\n' "${#PYFILES[@]}"
        else
            echo "darker reports formatting differences:" >&2
            darker --check --diff -r "$BASE"...HEAD "${PYFILES[@]}" >&2
            fail=1
        fi
    fi
fi

exit $fail

