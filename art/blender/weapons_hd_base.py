"""Armes HD de référence (témoins validés) : P9 (Commun), AK-47 (Commun), AUG (Légendaire)."""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import build_weapons as BW  # noqa: E402
from weapons_hd_kit import (box, cyl_x, cyl_y, grooves, prism, rail, rivets, rounded,  # noqa: E402
                            sphere, tube)


# --------------------------------------------------------------------------- pistolet P9 (Commun)

def pistol_p9(m):
    hz, th, L, cx = 0.17, 0.14, 0.86, 0.28
    front, back = cx + L / 2, cx - L / 2
    # Culasse : bloc chanfreiné, nez biseauté, rainures avant et arrière, fenêtre d'éjection.
    rounded(prism("slide", [(back, hz - th / 2), (front - 0.03, hz - th / 2), (front, hz - th / 2 + 0.03),
                            (front, hz + th / 2 - 0.035), (front - 0.05, hz + th / 2), (back + 0.02, hz + th / 2),
                            (back, hz + th / 2 - 0.02)], 0.12, m["blued"]), 0.012, 2)
    grooves(back + 0.05, 7, 0.026, (0.011, 0.126, th * 0.72), hz - 0.004, m["bore"])
    grooves(front - 0.17, 4, 0.024, (0.010, 0.126, th * 0.55), hz - 0.012, m["bore"])
    box("slideCut", (L - 0.12, 0.124, 0.008), (cx + 0.02, 0, hz - 0.035), m["dark"], bevel=0.0)
    box("port", (0.17, 0.014, 0.052), (cx + 0.06, -0.056, hz + 0.028), m["dark"], bevel=0.0)
    box("hood", (0.13, 0.03, 0.03), (cx + 0.07, -0.058, hz + 0.034), m["steel"], bevel=0.006)
    box("extractor", (0.07, 0.01, 0.016), (cx - 0.05, -0.062, hz + 0.03), m["dark"], bevel=0.0)
    # Organes de visée à points blancs.
    box("sightF", (0.028, 0.03, 0.04), (front - 0.05, 0, hz + th / 2 + 0.018), m["dark"], bevel=0.004)
    sphere("dotF", 0.008, (front - 0.05, -0.016, hz + th / 2 + 0.024), m["white"], seg=8)
    box("sightB", (0.05, 0.075, 0.042), (back + 0.06, 0, hz + th / 2 + 0.02), m["dark"], bevel=0.004)
    for yy in (-0.039,):
        sphere("dotB", 0.007, (back + 0.075, yy, hz + th / 2 + 0.026), m["white"], seg=8)
    # Canon : couronne en acier, âme sombre, guide de ressort dessous.
    cyl_x("barrel", 0.036, 0.036, 0.04, (front + 0.012, 0, hz + 0.012), m["steel"])
    cyl_x("boreF", 0.02, 0.02, 0.01, (front + 0.034, 0, hz + 0.012), m["bore"])
    cyl_x("guide", 0.018, 0.018, 0.03, (front + 0.005, 0, hz - 0.06), m["steel"])
    # Carcasse : cache-poussière avec rail, pontet carré, détente, leviers.
    rounded(prism("frame", [(back + 0.02, hz - th / 2), (front - 0.05, hz - th / 2), (front - 0.05, hz - 0.12),
                            (cx + 0.10, hz - 0.16), (back + 0.16, hz - 0.16), (back + 0.06, hz - 0.12)],
                  0.11, m["polymer"]), 0.012, 2)
    rail(m, cx + 0.12, front - 0.07, hz - 0.165, 0.09, mat="polymer")
    tube("guard", [(cx + 0.14, 0, hz - 0.15), (cx + 0.13, 0, hz - 0.25), (cx - 0.06, 0, hz - 0.255),
                   (cx - 0.13, 0, hz - 0.19)], 0.018, m["polymer"])
    tube("trigger", [(cx - 0.03, 0, hz - 0.13), (cx - 0.015, 0, hz - 0.18), (cx - 0.03, 0, hz - 0.225)], 0.014,
         m["dark"])
    box("slideStop", (0.11, 0.012, 0.022), (cx - 0.05, -0.062, hz - 0.085), m["dark"], bevel=0.004)
    box("takedown", (0.03, 0.012, 0.03), (cx + 0.06, -0.06, hz - 0.1), m["dark"], bevel=0.004)
    cyl_y("pin", 0.012, 0.118, (cx - 0.12, 0, hz - 0.1), m["steel"])
    # Poignée : bec de queue de castor, panneau granité, talon du chargeur.
    gx, gz = back + 0.2, hz - 0.11
    gh = 0.38
    rounded(BW.grip("grip", gx, gz, m["polymer"], h=gh, w=0.2, t=0.13), 0.02, 3)
    prism("beaver", [(back + 0.02, gz + 0.01), (back + 0.08, gz + 0.01), (back - 0.02, gz - 0.05),
                     (back - 0.03, gz - 0.02)], 0.12, m["polymer"])
    slant = 0.28
    prism("stipple", [(gx - 0.04, gz - 0.07), (gx - 0.17, gz - 0.07), (gx - 0.17 - 0.26 * slant, gz - 0.33),
                      (gx - 0.04 - 0.26 * slant, gz - 0.33)], 0.135, m["polymer_tex"])
    rounded(box("magbase", (0.22, 0.13, 0.035), (gx - 0.2 - gh * slant + 0.1, 0, gz - gh - 0.012),
                m["polymer"]), 0.01, 2)
    return {"grip": (back + 0.06, 0, hz - 0.30), "muzzle": (front + 0.04, 0, hz + 0.012)}


# --------------------------------------------------------------------------- AK-47 (Commun)

def rifle_ak47(m):
    rz = 0.18
    # Boîtier embouti, rivets, levier de sélection, levier d'armement, couvercle nervuré.
    rounded(box("receiver", (0.82, 0.13, 0.19), (0.10, 0, rz), m["blued"], bevel=0.012), 0.008, 2)
    rivets([(-0.22, 0.12), (-0.18, 0.12), (0.38, 0.12), (0.42, 0.12), (0.40, 0.23), (-0.20, 0.23)], 0.011,
           m["steel"], -0.066)
    box("selector", (0.36, 0.012, 0.034), (0.12, -0.072, 0.235), m["dark"], rot=(0, -0.04, 0), bevel=0.004)
    box("selTab", (0.05, 0.02, 0.06), (-0.07, -0.078, 0.22), m["dark"], bevel=0.004)
    rounded(prism("cover", [(-0.30, 0.27), (0.50, 0.27), (0.52, 0.30), (0.44, 0.335), (-0.24, 0.335),
                            (-0.30, 0.31)], 0.124, m["blued"]), 0.01, 2)
    grooves(-0.12, 3, 0.12, (0.012, 0.128, 0.05), 0.30, m["dark"])
    box("chargeH", (0.05, 0.05, 0.035), (0.46, -0.09, 0.26), m["steel"], bevel=0.006)
    box("magwell", (0.18, 0.135, 0.05), (0.38, 0, 0.09), m["blued"], bevel=0.006)
    # Hausse (bloc + planchette graduée), bloc de gaz, guidon dans sa protection.
    rounded(box("rsBlock", (0.16, 0.10, 0.08), (0.58, 0, 0.32), m["blued"]), 0.008, 2)
    prism("rsLeaf", [(0.52, 0.355), (0.70, 0.355), (0.70, 0.37), (0.52, 0.385)], 0.06, m["dark"])
    box("rsSlide", (0.04, 0.075, 0.03), (0.62, 0, 0.375), m["steel"], bevel=0.004)
    # Garde-main bas (bois, collier acier) et haut sur le tube de gaz.
    rounded(prism("hgLow", [(0.53, 0.22), (1.10, 0.22), (1.12, 0.17), (1.08, 0.10), (0.57, 0.09), (0.53, 0.13)],
                  0.15, m["wood"]), 0.025, 3)
    box("hgGroove", (0.40, 0.154, 0.012), (0.82, 0, 0.15), m["wood_dark"], bevel=0.0)
    box("hgBand", (0.035, 0.158, 0.145), (0.535, 0, 0.16), m["blued"], bevel=0.005)
    box("hgBand2", (0.04, 0.158, 0.13), (1.12, 0, 0.165), m["blued"], bevel=0.005)
    rounded(cyl_x("hgUp", 0.05, 0.05, 0.42, (0.90, 0, 0.30), m["wood"]), 0.012, 2)
    cyl_x("gasTube", 0.034, 0.034, 0.14, (1.17, 0, 0.30), m["blued"])
    grooves(1.13, 2, 0.04, (0.012, 0.072, 0.03), 0.30, m["bore"])
    rounded(box("gasBlock", (0.08, 0.09, 0.16), (1.26, 0, 0.26), m["blued"]), 0.008, 2)
    box("fsBase", (0.07, 0.07, 0.10), (1.48, 0, 0.27), m["blued"], bevel=0.006)
    tube("fsHood", [(1.48, -0.035, 0.32), (1.48, -0.035, 0.38), (1.48, 0.035, 0.38), (1.48, 0.035, 0.32)],
         0.009, m["blued"], seg=8)
    box("fsPost", (0.014, 0.014, 0.07), (1.48, 0, 0.34), m["dark"], bevel=0.0)
    # Canon, baguette de nettoyage, frein de bouche en biseau, tenon de baïonnette.
    cyl_x("barrel", 0.031, 0.031, 0.50, (1.30, 0, 0.21), m["steel"])
    cyl_x("rod", 0.011, 0.011, 0.86, (1.12, 0, 0.12), m["steel"], seg=10)
    rounded(prism("brake", [(1.54, 0.17), (1.62, 0.17), (1.66, 0.215), (1.62, 0.255), (1.54, 0.255)], 0.08,
                  m["blued"]), 0.008, 2)
    cyl_x("muzzleBore", 0.016, 0.016, 0.01, (1.665, 0, 0.215), m["bore"])
    box("lug", (0.06, 0.03, 0.03), (1.46, 0, 0.16), m["blued"], bevel=0.004)
    # Chargeur courbe en acier nervuré.
    pts = C.bezier((0.30, 0, 0.08), (0.30, 0, -0.18), (0.38, 0, -0.34), (0.54, 0, -0.47), 10)
    secs = [[(x, -0.052, z), (x + 0.15, -0.052, z), (x + 0.15, 0.052, z), (x, 0.052, z)] for (x, _y, z) in pts]
    rounded(C.mesh_obj("mag", C.bm_loft(secs), m["blued"], smooth=False), 0.01, 2)
    for k in range(1, 8):
        x, _y, z = pts[k]
        box("magRib", (0.13, 0.108, 0.012), (x + 0.075, 0, z), m["blued"], bevel=0.003)
    # Poignée, pontet, détente.
    rounded(BW.grip("grip", 0.00, 0.08, m["bakelite"], h=0.36, w=0.14), 0.02, 3)
    grooves(-0.06, 4, 0.045, (0.012, 0.142, 0.022), -0.06, m["wood_dark"], rot=(0, 0.28, 0))
    tube("guard", [(0.26, 0, 0.08), (0.25, 0, -0.04), (0.04, 0, -0.04), (0.01, 0, 0.06)], 0.016, m["blued"])
    tube("trigger", [(0.12, 0, 0.08), (0.135, 0, 0.03), (0.12, 0, -0.01)], 0.013, m["dark"])
    # Crosse bois (veinage), plaque de couche acier, battant de bretelle.
    rounded(prism("stock", [(-0.30, 0.28), (-0.30, 0.09), (-0.55, 0.01), (-0.97, -0.18), (-0.97, 0.25),
                            (-0.55, 0.27)], 0.13, m["wood"]), 0.03, 3)
    rounded(box("butt", (0.04, 0.14, 0.44), (-0.99, 0, 0.035), m["blued"]), 0.01, 2)
    rivets([(-0.99, 0.18), (-0.99, -0.11)], 0.012, m["steel"], -0.072)
    tube("swivel", [(-0.70, 0, -0.04), (-0.70, 0, -0.10), (-0.62, 0, -0.10), (-0.62, 0, -0.06)], 0.009,
         m["steel"], seg=8)
    return {"grip": (-0.10, 0, -0.10), "muzzle": (1.66, 0, 0.215)}


# --------------------------------------------------------------------------- AUG (Légendaire)

def rifle_aug(m):
    # Corps bullpup moulé (bords très arrondis), éclats d'or, filets dorés.
    body = rounded(prism("body", [(-0.86, 0.30), (-0.86, -0.02), (-0.72, -0.13), (-0.20, -0.13), (-0.12, 0.03),
                                  (0.40, 0.05), (0.52, 0.17), (0.52, 0.29), (0.40, 0.32), (-0.70, 0.32)],
                          0.17, m["legend"]), 0.05, 4)
    body.name = "body"
    for z in (0.30, 0.0):
        box("goldLine", (1.10, 0.176, 0.012), (-0.30, 0, z + 0.004), m["gold"], bevel=0.0)
    rounded(box("butt", (0.05, 0.18, 0.34), (-0.88, 0, 0.13), m["rubber"]), 0.02, 3)
    grooves(-0.88, 1, 0.0, (0.054, 0.184, 0.012), 0.06, m["bore"])
    # Chargeur fumé translucide (cartouches dorées visibles en haut), poignée, grand pontet.
    rounded(BW.mag("mag", -0.42, -0.10, m["smoke"], h=0.34, w=0.16, t=0.11, curve=0.05), 0.012, 2)
    box("rounds", (0.12, 0.112, 0.05), (-0.34, 0, -0.16), m["brass"], bevel=0.008)
    rounded(BW.grip("grip", 0.10, 0.04, m["legend_flat"], h=0.34, w=0.14, slant=0.15), 0.025, 3)
    tube("guardLoop", [(-0.08, 0, 0.0), (-0.10, 0, -0.30), (0.20, 0, -0.33), (0.40, 0, -0.30), (0.42, 0, 0.04)],
         0.022, m["legend_flat"])
    tube("trigger", [(0.02, 0, 0.0), (0.035, 0, -0.06), (0.02, 0, -0.10)], 0.014, m["gold"])
    cyl_y("crossbolt", 0.022, 0.18, (-0.02, 0, 0.12), m["gold"])
    rounded(box("ejection", (0.22, 0.014, 0.08), (-0.36, -0.088, 0.17), m["legend_flat"], bevel=0.0), 0.008, 2)
    box("ejLine", (0.22, 0.016, 0.008), (-0.36, -0.089, 0.13), m["bore"], bevel=0.0)
    rounded(prism("cheek", [(-0.84, 0.24), (-0.40, 0.25), (-0.44, 0.06), (-0.80, 0.04)], 0.18,
                  m["legend_flat"]), 0.03, 3)
    prism("gripTex", [(0.06, 0.0), (0.0, 0.0), (-0.05, -0.30), (0.01, -0.30)], 0.144, m["polymer_tex"])
    tube("sling", [(-0.80, -0.0, -0.06), (-0.80, 0, -0.12), (-0.72, 0, -0.12), (-0.72, 0, -0.08)], 0.012,
         m["gold"], seg=8)
    box("magRelease", (0.05, 0.19, 0.03), (-0.20, 0, -0.10), m["gold"], bevel=0.006)
    # Poignée avant repliable.
    rounded(prism("vgrip", [(0.40, 0.06), (0.52, 0.06), (0.50, -0.30), (0.40, -0.32), (0.38, -0.20)], 0.10,
                  m["legend_flat"]), 0.03, 3)
    grooves(0.42, 1, 0.0, (0.1, 0.104, 0.012), -0.26, m["gold"], rot=(0, 0.1, 0))
    # Canon, cylindre de gaz, cache-flamme à fentes doré.
    cyl_x("barrel", 0.04, 0.04, 0.66, (0.84, 0, 0.20), m["blued"])
    cyl_x("gas", 0.03, 0.03, 0.30, (0.68, 0, 0.27), m["blued"])
    cyl_x("flash", 0.056, 0.05, 0.16, (1.22, 0, 0.20), m["gold"])
    for k in range(3):
        box("slot", (0.08, 0.02, 0.016), (1.22, -0.052, 0.17 + k * 0.03), m["bore"], bevel=0.0)
    cyl_x("muzzleBore", 0.02, 0.02, 0.01, (1.30, 0, 0.20), m["bore"])
    # Lunette intégrée sur la poignée de transport : bagues dorées, oculaire caoutchouc, verre.
    rounded(prism("carry", [(-0.42, 0.32), (0.30, 0.32), (0.24, 0.42), (-0.36, 0.42)], 0.09, m["legend_flat"]),
            0.02, 3)
    zs = 0.49
    cyl_x("scope", 0.07, 0.07, 0.56, (-0.06, 0, zs), m["legend_flat"])
    cyl_x("scopeF", 0.07, 0.09, 0.10, (0.27, 0, zs), m["legend_flat"])
    cyl_x("scopeB", 0.085, 0.07, 0.09, (-0.39, 0, zs), m["rubber"])
    for xx in (-0.28, 0.16):
        cyl_x("ring", 0.079, 0.079, 0.035, (xx, 0, zs), m["gold"])
    cyl_x("lens", 0.085, 0.085, 0.01, (0.325, 0, zs), m["glass"])
    cyl_x("lensB", 0.07, 0.07, 0.01, (-0.44, 0, zs), m["glass"])
    cyl_y("turret", 0.034, 0.17, (-0.06, 0, zs), m["gold"])
    box("turretTop", (0.06, 0.06, 0.05), (-0.06, 0, zs + 0.085), m["gold"], bevel=0.008)
    return {"grip": (0.0, 0, -0.12), "muzzle": (1.31, 0, 0.20)}


WEAPONS = {"pistol_p9": pistol_p9, "rifle_ak47": rifle_ak47, "rifle_aug": rifle_aug}
