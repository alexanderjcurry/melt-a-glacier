"""Pines and flowers. Writes models/nature.glb:
    Pine0..Pine3   about 4 m tall, trunk at the origin (Scenery.forest)
    Daisy Tulip Cosmos Sunflower   small clumps that bloom as the ice goes
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403

import bmesh  # noqa: E402


def m(name, rgb, rough=0.85):
    return mat(name, rgb, rough)


def tier(y0, r, h, material, points, rng, droop=0.12):
    """One layer of branches: a cone whose bottom edge zig-zags in and out,
    drooping a little at the tips, so it reads as bunches of needles."""
    bm = bmesh.new()
    top = bm.verts.new(to_b((0, y0 + h, 0)))
    centre = bm.verts.new(to_b((0, y0 + h * 0.15, 0)))
    ring = []
    n = points * 2
    for k in range(n):
        a = math.tau * k / n + rng.uniform(-0.05, 0.05)
        out = k % 2 == 0
        rr = r * (1.0 if out else 0.72) * rng.uniform(0.92, 1.05)
        y = y0 - (droop if out else 0.0)
        ring.append(bm.verts.new(to_b((math.cos(a) * rr, y, math.sin(a) * rr))))
    for k in range(n):
        bm.faces.new([top, ring[k], ring[(k + 1) % n]])
        bm.faces.new([centre, ring[(k + 1) % n], ring[k]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    from kit import _obj
    return _obj("tier", bm, material, 0.0)


def pine(v):
    rng = random.Random(500 + v)
    o = []
    bark = m("bark", (0.36, 0.24, 0.16))
    greens = [(0.13, 0.3, 0.19), (0.17, 0.34, 0.17), (0.12, 0.28, 0.22), (0.19, 0.36, 0.2)]
    g = greens[v]
    o.append(cyl((0, 0, 0), (0, 1.5, 0), 0.17, 0.09, bark, 7, smooth=False))
    layers = [5, 6, 4, 5][v]
    slim = [1.0, 0.85, 1.12, 0.95][v]
    for k in range(layers):
        t = k / (layers - 1)
        y0 = 0.75 + k * (3.1 / layers)
        r = (1.4 - 1.0 * t) * slim * rng.uniform(0.92, 1.08)
        h = 1.15 - 0.25 * t
        c = tuple(min(1.0, x * (1.0 + 0.07 * k)) for x in g)
        o.append(tier(y0, r, h, m("needles%d_%d" % (v, k), c), 7 - k // 2, rng))
    o.append(tier(0.75 + layers * (3.1 / layers) - 0.1, 0.22, 0.55, m("needles%d_top" % v, tuple(min(1, x * 1.4) for x in g)), 4, rng, 0.04))
    return o


def leaves(o, n, h, rng, colour=(0.3, 0.55, 0.25)):
    leaf = m("leaf", colour)
    for k in range(n):
        a = math.tau * k / n + rng.uniform(-0.3, 0.3)
        lf = sphere((0, 0, 0), (0.02, 0.012, h * 0.35), leaf, 6, 4)
        transform(lf, rot_y(-a) @ rot_x(-0.7), (math.cos(a) * h * 0.18, h * 0.12, math.sin(a) * h * 0.18))
        o.append(lf)


def bloom(o, x, z, h, petals, petal_col, centre_col, petal_len, rng, tilt=0.35, cup=False):
    stem = m("stem", (0.3, 0.55, 0.22))
    a = rng.uniform(0, math.tau)
    top = Vector((x + math.cos(a) * 0.03, h, z + math.sin(a) * 0.03))
    o.append(cyl((x, 0, z), top, 0.008, 0.006, stem, 5, smooth=False))
    face_dir = rot_x(-tilt) @ rot_y(a)
    if cup:   # a tulip: a closed cup of petals
        for k in range(petals):
            b = math.tau * k / petals
            p = sphere((0, 0, 0), (petal_len * 0.45, petal_len, petal_len * 0.3), m("petal_" + str(petal_col), petal_col, 0.6), 8, 5)
            transform(p, rot_y(-b) @ rot_x(0.2), top + Vector((math.cos(b) * petal_len * 0.25, petal_len * 0.8, math.sin(b) * petal_len * 0.25)))
            o.append(p)
        return
    o.append(sphere(top, (petal_len * 0.38, petal_len * 0.2, petal_len * 0.38), m("centre_" + str(centre_col), centre_col, 0.7), 8, 5,
                    basis=face_dir))
    for k in range(petals):
        b = math.tau * k / petals
        p = sphere((0, 0, 0), (petal_len * 0.18, 0.006, petal_len * 0.5), m("petal_" + str(petal_col), petal_col, 0.7), 6, 3)
        transform(p, face_dir @ rot_y(-b), top + face_dir @ Vector((math.cos(b) * petal_len * 0.6, 0.0, math.sin(b) * petal_len * 0.6)))
        o.append(p)


def flower(kind):
    rng = random.Random(hash(kind) % 1000)
    o = []
    if kind == "Daisy":
        leaves(o, 5, 0.25, rng)
        for x, z, h in ((0, 0, 0.22), (0.07, 0.05, 0.17), (-0.06, 0.04, 0.19)):
            bloom(o, x, z, h, 12, (0.98, 0.97, 0.94), (1.0, 0.8, 0.2), 0.07, rng)
    elif kind == "Tulip":
        leaves(o, 4, 0.3, rng, (0.32, 0.58, 0.32))
        for x, z, h, c in ((0, 0, 0.28, (0.9, 0.2, 0.25)), (0.06, 0.05, 0.24, (0.98, 0.55, 0.2))):
            bloom(o, x, z, h, 5, c, c, 0.05, rng, cup=True)
    elif kind == "Cosmos":
        leaves(o, 5, 0.25, rng)
        for x, z, h in ((0, 0, 0.26), (0.06, -0.04, 0.2), (-0.05, 0.05, 0.23)):
            bloom(o, x, z, h, 8, (0.97, 0.55, 0.72), (1.0, 0.85, 0.3), 0.08, rng)
    else:
        leaves(o, 6, 0.4, rng)
        bloom(o, 0, 0, 0.5, 16, (1.0, 0.78, 0.15), (0.4, 0.25, 0.12), 0.12, rng, tilt=0.6)
    return o


def main():
    reset()
    objs = [join(pine(v), "Pine%d" % v) for v in range(4)]
    for kind in ("Daisy", "Tulip", "Cosmos", "Sunflower"):
        objs.append(join(flower(kind), kind))
    export("nature", objs)


if __name__ == "__main__":
    main()
