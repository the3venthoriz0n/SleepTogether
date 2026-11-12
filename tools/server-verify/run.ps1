# Compiles and runs the server DateTime tests against stub Catch2/TiltedCore headers.
# Usage: powershell -File tools\server-verify\run.ps1 [-Worktree <path>]
param(
    [string]$Worktree = 'C:\Users\Andrew\Documents\_devWin\TiltedEvolution-sleep'
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$out = Join-Path $here 'out'
New-Item -ItemType Directory -Force $out | Out-Null

$vsDevCmd = 'C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat'
if (-not (Test-Path $vsDevCmd)) { Write-Error "VsDevCmd.bat not found at $vsDevCmd"; exit 2 }

$code = Join-Path $Worktree 'Code'
$exe = Join-Path $out 'datetime_tests.exe'
Remove-Item $exe -ErrorAction SilentlyContinue

# Main for the stub lives here so the real tests\main.cpp is not needed
$mainCpp = Join-Path $out 'stub_main.cpp'
Set-Content -Encoding ascii $mainCpp "#define CATCH_CONFIG_MAIN`n#include <catch2/catch.hpp>`n"

# DateTime.cpp and tests\datetime.cpp differ only by case, so give each object an explicit name
$q = '"'
$flags = "/nologo /std:c++17 /EHsc /W4 /I$q$here\stubs$q /I$q$code$q /I$q$code\encoding$q"
$steps = @(
    "cl $flags /c $q$mainCpp$q /Fo$q$out\main.obj$q",
    "cl $flags /c $q$code\common\DateTime.cpp$q /Fo$q$out\dt_impl.obj$q",
    "cl $flags /c $q$code\tests\datetime.cpp$q /Fo$q$out\dt_tests.obj$q",
    "link /nologo /OUT:$q$exe$q $q$out\main.obj$q $q$out\dt_impl.obj$q $q$out\dt_tests.obj$q"
)
$line = $steps -join ' && '
cmd /c "$q$vsDevCmd$q -arch=x64 -no_logo && $line"
if ($LASTEXITCODE -ne 0) { Write-Host 'COMPILE FAILED'; exit 1 }

& $exe
if ($LASTEXITCODE -ne 0) { Write-Host 'TESTS FAILED'; exit 1 }
Write-Host 'ALL TESTS PASSED'
exit 0
