"""Compare real game renders against same-time master/smoke at two scales."""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / "artifacts/game/engine-wheel-clean"
# Independent tracing of the user's marked foreground, in master coordinates.
ROD = np.array([
    (817,631),(920,631),(934,666),(962,666),(962,648),(980,648),
    (980,631),(998,631),(998,613),(1070,613),(1070,631),(1088,631),
    (1088,721),(1070,721),(1070,739),(980,739),(980,721),(932,721),
    (926,757),(817,757),
])
OPENING = [(523,962,1088),(541,944,1106),(559,926,1124),(577,908,1142),
           (595,890,1142),(613,890,1142),(631,890,1142),(649,890,1142),
           (667,890,1142),(685,890,1142),(703,908,1142),(721,926,1142),
           (739,944,1124),(757,944,1106),(775,962,1106),(793,980,1088)]

def in_polygon(x, y, points):
    inside = np.zeros(x.shape, dtype=bool)
    for (x1,y1),(x2,y2) in zip(points, np.roll(points,-1,axis=0)):
        if y1 == y2:
            continue
        inside ^= ((y1 > y) != (y2 > y)) & (x < (x2-x1)*(y-y1)/(y2-y1)+x1)
    return inside

def verify(folder, baseline, zoom, bottom):
    paths = sorted((OUTPUT / folder).glob("frame-*.png"))
    assert len(paths) == 80
    scale = 92 * zoom / 958
    origin_x, origin_y = bottom[0] - 774*scale, bottom[1] - 936*scale
    y, x = np.mgrid[:600,:480]
    sx, sy = (x+0.5-origin_x)/scale, (y+0.5-origin_y)/scale
    rod = in_polygon(sx, sy, ROD)
    opening = np.zeros(x.shape, dtype=bool)
    for top,left,right in OPENING:
        opening |= (sx >= left) & (sx < right) & (sy >= top) & (sy < top+18)
    allowed = opening & ~rod
    result = dict(frames=80, outside_opening_changed_pixels=0,
                  connecting_rod_changed_pixels=0, smoke_changed_pixels=0,
                  animated_frame_transitions=0, scale=zoom)
    previous = None
    for path in paths:
        actual = np.array(Image.open(path).convert("RGBA"))
        original = np.array(Image.open(OUTPUT / baseline / path.name).convert("RGBA"))
        assert actual.shape == original.shape == (600,480,4)
        changed = np.any(actual != original,axis=2)
        result["outside_opening_changed_pixels"] += int(np.count_nonzero(changed & ~allowed))
        result["connecting_rod_changed_pixels"] += int(np.count_nonzero(changed & rod))
        result["smoke_changed_pixels"] += int(np.count_nonzero(changed & (sy < 430)))
        if previous is not None:
            result["animated_frame_transitions"] += bool(np.any(actual[allowed] != previous[allowed]))
        previous = actual
    return result

def main():
    source = ROOT / "game/assets/pixel_v2/facilities/engine_room_v2.png"
    master_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    assert master_hash == "7c9d2499ee2e6796260c1bd5177f71bc952474186e7abd2fc897e9fc5cd99903"
    results = {
        "master_sha256": master_hash, "new_artwork": False,
        "full_building": verify("frames","baseline",3,(240,552)),
        "close_up": verify("detail","detail-baseline",12,(0,590)),
    }
    (OUTPUT / "verification.json").write_text(json.dumps(results,indent=2),encoding="utf-8")
    print(json.dumps(results,indent=2))
    for name in ["full_building","close_up"]:
        result = results[name]
        assert result["outside_opening_changed_pixels"] == 0, name
        assert result["connecting_rod_changed_pixels"] == 0, name
        assert result["smoke_changed_pixels"] == 0, name
        assert result["animated_frame_transitions"] == 79, name

if __name__ == "__main__":
    main()
