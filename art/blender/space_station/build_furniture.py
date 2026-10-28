"""Mobilier des gabarits d'aménagement de la Station Orbitale (scripts/biomes/space_station/ss_templates.gd)
+ décors muraux (kit_wall_*) et détails au sol (decal_*), ajoutés à l'atlas existant.

Usage (racine du projet) :
    python3 art/blender/space_station/build_furniture.py            # rend + ré-empaquette l'atlas
    python3 art/blender/space_station/build_furniture.py --only locker_bank,desk_station

Les pièces déjà présentes dans assets/sprites/space_station/atlas.png sont reprises telles quelles
(aucune source requise) ; seules les nouvelles pièces sont rendues (même caméra 48°, même échelle,
mêmes ombres que build_props.py).
"""
from __future__ import annotations

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from ss_art import C, FP, M, Builder, TMP, ROOT, hazard_band, set_pieces_dir, _load  # noqa: E402,F401

# build_props.py du biome (atlas, pack, screen, led_row), chargé par chemin (même nom que celui du Far West).
SP = _load("ss_build_props", os.path.join(HERE, "build_props.py"))

OUT_DIR = os.path.join(ROOT, "assets", "sprites", "space_station")
PIECES = os.path.join(TMP, "pieces")


def p_desk_station(B: Builder) -> None:
    """Poste de travail : bureau, double écran, fauteuil."""
    w, d, h = 1.5, 0.75, 0.78
    B.box("top", (w, d, 0.06), (0, 0, h), M("white_panel"), bevel=0.02)
    B.box("ped", (0.45, d - 0.1, h - 0.05), (w / 2 - 0.3, 0, (h - 0.05) / 2), M("steel"))
    B.box("leg", (0.06, d - 0.1, h), (-w / 2 + 0.06, 0, h / 2), M("steel_dark"))
    for i, x in enumerate((-0.35, 0.3)):
        SP.screen(B, "scr%d" % i, 0.5, 0.32, (x, 0.22, h + 0.32), "screen_cyan" if i == 0 else "screen_green")
        B.box("st%d" % i, (0.05, 0.05, 0.16), (x, 0.26, h + 0.1), M("gunmetal"))
    B.box("kbd", (0.5, 0.18, 0.03), (-0.05, -0.12, h + 0.04), M("rubber"))
    B.cyl("mug", 0.05, 0.045, 0.11, (0.55, -0.15, h + 0.08), M("orange"), seg=10)
    B.cyl("chairb", 0.24, 0.24, 0.1, (0, -0.65, 0.48), M("navy"), seg=12)
    B.box("chairbk", (0.44, 0.08, 0.5), (0, -0.88, 0.8), M("navy"), bevel=0.04)
    B.cyl("chairp", 0.04, 0.04, 0.4, (0, -0.65, 0.22), M("gunmetal"), seg=8)


def p_locker_bank(B: Builder) -> None:
    w, d, h = 1.6, 0.55, 1.95
    for i in range(3):
        x = -w / 2 + (i + 0.5) * w / 3
        B.box("lk%d" % i, (w / 3 - 0.03, d, h), (x, 0, h / 2), M("navy" if i % 2 else "steel"), bevel=0.02)
        for k in range(5):
            B.box("v%d%d" % (i, k), (0.28, 0.02, 0.025), (x, -d / 2 - 0.01, h - 0.2 - k * 0.06), M("rubber"), outline=False)
        B.box("h%d" % i, (0.04, 0.04, 0.14), (x + 0.15, -d / 2 - 0.02, h * 0.55), M("steel_dark"))
        B.box("tag%d" % i, (0.16, 0.02, 0.07), (x, -d / 2 - 0.012, h * 0.75), M("white_panel"), outline=False)
    B.box("bench", (w, 0.34, 0.06), (0, -d / 2 - 0.35, 0.44), M("teal"), bevel=0.02)
    for sx in (-w / 2 + 0.15, w / 2 - 0.15):
        B.box("bl%.1f" % sx, (0.06, 0.3, 0.42), (sx, -d / 2 - 0.35, 0.21), M("steel_dark"))


def p_supply_shelf(B: Builder) -> None:
    w, d, h = 1.6, 0.6, 2.0
    for sx in (-w / 2, w / 2):
        B.box("up%.1f" % sx, (0.06, d, h), (sx, 0, h / 2), M("steel_dark"))
    rnd = random.Random(21)
    for k in range(4):
        z = 0.12 + k * 0.6
        B.box("sh%d" % k, (w, d, 0.04), (0, 0, z), M("steel"))
        if k == 3:
            continue
        x = -w / 2 + 0.1
        while x < w / 2 - 0.3:
            sw = rnd.uniform(0.25, 0.42)
            sh = rnd.uniform(0.2, 0.42)
            mat = rnd.choice(["orange", "white_panel", "olive", "teal", "navy"])
            B.box("bx%d%.2f" % (k, x), (sw, d * 0.75, sh), (x + sw / 2, 0, z + 0.02 + sh / 2), M(mat), bevel=0.02)
            x += sw + 0.05
    hazard_band(B, "hz", w - 0.1, (0, -d / 2 - 0.01, 0.05), h=0.06, n=6)


def p_crew_table(B: Builder) -> None:
    """Table ronde de détente et trois tabourets."""
    B.cyl("top", 0.6, 0.6, 0.06, (0, 0, 0.76), M("white_panel"), seg=24)
    B.cyl("edge", 0.62, 0.62, 0.03, (0, 0, 0.72), M("teal"), seg=24)
    B.cyl("ped", 0.08, 0.1, 0.7, (0, 0, 0.36), M("steel_dark"), seg=10)
    B.cyl("foot", 0.35, 0.38, 0.05, (0, 0, 0.03), M("steel_dark"), seg=16)
    for a in (0.7, 2.6, 4.6):
        x, y = math.cos(a) * 0.95, math.sin(a) * 0.8
        B.cyl("st%.1f" % a, 0.2, 0.2, 0.08, (x, y, 0.48), M("orange"), seg=12)
        B.cyl("sp%.1f" % a, 0.04, 0.06, 0.44, (x, y, 0.22), M("steel_dark"), seg=8)
    B.cyl("cup", 0.05, 0.045, 0.12, (0.15, -0.1, 0.86), M("orange"), seg=10)
    B.box("pad", (0.3, 0.22, 0.02), (-0.2, 0.1, 0.8), M("screen_cyan"), outline=False, rot=(0, 0, 0.4))


def p_med_cabinet_wall(B: Builder) -> None:
    w, d, h = 1.3, 0.45, 1.9
    B.box("body", (w, d, h), (0, 0, h / 2), M("white_panel"), bevel=0.03)
    B.box("glass", (w - 0.16, 0.02, 0.9), (0, -d / 2 - 0.01, 1.35), M("glass_dark"), outline=False)
    rnd = random.Random(4)
    for k in range(2):
        for i in range(5):
            B.cyl("b%d%d" % (k, i), 0.05, 0.05, 0.16, (-0.45 + i * 0.22, -0.08, 1.0 + k * 0.42), M(rnd.choice(["liquid_green", "red", "white_panel", "orange"])), seg=8, outline=False)
    B.box("cross_v", (0.08, 0.02, 0.3), (0, -d / 2 - 0.02, 0.5), M("red"), outline=False)
    B.box("cross_h", (0.3, 0.02, 0.08), (0, -d / 2 - 0.02, 0.5), M("red"), outline=False)


def p_tool_wall(B: Builder) -> None:
    w, h = 1.6, 1.8
    B.box("board", (w, 0.08, h), (0, 0.1, h / 2 + 0.2), M("gunmetal"), bevel=0.02)
    for k in range(6):
        for i in range(7):
            B.cyl("hole%d%d" % (k, i), 0.015, 0.015, 0.02, (-0.6 + i * 0.2, 0.05, 0.5 + k * 0.25), M("rubber"), rot=(math.pi / 2, 0, 0), seg=4, outline=False)
    B.box("wrench", (0.07, 0.03, 0.55), (-0.5, 0.03, 1.2), M("steel"), rot=(0, 0.3, 0))
    B.box("drill", (0.3, 0.12, 0.18), (0.1, 0.0, 1.4), M("orange"), bevel=0.03)
    B.box("drillh", (0.1, 0.1, 0.25), (0.05, 0.0, 1.22), M("rubber"))
    B.torus("cable", 0.18, 0.035, (0.5, 0.0, 1.1), M("hazard"), rot=(math.pi / 2, 0, 0), seg=16, rseg=5)
    B.box("bin", (1.4, 0.4, 0.4), (0, -0.15, 0.2), M("navy"), bevel=0.03)


def p_crate_pallet(B: Builder) -> None:
    B.box("pallet", (1.5, 1.2, 0.14), (0, 0, 0.07), M("steel_dark"))
    for i, (x, y, s, mat) in enumerate(((-0.35, -0.2, 0.62, "orange"), (0.35, -0.15, 0.58, "olive"), (0.0, 0.25, 0.6, "white_panel"), (-0.15, -0.1, 0.5, "navy"))):
        z = 0.14 + s / 2 + (0.6 if i == 3 else 0.0)
        B.box("c%d" % i, (s, s, s), (x, y, z), M(mat), bevel=0.03)
        B.box("st%d" % i, (s + 0.01, 0.02, 0.08), (x, y - s / 2 - 0.005, z), M("hazard", rim=0.0), outline=False)
    B.tube("strap", [(-0.75, -0.6, 0.6), (0, -0.62, 0.8), (0.75, -0.6, 0.6)], [0.02] * 3, M("hazard"))


def p_bio_bed(B: Builder) -> None:
    """Capsule de sommeil murale (couchette fermée)."""
    w, d, h = 1.4, 1.7, 1.1
    B.box("shell", (w, d, h), (0, 0, h / 2), M("white_panel"), bevel=0.12)
    B.box("hole", (w - 0.25, 0.04, h - 0.35), (0, -d / 2 - 0.01, h / 2 + 0.05), M("glass_dark"), outline=False)
    B.box("matt", (w - 0.3, d - 0.3, 0.12), (0, 0.0, 0.35), M("mattress"), bevel=0.04)
    B.box("blank", (w - 0.3, d * 0.5, 0.12), (0, -0.25, 0.4), M("cloth_blue"), bevel=0.04)
    B.box("lamp", (0.5, 0.03, 0.05), (0, -d / 2 - 0.02, h - 0.12), M("neon_white"), outline=False, shadow=False)
    SP.led_row(B, "led", 0.35, 0.6, -d / 2 - 0.02, 0.2, 3)


def p_ss_planter(B: Builder) -> None:
    B.cyl("pot", 0.3, 0.24, 0.5, (0, 0, 0.25), M("white_panel"), seg=14)
    B.cyl("soil", 0.27, 0.27, 0.03, (0, 0, 0.5), M("soil"), seg=14, outline=False)
    rnd = random.Random(3)
    for k in range(9):
        a = rnd.uniform(0, 6.28)
        B.sphere("lf%d" % k, 0.18, (math.cos(a) * 0.15, math.sin(a) * 0.12, 0.75 + rnd.uniform(0, 0.4)), M("plant" if k % 2 else "plant_dark"), scale=(1.2, 1.0, 0.7), seg=8, rings=5)


def p_ss_chair(B: Builder) -> None:
    B.cyl("seat", 0.25, 0.25, 0.09, (0, 0, 0.5), M("navy"), seg=12)
    B.box("back", (0.45, 0.08, 0.55), (0, 0.24, 0.82), M("navy"), bevel=0.05)
    B.cyl("post", 0.04, 0.04, 0.45, (0, 0, 0.25), M("gunmetal"), seg=8)
    for a in range(5):
        an = a * 2 * math.pi / 5
        B.box("leg%d" % a, (0.3, 0.05, 0.04), (math.cos(an) * 0.15, math.sin(an) * 0.15, 0.04), M("gunmetal"), rot=(0, 0, an))


# --- Décors muraux (plaqués sur la face avant des murs, vus presque de face) --------------------

def k_screen(B: Builder) -> None:
    SP.screen(B, "s", 0.8, 0.5, (0, 0, 1.0), "screen_cyan")
    B.box("bar1", (0.5, 0.03, 0.04), (-0.05, -0.04, 1.1), M("neon_white"), outline=False)
    B.box("bar2", (0.35, 0.03, 0.04), (-0.12, -0.04, 1.0), M("screen_amber"), outline=False)
    B.box("bar3", (0.6, 0.03, 0.04), (0.0, -0.04, 0.9), M("neon_white"), outline=False)


def k_vent(B: Builder) -> None:
    B.box("frame", (0.7, 0.06, 0.5), (0, 0, 0.95), M("steel_dark"), bevel=0.02)
    for k in range(6):
        B.box("sl%d" % k, (0.6, 0.04, 0.03), (0, -0.04, 0.78 + k * 0.07), M("rubber"), outline=False)


def k_sign(B: Builder) -> None:
    B.box("plate", (0.8, 0.04, 0.3), (0, 0, 1.15), M("hazard"), bevel=0.02)
    B.box("arrow", (0.4, 0.05, 0.08), (-0.05, -0.02, 1.15), M("rubber"), outline=False)
    B.box("tip", (0.12, 0.05, 0.12), (0.18, -0.02, 1.15), M("rubber"), rot=(0, math.pi / 4, 0), outline=False)


def k_panel(B: Builder) -> None:
    B.box("box", (0.6, 0.1, 0.6), (0, 0, 0.95), M("steel"), bevel=0.03)
    SP.led_row(B, "led", -0.2, 0.2, -0.06, 1.12, 5)
    for i in range(3):
        B.box("sw%d" % i, (0.08, 0.05, 0.14), (-0.15 + i * 0.15, -0.06, 0.88), M("red" if i == 1 else "rubber"), outline=False)


def k_window(B: Builder) -> None:
    B.box("frame", (0.9, 0.06, 0.55), (0, 0, 1.0), M("gunmetal"), bevel=0.06)
    B.box("glass", (0.78, 0.03, 0.44), (0, -0.03, 1.0), M("core_blue"), outline=False)
    for (x, z) in ((-0.25, 1.1), (0.1, 0.92), (0.3, 1.15), (-0.05, 1.18)):
        B.sphere("star%.1f" % x, 0.018, (x, -0.05, z), M("neon_white"), seg=5, rings=3, outline=False, shadow=False)


def k_pipes(B: Builder) -> None:
    for i, (z, mat) in enumerate(((0.75, "copper"), (0.9, "steel"), (1.05, "hazard"))):
        B.cyl("p%d" % i, 0.05, 0.05, 1.6, (0, -0.05, z), M(mat), rot=(0, math.pi / 2, 0), seg=10)
    B.cyl("valve", 0.1, 0.1, 0.04, (0.3, -0.12, 0.9), M("red"), rot=(math.pi / 2, 0, 0), seg=12)


# --- Détails au sol (vue de dessus) --------------------------------------------------------------

def d_tablet(B: Builder) -> None:
    B.box("t", (0.3, 0.4, 0.02), (0, 0, 0.01), M("gunmetal"), rot=(0, 0, 0.4))
    B.box("s", (0.26, 0.34, 0.025), (0, 0, 0.015), M("screen_cyan"), rot=(0, 0, 0.4), outline=False)
    B.box("p", (0.3, 0.4, 0.01), (0.3, -0.15, 0.005), M("white_panel"), rot=(0, 0, -0.3))


def d_mat(B: Builder) -> None:
    B.box("m", (1.3, 0.9, 0.02), (0, 0, 0.01), M("navy"), outline=False)
    B.box("b", (1.2, 0.8, 0.022), (0, 0, 0.012), M("steel_dark"), outline=False)
    for k in range(5):
        B.box("l%d" % k, (1.1, 0.04, 0.024), (0, -0.3 + k * 0.15, 0.014), M("teal"), outline=False)


def d_tools(B: Builder) -> None:
    B.box("w", (0.06, 0.4, 0.03), (-0.1, 0, 0.02), M("steel"), rot=(0, 0, 0.6))
    B.box("s", (0.05, 0.3, 0.03), (0.15, 0.05, 0.02), M("orange"), rot=(0, 0, -0.4))
    B.cyl("b", 0.05, 0.05, 0.03, (0.05, -0.2, 0.02), M("steel_dark"), seg=8)


FURNITURE = {
    "desk_station": (p_desk_station, (130, 120), 0.6), "locker_bank": (p_locker_bank, (120, 140), 1.0),
    "supply_shelf": (p_supply_shelf, (120, 140), 1.0), "crew_table": (p_crew_table, (130, 110), 0.5),
    "med_cabinet_wall": (p_med_cabinet_wall, (100, 140), 1.0), "tool_wall": (p_tool_wall, (120, 130), 0.9),
    "crate_pallet": (p_crate_pallet, (120, 120), 0.6), "bio_bed": (p_bio_bed, (120, 120), 0.6),
    "ss_planter": (p_ss_planter, (70, 100), 0.6), "ss_chair": (p_ss_chair, (60, 80), 0.5),
}
GLOW = {"desk_station": (0.0, 0.22, 1.1), "bio_bed": (0.0, -0.85, 1.0), "crew_table": (-0.2, 0.1, 0.8)}
WALL_KIT = {"screen": k_screen, "vent": k_vent, "sign": k_sign, "panel": k_panel, "window": k_window, "pipes": k_pipes}
FLOOR = {"tablet": d_tablet, "mat": d_mat, "tools": d_tools}


def main() -> None:
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    set_pieces_dir(PIECES)
    print("pièces reprises de l'atlas :", FP.seed_from_atlas(OUT_DIR, PIECES))
    for k, (fn, fr, tz) in FURNITURE.items():
        if not only or k in only:
            FP.render_piece("prop_" + k, fn, fr, target_z=tz, glow=GLOW.get(k), outline_px=4.5)
    for k, fn in WALL_KIT.items():
        if not only or "kit_wall_" + k in only or "wall" in only:
            FP.render_piece("kit_wall_" + k, fn, (70, 80), target_z=1.0, outline_px=3.5, shadow=False, elev=8.0)
    for k, fn in FLOOR.items():
        if not only or "decal_" + k in only or "floor" in only:
            FP.render_piece("decal_" + k, fn, (60, 60) if k != "mat" else (90, 70), target_z=0.0, flat=True, outline_px=2.5)
    SP.pack()


if __name__ == "__main__":
    main()
