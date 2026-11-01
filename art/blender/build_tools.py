"""The six heat tools, held in your hand and hung on the shed's tool wall.
Writes models/tools.glb: Tool0 (hair dryer) .. Tool5 (orbital mirror remote).

Same frame as the old code models: the business end points along -Z, about
0.25 m in front of the origin, with the grip below the origin. Parts in the
material "body" are recoloured in the game to the tool's colour
(Balance.TOOLS[i].color), or gold for the golden hair dryer.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403

BODY = (0.8, 0.8, 0.8)
DARK = (0.14, 0.14, 0.17)
STEEL = (0.72, 0.73, 0.77)
BRASS = (0.88, 0.68, 0.3)
WHITE = (0.95, 0.94, 0.9)
RED = (0.86, 0.15, 0.11)


def body():
    return mat("body", BODY, 0.4)


def m(name, rgb, rough=0.5, metal=0.0, emit=None):
    return mat(name, rgb, rough, metal, emit)


def along_z(prof, z0, material, segs=16, y=0.0, x=0.0, smooth=True):
    """A lathe along -Z: prof is [(radius, distance forward from z0)]."""
    ob = lathe(prof, material, segs, smooth=smooth)
    transform(ob, rot_x(-math.pi / 2), (x, y, z0))
    return ob


def hair_dryer():
    o = []
    b = body()
    dark = m("dark", DARK, 0.5)
    # Barrel: rounded back, a waist, then the nozzle.
    o.append(along_z(smooth_profile([(0.0, 0.0), (0.045, 0.004), (0.062, 0.03), (0.064, 0.09), (0.058, 0.2),
                                     (0.052, 0.24), (0.0, 0.241)], 2), 0.12, b, 20))
    o.append(along_z([(0.0, 0.0), (0.047, 0.0), (0.047, 0.01), (0.0, 0.011)], 0.128, dark, 18, smooth=False))
    for k in range(4):   # air intake rings on the back
        o.append(along_z([(0.04 - k * 0.009, 0.0), (0.04 - k * 0.009, 0.004), (0.035 - k * 0.009, 0.004),
                          (0.035 - k * 0.009, 0.0)], 0.131, m("grille", (0.35, 0.35, 0.4), 0.4), 18, smooth=False))
    o.append(along_z([(0.0645, 0.0), (0.0645, 0.016), (0.0, 0.017)], -0.02, m("trim", WHITE, 0.3), 20, smooth=False))
    o.append(along_z([(0.044, 0.0), (0.04, 0.09), (0.036, 0.1), (0.03, 0.1), (0.0, 0.09)], -0.15, dark, 18))
    o.append(along_z([(0.037, 0.0), (0.037, 0.012), (0.0, 0.0125)], -0.245, m("nozzle_ring", (0.32, 0.32, 0.36), 0.4), 18,
                     smooth=False))
    # Handle, with a white switch and a curly cable.
    o.append(cyl((0, -0.02, 0.035), (0, -0.2, 0.085), 0.032, 0.027, b, 14))
    o.append(sphere((0, -0.2, 0.085), (0.028, 0.02, 0.028), b, 12, 6))
    o.append(box((0, -0.075, 0.008), (0.024, 0.045, 0.016), m("trim", WHITE, 0.3), rot_x(0.26), 0.006))
    prev = Vector((0, -0.21, 0.09))
    for k in range(1, 13):
        t = k / 12
        p = Vector((0.012 * math.cos(t * 18), -0.21 - 0.09 * t, 0.09 + 0.04 * t + 0.012 * math.sin(t * 18)))
        o.append(cyl(prev, p, 0.006, 0.006, dark, 5))
        prev = p
    return o


def heat_lamp():
    o = []
    b = body()
    dark = m("dark", DARK, 0.5)
    steel = m("steel", STEEL, 0.25, 0.9)
    o.append(along_z([(0.045, 0.0), (0.13, 0.17), (0.138, 0.18), (0.13, 0.19), (0.04, 0.02)], 0.03, b, 22, smooth=False))
    o.append(along_z([(0.04, 0.0), (0.125, 0.17), (0.0, 0.17)], 0.025, steel, 22))   # shiny inside
    o.append(sphere((0, 0, -0.12), (0.075, 0.075, 0.07), m("bulb", (1.0, 0.55, 0.22), 0.3, 0.0, (1.0, 0.45, 0.1)), 16, 10))
    o.append(sphere((0.025, 0.03, -0.17), (0.02, 0.016, 0.01), m("bulb_hot", (1.0, 0.9, 0.7), 0.2, 0.0, (1.0, 0.8, 0.5)), 6, 4))
    # Wire guard: rings and spokes.
    for r, z in ((0.13, -0.165), (0.08, -0.185)):
        g = torus((0, 0, 0), r, 0.005, steel, 22, 4, smooth=False)
        transform(g, rot_x(math.pi / 2), (0, 0, z))
        o.append(g)
    for k in range(6):
        t = math.tau * k / 6
        o.append(cyl((math.cos(t) * 0.13, math.sin(t) * 0.13, -0.165), (0, 0, -0.195), 0.004, 0.004, steel, 4))
    o.append(along_z([(0.034, 0.0), (0.034, 0.08), (0.0, 0.08)], 0.11, dark, 14))
    o.append(box((0, 0, 0.13), (0.08, 0.08, 0.05), b, None, 0.012))
    # A clamp handle.
    o.append(cyl((0, -0.03, 0.11), (0, -0.21, 0.13), 0.025, 0.023, dark, 12))
    o.append(box((0, -0.04, 0.11), (0.03, 0.05, 0.06), steel, None, 0.008))
    o.append(sphere((0.04, 0.0, 0.13), (0.02, 0.02, 0.02), m("knob", RED, 0.4), 8, 5))
    return o


def blowtorch():
    o = []
    b = body()
    brass = m("brass", BRASS, 0.3, 0.85)
    steel = m("steel", STEEL, 0.25, 0.9)
    # The gas canister (it's the grip), with a label.
    can = lathe(smooth_profile([(0.0, 0.0), (0.05, 0.0), (0.056, 0.012), (0.056, 0.17), (0.05, 0.2), (0.03, 0.215),
                                (0.0, 0.22)], 2), b, 20, center=(0, -0.265, 0.05))
    o.append(can)
    o.append(cyl((0, -0.18, 0.05), (0, -0.1, 0.05), 0.0575, 0.0575, m("label", WHITE, 0.6), 20))
    o.append(cyl((0, -0.16, 0.05), (0, -0.12, 0.05), 0.058, 0.058, m("label_stripe", (1.0, 0.6, 0.15), 0.6), 20))
    # Brass valve block with a red knob, then the burner tube.
    o.append(box((0, -0.01, 0.045), (0.05, 0.05, 0.07), brass, None, 0.01))
    o.append(cyl((0.025, -0.005, 0.05), (0.065, -0.005, 0.05), 0.012, 0.012, brass, 8))
    knob = cyl((0.065, -0.005, 0.05), (0.08, -0.005, 0.05), 0.025, 0.025, m("knob", RED, 0.4), 12)
    o.append(knob)
    o.append(cyl((0, 0.005, 0.02), (0, 0.005, -0.17), 0.013, 0.013, steel, 10))
    o.append(along_z([(0.018, 0.0), (0.024, 0.1), (0.02, 0.1), (0.0, 0.08)], -0.16, m("burner", (0.36, 0.36, 0.4), 0.4, 0.6), 14))
    for k in range(4):   # air holes
        t = k * math.pi / 2
        o.append(box((math.cos(t) * 0.021, 0.005 + math.sin(t) * 0.021, -0.2), (0.008, 0.008, 0.012), m("dark", DARK, 0.5),
                     None, 0.0))
    o.append(box((0, -0.035, -0.005), (0.016, 0.03, 0.02), m("dark", DARK, 0.5), None, 0.004))   # igniter
    return o


def flamethrower():
    o = []
    b = body()
    gun = m("gun", (0.3, 0.31, 0.34), 0.35, 0.6)
    dark = m("dark", DARK, 0.5)
    o.append(cyl((0, 0, 0.17), (0, 0, -0.27), 0.028, 0.028, gun, 12))
    o.append(cyl((0, 0, -0.03), (0, 0, -0.22), 0.046, 0.046, dark, 16))
    for k in range(6):   # cooling fins
        z = -0.04 - 0.032 * k
        o.append(cyl((0, 0, z), (0, 0, z - 0.01), 0.054, 0.054, m("fin", (0.45, 0.45, 0.48), 0.3, 0.7), 16, smooth=False))
    o.append(along_z([(0.032, 0.0), (0.04, 0.035), (0.0, 0.035)], -0.26, dark, 14))
    o.append(cyl((0, -0.045, -0.23), (0, -0.045, -0.29), 0.009, 0.009, m("pilot", (1.0, 0.55, 0.15), 0.4, 0.0, (1.0, 0.4, 0.1)), 8))
    # Fuel tank underneath, with a hazard stripe and a gauge.
    o.append(along_z(smooth_profile([(0.0, 0.0), (0.04, 0.005), (0.055, 0.03), (0.055, 0.18), (0.04, 0.205), (0.0, 0.21)], 2),
                     0.18, b, 18, y=-0.088))
    o.append(cyl((0, -0.088, 0.06), (0, -0.088, 0.09), 0.0565, 0.0565, m("hazard", (1.0, 0.85, 0.2), 0.5), 18))
    for k in range(4):
        o.append(box((math.cos(k * 1.6) * 0.057, -0.088 + math.sin(k * 1.6) * 0.057, 0.075), (0.012, 0.012, 0.031), dark,
                     rot_z(k * 1.6), 0.0))
    o.append(cyl((0.05, -0.075, 0.12), (0.066, -0.075, 0.12), 0.022, 0.022, m("gauge", WHITE, 0.3), 14))
    o.append(box((0.067, -0.072, 0.12), (0.002, 0.016, 0.004), m("knob", RED, 0.4), rot_x(0.5), 0.0))
    # Grips.
    o.append(box((0, -0.15, 0.2), (0.034, 0.12, 0.05), dark, rot_x(0.3), 0.01))
    o.append(box((0, -0.075, -0.12), (0.03, 0.1, 0.035), dark, rot_x(-0.1), 0.01))
    o.append(box((0, -0.06, 0.15), (0.012, 0.04, 0.03), gun, rot_x(0.4), 0.004))   # trigger
    return o


def lava_hose():
    o = []
    b = body()
    brass = m("brass", BRASS, 0.3, 0.85)
    brass_d = m("brass_dark", (0.68, 0.5, 0.22), 0.35, 0.85)
    o.append(along_z([(0.048, 0.0), (0.042, 0.03), (0.026, 0.22), (0.022, 0.24), (0.0, 0.24)], 0.0, brass, 18))
    o.append(along_z([(0.05, 0.0), (0.05, 0.035), (0.0, 0.036)], 0.0, brass_d, 18, smooth=False))
    o.append(along_z([(0.035, 0.0), (0.035, 0.015), (0.0, 0.016)], -0.16, brass_d, 16, smooth=False))
    o.append(sphere((0, 0, -0.243), (0.02, 0.02, 0.012), m("lava_glow", (1.0, 0.6, 0.12), 0.3, 0.0, (1.0, 0.45, 0.05)), 10, 6))
    # Lever and pistol grip.
    o.append(box((0, 0.05, -0.07), (0.016, 0.014, 0.1), m("lever", (0.8, 0.12, 0.08), 0.4), rot_x(0.2), 0.004))
    o.append(box((0, 0.035, -0.02), (0.02, 0.03, 0.02), brass_d, None, 0.004))
    o.append(box((0, -0.085, 0.0), (0.036, 0.12, 0.046), m("grip", (0.16, 0.13, 0.11), 0.7), rot_x(0.25), 0.01))
    # The hose: corrugated, curving back and down, glowing between the ribs.
    p0, p1, p2 = Vector((0, 0, 0.02)), Vector((0, 0, 0.24)), Vector((0, -0.28, 0.26))
    prev = p0
    for k in range(1, 13):
        t = k / 12
        p = p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
        o.append(cyl(prev, p, 0.026, 0.026, b, 12, smooth=True))
        o.append(sphere(p, (0.031, 0.031, 0.031), m("hose_rib", (0.3, 0.12, 0.08), 0.6), 12, 6))
        prev = p
    return o


def mirror_remote():
    o = []
    b = body()
    dark = m("dark", DARK, 0.5)
    steel = m("steel", STEEL, 0.25, 0.9)
    o.append(box((0, -0.02, 0.0), (0.09, 0.045, 0.22), b, None, 0.018))
    o.append(box((0, -0.035, 0.0), (0.094, 0.02, 0.224), m("remote_base", (0.4, 0.42, 0.48), 0.4), None, 0.008))
    o.append(box((0, 0.003, 0.05), (0.062, 0.004, 0.065), m("lcd", (0.1, 0.22, 0.38), 0.2, 0.0, (0.05, 0.12, 0.2)), None, 0.0))
    o.append(box((-0.012, 0.0055, 0.04), (0.02, 0.002, 0.02), m("lcd_dot", (0.4, 0.95, 0.6), 0.3, 0.0, (0.3, 0.9, 0.5)), None, 0.0))
    o.append(cyl((0, 0.0, -0.045), (0, 0.016, -0.045), 0.019, 0.019, m("button_red", RED, 0.3), 14, smooth=False))
    for k, c in enumerate([(1.0, 0.85, 0.2), (0.3, 0.8, 0.35), (0.3, 0.55, 0.95)]):
        o.append(cyl((-0.026 + 0.026 * k, 0.0, -0.085), (-0.026 + 0.026 * k, 0.007, -0.085), 0.008, 0.008,
                     m("button%d" % k, c, 0.3), 8, smooth=False))
    o.append(cyl((0.032, 0.0, -0.09), (0.032, 0.13, -0.13), 0.004, 0.003, steel, 6))
    o.append(sphere((0.032, 0.13, -0.13), (0.009, 0.009, 0.009), m("button_red", RED, 0.3), 6, 4))
    # A tiny satellite dish, so you know what it talks to.
    o.append(cyl((0, 0.0, 0.085), (0, 0.03, 0.085), 0.008, 0.008, steel, 8))
    o.append(lathe([(0.012, 0.0), (0.06, 0.035), (0.055, 0.037), (0.0, 0.01)], m("dish", WHITE, 0.3), 18, center=(0, 0.025, 0.085)))
    o.append(cyl((0, 0.06, 0.085), (0, 0.1, 0.085), 0.004, 0.004, steel, 6))
    o.append(sphere((0, 0.1, 0.085), (0.01, 0.01, 0.01), dark, 6, 4))
    return o


def main():
    reset()
    objs = []
    for i, fn in enumerate([hair_dryer, heat_lamp, blowtorch, flamethrower, lava_hose, mirror_remote]):
        objs.append(join(fn(), "Tool%d" % i))
    export("tools", objs)


if __name__ == "__main__":
    main()
