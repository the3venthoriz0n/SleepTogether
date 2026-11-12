param(
    [string]$Version = "0.2.0"
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

# Server zip: built with System.IO.Compression so entry names use forward slashes
# (Compress-Archive on Windows PowerShell 5.1 writes backslashes, which break on a Linux server).
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zipSrv, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in @($main, $mani)) {
        $name  = "strpm-chat-relay/" + (Split-Path -Leaf $file)
        $entry = $archive.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
        $in    = [System.IO.File]::OpenRead($file)
        $out   = $entry.Open()
        try { $in.CopyTo($out) } finally { $out.Dispose(); $in.Dispose() }
    }
} finally {
    $archive.Dispose()
}
Write-Host "Created $zipSrv"
