"""Textures peintes du décor Far West (sols tuilables, faces de murs, toits, décalques plats).

Usage (depuis la racine du projet) :
    python3 art/blender/build_tiles.py            # écrit assets/textures/** (+ décalques temporaires)

Pas de Blender ici : peinture procédurale numpy (bruits périodiques par FFT, « coups de pinceau »
elliptiques, cailloux et touffes d'herbe tamponnés avec repli torique) => tout est tuilable.
Densité : 2 px par unité monde (1 case = 64 unités = 128 px), comme le héros 3D.
Lumière : couchant à l'ouest (haut-gauche), ombres bleu nuit portées vers le bas-droite.

Sorties :
  assets/textures/ground/sand.png, sand_b.png, planks.png, mine.png, macro.png  (répétition GPU)
  assets/textures/walls.png + walls_meta.gd (atlas : faces de murs, dessus, utilitaires)
  assets/textures/roofs/{shingle,tin,flat}.png (matières de toit tuilables, teintées en jeu)
  $RDM_TMP/tiles/decals/*.png              (décalques : empaquetés dans l'atlas par build_props)
"""
from __future__ import annotations

import json
import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX_DIR = os.path.join(ROOT, "assets", "textures")
TMP = os.path.join(os.environ.get("RDM_TMP", "/tmp/rdm_decor"), "tiles")

NIGHT = np.array([52, 56, 112], dtype=np.float32)       # ombres bleu nuit (sRGB)
OUTLINE = np.array([46, 28, 34], dtype=np.float32)


def C(*v) -> np.ndarray:
    return np.array(v, dtype=np.float32)


# ============================================================================ bruit & toile

def noise(n: int, beta: float, rng: np.random.Generator, aniso=(1.0, 1.0), m: int | None = None) -> np.ndarray:
    """Bruit fractal PÉRIODIQUE (n lignes x m colonnes) dans [0, 1] (spectre en 1/f^beta)."""
    m = m or n
    w = rng.standard_normal((n, m))
    F = np.fft.fft2(w)
    fy = np.fft.fftfreq(n)[:, None] * aniso[1]
    fx = np.fft.fftfreq(m)[None, :] * aniso[0]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    F *= f ** (-beta / 2.0)
    F[0, 0] = 0.0
    r = np.real(np.fft.ifft2(F))
    lo, hi = np.percentile(r, 1), np.percentile(r, 99)
    return np.clip((r - lo) / (hi - lo + 1e-9), 0.0, 1.0)


def ramp(t: np.ndarray, stops: list[tuple[float, np.ndarray]]) -> np.ndarray:
    """Rampe de couleurs (t : HxW) -> HxWx3."""
    out = np.zeros(t.shape + (3,), dtype=np.float32)
    xs = [s[0] for s in stops]
    for k in range(3):
        out[..., k] = np.interp(t, xs, [float(s[1][k]) for s in stops])
    return out


class Canvas:
    """Toile RGBA flottante (0..255) avec tampons à repli torique (wrap) optionnel."""

    def __init__(self, h: int, w: int, rgb=None, alpha: float = 255.0, wrap: bool = True):
        self.h, self.w, self.wrap = h, w, wrap
        self.a = np.zeros((h, w, 4), dtype=np.float32)
        if rgb is not None:
            self.a[..., :3] = rgb
        self.a[..., 3] = alpha

    def blend(self, y0: int, x0: int, mask: np.ndarray, color, opacity: float = 1.0) -> None:
        """Dépose `color` (3,) ou (h,w,3) avec la couverture `mask` (h,w) en (y0, x0) (coin)."""
        mh, mw = mask.shape
        if self.wrap:
            ys = np.arange(y0, y0 + mh) % self.h
            xs = np.arange(x0, x0 + mw) % self.w
            idx = np.ix_(ys, xs)
            m = mask
            col = color
        else:
            ya, yb = max(y0, 0), min(y0 + mh, self.h)
            xa, xb = max(x0, 0), min(x0 + mw, self.w)
            if ya >= yb or xa >= xb:
                return
            idx = (slice(ya, yb), slice(xa, xb))
            m = mask[ya - y0:yb - y0, xa - x0:xb - x0]
            col = color if np.ndim(color) == 1 else color[ya - y0:yb - y0, xa - x0:xb - x0]
        al = (m * opacity)[..., None]
        dst = self.a[idx]
        src_rgb = np.broadcast_to(np.asarray(col, dtype=np.float32), dst[..., :3].shape)
        da = dst[..., 3:4] / 255.0
        out_a = al + da * (1.0 - al)
        rgb = (src_rgb * al + dst[..., :3] * da * (1.0 - al)) / np.maximum(out_a, 1e-6)
        dst[..., :3] = rgb
        dst[..., 3:4] = out_a * 255.0
        self.a[idx] = dst

    def image(self) -> Image.Image:
        return Image.fromarray(np.clip(self.a + 0.5, 0, 255).astype(np.uint8), "RGBA")


def ellipse_mask(a: float, b: float, rot: float = 0.0, soft: float = 0.8) -> tuple[np.ndarray, int]:
    """Masque d'ellipse anticrénelée (demi-axes a, b en px). Renvoie (masque, rayon de boîte)."""
    R = int(math.ceil(max(a, b) + 2))
    yy, xx = np.mgrid[-R:R + 1, -R:R + 1].astype(np.float32)
    c, s = math.cos(rot), math.sin(rot)
    u = xx * c + yy * s
    v = -xx * s + yy * c
    d = np.sqrt((u / max(a, 0.3)) ** 2 + (v / max(b, 0.3)) ** 2)
    dist = (d - 1.0) * min(a, b)
    return np.clip(0.5 - dist / max(soft, 0.2), 0.0, 1.0), R


def poly_mask(pts: list[tuple[float, float]], soft: float = 0.7) -> tuple[np.ndarray, int, int]:
    """Masque d'un polygone (coordonnées locales). Renvoie (masque, x0, y0)."""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0, y0 = int(math.floor(min(xs))) - 2, int(math.floor(min(ys))) - 2
    x1, y1 = int(math.ceil(max(xs))) + 2, int(math.ceil(max(ys))) + 2
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32) + 0.5
    inside = np.zeros(xx.shape, dtype=bool)
    dmin = np.full(xx.shape, 1e9, dtype=np.float32)
    n = len(pts)
    for i in range(n):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % n]
        cond = ((ay > yy) != (by > yy)) & (xx < (bx - ax) * (yy - ay) / (by - ay + 1e-9) + ax)
        inside ^= cond
        dx, dy = bx - ax, by - ay
        L = dx * dx + dy * dy + 1e-9
        t = np.clip(((xx - ax) * dx + (yy - ay) * dy) / L, 0, 1)
        dmin = np.minimum(dmin, np.hypot(xx - ax - t * dx, yy - ay - t * dy))
    sd = np.where(inside, -dmin, dmin)
    return np.clip(0.5 - sd / soft, 0, 1), x0, y0


def seg_mask(x0: float, y0: float, x1: float, y1: float, w0: float, w1: float | None = None):
    """Trait (segment épais, effilé de w0 à w1). Renvoie (masque, ox, oy)."""
    w1 = w0 if w1 is None else w1
    R = max(w0, w1) + 2
    bx0, by0 = int(math.floor(min(x0, x1) - R)), int(math.floor(min(y0, y1) - R))
    bx1, by1 = int(math.ceil(max(x0, x1) + R)), int(math.ceil(max(y0, y1) + R))
    yy, xx = np.mgrid[by0:by1, bx0:bx1].astype(np.float32) + 0.5
    dx, dy = x1 - x0, y1 - y0
    L = dx * dx + dy * dy + 1e-9
    t = np.clip(((xx - x0) * dx + (yy - y0) * dy) / L, 0, 1)
    d = np.hypot(xx - x0 - t * dx, yy - y0 - t * dy)
    w = (w0 + (w1 - w0) * t) * 0.5
    return np.clip(w + 0.5 - d, 0, 1), bx0, by0


# ============================================================================ éléments peints

def pebble(cv: Canvas, x: float, y: float, r: float, rng, base=C(196, 164, 140), outline=True,
           shadow_len: float = 1.0) -> None:
    """Caillou : ombre portée bleu nuit (bas-droite), contour, corps, reflet chaud haut-gauche."""
    rot = rng.uniform(-0.6, 0.6)
    a, b = r * rng.uniform(1.0, 1.35), r * rng.uniform(0.7, 0.95)
    m, R = ellipse_mask(a * 1.15, b * 1.0, rot)
    cv.blend(int(y - R + b * 0.55 * shadow_len), int(x - R + a * 0.7 * shadow_len), m, NIGHT, 0.32)
    if outline:
        m, R = ellipse_mask(a + 1.1, b + 1.1, rot)
        cv.blend(int(y - R), int(x - R), m, OUTLINE, 0.85)
    col = base * rng.uniform(0.86, 1.08)
    m, R = ellipse_mask(a, b, rot)
    cv.blend(int(y - R), int(x - R), m, col)
    # face ombrée (bas-droite)
    m, R = ellipse_mask(a * 0.8, b * 0.62, rot)
    cv.blend(int(y - R + b * 0.38), int(x - R + a * 0.25), m, col * 0.72 + NIGHT * 0.18, 0.75)
    # reflet chaud
    m, R = ellipse_mask(a * 0.5, b * 0.42, rot)
    cv.blend(int(y - R - b * 0.32), int(x - R - a * 0.3), m, np.minimum(col * 1.22 + C(14, 8, 0), 255), 0.9)


def grass_tuft(cv: Canvas, x: float, y: float, size: float, rng, cols=None) -> None:
    """Touffe d'herbe sèche : brins en éventail, ombre au pied, brins clairs côté ouest."""
    cols = cols or [C(232, 204, 118), C(196, 172, 86), C(150, 140, 64), C(120, 104, 52)]
    m, R = ellipse_mask(size * 0.7, size * 0.22)
    cv.blend(int(y - R + 2), int(x - R + size * 0.35), m, NIGHT, 0.3)
    n = int(6 + size * 0.6)
    blades = []
    for i in range(n):
        ang = -math.pi / 2 + (i / (n - 1) - 0.5) * 2.1 + rng.uniform(-0.15, 0.15)
        ln = size * rng.uniform(0.55, 1.0) * (1.0 - 0.35 * abs(i / (n - 1) - 0.5))
        bx = x + rng.uniform(-size * 0.15, size * 0.15)
        blades.append((bx, ang, ln))
    for bx, ang, ln in blades:  # contour sombre
        ex, ey = bx + math.cos(ang) * ln, y + math.sin(ang) * ln
        mk, ox, oy = seg_mask(bx, y, ex, ey, 3.4, 1.2)
        cv.blend(oy, ox, mk, OUTLINE, 0.7)
    for k, (bx, ang, ln) in enumerate(blades):
        ex, ey = bx + math.cos(ang) * ln, y + math.sin(ang) * ln
        col = cols[0] if math.cos(ang) < -0.1 else cols[1 + (k % 2)]
        mk, ox, oy = seg_mask(bx, y, ex, ey, 2.0, 0.6)
        cv.blend(oy, ox, mk, col)


def strokes(cv: Canvas, n: int, rng, color_fn, length=(6, 16), width=(2.5, 4.5), opacity=0.35,
            angle_fn=None) -> None:
    """Coups de pinceau elliptiques (aspect peint). color_fn(y, x) -> couleur."""
    for _ in range(n):
        x, y = rng.uniform(0, cv.w), rng.uniform(0, cv.h)
        ang = angle_fn(y, x) if angle_fn else rng.uniform(0, math.pi)
        m, R = ellipse_mask(rng.uniform(*length) * 0.5, rng.uniform(*width) * 0.5, ang, soft=1.6)
        cv.blend(int(y - R), int(x - R), m, color_fn(int(y) % cv.h, int(x) % cv.w), opacity)


def crack(cv: Canvas, x: float, y: float, length: float, rng, col=C(120, 74, 52), w: float = 1.6) -> None:
    ang = rng.uniform(0, math.pi)
    px, py = x, y
    steps = int(length / 5) + 2
    for i in range(steps):
        ang += rng.uniform(-0.6, 0.6)
        nx, ny = px + math.cos(ang) * 5, py + math.sin(ang) * 5
        mk, ox, oy = seg_mask(px, py, nx, ny, w * (1.0 - 0.6 * i / steps) + 0.4)
        cv.blend(oy, ox, mk, col, 0.75)
        mk, ox, oy = seg_mask(px - 0.8, py - 1.0, nx - 0.8, ny - 1.0, 0.8)
        cv.blend(oy, ox, mk, C(250, 214, 160), 0.35)
        if rng.random() < 0.18:
            crack(cv, nx, ny, length * 0.4, rng, col, w * 0.7)
        px, py = nx, ny


def fine_grain(cv: Canvas, rng, amp: float = 7.0) -> None:
    g = rng.standard_normal((cv.h, cv.w)).astype(np.float32) * amp
    cv.a[..., :3] = np.clip(cv.a[..., :3] + g[..., None], 0, 255)


# ============================================================================ sols

def make_sand(seed: int, variant_b: bool = False, n: int = 512) -> Image.Image:
    rng = np.random.default_rng(seed)
    macro = noise(n, 2.6, rng)
    mid = noise(n, 1.8, rng)
    t = 0.55 * macro + 0.45 * mid
    if variant_b:
        stops = [(0.0, C(170, 116, 76)), (0.35, C(198, 142, 92)), (0.7, C(214, 162, 104)), (1.0, C(232, 184, 126))]
    else:
        stops = [(0.0, C(184, 128, 84)), (0.3, C(210, 154, 100)), (0.65, C(226, 174, 114)), (1.0, C(242, 198, 140))]
    base = ramp(t, stops)
    # Rides de vent (diagonales, ondulées).
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    warp = noise(n, 2.4, rng) * 6.0
    rip = np.sin((xx * 3 + yy * 5) / n * 2 * math.pi * 6 + warp)
    rip2 = np.sin((xx * 3 + yy * 5) / n * 2 * math.pi * 6 + warp + 0.5)
    base += (np.clip(rip - 0.75, 0, 1) * 30 - np.clip(rip2 - 0.8, 0, 1) * 40)[..., None] * (0.25 + 0.5 * mid[..., None])
    cv = Canvas(n, n, base)
    # Coups de pinceau : taches claires/sombres orientées par le vent.
    def col_fn(y, x):
        return np.clip(base[y, x] * rng.uniform(0.9, 1.1), 0, 255)
    strokes(cv, 2600, rng, col_fn, length=(8, 22), width=(3, 6), opacity=0.32,
            angle_fn=lambda y, x: -0.55 + rng.uniform(-0.3, 0.3))
    fine_grain(cv, rng, 5.0)
    # Gravillons et cailloux.
    for _ in range(260 if variant_b else 150):
        r = rng.uniform(0.9, 2.2)
        x, y = rng.uniform(0, n), rng.uniform(0, n)
        m, R = ellipse_mask(r, r * 0.8)
        cv.blend(int(y - R + 1), int(x - R + 1), m, NIGHT, 0.25)
        cv.blend(int(y - R), int(x - R), m, C(150, 104, 80) if rng.random() < 0.5 else C(246, 214, 170), 0.8)
    for _ in range(30 if variant_b else 14):
        pebble(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(2.5, 5.0), rng,
               C(206, 172, 148) if rng.random() < 0.6 else C(176, 140, 126))
    for _ in range(6 if variant_b else 2):
        pebble(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(6.0, 9.0), rng, C(196, 160, 140))
    if variant_b:
        # Plaques d'herbe sèche et terre craquelée.
        for _ in range(16):
            cx, cy = rng.uniform(0, n), rng.uniform(0, n)
            for _k in range(rng.integers(2, 5)):
                grass_tuft(cv, cx + rng.uniform(-18, 18), cy + rng.uniform(-10, 10), rng.uniform(9, 16), rng)
        for _ in range(5):
            crack(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(30, 60), rng)
    else:
        for _ in range(4):
            grass_tuft(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(8, 12), rng)
        for _ in range(2):
            crack(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(20, 40), rng)
    return cv.image().convert("RGB")


def make_planks(seed: int, n: int = 512) -> Image.Image:
    """Plancher de lattes horizontales vieillies (1 latte = 16 unités monde = 32 px)."""
    rng = np.random.default_rng(seed)
    bh = 32
    rows = n // bh
    grain = noise(n, 1.4, rng, aniso=(0.06, 1.0))      # fibres allongées en x
    big = noise(n, 2.6, rng)
    img = np.zeros((n, n, 3), dtype=np.float32)
    palette = [C(160, 106, 66), C(146, 96, 60), C(172, 118, 74), C(136, 90, 58), C(154, 108, 72), C(124, 84, 56)]
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    joints: list[tuple[int, int]] = []
    for r in range(rows):
        y0 = r * bh
        # 1 ou 2 aboutements par rangée (décalés), tuilables (modulo n).
        cuts = sorted(int(v) for v in rng.choice(np.arange(0, n, 16), size=rng.integers(1, 3), replace=False))
        segs = []
        for i, c in enumerate(cuts):
            c2 = cuts[(i + 1) % len(cuts)]
            segs.append((c, c2 if c2 > c else c2 + n))
        for (a, b) in segs:
            col = palette[rng.integers(len(palette))] * rng.uniform(0.92, 1.08)
            xs = np.arange(a, b) % n
            sl = (slice(y0, y0 + bh),)
            blk = np.ones((bh, len(xs), 3), np.float32) * col
            g = grain[y0:y0 + bh][:, xs]
            tone = (g - 0.5)
            # Veinage posterisé (aspect peint) + usure au centre.
            q = np.round(tone * 5) / 5
            blk *= (1.0 + q[..., None] * 0.22)
            blk *= (0.92 + 0.16 * big[y0:y0 + bh][:, xs])[..., None]
            # Biseau : lèvre claire en haut, ombre en bas.
            prof = np.ones(bh, np.float32)
            prof[0:2] = 1.25
            prof[2:4] = 1.1
            prof[-5:-2] = 0.9
            prof[-2:] = 0.72
            blk *= prof[:, None, None]
            img[sl[0], xs] = blk.transpose(0, 1, 2)
            joints.append((y0, a % n))
            # Noeud occasionnel.
            if rng.random() < 0.35:
                kx = int(rng.uniform(a + 20, b - 20)) % n
                ky = y0 + int(rng.uniform(9, bh - 9))
                kn = np.exp(-(((xx - kx + n / 2) % n - n / 2) ** 2 / 50 + (yy - ky) ** 2 / 14))
                img -= (kn * 55)[..., None] * C(0.9, 1.0, 1.1)
    img = np.clip(img, 0, 255)
    cv = Canvas(n, n, img)
    # Interstices sombres entre rangées.
    for r in range(rows):
        y0 = r * bh
        cv.blend(y0 - 1, 0, np.ones((2, n), np.float32), C(54, 32, 30), 0.95)
    # Aboutements + clous.
    for (y0, x) in joints:
        cv.blend(y0, x - 1, np.ones((bh, 2), np.float32), C(58, 34, 30), 0.95)
        cv.blend(y0 + 1, x + 1, np.ones((bh - 2, 1), np.float32), C(210, 160, 110), 0.5)
        for dy in (8, bh - 9):
            for dx in (-6, 6):
                m, R = ellipse_mask(1.5, 1.5)
                cv.blend(y0 + dy - R, x + dx - R, m, C(52, 46, 52))
                m, R = ellipse_mask(0.7, 0.7)
                cv.blend(y0 + dy - R - 1, x + dx - R - 1, m, C(180, 170, 170), 0.8)
    # Taches et éraflures (usure).
    for _ in range(40):
        m, R = ellipse_mask(rng.uniform(4, 14), rng.uniform(2, 6), rng.uniform(-0.2, 0.2), soft=4)
        cv.blend(int(rng.uniform(0, n)) - R, int(rng.uniform(0, n)) - R, m, C(92, 58, 40), 0.18)
    for _ in range(60):
        x, y = rng.uniform(0, n), rng.uniform(0, n)
        mk, ox, oy = seg_mask(x, y, x + rng.uniform(6, 22), y + rng.uniform(-1.5, 1.5), 1.0)
        cv.blend(oy, ox, mk, C(206, 160, 116), 0.4)
    fine_grain(cv, rng, 4.0)
    return cv.image().convert("RGB")


def make_mine(seed: int, n: int = 512) -> Image.Image:
    rng = np.random.default_rng(seed)
    t = 0.6 * noise(n, 2.4, rng) + 0.4 * noise(n, 1.6, rng)
    base = ramp(t, [(0.0, C(70, 58, 62)), (0.35, C(96, 78, 70)), (0.7, C(116, 94, 80)), (1.0, C(138, 114, 94))])
    cv = Canvas(n, n, base)
    strokes(cv, 2200, rng, lambda y, x: np.clip(base[y, x] * rng.uniform(0.85, 1.12), 0, 255),
            length=(6, 18), width=(3, 6), opacity=0.35)
    # Flaques humides bleutées.
    wet = noise(n, 2.8, rng)
    cv.a[..., :3] = cv.a[..., :3] * (1 - 0.22 * np.clip((wet - 0.72) * 5, 0, 1))[..., None] + \
        (NIGHT * 0.22 * np.clip((wet - 0.72) * 5, 0, 1)[..., None])
    fine_grain(cv, rng, 6.0)
    for _ in range(420):
        r = rng.uniform(0.8, 2.0)
        m, R = ellipse_mask(r, r * 0.8)
        x, y = rng.uniform(0, n), rng.uniform(0, n)
        cv.blend(int(y - R + 1), int(x - R + 1), m, C(30, 26, 44), 0.35)
        cv.blend(int(y - R), int(x - R), m, C(150, 130, 120) if rng.random() < 0.6 else C(60, 50, 54), 0.85)
    for _ in range(40):
        pebble(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(2.5, 6.0), rng, C(130, 114, 110))
    for _ in range(8):
        pebble(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(7.0, 11.0), rng, C(118, 102, 100))
    # Paillettes d'or et de pyrite.
    for _ in range(26):
        x, y = rng.uniform(0, n), rng.uniform(0, n)
        m, R = ellipse_mask(1.3, 1.0)
        cv.blend(int(y - R), int(x - R), m, C(255, 210, 90))
        cv.blend(int(y - R - 1), int(x - R - 1), ellipse_mask(0.6, 0.6)[0], C(255, 250, 210))
    return cv.image().convert("RGB")


def make_macro(seed: int, n: int = 256) -> Image.Image:
    rng = np.random.default_rng(seed)
    a = noise(n, 2.8, rng)
    b = noise(n, 1.9, rng)
    c = noise(n, 3.2, rng)
    rgb = np.stack([a, b, c], axis=-1) * 255
    return Image.fromarray(rgb.astype(np.uint8), "RGB")


# ============================================================================ murs (atlas)
# Face : 128 x 104 px (64 x 52 unités monde). Dessus : 128 x 128 (tuilable).

FW, FH = 128, 104


def _clapboard(rng, base: np.ndarray, w: int, h: int, board: int = 13) -> np.ndarray:
    """Bardage à clins horizontal tuilable en x (w px)."""
    g = noise(max(w, h), 1.3, rng, aniso=(0.08, 1.0), m=max(w, h))[:h, :w]
    img = np.ones((h, w, 3), np.float32) * base
    y = 0
    while y < h:
        hh = min(board, h - y)
        col = base * rng.uniform(0.9, 1.08)
        blk = np.ones((hh, w, 3), np.float32) * col
        blk *= (1.0 + (np.round((g[y:y + hh] - 0.5) * 4) / 4 * 0.2))[..., None]
        prof = np.linspace(1.18, 0.82, hh)[:, None, None]
        blk *= prof
        blk[-2:] = blk[-2:] * 0.55 + NIGHT * 0.2
        img[y:y + hh] = blk
        y += board
    return img


def _wall_face(kind: str, rng, variant: int, palette: dict) -> np.ndarray:
    w, h = FW, FH
    if kind == "wood":
        base = palette["wood"]
        img = _clapboard(rng, base, w, h)
        cv = Canvas(h, w, img, wrap=False)
        # Aboutements décalés + clous.
        for r in range(0, h - 13, 13):
            if rng.random() < 0.45:
                x = int(rng.uniform(8, w - 8))
                cv.blend(r, x, np.ones((12, 2), np.float32), C(60, 40, 36), 0.9)
        for _ in range(int(rng.integers(1, 4))):
            m, R = ellipse_mask(rng.uniform(5, 14), rng.uniform(3, 8), soft=4)
            cv.blend(int(rng.uniform(10, h - 20)) - R, int(rng.uniform(0, w)) - R, m, base * 0.7, 0.25)
        if variant == 3:
            # Planche remplacée (plus claire, moins délavée).
            y = 13 * int(rng.integers(2, 6))
            cv.blend(y, 30, np.ones((12, 50), np.float32), base * 1.2, 0.6)
        return _face_finish(cv, kind, palette)
    if kind == "adobe":
        base = palette["adobe"]
        t = noise(256, 2.2, rng)[:h, :w]
        img = ramp(t, [(0, base * 0.84), (0.5, base), (1, np.minimum(base * 1.1, 255))])
        cv = Canvas(h, w, img, wrap=False)
        strokes(cv, 160, rng, lambda y, x: np.clip(img[y, x] * rng.uniform(0.92, 1.08), 0, 255),
                length=(10, 24), width=(4, 8), opacity=0.3)
        if variant in (1, 3):
            # Enduit tombé : briques crues apparentes.
            ox, oy = int(rng.uniform(10, w - 50)), int(rng.uniform(26, h - 44))
            pm, px0, py0 = poly_mask([(0, 4), (14, 0), (40, 3), (44, 18), (30, 26), (6, 24)], 1.2)
            cv.blend(oy + py0, ox + px0, pm, C(150, 84, 60))
            for by in range(0, 24, 8):
                for bx in range((by // 8) % 2 * 7, 40, 14):
                    m = np.ones((6, 12), np.float32)
                    cv.blend(oy + by + 1, ox + bx + 2, m * pm[min(by + 4 - py0, pm.shape[0] - 1)][min(bx + 6 - px0, pm.shape[1] - 1)],
                             C(176, 102, 72) * rng.uniform(0.9, 1.1))
            pm2, px1, py1 = poly_mask([(0, 4), (14, 0), (40, 3), (44, 18), (30, 26), (6, 24)], 1.2)
            edge = np.clip(pm2 - np.roll(pm2, (-2, -2), (0, 1)), 0, 1)
            cv.blend(oy + py1, ox + px1, edge, OUTLINE, 0.6)
        if variant == 2:
            crack(cv, rng.uniform(20, 100), rng.uniform(30, 60), 40, rng, base * 0.55, 1.4)
        # Vigas (bouts de poutres) en haut.
        if variant % 2 == 0:
            for vx in (34, 94):
                cv.blend(12 + 3, vx + 3, np.ones((12, 16), np.float32), NIGHT, 0.4)
                cv.blend(12, vx, np.ones((12, 16), np.float32), C(112, 70, 44))
                cv.blend(12, vx, np.ones((3, 16), np.float32), C(160, 110, 72))
                cv.blend(12, vx, _frame(12, 16, 1.5), OUTLINE, 0.9)
        return _face_finish(cv, kind, palette)
    if kind.startswith("int_"):
        return _interior_face(kind, rng, variant)
    if kind == "rock":
        t = noise(256, 2.0, rng)[:h, :w]
        img = ramp(t, [(0, C(58, 48, 56)), (0.5, C(92, 76, 74)), (1, C(122, 104, 96))])
        cv = Canvas(h, w, img, wrap=False)
        for _ in range(9):
            cx, cy = rng.uniform(6, w - 6), rng.uniform(10, h - 14)
            rr = rng.uniform(8, 16)
            pts = [(cx + math.cos(a) * rr * rng.uniform(0.75, 1.1), cy + math.sin(a) * rr * 0.75 * rng.uniform(0.75, 1.1))
                   for a in np.linspace(0, 2 * math.pi, 7)[:-1]]
            pm, px0, py0 = poly_mask(pts, 1.0)
            col = C(104, 88, 86) * rng.uniform(0.8, 1.15)
            sh, _, _ = poly_mask([(p[0] + 3, p[1] + 3) for p in pts], 1.5)
            cv.blend(py0 + 0, px0 + 0, sh[:pm.shape[0], :pm.shape[1]] if sh.shape == pm.shape else pm, NIGHT, 0.35)
            cv.blend(py0, px0, pm, col)
            hi, hx, hy = poly_mask([(cx + (p[0] - cx) * 0.6 - rr * 0.25, cy + (p[1] - cy) * 0.6 - rr * 0.25) for p in pts], 1.0)
            cv.blend(hy, hx, hi, np.minimum(col * 1.3, 255), 0.7)
            edge = np.clip(pm - np.roll(np.roll(pm, -1, 0), -1, 1) * 0.0, 0, 1)
            ring = np.clip(pm * 4 * (1 - pm), 0, 1)
            cv.blend(py0, px0, ring, OUTLINE, 0.8)
            del edge
        if variant == 3:
            # Étai de bois.
            cv.blend(0, 52, np.ones((h, 24), np.float32), C(120, 80, 52))
            cv.blend(0, 52, np.ones((h, 6), np.float32), C(176, 128, 84))
            cv.blend(0, 70, np.ones((h, 6), np.float32), C(76, 50, 40))
            cv.blend(0, 52, _frame(h, 24, 2), OUTLINE, 0.9)
        if variant == 1:
            # Veine de minerai doré.
            for k in range(6):
                x = 20 + k * 15 + rng.uniform(-4, 4)
                y = 40 + math.sin(k) * 10
                m, R = ellipse_mask(3, 2)
                cv.blend(int(y - R), int(x - R), m, C(240, 196, 90))
        return _face_finish(cv, kind, palette)
    if kind == "fence":
        cv = Canvas(h, w, C(40, 36, 62), alpha=0.0, wrap=False)
        n = 4
        pw = w // n
        for i in range(n):
            x0 = i * pw + 2
            top = 8 + int(rng.uniform(0, 8))
            col = palette["fence"] * rng.uniform(0.88, 1.1)
            pts = [(x0, h), (x0, top + 7), (x0 + pw / 2 - 2, top), (x0 + pw - 4, top + 7), (x0 + pw - 4, h)]
            sh, sx, sy = poly_mask([(p[0] + 5, p[1] + 2) for p in pts], 1.2)
            cv.blend(sy, sx, sh, NIGHT, 0.35)
            pm, px0, py0 = poly_mask(pts, 0.8)
            ol, ox0, oy0 = poly_mask(pts, 2.6)
            cv.blend(oy0, ox0, np.clip(ol * 1.6, 0, 1), OUTLINE)
            grad = np.linspace(1.15, 0.75, pm.shape[1])[None, :, None] * col
            cv.blend(py0, px0, pm, np.broadcast_to(grad, pm.shape + (3,)))
            g = noise(64, 1.2, rng, aniso=(1.0, 0.1))[:pm.shape[0] % 64 or 1, :1]
            del g
        for yy in (30, h - 26):
            cv.blend(yy + 3, 0, np.ones((7, w), np.float32), NIGHT, 0.35)
            cv.blend(yy, 0, np.ones((7, w), np.float32), palette["fence"] * 0.85)
            cv.blend(yy, 0, np.ones((2, w), np.float32), palette["fence"] * 1.15)
            cv.blend(yy - 1, 0, np.ones((1, w), np.float32), OUTLINE, 0.9)
            cv.blend(yy + 7, 0, np.ones((1, w), np.float32), OUTLINE, 0.9)
        return cv.a
    raise ValueError(kind)


def _frame(h: int, w: int, t: float) -> np.ndarray:
    m = np.zeros((h, w), np.float32)
    k = int(math.ceil(t))
    m[:k, :] = 1
    m[-k:, :] = 1
    m[:, :k] = 1
    m[:, -k:] = 1
    return m


def _face_finish(cv: Canvas, kind: str, palette: dict) -> np.ndarray:
    h, w = cv.h, cv.w
    # Corniche (haut) : moulure claire.
    trim = palette["trim_" + kind]
    cv.blend(0, 0, np.ones((8, w), np.float32), trim)
    cv.blend(0, 0, np.ones((2, w), np.float32), np.minimum(trim * 1.3, 255))
    cv.blend(8, 0, np.ones((3, w), np.float32), NIGHT * 0.6 + trim * 0.2, 0.7)
    # Soubassement (bas) : pierres sèches / planche de pied.
    sb = palette["base_" + kind]
    cv.blend(h - 12, 0, np.ones((12, w), np.float32), sb)
    for x in range(0, w, 22):
        cv.blend(h - 12, x, np.ones((12, 2), np.float32), sb * 0.6)
    cv.blend(h - 12, 0, np.ones((2, w), np.float32), np.minimum(sb * 1.3, 255))
    # Occlusion bleu nuit au pied.
    g = np.linspace(0, 1, 14)[:, None] ** 1.5 * np.ones((1, w))
    cv.blend(h - 14, 0, g.astype(np.float32), NIGHT * 0.7, 0.55)
    return cv.a


def _window_face(kind: str, rng, variant: int, palette: dict) -> np.ndarray:
    """Face avec fenêtre éclairée de l'intérieur (lumière chaude)."""
    a = _wall_face(kind, rng, 0, palette)
    cv = Canvas(FH, FW, wrap=False)
    cv.a = a
    adobe = kind == "adobe"
    wx, wy, ww, wh = 36, 18, 56, 58
    if adobe:
        wx, wy, ww, wh = 40, 20, 48, 56
    # Embrasure (ombre portée bleu nuit vers le bas-droite).
    cv.blend(wy + 4, wx + 5, np.ones((wh, ww), np.float32), NIGHT, 0.5)
    # Volets (bois).
    if not adobe:
        shc = palette["shutter"] * rng.uniform(0.95, 1.05)
        for sx in (wx - 16, wx + ww + 2):
            cv.blend(wy, sx, np.ones((wh, 14), np.float32), shc)
            for yy in range(wy + 4, wy + wh - 2, 6):
                cv.blend(yy, sx + 2, np.ones((2, 10), np.float32), shc * 0.6)
                cv.blend(yy - 1, sx + 2, np.ones((1, 10), np.float32), np.minimum(shc * 1.3, 255), 0.7)
            cv.blend(wy, sx, _frame(wh, 14, 1.5), OUTLINE, 0.95)
    # Cadre.
    frame_col = palette["frame"]
    cv.blend(wy - 4, wx - 4, np.ones((wh + 8, ww + 8), np.float32), frame_col)
    cv.blend(wy - 4, wx - 4, np.ones((3, ww + 8), np.float32), np.minimum(frame_col * 1.3, 255))
    # Vitre : intérieur chaud éclairé (bas plus lumineux), reflet du couchant en haut.
    yy = np.linspace(0, 1, wh)[:, None]
    xx = np.linspace(0, 1, ww)[None, :]
    glow = np.exp(-((xx - 0.5) ** 2 / 0.12 + (yy - 0.62) ** 2 / 0.2))
    warm = C(255, 196, 96)[None, None] * (0.55 + 0.5 * glow[..., None]) + C(40, 10, -20) * (1 - glow[..., None])
    refl = np.clip(1 - (xx * 0.9 + yy * 1.4), 0, 1)[..., None]
    pane = warm * (1 - 0.5 * refl) + C(255, 150, 120) * 0.5 * refl
    if variant == 1:
        # Rideaux rouges tirés sur les côtés.
        cur = (np.abs(xx - 0.5) > 0.32)[..., None] * np.ones_like(yy)[..., None]
        pane = pane * (1 - cur * 0.85) + C(170, 40, 46) * cur * 0.85 * (0.8 + 0.3 * np.sin(xx * 60)[..., None])
    if variant == 2:
        # Silhouette sombre (étagères / bouteilles) contre la lumière.
        for k in range(5):
            bx = int(6 + k * 10)
            pane[int(wh * 0.55) - (8 + (k % 3) * 3):int(wh * 0.55), bx:bx + 5] *= 0.35
        pane[int(wh * 0.55):int(wh * 0.55) + 3] *= 0.4
    cv.blend(wy, wx, np.ones((wh, ww), np.float32), np.clip(pane, 0, 255))
    # Croisillons.
    mul = frame_col * 0.8
    cv.blend(wy, wx + ww // 2 - 2, np.ones((wh, 4), np.float32), mul)
    cv.blend(wy + wh // 2 - 2, wx, np.ones((4, ww), np.float32), mul)
    # Reflet diagonal.
    mk, ox, oy = seg_mask(wx + 6, wy + wh - 10, wx + ww * 0.5, wy + 6, 3.0)
    cv.blend(oy, ox, mk, C(255, 240, 210), 0.45)
    cv.blend(wy - 4, wx - 4, _frame(wh + 8, ww + 8, 2.0), OUTLINE, 0.95)
    cv.blend(wy, wx, _frame(wh, ww, 1.0), OUTLINE, 0.7)
    # Appui de fenêtre.
    cv.blend(wy + wh + 4, wx - 8, np.ones((6, ww + 16), np.float32), frame_col * 1.1)
    cv.blend(wy + wh + 4, wx - 8, np.ones((2, ww + 16), np.float32), np.minimum(frame_col * 1.4, 255))
    cv.blend(wy + wh + 4, wx - 8, _frame(6, ww + 16, 1.2), OUTLINE, 0.9)
    cv.blend(wy + wh + 10, wx - 6, np.ones((4, ww + 16), np.float32), NIGHT, 0.4)
    return cv.a


INTERIOR = {
    # papier peint (fond, motif), lambris
    "int_red": (C(120, 36, 44), C(176, 70, 66), C(104, 62, 40)),
    "int_green": (C(46, 84, 70), C(96, 136, 104), C(96, 60, 38)),
    "int_plank": (None, None, C(122, 84, 56)),
    "int_cream": (C(214, 190, 150), C(236, 214, 170), C(132, 94, 60)),
    "int_purple": (C(78, 52, 96), C(130, 96, 140), C(92, 58, 42)),
}


def _interior_face(kind: str, rng, variant: int) -> np.ndarray:
    paper, motif, wains = INTERIOR[kind]
    w, h = FW, FH
    split = 56
    if paper is None:
        img = np.zeros((h, w, 3), np.float32)
        top = np.transpose(_clapboard(rng, wains * 1.05, h, w, board=16), (1, 0, 2))  # planches verticales
        img[:] = top[:h, :w]
        cv = Canvas(h, w, img, wrap=False)
    else:
        t = noise(256, 2.0, rng)[:h, :w]
        img = ramp(t, [(0, paper * 0.9), (1, np.minimum(paper * 1.08, 255))])
        cv = Canvas(h, w, img, wrap=False)
        # Motif damassé : losanges/fleurons alignés (période 32 px => tuilable).
        for yy in range(6, split - 4, 16):
            for xx in range((yy // 16) % 2 * 16, w + 16, 32):
                m, R = ellipse_mask(3.2, 5.0)
                cv.blend(yy - R, xx - R, m, motif, 0.75)
                m, R = ellipse_mask(1.2, 1.2)
                cv.blend(yy - R - 5, xx - R, m, motif, 0.75)
                cv.blend(yy - R + 5, xx - R, m, motif, 0.75)
        # Bandes verticales fines.
        for xx in range(0, w, 16):
            cv.blend(0, xx, np.ones((split, 1), np.float32), paper * 0.82, 0.6)
    # Lambris : panneaux moulurés.
    cv.blend(split, 0, np.ones((h - split, w), np.float32), wains)
    for px in (6, 70):
        r = (split + 8, px, h - split - 22, 52)
        cv.blend(r[0], r[1], np.ones((r[2], r[3]), np.float32), wains * 0.82)
        cv.blend(r[0], r[1], np.ones((2, r[3]), np.float32), wains * 0.6)
        cv.blend(r[0], r[1], np.ones((r[2], 2), np.float32), wains * 0.6)
        cv.blend(r[0] + r[2] - 2, r[1], np.ones((2, r[3]), np.float32), np.minimum(wains * 1.35, 255))
        cv.blend(r[0], r[1] + r[3] - 2, np.ones((r[2], 2), np.float32), np.minimum(wains * 1.2, 255))
    # Cimaise.
    cv.blend(split - 2, 0, np.ones((6, w), np.float32), wains * 1.25)
    cv.blend(split - 2, 0, np.ones((2, w), np.float32), np.minimum(wains * 1.6, 255))
    cv.blend(split + 4, 0, np.ones((2, w), np.float32), OUTLINE, 0.7)
    # Plinthe sombre.
    cv.blend(h - 12, 0, np.ones((12, w), np.float32), wains * 0.55)
    cv.blend(h - 12, 0, np.ones((2, w), np.float32), np.minimum(wains * 1.1, 255))
    # Corniche haute.
    cv.blend(0, 0, np.ones((6, w), np.float32), wains * 0.9)
    cv.blend(6, 0, np.ones((3, w), np.float32), NIGHT * 0.5, 0.5)
    if variant == 1 and paper is not None:
        # Cadre accroché (tableau / miroir).
        cv.blend(14 + 3, 44 + 3, np.ones((26, 40), np.float32), NIGHT, 0.4)
        cv.blend(14, 44, np.ones((26, 40), np.float32), C(176, 132, 60))
        cv.blend(18, 48, np.ones((18, 32), np.float32), C(92, 112, 120))
        cv.blend(18, 48, np.ones((8, 32), np.float32), C(230, 150, 100), 0.6)
        cv.blend(14, 44, _frame(26, 40, 1.5), OUTLINE)
    if variant == 2 and paper is not None:
        # Papier peint décollé.
        pm, px0, py0 = poly_mask([(0, 0), (22, 2), (18, 16), (6, 22)], 1.0)
        cv.blend(10 + py0, 80 + px0, pm, paper * 0.6)
        mk, ox, oy = seg_mask(80, 10, 100, 12, 2)
        cv.blend(oy, ox, mk, np.minimum(paper * 1.3, 255))
    g = np.linspace(0, 1, 14)[:, None] ** 1.5 * np.ones((1, w))
    cv.blend(h - 14, 0, g.astype(np.float32), NIGHT * 0.6, 0.6)
    fine_grain(cv, rng, 3.0)
    return cv.a


def _cap(kind: str, rng) -> np.ndarray:
    n = 128
    if kind == "wood":
        img = _clapboard(rng, C(112, 76, 56), n, n, board=16)
        cv = Canvas(n, n, img)
    elif kind == "adobe":
        t = noise(n, 2.2, rng)
        img = ramp(t, [(0, C(170, 112, 80)), (1, C(206, 146, 104))])
        cv = Canvas(n, n, img)
        strokes(cv, 300, rng, lambda y, x: np.clip(img[y, x] * rng.uniform(0.9, 1.1), 0, 255), opacity=0.3)
    elif kind == "rock":
        t = noise(n, 1.9, rng)
        img = ramp(t, [(0, C(40, 34, 48)), (0.6, C(66, 54, 60)), (1, C(92, 78, 76))])
        cv = Canvas(n, n, img)
        for _ in range(16):
            pebble(cv, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(4, 10), rng, C(84, 72, 74), shadow_len=0.6)
    elif kind == "fence":
        img = _clapboard(rng, C(124, 92, 66), n, n, board=16)
        cv = Canvas(n, n, img)
    elif kind == "plaster":
        t = noise(n, 2.2, rng)
        img = ramp(t, [(0, C(98, 64, 48)), (1, C(122, 84, 60))])
        cv = Canvas(n, n, img)
    else:
        raise ValueError(kind)
    fine_grain(cv, rng, 4.0)
    return cv.a


PALETTE = {
    "wood": C(172, 142, 112), "adobe": C(224, 162, 112), "fence": C(150, 112, 78),
    "trim_wood": C(204, 178, 140), "base_wood": C(96, 74, 64),
    "trim_adobe": C(240, 196, 150), "base_adobe": C(150, 98, 70),
    "trim_rock": C(84, 70, 70), "base_rock": C(54, 44, 52),
    "shutter": C(76, 110, 112), "frame": C(196, 168, 128),
}


def make_walls(out_png: str, out_json: str) -> None:
    """Atlas des murs (1024 x 1024) : faces 128 x 104 (4 variantes unies + 4 fenêtres), dessus 128 x 128."""
    W = 1024
    atlas = np.zeros((W, W, 4), np.float32)
    regions: dict[str, list[list[int]]] = {}
    rng = np.random.default_rng(42)

    def put(name: str, arr: np.ndarray, x: int, y: int) -> None:
        h, w = arr.shape[:2]
        atlas[y:y + h, x:x + w] = arr
        regions.setdefault(name, []).append([x, y, w, h])

    # Rangées de 104 px : façades avec fenêtres (8 cellules), puis 2 matières par rangée (4 + 4).
    layout_rows = [[("wood", True)], [("adobe", True)], [("int_red", False), ("int_green", False)],
                   [("int_plank", False), ("int_cream", False)], [("int_purple", False), ("rock", False)],
                   [("fence", False)]]
    y = 0
    for row_kinds in layout_rows:
        x0 = 0
        for kind, windows in row_kinds:
            for v in range(4):
                put("face_" + kind, _wall_face(kind, rng, v, PALETTE), x0 + v * FW, y)
            x0 += 4 * FW
            if windows:
                for v in range(4):
                    put("window_" + kind, _window_face(kind, rng, v % 3, PALETTE), x0 + v * FW, y)
                x0 += 4 * FW
        y += FH
    # Dessus de murs (128 x 128, tuilables).
    uy = y
    for i, k in enumerate(["wood", "adobe", "rock", "fence", "plaster"]):
        put("cap_" + k, _cap(k, rng), i * 128, uy)
    # Utilitaires : pixel blanc, dégradés vertical / horizontal (opaque -> transparent).
    ux = 5 * 128 + 8
    atlas[uy:uy + 8, ux:ux + 8] = [255, 255, 255, 255]
    regions["white"] = [[ux + 2, uy + 2, 4, 4]]
    g = np.linspace(1.0, 0.0, 64)
    atlas[uy + 12:uy + 76, ux:ux + 8, :3] = 255
    atlas[uy + 12:uy + 76, ux:ux + 8, 3] = (g[:, None] ** 1.3) * 255
    regions["grad_v"] = [[ux + 2, uy + 13, 4, 62]]
    atlas[uy:uy + 8, ux + 16:ux + 80, :3] = 255
    atlas[uy:uy + 8, ux + 16:ux + 80, 3] = (g[None, :] ** 1.3) * 255
    regions["grad_h"] = [[ux + 17, uy + 2, 62, 4]]
    # Dégradés inversés (opaque en bas / à droite) et halo radial doux.
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
    # Métadonnées en GDScript (exportées avec le jeu, contrairement aux .json).
    with open(out_json, "w") as f:
        f.write("## Généré par art/blender/build_tiles.py : NE PAS ÉDITER.\n")
        f.write("## Régions (px) de assets/textures/walls.png ; 2 px par unité monde.\n")
        f.write("const REGIONS := %s\n" % json.dumps(regions))


# ============================================================================ toits (tuilables)

def make_roof(kind: str, seed: int, n: int = 256) -> Image.Image:
    """Matière de toit neutre (claire) teintée en jeu ; rangées horizontales (bas = égout)."""
    rng = np.random.default_rng(seed)
    if kind == "shingle":
        img = np.zeros((n, n, 3), np.float32)
        row = 20
        g = noise(n, 1.5, rng, aniso=(1.0, 0.15))
        for r in range(n // row + 1):
            y0 = r * row
            off = (r % 2) * 13 + int(rng.integers(0, 6))
            x = -off
            while x < n:
                wd = int(rng.integers(18, 30))
                col = C(214, 200, 186) * rng.uniform(0.82, 1.08)
                xs = np.arange(x, x + wd) % n
                ys = np.arange(y0, min(y0 + row, n))
                if len(ys) == 0:
                    break
                blk = np.ones((len(ys), len(xs), 3), np.float32) * col
                blk *= (0.9 + 0.2 * g[np.ix_(ys, xs)])[..., None]
                prof = np.linspace(1.12, 0.86, len(ys))[:, None, None]
                blk *= prof
                blk[-3:] = blk[-3:] * 0.45 + NIGHT * 0.35
                blk[:, :1] *= 0.55
                img[np.ix_(ys, xs)] = blk
                x += wd
        cv = Canvas(n, n, img)
        for _ in range(14):
            # Bardeaux manquants / mousse sèche.
            m, R = ellipse_mask(rng.uniform(6, 12), rng.uniform(4, 7), soft=2)
            cv.blend(int(rng.uniform(0, n)) - R, int(rng.uniform(0, n)) - R, m, C(120, 110, 104), 0.35)
        fine_grain(cv, rng, 4.0)
        return cv.image().convert("RGB")
    if kind == "tin":
        xx = np.arange(n, dtype=np.float32)
        wave = np.sin(xx / n * 2 * math.pi * 16)
        prof = 0.9 + 0.16 * wave + 0.1 * np.clip(np.sin(xx / n * 2 * math.pi * 16 + 0.8), 0.8, 1) * 5 - 0.4
        img = np.ones((n, n, 3), np.float32) * C(206, 206, 212) * prof[None, :, None]
        cv = Canvas(n, n, np.clip(img, 0, 255))
        rust = noise(n, 2.3, rng)
        r = np.clip((rust - 0.6) * 3.0, 0, 1)[..., None]
        cv.a[..., :3] = cv.a[..., :3] * (1 - r * 0.6) + C(176, 92, 52) * r * 0.6
        # Joints de tôle (horizontaux) + rivets.
        for y in (0, n // 2):
            cv.blend(y, 0, np.ones((3, n), np.float32), NIGHT * 0.8, 0.6)
            cv.blend(y + 3, 0, np.ones((1, n), np.float32), C(250, 250, 255), 0.6)
            for x in range(8, n, 32):
                m, R = ellipse_mask(1.6, 1.6)
                cv.blend(y + 6 - R, x - R, m, C(70, 70, 86))
        for _ in range(30):
            x, y = rng.uniform(0, n), rng.uniform(0, n)
            mk, ox, oy = seg_mask(x, y, x + rng.uniform(-2, 2), y + rng.uniform(10, 40), 2.0, 0.5)
            cv.blend(oy, ox, mk, C(150, 80, 50), 0.4)
        fine_grain(cv, rng, 3.0)
        return cv.image().convert("RGB")
    if kind == "flat":
        t = 0.6 * noise(n, 2.5, rng) + 0.4 * noise(n, 1.7, rng)
        img = ramp(t, [(0, C(196, 170, 150)), (1, C(236, 216, 196))])
        cv = Canvas(n, n, img)
        strokes(cv, 900, rng, lambda y, x: np.clip(img[y, x] * rng.uniform(0.9, 1.08), 0, 255),
                length=(10, 26), width=(4, 8), opacity=0.3)
        for _ in range(5):
            m, R = ellipse_mask(rng.uniform(14, 28), rng.uniform(8, 16), rng.uniform(0, 3), soft=1.5)
            cv.blend(int(rng.uniform(0, n)) - R, int(rng.uniform(0, n)) - R, m, C(150, 136, 130), 0.4)
        for _ in range(4):
            crack(cv, rng.uniform(0, n), rng.uniform(0, n), 30, rng, C(140, 120, 110), 1.2)
        fine_grain(cv, rng, 3.0)
        return cv.image().convert("RGB")
    raise ValueError(kind)


# ============================================================================ décalques plats

def make_decals(out_dir: str) -> dict[str, str]:
    """Décalques posés au sol (RGBA, non tuilables sauf ornière). Renvoie {nom: chemin}."""
    os.makedirs(out_dir, exist_ok=True)
    rng = np.random.default_rng(7)
    out: dict[str, str] = {}

    def save(name: str, cv: Canvas) -> None:
        p = os.path.join(out_dir, name + ".png")
        cv.image().save(p)
        out[name] = p

    # Ornière de roues (tuilable horizontalement) : 256 x 40 px.
    cv = Canvas(40, 256, C(120, 80, 50), alpha=0.0)
    cv.wrap = True
    yy = np.arange(40, dtype=np.float32)[:, None]
    for track in (12, 28):
        xs = np.arange(256, dtype=np.float32)
        wob = np.sin(xs / 256 * 2 * math.pi * 2) * 1.5
        d = np.abs(yy - track - wob[None, :])
        dark = np.clip(1.0 - d / 4.5, 0, 1) * 0.42
        lip = np.clip(1.0 - np.abs(yy - (track - 5) - wob[None, :]) / 1.5, 0, 1) * 0.35
        lip2 = np.clip(1.0 - np.abs(yy - (track + 5) - wob[None, :]) / 2.0, 0, 1) * 0.25
        a = cv.a
        for m, col in ((dark, C(126, 82, 54)), (lip, C(252, 220, 166)), (lip2, C(110, 72, 60))):
            al = m[..., None]
            da = a[..., 3:4] / 255
            oa = al + da * (1 - al)
            a[..., :3] = (col * al + a[..., :3] * da * (1 - al)) / np.maximum(oa, 1e-6)
            a[..., 3:4] = oa * 255
    save("rut", cv)
    # Touffes d'herbe (3), cailloux (3), fissures (2), traces de sabots, tache sombre.
    for i in range(3):
        cv = Canvas(56, 64, C(0, 0, 0), alpha=0.0, wrap=False)
        for _k in range(2 + i):
            grass_tuft(cv, 32 + rng.uniform(-12, 12), 46 + rng.uniform(-6, 4), rng.uniform(12, 20), rng)
        save("grass_%d" % i, cv)
    for i in range(3):
        cv = Canvas(48, 64, C(0, 0, 0), alpha=0.0, wrap=False)
        for _k in range(3 + i * 2):
            pebble(cv, 32 + rng.uniform(-20, 18), 24 + rng.uniform(-12, 10), rng.uniform(2.5, 6.5), rng,
                   C(204, 170, 148) if rng.random() < 0.6 else C(170, 136, 124))
        save("pebbles_%d" % i, cv)
    for i in range(2):
        cv = Canvas(96, 96, C(0, 0, 0), alpha=0.0, wrap=False)
        crack(cv, 48, 48, 60, rng, C(120, 72, 50), 2.2)
        save("crack_%d" % i, cv)
    cv = Canvas(64, 96, C(0, 0, 0), alpha=0.0, wrap=False)
    for k in range(5):
        x, y = 12 + k * 17, 20 + (k % 2) * 22
        m, R = ellipse_mask(5, 6)
        cv.blend(y - R, x - R, m, C(150, 98, 64), 0.6)
        m, R = ellipse_mask(3, 3.6)
        cv.blend(y - R + 1, x - R, m, C(214, 162, 108), 0.7)
    save("hoofprints", cv)
    cv = Canvas(64, 96, C(0, 0, 0), alpha=0.0, wrap=False)
    m, R = ellipse_mask(42, 24, 0.1, soft=14)
    cv.blend(32 - R, 48 - R, m[:, :], C(70, 44, 36), 0.45)
    save("stain", cv)
    # Tapis du saloon (rouge à motifs).
    cv = Canvas(120, 200, C(0, 0, 0), alpha=0.0, wrap=False)
    cv.blend(4 + 6, 4 + 8, np.ones((108, 188), np.float32), NIGHT, 0.4)
    cv.blend(4, 4, np.ones((108, 188), np.float32), C(150, 36, 40))
    cv.blend(12, 12, np.ones((92, 172), np.float32), C(196, 150, 84))
    cv.blend(16, 16, np.ones((84, 164), np.float32), C(126, 30, 38))
    for k in range(5):
        pm, px0, py0 = poly_mask([(0, -18), (16, 0), (0, 18), (-16, 0)], 0.8)
        cv.blend(58 + py0, 40 + k * 30 + px0, pm, C(214, 172, 96), 0.9)
        pm2, px1, py1 = poly_mask([(0, -9), (8, 0), (0, 9), (-8, 0)], 0.8)
        cv.blend(58 + py1, 40 + k * 30 + px1, pm2, C(70, 22, 30))
    g = noise(128, 1.0, rng)
    cv.a[:120, :128, :3] *= (0.92 + 0.12 * g[:120, :128, None])
    cv.blend(4, 4, _frame(108, 188, 1.5), OUTLINE, 0.8)
    for x in range(6, 194, 6):
        cv.blend(112, x, np.ones((6, 2), np.float32), C(220, 196, 140))
        cv.blend(0, x, np.ones((4, 2), np.float32), C(220, 196, 140))
    save("rug", cv)
    # Sciure / paille éparse (écurie, mine).
    cv = Canvas(64, 96, C(0, 0, 0), alpha=0.0, wrap=False)
    for _ in range(40):
        x, y = rng.uniform(8, 88), rng.uniform(8, 56)
        a = rng.uniform(0, math.pi)
        mk, ox, oy = seg_mask(x, y, x + math.cos(a) * 8, y + math.sin(a) * 8, 1.6)
        cv.blend(oy, ox, mk, C(236, 200, 110) if rng.random() < 0.6 else C(190, 150, 80), 0.9)
    save("straw", cv)
    # Ossements de bovin (désert).
    cv = Canvas(56, 80, C(0, 0, 0), alpha=0.0, wrap=False)
    for (x0, y0, x1, y1) in ((14, 36, 62, 30), (22, 22, 30, 44), (40, 20, 46, 42)):
        mk, ox, oy = seg_mask(x0 + 3, y0 + 3, x1 + 3, y1 + 3, 6)
        cv.blend(oy, ox, mk, NIGHT, 0.35)
        mk, ox, oy = seg_mask(x0, y0, x1, y1, 7)
        cv.blend(oy, ox, mk, OUTLINE)
        mk, ox, oy = seg_mask(x0, y0, x1, y1, 4.5)
        cv.blend(oy, ox, mk, C(240, 228, 206))
    save("bones", cv)
    return out


# ============================================================================ main

def main() -> None:
    gdir = os.path.join(TEX_DIR, "ground")
    os.makedirs(gdir, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)
    make_sand(11).save(os.path.join(gdir, "sand.png"), optimize=True)
    make_sand(23, variant_b=True).save(os.path.join(gdir, "sand_b.png"), optimize=True)
    make_planks(5).save(os.path.join(gdir, "planks.png"), optimize=True)
    make_mine(9).save(os.path.join(gdir, "mine.png"), optimize=True)
    make_macro(3).save(os.path.join(gdir, "macro.png"), optimize=True)
    make_walls(os.path.join(TEX_DIR, "walls.png"), os.path.join(TEX_DIR, "walls_meta.gd"))
    for k, s in (("shingle", 31), ("tin", 32), ("flat", 33)):
        os.makedirs(os.path.join(TEX_DIR, "roofs"), exist_ok=True)
        make_roof(k, s).save(os.path.join(TEX_DIR, "roofs", "%s.png" % k), optimize=True)
    make_decals(os.path.join(TMP, "decals"))
    # Grain de poussière (particules de la rue) : tache douce 32 px.
    yy, xx = np.mgrid[0:32, 0:32].astype(np.float32)
    d = np.hypot(xx - 15.5, yy - 15.5) / 16.0
    dust = np.zeros((32, 32, 4), np.float32)
    dust[..., :3] = 255
    dust[..., 3] = np.clip(1 - d, 0, 1) ** 2 * 255
    Image.fromarray(dust.astype(np.uint8), "RGBA").save(os.path.join(TEX_DIR, "dust.png"), optimize=True)
    print("TILES OK ->", TEX_DIR, TMP)


if __name__ == "__main__":
    main()
