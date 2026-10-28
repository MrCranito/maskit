"""Décors Far West en 3D « toon peint » (même pipeline et même angle que le héros) + atlas unique.

Usage (depuis la racine du projet ; ordre complet de régénération du décor) :
    python3 art/blender/build_tiles.py        # sols, murs, toits, décalques (numpy)
    python3 art/blender/build_buildings.py    # kit de façades (auvents, poteaux, bannières...)
    python3 art/blender/build_props.py        # décors + empaquetage de TOUT dans l'atlas
    python3 art/blender/build_props.py --only cactus,barrel   # re-rendre quelques décors puis empaqueter
    python3 art/blender/build_props.py --pack                  # empaqueter seulement

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

    def tube(self, name, path, radii, mat, seg=8, **kw):
        bm = C.bm_tube(path, radii, seg=seg)
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
                 shadow: bool = True) -> dict:
    """Construit, rend (objet + ombre), compose et enregistre PIECES/<name>.png (+ .json)."""
    from PIL import Image, ImageFilter
    os.makedirs(PIECES, exist_ok=True)
    C.reset_scene()
    wpx, hpx = int(frame_world[0] * PX_PER_WORLD), int(frame_world[1] * PX_PER_WORLD)
    C.setup_render((wpx * SS, hpx * SS), samples=3, outline_px=outline_px, inner_ratio=0.45)
    B = Builder()
    build_fn(B)
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

def pack(atlas_w: int = 2048) -> None:
    """Empaquette toutes les pièces (décors, kit de façades, décalques, lueurs) dans un atlas."""
    from PIL import Image
    items: list[tuple[str, Image.Image, dict]] = []
    for fn in sorted(os.listdir(PIECES)):
        if fn.endswith(".png") and not fn.endswith(".big.png"):
            name = fn[:-4]
            info = {}
            jp = os.path.join(PIECES, name + ".json")
            if os.path.exists(jp):
                with open(jp) as f:
                    info = json.load(f)
            items.append((name, Image.open(os.path.join(PIECES, fn)).convert("RGBA"), info))
    dec_dir = os.path.join(TMP, "tiles", "decals")
    if os.path.isdir(dec_dir):
        for fn in sorted(os.listdir(dec_dir)):
            if fn.endswith(".png"):
                im = Image.open(os.path.join(dec_dir, fn)).convert("RGBA")
                items.append(("decal_" + fn[:-4], im, {"feet": [im.width / 2, im.height / 2]}))
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
    out = os.path.join(OUT_DIR, "atlas.png")
    atlas.save(out, optimize=True)
    with open(os.path.join(OUT_DIR, "atlas_meta.gd"), "w") as f:
        f.write("## Généré par art/blender/build_props.py : NE PAS ÉDITER.\n")
        f.write("## Pièces de assets/sprites/far_west/atlas.png : rect [x, y, w, h] (px), feet [x, y]\n")
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
    args = sys.argv[1:]
    if "--pack" not in args:
        only = args[args.index("--only") + 1].split(",") if "--only" in args else None
        render_props(only)
    pack()


if __name__ == "__main__":
    main()
