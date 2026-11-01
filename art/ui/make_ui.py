"""Draws the HUD's textures into ui/*.png: a wooden sign, a sheet of paper,
an enamel button, a progress bar and the round phone buttons. They are
nine-patch images (see UiTheme), drawn 4x large and scaled down for clean
edges. Grey parts are tinted in the game, so one button image does every colour.

    pip install pillow && python art/ui/make_ui.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "ui")
S = 4   # supersampling
INK = (58, 36, 22, 255)


def save(img, name):
    img = img.resize((img.width // S, img.height // S), Image.LANCZOS)
    img.save(os.path.join(OUT, name + ".png"))
    print("wrote ui/%s.png %dx%d" % (name, img.width, img.height))


def wobble_rect(w, h, r, inset, seed, amp=1.2):
    """Points round a rounded rectangle with a slightly hand-cut edge."""
    rng = random.Random(seed)
    pts = []
    corners = [(w - inset - r, inset + r, -90), (w - inset - r, h - inset - r, 0), (inset + r, h - inset - r, 90),
               (inset + r, inset + r, 180)]
    for cx, cy, a0 in corners:
        for k in range(10):
            a = math.radians(a0 + 90 * k / 9)
            jitter = rng.uniform(-amp, amp) * S
            pts.append((cx + math.cos(a) * (r + jitter), cy + math.sin(a) * (r + jitter)))
    return pts


def shadow(base, pts, offset, blur, alpha):
    sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    d.polygon([(x + offset[0], y + offset[1]) for x, y in pts], fill=(0, 0, 0, alpha))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    return Image.alpha_composite(sh, base)


def mask_from(pts, size):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def wood_sign():
    w, h = 160 * S, 96 * S
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    pts = wobble_rect(w, h, 10 * S, 6 * S, 1)
    # Planks: base colour, grain streaks, and a seam.
    wood = Image.new("RGBA", (w, h), (150, 98, 58, 255))
    d = ImageDraw.Draw(wood)
    rng = random.Random(3)
    for k in range(60):
        y = rng.uniform(0, h)
        c = rng.choice([(128, 82, 47), (166, 112, 68), (138, 90, 52)])
        d.line([(0, y), (w, y + rng.uniform(-6, 6) * S)], fill=c + (255,), width=int(rng.uniform(1, 3) * S))
    d.line([(0, h * 0.5), (w, h * 0.5)], fill=(96, 60, 34, 255), width=2 * S)
    # Lighter top edge, darker bottom edge of each plank.
    for y0 in (6 * S, h * 0.5 + S):
        d.line([(0, y0 + 2 * S), (w, y0 + 2 * S)], fill=(184, 132, 86, 255), width=2 * S)
    m = mask_from(pts, (w, h))
    img.paste(wood, (0, 0), m)
    d = ImageDraw.Draw(img)
    d.line(pts + [pts[0]], fill=INK, width=3 * S, joint="curve")
    # Nails in the corners (inside the nine-patch margins, so they never stretch).
    for nx, ny in ((16, 16), (w // S - 16, 16), (16, h // S - 16), (w // S - 16, h // S - 16)):
        nx, ny = nx * S, ny * S
        d.ellipse([nx - 4 * S, ny - 4 * S, nx + 4 * S, ny + 4 * S], fill=(70, 70, 76, 255), outline=INK, width=S)
        d.ellipse([nx - 2 * S, ny - 3 * S, nx + 1 * S, ny], fill=(170, 170, 180, 255))
    img = shadow(img, pts, (0, 4 * S), 4 * S, 110)
    save(img, "wood_sign")


def paper():
    w, h = 160 * S, 160 * S
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    pts = wobble_rect(w, h, 6 * S, 8 * S, 5, amp=2.0)
    sheet = Image.new("RGBA", (w, h), (248, 238, 214, 255))
    d = ImageDraw.Draw(sheet)
    rng = random.Random(9)
    for k in range(500):   # paper fibres
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        a = rng.uniform(0, math.pi)
        ln = rng.uniform(2, 6) * S
        c = rng.choice([(242, 231, 206), (251, 243, 224), (244, 234, 211)])
        d.line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], fill=c + (255,), width=S)
    img.paste(sheet, (0, 0), mask_from(pts, (w, h)))
    d = ImageDraw.Draw(img)
    d.line(pts + [pts[0]], fill=(150, 112, 74, 255), width=2 * S, joint="curve")
    # A strip of tape at the top.
    tape = [(w * 0.5 - 22 * S, 2 * S), (w * 0.5 + 22 * S, 4 * S), (w * 0.5 + 21 * S, 18 * S), (w * 0.5 - 23 * S, 16 * S)]
    d.polygon(tape, fill=(236, 220, 160, 200))
    img = shadow(img, pts, (2 * S, 5 * S), 5 * S, 120)
    save(img, "paper")


def button(pressed):
    """Grey enamel sign button (tinted in game): ink outline, a lip at the bottom."""
    w, h = 96 * S, 72 * S
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    lip = 0 if pressed else 6 * S
    top = (6 if not pressed else 10) * S
    body = wobble_rect(w, h - 6 * S, 14 * S, 4 * S, 11, amp=0.6)
    body = [(x, y + (top - 4 * S)) for x, y in body]
    under = [(x, y + lip) for x, y in body]
    d = ImageDraw.Draw(img)
    if lip:
        d.polygon(under, fill=(120, 120, 120, 255))
        d.line(under + [under[0]], fill=INK, width=3 * S, joint="curve")
    d.polygon(body, fill=(222, 222, 222, 255))
    # Gloss band across the top.
    gl = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gl)
    ys = min(p[1] for p in body)
    gd.rounded_rectangle([12 * S, ys + 5 * S, w - 12 * S, ys + 15 * S], radius=5 * S, fill=(255, 255, 255, 120))
    img = Image.alpha_composite(img, gl)
    d = ImageDraw.Draw(img)
    d.line(body + [body[0]], fill=INK, width=3 * S, joint="curve")
    save(img, "button_down" if pressed else "button")


def bar():
    # Frame: a dark wooden slot. Fill: a grey (tinted) bar with a gloss stripe.
    w, h = 64 * S, 32 * S
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([2 * S, 2 * S, w - 2 * S, h - 2 * S], radius=12 * S, fill=(52, 36, 26, 230), outline=INK, width=3 * S)
    d.rounded_rectangle([7 * S, 7 * S, w - 7 * S, 11 * S], radius=2 * S, fill=(0, 0, 0, 70))
    save(img, "bar_frame")
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=9 * S, fill=(225, 225, 225, 255))
    d.rounded_rectangle([6 * S, 4 * S, w - 6 * S, 10 * S], radius=3 * S, fill=(255, 255, 255, 255))
    d.rectangle([0, h - 8 * S, w, h], fill=(190, 190, 190, 255))
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], radius=9 * S, fill=255)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(img, (0, 0), m)
    save(out, "bar_fill")


def disc():
    """The round phone buttons: a grey (tinted) enamel disc, ink rim, lip and gloss."""
    n = 256 * S
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = n // 2
    r = 112 * S
    lip = 8 * S
    d.ellipse([c - r, c - r + lip, c + r, c + r + lip], fill=(118, 118, 118, 255), outline=INK, width=5 * S)
    d.ellipse([c - r, c - r, c + r, c + r], fill=(220, 220, 220, 255), outline=INK, width=5 * S)
    d.ellipse([c - r + 14 * S, c - r + 14 * S, c + r - 14 * S, c + r - 14 * S], outline=(255, 255, 255, 110), width=4 * S)
    gl = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(gl).ellipse([c - r * 0.62, c - r * 0.86, c + r * 0.62, c - r * 0.3], fill=(255, 255, 255, 90))
    img = Image.alpha_composite(img, gl)
    save(img, "disc")
    # The joystick ring: a carved wooden hoop, see-through in the middle.
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([c - r, c - r, c + r, c + r], fill=(255, 255, 255, 40), outline=INK, width=5 * S)
    d.ellipse([c - r + 6 * S, c - r + 6 * S, c + r - 6 * S, c + r - 6 * S], outline=(245, 236, 214, 210), width=14 * S)
    d.ellipse([c - r + 20 * S, c - r + 20 * S, c + r - 20 * S, c + r - 20 * S], outline=INK, width=4 * S)
    for k in range(4):   # arrow notches
        a = k * math.pi / 2
        tip = (c + math.cos(a) * (r - 32 * S), c + math.sin(a) * (r - 32 * S))
        b1 = (c + math.cos(a + 0.12) * (r - 48 * S), c + math.sin(a + 0.12) * (r - 48 * S))
        b2 = (c + math.cos(a - 0.12) * (r - 48 * S), c + math.sin(a - 0.12) * (r - 48 * S))
        d.polygon([tip, b1, b2], fill=(245, 236, 214, 200))
    save(img, "stick_ring")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    wood_sign()
    paper()
    button(False)
    button(True)
    bar()
    disc()
