"""Armes HD lourdes : fusils à pompe (870, Benelli M4, AA-12) et mitrailleuses (M249, PKM, M60).

Mêmes repères et mêmes dimensions (en unités) que les anciens modèles de build_weapons.py :
X = canon vers la droite, Z = haut, côté visible = -Y (flanc droit de l'arme : fenêtre d'éjection,
levier d'armement). Références de silhouette : fiches Wikipédia (Remington 870, Benelli M4, Auto
Assault-12, M249, PK machine gun, M60 machine gun) et photos de profil.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import build_weapons as BW  # noqa: E402
import weapon_paint as WP  # noqa: E402
from weapons_hd_kit import (box, cyl_x, cyl_y, grooves, prism, rail, rivets, rounded,  # noqa: E402
                            sphere, tube)


# --------------------------------------------------------------------------- matériaux et briques

def _extra(m):
    """Matériaux propres à la famille (cartouches, boîtes de munitions)."""
    P = WP.paint
    m.setdefault("copper", P("copper", "#c0703a", "#4a2018", "#f0a870", metal=0.85, wear=0.25, grain=0.02))
    m.setdefault("shell_red", P("shell_red", "#b4302a", "#42121c", "#e8604e", gloss=0.35, wear=0.2, grain=0.03))
    m.setdefault("link", P("link", "#4a4c54", "#14141e", "#8a8e9a", metal=0.6, wear=0.4, grain=0.03))
    return m


def _prof(*segs, n=6):
    return BW.curve2d(*segs, n=n)


def rounds(m, pts, r=0.022, L=0.15, bullet="copper", links=True):
    """Bande de cartouches couchées (pointe vers +X) : étui laiton, collet, balle, maillon d'acier."""
    for (x, y, z) in pts:
        cyl_x("case", r, r, L * 0.55, (x, y, z), m["brass"], seg=10)
        cyl_x("rim", r * 1.05, r * 1.05, 0.008, (x - L * 0.275, y, z), m["brass"], seg=10)
        cyl_x("neck", r, r * 0.7, L * 0.12, (x + L * 0.335, y, z), m["brass"], seg=10)
        cyl_x("bullet", r * 0.68, r * 0.15, L * 0.26, (x + L * 0.52, y, z), m[bullet], seg=10)
        if links:
            cyl_x("link", r * 1.18, r * 1.18, L * 0.10, (x - L * 0.10, y, z), m["link"], seg=10)
            cyl_x("link2", r * 1.18, r * 1.18, L * 0.08, (x + L * 0.16, y, z), m["link"], seg=10)


def bipod_folded(m, x, z, length, y=-0.035, mat="dark"):
    """Bipied replié vers l'arrière sous le canon : collier, pieds plats à patin, bouton de réglage."""
    rounded(box("bipYoke", (0.08, 0.11, 0.07), (x, 0, z), m[mat], bevel=0.006), 0.006, 2)
    cyl_y("bipPivot", 0.016, 0.13, (x - 0.01, 0, z - 0.02), m["steel"], seg=10)
    for sy, k in ((y, m[mat]), (-y, m[mat])):
        C.mesh_obj("bipLeg", C.bm_tube([(x - 0.02, sy, z - 0.035), (x - length, sy, z - 0.055)], [0.018, 0.016],
                                      seg=8, flat=0.6, up=(0, 1, 0)), k)
    box("bipFoot", (0.07, 0.03, 0.04), (x - length - 0.01, y, z - 0.06), m["rubber"], bevel=0.008)
    box("bipAdj", (0.03, 0.012, 0.03), (x - length * 0.45, y - 0.016, z - 0.048), m["steel"], bevel=0.003)
    for k in range(3):
        box("bipNotch", (0.008, 0.012, 0.022), (x - length * 0.7 + k * 0.03, y - 0.014, z - 0.05), m["bore"],
            bevel=0.0)


def bipod_deployed(m, x, z, y=0.05, mat="dark", h=0.48, fwd=0.16):
    """Bipied déployé (M60) : deux pieds écartés vers l'avant, patins, entretoise."""
    rounded(box("bipYoke", (0.09, 0.12, 0.08), (x, 0, z), m[mat], bevel=0.006), 0.006, 2)
    cyl_y("bipPivot", 0.018, 0.14, (x, 0, z - 0.03), m["steel"], seg=10)
    for sy in (-y, y):
        C.mesh_obj("bipLeg", C.bm_tube([(x, sy, z - 0.03), (x + fwd * 0.5, sy * 2.0, z - h * 0.5),
                                        (x + fwd, sy * 3.0, z - h)], [0.022, 0.02, 0.018], seg=8), m[mat])
        sphere("bipFoot", 0.032, (x + fwd + 0.01, sy * 3.0, z - h - 0.01), m["rubber"], scale=(1.4, 1, 0.7))
        box("bipClamp", (0.045, 0.05, 0.03), (x + fwd * 0.45, sy * 1.9, z - h * 0.45), m["steel"], bevel=0.004)
    box("bipTelesc", (0.03, 0.03, 0.10), (x + fwd * 0.75, -y * 2.5, z - h * 0.75), m["steel"],
        rot=(0, -0.32, 0), bevel=0.004)


def carry_handle(m, x0, x1, z, h, mat, clamp="dark", r=0.024):
    """Poignée de transport en étrier (montants courts, barre de prise plate) fixée sur le canon."""
    pts = [(x0, 0, z)] + C.bezier((x0 + 0.01, 0, z + h * 0.55), (x0 + 0.02, 0, z + h), (x0 + 0.05, 0, z + h),
                                  (x0 + 0.08, 0, z + h), 4)
    pts += C.bezier((x1 - 0.08, 0, z + h), (x1 - 0.05, 0, z + h), (x1 - 0.02, 0, z + h),
                    (x1 - 0.01, 0, z + h * 0.55), 4) + [(x1, 0, z)]
    tube("handle", pts, r, m[mat], seg=10)
    rounded(box("handleGrip", (x1 - x0 - 0.12, 0.06, r * 2.6), ((x0 + x1) / 2, 0, z + h), m[mat], bevel=0.006),
            0.012, 2)
    grooves(x0 + 0.09, 5, (x1 - x0 - 0.18) / 4, (0.01, 0.064, r * 2.0), z + h, m["bore"])
    rounded(box("handleClamp", (x1 - x0 + 0.04, 0.11, 0.06), ((x0 + x1) / 2, 0, z - 0.01), m[clamp], bevel=0.006),
            0.006, 2)
    cyl_y("handleLatch", 0.018, 0.12, (x0 + 0.02, 0, z - 0.01), m["steel"], seg=10)


def muzzle_slotted(m, x, z, r, L, mat, n=4, slot="bore"):
    """Cache-flamme cylindrique à fentes (vu de profil : fentes longitudinales)."""
    cyl_x("flash", r, r, L, (x + L / 2, 0, z), m[mat], seg=20)
    for k in range(n):
        dz = (k - (n - 1) / 2) * r * 0.55
        box("flashSlot", (L * 0.62, 0.014, r * 0.22), (x + L * 0.56, -r * 0.9 + abs(dz) * 0.3, z + dz), m[slot],
            bevel=0.0)
    cyl_x("flashBore", r * 0.55, r * 0.55, 0.01, (x + L + 0.002, 0, z), m["bore"], seg=16)


def guard_loop(m, x0, x1, z, depth, mat, r=0.016):
    tube("guard", [(x1, 0, z), (x1 - 0.01, 0, z - depth), (x0 + 0.05, 0, z - depth - 0.005),
                   (x0, 0, z - depth + 0.04), (x0 - 0.01, 0, z)], r, m[mat])


# --------------------------------------------------------------------------- Remington 870 (Commun)

def shotgun_870(m):
    m = _extra(m)
    # Carcasse usinée : dessus plat, chute arrière vers la crosse, fenêtre d'éjection, fenêtre de chargement.
    rounded(prism("receiver", [(-0.05, 0.10), (0.56, 0.10), (0.56, 0.335), (0.04, 0.335), (-0.05, 0.305)],
                  0.13, m["blued"]), 0.014, 2)
    box("recLine", (0.58, 0.132, 0.008), (0.255, 0, 0.13), m["dark"], bevel=0.0)
    rounded(box("port", (0.24, 0.012, 0.085), (0.31, -0.064, 0.245), m["bore"], bevel=0.0), 0.006, 2)
    box("bolt", (0.20, 0.014, 0.05), (0.31, -0.063, 0.245), m["steel"], bevel=0.004)
    box("boltCut", (0.03, 0.016, 0.03), (0.37, -0.064, 0.25), m["dark"], bevel=0.0)
    box("loadPort", (0.26, 0.10, 0.02), (0.33, 0, 0.095), m["bore"], bevel=0.0)
    rivets([(0.02, 0.145), (0.40, 0.145)], 0.013, m["steel"], -0.066)
    # Groupe de détente (sous-garde) avec sûreté transversale, détente, arrêtoir de culasse.
    rounded(prism("trigPlate", [(-0.02, 0.10), (0.34, 0.10), (0.30, 0.06), (0.02, 0.06)], 0.11, m["blued"]),
            0.008, 2)
    guard_loop(m, 0.02, 0.28, 0.07, 0.13, "blued", r=0.017)
    tube("trigger", [(0.14, 0, 0.07), (0.155, 0, 0.02), (0.14, 0, -0.03)], 0.014, m["steel"])
    cyl_y("safety", 0.018, 0.13, (0.25, 0, 0.08), m["steel"], seg=12)
    box("slideRel", (0.05, 0.012, 0.02), (0.30, -0.06, 0.085), m["steel"], bevel=0.003)
    # Canon lisse, bague de culasse, couronne, guidon à bille laiton.
    cyl_x("barrel", 0.043, 0.04, 1.40, (1.26, 0, 0.27), m["blued"], seg=24)
    cyl_x("barrelExt", 0.05, 0.05, 0.08, (0.60, 0, 0.27), m["blued"], seg=24)
    cyl_x("crown", 0.042, 0.042, 0.02, (1.95, 0, 0.27), m["steel"], seg=24)
    cyl_x("bore", 0.03, 0.03, 0.01, (1.962, 0, 0.27), m["bore"], seg=16)
    sphere("bead", 0.016, (1.91, 0, 0.318), m["brass"], seg=10)
    # Tube magasin, collier de canon, bouchon moleté, battant de bretelle.
    cyl_x("magTube", 0.044, 0.044, 1.08, (1.10, 0, 0.175), m["blued"], seg=24)
    rounded(box("barrelRing", (0.05, 0.10, 0.12), (1.585, 0, 0.225), m["blued"], bevel=0.006), 0.008, 2)
    cyl_x("magCap", 0.05, 0.05, 0.08, (1.68, 0, 0.175), m["dark"], seg=24)
    grooves(1.655, 4, 0.016, (0.006, 0.104, 0.09), 0.175, m["bore"])
    tube("swivel", [(1.67, 0, 0.13), (1.67, 0, 0.09), (1.71, 0, 0.09), (1.71, 0, 0.13)], 0.008, m["steel"], seg=8)
    # Devant de pompe en bois (rainures annulaires) et barres d'action.
    rounded(prism("pump", _prof(((0.70, 0.13), (0.70, 0.105), (0.74, 0.095), (0.78, 0.095)),
                                (1.10, 0.095), ((1.10, 0.095), (1.14, 0.10), (1.16, 0.12), (1.16, 0.15)),
                                ((1.16, 0.20), (1.16, 0.225), (1.13, 0.235), (1.10, 0.235)),
                                (0.76, 0.235), ((0.76, 0.235), (0.72, 0.235), (0.70, 0.22), (0.70, 0.20))),
                  0.16, m["wood"]), 0.025, 3)
    for k in range(9):
        box("pumpRib", (0.014, 0.164, 0.11), (0.80 + k * 0.035, 0, 0.162), m["wood_dark"], bevel=0.0)
    box("actionBar", (0.16, 0.012, 0.024), (0.63, -0.05, 0.19), m["steel"], bevel=0.003)
    # Crosse bois à demi-poignée pistolet, quadrillage, plaque de couche caoutchouc, battant.
    stock = rounded(prism("stock", _prof((-0.05, 0.305), (-0.05, 0.10),
                                         ((-0.05, 0.10), (-0.12, 0.05), (-0.20, -0.04), (-0.32, -0.045)),
                                         ((-0.32, -0.045), (-0.40, -0.05), (-0.44, -0.03), (-0.50, -0.04)),
                                         (-1.02, -0.19), (-1.02, 0.22),
                                         ((-0.60, 0.235), (-0.30, 0.26), (-0.14, 0.30), (-0.05, 0.305))),
                          0.13, m["wood"]), 0.03, 3)
    stock.name = "stock"
    for k in range(5):
        box("checker", (0.012, 0.134, 0.13), (-0.13 - k * 0.035, 0, 0.11), m["wood_dark"], rot=(0, 0.5, 0),
            bevel=0.0)
        box("checker2", (0.012, 0.134, 0.13), (-0.13 - k * 0.035, 0, 0.11), m["wood_dark"], rot=(0, -0.5, 0),
            bevel=0.0)
    rounded(prism("pad", [(-1.02, -0.20), (-1.02, 0.23), (-1.075, 0.22), (-1.075, -0.19)], 0.135, m["rubber"]),
            0.015, 2)
    box("padSpacer", (0.01, 0.138, 0.42), (-1.025, 0, 0.015), m["white"], bevel=0.0)
    grooves(-1.06, 1, 0.0, (0.06, 0.14, 0.012), 0.12, m["bore"])
    grooves(-1.06, 1, 0.0, (0.06, 0.14, 0.012), -0.04, m["bore"])
    tube("stockSwivel", [(-0.82, 0, -0.12), (-0.82, 0, -0.17), (-0.76, 0, -0.17), (-0.76, 0, -0.105)], 0.008,
         m["steel"], seg=8)
    return {"grip": (-0.24, 0, 0.0), "muzzle": (1.965, 0, 0.27)}


# --------------------------------------------------------------------------- Benelli M4 (Rare)

def shotgun_benelli(m):
    m = _extra(m)
    # Carcasse alu patinée à rail, fenêtre d'éjection, gros levier d'armement à droite, bouton d'arrêtoir.
    rounded(prism("receiver", [(-0.09, 0.10), (0.57, 0.10), (0.60, 0.13), (0.60, 0.33), (0.54, 0.34),
                               (-0.05, 0.34), (-0.09, 0.31)], 0.13, m["gunmetal"]), 0.014, 2)
    box("recLine", (0.62, 0.133, 0.008), (0.25, 0, 0.14), m["dark"], bevel=0.0)
    rounded(box("port", (0.26, 0.012, 0.09), (0.30, -0.064, 0.245), m["bore"], bevel=0.0), 0.006, 2)
    box("bolt", (0.22, 0.014, 0.055), (0.30, -0.063, 0.245), m["steel"], bevel=0.004)
    cyl_y("chargeStem", 0.014, 0.06, (0.36, -0.09, 0.245), m["steel"], seg=10)
    sphere("chargeKnob", 0.032, (0.36, -0.125, 0.245), m["bronze"], scale=(1, 0.7, 1), seg=14)
    box("boltRel", (0.05, 0.014, 0.03), (0.47, -0.064, 0.15), m["bronze"], bevel=0.005)
    box("loadPort", (0.28, 0.10, 0.02), (0.32, 0, 0.095), m["bore"], bevel=0.0)
    rivets([(0.02, 0.17), (0.12, 0.17)], 0.012, m["steel"], -0.066)
    rail(m, -0.05, 0.54, 0.355, 0.075, mat="polymer")
    # Hausse à œilleton fantôme (oreilles de protection) à l'arrière du rail.
    rounded(prism("ghostBase", [(-0.07, 0.37), (0.10, 0.37), (0.08, 0.40), (-0.05, 0.40)], 0.09, m["polymer"]),
            0.006, 2)
    for yy in (-0.038, 0.038):
        rounded(prism("ghostEar", [(-0.04, 0.39), (0.07, 0.39), (0.05, 0.49), (0.0, 0.49)], 0.016, m["polymer"],
                      y=yy), 0.004, 2)
    C.mesh_obj("ghostRing", C.bm_xform(C.bm_torus(16, 8, 0.026, 0.009), loc=(0.02, 0, 0.45),
                                       rot=(1.5708, 0, 0)), m["steel"])
    # Canon, couronne, guidon à ailettes.
    cyl_x("barrel", 0.042, 0.039, 1.00, (1.08, 0, 0.27), m["gunmetal"], seg=24)
    cyl_x("crown", 0.041, 0.041, 0.02, (1.575, 0, 0.27), m["steel"], seg=24)
    cyl_x("bore", 0.03, 0.03, 0.01, (1.587, 0, 0.27), m["bore"], seg=16)
    rounded(box("fsBase", (0.10, 0.09, 0.05), (1.44, 0, 0.32), m["polymer"], bevel=0.006), 0.006, 2)
    for yy in (-0.036, 0.036):
        rounded(prism("fsEar", [(1.40, 0.34), (1.48, 0.34), (1.465, 0.42), (1.425, 0.42)], 0.014, m["polymer"],
                      y=yy), 0.004, 2)
    box("fsPost", (0.016, 0.016, 0.07), (1.44, 0, 0.375), m["dark"], bevel=0.0)
    sphere("fsDot", 0.007, (1.44, -0.009, 0.405), m["led_g"], seg=8)
    # Tube magasin, bouchon, collier de canon avec battant.
    cyl_x("magTube", 0.044, 0.044, 0.96, (1.05, 0, 0.17), m["polymer"], seg=24)
    cyl_x("magCap", 0.05, 0.05, 0.08, (1.53, 0, 0.17), m["dark"], seg=24)
    grooves(1.505, 4, 0.016, (0.006, 0.104, 0.09), 0.17, m["bore"])
    rounded(box("barrelClamp", (0.06, 0.10, 0.14), (1.47, 0, 0.22), m["dark"], bevel=0.006), 0.008, 2)
    cyl_y("clampScrew", 0.012, 0.11, (1.47, 0, 0.21), m["steel"], seg=10)
    tube("swivel", [(1.45, 0, 0.13), (1.45, 0, 0.095), (1.49, 0, 0.095), (1.49, 0, 0.13)], 0.008, m["steel"], seg=8)
    # Garde-main polymère ARGO (pistons), fentes d'aération.
    rounded(prism("forend", _prof((0.60, 0.11), (1.02, 0.11), ((1.02, 0.11), (1.07, 0.11), (1.09, 0.14), (1.09, 0.18)),
                                  ((1.09, 0.22), (1.09, 0.27), (1.06, 0.285), (1.02, 0.29)), (0.60, 0.30)),
                  0.165, m["polymer"]), 0.03, 3)
    for k in range(5):
        rounded(box("forendSlot", (0.06, 0.012, 0.035), (0.68 + k * 0.08, -0.083, 0.20), m["bore"], bevel=0.0),
                0.008, 2)
    box("forendLine", (0.44, 0.168, 0.01), (0.80, 0, 0.145), m["dark"], bevel=0.0)
    box("pistonCap", (0.03, 0.012, 0.05), (0.63, -0.083, 0.255), m["steel"], bevel=0.004)
    # Poignée pistolet texturée, pontet, détente bronze, sûreté.
    rounded(BW.grip("grip", -0.02, 0.11, m["polymer"], h=0.36, w=0.14, slant=0.3), 0.025, 3)
    prism("gripTex", [(-0.05, 0.05), (-0.13, 0.05), (-0.20, -0.20), (-0.12, -0.20)], 0.136, m["polymer_tex"])
    rounded(box("gripCap", (0.15, 0.13, 0.03), (-0.135, 0, -0.245), m["polymer"], bevel=0.008), 0.008, 2)
    rounded(prism("trigPlate", [(-0.03, 0.10), (0.30, 0.10), (0.26, 0.07), (0.0, 0.07)], 0.11, m["gunmetal"]),
            0.008, 2)
    guard_loop(m, 0.0, 0.24, 0.08, 0.13, "gunmetal", r=0.017)
    tube("trigger", [(0.11, 0, 0.08), (0.125, 0, 0.03), (0.11, 0, -0.02)], 0.014, m["bronze"])
    cyl_y("safety", 0.017, 0.13, (0.22, 0, 0.085), m["bronze"], seg=12)
    # Crosse polymère à poignée pistolet : arête de joue, évidement, plaque de couche, battant.
    rounded(prism("stock", _prof((-0.09, 0.31), (-0.09, 0.12), ((-0.16, 0.10), (-0.30, 0.08), (-0.50, 0.04),
                                                                 (-0.62, 0.0)), (-0.84, -0.06), (-0.84, 0.31),
                                 ((-0.60, 0.31), (-0.40, 0.30), (-0.20, 0.33), (-0.09, 0.31))),
                  0.13, m["polymer"]), 0.03, 3)
    rounded(prism("stockRecess", [(-0.30, 0.17), (-0.66, 0.11), (-0.72, 0.22), (-0.36, 0.25)], 0.134,
                  m["dark"]), 0.01, 2)
    box("cheekLine", (0.50, 0.134, 0.01), (-0.50, 0, 0.285), m["bore"], bevel=0.0)
    rounded(box("butt", (0.06, 0.14, 0.38), (-0.87, 0, 0.125), m["rubber"], bevel=0.01), 0.015, 2)
    for zz in (0.02, 0.10, 0.18, 0.26):
        box("buttRib", (0.064, 0.144, 0.01), (-0.87, 0, zz), m["bore"], bevel=0.0)
    tube("stockSwivel", [(-0.74, 0, -0.025), (-0.74, 0, -0.07), (-0.68, 0, -0.07), (-0.68, 0, -0.01)], 0.008,
         m["steel"], seg=8)
    return {"grip": (-0.14, 0, -0.10), "muzzle": (1.59, 0, 0.27)}


# --------------------------------------------------------------------------- AA-12 (Légendaire)

def shotgun_aa12(m):
    m = _extra(m)
    # Corps monobloc dans l'axe (crosse fixe), filets dorés, plaque de couche nervurée.
    body = rounded(prism("body", [(-0.96, 0.34), (-0.96, -0.06), (-0.84, -0.06), (-0.62, 0.07), (-0.24, 0.10),
                                  (0.70, 0.10), (0.76, 0.15), (0.76, 0.36), (0.70, 0.40), (-0.30, 0.40),
                                  (-0.62, 0.38), (-0.90, 0.36)], 0.17, m["legend"]), 0.03, 3)
    body.name = "body"
    box("goldLine", (1.62, 0.176, 0.012), (-0.12, 0, 0.36), m["gold"], bevel=0.0)
    box("goldLine2", (0.92, 0.176, 0.012), (0.24, 0, 0.13), m["gold"], bevel=0.0)
    box("panelLine", (0.01, 0.174, 0.26), (-0.30, 0, 0.25), m["bore"], bevel=0.0)
    box("panelLine2", (0.01, 0.174, 0.26), (0.46, 0, 0.25), m["bore"], bevel=0.0)
    rounded(prism("cheek", [(-0.88, 0.32), (-0.40, 0.33), (-0.44, 0.16), (-0.86, 0.06)], 0.178,
                  m["legend_flat"]), 0.02, 2)
    rivets([(-0.36, 0.20), (-0.36, 0.30), (0.42, 0.20), (0.42, 0.30), (0.66, 0.18)], 0.013, m["gold"], -0.087)
    rounded(box("butt", (0.05, 0.18, 0.42), (-0.985, 0, 0.14), m["rubber"], bevel=0.01), 0.015, 2)
    for zz in (0.0, 0.08, 0.16, 0.24, 0.30):
        box("buttRib", (0.054, 0.184, 0.01), (-0.985, 0, zz), m["bore"], bevel=0.0)
    tube("sling", [(-0.86, 0, -0.04), (-0.86, 0, -0.10), (-0.78, 0, -0.10), (-0.78, 0, -0.01)], 0.012, m["gold"],
         seg=8)
    # Fenêtre d'éjection et levier d'armement (non réciproque) sur le dessus avant.
    rounded(box("port", (0.24, 0.012, 0.08), (0.10, -0.086, 0.27), m["bore"], bevel=0.0), 0.006, 2)
    box("bolt", (0.20, 0.014, 0.045), (0.10, -0.085, 0.27), m["steel"], bevel=0.004)
    rail(m, -0.30, 0.66, 0.415, 0.08, mat="legend_flat")
    # Poignée de transport à hausse intégrée, guidon protégé à l'avant.
    pts = C.bezier((-0.18, 0, 0.43), (-0.14, 0, 0.60), (0.24, 0, 0.60), (0.28, 0, 0.43), 9)
    tube("handle", pts, 0.03, m["legend_flat"], seg=10)
    box("handleTop", (0.30, 0.07, 0.03), (0.05, 0, 0.585), m["legend_flat"], bevel=0.008)
    box("handleGold", (0.28, 0.074, 0.008), (0.05, 0, 0.57), m["gold"], bevel=0.0)
    rounded(prism("rearSight", [(-0.20, 0.43), (-0.10, 0.43), (-0.11, 0.53), (-0.17, 0.53)], 0.07,
                  m["legend_flat"]), 0.008, 2)
    cyl_y("rearAperture", 0.016, 0.074, (-0.14, 0, 0.50), m["bore"], seg=12)
    rounded(prism("fsBase", [(0.58, 0.43), (0.70, 0.43), (0.68, 0.47), (0.60, 0.47)], 0.08, m["legend_flat"]),
            0.006, 2)
    tube("fsHood", [(0.64, -0.035, 0.46), (0.64, -0.035, 0.53), (0.64, 0.035, 0.53), (0.64, 0.035, 0.46)], 0.01,
         m["legend_flat"], seg=8)
    box("fsPost", (0.014, 0.014, 0.06), (0.64, 0, 0.49), m["gold"], bevel=0.0)
    box("chargeH", (0.07, 0.05, 0.05), (0.52, -0.10, 0.36), m["gold"], bevel=0.008)
    # Manchon de canon ventilé, canon, frein de bouche doré à fentes.
    rounded(prism("shroud", [(0.76, 0.12), (1.20, 0.13), (1.24, 0.17), (1.24, 0.33), (1.20, 0.37), (0.76, 0.38)],
                  0.16, m["legend"]), 0.025, 3)
    for k in range(4):
        for zz in (0.21, 0.29):
            cyl_y("vent", 0.026, 0.164, (0.84 + k * 0.10, 0, zz), m["bore"], seg=12)
    box("shroudBand", (0.03, 0.166, 0.27), (0.79, 0, 0.25), m["gold"], bevel=0.0)
    cyl_x("barrel", 0.045, 0.045, 0.16, (1.32, 0, 0.25), m["dark"], seg=24)
    cyl_x("brake", 0.066, 0.062, 0.14, (1.46, 0, 0.25), m["gold"], seg=24)
    for k in range(3):
        box("brakeSlot", (0.025, 0.02, 0.09), (1.42 + k * 0.035, -0.058, 0.25), m["bore"], bevel=0.0)
    cyl_x("muzzleBore", 0.03, 0.03, 0.01, (1.533, 0, 0.25), m["bore"], seg=16)
    # Tambour de 20 coups (douilles rouges visibles par la fenêtre), puits, verrou.
    rounded(box("magwell", (0.26, 0.15, 0.10), (0.30, 0, 0.06), m["legend_flat"], bevel=0.008), 0.01, 2)
    box("feed", (0.16, 0.14, 0.10), (0.30, 0, -0.02), m["legend_flat"], bevel=0.008)
    cyl_y("drum", 0.25, 0.17, (0.30, 0, -0.27), m["legend_flat"], seg=40)
    cyl_y("drumRim", 0.255, 0.12, (0.30, 0, -0.27), m["gold"], seg=40)
    cyl_y("drumFace", 0.215, 0.18, (0.30, 0, -0.27), m["legend"], seg=40)
    import math
    for k in range(10):
        a = k * 2 * math.pi / 10
        box("drumRib", (0.012, 0.184, 0.10), (0.30 + 0.16 * math.cos(a), 0, -0.27 + 0.16 * math.sin(a)),
            m["legend_flat"], rot=(0, -a, 0), bevel=0.0)
    for k in range(5):
        a = 0.4 + k * 0.42
        cyl_y("shellWin", 0.036, 0.186, (0.30 + 0.19 * math.cos(a), 0, -0.27 + 0.19 * math.sin(a)), m["shell_red"],
              seg=14)
        cyl_y("shellBase", 0.022, 0.19, (0.30 + 0.19 * math.cos(a), 0, -0.27 + 0.19 * math.sin(a)), m["brass"],
              seg=12)
    cyl_y("drumHub", 0.07, 0.19, (0.30, 0, -0.27), m["gold"], seg=24)
    cyl_y("drumKey", 0.03, 0.2, (0.30, 0, -0.27), m["legend_flat"], seg=12)
    box("magRel", (0.05, 0.18, 0.03), (0.15, 0, 0.06), m["gold"], bevel=0.006)
    # Poignée, pontet, détente dorée, sûreté.
    rounded(BW.grip("grip", -0.10, 0.11, m["legend_flat"], h=0.36, w=0.15, slant=0.22), 0.025, 3)
    prism("gripTex", [(-0.13, 0.05), (-0.22, 0.05), (-0.28, -0.20), (-0.19, -0.20)], 0.156, m["polymer_tex"])
    guard_loop(m, -0.10, 0.12, 0.10, 0.13, "legend_flat", r=0.018)
    tube("trigger", [(0.0, 0, 0.10), (0.015, 0, 0.05), (0.0, 0, 0.0)], 0.014, m["gold"])
    cyl_y("safety", 0.018, 0.18, (-0.02, 0, 0.20), m["gold"], seg=12)
    for x in (-0.70, -0.52):
        box("goldBand", (0.03, 0.178, 0.24), (x, 0, 0.19), m["gold"], bevel=0.0)
    return {"grip": (-0.22, 0, -0.08), "muzzle": (1.535, 0, 0.25)}


# --------------------------------------------------------------------------- FN M249 (Commun)

def lmg_m249(m):
    m = _extra(m)
    # Boîtier en tôle emboutie, capot d'alimentation à rail, hausse à tambour derrière le capot.
    rounded(prism("receiver", [(-0.28, 0.11), (0.56, 0.11), (0.58, 0.14), (0.58, 0.33), (-0.26, 0.33),
                               (-0.28, 0.30)], 0.15, m["blued"]), 0.012, 2)
    box("recLine", (0.84, 0.152, 0.008), (0.15, 0, 0.16), m["dark"], bevel=0.0)
    rivets([(-0.20, 0.14), (-0.20, 0.29), (0.10, 0.14), (0.40, 0.14), (0.52, 0.29)], 0.012, m["steel"], -0.076)
    rounded(prism("cover", [(-0.20, 0.33), (0.50, 0.33), (0.52, 0.36), (0.46, 0.40), (-0.16, 0.40), (-0.20, 0.38)],
                  0.15, m["polymer"]), 0.012, 2)
    rail(m, -0.12, 0.42, 0.415, 0.07, mat="dark")
    box("coverLatch", (0.05, 0.155, 0.03), (0.47, 0, 0.35), m["steel"], bevel=0.004)
    rounded(box("rsBase", (0.10, 0.09, 0.05), (-0.23, 0, 0.355), m["dark"], bevel=0.006), 0.006, 2)
    prism("rsLeaf", [(-0.27, 0.37), (-0.19, 0.37), (-0.20, 0.46), (-0.25, 0.46)], 0.03, m["dark"])
    cyl_y("rsDrum", 0.028, 0.13, (-0.23, 0, 0.36), m["steel"], seg=14)
    # Fenêtre d'éjection basse, levier d'armement à droite.
    rounded(box("port", (0.22, 0.012, 0.05), (0.18, -0.076, 0.15), m["bore"], bevel=0.0), 0.006, 2)
    box("chargeSlot", (0.24, 0.012, 0.02), (0.40, -0.076, 0.23), m["bore"], bevel=0.0)
    box("chargeH", (0.06, 0.06, 0.05), (0.50, -0.10, 0.23), m["steel"], bevel=0.008)
    # Garde-main inférieur nervuré, bouclier thermique sur le canon.
    rounded(prism("handguard", [(0.58, 0.11), (0.96, 0.12), (0.98, 0.16), (0.98, 0.25), (0.58, 0.26)], 0.17,
                  m["polymer"]), 0.03, 3)
    for k in range(6):
        box("hgRib", (0.022, 0.174, 0.10), (0.63 + k * 0.06, 0, 0.17), m["dark"], bevel=0.0)
    rounded(prism("heatShield", [(0.58, 0.28), (0.98, 0.28), (0.96, 0.32), (0.58, 0.33)], 0.10, m["dark"]),
            0.01, 2)
    for k in range(4):
        rounded(box("heatVent", (0.05, 0.104, 0.018), (0.66 + k * 0.08, 0, 0.30), m["bore"], bevel=0.0),
                0.004, 2)
    # Canon, tube de gaz, bloc de gaz, guidon, cache-flamme.
    cyl_x("barrel", 0.038, 0.036, 1.00, (1.07, 0, 0.27), m["blued"], seg=24)
    cyl_x("gasTube", 0.034, 0.034, 0.40, (1.14, 0, 0.17), m["dark"], seg=20)
    rounded(box("gasBlock", (0.09, 0.09, 0.16), (1.36, 0, 0.215), m["blued"], bevel=0.008), 0.008, 2)
    cyl_y("gasPlug", 0.02, 0.10, (1.36, 0, 0.17), m["steel"], seg=10)
    rounded(box("fsBase", (0.06, 0.07, 0.06), (1.50, 0, 0.31), m["blued"], bevel=0.006), 0.006, 2)
    prism("fsPost", [(1.48, 0.33), (1.52, 0.33), (1.51, 0.42), (1.49, 0.42)], 0.02, m["dark"])
    muzzle_slotted(m, 1.55, 0.27, 0.042, 0.13, "blued")
    carry_handle(m, 0.64, 0.94, 0.32, 0.12, "polymer")
    bipod_folded(m, 1.30, 0.12, 0.40)
    # Boîte de bande souple 200 coups sous le boîtier, sangle, bande qui remonte vers l'alimentation.
    rounded(box("ammoBox", (0.34, 0.20, 0.30), (0.26, 0, -0.06), m["olive"], bevel=0.02), 0.03, 3)
    rounded(box("ammoLid", (0.36, 0.21, 0.05), (0.26, 0, 0.095), m["olive_dark"], bevel=0.01), 0.015, 2)
    box("ammoStrap", (0.04, 0.206, 0.31), (0.18, 0, -0.06), m["canvas"], bevel=0.0)
    box("ammoStrap2", (0.04, 0.206, 0.31), (0.34, 0, -0.06), m["canvas"], bevel=0.0)
    box("ammoLatch", (0.06, 0.03, 0.05), (0.26, -0.105, 0.06), m["dark"], bevel=0.005)
    box("ammoWin", (0.08, 0.012, 0.12), (0.26, -0.102, -0.08), m["olive_dark"], bevel=0.003)
    rounds(m, [(0.10, -0.06, 0.13), (0.10, -0.035, 0.155)], r=0.016, L=0.12)
    # Poignée, pontet, détente.
    rounded(BW.grip("grip", -0.06, 0.12, m["polymer"], h=0.34, w=0.14, slant=0.28), 0.025, 3)
    prism("gripTex", [(-0.09, 0.06), (-0.17, 0.06), (-0.23, -0.17), (-0.15, -0.17)], 0.146, m["polymer_tex"])
    rounded(prism("trigHousing", [(-0.10, 0.12), (0.12, 0.12), (0.10, 0.09), (-0.08, 0.09)], 0.11, m["dark"]),
            0.006, 2)
    guard_loop(m, -0.06, 0.12, 0.10, 0.12, "dark", r=0.016)
    tube("trigger", [(0.04, 0, 0.10), (0.055, 0, 0.05), (0.04, 0, 0.0)], 0.013, m["steel"])
    # Crosse fixe polymère : nervures, plaque de couche, battant.
    rounded(prism("stock", _prof((-0.28, 0.32), (-0.28, 0.12), ((-0.36, 0.11), (-0.50, 0.08), (-0.70, 0.04),
                                                                 (-0.98, 0.0)), (-0.98, 0.34), (-0.56, 0.34)),
                  0.14, m["polymer"]), 0.03, 3)
    for k in range(3):
        rounded(box("stockSlot", (0.10, 0.144, 0.09), (-0.84 + k * 0.15, 0, 0.21), m["dark"], bevel=0.0), 0.02, 2)
    rounded(box("butt", (0.05, 0.15, 0.36), (-1.005, 0, 0.17), m["rubber"], bevel=0.01), 0.012, 2)
    tube("stockSwivel", [(-0.60, 0, 0.06), (-0.60, 0, 0.0), (-0.54, 0, 0.0), (-0.54, 0, 0.07)], 0.008, m["steel"],
         seg=8)
    return {"grip": (-0.16, 0, -0.08), "muzzle": (1.68, 0, 0.27)}


# --------------------------------------------------------------------------- PKM (Rare)

def lmg_pkm(m):
    m = _extra(m)
    # Boîtier d'acier embouti patiné, rivets, nervure longitudinale, capot à hausse avant.
    rounded(prism("receiver", [(-0.28, 0.12), (0.52, 0.12), (0.54, 0.14), (0.54, 0.33), (-0.26, 0.33),
                               (-0.28, 0.31)], 0.14, m["gunmetal"]), 0.01, 2)
    box("recRib", (0.70, 0.146, 0.022), (0.10, 0, 0.22), m["gunmetal"], bevel=0.006)
    rivets([(-0.22, 0.155), (-0.10, 0.155), (0.06, 0.155), (0.24, 0.155), (0.42, 0.155), (-0.22, 0.29),
            (0.48, 0.29)], 0.011, m["steel"], -0.071)
    rounded(prism("cover", [(-0.20, 0.33), (0.40, 0.33), (0.42, 0.36), (0.36, 0.385), (-0.16, 0.385)], 0.144,
                  m["gunmetal"]), 0.01, 2)
    grooves(-0.10, 4, 0.12, (0.012, 0.148, 0.03), 0.37, m["dark"])
    cyl_y("coverHinge", 0.018, 0.15, (0.42, 0, 0.34), m["steel"], seg=12)
    box("coverLatch", (0.04, 0.15, 0.03), (-0.21, 0, 0.36), m["bronze"], bevel=0.004)
    rounded(box("rsBlock", (0.12, 0.08, 0.06), (0.47, 0, 0.36), m["gunmetal"], bevel=0.006), 0.006, 2)
    prism("rsLeaf", [(0.42, 0.39), (0.56, 0.39), (0.56, 0.405), (0.42, 0.42)], 0.05, m["dark"])
    box("rsSlide", (0.035, 0.065, 0.025), (0.48, 0, 0.41), m["bronze"], bevel=0.003)
    # Levier d'armement à droite, glissière, cache-poussière de la fenêtre d'alimentation.
    box("chargeSlot", (0.36, 0.012, 0.02), (0.22, -0.071, 0.18), m["bore"], bevel=0.0)
    rounded(box("chargeH", (0.07, 0.06, 0.05), (0.40, -0.10, 0.18), m["bronze"], bevel=0.008), 0.008, 2)
    box("feedCover", (0.14, 0.012, 0.07), (0.30, -0.072, 0.28), m["dark"], bevel=0.004)
    # Canon fin cannelé, porte-canon, tube de gaz sous le canon, guidon, cache-flamme à fentes.
    cyl_x("barrel", 0.034, 0.032, 1.12, (1.10, 0, 0.27), m["gunmetal"], seg=24)
    BW.flutes(m, 0.84, 0.27, 0.034, 0.44, 4, "dark", phase=0.785, w=0.012, depth=0.012)
    rounded(box("trunnion", (0.08, 0.12, 0.17), (0.57, 0, 0.245), m["gunmetal"], bevel=0.008), 0.008, 2)
    cyl_x("gasTube", 0.03, 0.03, 0.66, (0.90, 0, 0.165), m["gunmetal"], seg=20)
    rounded(box("gasBlock", (0.09, 0.09, 0.16), (1.25, 0, 0.215), m["gunmetal"], bevel=0.008), 0.008, 2)
    cyl_y("gasReg", 0.026, 0.11, (1.25, 0, 0.16), m["bronze"], seg=12)
    rounded(prism("fsBase", [(1.54, 0.29), (1.64, 0.29), (1.63, 0.33), (1.55, 0.33)], 0.07, m["gunmetal"]),
            0.006, 2)
    tube("fsHood", [(1.59, -0.032, 0.32), (1.59, -0.032, 0.42), (1.59, 0.032, 0.42), (1.59, 0.032, 0.32)], 0.009,
         m["gunmetal"], seg=8)
    box("fsPost", (0.012, 0.012, 0.07), (1.59, 0, 0.36), m["dark"], bevel=0.0)
    muzzle_slotted(m, 1.65, 0.27, 0.042, 0.15, "dark", n=3)
    # Poignée de transport (bois stratifié) sur le canon.
    carry_handle(m, 0.62, 0.90, 0.30, 0.12, "wood", clamp="gunmetal", r=0.026)
    bipod_folded(m, 1.20, 0.11, 0.42, mat="gunmetal")
    # Boîte de 100 coups accrochée sous le boîtier (côté droit), bande qui entre dans l'arme.
    rounded(box("ammoBox", (0.30, 0.17, 0.30), (0.26, 0, -0.06), m["olive"], bevel=0.012), 0.01, 2)
    rounded(box("ammoLid", (0.31, 0.175, 0.035), (0.26, 0, 0.085), m["olive_dark"], bevel=0.006), 0.006, 2)
    for zz in (-0.15, -0.06, 0.03):
        box("ammoRib", (0.30, 0.176, 0.012), (0.26, 0, zz), m["olive_dark"], bevel=0.0)
    box("ammoLatch", (0.04, 0.03, 0.06), (0.40, -0.09, 0.05), m["bronze"], bevel=0.005)
    tube("ammoHandle", [(0.18, -0.0, 0.10), (0.18, 0, 0.115), (0.34, 0, 0.115), (0.34, 0, 0.10)], 0.009,
         m["dark"], seg=8)
    rounded(box("ammoMount", (0.16, 0.12, 0.03), (0.26, 0, 0.115), m["gunmetal"], bevel=0.006), 0.006, 2)
    rounds(m, [(0.33, -0.095, 0.145), (0.33, -0.105, 0.18), (0.34, -0.1, 0.215)], r=0.016, L=0.13)
    # Poignée bois, pontet, détente.
    rounded(BW.grip("grip", -0.08, 0.12, m["wood"], h=0.34, w=0.14, slant=0.28), 0.025, 3)
    grooves(-0.15, 4, 0.045, (0.012, 0.144, 0.02), -0.04, m["wood_dark"], rot=(0, 0.28, 0))
    rounded(prism("trigHousing", [(-0.12, 0.12), (0.12, 0.12), (0.10, 0.09), (-0.10, 0.09)], 0.11,
                  m["gunmetal"]), 0.006, 2)
    guard_loop(m, -0.08, 0.10, 0.10, 0.12, "gunmetal", r=0.016)
    tube("trigger", [(0.02, 0, 0.10), (0.035, 0, 0.05), (0.02, 0, 0.0)], 0.013, m["bronze"])
    # Crosse squelette en bois stratifié : barre haute, barre basse, montant arrière, grand évidement.
    rounded(prism("stockTop", [(-0.28, 0.31), (-0.28, 0.20), (-0.90, 0.22), (-0.90, 0.31)], 0.11, m["wood"]),
            0.02, 3)
    rounded(prism("stockLow", [(-0.28, 0.12), (-0.28, 0.20), (-0.45, 0.13), (-0.88, -0.04), (-0.90, -0.10),
                               (-0.78, -0.10), (-0.42, 0.04)], 0.11, m["wood"]), 0.02, 3)
    rounded(prism("stockHeel", [(-0.95, 0.31), (-0.95, -0.10), (-0.84, -0.10), (-0.84, 0.31)], 0.115,
                  m["wood"]), 0.02, 3)
    box("stockSeam", (0.01, 0.117, 0.40), (-0.845, 0, 0.105), m["wood_dark"], bevel=0.0)
    rounded(box("butt", (0.04, 0.13, 0.42), (-0.97, 0, 0.105), m["gunmetal"], bevel=0.006), 0.008, 2)
    rivets([(-0.97, 0.26), (-0.97, -0.05)], 0.011, m["steel"], -0.066)
    rounded(box("buttRest", (0.10, 0.06, 0.03), (-0.88, 0, -0.115), m["gunmetal"], bevel=0.004), 0.004, 2)
    return {"grip": (-0.18, 0, -0.08), "muzzle": (1.80, 0, 0.27)}


# --------------------------------------------------------------------------- M60 (Épique)

def lmg_m60(m):
    m = _extra(m)
    # Boîtier noir, capot d'alimentation gravé, hausse à planchette, levier d'armement.
    rounded(prism("receiver", [(-0.35, 0.11), (0.55, 0.11), (0.57, 0.14), (0.57, 0.33), (-0.33, 0.33),
                               (-0.35, 0.30)], 0.15, m["dark"]), 0.012, 2)
    box("recLine", (0.90, 0.152, 0.008), (0.11, 0, 0.17), m["bore"], bevel=0.0)
    rivets([(-0.28, 0.14), (0.0, 0.14), (0.30, 0.14), (0.50, 0.14), (-0.28, 0.30)], 0.012, m["silver"], -0.076)
    rounded(prism("cover", [(-0.22, 0.33), (0.36, 0.33), (0.38, 0.36), (0.32, 0.40), (-0.18, 0.40),
                            (-0.22, 0.38)], 0.155, m["engraved"]), 0.012, 2)
    cyl_y("coverHinge", 0.02, 0.16, (-0.22, 0, 0.35), m["silver"], seg=12)
    box("coverLatch", (0.04, 0.16, 0.03), (0.36, 0, 0.36), m["silver"], bevel=0.004)
    rounded(box("rsBase", (0.14, 0.09, 0.05), (0.46, 0, 0.355), m["dark"], bevel=0.006), 0.006, 2)
    prism("rsLeaf", [(0.40, 0.38), (0.44, 0.38), (0.50, 0.47), (0.47, 0.48)], 0.04, m["silver"])
    cyl_y("rsKnob", 0.022, 0.13, (0.46, 0, 0.36), m["silver"], seg=12)
    box("chargeSlot", (0.40, 0.012, 0.02), (0.10, -0.076, 0.23), m["bore"], bevel=0.0)
    rounded(box("chargeH", (0.06, 0.07, 0.05), (0.29, -0.10, 0.23), m["silver"], bevel=0.008), 0.008, 2)
    rounded(box("port", (0.18, 0.012, 0.045), (0.02, -0.076, 0.145), m["bore"], bevel=0.0), 0.006, 2)
    # Garde-main beige nervuré sous le canon, colliers laiton.
    rounded(prism("handguard", [(0.57, 0.12), (1.06, 0.12), (1.10, 0.16), (1.10, 0.26), (1.06, 0.29),
                                (0.57, 0.29)], 0.18, m["tan"]), 0.035, 3)
    for k in range(8):
        box("hgRib", (0.022, 0.184, 0.11), (0.64 + k * 0.055, 0, 0.18), m["olive_dark"], bevel=0.0)
    for x in (0.585, 1.08):
        box("hgBand", (0.03, 0.186, 0.17), (x, 0, 0.205), m["brass"], bevel=0.004)
    # Canon argent, poignée de transport sur le canon, cylindre de gaz et bipied déployé, guidon.
    cyl_x("barrel", 0.042, 0.039, 1.14, (1.19, 0, 0.30), m["silver"], seg=24)
    carry_handle(m, 0.74, 1.04, 0.33, 0.14, "dark", clamp="silver", r=0.026)
    cyl_x("gasCyl", 0.042, 0.042, 0.34, (1.28, 0, 0.20), m["dark"], seg=20)
    rounded(box("gasBlock", (0.08, 0.09, 0.13), (1.44, 0, 0.25), m["dark"], bevel=0.008), 0.008, 2)
    cyl_y("gasNut", 0.03, 0.10, (1.44, 0, 0.20), m["silver"], seg=12)
    bipod_deployed(m, 1.40, 0.16)
    rounded(box("fsBase", (0.07, 0.07, 0.05), (1.66, 0, 0.345), m["dark"], bevel=0.006), 0.006, 2)
    prism("fsPost", [(1.645, 0.36), (1.675, 0.36), (1.668, 0.45), (1.652, 0.45)], 0.025, m["dark"])
    # Cache-flamme à griffes (long, fentes ouvertes).
    cyl_x("flashBase", 0.05, 0.05, 0.04, (1.78, 0, 0.30), m["dark"], seg=20)
    for dz in (-0.03, 0.0, 0.03):
        box("prong", (0.13, 0.02 if dz else 0.012, 0.018), (1.865, -0.04 if dz == 0 else -0.035, 0.30 + dz),
            m["dark"], bevel=0.003)
    cyl_x("flashBack", 0.048, 0.048, 0.13, (1.865, 0.02, 0.30), m["dark"], seg=20)
    cyl_x("flashTip", 0.05, 0.05, 0.02, (1.93, 0, 0.30), m["dark"], seg=20)
    cyl_x("flashBore", 0.026, 0.026, 0.01, (1.942, 0, 0.30), m["bore"], seg=16)
    # Bande de laiton qui pend sous le boîtier.
    belt = C.bezier((0.20, 0.03, 0.10), (0.18, 0.03, -0.06), (0.32, 0.03, -0.18), (0.50, 0.03, -0.19), 8)
    rounds(m, belt, r=0.02, L=0.15)
    # Poignée beige, pontet, détente, crosse longue à béquille d'épaule.
    rounded(BW.grip("grip", -0.10, 0.12, m["tan"], h=0.34, w=0.14, slant=0.28), 0.025, 3)
    grooves(-0.17, 4, 0.045, (0.012, 0.144, 0.02), -0.04, m["olive_dark"], rot=(0, 0.28, 0))
    rounded(prism("trigHousing", [(-0.14, 0.12), (0.10, 0.12), (0.08, 0.09), (-0.12, 0.09)], 0.11, m["dark"]),
            0.006, 2)
    guard_loop(m, -0.10, 0.08, 0.10, 0.12, "dark", r=0.016)
    tube("trigger", [(0.0, 0, 0.10), (0.015, 0, 0.05), (0.0, 0, 0.0)], 0.013, m["silver"])
    rounded(prism("stock", _prof((-0.35, 0.32), (-0.35, 0.12), ((-0.42, 0.11), (-0.60, 0.07), (-0.80, 0.03),
                                                                 (-1.08, 0.0)), (-1.08, 0.34), (-0.60, 0.34)),
                  0.15, m["tan"]), 0.035, 3)
    box("stockBand", (0.03, 0.156, 0.25), (-0.48, 0, 0.21), m["brass"], bevel=0.004)
    rounded(box("butt", (0.05, 0.155, 0.36), (-1.105, 0, 0.17), m["dark"], bevel=0.008), 0.01, 2)
    rounded(prism("shoulderRest", [(-1.06, -0.01), (-0.96, 0.01), (-1.00, -0.08), (-1.08, -0.09)], 0.10,
                  m["silver"]), 0.008, 2)
    cyl_y("restHinge", 0.016, 0.12, (-0.98, 0, 0.0), m["dark"], seg=10)
    tube("stockSwivel", [(-0.70, 0, 0.05), (-0.70, 0, -0.01), (-0.64, 0, -0.01), (-0.64, 0, 0.06)], 0.008,
         m["silver"], seg=8)
    return {"grip": (-0.20, 0, -0.08), "muzzle": (1.945, 0, 0.30)}


WEAPONS = {"shotgun_870": shotgun_870, "shotgun_benelli": shotgun_benelli, "shotgun_aa12": shotgun_aa12,
           "lmg_m249": lmg_m249, "lmg_pkm": lmg_pkm, "lmg_m60": lmg_m60}
