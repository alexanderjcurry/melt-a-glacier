"""A tiny synthesis kit for the game's sounds and music.

Everything is built from oscillators, noise and filters (numpy + scipy), so
every sound is original and can be tweaked and rebuilt. Arrays are float64
mono (n,) or stereo (n, 2) at SR samples per second.
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
rng = np.random.default_rng(1)


def seed(s):
    global rng
    rng = np.random.default_rng(s)


def secs(n):
    return int(round(n * SR))


def t_axis(dur):
    return np.arange(secs(dur)) / SR


# --- Sources ---------------------------------------------------------------------------
def noise(dur):
    return rng.standard_normal(secs(dur))


def pink(dur):
    """1/f noise via a filtered white source (Paul Kellet's approximation)."""
    w = noise(dur)
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    return normalize(signal.lfilter(b, a, w), 1.0)


def brown(dur):
    w = noise(dur)
    return normalize(signal.lfilter([1.0], [1.0, -0.995], w), 1.0)


def osc(freq, dur, shape="sine", phase=0.0):
    """freq can be a number or an array (one value per sample) for sweeps."""
    n = secs(dur)
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    ph = 2 * np.pi * np.cumsum(f) / SR + phase
    if shape == "sine":
        return np.sin(ph)
    if shape == "saw":
        # band-limited enough for our purposes: a few harmonics summed
        out = np.zeros(n)
        f0 = float(np.max(f)) if n else 1.0
        kmax = max(1, min(40, int(SR / 2.2 / max(f0, 1.0))))
        for k in range(1, kmax + 1):
            out += np.sin(k * ph) / k
        return out * 0.6
    if shape == "square":
        out = np.zeros(n)
        f0 = float(np.max(f)) if n else 1.0
        kmax = max(1, min(40, int(SR / 2.2 / max(f0, 1.0))))
        for k in range(1, kmax + 1, 2):
            out += np.sin(k * ph) / k
        return out * 0.8
    if shape == "tri":
        out = np.zeros(n)
        for i, k in enumerate(range(1, 16, 2)):
            out += ((-1) ** i) * np.sin(k * ph) / (k * k)
        return out * 0.8
    raise ValueError(shape)


def glide(f0, f1, dur, curve="exp"):
    n = secs(dur)
    if curve == "exp":
        return f0 * (f1 / f0) ** np.linspace(0, 1, n)
    return np.linspace(f0, f1, n)


# --- Envelopes -------------------------------------------------------------------------
def env_exp(dur, decay, attack=0.002):
    t = t_axis(dur)
    e = np.exp(-t / max(decay, 1e-4))
    a = secs(attack)
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    return e


def env_adsr(dur, a=0.01, d=0.1, s=0.7, r=0.2):
    n = secs(dur)
    e = np.full(n, s)
    na, nd, nr = secs(a), secs(d), secs(r)
    na = min(na, n)
    e[:na] = np.linspace(0, 1, na)
    nd = min(nd, n - na)
    e[na:na + nd] = np.linspace(1, s, nd)
    nr = min(nr, n)
    if nr > 0:
        e[n - nr:] *= np.linspace(1, 0, nr) ** 1.5
    return e


def fade(x, fin=0.003, fout=0.01):
    x = x.copy()
    a, b = secs(fin), secs(fout)
    if a:
        x[:a] *= np.linspace(0, 1, a)[:, None] if x.ndim == 2 else np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)[:, None] if x.ndim == 2 else np.linspace(1, 0, b)
    return x


def smooth_random(dur, rate, lo=0.0, hi=1.0):
    """A slowly wandering control signal (value noise at `rate` points per second)."""
    n = secs(dur)
    pts = max(2, int(dur * rate) + 3)
    vals = rng.uniform(lo, hi, pts)
    xp = np.linspace(0, n, pts)
    # cosine interpolation, smoother than linear
    idx = np.arange(n)
    j = np.clip(np.searchsorted(xp, idx, side="right") - 1, 0, pts - 2)
    fr = (idx - xp[j]) / (xp[j + 1] - xp[j])
    fr = (1 - np.cos(fr * np.pi)) / 2
    return vals[j] * (1 - fr) + vals[j + 1] * fr


# --- Filters ---------------------------------------------------------------------------
def _sos(kind, f, order=2, q=None):
    nyq = SR / 2
    if kind == "bp":
        lo, hi = f
        return signal.butter(order, [max(lo, 10) / nyq, min(hi, nyq * 0.98) / nyq], "bandpass", output="sos")
    return signal.butter(order, min(f, nyq * 0.98) / nyq, {"lp": "lowpass", "hp": "highpass"}[kind], output="sos")


def lp(x, f, order=2):
    return signal.sosfilt(_sos("lp", f, order), x, axis=0)


def hp(x, f, order=2):
    return signal.sosfilt(_sos("hp", f, order), x, axis=0)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bp", (lo, hi), order), x, axis=0)


def peak(x, f, q):
    """A resonant band (high q = ringing, like a struck object)."""
    b, a = signal.iirpeak(min(f, SR / 2 * 0.95), q, SR)
    return signal.lfilter(b, a, x, axis=0)


def sweep(x, cut, kind="lp", block=256, q=0.707):
    """A filter whose cutoff moves: cut is an array (one value per sample) or a function of 0..1."""
    n = len(x)
    if callable(cut):
        cut = cut(np.linspace(0, 1, n))
    cut = np.broadcast_to(cut, (n,))
    out = np.zeros(n)
    z = np.zeros(2)
    for s in range(0, n, block):
        e = min(n, s + block)
        f = float(np.clip(cut[s], 30, SR * 0.45))
        w0 = 2 * np.pi * f / SR
        al = np.sin(w0) / (2 * q)
        c = np.cos(w0)
        if kind == "lp":
            b = np.array([(1 - c) / 2, 1 - c, (1 - c) / 2])
        elif kind == "hp":
            b = np.array([(1 + c) / 2, -(1 + c), (1 + c) / 2])
        else:  # band
            b = np.array([al, 0, -al])
        a = np.array([1 + al, -2 * c, 1 - al])
        b, a = b / a[0], a / a[0]
        out[s:e], z = signal.lfilter(b, a, x[s:e], zi=z)
    return out


# --- Instruments and tones ---------------------------------------------------------------
def pluck(freq, dur, bright=0.5, decay=0.996):
    """Karplus-Strong plucked string."""
    n = secs(dur)
    period = max(2, int(round(SR / freq)))
    burst = rng.uniform(-1, 1, period)
    burst = lp(burst, 800 + 9000 * bright)
    x = np.zeros(n)
    x[:period] = burst
    a = np.zeros(period + 2)
    a[0] = 1
    a[period] = -decay * 0.5
    a[period + 1] = -decay * 0.5
    y = signal.lfilter([1.0], a, x)
    return taper(y * env_adsr(dur, 0.001, 0.0, 1.0, min(0.05, dur * 0.3)), 0.2, 0.05)


def bell(freq, dur, partials=((1, 1, 1.0), (2.0, 0.5, 0.6), (2.76, 0.35, 0.35), (5.4, 0.2, 0.18), (8.93, 0.1, 0.1)), decay=1.2):
    """Additive bell/tine: (ratio, amp, decay factor) per partial."""
    t = t_axis(dur)
    out = np.zeros(len(t))
    for r, a, dk in partials:
        f = freq * r
        if f > SR * 0.45:
            continue
        out += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / (decay * dk))
    out[:secs(0.002)] *= np.linspace(0, 1, secs(0.002))
    return taper(out)


def taper(x, frac=0.3, max_len=0.25):
    """Ease the very end of a ringing tone down to zero (no click where it's cut off)."""
    n = min(int(len(x) * frac), secs(max_len))
    if n > 1:
        x = x.copy()
        x[-n:] *= np.cos(np.linspace(0, np.pi / 2, n)) ** 2
    return x


def fm_tone(freq, dur, ratio=1.0, index=2.0, index_decay=0.2, decay=1.0, attack=0.003):
    t = t_axis(dur)
    idx = index * np.exp(-t / index_decay)
    m = np.sin(2 * np.pi * freq * ratio * t)
    return taper(np.sin(2 * np.pi * freq * t + idx * m) * env_exp(dur, decay, attack))


def drop(f0=700, f1=1600, dur=0.12, decay=0.035):
    """A water droplet: a sine that slides up fast and dies away."""
    f = glide(f0, f1, dur)
    return taper(osc(f, dur) * env_exp(dur, decay, 0.001))


def click(dur=0.01, f=3000, q=6):
    x = noise(dur) * env_exp(dur, dur / 4, 0.0002)
    return peak(x, f, q)


# --- Space -----------------------------------------------------------------------------
_ir_cache = {}


def reverb_ir(length=2.0, damp=4500, seed_=7, early=True):
    key = (length, damp, seed_, early)
    if key in _ir_cache:
        return _ir_cache[key]
    r = np.random.default_rng(seed_)
    n = secs(length)
    t = np.arange(n) / SR
    ir = np.zeros((n, 2))
    for ch in range(2):
        w = r.standard_normal(n) * np.exp(-t * 6.9 / length)
        # darker as it decays
        w = sweep(w, lambda u: damp * (1 - 0.8 * u) + 400, "lp")
        ir[:, ch] = w
    if early:
        for _ in range(10):
            d = int(r.uniform(0.005, 0.06) * SR)
            ir[d, :] += r.uniform(0.2, 0.6) * np.array([r.choice([-1, 1]), r.choice([-1, 1])])
    ir /= np.sqrt(np.sum(ir ** 2, axis=0, keepdims=True))
    _ir_cache[key] = ir
    return ir


def reverb(x, wet=0.25, length=2.0, damp=4500, predelay=0.012):
    """Stereo convolution reverb. x mono or stereo; returns stereo with the tail."""
    xs = stereo(x)
    ir = reverb_ir(length, damp)
    pd = secs(predelay)
    n = len(xs) + len(ir) + pd
    out = np.zeros((n, 2))
    out[:len(xs)] += xs * (1 - wet * 0.5)
    for ch in range(2):
        w = signal.fftconvolve(xs[:, ch], ir[:, ch])
        out[pd:pd + len(w), ch] += w * wet
    return out


def stereo(x, pan=0.0, width=0.0):
    if x.ndim == 2:
        return x
    l = np.cos((pan + 1) * np.pi / 4)
    r = np.sin((pan + 1) * np.pi / 4)
    out = np.stack([x * l, x * r], axis=1) * np.sqrt(2)
    if width > 0:
        d = secs(0.011 * width)
        out[d:, 1] = out[d:, 1] * (1 - width * 0.5) + out[:-d, 1] * width * 0.5 if d else out[:, 1]
    return out


def mix(*parts, length=None):
    """Add arrays of different lengths (mono and stereo mixed -> stereo)."""
    st = any(p.ndim == 2 for p in parts)
    n = length or max(len(p) for p in parts)
    out = np.zeros((n, 2)) if st else np.zeros(n)
    for p in parts:
        p = stereo(p) if st else p
        m = min(n, len(p))
        out[:m] += p[:m]
    return out


def place(buf, x, at, gain=1.0):
    """Add x into buf starting at `at` seconds (grows nothing: clipped to buf)."""
    s = secs(at)
    if s >= len(buf):
        return
    if buf.ndim == 2 and x.ndim == 1:
        x = stereo(x)
    m = min(len(buf) - s, len(x))
    buf[s:s + m] += x[:m] * gain


def pad_to(x, dur):
    n = secs(dur)
    if len(x) >= n:
        return x[:n]
    shape = (n - len(x),) + x.shape[1:]
    return np.concatenate([x, np.zeros(shape)])


def normalize(x, peak_=0.9):
    m = np.max(np.abs(x))
    return x if m == 0 else x * (peak_ / m)


def rms_normalize(x, target_db=-18.0, peak_cap=0.95):
    rms = np.sqrt(np.mean(x ** 2)) + 1e-12
    g = 10 ** (target_db / 20) / rms
    x = x * g
    m = np.max(np.abs(x))
    if m > peak_cap:
        x = soft_clip(x / m * 1.15) * peak_cap / np.tanh(1.15)
    return x


def soft_clip(x):
    return np.tanh(x)


def trim_tail(x, thresh_db=-60):
    """Cut trailing silence (keeps a short fade)."""
    mono = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=1)
    th = np.max(mono) * 10 ** (thresh_db / 20)
    idx = np.nonzero(mono > th)[0]
    if len(idx) == 0:
        return x
    end = min(len(x), idx[-1] + secs(0.02))
    return fade(x[:end], 0, 0.02)


def make_loop(x, xfade=0.25):
    """Seamless loop: the end blends into the start (works for noisy or tonal sounds)."""
    X = secs(xfade)
    L = len(x) - X
    y = x[X:X + L].copy()
    a = np.linspace(0, 1, X)
    if x.ndim == 2:
        a = a[:, None]
    # equal-power blend
    y[L - X:] = x[L:L + X] * np.cos(a * np.pi / 2) + x[:X] * np.sin(a * np.pi / 2)
    return y


# --- Output ----------------------------------------------------------------------------
def write_ogg(path, x, quality=4, mono=None):
    """Write an Ogg Vorbis file through ffmpeg."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.asarray(x, dtype=np.float64)
    if mono is True and x.ndim == 2:
        x = x.mean(axis=1)
    if mono is False and x.ndim == 1:
        x = stereo(x)
    x = np.clip(x, -1, 1)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wavfile.write(tmp.name, SR, (x * 32767).astype(np.int16))
        name = tmp.name
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", name, "-c:a", "libvorbis",
                    "-q:a", str(quality), "-map_metadata", "-1", path], check=True)
    os.unlink(name)
