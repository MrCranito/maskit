"""Conteneurs fouillables (fermé + ouvert) et cachettes des Terres gelées (préfixe fl_).

Usage : python3 art/blender/frozen_lands/build_containers.py [--only fl_ammo_box,hide_fl_locker]

Sorties : assets/sprites/frozen_lands/containers/<kind>.png, <kind>_open.png, hide_<kind>.png
Même pipeline que la station (art/blender/space_station/ss_art.py : toon froid, contour, 48°) ;
échelle : LootContainer / HidingSpot affichent ces PNG à l'échelle 0,55 → rendu à 1/0,55 px par
unité monde ; point d'appui au centre horizontal, 4 px au-dessus du bord bas (« foot » = 4).
Palette : vert militaire délavé, acier givré, béton, rouge des barils, cyan des cuves cryo.
"""
from __future__ import annotations

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "space_station"))
from ss_art import C, M, ROOT, custom, hazard_band, render_sprite  # noqa: E402

OUT = os.path.join(ROOT, "assets", "sprites", "frozen_lands", "containers")
PXW = 1.0 / 0.55

# Matériaux propres au biome (toon, liseré froid).
def MM(key: str, rim: float = 0.22):
    extra = {
        "olive_drab": "#5f6a48", "olive_dark": "#3e4632", "frost": "#dbe8f4", "snow": "#eef4fa",
        "steel_frost": "#9aa8b8", "drum_red": "#b8302c", "drum_dark": "#6a1c1c", "cryo_body": "#c8d4e0",
        "canvas": "#8a8464", "wood_pale": "#9a8468", "skin_frost": "#b8c4d0", "uniform": "#4a5a52",
        "concrete": "#8c929c", "ice_blue": "#7fc2e8",
    }
    if key in extra:
        return custom("fl_" + key, extra[key], rim)
    return M(key, rim)


def _frost(B, name, w, d, z, k=1.0):
    """Givre : fine plaque blanche posée sur un dessus."""
    B.box(name, (w * k, d * k, 0.02), (0, 0, z + 0.01), MM("frost", rim=0.0), outline=False, shadow=False)


def supply_crate(B, opened: bool) -> None:
    w, d, h = 1.1, 0.8, 0.66
    B.box("body", (w, d, h), (0, 0, h / 2), MM("olive_drab"), bevel=0.03)
    for x in (-w / 2 + 0.07, w / 2 - 0.07):
        B.box("rib%.1f" % x, (0.09, d + 0.03, h + 0.02), (x, 0, h / 2), MM("olive_dark"))
    B.box("stencil", (0.34, 0.02, 0.16), (0.0, -d / 2 - 0.006, h * 0.5), MM("white_panel", rim=0.0), outline=False)
    B.box("star", (0.1, 0.02, 0.1), (0.0, -d / 2 - 0.014, h * 0.5), MM("olive_dark", rim=0.0), outline=False)
    if opened:
        B.box("cavity", (w - 0.16, d - 0.14, 0.03), (0, 0, h + 0.005), M("rubber"))
        B.box("lid", (w, 0.06, d), (0, d / 2 + 0.12, h + d / 2 - 0.1), MM("olive_drab"), rot=(-0.3, 0, 0))
        B.box("item1", (0.3, 0.22, 0.14), (-0.2, -0.05, h + 0.06), MM("canvas"))
        B.cyl("item2", 0.07, 0.07, 0.28, (0.22, 0.05, h + 0.05), MM("drum_red"), rot=(0, math.pi / 2, 0), seg=10)
    else:
        B.box("lid", (w + 0.02, d + 0.02, 0.06), (0, 0, h + 0.03), MM("olive_dark"))
        _frost(B, "frost", w, d, h + 0.06, 0.7)
        B.box("latch", (0.12, 0.04, 0.1), (0, -d / 2 - 0.02, h - 0.05), M("steel"))


def ammo_box(B, opened: bool) -> None:
    w, d, h = 0.9, 0.5, 0.5
    B.box("body", (w, d, h), (0, 0, h / 2), MM("olive_dark"), bevel=0.02)
    B.box("stripe", (w + 0.01, d + 0.01, 0.05), (0, 0, h * 0.72), M("hazard", rim=0.0), outline=False)
    B.box("stencil", (0.3, 0.02, 0.1), (0.0, -d / 2 - 0.006, h * 0.4), MM("white_panel", rim=0.0), outline=False)
    B.box("handle", (0.3, 0.04, 0.04), (0.0, 0.0, h + 0.03), M("steel_dark"))
    if opened:
        B.box("lid", (w, 0.05, d), (0, d / 2 + 0.02, h + d / 2 - 0.05), MM("olive_dark"), rot=(-0.2, 0, 0))
        B.box("inside", (w - 0.08, d - 0.08, 0.02), (0, 0, h), M("rubber"))
        rnd = random.Random(2)
        for k in range(8):
            B.cyl("round%d" % k, 0.035, 0.035, 0.2, (-0.3 + k * 0.085, rnd.uniform(-0.1, 0.1), h + 0.1), M("brass"), seg=8)
    else:
        B.box("lid", (w + 0.02, d + 0.02, 0.05), (0, 0, h + 0.02), MM("olive_dark"))
        _frost(B, "frost", w, d, h + 0.05, 0.6)


def fuel_drum(B, opened: bool) -> None:
    r, h = 0.3, 0.9
    B.cyl("body", r, r, h, (0, 0, h / 2), MM("drum_red"), seg=16)
    for z in (0.25, 0.65):
        B.torus("ring%.1f" % z, r + 0.005, 0.025, (0, 0, z), MM("drum_dark"), seg=18)
    B.box("label", (0.3, 0.02, 0.14), (0.0, -r - 0.005, h * 0.5), MM("white_panel", rim=0.0), outline=False)
    if opened:
        B.cyl("top", r - 0.03, r - 0.03, 0.02, (0, 0, h), M("rubber"), seg=16)
        B.cyl("lid", r, r, 0.04, (r * 0.8, -r * 0.6, 0.02), MM("drum_dark"), seg=16)
        B.cyl("can", 0.1, 0.1, 0.2, (0.0, 0.0, h + 0.08), MM("steel_frost"), seg=10)
    else:
        B.cyl("top", r, r, 0.04, (0, 0, h + 0.02), MM("drum_dark"), seg=16)
        B.cyl("cap", 0.06, 0.06, 0.04, (0.12, 0.08, h + 0.06), M("steel"), seg=8)
        B.cyl("snow", r * 0.85, r * 0.7, 0.04, (0, 0, h + 0.06), MM("snow", rim=0.0), seg=16, outline=False, shadow=False)


def footlocker(B, opened: bool) -> None:
    w, d, h = 0.95, 0.5, 0.45
    B.box("body", (w, d, h), (0, 0, h / 2), MM("uniform"), bevel=0.02)
    for x in (-w / 2 + 0.05, w / 2 - 0.05):
        B.box("rib%.1f" % x, (0.06, d + 0.02, h + 0.01), (x, 0, h / 2), M("steel_dark"))
    B.box("tag", (0.26, 0.02, 0.08), (0.0, -d / 2 - 0.006, h * 0.55), MM("white_panel", rim=0.0), outline=False)
    if opened:
        B.box("lid", (w, 0.05, d), (0, d / 2 + 0.03, h + d / 2 - 0.04), MM("uniform"), rot=(-0.15, 0, 0))
        B.box("inside", (w - 0.08, d - 0.08, 0.02), (0, 0, h), M("rubber"))
        B.box("cloth", (0.4, 0.3, 0.1), (-0.15, 0.0, h + 0.05), MM("canvas"), bevel=0.03)
        B.box("photo", (0.16, 0.12, 0.01), (0.25, -0.05, h + 0.01), MM("white_panel", rim=0.0), outline=False)
    else:
        B.box("lid", (w + 0.02, d + 0.02, 0.05), (0, 0, h + 0.02), M("steel_dark"))
        B.box("latch", (0.1, 0.04, 0.08), (0, -d / 2 - 0.02, h - 0.03), M("brass"))


def cryo_pod(B, opened: bool, standing: bool = False) -> None:
    if standing:
        w, d, h = 0.75, 0.6, 1.8
        B.box("base", (w + 0.1, d + 0.1, 0.12), (0, 0, 0.06), M("gunmetal"))
        B.box("body", (w, d, h - 0.2), (0, 0.05, h / 2), MM("cryo_body"), bevel=0.05)
        B.box("glass", (w - 0.2, 0.05, h - 0.7), (0, -d / 2 - 0.01, h / 2 + 0.05), M("glass_dark"), outline=False)
        B.box("led", (0.3, 0.02, 0.05), (0, -d / 2 - 0.02, 0.3), M("screen_cyan"), outline=False)
        B.box("top", (w + 0.06, d + 0.06, 0.1), (0, 0.05, h - 0.05), M("gunmetal"))
        for k in range(3):
            B.box("pipe%d" % k, (0.05, 0.05, h - 0.4), (w / 2 + 0.02, -0.15 + k * 0.15, h / 2), M("steel"))
        return
    w, d, h = 1.5, 0.75, 0.6
    B.box("base", (w, d, 0.15), (0, 0, 0.075), M("gunmetal"))
    B.box("body", (w - 0.1, d - 0.05, h - 0.15), (0, 0, 0.15 + (h - 0.15) / 2), MM("cryo_body"), bevel=0.06)
    B.box("panel", (0.4, 0.02, 0.22), (-w / 2 + 0.35, -d / 2 + 0.02, 0.38), M("screen_cyan"), outline=False)
    for k in range(3):
        B.cyl("pipe%d" % k, 0.035, 0.035, 0.5, (w / 2 - 0.08, -0.2 + k * 0.2, 0.3), M("steel"), seg=8)
    if opened:
        B.box("inside", (w - 0.3, d - 0.2, 0.02), (0, 0, h), MM("ice_blue"), outline=False)
        B.box("lid", (w - 0.2, 0.06, d - 0.1), (0, d / 2 + 0.2, h + 0.3), M("glass_dark"), rot=(-1.1, 0, 0))
        B.sphere("mist", 0.3, (0, 0, h + 0.1), MM("frost", rim=0.0), scale=(1.6, 1.0, 0.4), outline=False, shadow=False)
    else:
        B.box("lid", (w - 0.2, d - 0.1, 0.1), (0, 0, h + 0.05), M("glass_dark"), bevel=0.04)
        B.box("frame", (w - 0.18, 0.06, 0.12), (0, -d / 2 + 0.08, h + 0.06), M("steel"))
        _frost(B, "frost", w - 0.3, d - 0.2, h + 0.1, 0.8)


def sample_case(B, opened: bool) -> None:
    w, d, h = 0.8, 0.5, 0.3
    B.box("body", (w, d, h), (0, 0, h / 2), MM("steel_frost"), bevel=0.02)
    B.box("corner1", (0.08, d + 0.01, h + 0.01), (-w / 2 + 0.04, 0, h / 2), M("gunmetal"))
    B.box("corner2", (0.08, d + 0.01, h + 0.01), (w / 2 - 0.04, 0, h / 2), M("gunmetal"))
    B.box("hazard", (0.22, 0.02, 0.1), (0.0, -d / 2 - 0.006, h * 0.5), M("hazard", rim=0.0), outline=False)
    if opened:
        B.box("lid", (w, 0.04, d), (0, d / 2 + 0.02, h + d / 2 - 0.03), MM("steel_frost"), rot=(-0.3, 0, 0))
        B.box("foam", (w - 0.1, d - 0.1, 0.02), (0, 0, h), M("rubber"))
        for k in range(4):
            B.cyl("vial%d" % k, 0.04, 0.04, 0.2, (-0.25 + k * 0.17, 0.0, h + 0.1), M("liquid_cyan"), seg=8)
    else:
        B.box("lid", (w + 0.02, d + 0.02, 0.04), (0, 0, h + 0.02), M("gunmetal"))
        B.box("handle", (0.3, 0.04, 0.04), (0, 0, h + 0.06), M("steel_dark"))


def sled(B, opened: bool) -> None:
    w, d = 1.5, 0.7
    for y in (-d / 2 + 0.08, d / 2 - 0.08):
        B.box("rail%.1f" % y, (w, 0.06, 0.06), (0, y, 0.03), MM("wood_pale"))
        B.box("post%.1f" % y, (0.06, 0.06, 0.25), (-w / 2 + 0.3, y, 0.15), MM("wood_pale"))
        B.box("post2%.1f" % y, (0.06, 0.06, 0.25), (w / 2 - 0.3, y, 0.15), MM("wood_pale"))
    B.box("deck", (w - 0.2, d - 0.1, 0.05), (0, 0, 0.3), MM("wood_pale"))
    if opened:
        B.box("crate", (0.5, 0.45, 0.4), (-0.3, 0, 0.52), MM("olive_drab"), bevel=0.02)
        B.box("lidopen", (0.5, 0.04, 0.45), (-0.3, 0.26, 0.9), MM("olive_dark"), rot=(-0.4, 0, 0))
        B.cyl("drum", 0.16, 0.16, 0.45, (0.35, 0.05, 0.55), MM("drum_red"), seg=12)
        B.box("sack", (0.35, 0.3, 0.2), (0.3, -0.1, 0.9), MM("canvas"), bevel=0.05)
    else:
        B.box("tarp", (w - 0.3, d - 0.15, 0.55), (0, 0, 0.6), MM("canvas"), bevel=0.1)
        B.box("strap1", (0.05, d - 0.1, 0.57), (-0.35, 0, 0.6), M("rubber"))
        B.box("strap2", (0.05, d - 0.1, 0.57), (0.35, 0, 0.6), M("rubber"))
        _frost(B, "frost", w - 0.5, d - 0.3, 0.88, 0.8)


def frozen_corpse(B, opened: bool) -> None:
    """Soldat gelé assis contre rien, recroquevillé ; ouvert = sac à dos retourné."""
    B.box("legs", (0.7, 0.35, 0.22), (0.05, 0.05, 0.11), MM("uniform"), bevel=0.05)
    B.box("torso", (0.45, 0.4, 0.55), (-0.2, 0.0, 0.4), MM("uniform"), bevel=0.06)
    B.sphere("head", 0.17, (-0.22, -0.05, 0.78), MM("skin_frost"))
    B.box("hood", (0.38, 0.3, 0.26), (-0.22, 0.05, 0.84), MM("olive_dark"), bevel=0.06)
    B.box("arm", (0.5, 0.14, 0.14), (0.05, -0.2, 0.3), MM("uniform"), rot=(0, 0.3, 0), bevel=0.04)
    B.box("boot1", (0.18, 0.14, 0.12), (0.42, -0.05, 0.06), M("rubber"))
    B.box("boot2", (0.18, 0.14, 0.12), (0.42, 0.15, 0.06), M("rubber"))
    B.sphere("snow", 0.4, (-0.1, 0.1, 0.02), MM("snow", rim=0.0), scale=(1.5, 1.1, 0.12), outline=False, shadow=False)
    if opened:
        B.box("pack", (0.35, 0.25, 0.3), (0.2, 0.35, 0.15), MM("canvas"), bevel=0.05, rot=(0.6, 0, 0.3))
        B.box("tin", (0.12, 0.08, 0.05), (0.45, 0.3, 0.03), M("steel"))
    else:
        B.box("pack", (0.35, 0.25, 0.4), (-0.5, 0.05, 0.25), MM("canvas"), bevel=0.05)
        _frost(B, "frost", 0.4, 0.25, 0.9, 0.9)


def locker(B, double: bool = True) -> None:
    w, d, h = 0.95 if double else 0.6, 0.5, 1.75
    B.box("body", (w, d, h), (0, 0.05, h / 2), MM("steel_frost"), bevel=0.02)
    B.box("top", (w + 0.03, d + 0.03, 0.05), (0, 0.05, h), M("gunmetal"))
    n = 2 if double else 1
    dw = (w - 0.06) / n
    for i in range(n):
        x = -w / 2 + 0.03 + dw * (i + 0.5)
        B.box("door%d" % i, (dw - 0.03, 0.03, h - 0.1), (x, -d / 2 + 0.03, h / 2), MM("olive_drab"))
        for k in range(4):
            B.box("vent%d%d" % (i, k), (dw * 0.6, 0.02, 0.03), (x, -d / 2 + 0.01, h - 0.25 - k * 0.07), M("rubber"))
        B.box("handle%d" % i, (0.03, 0.03, 0.18), (x + dw * 0.32, -d / 2 + 0.0, h * 0.5), M("gunmetal"))
        B.box("tag%d" % i, (dw * 0.4, 0.015, 0.08), (x, -d / 2 + 0.01, h * 0.62), M("white_panel", rim=0.0), outline=False)
    _frost(B, "frost", w, d, h + 0.05, 0.8)


def snowdrift(B) -> None:
    """Congère : monticule de neige contre un pan de glace, assez gros pour s'y enfouir."""
    B.sphere("drift", 0.55, (0, 0.05, 0.1), MM("snow", rim=0.1), scale=(1.4, 1.0, 0.9), outline=True)
    B.sphere("drift2", 0.35, (0.5, -0.1, 0.05), MM("snow", rim=0.1), scale=(1.2, 1.0, 0.7))
    B.sphere("drift3", 0.3, (-0.55, 0.05, 0.05), MM("frost", rim=0.1), scale=(1.2, 1.0, 0.6))
    B.box("ice", (0.5, 0.2, 0.5), (0.1, 0.35, 0.4), MM("ice_blue"), rot=(0, 0, 0.3), bevel=0.05)
    B.box("ice2", (0.3, 0.2, 0.35), (-0.3, 0.3, 0.3), MM("ice_blue"), rot=(0, 0, -0.4), bevel=0.05)


SPRITES = {
    "fl_supply_crate": (lambda B: supply_crate(B, False), lambda B: supply_crate(B, True), (80, 80), 0.4),
    "fl_ammo_box": (lambda B: ammo_box(B, False), lambda B: ammo_box(B, True), (70, 70), 0.3),
    "fl_fuel_drum": (lambda B: fuel_drum(B, False), lambda B: fuel_drum(B, True), (60, 80), 0.5),
    "fl_footlocker": (lambda B: footlocker(B, False), lambda B: footlocker(B, True), (70, 70), 0.3),
    "fl_cryo_pod": (lambda B: cryo_pod(B, False), lambda B: cryo_pod(B, True), (100, 80), 0.4),
    "fl_sample_case": (lambda B: sample_case(B, False), lambda B: sample_case(B, True), (60, 60), 0.2),
    "fl_sled": (lambda B: sled(B, False), lambda B: sled(B, True), (100, 90), 0.5),
    "fl_frozen_corpse": (lambda B: frozen_corpse(B, False), lambda B: frozen_corpse(B, True), (80, 80), 0.4),
}
HIDES = {
    "fl_locker": (lambda B: locker(B, True), (70, 100), 0.9),
    "fl_cryo": (lambda B: cryo_pod(B, False, standing=True), (60, 100), 0.9),
    "fl_snowdrift": (snowdrift, (90, 70), 0.3),
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
