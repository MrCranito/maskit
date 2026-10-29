"""Éléments 2D du menu et du démarrage de RaidersGo (PIL + numpy, aucun Blender) :

    python3 art/blender/build_menu_2d.py fx        # flammes (6 images), bouffée de fumée, braise
    python3 art/blender/build_menu_2d.py splash    # boot.png + couches du splash animé + icône
    python3 art/blender/build_menu_2d.py all

Entrées du splash : assets/ui/menu/lobby/back.jpg, camp.png, lobby.json (build_menu.py) et la
pose « contre-plongée » du héros (build_menu_hero.py --hero-shot, fichier temporaire).
Sorties :
    assets/ui/menu/lobby/flame.png   6 images 96 x 160 (planche 6 x 1), à mélanger en additif
    assets/ui/menu/lobby/smoke.png   bouffée douce 128 x 128 (blanc, alpha)
    assets/ui/splash/boot.png        image de démarrage moteur 1920 x 1080 (logo + slogan)
    assets/ui/splash/splash_bg.png   même image SANS le logo (fond du splash animé)
    assets/ui/splash/splash_logo.png logo seul (transparent, mêmes coordonnées que boot.png)
    assets/ui/menu/app_icon_1024.png icône d'application (opaque, 1024 x 1024)
Composition du démarrage lisible recadrée : le héros et le logo restent dans la bande centrale
(recadrage portrait du LaunchScreen iOS ≈ 500 px de large au centre ; recadrage 19,5:9 de
l'iPhone ≈ 1920 x 886 au centre).
"""
from __future__ import annotations

import json
import math
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LOBBY = os.path.join(ROOT, "assets", "ui", "menu", "lobby")
SPLASH = os.path.join(ROOT, "assets", "ui", "splash")
MENU = os.path.join(ROOT, "assets", "ui", "menu")
NUNITO = os.path.join(ROOT, "assets", "fonts", "nunito", "Nunito-Variable.ttf")
TMP = os.environ.get("RDM_TMP", os.path.join(tempfile.gettempdir(), "rdm_menu"))

RED = (199, 33, 43)
RED_DARK = (107, 13, 23)
INK = (10, 8, 23)
CREAM = (255, 250, 242)
NIGHT = (18, 26, 46)


# ----------------------------------------------------------------------------- effets
def flames() -> None:
    w, h, n = 96, 160, 6
    sheet = Image.new("RGBA", (w * n, h), (0, 0, 0, 0))
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = (xx - w / 2) / (w / 2)            # -1..1
    v = 1.0 - yy / h                       # 0 en bas, 1 en haut
    for k in range(n):
        ph = 2 * math.pi * k / n
        dens = np.zeros((h, w), np.float32)
        for (amp, cx, wid, hgt, f, sp) in ((1.0, 0.0, 0.42, 0.92, 2.2, 1.0), (0.7, -0.28, 0.26, 0.62, 3.1, 1.3),
                                           (0.7, 0.3, 0.24, 0.66, 2.7, 0.8), (0.45, 0.05, 0.16, 1.0, 4.0, 1.7)):
            sway = 0.12 * np.sin(v * f * 2.2 - ph * sp) * v + 0.05 * np.sin(v * 9.0 - ph * 2 + cx * 5) * v
            width = wid * np.clip(1.0 - (v / hgt) ** 1.6, 0, 1) * (1.0 + 0.35 * (1 - v))
            core = np.exp(-((u - cx - sway) / np.maximum(width, 1e-3)) ** 2 * 2.2)
            dens += amp * core * np.clip(1.0 - v / hgt, 0, 1) ** 0.6 * np.clip(v * 8, 0, 1)
        # langues qui se détachent : modulation verticale qui monte avec la phase
        dens *= 0.82 + 0.18 * np.sin(v * 14.0 - ph * 3)
        dens = np.clip(dens, 0, 1.4)
        t = np.clip(dens / 1.2, 0, 1)
        stops = [(0.0, (120, 20, 0, 0)), (0.18, (190, 50, 10, 120)), (0.4, (245, 120, 30, 210)),
                 (0.7, (255, 196, 80, 245)), (1.0, (255, 246, 200, 255))]
        rgba = np.zeros((h, w, 4), np.float32)
        for c in range(4):
            rgba[..., c] = np.interp(t, [s[0] for s in stops], [s[1][c] for s in stops])
        im = Image.fromarray(rgba.astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(1.2))
        sheet.paste(im, (k * w, 0))
    sheet.save(os.path.join(LOBBY, "flame.png"), optimize=True)


def smoke() -> None:
    s = 128
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    rng = np.random.default_rng(3)
    d = np.sqrt((xx - s / 2) ** 2 + (yy - s / 2) ** 2) / (s / 2)
    a = np.clip(1.0 - d, 0, 1) ** 1.8
    noise = np.asarray(Image.fromarray((rng.random((8, 8)) * 255).astype(np.uint8)).resize((s, s), Image.BICUBIC), np.float32) / 255
    a *= 0.6 + 0.4 * noise
    img = np.zeros((s, s, 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = (np.clip(a, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").filter(ImageFilter.GaussianBlur(2)).save(os.path.join(LOBBY, "smoke.png"), optimize=True)


# ----------------------------------------------------------------------------- logo
def nunito(size: int, weight: int = 1000) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(NUNITO, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def slanted_text(text: str, size: int, fill, outline: int, outline_fill, shear: float = 0.24,
                 shadow: tuple[int, int] | None = None, shadow_fill=None) -> Image.Image:
    """Texte Nunito Black incliné (comme RaidersLogo.slant_font), gros contour, ombre décalée."""
    f = nunito(size)
    bb = f.getbbox(text, stroke_width=outline)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    pad = outline * 2 + size // 4
    W, H = tw + pad * 2 + int(th * shear) + 40, th + pad * 2
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    org = (pad - bb[0], pad - bb[1])
    if shadow:
        sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(sh).text((org[0] + shadow[0], org[1] + shadow[1]), text, font=f, fill=shadow_fill,
                                stroke_width=outline, stroke_fill=shadow_fill)
        layer = Image.alpha_composite(layer, sh)
        d = ImageDraw.Draw(layer)
    d.text(org, text, font=f, fill=fill, stroke_width=outline, stroke_fill=outline_fill)
    # cisaillement horizontal (haut décalé vers la droite)
    layer = layer.transform(layer.size, Image.AFFINE, (1, shear, -shear * H, 0, 1, 0), Image.BICUBIC)
    return layer.crop(layer.getbbox())


def emblem(size: int, ring=CREAM, arrow=RED, outline: bool = True) -> Image.Image:
    """Emblème viseur + flèche de sortie (proportions d'RaidersEmblem), contour sombre."""
    k = 4
    s = size * k
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = s / 2
    r = s * 0.36
    w = s * 0.075
    dark = INK + (245,)
    a0 = math.degrees(-math.pi * 0.08)
    a1 = math.degrees(-math.pi * 0.42 + math.tau)
    passes = ((dark, s * 0.05), (ring + (255,), 0)) if outline else ((ring + (255,), 0),)
    for col, extra in passes:
        rr = r + 0
        d.arc([c - rr - (w + extra) / 2, c - rr - (w + extra) / 2, c + rr + (w + extra) / 2, c + rr + (w + extra) / 2],
              a0, a1, fill=col, width=int(w + extra))
        for ang in (math.pi, math.pi * 0.5, -math.pi * 0.5):
            dx, dy = math.cos(ang), math.sin(ang)
            d.line([(c + dx * (r - s * 0.16), c + dy * (r - s * 0.16)), (c + dx * (r + s * 0.12), c + dy * (r + s * 0.12))],
                   fill=col, width=int(w * 0.75 + extra * 0.8))
        rad = s * 0.035 + extra * 0.4
        d.ellipse([c - rad, c - rad, c + rad, c + rad], fill=col)
    dv = (math.cos(-math.pi / 4), math.sin(-math.pi / 4))
    n = (-dv[1], dv[0])
    st = (c + dv[0] * s * 0.02, c + dv[1] * s * 0.02)
    en = (c + dv[0] * s * 0.5, c + dv[1] * s * 0.5)
    head = s * 0.2
    se = (en[0] - dv[0] * head * 0.6, en[1] - dv[1] * head * 0.6)
    aw = s * 0.085
    P = lambda p, kk, m=0.0: (p[0] + n[0] * kk - dv[0] * m, p[1] + n[1] * kk - dv[1] * m)
    shaft = [P(st, aw / 2), P(se, aw / 2), P(se, -aw / 2), P(st, -aw / 2)]
    tip = [en, P(se, head * 0.62, head * 0.15), P(se, -head * 0.62, head * 0.15)]
    off = (s * 0.02, s * 0.03)
    for poly in (shaft, tip) if outline else ():
        d.polygon([(x + off[0], y + off[1]) for x, y in poly], fill=dark)
    d.polygon(shaft, fill=arrow + (255,))
    d.polygon(tip, fill=tuple(min(255, int(v * 1.12 + 10)) for v in arrow) + (255,))
    return im.resize((size, size), Image.LANCZOS)


def slogan_band(text: str, h: int) -> Image.Image:
    f = nunito(int(h * 0.62), 900)
    bb = f.getbbox(text)
    tw = bb[2] - bb[0]
    k = h * 0.35
    W = int(tw + h * 1.5)
    im = Image.new("RGBA", (W + 8, h + 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    pts = [(k, 0), (W, 0), (W - k, h), (0, h)]
    d.polygon([(x + 4, y + 6) for x, y in pts], fill=INK + (220,))
    d.polygon(pts, fill=(44, 16, 34, 255))
    d.polygon([pts[0], pts[1], (W - k * 0.18, h * 0.18), (k * 0.82, h * 0.18)], fill=(255, 255, 255, 30))
    d.text(((W - tw) / 2 - bb[0], (h - (bb[3] - bb[1])) / 2 - bb[1]), text, font=f, fill=CREAM)
    return im


def go_tag(h: int) -> Image.Image:
    """« GO » sur une étiquette rouge en forme de flèche (pointe à droite), comme RaidersLogo.GoTag."""
    txt = slanted_text("GO", int(h * 0.9), CREAM, max(3, h // 10), (64, 0, 10, 255))
    k, tip = h * 0.22, h * 0.42
    W = int(txt.width + h * 0.62)
    im = Image.new("RGBA", (W + h // 6, h + h // 6), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    pts = [(k, 0), (W - tip, 0), (W, h * 0.5), (W - tip - k * 0.5, h), (0, h)]
    d.polygon([(x + h * 0.05, y + h * 0.08) for x, y in pts], fill=INK + (235,))
    d.polygon(pts, fill=RED + (255,), outline=INK + (255,), width=max(3, int(h * 0.07)))
    d.polygon([pts[0], pts[1], (W - tip * 0.7, h * 0.13), (k * 0.85, h * 0.13)], fill=(255, 150, 125, 70))
    im.alpha_composite(txt, (int(h * 0.14), int((h - txt.height) / 2)))
    return im


def logo_lockup(width: int, with_emblem: bool = True) -> Image.Image:
    """Logo empilé « RaidersGo » : emblème au-dessus, « RAIDERS » incliné, étiquette « GO » en
    flèche rouge, bande du slogan."""
    title_size = int(width * 0.27)
    out = int(title_size * 0.13)
    l1 = slanted_text("RAIDERS", title_size, CREAM, out, INK + (255,), shadow=(int(out * 0.6), int(out * 1.0)), shadow_fill=RED_DARK + (255,))
    tag = go_tag(int(title_size * 0.95))
    band = slogan_band("Tire. Pille. Tire-toi.", int(title_size * 0.4))
    em = emblem(int(title_size * 1.25)) if with_emblem else Image.new("RGBA", (1, int(title_size * 0.2)), (0, 0, 0, 0))
    W = max(l1.width, tag.width, band.width, em.width) + 20
    H = em.height + l1.height + tag.height + band.height + title_size
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    y = 0
    im.alpha_composite(em, ((W - em.width) // 2, y))
    y += em.height - int(title_size * 0.18)
    im.alpha_composite(l1, ((W - l1.width) // 2, y))
    y += l1.height - int(title_size * 0.05)
    tag_xy = ((W - tag.width) // 2 + int(title_size * 0.1), y)
    im.alpha_composite(tag, tag_xy)
    y += tag.height + int(title_size * 0.02)
    im.alpha_composite(band, ((W - band.width) // 2, y))
    bb = im.getbbox()
    logo_lockup.emblem_cy = (em.height / 2 - bb[1]) / (bb[3] - bb[1])
    logo_lockup.emblem_w = em.width / (bb[2] - bb[0])
    logo_lockup.go_c = ((tag_xy[0] + tag.width * 0.45 - bb[0]) / (bb[2] - bb[0]), (tag_xy[1] + tag.height * 0.45 - bb[1]) / (bb[3] - bb[1]))
    logo_lockup.go_w = tag.width / (bb[2] - bb[0])
    return im.crop(bb)


# ----------------------------------------------------------------------------- splash / icône
def hero_shot(path: str, skin: str = "default", bust: bool = False) -> str:
    if not os.path.exists(path):
        subprocess.check_call([sys.executable, os.path.join(ROOT, "art", "blender", "build_menu_hero.py"),
                               "--bust" if bust else "--hero-shot", path, skin])
    return path


def cover(img: Image.Image, size: tuple[int, int], focus=(0.5, 0.5)) -> Image.Image:
    W, H = size
    s = max(W / img.width, H / img.height)
    r = img.resize((int(img.width * s + 0.5), int(img.height * s + 0.5)), Image.LANCZOS)
    x = int((r.width - W) * focus[0])
    y = int((r.height - H) * focus[1])
    return r.crop((x, y, x + W, y + H))


def splash() -> None:
    W, H = 1920, 1080
    meta = json.load(open(os.path.join(LOBBY, "lobby.json")))
    back = Image.open(os.path.join(LOBBY, "back.jpg")).convert("RGBA")
    camp = Image.open(os.path.join(LOBBY, "camp.png")).convert("RGBA")
    x, y, _w, _h = meta["camp"]
    back.alpha_composite(camp, (x, y))
    # fond : le camp au coucher du soleil, recadré sur le centre, flou de profondeur + voile
    bg = cover(back, (W, H), (0.52, 0.42)).filter(ImageFilter.GaussianBlur(7))
    arr = np.asarray(bg.convert("RGB"), np.float32)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    # vignettage bleu nuit + dégradé vers le bas (ancre du logo)
    d = np.sqrt(((xx - W / 2) / (W * 0.62)) ** 2 + ((yy - H * 0.45) / (H * 0.75)) ** 2)
    vig = np.clip((d - 0.45) * 1.3, 0, 0.85)[..., None]
    low = np.clip((yy - H * 0.5) / (H * 0.5), 0, 1)[..., None] ** 1.4 * 0.7
    night = np.array(NIGHT, np.float32)
    arr = arr * (1 - vig) + night * vig
    arr = arr * (1 - low) + night * low
    # halo chaud derrière le héros
    g = np.exp(-(((xx - W / 2) / (W * 0.22)) ** 2 + ((yy - H * 0.36) / (H * 0.34)) ** 2))[..., None]
    arr = arr + np.array([255, 150, 90], np.float32) * g * 0.28
    bg = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).convert("RGBA")
    # héros en contre-plongée, centré, coupé aux genoux par le dégradé
    hs = Image.open(hero_shot(os.path.join(TMP, "hero_shot.png"))).convert("RGBA")
    hs.putalpha(hs.getchannel("A").point(lambda v: 0 if v < 10 else v))
    hs = hs.crop(hs.getbbox())
    # grand emblème en filigrane derrière le héros (halo de viseur)
    halo = emblem(int(H * 0.82), ring=(255, 226, 190), arrow=(240, 80, 70), outline=False)
    halo.putalpha(halo.getchannel("A").point(lambda v: int(v * 0.2)))
    bg.alpha_composite(halo, (W // 2 - halo.width // 2, int(H * 0.02)))
    hh = int(H * 0.8)
    hs = hs.resize((int(hs.width * hh / hs.height), hh), Image.LANCZOS)
    hx, hy = W // 2 - hs.width // 2 + 10, int(H * 0.06)
    # contre-jour : liseré chaud autour de la silhouette
    a = hs.getchannel("A").filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(10))
    rim = Image.new("RGBA", hs.size, (255, 170, 100, 0))
    rim.putalpha(a.point(lambda v: int(v * 0.55)))
    bg.alpha_composite(rim, (hx, hy))
    bg.alpha_composite(hs, (hx, hy))
    # fondu du bas du héros dans la nuit
    fade = np.clip((yy - H * 0.62) / (H * 0.3), 0, 1) ** 1.2 * 0.92
    arr = np.asarray(bg.convert("RGB"), np.float32)
    arr = arr * (1 - fade[..., None]) + night * fade[..., None]
    bg = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).convert("RGBA")
    bg.convert("RGB").save(os.path.join(SPLASH, "splash_bg.png"), optimize=True)
    # logo : bande centrale (lisible dans le recadrage portrait ≈ 500 px)
    logo = logo_lockup(560, with_emblem=False)
    lw = min(logo.width, 480)
    logo = logo.resize((lw, int(logo.height * lw / logo.width)), Image.LANCZOS)
    ly = int(H * 0.89) - logo.height
    lx = (W - logo.width) // 2
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    pad = 40
    ga = Image.new("L", (logo.width + pad * 2, logo.height + pad * 2), 0)
    ga.paste(logo.getchannel("A"), (pad, pad))
    ga = ga.filter(ImageFilter.GaussianBlur(18))
    gl = Image.new("RGBA", ga.size, NIGHT + (0,))
    gl.putalpha(ga.point(lambda v: int(v * 0.7)))
    layer.alpha_composite(gl, (lx - pad, ly - pad))
    layer.alpha_composite(logo, (lx, ly))
    boot = bg.copy()
    boot.alpha_composite(layer)
    boot.convert("RGB").save(os.path.join(SPLASH, "boot.png"), optimize=True)
    bb = layer.getbbox()
    layer.crop(bb).save(os.path.join(SPLASH, "splash_logo.png"), optimize=True)
    with open(os.path.join(SPLASH, "splash.json"), "w") as f:
        json.dump({"size": [W, H], "logo_layer": [bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1]],
                   "logo_rect": [lx, ly, logo.width, logo.height],
                   "glow_center": [lx + int(logo.width * logo_lockup.go_c[0]), ly + int(logo.height * logo_lockup.go_c[1])],
                   "glow_size": int(logo.width * logo_lockup.go_w)}, f, indent=1)
        f.write("\n")
    icon()


def icon() -> None:
    S = 1024
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    t = yy / S
    stops = [(0.0, (40, 30, 80)), (0.45, (150, 64, 110)), (0.72, (238, 128, 86)), (1.0, (252, 190, 110))]
    arr = np.zeros((S, S, 3), np.float32)
    for c in range(3):
        arr[..., c] = np.interp(t, [s[0] for s in stops], [s[1][c] for s in stops])
    g = np.exp(-(((xx - S * 0.5) / (S * 0.45)) ** 2 + ((yy - S * 0.62) / (S * 0.4)) ** 2))[..., None]
    arr += np.array([255, 190, 120], np.float32) * g * 0.25
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).convert("RGBA")
    # grand emblème en filigrane derrière
    em = emblem(int(S * 0.98), ring=(255, 235, 215), arrow=RED)
    em.putalpha(em.getchannel("A").point(lambda v: int(v * 0.22)))
    im.alpha_composite(em, (int(S * 0.01), int(S * 0.0)))
    bust = Image.open(hero_shot(os.path.join(TMP, "hero_bust.png"), bust=True)).convert("RGBA")
    bust = bust.crop(bust.getbbox())
    bh = int(S * 0.9)
    bust = bust.resize((int(bust.width * bh / bust.height), bh), Image.LANCZOS)
    im.alpha_composite(bust, (int(S * 0.47) - bust.width // 2, S - bh + int(S * 0.03)))
    # « GO » en flèche rouge, en haut à droite (lisible en petit)
    tg = go_tag(int(S * 0.19))
    im.alpha_composite(tg, (S - tg.width - int(S * 0.03), S - tg.height - int(S * 0.07)))
    im.convert("RGB").save(os.path.join(MENU, "app_icon_1024.png"), optimize=True)
    im.convert("RGB").resize((192, 192), Image.LANCZOS).save(os.path.join(MENU, "app_icon_192.png"), optimize=True)
    # Android adaptatif : fond (dégradé + emblème en filigrane) et premier plan (buste, transparent)
    bgi = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).convert("RGBA")
    bgi.alpha_composite(em, (int(S * 0.01), 0))
    bgi.convert("RGB").resize((432, 432), Image.LANCZOS).save(os.path.join(MENU, "app_icon_adaptive_bg_432.png"), optimize=True)
    fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bw2 = int(S * 0.6)   # zone sûre adaptative : 66 % central
    b2 = bust.resize((bw2, int(bust.height * bw2 / bust.width)), Image.LANCZOS)
    fg.alpha_composite(b2, ((S - bw2) // 2, int(S * 0.83) - b2.height))
    fg.resize((432, 432), Image.LANCZOS).save(os.path.join(MENU, "app_icon_adaptive_fg_432.png"), optimize=True)


def main() -> None:
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    os.makedirs(LOBBY, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)
    if what in ("fx", "all"):
        flames()
        smoke()
    if what in ("splash", "all"):
        splash()
    if what == "icon":
        icon()


if __name__ == "__main__":
    main()
