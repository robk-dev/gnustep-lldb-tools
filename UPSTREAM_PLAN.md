# Upstreaming plan

Source branch: `gnustep/integration` — 24 commits on upstream `main`.

**Open PRs**

- [#216709](https://github.com/llvm/llvm-project/pull/216709) — overview, draft, not for merge
- [#216710](https://github.com/llvm/llvm-project/pull/216710) — MinGW CRT guard
- [#216711](https://github.com/llvm/llvm-project/pull/216711) — MS inheritance model on non-CXXRecordDecl DWARF types

The remaining eight are prepared but unsent; open each as its predecessor
lands, so only two or three are in flight at once.

Each PR below is cut by cherry-picking its commits onto a fresh branch off
`upstream/main`. LLVM squash-merges, so a PR holding several commits still
lands as one upstream commit; the PR title and description become that
commit's message. Later PRs are rebased onto `main` once their predecessor
lands.

## Independent fixes — no GNUstep knowledge needed to review

These touch no GNUstep code and can go first, in any order. They are also the
cheapest way to start a review relationship before the larger PRs land.

| PR | Commits | What it fixes |
|---|---|---|
| **1. MinGW CRT guard** (#216710) | 1 | `_CrtSetReportMode` is MSVC-only, so the crash-dialog path did not compile under MinGW. 3 lines. |
| **2. DWARF ObjC type completion on MSVC targets** (#216711) | 16, 25 | Objective-C interfaces reach the Microsoft-C++-ABI inheritance-model code, which assumes a `CXXRecordDecl`; every ObjC type completion from DWARF on an MSVC target crashed LLDB. Nothing to do with GNUstep. Commit 25 is the Shell test (cross-compiles to `x86_64-pc-windows-msvc`, links with `lld-link`, checks the AST via `lldb-test -dump-clang-ast`). |

## The GNUstep series

Ordered so each PR is reviewable on its own and depends only on its
predecessors. Reviewers to tag: **theraven** (libobjc2 ABI), **DavidSpickett**
and **labath** (Linux, test suite), **Michael137** and **jimingham**
(expressions, formatters), **jdevlieghere** (overall).

| PR | Commits | Contents |
|---|---|---|
| **3. Class descriptors and dynamic types** | 2, 7, 8, 19 | Parse `struct objc_class` from inferior memory, seed the ISA map from `._OBJC_CLASS_` symbols, resolve dynamic types and attach a type from debug info. Includes not giving class objects a dynamic type, which is a correctness fix for the same code. |
| **4. Unit tests for the class parsing** | 11 | Hermetic gtests over three data models. Could be folded into PR 3 if a reviewer prefers tests alongside the code — worth offering. |
| **5. Object description (`po`)** | 3 | Calls gnustep-base's `_NSPrintForDebugger`, the same hook AppleObjCRuntime uses. |
| **6. Step-through for dispatch trampolines** | 4, 9, 24 | Resolves the implementation via `objc_msg_lookup` from a nested plan, entry points identified by name. |
| **7. Expression evaluation** | 5, 6 | Registers the JIT'd module's selectors with the runtime through an IR pass. Expect the closest review; Michael137/jimingham. |
| **8. Robustness across libobjc2 configurations** | 10, 12, 17, 21 | Data-model-correct field offsets, COFF symbol and section names, `__objc_load`-based runtime detection (covers static and renamed builds, and PE import thunks), cache invalidation, the tagged-pointer table via debug info. |
| **9. API test suite support** | 13, 14, 15, 18 | `--objc-gnustep-dir` plumbing, the `objc-gnustep` category, the tests that use it, docs. Touches shared test infrastructure, so keep it standalone and strictly additive. labath/jdevlieghere. |
| **10. Data formatters** | 20, 22, 23 | Summary providers and synthetic children for the gnustep-base Foundation classes. Largest and most subjective; land last. |

## AI tool policy

LLVM's [AI tool policy](https://llvm.org/docs/AIToolPolicy.html) asks that
contributions containing substantial tool-generated content be labelled, and
suggests a commit trailer. Every commit on this branch carries:

```
Assisted-by: Claude Opus 5
```

(or `Claude Fable 5`, matching whichever model produced it). Upstream practice
uses the same trailer with values like `Claude`, `Claude Code` and
`Cursor / claude-opus-5`. Use `Assisted-by:`, not `Co-Authored-By:` — the
latter asserts authorship, which sits badly with the requirement that the
contributor holds the right to contribute the code under LLVM's licence.

Two further obligations fall on the human contributor, not the tool:

- **"Contributors must read and review all LLM-generated code or text before
  they ask other project members to review it"**, and must "be able to answer
  questions about their work during review". This is the binding constraint on
  how fast the remaining PRs should go out.
- PR descriptions should be the contributor's own words; drafts here are
  starting points to edit, not text to paste unread.

The policy also bans agents that act without human approval, and forbids using
AI tools on issues labelled `good first issue`. Neither applies here: every
push and PR in this series was made under direct human instruction.

## Before opening anything

- Post the RFC on Discourse (LLDB category) and let it sit for a few days.
  Draft is in the git history of this repo; it needs updating with the
  validated configuration matrix, the Windows results, and the fact that
  premerge will report the Shell and API tests as unsupported while the unit
  tests carry CI.
- Each PR description states plainly: what runs in premerge (the unit tests),
  what is skipped without a GNUstep runtime, and which configurations were
  validated on Linux and Windows.
- `git clang-format` against `upstream/main` for every PR.
- Open two or three at a time at most.

## Verification before each PR

```bash
ninja -C ../llvm-project/build lldb lldb-server clang
../llvm-project/build/bin/llvm-lit -v --filter=objc-gnustep \
    ../llvm-project/build/tools/lldb/test/{Shell,API}
bash gnustep-build/config_matrix.sh
```
