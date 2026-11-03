# Debugger lesson and reproducible developer labs

This companion to `../lldb-video-lesson` provides the executable examples behind the video. All commands below run from the `gnustep-lldb-tools` repository root. They preserve the existing demo launch configurations.

## Windows: configure, build, debug

Start with the Windows toolchain and GNUstep installation in the repository README. The default sibling layout is `llvm-project/build`, `gnustep-prefix` (MSVC libobjc2) and `gnustep-msvc/x64/Release` (Foundation). Python 3 is required. Use the integration build, not an unrelated system LLDB.

```powershell
python lessons/lab.py doctor
python lessons/lab.py setup
python lessons/test_workflows.py
python lessons/deep_labs.py
python lessons/test_workspace.py
code lessons/out/lesson.code-workspace
```

For another layout, specify paths explicitly; the generated workspace then uses those exact paths:

```powershell
python lessons/lab.py setup --llvm-root C:/src/llvm-project --build-dir C:/build/llvm --prefix C:/sdk/objc --base-prefix C:/sdk/gnustep
```

The workspace contains Basics, Runtime, Objective-C++, Foundation, Clang, nested LLDB, libobjc2 and gnustep-base launches. Open a fixture from `lessons/fixtures`, place a source breakpoint on `LESSON_STOP` or `FOUNDATION_STOP`, and select the corresponding launch. Each setup compiles with debug information; Objective-C uses DWARF. Generated files and transcripts are under ignored `lessons/out/`. `launch.json` contains the same copyable launch definitions as the workspace. Breakpoint commands use `preRunCommands`, after the target exists; target ABI settings belong in `initCommands`, before target creation.

CLI equivalent (PowerShell, after setup):

```powershell
$env:Path = "$(Split-Path (Get-Command python).Source);$env:Path"
& ../llvm-project/build/bin/lldb.exe --no-lldbinit -s lessons/out/runtime.lldb -- lessons/out/counter.exe
```

For Foundation, prepend the selected Foundation prefix's `bin` directory to PATH. The setup keeps its executable in a separate directory from the bare-runtime fixture so their runtime DLLs do not shadow one another. The Windows lesson builder intentionally accepts the MSVC ABI only; use the repository's existing MinGW recipes and LLVM tests for that configuration. A GNU-ABI PE must use `settings set plugin.object-file.pe-coff.abi gnu` **before target creation**.

## Linux / WSL

Use a Linux build of LLVM and the GNUstep stack from the repository's Linux setup instructions. A Windows executable under `/mnt/c` is not a Linux LLDB build. Choose a separate output directory when sharing the tooling checkout between platforms:

```bash
python3 lessons/lab.py setup \
  --llvm-root "$HOME/code/llvm-project" \
  --build-dir "$HOME/code/llvm-project/build" \
  --prefix /usr/local --base-prefix /usr/local \
  --out "$HOME/code/lesson-output"
python3 lessons/test_workflows.py --config "$HOME/code/lesson-output/config.json"
python3 lessons/deep_labs.py --config "$HOME/code/lesson-output/config.json"
code "$HOME/code/lesson-output/lesson.code-workspace"
```

Run `code` from the WSL terminal to open the Linux workspace using VS Code's WSL connection. If the Linux build cannot be found, the doctor command fails before trying to launch anything. Fresh Linux validation status is recorded in the teaching package; these commands must not be described as tested merely because Windows passes.

## Expected observations

At `LESSON_STOP`, `frame variable -d no-run-target object` identifies a Counter. `frame variable *counter` reports `before = 1`, `aligned = 42`, `after = 3`. `expression -- (int)[counter twice:21]` returns 42. `po counter` prints `Counter ready`; it invokes the fixture's description methods through the runtime. `step` reaches `-[Counter twice:]`.

The Foundation fixture displays three array elements and a number, raises `LessonException`, and catches it. The tests use throw breakpoints, not platform-dependent catch assumptions. The larger test coverage remains in LLVM's `objc-gnustep` suites.

## Agent access

`lab.py setup` writes `lessons/out/mcp.json` with a VS Code-compatible server entry using the selected `lldb-mcp`. Copy its **servers** entry into the workspace's `.vscode/mcp.json` if using VS Code; other MCP clients can use the same stdio executable and environment. No global configuration is changed automatically.

Use this sequence in an MCP client:

1. Discover `tools/list`; call `session_create` and retain its returned URI.
2. Call `command` with that URI as `debugger` and `script lldb.debugger.SetAsync(False)` as `command`.
3. Create the target using its absolute fixture path, set a breakpoint at `LESSON_STOP`, and run.
4. Inspect the stopped frame, evaluate the known expression if needed, step and inspect the resulting method frame.
5. Continue to exit and call `session_close` with the created session URI.

Do not assume DAP messages can be sent to MCP. The test driver implements each protocol separately and verifies their observed results. Introspection, expression evaluation and execution control are different operations; agents should say which they are using and retain evidence of the stop. Debuggee stdout is separate from MCP command output. See `llvm-project/lldb/docs/use/mcp.md` for attaching to an existing LLDB session.

## Full-source walkthroughs

`deep_labs.py` records four real breakpoint traces. `--only clang`, `--only lldb`, `--only runtime` and `--only base` select one. The default runs all four. Its temporary processes stop after recording evidence; use the generated workspace for interactive exploration. An optimised build may stop in an inlined frame: select the relevant caller in the backtrace.

The Clang breakpoint uses a source pattern in `CGObjCGNU.cpp`. A function-name breakpoint in the current optimised Windows build initially selected an ObjFW branch that was never executed for GNUstep. The Foundation method is implemented by **GSArray**, inherited by GSInlineArray. These are reasons to verify a breakpoint by observing a stop, not just by seeing a resolved location.

For Gorm, see [gorm.md](gorm.md). For automated runs and the LLVM buildbot proposal, see [ci.md](ci.md).
