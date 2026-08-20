#!/bin/bash
# Validate the LLDB GNUstep plugin against the libobjc2 build configurations
# we intend to claim support for. Each row builds a real inferior and checks
# what LLDB reports for it.
#
# Usage: config_matrix.sh [workdir]   (default /tmp/cfgmatrix)

set -uo pipefail

# llvm-project is expected next to this repo; override with PROJECT_ROOT=...
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$REPO_ROOT")/llvm-project}"
GNUSTEP_SRC_DIR="${GNUSTEP_SRC_DIR:-$HOME/gnustep-src}"
GNUSTEP_PREFIX="${GNUSTEP_PREFIX:-/usr/local}"
CLANG="$PROJECT_ROOT/build-stage1/bin/clang"
LLDB="$PROJECT_ROOT/build/bin/lldb"
SHELL_TESTS="$PROJECT_ROOT/lldb/test/Shell/Expr"
WORK="${1:-/tmp/cfgmatrix}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC} $1"; }
fail() { echo -e "${RED}FAIL${NC} $1"; }
skip() { echo -e "${YELLOW}SKIP${NC} $1"; }

mkdir -p "$WORK/inc"
cp -r "$GNUSTEP_PREFIX/include/objc" "$WORK/inc/" 2>/dev/null

# Builds an inferior from a Shell test source and prints what LLDB reports for
# a variable, so a row is a one-line comparison.
report_variable() {
    local binary="$1" breakpoint="$2" variable="$3"
    timeout 120 "$LLDB" -b -o "b $breakpoint" -o run \
        -o "frame variable -d run-target $variable" "$binary" 2>&1 |
        grep -oE "\([A-Za-z_][A-Za-z0-9_]* \*\) $variable" | head -1
}

echo "== Row 1: default shared libobjc2 =="
$CLANG -m64 -g -O0 -fobjc-runtime=gnustep-2.1 -I "$GNUSTEP_PREFIX/include" \
    "$SHELL_TESTS/objc-gnustep-dynamic-types.m" -o "$WORK/default.bin" \
    -L"$GNUSTEP_PREFIX/lib" -Wl,-rpath,"$GNUSTEP_PREFIX/lib" -lobjc 2>/dev/null
[ "$(report_variable "$WORK/default.bin" objc-gnustep-dynamic-types.m:47 object)" = "(Derived *) object" ] &&
    pass "dynamic type resolves" || fail "dynamic type"

echo "== Row 3: fully stripped libobjc2 (no symbol table) =="
mkdir -p "$WORK/striplib" && cp -P "$GNUSTEP_PREFIX"/lib/libobjc.so* "$WORK/striplib/" &&
    strip --strip-all "$WORK/striplib"/libobjc.so.4.* 2>/dev/null
$CLANG -m64 -g -O0 -fobjc-runtime=gnustep-2.1 -I "$GNUSTEP_PREFIX/include" \
    "$SHELL_TESTS/objc-gnustep-tagged-pointers.m" -o "$WORK/strip.bin" \
    -L"$WORK/striplib" -Wl,-rpath,"$WORK/striplib" -lobjc 2>/dev/null
out=$(timeout 120 "$LLDB" -b -o "b objc-gnustep-tagged-pointers.m:49" -o run \
    -o "frame variable -d run-target tagged" \
    -o "frame variable -d run-target ordinary" "$WORK/strip.bin" 2>&1)
# The small object class table cannot be found without symbols, so a tagged
# pointer must stay untyped rather than being guessed at - but an ordinary
# object still resolves.
if grep -q "(id) tagged" <<<"$out" && grep -q "(Ordinary \*) ordinary" <<<"$out"; then
    pass "degrades gracefully without symbols"
else
    fail "stripped runtime handling"
fi

echo "== Row 4: statically linked libobjc2 =="
skip "libobjc2's own objc-static target omits arc.mm; static links fail upstream"

echo "== Row 5: renamed libobjc2 (LIBOBJC_NAME) =="
if [ ! -f "$WORK/renamed-build/libobjc2.so" ]; then
    cmake "$GNUSTEP_SRC_DIR/libobjc2" -B "$WORK/renamed-build" -GNinja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CLANG" \
        -DCMAKE_CXX_COMPILER="${CLANG}++" -DGNUSTEP_INSTALL_TYPE=NONE \
        -DTESTS=OFF -DLIBOBJC_NAME=objc2 >/dev/null 2>&1
    ninja -C "$WORK/renamed-build" >/dev/null 2>&1
fi
$CLANG -m64 -g -O0 -fobjc-runtime=gnustep-2.1 -I "$WORK/inc" \
    "$SHELL_TESTS/objc-gnustep-dynamic-types.m" -o "$WORK/renamed.bin" \
    -L"$WORK/renamed-build" -Wl,-rpath,"$WORK/renamed-build" -lobjc2 2>/dev/null
# Detection has to find the runtime by symbol, since the file name no longer
# identifies it.
[ "$(report_variable "$WORK/renamed.bin" objc-gnustep-dynamic-types.m:47 object)" = "(Derived *) object" ] &&
    pass "runtime found by symbol, not file name" || fail "renamed runtime detection"

echo "== Row 6: old-ABI class inside a gnustep-2.x process =="
cat > "$WORK/oldabi.m" <<'EOF'
#import "objc/runtime.h"
__attribute__((objc_root_class))
@interface OldStyle { id isa; }
+ (id)alloc;
@end
@implementation OldStyle
+ (id)alloc { return class_createInstance(self, 0); }
@end
id make_old_object(void) { return [OldStyle alloc]; }
EOF
cat > "$WORK/mixed_main.m" <<'EOF'
#import "objc/runtime.h"
__attribute__((objc_root_class))
@interface NSObject { id isa; int refcount; }
@end
@implementation NSObject
+ (id)new { return class_createInstance(self, 0); }
@end
@interface Modern : NSObject
@end
@implementation Modern
@end
id make_old_object(void);
int main() {
  id modern = [Modern new];
  id old = make_old_object();
  return modern != old;
}
EOF
$CLANG -m64 -g -O0 -fobjc-runtime=gcc -I "$GNUSTEP_PREFIX/include" \
    -c "$WORK/oldabi.m" -o "$WORK/oldabi.o" 2>/dev/null
$CLANG -m64 -g -O0 -fobjc-runtime=gnustep-2.1 -I "$GNUSTEP_PREFIX/include" \
    "$WORK/mixed_main.m" "$WORK/oldabi.o" -o "$WORK/mixed.bin" \
    -L"$GNUSTEP_PREFIX/lib" -Wl,-rpath,"$GNUSTEP_PREFIX/lib" -lobjc 2>/dev/null
# The runtime rewrites old-ABI classes into the current layout when it loads
# them, so they must read back like any other class.
[ "$(report_variable "$WORK/mixed.bin" mixed_main.m:16 old)" = "(OldStyle *) old" ] &&
    pass "old-ABI class reads back correctly" || fail "old-ABI class"

echo "== Row 7: -fobjc-runtime=gnustep-2.0 / 2.1 / 2.2 =="
row7_ok=1
for version in gnustep-2.0 gnustep-2.1 gnustep-2.2; do
    $CLANG -m64 -g -O0 -fobjc-runtime=$version -I "$GNUSTEP_PREFIX/include" \
        "$SHELL_TESTS/objc-gnustep-dynamic-types.m" -o "$WORK/version.bin" \
        -L"$GNUSTEP_PREFIX/lib" -Wl,-rpath,"$GNUSTEP_PREFIX/lib" -lobjc 2>/dev/null
    [ "$(report_variable "$WORK/version.bin" objc-gnustep-dynamic-types.m:47 object)" = "(Derived *) object" ] ||
        { fail "$version"; row7_ok=0; }
done
[ $row7_ok -eq 1 ] && pass "all three runtime versions behave identically"

echo "== Row 8: class created at run time =="
cat > "$WORK/runtime_class.m" <<'EOF'
#import "objc/runtime.h"
__attribute__((objc_root_class))
@interface NSObject { id isa; int refcount; }
@end
@implementation NSObject
+ (id)new { return class_createInstance(self, 0); }
@end
@interface Known : NSObject
@end
@implementation Known
@end
int main() {
  Class made = objc_allocateClassPair(objc_getClass("NSObject"), "MadeAtRuntime", 0);
  objc_registerClassPair(made);
  id runtime_obj = class_createInstance(made, 0);
  id known_obj = [Known new];
  return runtime_obj != known_obj;
}
EOF
$CLANG -m64 -g -O0 -fobjc-runtime=gnustep-2.1 -I "$GNUSTEP_PREFIX/include" \
    "$WORK/runtime_class.m" -o "$WORK/rc.bin" \
    -L"$GNUSTEP_PREFIX/lib" -Wl,-rpath,"$GNUSTEP_PREFIX/lib" -lobjc 2>/dev/null
out=$(timeout 120 "$LLDB" -b -o "b runtime_class.m:17" -o run \
    -o "frame variable -d run-target runtime_obj known_obj" "$WORK/rc.bin" 2>&1)
# The class was registered at run time, so it has neither a class symbol nor
# debug info; its name and layout come from the runtime's metadata alone, via
# the interface the DeclVendor synthesizes. It must resolve just like the
# compiled class beside it.
if grep -q "(MadeAtRuntime \*) runtime_obj" <<<"$out" &&
   grep -q "(Known \*) known_obj" <<<"$out"; then
    pass "runtime-created class resolves to its own type"
else
    fail "runtime-created class"
fi

echo
echo "Rows 2 (bare libobjc2, no Foundation) and 9 (32-bit, big-endian) are"
echo "covered by the Shell tests and the unit tests respectively."
