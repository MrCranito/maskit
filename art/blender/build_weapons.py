"""Armes tenues (sprites vus de côté, pointant vers la DROITE) : revolver, fusil, arc.

Usage (depuis la racine du projet) : python3 art/blender/build_weapons.py
Sorties : assets/sprites/weapons/<id>.png + <id>.json (grip, muzzle en px, scale).
Repère de modélisation : X = vers l'avant (canon), Z = haut, caméra orthographique de côté
(regarde +Y), légère plongée pour garder le volume.
"""
from __future__ import annotations

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "weapons")
TMP = os.environ.get("RDM_TMP", "/tmp/rdm_weapons")
SS = 4


def mats():
    return {
        "steel": C.toon("steel", "#9aa2b4", "#2c3050", "#e8eef8", rim=0.35),
        "dark": C.toon("darksteel", "#4a4e60", "#181a30", "#8a90a4", rim=0.3),
        "wood": C.toon("wood", "#8a4a26", "#3a1a20", "#c27a40", rim=0.25),
        "gold": C.toon("gold", "#d8a83c", "#6a3e2a", "#ffe490", rim=0.35),
        "red": C.toon("red", "#c0242c", "#4e0e26", "#e8423e"),
        "string": C.toon("string", "#e8dcc2", "#8a8aa6", "#fff6e0", rim=0.0),
        "leather": C.toon("leather", "#5a3a2a", "#1e1424", "#86583a"),
    }


def box(name, size, loc, mat, rot=(0, 0, 0), bevel=0.0):
    return C.mesh_obj(name, C.bm_xform(C.bm_box(*size, bevel=bevel), loc=loc, rot=rot), mat, smooth=False)


def cyl_x(name, r1, r2, length, loc, mat, seg=14):
    bm = C.bm_cyl(seg, r1, r2, length)
    C.bm_xform(bm, loc=loc, rot=(0, math.pi / 2, 0))
    return C.mesh_obj(name, bm, mat, smooth=True)


def build_revolver(m):
    # canon (octogonal), cylindre, carcasse, pontet, crosse en bois incurvée, chien
    cyl_x("barrel", 0.055, 0.055, 0.95, (0.70, 0, 0.20), m["steel"], seg=8)
    box("rib", (0.95, 0.04, 0.03), (0.70, 0, 0.265), m["dark"])
    box("sight", (0.05, 0.03, 0.05), (1.14, 0, 0.28), m["dark"])
    cyl_x("muzzle", 0.07, 0.07, 0.05, (1.17, 0, 0.20), m["gold"], seg=8)
    cyl_x("ejector", 0.025, 0.025, 0.55, (0.55, 0, 0.11), m["dark"], seg=8)
    cyl_x("cylinder", 0.15, 0.15, 0.30, (0.08, 0, 0.17), m["steel"], seg=6)
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        C.mesh_obj("flute", C.bm_xform(C.bm_cyl(8, 0.035, 0.035, 0.24), loc=(0.08, 0.13 * math.cos(a), 0.17 + 0.13 * math.sin(a)),
                                       rot=(0, math.pi / 2, 0)), m["dark"])
    box("frame", (0.48, 0.11, 0.34), (0.03, 0, 0.14), m["dark"], bevel=0.02)
    # gravure dorée sur la carcasse : volutes simplifiées (petits tubes)
    for sy in (-1, 1):
        pts = C.bezier((-0.15, 0.058 * sy, 0.05), (-0.05, 0.058 * sy, 0.16), (0.10, 0.058 * sy, 0.02), (0.20, 0.058 * sy, 0.10), 8)
        C.mesh_obj("engrave", C.bm_tube(pts, [0.016] * 8, seg=6), m["gold"], smooth=True)
    # pontet
    guard = C.bm_tube(C.bezier((0.10, 0, -0.02), (0.10, 0, -0.20), (-0.12, 0, -0.20), (-0.14, 0, -0.04), 9), [0.025] * 9, seg=6)
    C.mesh_obj("guard", guard, m["dark"])
    box("trigger", (0.03, 0.03, 0.12), (-0.02, 0, -0.07), m["dark"], rot=(0, 0.3, 0))
    # chien
    box("hammer", (0.10, 0.05, 0.14), (-0.22, 0, 0.32), m["dark"], rot=(0, -0.6, 0), bevel=0.01)
    # crosse en bois (bec de corbin)
    sections = []
    path = C.bezier((-0.18, 0, 0.10), (-0.30, 0, -0.05), (-0.42, 0, -0.25), (-0.40, 0, -0.50), 7)
    widths = [0.15, 0.15, 0.16, 0.17, 0.18, 0.19, 0.20]
    for (x, y, z), w in zip(path, widths):
        sections.append([(x - w * 0.55, -0.075, z), (x + w * 0.45, -0.075, z), (x + w * 0.45, 0.075, z), (x - w * 0.55, 0.075, z)])
    grip = C.bm_loft(sections)
    g = C.mesh_obj("grip", grip, m["wood"], smooth=False)
    C.subsurf(g, 1)
    cap = C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(-0.405, 0, -0.52), scale=(0.11, 0.08, 0.04))
    C.mesh_obj("buttcap", cap, m["gold"])
    # médaillon doré sur la crosse
    C.mesh_obj("medal", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(-0.34, -0.075, -0.22), scale=(0.04, 0.015, 0.04)), m["gold"])
    return {"grip": (-0.33, 0, -0.20), "muzzle": (1.20, 0, 0.20), "bounds": (-0.50, 1.24, -0.58, 0.36)}


def build_rifle(m):
    cyl_x("barrel", 0.045, 0.045, 1.6, (1.0, 0, 0.16), m["steel"], seg=8)
    cyl_x("tube", 0.038, 0.038, 1.2, (0.80, 0, 0.07), m["dark"], seg=8)
    cyl_x("muzzle", 0.06, 0.06, 0.05, (1.80, 0, 0.16), m["gold"], seg=8)
    box("sight", (0.04, 0.03, 0.05), (1.74, 0, 0.22), m["dark"])
    box("fore", (0.70, 0.12, 0.13), (0.55, 0, 0.08), m["wood"], bevel=0.03)
    box("receiver", (0.42, 0.12, 0.28), (0.0, 0, 0.12), m["gold"], bevel=0.02)
    box("hammer", (0.08, 0.05, 0.12), (-0.20, 0, 0.27), m["dark"], rot=(0, -0.6, 0))
    lever = C.bm_tube(C.bezier((0.05, 0, -0.02), (0.05, 0, -0.22), (-0.30, 0, -0.22), (-0.30, 0, -0.04), 9), [0.022] * 9, seg=6)
    C.mesh_obj("lever", lever, m["dark"])
    stock = C.bm_loft([
        [(-0.20, -0.065, 0.24), (-0.20, -0.065, -0.02), (-0.20, 0.065, -0.02), (-0.20, 0.065, 0.24)],
        [(-0.55, -0.07, 0.16), (-0.55, -0.07, -0.10), (-0.55, 0.07, -0.10), (-0.55, 0.07, 0.16)],
        [(-1.05, -0.08, 0.14), (-1.05, -0.08, -0.32), (-1.05, 0.08, -0.32), (-1.05, 0.08, 0.14)],
    ])
    C.mesh_obj("stock", stock, m["wood"], smooth=False)
    box("butt", (0.04, 0.17, 0.48), (-1.07, 0, -0.09), m["dark"])
    for sy in (-1, 1):
        pts = C.bezier((-0.15, 0.062 * sy, 0.05), (-0.05, 0.062 * sy, 0.20), (0.08, 0.062 * sy, 0.0), (0.16, 0.062 * sy, 0.15), 8)
        C.mesh_obj("engrave", C.bm_tube(pts, [0.014] * 8, seg=6), m["dark"])
    return {"grip": (-0.22, 0, -0.05), "muzzle": (1.82, 0, 0.16), "bounds": (-1.12, 1.88, -0.40, 0.32)}


def build_bow(m):
    # arc recourbé vu de côté : branches en bois, poignée cuir, bouts dorés, corde
    pts_up = C.bezier((0.0, 0, 0.0), (0.18, 0, 0.30), (0.05, 0, 0.75), (0.16, 0, 0.98), 10)
    pts_dn = [(x, y, -z) for (x, y, z) in pts_up]
    rr = [0.10 - 0.06 * (i / 9) for i in range(10)]
    C.mesh_obj("limbU", C.bm_tube(pts_up, rr, seg=8, flat=0.7), m["wood"])
    C.mesh_obj("limbD", C.bm_tube(pts_dn, rr, seg=8, flat=0.7), m["wood"])
    for z in (0.98, -0.98):
        C.mesh_obj("tip", C.bm_xform(C.bm_sphere(8, 6, 0.04), loc=(0.16, 0, z)), m["gold"])
    C.mesh_obj("grip", C.bm_xform(C.bm_cyl(10, 0.11, 0.11, 0.30), loc=(0.0, 0, 0)), m["leather"])
    C.mesh_obj("gripband", C.bm_xform(C.bm_cyl(10, 0.115, 0.115, 0.05), loc=(0.0, 0, 0.16)), m["red"])
    C.mesh_obj("gripband2", C.bm_xform(C.bm_cyl(10, 0.115, 0.115, 0.05), loc=(0.0, 0, -0.16)), m["red"])
    s = C.bm_tube([(0.16, 0, 0.98), (-0.18, 0, 0.0), (0.16, 0, -0.98)], [0.008, 0.008, 0.008], seg=5)
    C.mesh_obj("string", s, m["string"])
    # flèche encochée
    cyl_x("shaft", 0.022, 0.022, 0.95, (0.30, 0, 0.0), m["wood"], seg=6)
    head = C.bm_cyl(4, 0.08, 0.0, 0.18)
    C.bm_xform(head, loc=(0.84, 0, 0), rot=(0, math.pi / 2, 0), scale=(1, 0.4, 1))
    C.mesh_obj("arrowhead", head, m["steel"], smooth=False)
    for sz in (1, -1):
        f = C.bm_loft([[(-0.17, -0.005, 0.0), (-0.02, -0.005, 0.0), (-0.06, -0.005, 0.06 * sz), (-0.20, -0.005, 0.07 * sz)],
                       [(-0.17, 0.005, 0.0), (-0.02, 0.005, 0.0), (-0.06, 0.005, 0.06 * sz), (-0.20, 0.005, 0.07 * sz)]])
        C.mesh_obj("fletch", f, m["red"], smooth=False)
    return {"grip": (0.0, 0, 0.0), "muzzle": (0.92, 0, 0.0), "bounds": (-0.30, 1.00, -1.06, 1.06)}


WEAPONS = {
    # id : (constructeur, taille finale px, scale)
    "revolver": (build_revolver, (64, 32), 0.55),
    "rifle": (build_rifle, (96, 32), 0.55),
    "bow": (build_bow, (48, 80), 0.55),
}


def render_weapon(wid: str) -> None:
    fn, (W, H), scale = WEAPONS[wid]
    C.reset_scene()
    C.setup_render((W * SS, H * SS), samples=6, outline_px=1.6 * SS, inner_ratio=0.45)
    info = fn(mats())
    x0, x1, z0, z1 = info["bounds"]
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    # caméra de côté (regarde +Y), légère plongée de 12° pour garder du volume
    ortho = max(x1 - x0, (z1 - z0) * W / H) * 1.04
    cam = C.ortho_camera(12.0, ortho, target=(cx, 0, cz))
    cam.data.sensor_fit = "HORIZONTAL"  # ortho_scale = largeur, même en portrait
    os.makedirs(TMP, exist_ok=True)
    big = os.path.join(TMP, wid + "_big.png")
    C.render_to(big)
    os.makedirs(OUT, exist_ok=True)
    C.downscale(big, os.path.join(OUT, wid + ".png"), (W, H))
    g = C.world_to_px(cam, info["grip"])
    mz = C.world_to_px(cam, info["muzzle"])
    meta = {
        "grip": [round(g[0] / SS), round(g[1] / SS)],
        "muzzle": [round(mz[0] / SS), round(mz[1] / SS)],
        "scale": scale,
        "size": [W, H],
    }
    with open(os.path.join(OUT, wid + ".json"), "w") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    print("WEAPON", wid, meta)


def main() -> None:
    ids = sys.argv[1:] or list(WEAPONS)
    for wid in ids:
        render_weapon(wid)


if __name__ == "__main__":
    main()
