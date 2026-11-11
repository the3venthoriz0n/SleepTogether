param(
    [string]$Version = "0.1.0"
)

$ErrorActionPreference = "Stop"
$root   = Split-Path -Parent $PSScriptRoot
$data   = Join-Path $root "package\Data"
$dll    = Join-Path $data "SKSE\Plugins\SleepTogether.dll"
$relay  = Join-Path $root "package\Server\strpm-chat-relay"
$main   = Join-Path $relay "main.lua"
$mani   = Join-Path $relay "strpm-chat-relay.manifest"
$dist   = Join-Path $root "dist"
$zip    = Join-Path $dist ("SleepTogether-{0}.zip" -f $Version)
$zipSrv = Join-Path $dist ("SleepTogether-Server-{0}.zip" -f $Version)

if (-not (Test-Path -LiteralPath $dll)) { throw "DLL not found: $dll. Build first (build_release.bat)." }

# The DLL must be the current build (it contains the version marker).
$bytes = [System.IO.File]::ReadAllBytes($dll)
$ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
if (-not $ascii.Contains("SleepTogether $Version loading")) { throw "Version marker for $Version not found in DLL." }

# The server resource must exist and contain the embedded Sleep Together handler.
if (-not (Test-Path -LiteralPath $main)) { throw "Server resource not found: $main. Run: python -I tools/build_server_resource.py" }
if (-not (Test-Path -LiteralPath $mani)) { throw "Server manifest not found: $mani. Run: python -I tools/build_server_resource.py" }
if (-not ([System.IO.File]::ReadAllText($main)).Contains("SleepTogetherHandler")) { throw "SleepTogetherHandler not found in $main. Run: python -I tools/build_server_resource.py" }

New-Item -ItemType Directory -Path $dist -Force | Out-Null
foreach ($z in @($zip, $zipSrv)) { if (Test-Path -LiteralPath $z) { Remove-Item -LiteralPath $z -Force } }

Compress-Archive -Path $data -DestinationPath $zip -CompressionLevel Optimal -Force
Write-Host "Created $zip"

# Server zip: folder strpm-chat-relay\ with main.lua and the manifest.
Compress-Archive -Path $relay -DestinationPath $zipSrv -CompressionLevel Optimal -Force
Write-Host "Created $zipSrv"
