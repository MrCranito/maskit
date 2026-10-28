"""Décors de la station sous-marine « Abysse Nérée » en 3D « toon peint » + atlas unique.

Même pipeline et même angle que le héros et les décors Far West (art/blender/build_props.py :
caméra orthographique plongée 48°, matériaux toon, contour Freestyle, ombre portée composée).

Usage (depuis la racine du projet ; ordre complet de régénération du biome) :
    python3 art/blender/underwater/uw_tiles.py       # sols, murs, décalques (numpy)
    python3 art/blender/underwater/uw_props.py       # décors + kit + empaquetage de l'atlas
    python3 art/blender/underwater/uw_props.py --only console,pump   # re-rendre quelques pièces
    python3 art/blender/underwater/uw_props.py --pack                # empaqueter seulement
    python3 art/blender/underwater/uw_containers.py  # conteneurs + cachettes
    python3 art/blender/underwater/uw_enemies.py     # ennemis + scripts/biomes/underwater/enemy_kinds.gd
    python3 art/blender/underwater/build_icons.py    # icônes d'objets (SVG)

Sorties : assets/sprites/underwater/atlas.png (+ atlas_meta.gd : rect, pieds, point chaud).
Échelle : 2 px par unité monde ; 1 BU Blender = 36 unités monde. Le point (0, 0, 0) de chaque
pièce = point d'appui au sol ; face avant vers -Y (caméra).
"""
from __future__ import annotations

import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..")))
import rdm_common as C  # noqa: E402
import build_props as BP  # noqa: E402
import bpy  # noqa: E402,F401

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "underwater")
TMP = os.environ.get("RDM_TMP", "/tmp/rdm_uw")
PIECES = os.path.join(TMP, "pieces")
DECALS = os.path.join(TMP, "uw_tiles", "decals")
BP.PIECES = PIECES
Builder = BP.Builder

# ----------------------------------------------------------------------------- matériaux
UW_PAL = {
    "uw_steel": ("#7e909a", "#2a3448", "#bccdd2"),
    "uw_steel_dark": ("#4c5866", "#18202f", "#7c8c98"),
    "uw_steel_light": ("#a8b8bc", "#4a5668", "#e2eef0"),
    "uw_yellow": ("#e2b232", "#6a4a34", "#ffe286"),
    "uw_red": ("#c23c30", "#4a1428", "#f2644c"),
    "uw_teal": ("#2c8c8a", "#12304a", "#56c4bc"),
    "uw_orange": ("#e07a2e", "#5a2a26", "#ffae5a"),
    "uw_white": ("#dfe8e6", "#7a8aa0", "#ffffff"),
    "uw_rubber": ("#2c3038", "#101420", "#4c5260"),
    "uw_blue_cloth": ("#3c5c8c", "#18223e", "#6488c0"),
    "uw_canvas": ("#b89a6a", "#4e4458", "#e0c890"),
    "uw_copper": ("#c4743c", "#4e2a2c", "#f0a060"),
    "uw_coral_pink": ("#e8686e", "#5a2440", "#ff9a90"),
    "uw_coral_orange": ("#f09048", "#6a3434", "#ffc070"),
    "uw_coral_purple": ("#a85ab4", "#3a1a4a", "#d890e0"),
    "uw_kelp": ("#3c8c4c", "#12303a", "#6cc474"),
    "uw_rock": ("#6a7478", "#262c40", "#9aa6a6"),
    "uw_bone": ("#e8dcc4", "#7a7a94", "#fffaf0"),
    "uw_wood": ("#9a7048", "#3e2a30", "#c8985e"),
    "uw_paper": ("#e6dcbc", "#8a8494", "#fff6dc"),
}
BP.PAL.update(UW_PAL)
EMIT = {
    "uw_screen": ("#5af0e0", 1.35), "uw_lamp": ("#ffb454", 1.7), "uw_alarm": ("#ff3a26", 1.7),
    "uw_aqua": ("#3ab8c8", 1.0), "uw_specimen": ("#6cff96", 1.15), "uw_led_g": ("#6aff7a", 1.8),
    "uw_led_r": ("#ff4a3a", 1.8), "uw_grow": ("#d07aff", 1.4), "uw_pool": ("#2a9cb0", 0.95),
    "uw_beacon": ("#5affb0", 1.8), "uw_hole": ("#06121c", 1.0),
}


def M(key: str, rim: float = 0.28):
    if key in EMIT:
        col, k = EMIT[key]
        return C.toon(key, col, emit=k)
    return BP.M(key, rim)


def hazard_ring(B: Builder, name: str, R: float, z: float, n: int = 16, w: float = 0.12, loc=(0, 0)) -> None:
    """Anneau de bandes jaunes et noires au sol (segments alternés)."""
    for k in range(n):
        a0 = 2 * math.pi * k / n
        a1 = 2 * math.pi * (k + 1) / n
        pts = []
        for t in range(5):
            a = a0 + (a1 - a0) * t / 4
            pts.append((loc[0] + math.cos(a) * R, loc[1] + math.sin(a) * R, z))
        B.tube("%s%d" % (name, k), pts, [w] * 5, M("uw_yellow" if k % 2 else "uw_rubber"), seg=4, shadow=False)


# ----------------------------------------------------------------------------- décors

def p_moon_pool(B: Builder) -> None:
    """Bassin d'amarrage (3 x 2 cases) : margelle d'acier, eau lumineuse, mini-sous-marin jaune."""
    # Profondeur 4,2 BU : en plongée 48° (x0,74) le bassin couvre bien ses 2 cases à l'écran.
    w, d = 5.0, 4.2
    y0 = -0.4 + d / 2
    lip = 0.32
    B.box("rim_f", (w, lip, 0.28), (0, y0 - d / 2 + lip / 2, 0.14), M("uw_steel"), bevel=0.03)
    B.box("rim_b", (w, lip, 0.28), (0, y0 + d / 2 - lip / 2, 0.14), M("uw_steel"), bevel=0.03)
    B.box("rim_l", (lip, d, 0.28), (-w / 2 + lip / 2, y0, 0.14), M("uw_steel"), bevel=0.03)
    B.box("rim_r", (lip, d, 0.28), (w / 2 - lip / 2, y0, 0.14), M("uw_steel"), bevel=0.03)
    for k in range(12):
        x = -w / 2 + 0.2 + k * (w - 0.4) / 11
        B.box("hz%d" % k, (0.18, 0.06, 0.06), (x, y0 - d / 2 + 0.05, 0.27), M("uw_yellow" if k % 2 else "uw_rubber"), outline=False, shadow=False)
    B.box("water", (w - 2 * lip, d - 2 * lip, 0.06), (0, y0, 0.08), M("uw_pool"), shadow=False)
    # Mini-sous-marin jaune à quai (à moitié immergé).
    sub = C.bm_loft([C.ellipse(0, 0, x, r * 0.85, r, 16) for x, r in
                     ((-1.55, 0.06), (-1.35, 0.36), (-0.6, 0.55), (0.5, 0.55), (1.2, 0.42), (1.6, 0.1))])
    C.bm_xform(sub, loc=(0, y0 + 0.1, 0.15), rot=(0, math.pi / 2, 0))
    B.add("sub_hull", sub, M("uw_yellow"), sharp=80)
    B.cyl("sub_tower", 0.28, 0.24, 0.42, (0.15, y0 + 0.1, 0.62), M("uw_yellow"), seg=14)
    B.cyl("sub_hatch", 0.2, 0.2, 0.06, (0.15, y0 + 0.1, 0.85), M("uw_steel_dark"), seg=14)
    for sx in (-0.6, 0.0, 0.6):
        B.cyl("sub_port%.1f" % sx, 0.11, 0.11, 0.05, (sx, y0 + 0.1 - 0.5, 0.3), M("uw_aqua"), rot=(math.pi / 2, 0, 0), seg=12)
    B.cyl("sub_prop", 0.05, 0.25, 0.1, (1.62, y0 + 0.1, 0.15), M("uw_steel_dark"), rot=(0, math.pi / 2, 0), seg=8)
    B.box("sub_fin", (0.3, 0.05, 0.4), (1.45, y0 + 0.1, 0.4), M("uw_red"))
    B.sphere("sub_light", 0.09, (-1.5, y0 + 0.1, 0.25), M("uw_lamp"), outline=False)
    # Bollards et cordage, échelle de bassin.
    for sx in (-1.9, 1.9):
        B.cyl("bollard%.1f" % sx, 0.12, 0.12, 0.35, (sx, y0 - d / 2 + 0.16, 0.42), M("uw_steel_dark"), seg=10)
        B.cyl("bolltop%.1f" % sx, 0.17, 0.17, 0.06, (sx, y0 - d / 2 + 0.16, 0.62), M("uw_steel_dark"), seg=10)
    B.tube("rope", C.bezier((-1.9, y0 - d / 2 + 0.16, 0.5), (-1.7, y0 - 0.6, 0.2), (-1.5, y0, 0.2), (-1.2, y0 + 0.1, 0.4), 7),
           [0.035] * 7, M("uw_canvas"), seg=5)
    for sz in range(3):
        B.box("ladder_r%d" % sz, (0.5, 0.04, 0.04), (1.4, y0 + d / 2 - lip - 0.02, 0.28 - sz * 0.08), M("uw_steel_light"))


def p_console(B: Builder) -> None:
    w, d, h = 1.5, 0.7, 0.95
    B.box("body", (w, d, h), (0, 0.05, h / 2), M("uw_steel_dark"), bevel=0.03)
    desk = C.bm_box(w + 0.1, 0.55, 0.08, bevel=0.02, segs=1)
    C.bm_xform(desk, loc=(0, -0.2, h + 0.05), rot=(0.3, 0, 0))
    B.add("desk", desk, M("uw_steel"))
    for k in range(9):
        B.box("key%d" % k, (0.11, 0.08, 0.04), (-0.55 + k * 0.14, -0.25, h + 0.11), M("uw_red" if k % 4 == 0 else "uw_steel_light"), rot=(0.3, 0, 0), outline=False)
    for sx, rz in ((-0.45, 0.25), (0.45, -0.25)):
        B.box("scr_b%.1f" % sx, (0.62, 0.08, 0.48), (sx, 0.2, h + 0.42), M("uw_steel_dark"), rot=(0.15, 0, rz), bevel=0.02)
        B.box("scr%.1f" % sx, (0.52, 0.03, 0.38), (sx - 0.01, 0.15, h + 0.42), M("uw_screen"), rot=(0.15, 0, rz), outline=False)
    for k in range(3):
        B.sphere("led%d" % k, 0.035, (-0.6 + k * 0.1, -d / 2 + 0.03, h * 0.75), M("uw_led_g" if k else "uw_led_r"), outline=False, shadow=False)
    B.cyl("chair_post", 0.04, 0.04, 0.45, (0.1, -0.85, 0.22), M("uw_steel_dark"), seg=6)
    B.cyl("chair_seat", 0.26, 0.26, 0.1, (0.1, -0.85, 0.48), M("uw_rubber"), seg=14)


def p_server_rack(B: Builder) -> None:
    w, d, h = 0.95, 0.65, 2.15
    B.box("body", (w, d, h), (0, 0, h / 2), M("uw_steel_dark"), bevel=0.03)
    rnd = random.Random(3)
    for k in range(9):
        z = 0.25 + k * 0.2
        B.box("unit%d" % k, (w - 0.14, 0.04, 0.15), (0, -d / 2 - 0.01, z), M("uw_rubber"))
        for j in range(4):
            if rnd.random() < 0.7:
                B.box("led%d_%d" % (k, j), (0.04, 0.02, 0.03), (-0.3 + j * 0.07, -d / 2 - 0.035, z + 0.02),
                      M(rnd.choice(["uw_led_g", "uw_led_g", "uw_led_r", "uw_screen"])), outline=False, shadow=False)
    B.box("vent", (w - 0.2, 0.03, 0.06), (0, -d / 2 - 0.02, h - 0.12), M("uw_steel"))
    for k in range(3):
        B.tube("cable%d" % k, C.bezier((0.3 - k * 0.1, 0, h), (0.3 - k * 0.1, 0.2, h + 0.3), (0.1, 0.4, h + 0.2), (0.0, 0.5, h + 0.1), 6),
               [0.03] * 6, M(["uw_red", "uw_teal", "uw_rubber"][k]), seg=5)


def p_bunk_bed(B: Builder) -> None:
    w, d = 1.9, 0.9
    for sx in (-w / 2, w / 2):
        for sy in (-d / 2, d / 2):
            B.box("post%.1f%.1f" % (sx, sy), (0.07, 0.07, 1.85), (sx, sy, 0.92), M("uw_steel"))
    for z in (0.4, 1.3):
        B.box("frame%.1f" % z, (w, d, 0.08), (0, 0, z), M("uw_steel_dark"))
        B.box("mat%.1f" % z, (w - 0.1, d - 0.08, 0.14), (0, 0, z + 0.11), M("uw_white"), bevel=0.04)
        B.box("blanket%.1f" % z, (w * 0.62, d - 0.04, 0.16), (0.3, -0.01, z + 0.12), M("uw_blue_cloth"), bevel=0.05)
        B.box("pillow%.1f" % z, (0.34, 0.6, 0.12), (-w / 2 + 0.25, 0, z + 0.22), M("uw_white"), bevel=0.05)
    B.box("rail", (w, 0.05, 0.05), (0, -d / 2, 1.65), M("uw_steel"))
    for k in range(4):
        B.box("rung%d" % k, (0.04, 0.04, 0.04) if False else (0.3, 0.04, 0.04), (w / 2 - 0.2, -d / 2 - 0.05, 0.5 + k * 0.28), M("uw_steel_light"))
    B.box("ladr", (0.04, 0.04, 1.4), (w / 2 - 0.05, -d / 2 - 0.05, 0.85), M("uw_steel_light"))
    B.box("ladl", (0.04, 0.04, 1.4), (w / 2 - 0.35, -d / 2 - 0.05, 0.85), M("uw_steel_light"))


def p_mess_table(B: Builder) -> None:
    w, d, h = 1.9, 0.8, 0.78
    B.box("top", (w, d, 0.07), (0, 0, h), M("uw_steel_light"), bevel=0.02)
    B.box("leg", (0.18, 0.5, h), (0, 0, h / 2), M("uw_steel_dark"))
    B.box("foot", (1.4, 0.3, 0.06), (0, 0, 0.03), M("uw_steel_dark"))
    for sy in (-d / 2 - 0.35, d / 2 + 0.35):
        B.box("bench%.1f" % sy, (w - 0.1, 0.32, 0.07), (0, sy, 0.46), M("uw_teal"), bevel=0.02)
        B.box("bleg%.1f" % sy, (0.12, 0.2, 0.43), (0, sy, 0.22), M("uw_steel_dark"))
    for k, (x, y) in enumerate(((-0.55, -0.15), (0.1, 0.2), (0.6, -0.12))):
        B.box("tray%d" % k, (0.42, 0.3, 0.03), (x, y, h + 0.05), M("uw_steel"), outline=False)
        B.sphere("food%d" % k, 0.08, (x - 0.06, y, h + 0.08), M("uw_orange"), scale=(1.2, 1, 0.5), outline=False)
        B.cyl("cup%d" % k, 0.05, 0.05, 0.12, (x + 0.12, y + 0.05, h + 0.11), M("uw_white"), seg=8)


def p_med_bed(B: Builder) -> None:
    w, d = 1.9, 0.85
    B.box("frame", (w, d, 0.12), (0, 0, 0.62), M("uw_steel_light"), bevel=0.02)
    B.box("mat", (w - 0.08, d - 0.06, 0.14), (0, 0, 0.75), M("uw_white"), bevel=0.05)
    B.box("sheet", (w * 0.55, d, 0.15), (0.35, 0, 0.77), M("uw_teal"), bevel=0.05)
    B.box("pillow", (0.36, 0.6, 0.12), (-w / 2 + 0.26, 0, 0.88), M("uw_white"), bevel=0.05)
    B.box("head", (0.07, d, 0.6), (-w / 2, 0, 0.9), M("uw_steel"))
    for sx in (-w / 2 + 0.1, w / 2 - 0.1):
        for sy in (-d / 2 + 0.08, d / 2 - 0.08):
            B.cyl("leg%.1f%.1f" % (sx, sy), 0.03, 0.03, 0.6, (sx, sy, 0.3), M("uw_steel"), seg=6)
            B.sphere("wheel%.1f%.1f" % (sx, sy), 0.06, (sx, sy, 0.06), M("uw_rubber"), seg=8, rings=5)
    # Perfusion et moniteur.
    B.cyl("iv", 0.02, 0.02, 1.7, (-w / 2 - 0.2, -0.3, 0.85), M("uw_steel_light"), seg=6)
    B.box("ivbag", (0.16, 0.06, 0.24), (-w / 2 - 0.2, -0.33, 1.55), M("uw_specimen"))
    B.tube("ivline", C.bezier((-w / 2 - 0.2, -0.33, 1.42), (-w / 2 - 0.1, -0.4, 1.0), (-0.6, -0.4, 0.95), (-0.4, -0.3, 0.86), 6),
           [0.012] * 6, M("uw_white"), seg=4, shadow=False)
    B.box("mon", (0.45, 0.12, 0.34), (-w / 2 - 0.15, 0.25, 1.35), M("uw_steel_dark"), bevel=0.02)
    B.box("monscr", (0.36, 0.02, 0.24), (-w / 2 - 0.15, 0.18, 1.35), M("uw_screen"), outline=False)
    B.cyl("monpost", 0.03, 0.03, 1.2, (-w / 2 - 0.15, 0.3, 0.6), M("uw_steel"), seg=6)


def _fish(B: Builder, name: str, loc, s: float, mat) -> None:
    x, y, z = loc
    B.sphere(name, s, (x, y, z), mat, scale=(1.4, 0.5, 0.8), seg=10, rings=6)
    B.box(name + "_t", (s * 0.2, s * 0.3, s * 1.1), (x + s * 1.5, y, z), mat, rot=(0, 0.0, 0))


def p_aquarium_tank(B: Builder) -> None:
    w, d, h = 1.55, 0.7, 1.25
    B.box("base", (w + 0.1, d + 0.1, 0.5), (0, 0, 0.25), M("uw_steel_dark"), bevel=0.03)
    B.box("water", (w - 0.06, d - 0.06, h - 0.1), (0, 0, 0.5 + h / 2 - 0.05), M("uw_aqua"))
    for sx in (-w / 2, w / 2):
        for sy in (-d / 2, d / 2):
            B.box("edge%.1f%.1f" % (sx, sy), (0.06, 0.06, h), (sx, sy, 0.5 + h / 2), M("uw_steel"))
    B.box("lid", (w + 0.08, d + 0.08, 0.1), (0, 0, 0.5 + h + 0.02), M("uw_steel"), bevel=0.02)
    B.box("lamp", (w * 0.6, 0.2, 0.06), (0, 0, 0.5 + h + 0.1), M("uw_lamp"), outline=False)
    rnd = random.Random(8)
    for k in range(4):
        _fish(B, "fish%d" % k, (rnd.uniform(-0.5, 0.5), -d / 2 + 0.02, rnd.uniform(0.8, 1.5)), rnd.uniform(0.06, 0.1),
              M(rnd.choice(["uw_orange", "uw_yellow", "uw_coral_pink"])))
    for k in range(3):
        x = -0.5 + k * 0.45
        for b in range(3):
            a = -math.pi / 2 + (b - 1) * 0.5
            B.tube("cor%d_%d" % (k, b), [(x, -0.1, 0.55), (x + math.cos(a) * 0.12, -0.12, 0.55 - math.sin(a) * 0.25)],
                   [0.04, 0.02], M(["uw_coral_pink", "uw_coral_orange", "uw_coral_purple"][k]), seg=5)
    B.sphere("rock", 0.18, (0.45, 0.05, 0.6), M("uw_rock"), scale=(1.4, 1, 0.6))


def p_specimen_tank(B: Builder) -> None:
    r, h = 0.38, 1.6
    B.cyl("base", r + 0.1, r + 0.12, 0.3, (0, 0, 0.15), M("uw_steel_dark"), seg=18)
    B.cyl("glass", r, r, h, (0, 0, 0.3 + h / 2), M("uw_specimen"), seg=18)
    B.cyl("cap", r + 0.08, r + 0.06, 0.22, (0, 0, 0.3 + h + 0.1), M("uw_steel_dark"), seg=18)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        B.cyl("rib%d" % k, 0.03, 0.03, h, (math.cos(a) * (r + 0.01), math.sin(a) * (r + 0.01), 0.3 + h / 2), M("uw_steel"), seg=5)
    # Spécimen : créature recroquevillée au masque de coquillage.
    B.sphere("spec_body", 0.17, (0, -0.05, 0.95), M("uw_coral_purple"), scale=(0.9, 0.8, 1.3))
    B.sphere("spec_mask", 0.12, (0, -0.16, 1.25), M("uw_bone"), scale=(1.0, 0.5, 1.15))
    B.tube("spec_tail", C.bezier((0, -0.05, 0.75), (0.15, -0.1, 0.55), (0.0, -0.1, 0.45), (-0.12, -0.08, 0.5), 6),
           [0.08, 0.07, 0.05, 0.04, 0.03, 0.01], M("uw_coral_purple"), seg=6)
    for k in range(3):
        B.tube("cable%d" % k, C.bezier((0.1 * k - 0.1, 0.1, 0.3 + h + 0.2), (0.1 * k - 0.1, 0.3, 0.3 + h + 0.4),
                                       (0.2, 0.5, 0.4), (0.3, 0.5, 0.05), 6), [0.03] * 6, M(["uw_rubber", "uw_red", "uw_rubber"][k]), seg=5)


def p_lab_bench(B: Builder) -> None:
    w, d, h = 1.7, 0.75, 0.9
    B.box("top", (w, d, 0.07), (0, 0, h), M("uw_white"), bevel=0.02)
    B.box("cab", (w - 0.1, d - 0.1, h - 0.08), (0, 0, (h - 0.08) / 2), M("uw_teal"))
    for k in range(3):
        B.box("drawer%d" % k, (0.46, 0.03, 0.6), (-0.55 + k * 0.55, -d / 2 + 0.04, 0.42), M("uw_steel_light"))
        B.box("handle%d" % k, (0.18, 0.04, 0.03), (-0.55 + k * 0.55, -d / 2 + 0.01, 0.62), M("uw_steel_dark"))
    # Microscope.
    B.box("mic_base", (0.25, 0.3, 0.05), (-0.45, 0.05, h + 0.06), M("uw_steel_dark"))
    B.tube("mic_arm", [(-0.45, 0.15, h + 0.06), (-0.45, 0.15, h + 0.4), (-0.45, 0.0, h + 0.5)], [0.04, 0.04, 0.04], M("uw_white"), seg=6)
    B.cyl("mic_tube", 0.05, 0.04, 0.3, (-0.45, -0.02, h + 0.4), M("uw_steel_dark"), rot=(0.4, 0, 0), seg=8)
    # Flacons colorés lumineux.
    for k, (x, col) in enumerate(((0.05, "uw_specimen"), (0.25, "uw_screen"), (0.45, "uw_grow"), (0.62, "uw_specimen"))):
        B.cyl("flask%d" % k, 0.07, 0.04, 0.22, (x, 0.1 - (k % 2) * 0.15, h + 0.15), M(col), seg=10)
        B.cyl("neck%d" % k, 0.025, 0.025, 0.1, (x, 0.1 - (k % 2) * 0.15, h + 0.3), M("uw_white"), seg=6)
    B.box("papers", (0.4, 0.3, 0.02), (-0.05, -0.15, h + 0.045), M("uw_paper"), rot=(0, 0, 0.25), outline=False)


def p_pipes(B: Builder) -> None:
    for k, (x, r, mat) in enumerate(((-0.45, 0.13, "uw_steel"), (-0.1, 0.17, "uw_copper"), (0.28, 0.11, "uw_steel"), (0.52, 0.08, "uw_red"))):
        B.cyl("p%d" % k, r, r, 2.3, (x, 0.15, 1.15), M(mat), seg=12)
        for z in (0.4, 1.4):
            B.cyl("flange%d_%.1f" % (k, z), r + 0.05, r + 0.05, 0.08, (x, 0.15, z), M("uw_steel_dark"), seg=12)
    B.tube("elbow", [(-0.45, 0.15, 0.8), (-0.45, -0.15, 0.8), (-0.1, -0.2, 0.8), (-0.1, 0.0, 0.8)], [0.09] * 4, M("uw_steel"), seg=10)
    # Volant de vanne rouge.
    B.torus("wheel", 0.2, 0.03, (-0.1, -0.08, 1.15), M("uw_red"), rot=(math.pi / 2, 0, 0), seg=18)
    for a in (0, math.pi / 2):
        B.box("spoke%.1f" % a, (0.38, 0.03, 0.03), (-0.1, -0.08, 1.15), M("uw_red"), rot=(0, a, 0))
    B.cyl("gauge", 0.1, 0.1, 0.05, (0.28, -0.0, 1.6), M("uw_white"), rot=(math.pi / 2, 0, 0), seg=14)
    B.box("needle", (0.12, 0.02, 0.02), (0.3, -0.03, 1.62), M("uw_red"), rot=(0, 0.6, 0), outline=False)


def p_pump(B: Builder) -> None:
    B.box("skid", (1.8, 0.85, 0.15), (0, 0, 0.08), M("uw_steel_dark"))
    B.cyl("motor", 0.36, 0.36, 0.9, (-0.4, 0, 0.55), M("uw_teal"), rot=(0, math.pi / 2, 0), seg=18)
    for k in range(6):
        B.cyl("fin%d" % k, 0.39, 0.39, 0.03, (-0.75 + k * 0.13, 0, 0.55), M("uw_steel"), rot=(0, math.pi / 2, 0), seg=18)
    B.cyl("volute", 0.45, 0.45, 0.4, (0.45, 0, 0.6), M("uw_yellow"), rot=(0, math.pi / 2, 0), seg=20)
    B.cyl("outlet", 0.14, 0.14, 0.7, (0.45, 0, 1.25), M("uw_steel"), seg=12)
    B.tube("inlet", [(0.7, 0, 0.6), (0.95, 0, 0.6), (0.95, 0.3, 0.6), (0.95, 0.45, 0.2)], [0.13] * 4, M("uw_steel"), seg=12)
    B.cyl("gauge", 0.09, 0.09, 0.04, (0.45, -0.24, 1.05), M("uw_white"), rot=(math.pi / 2, 0, 0), seg=12)
    B.box("plate", (0.3, 0.02, 0.14), (-0.4, -0.37, 0.6), M("uw_steel_light"), outline=False)
    B.sphere("lamp", 0.05, (-0.1, -0.3, 0.92), M("uw_led_g"), outline=False, shadow=False)


def p_valve_wheel(B: Builder) -> None:
    B.cyl("post", 0.12, 0.12, 0.9, (0, 0.05, 0.45), M("uw_steel"), seg=12)
    B.cyl("flange", 0.18, 0.18, 0.08, (0, 0.05, 0.08), M("uw_steel_dark"), seg=12)
    B.cyl("stem", 0.03, 0.03, 0.25, (0, 0.05, 0.98), M("uw_steel_light"), seg=6)
    B.torus("wheel", 0.26, 0.035, (0, 0.05, 1.08), M("uw_red"), seg=20)
    for a in (0, math.pi / 3, 2 * math.pi / 3):
        B.box("spoke%.1f" % a, (0.5, 0.03, 0.03), (0, 0.05, 1.08), M("uw_red"), rot=(0, 0, a))


def p_oxygen_rack(B: Builder) -> None:
    w = 1.3
    B.box("back", (w, 0.08, 1.5), (0, 0.25, 0.75), M("uw_steel_dark"))
    B.box("strap1", (w, 0.12, 0.08), (0, 0.0, 1.1), M("uw_steel"))
    B.box("strap2", (w, 0.12, 0.08), (0, 0.0, 0.45), M("uw_steel"))
    for k in range(4):
        x = -0.48 + k * 0.32
        B.cyl("tank%d" % k, 0.14, 0.14, 1.1, (x, 0.05, 0.62), M("uw_yellow"), seg=14)
        B.sphere("dome%d" % k, 0.14, (x, 0.05, 1.17), M("uw_yellow"), seg=12, rings=6)
        B.cyl("valve%d" % k, 0.04, 0.04, 0.14, (x, 0.05, 1.33), M("uw_steel_light"), seg=6)
        B.box("band%d" % k, (0.29, 0.29, 0.1), (x, 0.05, 0.85), M("uw_rubber"))


def p_diving_suit(B: Builder) -> None:
    B.box("stand", (0.7, 0.5, 0.08), (0, 0, 0.04), M("uw_steel_dark"))
    B.cyl("pole", 0.04, 0.04, 1.4, (0, 0.15, 0.7), M("uw_steel"), seg=6)
    torso = C.bm_loft([C.ellipse(0, 0, z, rx, ry, 14) for z, rx, ry in ((0.6, 0.24, 0.18), (0.9, 0.3, 0.2), (1.25, 0.33, 0.22), (1.42, 0.2, 0.16))])
    B.add("suit", torso, M("uw_canvas"), sharp=80)
    for sx in (-1, 1):
        B.tube("leg%d" % sx, [(0.12 * sx, 0, 0.62), (0.13 * sx, 0, 0.3), (0.13 * sx, -0.03, 0.12)], [0.11, 0.1, 0.1], M("uw_canvas"), seg=8)
        B.box("boot%d" % sx, (0.18, 0.3, 0.12), (0.13 * sx, -0.06, 0.08), M("uw_steel_dark"), bevel=0.03)
        B.tube("arm%d" % sx, [(0.32 * sx, 0, 1.3), (0.4 * sx, -0.05, 1.0), (0.38 * sx, -0.1, 0.75)], [0.09, 0.08, 0.08], M("uw_canvas"), seg=8)
        B.sphere("glove%d" % sx, 0.09, (0.38 * sx, -0.1, 0.7), M("uw_rubber"))
    B.cyl("collar", 0.26, 0.26, 0.1, (0, 0, 1.45), M("uw_copper"), seg=16)
    B.sphere("helmet", 0.3, (0, 0, 1.7), M("uw_copper"), seg=18, rings=12)
    B.cyl("faceplate", 0.14, 0.14, 0.06, (0, -0.28, 1.7), M("uw_aqua"), rot=(math.pi / 2, 0, 0), seg=16)
    B.torus("faceframe", 0.15, 0.025, (0, -0.3, 1.7), M("uw_yellow"), rot=(math.pi / 2, 0, 0), seg=16)
    for sx in (-1, 1):
        B.cyl("sideport%d" % sx, 0.08, 0.08, 0.05, (0.27 * sx, -0.08, 1.72), M("uw_aqua"), rot=(0, math.pi / 2, 0), seg=10)


def _coral(B: Builder, name: str, x: float, y: float, mat: str, n: int, size: float, seed: int) -> None:
    rnd = random.Random(seed)
    for b in range(n):
        a = rnd.uniform(0, 2 * math.pi)
        tilt = rnd.uniform(0.2, 0.7)
        ln = size * rnd.uniform(0.6, 1.0)
        p0 = (x, y, 0.1)
        p1 = (x + math.cos(a) * ln * tilt * 0.5, y + math.sin(a) * ln * tilt * 0.5, ln * 0.55)
        p2 = (x + math.cos(a) * ln * tilt, y + math.sin(a) * ln * tilt, ln)
        B.tube("%s_b%d" % (name, b), [p0, p1, p2], [size * 0.12, size * 0.09, size * 0.05], M(mat), seg=7)
        B.sphere("%s_t%d" % (name, b), size * 0.06, p2, M(mat), seg=8, rings=5)
        if rnd.random() < 0.6:
            q = (p1[0] + math.cos(a + 1.2) * ln * 0.25, p1[1] + math.sin(a + 1.2) * ln * 0.25, p1[2] + ln * 0.25)
            B.tube("%s_s%d" % (name, b), [p1, q], [size * 0.07, size * 0.04], M(mat), seg=6)


def p_coral_cluster(B: Builder) -> None:
    B.sphere("rock", 0.45, (0, 0.05, 0.12), M("uw_rock"), scale=(1.3, 1.0, 0.5))
    B.sphere("rock2", 0.25, (0.45, -0.15, 0.08), M("uw_rock"), scale=(1.2, 1.0, 0.6))
    _coral(B, "c1", -0.2, 0.05, "uw_coral_pink", 5, 0.8, 1)
    _coral(B, "c2", 0.3, -0.05, "uw_coral_orange", 4, 0.6, 2)
    B.sphere("brain", 0.2, (-0.45, -0.2, 0.18), M("uw_coral_purple"), scale=(1.2, 1, 0.8))
    for k in range(4):
        B.cyl("barn%d" % k, 0.06, 0.03, 0.08, (0.1 + k * 0.1, -0.35, 0.05), M("uw_bone"), seg=8)


def p_kelp(B: Builder) -> None:
    rnd = random.Random(4)
    B.sphere("rock", 0.3, (0, 0.05, 0.05), M("uw_rock"), scale=(1.4, 1.0, 0.4))
    for k in range(5):
        x0 = rnd.uniform(-0.25, 0.25)
        y0 = rnd.uniform(-0.1, 0.15)
        hgt = rnd.uniform(1.6, 2.6)
        ph = rnd.uniform(0, 6)
        pts = [(x0 + math.sin(ph + i * 0.8) * 0.12 * (i / 7), y0, hgt * i / 7) for i in range(8)]
        B.tube("stem%d" % k, pts, [0.035] * 8, M("uw_kelp"), seg=5)
        for i in range(2, 8, 2):
            p = pts[i]
            s = 1 if (i // 2) % 2 else -1
            leaf = C.bm_tube([p, (p[0] + 0.18 * s, p[1] - 0.02, p[2] + 0.12), (p[0] + 0.3 * s, p[1] - 0.03, p[2] + 0.3)],
                             [0.05, 0.08, 0.01], seg=6, flat=0.25, up=(0, 1, 0))
            B.add("leaf%d_%d" % (k, i), leaf, M("uw_kelp"), sharp=80)
        B.sphere("float%d" % k, 0.05, pts[-1], M("uw_coral_orange"), seg=8, rings=5)


def p_cable_spool(B: Builder) -> None:
    B.cyl("core", 0.3, 0.3, 0.7, (0, 0, 0.55), M("uw_rubber"), rot=(0, math.pi / 2, 0), seg=16)
    for sx in (-0.38, 0.38):
        B.cyl("flange%.1f" % sx, 0.55, 0.55, 0.06, (sx, 0, 0.55), M("uw_wood"), rot=(0, math.pi / 2, 0), seg=20)
        B.cyl("hub%.1f" % sx, 0.12, 0.12, 0.08, (sx * 1.1, 0, 0.55), M("uw_steel_dark"), rot=(0, math.pi / 2, 0), seg=10)
    for k in range(5):
        B.torus("wrap%d" % k, 0.39, 0.05, (-0.28 + k * 0.14, 0, 0.55), M(["uw_orange", "uw_rubber"][k % 2]), rot=(0, math.pi / 2, 0), seg=20, rseg=5)
    B.tube("tail", C.bezier((0.2, -0.35, 0.3), (0.3, -0.7, 0.05), (0.5, -0.7, 0.03), (0.8, -0.55, 0.03), 6), [0.05] * 6, M("uw_orange"), seg=6)


def p_crate_stack(B: Builder) -> None:
    def case(name, size, loc, mat, rot=0.0):
        B.box(name, size, loc, M(mat), rot=(0, 0, rot), bevel=0.04)
        B.box(name + "_band", (size[0] + 0.02, size[1] + 0.02, 0.06), loc, M("uw_steel_dark"), rot=(0, 0, rot))
    case("c1", (0.9, 0.7, 0.6), (-0.3, 0.05, 0.3), "uw_teal")
    case("c2", (0.75, 0.65, 0.55), (0.5, -0.05, 0.28), "uw_orange", 0.1)
    case("c3", (0.7, 0.6, 0.5), (-0.2, 0.1, 0.86), "uw_steel", -0.08)
    B.box("stencil", (0.3, 0.02, 0.14), (-0.3, -0.31, 0.32), M("uw_white"), outline=False)


def p_lamp_post(B: Builder) -> None:
    B.box("base", (0.4, 0.4, 0.12), (0, 0.05, 0.06), M("uw_steel_dark"))
    B.cyl("pole", 0.05, 0.05, 2.4, (0, 0.05, 1.25), M("uw_steel"), seg=8)
    B.box("arm", (0.5, 0.07, 0.07), (0.22, 0.05, 2.38), M("uw_steel_dark"))
    lx, lz = 0.42, 2.12
    B.cyl("shade", 0.05, 0.22, 0.14, (lx, 0.05, lz + 0.14), M("uw_steel_dark"), seg=12)
    B.sphere("bulb", 0.11, (lx, 0.05, lz), M("uw_lamp"), outline=False)
    for k in range(4):
        a = k * math.pi / 2
        B.tube("cage%d" % k, [(lx + math.cos(a) * 0.14, 0.05 + math.sin(a) * 0.14, lz + 0.08),
                              (lx + math.cos(a) * 0.15, 0.05 + math.sin(a) * 0.15, lz - 0.05),
                              (lx, 0.05, lz - 0.14)], [0.012] * 3, M("uw_steel_dark"), seg=4, shadow=False)


def p_alarm_light(B: Builder) -> None:
    B.box("base", (0.36, 0.36, 0.1), (0, 0.05, 0.05), M("uw_rubber"))
    B.cyl("pole", 0.06, 0.06, 1.5, (0, 0.05, 0.8), M("uw_yellow"), seg=8)
    for k in range(4):
        B.cyl("stripe%d" % k, 0.065, 0.065, 0.1, (0, 0.05, 0.3 + k * 0.3), M("uw_rubber"), seg=8)
    B.cyl("cap_base", 0.14, 0.14, 0.1, (0, 0.05, 1.6), M("uw_steel_dark"), seg=12)
    B.cyl("dome", 0.12, 0.1, 0.22, (0, 0.05, 1.76), M("uw_alarm"), seg=12)
    B.sphere("top", 0.1, (0, 0.05, 1.87), M("uw_alarm"), seg=10, rings=6)
    B.cyl("grill", 0.13, 0.13, 0.03, (0, 0.05, 1.72), M("uw_steel_dark"), seg=12)


def p_generator(B: Builder) -> None:
    B.box("skid", (2.6, 1.1, 0.15), (0, 0.05, 0.08), M("uw_steel_dark"))
    B.cyl("drum", 0.55, 0.55, 1.5, (-0.3, 0.05, 0.75), M("uw_steel"), rot=(0, math.pi / 2, 0), seg=22)
    for k in range(5):
        B.cyl("ring%d" % k, 0.58, 0.58, 0.06, (-0.95 + k * 0.32, 0.05, 0.75), M("uw_copper"), rot=(0, math.pi / 2, 0), seg=22)
    B.cyl("fly", 0.62, 0.62, 0.14, (0.75, 0.05, 0.75), M("uw_red"), rot=(0, math.pi / 2, 0), seg=24)
    B.cyl("hub", 0.15, 0.15, 0.2, (0.85, 0.05, 0.75), M("uw_steel_dark"), rot=(0, math.pi / 2, 0), seg=10)
    B.box("panel", (0.6, 0.12, 0.7), (-0.9, -0.5, 0.55), M("uw_steel_dark"), bevel=0.02)
    B.box("pscr", (0.4, 0.02, 0.2), (-0.9, -0.57, 0.7), M("uw_screen"), outline=False)
    for k in range(3):
        B.sphere("pled%d" % k, 0.035, (-1.05 + k * 0.15, -0.58, 0.45), M("uw_led_r" if k == 1 else "uw_led_g"), outline=False, shadow=False)
    B.tube("exhaust", [(-0.3, 0.3, 1.25), (-0.3, 0.45, 1.8), (-0.3, 0.6, 2.0)], [0.12, 0.12, 0.12], M("uw_steel_dark"), seg=10)


def p_hydro_planter(B: Builder) -> None:
    w, d = 1.7, 0.75
    B.box("tray", (w, d, 0.4), (0, 0, 0.45), M("uw_steel_light"), bevel=0.02)
    for sx in (-w / 2 + 0.1, w / 2 - 0.1):
        B.box("leg%.1f" % sx, (0.08, d - 0.1, 0.3), (sx, 0, 0.15), M("uw_steel_dark"))
    B.box("water", (w - 0.12, d - 0.12, 0.04), (0, 0, 0.64), M("uw_aqua"), shadow=False)
    rnd = random.Random(12)
    for k in range(14):
        x, y = rnd.uniform(-0.75, 0.75), rnd.uniform(-0.28, 0.28)
        hh = rnd.uniform(0.2, 0.45)
        B.tube("pl%d" % k, [(x, y, 0.62), (x + rnd.uniform(-0.08, 0.08), y, 0.62 + hh)], [0.05, 0.02],
               M(rnd.choice(["uw_kelp", "uw_kelp", "uw_specimen"])), seg=5)
    for sx in (-w / 2 + 0.1, w / 2 - 0.1):
        B.box("lpost%.1f" % sx, (0.05, 0.05, 1.0), (sx, d / 2 - 0.05, 1.1), M("uw_steel"))
    B.box("growlamp", (w, 0.22, 0.08), (0, d / 2 - 0.15, 1.6), M("uw_steel_dark"))
    B.box("growlight", (w - 0.1, 0.14, 0.03), (0, d / 2 - 0.15, 1.55), M("uw_grow"), outline=False)


def p_desk(B: Builder) -> None:
    w, d, h = 1.6, 0.75, 0.85
    B.box("top", (w, d, 0.06), (0, 0, h), M("uw_steel_light"), bevel=0.02)
    B.box("ped", (0.55, d - 0.1, h - 0.05), (0.45, 0, (h - 0.05) / 2), M("uw_steel"))
    for k in range(3):
        B.box("dr%d" % k, (0.45, 0.03, 0.22), (0.45, -d / 2 + 0.03, 0.15 + k * 0.26), M("uw_steel_light"))
    B.box("legl", (0.06, d - 0.1, h), (-w / 2 + 0.05, 0, h / 2), M("uw_steel_dark"))
    B.box("mon", (0.55, 0.1, 0.38), (-0.25, 0.2, h + 0.3), M("uw_steel_dark"), bevel=0.02)
    B.box("monscr", (0.47, 0.02, 0.3), (-0.25, 0.14, h + 0.3), M("uw_screen"), outline=False)
    B.box("papers", (0.35, 0.26, 0.02), (0.35, -0.05, h + 0.04), M("uw_paper"), rot=(0, 0, 0.3), outline=False)
    B.cyl("mug", 0.06, 0.06, 0.12, (0.6, 0.15, h + 0.09), M("uw_red"), seg=8)
    B.box("chair", (0.5, 0.45, 0.08), (-0.2, -0.75, 0.5), M("uw_rubber"))
    B.box("chairback", (0.5, 0.08, 0.55), (-0.2, -0.98, 0.8), M("uw_rubber"))


# ----------------------------------------------------------------------------- kit (pièces du constructeur)

def k_ladder_up(B: Builder) -> None:
    """Échelle d'acier contre le mur nord, montant vers une trappe de plafond (cage jaune)."""
    for sx in (-0.32, 0.32):
        B.box("rail%.1f" % sx, (0.07, 0.07, 2.4), (sx, 0.55, 1.2), M("uw_yellow"))
    for k in range(8):
        B.box("rung%d" % k, (0.64, 0.05, 0.05), (0, 0.55, 0.2 + k * 0.28), M("uw_steel_light"))
    for k in range(3):
        z = 0.9 + k * 0.5
        B.torus("cage%d" % k, 0.42, 0.025, (0, 0.3, z), M("uw_yellow"), seg=18, rseg=4)
    B.box("plate", (1.2, 1.2, 0.06), (0, 0.1, 0.03), M("uw_steel_dark"), shadow=False)
    hazard_ring(B, "hz", 0.52, 0.07, 12, 0.07, loc=(0, 0.1))


def k_hatch_down(B: Builder) -> None:
    """Trappe ronde ouverte dans le plancher : échelle qui descend dans le noir, couvercle relevé."""
    B.cyl("rim", 0.62, 0.62, 0.12, (0, 0.05, 0.06), M("uw_steel"), seg=28)
    B.cyl("hole", 0.5, 0.5, 0.14, (0, 0.05, 0.07), M("uw_hole"), seg=28, shadow=False)
    hazard_ring(B, "hz", 0.72, 0.03, 16, 0.08, loc=(0, 0.05))
    for sx in (-0.2, 0.2):
        B.box("rail%.1f" % sx, (0.05, 0.05, 0.5), (sx, 0.3, 0.05), M("uw_yellow"), shadow=False)
    for k in range(2):
        B.box("rung%d" % k, (0.4, 0.04, 0.04), (0, 0.3, 0.12 - k * 0.12), M("uw_steel_light"), shadow=False)
    lid = C.bm_cyl(28, 0.55, 0.55, 0.08)
    C.bm_xform(lid, loc=(0, 0.75, 0.55), rot=(math.radians(75), 0, 0))
    B.add("lid", lid, M("uw_steel"))
    B.torus("lidwheel", 0.22, 0.03, (0, 0.71, 0.56), M("uw_red"), rot=(math.radians(75), 0, 0), seg=16)


def k_pod(B: Builder) -> None:
    """Capsule de remontée vue d'en haut : sas rond dans le sol (2 x 2 cases), feux verts."""
    B.cyl("plate", 1.6, 1.6, 0.08, (0, 0, 0.04), M("uw_steel_dark"), seg=36, shadow=False)
    hazard_ring(B, "hz", 1.45, 0.1, 24, 0.12)
    B.cyl("collar", 1.05, 1.1, 0.25, (0, 0, 0.15), M("uw_steel"), seg=32)
    B.cyl("dome", 0.95, 0.95, 0.12, (0, 0, 0.3), M("uw_orange"), seg=32)
    B.sphere("domecap", 0.95, (0, 0, 0.32), M("uw_orange"), scale=(1, 1, 0.3), seg=28, rings=10)
    B.cyl("window", 0.35, 0.35, 0.05, (0, 0, 0.62), M("uw_aqua"), seg=20)
    B.torus("wheel", 0.42, 0.04, (0, 0, 0.6), M("uw_steel_light"), seg=24)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        B.sphere("feu%d" % k, 0.09, (math.cos(a) * 1.3, math.sin(a) * 1.3, 0.16), M("uw_beacon"), outline=False, shadow=False)


def k_wall_lamp(B: Builder) -> None:
    B.box("plate", (0.22, 0.05, 0.3), (0, 0.0, 0.0), M("uw_steel_dark"))
    B.box("arm", (0.06, 0.18, 0.06), (0, -0.1, 0.05), M("uw_steel_dark"))
    B.sphere("bulb", 0.1, (0, -0.2, 0.0), M("uw_lamp"), outline=False)
    for k in range(3):
        B.torus("cage%d" % k, 0.12, 0.012, (0, -0.2, -0.06 + k * 0.06), M("uw_steel_dark"), seg=12, rseg=4)


def k_wall_alarm(B: Builder) -> None:
    B.box("plate", (0.24, 0.05, 0.24), (0, 0.0, 0.0), M("uw_yellow"))
    B.cyl("dome", 0.1, 0.08, 0.16, (0, -0.1, 0.0), M("uw_alarm"), rot=(math.pi / 2, 0, 0), seg=12)
    B.cyl("grill", 0.11, 0.11, 0.03, (0, -0.12, 0.0), M("uw_steel_dark"), rot=(math.pi / 2, 0, 0), seg=12)


def k_wall_coral(B: Builder) -> None:
    """Grappe de coraux et bernacles qui envahit le pied d'un mur."""
    B.sphere("rock", 0.3, (0, 0.1, 0.05), M("uw_rock"), scale=(1.6, 0.8, 0.5))
    _coral(B, "a", -0.25, 0.1, "uw_coral_orange", 3, 0.5, 7)
    _coral(B, "b", 0.2, 0.12, "uw_coral_pink", 4, 0.55, 9)
    for k in range(6):
        B.cyl("barn%d" % k, 0.07, 0.035, 0.09, (-0.45 + k * 0.17, -0.12 + (k % 2) * 0.08, 0.06), M("uw_bone"), seg=8)


def k_beacon(B: Builder) -> None:
    """Balise de remontée (extraction) : bouée orange, mât, feu vert."""
    B.cyl("base", 0.25, 0.3, 0.2, (0, 0, 0.1), M("uw_orange"), seg=16)
    B.sphere("buoy", 0.28, (0, 0, 0.35), M("uw_orange"), seg=16, rings=10)
    B.torus("band", 0.29, 0.04, (0, 0, 0.35), M("uw_white"), seg=18)
    B.cyl("mast", 0.04, 0.04, 0.9, (0, 0, 0.95), M("uw_steel_light"), seg=8)
    B.sphere("light", 0.12, (0, 0, 1.45), M("uw_beacon"), outline=False)
    B.cyl("lcap", 0.13, 0.1, 0.06, (0, 0, 1.58), M("uw_steel_dark"), seg=10)


PROPS = {
    "moon_pool": p_moon_pool, "console": p_console, "server_rack": p_server_rack, "bunk_bed": p_bunk_bed,
    "mess_table": p_mess_table, "med_bed": p_med_bed, "aquarium_tank": p_aquarium_tank, "specimen_tank": p_specimen_tank,
    "lab_bench": p_lab_bench, "pipes": p_pipes, "pump": p_pump, "valve_wheel": p_valve_wheel, "oxygen_rack": p_oxygen_rack,
    "diving_suit": p_diving_suit, "coral_cluster": p_coral_cluster, "kelp": p_kelp, "cable_spool": p_cable_spool,
    "crate_stack": p_crate_stack, "lamp_post": p_lamp_post, "alarm_light": p_alarm_light, "generator": p_generator,
    "hydro_planter": p_hydro_planter, "desk": p_desk,
}
KIT = {
    "ladder_up": k_ladder_up, "hatch_down": k_hatch_down, "pod": k_pod, "wall_lamp": k_wall_lamp,
    "wall_alarm": k_wall_alarm, "wall_coral": k_wall_coral, "beacon": k_beacon,
}
# Cadre de rendu (unités monde : largeur, hauteur) et hauteur visée (BU).
FRAMES = {
    "moon_pool": ((220, 200), 2.2), "console": ((130, 120), 0.8), "server_rack": ((80, 130), 1.1),
    "bunk_bed": ((130, 130), 0.9), "mess_table": ((140, 120), 0.4), "med_bed": ((150, 120), 0.7),
    "aquarium_tank": ((120, 130), 0.9), "specimen_tank": ((80, 140), 1.1), "lab_bench": ((130, 110), 0.6),
    "pipes": ((100, 140), 1.2), "pump": ((140, 110), 0.6), "valve_wheel": ((60, 80), 0.6),
    "oxygen_rack": ((100, 110), 0.8), "diving_suit": ((70, 130), 1.0), "coral_cluster": ((90, 80), 0.4),
    "kelp": ((80, 140), 1.2), "cable_spool": ((100, 90), 0.4), "crate_stack": ((100, 110), 0.6),
    "lamp_post": ((70, 140), 1.3), "alarm_light": ((50, 110), 0.95), "generator": ((180, 150), 0.9),
    "hydro_planter": ((130, 120), 0.8), "desk": ((130, 120), 0.6),
    "ladder_up": ((90, 140), 1.1), "hatch_down": ((90, 90), 0.2), "pod": ((150, 140), 0.2),
    "wall_lamp": ((24, 24), 0.0), "wall_alarm": ((24, 24), 0.0), "wall_coral": ((70, 50), 0.2), "beacon": ((50, 90), 0.8),
}
# Points chauds (lueur additive), en BU depuis le point d'appui.
GLOW = {
    "console": (0.0, 0.15, 1.35), "aquarium_tank": (0.0, 0.0, 1.3), "specimen_tank": (0.0, 0.0, 1.1),
    "lamp_post": (0.42, 0.05, 2.12), "alarm_light": (0.0, 0.05, 1.8), "server_rack": (0.0, -0.3, 1.2),
    "hydro_planter": (0.0, 0.2, 1.3), "lab_bench": (0.3, 0.0, 1.1), "desk": (-0.25, 0.14, 1.15),
    "moon_pool": (0.0, 1.7, 0.1), "med_bed": (-1.1, 0.2, 1.35),
    "wall_lamp": (0.0, -0.2, 0.0), "wall_alarm": (0.0, -0.12, 0.0), "beacon": (0.0, 0.0, 1.45), "pod": (0.0, 0.0, 0.6),
}
NO_SHADOW = {"wall_lamp", "wall_alarm"}


def render_all(only: list[str] | None = None) -> None:
    for k, fn in list(PROPS.items()) + list(KIT.items()):
        if only and k not in only:
            continue
        name = ("prop_" if k in PROPS else "kit_") + k
        fr, tz = FRAMES[k]
        BP.render_piece(name, fn, fr, target_z=tz, glow=GLOW.get(k), shadow=k not in NO_SHADOW, outline_px=4.0)


def pack(atlas_w: int = 2048) -> None:
    """Empaquette décors, kit, décalques (uw_tiles) et lueurs dans assets/sprites/underwater/atlas.png."""
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
    items.append(("glow", BP._glow_sprite(128), {"feet": [64, 64]}))
    items.append(("white", Image.new("RGBA", (8, 8), (255, 255, 255, 255)), {"feet": [4, 4], "inset": 2}))
    items.sort(key=lambda t: (-t[1].height, t[0]))
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
    pieces = {}
    for name, im, info in items:
        px, py = pos[name]
        atlas.paste(im, (px, py))
        ins = info.get("inset", 0)
        e = {"rect": [px + ins, py + ins, im.width - 2 * ins, im.height - 2 * ins],
             "feet": [round(info.get("feet", [0, 0])[0], 1), round(info.get("feet", [0, 0])[1], 1)]}
        if "glow" in info:
            e["glow"] = info["glow"]
        pieces[name] = e
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, "atlas.png")
    atlas.save(out, optimize=True)
    with open(os.path.join(OUT_DIR, "atlas_meta.gd"), "w") as f:
        f.write("## Généré par art/blender/underwater/uw_props.py : NE PAS ÉDITER.\n")
        f.write("## Pièces de assets/sprites/underwater/atlas.png : rect [x, y, w, h] (px), feet [x, y]\n")
        f.write("## (point d'appui au sol, px depuis le coin du rect), glow (point chaud). 2 px = 1 unité monde.\n")
        f.write("const PIECES := %s\n" % json.dumps(pieces))
    print("ATLAS", out, atlas.size, len(items), "pièces")


def main() -> None:
    args = sys.argv[1:]
    if "--pack" not in args:
        only = args[args.index("--only") + 1].split(",") if "--only" in args else None
        render_all(only)
    pack()


if __name__ == "__main__":
    main()
