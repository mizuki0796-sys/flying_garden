"""Package the actual Godot engine-room capture without changing its animation."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--skill-root', type=Path, required=True)
parser.add_argument('--output', type=Path, default=ROOT / 'artifacts/game/engine-room-sprite-trial')
args = parser.parse_args()
out = args.output.resolve()
skill = args.skill_root.resolve()
sprite = skill / '.venv/Scripts/sprite-gen.exe'
ffmpeg = skill / '.tools/ffmpeg-9.0.2-essentials_build/bin/ffmpeg.exe'
img2webp = skill / '.tools/libwebp-1.6.0-windows-x64/bin/img2webp.exe'


def run(command):
    subprocess.run([str(v) for v in command], check=True)


capture = json.loads((out / 'capture.json').read_text(encoding='utf-8'))
frames = sorted((out / 'frames').glob('frame-*.png'))
assert len(frames) == capture['frames'] == 80
source_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in frames}
for frame in frames:
    with Image.open(frame) as im:
        assert im.mode == 'RGBA' and im.size == (480, 600)
        assert im.getchannel('A').getextrema()[0] == 0

run([sys.executable, ROOT / 'game/art_templates/complex_ui/verify_wheel_scope.py', '--output', out])
# Keep the authoritative background-composited preview for the original smoke opacity.
run([sys.executable, ROOT / 'game/art_templates/complex_ui/export_preview.py',
     '--frames', out / 'preview', '--output', out / 'power-room', '--fps', '20', '--ffmpeg', ffmpeg])

# This utility preserves the source order and timing; no loop search or retiming.
run([sprite, 'compose-gif', *frames, '--output', out / 'power-room-transparent.gif',
     '--delay-ticks', '5', '--manifest-output', out / 'sprite-gen-export.json'])
# WebP preserves graded smoke alpha; a GIF's one-bit alpha cannot do so.
run([img2webp, '-loop', '0', '-lossless', '-exact', '-d', '50', *frames,
     '-o', out / 'power-room-transparent.webp'])

run([ffmpeg, '-y', '-v', 'error', '-i', out / 'baseline/frame-000.png',
     '-i', out / 'frames/frame-000.png', '-filter_complex', 'hstack=inputs=2',
     '-frames:v', '1', out / 'comparison-before-after.png'])

artifacts = []
for name in ['power-room.gif', 'power-room-transparent.gif', 'power-room-transparent.webp']:
    with Image.open(out / name) as im:
        duration = 0
        for index in range(im.n_frames):
            im.seek(index)
            im.load()
            duration += im.info.get('duration', 0)
        assert im.n_frames == 80 and duration == 4000, (name, im.n_frames, duration)
        artifacts.append({'file': name, 'frames': im.n_frames, 'duration_ms': duration})
assert source_hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in frames}

source_files = [ROOT / 'game/assets/pixel_v2/facilities/engine_room_v2.png',
                ROOT / 'game/assets/pixel_v2/facilities/engine_room_layers_v1/flywheel.png',
                ROOT / 'game/scripts/engine_room_animation.gd', ROOT / 'game/scripts/main.gd']
result = {
    'status': 'passed', 'new_ai_generation': False, 'paid_generation_calls': 0,
    'source_frames_unchanged_by_packaging': True,
    'animation_exports': artifacts,
    'seamless_loop': False,
    'source_hashes': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files},
    'frames_sha256': source_hashes,
    'note': 'PNG/WebP preserve graded alpha. GIF is a preview; MP4 has an opaque background.',
}
(out / 'package-verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({k: v for k, v in result.items() if k != 'frames_sha256'}, ensure_ascii=False, indent=2))
