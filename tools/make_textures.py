"""Generate the addon's own textures as uncompressed 32-bit TGA files.

All art is drawn from scratch here, so no third-party artwork is shipped.
Usage:  python tools/make_textures.py <AddonFolder>
Writes <AddonFolder>/Media/Arrow.tga and <AddonFolder>/Media/Pin.tga.
"""
import math
import os
import struct
import sys

SS = 4  # supersampling per axis for smooth edges


def write_tga(path, size, pixels):
    """pixels: list of rows (top to bottom) of (r, g, b, a) tuples."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    with open(path, "wb") as f:
        f.write(header)
        for row in pixels:
            for r, g, b, a in row:
                f.write(bytes((b, g, r, a)))


def point_in_poly(x, y, poly):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def shrink(poly, factor):
    cx = sum(p[0] for p in poly) / len(poly)
    cy = sum(p[1] for p in poly) / len(poly)
    return [(cx + (px - cx) * factor, cy + (py - cy) * factor) for px, py in poly]


def coverage(px, py, size, test):
    hits = 0
    for sy in range(SS):
        for sx in range(SS):
            x = (px + (sx + 0.5) / SS) / size
            y = (py + (sy + 0.5) / SS) / size
            if test(x, y):
                hits += 1
    return hits / (SS * SS)


def blend(top, bottom):
    """Alpha-composite two (r, g, b, a) colours with float alpha 0..1."""
    tr, tg, tb, ta = top
    br, bg, bb, ba = bottom
    a = ta + ba * (1 - ta)
    if a == 0:
        return (0, 0, 0, 0)
    r = (tr * ta + br * ba * (1 - ta)) / a
    g = (tg * ta + bg * ba * (1 - ta)) / a
    b = (tb * ta + bb * ba * (1 - ta)) / a
    return (r, g, b, a)


def make_arrow(path, size=64):
    # Chevron pointing up (towards the top of the texture).
    outer = [(0.50, 0.04), (0.90, 0.94), (0.50, 0.72), (0.10, 0.94)]
    inner = shrink(outer, 0.78)
    rows = []
    for py in range(size):
        row = []
        for px in range(size):
            c_out = coverage(px, py, size, lambda x, y: point_in_poly(x, y, outer))
            c_in = coverage(px, py, size, lambda x, y: point_in_poly(x, y, inner))
            # light-to-deep blue from tip to tail
            t = py / size
            blue = (40 + 30 * (1 - t), 140 + 60 * (1 - t), 255, c_in)
            edge = (10, 35, 90, c_out)
            r, g, b, a = blend(blue, edge)
            row.append((int(r), int(g), int(b), int(a * 255)))
        rows.append(row)
    write_tga(path, size, rows)


def make_pin(path, size=32):
    rows = []
    for py in range(size):
        row = []
        for px in range(size):
            def dist(x, y):
                return math.hypot(x - 0.5, y - 0.5)
            c_out = coverage(px, py, size, lambda x, y: dist(x, y) <= 0.48)
            c_ring = coverage(px, py, size, lambda x, y: dist(x, y) <= 0.40)
            fill = (35, 120, 235, c_ring)
            ring = (255, 255, 255, c_out)
            r, g, b, a = blend(fill, ring)
            row.append((int(r), int(g), int(b), int(a * 255)))
        rows.append(row)
    write_tga(path, size, rows)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: python tools/make_textures.py <AddonFolder>")
    media = os.path.join(sys.argv[1], "Media")
    os.makedirs(media, exist_ok=True)
    make_arrow(os.path.join(media, "Arrow.tga"))
    make_pin(os.path.join(media, "Pin.tga"))
    print("Wrote Arrow.tga and Pin.tga to", media)


if __name__ == "__main__":
    main()
