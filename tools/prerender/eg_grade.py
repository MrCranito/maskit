"""Post-étalonnage du rendu des Pyramides d'Égypte (avant compose.py), sans re-rendu Blender.

Usage : python3 tools/prerender/eg_grade.py <render_dir>
Applique à render_dir/full.png ET à chaque b<id>_in.png (patchs d'intérieur, décalés de leur
position dans l'image : même résultat pixel pour pixel, raccords invisibles) :
  - courbe en S (ombres brun foncé, hautes lumières dorées), saturation dosée (EG_GRADE_SAT) ;
  - teinte : sable tiré vers l'ocre doré chaud (pas beige gris, pas orange saturé) ;
  - ombres portées vers le brun chocolat (pas noires, pas grises) ;
  - intérieurs assombris et taches orange des torches / braseros (positions du contrat) ;
  - halo doré sur la cour centrale et le sanctuaire ; vignettage chaud.
Idempotent : les originaux sont gardés en *_raw.png (relancer repart des originaux).
"""
import json
import math
import os
import shutil
import sys

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
SRC = sys.argv[1]
SAT = float(os.environ.get("EG_GRADE_SAT", "1.0"))
CURVE = float(os.environ.get("EG_GRADE_CURVE", "0.0"))
GLOW = float(os.environ.get("EG_GRADE_GLOW", "1.0"))
DARK_IN = float(os.environ.get("EG_GRADE_DARK_IN", "0.66"))
VIG = float(os.environ.get("EG_GRADE_VIG", "0.38"))
info = json.load(open(os.path.join(SRC, "render.json")))
L = json.load(open(os.path.join(SRC, "layout.json")))
PPC, M = info["ppc"], info["margin"]
C = L.get("contract", {})
TW, TH = L["size"]
FW, FH = (TW + 2 * M) * PPC, (TH + 2 * M) * PPC


def gpx(cx, cy):
    """Case (sol) → pixel de full.png (projection ground_square)."""
    return (cx + M) * PPC, (cy + M) * PPC


# Lueurs (x px, y px, rayon x, rayon y, couleur, intensité)
GLOWS = []
for t in C.get("torches", []):
    x, y = gpx(t[0] + 0.5, t[1] + 0.5)
    GLOWS.append((x, y, 1.2 * PPC, 1.1 * PPC, (1.0, 0.55, 0.18), 0.5))
for s in L.get("prop_spawns", []):
    if s.get("kind") in ("eg_brazier", "eg_torch", "eg_fire_bowl", "eg_campfire"):
        x, y = gpx(s["cell"][0] + 0.5, s["cell"][1] + 0.5)
        GLOWS.append((x, y, 1.5 * PPC, 1.4 * PPC, (1.0, 0.5, 0.14), 0.55))
sa = C.get("sanctuary", [30, 32, 12, 12])
x, y = gpx(sa[0] + sa[2] / 2, sa[1] + sa[3] / 2)
GLOWS.append((x, y, sa[2] * 0.45 * PPC, sa[3] * 0.45 * PPC, (1.0, 0.55, 0.15), 0.14))
for ct in C.get("courts", [])[:1]:
    x, y = gpx(ct[0] + ct[2] / 2, ct[1] + ct[3] / 2)
    GLOWS.append((x, y, ct[2] * 0.5 * PPC, ct[3] * 0.5 * PPC, (1.0, 0.55, 0.2), 0.08))

# Masque « intérieur » (cases FLOOR/DOOR/STAIRS de pièces non ouvertes : murs exclus), adouci.
_open = set()
for r in L.get("rooms", []):
    tg = r.get("tags", [])
    if any(t in ("court", "inner_court", "hypostyle", "desert", "avenue", "gate", "dunes", "camp", "oasis") for t in tg):
        x0, y0, w, h = r["rect"]
        for yy in range(y0, y0 + h):
            for xx in range(x0, x0 + w):
                _open.add((xx, yy))
_m = np.zeros((TH + 2 * M, TW + 2 * M), np.float32)
for _y, _row in enumerate(L["tiles"]):
    for _x, _ch in enumerate(_row):
        if _ch in ("2", "4", "5") and (_x, _y) not in _open:
            _m[_y + M, _x + M] = 1.0
from PIL import ImageFilter
_mi = Image.fromarray((_m * 255).astype(np.uint8)).resize(((TW + 2 * M) * 8, (TH + 2 * M) * 8), Image.BILINEAR)
IN_MASK = _mi.filter(ImageFilter.GaussianBlur(6))
# Masque « sable » (cases VOID / STREET hors dallage, marge comprise), adouci.
_s = np.ones((TH + 2 * M, TW + 2 * M), np.float32)
for _y, _row in enumerate(L["tiles"]):
    for _x, _ch in enumerate(_row):
        if _ch not in ("0", "1"):
            _s[_y + M, _x + M] = 0.0
_si = Image.fromarray((_s * 255).astype(np.uint8)).resize(((TW + 2 * M) * 8, (TH + 2 * M) * 8), Image.BILINEAR)
SAND_MASK = _si.filter(ImageFilter.GaussianBlur(5))
SAND_SAT = float(os.environ.get("EG_GRADE_SAND_SAT", "1.08"))
SAND_CON = float(os.environ.get("EG_GRADE_SAND_CON", "1.18"))
SHADOW = float(os.environ.get("EG_GRADE_SHADOW", "0.3"))


def sandm(x0, y0, w, h):
    sx = SAND_MASK.width / FW
    box = (x0 * sx, y0 * sx, (x0 + w) * sx, (y0 + h) * sx)
    return np.asarray(SAND_MASK.resize((w, h), Image.BILINEAR, box=box), np.float32) / 255.0


def inside(x0, y0, w, h):
    sx = IN_MASK.width / FW
    box = (x0 * sx, y0 * sx, (x0 + w) * sx, (y0 + h) * sx)
    return np.asarray(IN_MASK.resize((w, h), Image.BILINEAR, box=box), np.float32) / 255.0


def glow_field(x0, y0, w, h):
    out = np.zeros((h, w, 3), np.float32)
    ys = np.arange(y0, y0 + h, dtype=np.float32)[:, None]
    xs = np.arange(x0, x0 + w, dtype=np.float32)[None, :]
    for (gx, gy, rx, ry, col, k) in GLOWS:
        if gx + rx < x0 or gx - rx > x0 + w or gy + ry < y0 or gy - ry > y0 + h:
            continue
        d2 = ((xs - gx) / rx) ** 2 + ((ys - gy) / ry) ** 2
        f = np.clip(1.0 - d2, 0.0, 1.0) ** 3 * (k * GLOW)
        out += f[:, :, None] * np.array(col, np.float32)[None, None, :]
    return out


def scurve(v, k):
    """Courbe en S douce centrée sur 0.45 (ombres plus profondes, hautes lumières tenues)."""
    p = 0.45
    lo = p * (v / p) ** (1.0 + 0.55 * k)
    hi = 1.0 - (1.0 - p) * ((1.0 - v) / (1.0 - p)) ** (1.0 + 0.25 * k)
    return np.where(v < p, lo, hi)


# Quantiles de luminance (0, 5, …, 100 %) de la colonne « Pyramides » de la planche : le rendu
# brut est trop resserré (médiane haute, peu d'écart) ; on y apparie sa luminance.
REF_Q = np.array([0.0, 29.0, 42.1, 52.0, 60.2, 67.9, 74.9, 81.9, 89.3, 97.6, 106.3, 115.4, 125.1,
                  135.6, 146.4, 157.2, 167.2, 176.4, 185.0, 195.0, 255.0], np.float32) / 255.0
MATCH = float(os.environ.get("EG_GRADE_MATCH", "0.8"))
LUT = None


def build_lut(path):
    """LUT 256 → luminance appariée (calculée une fois sur full.png, appliquée aux patchs)."""
    global LUT
    im = Image.open(path).convert("RGB")
    im.thumbnail((800, 800))
    a = np.asarray(im, np.float32) / 255.0
    l = a @ np.array([0.299, 0.587, 0.114], np.float32)
    q = np.percentile(l, np.arange(0, 101, 5)).astype(np.float32)
    q = np.maximum.accumulate(q + np.arange(21, dtype=np.float32) * 1e-5)
    x = np.linspace(0.0, 1.0, 256, dtype=np.float32)
    m = np.interp(x, q, REF_Q)
    LUT = x * (1.0 - MATCH) + m * MATCH


def grade(a, x0, y0):
    f = a.astype(np.float32) / 255.0
    lum = f @ np.array([0.299, 0.587, 0.114], np.float32)
    # 0. appariement de luminance sur la planche (contraste, ombres brun foncé, hautes lumières)
    if LUT is not None:
        nl = LUT[np.clip(lum * 255.0, 0, 255).astype(np.int32)]
        f = f * (nl / np.maximum(lum, 1e-3))[:, :, None]
        lum = nl
    # 1. teinte : mélange vers l'ocre doré selon la luminance (le sable beige devient doré)
    gold = np.array([1.0, 0.74, 0.42], np.float32)
    mid = np.clip(1.0 - np.abs(lum - 0.6) / 0.4, 0.0, 1.0)[:, :, None]
    f = f * (1.0 - 0.1 * mid) + (lum[:, :, None] * gold * 1.08) * (0.1 * mid)
    # 2. ombres → brun chocolat
    sh = np.clip(1.0 - lum / 0.32, 0.0, 1.0)[:, :, None]
    f = f * (1.0 - 0.35 * sh) + (lum[:, :, None] * np.array([1.15, 0.78, 0.5], np.float32)) * (0.35 * sh)
    # 2b. sable : plus ocre doré et plus contrasté ; ombres portées plus sombres (détache les
    # pavillons du sol)
    sm = sandm(x0, y0, a.shape[1], a.shape[0])[:, :, None]
    l2 = (f @ np.array([0.299, 0.587, 0.114], np.float32))[:, :, None]
    ochre = l2 + (f - l2) * SAND_SAT
    ochre = ochre * np.array([1.02, 0.99, 0.92], np.float32)
    lm_ = 0.42
    ochre = ochre * ((lm_ + (l2 - lm_) * SAND_CON) / np.maximum(l2, 1e-3))
    f = f * (1.0 - sm) + ochre * sm
    l2 = f @ np.array([0.299, 0.587, 0.114], np.float32)
    shd = np.clip(1.0 - l2 / 0.3, 0.0, 1.0)[:, :, None]
    f = f * (1.0 - SHADOW * shd)
    # 3. intérieurs assombris
    i = inside(x0, y0, a.shape[1], a.shape[0])[:, :, None]
    f = f * (1.0 - i * (1.0 - DARK_IN))
    # 4. courbe + saturation
    lum = f @ np.array([0.299, 0.587, 0.114], np.float32)
    nl = scurve(np.clip(lum, 0.0, 1.0), CURVE)
    f = f * (nl / np.maximum(lum, 1e-4))[:, :, None]
    lum = nl
    f = lum[:, :, None] + (f - lum[:, :, None]) * SAT
    # 5. lueurs (screen modulé : plus fort sur les zones sombres)
    g = glow_field(x0, y0, a.shape[1], a.shape[0])
    f = 1.0 - (1.0 - np.clip(f, 0, 1)) * (1.0 - g * (0.45 + 0.55 * (1.0 - np.clip(lum, 0, 1)))[:, :, None])
    # 6. vignettage chaud (bords brun-rouge)
    ys = (np.arange(y0, y0 + a.shape[0], dtype=np.float32)[:, None] / FH - 0.5) * 2.0
    xs = (np.arange(x0, x0 + a.shape[1], dtype=np.float32)[None, :] / FW - 0.5) * 2.0
    v = np.clip((xs * xs * 0.8 + ys * ys * 0.6) - 0.25, 0.0, 1.0)[:, :, None] * VIG
    f = f * (1.0 - v) + f * np.array([0.75, 0.5, 0.3], np.float32) * v
    # 7. balance : bleu un peu relevé (le rendu brut est plus orangé que la planche), ombres
    # profondes légèrement bleu nuit (direction artistique)
    lum = f @ np.array([0.299, 0.587, 0.114], np.float32)
    deep = np.clip(1.0 - lum / 0.2, 0.0, 1.0)[:, :, None]
    f = f * np.array([0.99, 1.0, 1.12], np.float32) + deep * np.array([0.0, 0.006, 0.03], np.float32)
    return (np.clip(f, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def process(name, x0, y0, band=512):
    p = os.path.join(SRC, name)
    raw = p[:-4] + "_raw.png"
    if not os.path.exists(raw):
        shutil.copy(p, raw)
    im = Image.open(raw).convert("RGB")
    W, H = im.size
    out = Image.new("RGB", (W, H))
    for yy in range(0, H, band):
        hh = min(band, H - yy)
        a = np.asarray(im.crop((0, yy, W, yy + hh)), dtype=np.uint8)
        out.paste(Image.fromarray(grade(a, x0, y0 + yy)), (0, yy))
    out.save(p)
    print("GRADE", name, W, H, flush=True)


if __name__ == "__main__":
    _raw = os.path.join(SRC, "full_raw.png")
    build_lut(_raw if os.path.exists(_raw) else os.path.join(SRC, "full.png"))
    process("full.png", 0, 0)
    for b in info.get("buildings", []):
        n = "b%d_in.png" % b["id"]
        if os.path.exists(os.path.join(SRC, n)):
            process(n, b["px"][0], b["px"][1])
    print("DONE grade", len(GLOWS), "glows")
