# Windows validation report: GNUstep libobjc2 support in LLDB

Validated on Windows 11 / `x86_64-pc-windows-msvc` in two rounds (2026-08-12:
Windows support; 2026-08-16: data formatters). All fixes described here are
commits on `gnustep/integration` (rebased onto current upstream); the
DWARF-parser MS-ABI fix went upstream separately as llvm/llvm-project#216711.

## Headline

The feature works on Windows/MSVC — but only after three fixes, one of them to an
upstream LLDB bug outside the branch. The deepest finding: **CodeView/PDB debug
info cannot carry this feature** (the format has no Objective-C type
representation), so the Windows test recipe hardcoded in `build.py`
(`-gcodeview`) could never have worked. The working recipe is DWARF-in-COFF:
`-gdwarf` at compile, `lld-link /debug:dwarf` at link.

Final state: unit tests pass (33 runtime + 26 formatter cases), all Shell tests PASS as-recorded (XFAILs
removed), API test PASSES, gnustep-2.0/2.1/2.2 identical.

## Results table (§7.1–7.4)

| Suite | Before the fixes | After | Diagnosis |
|---|---|---|---|
| Unit `LanguageRuntimeObjCGNUstepTests` (30) | 30/30 PASS | 30/30 PASS | LLP64 offsets correct as authored |
| Shell `objc-gnustep-print.m` | FAIL — ivars read garbage (`_int = -1264426080`) | PASS | CodeView: no ObjC types → wrong layout path |
| Shell `objc-gnustep-dynamic-types.m` | FAIL — stays `(Base *)` | PASS | CodeView (silent static fallback); DWARF crashed pre-fix (upstream bug) |
| Shell `objc-gnustep-expr.m` | FAIL — `no known method '-addFortyTwoTo:'` | PASS | CodeView: classes parse as C++ structs |
| Shell `objc-gnustep-stepping.m` | FAIL — `step` behaves as `next` | PASS | runtime module misidentified via PE import thunk → step-through gate refused |
| Shell `objc-gnustep-tagged-pointers.m` | FAIL — stays `(objc_object *)` | PASS | CodeView type lookup |
| API `TestGNUstepDynamicValue` (2 active cases) | FAIL — build (coreutils), then launch `0xc0000135` | PASS (both) | Makefile.rules had no Windows link/DLL handling; lldbtest scrubs inferior PATH |
| check-lldb On vs Off | — | **No reproducible regressions** (all non-gnustep deltas vanish on re-run) | Comparison scoped to Shell+API (complete w.r.t. the flag); full check-lldb blocked by Smart App Control (environment, see Surprises) |

## Answers to the three open questions

### §5.2 — Are `$_OBJC_CLASS_` symbols visible to LLDB in a PE binary?

**Yes, with the `$_` prefix exactly as `GetClassSymbolPrefix()` expects — but only
if the binary provides a symbol source.** A linked PE image has no COFF symbol
table by default:

- CodeView route (`-g` → PDB): visible via PDB publics
  (`SymbolFileNativePDB::AddSymbols`). Verified: `image lookup -r -s OBJC_CLASS`
  → `$_OBJC_CLASS_NSObject`, `$_OBJC_CLASS_Base`, `$_OBJC_CLASS_Derived` in the
  test exe.
- Plain DWARF route (`-gdwarf` + default link): **not visible** — SymbolFileDWARF
  wins symbol-file selection, PDB publics are never merged, the sweep finds
  nothing (create-on-miss still resolves dynamic types).
- DWARF + `lld-link /debug:dwarf` (the recipe the fixes adopt): visible via the
  COFF symbol table the linker emits. Expression class-refs
  (`$_OBJC_REF_CLASS_*`) also resolve — without this, `expr [Derived new]` fails
  with `Couldn't look up symbols: $_OBJC_REF_CLASS_Derived`.

### §5.4 — Exact spelling of `__objc_load` as LLDB sees it

**`__objc_load`, verbatim — no extra prefix on x86_64 COFF.** Present in
objc.dll's export table (ordinal 19) and PDB. But: **every importing module
also shows a `__objc_load` symbol** (its import thunk, a valid code address in
`.text`), which made `ModuleDefinesFunction`'s address-validity test identify
the *executable* as the runtime module. The exe also carries the IAT symbol
`__imp___objc_load` — the fix uses that to reject importers. Consequences of
the misidentification before the fix: the step-through gate
(`objc_msg_lookup` in the "runtime module") always refused, and
`IsRuntimeInternalAddress()` classified every exe address as runtime-internal.

### §6.3 — Does gnustep-2.0 vs 2.1 matter on Windows?

**No. Settled.** Same test compiled/linked/debugged at `-fobjc-runtime=`
`gnustep-2.0`, `2.1`, `2.2` against libobjc2 v2.3 with the MSVC toolchain:
identical behavior at every version (compile, link, run, dynamic type resolves
to `Derived *`, message-send expression evaluates). The historical claim traced
to `attic/GNUSTEP_DEBUGGING.md`, where the symptom was a *link-time*
`.objc_selector_*` failure in a MinGW/Conan environment — a different, since
irrelevant problem, as WINDOWS_VALIDATION.md suspected.

## The three fixes

1. `a6da5325dd6a` **[lldb] Guard MS inheritance model against non-CXXRecordDecl
   DWARF types** — *upstream bug, independent of the branch; candidate for its
   own upstream PR.* `DWARFASTParserClang::CompleteRecordType()` unconditionally
   dereferenced `GetAsCXXRecordDecl()` (null for ObjC interfaces) in its
   Microsoft-ABI block. Effect: LLDB crashed (AV in
   `CXXRecordDecl::calculateInheritanceModel`, MicrosoftCXXABI.cpp:222) on ANY
   ObjC type completion from DWARF on an MSVC triple, even static
   `frame variable`. Never seen before because nobody debugs ObjC DWARF with a
   Microsoft-ABI target.
2. `54ab0ab630ae` **[lldb][GNUstep] Ignore PE import thunks when locating the
   runtime** — `ModuleDefinesFunction` now rejects modules that carry
   `__imp_<name>` for the queried symbol. Restores correct runtime-module
   identity on Windows; fixes dispatch step-through.
3. `99fecd3210c0` **[lldb][GNUstep] Build Windows GNUstep tests with DWARF and
   un-XFAIL them** — `build.py`: `-gcodeview` → `-gdwarf`, link `-g` →
   `-Wl,/debug:dwarf`; `Makefile.rules`: same link flag for API tests plus a
   rule copying objc.dll next to the test binary (lldbtest launches inferiors
   with PATH scrubbed on Windows — no PATH-based approach can work, verified
   against `lldbtest.py`'s `target.env-vars PATH=` sanitization); removes
   `XFAIL: system-windows` from all five Shell tests (adjusting the in-file
   breakpoint line numbers for the deleted line).

## Environment record (§9.4)

- Windows 11 Home 10.0.26200, Intel Core Ultra 9 275HX (24C), 31 GB RAM.
- VS Build Tools 2022: MSVC 14.44.35207, Windows SDK 10.0.26100.
- Host compiler for LLVM: clang-cl 22.1.8 (winget LLVM.LLVM release) + lld;
  CMake 4.3.2; Ninja 1.13.2; SWIG 4.4.1 (winget portable); Python 3.12.10
  (python.org via winget, per-user); GNU Make 3.81 (GnuWin32); GNU coreutils
  from Git for Windows (`C:\Program Files\Git\usr\bin`) — required by
  Makefile.rules (`dirname`, `pwd`, `cp`).
- libobjc2: tag v2.3 = `e877e782fb965c4e870d2ecf6aff58dddc6290ae`, built with
  release clang 22.1.8 (plain `clang.exe`, GNU driver — mirrors libobjc2's own
  Windows CI) under vcvars64:
  `cmake -G Ninja -DCMAKE_C_COMPILER=clang.exe -DCMAKE_CXX_COMPILER=clang.exe
  -DCMAKE_BUILD_TYPE=RelWithDebInfo -DTESTS=OFF
  -DCMAKE_INSTALL_PREFIX=C:/code/gnustep-prefix -DCMAKE_POLICY_VERSION_MINIMUM=3.5`
- Prefix layout after fixup (install puts the DLL in `bin\`):
  `lib\objc.dll` (copied), `lib\objc.lib`, `lib\objc.pdb` (copied from build
  tree), `include\objc\*.h`. FindGNUstepObjC.cmake found it; both
  `lit.site.cfg.py` files carried `objc_gnustep_dir = "C:/code/gnustep-prefix"`.
- LLVM configure (vcvars64):
  `cmake -S llvm -B build -G Ninja -DLLVM_ENABLE_PROJECTS="clang;lldb;lld"
  -DCMAKE_BUILD_TYPE=RelWithDebInfo
  -DLLVM_TARGETS_TO_BUILD=X86 -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl
  -DLLVM_ENABLE_LLD=ON -DLLVM_PARALLEL_LINK_JOBS=4 -DLLDB_ENABLE_PYTHON=ON
  -DPython3_EXECUTABLE=<python312> -DLLDB_INCLUDE_TESTS=ON
  -DLLDB_TEST_OBJC_GNUSTEP=On -DLLDB_TEST_OBJC_GNUSTEP_DIR=C:/code/gnustep-prefix
  -DLLDB_TEST_MAKE=<gnuwin32 make> -DSWIG_EXECUTABLE=<swig>`
- The clang `APInt` assertion mentioned in the brief (§6.1) has since been fixed
  upstream (llvm/llvm-project#215753); no assertion setting is required.

## Surprises (§9.5) — beyond §5's list

1. **CodeView is a hard wall, not a bug** — no ObjC semantics in the format;
   with it, the plugin can't work regardless of runtime correctness. Report
   recommendation: Windows requires DWARF-in-COFF for ObjC debugging; the
   feature should document this.
2. **The upstream MS-ABI DWARF crash** (fix 1) — any ObjC-from-DWARF completion
   crashed LLDB on MSVC triples before this branch's feature made the path
   reachable.
3. **PE import thunks defeat "defines vs references" symbol logic** (fix 2) —
   an ELF-ism that doesn't transfer: on COFF, importers DO have a valid-address
   symbol with the imported name.
4. **lldbtest scrubs the inferior's PATH on Windows** (shlib env var
   sanitization), so Windows API tests must co-locate DLLs with test binaries;
   no environment plumbing can reach the inferior.
5. **§6.2 (asm line info breaks stepping) did NOT reproduce on Windows** —
   stepping works with objc.pdb present; clang's CodeView pipeline doesn't give
   the hand-written `.S` dispatch functions line info the way DWARF-on-ELF did.
6. **Smart App Control blocked `check-lldb` wholesale** — it refuses to execute
   one freshly-built unittest binary (`ObjectFileELFTests.exe`,
   CodeIntegrity event 3077/3033, `VerifiedAndReputablePolicyState: 1`),
   killing googletest discovery for the whole run. Per-file allowlisting is not
   possible with SAC; disabling it is irreversible (user decision). Unaffected:
   Shell/API suites and directly-run unit binaries. The regression comparison
   is therefore scoped to Shell+API — complete w.r.t. the GNUstep flag, which
   only feeds those two suites' lit configs.
7. Minor: `lldb.exe` hard-crashes (delay-load AV) rather than degrading when
   `python312.dll` is absent from PATH — pre-existing Windows behavior, worth
   an upstream look someday.

## check-lldb comparison (§7.4)

Scope: `lldb-shell` (789 tests) + `lldb-api` (1481 tests) suites, run twice on
the fixes branch — GNUstep On, then Off (config-flip only; same binaries) —
with xunit output diffed per test. The Unit suite is invariant under the flag
(`LLDB_TEST_OBJC_GNUSTEP` feeds only the Shell/API lit configs) and could not
be run wholesale (Smart App Control blocks `ObjectFileELFTests.exe` at
googletest discovery; see Surprises #6); the GNUstep unit target passes 30/30
run directly.

Headline numbers (On run): Shell 489 pass / 1 fail; API 728 pass / 21 fail /
2 unresolved — a normal pre-existing-failure profile for LLDB on Windows.

Deltas:

- Shell: 6 — five are `objc-gnustep-*.m` PASS(on) → SKIP(off), i.e. the flag
  doing its job; the sixth (`Watchpoint/SetErrorCases.test`, FAIL only in the
  Off run) passes on individual re-run.
- API: 21 — one is `TestGNUstepDynamicValue` PASS(on) → SKIP(off), expected;
  the other 20 flip in BOTH directions across unrelated areas (lldb-dap, STL
  formatters, C++ lang tests). All 20 pass on individual re-run under the
  configuration they had failed in.

**Conclusion: no reproducible regression is attributable to the GNUstep
support or to the fixes.** The bidirectional deltas are run-to-run
nondeterminism: Smart App Control re-judges every freshly rebuilt unsigned
`a.out` inferior (visible as Windows Security toasts during API runs) plus
ordinary Windows LLDB flakiness under 24-way parallelism.

## Round 2: data formatters (sidebar previews) — 2026-08-16

Problem: the VS Code Variables view showed only hex addresses for Foundation
objects, and expanding a custom object recursed forever through `isa`.

Root causes and fixes:

| Fix | What |
|---|---|
| **`isa` recursion** | A root class declaring `id isa` (Apple uses `Class isa`) let `GetDynamicTypeAndAddress` type the *class object* as an instance of its own class (libobjc2 names a metaclass after its class). Descriptors now record the meta flag; class objects get no dynamic type. Unit + Shell test. |
| **Data formatters** | For gnustep-base in `Language/ObjC` (`GNUstepFormatters.*`, `GNUstepNSString/Number/Array/Dictionary.cpp`): strings (tagged `GSTinyString` decoded from pointer bits — clang emits `@"Hello"` as `0x919766cde000002c`; `NSConstantString`; the `GSString` family incl. Latin-1→UTF-8; `GSMutableString`), numbers (tagged + boxed), arrays, dictionaries, sets, data, dates, `NSNull`. Apple-identical output (`@"…"`, `@"N elements"`, `N key/value pairs`, `(int)N`, `YES`). Registered under gnustep-base's concrete class names (picked up via `ObjCLanguage::GetPossibleFormattersMatches`), plus 2-line hand-offs in Apple's providers for static values. **No inferior calls; no hardcoded offsets** — ivars are read by name through the dynamic type's DWARF (libobjc2 packs `instance_size`; `long` ivars differ LP64/LLP64). Not covered: `NSURL` (ivars behind `GS_EXPOSE`, in neither DWARF nor ivar-offset symbols). |
| **`SmallObjectClasses` fallback** | The hidden `SmallObjectClasses` table is found via debug info when no PDB/symtab has it — needed for the tools-windows-msvc `objc.dll` built with `-gdwarf`. |
| **Tests** | Hermetic decoder unit tests; API test `lang/objc-gnustep/data-formatters` gated on new `LLDB_TEST_OBJC_GNUSTEP_BASE_DIR` / `objc-gnustep-base` category (plumbed through lit/dotest/Makefile.rules like the runtime dir); Shell test for the `isa` fix. |

Validation:
- Windows: units 33/33 + 26/26; all 8 GNUstep Shell+API tests pass; scripted lldb-dap session asserts the `variables` payload (29 typed locals, array children `[0] = @"apple"`, dictionary `key`/`value` pairs, custom object `owner = @"Jane"`, subtree at depth 6 = 3 nodes, was infinite).
- **WSL/Linux (LP64, different gnustep-base build)**: units pass; **data-formatters API test passes unchanged** — the by-name ivar route makes the data model irrelevant. (`stepping.m` fails on a WSL build whose libobjc2 carries assembly line info — the §6.2 environment caveat, unrelated to the formatters.)
- Notes: `@30` in a literal is a tagged `NSSmallInt` → prints `(long)30` (only −1…12 are boxed singletons); the reference date decodes ~2 s off because gnustep-base's compressed-double encoding drops mantissa bits (gnustep-base's own `NSLog` prints the same); DAP shows `nil` `id` as `0x0` (pre-existing, unrelated).

Tools repo: `demos/foundation_types_demo.m` + launch config **"foundation types demo (data formatters)"** (`build-foundation.ps1 -Source/-Name`).
