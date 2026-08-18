# Builds a Foundation (gnustep-base) debugging demo on Windows.
#
# Compiles examples/simple_test.m together with foundation_shim.m (which
# supplies _NSPrintForDebugger, unexported from the base DLL on MSVC) against
# a GNUstep install produced by gnustep/tools-windows-msvc. Expected layout:
# the tools repo sits next to `llvm-project` (LLDB built at build\bin) and
# next to the GNUstep install root `gnustep-msvc` (x64\Release inside).
#
#   .\build-foundation.ps1 [-Clang ...] [-GnustepRoot ...] [-OutDir ...]
#
# Debug info is DWARF (CodeView cannot represent Objective-C types) and the
# link keeps a COFF symbol table via lld-link /debug:dwarf.
[CmdletBinding()]
param(
    [string]$Clang,
    [string]$GnustepRoot,
    [string]$OutDir,
    # Objective-C source to build; defaults to examples/simple_test.m.
    [string]$Source,
    # Output executable name (without .exe); defaults to foundation_demo.
    [string]$Name = 'foundation_demo'
)
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$CodeRoot = Split-Path -Parent $RepoRoot
if (-not $Clang)       { $Clang       = Join-Path $CodeRoot 'llvm-project\build\bin\clang.exe' }
if (-not $GnustepRoot) { $GnustepRoot = Join-Path $CodeRoot 'gnustep-msvc\x64\Release' }
if (-not $OutDir)      { $OutDir      = Join-Path $PSScriptRoot 'out' }

if (-not (Test-Path $Clang)) {
    throw "clang not found at '$Clang' - build llvm-project first or pass -Clang"
}
if (-not (Test-Path (Join-Path $GnustepRoot 'lib\gnustep-base.lib'))) {
    throw "gnustep-base not found under '$GnustepRoot' - build it with gnustep/tools-windows-msvc or pass -GnustepRoot"
}

if (-not $Source) { $Source = Join-Path $RepoRoot 'examples\simple_test.m' }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$exe = Join-Path $OutDir "$Name.exe"

# -fblocks is required (NSURLSession.h uses block types); this needs the
# repo's patches/libs-base-0001-no-block-ivar-clang24.patch applied to the
# gnustep-base headers, since modern clang rejects __block on an ivar.
$compile = @('-m64', '-gdwarf', '-O0',
             '-fobjc-runtime=gnustep-2.2',
             '-fconstant-string-class=NSConstantString',
             '-fexceptions', '-fobjc-exceptions', '-fblocks',
             '-DGNUSTEP', '-DGNUSTEP_BASE_LIBRARY=1', '-DGNU_RUNTIME=1',
             '-DGNUSTEP_WITH_DLL',
             '-I', (Join-Path $GnustepRoot 'include'),
             '-Xclang', '--dependent-lib=msvcrt')

$objects = @()
foreach ($src in @($Source, (Join-Path $PSScriptRoot 'foundation_shim.m'))) {
    $obj = Join-Path $OutDir ("$Name-" + [IO.Path]::GetFileNameWithoutExtension($src) + '.o')
    & $Clang ($compile + @('-c', $src, '-o', $obj))
    if ($LASTEXITCODE -ne 0) { throw "compile failed: $src" }
    $objects += $obj
}

& $Clang ($objects + @(
           '-o', $exe,
           '-L', (Join-Path $GnustepRoot 'lib'),
           '-lgnustep-base', '-lobjc',
           '-fuse-ld=lld-link', '-Wl,/debug:dwarf'))
if ($LASTEXITCODE -ne 0) { throw "link failed" }

Write-Host "Built $exe"
Write-Host "Run with '$GnustepRoot\bin' on PATH (DLLs live there)."
