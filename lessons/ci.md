# Opt-in integration coverage

The workflow `lesson-integration.yml` is manual and uses explicitly labelled, pre-provisioned runners. It does not alter LLVM's default GNUstep opt-in behaviour and does not provision or register a public LLVM bot. It can be dispatched after a maintainer installs its runner labels and repository variables.

## Runner contract

Provide isolated Linux and Windows workers labelled `gnustep-lldb`. Both require Python, CMake, Ninja, Git and an LLVM integration checkout with clang, lldb, lldb-dap, lldb-mcp and test targets built. Set repository variables `LESSON_LLVM_ROOT_LINUX`, `LESSON_LLVM_BUILD_LINUX`, `LESSON_OBJC_PREFIX_LINUX`, `LESSON_BASE_PREFIX_LINUX`, and the corresponding `_WINDOWS` variables. Prefixes must be native paths on that worker.

Provision the runtime stack with the existing README workflows, pinned to libobjc2 v2.3, tools-make make-2_9_3 and gnustep-base base-1_31_1. Use the MSVC stack for the Windows lesson job. Retain the platform-specific dependency build logs. A runner image update is a reviewed dependency change, not an implicit upgrade during a test.

The workflow requires an exact LLVM revision input and checks the configured checkout against it. It builds requested LLVM targets without replacing source or changing the configured toolchain, compiles fresh fixtures, runs CLI/DAP/MCP/Foundation checks, and uploads output even on failure. Configure the LLVM build with `LLDB_TEST_OBJC_GNUSTEP=ON`, `LLDB_TEST_OBJC_GNUSTEP_DIR`, and `LLDB_TEST_OBJC_GNUSTEP_BASE_DIR`. Tests intentionally fail if no GNUstep tests execute or any are unsupported in this provisioned job.

Linux GUI tests belong in a separate job with gnustep-gui/back and Xvfb or WSLg; they must not turn a core runtime failure into an infrastructure skip. `gorm.py smoke` is the headless breakpoint check once that application is built. Its dependency setup remains separately reported until validated.

## Proposed LLVM buildbot integration

Start with an opt-in Linux x86-64 worker containing a pinned full GNUstep stack. Add a Windows MSVC worker after agreeing ownership and the host image. Keep generic premerge unit coverage unchanged. The dedicated worker runs GNUstep Shell and API cases, Foundation formatters and exception tests, plus the selected unit suites. A later MinGW job exercises the separate ABI and catch paths; it is not implied by an MSVC pass.

Use `python lessons/run_ci.py --config <config.json> --llvm-revision <sha>` as the locally reproducible worker step. Archive `validation/` with binary versions, revision, hashes and the selected CMake configuration. Build failures, test failures, timeouts and unsupported tests are distinct evidence. Full-stack jobs should have a bounded wall clock and a documented owner, while quick parsing tests remain available everywhere.

Add `--deep` on developer-image workers with matching Clang, LLDB, libobjc2 and gnustep-base debug symbols to verify the four generated VS Code source launches through DAP. The default runtime CI path does not require a fully debuggable compiler build.

Before deploying a bot, maintainers must agree the worker owner, hosting resources, dependency-update policy and how failures are routed. Those are the external decisions raised by the RFC. This package supplies an executable runner and a reviewable workflow; it does not claim an upstream service exists.
