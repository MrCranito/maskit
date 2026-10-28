"""Kit de bâtiments Far West (Blender, même caméra 3/4 que le héros) : modules assemblés en 2D
par le WorldBuilder selon l'emprise de chaque bâtiment.

Usage :  python3 art/blender/build_buildings.py   (puis build_props.py --pack pour l'atlas)

Modules (pièces de l'atlas `kit_*`) :
  kit_post        poteau de porche tourné avec corbeaux (pieds = base du poteau)
  kit_post_iron   poteau de fonte (banque)
  kit_banner_red  bannière rouge à emblème de masque blanc (pieds = point d'accroche, en haut)
  kit_banner_blue bannière bleu nuit à étoile dorée (shérif)
  kit_lantern     lanterne murale sur potence (pieds = fixation au mur)
  kit_chimney     cheminée de briques (pieds = base au toit)
  kit_belltower   clocher d'église avec cloche et croix
  kit_tank        citerne d'eau de toit (adobe)
  kit_barrels     groupe de tonneaux et sacs décoratifs (porche)
  kit_balcony     garde-corps de balcon (1 case, tuilable horizontalement)
  kit_stairs_up   escalier de bois montant ; kit_ladder échelle de mine ; kit_trapdoor trappe
Les murs, sols et toits (matières tuilables) sont générés par build_tiles.py.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_props as P  # noqa: E402
from build_props import M  # noqa: E402
import rdm_common as C  # noqa: E402


def k_post(B: P.Builder) -> None:
    h = 3.6
    B.box("plinth", (0.26, 0.26, 0.18), (0, 0, 0.09), M("wood_dark"), bevel=0.02)
    B.box("shaft", (0.18, 0.18, h - 0.3), (0, 0, 0.18 + (h - 0.3) / 2), M("wood_grey"), bevel=0.015)
    for z in (0.5, h - 0.35):
        B.box("ring%.1f" % z, (0.22, 0.22, 0.06), (0, 0, z), M("wood_dark"))
    B.box("cap", (0.3, 0.3, 0.1), (0, 0, h - 0.05), M("wood_dark"))
    for sx in (-1, 1):  # corbeaux (consoles en diagonale)
        B.box("brace%d" % sx, (0.42, 0.1, 0.1), (sx * 0.2, 0, h - 0.25), M("wood"), rot=(0, sx * 0.7, 0))


def k_post_iron(B: P.Builder) -> None:
    h = 3.6
    B.cyl("base", 0.16, 0.13, 0.25, (0, 0, 0.12), M("iron_dark"), seg=12)
    B.cyl("shaft", 0.07, 0.07, h - 0.4, (0, 0, 0.25 + (h - 0.4) / 2), M("iron"), seg=10)
    B.cyl("cap", 0.1, 0.18, 0.18, (0, 0, h - 0.1), M("iron_dark"), seg=12)
    for z in (0.7, 1.4):
        B.torus("r%.1f" % z, 0.08, 0.02, (0, 0, z), M("brass"), seg=12, rseg=4)


def _banner(B: P.Builder, cloth: str, emblem: str, star: bool) -> None:
    w, h = 0.75, 1.5
    B.cyl("rod", 0.03, 0.03, w + 0.3, (0, -0.05, 0), M("wood_dark"), rot=(0, math.pi / 2, 0), seg=6)
    for sx in (-(w + 0.3) / 2, (w + 0.3) / 2):
        P.C.bm_sphere  # noqa
        B.sphere("knob%.1f" % sx, 0.05, (sx, -0.05, 0), M("brass"), seg=6, rings=4)
    # toile légèrement ondulée, terminée en queue d'aronde
    cols = 7
    rows = 9
    import bmesh
    bm = bmesh.new()
    grid = []
    for j in range(rows):
        z = -0.05 - j * h / (rows - 1)
        row = []
        for i in range(cols):
            x = -w / 2 + i * w / (cols - 1)
            y = -0.06 - 0.05 * math.sin(i * 1.3 + j * 0.4) - 0.02 * j
            zz = z
            if j == rows - 1:
                zz += 0.28 * (1 - abs(i - (cols - 1) / 2) / ((cols - 1) / 2))  # entaille
            row.append(bm.verts.new((x, y, zz)))
        grid.append(row)
    for j in range(rows - 1):
        for i in range(cols - 1):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.y > 0:
            f.normal_flip()
    ob = B.add("cloth", bm, M(cloth), sharp=80)
    P.C.solidify(ob, 0.02)
    # liseré doré en bas et emblème (décalques)
    B.tube("trim", [(-w / 2, -0.07, -0.25), (w / 2, -0.07 - 0.03, -0.25)], [0.018, 0.018], M("gold"), seg=4, outline=False)
    if star:
        pts = []
        for k in range(10):
            a = math.pi / 2 + k * math.pi / 5
            r = 0.22 if k % 2 == 0 else 0.09
            pts.append((math.cos(a) * r, math.sin(a) * r - 0.75))
        _flat_poly(B, "emblem", pts, -0.14, M(emblem))
    else:
        # masque kitsune stylisé : ovale + oreilles pointues + yeux
        pts = []
        for k in range(16):
            a = 2 * math.pi * k / 16
            pts.append((math.cos(a) * 0.17, math.sin(a) * 0.22 - 0.8))
        _flat_poly(B, "emblem", pts, -0.14, M(emblem))
        for sx in (-1, 1):
            _flat_poly(B, "ear%d" % sx, [(sx * 0.07, -0.62), (sx * 0.2, -0.5), (sx * 0.17, -0.7)], -0.14, M(emblem))
            _flat_poly(B, "eye%d" % sx, [(sx * 0.03, -0.78), (sx * 0.11, -0.74), (sx * 0.1, -0.8)], -0.15, M("red"))


def _flat_poly(B: P.Builder, name, pts2, y, mat) -> None:
    import bmesh
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, z)) for (x, z) in pts2]
    bm.faces.new(vs)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.y > 0:
            f.normal_flip()
    B.add(name, bm, mat, shadow=False, outline=False)


def k_banner_red(B: P.Builder) -> None:
    _banner(B, "cloth_red", "ivory", False)


def k_banner_blue(B: P.Builder) -> None:
    _banner(B, "black", "gold", True)


def k_lantern(B: P.Builder) -> None:
    B.box("plate", (0.16, 0.05, 0.3), (0, 0.02, 0), M("iron_dark"))
    B.tube("arm", [(0, 0, 0.05), (0, -0.35, 0.08), (0, -0.42, 0.0)], [0.025, 0.025, 0.02], M("iron_dark"), seg=5)
    lx, ly, lz = 0, -0.42, -0.3
    B.cyl("roof", 0.02, 0.15, 0.13, (lx, ly, lz + 0.2), M("iron"), seg=8)
    B.cyl("glass", 0.1, 0.1, 0.26, (lx, ly, lz), M("glass"), seg=8)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        B.cyl("bar%d" % k, 0.014, 0.014, 0.28, (lx + math.cos(a) * 0.1, ly + math.sin(a) * 0.1, lz), M("iron"), seg=4)
    B.cyl("bottom", 0.12, 0.1, 0.05, (lx, ly, lz - 0.15), M("iron"), seg=8)
    B.sphere("flame", 0.045, (lx, ly, lz - 0.02), M("flame"), scale=(1, 1, 1.7), shadow=False, outline=False)


def k_chimney(B: P.Builder) -> None:
    w, h = 0.6, 1.2
    brick = M("wood_red")
    for j in range(7):
        z = j * h / 7
        off = 0.06 if j % 2 else 0.0
        B.box("course%d" % j, (w + off * 0.4, w + off * 0.4, h / 7 - 0.015), (0, 0, z + h / 14), brick)
    B.box("crown", (w + 0.14, w + 0.14, 0.12), (0, 0, h + 0.06), M("stone"))
    B.box("hole", (w - 0.18, w - 0.18, 0.02), (0, 0, h + 0.125), M("black"), outline=False)


def k_belltower(B: P.Builder) -> None:
    s = 1.3
    B.box("base", (s, s, 0.9), (0, 0, 0.45), M("cream"), bevel=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            B.box("pil%d%d" % (sx, sy), (0.22, 0.22, 1.0), (sx * (s / 2 - 0.11), sy * (s / 2 - 0.11), 1.4), M("cream"))
    B.box("arch", (s, s, 0.25), (0, 0, 2.0), M("cream"))
    B.cyl("bell", 0.12, 0.3, 0.42, (0, 0, 1.55), M("brass"), seg=14)
    B.sphere("clap", 0.06, (0, 0, 1.33), M("iron_dark"), seg=6, rings=4)
    B.cyl("roof", 0.02, s * 0.82, 0.9, (0, 0, 2.55), M("wood_red"), seg=4, rot=(0, 0, math.pi / 4))
    B.box("cv", (0.08, 0.08, 0.6), (0, 0, 3.25), M("gold"))
    B.box("ch", (0.34, 0.08, 0.08), (0, 0, 3.35), M("gold"))


def k_tank(B: P.Builder) -> None:
    R, H = 0.6, 0.9
    for k in range(14):
        a = 2 * math.pi * k / 14
        B.box("st%d" % k, (0.28, 0.07, H), (math.cos(a) * R, math.sin(a) * R, 0.25 + H / 2),
              M("wood" if k % 3 else "wood_grey"), rot=(0, 0, a + math.pi / 2))
    for z in (0.4, 0.95):
        B.torus("h%.1f" % z, R + 0.04, 0.025, (0, 0, z), M("iron"), seg=24, rseg=4)
    for sx in (-0.4, 0.4):
        B.box("leg%.1f" % sx, (0.1, 1.2, 0.25), (sx, 0, 0.12), M("wood_dark"))
    B.cyl("lid", R + 0.06, R + 0.06, 0.06, (0, 0, 0.25 + H), M("wood_dark"), seg=18)


def k_barrels(B: P.Builder) -> None:
    P.p_barrel(B, loc=(-0.25, 0.1, 0), name="b1")
    P.p_barrel(B, loc=(0.42, 0.25, 0), name="b2")
    for i, (x, y) in enumerate(((0.15, -0.35), (0.55, -0.3))):
        B.sphere("sack%d" % i, 0.28, (x, y, 0.22), M("cloth_cream"), scale=(1.1, 0.8, 0.85), seg=10, rings=7)
        B.sphere("tie%d" % i, 0.08, (x, y, 0.47), M("cloth_cream"), seg=6, rings=4)


def k_balcony(B: P.Builder) -> None:
    L = 1.78
    B.box("rail", (L, 0.12, 0.08), (0, 0, 0.95), M("wood_dark"))
    B.box("base", (L, 0.12, 0.08), (0, 0, 0.1), M("wood_dark"))
    for i in range(6):
        x = -L / 2 + (i + 0.5) * L / 6
        B.cyl("bal%d" % i, 0.035, 0.035, 0.82, (x, 0, 0.52), M("wood"), seg=6)


def k_stairs_up(B: P.Builder) -> None:
    n = 7
    for i in range(n):
        B.box("step%d" % i, (1.5, 0.26, 0.18), (0, 0.6 - i * 0.2 + 0.0, 0.09 + i * 0.18), M("plank_light" if i % 2 else "wood"))
        B.box("riser%d" % i, (1.5, 0.04, 0.18 * (i + 1)), (0, 0.6 - i * 0.2 - 0.13, 0.09 * (i + 1)), M("wood_dark"))
    for sx in (-0.8, 0.8):
        B.box("str%.1f" % sx, (0.1, 1.5, 0.3), (sx, 0, 0.7), M("wood_dark"), rot=(-0.7, 0, 0))
        B.box("np%.1f" % sx, (0.1, 0.1, 1.0), (sx, -0.65, 0.5), M("wood_dark"))
        B.tube("hr%.1f" % sx, [(sx, -0.65, 1.0), (sx, 0.75, 2.2)], [0.04, 0.04], M("wood"), seg=6)


def k_ladder(B: P.Builder) -> None:
    for sx in (-0.3, 0.3):
        B.box("rail%.1f" % sx, (0.08, 0.08, 2.4), (sx, 0.3, 0.6), M("plank_light"), rot=(0.35, 0, 0))
    for i in range(7):
        z = -0.4 + i * 0.32
        B.cyl("rung%d" % i, 0.03, 0.03, 0.6, (0, 0.3 + z * 0.36, z), M("wood"), rot=(0, math.pi / 2, 0), seg=6)


def k_trapdoor(B: P.Builder) -> None:
    B.box("frame", (1.6, 1.6, 0.1), (0, 0, 0.05), M("wood_dark"))
    B.box("hole", (1.3, 1.3, 0.02), (0, 0, 0.1), M("black"), outline=False)
    B.box("lid", (1.3, 0.1, 1.2), (0, 0.72, 0.65), M("wood"))
    for z in (0.3, 1.0):
        B.box("strap%.1f" % z, (1.32, 0.03, 0.08), (0, 0.66, z), M("iron"))


KIT = {
    "kit_post": (k_post, (60, 150), 1.8), "kit_post_iron": (k_post_iron, (50, 150), 1.8),
    "kit_banner_red": (k_banner_red, (60, 80), -0.75), "kit_banner_blue": (k_banner_blue, (60, 80), -0.75),
    "kit_lantern": (k_lantern, (40, 50), -0.15), "kit_chimney": (k_chimney, (60, 80), 0.6),
    "kit_belltower": (k_belltower, (90, 150), 1.7), "kit_tank": (k_tank, (80, 80), 0.6),
    "kit_barrels": (k_barrels, (80, 70), 0.5), "kit_balcony": (k_balcony, (72, 60), 0.5),
    "kit_stairs_up": (k_stairs_up, (80, 110), 0.9), "kit_ladder": (k_ladder, (50, 80), 0.3),
    "kit_trapdoor": (k_trapdoor, (70, 80), 0.4),
}
GLOW = {"kit_lantern": (0, -0.42, -0.3)}
NO_SHADOW = {"kit_banner_red", "kit_banner_blue", "kit_lantern", "kit_balcony", "kit_trapdoor", "kit_ladder"}


def main() -> None:
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
    for name, (fn, fr, tz) in KIT.items():
        if only and name not in only:
            continue
        P.render_piece(name, fn, fr, target_z=tz, glow=GLOW.get(name), shadow=name not in NO_SHADOW,
                       outline_px=4.5)


if __name__ == "__main__":
    main()
