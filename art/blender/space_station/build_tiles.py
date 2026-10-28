"""Textures peintes de la Station Orbitale Kagami (sols tuilables, espace, planète, murs, décalques).

Usage (depuis la racine du projet ; ordre complet de régénération du biome) :
    python3 art/blender/space_station/build_tiles.py       # textures + décalques temporaires
    python3 art/blender/space_station/build_props.py       # décors 3D + atlas (décalques compris)
    python3 art/blender/space_station/build_containers.py  # conteneurs et cachettes
    python3 art/blender/space_station/build_enemies.py     # ennemis masqués + boss

Pas de Blender ici : peinture procédurale numpy (mêmes outils que art/blender/build_tiles.py :
bruits périodiques par FFT, masques anticrénelés). Le métal est peint à partir d'une carte de
hauteur (plaques biseautées, rivets, grilles, losanges) éclairée depuis le haut-gauche (même
lumière que les rendus 3D), puis salie (crasse dans les joints, rayures, grain).
Densité : 2 px par unité monde (1 case = 64 unités = 128 px). Tout est tuilable (512 px = 4 cases).

Sorties :
  assets/textures/space_station/floor_{deck,grate,hangar,lab,engine,command}.png, space.png, planet.png
  assets/textures/space_station/walls.png + walls_meta.gd (faces 128 x 104, dessus 128 x 128, utilitaires)
  $RDM_TMP/space_station/decals/*.png  (décalques au sol, empaquetés dans l'atlas par build_props.py)
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location("fw_build_tiles", os.path.join(os.path.dirname(HERE), "build_tiles.py"))
FT = importlib.util.module_from_spec(_spec)  # outils Far West : bruit, toile, masques
_spec.loader.exec_module(FT)

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEX_DIR = os.path.join(ROOT, "assets", "textures", "space_station")
TMP = os.path.join(os.environ.get("RDM_TMP", "/tmp/rdm_decor"), "space_station")

C = FT.C
noise = FT.noise
Canvas = FT.Canvas
ellipse_mask = FT.ellipse_mask
seg_mask = FT.seg_mask
poly_mask = FT.poly_mask

NIGHT = C(20, 26, 60)
OUTLINE = C(14, 14, 24)
LIGHT = np.array([-0.52, -0.62, 0.59], dtype=np.float32)
LIGHT /= np.linalg.norm(LIGHT)
CYAN = C(120, 230, 255)
AMBER = C(255, 176, 64)
RED = C(255, 56, 48)
HAZ_Y = C(236, 186, 40)
HAZ_K = C(30, 28, 34)
N = 512


# ============================================================================ outils métal

def smooth(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def blur(a: np.ndarray, r: float, wrap: bool = True) -> np.ndarray:
    """Flou gaussien périodique (FFT) d'une image HxW (ou HxWxC)."""
    if r <= 0:
        return a
    h, w = a.shape[:2]
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2.0 * (math.pi * r) ** 2 * (fx * fx + fy * fy))
    if not wrap:
        pad = int(r * 3) + 2
        if a.ndim == 2:
            ap = np.pad(a, pad, mode="edge")
        else:
            ap = np.pad(a, ((pad, pad), (pad, pad), (0, 0)), mode="edge")
        return blur(ap, r, True)[pad:pad + h, pad:pad + w]
    if a.ndim == 2:
        return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)
    out = np.empty_like(a)
    for k in range(a.shape[2]):
        out[..., k] = np.real(np.fft.ifft2(np.fft.fft2(a[..., k]) * g))
    return out


def lighting(h: np.ndarray, k: float = 1.0, wrap: bool = True) -> np.ndarray:
    """Facteur d'éclairage (≈1 sur le plat) d'une carte de hauteur (px), lumière haut-gauche."""
    if wrap:
        gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
        gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    else:
        gy, gx = np.gradient(h)
    nx, ny, nz = -gx * k, -gy * k, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    d = (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) / ln
    rel = d / LIGHT[2]
    return np.clip(1.0 + (rel - 1.0) * 1.35, 0.25, 1.9).astype(np.float32)


def plate_height(hm: np.ndarray, x0: int, y0: int, w: int, h: int, bevel: float = 4.0, height: float = 3.0,
                 gap: int = 2) -> None:
    """Plaque biseautée (coin x0, y0 ; joints de `gap` px) ajoutée à la carte de hauteur (max)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    d = np.minimum.reduce([xx - gap, w - gap - xx, yy - gap, h - gap - yy])
    p = smooth(d / bevel) * height
    sub = hm[y0:y0 + h, x0:x0 + w]
    np.maximum(sub, p, out=sub)


def dome(hm: np.ndarray, x: float, y: float, r: float, height: float, wrap: bool = True) -> None:
    R = int(math.ceil(r)) + 1
    yy, xx = np.mgrid[-R:R + 1, -R:R + 1].astype(np.float32)
    d = np.sqrt((xx - (x - int(x))) ** 2 + (yy - (y - int(y))) ** 2) / r
    bump = np.sqrt(np.clip(1.0 - d * d, 0, 1)) * height
    H, W = hm.shape
    ys = np.arange(int(y) - R, int(y) + R + 1)
    xs = np.arange(int(x) - R, int(x) + R + 1)
    if wrap:
        idx = np.ix_(ys % H, xs % W)
        hm[idx] = hm[idx] + bump
    else:
        m = (ys >= 0) & (ys < H)
        n = (xs >= 0) & (xs < W)
        hm[np.ix_(ys[m], xs[n])] += bump[np.ix_(m, n)]


def to_img(rgb: np.ndarray, alpha: np.ndarray | None = None) -> Image.Image:
    h, w = rgb.shape[:2]
    out = np.zeros((h, w, 4), np.float32)
    out[..., :3] = rgb
    out[..., 3] = 255 if alpha is None else alpha
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGBA")


def grain(rgb: np.ndarray, rng, amp: float = 5.0) -> np.ndarray:
    g = rng.standard_normal(rgb.shape[:2]).astype(np.float32) * amp
    return np.clip(rgb + g[..., None], 0, 255)


def scratches(rgb: np.ndarray, rng, n: int, col, opacity: float = 0.25, length=(10, 40)) -> np.ndarray:
    cv = Canvas(rgb.shape[0], rgb.shape[1], rgb)
    for _ in range(n):
        x, y = rng.uniform(0, cv.w), rng.uniform(0, cv.h)
        a = rng.uniform(0, math.pi)
        ln = rng.uniform(*length)
        mk, ox, oy = seg_mask(x, y, x + math.cos(a) * ln, y + math.sin(a) * ln, rng.uniform(0.6, 1.3))
        cv.blend(oy, ox, mk, col, opacity * rng.uniform(0.5, 1.0))
    return cv.a[..., :3]


def finish_floor(hm: np.ndarray, albedo: np.ndarray, rng, k: float = 1.0, ao: float = 0.55,
                 grime: float = 0.25) -> np.ndarray:
    """Éclaire la carte de hauteur, assombrit les creux (AO), salit, ajoute un grain peint."""
    L = lighting(hm, k)
    lo = blur(hm, 3.0)
    cav = np.clip((lo - hm) * 0.35, 0, 1)
    rgb = albedo * L[..., None]
    rgb = rgb * (1.0 - cav[..., None] * ao) + NIGHT * cav[..., None] * ao * 0.4
    dirt = noise(hm.shape[0], 2.2, rng)
    rgb *= (1.0 - grime * smooth((dirt - 0.45) * 2.2))[..., None] * 0.18 + (1.0 - 0.18)
    return grain(rgb, rng, 3.5)


# ============================================================================ sols

def make_deck(seed: int) -> Image.Image:
    """Pont principal : plaques d'acier gris bleuté, une à deux par case, rivets aux coins."""
    rng = np.random.default_rng(seed)
    hm = np.zeros((N, N), np.float32)
    alb = np.zeros((N, N, 3), np.float32)
    base = C(118, 128, 146)
    for cy in range(4):
        for cx in range(4):
            x0, y0 = cx * 128, cy * 128
            kind = rng.choice(3, p=[0.45, 0.3, 0.25])
            rects = [(x0, y0, 128, 128)] if kind == 0 else (
                [(x0, y0, 64, 128), (x0 + 64, y0, 64, 128)] if kind == 1 else [(x0, y0, 128, 64), (x0, y0 + 64, 128, 64)])
            for (x, y, w, h) in rects:
                plate_height(hm, x, y, w, h, bevel=3.5, height=3.0, gap=2)
                tone = base * rng.uniform(0.9, 1.08)
                alb[y:y + h, x:x + w] = tone
                for (rx, ry) in ((x + 7, y + 7), (x + w - 8, y + 7), (x + 7, y + h - 8), (x + w - 8, y + h - 8)):
                    dome(hm, rx, ry, 2.6, 1.6)
            # Motif antidérapant : petites barrettes sur une case sur trois.
            if rng.random() < 0.33:
                for i in range(6):
                    for j in range(6):
                        bx, by = x0 + 20 + i * 16, y0 + 20 + j * 16
                        if (i + j) % 2 == 0:
                            mk, ox, oy = seg_mask(bx - 4, by, bx + 4, by, 3)
                        else:
                            mk, ox, oy = seg_mask(bx, by - 4, bx, by + 4, 3)
                        hm[oy:oy + mk.shape[0], ox:ox + mk.shape[1]] += mk * 1.2
    n1 = noise(N, 2.0, rng)
    alb *= (0.92 + 0.16 * n1)[..., None]
    alb = scratches(alb, rng, 140, C(176, 188, 204), 0.22)
    rgb = finish_floor(hm, alb, rng)
    return to_img(rgb)


def make_grate(seed: int) -> Image.Image:
    """Coursives : caillebotis (fentes sombres, câbles et lueurs cyan en dessous) dans un cadre."""
    rng = np.random.default_rng(seed)
    hm = np.zeros((N, N), np.float32)
    alb = np.zeros((N, N, 3), np.float32) + C(104, 112, 128)
    under = np.zeros((N, N), np.float32)
    for cy in range(4):
        for cx in range(4):
            x0, y0 = cx * 128, cy * 128
            plate_height(hm, x0, y0, 128, 128, bevel=3.0, height=3.4, gap=2)
            # Fentes (lattes horizontales) à l'intérieur du cadre.
            for k in range(11):
                y = y0 + 16 + k * 9
                hm[y:y + 5, x0 + 14:x0 + 114] = -1.6
                under[y:y + 5, x0 + 14:x0 + 114] = 1.0
            # Traverse centrale.
            hm[y0 + 14:y0 + 114, x0 + 62:x0 + 66] = 2.6
            under[y0 + 14:y0 + 114, x0 + 62:x0 + 66] = 0.0
            for (rx, ry) in ((x0 + 7, y0 + 7), (x0 + 121, y0 + 7), (x0 + 7, y0 + 121), (x0 + 121, y0 + 121)):
                dome(hm, rx, ry, 2.4, 1.4)
    rgb = finish_floor(hm, alb, rng, ao=0.4)
    # Dessous : obscurité bleue, câbles, quelques témoins cyan.
    dark = C(14, 18, 34)
    cables = noise(N, 1.4, rng, aniso=(0.2, 1.0))
    deep = dark + C(30, 40, 60) * smooth((cables - 0.6) * 4.0)[..., None]
    glints = (rng.random((N, N)) < 0.0005).astype(np.float32)
    glints = np.clip(blur(glints, 1.2) * 40.0, 0, 1)
    deep = deep + CYAN * glints[..., None] * 0.6
    m = under[..., None]
    rgb = rgb * (1 - m) + deep * m
    rgb = scratches(rgb, rng, 60, C(170, 180, 196), 0.18)
    return to_img(grain(rgb, rng, 2.5))


def make_hangar(seed: int) -> Image.Image:
    """Hangar : grandes dalles lourdes plus sombres, taches d'huile, marques de patins."""
    rng = np.random.default_rng(seed)
    hm = np.zeros((N, N), np.float32)
    alb = np.zeros((N, N, 3), np.float32)
    base = C(96, 104, 118)
    for cy in range(4):
        for cx in range(2):
            x0, y0 = cx * 256, cy * 128
            plate_height(hm, x0, y0, 256, 128, bevel=5.0, height=3.5, gap=3)
            alb[y0:y0 + 128, x0:x0 + 256] = base * rng.uniform(0.9, 1.06)
            for i in range(9):
                for (yy_) in (y0 + 9, y0 + 119):
                    dome(hm, x0 + 12 + i * 29, yy_, 3.0, 1.8)
    n1 = noise(N, 2.4, rng)
    alb *= (0.9 + 0.2 * n1)[..., None]
    cv = Canvas(N, N, alb)
    for _ in range(14):
        m, R = ellipse_mask(rng.uniform(10, 34), rng.uniform(6, 20), rng.uniform(0, math.pi), soft=6.0)
        cv.blend(int(rng.uniform(0, N)) - R, int(rng.uniform(0, N)) - R, m, C(36, 38, 50), rng.uniform(0.25, 0.5))
    for _ in range(10):
        x, y = rng.uniform(0, N), rng.uniform(0, N)
        mk, ox, oy = seg_mask(x, y, x + rng.uniform(40, 120), y + rng.uniform(-6, 6), rng.uniform(5, 9))
        cv.blend(oy, ox, mk, C(50, 52, 62), 0.25)
    alb = scratches(cv.a[..., :3], rng, 120, C(160, 170, 186), 0.2, (14, 60))
    return to_img(finish_floor(hm, alb, rng, grime=0.4))


def make_lab(seed: int) -> Image.Image:
    """Laboratoire / infirmerie : carreaux clairs de 64 px, joints gris bleu, reflets froids."""
    rng = np.random.default_rng(seed)
    hm = np.zeros((N, N), np.float32)
    alb = np.zeros((N, N, 3), np.float32)
    for cy in range(8):
        for cx in range(8):
            x0, y0 = cx * 64, cy * 64
            plate_height(hm, x0, y0, 64, 64, bevel=2.5, height=1.6, gap=1)
            alb[y0:y0 + 64, x0:x0 + 64] = C(196, 206, 218) * rng.uniform(0.95, 1.03)
    joint = hm < 0.4
    alb[joint] = C(96, 110, 128)
    n1 = noise(N, 2.0, rng)
    alb *= (0.95 + 0.08 * n1)[..., None]
    rgb = finish_floor(hm, alb, rng, k=1.4, ao=0.3, grime=0.15)
    # Reflets froids diagonaux (sol lustré).
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    sheen = 0.5 + 0.5 * np.sin((xx + yy) / N * 2 * math.pi * 2)
    rgb = rgb + C(20, 34, 42) * (smooth((sheen - 0.75) * 3) * 0.45)[..., None]
    return to_img(np.clip(rgb, 0, 255))


def make_engine(seed: int) -> Image.Image:
    """Salle des machines : tôle larmée (losanges en relief), sombre, rouille et cambouis."""
    rng = np.random.default_rng(seed)
    hm = np.zeros((N, N), np.float32)
    alb = np.zeros((N, N, 3), np.float32)
    base = C(88, 90, 100)
    for cy in range(2):
        for cx in range(2):
            x0, y0 = cx * 256, cy * 256
            plate_height(hm, x0, y0, 256, 256, bevel=4.0, height=3.0, gap=3)
            alb[y0:y0 + 256, x0:x0 + 256] = base * rng.uniform(0.92, 1.06)
    # Losanges en quinconce (motif tuilable : pas de 16 px).
    pat = np.zeros((16, 16), np.float32)
    for (cx_, cy_, ang) in ((4, 4, 0.785), (12, 12, -0.785)):
        mk, ox, oy = seg_mask(cx_ - 3.5 * math.cos(ang), cy_ - 3.5 * math.sin(ang),
                              cx_ + 3.5 * math.cos(ang), cy_ + 3.5 * math.sin(ang), 2.6, 1.4)
        for yy_ in range(mk.shape[0]):
            for xx_ in range(mk.shape[1]):
                pat[(oy + yy_) % 16, (ox + xx_) % 16] = max(pat[(oy + yy_) % 16, (ox + xx_) % 16], mk[yy_, xx_])
    tile = np.tile(pat, (N // 16, N // 16))
    inner = hm > 2.5
    hm = hm + tile * 1.3 * inner
    n1 = noise(N, 2.2, rng)
    rust = smooth((noise(N, 2.6, rng) - 0.62) * 4.0)
    alb *= (0.88 + 0.22 * n1)[..., None]
    alb = alb * (1 - rust[..., None] * 0.6) + C(122, 74, 50) * rust[..., None] * 0.6
    cv = Canvas(N, N, alb)
    for _ in range(10):
        m, R = ellipse_mask(rng.uniform(8, 26), rng.uniform(5, 16), rng.uniform(0, math.pi), soft=5.0)
        cv.blend(int(rng.uniform(0, N)) - R, int(rng.uniform(0, N)) - R, m, C(24, 24, 30), rng.uniform(0.3, 0.55))
    return to_img(finish_floor(hm, cv.a[..., :3], rng, k=1.1, grime=0.5))


def make_command(seed: int) -> Image.Image:
    """Pont de commandement : panneaux bleu nuit, joints lumineux cyan, plaques plus fines."""
    rng = np.random.default_rng(seed)
    hm = np.zeros((N, N), np.float32)
    alb = np.zeros((N, N, 3), np.float32)
    base = C(54, 66, 98)
    for cy in range(4):
        for cx in range(4):
            x0, y0 = cx * 128, cy * 128
            plate_height(hm, x0, y0, 128, 128, bevel=2.5, height=2.2, gap=2)
            alb[y0:y0 + 128, x0:x0 + 128] = base * rng.uniform(0.92, 1.06)
            # Fines rainures décoratives.
            hm[y0 + 30:y0 + 32, x0 + 10:x0 + 118] -= 1.2
            hm[y0 + 96:y0 + 98, x0 + 10:x0 + 118] -= 1.2
    n1 = noise(N, 2.0, rng)
    alb *= (0.92 + 0.14 * n1)[..., None]
    rgb = finish_floor(hm, alb, rng, ao=0.3, grime=0.12)
    seam = (hm < 0.6).astype(np.float32)
    seam_g = np.clip(blur(seam, 2.0) * 1.4, 0, 1)
    rgb = rgb * (1 - seam[..., None] * 0.55) + C(50, 150, 200) * seam[..., None] * 0.55
    rgb = rgb + C(16, 50, 76) * seam_g[..., None] * 0.25
    return to_img(np.clip(grain(rgb, rng, 2.0), 0, 255))


def make_space(seed: int) -> Image.Image:
    """Espace (cases VOID) : fond bleu nuit, nébuleuse violette discrète, étoiles tuilables."""
    rng = np.random.default_rng(seed)
    neb = noise(N, 2.8, rng)
    neb2 = noise(N, 2.2, rng)
    rgb = np.zeros((N, N, 3), np.float32) + C(6, 9, 22)
    rgb += C(38, 22, 70) * smooth((neb - 0.5) * 2.0)[..., None] * 0.7
    rgb += C(16, 40, 80) * smooth((neb2 - 0.55) * 2.5)[..., None] * 0.6
    stars = np.zeros((N, N), np.float32)
    for _ in range(520):
        x, y = rng.integers(0, N), rng.integers(0, N)
        stars[y, x] = rng.uniform(0.3, 1.0) ** 2
    halo = blur(stars, 1.0) * 6.0
    cv = Canvas(N, N, rgb)
    rgb = cv.a[..., :3] + (C(255, 255, 255) * np.clip(stars * 1.6, 0, 1)[..., None]) + C(160, 200, 255) * np.clip(halo, 0, 1)[..., None] * 0.6
    for _ in range(9):  # étoiles brillantes en croix
        x, y = rng.uniform(20, N - 20), rng.uniform(20, N - 20)
        col = [C(255, 240, 220), C(180, 220, 255), C(255, 200, 240)][rng.integers(0, 3)]
        c2 = Canvas(N, N, rgb)
        m, R = ellipse_mask(3.0, 3.0, soft=2.0)
        c2.blend(int(y) - R, int(x) - R, m, col, 0.9)
        for a in (0.0, math.pi / 2):
            mk, ox, oy = seg_mask(x - math.cos(a) * 9, y - math.sin(a) * 9, x + math.cos(a) * 9, y + math.sin(a) * 9, 1.4, 1.4)
            c2.blend(oy, ox, mk, col, 0.5)
        rgb = c2.a[..., :3]
    return to_img(np.clip(rgb, 0, 255))


def planet_disc(n: int, rng, ring: bool = False) -> np.ndarray:
    """Planète gazeuse (RGBA flottant) : bandes, terminateur bleu nuit, halo d'atmosphère cyan."""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) + 0.5
    c = n / 2
    r = n * (0.3 if ring else 0.4)
    dx, dy = (xx - c) / r, (yy - c) / r
    d2 = dx * dx + dy * dy
    inside = d2 <= 1.0
    z = np.sqrt(np.clip(1 - d2, 0, 1))
    lat = dy + 0.15 * dx
    bands = noise(n, 2.4, rng, aniso=(7.0, 1.0))
    t = np.clip(0.5 + 0.5 * np.sin(lat * 9.0 + bands * 2.2), 0, 1)
    col = FT.ramp(t, [(0.0, C(40, 70, 150)), (0.4, C(70, 130, 210)), (0.7, C(140, 200, 240)), (1.0, C(230, 180, 160))])
    ndl = np.clip(dx * LIGHT[0] + dy * LIGHT[1] + z * LIGHT[2], -1, 1)
    lam = smooth((ndl + 0.25) * 1.6)
    col = col * (0.18 + 0.95 * lam[..., None]) + NIGHT * (1 - lam[..., None]) * 0.5
    rim = smooth((np.sqrt(d2) - 0.8) * 5.0) * lam
    col = col + C(120, 220, 255) * rim[..., None] * 0.55
    rgba = np.zeros((n, n, 4), np.float32)
    rgba[..., :3] = col
    a = np.clip((1.0 - np.sqrt(d2)) * r * 0.9, 0, 1)
    rgba[..., 3] = a * 255
    # Halo d'atmosphère.
    halo = np.clip(1.0 - (np.sqrt(d2) - 1.0) * 7.0, 0, 1) * (~inside)
    halo = halo ** 2 * (0.4 + 0.6 * smooth((dx * LIGHT[0] + dy * LIGHT[1]) + 0.6))
    rgba[..., :3] = np.where(inside[..., None], rgba[..., :3], C(110, 210, 255))
    rgba[..., 3] = np.maximum(rgba[..., 3], halo * 170)
    if ring:
        ang = -0.32
        u = (xx - c) * math.cos(ang) + (yy - c) * math.sin(ang)
        v = (-(xx - c) * math.sin(ang) + (yy - c) * math.cos(ang)) * 4.2
        rd = np.sqrt(u * u + v * v) / r
        band = smooth((rd - 1.22) * 14) * smooth((1.6 - rd) * 14) * (0.55 + 0.45 * np.sin(rd * 46))
        front = (v > 0) | ~inside
        rcol = C(220, 200, 180) * (0.6 + 0.4 * smooth(u / r + 0.5))[..., None]
        m = band * front * 0.85
        rgba[..., :3] = rgba[..., :3] * (1 - m[..., None]) + rcol * m[..., None]
        rgba[..., 3] = np.maximum(rgba[..., 3], m * 255)
    return rgba


# ============================================================================ murs

FW, FH = 128, 104


def _panel_base(rng, base, seams=(0, 64), neon: bool = True, kick=C(52, 58, 72)) -> tuple[np.ndarray, np.ndarray]:
    """Face de mur commune : rail haut, néon, panneaux, plinthe. Renvoie (hauteur, albédo)."""
    hm = np.zeros((FH, FW), np.float32)
    alb = np.zeros((FH, FW, 3), np.float32) + base
    # Panneaux (bord à bord des faces voisines : joints aux mêmes x).
    xs = list(seams) + [FW]
    for a, b in zip(xs, xs[1:]):
        yy, xx = np.mgrid[0:FH, 0:b - a].astype(np.float32) + 0.5
        d = np.minimum.reduce([xx - 1.5, (b - a) - 1.5 - xx, yy - 14, 82 - yy])
        hm[:, a:b] = np.maximum(hm[:, a:b], smooth(d / 3.0) * 2.5)
        alb[14:82, a:b] *= rng.uniform(0.94, 1.05)
    # Rail haut (y 0..10) et plinthe (y 84..104).
    hm[0:10] = 3.2
    hm[9:11] = 1.0
    alb[0:10] = base * 0.62
    alb[84:FH] = kick
    hm[84:FH] = 2.0
    hm[84:86] = 3.0
    hm[100:FH] = 0.8
    if neon:
        alb[11:14] = C(200, 245, 255)
    return hm, alb


def _shade_face(hm: np.ndarray, alb: np.ndarray, rng, emissive: np.ndarray | None = None) -> np.ndarray:
    L = lighting(hm, 1.0, wrap=True)
    lo = blur(hm, 2.5)
    cav = np.clip((lo - hm) * 0.4, 0, 1)
    rgb = alb * L[..., None] * (1.0 - cav[..., None] * 0.5)
    # Assombrissement vers le bas (lumière zénithale des néons).
    yy = np.arange(FH, dtype=np.float32)[:, None, None]
    rgb *= 1.04 - 0.22 * (yy / FH)
    rgb = grain(rgb, rng, 2.5)
    if emissive is not None:
        m = emissive[..., 3:4] / 255.0
        rgb = rgb * (1 - m) + emissive[..., :3] * m
    # Contour : liseré sombre sous le rail et au bas.
    rgb[10] = rgb[10] * 0.5
    rgb[FH - 2:FH] = OUTLINE
    return np.clip(rgb, 0, 255)


def _rivets(hm, xs, ys, r=2.0, h=1.4):
    for x in xs:
        for y in ys:
            dome(hm, x, y, r, h, wrap=False)


def face_panel(rng, v: int, base=C(112, 122, 140)) -> np.ndarray:
    hm, alb = _panel_base(rng, base)
    em = np.zeros((FH, FW, 4), np.float32)
    _rivets(hm, (6, 58, 70, 122), (18, 78))
    if v == 1:  # grille de ventilation
        for k in range(6):
            y = 34 + k * 6
            hm[y:y + 3, 76:116] = -1.5
        alb[34:70, 74:118] *= 0.8
    elif v == 2:  # étiquette + câble
        alb[24:34, 12:44] = C(220, 200, 120)
        alb[27:29, 15:40] = C(60, 50, 40)
        alb[30:32, 15:32] = C(60, 50, 40)
    elif v == 3:  # trappe d'accès
        yy, xx = np.mgrid[0:44, 0:40].astype(np.float32) + 0.5
        d = np.minimum.reduce([xx - 1, 39 - xx, yy - 1, 43 - yy])
        hm[30:74, 80:120] = hm[30:74, 80:120] - (1 - smooth(d / 2.0)) * 1.8
        alb[48:54, 112:116] = C(220, 170, 60)
    # Bande d'avertissement sur la plinthe (une face sur quatre).
    if v == 0:
        for x in range(0, FW, 16):
            mk, ox, oy = poly_mask([(x, 104), (x + 8, 104), (x + 16, 88), (x + 8, 88)])
            ys = slice(max(oy, 0), min(oy + mk.shape[0], FH))
            xs = slice(max(ox, 0), min(ox + mk.shape[1], FW))
            sub = mk[ys.start - oy:ys.stop - oy, xs.start - ox:xs.stop - ox]
            alb[ys, xs] = alb[ys, xs] * (1 - sub[..., None]) + HAZ_Y * sub[..., None]
    return _shade_face(hm, alb, rng, em)


def face_pipes(rng, v: int, base=C(100, 108, 124)) -> np.ndarray:
    """Coursive : deux conduites horizontales continues + colliers ; variante avec vanne."""
    hm, alb = _panel_base(rng, base)
    for (yc, r, col) in ((30, 7.0, C(150, 120, 90)), (52, 5.0, C(120, 140, 160))):
        yy = np.arange(FH, dtype=np.float32)[:, None]
        t = np.clip(1 - ((yy - yc) / r) ** 2, 0, 1)
        prof = np.sqrt(t) * r
        m = (t > 0).astype(np.float32)
        hm[:] = np.maximum(hm, (prof + 4.0) * m)
        alb[:] = alb * (1 - m[..., None]) + col * m[..., None]
        for cx in (22 + v * 7, 86 + v * 5):
            hm[int(yc - r - 1):int(yc + r + 2), cx:cx + 6] += 1.5
            alb[int(yc - r - 1):int(yc + r + 2), cx:cx + 6] = C(70, 74, 86)
    if v == 1:  # vanne rouge
        m9, R = ellipse_mask(9, 9, soft=1.0)
        m6, R6 = ellipse_mask(6, 6, soft=1.0)
        ring = np.clip(m9 - np.pad(m6, R - R6), 0, 1)
        y0, x0 = 30 - R, 64 - R
        hm[y0:y0 + ring.shape[0], x0:x0 + ring.shape[1]] += ring * 4
        sub = alb[y0:y0 + ring.shape[0], x0:x0 + ring.shape[1]]
        alb[y0:y0 + ring.shape[0], x0:x0 + ring.shape[1]] = sub * (1 - ring[..., None]) + C(200, 50, 40) * ring[..., None]
    return _shade_face(hm, alb, rng)


def face_screen(rng, v: int, base=C(112, 122, 140)) -> np.ndarray:
    hm, alb = _panel_base(rng, base)
    em = np.zeros((FH, FW, 4), np.float32)
    x0, y0, w, h = 22, 22, 84, 50
    yy, xx = np.mgrid[0:h + 8, 0:w + 8].astype(np.float32) + 0.5
    d = np.minimum.reduce([xx, w + 8 - xx, yy, h + 8 - yy])
    hm[y0 - 4:y0 + h + 4, x0 - 4:x0 + w + 4] += smooth(d / 3.0) * 2.0
    alb[y0 - 4:y0 + h + 4, x0 - 4:x0 + w + 4] = C(44, 48, 60)
    col = AMBER if v == 0 else CYAN
    scr = np.zeros((h, w, 3), np.float32) + col * 0.16
    rr = np.random.default_rng(100 + v)
    for k in range(6):  # lignes de texte / graphe
        ln = rr.integers(20, w - 10)
        scr[6 + k * 7:9 + k * 7, 6:6 + ln] = col * 0.85
    if v == 1:
        xs = np.arange(w)
        ys = (h * 0.55 + np.sin(xs / 6.0) * 8 + rr.normal(0, 2, w)).astype(int)
        for x, y in zip(xs, ys):
            scr[max(y - 1, 0):y + 1, x] = C(220, 255, 255)
    scan = (np.arange(h) % 3 == 0)[:, None, None]
    scr = scr * np.where(scan, 0.8, 1.0)
    em[y0:y0 + h, x0:x0 + w, :3] = scr
    em[y0:y0 + h, x0:x0 + w, 3] = 255
    # Reflet de vitre.
    for i in range(h):
        a = 18 + i
        if a < w:
            em[y0 + i, x0 + a:x0 + min(a + 10, w), :3] = np.minimum(em[y0 + i, x0 + a:x0 + min(a + 10, w), :3] + 28, 255)
    return _shade_face(hm, alb, rng, em)


def face_alarm(rng, v: int, base=C(112, 122, 140)) -> np.ndarray:
    hm, alb = _panel_base(rng, base)
    em = np.zeros((FH, FW, 4), np.float32)
    cx, cy = 64, 40
    # Boîtier.
    yy, xx = np.mgrid[0:36, 0:40].astype(np.float32) + 0.5
    d = np.minimum.reduce([xx, 40 - xx, yy, 36 - yy])
    hm[cy - 18:cy + 18, cx - 20:cx + 20] += smooth(d / 4.0) * 4.0
    alb[cy - 18:cy + 18, cx - 20:cx + 20] = C(58, 60, 70)
    m, R = ellipse_mask(12, 12, soft=1.2)
    em[cy - R:cy + R + 1, cx - R:cx + R + 1, :3] = RED
    em[cy - R:cy + R + 1, cx - R:cx + R + 1, 3] = m * 255
    m2, R2 = ellipse_mask(5, 4, soft=2.0)
    sub = em[cy - 5 - R2:cy - 5 + R2 + 1, cx - 4 - R2:cx - 4 + R2 + 1]
    sub[..., :3] = sub[..., :3] * (1 - m2[..., None]) + C(255, 210, 200) * m2[..., None]
    # Bandes jaunes et noires autour.
    for x in range(cx - 30, cx + 30, 10):
        mk, ox, oy = poly_mask([(x, 66), (x + 5, 66), (x + 10, 60), (x + 5, 60)])
        alb[oy:oy + mk.shape[0], ox:ox + mk.shape[1]] = alb[oy:oy + mk.shape[0], ox:ox + mk.shape[1]] * (1 - mk[..., None]) + HAZ_Y * mk[..., None]
    if v == 1:
        alb[70:78, 40:88] = C(220, 200, 120)
    return _shade_face(hm, alb, rng, em)


def face_window(rng, v: int, base=C(104, 114, 134)) -> np.ndarray:
    """Hublot rectangulaire arrondi : espace étoilé, nébuleuse et une tranche de planète."""
    hm, alb = _panel_base(rng, base, neon=False)
    em = np.zeros((FH, FW, 4), np.float32)
    x0, y0, w, h = 10, 14, 108, 66
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    rr_ = 14.0
    qx = np.clip(np.minimum(xx, w - xx), 0, rr_)
    qy = np.clip(np.minimum(yy, h - yy), 0, rr_)
    corner = np.sqrt((rr_ - qx) ** 2 + (rr_ - qy) ** 2)
    inner = np.where((qx < rr_) & (qy < rr_), rr_ - corner, np.minimum(np.minimum(xx, w - xx), np.minimum(yy, h - yy)))
    frame = smooth((inner + 0.0) / 3.0) * (1 - smooth((inner - 6.0) / 2.0))
    glass = smooth((inner - 6.5) / 1.0)
    hm[y0:y0 + h, x0:x0 + w] += frame * 4.0
    alb[y0:y0 + h, x0:x0 + w] = alb[y0:y0 + h, x0:x0 + w] * (1 - frame[..., None]) + C(70, 78, 96) * frame[..., None]
    # Vue.
    rr = np.random.default_rng(300 + v)
    sky = np.zeros((h, w, 3), np.float32) + C(6, 10, 28)
    sky += C(40, 24, 80) * smooth((noise(128, 2.6, rr)[:h, :w] - 0.45) * 2.0)[..., None] * 0.8
    for _ in range(40):
        sx, sy = rr.integers(0, w), rr.integers(0, h)
        sky[sy, sx] = C(255, 255, 255) * rr.uniform(0.4, 1.0)
    if v in (0, 1, 3):
        pr = [90.0, 140.0, 0.0, 70.0][v]
        pc = [(w * 0.2, h + 50.0), (w * 0.6, h + 110.0), (0, 0), (w + 20.0, h * 0.35)][v]
        py, px = np.mgrid[0:h, 0:w].astype(np.float32)
        dx, dy = (px - pc[0]) / pr, (py - pc[1]) / pr
        d2 = dx * dx + dy * dy
        inside = d2 < 1
        z = np.sqrt(np.clip(1 - d2, 0, 1))
        bands = 0.5 + 0.5 * np.sin((dy + 0.2 * dx) * 18.0 + noise(128, 2.4, rr, aniso=(7.0, 1.0))[:h, :w] * 1.6)
        pcol = FT.ramp(bands, [(0.0, C(50, 90, 170)), (0.5, C(90, 160, 230)), (1.0, C(210, 190, 170))])
        ndl = np.clip(dx * LIGHT[0] + dy * LIGHT[1] + z * LIGHT[2], -1, 1)
        lam = smooth((ndl + 0.2) * 1.6)
        pcol = pcol * (0.2 + 0.9 * lam[..., None])
        rim = np.clip(1 - np.abs(np.sqrt(d2) - 1.0) * pr / 3.0, 0, 1)
        sky = np.where(inside[..., None], pcol, sky) + C(120, 220, 255) * rim[..., None] * 0.6
    sky = sky * (0.9 + 0.1 * (yy / h))[..., None]
    for i in range(h):  # reflets de vitre diagonaux
        for (a0, wd) in ((30, 8), (44, 3)):
            a = a0 + i
            if a < w:
                sky[i, a:min(a + wd, w)] = np.minimum(sky[i, a:min(a + wd, w)] + 30, 255)
    em[y0:y0 + h, x0:x0 + w, :3] = sky
    em[y0:y0 + h, x0:x0 + w, 3] = glass * 255
    return _shade_face(hm, alb, rng, em)


def face_machine(rng, v: int) -> np.ndarray:
    """Salle des machines : tôle sombre nervurée, coulures de rouille, conduite, manomètre."""
    base = C(84, 86, 96)
    hm, alb = _panel_base(rng, base, seams=(0, 32, 64, 96), neon=False, kick=C(40, 40, 46))
    for x in (16, 48, 80, 112):
        hm[16:80, x - 2:x + 2] += 1.6
    rust = smooth((noise(128, 2.2, rng)[:FH, :FW] - 0.55) * 3.0) * np.linspace(0.3, 1.0, FH)[:, None]
    alb = alb * (1 - rust[..., None] * 0.5) + C(130, 76, 50) * rust[..., None] * 0.5
    yy = np.arange(FH, dtype=np.float32)[:, None]
    t = np.clip(1 - ((yy - 24) / 6.0) ** 2, 0, 1)
    m = (t > 0).astype(np.float32)
    hm[:] = np.maximum(hm, (np.sqrt(t) * 6 + 4) * m)
    alb[:] = alb * (1 - m[..., None]) + C(140, 110, 80) * m[..., None]
    em = np.zeros((FH, FW, 4), np.float32)
    if v == 1:  # manomètre
        mk, R = ellipse_mask(10, 10, soft=1.0)
        cx, cy = 40, 54
        alb[cy - R:cy + R + 1, cx - R:cx + R + 1] = alb[cy - R:cy + R + 1, cx - R:cx + R + 1] * (1 - mk[..., None]) + C(230, 226, 210) * mk[..., None]
        hm[cy - R:cy + R + 1, cx - R:cx + R + 1] += mk * 2.0
        nk, ox, oy = seg_mask(cx, cy, cx + 6, cy - 6, 1.8)
        alb[oy:oy + nk.shape[0], ox:ox + nk.shape[1]] = alb[oy:oy + nk.shape[0], ox:ox + nk.shape[1]] * (1 - nk[..., None]) + C(200, 30, 30) * nk[..., None]
    if v == 2:  # voyant ambre
        mk, R = ellipse_mask(5, 5, soft=1.0)
        em[60 - R:60 + R + 1, 96 - R:96 + R + 1, :3] = AMBER
        em[60 - R:60 + R + 1, 96 - R:96 + R + 1, 3] = mk * 255
    # Bandes d'avertissement sur la plinthe.
    for x in range(-16, FW + 16, 16):
        mk, ox, oy = poly_mask([(x, 104), (x + 8, 104), (x + 16, 86), (x + 8, 86)])
        ys = slice(max(oy, 0), min(oy + mk.shape[0], FH))
        xs = slice(max(ox, 0), min(ox + mk.shape[1], FW))
        if ys.start >= ys.stop or xs.start >= xs.stop:
            continue
        sub = mk[ys.start - oy:ys.stop - oy, xs.start - ox:xs.stop - ox]
        alb[ys, xs] = alb[ys, xs] * (1 - sub[..., None] * 0.9) + HAZ_Y * sub[..., None] * 0.9
    return _shade_face(hm, alb, rng, em)


def face_command(rng, v: int) -> np.ndarray:
    base = C(58, 70, 104)
    hm, alb = _panel_base(rng, base, seams=(0, 42, 86), neon=True, kick=C(34, 40, 60))
    em = np.zeros((FH, FW, 4), np.float32)
    em[60:62, 6:122, :3] = C(90, 210, 255)
    em[60:62, 6:122, 3] = 230
    if v == 1:
        alb[22:30, 50:78] = C(210, 180, 90)  # insigne doré
        hm[22:30, 50:78] += 1.2
    if v == 2:
        em[26:50, 54:74, :3] = C(80, 180, 230) * 0.5
        em[26:50, 54:74, 3] = 255
        em[30:32, 57:71, :3] = C(200, 245, 255)
        em[36:38, 57:68, :3] = C(200, 245, 255)
    return _shade_face(hm, alb, rng, em)


def face_lab(rng, v: int) -> np.ndarray:
    base = C(196, 206, 218)
    hm, alb = _panel_base(rng, base, seams=(0, 64), neon=True, kick=C(120, 134, 150))
    alb[44:48] = C(80, 200, 230)
    if v == 1:
        alb[20:36, 84:110] = C(220, 70, 70)
        alb[25:31, 94:100] = C(250, 250, 250)
        alb[22:34, 96:98] = C(250, 250, 250)
        alb[27:29, 90:104] = C(250, 250, 250)
    return _shade_face(hm, alb, rng)


def cap_tile(rng, base, ribs: bool = False) -> np.ndarray:
    """Dessus de mur (128 x 128, tuilable) : métal sombre en plaques, liseré."""
    hm = np.zeros((128, 128), np.float32)
    for (x, y, w, h) in ((0, 0, 64, 128), (64, 0, 64, 128)) if not ribs else ((0, 0, 128, 32), (0, 32, 128, 32), (0, 64, 128, 32), (0, 96, 128, 32)):
        plate_height(hm, x, y, w, h, bevel=3.0, height=2.0, gap=2)
    alb = np.zeros((128, 128, 3), np.float32) + base
    alb *= (0.9 + 0.16 * noise(128, 2.0, rng))[..., None]
    L = lighting(hm, 0.8)
    rgb = alb * L[..., None]
    return np.clip(grain(rgb, rng, 2.5), 0, 255)


def make_walls(out_png: str, out_meta: str) -> None:
    W = 1024
    atlas = np.zeros((W, W, 4), np.float32)
    regions: dict[str, list[list[int]]] = {}
    rng = np.random.default_rng(77)

    def put(name: str, arr: np.ndarray, x: int, y: int) -> None:
        h, w = arr.shape[:2]
        atlas[y:y + h, x:x + w, :3] = arr[..., :3]
        atlas[y:y + h, x:x + w, 3] = 255 if arr.shape[2] == 3 else arr[..., 3]
        regions.setdefault(name, []).append([x, y, w, h])

    rows = [
        [("face_panel", face_panel, 4), ("face_pipes", face_pipes, 2), ("face_screen", face_screen, 2)],
        [("face_window", face_window, 4), ("face_alarm", face_alarm, 2), ("face_lab", face_lab, 2)],
        [("face_machine", face_machine, 4), ("face_command", face_command, 4)],
    ]
    y = 0
    for row in rows:
        x = 0
        for name, fn, n in row:
            for v in range(n):
                put(name, fn(rng, v), x, y)
                x += FW
        y += FH
    # Dessus.
    uy = y
    put("cap_metal", cap_tile(rng, C(62, 68, 84)), 0, uy)
    put("cap_hull", cap_tile(rng, C(44, 48, 62), ribs=True), 128, uy)
    put("cap_machine", cap_tile(rng, C(56, 56, 64), ribs=True), 256, uy)
    put("cap_command", cap_tile(rng, C(44, 52, 78)), 384, uy)
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
    # Planète (décor du vide) : 512 x 512 dans le bas de l'atlas.
    pl = planet_disc(384, np.random.default_rng(5), ring=True)
    atlas[W - 384:W, 0:384] = pl
    regions["planet"] = [[0, W - 384, 384, 384]]
    pl2 = planet_disc(192, np.random.default_rng(9))
    pl2[..., :3] = pl2[..., :3] * C(1.15, 0.8, 0.7) / 1.0
    atlas[W - 192:W, 400:592] = pl2
    regions["moon"] = [[400, W - 192, 192, 192]]
    img = Image.fromarray(np.clip(atlas + 0.5, 0, 255).astype(np.uint8), "RGBA")
    img.save(out_png, optimize=True)
    with open(out_meta, "w") as f:
        f.write("## Généré par art/blender/space_station/build_tiles.py : NE PAS ÉDITER.\n")
        f.write("## Régions (px) de assets/textures/space_station/walls.png ; 2 px par unité monde.\n")
        f.write("const REGIONS := %s\n" % json.dumps(regions))


# ============================================================================ décalques

def make_decals(out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    rng = np.random.default_rng(31)

    def save(name: str, cv: Canvas) -> None:
        cv.image().save(os.path.join(out_dir, name + ".png"))

    # Bande d'avertissement (128 x 24) : diagonales jaunes et noires, bords usés.
    cv = Canvas(24, 128, C(0, 0, 0), alpha=0.0, wrap=False)
    m = np.ones((24, 128), np.float32)
    cv.blend(0, 0, m, HAZ_K, 0.92)
    for x in range(-24, 152, 24):
        mk, ox, oy = poly_mask([(x, 24), (x + 12, 24), (x + 24, 0), (x + 12, 0)])
        cv.blend(oy, ox, mk, HAZ_Y, 0.95)
    wear = noise(128, 1.6, rng)[:24, :128]
    cv.a[..., 3] *= np.clip(0.55 + wear * 0.6, 0, 1)
    save("hazard", cv)
    # Flèche au sol (64 x 64), peinture jaune usée.
    cv = Canvas(64, 64, C(0, 0, 0), alpha=0.0, wrap=False)
    mk, ox, oy = poly_mask([(32, 8), (54, 32), (40, 32), (40, 56), (24, 56), (24, 32), (10, 32)])
    cv.blend(oy, ox, mk, HAZ_Y, 0.75)
    cv.a[..., 3] *= np.clip(0.5 + noise(64, 1.4, rng) * 0.7, 0, 1)
    save("arrow", cv)
    # Faisceau de câbles (128 x 40) posé au sol.
    cv = Canvas(40, 128, C(0, 0, 0), alpha=0.0, wrap=False)
    for k, col in enumerate((C(40, 40, 50), C(160, 40, 40), C(40, 60, 120), C(50, 50, 56))):
        pts = [(x, 20 + math.sin(x / 18.0 + k) * 8 + (k - 1.5) * 4) for x in range(-4, 136, 6)]
        for (xa, ya), (xb, yb) in zip(pts, pts[1:]):
            mk, ox, oy = seg_mask(xa + 2, ya + 3, xb + 2, yb + 3, 5)
            cv.blend(oy, ox, mk, NIGHT, 0.35)
        for (xa, ya), (xb, yb) in zip(pts, pts[1:]):
            mk, ox, oy = seg_mask(xa, ya, xb, yb, 5)
            cv.blend(oy, ox, mk, OUTLINE, 1.0)
            mk, ox, oy = seg_mask(xa, ya, xb, yb, 3.4)
            cv.blend(oy, ox, mk, col, 1.0)
            mk, ox, oy = seg_mask(xa, ya - 1, xb, yb - 1, 1.0)
            cv.blend(oy, ox, mk, np.minimum(col + 70, 255), 0.7)
    save("cables", cv)
    # Brûlure (96 x 96).
    cv = Canvas(96, 96, C(0, 0, 0), alpha=0.0, wrap=False)
    m, R = ellipse_mask(40, 34, 0.3, soft=14.0)
    cv.blend(48 - R, 48 - R, m, C(16, 14, 18), 0.75)
    m, R = ellipse_mask(16, 12, 0.3, soft=6.0)
    cv.blend(48 - R, 48 - R, m, C(8, 6, 10), 0.85)
    save("scorch", cv)
    # Flaque de liquide de refroidissement (cyan lustré).
    cv = Canvas(80, 112, C(0, 0, 0), alpha=0.0, wrap=False)
    for _ in range(5):
        m, R = ellipse_mask(rng.uniform(14, 30), rng.uniform(9, 18), rng.uniform(0, 3), soft=1.2)
        cv.blend(40 - R + int(rng.uniform(-12, 12)), 56 - R + int(rng.uniform(-24, 24)), m, C(40, 170, 200), 0.75)
    m, R = ellipse_mask(10, 4, 0.3, soft=2.0)
    cv.blend(30 - R, 44 - R, m, C(210, 255, 255), 0.7)
    save("coolant", cv)
    # Tache d'huile.
    cv = Canvas(80, 96, C(0, 0, 0), alpha=0.0, wrap=False)
    for _ in range(4):
        m, R = ellipse_mask(rng.uniform(12, 28), rng.uniform(8, 18), rng.uniform(0, 3), soft=3.0)
        cv.blend(40 - R + int(rng.uniform(-8, 8)), 48 - R + int(rng.uniform(-14, 14)), m, C(20, 20, 28), 0.5)
    save("oil", cv)
    # Grille d'évacuation (64 x 64).
    cv = Canvas(64, 64, C(0, 0, 0), alpha=0.0, wrap=False)
    m = np.zeros((52, 52), np.float32) + 1.0
    cv.blend(8, 8, m, NIGHT, 0.4)
    cv.blend(6, 6, m, C(70, 76, 90), 1.0)
    for k in range(7):
        cv.blend(12 + k * 6, 12, np.ones((3, 40), np.float32), C(12, 14, 24), 1.0)
    cv.blend(6, 6, np.ones((2, 52), np.float32), C(160, 170, 190), 0.8)
    save("drain", cv)
    # Papiers / débris.
    cv = Canvas(64, 64, C(0, 0, 0), alpha=0.0, wrap=False)
    for _ in range(4):
        x, y = rng.uniform(14, 50), rng.uniform(14, 50)
        a = rng.uniform(0, math.pi)
        pts = [(x + math.cos(a + k * math.pi / 2) * 9, y + math.sin(a + k * math.pi / 2) * 7) for k in range(4)]
        mk, ox, oy = poly_mask(pts)
        cv.blend(oy + 2, ox + 2, mk, NIGHT, 0.3)
        cv.blend(oy, ox, mk, C(220, 226, 230), 0.9)
    save("papers", cv)
    # Bande lumineuse au sol (balisage, 128 x 12).
    cv = Canvas(12, 128, C(0, 0, 0), alpha=0.0, wrap=False)
    cv.blend(2, 0, np.ones((8, 128), np.float32), C(30, 34, 44), 1.0)
    for x in range(4, 128, 16):
        cv.blend(4, x, np.ones((4, 8), np.float32), C(170, 245, 255), 1.0)
    save("lightstrip", cv)


def main() -> None:
    os.makedirs(TEX_DIR, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)
    make_deck(11).save(os.path.join(TEX_DIR, "floor_deck.png"), optimize=True)
    make_grate(12).save(os.path.join(TEX_DIR, "floor_grate.png"), optimize=True)
    make_hangar(13).save(os.path.join(TEX_DIR, "floor_hangar.png"), optimize=True)
    make_lab(14).save(os.path.join(TEX_DIR, "floor_lab.png"), optimize=True)
    make_engine(15).save(os.path.join(TEX_DIR, "floor_engine.png"), optimize=True)
    make_command(16).save(os.path.join(TEX_DIR, "floor_command.png"), optimize=True)
    make_space(17).save(os.path.join(TEX_DIR, "space.png"), optimize=True)
    make_walls(os.path.join(TEX_DIR, "walls.png"), os.path.join(TEX_DIR, "walls_meta.gd"))
    make_decals(os.path.join(TMP, "decals"))
    # Poussière / particule froide (32 px).
    yy, xx = np.mgrid[0:32, 0:32].astype(np.float32)
    d = np.hypot(xx - 15.5, yy - 15.5) / 16.0
    mote = np.zeros((32, 32, 4), np.float32)
    mote[..., :3] = 255
    mote[..., 3] = np.clip(1 - d, 0, 1) ** 2 * 255
    Image.fromarray(mote.astype(np.uint8), "RGBA").save(os.path.join(TEX_DIR, "mote.png"), optimize=True)
    print("TILES OK ->", TEX_DIR, TMP)


if __name__ == "__main__":
    main()
