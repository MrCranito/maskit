"""Post-étalonnage du rendu de la Station Kagami (avant compose.py), sans re-rendu Blender.

Usage : python3 tools/prerender/ss_grade.py <render_dir>
Applique à render_dir/full.png ET à chaque b<id>_in.png (patchs d'intérieur, décalés de leur
position dans l'image : même résultat pixel pour pixel, raccords invisibles) :
  - appariement de la luminance sur les quantiles de la colonne « Station spatiale » de la planche
    (docs/reference/cartes.png) : le rendu brut est trop plat (tons moyens tassés) ;
  - virage des tons : ombres bleu nuit, tons moyens gris neutres légèrement chauds (sols de la
    planche), hautes lumières blanc froid ;
  - occlusion de contact calculée sur le plan (pied des murs côté salle) : profondeur des pièces ;
  - halo (bloom) froid calculé sur l'image entière en basse résolution (néons, écrans, hublots) ;
  - vignettage bleu nuit léger.
Idempotent : les originaux sont gardés en *_raw.png (relancer repart des originaux).
Réglages : variables d'environnement SS_GRADE_* (voir plus bas).
"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageFilter

Image.MAX_IMAGE_PIXELS = None
SRC = sys.argv[1]
info = json.load(open(os.path.join(SRC, "render.json")))
L = json.load(open(os.path.join(SRC, "layout.json")))
PPC, M = info["ppc"], info["margin"]
TW, TH = L["size"]
FW, FH = (TW + 2 * M) * PPC, (TH + 2 * M) * PPC
LW = np.array([0.299, 0.587, 0.114], np.float32)


def env(k, d):
    return float(os.environ.get("SS_GRADE_" + k, d))


MATCH = env("MATCH", "0.7")
MATCH2 = env("MATCH2", "0.5")
SAT = env("SAT", "1.08")
NAVY = env("NAVY", "0.5")
WARM = env("WARM", "0.15")
AO = env("AO", "0.3")
HAZE = env("HAZE", "0.45")
VIG = env("VIG", "0.35")
CLARITY = env("CLARITY", "45")      # contraste local (« peint », lisible sur mobile), en %

# Quantiles de luminance (0, 5, …, 100 %) de la colonne « Station spatiale » de la planche
# (carte vue de dessus, x 440-875, y 145-925).
REF_Q = np.array([0, 2, 3, 4, 5, 6, 8, 12, 18, 25, 32, 41, 52, 63, 76, 88, 100, 114, 136, 170, 255],
                 np.float32) / 255.0


def lut_for(im, match):
    t = im.copy()
    t.thumbnail((800, 800))
    a = np.asarray(t, np.float32) / 255.0
    l = a @ LW
    q = np.percentile(l, np.arange(0, 101, 5)).astype(np.float32)
    q = np.maximum.accumulate(q + np.arange(21, dtype=np.float32) * 1e-5)
    x = np.linspace(0.0, 1.0, 256, dtype=np.float32)
    m = np.interp(x, q, REF_Q)
    return x * (1.0 - match) + m * match


# Occlusion de contact : densité de murs (cases 3) floutée, appliquée sur les cases de sol.
_k = 8
_wall = np.zeros((TH + 2 * M, TW + 2 * M), np.float32)
_flo = np.zeros_like(_wall)
for _y, _row in enumerate(L["tiles"]):
    for _x, _ch in enumerate(_row):
        if _ch == "3":
            _wall[_y + M, _x + M] = 1.0
        elif _ch != "0":
            _flo[_y + M, _x + M] = 1.0
_wi = Image.fromarray((_wall * 255).astype(np.uint8)).resize(((TW + 2 * M) * _k, (TH + 2 * M) * _k), Image.NEAREST)
_fi = Image.fromarray((_flo * 255).astype(np.uint8)).resize(((TW + 2 * M) * _k, (TH + 2 * M) * _k), Image.NEAREST)
_wb = np.asarray(_wi.filter(ImageFilter.GaussianBlur(_k * 0.55)), np.float32) / 255.0
_fm = np.asarray(_fi.filter(ImageFilter.GaussianBlur(_k * 0.15)), np.float32) / 255.0
AO_MAP = Image.fromarray((np.clip(_wb * 2.0, 0, 1) * _fm * 255).astype(np.uint8))


def sample(img, x0, y0, w, h):
    sx = img.width / FW
    box = (x0 * sx, y0 * sx, (x0 + w) * sx, (y0 + h) * sx)
    return np.asarray(img.resize((w, h), Image.BILINEAR, box=box), np.float32) / 255.0


HAZE_MAP = None


def build_haze(im):
    global HAZE_MAP
    t = im.resize((max(1, im.width // 8), max(1, im.height // 8)), Image.BILINEAR)
    a = np.asarray(t, np.float32) / 255.0
    l = a @ LW
    k = np.clip((l - 0.5) / 0.4, 0.0, 1.0)[:, :, None]
    hi = Image.fromarray((np.clip(a * k, 0, 1) * 255).astype(np.uint8))
    r = max(2, int(PPC * 1.0 / 8))
    b1 = np.asarray(hi.filter(ImageFilter.GaussianBlur(r)), np.float32) / 255.0
    b2 = np.asarray(hi.filter(ImageFilter.GaussianBlur(r * 4)), np.float32) / 255.0
    h = (b1 * 0.6 + b2 * 0.7) * np.array([0.85, 0.92, 1.0], np.float32)
    HAZE_MAP = Image.fromarray((np.clip(h, 0, 1) * 255).astype(np.uint8))


LUT = None
LUT2 = None


def grade(a, x0, y0):
    f = a.astype(np.float32) / 255.0
    h_, w_ = f.shape[:2]
    lum = f @ LW
    if LUT is not None:
        nl = LUT[np.clip(lum * 255.0, 0, 255).astype(np.int32)]
        f = f * (nl / np.maximum(lum, 1e-3))[:, :, None]
        lum = nl
    # occlusion de contact (sols près des murs)
    if AO > 0:
        o = sample(AO_MAP, x0, y0, w_, h_)[:, :, None]
        f = f * (1.0 - AO * o)
    lum = f @ LW
    # tons moyens : gris neutre légèrement chaud (désature le bleu du rendu brut)
    mid = np.clip(1.0 - np.abs(lum - 0.45) / 0.3, 0.0, 1.0)[:, :, None] * WARM
    neutral = lum[:, :, None] * np.array([1.02, 0.99, 1.0], np.float32)
    f = f * (1.0 - mid) + neutral * mid
    # ombres → bleu nuit
    sh = np.clip(1.0 - lum / 0.22, 0.0, 1.0)[:, :, None] * NAVY
    navy = lum[:, :, None] * np.array([0.55, 0.8, 1.55], np.float32) + np.array([0.0, 0.004, 0.014], np.float32)
    f = f * (1.0 - sh) + navy * sh
    lum = f @ LW
    f = lum[:, :, None] + (f - lum[:, :, None]) * SAT
    # vignettage bleu nuit
    ys = (np.arange(y0, y0 + h_, dtype=np.float32)[:, None] / FH - 0.5) * 2.0
    xs = (np.arange(x0, x0 + w_, dtype=np.float32)[None, :] / FW - 0.5) * 2.0
    v = np.clip((xs * xs * 0.7 + ys * ys * 0.5) - 0.3, 0.0, 1.0)[:, :, None] * VIG
    f = f * (1.0 - v) + f * np.array([0.45, 0.55, 0.8], np.float32) * v
    return np.clip(f, 0.0, 1.0)


def final(f, x0, y0):
    lum = f @ LW
    if LUT2 is not None:
        nl = LUT2[np.clip(lum * 255.0, 0, 255).astype(np.int32)]
        f = f * (nl / np.maximum(lum, 1e-3))[:, :, None]
    if HAZE > 0 and HAZE_MAP is not None:
        g = sample(HAZE_MAP, x0, y0, f.shape[1], f.shape[0]) * HAZE
        f = 1.0 - (1.0 - np.clip(f, 0, 1)) * (1.0 - g)
    return (np.clip(f, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def process(name, x0, y0, second=True, band=512):
    p = os.path.join(SRC, name)
    raw = p[:-4] + "_raw.png"
    # nouveau rendu (fichier modifié depuis le dernier étalonnage) → il devient l'original
    if not os.path.exists(raw) or STATE.get(name) != os.path.getmtime(p):
        shutil.copy(p, raw)
    im = Image.open(raw).convert("RGB")
    if CLARITY > 0:
        # contraste local à grand rayon (≈ 0,6 case) : volumes et matières plus lisibles
        im = im.filter(ImageFilter.UnsharpMask(radius=max(2, int(PPC * 0.6)), percent=int(CLARITY), threshold=1))
    W, H = im.size
    out = Image.new("RGB", (W, H))
    for yy in range(0, H, band):
        hh = min(band, H - yy)
        a = np.asarray(im.crop((0, yy, W, yy + hh)), dtype=np.uint8)
        g = grade(a, x0, y0 + yy)
        out.paste(Image.fromarray(final(g, x0, y0 + yy) if second else (g * 255 + 0.5).astype(np.uint8)), (0, yy))
    print("GRADE", name, W, H, flush=True)
    return out


STATE_P = os.path.join(SRC, "ss_grade_state.json")
STATE = json.load(open(STATE_P)) if os.path.exists(STATE_P) else {}


def save(img, name):
    p = os.path.join(SRC, name)
    img.save(p)
    STATE[name] = os.path.getmtime(p)
    json.dump(STATE, open(STATE_P, "w"))


if __name__ == "__main__":
    _raw = os.path.join(SRC, "full_raw.png")
    _p = os.path.join(SRC, "full.png")
    if not os.path.exists(_raw) or STATE.get("full.png") != os.path.getmtime(_p):
        shutil.copy(_p, _raw)
        STATE["full.png"] = os.path.getmtime(_p)
    base = Image.open(_raw).convert("RGB")
    LUT = lut_for(base, MATCH)
    first = process("full.png", 0, 0, second=False)
    LUT2 = lut_for(first, MATCH2)
    build_haze(first)
    save(process("full.png", 0, 0), "full.png")
    for b in info.get("buildings", []):
        n = "b%d_in.png" % b["id"]
        if os.path.exists(os.path.join(SRC, n)):
            save(process(n, b["px"][0], b["px"][1]), n)
    print("DONE grade")
