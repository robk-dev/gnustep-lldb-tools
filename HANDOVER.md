# GNUstep Objective-C debugging in LLDB — handover

Last updated 2026-11-03 (after Codex round 2). This is the single document to read before touching
this work, whether you are Rob, Claude or Codex. It says what we are trying to
do, where everything is, how to prove that it works, and how it gets upstream.
History before October is in `docs-HANDOVER-2026-08-archive.md`.

---

## 1. Goal

LLDB has had a `GNUstepObjCRuntime` plugin since D146154 (2023), but it only
*detects* the GNUstep libobjc2 runtime, the Objective-C runtime used on Linux
and Windows. None of the debugging hooks are implemented:

- `GetDynamicTypeAndAddress` returns false;
- stepping into a message lands in the runtime's dispatch code;
- `po` errors out;
- the ISA map is empty.

Rob's work makes it a real runtime plugin, modelled on Apple's and diverging
where the libobjc2 ABI differs:

- class descriptors, dynamic types and tagged pointers;
- `po`;
- stepping through dispatch;
- expression evaluation;
- ivars and their offsets read from runtime metadata;
- a DeclVendor for classes without debug info;
- exception breakpoints and NSException backtraces;
- data formatters for gnustep-base.

The aim is to land it in **llvm/llvm-project**, as a series of small,
reviewable PRs, with **CI that actually runs the GNUstep tests**. That CI is
what the RFC discussion asked for.

- RFC: <https://discourse.llvm.org/t/rfc-lldb-objective-c-debugging-support-for-the-gnustep-libobjc2-runtime-on-non-apple-platforms/91623>
  (as posted: `drafts/rfc-discourse.md`).
- Umbrella PR, draft and not for merge: <https://github.com/llvm/llvm-project/pull/216709>.
- **#216710** (MinGW CRT guard): merged as `85413b1277e2`.
- **#216711** (MS inheritance-model crash on ObjC DWARF types): approved by
  Michael137 on 2026-08-17 and not yet merged. Rob has no commit access, so
  someone has to press merge (`drafts/pr-216711-ping.md`).

### What the RFC discussion asked for (still open)

- **@JDevlieghere**:
  - someone committed to reviewing and maintaining the code, which he put to
    @davidchisnall;
  - "keeping the new CI green", i.e. a CI that builds and runs the
    Objective-C tests against GNUstep.
- **@adrian.prantl**: what CI would be provided.
- **@davidchisnall** (libobjc2's author) said he doesn't know LLDB
  internals, so the ask to him is scoped to the runtime ABI
  (`drafts/dm-davidchisnall.md`).
- **@fseiffert** and **@mcarans** (shipping ObjC on Windows/Android) are
  potential testers.

Our answer: PR 4 adds the CI workflow, Rob owns it, and the RFC follow-up
says so (`drafts/rfc-followup-ci.md`). None of these have been sent yet.

---

## 2. Ground rules (Rob's standing instructions)

- **Rob opens every PR himself** and writes the descriptions in his own words.
  The drafts in `drafts/prs/` are starting points. Don't open, comment on, or
  edit any upstream PR or Discourse thread.
- **Don't push to the fork without Rob saying so.** Pushes so far:
  - 2026-10-18: `gnustep/pr-series` (old tip `aa155a32fccc`) and tag
    `windows/round4`, for Windows verification.
  - 2026-11-03, approved by Rob:
    - `gnustep/pr-series` = `8940e879a657` (force);
    - all 27 `upstream-pr/NN-*` branches;
    - the fork-only `ci/gnustep-fork-validation` (see §6; since deleted).
- Every commit ends with `Assisted-by: Claude Code` per the
  [AI tool policy](https://llvm.org/docs/AIToolPolicy.html). **Never
  `Co-Authored-By:`.** LLVM squash-merges, and **the PR description becomes the
  commit message**, so the trailer must be in the PR description too.
- One commit = one PR. Fix review findings **in the commit that introduced the
  problem** (`git commit --fixup` plus autosquash, or a rebase `edit`), never
  as a commit on top.
- Two or three PRs in flight at most. Open the next as its predecessor lands.
- GitHub's "Keep my email addresses private" must stay **off**, or the
  squash-merge dialog substitutes a noreply address, which reviewers object to
  (#216710 hit this).

---

## 3. Where everything is

### Machine

WSL2 Ubuntu (20 cores, ~20 GB) on a Windows 11 host (24 cores, 31 GB). Windows is reachable from
WSL through interop (`cmd.exe`, `git.exe`); see §5.2.

- **Interop can break mid-session**: every `.exe` then fails with
  `UtilAcceptVsock: accept4 failed 110`. Only `wsl --shutdown` from Windows
  fixes it, and that ends the WSL session.
- **`/tmp` is wiped on WSL restart**, so keep nothing you need there.
- `sudo` needs a password. Ask Rob to run the command himself.

### `~/code/llvm-project` (WSL)

**Remotes**

- `origin` = `robk-dev/llvm-project` (the fork)
- `upstream` = `llvm/llvm-project`

**Branches**

- **`gnustep/pr-series`** = `8940e879a657`, the series: 27 commits on
  `upstream/main` merge-base `dc057e33a1be`. Pushed to the fork, along with
  the `upstream-pr/*` branches. Every Codex round-1 and round-2 fix is in.
- `upstream-pr/NN-<slug>`: one local branch per commit, so PR *N* is the
  prefix ending at commit *N*.
- `gnustep/integration`: the old 51-commit August history, also on the fork.
  It is superseded; don't build on it.

**Backup tags**, one per rewrite: `backup/pr-series-r3-final-20261017`,
`-r4-final-20261017`, `-r5-20261103`, `-r6-20261103` (before Codex round 2),
`-r7-20261103` (= current).
`windows/round4` = `aa155a32fccc`, on the fork.

**Builds**

- `build-stage1/`: Release clang and lld, used as the host compiler.
- `build/`: the stage-2 LLDB build:
  - RelWithDebInfo, assertions on, `BUILD_SHARED_LIBS=ON`, ccache;
  - `LLVM_ENABLE_WERROR=OFF`, which is why the sweep in §5.1 exists;
  - GNUstep test options: `LLDB_TEST_OBJC_GNUSTEP=On`,
    `LLDB_TEST_OBJC_GNUSTEP_DIR=/usr/local`,
    `LLDB_TEST_OBJC_GNUSTEP_BASE_DIR=/usr/local`.

**GNUstep on Linux**

- Sources in `~/gnustep-src/`: libobjc2 v2.3 `e877e782`, tools-make
  `make-2_9_3`, libs-base `base-1_31_1`.
- Installed into `/usr/local`.
- The CI script (§6) builds the same stack into any prefix.

### `~/code/gnustep-lldb-tools` (WSL)

There is also an older clone at `C:\code\gnustep-lldb-tools`.

| Path | What it is |
|---|---|
| `HANDOVER.md` | this file |
| `UPSTREAM_PLAN.md` | the PR plan and the reasons for declined review suggestions |
| `gnustep-build/verify_commits.sh` | **per-commit build and test on Linux** (§5.1) |
| `gnustep-build/werror_sweep.sh` | syntax-only `-Werror` over the files the series touches |
| `gnustep-build/config_matrix.sh` | the libobjc2 configuration matrix (§5.1) |
| `gnustep-build/realapp_probe.py` | drives LLDB against autogsdoc, a real 14k-line ObjC program |
| `windows/*.bat` | the Windows build environment, config switcher and checks (§5.2) |
| `drafts/` (gitignored) | PR descriptions, the RFC, replies, audit reports, kickoff prompts |
| `WINDOWS_VALIDATION_RESULTS.md`, `README.md` | Windows setup and how the GNUstep stack is built |

### Windows (`C:\code`)

**LLVM build**

- `C:\code\llvm-project\build`: clang-cl 22.1.8 and lld from the winget LLVM
  release, VS Build Tools 2022 (MSVC 14.44, SDK 10.0.26100), RelWithDebInfo,
  assertions off.
- It is currently on branch `pr-series` (= `8940e879a657`), fetched straight
  from WSL, in the **MSVC** test configuration.

**GNUstep stacks**

| Toolchain | libobjc2 | gnustep-base |
|---|---|---|
| MSVC | `C:\code\gnustep-prefix` (built with plain `clang.exe`) | `C:\code\gnustep-msvc\x64\Release` |
| MinGW (MSYS2 UCRT64, `C:\msys64`) | `C:\code\gnustep-prefix-mingw` | built from source and installed over `C:\msys64\ucrt64`; MSYS2's own package is ABI-broken |

**Tools**

- Python 3.12 at `%LOCALAPPDATA%\Programs\Python\Python312` (the python.org
  per-user install; `lldb.exe` and `lldb-dap.exe` need its `python312.dll`).
- GnuWin32 make.
- Git for Windows' `usr\bin`, for the coreutils that Makefile.rules needs.

---

## 4. The series (one commit = one upstream PR)

Order is dependency order. PRs 1–4 are independent of everything. From 5 on,
each needs its predecessors. Wave 1 is 5–17, wave 2 is 18–27, and the
test-suite cross-targeting change (22) is the most invasive.

| # | Commit | Size | Notes |
|---|---|---|---|
| 1 | Fix a crash completing Objective-C types for MSVC targets | +46 −2 | = **#216711**, approved |
| 2 | [test] Apply GNUstep build flags only when a test asks for them | +6 −6 | independent; draft `drafts/prs/02-*` |
| 3 | [test] Add `--no-debug-info` to the Shell build helper | +21 −5 | independent; draft `03-*` |
| 4 | **[CI] Test LLDB against the GNUstep Objective-C runtime** | +251 | independent; draft `04-*`; answers the RFC |
| 5 | Add class descriptors, an ISA map and dynamic types | +624 −3 | first plugin PR; draft `05-*` |
| 6 | Implement `po` from libobjc2's public functions | +268 −4 | |
| 7 | Step through Objective-C message dispatch | +565 −1 | |
| 8 | Enable Objective-C expression evaluation | +171 | selector-registration IR pass |
| 9 | Handle every libobjc2 configuration | +529 −146 | data models, COFF, detection memo, COFF constant strings |
| 10 | Add unit tests for class structure parsing | +412 | hermetic; these run in premerge |
| 11 | [test] Run the API test suite against a GNUstep libobjc2 runtime | +217 −14 | Windows inferiors get DWARF from here; XFAILs dropped |
| 12 | Do not give class objects a dynamic type | +103 | |
| 13 | [test] Let API tests use a GNUstep gnustep-base | +91 −5 | also enables the CI's Foundation tests |
| 14 | Show selector names for libobjc2 SELs | +223 | |
| 15 | Add formatters for gnustep-base strings and numbers | +1275 −6 | plus dates, data, NSNull |
| 16 | Add formatters for gnustep-base collections | +656 −7 | |
| 17 | Add Objective-C exception breakpoints and objects | +381 −8 | |
| 18 | Add a type encoding parser for libobjc2 metadata | +1028 | hermetic, 5 data models |
| 19 | Read ivars from libobjc2 metadata | +1014 −40 | |
| 20 | Format NSException and NSError | +222 −8 | |
| 21 | Synthesize interfaces and methods from runtime metadata | +1150 −2 | the DeclVendor |
| 22 | [test] Build Shell and API test inferiors for a MinGW target | +337 −103 | changes what `target-windows` etc. mean in a cross build |
| 23 | Resolve exception breakpoints in earlier modules | +35 | MinGW catch breakpoints |
| 24 | Take ivar offsets from the runtime | +96 | |
| 25 | [lldb] Run the ObjC runtime's IR passes whenever ObjC is enabled | +134 −5 | touches ClangExpressionParser |
| 26 | Report the call stack recorded in an NSException | +179 −7 | |
| 27 | Resolve ivar offset symbols the inferior does not export | +231 −1 | |

`git log --reverse upstream/main..gnustep/pr-series` gives SHAs and full
messages. Every message is wrapped at 72 columns, has a title of at most 72
characters, and ends with `Assisted-by: Claude Code`.

**Non-goals**

- No behaviour change for Apple's runtime. No `AppleObjCRuntime/` file is
  touched, and Apple's registrations in `LoadObjCFormatters` are unchanged.
- No replacement for debug info: DWARF wins where it exists.
- No GCC libobjc and no ObjFW.
- No GNUstep-side changes required.

**Known limitations**, to state in the PR text:

- Members inside struct-typed ivars need gnustep-base's debug info, because
  libobjc2 encodings carry no field names.
- A bare `@throw` has no recorded stack.
- Catch breakpoints don't fire for Objective-C++ on ELF.
- A module stripped of its `.objc_selector_*` symbols loses method names.
- A class registered at run time can't be found by name until it has been
  seen by ISA.
- A bad receiver in an expression shows a raw signal.
- 8-bit strings are decoded as Latin-1.
- The step-through method cache is not invalidated on swizzle.
- A layout read while a class is mid-way through ivar layout can still be
  accepted if every ivar already happens to fit (see the Codex round-1 notes).

---

## 5. How to verify

Everything below was green on 2026-11-03 at `8940e879a657`, including the
Linux run of all 27 commits one at a time: every commit builds, the -Werror
sweep is clean, and its unit and GNUstep lit tests pass, with no failures.
Re-run all of it after any change.

### 5.1 Linux

```bash
cd ~/code/llvm-project
# after rebasing onto newer upstream, rebuild the stage-1 tablegens first
ninja -C build-stage1 llvm-tblgen clang-tblgen
ninja -C build lldb lldb-test-depends LanguageRuntimeObjCGNUstepTests LanguageObjCTests TargetTests

# the tip
build/tools/lldb/unittests/LanguageRuntime/ObjC/GNUstepObjCRuntime/LanguageRuntimeObjCGNUstepTests  # 211 pass
build/tools/lldb/unittests/Language/ObjC/LanguageObjCTests                                           # 29 pass
build/bin/llvm-lit -sv --filter=objc-gnustep build/tools/lldb/test/Shell build/tools/lldb/test/API  # 18 pass
build/bin/llvm-lit -s build/tools/lldb/test/Shell          # 803 discovered, 0 failed (616 pass at r4)

# every commit on its own, as premerge builds a PR (takes hours)
~/code/gnustep-lldb-tools/gnustep-build/verify_commits.sh \
    $(git rev-list --reverse upstream/main..gnustep/pr-series)

# formatting, per commit (premerge's format check covers .cpp/.h/.c/.inc, never .m)
for c in $(git rev-list --reverse upstream/main..gnustep/pr-series); do
  python3 clang/tools/clang-format/git-clang-format --binary build/bin/clang-format \
    --extensions cpp,c,h,inc --diff $c~1 $c -- lldb; done
# Python: darker 1.7.2 + black 23.12.1, from a venv, against upstream/main

# the libobjc2 configurations (stripped, renamed, old-ABI, 2.0/2.1/2.2, runtime-created classes)
PROJECT_ROOT=$PWD bash ~/code/gnustep-lldb-tools/gnustep-build/config_matrix.sh /some/scratch/dir
```

`verify_commits.sh` also runs `werror_sweep.sh` for every commit. The local
build doesn't use `-Werror`, and premerge does, so a warning would otherwise
only show up in CI.

### 5.2 Windows (driven from WSL)

The scripts are in `gnustep-lldb-tools/windows/`. Copy them to a Windows path
first, because cmd can't use a `\\wsl$` directory as its working directory.

```bash
cp ~/code/gnustep-lldb-tools/windows/*.bat /mnt/c/tmp/w/
cd /mnt/c/tmp/w     # run cmd.exe from a Windows directory
# bring the series over without pushing:
(cd /mnt/c/code/llvm-project && git.exe -c safe.directory='*' fetch \
   '\\wsl.localhost\Ubuntu\home\robk\code\llvm-project' gnustep/pr-series:refs/heads/pr-series \
   && git.exe checkout pr-series)
cmd.exe /c 'C:\tmp\w\env.bat C:\tmp\w\test-tip.bat C:\tmp\w\msvc'      # MSVC
cmd.exe /c 'C:\tmp\w\env.bat C:\tmp\w\switch-config.bat mingw'
cmd.exe /c 'C:\tmp\w\env.bat C:\tmp\w\test-tip.bat C:\tmp\w\mingw'     # MinGW/UCRT64
cmd.exe /c 'C:\tmp\w\env.bat C:\tmp\w\switch-config.bat msvc'          # leave it as found
# per commit (premerge builds each PR on Windows too):
cmd.exe /c 'C:\tmp\w\env.bat C:\tmp\w\verify-commit.bat <sha> C:\tmp\w\c<N>'
```

Pass `</dev/null` to `git.exe` inside shell loops, or it consumes the loop's
stdin.

The editor path (lldb-dap rather than the lldb CLI) has its own check. It
launches a demo through lldb-dap as VS Code does and prints the Locals:

```bash
python3 ~/code/gnustep-lldb-tools/scripts-wsl/dap_smoke.py \
  --dap /mnt/c/code/llvm-project/build/bin/lldb-dap.exe \
  --program 'C:\code\gnustep-lldb-tools\demos\out\foundation_types_demo.exe' \
  --source 'C:\code\gnustep-lldb-tools\demos\foundation_types_demo.m' --line 112 \
  --env 'PATH=C:\code\gnustep-msvc\x64\Release\bin;C:\Windows\System32' --expand mutableArray
```

Every local should show a summary (`@"Hi"`, `(long)123456`, `@"3 elements"`,
`3 key/value pairs`, dates, `<null>`). lldb-dap shows the pointer *and* the
summary (`0x... @"Hi"`) for every language; that's expected. Expected results:

| Configuration | Expected |
|---|---|
| MSVC | 17 GNUstep lit pass and 1 unsupported (`symbols-add` is Linux-only); 211 + 29 + 117 (TargetTests) unit; whole Shell suite 0 failures; no warnings in plugin files |
| MinGW/UCRT64 | 17 GNUstep lit pass and 1 unsupported; whole Shell suite 0 failures |
| Commits 1–10 | each builds; GNUstep Shell tests are XFAIL (by design until commit 11), except `stepping.m`, which passes |

**Windows traps**

- **A per-commit check leaves the build at that commit.** `verify-commit.bat`
  builds old commits in the shared build directory, so afterwards
  `build\bin` (including `lldb-dap.exe`, which the VS Code configs use) is
  that old commit's LLDB. On 2026-11-03 this showed up as Foundation values
  with no summaries in VS Code: the binaries were from commit 10, before the
  formatters exist. Always finish with
  `ninja -C build lldb lldb-dap lldb-test-depends` at the tip.
- **Smart App Control** blocks some freshly built binaries outright ("blocked
  by your organization's Device Guard policy").
  - In 2026-11 it blocked `clang-tblgen.exe`. The workaround is to append one
    byte to the binary (`printf '\0' >> file.exe`): a new hash, the same code.
  - It also intermittently blocks test inferiors mid-run, so a full Shell run
    shows a few random failures that pass when re-run. Always re-run failures
    on their own before believing them.
  - The first launch of a new binary can also fail once (`llvm-config` did).
- **Stale DLLs** beside the API test binaries are loaded in preference to
  PATH. `switch-config.bat` deletes them; always switch through it.
- **`env.bat` must be called once per `cmd.exe`.** Calling it repeatedly
  overflows PATH with "The input line is too long".
- **CodeView can't describe Objective-C**, so Windows inferiors must be built
  with DWARF (`-gdwarf`, `lld-link /debug:dwarf`). API tests skip the `pdb`
  variant.

### 5.3 Proving a test is not vacuous

For every new test, revert only the source fix (`git checkout <before> --
<source files>`), rebuild, and confirm that the test fails. Then restore.

- A CHECK line within 3 lines of a breakpoint matches LLDB's echo of the test
  source, not the command output. Keep CHECKs above the code.
- Shell-test breakpoint lines are absolute, so editing a test above a
  breakpoint means updating `b file.m:<line>`.
- Never run clang-format on `.m` tests.

---

## 6. CI (PR 4)

- **`.github/workflows/lldb-gnustep-tests.yml`**, modelled on
  `spirv-tests.yml`:
  - `if: github.repository_owner == 'llvm'`, `permissions: contents: read`,
    SHA-pinned actions;
  - the digest-pinned `ghcr.io/llvm/ci-ubuntu-26.04` container with
    `--cap-add=SYS_PTRACE --security-opt seccomp=unconfined`, because LLDB
    disables ASLR via `personality(2)`;
  - sccache;
  - builds clang and LLDB (Release, assertions on), then runs
    `llvm-lit -v --filter=objc-gnustep` over the Shell and API suites;
  - **fails if any selected test is UNSUPPORTED, SKIPPED or UNRESOLVED, or if
    none passes**, because lit counts unsupported as success;
  - triggers: pull requests touching the ObjC plugins, the tests and their
    helpers, `ClangExpressionParser.cpp`, `DeclVendor.h` or
    `clang/lib/CodeGen/CGObjCGNU.cpp`; daily at 04:00; and
    `workflow_dispatch`.
- **`lldb/utils/ci/build-gnustep.sh <prefix>`** builds pinned libobjc2 v2.3,
  gnustep-make 2.9.3 and gnustep-base 1.31.1 (debug info on). It works locally
  too.
  - Distribution packages can't be used, because Debian and Ubuntu build
    gnustep-base against GCC's runtime.
  - It carries a `sed` for `BLOCK_SCOPE` on an ivar in
    `NSBackgroundActivityScheduler.h`, and `-Wno-error=` flags for the legacy
    `configure` probes.
- **Status: the script is verified locally** (built a fresh prefix; every
  GNUstep test passed against it). **The workflow has never run on GitHub**:
  the owner guard keeps it off forks.
- **Fork validation (done, 2026-11-03).**
  - It ran at the series tip, with the owner guard relaxed by a fork-only
    commit on a scratch branch. The branch has since been deleted; the runs
    remain.
  - **Cold cache:** 64 minutes. GNUstep took 30 s, clang and LLDB 62 minutes;
    18/18 GNUstep tests passed.
    <https://github.com/robk-dev/llvm-project/actions/runs/41600865284>
    (attempt 1)
  - **Warm cache:** 5½ minutes. GNUstep came from the cache and the sccache
    build took 3 min 20 s; 18/18 passed. Same run, attempt 2.
  - **Guard check:** `LLDB_TEST_OBJC_GNUSTEP_BASE_DIR` dropped, so the
    Foundation API tests reported UNSUPPORTED. The job **failed**, as
    designed: <https://github.com/robk-dev/llvm-project/actions/runs/41609222467>.
  - The numbers are in `drafts/prs/04-*` and `drafts/rfc-followup-ci.md`.

---

## 7. Opening the PRs

1. **Prerequisites:**
   - Windows verification of the current tip is done (2026-11-03).
   - CI validated on the fork (§6).
   - Rob has re-read every line he puts his name to. The AI policy requires
     that he can answer questions about it.
2. **Comms first:**
   - Post the #216711 merge ping.
   - Post the RFC follow-up (`drafts/rfc-followup-ci.md`).
   - Send the DM to davidchisnall.
3. **First batch:** PRs 2, 3 and 4. Then PR 5 once the CI PR has had a
   reaction. #216711 (PR 1) is already open.
4. **Per PR:**
   - Push `upstream-pr/NN-*` to the fork.
   - Open the PR against `llvm/llvm-project:main`.
   - Paste Rob's rewrite of the matching draft, ending with
     `Assisted-by: Claude Code`.
   - A PR that depends on unmerged ones still contains their commits, so say
     "depends on #X; only the last commit is new".
   - Tag the reviewers:
     - theraven/davidchisnall: libobjc2 ABI
     - DavidSpickett and labath: Linux and the test suite
     - Michael137 and jimingham: expressions, formatters, thread plans
     - JDevlieghere: overall
5. **Review changes:** fold them into that PR's commit locally, rebase the
   rest of the series, re-run §5 for the affected commits, then force-push that
   PR's branch.
6. **Umbrella #216709:** replace its description with
   `drafts/pr-216709-description-r4.md`, after refreshing its numbers. Ask
   before force-pushing the umbrella branch.

**Drafts**

- `drafts/prs/02-*` to `05-*`
- `drafts/pr-216709-description-r4.md`
- `drafts/rfc-followup-ci.md`
- `drafts/dm-davidchisnall.md`
- `drafts/pr-216711-ping.md`
- `drafts/kickoff-windows-round4.md` (superseded by §5.2)

PR drafts for 6–27 aren't written yet. The commit messages are the best
starting point.

---

## 8. Review history (so nobody redoes it)

**Rounds**

- Three Claude audit rounds in October:
  - correctness: SEL flags, bitfields, sparse dictionaries, NSException
    over-read, no-debug-info IR pass, detection memo, and more;
  - structure: split commit 14, stray hunks, message accuracy;
  - the round-4 delta.
- Windows verification in 2026-11 found:
  - pre-1970 dates printed nothing (MSVC's `gmtime`), now formatted by
    `GNUstepFormatDate`;
  - a stale `XFAIL` on `stepping.m`.
- **Codex round 1 (2026-11-03).** Run headless by Claude with `codex exec` in
  a read-only sandbox, using `drafts/codex-audit-brief.md`.
  - Report: `drafts/codex-audit-r1-report.md`.
  - Disposition: `drafts/codex-audit-r1-response.md`.
  - All 8 findings were real and are fixed in their owning commits, each with
    a test that fails without the fix where one is possible.

- **Codex round 2 (2026-11-03).** Rob ran it with
  `drafts/codex-kickoff-prompt.md`.
  - Report: `drafts/codex-audit-r2-report.md`.
  - Disposition: `drafts/codex-audit-r2-response.md`.
  - 9 findings, all real, and the blocker was reproduced: the parser sized
    clang's UnknownAny placeholder.
  - All are fixed in their owning commits.
  - The class-name bound moved into PR 5. The step-through plan's
    argument-block ownership went into PR 9 rather than PR 7, because PR 9 is
    where its teardown is hardened.

**Declined suggestions** (reasons in `UPSTREAM_PLAN.md`):

- Pre-filtering modules before runtime detection: JITLoaderGDB already does a
  name lookup in every module on non-Apple targets, and detection is memoized
  per module.
- A separate formatter category: the libc++, libstdc++ and MSVC STL formatters
  share `cplusplus`.

---

## 9. Gotchas that cost time

- **History editing**
  - In `rebase -i`, an `edit` or `fixup` step that *conflicts* doesn't stop
    again after you resolve it. For a fixup, resolve, `git add`, then
    `git rebase --continue` (a manual `git commit` creates a separate commit).
    For an edit, `git commit --no-edit --cleanup=strip`, or `# Conflicts:`
    lands in the message. rerere is on and may resolve silently.
  - Do history edits that need no build in a scratch `git worktree`, while the
    main tree builds. Afterwards, prove that the verified and final trees
    differ only in comments.
- **Shells**
  - zsh doesn't word-split `$VAR`, aborts on unmatched globs, and reads
    `$B:l…` as a history modifier. Use `${B}` or `bash -c`.
  - `pkill -f <pattern>` kills the shell running it if the pattern is on its
    command line.
- **Builds**
  - After rebasing, rebuild the stage-1 tablegens.
  - Rebuild `lldb` itself, not only the unit target: a stale `liblldb.so` has
    produced convincing false results.
- **Formatting:** the format CI checks only C/C++ extensions. Never
  clang-format `.m` tests, because their breakpoint lines are absolute.
- **gnustep-base 1.31**
  - Its `configure` needs libcurl when built for libobjc2.
  - Its test programs need `-lobjc`.
  - tools-make's `--with-runtime-abi` decides the real compile ABI
    (`gnustep-2.2`).
- **Running inferior code on COFF:** a JIT'd constant string's isa is null
  until `.objc_early_init` runs, which is why the IR pass registers it.

---

## 10. Next steps, in order

1. Optionally, a Codex round 3 on the round-2 fixes (same prompt; point it at
   `drafts/codex-audit-r2-response.md`).
2. Comms (§7.2), then PRs 2–4, then 5.
3. Write the PR drafts for 6 onwards as the earlier ones land.
