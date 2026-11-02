"""Builds every sound effect and ambience loop in audio/sfx and audio/amb.

    python art/audio/make_sfx.py            # all of them
    python art/audio/make_sfx.py crack drip # just the ones whose names start with these

Each function returns a mono (n,) or stereo (n, 2) array. Names ending in
_1, _2... are variations of one sound that the game picks between at random.
Loops (tool sprays, sizzle, jetpack, wind...) are made seamless with make_loop.
"""
import os
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from synth import *  # noqa: E402,F401,F403
import synth as S  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOUNDS = {}   # name -> (function, kind) kind: "sfx" (mono, for 3D or 2D), "ui" (stereo), "loop", "amb"


def sound(name, kind="sfx", variants=1):
    def deco(fn):
        if variants == 1:
            SOUNDS[name] = (lambda: fn(0), kind)
        else:
            for v in range(variants):
                SOUNDS["%s_%d" % (name, v + 1)] = ((lambda v=v: fn(v)), kind)
        return fn
    return deco


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
        "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def hz(name):
    """'A4' -> 440.0"""
    n, o = name[:-1], int(name[-1])
    return midi(12 * (o + 1) + NOTE[n])


# =====================================================================================
# The six tools (seamless loops). Upgrades change their pitch and loudness in game.
# =====================================================================================
LOOP_LEN = 3.0


@sound("tool_loop_0", "loop")
def hair_dryer(_):
    d = LOOP_LEN + 0.4
    t = t_axis(d)
    # motor whine: a few harmonics of a slightly unsteady ~190 Hz hum
    f0 = 188 * (1 + 0.004 * smooth_random(d, 6, -1, 1))
    motor = sum(osc(f0 * k, d) * a for k, a in [(1, 0.5), (2, 0.35), (3, 0.25), (5, 0.12), (8, 0.05)])
    # fan blades chopping the air, and the air itself
    air = bp(noise(d), 700, 7000) * (1 + 0.12 * np.sin(2 * np.pi * 94 * t))
    air = air * (0.9 + 0.1 * smooth_random(d, 3))
    hiss = hp(noise(d), 5000) * 0.25
    x = motor * 0.22 + normalize(air, 1) * 0.55 + hiss * 0.3
    return rms_normalize(make_loop(lp(x, 9000), 0.4), -17)


@sound("tool_loop_1", "loop")
def heat_lamp(_):
    d = LOOP_LEN + 0.4
    hum = osc(100, d) * 0.5 + osc(200, d) * 0.3 + osc(300, d) * 0.12 + osc(400, d) * 0.06
    buzz = bp(osc(100, d, "square"), 1500, 4000) * 0.08
    warm = lp(brown(d), 500) * 0.35
    # the filament ticking as it heats
    ticks = np.zeros(secs(d))
    for _ in range(9):
        place(ticks, click(0.006, S.rng.uniform(2500, 5000), 8), S.rng.uniform(0, d - 0.1), S.rng.uniform(0.1, 0.35))
    x = hum * (0.85 + 0.15 * smooth_random(d, 2)) + buzz + warm + ticks
    return rms_normalize(make_loop(x, 0.4), -20)


@sound("tool_loop_2", "loop")
def blowtorch(_):
    d = LOOP_LEN + 0.4
    flutter = 0.8 + 0.2 * smooth_random(d, 14)
    jet = bp(noise(d), 1400, 9000) * flutter
    roar = lp(noise(d), 380) * (0.7 + 0.3 * smooth_random(d, 9)) * 2.2
    whistle = osc(2900 * (1 + 0.01 * smooth_random(d, 3, -1, 1)), d) * 0.02
    x = jet * 0.5 + roar + whistle
    return rms_normalize(make_loop(x, 0.4), -16)


@sound("tool_loop_3", "loop")
def flamethrower(_):
    d = LOOP_LEN + 0.4
    turb = 0.55 + 0.45 * smooth_random(d, 7) ** 1.5
    roar = lp(brown(d), 700) * turb
    body = bp(noise(d), 200, 1800) * (0.6 + 0.4 * smooth_random(d, 11)) * 0.5
    crackle = np.zeros(secs(d))
    for _ in range(int(d * 26)):
        place(crackle, click(0.004, S.rng.uniform(1500, 6000), 3), S.rng.uniform(0, d - 0.05), S.rng.uniform(0.2, 1.0))
    x = roar * 1.4 + body + crackle * 0.35
    return rms_normalize(make_loop(hp(lp(x, 8000), 30), 0.4), -15)


@sound("tool_loop_4", "loop")
def lava_hose(_):
    d = LOOP_LEN + 0.4
    rumble = lp(brown(d), 160) * 1.3
    flow = bp(noise(d), 120, 900) * (0.6 + 0.4 * smooth_random(d, 4)) * 0.6
    bubbles = np.zeros(secs(d))
    for _ in range(int(d * 14)):
        dur = S.rng.uniform(0.05, 0.14)
        f0 = S.rng.uniform(70, 160)
        b = osc(glide(f0, f0 * S.rng.uniform(1.8, 2.6), dur), dur) * env_exp(dur, dur * 0.35, 0.004)
        place(bubbles, b, S.rng.uniform(0, d - 0.15), S.rng.uniform(0.3, 0.9))
    sizzle = hp(noise(d), 4000) * (0.2 + 0.25 * smooth_random(d, 5))
    x = rumble + flow + bubbles * 0.8 + sizzle * 0.25
    return rms_normalize(make_loop(hp(x, 30), 0.4), -15)


@sound("tool_loop_5", "loop")
def orbital_mirror(_):
    # A column of sunlight from space: a shimmering chord with a slow pulse.
    d = 4.0   # every frequency is a multiple of 0.25 Hz, so this loops exactly
    t = t_axis(d)
    out = np.zeros(len(t))
    for f, a in [(110.0, 0.5), (110.25, 0.35), (165.0, 0.3), (220.0, 0.32), (277.25, 0.18), (330.0, 0.2),
                 (440.0, 0.12), (659.25, 0.08), (880.5, 0.06), (1318.5, 0.04), (1760.25, 0.03)]:
        out += a * np.sin(2 * np.pi * f * t + S.rng.uniform(0, 6.28))
    out *= 0.75 + 0.25 * np.sin(2 * np.pi * 0.5 * t)
    air = hp(noise(d), 6000)
    air = air * (0.5 + 0.5 * np.sin(2 * np.pi * 1.0 * t) ** 2) * 0.08
    sub = np.sin(2 * np.pi * 55 * t) * 0.25
    x = out + sub
    loop_air = make_loop(np.concatenate([air, air[:secs(0.3)]]), 0.3)
    x = x + loop_air[:len(x)]
    return rms_normalize(x, -18)


# Switching each tool on.
@sound("tool_on_0")
def dryer_on(_):
    c = click(0.012, 2200, 4) * 0.8
    spin = osc(glide(60, 188, 0.35), 0.35) * env_adsr(0.35, 0.05, 0.1, 0.8, 0.1) * 0.3
    return rms_normalize(mix(c, spin), -16)


@sound("tool_on_1")
def lamp_on(_):
    c = click(0.02, 1200, 3) * 1.0
    clunk = peak(noise(0.08) * env_exp(0.08, 0.015), 420, 5) * 0.6
    hum = osc(100, 0.3) * env_adsr(0.3, 0.12, 0.05, 0.6, 0.15) * 0.2
    return rms_normalize(mix(c, clunk, hum), -16)


@sound("tool_on_2")
def torch_on(_):
    d = 0.4
    pop = lp(noise(d), 1800) * env_exp(d, 0.06, 0.002)
    hiss = bp(noise(d), 1500, 8000) * env_adsr(d, 0.02, 0.1, 0.5, 0.2) * 0.5
    return rms_normalize(mix(pop, hiss), -15)


@sound("tool_on_3")
def flame_on(_):
    d = 0.6
    whoomph = sweep(brown(d) * 2, lambda u: 2000 * (1 - u) ** 2 + 150, "lp") * env_adsr(d, 0.02, 0.2, 0.4, 0.3)
    thump = osc(glide(110, 45, 0.25), 0.25) * env_exp(0.25, 0.08)
    return rms_normalize(mix(whoomph, thump * 0.6), -13)


@sound("tool_on_4")
def lava_on(_):
    d = 0.5
    glop = osc(glide(60, 240, 0.18), 0.18) * env_exp(0.18, 0.06, 0.005)
    glop2 = osc(glide(80, 300, 0.14), 0.14) * env_exp(0.14, 0.05, 0.005)
    rush = lp(noise(d), 600) * env_adsr(d, 0.08, 0.1, 0.5, 0.3) * 0.5
    x = np.zeros(secs(d))
    place(x, glop, 0.0)
    place(x, glop2, 0.12, 0.8)
    return rms_normalize(mix(x, rush), -14)


@sound("tool_on_5")
def mirror_on(_):
    d = 1.6
    out = np.zeros(secs(d))
    for i, n in enumerate(["A5", "E6", "A6", "C#7"]):
        place(out, bell(hz(n), 1.2, decay=0.6), i * 0.05, 0.4)
    swell = lp(noise(d), 3000) * env_adsr(d, 0.4, 0.3, 0.2, 0.8) * 0.15
    return rms_normalize(reverb(mix(out, swell), 0.35, 1.6), -17)


# =====================================================================================
# Ice
# =====================================================================================
@sound("sizzle_loop", "loop")
def sizzle(_):
    # Steam hissing where the heat lands, with tiny pops.
    d = 2.4
    steam = hp(noise(d), 2500) * (0.5 + 0.5 * smooth_random(d, 8)) * 0.6
    pops = np.zeros(secs(d))
    for _ in range(int(d * 60)):
        place(pops, click(0.003, S.rng.uniform(3000, 9000), 4), S.rng.uniform(0, d - 0.02), S.rng.uniform(0.1, 1.0))
    trickle = np.zeros(secs(d))
    for _ in range(int(d * 5)):
        f = S.rng.uniform(900, 2200)
        place(trickle, drop(f, f * 1.6, 0.05, 0.015), S.rng.uniform(0, d - 0.1), S.rng.uniform(0.1, 0.3))
    x = steam + pops * 0.5 + trickle
    return rms_normalize(make_loop(x, 0.3), -20)


@sound("crack", variants=5)
def crack(v):
    # A sharp ice crack: a burst of micro-fractures and a couple of glassy rings.
    S.seed(100 + v)
    d = 0.5
    x = np.zeros(secs(d))
    n = S.rng.integers(5, 12)
    t = 0.0
    for i in range(n):
        g = np.exp(-i * 0.35) * S.rng.uniform(0.5, 1.0)
        place(x, click(0.006, S.rng.uniform(1500, 6000), 2), t, g)
        t += S.rng.exponential(0.008)
    rings = np.zeros(secs(d))
    for _ in range(2):
        f = S.rng.uniform(1800, 4200)
        place(rings, bell(f, 0.35, partials=((1, 1, 1), (2.3, 0.4, 0.5)), decay=0.07), S.rng.uniform(0, 0.01), 0.15)
    thump = lp(noise(0.08), 300) * env_exp(0.08, 0.02) * 0.6
    return trim_tail(rms_normalize(mix(x, rings, thump), -16))


@sound("lake_crack", variants=3)
def lake_crack(v):
    # Thick lake ice "sings" when it cracks: a laser-like zing that falls in pitch.
    S.seed(150 + v)
    d = 0.9
    f = glide(S.rng.uniform(4500, 6500), S.rng.uniform(500, 900), 0.35)
    zing = osc(np.concatenate([f, np.full(secs(d) - len(f), f[-1])]), d) * env_exp(d, 0.12, 0.001)
    # dispersion smear: a few echoes of the zing
    out = np.zeros(secs(d))
    for k, (dl, g) in enumerate([(0, 1), (0.03, 0.5), (0.07, 0.3)]):
        place(out, zing, dl, g)
    out = bp(out, 300, 8000) * 0.5
    snap = click(0.01, 2500, 2)
    return trim_tail(rms_normalize(reverb(mix(out, snap), 0.25, 1.8), -17))


@sound("drip", variants=6)
def drip(v):
    S.seed(200 + v)
    f0 = S.rng.uniform(500, 1100)
    d = 0.18
    x = drop(f0, f0 * S.rng.uniform(1.8, 2.6), d, S.rng.uniform(0.025, 0.045))
    x = mix(x, click(0.004, 4000, 2) * 0.2)
    return trim_tail(rms_normalize(x, -20))


@sound("chunk_break", variants=3)
def chunk_break(v):
    # A loose chunk breaks off: a deep crack, then crumbling bits.
    S.seed(300 + v)
    d = 1.4
    groan = sweep(brown(0.5), lambda u: 600 * (1 - u) + 120, "lp") * env_adsr(0.5, 0.01, 0.2, 0.5, 0.25) * 1.3
    x = np.zeros(secs(d))
    place(x, groan, 0)
    for i in range(14):
        place(x, click(0.008, S.rng.uniform(800, 4000), 2), S.rng.uniform(0, 0.12), S.rng.uniform(0.3, 1.0))
    for i in range(24):
        t = 0.15 + S.rng.exponential(0.25)
        if t < d - 0.05:
            place(x, click(0.005, S.rng.uniform(1500, 6000), 3), t, S.rng.uniform(0.05, 0.3) * np.exp(-t * 1.5))
    thud = osc(glide(90, 40, 0.3), 0.3) * env_exp(0.3, 0.1) * 0.8
    place(x, thud, 0.02)
    return trim_tail(rms_normalize(x, -15))


@sound("slush_collapse", "ui")
def slush_collapse(_):
    # The last of a glacier collapses into slush: a long crumble and a wet whoosh.
    S.seed(400)
    d = 3.5
    whoosh = sweep(brown(d) * 1.5, lambda u: 2500 * np.exp(-3 * u) + 200, "lp") * env_adsr(d, 0.05, 0.6, 0.5, 2.0)
    slosh = bp(noise(d), 300, 2000) * smooth_random(d, 6) ** 2 * env_adsr(d, 0.3, 0.5, 0.6, 1.8) * 0.5
    x = np.zeros(secs(d))
    for i in range(70):
        t = S.rng.exponential(0.7)
        if t < d - 0.1:
            place(x, click(0.006, S.rng.uniform(700, 4000), 2), t, S.rng.uniform(0.1, 0.6) * np.exp(-t * 0.8))
    for i in range(16):
        f = S.rng.uniform(400, 1300)
        place(x, drop(f, f * 2, 0.12, 0.04), S.rng.uniform(0.5, d - 0.2), 0.25)
    thud = osc(glide(70, 30, 0.6), 0.6) * env_exp(0.6, 0.2)
    return trim_tail(rms_normalize(reverb(mix(whoosh, slosh, x, thud), 0.3, 2.2), -14))


# =====================================================================================
# Finds breaking free, by rarity
# =====================================================================================
@sound("find_shatter")
def find_shatter(_):
    S.seed(500)
    d = 1.4
    x = np.zeros(secs(d))
    for i in range(40):
        t = S.rng.exponential(0.12)
        f = S.rng.uniform(2000, 7500)
        if t < d - 0.4:
            place(x, bell(f, 0.4, partials=((1, 1, 1), (1.7, 0.3, 0.5)), decay=0.09), t, S.rng.uniform(0.1, 0.5) * np.exp(-t * 2))
    burst = hp(noise(0.3), 1500) * env_exp(0.3, 0.05) * 0.6
    thump = osc(glide(140, 60, 0.2), 0.2) * env_exp(0.2, 0.06) * 0.5
    return trim_tail(rms_normalize(mix(x, burst, thump), -15))


RARITY_PHRASES = [
    ["G5", "C6"],
    ["E5", "G5", "C6"],
    ["C5", "E5", "G5", "C6", "E6"],
    ["C5", "E5", "G5", "B5", "D6", "G6"],
    ["C5", "G5", "C6", "E6", "G6", "C7", "E7"],
]


@sound("find_jingle", "ui", variants=5)
def find_jingle(rarity):
    # A little music-box fanfare: longer and brighter the rarer the find.
    S.seed(600 + rarity)
    notes = RARITY_PHRASES[rarity]
    step = [0.11, 0.1, 0.09, 0.085, 0.08][rarity]
    d = 1.2 + 0.55 * rarity
    out = np.zeros(secs(d))
    for i, n in enumerate(notes):
        f = hz(n)
        tone = bell(f, 1.6, partials=((1, 1, 1), (3.0, 0.25, 0.25), (6.2, 0.08, 0.1)), decay=0.5 + 0.1 * rarity)
        place(out, tone, i * step, 0.55 + 0.05 * i)
    if rarity >= 2:
        # a chord under the last note
        root = {2: ["C4", "G4", "E5"], 3: ["G3", "D4", "B4", "G5"], 4: ["C3", "G3", "E4", "C5", "G5"]}[rarity]
        for n in root:
            place(out, fm_tone(hz(n), d - len(notes) * step, 2.0, 1.2, 0.3, 0.9), len(notes) * step, 0.18)
    if rarity >= 3:
        # sparkle that drifts up
        for k in range(14 + 8 * (rarity - 3)):
            t = len(notes) * step + S.rng.uniform(0, 1.0)
            place(out, bell(S.rng.uniform(3000, 8000), 0.3, partials=((1, 1, 1),), decay=0.08), t, 0.08)
    if rarity >= 4:
        # a soft choir-like swell
        dur = d - 0.2
        pad = np.zeros(secs(dur))
        for n in ["C4", "G4", "C5", "E5"]:
            for det in (-0.25, 0.25):
                pad += osc(hz(n) * 2 ** (det / 12), dur, "saw")
        pad = lp(pad, 2200) * env_adsr(dur, 0.6, 0.2, 0.8, 1.0) * 0.05
        place(out, pad, 0.2)
    return trim_tail(rms_normalize(reverb(out, 0.3, 2.0), -15 - (0 if rarity >= 2 else 2)))


@sound("find_hint", "ui")
def find_hint(_):
    # "Something's frozen in here": a soft, curious shimmer.
    S.seed(650)
    out = np.zeros(secs(1.6))
    for i, n in enumerate(["E6", "B6", "G#6"]):
        place(out, bell(hz(n), 1.0, partials=((1, 1, 1), (2.01, 0.2, 0.4)), decay=0.35), i * 0.13, 0.4)
    return trim_tail(rms_normalize(reverb(out, 0.45, 2.0), -22))


# =====================================================================================
# The shed
# =====================================================================================
def wood_knock(f=230, d=0.18, bright=1800):
    x = noise(d) * env_exp(d, 0.012, 0.0005)
    body = peak(x, f, 12) * 2.5 + peak(x, f * 2.3, 10) * 1.2 + bp(x, bright, bright * 2.5) * 0.3
    return body


def glug(f=180, n=3):
    """Water pouring out: the game's money is meltwater."""
    out = np.zeros(secs(0.12 * n + 0.2))
    for i in range(n):
        ff = f * S.rng.uniform(0.9, 1.15)
        place(out, drop(ff, ff * 2.4, 0.12, 0.05), i * 0.1 + S.rng.uniform(0, 0.02), 0.8)
    return out


@sound("buy_tool", "ui")
def buy_tool(_):
    S.seed(700)
    out = np.zeros(secs(1.3))
    place(out, wood_knock(180, 0.2), 0.0, 1.0)
    place(out, glug(200, 3), 0.03, 0.6)
    place(out, bell(hz("C6"), 0.9, decay=0.35), 0.16, 0.5)
    place(out, bell(hz("G6"), 0.9, decay=0.4), 0.27, 0.5)
    return trim_tail(rms_normalize(reverb(out, 0.15, 0.8), -14))


@sound("buy_upgrade", "ui")
def buy_upgrade(_):
    S.seed(710)
    out = np.zeros(secs(1.0))
    for i in range(4):   # a ratchet
        place(out, click(0.01, 3200, 5) + click(0.01, 1400, 4) * 0.5, i * 0.045, 0.7)
    clink = bell(hz("E6") * 1.03, 0.5, partials=((1, 1, 1), (2.76, 0.6, 0.4), (5.4, 0.3, 0.2)), decay=0.15)
    place(out, clink, 0.2, 0.5)
    place(out, bell(hz("A6"), 0.7, decay=0.3), 0.3, 0.4)
    place(out, glug(240, 2), 0.05, 0.4)
    return trim_tail(rms_normalize(reverb(out, 0.12, 0.8), -15))


def honk(f=520, d=0.22):
    """A penguin's squawk: a buzzy reed through a couple of formants, with a wobble."""
    fv = f * (1 + 0.08 * np.sin(np.linspace(0, np.pi, secs(d)))) * (1 + 0.02 * smooth_random(d, 30, -1, 1))
    src = osc(fv, d, "saw")
    v = peak(src, 900, 4) + peak(src, 2200, 6) * 0.6 + src * 0.1
    return v * env_adsr(d, 0.01, 0.05, 0.8, 0.06)


@sound("hire_0", "ui")
def hire_penguin(_):
    S.seed(720)
    out = np.zeros(secs(1.0))
    place(out, honk(560, 0.16), 0.0, 1.0)
    place(out, honk(700, 0.22), 0.2, 1.0)
    place(out, bell(hz("E6"), 0.6, decay=0.25), 0.05, 0.25)
    return trim_tail(rms_normalize(reverb(out, 0.12, 0.8), -15))


@sound("hire_1", "ui")
def hire_sauna(_):
    # Water on hot stones (and a wooden bucket).
    S.seed(730)
    d = 1.8
    out = np.zeros(secs(d))
    place(out, wood_knock(260, 0.2), 0, 0.8)
    splash = bp(noise(0.25), 400, 3000) * env_exp(0.25, 0.06) * 0.6
    place(out, splash, 0.08)
    tss = hp(noise(1.4), 2500) * env_adsr(1.4, 0.04, 0.2, 0.5, 0.9) * 0.6
    place(out, tss, 0.12)
    return trim_tail(rms_normalize(reverb(out, 0.18, 1.0), -15))


@sound("hire_2", "ui")
def hire_kevin(_):
    # Kevin wakes up (or levels up): a deep rumble and a happy blorp.
    S.seed(740)
    d = 2.0
    rumble = lp(brown(d) * 2.0, 140) * env_adsr(d, 0.3, 0.3, 0.7, 0.8)
    out = np.zeros(secs(d))
    place(out, osc(glide(70, 200, 0.25), 0.25) * env_exp(0.25, 0.08, 0.01), 0.7, 0.8)
    place(out, osc(glide(90, 260, 0.2), 0.2) * env_exp(0.2, 0.07, 0.01), 0.95, 0.7)
    return trim_tail(rms_normalize(mix(rumble, out), -13))


@sound("cant_afford", "ui")
def cant_afford(_):
    S.seed(750)
    out = np.zeros(secs(0.6))
    place(out, wood_knock(200, 0.15), 0.0, 1.0)
    place(out, wood_knock(160, 0.15), 0.12, 0.8)
    return trim_tail(rms_normalize(out, -17))


@sound("hover", "ui")
def hover(_):
    S.seed(760)
    return trim_tail(rms_normalize(mix(wood_knock(900, 0.05, 3000) * 0.6, click(0.005, 5000, 5) * 0.2), -26))


@sound("shed_bell", "ui")
def shed_bell(_):
    # The little bell over the shed door.
    S.seed(770)
    out = np.zeros(secs(1.6))
    parts = ((1, 1, 1), (2.42, 0.5, 0.5), (3.9, 0.3, 0.3), (5.6, 0.2, 0.2))
    for i, f in enumerate([1975, 2350, 1975, 2350]):
        place(out, bell(f, 1.0, partials=parts, decay=0.35), i * 0.07 + S.rng.uniform(0, 0.015), 0.5 * 0.8 ** i)
    return trim_tail(rms_normalize(reverb(out, 0.2, 1.0), -21))


# =====================================================================================
# UI
# =====================================================================================
@sound("click", "ui")
def ui_click(_):
    S.seed(800)
    return trim_tail(rms_normalize(mix(wood_knock(620, 0.06, 2600), click(0.004, 4000, 4) * 0.3), -19))


def page_flip(d=0.35):
    x = bp(noise(d), 1500, 7000)
    flutter = (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(glide(60, 20, d)) / SR)) ** 2
    return x * flutter * env_adsr(d, 0.03, 0.05, 0.7, 0.2)


@sound("book_open", "ui")
def book_open(_):
    S.seed(810)
    out = np.zeros(secs(0.6))
    place(out, wood_knock(180, 0.12) * 0.5, 0.0)
    place(out, page_flip(0.35), 0.05, 0.6)
    return trim_tail(rms_normalize(stereo(out, 0.0, 0.6), -18))


@sound("book_close", "ui")
def book_close(_):
    S.seed(820)
    out = np.zeros(secs(0.5))
    place(out, page_flip(0.18), 0.0, 0.4)
    place(out, mix(wood_knock(150, 0.15) * 0.9, lp(noise(0.15), 400) * env_exp(0.15, 0.02)), 0.12)
    return trim_tail(rms_normalize(out, -18))


@sound("offer_tag", "ui")
def offer_tag(_):
    # A paper tag swings down on its string, with a tiny bell.
    S.seed(830)
    out = np.zeros(secs(1.2))
    place(out, page_flip(0.25) * 0.5, 0.0)
    for i, n in enumerate(["G6", "C7"]):
        place(out, bell(hz(n), 0.8, decay=0.25), 0.18 + i * 0.1, 0.3)
    return trim_tail(rms_normalize(reverb(out, 0.2, 1.0), -21))


@sound("reward", "ui")
def reward(_):
    S.seed(840)
    out = np.zeros(secs(1.8))
    scale = ["C6", "D6", "E6", "G6", "A6", "C7", "D7", "E7"]
    for i, n in enumerate(scale):
        place(out, bell(hz(n), 0.8, decay=0.3), i * 0.045, 0.35)
    place(out, hp(noise(0.6), 3000) * env_adsr(0.6, 0.2, 0.1, 0.5, 0.3) * 0.08, 0.0)
    return trim_tail(rms_normalize(reverb(out, 0.3, 1.5), -17))


@sound("respawn", "ui")
def respawn(_):
    S.seed(850)
    d = 0.7
    whoosh = sweep(noise(d), lambda u: 300 + 3500 * np.sin(np.pi * u), "band", q=2.0) * env_adsr(d, 0.25, 0.1, 0.8, 0.3)
    pop = osc(glide(300, 900, 0.08), 0.08) * env_exp(0.08, 0.03)
    out = np.zeros(secs(d + 0.1))
    place(out, whoosh, 0)
    place(out, pop, d - 0.12, 0.5)
    return trim_tail(rms_normalize(stereo(out, 0, 0.5), -18))


@sound("purchase", "ui")
def purchase(_):
    # A real-money purchase went through: warm and grand, but short.
    S.seed(860)
    out = np.zeros(secs(2.0))
    for i, n in enumerate(["C5", "E5", "G5", "C6"]):
        place(out, fm_tone(hz(n), 1.5, 1.0, 1.5, 0.15, 0.8), i * 0.07, 0.35)
    for n in ["C4", "G4", "E5"]:
        place(out, fm_tone(hz(n), 1.6, 2.0, 0.8, 0.4, 1.0), 0.3, 0.15)
    return trim_tail(rms_normalize(reverb(out, 0.3, 1.6), -16))


# =====================================================================================
# You: footsteps, jumping, the jetpack
# =====================================================================================
@sound("step_snow", variants=5)
def step_snow(v):
    # Crunchy snow: lots of tiny grains squeezed in a quick burst.
    S.seed(900 + v)
    d = 0.22
    x = np.zeros(secs(d))
    n = S.rng.integers(30, 50)
    for i in range(n):
        t = abs(S.rng.normal(0.05, 0.03))
        place(x, click(0.003, S.rng.uniform(1500, 6000), 1.5), min(t, d - 0.01), S.rng.uniform(0.2, 1.0))
    body = lp(noise(d), 500) * env_adsr(d, 0.02, 0.05, 0.5, 0.1) * 0.6
    return trim_tail(rms_normalize(lp(x + body, 7000), -22))


@sound("step_ground", variants=4)
def step_ground(v):
    S.seed(920 + v)
    d = 0.18
    thud = lp(noise(d), 350) * env_exp(d, 0.03, 0.003) * 1.5
    rustle = bp(noise(d), 1500, 5000) * env_exp(d, 0.04, 0.01) * 0.25
    return trim_tail(rms_normalize(thud + rustle, -24))


@sound("step_wood", variants=4)
def step_wood(v):
    S.seed(940 + v)
    x = mix(wood_knock(S.rng.uniform(120, 170), 0.25, 1200), lp(noise(0.08), 300) * env_exp(0.08, 0.015) * 0.4)
    return trim_tail(rms_normalize(x, -21))


@sound("jump")
def jump(_):
    S.seed(960)
    d = 0.25
    x = sweep(noise(d), lambda u: 800 + 2500 * u, "band", q=1.5) * env_adsr(d, 0.05, 0.05, 0.6, 0.12)
    return trim_tail(rms_normalize(x, -24))


@sound("land")
def land(_):
    S.seed(970)
    out = np.zeros(secs(0.35))
    place(out, step_snow(4) * 1.3, 0.0)
    place(out, lp(noise(0.2), 220) * env_exp(0.2, 0.05, 0.004) * 1.0, 0.0)
    return trim_tail(rms_normalize(out, -18))


@sound("jet_loop", "loop")
def jet_loop(_):
    d = 2.4
    roar = lp(noise(d), 1400) * (0.7 + 0.3 * smooth_random(d, 18))
    hiss = hp(noise(d), 4000) * 0.3
    rumble = lp(brown(d), 120) * 1.2
    return rms_normalize(make_loop(hp(roar + hiss + rumble, 30), 0.3), -17)


@sound("jet_start")
def jet_start(_):
    S.seed(980)
    d = 0.45
    x = sweep(noise(d) * 1.2, lambda u: 300 + 3000 * u ** 0.5, "lp") * env_adsr(d, 0.01, 0.1, 0.7, 0.2)
    pop = lp(noise(0.05), 2000) * env_exp(0.05, 0.01)
    return trim_tail(rms_normalize(mix(x, pop), -17))


@sound("jet_sputter")
def jet_sputter(_):
    S.seed(990)
    out = np.zeros(secs(0.7))
    for i, t in enumerate([0.0, 0.13, 0.22, 0.38]):
        puff = lp(noise(0.08), 1200) * env_exp(0.08, 0.02, 0.003)
        place(out, puff, t, 0.9 * 0.75 ** i)
    return trim_tail(rms_normalize(out, -18))


# =====================================================================================
# Helpers
# =====================================================================================
@sound("penguin", variants=4)
def penguin(v):
    S.seed(1000 + v)
    out = np.zeros(secs(0.6))
    n = 1 + v % 2
    for i in range(n):
        place(out, honk(S.rng.uniform(600, 900), S.rng.uniform(0.07, 0.13)), i * 0.14, 1.0)
    return trim_tail(rms_normalize(out, -18))


@sound("sauna_steam", variants=3)
def sauna_steam(v):
    S.seed(1100 + v)
    d = 1.3
    out = np.zeros(secs(d))
    splash = bp(noise(0.15), 500, 3000) * env_exp(0.15, 0.04) * 0.5
    place(out, splash, 0)
    tss = hp(noise(1.1), 2800) * env_adsr(1.1, 0.03, 0.2, 0.45, 0.7)
    place(out, tss, 0.05, 0.7)
    return trim_tail(rms_normalize(out, -20))


@sound("sauna_ahh", variants=2)
def sauna_ahh(v):
    # A contented "ahh" from the sauna crew: a breathy voice through vowel formants.
    S.seed(1150 + v)
    d = 0.8
    f0 = (150 if v == 0 else 190) * (1 + 0.04 * np.linspace(0, -1, secs(d))) * (1 + 0.01 * np.sin(2 * np.pi * 5.5 * t_axis(d)))
    src = osc(f0, d, "saw") * 0.6 + bp(noise(d), 300, 3000) * 0.08
    v_ = peak(src, 750, 5) * 1.0 + peak(src, 1200, 6) * 0.6 + peak(src, 2600, 8) * 0.25
    return trim_tail(rms_normalize(v_ * env_adsr(d, 0.08, 0.1, 0.8, 0.35), -21))


@sound("kevin_launch", variants=2)
def kevin_launch(v):
    # Kevin lobs a lava bomb: a deep, far-off "thoom".
    S.seed(1200 + v)
    d = 1.6
    boom = osc(glide(85, 32, 0.6), 0.6) * env_exp(0.6, 0.2, 0.005)
    rumble = lp(brown(d), 180) * env_adsr(d, 0.01, 0.2, 0.4, 1.0) * 1.2
    out = mix(boom, rumble)
    return trim_tail(rms_normalize(out, -13))


@sound("bomb_whistle")
def bomb_whistle(_):
    S.seed(1250)
    d = 1.0
    f = glide(1400, 700, d)
    x = osc(f, d) * 0.3 + bp(noise(d), 800, 2500) * 0.4
    return trim_tail(rms_normalize(x * env_adsr(d, 0.3, 0.1, 0.8, 0.2), -24))


@sound("bomb_land", variants=3)
def bomb_land(v):
    # Lava hits ice: a wet splat and a big hiss of steam.
    S.seed(1300 + v)
    d = 2.0
    out = np.zeros(secs(d))
    splat = lp(noise(0.2), 1500) * env_exp(0.2, 0.04, 0.002) * 1.5
    place(out, splat, 0)
    place(out, osc(glide(120, 45, 0.25), 0.25) * env_exp(0.25, 0.08), 0, 1.0)
    hiss = hp(noise(1.7), 2000) * env_adsr(1.7, 0.05, 0.3, 0.45, 1.1) * 0.8
    place(out, hiss, 0.05)
    for i in range(8):
        f = S.rng.uniform(80, 200)
        place(out, osc(glide(f, f * 2.2, 0.1), 0.1) * env_exp(0.1, 0.035), S.rng.uniform(0.1, 1.0), 0.4)
    return trim_tail(rms_normalize(out, -14))


# =====================================================================================
# The village gate, pirates
# =====================================================================================
@sound("gate_unlock", "ui")
def gate_unlock(_):
    S.seed(1400)
    out = np.zeros(secs(1.0))
    metal = ((1, 1, 1), (2.3, 0.7, 0.6), (3.7, 0.5, 0.4), (5.2, 0.3, 0.3))
    place(out, mix(bell(820, 0.5, partials=metal, decay=0.08) * 0.6, click(0.01, 2500, 3)), 0.0)
    place(out, mix(bell(610, 0.6, partials=metal, decay=0.12) * 0.7, click(0.012, 1800, 3)), 0.18)
    place(out, wood_knock(140, 0.2) * 0.6, 0.22)
    return trim_tail(rms_normalize(reverb(out, 0.2, 1.2), -15))


@sound("gate_creak")
def gate_creak(_):
    # Stick-slip: a wooden hinge creaking open, a little irregular.
    S.seed(1410)
    d = 2.2
    x = np.zeros(secs(d))
    t = 0.0
    while t < d - 0.05:
        # the hinge sticks and slips at a rate that wanders (that's the "eee-aww")
        wob = 0.5 + 0.5 * np.sin(t * 1.7 + 0.8 * np.sin(t * 5.3))
        period = 0.004 + 0.012 * wob + S.rng.uniform(0, 0.0015)
        g = np.sin(np.pi * t / d) ** 0.5 * (0.4 if S.rng.random() < 0.08 else 1.0)
        x[secs(t)] += g * S.rng.uniform(0.6, 1.0)
        t += period
    body = peak(x, 380, 8) + peak(x, 920, 10) * 0.7 + peak(x, 1900, 12) * 0.3
    return trim_tail(rms_normalize(body, -17))


@sound("ship_bell", "ui")
def ship_bell(_):
    S.seed(1500)
    out = np.zeros(secs(3.0))
    parts = ((0.5, 0.6, 1.4), (1, 1, 1), (1.19, 0.6, 0.8), (1.5, 0.4, 0.6), (2.0, 0.5, 0.5), (2.5, 0.2, 0.3), (3.0, 0.15, 0.2))
    for i in range(2):
        place(out, bell(hz("A5"), 2.5, partials=parts, decay=1.0), i * 0.45, 0.5)
    return trim_tail(rms_normalize(reverb(out, 0.3, 2.0), -17))


def reed(f, d, vol=1.0):
    """A squeezebox reed: two slightly detuned square-ish waves with a little tremolo."""
    t = t_axis(d)
    x = osc(f * 1.003, d, "square") + osc(f * 0.997, d, "square") * 0.8
    x = lp(x, 2600) * (1 + 0.12 * np.sin(2 * np.pi * 6 * t))
    return x * env_adsr(d, 0.02, 0.05, 0.8, 0.05) * vol


@sound("pirate_sting", "ui")
def pirate_sting(_):
    # A ship is free: a jolly little squeezebox phrase and a jingle of coins.
    S.seed(1510)
    beat = 0.16
    phrase = [("D5", 1), ("G5", 1), ("G5", 0.5), ("A5", 0.5), ("B5", 1), ("G5", 1), ("D6", 2)]
    out = np.zeros(secs(beat * 9 + 1.2))
    t = 0.0
    for n, b in phrase:
        place(out, reed(hz(n), beat * b * 0.95), t, 0.5)
        place(out, reed(hz(n) / 2, beat * b * 0.95), t, 0.2)
        t += beat * b
    for n in ["G3", "D4"]:
        place(out, reed(hz(n), beat * 2), 0, 0.15)
        place(out, reed(hz(n), beat * 2), beat * 4, 0.15)
    for i in range(10):
        place(out, bell(S.rng.uniform(3500, 6000), 0.3, partials=((1, 1, 1), (1.6, 0.5, 0.5)), decay=0.07), t + S.rng.uniform(0, 0.3), 0.15)
    return trim_tail(rms_normalize(reverb(out, 0.18, 1.2), -16))


# =====================================================================================
# Big moments
# =====================================================================================
def music_box(f, d=1.6):
    return bell(f, d, partials=((1, 1, 1), (3.0, 0.2, 0.25), (6.1, 0.06, 0.1)), decay=0.6)


@sound("stage_done", "ui")
def stage_done(_):
    # The village is free! A warm little fanfare.
    S.seed(1600)
    beat = 0.19
    mel = [("C5", 1), ("E5", 1), ("G5", 1), ("C6", 2), ("A5", 1), ("C6", 1), ("E6", 4)]
    chords = [(0, ["C3", "G3", "E4"]), (5, ["F3", "A3", "C4"]), (7, ["C3", "G3", "C4", "E4"])]
    out = np.zeros(secs(beat * 11 + 3.0))
    t = 0.0
    for n, b in mel:
        place(out, music_box(hz(n), 2.0), t, 0.5)
        place(out, pluck(hz(n) / 2, 0.6, 0.4), t, 0.15)
        t += beat * b
    for at, ch in chords:
        for n in ch:
            place(out, fm_tone(hz(n), 2.5, 1.0, 1.0, 0.3, 1.2), at * beat, 0.18)
    for i in range(12):
        place(out, bell(S.rng.uniform(3000, 7000), 0.3, partials=((1, 1, 1),), decay=0.08), beat * 7 + S.rng.uniform(0, 1.2), 0.08)
    return trim_tail(rms_normalize(reverb(out, 0.3, 2.2), -14))


@sound("level_menu", "ui")
def level_menu(_):
    # Unfolding the map of what's next.
    S.seed(1620)
    out = np.zeros(secs(1.5))
    place(out, page_flip(0.5) * 0.7, 0.0)
    for i, n in enumerate(["D5", "A5", "E6"]):
        place(out, music_box(hz(n), 1.2), 0.25 + i * 0.12, 0.35)
    return trim_tail(rms_normalize(reverb(out, 0.25, 1.5), -19))


# =====================================================================================
# Ambience (long seamless loops, streamed)
# =====================================================================================
@sound("wind", "amb")
def wind(_):
    # Mountain wind: brown noise through a slowly wandering band, in stereo.
    S.seed(1700)
    d = 24.0
    chans = []
    for ch in range(2):
        g = smooth_random(d + 2, 0.35, 0.15, 1.0) ** 1.6
        centre = 250 + 700 * smooth_random(d + 2, 0.25)
        x = sweep(brown(d + 2) * 2.0, centre, "band", q=1.2) * g
        whistle = sweep(noise(d + 2), 1500 + 900 * smooth_random(d + 2, 0.2), "band", q=12) * smooth_random(d + 2, 0.15) ** 3 * 0.25
        chans.append(x + whistle)
    x = np.stack(chans, axis=1)
    return rms_normalize(make_loop(x, 2.0), -24)


def bird_call(kind):
    if kind == 0:   # a quick rising chirp, repeated
        out = np.zeros(secs(0.6))
        f0 = S.rng.uniform(2800, 4200)
        for i in range(S.rng.integers(2, 5)):
            c = osc(glide(f0, f0 * 1.5, 0.05), 0.05) * env_adsr(0.05, 0.005, 0.01, 0.8, 0.02)
            place(out, c, i * 0.09)
        return out
    if kind == 1:   # a trill
        d = S.rng.uniform(0.4, 0.8)
        f = S.rng.uniform(3500, 5000) * (1 + 0.12 * np.sin(2 * np.pi * S.rng.uniform(22, 30) * t_axis(d)))
        return osc(f, d) * env_adsr(d, 0.03, 0.05, 0.8, 0.1)
    if kind == 2:   # a two-note song, far off
        out = np.zeros(secs(0.8))
        a, b = S.rng.uniform(2000, 2600), S.rng.uniform(1500, 1900)
        place(out, osc(glide(a, a * 1.05, 0.15), 0.15) * env_adsr(0.15, 0.02, 0.02, 0.8, 0.05), 0)
        place(out, osc(glide(b, b * 0.95, 0.22), 0.22) * env_adsr(0.22, 0.02, 0.02, 0.8, 0.08), 0.22)
        return out
    # a falling whistle
    d = 0.35
    f0 = S.rng.uniform(3000, 3800)
    return osc(glide(f0, f0 * 0.6, d), d) * env_adsr(d, 0.02, 0.05, 0.8, 0.1)


@sound("birds", "amb")
def birds(_):
    # Summer: birdsong over a soft breeze and a trickle of water.
    S.seed(1800)
    d = 30.0
    out = np.zeros((secs(d), 2))
    t = 0.3
    while t < d - 1.0:
        call = bird_call(S.rng.integers(0, 4)) * S.rng.uniform(0.15, 0.5)
        place(out, stereo(call, S.rng.uniform(-0.8, 0.8)), t)
        t += S.rng.exponential(0.9)
    breeze = np.stack([lp(brown(d), 500) * smooth_random(d, 0.3, 0.3, 1.0) for _ in range(2)], axis=1) * 0.3
    trickle = np.zeros(secs(d))
    for _ in range(int(d * 8)):
        f = S.rng.uniform(700, 1800)
        place(trickle, drop(f, f * 1.7, 0.06, 0.02), S.rng.uniform(0, d - 0.1), S.rng.uniform(0.02, 0.08))
    out = reverb(out, 0.25, 1.5)[:secs(d)] + breeze + stereo(trickle, -0.3)
    return rms_normalize(make_loop(out, 1.5), -26)


# =====================================================================================
def build(prefixes=()):
    for name, (fn, kind) in SOUNDS.items():
        if prefixes and not any(name.startswith(p) for p in prefixes):
            continue
        S.seed(zlib.crc32(name.encode()))
        x = fn()
        if kind in ("sfx", "ui"):
            x = hp(x, 25)   # no DC offset (the rumbles are made of brown noise)
        folder = "amb" if kind == "amb" else "sfx"
        path = os.path.join(ROOT, "audio", folder, name + ".ogg")
        mono = kind in ("sfx", "loop")
        q = 3 if kind == "amb" else 4
        write_ogg(path, x, quality=q, mono=True if mono else False)
        print("%-18s %5.2fs  %s" % (name, len(x) / SR, kind))


if __name__ == "__main__":
    build(tuple(sys.argv[1:]))
