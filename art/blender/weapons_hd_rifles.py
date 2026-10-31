"""Armes HD, famille fusils d'assaut et fusils de précision : M4A1 (Rare), SCAR-H (Épique), M24 (Commun),
AX50 (Rare), Barrett M82 (Épique).

Mêmes conventions que weapons_hd_base.py (témoins validés) : X = canon vers la droite, Z = haut,
côté visible = -Y (flanc droit de l'arme : fenêtre d'éjection, levier de culasse, bouton de chargeur).
Dimensions reprises des anciens modèles (build_weapons.py), silhouettes d'après les armes réelles :
- Colt M4A1 : 838 mm, canon 14,5 po ; carcasses supérieure/inférieure, rail Picatinny plat, garde-main RIS,
  guidon en A, cache-flamme A2, crosse télescopique, chargeur STANAG légèrement courbe ;
- FN SCAR-H (Mk 17) : 965 mm, canon 16 po ; long boîtier supérieur carré à rail continu, rails latéraux et
  inférieur à l'avant, puits de chargeur évasé, crosse pliante réglable, chargeur droit de 20 ;
- Remington M24 : 1 092 mm, canon 24 po ; boîtier cylindrique Remington 700, crosse H-S Precision
  PST-024 (poignée quasi verticale, busc haut, devant large), lunette Leupold Mk 4 ;
- Accuracy International AX50 : 1 370 mm, canon 27 po ; châssis aluminium, rail continu, garde-main
  ajouré, crosse squelette pliante réglable (busc, plaque de couche, monopied), frein de bouche massif ;
- Barrett M82A1 : 1 448 mm, canon 29 po cannelé ; énorme boîtier supérieur en tôle percé à l'avant,
  frein de bouche à double chambre, bipied, poignée de transport repliable, chargeur de 10.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import build_weapons as BW  # noqa: E402
import weapon_paint as WP  # noqa: E402
from weapons_hd_kit import (box, cyl_x, cyl_y, grooves, prism, rail, rivets, rounded,  # noqa: E402
                            sphere, tube)


# --------------------------------------------------------------------------- briques de la famille

def screw(m, x, z, y, r=0.012, mat="steel", slot="bore"):
    """Tête de vis (disque posé sur la face visible) avec sa fente."""
    cyl_y("screw", r, 0.008, (x, y, z), m[mat], seg=14)
    box("slot", (r * 1.5, 0.004, r * 0.32), (x, y - 0.005, z), m[slot], rot=(0, 0.6, 0), bevel=0.0)


def rail_down(m, x0, x1, z, depth=0.08, mat="dark"):
    """Rail Picatinny sous l'arme (créneaux vers le bas)."""
    box("railD", (x1 - x0, depth, 0.03), ((x0 + x1) / 2, 0, z), m[mat], bevel=0.004)
    for k in range(int((x1 - x0) / 0.05)):
        box("railDT", (0.026, depth + 0.006, 0.022), (x0 + 0.025 + k * 0.05, 0, z - 0.024), m[mat], bevel=0.004)


def rail_side(m, x0, x1, z, y, mat="dark", h=0.05):
    """Rail Picatinny latéral sur la face visible (créneaux vers -Y)."""
    box("railS", (x1 - x0, 0.02, h), ((x0 + x1) / 2, y, z), m[mat], bevel=0.004)
    for k in range(int((x1 - x0) / 0.05)):
        box("railST", (0.026, 0.018, h + 0.014), (x0 + 0.025 + k * 0.05, y - 0.014, z), m[mat], bevel=0.004)


def scope(m, x0, x1, z, r=0.05, ro=0.085, base_z=None, body="polymer", ring="dark", turret="dark",
          rings=None, sunshade=0.0):
    """Lunette détaillée : bonnette caoutchouc, oculaire, bague de grossissement striée, corps, tourelles
    (élévation dessus, dérive côté visible), objectif évasé, verres, colliers sur embases de rail."""
    L = x1 - x0
    ri = r * 1.45
    # Oculaire : bonnette, cloche, bague de grossissement.
    cyl_x("eyecup", ri * 1.02, ri * 1.02, 0.05, (x0 + 0.025, 0, z), m["rubber"], seg=28)
    cyl_x("ocular", ri, ri * 0.95, 0.11, (x0 + 0.105, 0, z), m[body], seg=28)
    cyl_x("ocularT", ri * 0.95, r * 1.05, 0.05, (x0 + 0.185, 0, z), m[body], seg=28)
    cyl_x("power", r * 1.22, r * 1.22, 0.07, (x0 + 0.245, 0, z), m[body], seg=28)
    for k in range(5):
        box("powerRib", (0.008, 0.012, r * 1.4), (x0 + 0.218 + k * 0.013, -r * 1.2, z), m["bore"], bevel=0.0)
    cyl_x("lensB", ri * 0.82, ri * 0.82, 0.008, (x0 - 0.002, 0, z), m["glass"], seg=28)
    # Corps.
    xt0, xt1 = x0 + 0.28, x1 - 0.30 - sunshade
    cyl_x("tube", r, r, xt1 - xt0, ((xt0 + xt1) / 2, 0, z), m[body], seg=28)
    # Selle des tourelles, tourelle d'élévation striée, tourelle de dérive côté visible.
    xc = x0 + 0.28 + (xt1 - xt0) * 0.42
    rounded(box("saddle", (0.15, r * 2.3, r * 2.1), (xc, 0, z), m[body], bevel=0.02), 0.01, 2)
    BW.cyl_z("elevB", r * 0.75, r * 0.75, r * 0.5, (xc, 0, z + r * 1.25), m[body], seg=24)
    BW.cyl_z("elev", r * 0.82, r * 0.82, r * 0.75, (xc, 0, z + r * 1.85), m[turret], seg=24)
    for k in range(7):
        a = math.radians(-60 + k * 20)
        box("elevKn", (0.006, 0.01, r * 0.62), (xc + math.sin(a) * r * 0.82, -math.cos(a) * r * 0.82,
                                                 z + r * 1.85), m["bore"], rot=(0, 0, -a), bevel=0.0)
    BW.cyl_z("elevCap", r * 0.6, r * 0.5, 0.012, (xc, 0, z + r * 2.28), m[turret], seg=20)
    cyl_y("wind", r * 0.78, r * 0.7, (xc, -r * 1.35, z), m[turret], seg=24)
    cyl_y("windB", r * 0.62, r * 0.35, (xc, -r * 1.05, z), m[body], seg=20)
    for k in range(7):
        a = math.radians(-60 + k * 20)
        box("windKn", (0.006, r * 0.62, 0.01), (xc + math.sin(a) * r * 0.78, -r * 1.35,
                                                 z + math.cos(a) * r * 0.78), m["bore"], rot=(0, a, 0), bevel=0.0)
    box("windMark", (0.004, 0.004, r * 0.4), (xc, -r * 1.71, z + r * 0.35), m["white"], bevel=0.0)
    # Objectif évasé, pare-soleil éventuel, verre.
    xb = xt1
    cyl_x("bell", r, ro, 0.12, (xb + 0.06, 0, z), m[body], seg=32)
    cyl_x("obj", ro, ro, 0.18 + sunshade, (xb + 0.12 + (0.18 + sunshade) / 2, 0, z), m[body], seg=32)
    cyl_x("objRing", ro * 1.04, ro * 1.04, 0.025, (x1 - 0.012, 0, z), m[ring], seg=32)
    cyl_x("lens", ro * 0.86, ro * 0.86, 0.008, (x1 + 0.002, 0, z), m["glass"], seg=32)
    sphere("lensHi", ro * 0.22, (x1 + 0.004, -ro * 0.3, z + ro * 0.35), m["white"], scale=(0.1, 1, 1), seg=10)
    # Colliers et embases.
    rings = rings or (x0 + L * 0.34, x1 - L * 0.36)
    bz = base_z if base_z is not None else z - r - 0.06
    for xx in rings:
        cyl_x("ring", r * 1.16, r * 1.16, 0.045, (xx, 0, z), m[ring], seg=28)
        rounded(box("ringBase", (0.06, r * 1.8, z - r - bz), (xx, 0, (z - r + bz) / 2), m[ring]), 0.008, 2)
        box("ringCap", (0.045, 0.012, 0.03), (xx, -r * 1.16, z + r * 0.6), m[ring], bevel=0.003)
        screw(m, xx, z + r * 0.62, -r * 1.16 - 0.008, r=0.008, mat="steel")
        screw(m, xx, (z - r + bz) / 2, -r * 0.9 - 0.004, r=0.009, mat="steel")
    return xc


def bipod(m, x, z, h, mat="dark", fwd=0.16, spread=0.05, foot="rubber", ski=False):
    """Bipied déployé : embase, deux jambes télescopiques (tube + coulisse) inclinées vers l'avant, patins."""
    rounded(box("bpMount", (0.09, 0.12, 0.05), (x, 0, z), m[mat]), 0.01, 2)
    cyl_y("bpPivot", 0.022, 0.15, (x, 0, z - 0.03), m["steel"], seg=16)
    for sy in (spread, -spread):
        top = (x, sy, z - 0.04)
        mid = (x + fwd * 0.5, sy * 2.2, z - 0.04 - h * 0.5)
        end = (x + fwd, sy * 3.0, z - h)
        tube("bpLeg", [top, mid], 0.022, m[mat], seg=12)
        tube("bpLeg2", [mid, end], 0.016, m["steel"], seg=12)
        box("bpCollar", (0.05, 0.05, 0.035), mid, m[mat], rot=(0, math.atan2(fwd, h), 0), bevel=0.006)
        for k in range(3):
            fz = z - 0.04 - h * (0.6 + k * 0.1)
            fx = x + fwd * (0.6 + k * 0.1)
            box("bpNotch", (0.006, 0.006, 0.02), (fx - 0.012, sy * (2.4 + k * 0.2) - 0.014, fz), m["bore"],
                bevel=0.0)
        if ski:
            rounded(box("bpFoot", (0.14, 0.05, 0.025), (end[0] + 0.01, end[1], end[2] - 0.01), m[foot]), 0.01, 2)
        else:
            sphere("bpFoot", 0.032, (end[0], end[1], end[2] - 0.01), m[foot], scale=(1.1, 1, 0.8))


def curved_mag(m, mat, p0, p1, p2, p3, w, t, n=10):
    """Chargeur courbe (loft de sections rectangulaires le long d'une Bézier) ; renvoie les points."""
    pts = C.bezier(p0, p1, p2, p3, n)
    secs = [[(x, -t / 2, z), (x + w, -t / 2, z), (x + w, t / 2, z), (x, t / 2, z)] for (x, _y, z) in pts]
    rounded(C.mesh_obj("mag", C.bm_loft(secs), m[mat], smooth=False), 0.008, 2)
    return pts


# --------------------------------------------------------------------------- Colt M4A1 (Rare)

def rifle_m4a1(m):
    z0 = 0.24
    # Carcasse supérieure plate (flat-top) : rail Picatinny, fenêtre d'éjection et son volet, déflecteur
    # de douilles, assistance à la fermeture, levier d'armement.
    rounded(prism("upper", [(-0.30, 0.17), (0.47, 0.17), (0.47, 0.305), (-0.27, 0.305), (-0.30, 0.285)],
                  0.12, m["gunmetal"]), 0.012, 2)
    rail(m, -0.29, 0.47, 0.322, 0.09, mat="dark")
    box("upperLine", (0.74, 0.124, 0.006), (0.09, 0, 0.18), m["bore"], bevel=0.0)
    box("port", (0.22, 0.01, 0.065), (0.10, -0.06, 0.235), m["bore"], bevel=0.0)
    rounded(box("dustCover", (0.23, 0.012, 0.05), (0.10, -0.066, 0.228), m["gunmetal"], bevel=0.004), 0.004, 2)
    box("dustRib", (0.21, 0.014, 0.006), (0.10, -0.068, 0.236), m["dark"], bevel=0.0)
    cyl_x("dustHinge", 0.008, 0.008, 0.24, (0.10, -0.066, 0.198), m["steel"], seg=10)
    box("bolt", (0.12, 0.01, 0.02), (0.13, -0.058, 0.262), m["steel"], bevel=0.0)
    prism("deflector", [(-0.07, 0.22), (-0.005, 0.22), (-0.005, 0.30), (-0.05, 0.30)], 0.03, m["gunmetal"],
          y=-0.07)
    tube("fwdAssist", [(-0.25, -0.072, 0.245), (-0.07, -0.07, 0.272)], 0.03, m["gunmetal"], seg=18)
    cyl_x("fwdBtn", 0.024, 0.024, 0.03, (-0.265, -0.072, 0.243), m["dark"], seg=18)
    grooves(-0.272, 3, 0.01, (0.004, 0.006, 0.04), 0.243, m["bore"])
    box("charging", (0.07, 0.11, 0.035), (-0.325, 0, 0.29), m["dark"], bevel=0.006)
    box("chargeLatch", (0.035, 0.03, 0.025), (-0.33, -0.065, 0.29), m["bronze"], bevel=0.004)
    # Organe de visée arrière repliable (BUIS) sur le rail.
    box("buisBase", (0.11, 0.08, 0.025), (-0.21, 0, 0.35), m["dark"], bevel=0.004)
    rounded(prism("buis", [(-0.25, 0.36), (-0.17, 0.36), (-0.19, 0.44), (-0.235, 0.44)], 0.06, m["dark"]),
            0.006, 2)
    cyl_y("buisAp", 0.016, 0.07, (-0.212, 0, 0.425), m["dark"], seg=16)
    cyl_y("buisHole", 0.006, 0.074, (-0.212, 0, 0.425), m["bore"], seg=10)
    cyl_y("buisKnob", 0.018, 0.02, (-0.19, -0.045, 0.375), m["bronze"], seg=14)
    # Carcasse inférieure : puits de chargeur évasé, tour du tube tampon, goupilles, bouton de chargeur.
    rounded(prism("lower", [(-0.29, 0.17), (0.45, 0.17), (0.45, 0.13), (0.38, 0.10), (0.35, 0.10),
                            (0.345, -0.03), (0.33, -0.045), (0.15, -0.045), (0.145, 0.06), (-0.05, 0.07),
                            (-0.20, 0.07), (-0.29, 0.11)], 0.11, m["gunmetal"]), 0.012, 2)
    rounded(box("tower", (0.07, 0.11, 0.14), (-0.30, 0, 0.215), m["gunmetal"]), 0.02, 2)
    rounded(box("magFlare", (0.21, 0.124, 0.03), (0.245, 0, -0.035), m["gunmetal"]), 0.008, 2)
    box("magPanel", (0.15, 0.006, 0.09), (0.245, -0.057, 0.04), m["dark"], bevel=0.0)
    tube("releaseFence", [(0.10, -0.058, 0.08), (0.145, -0.058, 0.10), (0.145, -0.058, 0.15)], 0.009,
         m["gunmetal"], seg=8)
    cyl_y("magRelease", 0.022, 0.02, (0.115, -0.06, 0.12), m["dark"], seg=16)
    for (x, z) in ((-0.25, 0.145), (0.41, 0.145), (0.02, 0.11), (-0.07, 0.11)):
        cyl_y("pin", 0.011, 0.116, (x, 0, z), m["steel"], seg=12)
    cyl_y("selector", 0.02, 0.118, (-0.15, 0, 0.125), m["bronze"], seg=14)
    box("selTab", (0.05, 0.012, 0.016), (-0.165, -0.064, 0.13), m["dark"], rot=(0, 0.5, 0), bevel=0.003)
    # Pontet, détente.
    tube("guard", [(0.145, 0, 0.065), (0.135, 0, -0.015), (-0.04, 0, -0.02), (-0.06, 0, 0.06)], 0.016,
         m["gunmetal"])
    tube("trigger", [(0.04, 0, 0.07), (0.058, 0, 0.025), (0.042, 0, -0.005)], 0.013, m["dark"])
    # Poignée A2 : ergot pour le majeur, panneau quadrillé, semelle.
    rounded(BW.grip("grip", -0.05, 0.075, m["polymer"], h=0.32, w=0.13, t=0.11, slant=0.32), 0.022, 3)
    sphere("fingerNub", 0.026, (-0.085, 0, -0.06), m["polymer"], scale=(1, 2.1, 1), seg=12)
    prism("gripTex", [(-0.10, 0.04), (-0.165, 0.04), (-0.255, -0.21), (-0.19, -0.21)], 0.114, m["polymer_tex"])
    box("gripCap", (0.15, 0.114, 0.012), (-0.212, 0, -0.243), m["dark"], bevel=0.003)
    # Chargeur STANAG en aluminium, légèrement courbe : nervures, fenêtre de semelle.
    pts = curved_mag(m, "dark", (0.16, 0, 0.02), (0.16, 0, -0.16), (0.18, 0, -0.30), (0.235, 0, -0.42),
                     0.165, 0.09)
    for off in (0.04, 0.12):
        tube("magRib", [(x + off, -0.048, z) for (x, _y, z) in pts[2:-1]], 0.008, m["dark"], seg=8)
    rounded(box("magFloor", (0.2, 0.1, 0.03), (pts[-1][0] + 0.085, 0, pts[-1][2] - 0.01), m["polymer"],
                rot=(0, 0.35, 0)), 0.008, 2)
    # Tube tampon, écrou crénelé, plaque d'attache, crosse télescopique (levier, fente de bretelle, talon).
    cyl_x("buffer", 0.042, 0.042, 0.34, (-0.47, 0, 0.245), m["dark"], seg=24)
    cyl_x("castle", 0.056, 0.056, 0.035, (-0.335, 0, 0.245), m["dark"], seg=24)
    for k in range(3):
        a = math.radians(-50 + k * 50)
        box("castleN", (0.036, 0.012, 0.012), (-0.335, -0.056 * math.cos(a), 0.245 + 0.056 * math.sin(a)),
            m["bore"], rot=(-a, 0, 0), bevel=0.0)
    box("endPlate", (0.012, 0.12, 0.11), (-0.315, 0, 0.225), m["dark"], bevel=0.003)
    rounded(prism("stock", [(-0.58, 0.295), (-0.58, 0.205), (-0.63, 0.18), (-0.925, 0.04), (-0.925, 0.335),
                            (-0.68, 0.315)], 0.12, m["polymer"]), 0.02, 3)
    prism("stockRidge", [(-0.61, 0.27), (-0.90, 0.29), (-0.90, 0.25), (-0.64, 0.235)], 0.126, m["dark"])
    for x in (-0.40, -0.45, -0.50, -0.55):
        box("bufferHole", (0.012, 0.012, 0.012), (x, -0.041, 0.21), m["bore"], bevel=0.0)
    box("slingSlot", (0.11, 0.004, 0.035), (-0.80, -0.062, 0.115), m["bore"], rot=(0, -0.37, 0), bevel=0.0)
    box("stockLever", (0.11, 0.05, 0.02), (-0.67, 0, 0.16), m["dark"], rot=(0, -0.37, 0), bevel=0.004)
    rounded(box("buttPad", (0.035, 0.124, 0.31), (-0.94, 0, 0.183), m["rubber"]), 0.012, 2)
    grooves(-0.94, 1, 0.0, (0.04, 0.128, 0.008), 0.10, m["bore"])
    grooves(-0.94, 1, 0.0, (0.04, 0.128, 0.008), 0.26, m["bore"])
    # Garde-main RIS : bague delta, rails haut / bas / côté, caches de rail ajourés, vis.
    cyl_x("delta", 0.098, 0.09, 0.04, (0.49, 0, z0), m["gunmetal"], seg=28)
    rounded(box("ris", (0.58, 0.13, 0.15), (0.79, 0, z0), m["dark"], bevel=0.015), 0.01, 2)
    rail(m, 0.51, 1.07, 0.322, 0.09, mat="dark")
    rail_down(m, 0.51, 1.07, 0.158, 0.09, mat="dark")
    rail_side(m, 0.51, 0.66, z0, -0.072, mat="dark")
    rounded(box("cover", (0.38, 0.016, 0.06), (0.87, -0.074, z0), m["polymer"], bevel=0.006), 0.006, 2)
    grooves(0.70, 9, 0.042, (0.014, 0.02, 0.05), z0, m["dark"])
    for x in (0.53, 1.05):
        screw(m, x, 0.29, -0.068, r=0.011, mat="bronze")
        screw(m, x, 0.19, -0.068, r=0.011, mat="bronze")
    # Guidon en A sur le bloc de gaz, tenon de baïonnette, battant.
    rounded(box("fsbBase", (0.09, 0.085, 0.09), (1.15, 0, z0 - 0.005), m["blued"]), 0.01, 2)
    rounded(prism("fsb", [(1.10, 0.27), (1.20, 0.27), (1.175, 0.40), (1.135, 0.40)], 0.035, m["blued"]),
            0.006, 2)
    box("fsbHole", (0.03, 0.04, 0.06), (1.155, 0, 0.32), m["bore"], bevel=0.0)
    for sy in (-0.026, 0.026):
        rounded(prism("fsbEar", [(1.13, 0.38), (1.18, 0.38), (1.175, 0.44), (1.14, 0.44)], 0.014, m["blued"],
                      y=sy), 0.004, 2)
    box("fsPost", (0.012, 0.012, 0.06), (1.157, 0, 0.415), m["dark"], bevel=0.0)
    box("lug", (0.05, 0.03, 0.035), (1.17, 0, 0.175), m["blued"], bevel=0.004)
    tube("swivel", [(1.12, 0, 0.19), (1.12, 0, 0.14), (1.18, 0, 0.14), (1.18, 0, 0.19)], 0.008, m["steel"], seg=8)
    cyl_y("fsbPin", 0.009, 0.09, (1.13, 0, 0.215), m["steel"], seg=10)
    # Canon à gradin (lance-grenades), cache-flamme A2 ajouré (fermé dessous).
    cyl_x("barrel", 0.031, 0.031, 0.20, (1.18, 0, z0), m["blued"], seg=20)
    cyl_x("barrelStep", 0.024, 0.024, 0.025, (1.29, 0, z0), m["blued"], seg=20)
    cyl_x("barrel2", 0.028, 0.028, 0.16, (1.38, 0, z0), m["blued"], seg=20)
    cyl_x("flashNut", 0.034, 0.034, 0.02, (1.465, 0, z0), m["dark"], seg=20)
    cyl_x("flash", 0.038, 0.038, 0.11, (1.525, 0, z0), m["blued"], seg=24)
    for k in range(3):
        box("flashSlot", (0.075, 0.01, 0.01), (1.53, -0.035 + k * 0.004, z0 + 0.026 - k * 0.022), m["bore"],
            bevel=0.0)
    cyl_x("muzzleBore", 0.018, 0.018, 0.01, (1.578, 0, z0), m["bore"], seg=16)
    return {"grip": (-0.16, 0, -0.08), "muzzle": (1.58, 0, z0)}


# --------------------------------------------------------------------------- FN SCAR-H (Épique)

def rifle_scarh(m):
    z0 = 0.26
    # Boîtier supérieur long et carré, arêtes chanfreinées, rail continu, rails côté / dessous à l'avant.
    rounded(prism("upper", [(-0.32, 0.17), (0.80, 0.17), (0.88, 0.21), (0.88, 0.36), (0.865, 0.375),
                            (-0.30, 0.375), (-0.32, 0.355)], 0.15, m["tan"]), 0.016, 2)
    box("chamfer", (1.16, 0.156, 0.014), (0.27, 0, 0.352), m["olive"], bevel=0.0)
    rail(m, -0.31, 0.87, 0.39, 0.1, mat="tan")
    rail_side(m, 0.47, 0.86, 0.265, -0.085, mat="tan", h=0.055)
    rail_down(m, 0.47, 0.86, 0.157, 0.1, mat="tan")
    # Fenêtre d'éjection (sans volet), déflecteur, fente et poignée d'armement, vis six pans.
    box("port", (0.17, 0.01, 0.045), (0.12, -0.076, 0.255), m["bore"], bevel=0.0)
    box("bolt", (0.15, 0.012, 0.02), (0.125, -0.076, 0.262), m["blued"], bevel=0.0)
    prism("deflector", [(-0.03, 0.22), (0.01, 0.22), (0.01, 0.31), (-0.01, 0.31)], 0.03, m["tan"], y=-0.082)
    box("chSlot", (0.62, 0.008, 0.018), (0.36, -0.076, 0.315), m["bore"], bevel=0.0)
    rounded(box("chHandle", (0.04, 0.07, 0.035), (0.58, -0.11, 0.315), m["dark"], rot=(0, 0, 0.4)), 0.008, 2)
    sphere("chKnob", 0.026, (0.59, -0.145, 0.315), m["dark"], scale=(1, 1, 0.8))
    for (x, z) in ((-0.26, 0.21), (0.82, 0.21), (-0.26, 0.33)):
        cyl_y("hexBolt", 0.014, 0.162, (x, 0, z), m["silver"], seg=6)
    box("serial", (0.16, 0.004, 0.02), (-0.12, -0.076, 0.215), m["olive"], bevel=0.0)
    # Organes de visée repliables relevés.
    box("fsBase", (0.08, 0.08, 0.025), (0.82, 0, 0.415), m["dark"], bevel=0.004)
    rounded(prism("fs", [(0.80, 0.42), (0.85, 0.42), (0.835, 0.51), (0.81, 0.51)], 0.05, m["dark"]), 0.005, 2)
    box("fsPost", (0.012, 0.012, 0.05), (0.822, 0, 0.53), m["dark"], bevel=0.0)
    box("rsBase", (0.09, 0.08, 0.025), (-0.22, 0, 0.415), m["dark"], bevel=0.004)
    rounded(prism("rs", [(-0.255, 0.42), (-0.185, 0.42), (-0.2, 0.5), (-0.24, 0.5)], 0.06, m["dark"]), 0.005, 2)
    cyl_y("rsAp", 0.016, 0.07, (-0.22, 0, 0.485), m["dark"], seg=16)
    cyl_y("rsHole", 0.006, 0.074, (-0.22, 0, 0.485), m["bore"], seg=10)
    # Carcasse inférieure en polymère : puits évasé, bossage du bouton de chargeur, sélecteur.
    rounded(prism("lower", [(-0.30, 0.175), (0.40, 0.175), (0.40, 0.12), (0.355, 0.09), (0.36, -0.03),
                            (0.35, -0.05), (0.12, -0.05), (0.12, 0.06), (-0.06, 0.07), (-0.24, 0.07),
                            (-0.30, 0.12)], 0.13, m["tan"]), 0.014, 2)
    rounded(box("magFlare", (0.26, 0.15, 0.035), (0.237, 0, -0.04), m["tan"]), 0.01, 2)
    rounded(box("bossRel", (0.09, 0.144, 0.07), (0.08, 0, 0.115), m["tan"]), 0.02, 2)
    cyl_y("magRelease", 0.02, 0.022, (0.08, -0.073, 0.115), m["dark"], seg=16)
    cyl_y("selector", 0.024, 0.136, (-0.15, 0, 0.13), m["dark"], seg=16)
    box("selLever", (0.07, 0.012, 0.02), (-0.17, -0.072, 0.14), m["dark"], rot=(0, 0.5, 0), bevel=0.004)
    cyl_y("selDot", 0.006, 0.004, (-0.195, -0.08, 0.152), m["red"], seg=8)
    for (x, z) in ((-0.25, 0.15), (0.36, 0.15), (0.02, 0.115)):
        cyl_y("pin", 0.011, 0.134, (x, 0, z), m["steel"], seg=12)
    tube("guard", [(0.12, 0, 0.06), (0.105, 0, -0.025), (-0.05, 0, -0.03), (-0.07, 0, 0.06)], 0.019, m["tan"])
    tube("trigger", [(0.03, 0, 0.07), (0.048, 0, 0.025), (0.032, 0, -0.005)], 0.013, m["dark"])
    # Poignée pistolet, chargeur droit de 20 (acier, nervures).
    rounded(BW.grip("grip", -0.06, 0.075, m["polymer"], h=0.32, w=0.13, t=0.115, slant=0.3), 0.022, 3)
    sphere("fingerNub", 0.026, (-0.095, 0, -0.06), m["polymer"], scale=(1, 2.1, 1), seg=12)
    prism("gripTex", [(-0.11, 0.04), (-0.175, 0.04), (-0.26, -0.21), (-0.195, -0.21)], 0.118, m["polymer_tex"])
    pts = curved_mag(m, "polymer", (0.14, 0, 0.0), (0.14, 0, -0.12), (0.15, 0, -0.22), (0.165, 0, -0.33),
                     0.19, 0.1, n=6)
    for off in (0.05, 0.14):
        tube("magRib", [(x + off, -0.052, z) for (x, _y, z) in pts[1:-1]], 0.009, m["polymer"], seg=8)
    box("magWin", (0.03, 0.006, 0.12), (0.255, -0.051, -0.14), m["dark"], bevel=0.0)
    rounded(box("magFloor", (0.22, 0.11, 0.03), (0.26, 0, -0.335), m["dark"]), 0.008, 2)
    # Crosse pliante réglable : charnière, busc relevable, jambe inclinée, ajour triangulaire, plaque.
    rounded(box("hinge", (0.07, 0.15, 0.21), (-0.355, 0, 0.27), m["tan"]), 0.015, 2)
    BW.cyl_z("hingeKnuckle", 0.026, 0.026, 0.19, (-0.37, -0.07, 0.27), m["dark"], seg=16)
    rounded(prism("comb", [(-0.39, 0.375), (-0.98, 0.375), (-0.98, 0.23), (-0.66, 0.255), (-0.39, 0.28)],
                  0.13, m["tan"]), 0.018, 2)
    rounded(prism("strut", [(-0.39, 0.25), (-0.39, 0.175), (-0.86, -0.03), (-0.98, -0.045), (-0.98, 0.06),
                            (-0.88, 0.05)], 0.12, m["tan"]), 0.016, 2)
    rounded(prism("cheek", [(-0.55, 0.37), (-0.93, 0.37), (-0.93, 0.415), (-0.60, 0.41)], 0.12, m["olive"]),
            0.015, 2)
    cyl_y("cheekBtn", 0.016, 0.135, (-0.62, 0, 0.33), m["dark"], seg=12)
    box("lopBtn", (0.04, 0.136, 0.02), (-0.80, 0, 0.30), m["dark"], bevel=0.004)
    rounded(box("buttPlate", (0.06, 0.14, 0.43), (-0.96, 0, 0.165), m["tan"]), 0.015, 2)
    rounded(box("buttPad", (0.035, 0.145, 0.44), (-1.005, 0, 0.165), m["rubber"]), 0.012, 2)
    grooves(-1.005, 4, 0.0, (0.04, 0.15, 0.006), 0.0, m["bore"])
    for k, z in enumerate((0.05, 0.15, 0.25, 0.33)):
        box("padLine", (0.04, 0.15, 0.006), (-1.005, 0, z), m["bore"], bevel=0.0)
    cyl_y("slingQD", 0.02, 0.14, (-0.90, 0, 0.30), m["silver"], seg=14)
    # Canon, régulateur de gaz, cache-flamme gravé à fentes.
    cyl_x("barrel", 0.036, 0.036, 0.42, (1.09, 0, z0), m["blued"], seg=22)
    rounded(box("gasReg", (0.07, 0.09, 0.06), (0.92, 0, 0.2), m["dark"]), 0.01, 2)
    cyl_y("gasKnob", 0.02, 0.1, (0.92, 0, 0.2), m["silver"], seg=12)
    cyl_x("flashNut", 0.04, 0.04, 0.02, (1.28, 0, z0), m["dark"], seg=22)
    cyl_x("flash", 0.046, 0.042, 0.13, (1.355, 0, z0), m["engraved"], seg=26)
    for k in range(3):
        box("flashSlot", (0.09, 0.01, 0.011), (1.36, -0.042 + abs(k - 1) * 0.006, z0 + 0.024 - k * 0.024),
            m["bore"], bevel=0.0)
    cyl_x("muzzleBore", 0.02, 0.02, 0.01, (1.423, 0, z0), m["bore"], seg=16)
    return {"grip": (-0.17, 0, -0.08), "muzzle": (1.425, 0, z0)}


# --------------------------------------------------------------------------- Remington M24 (Commun)

def sniper_m24(m):
    z0 = 0.25
    stip = WP.paint("m24_stipple", "#4c2a16", "#1e0e0c", "#7a4a2a", grain=0.45, grain_scale=150.0, wear=0.1)
    # Crosse H-S Precision : devant large (beavertail), poignée quasi verticale, busc haut, talon droit.
    prof = BW.curve2d(
        (1.02, 0.23), (0.32, 0.235), (0.32, 0.25), (-0.32, 0.25),
        ((-0.32, 0.25), (-0.40, 0.25), (-0.46, 0.22), (-0.56, 0.285)),
        (-1.11, 0.295), (-1.11, -0.215),
        ((-1.11, -0.215), (-0.85, -0.14), (-0.62, -0.08), (-0.50, -0.06)),
        ((-0.50, -0.06), (-0.46, -0.10), (-0.47, -0.20), (-0.47, -0.25)),
        (-0.31, -0.255),
        ((-0.31, -0.255), (-0.27, -0.14), (-0.24, -0.02), (-0.20, 0.07)),
        (0.05, 0.095), (0.92, 0.13),
        ((0.92, 0.13), (0.99, 0.135), (1.03, 0.17), (1.02, 0.23)), n=6)
    rounded(prism("stock", prof, 0.13, m["wood_dark"]), 0.03, 3)
    # Quadrillage (poignée, devant), ligne de busc.
    prism("gripStip", [(-0.27, 0.0), (-0.43, -0.07), (-0.445, -0.22), (-0.32, -0.22)], 0.134, stip)
    prism("foreStip", [(0.30, 0.19), (0.72, 0.19), (0.72, 0.13), (0.30, 0.115)], 0.134, stip)
    box("combLine", (0.5, 0.134, 0.008), (-0.84, 0, 0.24), m["dark"], bevel=0.0)
    # Talon : entretoises de longueur, plaque caoutchouc.
    box("spacer", (0.02, 0.13, 0.5), (-1.12, 0, 0.04), m["dark"], bevel=0.003)
    box("spacer2", (0.02, 0.13, 0.5), (-1.14, 0, 0.04), m["polymer"], bevel=0.003)
    rounded(box("buttPad", (0.045, 0.135, 0.52), (-1.172, 0, 0.04), m["rubber"]), 0.015, 2)
    for z in (-0.12, 0.0, 0.12, 0.22):
        box("padLine", (0.05, 0.14, 0.006), (-1.172, 0, z), m["bore"], bevel=0.0)
    # Boîtier cylindrique Remington 700 : bague avant, fenêtre d'éjection, culasse et levier, chien.
    cyl_x("receiver", 0.058, 0.058, 0.62, (0.01, 0, z0 + 0.01), m["blued"], seg=28)
    cyl_x("frontRing", 0.062, 0.062, 0.03, (0.31, 0, z0 + 0.01), m["blued"], seg=28)
    box("port", (0.2, 0.012, 0.05), (0.07, -0.052, z0 + 0.03), m["bore"], bevel=0.0)
    cyl_x("boltBody", 0.03, 0.03, 0.19, (0.06, -0.026, z0 + 0.03), m["steel"], seg=16)
    cyl_x("shroud", 0.05, 0.036, 0.09, (-0.345, 0, z0 + 0.02), m["blued"], seg=20)
    cyl_x("cocking", 0.022, 0.018, 0.05, (-0.41, 0, z0 + 0.02), m["steel"], seg=14)
    box("boltSlot", (0.05, 0.012, 0.04), (-0.19, -0.056, z0 + 0.03), m["bore"], bevel=0.0)
    tube("boltHandle", [(-0.18, -0.05, z0 + 0.035), (-0.19, -0.11, z0 + 0.0), (-0.205, -0.15, z0 - 0.07)],
         0.019, m["steel"], seg=12)
    sphere("boltKnob", 0.045, (-0.21, -0.16, z0 - 0.095), m["polymer"], scale=(1, 1, 1.1), seg=16)
    cyl_y("bolt_safety", 0.012, 0.02, (-0.27, -0.055, z0 - 0.0), m["dark"], seg=10)
    box("safety", (0.04, 0.012, 0.018), (-0.28, -0.065, z0 + 0.0), m["dark"], bevel=0.003)
    # Canon lourd conique, couronne.
    cyl_x("barrel", 0.044, 0.033, 1.53, (1.095, 0, z0 + 0.01), m["blued"], seg=24)
    cyl_x("crown", 0.034, 0.03, 0.02, (1.865, 0, z0 + 0.01), m["steel"], seg=20)
    cyl_x("muzzleBore", 0.014, 0.014, 0.01, (1.876, 0, z0 + 0.01), m["bore"], seg=12)
    # Pontet et plancher articulé, vis d'action, battants de bretelle.
    rounded(box("floorplate", (0.36, 0.08, 0.025), (-0.03, 0, 0.09), m["blued"]), 0.008, 2)
    tube("guard", [(-0.10, 0, 0.09), (-0.105, 0, 0.0), (-0.22, 0, -0.01), (-0.245, 0, 0.05)], 0.016,
         m["blued"])
    tube("trigger", [(-0.165, 0, 0.09), (-0.15, 0, 0.04), (-0.165, 0, 0.01)], 0.013, m["steel"])
    box("fpLatch", (0.025, 0.084, 0.012), (-0.095, 0, 0.104), m["steel"], bevel=0.003)
    for x in (0.12, -0.27):
        cyl_y("actionScrew", 0.012, 0.136, (x, 0, 0.13), m["steel"], seg=12)
    for (x, z) in ((0.85, 0.12), (-0.95, -0.165)):
        cyl_y("stud", 0.016, 0.136, (x, 0, z), m["steel"], seg=12)
        tube("swivel", [(x - 0.035, 0, z - 0.01), (x - 0.035, 0, z - 0.07), (x + 0.035, 0, z - 0.07),
                        (x + 0.035, 0, z - 0.01)], 0.008, m["steel"], seg=8)
    # Embase et lunette Leupold Mk 4 (10 x 40) : colliers, tourelles, objectif.
    box("base", (0.62, 0.06, 0.03), (0.0, 0, z0 + 0.075), m["dark"], bevel=0.004)
    scope(m, -0.34, 0.60, 0.41, r=0.048, ro=0.075, base_z=z0 + 0.09, body="polymer", ring="dark",
          turret="dark", rings=(-0.10, 0.22))
    return {"grip": (-0.37, 0, -0.12), "muzzle": (1.878, 0, z0 + 0.01)}


# --------------------------------------------------------------------------- Accuracy International AX50 (Rare)

def _octo_tube(name, x0, x1, zc, hw, hh, ch, mat):
    """Garde-main à section octogonale (chanfreins) entre x0 et x1."""
    sec = [(-hw + ch, -hh), (hw - ch, -hh), (hw, -hh + ch), (hw, hh - ch), (hw - ch, hh), (-hw + ch, hh),
           (-hw, hh - ch), (-hw, -hh + ch)]
    secs = [[(x, y, zc + z) for (y, z) in sec] for x in (x0, x1)]
    return C.mesh_obj(name, C.bm_loft(secs), mat, smooth=False)


def sniper_ax50(m):
    z0 = 0.26
    # Boîtier d'action aluminium, culasse (gros levier boule), chien.
    rounded(box("action", (0.70, 0.13, 0.13), (-0.04, 0, 0.275), m["gunmetal"], bevel=0.015), 0.01, 2)
    box("port", (0.22, 0.01, 0.055), (0.10, -0.066, 0.285), m["bore"], bevel=0.0)
    cyl_x("boltBody", 0.034, 0.034, 0.2, (0.10, -0.04, 0.285), m["steel"], seg=16)
    cyl_x("shroud", 0.05, 0.04, 0.10, (-0.44, 0, 0.28), m["dark"], seg=22)
    cyl_x("cocking", 0.024, 0.02, 0.05, (-0.51, 0, 0.28), m["steel"], seg=14)
    tube("boltHandle", [(-0.25, -0.06, 0.29), (-0.265, -0.12, 0.25), (-0.28, -0.16, 0.18)], 0.016, m["steel"],
         seg=12)
    sphere("boltKnob", 0.045, (-0.285, -0.17, 0.155), m["polymer"], scale=(1, 1, 1.15), seg=16)
    for x in (-0.30, 0.22):
        screw(m, x, 0.24, -0.068, r=0.012, mat="bronze")
    # Châssis inférieur, puits de chargeur, pontet en aluminium, poignée verticale.
    rounded(prism("chassis", [(-0.42, 0.215), (0.34, 0.215), (0.34, 0.15), (0.24, 0.11), (-0.02, 0.11),
                              (-0.24, 0.12), (-0.42, 0.15)], 0.13, m["gunmetal"]), 0.012, 2)
    box("chassisLine", (0.74, 0.134, 0.006), (-0.04, 0, 0.205), m["bore"], bevel=0.0)
    rounded(box("magwell", (0.25, 0.134, 0.05), (0.12, 0, 0.10), m["gunmetal"]), 0.01, 2)
    rounded(box("mag", (0.21, 0.1, 0.24), (0.12, 0, -0.03), m["dark"]), 0.012, 2)
    box("magRib", (0.006, 0.104, 0.2), (0.07, 0, -0.03), m["polymer"], bevel=0.0)
    box("magRib2", (0.006, 0.104, 0.2), (0.17, 0, -0.03), m["polymer"], bevel=0.0)
    rounded(box("magBase", (0.24, 0.11, 0.035), (0.12, 0, -0.16), m["polymer"]), 0.01, 2)
    box("magRelease", (0.03, 0.12, 0.05), (0.27, 0, 0.09), m["bronze"], bevel=0.006)
    tube("guard", [(-0.02, 0, 0.11), (-0.03, 0, -0.01), (-0.19, 0, -0.02), (-0.21, 0, 0.08)], 0.02,
         m["gunmetal"])
    tube("trigger", [(-0.10, 0, 0.11), (-0.085, 0, 0.06), (-0.10, 0, 0.025)], 0.013, m["steel"])
    rounded(BW.grip("grip", -0.20, 0.12, m["polymer"], h=0.31, w=0.14, t=0.115, slant=0.18), 0.022, 3)
    for k in range(3):
        sphere("finger", 0.022, (-0.215 - k * 0.018, 0, 0.04 - k * 0.075), m["polymer"], scale=(1, 2.4, 1),
               seg=10)
    prism("gripTex", [(-0.25, 0.08), (-0.32, 0.08), (-0.37, -0.17), (-0.30, -0.17)], 0.119, m["polymer_tex"])
    # Garde-main octogonal ajouré (fentes), rail continu, rail de bipied.
    _octo_tube("forend", 0.33, 1.13, 0.245, 0.075, 0.09, 0.03, m["gunmetal"])
    for row, z in enumerate((0.275, 0.205)):
        for k in range(6):
            rounded(box("slotKM", (0.08, 0.012, 0.024), (0.43 + k * 0.12 + row * 0.06, -0.075, z), m["bore"],
                        bevel=0.0), 0.006, 2)
    rail(m, -0.44, 1.10, 0.355, 0.09, mat="dark")
    rail_down(m, 0.82, 1.10, 0.14, 0.08, mat="dark")
    box("forendCap", (0.025, 0.155, 0.185), (1.13, 0, 0.245), m["dark"], bevel=0.006)
    # Canon cannelé, frein de bouche massif à larges évents.
    cyl_x("barrel", 0.048, 0.048, 0.66, (1.46, 0, z0), m["dark"], seg=26)
    BW.flutes(m, 1.44, z0, 0.047, 0.52, 6, "bore", phase=math.pi / 6, w=0.012, depth=0.008)
    cyl_x("brakeNut", 0.056, 0.056, 0.03, (1.805, 0, z0), m["gunmetal"], seg=26)
    cyl_x("brake", 0.074, 0.074, 0.2, (1.92, 0, z0), m["gunmetal"], seg=30)
    for x in (1.87, 1.955):
        box("port", (0.055, 0.03, 0.09), (x, -0.06, z0), m["bore"], bevel=0.0)
        box("portT", (0.055, 0.03, 0.03), (x, 0, z0 + 0.067), m["bore"], bevel=0.0)
    cyl_x("brakeFront", 0.076, 0.07, 0.02, (2.02, 0, z0), m["bronze"], seg=30)
    cyl_x("muzzleBore", 0.03, 0.03, 0.01, (2.032, 0, z0), m["bore"], seg=16)
    # Lunette tactique 5-25 x 56, tourelles bronze.
    scope(m, -0.38, 0.66, 0.50, r=0.052, ro=0.096, base_z=0.37, body="polymer", ring="dark", turret="bronze",
          rings=(-0.10, 0.34))
    # Crosse squelette pliante : charnière, poutre haute, busc réglable, jambe inclinée, plaque, monopied.
    rounded(box("hinge", (0.08, 0.13, 0.21), (-0.47, 0, 0.25), m["dark"]), 0.012, 2)
    BW.cyl_z("hingeKnuckle", 0.026, 0.026, 0.19, (-0.49, -0.068, 0.25), m["steel"], seg=16)
    rounded(prism("beam", [(-0.50, 0.345), (-1.00, 0.345), (-1.00, 0.275), (-0.50, 0.275)], 0.11,
                  m["gunmetal"]), 0.012, 2)
    rounded(prism("cheek", [(-0.60, 0.345), (-0.95, 0.345), (-0.95, 0.43), (-0.65, 0.425)], 0.11,
                  m["polymer"]), 0.018, 2)
    BW.cyl_z("cheekPost", 0.015, 0.015, 0.06, (-0.68, -0.03, 0.36), m["steel"], seg=10)
    cyl_y("cheekWheel", 0.03, 0.03, (-0.75, -0.07, 0.31), m["bronze"], seg=18)
    rounded(prism("strut", [(-0.50, 0.20), (-0.50, 0.135), (-0.92, -0.025), (-1.00, -0.025), (-1.00, 0.05),
                            (-0.92, 0.05)], 0.1, m["gunmetal"]), 0.012, 2)
    rounded(box("buttPlate", (0.05, 0.12, 0.45), (-1.02, 0, 0.155), m["dark"]), 0.012, 2)
    rounded(box("buttPad", (0.04, 0.13, 0.46), (-1.065, 0, 0.155), m["rubber"]), 0.014, 2)
    for z in (0.02, 0.12, 0.22, 0.32):
        box("padLine", (0.045, 0.135, 0.006), (-1.065, 0, z), m["bore"], bevel=0.0)
    cyl_y("lopWheel", 0.028, 0.03, (-1.0, -0.07, 0.31), m["bronze"], seg=18)
    tube("monopod", [(-0.86, 0, 0.0), (-0.86, 0, -0.16)], 0.017, m["dark"], seg=12)
    cyl_x("monoKnob", 0.03, 0.03, 0.03, (-0.86, 0, -0.05), m["bronze"], seg=16)
    rounded(box("monoFoot", (0.07, 0.05, 0.02), (-0.86, 0, -0.17), m["rubber"]), 0.006, 2)
    # Bipied Atlas déployé sous le garde-main.
    bipod(m, 1.0, 0.115, 0.38, mat="dark", fwd=0.17)
    return {"grip": (-0.29, 0, -0.06), "muzzle": (2.035, 0, z0)}


# --------------------------------------------------------------------------- Barrett M82A1 (Épique)

def sniper_m82(m):
    z0 = 0.29
    # Boîtier supérieur en tôle (de la plaque de couche au canon), avant percé de grandes lumières.
    rounded(prism("upper", [(-1.08, 0.205), (1.00, 0.205), (1.07, 0.24), (1.07, 0.36), (1.02, 0.42),
                            (-1.08, 0.42)], 0.17, m["dark"]), 0.016, 2)
    for k in range(6):
        x = 0.46 + k * 0.095
        rounded(box("vent", (0.07, 0.012, 0.05), (x, -0.086, 0.36), m["bore"], bevel=0.0), 0.01, 2)
        rounded(box("ventL", (0.07, 0.012, 0.05), (x + 0.045, -0.086, 0.27), m["bore"], bevel=0.0), 0.01, 2)
    cyl_x("barrelIn", 0.05, 0.05, 0.62, (0.73, 0, z0 + 0.025), m["silver"], seg=16)
    box("seam", (2.12, 0.174, 0.008), (-0.02, 0, 0.215), m["bore"], bevel=0.0)
    rivets([(x, 0.40) for x in (-0.95, -0.55, -0.15, 0.25)] + [(x, 0.225) for x in (-0.95, -0.55)], 0.012,
           m["silver"], -0.087)
    # Levier d'armement côté droit, rail, poignée de transport repliable gravée.
    box("chSlot", (0.3, 0.008, 0.02), (0.18, -0.086, 0.32), m["bore"], bevel=0.0)
    rounded(box("chHandle", (0.05, 0.08, 0.05), (0.08, -0.12, 0.32), m["silver"]), 0.01, 2)
    rail(m, -0.42, 0.50, 0.435, 0.1, mat="dark")
    for x in (0.60, 0.88):
        rounded(box("hBase", (0.05, 0.08, 0.04), (x, 0, 0.44), m["dark"]), 0.008, 2)
    tube("handle", C.bezier((0.60, 0, 0.45), (0.61, 0, 0.58), (0.87, 0, 0.58), (0.88, 0, 0.45), 9), 0.024,
         m["engraved"], seg=12)
    # Carcasse inférieure : talon de crosse incliné, coussin de joue, plaque de couche épaisse, monopied.
    rounded(prism("lower", [(-1.08, 0.215), (0.43, 0.215), (0.43, 0.125), (0.35, 0.085), (-0.44, 0.085),
                            (-1.08, -0.01)], 0.15, m["dark"]), 0.016, 2)
    box("lowerLine", (1.5, 0.154, 0.006), (-0.32, 0, 0.12), m["bore"], bevel=0.0)
    rounded(box("cheekPad", (0.44, 0.18, 0.045), (-0.80, 0, 0.43), m["rubber"]), 0.018, 2)
    rounded(box("buttPlate", (0.04, 0.17, 0.44), (-1.10, 0, 0.205), m["dark"]), 0.012, 2)
    rounded(box("buttPad", (0.075, 0.18, 0.47), (-1.155, 0, 0.205), m["rubber"]), 0.025, 3)
    for z in (0.04, 0.14, 0.24, 0.34):
        box("padLine", (0.08, 0.185, 0.008), (-1.155, 0, z), m["bore"], bevel=0.0)
    tube("monopod", [(-0.92, 0, 0.01), (-0.92, 0, -0.13)], 0.02, m["dark"], seg=12)
    cyl_x("monoKnob", 0.034, 0.034, 0.035, (-0.92, 0, -0.04), m["silver"], seg=16)
    rounded(box("monoFoot", (0.08, 0.06, 0.022), (-0.92, 0, -0.14), m["rubber"]), 0.006, 2)
    for x in (-0.80, -0.30, 0.30):
        cyl_y("pin", 0.016, 0.158, (x, 0, 0.17), m["silver"], seg=12)
    # Poignée, pontet, détente, sélecteur.
    rounded(BW.grip("grip", -0.25, 0.09, m["polymer"], h=0.33, w=0.15, t=0.12, slant=0.24), 0.024, 3)
    prism("gripTex", [(-0.29, 0.05), (-0.37, 0.05), (-0.44, -0.2), (-0.36, -0.2)], 0.124, m["polymer_tex"])
    tube("guard", [(-0.01, 0, 0.09), (-0.02, 0, -0.02), (-0.22, 0, -0.03), (-0.245, 0, 0.06)], 0.02, m["dark"])
    tube("trigger", [(-0.11, 0, 0.09), (-0.095, 0, 0.04), (-0.11, 0, 0.005)], 0.014, m["silver"])
    cyl_y("selector", 0.022, 0.156, (-0.33, 0, 0.15), m["silver"], seg=14)
    box("selLever", (0.06, 0.012, 0.02), (-0.355, -0.08, 0.16), m["dark"], rot=(0, 0.5, 0), bevel=0.004)
    # Chargeur de 10 (.50 BMG) : boîte haute, nervures, semelle.
    rounded(prism("mag", [(0.05, 0.10), (0.33, 0.10), (0.345, -0.22), (0.065, -0.22)], 0.13, m["dark"]),
            0.012, 2)
    for z in (0.0, -0.08, -0.16):
        box("magRib", (0.28, 0.136, 0.018), (0.198, 0, z), m["dark"], bevel=0.004)
    rounded(box("magBase", (0.31, 0.14, 0.035), (0.205, 0, -0.235), m["polymer"]), 0.01, 2)
    box("magRelease", (0.035, 0.15, 0.05), (0.37, 0, 0.11), m["silver"], bevel=0.006)
    # Lunette sur le rail.
    scope(m, -0.40, 0.48, 0.60, r=0.055, ro=0.095, base_z=0.455, body="polymer", ring="dark",
          turret="silver", rings=(-0.14, 0.30))
    # Canon cannelé argent, collier, bipied déployé (patins).
    cyl_x("barrel", 0.062, 0.058, 0.88, (1.50, 0, z0), m["silver"], seg=28)
    BW.flutes(m, 1.47, z0, 0.059, 0.66, 6, "dark", phase=math.pi / 6, w=0.016, depth=0.008)
    cyl_x("collar", 0.075, 0.075, 0.04, (1.09, 0, z0), m["dark"], seg=28)
    bipod(m, 1.0, 0.18, 0.47, mat="dark", fwd=0.15, spread=0.06, ski=True)
    # Frein de bouche à double chambre (pointe de flèche), gravé.
    rounded(prism("brake", [(1.94, 0.215), (2.12, 0.215), (2.16, 0.25), (2.16, 0.33), (2.12, 0.365),
                            (1.94, 0.365)], 0.18, m["engraved"]), 0.014, 2)
    for x in (1.99, 2.075):
        rounded(box("chamber", (0.06, 0.014, 0.11), (x, -0.087, z0), m["bore"], bevel=0.0), 0.01, 2)
    cyl_x("muzzleBore", 0.03, 0.03, 0.01, (2.165, 0, z0), m["bore"], seg=16)
    return {"grip": (-0.37, 0, -0.08), "muzzle": (2.165, 0, z0)}


WEAPONS = {"rifle_m4a1": rifle_m4a1, "rifle_scarh": rifle_scarh, "sniper_m24": sniper_m24,
           "sniper_ax50": sniper_ax50, "sniper_m82": sniper_m82}
