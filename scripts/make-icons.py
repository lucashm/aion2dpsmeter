#!/usr/bin/env python3
"""Draws the app icons: a DPS meter's four rows on a dark rounded square, in
each faction's colours. Original art, so the repo holds none of the game's.
  desktop/aion2-meter-<faction>.png   256 px (app menu, notifications)
  tray/icon-<faction>-64.argb         64 px raw ARGB32, big-endian (the tray protocol's format)
Needs Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent.parent
SIZE, AA = 256, 4
S = SIZE * AA

# (background top, background bottom, bar bottom, bar top)
FACTIONS = {
    "elyos": ((0x1E, 0x2A, 0x44), (0x0C, 0x12, 0x20), (0xC8, 0x8A, 0x2E), (0xFF, 0xD9, 0x7A)),
    "asmodian": ((0x2E, 0x1A, 0x40), (0x12, 0x09, 0x1C), (0x7A, 0x3F, 0xD9), (0xD6, 0xA8, 0xFF)),
}


def vertical(size, top, bottom):
    """A top-to-bottom gradient."""
    w, h = size
    g = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        g.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return g.resize((w, h))


def draw(bg_top, bg_bottom, bar_bottom, bar_top):
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shape = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shape).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.22), fill=255)
    icon.paste(vertical((S, S), bg_top, bg_bottom), (0, 0), shape)

    # The meter's rows: four bars, longest first, sharing one gradient so the top one is brightest.
    bars = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(bars)
    left, top, thick, gap = int(S * 0.20), int(S * 0.22), int(S * 0.11), int(S * 0.057)
    for i, length in enumerate((0.60, 0.46, 0.33, 0.21)):
        y = top + i * (thick + gap)
        d.rounded_rectangle((left, y, left + int(S * length), y + thick), radius=int(thick * 0.32), fill=255)
    icon.paste(vertical((S, S), bar_top, bar_bottom), (0, 0), bars)

    # A thin edge in the bar colour, so the icon holds on dark panels.
    ImageDraw.Draw(icon).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.22),
                                           outline=bar_bottom + (150,), width=int(S * 0.012))
    return icon.resize((SIZE, SIZE), Image.LANCZOS)


for faction, colours in FACTIONS.items():
    icon = draw(*colours)
    icon.save(root / f"desktop/aion2-meter-{faction}.png", optimize=True)

    rgba = icon.resize((64, 64), Image.LANCZOS).tobytes()
    argb = b"".join(bytes((rgba[i + 3], rgba[i], rgba[i + 1], rgba[i + 2])) for i in range(0, len(rgba), 4))
    assert len(argb) == 64 * 64 * 4
    (root / f"tray/icon-{faction}-64.argb").write_bytes(argb)
