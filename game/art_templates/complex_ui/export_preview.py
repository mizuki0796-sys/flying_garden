"""Encode an existing Godot PNG sequence without changing the source frames."""
import argparse
from pathlib import Path
import subprocess
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="Output prefix without suffix")
    parser.add_argument("--fps", type=int, default=20)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    args = parser.parse_args()
    files = sorted(args.frames.glob("frame-*.png"))
    if not files or args.fps <= 0:
        parser.error("A nonempty numbered sequence and positive FPS are required")
    for index, path in enumerate(files):
        if path.name != f"frame-{index:03d}.png":
            parser.error("Frames must be contiguous and start at frame-000.png")
    frames = [Image.open(path).convert("RGB") for path in files]
    if len({image.size for image in frames}) != 1:
        parser.error("All frames must have the same size")
    width, height = frames[0].size
    if width % 2 or height % 2:
        parser.error("H.264 yuv420p export requires even dimensions; fix the capture canvas")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # One palette across the entire GIF avoids frame-by-frame color flicker.
    samples = frames[::max(1, len(frames) // 12)]
    swatch = Image.new("RGB", (width, height * len(samples)))
    for index, frame in enumerate(samples):
        swatch.paste(frame, (0, index * height))
    palette = swatch.quantize(colors=256)
    quantized = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    gif = args.output.with_suffix(".gif")
    quantized[0].save(gif, save_all=True, append_images=quantized[1:], duration=round(1000 / args.fps), loop=0, optimize=False)
    mp4 = args.output.with_suffix(".mp4")
    subprocess.run([str(args.ffmpeg), "-y", "-loglevel", "error", "-framerate", str(args.fps),
                    "-i", str(args.frames / "frame-%03d.png"), "-c:v", "libx264", "-crf", "18",
                    "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(mp4)], check=True)
    subprocess.run([str(args.ffmpeg), "-v", "error", "-i", str(mp4), "-f", "null", "-"], check=True)
    with Image.open(gif) as encoded:
        assert encoded.n_frames == len(frames)
    print(f"Encoded and decoded {len(frames)} frames, {args.fps} FPS, {len(frames)/args.fps:.2f}s: {mp4}")


if __name__ == "__main__":
    main()
