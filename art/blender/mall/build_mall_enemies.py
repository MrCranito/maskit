"""Ennemis masqués du centre commercial (4 + boss) : modélisation 3D scriptée + rendu 3/4.

Même pipeline que le héros (art/blender/build_hero.py, rdm_common.py) : matériaux toon en
émission, contour Freestyle, caméra orthographique plongée de 48°, rendu 2x puis réduction.
Une seule vue 3/4 face (tournée vers la droite : EnemyVisual retourne le sprite à gauche).

Usage (depuis la racine du projet) :
    python3 art/blender/mall/build_mall_enemies.py            # tous
    python3 art/blender/mall/build_mall_enemies.py mall_guard # un seul

Sorties : assets/sprites/mall/enemies/<kind>.png (256 x 256, boss 512 x 512 ; 2 px par unité
monde) et scripts/biomes/mall/enemy_kinds.gd (const KINDS au format EnemyVisual.KINDS :
pieds, tête, yeux mesurés sur le rendu).
"""
from __future__ import annotations

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import rdm_common as C  # noqa: E402
import build_props as BP  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "mall", "enemies")
KINDS_GD = os.path.join(ROOT, "scripts", "biomes", "mall", "enemy_kinds.gd")
TMP = os.path.join(os.environ.get("RDM_TMP", "/tmp/rdm_mall"), "enemies")
PX_PER_WORLD = 2.0
WORLD_PER_BU = 36.0
SS = 2
ELEV = 48.0
FACING = 18.0          # rotation (degrés) : regard vers la droite de l'écran

PAL = {
    "navy": ("#2e3a5e", "#10142e", "#4a5a8a"),
    "navy_light": ("#46588a", "#1a2244", "#6a80b8"),
    "black": ("#2a2630", "#0e0c1a", "#4a4452"),
    "leather": ("#3b2a2a", "#161226", "#5e4236"),
    "boot": ("#2e2428", "#0e0c18", "#4e3e3e"),
    "mask": ("#f2ece2", "#9896b4", "#fffaf2"),
    "gold": ("#e8b040", "#7a4a2a", "#ffe08a"),
    "silver": ("#b8bccc", "#4a4e6a", "#f2f4ff"),
    "red": ("#c0262e", "#4e0e26", "#ee4a40"),
    "purple": ("#6a3a96", "#24123e", "#9a62c8"),
    "green": ("#4aa050", "#163a32", "#7ad070"),
    "orange": ("#e8782e", "#6a2e20", "#ffa860"),
    "yellow": ("#f0c840", "#7a5a30", "#fff08a"),
    "cream": ("#e8dcc2", "#8a8aa6", "#fff6e0"),
    "violet_coat": ("#4a3060", "#18102a", "#6e4a8a"),
    "grey": ("#6a6a78", "#24263a", "#9a9aac"),
    "suit": ("#3a3a46", "#14141f", "#5e5e70"),
    "shirt": ("#e8e4ee", "#8a88a6", "#ffffff"),
    "skin": ("#d8a888", "#7a5060", "#f8d0b0"),
    "mannequin": ("#ece4dc", "#9a90a8", "#fffaf2"),
    "pink": ("#e06aa0", "#6a2a5a", "#ff9ac8"),
    "teal": ("#3a9a9a", "#163a4a", "#6ad0c8"),
    "metal": ("#6a6e80", "#26283e", "#a8aec0"),
    "wood": ("#8a5a3a", "#3a2230", "#b07a50"),
}
EMIT = {"eye_cyan": ("#7af0ff", 1.8), "eye_red": ("#ff3a2a", 1.8), "eye_violet": ("#c070ff", 1.8),
        "eye_orange": ("#ffa040", 1.8), "torch": ("#fff0b0", 1.8), "lens": ("#5af0ff", 1.6)}


def M(key: str, rim: float = 0.3):
    if key in EMIT:
        c, s = EMIT[key]
        return C.toon("e_" + key, c, emit=s)
    b, s, l = PAL[key]
    return C.toon("e_" + key, b, s, l, rim=rim)


class Body:
    """Personnage statique : pièces enfants d'une racine (tournée vers la droite)."""

    def __init__(self) -> None:
        self.root = C.empty("root", (0, 0, 0))
        self.eyes: list[tuple[float, float, float]] = []
        self.head_top = 1.9

    def add(self, name, bm, mat, smooth=True):
        ob = C.mesh_obj(name, bm, mat, smooth=smooth)
        ob.parent = self.root
        return ob

    def box(self, name, size, loc, mat, rot=(0, 0, 0), bevel=0.02):
        return self.add(name, C.bm_xform(C.bm_box(*size, bevel=bevel, segs=1), loc=loc, rot=rot), mat, smooth=False)

    def cyl(self, name, r1, r2, depth, loc, mat, rot=(0, 0, 0), seg=12, scale=(1, 1, 1)):
        return self.add(name, C.bm_xform(C.bm_cyl(seg, r1, r2, depth), loc=loc, rot=rot, scale=scale), mat)

    def sphere(self, name, r, loc, mat, scale=(1, 1, 1), seg=14, rings=9):
        return self.add(name, C.bm_xform(C.bm_sphere(seg, rings, r), loc=loc, scale=scale), mat)

    def tube(self, name, pts, radii, mat, seg=10, flat=1.0):
        return self.add(name, C.bm_tube(pts, radii, seg=seg, flat=flat), mat)

    def limb(self, name, a, b, c, r0, r1, r2, mat):
        pts = C.bezier(a, (a[0] * 0.6 + b[0] * 0.4, a[1] * 0.6 + b[1] * 0.4, a[2] * 0.6 + b[2] * 0.4),
                       (b[0], b[1], b[2]), c, 6)
        radii = [r0 + (r2 - r0) * i / 5 + (r1 - (r0 + r2) / 2) * math.sin(math.pi * i / 5) for i in range(6)]
        return self.tube(name, pts, radii, mat, seg=10)


def humanoid(B: Body, k: float = 1.0, sh: float = 0.26, waist: float = 0.19, hip: float = 0.2, head: float = 1.38,
             cloth_top: str = "navy", cloth_leg: str = "navy", boots: str = "boot", arms=None, legs=None,
             skin_hands: str = "black", belly: float = 0.0) -> dict:
    """Corps héroïque (proportions du héros, ×k). Renvoie des repères (épaules, mains, tête)."""
    pz = 0.82 * k
    legs = legs or {"L": ((0.13, 0.02, 0.44), (0.17, 0.0, 0.07)), "R": ((-0.12, -0.04, 0.44), (-0.17, -0.02, 0.07))}
    for side, sx in (("L", 1), ("R", -1)):
        knee, ankle = legs[side]
        hipp = (0.11 * sx * k, 0, pz)
        kn = (knee[0] * k, knee[1] * k, knee[2] * k)
        an = (ankle[0] * k, ankle[1] * k, ankle[2] * k)
        B.limb("leg" + side, hipp, kn, an, 0.1 * k, 0.095 * k, 0.075 * k, M(cloth_leg))
        B.box("foot" + side, (0.15 * k, 0.27 * k, 0.11 * k), (an[0], an[1] - 0.06 * k, 0.055 * k), M(boots), bevel=0.03 * k)
        B.cyl("cuff" + side, 0.085 * k, 0.09 * k, 0.12 * k, (an[0], an[1], an[2] + 0.04 * k), M(boots))
    B.sphere("hips", 1.0, (0, 0, pz), M(cloth_leg), scale=(hip * k, 0.15 * k, 0.14 * k))
    secs = [C.ellipse(0, 0, pz + 0.02 * k, hip * 0.95 * k, 0.14 * k, 14),
            C.ellipse(0, -belly * 0.5 * k, pz + 0.18 * k, (waist + belly) * k, (0.14 + belly) * k, 14),
            C.ellipse(0, 0.0, pz + 0.36 * k, (sh * 0.88 + belly * 0.5) * k, (0.16 + belly * 0.6) * k, 14),
            C.ellipse(0, 0.01, pz + 0.5 * k, sh * k, 0.16 * k, 14),
            C.ellipse(0, 0.015, pz + 0.58 * k, 0.12 * k, 0.1 * k, 14)]
    B.add("torso", C.bm_loft(secs), M(cloth_top))
    neck = (0, 0.0, pz + 0.62 * k)
    B.cyl("neck", 0.07 * k, 0.08 * k, 0.12 * k, neck, M(cloth_top))
    hc = (0, -0.01 * k, pz + 0.62 * k + 0.2 * k * head)
    arms = arms or {"L": ((0.36, 0.0, 0.4), (0.38, -0.08, 0.15)), "R": ((-0.36, 0.02, 0.4), (-0.38, -0.08, 0.15))}
    out = {"head": hc, "head_r": 0.19 * k * head, "hands": {}, "pz": pz}
    for side, sx in (("L", 1), ("R", -1)):
        s = (sh * 0.95 * sx * k, 0.0, pz + 0.5 * k)
        el, hd = arms[side]
        e = (el[0] * k, el[1] * k, pz + el[2] * k)
        h = (hd[0] * k, hd[1] * k, pz + hd[2] * k)
        B.sphere("shoulder" + side, 0.1 * k, s, M(cloth_top), scale=(1.1, 1, 0.9))
        B.limb("arm" + side, s, e, h, 0.085 * k, 0.075 * k, 0.065 * k, M(cloth_top))
        B.sphere("hand" + side, 0.07 * k, h, M(skin_hands), scale=(0.9, 1.0, 1.1))
        out["hands"][side] = h
    return out


def mask_face(B: Body, hc, r, mat_key="mask", eye_mat="eye_cyan", elong=1.1, eye_dx=0.36, eye_z=0.12, slit=False):
    """Masque ovale posé sur la face (-Y) + orbites sombres ; mémorise la position des yeux."""
    bm = C.bm_sphere(18, 12, 1.0)
    for v in bm.verts:
        if v.co.y > 0:
            v.co.y *= 0.4
        if v.co.z < 0:
            v.co.x *= 1.0 + 0.35 * v.co.z
    C.bm_xform(bm, loc=(hc[0], hc[1] - r * 0.55, hc[2] - r * 0.05), scale=(r * 0.92, r * 0.62, r * 1.05 * elong))
    B.add("mask", bm, M(mat_key, rim=0.25))
    for sx in (-1, 1):
        ex, ez = hc[0] + sx * r * eye_dx, hc[2] + r * eye_z
        ey = hc[1] - r * 1.12
        sc = (r * 0.2, r * 0.08, r * (0.06 if slit else 0.13))
        B.sphere("orb%d" % sx, 1.0, (ex, ey + r * 0.03, ez), M("black"), scale=sc, seg=10, rings=6)
        B.sphere("eye%d" % sx, 1.0, (ex, ey - r * 0.01, ez), M(eye_mat), scale=(sc[0] * 0.55, sc[1], sc[2] * 0.55), seg=8, rings=5)
        B.eyes.append((ex, ey - r * 0.04, ez))


# ----------------------------------------------------------------------------- personnages

def make_guard(B: Body) -> dict:
    """Vigile masqué : uniforme marine, casquette, masque blanc à visière, matraque + lampe."""
    o = humanoid(B, 1.1, sh=0.29, waist=0.21, cloth_top="navy", cloth_leg="navy",
                 arms={"L": ((0.38, -0.12, 0.3), (0.3, -0.32, 0.25)), "R": ((-0.38, 0.0, 0.32), (-0.36, -0.1, 0.06))})
    hc, r = o["head"], o["head_r"]
    B.sphere("headb", r, hc, M("skin"), scale=(0.95, 0.95, 1.05))
    mask_face(B, hc, r, "mask", "eye_cyan", slit=True)
    B.box("visor", (r * 1.5, r * 0.25, r * 0.22), (hc[0], hc[1] - r * 0.95, hc[2] + r * 0.12), M("black"))
    B.sphere("cap", r * 1.06, (hc[0], hc[1] + 0.01, hc[2] + r * 0.32), M("navy"), scale=(1.0, 1.0, 0.72))
    B.box("brim", (r * 1.4, r * 0.8, 0.03), (hc[0], hc[1] - r * 0.85, hc[2] + r * 0.42), M("black"), rot=(0.25, 0, 0))
    B.sphere("capbadge", 0.035, (hc[0], hc[1] - r * 1.0, hc[2] + r * 0.66), M("gold"), scale=(1, 0.4, 1))
    pz = o["pz"]
    B.cyl("belt", 0.235, 0.235, 0.07, (0, 0, pz + 0.05), M("black"), scale=(1, 0.75, 1))
    B.box("badge", (0.07, 0.02, 0.09), (0.1, -0.17 * 1.1, pz + 0.42 * 1.1), M("gold"))
    B.box("pocketL", (0.1, 0.02, 0.08), (-0.1, -0.165 * 1.1, pz + 0.38 * 1.1), M("navy_light"))
    for sx in (-1, 1):
        B.box("epaulet%d" % sx, (0.14, 0.12, 0.03), (sx * 0.27, 0.0, pz + 0.58 * 1.1), M("navy_light"))
    B.box("radio", (0.06, 0.04, 0.1), (-0.2, -0.12 * 1.1, pz + 0.48 * 1.1), M("black"))
    hl = o["hands"]["L"]
    B.tube("baton", [(hl[0], hl[1] + 0.05, hl[2] - 0.05), (hl[0] + 0.06, hl[1] - 0.25, hl[2] + 0.35)], [0.035, 0.03], M("black"))
    hr = o["hands"]["R"]
    B.cyl("torch", 0.04, 0.05, 0.25, (hr[0], hr[1] - 0.08, hr[2] - 0.02), M("metal"), rot=(1.4, 0, 0))
    B.sphere("torchl", 0.045, (hr[0], hr[1] - 0.22, hr[2] - 0.0), M("torch"))
    return o


def make_clown(B: Body) -> dict:
    """Pilleur au masque de clown : sweat à capuche violet, cheveux orange et verts, sac de butin,
    pied-de-biche ; silhouette fine penchée en avant (rapide)."""
    o = humanoid(B, 1.04, sh=0.24, waist=0.17, hip=0.18, cloth_top="purple", cloth_leg="green",
                 arms={"L": ((0.34, -0.15, 0.25), (0.3, -0.38, 0.32)), "R": ((-0.34, 0.12, 0.25), (-0.3, 0.1, 0.0))},
                 legs={"L": ((0.16, -0.12, 0.42), (0.2, -0.16, 0.07)), "R": ((-0.12, 0.08, 0.42), (-0.16, 0.14, 0.07))},
                 skin_hands="mask")
    hc, r = o["head"], o["head_r"]
    B.sphere("headb", r, hc, M("purple"), scale=(1.0, 1.0, 1.05))
    mask_face(B, hc, r, "mask", "eye_red", elong=1.05)
    B.sphere("nose", r * 0.24, (hc[0], hc[1] - r * 1.25, hc[2] - r * 0.12), M("red"))
    smile = [(hc[0] + r * 0.5 * math.cos(a), hc[1] - r * 1.08 + 0.02 * abs(math.cos(a)), hc[2] - r * 0.45 - r * 0.25 * math.sin(a))
             for a in [math.pi * (0.1 + 0.8 * i / 8) for i in range(9)]]
    B.tube("smile", smile, [r * 0.06] * 9, M("red"), seg=6)
    for sx in (-1, 1):
        B.box("tri%d" % sx, (r * 0.08, 0.01, r * 0.3), (hc[0] + sx * r * 0.36, hc[1] - r * 1.1, hc[2] + r * 0.35), M("violet_coat"))
        for k in range(3):
            B.sphere("hair%d%d" % (sx, k), r * 0.32, (hc[0] + sx * r * (0.8 + 0.15 * k), hc[1] + r * 0.1, hc[2] + r * (0.1 + 0.25 * k)),
                     M("orange" if k % 2 == 0 else "green"))
    hood = C.bm_sphere(14, 10, 1.0)
    for v in hood.verts:
        if v.co.y < -0.2 and v.co.z < 0.6:
            v.co.y = -0.2 + (v.co.y + 0.2) * 0.2
    C.bm_xform(hood, loc=(hc[0], hc[1] + r * 0.2, hc[2] + r * 0.05), scale=(r * 1.12, r * 1.1, r * 1.12))
    B.add("hood", hood, M("purple"))
    pz = o["pz"]
    B.box("pocket", (0.26, 0.04, 0.12), (0, -0.16, pz + 0.24), M("violet_coat"))
    hl, hr = o["hands"]["L"], o["hands"]["R"]
    B.tube("crowbar", [(hl[0], hl[1], hl[2] - 0.15), (hl[0] + 0.02, hl[1] - 0.05, hl[2] + 0.4), (hl[0] + 0.1, hl[1] - 0.12, hl[2] + 0.45)],
           [0.025, 0.025, 0.02], M("red"))
    B.sphere("sack", 0.22, (hr[0] - 0.05, hr[1] + 0.12, hr[2] - 0.15), M("cream"), scale=(1.0, 0.9, 1.2))
    B.sphere("sackknot", 0.06, (hr[0], hr[1] + 0.05, hr[2] + 0.08), M("cream"))
    return o


def make_sniper(B: Body) -> dict:
    """Sniper des balcons : long manteau violet sombre, masque à gaz noir à lentilles cyan,
    fusil à lunette tenu en travers."""
    o = humanoid(B, 1.08, sh=0.25, waist=0.18, cloth_top="violet_coat", cloth_leg="black",
                 arms={"L": ((0.3, -0.25, 0.3), (0.16, -0.4, 0.4)), "R": ((-0.32, -0.12, 0.3), (-0.12, -0.36, 0.2))})
    hc, r = o["head"], o["head_r"]
    B.sphere("headb", r, hc, M("black"), scale=(1.0, 1.0, 1.05))
    mask_face(B, hc, r, "grey", "eye_cyan", elong=1.0)
    for sx in (-1, 1):
        B.cyl("lens%d" % sx, r * 0.24, r * 0.24, r * 0.15, (hc[0] + sx * r * 0.36, hc[1] - r * 1.05, hc[2] + r * 0.12), M("silver"), rot=(math.pi / 2, 0, 0))
    B.cyl("filter", r * 0.22, r * 0.26, r * 0.4, (hc[0], hc[1] - r * 1.15, hc[2] - r * 0.45), M("black"), rot=(math.pi / 2 - 0.4, 0, 0))
    B.cyl("hat", r * 0.95, r * 0.9, r * 0.3, (hc[0], hc[1] + r * 0.15, hc[2] + r * 0.85), M("black"))
    B.cyl("hatbrim", r * 1.2, r * 1.2, 0.02, (hc[0], hc[1] + r * 0.2, hc[2] + r * 0.7), M("black"))
    pz = o["pz"]
    coat = C.bm_loft([C.ellipse(0, 0.0, pz + 0.05, 0.23, 0.17, 14), C.ellipse(0, 0.02, pz - 0.25, 0.3, 0.22, 14),
                      C.ellipse(0, 0.04, pz - 0.5, 0.36, 0.26, 14)], cap_start=False, cap_end=False)
    B.add("coat", coat, M("violet_coat"))
    B.tube("scarf", [(0.0, -0.12 * 1.1, pz + 0.58 * 1.1), (0.12, -0.2, pz + 0.4 * 1.1), (0.18, -0.18 * 1.1, pz + 0.15 * 1.1)], [0.07, 0.06, 0.04], M("teal"), flat=0.4)
    hl, hr = o["hands"]["L"], o["hands"]["R"]
    a = Vector(hr) + Vector((-0.25, 0.1, -0.12))
    b = Vector(hl) + Vector((0.45, -0.25, 0.18))
    B.tube("rifle", [tuple(a), tuple(a.lerp(b, 0.5)), tuple(b)], [0.05, 0.035, 0.025], M("wood"))
    B.tube("barrel", [tuple(a.lerp(b, 0.45)), tuple(b + (b - a) * 0.25)], [0.022, 0.02], M("metal"))
    sc = a.lerp(b, 0.55) + Vector((0, 0, 0.07))
    B.cyl("scope", 0.035, 0.035, 0.28, tuple(sc), M("black"), rot=(0, math.pi / 2 - math.atan2(b.z - a.z, b.x - a.x), math.atan2(b.y - a.y, b.x - a.x)))
    return o


def make_mannequin(B: Body) -> dict:
    """Mannequin de vitrine animé : corps lisse blanc aux articulations rondes, robe de soirée
    déchirée, loup vénitien violet et or ; bras levés en griffes (embuscade)."""
    o = humanoid(B, 1.1, sh=0.24, waist=0.16, hip=0.19, cloth_top="mannequin", cloth_leg="mannequin", boots="mannequin",
                 arms={"L": ((0.42, -0.12, 0.55), (0.36, -0.3, 0.78)), "R": ((-0.4, -0.05, 0.52), (-0.3, -0.28, 0.72))},
                 skin_hands="mannequin")
    hc, r = o["head"], o["head_r"]
    B.sphere("headb", r, hc, M("mannequin"), scale=(0.9, 0.95, 1.12))
    pz = o["pz"]
    for (x, z) in ((0.11, 0.44), (-0.11, 0.44), (0.0, 0.62)):
        B.sphere("joint%.2f%.2f" % (x, z), 0.05, (x, -0.06, (z if z > 0.6 else z) * 1.02), M("grey"))
    for sx in (-1, 1):
        B.sphere("sh_j%d" % sx, 0.075, (sx * 0.23, 0.0, pz + 0.51), M("grey"))
    mask_face(B, hc, r * 0.98, "mannequin", "eye_violet", elong=1.12)
    # Loup vénitien (bandeau violet et or sur les yeux, pointes).
    lp = []
    for i in range(11):
        t = i / 10
        lp.append((hc[0] + (t - 0.5) * r * 1.9, hc[1] - r * 1.06 + 0.02 * abs(t - 0.5), hc[2] + r * (0.12 + 0.35 * (abs(t - 0.5) * 2) ** 2)))
    B.tube("loup", lp, [r * 0.16] * 11, M("purple"), seg=8, flat=0.45)
    B.tube("loupgold", [(p[0], p[1] - 0.01, p[2] + r * 0.17) for p in lp], [r * 0.04] * 11, M("gold"), seg=6)
    for sx in (-1, 1):
        B.tube("feather%d" % sx, C.bezier((hc[0] + sx * r * 0.9, hc[1] - r * 0.7, hc[2] + r * 0.5), (hc[0] + sx * r * 1.2, hc[1] - r * 0.6, hc[2] + r * 0.8),
                                           (hc[0] + sx * r * 1.45, hc[1] - r * 0.5, hc[2] + r * 1.05), (hc[0] + sx * r * 1.7, hc[1] - r * 0.3, hc[2] + r * 1.2), 6),
               [0.03, 0.05, 0.05, 0.04, 0.03, 0.005], M("pink"), seg=6, flat=0.35)
    dress = C.bm_loft([C.ellipse(0, 0.0, pz + 0.3, 0.19, 0.15, 16), C.ellipse(0, 0.01, pz, 0.24, 0.19, 16),
                       C.ellipse(0, 0.02, pz - 0.35, 0.33, 0.27, 16), C.ellipse(0, 0.03, pz - 0.55, 0.38, 0.3, 16)], cap_start=False, cap_end=False)
    for v in dress.verts:
        if v.co.z < pz - 0.5:
            v.co.z += 0.08 * math.sin(v.co.x * 25)
    B.add("dress", dress, M("red"))
    B.tube("sash", [(-0.18, -0.15 * 1.1, pz + 0.48 * 1.1), (0.0, -0.18 * 1.1, pz + 0.3 * 1.1), (0.2, -0.16 * 1.1, pz + 0.08 * 1.1)], [0.04, 0.04, 0.04], M("gold"), flat=0.4)
    return o


def make_director(B: Body) -> dict:
    """Le Directeur (boss) : colosse en costume rayé, cravate rouge, masque d'or souriant aux yeux
    orange, mallette d'acier massive en guise d'arme."""
    o = humanoid(B, 1.7, sh=0.36, waist=0.25, hip=0.24, head=1.0, cloth_top="suit", cloth_leg="suit", boots="black",
                 arms={"L": ((0.46, -0.08, 0.28), (0.44, -0.2, 0.02)), "R": ((-0.5, 0.0, 0.3), (-0.5, -0.12, 0.0))},
                 legs={"L": ((0.16, -0.02, 0.44), (0.22, -0.02, 0.07)), "R": ((-0.16, 0.02, 0.44), (-0.22, 0.02, 0.07))},
                 skin_hands="skin", belly=0.08)
    hc, r = o["head"], o["head_r"]
    B.sphere("headb", r, hc, M("skin"), scale=(1.0, 1.0, 1.05))
    mask_face(B, hc, r, "gold", "eye_orange", elong=1.08, slit=True)
    smile = [(hc[0] + r * 0.45 * math.cos(a), hc[1] - r * 1.1, hc[2] - r * 0.4 - r * 0.2 * math.sin(a))
             for a in [math.pi * (0.1 + 0.8 * i / 8) for i in range(9)]]
    B.tube("smile", smile, [r * 0.05] * 9, M("black"), seg=6)
    B.sphere("hair", r * 1.02, (hc[0], hc[1] + r * 0.15, hc[2] + r * 0.2), M("black"), scale=(1.0, 0.9, 0.85))
    k = 1.7
    pz = o["pz"]
    tie = [(0.0, -0.2 * k - 0.02, pz + 0.58 * k), (0.0, -0.24 * k, pz + 0.4 * k), (0.01, -0.25 * k, pz + 0.22 * k)]
    B.tube("shirt", [(0, -0.14 * k, pz + 0.6 * k), (0, -0.22 * k, pz + 0.4 * k), (0, -0.22 * k, pz + 0.24 * k)], [0.07 * k, 0.06 * k, 0.04 * k], M("shirt"), flat=0.35)
    B.tube("tie", tie, [0.035 * k, 0.045 * k, 0.03 * k], M("red"), flat=0.4)
    for sx in (-1, 1):
        B.tube("lapel%d" % sx, [(sx * 0.06 * k, -0.17 * k, pz + 0.58 * k), (sx * 0.13 * k, -0.22 * k, pz + 0.38 * k)], [0.03 * k, 0.04 * k], M("suit"), flat=0.3)
    B.box("pin", (0.05, 0.02, 0.05), (0.18 * k, -0.2 * k, pz + 0.48 * k), M("gold"))
    hr = o["hands"]["R"]
    B.box("case", (0.75, 0.25, 0.55), (hr[0] - 0.05, hr[1] - 0.05, hr[2] - 0.32), M("silver"), bevel=0.04)
    B.box("caseband", (0.77, 0.27, 0.06), (hr[0] - 0.05, hr[1] - 0.05, hr[2] - 0.2), M("metal"))
    B.box("latch", (0.1, 0.03, 0.06), (hr[0] - 0.05, hr[1] - 0.19, hr[2] - 0.1), M("gold"))
    hl = o["hands"]["L"]
    B.box("watch", (0.1, 0.12, 0.05), (hl[0], hl[1] + 0.02, hl[2] + 0.12), M("gold"))
    # Épaulettes massives (carrure de colosse).
    for sx in (-1, 1):
        B.sphere("pad%d" % sx, 0.2, (sx * 0.58, 0.0, pz + 0.86), M("suit"), scale=(1.2, 1.0, 0.75))
    return o


CHARS = {
    # kind : (constructeur, taille du cadre px, hauteur de visée BU, aura, débris, rayon d'ombre)
    "mall_guard": (make_guard, 256, 0.95, (0.35, 0.95, 1.0), ["navy", "mask", "gold"], 20.0),
    "mall_clown": (make_clown, 256, 0.9, (1.0, 0.3, 0.3), ["purple", "mask", "orange", "green"], 18.0),
    "mall_sniper": (make_sniper, 256, 0.95, (0.4, 0.95, 1.0), ["violet_coat", "grey", "teal"], 18.0),
    "mall_mannequin": (make_mannequin, 256, 1.0, (0.75, 0.42, 1.0), ["mannequin", "purple", "red", "gold"], 19.0),
    "mall_director": (make_director, 512, 1.65, (1.0, 0.6, 0.2), ["suit", "gold", "red", "shirt"], 44.0),
}


def hexc(key: str) -> str:
    b = PAL[key][0].lstrip("#")
    return "Color(%.3f, %.3f, %.3f)" % tuple(int(b[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def render(kind: str) -> dict:
    fn, frame, tz, aura, debris, shadow = CHARS[kind]
    C.reset_scene()
    C.setup_render((frame * SS, frame * SS), samples=4, outline_px=4.0 if frame == 256 else 6.0, inner_ratio=0.45)
    B = Body()
    o = fn(B)
    B.root.rotation_euler = (0, 0, math.radians(FACING))
    ortho = frame / (PX_PER_WORLD * WORLD_PER_BU)
    cam = C.ortho_camera(ELEV, ortho, target=(0, 0, tz), dist=30.0)
    bpy.context.view_layer.update()
    mw = B.root.matrix_world
    feet = C.world_to_px(cam, (0, 0, 0))
    hc = mw @ Vector(o["head"])
    top = C.world_to_px(cam, tuple(hc + Vector((0, 0, o["head_r"] * 1.6))))
    eyes = [C.world_to_px(cam, tuple(mw @ Vector(e))) for e in B.eyes]
    os.makedirs(TMP, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    big = os.path.join(TMP, kind + ".big.png")
    C.render_to(big)
    im = C.downscale(big, None, (frame, frame))
    im = BP._paint(im)
    out = os.path.join(OUT_DIR, kind + ".png")
    im.save(out, optimize=True)
    os.remove(big)
    f = (feet[0] / SS, feet[1] / SS)
    head_y = (top[1] / SS - f[1]) / PX_PER_WORLD
    info = {"frame": frame, "feet": [round(f[0], 1), round(f[1], 1)], "head": round(head_y - 6.0, 1),
            "eyes": [[round(e[0] / SS, 1), round(e[1] / SS, 1)] for e in eyes], "aura": aura, "debris": debris, "shadow": shadow}
    print("CHAR", kind, json.dumps(info), flush=True)
    with open(os.path.join(TMP, kind + ".json"), "w") as fp:
        json.dump(info, fp)
    return info


def write_kinds() -> None:
    lines = ["## Généré par art/blender/mall/build_mall_enemies.py : NE PAS ÉDITER.",
             "## Visuels des ennemis du centre commercial (format EnemyVisual.KINDS), chargés par BiomeRegistry.",
             "## Sprites rendus sous Blender (2 px par unité monde) : scale = 0.5.", "", "const KINDS := {"]
    for kind in CHARS:
        p = os.path.join(TMP, kind + ".json")
        if not os.path.exists(p):
            continue
        with open(p) as fp:
            i = json.load(fp)
        fr = i["frame"]
        e = i["eyes"]
        lines.append('\t&"%s": {' % kind)
        lines.append('\t\t"path": "res://assets/sprites/mall/enemies/%s.png",' % kind)
        lines.append('\t\t"svg_size": Vector2(%d, %d), "feet": Vector2(%.1f, %.1f), "scale": 0.5,' % (fr, fr, i["feet"][0], i["feet"][1]))
        lines.append('\t\t"head": Vector2(0, %.1f), "shadow": %.1f,' % (i["head"], i["shadow"]))
        lines.append('\t\t"eyes": [%s], "eye_r": %.1f,' % (", ".join("Vector2(%.1f, %.1f)" % (x, y) for x, y in e), 3.6 if fr == 256 else 5.0))
        lines.append('\t\t"aura": Color(%.2f, %.2f, %.2f),' % tuple(i["aura"]))
        lines.append('\t\t"debris": [%s],' % ", ".join(hexc(k) for k in i["debris"]))
        lines.append("\t},")
    lines.append("}")
    with open(KINDS_GD, "w") as fp:
        fp.write("\n".join(lines) + "\n")
    print("KINDS", KINDS_GD)


def main() -> None:
    only = sys.argv[1:]
    for kind in CHARS:
        if only and kind not in only:
            continue
        render(kind)
    write_kinds()


if __name__ == "__main__":
    main()
