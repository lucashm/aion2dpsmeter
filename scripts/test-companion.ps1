# Native WebView2 -> Rust -> real daemon replay -> four HWND overlays.
# The report command exists only with the ui-smoke feature.
[CmdletBinding()]
param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$runRoot = Join-Path $root ('target/companion-smoke-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path "$runRoot/aion2-meter" | Out-Null
$oldLocal = $env:LOCALAPPDATA
$oldReplay = $env:AION2_COMPANION_SMOKE_REPLAY
$oldReport = $env:AION2_COMPANION_SMOKE_REPORT
$oldSmoke = $env:VITE_UI_SMOKE
Push-Location $root
try {
    if (-not $SkipBuild) {
        $env:VITE_UI_SMOKE = '1'
        npm --prefix windows/ui run build
        if ($LASTEXITCODE -ne 0) { throw 'Smoke UI build failed.' }
        & "$PSScriptRoot/prepare-windows.ps1"
        cargo build --locked -p aion2-meterd -p aion2-meter-windows --features ui-smoke
        if ($LASTEXITCODE -ne 0) { throw 'Smoke native build failed.' }
    }
    $pcap = Join-Path $runRoot 'fixture.pcap'
    python -c "import importlib.util,pathlib,sys;s=importlib.util.spec_from_file_location('fixture','scripts/test-daemon.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.write_capture(pathlib.Path(sys.argv[1]))" $pcap
    if ($LASTEXITCODE -ne 0) { throw 'Could not generate the replay fixture.' }
    Set-Content -LiteralPath "$runRoot/aion2-meter/companion.json" -Value '{"autoStart":false,"sound":false}' -Encoding utf8
    New-Item -ItemType Directory -Force -Path "$runRoot/aion2-meter/fights" | Out-Null
    Copy-Item -LiteralPath 'windows/testdata/fight.json' -Destination "$runRoot/aion2-meter/fights/desktop_fixture.json"
    $env:LOCALAPPDATA = $runRoot
    $env:AION2_COMPANION_SMOKE_REPLAY = $pcap
    $env:AION2_COMPANION_SMOKE_REPORT = Join-Path $runRoot 'report.json'
    $process = Start-Process -FilePath "$root/target/debug/aion2-meter-windows.exe" -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(90000)) {
        Stop-Process -Id $process.Id -Force
        throw "Native smoke timed out. Inspect $runRoot"
    }
    if (-not (Test-Path -LiteralPath $env:AION2_COMPANION_SMOKE_REPORT)) { throw "No native report. Inspect $runRoot/aion2-meter/startup-error.log" }
    $report = Get-Content -LiteralPath $env:AION2_COMPANION_SMOKE_REPORT -Raw | ConvertFrom-Json
    if (-not $report.ok) { throw ($report | ConvertTo-Json -Depth 8) }
    $saved = Get-Content -LiteralPath "$runRoot/aion2-meter/companion.json" -Raw | ConvertFrom-Json
    if ($saved.petPhase -ne 2 -or $saved.overlayVisible -ne $false) { throw 'Preferences were not saved.' }
    if ($saved.PSObject.Properties.Name -contains 'locked') { throw 'Click-through must not persist.' }
    Write-Output ($report.checks -join "`n")
    Write-Output "Native smoke passed. Report: $runRoot/report.json"
} finally {
    $env:LOCALAPPDATA = $oldLocal
    $env:AION2_COMPANION_SMOKE_REPLAY = $oldReplay
    $env:AION2_COMPANION_SMOKE_REPORT = $oldReport
    $env:VITE_UI_SMOKE = $oldSmoke
    Pop-Location
}
