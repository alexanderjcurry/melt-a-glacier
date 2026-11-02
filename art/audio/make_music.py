"""Composes and renders the game's music into audio/music.

    python art/audio/make_music.py            # every track
    python art/audio/make_music.py valley_1   # one track

The tunes are written out by hand below (chords, melodies, accompaniment
patterns) and played by small synthesized instruments: a felt piano, a music
box, a kalimba, a celesta, a soft flute, a warm pad, a plucked bass,
pizzicato and a shaker. Nothing is sampled, so it's all original.

Tracks:
  valley_1  F major, 84 bpm. Music box over a flowing felt piano. The first glacier.
  valley_2  D major, a 3/4 waltz at 76 bpm. Kalimba and pizzicato. The first glacier.
  lake_1    E minor into G, 66 bpm. Flute over a wide pad. The frozen lake.
  lake_2    A minor into C, 82 bpm. Celesta and pizzicato, a little busier. The frozen lake.
  summer    C major, 92 bpm. Flute, kalimba and piano. The ending, when summer's back.
"""
import os
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import synth as S  # noqa: E402
from synth import (SR, bell, env_adsr, env_exp, fm_tone, lp, hp, bp, noise, osc, place, pluck,  # noqa: E402
                   reverb, rms_normalize, secs, smooth_random, stereo, t_axis, trim_tail, write_ogg)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
        "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def m(name):
    """'A4' -> 69"""
    return 12 * (int(name[-1]) + 1) + NOTE[name[:-1]]


def f(midi_):
    return 440.0 * 2 ** ((midi_ - 69) / 12)


# =====================================================================================
# Instruments: (freq, seconds, velocity 0..1) -> mono array (may ring past `seconds`)
# =====================================================================================
def piano(fr, d, vel):
    ring = min(4.0, 2.8 * (220 / fr) ** 0.35)
    total = d + 0.35
    t = t_axis(total)
    out = np.zeros(len(t))
    B = 0.00025
    bright = 1.7 - 0.7 * vel
    for k in range(1, 11):
        fk = fr * k * np.sqrt(1 + B * k * k)
        if fk > 9000:
            break
        a = 1.0 / k ** bright
        dk = ring / (1 + 0.45 * (k - 1))
        part = np.sin(2 * np.pi * fk * t + S.rng.uniform(0, 6.28))
        if k <= 3:   # two strings a hair apart: a slow, warm beat
            part = 0.5 * part + 0.5 * np.sin(2 * np.pi * fk * 1.0007 * t)
        out += a * part * np.exp(-t / dk)
    hammer = lp(S.rng.standard_normal(secs(0.012)), 1800) * np.linspace(1, 0, secs(0.012)) * 0.15
    out[:len(hammer)] += hammer
    out[:secs(0.004)] *= np.linspace(0, 1, secs(0.004))
    # the damper comes down when the key is let go
    rel = np.ones(len(t))
    r0 = secs(d)
    if r0 < len(t):
        rel[r0:] = np.exp(-np.arange(len(t) - r0) / (0.09 * SR))
    return lp(out * rel, 2200 + 3000 * vel) * vel


def music_box(fr, d, vel):
    ring = 1.6 * (523 / fr) ** 0.3
    x = bell(fr, ring * 2.2, partials=((1, 1, 1), (3.01, 0.16, 0.3), (5.97, 0.05, 0.12)), decay=ring)
    x[:secs(0.003)] += S.rng.standard_normal(secs(0.003)) * 0.05
    return x * vel


def kalimba(fr, d, vel):
    ring = 0.9 * (440 / fr) ** 0.3
    x = bell(fr, ring * 2.5, partials=((1, 1, 1), (6.27, 0.14, 0.12), (2.0, 0.04, 0.5)), decay=ring)
    thumb = lp(S.rng.standard_normal(secs(0.01)), 900) * np.linspace(1, 0, secs(0.01)) * 0.2
    x[:len(thumb)] += thumb
    return x * vel


def celesta(fr, d, vel):
    ring = 1.3 * (523 / fr) ** 0.4
    x = fm_tone(fr, ring * 2.5, 1.0, 1.4, 0.05, ring, 0.002) + fm_tone(fr * 2, ring * 2.5, 1.0, 0.3, 0.05, ring * 0.5) * 0.15
    return x * vel


def flute(fr, d, vel):
    total = d + 0.15
    t = t_axis(total)
    vib_amt = np.clip((t - 0.25) / 0.4, 0, 1) * 0.004
    fv = fr * (1 + vib_amt * np.sin(2 * np.pi * 5.0 * t))
    ph = 2 * np.pi * np.cumsum(fv) / SR
    tone = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.05 * np.sin(3 * ph)
    breath = bp(S.rng.standard_normal(len(t)), fr * 0.9, min(fr * 5, 12000)) * 0.06
    amp = 1 + 0.06 * smooth_random(total, 3, -1, 1)
    e = env_adsr(total, 0.07, 0.1, 0.85, 0.15)
    return (tone + breath) * amp * e * vel * 0.7


def bass(fr, d, vel):
    total = d + 0.2
    x = pluck(fr, total, 0.18, 0.997) * 0.8
    body = osc(fr, total) * env_exp(total, 0.6, 0.006) * 0.5
    x = (x + body) * env_adsr(total, 0.003, 0.0, 1.0, 0.12)
    return lp(x, 900) * vel


def pizz(fr, d, vel):
    total = min(d, 0.5) + 0.2
    x = pluck(fr, total, 0.45, 0.985)
    return lp(x, 3500) * env_adsr(total, 0.002, 0.0, 1.0, 0.1) * vel


def shaker(fr, d, vel):
    x = hp(S.rng.standard_normal(secs(0.07)), 5500) * env_exp(0.07, 0.018, 0.006)
    return x * vel * 0.25


def glock(fr, d, vel):
    return bell(fr, 1.5, partials=((1, 1, 1), (2.76, 0.3, 0.3), (5.4, 0.1, 0.15)), decay=0.5) * vel


INSTRUMENTS = {"piano": piano, "box": music_box, "kalimba": kalimba, "celesta": celesta, "flute": flute,
               "bass": bass, "pizz": pizz, "shaker": shaker, "glock": glock}


# =====================================================================================
# A little sequencer
# =====================================================================================
class Song:
    def __init__(self, bpm, meter, bars, tail=4.0):
        self.bpm, self.meter, self.bars = bpm, meter, bars
        self.beat = 60.0 / bpm
        self.length = bars * meter * self.beat + tail
        self.tracks = {}   # name -> stereo buffer
        self.pans = {}

    def buf(self, name):
        if name not in self.tracks:
            self.tracks[name] = np.zeros((secs(self.length), 2))
        return self.tracks[name]

    def at(self, bar, beat):
        return (bar * self.meter + beat) * self.beat

    def note(self, inst, bar, beat, beats, pitch, vel=0.8, pan=0.0, track=None, swing=0.0):
        if isinstance(pitch, str):
            pitch = m(pitch)
        frac = beat % 1.0
        if swing and abs(frac - 0.5) < 1e-6:
            beat += swing
        t = self.at(bar, beat) + S.rng.normal(0, 0.006)
        vel = float(np.clip(vel * S.rng.uniform(0.92, 1.05), 0.05, 1.0))
        x = S.taper(INSTRUMENTS[inst](f(pitch), beats * self.beat, vel), 0.25, 0.12)
        place(self.buf(track or inst), stereo(x, pan), max(0.0, t))

    def melody(self, inst, bar, seq, vel=0.8, pan=0.0, shift=0, track=None):
        """seq: list of (note name or None, beats)."""
        beat = 0.0
        for n, b in seq:
            if n is not None:
                accent = 1.0 if (beat % self.meter) == 0 else 0.92
                self.note(inst, bar, beat, b * 0.95, m(n) + shift, vel * accent, pan, track)
            beat += b
        return beat

    def pad(self, bar, beats, names, vel=0.5, track="pad", cutoff=1300, attack=1.0):
        d = beats * self.beat
        total = d + 1.6
        t = t_axis(total)
        out = np.zeros((len(t), 2))
        for n in names:
            fr = f(m(n))
            for ch, det in ((0, -0.07), (1, 0.07)):
                v = osc(fr * 2 ** (det / 12), total, "saw") + osc(fr * 2 ** (-det / 24), total, "saw") * 0.6
                out[:, ch] += v
        cut = cutoff * (1 + 0.2 * np.sin(2 * np.pi * 0.15 * t))
        for ch in range(2):
            out[:, ch] = S.sweep(out[:, ch], cut, "lp")
        e = env_adsr(total, attack, 0.3, 0.8, 1.6)
        out *= e[:, None] * vel * 0.06
        place(self.buf(track), out, self.at(bar, 0))

    def render(self, gains, wet=0.28, room=2.4, target=-19.0):
        n = secs(self.length)
        dry = np.zeros((n, 2))
        for name, b in self.tracks.items():
            dry += b * gains.get(name, 1.0)
        out = reverb(dry, wet, room, 5000)
        out = hp(out, 30)
        out = trim_tail(out[: n + secs(room)], -55)
        return rms_normalize(out, target)


def ch(bass_, upper):
    return (bass_, upper.split())


# --- Accompaniment patterns ---------------------------------------------------------------
def flowing(song, bar, chord, vel=0.5, inst="piano", meter=4):
    """Felt-piano arpeggio in eighths: bass, then up through the chord and back."""
    b, up = chord
    song.note("bass" if inst == "bass" else inst, bar, 0, 2, b, vel * 1.05, -0.15)
    order = [up[0], up[1], up[2], up[1], up[0] if len(up) < 4 else up[3], up[1], up[2], up[1]]
    for i in range(1, 8):
        song.note(inst, bar, i * 0.5, 0.7, order[i], vel * (0.75 if i % 2 else 0.85), 0.1 + 0.05 * (i % 3))


def waltz(song, bar, chord, vel=0.5, inst="piano"):
    b, up = chord
    song.note(inst, bar, 0, 1.5, b, vel, -0.2)
    for beat in (1, 2):
        for n in up:
            song.note(inst, bar, beat, 0.7, n, vel * 0.55, 0.15)


def offbeats(song, bar, chord, vel=0.5, inst="pizz", meter=4):
    b, up = chord
    for beat in range(meter):
        for n in up:
            song.note(inst, bar, beat + 0.5, 0.4, n, vel * 0.6, 0.25)


def walking_bass(song, bar, chord, vel=0.7, pattern=(0, 2), meter=4):
    b, up = chord
    root = m(b)
    for i, beat in enumerate(pattern):
        pitch = root if i % 2 == 0 else root + 7
        song.note("bass", bar, beat, (meter / len(pattern)) * 0.9, pitch, vel, -0.1)


def shaker_bar(song, bar, vel=0.4, swing=0.06, meter=4):
    for i in range(meter * 2):
        song.note("shaker", bar, i * 0.5, 0.2, 60, vel * (1.0 if i % 2 == 0 else 0.6), 0.35, swing=swing)


# =====================================================================================
# The tracks
# =====================================================================================
def valley_1():
    """F major, 84 bpm: music box over a flowing felt piano. Intro 4, A 8, B 8, A' 8, outro 4."""
    S.seed(11)
    s = Song(84, 4, 32, tail=5.0)
    A = [ch("F2", "A3 C4 F4"), ch("A2", "G3 C4 E4"), ch("Bb2", "F3 Bb3 D4"), ch("C3", "G3 C4 E4"),
         ch("F2", "A3 C4 F4"), ch("D2", "F3 A3 C4"), ch("G2", "F3 Bb3 D4"), ch("C3", "Bb3 E4 G4")]
    B = [ch("Bb2", "F3 Bb3 D4"), ch("C3", "G3 C4 E4"), ch("A2", "E3 A3 C4"), ch("D2", "F3 A3 D4"),
         ch("G2", "F3 Bb3 D4"), ch("C3", "E3 G3 C4"), ch("A2", "F3 A3 C4"), ch("Bb2", "F3 Bb3 D4")]
    intro = [ch("F2", "A3 C4 F4"), ch("Bb2", "F3 Bb3 D4"), ch("F2", "A3 C4 F4"), ch("C3", "G3 C4 E4")]
    outro = [ch("F2", "A3 C4 F4"), ch("Bb2", "F3 Bb3 D4"), ch("G2", "F3 Bb3 D4"), ch("F2", "A3 C4 F4")]
    mel_a = [("C5", 1), ("A4", .5), ("C5", .5), ("F5", 1.5), ("E5", .5),
             ("E5", 1), ("C5", 1), ("A4", 2),
             ("D5", 1), ("F5", .5), ("D5", .5), ("Bb4", 1), ("C5", 1),
             ("E5", .5), ("D5", .5), ("C5", 1), ("G4", 2),
             ("C5", 1), ("A4", .5), ("C5", .5), ("F5", 1), ("A5", 1),
             ("G5", 1.5), ("F5", .5), ("E5", .5), ("D5", .5), ("C5", 1),
             ("Bb4", 1), ("D5", 1), ("F5", 1), ("E5", .5), ("D5", .5),
             ("E5", 1), ("G5", 1), ("C5", 2)]
    mel_b = [("F5", 2), ("D5", 1), ("F5", 1),
             ("G5", 1.5), ("E5", .5), ("C5", 2),
             ("E5", 1), ("A5", 1), ("G5", 1), ("E5", 1),
             ("F5", 2), ("D5", 2),
             ("D5", 1), ("F5", 1), ("Bb5", 1.5), ("A5", .5),
             ("G5", 1), ("E5", 1), ("C5", 1), ("D5", 1),
             ("C5", 1), ("F5", 1), ("A5", 2),
             ("G5", 2), ("E5", 1), ("C5", 1)]
    bar = 0
    for c in intro:
        flowing(s, bar, c, 0.45)
        bar += 1
    for c in A:
        flowing(s, bar, c, 0.42)
        s.pad(bar, 4, c[1], 0.35)
        walking_bass(s, bar, c, 0.55)
        bar += 1
    s.melody("box", 4, mel_a, 0.75, 0.1)
    for c in B:
        flowing(s, bar, c, 0.45)
        s.pad(bar, 4, c[1], 0.45)
        walking_bass(s, bar, c, 0.6, (0, 2, 3))
        shaker_bar(s, bar, 0.35)
        bar += 1
    s.melody("piano", 12, mel_b, 0.62, 0.0, 12)
    s.melody("flute", 12, mel_b, 0.25, -0.3)
    for c in A:
        flowing(s, bar, c, 0.42)
        s.pad(bar, 4, c[1], 0.4)
        walking_bass(s, bar, c, 0.55)
        shaker_bar(s, bar, 0.25)
        bar += 1
    s.melody("box", 20, mel_a, 0.75, 0.1)
    s.melody("glock", 20, [(n, b) for n, b in mel_a[:5]] + [(None, 28)], 0.15, -0.4, 12)
    for i, c in enumerate(outro):
        if i < 3:
            flowing(s, bar, c, 0.4 - 0.05 * i)
        else:
            s.note("bass", bar, 0, 4, c[0], 0.5)
            for k, n in enumerate(c[1]):
                s.note("piano", bar, k * 0.12, 4, n, 0.4)
        s.pad(bar, 4, c[1], 0.3)
        bar += 1
    s.melody("box", 28, [("A5", 2), ("F5", 2), ("D5", 2), ("Bb4", 2), ("A4", 1), ("C5", 1), ("E5", 2), ("F5", 4)], 0.6, 0.1)
    return s.render({"piano": 0.9, "box": 1.0, "flute": 0.8, "pad": 0.9, "bass": 0.9, "shaker": 0.7, "glock": 0.8})


def valley_2():
    """D major waltz, 76 bpm: kalimba lead, pizzicato and piano. Intro 4, A 8, A2 8, bridge 8, A 8, outro 2."""
    S.seed(22)
    s = Song(76, 3, 38, tail=5.0)
    A = [ch("D2", "F#3 A3 D4"), ch("D2", "G3 B3 D4"), ch("D2", "F#3 A3 D4"), ch("A2", "E3 A3 C#4"),
         ch("B2", "F#3 B3 D4"), ch("G2", "G3 B3 D4"), ch("E2", "G3 B3 D4"), ch("A2", "G3 C#4 E4")]
    bridge = [ch("G2", "G3 B3 D4"), ch("A2", "A3 C#4 E4"), ch("F#2", "F#3 A3 C#4"), ch("B2", "F#3 B3 D4"),
              ch("E2", "G3 B3 E4"), ch("A2", "G3 C#4 E4"), ch("D2", "F#3 A3 D4"), ch("D2", "F#3 A3 D4")]
    mel_a = [("A4", 1), ("F#5", 1.5), ("E5", .5),
             ("D5", 1), ("B4", 2),
             ("A4", 1), ("D5", 1), ("F#5", 1),
             ("E5", 3),
             ("F#5", 1), ("D5", 1), ("B4", 1),
             ("G5", 1.5), ("F#5", .5), ("E5", 1),
             ("D5", 1), ("E5", 1), ("G5", 1),
             ("C#5", 2), ("A4", 1)]
    mel_a2 = mel_a[:13] + [("G5", 1), ("F#5", 1), ("E5", 1), ("E5", 1.5), ("C#5", .5), ("A4", 1)]
    mel_a_end = mel_a[:13] + [("G5", 1), ("F#5", 1), ("E5", 1), ("D5", 3)]
    mel_br = [("B4", 1), ("D5", 1), ("G5", 1),
              ("A5", 2), ("E5", 1),
              ("F#5", 1), ("C#5", 1), ("A4", 1),
              ("D5", 3),
              ("E5", 1), ("G5", 1), ("B5", 1),
              ("A5", 1.5), ("G5", .5), ("E5", 1),
              ("F#5", 3),
              ("D5", 2), ("A4", 1)]
    bar = 0
    for i in range(4):
        waltz(s, bar, A[i % 2 * 2], 0.42, "piano")
        bar += 1
    s.melody("glock", 0, [(None, 6), ("A5", 1), ("D6", 1), ("F#6", 4)], 0.18, 0.4)
    for section, mel, inst in ((A, mel_a, "kalimba"), (A, mel_a2, "kalimba"), (bridge, mel_br, "flute"), (A, mel_a_end, "kalimba")):
        start = bar
        for c in section:
            waltz(s, bar, c, 0.36, "pizz")
            s.note("bass", bar, 0, 2.5, c[0], 0.6)
            if section is bridge:
                s.pad(bar, 3, c[1], 0.45)
            else:
                s.pad(bar, 3, c[1], 0.28)
            bar += 1
        s.melody(inst, start, mel, 0.8 if inst == "kalimba" else 0.55, 0.15)
        if inst == "kalimba" and mel is mel_a2:
            s.melody("piano", start, mel, 0.3, -0.2, -12)
    s.note("bass", bar, 0, 6, "D2", 0.5)
    for k, n in enumerate(["D4", "F#4", "A4", "D5"]):
        s.note("piano", bar, k * 0.15, 6, n, 0.35)
    s.melody("kalimba", bar, [("A5", 1), ("F#5", 1), ("D6", 4)], 0.6, 0.15)
    return s.render({"kalimba": 1.0, "pizz": 0.8, "piano": 0.75, "bass": 0.85, "pad": 0.8, "flute": 0.9, "glock": 0.8})


def lake_1():
    """E minor into G, 66 bpm: flute over a wide pad, sparse piano, deep bass, glock sparkle."""
    S.seed(33)
    s = Song(66, 4, 30, tail=6.0)
    A = [ch("E2", "G3 B3 F#4"), ch("C2", "G3 B3 E4"), ch("G2", "G3 B3 D4"), ch("F#2", "A3 D4 F#4"),
         ch("E2", "G3 B3 F#4"), ch("C2", "G3 B3 E4"), ch("A2", "G3 C4 E4"), ch("B2", "F#3 B3 D#4")]
    B = [ch("C2", "G3 C4 E4"), ch("D2", "F#3 A3 D4"), ch("B2", "F#3 A3 D4"), ch("E2", "G3 B3 E4"),
         ch("C2", "G3 C4 E4"), ch("D2", "F#3 A3 D4"), ch("G2", "G3 B3 D4"), ch("B2", "F#3 B3 D#4")]
    mel_a = [(None, 1), ("B4", 1), ("E5", 1), ("F#5", 1),
             ("G5", 3), ("E5", 1),
             ("D5", 2), ("B4", 1), ("D5", 1),
             ("A4", 3), (None, 1),
             ("B4", 1), ("E5", 1), ("F#5", 1), ("G5", 1),
             ("B5", 2), ("A5", 1), ("G5", 1),
             ("E5", 2), ("G5", 1), ("A5", 1),
             ("F#5", 3), ("D#5", 1)]
    mel_b = [("E5", 1.5), ("G5", .5), ("B5", 2),
             ("A5", 1.5), ("F#5", .5), ("D5", 2),
             ("F#5", 1), ("D5", 1), ("B4", 2),
             ("E5", 2), ("G5", 1), ("B5", 1),
             ("C6", 2), ("B5", 1), ("G5", 1),
             ("A5", 2), ("F#5", 1), ("D5", 1),
             ("G5", 1), ("B5", 1), ("D6", 2),
             ("B5", 3), (None, 1)]

    def sparse(bar, c, vel):
        s.note("bass", bar, 0, 3.5, c[0], 0.55)
        s.note("piano", bar, 0, 2, c[1][0], vel)
        s.note("piano", bar, 1.5, 2, c[1][1], vel * 0.8)
        s.note("piano", bar, 2.5, 1.5, c[1][2], vel * 0.85)

    bar = 0
    intro = [ch("E2", "G3 B3 F#4"), ch("C2", "G3 B3 E4"), ch("E2", "G3 B3 F#4"), ch("C2", "G3 B3 E4")]
    for c in intro:
        s.pad(bar, 4, c[1], 0.5, attack=2.0, cutoff=1000)
        s.note("bass", bar, 0, 4, c[0], 0.45)
        bar += 1
    s.melody("glock", 1, [("B5", 1), ("E6", 1), ("F#6", 2), (None, 4), ("G6", 1), ("F#6", 1), ("B5", 2)], 0.2, 0.4)
    for sec, mel in ((A, mel_a), (B, mel_b), (A, mel_a)):
        start = bar
        for c in sec:
            s.pad(bar, 4, c[1], 0.45, attack=1.5, cutoff=1100)
            sparse(bar, c, 0.32)
            bar += 1
        s.melody("flute", start, mel, 0.62, 0.0)
        if sec is B:
            s.melody("celesta", start, mel, 0.18, 0.35, 12)
    for c in [ch("C2", "G3 B3 E4"), ch("E2", "G3 B3 E4")]:
        s.pad(bar, 4, c[1], 0.4, attack=1.5, cutoff=900)
        s.note("bass", bar, 0, 4, c[0], 0.4)
        bar += 1
    s.melody("glock", bar - 2, [("G6", 1), ("E6", 1), ("B5", 2), ("E6", 4)], 0.18, 0.4)
    return s.render({"flute": 0.95, "pad": 1.0, "piano": 0.8, "bass": 0.9, "glock": 0.8, "celesta": 0.8}, wet=0.36, room=3.2)


def lake_2():
    """A minor into C, 82 bpm: celesta ostinato and melody, pizzicato, plucked bass."""
    S.seed(44)
    s = Song(82, 4, 36, tail=5.0)
    A = [ch("A2", "A3 C4 E4"), ch("F2", "A3 C4 F4"), ch("C3", "G3 C4 E4"), ch("G2", "G3 B3 D4"),
         ch("A2", "A3 C4 E4"), ch("F2", "A3 C4 F4"), ch("D2", "F3 A3 C4"), ch("E2", "G#3 B3 D4")]
    B = [ch("F2", "A3 C4 F4"), ch("G2", "G3 B3 D4"), ch("E2", "G3 B3 E4"), ch("A2", "A3 C4 E4"),
         ch("D2", "F3 A3 D4"), ch("G2", "G3 B3 D4"), ch("C3", "G3 C4 E4"), ch("E2", "G#3 B3 E4")]
    mel_a = [("E5", 1), ("A5", 1), ("B5", .5), ("C6", .5), ("B5", 1),
             ("A5", 2), ("F5", 1), ("C5", 1),
             ("E5", 1), ("G5", 1), ("C6", 1), ("G5", 1),
             ("B5", 2), ("D5", 2),
             ("C5", 1), ("E5", 1), ("A5", 1), ("B5", 1),
             ("C6", 1.5), ("B5", .5), ("A5", 1), ("F5", 1),
             ("D5", 1), ("F5", 1), ("A5", 1), ("C6", 1),
             ("B5", 2), ("G#5", 2)]
    mel_b = [("A5", 1), ("C6", 1), ("A5", 1), ("F5", 1),
             ("G5", 1), ("B5", 1), ("D6", 2),
             ("E5", 1), ("G5", 1), ("B5", 1), ("G5", 1),
             ("A5", 3), ("E5", 1),
             ("F5", 1), ("A5", 1), ("D6", 1), ("C6", 1),
             ("B5", 1), ("G5", 1), ("D5", 1), ("G5", 1),
             ("E5", 1), ("G5", 1), ("C6", 2),
             ("G#5", 2), ("B5", 2)]

    def ostinato(bar, c, vel):
        up = c[1]
        pat = [up[0], up[2], up[1], up[2]] * 2
        for i, n in enumerate(pat):
            s.note("celesta", bar, i * 0.5, 0.5, m(n) + 12, vel * (1.0 if i % 2 == 0 else 0.75), -0.3, track="ost")

    bar = 0
    for c in A[:4]:
        ostinato(bar, c, 0.3)
        bar += 1
    for sec, mel in ((A, mel_a), (B, mel_b), (A, mel_a), (B, mel_b)):
        start = bar
        for c in sec:
            ostinato(bar, c, 0.24)
            offbeats(s, bar, c, 0.35)
            walking_bass(s, bar, c, 0.6, (0, 1.5, 2, 3.5) if sec is B else (0, 2))
            s.pad(bar, 4, c[1], 0.3, cutoff=1000)
            bar += 1
        s.melody("celesta" if sec is A else "box", start, mel, 0.7, 0.15)
        if sec is B:
            s.melody("flute", start, mel, 0.22, -0.2, -12)
    s.note("bass", bar, 0, 4, "A2", 0.5)
    for k, n in enumerate(["A3", "C4", "E4", "A4"]):
        s.note("celesta", bar, k * 0.12, 4, m(n) + 12, 0.35)
    return s.render({"celesta": 1.0, "ost": 0.75, "pizz": 0.75, "bass": 0.9, "pad": 0.85, "box": 1.0, "flute": 0.8})


def summer():
    """C major, 92 bpm: the ending. Flute and kalimba over piano, with a light shaker."""
    S.seed(55)
    s = Song(92, 4, 36, tail=6.0)
    A = [ch("C3", "G3 C4 E4"), ch("B2", "G3 B3 D4"), ch("A2", "A3 C4 E4"), ch("F2", "A3 C4 F4"),
         ch("C3", "G3 C4 E4"), ch("G2", "G3 B3 D4"), ch("F2", "A3 C4 F4"), ch("G2", "F3 B3 D4")]
    B = [ch("F2", "A3 C4 F4"), ch("G2", "G3 B3 D4"), ch("E2", "G3 B3 E4"), ch("A2", "A3 C4 E4"),
         ch("F2", "A3 C4 F4"), ch("G2", "G3 B3 D4"), ch("C3", "G3 C4 E4"), ch("C3", "G3 C4 E4")]
    mel_a = [("E5", 1), ("G5", 1), ("C6", 1.5), ("B5", .5),
             ("B5", 1), ("G5", 1), ("D5", 2),
             ("C5", 1), ("E5", 1), ("A5", 1), ("G5", 1),
             ("F5", 1), ("A5", 1), ("C6", 2),
             ("G5", 1), ("E5", 1), ("C5", 1), ("E5", 1),
             ("D5", 1), ("G5", 1), ("B5", 2),
             ("A5", 1), ("G5", 1), ("F5", 1), ("A5", 1),
             ("G5", 4)]
    mel_b = [("A5", 2), ("C6", 2),
             ("B5", 2), ("D6", 2),
             ("G5", 1), ("E5", 1), ("B5", 2),
             ("A5", 1), ("C6", 1), ("E6", 2),
             ("C6", 1), ("A5", 1), ("F5", 2),
             ("D6", 1), ("B5", 1), ("G5", 2),
             ("C6", 4),
             (None, 4)]
    bar = 0
    for c in A[:4]:
        flowing(s, bar, c, 0.45)
        bar += 1
    for sec, mel, lead in ((A, mel_a, "kalimba"), (A, mel_a, "flute"), (B, mel_b, "flute"), (A, mel_a, "kalimba")):
        start = bar
        for c in sec:
            flowing(s, bar, c, 0.4)
            walking_bass(s, bar, c, 0.6, (0, 2, 3))
            shaker_bar(s, bar, 0.4)
            s.pad(bar, 4, c[1], 0.3)
            bar += 1
        s.melody(lead, start, mel, 0.8 if lead == "kalimba" else 0.6, 0.12)
        if lead == "flute":
            s.melody("kalimba", start, mel, 0.3, -0.3, -12)
    for k, n in enumerate(["C3", "G3", "C4", "E4", "G4", "C5"]):
        s.note("piano", bar, k * 0.1, 4, n, 0.4)
    s.melody("kalimba", bar, [("G5", 0.5), ("C6", 0.5), ("E6", 3)], 0.6)
    return s.render({"piano": 0.85, "kalimba": 1.0, "flute": 0.95, "bass": 0.9, "shaker": 0.75, "pad": 0.8})


TRACKS = {"valley_1": valley_1, "valley_2": valley_2, "lake_1": lake_1, "lake_2": lake_2, "summer": summer}


if __name__ == "__main__":
    names = sys.argv[1:] or list(TRACKS)
    for n in names:
        x = TRACKS[n]()
        write_ogg(os.path.join(ROOT, "audio", "music", n + ".ogg"), x, quality=2, mono=False)
        print("%-10s %6.1fs" % (n, len(x) / SR))
