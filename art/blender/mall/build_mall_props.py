"""Décors, conteneurs et cachettes du centre commercial en 3D « toon peint » + atlas.

Même pipeline, même caméra (orthographique plongée 48°), même échelle (2 px par unité monde,
1 BU = 36 unités monde) et mêmes ombres portées bleu nuit que les décors Far West
(fonctions réutilisées de art/blender/build_props.py, sans modifier ce fichier).

Usage (depuis la racine du projet, après build_mall_tiles.py qui produit les décalques) :
    python3 art/blender/mall/build_mall_props.py                 # tout
    python3 art/blender/mall/build_mall_props.py --only bench,car_wreck   # quelques pièces
    python3 art/blender/mall/build_mall_props.py --pack          # ré-empaqueter seulement

Sorties :
  assets/sprites/mall/atlas.png + atlas_meta.gd   (décors prop_<kind>, décalques decal_<nom>, glow, white)
  assets/sprites/mall/containers/<kind>.png, <kind>_open.png, hide_<kind>.png
      (dimensions puissances de 2, pieds en bas au centre ; densité 1/0.55 px par unité monde :
       LootContainer/HidingSpot les affichent à l'échelle 0.55)
"""
from __future__ import annotations

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import rdm_common as C  # noqa: E402
import build_props as BP  # noqa: E402
import bpy  # noqa: E402,F401

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "mall")
CONT_DIR = os.path.join(OUT_DIR, "containers")
TMP = os.environ.get("RDM_TMP", "/tmp/rdm_mall")
PIECES = os.path.join(TMP, "pieces")
CPIECES = os.path.join(TMP, "cpieces")
DECALS = os.path.join(TMP, "decals")
CONTAINER_SCALE = 0.55   # échelle d'affichage des sprites de conteneurs en jeu

PAL = {
    "cream_stone": ("#e6d2b4", "#8a7a92", "#fff0d8"),
    "pink_stone": ("#d49a8c", "#6a4a6a", "#f8c0a8"),
    "water": ("#5ab0c8", "#245078", "#a8e8f0"),
    "leaf": ("#5e9a48", "#1e4448", "#9ad06a"),
    "leaf_dark": ("#3e7038", "#163238", "#6aa050"),
    "trunk": ("#8a6a4a", "#3a2a38", "#c09a68"),
    "terracotta": ("#c06a4a", "#5a2a3a", "#e89068"),
    "concrete": ("#a8a2a6", "#4a4a62", "#d8d2d0"),
    "chrome": ("#b8bccc", "#4a4e6a", "#f2f4ff"),
    "metal": ("#6a6e80", "#26283e", "#a8aec0"),
    "metal_dark": ("#3e4050", "#16182a", "#6a6e80"),
    "wood": ("#b07a4c", "#5a3a3a", "#e0a868"),
    "wood_dark": ("#6e4630", "#2e1e2a", "#9a6440"),
    "white": ("#ece8e4", "#8a8aa6", "#ffffff"),
    "mannequin": ("#ece4dc", "#9a90a8", "#fffaf2"),
    "red": ("#c0303a", "#4e1028", "#ee5048"),
    "pink": ("#e06aa0", "#6a2a5a", "#ff9ac8"),
    "violet": ("#7a4ab0", "#2a1a50", "#a878e0"),
    "teal": ("#3a9a9a", "#163a4a", "#6ad0c8"),
    "yellow": ("#e8c040", "#7a5a30", "#fff08a"),
    "orange": ("#e07a30", "#6a3020", "#ffa860"),
    "blue": ("#3a6ab8", "#162a58", "#6a9ae8"),
    "green": ("#4a9a5a", "#163a3a", "#7ad08a"),
    "black": ("#2a2630", "#100e1c", "#4a4452"),
    "cardboard": ("#c09a64", "#5e4a46", "#ecc88a"),
    "rust": ("#a85a34", "#4a2430", "#d88050"),
    "car_red": ("#a8443a", "#4a1a2a", "#d86a52"),
    "car_blue": ("#4a6a90", "#1a2a48", "#7a9ac0"),
    "tire": ("#2e2a30", "#0e0c18", "#4a4450"),
    "glass_dark": ("#3a4a66", "#141a32", "#7a9ac0"),
    "cloth_red": ("#a8303a", "#4a1430", "#d8504a"),
    "cloth_blue": ("#3a5a9a", "#16224a", "#6a8ad0"),
    "cloth_cream": ("#e0d0b0", "#7e7890", "#fff4dc"),
    "gold": ("#f0c040", "#8a5a30", "#fff0a0"),
    "paper": ("#e6dcc6", "#8a8098", "#fff8e8"),
    "skin": ("#d8a888", "#7a5060", "#f8d0b0"),
    "uniform": ("#3a4866", "#141a34", "#5a6a90"),
    "popcorn": ("#f6e6b0", "#a08a70", "#ffffff"),
    "bitumen": ("#5a5258", "#201c2a", "#86787a"),
}
EMIT = {
    "neon_pink": ("#ff4ab8", 2.2), "neon_violet": ("#a860ff", 2.0), "neon_cyan": ("#5af0ff", 2.0),
    "screen": ("#6ae0ff", 1.5), "screen_pink": ("#ff6ac8", 1.5), "lamp": ("#ffd890", 1.8),
    "water_glow": ("#8ae0f0", 1.1), "led_green": ("#6aff8a", 1.8), "led_red": ("#ff4a3a", 1.8),
}


def M(key: str, rim: float = 0.28):
    if key in EMIT:
        col, s = EMIT[key]
        return C.toon("m_" + key, col, emit=s)
    b, s, l = PAL[key]
    return C.toon("m_" + key, b, s, l, rim=rim)


Builder = BP.Builder


# ============================================================================ décors

def p_fountain(B: Builder) -> None:
    """Fontaine de l'atrium : bassin octogonal en pierre crème, vasque, masque de pierre
    qui crache l'eau, mousse et fougères qui débordent."""
    rx, ry = 3.9, 2.4
    n = 8
    outer = [(math.cos(2 * math.pi * k / n + math.pi / 8) * rx, math.sin(2 * math.pi * k / n + math.pi / 8) * ry) for k in range(n)]
    # Margelle : segments de pierre.
    for k in range(n):
        a, b = outer[k], outer[(k + 1) % n]
        cx, cy = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        ang = math.atan2(b[1] - a[1], b[0] - a[0])
        B.box("rim%d" % k, (ln + 0.12, 0.32, 0.5), (cx, cy, 0.25), M("cream_stone"), rot=(0, 0, ang), bevel=0.04)
        B.box("rimc%d" % k, (ln + 0.16, 0.38, 0.07), (cx, cy, 0.52), M("pink_stone"), rot=(0, 0, ang), bevel=0.02)
    bm = C.bm_cyl(24, 1.0, 1.0, 0.04)
    C.bm_xform(bm, loc=(0, 0, 0.38), scale=(rx - 0.25, ry - 0.25, 1))
    B.add("water", bm, M("water"), outline=False)
    # Fût + vasque.
    B.cyl("shaft", 0.28, 0.36, 0.9, (0, 0, 0.75), M("cream_stone"), seg=12)
    B.cyl("bowl", 0.9, 0.45, 0.28, (0, 0, 1.25), M("pink_stone"), seg=20)
    B.cyl("bowlw", 0.82, 0.82, 0.03, (0, 0, 1.38), M("water"), seg=20, outline=False)
    # Masque de pierre au sommet (ovale, yeux creux) qui crache de l'eau.
    B.cyl("neck", 0.16, 0.2, 0.4, (0, 0, 1.55), M("cream_stone"), seg=10)
    B.sphere("mask", 0.32, (0, -0.05, 1.98), M("mannequin"), scale=(0.85, 0.5, 1.15), seg=16, rings=10)
    for sx in (-0.11, 0.11):
        B.sphere("eye%.2f" % sx, 0.06, (sx, -0.2, 2.05), M("black"), scale=(1.3, 0.5, 0.8), seg=8, rings=5, outline=False)
    B.box("brow", (0.05, 0.02, 0.05), (0, -0.2, 2.2), M("red"), rot=(0, 0.78, 0), outline=False)
    B.tube("jet", C.bezier((0, -0.2, 1.8), (0, -0.55, 1.85), (0, -0.75, 1.6), (0, -0.8, 1.4), 7),
           [0.05, 0.06, 0.06, 0.05, 0.05, 0.04, 0.03], M("water_glow"), outline=False, shadow=False)
    # Végétation : fougères et lierre sur la margelle.
    import random
    rnd = random.Random(3)
    for k in range(14):
        a = rnd.uniform(0, 2 * math.pi)
        x, y = math.cos(a) * (rx - 0.05), math.sin(a) * (ry - 0.05)
        B.sphere("bush%d" % k, rnd.uniform(0.16, 0.3), (x, y, 0.62), M("leaf" if k % 2 else "leaf_dark"), scale=(1.3, 1.0, 0.7), seg=8, rings=6)
    for k in range(5):
        a = rnd.uniform(0.6, 2.6)
        x, y = math.cos(a) * rx * 0.98, -math.sin(a) * ry * 0.98
        B.tube("ivy%d" % k, [(x, y - 0.1, 0.55), (x * 1.02, y - 0.2, 0.3), (x * 1.03, y - 0.22, 0.05)], [0.05, 0.04, 0.02], M("leaf_dark"))


def p_planter(B: Builder) -> None:
    w, d, h = 1.5, 0.8, 0.55
    B.box("box", (w, d, h), (0, 0, h / 2), M("concrete"), bevel=0.03)
    B.box("lip", (w + 0.08, d + 0.08, 0.06), (0, 0, h), M("pink_stone"), bevel=0.02)
    B.box("soil", (w - 0.1, d - 0.1, 0.05), (0, 0, h - 0.02), M("trunk"), outline=False)
    import random
    rnd = random.Random(5)
    for k in range(11):
        x, y = rnd.uniform(-w / 2 + 0.2, w / 2 - 0.2), rnd.uniform(-0.2, 0.2)
        B.sphere("b%d" % k, rnd.uniform(0.2, 0.34), (x, y, h + rnd.uniform(0.15, 0.45)), M("leaf" if k % 3 else "leaf_dark"),
                 scale=(1.2, 1.0, 0.9), seg=9, rings=6)
    for k in range(4):  # lianes qui retombent devant
        x = rnd.uniform(-w / 2 + 0.2, w / 2 - 0.2)
        B.tube("vine%d" % k, [(x, -d / 2 + 0.05, h + 0.1), (x + 0.05, -d / 2 - 0.06, h - 0.1), (x - 0.03, -d / 2 - 0.05, 0.12)],
               [0.045, 0.035, 0.02], M("leaf_dark"))


def p_palm_pot(B: Builder) -> None:
    B.cyl("pot", 0.36, 0.28, 0.6, (0, 0, 0.3), M("terracotta"), seg=16)
    B.torus("rim", 0.36, 0.05, (0, 0, 0.6), M("terracotta"), seg=20, rseg=5)
    pts = [(0, 0, 0.55), (0.04, 0.0, 1.2), (0.1, 0.02, 1.8), (0.12, 0.03, 2.3)]
    B.tube("trunk", pts, [0.11, 0.09, 0.08, 0.07], M("trunk"), seg=8)
    for k in range(8):
        a = 2 * math.pi * k / 8 + 0.3
        tip = (0.12 + math.cos(a) * 1.1, 0.03 + math.sin(a) * 0.8, 1.85 + (0.15 if k % 2 else -0.15))
        mid = (0.12 + math.cos(a) * 0.6, 0.03 + math.sin(a) * 0.45, 2.45)
        bm = C.bm_tube([(0.12, 0.03, 2.3), mid, tip], [0.05, 0.16, 0.02], seg=6, flat=0.18)
        B.add("frond%d" % k, bm, M("leaf" if k % 2 else "leaf_dark"), sharp=80)


def p_bench(B: Builder) -> None:
    w = 1.6
    for i in range(4):
        B.box("slat%d" % i, (w, 0.11, 0.05), (0, -0.2 + i * 0.13, 0.45), M("wood"), bevel=0.01)
    for i in range(2):
        B.box("back%d" % i, (w, 0.05, 0.11), (0, 0.24, 0.72 + i * 0.16), M("wood"), bevel=0.01)
    for sx in (-w / 2 + 0.15, w / 2 - 0.15):
        B.box("leg%.1f" % sx, (0.07, 0.5, 0.05), (sx, 0.0, 0.03), M("metal_dark"))
        B.box("legv%.1f" % sx, (0.07, 0.06, 0.45), (sx, -0.18, 0.22), M("metal_dark"))
        B.box("legb%.1f" % sx, (0.07, 0.06, 0.95), (sx, 0.24, 0.47), M("metal_dark"))
    B.box("papers", (0.3, 0.22, 0.02), (0.3, -0.05, 0.49), M("paper"), rot=(0, 0, 0.4), outline=False)


def p_mannequin(B: Builder, tilt: float = 0.18, dress: str = "cloth_red") -> None:
    B.cyl("base", 0.25, 0.28, 0.06, (0, 0, 0.03), M("metal_dark"), seg=14)
    B.cyl("pole", 0.025, 0.025, 0.5, (0, 0, 0.3), M("chrome"), seg=6)
    root = C.empty("mroot", (0, 0, 0))
    objs = []
    objs.append(B.cyl("legs", 0.16, 0.11, 0.6, (0, 0, 0.6), M("mannequin"), seg=12))
    objs.append(B.cyl("skirt", 0.36, 0.2, 0.55, (0, 0, 0.98), M(dress), seg=16))
    objs.append(B.cyl("torso", 0.2, 0.25, 0.55, (0, 0, 1.45), M(dress), seg=14))
    objs.append(B.sphere("chest", 0.25, (0, 0, 1.68), M(dress), scale=(1.0, 0.75, 0.6), seg=12, rings=8))
    objs.append(B.cyl("neck", 0.06, 0.07, 0.15, (0, 0, 1.83), M("mannequin"), seg=8))
    objs.append(B.sphere("head", 0.16, (0, 0, 2.02), M("mannequin"), scale=(0.85, 0.85, 1.12), seg=14, rings=10))
    for sx in (-1, 1):
        objs.append(B.tube("arm%d" % sx, [(0.26 * sx, 0, 1.72), (0.34 * sx, -0.05, 1.42), (0.3 * sx, -0.14, 1.15)],
                           [0.06, 0.05, 0.045], M("mannequin")))
    for ob in objs:
        ob.parent = root
    root.rotation_euler = (0, tilt, 0.25)


def p_clothes_rack(B: Builder) -> None:
    w = 1.5
    for sx in (-w / 2, w / 2):
        B.cyl("post%.1f" % sx, 0.025, 0.025, 1.5, (sx, 0, 0.75), M("chrome"), seg=6)
        B.box("foot%.1f" % sx, (0.06, 0.6, 0.04), (sx, 0, 0.02), M("chrome"))
    B.cyl("bar", 0.025, 0.025, w, (0, 0, 1.48), M("chrome"), rot=(0, math.pi / 2, 0), seg=6)
    cols = ["cloth_red", "cloth_blue", "cloth_cream", "pink", "violet", "teal", "yellow", "black"]
    for i in range(8):
        x = -w / 2 + 0.15 + i * (w - 0.3) / 7
        B.box("cl%d" % i, (0.08, 0.5, 0.75), (x, 0, 1.08), M(cols[i % len(cols)]), rot=(0, 0.05 * (i % 3 - 1), 0), bevel=0.02)
        B.torus("h%d" % i, 0.05, 0.008, (x, 0, 1.5), M("chrome"), rot=(0, math.pi / 2, 0), seg=10, rseg=3)
    B.box("fallen", (0.6, 0.45, 0.06), (0.4, -0.45, 0.03), M("pink"), rot=(0, 0, 0.5), outline=True)


def p_store_shelf(B: Builder) -> None:
    """Gondole de supermarché double face, rayons à moitié vides, produits renversés."""
    import random
    rnd = random.Random(7)
    w, d, h = 3.3, 0.85, 1.2
    B.box("base", (w, d, 0.15), (0, 0, 0.075), M("metal_dark"))
    B.box("back", (w, 0.06, h), (0, 0, h / 2), M("white"))
    B.box("cap", (w + 0.04, 0.12, 0.04), (0, 0, h), M("metal"))
    for sx in (-w / 2, w / 2):
        B.box("end%.1f" % sx, (0.06, d, h), (sx, 0, h / 2), M("red"))
    cols = ["red", "yellow", "blue", "green", "orange", "pink", "cardboard", "white", "teal"]
    for lvl, z in enumerate((0.2, 0.6, 1.0)):
        for sy in (-1, 1):
            B.box("sh%d%d" % (lvl, sy), (w - 0.1, d / 2 - 0.05, 0.03), (0, sy * d / 4, z), M("metal"))
            x = -w / 2 + 0.12
            while x < w / 2 - 0.2:
                bw = rnd.uniform(0.12, 0.26)
                if rnd.random() < 0.55:
                    hh = rnd.uniform(0.18, 0.34)
                    if rnd.random() < 0.5:
                        B.box("p%d%d%.2f" % (lvl, sy, x), (bw, 0.22, hh), (x + bw / 2, sy * d / 4, z + hh / 2 + 0.02), M(cols[rnd.randrange(len(cols))]))
                    else:
                        B.cyl("c%d%d%.2f" % (lvl, sy, x), bw / 2.2, bw / 2.2, hh, (x + bw / 2, sy * d / 4, z + hh / 2 + 0.02), M(cols[rnd.randrange(len(cols))]), seg=8)
                x += bw + 0.03
    for k in range(4):
        B.box("fl%d" % k, (rnd.uniform(0.15, 0.3), 0.22, 0.14), (rnd.uniform(-w / 2, w / 2), -d / 2 - rnd.uniform(0.15, 0.4), 0.07),
              M(cols[rnd.randrange(len(cols))]), rot=(0, 0, rnd.uniform(0, 3)))


def p_checkout(B: Builder) -> None:
    w, d, h = 1.7, 0.75, 1.0
    B.box("body", (w, d, h), (0, 0, h / 2), M("white"), bevel=0.03)
    B.box("stripe", (w + 0.01, d + 0.01, 0.12), (0, 0, h * 0.7), M("red"))
    B.box("top", (w + 0.06, d + 0.06, 0.05), (0, 0, h), M("metal_dark"))
    B.box("belt", (w * 0.55, d * 0.7, 0.02), (-w * 0.18, 0, h + 0.035), M("black"))
    B.box("reg", (0.45, 0.4, 0.28), (w * 0.3, 0.05, h + 0.16), M("metal"), bevel=0.03)
    B.box("screen", (0.35, 0.06, 0.24), (w * 0.3, 0.15, h + 0.42), M("screen"), rot=(-0.4, 0, 0), outline=True)
    B.cyl("pole", 0.025, 0.025, 0.9, (w / 2 - 0.1, 0.3, h + 0.45), M("chrome"), seg=6)
    B.box("num", (0.25, 0.06, 0.2), (w / 2 - 0.1, 0.3, h + 0.95), M("led_green"))


def p_food_table(B: Builder) -> None:
    B.cyl("top", 0.55, 0.55, 0.05, (0, 0, 0.75), M("white"), seg=20)
    B.cyl("leg", 0.05, 0.05, 0.72, (0, 0, 0.37), M("chrome"), seg=8)
    B.cyl("foot", 0.28, 0.3, 0.04, (0, 0, 0.02), M("chrome"), seg=14)
    B.box("tray", (0.42, 0.3, 0.03), (0.08, 0.05, 0.79), M("red"), rot=(0, 0, 0.3))
    B.cyl("cup", 0.06, 0.05, 0.18, (-0.2, -0.1, 0.87), M("yellow"), seg=8)
    for k, a in enumerate((0.3, 2.3, 4.2)):
        x, y = math.cos(a) * 0.82, math.sin(a) * 0.62
        tip = 0.35 if k == 2 else 0.0
        B.box("seat%d" % k, (0.42, 0.42, 0.05), (x, y, 0.45 - tip * 0.3), M("orange"), rot=(tip, 0, a + math.pi / 2), bevel=0.02)
        B.box("bk%d" % k, (0.42, 0.05, 0.4), (x + math.cos(a) * 0.2, y + math.sin(a) * 0.2, 0.68 - tip * 0.3), M("orange"),
              rot=(tip, 0, a + math.pi / 2), bevel=0.02)
        for dx in (-0.16, 0.16):
            B.cyl("l%d%.2f" % (k, dx), 0.02, 0.02, 0.43, (x + dx * math.sin(a), y - dx * math.cos(a), 0.22), M("chrome"), seg=5)


def p_cinema_seats(B: Builder) -> None:
    n = 4
    w = 0.78
    for i in range(n):
        x = -(n - 1) * w / 2 + i * w
        torn = i == 2
        B.box("seat%d" % i, (0.62, 0.55, 0.14), (x, -0.05, 0.42), M("cloth_red"), bevel=0.04)
        B.box("back%d" % i, (0.62, 0.16, 0.75), (x, 0.24, 0.8 if not torn else 0.74), M("cloth_red"), rot=(0.18 if not torn else 0.45, 0, 0), bevel=0.05)
        if torn:
            B.box("foam%d" % i, (0.3, 0.05, 0.25), (x + 0.05, 0.12, 0.85), M("yellow"), rot=(0.45, 0, 0), outline=False)
    for i in range(n + 1):
        x = -n * w / 2 + i * w
        B.box("arm%d" % i, (0.1, 0.62, 0.62), (x, 0.0, 0.31), M("black"), bevel=0.02)
    B.cyl("popcorn", 0.11, 0.08, 0.22, (-0.4, -0.55, 0.11), M("red"), seg=10)


def p_popcorn_machine(B: Builder) -> None:
    B.box("cart", (0.9, 0.6, 0.7), (0, 0, 0.45), M("red"), bevel=0.03)
    for sx in (-0.35, 0.35):
        B.cyl("wh%.1f" % sx, 0.12, 0.12, 0.06, (sx, -0.31, 0.12), M("black"), rot=(math.pi / 2, 0, 0), seg=12)
    B.box("glass", (0.8, 0.5, 0.65), (0, 0, 1.13), M("glass_dark"), bevel=0.02)
    import random
    rnd = random.Random(2)
    for k in range(16):
        B.sphere("pc%d" % k, 0.06, (rnd.uniform(-0.32, 0.32), rnd.uniform(-0.2, 0.2), 0.86 + rnd.uniform(0, 0.14)), M("popcorn"), seg=6, rings=4, outline=False)
    B.box("roof", (0.95, 0.65, 0.1), (0, 0, 1.5), M("red"), bevel=0.03)
    B.box("sign", (0.7, 0.05, 0.22), (0, -0.33, 1.62), M("yellow"))


def p_arcade_cabinet(B: Builder) -> None:
    B.box("body", (0.75, 0.75, 1.75), (0, 0.05, 0.88), M("violet"), bevel=0.02)
    B.box("side_art", (0.77, 0.6, 0.12), (0, 0.05, 1.45), M("pink"), outline=False)
    B.box("screen", (0.6, 0.08, 0.5), (0, -0.33, 1.25), M("screen"), rot=(-0.2, 0, 0))
    B.box("panel", (0.7, 0.35, 0.08), (0, -0.42, 0.95), M("black"), rot=(0.3, 0, 0))
    B.cyl("stick", 0.02, 0.02, 0.12, (-0.15, -0.45, 1.04), M("chrome"), seg=5)
    B.sphere("ball", 0.04, (-0.15, -0.45, 1.11), M("red"), seg=8, rings=5)
    for k in range(3):
        B.cyl("btn%d" % k, 0.035, 0.035, 0.03, (0.05 + k * 0.1, -0.46, 1.0), M(["led_red", "neon_cyan", "yellow"][k]), seg=8)
    B.box("marquee", (0.72, 0.1, 0.22), (0, -0.3, 1.66), M("neon_pink"))


def p_car_wreck(B: Builder, body: str = "car_red", plants: bool = True) -> None:
    """Berline abandonnée : carrosserie rouillée, pneus à plat, vitres brisées, herbes."""
    L, Wd = 3.9, 1.65
    B.box("lower", (L, Wd, 0.55), (0, 0, 0.5), M(body), bevel=0.12)
    B.box("hood", (1.1, Wd - 0.06, 0.12), (-1.35, 0, 0.82), M(body), rot=(0, 0.06, 0), bevel=0.05)
    B.box("trunk", (0.8, Wd - 0.06, 0.12), (1.5, 0, 0.82), M(body), bevel=0.05)
    cab = C.bm_loft([
        [(-0.85, -0.78, 0.78), (1.1, -0.78, 0.78), (1.1, 0.78, 0.78), (-0.85, 0.78, 0.78)],
        [(-0.45, -0.68, 1.35), (0.85, -0.68, 1.35), (0.85, 0.68, 1.35), (-0.45, 0.68, 1.35)],
    ])
    B.add("cabin", cab, M("glass_dark"), sharp=30)
    B.box("roof", (1.35, 1.4, 0.06), (0.2, 0, 1.37), M(body), bevel=0.03)
    for (x, y, k) in ((-1.25, -0.78, 0), (1.25, -0.78, 1), (-1.25, 0.78, 2), (1.25, 0.78, 3)):
        B.cyl("tire%d" % k, 0.36, 0.36, 0.26, (x, y, 0.3), M("tire"), rot=(math.pi / 2, 0, 0), seg=14)
        B.cyl("hub%d" % k, 0.15, 0.15, 0.28, (x, y, 0.3), M("chrome"), rot=(math.pi / 2, 0, 0), seg=10)
    B.box("bumperf", (0.12, Wd, 0.18), (-L / 2 - 0.02, 0, 0.4), M("chrome"))
    B.box("bumperr", (0.12, Wd, 0.18), (L / 2 + 0.02, 0, 0.4), M("chrome"))
    for sy in (-0.55, 0.55):
        B.box("lamp%.1f" % sy, (0.06, 0.3, 0.14), (-L / 2 - 0.05, sy, 0.6), M("paper"))
    import random
    rnd = random.Random(11)
    for k in range(5):
        B.sphere("rust%d" % k, rnd.uniform(0.12, 0.22), (rnd.uniform(-1.6, 1.6), -Wd / 2 - 0.01, rnd.uniform(0.35, 0.7)), M("rust"),
                 scale=(1.4, 0.08, 0.8), seg=8, rings=5, outline=False, shadow=False)
    if plants:
        for k in range(6):
            B.sphere("weed%d" % k, rnd.uniform(0.15, 0.28), (rnd.uniform(-1.9, 1.9), -Wd / 2 - rnd.uniform(0.05, 0.3), 0.12),
                     M("leaf" if k % 2 else "leaf_dark"), scale=(1.3, 1.0, 1.0), seg=8, rings=5)


def p_traffic_cone(B: Builder) -> None:
    B.box("base", (0.42, 0.42, 0.05), (0, 0, 0.025), M("orange"), bevel=0.02)
    B.cyl("cone", 0.17, 0.03, 0.7, (0, 0, 0.4), M("orange"), seg=14)
    B.cyl("band", 0.125, 0.105, 0.12, (0, 0, 0.4), M("white"), seg=14)


def p_trash_bin(B: Builder) -> None:
    B.cyl("bin", 0.32, 0.3, 0.9, (0, 0, 0.45), M("metal"), seg=16)
    B.torus("rim", 0.32, 0.03, (0, 0, 0.9), M("metal_dark"), seg=18, rseg=4)
    for k in range(4):
        a = k * 1.6
        B.sphere("tr%d" % k, 0.12, (math.cos(a) * 0.12, math.sin(a) * 0.12, 0.95), M(["paper", "black", "cardboard", "pink"][k]), scale=(1.2, 1, 0.7), seg=7, rings=5)
    B.box("lid", (0.5, 0.06, 0.4), (0.45, -0.1, 0.08), M("metal_dark"), rot=(0, 1.3, 0.4))


def p_neon_sign(B: Builder) -> None:
    """Enseigne lumineuse sur pied : cœur néon rose et étoile violette."""
    B.box("base", (0.5, 0.35, 0.08), (0, 0, 0.04), M("metal_dark"))
    B.cyl("pole", 0.04, 0.04, 1.3, (0, 0, 0.7), M("metal_dark"), seg=6)
    B.box("panel", (1.0, 0.08, 0.8), (0, 0, 1.75), M("black"), bevel=0.02)
    pts = []
    for k in range(21):
        t = k / 20 * 2 * math.pi
        x = 16 * math.sin(t) ** 3
        z = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x * 0.017, -0.06, 1.77 + z * 0.017))
    B.tube("heart", pts, [0.025] * len(pts), M("neon_pink"), seg=6, outline=False, shadow=False)


def p_mall_map(B: Builder) -> None:
    B.box("foot", (0.5, 0.4, 0.06), (0, 0, 0.03), M("metal_dark"))
    B.box("post", (0.6, 0.14, 1.55), (0, 0.04, 0.8), M("metal"), bevel=0.02)
    B.box("panel", (0.56, 0.04, 0.9), (0, -0.04, 1.05), M("lamp"))
    for k in range(5):
        B.box("blk%d" % k, (0.12 + 0.05 * (k % 2), 0.02, 0.1), (-0.15 + (k % 3) * 0.15, -0.065, 0.75 + k * 0.13),
              M(["pink", "teal", "violet", "orange", "green"][k]), outline=False)
    B.sphere("here", 0.04, (0.05, -0.07, 1.1), M("led_red"), seg=8, rings=5, outline=False)
    B.box("top", (0.66, 0.18, 0.12), (0, 0.02, 1.6), M("violet"), bevel=0.02)


def p_puddle(B: Builder) -> None:
    import random
    rnd = random.Random(4)
    for k in range(5):
        bm = C.bm_cyl(16, 1.0, 1.0, 0.01)
        C.bm_xform(bm, loc=(rnd.uniform(-0.5, 0.5), rnd.uniform(-0.3, 0.3), 0.0), scale=(rnd.uniform(0.3, 0.6), rnd.uniform(0.2, 0.4), 1))
        B.add("pd%d" % k, bm, M("water"), outline=False)


def p_debris(B: Builder) -> None:
    import random
    rnd = random.Random(9)
    for k in range(7):
        B.box("tile%d" % k, (rnd.uniform(0.3, 0.6), rnd.uniform(0.3, 0.6), 0.04), (rnd.uniform(-0.6, 0.6), rnd.uniform(-0.4, 0.4), 0.03 + k * 0.025),
              M("white" if k % 2 else "paper"), rot=(rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), rnd.uniform(0, 3)))
    for k in range(6):
        B.sphere("ch%d" % k, rnd.uniform(0.07, 0.14), (rnd.uniform(-0.7, 0.7), rnd.uniform(-0.45, 0.45), 0.05), M("concrete"), scale=(1.2, 1, 0.7), seg=6, rings=4)
    B.box("light", (1.0, 0.25, 0.08), (0.1, -0.1, 0.2), M("metal"), rot=(0.1, 0.25, 0.6))
    B.box("tube", (0.85, 0.06, 0.05), (0.1, -0.1, 0.26), M("white"), rot=(0.1, 0.25, 0.6), outline=False)


def p_desk(B: Builder) -> None:
    w, d, h = 1.6, 0.8, 0.78
    B.box("top", (w, d, 0.06), (0, 0, h), M("wood_dark"), bevel=0.02)
    B.box("drawers", (0.45, d - 0.06, h - 0.06), (w / 2 - 0.25, 0, (h - 0.06) / 2), M("wood"))
    for k in range(3):
        B.box("dr%d" % k, (0.36, 0.02, 0.16), (w / 2 - 0.25, -d / 2, 0.15 + k * 0.22), M("wood_dark"))
    B.box("legl", (0.06, d - 0.06, h - 0.06), (-w / 2 + 0.05, 0, (h - 0.06) / 2), M("wood"))
    B.box("mon", (0.5, 0.05, 0.35), (-0.15, 0.15, h + 0.3), M("black"), bevel=0.02)
    B.box("monsc", (0.44, 0.02, 0.28), (-0.15, 0.12, h + 0.3), M("screen"), outline=False)
    B.box("monft", (0.16, 0.14, 0.12), (-0.15, 0.18, h + 0.09), M("black"))
    for k in range(3):
        B.box("pp%d" % k, (0.28, 0.2, 0.01), (0.35 + k * 0.05, -0.1 + k * 0.03, h + 0.04 + k * 0.01), M("paper"), rot=(0, 0, 0.2 * k), outline=False)
    B.cyl("lamp", 0.02, 0.02, 0.4, (0.6, 0.25, h + 0.2), M("metal"), seg=6)
    B.cyl("shade", 0.14, 0.07, 0.14, (0.6, 0.18, h + 0.42), M("green"), rot=(0.5, 0, 0), seg=12)
    B.sphere("bulb", 0.05, (0.6, 0.12, h + 0.36), M("lamp"), outline=False, shadow=False)
    B.box("chair", (0.5, 0.5, 0.08), (-0.2, -0.65, 0.45), M("black"), bevel=0.03)
    B.box("chairb", (0.5, 0.08, 0.6), (-0.2, -0.88, 0.78), M("black"), bevel=0.03)
    B.cyl("chairl", 0.03, 0.03, 0.42, (-0.2, -0.65, 0.21), M("chrome"), seg=6)


def p_filing_cabinet(B: Builder) -> None:
    B.box("body", (0.55, 0.6, 1.35), (0, 0, 0.675), M("metal"), bevel=0.02)
    for k in range(4):
        z = 0.2 + k * 0.32
        out = 0.25 if k == 2 else 0.0
        B.box("dr%d" % k, (0.5, 0.04 + out, 0.28), (0, -0.31 - out / 2, z), M("metal"), bevel=0.01)
        B.box("hd%d" % k, (0.15, 0.03, 0.03), (0, -0.34 - out, z + 0.06), M("chrome"))
        if out:
            B.box("files", (0.42, 0.22, 0.2), (0, -0.4, z + 0.1), M("paper"))
    B.box("paper_f", (0.3, 0.22, 0.01), (0.3, -0.6, 0.01), M("paper"), rot=(0, 0, 0.6), outline=False)


def p_ac_unit(B: Builder) -> None:
    B.box("body", (1.3, 0.9, 0.85), (0, 0, 0.5), M("white"), bevel=0.04)
    B.box("base", (1.4, 1.0, 0.08), (0, 0, 0.04), M("metal_dark"))
    B.cyl("grill", 0.36, 0.36, 0.04, (0, 0, 0.94), M("metal_dark"), seg=20)
    for k in range(4):
        a = k * math.pi / 4
        B.box("blade%d" % k, (0.62, 0.08, 0.02), (0, 0, 0.97), M("metal"), rot=(0, 0, a), outline=False)
    for k in range(5):
        B.box("vent%d" % k, (0.9, 0.02, 0.05), (0, -0.46, 0.25 + k * 0.1), M("metal_dark"), outline=False)
    B.box("rust", (0.35, 0.02, 0.3), (0.35, -0.46, 0.35), M("rust"), outline=False)
    B.tube("pipe", [(0.65, 0.2, 0.3), (0.95, 0.25, 0.3), (1.0, 0.3, 0.05)], [0.05, 0.05, 0.05], M("metal"))


def p_roof_vent(B: Builder) -> None:
    B.box("curb", (0.5, 0.5, 0.25), (0, 0, 0.125), M("metal_dark"))
    B.cyl("pipe", 0.16, 0.16, 0.8, (0, 0, 0.6), M("metal"), seg=12)
    B.cyl("hat", 0.34, 0.1, 0.22, (0, 0, 1.1), M("metal"), seg=14)
    B.box("rust", (0.15, 0.02, 0.25), (0.06, -0.17, 0.6), M("rust"), outline=False)


def p_tv_wall(B: Builder) -> None:
    B.box("stand", (1.6, 0.5, 0.5), (0, 0.1, 0.25), M("black"), bevel=0.02)
    for i in range(2):
        for j in range(2):
            x, z = -0.38 + i * 0.76, 0.85 + j * 0.55
            B.box("tv%d%d" % (i, j), (0.72, 0.12, 0.5), (x, 0.15, z), M("metal_dark"), bevel=0.02)
            sc = ["screen", "screen_pink", "black", "screen"][i * 2 + j]
            B.box("sc%d%d" % (i, j), (0.64, 0.02, 0.42), (x, 0.08, z), M(sc), outline=False)
    B.box("fallen", (0.7, 0.45, 0.12), (0.6, -0.45, 0.08), M("metal_dark"), rot=(0, 0, 0.3))


def p_toy_pile(B: Builder) -> None:
    def bear(x, y, z, col, s=1.0):
        B.sphere("bb%.1f" % x, 0.24 * s, (x, y, z + 0.24 * s), M(col), scale=(1, 0.85, 1), seg=10, rings=7)
        B.sphere("bh%.1f" % x, 0.17 * s, (x, y - 0.03, z + 0.6 * s), M(col), seg=10, rings=7)
        for sx in (-1, 1):
            B.sphere("be%.1f%d" % (x, sx), 0.06 * s, (x + sx * 0.12 * s, y, z + 0.74 * s), M(col), seg=6, rings=4)
        B.sphere("bm%.1f" % x, 0.06 * s, (x, y - 0.17 * s, z + 0.56 * s), M("cloth_cream"), seg=6, rings=4)
    bear(-0.3, 0.1, 0.0, "cardboard")
    bear(0.35, 0.0, 0.0, "pink", 0.8)
    B.sphere("ball", 0.2, (0.05, -0.35, 0.2), M("blue"), seg=12, rings=8)
    B.box("blk1", (0.2, 0.2, 0.2), (0.6, -0.3, 0.1), M("yellow"))
    B.box("blk2", (0.2, 0.2, 0.2), (0.62, -0.28, 0.3), M("red"), rot=(0, 0, 0.4))
    B.box("box", (0.5, 0.35, 0.4), (-0.6, -0.25, 0.2), M("teal"), rot=(0, 0, 0.3))


def p_medicine_shelf(B: Builder) -> None:
    import random
    rnd = random.Random(6)
    w, d, h = 1.6, 0.45, 1.7
    B.box("back", (w, 0.05, h), (0, d / 2, h / 2), M("white"))
    for sx in (-w / 2, w / 2):
        B.box("side%.1f" % sx, (0.05, d, h), (sx, 0, h / 2), M("white"))
    for lvl, z in enumerate((0.1, 0.5, 0.9, 1.3)):
        B.box("sh%d" % lvl, (w, d, 0.04), (0, 0, z), M("white"))
        x = -w / 2 + 0.1
        while x < w / 2 - 0.12:
            if rnd.random() < 0.6:
                col = ["white", "teal", "green", "pink", "orange"][rnd.randrange(5)]
                if rnd.random() < 0.5:
                    B.cyl("b%d%.2f" % (lvl, x), 0.05, 0.05, 0.18, (x, -0.05, z + 0.11), M(col), seg=8)
                else:
                    B.box("x%d%.2f" % (lvl, x), (0.14, 0.12, 0.2), (x, -0.05, z + 0.12), M(col))
            x += 0.16
    B.box("cross_v", (0.12, 0.04, 0.36), (0, -0.0, h + 0.25), M("led_green"))
    B.box("cross_h", (0.36, 0.04, 0.12), (0, -0.0, h + 0.25), M("led_green"))


def p_generator(B: Builder) -> None:
    B.box("skid", (1.7, 0.9, 0.12), (0, 0, 0.06), M("metal_dark"))
    B.box("body", (1.5, 0.8, 0.9), (0, 0, 0.57), M("yellow"), bevel=0.04)
    for k in range(6):
        B.box("v%d" % k, (0.04, 0.02, 0.5), (-0.6 + k * 0.08, -0.41, 0.6), M("metal_dark"), outline=False)
    B.box("panel", (0.4, 0.03, 0.3), (0.4, -0.41, 0.7), M("metal"))
    B.sphere("led", 0.03, (0.32, -0.43, 0.78), M("led_red"), seg=6, rings=4, outline=False)
    B.cyl("exhaust", 0.07, 0.07, 0.5, (-0.5, 0.2, 1.25), M("metal"), seg=8)
    B.tube("cable", [(0.75, -0.2, 0.3), (1.0, -0.4, 0.05), (1.3, -0.3, 0.02)], [0.03] * 3, M("black"))


PROPS = {
    "fountain": (p_fountain, (330, 250), 0.9), "planter": (p_planter, (110, 100), 0.5), "palm_pot": (p_palm_pot, (130, 160), 1.5),
    "bench": (p_bench, (110, 80), 0.5), "mannequin": (p_mannequin, (70, 110), 1.1), "clothes_rack": (p_clothes_rack, (110, 100), 0.8),
    "store_shelf": (p_store_shelf, (150, 120), 0.7), "checkout": (p_checkout, (100, 100), 0.7), "food_table": (p_food_table, (110, 90), 0.5),
    "cinema_seats": (p_cinema_seats, (150, 90), 0.5), "popcorn_machine": (p_popcorn_machine, (70, 100), 0.8),
    "arcade_cabinet": (p_arcade_cabinet, (60, 100), 0.9), "car_wreck": (p_car_wreck, (180, 130), 0.6),
    "traffic_cone": (p_traffic_cone, (36, 46), 0.35), "trash_bin": (p_trash_bin, (50, 66), 0.5),
    "neon_sign": (p_neon_sign, (60, 110), 1.2), "mall_map": (p_mall_map, (50, 90), 0.9), "puddle": (p_puddle, (90, 70), 0.0),
    "debris": (p_debris, (90, 70), 0.2), "desk": (p_desk, (110, 100), 0.6), "filing_cabinet": (p_filing_cabinet, (50, 80), 0.7),
    "ac_unit": (p_ac_unit, (100, 90), 0.5), "roof_vent": (p_roof_vent, (46, 70), 0.6), "tv_wall": (p_tv_wall, (100, 100), 0.8),
    "toy_pile": (p_toy_pile, (80, 70), 0.3), "medicine_shelf": (p_medicine_shelf, (100, 110), 1.0), "generator": (p_generator, (110, 90), 0.5),
}
FLAT = {"puddle"}
GLOW = {"neon_sign": (0.0, -0.06, 1.8), "mall_map": (0.0, -0.05, 1.05), "arcade_cabinet": (0.0, -0.33, 1.3),
        "desk": (0.6, 0.12, 1.14), "tv_wall": (0.0, 0.1, 1.1), "medicine_shelf": (0.0, 0.0, 1.95), "checkout": (0.5, 0.3, 1.95)}


# ============================================================================ conteneurs et cachettes

def c_register(B: Builder, open_: bool) -> None:
    B.box("stand", (0.9, 0.6, 0.75), (0, 0, 0.375), M("white"), bevel=0.02)
    B.box("stripe", (0.91, 0.61, 0.08), (0, 0, 0.6), M("pink"))
    B.box("reg", (0.6, 0.5, 0.3), (0, 0.02, 0.92), M("metal"), bevel=0.04)
    B.box("keys", (0.5, 0.25, 0.06), (0, -0.12, 1.1), M("metal_dark"), rot=(-0.5, 0, 0))
    B.box("disp", (0.3, 0.06, 0.16), (0, 0.18, 1.2), M("led_green"))
    if open_:
        B.box("drawer", (0.52, 0.42, 0.12), (0, -0.4, 0.8), M("metal_dark"), bevel=0.01)
        B.box("trayin", (0.46, 0.36, 0.02), (0, -0.4, 0.86), M("black"), outline=False)
    else:
        B.box("drawer", (0.52, 0.05, 0.12), (0, -0.24, 0.8), M("metal_dark"))
        B.box("cash", (0.2, 0.04, 0.03), (0.1, -0.27, 0.86), M("green"), outline=False)


def c_display(B: Builder, open_: bool) -> None:
    B.box("base", (1.0, 0.6, 0.7), (0, 0, 0.35), M("wood_dark"), bevel=0.02)
    B.box("trim", (1.02, 0.62, 0.05), (0, 0, 0.7), M("gold"))
    B.box("velvet", (0.9, 0.5, 0.03), (0, 0, 0.73), M("violet"), outline=False)
    if not open_:
        B.box("watch", (0.12, 0.12, 0.04), (-0.25, -0.05, 0.76), M("gold"), outline=False)
        B.box("phone", (0.12, 0.2, 0.03), (0.05, 0.0, 0.76), M("black"), outline=False)
        B.sphere("ring", 0.05, (0.3, -0.05, 0.78), M("gold"), seg=8, rings=5, outline=False)
        B.box("glass", (0.96, 0.56, 0.35), (0, 0, 0.92), M("glass_dark"), bevel=0.01)
    else:
        for k in range(4):
            B.box("shard%d" % k, (0.22, 0.15, 0.01), (-0.3 + k * 0.2, -0.5 - 0.05 * k, 0.01), M("glass_dark"), rot=(0, 0, k), outline=False)
        for sx in (-0.47, 0.47):
            B.box("fr%.1f" % sx, (0.02, 0.56, 0.35), (sx, 0, 0.92), M("chrome"))
        B.box("frb", (0.96, 0.02, 0.35), (0, 0.27, 0.92), M("glass_dark"))


def c_jewel_safe(B: Builder, open_: bool) -> None:
    w, d, h = 0.95, 0.75, 1.15
    B.box("body", (w, d, h), (0, 0, h / 2 + 0.06), M("metal_dark"), bevel=0.04)
    B.box("plinth", (w + 0.05, d + 0.05, 0.08), (0, 0, 0.04), M("black"))
    if open_:
        B.box("cav", (w - 0.16, 0.02, h - 0.16), (0, -d / 2 + 0.01, h / 2 + 0.06), M("black"), outline=False)
        B.box("shelf", (w - 0.18, d - 0.2, 0.03), (0, -0.05, h / 2 + 0.1), M("metal"))
        B.box("door", (0.08, w - 0.06, h - 0.06), (-w / 2 - 0.02, -d / 2 - w / 2 + 0.06, h / 2 + 0.06), M("metal"), bevel=0.02)
        B.cyl("dial", 0.11, 0.11, 0.05, (-w / 2 - 0.08, -d / 2 - w / 2 + 0.06, h / 2 + 0.2), M("gold"), rot=(0, math.pi / 2, 0), seg=14)
    else:
        B.box("door", (w - 0.1, 0.05, h - 0.1), (0, -d / 2 - 0.02, h / 2 + 0.06), M("metal"), bevel=0.02)
        B.cyl("dial", 0.14, 0.14, 0.05, (-0.1, -d / 2 - 0.06, h / 2 + 0.2), M("gold"), rot=(math.pi / 2, 0, 0), seg=16)
        B.tube("handle", [(0.25, -d / 2 - 0.06, h / 2 + 0.3), (0.25, -d / 2 - 0.12, h / 2 + 0.06), (0.25, -d / 2 - 0.06, h / 2 - 0.18)], [0.03] * 3, M("chrome"))
        for sx in (-w / 2 + 0.12, w / 2 - 0.12):
            for sz in (0.2, h - 0.05):
                B.sphere("bolt%.1f%.1f" % (sx, sz), 0.035, (sx, -d / 2 - 0.05, sz), M("chrome"), seg=6, rings=4)


def c_cart(B: Builder, open_: bool) -> None:
    """Chariot de supermarché (grille chromée), chargé ou vide (renversé)."""
    root = C.empty("cartroot", (0, 0, 0))
    objs = []
    L, Wd, H = 1.05, 0.6, 0.5
    z0 = 0.4
    for i in range(7):
        x = -L / 2 + i * L / 6
        objs.append(B.box("vx%d" % i, (0.015, 0.015, H), (x, -Wd / 2, z0 + H / 2), M("chrome"), outline=False))
        objs.append(B.box("vb%d" % i, (0.015, 0.015, H), (x, Wd / 2, z0 + H / 2), M("chrome"), outline=False))
    for z in (z0, z0 + H / 2, z0 + H):
        objs.append(B.box("hf%.2f" % z, (L, 0.025, 0.025), (0, -Wd / 2, z), M("chrome")))
        objs.append(B.box("hb%.2f" % z, (L, 0.025, 0.025), (0, Wd / 2, z), M("chrome")))
        objs.append(B.box("hl%.2f" % z, (0.025, Wd, 0.025), (-L / 2, 0, z), M("chrome")))
        objs.append(B.box("hr%.2f" % z, (0.025, Wd, 0.025), (L / 2, 0, z), M("chrome")))
    objs.append(B.box("bottom", (L, Wd, 0.02), (0, 0, z0), M("metal"), outline=False))
    objs.append(B.cyl("handle", 0.03, 0.03, Wd + 0.1, (L / 2 + 0.15, 0, z0 + H + 0.1), M("red"), rot=(math.pi / 2, 0, 0), seg=8))
    for sy in (-Wd / 2, Wd / 2):
        objs.append(B.box("arm%.1f" % sy, (0.2, 0.02, 0.02), (L / 2 + 0.07, sy, z0 + H + 0.05), M("chrome")))
        for sx in (-L / 2 + 0.05, L / 2 - 0.05):
            objs.append(B.cyl("leg%.1f%.1f" % (sx, sy), 0.015, 0.015, z0, (sx, sy, z0 / 2), M("chrome"), seg=5))
            objs.append(B.cyl("wh%.1f%.1f" % (sx, sy), 0.06, 0.06, 0.04, (sx, sy, 0.06), M("black"), rot=(math.pi / 2, 0, 0), seg=10))
    if not open_:
        cols = ["red", "yellow", "blue", "green", "cardboard", "orange"]
        for k in range(7):
            objs.append(B.box("g%d" % k, (0.22, 0.18, 0.2), (-0.35 + (k % 4) * 0.22, -0.12 + (k // 4) * 0.24, z0 + 0.12 + (k % 2) * 0.12), M(cols[k % 6]), rot=(0, 0, k * 0.4)))
        objs.append(B.cyl("bottle", 0.06, 0.06, 0.35, (0.2, 0.1, z0 + 0.35), M("green"), rot=(0.4, 0, 0), seg=8))
    for ob in objs:
        ob.parent = root
    if open_:
        root.rotation_euler = (0.0, 0.0, 0.5)


def c_vending(B: Builder, open_: bool) -> None:
    w, d, h = 0.95, 0.8, 1.85
    B.box("body", (w, d, h), (0, 0, h / 2), M("blue"), bevel=0.03)
    B.box("glass", (0.6, 0.04, 1.3), (-0.12, -d / 2, 1.05), M("glass_dark"))
    for k in range(5):
        z = 0.5 + k * 0.25
        for j in range(4):
            if open_ and (k + j) % 3:
                continue
            B.box("it%d%d" % (k, j), (0.1, 0.08, 0.14), (-0.33 + j * 0.14, -d / 2 + 0.06, z + 0.08), M(["red", "yellow", "green", "orange"][j]), outline=False)
        B.box("sp%d" % k, (0.58, 0.03, 0.015), (-0.12, -d / 2 + 0.03, z), M("chrome"), outline=False)
    B.box("pad", (0.18, 0.04, 0.5), (0.33, -d / 2, 1.2), M("metal_dark"))
    B.box("led", (0.14, 0.02, 0.06), (0.33, -d / 2 - 0.02, 1.4), M("led_red" if open_ else "led_green"), outline=False)
    B.box("slot", (0.5, 0.04, 0.16), (-0.1, -d / 2, 0.22), M("black"))
    B.box("topsign", (w - 0.1, 0.04, 0.2), (0, -d / 2, h - 0.15), M("neon_cyan" if not open_ else "screen"))
    if open_:
        cx, cz = -0.1, 1.1
        for k in range(6):
            a = k * 1.05
            B.box("cr%d" % k, (0.4, 0.01, 0.015), (cx + math.cos(a) * 0.18, -d / 2 - 0.03, cz + math.sin(a) * 0.18),
                  M("white"), rot=(0, -a, 0), outline=False)


def c_stock_box(B: Builder, open_: bool) -> None:
    def box(name, size, loc, rot=0.0, flaps=False):
        B.box(name, size, loc, M("cardboard"), rot=(0, 0, rot), bevel=0.01)
        B.box(name + "_tape", (size[0] * 0.15, size[1] + 0.005, 0.01), (loc[0], loc[1], loc[2] + size[2] / 2), M("paper"), rot=(0, 0, rot), outline=False)
        if flaps:
            for sy in (-1, 1):
                B.box(name + "_fl%d" % sy, (size[0], 0.02, size[1] * 0.45), (loc[0], loc[1] + sy * (size[1] / 2 + 0.1), loc[2] + size[2] / 2 + 0.1),
                      M("cardboard"), rot=(sy * 0.7, 0, rot))
    box("b1", (0.8, 0.6, 0.5), (-0.1, 0.05, 0.25))
    box("b2", (0.6, 0.5, 0.42), (0.35, -0.12, 0.21), 0.25)
    box("b3", (0.55, 0.45, 0.4), (-0.05, 0.05, 0.7), -0.15, flaps=open_)
    if open_:
        B.box("in", (0.48, 0.38, 0.02), (-0.05, 0.05, 0.86), M("black"), rot=(0, 0, -0.15), outline=False)
        B.box("loose", (0.3, 0.2, 0.08), (0.45, -0.5, 0.04), M("paper"), rot=(0, 0, 0.6))


def c_corpse(B: Builder, open_: bool) -> None:
    """Pilleur tombé au sol (masque fêlé, blouson), sac à dos à côté."""
    B.cyl("body", 0.22, 0.2, 0.75, (0, 0, 0.18), M("uniform"), rot=(0, math.pi / 2, 0.15), seg=12)
    B.sphere("head", 0.17, (-0.5, 0.05, 0.17), M("skin"), seg=12, rings=8)
    B.sphere("mask", 0.15, (-0.5, -0.06, 0.2), M("mannequin"), scale=(0.9, 0.5, 1.05), seg=12, rings=8)
    B.box("crack", (0.02, 0.01, 0.18), (-0.47, -0.14, 0.22), M("black"), rot=(0, 0.4, 0), outline=False)
    for sy in (-1, 1):
        B.tube("leg%d" % sy, [(0.35, sy * 0.1, 0.12), (0.7, sy * 0.2, 0.1), (0.95, sy * 0.15, 0.08)], [0.09, 0.08, 0.07], M("black"))
        B.tube("arm%d" % sy, [(-0.25, sy * 0.2, 0.2), (-0.15, sy * 0.45, 0.08), (0.1, sy * 0.55, 0.06)], [0.07, 0.06, 0.05], M("uniform"))
    if open_:
        B.box("bag", (0.4, 0.3, 0.12), (0.3, -0.5, 0.06), M("cloth_red"), rot=(0, 0, 0.5), bevel=0.03)
        B.box("flap", (0.36, 0.22, 0.02), (0.15, -0.72, 0.03), M("cloth_red"), rot=(0, 0, 0.9))
    else:
        B.box("bag", (0.4, 0.3, 0.32), (0.3, -0.45, 0.16), M("cloth_red"), rot=(0, 0, 0.5), bevel=0.05)
        B.box("strap", (0.06, 0.32, 0.34), (0.25, -0.45, 0.17), M("black"), rot=(0, 0, 0.5))


def h_fitting_room(B: Builder) -> None:
    w, d, h = 1.0, 0.95, 2.0
    B.box("back", (w, 0.06, h), (0, d / 2, h / 2), M("white"))
    for sx in (-w / 2, w / 2):
        B.box("side%.1f" % sx, (0.06, d, h), (sx, 0, h / 2), M("white"))
    B.box("rod", (w, 0.04, 0.04), (0, -d / 2, h - 0.05), M("chrome"))
    import random
    rnd = random.Random(1)
    for k in range(7):
        x = -w / 2 + 0.07 + k * (w - 0.14) / 6
        B.box("fold%d" % k, (0.16, 0.06, h - 0.2), (x, -d / 2 + (0.02 if k % 2 else -0.02), h / 2 + 0.03), M("pink"), bevel=0.02)
    B.box("stool", (0.3, 0.3, 0.4), (0.25, 0.1, 0.2), M("wood"))
    B.box("sign", (0.4, 0.04, 0.16), (0, -d / 2 - 0.02, h + 0.05), M("neon_violet"))
    del rnd


def h_shelving(B: Builder) -> None:
    w, d, h = 1.4, 0.6, 2.0
    for sx in (-w / 2, w / 2):
        for sy in (-d / 2, d / 2):
            B.box("up%.1f%.1f" % (sx, sy), (0.05, 0.05, h), (sx, sy, h / 2), M("orange"))
    for z in (0.15, 0.75, 1.35, 1.95):
        B.box("sh%.2f" % z, (w, d, 0.04), (0, 0, z), M("metal"))
    B.box("bx1", (0.6, 0.45, 0.45), (-0.3, 0.0, 0.4), M("cardboard"))
    B.box("bx2", (0.5, 0.45, 0.4), (0.35, 0.02, 0.97), M("cardboard"), rot=(0, 0, 0.1))
    B.box("bx3", (0.55, 0.45, 0.4), (-0.25, 0.0, 1.57), M("cardboard"), rot=(0, 0, -0.1))
    B.box("tarp", (0.7, 0.04, 1.2), (0.3, -d / 2 - 0.03, 0.62), M("blue"), rot=(0, 0.05, 0))


def h_counter(B: Builder) -> None:
    w, d, h = 1.6, 0.7, 1.05
    B.box("body", (w, d, h), (0, 0, h / 2), M("wood"), bevel=0.02)
    B.box("top", (w + 0.1, d + 0.1, 0.07), (0, 0, h), M("pink_stone"), bevel=0.02)
    for k in range(4):
        B.box("pan%d" % k, (w / 4 - 0.1, 0.03, h - 0.3), (-w / 2 + (k + 0.5) * w / 4, -d / 2 - 0.01, h / 2), M("wood_dark"))
    B.box("bell", (0.12, 0.12, 0.06), (0.4, 0.0, h + 0.06), M("gold"))
    B.box("menu", (0.4, 0.05, 0.3), (-0.4, 0.15, h + 0.18), M("black"))


def h_car(B: Builder) -> None:
    p_car_wreck(B, body="car_blue", plants=False)


CONTAINERS = {
    "mall_register": (c_register, (80, 90), 0.55), "mall_display": (c_display, (80, 80), 0.5),
    "mall_jewel_safe": (c_jewel_safe, (80, 90), 0.6), "mall_cart": (c_cart, (80, 80), 0.45),
    "mall_vending": (c_vending, (70, 110), 0.95), "mall_stock_box": (c_stock_box, (70, 70), 0.45),
    "mall_corpse": (c_corpse, (90, 60), 0.15),
}
HIDES = {
    "mall_fitting_room": (h_fitting_room, (70, 110), 1.0), "mall_shelving": (h_shelving, (80, 110), 1.0),
    "mall_counter": (h_counter, (100, 80), 0.55), "mall_car": (h_car, (180, 130), 0.6),
}


# ============================================================================ rendu

def _use_dir(d: str) -> None:
    BP.PIECES = d


def render_props(only=None) -> None:
    _use_dir(PIECES)
    for k, (fn, fr, tz) in PROPS.items():
        if only and k not in only:
            continue
        BP.render_piece("prop_" + k, fn, fr, target_z=tz, flat=k in FLAT, glow=GLOW.get(k))


def _pot(n: int) -> int:
    p = 1
    while p < n:
        p *= 2
    return p


def _export_container(src_name: str, dst: str) -> None:
    """Pièce rendue à 2 px/u -> densité 1/0.55 px/u, cadre en puissances de 2, pieds en bas au centre."""
    from PIL import Image
    im = Image.open(os.path.join(CPIECES, src_name + ".png")).convert("RGBA")
    with open(os.path.join(CPIECES, src_name + ".json")) as f:
        info = json.load(f)
    k = (1.0 / CONTAINER_SCALE) / BP.PX_PER_WORLD
    w, h = max(1, round(im.width * k)), max(1, round(im.height * k))
    im = im.convert("RGBa").resize((w, h), Image.LANCZOS).convert("RGBA")
    fx = info["feet"][0] * k
    # Point d'appui = bas du contenu (face avant au sol), centré horizontalement sur les pieds 3D.
    bb = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    bottom = bb[3] if bb else h
    half = max(fx, w - fx)
    W = _pot(int(math.ceil(half * 2)) + 2)
    H = _pot(bottom + 4)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ox = int(round(W / 2 - fx))
    oy = H - 4 - bottom
    canvas.paste(im, (ox, oy), im)
    canvas.save(dst, optimize=True)
    print("CONT", os.path.basename(dst), canvas.size)


def render_containers(only=None) -> None:
    os.makedirs(CONT_DIR, exist_ok=True)
    _use_dir(CPIECES)
    for k, (fn, fr, tz) in CONTAINERS.items():
        if only and k not in only:
            continue
        for open_ in (False, True):
            name = k + ("_open" if open_ else "")
            BP.render_piece(name, lambda B, f=fn, o=open_: f(B, o), fr, target_z=tz)
            _export_container(name, os.path.join(CONT_DIR, name + ".png"))
    for k, (fn, fr, tz) in HIDES.items():
        if only and k not in only:
            continue
        name = "hide_" + k
        BP.render_piece(name, fn, fr, target_z=tz)
        _export_container(name, os.path.join(CONT_DIR, name + ".png"))


def pack(atlas_w: int = 2048) -> None:
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
    H = _pot(y + shelf)
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
    atlas.save(os.path.join(OUT_DIR, "atlas.png"), optimize=True)
    with open(os.path.join(OUT_DIR, "atlas_meta.gd"), "w") as f:
        f.write("## Généré par art/blender/mall/build_mall_props.py : NE PAS ÉDITER.\n")
        f.write("## Pièces de assets/sprites/mall/atlas.png : rect [x, y, w, h] (px), feet [x, y]\n")
        f.write("## (point d'appui au sol, px depuis le coin du rect), glow (point chaud). 2 px = 1 unité monde.\n")
        f.write("const PIECES := %s\n" % json.dumps(meta))
    print("ATLAS", atlas.size, len(items))


def main() -> None:
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    if "--pack" not in args:
        if "--containers" not in args:
            render_props(only)
        if "--props" not in args:
            render_containers(only)
    pack()


if __name__ == "__main__":
    main()
