"""Conteneurs fouillables et cachettes de la station sous-marine (3D toon, même caméra que le héros).

Usage (depuis la racine du projet) :
    python3 art/blender/underwater/uw_containers.py              # tout
    python3 art/blender/underwater/uw_containers.py --only uw_crate,hide_uw_pipes

Sorties : assets/sprites/underwater/containers/<kind>.png, <kind>_open.png, hide_<kind>.png
(contrat BiomeAssets / LootContainer / HidingSpot : sprite centré, pieds en bas au centre à
FOOT px du bord, affiché à l'échelle SCALE = 0,55 unité monde par px, comme les conteneurs Far West).
Cadres en puissances de 2 (128 x 128, 128 x 256, 256 x 128).
"""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..")))
import uw_props as P  # noqa: E402
import rdm_common as C  # noqa: E402
import build_props as BP  # noqa: E402
import bpy  # noqa: E402

M = P.M
Builder = P.Builder
OUT = os.path.join(P.ROOT, "assets", "sprites", "underwater", "containers")
SCALE = 0.55                      # unités monde par px (LootContainer / HidingSpot)
PX_PER_WORLD = 1.0 / SCALE
PX_PER_BU = PX_PER_WORLD * 36.0
FOOT = 4                          # px entre les pieds et le bas de l'image
SS = 2


# ----------------------------------------------------------------------------- modèles

def c_crate(B: Builder, open_: bool) -> None:
    w, d, h = 1.25, 0.8, 0.62
    B.box("body", (w, d, h), (0, 0, h / 2), M("uw_orange"), bevel=0.06)
    B.box("rib", (w + 0.03, d + 0.03, 0.08), (0, 0, h * 0.35), M("uw_steel_dark"))
    for sx in (-w / 2 + 0.25, w / 2 - 0.25):
        B.box("clamp%.1f" % sx, (0.14, 0.06, 0.22), (sx, -d / 2 - 0.02, h - 0.05), M("uw_steel_light"))
    B.box("plate", (0.4, 0.02, 0.16), (0, -d / 2 - 0.01, h * 0.62), M("uw_white"), outline=False)
    B.box("handle", (0.08, 0.3, 0.06), (w / 2 + 0.03, 0, h * 0.7), M("uw_rubber"))
    if open_:
        lid = C.bm_box(w, d, 0.16, bevel=0.05, segs=1)
        C.bm_xform(lid, loc=(0, d / 2 + 0.08, h + d / 2 - 0.02), rot=(math.radians(-80), 0, 0))
        B.add("lid", lid, M("uw_orange"))
        B.box("inside", (w - 0.12, d - 0.12, 0.05), (0, 0, h - 0.04), M("uw_rubber"), outline=False)
        B.cyl("tank", 0.1, 0.1, 0.5, (-0.25, -0.05, h), M("uw_yellow"), rot=(0, math.pi / 2, 0), seg=10)
        B.box("kit", (0.3, 0.2, 0.12), (0.3, 0.05, h + 0.02), M("uw_red"))
    else:
        B.box("lid", (w + 0.02, d + 0.02, 0.16), (0, 0, h + 0.06), M("uw_orange"), bevel=0.05)


def c_locker(B: Builder, open_: bool, hide: bool = False) -> None:
    w, d, h = 0.72, 0.55, 1.95
    B.box("body", (w, d, h), (0, 0.05, h / 2), M("uw_teal"), bevel=0.03)
    B.box("top", (w + 0.04, d + 0.04, 0.05), (0, 0.05, h), M("uw_steel_dark"))
    door_w = w - 0.08
    if open_:
        B.box("inside", (w - 0.08, 0.02, h - 0.12), (0, -d / 2 + 0.06, h / 2), M("uw_steel_dark"), outline=False)
        B.box("shelf", (w - 0.1, d - 0.12, 0.04), (0, 0.05, h * 0.72), M("uw_steel"))
        B.cyl("bottle", 0.09, 0.09, 0.42, (0.0, 0.0, h * 0.72 + 0.23), M("uw_yellow"), seg=10)
        B.box("bag", (0.4, 0.3, 0.32), (0.0, 0.0, 0.22), M("uw_red"), bevel=0.06)
        door = C.bm_box(door_w, 0.04, h - 0.1)
        C.bm_xform(door, loc=(-w / 2 - door_w / 2 * math.cos(1.2) + 0.02, -d / 2 + 0.05 - door_w / 2 * math.sin(1.2), h / 2),
                   rot=(0, 0, 1.2))
        B.add("door", door, M("uw_teal"))
    else:
        ajar = 0.25 if hide else 0.0
        door = C.bm_box(door_w, 0.04, h - 0.1)
        C.bm_xform(door, loc=(-w / 2 + door_w / 2 * math.cos(ajar) + 0.04, -d / 2 + 0.03 - door_w / 2 * math.sin(ajar), h / 2), rot=(0, 0, -ajar))
        B.add("door", door, M("uw_teal"))
        for k in range(4):
            B.box("vent%d" % k, (door_w * 0.6, 0.02, 0.025), (-0.0, -d / 2 - 0.0 - 0.05 * ajar * 2, h - 0.25 - k * 0.06), M("uw_steel_dark"), outline=False)
        B.box("latch", (0.04, 0.03, 0.16), (w / 2 - 0.12, -d / 2 - 0.01, h * 0.5), M("uw_steel_light"))
        B.box("num", (0.18, 0.02, 0.12), (0, -d / 2 - 0.01, h * 0.72), M("uw_white"), outline=False)
        if hide:
            B.box("dark", (0.05, 0.02, h - 0.2), (w / 2 - 0.06, -d / 2 + 0.03, h / 2), M("uw_hole"), outline=False)


def c_lab_cabinet(B: Builder, open_: bool) -> None:
    w, d, h = 1.15, 0.55, 1.8
    B.box("body", (w, d, h), (0, 0.05, h / 2), M("uw_white"), bevel=0.03)
    B.box("inner", (w - 0.12, 0.02, h - 0.55), (0, -d / 2 + 0.07, h / 2 + 0.2), M("uw_steel_dark"), outline=False)
    for k, z in enumerate((0.75, 1.15, 1.5)):
        B.box("shelf%d" % k, (w - 0.14, d - 0.15, 0.03), (0, 0.05, z), M("uw_steel_light"), outline=False)
        for j in range(4):
            col = ["uw_specimen", "uw_screen", "uw_grow", "uw_aqua"][(j + k) % 4]
            if open_ and j % 2:
                continue
            B.cyl("jar%d_%d" % (k, j), 0.07, 0.07, 0.2, (-0.38 + j * 0.25, 0.0, z + 0.12), M(col), seg=10)
    B.box("base", (w, 0.02, 0.4), (0, -d / 2 + 0.02, 0.25), M("uw_teal"))
    if open_:
        for sx in (-1, 1):
            door = C.bm_box(w / 2 - 0.04, 0.04, h - 0.6)
            ang = 1.1 * sx
            cx = sx * (w / 2) + -sx * (w / 4 - 0.02) * math.cos(ang)
            C.bm_xform(door, loc=(sx * (w / 2 + 0.1), -d / 2 - (w / 4) * math.sin(abs(ang)) + 0.02, h / 2 + 0.22), rot=(0, 0, ang))
            B.add("door%d" % sx, door, M("uw_aqua"))
    else:
        for sx in (-1, 1):
            B.box("glass%d" % sx, (w / 2 - 0.06, 0.03, h - 0.62), (sx * (w / 4), -d / 2 - 0.0, h / 2 + 0.22), M("uw_aqua"))
            B.box("frame%d" % sx, (0.04, 0.04, h - 0.6), (sx * 0.03, -d / 2 - 0.01, h / 2 + 0.22), M("uw_steel"))
    B.box("cross", (0.3, 0.02, 0.1), (0, -d / 2 - 0.0, 0.25), M("uw_red"), outline=False)


def c_sample_chest(B: Builder, open_: bool) -> None:
    w, d, h = 1.3, 0.85, 0.6
    B.box("body", (w, d, h), (0, 0, h / 2 + 0.06), M("uw_steel"), bevel=0.05)
    for sx in (-w / 2 + 0.12, w / 2 - 0.12):
        B.box("foot%.1f" % sx, (0.18, d - 0.1, 0.08), (sx, 0, 0.04), M("uw_steel_dark"))
        B.box("corner%.1f" % sx, (0.14, d + 0.04, h + 0.04), (sx, 0, h / 2 + 0.06), M("uw_yellow"))
    B.box("seal", (0.5, 0.03, 0.08), (0, -d / 2 - 0.01, h * 0.75), M("uw_screen"), outline=False)
    B.cyl("lock", 0.09, 0.09, 0.05, (0, -d / 2 - 0.02, h * 0.45), M("uw_red"), rot=(math.pi / 2, 0, 0), seg=12)
    if open_:
        lid = C.bm_box(w, d, 0.18, bevel=0.05, segs=1)
        C.bm_xform(lid, loc=(0, d / 2 + 0.1, h + 0.06 + d / 2 - 0.02), rot=(math.radians(-82), 0, 0))
        B.add("lid", lid, M("uw_steel"))
        B.box("foam", (w - 0.14, d - 0.14, 0.04), (0, 0, h + 0.03), M("uw_rubber"), outline=False)
        for j in range(5):
            B.cyl("vial%d" % j, 0.06, 0.06, 0.22, (-0.4 + j * 0.2, -0.05, h + 0.12), M(["uw_specimen", "uw_grow", "uw_screen"][j % 3]),
                  rot=(math.pi / 2, 0, 0), seg=10)
        B.sphere("pearl", 0.09, (0.35, 0.18, h + 0.12), M("uw_white"))
    else:
        B.box("lid", (w + 0.02, d + 0.02, 0.18), (0, 0, h + 0.1), M("uw_steel"), bevel=0.05)
        B.box("lidband", (w + 0.04, 0.12, 0.2), (0, 0, h + 0.1), M("uw_yellow"))


def c_diver_corpse(B: Builder, open_: bool) -> None:
    """Plongeur noyé allongé (casque de cuivre, combinaison), sac de plongée."""
    rot = 0.25
    import bmesh  # noqa: F401
    sub = Builder()
    # Le loft est construit le long de z puis couché le long de x.
    sub.add("torso", C.bm_xform(C.bm_loft([C.ellipse(0, 0, z, 0.26, 0.17, 12) for z in (-0.55, -0.2, 0.15, 0.38)]),
                                 loc=(0, 0, 0.2), rot=(0, math.pi / 2, 0)), M("uw_canvas"), sharp=80)
    sub.sphere("helmet", 0.27, (-0.75, 0.0, 0.28), M("uw_copper"), seg=16, rings=10)
    sub.cyl("plate", 0.13, 0.13, 0.05, (-0.85, -0.2, 0.3), M("uw_hole"), rot=(math.pi / 2, 0, -0.5), seg=14)
    sub.torus("ring", 0.14, 0.025, (-0.86, -0.22, 0.3), M("uw_yellow"), rot=(math.pi / 2, 0, -0.5), seg=14)
    for sy in (-0.12, 0.12):
        sub.tube("leg%.1f" % sy, [(0.35, sy, 0.18), (0.75, sy * 1.6, 0.14), (1.0, sy * 1.8, 0.12)], [0.11, 0.1, 0.1], M("uw_canvas"), seg=8)
        sub.box("boot%.1f" % sy, (0.25, 0.18, 0.18), (1.1, sy * 1.8, 0.1), M("uw_steel_dark"), bevel=0.04)
    sub.tube("armL", [(-0.4, -0.25, 0.22), (-0.1, -0.5, 0.12), (0.15, -0.55, 0.1)], [0.08, 0.08, 0.07], M("uw_canvas"), seg=8)
    sub.tube("armR", [(-0.4, 0.25, 0.22), (-0.2, 0.5, 0.12), (-0.45, 0.65, 0.1)], [0.08, 0.08, 0.07], M("uw_canvas"), seg=8)
    sub.sphere("gloveL", 0.08, (0.18, -0.56, 0.1), M("uw_rubber"))
    sub.sphere("gloveR", 0.08, (-0.48, 0.66, 0.1), M("uw_rubber"))
    sub.cyl("tank", 0.13, 0.13, 0.7, (-0.05, 0.3, 0.32), M("uw_yellow"), rot=(0, math.pi / 2, 0), seg=12)
    sub.tube("hose", C.bezier((-0.4, 0.3, 0.35), (-0.6, 0.35, 0.5), (-0.7, 0.2, 0.45), (-0.7, 0.1, 0.35), 6), [0.03] * 6, M("uw_rubber"), seg=5)
    if open_:
        sub.box("pouch", (0.3, 0.25, 0.1), (0.5, -0.5, 0.05), M("uw_red"), rot=(0, 0, 0.4))
        sub.sphere("pearl", 0.06, (0.75, -0.45, 0.06), M("uw_white"))
        sub.cyl("bolts", 0.03, 0.03, 0.4, (0.55, -0.75, 0.05), M("uw_steel_light"), rot=(0, math.pi / 2, 0.3), seg=6)
    else:
        sub.box("pouch", (0.25, 0.1, 0.2), (0.0, -0.25, 0.22), M("uw_red"))
    for ob in sub.objs:
        ob.rotation_euler = (0, 0, rot)
        B.objs.append(ob)
    for n in sub.noshadow:
        B.noshadow.add(n)


def c_tank(B: Builder, open_: bool) -> None:
    """Réservoir de stockage : cuve verticale à hublot (perles et coquillages au fond)."""
    r, h = 0.48, 1.25
    B.cyl("body", r, r, h, (0, 0, h / 2 + 0.12), M("uw_steel"), seg=22)
    B.sphere("dome", r, (0, 0, h + 0.12), M("uw_steel"), scale=(1, 1, 0.45), seg=22, rings=8)
    for z in (0.3, h - 0.05):
        B.torus("band%.1f" % z, r + 0.01, 0.03, (0, 0, z), M("uw_steel_dark"), seg=24, rseg=5)
    for k in range(3):
        a = math.pi / 2 + k * 2 * math.pi / 3
        B.box("leg%d" % k, (0.1, 0.1, 0.2), (math.cos(a) * r * 0.8, math.sin(a) * r * 0.8, 0.1), M("uw_steel_dark"))
    B.cyl("window", 0.2, 0.2, 0.06, (0, -r + 0.01, 0.7), M("uw_aqua"), rot=(math.pi / 2, 0, 0), seg=16)
    B.torus("wframe", 0.21, 0.03, (0, -r - 0.02, 0.7), M("uw_copper"), rot=(math.pi / 2, 0, 0), seg=16)
    B.box("label", (0.3, 0.02, 0.1), (0, -r - 0.0, 1.05), M("uw_yellow"), outline=False)
    B.cyl("valve", 0.04, 0.04, 0.3, (r, 0, 0.35), M("uw_steel_light"), rot=(0, math.pi / 2, 0), seg=6)
    B.torus("vwheel", 0.1, 0.02, (r + 0.15, 0, 0.35), M("uw_red"), rot=(0, math.pi / 2, 0), seg=12)
    if open_:
        B.cyl("hatchring", 0.22, 0.22, 0.06, (0, 0, h + 0.33), M("uw_steel_dark"), seg=16)
        B.cyl("hole", 0.17, 0.17, 0.07, (0, 0, h + 0.34), M("uw_hole"), seg=16, shadow=False)
        lid = C.bm_cyl(16, 0.22, 0.22, 0.05)
        C.bm_xform(lid, loc=(0, 0.25, h + 0.5), rot=(math.radians(-70), 0, 0))
        B.add("lid", lid, M("uw_steel"))
    else:
        B.cyl("hatch", 0.22, 0.22, 0.08, (0, 0, h + 0.33), M("uw_steel_dark"), seg=16)
        B.torus("hwheel", 0.13, 0.02, (0, 0, h + 0.39), M("uw_red"), seg=14)


def h_pipes(B: Builder) -> None:
    """Cachette : tuyauterie épaisse contre le mur, avec un recoin sombre derrière."""
    B.box("back", (1.7, 0.1, 1.9), (0, 0.45, 0.95), M("uw_steel_dark"))
    B.box("niche", (0.6, 0.05, 1.4), (0.0, 0.38, 0.72), M("uw_hole"), outline=False)
    for k, (x, r, mat) in enumerate(((-0.6, 0.2, "uw_copper"), (-0.3, 0.14, "uw_steel"), (0.38, 0.22, "uw_steel"), (0.68, 0.12, "uw_red"))):
        B.cyl("p%d" % k, r, r, 2.0, (x, 0.12, 1.0), M(mat), seg=14)
        for z in (0.35, 1.5):
            B.cyl("fl%d_%.1f" % (k, z), r + 0.05, r + 0.05, 0.08, (x, 0.12, z), M("uw_steel_dark"), seg=14)
    B.tube("bend", [(-0.6, 0.12, 1.75), (-0.6, -0.05, 1.95), (0.38, -0.05, 1.95), (0.38, 0.12, 1.75)], [0.13] * 4, M("uw_copper"), seg=12)
    B.torus("wheel", 0.17, 0.03, (0.38, -0.12, 1.1), M("uw_red"), rot=(math.pi / 2, 0, 0), seg=16)
    B.box("hz", (1.7, 0.03, 0.12), (0, 0.39, 0.06), M("uw_yellow"), outline=False)


def h_lab_table(B: Builder) -> None:
    """Cachette : grande paillasse recouverte d'une bâche qui tombe jusqu'au sol."""
    w, d, h = 1.8, 0.9, 0.95
    B.box("top", (w, d, 0.07), (0, 0, h), M("uw_white"), bevel=0.02)
    cloth = C.bm_loft([
        [(-w / 2 - 0.04, -d / 2 - 0.04, h + 0.02), (w / 2 + 0.04, -d / 2 - 0.04, h + 0.02)],
        [(-w / 2 - 0.02, -d / 2 - 0.1, h * 0.5), (w / 2 + 0.02, -d / 2 - 0.08, h * 0.5)],
        [(-w / 2 + 0.05, -d / 2 - 0.12, 0.02), (w / 2 - 0.02, -d / 2 - 0.14, 0.02)],
    ], cap_start=False, cap_end=False, closed=False)
    ob = B.add("cloth", cloth, M("uw_teal"), sharp=80)
    C.solidify(ob, 0.02)
    B.box("cloth_top", (w * 0.8, d * 0.9, 0.03), (0, 0, h + 0.05), M("uw_teal"))
    B.box("hem", (w * 0.4, 0.03, 0.3), (-0.35, -d / 2 - 0.14, 0.15), M("uw_hole"), outline=False)
    for j in range(3):
        B.cyl("flask%d" % j, 0.07, 0.04, 0.2, (0.3 + j * 0.2, 0.15, h + 0.15), M(["uw_specimen", "uw_screen", "uw_grow"][j]), seg=10)
    B.box("mic", (0.2, 0.25, 0.4), (-0.5, 0.15, h + 0.25), M("uw_steel_dark"))


# kind -> (fonction, cadre px (w, h), cible z (BU))
# kind -> (fonction, cadre px (w, h), cible z (BU), foot px : marge sous les pieds = profondeur
# de l'avant de l'objet ; la même valeur va dans scripts/biomes/underwater/container_defs.gd).
CONTAINERS = {
    "uw_crate": (c_crate, (128, 128), 0.5, 24),
    "uw_locker": (c_locker, (128, 256), 1.0, 22),
    "uw_lab_cabinet": (c_lab_cabinet, (128, 256), 0.9, 22),
    "uw_sample_chest": (c_sample_chest, (128, 128), 0.5, 26),
    "uw_diver_corpse": (c_diver_corpse, (256, 128), 0.2, 30),
    "uw_tank": (c_tank, (128, 256), 0.8, 26),
}
HIDES = {
    "uw_locker": (lambda B: c_locker(B, False, True), (128, 256), 1.0, 22),
    "uw_pipes": (h_pipes, (256, 256), 1.0, 18),
    "uw_lab_table": (h_lab_table, (256, 128), 0.5, 32),
}


def render_fixed(name: str, build_fn, size: tuple[int, int], target_z: float, foot: int = FOOT) -> None:
    """Rendu objet + ombre dans un cadre fixe, pieds (0,0,0) en (w/2, h - foot)."""
    from PIL import Image, ImageFilter
    C.reset_scene()
    w, h = size
    C.setup_render((w * SS, h * SS), samples=3, outline_px=3.6, inner_ratio=0.45)
    B = Builder()
    build_fn(B)
    cam = C.ortho_camera(P.BP.ELEV, max(w, h) / PX_PER_BU, target=(0, 0, target_z), dist=30.0)
    cd = cam.data
    for _ in range(2):
        bpy.context.view_layer.update()
        fx, fy = C.world_to_px(cam, (0, 0, 0))
        fx, fy = fx / SS, fy / SS
        cd.shift_x += (fx - w / 2) / max(w, h)
        cd.shift_y += ((h - foot) - fy) / max(w, h)
    big = os.path.join(P.PIECES, name + ".big.png")
    os.makedirs(P.PIECES, exist_ok=True)
    C.render_to(big)
    obj = C.downscale(big, None, (w, h))
    comp = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for ob in B.objs:
        ob.hide_render = True
    BP._shadow_objects(B)
    bpy.context.scene.render.use_freestyle = False
    C.render_to(big)
    sh = C.downscale(big, None, (w, h)).getchannel("A").filter(ImageFilter.GaussianBlur(1.4))
    layer = Image.new("RGBA", (w, h), BP.SHADOW_RGBA[:3] + (0,))
    layer.putalpha(sh.point(lambda a: a * BP.SHADOW_RGBA[3] // 255))
    comp = Image.alpha_composite(comp, layer)
    comp = Image.alpha_composite(comp, BP._paint(obj))
    os.remove(big)
    os.makedirs(OUT, exist_ok=True)
    comp.save(os.path.join(OUT, name + ".png"), optimize=True)
    bb = comp.getchannel("A").getbbox()
    print("SPRITE", name, size, "bbox", bb, flush=True)


def main() -> None:
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    for k, (fn, size, tz, foot) in CONTAINERS.items():
        for open_ in (False, True):
            name = k + ("_open" if open_ else "")
            if only and name not in only and k not in only:
                continue
            render_fixed(name, lambda B, f=fn, o=open_: f(B, o), size, tz, foot)
    for k, (fn, size, tz, foot) in HIDES.items():
        name = "hide_" + k
        if only and name not in only:
            continue
        render_fixed(name, fn, size, tz, foot)


if __name__ == "__main__":
    main()
