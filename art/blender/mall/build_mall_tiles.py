"""Textures peintes du biome « centre commercial abandonné » (Galeries Lumière).

Usage (depuis la racine du projet) :
    python3 art/blender/mall/build_mall_tiles.py

Pas de Blender ici : peinture procédurale numpy (mêmes outils que art/blender/build_tiles.py :
bruits périodiques, coups de pinceau, cailloux…) => sols tuilables.
Densité : 2 px par unité monde (1 case = 64 unités = 128 px).
Lumière : couchant à l'ouest (haut-gauche), ombres bleu nuit vers le bas-droite.

Sorties :
  assets/textures/mall/ground/{tiles,lino,parquet,carpet,marble,concrete,roof,macro}.png
  assets/textures/mall/walls.png + walls_meta.gd   (atlas des faces de murs et dessus)
  $RDM_TMP/mall/decals/*.png                         (décalques, empaquetés par build_mall_props.py)
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import build_tiles as BT  # noqa: E402  (outils de peinture communs)
from build_tiles import C, Canvas, NIGHT, OUTLINE, ellipse_mask, poly_mask, seg_mask, noise, ramp  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEX_DIR = os.path.join(ROOT, "assets", "textures", "mall")
TMP = os.path.join(os.environ.get("RDM_TMP", "/tmp/rdm_mall"), "decals")

N = 512


def grain(cv: Canvas, rng, amp: float) -> None:
    BT.fine_grain(cv, rng, amp)


def moss_blob(cv: Canvas, x: float, y: float, r: float, rng, strength: float = 1.0) -> None:
    """Tache de mousse (verts sourds, cœur plus clair), bords irréguliers."""
    cols = [C(70, 96, 52), C(96, 128, 64), C(128, 152, 76), C(58, 78, 50)]
    for _ in range(int(6 + r)):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(0, r * 0.8)
        rr = rng.uniform(r * 0.25, r * 0.55)
        m, R = ellipse_mask(rr, rr * rng.uniform(0.6, 1.0), rng.uniform(0, 3), soft=1.5)
        cv.blend(int(y + math.sin(a) * d - R), int(x + math.cos(a) * d - R), m, cols[rng.integers(0, 4)], 0.55 * strength)


def weed(cv: Canvas, x: float, y: float, size: float, rng) -> None:
    BT.grass_tuft(cv, x, y, size, rng, cols=[C(150, 196, 96), C(96, 150, 70), C(70, 120, 60), C(52, 92, 50)])


# ============================================================================ sols

def make_tiles(seed: int) -> Image.Image:
    """Carrelage de galerie : dalles crème 64 px (32 u), dalles d'accent rose terre cuite en
    motif diagonal, joints sombres, fissures, dalles manquantes (terre + herbes), mousse."""
    rng = np.random.default_rng(seed)
    n, ts = N, 64
    vein = noise(n, 1.6, rng, aniso=(0.35, 1.0))
    big = noise(n, 2.6, rng)
    img = np.zeros((n, n, 3), np.float32)
    cream = [C(236, 222, 198), C(228, 212, 188), C(240, 228, 206), C(222, 206, 182)]
    accent = [C(206, 162, 138), C(196, 150, 128)]
    missing = set()
    for _ in range(0):
        missing.add((int(rng.integers(0, n // ts)), int(rng.integers(0, n // ts))))
    for j in range(n // ts):
        for i in range(n // ts):
            y0, x0 = j * ts, i * ts
            acc = (i + j) % 4 == 0 and (i - j) % 4 == 0
            base = accent[(i + j) % 2] if acc else cream[int(rng.integers(0, 4))]
            v = vein[y0:y0 + ts, x0:x0 + ts]
            blk = base[None, None] * (0.94 + 0.1 * v[..., None]) * (0.95 + 0.08 * big[y0:y0 + ts, x0:x0 + ts, None])
            # Veines fines du marbre.
            vv = np.abs(np.sin(v * 18.0 + i * 1.7))
            blk *= (1.0 - 0.07 * (vv < 0.08))[..., None]
            img[y0:y0 + ts, x0:x0 + ts] = blk
    cv = Canvas(n, n, img)
    BT.strokes(cv, 1600, rng, lambda y, x: np.clip(img[y, x] * rng.uniform(0.93, 1.06), 0, 255),
               length=(8, 18), width=(3, 6), opacity=0.25)
    # Joints (3 px) + biseau clair haut-gauche de chaque dalle.
    for k in range(0, n, ts):
        cv.blend(k - 1, 0, np.ones((3, n), np.float32), C(120, 98, 92), 0.95)
        cv.blend(0, k - 1, np.ones((n, 3), np.float32), C(120, 98, 92), 0.95)
        cv.blend(k + 2, 0, np.ones((1, n), np.float32), C(255, 244, 222), 0.45)
        cv.blend(0, k + 2, np.ones((n, 1), np.float32), C(255, 244, 222), 0.35)
        cv.blend(k - 3, 0, np.ones((1, n), np.float32), NIGHT, 0.18)
    # Crasse dans les joints, mousse qui gagne.
    for _ in range(60):
        gx = int(rng.integers(0, n // ts)) * ts
        gy = rng.uniform(0, n)
        if rng.random() < 0.5:
            moss_blob(cv, gx, gy, rng.uniform(3, 7), rng, 0.7)
        else:
            moss_blob(cv, gy, gx, rng.uniform(3, 7), rng, 0.7)
    for _ in range(14):
        BT.crack(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(18, 46), rng, C(110, 84, 76), 1.5)
    # Dalles manquantes : chape de ciment / terre + herbes.
    for (i, j) in missing:
        y0, x0 = j * ts, i * ts
        pts = [(4, 6), (ts - 6, 3), (ts - 3, ts - 8), (ts / 2, ts - 3), (5, ts - 6)]
        pm, px0, py0 = poly_mask(pts, 1.2)
        cv.blend(y0 + py0, x0 + px0, pm, C(104, 86, 74))
        sh, sx, sy = poly_mask([(p[0] + 3, p[1] + 3) for p in pts[:2]] + [(ts - 4, ts / 2)], 3)
        cv.blend(y0 + 3, x0 + 3, np.ones((5, ts - 8), np.float32), NIGHT, 0.4)
        for _ in range(12):
            BT.pebble(cv, x0 + rng.uniform(10, ts - 10), y0 + rng.uniform(10, ts - 10), rng.uniform(1.5, 3.5), rng, C(176, 150, 130))
        for _ in range(3):
            weed(cv, x0 + rng.uniform(12, ts - 12), y0 + rng.uniform(24, ts - 8), rng.uniform(9, 14), rng)
        del sh, sx, sy
    for _ in range(10):
        weed(cv, rng.integers(0, n // ts) * ts + rng.uniform(-2, 2), rng.uniform(0, n), rng.uniform(6, 10), rng)
    # Taches d'eau / salissures douces.
    for _ in range(10):
        m, R = ellipse_mask(rng.uniform(14, 36), rng.uniform(8, 20), rng.uniform(0, 3), soft=10)
        cv.blend(int(rng.uniform(0, n)) - R, int(rng.uniform(0, n)) - R, m, C(150, 124, 104), 0.22)
    grain(cv, rng, 3.5)
    return cv.image().convert("RGB")


def make_lino(seed: int) -> Image.Image:
    """Lino en damier vert d'eau / crème (supermarché, pharmacie), usé, rayé."""
    rng = np.random.default_rng(seed)
    n, ts = N, 64
    t = noise(n, 2.2, rng)
    img = np.zeros((n, n, 3), np.float32)
    a, b = C(150, 186, 168), C(232, 224, 200)
    for j in range(n // ts):
        for i in range(n // ts):
            col = a if (i + j) % 2 == 0 else b
            img[j * ts:(j + 1) * ts, i * ts:(i + 1) * ts] = col * rng.uniform(0.95, 1.04)
    img *= (0.9 + 0.16 * t[..., None])
    cv = Canvas(n, n, img)
    BT.strokes(cv, 900, rng, lambda y, x: np.clip(img[y, x] * rng.uniform(0.92, 1.06), 0, 255),
               length=(10, 24), width=(3, 5), opacity=0.22)
    for k in range(0, n, ts):
        cv.blend(k, 0, np.ones((1, n), np.float32), C(90, 90, 84), 0.6)
        cv.blend(0, k, np.ones((n, 1), np.float32), C(90, 90, 84), 0.6)
    for _ in range(40):  # rayures de chariots
        x, y = rng.uniform(0, n), rng.uniform(0, n)
        mk, ox, oy = seg_mask(x, y, x + rng.uniform(-60, 60), y + rng.uniform(-8, 8), 1.0)
        cv.blend(oy, ox, mk, C(70, 70, 70), 0.25)
    for _ in range(12):
        m, R = ellipse_mask(rng.uniform(10, 30), rng.uniform(8, 18), rng.uniform(0, 3), soft=8)
        cv.blend(int(rng.uniform(0, n)) - R, int(rng.uniform(0, n)) - R, m, C(110, 96, 80), 0.25)
    for _ in range(6):
        BT.crack(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(20, 40), rng, C(90, 80, 70), 1.2)
    grain(cv, rng, 3.0)
    return cv.image().convert("RGB")


def make_parquet(seed: int) -> Image.Image:
    """Parquet à lames décalées (boutiques), vernis usé, lames gondolées par l'humidité."""
    rng = np.random.default_rng(seed)
    n, bh = N, 24
    grainn = noise(n, 1.4, rng, aniso=(0.05, 1.0))
    img = np.zeros((n, n, 3), np.float32)
    pal = [C(176, 120, 76), C(160, 106, 68), C(188, 132, 84), C(150, 98, 64)]
    cv_cuts = []
    for r in range(n // bh):
        y0 = r * bh
        off = int(rng.integers(0, 6)) * 32
        x = -off
        while x < n:
            ln = int(rng.integers(3, 7)) * 32
            col = pal[int(rng.integers(0, 4))] * rng.uniform(0.94, 1.05)
            for xx in range(max(x, 0), min(x + ln, n)):
                img[y0:y0 + bh, xx] = col
            cv_cuts.append((y0, x % n))
            x += ln
    img *= (0.88 + 0.22 * grainn[..., None])
    cv = Canvas(n, n, img)
    for r in range(n // bh):
        cv.blend(r * bh, 0, np.ones((2, n), np.float32), C(70, 44, 36), 0.85)
        cv.blend(r * bh + 2, 0, np.ones((1, n), np.float32), C(236, 196, 140), 0.4)
    for (y0, x) in cv_cuts:
        cv.blend(y0, x, np.ones((bh, 2), np.float32), C(70, 44, 36), 0.8)
    for _ in range(18):
        m, R = ellipse_mask(rng.uniform(16, 40), rng.uniform(10, 24), rng.uniform(0, 3), soft=12)
        cv.blend(int(rng.uniform(0, n)) - R, int(rng.uniform(0, n)) - R, m, C(110, 76, 60), 0.25)
    grain(cv, rng, 3.0)
    return cv.image().convert("RGB")


def make_carpet(seed: int) -> Image.Image:
    """Moquette bordeaux à motif géométrique (cinéma, bureaux), taches et usure."""
    rng = np.random.default_rng(seed)
    n = N
    t = noise(n, 2.0, rng)
    img = ramp(t, [(0, C(92, 34, 56)), (0.5, C(114, 44, 66)), (1, C(132, 56, 78))])
    cv = Canvas(n, n, img)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    # Motif : losanges dorés et points violets (période 64 px).
    u = (xx % 64) - 32
    v = (yy % 64) - 32
    dia = np.abs(np.abs(u) + np.abs(v) - 22) < 2.2
    dot = np.hypot(u, v) < 4
    cv.a[..., :3] = np.where(dia[..., None], cv.a[..., :3] * 0.4 + C(214, 160, 84) * 0.6, cv.a[..., :3])
    cv.a[..., :3] = np.where(dot[..., None], cv.a[..., :3] * 0.3 + C(150, 90, 190) * 0.7, cv.a[..., :3])
    fib = rng.standard_normal((n, n)).astype(np.float32) * 9
    cv.a[..., :3] = np.clip(cv.a[..., :3] + fib[..., None], 0, 255)
    for _ in range(16):
        m, R = ellipse_mask(rng.uniform(12, 34), rng.uniform(8, 22), rng.uniform(0, 3), soft=9)
        cv.blend(int(rng.uniform(0, n)) - R, int(rng.uniform(0, n)) - R, m, C(64, 30, 40), 0.3)
    return cv.image().convert("RGB")


def make_marble(seed: int) -> Image.Image:
    """Grandes dalles de marbre sombre veiné (bijouterie, high-tech) à joints dorés."""
    rng = np.random.default_rng(seed)
    n, ts = N, 128
    vein = noise(n, 1.5, rng, aniso=(0.5, 1.0))
    img = ramp(vein, [(0, C(36, 32, 48)), (0.5, C(58, 52, 72)), (1, C(84, 76, 96))])
    vv = np.abs(np.sin(vein * 22.0))
    img = np.where((vv < 0.06)[..., None], img * 0.5 + C(220, 210, 230) * 0.5, img)
    cv = Canvas(n, n, img)
    for k in range(0, n, ts):
        cv.blend(k - 1, 0, np.ones((2, n), np.float32), C(200, 160, 80), 0.85)
        cv.blend(0, k - 1, np.ones((n, 2), np.float32), C(200, 160, 80), 0.85)
    for _ in range(8):
        BT.crack(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(20, 50), rng, C(20, 18, 30), 1.3)
    grain(cv, rng, 2.5)
    return cv.image().convert("RGB")


def make_concrete(seed: int) -> Image.Image:
    """Béton de parking : dalle grise, joints de dilatation, taches d'huile, humidité."""
    rng = np.random.default_rng(seed)
    n = N
    t = 0.6 * noise(n, 2.4, rng) + 0.4 * noise(n, 1.6, rng)
    img = ramp(t, [(0, C(104, 102, 110)), (0.5, C(132, 128, 134)), (1, C(156, 150, 150))])
    cv = Canvas(n, n, img)
    BT.strokes(cv, 1400, rng, lambda y, x: np.clip(img[y, x] * rng.uniform(0.9, 1.08), 0, 255),
               length=(10, 26), width=(4, 8), opacity=0.25)
    for k in (0, 256):
        cv.blend(k, 0, np.ones((2, n), np.float32), C(70, 68, 80), 0.8)
        cv.blend(0, k, np.ones((n, 2), np.float32), C(70, 68, 80), 0.8)
    for _ in range(5):
        m, R = ellipse_mask(rng.uniform(16, 40), rng.uniform(10, 26), rng.uniform(0, 3), soft=14)
        cv.blend(int(rng.uniform(0, n)) - R, int(rng.uniform(0, n)) - R, m, C(70, 70, 84), 0.2)
    for _ in range(10):
        BT.crack(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(24, 60), rng, C(70, 66, 76), 1.4)
    for _ in range(40):
        BT.pebble(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(1.2, 2.6), rng, C(150, 146, 150), outline=False)
    grain(cv, rng, 4.0)
    return cv.image().convert("RGB")


def make_roof(seed: int) -> Image.Image:
    """Toit-terrasse : membrane bitumée à gravillons, lés soudés, flaques séchées, mousse."""
    rng = np.random.default_rng(seed)
    n = N
    t = 0.5 * noise(n, 2.4, rng) + 0.5 * noise(n, 1.4, rng)
    img = ramp(t, [(0, C(120, 118, 128)), (0.5, C(146, 142, 146)), (1, C(172, 166, 162))])
    cv = Canvas(n, n, img)
    for _ in range(2600):
        r = rng.uniform(0.8, 2.0)
        x, y = rng.uniform(0, n), rng.uniform(0, n)
        m, R = ellipse_mask(r, r * 0.85)
        cv.blend(int(y - R + 1), int(x - R + 1), m, NIGHT, 0.2)
        cv.blend(int(y - R), int(x - R), m, C(176, 160, 148) if rng.random() < 0.5 else C(92, 84, 90), 0.8)
    for k in range(0, n, 256):
        cv.blend(k, 0, np.ones((3, n), np.float32), C(96, 88, 96), 0.35)
    for _ in range(18):
        moss_blob(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(4, 10), rng, 0.8)
    for _ in range(4):
        m, R = ellipse_mask(rng.uniform(20, 40), rng.uniform(12, 24), rng.uniform(0, 3), soft=16)
        cv.blend(int(rng.uniform(0, n)) - R, int(rng.uniform(0, n)) - R, m, C(90, 86, 100), 0.2)
    grain(cv, rng, 3.0)
    return cv.image().convert("RGB")


# ============================================================================ murs (atlas)
FW, FH = 128, 104


def _frame(h: int, w: int, t: float) -> np.ndarray:
    return BT._frame(h, w, t)


def _foot_ao(cv: Canvas, strength: float = 0.55) -> None:
    g = np.linspace(0, 1, 14)[:, None] ** 1.5 * np.ones((1, cv.w))
    cv.blend(cv.h - 14, 0, g.astype(np.float32), NIGHT * 0.7, strength)


def face_plaster(rng, v: int) -> np.ndarray:
    """Mur de galerie : enduit crème, bandeau, plinthe de marbre, taches d'humidité, mousse."""
    w, h = FW, FH
    t = noise(256, 2.2, rng)[:h, :w]
    base = C(226, 200, 170)
    img = ramp(t, [(0, base * 0.88), (0.5, base), (1, np.minimum(base * 1.06, 255))])
    cv = Canvas(h, w, img, wrap=False)
    BT.strokes(cv, 150, rng, lambda y, x: np.clip(img[y, x] * rng.uniform(0.93, 1.07), 0, 255),
               length=(10, 24), width=(4, 8), opacity=0.28)
    # Bandeau haut (frise rose) et corniche.
    cv.blend(0, 0, np.ones((10, w), np.float32), C(196, 150, 140))
    cv.blend(0, 0, np.ones((2, w), np.float32), C(250, 220, 200))
    cv.blend(10, 0, np.ones((3, w), np.float32), NIGHT, 0.35)
    cv.blend(16, 0, np.ones((3, w), np.float32), C(180, 120, 130), 0.8)
    # Coulures d'humidité.
    for _ in range(int(rng.integers(1, 4))):
        x = rng.uniform(4, w - 4)
        ln = rng.uniform(20, 60)
        mk, ox, oy = seg_mask(x, 18, x + rng.uniform(-3, 3), 18 + ln, rng.uniform(5, 10), 1.0)
        cv.blend(oy, ox, mk, C(140, 120, 104), 0.28)
    if v == 1:
        # Enduit tombé : briques.
        ox, oy = int(rng.uniform(14, w - 56)), int(rng.uniform(30, 50))
        pts = [(0, 6), (16, 0), (42, 4), (46, 20), (30, 28), (4, 24)]
        pm, px0, py0 = poly_mask(pts, 1.2)
        cv.blend(oy + py0, ox + px0, pm, C(150, 86, 66))
        for by in range(0, 26, 7):
            for bx in range((by // 7) % 2 * 6, 44, 12):
                cv.blend(oy + by + 1, ox + bx + 1, np.ones((5, 10), np.float32) * 0.8, C(176, 104, 80) * rng.uniform(0.9, 1.1))
        pm2, qx, qy = poly_mask(pts, 2.5)
        cv.blend(oy + qy, ox + qx, np.clip(pm2 * 3 * (1 - pm2), 0, 1), OUTLINE, 0.7)
    if v == 2:
        BT.crack(cv, rng.uniform(20, 100), rng.uniform(26, 50), 50, rng, C(120, 96, 84), 1.4)
    if v == 3:
        # Affiche promotionnelle déchirée (rose néon passé).
        px, py = int(rng.uniform(30, 60)), 26
        cv.blend(py + 3, px + 3, np.ones((40, 30), np.float32), NIGHT, 0.35)
        cv.blend(py, px, np.ones((40, 30), np.float32), C(236, 120, 170))
        cv.blend(py + 6, px + 4, np.ones((10, 22), np.float32), C(255, 236, 200))
        cv.blend(py + 22, px + 4, np.ones((3, 22), np.float32), C(90, 40, 90))
        cv.blend(py + 28, px + 4, np.ones((3, 16), np.float32), C(90, 40, 90))
        tear, tx, ty = poly_mask([(0, 0), (30, 0), (30, 12), (14, 18), (0, 8)], 1.0)
        cv.blend(py + 26 + ty, px + tx, tear * 0.9, img[60, 60] * 0.95)
        cv.blend(py, px, _frame(40, 30, 1.2), OUTLINE, 0.8)
    # Plinthe de marbre rose + mousse au pied.
    cv.blend(h - 14, 0, np.ones((14, w), np.float32), C(170, 116, 108))
    cv.blend(h - 14, 0, np.ones((2, w), np.float32), C(230, 180, 160))
    for _ in range(int(rng.integers(2, 6))):
        moss_blob(cv, rng.uniform(0, w), h - 10, rng.uniform(4, 9), rng)
    if rng.random() < 0.6:
        BT.grass_tuft(cv, rng.uniform(10, w - 10), h - 2, rng.uniform(10, 16), rng,
                      cols=[C(150, 196, 96), C(96, 150, 70), C(70, 120, 60), C(52, 92, 50)])
    _foot_ao(cv)
    BT.fine_grain(cv, rng, 3.0)
    return cv.a


def face_vitrine(rng, v: int) -> np.ndarray:
    """Devanture de boutique : vitrine sombre (reflets du couchant), montants métalliques,
    soubassement ; variantes : vitre brisée, rideau métallique à demi baissé, mannequin."""
    w, h = FW, FH
    cv = Canvas(h, w, C(70, 66, 80), wrap=False)
    # Bandeau d'enseigne (haut) sombre — le néon est ajouté en jeu.
    cv.blend(0, 0, np.ones((14, w), np.float32), C(52, 46, 62))
    cv.blend(0, 0, np.ones((2, w), np.float32), C(150, 130, 150))
    cv.blend(14, 0, np.ones((3, w), np.float32), C(36, 32, 46))
    # Vitre.
    gy, gh = 17, h - 17 - 16
    yy = np.linspace(0, 1, gh)[:, None]
    xx = np.linspace(0, 1, w)[None, :]
    inside = C(34, 40, 62)[None, None] * (0.8 + 0.4 * yy[..., None]) * np.ones((1, w, 1))
    refl = np.clip(1.0 - (xx * 0.7 + yy * 1.3), 0, 1)[..., None]
    pane = inside * (1 - 0.55 * refl) + C(250, 150, 120) * 0.55 * refl
    # Bande de reflet violet en bas (néons d'en face).
    pane += (np.clip(yy - 0.7, 0, 1) * 1.6)[..., None] * C(90, 40, 110)
    if v == 3:
        # Silhouette de mannequin derrière la vitre.
        cx = 64
        m, R = ellipse_mask(6, 7)
        sil = np.zeros((gh, w), np.float32)
        sil[max(0, 14 - R):14 + R + 1, cx - R:cx + R + 1] = np.maximum(sil[max(0, 14 - R):14 + R + 1, cx - R:cx + R + 1], m[:min(2 * R + 1, 14 + R + 1)])
        pmb, bx0, by0 = poly_mask([(cx - 12, 22), (cx + 12, 22), (cx + 9, 50), (cx + 14, gh), (cx - 14, gh), (cx - 9, 50)], 1.0)
        ys, xs = slice(max(by0, 0), min(by0 + pmb.shape[0], gh)), slice(bx0, bx0 + pmb.shape[1])
        sil[ys, xs] = np.maximum(sil[ys, xs], pmb[:sil[ys, xs].shape[0], :sil[ys, xs].shape[1]])
        pane = pane * (1 - sil[..., None] * 0.6) + C(20, 18, 30) * sil[..., None] * 0.6
    cv.blend(gy, 0, np.ones((gh, w), np.float32), np.clip(pane, 0, 255))
    # Reflets diagonaux.
    for (x0, wdt) in ((18, 5.0), (30, 2.0), (86, 4.0)):
        mk, ox, oy = seg_mask(x0, gy + gh - 4, x0 + 26, gy + 4, wdt)
        cv.blend(oy, ox, mk, C(255, 236, 214), 0.28)
    if v == 1:
        # Vitre brisée : trou étoilé, éclats.
        cx, cy = rng.uniform(40, 90), rng.uniform(36, 60)
        pts = []
        for k in range(10):
            a = k / 10 * 2 * math.pi
            r = rng.uniform(10, 22) if k % 2 == 0 else rng.uniform(5, 10)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.9))
        pm, px0, py0 = poly_mask(pts, 0.8)
        cv.blend(py0, px0, pm, C(14, 12, 24))
        for k in range(7):
            a = rng.uniform(0, 2 * math.pi)
            mk, ox, oy = seg_mask(cx, cy, cx + math.cos(a) * rng.uniform(26, 48), cy + math.sin(a) * rng.uniform(18, 34), 1.0)
            cv.blend(oy, ox, mk, C(230, 230, 250), 0.6)
    if v == 2:
        # Rideau métallique à demi baissé.
        sh = int(rng.uniform(30, 48))
        cv.blend(gy, 0, np.ones((sh, w), np.float32), C(150, 150, 160))
        for yy2 in range(gy, gy + sh, 5):
            cv.blend(yy2, 0, np.ones((1, w), np.float32), C(90, 90, 104))
            cv.blend(yy2 + 1, 0, np.ones((1, w), np.float32), C(200, 200, 210), 0.6)
        cv.blend(gy + sh, 0, np.ones((4, w), np.float32), C(70, 70, 84))
        cv.blend(gy + sh + 4, 0, np.ones((4, w), np.float32), NIGHT, 0.4)
        # Graffiti rose.
        for k in range(3):
            mk, ox, oy = seg_mask(20 + k * 30, gy + 10 + k * 3, 40 + k * 30, gy + 20 - k * 2, 3.0)
            cv.blend(oy, ox, mk, C(250, 90, 180), 0.8)
    # Montants métalliques.
    for x in (0, w // 2 - 2, w - 4):
        cv.blend(gy, x, np.ones((gh, 4), np.float32), C(96, 92, 106))
        cv.blend(gy, x, np.ones((gh, 1), np.float32), C(190, 180, 196))
    cv.blend(gy, 0, np.ones((2, w), np.float32), C(30, 26, 38))
    # Soubassement.
    cv.blend(h - 16, 0, np.ones((16, w), np.float32), C(92, 84, 98))
    cv.blend(h - 16, 0, np.ones((2, w), np.float32), C(170, 160, 176))
    cv.blend(h - 16, 0, np.ones((1, w), np.float32), OUTLINE, 0.8)
    for _ in range(int(rng.integers(1, 3))):
        moss_blob(cv, rng.uniform(0, w), h - 6, rng.uniform(3, 6), rng)
    _foot_ao(cv, 0.5)
    BT.fine_grain(cv, rng, 2.5)
    return cv.a


def face_int(rng, v: int) -> np.ndarray:
    """Mur intérieur de boutique : peinture claire (teintée en jeu), cimaise, plinthe, écailles."""
    w, h = FW, FH
    t = noise(256, 2.0, rng)[:h, :w]
    base = C(236, 230, 224)
    img = ramp(t, [(0, base * 0.9), (1, base)])
    cv = Canvas(h, w, img, wrap=False)
    BT.strokes(cv, 120, rng, lambda y, x: np.clip(img[y, x] * rng.uniform(0.94, 1.05), 0, 255),
               length=(10, 24), width=(4, 8), opacity=0.25)
    cv.blend(0, 0, np.ones((6, w), np.float32), C(250, 246, 240))
    cv.blend(6, 0, np.ones((3, w), np.float32), NIGHT, 0.25)
    if v == 1:
        # Peinture écaillée.
        for _ in range(5):
            pts = [(rng.uniform(0, 14), rng.uniform(0, 10)) for _ in range(5)]
            pm, px0, py0 = poly_mask(sorted(pts, key=lambda p: math.atan2(p[1] - 5, p[0] - 7)), 1.0)
            cv.blend(int(rng.uniform(16, 70)) + py0, int(rng.uniform(4, w - 20)) + px0, pm, C(170, 160, 150))
    if v == 2:
        # Étagère murale vide (rail + consoles).
        for yy in (30, 56):
            cv.blend(yy + 3, 6, np.ones((4, w - 12), np.float32), NIGHT, 0.3)
            cv.blend(yy, 6, np.ones((4, w - 12), np.float32), C(140, 120, 104))
            cv.blend(yy, 6, np.ones((1, w - 12), np.float32), C(220, 200, 180))
    if v == 3:
        # Affiche de soldes.
        cv.blend(24 + 3, 70 + 3, np.ones((34, 40), np.float32), NIGHT, 0.3)
        cv.blend(24, 70, np.ones((34, 40), np.float32), C(230, 70, 90))
        cv.blend(30, 76, np.ones((12, 28), np.float32), C(255, 240, 220))
        cv.blend(46, 76, np.ones((6, 18), np.float32), C(255, 220, 90))
        cv.blend(24, 70, _frame(34, 40, 1.2), OUTLINE, 0.7)
    cv.blend(h - 12, 0, np.ones((12, w), np.float32), C(120, 104, 100))
    cv.blend(h - 12, 0, np.ones((2, w), np.float32), C(200, 186, 176))
    _foot_ao(cv, 0.5)
    BT.fine_grain(cv, rng, 2.5)
    return cv.a


def face_tile(rng, v: int) -> np.ndarray:
    """Faïence blanche (pharmacie, réserves, locaux) : carreaux 16 px, joints, carreaux tombés."""
    w, h = FW, FH
    cv = Canvas(h, w, C(220, 226, 226), wrap=False)
    for y in range(0, h, 16):
        for x in range(0, w, 16):
            cv.blend(y, x, np.ones((15, 15), np.float32), C(226, 232, 232) * rng.uniform(0.93, 1.03))
            cv.blend(y, x, np.ones((2, 15), np.float32), C(250, 255, 255), 0.6)
    for y in range(0, h, 16):
        cv.blend(y + 15, 0, np.ones((1, w), np.float32), C(150, 156, 160))
    for x in range(0, w, 16):
        cv.blend(0, x + 15, np.ones((h, 1), np.float32), C(150, 156, 160))
    for _ in range(int(rng.integers(1, 5)) + v):
        x, y = int(rng.integers(0, 8)) * 16, int(rng.integers(1, 5)) * 16
        cv.blend(y, x, np.ones((15, 15), np.float32), C(120, 112, 110))
        cv.blend(y, x, np.ones((3, 15), np.float32), NIGHT, 0.4)
    for _ in range(2):
        mk, ox, oy = seg_mask(rng.uniform(0, w), 10, rng.uniform(0, w), rng.uniform(50, 90), rng.uniform(4, 9), 1)
        cv.blend(oy, ox, mk, C(150, 140, 110), 0.3)
    cv.blend(h - 10, 0, np.ones((10, w), np.float32), C(90, 96, 104))
    _foot_ao(cv, 0.5)
    return cv.a


def face_concrete(rng, v: int) -> np.ndarray:
    """Mur de parking : béton banché, bande jaune et noire, marquages peints."""
    w, h = FW, FH
    t = noise(256, 2.2, rng)[:h, :w]
    img = ramp(t, [(0, C(112, 110, 118)), (1, C(150, 146, 148))])
    cv = Canvas(h, w, img, wrap=False)
    for y in (34, 70):
        cv.blend(y, 0, np.ones((1, w), np.float32), C(80, 78, 88), 0.8)
    for x in (10, 54, 98):
        for y in (16, 52, 88):
            m, R = ellipse_mask(1.8, 1.8)
            cv.blend(y - R, x - R, m, C(70, 70, 80))
    cv.blend(h - 30, 0, np.ones((16, w), np.float32), C(230, 186, 50))
    for x in range(-16, w, 24):
        pm, px0, py0 = poly_mask([(x, 16), (x + 10, 16), (x + 22, 0), (x + 12, 0)], 0.6)
        cv.blend(h - 30 + py0, px0, pm, C(40, 36, 44))
    cv.blend(h - 30, 0, np.ones((1, w), np.float32), OUTLINE, 0.5)
    if v == 1:
        # « P » peint.
        cv.blend(20, 50, np.ones((30, 6), np.float32), C(240, 240, 240))
        cv.blend(20, 50, np.ones((5, 20), np.float32), C(240, 240, 240))
        cv.blend(33, 50, np.ones((5, 20), np.float32), C(240, 240, 240))
        cv.blend(20, 66, np.ones((18, 5), np.float32), C(240, 240, 240))
    if v == 2:
        # Flèche de sortie verte.
        pm, px0, py0 = poly_mask([(30, 34), (70, 34), (70, 26), (92, 42), (70, 58), (70, 50), (30, 50)], 0.8)
        cv.blend(py0, px0, pm, C(60, 190, 110))
    if v == 3:
        for _ in range(3):
            mk, ox, oy = seg_mask(rng.uniform(0, w), 4, rng.uniform(0, w), rng.uniform(40, 70), rng.uniform(5, 10), 1)
            cv.blend(oy, ox, mk, C(110, 90, 70), 0.35)
    cv.blend(h - 14, 0, np.ones((14, w), np.float32), C(90, 88, 96))
    _foot_ao(cv, 0.55)
    BT.fine_grain(cv, rng, 4.0)
    return cv.a


def face_office(rng, v: int) -> np.ndarray:
    """Bureaux de la direction : lambris sombre en bas, tissu mural beige, moulures."""
    w, h = FW, FH
    t = noise(256, 2.0, rng)[:h, :w]
    img = ramp(t, [(0, C(176, 160, 136)), (1, C(200, 184, 158))])
    cv = Canvas(h, w, img, wrap=False)
    for x in range(0, w, 8):
        cv.blend(0, x, np.ones((50, 1), np.float32), C(160, 144, 120), 0.5)
    cv.blend(50, 0, np.ones((h - 50, w), np.float32), C(104, 66, 46))
    for px in (6, 70):
        cv.blend(58, px, np.ones((h - 80, 52), np.float32), C(88, 54, 38))
        cv.blend(58 + h - 82, px, np.ones((2, 52), np.float32), C(150, 104, 70))
    cv.blend(48, 0, np.ones((5, w), np.float32), C(150, 104, 70))
    cv.blend(48, 0, np.ones((1, w), np.float32), C(220, 170, 120))
    if v == 1:
        cv.blend(12 + 3, 40 + 3, np.ones((26, 44), np.float32), NIGHT, 0.35)
        cv.blend(12, 40, np.ones((26, 44), np.float32), C(196, 160, 70))
        cv.blend(15, 43, np.ones((20, 38), np.float32), C(120, 90, 130))
        cv.blend(15, 43, np.ones((7, 38), np.float32), C(250, 150, 110), 0.7)
        cv.blend(12, 40, _frame(26, 44, 1.5), OUTLINE)
    cv.blend(0, 0, np.ones((5, w), np.float32), C(120, 84, 60))
    _foot_ao(cv, 0.55)
    BT.fine_grain(cv, rng, 2.5)
    return cv.a


def face_parapet(rng, v: int) -> np.ndarray:
    """Acrotère du toit : béton taché de rouille, couvertine métallique, mousse."""
    w, h = FW, FH
    t = noise(256, 2.2, rng)[:h, :w]
    img = ramp(t, [(0, C(150, 136, 128)), (1, C(186, 170, 156))])
    cv = Canvas(h, w, img, wrap=False)
    cv.blend(0, 0, np.ones((8, w), np.float32), C(150, 156, 170))
    cv.blend(0, 0, np.ones((2, w), np.float32), C(230, 230, 240))
    cv.blend(8, 0, np.ones((3, w), np.float32), NIGHT, 0.35)
    for _ in range(int(rng.integers(1, 4))):
        x = rng.uniform(0, w)
        mk, ox, oy = seg_mask(x, 10, x, rng.uniform(40, 90), rng.uniform(4, 8), 1)
        cv.blend(oy, ox, mk, C(150, 90, 60), 0.35)
    for _ in range(int(rng.integers(2, 5))):
        moss_blob(cv, rng.uniform(0, w), h - 8, rng.uniform(4, 9), rng)
    if v == 2:
        BT.crack(cv, rng.uniform(20, 100), 30, 40, rng, C(110, 96, 90), 1.4)
    _foot_ao(cv, 0.5)
    BT.fine_grain(cv, rng, 3.0)
    return cv.a


def face_glass(rng, v: int) -> np.ndarray:
    """Mur-rideau vitré des bureaux (vu du toit) : reflets du couchant, montants sombres."""
    w, h = FW, FH
    yy = np.linspace(0, 1, h)[:, None]
    xx = np.linspace(0, 1, w)[None, :]
    sky = (C(250, 170, 110)[None, None] * (1 - yy[..., None]) + C(140, 80, 150)[None, None] * yy[..., None]) * np.ones((1, w, 1))
    cv = Canvas(h, w, sky * 0.75 + C(20, 24, 50) * 0.25, wrap=False)
    for (x0, wdt) in ((20, 8.0), (40, 3.0), (96, 6.0)):
        mk, ox, oy = seg_mask(x0, h - 6, x0 + 30, 6, wdt)
        cv.blend(oy, ox, mk, C(255, 240, 220), 0.3)
    for x in (0, 62, 124):
        cv.blend(0, x, np.ones((h, 4), np.float32), C(52, 52, 66))
    for y in (0, 50):
        cv.blend(y, 0, np.ones((4, w), np.float32), C(52, 52, 66))
    if v == 1:
        cx, cy = 90, 30
        for k in range(8):
            a = rng.uniform(0, 2 * math.pi)
            mk, ox, oy = seg_mask(cx, cy, cx + math.cos(a) * 26, cy + math.sin(a) * 18, 1.0)
            cv.blend(oy, ox, mk, C(240, 240, 255), 0.6)
    cv.blend(h - 12, 0, np.ones((12, w), np.float32), C(70, 66, 80))
    _foot_ao(cv, 0.5)
    return cv.a


def cap(kind: str, rng) -> np.ndarray:
    n = 128
    if kind == "plaster":
        t = noise(n, 2.2, rng)
        img = ramp(t, [(0, C(112, 96, 100)), (1, C(140, 120, 120))])
    elif kind == "concrete":
        t = noise(n, 2.2, rng)
        img = ramp(t, [(0, C(70, 70, 82)), (1, C(96, 94, 104))])
    elif kind == "roof":
        t = noise(n, 2.0, rng)
        img = ramp(t, [(0, C(100, 92, 98)), (1, C(132, 122, 120))])
    elif kind == "dark":
        t = noise(n, 2.0, rng)
        img = ramp(t, [(0, C(56, 50, 66)), (1, C(78, 70, 86))])
    else:
        raise ValueError(kind)
    cv = Canvas(n, n, img)
    BT.strokes(cv, 220, rng, lambda y, x: np.clip(img[y, x] * rng.uniform(0.9, 1.1), 0, 255), opacity=0.3)
    if kind in ("plaster", "roof"):
        for _ in range(4):
            moss_blob(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(3, 7), rng, 0.7)
    BT.fine_grain(cv, rng, 4.0)
    return cv.a


FACES = [("plaster", face_plaster), ("vitrine", face_vitrine), ("int", face_int), ("tile", face_tile),
         ("concrete", face_concrete), ("office", face_office), ("parapet", face_parapet), ("glass", face_glass)]


def make_walls(out_png: str, out_meta: str) -> None:
    W = 1024
    atlas = np.zeros((W, W, 4), np.float32)
    regions: dict[str, list[list[int]]] = {}
    rng = np.random.default_rng(303)

    def put(name: str, arr: np.ndarray, x: int, y: int) -> None:
        h, w = arr.shape[:2]
        atlas[y:y + h, x:x + w] = arr
        regions.setdefault(name, []).append([x, y, w, h])

    for i, (name, fn) in enumerate(FACES):
        row, col = i // 2, i % 2
        for v in range(4):
            put("face_" + name, fn(rng, v), col * 512 + v * FW, row * FH)
    uy = 4 * FH
    for i, k in enumerate(["plaster", "concrete", "roof", "dark"]):
        put("cap_" + k, cap(k, rng), i * 128, uy)
    ux = 4 * 128 + 8
    atlas[uy:uy + 8, ux:ux + 8] = [255, 255, 255, 255]
    regions["white"] = [[ux + 2, uy + 2, 4, 4]]
    g = np.linspace(1.0, 0.0, 64)
    atlas[uy + 12:uy + 76, ux:ux + 8, :3] = 255
    atlas[uy + 12:uy + 76, ux:ux + 8, 3] = (g[:, None] ** 1.3) * 255
    regions["grad_v"] = [[ux + 2, uy + 13, 4, 62]]
    atlas[uy:uy + 8, ux + 16:ux + 80, :3] = 255
    atlas[uy:uy + 8, ux + 16:ux + 80, 3] = (g[None, :] ** 1.3) * 255
    regions["grad_h"] = [[ux + 17, uy + 2, 62, 4]]
    atlas[uy + 12:uy + 76, ux + 12:ux + 20, :3] = 255
    atlas[uy + 12:uy + 76, ux + 12:ux + 20, 3] = (g[::-1, None] ** 1.3) * 255
    regions["grad_v_up"] = [[ux + 14, uy + 13, 4, 62]]
    atlas[uy + 12:uy + 20, ux + 24:ux + 88, :3] = 255
    atlas[uy + 12:uy + 20, ux + 24:ux + 88, 3] = (g[None, ::-1] ** 1.3) * 255
    regions["grad_h_left"] = [[ux + 25, uy + 14, 62, 4]]
    yy, xx = np.mgrid[0:96, 0:96].astype(np.float32)
    d = np.hypot(xx - 47.5, yy - 47.5) / 48.0
    atlas[uy + 24:uy + 120, ux + 24:ux + 120, :3] = 255
    atlas[uy + 24:uy + 120, ux + 24:ux + 120, 3] = np.clip(1 - d, 0, 1) ** 1.6 * 255
    regions["soft"] = [[ux + 24, uy + 24, 96, 96]]
    # Néon : tube blanc à cœur saturé (teinté en jeu), 64 x 12.
    tube = np.zeros((12, 64), np.float32)
    yv = np.abs(np.linspace(-1, 1, 12))[:, None]
    tube[:] = np.clip(1.15 - yv * 1.2, 0, 1)
    atlas[uy + 124:uy + 136, ux:ux + 64, :3] = 255
    atlas[uy + 124:uy + 136, ux:ux + 64, 3] = tube * 255
    regions["neon"] = [[ux + 2, uy + 124, 60, 12]]
    img = Image.fromarray(np.clip(atlas + 0.5, 0, 255).astype(np.uint8), "RGBA")
    img.save(out_png, optimize=True)
    with open(out_meta, "w") as f:
        f.write("## Généré par art/blender/mall/build_mall_tiles.py : NE PAS ÉDITER.\n")
        f.write("## Régions (px) de assets/textures/mall/walls.png ; 2 px par unité monde.\n")
        f.write("const REGIONS := %s\n" % json.dumps(regions))


# ============================================================================ décalques

def make_decals(out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    rng = np.random.default_rng(77)

    def save(name: str, cv: Canvas) -> None:
        cv.image().save(os.path.join(out_dir, name + ".png"))

    for k in range(3):
        cv = Canvas(72, 72, C(0, 0, 0), alpha=0, wrap=False)
        for _ in range(4):
            moss_blob(cv, rng.uniform(22, 50), rng.uniform(22, 50), rng.uniform(8, 14), rng)
        save("moss_%d" % k, cv)
    for k in range(3):
        cv = Canvas(56, 64, C(0, 0, 0), alpha=0, wrap=False)
        for _ in range(int(rng.integers(2, 4))):
            weed(cv, rng.uniform(18, 46), rng.uniform(34, 50), rng.uniform(12, 20), rng)
        save("weeds_%d" % k, cv)
    for k in range(2):
        cv = Canvas(90, 90, C(0, 0, 0), alpha=0, wrap=False)
        BT.crack(cv, 45, 45, 70, rng, C(96, 76, 70), 1.8)
        save("crack_%d" % k, cv)
    # Éclats de verre.
    cv = Canvas(80, 80, C(0, 0, 0), alpha=0, wrap=False)
    for _ in range(14):
        x, y = rng.uniform(10, 70), rng.uniform(10, 70)
        pts = [(x + rng.uniform(-6, 6), y + rng.uniform(-5, 5)) for _ in range(3)]
        pm, px0, py0 = poly_mask(pts, 0.7)
        cv.blend(py0 + 1, px0 + 2, pm, NIGHT, 0.3)
        cv.blend(py0, px0, pm, C(200, 230, 240), 0.8)
        cv.blend(py0, px0, np.clip(pm * 3 * (1 - pm), 0, 1), C(255, 255, 255), 0.7)
    save("glass", cv)
    # Feuilles mortes.
    cv = Canvas(70, 70, C(0, 0, 0), alpha=0, wrap=False)
    for _ in range(12):
        x, y = rng.uniform(10, 60), rng.uniform(10, 60)
        m, R = ellipse_mask(rng.uniform(3, 5), rng.uniform(1.6, 2.4), rng.uniform(0, 3))
        cv.blend(int(y - R + 1), int(x - R + 2), m, NIGHT, 0.3)
        cv.blend(int(y - R), int(x - R), m, [C(200, 120, 50), C(170, 90, 50), C(150, 140, 60)][int(rng.integers(0, 3))])
    save("leaves", cv)
    # Papiers / prospectus.
    cv = Canvas(70, 60, C(0, 0, 0), alpha=0, wrap=False)
    for _ in range(4):
        x, y = rng.uniform(14, 56), rng.uniform(14, 46)
        a = rng.uniform(0, 3)
        pts = [(x + math.cos(a + k * 1.57) * 9, y + math.sin(a + k * 1.57) * 7) for k in range(4)]
        pm, px0, py0 = poly_mask(pts, 0.7)
        cv.blend(py0 + 2, px0 + 2, pm, NIGHT, 0.3)
        cv.blend(py0, px0, pm, [C(240, 236, 220), C(250, 160, 200), C(200, 220, 250)][int(rng.integers(0, 3))])
    save("papers", cv)
    # Gravats de carrelage.
    cv = Canvas(80, 64, C(0, 0, 0), alpha=0, wrap=False)
    for _ in range(14):
        BT.pebble(cv, rng.uniform(10, 70), rng.uniform(10, 54), rng.uniform(2, 5), rng, C(220, 200, 176))
    save("rubble", cv)
    # Tache d'huile (parking).
    cv = Canvas(110, 80, C(0, 0, 0), alpha=0, wrap=False)
    m, R = ellipse_mask(42, 26, 0.2, soft=10)
    cv.blend(40 - R, 55 - R, m, C(30, 30, 44), 0.55)
    m, R = ellipse_mask(16, 10, 0.4, soft=4)
    cv.blend(36 - R, 46 - R, m, C(80, 60, 110), 0.25)
    save("oil", cv)
    # Marquages de parking (bande blanche 4 x 120 u = 8 x 240 px) et flèche.
    cv = Canvas(240, 12, C(240, 236, 220), alpha=0, wrap=False)
    cv.blend(0, 2, np.ones((240, 8), np.float32), C(236, 230, 210), 0.85)
    for _ in range(30):
        m, R = ellipse_mask(rng.uniform(1, 3), rng.uniform(1, 3))
        cv.a[max(0, int(rng.uniform(0, 236)) - R):, :, 3] *= 1.0
    save("line", cv)
    cv = Canvas(90, 60, C(0, 0, 0), alpha=0, wrap=False)
    pm, px0, py0 = poly_mask([(6, 22), (54, 22), (54, 8), (84, 30), (54, 52), (54, 38), (6, 38)], 0.8)
    cv.blend(py0, px0, pm, C(236, 230, 210), 0.85)
    save("arrow", cv)
    # Hélipad : cercle + « H » (256 x 256 px = 128 u).
    S = 256
    cv = Canvas(S, S, C(0, 0, 0), alpha=0, wrap=False)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    d = np.hypot(xx - S / 2, yy - S / 2)
    ring = np.clip(1 - np.abs(d - 110) / 7, 0, 1)
    cv.blend(0, 0, ring, C(240, 200, 70), 0.9)
    disk = np.clip((104 - d) / 2, 0, 1)
    cv.blend(0, 0, disk, C(60, 64, 80), 0.55)
    for r in ((70, 60, 20, 136), (166, 60, 20, 136), (90, 118, 76, 20)):
        cv.blend(r[1], r[0], np.ones((r[3], r[2]), np.float32), C(244, 240, 230), 0.92)
    save("helipad", cv)
    # Tache d'eau sombre (humidité) au sol.
    cv = Canvas(120, 90, C(0, 0, 0), alpha=0, wrap=False)
    m, R = ellipse_mask(52, 34, 0.1, soft=18)
    cv.blend(45 - R, 60 - R, m, C(60, 70, 90), 0.4)
    save("damp", cv)
    print("DECALS", out_dir)


def main() -> None:
    gdir = os.path.join(TEX_DIR, "ground")
    os.makedirs(gdir, exist_ok=True)
    make_tiles(11).save(os.path.join(gdir, "tiles.png"), optimize=True)
    make_lino(12).save(os.path.join(gdir, "lino.png"), optimize=True)
    make_parquet(13).save(os.path.join(gdir, "parquet.png"), optimize=True)
    make_carpet(14).save(os.path.join(gdir, "carpet.png"), optimize=True)
    make_marble(15).save(os.path.join(gdir, "marble.png"), optimize=True)
    make_concrete(16).save(os.path.join(gdir, "concrete.png"), optimize=True)
    make_roof(17).save(os.path.join(gdir, "roof.png"), optimize=True)
    BT.make_macro(18).save(os.path.join(gdir, "macro.png"), optimize=True)
    make_walls(os.path.join(TEX_DIR, "walls.png"), os.path.join(TEX_DIR, "walls_meta.gd"))
    make_decals(TMP)
    print("OK", TEX_DIR)


if __name__ == "__main__":
    main()
