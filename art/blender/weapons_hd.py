"""Armes HD : modèles détaillés et matériaux peints (weapon_paint.py), rendus en double résolution.

Usage (depuis la racine du projet, environnement tools/prerender/mac_env.sh) :
    python3 art/blender/weapons_hd.py                         # toutes les armes HD
    python3 art/blender/weapons_hd.py pistol_p9 rifle_aug     # quelques-unes
    python3 art/blender/weapons_hd.py --compare out.png [ids] # planche avant (git HEAD) / après

Mêmes sorties et mêmes repères que build_weapons.py (qui reste la référence des armes non refaites) :
- assets/sprites/weapons/<id>.png + .json : arme tenue, 3/4 plongeant, canon vers la droite. Deux fois
  plus de pixels par unité (PX_PER_UNIT 88) et échelle moitié (0.225) : même taille en jeu, image nette ;
- assets/ui/weapons/<id>.png + .json : icône de profil 512 × 256 (grip, muzzle, size).
Repère : X = canon, Z = haut, Y = profondeur (côté visible = -Y).
Rareté visible sur l'arme : Commun polymère et acier noir mat, Rare acier patiné, Épique bois et
gravures, Légendaire noir à éclats d'or.
"""
from __future__ import annotations

import json
import math
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import weapon_paint as WP  # noqa: E402
import build_weapons as BW  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

ROOT = BW.ROOT
OUT = BW.OUT
OUT_ICON = BW.OUT_ICON
TMP = os.environ.get("RDM_TMP", "/tmp/rdm_weapons_hd")
SS = 3
PX_PER_UNIT = 88.0
HELD_SCALE = BW.HELD_SCALE * BW.PX_PER_UNIT / PX_PER_UNIT   # même taille en jeu
ICON_SIZE = (512, 256)
SAMPLES = 48
OUTLINE_HELD = 2.0
OUTLINE_ICON = 3.4
INNER_RATIO = 0.28


# --------------------------------------------------------------------------- matériaux

def mats():
    P = WP.paint
    return {
        # polymère et acier noir mat (Commun)
        "polymer": P("polymer", "#2a2c33", "#0b0c16", "#5a5d6a", wear=0.45, grain=0.07, edge="#6e717e"),
        "polymer_tex": P("polymer_tex", "#2c2e35", "#09090f", "#555865", wear=0.2, grain=0.45, grain_scale=140.0),
        "blued": P("blued", "#30323a", "#0c0d18", "#646a7c", metal=0.55, wear=0.55, grain=0.05, edge="#9aa0b0"),
        "steel": P("steel", "#767b88", "#24283e", "#c8ccd8", metal=0.7, wear=0.4, grain=0.04),
        "dark": P("dark", "#3a3c44", "#101220", "#70747f", metal=0.4, wear=0.35, grain=0.05),
        "bore": P("bore", "#0c0c10", "#050508", "#1a1a20", ao=0.0, rim=0.0, grain=0.0),
        "rubber": P("rubber", "#232328", "#09090e", "#3e3e46", grain=0.12, grain_scale=180.0, rim=0.15),
        "white": P("white", "#f2efe4", "#9a98a8", "#ffffff", ao=0.0, grain=0.0, rim=0.0),
        "glass": P("glass", "#3c5e86", "#0e1a34", "#a8d0f0", gloss=0.9, ao=0.2, grain=0.0),
        # bois (AK)
        "wood": P("wood", "#a2602c", "#3c1a18", "#d88e48", wood=1.0, gloss=0.25, wear=0.3, grain=0.04,
                  edge="#e8b070"),
        "wood_dark": P("wood_dark", "#6e3c1e", "#2a1214", "#a2643a", wood=1.0, gloss=0.2, wear=0.25),
        "bakelite": P("bakelite", "#8c3e1e", "#341414", "#c46a3a", gloss=0.35, wear=0.2, grain=0.03),
        # Légendaire : noir à éclats d'or
        "legend": P("legend", "#202027", "#07070c", "#4a4a58", wear=0.35, grain=0.06, alt="#d8a640",
                    alt_scale=9.0, alt_cut=0.64),
        "legend_flat": P("legend_flat", "#1e1e25", "#07070c", "#42424e", wear=0.35, grain=0.06),
        "gold": P("gold", "#d9aa45", "#5e3a26", "#ffe7a0", metal=1.0, wear=0.3, grain=0.03, edge="#fff4cc"),
        "smoke": P("smoke", "#4a4034", "#16120e", "#8a7a62", gloss=0.6, grain=0.02),
        "brass": P("brass", "#b48a3c", "#4a2e1e", "#f0cc7a", metal=0.9, grain=0.02),
    }


# --------------------------------------------------------------------------- briques

def rounded(ob, width=0.02, segs=3, angle=40.0):
    """Arêtes arrondies (modificateur Biseau) : polymère moulé, bois poncé."""
    md = ob.modifiers.new("bev", "BEVEL")
    md.width = width
    md.segments = segs
    md.limit_method = "ANGLE"
    md.angle_limit = math.radians(angle)
    return ob


def box(name, size, loc, mat, rot=(0, 0, 0), bevel=0.01):
    return BW.box(name, size, loc, mat, rot=rot, bevel=bevel)


def cyl_x(name, r1, r2, length, loc, mat, seg=24):
    return BW.cyl_x(name, r1, r2, length, loc, mat, seg=seg)


def cyl_y(name, r, depth, loc, mat, seg=20):
    return BW.cyl_y(name, r, depth, loc, mat, seg=seg)


def prism(name, prof, depth, mat, y=0.0):
    return BW.prism(name, prof, depth, mat, y=y)


def sphere(name, r, loc, mat, scale=(1, 1, 1), seg=12):
    bm = C.bm_xform(C.bm_sphere(seg, max(4, seg // 2), 1.0), loc=loc, scale=(r * scale[0], r * scale[1], r * scale[2]))
    return C.mesh_obj(name, bm, mat)


def tube(name, pts, r, mat, seg=10):
    return C.mesh_obj(name, C.bm_tube(pts, [r] * len(pts), seg=seg), mat)


def grooves(x0, n, step, size, z, mat, rot=(0, 0, 0)):
    """Rainures (serrations, nervures) : fines lames sombres qui dépassent un peu de la pièce."""
    for k in range(n):
        box("groove", size, (x0 + k * step, 0, z), mat, rot=rot, bevel=0.0)


def rivets(pts, r, mat, y):
    for (x, z) in pts:
        sphere("rivet", r, (x, y, z), mat, scale=(1, 0.55, 1), seg=10)


def rail(m, x0, x1, z, depth=0.08, mat="dark"):
    box("rail", (x1 - x0, depth, 0.03), ((x0 + x1) / 2, 0, z), m[mat], bevel=0.004)
    n = int((x1 - x0) / 0.05)
    for k in range(n):
        box("railT", (0.026, depth + 0.006, 0.022), (x0 + 0.025 + k * 0.05, 0, z + 0.024), m[mat], bevel=0.004)


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


HD = {"pistol_p9": pistol_p9, "rifle_ak47": rifle_ak47, "rifle_aug": rifle_aug}


# --------------------------------------------------------------------------- skins d'armes

def _skin_mats(over, base_fn):
    """Jeu de matériaux de l'arme (base_fn) avec certaines clés remplacées (over() -> {clé: matériau})."""
    def f():
        m = base_fn()
        m.update(over())
        return m
    return f


def _tiger():
    import build_weapon_skins as BWS
    stripes = BWS.mask_bands(24.0, 0.5, warp=0.35, axis="X", tilt=0.45)
    tiger = WP.paint("skT_tiger", "#f08a1e", "#6a2c12", "#ffc46a", gloss=0.3, wear=0.2, grain=0.03,
                     layers=[("#1a120e", stripes)])
    return {"wood": tiger, "wood_dark": tiger, "bakelite": tiger,
            "blued": WP.paint("skT_black", "#28231f", "#0a0808", "#544a40", metal=0.5, wear=0.5)}


def _flames():
    import build_weapon_skins as BWS
    red = BWS.mask_flames(-0.6, tongues=13.0, depth=0.42)
    yellow = BWS.mask_flames(-0.1, tongues=13.0, depth=0.42)
    fl = WP.paint("skF_flames", "#1c181e", "#060408", "#443c48", gloss=0.35, wear=0.25,
                  layers=[("#e0281a", red), ("#ffc02a", yellow)])
    return {"legend": fl, "legend_flat": fl,
            "gold": WP.paint("skF_gold", "#ffc02a", "#8a4a1a", "#fff2a0", metal=1.0, wear=0.3)}


SKINS = {"wsk_ak47_tiger": ("rifle_ak47", _tiger), "wsk_aug_flames": ("rifle_aug", _flames)}
OUT_SKIN_HELD = os.path.join(OUT, "skins")
OUT_SKIN_ICON = os.path.join(OUT_ICON, "skins")


# --------------------------------------------------------------------------- rendu

def _render(wid, build, elev, size, outline, pad_px, azim=0.0, ppu=PX_PER_UNIT):
    C.reset_scene()
    WP.reset()
    info = build(mats())
    pts = BW._points()
    cam = C.ortho_camera(elev, 10.0, target=(0, 0, 0), azim_deg=azim)
    bpy.context.view_layer.update()
    u, v = BW._cam_uv(cam, pts)
    cu, cv = (u.min() + u.max()) / 2, (v.min() + v.max()) / 2
    w_u, h_u = u.max() - u.min(), v.max() - v.min()
    if size is None:
        W = int(math.ceil((w_u * ppu + 2 * pad_px) / 4.0) * 4)
        H = int(math.ceil((h_u * ppu + 2 * pad_px) / 4.0) * 4)
        ortho = W / ppu
    else:
        W, H = size
        ortho = max(w_u / (W - 2 * pad_px) * W, h_u / (H - 2 * pad_px) * W)
    cam.location = cam.location + cam.matrix_world.to_3x3() @ Vector((cu, cv, 0))
    cam.data.ortho_scale = ortho
    cam.data.sensor_fit = "HORIZONTAL"
    C.setup_render((W * SS, H * SS), samples=SAMPLES, outline_px=outline * SS, inner_ratio=INNER_RATIO)
    bpy.context.scene.camera = cam
    os.makedirs(TMP, exist_ok=True)
    big = os.path.join(TMP, wid + "_big.png")
    C.render_to(big)
    return big, cam, info, (W, H)


def _px(cam, co):
    g = C.world_to_px(cam, co)
    return [round(g[0] / SS, 1), round(g[1] / SS, 1)]


def render_skin(skin_id: str) -> None:
    """Skin d'arme : même modèle et même cadrage que l'arme (grip/muzzle du JSON de l'arme valables)."""
    wid, over = SKINS[skin_id]
    global mats
    base = mats
    mats = _skin_mats(over, base)
    try:
        big, _cam, _info, (W, H) = _render(skin_id, HD[wid], BW.HELD_ELEV, None, OUTLINE_HELD, 6)
        C.downscale(big, os.path.join(OUT_SKIN_HELD, skin_id + ".png"), (W, H))
        big, _cam, _info, (W2, H2) = _render(skin_id + "_icon", HD[wid], BW.ICON_ELEV, ICON_SIZE, OUTLINE_ICON, 20,
                                             azim=BW.ICON_AZIM)
        C.downscale(big, os.path.join(OUT_SKIN_ICON, skin_id + ".png"), (W2, H2))
    finally:
        mats = base
    print("SKIN", skin_id, (W, H), (W2, H2), flush=True)


def render_item(wid: str) -> None:
    fn = HD[wid]
    big, cam, info, (W, H) = _render(wid, fn, BW.HELD_ELEV, None, OUTLINE_HELD, 6)
    C.downscale(big, os.path.join(OUT, wid + ".png"), (W, H))
    meta = {"grip": [round(x) for x in _px(cam, info["grip"])],
            "muzzle": [round(x) for x in _px(cam, info["muzzle"])],
            "scale": round(HELD_SCALE, 4), "size": [W, H], "rarity": BW.RARITY[wid]}
    with open(os.path.join(OUT, wid + ".json"), "w", newline="\n") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    big, cam, info, (W, H) = _render(wid, fn, BW.ICON_ELEV, ICON_SIZE, OUTLINE_ICON, 20, azim=BW.ICON_AZIM)
    C.downscale(big, os.path.join(OUT_ICON, wid + ".png"), (W, H))
    imeta = {"grip": _px(cam, info["grip"]), "muzzle": _px(cam, info["muzzle"]), "size": [W, H]}
    with open(os.path.join(OUT_ICON, wid + ".json"), "w", newline="\n") as f:
        json.dump(imeta, f, indent=2)
        f.write("\n")
    print("HD", wid, meta, flush=True)


def compare(out: str, ids: list[str]) -> None:
    """Planche avant (version git HEAD) / après : icône et arme tenue, sur fond de rareté."""
    from io import BytesIO
    from PIL import Image, ImageDraw

    def old(path):
        rel = os.path.relpath(path, ROOT)
        data = subprocess.run(["git", "-C", ROOT, "show", "HEAD:" + rel], capture_output=True).stdout
        return Image.open(BytesIO(data)).convert("RGBA") if data else None

    cw, ch = 560, 330
    sheet = Image.new("RGBA", (cw * 2 + 30, ch * len(ids) + 50), (16, 18, 30, 255))
    dr = ImageDraw.Draw(sheet)
    dr.text((20, 14), "AVANT", fill=(220, 220, 230, 255))
    dr.text((cw + 30, 14), "APRES", fill=(220, 220, 230, 255))
    for r, wid in enumerate(ids):
        y = 40 + r * ch
        col = BW.RARITY_COL[BW.RARITY[wid]]
        for c, get in enumerate((old, lambda p: Image.open(p).convert("RGBA"))):
            x = 10 + c * (cw + 10)
            dr.rounded_rectangle((x, y, x + cw, y + ch - 10), 10, outline=col, width=2,
                                 fill=(col[0] // 7 + 16, col[1] // 7 + 18, col[2] // 7 + 30, 255))
            ic = get(os.path.join(OUT_ICON, wid + ".png"))
            if ic is not None:
                ic.thumbnail((512, 200))
                sheet.alpha_composite(ic, (x + (cw - ic.width) // 2, y + 8))
            held = get(os.path.join(OUT, wid + ".png"))
            if held is not None:
                # Arme tenue à sa taille en jeu (échelle du JSON) × 2 pour la voir.
                meta_scale = BW.HELD_SCALE if c == 0 else HELD_SCALE
                k = meta_scale / BW.HELD_SCALE * 2.0
                held = held.resize((max(1, int(held.width * k)), max(1, int(held.height * k))), Image.LANCZOS)
                sheet.alpha_composite(held, (x + 14, y + ch - 20 - held.height))
            dr.text((x + cw - 160, y + ch - 30), wid, fill=(240, 240, 240, 255))
    sheet.save(out)
    print("COMPARE", out, flush=True)


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ids = [a for a in args if a in HD]
    if "--compare" in args:
        compare(args[args.index("--compare") + 1], ids or list(HD))
        return
    for wid in (ids or list(HD)):
        render_item(wid)
    # Skins des armes rendues (même taille d'image que l'arme : grip/muzzle partagés).
    for sid, (wid, _o) in SKINS.items():
        if wid in (ids or list(HD)):
            render_skin(sid)


if __name__ == "__main__":
    main()
