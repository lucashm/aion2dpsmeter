#!/usr/bin/env python3
"""Regenerates tray/icon-64.argb (raw 64x64 ARGB32, big-endian, what the tray
protocol takes) from desktop/aion2-meter.png. Needs Pillow."""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent.parent
img = Image.open(root / "desktop/aion2-meter.png").convert("RGBA").resize((64, 64), Image.LANCZOS)
rgba = img.tobytes()
argb = b"".join(bytes((rgba[i + 3], rgba[i], rgba[i + 1], rgba[i + 2])) for i in range(0, len(rgba), 4))
(root / "tray/icon-64.argb").write_bytes(argb)
