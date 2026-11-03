# Upstreaming plan

Source branch: `gnustep/pr-series` (27 commits on `upstream/main`
`dc057e33a1be`), **one commit per upstream PR**, in dependency order. Every
commit builds on its own with `-Werror`, is clang-format and darker clean
against its parent, and passes every GNUstep test that exists at that point.
A PR branch is just the prefix of the series that ends at its commit
(`upstream-pr/NN-*`). **`HANDOVER.md` is the source of truth** for the
current SHA, what is pushed, and how to verify; this file covers only the plan.

LLVM squash-merges, so **the PR description becomes the commit message**. That
includes its `Assisted-by:` trailer, which the commits' own trailers do not
survive to provide.

**Landed**

- [#216710](https://github.com/llvm/llvm-project/pull/216710): guard the CRT
  debug report calls with `_MSC_VER`. Merged as `85413b1277e2`.

**Open**

- [#216709](https://github.com/llvm/llvm-project/pull/216709): the overview.
  A draft, not for merge. The refreshed description is
  `drafts/pr-216709-description-r4.md`.
- [#216711](https://github.com/llvm/llvm-project/pull/216711): the MS
  inheritance model on non-`CXXRecordDecl` DWARF types (= commit 1). Approved
  2026-08-17 and waiting for someone to merge it; the ping is
  `drafts/pr-216711-ping.md`.

## The series

| # | PR | Notes |
|---|---|---|
| 1 | #216711 Fix a crash completing ObjC types for MSVC targets | approved |
| 2 | [test] Apply GNUstep build flags only when a test asks for them | independent; draft `drafts/prs/02-*` |
| 3 | [test] Add `--no-debug-info` to the Shell build helper | independent; draft `drafts/prs/03-*` |
| 4 | **[CI] Test LLDB against the GNUstep Objective-C runtime** | independent; draft `drafts/prs/04-*`; answers the RFC's CI question |
| 5 | Add class descriptors, an ISA map and dynamic types | wave 1 starts here |
| 6 | Implement `po` from libobjc2's public functions | |
| 7 | Step through Objective-C message dispatch | |
| 8 | Enable Objective-C expression evaluation | expect the closest review |
| 9 | Handle every libobjc2 configuration | data models, COFF, detection memo |
| 10 | Add unit tests for class structure parsing | hermetic |
| 11 | [test] Run the API test suite against a GNUstep libobjc2 | shared test infra |
| 12 | Do not give class objects a dynamic type | |
| 13 | [test] Let API tests use a GNUstep gnustep-base | also turns on the CI's Foundation tests |
| 14 | Show selector names for libobjc2 SELs | |
| 15 | Add formatters for gnustep-base strings and numbers | |
| 16 | Add formatters for gnustep-base collections | |
| 17 | Add Objective-C exception breakpoints and objects | |
| 18 | Add a type encoding parser for libobjc2 metadata | wave 2 starts here; hermetic |
| 19 | Read ivars from libobjc2 metadata | ships with the `GetTypeBitSize` override |
| 20 | Format NSException and NSError | |
| 21 | Synthesize interfaces and methods from runtime metadata | the DeclVendor |
| 22 | [test] Build Shell and API test inferiors for a MinGW target | most invasive test change; changes what `target-windows` etc. mean in a cross build |
| 23 | Resolve exception breakpoints in earlier modules | MinGW catch breakpoints |
| 24 | Take ivar offsets from the runtime | |
| 25 | [lldb] Run the ObjC runtime's IR passes whenever ObjC is enabled | touches ClangExpressionParser |
| 26 | Report the call stack recorded in an NSException | |
| 27 | Resolve ivar offset symbols the inferior does not export | |

Dropped from the August plan: the `frame recognizer list` crash, which
upstream fixed (#222810), and `%msvc_link`, whose test upstream deleted. The
"IR passes by primary language" fix became #25.

Reviewers to tag:

- **theraven**: the libobjc2 ABI
- **DavidSpickett** and **labath**: Linux and the test suite
- **Michael137** and **jimingham**: expressions, formatters, thread plans
- **jdevlieghere**: overall

Two or three PRs in flight at most. Open the next one as its predecessor
lands. **Rob opens every PR himself; nothing is opened or pushed without his
say-so.**

## Declined review suggestions (have the answer ready)

- *Detection should pre-filter modules before looking up `__objc_load`.*
  JITLoaderGDB already looks up `__jit_debug_register_code` by name in every
  module on every `ModulesDidLoad`, on every non-Apple target, so the symtab
  name index exists anyway. The per-module memo covers repeated calls.
- *The GNUstep formatters should get their own category.* CPlusPlusLanguage
  loads the libc++, libstdc++ and MSVC STL formatters into one `cplusplus`
  category. Ours are registered under gnustep-base's own class names, and the
  providers decline anything that is not a GNUstep value.

## AI tool policy

Every commit carries `Assisted-by: Claude Code`, with a lowercase `b` and no
address. Never `Co-Authored-By:`, which asserts authorship and conflicts
with the contributor holding the right to license the code.

**The trailer must also appear in the PR description**, because squash-merge
composes the commit message from the description and discards the commits' own
trailers. #216711 nearly landed unlabelled for exactly this reason.

The policy's binding constraints fall on the contributor, not the tool: read and
review everything before asking for review, be able to answer questions about it,
and write the PR descriptions yourself. That is what paces this series.

## Verification before each PR

```bash
ninja -C ../llvm-project/build lldb lldb-test-depends \
      LanguageRuntimeObjCGNUstepTests LanguageObjCTests TargetTests
../llvm-project/build/bin/llvm-lit ../llvm-project/build/tools/lldb/test/Shell
../llvm-project/build/bin/llvm-lit --filter=objc-gnustep \
      ../llvm-project/build/tools/lldb/test/{Shell,API}
bash gnustep-build/config_matrix.sh
bash gnustep-build/werror_sweep.sh
```

The `-Werror` sweep is not optional. The local build is configured
`LLVM_ENABLE_WERROR=OFF` while premerge builds with it **on**, so a warning that
fails CI compiles silently here — which is exactly how a `-Wformat` mismatch and
a `-Wshift-negative-value` reached the umbrella PR. The sweep is syntax-only over
just the files the branch touches, so it costs seconds.

Rebuild `lldb` itself, not just the unit-test target — a stale `liblldb.so` has
produced a convincing false failure more than once. And when a validation script
reports a product failure, check the harness first.
