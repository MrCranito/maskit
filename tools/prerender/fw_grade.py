"""Post-étalonnage du rendu Far West / Dust Creek (avant compose.py), sans re-rendu Blender.

Usage : python3 tools/prerender/fw_grade.py <render_dir>
Applique à render_dir/full.png ET à chaque b<id>_in.png (patchs d'intérieur, décalés de leur
position dans l'image : même résultat pixel pour pixel, raccords invisibles) :
  - appariement de la luminance sur les quantiles de la colonne « Far West » de la planche
    docs/reference/cartes.png (contraste, ombres, hautes lumières) ;
  - sable tiré vers l'ocre orangé de la planche, ombres portées brun chaud (pas noires ni bleues) ;
  - clarté (contraste local à grand rayon, calculé sur l'image entière en basse résolution) :
    lecture « peinte » et profondeur des matières ;
  - intérieurs légèrement assombris ; halo chaud diffus (lumière de fin d'après-midi) ;
  - vignettage chaud léger.
Les champs globaux (LUT, clarté, halo) sont calculés une fois sur full.png et appliqués aux patchs
avec le même décalage. Idempotent : les originaux sont gardés en *_raw.png.
Réglages : FW_GRADE_MATCH, FW_GRADE_SAT, FW_GRADE_WARM, FW_GRADE_SHADOW, FW_GRADE_CLARITY,
FW_GRADE_HAZE, FW_GRADE_VIG, FW_GRADE_DARK_IN, FW_GRADE_OUTLINE.
"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageFilter

Image.MAX_IMAGE_PIXELS = None
SRC = sys.argv[1]
MATCH = float(os.environ.get("FW_GRADE_MATCH", "0.9"))
SAT = float(os.environ.get("FW_GRADE_SAT", "1.0"))
WARM = float(os.environ.get("FW_GRADE_WARM", "0.35"))
SHADOW = float(os.environ.get("FW_GRADE_SHADOW", "0.3"))
CLARITY = float(os.environ.get("FW_GRADE_CLARITY", "0.35"))
HAZE = float(os.environ.get("FW_GRADE_HAZE", "0.18"))
VIG = float(os.environ.get("FW_GRADE_VIG", "0.25"))
DARK_IN = float(os.environ.get("FW_GRADE_DARK_IN", "1.0"))
OUTLINE = float(os.environ.get("FW_GRADE_OUTLINE", "0.0"))
info = json.load(open(os.path.join(SRC, "render.json")))
L = json.load(open(os.path.join(SRC, "layout.json")))
PPC, M = info["ppc"], info["margin"]
TW, TH = L["size"]
FW, FH = (TW + 2 * M) * PPC, (TH + 2 * M) * PPC
LW = np.array([0.299, 0.587, 0.114], np.float32)

# Quantiles de luminance (0, 5, …, 100 %) de la carte « Far West » de la planche (x 12‑395,
# y 150‑850 de docs/reference/cartes.png).
REF_Q = np.array([0.0, 29.1, 40.1, 49.2, 57.6, 65.8, 74.6, 83.4, 91.7, 99.9, 109.0, 119.4, 130.7,
                  141.9, 151.5, 159.3, 166.0, 172.2, 178.5, 186.1, 248.0], np.float32) / 255.0

# Masque « intérieur » (cases FLOOR / DOOR des bâtiments), adouci.
_m = np.zeros((TH + 2 * M, TW + 2 * M), np.float32)
for b in L.get("buildings", []):
    x, y, w, h = b["rect"]
    _m[y + M + 1:y + h + M - 1, x + M + 1:x + w + M - 1] = 1.0
_mi = Image.fromarray((_m * 255).astype(np.uint8)).resize(((TW + 2 * M) * 8, (TH + 2 * M) * 8), Image.BILINEAR)
IN_MASK = _mi.filter(ImageFilter.GaussianBlur(5))


def field(img, x0, y0, w, h):
    """Extrait d'un champ basse résolution (aligné sur full.png) à la taille (w, h)."""
    sx = img.width / FW
    box = (x0 * sx, y0 * sx, (x0 + w) * sx, (y0 + h) * sx)
    return np.asarray(img.resize((w, h), Image.BILINEAR, box=box), np.float32) / 255.0


LUT = None
BLUR = None   # luminance floutée (clarté)
HAZE_MAP = None


def build_globals(im):
    global LUT, BLUR, HAZE_MAP
    t = im.copy()
    t.thumbnail((800, 800))
    a = np.asarray(t, np.float32) / 255.0
    l = a @ LW
    q = np.percentile(l, np.arange(0, 101, 5)).astype(np.float32)
    q = np.maximum.accumulate(q + np.arange(21, dtype=np.float32) * 1e-5)
    x = np.linspace(0.0, 1.0, 256, dtype=np.float32)
    LUT = x * (1.0 - MATCH) + np.interp(x, q, REF_Q) * MATCH
    # basse résolution (1/4) pour la clarté et le halo
    s = im.resize((max(1, im.width // 4), max(1, im.height // 4)), Image.BILINEAR)
    sa = np.asarray(s, np.float32) / 255.0
    sl = LUT[np.clip(sa @ LW * 255.0, 0, 255).astype(np.int32)]
    li = Image.fromarray((np.clip(sl, 0, 1) * 255).astype(np.uint8))
    BLUR = li.filter(ImageFilter.GaussianBlur(max(2, PPC * 1.6 / 4)))
    k = np.clip((sl - 0.55) / 0.35, 0.0, 1.0)
    hi = Image.fromarray((k * 255).astype(np.uint8))
    r = max(2, int(PPC * 1.0 / 4))
    h1 = np.asarray(hi.filter(ImageFilter.GaussianBlur(r)), np.float32)
    h2 = np.asarray(hi.filter(ImageFilter.GaussianBlur(r * 5)), np.float32)
    HAZE_MAP = Image.fromarray(np.clip(h1 * 0.5 + h2 * 0.7, 0, 255).astype(np.uint8))


def grade(a, x0, y0):
    h, w = a.shape[:2]
    f = a.astype(np.float32) / 255.0
    lum = f @ LW
    # 0. luminance appariée à la planche
    nl = LUT[np.clip(lum * 255.0, 0, 255).astype(np.int32)]
    f = f * (nl / np.maximum(lum, 1e-3))[:, :, None]
    lum = nl
    # 1. clarté : contraste local (détail / grand rayon), plus fort dans les tons moyens
    if CLARITY > 0:
        bl = field(BLUR, x0, y0, w, h)
        mid = np.clip(1.0 - np.abs(lum - 0.5) / 0.5, 0.0, 1.0)
        nl = np.clip(lum + (lum - bl) * CLARITY * (0.4 + 0.6 * mid), 0.0, 1.0)
        f = f * (nl / np.maximum(lum, 1e-3))[:, :, None]
        lum = nl
    # 2. teinte : tons moyens/clairs vers l'ocre orangé de la planche (207,147,103)
    ochre = np.array([1.0, 0.71, 0.50], np.float32) / 0.776
    warm = np.clip((f[:, :, 0] - f[:, :, 2]) / np.maximum(lum, 1e-3) / 0.6, 0.0, 1.0)
    m = (np.clip((lum - 0.25) / 0.35, 0.0, 1.0) * warm)[:, :, None] * WARM
    f = f * (1.0 - m) + (lum[:, :, None] * ochre) * m
    # 3. ombres → brun chaud (52,35,30)
    brown = np.array([1.0, 0.67, 0.58], np.float32) / 0.736
    sh = np.clip(1.0 - lum / 0.3, 0.0, 1.0)[:, :, None] * SHADOW
    f = f * (1.0 - sh) + (lum[:, :, None] * brown) * sh
    # 4. intérieurs un peu assombris
    i = field(IN_MASK, x0, y0, w, h)[:, :, None]
    f = f * (1.0 - i * (1.0 - DARK_IN))
    # 5. saturation
    l2 = (f @ LW)[:, :, None]
    f = l2 + (f - l2) * SAT
    # 6. halo chaud (screen)
    if HAZE > 0:
        g = field(HAZE_MAP, x0, y0, w, h)[:, :, None] * HAZE * np.array([1.0, 0.72, 0.42], np.float32)
        f = 1.0 - (1.0 - np.clip(f, 0, 1)) * (1.0 - g)
    # 7. vignettage chaud léger
    if VIG > 0:
        ys = (np.arange(y0, y0 + h, dtype=np.float32)[:, None] / FH - 0.5) * 2.0
        xs = (np.arange(x0, x0 + w, dtype=np.float32)[None, :] / FW - 0.5) * 2.0
        v = np.clip(xs * xs * 0.7 + ys * ys * 0.35 - 0.3, 0.0, 1.0)[:, :, None] * VIG
        f = f * (1.0 - v) + f * np.array([0.72, 0.5, 0.36], np.float32) * v
    return (np.clip(f, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def process(name, x0, y0, band=512):
    p = os.path.join(SRC, name)
    raw = p[:-4] + "_raw.png"
    if not os.path.exists(raw):
        shutil.copy(p, raw)
    im = Image.open(raw).convert("RGB")
    W, H = im.size
    if OUTLINE > 0:
        # contours nets (lecture « peinte » de la planche) : arêtes de luminance assombries
        e = np.asarray(im.convert("L").filter(ImageFilter.FIND_EDGES).filter(ImageFilter.GaussianBlur(0.7)), np.float32) / 255.0
        k = 1.0 - OUTLINE * np.clip((e - 0.04) / 0.25, 0.0, 1.0)
        a0 = np.asarray(im, np.float32) * k[:, :, None]
        im = Image.fromarray(np.clip(a0, 0, 255).astype(np.uint8))
    out = Image.new("RGB", (W, H))
    for yy in range(0, H, band):
        hh = min(band, H - yy)
        a = np.asarray(im.crop((0, yy, W, yy + hh)), dtype=np.uint8)
        out.paste(Image.fromarray(grade(a, x0, y0 + yy)), (0, yy))
    print("GRADE", name, W, H, flush=True)
    return out


if __name__ == "__main__":
    _raw = os.path.join(SRC, "full_raw.png")
    build_globals(Image.open(_raw if os.path.exists(_raw) else os.path.join(SRC, "full.png")).convert("RGB"))
    process("full.png", 0, 0).save(os.path.join(SRC, "full.png"))
    for b in info.get("buildings", []):
        n = "b%d_in.png" % b["id"]
        if os.path.exists(os.path.join(SRC, n)):
            process(n, b["px"][0], b["px"][1]).save(os.path.join(SRC, n))
    print("DONE grade")
