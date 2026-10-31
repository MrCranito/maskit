"""FN P90 HD (Épique) d'après le vrai : bullpup de 50,5 × 21 cm (hauteur = 0,42 × longueur), carcasse
très arrondie percée de deux ouvertures (trou du pouce, puis grand pontet qui sert de poignée avant
avec son arrêtoir), chargeur translucide de 50 coups couché sur le dessus (cartouches en travers,
vues par leur culot), viseur reflex intégré à l'avant du dessus, canon court à cache-flamme biseauté,
leviers d'armement de part et d'autre sous le viseur, éjection vers le bas derrière la poignée.
Teinte « FDE » (beige) de l'Épique, viseur et canon noirs. Longueur 1,7 unité comme l'ancien modèle.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
from weapons_hd_kit import box, cyl_x, cyl_y, prism, rounded  # noqa: E402

W = 0.19   # largeur de la carcasse (5,5 cm)


def _bar(name, pts, r, mat, yscale=1.8):
    """Barre de carcasse moulée : tube à section ovale (aussi large que la carcasse)."""
    bm = C.bm_tube(pts, [r] * len(pts), seg=14)
    C.bm_xform(bm, scale=(1.0, yscale, 1.0))
    return C.mesh_obj(name, bm, mat)


def smg_p90(m):
    body_m, dark_m = m["tan"], m["legend_flat"]
    # Corps : de la plaque de couche (gauche) au nez sous le viseur, dessus plat sous le chargeur.
    rounded(prism("body", [(-0.73, -0.07), (-0.74, 0.17), (-0.69, 0.235), (-0.61, 0.26), (-0.58, 0.14),
                           (0.30, 0.14), (0.62, 0.15), (0.73, 0.11), (0.80, 0.045), (0.79, -0.05),
                           (0.62, -0.11), (0.46, -0.13), (-0.60, -0.13)], W, body_m), 0.05, 4)
    # Dessous : barre arrière (plaque de couche -> bas du trou du pouce -> pied de la poignée) puis
    # pontet-poignée avant qui remonte vers l'arrêtoir.
    # Le bas arrière est plein jusqu'au trou du pouce (petit ovale) ; le pontet est grand.
    rounded(prism("rearLow", [(-0.73, -0.06), (-0.46, -0.12), (-0.44, -0.20), (-0.50, -0.27), (-0.62, -0.27),
                              (-0.71, -0.20)], W, body_m), 0.05, 4)
    pts = C.bezier((-0.56, 0, -0.26), (-0.42, 0, -0.34), (-0.26, 0, -0.34), (-0.14, 0, -0.315), 10)
    _bar("rearBar", pts, 0.055, body_m)
    pts = C.bezier((-0.14, 0, -0.31), (0.18, 0, -0.35), (0.46, 0, -0.32), (0.51, 0, -0.14), 12)
    _bar("guard", pts, 0.058, body_m)
    _bar("guardTop", [(0.51, 0, -0.14), (0.54, 0, -0.10)], 0.06, body_m)
    # Arrêtoir de main à l'avant du pontet.
    rounded(prism("handstop", [(0.47, -0.24), (0.56, -0.20), (0.58, -0.14), (0.52, -0.12), (0.46, -0.17)], W * 0.9,
                  body_m), 0.02, 3)
    # Poignée : barre inclinée entre le trou du pouce et le pontet (pied en arrière).
    rounded(prism("grip", [(-0.06, -0.10), (0.09, -0.10), (-0.02, -0.31), (-0.17, -0.31)], W * 0.92, body_m),
            0.05, 4)
    # Détente et sélecteur rotatif (disque sous la détente).
    C.mesh_obj("trigger", C.bm_tube([(0.12, 0, -0.11), (0.145, 0, -0.16), (0.13, 0, -0.20)], [0.017] * 3, seg=8),
               dark_m)
    # Goulotte d'éjection (sous le corps, derrière la poignée), plaque de couche caoutchouc.
    box("chute", (0.14, W * 0.6, 0.02), (-0.26, 0, -0.125), m["bore"], bevel=0.004)
    rounded(prism("buttpad", [(-0.76, -0.05), (-0.72, -0.07), (-0.72, 0.17), (-0.76, 0.16)], W * 1.02,
                  m["rubber"]), 0.012, 2)
    # Chargeur translucide fumé couché sur le dessus, cartouches en travers vues par leur culot.
    mz0, mz1 = 0.14, 0.27
    rounded(box("mag", (1.06, W * 0.86, mz1 - mz0), (-0.07, 0, (mz0 + mz1) / 2), m["smoke"], bevel=0.0), 0.02, 3)
    rounded(box("magRear", (0.07, W * 0.88, mz1 - mz0 + 0.01), (-0.57, 0, (mz0 + mz1) / 2), dark_m), 0.015, 2)
    for k in range(18):
        x = -0.50 + k * 0.047
        for row, z in enumerate((0.175, 0.232)):
            xx = x + (0.0235 if row else 0.0)
            if xx > 0.30:
                continue
            cyl_y("round", 0.018, W * 0.875, (xx, 0, z), m["brass"], seg=12)
            cyl_y("primer", 0.006, W * 0.88, (xx, 0, z), m["bronze"], seg=8)
    # Viseur reflex intégré (dessus avant) : boîtier noir, lentille avant, hausses de secours.
    # Boîtier du viseur moulé avec la carcasse, incliné vers l'arrière ; fenêtres sombres.
    rounded(prism("sight", [(0.22, 0.14), (0.70, 0.14), (0.72, 0.20), (0.64, 0.38), (0.40, 0.40),
                            (0.30, 0.30)], W * 0.86, body_m), 0.045, 4)
    rounded(prism("sightWin", [(0.42, 0.30), (0.60, 0.30), (0.62, 0.34), (0.44, 0.36)], W * 0.9, dark_m), 0.01, 2)
    cyl_x("lensF", 0.05, 0.05, 0.012, (0.69, 0, 0.27), m["glass"], seg=24)
    cyl_x("lensRing", 0.06, 0.06, 0.012, (0.685, 0, 0.27), dark_m, seg=24)
    for x in (0.34, 0.58):
        box("ironSight", (0.04, 0.03, 0.04), (x, -W * 0.46, 0.39), dark_m, bevel=0.006)
    box("sightScrew", (0.03, 0.01, 0.03), (0.46, -W * 0.415, 0.24), m["steel"], bevel=0.004)
    # Leviers d'armement (de part et d'autre, sous le viseur) et vis de carcasse.
    rounded(box("charge", (0.09, 0.04, 0.035), (0.56, -W * 0.55, 0.09), dark_m), 0.01, 2)
    for (x, z) in ((-0.48, 0.02), (0.30, 0.04), (-0.62, -0.02)):
        cyl_y("screw", 0.014, W * 1.02, (x, 0, z), dark_m, seg=12)
    # Anneaux de bretelle.
    cyl_y("sling", 0.022, W * 1.08, (-0.66, 0, 0.06), m["steel"], seg=14)
    # Canon court et cache-flamme biseauté (coupe en diagonale).
    cyl_x("barrel", 0.032, 0.032, 0.10, (0.83, 0, 0.03), m["blued"], seg=20)
    rounded(prism("flash", [(0.86, -0.012), (0.95, -0.012), (0.99, 0.072), (0.86, 0.072)], 0.088, dark_m), 0.012, 2)
    for k in range(2):
        box("flashSlot", (0.05, 0.092, 0.012), (0.915, 0, 0.012 + k * 0.032), m["bore"], bevel=0.0)
    cyl_x("muzzleBore", 0.016, 0.016, 0.01, (0.985, 0, 0.03), m["bore"], seg=12)
    return {"grip": (-0.07, 0, -0.20), "muzzle": (0.99, 0, 0.03)}


WEAPONS = {"smg_p90": smg_p90}
