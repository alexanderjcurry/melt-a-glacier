"""The goblin pirate fleet frozen in the lake. Writes models/pirates.glb with:

    Galleon         the flagship: three masts, castles fore and aft, cannons
    Sloop           a smaller one-master
    GoblinCaptain   tricorn hat, red coat, hook
    GoblinDeckhand  striped shirt, red bandana, a mop
    GoblinLookout   purple bandana, eyepatch, spyglass

Ships: the bow points to -Z, y = 0 is the waterline (the lake's surface) and the
origin is the middle of the hull. Goblins stand on y = 0 and face -Z.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403

INK = (0.12, 0.08, 0.07)
WHITE = (0.97, 0.96, 0.93)


def m(name, rgb, rough=0.8, metal=0.0, emit=None):
    return mat(name, rgb, rough, metal, emit)


# ------------------------------------------------------------------------------------------
# Shapes the ships need
# ------------------------------------------------------------------------------------------
def loft(stations, material, name="hull", cols=12):
    """A closed hull from cross-sections. stations = [(z, half_width, keel_y, rail_y)], bow
    first. Each section is a U from rail to keel to rail."""
    bm = bmesh.new()
    rings = []
    for z, w, keel, rail in stations:
        ring = []
        for k in range(cols + 1):
            s = -1.0 + 2.0 * k / cols
            a = abs(s)
            x = w * s
            y = rail - (rail - keel) * (1.0 - a ** 2.6) ** 0.85
            ring.append(bm.verts.new(to_b((x, y, z))))
        rings.append(ring)
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(cols):
            bm.faces.new([a[k], a[k + 1], b[k + 1], b[k]])
    for ring in (rings[0], rings[-1]):   # bow and transom caps
        bm.faces.new(ring)
    # The deck: a lid across the top.
    top = [r[0] for r in rings] + [r[-1] for r in reversed(rings)]
    bm.faces.new(top)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit_obj(name, bm, material)


def kit_obj(name, bm, material, smooth=False):
    from kit import _obj
    return _obj(name, bm, material, 0.0, smooth=smooth)


def prism_y(poly, y0, y1, material, name="prism"):
    """A polygon in the xz plane [(x, z)], extruded from y0 up to y1."""
    bm = bmesh.new()
    a = [bm.verts.new(to_b((x, y0, z))) for x, z in poly]
    b = [bm.verts.new(to_b((x, y1, z))) for x, z in poly]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(poly)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([a[i], a[j], b[j], b[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit_obj(name, bm, material)


def wall(poly, y0, y1, thick, material, closed=True, name="wall"):
    """A thin wall standing on a path in the xz plane (the bulwarks round a deck)."""
    o = []
    n = len(poly)
    for i in range(n if closed else n - 1):
        x0, z0 = poly[i]
        x1, z1 = poly[(i + 1) % n]
        dx, dz = x1 - x0, z1 - z0
        ln = math.hypot(dx, dz)
        if ln < 1e-4:
            continue
        ang = math.atan2(dx, dz)
        o.append(box(((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), (thick, y1 - y0, ln + thick), material,
                     rot_y(ang), 0.0, name=name))
    return o


def sail(cx, cy, cz, w, h, billow, material, patch=None, rng=None, tatter=True, name="sail"):
    """A square sail hanging from a yard at (cx, cy + h/2, cz), bellied toward -Z,
    with a ragged bottom edge. Two-sided."""
    bm = bmesh.new()
    nx, ny = 6, 5
    grid = []
    for j in range(ny + 1):
        row = []
        v = j / ny   # 0 = top
        for i in range(nx + 1):
            u = -1.0 + 2.0 * i / nx
            x = cx + u * w * 0.5 * (1.0 - 0.06 * v)
            y = cy + h * 0.5 - v * h
            if tatter and j == ny:
                y += (0.18 if i % 2 else -0.05) * h * 0.25
            z = cz - billow * (1.0 - u * u) * math.sin(math.pi * min(1.0, v * 0.9 + 0.1))
            row.append((x, y, z))
        grid.append(row)
    for side in (0, 1):
        vs = [[bm.verts.new(to_b((p[0], p[1], p[2] + (0.015 if side else -0.015)))) for p in row] for row in grid]
        for j in range(ny):
            for i in range(nx):
                q = [vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]]
                bm.faces.new(q if side else list(reversed(q)))
    ob = kit_obj(name, bm, material)
    o = [ob]
    if patch is not None and rng is not None:
        for _ in range(2):
            u = rng.uniform(-0.55, 0.55)
            v = rng.uniform(0.2, 0.75)
            z = cz - billow * (1.0 - u * u) * math.sin(math.pi * min(1.0, v * 0.9 + 0.1))
            for s in (-1, 1):
                o.append(box((cx + u * w * 0.5, cy + h * 0.5 - v * h, z + 0.03 * s), (w * 0.16, h * 0.16, 0.01),
                             patch, rot_z(rng.uniform(-0.3, 0.3)), 0.0, name="patch"))
    return o


def flag(x, y, z, w, h, material, skull=True):
    """A pirate flag flying off a masthead toward +X, rippled."""
    bm = bmesh.new()
    nx = 6
    for side in (0, 1):
        vs = []
        for i in range(nx + 1):
            u = i / nx
            dz = 0.12 * math.sin(u * math.pi * 2.0) * u + (0.02 if side else -0.02)
            vs.append((bm.verts.new(to_b((x + u * w, y, z + dz))), bm.verts.new(to_b((x + u * w, y - h, z + dz)))))
        for i in range(nx):
            q = [vs[i][0], vs[i + 1][0], vs[i + 1][1], vs[i][1]]
            bm.faces.new(q if side else list(reversed(q)))
    o = [kit_obj("flag", bm, material)]
    if skull:
        bone = m("bone", (0.93, 0.91, 0.82), 0.7)
        u = 0.45
        cxs = x + u * w
        dz = 0.12 * math.sin(u * math.pi * 2.0) * u
        for s in (-1, 1):
            zz = z + dz + 0.04 * s
            o.append(sphere((cxs, y - h * 0.4, zz), (h * 0.17, h * 0.17, 0.02), bone, 10, 4))
            for e in (-1, 1):   # goblin ears on the skull
                o.append(sphere((cxs + e * h * 0.24, y - h * 0.34, zz), (h * 0.12, h * 0.04, 0.015), bone, 6, 3,
                                basis=rot_z(0.5 * e)))
                o.append(box((cxs, y - h * 0.72, zz), (h * 0.55, h * 0.06, 0.015), bone, rot_z(0.6 * e), 0.0))
    return o


def cannon(x, y, z, side, iron):
    o = [cyl((x, y, z), (x + side * 0.9, y + 0.02, z), 0.13, 0.11, iron, 10)]
    o.append(cyl((x + side * 0.86, y + 0.02, z), (x + side * 0.92, y + 0.02, z), 0.14, 0.14, iron, 10))   # muzzle ring
    return o


# ------------------------------------------------------------------------------------------
# Ships
# ------------------------------------------------------------------------------------------
def hull_stations(length, beam, keel, deck, transom=0.72, rake=1.2):
    """Cross-sections bow (-Z) to stern (+Z) for a chunky, round-bottomed hull."""
    out = []
    n = 14
    for i in range(n + 1):
        t = i / n
        z = -length * 0.5 + t * length
        front = min(1.0, t / 0.42)
        w = beam * 0.5 * (math.sin(front * math.pi * 0.5) ** 0.75)
        if t > 0.7:
            w *= 1.0 - (1.0 - transom) * ((t - 0.7) / 0.3) ** 1.6
        w = max(w, 0.06)
        k = keel + rake * max(0.0, (0.3 - t) / 0.3) ** 1.8 * (deck - keel) * 0.7
        k += 0.4 * max(0.0, (t - 0.85) / 0.15) ** 2
        r = deck + 0.35 * max(0.0, (0.25 - t) / 0.25) ** 2   # the bow sweeps up a little
        out.append((z, w, k, r))
    return out


def outline(stations, inset=0.0, t0=0.0, t1=1.0):
    """The deck's edge as a polygon (x, z), going down the port side and back up starboard."""
    n = len(stations) - 1
    pick = [s for i, s in enumerate(stations) if t0 - 1e-6 <= i / n <= t1 + 1e-6]
    left = [(-(w - inset), z) for z, w, _, _ in pick]
    right = [((w - inset), z) for z, w, _, _ in reversed(pick)]
    return left + right


def ship(length, beam, deck, masts, castle_aft, castle_fore, guns, seed):
    rng = random.Random(seed)
    hull_wood = m("hull_wood", (0.48, 0.32, 0.2), 0.85)
    plank = m("deck_plank", (0.6, 0.45, 0.3), 0.85)
    trim = m("goblin_trim", (0.42, 0.55, 0.22), 0.7)      # mossy goblin green
    gold = m("trim_gold", (0.85, 0.65, 0.25), 0.4, 0.6)
    dark = m("hull_dark", (0.16, 0.11, 0.09), 0.9)
    iron = m("cannon_iron", (0.18, 0.18, 0.2), 0.5, 0.6)
    canvas = m("sail_canvas", (0.86, 0.81, 0.68), 0.9)
    patch = m("sail_patch", (0.55, 0.45, 0.32), 0.9)
    rope = m("rope", (0.5, 0.4, 0.28), 0.9)
    black = m("flag_black", (0.1, 0.09, 0.1), 0.9)
    glow = m("lantern_glow", (1.0, 0.8, 0.4), 0.4, emit=(1.0, 0.7, 0.3))
    keel = -1.3
    st = hull_stations(length, beam, keel, deck)
    o = [loft(st, hull_wood)]
    # A green band and a gold rub-rail along the hull.
    def rail_at(z):
        for a, b in zip(st, st[1:]):
            if a[0] <= z <= b[0]:
                f = (z - a[0]) / max(b[0] - a[0], 1e-6)
                return a[3] + (b[3] - a[3]) * f
        return st[0][3] if z < st[0][0] else st[-1][3]

    band = loft([(z, w * 1.012 + 0.02, k - 0.02, r) for z, w, k, r in st], trim, "band")
    deform(band, lambda p: Vector((p.x, min(max(p.y, rail_at(p.z) - 0.95), rail_at(p.z) - 0.32), p.z)))
    o.append(band)
    # Deck planks: a slightly inset lid on top with plank seams.
    o.append(prism_y(outline(st, 0.18), deck - 0.05, deck + 0.02, plank, "deck"))
    for k in range(-int(beam), int(beam) + 1):
        x = k * 0.32
        if abs(x) < beam * 0.42:
            o.append(box((x, deck + 0.025, 0.1), (0.02, 0.01, length * 0.72), dark, None, 0.0))
    # Bulwarks with a gold cap.
    rail_h = 0.55
    edge = outline(st, 0.08)
    o += wall(edge, deck, deck + rail_h, 0.12, hull_wood)
    o += wall(edge, deck + rail_h, deck + rail_h + 0.06, 0.18, gold)
    # The aft castle: a raised deck with a lit cabin under it, windows in the transom.
    if castle_aft:
        t0 = 0.74
        poly = outline(st, 0.08, t0, 1.0)
        top = deck + castle_aft
        o.append(prism_y(poly, deck, top, hull_wood, "castle"))
        o.append(prism_y(outline(st, 0.2, t0, 1.0), top - 0.02, top + 0.03, plank, "castle_deck"))
        o += wall(poly, top, top + rail_h, 0.12, hull_wood)
        o += wall(poly, top + rail_h, top + rail_h + 0.06, 0.18, gold)
        zf = st[int(t0 * 14)][0]
        o.append(box((0, deck + castle_aft * 0.5, zf - 0.02), (beam * 0.35, castle_aft * 0.55, 0.06), dark, None, 0.0))
        zt = length * 0.5
        wt = st[-1][1]
        for k in (-1, 0, 1):
            o.append(box((k * wt * 0.5, deck + castle_aft * 0.45, zt + 0.02), (wt * 0.28, castle_aft * 0.35, 0.06), glow,
                         None, 0.0))
        o.append(box((0, deck + castle_aft + 0.1, zt + 0.06), (wt * 1.8, 0.14, 0.1), gold, None, 0.0))
        o.append(cyl((0, top + rail_h + 0.06, zt - 0.1), (0, top + rail_h + 0.9, zt + 0.1), 0.04, 0.04, iron, 6))
        o.append(sphere((0, top + rail_h + 0.95, zt + 0.12), (0.16, 0.22, 0.16), glow, 8, 5))
    if castle_fore:
        poly = outline(st, 0.08, 0.0, 0.22)
        top = deck + castle_fore
        o.append(prism_y(poly, deck, top, hull_wood, "forecastle"))
        o += wall(poly, top, top + rail_h * 0.8, 0.12, hull_wood)
    # Bowsprit and a goblin figurehead.
    bz = -length * 0.5
    bow_y = st[0][3]
    o.append(cyl((0, deck + 0.2, bz + 1.2), (0, bow_y + 1.6, bz - 2.6), 0.12, 0.07, hull_wood, 8))
    fig = m("figurehead", (0.42, 0.6, 0.28), 0.6)
    o.append(sphere((0, bow_y - 0.4, bz - 0.25), (0.32, 0.36, 0.32), fig, 10, 7))
    for s in (-1, 1):
        o.append(cyl((0.25 * s, bow_y - 0.3, bz - 0.25), (0.75 * s, bow_y - 0.1, bz - 0.15), 0.12, 0.0, fig, 6))   # ears
    o.append(sphere((0, bow_y - 0.45, bz - 0.55), (0.1, 0.12, 0.14), fig, 6, 4))   # nose
    for s in (-1, 1):
        o.append(sphere((0.13 * s, bow_y - 0.28, bz - 0.5), (0.07, 0.07, 0.04), gold, 6, 4))   # brass eyes
    # Gun ports and cannons along both sides.
    for g in guns:
        for s in (-1, 1):
            zi = min(range(len(st)), key=lambda i: abs(st[i][0] - g))
            w = st[zi][1]
            y = deck - 0.55
            o.append(box((s * (w + 0.0), y, g), (0.08, 0.5, 0.55), dark, None, 0.0))
            o += cannon(s * (w - 0.6), y, g, s, iron)
    # Masts, yards, sails, a crow's nest on the tallest, a flag on top.
    tallest = max(h for _, h, _ in masts)
    for z, h, sw in masts:
        o.append(cyl((0, deck - 0.2, z), (0, h, z), 0.22, 0.13, hull_wood, 10))
        n_sails = 2 if h > 9 else 1
        lo = deck + 1.8
        span = (h - 1.2 - lo) / n_sails
        for k in range(n_sails):
            w = sw * (1.0 - 0.22 * k)
            cy = lo + span * (k + 0.5)
            yard_y = cy + span * 0.5 - 0.05
            o.append(cyl((-w * 0.55, yard_y, z - 0.25), (w * 0.55, yard_y, z - 0.25), 0.08, 0.08, hull_wood, 6))
            o += sail(0, cy - 0.05, z - 0.4, w, span * 0.92, 0.45, canvas, patch, rng)
        if h == tallest:
            ny = h - 2.2
            o.append(lathe([(0.0, 0.0), (0.55, 0.05), (0.7, 0.6), (0.62, 0.62), (0.0, 0.12)], hull_wood, 12,
                           center=(0, ny, z), smooth=False, name="nest"))
            o += flag(0.1, h + 0.05, z, 2.6, 1.7, black)
        else:
            o += flag(0.1, h + 0.05, z, 1.4, 0.8, black, skull=False)
        # Rigging down to the rails.
        for s in (-1, 1):
            zi = min(range(len(st)), key=lambda i: abs(st[i][0] - z))
            w = st[zi][1]
            for dz in (-0.6, 0.6):
                o.append(cyl((s * w, deck + rail_h, z + dz), (s * 0.15, h - 1.0, z), 0.025, 0.025, rope, 4, smooth=False))
    # Barrels and a crate on deck.
    for k in range(3):
        x = rng.uniform(-beam * 0.25, beam * 0.25)
        zz = rng.uniform(-length * 0.15, length * 0.2)
        o.append(lathe([(0.0, 0.0), (0.26, 0.0), (0.31, 0.3), (0.26, 0.6), (0.0, 0.6)], hull_wood, 10,
                       center=(x, deck, zz), smooth=False, name="barrel"))
        o.append(torus((x, deck + 0.3, zz), 0.31, 0.025, iron, 10, 4))
    return o


def galleon():
    length = 17.0
    return ship(length, 5.4, 2.0,
                masts=[(-4.6, 15.5, 4.4), (0.2, 18.5, 5.4), (4.6, 14.0, 4.0)],
                castle_aft=1.6, castle_fore=0.9, guns=[-3.4, -1.4, 0.8, 2.8], seed=7)


def sloop():
    return ship(10.5, 3.6, 1.4, masts=[(-0.8, 16.5, 4.4)], castle_aft=0.9, castle_fore=0.0, guns=[-1.6, 1.2], seed=11)


# ------------------------------------------------------------------------------------------
# Goblins
# ------------------------------------------------------------------------------------------
GOB = (0.45, 0.66, 0.3)


def goblin(o, coat, legs, arm_l, arm_r):
    """A stubby goblin about 1.05 m tall. arm_l / arm_r are hand offsets from the shoulders.
    Returns the head centre and radius."""
    skin = m("goblin_skin", GOB, 0.65)
    boot = m("goblin_boot", (0.25, 0.17, 0.12), 0.8)
    eye_w = m("goblin_eye", (1.0, 0.88, 0.35), 0.3)
    eye = m("eye", INK, 0.3)
    tooth = m("tooth", WHITE, 0.4)
    for s in (-1, 1):
        o.append(cyl((0.08 * s, 0.3, 0), (0.09 * s, 0.06, 0), 0.055, 0.05, legs, 8))
        o.append(sphere((0.09 * s, 0.05, -0.04), (0.07, 0.05, 0.11), boot, 8, 5))
    o.append(lathe(smooth_profile([(0.0, 0.26), (0.16, 0.28), (0.2, 0.42), (0.15, 0.58), (0.0, 0.62)], 2), coat, 14))
    for s, hand in ((-1, arm_l), (1, arm_r)):
        sh = Vector((0.16 * s, 0.54, 0))
        hp = sh + Vector(hand)
        o.append(cyl(sh, hp, 0.045, 0.04, coat, 8))
        o.append(sphere(hp, (0.05, 0.05, 0.05), skin, 8, 5))
    hy, hr = 0.8, 0.2
    o.append(sphere((0, hy, 0), (hr, hr * 0.92, hr * 0.95), skin, 16, 10))
    for s in (-1, 1):   # the ears: long, pointy, sticking out sideways
        o.append(cyl((0.16 * s, hy + 0.02, 0.02), (0.42 * s, hy + 0.12, 0.06), 0.07, 0.0, skin, 8))
    o.append(sphere((0, hy - 0.03, -0.2), (0.06, 0.06, 0.09), skin, 8, 5))   # a big nose
    for s in (-1, 1):
        o.append(sphere((0.08 * s, hy + 0.05, -0.16), (0.055, 0.06, 0.03), eye_w, 8, 5))
        o.append(sphere((0.08 * s, hy + 0.05, -0.185), (0.025, 0.03, 0.01), eye, 6, 4))
    o.append(box((0, hy - 0.11, -0.17), (0.16, 0.03, 0.02), m("mouth", (0.3, 0.12, 0.1), 0.6), None, 0.0))
    for s in (-1, 1):
        o.append(box((0.045 * s, hy - 0.085, -0.18), (0.03, 0.04, 0.015), tooth, None, 0.0))
    return hy, hr


def captain():
    o = []
    coat = m("captain_coat", (0.7, 0.16, 0.14), 0.7)
    gold = m("trim_gold", (0.85, 0.65, 0.25), 0.4, 0.6)
    hat = m("hat_black", (0.12, 0.1, 0.1), 0.8)
    hy, hr = goblin(o, coat, m("pants_dark", (0.2, 0.17, 0.2), 0.8), (-0.06, -0.2, -0.06), (0.12, 0.2, -0.1))
    for s in (-1, 1):
        o.append(box((0.07 * s, 0.45, -0.17), (0.03, 0.25, 0.02), gold, None, 0.0))   # gold buttons line
    o.append(cyl((0.28, 0.74, -0.1), (0.28, 0.86, -0.1), 0.012, 0.012, m("hook", (0.75, 0.77, 0.8), 0.25, 0.9), 6))
    o.append(torus((0.28, 0.9, -0.12), 0.04, 0.012, m("hook", (0.75, 0.77, 0.8), 0.25, 0.9), 10, 4))
    # Tricorn: a squashed three-cornered brim and a crown, with a skull badge.
    brim = lathe([(0.0, 0.0), (0.3, 0.0), (0.3, 0.04), (0.0, 0.04)], hat, 3, center=(0, hy + 0.13, 0.02), smooth=False,
                 phase=math.pi / 2)
    deform(brim, lambda p: Vector((p.x, p.y + 0.12 * max(0.0, (Vector((p.x, 0, p.z - 0.02)).length - 0.12)), p.z)))
    o.append(brim)
    o.append(sphere((0, hy + 0.2, 0.02), (0.16, 0.11, 0.15), hat, 12, 6))
    o.append(sphere((0, hy + 0.21, -0.14), (0.04, 0.04, 0.015), m("bone", (0.93, 0.91, 0.82), 0.7), 6, 4))
    return o


def deckhand():
    o = []
    shirt = m("shirt_white", WHITE, 0.8)
    red = m("bandana_red", (0.82, 0.18, 0.15), 0.7)
    wood = m("mop_wood", (0.6, 0.45, 0.3), 0.8)
    hy, hr = goblin(o, shirt, m("pants_blue", (0.25, 0.32, 0.5), 0.8), (-0.08, -0.22, -0.02), (0.06, -0.12, -0.16))
    for y in (0.34, 0.42, 0.5):   # stripes
        o.append(torus((0, y, 0), 0.19, 0.022, red, 14, 4))
    o.append(sphere((0, hy + 0.08, 0.01), (0.205, 0.14, 0.2), red, 12, 6))   # bandana
    o.append(sphere((0.04, hy + 0.06, 0.2), (0.06, 0.04, 0.06), red, 6, 4))   # its knot
    # A mop, held out front.
    o.append(cyl((0.22, 0.02, -0.25), (0.22, 1.05, -0.16), 0.022, 0.022, wood, 6))
    o.append(sphere((0.22, 0.05, -0.26), (0.11, 0.07, 0.11), m("mop_head", (0.82, 0.78, 0.65), 0.9), 8, 4))
    return o


def lookout():
    o = []
    vest = m("vest_brown", (0.45, 0.3, 0.2), 0.8)
    purple = m("bandana_purple", (0.45, 0.25, 0.6), 0.7)
    brass = m("spyglass", (0.85, 0.65, 0.25), 0.35, 0.7)
    hy, hr = goblin(o, vest, m("pants_dark", (0.2, 0.17, 0.2), 0.8), (-0.04, 0.22, -0.12), (0.06, -0.22, -0.02))
    o.append(sphere((0, hy + 0.08, 0.01), (0.205, 0.14, 0.2), purple, 12, 6))
    o.append(box((0.08, hy + 0.05, -0.19), (0.09, 0.08, 0.02), m("hat_black", (0.12, 0.1, 0.1), 0.8), None, 0.0))   # eyepatch
    o.append(box((0, hy + 0.1, -0.17), (0.4, 0.02, 0.02), m("hat_black", (0.12, 0.1, 0.1), 0.8), rot_z(-0.25), 0.0))
    o.append(cyl((-0.2, 0.76, -0.12), (-0.1, 0.86, -0.42), 0.035, 0.028, brass, 8))   # spyglass to the good eye
    return o


def main():
    reset()
    objs = [join(galleon(), "Galleon"), join(sloop(), "Sloop"), join(captain(), "GoblinCaptain"),
            join(deckhand(), "GoblinDeckhand"), join(lookout(), "GoblinLookout")]
    export("pirates", objs)


if __name__ == "__main__":
    main()
