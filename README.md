# gnustep-lldb-tools

Dev tooling for the GNUstep/libobjc2 LLDB upstreaming project
(<https://github.com/robk-dev/llvm-project>). Lives outside the LLVM tree so
the feature branch stays a pure upstream diff.

The feature being developed is Objective-C debugging support in LLDB for the
GNUstep [libobjc2](https://github.com/gnustep/libobjc2) runtime — the runtime
used on the platforms that have none of their own, Linux and Windows. It
covers dynamic types, tagged pointers, `po`, stepping through message
dispatch, expression evaluation, and data formatters for the gnustep-base
Foundation classes.

**Start with [HANDOVER.md](HANDOVER.md)** — branch state, verified test numbers,
what remains, and the working rules that are easy to get wrong.

## Repository layout

| Path | Purpose |
|---|---|
| `demos/` | Debugging demos: `runtime_demo.m` (bare libobjc2) and `foundation_types_demo.m` (every Foundation type, for the formatters). Built by `Makefile` on Linux and `build*.ps1` on Windows. |
| `examples/` | `simple_test.m`, the small Foundation program the "foundation demo" debugs |
| `.vscode/` | `launch.json` / `tasks.json` for both platforms, wired to the sibling build's `lldb-dap` |
| `scripts-wsl/` | Two-stage LLVM/LLDB build for Linux/WSL (`setup.sh`) |
| `gnustep-build/` | Linux/WSL GNUstep stack build (`helpers/gnustep_operations.sh`) and `config_matrix.sh`, the libobjc2 configuration sweep |
| `patches/` | gnustep-base patches for Windows, in `tools-windows-msvc --patches` form |
| `tests/` | `check_paths.sh` — path-derivation and de-personalization checks |
| `CLI_VERIFICATION.md` | Copy-pasteable `lldb` command lines that verify every feature, with expected output |
| `WINDOWS_VALIDATION_RESULTS.md` | What was validated on Windows, how, and what was fixed |

Every script derives its paths from its own location and expects the
`llvm-project` checkout to sit **next to this repo** (`<parent>/llvm-project`);
export `PROJECT_ROOT` to override. Machine conventions (`/usr/local`,
`$HOME/gnustep-src`) are env-overridable defaults.

---

## Setup: Linux / WSL

Expect a few hours, most of it the two LLVM builds.

**1. Build dependencies**

```bash
bash gnustep-build/helpers/gnustep_operations.sh install-deps
```

**2. Build LLVM/LLDB** (stage 1 clang+lld, then stage 2 LLDB built with it)

```bash
bash scripts-wsl/setup.sh
```

Stage 1 exists because libobjc2 and every Objective-C test program need a
clang, and building them all with one compiler keeps runtime metadata
consistent. The result is `../llvm-project/build/bin/{lldb,lldb-dap,clang}`.

**3. Build the GNUstep stack** (libobjc2 → tools-make → gnustep-base)

```bash
bash gnustep-build/helpers/gnustep_operations.sh build-all
```

Pinned to libobjc2 `v2.3`, tools-make `make-2_9_3`, libs-base `base-1_31_1`,
installed to `/usr/local` (needs sudo; override with `GNUSTEP_INSTALL_DIR`).

**4. Point the test suites at the runtime** and rebuild:

```bash
cmake -DLLDB_TEST_OBJC_GNUSTEP=On \
      -DLLDB_TEST_OBJC_GNUSTEP_DIR=/usr/local \
      -DLLDB_TEST_OBJC_GNUSTEP_BASE_DIR=/usr/local ../llvm-project/build
ninja -C ../llvm-project/build lldb lldb-dap lldb-server clang
```

Without these the GNUstep tests are silently *skipped*, which reads like
success — check that `build/tools/lldb/test/Shell/lit.site.cfg.py` really
contains your prefix before trusting a green run.

**5. Verify**

```bash
# in-tree tests
../llvm-project/build/bin/llvm-lit -v --filter=objc-gnustep \
    ../llvm-project/build/tools/lldb/test/Shell \
    ../llvm-project/build/tools/lldb/test/API

# libobjc2 configuration sweep (stripped, renamed, old ABI, runtime versions…)
bash gnustep-build/config_matrix.sh
```

`CLI_VERIFICATION.md` has hand-run `lldb` command lines with expected output
if you want to see each feature directly.

### Known Linux gotchas

- **Rebuild the stage 1 tablegens after rebasing onto newer upstream.** The
  stage 2 build is configured with `LLVM_TABLEGEN`/`CLANG_TABLEGEN` pointing at
  the stage 1 binaries, so after pulling in upstream changes those binaries are
  older than the `.td` files they process and the generated `.inc` files no
  longer match their headers. The failure looks like unrelated compile errors
  in generated code, e.g. `RuntimeLibcalls.inc:… does not match any
  declaration`. Fix with:

  ```bash
  ninja -C ../llvm-project/build-stage1 llvm-tblgen clang-tblgen
  ```

- **`BUILD_SHARED_LIBS=ON` does not protect you from stale executables.**
  `ninja lldb` builds only what `lldb` depends on, so sibling tools such as
  `lldb-test` keep their old object code while the `.so`s they load are
  rebuilt. The mismatch shows up as nonsense far from anything you changed —
  in one case `lldb-test -dump-clang-ast` asserting `TUDecl might have been
  reset by 'cleanup'` on a two-line C++ file. Before concluding a tool is
  broken, rebuild it. `ninja -C ../llvm-project/build lldb-test-depends` builds
  everything the test suites need, and is also what makes the Shell suite
  meaningful: without it around a hundred `SymbolFile/DWARF` tests fail purely
  because `yaml2obj`, `llvm-dwarfdump` and friends were never built.
- **The `APInt` assertion is fixed** — it was an upstream clang bug affecting
  GNUstep classes with ivars, resolved by llvm/llvm-project#215753. An
  assertions-enabled build now runs the full GNUstep Shell suite clean; there
  is no longer any reason to pass `-DLLVM_ENABLE_ASSERTIONS=OFF`.
- **Stepping into a message send lands in the runtime's assembly** if libobjc2
  was built with debug info covering its hand-written dispatch functions,
  because LLDB then has source to step into. Stepping into the *method* still
  works either way; only where a nil-receiver send lands differs. A runtime
  with `objcopy --strip-debug` applied behaves like a distribution package.

---

## Setup: Windows

Validated on Windows 11 with `x86_64-pc-windows-msvc`;
`WINDOWS_VALIDATION_RESULTS.md` records the exact toolchain versions and every
command used.

**1. Tooling.** VS Build Tools 2022 (MSVC + Windows SDK), clang/clang-cl and
lld (winget `LLVM.LLVM`), CMake, Ninja, SWIG, Python 3.12 (python.org build —
`lldb-dap` needs `python312.dll` on PATH), GNU Make and GNU coreutils
(Git for Windows' `usr\bin` supplies the `dirname`/`pwd`/`cp` that
`Makefile.rules` needs). Run the builds from a `vcvars64` shell.

**2. libobjc2** into a sibling `gnustep-prefix`:

```
cmake -S libobjc2 -B libobjc2-build -G Ninja ^
  -DCMAKE_C_COMPILER=clang.exe -DCMAKE_CXX_COMPILER=clang.exe ^
  -DCMAKE_BUILD_TYPE=RelWithDebInfo -DTESTS=OFF ^
  -DCMAKE_INSTALL_PREFIX=<parent>\gnustep-prefix
ninja -C libobjc2-build install
```

Then **copy `objc.dll` from `bin\` into `lib\`**: LLDB's
`FindGNUstepObjC.cmake` looks for `lib\objc.dll`, and if it does not find it
every test is skipped rather than failed.

**3. LLVM/LLDB** with clang-cl, `-DLLVM_ENABLE_ASSERTIONS=OFF`, and
`-DLLDB_TEST_OBJC_GNUSTEP=On -DLLDB_TEST_OBJC_GNUSTEP_DIR=<prefix>`. The full
invocation is in `WINDOWS_VALIDATION_RESULTS.md`.

**4. gnustep-base** (only needed for the Foundation demos and formatter
tests) via [gnustep/tools-windows-msvc](https://github.com/gnustep/tools-windows-msvc),
applying the patches in `patches/` with its `--patches` flag, installed to a
sibling `gnustep-msvc`.

### Known Windows gotchas

- **Build the tests with DWARF, not CodeView.** CodeView cannot represent
  Objective-C types: with `-gcodeview`, dynamic types silently fall back to
  the static type, ivars read from the wrong offsets, and expressions reject
  message sends. The in-tree test helper now uses `-gdwarf` with
  `lld-link /debug:dwarf`, which is also what makes the runtime metadata
  symbols visible.
- **gnustep-base does not dllexport `_NSPrintForDebugger`**, which `po` calls.
  `demos/foundation_shim.m` defines it in the executable to work around this.

---

## Debugging in VS Code (either platform)

1. Install the **LLDB DAP** extension (`llvm-vs-code-extensions.lldb-dap`).
   No settings are needed: the configs point at the sibling build's
   `lldb-dap` directly.
2. Open this folder and pick a configuration:

| Configuration | Debugs | Needs |
|---|---|---|
| **runtime demo (bare libobjc2)** | `demos/runtime_demo.m` | libobjc2 only |
| **foundation demo (gnustep-base)** | `examples/simple_test.m` | gnustep-base |
| **foundation types demo (data formatters)** | `demos/foundation_types_demo.m` | gnustep-base |

Each has a pre-launch task that builds it — `make` on Linux, PowerShell on
Windows — so F5 is all that is required.

The **foundation types demo** is the one to look at: its locals cover every
core Foundation type, so the Variables view shows `@"Hello"`, `@"3 elements"`,
`3 key/value pairs`, `(int)5`, dates, `<null>` and expandable
array/dictionary/set children — the presentation Apple's LLDB gives on macOS.
Its two `// step here` lines are where Step Into (F11) demonstrates
`objc_msgSend` step-through, into gnustep-base's `-[GSArray count]` and into
the demo's own `-[Account description]`.

If a demo builds but will not launch, check that `lldb-dap` exists in the
sibling build (`ninja -C ../llvm-project/build lldb-dap`).
