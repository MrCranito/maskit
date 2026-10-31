"""FN P90 HD (Épique) d'après l'image de référence de Victor (carte d'arsenal « P90 · Épique ») :
- bloc compact et anguleux, dessus plat et continu, face avant verticale, canon court qui sort haut ;
- carcasse inférieure épaisse percée de deux ouvertures ovales (booléens) : trou du pouce à l'arrière,
  grand pontet à l'avant, séparés par la poignée ;
- chargeur intégré au dessus : bande d'acier sombre à fenêtre claire ;
- viseur surélevé à l'avant du dessus, anneau de visée arrière ;
- bleu marine peint, usure dorée sur les arêtes et éclats d'or (finition de l'Épique).
Longueur 1,7 unité comme l'ancien modèle.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import weapon_paint as WP  # noqa: E402
from weapons_hd_kit import box, cyl_x, cyl_y, prism, rounded  # noqa: E402

W = 0.19   # largeur de la carcasse


def _cut(target, name, x, z, rx, rz, rot=0.0):
    """Perce une ouverture ovale de part en part (cylindre d'axe Y, booléen DIFFERENCE)."""
    bm = C.bm_cyl(48, 1.0, 1.0, W * 3.0)
    C.bm_xform(bm, rot=(math.pi / 2, 0, 0))
    C.bm_xform(bm, scale=(rx, 1.0, rz))
    C.bm_xform(bm, rot=(0, rot, 0), loc=(x, 0, z))
    cutter = C.mesh_obj(name, bm, target.data.materials[0])
    cutter.hide_render = True
    cutter.hide_viewport = True
    md = target.modifiers.new(name, "BOOLEAN")
    md.operation = "DIFFERENCE"
    md.solver = "EXACT"
    md.object = cutter
    return cutter


def smg_p90(m):
    navy = WP.paint("p90_navy", "#1d2540", "#05070f", "#45547c", wear=0.75, edge="#e0ae4c", grain=0.09,
                    grain_scale=90.0, alt="#c9973e", alt_scale=6.0, alt_cut=0.6)
    navy_dark = WP.paint("p90_navy_dark", "#151a2c", "#040509", "#34405e", wear=0.55, edge="#d6a444", grain=0.08)
    gold = m["gold"]
    # Carcasse : dessus plat, plaque de couche verticale, dessous qui descend vers le pontet puis remonte
    # vers la face avant.
    body = prism("body", [(-0.72, 0.25), (0.74, 0.25), (0.78, 0.21), (0.78, 0.02), (0.70, -0.10), (0.58, -0.22),
                          (0.42, -0.28), (0.25, -0.30), (0.05, -0.29), (-0.18, -0.25), (-0.50, -0.22),
                          (-0.66, -0.19), (-0.72, -0.12)], W, navy)
    # Trou du pouce (arrière) et grand pontet (avant), séparés par la poignée.
    _cut(body, "thumbhole", -0.17, -0.07, 0.13, 0.10, rot=-0.25)
    _cut(body, "guardHole", 0.26, -0.10, 0.20, 0.14, rot=0.12)
    rounded(body, 0.03, 3)
    # Filets dorés et rainure de plaque arrière.
    box("goldLine", (0.36, W * 1.01, 0.012), (-0.50, 0, 0.0), gold, bevel=0.0)
    box("buttLine", (0.012, W * 1.01, 0.30), (-0.66, 0, 0.06), m["bore"], bevel=0.0)
    # Détente au fond du pontet.
    C.mesh_obj("trigger", C.bm_tube([(0.13, 0, 0.05), (0.15, 0, 0.0), (0.135, 0, -0.04)], [0.016] * 3, seg=8), gold)
    # Chargeur intégré au dessus : bande sombre, fenêtre claire (corps translucide), embouts.
    rounded(box("mag", (1.10, W * 0.9, 0.09), (-0.08, 0, 0.29), navy_dark, bevel=0.0), 0.015, 2)
    box("magWindow", (0.90, W * 0.92, 0.04), (-0.07, 0, 0.29), m["steel"], bevel=0.006)
    box("magLatch", (0.06, W * 0.95, 0.05), (-0.60, 0, 0.30), m["gold"], bevel=0.006)
    # Viseur surélevé à l'avant : bloc, lentille, anneau de visée arrière, guidon.
    rounded(prism("sight", [(0.18, 0.33), (0.80, 0.33), (0.80, 0.40), (0.70, 0.47), (0.30, 0.47), (0.22, 0.42)],
                  W * 0.7, navy), 0.02, 3)
    cyl_x("lens", 0.045, 0.045, 0.012, (0.805, 0, 0.40), m["glass"], seg=24)
    box("sightWin", (0.30, W * 0.72, 0.03), (0.47, 0, 0.42), m["glass"], bevel=0.004)
    C.mesh_obj("ring", C.bm_xform(C.bm_torus(32, 8, 0.05, 0.014), loc=(0.68, 0, 0.53), rot=(0, math.pi / 2, 0)),
               navy_dark)
    box("ringPost", (0.03, 0.03, 0.05), (0.68, 0, 0.485), navy_dark, bevel=0.004)
    box("frontSight", (0.025, 0.03, 0.05), (0.32, 0, 0.495), navy_dark, bevel=0.004)
    # Levier d'armement doré (côté visible) et vis dorées.
    rounded(box("charge", (0.08, 0.04, 0.04), (0.60, -W * 0.56, 0.17), gold), 0.01, 2)
    for (x, z) in ((-0.40, 0.18), (0.10, 0.18), (0.52, -0.06), (-0.62, -0.08)):
        cyl_y("screw", 0.016, W * 1.03, (x, 0, z), gold, seg=12)
    # Canon court qui sort haut de la face avant, cache-flamme.
    cyl_x("barrel", 0.034, 0.034, 0.12, (0.84, 0, 0.16), m["steel"], seg=20)
    cyl_x("flash", 0.045, 0.042, 0.08, (0.93, 0, 0.16), navy_dark, seg=20)
    cyl_x("muzzleBore", 0.018, 0.018, 0.01, (0.972, 0, 0.16), m["bore"], seg=12)
    return {"grip": (0.02, 0, -0.12), "muzzle": (0.975, 0, 0.16)}


WEAPONS = {"smg_p90": smg_p90}
