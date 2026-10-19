# Build-time import library only. Npcap itself must be installed separately
# for live capture and replay; it is never downloaded or redistributed here.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$importDir = Join-Path $root 'target/npcap-import'
New-Item -ItemType Directory -Force -Path $importDir | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw 'Install Visual Studio Build Tools with Desktop development with C++.'
}
$lib = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'VC/Tools/MSVC/*/bin/Hostx64/x64/lib.exe' | Select-Object -First 1
if (-not $lib) { throw 'MSVC x64 lib.exe was not found. Install the C++ build tools.' }
& $lib /nologo /machine:x64 "/def:$(Join-Path $root 'windows/wpcap.def')" "/out:$(Join-Path $importDir 'wpcap.lib')"
if ($LASTEXITCODE -ne 0) { throw 'Could not generate the Npcap import library.' }
$env:LIBPCAP_LIBDIR = $importDir
# Npcap supports libpcap 1.9.1 APIs. Pin detection so builds also work on CI
# without a runtime DLL or capture driver installed.
$env:LIBPCAP_VER = '1.9.1'
Write-Output "Npcap imports ready: $importDir"
