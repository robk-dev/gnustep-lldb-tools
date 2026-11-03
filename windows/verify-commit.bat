@echo off
rem Checks out one commit (detached), builds it and runs the GNUstep Shell tests,
rem as premerge would build a single PR. Usage (inside env.bat):
rem   verify-commit.bat <sha> <log-prefix>
rem Before commit 11 of the series the GNUstep Shell tests are XFAIL on Windows
rem by design (inferiors only get DWARF from that commit on).
git checkout -q --detach %1
ninja -C build lldb lldb-test > %2-build.log 2>&1
echo BUILD_EXIT=%ERRORLEVEL% >> %2-build.log
python build\bin\llvm-lit.py -v --filter="objc-gnustep|objc-interface-msvc" build\tools\lldb\test\Shell > %2-lit.log 2>&1
