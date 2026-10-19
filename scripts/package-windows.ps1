[CmdletBinding()]
param([string]$Version = 'dev')
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw 'Version must be a plain filename component.' }
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    npm --prefix windows/ui ci
    if ($LASTEXITCODE -ne 0) { throw 'Companion dependency install failed.' }
    # A normal production build excludes the opt-in smoke controller.
    $previousSmoke = $env:VITE_UI_SMOKE
    try {
        $env:VITE_UI_SMOKE = ''
        npm --prefix windows/ui run build
        if ($LASTEXITCODE -ne 0) { throw 'Companion UI build failed.' }
    } finally { $env:VITE_UI_SMOKE = $previousSmoke }
    & "$PSScriptRoot/prepare-windows.ps1"
    cargo build --locked --release --target x86_64-pc-windows-msvc -p aion2-meterd -p aion2-meter-windows
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
    $name = "aion2-meter-$Version-x86_64-windows"
    $dist = Join-Path $root 'dist'
    $out = Join-Path $dist $name
    # Resolve and bound the generated destination before recursive removal.
    $expected = [IO.Path]::GetFullPath($out)
    $distPrefix = [IO.Path]::GetFullPath($dist) + [IO.Path]::DirectorySeparatorChar
    if (-not $expected.StartsWith($distPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Package destination is outside dist.' }
    if (Test-Path -LiteralPath $expected) { Remove-Item -LiteralPath $expected -Recurse -Force }
    New-Item -ItemType Directory -Force -Path "$out/data/i18n", "$out/docs" | Out-Null
    Copy-Item -LiteralPath 'target/x86_64-pc-windows-msvc/release/aion2-meterd.exe', 'target/x86_64-pc-windows-msvc/release/aion2-meter-windows.exe' -Destination $out
    $data = 'third_party/a2tools/src/data'
    Copy-Item -LiteralPath "$data/i18n/skills", "$data/i18n/npcs" -Destination "$out/data/i18n" -Recurse
    Copy-Item -LiteralPath "$data/dot_skill_ids.json", "$data/skill_icons.json", "$data/abnormals.json" -Destination "$out/data"
    Copy-Item -LiteralPath 'LICENSE', 'README.md', 'CHANGELOG.md' -Destination $out
    Copy-Item -LiteralPath 'docs/windows.md' -Destination "$out/WINDOWS.md"
    Copy-Item -LiteralPath 'docs/windows.md' -Destination "$out/docs/windows.md"
    Copy-Item -LiteralPath 'docs/windows-ui-stack.md', 'docs/windows-ui-design.md' -Destination "$out/docs"
    $zip = Join-Path $dist "$name.zip"
    Compress-Archive -Path $out -DestinationPath $zip -Force
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText("$zip.sha256", "$hash  $name.zip`n")
    Write-Output $zip
} finally { Pop-Location }
