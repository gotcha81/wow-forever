"""Generate the addon's own textures as uncompressed 32-bit TGA files.

All art is drawn from scratch here, so no third-party artwork is shipped.
Usage:  python tools/make_textures.py <AddonFolder>
Writes Arrow.tga, Pin.tga, Dot.tga, Locked.tga, Unlocked.tga and Cog.tga to <AddonFolder>/Media/.
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


def make_dot(path, size=16):
    """Small blue dot with a dark edge: quest objective spots on the maps."""
    rows = []
    for py in range(size):
        row = []
        for px in range(size):
            def dist(x, y):
                return math.hypot(x - 0.5, y - 0.5)
            c_out = coverage(px, py, size, lambda x, y: dist(x, y) <= 0.46)
            c_in = coverage(px, py, size, lambda x, y: dist(x, y) <= 0.34)
            fill = (90, 175, 255, c_in)
            edge = (10, 35, 90, c_out)
            r, g, b, a = blend(fill, edge)
            row.append((int(r), int(g), int(b), int(a * 255)))
        rows.append(row)
    write_tga(path, size, rows)


def make_lock(path, opened, size=32):
    """Gold padlock. `opened` lifts the shackle and swings it to the right."""
    body = (0.20, 0.46, 0.80, 0.92)  # x0, y0, x1, y1 of the lock body
    lift = 0.10 if opened else 0.0
    shift = 0.17 if opened else 0.0
    cx, cy, r_out, r_in = 0.50 + shift, 0.46 - lift, 0.24, 0.14

    def in_body(x, y):
        return body[0] <= x <= body[2] and body[1] <= y <= body[3]

    def in_shackle(x, y):
        d = math.hypot(x - cx, y - cy)
        ring = r_in <= d <= r_out and y <= cy
        leg_l = (cx - r_out) <= x <= (cx - r_in) and cy <= y <= body[1] + 0.02
        leg_r = (cx + r_in) <= x <= (cx + r_out) and cy <= y <= body[1] + 0.02
        if opened:
            leg_l = False  # the free end hangs open
        return ring or leg_l or leg_r

    def in_keyhole(x, y):
        return math.hypot(x - 0.50, y - 0.64) <= 0.06 or (0.47 <= x <= 0.53 and 0.64 <= y <= 0.80)

    rows = []
    for py in range(size):
        row = []
        for px in range(size):
            c_body = coverage(px, py, size, lambda x, y: in_body(x, y) and not in_keyhole(x, y))
            c_shackle = coverage(px, py, size, in_shackle)
            gold = (255, 205, 60, c_body)
            steel = (210, 210, 215, c_shackle)
            r, g, b, a = blend(gold, steel)
            row.append((int(r), int(g), int(b), int(a * 255)))
        rows.append(row)
    write_tga(path, size, rows)


def make_cog(path, size=32, teeth=8):
    """Silver cogwheel with a hole in the middle."""
    def in_cog(x, y):
        dx, dy = x - 0.5, y - 0.5
        d = math.hypot(dx, dy)
        angle = math.atan2(dy, dx) % (2 * math.pi)
        phase = (angle / (2 * math.pi) * teeth) % 1.0
        outer = 0.47 if phase < 0.5 else 0.36  # teeth and the gaps between them
        return 0.15 <= d <= outer

    rows = []
    for py in range(size):
        row = []
        for px in range(size):
            c = coverage(px, py, size, in_cog)
            shade = 200 + int(40 * (1 - py / size))  # lighter at the top
            row.append((shade, shade, min(255, shade + 10), int(c * 255)))
        rows.append(row)
    write_tga(path, size, rows)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: python tools/make_textures.py <AddonFolder>")
    media = os.path.join(sys.argv[1], "Media")
    os.makedirs(media, exist_ok=True)
    make_arrow(os.path.join(media, "Arrow.tga"))
    make_pin(os.path.join(media, "Pin.tga"))
    make_dot(os.path.join(media, "Dot.tga"))
    make_lock(os.path.join(media, "Locked.tga"), opened=False)
    make_lock(os.path.join(media, "Unlocked.tga"), opened=True)
    make_cog(os.path.join(media, "Cog.tga"))
    print("Wrote Arrow, Pin, Dot, Locked, Unlocked and Cog textures to", media)


if __name__ == "__main__":
    main()
