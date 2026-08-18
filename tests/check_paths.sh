#!/bin/bash
# Path-derivation and de-personalization checks for this repo.
#
# Verifies that:
#   1. no personal hardcoded paths remain in tracked files,
#   2. every shell script parses (bash -n),
#   3. the scripts derive PROJECT_ROOT from their own location (sibling
#      llvm-project of wherever the repo lives), independent of the CWD,
#      and that a PROJECT_ROOT env override always wins.
#
# Run from anywhere, on Linux/WSL or Git Bash on Windows:
#   bash tests/check_paths.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
FAILURES=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }

# --- 1. No personal paths in tracked files ---------------------------------
if git -C "$REPO_ROOT" grep -nI -e "/home/robk" -e "kardjali" -- . ":(exclude)tests/check_paths.sh" >/dev/null 2>&1; then
    fail "personal hardcoded paths still present:"
    git -C "$REPO_ROOT" grep -nI -e "/home/robk" -e "kardjali" -- . ":(exclude)tests/check_paths.sh" >&2
else
    pass "no personal hardcoded paths in tracked files"
fi

# --- 2. Every shell script parses ------------------------------------------
SYNTAX_OK=1
while IFS= read -r script; do
    if ! bash -n "$REPO_ROOT/$script" 2>/dev/null; then
        fail "syntax error: $script"
        SYNTAX_OK=0
    fi
done < <(git -C "$REPO_ROOT" ls-files '*.sh')
[ "$SYNTAX_OK" = 1 ] && pass "all tracked shell scripts parse (bash -n)"

# --- 3. Derivation is location-based, not CWD-based ------------------------
# Each entry script must resolve PROJECT_ROOT to the sibling llvm-project of
# the repo, no matter where the caller's CWD is. We copy the script's actual
# derivation lines into a probe file IN THE SAME DIRECTORY (so BASH_SOURCE
# behaves identically) and execute that.
derive() { # $1 = script abs path, $2 = cwd to run from
    local dir tmp out
    dir="$(dirname "$1")"
    tmp="$(mktemp "$dir/.derive_probe_XXXXXX")"
    {
        sed -n "1,45p" "$1" |
            grep -E "^(SCRIPT_DIR|REPO_ROOT|WORKSPACE_ROOT|HELPERS_DIR|PROJECT_ROOT)="
        echo 'echo "$PROJECT_ROOT"'
    } >"$tmp"
    out="$( (cd "$2" && bash "$tmp") 2>/dev/null )"
    rm -f "$tmp"
    printf '%s\n' "$out"
}

EXPECTED="$(dirname "$REPO_ROOT")/llvm-project"
for rel in gnustep-build/config_matrix.sh scripts-wsl/setup.sh; do
    for cwd in "$REPO_ROOT" /; do
        got="$(derive "$REPO_ROOT/$rel" "$cwd")"
        if [ "$got" = "$EXPECTED" ]; then
            pass "$rel derives PROJECT_ROOT correctly (cwd=$cwd)"
        else
            fail "$rel derived '$got' (cwd=$cwd), expected '$EXPECTED'"
        fi
    done
done

# Env override must win.
got="$(PROJECT_ROOT=/custom/override derive "$REPO_ROOT/gnustep-build/config_matrix.sh" /)"
if [ "$got" = "/custom/override" ]; then
    pass "PROJECT_ROOT env override wins"
else
    fail "PROJECT_ROOT env override ignored (got '$got')"
fi

# helpers/common.sh derives one level deeper.
got="$(bash -c 'source "'"$REPO_ROOT"'/gnustep-build/helpers/common.sh" >/dev/null 2>&1; echo "$PROJECT_ROOT"')"
if [ "$got" = "$EXPECTED" ]; then
    pass "helpers/common.sh derives PROJECT_ROOT correctly"
else
    fail "helpers/common.sh derived '$got', expected '$EXPECTED'"
fi

echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo "ALL CHECKS PASSED"
else
    echo "$FAILURES CHECK(S) FAILED"
    exit 1
fi
