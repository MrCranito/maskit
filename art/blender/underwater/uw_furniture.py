"""Mobilier des gabarits d'aménagement de la station sous-marine (scripts/biomes/underwater/uw_templates.gd)
+ décors muraux (kit_wall_*) et détails au sol (decal_*), ajoutés à l'atlas existant.

Usage (racine du projet) :
    python3 art/blender/underwater/uw_furniture.py               # rend + ré-empaquette l'atlas
    python3 art/blender/underwater/uw_furniture.py --only uw_locker_bank

Les pièces déjà présentes dans assets/sprites/underwater/atlas.png sont reprises telles quelles ;
seules les nouvelles pièces sont rendues (même caméra 48°, même échelle, mêmes ombres).
"""
from __future__ import annotations

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import uw_props as UP  # noqa: E402
from uw_props import BP, C, M, Builder  # noqa: E402,F401

PIECES = UP.PIECES


def p_uw_locker_bank(B: Builder) -> None:
    w, d, h = 1.5, 0.55, 1.9
    for i in range(3):
        x = -w / 2 + (i + 0.5) * w / 3
        B.box("lk%d" % i, (w / 3 - 0.03, d, h), (x, 0, h / 2), M("uw_teal" if i % 2 else "uw_steel"), bevel=0.02)
        for k in range(4):
            B.box("v%d%d" % (i, k), (0.26, 0.02, 0.025), (x, -d / 2 - 0.01, h - 0.2 - k * 0.06), M("uw_rubber"), outline=False)
        B.box("h%d" % i, (0.04, 0.04, 0.14), (x + 0.14, -d / 2 - 0.02, h * 0.55), M("uw_steel_dark"))
    B.box("suit", (0.3, 0.1, 0.6), (0.5, -d / 2 - 0.08, 1.1), M("uw_orange"), bevel=0.05)
    B.sphere("helmet", 0.15, (0.5, -d / 2 - 0.1, 1.55), M("uw_copper"), seg=10, rings=7)


def p_uw_bunk(B: Builder) -> None:
    """Couchette simple avec rideau et étagère."""
    w, d = 1.1, 1.75
    B.box("frame", (w, d, 0.3), (0, 0, 0.35), M("uw_steel_dark"), bevel=0.02)
    B.box("matt", (w - 0.08, d - 0.1, 0.14), (0, 0, 0.56), M("uw_white"), bevel=0.04)
    B.box("blank", (w - 0.04, d * 0.55, 0.12), (0, -d * 0.18, 0.6), M("uw_blue_cloth"), bevel=0.05)
    B.box("pillow", (w * 0.6, 0.3, 0.1), (0, d / 2 - 0.25, 0.68), M("uw_white"), bevel=0.04)
    B.box("head", (w + 0.06, 0.1, 1.2), (0, d / 2, 0.6), M("uw_steel"), bevel=0.02)
    B.box("shelf", (w, 0.25, 0.04), (0, d / 2 - 0.15, 1.15), M("uw_steel_dark"))
    B.box("book", (0.2, 0.15, 0.08), (-0.2, d / 2 - 0.15, 1.21), M("uw_red"))
    B.cyl("lamp", 0.07, 0.07, 0.12, (0.3, d / 2 - 0.15, 1.23), M("uw_lamp"), seg=8)


def p_uw_table(B: Builder) -> None:
    """Petite table de cabine boulonnée + deux tabourets."""
    B.cyl("top", 0.5, 0.5, 0.06, (0, 0, 0.75), M("uw_steel_light"), seg=18)
    B.cyl("ped", 0.07, 0.09, 0.7, (0, 0, 0.36), M("uw_steel_dark"), seg=10)
    B.cyl("foot", 0.3, 0.32, 0.05, (0, 0, 0.03), M("uw_steel_dark"), seg=14)
    for sx in (-0.85, 0.85):
        B.cyl("st%.1f" % sx, 0.2, 0.2, 0.08, (sx, 0, 0.46), M("uw_teal"), seg=12)
        B.cyl("sp%.1f" % sx, 0.04, 0.06, 0.42, (sx, 0, 0.21), M("uw_steel_dark"), seg=8)
    B.cyl("mug", 0.05, 0.045, 0.12, (0.12, -0.1, 0.84), M("uw_orange"), seg=10)
    B.box("chart", (0.4, 0.3, 0.01), (-0.15, 0.05, 0.79), M("uw_paper"), rot=(0, 0, 0.3), outline=False)


def p_uw_shelf(B: Builder) -> None:
    w, d, h = 1.5, 0.55, 1.9
    for sx in (-w / 2, w / 2):
        B.box("up%.1f" % sx, (0.06, d, h), (sx, 0, h / 2), M("uw_steel_dark"))
    rnd = random.Random(13)
    for k in range(4):
        z = 0.1 + k * 0.56
        B.box("sh%d" % k, (w, d, 0.04), (0, 0, z), M("uw_steel"))
        if k == 3:
            continue
        x = -w / 2 + 0.08
        while x < w / 2 - 0.25:
            t = rnd.random()
            if t < 0.45:
                hh = rnd.uniform(0.25, 0.4)
                B.cyl("jar%d%.2f" % (k, x), 0.09, 0.09, hh, (x + 0.09, 0, z + 0.02 + hh / 2), M(rnd.choice(["uw_specimen", "uw_aqua", "uw_steel_light"])), seg=10)
                x += 0.24
            else:
                bw = rnd.uniform(0.28, 0.4)
                bh = rnd.uniform(0.2, 0.35)
                B.box("bx%d%.2f" % (k, x), (bw, d * 0.7, bh), (x + bw / 2, 0, z + 0.02 + bh / 2), M(rnd.choice(["uw_yellow", "uw_white", "uw_orange", "uw_teal"])), bevel=0.02)
                x += bw + 0.05


def p_uw_workbench(B: Builder) -> None:
    w, d, h = 1.6, 0.75, 0.85
    B.box("top", (w, d, 0.08), (0, 0, h), M("uw_wood"), bevel=0.02)
    for sx in (-w / 2 + 0.08, w / 2 - 0.08):
        B.box("leg%.1f" % sx, (0.08, d - 0.1, h), (sx, 0, h / 2), M("uw_steel_dark"))
    B.box("low", (w - 0.2, d - 0.2, 0.04), (0, 0, 0.25), M("uw_steel"))
    B.box("vise", (0.25, 0.2, 0.18), (-0.55, -0.15, h + 0.13), M("uw_steel_dark"), bevel=0.02)
    B.cyl("valve", 0.12, 0.12, 0.05, (0.15, 0.0, h + 0.07), M("uw_red"), seg=12)
    B.box("tools", (0.4, 0.2, 0.06), (0.5, 0.1, h + 0.07), M("uw_orange"), bevel=0.02)
    B.box("pegb", (w, 0.06, 0.9), (0, d / 2, h + 0.5), M("uw_steel_dark"))
    for i in range(4):
        B.box("t%d" % i, (0.05, 0.03, 0.35), (-0.5 + i * 0.32, d / 2 - 0.05, h + 0.55), M("uw_steel_light"), rot=(0, 0.2 * (i - 1.5), 0))
    B.box("lamp", (0.6, 0.15, 0.05), (0, d / 2 - 0.1, h + 1.0), M("uw_lamp"), outline=False)


def p_uw_sample_rack(B: Builder) -> None:
    """Râtelier d'éprouvettes / bocaux d'échantillons lumineux."""
    w, d, h = 1.4, 0.5, 1.6
    B.box("body", (w, d, 0.7), (0, 0, 0.35), M("uw_white"), bevel=0.03)
    B.box("glass", (w - 0.05, d - 0.05, 0.85), (0, 0, 1.13), M("uw_aqua"), bevel=0.02)
    B.box("top", (w + 0.04, d + 0.04, 0.06), (0, 0, h), M("uw_steel"))
    for i in range(6):
        B.cyl("tube%d" % i, 0.06, 0.06, 0.5, (-0.55 + i * 0.22, 0, 1.0), M("uw_specimen" if i % 2 else "uw_grow"), seg=8, outline=False)
    for i in range(3):
        B.box("dr%d" % i, (w / 3 - 0.08, 0.03, 0.5), (-w / 3 + i * w / 3, -d / 2 - 0.01, 0.35), M("uw_steel_light"))


def p_uw_crates(B: Builder) -> None:
    for i, (x, y, z, s, mat) in enumerate(((-0.3, 0.0, 0.32, 0.64, "uw_yellow"), (0.38, -0.05, 0.27, 0.54, "uw_teal"),
                                          (-0.15, 0.05, 0.92, 0.55, "uw_orange"))):
        B.box("c%d" % i, (s, s, s), (x, y, z), M(mat), bevel=0.04)
        B.box("b%d" % i, (s + 0.01, 0.02, 0.08), (x, y - s / 2 - 0.005, z), M("uw_rubber"), outline=False)
    B.tube("net", [(-0.7, -0.3, 0.6), (0, -0.4, 1.2), (0.7, -0.3, 0.6)], [0.02] * 3, M("uw_canvas"))


def p_uw_bench(B: Builder) -> None:
    w = 1.6
    B.box("seat", (w, 0.45, 0.07), (0, 0, 0.45), M("uw_teal"), bevel=0.02)
    for sx in (-w / 2 + 0.2, w / 2 - 0.2):
        B.box("leg%.1f" % sx, (0.08, 0.4, 0.42), (sx, 0, 0.21), M("uw_steel_dark"))
    B.box("back", (w, 0.08, 0.5), (0, 0.22, 0.75), M("uw_teal"), bevel=0.02)


def p_uw_machine(B: Builder) -> None:
    """Groupe électrogène / compresseur compact (salle des machines)."""
    w, d, h = 1.5, 0.9, 1.2
    B.box("body", (w, d, h), (0, 0, h / 2 + 0.1), M("uw_steel"), bevel=0.04)
    B.box("skid", (w + 0.1, d + 0.1, 0.1), (0, 0, 0.05), M("uw_steel_dark"))
    B.cyl("fan", 0.35, 0.35, 0.05, (-0.3, -d / 2 - 0.02, 0.7), M("uw_rubber"), rot=(math.pi / 2, 0, 0), seg=18)
    for k in range(6):
        a = k * math.pi / 3
        B.box("bl%d" % k, (0.06, 0.03, 0.3), (-0.3 + math.cos(a) * 0.15, -d / 2 - 0.04, 0.7 + math.sin(a) * 0.15), M("uw_steel_light"), rot=(0, a, 0), outline=False)
    B.box("panel", (0.4, 0.04, 0.35), (0.45, -d / 2 - 0.01, 0.8), M("uw_steel_dark"))
    B.box("scr", (0.3, 0.02, 0.12), (0.45, -d / 2 - 0.03, 0.88), M("uw_screen"), outline=False)
    B.cyl("pipe", 0.08, 0.08, 1.2, (0.5, 0.2, 1.4), M("uw_copper"), seg=10)
    B.box("hz", (w, 0.02, 0.08), (0, -d / 2 - 0.01, 0.2), M("uw_yellow"), outline=False)


# --- Décors muraux ---------------------------------------------------------------------------------

def k_porthole(B: Builder) -> None:
    B.cyl("ring", 0.33, 0.33, 0.08, (0, 0, 1.05), M("uw_copper"), rot=(math.pi / 2, 0, 0), seg=22)
    B.cyl("glass", 0.27, 0.27, 0.04, (0, -0.04, 1.05), M("uw_aqua"), rot=(math.pi / 2, 0, 0), seg=22, outline=False)
    for k in range(8):
        a = k * math.pi / 4
        B.sphere("bolt%d" % k, 0.03, (math.cos(a) * 0.3, -0.06, 1.05 + math.sin(a) * 0.3), M("uw_steel_dark"), seg=5, rings=3, outline=False)
    B.sphere("fish", 0.05, (0.08, -0.05, 1.1), M("uw_orange"), scale=(1.6, 0.4, 0.8), seg=6, rings=4, outline=False)


def k_gauge(B: Builder) -> None:
    B.box("plate", (0.6, 0.05, 0.4), (0, 0, 1.0), M("uw_steel_dark"), bevel=0.02)
    for i, x in enumerate((-0.15, 0.15)):
        B.cyl("g%d" % i, 0.12, 0.12, 0.05, (x, -0.04, 1.0), M("uw_white"), rot=(math.pi / 2, 0, 0), seg=14)
        B.box("n%d" % i, (0.02, 0.03, 0.1), (x + 0.02, -0.07, 1.03), M("uw_red"), rot=(0, 0.6 - i, 0), outline=False)


def k_chart(B: Builder) -> None:
    B.box("chart", (0.85, 0.03, 0.55), (0, 0, 1.0), M("uw_paper"))
    B.tube("coast", [(-0.35, -0.02, 0.85), (-0.1, -0.02, 1.0), (0.1, -0.02, 0.9), (0.35, -0.02, 1.15)], [0.012] * 4, M("uw_teal"), outline=False)
    for (x, z) in ((-0.2, 1.1), (0.2, 0.9)):
        B.sphere("pin%.1f" % x, 0.025, (x, -0.04, z), M("uw_red"), seg=6, rings=4, outline=False)


def k_valves(B: Builder) -> None:
    B.cyl("pipe", 0.06, 0.06, 1.5, (0, -0.05, 0.85), M("uw_copper"), rot=(0, math.pi / 2, 0), seg=10)
    for i, x in enumerate((-0.4, 0.35)):
        B.cyl("stem%d" % i, 0.03, 0.03, 0.2, (x, -0.05, 0.98), M("uw_steel_dark"), seg=6)
        B.torus("wheel%d" % i, 0.12, 0.02, (x, -0.08, 1.1), M("uw_red"), rot=(math.pi / 2, 0, 0), seg=16, rseg=4)


def k_board(B: Builder) -> None:
    B.box("cork", (0.8, 0.04, 0.5), (0, 0, 1.0), M("uw_wood"), bevel=0.02)
    rnd = random.Random(4)
    for i in range(5):
        B.box("n%d" % i, (0.18, 0.03, 0.15), (-0.25 + (i % 3) * 0.25, -0.03, 1.1 - (i // 3) * 0.22), M(rnd.choice(["uw_paper", "uw_yellow", "uw_white"])), rot=(0, rnd.uniform(-0.2, 0.2), 0))


def k_screen(B: Builder) -> None:
    B.box("f", (0.8, 0.05, 0.5), (0, 0, 1.0), M("uw_steel_dark"), bevel=0.03)
    B.box("s", (0.7, 0.03, 0.4), (0, -0.03, 1.0), M("uw_screen"), outline=False)
    B.tube("wave", [(-0.3, -0.05, 1.0), (-0.15, -0.05, 1.1), (0.0, -0.05, 0.92), (0.15, -0.05, 1.08), (0.3, -0.05, 1.0)], [0.012] * 5, M("uw_led_g"), outline=False)


# --- Détails au sol -----------------------------------------------------------------------------------

def d_papers(B: Builder) -> None:
    rnd = random.Random(2)
    for i in range(4):
        B.box("p%d" % i, (0.3, 0.4, 0.01), (rnd.uniform(-0.25, 0.25), rnd.uniform(-0.2, 0.2), 0.01 * i), M("uw_paper"), rot=(0, 0, rnd.uniform(-1, 1)))


def d_mat(B: Builder) -> None:
    B.box("m", (1.2, 0.8, 0.02), (0, 0, 0.01), M("uw_rubber"), outline=False)
    for k in range(6):
        B.box("l%d" % k, (1.1, 0.05, 0.022), (0, -0.3 + k * 0.12, 0.012), M("uw_steel_dark"), outline=False)


def d_tools(B: Builder) -> None:
    B.box("w", (0.06, 0.4, 0.03), (-0.1, 0, 0.02), M("uw_steel_light"), rot=(0, 0, 0.6))
    B.torus("hose", 0.15, 0.03, (0.15, 0.05, 0.03), M("uw_orange"), seg=14, rseg=4)


FURNITURE = {
    "uw_locker_bank": (p_uw_locker_bank, (110, 130), 1.0), "uw_bunk": (p_uw_bunk, (110, 130), 0.6),
    "uw_table": (p_uw_table, (110, 90), 0.5), "uw_shelf": (p_uw_shelf, (110, 130), 1.0),
    "uw_workbench": (p_uw_workbench, (120, 120), 0.8), "uw_sample_rack": (p_uw_sample_rack, (110, 120), 0.8),
    "uw_crates": (p_uw_crates, (100, 100), 0.6), "uw_bench": (p_uw_bench, (110, 80), 0.5),
    "uw_machine": (p_uw_machine, (120, 140), 0.8),
}
GLOW = {"uw_sample_rack": (0.0, 0.0, 1.1), "uw_workbench": (0.0, 0.3, 1.85), "uw_bunk": (0.3, 0.7, 1.23)}
WALL_KIT = {"porthole": k_porthole, "gauge": k_gauge, "chart": k_chart, "valves": k_valves, "board": k_board, "screen": k_screen}
FLOOR = {"papers": d_papers, "mat": d_mat, "tools": d_tools}


def main() -> None:
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    BP.PIECES = PIECES
    print("pièces reprises de l'atlas :", BP.seed_from_atlas(UP.OUT_DIR, PIECES))
    for k, (fn, fr, tz) in FURNITURE.items():
        if not only or k in only:
            BP.render_piece("prop_" + k, fn, fr, target_z=tz, glow=GLOW.get(k))
    for k, fn in WALL_KIT.items():
        if not only or "kit_wall_" + k in only or "wall" in only:
            BP.render_piece("kit_wall_" + k, fn, (70, 80), target_z=1.0, outline_px=3.5, shadow=False, elev=8.0)
    for k, fn in FLOOR.items():
        if not only or "decal_" + k in only or "floor" in only:
            BP.render_piece("decal_uw_" + k, fn, (60, 60) if k != "mat" else (90, 70), target_z=0.0, flat=True, outline_px=2.5)
    UP.pack()


if __name__ == "__main__":
    main()
