#!/usr/bin/env python3
"""Builds the app icons from desktop/art/{elyos,asmodian}.webp: the same cut of
both (her face and sword), so they match 1:1 apart from colour.
  desktop/aion2-meter-<faction>.png   256 px, rounded corners (app menu, notifications)
  tray/icon-<faction>-64.argb         64 px raw ARGB32, big-endian (the tray protocol's format)
Needs Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent.parent
CROP = (150, 120, 850, 820)  # in the 1254 px source images
SIZE, AA = 256, 4

for faction in ("elyos", "asmodian"):
    src = Image.open(root / f"desktop/art/{faction}.webp").convert("RGBA")
    assert src.size == (1254, 1254), f"{faction}: expected 1254x1254, got {src.size}"
    icon = src.crop(CROP).resize((SIZE, SIZE), Image.LANCZOS)
    # Rounded corners, drawn large and scaled down for a smooth edge.
    mask = Image.new("L", (SIZE * AA, SIZE * AA), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, SIZE * AA - 1, SIZE * AA - 1), radius=int(SIZE * AA * 0.18), fill=255)
    icon.putalpha(mask.resize((SIZE, SIZE), Image.LANCZOS))
    icon.save(root / f"desktop/aion2-meter-{faction}.png", optimize=True)

    rgba = icon.resize((64, 64), Image.LANCZOS).tobytes()
    argb = b"".join(bytes((rgba[i + 3], rgba[i], rgba[i + 1], rgba[i + 2])) for i in range(0, len(rgba), 4))
    (root / f"tray/icon-{faction}-64.argb").write_bytes(argb)
