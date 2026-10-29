"""Génère les illustrations des menus et l'image de démarrage (boot splash).

Usage (depuis la racine du projet) :
    python3 assets/ui/menu/build_menu_art.py

Sorties :
    assets/ui/menu/sky.png        ciel de coucher de soleil (dégradé + soleil), 1280x720
    assets/ui/menu/town_far.png   silhouettes lointaines (mesas, ville), bande 2560x300
    assets/ui/menu/town_near.png  silhouettes proches (façades Far West), bande 2560x340
    assets/ui/menu/glow.png       halo radial blanc (à teinter via modulate), 256x256
    assets/ui/menu/vignette.png   vignettage doux, 640x360 (étiré)
    (l'image de démarrage boot.png est désormais produite par art/blender/build_menu_2d.py)

Tout est dessiné en code (PIL + numpy), couleurs de la planche de référence :
ciel orange / rose / violet, ombres bleu nuit (#121a2e).
"""
from __future__ import annotations

import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
MENU = os.path.join(ROOT, "assets/ui/menu")
SPLASH = os.path.join(ROOT, "assets/ui/splash")
RYE = os.path.join(ROOT, "assets/fonts/rye/Rye-Regular.ttf")
NUNITO = os.path.join(ROOT, "assets/fonts/nunito/Nunito-Variable.ttf")
MASK = os.path.join(ROOT, "assets/ui/masks/kitsune.png")

# Dégradé du ciel (haut -> horizon), position 0..1
SKY_STOPS = [
    (0.00, (18, 22, 52)),
    (0.22, (52, 36, 92)),
    (0.45, (128, 56, 112)),
    (0.66, (222, 92, 92)),
    (0.82, (250, 150, 80)),
    (1.00, (255, 206, 128)),
]
NIGHT = (18, 26, 46)
FAR_COL = (74, 44, 86)
MID_COL = (44, 32, 66)
NEAR_COL = (18, 20, 40)


def lerp(a, b, t):
    return a + (b - a) * t


def gradient(h: int, w: int, stops) -> np.ndarray:
    ys = np.linspace(0.0, 1.0, h)
    out = np.zeros((h, w, 3), np.float32)
    for c in range(3):
        xs = [s[0] for s in stops]
        vs = [s[1][c] for s in stops]
        out[:, :, c] = np.interp(ys, xs, vs)[:, None]
    return out


def add_glow(img: np.ndarray, cx: float, cy: float, radius: float, color, strength: float) -> None:
    h, w, _ = img.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / radius
    a = np.clip(1.0 - d, 0.0, 1.0) ** 2.2 * strength
    for c in range(3):
        img[:, :, c] = img[:, :, c] + (color[c] - img[:, :, c]) * a


def sky_image(w: int, h: int, horizon: float, sun=(0.5, 0.8), seed: int = 3) -> Image.Image:
    """Ciel : dégradé jusqu'à l'horizon (fraction de h), soleil + halo, bandes de nuages."""
    hz = int(h * horizon)
    arr = gradient(hz, w, SKY_STOPS)
    full = np.zeros((h, w, 3), np.float32)
    full[:hz] = arr
    full[hz:] = np.array(SKY_STOPS[-1][1], np.float32)
    sx, sy = w * sun[0], h * sun[1]
    add_glow(full, sx, sy, w * 0.55, (255, 170, 110), 0.55)
    add_glow(full, sx, sy, w * 0.18, (255, 225, 170), 0.8)
    img = Image.fromarray(np.clip(full, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    # Disque solaire
    d = ImageDraw.Draw(img)
    r = h * 0.085
    d.ellipse([sx - r, sy - r, sx + r, sy + r], fill=(255, 236, 190, 255))
    # Bandes de nuages étirées (rose / violet), floues
    clouds = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cd = ImageDraw.Draw(clouds)
    rng = random.Random(seed)
    for i in range(16):
        cy = rng.uniform(0.18, 0.72) * h
        cx = rng.uniform(-0.1, 1.1) * w
        cw = rng.uniform(0.18, 0.45) * w
        ch = rng.uniform(0.012, 0.03) * h
        t = cy / h
        col = (int(lerp(120, 255, t)), int(lerp(70, 140, t)), int(lerp(140, 120, t)), int(rng.uniform(70, 140)))
        cd.ellipse([cx - cw / 2, cy - ch, cx + cw / 2, cy + ch], fill=col)
    # Flou de l'alpha seulement (couleur pleine partout) : pas de frange sombre.
    ca = np.array(clouds).astype(np.float32)
    alpha = Image.fromarray(ca[:, :, 3].astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(h * 0.01))
    rgb = Image.fromarray(ca[:, :, :3].astype(np.uint8), "RGB").filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(h * 0.01))
    clouds = Image.merge("RGBA", (*rgb.split(), alpha))
    img = Image.alpha_composite(img, clouds)
    # Fine ligne lumineuse sur l'horizon
    return img


# --- Silhouettes -----------------------------------------------------------------

def facade(d: ImageDraw.ImageDraw, x: float, base: float, w: float, h: float, col, kind: str, rng: random.Random) -> None:
    """Façade Far West vue de face (fausse façade, saloon, église, réservoir…)."""
    if kind == "false_front":
        d.rectangle([x, base - h, x + w, base], fill=col)
        # Fronton à gradins
        step = w * 0.12
        d.rectangle([x + step, base - h - h * 0.12, x + w - step, base - h], fill=col)
        d.rectangle([x + step * 2.2, base - h - h * 0.2, x + w - step * 2.2, base - h], fill=col)
        # Auvent (porche) avec poteaux
        d.rectangle([x - w * 0.06, base - h * 0.42, x + w * 1.06, base - h * 0.37], fill=col)
    elif kind == "saloon":
        d.rectangle([x, base - h, x + w, base], fill=col)
        d.polygon([(x - 4, base - h), (x + w * 0.5, base - h * 1.25), (x + w + 4, base - h)], fill=col)
        d.rectangle([x - w * 0.08, base - h * 0.55, x + w * 1.08, base - h * 0.5], fill=col)  # balcon
        for k in range(5):
            px = x - w * 0.06 + k * (w * 1.12) / 4
            d.rectangle([px - 1.5, base - h * 0.55, px + 1.5, base], fill=col)
    elif kind == "church":
        d.rectangle([x, base - h, x + w, base], fill=col)
        d.polygon([(x - 3, base - h), (x + w / 2, base - h * 1.35), (x + w + 3, base - h)], fill=col)
        tw = w * 0.34
        tx = x + w / 2 - tw / 2
        d.rectangle([tx, base - h * 1.9, tx + tw, base - h], fill=col)
        d.polygon([(tx - 2, base - h * 1.9), (tx + tw / 2, base - h * 2.5), (tx + tw + 2, base - h * 1.9)], fill=col)
        cxm = tx + tw / 2
        d.rectangle([cxm - 1.5, base - h * 2.75, cxm + 1.5, base - h * 2.45], fill=col)
        d.rectangle([cxm - 6, base - h * 2.66, cxm + 6, base - h * 2.62], fill=col)
    elif kind == "water_tower":
        tw = w
        top = base - h
        d.rectangle([x, top, x + tw, top + h * 0.38], fill=col)
        d.polygon([(x - 4, top), (x + tw / 2, top - h * 0.18), (x + tw + 4, top)], fill=col)
        for lx in (x + tw * 0.12, x + tw * 0.82):
            d.rectangle([lx, top + h * 0.38, lx + 4, base], fill=col)
        d.line([(x + tw * 0.14, top + h * 0.4), (x + tw * 0.84, base)], fill=col, width=3)
        d.line([(x + tw * 0.84, top + h * 0.4), (x + tw * 0.14, base)], fill=col, width=3)
    elif kind == "windmill":
        cx = x + w / 2
        top = base - h
        d.polygon([(cx - w * 0.18, base), (cx - 3, top), (cx + 3, top), (cx + w * 0.18, base)], fill=col)
        for k in range(12):
            a = k * math.tau / 12 + 0.2
            d.line([(cx, top), (cx + math.cos(a) * w * 0.55, top + math.sin(a) * w * 0.55)], fill=col, width=4)
        d.ellipse([cx - w * 0.2, top - w * 0.2, cx + w * 0.2, top + w * 0.2], outline=col, width=3)
    elif kind == "cactus":
        d.rounded_rectangle([x + w * 0.4, base - h, x + w * 0.6, base], radius=w * 0.1, fill=col)
        d.rounded_rectangle([x, base - h * 0.75, x + w * 0.2, base - h * 0.35], radius=w * 0.1, fill=col)
        d.rectangle([x, base - h * 0.45, x + w * 0.5, base - h * 0.35], fill=col)
        d.rounded_rectangle([x + w * 0.8, base - h * 0.9, x + w, base - h * 0.5], radius=w * 0.1, fill=col)
        d.rectangle([x + w * 0.5, base - h * 0.6, x + w, base - h * 0.5], fill=col)
    elif kind == "pole":
        d.rectangle([x, base - h, x + 4, base], fill=col)
        d.rectangle([x - 14, base - h + 8, x + 18, base - h + 12], fill=col)


def town_band(w: int, h: int, col, kinds_seq, scale: float, seed: int, ground: float, hills=None, windows: bool = False) -> Image.Image:
    """Bande horizontale (raccordable en boucle) de silhouettes sur un sol plein."""
    ss = 2
    W, H = w * ss, h * ss
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    base = H * ground
    if hills is not None:
        # Mesas / collines lointaines (périodiques pour boucler)
        pts = [(0, H)]
        for i in range(0, 161):
            t = i / 160
            y = base - H * hills * (0.5 + 0.25 * math.sin(t * math.tau * 3 + 0.7) + 0.2 * math.sin(t * math.tau * 7 + 2.1))
            pts.append((t * W, y))
        pts.append((W, H))
        d.polygon(pts, fill=col)
        # Mesas à sommet plat
        for k in range(3):
            mx = (k + 0.3) * W / 3 + rng.uniform(-80, 80) * ss
            mw = rng.uniform(380, 620) * ss
            mh = rng.uniform(0.22, 0.34) * H
            # Mesa : plateau large, falaises raides puis éboulis en pente douce
            d.polygon([(mx - mw * 0.62, base), (mx - mw * 0.42, base - mh * 0.35), (mx - mw * 0.36, base - mh),
                       (mx + mw * 0.3, base - mh), (mx + mw * 0.38, base - mh * 0.4), (mx + mw * 0.6, base)], fill=col)
            bx = mx + mw * 0.5
            d.polygon([(bx - 40 * ss, base - mh * 0.3), (bx - 30 * ss, base - mh * 0.75), (bx + 10 * ss, base - mh * 0.75),
                       (bx + 18 * ss, base - mh * 0.3)], fill=col)
    x = rng.uniform(10, 40) * ss
    i = 0
    while x < W - 80 * ss:
        kind = kinds_seq[i % len(kinds_seq)]
        i += 1
        if kind == "gap":
            x += rng.uniform(60, 140) * ss * scale
            continue
        bw = rng.uniform(90, 150) * ss * scale
        bh = rng.uniform(70, 120) * ss * scale
        if kind == "church":
            bw, bh = 90 * ss * scale, 85 * ss * scale
        elif kind == "water_tower":
            bw, bh = 60 * ss * scale, 150 * ss * scale
        elif kind == "windmill":
            bw, bh = 70 * ss * scale, 170 * ss * scale
        elif kind == "cactus":
            bw, bh = 34 * ss * scale, 70 * ss * scale
        elif kind == "pole":
            bw, bh = 20 * ss * scale, 110 * ss * scale
        facade(d, x, base + 2, bw, bh, col, kind, rng)
        if windows and kind in ("false_front", "saloon", "church"):
            for _k in range(rng.randint(0, 3)):
                wx = x + rng.uniform(0.15, 0.75) * bw
                wy = base - rng.uniform(0.25, 0.7) * bh
                ww, wh = 9 * ss * scale, 13 * ss * scale
                warm = (255, rng.randint(170, 210), rng.randint(90, 130), 255)
                d.rectangle([wx, wy, wx + ww, wy + wh], fill=warm)
                d.line([(wx + ww / 2, wy), (wx + ww / 2, wy + wh)], fill=col, width=ss)
        x += bw + rng.uniform(4, 26) * ss * scale
    d.rectangle([0, base, W, H], fill=col)
    return img.resize((w, h), Image.LANCZOS)


def glow_texture(size: int = 256) -> Image.Image:
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2
    d = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / c
    a = np.clip(1.0 - d, 0, 1) ** 2.0
    arr = np.zeros((size, size, 4), np.uint8)
    arr[:, :, :3] = 255
    arr[:, :, 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def vignette_texture(w: int = 640, h: int = 360) -> Image.Image:
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx / (w - 1) - 0.5) * 2
    ny = (yy / (h - 1) - 0.5) * 2
    d = np.sqrt(nx ** 2 * 0.8 + ny ** 2)
    a = np.clip((d - 0.55) / 0.9, 0, 1) ** 1.6 * 0.85
    arr = np.zeros((h, w, 4), np.uint8)
    arr[:, :, 0], arr[:, :, 1], arr[:, :, 2] = NIGHT
    arr[:, :, 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def text_layer(size, text, font_path, font_size, fill, center, shadow=True, stroke=0, stroke_fill=None, weight=None, glow=None):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    f = ImageFont.truetype(font_path, font_size)
    if weight is not None:
        try:
            f.set_variation_by_axes([weight])
        except Exception:
            pass
    d = ImageDraw.Draw(layer)
    bbox = d.textbbox((0, 0), text, font=f, stroke_width=stroke)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = center[0] - tw / 2 - bbox[0]
    y = center[1] - th / 2 - bbox[1]
    if glow is not None:
        g = Image.new("RGBA", size, (0, 0, 0, 0))
        ImageDraw.Draw(g).text((x, y), text, font=f, fill=glow, stroke_width=stroke + 6, stroke_fill=glow)
        layer = Image.alpha_composite(layer, g.filter(ImageFilter.GaussianBlur(font_size * 0.18)))
    if shadow:
        s = Image.new("RGBA", size, (0, 0, 0, 0))
        ImageDraw.Draw(s).text((x + font_size * 0.04, y + font_size * 0.06), text, font=f, fill=(10, 12, 28, 200), stroke_width=stroke, stroke_fill=(10, 12, 28, 200))
        layer = Image.alpha_composite(layer, s.filter(ImageFilter.GaussianBlur(font_size * 0.03)))
    d = ImageDraw.Draw(layer)
    d.text((x, y), text, font=f, fill=fill, stroke_width=stroke, stroke_fill=stroke_fill)
    return layer


def dust(size, count, seed, color=(255, 214, 160)) -> Image.Image:
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rng = random.Random(seed)
    for _ in range(count):
        x = rng.uniform(0, size[0])
        y = rng.uniform(size[1] * 0.35, size[1])
        r = rng.uniform(1.0, 3.2)
        a = int(rng.uniform(40, 150))
        d.ellipse([x - r, y - r, x + r, y + r], fill=color + (a,))
    return layer.filter(ImageFilter.GaussianBlur(0.8))


def build_menu_layers() -> None:
    os.makedirs(MENU, exist_ok=True)
    sky = sky_image(1280, 720, 0.86, sun=(0.5, 0.74))
    sky.save(os.path.join(MENU, "sky.png"))
    far = town_band(2560, 300, FAR_COL, ["gap"], 1.0, 11, 0.86, hills=0.28)
    mid = town_band(2560, 300, MID_COL,
                    ["false_front", "church", "gap", "false_front", "water_tower", "saloon", "gap", "windmill", "false_front", "gap"],
                    0.62, 21, 0.9)
    far = Image.alpha_composite(far, mid)
    far.save(os.path.join(MENU, "town_far.png"))
    near = town_band(2560, 340, NEAR_COL,
                     ["saloon", "false_front", "cactus", "gap", "false_front", "pole", "church", "gap", "false_front",
                      "water_tower", "saloon", "cactus", "gap", "false_front", "pole"],
                     1.0, 37, 0.84, windows=True)
    near.save(os.path.join(MENU, "town_near.png"))
    glow_texture().save(os.path.join(MENU, "glow.png"))
    vignette_texture().save(os.path.join(MENU, "vignette.png"))


def build_boot_splash() -> None:
    os.makedirs(SPLASH, exist_ok=True)
    W, H = 1920, 1080
    img = sky_image(W, H, 0.86, sun=(0.5, 0.56))
    far = Image.open(os.path.join(MENU, "town_far.png")).resize((int(2560 * 1.5), int(300 * 1.5)), Image.LANCZOS)
    img.alpha_composite(far.crop((300, 0, 300 + W, far.height)), (0, H - far.height - 60))
    near = Image.open(os.path.join(MENU, "town_near.png")).resize((int(2560 * 1.5), int(340 * 1.5)), Image.LANCZOS)
    img.alpha_composite(near.crop((900, 0, 900 + W, near.height)), (0, H - near.height + 10))
    img = Image.alpha_composite(img, dust((W, H), 160, 5))
    # Assombrir le haut (lisibilité du titre) et les bords
    vig = vignette_texture(W // 2, H // 2).resize((W, H), Image.BILINEAR)
    img = Image.alpha_composite(img, vig)
    # Lueur rouge derrière le masque
    mx, my = W / 2, H * 0.55
    g = glow_texture(512).resize((900, 900), Image.BILINEAR)
    gr = np.array(g).astype(np.float32)
    gr[:, :, 0], gr[:, :, 1], gr[:, :, 2] = 230, 40, 40
    gr[:, :, 3] *= 0.85
    img.alpha_composite(Image.fromarray(gr.astype(np.uint8), "RGBA"), (int(mx - 450), int(my - 450)))
    # Masque kitsune
    mask = Image.open(MASK).convert("RGBA").resize((460, 460), Image.LANCZOS)
    img.alpha_composite(mask, (int(mx - 230), int(my - 230)))
    # Titre en Rye
    title = text_layer((W, H), "Les Royaumes des Masques", RYE, 118, (255, 246, 232), (W / 2, H * 0.17),
                       stroke=3, stroke_fill=(40, 16, 30), glow=(255, 120, 60, 120))
    img = Image.alpha_composite(img, title)
    sub = text_layer((W, H), "E X T R A C T I O N", NUNITO, 44, (255, 214, 170), (W / 2, H * 0.285), weight=900,
                     stroke=1, stroke_fill=(40, 16, 30))
    img = Image.alpha_composite(img, sub)
    # Filets décoratifs autour du sous-titre
    d = ImageDraw.Draw(img)
    for sgn in (-1, 1):
        x0 = W / 2 + sgn * 300
        x1 = W / 2 + sgn * 470
        d.line([(x0, H * 0.285), (x1, H * 0.285)], fill=(255, 214, 170, 200), width=3)
        d.polygon([(x0, H * 0.285 - 7), (x0 + sgn * 9, H * 0.285), (x0, H * 0.285 + 7), (x0 - sgn * 9, H * 0.285)], fill=(214, 40, 48, 255))
    img.convert("RGB").save(os.path.join(SPLASH, "boot.png"), optimize=True)


if __name__ == "__main__":
    build_menu_layers()
    # L'image de démarrage n'est plus produite ici (ancien titre) : voir
    # art/blender/build_menu_2d.py splash (RaidersGo). build_boot_splash() est conservée pour mémoire.
    print("ok")
