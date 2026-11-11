"""Pack original wall tops and front faces for exposed ring cells."""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
LIB = ROOT / "asset-library/01_islands_sky/flying_garden_wall_tiles_v1"
materials = json.loads((LIB / "integration_catalog.json").read_text(encoding="utf-8"))["materials"]
atlas = Image.new("RGBA", (12 * 80, len(materials) * 64))
for row, material in enumerate(materials):
    for column, variant in enumerate(material["variants"]):
        with Image.open(ROOT / variant["path"]) as source:
            for key, height, offset in [("source_face", 50, 0), ("source_bottom", 14, 50)]:
                x, y, w, h = material[key]
                assert x + w <= source.width and y + h <= source.height
                face = source.crop((x, y, x + w, y + h)).resize((80, height), Image.Resampling.BOX)
                atlas.paste(face, (column * 80, row * 64 + offset))
atlas.save(ROOT / "game/assets/pixel_v2/walls/exposed.png")
