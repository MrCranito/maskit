"""Conteneurs fouillables (fermé + ouvert) et cachettes de la Station Orbitale Kagami.

Usage : python3 art/blender/space_station/build_containers.py [--only locker,terminal]

Sorties : assets/sprites/space_station/containers/<kind>.png, <kind>_open.png, hide_<kind>.png
Échelle : LootContainer / HidingSpot affichent ces PNG à l'échelle 0,55 → rendu à 1/0,55 px par
unité monde ; point d'appui au centre horizontal, 4 px au-dessus du bord bas (« foot » = 4).
"""
from __future__ import annotations

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ss_art import C, M, ROOT, hazard_band, render_sprite  # noqa: E402

OUT = os.path.join(ROOT, "assets", "sprites", "space_station", "containers")
PXW = 1.0 / 0.55


def locker(B, opened: bool, double: bool = False) -> None:
    w = 0.95 if double else 0.6
    d, h = 0.5, 1.75
    B.box("body", (w, d, h), (0, 0.05, h / 2), M("steel_dark"), bevel=0.02)
    B.box("top", (w + 0.03, d + 0.03, 0.05), (0, 0.05, h), M("gunmetal"))
    n = 2 if double else 1
    dw = (w - 0.06) / n
    for i in range(n):
        x = -w / 2 + 0.03 + dw * (i + 0.5)
        if opened and i == 0:
            # Intérieur sombre + étagère + objets, porte pivotée vers l'avant gauche.
            B.box("inside%d" % i, (dw - 0.04, 0.02, h - 0.12), (x, -d / 2 + 0.08, h / 2), M("rubber"))
            B.box("shelf%d" % i, (dw - 0.06, d - 0.1, 0.03), (x, 0.05, h * 0.7), M("steel"))
            B.box("bag%d" % i, (dw * 0.6, 0.25, 0.28), (x, 0.0, h * 0.7 + 0.15), M("olive"), bevel=0.04)
            B.cyl("can%d" % i, 0.06, 0.06, 0.16, (x + 0.1, -0.05, 0.4), M("orange"), seg=10)
            B.box("door%d" % i, (0.03, dw, h - 0.1), (x - dw / 2 - dw * 0.35, -d / 2 - dw * 0.42, h / 2), M("steel"),
                  rot=(0, 0, -0.55))
        else:
            B.box("door%d" % i, (dw - 0.03, 0.03, h - 0.1), (x, -d / 2 + 0.03, h / 2), M("steel"))
            for k in range(4):
                B.box("vent%d%d" % (i, k), (dw * 0.6, 0.02, 0.03), (x, -d / 2 + 0.01, h - 0.25 - k * 0.07), M("rubber"))
            B.box("handle%d" % i, (0.03, 0.03, 0.18), (x + dw * 0.32, -d / 2 + 0.0, h * 0.5), M("gunmetal"))
            B.box("tag%d" % i, (dw * 0.4, 0.015, 0.08), (x, -d / 2 + 0.01, h * 0.62), M("white_panel", rim=0.0), outline=False)
    hazard_band(B, "hz", w - 0.05, (0, -d / 2 + 0.03, 0.06), h=0.07, n=6)


def cargo_crate(B, opened: bool) -> None:
    w, d, h = 1.05, 0.8, 0.62
    B.box("body", (w, d, h), (0, 0, h / 2), M("orange"), bevel=0.03)
    for x in (-w / 2 + 0.06, w / 2 - 0.06):
        B.box("rib%.1f" % x, (0.08, d + 0.03, h + 0.02), (x, 0, h / 2), M("steel_dark"))
    B.box("label", (0.32, 0.02, 0.2), (0.0, -d / 2 - 0.005, h * 0.55), M("white_panel", rim=0.0), outline=False)
    B.box("stencil", (0.22, 0.02, 0.04), (0.0, -d / 2 - 0.012, h * 0.55), M("rubber", rim=0.0), outline=False)
    if opened:
        B.box("cavity", (w - 0.14, d - 0.12, 0.03), (0, 0, h + 0.005), M("rubber"))
        B.box("lid", (w, 0.06, d), (0, d / 2 + 0.12, h + d / 2 - 0.1), M("orange"), rot=(-0.25, 0, 0))
        B.box("item1", (0.3, 0.25, 0.15), (-0.2, -0.05, h + 0.06), M("steel"))
        B.cyl("item2", 0.08, 0.08, 0.3, (0.25, 0.05, h + 0.05), M("screen_cyan"), rot=(0, math.pi / 2, 0), seg=10)
    else:
        B.box("lid", (w + 0.02, d + 0.02, 0.06), (0, 0, h + 0.03), M("steel_dark"))
        B.box("latch", (0.12, 0.04, 0.1), (0, -d / 2 - 0.02, h - 0.05), M("hazard"))


def med_cabinet(B, opened: bool) -> None:
    w, d, h = 0.85, 0.42, 1.45
    B.box("body", (w, d, h), (0, 0.1, h / 2), M("white_panel"), bevel=0.03)
    B.box("base", (w + 0.02, d + 0.02, 0.08), (0, 0.1, 0.04), M("gunmetal"))
    if opened:
        B.box("inside", (w - 0.08, 0.02, h - 0.16), (0, -d / 2 + 0.16, h / 2 + 0.02), M("steel_dark"))
        for z in (0.45, 0.85, 1.2):
            B.box("shelf%.1f" % z, (w - 0.1, d - 0.08, 0.025), (0, 0.1, z), M("steel"))
        rnd = random.Random(3)
        for z in (0.45, 0.85, 1.2):
            for k in range(4):
                B.cyl("bot%.1f%d" % (z, k), 0.04, 0.04, 0.14, (-0.27 + k * 0.18, 0.0, z + 0.08),
                      M(rnd.choice(["red", "teal", "screen_green", "white_panel"])), seg=8)
        for sx in (-1, 1):
            B.box("door%d" % sx, (w / 2 - 0.03, 0.03, h - 0.1), (sx * (w / 2 + w * 0.12), -d / 2 - w * 0.15, h / 2), M("white_panel"),
                  rot=(0, 0, sx * 0.9))
    else:
        for sx in (-1, 1):
            B.box("door%d" % sx, (w / 2 - 0.03, 0.03, h - 0.1), (sx * w / 4, -d / 2 + 0.11, h / 2), M("white_panel"))
        B.box("cross_v", (0.08, 0.02, 0.28), (0, -d / 2 + 0.09, h * 0.68), M("red", rim=0.0), outline=False)
        B.box("cross_h", (0.28, 0.02, 0.08), (0, -d / 2 + 0.09, h * 0.68), M("red", rim=0.0), outline=False)
        B.box("led", (0.06, 0.02, 0.04), (w / 2 - 0.1, -d / 2 + 0.09, h - 0.12), M("led_green"), outline=False)


def armory_chest(B, opened: bool) -> None:
    w, d, h = 1.15, 0.72, 0.6
    B.box("body", (w, d, h), (0, 0, h / 2), M("gunmetal"), bevel=0.04)
    B.box("trim", (w + 0.02, d + 0.02, 0.06), (0, 0, h - 0.04), M("hazard"))
    for x in (-w / 2 + 0.12, w / 2 - 0.12):
        B.box("corner%.1f" % x, (0.12, d + 0.04, h + 0.02), (x, 0, h / 2), M("steel_dark"))
    if opened:
        B.box("cavity", (w - 0.16, d - 0.14, 0.03), (0, 0, h + 0.005), M("rubber"))
        B.box("glowbed", (w - 0.3, d - 0.3, 0.02), (0, 0, h + 0.02), M("screen_amber"), outline=False)
        B.box("rifle", (0.7, 0.12, 0.08), (0, -0.05, h + 0.06), M("steel"))
        bm = C.bm_box(w, 0.08, d * 0.95, bevel=0.03)
        C.bm_xform(bm, loc=(0, d / 2 + 0.05, h + d * 0.45), rot=(-0.2, 0, 0))
        B.add("lid", bm, M("gunmetal"))
    else:
        bm = C.bm_box(w, d, 0.2, bevel=0.06)
        C.bm_xform(bm, loc=(0, 0, h + 0.08))
        B.add("lid", bm, M("gunmetal"))
        B.box("lock", (0.2, 0.05, 0.18), (0, -d / 2 - 0.02, h - 0.08), M("steel"))
        B.box("lockled", (0.08, 0.02, 0.05), (0, -d / 2 - 0.05, h - 0.05), M("alarm_red"), outline=False)
        B.box("stripe", (0.6, 0.02, 0.08), (0, -d / 2 - 0.005, h * 0.4), M("screen_amber"), outline=False)


def cryo_pod(B, opened: bool, standing: bool = False) -> None:
    if standing:
        h, r = 1.85, 0.48
        B.cyl("base", r + 0.08, r + 0.1, 0.18, (0, 0.1, 0.09), M("gunmetal"), seg=20)
        B.cyl("back", r, r, h - 0.3, (0, 0.22, h / 2 + 0.05), M("white_panel"), seg=20)
        B.sphere("frost", r * 0.8, (0, -0.22, h / 2 + 0.05), M("liquid_cyan"), scale=(0.85, 0.5, 1.7), seg=18, rings=10, outline=False)
        B.cyl("cap", r + 0.06, r, 0.2, (0, 0.12, h - 0.05), M("gunmetal"), seg=20)
        B.box("panel", (0.3, 0.03, 0.12), (0, -r + 0.05, 0.3), M("screen_cyan"), outline=False)
        return
    L, w = 1.75, 0.8
    B.box("bed", (L, w, 0.45), (0, 0, 0.22), M("gunmetal"), bevel=0.04)
    B.box("trim", (L + 0.02, w + 0.02, 0.05), (0, 0, 0.42), M("steel"))
    B.box("panel", (0.4, 0.02, 0.12), (L / 2 - 0.35, -w / 2 - 0.01, 0.25), M("screen_cyan"), outline=False)
    # Occupant (cadavre de l'équipage, masque blanc fêlé).
    B.sphere("body", 0.25, (0.05, 0, 0.6), M("cloth_blue"), scale=(2.4, 0.9, 0.5), seg=14, rings=8)
    B.sphere("head", 0.15, (-0.6, 0, 0.63), M("gunmetal"), scale=(1, 0.9, 0.8))
    B.sphere("mask", 0.12, (-0.64, -0.06, 0.68), M("mask"), scale=(0.9, 0.6, 0.9))
    B.box("crack", (0.01, 0.01, 0.12), (-0.64, -0.13, 0.68), M("rubber"), rot=(0, 0.4, 0), outline=False)
    if opened:
        bm = C.bm_box(L - 0.1, 0.06, w * 0.7, bevel=0.03)
        C.bm_xform(bm, loc=(0, w / 2 + 0.1, 0.75), rot=(-0.35, 0, 0))
        B.add("lid", bm, M("glass_dark"))
        B.box("frost_lid", (L - 0.3, 0.02, w * 0.5), (0, w / 2 + 0.05, 0.78), M("liquid_cyan"), rot=(-0.35, 0, 0), outline=False)
    else:
        B.sphere("lid", 0.4, (0, 0, 0.55), M("liquid_cyan"), scale=(2.1, 0.95, 0.65), seg=20, rings=10)
        B.box("frame", (L, 0.06, 0.06), (0, -w / 2, 0.47), M("steel"))


def terminal(B, opened: bool) -> None:
    w, d, h = 0.75, 0.5, 1.35
    B.box("body", (w, d, h), (0, 0.1, h / 2), M("steel_dark"), bevel=0.03)
    bm = C.bm_box(w - 0.12, 0.05, 0.5, bevel=0.01)
    C.bm_xform(bm, loc=(0, -d / 2 + 0.08, h - 0.32), rot=(0.25, 0, 0))
    B.add("bezel", bm, M("gunmetal"))
    B.box("screen", (w - 0.2, 0.02, 0.4), (0, -d / 2 + 0.04, h - 0.32), M("screen_green" if opened else "screen_cyan"),
          rot=(0.25, 0, 0), outline=False)
    B.box("keys", (w - 0.12, 0.25, 0.04), (0, -d / 2 - 0.05, 0.85), M("gunmetal"), rot=(-0.3, 0, 0))
    if opened:
        B.box("hatch", (0.4, 0.03, 0.45), (-0.45, -d / 2 - 0.15, 0.35), M("steel"), rot=(0, 0, -0.9))
        B.box("guts", (0.4, 0.02, 0.4), (0, -d / 2 + 0.11, 0.35), M("rubber"))
        for k in range(3):
            B.box("chip%d" % k, (0.1, 0.02, 0.06), (-0.12 + k * 0.12, -d / 2 + 0.09, 0.3 + k * 0.05), M("led_green"), outline=False)
    else:
        B.box("hatch", (0.4, 0.03, 0.45), (0, -d / 2 + 0.11, 0.35), M("steel"))
        B.box("led", (0.05, 0.02, 0.05), (0.15, -d / 2 + 0.09, 0.55), M("led_amber"), outline=False)


def vent(B) -> None:
    w, d, h = 1.05, 0.5, 0.85
    B.box("duct", (w, d, h), (0, 0.15, h / 2), M("steel"), bevel=0.03)
    B.box("frame", (w - 0.08, 0.06, h - 0.12), (0, -d / 2 + 0.12, h / 2), M("gunmetal"))
    for k in range(6):
        B.box("slat%d" % k, (w - 0.2, 0.05, 0.05), (0, -d / 2 + 0.08, 0.15 + k * 0.11), M("steel_dark"), rot=(0.5, 0, 0))
    for x in (-w / 2 + 0.09, w / 2 - 0.09):
        for z in (0.1, h - 0.1):
            B.sphere("bolt%.1f%.1f" % (x, z), 0.025, (x, -d / 2 + 0.09, z), M("steel"))
    B.box("tag", (0.3, 0.02, 0.08), (0, -d / 2 + 0.08, h + 0.05), M("hazard", rim=0.0))


SPRITES = {
    "locker": (lambda B: locker(B, False), lambda B: locker(B, True), (60, 100), 0.9),
    "cargo_crate": (lambda B: cargo_crate(B, False), lambda B: cargo_crate(B, True), (80, 80), 0.4),
    "med_cabinet": (lambda B: med_cabinet(B, False), lambda B: med_cabinet(B, True), (80, 90), 0.8),
    "armory_chest": (lambda B: armory_chest(B, False), lambda B: armory_chest(B, True), (80, 80), 0.4),
    "cryo_pod": (lambda B: cryo_pod(B, False), lambda B: cryo_pod(B, True), (100, 80), 0.4),
    "terminal": (lambda B: terminal(B, False), lambda B: terminal(B, True), (70, 90), 0.7),
}
HIDES = {
    "locker": (lambda B: locker(B, False, double=True), (70, 100), 0.9),
    "vent": (vent, (70, 70), 0.4),
    "cryo": (lambda B: cryo_pod(B, False, standing=True), (60, 100), 0.9),
}


def main() -> None:
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    for k, (closed, opened, fr, tz) in SPRITES.items():
        if only and k not in only:
            continue
        render_sprite(k, closed, fr, PXW, os.path.join(OUT, k + ".png"), target_z=tz, outline_px=4.0, shadow=False, anchor_bottom=True)
        render_sprite(k + "_open", opened, fr, PXW, os.path.join(OUT, k + "_open.png"), target_z=tz, outline_px=4.0, shadow=False, anchor_bottom=True)
    for k, (fn, fr, tz) in HIDES.items():
        if only and ("hide_" + k) not in only and k not in only:
            continue
        render_sprite("hide_" + k, fn, fr, PXW, os.path.join(OUT, "hide_" + k + ".png"), target_z=tz, outline_px=4.0, shadow=False, anchor_bottom=True)


if __name__ == "__main__":
    main()
