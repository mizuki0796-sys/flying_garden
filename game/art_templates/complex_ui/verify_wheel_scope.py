"""Verify the engine's unchanged area against same-time original/smoke frames."""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=ROOT / "artifacts/game/engine-wheel-only")
OUTPUT = parser.parse_args().output.resolve()
frames = sorted((OUTPUT / "frames").glob("frame-*.png"))
assert len(frames) == 80, "Capture the 80-frame reference and modified sequences first"
source = ROOT / "game/assets/pixel_v2/facilities/engine_room_v2.png"
assert hashlib.sha256(source.read_bytes()).hexdigest() == "7c9d2499ee2e6796260c1bd5177f71bc952474186e7abd2fc897e9fc5cd99903"
scale = 276 / 958
origin_x, origin_y = 102 - 295 * scale, 552 - 936 * scale
y, x = np.mgrid[:600, :480]
# 2 screen pixels of explicit rasterization tolerance at the ellipse perimeter.
mask = ((x - (origin_x + 1024 * scale)) / (188 * scale + 2)) ** 2 + ((y - (origin_y + 660 * scale)) / (211 * scale + 2)) ** 2 <= 1
outside_changes = smoke_changes = changed_frames = 0
source_x = (x + 0.5 - origin_x) / scale
source_y = (y + 0.5 - origin_y) / scale
connectors = np.zeros_like(mask)
for rx, ry, rw, rh in [(817, 648, 145, 110), (962, 666, 37, 38), (999, 648, 55, 76)]:
    connectors |= (source_x > rx + 3) & (source_x < rx + rw - 3) & (source_y > ry + 3) & (source_y < ry + rh - 3)
wall_samples = np.zeros_like(mask)
for rx, ry, rw, rh in [(844, 454, 42, 48), (915, 430, 40, 32), (1135, 450, 25, 42)]:
    wall_samples |= (source_x > rx) & (source_x < rx + rw) & (source_y > ry) & (source_y < ry + rh)
connector_changes = wall_changes = 0
first_frame = None
animated = False
for frame in frames:
    actual = np.array(Image.open(frame))
    original = np.array(Image.open(OUTPUT / "baseline" / frame.name))
    assert actual.shape == original.shape and actual.shape[:2] == (600, 480)
    changed = np.any(actual != original, axis=2)
    outside_changes += int(np.count_nonzero(changed & ~mask))
    smoke_changes += int(np.count_nonzero(changed[:300]))
    connector_changes += int(np.count_nonzero(changed & connectors))
    wall_changes += int(np.count_nonzero(changed & wall_samples))
    changed_frames += bool(np.any(changed & mask))
    if first_frame is None:
        first_frame = actual.copy()
    else:
        animated |= bool(np.any(actual[mask] != first_frame[mask]))
result = {"frames": len(frames), "outside_wheel_changed_pixels": outside_changes,
          "smoke_changed_pixels": smoke_changes, "wheel_changed_frames": changed_frames,
          "wheel_animates": animated, "original_png_hash_unchanged": True}
result.update({"connector_changed_pixels": connector_changes, "sampled_wall_changed_pixels": wall_changes})
(OUTPUT / "verification.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print(json.dumps(result, indent=2))
assert outside_changes == 0 and smoke_changes == 0 and animated and changed_frames == len(frames)
assert connector_changes == 0 and wall_changes == 0
