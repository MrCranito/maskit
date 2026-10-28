"""Décors de la Station Orbitale Kagami en 3D « toon peint » + atlas unique (décors + décalques + lueur).

Usage (depuis la racine du projet ; voir l'ordre complet dans build_tiles.py) :
    python3 art/blender/space_station/build_props.py                  # rend tout + empaquette
    python3 art/blender/space_station/build_props.py --only console,shuttle
    python3 art/blender/space_station/build_props.py --pack           # empaqueter seulement

Sorties : assets/sprites/space_station/atlas.png + atlas_meta.gd (rect, pieds, point chaud).
Échelle : 2 px par unité monde, 1 BU = 36 unités monde, caméra orthographique plongée 48°
(identique au héros et aux décors Far West). (0, 0, 0) = point d'appui au sol, face avant vers -Y.
Les pièces temporaires vont dans $RDM_TMP/space_station/pieces.
"""
from __future__ import annotations

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ss_art import C, FP, M, Builder, TMP, ROOT, custom, hazard_band, set_pieces_dir  # noqa: E402
import bmesh  # noqa: E402

OUT_DIR = os.path.join(ROOT, "assets", "sprites", "space_station")
PIECES = os.path.join(TMP, "pieces")
DECALS = os.path.join(TMP, "decals")
CELL = 1.78


# ----------------------------------------------------------------------------- petites aides

def screen(B, name, w, h, loc, mat="screen_cyan", tilt=0.0, frame=True):
    """Écran (cadre gunmetal + dalle émissive) tourné vers -Y, incliné de `tilt` rad vers le haut."""
    x, y, z = loc
    if frame:
        B.box(name + "_f", (w + 0.08, 0.05, h + 0.08), (x, y + 0.02, z), M("gunmetal"), rot=(tilt, 0, 0))
    B.box(name, (w, 0.02, h), (x, y - 0.015, z), M(mat), rot=(tilt, 0, 0), outline=False, shadow=False)


def led_row(B, name, x0, x1, y, z, n, mats=("led_green", "led_amber", "screen_cyan")):
    rnd = random.Random(hash(name) & 0xFFFF)
    for i in range(n):
        x = x0 + (x1 - x0) * (i + 0.5) / n
        B.box("%s%d" % (name, i), (0.035, 0.02, 0.03), (x, y, z), M(rnd.choice(mats)), outline=False, shadow=False)


# ----------------------------------------------------------------------------- décors

def p_console(B: Builder) -> None:
    w = 1.5
    B.box("body", (w, 0.62, 0.62), (0, 0.05, 0.31), M("steel_dark"), bevel=0.03)
    # Pupitre incliné.
    bm = C.bm_loft([[(-w / 2, -0.28, 0.62), (w / 2, -0.28, 0.62), (w / 2, 0.36, 0.86), (-w / 2, 0.36, 0.86)],
                    [(-w / 2, -0.28, 0.68), (w / 2, -0.28, 0.68), (w / 2, 0.36, 0.92), (-w / 2, 0.36, 0.92)]])
    B.add("desk", bm, M("steel"), sharp=30)
    for i, x in enumerate((-0.45, 0.0, 0.45)):
        B.box("key%d" % i, (0.36, 0.3, 0.02), (x, 0.0, 0.78), M("screen_cyan" if i != 1 else "screen_amber"),
              rot=(-0.36, 0, 0), outline=False, shadow=False)
    B.box("mon_post", (0.08, 0.08, 0.5), (0, 0.32, 1.1), M("gunmetal"))
    screen(B, "mon", 0.9, 0.5, (0, 0.3, 1.45), "screen_cyan")
    B.box("kick", (w - 0.1, 0.05, 0.1), (0, -0.27, 0.06), M("hazard", rim=0.0))
    led_row(B, "led", -0.6, 0.6, -0.27, 0.45, 8)


def p_server_rack(B: Builder) -> None:
    w, d, h = 0.86, 0.62, 2.0
    B.box("cab", (w, d, h), (0, 0.05, h / 2), M("gunmetal"), bevel=0.03)
    B.box("door", (w - 0.12, 0.03, h - 0.2), (0, -d / 2 + 0.03, h / 2), M("steel_dark"))
    for k in range(9):
        z = 0.28 + k * 0.17
        B.box("unit%d" % k, (w - 0.22, 0.02, 0.11), (0, -d / 2 + 0.01, z), M("rubber"))
        led_row(B, "l%d" % k, -0.28, 0.12, -d / 2, z, 5)
    B.box("top", (w + 0.04, d + 0.04, 0.06), (0, 0.05, h + 0.02), M("steel"))
    hazard_band(B, "hz", w - 0.1, (0, -d / 2 - 0.005, 0.08), h=0.08, n=6)


def p_bunk_bed(B: Builder) -> None:
    w, d = 1.25, 1.7
    for sx in (-w / 2, w / 2):
        for sy in (-d / 2 + 0.05, d / 2 - 0.05):
            B.box("post%.1f%.1f" % (sx, sy), (0.07, 0.07, 1.55), (sx, sy, 0.78), M("steel"))
    for z, blanket in ((0.38, "cloth_blue"), (1.12, "cloth_grey")):
        B.box("frame%.1f" % z, (w + 0.06, d, 0.08), (0, 0, z), M("steel_dark"))
        B.box("matt%.1f" % z, (w - 0.08, d - 0.1, 0.14), (0, 0, z + 0.11), M("mattress"), bevel=0.04)
        B.box("blank%.1f" % z, (w - 0.04, d * 0.55, 0.16), (0, -d * 0.18, z + 0.13), M(blanket), bevel=0.05)
        B.box("pillow%.1f" % z, (w * 0.6, 0.3, 0.1), (0, d / 2 - 0.25, z + 0.22), M("white_panel"), bevel=0.04)
    B.box("ladder", (0.05, 0.05, 1.2), (w / 2 - 0.15, -d / 2 - 0.04, 0.6), M("steel"))
    for k in range(4):
        B.box("rung%d" % k, (0.3, 0.04, 0.03), (w / 2 - 0.3, -d / 2 - 0.04, 0.3 + k * 0.25), M("steel"))


def p_mess_table(B: Builder) -> None:
    w, d = 1.7, 0.75
    B.box("top", (w, d, 0.07), (0, 0, 0.76), M("white_panel"), bevel=0.02)
    B.box("ped", (0.2, 0.2, 0.72), (0, 0, 0.36), M("steel_dark"))
    B.box("foot", (0.8, 0.5, 0.05), (0, 0, 0.03), M("steel_dark"))
    for sy in (-d / 2 - 0.32, d / 2 + 0.32):
        B.box("bench%.1f" % sy, (w - 0.1, 0.32, 0.06), (0, sy, 0.46), M("teal"), bevel=0.02)
        for sx in (-w / 2 + 0.25, w / 2 - 0.25):
            B.box("bl%.1f%.1f" % (sx, sy), (0.06, 0.06, 0.44), (sx, sy, 0.22), M("steel_dark"))
    for i, x in enumerate((-0.55, 0.05, 0.5)):
        B.box("tray%d" % i, (0.36, 0.26, 0.03), (x, -0.12 + 0.2 * (i % 2), 0.81), M("steel"))
        B.cyl("cup%d" % i, 0.05, 0.045, 0.12, (x + 0.12, -0.05 + 0.2 * (i % 2), 0.88), M("orange"), seg=10)


def p_med_bed(B: Builder) -> None:
    w, d = 0.9, 1.75
    B.box("base", (w * 0.6, d * 0.6, 0.5), (0, 0, 0.25), M("steel_dark"))
    B.box("frame", (w, d, 0.1), (0, 0, 0.55), M("white_panel"), bevel=0.03)
    B.box("matt", (w - 0.1, d - 0.12, 0.12), (0, 0, 0.66), M("mattress"), bevel=0.04)
    bm = C.bm_box(w - 0.12, 0.6, 0.1, bevel=0.03)
    C.bm_xform(bm, loc=(0, d / 2 - 0.4, 0.86), rot=(-0.5, 0, 0))
    B.add("back", bm, M("mattress"))
    B.box("sheet", (w - 0.06, d * 0.5, 0.1), (0, -d * 0.2, 0.72), M("teal"), bevel=0.04)
    B.box("arm", (0.06, 0.06, 1.3), (w / 2 + 0.12, d / 2 - 0.2, 0.65), M("steel"))
    screen(B, "ecg", 0.42, 0.3, (w / 2 + 0.12, d / 2 - 0.26, 1.42), "screen_green")


def p_lab_bench(B: Builder) -> None:
    w, d = 1.6, 0.72
    B.box("cab", (w, d, 0.8), (0, 0.05, 0.4), M("white_panel"), bevel=0.03)
    B.box("top", (w + 0.06, d + 0.06, 0.06), (0, 0.05, 0.83), M("gunmetal"))
    for i, x in enumerate((-0.4, 0.4)):
        B.box("door%d" % i, (0.72, 0.02, 0.6), (x, -d / 2 + 0.04, 0.42), M("steel"))
    rnd = random.Random(7)
    for k, (x, y) in enumerate(((-0.6, -0.05), (-0.42, 0.12), (-0.2, -0.08), (0.45, 0.15), (0.62, -0.05))):
        liq = rnd.choice(["liquid_green", "liquid_cyan", "grow_purple"])
        B.cyl("flask%d" % k, 0.07, 0.04, 0.22, (x, y, 0.97), M("glass_dark"), seg=10)
        B.cyl("liq%d" % k, 0.065, 0.06, 0.1, (x, y, 0.92), M(liq), seg=10, outline=False)
    # Microscope.
    B.box("ms_base", (0.25, 0.2, 0.05), (0.1, 0.1, 0.89), M("rubber"))
    B.box("ms_arm", (0.05, 0.05, 0.35), (0.1, 0.17, 1.06), M("rubber"))
    B.cyl("ms_tube", 0.04, 0.035, 0.3, (0.1, 0.08, 1.15), M("steel"), rot=(0.4, 0, 0), seg=10)


def p_specimen_tank(B: Builder) -> None:
    r, h = 0.42, 1.9
    B.cyl("base", r + 0.1, r + 0.12, 0.28, (0, 0, 0.14), M("steel_dark"), seg=20)
    B.cyl("cap", r + 0.08, r + 0.04, 0.22, (0, 0, h - 0.11), M("steel_dark"), seg=20)
    B.cyl("liquid", r - 0.02, r - 0.02, h - 0.5, (0, 0, h / 2), M("liquid_green"), seg=20, outline=False)
    B.cyl("glass", r, r, h - 0.48, (0, 0, h / 2), M("glass_dark"), seg=20, shadow=False).hide_render = True
    # Silhouette sombre en suspension (spécimen masqué).
    B.sphere("spec_head", 0.13, (0, -0.08, 1.25), M("gunmetal"), scale=(1, 0.9, 1.15), outline=False)
    B.sphere("spec_mask", 0.1, (0, -0.17, 1.25), M("mask"), scale=(1, 0.5, 1.2), outline=False)
    B.sphere("spec_body", 0.18, (0, -0.05, 0.9), M("gunmetal"), scale=(1, 0.8, 1.6), outline=False)
    for k in range(3):
        a = k * 2.1
        B.box("rib%d" % k, (0.06, 0.06, h - 0.48), (math.cos(a) * r, math.sin(a) * r, h / 2), M("steel"))
    for k in range(5):
        B.sphere("bub%d" % k, 0.025, (0.1 - k * 0.04, -r + 0.05, 0.6 + k * 0.18), M("neon_white"), outline=False, shadow=False)
    B.tube("hose", [(r, 0.1, h - 0.1), (r + 0.25, 0.2, h - 0.3), (r + 0.3, 0.25, 0.3), (r + 0.1, 0.2, 0.05)],
           [0.04] * 4, M("rubber"))


def p_cargo_stack(B: Builder) -> None:
    def crate(name, sx, sy, sz, loc, mat, rot=0.0):
        B.box(name, (sx, sy, sz), loc, M(mat), rot=(0, 0, rot), bevel=0.025)
        for dz in (-sz / 2 + 0.06, sz / 2 - 0.06):
            B.box(name + "_b%.2f" % dz, (sx + 0.02, sy + 0.02, 0.05), (loc[0], loc[1], loc[2] + dz), M("steel_dark"), rot=(0, 0, rot))
        B.box(name + "_lbl", (sx * 0.4, 0.01, sz * 0.3), (loc[0] - sx * 0.15, loc[1] - sy / 2 - 0.005, loc[2]),
              M("white_panel", rim=0.0), rot=(0, 0, rot), outline=False, shadow=False)
    crate("c1", 0.8, 0.75, 0.62, (-0.38, 0.05, 0.31), "orange")
    crate("c2", 0.7, 0.7, 0.55, (0.4, 0.1, 0.28), "steel")
    crate("c3", 0.62, 0.6, 0.5, (-0.25, 0.08, 0.87), "olive", rot=0.15)
    crate("c4", 0.45, 0.45, 0.36, (0.38, 0.05, 0.74), "orange", rot=-0.2)


def p_pipe_cluster(B: Builder) -> None:
    h = 2.3
    for i, (x, r, mat) in enumerate(((-0.42, 0.13, "copper"), (-0.12, 0.1, "steel"), (0.16, 0.16, "steel_dark"), (0.46, 0.09, "copper"))):
        B.cyl("p%d" % i, r, r, h, (x, 0.2, h / 2), M(mat), seg=14)
        for z in (0.35, 1.2, 2.0):
            B.cyl("cl%d%.1f" % (i, z), r + 0.03, r + 0.03, 0.07, (x, 0.2, z), M("gunmetal"), seg=14)
    B.cyl("valve_stem", 0.03, 0.03, 0.18, (0.16, 0.0, 1.0), M("steel"), rot=(math.pi / 2, 0, 0), seg=6)
    B.torus("valve", 0.14, 0.025, (0.16, -0.09, 1.0), M("red"), rot=(math.pi / 2, 0, 0), seg=18, rseg=5)
    B.cyl("gauge", 0.09, 0.09, 0.05, (-0.12, 0.08, 1.45), M("white_panel"), rot=(math.pi / 2, 0, 0), seg=14)
    B.box("base", (1.3, 0.5, 0.1), (0.02, 0.2, 0.05), M("gunmetal"))


def p_reactor_core(B: Builder) -> None:
    B.cyl("plinth", 1.45, 1.55, 0.25, (0, 0, 0.12), M("gunmetal"), seg=32)
    B.cyl("plinth2", 1.15, 1.2, 0.2, (0, 0, 0.35), M("steel_dark"), seg=32)
    hazard = [(math.cos(a) * 1.5, math.sin(a) * 1.5) for a in [i * math.pi / 8 for i in range(16)]]
    for k, (x, y) in enumerate(hazard):
        if y < 0.4:
            B.box("hz%d" % k, (0.3, 0.06, 0.08), (x, y - 0.02, 0.2), M("hazard" if k % 2 else "rubber", rim=0.0),
                  rot=(0, 0, math.atan2(y, x) + math.pi / 2), outline=False, shadow=False)
    B.cyl("core", 0.5, 0.5, 2.6, (0, 0, 1.75), M("core_cyan"), seg=24, outline=False)
    for z in (0.75, 1.45, 2.15, 2.85):
        B.torus("clamp%.1f" % z, 0.6, 0.09, (0, 0, z), M("steel"), seg=28, rseg=8)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        B.box("strut%d" % k, (0.14, 0.14, 2.7), (math.cos(a) * 0.7, math.sin(a) * 0.7, 1.75), M("steel_dark"))
    B.cyl("cap", 0.75, 0.55, 0.35, (0, 0, 3.2), M("gunmetal"), seg=24)
    B.cyl("cap2", 0.35, 0.3, 0.2, (0, 0, 3.45), M("steel"), seg=20)
    for k in range(5):
        a = -0.4 - k * 0.55
        B.tube("cable%d" % k, [(math.cos(a) * 0.75, math.sin(a) * 0.75 + 0.2, 3.1), (math.cos(a) * 1.3, math.sin(a) * 1.3 + 0.3, 2.4),
                               (math.cos(a) * 1.45, math.sin(a) * 1.45 + 0.2, 0.5)], [0.06, 0.06, 0.06], M("rubber"))


def p_holo_table(B: Builder) -> None:
    B.cyl("ped", 0.25, 0.4, 0.75, (0, 0, 0.37), M("gunmetal"), seg=20)
    B.cyl("top", 0.7, 0.65, 0.12, (0, 0, 0.8), M("steel"), seg=28)
    B.torus("rim", 0.66, 0.035, (0, 0, 0.86), M("screen_cyan"), seg=28, rseg=5, outline=False)
    B.cyl("emitter", 0.3, 0.3, 0.03, (0, 0, 0.88), M("holo"), seg=20, outline=False, shadow=False)
    # Hologramme : planète filaire + anneau, sans contour ni ombre.
    B.sphere("holo_planet", 0.32, (0, 0, 1.4), M("holo"), seg=16, rings=10, outline=False, shadow=False)
    B.torus("holo_ring", 0.5, 0.015, (0, 0, 1.4), M("neon_white"), rot=(0.4, 0.2, 0), seg=28, rseg=4, outline=False, shadow=False)
    B.cyl("beam", 0.3, 0.05, 0.25, (0, 0, 1.0), M("holo"), seg=16, outline=False, shadow=False)
    for ob in B.objs:
        if ob.name.startswith(("holo_planet", "beam")):
            ob.display_type = "WIRE"


def p_captain_chair(B: Builder) -> None:
    B.cyl("ped", 0.12, 0.3, 0.45, (0, 0, 0.22), M("gunmetal"), seg=14)
    B.box("seat", (0.75, 0.7, 0.16), (0, 0, 0.5), M("navy"), bevel=0.05)
    bm = C.bm_box(0.75, 0.16, 0.95, bevel=0.06)
    C.bm_xform(bm, loc=(0, 0.33, 1.0), rot=(-0.15, 0, 0))
    B.add("back", bm, M("navy"))
    B.box("head", (0.5, 0.14, 0.22), (0, 0.38, 1.5), M("steel_dark"), bevel=0.04)
    for sx in (-1, 1):
        B.box("arm%d" % sx, (0.14, 0.62, 0.12), (sx * 0.44, 0.0, 0.72), M("steel_dark"), bevel=0.03)
        B.box("pad%d" % sx, (0.12, 0.3, 0.02), (sx * 0.44, -0.12, 0.79), M("screen_amber" if sx < 0 else "screen_cyan"),
              outline=False, shadow=False)
    B.box("trim", (0.77, 0.02, 0.04), (0, -0.36, 0.55), M("brass"))


def p_weapon_rack(B: Builder) -> None:
    w, h = 1.4, 1.7
    B.box("back", (w, 0.12, h), (0, 0.25, h / 2), M("gunmetal"), bevel=0.02)
    B.box("shelf", (w, 0.35, 0.06), (0, 0.12, 0.35), M("steel_dark"))
    for i, x in enumerate((-0.45, 0.0, 0.45)):
        z0 = 0.42
        B.box("stock%d" % i, (0.1, 0.08, 0.35), (x, 0.12, z0 + 0.17), M("rubber"))
        B.box("body%d" % i, (0.13, 0.1, 0.6), (x, 0.12, z0 + 0.65), M("steel_dark"), bevel=0.02)
        B.cyl("barrel%d" % i, 0.025, 0.025, 0.45, (x, 0.1, z0 + 1.15), M("steel"), seg=8)
        B.box("cell%d" % i, (0.06, 0.02, 0.18), (x, 0.06, z0 + 0.6), M("plasma"), outline=False, shadow=False)
    B.box("sign", (0.5, 0.02, 0.12), (0, 0.18, h - 0.12), M("hazard", rim=0.0))
    B.box("lock", (0.12, 0.04, 0.12), (w / 2 - 0.12, 0.18, h / 2), M("alarm_red"), outline=False)


def p_plant_bed(B: Builder) -> None:
    w, d = 1.3, 0.7
    B.box("tray", (w, d, 0.45), (0, 0, 0.22), M("white_panel"), bevel=0.03)
    B.box("soil", (w - 0.1, d - 0.1, 0.05), (0, 0, 0.45), M("soil"))
    rnd = random.Random(5)
    for k in range(10):
        x, y = -w / 2 + 0.15 + (k % 5) * (w - 0.3) / 4, (-0.16 if k < 5 else 0.16)
        hgt = rnd.uniform(0.2, 0.4)
        B.sphere("leaf%d" % k, rnd.uniform(0.12, 0.17), (x, y, 0.5 + hgt * 0.6), M("plant" if k % 3 else "plant_dark"),
                 scale=(1.1, 1.0, 0.9), seg=9, rings=6)
    for sx in (-w / 2 + 0.05, w / 2 - 0.05):
        B.box("post%.1f" % sx, (0.05, 0.05, 1.3), (sx, 0.3, 0.65), M("steel"))
    B.box("lamp", (w, 0.18, 0.06), (0, 0.15, 1.3), M("gunmetal"))
    B.box("lamp_e", (w - 0.1, 0.12, 0.02), (0, 0.15, 1.265), M("grow_purple"), outline=False, shadow=False)


def p_vending_machine(B: Builder) -> None:
    w, d, h = 0.95, 0.7, 1.95
    B.box("body", (w, d, h), (0, 0.05, h / 2), M("red"), bevel=0.04)
    B.box("glass", (w * 0.62, 0.03, h * 0.6), (-0.13, -d / 2 + 0.03, h * 0.58), M("screen_cyan"), outline=False)
    for r in range(4):
        for c in range(3):
            B.box("item%d%d" % (r, c), (0.12, 0.02, 0.1), (-0.3 + c * 0.17, -d / 2 + 0.01, 0.75 + r * 0.25),
                  M(["orange", "plant", "hazard"][(r + c) % 3], rim=0.0), outline=False, shadow=False)
    B.box("panel", (0.2, 0.03, 0.5), (w / 2 - 0.16, -d / 2 + 0.03, 1.2), M("gunmetal"))
    B.box("pad", (0.12, 0.02, 0.1), (w / 2 - 0.16, -d / 2 + 0.01, 1.3), M("led_green"), outline=False)
    B.box("slot", (0.5, 0.03, 0.18), (-0.1, -d / 2 + 0.03, 0.3), M("rubber"))
    B.box("logo", (w - 0.2, 0.02, 0.18), (0, -d / 2 + 0.02, h - 0.18), M("neon_white"), outline=False)


def p_coolant_tank(B: Builder) -> None:
    r, h = 0.48, 1.6
    B.cyl("body", r, r, h, (0, 0.05, h / 2 + 0.1), M("white_panel"), seg=22)
    B.sphere("dome", r, (0, 0.05, h + 0.1), M("white_panel"), scale=(1, 1, 0.45), seg=22, rings=8)
    for z in (0.35, h - 0.1):
        B.torus("band%.1f" % z, r + 0.01, 0.04, (0, 0.05, z), M("hazard"), seg=24, rseg=5)
    B.cyl("feet", r * 0.8, r * 0.9, 0.12, (0, 0.05, 0.06), M("gunmetal"), seg=18)
    B.cyl("gauge", 0.1, 0.1, 0.04, (0.18, -r + 0.06, 1.0), M("screen_cyan"), rot=(math.pi / 2, 0, 0), seg=14, outline=False)
    B.box("label", (0.3, 0.02, 0.12), (-0.15, -r + 0.03, 0.75), M("teal", rim=0.0), rot=(0, 0, 0.3), outline=False)
    B.tube("pipe", [(r, 0.05, 1.3), (r + 0.25, 0.1, 1.3), (r + 0.3, 0.2, 0.2), (r + 0.3, 0.3, 0.02)], [0.06] * 4, M("copper"))


def p_power_node(B: Builder) -> None:
    w, d, h = 1.1, 0.8, 1.15
    B.box("body", (w, d, h), (0, 0.05, h / 2), M("steel_dark"), bevel=0.04)
    B.box("fins", (w + 0.04, d - 0.2, 0.4), (0, 0.05, 0.35), M("gunmetal"))
    for i in range(6):
        B.box("fin%d" % i, (w + 0.06, 0.03, 0.36), (0, -d / 2 + 0.12 + i * 0.1, 0.35), M("steel"))
    for i, x in enumerate((-0.3, 0.3)):
        B.cyl("coil%d" % i, 0.16, 0.16, 0.5, (x, 0.05, h + 0.25), M("copper"), seg=16)
        B.cyl("glow%d" % i, 0.11, 0.11, 0.52, (x, 0.05, h + 0.25), M("plasma" if i == 0 else "core_cyan"), seg=12, outline=False)
        B.cyl("cap%d" % i, 0.19, 0.19, 0.06, (x, 0.05, h + 0.52), M("gunmetal"), seg=16)
    hazard_band(B, "hz", w - 0.1, (0, -d / 2 + 0.03, 0.85), h=0.12, n=8)
    led_row(B, "led", -0.35, 0.35, -d / 2 + 0.03, 1.0, 6, ("led_amber", "alarm_red"))


def p_escape_pod(B: Builder) -> None:
    r, h = 0.62, 1.9
    secs = []
    for i in range(12):
        t = i / 11
        z = 0.15 + t * h
        rr = r * math.sin(math.pi * (0.12 + 0.76 * t)) ** 0.6
        secs.append(C.ellipse(0, 0.15, z, rr, rr * 0.92, n=22))
    bm = C.bm_loft(secs)
    B.add("hull", bm, M("white_panel"), sharp=80)
    B.cyl("base", r * 0.95, r * 1.05, 0.18, (0, 0.15, 0.09), M("gunmetal"), seg=22)
    B.sphere("window", 0.24, (0, -0.33, 1.32), M("glass_dark"), scale=(1, 0.4, 1.1), seg=14)
    B.sphere("glint", 0.07, (-0.07, -0.42, 1.42), M("neon_white"), scale=(1, 0.5, 1.4), outline=False, shadow=False)
    for z in (0.65, 1.75):
        B.torus("stripe%.1f" % z, r * 0.92 if z < 1 else r * 0.62, 0.035, (0, 0.15, z), M("orange"), seg=24, rseg=5)
    B.box("hatch", (0.42, 0.04, 0.55), (0, -0.44, 0.75), M("steel"), bevel=0.03)
    B.box("hatch_l", (0.1, 0.02, 0.08), (0.12, -0.47, 0.95), M("led_green"), outline=False)
    B.box("clamp", (0.16, 0.5, 0.16), (0, 0.65, 1.2), M("gunmetal"))


def p_floor_cables(B: Builder) -> None:
    rnd = random.Random(11)
    L = CELL
    for k, mat in enumerate(("rubber", "red", "cloth_blue", "rubber")):
        pts = []
        for i in range(9):
            x = -L / 2 + L * i / 8
            y = (k - 1.5) * 0.12 + math.sin(i * 0.9 + k * 1.3) * 0.18 + rnd.uniform(-0.03, 0.03)
            pts.append((x, y, 0.035))
        B.tube("cable%d" % k, pts, [0.035] * 9, M(mat), seg=6, shadow=False)
    B.box("junction", (0.3, 0.22, 0.1), (0.2, 0.0, 0.05), M("gunmetal"), shadow=False)


def p_warning_beacon(B: Builder) -> None:
    B.cyl("base", 0.22, 0.26, 0.1, (0, 0, 0.05), M("gunmetal"), seg=14)
    B.cyl("pole", 0.05, 0.05, 1.2, (0, 0, 0.65), M("hazard"), seg=10)
    for z in (0.35, 0.75):
        B.cyl("blk%.1f" % z, 0.052, 0.052, 0.12, (0, 0, z), M("rubber"), seg=10)
    B.cyl("cage", 0.14, 0.14, 0.28, (0, 0, 1.38), M("alarm_red"), seg=14, outline=False)
    B.cyl("lid", 0.16, 0.12, 0.06, (0, 0, 1.55), M("gunmetal"), seg=14)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        B.box("bar%d" % k, (0.02, 0.02, 0.3), (math.cos(a) * 0.15, math.sin(a) * 0.15, 1.38), M("gunmetal"))


def p_shuttle(B: Builder) -> None:
    """Navette de liaison posée sur patins dans le hangar (nez vers l'ouest)."""
    L, Wd = 4.6, 2.0
    secs = []
    prof = [(-2.3, 0.15, 0.25), (-1.9, 0.55, 0.55), (-1.2, 0.85, 0.75), (0.0, 0.95, 0.85), (1.3, 0.92, 0.8), (2.2, 0.75, 0.62), (2.4, 0.6, 0.5)]
    for x, hw, hh in prof:
        sec = []
        for k in range(16):
            a = 2 * math.pi * k / 16
            sec.append((x, math.cos(a) * hw, 1.15 + math.sin(a) * hh * (1.0 if math.sin(a) > 0 else 0.7)))
        secs.append(sec)
    bm = C.bm_loft(secs)
    B.add("hull", bm, custom("shuttle_hull", "#a8b2c2"), sharp=70)
    # Verrière.
    B.sphere("canopy", 0.6, (-1.25, 0.0, 1.62), M("glass_dark"), scale=(1.3, 0.85, 0.5), seg=18, rings=8)
    B.sphere("canopy_glint", 0.18, (-1.45, -0.25, 1.86), M("neon_white"), scale=(1.6, 0.6, 0.4), outline=False, shadow=False)
    # Bandes et immatriculation.
    for x in (-0.4, 0.9):
        bm2 = C.bm_box(0.18, 1.98, 1.4)
        C.bm_xform(bm2, loc=(x, 0, 1.2))
    B.box("stripe", (2.4, 0.02, 0.12), (0.4, -0.9, 1.25), M("orange", rim=0.0), outline=False, shadow=False)
    B.box("stripe2", (2.0, 0.02, 0.05), (0.5, -0.91, 1.08), M("navy", rim=0.0), outline=False, shadow=False)
    # Ailes et réacteurs.
    for sy in (-1, 1):
        bm3 = C.bm_loft([[(0.2, sy * 0.8, 0.9), (1.6, sy * 0.8, 0.9), (1.6, sy * 0.8, 1.0), (0.2, sy * 0.8, 1.0)],
                         [(1.1, sy * 1.7, 0.75), (1.8, sy * 1.7, 0.75), (1.8, sy * 1.7, 0.82), (1.1, sy * 1.7, 0.82)]])
        B.add("wing%d" % sy, bm3, M("steel"), sharp=30)
        B.cyl("eng%d" % sy, 0.3, 0.26, 0.9, (2.35, sy * 0.55, 1.0), M("steel_dark"), rot=(0, math.pi / 2, 0), seg=16)
        B.cyl("engglow%d" % sy, 0.2, 0.2, 0.05, (2.82, sy * 0.55, 1.0), M("core_blue"), rot=(0, math.pi / 2, 0), seg=14, outline=False)
    B.box("fin", (0.9, 0.08, 0.7), (1.9, 0.0, 1.95), M("steel"), rot=(0, -0.35, 0))
    # Patins.
    for sx in (-1.2, 1.3):
        for sy in (-0.65, 0.65):
            B.box("leg%.1f%.1f" % (sx, sy), (0.1, 0.1, 0.6), (sx, sy, 0.35), M("gunmetal"))
        B.box("skid%.1f" % sx, (0.5, 1.6, 0.08), (sx, 0, 0.04), M("steel_dark"))
    B.box("ramp", (0.9, 0.9, 0.06), (0.4, -1.25, 0.3), M("steel"), rot=(0.55, 0, 0))
    B.box("door", (0.85, 0.04, 0.7), (0.4, -0.94, 1.05), M("gunmetal"))
    led_row(B, "nav", -2.0, -1.8, -0.5, 1.0, 1, ("alarm_red",))
    led_row(B, "nav2", 1.9, 2.1, -0.75, 0.95, 1, ("led_green",))
    for ob in B.objs:  # navette à l'échelle du hangar (empreinte 4 × 3 cases)
        ob.scale = (1.55, 1.55, 1.55)


def p_workbench(B: Builder) -> None:
    w, d = 1.6, 0.75
    B.box("top", (w, d, 0.08), (0, 0.05, 0.86), M("steel_dark"), bevel=0.02)
    for sx in (-w / 2 + 0.08, w / 2 - 0.08):
        for sy in (-d / 2 + 0.1, d / 2):
            B.box("leg%.1f%.1f" % (sx, sy), (0.07, 0.07, 0.84), (sx, sy, 0.42), M("gunmetal"))
    B.box("shelf", (w - 0.1, d - 0.1, 0.04), (0, 0.05, 0.25), M("steel"))
    B.box("panel", (w, 0.05, 0.9), (0, d / 2 + 0.05, 1.35), M("steel"))
    for i in range(5):
        B.box("tool%d" % i, (0.05, 0.02, 0.3 - 0.03 * i), (-0.55 + i * 0.25, d / 2 + 0.02, 1.4), M(["red", "hazard", "steel_dark", "orange", "teal"][i]))
    B.box("vise", (0.25, 0.2, 0.15), (0.55, -0.05, 0.98), M("navy"))
    B.box("box", (0.4, 0.28, 0.22), (-0.45, 0.0, 1.0), M("red"), bevel=0.02)
    B.box("lamp_arm", (0.04, 0.04, 0.6), (0.2, d / 2 - 0.05, 1.2), M("gunmetal"), rot=(0.5, 0, 0))
    B.cyl("lamp", 0.12, 0.06, 0.12, (0.2, 0.05, 1.45), M("gunmetal"), seg=12, rot=(0.6, 0, 0))
    B.cyl("bulb", 0.09, 0.09, 0.02, (0.2, 0.0, 1.4), M("screen_amber"), seg=12, rot=(0.6, 0, 0), outline=False)


def p_fuel_drums(B: Builder) -> None:
    for i, (x, y, mat) in enumerate(((-0.33, 0.12, "hazard"), (0.32, 0.18, "red"), (0.0, -0.22, "hazard"))):
        r, h = 0.3, 0.95
        B.cyl("drum%d" % i, r, r, h, (x, y, h / 2), M(mat), seg=18)
        for z in (0.2, 0.5, 0.8):
            B.torus("rib%d%.1f" % (i, z), r + 0.005, 0.02, (x, y, z), M("steel_dark"), seg=20, rseg=4)
        B.cyl("lid%d" % i, r * 0.92, r * 0.92, 0.02, (x, y, h + 0.005), M("steel_dark"), seg=18)
        B.box("lbl%d" % i, (0.22, 0.01, 0.16), (x, y - r - 0.003, 0.55), M("rubber", rim=0.0), outline=False, shadow=False)


PROPS = {
    "console": p_console, "server_rack": p_server_rack, "bunk_bed": p_bunk_bed, "mess_table": p_mess_table,
    "med_bed": p_med_bed, "lab_bench": p_lab_bench, "specimen_tank": p_specimen_tank, "cargo_stack": p_cargo_stack,
    "pipe_cluster": p_pipe_cluster, "reactor_core": p_reactor_core, "holo_table": p_holo_table,
    "captain_chair": p_captain_chair, "weapon_rack": p_weapon_rack, "plant_bed": p_plant_bed,
    "vending_machine": p_vending_machine, "coolant_tank": p_coolant_tank, "power_node": p_power_node,
    "escape_pod": p_escape_pod, "floor_cables": p_floor_cables, "warning_beacon": p_warning_beacon,
    "shuttle": p_shuttle, "workbench": p_workbench, "fuel_drums": p_fuel_drums,
}
FLAT = {"floor_cables"}
# Cadre (unités monde) et hauteur visée (BU).
FRAMES = {
    "console": ((140, 130), 0.8), "server_rack": ((90, 150), 1.0), "bunk_bed": ((120, 150), 0.8),
    "mess_table": ((150, 120), 0.5), "med_bed": ((110, 140), 0.7), "lab_bench": ((140, 120), 0.7),
    "specimen_tank": ((90, 150), 1.0), "cargo_stack": ((120, 110), 0.6), "pipe_cluster": ((120, 160), 1.2),
    "reactor_core": ((240, 300), 1.8), "holo_table": ((120, 130), 0.9), "captain_chair": ((90, 110), 0.8),
    "weapon_rack": ((130, 130), 0.9), "plant_bed": ((130, 120), 0.6), "vending_machine": ((100, 150), 1.0),
    "coolant_tank": ((100, 140), 0.9), "power_node": ((110, 130), 0.8), "escape_pod": ((100, 150), 1.0),
    "floor_cables": ((72, 72), 0.0), "warning_beacon": ((60, 100), 0.8), "shuttle": ((480, 380), 1.5),
    "workbench": ((140, 120), 0.8), "fuel_drums": ((110, 100), 0.5),
}
# Points chauds (lueur additive) en coordonnées BU depuis le point d'appui.
GLOW = {
    "console": (0.0, 0.3, 1.45), "server_rack": (0.0, -0.3, 1.0), "specimen_tank": (0.0, 0.0, 1.0),
    "holo_table": (0.0, 0.0, 1.3), "vending_machine": (0.0, -0.3, 1.2), "power_node": (0.0, 0.05, 1.4),
    "warning_beacon": (0.0, 0.0, 1.38), "reactor_core": (0.0, 0.0, 1.8), "plant_bed": (0.0, 0.15, 1.2),
    "workbench": (0.2, 0.0, 1.35), "escape_pod": (0.0, -0.4, 1.3), "lab_bench": (0.0, 0.0, 1.0),
    "med_bed": (0.5, 0.6, 1.4), "weapon_rack": (0.0, 0.1, 1.0), "coolant_tank": (0.18, -0.45, 1.0),
    "shuttle": (4.3, 0.0, 1.55),
}


def render_props(only: list[str] | None = None) -> None:
    set_pieces_dir(PIECES)
    for k, fn in PROPS.items():
        if only and k not in only:
            continue
        fr, tz = FRAMES[k]
        FP.render_piece("prop_" + k, fn, fr, target_z=tz, flat=k in FLAT, glow=GLOW.get(k),
                        outline_px=4.5 if k not in ("shuttle", "reactor_core") else 5.5)


def pack(atlas_w: int = 2048) -> None:
    """Empaquette décors + décalques + lueur dans assets/sprites/space_station/atlas.png."""
    import json
    from PIL import Image
    items = []
    for fn in sorted(os.listdir(PIECES)):
        if fn.endswith(".png") and not fn.endswith(".big.png"):
            name = fn[:-4]
            info = {}
            jp = os.path.join(PIECES, name + ".json")
            if os.path.exists(jp):
                with open(jp) as f:
                    info = json.load(f)
            items.append((name, Image.open(os.path.join(PIECES, fn)).convert("RGBA"), info))
    if os.path.isdir(DECALS):
        for fn in sorted(os.listdir(DECALS)):
            if fn.endswith(".png"):
                im = Image.open(os.path.join(DECALS, fn)).convert("RGBA")
                items.append(("decal_" + fn[:-4], im, {"feet": [im.width / 2, im.height / 2]}))
    items.append(("glow", FP._glow_sprite(128), {"feet": [64, 64]}))
    items.append(("white", Image.new("RGBA", (8, 8), (255, 255, 255, 255)), {"feet": [4, 4], "inset": 2}))
    items.sort(key=lambda t: -t[1].height)
    pad = 2
    x = y = shelf = 0
    pos = {}
    for name, im, _ in items:
        if x + im.width + pad > atlas_w:
            x = 0
            y += shelf + pad
            shelf = 0
        pos[name] = (x, y)
        x += im.width + pad
        shelf = max(shelf, im.height)
    h = y + shelf
    H = 1
    while H < h:
        H *= 2
    atlas = Image.new("RGBA", (atlas_w, H), (0, 0, 0, 0))
    meta = {}
    for name, im, info in items:
        px, py = pos[name]
        atlas.paste(im, (px, py))
        ins = info.get("inset", 0)
        e = {"rect": [px + ins, py + ins, im.width - 2 * ins, im.height - 2 * ins],
             "feet": [round(info.get("feet", [0, 0])[0], 1), round(info.get("feet", [0, 0])[1], 1)]}
        if "glow" in info:
            e["glow"] = info["glow"]
        meta[name] = e
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, "atlas.png")
    atlas.save(out, optimize=True)
    with open(os.path.join(OUT_DIR, "atlas_meta.gd"), "w") as f:
        f.write("## Généré par art/blender/space_station/build_props.py : NE PAS ÉDITER.\n")
        f.write("## Pièces de assets/sprites/space_station/atlas.png : rect [x, y, w, h] (px), feet [x, y]\n")
        f.write("## (point d'appui au sol, px depuis le coin du rect), glow (point chaud). 2 px = 1 unité monde.\n")
        f.write("const PIECES := %s\n" % json.dumps(meta))
    print("ATLAS", out, atlas.size, len(items), "pièces")


def main() -> None:
    args = sys.argv[1:]
    if "--pack" not in args:
        only = args[args.index("--only") + 1].split(",") if "--only" in args else None
        render_props(only)
    pack()


if __name__ == "__main__":
    main()
