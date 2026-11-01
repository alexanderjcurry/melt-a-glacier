"""People and animals: the villagers who come out when the village thaws, and
the sauna crew helper. Writes models/characters.glb with meshes:

    Grandma Grandpa Kid Woman Man Dog Cat Rooster   (stand on y = 0, face -Z)
    SaunaBody  SaunaLeg                             (the helper's rig parts)

The sauna crew's towel is in materials "towel" / "towel_stripe" and its skin
in "skin", so the game recolours them per crew member (Creatures.sauna).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403

INK = (0.12, 0.08, 0.07)
SKIN = (0.98, 0.8, 0.68)
WHITE = (0.97, 0.96, 0.93)


def m(name, rgb, rough=0.8, metal=0.0, emit=None):
    return mat(name, rgb, rough, metal, emit)


def face(o, y, r, skin, closed=False, z_scale=1.0):
    """Eyes, cheeks and a nose on a head of radius r centred at height y."""
    front = -r * 0.93 * z_scale
    eye = m("eye", INK, 0.3)
    for s in (-1, 1):
        if closed:
            o.append(box((0.38 * r * s, y + 0.05 * r, front - 0.005), (0.22 * r, 0.05 * r, 0.04 * r), eye, rot_z(0.3 * s), 0.0))
        else:
            o.append(sphere((0.36 * r * s, y + 0.08 * r, front + 0.02 * r), (0.11 * r, 0.14 * r, 0.06 * r), eye, 8, 6))
            o.append(sphere((0.33 * r * s, y + 0.13 * r, front - 0.025 * r), (0.035 * r, 0.035 * r, 0.02 * r), m("shine", WHITE, 0.2), 6, 4))
        o.append(sphere((0.58 * r * s, y - 0.2 * r, front + 0.15 * r), (0.15 * r, 0.09 * r, 0.05 * r), m("blush", (1.0, 0.6, 0.6), 0.8), 8, 5))
    o.append(sphere((0, y - 0.08 * r, front - 0.03 * r), (0.12 * r, 0.11 * r, 0.1 * r), skin, 8, 5))
    o.append(box((0, y - 0.38 * r, front + 0.05 * r), (0.28 * r, 0.05 * r, 0.04 * r), m("mouth", (0.55, 0.22, 0.2), 0.6),
                 rot_x(0.2), 0.0))


def person(o, h, skin, shirt, legs, shoes, skirt=None, arm_up=0.0, head_r=None):
    """A chibi body of total height h (without hair). Returns the head centre and radius."""
    sk = m("skin_%s" % str(skin), skin, 0.7)
    hr = head_r or h * 0.19
    leg_h = h * 0.3
    torso_top = h - hr * 1.9
    for s in (-1, 1):
        o.append(cyl((0.07 * s * h, leg_h, 0), (0.07 * s * h, 0.06, 0), 0.055 * h, 0.05 * h, legs, 10))
        o.append(sphere((0.07 * s * h, 0.045, -0.03 * h), (0.06 * h, 0.045, 0.1 * h), shoes, 10, 6))
    if skirt is not None:
        o.append(lathe([(0.0, leg_h * 0.35), (0.2 * h, leg_h * 0.35), (0.15 * h, torso_top * 0.75), (0.0, torso_top * 0.75)],
                       skirt, 16))
    o.append(lathe(smooth_profile([(0.0, leg_h - 0.02), (0.14 * h, leg_h), (0.16 * h, (leg_h + torso_top) * 0.5),
                                   (0.13 * h, torso_top), (0.0, torso_top + 0.03)], 2), shirt, 16))
    # Arms: the right one can be raised to wave (arm_up 0..1).
    for s in (-1, 1):
        sh = Vector((0.15 * s * h, torso_top - 0.04 * h, 0))
        up = arm_up if s > 0 else 0.0
        hand = sh + Vector((0.08 * s * h + 0.1 * s * h * up, -0.3 * h * (1 - up) + 0.32 * h * up, -0.04 * h))
        o.append(cyl(sh, hand, 0.045 * h, 0.04 * h, shirt, 8))
        o.append(sphere(hand, (0.045 * h, 0.045 * h, 0.045 * h), sk, 8, 5))
    hy = torso_top + hr * 0.95
    o.append(sphere((0, hy, 0), (hr, hr * 0.97, hr * 0.95), sk, 18, 12))
    for s in (-1, 1):
        o.append(sphere((hr * 0.98 * s, hy, 0.0), (hr * 0.15, hr * 0.22, hr * 0.12), sk, 8, 5))   # ears
    return hy, hr, sk


def grandma():
    o = []
    hy, hr, sk = person(o, 1.0, SKIN, m("cardigan", (0.6, 0.38, 0.62)), m("stocking", (0.85, 0.82, 0.78)),
                        m("shoe_black", (0.15, 0.13, 0.13), 0.5), skirt=m("skirt_navy", (0.25, 0.3, 0.48)))
    face(o, hy, hr, sk)
    hair = m("hair_grey", (0.82, 0.82, 0.85), 0.9)
    o.append(sphere((0, hy + hr * 0.25, hr * 0.12), (hr * 1.04, hr * 0.8, hr * 0.95), hair, 14, 8))
    o.append(sphere((0, hy + hr * 0.9, hr * 0.35), (hr * 0.45, hr * 0.4, hr * 0.4), hair, 10, 6))   # bun
    # Round glasses.
    for s in (-1, 1):
        g = torus((0, 0, 0), hr * 0.2, hr * 0.03, m("glasses", (0.75, 0.6, 0.25), 0.3, 0.8), 14, 4)
        transform(g, rot_x(math.pi / 2), (hr * 0.36 * s, hy + hr * 0.08, -hr * 0.97))
        o.append(g)
    # A shawl and a basket.
    o.append(lathe([(0.0, 0.0), (0.2, 0.0), (0.13, 0.1), (0.0, 0.1)], m("shawl", (0.85, 0.3, 0.3)), 16, center=(0, 0.6, 0)))
    o.append(lathe([(0.0, 0.0), (0.08, 0.0), (0.1, 0.09), (0.09, 0.09), (0.0, 0.01)], m("wicker", (0.75, 0.55, 0.3)), 12,
                   center=(-0.24, 0.32, -0.06), smooth=False))
    o.append(sphere((-0.24, 0.42, -0.06), (0.06, 0.04, 0.06), m("apple", (0.85, 0.15, 0.15), 0.4), 8, 5))
    return o


def grandpa():
    o = []
    hy, hr, sk = person(o, 1.05, SKIN, m("shirt_white", WHITE), m("lederhosen", (0.45, 0.3, 0.18)),
                        m("shoe_brown", (0.35, 0.22, 0.13), 0.6))
    face(o, hy, hr, sk)
    white = m("hair_white", (0.95, 0.95, 0.95), 0.9)
    for s in (-1, 1):
        o.append(sphere((hr * 0.8 * s, hy - hr * 0.05, hr * 0.15), (hr * 0.3, hr * 0.35, hr * 0.5), white, 8, 6))
        o.append(sphere((hr * 0.18 * s, hy - hr * 0.25, -hr * 0.98), (hr * 0.25, hr * 0.12, hr * 0.1), white, 8, 5,
                        basis=rot_z(-0.35 * s)))   # moustache
        o.append(box((0.09 * s, 0.6, -0.12), (0.035, 0.32, 0.02), m("lederhosen", (0.45, 0.3, 0.18)), None, 0.005))   # braces
    o.append(box((0, 0.66, -0.135), (0.2, 0.04, 0.02), m("lederhosen", (0.45, 0.3, 0.18)), None, 0.005))
    o.append(lathe([(0.0, 0.0), (0.18, 0.0), (0.21, 0.06), (0.0, 0.06)], m("lederhosen", (0.45, 0.3, 0.18)), 16, center=(0, 0.3, 0)))
    # Alpine hat with a feather.
    felt = m("felt_green", (0.25, 0.42, 0.3), 0.9)
    o.append(cyl((0, hy + hr * 0.62, 0), (0, hy + hr * 0.68, 0), hr * 1.35, hr * 1.35, felt, 18))
    o.append(lathe([(hr * 0.75, 0.0), (hr * 0.7, hr * 0.55), (hr * 0.4, hr * 0.75), (0.0, hr * 0.78)], felt, 16,
                   center=(0, hy + hr * 0.65, 0)))
    o.append(cyl((0, hy + hr * 0.68, 0), (0, hy + hr * 0.78, 0), hr * 0.76, hr * 0.74, m("hatband", (0.65, 0.2, 0.18)), 16))
    o.append(cyl((hr * 0.6, hy + hr * 0.8, hr * 0.3), (hr * 0.9, hy + hr * 1.5, hr * 0.5), 0.012, 0.004, m("feather", (0.9, 0.9, 0.85)), 6))
    # A walking stick.
    o.append(cyl((0.24, 0.0, -0.1), (0.24, 0.62, -0.07), 0.018, 0.018, m("stick", (0.5, 0.33, 0.2)), 6))
    return o


def kid():
    o = []
    hy, hr, sk = person(o, 0.78, (0.92, 0.72, 0.56), m("jacket_yellow", (1.0, 0.78, 0.2)), m("pants_blue", (0.3, 0.45, 0.75)),
                        m("boot_red", (0.8, 0.2, 0.18), 0.5), arm_up=1.0, head_r=0.18)
    face(o, hy, hr, sk)
    o.append(sphere((0, hy + hr * 0.35, hr * 0.05), (hr * 1.04, hr * 0.75, hr * 1.02), m("beanie", (0.85, 0.25, 0.3)), 14, 8))
    o.append(torus((0, hy + hr * 0.12, hr * 0.05), hr * 0.98, hr * 0.12, m("beanie_rim", WHITE), 18, 6))
    o.append(sphere((0, hy + hr * 1.12, hr * 0.05), (hr * 0.25, hr * 0.25, hr * 0.25), m("beanie_rim", WHITE), 8, 6))
    o.append(torus((0, 0.47, 0), 0.11, 0.035, m("scarf_green", (0.3, 0.7, 0.4)), 14, 6))
    return o


def woman():
    o = []
    hy, hr, sk = person(o, 1.0, (0.86, 0.62, 0.47), m("blouse", WHITE), m("stocking", (0.85, 0.82, 0.78)),
                        m("shoe_black", (0.15, 0.13, 0.13), 0.5), skirt=m("dirndl_blue", (0.25, 0.45, 0.75)))
    face(o, hy, hr, sk)
    o.append(lathe([(0.0, 0.0), (0.155, 0.0), (0.135, 0.22), (0.0, 0.22)], m("bodice", (0.75, 0.2, 0.25)), 16, center=(0, 0.44, 0)))
    o.append(box((0, 0.3, -0.15), (0.2, 0.36, 0.02), m("apron", (0.98, 0.95, 0.88)), rot_x(0.15), 0.01))
    hair = m("hair_blonde", (0.95, 0.78, 0.4), 0.9)
    o.append(sphere((0, hy + hr * 0.2, hr * 0.1), (hr * 1.05, hr * 0.85, hr * 0.97), hair, 14, 8))
    for s in (-1, 1):   # two braids
        for k in range(4):
            o.append(sphere((hr * 0.75 * s, hy - hr * 0.3 - k * hr * 0.32, hr * 0.15), (hr * 0.17, hr * 0.2, hr * 0.17), hair, 8, 5))
        o.append(sphere((hr * 0.75 * s, hy - hr * 1.6, hr * 0.15), (hr * 0.1, hr * 0.08, hr * 0.1), m("ribbon_red", (0.85, 0.2, 0.25)), 6, 4))
    for k in range(4):   # flowers in her hair
        a = -0.6 + k * 0.4
        o.append(sphere((math.sin(a) * hr * 1.0, hy + hr * 0.75, -math.cos(a) * hr * 0.5), (hr * 0.1, hr * 0.1, hr * 0.1),
                        m("hair_flower%d" % (k % 2), [(1.0, 0.85, 0.3), (0.95, 0.45, 0.6)][k % 2]), 6, 4))
    return o


def man():
    o = []
    hy, hr, sk = person(o, 1.1, (0.95, 0.75, 0.62), m("shirt_check", (0.78, 0.22, 0.2)), m("trousers", (0.35, 0.3, 0.28)),
                        m("boot_brown", (0.35, 0.22, 0.13), 0.6))
    face(o, hy, hr, sk)
    hair = m("hair_brown", (0.4, 0.25, 0.15), 0.9)
    o.append(sphere((0, hy + hr * 0.35, hr * 0.12), (hr * 1.02, hr * 0.7, hr * 0.92), hair, 14, 8))
    o.append(sphere((0, hy - hr * 0.5, -hr * 0.45), (hr * 0.8, hr * 0.55, hr * 0.6), hair, 12, 8))   # beard
    o.append(box((0, hy - hr * 0.28, -hr * 0.97), (hr * 0.28, hr * 0.06, hr * 0.06), m("mouth", (0.55, 0.22, 0.2), 0.6), None, 0.0))
    for k in range(3):   # check lines on the shirt
        o.append(cyl((0, 0.42 + k * 0.1, 0), (0, 0.43 + k * 0.1, 0), 0.177, 0.176, m("check_dark", (0.5, 0.12, 0.12)), 16))
    # A mug of hot chocolate.
    o.append(cyl((-0.27, 0.36, -0.08), (-0.27, 0.48, -0.08), 0.05, 0.05, m("mug", (0.25, 0.5, 0.85), 0.4), 12))
    o.append(cyl((-0.27, 0.47, -0.08), (-0.27, 0.485, -0.08), 0.043, 0.043, m("cocoa", (0.4, 0.22, 0.12), 0.3), 12))
    return o


def dog():
    o = []
    fur = m("dog_fur", (0.94, 0.85, 0.72), 0.9)
    brown = m("dog_brown", (0.62, 0.38, 0.2), 0.9)
    o.append(sphere((0, 0.32, 0.05), (0.17, 0.16, 0.26), fur, 14, 8))
    o.append(sphere((0.06, 0.38, 0.15), (0.1, 0.08, 0.1), brown, 8, 5))   # a patch
    for sx in (-1, 1):
        for sz in (-0.12, 0.2):
            o.append(cyl((sx * 0.09, 0.25, sz), (sx * 0.09, 0.03, sz), 0.05, 0.045, fur, 8))
            o.append(sphere((sx * 0.09, 0.03, sz - 0.03), (0.05, 0.03, 0.06), fur, 8, 4))
    o.append(sphere((0, 0.55, -0.2), (0.16, 0.15, 0.15), fur, 14, 8))
    o.append(sphere((0, 0.5, -0.33), (0.08, 0.065, 0.08), fur, 10, 6))   # muzzle
    o.append(sphere((0, 0.53, -0.41), (0.035, 0.03, 0.025), m("nose", INK, 0.3), 8, 5))
    o.append(box((0, 0.46, -0.39), (0.05, 0.015, 0.05), m("tongue", (0.95, 0.45, 0.5), 0.5), rot_x(0.6), 0.008))
    for s in (-1, 1):
        o.append(sphere((0.07 * s, 0.6, -0.33), (0.025, 0.03, 0.015), m("eye", INK, 0.3), 6, 4))
        o.append(sphere((0.15 * s, 0.53, -0.18), (0.05, 0.12, 0.07), brown, 8, 5, basis=rot_z(0.3 * s)))   # floppy ears
    o.append(cyl((0, 0.4, 0.3), (0, 0.55, 0.42), 0.03, 0.02, fur, 6))   # tail up
    o.append(torus((0, 0.43, -0.12), 0.1, 0.018, m("collar", (0.85, 0.2, 0.2), 0.5), 14, 4))
    return o


def cat():
    o = []
    fur = m("cat_fur", (0.95, 0.62, 0.3), 0.9)
    stripe = m("cat_stripe", (0.78, 0.42, 0.18), 0.9)
    white = m("cat_white", WHITE, 0.9)
    o.append(sphere((0, 0.2, 0.04), (0.15, 0.2, 0.15), fur, 14, 8))   # sitting
    o.append(sphere((0, 0.17, -0.06), (0.1, 0.14, 0.08), white, 10, 6))
    for k in range(3):
        o.append(torus((0, 0.18 + k * 0.08, 0.06), 0.13 - k * 0.012, 0.012, stripe, 14, 4))
    o.append(sphere((0, 0.47, -0.02), (0.14, 0.12, 0.12), fur, 14, 8))
    for s in (-1, 1):
        o.append(lathe([(0.0, 0.0), (0.05, 0.0), (0.0, 0.09)], fur, 4, center=(0.08 * s, 0.55, 0.0), smooth=False))
        o.append(sphere((0.05 * s, 0.49, -0.115), (0.025, 0.032, 0.012), m("cat_eye", (0.45, 0.75, 0.3), 0.2), 6, 4))
        o.append(sphere((0.05 * s, 0.49, -0.125), (0.007, 0.024, 0.006), m("eye", INK, 0.3), 4, 3))
        o.append(sphere((0.06 * s, 0.03, -0.1), (0.04, 0.03, 0.05), white, 6, 4))   # paws
        for k in (-1, 1):   # whiskers
            o.append(cyl((0.04 * s, 0.44, -0.12), (0.15 * s, 0.44 + 0.02 * k, -0.11), 0.002, 0.002, white, 3))
    o.append(sphere((0, 0.45, -0.13), (0.015, 0.012, 0.01), m("nose_pink", (0.95, 0.5, 0.55), 0.5), 6, 4))
    prev = Vector((0, 0.05, 0.17))
    for k in range(1, 7):   # tail curling round
        t = k / 6
        p = Vector((0.18 * math.sin(t * 2.2), 0.05 + 0.12 * t * t, 0.17 - 0.05 * t))
        o.append(cyl(prev, p, 0.03, 0.028, fur if k % 2 else stripe, 6))
        prev = p
    return o


def rooster():
    o = []
    white = m("feather_white", (0.97, 0.95, 0.9), 0.9)
    red = m("comb", (0.9, 0.18, 0.15), 0.6)
    yellow = m("beak_yellow", (1.0, 0.75, 0.2), 0.5)
    o.append(sphere((0, 0.3, 0.03), (0.13, 0.13, 0.18), white, 14, 8))
    o.append(sphere((0, 0.48, -0.1), (0.08, 0.09, 0.08), white, 12, 8))
    for k in range(3):
        o.append(sphere((0, 0.58 + k * 0.01, -0.13 + k * 0.05), (0.02, 0.04, 0.025), red, 6, 4))
    o.append(sphere((0, 0.42, -0.17), (0.02, 0.035, 0.015), red, 6, 4))   # wattle
    beak = lathe([(0.0, 0.0), (0.025, 0.0), (0.0, 0.06)], yellow, 6, smooth=False)
    transform(beak, rot_x(-math.pi / 2), (0, 0.47, -0.16))
    o.append(beak)
    for s in (-1, 1):
        o.append(sphere((0.045 * s, 0.5, -0.16), (0.012, 0.015, 0.01), m("eye", INK, 0.3), 6, 4))
        o.append(cyl((0.05 * s, 0.2, 0.03), (0.05 * s, 0.0, 0.02), 0.012, 0.012, yellow, 6))
        o.append(sphere((0.12 * s, 0.31, 0.04), (0.03, 0.08, 0.12), white, 8, 5))   # wings
    for k, c in enumerate([(0.15, 0.3, 0.25), (0.1, 0.1, 0.12), (0.2, 0.4, 0.3)]):
        a = -0.4 + k * 0.4
        o.append(sphere((math.sin(a) * 0.04, 0.42 + k * 0.02, 0.2 + k * 0.02), (0.03, 0.14, 0.05),
                        m("tail%d" % k, c, 0.5), 8, 5, basis=rot_x(-0.5 + k * 0.1) @ rot_z(a)))
    return o


def sauna_body():
    o = []
    towel = m("towel", (0.97, 0.97, 0.94), 0.95)
    stripe = m("towel_stripe", (0.75, 0.75, 0.72), 0.95)
    skin = m("skin", SKIN, 0.7)
    wood = m("bucket_wood", (0.6, 0.38, 0.2), 0.8)
    o.append(lathe(smooth_profile([(0.0, 0.3), (0.215, 0.3), (0.225, 0.5), (0.2, 0.75), (0.19, 0.82), (0.0, 0.83)], 2), towel, 18))
    for y in (0.42, 0.7):
        o.append(cyl((0, y, 0), (0, y + 0.04, 0), 0.228 - (y - 0.42) * 0.1, 0.227 - (y - 0.42) * 0.1, stripe, 18, smooth=False))
    o.append(box((0.12, 0.6, -0.2), (0.08, 0.14, 0.04), towel, rot_z(0.3), 0.02))   # the tuck
    o.append(sphere((0, 0.84, 0), (0.21, 0.11, 0.15), skin, 14, 8))
    o.append(cyl((0, 0.86, 0), (0, 0.96, 0), 0.06, 0.06, skin, 8))
    o.append(sphere((0, 1.04, 0), (0.135, 0.135, 0.13), skin, 16, 10))
    face(o, 1.04, 0.135, skin, closed=True)
    for s in (-1, 1):
        o.append(cyl((0.19 * s, 0.85, 0.0), (0.16 * s, 0.7, -0.17), 0.048, 0.042, skin, 8))
        o.append(cyl((0.16 * s, 0.7, -0.17), (0.12 * s, 0.68, -0.25), 0.042, 0.04, skin, 8))
        o.append(sphere((0.12 * s, 0.68, -0.26), (0.045, 0.045, 0.045), skin, 8, 5))
    # Towel turban with a knot, a few beads of sweat.
    o.append(sphere((0, 1.14, 0.01), (0.16, 0.1, 0.16), towel, 14, 8))
    o.append(torus((0, 1.12, 0.01), 0.14, 0.03, stripe, 16, 5))
    o.append(sphere((0, 1.22, -0.06), (0.06, 0.05, 0.05), towel, 8, 5))
    o.append(sphere((0.09, 1.08, -0.11), (0.012, 0.018, 0.01), m("sweat", (0.7, 0.88, 1.0), 0.1), 6, 4))
    # Wooden bucket of glowing stones, with a ladle.
    o.append(lathe([(0.0, 0.56), (0.11, 0.56), (0.125, 0.7), (0.115, 0.7), (0.0, 0.69)], wood, 12, center=(0, 0, -0.27), smooth=False))
    for y in (0.59, 0.67):
        o.append(cyl((0, y, -0.27), (0, y + 0.018, -0.27), 0.12 + (y - 0.56) * 0.1, 0.12 + (y - 0.56) * 0.1,
                     m("iron", (0.3, 0.3, 0.32), 0.5, 0.5), 12, smooth=False))
    hot = m("stone_hot", (1.0, 0.45, 0.12), 0.4, 0.0, (1.0, 0.35, 0.05))
    for x, z in ((-0.03, -0.25), (0.04, -0.29), (0.0, -0.31)):
        o.append(sphere((x, 0.705, z), (0.045, 0.028, 0.045), hot, 8, 5))
    o.append(cyl((0.08, 0.68, -0.22), (0.16, 0.85, -0.2), 0.01, 0.01, wood, 5))
    return o


def sauna_leg():
    skin = m("skin", SKIN, 0.7)
    return [cyl((0, 0.04, 0), (0, 0.36, 0), 0.05, 0.058, skin, 10),
            sphere((0, 0.03, -0.035), (0.05, 0.03, 0.085), skin, 8, 5)]


def main():
    reset()
    objs = []
    for name, fn in [("Grandma", grandma), ("Grandpa", grandpa), ("Kid", kid), ("Woman", woman), ("Man", man),
                     ("Dog", dog), ("Cat", cat), ("Rooster", rooster), ("SaunaBody", sauna_body), ("SaunaLeg", sauna_leg)]:
        objs.append(join(fn(), name))
    export("characters", objs)


if __name__ == "__main__":
    main()
