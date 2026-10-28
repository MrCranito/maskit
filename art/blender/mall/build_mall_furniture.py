"""Mobilier des gabarits d'aménagement du centre commercial (scripts/biomes/mall/mall_templates.gd)
+ décors muraux (kit_wall_*) et détails au sol (decal_*), ajoutés à l'atlas existant.

Usage (racine du projet) :
    python3 art/blender/mall/build_mall_furniture.py               # rend + ré-empaquette l'atlas
    python3 art/blender/mall/build_mall_furniture.py --only gondola,shoe_rack

Les pièces déjà présentes dans assets/sprites/mall/atlas.png sont reprises telles quelles ; seules
les nouvelles pièces sont rendues (même caméra 48°, même échelle, mêmes ombres).
"""
from __future__ import annotations

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import build_mall_props as MP  # noqa: E402
from build_mall_props import BP, C, M, Builder  # noqa: E402,F401

PIECES = MP.PIECES


def p_gondola(B: Builder) -> None:
    """Gondole de supermarché double face (rangées d'allées)."""
    w, d, h = 1.7, 0.8, 1.45
    B.box("base", (w, d, 0.16), (0, 0, 0.08), M("metal_dark"))
    B.box("spine", (w, 0.06, h), (0, 0, h / 2), M("white"))
    B.box("cap", (w + 0.04, d * 0.6, 0.06), (0, 0, h), M("red"))
    rnd = random.Random(8)
    for k in range(3):
        z = 0.2 + k * 0.42
        for sy in (-1, 1):
            B.box("sh%d%d" % (k, sy), (w, d / 2 - 0.04, 0.03), (0, sy * d / 4, z), M("chrome"))
            x = -w / 2 + 0.06
            while x < w / 2 - 0.15:
                pw = rnd.uniform(0.1, 0.22)
                ph = rnd.uniform(0.18, 0.32)
                mat = rnd.choice(["red", "yellow", "blue", "green", "orange", "white", "pink", "teal"])
                if rnd.random() < 0.15:
                    x += pw
                    continue
                B.box("p%d%d%.2f" % (k, sy, x), (pw, d / 2 - 0.12, ph), (x + pw / 2, sy * d / 4, z + 0.02 + ph / 2), M(mat), bevel=0.01)
                x += pw + 0.02
    B.box("price", (w, 0.02, 0.05), (0, -d / 2 + 0.02, 0.24), M("yellow"), outline=False)


def p_shoe_rack(B: Builder) -> None:
    w, d, h = 1.6, 0.5, 1.6
    B.box("back", (w, 0.06, h), (0, d / 2, h / 2), M("wood"))
    rnd = random.Random(5)
    for k in range(4):
        z = 0.15 + k * 0.38
        B.box("sh%d" % k, (w, d, 0.04), (0, 0, z), M("white"), rot=(0.18, 0, 0))
        for i in range(4):
            x = -0.6 + i * 0.4
            mat = rnd.choice(["red", "black", "white", "blue", "orange"])
            B.box("sh%d%d" % (k, i), (0.14, 0.3, 0.1), (x - 0.08, -0.02, z + 0.08), M(mat), bevel=0.04)
            B.box("sh%d%db" % (k, i), (0.14, 0.3, 0.1), (x + 0.08, -0.02, z + 0.08), M(mat), bevel=0.04)


def p_display_table(B: Builder) -> None:
    """Table de présentation (vêtements pliés, livres, gadgets)."""
    w, d, h = 1.5, 0.9, 0.8
    B.box("top", (w, d, 0.08), (0, 0, h), M("wood"), bevel=0.02)
    B.box("base", (w - 0.2, d - 0.2, h - 0.08), (0, 0, (h - 0.08) / 2), M("white"))
    rnd = random.Random(2)
    for i in range(6):
        x = -0.5 + (i % 3) * 0.5
        y = -0.2 + (i // 3) * 0.4
        mat = rnd.choice(["cloth_red", "cloth_blue", "cloth_cream", "pink", "teal"])
        for k in range(rnd.randint(2, 4)):
            B.box("f%d%d" % (i, k), (0.36, 0.28, 0.05), (x, y, h + 0.07 + k * 0.055), M(mat), bevel=0.01, outline=k == 0)
    B.box("sign", (0.3, 0.03, 0.2), (0.6, -0.4, h + 0.15), M("yellow"), rot=(-0.3, 0, 0))


def p_food_counter(B: Builder) -> None:
    """Comptoir de restauration : vitrine chauffante, caisse, menus lumineux."""
    w, d, h = 2.4, 0.8, 1.05
    B.box("body", (w, d, h), (0, 0, h / 2), M("red"), bevel=0.02)
    B.box("top", (w + 0.08, d + 0.08, 0.06), (0, 0, h + 0.03), M("chrome"))
    B.box("glass", (1.2, 0.5, 0.35), (-0.4, 0, h + 0.22), M("glass_dark"), bevel=0.03)
    for i in range(4):
        B.box("food%d" % i, (0.22, 0.3, 0.1), (-0.85 + i * 0.3, 0, h + 0.12), M(["yellow", "orange", "rust", "yellow"][i]), bevel=0.04, outline=False)
    B.box("reg", (0.4, 0.35, 0.25), (0.8, 0.0, h + 0.16), M("metal_dark"), bevel=0.02)
    B.box("regs", (0.3, 0.03, 0.15), (0.8, -0.1, h + 0.33), M("screen"), rot=(-0.4, 0, 0), outline=False)
    for i in range(3):
        B.box("menu%d" % i, (0.65, 0.05, 0.4), (-0.75 + i * 0.75, d / 2 + 0.2, 2.15), M("screen_pink" if i == 1 else "screen"), outline=False)
    B.box("menub", (2.4, 0.08, 0.5), (0, d / 2 + 0.25, 2.15), M("black"))
    for sx in (-1.1, 1.1):
        B.box("post%.1f" % sx, (0.08, 0.08, 1.0), (sx, d / 2 + 0.25, 1.6), M("chrome"))
    B.box("stripe", (w, 0.02, 0.1), (0, -d / 2 - 0.01, 0.75), M("yellow"), outline=False)


def p_office_desk(B: Builder) -> None:
    w, d, h = 1.5, 0.75, 0.78
    B.box("top", (w, d, 0.06), (0, 0, h), M("wood"), bevel=0.02)
    B.box("ped", (0.45, d - 0.1, h - 0.05), (w / 2 - 0.3, 0, (h - 0.05) / 2), M("metal"))
    B.box("leg", (0.06, d - 0.1, h), (-w / 2 + 0.06, 0, h / 2), M("metal_dark"))
    B.box("mon", (0.6, 0.05, 0.38), (-0.1, 0.22, h + 0.3), M("black"), bevel=0.02)
    B.box("mons", (0.52, 0.02, 0.3), (-0.1, 0.19, h + 0.3), M("screen"), outline=False)
    B.box("kbd", (0.45, 0.16, 0.03), (-0.1, -0.12, h + 0.04), M("black"))
    B.box("papers", (0.3, 0.4, 0.04), (0.5, 0.0, h + 0.05), M("paper"), rot=(0, 0, 0.2))
    B.cyl("chair", 0.24, 0.24, 0.1, (0, -0.65, 0.48), M("black"), seg=12)
    B.box("chairb", (0.44, 0.08, 0.5), (0, -0.88, 0.8), M("black"), bevel=0.04)


def p_stock_rack(B: Builder) -> None:
    """Rayonnage de réserve (cartons empilés)."""
    w, d, h = 1.7, 0.7, 2.0
    for sx in (-w / 2, w / 2):
        for sy in (-d / 2, d / 2):
            B.box("up%.1f%.1f" % (sx, sy), (0.06, 0.06, h), (sx, sy, h / 2), M("orange"))
    rnd = random.Random(11)
    for k in range(4):
        z = 0.1 + k * 0.6
        B.box("sh%d" % k, (w, d, 0.04), (0, 0, z), M("metal"))
        if k == 3:
            continue
        x = -w / 2 + 0.06
        while x < w / 2 - 0.3:
            bw = rnd.uniform(0.32, 0.5)
            bh = rnd.uniform(0.3, 0.5)
            B.box("bx%d%.2f" % (k, x), (bw, d - 0.12, bh), (x + bw / 2, 0, z + 0.02 + bh / 2), M("cardboard"), bevel=0.01)
            B.box("tp%d%.2f" % (k, x), (bw, 0.02, 0.05), (x + bw / 2, -d / 2 + 0.05, z + 0.02 + bh * 0.7), M("paper"), outline=False)
            x += bw + 0.04


def p_glass_case(B: Builder) -> None:
    """Vitrine-comptoir de bijouterie / parfumerie."""
    w, d, h = 1.5, 0.6, 1.0
    B.box("base", (w, d, 0.5), (0, 0, 0.25), M("wood_dark"), bevel=0.02)
    B.box("glass", (w - 0.04, d - 0.04, 0.45), (0, 0, 0.73), M("glass_dark"), bevel=0.01)
    B.box("top", (w + 0.04, d + 0.04, 0.03), (0, 0, 0.96), M("chrome"))
    rnd = random.Random(3)
    for i in range(6):
        x = -0.55 + i * 0.22
        B.box("cush%d" % i, (0.14, 0.14, 0.04), (x, 0, 0.53), M("cloth_red"), outline=False)
        if rnd.random() < 0.8:
            B.sphere("gem%d" % i, 0.04, (x, 0, 0.6), M(rnd.choice(["gold", "neon_cyan", "neon_pink"])), seg=6, rings=4, outline=False)
    B.box("lamp", (w - 0.1, 0.03, 0.02), (0, 0, 0.92), M("lamp"), outline=False, shadow=False)


def p_bookshelf(B: Builder) -> None:
    w, d, h = 1.6, 0.45, 2.0
    B.box("back", (w, 0.06, h), (0, d / 2, h / 2), M("wood_dark"))
    for sx in (-w / 2, w / 2):
        B.box("side%.1f" % sx, (0.08, d, h), (sx, 0, h / 2), M("wood"))
    rnd = random.Random(31)
    for k in range(4):
        z = 0.1 + k * 0.48
        B.box("sh%d" % k, (w, d, 0.04), (0, 0, z), M("wood"))
        x = -w / 2 + 0.08
        while x < w / 2 - 0.12:
            bw = rnd.uniform(0.06, 0.1)
            bh = rnd.uniform(0.28, 0.4)
            B.box("b%d%.2f" % (k, x), (bw, d * 0.7, bh), (x + bw / 2, -0.02, z + 0.02 + bh / 2),
                  M(rnd.choice(["red", "blue", "green", "yellow", "white", "black", "violet"])))
            x += bw + 0.01
    B.box("sign", (0.6, 0.04, 0.16), (0, -d / 2, h + 0.1), M("yellow"))


def p_mall_sofa(B: Builder) -> None:
    w, d = 2.0, 0.8
    B.box("seat", (w, d, 0.28), (0, 0, 0.42), M("teal"), bevel=0.08)
    B.box("back", (w, 0.22, 0.6), (0, d / 2 - 0.1, 0.78), M("teal"), bevel=0.08)
    for sx in (-w / 2, w / 2):
        B.box("arm%.1f" % sx, (0.2, d, 0.5), (sx, 0, 0.5), M("teal"), bevel=0.08)
    B.box("base", (w + 0.05, d, 0.12), (0, 0, 0.18), M("metal_dark"))


def p_tray_cart(B: Builder) -> None:
    B.box("frame", (0.8, 0.55, 1.1), (0, 0, 0.6), M("chrome"))
    for k in range(4):
        B.box("tray%d" % k, (0.75, 0.5, 0.03), (0, 0, 0.3 + k * 0.25), M("orange"))
    for sx in (-0.35, 0.35):
        for sy in (-0.22, 0.22):
            B.cyl("w%.1f%.1f" % (sx, sy), 0.05, 0.05, 0.04, (sx, sy, 0.05), M("tire"), rot=(math.pi / 2, 0, 0), seg=8)


# --- Décors muraux -------------------------------------------------------------------------------

def k_poster(B: Builder) -> None:
    B.box("frame", (0.6, 0.05, 0.85), (0, 0, 1.0), M("black"))
    B.box("img", (0.52, 0.03, 0.75), (0, -0.03, 1.0), M("pink"), outline=False)
    B.box("txt", (0.4, 0.035, 0.12), (0, -0.04, 1.25), M("white"), outline=False)
    B.box("pct", (0.24, 0.035, 0.24), (0.05, -0.04, 0.9), M("yellow"), outline=False)


def k_sale(B: Builder) -> None:
    B.box("sign", (0.8, 0.04, 0.35), (0, 0, 1.15), M("red"), bevel=0.02)
    B.box("txt", (0.6, 0.045, 0.12), (0, -0.02, 1.15), M("white"), outline=False)


def k_clock(B: Builder) -> None:
    B.cyl("face", 0.25, 0.25, 0.06, (0, 0, 1.15), M("white"), rot=(math.pi / 2, 0, 0), seg=20)
    B.torus("rim", 0.25, 0.03, (0, 0, 1.15), M("metal_dark"), rot=(math.pi / 2, 0, 0), seg=20, rseg=5)
    B.box("h1", (0.025, 0.05, 0.16), (0, -0.04, 1.2), M("black"), outline=False)
    B.box("h2", (0.12, 0.05, 0.025), (0.05, -0.04, 1.15), M("black"), outline=False)


def k_shelf(B: Builder) -> None:
    B.box("sh", (1.1, 0.25, 0.04), (0, -0.1, 1.0), M("white"))
    rnd = random.Random(7)
    for i in range(6):
        B.box("p%d" % i, (0.12, 0.15, rnd.uniform(0.15, 0.28)), (-0.45 + i * 0.18, -0.1, 1.12), M(rnd.choice(["pink", "teal", "yellow", "violet", "white"])), bevel=0.02)


def k_tv(B: Builder) -> None:
    B.box("tv", (0.9, 0.06, 0.52), (0, 0, 1.05), M("black"), bevel=0.02)
    B.box("scr", (0.82, 0.03, 0.44), (0, -0.03, 1.05), M("screen"), outline=False)
    B.box("bar", (0.5, 0.035, 0.06), (-0.1, -0.04, 1.12), M("screen_pink"), outline=False)


def k_board(B: Builder) -> None:
    B.box("cork", (0.85, 0.04, 0.55), (0, 0, 1.0), M("cardboard"), bevel=0.02)
    rnd = random.Random(9)
    for i in range(5):
        B.box("n%d" % i, (0.2, 0.03, 0.16), (-0.28 + (i % 3) * 0.28, -0.03, 1.12 - (i // 3) * 0.24), M(rnd.choice(["paper", "yellow", "pink"])), rot=(0, rnd.uniform(-0.2, 0.2), 0))


# --- Détails au sol ---------------------------------------------------------------------------------

def d_tray(B: Builder) -> None:
    B.box("t", (0.45, 0.32, 0.02), (0, 0, 0.01), M("orange"), rot=(0, 0, 0.3))
    B.cyl("cup", 0.06, 0.05, 0.12, (0.1, 0.05, 0.08), M("red"), seg=10)
    B.box("fries", (0.12, 0.08, 0.1), (-0.1, -0.03, 0.06), M("yellow"))


def d_clothes(B: Builder) -> None:
    B.box("c1", (0.5, 0.35, 0.03), (0, 0, 0.015), M("cloth_blue"), rot=(0, 0, 0.5), bevel=0.01)
    B.box("c2", (0.4, 0.3, 0.03), (0.2, 0.15, 0.03), M("cloth_red"), rot=(0, 0, -0.4), bevel=0.01)


def d_boxes(B: Builder) -> None:
    B.box("b1", (0.4, 0.3, 0.15), (-0.1, 0, 0.07), M("cardboard"), rot=(0, 0, 0.3))
    B.box("b2", (0.3, 0.25, 0.04), (0.25, 0.15, 0.02), M("cardboard"), rot=(0, 0, -0.2))


def d_rug(B: Builder) -> None:
    B.box("r", (1.5, 1.0, 0.02), (0, 0, 0.01), M("violet"), outline=False)
    B.box("in", (1.3, 0.8, 0.022), (0, 0, 0.012), M("pink"), outline=False)
    B.box("in2", (1.1, 0.6, 0.024), (0, 0, 0.014), M("violet"), outline=False)


FURNITURE = {
    "gondola": (p_gondola, (130, 110), 0.7), "shoe_rack": (p_shoe_rack, (120, 120), 0.8),
    "display_table": (p_display_table, (120, 100), 0.5), "food_counter": (p_food_counter, (170, 160), 1.0),
    "office_desk": (p_office_desk, (120, 110), 0.6), "stock_rack": (p_stock_rack, (130, 140), 1.0),
    "glass_case": (p_glass_case, (110, 90), 0.5), "bookshelf": (p_bookshelf, (120, 140), 1.0),
    "mall_sofa": (p_mall_sofa, (120, 90), 0.5), "tray_cart": (p_tray_cart, (70, 90), 0.6),
}
GLOW = {"food_counter": (0.0, 0.6, 2.15), "glass_case": (0.0, 0.0, 0.92), "office_desk": (-0.1, 0.2, 1.1)}
WALL_KIT = {"poster": k_poster, "sale": k_sale, "clock": k_clock, "shelf": k_shelf, "tv": k_tv, "board": k_board}
FLOOR = {"tray": d_tray, "clothes": d_clothes, "boxes": d_boxes, "rug": d_rug}


def main() -> None:
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    MP._use_dir(PIECES)
    print("pièces reprises de l'atlas :", BP.seed_from_atlas(MP.OUT_DIR, PIECES))
    for k, (fn, fr, tz) in FURNITURE.items():
        if not only or k in only:
            BP.render_piece("prop_" + k, fn, fr, target_z=tz, glow=GLOW.get(k))
    for k, fn in WALL_KIT.items():
        if not only or "kit_wall_" + k in only or "wall" in only:
            BP.render_piece("kit_wall_" + k, fn, (70, 80), target_z=1.0, outline_px=3.5, shadow=False, elev=8.0)
    for k, fn in FLOOR.items():
        if not only or "decal_" + k in only or "floor" in only:
            BP.render_piece("decal_" + k, fn, (60, 60) if k != "rug" else (100, 70), target_z=0.0, flat=True, outline_px=2.5)
    MP.pack()


if __name__ == "__main__":
    main()
