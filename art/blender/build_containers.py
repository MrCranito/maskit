"""Conteneurs fouillables Far West en 3D « toon peint » (même pipeline, même angle et mêmes
matériaux que les décors de build_props.py), chacun FERMÉ et OUVERT.

Usage (depuis la racine du projet) :
    python3 art/blender/build_containers.py                  # tous les conteneurs
    python3 art/blender/build_containers.py --only chest,safe

Sorties : assets/sprites/far_west/containers/<kind>.png et <kind>_open.png
          + containers.json : { "<kind>" / "<kind>_open" : {feet: [x, y], size: [w, h]} } (px).
Échelle : 2 px par unité monde (comme l'atlas du décor) ; LootContainer affiche ces images à
l'échelle 0,5 et place le point d'appui (feet) sur l'origine du conteneur.
Repère des modèles : (0, 0, 0) = point d'appui au sol, face avant vers -Y, z vers le haut.
"""
from __future__ import annotations

import json
import math
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_props as P  # noqa: E402
import rdm_common as C  # noqa: E402

M = P.M
Builder = P.Builder
ROOT = P.ROOT
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "far_west", "containers")
TMP = os.environ.get("RDM_TMP", "/tmp/rdm_containers")


def skin():
    return C.toon("skin", "#c88a64", "#5a3a4a", "#f0b088", rim=0.3)


# ----------------------------------------------------------------------------- outils

def _rot_box(B: Builder, name, size, pivot, offset, rot, mat, bevel=0.0, **kw):
    """Boîte décalée de `offset` par rapport au pivot, tournée de `rot` autour du pivot."""
    bm = C.bm_box(*size, bevel=bevel, segs=1)
    C.bm_xform(bm, loc=offset)
    C.bm_xform(bm, loc=pivot, rot=rot)
    return B.add(name, bm, mat, **kw)


def _half_lid(B: Builder, name, w, d, z0, mat, angle=0.0, hinge_y=None):
    """Couvercle bombé (demi-cylindre sur l'axe X) posé à z0 ; `angle` = ouverture autour de la
    charnière arrière (y = d/2, z = z0)."""
    r = d / 2
    secs = []
    for x in (-w / 2, w / 2):
        pts = []
        for k in range(13):
            a = math.pi * k / 12
            pts.append((x, math.cos(a) * r, z0 + math.sin(a) * r * 0.8))
        secs.append(pts)
    bm = C.bm_loft(secs)
    if angle:
        hy = d / 2 if hinge_y is None else hinge_y
        C.bm_xform(bm, loc=(0, -hy, -z0))
        C.bm_xform(bm, loc=(0, hy, z0), rot=(angle, 0, 0))
    return B.add(name, bm, mat, sharp=70)


# ----------------------------------------------------------------------------- conteneurs
# Chaque fonction reçoit (B, opened).

def c_chest(B: Builder, opened: bool) -> None:
    w, d, hb = 1.45, 0.82, 0.52
    B.box("base", (w, d, hb), (0, 0, hb / 2), M("wood"), bevel=0.02)
    for i in range(3):   # lattes horizontales (avant)
        B.box("plank%d" % i, (w - 0.04, 0.03, hb / 3 - 0.02), (0, -d / 2 - 0.01, (i + 0.5) * hb / 3),
              M("wood" if i % 2 == 0 else "plank_light"))
    for sx in (-w / 2 + 0.28, w / 2 - 0.28):
        B.box("band%.1f" % sx, (0.09, d + 0.05, hb + 0.02), (sx, 0, hb / 2), M("iron"))
    for sx in (-w / 2, w / 2):
        B.box("corner%.1f" % sx, (0.1, d + 0.04, 0.12), (sx, 0, 0.06), M("iron_dark"))
    ang = math.radians(-112) if opened else 0.0
    _half_lid(B, "lid", w, d, hb, M("wood_dark"), angle=ang)
    for sx in (-w / 2 + 0.28, w / 2 - 0.28):   # cerclages du couvercle
        pts = []
        for k in range(13):
            a = math.pi * k / 12
            p = (sx, math.cos(a) * (d / 2 + 0.02), hb + math.sin(a) * (d / 2 + 0.02) * 0.8)
            if opened:
                y, z = p[1] - d / 2, p[2] - hb
                c, s = math.cos(ang), math.sin(ang)
                p = (sx, d / 2 + y * c - z * s, hb + y * s + z * c)
            pts.append(p)
        B.tube("lidband%.1f" % sx, pts, [0.035] * 13, M("iron"), seg=5)
    if opened:
        B.box("inside", (w - 0.12, d - 0.12, 0.02), (0, 0, hb - 0.04), M("black"), outline=False)
        for k in range(9):   # pièces d'or
            x = -0.45 + (k % 5) * 0.22
            y = -0.15 + (k // 5) * 0.22
            B.cyl("coin%d" % k, 0.08, 0.08, 0.03, (x, y, hb - 0.01 + (k % 3) * 0.02), M("gold"), seg=10,
                  rot=(0.2 * (k % 2), 0.15, 0), shadow=False)
        B.box("bar", (0.32, 0.14, 0.09), (0.15, 0.1, hb + 0.04), M("gold"), bevel=0.01, rot=(0, 0, 0.3),
              shadow=False)
    else:
        B.box("lock", (0.16, 0.06, 0.2), (0, -d / 2 - 0.04, hb - 0.02), M("brass"), bevel=0.01)
        B.cyl("keyhole", 0.025, 0.025, 0.02, (0, -d / 2 - 0.075, hb - 0.03), M("black"),
              rot=(math.pi / 2, 0, 0), seg=6, outline=False)


def c_crate(B: Builder, opened: bool) -> None:
    w, d, h = 1.15, 0.95, 0.9
    B.box("core", (w - 0.06, d - 0.06, h - 0.04), (0, 0, h / 2), M("wood_dark"))
    B.plank_row("front", -w / 2, w / 2, -d / 2, 0.0, h, 0.05, M("plank_light"), 4, axis="z")
    B.plank_row("side", -d / 2, d / 2, w / 2, 0.0, h, 0.05, M("wood"), 4, axis="z")
    a = math.atan2(h - 0.12, w - 0.12)
    B.box("brace", (math.hypot(w - 0.12, h - 0.12), 0.05, 0.12), (0, -d / 2 - 0.045, h / 2), M("wood"),
          rot=(0, -a, 0))
    for sx in (-w / 2 + 0.05, w / 2 - 0.05):
        B.box("post%.2f" % sx, (0.1, 0.07, h), (sx, -d / 2 - 0.035, h / 2), M("wood"))
    B.box("stencil", (0.34, 0.01, 0.16), (-0.2, -d / 2 - 0.075, h * 0.72), M("black"), outline=False,
          rot=(0, -a, 0))
    if opened:
        B.box("hole", (w - 0.14, d - 0.14, 0.02), (0, 0, h + 0.005), M("black"), outline=False)
        for k in range(10):   # paille
            B.sphere("straw%d" % k, 0.13, (-0.38 + (k % 5) * 0.19, -0.2 + (k // 5) * 0.3, h + 0.02), M("hay"),
                     scale=(1.3, 1, 0.45), seg=8, rings=5)
        for i in range(3):    # planches du couvercle posées contre le flanc gauche
            _rot_box(B, "lid%d" % i, (0.05, d / 3 - 0.02, h * 1.05), (-w / 2 - 0.18, -d / 3 + i * d / 3, 0),
                     (0, 0, h * 0.52), (0, -0.22, 0), M("plank_light"))
    else:
        B.plank_row("top", -w / 2, w / 2, 0, h, h + 0.05, d, M("plank_light"), 3, axis="x", seed=3)


def c_barrel(B: Builder, opened: bool) -> None:
    P.p_barrel(B)
    if opened:
        B.cyl("hole", 0.27, 0.27, 0.02, (0, 0, 1.04), M("black"), seg=20, outline=False)
        B.cyl("liquid", 0.22, 0.22, 0.02, (0, 0, 1.05), M("bottle_b"), seg=20, outline=False)
        lid = C.bm_cyl(20, 0.3, 0.3, 0.05)
        C.bm_xform(lid, loc=(0.42, -0.32, 0.31), rot=(1.25, 0, 0.5))
        B.add("lid", lid, M("wood_dark"))


def _shell(B: Builder, prefix, w, d, h, z0, mat, inner=None, t=0.05):
    """Caisson ouvert à l'avant (dos, flancs, fond, dessus) : l'intérieur reste visible."""
    inner = inner or M("black")
    B.box(prefix + "_back", (w, t, h), (0, d / 2 - t / 2, z0 + h / 2), mat)
    B.box(prefix + "_backin", (w - 2 * t, 0.01, h - 2 * t), (0, d / 2 - t - 0.006, z0 + h / 2), inner, outline=False)
    for sx in (-1, 1):
        B.box(prefix + "_side%d" % sx, (t, d, h), (sx * (w / 2 - t / 2), 0, z0 + h / 2), mat)
    B.box(prefix + "_bottom", (w, d, t), (0, 0, z0 + t / 2), mat)
    B.box(prefix + "_top", (w, d, t), (0, 0, z0 + h - t / 2), mat)


def _doors(B: Builder, w, d, z0, h, opened, mat, knob=True, panel=True, angle=1.95):
    dw = w / 2 - 0.03
    for side in (-1, 1):
        hinge = (side * (w / 2 - 0.02), -d / 2 - 0.03, z0 + h / 2)
        a = side * -angle if opened else 0.0
        _rot_box(B, "door%d" % side, (dw, 0.05, h), hinge, (-side * dw / 2, 0, 0), (0, 0, a), mat)
        if panel:
            _rot_box(B, "panel%d" % side, (dw - 0.14, 0.02, h - 0.18), hinge, (-side * dw / 2, -0.035, 0),
                     (0, 0, a), M("wood_dark"), outline=False)
        if knob:
            _rot_box(B, "knob%d" % side, (0.05, 0.05, 0.12), hinge, (-side * (dw - 0.08), -0.05, 0), (0, 0, a),
                     M("brass"))


def c_cupboard(B: Builder, opened: bool) -> None:
    w, d, h = 1.5, 0.55, 1.05
    if opened:
        _shell(B, "body", w, d, h, 0.06, M("wood_dark"))
    else:
        B.box("body", (w, d, h), (0, 0, h / 2 + 0.06), M("wood_dark"), bevel=0.02)
    B.box("top", (w + 0.1, d + 0.08, 0.06), (0, 0, h + 0.09), M("wood"))
    for sx in (-w / 2 + 0.08, w / 2 - 0.08):
        B.box("foot%.1f" % sx, (0.1, d, 0.08), (sx, 0, 0.04), M("wood_dark"))
    if opened:
        B.box("shelf", (w - 0.1, d - 0.08, 0.04), (0, -0.02, h * 0.55), M("wood"))
        P._bottles(B, "bt", -0.6, 0.0, -0.08, h * 0.57, 4, 11)
        for k in range(3):
            B.cyl("can%d" % k, 0.07, 0.07, 0.16, (0.15 + k * 0.17, -0.1, h * 0.57 + 0.08), M("steel"), seg=10)
        B.box("blanket", (0.7, d - 0.15, 0.22), (0.0, -0.05, 0.25), M("cloth_red"), bevel=0.04)
    _doors(B, w, d, 0.06, h - 0.04, opened, M("wood"))


def c_wardrobe(B: Builder, opened: bool) -> None:
    w, d, h = 1.25, 0.6, 2.1
    if opened:
        _shell(B, "body", w, d, h, 0.08, M("wood_dark"))
    else:
        B.box("body", (w, d, h), (0, 0, h / 2 + 0.08), M("wood_dark"), bevel=0.02)
    B.box("crown", (w + 0.14, d + 0.1, 0.12), (0, 0, h + 0.14), M("wood"), bevel=0.02)
    B.box("base", (w + 0.08, d + 0.06, 0.1), (0, 0, 0.05), M("wood"))
    if opened:
        B.cyl("rod", 0.025, 0.025, w - 0.12, (0, -0.05, h - 0.25), M("brass"), rot=(0, math.pi / 2, 0), seg=8)
        for k, (mat, x) in enumerate((("cloth_red", -0.38), ("cloth_cream", -0.08), ("leather", 0.22))):
            B.box("coat%d" % k, (0.26, 0.2, 0.95), (x, -0.06, h - 0.75), M(mat), bevel=0.05)
        B.box("shelf", (w - 0.1, d - 0.1, 0.04), (0, -0.03, 0.42), M("wood"))
        B.cyl("hat_b", 0.2, 0.2, 0.03, (0.3, -0.05, 0.46), M("black"), seg=14)
        B.cyl("hat_c", 0.12, 0.11, 0.14, (0.3, -0.05, 0.54), M("black"), seg=14)
    _doors(B, w, d, 0.1, h - 0.06, opened, M("wood"), angle=1.25)


def c_safe(B: Builder, opened: bool) -> None:
    if not opened:
        P.p_safe(B)
        return
    w, d, h = 1.0, 0.9, 1.35
    _shell(B, "body", w, d, h, 0.08, M("green_paint"), t=0.1)
    B.box("shelf", (w - 0.24, d - 0.2, 0.04), (0, -0.05, h * 0.55), M("iron_dark"))
    for k in range(3):
        B.box("gold%d" % k, (0.26, 0.12, 0.09), (-0.24 + k * 0.24, -d / 2 + 0.12, h * 0.58 + 0.04),
              M("gold"), bevel=0.01, shadow=False)
    B.box("gold3", (0.26, 0.12, 0.09), (-0.12, -d / 2 + 0.14, h * 0.58 + 0.13), M("gold"), bevel=0.01,
          shadow=False)
    for k in range(4):
        B.box("bills%d" % k, (0.28, 0.16, 0.05), (-0.18 + (k % 2) * 0.34, -d / 2 + 0.16, 0.2 + k // 2 * 0.06),
              M("green_paint"), shadow=False)
    hinge = (-w / 2 + 0.05, -d / 2 - 0.03, h / 2 + 0.08)
    a = 1.95
    _rot_box(B, "door", (w - 0.2, 0.08, h - 0.25), hinge, ((w - 0.2) / 2, 0, 0), (0, 0, a), M("green_paint"),
             bevel=0.02)
    _rot_box(B, "dial", (0.2, 0.06, 0.2), hinge, ((w - 0.2) / 2, -0.07, h * 0.13), (0, 0, a), M("steel"))
    for sx in (-w / 2 + 0.15, w / 2 - 0.15):
        B.box("foot%.1f" % sx, (0.18, d - 0.1, 0.1), (sx, 0, 0.05), M("iron_dark"))


def c_wagon(B: Builder, opened: bool) -> None:
    P.p_wagon(B)
    if opened:   # caisse du chariot ouverte : paille + couvercle posé de travers
        zb = 0.75
        B.box("crate_hole", (0.6, 0.5, 0.02), (-0.2, 0.1, zb + 0.62), M("black"), outline=False, rot=(0, 0, 0.2))
        for k in range(5):
            B.sphere("straw%d" % k, 0.12, (-0.4 + k * 0.1, 0.1 + (k % 2) * 0.1, zb + 0.64), M("hay"),
                     scale=(1.3, 1, 0.45), seg=8, rings=5)
        _rot_box(B, "crate_lid", (0.72, 0.62, 0.05), (0.45, -0.35, zb + 0.75), (0, 0, 0), (0.5, 0.3, 0.6),
                 M("plank_light"))
        B.sphere("sack", 0.22, (0.6, -0.15, zb + 0.25), M("cloth_cream"), scale=(1.2, 0.9, 0.8))


def c_stagecoach(B: Builder, opened: bool) -> None:
    w, d, z0, h = 2.0, 1.15, 0.95, 1.2
    B.box("body", (w, d, h), (0, 0, z0 + h / 2), M("wood_red"), bevel=0.06)
    B.box("belt", (w + 0.04, d + 0.04, 0.1), (0, 0, z0 + 0.12), M("wood_dark"))
    B.box("roof", (w + 0.18, d + 0.14, 0.1), (0, 0, z0 + h + 0.05), M("black"), bevel=0.03)
    for sx in (-w / 2 + 0.38, w / 2 - 0.38):   # fenêtres avant
        B.box("win%.1f" % sx, (0.42, 0.04, 0.4), (sx, -d / 2 - 0.01, z0 + h * 0.65), M("black"), outline=False)
        B.box("frame%.1f" % sx, (0.5, 0.05, 0.48), (sx, -d / 2 + 0.005, z0 + h * 0.65), M("brass"))
    # galerie de toit et malles
    for sy in (-d / 2, d / 2):
        B.cyl("rail%.1f" % sy, 0.025, 0.025, w, (0, sy, z0 + h + 0.25), M("brass"), rot=(0, math.pi / 2, 0), seg=6)
    B.box("trunk1", (0.6, 0.5, 0.32), (-0.45, 0.05, z0 + h + 0.27), M("leather"), bevel=0.03)
    if opened:
        B.box("trunk2", (0.55, 0.45, 0.22), (0.4, 0.0, z0 + h + 0.21), M("leather"), bevel=0.02)
        B.box("trunk2_in", (0.48, 0.38, 0.02), (0.4, 0.0, z0 + h + 0.33), M("black"), outline=False)
        _rot_box(B, "trunk2_lid", (0.55, 0.45, 0.06), (0.4, 0.225, z0 + h + 0.33), (0, -0.225, 0), (-1.9, 0, 0),
                 M("leather"))
    else:
        B.box("trunk2", (0.55, 0.45, 0.3), (0.4, 0.0, z0 + h + 0.26), M("cloth_cream"), bevel=0.03)
    # banc du cocher et timon
    B.box("seat", (0.5, d * 0.9, 0.1), (-w / 2 - 0.25, 0, z0 + 0.7), M("wood_dark"))
    B.box("footboard", (0.5, d * 0.9, 0.06), (-w / 2 - 0.45, 0, z0 + 0.25), M("wood_dark"), rot=(0, 0.5, 0))
    B.tube("tongue", [(-w / 2 - 0.3, 0, 0.8), (-w / 2 - 1.2, -0.05, 0.35), (-w / 2 - 1.5, -0.08, 0.25)],
           [0.07, 0.06, 0.05], M("wood_dark"))
    for (sx, R) in ((-w / 2 + 0.25, 0.6), (w / 2 - 0.25, 0.78)):
        for sy in (-d / 2 - 0.12, d / 2 + 0.12):
            P.wheel(B, "wh%.1f%.1f" % (sx, sy), R, (sx, sy, R), M("iron"), M("wood_red"), axis="y")
    # porte (centre avant) : poignée laiton ; ouverte = pivotée sur la charnière gauche
    hinge = (-0.3, -d / 2 - 0.03, z0 + h * 0.5)
    a = 1.9 if opened else 0.0
    _rot_box(B, "door", (0.6, 0.05, h - 0.15), hinge, (0.3, 0, 0), (0, 0, a), M("wood_red"))
    _rot_box(B, "doorwin", (0.36, 0.03, 0.34), hinge, (0.3, -0.03, h * 0.15), (0, 0, a), M("black"), outline=False)
    _rot_box(B, "handle", (0.05, 0.06, 0.14), hinge, (0.52, -0.05, 0), (0, 0, a), M("brass"))
    if opened:
        B.box("doorway", (0.58, 0.04, h - 0.17), (0.0, -d / 2 - 0.005, z0 + h * 0.5), M("black"), outline=False)
        B.box("seat_in", (0.5, 0.3, 0.12), (0.0, -0.1, z0 + 0.35), M("cloth_red"))


def c_corpse(B: Builder, opened: bool) -> None:
    # Hors-la-loi allongé sur le dos, tête à gauche.
    B.box("torso", (0.62, 0.42, 0.2), (0.0, 0.0, 0.12), M("cloth_red"), bevel=0.06)
    B.box("belt", (0.08, 0.44, 0.21), (0.27, 0.0, 0.12), M("leather"))
    B.sphere("head", 0.15, (-0.45, 0.02, 0.13), skin(), scale=(1, 1, 0.9))
    B.box("bandana", (0.1, 0.26, 0.14), (-0.33, 0.0, 0.13), M("black"), bevel=0.03)
    for sy in (-0.12, 0.12):
        B.tube("leg%.2f" % sy, [(0.3, sy, 0.1), (0.62, sy * 1.3, 0.09), (0.9, sy * 1.5, 0.08)], [0.09, 0.08, 0.075],
               M("wood_grey"))
        B.box("boot%.2f" % sy, (0.2, 0.13, 0.22), (0.98, sy * 1.55, 0.12), M("leather"), bevel=0.03)
    B.tube("armL", [(-0.15, -0.21, 0.13), (0.0, -0.42, 0.08), (0.18, -0.5, 0.06)], [0.07, 0.06, 0.055],
           M("cloth_red"))
    B.tube("armR", [(-0.15, 0.21, 0.13), (-0.35, 0.42, 0.08), (-0.55, 0.45, 0.06)], [0.07, 0.06, 0.055],
           M("cloth_red"))
    # chapeau tombé
    B.cyl("hat_b", 0.24, 0.24, 0.03, (-0.75, -0.3, 0.02), M("wood_dark"), seg=16)
    B.cyl("hat_c", 0.13, 0.12, 0.13, (-0.75, -0.3, 0.09), M("wood_dark"), seg=14)
    if opened:   # sacoche vidée, poches retournées
        B.box("bag", (0.36, 0.26, 0.16), (0.3, -0.52, 0.08), M("leather"), bevel=0.03)
        _rot_box(B, "flap", (0.36, 0.2, 0.03), (0.3, -0.39, 0.16), (0, 0.1, 0), (0.9, 0, 0), M("leather"))
        for k in range(5):
            B.cyl("coin%d" % k, 0.06, 0.06, 0.025, (0.5 + k * 0.09, -0.62 + (k % 2) * 0.1, 0.015), M("gold"), seg=10,
                  shadow=False)
        B.box("pocket", (0.12, 0.1, 0.02), (0.1, 0.24, 0.2), M("cloth_cream"), rot=(0, 0, 0.3))


# kind : (fonction, cadre de rendu (unités monde), hauteur visée en BU)
CONTAINERS = {
    "chest": (c_chest, (110, 110), 0.5),
    "crate": (c_crate, (100, 100), 0.5),
    "barrel": (c_barrel, (90, 90), 0.6),
    "cupboard": (c_cupboard, (120, 110), 0.6),
    "wardrobe": (c_wardrobe, (110, 150), 1.1),
    "wagon": (c_wagon, (300, 200), 1.0),
    "stagecoach": (c_stagecoach, (260, 210), 1.2),
    "safe": (c_safe, (100, 110), 0.8),
    "corpse": (c_corpse, (130, 90), 0.15),
}


def main() -> None:
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    P.PIECES = TMP
    os.makedirs(TMP, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    meta_path = os.path.join(OUT_DIR, "containers.json")
    meta = {}
    if os.path.exists(meta_path):
        with open(meta_path) as f:
            meta = json.load(f)
    for kind, (fn, frame, tz) in CONTAINERS.items():
        if only and kind not in only:
            continue
        for opened in (False, True):
            name = kind + ("_open" if opened else "")
            info = P.render_piece(name, lambda B, o=opened, f=fn: f(B, o), frame, target_z=tz)
            shutil.copy(os.path.join(TMP, name + ".png"), os.path.join(OUT_DIR, name + ".png"))
            meta[name] = {"feet": info["feet"], "size": info["size"]}
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=1, sort_keys=True)
    print("OK", len(meta), "images ->", OUT_DIR)


if __name__ == "__main__":
    main()
