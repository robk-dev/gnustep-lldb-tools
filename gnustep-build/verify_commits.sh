#!/bin/bash
# Build and test each given commit of llvm-project on its own, the way premerge
# builds a PR, and print one summary line per commit.
#
# Usage: verify_commits.sh <commit>...
#   e.g. verify_commits.sh $(git -C ../llvm-project rev-list --reverse upstream/main..gnustep/pr-series)
#
# PROJECT_ROOT  llvm-project checkout (default: ../llvm-project next to this repo)
# BUILD_DIR     configured LLDB build dir inside it (default: build)
# LOG_DIR       where full build logs go (default: /tmp/gnustep-verify)
#
# Checks out each commit (detached) in PROJECT_ROOT, so the working tree must be
# clean and nothing else may be using the build dir. Per commit: regenerate
# build.ninja (so the target list is that commit's), build lldb, lldb-test and
# whichever GNUstep unit-test targets exist there, run the -Werror sweep over the
# files the series touches, run those unit tests, and run every objc-gnustep
# Shell and API test.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$(dirname "$SCRIPT_DIR")")/llvm-project}"
BUILD_DIR="${BUILD_DIR:-build}"
LOG_DIR="${LOG_DIR:-/tmp/gnustep-verify}"
mkdir -p "$LOG_DIR"
cd "$PROJECT_ROOT" || exit 2
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "working tree not clean; refusing to check out commits" >&2; exit 2
fi
for c in "$@"; do
  sha=$(git rev-parse --short "$c")
  git checkout -q --detach "$sha" || { echo "$sha CHECKOUT FAILED"; continue; }
  ninja -C "$BUILD_DIR" build.ninja > /dev/null 2>&1
  targets=(lldb lldb-test)
  for t in LanguageRuntimeObjCGNUstepTests LanguageObjCTests; do
    ninja -C "$BUILD_DIR" -t targets all 2>/dev/null | grep -q "^$t:" && targets+=("$t")
  done
  if ! ninja -C "$BUILD_DIR" "${targets[@]}" > "$LOG_DIR/build-$sha.log" 2>&1; then
    echo "$(git log -1 --format='%h %s') | BUILD FAILED"
    grep error: "$LOG_DIR/build-$sha.log" | head -5
    continue
  fi
  w=$(PROJECT_ROOT=$PWD bash "$SCRIPT_DIR/werror_sweep.sh" upstream/main 2>&1 |
      grep -E "FAIL|swept" | head -3 | tr '\n' ' ')
  u=""
  for p in LanguageRuntime/ObjC/GNUstepObjCRuntime/LanguageRuntimeObjCGNUstepTests \
           Language/ObjC/LanguageObjCTests; do
    b=$BUILD_DIR/tools/lldb/unittests/$p
    [[ " ${targets[*]} " == *" $(basename $p) "* ]] && [ -x "$b" ] &&
      u+="$(basename $p): $("$b" 2>&1 | grep -E '^\[  (PASSED|FAILED)' | tr '\n' ' ') "
  done
  l=$(./$BUILD_DIR/bin/llvm-lit -s --filter=objc-gnustep \
        $BUILD_DIR/tools/lldb/test/Shell $BUILD_DIR/tools/lldb/test/API 2>&1 |
      grep -E "^(FAIL|UNRESOLVED|XPASS):|^  (Passed|Failed|Unresolved|Unsupported)" | tr '\n' ' ')
  echo "$(git log -1 --format='%h %s') | werror: $w | $u| lit: $l"
done
