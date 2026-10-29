"""Fond du menu principal de RaidersGo : « camp de base » militaire à la lisière de la ville
fantôme de Dust Creek, au coucher du soleil (rendu Cycles réaliste, mêmes matériaux et mêmes
constructeurs que la carte pré-rendue : tools/prerender/fw_scene.py).

Usage (depuis la racine du projet) :
    python3 art/blender/build_menu.py                 # rendu final (2048 x 1024)
    python3 art/blender/build_menu.py --quick         # aperçu rapide (512 x 256, peu d'échantillons)
    python3 art/blender/build_menu.py --only back,camp,front,flag,mist

Sorties (assets/ui/menu/lobby/) :
    back.jpg     ciel peint + ville + désert + sol (opaque)           -> couche lointaine
    camp.png     camp (camion, tente, table d'armes, caisses, feu…)  -> couche du milieu (rognée)
    front.png    premier plan (sacs de sable, caisses)               -> couche proche (rognée)
    flag_0..5    drapeau rouge à l'emblème blanc qui flotte (6 images, planche flag.png)
    lobby.json   positions (px de l'image 2048 x 1024) : couches rognées, héros (pieds, hauteur
                 d'une unité), feu, fumée, drapeau ; lu par scripts/ui/menus/lobby_scene.gd.
Le héros n'est pas dans ce rendu : il est rendu à part pour chaque skin (build_menu_hero.py)
et posé par le jeu à l'emplacement « hero » du JSON.

Repère : celui de fw_scene (1 unité = 1 case de 64 px ; X = colonne, Y = -rangée, Z = hauteur).
La caméra (perspective) est au sud, regarde vers le nord : la ville est au fond.
"""
from __future__ import annotations

import json
import math
import os
import random
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "ui", "menu", "lobby")
ARGS = sys.argv[1:]
QUICK = "--quick" in ARGS
# « flag » (ancienne animation à 6 images) n'est plus rendu par défaut : le drapeau est une
# texture plate (build_menu_2d.py fx) ondulée par un shader dans le jeu.
ONLY = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else ["back", "camp", "front", "mist"]
TMP = os.environ.get("RDM_TMP", os.path.join(tempfile.gettempdir(), "rdm_menu"))
os.makedirs(TMP, exist_ok=True)
os.makedirs(OUT, exist_ok=True)

MID = "--mid" in ARGS
IMG_W, IMG_H = (512, 256) if QUICK else ((1024, 512) if MID else (2048, 1024))
SAMPLES = 6 if QUICK else (16 if MID else 28)
QUICK = QUICK or MID

# ----------------------------------------------------------------------------- ville (layout)
GW, GH = 52, 34
CAM_X, CAM_ROW, CAM_Z = 25.5, 49.0, 0.70
LENS = 30.0
PITCH = -3.0            # degrés (négatif = vers le bas)
HERO_DEPTH = 2.9       # distance caméra -> pieds du héros (unités)
HERO_SCREEN_X = 0.405   # position horizontale voulue du héros (fraction de l'image)

TOWN = [  # (id, arch, x, y, w, h, stories, roof)
    (1, "store", 6, 12, 5, 6, 1, "tin_grey"),
    (2, "saloon", 12, 11, 7, 7, 2, "red"),
    (3, "bank", 20, 12, 4, 6, 1, "tin_blue"),
    (4, "hotel", 26, 11, 6, 7, 2, "tin_blue"),
    (5, "sheriff", 33, 12, 5, 6, 1, "plank"),
    (6, "store", 39, 12, 5, 6, 1, "tin_rust"),
    (7, "house", 45, 13, 4, 5, 1, "shingle"),
    (8, "house", 1, 13, 4, 5, 1, "tin_grey"),
    (9, "stable", 15, 2, 7, 6, 1, "plank"),
    (10, "house", 30, 3, 5, 5, 1, "tin_grey"),
]


def make_layout() -> dict:
    tiles = [["1"] * GW for _ in range(GH)]
    buildings = []
    for (bid, arch, x, y, w, h, st, roof) in TOWN:
        doors = []
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                edge = xx in (x, x + w - 1) or yy in (y, y + h - 1)
                tiles[yy][xx] = "3" if edge else "2"
        dx = x + w // 2
        tiles[y + h - 1][dx] = "4"
        doors.append({"cell": [dx, y + h - 1], "outside": True})
        buildings.append({"id": bid, "arch": arch, "rect": [x, y, w, h], "stories": st, "roof_style": roof,
                          "porch_side": "S", "doors": doors})
    props = []
    rng = random.Random(4)
    for (bid, arch, x, y, w, h, st, roof) in TOWN[:8]:
        for k in range(2):
            props.append({"cell": [x + rng.randint(0, w - 1), y + h + 1], "kind": rng.choice(["barrel", "crate_stack", "sacks", "hitching_post"])})
    props += [{"cell": [10, 21], "kind": "covered_wagon", "rot": 0.25}, {"cell": [36, 21], "kind": "water_trough"},
              {"cell": [30, 20], "kind": "lantern"}, {"cell": [19, 20], "kind": "lantern"}]
    return {
        "size": [GW, GH], "seed": 7, "tiles": ["".join(r) for r in tiles], "buildings": buildings,
        "landmarks": [{"kind": "water_tower", "rect": [24, 4, 4, 4]}, {"kind": "windmill", "rect": [41, 4, 3, 3]}],
        "train": [], "rails": [], "props": props, "fences": [[[2, 20], [5, 20]], [[46, 19], [50, 19]]],
        "rock_formations": [
            {"cells": [[x, y] for x in range(-6, -1) for y in range(8, 14)], "height": 3.2},
            {"cells": [[x, y] for x in range(52, 57) for y in range(6, 12)], "height": 3.8},
        ],
        "paths": [[x, y] for x in range(-4, GW + 4) for y in range(19, 23)],
    }


LAYOUT_PATH = os.path.join(TMP, "menu_layout.json")
with open(LAYOUT_PATH, "w") as _f:
    json.dump(make_layout(), _f)
sys.argv = ["fw_scene.py", LAYOUT_PATH, TMP, "24", str(SAMPLES), "full", "4"]
sys.path.insert(0, os.path.join(ROOT, "tools", "prerender"))
os.environ.setdefault("FW_EXPOSURE", "0.75")
import fw_scene as fw  # noqa: E402  (construit la scène vide à l'import)
import bpy  # noqa: E402
from mathutils import Vector, Euler  # noqa: E402

MB = fw.MB
NT = fw.NT
Y = fw.Y


def cam_row(depth: float) -> float:
    return CAM_ROW - depth


def W(x: float, depth: float) -> tuple[float, float]:
    """Position monde (x Blender, y Blender) d'un point à `depth` unités devant la caméra."""
    return x, Y(cam_row(depth))


# ----------------------------------------------------------------------------- matériaux en plus
def extra_materials() -> None:
    fw.mat_simple("olive", (0.085, 0.09, 0.045), 0.62, var=0.35, scale=5.0, c2=(0.05, 0.05, 0.03), bump=0.25)
    fw.mat_simple("olive_light", (0.15, 0.15, 0.08), 0.7, var=0.3, scale=6.0)
    fw.mat_simple("khaki", (0.30, 0.25, 0.15), 0.9, var=0.35, scale=6.0, c2=(0.20, 0.16, 0.09), bump=0.35)
    fw.mat_simple("khaki_dark", (0.16, 0.13, 0.08), 0.9, var=0.3, scale=6.0)
    fw.mat_simple("rubber", (0.025, 0.025, 0.028), 0.8, var=0.2, scale=12.0)
    fw.mat_simple("gunmetal", (0.03, 0.032, 0.036), 0.42, metal=0.6, var=0.25, scale=9.0)
    fw.mat_simple("polymer", (0.045, 0.042, 0.04), 0.6, var=0.2)
    fw.mat_simple("sandbag", (0.36, 0.30, 0.19), 0.95, var=0.45, scale=14.0, c2=(0.25, 0.20, 0.12), bump=0.6)
    fw.mat_simple("yellow_stencil", (0.55, 0.42, 0.06), 0.7, var=0.2)
    fw.mat_simple("ember", (0.3, 0.08, 0.02), 0.8, emit=((1.0, 0.32, 0.06), 6.0))
    fw.mat_simple("bulb", (0.9, 0.7, 0.4), 0.4, emit=((1.0, 0.72, 0.38), 9.0))
    fw.mat_simple("lamp", (0.9, 0.6, 0.3), 0.4, emit=((1.0, 0.6, 0.25), 5.0))
    fw.mat_simple("tent_inside", (0.03, 0.025, 0.02), 0.95, var=0.2)
    fw.mat_simple("cable", (0.02, 0.02, 0.02), 0.6, var=0.1)
    fw.mat_simple("headlight", (0.5, 0.5, 0.45), 0.2, metal=0.5, var=0.1)
    # filet de camouflage : taches vert/brun/sable, trous (alpha)
    s = NT("camo_net")
    o = s.obj()
    n = s.noise(o, 3.0, 4, 0.6)
    col = s.ramp(n, [(0.35, (0.06, 0.07, 0.035)), (0.5, (0.16, 0.14, 0.07)), (0.62, (0.28, 0.22, 0.12))])
    holes = s.voronoi(o, 22.0, "Distance")
    s.done(col, 0.95, s.bump(n, 0.8, 0.05))
    s.l(s.smooth(holes, 0.12, 0.22), s.b.inputs["Alpha"])
    # drapeau : rouge, emblème blanc (texture générée)
    emb = os.path.join(TMP, "flag_emblem.png")
    make_emblem_png(emb)
    s = NT("flag_cloth")
    img = bpy.data.images.load(emb)
    tx = s.n("ShaderNodeTexImage")
    tx.image = img
    tx.extension = "CLIP"
    s.l(s.uv(), tx.inputs[0])
    n = s.noise(s.obj(), 18.0, 4)
    red = s.mix(s.mul(n, 0.4), (0.42, 0.025, 0.03), (0.30, 0.015, 0.02))
    col = s.mix(tx.outputs["Alpha"], red, (0.80, 0.76, 0.70))
    s.done(col, 0.8, s.bump(n, 0.15, 0.02))
    s.m.use_backface_culling = False


def make_emblem_png(path: str) -> None:
    """Emblème de RaidersGo (viseur ouvert + flèche de sortie) en blanc, sur fond transparent ;
    proportions de scripts/ui/menus/raiders_emblem.gd. Image 512 x 320 (rapport du drapeau)."""
    from PIL import Image, ImageDraw
    w, h = 1024, 640
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    s = 420.0
    cx, cy = w * 0.5, h * 0.5
    r = s * 0.36
    lw = int(s * 0.075)
    a0 = math.degrees(-math.pi * 0.08)
    a1 = math.degrees(-math.pi * 0.42 + math.tau)
    d.arc([cx - r, cy - r, cx + r, cy + r], a0, a1, fill=(255, 255, 255, 255), width=lw)
    for ang in (math.pi, math.pi * 0.5, -math.pi * 0.5):
        dx, dy = math.cos(ang), math.sin(ang)
        d.line([(cx + dx * (r - s * 0.16), cy + dy * (r - s * 0.16)), (cx + dx * (r + s * 0.12), cy + dy * (r + s * 0.12))],
               fill=(255, 255, 255, 255), width=int(lw * 0.75))
    d.ellipse([cx - s * 0.035, cy - s * 0.035, cx + s * 0.035, cy + s * 0.035], fill=(255, 255, 255, 255))
    dirv = (math.cos(-math.pi * 0.25), math.sin(-math.pi * 0.25))
    nrm = (-dirv[1], dirv[0])
    st = (cx + dirv[0] * s * 0.02, cy + dirv[1] * s * 0.02)
    en = (cx + dirv[0] * s * 0.5, cy + dirv[1] * s * 0.5)
    head = s * 0.2
    se = (en[0] - dirv[0] * head * 0.6, en[1] - dirv[1] * head * 0.6)
    aw = s * 0.085
    P = lambda p, k, m=0.0: (p[0] + nrm[0] * k - dirv[0] * m, p[1] + nrm[1] * k - dirv[1] * m)
    d.polygon([P(st, aw / 2), P(se, aw / 2), P(se, -aw / 2), P(st, -aw / 2)], fill=(255, 255, 255, 255))
    d.polygon([en, P(se, head * 0.62, head * 0.15), P(se, -head * 0.62, head * 0.15)], fill=(255, 255, 255, 255))
    im.save(path)


# ----------------------------------------------------------------------------- sol, désert, mesas
def build_ground_menu() -> None:
    """Grand plan de sable (matériau « ground » de la carte) jusqu'à l'horizon + masque :
    rue de la ville (R), abords rocheux (G), camp piétiné (B), traces de pneus (A)."""
    from PIL import Image, ImageDraw, ImageFilter
    ext = (-30.0, 80.0, -10.0, 60.0)   # x0, x1, rangée0, rangée1
    ppx = 8
    x0, x1, y0, y1 = ext
    Wp, Hp = int((x1 - x0) * ppx), int((y1 - y0) * ppx)

    def P(cx, cy):
        return ((cx - x0) * ppx, (cy - y0) * ppx)
    R = Image.new("L", (Wp, Hp), 0)
    dr = ImageDraw.Draw(R)
    dr.rectangle([P(-30, 18.6), P(80, 23.4)], fill=255)          # grand-rue
    pts = [P(CAM_X + 2.5 + 0.8 * math.sin(r * 0.25), r) for r in range(22, 61)]  # piste vers le camp
    dr.line(pts, fill=230, width=int(ppx * 2.6))
    R = R.filter(ImageFilter.GaussianBlur(ppx * 0.8))
    G = Image.new("L", (Wp, Hp), 0)
    Bm = Image.new("L", (Wp, Hp), 0)
    db = ImageDraw.Draw(Bm)
    db.ellipse([P(CAM_X - 9, cam_row(13)), P(CAM_X + 9, cam_row(1))], fill=200)
    Bm = Bm.filter(ImageFilter.GaussianBlur(ppx * 2.0))
    Am = Image.new("L", (Wp, Hp), 0)
    da = ImageDraw.Draw(Am)
    for off in (-0.55, 0.55):
        da.line([P(CAM_X + 2.5 + off + 0.8 * math.sin(r * 0.25), r) for r in range(22, 61)], fill=255, width=max(1, int(ppx * 0.25)))
    img = Image.merge("RGBA", (R, G, Bm, Am)).transpose(Image.FLIP_TOP_BOTTOM)
    mask = os.path.join(TMP, "_menu_ground_mask.png")
    img.save(mask)
    fw.mat_ground(mask, ext)
    mb = MB()
    E = 420.0
    mb.poly([(-E, -E, 0), (E, -E, 0), (E, E, 0), (-E, E, 0)], "ground", [(0, 0), (1, 0), (1, 1), (0, 1)])
    g = mb.to_object("ground", "world")
    g["menu_ground"] = True
    # éparpillement : herbes sèches, buissons, cactus, cailloux entre le camp et la ville
    sc = MB()
    rng = random.Random(21)
    for _ in range(900):
        depth = rng.uniform(5.0, 70.0)
        half = depth * 0.62 + 2.0
        x = CAM_X + rng.uniform(-half, half)
        if depth < 10.0 and abs(x - CAM_X) < 7.0 and rng.random() < 0.85:
            continue   # camp : sol dégagé
        row = cam_row(depth)
        if 10.5 <= row <= 23.5 and -2 <= x <= 54:
            continue   # ville
        y = Y(row)
        r = rng.random()
        if r < 0.38:
            fw.grass(sc, x, y, rng.uniform(0.7, 1.2), rng)
        elif r < 0.66:
            fw.shrub(sc, x, y, rng.uniform(0.6, 1.3), rng, rng.choice(["sage", "dry", "foliage2", "sage"]))
        elif r < 0.74:
            fw.cactus(sc, x, y, rng.uniform(0.6, 1.0), rng)
        else:
            sc.sphere(x, y, 0.0, rng.uniform(0.06, 0.2), rng.choice(["pebble", "rock", "stone"]), sub=1, sz=0.5, jitter=0.35, rng=rng)
    sc.to_object("scatter", "world")


def mesa(mb, cx, cy, rx, ry, height, rng, flat=True):
    z = 0.0
    while z < height:
        hh = rng.uniform(0.9, 1.6)
        fw.slab(mb, cx + rng.uniform(-0.3, 0.3), cy + rng.uniform(-0.3, 0.3), z, rx, ry, hh, rng, rng.uniform(0, 0.3), 48)
        z += hh * 0.92
        k = rng.uniform(0.96, 1.0) if (flat and z < height * 0.85) else rng.uniform(0.78, 0.9)
        rx *= k
        ry *= k


def build_far() -> None:
    """Mesas et buttes lointaines (horizon) + rochers à mi-distance."""
    mb = MB()
    rng = random.Random(9)
    for (dx, depth, rx, ry, h) in ((-70, 150, 26, 9, 16), (-22, 175, 18, 8, 22), (30, 160, 30, 10, 13),
                                   (85, 140, 22, 8, 19), (130, 190, 30, 10, 24), (-120, 185, 26, 9, 14)):
        mesa(mb, CAM_X + dx, Y(cam_row(depth)), rx, ry, h, rng)
    for (dx, depth, rx, ry, h) in ((-38, 85, 7, 4, 7), (52, 80, 8, 4, 6), (-58, 100, 6, 3, 9), (16, 110, 5, 3, 8)):
        mesa(mb, CAM_X + dx, Y(cam_row(depth)), rx, ry, h, rng, flat=False)
    mb.to_object("mesas", "far")
    rk = MB()
    for (dx, depth, n, h) in ((-17, 26, 14, 2.2), (19, 24, 12, 1.8), (-26, 40, 20, 3.0), (30, 44, 18, 2.6)):
        cells = [[int(CAM_X + dx) + i, int(cam_row(depth)) + j] for i in range(int(math.sqrt(n)) + 1) for j in range(int(math.sqrt(n)))]
        fw.rock_formation(rk, cells, h, random.Random(n))
    rk.to_object("rocks_mid", "world")


# ----------------------------------------------------------------------------- camp
def local(x, y, rot, lx, ly):
    return fw.local(x, y, rot, lx, ly)


def truck(mb, x, y, rot, rng):
    """Camion militaire bâché (type 4x4), vert olive, couché le long de `rot`."""
    def box(lx0, ly0, z0, lx1, ly1, z1, mat):
        cx, cy = local(x, y, rot, (lx0 + lx1) / 2, (ly0 + ly1) / 2)
        hx, hy = (lx1 - lx0) / 2, (ly1 - ly0) / 2
        mb.box(cx - hx, cy - hy, z0, cx + hx, cy + hy, z1, mat, rot=rot, piv=(cx, cy))
    L, Wd = 4.4, 1.55
    box(-L / 2, -0.45, 0.42, L / 2, 0.45, 0.6, "gunmetal")               # châssis
    box(L / 2 - 1.05, -Wd / 2, 0.62, L / 2 - 0.05, Wd / 2, 1.18, "olive")  # capot
    box(L / 2 - 0.05, -Wd / 2 + 0.1, 0.62, L / 2 + 0.06, Wd / 2 - 0.1, 1.08, "polymer")  # calandre
    for sg in (-1, 1):
        px, py = local(x, y, rot, L / 2 + 0.07, sg * 0.5)
        mb.cyl(px, py, 0.98, 0.06, 0.09, "headlight", 12, axis="X", rot=rot)
    box(L / 2 + 0.02, -Wd / 2 - 0.05, 0.5, L / 2 + 0.2, Wd / 2 + 0.05, 0.62, "gunmetal")  # pare-chocs
    box(L / 2 - 1.95, -Wd / 2, 0.62, L / 2 - 1.05, Wd / 2, 1.72, "olive")  # cabine
    box(L / 2 - 1.08, -Wd / 2 + 0.08, 1.2, L / 2 - 1.02, Wd / 2 - 0.08, 1.64, "glass")  # pare-brise
    for sg in (-1, 1):
        box(L / 2 - 1.85, sg * Wd / 2 - 0.02, 1.22, L / 2 - 1.2, sg * Wd / 2 + 0.02, 1.6, "glass")  # vitres
    box(L / 2 - 2.0, -Wd / 2 - 0.02, 1.72, L / 2 - 1.0, Wd / 2 + 0.02, 1.78, "olive")
    box(-L / 2, -Wd / 2, 0.62, L / 2 - 2.0, Wd / 2, 1.0, "olive")         # plateau
    # bâche (demi-cylindre aplati)
    n = 10
    R = Wd / 2 + 0.03
    zc = 1.0
    rings = []
    for lx in (-L / 2 + 0.02, L / 2 - 2.05):
        ring = []
        for j in range(n + 1):
            a = math.pi * j / n
            px, py = local(x, y, rot, lx, math.cos(a) * R)
            ring.append(mb.bm.verts.new((px, py, zc + 0.35 + math.sin(a) * R * 0.75)))
        rings.append(ring)
    mi = mb.mi("khaki")
    for j in range(n):
        f = mb.bm.faces.new((rings[0][j], rings[0][j + 1], rings[1][j + 1], rings[1][j]))
        f.material_index = mi
    for k in (0, 1):
        f = mb.bm.faces.new(rings[k] if k else list(reversed(rings[k])))
        f.material_index = mi
    for sg in (-1, 1):   # flancs droits de la bâche
        box(-L / 2 + 0.02, sg * R - 0.012, zc, L / 2 - 2.05, sg * R + 0.012, zc + 0.36, "khaki")
    # roues
    for lx in (-1.35, -0.55, 1.45):
        for sg in (-1, 1):
            px, py = local(x, y, rot, lx, sg * (Wd / 2 - 0.05))
            mb.cyl(px, py, 0.42, 0.3, 0.42, "rubber", 18, axis="Y", rot=rot)
            px2, py2 = local(x, y, rot, lx, sg * (Wd / 2 + 0.11))
            mb.cyl(px2, py2, 0.42, 0.02, 0.22, "olive_light", 12, axis="Y", rot=rot)
    # jerricans + roue de secours
    for k in range(2):
        box(-L / 2 + 0.3 + k * 0.3, -Wd / 2 - 0.16, 0.62, -L / 2 + 0.55 + k * 0.3, -Wd / 2 - 0.02, 0.98, "olive_light")
    px, py = local(x, y, rot, -L / 2 - 0.12, 0.0)
    mb.cyl(px, py, 1.0, 0.25, 0.4, "rubber", 18, axis="X", rot=rot)


def tent(mb, x, y, rot, rng):
    """Tente militaire (toit à deux pans, entrée ouverte vers la caméra)."""
    L, Wd, Hh, Hw = 2.6, 2.4, 1.75, 0.75
    def P(lx, ly, z):
        px, py = local(x, y, rot, lx, ly)
        return (px, py, z)
    # pans de toit (le long de X local), murets
    for sg in (-1, 1):
        mb.poly([P(-L / 2, sg * Wd / 2, Hw), P(L / 2, sg * Wd / 2, Hw), P(L / 2, 0, Hh), P(-L / 2, 0, Hh)][::sg], "khaki")
        mb.poly([P(-L / 2, sg * Wd / 2, 0), P(L / 2, sg * Wd / 2, 0), P(L / 2, sg * Wd / 2, Hw), P(-L / 2, sg * Wd / 2, Hw)][::-sg], "khaki")
    # fond (arrière) plein, avant ouvert (intérieur sombre + rabats relevés)
    mb.poly([P(-L / 2, -Wd / 2, 0), P(-L / 2, Wd / 2, 0), P(-L / 2, Wd / 2, Hw), P(-L / 2, 0, Hh), P(-L / 2, -Wd / 2, Hw)], "khaki")
    mb.poly([P(L / 2 - 0.02, -Wd / 2 + 0.05, 0), P(L / 2 - 0.02, Wd / 2 - 0.05, 0), P(L / 2 - 0.02, Wd / 2 - 0.05, Hw),
             P(L / 2 - 0.02, 0, Hh - 0.05), P(L / 2 - 0.02, -Wd / 2 + 0.05, Hw)], "khaki")
    mb.poly([P(L / 2, -0.5, 0.0), P(L / 2, 0.5, 0.0), P(L / 2, 0.5, 1.05), P(L / 2, 0.0, 1.45), P(L / 2, -0.5, 1.05)], "tent_inside")
    for sg in (-1, 1):   # rabats roulés
        a = P(L / 2 + 0.03, sg * 0.55, 0.15)
        b = P(L / 2 + 0.03, sg * 0.32, 1.35)
        mb.seg(a, b, 0.07, "khaki_dark", 8)
    # faîtière, mâts, haubans, piquets
    mb.seg(P(-L / 2 - 0.1, 0, Hh + 0.02), P(L / 2 + 0.1, 0, Hh + 0.02), 0.035, "wood_dark", 6)
    for lx in (-L / 2 - 0.05, L / 2 + 0.05):
        mb.seg(P(lx, 0, 0), P(lx, 0, Hh + 0.12), 0.03, "wood_dark", 6)
    for lx in (-L / 2 + 0.2, 0.0, L / 2 - 0.2):
        for sg in (-1, 1):
            a = P(lx, sg * Wd / 2, Hw)
            b = P(lx, sg * (Wd / 2 + 0.75), 0.0)
            mb.seg(a, b, 0.008, "cable", 3)
            mb.seg(b, (b[0], b[1], 0.12), 0.02, "wood_dark", 4)


def table_with_guns(mb, x, y, rot, rng):
    """Table pliante couverte d'armes, caisses de munitions, radio et lanterne."""
    def box(lx0, ly0, z0, lx1, ly1, z1, mat, r=0.0):
        cx, cy = local(x, y, rot, (lx0 + lx1) / 2, (ly0 + ly1) / 2)
        hx, hy = (lx1 - lx0) / 2, (ly1 - ly0) / 2
        mb.box(cx - hx, cy - hy, z0, cx + hx, cy + hy, z1, mat, rot=rot + r, piv=(cx, cy))
    box(-0.9, -0.38, 0.6, 0.9, 0.38, 0.65, "olive_light")
    for (a, b) in ((-0.82, -0.3), (0.82, -0.3), (-0.82, 0.3), (0.82, 0.3)):
        box(a - 0.02, b - 0.02, 0.0, a + 0.02, b + 0.02, 0.6, "gunmetal")
    # fusils couchés
    for (lx, ly, r) in ((-0.25, -0.12, 0.08), (0.05, 0.12, -0.05), (0.5, -0.18, 0.2)):
        box(lx - 0.42, ly - 0.03, 0.65, lx + 0.12, ly + 0.03, 0.72, "gunmetal", r)
        box(lx + 0.12, ly - 0.035, 0.65, lx + 0.42, ly + 0.035, 0.73, "polymer", r)
        box(lx - 0.15, ly + 0.02, 0.65, lx - 0.08, ly + 0.14, 0.69, "polymer", r)
    # caisses de munitions
    for (lx, ly) in ((-0.68, 0.2), (0.7, 0.18)):
        box(lx - 0.13, ly - 0.08, 0.65, lx + 0.13, ly + 0.08, 0.8, "olive")
        box(lx - 0.13, ly - 0.085, 0.72, lx + 0.13, ly - 0.08, 0.75, "yellow_stencil")
    # radio + antenne
    box(0.25, 0.18, 0.65, 0.5, 0.33, 0.85, "olive")
    px, py = local(x, y, rot, 0.45, 0.3)
    mb.seg((px, py, 0.85), (px + 0.05, py, 1.55), 0.006, "cable", 3)
    # lanterne
    px, py = local(x, y, rot, -0.45, 0.25)
    mb.cyl(px, py, 0.65, 0.68, 0.06, "gunmetal", 10)
    mb.cyl(px, py, 0.68, 0.82, 0.045, "lamp", 10)
    mb.cyl(px, py, 0.82, 0.86, 0.06, "gunmetal", 10)


def camo_net(mb, x, y, rot, rng, L=3.4, Wd=2.4, h=1.95):
    """Filet de camouflage tendu sur quatre perches, qui pend entre elles."""
    nx, ny = 18, 12
    grid = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            u, v = i / nx, j / ny
            lx, ly = (u - 0.5) * L, (v - 0.5) * Wd
            sag = 0.32 * math.sin(math.pi * u) * math.sin(math.pi * v) + rng.uniform(-0.04, 0.04)
            px, py = local(x, y, rot, lx, ly)
            row.append(mb.bm.verts.new((px, py, h - sag)))
        grid.append(row)
    mi = mb.mi("camo_net")
    for j in range(ny):
        for i in range(nx):
            f = mb.bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            f.material_index = mi
    for (u, v) in ((0, 0), (1, 0), (0, 1), (1, 1)):
        px, py = local(x, y, rot, (u - 0.5) * L, (v - 0.5) * Wd)
        mb.seg((px, py, 0.0), (px, py, h + 0.05), 0.035, "wood_dark", 6)
    # pans qui pendent sur les côtés
    for sg in (-1, 1):
        for i in range(0, nx, 3):
            u = i / nx
            px, py = local(x, y, rot, (u - 0.5) * L, sg * Wd / 2)
            mb.seg((px, py, h), (px, py + rng.uniform(-0.05, 0.05), h - rng.uniform(0.3, 0.6)), 0.05, "camo_net", 4)


def ammo_crate(mb, x, y, rot, z=0.0, s=1.0, mat="olive"):
    L, Wd, Hh = 0.75 * s, 0.38 * s, 0.32 * s
    def box(lx0, ly0, z0, lx1, ly1, z1, m):
        cx, cy = local(x, y, rot, (lx0 + lx1) / 2, (ly0 + ly1) / 2)
        hx, hy = (lx1 - lx0) / 2, (ly1 - ly0) / 2
        mb.box(cx - hx, cy - hy, z0, cx + hx, cy + hy, z1, m, rot=rot, piv=(cx, cy))
    box(-L / 2, -Wd / 2, z, L / 2, Wd / 2, z + Hh, mat)
    box(-L / 2 - 0.01, -Wd / 2 - 0.01, z + Hh - 0.05, L / 2 + 0.01, Wd / 2 + 0.01, z + Hh + 0.01, "olive_light" if mat == "olive" else "wood_dark")
    box(-L / 2 * 0.6, -Wd / 2 - 0.012, z + Hh * 0.35, L / 2 * 0.6, -Wd / 2 - 0.005, z + Hh * 0.55, "yellow_stencil")
    for sg in (-1, 1):
        box(sg * L / 2 - 0.02, -0.06, z + Hh * 0.55, sg * L / 2 + 0.02, 0.06, z + Hh * 0.65, "gunmetal")


def drum(mb, x, y, mat="olive"):
    mb.cyl(x, y, 0, 0.82, 0.27, mat, 18)
    for z in (0.27, 0.55):
        mb.cyl(x, y, z, z + 0.03, 0.28, mat, 18)
    mb.cyl(x, y, 0.82, 0.84, 0.25, "gunmetal", 18)


def sandbags(mb, pts, rows, rng, k=1.0):
    """Muret de sacs de sable le long d'une polyligne (x, y monde) ; k = échelle des sacs."""
    for r in range(rows):
        for q in range(len(pts) - 1):
            p0, p1 = Vector((*pts[q], 0)), Vector((*pts[q + 1], 0))
            d = p1 - p0
            Lg = d.length
            n = max(1, int(Lg / (0.5 * k)))
            for i in range(n):
                t = (i + 0.5 + (0.5 if r % 2 else 0.0)) / n
                if t > 1.0:
                    continue
                c = p0.lerp(p1, t)
                mb.sphere(c.x, c.y, (0.11 + r * 0.19) * k, 0.27 * k, "sandbag", sub=2, sx=1.0, sy=0.6, sz=0.4,
                          jitter=0.06, rng=rng)


def hedgehog(mb, x, y, rng, s=1.0):
    """Hérisson tchèque (trois poutrelles d'acier croisées)."""
    for k in range(3):
        a = k * math.pi / 3 + rng.uniform(-0.1, 0.1)
        d = Vector((math.cos(a), math.sin(a), 0.9)).normalized() * 0.85 * s
        c = Vector((x, y, 0.55 * s))
        mb.seg(c - d, c + d, 0.06 * s, "rust_iron", 4)


def campfire(mb, x, y, rng):
    for k in range(11):
        a = k / 11 * math.tau
        mb.sphere(x + math.cos(a) * 0.36, y + math.sin(a) * 0.3, 0.05, rng.uniform(0.08, 0.11), "stone", sub=1, sz=0.7, jitter=0.25, rng=rng)
    for k in range(5):
        a = k / 5 * math.tau + 0.3
        p0 = (x + math.cos(a) * 0.3, y + math.sin(a) * 0.26, 0.04)
        p1 = (x + math.cos(a) * 0.04, y + math.sin(a) * 0.04, 0.3)
        mb.seg(p0, p1, 0.045, "deadwood" if k % 2 else "wood_dark", 6)
    for k in range(8):
        mb.sphere(x + rng.uniform(-0.15, 0.15), y + rng.uniform(-0.12, 0.12), 0.03, rng.uniform(0.04, 0.07), "ember", sub=1, sz=0.6, jitter=0.3, rng=rng)
    # bûches-bancs
    for (dx, dy, a) in ((0.0, 1.0, 0.1), (1.05, 0.15, 1.45)):
        px, py = x + dx, y + dy
        d = Vector((math.cos(a), math.sin(a), 0)) * 0.6
        mb.seg((px - d.x, py - d.y, 0.14), (px + d.x, py + d.y, 0.14), 0.13, "bark", 10)


def string_lights(mb, p0, p1, n, sag=0.35):
    p0, p1 = Vector(p0), Vector(p1)
    pts = []
    for k in range(n + 1):
        t = k / n
        p = p0.lerp(p1, t)
        p.z -= sag * 4 * t * (1 - t)
        pts.append(p)
    for k in range(n):
        mb.seg(pts[k], pts[k + 1], 0.006, "cable", 3)
    for k in range(1, n):
        q = pts[k]
        mb.sphere(q.x, q.y, q.z - 0.05, 0.035, "bulb", sub=1)


FLAG = {}


def build_camp() -> None:
    """Camp de base. Positions : (décalage x par rapport à l'axe de la caméra, profondeur).
    Le centre de l'image (derrière le héros et le feu) reste dégagé jusqu'à la grand-rue."""
    rng = random.Random(3)
    camp = MB()
    # feu de camp à droite du héros, un peu derrière ; bûches-bancs
    fx, fy = W(CAM_X + 0.95, 5.3)
    campfire(camp, fx, fy, rng)
    FLAG["fire"] = (fx, fy, 0.18)
    # sac à dos posé à gauche du héros (corps, rabat, poches, bretelles)
    px, py = W(CAM_X - 1.35, 4.4)
    camp.box(px - 0.17, py - 0.11, 0.0, px + 0.17, py + 0.11, 0.42, "khaki", rot=0.4, piv=(px, py))
    camp.box(px - 0.18, py - 0.13, 0.36, px + 0.18, py + 0.1, 0.46, "khaki_dark", rot=0.4, piv=(px, py))
    camp.box(px - 0.12, py - 0.17, 0.06, px + 0.12, py - 0.1, 0.26, "khaki_dark", rot=0.4, piv=(px, py))
    camp.seg((px - 0.12, py + 0.1, 0.05), (px - 0.1, py + 0.12, 0.4), 0.025, "khaki_dark", 5)   # bretelles
    camp.seg((px + 0.12, py + 0.1, 0.05), (px + 0.1, py + 0.12, 0.4), 0.025, "khaki_dark", 5)
    # filet de camouflage + table d'armes (gauche), camion derrière
    nx, ny = W(CAM_X - 3.7, 11.5)
    camo_net(camp, nx, ny, math.radians(10), rng)
    table_with_guns(camp, nx + 0.2, ny + 0.1, math.radians(10), rng)
    FLAG["lantern"] = (nx + 0.2 - 0.45, ny + 0.1 + 0.25, 0.78)
    kx, ky = W(CAM_X - 7.6, 16.0)
    truck(camp, kx, ky, math.radians(-32), rng)
    # tente (droite)
    tx, ty = W(CAM_X + 5.9, 12.8)
    tent(camp, tx, ty, math.radians(-108), rng)
    # caisses de munitions, fûts, caisses en bois
    for (dx, d, r, st) in ((-2.9, 7.4, 0.3, 2), (-2.1, 7.1, -0.2, 1), (2.7, 7.6, 0.5, 2), (3.5, 7.0, 1.2, 1),
                           (4.0, 11.2, 0.1, 1), (-5.6, 9.6, 0.9, 1)):
        px, py = W(CAM_X + dx, d)
        for k in range(st):
            ammo_crate(camp, px + rng.uniform(-0.04, 0.04), py, r + rng.uniform(-0.1, 0.1), z=k * 0.33)
    for (dx, d, m) in ((-5.6, 12.6, "olive"), (-5.15, 12.9, "olive"), (8.2, 12.0, "rust_iron"), (7.8, 12.5, "olive")):
        px, py = W(CAM_X + dx, d)
        drum(camp, px, py, m)
    for (dx, d) in ((-1.7, 9.3), (7.4, 14.6)):
        px, py = W(CAM_X + dx, d)
        fw.crate(camp, px, py, 0.5, rng, 0.0, rng.uniform(-0.3, 0.3))
        fw.crate(camp, px + 0.05, py, 0.42, rng, 0.5, rng.uniform(-0.3, 0.3))
    # mât + drapeau (le drapeau est rendu à part, animé)
    fx2, fy2 = W(CAM_X + 2.7, 15.5)
    camp.cyl(fx2, fy2, 0, 3.3, 0.035, "steel", 10)
    camp.sphere(fx2, fy2, 3.33, 0.055, "brass", sub=1)
    camp.cyl(fx2, fy2, 0, 0.12, 0.2, "stone", 12)
    FLAG["pole"] = (fx2, fy2, 3.2)
    # guirlandes lumineuses : du mât vers le filet et vers la tente
    string_lights(camp, (fx2, fy2, 2.3), (nx + 1.6, ny - 1.1, 1.95), 11, 0.3)
    string_lights(camp, (fx2, fy2, 2.2), (tx - 0.7, ty - 0.6, 1.8), 8, 0.22)
    # hérissons tchèques et sacs de sable à mi-distance
    for (dx, d) in ((-6.8, 21.0), (6.0, 23.0), (-1.0, 26.0), (10.5, 19.0)):
        px, py = W(CAM_X + dx, d)
        hedgehog(camp, px, py, rng)
    px, py = W(CAM_X + 8.8, 16.5)
    sandbags(camp, [(px - 1.4, py + 0.2), (px, py - 0.25), (px + 1.2, py + 0.3)], 3, rng)
    camp.to_object("camp", "camp")
    # premier plan (coins bas de l'image)
    front = MB()
    lx_, ly_ = W(CAM_X - 1.95, 2.6)
    sandbags(front, [(lx_ - 0.9, ly_ + 0.4), (lx_ - 0.2, ly_), (lx_ + 0.25, ly_ - 0.15)], 2, random.Random(5), 0.6)
    rx_, ry_ = W(CAM_X + 1.95, 2.9)
    ammo_crate(front, rx_, ry_, 0.5, 0.0, 0.8)
    ammo_crate(front, rx_ + 0.08, ry_ + 0.05, 0.25, 0.26, 0.8)
    front.to_object("front", "front")
    # lumière du feu (chaude) + lanterne
    for (pos, energy, col, radius) in (((fx, fy, 0.75), 22.0, (1.0, 0.45, 0.15), 0.25),
                                       (FLAG["lantern"][:2] + (0.95,), 5.0, (1.0, 0.6, 0.3), 0.05)):
        L = bpy.data.lights.new("pt", "POINT")
        L.energy = energy
        L.color = col
        L.shadow_soft_size = radius
        o = bpy.data.objects.new("pt", L)
        fw.coll("lights").objects.link(o)
        o.location = pos


def build_flag(phase: float) -> bpy.types.Object:
    """Drapeau (1,5 x 0,95) accroché au mât, ondulation à la phase donnée (0..1)."""
    for o in list(bpy.data.objects):
        if o.name.startswith("flagcloth"):
            bpy.data.objects.remove(o)
    px, py, top = FLAG["pole"]
    Lf, Hf = 1.25, 0.78
    nx, ny = 24, 12
    V, F, UV = [], [], []
    for j in range(ny + 1):
        for i in range(nx + 1):
            u, v = i / nx, j / ny
            a = u ** 1.2
            wave = 0.16 * a * math.sin(2 * math.pi * (u * 1.4 - phase)) + 0.05 * a * math.sin(2 * math.pi * (u * 2.7 - phase * 2) + v * 2)
            droop = -0.12 * a * a - 0.04 * a * math.sin(2 * math.pi * (phase + v * 0.5))
            # le drapeau flotte vers la droite de l'écran (+X) et un peu vers l'arrière (+Y)
            x = px + 0.05 + u * Lf * 0.96
            y = py + u * 0.25 + wave
            z = top - (1 - v) * Hf + droop
            V.append((x, y, z))
            UV.append((u, v))
    for j in range(ny):
        for i in range(nx):
            k = j * (nx + 1) + i
            F.append((k, k + 1, k + nx + 2, k + nx + 1))
    me = bpy.data.meshes.new("flagcloth")
    me.from_pydata(V, [], F)
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            uvl.data[li].uv = UV[vi]
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.materials.append(fw.MATS["flag_cloth"])
    ob = bpy.data.objects.new("flagcloth", me)
    fw.coll("flag").objects.link(ob)
    return ob


# ----------------------------------------------------------------------------- caméra, lumière
def setup_camera_light():
    cam = fw.setup_render()
    sc = fw.scene
    cam.data.type = "PERSP"
    cam.data.lens = LENS
    cam.data.sensor_width = 36.0
    cam.data.sensor_fit = "HORIZONTAL"
    cam.data.clip_start = 0.05
    cam.data.clip_end = 2000.0
    cam.location = (CAM_X, Y(CAM_ROW), CAM_Z)
    cam.rotation_euler = Euler((math.radians(90 + PITCH), 0, 0))
    sc.render.resolution_x, sc.render.resolution_y = IMG_W, IMG_H
    sc.render.pixel_aspect_x = 1.0
    sc.render.resolution_percentage = 100
    sun = bpy.data.objects["sun"]
    # soleil bas à l'ouest (gauche), un peu côté caméra : lumière rasante sur les façades
    d = Vector((0.86, 0.42, -0.26)).normalized()
    sun.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    sun.data.energy = float(os.environ.get("MENU_SUN", "6.0"))
    sun.data.color = (1.0, 0.62, 0.36)
    w = sc.world
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.36, 0.30, 0.58, 1)
    bg.inputs[1].default_value = float(os.environ.get("MENU_SKY", "0.9"))
    sc.render.film_transparent = True
    sc.render.image_settings.color_mode = "RGBA"
    sc.cycles.samples = SAMPLES
    return cam


def project(cam, co) -> tuple[float, float]:
    from bpy_extras.object_utils import world_to_camera_view
    bpy.context.view_layer.update()
    v = world_to_camera_view(fw.scene, cam, Vector(co))
    return (v.x * IMG_W, (1.0 - v.y) * IMG_H)


def set_layer(visible: list[str], catcher: bool) -> None:
    """Affiche seulement ces collections ; `catcher` : le sol devient un attrape-ombres."""
    vl = fw.scene.view_layers[0]
    for lc in vl.layer_collection.children:
        lc.exclude = lc.name not in visible and not (catcher and lc.name == "world")
    for o in bpy.data.collections["world"].objects:
        if catcher:
            keep = o.name == "ground"
            o.hide_render = not keep
            o.is_shadow_catcher = keep
        else:
            o.hide_render = False
            o.is_shadow_catcher = False


def render(path: str) -> None:
    fw.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ----------------------------------------------------------------------------- ciel + compositing
def paint_sky(w: int, h: int, horizon: float, sun_xy: tuple[float, float]):
    """Ciel de coucher de soleil peint (numpy) : violet en haut, rose, orange, jaune pâle à
    l'horizon ; halo du soleil, longs nuages effilés éclairés par en dessous, étoiles discrètes."""
    import numpy as np
    from PIL import Image, ImageFilter
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = np.clip(yy / max(horizon, 1.0), 0.0, 1.3)
    stops = [(0.0, (34, 30, 74)), (0.35, (88, 52, 112)), (0.62, (186, 86, 116)), (0.82, (238, 132, 94)),
             (0.95, (252, 186, 112)), (1.05, (255, 214, 150)), (1.3, (240, 170, 120))]
    sky = np.zeros((h, w, 3), np.float32)
    for c in range(3):
        sky[..., c] = np.interp(t, [s[0] for s in stops], [s[1][c] for s in stops])
    sx, sy = sun_xy
    d = np.sqrt(((xx - sx) / w) ** 2 * 2.2 + ((yy - sy) / h) ** 2 * 3.0)
    glow = np.exp(-d * 5.5)[..., None]
    sky = sky * (1 - glow * 0.55) + np.array([255, 226, 160], np.float32) * glow * 0.55
    core = np.exp(-(d / 0.035) ** 2)[..., None]
    sky = sky * (1 - core) + np.array([255, 246, 214], np.float32) * core
    # nuages : bruit de valeur multi-échelle étiré horizontalement
    rng = np.random.default_rng(5)
    cloud = np.zeros((h, w), np.float32)
    for k, amp in ((8, 0.5), (16, 0.3), (40, 0.2)):
        small = rng.random((k, k * 2)).astype(np.float32)
        im = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        cloud += np.asarray(im, np.float32) / 255.0 * amp
    band = np.exp(-((t - 0.55) / 0.22) ** 2) * 0.9 + np.exp(-((t - 0.25) / 0.12) ** 2) * 0.5
    cm = np.clip((cloud - 0.52) * 3.2, 0, 1) * band
    cm_img = Image.fromarray((cm * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(w / 400))
    cm = np.asarray(cm_img, np.float32)[..., None] / 255.0
    lit = np.clip(1.0 - np.abs(xx - sx)[..., None] / (w * 0.9), 0.3, 1.0)
    ccol = np.array([120, 62, 112], np.float32) * (1 - lit) + np.array([255, 150, 120], np.float32) * lit
    sky = sky * (1 - cm * 0.75) + ccol * cm * 0.75
    stars = (rng.random((h, w)) > 0.9994) * np.clip(1 - t * 2.2, 0, 1)
    sky += stars[..., None] * 160
    return Image.fromarray(np.clip(sky, 0, 255).astype(np.uint8))


def composite_back(back_png: str, mist_png: str | None, horizon_y: float, sun_xy, out_jpg: str) -> None:
    import numpy as np
    from PIL import Image, ImageEnhance
    rgba = Image.open(back_png).convert("RGBA")
    w, h = rgba.size
    sky = paint_sky(w, h, horizon_y, sun_xy).convert("RGBA")
    img = Image.alpha_composite(sky, rgba)
    arr = np.asarray(img.convert("RGB"), np.float32)
    if mist_png and os.path.exists(mist_png):
        m = np.asarray(Image.open(mist_png).convert("L").resize((w, h)), np.float32) / 255.0
        m = np.where(m <= 0.04045, m / 12.92, ((m + 0.055) / 1.055) ** 2.4)   # sRGB -> linéaire
        a = np.asarray(rgba.getchannel("A"), np.float32) / 255.0
        dist = m * 400.0
        fog = (1.0 - np.exp(-np.maximum(dist - 14.0, 0.0) / 120.0)) * a
        yy = np.arange(h, dtype=np.float32)[:, None]
        hz = np.clip(1.0 - np.abs(yy - horizon_y) / (h * 0.5), 0, 1)
        fogcol = np.asarray(sky.convert("RGB"), np.float32) * 0.6 + np.array([236, 150, 128], np.float32) * 0.4
        f = np.clip(fog * (0.55 + 0.45 * hz), 0, 0.85)[..., None]
        arr = arr * (1 - f) + fogcol * f
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    if mist_png and os.path.exists(mist_png):
        # profondeur de champ : le lointain (ville, mesas) légèrement flou, le camp net
        from PIL import ImageFilter
        blur = out.filter(ImageFilter.GaussianBlur(w / 900.0))
        k = np.clip((dist - 12.0) / 25.0, 0, 1) * a + (1 - a)
        k_img = Image.fromarray((k * 255).astype(np.uint8))
        out = Image.composite(blur, out, k_img)
    out = ImageEnhance.Color(out).enhance(1.12)
    out.save(out_jpg, quality=90, optimize=True)


def crop_layer(src: str, dst: str) -> list[int]:
    """Rogne une couche transparente à sa boîte englobante ; renvoie [x, y, w, h]."""
    from PIL import Image
    im = Image.open(src).convert("RGBA")
    a = im.getchannel("A").point(lambda v: 0 if v < 12 else v)   # bruit de l'attrape-ombres
    im.putalpha(a)
    bb = a.getbbox() or (0, 0, 1, 1)
    im.crop(bb).save(dst, optimize=True)
    return [bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1]]


def grade_layer(path: str) -> None:
    from PIL import Image, ImageEnhance
    im = Image.open(path).convert("RGBA")
    a = im.getchannel("A")
    rgb = ImageEnhance.Color(im.convert("RGB")).enhance(fw.SAT)
    rgb = ImageEnhance.Contrast(rgb).enhance(fw.CON)
    rgb.putalpha(a)
    rgb.save(path)


def mist_material() -> bpy.types.Material:
    m = bpy.data.materials.new("menu_mist")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    lp = nt.nodes.new("ShaderNodeLightPath")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.0
    mr.inputs["From Max"].default_value = 400.0
    nt.links.new(lp.outputs["Ray Length"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], em.inputs["Color"])
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


# ----------------------------------------------------------------------------- main
def main() -> None:
    import time
    t0 = time.time()
    fw.build_materials()
    extra_materials()
    fw.build_ground = build_ground_menu
    fw.build_world()
    build_far()
    build_camp()
    for c in ("camp", "front", "far", "flag", "lights"):
        fw.coll(c)
    cam = setup_camera_light()
    print("BUILD %.1fs" % (time.time() - t0), flush=True)
    sc = fw.scene
    sc.render.use_persistent_data = True
    suffix = "_q" if QUICK else ""
    meta: dict = {"size": [IMG_W, IMG_H]}
    horizon = project(cam, (CAM_X, Y(CAM_ROW - 3000.0), 0.0))
    sun_xy = (-IMG_W * 0.06, horizon[1] - IMG_H * 0.04)   # soleil juste hors champ, à gauche
    meta["horizon_y"] = round(horizon[1], 1)
    # héros : pieds au sol à HERO_DEPTH, x choisi à l'écran
    feet_row = cam_row(HERO_DEPTH)
    fx_ = project(cam, (CAM_X, Y(feet_row), 0.0))
    # x monde pour la fraction voulue : interpolation linéaire à cette profondeur
    p1 = project(cam, (CAM_X + 1.0, Y(feet_row), 0.0))
    hx = CAM_X + (HERO_SCREEN_X * IMG_W - fx_[0]) / (p1[0] - fx_[0])
    feet = project(cam, (hx, Y(feet_row), 0.0))
    head = project(cam, (hx, Y(feet_row), 1.0))
    meta["hero"] = {"feet": [round(feet[0], 1), round(feet[1], 1)], "unit_px": round(feet[1] - head[1], 2)}
    fire = FLAG["fire"]
    fp = project(cam, fire)
    fp1 = project(cam, (fire[0], fire[1], fire[2] + 1.0))
    meta["fire"] = {"pos": [round(fp[0], 1), round(fp[1], 1)], "unit_px": round(fp[1] - fp1[1], 2)}
    pole = FLAG["pole"]
    meta["pole_top"] = [round(v, 1) for v in project(cam, pole)]
    p_end = project(cam, (pole[0] + 1.25, pole[1], pole[2]))
    p_low = project(cam, (pole[0], pole[1], pole[2] - 0.78))
    meta["flag"] = {"size": [round(p_end[0] - meta["pole_top"][0], 1), round(p_low[1] - meta["pole_top"][1], 1)]}
    lan = project(cam, FLAG["lantern"])
    meta["lantern"] = [round(lan[0], 1), round(lan[1], 1)]
    meta["sun"] = [round(sun_xy[0], 1), round(sun_xy[1], 1)]

    if "mist" in ONLY:
        set_layer(["world", "far"], False)
        mm = mist_material()
        vl = sc.view_layers[0]
        vl.material_override = mm
        old = (sc.cycles.samples, sc.view_settings.view_transform, sc.view_settings.look, sc.view_settings.exposure,
               sc.cycles.use_denoising)
        sc.cycles.samples = 2
        sc.cycles.use_denoising = False
        sc.view_settings.view_transform = "Standard"
        sc.view_settings.look = "None"
        sc.view_settings.exposure = 0.0
        sun_e = bpy.data.objects["sun"].data.energy
        bpy.data.objects["sun"].data.energy = 0.0
        render(os.path.join(TMP, "mist%s.png" % suffix))
        bpy.data.objects["sun"].data.energy = sun_e
        vl.material_override = None
        sc.cycles.samples, sc.view_settings.view_transform, sc.view_settings.look, sc.view_settings.exposure, \
            sc.cycles.use_denoising = old
        print("MIST %.1fs" % (time.time() - t0), flush=True)
    if "back" in ONLY:
        set_layer(["world", "far", "lights"], False)
        p = os.path.join(TMP, "back%s.png" % suffix)
        render(p)
        grade_layer(p)
        composite_back(p, os.path.join(TMP, "mist%s.png" % suffix), horizon[1], sun_xy, os.path.join(OUT if not QUICK else TMP, "back%s.jpg" % suffix))
        print("BACK %.1fs" % (time.time() - t0), flush=True)
    for name in ("camp", "front"):
        if name in ONLY:
            set_layer([name, "lights"], True)
            p = os.path.join(TMP, "%s%s.png" % (name, suffix))
            render(p)
            grade_layer(p)
            meta[name] = crop_layer(p, os.path.join(OUT if not QUICK else TMP, "%s%s.png" % (name, suffix)))
            print(name.upper(), "%.1fs" % (time.time() - t0), flush=True)
    if "flag" in ONLY:
        from PIL import Image
        set_layer(["flag"], False)
        frames = []
        boxes = []
        for k in range(6):
            build_flag(k / 6.0)
            p = os.path.join(TMP, "flag_%d%s.png" % (k, suffix))
            render(p)
            grade_layer(p)
            im = Image.open(p)
            frames.append(im)
            boxes.append(im.getchannel("A").getbbox())
        bb = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
        fw_, fh_ = bb[2] - bb[0], bb[3] - bb[1]
        sheet = Image.new("RGBA", (fw_ * 3, fh_ * 2), (0, 0, 0, 0))
        for k, im in enumerate(frames):
            sheet.paste(im.crop(bb), ((k % 3) * fw_, (k // 3) * fh_))
        sheet.save(os.path.join(OUT if not QUICK else TMP, "flag%s.png" % suffix), optimize=True)
        meta["flag"] = {"rect": [bb[0], bb[1], fw_, fh_], "cols": 3, "rows": 2, "frames": 6, "fps": 8}
        print("FLAG %.1fs" % (time.time() - t0), flush=True)
    jp = os.path.join(OUT if not QUICK else TMP, "lobby%s.json" % suffix)
    old_meta = {}
    if os.path.exists(jp):
        with open(jp) as f:
            old_meta = json.load(f)
    old_meta.update(meta)
    with open(jp, "w") as f:
        json.dump(old_meta, f, indent=1)
        f.write("\n")
    print("DONE %.1fs" % (time.time() - t0), flush=True)


main()
