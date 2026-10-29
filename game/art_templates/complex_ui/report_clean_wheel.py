"""Package captured images and provenance; never modify game artwork."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / "artifacts/game/engine-wheel-clean"
tiles = [
    ("Original", OUTPUT / "detail-baseline/frame-000.png"),
    ("t = 0.00 s", OUTPUT / "detail/frame-000.png"),
    ("t = 0.60 s", OUTPUT / "detail/frame-012.png"),
    ("t = 1.20 s", OUTPUT / "detail/frame-024.png"),
]
sheet = Image.new("RGB", (480*len(tiles),632), "#a9d9d8")
draw = ImageDraw.Draw(sheet)
for index,(label,path) in enumerate(tiles):
    sheet.paste(Image.open(path).convert("RGB"), (index*480,32))
    draw.text((index*480+16,10),label,fill="#244d46")
sheet.save(OUTPUT / "comparison.png")
paths = [
    "game/assets/pixel_v2/facilities/engine_room_v2.png",
    "game/assets/pixel_v2/facilities/engine_room_layers_v1/flywheel.png",
    "game/scripts/engine_room_animation.gd",
    "game/tests/engine_wheel_clean_preview.gd",
    "game/tests/engine_wheel_preview_canvas.gd",
    "game/scripts/main.gd",
]
manifest = {
    "renderer": "game/scripts/main.gd::_draw_building",
    "frames": 80, "fps": 20, "duration_seconds": 4,
    "seamless_loop": False, "speed_radians_per_second": 2.8,
    "new_artwork": False, "spoke_grid_source_pixels": 18, "cached_phases": 128,
    "fixed_foreground": "complete connecting rod, copper bearing, silver axle cap",
    "fixed_rim": True, "smoke_changed": False,
    "reproduce": "game/art_templates/complex_ui/preview_clean_wheel.ps1",
    "sha256": {path:hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in paths},
}
(OUTPUT / "manifest.json").write_text(json.dumps(manifest,indent=2),encoding="utf-8")
print("Saved comparison.png and manifest.json")
