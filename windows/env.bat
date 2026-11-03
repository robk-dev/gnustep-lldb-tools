@echo off
rem Runs its arguments in C:\code\llvm-project with the toolchain the Windows
rem LLDB build needs: VS Build Tools 2022 (vcvars64), release clang-cl/lld,
rem GnuWin32 make and Git for Windows' coreutils (Makefile.rules needs
rem dirname/pwd/cp), and Python 3.12 (lldb.exe needs python312.dll on PATH).
rem
rem Call it once per cmd.exe: every call re-runs vcvars64 and lengthens PATH,
rem and after a handful of calls cmd reports "The input line is too long".
rem To run several commands, pass a .bat that runs them all.
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set "PATH=C:\Program Files\LLVM\bin;C:\Program Files (x86)\GnuWin32\bin;C:\Program Files\Git\usr\bin;%LOCALAPPDATA%\Programs\Python\Python312;%PATH%"
cd /d C:\code\llvm-project
%*
