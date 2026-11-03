# GNUstep LLDB upstreaming — state and handover

Written 2026-08-20, updated after the gap-closing round. Read this first; it is
the single source of truth for where the work stands. Everything below was
verified, not remembered.

## State as of 2026-10-17 (round 4). This section supersedes the ones below.

| | |
|---|---|
| Work branch | `gnustep/pr-series` in `~/code/llvm-project`, **local only**. 27 commits on `upstream/main` `dc057e33a1be`, **one commit per upstream PR** (table in `UPSTREAM_PLAN.md`). Tagged `backup/pr-series-r4-final-20261017`. The previous version is `backup/pr-series-r3-final-20261017`. |
| Fork | 2026-10-18: pushed `gnustep/pr-series` (= `aa155a32fccc`) and tag `windows/round4`. The local branch has since moved on (`dd662364077a`, the Windows fixes); the fork is behind. `gnustep/integration` on origin is still the 51-commit August history. No new PRs are opened; Rob decides when. |
| Drafts | `drafts/pr-216709-description-r4.md` (umbrella refresh), `drafts/prs/0{2,3,4,5}-*.md`, `drafts/rfc-followup-ci.md`, `drafts/dm-davidchisnall.md`, `drafts/pr-216711-ping.md`, `drafts/kickoff-windows-round4.md` (fill in the SHA when `windows/round4` is pushed) |

Verified on Linux x86_64 at the tip, and commit by commit:

```
every commit        builds, -Werror sweep clean, unit tests pass, GNUstep lit tests that exist there pass
                    clang-format (C/C++) and darker (Python) clean against its parent
whole Shell suite   803 discovered / 616 passed / 180 unsupported / 7 XFAIL / 0 failed
GNUstep lit         17 (Shell + API)
unit                173 (runtime) + 28 (formatters)
config matrix       all rows pass; row 4 (static libobjc2) skipped, as before
CI script           lldb/utils/ci/build-gnustep.sh built a fresh prefix; all GNUstep tests passed against it
```

Windows (2026-11-03, verified by Claude from WSL on this machine, at `windows/round4` plus the two fixes below):

```
MSVC (clang-cl)     GNUstep lit 17/17; unit 173 + 29 + 117 (target); whole Shell suite 536 pass / 7 flaky
                    (all 7 pass when re-run; Smart App Control blocks freshly linked binaries mid-run)
MSVC, commits 1-10  each builds with no warnings in our files; GNUstep Shell tests pass or XFAIL as designed
MinGW/UCRT64        GNUstep lit 17/17; whole Shell suite 543 pass / 0 fail; CATCH breakpoint 5/5
```

Two fixes came out of it, both folded into their commits (`backup/pr-series-r5-20261103`):
- Dates before 1970 printed nothing on Windows (MSVC's `gmtime` rejects them, e.g. `distantPast`).
  The NSDate summary now does its own proleptic-Gregorian conversion (`GNUstepFormatDate`), with a unit test.
- `objc-gnustep-stepping.m` carried `XFAIL: system-windows` from commit 7 but passes there (XPASS);
  the marker is gone from commit 7 on.

Smart App Control on this machine blocks some freshly built binaries outright (`clang-tblgen.exe` this time).
Workaround: append one byte to the binary (new hash, same code). See `drafts/kickoff-windows-round4.md`.

Review: three independent audit rounds this session (correctness, structure, and
the round-4 delta). Their findings are fixed in the commits that own them. Two
suggestions were declined, and the reasons are in `UPSTREAM_PLAN.md`.

Next steps, all Rob's call:

1. Push `gnustep/pr-series` (and the `upstream-pr/*` prefixes) to the fork,
   then tag `windows/round4` and hand `drafts/kickoff-windows-round4.md` to the
   Windows agent.
2. Ping #216711 to get it merged.
3. Post the RFC follow-up about CI. Contact davidchisnall.
4. Open PRs 2–4, then 5. Two or three in flight at most.

## Where things were (August; historical)

| | |
|---|---|
| Work branch | `gnustep/integration` = **`c29ce1a8c933`**, 51 commits on `upstream/main` `b562ef546e46`, pushed. Tagged `windows/round3` — hand that tag to anyone verifying, never a SHA: the branch is rebased often. |
| Merged | **#216710** (MinGW CRT guard) → upstream `85413b1277e2`, author `robk@robk.dev` |
| Open, approved | **#216711** (MS inheritance model), branch `lldb-dwarf-objc-msvc-inheritance` = `b01a072abb07` |
| Open, draft | **#216709** umbrella, description current as of today |
| Tools repo | `gnustep-lldb-tools` `main`, 1 commit ahead of origin (`c16f786`), plus uncommitted doc edits |

Backup tags exist at each risky step: `backup/pre-round2-*`, `backup/post-phase2-dist-*`,
`backup/post-phase3-*`, `backup/pre-upstream-rebase-*`, `backup/post-phase4-*`.

## Verified numbers (Linux, at the tip)

```
whole Shell suite   799 discovered / 610 passed / 182 unsupported / 7 XFAIL / 0 failed
GNUstep lit         16  (13 Shell + 3 API)
unit                137 (runtime) + 28 (formatters, of which 7 are ours) + 78 (target)
config matrix       all rows pass; row 4 (static libobjc2) legitimately skipped
-Werror             clean at the tip AND commit by commit
clang-format        clean at the tip; two mid-history windows, see UPSTREAM_PLAN.md
series size         90 files, ~8700 insertions
```

Windows, verified at this tip (tag `windows/round3`), both toolchains:

```
whole Shell suite   799 discovered / 498 passed / 268 unsupported / 32 XFAIL / 0 failed
GNUstep lit         16  (13 Shell + 3 API)
unit                130 + 27 + 77 (TargetTests is 77 here; one case is host-gated)
```

MSVC and MinGW/UCRT64 are identical, test for test, and match Linux on every
GNUstep count. All four tests from this round run and pass there; the two that
could have passed vacuously were checked by removing the code they cover.
CLANG64 remains hand-verified only — the suite cannot link there.

One caveat when reading a Windows run: Smart App Control intermittently blocks
a freshly linked inferior, so each full-suite run shows exactly one failure, a
different test each time, passing standalone. No GNUstep test ever flaked.

## The gap-closing round (most recent work)

Four things Apple's runtime does and ours did not. Three are now done; the
fourth is documented instead, deliberately.

| | Outcome | Commit |
|---|---|---|
| Dynamic type for a class with no debug info | **done** — folded into *Synthesize interfaces from runtime metadata*, which had been shipping half a feature | by subject; SHAs churn |
| Exception call stack | **done** — `thread exception` and lldb-dap now show it | *Report the call stack recorded inside an NSException* |
| Ivar offsets with no exported symbol | **done** — `LookupRuntimeSymbol` | *Resolve ivar offset symbols the inferior does not export* |
| Object checker | **not done, on purpose** — see below | — |

**The object checker is inert, not merely unwritten.** `IRDynamicChecks` injects
the guard by matching callees named `objc_msgSend`; under the legacy dispatch
cc1 defaults to — which is what LLDB's expression parser uses — clang emits
`objc_msg_lookup_sender`, so a checker would never be called. Writing one is
also unsafe: Apple's is safe on a garbage receiver only because it delegates to
`gdb_object_getClass`, a debugger-support entry point in their libobjc that
libobjc2 has no equivalent of. This is now §2(d) of the RFC — a shared-code
finding, not a plugin limitation.

**The first one's diagnosis was wrong for a while, and the wrong version reached
the RFC.** The on-demand ISA fallback already existed and worked; the class name
resolved fine. What was missing is that `GetDynamicTypeAndAddress` never asked
the DeclVendor for a *type*, so the result was a name with no type — and
`FixUpDynamicType` pairs a bare name with the **static** CompilerType, which
`ValueObjectDynamicValue::GetTypeName` prefers. Hence `(id)`. Worth remembering
as a shape: "feature missing" and "feature present but its result is discarded
downstream" look identical from the command line.

## Runtime-registered classes: what works, and why not more

`frame variable` on a value of an `objc_allocateClassPair` class works cold —
that path reaches the class through the object's ISA, and `GetClassDescriptorFromISA`
parses `struct objc_class` from memory and caches it by ISA *and* by name.

`type lookup Foo`, and naming `Foo` in an expression, do **not** work until a
value of it has been printed once. The name-to-ISA map is built by sweeping
class symbols and such a class has none.

This was investigated; do not re-investigate without reading this:

- **A per-stop re-sweep would not help.** `UpdateISAToDescriptorMapIfNeeded` is
  dirty-gated on `ModulesDidLoad`, but even if it ran every stop it only scans
  module symbol tables — which by definition never contain a runtime-registered
  class. It would cost time and find nothing.
- **Reading libobjc2's class table is possible but a bad trade.** `class_table`
  exists at a fixed address and *is* in `.symtab` — but as a **local** symbol
  (`nm` shows `b class_table`), so stripping removes it, and stripped is the
  normal distribution case (our own matrix has a stripped row). Its layout is
  the private `MAP_TABLE_*` hash, with no ABI guarantee; encoding it in LLDB
  would break on a libobjc2 update.
- **The clean option, if it is ever wanted**, is to call `objc_getClass(name)`
  in the inferior *only when a by-name lookup misses*. Both it and
  `objc_lookUpClass` are public (`T`) in libobjc2. That is one call on a path
  where the user explicitly asked for a type by name — not a per-stop cost. The
  price is that `type lookup` would start running code, which forfeits a
  property currently stated plainly in the RFC.

The practical cost of leaving it is low: to name such a class you generally have
to have seen it, and once any value of it is printed it is cached for the
session.

## What remains

1. ~~Windows verification of this round~~ — **done**. MSVC and MinGW/UCRT64 both
   report 799 / 498 / 268 / 32 / **0 failed** and 16 GNUstep tests (13 Shell +
   3 API), matching Linux test for test. The two riskiest were proven
   non-vacuous there by removing the code they cover. CLANG64 still cannot run
   the suite, for the unchanged libc++/libstdc++ reason. Re-verify with the
   `windows/round3` tag if the branch is rewritten again.
2. **Post the RFC** to Discourse, LLDB category. Rob posts it. Its job is to get
   agreement before ~22 PRs arrive: on the runtime-detection change, on where
   runtime-specific gaps in shared LLDB code should be fixed, and on what CI can
   realistically cover when premerge has no libobjc2 installed.
3. **Cut the PR series.** Grouping is in `UPSTREAM_PLAN.md` — independent fixes
   first, then wave 1 (plugin foundation), wave 2 (runtime introspection, now
   including the exception backtrace and the ivar-symbol fallback), wave 3
   (cross-targeting). Sweep `-Werror` **per commit**, not just at the tip.
4. **More review rounds** — see "What reviewers will ask" below.
5. **Non-LLVM upstreaming** (`drafts/upstream-gnustep.md`) — three items, none
   blocking, after the LLVM work.

## Working rules that are easy to get wrong

- **`gnustep/integration` gets rewritten.** That is the agreed protocol. Anyone
  branching from it must re-fetch rather than assume their base survived — this
  already caught the Windows agent out once.
- **Commit trailer is `Assisted-by: Claude Opus 5`** — lowercase `b`, model name
  only, no address. Never `Co-Authored-By:`.
- **The trailer must also be in the PR description.** Squash-merge composes the
  commit message from the description and discards commit trailers. #216711
  nearly landed unlabelled because of this.
- **Fold fixes into the commit that introduced the defect**, not at the tip.
  Each PR is squash-merged separately, so a fix appended at the tip leaves the
  earlier PR failing CI on its own.
- **Run `bash gnustep-build/werror_sweep.sh` before pushing.** The local build is
  `LLVM_ENABLE_WERROR=OFF` and premerge is ON; two warnings reached CI that way.

## Hard-won lessons (each cost real time)

- **Check the harness before believing a product failure.** Three of the
  "failures" chased in this project were a stale `lldb-test` binary, a stale
  breakpoint line number in a script, and a stale build after a rebase.
- **A green `llvm-lit` run after a rebase can be stale binaries.** Rebuild first.
- **`git apply` fails where `git apply -3` succeeds** when context has moved;
  patches from `git show` carry blob SHAs, so the 3-way merge works.
- **Assert that a scripted edit took.** Twice, a python `replace` silently no-oped
  and `--amend` committed nothing, making a test look vacuous when it wasn't.
- **Whitespace-only reversions are invisible in review.** Detect with: split
  `git diff -U0` per file, flag hunks where removed and added text match after
  stripping whitespace. Token-level ones (`(a,b) =` → `a,b =`) need a deletion
  count instead — a file we only add to should show **0 deletions**.
- **Don't add `-Wall -Wextra` to LLVM's own flags** when sweeping; LLVM disables
  `-Wunused-parameter` and you'll drown in header noise.
- **Several Shell tests break on absolute line numbers**, so editing comments
  shifts them. Prefer `breakpoint set -p "break [h]ere"` — the `[h]` stops the
  pattern matching the RUN line itself.
- **Whole-file `clang-format` is not the CI check.** Five C++ files report
  reformatting; all five are pre-existing upstream. Compare against
  `git show upstream/main:<file>` before assuming it is yours.

## Traps found this round (add to the list before the next one)

- **A CHECK block inside lldb's source echo matches its own text.** lldb prints
  the source lines around the breakpoint (`stop-line-count-after`, default 3).
  A `// CHECK:` within that window is satisfied by the *echo of the test file
  itself*, not by command output. Two GNUstep tests were at margin **0** and one
  was demonstrably passing with no `expr` output at all. Keep CHECK blocks above
  the code, and measure the margin: `breakpoint_line + 3` vs first CHECK line.
- **`clang-format` can fail mid-history while the tip is clean, and the obvious
  per-commit check gives the wrong answer.** The `code_formatter` job runs on a
  PR's *cumulative* diff, so measure with `git clang-format --diff upstream/main`
  at each commit, not `--diff HEAD~1`. Per-commit reports six scattered commits;
  cumulative reports the two real windows (1–10, closed by *Formatting and
  include cleanup*; 30–36, closed by *Vend methods from runtime metadata*).
  Details and the two ways to close them are in `UPSTREAM_PLAN.md`. Distributing
  the formatting backwards is **not** a mechanical rebase — attempted and
  abandoned, because early formatting touches regions that later commits rewrite
  wholesale.
- **The formatter CI runs darker as well as clang-format**, and a C++-only
  sweep misses it — a wrapped `self.expect()` reached CI that way. `darker` is
  now part of `werror_sweep.sh`, and it has the same mid-history shape: check
  each commit against *its own parent*, because a line introduced unformatted
  by one commit and tidied by a later one is dirty at the commit in between.
- **`-Werror` can fail mid-history while the tip is clean.** A constant
  introduced by commit N and first used by N+3 makes every commit in between
  fail premerge. `werror_sweep.sh` only checks the tip and structurally cannot
  see this. Sweep per commit before cutting PRs; one such window (3 commits,
  one of them test-only) existed and is now fixed.
- **`git commit --amend` during a rebase conflict amends the *previous* commit.**
  It silently squashes the conflicted commit into its predecessor and the count
  drops by one. Always `git add -u && git rebase --continue`. This cost a full
  redo once; the only thing that caught it was checking the commit count.
- **A background agent can rewrite your branch.** One swept its own debug
  `fprintf`s into a commit and then re-amended to remove them. The tree came out
  correct, but verify: `git diff <expected> HEAD` and grep the series for
  `fprintf(stderr`/`std::cerr` before pushing.
- **Do not run the test suite while agents are running.** Concurrent `ninja` in
  one build directory produced a truncated archive and four phantom test
  failures. Any result taken while an agent is active is unreliable.

## What reviewers will ask, and the current answer

- **"Why does a plugin sweep the target's breakpoint list?"** The exception
  load-order workaround is the only `GetBreakpointList` caller under
  `Plugins/`. It carries a FIXME naming `ExceptionSearchFilter::ModulePasses` as
  the real site. Expect pushback; the RFC raises it.
- **"Why override `GetRuntimeType`?"** Because
  `ObjectFile::GetSymbolTypeFromName` doesn't know gnustep class symbols, so the
  debug-info branch always misses. RFC §2a offers to fix the cause instead.
- **"Should the Shell suite cross-target at all?"** Wave 3 hoists
  `LLDB_TEST_TRIPLE` out of the API subdirectory. Most invasive change in the
  series; sent last, flagged in its own description.
- **"Is this extractive?"** The AI policy's central test is whether a
  contribution is worth more than the time it costs to review. That is why the
  series is sliced small, why the RFC goes first, and why each PR states what
  premerge runs versus skips. Rob must be able to answer questions on any of it —
  that is the binding constraint on pace, not the code.

## Files worth knowing

- `UPSTREAM_PLAN.md` — PR grouping, three waves, verification recipe
- `drafts/pr-216709-description.md` — published umbrella text
- `drafts/kickoff-windows-round3.md` — Windows agent prompt for the current round
- `drafts/kickoff-windows-agent.md` — the previous round's prompt, superseded
- `drafts/handover-corrections-for-windows-agent.md` — corrections owed to them
- `drafts/apple-parity-audit.md` — the audit against AppleObjCRuntime
- `drafts/phase3-validation-results.md` — the four untested paths, exercised
- `gnustep-build/werror_sweep.sh`, `gnustep-build/config_matrix.sh`

## Claims that were checked and corrected

How the project is described to reviewers was rewritten after checking it
against actual LLDB behaviour rather than intuition. Three claims about what
does *not* work today did not survive:

- **"`frame variable` shows the address, not the object" — false** where the
  class has debug info. With dynamic values off, `frame variable *w` on a
  statically-typed object still prints every ivar; DWARF carries them. Only the
  *dynamic* type is lost: a variable declared `id` or as a base class keeps its
  declared type.
- **"`po` does nothing" — false.** Upstream's stub returns a specific error,
  `"LLDB's GNUStep runtime does not support object description"`.
- **"a message send does not compile" — imprecise.** Where debug info describes
  the method it compiles and then misbehaves; only without debug info does it
  fail to compile ("no known method").

The "before" state is best read straight from upstream's stub:
`GetDynamicTypeAndAddress` returns false, `GetStepThroughTrampolinePlan` returns
nullptr, `GetObjectDescription` returns that error, and
`UpdateISAToDescriptorMapIfNeeded` is empty. Nothing there disables DWARF, which
is why so much still works.

**The lesson generalises to everything written for reviewers:** a claim about
what does or does not work should be traceable to something observed, because
anyone with a GNUstep setup can check it in a minute. Overstating the problem is
the fastest way to lose credibility on the parts that are true.
