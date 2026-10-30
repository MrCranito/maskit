"""Post-étalonnage du rendu du Carnaval hanté (avant compose.py), sans re-rendu Blender.

Usage : python3 tools/prerender/hc_grade.py <render_dir> [force]
Applique à render_dir/full.png ET à chaque b<id>_in.png (patchs d'intérieur, décalés de leur
position dans l'image : même résultat pixel pour pixel, raccords invisibles) :
  - saturation renforcée (HC_GRADE_SAT, défaut 1.18) ;
  - ombres bleu nuit tirées vers le violet et légèrement relevées (moins de noir) ;
  - lueurs magenta / violettes au SOL, en coordonnées du plan (layout.json + contrat) : grand halo
    autour du chapiteau et sur la place, couloir le long de l'allée centrale, parvis du clown,
    halos des manèges ; halos chauds sous les lampadaires (prop_spawns hc_lamp_post) ;
  - intérieurs chauds : pixels déjà orangés renforcés.
Idempotent : les originaux sont gardés en *_raw.png (relancer repart des originaux).
Traitement par bandes (mémoire bornée).
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
SAT = float(os.environ.get("HC_GRADE_SAT", "1.18"))
GLOW = float(os.environ.get("HC_GRADE_GLOW", "1.0"))
info = json.load(open(os.path.join(SRC, "render.json")))
L = json.load(open(os.path.join(SRC, "layout.json")))
PPC, M = info["ppc"], info["margin"]
TAN = math.tan(math.radians(info["tilt_deg"]))
C = L.get("contract", {})


def gpx(cx, cy):
    """Case (sol, z = 0) → pixel de full.png (projection ground_square)."""
    return (cx + M) * PPC, (cy + M) * PPC


# Sources de lueur : (x px, y px, rayon x px, rayon y px, couleur RGB 0..1, intensité)
GLOWS = []
t = C.get("tent", {"c": [36.5, 44.5], "r": [16.0, 12.0]})
tx, ty = gpx(*t["c"])
GLOWS.append((tx, ty, (t["r"][0] + 7) * PPC, (t["r"][1] + 6) * PPC, (0.78, 0.3, 1.0), 0.3))
GLOWS.append((tx, ty, t["r"][0] * 0.75 * PPC, t["r"][1] * 0.75 * PPC, (0.65, 0.3, 1.0), 0.35))
for pth in C.get("paths", []):
    for (px_, py_) in pth["pts"]:
        x, y = gpx(px_, py_)
        GLOWS.append((x, y, 4.5 * PPC, 3.5 * PPC, (0.75, 0.3, 1.0), 0.18 if pth["role"] != "avenue" else 0.26))
lot = C.get("lot", [22, 111, 28, 14])
x, y = gpx(lot[0] + lot[2] / 2, lot[1] + 2)
GLOWS.append((x, y, 12 * PPC, 9 * PPC, (0.8, 0.3, 1.0), 0.3))
for rd in C.get("rides", []):
    x, y = gpx(*rd["c"])
    col = (0.85, 0.3, 1.0) if rd["kind"] == "ferris_wheel" else (1.0, 0.55, 0.35)
    GLOWS.append((x, y, (rd["r"] + 4) * PPC, (rd["r"] + 4) * PPC, col, 0.3))
for s in L.get("prop_spawns", []):
    if s["kind"] == "hc_lamp_post":
        x, y = gpx(s["cell"][0] + 0.95, s["cell"][1] + 0.5)
        GLOWS.append((x, y, 2.6 * PPC, 2.0 * PPC, (1.0, 0.7, 0.4), 0.28))


# Masque « hors parc » (cases VOID et marge), adouci : forêt plus sombre et violacée.
_TW, _TH = L["size"]
_m = np.ones((_TH + 2 * M, _TW + 2 * M), np.float32)
for _y, _row in enumerate(L["tiles"]):
    for _x, _ch in enumerate(_row):
        if _ch != "0":
            _m[_y + M, _x + M] = 0.0
from PIL import ImageFilter
_mi = Image.fromarray((_m * 255).astype(np.uint8)).resize(((_TW + 2 * M) * 8, (_TH + 2 * M) * 8), Image.BILINEAR)
OUT_MASK = _mi.filter(ImageFilter.GaussianBlur(10))
OUT_K = float(os.environ.get("HC_GRADE_OUTSIDE", "0.56"))
CURVE = float(os.environ.get("HC_GRADE_CURVE", "0.55"))


def outside(x0, y0, w, h):
    """Masque hors parc (h, w) en 0..1 pour le rectangle de pixels donné."""
    sx = OUT_MASK.width / ((_TW + 2 * M) * PPC)
    box = (x0 * sx, y0 * sx, (x0 + w) * sx, (y0 + h) * sx)
    return np.asarray(OUT_MASK.resize((w, h), Image.BILINEAR, box=box), np.float32) / 255.0


_HZ = None


def haze(x0, y0, w, h):
    """Champ de brume 0..1 : bruit de valeur lissé (grille de 6 cases), lu dans le rectangle."""
    global _HZ
    if _HZ is None:
        rngh = np.random.default_rng(7)
        gw, gh = (_TW + 2 * M) // 6 + 2, (_TH + 2 * M) // 6 + 2
        base = Image.fromarray((rngh.random((gh, gw)) * 255).astype(np.uint8)).resize(((_TW + 2 * M) * 8, (_TH + 2 * M) * 8), Image.BICUBIC)
        _HZ = base.filter(ImageFilter.GaussianBlur(14))
    sx = _HZ.width / ((_TW + 2 * M) * PPC)
    box = (x0 * sx, y0 * sx, (x0 + w) * sx, (y0 + h) * sx)
    v = np.asarray(_HZ.resize((w, h), Image.BILINEAR, box=box), np.float32) / 255.0
    return np.clip((v - 0.35) * 1.6, 0.0, 1.0)


def glow_field(x0, y0, w, h):
    """Champ additif (h, w, 3) de toutes les lueurs qui recoupent le rectangle."""
    out = np.zeros((h, w, 3), np.float32)
    ys = np.arange(y0, y0 + h, dtype=np.float32)[:, None]
    xs = np.arange(x0, x0 + w, dtype=np.float32)[None, :]
    for (gx, gy, rx, ry, col, k) in GLOWS:
        if gx + rx < x0 or gx - rx > x0 + w or gy + ry < y0 or gy - ry > y0 + h:
            continue
        d2 = ((xs - gx) / rx) ** 2 + ((ys - gy) / ry) ** 2
        f = np.clip(1.0 - d2, 0.0, 1.0) ** 2 * (k * GLOW)
        out += f[:, :, None] * np.array(col, np.float32)[None, None, :]
    return out


def grade(a, x0, y0):
    """a : uint8 (h, w, 3) dont le pixel (0, 0) est (x0, y0) dans full.png."""
    f = a.astype(np.float32) / 255.0
    lum = f @ np.array([0.299, 0.587, 0.114], np.float32)
    # saturation
    f = lum[:, :, None] + (f - lum[:, :, None]) * SAT
    # ombres : bleu nuit → violet (sans relever : les noirs restent profonds comme la planche)
    sh = np.clip(1.0 - lum / 0.28, 0.0, 1.0)[:, :, None]
    f = f + sh * np.array([0.025, 0.0, 0.02], np.float32)
    # intérieurs chauds : pixels orangés (R > G > B) renforcés
    warm = np.clip((f[:, :, 0] - f[:, :, 2]) * 3.0, 0.0, 1.0) * np.clip((f[:, :, 1] - f[:, :, 2]) * 3.0, 0.0, 1.0)
    f = f + warm[:, :, None] * np.array([0.06, 0.025, -0.02], np.float32)
    # hors parc : assombri, teinté violet nuit
    o = outside(x0, y0, a.shape[1], a.shape[0])[:, :, None]
    f = f * (1.0 - o * (1.0 - OUT_K)) + o * np.array([0.005, 0.012, 0.045], np.float32)
    # brume violette légère (bruit basse fréquence en coordonnées image, stable entre bandes)
    hz = haze(x0, y0, a.shape[1], a.shape[0])[:, :, None]
    f = f + hz * np.array([0.05, 0.015, 0.08], np.float32) * float(os.environ.get("HC_GRADE_HAZE", "0.45"))
    # lueurs au sol : ajout « screen » modulé (plus fort sur les zones sombres, garde les hautes lumières)
    g = glow_field(x0, y0, a.shape[1], a.shape[0])
    f = 1.0 - (1.0 - np.clip(f, 0, 1)) * (1.0 - g * (0.45 + 0.25 * (1.0 - np.clip(lum, 0, 1)))[:, :, None])
    # magentas → violets (la planche tire vers le violet bleuté)
    mag = np.clip((f[:, :, 0] - f[:, :, 1]) * 2.0, 0.0, 1.0) * np.clip((f[:, :, 2] - f[:, :, 1]) * 2.0, 0.0, 1.0)
    f = f + mag[:, :, None] * np.array([-0.07, 0.0, 0.05], np.float32)
    # courbe en S (contraste ombre / lumière marqué) puis gamma léger vers les tons sombres
    f = np.clip(f, 0.0, 1.0)
    sc = f * f * (3.0 - 2.0 * f)
    f = f + (sc - f) * CURVE
    f = np.power(f, 1.12)
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


process("full.png", 0, 0)
for b in info.get("buildings", []):
    n = "b%d_in.png" % b["id"]
    if os.path.exists(os.path.join(SRC, n)):
        process(n, b["px"][0], b["px"][1])
print("DONE grade", len(GLOWS), "glows")
