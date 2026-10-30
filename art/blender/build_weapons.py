"""Arsenal d'Exfil Rush (planche docs/reference/arsenal.jpg) : 30 armes + 5 équipements.

Usage (depuis la racine du projet) :
    python3 art/blender/build_weapons.py                   # tout (sprites tenus, icônes, sprites au sol)
    python3 art/blender/build_weapons.py smg_mp5 rifle_aug # quelques-uns
    python3 art/blender/build_weapons.py --phase8          # les 12 armes de la phase 8 (revolvers, pompes, LMG, LG)
    python3 art/blender/build_weapons.py --sheet out.png   # planche-contact des icônes (après rendu)
    python3 art/blender/build_weapons.py --phase8 --sheet out.png   # planche des 12 armes de la phase 8
Sans bpy en module : blender -b --python lanceur.py -- art/blender/build_weapons.py <args>, où le lanceur
remplace sys.argv par [script, args...] puis exécute le script (Pillow doit être importable).

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


# --------------------------------------------------------------------------- briques (phase 8)

def curve2d(*segs, n=6):
    """Profil 2D (x, z) fait de segments de Bézier cubiques [(p0, p1, p2, p3), ...] et de points seuls."""
    out = []
    for s in segs:
        if len(s) == 4 and isinstance(s[0], tuple):
            p0, p1, p2, p3 = s
            for i in range(n + 1):
                t = i / n
                a, b, c, d = (1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3
                pt = (a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1])
                if not out or abs(out[-1][0] - pt[0]) + abs(out[-1][1] - pt[1]) > 1e-4:
                    out.append(pt)
        else:
            out.append(s)
    return out


def flutes(m, x, z, r, length, n, mat, phase=0.0, w=0.035, depth=0.02):
    """Cannelures d'un barillet d'axe X (bandes sombres posées sur la surface)."""
    for k in range(n):
        a = phase + k * 2 * math.pi / n
        box("flute", (length, depth, w), (x, -r * math.cos(a), z + r * math.sin(a)), m[mat],
            rot=(math.pi - a, 0, 0), bevel=0.0)


def ribs_x(m, x0, x1, n, z, size_y, size_z, mat):
    """Anneaux / nervures transversales régulières (garde-main striés, devant de pompe)."""
    for k in range(n):
        xx = x0 + (x1 - x0) * (k + 0.5) / n
        box("rib", (0.022, size_y, size_z), (xx, 0, z), m[mat], bevel=0.0)


def shells(m, pts, mat="brass", tip="dark", r=0.026):
    """Bande de cartouches (mitrailleuses) : une cartouche couchée par point, pointe vers +X."""
    for (x, y, z) in pts:
        cyl_x("round", r, r, 0.10, (x, y, z), m[mat], seg=8)
        cyl_x("tip", r, r * 0.35, 0.05, (x + 0.075, y, z), m[mat], seg=8)
        box("link", (0.03, r * 2.4, r * 2.4), (x - 0.02, y, z), m[tip], bevel=0.0)


def bipod(m, x, z, mat="dark", deployed=True, y=0.05):
    for sy in (-y, y):
        if deployed:
            C.mesh_obj("bipod", C.bm_tube([(x, sy, z), (x + 0.16, sy * 3, z - 0.46)], [0.024, 0.02], seg=6), m[mat])
            C.mesh_obj("foot", C.bm_xform(C.bm_sphere(8, 6, 0.03), loc=(x + 0.16, sy * 3, z - 0.47)), m["rubber"])
        else:
            C.mesh_obj("bipod", C.bm_tube([(x, sy, z), (x - 0.42, sy * 1.2, z - 0.05)], [0.022, 0.02], seg=6), m[mat])


# --------------------------------------------------------------------------- revolvers

def _revolver(m, frame, barrel, gripm, cyl, blen, underlug="rod", rib=False, adj_sight=False, cyl_len=0.27):
    """Revolver : barillet d'axe X (centre x=0.11, z=0.15), canon au-dessus de l'axe (z=0.21)."""
    cx, cz, r = 0.11, 0.15, 0.105
    x0, x1 = cx - cyl_len / 2, cx + cyl_len / 2
    # carcasse : montant arrière (bouclier), pontet supérieur, cadre inférieur, pied de canon
    prism("frameBack", [(x0 - 0.10, 0.30), (x0 + 0.01, 0.30), (x0 + 0.01, 0.02), (x0 - 0.06, 0.0), (x0 - 0.12, 0.10)],
          0.12, m[frame])
    box("topStrap", (cyl_len + 0.04, 0.10, 0.05), (cx, 0, 0.285), m[frame], bevel=0.01)
    box("frameLow", (cyl_len + 0.04, 0.10, 0.06), (cx, 0, 0.02), m[frame], bevel=0.01)
    box("frameFront", (0.07, 0.12, 0.30), (x1 + 0.03, 0, 0.15), m[frame], bevel=0.012)
    # barillet cannelé
    cyl_x("cylinder", r, r, cyl_len, (cx, 0, cz), m[cyl], seg=18)
    cyl_x("cylFront", r * 0.92, r * 0.80, 0.02, (x1 + 0.005, 0, cz), m[cyl], seg=18)
    flutes(m, cx + 0.01, cz, r * 0.97, cyl_len * 0.62, 6, "black", phase=math.pi / 6)
    cyl_x("pin", 0.022, 0.022, 0.06, (x1 + 0.08, 0, cz - 0.02), m["steel"], seg=8)
    # canon
    xb0 = x1 + 0.06
    cyl_x("barrel", 0.045, 0.042, blen, (xb0 + blen / 2, 0, 0.21), m[barrel], seg=14)
    cyl_x("crown", 0.034, 0.034, 0.012, (xb0 + blen + 0.004, 0, 0.21), m["black"], seg=12)
    if underlug == "full":           # Python : tenon plein sous tout le canon
        box("underlug", (blen, 0.085, 0.085), (xb0 + blen / 2, 0, 0.15), m[barrel], bevel=0.02)
    elif underlug == "shroud":       # Model 29 : carénage de la tige d'éjection, à mi-canon
        prism("shroud", [(xb0 - 0.01, 0.20), (xb0 + 0.34, 0.20), (xb0 + 0.34, 0.13), (xb0 + 0.30, 0.10),
                         (xb0 - 0.01, 0.10)], 0.08, m[barrel])
    else:                            # Peacemaker : tige d'éjection et son fourreau, côté droit
        cyl_x("ejRod", 0.022, 0.022, blen * 0.82, (xb0 + blen * 0.41, -0.035, 0.145), m[barrel], seg=8)
        cyl_x("ejHead", 0.03, 0.03, 0.04, (xb0 + 0.06, -0.06, 0.145), m["steel"], seg=8)
    if rib:                          # bande ventilée (Python)
        box("rib", (blen, 0.05, 0.022), (xb0 + blen / 2, 0, 0.295), m[barrel], bevel=0.0)
        for k in range(int(blen / 0.09)):
            box("ribPost", (0.03, 0.045, 0.05), (xb0 + 0.05 + k * 0.09, 0, 0.265), m[barrel], bevel=0.0)
    box("sightF", (0.06, 0.03, 0.06) if not rib else (0.05, 0.03, 0.05),
        (xb0 + blen - 0.04, 0, 0.27 if not rib else 0.325), m[barrel], bevel=0.0)
    if adj_sight:
        box("sightR", (0.08, 0.08, 0.05), (x0 - 0.02, 0, 0.33), m["black"], bevel=0.0)
    # chien (crête) et détente
    prism("hammer", [(x0 - 0.06, 0.26), (x0 - 0.02, 0.30), (x0 - 0.10, 0.37), (x0 - 0.17, 0.36), (x0 - 0.10, 0.30)],
          0.05, m["dark"])
    guard("guard", x0 - 0.02, x0 + 0.17, 0.0, m[frame])
    box("trigger", (0.025, 0.03, 0.10), (x0 + 0.06, 0, -0.06), m["dark"], rot=(0, 0.35, 0))
    # crosse « bec de corbin » (dos qui remonte vers le chien, talon arrondi)
    gx = x0 - 0.04
    prof = curve2d(((gx + 0.04, 0.0), (gx - 0.02, -0.06), (gx - 0.06, -0.18), (gx - 0.04, -0.30)),
                   ((gx - 0.07, -0.33), (gx - 0.14, -0.36), (gx - 0.24, -0.34), (gx - 0.26, -0.30)),
                   ((gx - 0.24, -0.20), (gx - 0.20, -0.04), (gx - 0.12, 0.10), (gx - 0.07, 0.26)),
                   (gx + 0.0, 0.10))
    prism("grip", prof, 0.13, m[gripm])
    # plaquettes de crosse (bois / caoutchouc) légèrement en relief, cadre visible autour
    inner = curve2d(((gx - 0.01, -0.03), (gx - 0.05, -0.10), (gx - 0.08, -0.20), (gx - 0.07, -0.28)),
                    ((gx - 0.07, -0.28), (gx - 0.12, -0.31), (gx - 0.18, -0.31), (gx - 0.22, -0.28)),
                    ((gx - 0.20, -0.18), (gx - 0.16, -0.06), (gx - 0.10, 0.06), (gx - 0.06, 0.08)))
    prism("gripPanel", inner, 0.145, m[gripm])
    return {"grip": (gx - 0.13, 0, -0.14), "muzzle": (xb0 + blen + 0.01, 0, 0.21), "x0": x0, "gx": gx}


def revolver_peacemaker(m):
    # Colt Single Action Army : carcasse bleuie, canon 4,75", tige d'éjection, plaquettes en noyer, chien à crête
    info = _revolver(m, "black", "dark", "wood_grip", "dark", 0.50, underlug="rod")
    box("loadGate", (0.05, 0.012, 0.10), (info["x0"] + 0.02, -0.062, 0.15), m["dark"], bevel=0.0)
    return info


def revolver_model29(m):
    # S&W Model 29 : acier patiné, canon long 8 3/8", carénage d'éjecteur, hausse réglable, crosse bois
    info = _revolver(m, "gunmetal", "gunmetal", "wood", "worn", 0.84, underlug="shroud", adj_sight=True)
    cyl_y("latch", 0.03, 0.13, (info["x0"] - 0.05, 0, 0.21), m["steel"])
    return info


def revolver_python(m):
    # Colt Python : finition nickelée gravée, canon 6" à bande ventilée et tenon plein, crosse bois à médaillon
    info = _revolver(m, "silver", "engraved", "wood_grip", "silver", 0.62, underlug="full", rib=True, adj_sight=True)
    gx = info["gx"]
    C.mesh_obj("medal", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(gx - 0.13, -0.075, -0.12), scale=(0.035, 0.012, 0.04)),
               m["gold"])
    box("goldLine", (0.30, 0.124, 0.012), (0.11, 0, 0.255), m["gold"], bevel=0.0)
    return info


# --------------------------------------------------------------------------- fusils à pompe

def _shotgun_stock(m, mat, x0=-0.02, butt="rubber", length=1.0):
    """Crosse droite de chasse (poignée anglaise) partant de l'arrière de la carcasse."""
    xb = x0 - length
    prism("stock", [(x0, 0.30), (x0, 0.10), (x0 - 0.28, 0.03), (xb, -0.16), (xb, 0.28), (x0 - 0.36, 0.24)], 0.13, m[mat])
    box("butt", (0.05, 0.14, 0.46), (xb - 0.02, 0, 0.06), m[butt])
    return {"grip": (x0 - 0.22, 0, 0.02)}


def shotgun_870(m):
    # Remington 870 : carcasse noire, long canon, tube magasin, devant de pompe strié en bois, crosse bois
    box("receiver", (0.60, 0.13, 0.22), (0.26, 0, 0.20), m["black"], bevel=0.025)
    box("port", (0.24, 0.01, 0.07), (0.30, -0.068, 0.23), m["dark"], bevel=0.0)
    box("loadPort", (0.22, 0.10, 0.02), (0.30, 0, 0.085), m["dark"], bevel=0.0)
    cyl_x("barrel", 0.042, 0.04, 1.42, (1.24, 0, 0.27), m["dark"], seg=12)
    cyl_x("vrib", 0.016, 0.016, 1.38, (1.22, 0, 0.315), m["dark"], seg=6)
    C.mesh_obj("bead", C.bm_xform(C.bm_sphere(8, 6, 0.022), loc=(1.92, 0, 0.33)), m["brass"])
    cyl_x("magTube", 0.04, 0.04, 1.10, (1.10, 0, 0.17), m["black"], seg=12)
    cyl_x("magCap", 0.046, 0.046, 0.06, (1.68, 0, 0.17), m["dark"], seg=12)
    box("barrelBand", (0.05, 0.10, 0.16), (1.58, 0, 0.22), m["dark"], bevel=0.01)
    box("pump", (0.46, 0.16, 0.13), (0.92, 0, 0.165), m["wood"], bevel=0.04)
    ribs_x(m, 0.72, 1.12, 9, 0.165, 0.166, 0.10, "wood_dark")
    guard("guard", 0.04, 0.26, 0.08, m["black"])
    box("trigger", (0.03, 0.03, 0.10), (0.14, 0, 0.02), m["dark"], rot=(0, 0.3, 0))
    info = _shotgun_stock(m, "wood", x0=-0.04, length=0.98)
    return {"grip": info["grip"], "muzzle": (1.96, 0, 0.27)}


def shotgun_benelli(m):
    # Benelli M4 : semi-auto tactique, acier patiné, crosse télescopique, poignée pistolet, œilletons, rail
    box("receiver", (0.66, 0.13, 0.22), (0.24, 0, 0.21), m["gunmetal"], bevel=0.025)
    box("port", (0.22, 0.01, 0.07), (0.30, -0.068, 0.24), m["black"], bevel=0.0)
    rail(m, -0.04, 0.52, 0.335, 0.08, mat="black")
    # œilletons (ghost ring) arrière, guidon à ailettes
    prism("ghostR", [(-0.02, 0.35), (0.06, 0.35), (0.05, 0.46), (0.01, 0.46)], 0.10, m["black"])
    cyl_y("ring", 0.03, 0.105, (0.03, 0, 0.44), m["dark"])
    cyl_x("barrel", 0.042, 0.04, 1.02, (1.06, 0, 0.27), m["dark"], seg=12)
    prism("sightF", [(1.40, 0.30), (1.48, 0.30), (1.47, 0.40), (1.42, 0.40)], 0.07, m["black"])
    cyl_x("magTube", 0.042, 0.042, 0.98, (1.04, 0, 0.17), m["black"], seg=12)
    cyl_x("magCap", 0.05, 0.05, 0.06, (1.54, 0, 0.17), m["dark"], seg=12)
    box("forend", (0.54, 0.16, 0.15), (0.84, 0, 0.18), m["black"], bevel=0.035)
    slots(m, 0.64, 5, 0.09, 0.15, 0.04, 0.165, "dark")
    box("bolt", (0.05, 0.05, 0.05), (0.36, -0.09, 0.22), m["steel"], bevel=0.01)
    grip("grip", -0.02, 0.10, m["black"], h=0.34, w=0.13)
    guard("guard", 0.00, 0.22, 0.09, m["gunmetal"])
    box("trigger", (0.03, 0.03, 0.10), (0.10, 0, 0.03), m["dark"], rot=(0, 0.3, 0))
    # crosse télescopique : tube + crosse coulissante + plaque de couche
    cyl_x("tube", 0.05, 0.05, 0.50, (-0.30, 0, 0.24), m["black"], seg=10)
    prism("stock", [(-0.36, 0.33), (-0.36, 0.14), (-0.56, 0.04), (-0.82, 0.0), (-0.82, 0.34)], 0.13, m["black"])
    box("cheek", (0.30, 0.135, 0.04), (-0.62, 0, 0.34), m["worn"])
    box("butt", (0.05, 0.14, 0.36), (-0.84, 0, 0.17), m["rubber"])
    return {"grip": (-0.12, 0, -0.08), "muzzle": (1.58, 0, 0.27)}


def shotgun_aa12(m):
    # AA-12 : automatique, corps rectiligne massif (crosse dans l'axe), chargeur tambour, manchon ventilé
    prof = [(-0.96, 0.34), (-0.96, -0.08), (-0.82, -0.08), (-0.62, 0.06), (-0.22, 0.10), (0.70, 0.10),
            (0.76, 0.16), (0.76, 0.34), (0.66, 0.40), (-0.20, 0.40), (-0.60, 0.38)]
    prism("body", prof, 0.17, m["legend"])
    box("butt", (0.05, 0.18, 0.44), (-0.98, 0, 0.13), m["rubber"])
    rail(m, -0.20, 0.66, 0.42, 0.08, mat="black")
    # poignée de transport et organes de visée
    C.mesh_obj("handle", C.bm_tube(C.bezier((-0.10, 0, 0.42), (-0.06, 0, 0.58), (0.22, 0, 0.58), (0.26, 0, 0.42), 7),
                                   [0.028] * 7, seg=6), m["black"])
    box("sightF", (0.05, 0.07, 0.10), (0.62, 0, 0.48), m["black"], bevel=0.0)
    # manchon de canon ventilé + canon court + cache-flamme
    box("shroud", (0.46, 0.15, 0.16), (0.99, 0, 0.25), m["legend"], bevel=0.02)
    slots(m, 0.82, 4, 0.10, 0.25, 0.06, 0.155, "black")
    cyl_x("barrel", 0.045, 0.045, 0.16, (1.30, 0, 0.25), m["dark"], seg=12)
    cyl_x("brake", 0.06, 0.06, 0.10, (1.42, 0, 0.25), m["gold"], seg=10)
    # tambour de 20 coups devant la poignée
    cyl_y("drum", 0.25, 0.17, (0.28, 0, -0.20), m["black"])
    cyl_y("drumFace", 0.20, 0.18, (0.28, 0, -0.20), m["legend"])
    cyl_y("drumHub", 0.06, 0.19, (0.28, 0, -0.20), m["gold"])
    box("feed", (0.20, 0.14, 0.16), (0.28, 0, 0.06), m["black"], bevel=0.01)
    grip("grip", -0.10, 0.10, m["black"], h=0.36, w=0.14, slant=0.22)
    guard("guard", -0.08, 0.10, 0.09, m["legend"])
    box("trigger", (0.03, 0.03, 0.10), (0.00, 0, 0.03), m["gold"], rot=(0, 0.3, 0))
    for x in (-0.70, -0.36):
        box("goldBand", (0.04, 0.178, 0.30), (x, 0, 0.18), m["gold"], bevel=0.0)
    return {"grip": (-0.20, 0, -0.08), "muzzle": (1.48, 0, 0.25)}


# --------------------------------------------------------------------------- mitrailleuses

def lmg_m249(m):
    # M249 SAW : boîtier noir, capot d'alimentation, boîte de bande souple sous l'arme, poignée de transport,
    # bipied replié sous le canon, crosse pleine
    box("receiver", (0.84, 0.15, 0.22), (0.14, 0, 0.22), m["black"], bevel=0.025)
    box("cover", (0.46, 0.15, 0.07), (0.02, 0, 0.365), m["dark"], bevel=0.02)
    box("sightR", (0.08, 0.07, 0.07), (-0.16, 0, 0.42), m["dark"], bevel=0.0)
    rail(m, -0.10, 0.24, 0.41, 0.07)
    box("handguard", (0.40, 0.17, 0.16), (0.76, 0, 0.18), m["black"], bevel=0.035)
    ribs_x(m, 0.60, 0.92, 6, 0.18, 0.175, 0.12, "dark")
    cyl_x("barrel", 0.04, 0.038, 1.00, (1.06, 0, 0.27), m["dark"], seg=12)
    cyl_x("gasTube", 0.035, 0.035, 0.40, (1.12, 0, 0.17), m["dark"], seg=10)
    box("gasBlock", (0.08, 0.09, 0.16), (1.32, 0, 0.21), m["dark"])
    box("sightF", (0.04, 0.05, 0.14), (1.50, 0, 0.36), m["dark"], bevel=0.0)
    cyl_x("flash", 0.05, 0.05, 0.14, (1.62, 0, 0.27), m["dark"], seg=8)
    C.mesh_obj("handle", C.bm_tube(C.bezier((0.66, 0, 0.30), (0.68, 0, 0.46), (0.90, 0, 0.46), (0.92, 0, 0.30), 7),
                                   [0.024] * 7, seg=6), m["black"])
    bipod(m, 1.30, 0.14, deployed=False)
    # boîte à munitions + bande qui remonte vers le boîtier
    box("ammoBox", (0.30, 0.18, 0.28), (0.26, 0, -0.04), m["olive"], bevel=0.03)
    box("ammoLid", (0.32, 0.19, 0.04), (0.26, 0, 0.11), m["olive_dark"], bevel=0.01)
    box("ammoStrap", (0.04, 0.185, 0.29), (0.20, 0, -0.04), m["olive_dark"], bevel=0.0)
    shells(m, [(0.14, -0.11, 0.16), (0.10, -0.11, 0.20)], r=0.022)
    grip("grip", -0.06, 0.11, m["black"], h=0.34, w=0.13)
    guard("guard", -0.04, 0.10, 0.10, m["black"])
    prism("stock", [(-0.28, 0.32), (-0.28, 0.12), (-0.54, 0.06), (-0.98, 0.0), (-0.98, 0.34), (-0.56, 0.34)],
          0.14, m["black"])
    slots(m, -0.80, 3, 0.12, 0.17, 0.10, 0.145, "dark")
    box("butt", (0.05, 0.15, 0.36), (-1.00, 0, 0.17), m["rubber"])
    return {"grip": (-0.16, 0, -0.07), "muzzle": (1.69, 0, 0.27)}


def lmg_pkm(m):
    # PKM : boîtier d'acier embouti patiné, crosse squelette en bois, canon fin cannelé, tube de gaz sous le
    # canon, poignée de transport, cache-flamme long, boîte de 100 coups
    box("receiver", (0.80, 0.14, 0.21), (0.12, 0, 0.22), m["worn"], bevel=0.02)
    for x in (-0.14, 0.10, 0.34):
        box("rivet", (0.03, 0.145, 0.03), (x, 0, 0.17), m["dark"], bevel=0.0)
    box("cover", (0.56, 0.145, 0.06), (0.04, 0, 0.355), m["gunmetal"], bevel=0.02)
    box("sightR", (0.12, 0.07, 0.06), (0.30, 0, 0.40), m["dark"])
    cyl_x("barrel", 0.036, 0.034, 1.12, (1.08, 0, 0.27), m["dark"], seg=10)
    flutes(m, 0.80, 0.27, 0.036, 0.40, 4, "black", w=0.012, depth=0.012)
    cyl_x("gasTube", 0.032, 0.032, 0.62, (0.84, 0, 0.17), m["gunmetal"], seg=10)
    box("gasBlock", (0.08, 0.08, 0.16), (1.18, 0, 0.21), m["dark"])
    box("sightF", (0.05, 0.05, 0.16), (1.52, 0, 0.36), m["dark"], bevel=0.0)
    cyl_x("flash", 0.045, 0.05, 0.18, (1.72, 0, 0.27), m["dark"], seg=8)
    slots(m, 1.66, 3, 0.05, 0.27, 0.07, 0.105, "black")
    C.mesh_obj("handle", C.bm_tube(C.bezier((0.52, 0, 0.30), (0.52, 0, 0.46), (0.72, 0, 0.46), (0.74, 0, 0.30), 7),
                                   [0.026] * 7, seg=6), m["wood"])
    bipod(m, 1.16, 0.14, deployed=False)
    # boîte de bande métallique verte + bande
    box("ammoBox", (0.30, 0.15, 0.30), (0.26, 0, -0.06), m["olive"], bevel=0.015)
    box("ammoLid", (0.31, 0.155, 0.03), (0.26, 0, 0.09), m["dark"], bevel=0.0)
    cyl_y("ammoKnob", 0.025, 0.17, (0.20, 0, 0.00), m["dark"])
    shells(m, [(0.16, -0.10, 0.15), (0.12, -0.10, 0.19)], r=0.022)
    grip("grip", -0.08, 0.11, m["wood"], h=0.34, w=0.13)
    guard("guard", -0.06, 0.10, 0.10, m["dark"])
    # crosse squelette : cadre en tube aplati + talon plein
    pts = [(-0.28, 0, 0.30), (-0.94, 0, 0.30), (-0.96, 0, -0.06), (-0.78, 0, -0.04), (-0.42, 0, 0.10),
           (-0.28, 0, 0.14)]
    C.mesh_obj("skel", C.bm_tube(pts + [pts[0]], [0.045] * 7, seg=6, flat=0.55, up=(0, 1, 0)), m["wood"])
    prism("heel", [(-0.96, 0.30), (-0.96, -0.06), (-0.84, -0.04), (-0.84, 0.30)], 0.11, m["wood"])
    box("butt", (0.04, 0.13, 0.40), (-0.98, 0, 0.12), m["dark"])
    return {"grip": (-0.18, 0, -0.07), "muzzle": (1.80, 0, 0.27)}


def lmg_m60(m):
    # M60 : longue silhouette droite, garde-main et crosse beige, canon argenté à poignée, bipied déployé,
    # longue bande de cartouches en laiton qui pend du côté gauche
    box("receiver", (0.90, 0.15, 0.22), (0.10, 0, 0.22), m["dark"], bevel=0.025)
    box("cover", (0.50, 0.155, 0.07), (0.04, 0, 0.365), m["gunmetal"], bevel=0.02)
    box("sightR", (0.08, 0.08, 0.10), (-0.22, 0, 0.43), m["dark"], bevel=0.0)
    box("handguard", (0.52, 0.18, 0.15), (0.84, 0, 0.17), m["tan"], bevel=0.04)
    ribs_x(m, 0.62, 1.06, 7, 0.17, 0.185, 0.10, "olive_dark")
    cyl_x("barrel", 0.042, 0.04, 1.10, (1.20, 0, 0.27), m["silver"], seg=12)
    cyl_x("gasCyl", 0.045, 0.045, 0.30, (1.24, 0, 0.17), m["dark"], seg=10)
    box("sightF", (0.04, 0.05, 0.13), (1.66, 0, 0.36), m["dark"], bevel=0.0)
    cyl_x("flash", 0.055, 0.05, 0.14, (1.80, 0, 0.27), m["dark"], seg=8)
    C.mesh_obj("handle", C.bm_tube(C.bezier((0.76, 0, 0.31), (0.80, 0, 0.50), (1.02, 0, 0.50), (1.04, 0, 0.31), 7),
                                   [0.026] * 7, seg=6), m["dark"])
    bipod(m, 1.36, 0.14, deployed=True)
    # bande de laiton : sort du capot et pend en arc sur le flanc visible
    belt = C.bezier((0.04, -0.12, 0.30), (0.06, -0.14, 0.02), (0.26, -0.14, -0.22), (0.46, -0.13, -0.24), 9)
    shells(m, belt, r=0.024)
    grip("grip", -0.10, 0.11, m["tan"], h=0.34, w=0.13)
    guard("guard", -0.08, 0.10, 0.10, m["dark"])
    prism("stock", [(-0.35, 0.32), (-0.35, 0.12), (-0.60, 0.06), (-1.08, 0.0), (-1.08, 0.34), (-0.60, 0.34)],
          0.14, m["tan"])
    box("shoulder", (0.10, 0.10, 0.06), (-0.92, 0, -0.02), m["dark"], rot=(0, 0.3, 0))
    box("butt", (0.05, 0.15, 0.36), (-1.10, 0, 0.17), m["rubber"])
    for x in (-0.48, 0.44):
        box("brassBand", (0.035, 0.158, 0.23), (x, 0, 0.22 if x > 0 else 0.22), m["brass"], bevel=0.0)
    return {"grip": (-0.20, 0, -0.07), "muzzle": (1.87, 0, 0.27)}


# --------------------------------------------------------------------------- lance-grenades

def gl_m79(m):
    # M79 « blooper » : canon court et gros à bascule, crosse et devant en bois, hausse à cadre relevée
    box("receiver", (0.30, 0.15, 0.22), (-0.02, 0, 0.21), m["black"], bevel=0.025)
    cyl_x("barrel", 0.095, 0.095, 0.76, (0.50, 0, 0.24), m["dark"], seg=18)
    cyl_x("muzzle", 0.105, 0.105, 0.05, (0.86, 0, 0.24), m["black"], seg=18)
    cyl_x("bore", 0.07, 0.07, 0.01, (0.89, 0, 0.24), m["black"], seg=16)
    box("forend", (0.42, 0.17, 0.10), (0.32, 0, 0.13), m["wood"], bevel=0.035)
    # hausse à cadre (relevée) + guidon
    box("leafBase", (0.10, 0.10, 0.04), (0.20, 0, 0.345), m["dark"], bevel=0.0)
    prism("leaf", [(0.17, 0.35), (0.21, 0.35), (0.25, 0.56), (0.21, 0.56)], 0.08, m["dark"])
    box("leafTop", (0.04, 0.10, 0.03), (0.23, 0, 0.56), m["dark"], bevel=0.0)
    box("sightF", (0.04, 0.04, 0.07), (0.80, 0, 0.36), m["dark"], bevel=0.0)
    box("latch", (0.06, 0.06, 0.05), (-0.10, 0, 0.345), m["steel"], bevel=0.0)
    guard("guard", -0.08, 0.14, 0.10, m["black"])
    box("trigger", (0.03, 0.03, 0.09), (0.02, 0, 0.04), m["dark"], rot=(0, 0.3, 0))
    prism("stock", [(-0.16, 0.30), (-0.16, 0.10), (-0.42, 0.02), (-0.90, -0.12), (-0.90, 0.28), (-0.46, 0.26)],
          0.14, m["wood"])
    box("butt", (0.08, 0.16, 0.42), (-0.94, 0, 0.08), m["rubber"], bevel=0.02)
    return {"grip": (-0.34, 0, 0.04), "muzzle": (0.90, 0, 0.24)}


def gl_china_lake(m):
    # China Lake : lance-grenades à pompe, gros canon au-dessus d'un tube magasin, pompe en bois strié,
    # carcasse d'acier patiné, crosse bois, hausse à échelle
    box("receiver", (0.58, 0.16, 0.30), (0.10, 0, 0.21), m["gunmetal"], bevel=0.03)
    box("port", (0.24, 0.01, 0.10), (0.16, -0.083, 0.27), m["black"], bevel=0.0)
    cyl_x("barrel", 0.075, 0.075, 0.96, (0.86, 0, 0.29), m["dark"], seg=16)
    cyl_x("muzzle", 0.085, 0.085, 0.05, (1.34, 0, 0.29), m["gunmetal"], seg=16)
    cyl_x("magTube", 0.07, 0.07, 0.74, (0.76, 0, 0.12), m["gunmetal"], seg=16)
    cyl_x("magCap", 0.075, 0.075, 0.05, (1.14, 0, 0.12), m["dark"], seg=16)
    box("band", (0.05, 0.12, 0.26), (1.20, 0, 0.21), m["dark"], bevel=0.01)
    cyl_x("pump", 0.10, 0.10, 0.38, (0.80, 0, 0.12), m["wood"], seg=16)
    for k in range(6):
        cyl_x("groove", 0.104, 0.104, 0.018, (0.65 + k * 0.06, 0, 0.12), m["wood_dark"], seg=16)
    # hausse à échelle repliée + guidon
    prism("ladder", [(0.04, 0.36), (0.30, 0.36), (0.30, 0.40), (0.06, 0.44)], 0.08, m["dark"])
    box("sightF", (0.04, 0.04, 0.08), (1.28, 0, 0.40), m["dark"], bevel=0.0)
    guard("guard", -0.06, 0.16, 0.06, m["gunmetal"])
    box("trigger", (0.03, 0.03, 0.09), (0.04, 0, 0.00), m["dark"], rot=(0, 0.3, 0))
    info = _shotgun_stock(m, "wood", x0=-0.18, length=0.80)
    return {"grip": info["grip"], "muzzle": (1.37, 0, 0.29)}


def gl_m32(m):
    # M32 MGL : barillet tournant de 6 coups cannelé, carcasse ouverte beige, rail + viseur, poignée avant
    # verticale, crosse télescopique
    cx, cz, r, L = 0.24, 0.10, 0.20, 0.40
    # carcasse : bloc arrière (poignée), longerons haut/bas reliant le canon, plaque avant
    box("rear", (0.22, 0.16, 0.36), (-0.06, 0, 0.14), m["tan"], bevel=0.025)
    box("topStrap", (0.80, 0.10, 0.07), (0.28, 0, 0.37), m["tan"], bevel=0.015)
    rail(m, -0.10, 0.64, 0.415, 0.08, mat="black")
    box("frontPlate", (0.06, 0.16, 0.38), (cx + L / 2 + 0.04, 0, 0.17), m["tan"], bevel=0.02)
    cyl_x("axis", 0.03, 0.03, L + 0.14, (cx, 0, cz), m["steel"], seg=8)
    # barillet cannelé et têtes de grenades (laiton) visibles en façade
    cyl_x("cylinder", r, r, L, (cx, 0, cz), m["dark"], seg=24)
    flutes(m, cx, cz, r * 0.98, L * 0.82, 6, "black", phase=0.0, w=0.07, depth=0.03)
    cyl_x("cylRear", r * 1.02, r * 1.02, 0.03, (cx - L / 2, 0, cz), m["olive_dark"], seg=24)
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        cyl_x("nose", 0.055, 0.04, 0.03, (cx + L / 2 + 0.005, -0.12 * math.cos(a), cz + 0.12 * math.sin(a)),
              m["brass"], seg=10)
    # canon court rayé + bague
    cyl_x("barrel", 0.075, 0.075, 0.44, (0.73, 0, 0.24), m["dark"], seg=16)
    cyl_x("muzzle", 0.085, 0.085, 0.05, (0.96, 0, 0.24), m["black"], seg=16)
    box("barrelRail", (0.28, 0.06, 0.04), (0.70, 0, 0.335), m["tan"], bevel=0.0)
    # viseur réflexe sur le rail
    box("optic", (0.16, 0.10, 0.12), (0.12, 0, 0.49), m["black"], bevel=0.02)
    cyl_x("optLens", 0.045, 0.045, 0.01, (0.205, 0, 0.50), m["glass"], seg=12)
    # poignée avant verticale, poignée pistolet, détente
    prism("vgrip", [(0.64, 0.19), (0.74, 0.19), (0.73, -0.14), (0.65, -0.14)], 0.10, m["black"])
    grip("grip", -0.02, 0.0, m["black"], h=0.34, w=0.13)
    guard("guard", -0.02, 0.10, -0.02, m["tan"])
    box("trigger", (0.03, 0.03, 0.09), (0.04, 0, -0.08), m["dark"], rot=(0, 0.3, 0))
    # crosse télescopique
    cyl_x("tube", 0.045, 0.045, 0.44, (-0.38, 0, 0.24), m["black"], seg=10)
    prism("stock", [(-0.44, 0.33), (-0.44, 0.14), (-0.60, 0.06), (-0.84, 0.03), (-0.84, 0.34)], 0.13, m["tan"])
    box("butt", (0.05, 0.14, 0.34), (-0.86, 0, 0.18), m["rubber"])
    return {"grip": (-0.12, 0, -0.18), "muzzle": (0.99, 0, 0.24)}


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
    # phase 8 : revolvers, fusils à pompe, mitrailleuses, lance-grenades
    "revolver_peacemaker": revolver_peacemaker, "revolver_model29": revolver_model29,
    "revolver_python": revolver_python,
    "shotgun_870": shotgun_870, "shotgun_benelli": shotgun_benelli, "shotgun_aa12": shotgun_aa12,
    "lmg_m249": lmg_m249, "lmg_pkm": lmg_pkm, "lmg_m60": lmg_m60,
    "gl_m79": gl_m79, "gl_china_lake": gl_china_lake, "gl_m32": gl_m32,
}
PHASE8 = ["revolver_peacemaker", "revolver_model29", "revolver_python", "shotgun_870", "shotgun_benelli",
          "shotgun_aa12", "lmg_m249", "lmg_pkm", "lmg_m60", "gl_m79", "gl_china_lake", "gl_m32"]
RARITY = {"pistol_p9": 0, "pistol_glock18": 2, "pistol_deagle": 3, "pistol_p320": 4,
          "smg_mp5": 0, "smg_vector": 2, "smg_p90": 3, "smg_uzi": 4,
          "rifle_ak47": 0, "rifle_m4a1": 2, "rifle_scarh": 3, "rifle_aug": 4,
          "sniper_m24": 0, "sniper_ax50": 2, "sniper_m82": 3,
          "rocket_rpg7": 2, "rocket_m202": 3, "rocket_javelin": 4,
          "gadget_frag": 0, "gadget_smoke": 2, "gadget_mine": 3, "gadget_c4": 4, "gadget_drone": 4,
          "revolver_peacemaker": 0, "revolver_model29": 2, "revolver_python": 3,
          "shotgun_870": 0, "shotgun_benelli": 2, "shotgun_aa12": 4,
          "lmg_m249": 0, "lmg_pkm": 2, "lmg_m60": 3,
          "gl_m79": 0, "gl_china_lake": 2, "gl_m32": 3}
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
    with open(os.path.join(OUT, wid + ".json"), "w", newline="\n") as f:
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


def contact_sheet(out: str, ids: list[str] | None = None) -> None:
    """Planche façon arsenal.jpg : vignettes à fond de rareté, icône + nom."""
    from PIL import Image, ImageDraw
    ids = ids or list(WEAPONS)
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
                     "rocket_launcher": "rocket_rpg7", "gadget": "gadget_frag", "revolver": "revolver_peacemaker",
                     "shotgun": "shotgun_870", "lmg": "lmg_m249", "grenade_launcher": "gl_m79"}


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
    sheet = args[args.index("--sheet") + 1] if "--sheet" in args else None
    ids = [a for a in args if a in WEAPONS]
    if "--phase8" in args:
        ids += PHASE8
    if sheet:
        contact_sheet(sheet, ids)
        return
    for wid in (ids or list(WEAPONS)):
        render_item(wid)
    write_category_fallbacks()


if __name__ == "__main__":
    main()
