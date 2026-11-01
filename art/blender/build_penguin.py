"""The penguin helper (about 0.84 m tall, facing -Z, feet on y = 0).
Writes models/penguin.glb with these meshes, each around its own pivot so the
game can animate them (see Creatures.penguin):
    Body      everything that doesn't move on its own; the scarf uses the
              material "scarf" so the game can recolour it per penguin
    FlipperL  pivot (-0.205, 0.52, 0)     FlipperR  pivot (0.205, 0.52, 0)
    Foot      pivot at the ankle (used for both feet)
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403

BLACK = (0.1, 0.12, 0.17)
WHITE = (0.97, 0.96, 0.93)
ORANGE = (1.0, 0.58, 0.14)


def lean(p):
    """A little forward lean of the head, so it looks curious."""
    return p + Vector((0, 0, -0.035 * max(0.0, (p.y - 0.5) / 0.34) ** 2))


def body(objs):
    black = mat("feathers", BLACK, 0.55)
    white = mat("belly", WHITE, 0.7)
    prof = [(0.0, 0.0), (0.13, 0.015), (0.2, 0.07), (0.235, 0.17), (0.24, 0.29), (0.218, 0.41), (0.182, 0.5),
            (0.158, 0.565), (0.162, 0.63), (0.158, 0.7), (0.138, 0.765), (0.095, 0.815), (0.035, 0.84), (0.0, 0.843)]
    objs.append(deform(lathe(smooth_profile(prof, 3), black, 40, scale_xz=(1.0, 0.9), name="Body"), lean))
    # The white belly and face are rounded shells that bulge just out of the
    # black body, so the edge between them is a clean curve.
    objs.append(sphere((0, 0.28, -0.1), (0.185, 0.245, 0.138), white, 28, 16))
    for s in (-1, 1):
        objs.append(deform(sphere((0.047 * s, 0.678, -0.062), (0.092, 0.088, 0.092), white, 16, 10), lean))
    objs.append(deform(sphere((0, 0.63, -0.06), (0.088, 0.06, 0.092), white, 16, 10), lean))


def face(objs):
    eye = mat("eye", (0.03, 0.03, 0.05), 0.15)
    shine = mat("shine", (1, 1, 1), 0.2)
    blush = mat("blush", (1.0, 0.62, 0.66), 0.8)
    beak = mat("beak", ORANGE, 0.5)
    beak_dark = mat("beak_dark", (0.9, 0.42, 0.08), 0.5)
    for s in (-1, 1):
        objs.append(sphere((0.056 * s, 0.688, -0.153), (0.03, 0.036, 0.02), eye, 12, 8))
        objs.append(sphere((0.05 * s, 0.7, -0.17), (0.01, 0.01, 0.006), shine, 6, 4))
        objs.append(sphere((0.064 * s, 0.678, -0.172), (0.005, 0.005, 0.004), shine, 6, 4))
        objs.append(sphere((0.094 * s, 0.64, -0.135), (0.03, 0.017, 0.012), blush, 8, 5, basis=rot_y(-0.5 * s)))
        # Brows: a tiny tilt makes it look keen.
        objs.append(box((0.056 * s, 0.735, -0.155), (0.04, 0.009, 0.012), eye, rot_z(-0.25 * s) @ rot_x(0.3), 0.003))
    # Beak: upper and lower halves, pointy.
    upper = lathe([(0.0, 0.0), (0.042, 0.0), (0.028, 0.06), (0.0, 0.11)], beak, 12, smooth=True, scale_xz=(1.0, 0.6))
    transform(upper, rot_x(-math.pi / 2 - 0.12), (0, 0.648, -0.14))
    objs.append(upper)
    lower = lathe([(0.0, 0.0), (0.03, 0.0), (0.018, 0.04), (0.0, 0.07)], beak_dark, 10, smooth=True, scale_xz=(1.0, 0.5))
    transform(lower, rot_x(-math.pi / 2 + 0.1), (0, 0.628, -0.14))
    objs.append(lower)


def scarf(objs):
    sc = mat("scarf", (0.85, 0.18, 0.2), 0.9)
    ring = torus((0, 0.535, -0.004), 0.162, 0.04, sc, 28, 8)
    deform(ring, lambda p: Vector((p.x, p.y, p.z * 0.9 - 0.004)))
    objs.append(ring)
    objs.append(sphere((0.085, 0.52, -0.14), (0.04, 0.035, 0.03), sc, 8, 6))
    # Two tails hanging down the front, a bit flared.
    for k, (ang, ln) in enumerate(((0.18, 0.17), (-0.05, 0.13))):
        tail = box((0, -ln * 0.5, 0), (0.06, ln, 0.022), sc, None, 0.008)
        deform(tail, lambda p: Vector((p.x * (1.0 + 0.5 * (-p.y / ln)), p.y, p.z)))
        transform(tail, rot_z(ang) @ rot_x(-0.3), (0.085 + 0.02 * k, 0.51, -0.155 - 0.01 * k))
        objs.append(tail)


def torch(objs):
    red = mat("tank", (0.86, 0.16, 0.12), 0.35, 0.2)
    brass = mat("brass", (0.9, 0.72, 0.32), 0.3, 0.85)
    black = mat("hose", (0.12, 0.12, 0.13), 0.6)
    tank = lathe(smooth_profile([(0.0, 0.0), (0.03, 0.002), (0.042, 0.02), (0.042, 0.1), (0.03, 0.118), (0.0, 0.12)], 2),
                 red, 14)
    a, b = Vector((0.13, 0.31, -0.19)), Vector((0.13, 0.255, -0.3))
    q = Vector((0, 1, 0)).rotation_difference((b - a).normalized())
    transform(tank, q.to_matrix(), a)
    objs.append(tank)
    objs.append(cyl(b, b + (b - a).normalized() * 0.02, 0.018, 0.018, brass, 8))
    objs.append(cyl((0.13, 0.25, -0.31), (0.13, 0.205, -0.36), 0.013, 0.008, brass, 8))
    objs.append(cyl((0.13, 0.205, -0.36), (0.13, 0.198, -0.368), 0.012, 0.012, black, 8))
    objs.append(box((0.165, 0.27, -0.29), (0.03, 0.012, 0.012), black, rot_y(0.3), 0.0))


def flipper(side):
    m = mat("feathers", BLACK, 0.55)
    ob = sphere((0, 0, 0), (0.032, 0.17, 0.08), m, 12, 10, name="Flipper")

    def shape(p):
        t = (p.y + 0.17) / 0.34    # 0 at the tip, 1 at the shoulder
        k = 0.45 + 0.55 * t
        return Vector((p.x * (0.6 + 0.4 * t), p.y, p.z * k + 0.02 * (1 - t)))

    deform(ob, shape)
    transform(ob, rot_z(0.24 * side), (0.03 * side, -0.15, 0.0))
    ob.name = "FlipperL" if side < 0 else "FlipperR"
    ob.data.name = ob.name
    return ob


def foot():
    m = mat("beak", ORANGE, 0.5)
    objs = [sphere((0, 0.0, -0.035), (0.06, 0.026, 0.085), m, 12, 6)]
    for k in (-1, 0, 1):
        objs.append(sphere((0.035 * k, 0.0, -0.11 + abs(k) * 0.012), (0.024, 0.02, 0.03), m, 8, 5))
    ob = join(objs, "Foot")
    return ob


def main():
    reset()
    parts = []
    body(parts)
    face(parts)
    scarf(parts)
    torch(parts)
    b = join(parts, "Body")
    export("penguin", [b, flipper(-1), flipper(1), foot()])


if __name__ == "__main__":
    main()
