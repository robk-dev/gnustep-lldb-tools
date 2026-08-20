# Upstreaming plan

Source branch: `gnustep/integration`, rebased on `upstream/main`.

**Landed**

- [#216710](https://github.com/llvm/llvm-project/pull/216710) — Guard CRT debug
  report calls with `_MSC_VER`. Merged as `85413b1277e2`.

**Open**

- [#216709](https://github.com/llvm/llvm-project/pull/216709) — overview, draft,
  not for merge.
- [#216711](https://github.com/llvm/llvm-project/pull/216711) — MS inheritance
  model on non-`CXXRecordDecl` DWARF types. Approved.

Each PR is cut by cherry-picking its commits onto a fresh branch off
`upstream/main`. LLVM squash-merges, so a PR holding several commits still lands
as one upstream commit, and **the PR description becomes that commit message** —
including its `Assisted-by:` trailer, which the commits' own trailers do not
survive to provide.

## Independent fixes — no GNUstep knowledge needed to review

Cheapest way to keep a review relationship going, and each is a real bug on its
own. Send these first, in any order.

| PR | What it fixes |
|---|---|
| **MS inheritance model** (#216711) | Objective-C interfaces reach the Microsoft-C++-ABI inheritance-model code, which assumes a `CXXRecordDecl`; every ObjC type completion from DWARF on an MSVC target crashed LLDB. |
| **Frame recognizer with no module** | `frame recognizer list` dereferences a null `ConstString`. Reachable only through the API today, which is why it survived. Self-contained gtest. |
| **GNUstep build flags applied to every `%build`** | The Shell build helper keyed the libobjc2 include and library paths off `--objc-gnustep-dir`, which lit passes to *every* `%build` on a GNUstep-configured build. Contained only because `--compiler=any` preferred `clang-cl` on Windows. Fixes upstream code, not ours. |
| **`%msvc_link` without an MSVC requirement** | The one test using that substitution asked only for `target-windows`; run from a non-vcvars shell it executes the literal string and the shell returns 127. |
| **`--no-debug-info` for the Shell build helper** | Needed to test anything that must work from a source other than debug info. |

## Wave 1 — the plugin, foundation upward

Reviewers to tag: **theraven** (libobjc2 ABI), **DavidSpickett** and **labath**
(Linux, test suite), **Michael137** and **jimingham** (expressions, formatters,
thread plans), **jdevlieghere** (overall).

| PR | Contents |
|---|---|
| Class descriptors, ISA map, dynamic types | Parse `struct objc_class` from inferior memory, seed the ISA map from class symbols, resolve dynamic types. Includes not giving class objects a dynamic type. |
| Unit tests for the class parsing | Hermetic gtests over three data models. Offer to fold into the PR above if a reviewer prefers tests alongside code. |
| Object description (`po`) | Built from libobjc2's `OBJC_PUBLIC` primitives, so it works against a bare runtime. Does **not** depend on gnustep-base exporting `_NSPrintForDebugger`. |
| Step-through for dispatch trampolines | Resolves the implementation via `objc_msg_lookup`; steps out of a nil send rather than stranding the user in dispatch assembly. |
| Expression evaluation | Registers the JIT'd module's selectors through an IR pass. Expect the closest review. |
| Robustness across libobjc2 configurations | Data-model-correct field offsets, COFF symbol and section names, `__objc_load`-based detection, cache invalidation. |
| API test suite support | `--objc-gnustep-dir` plumbing, the category, the tests, docs. Shared test infrastructure — keep standalone and strictly additive. |
| Data formatters | Summary providers and synthetic children for gnustep-base, including the string flags fallback for classes with no debug info. |

## Wave 2 — runtime introspection

Opens only once wave 1 has landed.

| PR | Contents |
|---|---|
| Type encoding parser | Hermetic; takes a `Triple`, needs no target state. 51 cases across three data models. |
| Ivars from runtime metadata | `GetNumIVars`/`GetIVarAtIndex` plus the `GetTypeBitSize` override — these must ship together or a wrong-`sizeof` regression lands in tree. |
| Ivar offsets from the runtime | Overrides `GetByteOffsetForIvar`. Small, self-contained, and fixes wrong values for any over-aligned ivar and everything after it. Depends on the PR above. |
| `DeclVendor` | Interfaces and methods synthesized from runtime metadata. The largest and closest port of Apple code. Now also carries the dynamic-value fallback: without it a class with no debug info resolves to a name but displays as `id`, which is what made a runtime-created class look unsupported. |
| Exception breakpoints and exception objects | Including the catch entry point (both `objc_begin_catch` and `__cxa_begin_catch`) and the load-order re-resolve. |
| Exception backtrace | `GetBacktraceThreadFromException`, reading the `GSStackTrace` gnustep-base fills in `-[NSException raise]`. Self-contained; depends on the ivar-metadata PR. Needs gnustep-base, so its test is API-only. |
| Ivar offset symbols | `LookupRuntimeSymbol`, for when the inferior exports no `__objc_ivar_offset_*` symbol (stripped module, hidden-visibility ivar, `class_addIvar`). Carries the descriptor change that keeps the offset *address* libobjc2 gives us, which nothing needed until now. |

## Wave 3 — cross-targeting the test suites

Most invasive; sent last. Hoists `LLDB_TEST_TRIPLE` and `LLDB_TEST_SYSROOT` out
of `lldb/test/API/CMakeLists.txt` so the Shell suite can build inferiors for a
different target, adds two lit substitutions, and restructures the build
helper's compile/link flag logic.

Two things to flag explicitly in those descriptions: the commit that re-derives
`target-windows` / `windows-msvc` / `windows-gnu` from the inferior's triple
**changes what those features mean** for any out-of-tree test in a
cross-configured build; and the API-suite half touches `Makefile.rules`, shared
by the entire suite.

## Two formatting windows to close when the PRs are cut

`clang-format` is clean at the branch tip, but LLVM's `code_formatter` job runs
on a PR's **cumulative diff** versus the merge base — so a PR that ends inside
one of these windows fails it:

| Window | Closed by |
|---|---|
| commits 1–10 (through *Add unit tests for class structure parsing*) | 11, *Formatting and include cleanup* |
| commits 30–36 (through *Synthesize interfaces from runtime metadata*) | 37, *Vend methods from runtime metadata* |

Any PR whose last commit falls in a window is dirty; any PR that includes the
closing commit is clean. Two ways to fix, decide when the grouping is final:
group each window's commits into PRs that carry their closing commit, or
distribute the formatting into the commits that introduce the code.

**Distributing it is not a mechanical rebase** — it was attempted and abandoned.
Running `git clang-format` at commit 1 reformats regions that commit 9
(*Harden runtime for all libobjc2 configurations*) later rewrites wholesale, so
the replay conflicts semantically rather than textually. If you do it, resolve
by taking the later commit's content and re-running the formatter there.

Reproduce the sweep by checking out each commit in a worktree and running
`git clang-format --diff upstream/main -- lldb/source lldb/include lldb/unittests`
— note **`upstream/main`**, not `HEAD~1`: per-commit is the wrong measure and
reports six scattered commits instead of these two windows.

## A commit must build clean on its own

Premerge builds every PR with `-Werror`, and the sweep below only checks the
branch tip — so a constant introduced by commit N and first used by commit N+2
fails CI for the two PRs in between while the tip stays green. Check the commits
a PR actually contains, not just the final tree.

## Before opening anything

- Post the RFC on Discourse (LLDB category) and let it sit. Draft in
  `drafts/rfc-discourse.md`.
- Each PR description states what premerge runs (the unit tests) versus what is
  unsupported there, and which configurations were validated.
- `git clang-format` against `upstream/main` for every PR.
- Two or three in flight at most.

## AI tool policy

Every commit carries `Assisted-by: Claude Opus 5` — lowercase `b`, model name
only, no address. Never `Co-Authored-By:`, which asserts authorship and conflicts
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
