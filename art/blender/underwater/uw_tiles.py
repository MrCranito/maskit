"""Textures peintes de la station sous-marine « Abysse Nérée » (sols tuilables, atlas des murs,
décalques plats, eau, bulles).

Usage (depuis la racine du projet) :
    python3 art/blender/underwater/uw_tiles.py

Pas de Blender ici : peinture procédurale numpy (mêmes outils que art/blender/build_tiles.py :
bruits périodiques, coups de pinceau, tampons à repli torique) => sols tuilables.
Densité : 2 px par unité monde (1 case = 64 unités = 128 px), comme le héros 3D.
Lumière : lampes chaudes en haut à gauche, ombres bleu nuit vers le bas-droite ; ambiance
bleu-vert profond, contraste chaud / froid.

Sorties :
  assets/textures/underwater/deck.png, lab.png, grate.png, seabed.png (512, répétition GPU)
  assets/textures/underwater/caustics.png (256, eau peu profonde animée par shader)
  assets/textures/underwater/walls.png + walls_meta.gd (atlas 1024 : faces, dessus, utilitaires)
  assets/textures/underwater/bubble.png (particule de bulle)
  $RDM_TMP/uw_tiles/decals/*.png (décalques : empaquetés dans l'atlas par uw_props.py)
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from build_tiles import (C, Canvas, NIGHT, OUTLINE, ellipse_mask, fine_grain, noise,  # noqa: E402
                         pebble, poly_mask, ramp, seg_mask, strokes, _frame)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
TEX_DIR = os.path.join(ROOT, "assets", "textures", "underwater")
TMP = os.path.join(os.environ.get("RDM_TMP", "/tmp/rdm_uw"), "uw_tiles")

DEEP = C(14, 40, 62)
STEEL = C(104, 122, 132)
STEEL_D = C(58, 70, 84)
RIVET = C(150, 166, 172)
RUST = C(150, 84, 50)
WARM = C(255, 196, 120)


def _rivet(cv: Canvas, x: float, y: float, r: float = 1.8) -> None:
    m, R = ellipse_mask(r + 0.9, r + 0.9)
    cv.blend(int(y - R + 1), int(x - R + 1), m, NIGHT, 0.5)
    m, R = ellipse_mask(r, r)
    cv.blend(int(y - R), int(x - R), m, C(70, 82, 94))
    m, R = ellipse_mask(r * 0.5, r * 0.5)
    cv.blend(int(y - R - 0.6), int(x - R - 0.6), m, RIVET + 40, 0.9)


def _rust_streak(cv: Canvas, rng, x: float, y: float, length: float, w: float = 3.0, col=RUST) -> None:
    for k in range(3):
        xx = x + rng.uniform(-w, w)
        mk, ox, oy = seg_mask(xx, y, xx + rng.uniform(-2, 2), y + length * rng.uniform(0.5, 1.0), w * rng.uniform(0.4, 1.0), 0.4)
        cv.blend(oy, ox, mk, col * rng.uniform(0.8, 1.1), 0.35)


# ============================================================================ sols

def make_deck(seed: int, n: int = 512) -> Image.Image:
    """Tôles d'acier rivetées (une tôle = une case = 128 px), quelques tôles larmées, usure."""
    rng = np.random.default_rng(seed)
    big = noise(n, 2.4, rng)
    mid = noise(n, 1.6, rng)
    base = ramp(0.6 * big + 0.4 * mid, [(0.0, C(70, 84, 94)), (0.45, C(92, 108, 116)), (1.0, C(118, 132, 136))])
    cv = Canvas(n, n, base)
    strokes(cv, 1500, rng, lambda y, x: np.clip(base[y, x] * rng.uniform(0.88, 1.1), 0, 255),
            length=(10, 28), width=(3, 6), opacity=0.25, angle_fn=lambda y, x: rng.uniform(-0.15, 0.15))
    P = 128
    for py in range(0, n, P):
        for px in range(0, n, P):
            tone = rng.uniform(0.9, 1.08)
            cv.a[py:py + P, px:px + P, :3] *= tone
            kind = rng.random()
            if kind < 0.3:
                # Tôle larmée (relief en grains de riz, motif alterné).
                for yy in range(py + 10, py + P - 6, 12):
                    for xx in range(px + 10 + (6 if (yy // 12) % 2 else 0), px + P - 6, 12):
                        rot = 0.7 if ((xx // 12 + yy // 12) % 2) else -0.7
                        m, R = ellipse_mask(3.6, 1.2, rot)
                        cv.blend(yy - R + 1, xx - R + 1, m, NIGHT, 0.35)
                        cv.blend(yy - R, xx - R, m, C(150, 164, 168), 0.55)
            elif kind < 0.42:
                # Trappe de visite carrée boulonnée.
                cv.blend(py + 30, px + 30, _frame(68, 68, 2.5), C(40, 48, 60), 0.85)
                cv.blend(py + 32, px + 32, _frame(64, 64, 1.2), C(150, 164, 170), 0.55)
                for (ax, ay) in ((36, 36), (92, 36), (36, 92), (92, 92)):
                    _rivet(cv, px + ax, py + ay, 2.4)
            # Joints : arête claire haut-gauche, ombre bas-droite.
            cv.blend(py, px, np.ones((2, P), np.float32), C(36, 42, 56), 0.95)
            cv.blend(py, px, np.ones((P, 2), np.float32), C(36, 42, 56), 0.95)
            cv.blend(py + 2, px + 2, np.ones((2, P - 4), np.float32), C(160, 176, 180), 0.45)
            cv.blend(py + 2, px + 2, np.ones((P - 4, 2), np.float32), C(160, 176, 180), 0.35)
            cv.blend(py + P - 4, px + 2, np.ones((2, P - 4), np.float32), NIGHT, 0.35)
            for t in range(8, P, 24):
                for (ax, ay) in ((t, 6), (t, P - 7), (6, t), (P - 7, t)):
                    _rivet(cv, px + ax, py + ay)
    # Rouille aux joints, taches d'huile, éraflures.
    wet = noise(n, 2.6, rng)
    m = np.clip((wet - 0.78) * 6, 0, 1)
    cv.a[..., :3] = cv.a[..., :3] * (1 - 0.35 * m[..., None]) + RUST * 0.35 * m[..., None]
    for _ in range(18):
        mm, R = ellipse_mask(rng.uniform(6, 18), rng.uniform(4, 10), rng.uniform(0, 3), soft=5)
        cv.blend(int(rng.uniform(0, n)) - R, int(rng.uniform(0, n)) - R, mm, C(30, 34, 44), 0.25)
    for _ in range(90):
        x, y = rng.uniform(0, n), rng.uniform(0, n)
        mk, ox, oy = seg_mask(x, y, x + rng.uniform(-18, 18), y + rng.uniform(-4, 4), 1.0)
        cv.blend(oy, ox, mk, C(176, 190, 194), 0.35)
    fine_grain(cv, rng, 3.5)
    return cv.image().convert("RGB")


def make_lab(seed: int, n: int = 512) -> Image.Image:
    """Carrelage de laboratoire clair (carreaux de 32 px = 16 unités), joints, usure, reflets."""
    rng = np.random.default_rng(seed)
    big = noise(n, 2.6, rng)
    base = ramp(big, [(0, C(170, 192, 192)), (0.6, C(196, 214, 210)), (1, C(214, 228, 222))])
    cv = Canvas(n, n, base)
    S = 32
    for py in range(0, n, S):
        for px in range(0, n, S):
            col = rng.uniform(0.94, 1.04)
            cv.a[py:py + S, px:px + S, :3] *= col
            if rng.random() < 0.06:
                cv.a[py:py + S, px:px + S, :3] = cv.a[py:py + S, px:px + S, :3] * 0.6 + C(60, 150, 150) * 0.4
            cv.blend(py + 2, px + 2, np.ones((3, S - 6), np.float32), C(240, 250, 246), 0.35)
            cv.blend(py + S - 3, px + 2, np.ones((2, S - 4), np.float32), NIGHT, 0.12)
    for g in range(0, n, S):
        cv.blend(g - 1, 0, np.ones((2, n), np.float32), C(96, 112, 118), 0.85)
        cv.blend(0, g - 1, np.ones((n, 2), np.float32), C(96, 112, 118), 0.85)
    strokes(cv, 600, rng, lambda y, x: np.clip(base[y, x] * rng.uniform(0.9, 1.06), 0, 255),
            length=(10, 26), width=(3, 7), opacity=0.16)
    dirt = noise(n, 2.4, rng)
    m = np.clip((dirt - 0.7) * 4, 0, 1)
    cv.a[..., :3] = cv.a[..., :3] * (1 - 0.25 * m[..., None]) + C(90, 110, 100) * 0.25 * m[..., None]
    fine_grain(cv, rng, 2.5)
    return cv.image().convert("RGB")


def make_grate(seed: int, n: int = 512) -> Image.Image:
    """Caillebotis d'acier des tubes : barreaux sur fond sombre (eau / vide en dessous)."""
    rng = np.random.default_rng(seed)
    depth = noise(n, 2.2, rng)
    under = ramp(depth, [(0, C(8, 26, 38)), (0.6, C(16, 46, 60)), (1, C(30, 74, 84))])
    cv = Canvas(n, n, under)
    # Barreaux porteurs (horizontaux, larges) puis entretoises (verticales, fines).
    for y in range(0, n, 16):
        cv.blend(y + 3, 0, np.ones((7, n), np.float32), NIGHT, 0.55)
        cv.blend(y, 0, np.ones((6, n), np.float32), C(96, 112, 120))
        cv.blend(y, 0, np.ones((2, n), np.float32), C(160, 176, 178), 0.8)
        cv.blend(y + 5, 0, np.ones((1, n), np.float32), C(40, 46, 58), 0.8)
    for x in range(0, n, 32):
        cv.blend(0, x + 2, np.ones((n, 3), np.float32), NIGHT, 0.45)
        cv.blend(0, x, np.ones((n, 3), np.float32), C(84, 100, 110))
        cv.blend(0, x, np.ones((n, 1), np.float32), C(150, 166, 170), 0.7)
    # Cadres de panneaux (128 px) avec boulons.
    for p in range(0, n, 128):
        cv.blend(p, 0, np.ones((4, n), np.float32), C(70, 82, 94))
        cv.blend(0, p, np.ones((n, 4), np.float32), C(70, 82, 94))
        for t in range(0, n, 128):
            _rivet(cv, p + 2, t + 2, 2.6)
    # Rouille et algues par plaques.
    m = np.clip((noise(n, 2.5, rng) - 0.7) * 5, 0, 1)
    cv.a[..., :3] = cv.a[..., :3] * (1 - 0.3 * m[..., None]) + RUST * 0.3 * m[..., None]
    m2 = np.clip((noise(n, 2.5, rng) - 0.76) * 5, 0, 1)
    cv.a[..., :3] = cv.a[..., :3] * (1 - 0.3 * m2[..., None]) + C(60, 120, 80) * 0.3 * m2[..., None]
    fine_grain(cv, rng, 3.0)
    return cv.image().convert("RGB")


def make_seabed(seed: int, n: int = 512) -> Image.Image:
    """Fond marin (sous et autour de la station) : sable gris-vert à rides, cailloux, coquillages."""
    rng = np.random.default_rng(seed)
    t = 0.6 * noise(n, 2.4, rng) + 0.4 * noise(n, 1.5, rng)
    base = ramp(t, [(0, C(76, 96, 96)), (0.5, C(104, 122, 116)), (1, C(132, 146, 134))])
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    warp = noise(n, 2.2, rng) * 40
    ripple = np.sin((yy + warp) / n * 2 * math.pi * 24 + np.sin(xx / n * 2 * math.pi * 3) * 2.0)
    base = base * (1.0 + (np.round(ripple * 2) / 2 * 0.06))[..., None]
    cv = Canvas(n, n, base)
    strokes(cv, 1200, rng, lambda y, x: np.clip(base[y, x] * rng.uniform(0.9, 1.1), 0, 255),
            length=(8, 22), width=(3, 6), opacity=0.25, angle_fn=lambda y, x: rng.uniform(-0.3, 0.3))
    for _ in range(60):
        pebble(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(2.5, 7), rng, C(120, 128, 126), shadow_len=0.7)
    for _ in range(16):
        x, y = rng.uniform(0, n), rng.uniform(0, n)
        m, R = ellipse_mask(5, 3.5, rng.uniform(0, 3))
        cv.blend(int(y - R), int(x - R), m, C(230, 196, 176))
        for k in range(3):
            mk, ox, oy = seg_mask(x - 4 + k * 4, y - 2, x - 2 + k * 2, y + 3, 0.8)
            cv.blend(oy, ox, mk, C(160, 110, 100), 0.7)
    fine_grain(cv, rng, 4.0)
    return cv.image().convert("RGB")


def make_caustics(seed: int, n: int = 256) -> Image.Image:
    """Réseau de caustiques (lignes lumineuses) tuilable, en niveaux de gris (alpha = luminance)."""
    rng = np.random.default_rng(seed)
    a = noise(n, 2.0, rng)
    b = noise(n, 2.0, rng)
    v = np.abs(a - 0.5) + np.abs(b - 0.5) * 0.7
    lines = np.clip(1.0 - v * 6.0, 0, 1) ** 2.2
    img = np.zeros((n, n, 4), np.float32)
    img[..., :3] = 255
    img[..., 3] = lines * 255
    return Image.fromarray(img.astype(np.uint8), "RGBA")


# ============================================================================ murs (atlas)
# Face : 128 x 104 px (64 x 52 unités monde). Dessus : 128 x 128 (tuilable).

FW, FH = 128, 104


def _sea_view(rng, w: int, h: int, variant: int, fish: bool = True) -> np.ndarray:
    """Vue sur le large derrière une vitre : dégradé bleu-vert, rais de lumière, algues, poissons."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = yy / max(h - 1, 1)
    img = ramp(t, [(0, C(38, 126, 140)), (0.45, C(20, 76, 104)), (1, C(8, 34, 58))])
    cv = Canvas(h, w, img, wrap=False)
    # Rais de lumière obliques venant de la surface.
    for k in range(3):
        x0 = rng.uniform(-20, w)
        pm, px0, py0 = poly_mask([(x0, 0), (x0 + 16, 0), (x0 + 46, h), (x0 + 22, h)], 6.0)
        cv.blend(py0, px0, pm * np.linspace(1, 0, pm.shape[0])[:, None], C(150, 230, 230), 0.16)
    # Fond rocheux / dunes au loin.
    pts = [(0, h)]
    for x in range(0, w + 16, 16):
        pts.append((x, h - 18 - rng.uniform(0, 14)))
    pts.append((w, h))
    pm, px0, py0 = poly_mask(pts, 1.5)
    cv.blend(py0, px0, pm, C(10, 40, 56), 0.9)
    # Algues (kelp) ondulantes en silhouette.
    for k in range(int(rng.integers(2, 5))):
        x = rng.uniform(4, w - 4)
        hh = rng.uniform(h * 0.4, h * 0.9)
        phase = rng.uniform(0, 6)
        prev = (x, h)
        for i in range(1, 9):
            fy = h - hh * i / 8
            fx = x + math.sin(phase + i * 0.9) * 5
            mk, ox, oy = seg_mask(prev[0], prev[1], fx, fy, 5.0 - i * 0.4, 4.0 - i * 0.4)
            cv.blend(oy, ox, mk, C(18, 70, 60), 0.85)
            if i % 2 == 0:
                m, R = ellipse_mask(5, 2, 0.6 if i % 4 else -0.6)
                cv.blend(int(fy - R), int(fx - R + (4 if i % 4 else -4)), m, C(26, 92, 70), 0.8)
            prev = (fx, fy)
    if fish:
        for k in range(int(rng.integers(1, 4)) + (2 if variant == 2 else 0)):
            fx, fy = rng.uniform(10, w - 10), rng.uniform(12, h * 0.6)
            s = rng.uniform(3, 6)
            m, R = ellipse_mask(s, s * 0.45)
            cv.blend(int(fy - R), int(fx - R), m, C(14, 56, 78), 0.8)
            pm, px0, py0 = poly_mask([(fx + s * 0.8, fy), (fx + s * 1.8, fy - s * 0.6), (fx + s * 1.8, fy + s * 0.6)], 0.8)
            cv.blend(py0, px0, pm, C(14, 56, 78), 0.8)
    # Bulles.
    for k in range(6):
        bx, by = rng.uniform(4, w - 4), rng.uniform(4, h - 4)
        r = rng.uniform(1.0, 2.6)
        m, R = ellipse_mask(r, r)
        cv.blend(int(by - R), int(bx - R), m, C(170, 240, 240), 0.35)
    return cv.a[..., :3]


def _glass(cv: Canvas, x: int, y: int, w: int, h: int, rng) -> None:
    """Reflets du verre : deux traits diagonaux clairs + liseré."""
    for k, (o, ww) in enumerate(((0.15, 7), (0.32, 3))):
        x0 = x + w * o
        pm, px0, py0 = poly_mask([(x0, y), (x0 + ww, y), (x0 + ww + h * 0.5, y + h), (x0 + h * 0.5, y + h)], 1.0)
        cv.blend(py0, px0, pm, C(220, 250, 250), 0.22 if k == 0 else 0.3)
    cv.blend(y, x, np.ones((2, w), np.float32), C(190, 240, 240), 0.5)


def _steel_panels(rng, w: int, h: int, base=STEEL, seams=(30, 66)) -> Canvas:
    t = noise(256, 2.0, rng)[:h, :w]
    img = ramp(t, [(0, base * 0.82), (0.5, base), (1, np.minimum(base * 1.1, 255))])
    cv = Canvas(h, w, img, wrap=False)
    strokes(cv, 120, rng, lambda y, x: np.clip(img[y, x] * rng.uniform(0.9, 1.08), 0, 255),
            length=(12, 28), width=(3, 6), opacity=0.25, angle_fn=lambda y, x: 0.0)
    for sy in seams:
        cv.blend(sy, 0, np.ones((2, w), np.float32), C(34, 40, 54), 0.9)
        cv.blend(sy + 2, 0, np.ones((1, w), np.float32), C(170, 184, 188), 0.4)
        for x in range(6, w, 20):
            _rivet(cv, x, sy - 4, 1.5)
            _rivet(cv, x, sy + 6, 1.5)
    return cv


def _face_finish(cv: Canvas, top=C(80, 94, 104), base=C(44, 52, 64)) -> np.ndarray:
    h, w = cv.h, cv.w
    # Corniche haute (rail d'acier) + soubassement sombre, occlusion au pied.
    cv.blend(0, 0, np.ones((8, w), np.float32), top)
    cv.blend(0, 0, np.ones((2, w), np.float32), np.minimum(top * 1.5, 255))
    cv.blend(8, 0, np.ones((3, w), np.float32), NIGHT * 0.6 + top * 0.2, 0.7)
    cv.blend(h - 12, 0, np.ones((12, w), np.float32), base)
    cv.blend(h - 12, 0, np.ones((2, w), np.float32), np.minimum(base * 1.6, 255))
    for x in range(10, w, 32):
        _rivet(cv, x, h - 6, 1.5)
    g = np.linspace(0, 1, 14)[:, None] ** 1.5 * np.ones((1, w))
    cv.blend(h - 14, 0, g.astype(np.float32), NIGHT * 0.7, 0.55)
    return cv.a


def _face_steel(rng, v: int) -> np.ndarray:
    cv = _steel_panels(rng, FW, FH)
    if v == 1:
        # Conduite horizontale + vanne.
        cv.blend(44, 0, np.ones((12, FW), np.float32), C(70, 80, 92))
        cv.blend(44, 0, np.ones((3, FW), np.float32), C(150, 160, 166))
        cv.blend(53, 0, np.ones((3, FW), np.float32), NIGHT, 0.6)
        for x in (24, 88):
            cv.blend(41, x, np.ones((18, 8), np.float32), C(60, 66, 76))
            cv.blend(41, x, _frame(18, 8, 1), OUTLINE, 0.9)
        # Volant de vanne rouge (anneau + croisillon).
        m, R = ellipse_mask(10, 10)
        cv.blend(50 - R, 58 - R, m, OUTLINE, 0.9)
        m, R = ellipse_mask(8.5, 8.5)
        cv.blend(50 - R, 58 - R, m, C(196, 56, 44))
        m2, R2 = ellipse_mask(5.5, 5.5)
        cv.blend(50 - R2, 58 - R2, m2, C(70, 80, 92))
        cv.blend(49, 50, np.ones((2, 17), np.float32), C(230, 96, 72))
        cv.blend(42, 57, np.ones((17, 2), np.float32), C(230, 96, 72))
        m3, R3 = ellipse_mask(2.2, 2.2)
        cv.blend(50 - R3, 58 - R3, m3, C(250, 200, 120))
    elif v == 2:
        # Panneau de bandes de danger + plaque.
        for i in range(0, FW + 30, 16):
            pm, px0, py0 = poly_mask([(i, 76), (i + 8, 76), (i - 4, 88), (i - 12, 88)], 0.8)
            cv.blend(py0, px0, pm, C(232, 180, 40))
        cv.blend(76, 0, np.ones((12, FW), np.float32) * 0 + 0, C(0, 0, 0), 0.0)
        cv.blend(74, 0, np.ones((2, FW), np.float32), OUTLINE, 0.8)
        cv.blend(88, 0, np.ones((2, FW), np.float32), OUTLINE, 0.8)
        cv.blend(36, 40, np.ones((22, 48), np.float32), C(36, 44, 56))
        cv.blend(36, 40, _frame(22, 48, 1.5), C(170, 180, 186), 0.6)
        for k in range(3):
            cv.blend(41 + k * 5, 46, np.ones((2, 26 - k * 6), np.float32), C(230, 200, 120), 0.8)
    elif v == 3:
        _rust_streak(cv, rng, rng.uniform(20, 100), 32, 50)
        _rust_streak(cv, rng, rng.uniform(20, 100), 68, 24)
    # Lampe murale chaude occasionnelle (lueur ajoutée en jeu).
    return _face_finish(cv)


def _face_window(rng, v: int) -> np.ndarray:
    """Mur d'acier avec hublot rond (variantes 0-1) ou baie rectangulaire (2-3) sur le large."""
    cv = _steel_panels(rng, FW, FH, seams=(84,))
    sea = _sea_view(rng, FW, FH, v)
    if v < 2:
        cx, cy, r = FW / 2, 44, 26
        yy, xx = np.mgrid[0:FH, 0:FW].astype(np.float32)
        d = np.hypot(xx - cx, yy - cy)
        rim = np.clip(r + 7 - d, 0, 1) * np.clip(d - r + 1, 0, 1)
        win = np.clip(r - d + 0.5, 0, 1)
        cv.blend(0, 0, np.clip(r + 9 - d, 0, 1), NIGHT, 0.5)
        cv.blend(0, 0, rim.astype(np.float32), C(176, 140, 70))
        cv.blend(0, 0, win.astype(np.float32), sea)
        _glass(cv, int(cx - r), int(cy - r), int(2 * r), int(2 * r), rng)
        cv.blend(0, 0, (np.clip(r + 7.5 - d, 0, 1) - np.clip(r + 6.5 - d, 0, 1)).astype(np.float32), OUTLINE, 0.9)
        cv.blend(0, 0, (np.clip(r + 0.5 - d, 0, 1) - np.clip(r - 0.8 - d, 0, 1)).astype(np.float32), OUTLINE, 0.9)
        for k in range(8):
            a = k * math.pi / 4
            _rivet(cv, cx + math.cos(a) * (r + 3.5), cy + math.sin(a) * (r + 3.5), 1.6)
    else:
        x0, y0, w, h = 16, 16, FW - 32, 58
        cv.blend(y0 - 5, x0 - 5, np.ones((h + 10, w + 10), np.float32), C(66, 76, 88))
        cv.blend(y0, x0, np.ones((h, w), np.float32), sea[y0:y0 + h, x0:x0 + w])
        cv.blend(y0, x0 + w // 2 - 2, np.ones((h, 4), np.float32), C(66, 76, 88))
        _glass(cv, x0, y0, w, h, rng)
        cv.blend(y0 - 5, x0 - 5, _frame(h + 10, w + 10, 1.5), OUTLINE, 0.9)
        cv.blend(y0, x0, _frame(h, w, 1.2), OUTLINE, 0.8)
    return _face_finish(cv)


def _face_glass(rng, v: int) -> np.ndarray:
    """Paroi d'un tube vitré : membrures d'acier, grand vitrage sur les fonds marins."""
    sea = _sea_view(rng, FW, FH, v)
    cv = Canvas(FH, FW, sea, wrap=False)
    _glass(cv, 0, 10, FW, FH - 22, rng)
    # Membrures (arceaux du tube) aux bords de la case + rails haut/bas.
    for x in (0, FW - 10):
        cv.blend(0, x, np.ones((FH, 10), np.float32), C(84, 98, 110))
        cv.blend(0, x, np.ones((FH, 2), np.float32), C(170, 186, 192), 0.8)
        cv.blend(0, x + 8, np.ones((FH, 2), np.float32), NIGHT, 0.6)
        for y in range(14, FH - 12, 16):
            _rivet(cv, x + 5, y, 1.5)
    cv.blend(0, 0, np.ones((10, FW), np.float32), C(84, 98, 110))
    cv.blend(0, 0, np.ones((2, FW), np.float32), C(176, 190, 196))
    cv.blend(FH - 14, 0, np.ones((14, FW), np.float32), C(56, 66, 80))
    cv.blend(FH - 14, 0, np.ones((2, FW), np.float32), C(150, 166, 172))
    # Condensation / algues collées au bas de la vitre.
    if v in (1, 3):
        for k in range(10):
            m, R = ellipse_mask(rng.uniform(3, 7), rng.uniform(2, 4))
            cv.blend(int(FH - 18 - rng.uniform(0, 8)) - R, int(rng.uniform(12, FW - 12)) - R, m, C(40, 110, 80), 0.6)
    g = np.linspace(0, 1, 10)[:, None] ** 1.5 * np.ones((1, FW))
    cv.blend(FH - 10, 0, g.astype(np.float32), NIGHT, 0.5)
    return cv.a


def _face_lab(rng, v: int) -> np.ndarray:
    """Cloison de laboratoire : panneaux stratifiés clairs, bande turquoise, écran ou affiche."""
    base = C(196, 210, 208)
    t = noise(256, 2.2, rng)[:FH, :FW]
    img = ramp(t, [(0, base * 0.9), (1, np.minimum(base * 1.04, 255))])
    cv = Canvas(FH, FW, img, wrap=False)
    for x in (0, 64):
        cv.blend(10, x, np.ones((FH - 22, 2), np.float32), C(120, 136, 140), 0.8)
        cv.blend(10, x + 2, np.ones((FH - 22, 1), np.float32), C(240, 250, 248), 0.6)
    cv.blend(62, 0, np.ones((7, FW), np.float32), C(40, 150, 150))
    cv.blend(62, 0, np.ones((2, FW), np.float32), C(120, 220, 210))
    if v == 1:
        # Écran de contrôle (lueur cyan ajoutée en jeu).
        cv.blend(24, 34, np.ones((28, 46), np.float32), C(30, 40, 52))
        cv.blend(27, 37, np.ones((22, 40), np.float32), C(40, 170, 170))
        for k in range(4):
            cv.blend(30 + k * 5, 40, np.ones((2, int(rng.uniform(10, 32))), np.float32), C(190, 255, 240), 0.8)
        cv.blend(24, 34, _frame(28, 46, 1.5), OUTLINE, 0.9)
    elif v == 2:
        # Affiche « Expérience Nérée » (masque stylisé).
        cv.blend(20, 78, np.ones((36, 28), np.float32), C(236, 226, 196))
        m, R = ellipse_mask(8, 10)
        cv.blend(38 - R, 92 - R, m, C(40, 120, 140))
        cv.blend(34, 87, np.ones((2, 4), np.float32), C(250, 250, 240))
        cv.blend(34, 94, np.ones((2, 4), np.float32), C(250, 250, 240))
        cv.blend(20, 78, _frame(36, 28, 1.2), OUTLINE, 0.8)
    elif v == 3:
        _rust_streak(cv, rng, rng.uniform(10, 120), 14, 40, 2.0, C(120, 140, 100))
    return _face_finish(cv, top=C(150, 166, 168), base=C(70, 84, 92))


def _face_rust(rng, v: int) -> np.ndarray:
    """Acier rongé de la Fosse : rouille, bernacles, coraux et algues qui envahissent le mur."""
    cv = _steel_panels(rng, FW, FH, base=C(92, 96, 98), seams=(40,))
    m = np.clip((noise(256, 2.3, rng)[:FH, :FW] - 0.45) * 3, 0, 1)
    cv.a[..., :3] = cv.a[..., :3] * (1 - 0.6 * m[..., None]) + RUST * 0.6 * m[..., None]
    for k in range(5):
        _rust_streak(cv, rng, rng.uniform(4, FW - 4), rng.uniform(10, 50), rng.uniform(20, 50), 3.0)
    # Bernacles (cônes clairs) en grappes.
    for k in range(int(rng.integers(10, 22))):
        x = rng.uniform(4, FW - 4)
        y = FH - 14 - abs(rng.normal(0, 18))
        r = rng.uniform(2.0, 4.0)
        m1, R = ellipse_mask(r + 1, r + 0.8)
        cv.blend(int(y - R + 1), int(x - R + 1), m1, NIGHT, 0.5)
        m2, R2 = ellipse_mask(r, r * 0.85)
        cv.blend(int(y - R2), int(x - R2), m2, C(214, 206, 186))
        m3, R3 = ellipse_mask(r * 0.4, r * 0.35)
        cv.blend(int(y - R3), int(x - R3), m3, C(70, 60, 60))
    # Coraux (touffes roses / orangées) au pied, algues vertes.
    for k in range(int(rng.integers(1, 3)) + (2 if v == 2 else 0)):
        x = rng.uniform(10, FW - 10)
        col = [C(236, 110, 100), C(250, 150, 80), C(200, 90, 160)][int(rng.integers(0, 3))]
        for b in range(5):
            a = -math.pi / 2 + rng.uniform(-0.9, 0.9)
            ln = rng.uniform(8, 18)
            mk, ox, oy = seg_mask(x, FH - 12, x + math.cos(a) * ln, FH - 12 + math.sin(a) * ln, 4.5, 2.0)
            cv.blend(oy, ox, mk, OUTLINE, 0.8)
            mk, ox, oy = seg_mask(x, FH - 12, x + math.cos(a) * ln, FH - 12 + math.sin(a) * ln, 3.0, 1.0)
            cv.blend(oy, ox, mk, col)
    for k in range(6):
        x = rng.uniform(0, FW)
        mk, ox, oy = seg_mask(x, 10, x + rng.uniform(-6, 6), 10 + rng.uniform(10, 30), 3.0, 0.6)
        cv.blend(oy, ox, mk, C(60, 120, 70), 0.6)
    return _face_finish(cv, top=C(84, 76, 72), base=C(40, 44, 50))


def _cap(kind: str, rng) -> np.ndarray:
    n = 128
    if kind == "steel":
        t = noise(n, 2.0, rng)
        img = ramp(t, [(0, C(44, 54, 66)), (0.6, C(58, 70, 82)), (1, C(72, 84, 94))])
        cv = Canvas(n, n, img)
        strokes(cv, 300, rng, lambda y, x: np.clip(img[y, x] * rng.uniform(0.9, 1.1), 0, 255), opacity=0.25)
        for p in (0, 64):
            cv.blend(p, 0, np.ones((2, n), np.float32), C(26, 30, 42))
            cv.blend(0, p, np.ones((n, 2), np.float32), C(26, 30, 42))
            for t2 in range(8, n, 16):
                _rivet(cv, t2, p + 6, 1.4)
        # Conduites et câbles qui courent sur le dessus.
        cv.blend(92, 0, np.ones((8, n), np.float32), C(64, 74, 84))
        cv.blend(92, 0, np.ones((2, n), np.float32), C(120, 132, 140))
    elif kind == "glass":
        sea = ramp(noise(n, 2.2, rng), [(0, C(16, 60, 80)), (1, C(40, 120, 130))])
        cv = Canvas(n, n, sea)
        for p in range(0, n, 64):
            cv.blend(0, p, np.ones((n, 8), np.float32), C(80, 96, 108))
            cv.blend(0, p, np.ones((n, 2), np.float32), C(170, 186, 192), 0.8)
            cv.blend(p, 0, np.ones((6, n), np.float32), C(70, 84, 96))
        for k in range(6):
            x0 = rng.uniform(0, n)
            mk, ox, oy = seg_mask(x0, 0, x0 + 40, n, 6, 6)
            cv.blend(oy, ox, mk, C(200, 245, 245), 0.12)
    elif kind == "rust":
        t = noise(n, 2.0, rng)
        img = ramp(t, [(0, C(56, 56, 62)), (0.6, C(78, 72, 72)), (1, C(104, 84, 70))])
        cv = Canvas(n, n, img)
        for _ in range(7):
            r = rng.uniform(2, 3.5)
            m, R = ellipse_mask(r, r)
            x, y = rng.uniform(0, n), rng.uniform(0, n)
            cv.blend(int(y - R), int(x - R), m, C(196, 188, 170))
            cv.blend(int(y - R / 2), int(x - R / 2), ellipse_mask(r * 0.4, r * 0.4)[0], C(60, 50, 50))
        for _ in range(5):
            m, R = ellipse_mask(rng.uniform(5, 12), rng.uniform(3, 7), rng.uniform(0, 3), soft=3)
            cv.blend(int(rng.uniform(0, n)) - R, int(rng.uniform(0, n)) - R, m, C(50, 110, 70), 0.35)
    elif kind == "lab":
        t = noise(n, 2.2, rng)
        img = ramp(t, [(0, C(106, 120, 124)), (1, C(132, 146, 148))])
        cv = Canvas(n, n, img)
        for p in (0, 64):
            cv.blend(p, 0, np.ones((2, n), np.float32), C(70, 84, 90))
            cv.blend(0, p, np.ones((n, 2), np.float32), C(70, 84, 90))
    else:
        raise ValueError(kind)
    fine_grain(cv, rng, 3.0)
    return cv.a


def make_walls(out_png: str, out_meta: str) -> None:
    """Atlas des murs (1024 x 512) : faces 128 x 104, dessus 128 x 128, utilitaires."""
    W = 1024
    atlas = np.zeros((512, W, 4), np.float32)
    regions: dict[str, list[list[int]]] = {}
    rng = np.random.default_rng(404)

    def put(name: str, arr: np.ndarray, x: int, y: int) -> None:
        h, w = arr.shape[:2]
        atlas[y:y + h, x:x + w] = arr
        regions.setdefault(name, []).append([x, y, w, h])

    rows = [[("steel", _face_steel), ("window", _face_window)], [("glass", _face_glass), ("lab", _face_lab)],
            [("rust", _face_rust), ("lab_window", None)]]
    y = 0
    for row in rows:
        x0 = 0
        for name, fn in row:
            for v in range(4):
                if fn is None:
                    # Baie vitrée dans une cloison de labo (hublot sur fond clair).
                    put("face_" + name, _blend_lab_window(_face_window(rng, v), _face_lab(rng, 0), v), x0 + v * FW, y)
                else:
                    put("face_" + name, fn(rng, v), x0 + v * FW, y)
            x0 += 4 * FW
        y += FH
    uy = y
    for i, k in enumerate(["steel", "glass", "rust", "lab"]):
        put("cap_" + k, _cap(k, rng), i * 128, uy)
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
    img = Image.fromarray(np.clip(atlas + 0.5, 0, 255).astype(np.uint8), "RGBA")
    img.save(out_png, optimize=True)
    with open(out_meta, "w") as f:
        f.write("## Généré par art/blender/underwater/uw_tiles.py : NE PAS ÉDITER.\n")
        f.write("## Régions (px) de assets/textures/underwater/walls.png ; 2 px par unité monde.\n")
        f.write("const REGIONS := %s\n" % json.dumps(regions))


def _blend_lab_window(win: np.ndarray, lab: np.ndarray, v: int) -> np.ndarray:
    """Hublot de _face_window posé sur une cloison de labo (le fond d'acier remplacé)."""
    out = lab.copy()
    yy, xx = np.mgrid[0:FH, 0:FW].astype(np.float32)
    if v < 2:
        keep = np.clip(34 - np.hypot(xx - FW / 2, yy - 44), 0, 1)
    else:
        keep = ((xx >= 10) & (xx < FW - 10) & (yy >= 10) & (yy < 80)).astype(np.float32)
    out[..., :3] = lab[..., :3] * (1 - keep[..., None]) + win[..., :3] * keep[..., None]
    return out


# ============================================================================ décalques

def _save_decal(cv: Canvas, name: str) -> None:
    os.makedirs(os.path.join(TMP, "decals"), exist_ok=True)
    cv.image().save(os.path.join(TMP, "decals", name + ".png"))


def make_decals() -> None:
    rng = np.random.default_rng(77)
    # Flaques d'eau (reflet bleu-vert, bord sombre humide).
    for i in range(3):
        w, h = int(rng.uniform(90, 150)), int(rng.uniform(50, 80))
        cv = Canvas(h, w, None, alpha=0, wrap=False)
        pts = []
        for k in range(14):
            a = 2 * math.pi * k / 14
            r = rng.uniform(0.7, 1.0)
            pts.append((w / 2 + math.cos(a) * (w / 2 - 4) * r, h / 2 + math.sin(a) * (h / 2 - 4) * r))
        pm, px0, py0 = poly_mask(pts, 2.5)
        cv.blend(py0, px0, pm, C(20, 40, 56), 0.55)
        pm2, px1, py1 = poly_mask([(p[0] * 0.9 + w * 0.05, p[1] * 0.85 + h * 0.05) for p in pts], 2.0)
        cv.blend(py1, px1, pm2, C(70, 150, 160), 0.55)
        for k in range(3):
            yk = h * rng.uniform(0.35, 0.6)
            mk, ox, oy = seg_mask(w * rng.uniform(0.25, 0.45), yk, w * rng.uniform(0.55, 0.75), yk - 2, 2.0)
            cv.blend(oy, ox, mk, C(200, 250, 250), 0.35)
        _save_decal(cv, "puddle_%d" % i)
    # Taches de rouille / d'huile.
    for i in range(2):
        cv = Canvas(70, 90, None, alpha=0, wrap=False)
        for k in range(6):
            m, R = ellipse_mask(rng.uniform(8, 24), rng.uniform(6, 16), rng.uniform(0, 3), soft=6)
            cv.blend(35 - R + int(rng.uniform(-8, 8)), 45 - R + int(rng.uniform(-12, 12)), m, RUST if i == 0 else C(30, 30, 40), 0.3)
        _save_decal(cv, "stain_%d" % i)
    # Bandes de danger (devant les sas) : 128 x 24.
    cv = Canvas(24, 128, None, alpha=0, wrap=False)
    cv.blend(0, 0, np.ones((24, 128), np.float32), C(30, 30, 36), 0.9)
    for x in range(-24, 140, 20):
        pm, px0, py0 = poly_mask([(x, 22), (x + 10, 22), (x + 22, 2), (x + 12, 2)], 0.8)
        cv.blend(py0, px0, pm, C(236, 186, 44))
    m = np.clip(noise(128, 1.8, rng)[:24, :128] * 1.6 - 0.5, 0, 1)
    cv.a[..., :3] = cv.a[..., :3] * (1 - 0.35 * m[..., None]) + C(60, 60, 64) * 0.35 * m[..., None]
    cv.blend(0, 0, _frame(24, 128, 1.5), OUTLINE, 0.6)
    _save_decal(cv, "hazard")
    # Grille d'évacuation au sol.
    cv = Canvas(48, 48, None, alpha=0, wrap=False)
    m, R = ellipse_mask(21, 21)
    cv.blend(24 - R, 24 - R, m, OUTLINE, 0.9)
    m, R = ellipse_mask(19.5, 19.5)
    cv.blend(24 - R, 24 - R, m, C(96, 108, 116))
    m, R = ellipse_mask(15, 15)
    cv.blend(24 - R, 24 - R, m, C(14, 24, 34))
    for k in range(-12, 14, 6):
        cv.blend(24 + k - 1, 10, np.ones((3, 28), np.float32), C(90, 102, 110))
    _save_decal(cv, "drain")
    # Câbles au sol.
    cv = Canvas(40, 160, None, alpha=0, wrap=False)
    for k, col in enumerate((C(40, 40, 46), C(150, 40, 40), C(40, 90, 150))):
        pts = [(x, 20 + math.sin(x / 18 + k) * 8 + k * 3) for x in range(0, 161, 8)]
        for a, b in zip(pts, pts[1:]):
            mk, ox, oy = seg_mask(a[0], a[1], b[0], b[1], 5.0)
            cv.blend(oy, ox, mk, OUTLINE, 0.9)
        for a, b in zip(pts, pts[1:]):
            mk, ox, oy = seg_mask(a[0], a[1], b[0], b[1], 3.2)
            cv.blend(oy, ox, mk, col)
    _save_decal(cv, "cables")
    # Plaques d'algues / bernacles au sol (zones humides).
    for i in range(2):
        cv = Canvas(64, 96, None, alpha=0, wrap=False)
        for k in range(18):
            m, R = ellipse_mask(rng.uniform(3, 8), rng.uniform(2, 5), rng.uniform(0, 3))
            cv.blend(int(rng.uniform(12, 52)) - R, int(rng.uniform(12, 84)) - R, m, C(52, 120, 80) if k % 3 else C(90, 140, 70), 0.75)
        for k in range(10 if i else 4):
            r = rng.uniform(2, 3.5)
            m, R = ellipse_mask(r, r)
            x, y = rng.uniform(10, 86), rng.uniform(10, 54)
            cv.blend(int(y - R + 1), int(x - R + 1), m, NIGHT, 0.5)
            cv.blend(int(y - R), int(x - R), m, C(214, 206, 186))
        _save_decal(cv, "algae_%d" % i)
    # Sable / vase déposé par l'inondation.
    cv = Canvas(80, 128, None, alpha=0, wrap=False)
    pts = [(64 + math.cos(a) * 58 * rng.uniform(0.6, 1), 40 + math.sin(a) * 34 * rng.uniform(0.6, 1)) for a in np.linspace(0, 2 * math.pi, 16, endpoint=False)]
    pm, px0, py0 = poly_mask(pts, 6.0)
    cv.blend(py0, px0, pm, C(120, 130, 112), 0.6)
    _save_decal(cv, "silt")
    # Rai de lumière (vertical, doux) pour les puits de lumière : 96 x 256, blanc.
    h, w = 256, 96
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    core = np.clip(1 - np.abs(xx - w / 2 - (yy - h) * 0.18) / (w * 0.42), 0, 1) ** 1.6
    fade = np.clip(yy / h, 0, 1) ** 0.7 * np.clip((h - yy) / (h * 0.15), 0, 1)
    arr = np.zeros((h, w, 4), np.float32)
    arr[..., :3] = 255
    arr[..., 3] = core * fade * 255
    Image.fromarray(arr.astype(np.uint8), "RGBA").save(os.path.join(TMP, "decals", "shaft.png"))


def make_bubble(n: int = 32) -> Image.Image:
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.hypot(xx - n / 2 + 0.5, yy - n / 2 + 0.5) / (n / 2)
    ring = np.clip(1 - np.abs(d - 0.78) * 6, 0, 1)
    fill = np.clip(1 - d, 0, 1) * 0.25
    hi = np.clip(1 - np.hypot(xx - n * 0.36, yy - n * 0.34) / (n * 0.12), 0, 1)
    a = np.clip(ring * 0.9 + fill + hi, 0, 1)
    img = np.zeros((n, n, 4), np.float32)
    img[..., :3] = 255
    img[..., 3] = a * 255
    return Image.fromarray(img.astype(np.uint8), "RGBA")


def main() -> None:
    os.makedirs(TEX_DIR, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)
    make_deck(101).save(os.path.join(TEX_DIR, "deck.png"), optimize=True)
    make_lab(102).save(os.path.join(TEX_DIR, "lab.png"), optimize=True)
    make_grate(103).save(os.path.join(TEX_DIR, "grate.png"), optimize=True)
    make_seabed(104).save(os.path.join(TEX_DIR, "seabed.png"), optimize=True)
    make_caustics(105).save(os.path.join(TEX_DIR, "caustics.png"), optimize=True)
    make_bubble().save(os.path.join(TEX_DIR, "bubble.png"), optimize=True)
    make_walls(os.path.join(TEX_DIR, "walls.png"), os.path.join(TEX_DIR, "walls_meta.gd"))
    make_decals()
    print("UW TILES OK ->", TEX_DIR, TMP)


if __name__ == "__main__":
    main()
