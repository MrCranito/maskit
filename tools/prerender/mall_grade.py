"""Post-étalonnage du rendu des Galeries Lumière (avant compose.py), sans re-rendu Blender.

Usage : python3 tools/prerender/mall_grade.py <render_dir>
Appliqué à render_dir/full.png ET à chaque b<id>_in.png (patchs d'intérieur, décalés de leur
position dans l'image : même résultat pixel pour pixel, raccords invisibles) :
  - appariement de la luminance sur les quantiles de la carte de la planche (colonne « Centre
    commercial abandonné » de docs/reference/cartes.png) ;
  - transfert de teinte par tranche de luminance (ombres bleu-violet, tons moyens beige rosé,
    hautes lumières ambrées) calé sur la même planche ;
  - boutiques plus sombres et plus chaudes que la galerie (lecture « pièces tamisées ») ;
  - dehors (rue, parking) bleu nuit ; halo chaud diffus (bloom) calculé sur l'image entière ;
    vignettage ; second appariement de luminance.
Idempotent : les originaux sont gardés en *_raw.png (relancer repart des originaux).
Réglages : MALL_GRADE_* (variables d'environnement).
"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageFilter

Image.MAX_IMAGE_PIXELS = None
SRC = sys.argv[1]
E = os.environ.get
MATCH = float(E("MALL_GRADE_MATCH", "0.75"))
MATCH2 = float(E("MALL_GRADE_MATCH2", "0.6"))
CHROMA = float(E("MALL_GRADE_CHROMA", "0.7"))
SAT = float(E("MALL_GRADE_SAT", "1.08"))
DARK_IN = float(E("MALL_GRADE_DARK_IN", "0.72"))
WARM_IN = float(E("MALL_GRADE_WARM_IN", "0.25"))
OUT_K = float(E("MALL_GRADE_OUT", "0.6"))
VIG = float(E("MALL_GRADE_VIG", "0.6"))
HAZE = float(E("MALL_GRADE_HAZE", "0.3"))
CLARITY = float(E("MALL_GRADE_CLARITY", "0.35"))
LIFT = float(E("MALL_GRADE_LIFT", "0.12"))
SHOULDER = float(E("MALL_GRADE_SHOULDER", "0.6"))

info = json.load(open(os.path.join(SRC, "render.json")))
L = json.load(open(os.path.join(SRC, "layout.json")))
PPC, M = info["ppc"], info["margin"]
TW, TH = L["size"]
FW, FH = (TW + 2 * M) * PPC, (TH + 2 * M) * PPC
LW = np.array([0.299, 0.587, 0.114], np.float32)

# ---------------------------------------------------------------- référence (planche)
_REF = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "reference", "cartes.png")
_ref = np.asarray(Image.open(_REF).convert("RGB").crop((880, 145, 1312, 925)), np.float32) / 255.0
_rl = _ref @ LW
REF_Q = np.percentile(_rl, np.arange(0, 101, 5)).astype(np.float32)
REF_Q[0], REF_Q[-1] = 0.0, 1.0
NB = 12
BINS = np.linspace(0.0, 1.0, NB + 1)


def chroma_table(a, l):
    """Teinte moyenne (rgb - lum) par tranche de luminance."""
    out = np.zeros((NB, 3), np.float32)
    cnt = np.zeros(NB, np.float32)
    idx = np.clip((l * NB).astype(np.int32), 0, NB - 1)
    for i in range(NB):
        m = idx == i
        cnt[i] = m.sum()
        if cnt[i] > 30:
            out[i] = (a[m] - l[m][:, None]).mean(0)
    return out, cnt


REF_CH, REF_CNT = chroma_table(_ref, _rl)
# tranches absentes de la planche : on prolonge la dernière tranche connue
for i in range(NB):
    if REF_CNT[i] <= 30:
        j = max([k for k in range(NB) if REF_CNT[k] > 30 and k < i] or [0])
        REF_CH[i] = REF_CH[j] * 0.6

# ---------------------------------------------------------------- masques (cases)
def cell_mask(pred, blur):
    m = np.zeros((TH + 2 * M, TW + 2 * M), np.float32)
    for y, row in enumerate(L["tiles"]):
        for x, ch in enumerate(row):
            if pred(x, y, ch):
                m[y + M, x + M] = 1.0
    if pred(-1, -1, "margin"):
        m[:M, :] = 1.0
        m[-M:, :] = 1.0
        m[:, :M] = 1.0
        m[:, -M:] = 1.0
    im = Image.fromarray((m * 255).astype(np.uint8)).resize(((TW + 2 * M) * 8, (TH + 2 * M) * 8), Image.BILINEAR)
    return im.filter(ImageFilter.GaussianBlur(blur))


_park = L.get("contract", {}).get("parking", [1, 106, 64, 16])


def _in_park(x, y):
    return _park[0] <= x < _park[0] + _park[2] and _park[1] <= y < _park[1] + _park[3]


SHOP_MASK = cell_mask(lambda x, y, ch: ch == "2", 5)
OUT_MASK = cell_mask(lambda x, y, ch: ch == "margin" or ch == "0" or (ch != "3" and _in_park(x, y)), 6)


def sample(mask, x0, y0, w, h):
    sx = mask.width / FW
    box = (x0 * sx, y0 * sx, (x0 + w) * sx, (y0 + h) * sx)
    return np.asarray(mask.resize((w, h), Image.BILINEAR, box=box), np.float32) / 255.0


# ---------------------------------------------------------------- tables calculées sur full.png
LUT = None
LUT2 = None
CH_DELTA = None
HAZE_MAP = None


def lut_from(a, k):
    l = a @ LW
    q = np.percentile(l, np.arange(0, 101, 5)).astype(np.float32)
    q = np.maximum.accumulate(q + np.arange(21, dtype=np.float32) * 1e-5)
    x = np.linspace(0.0, 1.0, 256, dtype=np.float32)
    return x * (1.0 - k) + np.interp(x, q, REF_Q) * k


STAT_PAD = float(E("MALL_GRADE_STAT_PAD", "1.5"))   # marge (cases) gardée autour du bâtiment pour les statistiques


def thumb(im):
    """Vignette de l'image cadrée comme la planche (bâtiment + parking + une bande de rue)."""
    c = max(0, int((M - STAT_PAD) * PPC * im.width / FW))
    t = im.crop((c, c, im.width - c, im.height - c))
    t.thumbnail((900, 900))
    return np.asarray(t, np.float32) / 255.0


def apply_lut(f, lut):
    lum = f @ LW
    nl = lut[np.clip(lum * 255.0, 0, 255).astype(np.int32)]
    return f * (nl / np.maximum(lum, 1e-3))[:, :, None]


def stage1(a, x0, y0):
    f = a.astype(np.float32) / 255.0
    if LUT is not None:
        f = apply_lut(f, LUT)
    lum = f @ LW
    # transfert de teinte par tranche (interpolé entre tranches)
    if CH_DELTA is not None:
        t = np.clip(lum * NB - 0.5, 0, NB - 1)
        i0 = np.floor(t).astype(np.int32)
        i1 = np.minimum(i0 + 1, NB - 1)
        w = (t - i0)[:, :, None]
        d = CH_DELTA[i0] * (1 - w) + CH_DELTA[i1] * w
        f = f + d * CHROMA
    h_, w_ = a.shape[:2]
    # boutiques : plus sombres, plus chaudes
    s = sample(SHOP_MASK, x0, y0, w_, h_)[:, :, None]
    f = f * (1.0 - s * (1.0 - DARK_IN))
    warm = np.array([1.06, 0.98, 0.86], np.float32)
    f = f * (1.0 + s * WARM_IN * (warm - 1.0) / 0.25 * 0.25)
    # dehors : bleu nuit
    if OUT_K > 0:
        o = sample(OUT_MASK, x0, y0, w_, h_)[:, :, None]
        lo = (f @ LW)[:, :, None]
        night = f * 0.35 + lo * np.array([0.92, 0.9, 1.12], np.float32) * 0.65
        f = f * (1 - o * OUT_K) + night * (o * OUT_K)
    # vignettage
    ys = (np.arange(y0, y0 + h_, dtype=np.float32)[:, None] / FH - 0.5) * 2.0
    xs = (np.arange(x0, x0 + w_, dtype=np.float32)[None, :] / FW - 0.5) * 2.0
    v = np.clip((xs * xs * 0.9 + ys * ys * 0.5) - 0.3, 0.0, 1.0)[:, :, None] * VIG
    f = f * (1.0 - v) + f * np.array([0.55, 0.5, 0.75], np.float32) * v
    if SAT != 1.0:
        l2 = (f @ LW)[:, :, None]
        f = l2 + (f - l2) * SAT
    return np.clip(f, 0, 1)


def build_haze(im):
    global HAZE_MAP
    t = im.resize((max(1, im.width // 8), max(1, im.height // 8)), Image.BILINEAR)
    a = np.asarray(t, np.float32) / 255.0
    l = a @ LW
    k = np.clip((l - 0.4) / 0.35, 0.0, 1.0)[:, :, None]
    hi = Image.fromarray((np.clip(a * k, 0, 1) * 255).astype(np.uint8))
    r = max(2, int(PPC * 1.0 / 8))
    b1 = np.asarray(hi.filter(ImageFilter.GaussianBlur(r)), np.float32) / 255.0
    b2 = np.asarray(hi.filter(ImageFilter.GaussianBlur(r * 4)), np.float32) / 255.0
    h = (b1 * 0.6 + b2 * 0.7) * np.array([1.0, 0.8, 0.6], np.float32)
    HAZE_MAP = Image.fromarray((np.clip(h, 0, 1) * 255).astype(np.uint8))


def stage2(f, x0, y0):
    if LUT2 is not None:
        f = apply_lut(f, LUT2)
    # noirs relevés vers un brun-violet (ombres « peintes » de la planche, jamais noires) et
    # épaule douce des hautes lumières (reflets des plafonniers ambrés, pas blancs)
    if LIFT > 0:
        f = f * (1.0 - LIFT) + np.array([0.16, 0.12, 0.2], np.float32) * LIFT
    if SHOULDER < 1.0:
        lum = f @ LW
        k = SHOULDER
        nl = np.where(lum > k, k + (1 - k) * (1 - np.exp(-(lum - k) / (1 - k))) * 0.85, lum)
        f = f * (nl / np.maximum(lum, 1e-4))[:, :, None]
        hot = np.clip((lum - k) / (1 - k), 0, 1)[:, :, None]
        f = f * (1 - 0.25 * hot) + f * np.array([1.08, 0.93, 0.72], np.float32) * (0.25 * hot)
    h_, w_ = f.shape[:2]
    if HAZE_MAP is not None and HAZE > 0:
        sx = HAZE_MAP.width / FW
        box = (x0 * sx, y0 * sx, (x0 + w_) * sx, (y0 + h_) * sx)
        g = np.asarray(HAZE_MAP.resize((w_, h_), Image.BILINEAR, box=box), np.float32) / 255.0 * HAZE
        f = 1.0 - (1.0 - np.clip(f, 0, 1)) * (1.0 - g)
    return np.clip(f, 0, 1)


def clarity(im):
    if CLARITY <= 0:
        return im
    return im.filter(ImageFilter.UnsharpMask(radius=max(2, int(PPC * 0.6)), percent=int(CLARITY * 100), threshold=1))


def process(name, x0, y0, final=True, band=512):
    p = os.path.join(SRC, name)
    raw = p[:-4] + "_raw.png"
    # nouveau rendu (pas la sortie d'un étalonnage précédent) : il devient l'original
    if not os.path.exists(raw) or os.path.getmtime(p) != GRADED.get(name):
        shutil.copy(p, raw)
    im = Image.open(raw).convert("RGB")
    W, H = im.size
    out = Image.new("RGB", (W, H))
    for yy in range(0, H, band):
        hh = min(band, H - yy)
        a = np.asarray(im.crop((0, yy, W, yy + hh)), dtype=np.uint8)
        f = stage1(a, x0, y0 + yy)
        if final:
            f = stage2(f, x0, y0 + yy)
        out.paste(Image.fromarray((f * 255 + 0.5).astype(np.uint8)), (0, yy))
    print("GRADE", name, W, H, flush=True)
    return clarity(out) if final else out


_GP = os.path.join(SRC, "grade.json")
GRADED = json.load(open(_GP)) if os.path.exists(_GP) else {}


def save(im, name):
    p = os.path.join(SRC, name)
    im.save(p)
    GRADED[name] = os.path.getmtime(p)
    json.dump(GRADED, open(_GP, "w"))


if __name__ == "__main__":
    raw = os.path.join(SRC, "full_raw.png")
    fp = os.path.join(SRC, "full.png")
    fresh = not os.path.exists(raw) or os.path.getmtime(fp) != GRADED.get("full.png")
    base = Image.open(fp if fresh else raw).convert("RGB")
    a = thumb(base)
    LUT = lut_from(a, MATCH)
    a1 = apply_lut(a, LUT)
    l1 = a1 @ LW
    ch, cnt = chroma_table(a1, l1)
    CH_DELTA = np.where((cnt > 30)[:, None], REF_CH - ch, 0.0).astype(np.float32)
    first = process("full.png", 0, 0, final=False)
    a2 = thumb(first)
    LUT2 = lut_from(a2, MATCH2)
    build_haze(first)
    save(process("full.png", 0, 0), "full.png")
    for b in info.get("buildings", []):
        n = "b%d_in.png" % b["id"]
        if os.path.exists(os.path.join(SRC, n)):
            save(process(n, b["px"][0], b["px"][1]), n)
    print("DONE grade")
