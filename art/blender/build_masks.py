"""Portraits de masques pour les menus (256x256, fond transparent, lueur d'aura).

Usage (depuis la racine du projet) : python3 art/blender/build_masks.py [id ...]
Sorties : assets/ui/masks/<id>.png pour kitsune, colosse, spectre, alchimiste, marionnettiste.
Chaque masque est modélisé simplement (face -Y), vu de face légèrement de 3/4, éclairage
toon dramatique, yeux émissifs ; une lueur d'aura floutée est composée derrière (PIL).
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "ui", "masks")
TMP = os.environ.get("RDM_TMP", "/tmp/rdm_masks")
SIZE = 256
SS = 2
ORTHO = {"colosse": 1.85, "spectre": 2.45, "marionnettiste": 2.45}


def face_shell(name, mat, w=0.42, h=0.50, depth=0.30, chin=0.75, chin_len=1.0, snout=0.25,
               brow_flat=0.18, faceted=False, seg=20, rings=16):
    """Coque de masque générique (ellipsoïde déformé, dos aplati), centrée en 0, face -Y."""
    bm = C.bm_sphere(seg, rings, 1.0)
    for v in bm.verts:
        x, y, z = v.co
        if z < 0.0:
            k = -z
            x *= 1.0 - chin * k ** 1.2
            z *= 1.0 + (chin_len - 1.0 + 0.5) * k ** 1.4
            y *= 1.0 - 0.4 * k
        else:
            x *= 1.0 - brow_flat * z ** 2
        if y < 0.0:
            ridge = math.exp(-(x * x) / 0.08)
            y -= snout * (-y) * ridge * (0.4 + 0.6 * max(0.0, -z))
        if y > 0.0:
            y *= 0.3
        v.co = Vector((x * w, y * depth, z * h))
    return C.mesh_obj(name, bm, mat, smooth=not faceted)


def eye_poly(cx, cz, w, h, tilt, sx, n=12):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x = math.cos(a) * w
        z = math.sin(a) * h * (1.0 if math.sin(a) > 0 else 0.7)
        pts.append((cx * sx + (x * math.cos(tilt) - z * math.sin(tilt)) * sx,
                    cz + x * math.sin(tilt) + z * math.cos(tilt)))
    if sx < 0:
        pts.reverse()
    return pts


def eyes(target, cx, cz, w, h, tilt, rim_mat, hole_mat, glow_mat):
    nofs = C.nofs_collection()
    for sx in (1, -1):
        if rim_mat is not None:
            C.decal(target, eye_poly(cx, cz, w * 1.25, h * 1.45, tilt, sx), rim_mat, "eyerim", lift=0.003, coll=nofs)
        C.decal(target, eye_poly(cx, cz, w, h, tilt, sx), hole_mat, "eyehole", lift=0.006, coll=nofs)
        C.decal(target, eye_poly(cx, cz, w * 0.72, h * 0.62, tilt, sx), glow_mat, "eyeglow", lift=0.009, coll=nofs)


def tube(name, pts, r0, r1, mat, flat=1.0, seg=8, up=(0, 1, 0)):
    n = len(pts)
    rr = [r0 + (r1 - r0) * (i / (n - 1)) for i in range(n)]
    return C.mesh_obj(name, C.bm_tube(pts, rr, seg=seg, flat=flat, up=up), mat)


# ----------------------------------------------------------------------------- masques

def mask_kitsune():
    white = C.toon("white", "#f4ede2", "#8a8cb4", "#fffaf2")
    red = C.toon("red", "#c8202a", "#5a1028", "#e8383a")
    hole = C.toon("hole", "#2a0c12", rim=0.0)
    glow = C.toon("glow", "#ff2a1c", emit=1.8)
    hood = C.toon("hood", "#a3202a", "#4a1030", "#d0383a")
    m = face_shell("mask", white, w=0.40, h=0.46, depth=0.32, chin=0.80, chin_len=1.25, snout=0.32)
    eyes(m, 0.17, 0.02, 0.12, 0.055, 0.42, red, hole, glow)
    nofs = C.nofs_collection()
    C.decal(m, [(0.0, 0.40), (0.05, 0.28), (0.0, 0.18), (-0.05, 0.28)], red, "brow", coll=nofs)
    C.decal(m, [(0.0, -0.40), (0.035, -0.46), (0.0, -0.58), (-0.035, -0.46)], red, "nose", coll=nofs)
    for sx in (1, -1):
        for k, (cz, ln) in enumerate(((-0.13, 0.15), (-0.21, 0.12))):
            x0, x1 = 0.12, 0.12 + ln
            pts = [(x0 * sx, cz + 0.02), (x1 * sx, cz + 0.08), (x1 * sx, cz + 0.045), (x0 * sx, cz - 0.015)]
            if sx < 0:
                pts.reverse()
            C.decal(m, pts, red, "cheek", coll=nofs, subdiv=2)
        # oreilles / cornes rouges
        tube("ear", C.bezier((0.18 * sx, 0.10, 0.35), (0.24 * sx, 0.08, 0.60), (0.30 * sx, 0.10, 0.80), (0.40 * sx, 0.16, 0.95), 8),
             0.11, 0.004, red, flat=0.45)
        tube("ear2", C.bezier((0.34 * sx, 0.14, 0.22), (0.46 * sx, 0.14, 0.34), (0.54 * sx, 0.16, 0.42), (0.62 * sx, 0.20, 0.48), 7),
             0.06, 0.003, red, flat=0.45)
    # capuche derrière (cadre rouge)
    hb = C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, 0.28, 0.05), scale=(0.52, 0.30, 0.58))
    C.mesh_obj("hood", hb, hood)
    return "#ff3a2a"


def mask_colosse():
    gold = C.toon("gold", "#d8a640", "#5a3a3a", "#ffe08a", rim=0.4)
    stone = C.toon("stone", "#6e655e", "#24223a", "#a89a88", rim=0.2)
    dark = C.toon("dark", "#1a1420", rim=0.0)
    glow = C.toon("glow", "#5ac8ff", emit=1.15)
    # casque : dôme d'or massif
    dome = C.bm_sphere(20, 14, 1.0)
    for v in dome.verts:
        x, y, z = v.co
        if z < -0.1:
            z = -0.1 + (z + 0.1) * 1.6
            x *= 0.92
        v.co = Vector((x * 0.50, y * 0.46, z * 0.52))
    C.mesh_obj("dome", dome, gold)
    # crête centrale
    crest = C.bm_xform(C.bm_box(0.08, 0.60, 0.20, bevel=0.03), loc=(0, 0.02, 0.50))
    C.mesh_obj("crest", crest, gold, smooth=False)
    # visière de pierre (plaque frontale) + fente en T
    plate = C.bm_xform(C.bm_box(0.78, 0.18, 0.62, bevel=0.06, segs=3), loc=(0, -0.36, -0.12))
    C.mesh_obj("plate", plate, stone, smooth=False)
    brow = C.bm_xform(C.bm_box(0.86, 0.22, 0.14, bevel=0.04), loc=(0, -0.40, 0.14))
    C.mesh_obj("brow", brow, gold, smooth=False)
    slit = C.bm_xform(C.bm_box(0.62, 0.05, 0.09), loc=(0, -0.455, 0.02))
    C.mesh_obj("slit", slit, dark, smooth=False)
    nose = C.bm_xform(C.bm_box(0.10, 0.05, 0.36), loc=(0, -0.455, -0.18))
    C.mesh_obj("noseslit", nose, dark, smooth=False)
    for sx in (1, -1):
        e = C.bm_xform(C.bm_box(0.19, 0.03, 0.075), loc=(0.17 * sx, -0.48, 0.02), rot=(0, -0.18 * sx, 0))
        C.mesh_obj("eye", e, glow, smooth=False)
        cheek = C.bm_xform(C.bm_box(0.18, 0.30, 0.50, bevel=0.04), loc=(0.44 * sx, -0.14, -0.22), rot=(0, 0, 0.25 * sx))
        C.mesh_obj("cheek", cheek, gold, smooth=False)
        rivet = C.bm_xform(C.bm_sphere(8, 6, 0.035), loc=(0.30 * sx, -0.475, 0.14))
        C.mesh_obj("rivet", rivet, stone)
    # gemme frontale
    gem = C.bm_xform(C.bm_sphere(6, 4, 1.0), loc=(0, -0.50, 0.15), scale=(0.06, 0.04, 0.08))
    C.mesh_obj("gem", gem, C.toon("gem", "#ffb030", emit=1.4), smooth=False)
    return "#ffb84a"


def mask_spectre():
    silver = C.toon("silver", "#c4cad8", "#2c3460", "#f4f8ff", rim=0.45, band=0.48)
    dark = C.toon("dark", "#0c1424", rim=0.0)
    glow = C.toon("glow", "#30e0ff", emit=1.5)
    m = face_shell("mask", silver, w=0.40, h=0.50, depth=0.30, chin=0.85, chin_len=1.30, snout=0.15,
                   faceted=True, seg=10, rings=8)
    # pointes anguleuses (couronne) et lames latérales
    for sx in (1, -1):
        for (bx, bz, tx, tz, r) in ((0.10, 0.38, 0.22, 0.95, 0.07), (0.26, 0.28, 0.55, 0.78, 0.06), (0.36, 0.05, 0.70, 0.30, 0.05)):
            tube("spike", [(bx * sx, 0.05, bz), ((bx + tx) / 2 * sx, 0.06, (bz + tz) / 2), (tx * sx, 0.08, tz)], r, 0.003, silver,
                 flat=0.35, seg=4)
    eyes(m, 0.16, 0.02, 0.12, 0.045, 0.50, None, dark, glow)
    # éclairs cyan
    for sx in (1, -1):
        pts = [(0.30 * sx, -0.10, 0.10), (0.48 * sx, -0.05, 0.20), (0.44 * sx, -0.05, 0.05), (0.66 * sx, 0.0, 0.18),
               (0.60 * sx, 0.0, 0.0), (0.80 * sx, 0.02, 0.08)]
        tube("bolt", pts, 0.020, 0.008, glow, seg=5)
        pts = [(0.22 * sx, -0.10, -0.40), (0.40 * sx, -0.04, -0.52), (0.34 * sx, -0.04, -0.62), (0.56 * sx, 0.0, -0.76)]
        tube("bolt2", pts, 0.018, 0.006, glow, seg=5)
    nofs = C.nofs_collection()
    C.decal(m, [(0.0, 0.42), (0.035, 0.20), (0.0, 0.10), (-0.035, 0.20)], glow, "brow", coll=nofs)
    return "#3ae8ff"


def mask_alchimiste():
    fire = C.toon("fire", "#e8641c", "#7a1a20", "#ffb040", rim=0.45)
    deep = C.toon("deep", "#9a1c1c", "#3a0a1c", "#d8401c")
    dark = C.toon("dark", "#2a0a08", rim=0.0)
    glow = C.toon("glow", "#ffd040", emit=1.4)
    flame_glow = C.toon("flameglow", "#ff8a20", emit=1.6)
    m = face_shell("mask", fire, w=0.40, h=0.46, depth=0.30, chin=0.70, chin_len=1.15, snout=0.10)
    eyes(m, 0.16, 0.03, 0.13, 0.055, 0.35, None, dark, glow)
    nofs = C.nofs_collection()
    # motif de flammes rouges sur le masque
    C.decal(m, [(0.0, 0.42), (0.08, 0.26), (0.04, 0.30), (0.0, 0.16), (-0.04, 0.30), (-0.08, 0.26)], deep, "brow", coll=nofs)
    for sx in (1, -1):
        C.decal(m, [(0.10 * sx, -0.14), (0.26 * sx, -0.10), (0.20 * sx, -0.20), (0.30 * sx, -0.26), (0.12 * sx, -0.28)][::sx],
                deep, "cheek", coll=nofs)
    # langues de feu autour (cornes de flamme)
    flames = [(0.0, 0.40, 0.0, 1.05, 0.11), (0.14, 0.36, 0.26, 0.92, 0.09), (0.28, 0.26, 0.50, 0.78, 0.08),
              (0.38, 0.06, 0.66, 0.36, 0.07), (0.40, -0.18, 0.62, -0.02, 0.06)]
    for (bx, bz, tx, tz, r) in flames:
        for sx in ((1,) if bx == 0 else (1, -1)):
            mx, mz = (bx + tx) / 2, (bz + tz) / 2
            pts = C.bezier((bx * sx, 0.08, bz), ((mx - 0.06) * sx, 0.10, mz), ((mx + 0.10) * sx, 0.12, mz + 0.12), (tx * sx, 0.14, tz), 7)
            tube("flame", pts, r, 0.004, flame_glow if r > 0.08 else fire, flat=0.4)
    return "#ff7a1a"


def mask_marionnettiste():
    bone = C.toon("bone", "#ece2cc", "#5a4a7a", "#fff8ea", rim=0.35)
    crack = C.toon("crack", "#6a5a5a", rim=0.0)
    dark = C.toon("dark", "#1a0a24", rim=0.0)
    glow = C.toon("glow", "#b860ff", emit=1.5)
    string = C.toon("string", "#c8b8a0", "#5a4a7a", "#f0e4d0", rim=0.0)
    wood = C.toon("wood", "#7a5a3a", "#2a1a2a", "#a8804c")
    m = face_shell("mask", bone, w=0.36, h=0.50, depth=0.30, chin=0.85, chin_len=1.45, snout=0.20)
    eyes(m, 0.15, 0.04, 0.11, 0.050, 0.28, None, dark, glow)
    nofs = C.nofs_collection()
    # fissures et marques
    C.decal(m, [(0.0, 0.45), (0.02, 0.30), (0.0, 0.18), (-0.02, 0.30)], crack, "brow", coll=nofs)
    for sx in (1, -1):
        C.decal(m, [(0.14 * sx, -0.08), (0.17 * sx, -0.08), (0.15 * sx, -0.40), (0.12 * sx, -0.40)][::sx], crack, "tear", coll=nofs)
    C.decal(m, [(-0.08, -0.48), (0.08, -0.48), (0.08, -0.51), (-0.08, -0.51)], crack, "mouth", coll=nofs)
    # croix de manipulation en bois au-dessus + fils jusqu'au masque
    bar = C.bm_xform(C.bm_box(0.90, 0.06, 0.06, bevel=0.015), loc=(0, 0.05, 0.98))
    C.mesh_obj("bar", bar, wood, smooth=False)
    bar2 = C.bm_xform(C.bm_box(0.06, 0.40, 0.06, bevel=0.015), loc=(0, 0.05, 0.98))
    C.mesh_obj("bar2", bar2, wood, smooth=False)
    for (tx, tz, ex, ez) in ((0.42, 0.98, 0.34, 0.10), (-0.42, 0.98, -0.34, 0.10), (0.16, 0.98, 0.10, 0.44),
                             (-0.16, 0.98, -0.10, 0.44), (0.42, 0.98, 0.44, -0.80), (-0.42, 0.98, -0.44, -0.80)):
        C.mesh_obj("string", C.bm_tube([(tx, 0.0, tz), ((tx + ex) / 2, -0.05, (tz + ez) / 2), (ex, -0.05, ez)],
                                       [0.008, 0.008, 0.008], seg=4), string)
    # anneaux latéraux (oreilles) et lueur violette
    for sx in (1, -1):
        ring = C.bm_xform(C.bm_torus(14, 6, 0.08, 0.018), loc=(0.40 * sx, 0.02, 0.10), rot=(math.pi / 2, 0, 0))
        C.mesh_obj("ring", ring, wood)
    return "#a050ff"


MASKS = {
    "kitsune": mask_kitsune,
    "colosse": mask_colosse,
    "spectre": mask_spectre,
    "alchimiste": mask_alchimiste,
    "marionnettiste": mask_marionnettiste,
}


def compose_glow(src: str, dst: str, aura_hex: str) -> None:
    from PIL import Image, ImageChops, ImageFilter
    im = C.downscale(src, None, (SIZE, SIZE))
    a = im.getchannel("A")
    halo = a.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(14))
    halo = halo.point(lambda v: int(min(255, v * 0.85)))
    r, g, b = (int(aura_hex[i:i + 2], 16) for i in (1, 3, 5))
    glow = Image.new("RGBA", im.size, (r, g, b, 0))
    glow.putalpha(halo)
    out = Image.alpha_composite(glow, im)
    out.save(dst, optimize=True)
    del ImageChops


def render_mask(mid: str) -> None:
    C.reset_scene()
    C.setup_render(SIZE * SS, samples=8, outline_px=2.6 * SS, inner_ratio=0.5)
    aura = MASKS[mid]()
    # légère rotation 3/4 + plongée faible
    for ob in bpy.data.objects:
        if ob.parent is None and ob.type == "MESH":
            ob.rotation_euler.z += math.radians(-14)
    C.ortho_camera(10.0, ORTHO.get(mid, 2.25), target=(0, 0, 0.10))
    os.makedirs(TMP, exist_ok=True)
    big = os.path.join(TMP, mid + "_big.png")
    C.render_to(big)
    os.makedirs(OUT, exist_ok=True)
    compose_glow(big, os.path.join(OUT, mid + ".png"), aura)
    print("MASK", mid)


def main() -> None:
    for mid in sys.argv[1:] or list(MASKS):
        render_mask(mid)


if __name__ == "__main__":
    main()
