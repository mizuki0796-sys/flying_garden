param(
    [string]$FFmpeg = 'C:\Users\32043\.codex\skills\sprite-gen\.tools\ffmpeg-9.0.2-essentials_build\bin\ffmpeg.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outputRoot = Join-Path $projectRoot 'artifacts\game\collector-single-tile-animation'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$previousAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $projectRoot '.codex_tmp\godot-user'
    $render = Start-Process -FilePath (Join-Path $projectRoot '.codex_tmp\godot-4.7.2\Godot_v4.7.2-stable_win64.exe') -ArgumentList @('--path', ('"' + (Join-Path $projectRoot 'game') + '"'), '--script', 'res://tests/collector_propellers_preview.gd', '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--position', '-20000,-20000', '--log-file', ('"' + (Join-Path $outputRoot 'godot.log') + '"')) -WindowStyle Hidden -PassThru
    if (-not $render.WaitForExit(60000)) {
        $render.Kill()
        throw 'Preview timed out; inspect godot.log.'
    }
    if ($render.ExitCode -ne 0 -or (Select-String -LiteralPath (Join-Path $outputRoot 'godot.log') -Pattern 'SCRIPT ERROR|SHADER ERROR' -Quiet)) { throw 'Rendering or pixel checks failed.' }
    if (-not (Select-String -LiteralPath (Join-Path $outputRoot 'godot.log') -Pattern 'COLLECTOR PROPELLERS:' -Quiet)) { throw 'Preview did not complete its checks.' }
} finally {
    $env:APPDATA = $previousAppData
}
$sequence = Join-Path $outputRoot 'frames\frame-%03d.png'
& $FFmpeg -y -loglevel error -framerate 50 -i $sequence -filter_complex '[0:v]split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=none' -loop 0 (Join-Path $outputRoot 'collector-propellers.gif')
if ($LASTEXITCODE -ne 0) { throw 'GIF encoding failed.' }
& $FFmpeg -y -loglevel error -framerate 50 -i $sequence -c:v libx264 -crf 18 -pix_fmt yuv420p -movflags +faststart (Join-Path $outputRoot 'collector-propellers.mp4')
if ($LASTEXITCODE -ne 0) { throw 'MP4 encoding failed.' }
foreach ($extension in @('gif', 'mp4')) {
    & $FFmpeg -v error -i (Join-Path $outputRoot "collector-propellers.$extension") -f null -
    if ($LASTEXITCODE -ne 0) { throw "Invalid $extension preview." }
}
Get-Content -LiteralPath (Join-Path $outputRoot 'validation.json')
