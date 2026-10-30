param(
    [string]$Godot = '.codex_tmp/godot-4.7.2/Godot_v4.7.2-stable_win64.exe',
    [string]$FFmpeg = '.codex_tmp/video-tools/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
Push-Location $projectRoot
$previousAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $projectRoot '.codex_tmp/layout-appdata'
    foreach ($script in @('island_layout_test', 'cyclone_smoke_preview')) {
        $log = Join-Path $projectRoot "artifacts/game/$script.log"
        $job = Start-Process -FilePath $Godot -ArgumentList @('--path', 'game', '--script', "res://tests/$script.gd", '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--position', '-20000,-20000', '--log-file', ('"' + $log + '"')) -WindowStyle Hidden -PassThru
        if (-not $job.WaitForExit(60000)) { throw "Preview timed out; process $($job.Id), log $log" }
        if ($job.ExitCode -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|[1-9][0-9]* failures|Smoke change altered' -Quiet)) { throw "Preview failed; see $log" }
    }
    $output = 'artifacts/game/cyclone-smoke'
    & $FFmpeg -y -loglevel error -framerate 20 -i "$output/frames/frame-%03d.png" -filter_complex '[0:v]split[a][b];[a]palettegen[p];[b][p]paletteuse' "$output/cyclone.gif"
    if ($LASTEXITCODE -ne 0) { throw 'GIF encoding failed' }
    & $FFmpeg -y -loglevel error -framerate 20 -i "$output/frames/frame-%03d.png" -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$output/cyclone.mp4"
    if ($LASTEXITCODE -ne 0) { throw 'MP4 encoding failed' }
    & $FFmpeg -v error -i "$output/cyclone.mp4" -f null -
    if ($LASTEXITCODE -ne 0) { throw 'MP4 decoding failed' }
} finally {
    $env:APPDATA = $previousAppData
    Pop-Location
}
