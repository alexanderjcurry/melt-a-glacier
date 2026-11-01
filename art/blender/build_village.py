"""The frozen village: five chalets, the church with its onion-dome tower, and
the well. Writes models/house_0..4.glb, models/church.glb, models/well.glb.

Each house stands on y = 0 with its footprint centred on the origin, door
facing +Z (the valley mouth), and stays inside the footprint box world.gd
carves out of the ice (w x 4.3 x d), give or take the roof overhang.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403
from kit import _g2b  # noqa: E402

# Must match HOUSES in scripts/world.gd: width, depth, walls, roof, shutters, wooden upper floor.
HOUSES = [
    (3, 3, (0.95, 0.89, 0.76), (0.66, 0.25, 0.2), (0.24, 0.42, 0.3), True),
    (3, 3, (0.87, 0.9, 0.93), (0.27, 0.36, 0.55), (0.62, 0.22, 0.2), False),
    (4, 3, (0.96, 0.86, 0.62), (0.32, 0.47, 0.3), (0.55, 0.3, 0.18), True),
    (3, 4, (0.97, 0.8, 0.6), (0.5, 0.3, 0.22), (0.25, 0.4, 0.55), False),
    (3, 3, (0.91, 0.78, 0.76), (0.4, 0.28, 0.42), (0.3, 0.45, 0.32), True),
]
WALL = 3.0
ROOF = 1.3
PLINTH = 0.5

STONE = (0.6, 0.59, 0.57)
STONE_DARK = (0.45, 0.44, 0.43)
WOOD = (0.5, 0.33, 0.2)
WOOD_DARK = (0.36, 0.23, 0.14)
TRIM = (0.95, 0.93, 0.87)
GLASS = (0.2, 0.27, 0.36)
FLOWERS = [(0.86, 0.2, 0.24), (0.98, 0.55, 0.65), (0.98, 0.82, 0.3)]
LEAF = (0.3, 0.5, 0.25)


def window(objs, cx, y0, y1, w, face_z, normal, shutter_col=None, flowers=False, tag=""):
    """A window on a wall. `normal` is +1/-1 along z (front/back) or 'x+'/'x-' for side walls."""
    # Work in a local frame: u along the wall, n out of it.
    if normal in (1, -1):
        u = Vector((1, 0, 0))
        n = Vector((0, 0, normal))
    else:
        s = 1 if normal == "x+" else -1
        u = Vector((0, 0, -s))
        n = Vector((s, 0, 0))
    base = u * cx + n * face_z
    ym = (y0 + y1) * 0.5
    h = y1 - y0
    basis = Matrix((u, Vector((0, 1, 0)), n)).transposed()
    t = mat("trim", TRIM, 0.7)
    objs.append(box(base + Vector((0, ym, 0)) - n * 0.02, (w, h, 0.06), mat("glass", GLASS, 0.15, 0.1), basis, 0.0))
    fr = 0.07
    objs.append(box(base + Vector((0, y1 + fr * 0.5, 0)) + n * 0.03, (w + 2 * fr, fr, 0.08), t, basis, 0.015))
    objs.append(box(base + Vector((0, y0 - fr * 0.5, 0)) + n * 0.05, (w + 2 * fr + 0.06, fr, 0.14), t, basis, 0.015))
    for sd in (-1, 1):
        objs.append(box(base + u * sd * (w + fr) * 0.5 + Vector((0, ym, 0)) + n * 0.03, (fr, h, 0.08), t, basis, 0.015))
    objs.append(box(base + Vector((0, ym, 0)) + n * 0.02, (0.035, h, 0.04), t, basis, 0.0))
    objs.append(box(base + Vector((0, ym + h * 0.1, 0)) + n * 0.02, (w, 0.035, 0.04), t, basis, 0.0))
    if shutter_col is not None:
        sm = mat("shutter" + tag, shutter_col, 0.8)
        for sd in (-1, 1):
            sw = w * 0.5 + 0.02
            c = base + u * sd * (w * 0.5 + fr + sw * 0.5 + 0.01) + Vector((0, ym, 0)) + n * 0.035
            objs.append(box(c, (sw, h + 0.06, 0.04), sm, basis, 0.012))
            for k in (-1, 0, 1):   # louvres
                objs.append(box(c + Vector((0, k * h * 0.28, 0)) + n * 0.025, (sw * 0.8, 0.03, 0.02),
                                mat("shutter_dark" + tag, tuple(x * 0.75 for x in shutter_col), 0.8), basis, 0.0))
    if flowers:
        bx = base + Vector((0, y0 - 0.2, 0)) + n * 0.14
        objs.append(box(bx, (w + 0.1, 0.18, 0.2), mat("wood_dark", WOOD_DARK), basis, 0.02))
        k = 0
        for i in range(5):
            off = (i - 2) / 2.0 * (w * 0.42)
            objs.append(sphere(bx + u * off + Vector((0, 0.12, 0)), (0.09, 0.07, 0.08), mat("leaf", LEAF, 0.9),
                               8, 5))
            fc = FLOWERS[(i + len(tag)) % len(FLOWERS)]
            objs.append(sphere(bx + u * (off + 0.03) + Vector((0, 0.18, 0)) + n * 0.03, (0.045, 0.04, 0.045),
                               mat("flower%d" % ((i + len(tag)) % 3), fc, 0.7), 6, 4))
            k += 1


def roof(objs, w, d, peak, roof_col, overhang=0.3, thick=0.12, courses=5, tag=""):
    """A gable roof, ridge along z, with shingle courses, a ridge cap and bargeboards."""
    rise = peak - WALL
    half = w * 0.5
    a = math.atan2(rise, half)
    run = half + overhang
    length = run / math.cos(a)
    rm = mat("roof" + tag, roof_col, 0.75)
    rd = mat("roof_dark" + tag, tuple(c * 0.72 for c in roof_col), 0.75)
    depth = d + 2 * overhang
    for s in (-1, 1):
        basis = rot_z(-s * a)   # tilt down toward +x for s=+1
        down = basis @ Vector((s, 0, 0))   # along the slope, away from the ridge
        up_n = basis @ Vector((0, 1, 0))
        top = Vector((0, peak, 0))
        mid = top + down * (length * 0.5) + up_n * (thick * 0.5)
        objs.append(box(mid, (length + 0.05, thick, depth), rd, basis, 0.02))
        # Shingle courses: each a little proud of the last, so the roof steps.
        cl = length / courses
        for i in range(courses):
            c = top + down * (cl * (i + 0.5) + 0.02) + up_n * (thick + 0.03)
            bb = basis @ rot_z(s * 0.06)   # tip each course's lower edge out
            objs.append(box(c, (cl + 0.06, 0.06, depth + 0.02), rm, bb, 0.02))
        # Bargeboards on both gable ends.
        for z in (-depth * 0.5 - 0.02, depth * 0.5 + 0.02):
            bc = top + down * (length * 0.5) + up_n * 0.02 + Vector((0, 0, z))
            objs.append(box(bc, (length + 0.05, 0.2, 0.05), mat("wood_dark", WOOD_DARK), basis, 0.012))
    objs.append(box((0, peak + thick + 0.06, 0), (0.18, 0.18, depth + 0.06), rd, rot_z(math.pi / 4), 0.02))
    return a


def gable(objs, w, d, peak, material, z_off=0.0):
    hw = w * 0.5
    objs.append(extrude([(-hw, WALL), (hw, WALL), (0, peak)], -d * 0.5 + z_off, d * 0.5 - z_off, material, 0.0))


def chimney(objs, x, z, base, top):
    objs.append(box((x, (base + top) * 0.5, z), (0.42, top - base, 0.42), mat("stone", STONE, 0.95), None, 0.03))
    objs.append(box((x, top + 0.04, z), (0.54, 0.08, 0.54), mat("stone_dark", STONE_DARK, 0.95), None, 0.02))
    objs.append(box((x, top + 0.16, z), (0.2, 0.16, 0.2), mat("stone_dark", STONE_DARK, 0.95), None, 0.01))


def house(i):
    reset()
    w, d, wall_col, roof_col, shutter_col, wooden = HOUSES[i]
    objs = []
    hw, hd = w * 0.5, d * 0.5
    stone = mat("stone", STONE, 0.95)
    plaster = mat("plaster%d" % i, wall_col, 0.95)
    wood = mat("wood", WOOD, 0.85)
    wood_dark = mat("wood_dark", WOOD_DARK, 0.85)
    # Stone footing, plastered walls, and on some houses a wooden upper floor.
    objs.append(boxlh((-hw - 0.05, 0, -hd - 0.05), (hw + 0.05, PLINTH, hd + 0.05), stone, 0.04))
    objs.append(box((0, PLINTH + 0.02, 0), (w + 0.14, 0.05, d + 0.14), mat("stone_dark", STONE_DARK, 0.95), None, 0.02))
    upper = 1.95 if wooden else WALL
    objs.append(boxlh((-hw, PLINTH, -hd), (hw, upper, hd), plaster, 0.03))
    peak = WALL + ROOF - 0.18
    if wooden:
        objs.append(boxlh((-hw - 0.03, upper, -hd - 0.03), (hw + 0.03, WALL, hd + 0.03), wood, 0.02))
        y = upper + 0.2
        while y < WALL - 0.05:   # log seams
            for zz in (hd + 0.04, -hd - 0.04):
                objs.append(box((0, y, zz), (w + 0.06, 0.03, 0.02), wood_dark, None, 0.0))
            for xx in (hw + 0.04, -hw - 0.04):
                objs.append(box((xx, y, 0), (0.02, 0.03, d + 0.06), wood_dark, None, 0.0))
            y += 0.22
        # A little balcony rail across the front, under the gable.
        rail_z = hd + 0.2
        objs.append(box((0, upper - 0.02, rail_z - 0.08), (w + 0.1, 0.06, 0.3), wood_dark, None, 0.015))
        objs.append(box((0, upper + 0.62, rail_z), (w + 0.1, 0.06, 0.07), wood_dark, None, 0.015))
        n = int(w / 0.18)
        for k in range(n + 1):
            x = -hw + w * k / n
            objs.append(box((x, upper + 0.31, rail_z), (0.05, 0.6, 0.04), wood, None, 0.008))
    else:
        # Wooden corner boards on the plaster houses.
        for sx in (-1, 1):
            for sz in (-1, 1):
                objs.append(box((sx * (hw + 0.005), (PLINTH + WALL) * 0.5, sz * (hd + 0.005)),
                                (0.14, WALL - PLINTH, 0.14), wood_dark, None, 0.02))
        objs.append(boxlh((-hw - 0.04, WALL - 0.14, -hd - 0.04), (hw + 0.04, WALL, hd + 0.04), wood_dark, 0.02))
    # The gable: vertical boards.
    gable(objs, w, d, peak, wood)
    k = -hw + 0.2
    while k < hw - 0.1:
        hgt = (peak - WALL) * (1 - abs(k) / hw)
        if hgt > 0.1:
            for zz in (hd + 0.01, -hd - 0.01):
                objs.append(box((k, WALL + hgt * 0.5, zz), (0.025, hgt, 0.02), wood_dark, None, 0.0))
        k += 0.25
    roof(objs, w, d, peak, roof_col, tag=str(i))
    chimney(objs, hw * 0.45, -hd * 0.35, WALL + 0.5, peak + 0.55)
    # Front: door with a canopy and a step, windows either side.
    fz = hd
    objs.append(box((0, 0.95, fz + 0.01), (0.86, 1.86, 0.05), mat("trim", TRIM, 0.7), None, 0.015))
    objs.append(box((0, 0.93, fz + 0.04), (0.72, 1.78, 0.06), wood, None, 0.015))
    for kx in (-0.24, 0.0, 0.24):
        objs.append(box((kx, 0.93, fz + 0.075), (0.015, 1.7, 0.01), wood_dark, None, 0.0))
    objs.append(box((0, 1.15, fz + 0.075), (0.62, 0.05, 0.02), wood_dark, None, 0.0))
    objs.append(sphere((0.24, 0.95, fz + 0.1), (0.035, 0.035, 0.035), mat("brass", (0.86, 0.68, 0.3), 0.35, 0.8), 6, 4))
    objs.append(box((0, 0.06, fz + 0.24), (1.1, 0.12, 0.42), stone, None, 0.03))
    objs.append(box((0, 2.0, fz + 0.2), (1.1, 0.07, 0.42), mat("roof%d" % i, roof_col, 0.75), rot_x(-0.25), 0.015))
    for sx in (-1, 1):
        objs.append(box((sx * 0.48, 1.88, fz + 0.24), (0.05, 0.2, 0.3), wood_dark, rot_x(0.6), 0.0))
    win_y0, win_y1 = 1.05, 1.75
    if w >= 3:
        for sx in (-1, 1):
            window(objs, sx * (hw - 0.5), win_y0, win_y1, 0.48, fz + 0.01, 1, None, flowers=True, tag="%d%d" % (i, sx))
    # Upper front window in the gable, sides and back.
    window(objs, 0, WALL + 0.15, WALL + 0.65, 0.42, fz + 0.01, 1, shutter_col, tag=str(i))
    for side in ("x+", "x-"):
        window(objs, 0, win_y0 + 0.05, win_y1 + 0.05, 0.55, hw + 0.01, side, shutter_col, tag=str(i))
        if not wooden:
            window(objs, 0, 2.15, 2.65, 0.45, hw + 0.01, side, shutter_col, tag=str(i))
    window(objs, 0, win_y0, win_y1, 0.55, hd + 0.01, -1, shutter_col, tag=str(i))
    ob = join(objs, "House%d" % i)
    export("house_%d" % i, [ob])


# ---------------------------------------------------------------------------------
# The church: nave (4 x 5, walls 3.5, roof 1.6) and the tower in front (2 x 2,
# 6 m to the belfry top, then the onion dome to 9.8 m). Origin = the nave's
# footprint corner at (CHURCH.x, CHURCH.z) in world.gd, i.e. world (-1, 0, -17).
# ---------------------------------------------------------------------------------
def arched_window(objs, center_u, y0, y1, w, face, normal_axis, sign, glass_m, trim_m):
    """A tall round-topped window. normal_axis 'x' or 'z'."""
    h = y1 - y0 - w * 0.5
    if normal_axis == "x":
        u = Vector((0, 0, 1))
        n = Vector((sign, 0, 0))
    else:
        u = Vector((1, 0, 0))
        n = Vector((0, 0, sign))
    basis = Matrix((u, Vector((0, 1, 0)), n)).transposed()
    base = u * center_u + n * face
    objs.append(box(base + Vector((0, y0 + h * 0.5, 0)) - n * 0.01, (w, h, 0.06), glass_m, basis, 0.0))
    arch = []
    for k in range(9):
        t = math.pi * k / 8
        arch.append((math.cos(t) * w * 0.5, y0 + h + math.sin(t) * w * 0.5))
    pts = [(-w * 0.5, y0 + h)] + arch[::-1][1:-1] + [(w * 0.5, y0 + h)]
    ob = extrude([(p[0], p[1]) for p in arch], -0.03, 0.03, glass_m, 0.0)
    ob.data.transform(_g2b(basis) if False else Matrix.Identity(4))
    # Place the arch: build in the u/y plane at the face.
    for v in ob.data.vertices:
        g = Vector((v.co.x, v.co.z, -v.co.y))   # back to Godot
        p = base + u * g.x + Vector((0, g.y, 0)) + n * (g.z - 0.01)
        v.co = to_b(p)
    objs.append(ob)
    # Trim: sill and a frame round the arch.
    objs.append(box(base + Vector((0, y0 - 0.04, 0)) + n * 0.05, (w + 0.2, 0.08, 0.12), trim_m, basis, 0.015))
    for sd in (-1, 1):
        objs.append(box(base + u * sd * (w * 0.5 + 0.04) + Vector((0, y0 + h * 0.5, 0)) + n * 0.02,
                        (0.08, h, 0.06), trim_m, basis, 0.01))
    for k in range(8):
        t0, t1 = math.pi * k / 8, math.pi * (k + 1) / 8
        tm = (t0 + t1) * 0.5
        r = w * 0.5 + 0.04
        c = base + u * math.cos(tm) * r + Vector((0, y0 + h + math.sin(tm) * r, 0)) + n * 0.02
        seg = 2 * r * math.sin((t1 - t0) * 0.5) + 0.02
        objs.append(box(c, (seg, 0.08, 0.06), trim_m, basis @ rot_z(tm - math.pi / 2), 0.0))


def church():
    reset()
    objs = []
    white = mat("church_white", (0.96, 0.95, 0.91), 0.95)
    stone = mat("stone", STONE, 0.95)
    stone_dark = mat("stone_dark", STONE_DARK, 0.95)
    quoin = mat("quoin", (0.82, 0.79, 0.72), 0.95)
    slate = mat("slate", (0.33, 0.36, 0.45), 0.7)
    slate_dark = mat("slate_dark", (0.24, 0.26, 0.33), 0.7)
    copper = mat("copper", (0.36, 0.62, 0.55), 0.55, 0.2)
    copper_dark = mat("copper_dark", (0.26, 0.48, 0.43), 0.55, 0.2)
    gold = mat("gold", (0.98, 0.8, 0.32), 0.3, 0.9)
    glass = mat("church_glass", (0.25, 0.3, 0.45), 0.15, 0.1)
    wood = mat("wood", WOOD, 0.85)
    wood_dark = mat("wood_dark", WOOD_DARK, 0.85)
    # --- Nave: x 0..4, z 0..5 (local), walls 3.5, ridge along z.
    nw, nd, nh = 4.0, 5.0, 3.5
    cx, cz = 2.0, 2.5
    objs.append(boxlh((-0.06, 0, -0.06), (nw + 0.06, 0.45, nd + 0.06), stone, 0.04))
    objs.append(boxlh((0, 0.45, 0), (nw, nh, nd), white, 0.03))
    objs.append(boxlh((-0.05, nh - 0.16, -0.05), (nw + 0.05, nh, nd + 0.05), quoin, 0.02))
    # Gable + roof, built round the nave centre.
    sub = []
    global WALL
    old = WALL
    WALL = nh
    gable(sub, nw, nd, nh + 1.45, white)
    roof(sub, nw, nd, nh + 1.45, (0.33, 0.36, 0.45), overhang=0.25, courses=6, tag="church")
    WALL = old
    for ob in sub:
        ob.data.transform(Matrix.Translation(to_b((cx, 0, cz))))
        objs.append(ob)
    for side, x in (("x", 0.0), ("x", nw)):
        sgn = -1 if x == 0.0 else 1
        for zc in (1.25, 3.75):
            arched_window(objs, zc, 1.3, 2.9, 0.62, x + sgn * 0.01, "x", sgn, glass, quoin)
    # Rose window at the back.
    objs.append(cyl((cx, 4.2, -0.02), (cx, 4.2, -0.06), 0.42, 0.42, quoin, 16, smooth=False))
    objs.append(cyl((cx, 4.2, -0.05), (cx, 4.2, -0.09), 0.32, 0.32, glass, 16, smooth=False))
    # Corner quoins on the nave.
    for qx in (0.0, nw):
        for qz in (0.0, nd):
            y = 0.5
            k = 0
            while y < nh - 0.3:
                big = k % 2 == 0
                sx = 0.34 if big else 0.2
                objs.append(box((qx, y + 0.15, qz), (sx, 0.28, 0.2 if big else 0.34), quoin, None, 0.02))
                y += 0.32
                k += 1
    # --- Tower: x 1..3, z 5..7 (local), 6 m up.
    tx0, tz0, tw, th = 1.0, 5.0, 2.0, 6.0
    tcx, tcz = tx0 + tw * 0.5, tz0 + tw * 0.5
    objs.append(boxlh((tx0 - 0.08, 0, tz0 - 0.08), (tx0 + tw + 0.08, 0.5, tz0 + tw + 0.08), stone, 0.04))
    objs.append(boxlh((tx0, 0.5, tz0), (tx0 + tw, th - 1.9, tz0 + tw), white, 0.03))
    # Cornices.
    objs.append(boxlh((tx0 - 0.1, th - 1.95, tz0 - 0.1), (tx0 + tw + 0.1, th - 1.75, tz0 + tw + 0.1), quoin, 0.03))
    objs.append(boxlh((tx0 - 0.12, th - 0.2, tz0 - 0.12), (tx0 + tw + 0.12, th, tz0 + tw + 0.12), quoin, 0.03))
    # Belfry: four corner piers with arched openings between, and a bell inside.
    for sx in (0, 1):
        for sz in (0, 1):
            x = tx0 + sx * (tw - 0.4)
            z = tz0 + sz * (tw - 0.4)
            objs.append(boxlh((x, th - 1.75, z), (x + 0.4, th - 0.2, z + 0.4), white, 0.03))
    for axis in ("x", "z"):
        for s in (-1, 1):
            # Arch tops between the piers.
            if axis == "z":
                c = Vector((tcx, th - 0.45, tcz + s * (tw * 0.5 - 0.15)))
                objs.append(box(c, (tw - 0.8, 0.5, 0.3), white, None, 0.02))
            else:
                c = Vector((tcx + s * (tw * 0.5 - 0.15), th - 0.45, tcz))
                objs.append(box(c, (0.3, 0.5, tw - 0.8), white, None, 0.02))
            objs.append(box(c + Vector((0, -0.25, 0)), (0.95 if axis == "z" else 0.32, 0.06, 0.32 if axis == "z" else 0.95),
                            quoin, None, 0.0))
            # Railing in each opening.
            rc = c + Vector((0, -1.1, 0))
            objs.append(box(rc, (tw - 0.8, 0.08, 0.1) if axis == "z" else (0.1, 0.08, tw - 0.8), wood_dark, None, 0.01))
    objs.append(lathe([(0, 0.1), (0.36, 0.0), (0.33, 0.12), (0.24, 0.4), (0.22, 0.55), (0.1, 0.62), (0, 0.63)],
                      gold, 14, center=(tcx, th - 1.25, tcz)))
    objs.append(boxlh((tcx - 0.6, th - 0.62, tcz - 0.05), (tcx + 0.6, th - 0.54, tcz + 0.05), wood_dark, 0.0))
    # Tower quoins.
    for qx in (tx0, tx0 + tw):
        for qz in (tz0, tz0 + tw):
            y = 0.5
            k = 0
            while y < th - 2.1:
                big = k % 2 == 0
                objs.append(box((qx, y + 0.15, qz), (0.3 if big else 0.18, 0.28, 0.18 if big else 0.3), quoin, None, 0.02))
                y += 0.32
                k += 1
    # Clock on the front, and a window above the door.
    fz = tz0 + tw
    objs.append(cyl((tcx, th - 2.75, fz - 0.02), (tcx, th - 2.75, fz + 0.06), 0.48, 0.48, quoin, 20, smooth=False))
    objs.append(cyl((tcx, th - 2.75, fz + 0.05), (tcx, th - 2.75, fz + 0.09), 0.4, 0.4, mat("clock", (0.98, 0.96, 0.88), 0.6), 20, smooth=False))
    for k in range(12):
        t = math.tau * k / 12
        objs.append(box((tcx + math.cos(t) * 0.33, th - 2.75 + math.sin(t) * 0.33, fz + 0.1), (0.04, 0.04, 0.02),
                        mat("ink", (0.12, 0.12, 0.15), 0.6), rot_z(t), 0.0))
    objs.append(box((tcx, th - 2.75 + 0.12, fz + 0.11), (0.04, 0.26, 0.02), gold, None, 0.0))
    objs.append(box((tcx + 0.09, th - 2.75 - 0.04, fz + 0.115), (0.2, 0.035, 0.02), gold, rot_z(-0.5), 0.0))
    arched_window(objs, tcx, 2.4, 3.3, 0.36, fz + 0.01, "z", 1, glass, quoin)
    # Door: arched wooden door with a stone surround and steps.
    objs.append(box((tcx, 0.9, fz + 0.02), (1.1, 1.8, 0.06), quoin, None, 0.02))
    objs.append(cyl((tcx, 1.8, fz - 0.01), (tcx, 1.8, fz + 0.05), 0.55, 0.55, quoin, 16, smooth=False))
    objs.append(box((tcx, 0.85, fz + 0.05), (0.86, 1.7, 0.05), wood, None, 0.015))
    objs.append(cyl((tcx, 1.7, fz + 0.025), (tcx, 1.7, fz + 0.075), 0.43, 0.43, wood, 16, smooth=False))
    objs.append(box((tcx, 0.9, fz + 0.085), (0.02, 1.8, 0.015), wood_dark, None, 0.0))
    for sy in (0.5, 1.3):
        objs.append(box((tcx, sy, fz + 0.09), (0.8, 0.05, 0.015), mat("iron", (0.18, 0.18, 0.2), 0.5, 0.6), None, 0.0))
    objs.append(box((tcx, 0.07, fz + 0.3), (1.4, 0.14, 0.5), stone, None, 0.03))
    objs.append(box((tcx, 0.04, fz + 0.62), (1.6, 0.08, 0.3), stone_dark, None, 0.02))
    # --- Onion dome: 6.0 -> 9.8 m.
    base_y = th
    objs.append(lathe([(0, 0), (1.05, 0), (1.05, 0.12), (0.82, 0.25), (0.78, 0.25)], slate_dark, 8, center=(tcx, base_y, tcz),
                      smooth=False, phase=math.pi / 8))
    objs.append(lathe([(0.62, 0.0), (0.62, 0.85), (0.66, 0.9), (0.0, 0.92)], white, 8, center=(tcx, base_y + 0.2, tcz),
                      smooth=False, phase=math.pi / 8))
    onion = [(0.0, 0.0), (0.66, 0.0), (0.82, 0.18), (0.88, 0.42), (0.8, 0.7), (0.58, 0.98), (0.32, 1.22), (0.14, 1.45),
             (0.07, 1.65), (0.06, 1.75), (0.0, 1.76)]
    # Taller than it is wide, so it stands well clear of the ice as a landmark.
    onion = [(r * 1.05, y * 1.3) for r, y in onion]
    dome_y = base_y + 1.1
    objs.append(lathe(onion, copper, 16, center=(tcx, dome_y, tcz)))
    # Ribs on the onion.
    for k in range(8):
        t = math.tau * k / 8
        prof = onion[1:-2]
        for a, b in zip(prof, prof[1:]):
            pa = Vector((tcx + math.cos(t) * (a[0] + 0.01), dome_y + a[1], tcz + math.sin(t) * (a[0] + 0.01)))
            pb = Vector((tcx + math.cos(t) * (b[0] + 0.01), dome_y + b[1], tcz + math.sin(t) * (b[0] + 0.01)))
            objs.append(cyl(pa, pb, 0.025, 0.025, copper_dark, 4, smooth=False))
    top = dome_y + onion[-1][1]
    objs.append(cyl((tcx, top - 0.05, tcz), (tcx, top + 0.6, tcz), 0.035, 0.025, gold, 6))
    objs.append(sphere((tcx, top + 0.15, tcz), (0.11, 0.11, 0.11), gold, 10, 6))
    objs.append(box((tcx, top + 0.55, tcz), (0.05, 0.5, 0.05), gold, None, 0.0))
    objs.append(box((tcx, top + 0.62, tcz), (0.3, 0.05, 0.05), gold, None, 0.0))
    ob = join(objs, "Church")
    export("church", [ob])


def well():
    reset()
    objs = []
    stone = mat("stone", STONE, 0.95)
    stone_dark = mat("stone_dark", STONE_DARK, 0.95)
    wood = mat("wood", WOOD, 0.85)
    wood_dark = mat("wood_dark", WOOD_DARK, 0.85)
    # Ring of stones.
    n = 10
    for row in range(3):
        for k in range(n):
            t = math.tau * (k + 0.5 * (row % 2)) / n
            c = Vector((math.cos(t) * 0.6, 0.15 + row * 0.25, math.sin(t) * 0.6))
            objs.append(box(c, (0.24, 0.24, 0.38), stone if (k + row) % 3 else stone_dark, rot_y(-t), 0.05))
    objs.append(lathe([(0.0, 0.0), (0.5, 0.0), (0.5, 0.62), (0.0, 0.62)], mat("water_dark", (0.12, 0.2, 0.26), 0.2), 14))
    objs.append(lathe([(0.48, 0.66), (0.78, 0.66), (0.78, 0.76), (0.48, 0.76)], stone, 14, smooth=False))
    for s in (-1, 1):
        objs.append(box((s * 0.68, 1.35, 0), (0.12, 1.4, 0.12), wood, None, 0.02))
    objs.append(cyl((-0.75, 1.65, 0), (0.75, 1.65, 0), 0.06, 0.06, wood_dark, 8))
    objs.append(cyl((0, 1.6, 0), (0, 1.0, 0), 0.01, 0.01, mat("rope", (0.8, 0.7, 0.5), 0.9), 4))
    objs.append(lathe([(0, 0), (0.1, 0), (0.12, 0.18), (0.11, 0.18), (0.09, 0.02), (0, 0.02)], wood, 10, center=(0, 0.82, 0),
                      smooth=False))
    # A little shingled roof.
    sub = []
    global WALL
    old = WALL
    WALL = 2.0
    roof(sub, 1.4, 0.9, 2.4, (0.55, 0.3, 0.2), overhang=0.15, thick=0.06, courses=3, tag="well")
    WALL = old
    objs.extend(sub)
    objs.append(cyl((0.82, 1.65, 0), (0.82, 1.65, 0.0), 0.0, 0.0, wood, 4) if False else box((0.82, 1.65, 0.12), (0.04, 0.04, 0.3), wood_dark, None, 0.0))
    ob = join(objs, "Well")
    export("well", [ob])


if __name__ == "__main__":
    for i in range(len(HOUSES)):
        house(i)
    church()
    well()
