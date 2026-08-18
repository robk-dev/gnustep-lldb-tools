# Builds the bare-libobjc2 runtime demo on Windows with the in-tree clang.
#
# All paths derive from this script's location: the tools repo is expected to
# sit next to `llvm-project` (with LLDB built at llvm-project\build) and next
# to the libobjc2 install prefix `gnustep-prefix`. Override any of them:
#
#   .\build.ps1 -Clang C:\other\clang.exe -Prefix D:\objc -OutDir D:\out
#
# The flag recipe is the one validated for the GNUstep LLDB plugin on Windows:
# DWARF debug info (CodeView cannot represent Objective-C types) and
# lld-link /debug:dwarf (keeps DWARF sections and emits the COFF symbol table
# LLDB needs for the runtime metadata symbols).
[CmdletBinding()]
param(
    [string]$Clang,
    [string]$Prefix,
    [string]$OutDir
)
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$CodeRoot = Split-Path -Parent $RepoRoot
if (-not $Clang)  { $Clang  = Join-Path $CodeRoot 'llvm-project\build\bin\clang.exe' }
if (-not $Prefix) { $Prefix = Join-Path $CodeRoot 'gnustep-prefix' }
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot 'out' }

if (-not (Test-Path $Clang)) {
    throw "clang not found at '$Clang' - build llvm-project first or pass -Clang"
}
if (-not (Test-Path (Join-Path $Prefix 'lib\objc.lib'))) {
    throw "libobjc2 import library not found under '$Prefix\lib' - install libobjc2 there or pass -Prefix"
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$src = Join-Path $PSScriptRoot 'runtime_demo.m'
$obj = Join-Path $OutDir 'runtime_demo.o'
$exe = Join-Path $OutDir 'runtime_demo.exe'

& $Clang @('-m64', '-gdwarf', '-O0', '-c',
           '-fobjc-runtime=gnustep-2.0',
           '-I', (Join-Path $Prefix 'include'),
           '-Xclang', '--dependent-lib=msvcrtd',
           $src, '-o', $obj)
if ($LASTEXITCODE -ne 0) { throw "compile failed ($LASTEXITCODE)" }

& $Clang @($obj, '-o', $exe,
           '-L', (Join-Path $Prefix 'lib'), '-lobjc',
           '-fuse-ld=lld-link', '-Wl,/debug:dwarf')
if ($LASTEXITCODE -ne 0) { throw "link failed ($LASTEXITCODE)" }

# The inferior needs objc.dll; keeping it next to the exe avoids any PATH
# requirements no matter how the debugger launches it.
Copy-Item (Join-Path $Prefix 'lib\objc.dll') $OutDir -Force

Write-Host "Built $exe"
