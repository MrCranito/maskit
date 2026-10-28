"""Armes à feu d'Exfil Rush : sprites tenus (3/4 plongeant, canon vers la DROITE) + icônes d'inventaire.

Usage (depuis la racine du projet) :
    python3 art/blender/build_weapons.py              # toutes les armes (sprites + icônes)
    python3 art/blender/build_weapons.py smg sniper   # quelques-unes
    python3 art/blender/build_weapons.py --sheet out.png   # planche-contact des icônes (après rendu)

Sorties :
- assets/sprites/weapons/<id>.png + <id>.json (grip, muzzle en px dans l'image, scale, size)
- assets/ui/weapons/<id>.png (vue de profil, 192x96, fond transparent)
Repère de modélisation : X = vers l'avant (canon), Z = haut, Y = profondeur (côté visible = -Y).
Échelle commune : PX_PER_UNIT px par unité Blender dans le sprite tenu (tailles relatives cohérentes).
Teintes NEUTRES (acier, polymère, bois désaturé) : la rareté est affichée par l'UI et les skins
d'armes recolorent par shader en conservant la luminance.
"""
from __future__ import annotations

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import bpy  # noqa: E402,F401

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "weapons")
OUT_ICON = os.path.join(ROOT, "assets", "ui", "weapons")
TMP = os.environ.get("RDM_TMP", "/tmp/rdm_weapons")
SS = 4
PX_PER_UNIT = 44.0          # sprite tenu : px par unité Blender
HELD_SCALE = 0.45           # échelle d'affichage en jeu (unités monde par px)
HELD_ELEV = 34.0            # plongée de la vue tenue (cohérente avec le héros, vu de dessus)
ICON_SIZE = (192, 96)
ICON_ELEV = 8.0


def mats():
    return {
        "steel": C.toon("steel", "#a4a8b2", "#363a52", "#eef0f6", rim=0.35),
        "dark": C.toon("darksteel", "#4c505c", "#16182a", "#868c9c", rim=0.30),
        "black": C.toon("polymer", "#34363e", "#101020", "#5c5e68", rim=0.30),
        "wood": C.toon("wood", "#7e5a40", "#30202a", "#a87c58", rim=0.25),
        "tan": C.toon("tan", "#9a8c70", "#3c3434", "#c4b490", rim=0.25),
        "olive": C.toon("olive", "#6a6e5a", "#262a2e", "#90947a", rim=0.25),
        "gold": C.toon("gold", "#d6aa4c", "#6a4430", "#ffe49a", rim=0.40),
        "ivory": C.toon("ivory", "#e6dcc6", "#8a8698", "#fffaf0", rim=0.25),
        "brass": C.toon("brass", "#b89a5c", "#4e3a34", "#e4cc8c", rim=0.35),
        "glass": C.toon("glass", "#6a8aa4", "#1e2a44", "#c4dcec", rim=0.5),
        "rubber": C.toon("rubber", "#2a2a30", "#0c0c16", "#46464e", rim=0.2),
    }


# --------------------------------------------------------------------------- briques

def box(name, size, loc, mat, rot=(0, 0, 0), bevel=0.012):
    return C.mesh_obj(name, C.bm_xform(C.bm_box(*size, bevel=bevel), loc=loc, rot=rot), mat, smooth=False)


def cyl_x(name, r1, r2, length, loc, mat, seg=14, smooth=True):
    bm = C.bm_cyl(seg, r1, r2, length)
    C.bm_xform(bm, loc=loc, rot=(0, math.pi / 2, 0))
    return C.mesh_obj(name, bm, mat, smooth=smooth)


def cyl_y(name, r, depth, loc, mat, seg=14):
    bm = C.bm_cyl(seg, r, r, depth)
    C.bm_xform(bm, loc=loc, rot=(math.pi / 2, 0, 0))
    return C.mesh_obj(name, bm, mat, smooth=True)


def prism(name, prof, depth, mat, y=0.0, smooth=False):
    """Extrusion d'un profil 2D (x, z) sur l'épaisseur `depth` (Y)."""
    secs = [[(x, y - depth / 2, z) for (x, z) in prof], [(x, y + depth / 2, z) for (x, z) in prof]]
    bm = C.bm_loft(secs)
    return C.mesh_obj(name, bm, mat, smooth=smooth)


def grip(name, x, z, mat, h=0.36, w=0.15, t=0.13, slant=0.28):
    """Poignée pistolet inclinée vers l'arrière ; (x, z) = haut avant."""
    prof = [(x, z), (x - w, z), (x - w - h * slant, z - h), (x - h * slant + 0.01, z - h)]
    return prism(name, prof, t, mat)


def guard(name, x0, x1, z, mat, depth=0.11):
    pts = C.bezier((x1, 0, z), (x1, 0, z - 0.14), (x0 + 0.02, 0, z - 0.14), (x0, 0, z - 0.02), 8)
    return C.mesh_obj(name, C.bm_tube(pts, [0.018] * 8, seg=6), mat)


def mag(name, x, z, mat, h=0.36, w=0.13, t=0.10, curve=0.0):
    prof = [(x, z), (x + w, z), (x + w + curve, z - h), (x + curve, z - h)]
    return prism(name, prof, t, mat)


def scope(m, x0, x1, z, r=0.075, body="black"):
    L = x1 - x0
    cyl_x("scope", r * 0.75, r * 0.75, L * 0.6, ((x0 + x1) / 2, 0, z), m[body])
    cyl_x("scopeF", r * 0.75, r * 1.25, L * 0.22, (x1 - L * 0.11, 0, z), m[body])
    cyl_x("scopeB", r * 1.1, r * 0.75, L * 0.20, (x0 + L * 0.10, 0, z), m[body])
    cyl_x("lens", r * 1.05, r * 1.05, 0.012, (x1 + 0.004, 0, z), m["glass"])
    cyl_y("turret", r * 0.45, 0.06, ((x0 + x1) / 2, -r * 0.8, z), m["dark"])
    box("turretT", (0.07, 0.07, 0.06), ((x0 + x1) / 2, 0, z + r * 0.95), m["dark"])
    for xx in (x0 + L * 0.3, x1 - L * 0.35):
        box("ring", (0.06, 0.09, 0.07), (xx, 0, z - r - 0.02), m["dark"])


def rail(m, x0, x1, z, depth=0.08):
    box("rail", (x1 - x0, depth, 0.03), ((x0 + x1) / 2, 0, z), m["dark"])
    n = int((x1 - x0) / 0.06)
    for k in range(n):
        box("railT", (0.03, depth + 0.004, 0.022), (x0 + 0.03 + k * 0.06, 0, z + 0.024), m["dark"], bevel=0.0)


# --------------------------------------------------------------------------- armes

def w_starter_pistol(m):
    # petit pistolet compact, carcasse polymère, glissière acier
    box("slide", (0.62, 0.11, 0.13), (0.20, 0, 0.17), m["steel"])
    for k in range(4):
        box("serr", (0.012, 0.115, 0.10), (-0.04 + k * 0.03, 0, 0.17), m["dark"], bevel=0.0)
    box("frame", (0.56, 0.10, 0.08), (0.18, 0, 0.07), m["black"])
    cyl_x("barrel", 0.035, 0.035, 0.06, (0.52, 0, 0.18), m["dark"])
    box("sightF", (0.03, 0.03, 0.04), (0.47, 0, 0.25), m["dark"], bevel=0.0)
    box("sightB", (0.04, 0.05, 0.04), (-0.06, 0, 0.25), m["dark"], bevel=0.0)
    grip("grip", 0.08, 0.06, m["black"], h=0.34, w=0.16)
    guard("guard", 0.10, 0.28, 0.04, m["black"])
    return {"grip": (-0.03, 0, -0.10), "muzzle": (0.56, 0, 0.18)}


def w_pistol(m):
    box("slide", (0.82, 0.12, 0.15), (0.26, 0, 0.18), m["dark"])
    for k in range(5):
        box("serr", (0.012, 0.125, 0.11), (-0.08 + k * 0.03, 0, 0.18), m["black"], bevel=0.0)
    box("port", (0.14, 0.01, 0.05), (0.30, -0.062, 0.20), m["black"], bevel=0.0)
    box("frame", (0.72, 0.11, 0.09), (0.22, 0, 0.07), m["black"])
    rail(m, 0.36, 0.56, 0.015, 0.09)
    cyl_x("barrel", 0.035, 0.035, 0.06, (0.68, 0, 0.19), m["steel"])
    box("sightF", (0.03, 0.03, 0.04), (0.62, 0, 0.27), m["steel"], bevel=0.0)
    box("sightB", (0.05, 0.06, 0.04), (-0.08, 0, 0.27), m["steel"], bevel=0.0)
    grip("grip", 0.08, 0.06, m["black"], h=0.40, w=0.17)
    box("magbase", (0.17, 0.12, 0.03), (-0.10, 0, -0.35), m["dark"])
    guard("guard", 0.10, 0.32, 0.04, m["black"])
    return {"grip": (-0.04, 0, -0.12), "muzzle": (0.72, 0, 0.19)}


def w_pistol_heavy(m):
    # gros calibre type « desert », glissière massive, canon triangulaire
    box("slide", (1.00, 0.16, 0.22), (0.32, 0, 0.21), m["steel"], bevel=0.02)
    box("rib", (0.95, 0.06, 0.03), (0.34, 0, 0.335), m["dark"])
    for k in range(6):
        box("vent", (0.04, 0.165, 0.05), (0.42 + k * 0.08, 0, 0.27), m["dark"], bevel=0.0)
    box("frame", (0.80, 0.14, 0.12), (0.22, 0, 0.05), m["dark"], bevel=0.02)
    cyl_x("muzzle", 0.05, 0.05, 0.04, (0.83, 0, 0.21), m["black"])
    box("hammer", (0.08, 0.07, 0.10), (-0.20, 0, 0.30), m["dark"], rot=(0, -0.5, 0))
    grip("grip", 0.06, 0.02, m["black"], h=0.46, w=0.20, t=0.16)
    guard("guard", 0.08, 0.34, 0.00, m["dark"], 0.14)
    return {"grip": (-0.08, 0, -0.18), "muzzle": (0.85, 0, 0.21)}


def _revolver(m, frame_mat, accent, grip_mat, barrel_len=0.85):
    x1 = 0.20 + barrel_len
    cyl_x("barrel", 0.055, 0.055, barrel_len, ((0.20 + x1) / 2, 0, 0.20), frame_mat, seg=8)
    box("rib", (barrel_len, 0.045, 0.035), ((0.20 + x1) / 2, 0, 0.265), frame_mat)
    box("sight", (0.05, 0.03, 0.06), (x1 - 0.05, 0, 0.29), m["dark"], bevel=0.0)
    cyl_x("ejector", 0.028, 0.028, barrel_len * 0.6, (0.20 + barrel_len * 0.32, 0, 0.11), frame_mat, seg=8)
    cyl_x("cylinder", 0.155, 0.155, 0.30, (0.04, 0, 0.17), frame_mat, seg=6)
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        C.mesh_obj("flute", C.bm_xform(C.bm_cyl(8, 0.034, 0.034, 0.26),
                   loc=(0.04, 0.135 * math.cos(a), 0.17 + 0.135 * math.sin(a)), rot=(0, math.pi / 2, 0)), accent)
    box("frame", (0.48, 0.11, 0.34), (0.0, 0, 0.14), frame_mat, bevel=0.02)
    guard("guard", -0.16, 0.08, -0.02, frame_mat)
    box("hammer", (0.10, 0.05, 0.14), (-0.25, 0, 0.32), m["dark"], rot=(0, -0.6, 0))
    path = C.bezier((-0.20, 0, 0.10), (-0.32, 0, -0.05), (-0.43, 0, -0.25), (-0.41, 0, -0.48), 7)
    secs = []
    for (x, y, z), w in zip(path, [0.15, 0.15, 0.16, 0.17, 0.18, 0.19, 0.20]):
        secs.append([(x - w * 0.55, -0.075, z), (x + w * 0.45, -0.075, z), (x + w * 0.45, 0.075, z), (x - w * 0.55, 0.075, z)])
    g = C.mesh_obj("grip", C.bm_loft(secs), grip_mat, smooth=False)
    C.subsurf(g, 1)
    C.mesh_obj("cap", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(-0.415, 0, -0.50), scale=(0.11, 0.08, 0.04)), frame_mat)
    return {"grip": (-0.33, 0, -0.18), "muzzle": (x1 + 0.02, 0, 0.20)}


def w_revolver(m):
    return _revolver(m, m["steel"], m["dark"], m["wood"])


def w_revolver_gold(m):
    info = _revolver(m, m["gold"], m["brass"], m["ivory"], barrel_len=0.95)
    for sy in (-1, 1):
        pts = C.bezier((-0.15, 0.058 * sy, 0.05), (-0.05, 0.058 * sy, 0.18), (0.10, 0.058 * sy, 0.02), (0.20, 0.058 * sy, 0.12), 8)
        C.mesh_obj("engrave", C.bm_tube(pts, [0.016] * 8, seg=6), m["brass"])
    C.mesh_obj("medal", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(-0.34, -0.078, -0.22), scale=(0.045, 0.015, 0.045)), m["gold"])
    return info


def w_smg(m):
    box("receiver", (0.95, 0.14, 0.20), (0.15, 0, 0.16), m["black"], bevel=0.02)
    box("top", (0.80, 0.10, 0.05), (0.15, 0, 0.285), m["dark"])
    cyl_x("shroud", 0.075, 0.075, 0.30, (0.76, 0, 0.18), m["dark"], seg=10)
    for k in range(4):
        cyl_y("hole", 0.022, 0.16, (0.67 + k * 0.065, 0, 0.18), m["black"], seg=8)
    cyl_x("barrel", 0.035, 0.035, 0.12, (0.96, 0, 0.18), m["steel"])
    box("sightF", (0.04, 0.04, 0.08), (0.58, 0, 0.33), m["dark"], bevel=0.0)
    box("sightB", (0.06, 0.06, 0.07), (-0.22, 0, 0.33), m["dark"], bevel=0.0)
    mag("mag", 0.18, 0.08, m["dark"], h=0.50, w=0.12, curve=0.06)
    grip("grip", -0.08, 0.07, m["black"], h=0.34, w=0.15)
    guard("guard", -0.06, 0.15, 0.06, m["black"])
    # crosse repliable en fil d'acier
    pts = [(-0.32, 0, 0.22), (-0.80, 0, 0.20), (-0.82, 0, 0.0), (-0.32, 0, 0.06)]
    C.mesh_obj("stock", C.bm_tube(pts, [0.026] * 4, seg=6), m["dark"])
    box("butt", (0.05, 0.12, 0.26), (-0.82, 0, 0.10), m["rubber"])
    return {"grip": (-0.18, 0, -0.10), "muzzle": (1.02, 0, 0.18)}


def w_smg_compact(m):
    # mitraillette compacte type « boîte » : corps court, chargeur dans la poignée
    box("receiver", (0.66, 0.15, 0.24), (0.12, 0, 0.17), m["black"], bevel=0.03)
    box("top", (0.60, 0.10, 0.04), (0.12, 0, 0.31), m["dark"])
    cyl_x("barrel", 0.04, 0.04, 0.14, (0.52, 0, 0.20), m["steel"])
    cyl_x("muzzle", 0.05, 0.05, 0.05, (0.60, 0, 0.20), m["dark"])
    grip("grip", 0.02, 0.06, m["black"], h=0.44, w=0.15, slant=0.10)
    box("magbase", (0.15, 0.13, 0.04), (-0.08, 0, -0.39), m["dark"])
    guard("guard", 0.04, 0.24, 0.05, m["black"])
    box("strap", (0.06, 0.10, 0.10), (-0.24, 0, 0.18), m["dark"])
    return {"grip": (-0.06, 0, -0.12), "muzzle": (0.63, 0, 0.20)}


def w_shotgun(m):
    # fusil à pompe : canon épais + tube magasin, pompe striée, crosse bois
    cyl_x("barrel", 0.065, 0.065, 1.50, (1.00, 0, 0.21), m["dark"], seg=10)
    cyl_x("tube", 0.060, 0.060, 1.25, (0.88, 0, 0.08), m["dark"], seg=10)
    cyl_x("muzzle", 0.075, 0.075, 0.06, (1.74, 0, 0.21), m["steel"], seg=10)
    box("pump", (0.48, 0.17, 0.16), (0.85, 0, 0.08), m["wood"], bevel=0.03)
    for k in range(6):
        box("ridge", (0.022, 0.175, 0.17), (0.65 + k * 0.08, 0, 0.08), m["dark"], bevel=0.0)
    box("receiver", (0.55, 0.15, 0.30), (0.02, 0, 0.14), m["steel"], bevel=0.025)
    box("port", (0.22, 0.01, 0.08), (0.05, -0.077, 0.18), m["black"], bevel=0.0)
    guard("guard", -0.18, 0.05, -0.01, m["dark"])
    stock = [(-0.26, 0.28), (-0.26, -0.01), (-0.48, -0.12), (-1.02, -0.30), (-1.02, 0.17), (-0.48, 0.20)]
    prism("stock", stock, 0.15, m["wood"])
    box("butt", (0.05, 0.16, 0.48), (-1.04, 0, -0.065), m["rubber"])
    return {"grip": (-0.32, 0, 0.02), "muzzle": (1.78, 0, 0.21)}


def w_shotgun_double(m):
    # double canon (superposé), bascule, crosse bois clair
    cyl_x("barrelA", 0.07, 0.07, 1.20, (0.85, 0, 0.26), m["steel"], seg=12)
    cyl_x("barrelB", 0.07, 0.07, 1.20, (0.85, 0, 0.12), m["steel"], seg=12)
    box("rib", (1.18, 0.04, 0.03), (0.85, 0, 0.345), m["dark"])
    box("lug", (1.10, 0.06, 0.06), (0.85, 0, 0.19), m["dark"], bevel=0.0)
    cyl_x("muzzleA", 0.078, 0.078, 0.04, (1.46, 0, 0.26), m["dark"], seg=12)
    cyl_x("muzzleB", 0.078, 0.078, 0.04, (1.46, 0, 0.12), m["dark"], seg=12)
    box("fore", (0.45, 0.15, 0.10), (0.55, 0, 0.03), m["wood"], bevel=0.03)
    box("action", (0.36, 0.16, 0.30), (0.06, 0, 0.17), m["steel"], bevel=0.03)
    for sx in (-0.06, 0.02):
        box("hammer", (0.06, 0.04, 0.12), (-0.16 + sx, 0, 0.36), m["dark"], rot=(0, -0.6, 0))
    guard("guard", -0.14, 0.06, 0.03, m["dark"])
    stock = [(-0.12, 0.31), (-0.12, 0.02), (-0.40, -0.10), (-0.95, -0.28), (-0.95, 0.18), (-0.40, 0.22)]
    prism("stock", stock, 0.15, m["wood"])
    box("butt", (0.05, 0.16, 0.48), (-0.97, 0, -0.05), m["dark"])
    return {"grip": (-0.26, 0, 0.04), "muzzle": (1.48, 0, 0.19)}


def _rifle_base(m, body="black", furn="black", long=1.0):
    box("upper", (0.80, 0.13, 0.15), (0.10, 0, 0.24), m[body], bevel=0.02)
    box("lower", (0.60, 0.12, 0.12), (0.02, 0, 0.10), m[body], bevel=0.02)
    x_hg = 0.50 + 0.30 * long
    box("handguard", (0.62 * long, 0.15, 0.17), (x_hg, 0, 0.22), m[furn], bevel=0.03)
    for k in range(int(5 * long)):
        box("slot", (0.06, 0.155, 0.04), (0.30 + k * 0.12, 0, 0.18), m["dark"], bevel=0.0)
    x_end = 0.50 + 0.62 * long + 0.15
    cyl_x("barrel", 0.035, 0.035, 0.30, (x_end, 0, 0.23), m["dark"], seg=10)
    cyl_x("brake", 0.055, 0.055, 0.12, (x_end + 0.18, 0, 0.23), m["dark"], seg=8)
    box("sightF", (0.04, 0.05, 0.12), (x_end - 0.12, 0, 0.34), m["dark"], bevel=0.0)
    mag("mag", 0.14, 0.05, m["dark"], h=0.42, w=0.14, t=0.10, curve=0.10)
    grip("grip", -0.14, 0.05, m[furn], h=0.32, w=0.13)
    guard("guard", -0.12, 0.10, 0.04, m[body])
    stock = [(-0.30, 0.30), (-0.30, 0.10), (-0.60, 0.06), (-0.92, -0.12), (-0.92, 0.30)]
    prism("stock", stock, 0.13, m[furn])
    box("butt", (0.04, 0.14, 0.44), (-0.94, 0, 0.09), m["rubber"])
    return x_end + 0.24


def w_rifle(m):
    end = _rifle_base(m)
    box("carry", (0.40, 0.08, 0.06), (0.05, 0, 0.36), m["dark"])
    box("carryF", (0.05, 0.08, 0.08), (0.24, 0, 0.32), m["dark"], bevel=0.0)
    box("carryB", (0.05, 0.08, 0.08), (-0.14, 0, 0.32), m["dark"], bevel=0.0)
    return {"grip": (-0.26, 0, -0.08), "muzzle": (end, 0, 0.23)}


def w_rifle_tactical(m):
    end = _rifle_base(m, body="tan", furn="tan", long=1.15)
    rail(m, -0.25, 1.08, 0.33)
    # viseur point rouge + poignée verticale + lampe
    box("dot", (0.22, 0.10, 0.14), (0.05, 0, 0.44), m["black"], bevel=0.02)
    cyl_x("dotLens", 0.05, 0.05, 0.02, (0.17, 0, 0.45), m["glass"])
    prism("vgrip", [(0.70, 0.12), (0.80, 0.12), (0.78, -0.18), (0.70, -0.18)], 0.09, m["black"])
    cyl_x("light", 0.04, 0.045, 0.16, (0.98, -0.06, 0.13), m["black"])
    cyl_x("supp", 0.065, 0.065, 0.34, (end + 0.10, 0, 0.23), m["black"], seg=12)
    return {"grip": (-0.26, 0, -0.08), "muzzle": (end + 0.28, 0, 0.23)}


def w_sniper(m):
    # verrou, canon très long, grosse lunette, crosse bois à joue
    cyl_x("barrel", 0.045, 0.035, 1.80, (1.20, 0, 0.20), m["dark"], seg=10)
    cyl_x("brake", 0.06, 0.06, 0.12, (2.14, 0, 0.20), m["dark"], seg=8)
    box("receiver", (0.70, 0.12, 0.16), (0.05, 0, 0.20), m["steel"], bevel=0.02)
    bolt = C.bm_tube([(-0.05, -0.06, 0.24), (-0.05, -0.16, 0.20), (-0.04, -0.20, 0.12)], [0.02, 0.02, 0.02], seg=6)
    C.mesh_obj("bolt", bolt, m["steel"])
    C.mesh_obj("knob", C.bm_xform(C.bm_sphere(8, 6, 0.045), loc=(-0.04, -0.20, 0.12)), m["dark"])
    scope(m, -0.25, 0.55, 0.40, r=0.08)
    stock = [(0.85, 0.20), (0.85, 0.08), (0.30, 0.04), (-0.15, -0.02), (-0.30, -0.30), (-0.42, -0.30),
             (-0.46, -0.05), (-1.10, -0.18), (-1.10, 0.24), (-0.55, 0.28), (-0.30, 0.16)]
    prism("stock", stock, 0.13, m["wood"])
    box("butt", (0.05, 0.14, 0.44), (-1.12, 0, 0.03), m["rubber"])
    mag("mag", 0.10, 0.06, m["dark"], h=0.16, w=0.16)
    guard("guard", -0.20, 0.02, 0.02, m["dark"])
    return {"grip": (-0.38, 0, -0.12), "muzzle": (2.20, 0, 0.20)}


def w_sniper_heavy(m):
    # anti-matériel : canon épais à gros frein, bipied, chargeur massif, polymère sombre
    cyl_x("barrel", 0.07, 0.06, 1.90, (1.30, 0, 0.22), m["dark"], seg=10)
    box("brake", (0.24, 0.16, 0.16), (2.32, 0, 0.22), m["dark"], bevel=0.02)
    for k in range(3):
        box("port", (0.04, 0.17, 0.10), (2.24 + k * 0.07, 0, 0.22), m["black"], bevel=0.0)
    box("receiver", (1.00, 0.17, 0.24), (0.15, 0, 0.20), m["olive"], bevel=0.03)
    rail(m, -0.25, 0.70, 0.335, 0.09)
    scope(m, -0.30, 0.60, 0.47, r=0.09)
    mag("mag", 0.18, 0.08, m["dark"], h=0.32, w=0.22, t=0.13)
    grip("grip", -0.20, 0.08, m["black"], h=0.34, w=0.15)
    guard("guard", -0.18, 0.04, 0.08, m["black"])
    prism("stock", [(-0.35, 0.32), (-0.35, 0.08), (-1.15, -0.10), (-1.15, 0.32)], 0.13, m["olive"])
    box("butt", (0.06, 0.15, 0.46), (-1.17, 0, 0.11), m["rubber"])
    for sy in (-0.04, 0.04):
        C.mesh_obj("bipod", C.bm_tube([(1.40, sy, 0.15), (1.55, sy * 3, -0.30)], [0.022, 0.018], seg=6), m["dark"])
    return {"grip": (-0.32, 0, -0.08), "muzzle": (2.44, 0, 0.22)}


def w_lmg(m):
    # mitrailleuse : gros boîtier, canon à manchon ventilé, bande de cartouches, bipied, poignée de transport
    box("receiver", (0.90, 0.17, 0.26), (0.10, 0, 0.20), m["dark"], bevel=0.03)
    box("cover", (0.70, 0.18, 0.08), (0.12, 0, 0.37), m["black"], bevel=0.02)
    cyl_x("jacket", 0.085, 0.085, 0.90, (1.00, 0, 0.22), m["black"], seg=12)
    for k in range(7):
        cyl_y("vent", 0.03, 0.18, (0.65 + k * 0.11, 0, 0.22), m["dark"], seg=8)
    cyl_x("barrel", 0.04, 0.04, 0.30, (1.55, 0, 0.22), m["dark"])
    cyl_x("flash", 0.06, 0.05, 0.12, (1.72, 0, 0.22), m["dark"], seg=8)
    # boîte à munitions + bande de cartouches
    box("ammo", (0.30, 0.20, 0.30), (0.20, -0.02, -0.12), m["olive"], bevel=0.03)
    for k in range(7):
        a = k / 6
        x = 0.30 - 0.05 * a
        z = 0.06 + 0.16 * a
        C.mesh_obj("round", C.bm_xform(C.bm_cyl(8, 0.025, 0.012, 0.11), loc=(x + 0.02 * k * 0, -0.11, z),
                   rot=(math.pi / 2, 0, 0)), m["brass"])
    pts = C.bezier((0.33, -0.10, 0.03), (0.40, -0.10, 0.10), (0.36, -0.10, 0.20), (0.28, -0.10, 0.26), 6)
    C.mesh_obj("belt", C.bm_tube(pts, [0.03] * 6, seg=6, flat=0.4, up=(0, 1, 0)), m["brass"])
    grip("grip", -0.12, 0.08, m["black"], h=0.34, w=0.15)
    guard("guard", -0.10, 0.10, 0.07, m["dark"])
    prism("stock", [(-0.34, 0.32), (-0.34, 0.10), (-0.95, -0.06), (-0.95, 0.30)], 0.14, m["black"])
    box("butt", (0.05, 0.15, 0.40), (-0.97, 0, 0.12), m["rubber"])
    C.mesh_obj("handle", C.bm_tube(C.bezier((0.80, 0, 0.30), (0.82, 0, 0.48), (0.98, 0, 0.48), (1.00, 0, 0.30), 7),
                                   [0.025] * 7, seg=6), m["dark"])
    for sy in (-0.04, 0.04):
        C.mesh_obj("bipod", C.bm_tube([(1.35, sy, 0.14), (1.50, sy * 3, -0.26)], [0.02, 0.016], seg=6), m["dark"])
    return {"grip": (-0.24, 0, -0.08), "muzzle": (1.78, 0, 0.22)}


def w_rocket_launcher(m):
    # bazooka : long tube épais, ouverture avant évasée avec roquette visible, poignées, viseur
    cyl_x("tube", 0.15, 0.15, 2.0, (0.45, 0, 0.20), m["olive"], seg=16)
    cyl_x("bell", 0.15, 0.20, 0.25, (1.50, 0, 0.20), m["olive"], seg=16)
    cyl_x("rim", 0.205, 0.205, 0.04, (1.63, 0, 0.20), m["dark"], seg=16)
    cyl_x("rocket", 0.10, 0.02, 0.18, (1.66, 0, 0.20), m["steel"], seg=12)
    cyl_x("back", 0.17, 0.19, 0.20, (-0.62, 0, 0.20), m["dark"], seg=16)
    for x in (0.10, 0.85):
        cyl_x("band", 0.158, 0.158, 0.06, (x, 0, 0.20), m["dark"], seg=16)
    box("sightBox", (0.20, 0.08, 0.14), (0.40, -0.04, 0.42), m["dark"])
    cyl_x("sightLens", 0.035, 0.035, 0.02, (0.51, -0.04, 0.43), m["glass"])
    grip("grip", 0.02, 0.05, m["black"], h=0.32, w=0.15, slant=0.15)
    grip("grip2", 0.62, 0.05, m["black"], h=0.26, w=0.13, slant=0.10)
    guard("guard", 0.02, 0.20, 0.04, m["dark"])
    box("shoulder", (0.34, 0.10, 0.10), (-0.25, 0, 0.0), m["rubber"])
    return {"grip": (-0.06, 0, -0.10), "muzzle": (1.66, 0, 0.20)}


def w_grenade_launcher(m):
    # lance-grenades à barillet : gros tambour, canon court et large, crosse repliable
    cyl_x("drum", 0.24, 0.24, 0.40, (0.20, 0, 0.18), m["dark"], seg=12)
    for k in range(6):
        a = k * math.pi / 3
        C.mesh_obj("chamber", C.bm_xform(C.bm_cyl(10, 0.065, 0.065, 0.42),
                   loc=(0.20, 0.16 * math.cos(a), 0.18 + 0.16 * math.sin(a)), rot=(0, math.pi / 2, 0)), m["black"])
    cyl_x("barrel", 0.10, 0.10, 0.60, (0.70, 0, 0.30), m["black"], seg=14)
    cyl_x("bore", 0.07, 0.07, 0.02, (1.005, 0, 0.30), m["rubber"], seg=14)
    box("frameTop", (0.95, 0.10, 0.06), (0.45, 0, 0.44), m["dark"])
    box("frameBot", (0.55, 0.10, 0.06), (0.25, 0, -0.08), m["dark"])
    prism("vgrip", [(0.66, 0.20), (0.78, 0.20), (0.76, -0.10), (0.66, -0.10)], 0.09, m["black"])
    box("sight", (0.16, 0.06, 0.10), (0.35, 0, 0.52), m["dark"])
    grip("grip", -0.06, 0.06, m["black"], h=0.34, w=0.15)
    guard("guard", -0.04, 0.10, 0.04, m["dark"])
    pts = [(-0.20, 0, 0.28), (-0.85, 0, 0.24), (-0.85, 0, 0.00), (-0.20, 0, 0.06)]
    C.mesh_obj("stock", C.bm_tube(pts, [0.03] * 4, seg=6), m["dark"])
    box("butt", (0.06, 0.13, 0.30), (-0.86, 0, 0.12), m["rubber"])
    return {"grip": (-0.17, 0, -0.10), "muzzle": (1.02, 0, 0.30)}


def w_bow(m):
    """Ancien arc (gardé : data/weapons/starter_bow.tres)."""
    pts_up = C.bezier((0.0, 0, 0.0), (0.18, 0, 0.30), (0.05, 0, 0.75), (0.16, 0, 0.98), 10)
    pts_dn = [(x, y, -z) for (x, y, z) in pts_up]
    rr = [0.10 - 0.06 * (i / 9) for i in range(10)]
    C.mesh_obj("limbU", C.bm_tube(pts_up, rr, seg=8, flat=0.7), m["wood"])
    C.mesh_obj("limbD", C.bm_tube(pts_dn, rr, seg=8, flat=0.7), m["wood"])
    C.mesh_obj("grip", C.bm_xform(C.bm_cyl(10, 0.11, 0.11, 0.30), loc=(0.0, 0, 0)), m["rubber"])
    s = C.bm_tube([(0.16, 0, 0.98), (-0.18, 0, 0.0), (0.16, 0, -0.98)], [0.008, 0.008, 0.008], seg=5)
    C.mesh_obj("string", s, m["ivory"])
    cyl_x("shaft", 0.022, 0.022, 0.95, (0.30, 0, 0.0), m["wood"], seg=6)
    return {"grip": (0.0, 0, 0.0), "muzzle": (0.92, 0, 0.0)}


WEAPONS = {
    "starter_pistol": w_starter_pistol, "pistol": w_pistol, "pistol_heavy": w_pistol_heavy,
    "revolver": w_revolver, "revolver_gold": w_revolver_gold,
    "smg": w_smg, "smg_compact": w_smg_compact,
    "shotgun": w_shotgun, "shotgun_double": w_shotgun_double,
    "rifle": w_rifle, "rifle_tactical": w_rifle_tactical,
    "sniper": w_sniper, "sniper_heavy": w_sniper_heavy,
    "lmg": w_lmg, "rocket_launcher": w_rocket_launcher, "grenade_launcher": w_grenade_launcher,
}
# Gardés hors de la liste figée (référencés par d'anciennes données) : pas d'icône.
LEGACY = {"bow": w_bow}


def _bounds():
    """Boîte englobante (x0, x1, z0, z1) dans le plan de la caméra : projections des sommets."""
    import numpy as np
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    pts = []
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        ev = ob.evaluated_get(deps)
        me = ev.to_mesh()
        mw = ob.matrix_world
        for v in me.vertices:
            pts.append(tuple(mw @ v.co))
        ev.to_mesh_clear()
    return np.array(pts)


def _cam_frame(cam, pts):
    """Coordonnées (droite, haut) des points dans le repère de la caméra orthographique."""
    import numpy as np
    m = cam.matrix_world.inverted()
    R = np.array(m)[:3, :3]
    T = np.array(m)[:3, 3]
    loc = pts @ R.T + T
    return loc[:, 0], loc[:, 1]


def _render(wid: str, fn, elev: float, size: tuple[int, int] | None, outline: float, pad_px: int):
    """Rend l'arme ; size None = taille déduite de PX_PER_UNIT. Renvoie (chemin, cam, info, (W, H))."""
    C.reset_scene()
    info = fn(mats())
    pts = _bounds()
    cam = C.ortho_camera(elev, 10.0, target=(0, 0, 0))
    bpy.context.view_layer.update()
    u, v = _cam_frame(cam, pts)
    cu, cv = (u.min() + u.max()) / 2, (v.min() + v.max()) / 2
    w_u, h_u = u.max() - u.min(), v.max() - v.min()
    if size is None:
        W = int(math.ceil((w_u * PX_PER_UNIT + 2 * pad_px) / 4.0) * 4)
        H = int(math.ceil((h_u * PX_PER_UNIT + 2 * pad_px) / 4.0) * 4)
        ortho = W / PX_PER_UNIT
    else:
        W, H = size
        ortho = max(w_u / (W - 2 * pad_px) * W, h_u / (H - 2 * pad_px) * W)
    # recentre la caméra sur la boîte englobante
    cam.location = cam.location + cam.matrix_world.to_3x3() @ __import__("mathutils").Vector((cu, cv, 0))
    cam.data.ortho_scale = ortho
    cam.data.sensor_fit = "HORIZONTAL"
    C.setup_render((W * SS, H * SS), samples=6, outline_px=outline * SS, inner_ratio=0.45)
    bpy.context.scene.camera = cam
    os.makedirs(TMP, exist_ok=True)
    big = os.path.join(TMP, wid + "_big.png")
    C.render_to(big)
    return big, cam, info, (W, H)


def render_weapon(wid: str, fn, icon: bool = True) -> None:
    big, cam, info, (W, H) = _render(wid, fn, HELD_ELEV, None, 1.3, 3)
    os.makedirs(OUT, exist_ok=True)
    C.downscale(big, os.path.join(OUT, wid + ".png"), (W, H))
    g = C.world_to_px(cam, info["grip"])
    mz = C.world_to_px(cam, info["muzzle"])
    meta = {
        "grip": [round(g[0] / SS), round(g[1] / SS)],
        "muzzle": [round(mz[0] / SS), round(mz[1] / SS)],
        "scale": HELD_SCALE,
        "size": [W, H],
    }
    with open(os.path.join(OUT, wid + ".json"), "w") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    print("WEAPON", wid, meta, flush=True)
    if icon:
        big, _cam, _info, (W, H) = _render(wid, fn, ICON_ELEV, ICON_SIZE, 2.4, 8)
        os.makedirs(OUT_ICON, exist_ok=True)
        C.downscale(big, os.path.join(OUT_ICON, wid + ".png"), (W, H))


def contact_sheet(out: str) -> None:
    from PIL import Image, ImageDraw
    ids = list(WEAPONS)
    cols = 4
    cw, ch = 300, 190
    sheet = Image.new("RGBA", (cw * cols, ch * math.ceil(len(ids) / cols)), (18, 26, 46, 255))
    dr = ImageDraw.Draw(sheet)
    for k, wid in enumerate(ids):
        x, y = (k % cols) * cw, (k // cols) * ch
        ic = Image.open(os.path.join(OUT_ICON, wid + ".png"))
        sheet.alpha_composite(ic, (x + 10, y + 6))
        small = ic.resize((128, 64), Image.LANCZOS)
        sheet.alpha_composite(small, (x + 210 - 40, y + 110))
        held = Image.open(os.path.join(OUT, wid + ".png"))
        sheet.alpha_composite(held, (x + 10, y + 110))
        dr.text((x + 10, y + 172), wid, fill=(230, 230, 240, 255))
    sheet.save(out)
    print("SHEET", out)


def main() -> None:
    args = sys.argv[1:]
    if "--sheet" in args:
        contact_sheet(args[args.index("--sheet") + 1])
        return
    ids = args or list(WEAPONS) + list(LEGACY)
    for wid in ids:
        if wid in WEAPONS:
            render_weapon(wid, WEAPONS[wid])
        elif wid in LEGACY:
            render_weapon(wid, LEGACY[wid], icon=False)


if __name__ == "__main__":
    main()
