"""Briques et matériaux communs des armes HD (weapons_hd.py et ses familles weapons_hd_*.py).

Repère : X = canon (vers la droite), Z = haut, Y = profondeur (côté visible = -Y, caméra quasi de
profil, légère plongée). Unités Blender : un fusil fait ~2,6 unités, un pistolet ~1 ; la taille en jeu
découle de ces unités (88 px par unité, échelle 0.225), donc garder les proportions des modèles
d'origine (art/blender/build_weapons.py). Chaque fonction de modèle reçoit m = mats() et renvoie
{"grip": (x, y, z), "muzzle": (x, y, z)} : point de prise (main) et bout du canon.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import weapon_paint as WP  # noqa: E402
import build_weapons as BW  # noqa: E402

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
        # Rare : acier patiné, bronze
        "gunmetal": P("gunmetal", "#5a5e68", "#181a2a", "#a0a6b4", metal=0.6, wear=0.5, grain=0.05,
                      alt="#7e828c", alt_scale=26.0, alt_cut=0.66),
        "bronze": P("bronze", "#8a6a44", "#2e2020", "#c49a64", metal=0.8, wear=0.35),
        # Épique : gravures argent / or, beige, olive, marine
        "silver": P("silver", "#c2c5cd", "#4a4c64", "#ffffff", metal=0.9, wear=0.3, grain=0.03),
        "engraved": P("engraved", "#bab6aa", "#4a4a5e", "#f6f2e6", metal=0.8, wear=0.3, alt="#c89a48",
                      alt_scale=16.0, alt_cut=0.6),
        "tan": P("tan", "#b09a74", "#463a36", "#dcc8a0", wear=0.35, grain=0.06),
        "olive": P("olive", "#5e6444", "#20241e", "#8a9064", wear=0.35, grain=0.06),
        "olive_dark": P("olive_dark", "#3e4430", "#121612", "#626a4c", wear=0.3, grain=0.08),
        "navy": P("navy", "#262c40", "#0a0c1a", "#4c5674", wear=0.35, grain=0.05),
        # divers (lanceurs, gadgets, optiques)
        "red": P("red", "#b0282a", "#40101c", "#e8584a", gloss=0.3, wear=0.25),
        "orange": P("orange", "#c86a2a", "#4e2218", "#f4a058", gloss=0.25, wear=0.25),
        "khaki": P("khaki", "#8a8058", "#34302a", "#b8ac7e", grain=0.12, grain_scale=90.0),
        "canvas": P("canvas", "#6e6a4c", "#26241c", "#9a946c", grain=0.2, grain_scale=200.0, rim=0.15),
        "cream": P("cream", "#d8d2bc", "#7e7a8a", "#fffaea", wear=0.2),
        "putty": P("putty", "#c8b48a", "#5a4c44", "#ecdcb0", grain=0.1),
        "led": P("led", "#ff3a2a", emit=1.6),
        "led_b": P("led_b", "#48c8ff", emit=1.6),
        "led_g": P("led_g", "#5aff7a", emit=1.6),
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
