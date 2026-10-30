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

def mall(capture=""):
    """Vignette des Galeries Lumière : recadrage 16:9 du rendu pré-calculé (mini-carte du paquet
    assets/prerender/mall/<seed>/minimap.webp, ou toute image donnée) centré sur l'atrium ; sinon
    illustration peinte."""
    if not capture:
        root = os.path.join(OUT, "..", "..", "prerender", "mall")
        if os.path.isdir(root):
            for s in sorted(os.listdir(root)):
                p = os.path.join(root, s, "minimap.webp")
                if os.path.exists(p):
                    capture = p
    if capture and os.path.exists(capture):
        src = Image.open(capture).convert("RGB")
        sw, sh = src.size
        cw = int(sw * 0.9)
        ch = int(cw * H / W)
        cx, cy = sw * 0.5, sh * 0.44
        box = (int(cx - cw / 2), int(cy - ch / 2), int(cx + cw / 2), int(cy + ch / 2))
        img = src.crop(box).resize((W, H), Image.LANCZOS)
        img = ImageEnhance.Contrast(img).enhance(1.08)
        finish(img, "mall")
        return
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


# --- Terres gelées (agent Terres gelées) ---------------------------------------------------

def frozen_lands(capture=""):
    """Vignette des Terres gelées : recadrage 16:9 du rendu pré-calculé (mini-carte du paquet
    assets/prerender/frozen_lands/<seed>/minimap.webp, ou toute image donnée) centré sur le
    laboratoire aux cristaux ; sinon illustration peinte (plateau de glace, base, cristal)."""
    if not capture:
        root = os.path.join(OUT, "..", "..", "prerender", "frozen_lands")
        if os.path.isdir(root):
            for s in sorted(os.listdir(root)):
                p = os.path.join(root, s, "minimap.webp")
                if os.path.exists(p):
                    capture = p
    if capture and os.path.exists(capture):
        src = Image.open(capture).convert("RGB")
        sw, sh = src.size
        # Cadre 16:9 autour du centre (le labo circulaire est au centre du plan, un peu haut).
        cw = int(sw * 0.78)
        ch = int(cw * H / W)
        cx, cy = sw * 0.5, sh * 0.49
        box = (int(cx - cw / 2), int(cy - ch / 2), int(cx + cw / 2), int(cy + ch / 2))
        img = src.crop(box).resize((W, H), Image.LANCZOS)
        img = ImageEnhance.Contrast(img).enhance(1.12)
        img = ImageEnhance.Color(img).enhance(1.1)
        finish(img, "frozen_lands")
        return
    w, h = W * S, H * S
    img = vgrad(w, h, [(0.0, (8, 14, 36)), (0.5, (14, 28, 56)), (1.0, (40, 70, 110))]).convert("RGBA")
    d = ImageDraw.Draw(img)
    rnd = random.Random(5)
    # Plateau de glace (ellipse bruitée) et banquise
    pts = []
    for a in range(0, 360, 6):
        r = 1.0 + rnd.uniform(-0.08, 0.08)
        pts.append((w * 0.5 + math.cos(math.radians(a)) * w * 0.42 * r, h * 0.58 + math.sin(math.radians(a)) * h * 0.46 * r))
    d.polygon(pts, fill=(96, 150, 200, 255))
    pts2 = [(x, y - 14 * S) for (x, y) in pts]
    d.polygon(pts2, fill=(214, 228, 242, 255))
    # Base en croix : bunkers gris et cour centrale
    cx, cy = w * 0.5, h * 0.55
    for (x0, y0, x1, y1) in [(-0.22, -0.07, 0.22, 0.07), (-0.07, -0.26, 0.07, 0.2), (-0.3, -0.2, -0.12, -0.08), (0.12, -0.2, 0.3, -0.08)]:
        d.rectangle([cx + x0 * w, cy + y0 * h, cx + x1 * w, cy + y1 * h], fill=(78, 86, 100, 255), outline=(30, 34, 46, 255), width=3)
        d.rectangle([cx + x0 * w, cy + y0 * h, cx + x1 * w, cy + y0 * h + 10 * S], fill=(200, 212, 226, 255))
    # Laboratoire circulaire + cristal
    r = h * 0.11
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(40, 62, 92, 255), outline=(150, 190, 230, 255), width=4)
    img = Image.alpha_composite(img, glow((w, h), (cx, cy), int(r * 1.6), (90, 200, 255), 170))
    d = ImageDraw.Draw(img)
    d.polygon([(cx, cy - r * 0.9), (cx + r * 0.35, cy + r * 0.3), (cx - r * 0.35, cy + r * 0.3)], fill=(170, 235, 255, 255))
    d.polygon([(cx + r * 0.4, cy - r * 0.5), (cx + r * 0.65, cy + r * 0.3), (cx + r * 0.15, cy + r * 0.3)], fill=(120, 205, 250, 255))
    # Héliport et lumières rouges
    hx, hy = w * 0.2, h * 0.3
    d.rectangle([hx - 40 * S, hy - 30 * S, hx + 40 * S, hy + 30 * S], fill=(60, 68, 84, 255))
    d.ellipse([hx - 22 * S, hy - 22 * S, hx + 22 * S, hy + 22 * S], outline=(250, 190, 60, 255), width=4)
    for _ in range(8):
        px, py = rnd.uniform(w * 0.2, w * 0.8), rnd.uniform(h * 0.25, h * 0.85)
        img = Image.alpha_composite(img, glow((w, h), (px, py), 14 * S, (255, 60, 50), 180))
    # Flocons
    d = ImageDraw.Draw(img)
    for _ in range(260):
        px, py = rnd.uniform(0, w), rnd.uniform(0, h)
        rr = rnd.uniform(1, 3) * S
        d.ellipse([px - rr, py - rr, px + rr, py + rr], fill=(240, 248, 255, rnd.randint(90, 200)))
    finish(img.convert("RGB"), "frozen_lands")


# --- Carnaval hanté (agent Carnaval) -----------------------------------------------------

def haunted_carnival(capture=""):
    """Vignette du Carnaval hanté : recadrage 16:9 du rendu pré-calculé (mini-carte du paquet
    assets/prerender/haunted_carnival/<seed>/minimap.webp, ou toute image donnée) centré sur le
    chapiteau ; sinon illustration peinte (chapiteau rayé, grande roue, nuit violette)."""
    if not capture:
        root = os.path.join(OUT, "..", "..", "prerender", "haunted_carnival")
        if os.path.isdir(root):
            for s in sorted(os.listdir(root)):
                p = os.path.join(root, s, "minimap.webp")
                if os.path.exists(p):
                    capture = p
    if capture and os.path.exists(capture):
        src = Image.open(capture).convert("RGB")
        sw, sh = src.size
        # Cadre 16:9 : largeur du parc, centré sur le chapiteau (≈ 40 % de la hauteur du plan).
        cw = int(sw * 0.8)
        ch = int(cw * 9 / 16)
        cx, cy = sw * 0.5, sh * 0.42
        box = (int(cx - cw / 2), int(cy - ch / 2), int(cx + cw / 2), int(cy + ch / 2))
        img = src.crop(box).resize((W, H), Image.LANCZOS)
        img = ImageEnhance.Color(img).enhance(1.15)
        img = ImageEnhance.Contrast(img).enhance(1.08)
        finish(img, "haunted_carnival")
        return
    w, h = W * S, H * S
    rnd = random.Random(5)
    img = vgrad(w, h, [(0, (18, 8, 36)), (0.6, (70, 24, 96)), (1, (30, 12, 44))]).convert("RGBA")
    d = ImageDraw.Draw(img)
    # Grande roue à gauche
    cx, cy, r = w * 0.22, h * 0.48, h * 0.34
    for k in range(16):
        a = k / 16 * math.tau
        d.line([cx, cy, cx + math.cos(a) * r, cy + math.sin(a) * r], fill=(230, 90, 160, 255), width=3)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 120, 200, 255), width=6)
    d.ellipse([cx - r * 0.55, cy - r * 0.55, cx + r * 0.55, cy + r * 0.55], outline=(255, 200, 120, 255), width=3)
    glow_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glow_layer = Image.alpha_composite(glow_layer, glow((w, h), (cx, cy), r * 1.1, (255, 60, 200), 140))
    # Chapiteau rayé à droite
    tx, ty, tw, th = w * 0.68, h * 0.62, w * 0.42, h * 0.34
    for k in range(18):
        a0 = k / 18 * math.tau
        a1 = (k + 1) / 18 * math.tau
        col = (190, 30, 50, 255) if k % 2 else (235, 220, 210, 255)
        d.polygon([(tx, ty - th * 0.9), (tx + math.cos(a0) * tw / 2, ty + math.sin(a0) * th * 0.4), (tx + math.cos(a1) * tw / 2, ty + math.sin(a1) * th * 0.4)], fill=col)
    d.rectangle([tx - tw * 0.5, ty + th * 0.1, tx + tw * 0.5, ty + th * 0.75], fill=(120, 40, 120, 255))
    glow_layer = Image.alpha_composite(glow_layer, glow((w, h), (tx, ty + th * 0.4), tw * 0.5, (180, 80, 255), 150))
    # Sol pavé + guirlandes
    d.rectangle([0, h * 0.84, w, h], fill=(48, 30, 56, 255))
    for k in range(0, w, 26):
        d.ellipse([k, h * 0.18 + 14 * math.sin(k / 60), k + 8, h * 0.18 + 8 + 14 * math.sin(k / 60)], fill=(255, 210, 120, 255))
    img = Image.alpha_composite(img, glow_layer.filter(ImageFilter.GaussianBlur(24)))
    finish(img.convert("RGB"), "haunted_carnival")


# --- Pyramides d'Égypte (agent Pyramides) ----------------------------------------------------

def egypt_pyramids(capture=""):
    """Vignette des Pyramides d'Égypte : recadrage 16:9 du rendu pré-calculé (mini-carte du paquet
    assets/prerender/egypt_pyramids/<seed>/minimap.webp, ou toute image donnée) centré sur le grand
    temple ; sinon illustration peinte (pyramides au couchant, temple doré)."""
    if not capture:
        root = os.path.join(OUT, "..", "..", "prerender", "egypt_pyramids")
        if os.path.isdir(root):
            for s in sorted(os.listdir(root)):
                p = os.path.join(root, s, "minimap.webp")
                if os.path.exists(p):
                    capture = p
    if capture and os.path.exists(capture):
        src = Image.open(capture).convert("RGB")
        sw, sh = src.size
        cw = int(sw * 0.82)
        ch = int(cw * H / W)
        cx, cy = sw * 0.5, sh * 0.5
        box = (int(cx - cw / 2), int(cy - ch / 2), int(cx + cw / 2), int(cy + ch / 2))
        img = src.crop(box).resize((W, H), Image.LANCZOS)
        img = ImageEnhance.Contrast(img).enhance(1.1)
        img = ImageEnhance.Color(img).enhance(1.12)
        warm = vgrad(W, H, [(0, (255, 170, 90)), (1, (120, 50, 40))])
        img = Image.blend(img, warm, 0.1)
        finish(img, "egypt_pyramids")
        return
    w, h = W * S, H * S
    rnd = random.Random(9)
    img = vgrad(w, h, [(0.0, (90, 40, 70)), (0.4, (240, 120, 70)), (0.62, (255, 190, 110)), (1.0, (200, 140, 70))]).convert("RGBA")
    img = Image.alpha_composite(img, glow((w, h), (w * 0.3, h * 0.55), 160, (255, 230, 170), 220))
    d = ImageDraw.Draw(img)
    # Dunes
    d.polygon([(0, h * 0.62), (w * 0.3, h * 0.56), (w * 0.6, h * 0.64), (w, h * 0.58), (w, h), (0, h)], fill=(214, 160, 88, 255))
    d.polygon([(0, h * 0.78), (w * 0.4, h * 0.72), (w * 0.8, h * 0.8), (w, h * 0.74), (w, h), (0, h)], fill=(232, 182, 104, 255))
    # Pyramides
    for (px, base, hh, c1, c2) in [(w * 0.78, w * 0.42, h * 0.5, (200, 150, 84), (120, 78, 42)), (w * 0.52, w * 0.26, h * 0.32, (210, 158, 90), (130, 84, 46)),
                                   (w * 0.14, w * 0.22, h * 0.26, (205, 152, 86), (125, 80, 44))]:
        d.polygon([(px - base / 2, h * 0.64), (px, h * 0.64 - hh), (px + base / 2, h * 0.64)], fill=c2)
        d.polygon([(px - base / 2, h * 0.64), (px, h * 0.64 - hh), (px - base * 0.05, h * 0.64)], fill=c1)
    # Temple doré au premier plan : pylônes, colonnes, sanctuaire
    tx, ty = w * 0.42, h * 0.86
    d.rectangle([tx - 200 * S, ty - 90 * S, tx + 200 * S, ty], fill=(190, 140, 80, 255), outline=(70, 40, 20, 255), width=3)
    for k in range(8):
        cx = tx - 170 * S + k * 48 * S
        d.rectangle([cx - 8 * S, ty - 80 * S, cx + 8 * S, ty], fill=(230, 190, 120, 255), outline=(70, 40, 20, 255), width=2)
    d.rectangle([tx - 60 * S, ty - 120 * S, tx + 60 * S, ty - 40 * S], fill=(222, 170, 60, 255), outline=(70, 40, 20, 255), width=3)
    img = Image.alpha_composite(img, glow((w, h), (tx, ty - 80 * S), 90 * S, (255, 200, 90), 150))
    d = ImageDraw.Draw(img)
    for k in range(6):
        px, py = tx - 180 * S + k * 72 * S, ty - 60 * S
        d.ellipse([px - 5 * S, py - 5 * S, px + 5 * S, py + 5 * S], fill=(255, 150, 50, 255))
    finish(img.convert("RGB"), "egypt_pyramids")


if __name__ == "__main__":
    far_west(sys.argv[1] if len(sys.argv) > 1 else "")
    space_station()
    mall()
    frozen_lands()
    haunted_carnival()
    egypt_pyramids()
