"""Décors, conteneurs et cachettes des Pyramides d'Égypte en 3D « toon peint » + atlas.

Même pipeline, même caméra (orthographique plongée 48°), même échelle (2 px par unité monde,
1 BU = 36 unités monde) que les décors Far West / centre commercial (fonctions réutilisées de
art/blender/build_props.py et art/blender/mall/build_mall_props.py, sans les modifier). Ombres
portées chaudes (brun) au lieu du bleu nuit : lumière dorée du désert.

Usage (depuis la racine du projet) :
    python3 art/blender/egypt_pyramids/build_eg_props.py                  # tout
    python3 art/blender/egypt_pyramids/build_eg_props.py --only eg_brazier,eg_jar
    python3 art/blender/egypt_pyramids/build_eg_props.py --pack           # ré-empaqueter seulement

Sorties :
  assets/sprites/egypt_pyramids/atlas.png + atlas_meta.gd   (décors prop_<kind>, glow, white)
  assets/sprites/egypt_pyramids/containers/<kind>.png, <kind>_open.png, hide_<kind>.png
"""
from __future__ import annotations

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "mall"))
import rdm_common as C  # noqa: E402
import build_props as BP  # noqa: E402
import build_mall_props as MP  # noqa: E402
import bpy  # noqa: E402,F401

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "egypt_pyramids")
CONT_DIR = os.path.join(OUT_DIR, "containers")
TMP = os.environ.get("RDM_TMP", "/tmp/rdm_egypt")
PIECES = os.path.join(TMP, "pieces")
CPIECES = os.path.join(TMP, "cpieces")
BP.SHADOW_RGBA = (84, 40, 18, 110)   # ombre chaude brun-rouge

PAL = {
    "sandstone": ("#e2c08a", "#8a5a34", "#fff0c8"),
    "sandstone_dark": ("#b88a56", "#5a3a22", "#e8c08a"),
    "limestone": ("#f0e0bc", "#9a7a5a", "#fff8e8"),
    "basalt": ("#4a4044", "#1e1618", "#7a6a70"),
    "gold": ("#f2c23a", "#8a5a20", "#fff4b0"),
    "gold_dark": ("#c89a2a", "#6a4418", "#f0d070"),
    "lapis": ("#2a4aa8", "#121e56", "#5a80e0"),
    "turquoise": ("#3aa8a0", "#145050", "#8ae0d8"),
    "clay": ("#c0744a", "#5a2e1a", "#e8a070"),
    "clay_dark": ("#8a4a2a", "#3a1a10", "#c07a50"),
    "linen": ("#eadcb8", "#8a7a66", "#fff8e8"),
    "linen_old": ("#c8b48a", "#6a5a46", "#eadcb8"),
    "wood": ("#9a6a3a", "#4a2e1a", "#c89a60"),
    "wood_dark": ("#5e3e22", "#2e1e14", "#8a6040"),
    "bronze": ("#a8743a", "#4a2e18", "#d8a060"),
    "iron": ("#5a5a66", "#26262e", "#8a8a98"),
    "bone": ("#e8e0cc", "#8a8070", "#fffaf0"),
    "red": ("#b03030", "#4e1020", "#e05848"),
    "black": ("#2a2228", "#100c14", "#4a4048"),
    "green": ("#4a8a3a", "#1a3a20", "#7ab860"),
    "palm": ("#5a9a40", "#1e4428", "#9ad070"),
    "skin": ("#c89060", "#6a4030", "#e8b890"),
    "ember": ("#ff8a30", "#8a3010", "#ffd080"),
    "rope": ("#b89a60", "#5a4a30", "#e0c890"),
}
EMIT = {"flame": ("#ffb040", 2.4), "ember_glow": ("#ff6a20", 1.6), "gold_glow": ("#ffd860", 0.9)}


def M(key: str, rim: float = 0.28):
    if key in EMIT:
        col, s = EMIT[key]
        return C.toon("e_" + key, col, emit=s)
    b, s, l = PAL[key]
    return C.toon("e_" + key, b, s, l, rim=rim)


Builder = BP.Builder


# ============================================================================ décors

def p_brazier(B: Builder) -> None:
    """Brasero sur trépied de bronze, braises et flamme."""
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.3
        B.tube("leg%d" % k, [(math.cos(a) * 0.3, math.sin(a) * 0.3, 0.0), (math.cos(a) * 0.14, math.sin(a) * 0.14, 0.8)], [0.04, 0.035], M("bronze"))
    B.cyl("bowl", 0.36, 0.22, 0.26, (0, 0, 0.9), M("bronze"), seg=14)
    B.cyl("rim", 0.38, 0.38, 0.05, (0, 0, 1.03), M("gold_dark"), seg=14)
    B.cyl("coal", 0.3, 0.3, 0.06, (0, 0, 1.05), M("ember_glow"), seg=12, outline=False)
    B.sphere("fl1", 0.22, (0, 0, 1.25), M("flame"), scale=(1, 1, 1.5), seg=10, rings=7, outline=False, shadow=False)
    B.sphere("fl2", 0.12, (0.08, -0.04, 1.55), M("flame"), scale=(1, 1, 1.4), seg=8, rings=6, outline=False, shadow=False)


def p_statue(B: Builder) -> None:
    """Statue d'Anubis assis sur un socle de grès."""
    B.box("base", (0.8, 0.8, 0.3), (0, 0, 0.15), M("sandstone_dark"), bevel=0.03)
    B.box("body", (0.46, 0.5, 0.9), (0, 0.02, 0.75), M("basalt"), bevel=0.04)
    B.box("legs", (0.5, 0.3, 0.45), (0, -0.25, 0.52), M("basalt"), bevel=0.04)
    B.sphere("head", 0.2, (0, 0.0, 1.38), M("basalt"), scale=(1, 1.3, 1), seg=12, rings=8)
    for sx in (-0.1, 0.1):
        B.box("ear%.1f" % sx, (0.07, 0.05, 0.3), (sx, 0.05, 1.62), M("basalt"), rot=(0.15, sx * 1.5, 0))
    B.box("collar", (0.5, 0.52, 0.1), (0, 0.02, 1.18), M("gold"))
    B.box("eyes", (0.26, 0.02, 0.05), (0, -0.2, 1.42), M("gold"), outline=False)


def p_canopic_jars(B: Builder) -> None:
    for k, (x, hm) in enumerate(((-0.42, "skin"), (-0.14, "clay"), (0.14, "bone"), (0.42, "basalt"))):
        B.cyl("j%d" % k, 0.11, 0.13, 0.4, (x, 0, 0.2), M("limestone"), seg=10)
        B.sphere("h%d" % k, 0.12, (x, 0, 0.47), M(hm), scale=(1, 0.9, 1.1), seg=10, rings=7)
    B.box("shelf", (1.2, 0.4, 0.06), (0, 0, 0.03), M("sandstone_dark"))


def p_sarcophagus_big(B: Builder) -> None:
    """Grand sarcophage de pierre à couvercle doré (masque, bras croisés)."""
    B.box("base", (2.3, 1.0, 0.7), (0, 0, 0.35), M("sandstone"), bevel=0.04)
    B.box("lid", (2.1, 0.86, 0.3), (0, 0, 0.85), M("gold"), bevel=0.08)
    B.sphere("face", 0.22, (-0.75, 0, 1.02), M("gold_dark"), scale=(1.1, 1, 0.8), seg=12, rings=8)
    B.box("nemes", (0.7, 0.95, 0.2), (-0.7, 0, 0.95), M("lapis"), bevel=0.04)
    B.box("arms", (0.5, 0.5, 0.12), (0.0, 0, 1.03), M("gold_dark"), rot=(0, 0, 0.7))
    for k in range(4):
        B.box("band%d" % k, (0.06, 0.9, 0.32), (0.2 + k * 0.3, 0, 0.85), M("lapis"), outline=False)


def p_offering_table(B: Builder) -> None:
    B.box("top", (2.0, 0.9, 0.12), (0, 0, 0.8), M("limestone"), bevel=0.02)
    for sx in (-0.8, 0.8):
        B.box("leg%.1f" % sx, (0.25, 0.7, 0.75), (sx, 0, 0.37), M("sandstone_dark"))
    B.sphere("fruit1", 0.12, (-0.4, 0.1, 0.95), M("red"), seg=8, rings=6)
    B.sphere("fruit2", 0.11, (-0.2, -0.15, 0.94), M("clay"), seg=8, rings=6)
    B.cyl("jar", 0.1, 0.13, 0.35, (0.35, 0.1, 1.03), M("clay"), seg=10)
    B.box("gold", (0.3, 0.2, 0.08), (0.7, -0.2, 0.9), M("gold"))
    B.cyl("candle", 0.04, 0.04, 0.3, (0.0, 0.25, 1.0), M("linen"), seg=8)
    B.sphere("flame", 0.06, (0.0, 0.25, 1.22), M("flame"), scale=(1, 1, 1.6), seg=8, rings=6, outline=False, shadow=False)


def p_embalming_table(B: Builder) -> None:
    B.box("top", (1.9, 0.8, 0.1), (0, 0, 0.75), M("basalt"), bevel=0.02)
    for sx in (-0.75, 0.75):
        B.box("leg%.1f" % sx, (0.2, 0.6, 0.7), (sx, 0, 0.35), M("basalt"))
    B.cyl("body", 0.2, 0.2, 1.5, (0, 0, 0.95), M("linen_old"), rot=(0, math.pi / 2, 0), seg=12)
    B.sphere("head", 0.18, (-0.8, 0, 0.95), M("linen_old"), seg=10, rings=7)
    for k in range(5):
        B.box("wrap%d" % k, (0.06, 0.44, 0.44), (-0.5 + k * 0.3, 0, 0.95), M("linen"), rot=(0.3 * (k % 2), 0, 0), outline=False)
    B.cyl("jar", 0.09, 0.11, 0.3, (0.75, 0.3, 0.9), M("limestone"), seg=8)


def p_weapon_rack(B: Builder) -> None:
    B.box("frame", (1.3, 0.12, 0.08), (0, 0.15, 0.04), M("wood_dark"))
    B.box("bar", (1.3, 0.08, 0.08), (0, 0.15, 1.0), M("wood_dark"))
    for sx in (-0.6, 0.6):
        B.box("post%.1f" % sx, (0.08, 0.1, 1.1), (sx, 0.15, 0.55), M("wood"))
    for k in range(4):
        x = -0.42 + k * 0.28
        B.tube("spear%d" % k, [(x, 0.05, 0.05), (x + 0.05, 0.1, 1.5)], [0.025, 0.02], M("wood"))
        B.box("tip%d" % k, (0.06, 0.03, 0.2), (x + 0.05, 0.1, 1.6), M("bronze"))
    B.box("shield", (0.5, 0.06, 0.6), (0.35, 0.02, 0.55), M("bronze"), bevel=0.04)
    B.sphere("boss", 0.08, (0.35, -0.02, 0.55), M("gold"), seg=8, rings=6)


def p_bench(B: Builder) -> None:
    B.box("seat", (1.4, 0.45, 0.12), (0, 0, 0.42), M("sandstone"), bevel=0.02)
    for sx in (-0.55, 0.55):
        B.box("leg%.1f" % sx, (0.18, 0.4, 0.38), (sx, 0, 0.19), M("sandstone_dark"))
    B.box("cushion", (0.6, 0.38, 0.08), (-0.2, 0, 0.52), M("red"), bevel=0.03)


def p_scroll_shelf(B: Builder) -> None:
    w, d, h = 1.4, 0.45, 1.5
    B.box("back", (w, 0.05, h), (0, d / 2, h / 2), M("wood_dark"))
    for sx in (-w / 2, w / 2):
        B.box("side%.1f" % sx, (0.05, d, h), (sx, 0, h / 2), M("wood"))
    for z in (0.1, 0.55, 1.0, 1.45):
        B.box("sh%.2f" % z, (w, d, 0.05), (0, 0, z), M("wood"))
    import random
    rnd = random.Random(3)
    for z in (0.12, 0.57, 1.02):
        x = -w / 2 + 0.1
        while x < w / 2 - 0.1:
            B.cyl("sc%.2f%.2f" % (x, z), 0.06, 0.06, d - 0.08, (x, 0, z + 0.07), M(rnd.choice(["linen", "linen_old", "clay"])), rot=(math.pi / 2, 0, 0), seg=8, outline=False)
            x += 0.14


def p_spikes(B: Builder) -> None:
    """Dalle piégée : grille de piques de bronze sorties du sol (plat)."""
    B.box("slab", (1.1, 1.1, 0.04), (0, 0, 0.02), M("basalt"))
    for i in range(3):
        for j in range(3):
            x, y = -0.35 + i * 0.35, -0.35 + j * 0.35
            B.cyl("sp%d%d" % (i, j), 0.06, 0.0, 0.5, (x, y, 0.28), M("bronze"), seg=6)


def p_rubble(B: Builder) -> None:
    import random
    rnd = random.Random(5)
    for k in range(7):
        x, y = rnd.uniform(-0.5, 0.5), rnd.uniform(-0.35, 0.35)
        s = rnd.uniform(0.12, 0.3)
        B.box("r%d" % k, (s, s * 0.8, s * 0.6), (x, y, s * 0.3), M(rnd.choice(["sandstone", "sandstone_dark", "limestone"])), rot=(0, 0, rnd.uniform(0, 3)), bevel=0.02)


def p_cactus(B: Builder) -> None:
    BP.p_cactus(B)


def p_bones(B: Builder) -> None:
    B.sphere("skull", 0.16, (-0.3, 0.05, 0.14), M("bone"), scale=(1.1, 1, 0.9), seg=10, rings=7)
    B.box("jaw", (0.2, 0.14, 0.06), (-0.26, -0.08, 0.05), M("bone"))
    for k in range(4):
        B.tube("rib%d" % k, [(0.0 + k * 0.15, -0.25, 0.03), (0.05 + k * 0.15, 0.0, 0.14), (0.0 + k * 0.15, 0.25, 0.03)], [0.025, 0.03, 0.025], M("bone"))
    B.tube("bone", [(0.2, -0.4, 0.04), (0.75, -0.2, 0.04)], [0.04, 0.04], M("bone"))


def p_tent(B: Builder) -> None:
    """Tente de pilleurs : toile rayée sur piquets, tapis et sacs devant."""
    w, d, h = 2.6, 2.2, 1.5
    B.box("rug", (1.4, 0.8, 0.03), (0, -1.3, 0.015), M("red"), outline=False)
    for sx in (-w / 2, w / 2):
        B.tube("pole%.1f" % sx, [(sx, d / 2 - 0.2, 0), (sx, d / 2 - 0.2, h * 0.75)], [0.04, 0.03], M("wood"))
    B.tube("mast", [(0, 0.1, 0), (0, 0.1, h)], [0.05, 0.04], M("wood"))
    bm = C.bm_loft([[(-w / 2, -d / 2, 0.0), (w / 2, -d / 2, 0.0), (w / 2, d / 2, 0.0), (-w / 2, d / 2, 0.0)],
                    [(-w / 2 + 0.1, -d / 2 + 0.1, h * 0.75), (w / 2 - 0.1, -d / 2 + 0.1, h * 0.75), (w / 2 - 0.1, d / 2 - 0.1, h * 0.75), (-w / 2 + 0.1, d / 2 - 0.1, h * 0.75)],
                    [(-0.3, 0.0, h), (0.3, 0.0, h), (0.3, 0.2, h), (-0.3, 0.2, h)]], cap_start=False, cap_end=True)
    B.add("canvas", bm, M("linen"))
    for k in range(5):
        B.box("stripe%d" % k, (0.12, 0.02, h * 0.7), (-1.0 + k * 0.5, -d / 2 - 0.01, h * 0.37), M("red"), rot=(-0.25, 0, 0), outline=False)
    B.box("sack", (0.5, 0.4, 0.4), (1.0, -1.3, 0.2), M("rope"), bevel=0.06)
    B.cyl("pot", 0.14, 0.18, 0.4, (-1.0, -1.3, 0.2), M("clay"), seg=10)


PROPS = {
    "eg_brazier": (p_brazier, (60, 110), 1.1), "eg_statue": (p_statue, (70, 120), 0.9),
    "eg_canopic_jars": (p_canopic_jars, (90, 60), 0.3), "eg_sarcophagus_big": (p_sarcophagus_big, (160, 110), 0.6),
    "eg_offering_table": (p_offering_table, (150, 100), 0.6), "eg_embalming_table": (p_embalming_table, (140, 100), 0.6),
    "eg_weapon_rack": (p_weapon_rack, (100, 110), 0.8), "eg_bench": (p_bench, (100, 70), 0.35),
    "eg_scroll_shelf": (p_scroll_shelf, (100, 110), 0.8), "eg_spikes": (p_spikes, (90, 90), 0.0),
    "eg_rubble": (p_rubble, (80, 60), 0.15), "eg_cactus": (p_cactus, (70, 110), 1.0),
    "eg_bones": (p_bones, (80, 60), 0.1), "eg_tent": (p_tent, (200, 170), 0.7),
}
FLAT = {"eg_spikes", "eg_bones"}
GLOW = {"eg_brazier": (0.0, 0.0, 1.3), "eg_offering_table": (0.0, 0.25, 1.2)}


# ============================================================================ conteneurs et cachettes

def c_jar(B: Builder, open_: bool) -> None:
    B.cyl("body", 0.24, 0.3, 0.5, (0, 0, 0.3), M("clay"), seg=12)
    B.cyl("foot", 0.2, 0.24, 0.1, (0, 0, 0.05), M("clay_dark"), seg=12)
    B.cyl("neck", 0.3, 0.2, 0.15, (0, 0, 0.62), M("clay"), seg=12)
    for k in range(3):
        B.box("band%d" % k, (0.62, 0.62, 0.03), (0, 0, 0.3 + k * 0.1), M("clay_dark"), outline=False)
    if open_:
        B.cyl("lid", 0.2, 0.2, 0.05, (0.35, -0.2, 0.03), M("linen_old"), seg=10, rot=(0.3, 0, 0))
        B.cyl("hole", 0.17, 0.17, 0.02, (0, 0, 0.7), M("black"), seg=10, outline=False)
    else:
        B.cyl("lid", 0.22, 0.2, 0.06, (0, 0, 0.72), M("linen_old"), seg=10)
        B.box("seal", (0.1, 0.1, 0.03), (0, 0, 0.76), M("red"))


def c_sarcophagus(B: Builder, open_: bool) -> None:
    B.box("base", (1.3, 0.6, 0.5), (0, 0, 0.25), M("sandstone"), bevel=0.03)
    for k in range(3):
        B.box("gl%d" % k, (0.3, 0.02, 0.3), (-0.4 + k * 0.4, -0.31, 0.25), M("sandstone_dark"), outline=False)
    if open_:
        B.box("lid", (1.25, 0.55, 0.14), (0.25, 0.25, 0.6), M("gold"), rot=(0.4, 0.1, 0), bevel=0.03)
        B.box("inside", (1.15, 0.45, 0.02), (0, 0, 0.5), M("black"), outline=False)
        B.cyl("mummy", 0.14, 0.14, 1.0, (0, 0, 0.6), M("linen_old"), rot=(0, math.pi / 2, 0), seg=10)
    else:
        B.box("lid", (1.25, 0.55, 0.14), (0, 0, 0.57), M("gold"), bevel=0.04)
        B.sphere("face", 0.14, (-0.42, 0, 0.66), M("gold_dark"), scale=(1.1, 1, 0.7), seg=10, rings=7)
        B.box("nemes", (0.42, 0.56, 0.1), (-0.4, 0, 0.63), M("lapis"), bevel=0.02)


def c_chest(B: Builder, open_: bool) -> None:
    B.box("body", (0.9, 0.55, 0.45), (0, 0, 0.225), M("wood"), bevel=0.02)
    for sx in (-0.38, 0.38):
        B.box("band%.1f" % sx, (0.06, 0.57, 0.47), (sx, 0, 0.23), M("bronze"), outline=False)
    if open_:
        B.box("lid", (0.9, 0.55, 0.1), (0, 0.3, 0.72), M("wood_dark"), rot=(-1.3, 0, 0), bevel=0.02)
        B.box("inside", (0.8, 0.45, 0.02), (0, 0, 0.44), M("black"), outline=False)
        B.sphere("coins", 0.12, (0.1, 0, 0.44), M("gold"), scale=(1.5, 1, 0.5), seg=8, rings=5, outline=False)
    else:
        B.box("lid", (0.9, 0.55, 0.12), (0, 0, 0.5), M("wood_dark"), bevel=0.04)
        B.box("lock", (0.12, 0.05, 0.14), (0, -0.29, 0.42), M("bronze"))


def c_gold_chest(B: Builder, open_: bool) -> None:
    B.box("body", (1.0, 0.6, 0.5), (0, 0, 0.25), M("gold"), bevel=0.03)
    for k in range(3):
        B.box("gem%d" % k, (0.12, 0.03, 0.12), (-0.3 + k * 0.3, -0.31, 0.25), M("lapis"), outline=False)
    B.box("trim", (1.04, 0.64, 0.05), (0, 0, 0.5), M("gold_dark"))
    if open_:
        B.box("lid", (1.0, 0.6, 0.14), (0, 0.32, 0.8), M("gold"), rot=(-1.2, 0, 0), bevel=0.04)
        B.box("inside", (0.9, 0.5, 0.02), (0, 0, 0.5), M("black"), outline=False)
        B.sphere("treasure", 0.2, (0, 0, 0.5), M("gold_glow"), scale=(2.0, 1.1, 0.6), seg=10, rings=6, outline=False)
        B.sphere("gem", 0.07, (0.2, 0.05, 0.6), M("turquoise"), seg=8, rings=5, outline=False)
    else:
        B.box("lid", (1.0, 0.6, 0.16), (0, 0, 0.58), M("gold"), bevel=0.06)
        B.box("cart", (0.3, 0.05, 0.2), (0, -0.31, 0.5), M("lapis"))
        B.sphere("scarab", 0.08, (0, -0.33, 0.5), M("turquoise"), scale=(1, 0.6, 1.2), seg=8, rings=6)


def c_altar(B: Builder, open_: bool) -> None:
    B.box("base", (1.2, 0.6, 0.2), (0, 0, 0.1), M("sandstone_dark"), bevel=0.02)
    B.box("top", (1.1, 0.55, 0.55), (0, 0, 0.47), M("limestone"), bevel=0.03)
    B.box("frieze", (1.12, 0.57, 0.1), (0, 0, 0.6), M("gold"), outline=False)
    for sx in (-0.4, 0.4):
        B.cyl("cnd%.1f" % sx, 0.035, 0.035, 0.25, (sx, -0.1, 0.87), M("linen"), seg=8)
        B.sphere("fl%.1f" % sx, 0.05, (sx, -0.1, 1.05), M("flame"), scale=(1, 1, 1.6), seg=8, rings=6, outline=False, shadow=False)
    if open_:
        B.box("cloth", (0.5, 0.4, 0.03), (0.0, 0.0, 0.76), M("linen_old"), rot=(0, 0, 0.3))
    else:
        B.cyl("bowl", 0.18, 0.12, 0.12, (0, 0.05, 0.81), M("gold"), seg=12)
        B.sphere("fruit", 0.09, (0.05, 0.05, 0.9), M("red"), seg=8, rings=6)
        B.sphere("fruit2", 0.08, (-0.08, 0.1, 0.88), M("clay"), seg=8, rings=6)


def c_basket(B: Builder, open_: bool) -> None:
    B.cyl("body", 0.28, 0.34, 0.4, (0, 0, 0.2), M("rope"), seg=12)
    for k in range(4):
        B.box("ring%d" % k, (0.7, 0.7, 0.02), (0, 0, 0.08 + k * 0.1), M("wood"), outline=False)
    if open_:
        B.cyl("lid", 0.3, 0.3, 0.04, (0.4, -0.15, 0.02), M("rope"), seg=10)
        B.cyl("in", 0.26, 0.26, 0.02, (0, 0, 0.4), M("black"), seg=10, outline=False)
    else:
        B.cyl("lid", 0.34, 0.3, 0.08, (0, 0, 0.43), M("rope"), seg=12)
        B.box("knob", (0.1, 0.1, 0.08), (0, 0, 0.5), M("wood"))


def c_mummy(B: Builder, open_: bool) -> None:
    """Momie allongée, bandelettes ; fouillée : bandelettes défaites."""
    B.cyl("body", 0.2, 0.18, 1.3, (0.1, 0, 0.18), M("linen_old"), rot=(0, math.pi / 2, 0.08), seg=12)
    B.sphere("head", 0.19, (-0.6, 0, 0.18), M("linen_old"), seg=12, rings=8)
    for k in range(6):
        B.box("wrap%d" % k, (0.06, 0.4, 0.4), (-0.35 + k * 0.22, 0, 0.18), M("linen"), rot=(0.2 * (k % 2), 0, 0.1), outline=False)
    B.box("mask", (0.1, 0.22, 0.2), (-0.72, 0, 0.2), M("gold"), bevel=0.02)
    if open_:
        B.tube("loose", [(-0.4, -0.25, 0.05), (0.0, -0.5, 0.02), (0.4, -0.45, 0.02)], [0.04, 0.035, 0.03], M("linen"))
        B.box("hole", (0.3, 0.25, 0.04), (0.2, 0.0, 0.36), M("black"), outline=False)


def c_corpse(B: Builder, open_: bool) -> None:
    """Pilleur momifié par le sable (chèche, veste) avec sa sacoche."""
    B.cyl("body", 0.22, 0.2, 0.75, (0, 0, 0.18), M("linen_old"), rot=(0, math.pi / 2, 0.15), seg=12)
    B.sphere("head", 0.17, (-0.5, 0.05, 0.17), M("skin"), seg=12, rings=8)
    B.sphere("scarf", 0.18, (-0.5, 0.05, 0.19), M("red"), scale=(1, 1, 0.6), seg=12, rings=8)
    for sy in (-1, 1):
        B.tube("leg%d" % sy, [(0.35, sy * 0.1, 0.12), (0.7, sy * 0.2, 0.1), (0.95, sy * 0.15, 0.08)], [0.09, 0.08, 0.07], M("black"))
        B.tube("arm%d" % sy, [(-0.25, sy * 0.2, 0.2), (-0.15, sy * 0.45, 0.08), (0.1, sy * 0.55, 0.06)], [0.07, 0.06, 0.05], M("linen_old"))
    if open_:
        B.box("bag", (0.4, 0.3, 0.12), (0.3, -0.5, 0.06), M("rope"), rot=(0, 0, 0.5), bevel=0.03)
    else:
        B.box("bag", (0.4, 0.3, 0.32), (0.3, -0.45, 0.16), M("rope"), rot=(0, 0, 0.5), bevel=0.05)
        B.box("strap", (0.06, 0.32, 0.34), (0.25, -0.45, 0.17), M("black"), rot=(0, 0, 0.5))


def h_sarcophagus_hide(B: Builder) -> None:
    B.box("base", (1.3, 0.6, 0.55), (0, 0, 0.275), M("sandstone_dark"), bevel=0.03)
    B.box("lid", (1.25, 0.55, 0.14), (0.15, 0.2, 0.66), M("sandstone"), rot=(0.25, 0.05, 0), bevel=0.03)
    B.box("inside", (1.15, 0.45, 0.02), (0, 0, 0.55), M("black"), outline=False)


def h_big_jar(B: Builder) -> None:
    B.cyl("body", 0.34, 0.42, 0.9, (0, 0, 0.5), M("clay"), seg=14)
    B.cyl("foot", 0.3, 0.34, 0.1, (0, 0, 0.05), M("clay_dark"), seg=14)
    B.cyl("neck", 0.42, 0.3, 0.2, (0, 0, 1.05), M("clay"), seg=14)
    B.cyl("mouth", 0.26, 0.26, 0.03, (0, 0, 1.16), M("black"), seg=12, outline=False)
    for k in range(2):
        B.box("band%d" % k, (0.86, 0.86, 0.03), (0, 0, 0.5 + k * 0.25), M("clay_dark"), outline=False)


def h_hay_cart(B: Builder) -> None:
    B.box("bed", (1.8, 1.0, 0.15), (0, 0, 0.45), M("wood"), bevel=0.02)
    for sx in (-0.6, 0.6):
        BP.wheel(B, "w%.1f" % sx, 0.4, (sx, -0.55, 0.4), M("wood_dark"), M("wood"), axis="y", spokes=8, thick=0.07)
        BP.wheel(B, "wb%.1f" % sx, 0.4, (sx, 0.55, 0.4), M("wood_dark"), M("wood"), axis="y", spokes=8, thick=0.07)
    B.sphere("hay", 0.5, (0, 0, 0.8), M("rope"), scale=(1.6, 0.9, 0.6), seg=12, rings=8)
    B.tube("shaft", [(0.9, 0.3, 0.45), (1.6, 0.3, 0.3)], [0.04, 0.03], M("wood"))


CONTAINERS = {
    "eg_jar": (c_jar, (60, 70), 0.4), "eg_sarcophagus": (c_sarcophagus, (110, 80), 0.4),
    "eg_chest": (c_chest, (80, 70), 0.3), "eg_gold_chest": (c_gold_chest, (90, 80), 0.35),
    "eg_altar": (c_altar, (100, 90), 0.5), "eg_basket": (c_basket, (60, 60), 0.25),
    "eg_mummy": (c_mummy, (110, 60), 0.15), "eg_corpse": (c_corpse, (90, 60), 0.15),
}
HIDES = {
    "eg_sarcophagus_hide": (h_sarcophagus_hide, (110, 80), 0.4), "eg_big_jar": (h_big_jar, (80, 100), 0.6),
    "eg_hay_cart": (h_hay_cart, (150, 110), 0.5),
}


# ============================================================================ rendu

def render_props(only=None) -> None:
    BP.PIECES = PIECES
    for k, (fn, fr, tz) in PROPS.items():
        if only and k not in only:
            continue
        BP.render_piece("prop_" + k, fn, fr, target_z=tz, flat=k in FLAT, glow=GLOW.get(k))


def render_containers(only=None) -> None:
    os.makedirs(CONT_DIR, exist_ok=True)
    BP.PIECES = CPIECES
    MP.CPIECES = CPIECES
    for k, (fn, fr, tz) in CONTAINERS.items():
        if only and k not in only:
            continue
        for open_ in (False, True):
            name = k + ("_open" if open_ else "")
            BP.render_piece(name, lambda B, f=fn, o=open_: f(B, o), fr, target_z=tz)
            MP._export_container(name, os.path.join(CONT_DIR, name + ".png"))
    for k, (fn, fr, tz) in HIDES.items():
        if only and k not in only:
            continue
        name = "hide_" + k
        BP.render_piece(name, fn, fr, target_z=tz)
        MP._export_container(name, os.path.join(CONT_DIR, name + ".png"))


def pack() -> None:
    MP.PIECES = PIECES
    MP.DECALS = os.path.join(TMP, "decals_none")
    MP.OUT_DIR = OUT_DIR
    MP.pack()
    # En-tête du fichier de métadonnées : généré par ce script.
    mp = os.path.join(OUT_DIR, "atlas_meta.gd")
    with open(mp) as f:
        txt = f.read()
    txt = txt.replace("art/blender/mall/build_mall_props.py", "art/blender/egypt_pyramids/build_eg_props.py").replace("assets/sprites/mall/atlas.png", "assets/sprites/egypt_pyramids/atlas.png")
    with open(mp, "w") as f:
        f.write(txt)


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
