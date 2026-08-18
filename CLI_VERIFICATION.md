# Verifying the GNUstep LLDB support from the command line

Everything the VS Code launch configs do can be driven from `lldb.exe`
directly. This is the quickest way to check a build, and the commands below
are the ones the tests and demos assert on.

Layout assumed (see README): this repo next to `llvm-project` (built at
`build\`), `gnustep-prefix` (libobjc2 v2.3) and `gnustep-msvc\x64\Release`
(gnustep-base from tools-windows-msvc). Adjust paths otherwise.

## 0. Environment (PowerShell)

```powershell
# lldb.exe needs python312.dll; the inferiors need the runtime/Foundation DLLs.
$env:Path = "C:\code\gnustep-msvc\x64\Release\bin;C:\code\gnustep-prefix\lib;" +
            "$env:LOCALAPPDATA\Programs\Python\Python312;" + $env:Path
$lldb = "C:\code\llvm-project\build\bin\lldb.exe"

# Build the demos (each script derives its paths from its own location).
powershell -NoProfile -ExecutionPolicy Bypass -File demos\build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File demos\build-foundation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File demos\build-foundation.ps1 `
    -Source demos\foundation_types_demo.m -Name foundation_types_demo
```

`-b` (batch) below runs the `-o` commands and exits; drop it to stay in the
interactive prompt after they run.

## 1. Runtime detection, dynamic types, tagged pointers, `po`, expressions

Bare libobjc2, no Foundation:

```powershell
& $lldb -b -o "br set -p 'break here: inspect' -f runtime_demo.m" -o "run" `
  -o "frame variable -d run-target shapes[0] shapes[1] shapes[2]" `
  -o "frame variable -d run-target tiny" `
  -o "expr (double)[shapes[1] area]" `
  -o "po shapes[1]" `
  -- demos\out\runtime_demo.exe
```

Expect `(Square *) shapes[0]`, `(Circle *) shapes[1]`, `(Shape *) shapes[2]`
(dynamic types; the static type is `Shape *` for all three - printing the
whole C array as one value lists raw pointers, dynamic types apply per
element); `(TinyInt *) tiny = 0x0000000000000151` (a
tagged pointer resolved through the runtime's small-object table); the
expression evaluating to `3.14159…`; `po` printing `<Circle: 0x…>` (via the
program's own `_NSPrintForDebugger`).

Real Foundation (gnustep-base):

```powershell
& $lldb -b -o "br set -p 'break here' -f foundation_types_demo.m" -o "run" `
  -o "frame variable -d run-target tinyString constantString unicodeBuilt" `
  -o "frame variable -d run-target boolYes smallInt taggedInt floatNumber" `
  -o "frame variable -d run-target fruits person colors data epoch null" `
  -o "frame variable -d run-target fruits[0] person[0] colors[0]" `
  -o "frame variable -d run-target *account" `
  -o "po fruits" -o "po person" -o "po account" `
  -o "expr (id)[fruits objectAtIndex:1]" -o "po [fruits objectAtIndex:1]" `
  -- demos\out\foundation_types_demo.exe
```

Expect the data-formatter output, identical in shape to Apple's LLDB:

```
(GSTinyString *) tinyString = 0x91a4000000000014 @"Hi"
(NSConstantString *) constantString = 0x… @"A constant string literal"
(GSCInlineString *) unicodeBuilt = 0x… @"ünïcödé 7"
(NSBoolNumber *) boolYes = 0x… YES
(NSIntNumber *) smallInt = 0x… (int)5
(NSSmallInt *) taggedInt = 0x00000000000f1201 (long)123456
(NSSmallFloat *) floatNumber = 0x3ff8000000000005 (float)1.500000
(GSInlineArray *) fruits = 0x… @"3 elements"
(GSDictionary *) person = 0x… 3 key/value pairs
(GSSet *) colors = 0x… 3 elements
(NSDataMalloc *) data = 0x… 12 bytes
(GSSmallDate *) epoch = 0x0880000000000006 2001-01-01 00:00:02 UTC
(NSNull *) null = 0x… <null>
(GSTinyString *) fruits[0] = 0x… @"apple"
(__lldb_autogen_nspair) person[0] = { key = … @"skills"  value = … @"2 elements" }
(Account) *account = { … owner = … @"Jane"  balance = … (double)1234.5  tags = … @"2 elements" }
(lldb) po fruits
(apple, banana, cherry)
(lldb) po account
<Account Jane: 1234.5>
(lldb) expr (id)[fruits objectAtIndex:1]
(GSTinyString *) $0 = 0xc587761dd8400034 @"banana"
```

`po` runs the object's real `-description` through gnustep-base's
`_NSPrintForDebugger` (supplied by `demos/foundation_shim.m`, because
gnustep-base does not export it on MSVC). Everything else — dynamic types,
summaries, children — reads memory only and never runs code in the program.

Notes: `@30` prints as `(long)30` (it is a tagged `NSSmallInt`; only −1…12
are boxed singletons); the reference date is a couple of seconds off because
gnustep-base's compressed date encoding drops mantissa bits — its own
`NSLog` prints the same. `NSURL` has no summary (its ivars are hidden behind
`GS_EXPOSE`); `po url` still works.

## 2. Stepping through `objc_msgSend`

```powershell
& $lldb -b -o "br set -p 'step here: Foundation' -f foundation_types_demo.m" `
  -o "br set -p 'step here: user class' -f foundation_types_demo.m" -o "run" `
  -o "step" -o "frame info" -o "finish" `
  -o "continue" -o "step" -o "frame info" -o "finish" `
  -- demos\out\foundation_types_demo.exe
```

Expect the first `step` to stop in
`gnustep-base-1_31.dll`-[GSArray count](self=@"3 elements", …) at GSArray.m:259`
and `finish` to report `Return value: (NSUInteger) $0 = 3`; the second `step`
to stop in `-[Account description]` in `foundation_types_demo.m` and `finish`
to report `@"<Account Jane: 1234.5>"`. LLDB stopped *in the method*, not in
`objc_msgSend`'s assembly: the runtime plugin's step-through plan asked the
runtime for the method's address. A message to `nil` is stepped over.

The same thing with the bare runtime: break at `break here: step into` in
`runtime_demo.m` and `step` lands in `-[Square area]`.

## 3. Class objects are not instances

```powershell
& $lldb -b -o "br set -p 'break here: inspect' -f runtime_demo.m" -o "run" `
  -o "frame variable -d run-target -T *shapes[0]" -- demos\out\runtime_demo.exe
```

Expect a finite object with `(id) isa = 0x…` — the class object keeps its
static `id` type instead of being shown as a `Square` instance (which used to
recurse forever in the Variables view).

## 4. Where the debugger finds things

```powershell
& $lldb -b -o "br set -p 'break here' -f foundation_types_demo.m" -o "run" `
  -o "image lookup -s __objc_load" `
  -o 'image lookup -s $_OBJC_CLASS_NSObject' `
  -o "image lookup -s SmallObjectClasses" `
  -o "type summary info fruits" `
  -o "type synthetic info fruits" `
  -- demos\out\foundation_types_demo.exe
```

`__objc_load` is reported in `objc.dll` (its definition - this identifies the
runtime) *and* in the executable (an import thunk with the same name; the
plugin tells them apart by the exe's `__imp___objc_load`). `$_OBJC_CLASS_*`
symbols - here in `gnustep-base-1_31.dll`'s export table - seed the class map.
`SmallObjectClasses` in `objc.dll` types tagged pointers (found via PDB, COFF
symtab, or debug info). The last two print which formatter is attached:
`GNUstep NSArray summary provider` / `GNUstep NSArray synthetic children`.

## 5. The automated equivalents

- Unit: `build\tools\lldb\unittests\LanguageRuntime\ObjC\GNUstepObjCRuntime\LanguageRuntimeObjCGNUstepTests.exe`
  and `build\tools\lldb\unittests\Language\ObjC\LanguageObjCTests.exe`.
- Shell + API: `python build\bin\llvm-lit.py -v --filter=objc-gnustep build\tools\lldb\test\Shell build\tools\lldb\test\API`
  (needs `-DLLDB_TEST_OBJC_GNUSTEP=On -DLLDB_TEST_OBJC_GNUSTEP_DIR=… ` and,
  for the data-formatter test, `-DLLDB_TEST_OBJC_GNUSTEP_BASE_DIR=…`).

## 6. Stepping off the end of `main`

`next`/`step` past `main`'s closing brace stops in
`__scrt_common_main_seh` (then `BaseThreadInitThunk`, `RtlUserThreadStart`):
the MSVC C runtime's startup code that called `main`. Those routines are
precompiled into the CRT without source or line tables, so the debugger can
only show disassembly there. This is the normal end-of-program experience on
every platform (macOS shows `start`/dyld, Linux `__libc_start_call_main`)
and unrelated to the Objective-C support; use Continue or Step Out at the
last line instead of stepping out of `main`.
