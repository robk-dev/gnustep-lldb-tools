@echo off
rem Points the existing build dir at the MSVC or the MinGW/UCRT64 GNUstep stack
rem for the test suites (it does not change how LLDB itself is built), and
rem deletes the GNUstep API test inferiors: stale DLLs left beside them by the
rem other configuration are loaded in preference to PATH and make a run lie.
rem Usage (inside env.bat): switch-config.bat msvc|mingw
if "%1"=="mingw" (
  cmake -S llvm -B build -DLLDB_TEST_OBJC_GNUSTEP_DIR=C:/code/gnustep-prefix-mingw -DLLDB_TEST_OBJC_GNUSTEP_BASE_DIR=C:/msys64/ucrt64 -DLLDB_TEST_TRIPLE=x86_64-w64-windows-gnu -DLLDB_TEST_SYSROOT=C:/msys64/ucrt64
) else (
  cmake -S llvm -B build -DLLDB_TEST_OBJC_GNUSTEP_DIR=C:/code/gnustep-prefix -DLLDB_TEST_OBJC_GNUSTEP_BASE_DIR=C:/code/gnustep-msvc/x64/Release -DLLDB_TEST_TRIPLE=x86_64-pc-windows-msvc -DLLDB_TEST_SYSROOT=
)
if exist build\lldb-test-build\lang\objc-gnustep rmdir /s /q build\lldb-test-build\lang\objc-gnustep
