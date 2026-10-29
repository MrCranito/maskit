"""Décors Far West en 3D « toon peint » (même pipeline et même angle que le héros) + atlas unique.

Usage (depuis la racine du projet ; ordre complet de régénération du décor) :
    python3 art/blender/build_tiles.py        # sols, murs, toits, décalques (numpy)
    python3 art/blender/build_buildings.py    # kit de façades (auvents, poteaux, bannières...)
    python3 art/blender/build_props.py        # décors + empaquetage de TOUT dans l'atlas
    python3 art/blender/build_props.py --only cactus,barrel   # re-rendre quelques décors puis empaqueter
    python3 art/blender/build_props.py --pack                  # empaqueter seulement
    python3 art/blender/build_props.py --keep --furniture      # reprendre l'atlas actuel + mobilier
                                                               # des gabarits d'aménagement
    python3 art/blender/build_props.py --landmarks [--only lm_loco]  # grands décors (rochers, train,
                                                               # éolienne, puits) → landmarks.png

Sorties : assets/sprites/far_west/atlas.png (+ atlas_meta.gd : rect, pieds en px d'atlas).
Échelle : 2 px par unité monde. 1 BU Blender projeté = 36 unités monde (comme le héros :
caméra orthographique plongée de 48°). Le point (0, 0, 0) de chaque pièce = point d'appui au sol.
Ombres portées : 2e rendu de la géométrie aplatie au sol (cisaillement : soleil couchant à
l'ouest, ombre vers l'est et un peu vers le bas), composée en bleu nuit translucide sous l'objet.
"""
from __future__ import annotations

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "far_west")
TMP = os.environ.get("RDM_TMP", "/tmp/rdm_decor")
PIECES = os.path.join(TMP, "pieces")

ELEV = 48.0
PX_PER_WORLD = 2.0
WORLD_PER_BU = 36.0
SS = 2
PX_PER_BU = PX_PER_WORLD * WORLD_PER_BU          # 72 px par BU (image finale)
SHADOW_RGBA = (40, 46, 104, 112)                 # bleu nuit, alpha ~0.44
SHEAR = Matrix(((1, 0, 0.62, 0), (0, 1, -0.22, 0), (0, 0, 0.0, 0.004), (0, 0, 0, 1)))

# ----------------------------------------------------------------------------- matériaux
PAL = {
    "wood": ("#b07a4c", "#5a3a3a", "#e0a868"),
    "wood_dark": ("#6e4630", "#2e1e2a", "#9a6440"),
    "wood_grey": ("#a89480", "#4e4658", "#d8c4a0"),
    "wood_red": ("#a8402e", "#4a1a2a", "#d8603e"),
    "plank_light": ("#c89a68", "#6a4a48", "#f0c48a"),
    "iron": ("#5a5c6e", "#22233a", "#9aa0b4"),
    "iron_dark": ("#3a3a48", "#16162a", "#6a6c80"),
    "brass": ("#d0a040", "#6a4a3a", "#ffe08a"),
    "rust": ("#a85a34", "#4a2430", "#d88050"),
    "cactus": ("#5f8f3e", "#22404a", "#9cc860"),
    "cactus_rib": ("#4a7432", "#1a3040", "#7aa84a"),
    "flower": ("#e85a7a", None, "#ffa0b0"),
    "hay": ("#dcb44c", "#7a6040", "#ffe08a"),
    "hay_dark": ("#b08a38", "#5a4434", "#e0b858"),
    "felt": ("#2e7a50", "#123040", "#4aa070"),
    "water": ("#4a90b8", "#1e3a6a", "#9ad0e8"),
    "stone": ("#9a8a80", "#3e3a52", "#c8b8a8"),
    "ore": ("#7a6a68", "#2a2638", "#a89490"),
    "gold": ("#f0c040", "#8a5a30", "#fff0a0"),
    "cream": ("#e8dcc2", "#8a8aa6", "#fff6e0"),
    "paper": ("#e6d2a6", "#8a7a7a", "#fff0cc"),
    "red": ("#b8282e", "#4e1028", "#e8483e"),
    "black": ("#2a2430", "#100e1c", "#4a4250"),
    "ivory": ("#f2ead8", "#9a96b0", "#ffffff"),
    "glass": ("#ffd890", None, None),
    "flame": ("#ffb040", None, None),
    "bottle_g": ("#3e8a4a", "#16303a", "#7ad08a"),
    "bottle_b": ("#8a4a2a", "#3a1e26", "#c8783e"),
    "cloth_red": ("#a8303a", "#4a1430", "#d8504a"),
    "cloth_cream": ("#e0d0b0", "#7e7890", "#fff4dc"),
    "bone": ("#ece0c8", "#8a8aa0", "#ffffff"),
    "tumble": ("#b08850", "#5a4038", "#e0b878"),
    "leather": ("#7a4a30", "#2e1a26", "#a86a40"),
    "green_paint": ("#4e7a6a", "#1e3440", "#7aa894"),
    "steel": ("#8890a0", "#3a3c54", "#d0d4e0"),
    "candle": ("#f4ead0", "#9a8a90", "#ffffff"),
    "mirror": ("#9ab8c8", "#4a5a7a", "#e4f4fa"),
    "sky": ("#e89060", "#7a4a6a", "#ffc890"),
    # Ville éparpillée (planche des cartes) : grès rouge, buissons, train.
    "rock_red": ("#a8482e", "#4a1e3a", "#d8683e"),
    "rock_orange": ("#bc5e36", "#52243c", "#e88450"),
    "rock_dark": ("#86382a", "#381834", "#b05238"),
    "rock_top": ("#d08452", "#6a3446", "#f4a86c"),
    "bush": ("#6e8a3c", "#24403e", "#a6c464"),
    "bush_dry": ("#9a8a4a", "#4a4040", "#c8b870"),
    "loco": ("#34343e", "#14141e", "#5a5a6a"),
    "red_paint": ("#b0362c", "#4a1428", "#e0583e"),
    "boxcar": ("#9a3a2e", "#42182a", "#c85a40"),
    "boxcar_b": ("#7a4a36", "#34202a", "#a86a48"),
    "tank_grey": ("#8a8c96", "#3a3c54", "#c4c8d4"),
    "coal": ("#26242c", "#0c0c16", "#4a4652"),
    "ballast": ("#8a7a70", "#3e3848", "#b4a494"),
}


def M(key: str, rim: float = 0.28):
    b, s, l = PAL[key]
    if key in ("glass", "flame"):
        return C.toon(key, b, emit=1.6 if key == "flame" else 1.25)
    return C.toon(key, b, s, l, rim=rim)


# ----------------------------------------------------------------------------- géométrie

class Builder:
    """Collecte les objets d'une pièce (pour le rendu et la passe d'ombre)."""

    def __init__(self) -> None:
        self.objs: list[bpy.types.Object] = []
        self.noshadow: set[str] = set()

    def add(self, name: str, bm: bmesh.types.BMesh, mat, sharp: float = 40.0, shadow: bool = True,
            outline: bool = True) -> bpy.types.Object:
        sharp_edges = []
        for e in bm.edges:
            if len(e.link_faces) == 2:
                try:
                    if e.calc_face_angle() > math.radians(sharp):
                        sharp_edges.append(e)
                except ValueError:
                    pass
        if sharp_edges:
            # Arêtes vives séparées : normales non interpolées (faces planes nettes).
            bmesh.ops.split_edges(bm, edges=sharp_edges)
        ob = C.mesh_obj(name, bm, mat, smooth=True, coll=None if outline else C.nofs_collection())
        self.objs.append(ob)
        if not shadow:
            self.noshadow.add(ob.name)
        return ob

    def box(self, name, size, loc, mat, rot=(0, 0, 0), bevel=0.0, **kw):
        bm = C.bm_box(*size, bevel=bevel, segs=1)
        C.bm_xform(bm, loc=loc, rot=rot)
        return self.add(name, bm, mat, **kw)

    def cyl(self, name, r1, r2, depth, loc, mat, rot=(0, 0, 0), seg=14, **kw):
        bm = C.bm_cyl(seg, r1, r2, depth)
        C.bm_xform(bm, loc=loc, rot=rot)
        return self.add(name, bm, mat, **kw)

    def sphere(self, name, r, loc, mat, scale=(1, 1, 1), seg=14, rings=9, **kw):
        bm = C.bm_sphere(seg, rings, r)
        C.bm_xform(bm, loc=loc, scale=scale)
        kw.setdefault("sharp", 80.0)
        return self.add(name, bm, mat, **kw)

    def tube(self, name, path, radii, mat, seg=8, flat=1.0, **kw):
        bm = C.bm_tube(path, radii, seg=seg, flat=flat)
        kw.setdefault("sharp", 80.0)
        return self.add(name, bm, mat, **kw)

    def torus(self, name, R, r, loc, mat, rot=(0, 0, 0), seg=20, rseg=6, **kw):
        bm = C.bm_torus(seg, rseg, R, r)
        C.bm_xform(bm, loc=loc, rot=rot)
        kw.setdefault("sharp", 80.0)
        return self.add(name, bm, mat, **kw)

    def plank_row(self, prefix, x0, x1, y, z0, z1, thick, mat, n, axis="x", gap=0.012, jitter=0.0, seed=0):
        """Rangée de planches (séparées : contour Freestyle entre chaque latte)."""
        import random
        rnd = random.Random(seed)
        span = (x1 - x0) / n
        for i in range(n):
            a = x0 + i * span
            jz = rnd.uniform(-jitter, jitter)
            if axis == "x":   # planches verticales côte à côte le long de x
                self.box("%s%d" % (prefix, i), (span - gap, thick, z1 - z0 + jz),
                         (a + span / 2, y, (z0 + z1 + jz) / 2), mat)
            else:             # planches horizontales empilées en z
                self.box("%s%d" % (prefix, i), (x1 - x0 + jz, thick, (z1 - z0) / n - gap),
                         ((x0 + x1) / 2, y, z0 + (i + 0.5) * (z1 - z0) / n), mat)


def wheel(B: Builder, name: str, R: float, loc, mat_rim, mat_spoke, axis="y", spokes=10, thick=0.07):
    rot = (math.pi / 2, 0, 0) if axis == "y" else (0, math.pi / 2, 0)
    B.torus(name + "_rim", R - thick * 0.6, thick, loc, mat_rim, rot=rot, seg=28, rseg=6)
    B.cyl(name + "_hub", 0.09 * R / 0.5, 0.09 * R / 0.5, thick * 2.6, loc, M("iron_dark"), rot=rot, seg=10)
    for k in range(spokes):
        a = 2 * math.pi * k / spokes
        if axis == "y":
            d = (math.cos(a), 0, math.sin(a))
        else:
            d = (0, math.cos(a), math.sin(a))
        p0 = tuple(loc[i] + d[i] * 0.12 * R / 0.5 for i in range(3))
        p1 = tuple(loc[i] + d[i] * (R - thick) for i in range(3))
        B.tube("%s_sp%d" % (name, k), [p0, p1], [thick * 0.42, thick * 0.32], mat_spoke, seg=5)


# ----------------------------------------------------------------------------- décors
# Chaque fonction construit la pièce autour de (0, 0, 0) (point d'appui), face avant vers -Y.

def p_cactus(B: Builder) -> None:
    g = M("cactus")

    def fluted(name, path, r):
        """Tronc cannelé (8 côtes) le long d'un chemin, bout arrondi."""
        P = [Vector(p) for p in path]
        secs = []
        n = len(P)
        for i in range(n):
            t = (P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized()
            side = t.cross(Vector((0, 1, 0)))
            if side.length < 1e-4:
                side = Vector((1, 0, 0))
            side.normalize()
            nrm = side.cross(t).normalized()
            taper = 1.0 if i < n - 2 else (0.8 if i == n - 2 else 0.45)
            sec = []
            for k in range(32):
                a = 2 * math.pi * k / 32
                rr = r * taper * (1.0 + 0.09 * math.cos(8 * a))
                sec.append(tuple(P[i] + side * math.cos(a) * rr + nrm * math.sin(a) * rr))
            secs.append(sec)
        bm = C.bm_loft(secs)
        B.add(name, bm, g, sharp=85)
        # épines claires (petits points sur les côtes avant)
        for i in range(1, n - 1, 1):
            for k in (-1, 0, 1):
                a = -math.pi / 2 + k * math.pi / 4
                p = P[i] + Vector((math.cos(a) * r * 1.07, math.sin(a) * r * 1.07, 0))
                B.sphere("%s_sp%d_%d" % (name, i, k), 0.025, tuple(p), M("cream"), seg=5, rings=3,
                         shadow=False, outline=False)
    fluted("trunk", [(0, 0, 0), (0, 0, 0.6), (0, 0, 1.2), (0, 0, 1.8), (0, 0, 2.3), (0, 0, 2.55)], 0.27)
    fluted("armL", C.bezier((-0.15, 0, 0.95), (-0.7, 0, 0.95), (-0.72, 0, 1.2), (-0.7, 0, 1.85), 7), 0.17)
    fluted("armR", C.bezier((0.15, 0, 1.35), (0.62, 0, 1.35), (0.64, 0, 1.55), (0.62, 0, 2.1), 7), 0.15)
    B.sphere("flower", 0.07, (0.0, -0.08, 2.6), M("flower"), scale=(1, 1, 0.6), outline=False)
    for k in range(6):  # cailloux au pied
        a = k * 1.1
        B.sphere("st%d" % k, 0.07 + 0.03 * (k % 3), (math.cos(a) * 0.4, math.sin(a) * 0.3, 0.03), M("stone"),
                 scale=(1.2, 1, 0.6), seg=8, rings=5)


def p_barrel(B: Builder, loc=(0, 0, 0), name="barrel", water: bool = False) -> None:
    x, y, z = loc
    h, r = 1.0, 0.34
    secs = []
    for i in range(9):
        t = i / 8
        rr = r * (0.88 + 0.12 * math.sin(math.pi * t))
        secs.append(C.ellipse(x, y, z + t * h, rr, rr, n=20))
    bm = C.bm_loft(secs)
    B.add(name + "_body", bm, M("wood"), sharp=70)
    # douelles : fines lignes sombres verticales (avant)
    for k in range(7):
        a = -math.pi * 0.5 + (k - 3) * 0.33
        pts = []
        for i in range(9):
            t = i / 8
            rr = r * (0.88 + 0.12 * math.sin(math.pi * t)) + 0.004
            pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr, z + t * h))
        B.tube("%s_st%d" % (name, k), pts, [0.012] * 9, M("wood_dark"), seg=4, shadow=False)
    for t in (0.14, 0.86, 0.36, 0.64):
        rr = r * (0.88 + 0.12 * math.sin(math.pi * t)) + 0.012
        B.torus("%s_hoop%.0f" % (name, t * 100), rr, 0.03, (x, y, z + t * h), M("iron"), seg=24, rseg=5)
    B.cyl(name + "_top", r * 0.86, r * 0.86, 0.04, (x, y, z + h - 0.01), M("wood_dark" if not water else "water"), seg=20)
    if not water:
        B.cyl(name + "_bung", 0.05, 0.05, 0.03, (x + 0.15, y - 0.1, z + h + 0.01), M("wood"), seg=8)


def p_water_trough(B: Builder) -> None:
    w, d, h = 1.7, 0.8, 0.75
    wood = M("wood_grey")
    B.box("legs_l", (0.14, d * 0.9, 0.25), (-w / 2 + 0.25, 0, 0.12), M("wood_dark"))
    B.box("legs_r", (0.14, d * 0.9, 0.25), (w / 2 - 0.25, 0, 0.12), M("wood_dark"))
    for i, zz in enumerate((0.35, 0.58)):
        B.box("front%d" % i, (w, 0.1, 0.24), (0, -d / 2, zz), wood)
        B.box("back%d" % i, (w, 0.1, 0.24), (0, d / 2, zz), wood)
    B.box("endl", (0.1, d, 0.5), (-w / 2, 0, 0.47), wood)
    B.box("endr", (0.1, d, 0.5), (w / 2, 0, 0.47), wood)
    B.box("bottom", (w, d, 0.08), (0, 0, 0.24), wood)
    B.box("water", (w - 0.12, d - 0.12, 0.02), (0, 0, 0.62), M("water"), outline=False)
    for sx in (-w / 2 + 0.06, w / 2 - 0.06):
        for sy in (-d / 2, d / 2):
            B.box("band%.1f%.1f" % (sx, sy), (0.16, 0.13, 0.5), (sx, sy, 0.47), M("iron"))
    # pompe à bras
    B.box("pump", (0.18, 0.18, 1.2), (w / 2 - 0.35, d / 2 + 0.1, 0.6), M("iron"))
    B.tube("spout", [(w / 2 - 0.35, d / 2 + 0.05, 1.05), (w / 2 - 0.35, d / 2 - 0.25, 1.0), (w / 2 - 0.35, d / 2 - 0.3, 0.88)],
           [0.05, 0.05, 0.04], M("iron"))
    B.tube("handle", [(w / 2 - 0.35, d / 2 + 0.1, 1.2), (w / 2 - 0.1, d / 2 + 0.1, 1.5)], [0.035, 0.03], M("iron_dark"))


def p_hitching_post(B: Builder) -> None:
    w = 1.9
    for sx in (-w / 2 + 0.15, w / 2 - 0.15):
        B.box("post%.1f" % sx, (0.2, 0.2, 1.35), (sx, 0, 0.67), M("wood"), bevel=0.02)
        B.box("cap%.1f" % sx, (0.26, 0.26, 0.06), (sx, 0, 1.36), M("wood_dark"))
    B.cyl("rail", 0.08, 0.08, w + 0.1, (0, -0.02, 1.15), M("wood_grey"), rot=(0, math.pi / 2, 0), seg=10)
    B.torus("ring", 0.08, 0.018, (0.3, -0.12, 1.02), M("iron"), rot=(math.pi / 2, 0, 0), seg=14, rseg=4)
    # bride de cuir qui pend
    B.tube("rein", [(0.3, -0.12, 0.95), (0.35, -0.16, 0.7), (0.5, -0.18, 0.55), (0.62, -0.16, 0.62)],
           [0.025] * 4, M("leather"))


def p_wagon(B: Builder) -> None:
    w, d = 2.9, 1.3
    zb = 0.75
    B.box("bed", (w, d, 0.12), (0, 0, zb), M("wood_dark"))
    B.plank_row("side_f", -w / 2, w / 2, -d / 2, zb, zb + 0.65, 0.08, M("wood_red"), 3, axis="z")
    B.plank_row("side_b", -w / 2, w / 2, d / 2, zb, zb + 0.65, 0.08, M("wood_red"), 3, axis="z")
    B.box("end_l", (0.08, d, 0.65), (-w / 2, 0, zb + 0.32), M("wood_red"))
    B.box("end_r", (0.08, d, 0.65), (w / 2, 0, zb + 0.32), M("wood_red"))
    for sx in (-w / 2, -w / 6, w / 6, w / 2):
        B.box("stake%.1f" % sx, (0.1, 0.1, 0.8), (sx, -d / 2 - 0.05, zb + 0.35), M("wood_dark"))
    # bâche tendue sur arceaux (diligence couverte)
    secs = []
    for i in range(5):
        x = -w / 2 + 0.2 + i * (w - 1.0) / 4
        pts = []
        for k in range(13):
            a = math.pi * k / 12
            pts.append((x, math.cos(a) * d * 0.52, zb + 0.6 + math.sin(a) * 1.05))
        secs.append(pts)
    bm = C.bm_loft(secs, closed=False)
    ob = B.add("canvas", bm, M("cloth_cream"), sharp=80)
    C.solidify(ob, 0.03)
    for i in range(5):
        x = -w / 2 + 0.2 + i * (w - 1.0) / 4
        pts = [(x - 0.01, math.cos(math.pi * k / 12) * d * 0.535, zb + 0.6 + math.sin(math.pi * k / 12) * 1.08) for k in range(13)]
        B.tube("hoop%d" % i, pts, [0.03] * 13, M("wood_dark"), seg=5)
    for (sx, R) in ((-w / 2 + 0.55, 0.62), (w / 2 - 0.65, 0.72)):
        for sy in (-d / 2 - 0.15, d / 2 + 0.15):
            wheel(B, "wh%.1f%.1f" % (sx, sy), R, (sx, sy, R), M("iron"), M("wood"), axis="y")
    B.cyl("axle_f", 0.06, 0.06, d + 0.4, (-w / 2 + 0.55, 0, 0.62), M("iron_dark"), rot=(math.pi / 2, 0, 0))
    B.cyl("axle_b", 0.06, 0.06, d + 0.4, (w / 2 - 0.65, 0, 0.72), M("iron_dark"), rot=(math.pi / 2, 0, 0))
    B.tube("tongue", [(-w / 2, 0, 0.7), (-w / 2 - 1.1, -0.1, 0.3), (-w / 2 - 1.5, -0.15, 0.22)], [0.07, 0.06, 0.05], M("wood_dark"))
    p_barrel(B, loc=(w / 2 - 0.55, 0.2, zb + 0.06), name="cargo_b")
    B.box("crate", (0.7, 0.6, 0.55), (-0.2, 0.1, zb + 0.34), M("plank_light"), rot=(0, 0, 0.2))


def p_wagon_wheel(B: Builder) -> None:
    # Roue posée contre un mur, légèrement inclinée
    R = 0.72
    sub = Builder()
    wheel(sub, "w", R, (0, 0.15, R), M("iron"), M("wood"), axis="y")
    for ob in sub.objs:
        ob.rotation_euler = (math.radians(-12), 0, 0)
        B.objs.append(ob)


def p_saloon_bar(B: Builder) -> None:
    w, d, h = 4.0, 0.8, 1.15
    B.box("top", (w + 0.2, d + 0.2, 0.1), (0, 0, h), M("wood_dark"), bevel=0.03)
    B.box("top_edge", (w + 0.24, 0.08, 0.06), (0, -d / 2 - 0.1, h - 0.02), M("brass"))
    B.box("body", (w, d, h - 0.1), (0, 0, (h - 0.1) / 2), M("wood"))
    # panneaux moulurés en façade
    n = 8
    for i in range(n):
        x = -w / 2 + (i + 0.5) * w / n
        B.box("pan%d" % i, (w / n - 0.18, 0.04, h - 0.45), (x, -d / 2 - 0.02, (h - 0.1) / 2 + 0.04), M("wood_red"), bevel=0.02)
    B.box("kick", (w + 0.05, d + 0.05, 0.14), (0, 0, 0.07), M("wood_dark"))
    B.cyl("footrail", 0.04, 0.04, w, (0, -d / 2 - 0.2, 0.24), M("brass"), rot=(0, math.pi / 2, 0), seg=8)
    import random
    rnd = random.Random(4)
    for i in range(9):  # bouteilles et verres
        x = -w / 2 + 0.4 + i * (w - 0.8) / 8 + rnd.uniform(-0.15, 0.15)
        if i % 3 == 2:
            B.cyl("glass%d" % i, 0.06, 0.07, 0.14, (x, -0.1, h + 0.12), M("cream"), seg=8)
        else:
            mat = M("bottle_g" if i % 2 else "bottle_b")
            B.cyl("bot%d" % i, 0.075, 0.075, 0.32, (x, 0.05, h + 0.21), mat, seg=8)
            B.cyl("neck%d" % i, 0.03, 0.03, 0.14, (x, 0.05, h + 0.44), mat, seg=6)
    for sx in (-w / 3, 0.2, w / 3):  # tabourets
        B.cyl("stool%.1f" % sx, 0.22, 0.22, 0.08, (sx, -d / 2 - 0.55, 0.85), M("wood_red"), seg=14)
        B.cyl("stoolleg%.1f" % sx, 0.05, 0.08, 0.8, (sx, -d / 2 - 0.55, 0.4), M("iron_dark"), seg=8)


def p_piano(B: Builder) -> None:
    w, d, h = 1.8, 0.7, 1.7
    B.box("case", (w, d, h - 0.3), (0, 0.1, 0.3 + (h - 0.3) / 2), M("wood_dark"), bevel=0.03)
    B.box("top", (w + 0.1, d + 0.12, 0.08), (0, 0.1, h + 0.02), M("wood_dark"))
    B.box("panel", (w - 0.4, 0.04, 0.7), (0, -d / 2 + 0.08, 1.35), M("wood_red"), bevel=0.02)
    B.box("keybed", (w - 0.1, 0.45, 0.12), (0, -d / 2 - 0.15, 0.95), M("wood_dark"))
    B.box("keys", (w - 0.3, 0.32, 0.03), (0, -d / 2 - 0.16, 1.02), M("ivory"))
    for i in range(16):
        if i % 7 in (2, 6):
            continue
        x = -(w - 0.3) / 2 + (i + 0.75) * (w - 0.3) / 16
        B.box("bk%d" % i, (0.06, 0.18, 0.04), (x, -d / 2 - 0.07, 1.045), M("black"), outline=False)
    for sx in (-w / 2 + 0.15, w / 2 - 0.15):
        B.box("leg%.1f" % sx, (0.12, 0.12, 0.9), (sx, -d / 2 - 0.3, 0.45), M("wood_dark"))
    B.box("plinth", (w, d, 0.3), (0, 0.1, 0.15), M("wood_dark"))
    for sx in (-0.75, 0.75):  # chandeliers
        B.cyl("cand%.1f" % sx, 0.035, 0.035, 0.24, (sx, 0.0, h + 0.18), M("candle"), seg=6)
        B.sphere("fl%.1f" % sx, 0.05, (sx, 0.0, h + 0.34), M("flame"), scale=(1, 1, 1.6), shadow=False, outline=False)
    B.box("sheet", (0.5, 0.03, 0.34), (0.2, -d / 2 + 0.04, 1.85), M("paper"), rot=(math.radians(-12), 0, 0))
    B.cyl("stool", 0.24, 0.24, 0.1, (0, -d / 2 - 0.85, 0.7), M("wood_red"), seg=14)
    B.cyl("stoolleg", 0.05, 0.1, 0.66, (0, -d / 2 - 0.85, 0.33), M("wood_dark"), seg=8)


def p_poker_table(B: Builder) -> None:
    R = 0.75
    B.cyl("rim", R, R, 0.1, (0, 0, 0.95), M("wood_dark"), seg=28)
    B.cyl("felt", R - 0.1, R - 0.1, 0.02, (0, 0, 1.005), M("felt"), seg=28, outline=False)
    B.cyl("leg", 0.12, 0.12, 0.9, (0, 0, 0.45), M("wood_dark"), seg=10)
    B.cyl("foot", 0.45, 0.5, 0.08, (0, 0, 0.04), M("wood_dark"), seg=16)
    import random
    rnd = random.Random(2)
    for i in range(5):
        a = rnd.uniform(0, 6.28)
        rr = rnd.uniform(0.2, 0.6)
        B.box("card%d" % i, (0.16, 0.22, 0.01), (math.cos(a) * rr, math.sin(a) * rr, 1.02), M("ivory"), rot=(0, 0, a), outline=False)
    for i, (x, y) in enumerate(((-0.25, -0.3), (0.35, 0.1), (0.1, 0.45))):
        for k in range(3 + i):
            B.cyl("chip%d_%d" % (i, k), 0.07, 0.07, 0.025, (x, y, 1.03 + k * 0.026), M("red" if i != 1 else "cream"), seg=10, outline=k == 2 + i)
    B.cyl("glass", 0.06, 0.07, 0.16, (-0.5, 0.25, 1.09), M("bottle_b"), seg=8)
    for a in (0.6, 2.4, 4.3):  # chaises
        cx, cy = math.cos(a) * 1.35, math.sin(a) * 1.0
        B.box("seat%.1f" % a, (0.5, 0.5, 0.08), (cx, cy, 0.62), M("wood"), rot=(0, 0, a))
        for lx in (-0.2, 0.2):
            for ly in (-0.2, 0.2):
                rx = cx + lx * math.cos(a) - ly * math.sin(a)
                ry = cy + lx * math.sin(a) + ly * math.cos(a)
                B.box("cl%.1f%.1f%.1f" % (a, lx, ly), (0.06, 0.06, 0.6), (rx, ry, 0.3), M("wood_dark"))
        bx, by = cx + math.cos(a) * 0.25, cy + math.sin(a) * 0.25
        B.box("back%.1f" % a, (0.5, 0.06, 0.65), (bx, by, 0.98), M("wood"), rot=(0, 0, a + math.pi / 2))


def p_lantern(B: Builder) -> None:
    # Lanterne sur poteau (rue / intérieur posé)
    B.box("pole", (0.12, 0.12, 2.6), (0, 0.05, 1.3), M("wood_dark"))
    B.box("base", (0.4, 0.4, 0.12), (0, 0.05, 0.06), M("wood_dark"))
    B.box("arm", (0.55, 0.08, 0.08), (0.24, 0.05, 2.45), M("iron_dark"))
    lx, lz = 0.45, 2.0
    B.cyl("hook", 0.015, 0.015, 0.2, (lx, 0.05, lz + 0.35), M("iron_dark"), seg=4)
    B.cyl("roof", 0.02, 0.2, 0.16, (lx, 0.05, lz + 0.25), M("iron"), seg=8)
    B.cyl("glass", 0.13, 0.13, 0.32, (lx, 0.05, lz), M("glass"), seg=8, outline=True, shadow=True)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        B.cyl("bar%d" % k, 0.018, 0.018, 0.34, (lx + math.cos(a) * 0.13, 0.05 + math.sin(a) * 0.13, lz), M("iron"), seg=4)
    B.cyl("bottom", 0.16, 0.14, 0.06, (lx, 0.05, lz - 0.18), M("iron"), seg=8)
    B.sphere("flame", 0.05, (lx, 0.05, lz - 0.02), M("flame"), scale=(1, 1, 1.7), shadow=False, outline=False)


def p_rail_track(B: Builder) -> None:
    # Tronçon de voie (E-O) d'une case : traverses + rails (plat, pas d'ombre propre).
    L = 1.78
    for i in range(4):
        x = -L / 2 + (i + 0.5) * L / 4
        B.box("tie%d" % i, (0.22, 1.25, 0.08), (x, 0, 0.04), M("wood_dark" if i % 2 else "wood"), shadow=False)
    for sy in (-0.38, 0.38):
        B.box("rail%.1f" % sy, (L, 0.07, 0.1), (0, sy, 0.13), M("steel"), shadow=False)
        B.box("railb%.1f" % sy, (L, 0.13, 0.03), (0, sy, 0.09), M("iron"), shadow=False)


def p_mine_cart(B: Builder) -> None:
    w, d = 1.5, 1.05
    secs = []
    for z, s in ((0.35, 0.82), (1.1, 1.0)):
        secs.append([(-w / 2 * s, -d / 2 * s, z), (w / 2 * s, -d / 2 * s, z), (w / 2 * s, d / 2 * s, z), (-w / 2 * s, d / 2 * s, z)])
    bm = C.bm_loft(secs)
    B.add("tub", bm, M("rust"), sharp=30)
    for z in (0.5, 0.95):
        s = 0.82 + (z - 0.35) / 0.75 * 0.18 + 0.02
        B.box("bandf%.1f" % z, (w * s, 0.03, 0.07), (0, -d / 2 * s, z), M("iron_dark"))
    for sx in (-0.45, 0.45):
        B.box("rib%.1f" % sx, (0.07, 0.03, 0.7), (sx, -d / 2 * 0.92, 0.73), M("iron_dark"))
    for sx in (-0.48, 0.48):
        for sy in (-0.42, 0.42):
            B.cyl("w%.1f%.1f" % (sx, sy), 0.2, 0.2, 0.08, (sx, sy * 1.1, 0.2), M("iron_dark"), rot=(math.pi / 2, 0, 0), seg=14)
    # charge de minerai
    import random
    rnd = random.Random(3)
    for k in range(14):
        x, y = rnd.uniform(-0.55, 0.55), rnd.uniform(-0.35, 0.35)
        B.sphere("ore%d" % k, rnd.uniform(0.12, 0.2), (x, y, 1.1 + rnd.uniform(0, 0.12)),
                 M("gold" if k % 5 == 0 else "ore"), scale=(1.2, 1, 0.8), seg=7, rings=5)


def p_support_beam(B: Builder) -> None:
    # Cadre de boisage : deux montants + chapeau (au mur)
    B.box("post_l", (0.24, 0.24, 2.8), (-0.75, 0, 1.4), M("wood"), bevel=0.02)
    B.box("post_r", (0.24, 0.24, 2.8), (0.75, 0, 1.4), M("wood"), bevel=0.02)
    B.box("cap", (2.0, 0.3, 0.28), (0, 0, 2.9), M("wood_dark"), bevel=0.02)
    for sx in (-1, 1):
        B.box("brace%d" % sx, (0.12, 0.14, 0.6), (sx * 0.55, 0, 2.6), M("wood_dark"), rot=(0, sx * 0.8, 0))
    B.tube("nail", [(-0.75, -0.13, 2.2), (-0.75, -0.16, 2.2)], [0.03, 0.03], M("iron"))


def p_wanted_poster(B: Builder) -> None:
    # Panneau d'affichage sur pied avec avis de recherche.
    for sx in (-0.5, 0.5):
        B.box("leg%.1f" % sx, (0.12, 0.12, 2.1), (sx, 0.05, 1.05), M("wood_dark"))
    B.box("board", (1.3, 0.08, 1.15), (0, 0.0, 1.55), M("wood_grey"), bevel=0.02)
    B.box("roof", (1.5, 0.35, 0.06), (0, -0.05, 2.18), M("wood_dark"), rot=(math.radians(-15), 0, 0))
    B.box("poster", (0.62, 0.02, 0.86), (-0.18, -0.06, 1.55), M("paper"), rot=(0, 0.04, 0))
    B.box("poster2", (0.38, 0.02, 0.5), (0.38, -0.055, 1.68), M("paper"), rot=(0, -0.08, 0))
    # « WANTED » + portrait (décalques sombres)
    B.box("title", (0.5, 0.01, 0.1), (-0.18, -0.075, 1.88), M("black"), outline=False)
    B.box("face", (0.34, 0.01, 0.36), (-0.18, -0.075, 1.55), M("wood_dark"), outline=False)
    B.box("mask", (0.22, 0.012, 0.08), (-0.18, -0.082, 1.6), M("red"), outline=False)
    B.box("rew", (0.44, 0.01, 0.06), (-0.18, -0.075, 1.25), M("black"), outline=False)
    B.box("rew2", (0.3, 0.01, 0.05), (-0.18, -0.075, 1.17), M("black"), outline=False)
    for (x, z) in ((-0.45, 1.95), (0.08, 1.95), (0.38, 1.9)):
        B.sphere("pin%.1f" % x, 0.025, (x, -0.09, z), M("red"), seg=6, rings=4, outline=False)


def p_water_tower(B: Builder) -> None:
    H = 3.2
    for sx in (-0.95, 0.95):
        for sy in (-0.75, 0.75):
            B.box("leg%.1f%.1f" % (sx, sy), (0.18, 0.18, H), (sx, sy, H / 2), M("wood"), rot=(sy * 0.05, -sx * 0.05, 0))
    for z in (1.0, 2.2):
        B.box("xf%.1f" % z, (2.0, 0.08, 0.12), (0, -0.78, z), M("wood_dark"))
        B.box("xs%.1f" % z, (0.08, 1.6, 0.12), (-0.98, 0, z), M("wood_dark"))
    B.box("diag", (2.3, 0.07, 0.1), (0, -0.8, 1.6), M("wood_dark"), rot=(0, 0.5, 0))
    B.box("deck", (2.4, 2.0, 0.12), (0, 0, H + 0.05), M("wood_dark"))
    # cuve à douelles
    R, Ht = 1.15, 1.9
    n = 22
    for k in range(n):
        a = 2 * math.pi * k / n
        B.box("stave%d" % k, (0.34, 0.1, Ht), (math.cos(a) * R, math.sin(a) * R, H + 0.1 + Ht / 2),
              M("wood" if k % 3 else "wood_grey"), rot=(0, 0, a + math.pi / 2))
    for z in (0.25, 0.9, 1.6):
        B.torus("hoop%.1f" % z, R + 0.06, 0.035, (0, 0, H + 0.1 + z), M("iron"), seg=32, rseg=5)
    B.cyl("roof", 0.05, R + 0.25, 0.75, (0, 0, H + 0.1 + Ht + 0.36), M("wood_red"), seg=16)
    B.cyl("finial", 0.06, 0.03, 0.3, (0, 0, H + Ht + 0.95), M("iron_dark"), seg=6)
    B.tube("spout", [(0.5, -1.0, H + 0.5), (0.5, -1.4, H + 0.3), (0.5, -1.5, H - 0.4)], [0.08, 0.08, 0.08], M("iron"))
    B.tube("ladder_l", [(-0.3, -1.16, 0), (-0.3, -1.16, H + 1.6)], [0.035, 0.035], M("wood_dark"))
    B.tube("ladder_r", [(0.0, -1.16, 0), (0.0, -1.16, H + 1.6)], [0.035, 0.035], M("wood_dark"))
    for k in range(12):
        z = 0.3 + k * 0.38
        B.tube("rung%d" % k, [(-0.3, -1.17, z), (0.0, -1.17, z)], [0.025, 0.025], M("wood"), seg=4)


def p_tumbleweed(B: Builder) -> None:
    import random
    rnd = random.Random(9)
    c = (0, 0, 0.42)
    B.sphere("core", 0.3, c, M("tumble"), seg=10, rings=7)
    for k in range(34):
        a, b = rnd.uniform(0, 6.28), rnd.uniform(-1.2, 1.2)
        p = [c]
        r = 0.0
        for j in range(4):
            r += rnd.uniform(0.1, 0.16)
            aa = a + rnd.uniform(-0.6, 0.6)
            p.append((math.cos(aa) * math.cos(b) * r, math.sin(aa) * math.cos(b) * r * 0.9, c[2] + math.sin(b) * r * 0.9))
        B.tube("tw%d" % k, p, [0.022, 0.018, 0.014, 0.01, 0.007], M("tumble" if k % 3 else "hay_dark"), seg=4, sharp=80)


def p_hay_bale(B: Builder) -> None:
    w, d, h = 1.4, 0.85, 0.75
    B.box("bale", (w, d, h), (0, 0, h / 2), M("hay"), bevel=0.08)
    import random
    rnd = random.Random(1)
    for k in range(26):  # brins qui dépassent
        x = rnd.uniform(-w / 2, w / 2)
        z = rnd.uniform(0.1, h)
        side = rnd.choice((-1, 1))
        y0 = -d / 2 - 0.01 if side < 0 else rnd.uniform(-d / 2, d / 2)
        z0 = z if side < 0 else h + 0.01
        B.tube("st%d" % k, [(x, y0, z0), (x + rnd.uniform(-0.12, 0.12), y0 - 0.08 * (side < 0), z0 + rnd.uniform(0.02, 0.1))],
               [0.012, 0.006], M("hay_dark" if k % 2 else "hay"), seg=3, shadow=False, outline=False)
    for sx in (-w / 4, w / 4):  # liens
        B.box("tie%.1f" % sx, (0.04, d + 0.02, 0.03), (sx, 0, h + 0.005), M("leather"))
        B.box("tief%.1f" % sx, (0.04, 0.03, h), (sx, -d / 2 - 0.005, h / 2), M("leather"))
    B.box("bale2", (1.1, 0.85, 0.7), (0.15, 0.1, h + 0.35), M("hay_dark"), bevel=0.07, rot=(0, 0, 0.25))


def p_bed(B: Builder) -> None:
    w, d = 1.35, 2.3
    B.box("frame", (w, d, 0.28), (0, 0, 0.4), M("wood"))
    B.box("matt", (w - 0.08, d - 0.1, 0.18), (0, 0, 0.62), M("cloth_cream"), bevel=0.05)
    B.box("blanket", (w, d * 0.6, 0.06), (0, -d * 0.18, 0.72), M("cloth_red"), bevel=0.02)
    B.box("pillow", (w * 0.75, 0.38, 0.14), (0, d / 2 - 0.3, 0.76), M("ivory"), bevel=0.05)
    B.box("head", (w + 0.1, 0.12, 1.25), (0, d / 2, 0.62), M("wood_dark"), bevel=0.02)
    B.box("foot", (w + 0.1, 0.12, 0.8), (0, -d / 2, 0.4), M("wood_dark"), bevel=0.02)
    for sx in (-w / 2, w / 2):
        B.cyl("hp%.1f" % sx, 0.06, 0.06, 1.4, (sx, d / 2, 0.7), M("iron"), seg=8)
        B.sphere("hk%.1f" % sx, 0.08, (sx, d / 2, 1.42), M("brass"), seg=8, rings=5)


def p_desk(B: Builder) -> None:
    w, d, h = 1.7, 0.8, 0.95
    B.box("top", (w, d, 0.08), (0, 0, h), M("wood_dark"), bevel=0.02)
    for sx in (-w / 2 + 0.35, w / 2 - 0.35):
        B.box("ped%.1f" % sx, (0.62, d - 0.1, h - 0.06), (sx, 0, (h - 0.06) / 2), M("wood"))
        for k in range(3):
            B.box("dr%.1f%d" % (sx, k), (0.5, 0.03, 0.24), (sx, -d / 2 + 0.03, 0.18 + k * 0.28), M("wood_red"))
            B.sphere("kn%.1f%d" % (sx, k), 0.03, (sx, -d / 2 - 0.0, 0.2 + k * 0.28), M("brass"), seg=6, rings=4, outline=False)
    B.box("papers", (0.5, 0.36, 0.03), (-0.3, 0.05, h + 0.05), M("paper"), rot=(0, 0, 0.2))
    B.box("book", (0.36, 0.28, 0.08), (0.45, 0.1, h + 0.08), M("cloth_red"), rot=(0, 0, -0.3))
    B.cyl("ink", 0.06, 0.06, 0.1, (0.1, 0.2, h + 0.09), M("black"), seg=8)
    B.tube("quill", [(0.1, 0.2, h + 0.12), (0.18, 0.3, h + 0.45)], [0.012, 0.03], M("ivory"), seg=4)
    # lampe à pétrole
    B.cyl("lampb", 0.12, 0.1, 0.12, (0.75, 0.25, h + 0.1), M("brass"), seg=10)
    B.cyl("lampg", 0.08, 0.1, 0.24, (0.75, 0.25, h + 0.28), M("glass"), seg=10)
    B.sphere("lampf", 0.035, (0.75, 0.25, h + 0.27), M("flame"), scale=(1, 1, 1.8), shadow=False, outline=False)
    B.box("chair", (0.55, 0.5, 0.08), (0, 0.85, 0.58), M("leather"))
    B.box("chairback", (0.55, 0.08, 0.7), (0, 1.1, 0.95), M("leather"))


def p_jail_bars(B: Builder) -> None:
    w, h = 1.78, 2.8
    B.box("top", (w, 0.14, 0.12), (0, 0, h), M("iron_dark"))
    B.box("bot", (w, 0.14, 0.12), (0, 0, 0.06), M("iron_dark"))
    B.box("mid", (w, 0.1, 0.08), (0, 0, h * 0.45), M("iron"))
    for i in range(9):
        x = -w / 2 + 0.1 + i * (w - 0.2) / 8
        B.cyl("bar%d" % i, 0.035, 0.035, h, (x, 0, h / 2), M("iron"), seg=6)
    B.box("lock", (0.18, 0.1, 0.22), (0.5, -0.08, h * 0.45), M("brass"))


def p_bench(B: Builder) -> None:
    w = 1.5
    B.plank_row("seat", -w / 2, w / 2, 0, 0.62, 0.68, 0.5, M("wood_grey"), 1, axis="z")
    for i in range(3):
        B.box("back%d" % i, (w, 0.06, 0.13), (0, 0.27, 0.95 + i * 0.18), M("wood_grey"), rot=(0.12, 0, 0))
    for sx in (-w / 2 + 0.2, w / 2 - 0.2):
        B.box("leg%.1f" % sx, (0.1, 0.5, 0.62), (sx, 0, 0.31), M("wood_dark"))
        B.box("bk%.1f" % sx, (0.1, 0.08, 0.75), (sx, 0.3, 1.0), M("wood_dark"))


def p_safe(B: Builder) -> None:
    w, d, h = 1.0, 0.9, 1.35
    B.box("body", (w, d, h), (0, 0, h / 2 + 0.08), M("green_paint"), bevel=0.06)
    B.box("door", (w - 0.2, 0.05, h - 0.25), (0, -d / 2 - 0.02, h / 2 + 0.08), M("green_paint"), bevel=0.02)
    B.box("trim", (w - 0.3, 0.02, h - 0.36), (0, -d / 2 - 0.05, h / 2 + 0.08), M("gold"), outline=False)
    B.box("trim2", (w - 0.36, 0.025, h - 0.42), (0, -d / 2 - 0.055, h / 2 + 0.08), M("green_paint"), outline=False)
    B.cyl("dial", 0.14, 0.14, 0.06, (0.0, -d / 2 - 0.08, h * 0.62), M("steel"), rot=(math.pi / 2, 0, 0), seg=16)
    B.cyl("handle", 0.03, 0.03, 0.3, (0.0, -d / 2 - 0.12, h * 0.38), M("brass"), rot=(0, math.pi / 2, 0), seg=6)
    for sx in (-w / 2 + 0.15, w / 2 - 0.15):
        B.box("foot%.1f" % sx, (0.18, d - 0.1, 0.1), (sx, 0, 0.05), M("iron_dark"))


def p_shelf(B: Builder) -> None:
    w, d, h = 1.6, 0.55, 2.3
    B.box("back", (w, 0.06, h), (0, d / 2, h / 2), M("wood_dark"))
    for sx in (-w / 2, w / 2):
        B.box("side%.1f" % sx, (0.08, d, h), (sx, 0, h / 2), M("wood"))
    import random
    rnd = random.Random(5)
    for k in range(4):
        z = 0.15 + k * 0.72
        B.box("sh%d" % k, (w, d, 0.06), (0, 0, z), M("wood"))
        if k == 3:
            continue
        x = -w / 2 + 0.2
        while x < w / 2 - 0.25:
            t = rnd.random()
            if t < 0.35:
                hh = rnd.uniform(0.28, 0.42)
                B.cyl("jar%d%.2f" % (k, x), 0.1, 0.1, hh, (x + 0.1, 0, z + 0.03 + hh / 2),
                      M(rnd.choice(["bottle_g", "bottle_b", "cream"])), seg=8)
                x += 0.26
            elif t < 0.7:
                hh = rnd.uniform(0.25, 0.4)
                B.box("box%d%.2f" % (k, x), (0.34, d * 0.7, hh), (x + 0.17, 0, z + 0.03 + hh / 2),
                      M(rnd.choice(["plank_light", "cloth_red", "paper", "green_paint"])))
                x += 0.4
            else:
                B.cyl("can%d%.2f" % (k, x), 0.09, 0.09, 0.2, (x + 0.09, -0.05, z + 0.13), M("steel"), seg=8)
                x += 0.22


def p_counter(B: Builder) -> None:
    w, d, h = 3.2, 0.8, 1.15
    B.box("top", (w + 0.15, d + 0.15, 0.1), (0, 0, h), M("wood_dark"), bevel=0.03)
    B.box("body", (w, d, h - 0.1), (0, 0, (h - 0.1) / 2), M("wood"))
    n = 6
    for i in range(n):
        x = -w / 2 + (i + 0.5) * w / n
        B.box("pan%d" % i, (w / n - 0.2, 0.04, h - 0.45), (x, -d / 2 - 0.02, (h - 0.1) / 2 + 0.04), M("plank_light"), bevel=0.02)
    # grille de guichet + caisse + balance
    for i in range(7):
        B.cyl("gb%d" % i, 0.015, 0.015, 0.75, (-1.2 + i * 0.12, 0, h + 0.4), M("brass"), seg=4)
    B.box("gtop", (0.85, 0.06, 0.06), (-0.84, 0, h + 0.78), M("brass"))
    B.box("register", (0.55, 0.45, 0.4), (1.2, 0.05, h + 0.25), M("brass"), bevel=0.03)
    B.box("regtop", (0.45, 0.2, 0.18), (1.2, 0.18, h + 0.52), M("gold"), rot=(-0.3, 0, 0))
    B.cyl("scale", 0.03, 0.03, 0.5, (0.2, 0.1, h + 0.25), M("brass"), seg=6)
    B.tube("beam", [(-0.1, 0.1, h + 0.5), (0.5, 0.1, h + 0.5)], [0.02, 0.02], M("brass"))
    for sx in (-0.1, 0.5):
        B.cyl("pan%.1f" % sx, 0.13, 0.1, 0.04, (sx, 0.1, h + 0.32), M("brass"), seg=10)
    B.box("ledger", (0.5, 0.35, 0.06), (-2.0, 0.0, h + 0.08), M("cloth_red"), rot=(0, 0, 0.15))


def p_pew(B: Builder) -> None:
    w = 2.6
    B.box("seat", (w, 0.55, 0.08), (0, 0, 0.62), M("wood_dark"))
    B.box("back", (w, 0.08, 0.75), (0, 0.27, 1.0), M("wood_dark"), rot=(0.1, 0, 0))
    B.box("backtop", (w + 0.05, 0.14, 0.06), (0, 0.31, 1.38), M("wood"))
    for sx in (-w / 2, w / 2):
        B.box("end%.1f" % sx, (0.1, 0.65, 1.3), (sx, 0.05, 0.65), M("wood"), bevel=0.03)
    B.box("book", (0.3, 0.22, 0.05), (0.8, -0.05, 0.69), M("black"), rot=(0, 0, 0.3))


def p_ore_pile(B: Builder) -> None:
    import random
    rnd = random.Random(8)
    for k in range(22):
        a = rnd.uniform(0, 6.28)
        r = rnd.uniform(0, 0.75) * (1 - k / 30)
        z = max(0.0, 0.55 - r * 0.7) * rnd.uniform(0.6, 1.0)
        B.sphere("o%d" % k, rnd.uniform(0.14, 0.26), (math.cos(a) * r * 1.2, math.sin(a) * r * 0.8, z + 0.08),
                 M("gold" if k % 6 == 0 else ("ore" if k % 2 else "stone")), scale=(1.2, 1.0, 0.8), seg=7, rings=5)
    B.tube("pick", [(0.75, -0.25, 0.05), (0.2, -0.45, 0.6)], [0.035, 0.035], M("wood"))
    B.tube("pickhead", [(0.05, -0.5, 0.55), (0.25, -0.42, 0.66), (0.42, -0.36, 0.55)], [0.03, 0.045, 0.02], M("iron"))


def p_altar(B: Builder) -> None:
    w, d, h = 1.8, 0.8, 1.1
    B.box("body", (w, d, h), (0, 0, h / 2), M("wood"), bevel=0.03)
    B.box("cloth", (w + 0.1, d + 0.1, 0.05), (0, 0, h + 0.02), M("ivory"))
    B.box("drape", (1.0, 0.03, 0.85), (0, -d / 2 - 0.06, h - 0.4), M("cloth_red"))
    B.box("crossv", (0.07, 0.04, 0.45), (0, -d / 2 - 0.08, h - 0.4), M("gold"), outline=False)
    B.box("crossh", (0.28, 0.04, 0.07), (0, -d / 2 - 0.08, h - 0.3), M("gold"), outline=False)
    B.box("crossV", (0.1, 0.1, 0.9), (0, 0.15, h + 0.48), M("gold"))
    B.box("crossH", (0.5, 0.1, 0.1), (0, 0.15, h + 0.68), M("gold"))
    for sx in (-0.8, 0.8):
        B.cyl("holder%.1f" % sx, 0.08, 0.1, 0.12, (sx, 0, h + 0.1), M("brass"), seg=8)
        B.cyl("cand%.1f" % sx, 0.045, 0.045, 0.4, (sx, 0, h + 0.36), M("candle"), seg=8)
        B.sphere("fl%.1f" % sx, 0.05, (sx, 0, h + 0.6), M("flame"), scale=(1, 1, 1.7), shadow=False, outline=False)


# ----------------------------------------------------------------------------- mobilier des gabarits
# (aménagement par type de pièce : scripts/dungeon/gen/fw_templates.gd)

def _bottles(B: Builder, prefix: str, x0: float, x1: float, y: float, z: float, n: int, seed: int) -> None:
    import random
    rnd = random.Random(seed)
    for i in range(n):
        x = x0 + (x1 - x0) * (i + 0.5) / n + rnd.uniform(-0.04, 0.04)
        mat = M(rnd.choice(["bottle_g", "bottle_b", "bottle_g", "cream"]))
        hh = rnd.uniform(0.22, 0.32)
        B.cyl("%sb%d" % (prefix, i), 0.065, 0.065, hh, (x, y, z + hh / 2), mat, seg=8)
        B.cyl("%sn%d" % (prefix, i), 0.026, 0.026, 0.1, (x, y, z + hh + 0.05), mat, seg=6, outline=False)


def p_bottle_shelf(B: Builder) -> None:
    """Étagère à bouteilles derrière le bar (miroir au centre)."""
    w, d, h = 3.2, 0.5, 2.4
    B.box("back", (w, 0.08, h), (0, d / 2, h / 2), M("wood_dark"))
    B.box("mirror", (1.0, 0.03, 0.9), (0, d / 2 - 0.06, 1.55), M("mirror"), outline=False)
    B.box("mframe", (1.12, 0.05, 1.02), (0, d / 2 - 0.04, 1.55), M("brass"))
    for sx in (-w / 2, w / 2):
        B.box("side%.1f" % sx, (0.1, d, h), (sx, 0, h / 2), M("wood"))
    B.box("crown", (w + 0.2, d + 0.1, 0.12), (0, 0, h + 0.06), M("wood_dark"), bevel=0.02)
    B.box("base", (w, d, 0.7), (0, 0, 0.35), M("wood"))
    for i in range(4):
        x = -w / 2 + (i + 0.5) * w / 4
        B.box("door%d" % i, (w / 4 - 0.12, 0.03, 0.5), (x, -d / 2 - 0.01, 0.36), M("wood_red"), bevel=0.01)
    for k, z in enumerate((0.72, 1.3, 1.88)):
        for sx, x0, x1 in ((-1, -w / 2 + 0.08, -0.62), (1, 0.62, w / 2 - 0.08)):
            B.box("sh%d%d" % (k, sx), (x1 - x0, d - 0.1, 0.05), ((x0 + x1) / 2, 0, z), M("wood"))
            _bottles(B, "bt%d%d" % (k, sx), x0, x1, -0.02, z + 0.03, 4, k * 7 + sx)
    B.box("shmid", (1.24, d - 0.1, 0.05), (0, 0, 0.72), M("wood"))
    _bottles(B, "btm", -0.55, 0.55, -0.02, 0.75, 4, 99)


def p_stage(B: Builder) -> None:
    """Petite scène de saloon : estrade, rideaux rouges, rampe de lumières."""
    w, d, h = 5.0, 2.7, 0.5
    B.box("deck", (w, d, h), (0, 0, h / 2), M("wood"), bevel=0.02)
    B.plank_row("front", -w / 2, w / 2, -d / 2 - 0.01, 0.02, h - 0.04, 0.03, M("wood_red"), 8)
    B.box("lip", (w + 0.1, 0.12, 0.08), (0, -d / 2, h), M("wood_dark"))
    for sx in (-w / 2 + 0.15, w / 2 - 0.15):
        B.box("post%.1f" % sx, (0.18, 0.18, 2.8), (sx, d / 2 - 0.2, h + 1.4), M("wood_dark"))
    B.box("valance", (w, 0.14, 0.4), (0, d / 2 - 0.2, h + 2.65), M("cloth_red"), bevel=0.02)
    B.box("trim", (w, 0.03, 0.06), (0, d / 2 - 0.28, h + 2.47), M("gold"), outline=False)
    for sx in (-1, 1):
        secs = []
        for i in range(6):
            x = sx * (w / 2 - 0.3 - i * 0.16)
            z0 = h
            secs.append([(x, d / 2 - 0.25 + 0.08 * math.sin(i * 1.7), z0), (x, d / 2 - 0.25 + 0.08 * math.sin(i * 1.7), h + 2.5)])
        for i, sec in enumerate(secs):
            B.box("cur%d%d" % (sx, i), (0.18, 0.08, 2.5), (sec[0][0], sec[0][1], h + 1.25), M("cloth_red"))
        B.tube("tie%d" % sx, [(sx * (w / 2 - 0.25), d / 2 - 0.3, h + 1.2), (sx * (w / 2 - 1.05), d / 2 - 0.3, h + 1.2)], [0.03, 0.03], M("gold"))
    B.box("backdrop", (w - 0.4, 0.06, 2.5), (0, d / 2 - 0.12, h + 1.25), M("wood_red"))
    for i in range(7):
        x = -w / 2 + 0.5 + i * (w - 1.0) / 6
        B.cyl("lamp%d" % i, 0.07, 0.09, 0.1, (x, -d / 2 + 0.12, h + 0.05), M("brass"), seg=8)
        B.sphere("lampf%d" % i, 0.045, (x, -d / 2 + 0.12, h + 0.13), M("flame"), shadow=False, outline=False)
    B.cyl("chair", 0.22, 0.22, 0.08, (-0.6, 0.2, h + 0.55), M("wood"), seg=12)
    B.cyl("chairl", 0.04, 0.06, 0.55, (-0.6, 0.2, h + 0.27), M("wood_dark"), seg=6)
    B.box("guitar", (0.35, 0.08, 0.9), (0.7, 0.3, h + 0.45), M("wood_red"), rot=(0, 0.3, 0), bevel=0.05)


def p_dresser(B: Builder) -> None:
    w, d, h = 1.4, 0.6, 1.2
    B.box("body", (w, d, h), (0, 0, h / 2 + 0.08), M("wood"), bevel=0.02)
    B.box("top", (w + 0.08, d + 0.06, 0.06), (0, 0, h + 0.11), M("wood_dark"))
    for k in range(3):
        z = 0.3 + k * 0.36
        B.box("dr%d" % k, (w - 0.14, 0.03, 0.3), (0, -d / 2 - 0.01, z), M("wood_red"), bevel=0.01)
        for sx in (-0.3, 0.3):
            B.sphere("kn%d%.1f" % (k, sx), 0.03, (sx, -d / 2 - 0.04, z), M("brass"), seg=6, rings=4, outline=False)
    B.box("mframe", (0.9, 0.06, 0.95), (0, d / 2 - 0.08, h + 0.6), M("wood_dark"), bevel=0.03)
    B.box("mirror", (0.74, 0.02, 0.8), (0, d / 2 - 0.12, h + 0.6), M("mirror"), outline=False)
    B.cyl("vase", 0.07, 0.05, 0.25, (-0.45, -0.05, h + 0.27), M("cream"), seg=8)
    B.box("brush", (0.22, 0.08, 0.04), (0.4, -0.1, h + 0.16), M("leather"))


def p_washstand(B: Builder) -> None:
    w, d, h = 1.0, 0.55, 0.9
    B.box("body", (w, d, h), (0, 0, h / 2), M("wood"), bevel=0.02)
    B.box("top", (w + 0.06, d + 0.04, 0.05), (0, 0, h + 0.03), M("cream"))
    B.box("door", (w - 0.2, 0.03, h - 0.3), (0, -d / 2 - 0.01, h / 2), M("wood_red"), bevel=0.01)
    B.cyl("basin", 0.3, 0.18, 0.14, (0, 0, h + 0.12), M("ivory"), seg=16)
    B.cyl("water", 0.26, 0.26, 0.01, (0, 0, h + 0.18), M("water"), seg=16, outline=False)
    B.cyl("pitcher", 0.1, 0.13, 0.36, (0.32, 0.08, h + 0.24), M("ivory"), seg=10)
    B.box("towel", (0.3, 0.03, 0.4), (-0.42, -d / 2 - 0.03, h - 0.15), M("cloth_cream"))
    B.box("splash", (w, 0.05, 0.5), (0, d / 2, h + 0.27), M("wood_dark"))


def p_nightstand(B: Builder) -> None:
    w, d, h = 0.6, 0.5, 0.75
    B.box("body", (w, d, h), (0, 0, h / 2), M("wood"), bevel=0.02)
    B.box("dr", (w - 0.1, 0.03, 0.2), (0, -d / 2 - 0.01, h - 0.18), M("wood_red"))
    B.sphere("kn", 0.03, (0, -d / 2 - 0.04, h - 0.18), M("brass"), seg=6, rings=4, outline=False)
    B.cyl("holder", 0.1, 0.08, 0.05, (0.05, 0.05, h + 0.03), M("brass"), seg=10)
    B.cyl("candle", 0.04, 0.04, 0.24, (0.05, 0.05, h + 0.17), M("candle"), seg=8)
    B.sphere("fl", 0.045, (0.05, 0.05, h + 0.33), M("flame"), scale=(1, 1, 1.7), shadow=False, outline=False)
    B.box("book", (0.22, 0.16, 0.05), (-0.15, -0.05, h + 0.03), M("cloth_red"), rot=(0, 0, 0.3))


def p_gun_rack(B: Builder) -> None:
    w, h = 1.5, 2.0
    B.box("board", (w, 0.08, h), (0, 0.1, h / 2 + 0.2), M("wood_dark"), bevel=0.02)
    B.box("shelf", (w, 0.3, 0.06), (0, -0.02, 0.45), M("wood"))
    B.box("rail", (w, 0.12, 0.08), (0, 0.0, 1.85), M("wood"))
    for i in range(4):
        x = -w / 2 + 0.25 + i * (w - 0.5) / 3
        B.box("stock%d" % i, (0.12, 0.07, 0.45), (x, -0.02, 0.7), M("wood_red"), bevel=0.02)
        B.cyl("barrel%d" % i, 0.025, 0.025, 1.1, (x, -0.02, 1.4), M("iron_dark"), seg=6)
    B.box("ammo", (0.32, 0.22, 0.14), (0.45, -0.05, 0.08), M("green_paint"))
    B.box("ammo2", (0.28, 0.2, 0.12), (0.4, -0.05, 0.21), M("wood"))


def p_bookcase(B: Builder) -> None:
    import random
    w, d, h = 1.5, 0.5, 2.3
    B.box("back", (w, 0.06, h), (0, d / 2, h / 2), M("wood_dark"))
    for sx in (-w / 2, w / 2):
        B.box("side%.1f" % sx, (0.08, d, h), (sx, 0, h / 2), M("wood"))
    B.box("crown", (w + 0.12, d + 0.08, 0.1), (0, 0, h + 0.05), M("wood_dark"))
    rnd = random.Random(12)
    for k in range(4):
        z = 0.1 + k * 0.56
        B.box("sh%d" % k, (w, d, 0.05), (0, 0, z), M("wood"))
        x = -w / 2 + 0.08
        while x < w / 2 - 0.15:
            bw = rnd.uniform(0.06, 0.11)
            bh = rnd.uniform(0.32, 0.44)
            tilt = rnd.uniform(-0.15, 0.15) if rnd.random() < 0.15 else 0.0
            B.box("bk%d%.2f" % (k, x), (bw, d * 0.7, bh), (x + bw / 2, -0.02, z + 0.03 + bh / 2),
                  M(rnd.choice(["cloth_red", "green_paint", "leather", "wood_red", "cream", "black"])), rot=(0, tilt, 0))
            x += bw + 0.01
            if rnd.random() < 0.08:
                x += 0.12


def p_crate_stack(B: Builder) -> None:
    def crate(name, s, loc, rot=0.0):
        B.box(name, (s, s, s), loc, M("plank_light"), rot=(0, 0, rot), bevel=0.02)
        x, y, z = loc
        for k in (-1, 1):
            B.box(name + "b%d" % k, (s + 0.02, 0.06, 0.08), (x, y - s / 2 - 0.01, z + k * (s / 2 - 0.06)), M("wood_dark"), rot=(0, 0, rot))
        B.box(name + "x", (0.06, 0.03, s * 1.3), (x, y - s / 2 - 0.02, z), M("wood_dark"), rot=(0, 0.78, 0))
    crate("c1", 0.75, (-0.3, 0.0, 0.375))
    crate("c2", 0.62, (0.42, 0.05, 0.31), 0.1)
    crate("c3", 0.6, (-0.2, 0.05, 1.05), -0.15)
    B.box("lid", (0.5, 0.4, 0.04), (0.45, -0.02, 0.64), M("paper"), rot=(0, 0, 0.3))


def p_sacks(B: Builder) -> None:
    for i, (x, y, z, r) in enumerate(((-0.35, 0.05, 0.25, 0.2), (0.3, 0.0, 0.25, -0.3), (0.0, 0.1, 0.62, 0.1))):
        B.sphere("sack%d" % i, 0.42, (x, y, z), M("cloth_cream"), scale=(1.15, 0.8, 0.62), seg=12, rings=8)
        B.sphere("tie%d" % i, 0.09, (x + 0.38 * math.cos(r), y - 0.05, z + 0.08), M("hay_dark"), scale=(1.4, 0.8, 0.8), seg=8, rings=5)
    B.box("stamp", (0.3, 0.02, 0.18), (-0.33, -0.29, 0.28), M("cloth_red"), outline=False)


def p_dining_table(B: Builder) -> None:
    w, d, h = 2.6, 1.0, 0.9
    B.box("top", (w, d, 0.08), (0, 0, h), M("wood_dark"), bevel=0.02)
    B.box("cloth", (w * 0.95, d * 0.5, 0.02), (0, 0, h + 0.05), M("cloth_cream"), outline=False)
    for sx in (-w / 2 + 0.15, w / 2 - 0.15):
        for sy in (-d / 2 + 0.12, d / 2 - 0.12):
            B.box("leg%.1f%.1f" % (sx, sy), (0.1, 0.1, h), (sx, sy, h / 2), M("wood_dark"))
    for i, x in enumerate((-0.8, 0.0, 0.8)):
        B.cyl("plate%d" % i, 0.14, 0.14, 0.02, (x, -0.25, h + 0.07), M("ivory"), seg=12, outline=False)
        B.cyl("plate2%d" % i, 0.14, 0.14, 0.02, (x, 0.25, h + 0.07), M("ivory"), seg=12, outline=False)
    B.cyl("cand", 0.035, 0.035, 0.3, (0, 0, h + 0.2), M("candle"), seg=8)
    B.sphere("fl", 0.04, (0, 0, h + 0.38), M("flame"), scale=(1, 1, 1.7), shadow=False, outline=False)
    _bottles(B, "tb", 0.3, 0.6, 0.0, h + 0.04, 2, 5)
    for sy, back in ((-d / 2 - 0.4, -1), (d / 2 + 0.4, 1)):
        for x in (-0.8, 0.0, 0.8):
            B.box("seat%.1f%.1f" % (x, sy), (0.46, 0.44, 0.07), (x, sy, 0.55), M("wood"))
            for lx in (-0.18, 0.18):
                for ly in (-0.17, 0.17):
                    B.box("cl%.1f%.1f%.2f%.2f" % (x, sy, lx, ly), (0.05, 0.05, 0.55), (x + lx, sy + ly, 0.27), M("wood_dark"))
            B.box("back%.1f%.1f" % (x, sy), (0.46, 0.05, 0.6), (x, sy + back * 0.2, 0.88), M("wood"))


def p_table_chairs(B: Builder) -> None:
    """Petite table carrée et deux chaises (bureau du shérif, sacristie, salle à manger)."""
    h = 0.9
    B.box("top", (1.0, 0.9, 0.07), (0, 0, h), M("wood"), bevel=0.02)
    for sx in (-0.4, 0.4):
        for sy in (-0.35, 0.35):
            B.box("leg%.1f%.1f" % (sx, sy), (0.08, 0.08, h), (sx, sy, h / 2), M("wood_dark"))
    B.box("paper", (0.3, 0.22, 0.01), (-0.15, 0.05, h + 0.04), M("paper"), rot=(0, 0, 0.3), outline=False)
    B.cyl("mug", 0.06, 0.06, 0.12, (0.25, -0.1, h + 0.1), M("iron"), seg=8)
    for sx in (-1, 1):
        x = sx * 0.92
        B.box("seat%d" % sx, (0.44, 0.46, 0.07), (x, 0, 0.55), M("wood"))
        for lx in (-0.17, 0.17):
            for ly in (-0.18, 0.18):
                B.box("cl%d%.2f%.2f" % (sx, lx, ly), (0.05, 0.05, 0.55), (x + lx, ly, 0.27), M("wood_dark"))
        B.box("back%d" % sx, (0.05, 0.46, 0.6), (x + sx * 0.2, 0, 0.88), M("wood"))


def p_candelabra(B: Builder) -> None:
    B.cyl("foot", 0.22, 0.26, 0.06, (0, 0, 0.03), M("brass"), seg=12)
    B.cyl("stem", 0.04, 0.05, 1.4, (0, 0, 0.75), M("brass"), seg=8)
    B.tube("arms", [(-0.3, 0, 1.55), (-0.25, 0, 1.4), (0, 0, 1.35), (0.25, 0, 1.4), (0.3, 0, 1.55)], [0.025] * 5, M("brass"))
    for x in (-0.3, 0.0, 0.3):
        z = 1.55 if x else 1.5
        B.cyl("cup%.1f" % x, 0.06, 0.04, 0.05, (x, 0, z), M("brass"), seg=8)
        B.cyl("c%.1f" % x, 0.035, 0.035, 0.22, (x, 0, z + 0.13), M("candle"), seg=8)
        B.sphere("f%.1f" % x, 0.04, (x, 0, z + 0.29), M("flame"), scale=(1, 1, 1.7), shadow=False, outline=False)


def p_settee(B: Builder) -> None:
    w, d = 2.4, 0.8
    B.box("seat", (w, d, 0.3), (0, 0, 0.45), M("cloth_red"), bevel=0.08)
    B.box("back", (w, 0.25, 0.7), (0, d / 2 - 0.1, 0.85), M("cloth_red"), bevel=0.1)
    for sx in (-w / 2, w / 2):
        B.box("arm%.1f" % sx, (0.22, d, 0.55), (sx, 0, 0.55), M("cloth_red"), bevel=0.08)
        for sy in (-d / 2 + 0.1, d / 2 - 0.1):
            B.cyl("leg%.1f%.1f" % (sx, sy), 0.05, 0.04, 0.3, (sx, sy, 0.15), M("wood_dark"), seg=6)
    B.box("frame", (w + 0.1, d + 0.05, 0.08), (0, 0, 0.3), M("wood_dark"))
    for sx in (-0.6, 0.6):
        B.box("cush%.1f" % sx, (0.4, 0.15, 0.35), (sx, d / 2 - 0.3, 0.8), M("cloth_cream"), bevel=0.06, rot=(0.2, 0, 0))


def p_stove(B: Builder) -> None:
    B.cyl("body", 0.38, 0.38, 0.9, (0, 0, 0.6), M("iron_dark"), seg=16)
    B.cyl("belly", 0.44, 0.44, 0.3, (0, 0, 0.6), M("iron_dark"), seg=16)
    B.cyl("top", 0.42, 0.42, 0.06, (0, 0, 1.08), M("iron"), seg=16)
    B.cyl("pipe", 0.12, 0.12, 1.6, (0, 0.1, 1.9), M("iron_dark"), seg=10)
    B.box("door", (0.3, 0.04, 0.24), (0, -0.44, 0.55), M("iron"))
    B.box("glow", (0.22, 0.02, 0.06), (0, -0.47, 0.5), M("flame"), outline=False, shadow=False)
    for a in (0.6, 2.5, 4.4):
        B.cyl("foot%.1f" % a, 0.05, 0.07, 0.15, (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.07), M("iron_dark"), seg=6)
    B.cyl("kettle", 0.15, 0.12, 0.18, (0.15, -0.1, 1.2), M("steel"), seg=10)


def p_bucket(B: Builder) -> None:
    B.cyl("bucket", 0.22, 0.17, 0.38, (0, 0, 0.19), M("wood"), seg=14)
    for z in (0.08, 0.3):
        B.torus("hoop%.1f" % z, 0.19 + z * 0.08, 0.02, (0, 0, z), M("iron"), seg=18, rseg=4)
    B.cyl("water", 0.2, 0.2, 0.01, (0, 0, 0.36), M("water"), seg=14, outline=False)
    B.tube("handle", [(-0.22, 0, 0.38), (0, 0, 0.6), (0.22, 0, 0.38)], [0.015] * 3, M("iron"))


def p_tool_rack(B: Builder) -> None:
    w, h = 1.5, 1.9
    B.box("board", (w, 0.08, h), (0, 0.1, h / 2 + 0.15), M("wood_grey"), bevel=0.02)
    B.box("pick", (0.06, 0.06, 1.2), (-0.45, 0.0, 1.1), M("wood"), rot=(0, 0.1, 0))
    B.tube("pickh", [(-0.75, -0.02, 1.62), (-0.45, -0.02, 1.72), (-0.15, -0.02, 1.62)], [0.03, 0.05, 0.03], M("iron"))
    B.box("shovel", (0.06, 0.06, 1.1), (0.05, 0.0, 1.1), M("wood"))
    B.box("blade", (0.3, 0.04, 0.4), (0.05, -0.02, 0.5), M("iron"), bevel=0.03)
    B.torus("rope", 0.22, 0.04, (0.5, -0.02, 1.3), M("hay_dark"), rot=(math.pi / 2, 0, 0), seg=18, rseg=5)
    B.cyl("lamp", 0.08, 0.08, 0.2, (0.5, -0.05, 0.75), M("glass"), seg=8)


# Décors muraux (dessinés sur la face avant des murs, sans ombre portée ; (0,0,0) = bas du décor,
# plaqué contre le mur : géométrie en y ≈ 0, face vers -Y).

def k_frame(B: Builder) -> None:
    B.box("frame", (0.8, 0.06, 0.62), (0, 0, 0.95), M("brass"), bevel=0.02)
    B.box("canvas", (0.66, 0.02, 0.48), (0, -0.04, 0.95), M("sky"), outline=False)
    B.box("hill", (0.66, 0.025, 0.16), (0, -0.05, 0.79), M("cactus"), outline=False)
    B.box("sun", (0.12, 0.03, 0.12), (0.15, -0.055, 1.05), M("gold"), outline=False)


def k_horns(B: Builder) -> None:
    B.box("plaque", (0.36, 0.05, 0.42), (0, 0, 1.0), M("wood_dark"), bevel=0.03)
    B.sphere("skull", 0.16, (0, -0.07, 1.0), M("bone"), scale=(0.85, 0.6, 1.2), seg=10, rings=7)
    for sx in (-1, 1):
        B.tube("horn%d" % sx, [(sx * 0.1, -0.08, 1.12), (sx * 0.45, -0.1, 1.15), (sx * 0.7, -0.1, 1.32)], [0.06, 0.04, 0.012], M("ivory"))


def k_mirror(B: Builder) -> None:
    B.box("frame", (0.62, 0.05, 0.86), (0, 0, 1.0), M("wood_dark"), bevel=0.04)
    B.box("glass", (0.5, 0.02, 0.74), (0, -0.03, 1.0), M("mirror"), outline=False)
    B.box("hl", (0.06, 0.025, 0.5), (-0.12, -0.04, 1.05), M("ivory"), rot=(0, 0.4, 0), outline=False)


def k_poster(B: Builder) -> None:
    B.box("paper", (0.5, 0.02, 0.7), (0, 0, 0.95), M("paper"), rot=(0, 0.05, 0))
    B.box("title", (0.4, 0.025, 0.08), (0, -0.02, 1.2), M("black"), outline=False)
    B.box("face", (0.24, 0.025, 0.26), (0, -0.02, 0.97), M("wood_dark"), outline=False)
    B.box("mask", (0.16, 0.03, 0.06), (0, -0.025, 1.0), M("red"), outline=False)
    B.box("rew", (0.34, 0.025, 0.05), (0, -0.02, 0.75), M("black"), outline=False)


def k_clock(B: Builder) -> None:
    B.box("case", (0.42, 0.12, 0.95), (0, 0, 0.95), M("wood_dark"), bevel=0.03)
    B.cyl("face", 0.16, 0.16, 0.02, (0, -0.07, 1.22), M("ivory"), rot=(math.pi / 2, 0, 0), seg=16)
    B.box("hand", (0.02, 0.025, 0.12), (0, -0.09, 1.26), M("black"), outline=False)
    B.box("hand2", (0.09, 0.025, 0.02), (0.04, -0.09, 1.22), M("black"), outline=False)
    B.box("glass", (0.24, 0.02, 0.4), (0, -0.07, 0.75), M("mirror"), outline=False)
    B.cyl("pend", 0.06, 0.06, 0.02, (0, -0.08, 0.65), M("gold"), rot=(math.pi / 2, 0, 0), seg=10)


def k_map(B: Builder) -> None:
    B.box("map", (0.9, 0.02, 0.6), (0, 0, 0.95), M("paper"))
    B.box("land", (0.5, 0.025, 0.3), (-0.1, -0.015, 0.98), M("hay"), rot=(0, 0.3, 0), outline=False)
    B.tube("river", [(-0.4, -0.02, 0.8), (-0.1, -0.02, 0.95), (0.2, -0.02, 0.9), (0.4, -0.02, 1.15)], [0.012] * 4, M("water"), outline=False)
    for (x, z) in ((-0.3, 1.1), (0.25, 0.85), (0.1, 1.1)):
        B.sphere("pin%.1f" % x, 0.03, (x, -0.04, z), M("red"), seg=6, rings=4, outline=False)


def k_tools(B: Builder) -> None:
    B.box("hook", (0.9, 0.06, 0.06), (0, 0, 1.4), M("wood_dark"))
    B.tube("rope", [(-0.3, -0.03, 1.38), (-0.32, -0.04, 1.0), (-0.28, -0.03, 0.75)], [0.03] * 3, M("hay_dark"))
    B.torus("coil", 0.16, 0.04, (-0.3, -0.05, 0.95), M("hay_dark"), rot=(math.pi / 2, 0, 0), seg=16, rseg=5)
    B.box("saw", (0.5, 0.02, 0.14), (0.15, -0.03, 1.05), M("steel"), rot=(0, 0.2, 0))
    B.box("sawh", (0.14, 0.04, 0.12), (0.43, -0.03, 1.11), M("wood"), rot=(0, 0.2, 0))
    B.cyl("lamp", 0.07, 0.07, 0.18, (0.32, -0.05, 1.28), M("glass"), seg=8)


def k_horseshoe(B: Builder) -> None:
    B.box("board", (0.5, 0.04, 0.3), (0, 0, 1.0), M("wood_grey"), bevel=0.02)
    for i, x in enumerate((-0.12, 0.12)):
        pts = [(x + 0.08 * math.cos(a), -0.04, 1.0 + 0.09 * math.sin(a)) for a in [math.pi * (0.1 + 0.8 * k / 8) for k in range(9)]]
        B.tube("hs%d" % i, pts, [0.018] * 9, M("iron"), seg=4)
    B.tube("bridle", [(0.25, -0.04, 1.1), (0.3, -0.06, 0.8), (0.2, -0.06, 0.6)], [0.025] * 3, M("leather"))


def k_bottles(B: Builder) -> None:
    w = 1.6
    B.box("shelf", (w, 0.22, 0.05), (0, -0.08, 0.95), M("wood"))
    for sx in (-w / 2 + 0.1, w / 2 - 0.1):
        B.box("br%.1f" % sx, (0.05, 0.18, 0.18), (sx, -0.06, 0.85), M("wood_dark"))
    _bottles(B, "wb", -w / 2 + 0.1, w / 2 - 0.1, -0.08, 0.98, 8, 33)
    B.box("sign", (0.7, 0.04, 0.24), (0, 0, 1.48), M("wood_red"), bevel=0.02)
    B.box("signt", (0.5, 0.045, 0.06), (0, -0.01, 1.48), M("gold"), outline=False)


def k_keys(B: Builder) -> None:
    B.box("board", (0.8, 0.05, 0.55), (0, 0, 1.05), M("wood_dark"), bevel=0.02)
    for i in range(8):
        x = -0.3 + (i % 4) * 0.2
        z = 1.18 - (i // 4) * 0.25
        B.cyl("hook%d" % i, 0.012, 0.012, 0.06, (x, -0.04, z), M("brass"), rot=(math.pi / 2, 0, 0), seg=4, outline=False)
        if i not in (2, 5):
            B.box("key%d" % i, (0.04, 0.02, 0.14), (x, -0.05, z - 0.08), M("gold"), outline=False)


def k_cross(B: Builder) -> None:
    B.box("v", (0.12, 0.06, 0.9), (0, 0, 1.0), M("wood_dark"), bevel=0.02)
    B.box("h", (0.5, 0.06, 0.12), (0, 0, 1.18), M("wood_dark"), bevel=0.02)
    B.box("vg", (0.05, 0.065, 0.8), (0, -0.01, 1.0), M("gold"), outline=False)


def k_rifles(B: Builder) -> None:
    for i, z in enumerate((0.85, 1.2)):
        for sx in (-0.45, 0.45):
            B.box("peg%d%.1f" % (i, sx), (0.06, 0.12, 0.06), (sx, -0.05, z - 0.05), M("wood_dark"))
        B.box("stock%d" % i, (0.32, 0.06, 0.11), (-0.5, -0.1, z), M("wood_red"), bevel=0.02)
        B.cyl("barrel%d" % i, 0.022, 0.022, 0.95, (0.1, -0.1, z + 0.02), M("iron_dark"), rot=(0, math.pi / 2, 0), seg=6)


def k_bars(B: Builder) -> None:
    """Grille de cellule vue à travers le mur (barreaux sur toute la face)."""
    w = 1.6
    B.box("dark", (w, 0.02, 1.7), (0, 0.06, 0.85), M("black"), outline=False)
    B.box("top", (w, 0.08, 0.1), (0, 0, 1.68), M("iron_dark"))
    B.box("mid", (w, 0.06, 0.07), (0, 0, 0.9), M("iron"))
    for i in range(7):
        x = -w / 2 + 0.12 + i * (w - 0.24) / 6
        B.cyl("bar%d" % i, 0.035, 0.035, 1.7, (x, -0.02, 0.85), M("iron"), seg=6)


# Détails au sol (vue de dessus, posés à plat, centrés sur (0, 0)).

def d_bottles(B: Builder) -> None:
    for i, (x, y, a, mat) in enumerate(((-0.2, 0.05, 0.6, "bottle_g"), (0.25, -0.1, -1.2, "bottle_b"))):
        B.cyl("b%d" % i, 0.07, 0.07, 0.3, (x, y, 0.07), M(mat), rot=(math.pi / 2, 0, a), seg=8)
    B.cyl("glass", 0.06, 0.05, 0.1, (0.05, 0.22, 0.05), M("cream"), seg=8)
    B.sphere("spill", 0.2, (0.05, -0.05, 0.0), M("bottle_b"), scale=(1.4, 0.9, 0.05), seg=12, rings=4, outline=False)


def d_cards(B: Builder) -> None:
    import random
    rnd = random.Random(3)
    for i in range(6):
        a = rnd.uniform(0, 6.28)
        r = rnd.uniform(0.05, 0.35)
        B.box("card%d" % i, (0.16, 0.22, 0.01), (math.cos(a) * r, math.sin(a) * r, 0.01), M("ivory"), rot=(0, 0, a), outline=False)
    for i in range(4):
        B.cyl("chip%d" % i, 0.06, 0.06, 0.02, (rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), 0.02), M("red" if i % 2 else "cream"), seg=10)


def d_papers(B: Builder) -> None:
    import random
    rnd = random.Random(6)
    for i in range(5):
        B.box("p%d" % i, (0.32, 0.42, 0.01), (rnd.uniform(-0.3, 0.3), rnd.uniform(-0.2, 0.2), 0.01 * i),
              M("paper" if i % 3 else "cream"), rot=(0, 0, rnd.uniform(-1, 1)))


def d_coins(B: Builder) -> None:
    import random
    rnd = random.Random(8)
    for i in range(9):
        B.cyl("c%d" % i, 0.06, 0.06, 0.02, (rnd.uniform(-0.35, 0.35), rnd.uniform(-0.25, 0.25), 0.01), M("gold"), seg=10)
    B.box("bar", (0.32, 0.14, 0.1), (0.1, 0.05, 0.05), M("gold"), bevel=0.02)
    B.box("bag", (0.3, 0.3, 0.2), (-0.25, 0.1, 0.1), M("cloth_cream"), bevel=0.08)


def d_runner(B: Builder) -> None:
    """Tronçon de tapis de couloir (une case de long, raccords invisibles)."""
    L, W = 1.78, 1.0
    B.box("rug", (W, L, 0.02), (0, 0, 0.01), M("cloth_red"), outline=False)
    for sx in (-1, 1):
        B.box("border%d" % sx, (0.08, L, 0.022), (sx * (W / 2 - 0.1), 0, 0.012), M("gold"), outline=False)
        B.box("edge%d" % sx, (0.04, L, 0.024), (sx * (W / 2 - 0.02), 0, 0.012), M("wood_red"), outline=False)
    B.box("motif", (0.3, 0.3, 0.023), (0, 0, 0.013), M("gold"), rot=(0, 0, math.pi / 4), outline=False)
    B.box("motif2", (0.2, 0.2, 0.024), (0, 0, 0.014), M("cloth_red"), rot=(0, 0, math.pi / 4), outline=False)


def d_rug_round(B: Builder) -> None:
    B.cyl("rug", 1.0, 1.0, 0.02, (0, 0, 0.01), M("wood_red"), seg=32)
    B.cyl("in", 0.8, 0.8, 0.022, (0, 0, 0.012), M("cloth_cream"), seg=32, outline=False)
    B.cyl("in2", 0.55, 0.55, 0.024, (0, 0, 0.014), M("cloth_red"), seg=32, outline=False)
    B.cyl("c", 0.2, 0.2, 0.026, (0, 0, 0.016), M("gold"), seg=16, outline=False)


# ----------------------------------------------------------------------------- grands décors
# Grands décors de la ville éparpillée (FloorLayout.landmark_spawns) : posés sur des cases de mur,
# emprise (cases) → le modèle remplit l'emprise vue en 3/4 (1 case = 64 u = 1,778 BU ; la
# profondeur au sol D et la hauteur H se partagent les rangées : 0,743·D + 0,669·H ≈ rangées).
# (0, 0, 0) = milieu du bord AVANT (sud) de l'emprise ; le modèle s'étend vers +Y (nord).

CELL = 64.0 / WORLD_PER_BU


def _depth_for(rows: float, h: float) -> float:
    return max(0.6, (rows * CELL - 0.669 * h) / 0.743)


def _rock_blob(rnd, w: float, d: float, n: int = 14, rough: float = 0.16):
    """Contour irrégulier (x, y) d'un amas, dans [-w/2, w/2] × [0, d]."""
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        k = 1.0 + rnd.uniform(-rough, rough)
        pts.append((math.cos(a) * w / 2 * k, d / 2 + math.sin(a) * d / 2 * k))
    return pts


def _strata(B: Builder, name: str, rnd, w: float, d: float, h: float, layers: int, x0: float = 0.0, y0: float = 0.0,
            shrink: float = 0.12) -> float:
    """Empilement de strates de grès (prismes à contour irrégulier, retrait progressif)."""
    z = 0.0
    mats = [M("rock_red"), M("rock_orange"), M("rock_dark"), M("rock_orange")]
    base = _rock_blob(rnd, w, d)
    cx, cy = 0.0, d / 2
    for k in range(layers):
        hz = h / layers * rnd.uniform(0.8, 1.2)
        s = 1.0 - shrink * k - rnd.uniform(0.0, 0.05)
        dx, dy = rnd.uniform(-0.1, 0.1) * w, rnd.uniform(-0.06, 0.04) * d
        sec0, sec1 = [], []
        for (px, py) in base:
            j = rnd.uniform(0.96, 1.04)
            qx = x0 + cx + (px - cx) * s * j + dx
            qy = y0 + cy + (py - cy) * s * j + dy
            sec0.append((qx, qy, z))
            sec1.append((x0 + cx + (px - cx) * s * j * 0.93 + dx, y0 + cy + (py - cy) * s * j * 0.93 + dy, z + hz))
        bm = C.bm_loft([sec0, sec1])
        top = M("rock_top") if k == layers - 1 else mats[k % len(mats)]
        ob = B.add("%s_l%d" % (name, k), bm, [mats[k % len(mats)], top], sharp=35)
        # Dessus de la dernière strate : couleur claire (face du haut = dernier polygone).
        if k == layers - 1:
            ob.data.polygons[-1].material_index = 1
        z += hz
    return z


def _bushes(B: Builder, rnd, pts, scale: float = 1.0, dry: float = 0.3) -> None:
    for i, (x, y, z) in enumerate(pts):
        r = rnd.uniform(0.16, 0.26) * scale
        m = M("bush_dry" if rnd.random() < dry else "bush")
        for k in range(4):
            a = rnd.uniform(0, 6.28)
            B.sphere("bush%d_%d" % (i, k), r * rnd.uniform(0.7, 1.0),
                     (x + math.cos(a) * r * 0.6, y + math.sin(a) * r * 0.5, z + r * 0.6 + rnd.uniform(0, r * 0.4)),
                     m, scale=(1.0, 1.0, 0.8), seg=8, rings=6)


def _boulders(B: Builder, rnd, pts) -> None:
    for i, (x, y, r) in enumerate(pts):
        B.sphere("bd%d" % i, r, (x, y, r * 0.45), M("rock_red" if i % 2 else "rock_orange"),
                 scale=(1.25, 1.0, 0.75), seg=9, rings=6, sharp=40)


def lm_rock(fp, seed: int, layers: int, h: float, mesa: bool = False):
    def build(B: Builder) -> None:
        import random
        rnd = random.Random(seed)
        w = fp[0] * CELL * 0.9
        d = _depth_for(fp[1] + 0.4, h)
        top = _strata(B, "main", rnd, w, d * 0.92, h, layers, y0=d * 0.04, shrink=0.1 if mesa else 0.16)
        # Second bloc (plus bas) sur le côté : silhouette en amas.
        if fp[0] >= 3:
            side = rnd.choice((-1, 1))
            _strata(B, "sub", rnd, w * 0.45, d * 0.5, h * 0.55, max(2, layers - 2), x0=side * w * 0.3, y0=-d * 0.02)
        _boulders(B, rnd, [(rnd.uniform(-w / 2, w / 2), rnd.uniform(-0.1, 0.25), rnd.uniform(0.12, 0.26)) for _ in range(3 + fp[0])])
        bushes = [(rnd.uniform(-w / 2, w / 2) * 0.9, rnd.uniform(-0.2, 0.1), 0.0) for _ in range(1 + fp[0] // 2)]
        bushes += [(rnd.uniform(-w / 4, w / 4), d * rnd.uniform(0.35, 0.6), top - 0.05) for _ in range(1 if fp[0] < 4 else 2)]
        _bushes(B, rnd, bushes, scale=1.0 + 0.1 * fp[0])
    return build


def _trucks(B: Builder, xs, d: float, r: float = 0.32) -> None:
    for i, x in enumerate(xs):
        B.box("truck%d" % i, (1.0, d * 0.82, 0.22), (x, d / 2, r + 0.05), M("iron_dark"))
        for k, dx in enumerate((-0.32, 0.32)):
            B.cyl("wh%d_%d" % (i, k), r, r, 0.12, (x + dx, 0.02, r), M("iron_dark"), rot=(math.pi / 2, 0, 0), seg=16)
            B.cyl("whc%d_%d" % (i, k), r * 0.45, r * 0.45, 0.13, (x + dx, 0.01, r), M("rust"), rot=(math.pi / 2, 0, 0), seg=10)


def _car_body(B: Builder, name: str, L: float, d: float, h: float, z0: float, mat, roof=None) -> None:
    B.box(name + "_frame", (L + 0.1, d + 0.06, 0.16), (0, d / 2, z0 - 0.08), M("iron_dark"))
    B.box(name, (L, d, h), (0, d / 2, z0 + h / 2), mat, bevel=0.03)
    # Planches verticales (lattes) sur la face avant.
    n = int(L / 0.28)
    for k in range(n + 1):
        x = -L / 2 + k * L / n
        B.box("%s_slat%d" % (name, k), (0.03, 0.02, h * 0.96), (x, -0.005, z0 + h / 2), M("wood_dark"), shadow=False)
    B.box(name + "_roof", (L + 0.16, d + 0.2, 0.1), (0, d / 2, z0 + h + 0.05), roof or M("wood_grey"), bevel=0.03)
    B.box(name + "_walk", (L * 0.95, 0.22, 0.05), (0, d / 2, z0 + h + 0.12), M("wood_dark"))


def lm_boxcar(variant: int):
    def build(B: Builder) -> None:
        L = 4 * CELL * 0.94
        d, h, z0 = 1.9, 1.75, 0.62
        mat = M("boxcar" if variant == 0 else "boxcar_b")
        _car_body(B, "box", L, d, h, z0, mat)
        # Porte coulissante (entrouverte sur la variante b).
        B.box("door", (1.3, 0.05, h * 0.9), (0.2 if variant == 0 else 0.6, -0.03, z0 + h * 0.47), M("wood_red" if variant == 0 else "wood"))
        B.box("rail_d", (2.4, 0.04, 0.06), (0.3, -0.06, z0 + h * 0.93), M("iron"))
        if variant == 1:
            B.box("gap", (0.5, 0.02, h * 0.85), (-0.4, -0.04, z0 + h * 0.45), M("black"), outline=False)
        B.box("ladder", (0.2, 0.04, h), (L / 2 - 0.25, -0.05, z0 + h / 2), M("iron"))
        _trucks(B, (-L / 2 + 0.9, L / 2 - 0.9), d)
    return build


def lm_tankcar(B: Builder) -> None:
    L = 4 * CELL * 0.94
    d = 1.8
    B.box("frame", (L, d * 0.8, 0.2), (0, d / 2, 0.66), M("iron_dark"))
    B.cyl("tank", 0.95, 0.95, L * 0.92, (0, d / 2, 1.6), M("tank_grey"), rot=(0, math.pi / 2, 0), seg=24)
    for sx in (-1, 1):
        B.sphere("cap%d" % sx, 0.95, (sx * L * 0.46, d / 2, 1.6), M("tank_grey"), scale=(0.3, 1, 1), seg=16, rings=10)
    B.cyl("dome", 0.36, 0.36, 0.5, (0, d / 2, 2.6), M("tank_grey"), seg=14)
    B.cyl("domecap", 0.42, 0.42, 0.08, (0, d / 2, 2.86), M("iron_dark"), seg=14)
    for x in (-L * 0.3, L * 0.3):
        B.torus("band%.1f" % x, 0.97, 0.04, (x, d / 2, 1.6), M("iron_dark"), rot=(0, math.pi / 2, 0), seg=28, rseg=5)
    B.box("label", (1.4, 0.02, 0.35), (0, d / 2 - 0.96, 1.6), M("cream"), outline=False)
    _trucks(B, (-L / 2 + 0.9, L / 2 - 0.9), d)


def lm_flatcar(B: Builder) -> None:
    import random
    rnd = random.Random(5)
    L = 4 * CELL * 0.94
    d = 1.9
    B.box("deck", (L, d, 0.22), (0, d / 2, 0.78), M("wood"), bevel=0.02)
    B.box("frame", (L + 0.1, d + 0.06, 0.16), (0, d / 2, 0.62), M("iron_dark"))
    # Chargement : billes de bois et caisses (assez haut pour servir de couvert).
    for k in range(3):
        for j in range(3 - k):
            y = d * 0.25 + j * 0.55 + k * 0.27
            B.cyl("log%d%d" % (k, j), 0.27, 0.27, L * 0.5, (-L * 0.2, y, 1.15 + k * 0.46), M("wood" if (j + k) % 2 else "wood_dark"),
                  rot=(0, math.pi / 2, 0), seg=12)
    for k2 in range(3):
        B.box("crate%d" % k2, (0.8, 0.8, 0.75), (L * 0.22 + (k2 % 2) * 0.9, d * 0.3 + (k2 // 2) * 0.9, 1.27 + (k2 // 2) * 0.0),
              M("plank_light"), bevel=0.03, rot=(0, 0, rnd.uniform(-0.1, 0.1)))
    for x in (-L / 2 + 0.2, L / 2 - 0.2):
        for y in (0.1, d - 0.1):
            B.box("stake%.1f%.1f" % (x, y), (0.1, 0.1, 0.9), (x, y, 1.3), M("wood_dark"))
    _trucks(B, (-L / 2 + 0.9, L / 2 - 0.9), d)


def lm_caboose(B: Builder) -> None:
    L = 3 * CELL * 0.92
    d, h, z0 = 1.85, 1.6, 0.62
    _car_body(B, "cab", L * 0.82, d, h, z0, M("red_paint"), roof=M("wood_dark"))
    B.box("cupola", (1.2, d * 0.7, 0.6), (0, d / 2, z0 + h + 0.4), M("red_paint"), bevel=0.02)
    B.box("cuproof", (1.4, d * 0.85, 0.08), (0, d / 2, z0 + h + 0.74), M("wood_dark"))
    for x in (-0.35, 0.35):
        B.box("cw%.1f" % x, (0.35, 0.03, 0.3), (x, d / 2 - d * 0.35 - 0.01, z0 + h + 0.42), M("glass"), outline=False)
    for x in (-0.6, 0.6):
        B.box("win%.1f" % x, (0.4, 0.03, 0.45), (x, -0.02, z0 + h * 0.62), M("glass"), outline=False)
    for sx in (-1, 1):
        B.box("porch%d" % sx, (0.4, d, 0.08), (sx * (L * 0.41 + 0.2), d / 2, z0), M("iron_dark"))
        B.box("rail%d" % sx, (0.05, d, 0.5), (sx * (L * 0.41 + 0.38), d / 2, z0 + 0.3), M("iron"))
    _trucks(B, (-L * 0.28, L * 0.28), d)


def lm_tender(B: Builder) -> None:
    L = 3 * CELL * 0.92
    d = 1.9
    B.box("body", (L, d, 1.25), (0, d / 2, 1.25), M("loco"), bevel=0.04)
    B.box("coal", (L * 0.85, d * 0.8, 0.3), (0, d / 2, 1.95), M("coal"), bevel=0.15)
    import random
    rnd = random.Random(2)
    for k in range(10):
        B.sphere("lump%d" % k, rnd.uniform(0.12, 0.2), (rnd.uniform(-L * 0.38, L * 0.38), rnd.uniform(0.3, d - 0.3), 2.1),
                 M("coal"), seg=6, rings=4)
    B.box("stripe", (L * 0.98, 0.02, 0.12), (0, -0.01, 1.4), M("red_paint"), outline=False)
    _trucks(B, (-L * 0.28, L * 0.28), d)


def lm_loco(B: Builder) -> None:
    """Locomotive à vapeur (tête à l'ouest) : chaudière noire, cheminée, cabine, chasse-buffles rouge."""
    L = 5 * CELL * 0.94
    d = 1.9
    yc = d / 2
    B.box("frame", (L, d * 0.86, 0.3), (0.0, yc, 0.75), M("iron_dark"))
    B.cyl("boiler", 0.72, 0.72, L * 0.58, (-L * 0.12, yc, 1.6), M("loco"), rot=(0, math.pi / 2, 0), seg=24)
    B.cyl("smokebox", 0.76, 0.76, 0.6, (-L * 0.42, yc, 1.6), M("iron_dark"), rot=(0, math.pi / 2, 0), seg=24)
    B.cyl("front", 0.6, 0.6, 0.06, (-L * 0.42 - 0.32, yc, 1.6), M("iron"), rot=(0, math.pi / 2, 0), seg=20)
    B.cyl("lamp", 0.2, 0.2, 0.3, (-L * 0.42 - 0.1, yc, 2.5), M("brass"), rot=(0, math.pi / 2, 0), seg=12)
    B.cyl("lampg", 0.14, 0.14, 0.04, (-L * 0.42 - 0.27, yc, 2.5), M("glass"), rot=(0, math.pi / 2, 0), seg=12, outline=False)
    B.cyl("stack", 0.2, 0.4, 0.9, (-L * 0.36, yc, 2.65), M("loco"), seg=16)
    B.cyl("stacktop", 0.42, 0.42, 0.1, (-L * 0.36, yc, 3.1), M("iron_dark"), seg=16)
    B.cyl("dome", 0.3, 0.32, 0.45, (-L * 0.1, yc, 2.4), M("brass"), seg=16)
    B.sphere("domecap", 0.31, (-L * 0.1, yc, 2.62), M("brass"), scale=(1, 1, 0.5), seg=12, rings=6)
    B.cyl("sand", 0.24, 0.26, 0.35, (-L * 0.24, yc, 2.35), M("loco"), seg=14)
    for x in (-L * 0.3, -L * 0.05, L * 0.12):
        B.torus("band%.1f" % x, 0.74, 0.035, (x, yc, 1.6), M("brass"), rot=(0, math.pi / 2, 0), seg=28, rseg=5)
    # Cabine.
    cx = L * 0.33
    B.box("cab", (1.6, d * 0.95, 1.9), (cx, yc, 1.85), M("red_paint"), bevel=0.03)
    B.box("cabroof", (1.9, d * 1.08, 0.12), (cx, yc, 2.86), M("loco"), bevel=0.03)
    B.box("cabwin", (0.6, 0.03, 0.55), (cx + 0.15, yc - d * 0.48, 2.15), M("glass"), outline=False)
    # Chasse-buffles.
    secs = []
    for z, k in ((0.25, 1.0), (0.8, 0.55)):
        secs.append([(-L / 2 - 0.25 * k, 0.15, z), (-L / 2 + 0.2, 0.05, z), (-L / 2 + 0.2, d - 0.05, z), (-L / 2 - 0.25 * k, d - 0.15, z)])
    B.add("pilot", C.bm_loft(secs), M("red_paint"), sharp=30)
    # Roues motrices rouges + bielle.
    for i, x in enumerate((-L * 0.2, 0.0, L * 0.18)):
        B.cyl("dw%d" % i, 0.55, 0.55, 0.12, (x, 0.04, 0.6), M("red_paint"), rot=(math.pi / 2, 0, 0), seg=20)
        B.cyl("dwh%d" % i, 0.18, 0.18, 0.14, (x, 0.03, 0.6), M("iron_dark"), rot=(math.pi / 2, 0, 0), seg=10)
    B.box("rod", (L * 0.42, 0.04, 0.08), (-L * 0.01, -0.06, 0.55), M("steel"))
    B.cyl("cyl", 0.25, 0.25, 0.7, (-L * 0.36, 0.1, 0.85), M("iron"), rot=(0, math.pi / 2, 0), seg=14)
    for x in (-L * 0.42, L * 0.33):
        B.cyl("pw%.1f" % x, 0.3, 0.3, 0.12, (x, 0.04, 0.32), M("iron_dark"), rot=(math.pi / 2, 0, 0), seg=14)


def lm_windmill(B: Builder) -> None:
    """Éolienne de pompage (tour en treillis, roue à pales, gouvernail), avec réservoir au pied."""
    H = 6.2
    yc = CELL * 0.9
    for sx in (-1, 1):
        for sy in (-1, 1):
            p0 = (sx * 0.9, yc + sy * 0.9, 0.0)
            p1 = (sx * 0.18, yc + sy * 0.18, H)
            B.tube("leg%d%d" % (sx, sy), [p0, p1], [0.06, 0.04], M("wood_grey"), seg=6)
    for k in range(1, 6):
        t = k / 6.0
        r = 0.9 * (1 - t) + 0.18 * t
        z = H * t
        for (a, b) in (((-r, -r), (r, -r)), ((r, -r), (r, r)), ((-r, -r), (-r, r))):
            B.tube("brace%d_%d%d" % (k, int(a[0] > 0), int(b[1] > 0)), [(a[0], yc + a[1], z), (b[0], yc + b[1], z)], [0.025, 0.025], M("wood_dark"), seg=4)
    B.box("deck", (0.7, 0.7, 0.08), (0, yc, H), M("wood_dark"))
    # Roue (pales en éventail) tournée de 35° vers la caméra.
    hub = (-0.25, yc - 0.45, H + 0.45)
    rot = math.radians(35)
    n = 18
    for k in range(n):
        a = 2 * math.pi * k / n
        d0 = (math.cos(a), math.sin(a))
        def P(r):
            x = d0[0] * r
            z = d0[1] * r
            return (hub[0] + x * math.cos(rot), hub[1] - x * math.sin(rot) * 0.6, hub[2] + z)
        B.tube("blade%d" % k, [P(0.25), P(1.35)], [0.09, 0.14], M("cream" if k % 2 else "steel"), seg=3, flat=0.2)
    B.torus("ring", 0.85, 0.035, hub, M("iron"), rot=(math.pi / 2, 0, -rot), seg=28, rseg=4)
    B.torus("ring2", 1.35, 0.03, hub, M("iron"), rot=(math.pi / 2, 0, -rot), seg=32, rseg=4)
    B.sphere("hubc", 0.18, hub, M("iron_dark"), seg=10, rings=6)
    B.tube("tailbar", [(hub[0], hub[1], hub[2]), (hub[0] + 1.5, hub[1] + 0.9, hub[2] + 0.1)], [0.04, 0.03], M("iron"))
    B.box("vane", (0.06, 1.1, 0.7), (hub[0] + 1.6, hub[1] + 0.95, hub[2] + 0.15), M("red_paint"), rot=(0, 0, 0.5))
    B.tube("pump", [(0, yc, 0.0), (0, yc, H)], [0.03, 0.03], M("iron"), seg=5)
    # Réservoir rond au pied.
    B.cyl("tank", 0.75, 0.75, 0.55, (0.95, yc - 0.55, 0.28), M("wood_grey"), seg=20)
    B.cyl("water", 0.68, 0.68, 0.02, (0.95, yc - 0.55, 0.55), M("water"), seg=20, outline=False)
    B.torus("tband", 0.77, 0.03, (0.95, yc - 0.55, 0.42), M("iron"), seg=24, rseg=4)


def lm_well(B: Builder) -> None:
    """Puits de pierre de la place : margelle, toit à deux pans, treuil et seau."""
    yc = CELL * 0.85
    R = 1.05
    import random
    rnd = random.Random(4)
    n = 16
    for ring_i, z in enumerate((0.0, 0.32, 0.64)):
        for k in range(n):
            a = 2 * math.pi * (k + 0.5 * (ring_i % 2)) / n
            B.box("st%d_%d" % (ring_i, k), (0.42, 0.3, 0.3), (math.cos(a) * R, yc + math.sin(a) * R, z + 0.16),
                  M("stone" if (k + ring_i) % 3 else "ore"), bevel=0.05, rot=(0, 0, a + math.pi / 2))
    B.cyl("dark", R - 0.18, R - 0.18, 0.02, (0, yc, 0.9), M("black"), seg=24, outline=False)
    B.cyl("water", R - 0.25, R - 0.25, 0.02, (0, yc, 0.5), M("water"), seg=24, outline=False)
    for sx in (-1, 1):
        B.box("post%d" % sx, (0.16, 0.16, 2.2), (sx * (R + 0.05), yc, 1.1), M("wood"), bevel=0.02)
    B.cyl("axle", 0.1, 0.1, 2 * R + 0.3, (0, yc, 1.75), M("wood_dark"), rot=(0, math.pi / 2, 0), seg=10)
    B.tube("crank", [(R + 0.2, yc, 1.75), (R + 0.25, yc - 0.3, 1.6), (R + 0.25, yc - 0.32, 1.45)], [0.03] * 3, M("iron"))
    B.tube("rope", [(0, yc, 1.7), (0, yc, 1.1)], [0.02, 0.02], M("hay_dark"))
    B.cyl("bucket", 0.18, 0.14, 0.28, (0, yc, 1.0), M("wood"), seg=12)
    # Toit à deux pans (bardeaux).
    for sy in (-1, 1):
        B.box("roof%d" % sy, (2 * R + 0.8, 0.95, 0.07), (0, yc + sy * 0.38, 2.42), M("wood_red"), rot=(sy * 0.62, 0, 0))
    B.box("ridge", (2 * R + 0.85, 0.12, 0.1), (0, yc, 2.72), M("wood_dark"))
    _bushes(B, rnd, [(-R - 0.5, yc - 0.6, 0.0), (R + 0.6, yc + 0.4, 0.0)], scale=0.9)


def d_rail(B: Builder) -> None:
    """Tronçon de voie ferrée (E-O) vu de dessus : ballast, traverses, rails ; raccord sans couture."""
    import random
    rnd = random.Random(11)
    L = 2.2
    B.box("ballast", (L, 1.85, 0.06), (0, 0, 0.03), M("ballast"), outline=False)
    for k in range(40):
        B.sphere("pb%d" % k, rnd.uniform(0.03, 0.06), (rnd.uniform(-L / 2, L / 2), rnd.choice((-1, 1)) * rnd.uniform(0.7, 0.9), 0.07),
                 M("stone" if k % 2 else "ore"), seg=5, rings=3, outline=False)
    for i in range(5):
        x = -CELL / 2 + (i + 0.5) * CELL / 4
        if abs(x) > L / 2:
            continue
        B.box("tie%d" % i, (0.24, 1.45, 0.08), (x, 0, 0.1), M("wood_dark" if i % 2 else "wood"))
    for sy in (-0.42, 0.42):
        B.box("rail%.1f" % sy, (L, 0.08, 0.1), (0, sy, 0.19), M("steel"))
        B.box("railb%.1f" % sy, (L, 0.15, 0.03), (0, sy, 0.15), M("iron"))


def p_shrub(B: Builder) -> None:
    import random
    rnd = random.Random(21)
    _bushes(B, rnd, [(0.0, 0.0, 0.0), (0.28, 0.12, 0.0), (-0.25, 0.1, 0.0)], scale=1.25, dry=0.35)
    for k in range(6):
        a = rnd.uniform(0, 6.28)
        B.tube("tw%d" % k, [(0, 0.05, 0.05), (math.cos(a) * 0.45, 0.05 + math.sin(a) * 0.3, 0.35 + rnd.uniform(0, 0.25))],
               [0.02, 0.008], M("tumble"), seg=4)


def p_tree(B: Builder) -> None:
    """Arbre du désert (mesquite) : tronc tordu, houppier vert en boules."""
    import random
    rnd = random.Random(31)
    B.tube("trunk", [(0, 0, 0), (0.05, 0.02, 0.6), (-0.1, 0.05, 1.2), (0.0, 0.05, 1.6)], [0.12, 0.1, 0.08, 0.06], M("wood_dark"), seg=7)
    B.tube("br1", [(-0.05, 0.04, 1.0), (-0.5, 0.1, 1.5)], [0.06, 0.04], M("wood_dark"), seg=5)
    B.tube("br2", [(0.0, 0.04, 1.2), (0.5, 0.0, 1.7)], [0.06, 0.04], M("wood_dark"), seg=5)
    for k in range(9):
        a = k * 0.7
        r = rnd.uniform(0.32, 0.46)
        B.sphere("leaf%d" % k, r, (math.cos(a) * 0.45, 0.05 + math.sin(a) * 0.3, 1.65 + rnd.uniform(-0.15, 0.3)),
                 M("bush" if k % 3 else "cactus"), scale=(1, 1, 0.8), seg=9, rings=6)


def p_cart(B: Builder) -> None:
    """Charrette à bras (deux roues) chargée de caisses et d'un tonneau."""
    w, d = 2.2, 1.1
    zb = 0.7
    B.box("bed", (w, d, 0.1), (0, 0, zb), M("wood"))
    for sy in (-d / 2, d / 2):
        B.box("side%.1f" % sy, (w, 0.07, 0.35), (0, sy, zb + 0.2), M("wood_grey"))
    for sx in (-w / 2, w / 2):
        B.box("end%.1f" % sx, (0.07, d, 0.35), (sx, 0, zb + 0.2), M("wood_grey"))
    for sy in (-d / 2 - 0.12, d / 2 + 0.12):
        wheel(B, "wh%.1f" % sy, 0.62, (0.15, sy, 0.62), M("iron"), M("wood"), axis="y")
    B.tube("shaft_l", [(-w / 2, -0.35, zb), (-w / 2 - 1.0, -0.38, 0.25)], [0.05, 0.04], M("wood_dark"))
    B.tube("shaft_r", [(-w / 2, 0.35, zb), (-w / 2 - 1.0, 0.38, 0.25)], [0.05, 0.04], M("wood_dark"))
    B.box("crate", (0.65, 0.6, 0.55), (0.45, 0.0, zb + 0.33), M("plank_light"), bevel=0.03, rot=(0, 0, 0.15))
    p_barrel(B, loc=(-0.45, 0.05, zb + 0.05), name="cb")


def p_fence(B: Builder) -> None:
    """Barrière de ranch (2 cases) : poteaux et deux lisses, une lisse cassée."""
    w = 2 * CELL * 0.92
    for k in range(4):
        x = -w / 2 + k * w / 3
        B.box("post%d" % k, (0.14, 0.14, 1.15), (x, 0.0, 0.57), M("wood_grey" if k % 2 else "wood"), bevel=0.02,
              rot=(0, (k - 1.5) * 0.03, 0))
    B.box("rail_hi", (w + 0.1, 0.08, 0.14), (0, -0.08, 0.95), M("wood"))
    B.box("rail_lo", (w * 0.62, 0.08, 0.14), (-w * 0.19, -0.08, 0.5), M("wood_grey"))
    B.box("rail_br", (w * 0.38, 0.08, 0.14), (w * 0.3, -0.12, 0.3), M("wood_grey"), rot=(0, 0.35, 0))


# Grands décors : (fonction, cadre monde (l, h), hauteur visée BU).
LANDMARKS = {
    "lm_rock_a": (lm_rock((2, 2), 1, 3, 1.4), (220, 220), 0.8),
    "lm_rock_b": (lm_rock((3, 2), 2, 3, 1.5), (300, 240), 0.8),
    "lm_rock_c": (lm_rock((3, 3), 3, 4, 2.0), (300, 320), 1.0),
    "lm_rock_d": (lm_rock((4, 3), 4, 4, 2.2), (380, 330), 1.1),
    "lm_rock_e": (lm_rock((2, 3), 5, 4, 1.9), (220, 320), 1.0),
    "lm_mesa": (lm_rock((5, 4), 6, 5, 2.6, mesa=True), (460, 430), 1.3),
    "lm_loco": (lm_loco, (380, 300), 1.6),
    "lm_tender": (lm_tender, (240, 240), 1.3),
    "lm_boxcar": (lm_boxcar(0), (310, 260), 1.4),
    "lm_boxcar_b": (lm_boxcar(1), (310, 260), 1.4),
    "lm_tankcar": (lm_tankcar, (310, 260), 1.4),
    "lm_flatcar": (lm_flatcar, (310, 260), 1.2),
    "lm_caboose": (lm_caboose, (240, 280), 1.5),
    "lm_windmill": (lm_windmill, (260, 460), 3.2),
    "lm_well": (lm_well, (220, 220), 1.2),
}
LANDMARK_DIR = os.path.join(TMP, "landmarks")


def render_landmarks(only: list[str] | None = None) -> None:
    global PIECES
    keep = PIECES
    PIECES = LANDMARK_DIR
    try:
        for k, (fn, fr, tz) in LANDMARKS.items():
            if only and k not in only:
                continue
            render_piece(k, fn, fr, target_z=tz, outline_px=5.0)
        if not only or "decal_rail" in only:
            render_piece("decal_rail", d_rail, (72, 72), target_z=0.0, flat=True, outline_px=2.5)
    finally:
        PIECES = keep


def pack_landmarks() -> None:
    """Atlas séparé des grands décors : assets/sprites/far_west/landmarks.png (+ landmarks_meta.gd)."""
    pack(2048, pieces_dir=LANDMARK_DIR, out_name="landmarks", extras=False)


FURNITURE = {
    "bottle_shelf": p_bottle_shelf, "stage": p_stage, "dresser": p_dresser, "washstand": p_washstand,
    "nightstand": p_nightstand, "gun_rack": p_gun_rack, "bookcase": p_bookcase, "crate_stack": p_crate_stack,
    "sacks": p_sacks, "dining_table": p_dining_table, "table_chairs": p_table_chairs, "candelabra": p_candelabra,
    "settee": p_settee, "stove": p_stove, "bucket": p_bucket, "tool_rack": p_tool_rack,
    "shrub": p_shrub, "cart": p_cart, "fence": p_fence, "tree": p_tree,
}
FURNITURE_FRAMES = {
    "bottle_shelf": ((150, 140), 1.2), "stage": ((240, 230), 1.4), "dresser": ((90, 120), 1.0),
    "washstand": ((80, 90), 0.6), "nightstand": ((60, 70), 0.5), "gun_rack": ((90, 120), 1.1),
    "bookcase": ((90, 130), 1.2), "crate_stack": ((90, 90), 0.6), "sacks": ((80, 70), 0.4),
    "dining_table": ((150, 140), 0.6), "table_chairs": ((120, 90), 0.6), "candelabra": ((50, 90), 0.9),
    "settee": ((120, 90), 0.5), "stove": ((70, 140), 1.3), "bucket": ((40, 40), 0.3), "tool_rack": ((90, 110), 1.0),
    "shrub": ((70, 60), 0.3), "cart": ((170, 110), 0.6), "fence": ((150, 90), 0.5),
    "tree": ((130, 150), 1.2),
}
FURNITURE_GLOW = {"candelabra": (0.0, 0.0, 1.8), "nightstand": (0.05, 0.05, 1.08), "stove": (0.0, -0.45, 0.5),
                  "dining_table": (0.0, 0.0, 1.28), "stage": (0.0, -1.2, 0.6)}
WALL_KIT = {
    "frame": k_frame, "horns": k_horns, "mirror": k_mirror, "poster": k_poster, "clock": k_clock, "map": k_map,
    "tools": k_tools, "horseshoe": k_horseshoe, "bottles": k_bottles, "keys": k_keys, "cross": k_cross,
    "rifles": k_rifles, "bars": k_bars,
}
FLOOR_DETAILS = {"bottles": d_bottles, "cards": d_cards, "papers": d_papers, "coins": d_coins,
                 "runner": d_runner, "rug_round": d_rug_round}


def render_furniture(only: list[str] | None = None) -> None:
    for k, fn in FURNITURE.items():
        if only and k not in only:
            continue
        fr, tz = FURNITURE_FRAMES[k]
        render_piece("prop_" + k, fn, fr, target_z=tz, glow=FURNITURE_GLOW.get(k))
    for k, fn in WALL_KIT.items():
        if only and "kit_wall_" + k not in only and "wall" not in only:
            continue
        # Vue presque de face : le décor est plaqué sur la face avant (verticale) du mur.
        render_piece("kit_wall_" + k, fn, (70, 80), target_z=1.0, outline_px=3.5, shadow=False, elev=8.0)
    for k, fn in FLOOR_DETAILS.items():
        if only and "decal_" + k not in only and "floor" not in only:
            continue
        fr = (72, 72) if k not in ("rug_round",) else (80, 80)
        if k == "runner":
            fr = (40, 64)
        render_piece("decal_" + k, fn, fr, target_z=0.0, flat=True, outline_px=2.5)


def seed_from_atlas(out_dir: str, pieces_dir: str, skip_prefix: tuple = ("white", "glow")) -> int:
    """Ré-extrait les pièces d'un atlas existant (rect + pieds + point chaud) vers pieces_dir,
    pour pouvoir ré-empaqueter sans re-rendre ce qui existe déjà (sources absentes)."""
    import re
    import ast
    from PIL import Image
    meta_src = open(os.path.join(out_dir, "atlas_meta.gd")).read()
    m = re.search(r"const PIECES := (\{.*\})", meta_src, re.S)
    pieces = ast.literal_eval(m.group(1))
    atlas = Image.open(os.path.join(out_dir, "atlas.png")).convert("RGBA")
    os.makedirs(pieces_dir, exist_ok=True)
    n = 0
    for name, e in pieces.items():
        if name in skip_prefix:
            continue
        x, y, w, h = e["rect"]
        dst = os.path.join(pieces_dir, name + ".png")
        if os.path.exists(dst):
            continue
        atlas.crop((x, y, x + w, y + h)).save(dst)
        info = {"feet": e["feet"], "size": [w, h]}
        for k in ("glow", "anchors"):
            if k in e:
                info[k] = e[k]
        with open(os.path.join(pieces_dir, name + ".json"), "w") as f:
            json.dump(info, f)
        n += 1
    return n


PROPS = {
    "cactus": p_cactus, "barrel": p_barrel, "water_trough": p_water_trough, "hitching_post": p_hitching_post,
    "wagon": p_wagon, "wagon_wheel": p_wagon_wheel, "saloon_bar": p_saloon_bar, "piano": p_piano,
    "poker_table": p_poker_table, "lantern": p_lantern, "rail_track": p_rail_track, "mine_cart": p_mine_cart,
    "support_beam": p_support_beam, "wanted_poster": p_wanted_poster, "water_tower": p_water_tower,
    "tumbleweed": p_tumbleweed, "hay_bale": p_hay_bale, "bed": p_bed, "desk": p_desk, "jail_bars": p_jail_bars,
    "bench": p_bench, "safe": p_safe, "shelf": p_shelf, "counter": p_counter, "pew": p_pew,
    "ore_pile": p_ore_pile, "altar": p_altar,
}
# Décors posés à plat : vue de dessus (même échelle au sol que les cases), sans ombre portée.
FLAT = {"rail_track"}
# Points chauds (lueur additive) en px depuis le point d'appui, par décor (image finale).
GLOW = {"lantern": (0.45, 0.05, 2.0), "piano": (0.0, 0.0, 2.25), "desk": (0.75, 0.25, 1.3), "altar": (0.0, 0.0, 1.8)}


# ----------------------------------------------------------------------------- rendu

def _shadow_objects(B: Builder) -> list[bpy.types.Object]:
    dg = bpy.context.evaluated_depsgraph_get()
    mat = C.toon("_shadow", "#000000", emit=1.0)
    out = []
    for ob in B.objs:
        if ob.name in B.noshadow or ob.type != "MESH":
            continue
        ev = ob.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(ev)
        me.transform(SHEAR @ ob.matrix_world)
        me.materials.clear()
        me.materials.append(mat)
        so = bpy.data.objects.new(ob.name + "_sh", me)
        bpy.context.scene.collection.objects.link(so)
        out.append(so)
    return out


def render_piece(name: str, build_fn, frame_world: tuple[float, float], target_z: float = 1.0,
                 flat: bool = False, outline_px: float = 5.0, glow=None, extra: dict | None = None,
                 shadow: bool = True, elev: float | None = None) -> dict:
    """Construit, rend (objet + ombre), compose et enregistre PIECES/<name>.png (+ .json)."""
    from PIL import Image, ImageFilter
    os.makedirs(PIECES, exist_ok=True)
    C.reset_scene()
    wpx, hpx = int(frame_world[0] * PX_PER_WORLD), int(frame_world[1] * PX_PER_WORLD)
    C.setup_render((wpx * SS, hpx * SS), samples=3, outline_px=outline_px, inner_ratio=0.45)
    B = Builder()
    build_fn(B)
    if elev is None:
        elev = 90.0 if flat else ELEV
    cam = C.ortho_camera(elev, max(wpx, hpx) / PX_PER_BU, target=(0, 0, target_z), dist=30.0)
    bpy.context.view_layer.update()
    feet = C.world_to_px(cam, (0, 0, 0))
    feet = (feet[0] / SS, feet[1] / SS)
    big = os.path.join(PIECES, name + ".big.png")
    C.render_to(big)
    obj = C.downscale(big, None, (wpx, hpx))
    comp = Image.new("RGBA", (wpx, hpx), (0, 0, 0, 0))
    if shadow and not flat:
        for ob in B.objs:
            ob.hide_render = True
        _shadow_objects(B)
        sc = bpy.context.scene
        sc.render.use_freestyle = False
        C.render_to(big)
        sh = C.downscale(big, None, (wpx, hpx)).getchannel("A")
        sh = sh.filter(ImageFilter.GaussianBlur(1.6))
        layer = Image.new("RGBA", (wpx, hpx), SHADOW_RGBA[:3] + (0,))
        layer.putalpha(sh.point(lambda a: a * SHADOW_RGBA[3] // 255))
        comp = Image.alpha_composite(comp, layer)
    comp = Image.alpha_composite(comp, _paint(obj))
    os.remove(big)
    bb = comp.getchannel("A").point(lambda a: 255 if a > 6 else 0).getbbox()
    if bb is None:
        raise RuntimeError("pièce vide : " + name)
    bb = (max(bb[0] - 1, 0), max(bb[1] - 1, 0), min(bb[2] + 1, wpx), min(bb[3] + 1, hpx))
    crop = comp.crop(bb)
    crop.save(os.path.join(PIECES, name + ".png"))
    info = {"feet": [round(feet[0] - bb[0], 1), round(feet[1] - bb[1], 1)], "size": [crop.width, crop.height]}
    if glow is not None:
        gp = C.world_to_px(cam, glow)
        info["glow"] = [round(gp[0] / SS - bb[0], 1), round(gp[1] / SS - bb[1], 1)]
    if extra:
        info.update(extra)
    with open(os.path.join(PIECES, name + ".json"), "w") as f:
        json.dump(info, f)
    print("PIECE", name, info, flush=True)
    return info


def _paint(im):
    """Léger grain « peint » (variation de valeur basse fréquence + bruit fin), alpha intact."""
    import numpy as np
    from PIL import Image
    a = np.asarray(im).astype(np.float32)
    h, w = a.shape[:2]
    rng = np.random.default_rng(h * 31 + w)
    lo = rng.standard_normal((h // 6 + 2, w // 6 + 2)).astype(np.float32)
    lo = np.asarray(Image.fromarray(lo).resize((w, h), Image.BICUBIC))
    fine = rng.standard_normal((h, w)).astype(np.float32)
    k = 1.0 + lo[..., None] * 0.035 + fine[..., None] * 0.02
    a[..., :3] = np.clip(a[..., :3] * k, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


# Cadre de rendu (unités monde : largeur, hauteur) et hauteur visée (BU) par décor.
FRAMES = {
    "cactus": ((150, 150), 1.4), "barrel": ((90, 90), 0.6), "water_trough": ((170, 110), 0.5),
    "hitching_post": ((140, 90), 0.6), "wagon": ((300, 190), 1.0), "wagon_wheel": ((90, 90), 0.7),
    "saloon_bar": ((300, 150), 0.6), "piano": ((150, 150), 0.9), "poker_table": ((150, 130), 0.5),
    "lantern": ((80, 130), 1.3), "rail_track": ((72, 72), 0.0), "mine_cart": ((110, 100), 0.6),
    "support_beam": ((110, 150), 1.5), "wanted_poster": ((100, 120), 1.1), "water_tower": ((190, 280), 2.6),
    "tumbleweed": ((70, 60), 0.4), "hay_bale": ((110, 90), 0.6), "bed": ((110, 130), 0.5),
    "desk": ((140, 110), 0.6), "jail_bars": ((110, 120), 1.4), "bench": ((140, 90), 0.6),
    "safe": ((90, 100), 0.8), "shelf": ((130, 140), 1.2), "counter": ((240, 120), 0.7),
    "pew": ((200, 90), 0.6), "ore_pile": ((100, 80), 0.3), "altar": ((140, 120), 0.8),
}


def render_props(only: list[str] | None = None) -> None:
    for k, fn in PROPS.items():
        if only and k not in only:
            continue
        fr, tz = FRAMES[k]
        render_piece("prop_" + k, fn, fr, target_z=tz, flat=k in FLAT, glow=GLOW.get(k))


# ----------------------------------------------------------------------------- atlas

def pack(atlas_w: int = 2048, pieces_dir: str | None = None, out_name: str = "atlas", extras: bool = True) -> None:
    """Empaquette toutes les pièces (décors, kit de façades, décalques, lueurs) dans un atlas."""
    from PIL import Image
    pieces_dir = pieces_dir or PIECES
    items: list[tuple[str, Image.Image, dict]] = []
    for fn in sorted(os.listdir(pieces_dir)):
        if fn.endswith(".png") and not fn.endswith(".big.png"):
            name = fn[:-4]
            info = {}
            jp = os.path.join(pieces_dir, name + ".json")
            if os.path.exists(jp):
                with open(jp) as f:
                    info = json.load(f)
            items.append((name, Image.open(os.path.join(pieces_dir, fn)).convert("RGBA"), info))
    dec_dir = os.path.join(TMP, "tiles", "decals")
    if extras and os.path.isdir(dec_dir):
        for fn in sorted(os.listdir(dec_dir)):
            if fn.endswith(".png"):
                im = Image.open(os.path.join(dec_dir, fn)).convert("RGBA")
                items.append(("decal_" + fn[:-4], im, {"feet": [im.width / 2, im.height / 2]}))
    if extras:
        items.append(("glow", _glow_sprite(128), {"feet": [64, 64]}))
        items.append(("white", Image.new("RGBA", (8, 8), (255, 255, 255, 255)), {"feet": [4, 4], "inset": 2}))
    # Rangement par étagères (hauteur décroissante), marge 2 px.
    items.sort(key=lambda t: -t[1].height)
    pad = 2
    x = y = shelf = 0
    pos = {}
    for name, im, _ in items:
        if x + im.width + pad > atlas_w:
            x = 0
            y += shelf + pad
            shelf = 0
        pos[name] = (x, y)
        x += im.width + pad
        shelf = max(shelf, im.height)
    h = y + shelf
    H = 1
    while H < h:
        H *= 2
    atlas = Image.new("RGBA", (atlas_w, H), (0, 0, 0, 0))
    meta = {"px_per_world": PX_PER_WORLD, "pieces": {}}
    for name, im, info in items:
        px, py = pos[name]
        atlas.paste(im, (px, py))
        ins = info.get("inset", 0)
        e = {"rect": [px + ins, py + ins, im.width - 2 * ins, im.height - 2 * ins],
             "feet": [round(info.get("feet", [0, 0])[0], 1), round(info.get("feet", [0, 0])[1], 1)]}
        for k in ("glow", "anchors"):
            if k in info:
                e[k] = info[k]
        meta["pieces"][name] = e
    # Pixels quasi transparents -> 0 (compression), mais couleur conservée (pas de franges).
    out = os.path.join(OUT_DIR, out_name + ".png")
    atlas.save(out, optimize=True)
    with open(os.path.join(OUT_DIR, out_name + "_meta.gd"), "w") as f:
        f.write("## Généré par art/blender/build_props.py : NE PAS ÉDITER.\n")
        f.write("## Pièces de assets/sprites/far_west/%s.png : rect [x, y, w, h] (px), feet [x, y]\n" % out_name)
        f.write("## (point d'appui au sol, px depuis le coin du rect), glow (point chaud). 2 px = 1 unité monde.\n")
        f.write("const PIECES := %s\n" % json.dumps(meta["pieces"]))
    print("ATLAS", out, atlas.size, len(items), "pièces")


def _glow_sprite(n: int):
    import numpy as np
    from PIL import Image
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.hypot(xx - n / 2 + 0.5, yy - n / 2 + 0.5) / (n / 2)
    a = np.clip(1 - d, 0, 1) ** 2.2
    img = np.zeros((n, n, 4), np.float32)
    img[..., 0] = 255
    img[..., 1] = 255
    img[..., 2] = 255
    img[..., 3] = a * 255
    return Image.fromarray(img.astype(np.uint8), "RGBA")


def main() -> None:
    """--keep : repart des pièces de l'atlas actuel (aucun re-rendu de l'existant).
    --furniture [--only a,b] : rend le mobilier / décors muraux / détails au sol des gabarits."""
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    if "--landmarks" in args:
        render_landmarks(only)
        pack_landmarks()
        return
    if "--keep" in args:
        print("pièces reprises de l'atlas :", seed_from_atlas(OUT_DIR, PIECES))
    if "--furniture" in args:
        render_furniture(only)
    elif "--pack" not in args:
        render_props(only)
    pack()


if __name__ == "__main__":
    main()
