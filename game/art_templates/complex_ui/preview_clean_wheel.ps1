param(
    [string]$Python = 'C:\Users\32043\.codex\skills\sprite-gen\.venv\Scripts\python.exe',
    [string]$FFmpeg = 'C:\Users\32043\.codex\skills\sprite-gen\.tools\ffmpeg-9.0.2-essentials_build\bin\ffmpeg.exe',
    [switch]$ExportOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outputRoot = Join-Path $projectRoot 'artifacts\game\engine-wheel-clean'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
if (-not $ExportOnly) {
    $godotBinary = Join-Path $projectRoot '.codex_tmp\godot-4.7.2\Godot_v4.7.2-stable_win64.exe'
    $gamePath = Join-Path $projectRoot 'game'
    $logFile = Join-Path $outputRoot 'godot.log'
    $previousAppData = $env:APPDATA
    try {
        $env:APPDATA = Join-Path $projectRoot '.codex_tmp\godot-user'
        $renderProcess = Start-Process -FilePath $godotBinary -ArgumentList @('--path', ('"' + $gamePath + '"'), '--script', 'res://tests/engine_wheel_clean_preview.gd', '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--position', '-20000,-20000', '--log-file', ('"' + $logFile + '"')) -WindowStyle Hidden -PassThru
        if (-not $renderProcess.WaitForExit(60000)) { throw 'Rendering exceeded 60 seconds; inspect godot.log.' }
        if ($renderProcess.ExitCode -ne 0) { throw "Godot failed: $($renderProcess.ExitCode)" }
        if (Select-String -LiteralPath $logFile -Pattern 'SCRIPT ERROR|ERROR:' -Quiet) { throw 'Godot logged an error.' }
    } finally {
        $env:APPDATA = $previousAppData
    }
}
& $Python (Join-Path $PSScriptRoot 'verify_clean_wheel.py')
if ($LASTEXITCODE -ne 0) { throw 'Pixel scope verification failed.' }
foreach ($entry in @(@('frames', 'power-room-clean'), @('detail', 'flywheel-detail'))) {
    & $Python (Join-Path $PSScriptRoot 'export_preview.py') --frames (Join-Path $outputRoot $entry[0]) --output (Join-Path $outputRoot $entry[1]) --fps 20 --ffmpeg $FFmpeg
    if ($LASTEXITCODE -ne 0) { throw 'Preview encoding or decoding failed.' }
}
& $Python (Join-Path $PSScriptRoot 'report_clean_wheel.py')
if ($LASTEXITCODE -ne 0) { throw 'Preview report failed.' }
