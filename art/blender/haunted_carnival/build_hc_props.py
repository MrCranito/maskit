"""Conteneurs et cachettes du Carnaval hanté en 3D « toon peint » (sprites PNG).

Même pipeline, même caméra (orthographique plongée 48°), même échelle et mêmes ombres bleu nuit
que les décors Far West / centre commercial (fonctions de art/blender/build_props.py et
art/blender/mall/build_mall_props.py, sans les modifier).

Usage (depuis la racine du projet) :
    python3 art/blender/haunted_carnival/build_hc_props.py                 # tout
    python3 art/blender/haunted_carnival/build_hc_props.py --only hc_fair_crate,hc_corpse

Sorties : assets/sprites/haunted_carnival/containers/<kind>.png, <kind>_open.png, hide_<kind>.png
  (dimensions puissances de 2, pieds en bas au centre ; densité 1/0.55 px par unité monde).
Les décors du parc (lampadaires, manèges, stands…) ne sont PAS rendus ici : ils font partie du
rendu pré-calculé (tools/prerender/hc_scene.py) ; le constructeur 2D de repli les dessine en formes.
"""
from __future__ import annotations

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
CONT_DIR = os.path.join(ROOT, "assets", "sprites", "haunted_carnival", "containers")
TMP = os.environ.get("RDM_TMP", "/tmp/rdm_hc")
MP.CPIECES = os.path.join(TMP, "cpieces")
MP.CONT_DIR = CONT_DIR

MP.PAL.update({
    "canvas_red": ("#b8222c", "#4a0e1c", "#e85048"),
    "canvas_white": ("#ece0d4", "#8a7a92", "#fff6ea"),
    "plush": ("#d8a070", "#6a4040", "#f0c898"),
    "plush_pink": ("#e890b8", "#7a3060", "#ffb8d8"),
    "stuffing": ("#f4ecdc", "#9a8a90", "#ffffff"),
    "painted_wood": ("#8a4a5a", "#3a1a30", "#b87080"),
    "iron": ("#4a4a58", "#1a1a2a", "#7a7a90"),
    "dumpster": ("#3a6a4a", "#14302a", "#5a9a6a"),
    "purple": ("#5a3a90", "#241248", "#8a66c0"),
})
M = MP.M
Builder = BP.Builder


def c_fair_crate(B: Builder, open_: bool) -> None:
    B.box("b1", (0.9, 0.7, 0.55), (0, 0.05, 0.275), M("wood"), bevel=0.02)
    for sx in (-0.4, 0.4):
        B.box("strap%.1f" % sx, (0.06, 0.72, 0.56), (sx, 0.05, 0.28), M("iron"))
    B.box("label", (0.4, 0.02, 0.22), (0.05, -0.31, 0.3), M("canvas_white"))
    B.box("star", (0.14, 0.01, 0.14), (0.05, -0.325, 0.3), M("canvas_red"), rot=(0, math.pi / 4, 0), outline=False)
    if open_:
        B.box("lid", (0.92, 0.72, 0.05), (0.0, 0.5, 0.75), M("wood"), rot=(1.1, 0, 0))
        B.box("in", (0.8, 0.6, 0.02), (0, 0.05, 0.54), M("black"), outline=False)
        B.sphere("ball", 0.1, (-0.2, 0.0, 0.62), M("canvas_red"), seg=10, rings=6)
        B.sphere("ball2", 0.09, (0.18, 0.08, 0.6), M("yellow"), seg=10, rings=6)
    else:
        B.box("lid", (0.92, 0.72, 0.06), (0, 0.05, 0.58), M("wood_dark"))
        B.sphere("ball", 0.12, (0.5, -0.3, 0.12), M("canvas_red"), seg=10, rings=6)


def c_stand_counter(B: Builder, open_: bool) -> None:
    w, d, h = 1.5, 0.6, 0.95
    B.box("body", (w, d, h), (0, 0, h / 2), M("painted_wood"), bevel=0.02)
    for k in range(5):
        if k % 2 == 0:
            B.box("stripe%d" % k, (w / 5 - 0.02, 0.02, h - 0.1), (-w / 2 + (k + 0.5) * w / 5, -d / 2 - 0.01, h / 2), M("canvas_red"), outline=False)
    B.box("top", (w + 0.1, d + 0.1, 0.06), (0, 0, h), M("wood"), bevel=0.02)
    B.box("bunting", (w + 0.1, 0.02, 0.12), (0, -d / 2 - 0.02, h - 0.02), M("canvas_white"))
    if open_:
        B.box("drawer", (0.5, 0.4, 0.12), (0.3, -0.45, h - 0.3), M("wood_dark"))
        B.box("drin", (0.44, 0.34, 0.02), (0.3, -0.45, h - 0.24), M("black"), outline=False)
        B.sphere("duck", 0.1, (-0.4, 0.05, h + 0.12), M("yellow"), seg=10, rings=6)
    else:
        B.cyl("jar", 0.14, 0.14, 0.3, (-0.45, 0.0, h + 0.18), M("glass_dark"), seg=12)
        B.sphere("duck", 0.1, (0.1, 0.0, h + 0.12), M("yellow"), seg=10, rings=6)
        B.box("sign", (0.5, 0.04, 0.22), (0.4, 0.1, h + 0.18), M("gold"))


def c_caravan_chest(B: Builder, open_: bool) -> None:
    w, d, h = 0.95, 0.6, 0.6
    B.box("body", (w, d, h), (0, 0, h / 2), M("purple"), bevel=0.02)
    for sx in (-0.3, 0.3):
        B.box("band%.1f" % sx, (0.07, d + 0.02, h + 0.02), (sx, 0, h / 2), M("gold"))
    B.box("lock", (0.14, 0.05, 0.16), (0, -d / 2 - 0.02, h * 0.55), M("gold"))
    if open_:
        B.box("lid", (w, d, 0.1), (0, d / 2, h + d / 2), M("purple"), rot=(math.pi / 2 - 0.3, 0, 0), bevel=0.02)
        B.box("in", (w - 0.1, d - 0.1, 0.02), (0, 0, h - 0.02), M("black"), outline=False)
        B.sphere("gem", 0.07, (-0.2, 0.0, h + 0.04), M("neon_violet"), seg=8, rings=5)
        B.box("coins", (0.3, 0.2, 0.06), (0.2, 0.05, h), M("gold"))
    else:
        B.box("lid", (w, d, 0.14), (0, 0, h + 0.07), M("purple"), bevel=0.05)
        B.box("chain", (w + 0.1, 0.05, 0.05), (0, -d / 2 - 0.02, h * 0.3), M("iron"))


def c_trash_can(B: Builder, open_: bool) -> None:
    B.cyl("body", 0.3, 0.26, 0.85, (0, 0, 0.425), M("dumpster"), seg=14)
    for z in (0.2, 0.6):
        B.cyl("ring%.1f" % z, 0.31, 0.31, 0.04, (0, 0, z), M("iron"), seg=14)
    if open_:
        B.cyl("lid", 0.33, 0.33, 0.05, (0.45, -0.1, 0.03), M("iron"), seg=14, rot=(0.0, 0.0, 0.2))
        B.box("paper", (0.25, 0.2, 0.04), (0.0, -0.05, 0.86), M("paper"), rot=(0, 0, 0.5))
        B.cyl("cup", 0.06, 0.05, 0.14, (0.15, 0.05, 0.92), M("canvas_red"), seg=8, rot=(0.6, 0, 0))
    else:
        B.cyl("lid", 0.34, 0.2, 0.12, (0, 0, 0.9), M("iron"), seg=14)
        B.box("sign", (0.28, 0.02, 0.18), (0, -0.3, 0.5), M("canvas_white"))


def c_corpse(B: Builder, open_: bool) -> None:
    """Forain tombé : costume rayé, chapeau melon, sac à côté."""
    B.cyl("body", 0.22, 0.2, 0.75, (0, 0, 0.18), M("canvas_red"), rot=(0, math.pi / 2, 0.15), seg=12)
    for k in range(3):
        B.cyl("stripe%d" % k, 0.225, 0.225, 0.08, (-0.25 + k * 0.25, 0.0, 0.18), M("canvas_white"), rot=(0, math.pi / 2, 0.15), seg=12, outline=False)
    B.sphere("head", 0.17, (-0.5, 0.05, 0.17), M("skin"), seg=12, rings=8)
    B.cyl("hat", 0.16, 0.16, 0.14, (-0.62, 0.3, 0.07), M("black"), rot=(0.3, 0, 0), seg=12)
    B.cyl("brim", 0.24, 0.24, 0.03, (-0.62, 0.3, 0.02), M("black"), rot=(0.3, 0, 0), seg=14)
    for sy in (-1, 1):
        B.tube("leg%d" % sy, [(0.35, sy * 0.1, 0.12), (0.7, sy * 0.2, 0.1), (0.95, sy * 0.15, 0.08)], [0.09, 0.08, 0.07], M("purple"))
        B.tube("arm%d" % sy, [(-0.25, sy * 0.2, 0.2), (-0.15, sy * 0.45, 0.08), (0.1, sy * 0.55, 0.06)], [0.07, 0.06, 0.05], M("canvas_red"))
    if open_:
        B.box("bag", (0.4, 0.3, 0.12), (0.3, -0.5, 0.06), M("wood_dark"), rot=(0, 0, 0.5), bevel=0.03)
        B.sphere("ball", 0.07, (0.55, -0.6, 0.07), M("yellow"), seg=8, rings=5)
    else:
        B.box("bag", (0.4, 0.3, 0.32), (0.3, -0.45, 0.16), M("wood_dark"), rot=(0, 0, 0.5), bevel=0.05)


def c_plush_corpse(B: Builder, open_: bool) -> None:
    """Peluche géante éventrée (ours), rembourrage au sol."""
    B.sphere("belly", 0.42, (0, 0, 0.3), M("plush"), scale=(1.2, 1.0, 0.7), seg=14, rings=9)
    B.sphere("head", 0.3, (-0.6, 0.05, 0.28), M("plush"), seg=12, rings=8)
    for sy in (-1, 1):
        B.sphere("ear%d" % sy, 0.12, (-0.75, sy * 0.25, 0.48), M("plush_pink"), seg=8, rings=5)
        B.cyl("leg%d" % sy, 0.12, 0.1, 0.5, (0.45, sy * 0.3, 0.12), M("plush"), rot=(0, math.pi / 2, sy * 0.3), seg=10)
    B.box("eye", (0.06, 0.06, 0.02), (-0.86, -0.1, 0.34), M("black"), rot=(0, 0.6, 0.7), outline=False)
    B.box("eye2", (0.06, 0.06, 0.02), (-0.86, 0.1, 0.34), M("black"), rot=(0, 0.6, -0.7), outline=False)
    if open_:
        B.box("rip", (0.5, 0.06, 0.02), (0.05, -0.05, 0.6), M("black"), rot=(0, 0, 0.3), outline=False)
        for k in range(4):
            B.sphere("stuff%d" % k, 0.1, (0.1 + k * 0.15, -0.5 - k * 0.08, 0.08), M("stuffing"), seg=8, rings=5)
    else:
        B.box("rip", (0.4, 0.05, 0.02), (0.05, -0.05, 0.6), M("black"), rot=(0, 0, 0.3), outline=False)
        B.sphere("stuff", 0.12, (0.1, -0.1, 0.62), M("stuffing"), seg=8, rings=5)


def h_photo_booth(B: Builder) -> None:
    w, d, h = 1.0, 0.9, 2.0
    B.box("body", (w, d, h), (0, 0.1, h / 2), M("purple"), bevel=0.02)
    B.box("curtain", (w - 0.1, 0.05, h - 0.5), (0, -d / 2 + 0.1, (h - 0.5) / 2), M("canvas_red"))
    for k in range(5):
        B.box("fold%d" % k, (0.08, 0.06, h - 0.55), (-w / 2 + 0.1 + k * (w - 0.2) / 4, -d / 2 + 0.08, (h - 0.5) / 2), M("canvas_red"), outline=False)
    B.box("sign", (w, 0.06, 0.3), (0, -d / 2 + 0.08, h - 0.2), M("neon_pink"))
    B.box("topsign", (0.5, 0.06, 0.2), (0, -d / 2 + 0.08, h + 0.12), M("gold"))


def h_dumpster(B: Builder) -> None:
    w, d, h = 1.5, 0.8, 1.1
    B.box("body", (w, d, h), (0, 0, h / 2 + 0.1), M("dumpster"), bevel=0.03)
    B.box("lid", (w + 0.05, d / 2, 0.08), (0, d / 4, h + 0.1), M("dumpster"), bevel=0.02)
    B.box("lid2", (w + 0.05, d / 2, 0.08), (0, -d / 4 - 0.2, h + 0.3), M("dumpster"), rot=(0.7, 0, 0), bevel=0.02)
    for sx in (-w / 2 + 0.15, w / 2 - 0.15):
        B.cyl("wheel%.1f" % sx, 0.08, 0.08, 0.06, (sx, -d / 2 + 0.1, 0.08), M("black"), rot=(math.pi / 2, 0, 0), seg=10)
    B.box("tag", (0.6, 0.02, 0.3), (0.1, -d / 2 - 0.01, 0.6), M("neon_violet"), outline=False)
    B.box("bag", (0.4, 0.3, 0.3), (-0.3, 0.1, h + 0.25), M("black"), bevel=0.08)


def h_plush_heap(B: Builder) -> None:
    import random
    rnd = random.Random(7)
    cols = ["plush", "plush_pink", "yellow", "teal", "canvas_red"]
    for k in range(9):
        x = rnd.uniform(-0.5, 0.5)
        y = rnd.uniform(-0.3, 0.3)
        z = 0.22 + (k // 3) * 0.3
        B.sphere("p%d" % k, rnd.uniform(0.18, 0.28), (x, y, z), M(cols[k % 5]), seg=10, rings=7)
        B.sphere("e%d" % k, 0.07, (x - 0.1, y - 0.2, z + 0.12), M(cols[(k + 1) % 5]), seg=6, rings=4)
    B.box("base", (1.3, 0.8, 0.1), (0, 0, 0.05), M("wood"), bevel=0.02)


def h_stand_back(B: Builder) -> None:
    w, d, h = 1.6, 0.7, 1.0
    B.box("body", (w, d, h), (0, 0, h / 2), M("painted_wood"), bevel=0.02)
    for k in range(6):
        if k % 2 == 0:
            B.box("stripe%d" % k, (w / 6 - 0.02, 0.02, h - 0.1), (-w / 2 + (k + 0.5) * w / 6, -d / 2 - 0.01, h / 2), M("canvas_white"), outline=False)
    B.box("top", (w + 0.1, d + 0.1, 0.06), (0, 0, h), M("wood"), bevel=0.02)
    B.box("shelf", (w - 0.2, 0.3, 0.04), (0, 0.15, h + 0.5), M("wood"))
    for k in range(4):
        B.sphere("prize%d" % k, 0.12, (-0.55 + k * 0.37, 0.15, h + 0.62), M(["plush_pink", "plush", "yellow", "teal"][k]), seg=8, rings=5)
    B.box("back", (w, 0.05, 1.2), (0, d / 2 + 0.3, 0.6), M("canvas_red"))


def h_caravan_bed(B: Builder) -> None:
    w, d, h = 1.5, 0.8, 0.5
    B.box("frame", (w, d, h), (0, 0, h / 2), M("wood_dark"), bevel=0.02)
    B.box("mattress", (w - 0.1, d - 0.1, 0.15), (0, 0, h + 0.07), M("canvas_white"), bevel=0.04)
    B.box("blanket", (w * 0.6, d - 0.08, 0.1), (0.25, 0, h + 0.2), M("purple"), bevel=0.04)
    B.box("pillow", (0.35, d - 0.3, 0.14), (-0.5, 0, h + 0.22), M("canvas_red"), bevel=0.05)
    B.box("skirt", (w, 0.02, h - 0.1), (0, -d / 2 - 0.01, h / 2), M("canvas_red"), outline=False)


CONTAINERS = {
    "hc_fair_crate": (c_fair_crate, (80, 80), 0.4), "hc_stand_counter": (c_stand_counter, (100, 90), 0.6),
    "hc_caravan_chest": (c_caravan_chest, (80, 80), 0.4), "hc_trash_can": (c_trash_can, (70, 90), 0.5),
    "hc_corpse": (c_corpse, (90, 60), 0.15), "hc_plush_corpse": (c_plush_corpse, (100, 70), 0.3),
}
HIDES = {
    "hc_photo_booth": (h_photo_booth, (70, 120), 1.0), "hc_dumpster": (h_dumpster, (100, 100), 0.6),
    "hc_plush_heap": (h_plush_heap, (90, 80), 0.5), "hc_stand_back": (h_stand_back, (100, 100), 0.7),
    "hc_caravan_bed": (h_caravan_bed, (100, 70), 0.4),
}


def main() -> None:
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1].split(",")
    MP.CONTAINERS = CONTAINERS
    MP.HIDES = HIDES
    MP.render_containers(only)
    print("DONE", CONT_DIR)


if __name__ == "__main__":
    main()
