"""FN P90 HD (Épique), modèle léger fait maison.

Contours et dimensions relevés sur « P90 Submachine Gun Low Poly Game Ready » (JaNaZa_ZaIb, Sketchfab,
licence Standard) : silhouette de profil projetée, retournée (canon vers +X) et mise à 1,7 unité,
puis tracée et simplifiée (constantes ci-dessous). Le modèle Sketchfab ne sert QUE de gabarit : il
n'est ni importé ni livré avec le jeu.
Construction : carcasse = extrusion du contour extérieur, percée (booléens) du trou du pouce, du
pontet et de la fenêtre du viseur ; chargeur, viseur, levier d'armement, détente, canon et
cache-flamme rapportés. Finition d'après la carte d'arsenal de Victor : bleu marine peint, usure
dorée sur les arêtes et éclats d'or.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import weapon_paint as WP  # noqa: E402
from weapons_hd_kit import box, cyl_x, cyl_y, prism, rounded  # noqa: E402

W = 0.17   # largeur de la carcasse

# Contours (x, z) en unités, sens horaire ; face avant coupée en x = 0.672 (le canon est rapporté).
OUTER = [(0.214, 0.331), (0.229, 0.331), (0.233, 0.322), (0.245, 0.322), (0.248, 0.329), (0.264, 0.329),
    (0.267, 0.321), (0.280, 0.321), (0.283, 0.329), (0.296, 0.331), (0.303, 0.321), (0.327, 0.321),
    (0.351, 0.305), (0.462, 0.291), (0.553, 0.291), (0.554, 0.310), (0.551, 0.316), (0.568, 0.317),
    (0.575, 0.291), (0.582, 0.298), (0.601, 0.306), (0.624, 0.296), (0.630, 0.284), (0.625, 0.309),
    (0.633, 0.312), (0.640, 0.305), (0.659, 0.236), (0.672, 0.209), (0.672, 0.090), (0.666, 0.089),
    (0.666, 0.077), (0.672, 0.076), (0.672, 0.003), (0.667, 0.003), (0.659, -0.007), (0.659, -0.039),
    (0.672, -0.042), (0.672, -0.181), (0.634, -0.180), (0.631, -0.111), (0.623, -0.089),
    (0.618, -0.086), (0.554, -0.087), (0.533, -0.106), (0.523, -0.162), (0.504, -0.220),
    (0.468, -0.275), (0.420, -0.312), (0.387, -0.323), (0.308, -0.328), (0.261, -0.319),
    (0.260, -0.301), (0.287, -0.271), (0.287, -0.205), (0.259, -0.158), (0.312, -0.156),
    (0.273, -0.155), (0.275, -0.149), (0.258, -0.151), (0.256, -0.160), (0.225, -0.160),
    (0.206, -0.167), (0.153, -0.223), (0.103, -0.266), (0.043, -0.298), (-0.018, -0.316),
    (-0.189, -0.319), (-0.191, -0.297), (-0.201, -0.281), (-0.307, -0.242), (-0.373, -0.225),
    (-0.381, -0.234), (-0.399, -0.243), (-0.701, -0.243), (-0.702, -0.238), (-0.711, -0.238),
    (-0.851, -0.246), (-0.851, 0.190), (-0.841, 0.199), (-0.356, 0.213), (-0.208, 0.213),
    (-0.202, 0.212), (-0.201, 0.180), (0.131, 0.181), (0.150, 0.250), (0.152, 0.254), (0.162, 0.256),
    (0.175, 0.284), (0.178, 0.306), (0.195, 0.322), (0.210, 0.322), (0.213, 0.330)]
THUMBHOLE = [(-0.111, -0.037), (0.033, -0.037), (0.059, -0.045), (0.084, -0.071), (0.089, -0.099),
    (0.080, -0.119), (-0.032, -0.188), (-0.069, -0.201), (-0.103, -0.198), (-0.135, -0.186),
    (-0.165, -0.157), (-0.172, -0.124), (-0.168, -0.083), (-0.144, -0.049), (-0.121, -0.038),
    (-0.112, -0.038)]
GUARD_HOLE = [(0.310, -0.037), (0.364, -0.037), (0.365, -0.045), (0.406, -0.045), (0.408, -0.048),
    (0.420, -0.064), (0.423, -0.089), (0.422, -0.129), (0.409, -0.156), (0.392, -0.173),
    (0.368, -0.177), (0.345, -0.171), (0.329, -0.156), (0.328, -0.140), (0.316, -0.139),
    (0.300, -0.121), (0.290, -0.074), (0.293, -0.053), (0.309, -0.038)]
SIGHT_WINDOW = [(0.265, 0.241), (0.296, 0.238), (0.567, 0.191), (0.567, 0.182), (0.255, 0.182), (0.266, 0.233),
    (0.265, 0.240)]


def _cw(pts):
    """Sens horaire (attendu par prism) : aire signée négative."""
    a = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
            for i in range(len(pts)))
    return list(pts) if a < 0 else list(reversed(pts))


def _clip_z(pts, z0, keep_above):
    """Polygone coupé par la droite z = z0 (Sutherland-Hodgman) : partie au-dessus ou en dessous."""
    def inside(p):
        return p[1] >= z0 if keep_above else p[1] <= z0
    out = []
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        if inside(a):
            out.append(a)
        if inside(a) != inside(b):
            t = (z0 - a[1]) / (b[1] - a[1])
            out.append((a[0] + t * (b[0] - a[0]), z0))
    return out


def _cut(target, name, pts):
    """Perce une ouverture (contour pts) de part en part : prisme et booléen DIFFERENCE."""
    cutter = prism(name, _cw(pts), W * 3.0, target.data.materials[0])
    cutter.hide_render = True
    cutter.hide_viewport = True
    md = target.modifiers.new(name, "BOOLEAN")
    md.operation = "DIFFERENCE"
    md.solver = "EXACT"
    md.object = cutter


def smg_p90(m):
    navy = WP.paint("p90_navy", "#1b2339", "#04060d", "#4a5e92", wear=0.7, edge="#d9a648", grain=0.1,
                    grain_scale=90.0, alt="#c08f3a", alt_scale=5.0, alt_cut=0.64, rim=0.22)
    navy_dark = WP.paint("p90_navy_dark", "#141a2c", "#04050a", "#3a4668", wear=0.5, edge="#d6a444", grain=0.08)
    gold = m["gold"]
    # Deux étages : bas (crosse, ouvertures) pleine largeur, haut (chargeur, viseur) plus étroit -> marche.
    split = 0.10
    body = prism("body", _cw(_clip_z(OUTER, split + 0.004, False)), W, navy)
    for name, hole in (("thumbhole", THUMBHOLE), ("guardHole", GUARD_HOLE)):
        _cut(body, name, hole)
    rounded(body, 0.014, 2, angle=35.0)
    top = prism("top", _cw(_clip_z(OUTER, split, True)), W * 0.84, navy)
    _cut(top, "sightWindow", SIGHT_WINDOW)
    rounded(top, 0.012, 2, angle=35.0)
    # Panneaux de la crosse (rainures), plaque de couche.
    box("buttSeam", (0.47, W * 1.01, 0.008), (-0.61, 0, 0.006), navy_dark, bevel=0.0)
    box("stockSeam", (0.008, W * 1.01, 0.18), (-0.385, 0, -0.09), navy_dark, bevel=0.0)
    # Chargeur translucide dans son canal (bande gris acier), loquet arrière, fond de chargeur.
    mag_m = WP.paint("p90_mag", "#6a7284", "#1c2030", "#b6c0d4", metal=0.6, gloss=0.3, wear=0.3, grain=0.04)
    rounded(box("mag", (0.67, W * 1.06, 0.10), (0.215, 0, 0.162), mag_m, bevel=0.0), 0.008, 2)
    rounded(box("magRear", (0.22, W * 1.05, 0.14), (-0.235, 0, 0.14), navy_dark, bevel=0.0), 0.01, 2)
    box("magLatch", (0.08, W * 1.08, 0.055), (-0.33, 0, 0.15), gold, bevel=0.006)
    box("magTop", (0.67, W * 1.07, 0.012), (0.215, 0, 0.216), navy_dark, bevel=0.0)
    box("magBottom", (0.67, W * 1.07, 0.012), (0.215, 0, 0.108), navy_dark, bevel=0.0)
    # Viseur : capot, fenêtre vitrée, rail crénelé, anneau de hausse à l'avant.
    box("sightGlass", (0.24, W * 0.5, 0.05), (0.40, 0, 0.255), m["glass"], bevel=0.004)
    C.mesh_obj("ring", C.bm_xform(C.bm_torus(32, 8, 0.03, 0.01), loc=(0.60, 0, 0.285), rot=(0, math.pi / 2, 0)),
               navy_dark)
    # Levier d'armement (avant, côté visible), vis et filets dorés, détente.
    rounded(box("charge", (0.08, 0.04, 0.05), (0.53, -W * 0.56, 0.045), navy_dark), 0.01, 2)
    cyl_y("chargeKnob", 0.016, W * 1.2, (0.53, 0, 0.045), gold, seg=12)
    for (x, z) in ((-0.28, 0.0), (-0.10, -0.08), (0.12, -0.05), (0.40, -0.06), (0.62, 0.0), (-0.60, -0.22)):
        cyl_y("screw", 0.012, W * 1.03, (x, 0, z), gold, seg=12)
    box("goldLine", (0.30, W * 1.01, 0.01), (-0.62, 0, -0.17), gold, bevel=0.0)
    box("goldFront", (0.10, W * 1.01, 0.01), (0.58, 0, -0.07), gold, bevel=0.0)
    C.mesh_obj("trigger", C.bm_tube([(0.235, 0, -0.06), (0.25, 0, -0.10), (0.24, 0, -0.14)], [0.012] * 3, seg=8),
               gold)
    # Canon et cache-flamme (rapportés devant la face avant).
    cyl_x("barrel", 0.022, 0.022, 0.07, (0.705, 0, 0.04), m["steel"], seg=20)
    cyl_x("flash", 0.032, 0.03, 0.13, (0.79, 0, 0.04), navy_dark, seg=20)
    for k in range(3):
        box("flashSlot", (0.07, 0.01, 0.008), (0.79, -0.031, 0.025 + k * 0.015), m["bore"], bevel=0.0)
    cyl_x("muzzleBore", 0.013, 0.013, 0.01, (0.853, 0, 0.04), m["bore"], seg=12)
    return {"grip": (0.19, 0, -0.10), "muzzle": (0.855, 0, 0.04)}


WEAPONS = {"smg_p90": smg_p90}
