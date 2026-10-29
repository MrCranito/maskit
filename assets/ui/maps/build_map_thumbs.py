#!/usr/bin/env python3
"""Vignettes provisoires des biomes pour la sélection de carte : assets/ui/maps/<biome>.png (640x360).

Usage : python3 assets/ui/maps/build_map_thumbs.py [capture_far_west.png]
  - far_west : recadrage d'une capture du jeu (rue de Dust Creek) étalonnée en coucher de soleil,
    si une capture est donnée ; sinon silhouette de ville peinte.
  - space_station, mall : illustrations peintes en code (dégradés, silhouettes, lumières).
Les agents biomes peuvent remplacer chaque PNG par un vrai rendu (même nom, 16:9) : MapCard
charge assets/ui/maps/<biome>.png à l'exécution.
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

W, H = 640, 360
S = 2  # suréchantillonnage (anticrénelage)
OUT = os.path.dirname(os.path.abspath(__file__))


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def vgrad(w, h, stops):
    """Dégradé vertical : stops = [(t, (r,g,b)), ...]."""
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        for i in range(len(stops) - 1):
            if stops[i][0] <= t <= stops[i + 1][0]:
                k = (t - stops[i][0]) / max(stops[i + 1][0] - stops[i][0], 1e-6)
                c = lerp(stops[i][1], stops[i + 1][1], k)
                break
        else:
            c = stops[-1][1]
        for x in range(w):
            px[x, y] = c
    return img


def glow(size, center, radius, color, alpha=200):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=color + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.45))


def vignette(img, strength=0.55):
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse([-w * 0.25, -h * 0.35, w * 1.25, h * 1.35], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(w * 0.08))
    dark = Image.new("RGB", (w, h), (8, 10, 22))
    return Image.composite(img, Image.blend(img, dark, strength), mask)


def finish(img, name):
    img = img.resize((W, H), Image.LANCZOS) if img.size != (W, H) else img
    img = vignette(img.convert("RGB"), 0.5)
    img.save(os.path.join(OUT, name + ".png"))
    print("écrit", name)


# --- Far West -------------------------------------------------------------------------

def far_west(capture):
    if capture and os.path.exists(capture):
        src = Image.open(capture).convert("RGB")
        # Rue principale (sans HUD ni bandeau) : 960x540 → 640x360
        box = (160, 110, 160 + 960, 110 + 540)
        img = src.crop(box).resize((W, H), Image.LANCZOS)
        img = ImageEnhance.Color(img).enhance(1.12)
        warm = vgrad(W, H, [(0, (250, 140, 90)), (1, (120, 60, 110))])
        img = Image.blend(img, warm, 0.16)
        top = glow((W, H), (W * 0.72, -40), 260, (255, 170, 110), 150)
        img = Image.alpha_composite(img.convert("RGBA"), top).convert("RGB")
        finish(img, "far_west")
        return
    w, h = W * S, H * S
    img = vgrad(w, h, [(0, (70, 40, 100)), (0.45, (235, 110, 120)), (0.75, (250, 170, 90)), (1, (90, 50, 60))])
    img = Image.alpha_composite(img.convert("RGBA"), glow((w, h), (w * 0.6, h * 0.62), 120, (255, 220, 150), 230))
    d = ImageDraw.Draw(img)
    rnd = random.Random(3)
    x = -20
    while x < w:
        bw = rnd.randint(90, 200)
        bh = rnd.randint(120, 260)
        d.rectangle([x, h * 0.75 - bh, x + bw, h], fill=(22, 18, 34))
        x += bw + rnd.randint(10, 60)
    d.rectangle([0, h * 0.75, w, h], fill=(30, 22, 36))
    finish(img, "far_west")


# --- Station spatiale -----------------------------------------------------------------

def space_station():
    w, h = W * S, H * S
    rnd = random.Random(7)
    img = vgrad(w, h, [(0, (8, 10, 30)), (0.6, (30, 22, 70)), (1, (70, 30, 90))]).convert("RGBA")
    d = ImageDraw.Draw(img)
    for _ in range(420):
        x, y = rnd.random() * w, rnd.random() * h
        r = rnd.choice([1, 1, 1, 2, 2, 3])
        a = rnd.randint(120, 255)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(220, 230, 255, a))
    # Nébuleuse
    img = Image.alpha_composite(img, glow((w, h), (w * 0.2, h * 0.3), 260, (120, 60, 200), 90))
    img = Image.alpha_composite(img, glow((w, h), (w * 0.35, h * 0.15), 180, (60, 140, 220), 70))
    # Planète
    planet = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    pd = ImageDraw.Draw(planet)
    pc = (w * 0.86, h * 1.25)
    pr = h * 0.75
    img = Image.alpha_composite(img, glow((w, h), pc, pr * 1.08, (90, 200, 255), 160))
    pd.ellipse([pc[0] - pr, pc[1] - pr, pc[0] + pr, pc[1] + pr], fill=(30, 70, 120, 255))
    for i in range(9):
        yy = pc[1] - pr + i * pr * 0.2
        pd.arc([pc[0] - pr, yy - 40, pc[0] + pr, yy + 40], 180, 360, fill=(60, 120, 170, 160), width=10)
    img = Image.alpha_composite(img, planet)
    # Station : anneau + moyeu + modules
    st = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(st)
    cx, cy = w * 0.42, h * 0.5
    R = h * 0.34
    sd.ellipse([cx - R, cy - R * 0.42, cx + R, cy + R * 0.42], outline=(150, 165, 190, 255), width=26)
    sd.ellipse([cx - R + 13, cy - R * 0.42 + 8, cx + R - 13, cy + R * 0.42 - 8], outline=(70, 80, 105, 255), width=6)
    for a in range(0, 360, 45):
        ang = math.radians(a)
        sd.line([cx, cy, cx + math.cos(ang) * R, cy + math.sin(ang) * R * 0.42], fill=(110, 120, 145, 255), width=8)
    sd.rectangle([cx - 30, cy - 120, cx + 30, cy + 120], fill=(120, 132, 158, 255))
    sd.rectangle([cx - 90, cy - 26, cx + 90, cy + 26], fill=(95, 105, 132, 255))
    sd.ellipse([cx - 44, cy - 44, cx + 44, cy + 44], fill=(160, 172, 196, 255))
    # Panneaux solaires
    for side in (-1, 1):
        px0 = cx + side * (R + 40)
        sd.rectangle([min(px0, px0 + side * 210), cy - 50, max(px0, px0 + side * 210), cy + 50], fill=(30, 60, 120, 255), outline=(120, 170, 230, 255), width=4)
        for k in range(1, 6):
            xx = px0 + side * 35 * k
            sd.line([xx, cy - 50, xx, cy + 50], fill=(80, 130, 200, 255), width=2)
        sd.line([cx + side * R, cy, px0, cy], fill=(110, 120, 145, 255), width=8)
    img = Image.alpha_composite(img, st)
    # Hublots allumés
    lights = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lights)
    for a in range(0, 360, 15):
        ang = math.radians(a)
        x = cx + math.cos(ang) * R
        y = cy + math.sin(ang) * R * 0.42
        ld.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(110, 240, 255, 255))
    for k in range(-3, 4):
        ld.rectangle([cx - 8 + k * 0, cy - 100 + 30 * (k + 3), cx + 8, cy - 92 + 30 * (k + 3)], fill=(255, 210, 120, 255))
    img = Image.alpha_composite(img, lights.filter(ImageFilter.GaussianBlur(6)))
    img = Image.alpha_composite(img, lights)
    img = Image.alpha_composite(img, glow((w, h), (cx, cy), 60, (120, 230, 255), 120))
    finish(img.convert("RGB"), "space_station")


# --- Centre commercial ----------------------------------------------------------------

def mall():
    w, h = W * S, H * S
    rnd = random.Random(11)
    img = vgrad(w, h, [(0, (28, 16, 46)), (0.55, (60, 30, 80)), (1, (24, 16, 34))]).convert("RGBA")
    d = ImageDraw.Draw(img)
    # Trois étages de galeries (balcons) avec vitrines
    neon = [(255, 90, 180), (90, 220, 255), (255, 200, 90), (170, 110, 255), (120, 255, 170)]
    floors_y = [h * 0.08, h * 0.36, h * 0.64]
    glow_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    for fi, fy in enumerate(floors_y):
        fh = h * 0.24
        d.rectangle([0, fy, w, fy + fh], fill=(44 + fi * 6, 30 + fi * 4, 60 + fi * 6, 255))
        x = 30
        while x < w - 60:
            sw = rnd.randint(150, 230)
            col = rnd.choice(neon)
            lit = rnd.random() > 0.25
            shop = [x, fy + fh * 0.28, x + sw, fy + fh - 10]
            d.rectangle(shop, fill=(20, 16, 30, 255), outline=(90, 80, 110, 255), width=4)
            if lit:
                d.rectangle([shop[0] + 8, shop[1] + 8, shop[2] - 8, shop[3] - 6], fill=tuple(int(c * 0.35) for c in col) + (255,))
                gd.rectangle([x + 16, fy + fh * 0.08, x + sw - 16, fy + fh * 0.22], fill=col + (255,))
            d.rectangle([x + 16, fy + fh * 0.08, x + sw - 16, fy + fh * 0.22], fill=(col if lit else (60, 50, 70)) + (255,))
            # Vitrine brisée
            if rnd.random() > 0.6:
                bx = rnd.randint(shop[0] + 20, shop[2] - 40)
                by = rnd.randint(int(shop[1]) + 10, int(shop[3]) - 30)
                for _ in range(4):
                    d.line([bx, by, bx + rnd.randint(-40, 40), by + rnd.randint(-30, 30)], fill=(200, 210, 230, 200), width=2)
            x += sw + rnd.randint(18, 40)
        # Garde-corps du balcon
        d.rectangle([0, fy + fh, w, fy + fh + 14], fill=(150, 150, 170, 255))
        d.rectangle([0, fy + fh + 14, w, fy + fh + 30], fill=(30, 22, 40, 255))
        for k in range(0, w, 34):
            d.line([k, fy + fh - 26, k, fy + fh], fill=(170, 170, 190, 200), width=3)
        d.line([0, fy + fh - 26, w, fy + fh - 26], fill=(200, 200, 220, 255), width=5)
    img = Image.alpha_composite(img, glow_layer.filter(ImageFilter.GaussianBlur(18)))
    # Escalator en diagonale
    esc = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ed = ImageDraw.Draw(esc)
    x0, y0, x1, y1 = w * 0.55, h * 0.98, w * 0.86, h * 0.34
    ed.polygon([(x0, y0), (x0 + 110, y0), (x1 + 110, y1), (x1, y1)], fill=(70, 66, 86, 255))
    for i in range(18):
        t = i / 18
        xa = x0 + (x1 - x0) * t
        ya = y0 + (y1 - y0) * t
        ed.line([xa, ya, xa + 110, ya], fill=(120, 116, 140, 255), width=4)
    ed.line([(x0, y0), (x1, y1)], fill=(220, 220, 235, 255), width=10)
    ed.line([(x0 + 110, y0), (x1 + 110, y1)], fill=(220, 220, 235, 255), width=10)
    img = Image.alpha_composite(img, esc)
    # Sol carrelé en bas + reflets
    d = ImageDraw.Draw(img)
    # Lumière de verrière
    img = Image.alpha_composite(img, glow((w, h), (w * 0.3, -60), 300, (255, 160, 220), 110))
    finish(img.convert("RGB"), "mall")


if __name__ == "__main__":
    far_west(sys.argv[1] if len(sys.argv) > 1 else "")
    space_station()
    mall()
