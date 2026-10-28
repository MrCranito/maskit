"""Arsenal d'Exfil Rush (planche docs/reference/arsenal.jpg) : 18 armes + 5 équipements.

Usage (depuis la racine du projet) :
    python3 art/blender/build_weapons.py                   # tout (sprites tenus, icônes, sprites au sol)
    python3 art/blender/build_weapons.py smg_mp5 rifle_aug # quelques-uns
    python3 art/blender/build_weapons.py --sheet out.png   # planche-contact des icônes (après rendu)

Sorties :
- assets/sprites/weapons/<id>.png + <id>.json (grip, muzzle en px dans l'image, scale, size) :
  arme tenue, 3/4 plongeant, canon vers la DROITE ;
- assets/ui/weapons/<id>.png : icône d'inventaire de profil (256x128, fond transparent) ;
- gadgets : assets/sprites/weapons/<id>_world.png (objet vu du dessus, 64x64 ; drone : + <id>_world_b.png,
  hélices décalées pour l'animation).
Repère de modélisation : X = vers l'avant (canon), Z = haut, Y = profondeur (côté visible = -Y).
La rareté se voit sur l'arme, comme sur la planche : Commun noir mat, Rare acier usé, Épique finitions
travaillées (gravures, bois, beige), Légendaire noir et éclats d'or.
"""
from __future__ import annotations

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "weapons")
OUT_ICON = os.path.join(ROOT, "assets", "ui", "weapons")
TMP = os.environ.get("RDM_TMP", "/tmp/rdm_weapons")
SS = 4
PX_PER_UNIT = 44.0          # sprite tenu : px par unité Blender
HELD_SCALE = 0.45           # échelle d'affichage en jeu (unités monde par px)
HELD_ELEV = 34.0            # plongée de la vue tenue
ICON_SIZE = (256, 128)
ICON_ELEV = 10.0
ICON_AZIM = -8.0            # léger 3/4 pour le volume (comme la planche)
WORLD_SIZE = 64


def mats():
    P = C.toon_pattern
    return {
        # communs : noir mat / polymère
        "black": C.toon("polymer", "#2e3036", "#0c0c16", "#565862", rim=0.32),
        "dark": C.toon("darksteel", "#45474f", "#121422", "#7c808c", rim=0.32),
        "steel": C.toon("steel", "#a2a6b0", "#343852", "#eef0f6", rim=0.40),
        "worn": P("worn", [("#3c3e46", "#101220", "#6a6c78"), ("#7a7c86", "#262838", "#b8bac4")], 34.0,
                  thresholds=(0.66,), rim=0.35),
        "rubber": C.toon("rubber", "#26262c", "#0a0a14", "#424248", rim=0.2),
        # bois
        "wood": P("wood", [("#8e5428", "#3a1a1c", "#c47e3e"), ("#6e3e1e", "#2c1218", "#9a5e2e")], 3.0,
                  thresholds=(0.55,), rim=0.25),
        "wood_dark": P("wooddark", [("#5a3a24", "#22121a", "#82583a"), ("#46301e", "#1a0e16", "#684630")], 3.0,
                       thresholds=(0.55,), rim=0.25),
        "wood_grip": C.toon("woodgrip", "#4a2e20", "#1a0c14", "#704632", rim=0.25),
        # rares : acier patiné, bronze
        "gunmetal": P("gunmetal", [("#5c606a", "#1a1c2c", "#9ca0ac"), ("#8a8c94", "#2e3040", "#d0d2da")], 30.0,
                      thresholds=(0.67,), rim=0.40),
        "bronze": C.toon("bronze", "#7e6040", "#2e2020", "#b08a5a", rim=0.40),
        # épiques
        "silver": C.toon("silver", "#c4c6cc", "#4e5068", "#ffffff", rim=0.45),
        "engraved": P("engraved", [("#b8b4a8", "#4a4a5e", "#f6f2e6"), ("#c89a48", "#5a3a28", "#f4d488")], 16.0,
                      thresholds=(0.58,), rim=0.45),
        "tan": P("tan", [("#a89474", "#463a36", "#d4c09a"), ("#8e7a5c", "#36302e", "#b8a27c")], 28.0,
                 thresholds=(0.64,), rim=0.30),
        "navy": P("navy", [("#262c40", "#0a0c1a", "#46506e"), ("#b88a3e", "#4a3024", "#e8c070")], 26.0,
                  thresholds=(0.70,), rim=0.32),
        "olive": C.toon("olive", "#5e6444", "#20241e", "#868c62", rim=0.30),
        "olive_dark": P("olivedark", [("#3e4430", "#121612", "#5e664a"), ("#363a2a", "#0e100e", "#525840")], 20.0,
                        thresholds=(0.60,), rim=0.30),
        "brass": C.toon("brass", "#8a7448", "#2e2422", "#bea270", rim=0.40),
        # légendaires : noir et or
        "legend": P("legend", [("#1e1e24", "#08080e", "#3c3c46"), ("#d0a040", "#5e3e2a", "#ffe08a")], 14.0,
                    thresholds=(0.66,), rim=0.38),
        "gold": C.toon("gold", "#d6a844", "#6a4430", "#ffe49a", rim=0.45),
        # divers
        "red": C.toon("red", "#b0282a", "#40101c", "#e2523e", rim=0.35),
        "orange": C.toon("orange", "#c86a2a", "#4e2218", "#f09a50", rim=0.35),
        "glass": C.toon("glass", "#5a7ea0", "#18243e", "#c4dcf0", rim=0.55),
        "led": C.toon("led", "#ff3a2a", emit=1.4),
        "led_b": C.toon("ledb", "#48c8ff", emit=1.4),
        "khaki": C.toon("khaki", "#8a8058", "#34302a", "#b4a87a", rim=0.30),
        "cream": C.toon("cream", "#d8d2bc", "#7e7a8a", "#fffaea", rim=0.30),
        "putty": C.toon("putty", "#c8b48a", "#5a4c44", "#ecdcb0", rim=0.25),
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


def cyl_z(name, r1, r2, h, loc, mat, seg=16, smooth=True):
    return C.mesh_obj(name, C.bm_xform(C.bm_cyl(seg, r1, r2, h), loc=loc), mat, smooth=smooth)


def prism(name, prof, depth, mat, y=0.0, smooth=False):
    """Extrusion d'un profil 2D (x, z) sur l'épaisseur `depth` (Y)."""
    secs = [[(x, y - depth / 2, z) for (x, z) in prof], [(x, y + depth / 2, z) for (x, z) in prof]]
    return C.mesh_obj(name, C.bm_loft(secs), mat, smooth=smooth)


def grip(name, x, z, mat, h=0.36, w=0.15, t=0.13, slant=0.28):
    """Poignée pistolet inclinée vers l'arrière ; (x, z) = haut avant."""
    prof = [(x, z), (x - w, z), (x - w - h * slant, z - h), (x - h * slant + 0.01, z - h)]
    return prism(name, prof, t, mat)


def guard(name, x0, x1, z, mat):
    pts = C.bezier((x1, 0, z), (x1, 0, z - 0.14), (x0 + 0.02, 0, z - 0.14), (x0, 0, z - 0.02), 8)
    return C.mesh_obj(name, C.bm_tube(pts, [0.018] * 8, seg=6), mat)


def mag(name, x, z, mat, h=0.36, w=0.13, t=0.10, curve=0.0):
    prof = [(x, z), (x + w, z), (x + w + curve, z - h), (x + curve, z - h)]
    return prism(name, prof, t, mat)


def scope(m, x0, x1, z, r=0.075, body="black", ring="dark"):
    L = x1 - x0
    cyl_x("scope", r * 0.72, r * 0.72, L * 0.6, ((x0 + x1) / 2, 0, z), m[body])
    cyl_x("scopeF", r * 0.72, r * 1.25, L * 0.22, (x1 - L * 0.11, 0, z), m[body])
    cyl_x("scopeB", r * 1.1, r * 0.72, L * 0.20, (x0 + L * 0.10, 0, z), m[body])
    cyl_x("lens", r * 1.05, r * 1.05, 0.012, (x1 + 0.004, 0, z), m["glass"])
    cyl_y("turret", r * 0.45, 0.07, ((x0 + x1) / 2, -r * 0.8, z), m[ring])
    box("turretT", (0.07, 0.07, 0.06), ((x0 + x1) / 2, 0, z + r * 0.95), m[ring])
    for xx in (x0 + L * 0.3, x1 - L * 0.35):
        box("ring", (0.06, 0.09, 0.08), (xx, 0, z - r - 0.02), m[ring])


def rail(m, x0, x1, z, depth=0.08, mat="dark"):
    box("rail", (x1 - x0, depth, 0.03), ((x0 + x1) / 2, 0, z), m[mat])
    n = int((x1 - x0) / 0.06)
    for k in range(n):
        box("railT", (0.03, depth + 0.004, 0.022), (x0 + 0.03 + k * 0.06, 0, z + 0.024), m[mat], bevel=0.0)


def slots(m, x0, n, step, z, h, depth, mat="black"):
    for k in range(n):
        box("slot", (step * 0.5, depth, h), (x0 + k * step, 0, z), m[mat], bevel=0.0)


# --------------------------------------------------------------------------- pistolets

def _pistol(m, slide, frame, gripm, accent=None, long=1.0, heavy=False):
    L = 0.86 * long
    hz = 0.17 if not heavy else 0.19
    th = 0.14 if not heavy else 0.17
    box("slide", (L, 0.12, th), (0.28 * long, 0, hz), m[slide], bevel=0.018)
    for k in range(6):
        box("serr", (0.014, 0.125, th * 0.75), (-0.10 + k * 0.032, 0, hz), m["black"], bevel=0.0)
    box("port", (0.16, 0.01, 0.05), (0.34 * long, -0.062, hz + 0.02), m["black"], bevel=0.0)
    box("frame", (L * 0.86, 0.11, 0.09), (0.24 * long, 0, hz - 0.11), m[frame])
    rail(m, 0.40 * long, 0.62 * long, hz - 0.165, 0.09, mat=frame)
    cyl_x("barrel", 0.036, 0.036, 0.05, (0.28 * long + L / 2 + 0.02, 0, hz + 0.01), m["black"])
    box("sightF", (0.03, 0.03, 0.04), (0.28 * long + L / 2 - 0.05, 0, hz + th / 2 + 0.02), m["dark"], bevel=0.0)
    box("sightB", (0.05, 0.06, 0.04), (-0.10, 0, hz + th / 2 + 0.02), m["dark"], bevel=0.0)
    box("hammer", (0.05, 0.05, 0.07), (-0.16, 0, hz + 0.03), m["dark"], rot=(0, -0.5, 0))
    grip("grip", 0.08, hz - 0.11, m[gripm], h=0.42, w=0.19, t=0.13)
    box("magbase", (0.19, 0.12, 0.03), (-0.12, 0, hz - 0.11 - 0.42), m[frame])
    guard("guard", 0.10, 0.36, hz - 0.13, m[frame])
    box("trigger", (0.03, 0.03, 0.10), (0.16, 0, hz - 0.20), m["dark"], rot=(0, 0.3, 0))
    if accent:
        box("accent", (L * 0.92, 0.126, 0.025), (0.28 * long, 0, hz - 0.035), m[accent], bevel=0.0)
    return {"grip": (-0.06, 0, hz - 0.30), "muzzle": (0.28 * long + L / 2 + 0.05, 0, hz + 0.01)}


def pistol_p9(m):
    return _pistol(m, "black", "black", "black")


def pistol_glock18(m):
    info = _pistol(m, "gunmetal", "dark", "worn")
    box("selector", (0.05, 0.13, 0.03), (-0.05, 0, 0.21), m["bronze"])
    return info


def pistol_deagle(m):
    info = _pistol(m, "engraved", "silver", "wood_grip", accent="gold", long=1.12, heavy=True)
    for k in range(4):
        box("rib", (0.20, 0.06, 0.02), (0.30 + k * 0.0, 0, 0.29), m["silver"])
    C.mesh_obj("medal", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(-0.18, -0.068, -0.10), scale=(0.04, 0.012, 0.05)),
               m["gold"])
    return info


def pistol_p320(m):
    return _pistol(m, "legend", "legend", "legend", accent="gold", long=1.05)


# --------------------------------------------------------------------------- mitraillettes

def smg_mp5(m):
    box("receiver", (0.90, 0.13, 0.17), (0.18, 0, 0.18), m["black"], bevel=0.03)
    cyl_x("tube", 0.075, 0.075, 0.95, (0.22, 0, 0.20), m["black"], seg=14)
    box("handguard", (0.40, 0.16, 0.16), (0.78, 0, 0.16), m["black"], bevel=0.04)
    slots(m, 0.64, 4, 0.08, 0.16, 0.05, 0.165, "dark")
    cyl_x("barrel", 0.034, 0.034, 0.22, (1.08, 0, 0.20), m["dark"])
    cyl_x("tip", 0.05, 0.05, 0.06, (1.20, 0, 0.20), m["dark"])
    box("cocking", (0.05, 0.03, 0.12), (0.70, -0.09, 0.30), m["dark"], rot=(0, 0.6, 0))
    box("hood", (0.06, 0.08, 0.10), (1.00, 0, 0.32), m["dark"], bevel=0.0)
    rail(m, -0.10, 0.40, 0.30, 0.08)
    # petite lunette de visée (planche)
    cyl_x("optic", 0.05, 0.05, 0.28, (0.15, 0, 0.42), m["dark"])
    cyl_x("optLens", 0.055, 0.055, 0.01, (0.29, 0, 0.42), m["bronze"])
    box("optMount", (0.10, 0.06, 0.07), (0.15, 0, 0.35), m["dark"])
    mag("mag", 0.38, 0.09, m["black"], h=0.50, w=0.11, curve=0.10)
    grip("grip", -0.02, 0.09, m["black"], h=0.36, w=0.15)
    guard("guard", 0.00, 0.22, 0.07, m["black"])
    # crosse rétractable
    pts = [(-0.28, 0, 0.25), (-0.78, 0, 0.25), (-0.80, 0, 0.0), (-0.70, 0, 0.0)]
    C.mesh_obj("stock", C.bm_tube(pts, [0.028] * 4, seg=6), m["dark"])
    box("butt", (0.06, 0.13, 0.32), (-0.80, 0, 0.12), m["rubber"])
    return {"grip": (-0.13, 0, -0.10), "muzzle": (1.24, 0, 0.20)}


def smg_vector(m):
    # Kriss Vector : corps anguleux vertical, chargeur long sous la poignée avant, canon court
    prof = [(-0.20, 0.36), (0.72, 0.36), (0.80, 0.24), (0.66, 0.04), (0.40, -0.18), (0.18, -0.18),
            (0.10, 0.04), (-0.20, 0.10)]
    prism("body", prof, 0.15, m["worn"])
    rail(m, -0.18, 0.70, 0.38, 0.08)
    box("sightB", (0.06, 0.07, 0.08), (-0.10, 0, 0.45), m["dark"], bevel=0.0)
    box("sightF", (0.05, 0.07, 0.08), (0.64, 0, 0.45), m["dark"], bevel=0.0)
    cyl_x("barrel", 0.04, 0.04, 0.26, (0.92, 0, 0.26), m["dark"])
    cyl_x("supp", 0.06, 0.06, 0.12, (1.08, 0, 0.26), m["black"])
    rail(m, 0.66, 0.84, 0.17, 0.07)
    mag("mag", 0.20, -0.18, m["black"], h=0.52, w=0.11, t=0.10)
    grip("grip", -0.04, 0.10, m["black"], h=0.36, w=0.14, slant=0.20)
    guard("guard", -0.02, 0.18, 0.08, m["black"])
    prism("stock", [(-0.20, 0.34), (-0.20, 0.14), (-0.62, 0.12), (-0.66, -0.06), (-0.76, -0.06),
                    (-0.76, 0.34)], 0.12, m["black"])
    for k in range(3):
        box("bronze", (0.04, 0.155, 0.04), (0.30 + k * 0.12, 0, 0.30), m["bronze"], bevel=0.0)
    return {"grip": (-0.12, 0, -0.10), "muzzle": (1.15, 0, 0.26)}


def smg_p90(m):
    # P90 : bloc bullpup arrondi, trou de pouce, chargeur horizontal translucide sur le dessus
    prof = [(-0.70, 0.30), (-0.70, -0.14), (-0.55, -0.24), (-0.30, -0.24), (-0.22, -0.10), (0.02, -0.10),
            (0.10, -0.26), (0.30, -0.26), (0.40, -0.10), (0.62, -0.06), (0.74, 0.08), (0.74, 0.28),
            (0.60, 0.34), (-0.60, 0.36)]
    prism("body", prof, 0.20, m["navy"])
    cyl_y("thumb", 0.08, 0.22, (-0.40, 0, -0.06), m["black"])
    cyl_y("thumb2", 0.07, 0.22, (0.22, 0, -0.10), m["black"])
    box("magTop", (1.02, 0.16, 0.08), (0.04, 0, 0.40), m["dark"], bevel=0.02)
    box("magWin", (0.70, 0.01, 0.04), (0.02, -0.082, 0.40), m["bronze"], bevel=0.0)
    box("optic", (0.30, 0.10, 0.10), (0.08, 0, 0.50), m["black"], bevel=0.02)
    cyl_x("barrel", 0.035, 0.035, 0.22, (0.84, 0, 0.16), m["dark"])
    cyl_x("tip", 0.05, 0.05, 0.08, (0.96, 0, 0.16), m["dark"])
    return {"grip": (0.10, 0, -0.14), "muzzle": (1.00, 0, 0.16)}


def smg_uzi(m):
    # Uzi : boîte compacte, chargeur dans la poignée, canon court, crosse repliée
    box("receiver", (0.80, 0.14, 0.24), (0.15, 0, 0.18), m["legend"], bevel=0.03)
    box("top", (0.74, 0.10, 0.04), (0.15, 0, 0.32), m["black"])
    slots(m, 0.00, 3, 0.12, 0.30, 0.03, 0.145, "gold")
    cyl_x("barrel", 0.04, 0.04, 0.20, (0.64, 0, 0.20), m["dark"])
    cyl_x("nut", 0.06, 0.06, 0.05, (0.58, 0, 0.20), m["gold"])
    box("sightF", (0.05, 0.06, 0.08), (0.48, 0, 0.37), m["black"], bevel=0.0)
    box("sightB", (0.05, 0.06, 0.06), (-0.18, 0, 0.36), m["black"], bevel=0.0)
    grip("grip", 0.10, 0.06, m["legend"], h=0.50, w=0.15, slant=0.10)
    box("magbase", (0.15, 0.12, 0.05), (0.00, 0, -0.47), m["gold"])
    guard("guard", 0.12, 0.32, 0.05, m["black"])
    pts = [(-0.24, 0, 0.26), (-0.60, 0, 0.26), (-0.62, 0, 0.02), (-0.24, 0, 0.06)]
    C.mesh_obj("stock", C.bm_tube(pts, [0.026] * 4, seg=6), m["black"])
    return {"grip": (0.02, 0, -0.14), "muzzle": (0.74, 0, 0.20)}


# --------------------------------------------------------------------------- fusils d'assaut

def rifle_ak47(m):
    # AK : bois orangé (garde-main, poignée, crosse), boîtier noir, chargeur courbe, bloc gaz
    box("receiver", (0.80, 0.13, 0.20), (0.10, 0, 0.18), m["black"], bevel=0.02)
    box("cover", (0.70, 0.12, 0.06), (0.08, 0, 0.30), m["dark"], bevel=0.02)
    box("hgLow", (0.48, 0.15, 0.13), (0.75, 0, 0.15), m["wood"], bevel=0.035)
    cyl_x("gasTube", 0.04, 0.04, 0.44, (0.74, 0, 0.30), m["wood"])
    box("gasBlock", (0.06, 0.08, 0.14), (1.00, 0, 0.27), m["dark"])
    cyl_x("barrel", 0.033, 0.033, 0.56, (1.24, 0, 0.21), m["dark"])
    cyl_x("brake", 0.045, 0.05, 0.12, (1.56, 0, 0.21), m["dark"], seg=8)
    box("sightF", (0.04, 0.05, 0.13), (1.42, 0, 0.30), m["dark"], bevel=0.0)
    box("sightR", (0.12, 0.07, 0.06), (0.44, 0, 0.36), m["dark"])
    # chargeur courbe
    pts = C.bezier((0.30, 0, 0.08), (0.30, 0, -0.18), (0.38, 0, -0.34), (0.52, 0, -0.46), 6)
    secs = []
    for (x, _y, z) in pts:
        secs.append([(x, -0.05, z), (x + 0.15, -0.05, z), (x + 0.15, 0.05, z), (x, 0.05, z)])
    C.mesh_obj("mag", C.bm_loft(secs), m["wood"], smooth=False)
    grip("grip", 0.00, 0.08, m["wood"], h=0.34, w=0.13)
    guard("guard", 0.02, 0.24, 0.06, m["dark"])
    prism("stock", [(-0.30, 0.28), (-0.30, 0.08), (-0.55, 0.0), (-0.95, -0.18), (-0.95, 0.24), (-0.55, 0.26)],
          0.13, m["wood"])
    box("butt", (0.04, 0.14, 0.43), (-0.97, 0, 0.03), m["dark"])
    return {"grip": (-0.10, 0, -0.10), "muzzle": (1.62, 0, 0.21)}


def _ar15(m, body, furn, long=1.0, carry=True, rails=False):
    box("upper", (0.78, 0.13, 0.16), (0.10, 0, 0.25), m[body], bevel=0.02)
    box("lower", (0.58, 0.12, 0.13), (0.02, 0, 0.10), m[body], bevel=0.02)
    L = 0.62 * long
    box("handguard", (L, 0.16, 0.18), (0.50 + L / 2, 0, 0.22), m[furn], bevel=0.035)
    if rails:
        for z in (0.33, 0.11):
            rail(m, 0.52, 0.48 + L, z, 0.09, mat=furn)
    else:
        slots(m, 0.56, int(5 * long), 0.11, 0.18, 0.04, 0.165, "black")
    x_end = 0.50 + L + 0.12
    cyl_x("barrel", 0.033, 0.033, 0.34, (x_end + 0.05, 0, 0.23), m["dark"], seg=10)
    cyl_x("flash", 0.045, 0.045, 0.12, (x_end + 0.26, 0, 0.23), m["dark"], seg=8)
    box("sightF", (0.05, 0.06, 0.16), (x_end - 0.04, 0, 0.36), m["dark"], bevel=0.0)
    if carry:
        box("carry", (0.38, 0.08, 0.06), (0.06, 0, 0.40), m[body])
        box("carryF", (0.06, 0.08, 0.10), (0.24, 0, 0.35), m[body], bevel=0.0)
        box("carryB", (0.06, 0.08, 0.10), (-0.12, 0, 0.35), m[body], bevel=0.0)
    else:
        rail(m, -0.25, 0.48, 0.34, 0.08, mat=body)
    mag("mag", 0.16, 0.05, m["black"], h=0.42, w=0.14, t=0.10, curve=0.06)
    grip("grip", -0.12, 0.05, m[furn], h=0.33, w=0.13)
    guard("guard", -0.10, 0.12, 0.04, m[body])
    box("bufferTube", (0.32, 0.08, 0.08), (-0.44, 0, 0.24), m["black"])
    prism("stock", [(-0.48, 0.32), (-0.48, 0.10), (-0.66, 0.02), (-0.92, 0.0), (-0.92, 0.33)], 0.13, m[furn])
    box("butt", (0.04, 0.14, 0.34), (-0.94, 0, 0.16), m["rubber"])
    return x_end + 0.32


def rifle_m4a1(m):
    end = _ar15(m, "gunmetal", "black", long=1.0, carry=True, rails=True)
    return {"grip": (-0.24, 0, -0.08), "muzzle": (end, 0, 0.23)}


def rifle_scarh(m):
    # SCAR-H : boîtier supérieur long anguleux beige, crosse repliable beige, chargeur droit noir
    box("upper", (1.20, 0.15, 0.20), (0.28, 0, 0.26), m["tan"], bevel=0.025)
    rail(m, -0.25, 0.86, 0.38, 0.09, mat="tan")
    for z in (0.18,):
        rail(m, 0.55, 0.86, z - 0.02, 0.09, mat="tan")
    box("lower", (0.56, 0.13, 0.14), (0.00, 0, 0.10), m["tan"], bevel=0.02)
    cyl_x("barrel", 0.036, 0.036, 0.44, (1.08, 0, 0.26), m["dark"])
    cyl_x("brake", 0.055, 0.055, 0.14, (1.34, 0, 0.26), m["dark"], seg=8)
    box("charging", (0.05, 0.05, 0.10), (0.62, -0.09, 0.30), m["dark"], rot=(0, 0.5, 0))
    box("sightB", (0.06, 0.07, 0.08), (-0.18, 0, 0.45), m["dark"], bevel=0.0)
    box("sightF", (0.05, 0.07, 0.10), (0.80, 0, 0.46), m["dark"], bevel=0.0)
    mag("mag", 0.14, 0.05, m["black"], h=0.38, w=0.16, t=0.11)
    grip("grip", -0.14, 0.05, m["black"], h=0.33, w=0.13)
    guard("guard", -0.12, 0.10, 0.04, m["tan"])
    prism("stock", [(-0.32, 0.34), (-0.32, 0.12), (-0.60, 0.08), (-0.90, -0.06), (-0.98, -0.06),
                    (-0.98, 0.34)], 0.14, m["tan"])
    box("cheek", (0.40, 0.15, 0.05), (-0.68, 0, 0.36), m["tan"])
    return {"grip": (-0.26, 0, -0.08), "muzzle": (1.42, 0, 0.26)}


def rifle_aug(m):
    # AUG : bullpup, corps arrière massif (chargeur derrière la poignée), lunette intégrée, poignée avant
    prof = [(-0.86, 0.30), (-0.86, -0.02), (-0.70, -0.12), (-0.18, -0.12), (-0.10, 0.04), (0.42, 0.06),
            (0.50, 0.20), (0.50, 0.30)]
    prism("body", prof, 0.17, m["legend"])
    box("butt", (0.04, 0.17, 0.30), (-0.88, 0, 0.14), m["rubber"])
    mag("mag", -0.40, -0.10, m["black"], h=0.32, w=0.15, t=0.11, curve=0.04)
    grip("grip", 0.08, 0.04, m["black"], h=0.34, w=0.13, slant=0.15)
    guard("guardLoop", -0.06, 0.40, 0.03, m["legend"])
    prism("vgrip", [(0.40, 0.06), (0.50, 0.06), (0.48, -0.30), (0.40, -0.30)], 0.09, m["black"])
    cyl_x("barrel", 0.04, 0.04, 0.70, (0.80, 0, 0.20), m["dark"])
    cyl_x("flash", 0.055, 0.05, 0.14, (1.20, 0, 0.20), m["dark"], seg=8)
    # lunette intégrée sur poignée de transport
    box("carry", (0.70, 0.08, 0.10), (-0.05, 0, 0.38), m["legend"])
    scope(m, -0.36, 0.22, 0.50, r=0.065, body="black", ring="gold")
    for k in range(2):
        box("goldBand", (0.04, 0.175, 0.30), (-0.62 + k * 0.30, 0, 0.12), m["gold"], bevel=0.0)
    return {"grip": (-0.02, 0, -0.12), "muzzle": (1.28, 0, 0.20)}


# --------------------------------------------------------------------------- snipers

def sniper_m24(m):
    # M24 : crosse bois sombre, verrou, lunette longue, canon fin
    cyl_x("barrel", 0.042, 0.032, 1.50, (1.10, 0, 0.22), m["dark"], seg=10)
    box("receiver", (0.60, 0.11, 0.14), (0.05, 0, 0.22), m["dark"], bevel=0.02)
    bolt = C.bm_tube([(-0.10, -0.06, 0.25), (-0.10, -0.16, 0.20), (-0.09, -0.20, 0.12)], [0.02, 0.02, 0.02], seg=6)
    C.mesh_obj("bolt", bolt, m["steel"])
    C.mesh_obj("knob", C.bm_xform(C.bm_sphere(8, 6, 0.045), loc=(-0.09, -0.20, 0.12)), m["dark"])
    scope(m, -0.28, 0.58, 0.42, r=0.075)
    stock = [(1.00, 0.20), (1.00, 0.10), (0.40, 0.04), (-0.10, 0.02), (-0.30, -0.28), (-0.42, -0.28),
             (-0.46, -0.04), (-1.10, -0.20), (-1.10, 0.24), (-0.55, 0.26), (-0.30, 0.16)]
    prism("stock", stock, 0.13, m["wood_dark"])
    box("butt", (0.05, 0.14, 0.45), (-1.12, 0, 0.02), m["rubber"])
    guard("guard", -0.24, -0.02, 0.02, m["dark"])
    return {"grip": (-0.38, 0, -0.12), "muzzle": (1.86, 0, 0.22)}


def sniper_ax50(m):
    # AX-50 : châssis tactique, crosse squelette, chargeur, frein de bouche, longue lunette
    cyl_x("barrel", 0.05, 0.042, 1.40, (1.10, 0, 0.24), m["gunmetal"], seg=10)
    box("brake", (0.18, 0.11, 0.11), (1.86, 0, 0.24), m["dark"], bevel=0.02)
    box("chassis", (1.10, 0.15, 0.16), (0.20, 0, 0.18), m["gunmetal"], bevel=0.02)
    slots(m, 0.40, 5, 0.10, 0.18, 0.05, 0.155, "black")
    rail(m, -0.30, 0.70, 0.29, 0.09)
    scope(m, -0.30, 0.62, 0.45, r=0.085)
    mag("mag", 0.02, 0.10, m["black"], h=0.30, w=0.18, t=0.11)
    grip("grip", -0.20, 0.10, m["black"], h=0.34, w=0.14)
    guard("guard", -0.18, 0.04, 0.09, m["dark"])
    pts = [(-0.38, 0, 0.30), (-1.00, 0, 0.30), (-1.00, 0, -0.04), (-0.62, 0, 0.02), (-0.38, 0, 0.12)]
    C.mesh_obj("skel", C.bm_tube(pts, [0.04] * 5, seg=6), m["black"])
    box("butt", (0.05, 0.14, 0.40), (-1.02, 0, 0.13), m["rubber"])
    box("cheek", (0.30, 0.12, 0.05), (-0.75, 0, 0.36), m["black"])
    for sy in (-0.04, 0.04):
        C.mesh_obj("bipod", C.bm_tube([(1.00, sy, 0.14), (1.12, sy * 3, -0.28)], [0.022, 0.018], seg=6), m["dark"])
    return {"grip": (-0.32, 0, -0.08), "muzzle": (1.96, 0, 0.24)}


def sniper_m82(m):
    # Barrett M82 : gros boîtier rectangulaire, canon épais à frein en flèche, poignée de transport, bipied
    cyl_x("barrel", 0.065, 0.055, 1.30, (1.30, 0, 0.26), m["silver"], seg=12)
    prism("brake", [(1.90, 0.18), (2.10, 0.14), (2.12, 0.38), (1.90, 0.34)], 0.18, m["dark"])
    box("upper", (1.30, 0.17, 0.22), (0.25, 0, 0.30), m["dark"], bevel=0.03)
    slots(m, 0.50, 6, 0.10, 0.30, 0.10, 0.175, "black")
    box("lower", (0.90, 0.15, 0.16), (0.05, 0, 0.12), m["dark"], bevel=0.03)
    rail(m, -0.30, 0.60, 0.425, 0.09)
    scope(m, -0.30, 0.58, 0.58, r=0.09)
    mag("mag", 0.12, 0.05, m["black"], h=0.34, w=0.24, t=0.13)
    for k in range(3):
        box("magRib", (0.22, 0.135, 0.02), (0.24, 0, -0.05 - k * 0.09), m["dark"], bevel=0.0)
    grip("grip", -0.24, 0.05, m["black"], h=0.34, w=0.15)
    guard("guard", -0.22, 0.02, 0.04, m["dark"])
    prism("stock", [(-0.40, 0.40), (-0.40, 0.06), (-1.10, 0.02), (-1.10, 0.40)], 0.15, m["dark"])
    box("butt", (0.06, 0.17, 0.42), (-1.13, 0, 0.21), m["rubber"])
    C.mesh_obj("handle", C.bm_tube(C.bezier((0.70, 0, 0.41), (0.72, 0, 0.56), (0.92, 0, 0.56), (0.94, 0, 0.41), 7),
                                   [0.025] * 7, seg=6), m["dark"])
    for sy in (-0.04, 0.04):
        C.mesh_obj("bipod", C.bm_tube([(1.30, sy, 0.18), (1.44, sy * 3, -0.28)], [0.024, 0.02], seg=6), m["dark"])
    return {"grip": (-0.36, 0, -0.12), "muzzle": (2.12, 0, 0.26)}


# --------------------------------------------------------------------------- lance-roquettes

def rocket_rpg7(m):
    # RPG-7 : tube fin, manchon bois, ogive verte et rouge en avant, deux poignées, viseur
    cyl_x("tube", 0.075, 0.075, 1.40, (0.15, 0, 0.20), m["dark"], seg=14)
    cyl_x("woodSleeve", 0.10, 0.10, 0.52, (-0.18, 0, 0.20), m["wood"], seg=14)
    cyl_x("bell", 0.08, 0.15, 0.24, (-0.70, 0, 0.20), m["dark"], seg=14)
    cyl_x("bellRim", 0.155, 0.155, 0.03, (-0.82, 0, 0.20), m["brass"], seg=14)
    # ogive
    cyl_x("neck", 0.06, 0.06, 0.18, (0.94, 0, 0.20), m["olive"], seg=12)
    cyl_x("warhead", 0.10, 0.15, 0.16, (1.10, 0, 0.20), m["red"], seg=14)
    cyl_x("warhead2", 0.15, 0.12, 0.18, (1.27, 0, 0.20), m["red"], seg=14)
    cyl_x("cone", 0.12, 0.03, 0.24, (1.48, 0, 0.20), m["olive"], seg=14)
    cyl_x("fuze", 0.03, 0.02, 0.08, (1.63, 0, 0.20), m["brass"], seg=8)
    grip("grip", 0.30, 0.13, m["wood"], h=0.32, w=0.12, slant=0.12)
    grip("grip2", 0.68, 0.13, m["dark"], h=0.22, w=0.10, slant=0.08)
    guard("guard", 0.18, 0.32, 0.11, m["dark"])
    box("sight", (0.10, 0.06, 0.14), (0.45, 0, 0.36), m["dark"])
    box("sightTop", (0.24, 0.05, 0.04), (0.45, 0, 0.44), m["dark"])
    return {"grip": (0.20, 0, -0.06), "muzzle": (1.60, 0, 0.20)}


def rocket_m202(m):
    # M202 (tel que sur la planche) : gros tube bronze patiné, bagues, embouchure évasée, deux poignées
    cyl_x("tube", 0.15, 0.15, 1.70, (0.25, 0, 0.24), m["bronze"], seg=18)
    cyl_x("front", 0.15, 0.19, 0.20, (1.18, 0, 0.24), m["bronze"], seg=18)
    cyl_x("frontRim", 0.195, 0.195, 0.05, (1.30, 0, 0.24), m["dark"], seg=18)
    cyl_x("bore", 0.13, 0.13, 0.01, (1.33, 0, 0.24), m["black"], seg=18)
    cyl_x("back", 0.17, 0.17, 0.12, (-0.62, 0, 0.24), m["dark"], seg=18)
    for x in (-0.40, 0.10, 0.60, 1.02):
        cyl_x("band", 0.158, 0.158, 0.05, (x, 0, 0.24), m["dark"], seg=18)
    box("rib", (1.30, 0.05, 0.03), (0.30, 0, 0.395), m["dark"])
    box("sight", (0.14, 0.08, 0.12), (0.30, -0.10, 0.44), m["dark"])
    grip("grip", 0.05, 0.10, m["dark"], h=0.30, w=0.12, slant=0.12)
    grip("grip2", 0.62, 0.10, m["dark"], h=0.24, w=0.10, slant=0.08)
    guard("guard", -0.05, 0.10, 0.08, m["dark"])
    return {"grip": (-0.04, 0, -0.08), "muzzle": (1.33, 0, 0.24)}


def rocket_javelin(m):
    # Javelin : grand tube olive sombre, CLU (unité de visée) noir et or, renflement avant
    cyl_x("tube", 0.14, 0.14, 1.70, (0.30, 0, 0.24), m["olive_dark"], seg=16)
    cyl_x("front", 0.14, 0.18, 0.22, (1.24, 0, 0.24), m["olive_dark"], seg=16)
    cyl_x("frontCap", 0.185, 0.185, 0.06, (1.38, 0, 0.24), m["black"], seg=16)
    cyl_x("back", 0.16, 0.16, 0.18, (-0.62, 0, 0.24), m["black"], seg=16)
    for x in (-0.30, 0.40, 0.90):
        cyl_x("band", 0.148, 0.148, 0.05, (x, 0, 0.24), m["gold"], seg=16)
    # CLU
    box("clu", (0.42, 0.26, 0.24), (-0.05, -0.10, 0.12), m["legend"], bevel=0.03)
    cyl_x("cluLens", 0.07, 0.07, 0.04, (0.18, -0.10, 0.14), m["glass"])
    box("cluHandle", (0.10, 0.08, 0.20), (-0.20, -0.10, -0.06), m["black"])
    grip("grip", 0.20, -0.02, m["black"], h=0.26, w=0.12, slant=0.12)
    return {"grip": (0.10, 0, -0.16), "muzzle": (1.40, 0, 0.24)}


# --------------------------------------------------------------------------- équipements

def gadget_frag(m):
    # grenade à fragmentation « ananas » kaki/bronze, levier et goupille
    body = C.bm_sphere(16, 12, 1.0)
    C.bm_xform(body, scale=(0.30, 0.30, 0.36))
    C.mesh_obj("body", body, m["khaki"])
    for k in range(5):
        z = -0.24 + k * 0.12
        r = 0.30 * math.sqrt(max(0.0, 1 - (z / 0.36) ** 2)) + 0.012
        C.mesh_obj("groove", C.bm_xform(C.bm_torus(18, 5, r, 0.014), loc=(0, 0, z)), m["olive_dark"])
    for k in range(8):
        a = k * math.pi / 4
        pts = [(0.30 * math.cos(a) * math.sin(t), 0.30 * math.sin(a) * math.sin(t), 0.36 * math.cos(t))
               for t in (0.4 + 0.3 * i for i in range(9))]
        C.mesh_obj("groove", C.bm_tube(pts, [0.013] * 9, seg=5), m["olive_dark"])
    cyl_z("neck", 0.10, 0.09, 0.12, (0, 0, 0.40), m["brass"])
    cyl_z("cap", 0.11, 0.11, 0.06, (0, 0, 0.48), m["dark"])
    lever = C.bm_tube(C.bezier((0.06, 0, 0.50), (0.18, 0, 0.52), (0.30, 0, 0.30), (0.31, 0, 0.02), 6),
                      [0.03] * 6, seg=6, flat=0.4, up=(0, 1, 0))
    C.mesh_obj("lever", lever, m["dark"])
    C.mesh_obj("ring", C.bm_xform(C.bm_torus(16, 5, 0.09, 0.014), loc=(-0.14, -0.05, 0.50), rot=(1.2, 0, 0)),
               m["steel"])
    return {"grip": (0.0, 0, 0.0), "muzzle": (0.32, 0, 0.10)}


def gadget_smoke(m):
    # fumigène : cylindre olive à bande jaune et bande rouge, bouchon et levier
    cyl_z("body", 0.20, 0.20, 0.72, (0, 0, 0.0), m["cream"], seg=20)
    cyl_z("band", 0.205, 0.205, 0.40, (0, 0, -0.02), m["olive"], seg=20)
    cyl_z("bandY", 0.207, 0.207, 0.06, (0, 0, 0.24), C.toon("yellow", "#d8b030", "#5a4020", "#ffe070"), seg=20)
    cyl_z("bandR", 0.207, 0.207, 0.04, (0, 0, -0.30), m["red"], seg=20)
    cyl_z("top", 0.12, 0.17, 0.08, (0, 0, 0.40), m["steel"], seg=20)
    cyl_z("cap", 0.09, 0.09, 0.08, (0, 0, 0.48), m["dark"])
    lever = C.bm_tube(C.bezier((0.06, 0, 0.50), (0.16, 0, 0.54), (0.24, 0, 0.34), (0.23, 0, 0.0), 6),
                      [0.03] * 6, seg=6, flat=0.4, up=(0, 1, 0))
    C.mesh_obj("lever", lever, m["dark"])
    C.mesh_obj("ring", C.bm_xform(C.bm_torus(16, 5, 0.08, 0.014), loc=(-0.12, -0.05, 0.52), rot=(1.2, 0, 0)),
               m["steel"])
    return {"grip": (0.0, 0, 0.0), "muzzle": (0.24, 0, 0.10)}


def gadget_mine(m):
    # mine antipersonnel ronde en bronze/laiton, couvercle cannelé, détonateur central, poignée
    cyl_z("body", 0.40, 0.42, 0.22, (0, 0, 0.0), m["brass"], seg=28)
    cyl_z("lid", 0.34, 0.38, 0.06, (0, 0, 0.14), m["bronze"], seg=28)
    for k in range(12):
        a = k * math.pi / 6
        box("rib", (0.26, 0.025, 0.02), (0.20 * math.cos(a), 0.20 * math.sin(a), 0.18), m["dark"],
            rot=(0, 0, a), bevel=0.0)
    cyl_z("fuze", 0.08, 0.10, 0.10, (0, 0, 0.22), m["dark"])
    cyl_z("pin", 0.03, 0.03, 0.06, (0, 0, 0.30), m["steel"])
    C.mesh_obj("handle", C.bm_tube(C.bezier((0.30, 0, 0.12), (0.42, 0, 0.30), (0.20, 0, 0.36), (0.10, 0, 0.26), 6),
                                   [0.022] * 6, seg=6), m["dark"])
    return {"grip": (0.0, 0, 0.0), "muzzle": (0.42, 0, 0.0)}


def gadget_c4(m):
    # C4 : pain d'explosif emballé noir, sangles, minuterie avec LED rouges, fils
    box("block", (0.80, 0.42, 0.30), (0, 0, 0.0), m["black"], bevel=0.035)
    for x in (-0.26, 0.26):
        box("strap", (0.07, 0.44, 0.32), (x, 0, 0.0), m["dark"], bevel=0.01)
        box("buckle", (0.08, 0.02, 0.06), (x, -0.225, 0.04), m["red"], bevel=0.0)
    box("label", (0.30, 0.01, 0.12), (0.0, -0.215, 0.02), m["putty"], bevel=0.0)
    box("timer", (0.26, 0.20, 0.08), (0.0, 0.0, 0.19), m["dark"], bevel=0.02)
    box("screen", (0.16, 0.10, 0.012), (0.0, -0.02, 0.235), m["led"], bevel=0.0)
    for k, x in enumerate((-0.30, 0.30)):
        box("cap", (0.06, 0.06, 0.08), (x, 0.10, 0.19), m["red"], bevel=0.01)
    C.mesh_obj("wire", C.bm_tube(C.bezier((0.12, 0.05, 0.20), (0.20, -0.10, 0.30), (0.28, -0.05, 0.28),
                                          (0.30, 0.10, 0.23), 6), [0.014] * 6, seg=5), m["red"])
    C.mesh_obj("wire2", C.bm_tube(C.bezier((-0.12, 0.05, 0.20), (-0.20, -0.10, 0.30), (-0.28, -0.05, 0.28),
                                           (-0.30, 0.10, 0.23), 6), [0.014] * 6, seg=5), m["gold"])
    return {"grip": (0.0, 0, 0.0), "muzzle": (0.40, 0, 0.0)}


def gadget_drone(m, rotor_phase: float = 0.0):
    # quadrirotor : coque bleu nuit, quatre bras, protections d'hélices, caméra sous le nez
    shell = C.bm_sphere(20, 12, 1.0)
    C.bm_xform(shell, scale=(0.28, 0.24, 0.12))
    C.mesh_obj("shell", shell, C.toon("droneBody", "#283a6a", "#0a1028", "#5a7ab8", rim=0.45))
    box("bottom", (0.36, 0.30, 0.06), (0, 0, -0.08), m["black"], bevel=0.02)
    cyl_x("cam", 0.05, 0.05, 0.08, (0.28, 0, -0.10), m["black"])
    cyl_x("camLens", 0.035, 0.035, 0.01, (0.325, 0, -0.10), m["glass"])
    C.mesh_obj("led", C.bm_xform(C.bm_sphere(8, 6, 0.025), loc=(0.20, 0, 0.08)), m["led_b"])
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        x, y = 0.55 * math.cos(a), 0.55 * math.sin(a)
        C.mesh_obj("arm", C.bm_tube([(0.12 * math.cos(a), 0.12 * math.sin(a), 0.0), (x, y, 0.02)], [0.03, 0.025],
                                    seg=6), m["black"])
        cyl_z("motor", 0.045, 0.045, 0.08, (x, y, 0.05), m["dark"])
        C.mesh_obj("guard", C.bm_xform(C.bm_torus(28, 5, 0.25, 0.012), loc=(x, y, 0.06)), m["steel"])
        for b in range(2):
            ang = rotor_phase + a * 1.7 + b * math.pi
            box("blade", (0.22, 0.04, 0.008), (x + 0.11 * math.cos(ang), y + 0.11 * math.sin(ang), 0.10),
                C.toon("blade", "#c8ccd8", "#5a5e78", "#ffffff", rim=0.2), rot=(0, 0, ang), bevel=0.0)
    for sx in (-1, 1):   # patins
        C.mesh_obj("skid", C.bm_tube([(0.15, 0.12 * sx, -0.10), (0.15, 0.16 * sx, -0.22), (-0.15, 0.16 * sx, -0.22),
                                      (-0.15, 0.12 * sx, -0.10)], [0.012] * 4, seg=5), m["dark"])
    return {"grip": (-0.10, 0, -0.10), "muzzle": (0.30, 0, -0.10)}


WEAPONS = {
    "pistol_p9": pistol_p9, "pistol_glock18": pistol_glock18, "pistol_deagle": pistol_deagle,
    "pistol_p320": pistol_p320,
    "smg_mp5": smg_mp5, "smg_vector": smg_vector, "smg_p90": smg_p90, "smg_uzi": smg_uzi,
    "rifle_ak47": rifle_ak47, "rifle_m4a1": rifle_m4a1, "rifle_scarh": rifle_scarh, "rifle_aug": rifle_aug,
    "sniper_m24": sniper_m24, "sniper_ax50": sniper_ax50, "sniper_m82": sniper_m82,
    "rocket_rpg7": rocket_rpg7, "rocket_m202": rocket_m202, "rocket_javelin": rocket_javelin,
    "gadget_frag": gadget_frag, "gadget_smoke": gadget_smoke, "gadget_mine": gadget_mine,
    "gadget_c4": gadget_c4, "gadget_drone": gadget_drone,
}
RARITY = {"pistol_p9": 0, "pistol_glock18": 2, "pistol_deagle": 3, "pistol_p320": 4,
          "smg_mp5": 0, "smg_vector": 2, "smg_p90": 3, "smg_uzi": 4,
          "rifle_ak47": 0, "rifle_m4a1": 2, "rifle_scarh": 3, "rifle_aug": 4,
          "sniper_m24": 0, "sniper_ax50": 2, "sniper_m82": 3,
          "rocket_rpg7": 2, "rocket_m202": 3, "rocket_javelin": 4,
          "gadget_frag": 0, "gadget_smoke": 2, "gadget_mine": 3, "gadget_c4": 4, "gadget_drone": 4}
# Gadgets tenus : rendus à ~48 px de large, affichés à GADGET_SCALE (~14 unités monde en main).
GADGET_SCALE = 0.30


def _points():
    import numpy as np
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    pts = []
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH" or ob.hide_render:
            continue
        ev = ob.evaluated_get(deps)
        me = ev.to_mesh()
        mw = ob.matrix_world
        for v in me.vertices:
            pts.append(tuple(mw @ v.co))
        ev.to_mesh_clear()
    return np.array(pts)


def _cam_uv(cam, pts):
    import numpy as np
    m = cam.matrix_world.inverted()
    R = np.array(m)[:3, :3]
    T = np.array(m)[:3, 3]
    loc = pts @ R.T + T
    return loc[:, 0], loc[:, 1]


def _render(wid, build, elev, size, outline, pad_px, azim=0.0, ppu=PX_PER_UNIT):
    """Rend l'objet ; size None = taille déduite de ppu. Renvoie (chemin, cam, info, (W, H))."""
    C.reset_scene()
    info = build(mats())
    pts = _points()
    cam = C.ortho_camera(elev, 10.0, target=(0, 0, 0), azim_deg=azim)
    bpy.context.view_layer.update()
    u, v = _cam_uv(cam, pts)
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
    C.setup_render((W * SS, H * SS), samples=6, outline_px=outline * SS, inner_ratio=0.45)
    bpy.context.scene.camera = cam
    os.makedirs(TMP, exist_ok=True)
    big = os.path.join(TMP, wid + "_big.png")
    C.render_to(big)
    return big, cam, info, (W, H)


def render_item(wid: str) -> None:
    fn = WEAPONS[wid]
    gadget = wid.startswith("gadget_")
    # sprite tenu
    if gadget:
        # gadgets : taille fixe à l'écran (~GADGET_HELD_PX px de large x scale)
        C.reset_scene()
        fn(mats())
        u, _v = _cam_uv(C.ortho_camera(HELD_ELEV, 10.0), _points())
        ppu = 48.0 / max(u.max() - u.min(), 1e-3)
    else:
        ppu = PX_PER_UNIT
    big, cam, info, (W, H) = _render(wid, fn, HELD_ELEV, None, 1.3, 3, ppu=ppu)
    os.makedirs(OUT, exist_ok=True)
    C.downscale(big, os.path.join(OUT, wid + ".png"), (W, H))
    g = C.world_to_px(cam, info["grip"])
    mz = C.world_to_px(cam, info["muzzle"])
    meta = {
        "grip": [round(g[0] / SS), round(g[1] / SS)],
        "muzzle": [round(mz[0] / SS), round(mz[1] / SS)],
        "scale": GADGET_SCALE if gadget else HELD_SCALE,
        "size": [W, H],
        "rarity": RARITY[wid],
    }
    with open(os.path.join(OUT, wid + ".json"), "w") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    # icône de profil
    big, _c, _i, (W, H) = _render(wid, fn, ICON_ELEV if not gadget else 22.0, ICON_SIZE,
                                  2.2, 10, azim=ICON_AZIM if not gadget else -25.0)
    os.makedirs(OUT_ICON, exist_ok=True)
    C.downscale(big, os.path.join(OUT_ICON, wid + ".png"), (W, H))
    # objet au sol / en vol (vu du dessus, 3/4 très plongeant)
    if gadget:
        if wid == "gadget_drone":
            for suffix, ph in (("_world", 0.0), ("_world_b", math.pi / 2)):
                big, _c, _i, _s = _render(wid + suffix, lambda mm, ph=ph: gadget_drone(mm, ph), 70.0,
                                          (WORLD_SIZE, WORLD_SIZE), 1.4, 2)
                C.downscale(big, os.path.join(OUT, wid + suffix + ".png"), (WORLD_SIZE, WORLD_SIZE))
        else:
            big, _c, _i, _s = _render(wid + "_world", fn, 62.0, (WORLD_SIZE, WORLD_SIZE), 1.6, 4, azim=-20.0)
            C.downscale(big, os.path.join(OUT, wid + "_world.png"), (WORLD_SIZE, WORLD_SIZE))
    print("ITEM", wid, meta, flush=True)


RARITY_COL = {0: (150, 156, 168), 2: (60, 120, 230), 3: (150, 70, 230), 4: (230, 170, 50)}


def contact_sheet(out: str) -> None:
    """Planche façon arsenal.jpg : vignettes à fond de rareté, icône + nom."""
    from PIL import Image, ImageDraw
    ids = list(WEAPONS)
    cols = 4
    cw, ch = 300, 186
    sheet = Image.new("RGBA", (cw * cols + 10, ch * math.ceil(len(ids) / cols) + 10), (14, 20, 36, 255))
    dr = ImageDraw.Draw(sheet)
    for k, wid in enumerate(ids):
        x, y = 10 + (k % cols) * cw, 10 + (k // cols) * ch
        col = RARITY_COL[RARITY[wid]]
        dr.rounded_rectangle((x, y, x + cw - 12, y + ch - 12), 10, fill=(col[0] // 6 + 14, col[1] // 6 + 18,
                                                                          col[2] // 6 + 30, 255), outline=col, width=2)
        ic = Image.open(os.path.join(OUT_ICON, wid + ".png"))
        sheet.alpha_composite(ic, (x + 10, y + 6))
        if wid.startswith("gadget_"):
            wo = Image.open(os.path.join(OUT, wid + "_world.png"))
            sheet.alpha_composite(wo, (x + cw - 12 - 70, y + ch - 12 - 70))
        held = Image.open(os.path.join(OUT, wid + ".png"))
        sheet.alpha_composite(held, (x + 10, y + ch - 14 - held.height - 16))
        dr.rectangle((x, y + ch - 32, x + cw - 12, y + ch - 12), fill=col)
        dr.text((x + 10, y + ch - 28), wid, fill=(255, 255, 255, 255))
    sheet.save(out)
    print("SHEET", out)


# Repli par catégorie (WeaponCatalog.icon_for / WeaponView : <category>.png) = modèle commun de la catégorie.
CATEGORY_FALLBACK = {"pistol": "pistol_p9", "smg": "smg_mp5", "rifle": "rifle_ak47", "sniper": "sniper_m24",
                     "rocket_launcher": "rocket_rpg7", "gadget": "gadget_frag"}


def write_category_fallbacks() -> None:
    import shutil
    for cat, src in CATEGORY_FALLBACK.items():
        if not os.path.exists(os.path.join(OUT, src + ".png")):
            continue
        shutil.copy(os.path.join(OUT_ICON, src + ".png"), os.path.join(OUT_ICON, cat + ".png"))
        for ext in (".png", ".json"):
            shutil.copy(os.path.join(OUT, src + ext), os.path.join(OUT, cat + ext))


def main() -> None:
    args = sys.argv[1:]
    if "--sheet" in args:
        contact_sheet(args[args.index("--sheet") + 1])
        return
    for wid in (args or list(WEAPONS)):
        render_item(wid)
    write_category_fallbacks()


if __name__ == "__main__":
    main()
