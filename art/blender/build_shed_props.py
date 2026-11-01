"""Things round the outside of the tool shed: a woodpile along the south wall,
a rain barrel, a lantern by the door, crates, a chopping block with an axe and
a stovepipe through the roof. Writes models/shed_props.glb, authored in world
coordinates (the shed itself is built in scripts/shed.gd: room x 9..17,
z 8..15, walls 0.2 thick, 3.2 high, ridge 2 m above, door in the west wall).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403

LOG_END = (0.84, 0.66, 0.44)
BARK = (0.38, 0.26, 0.17)
WOOD = (0.55, 0.38, 0.23)
WOOD_DARK = (0.36, 0.23, 0.14)
IRON = (0.2, 0.2, 0.22)


def log(objs, a, b, r):
    # Bark round the side, pale cut rings at the ends.
    objs.append(cyl(a, b, r, r * 0.97, mat("bark", BARK, 0.95), 7, smooth=False))
    d = (Vector(b) - Vector(a)).normalized() * 0.006
    objs.append(cyl(Vector(a) - d, Vector(a) + d, r * 0.85, r * 0.85, mat("log_end", LOG_END, 0.9), 7, smooth=False))
    objs.append(cyl(Vector(b) - d, Vector(b) + d, r * 0.82, r * 0.82, mat("log_end", LOG_END, 0.9), 7, smooth=False))


def woodpile(objs, x0, x1, z, rng):
    # Logs lie along z (ends facing out from the wall), stacked in rows, with
    # a little lean-to roof over them.
    r = 0.09
    rows = 6
    for row in range(rows):
        y = r + row * r * 1.72
        n = int((x1 - x0) / (2 * r)) - (row % 2)
        for k in range(n):
            x = x0 + r * (1 + row % 2) + k * 2 * r + rng.uniform(-0.01, 0.01)
            rr = r * rng.uniform(0.85, 1.05)
            dz = rng.uniform(-0.04, 0.04)
            log(objs, (x, y, z - 0.25 + dz), (x, y, z + 0.27 + dz), rr)
    top = r + rows * r * 1.72 + 0.12
    for x in (x0 - 0.06, x1 + 0.06):
        objs.append(box((x, top * 0.5, z + 0.32), (0.08, top, 0.08), mat("wood_dark", WOOD_DARK, 0.85), None, 0.01))
    objs.append(box(((x0 + x1) * 0.5, top + 0.08, z + 0.1), (x1 - x0 + 0.4, 0.05, 0.75),
                    mat("tin", (0.42, 0.45, 0.48), 0.45, 0.6), rot_x(-0.22), 0.01))
    objs.append(boxlh((x0 - 0.1, 0.0, z - 0.3), (x1 + 0.1, 0.05, z + 0.32), mat("wood_dark", WOOD_DARK, 0.85), 0.01))


def barrel(objs, x, z):
    wood = mat("barrel", (0.52, 0.34, 0.2), 0.8)
    prof = smooth_profile([(0.0, 0.0), (0.27, 0.0), (0.31, 0.2), (0.33, 0.42), (0.31, 0.64), (0.27, 0.84), (0.0, 0.84)], 2)
    objs.append(lathe(prof, wood, 14, center=(x, 0, z), smooth=False))
    for y in (0.12, 0.42, 0.72):
        r = 0.31 + 0.02 * (1 - abs(y - 0.42) / 0.42) + 0.012
        objs.append(torus((x, y, z), r, 0.018, mat("iron", IRON, 0.5, 0.5), 14, 4, smooth=False))
    objs.append(lathe([(0, 0.0), (0.26, 0.0), (0.26, 0.01), (0, 0.01)], mat("water", (0.2, 0.35, 0.42), 0.1), 14,
                      center=(x, 0.76, z)))
    # Downpipe from the gutter.
    tin = mat("tin", (0.42, 0.45, 0.48), 0.45, 0.6)
    objs.append(cyl((x + 0.08, 0.88, z - 0.2), (x + 0.08, 2.92, z - 0.2), 0.04, 0.04, tin, 8))
    objs.append(cyl((x + 0.08, 2.92, z - 0.2), (x + 0.08, 2.98, z - 0.14), 0.04, 0.04, tin, 8))
    # Gutter along the south eave.
    objs.append(cyl((8.45, 3.0, 15.62), (17.55, 3.0, 15.62), 0.06, 0.06, tin, 8))


def lantern(objs, x, y, z):
    iron = mat("iron", IRON, 0.5, 0.5)
    glow = mat("glow", (1.0, 0.82, 0.45), 0.4, 0.0, emit=(1.0, 0.72, 0.3))
    objs.append(box((x + 0.05, y + 0.3, z), (0.1, 0.04, 0.04), iron, None, 0.0))   # bracket
    objs.append(box((x - 0.06, y + 0.17, z), (0.02, 0.22, 0.02), iron, None, 0.0))
    objs.append(box((x - 0.06, y - 0.05, z), (0.16, 0.24, 0.16), glow, None, 0.0))
    for sx in (-1, 1):
        for sz in (-1, 1):
            objs.append(box((x - 0.06 + sx * 0.085, y - 0.05, z + sz * 0.085), (0.025, 0.26, 0.025), iron, None, 0.0))
    objs.append(lathe([(0.0, 0.0), (0.13, 0.0), (0.0, 0.1)], iron, 4, center=(x - 0.06, y + 0.08, z), smooth=False,
                      phase=math.pi / 4))
    objs.append(box((x - 0.06, y - 0.18, z), (0.18, 0.03, 0.18), iron, None, 0.005))


def crate(objs, c, s, rot):
    wood = mat("crate", (0.72, 0.55, 0.34), 0.85)
    dark = mat("wood_dark", WOOD_DARK, 0.85)
    b = rot_y(rot)
    objs.append(box(c, (s, s, s), wood, b, 0.02))
    for ax in range(3):
        for sgn in (-1, 1):
            for e in (-1, 1):
                # Edge battens on each face.
                if ax == 0:
                    p, sz = Vector((sgn * s * 0.5, 0, e * s * 0.44)), (0.02, s, 0.08)
                elif ax == 1:
                    p, sz = Vector((e * s * 0.44, 0, sgn * s * 0.5)), (0.08, s, 0.02)
                else:
                    p, sz = Vector((e * s * 0.44, sgn * s * 0.5, 0)), (0.08, 0.02, s)
                objs.append(box(Vector(c) + b @ p, sz, dark, b, 0.005))


def chopping_block(objs, x, z):
    log(objs, (x, 0.0, z), (x, 0.45, z), 0.22)
    # The axe, stuck in the top.
    objs.append(cyl((x + 0.02, 0.4, z), (x + 0.32, 0.85, z + 0.05), 0.022, 0.02, mat("handle", (0.78, 0.6, 0.38), 0.7), 6))
    objs.append(box((x - 0.01, 0.42, z), (0.14, 0.09, 0.025), mat("steel", (0.65, 0.67, 0.7), 0.3, 0.9), rot_z(0.98), 0.005))
    for k in range(3):
        a = k * 2.1 + 0.4
        objs.append(box((x + math.cos(a) * 0.45, 0.06, z + math.sin(a) * 0.45), (0.2, 0.12, 0.07),
                        mat("log_end", LOG_END, 0.9), rot_y(a) @ rot_z(0.3 * k), 0.01))


def stovepipe(objs, x, z):
    iron = mat("iron", IRON, 0.5, 0.5)
    # The roof: ridge at y 5.2 over z 11.5, slope 2.0 / 3.7.
    zc, half = 11.5, 3.7
    y_roof = 3.2 + 2.0 * (1 - abs(z - zc) / half) + 0.2
    objs.append(cyl((x, y_roof - 0.3, z), (x, y_roof + 0.8, z), 0.09, 0.09, iron, 10))
    objs.append(lathe([(0.0, 0.0), (0.2, 0.0), (0.0, 0.14)], iron, 10, center=(x, y_roof + 0.9, z), smooth=False))
    objs.append(box((x, y_roof - 0.02, z), (0.32, 0.06, 0.32), iron, rot_x(math.atan2(2.0, half)), 0.01))


def main():
    reset()
    rng = random.Random(7)
    objs = []
    woodpile(objs, 12.5, 14.9, 15.55, rng)
    barrel(objs, 9.25, 15.75)
    lantern(objs, 8.7, 2.05, 12.6)
    crate(objs, (8.15, 0.3, 9.55), 0.6, 0.15)
    crate(objs, (8.2, 0.85, 9.6), 0.5, -0.2)
    crate(objs, (8.25, 0.25, 8.85), 0.5, 0.4)
    chopping_block(objs, 11.6, 16.4)
    stovepipe(objs, 15.6, 9.6)
    ob = join(objs, "ShedProps")
    export("shed_props", [ob])


if __name__ == "__main__":
    main()
