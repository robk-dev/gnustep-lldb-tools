@echo off
rem Builds and tests the checked-out tree in the current configuration.
rem Usage (inside env.bat): test-tip.bat <log-prefix>
ninja -C build lldb lldb-test-depends LanguageObjCTests LanguageRuntimeObjCGNUstepTests TargetTests > %1-build.log 2>&1
echo BUILD_EXIT=%ERRORLEVEL% >> %1-build.log
build\tools\lldb\unittests\LanguageRuntime\ObjC\GNUstepObjCRuntime\LanguageRuntimeObjCGNUstepTests.exe > %1-unit-runtime.log 2>&1
build\tools\lldb\unittests\Language\ObjC\LanguageObjCTests.exe > %1-unit-formatters.log 2>&1
python build\bin\llvm-lit.py -v --filter=objc-gnustep build\tools\lldb\test\Shell build\tools\lldb\test\API > %1-lit-gnustep.log 2>&1
python build\bin\llvm-lit.py -s build\tools\lldb\test\Shell > %1-lit-shell.log 2>&1
