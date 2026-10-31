"""Icône d'application de RaidersGo (direction D : encre, violet électrique, coupes en biais).

Usage (depuis la racine du projet, Python 3 + Pillow + numpy) :
    python art/icon/build_app_icon.py              # toutes les sorties de la variante retenue
    python art/icon/build_app_icon.py --sheet OUT  # planche des 3 variantes (512 / 96 / 48)
    python art/icon/build_app_icon.py --variant B  # forcer une variante (A, B ou C)

Le buste du héros (variante A) est rendu par Blender (même modèle et même pipeline toon que les
menus) via art/blender/build_app_icon_bust.py, puis mis en cache dans RDM_TMP (supprimer
icon_bust_default.png de ce dossier après avoir modifié le cadrage du buste). Indiquer Blender par
la variable BLENDER (défaut : « blender » dans le PATH) ; BLENDER_PRE peut donner un script lanceur
inséré avant « -- » (par exemple pour ajouter Pillow au Python de Blender).

Variantes :
    A « Héros »   buste du héros, fusil en travers, devant un bandeau violet en biais
    B « Viseur »  emblème du démarrage : bloc violet biseauté, viseur ouvert et flèche de sortie
    C « RG »      monogramme Anton, pistolet en silhouette qui traverse le bandeau

Sorties (assets/ui/menu/) :
    app_icon_1024.png               icône du projet Godot + iOS (opaque, 1024)
    app_icon_192.png                Android legacy (opaque, 192)
    app_icon_adaptive_fg_432.png    Android adaptatif, premier plan (transparent, zone sûre 66 %)
    app_icon_adaptive_bg_432.png    Android adaptatif, arrière-plan (opaque)
    app_icon_adaptive_mono_432.png  Android 13+ icône à thème (silhouette blanche, transparent)
    app_icon_ios_dark_1024.png      iOS 18 apparence sombre (premier plan sur fond transparent)
    app_icon_ios_tinted_1024.png    iOS 18 apparence teintée (niveaux de gris sur noir)
    app_icon_pwa_{144,180,512}.png  Web (PWA)
    app_icon.ico                    Windows, multi-tailles 16 à 256
"""
from __future__ import annotations

import math
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "ui", "menu")
ANTON = os.path.join(ROOT, "assets", "fonts", "anton", "Anton-Regular.ttf")
BUST_SCRIPT = os.path.join(ROOT, "art", "blender", "build_app_icon_bust.py")
TMP = os.environ.get("RDM_TMP", os.path.join(tempfile.gettempdir(), "rdm_icon"))

CHOSEN = "A"
S = 1024          # taille de travail finale
SS = 2            # sur-échantillonnage des aplats vectoriels

INK = (6, 7, 13)
INK_2 = (20, 16, 40)
VIOLET = (124, 77, 255)
VIOLET_L = (183, 155, 255)
WHITE = (255, 255, 255)


# ---------------------------------------------------------------------------- outils
def canvas(size: int = S, color=(0, 0, 0, 0)) -> Image.Image:
    return Image.new("RGBA", (size, size), color)


def poly(points, color, size: int = S) -> Image.Image:
    """Aplat vectoriel anti-crénelé (coordonnées en fraction de la taille)."""
    big = canvas(size * SS)
    ImageDraw.Draw(big).polygon([(x * size * SS, y * size * SS) for x, y in points], fill=color)
    return big.resize((size, size), Image.LANCZOS)


def tint(alpha: Image.Image, color) -> Image.Image:
    im = Image.new("RGBA", alpha.size, color[:3] + (255,))
    a = alpha if len(color) < 4 else alpha.point(lambda v: v * color[3] // 255)
    im.putalpha(a)
    return im


def glow(layer: Image.Image, color, radius: float, strength: float = 1.0) -> Image.Image:
    a = layer.getchannel("A").filter(ImageFilter.GaussianBlur(radius))
    a = a.point(lambda v: min(255, int(v * strength)))
    return tint(a, color)


def dilate(alpha: Image.Image, px: int) -> Image.Image:
    """Grossit une silhouette de px pixels (contour « autocollant »)."""
    a = alpha.filter(ImageFilter.GaussianBlur(px * 0.5))
    return a.point(lambda v: 255 if v > 10 else 0).filter(ImageFilter.GaussianBlur(1.2))


def background(band: bool = True) -> Image.Image:
    """Encre, halo violet en haut à droite, grand bandeau violet en biais (direction D)."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
    arr = np.zeros((S, S, 3), np.float32)
    arr[...] = INK
    t = np.clip(1.0 - yy * 0.9 - (1 - xx) * 0.25, 0, 1)[..., None]
    arr = arr * (1 - t * 0.6) + np.array(INK_2, np.float32) * t * 0.6
    g = np.exp(-(((xx - 0.72) / 0.42) ** 2 + ((yy - 0.30) / 0.42) ** 2))[..., None]
    arr += np.array(VIOLET, np.float32) * g * 0.22
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).convert("RGBA")
    if band:
        # bandeau principal en biais (montant vers la droite) + filet clair parallèle
        im.alpha_composite(poly([(-0.1, 0.80), (1.1, 0.18), (1.1, 0.50), (-0.1, 1.12)], VIOLET + (235,)))
        im.alpha_composite(poly([(-0.1, 0.70), (1.1, 0.08), (1.1, 0.13), (-0.1, 0.75)], VIOLET_L + (150,)))
    return im


def flatten(im: Image.Image, color=INK) -> Image.Image:
    base = Image.new("RGBA", im.size, color + (255,))
    base.alpha_composite(im)
    return base.convert("RGB")


# ---------------------------------------------------------------------------- sujets
def bust_image(skin: str = "default") -> Image.Image:
    path = os.path.join(TMP, "icon_bust_%s.png" % skin)
    if not os.path.exists(path):
        blender = os.environ.get("BLENDER", "blender")
        cmd = [blender, "-b"]
        if os.environ.get("BLENDER_PRE"):
            cmd += ["-P", os.environ["BLENDER_PRE"]]
            cmd += ["--", BUST_SCRIPT, path, skin]
        else:
            cmd += ["--python", BUST_SCRIPT, "--", path, skin]
        subprocess.check_call(cmd)
    im = Image.open(path).convert("RGBA")
    im.putalpha(im.getchannel("A").point(lambda v: 0 if v < 6 else v))
    return im.crop(im.getbbox())


def hero_layer(scale: float = 0.98, cx: float = 0.50, bottom: float = 1.06) -> Image.Image:
    """Buste centré, coupé en bas ; contour encre épais + liseré violet clair pour décoller du fond."""
    bust = bust_image()
    h = int(S * scale)
    bust = bust.resize((int(bust.width * h / bust.height), h), Image.LANCZOS)
    lay = canvas()
    x = int(S * cx - bust.width / 2)
    y = int(S * bottom - h)
    # alpha_composite refuse les décalages négatifs : on recadre la source à la place
    src = bust.crop((max(0, -x), max(0, -y), bust.width, bust.height))
    lay.alpha_composite(src.crop((0, 0, min(src.width, S - max(0, x)), min(src.height, S - max(0, y)))),
                        (max(0, x), max(0, y)))
    a = lay.getchannel("A")
    rim = tint(dilate(a, 26), VIOLET_L)
    ink = tint(dilate(a, 12), INK)
    out = canvas()
    out.alpha_composite(rim)
    out.alpha_composite(ink)
    out.alpha_composite(lay)
    return out


def reticle(size: int, color=WHITE, box: float = 1.0, cx: float = 0.5, cy: float = 0.5) -> Image.Image:
    """Viseur ouvert en haut à droite et flèche de sortie (même tracé que splash_screen.gd)."""
    big = canvas(size * SS)
    d = ImageDraw.Draw(big)
    s = size * SS * box
    c = (size * SS * cx, size * SS * cy)
    rad = s * 0.27
    w = max(2, int(s * 0.085))
    # arc de -0.08 PI à 1.58 PI (sens écran, y vers le bas) : ouvert en haut à droite
    d.arc([c[0] - rad - w / 2, c[1] - rad - w / 2, c[0] + rad + w / 2, c[1] + rad + w / 2],
          start=math.degrees(-math.pi * 0.08), end=math.degrees(math.pi * 1.58), fill=color, width=w)
    for ang in (math.pi, math.pi * 0.5, -math.pi * 0.5):
        dx, dy = math.cos(ang), math.sin(ang)
        p0 = (c[0] + dx * (rad - s * 0.10), c[1] + dy * (rad - s * 0.10))
        p1 = (c[0] + dx * (rad + s * 0.10), c[1] + dy * (rad + s * 0.10))
        d.line([p0, p1], fill=color, width=int(w * 0.85))
    r0 = s * 0.05
    d.ellipse([c[0] - r0, c[1] - r0, c[0] + r0, c[1] + r0], fill=color)
    dirx, diry = math.cos(-math.pi * 0.25), math.sin(-math.pi * 0.25)
    nx, ny = -diry, dirx
    tip = (c[0] + dirx * s * 0.42, c[1] + diry * s * 0.42)
    head = s * 0.19
    base = (tip[0] - dirx * head, tip[1] - diry * head)
    d.line([(c[0] + dirx * s * 0.08, c[1] + diry * s * 0.08), base], fill=color, width=w)
    d.polygon([tip, (base[0] + nx * head * 0.62, base[1] + ny * head * 0.62),
               (base[0] - nx * head * 0.62, base[1] - ny * head * 0.62)], fill=color)
    return big.resize((size, size), Image.LANCZOS)


def cutbox(x0, y0, x1, y1, cut, color) -> Image.Image:
    """Bloc biseauté (CutBox) : coins haut-gauche et bas-droit coupés."""
    return poly([(x0, y0 + cut), (x0 + cut, y0), (x1, y0), (x1, y1 - cut), (x1 - cut, y1), (x0, y1)], color)


def pistol(color, size: int = S) -> Image.Image:
    """Silhouette de pistolet (profil, canon vers la droite), dans un carré unité."""
    pts = [(0.10, 0.30), (0.86, 0.30), (0.90, 0.33), (0.90, 0.44), (0.84, 0.46),  # culasse + bouche
           (0.42, 0.46), (0.40, 0.52), (0.46, 0.60), (0.44, 0.62),                 # pontet
           (0.36, 0.56), (0.34, 0.52), (0.30, 0.86), (0.12, 0.86),                  # poignée
           (0.16, 0.48), (0.10, 0.44)]
    return poly(pts, color, size)


# ---------------------------------------------------------------------------- variantes
def variant_a() -> tuple[Image.Image, Image.Image, Image.Image]:
    """Retourne (icône pleine, premier plan transparent, arrière-plan)."""
    bg = background()
    fg = hero_layer()
    full = bg.copy()
    full.alpha_composite(glow(fg, VIOLET, 40, 0.8))
    full.alpha_composite(fg)
    return full, fg, bg


def variant_b():
    bg = background(band=False)
    bg.alpha_composite(poly([(-0.1, 0.92), (1.1, 0.30), (1.1, 0.40), (-0.1, 1.02)], VIOLET + (90,)))
    fg = canvas()
    box = cutbox(0.14, 0.14, 0.86, 0.86, 0.17, VIOLET + (255,))
    fg.alpha_composite(box)
    fg.alpha_composite(reticle(S, WHITE, box=0.72))
    full = bg.copy()
    full.alpha_composite(glow(box, VIOLET, 50, 0.7))
    full.alpha_composite(fg)
    return full, fg, bg


def variant_c():
    bg = background()
    fg = canvas()
    big = canvas(S * SS)
    d = ImageDraw.Draw(big)
    font = ImageFont.truetype(ANTON, int(S * SS * 0.56))
    gap = S * SS * 0.015
    r_w = d.textlength("R", font=font)
    g_w = d.textlength("G", font=font)
    x = (S * SS - r_w - g_w - gap) / 2
    y = -S * SS * 0.02
    # ombre encre décalée, puis lettres
    for off, col_r, col_g in ((S * SS * 0.022, INK, INK), (0, WHITE, VIOLET_L)):
        d.text((x + off, y + off), "R", font=font, fill=col_r + (255,))
        d.text((x + r_w + gap + off, y + off), "G", font=font, fill=col_g + (255,))
    fg.alpha_composite(big.resize((S, S), Image.LANCZOS))
    # pistolet sous le monogramme, canon vers la droite, légèrement relevé
    gun = pistol(WHITE + (255,)).rotate(10, resample=Image.BICUBIC)
    gun = gun.resize((int(S * 0.50), int(S * 0.50)), Image.LANCZOS)
    g = canvas()
    g.alpha_composite(gun, (int(S * 0.27), int(S * 0.53)))
    fg.alpha_composite(tint(dilate(g.getchannel("A"), 16), INK))
    fg.alpha_composite(g)
    full = bg.copy()
    full.alpha_composite(fg)
    return full, fg, bg


VARIANTS = {"A": ("Héros", variant_a), "B": ("Viseur", variant_b), "C": ("RG", variant_c)}


# ---------------------------------------------------------------------------- sorties
def mono_mark() -> Image.Image:
    """Icône à thème (Android 13+) : glyphe d'une seule couleur, sans fond."""
    return reticle(S, WHITE, box=0.62)


def adaptive_fg(fg: Image.Image, variant: str) -> Image.Image:
    """Premier plan adaptatif : le sujet tient dans le cercle central de 66 % (72 dp sur 108)."""
    if variant == "A":
        # le buste peut déborder en bas (masqué), la tête reste dans la zone sûre
        lay = hero_layer(scale=0.62, cx=0.50, bottom=0.87)
        return lay
    inner = fg.resize((int(S * 0.70), int(S * 0.70)), Image.LANCZOS)
    out = canvas()
    out.alpha_composite(inner, ((S - inner.width) // 2, (S - inner.height) // 2))
    return out


def write_all(variant: str) -> None:
    full, fg, bg = VARIANTS[variant][1]()
    os.makedirs(OUT, exist_ok=True)
    rgb = flatten(full)
    rgb.save(os.path.join(OUT, "app_icon_1024.png"), optimize=True)
    rgb.resize((192, 192), Image.LANCZOS).save(os.path.join(OUT, "app_icon_192.png"), optimize=True)
    for n in (144, 180, 512):
        rgb.resize((n, n), Image.LANCZOS).save(os.path.join(OUT, "app_icon_pwa_%d.png" % n), optimize=True)
    afg = adaptive_fg(fg, variant)
    afg.resize((432, 432), Image.LANCZOS).save(os.path.join(OUT, "app_icon_adaptive_fg_432.png"), optimize=True)
    flatten(bg).resize((432, 432), Image.LANCZOS).save(os.path.join(OUT, "app_icon_adaptive_bg_432.png"), optimize=True)
    mono_mark().resize((432, 432), Image.LANCZOS).save(os.path.join(OUT, "app_icon_adaptive_mono_432.png"), optimize=True)
    # iOS 18 : sombre = sujet sur fond transparent ; teinté = luminance du sujet, opaque sur noir
    dark = canvas()
    dark.alpha_composite(glow(fg, VIOLET, 40, 0.6))
    dark.alpha_composite(fg)
    dark.save(os.path.join(OUT, "app_icon_ios_dark_1024.png"), optimize=True)
    flatten(fg, (0, 0, 0)).convert("L").save(os.path.join(OUT, "app_icon_ios_tinted_1024.png"), optimize=True)
    # Windows : .ico multi-tailles (fenêtre, barre des tâches, explorateur)
    rgb.save(os.path.join(OUT, "app_icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48),
                                                        (64, 64), (128, 128), (256, 256)])
    print("icône %s (%s) écrite dans %s" % (variant, VARIANTS[variant][0], OUT))


def sheet(path: str) -> None:
    """Planche : chaque variante en grand, puis en 96, 64 et 48 px sur fond clair et sombre."""
    W, H = 1500, 1080
    im = Image.new("RGB", (W, H), (236, 233, 242))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 760, W, H], fill=(18, 18, 24))
    title = ImageFont.truetype(ANTON, 44)
    small = ImageFont.truetype(ANTON, 24)
    d.text((40, 20), "ICÔNE RAIDERSGO : VARIANTES", font=title, fill=INK)
    d.text((40, 1030), "TAILLES RÉELLES 96 / 64 / 48 PX, PUIS 48 PX AGRANDI (PIXELS VISIBLES)", font=small,
           fill=(200, 200, 210))
    for i, (k, (name, fn)) in enumerate(VARIANTS.items()):
        full = flatten(fn()[0])
        x0 = 40 + i * 490
        d.text((x0, 90), "%s  %s" % (k, name.upper()), font=small, fill=INK)
        big = rounded(full.resize((400, 400), Image.LANCZOS), 0.22)
        im.paste(big, (x0, 130), big)
        for yb in (560, 800):
            xx = x0
            for n in (96, 64, 48):
                ic = rounded(full.resize((n, n), Image.LANCZOS), 0.22)
                im.paste(ic, (xx, yb + (96 - n) // 2), ic)
                xx += n + 26
        zoom = rounded(full.resize((48, 48), Image.LANCZOS).resize((144, 144), Image.NEAREST), 0.22)
        im.paste(zoom, (x0 + 290, 870), zoom)
    im.save(path)
    print("planche", path)


def rounded(im: Image.Image, r: float) -> Image.Image:
    """Masque squircle approché (coins arrondis) pour les aperçus."""
    n = im.width
    m = Image.new("L", (n * 4, n * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, n * 4 - 1, n * 4 - 1], radius=int(n * 4 * r), fill=255)
    out = im.convert("RGBA")
    out.putalpha(m.resize((n, n), Image.LANCZOS))
    return out


def main() -> None:
    args = sys.argv[1:]
    os.makedirs(TMP, exist_ok=True)
    variant = args[args.index("--variant") + 1] if "--variant" in args else CHOSEN
    if "--sheet" in args:
        sheet(args[args.index("--sheet") + 1])
        return
    write_all(variant)


if __name__ == "__main__":
    main()
