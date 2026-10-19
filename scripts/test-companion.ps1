# Native WebView2 -> Rust -> real daemon replay -> four HWND overlays.
# The report command exists only with the ui-smoke feature.
[CmdletBinding()]
param([switch]$SkipBuild, [switch]$Release, [switch]$MeasureIdle)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$runRoot = Join-Path $root ('target/companion-smoke-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path "$runRoot/aion2-meter" | Out-Null
$oldLocal = $env:LOCALAPPDATA
$oldReplay = $env:AION2_COMPANION_SMOKE_REPLAY
$oldReport = $env:AION2_COMPANION_SMOKE_REPORT
$oldSmoke = $env:VITE_UI_SMOKE
$oldHold = $env:AION2_COMPANION_SMOKE_HOLD_MS
Push-Location $root
try {
    if (-not $SkipBuild) {
        $env:VITE_UI_SMOKE = '1'
        npm --prefix windows/ui run build
        if ($LASTEXITCODE -ne 0) { throw 'Smoke UI build failed.' }
        & "$PSScriptRoot/prepare-windows.ps1"
        $buildArgs = @('build', '--locked', '-p', 'aion2-meterd', '-p', 'aion2-meter-windows', '--features', 'ui-smoke')
        if ($Release) { $buildArgs += @('--release', '--target', 'x86_64-pc-windows-msvc') }
        & cargo @buildArgs
        if ($LASTEXITCODE -ne 0) { throw 'Smoke native build failed.' }
    }
    $pcap = Join-Path $runRoot 'fixture.pcap'
    python -c "import importlib.util,pathlib,sys;s=importlib.util.spec_from_file_location('fixture','scripts/test-daemon.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.write_capture(pathlib.Path(sys.argv[1]))" $pcap
    if ($LASTEXITCODE -ne 0) { throw 'Could not generate the replay fixture.' }
    @{ autoStart = $false; sound = $false; overlayVisible = [bool]$MeasureIdle } | ConvertTo-Json | Set-Content -LiteralPath "$runRoot/aion2-meter/companion.json" -Encoding utf8
    New-Item -ItemType Directory -Force -Path "$runRoot/aion2-meter/fights" | Out-Null
    Copy-Item -LiteralPath 'windows/testdata/fight.json' -Destination "$runRoot/aion2-meter/fights/desktop_fixture.json"
    $env:LOCALAPPDATA = $runRoot
    $env:AION2_COMPANION_SMOKE_REPLAY = $pcap
    $env:AION2_COMPANION_SMOKE_REPORT = Join-Path $runRoot 'report.json'
    $env:AION2_COMPANION_SMOKE_HOLD_MS = if ($MeasureIdle) { '20000' } else { '0' }
    $binaryDir = if ($Release) { "$root/target/x86_64-pc-windows-msvc/release" } else { "$root/target/debug" }
    $process = Start-Process -FilePath "$binaryDir/aion2-meter-windows.exe" -WindowStyle Hidden -PassThru
    if ($MeasureIdle) {
        $ready = Join-Path $runRoot 'report.ready.json'
        $deadline = [DateTime]::UtcNow.AddSeconds(25)
        while (-not (Test-Path -LiteralPath $ready)) {
            if ($process.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw "Idle measurement did not become ready: $runRoot" }
            Start-Sleep -Milliseconds 100
        }
        # Include the companion, native overlay child and all WebView2 descendants.
        function Read-AppUsage([int]$rootId) {
            $inventory = @(Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId)
            $ids = [Collections.Generic.HashSet[int]]::new()
            [void]$ids.Add($rootId)
            do {
                $added = $false
                foreach ($item in $inventory) {
                    if ($ids.Contains([int]$item.ParentProcessId) -and $ids.Add([int]$item.ProcessId)) { $added = $true }
                }
            } while ($added)
            $children = @(Get-Process -Id @($ids) -ErrorAction SilentlyContinue)
            [pscustomobject]@{ cpu = ($children.CPU | Measure-Object -Sum).Sum; privateBytes = ($children.PrivateMemorySize64 | Measure-Object -Sum).Sum; count = $children.Count; time = [DateTime]::UtcNow }
        }
        $before = Read-AppUsage $process.Id
        Start-Sleep -Seconds 5
        $after = Read-AppUsage $process.Id
        $seconds = ($after.time - $before.time).TotalSeconds
        $corePercent = 100 * ($after.cpu - $before.cpu) / $seconds
        $measurement = [ordered]@{ configuration = 'Visible companion + four idle native widgets; capture stopped'; release = [bool]$Release; seconds = [Math]::Round($seconds, 2); processCount = $after.count; privateCommitMiB = [Math]::Round($after.privateBytes / 1MB, 1); cpuOneCorePercent = [Math]::Round($corePercent, 2); cpuMachinePercent = [Math]::Round($corePercent / [Environment]::ProcessorCount, 2); logicalProcessors = [Environment]::ProcessorCount }
        $measurement | ConvertTo-Json | Set-Content -LiteralPath "$runRoot/performance.json" -Encoding utf8
        Write-Output ($measurement | ConvertTo-Json -Compress)
    }
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
    $env:AION2_COMPANION_SMOKE_HOLD_MS = $oldHold
    Pop-Location
}
