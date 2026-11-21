"""Generate CleanFrame's own bar textures as uncompressed 32-bit TGA files.

All art is drawn from scratch here (simple greyscale shading), so no third-party
artwork is shipped. The textures are white/grey so the game can tint them with
the bar colour (class colour, power colour, ...).

Usage:  python tools/make_bar_textures.py <AddonFolder>
Writes BarGradient.tga, BarGlossy.tga and BarStriped.tga to <AddonFolder>/Media/.
"""
import os
import struct
import sys

W, H = 64, 64  # power-of-two size; the game stretches it over the bar


def write_tga(path, rows):
    """rows: list of rows (top to bottom) of (r, g, b, a) tuples."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 0x28)
    with open(path, "wb") as f:
        f.write(header)
        for row in rows:
            for r, g, b, a in row:
                f.write(bytes((b, g, r, a)))


def grey(v):
    v = max(0, min(255, int(round(v * 255))))
    return (v, v, v, 255)


def gradient():
    # Light at the top, darker at the bottom.
    return [[grey(1.0 - 0.45 * (y / (H - 1)))] * W for y in range(H)]


def glossy():
    # A bright shine on the top half, flat colour below, a thin dark line at the bottom.
    rows = []
    for y in range(H):
        t = y / (H - 1)
        if t < 0.5:
            v = 1.0 - 0.25 * (t / 0.5)  # 1.0 -> 0.75
        else:
            v = 0.68
        if y >= H - 3:
            v = 0.5
        rows.append([grey(v)] * W)
    return rows


def striped():
    # Flat colour with faint diagonal stripes.
    rows = []
    for y in range(H):
        row = []
        for x in range(W):
            row.append(grey(0.82 if ((x + y) // 8) % 2 else 1.0))
        rows.append(row)
    return rows


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: python tools/make_bar_textures.py <AddonFolder>")
    media = os.path.join(sys.argv[1], "Media")
    os.makedirs(media, exist_ok=True)
    for name, fn in (("BarGradient", gradient), ("BarGlossy", glossy), ("BarStriped", striped)):
        write_tga(os.path.join(media, name + ".tga"), fn())
        print("wrote", name + ".tga")


if __name__ == "__main__":
    main()
