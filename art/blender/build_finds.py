"""The eleven things frozen in the glacier (Balance.DISCOVERIES, in order).
Writes models/finds.glb with one mesh per find, Find0..Find10, each standing
on y = 0 and facing -Z (toward you as you dig it out). The game scales and
centres them (World._make_find_marker), so sizes here are only relative.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403

INK = (0.1, 0.09, 0.1)
WHITE = (0.97, 0.96, 0.93)


def m(name, rgb, rough=0.7, metal=0.0, emit=None):
    return mat(name, rgb, rough, metal, emit)


def mitten():
    o = []
    red = m("mitten_red", (0.86, 0.2, 0.22), 0.95)
    cream = m("wool_cream", (0.97, 0.93, 0.84), 0.95)
    o.append(sphere((0, 0.36, 0), (0.17, 0.25, 0.08), red, 18, 12))
    o.append(sphere((0.15, 0.27, 0), (0.06, 0.12, 0.06), red, 12, 8, basis=rot_z(-0.6)))
    o.append(cyl((0, 0.0, 0), (0, 0.14, 0), 0.14, 0.15, cream, 18))
    for k in range(9):   # ribbing
        t = math.tau * k / 9 + 0.3
        o.append(box((math.cos(t) * 0.143, 0.07, math.sin(t) * 0.143), (0.02, 0.13, 0.02), cream, rot_y(-t), 0.005))
    # A knitted snowflake on the back.
    for k in range(3):
        o.append(box((0, 0.4, -0.08), (0.016, 0.16, 0.012), m("wool_white", WHITE, 0.95), rot_z(k * math.pi / 3), 0.0))
    o.append(box((0, 0.2, -0.075), (0.3, 0.02, 0.012), m("wool_white", WHITE, 0.95), None, 0.0))
    return o


def pizza():
    o = []
    card = m("cardboard", (0.78, 0.6, 0.4), 0.95)
    crust = m("crust", (0.88, 0.62, 0.3), 0.8)
    cheese = m("cheese", (1.0, 0.82, 0.38), 0.6)
    pep = m("pepperoni", (0.75, 0.2, 0.15), 0.6)
    basil = m("basil", (0.25, 0.55, 0.22), 0.7)
    tilt = rot_x(-1.1)   # standing up on its edge, leaning back, facing -Z
    c = Vector((0, 0.3, 0.05))
    o.append(box(c + tilt @ Vector((0, -0.02, 0)), (0.66, 0.03, 0.66), card, tilt, 0.01))
    o.append(box(c + tilt @ Vector((0, 0.03, 0.33)), (0.66, 0.1, 0.02), card, tilt, 0.008))
    o.append(box(c + tilt @ Vector((0, 0.03, -0.33)), (0.66, 0.1, 0.02), card, tilt, 0.008))
    disc = cyl((0, 0, 0), (0, 0.035, 0), 0.29, 0.29, crust, 24, smooth=False)
    top = cyl((0, 0.02, 0), (0, 0.045, 0), 0.25, 0.25, cheese, 24, smooth=False)
    ring = torus((0, 0.035, 0), 0.27, 0.03, crust, 24, 6)
    parts = [disc, top, ring]
    for k, (x, z) in enumerate([(0.1, 0.08), (-0.12, 0.05), (0.02, -0.14), (-0.06, 0.17), (0.15, -0.1), (-0.15, -0.12)]):
        parts.append(cyl((x, 0.045, z), (x, 0.055, z), 0.045, 0.045, pep, 10, smooth=False))
        if k % 2 == 0:
            parts.append(sphere((x + 0.05, 0.05, z - 0.04), (0.025, 0.006, 0.015), basil, 6, 3))
    for p in parts:
        transform(p, tilt, c + tilt @ Vector((0, 0.0, 0)))
        o.append(p)
    # A cheese string hanging off the edge, and frost.
    o.append(cyl(c + tilt @ Vector((0.18, 0.05, 0.2)), c + tilt @ Vector((0.2, 0.0, 0.33)) + Vector((0, -0.08, 0)), 0.01, 0.006, cheese, 6))
    return o


def mixtape():
    o = []
    shell = m("cassette", (0.16, 0.16, 0.19), 0.4)
    label = m("cassette_label", (0.98, 0.93, 0.8), 0.8)
    stripe = m("cassette_stripe", (0.95, 0.45, 0.6), 0.8)
    stripe2 = m("cassette_stripe2", (0.35, 0.75, 0.9), 0.8)
    win = m("cassette_window", (0.35, 0.3, 0.32), 0.15)
    reel = m("reel", (0.95, 0.95, 0.95), 0.5)
    o.append(box((0, 0.21, 0), (0.62, 0.4, 0.08), shell, None, 0.03))
    o.append(box((0, 0.27, -0.042), (0.52, 0.22, 0.01), label, None, 0.0))
    o.append(box((0, 0.355, -0.046), (0.52, 0.035, 0.01), stripe, None, 0.0))
    o.append(box((0, 0.32, -0.046), (0.52, 0.025, 0.01), stripe2, None, 0.0))
    o.append(box((0, 0.24, -0.048), (0.28, 0.08, 0.01), win, None, 0.0))
    for x in (-0.09, 0.09):
        o.append(cyl((x, 0.24, -0.04), (x, 0.24, -0.052), 0.035, 0.035, reel, 12, smooth=False))
        for k in range(6):
            t = math.tau * k / 6
            o.append(box((x + math.cos(t) * 0.022, 0.24 + math.sin(t) * 0.022, -0.054), (0.012, 0.012, 0.006), shell, None, 0.0))
    o.append(box((0, 0.06, -0.04), (0.42, 0.08, 0.02), shell, None, 0.01))
    for x in (-0.12, -0.04, 0.04, 0.12):
        o.append(box((x, 0.04, -0.052), (0.03, 0.03, 0.01), win, None, 0.0))
    # Tape spilling out at the bottom.
    for k in range(5):
        o.append(cyl((0.05 + k * 0.05, 0.02 + 0.03 * math.sin(k), -0.05), (0.1 + k * 0.05, 0.02 + 0.03 * math.sin(k + 1), -0.08),
                     0.006, 0.006, m("tape", (0.3, 0.2, 0.15), 0.3), 4))
    return o


def snowmobile():
    o = []
    red = m("sled_red", (0.9, 0.2, 0.15), 0.35, 0.1)
    black = m("sled_black", (0.12, 0.12, 0.14), 0.6)
    glass = m("sled_glass", (0.45, 0.65, 0.8), 0.1, 0.2)
    steel = m("steel", (0.7, 0.72, 0.76), 0.3, 0.8)
    yellow = m("sled_yellow", (1.0, 0.8, 0.2), 0.5)
    # Faces -Z: nose and skis at the front.
    o.append(box((0, 0.42, -0.25), (0.6, 0.35, 0.9), red, rot_x(-0.12), 0.08))
    o.append(box((0, 0.36, 0.45), (0.58, 0.3, 0.7), red, None, 0.06))
    o.append(box((0, 0.58, 0.48), (0.42, 0.14, 0.62), black, None, 0.06))   # seat
    o.append(box((0, 0.42, 0.45), (0.62, 0.04, 0.72), yellow, None, 0.0))   # stripe
    o.append(box((0, 0.75, -0.2), (0.5, 0.3, 0.03), glass, rot_x(0.5), 0.02))
    o.append(cyl((-0.28, 0.72, -0.05), (0.28, 0.72, -0.05), 0.02, 0.02, black, 8))
    for s in (-1, 1):
        o.append(box((0.3 * s, 0.72, -0.05), (0.07, 0.05, 0.05), black, None, 0.01))
        o.append(cyl((0.25 * s, 0.25, -0.55), (0.32 * s, 0.05, -0.55), 0.03, 0.03, steel, 8))
        ski = box((0.34 * s, 0.03, -0.55), (0.14, 0.04, 0.9), black, None, 0.015)
        deform(ski, lambda p: p + Vector((0, max(0.0, -(p.z + 0.85)) * 1.2, 0)))
        o.append(ski)
    o.append(box((0, 0.13, 0.5), (0.46, 0.22, 0.8), black, None, 0.06))   # track
    for k in range(7):
        o.append(box((0, 0.02, 0.15 + k * 0.11), (0.47, 0.03, 0.04), m("tread", (0.25, 0.25, 0.28), 0.8), None, 0.0))
    o.append(sphere((0, 0.5, -0.72), (0.12, 0.07, 0.04), m("headlight", (1.0, 0.95, 0.75), 0.2, 0.0, (1.0, 0.9, 0.6)), 10, 6))
    # The keys, still in it.
    o.append(torus((0.12, 0.62, -0.05), 0.025, 0.006, steel, 10, 4))
    o.append(box((0.12, 0.58, -0.05), (0.02, 0.05, 0.01), m("keyfob", (0.2, 0.5, 0.95), 0.4), None, 0.0))
    return o


def mammoth():
    o = []
    fur = m("fur", (0.55, 0.35, 0.22), 0.95)
    fur_d = m("fur_dark", (0.42, 0.25, 0.15), 0.95)
    tusk = m("tusk", (0.97, 0.93, 0.82), 0.5)
    eye = m("eye_black", INK, 0.2)
    o.append(sphere((0, 0.95, 0.15), (0.55, 0.5, 0.7), fur, 20, 12))
    o.append(sphere((0, 1.15, -0.45), (0.38, 0.4, 0.38), fur, 18, 12))
    o.append(sphere((0, 1.5, -0.4), (0.25, 0.2, 0.25), fur_d, 12, 8))   # the dome on top of the head
    for sx in (-1, 1):
        for sz in (-0.25, 0.5):
            o.append(cyl((sx * 0.3, 0.7, sz), (sx * 0.3, 0.0, sz), 0.17, 0.16, fur_d, 12))
            o.append(cyl((sx * 0.3, 0.02, sz), (sx * 0.3, 0.0, sz), 0.17, 0.17, m("toenail", (0.85, 0.8, 0.7), 0.6), 12))
        o.append(sphere((sx * 0.36, 1.18, -0.3), (0.06, 0.2, 0.16), fur_d, 10, 6))   # ears
        o.append(sphere((sx * 0.16, 1.25, -0.79), (0.045, 0.05, 0.03), eye, 8, 6))
        o.append(sphere((sx * 0.15, 1.27, -0.82), (0.015, 0.015, 0.01), m("shine", WHITE, 0.2), 6, 4))
        # Annoyed brows: angled down toward the middle.
        o.append(box((sx * 0.16, 1.34, -0.8), (0.14, 0.035, 0.04), fur_d, rot_z(0.4 * sx), 0.01))
        # Tusks: curving out and up.
        prev = Vector((sx * 0.15, 0.95, -0.75))
        for k in range(1, 7):
            t = k / 6
            p = Vector((sx * (0.15 + 0.2 * t), 0.95 - 0.3 * t + 0.45 * t * t, -0.75 - 0.4 * t + 0.2 * t * t))
            o.append(cyl(prev, p, 0.055 * (1 - t * 0.6), 0.055 * (1 - (t + 0.17) * 0.6), tusk, 8))
            prev = p
    # Trunk.
    prev = Vector((0, 1.05, -0.8))
    for k in range(1, 8):
        t = k / 7
        p = Vector((0.05 * math.sin(t * 3), 1.05 - 0.75 * t, -0.85 - 0.15 * t + 0.25 * t * t))
        o.append(cyl(prev, p, 0.12 * (1 - 0.45 * (k - 1) / 7), 0.12 * (1 - 0.45 * k / 7), fur_d, 10))
        prev = p
    # Shaggy fringe under the belly.
    for k in range(14):
        x = -0.45 + k * 0.07
        o.append(lathe([(0.0, 0.0), (0.06, 0.0), (0.0, -0.18)], fur_d, 5, center=(x, 0.62, 0.15 + 0.1 * math.sin(k)), smooth=False))
    o.append(cyl((0, 1.0, 0.85), (0, 0.6, 1.0), 0.04, 0.02, fur_d, 6))   # tail
    return o


def helmet():
    o = []
    steel = m("helmet_steel", (0.62, 0.64, 0.68), 0.35, 0.8)
    brass = m("brass", (0.88, 0.68, 0.3), 0.35, 0.85)
    leather = m("leather", (0.42, 0.25, 0.15), 0.8)
    prof = [(math.sin(a) * 0.32, math.cos(a) * 0.34) for a in [math.pi / 2 * (1 - k / 10) for k in range(11)]]
    o.append(lathe([(0.32, 0.0)] + prof[1:], steel, 24, center=(0, 0.1, 0)))
    o.append(torus((0, 0.12, 0), 0.325, 0.035, brass, 24, 6))
    for k in range(4):   # crossing bands
        t = k * math.pi / 2
        for j in range(8):
            a0 = math.pi / 2 * j / 8
            a1 = math.pi / 2 * (j + 1) / 8
            p0 = Vector((math.cos(t) * math.cos(a0) * 0.335, 0.1 + math.sin(a0) * 0.35, math.sin(t) * math.cos(a0) * 0.335))
            p1 = Vector((math.cos(t) * math.cos(a1) * 0.335, 0.1 + math.sin(a1) * 0.35, math.sin(t) * math.cos(a1) * 0.335))
            o.append(cyl(p0, p1, 0.022, 0.022, brass, 6))
    o.append(sphere((0, 0.45, 0), (0.05, 0.04, 0.05), brass, 8, 5))
    o.append(box((0, 0.02, -0.33), (0.07, 0.26, 0.03), steel, None, 0.01))   # nose guard
    for k in range(10):
        t = math.tau * k / 10
        o.append(sphere((math.cos(t) * 0.36, 0.12, math.sin(t) * 0.36), (0.014, 0.014, 0.014), steel, 6, 4))
    for s in (-1, 1):   # short leather cheek straps
        o.append(box((0.3 * s, 0.06, 0.04), (0.03, 0.1, 0.07), leather, None, 0.01))
    # Little rim of ice still stuck to it... no: a dent, to show it saw action.
    return o


def caveman():
    o = []
    skin = m("skin_cave", (0.92, 0.7, 0.55), 0.8)
    hair = m("hair_cave", (0.3, 0.18, 0.1), 0.95)
    hide = m("leopard", (0.95, 0.65, 0.25), 0.9)
    spot = m("leopard_spot", (0.35, 0.22, 0.1), 0.9)
    eye = m("eye_black", INK, 0.2)
    # Disco pose: right arm pointing up, left hand on hip, one knee bent.
    o.append(sphere((0, 0.78, 0), (0.26, 0.32, 0.2), hide, 16, 10))
    for k in range(9):
        a = k * 2.3
        o.append(sphere((math.cos(a) * 0.24, 0.65 + (k % 3) * 0.12, math.sin(a) * 0.18), (0.035, 0.03, 0.01), spot, 6, 4,
                        basis=rot_y(-a + math.pi / 2)))
    o.append(sphere((0, 1.25, 0), (0.2, 0.22, 0.19), skin, 16, 10))
    o.append(sphere((0, 1.38, 0.03), (0.25, 0.2, 0.23), hair, 12, 8))   # wild hair
    for k in range(7):
        a = k * 0.9
        o.append(sphere((math.cos(a) * 0.2, 1.4 + 0.08 * math.sin(k), math.sin(a) * 0.2 + 0.03), (0.09, 0.08, 0.09), hair, 8, 5))
    o.append(sphere((0, 1.12, -0.11), (0.17, 0.12, 0.1), hair, 12, 8))   # beard
    o.append(sphere((0, 1.24, -0.18), (0.045, 0.04, 0.04), skin, 8, 5))   # nose
    for s in (-1, 1):
        o.append(sphere((0.07 * s, 1.31, -0.165), (0.025, 0.03, 0.015), eye, 8, 5))
        o.append(box((0.07 * s, 1.36, -0.17), (0.07, 0.025, 0.03), hair, rot_z(-0.25 * s), 0.008))
    o.append(box((0, 1.17, -0.19), (0.08, 0.025, 0.02), m("mouth", (0.5, 0.15, 0.15), 0.6), None, 0.008))
    # Arms.
    o.append(cyl((0.22, 0.98, 0), (0.42, 1.35, -0.05), 0.07, 0.06, skin, 10))
    o.append(cyl((0.42, 1.35, -0.05), (0.55, 1.75, -0.08), 0.06, 0.05, skin, 10))
    o.append(sphere((0.56, 1.8, -0.08), (0.06, 0.07, 0.06), skin, 8, 6))
    o.append(cyl((0.56, 1.84, -0.08), (0.57, 1.95, -0.09), 0.02, 0.018, skin, 6))   # pointing finger
    o.append(cyl((-0.22, 0.98, 0), (-0.42, 0.78, -0.05), 0.07, 0.06, skin, 10))
    o.append(cyl((-0.42, 0.78, -0.05), (-0.26, 0.62, -0.08), 0.06, 0.05, skin, 10))
    # Legs: one straight, one kicked out.
    o.append(cyl((-0.1, 0.52, 0), (-0.13, 0.05, 0), 0.08, 0.07, skin, 10))
    o.append(cyl((0.1, 0.52, 0), (0.32, 0.3, -0.05), 0.08, 0.07, skin, 10))
    o.append(cyl((0.32, 0.3, -0.05), (0.3, 0.05, -0.02), 0.07, 0.065, skin, 10))
    for x in (-0.14, 0.3):
        o.append(sphere((x, 0.04, -0.06), (0.08, 0.05, 0.12), skin, 8, 5))
    # A club at his feet.
    o.append(cyl((-0.35, 0.05, 0.15), (-0.05, 0.12, 0.3), 0.04, 0.08, m("club", (0.55, 0.38, 0.22), 0.9), 8))
    return o


def fish():
    o = []
    body = m("fish_body", (0.32, 0.5, 0.62), 0.5)
    belly = m("fish_belly", (0.8, 0.85, 0.8), 0.5)
    fin = m("fish_fin", (0.25, 0.4, 0.52), 0.6)
    spot = m("fish_spot", (0.85, 0.85, 0.75), 0.6)
    # Faces -X on its belly... no: swims toward -X, side turned to -Z so you see its profile.
    b = sphere((0, 0.35, 0), (0.55, 0.26, 0.17), body, 22, 12)
    o.append(b)
    o.append(sphere((0.02, 0.27, 0), (0.48, 0.17, 0.15), belly, 18, 10))
    o.append(sphere((-0.45, 0.36, 0), (0.17, 0.18, 0.14), body, 12, 8))   # head
    o.append(sphere((-0.5, 0.42, -0.1), (0.055, 0.055, 0.03), m("fish_eye", (1.0, 0.85, 0.3), 0.2), 10, 6))
    o.append(sphere((-0.51, 0.42, -0.125), (0.03, 0.03, 0.015), m("eye_black", INK, 0.2), 8, 5))
    o.append(box((-0.6, 0.3, -0.06), (0.1, 0.015, 0.1), m("mouth", (0.5, 0.15, 0.15), 0.6), rot_z(-0.2), 0.0))
    for k in range(4):   # teeth
        o.append(lathe([(0, 0), (0.012, 0), (0, -0.03)], m("tooth", WHITE, 0.4), 4, center=(-0.6 + k * 0.025, 0.33, -0.07 + k * 0.01), smooth=False))
    # Lobed fins (it's a prehistoric fish).
    for x, y, a in ((-0.15, 0.1, 0.9), (0.15, 0.12, 0.7), (-0.05, 0.6, -0.4), (0.2, 0.57, -0.6)):
        o.append(sphere((x, y, -0.05), (0.12, 0.05, 0.03), fin, 10, 6, basis=rot_z(a)))
    tail = extrude([(0.5, 0.35), (0.85, 0.65), (0.78, 0.35), (0.85, 0.05)], -0.02, 0.02, fin, 0.01)
    o.append(tail)
    for k in range(10):
        o.append(sphere((-0.3 + k * 0.08, 0.4 + 0.08 * math.sin(k * 1.7), -0.155), (0.022, 0.022, 0.01), spot, 6, 4))
    return o


def phone():
    o = []
    fur = m("yeti_fur", (0.93, 0.93, 0.95), 0.95)
    screen = m("screen", (0.25, 0.55, 0.95), 0.2, 0.0, (0.2, 0.45, 0.9))
    case = m("phone_case", (0.15, 0.15, 0.18), 0.4)
    badge = m("badge", (0.95, 0.2, 0.2), 0.4, 0.0, (0.9, 0.1, 0.1))
    tilt = rot_x(-0.25)
    c = Vector((0, 0.42, 0))
    o.append(box(c, (0.42, 0.8, 0.06), case, tilt, 0.05))
    o.append(box(c + tilt @ Vector((0, 0.02, -0.032)), (0.36, 0.66, 0.01), screen, tilt, 0.0))
    # App icons and a big notification badge.
    cols = [(0.95, 0.75, 0.2), (0.4, 0.85, 0.45), (0.95, 0.45, 0.6), (0.6, 0.5, 0.95)]
    for k in range(8):
        x = -0.12 + (k % 4) * 0.08
        y = 0.22 - (k // 4) * 0.1
        o.append(box(c + tilt @ Vector((x, y, -0.04)), (0.055, 0.055, 0.008), m("app%d" % (k % 4), cols[k % 4], 0.5), tilt, 0.008))
    o.append(cyl(c + tilt @ Vector((0.15, 0.32, -0.04)), c + tilt @ Vector((0.15, 0.32, -0.06)), 0.06, 0.06, badge, 14, smooth=False))
    for k in range(3):   # "..." on the badge
        o.append(box(c + tilt @ Vector((0.12 + k * 0.03, 0.32, -0.065)), (0.014, 0.014, 0.004), m("badge_dot", WHITE, 0.5), tilt, 0.0))
    # A fluffy yeti-fur case round the edges.
    for k in range(26):
        t = k / 26
        if t < 0.25:
            p = Vector((-0.21 + t / 0.25 * 0.42, 0.4, 0))
        elif t < 0.5:
            p = Vector((0.21, 0.4 - (t - 0.25) / 0.25 * 0.8, 0))
        elif t < 0.75:
            p = Vector((0.21 - (t - 0.5) / 0.25 * 0.42, -0.4, 0))
        else:
            p = Vector((-0.21, -0.4 + (t - 0.75) / 0.25 * 0.8, 0))
        o.append(sphere(c + tilt @ (p + Vector((0, 0, 0.02))), (0.055, 0.055, 0.045), fur, 8, 5))
    return o


def bottle():
    o = []
    glass = m("bottle_glass", (0.25, 0.6, 0.4), 0.1, 0.1)
    cork = m("cork", (0.75, 0.55, 0.35), 0.9)
    paper = m("scroll", (0.97, 0.92, 0.75), 0.8)
    prof = smooth_profile([(0, 0), (0.15, 0), (0.17, 0.05), (0.17, 0.4), (0.14, 0.48), (0.06, 0.58), (0.05, 0.72),
                           (0.055, 0.74), (0, 0.745)], 2)
    b = lathe(prof, glass, 18)
    transform(b, rot_z(math.pi / 2 - 0.25) @ rot_y(0.0), (0.35, 0.17, 0))   # lying down, neck raised a little
    o.append(b)
    ck = cyl((0, 0.7, 0), (0, 0.82, 0), 0.045, 0.05, cork, 10)
    transform(ck, rot_z(math.pi / 2 - 0.25), (0.35, 0.17, 0))
    o.append(ck)
    # The message, rolled up with a ribbon, poking out of the neck.
    sc = cyl((0, 0.55, 0), (0, 0.9, 0), 0.03, 0.03, paper, 10)
    transform(sc, rot_z(math.pi / 2 - 0.25) @ rot_x(0.05), (0.33, 0.2, 0.0))
    o.append(sc)
    o.append(torus((0, 0, 0), 0.034, 0.008, m("ribbon", (0.85, 0.2, 0.2), 0.6), 10, 4))
    transform(o[-1], rot_z(math.pi / 2 - 0.25) @ rot_x(0.0), (-0.42, 0.42, 0.0))
    # A bit of sand and a shell.
    o.append(sphere((0.0, 0.0, 0.0), (0.45, 0.06, 0.25), m("sand", (0.92, 0.82, 0.6), 0.95), 14, 6))
    o.append(sphere((-0.3, 0.06, -0.15), (0.06, 0.03, 0.05), m("shell", (1.0, 0.75, 0.7), 0.5), 8, 5))
    return o


def egg():
    o = []
    shell = m("egg_shell", (0.94, 0.9, 0.78), 0.6)
    spot = m("egg_spot", (0.45, 0.68, 0.38), 0.6)
    prof = smooth_profile([(0, 0), (0.18, 0.02), (0.27, 0.15), (0.29, 0.32), (0.25, 0.5), (0.16, 0.65), (0, 0.7)], 3)
    o.append(lathe(prof, shell, 24))
    for k in range(14):
        a = k * 2.4
        y = 0.08 + (k / 13) * 0.52
        r = 0.27 * math.sin(math.pi * y / 0.7) + 0.01
        o.append(sphere((math.cos(a) * r, y, math.sin(a) * r), (0.045, 0.04, 0.045), spot, 8, 5))
    # A crack across the front, and an eye looking out of it.
    pts = [(-0.18, 0.42), (-0.1, 0.38), (-0.05, 0.45), (0.02, 0.37), (0.09, 0.44), (0.16, 0.38)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        z0 = -math.sqrt(max(0.0, 0.29 ** 2 - x0 ** 2)) - 0.0
        z1 = -math.sqrt(max(0.0, 0.29 ** 2 - x1 ** 2)) - 0.0
        o.append(cyl((x0, y0, z0), (x1, y1, z1), 0.012, 0.012, m("crack", (0.15, 0.1, 0.08), 0.8), 4))
    o.append(sphere((0.0, 0.33, -0.27), (0.08, 0.05, 0.04), m("crack", (0.15, 0.1, 0.08), 0.8), 10, 6))
    o.append(sphere((0.0, 0.335, -0.298), (0.035, 0.03, 0.015), m("dino_eye", (1.0, 0.85, 0.2), 0.2, 0.0, (0.6, 0.45, 0.0)), 8, 5))
    o.append(sphere((0.0, 0.335, -0.312), (0.008, 0.025, 0.006), m("eye_black", INK, 0.2), 6, 4))
    # Bits of shell already fallen off.
    for k, (x, z) in enumerate([(0.3, -0.2), (-0.32, -0.12), (0.18, -0.33)]):
        o.append(box((x, 0.015, z), (0.08, 0.02, 0.06), shell, rot_y(k * 1.3), 0.01))
    return o


def main():
    reset()
    objs = []
    for i, fn in enumerate([mitten, pizza, mixtape, snowmobile, mammoth, helmet, caveman, fish, phone, bottle, egg]):
        objs.append(join(fn(), "Find%d" % i))
    export("finds", objs)


if __name__ == "__main__":
    main()
