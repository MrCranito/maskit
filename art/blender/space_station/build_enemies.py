"""Ennemis masqués de la Station Orbitale Kagami (une vue 3/4 de face par ennemi, flip géré en jeu).

Usage : python3 art/blender/space_station/build_enemies.py [--only space_drone,space_soldier]

Sorties : assets/sprites/space_station/enemies/<kind>.png + $RDM_TMP/space_station/enemies.json (taille, pieds, yeux, tête)
          → reportés dans scripts/biomes/space_station/enemy_kinds.gd (KINDS).
Échelle : 2 px par unité monde (EnemyVisual : scale = 0,5) ; même caméra que le héros (48°),
mêmes proportions héroïques (tête agrandie). Pas d'ombre peinte : EnemyVisual dessine la sienne.
  space_drone            drone de sécurité masqué (rapide, fragile, tir laser)       ~50 u
  space_soldier          soldat en combinaison, masque de spectre (distance)         ~68 u
  space_android          androïde marionnette, masque d'os à fils (mêlée rapide)      ~66 u
  space_brute            brute en exosquelette, masque de colosse (mêlée lourde, zone) ~90 u
  space_reactor_colossus boss : colosse cyborg au cœur de réacteur                    ~130 u
"""
from __future__ import annotations

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ss_art import C, M, ROOT, TMP, custom, render_sprite  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

OUT = os.path.join(ROOT, "assets", "sprites", "space_station", "enemies")
PXW = 2.0
YAW = -0.38   # rotation 3/4 (le personnage tourne légèrement vers la droite de l'écran)


class Rig:
    """Collecte des points remarquables (yeux, sommet) à reporter en pixels après rotation."""

    def __init__(self, B):
        self.B = B
        self.pts: dict[str, tuple] = {}

    def finish(self) -> dict:
        rot = Matrix.Rotation(YAW, 4, "Z")
        for ob in self.B.objs:
            ob.matrix_world = rot @ ob.matrix_world
        return {k: tuple(rot @ Vector(v)) for k, v in self.pts.items()}


def limb(B, name, a, b, r0, r1, mat, seg=10):
    return B.tube(name, [a, ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2), b], [r0, (r0 + r1) / 2, r1], mat, seg=seg)


def legs(B, mats, hip_w=0.12, thigh=(0.1, 0.085), shin=(0.09, 0.075), boot="rubber", pelvis_z=0.8, stance=0.05, bulk=1.0):
    for sx in (1, -1):
        hx = hip_w * sx
        knee = (hx + stance * sx * 0.5, -0.03, pelvis_z * 0.52)
        ankle = (hx + stance * sx, 0.0, 0.1)
        limb(B, "thigh%d" % sx, (hx, 0, pelvis_z - 0.02), knee, thigh[0] * bulk, thigh[1] * bulk, M(mats[0]))
        limb(B, "shin%d" % sx, knee, ankle, shin[0] * bulk, shin[1] * bulk, M(mats[1]))
        B.sphere("knee%d" % sx, 0.085 * bulk, (knee[0], knee[1] - 0.04, knee[2]), M(mats[2]), scale=(1, 0.8, 0.9))
        B.box("foot%d" % sx, (0.16 * bulk, 0.27 * bulk, 0.11), (ankle[0], ankle[1] - 0.06, 0.055), M(boot), bevel=0.035)


def torso(B, mat, z0, z1, w0, w1, d=0.72, name="torso"):
    secs = []
    n = 5
    for i in range(n):
        t = i / (n - 1)
        z = z0 + (z1 - z0) * t
        w = w0 + (w1 - w0) * math.sin(t * math.pi * 0.62)
        if i == n - 1:
            w *= 0.55
        secs.append(C.ellipse(0, 0.01, z, w, w * d, 14))
    return B.add(name, C.bm_loft(secs), M(mat) if isinstance(mat, str) else mat, sharp=80)


def arm(B, sx, shoulder, elbow, hand, mats, r=(0.075, 0.065), hand_r=0.07, pad=None):
    limb(B, "uarm%d" % sx, shoulder, elbow, r[0], r[1], M(mats[0]))
    limb(B, "farm%d" % sx, elbow, hand, r[1], r[1] * 1.1, M(mats[1]))
    B.sphere("hand%d" % sx, hand_r, hand, M(mats[2]), scale=(0.9, 1, 1.1))
    if pad:
        B.sphere("pad%d" % sx, pad[0], (shoulder[0] + 0.03 * sx, shoulder[1], shoulder[2] + 0.02), M(pad[1]), scale=(1.05, 1.0, 0.8))


def mask_face(B, rig, name, center, w, h, mat, eye_mat, eye_dx, eye_z, eye_r=0.03, shape="oval", depth=0.11):
    """Masque posé sur le visage (avant -Y) + yeux émissifs ; enregistre les yeux dans rig.pts."""
    cx, cy, cz = center
    bm = C.bm_sphere(18, 12, 1.0)
    for v in bm.verts:
        x, y, z = v.co
        if shape == "angular":
            # Spectre : pommettes saillantes, menton en pointe, front en V.
            if z < 0:
                x *= 1.0 - 0.7 * (-z) ** 1.2
                z *= 1.0 + 0.5 * (-z)
            else:
                x *= 1.0 + 0.15 * z
        elif shape == "skull":
            if z < -0.2:
                x *= 0.75
        elif shape == "helm":
            z *= 1.0 if z > 0 else 0.8
            x *= 1.08
        if y > 0:
            y *= 0.3
        v.co = Vector((x * w, y * depth, z * h))
    C.bm_xform(bm, loc=(cx, cy, cz))
    B.add(name, bm, M(mat) if isinstance(mat, str) else mat, sharp=60)
    for i, sx in enumerate((-1, 1)):
        ex, ey, ez = cx + eye_dx * sx, cy - depth * 0.92, cz + eye_z
        B.sphere("%s_eye%d" % (name, i), eye_r, (ex, ey, ez), M(eye_mat), scale=(1.5, 0.5, 0.75), outline=False, shadow=False)
        rig.pts["eye%d" % i] = (ex, ey - 0.01, ez)


# ----------------------------------------------------------------------------- ennemis

def space_soldier(B) -> dict:
    rig = Rig(B)
    legs(B, ("navy", "navy", "steel"), boot="gunmetal", stance=0.06)
    B.sphere("hips", 1.0, (0, 0, 0.8), M("navy"), scale=(0.21, 0.16, 0.13))
    B.box("belt", (0.44, 0.33, 0.07), (0, 0, 0.84), M("gunmetal"), bevel=0.02)
    B.box("buckle", (0.09, 0.03, 0.06), (0, -0.17, 0.84), M("screen_cyan"), outline=False)
    torso(B, "cloth_grey", 0.86, 1.36, 0.19, 0.25)
    B.box("chest", (0.42, 0.18, 0.28), (0, -0.1, 1.15), M("steel"), bevel=0.05)
    B.box("chestlight", (0.12, 0.02, 0.04), (-0.08, -0.2, 1.2), M("screen_cyan"), outline=False)
    B.box("pack", (0.38, 0.22, 0.42), (0, 0.2, 1.12), M("gunmetal"), bevel=0.05)
    for sx in (-1, 1):
        B.cyl("tank%d" % sx, 0.07, 0.07, 0.4, (sx * 0.13, 0.3, 1.12), M("white_panel"), seg=10)
    # Bras : fusil plasma tenu en travers.
    arm(B, 1, (0.27, 0, 1.3), (0.33, -0.12, 1.08), (0.16, -0.3, 1.02), ("navy", "cloth_grey", "gunmetal"), pad=(0.12, "steel"))
    arm(B, -1, (-0.27, 0, 1.3), (-0.3, -0.15, 1.08), (-0.08, -0.34, 1.1), ("navy", "cloth_grey", "gunmetal"), pad=(0.12, "steel"))
    rifle = [("stock", (0.12, 0.1, 0.1), (0.28, -0.26, 1.02)), ("body", (0.5, 0.12, 0.13), (0.02, -0.32, 1.06)),
             ("barrel", (0.36, 0.06, 0.06), (-0.4, -0.36, 1.1))]
    for n, s, l in rifle:
        B.box("rifle_" + n, s, l, M("steel_dark"), rot=(0, 0, 0.35), bevel=0.015)
    B.box("rifle_cell", (0.16, 0.02, 0.05), (0.02, -0.4, 1.08), M("screen_cyan"), rot=(0, 0, 0.35), outline=False)
    # Casque + masque de spectre argenté.
    B.sphere("helmet", 1.0, (0, 0.02, 1.62), M("steel_dark"), scale=(0.25, 0.25, 0.25))
    B.cyl("collar", 0.17, 0.2, 0.1, (0, 0.01, 1.4), M("gunmetal"), seg=16)
    mask_face(B, rig, "mask", (0, -0.2, 1.6), 0.2, 0.22, custom("silver_mask", "#dce4ee"), "eye_cyan", 0.075, 0.03, shape="angular")
    for sx in (-1, 1):  # ailerons du masque
        B.tube("fin%d" % sx, [(sx * 0.16, -0.06, 1.72), (sx * 0.27, 0.0, 1.85), (sx * 0.3, 0.05, 1.95)], [0.035, 0.025, 0.004],
               M("white_panel"))
    rig.pts["top"] = (0, 0, 1.92)
    return rig.finish()


def space_android(B) -> dict:
    rig = Rig(B)
    legs(B, ("white_panel", "white_panel", "gunmetal"), thigh=(0.075, 0.06), shin=(0.065, 0.05), boot="gunmetal", stance=0.09, hip_w=0.1)
    B.sphere("hips", 1.0, (0, 0, 0.8), M("gunmetal"), scale=(0.16, 0.12, 0.1))
    B.cyl("waist", 0.08, 0.1, 0.18, (0, 0, 0.93), M("gunmetal"), seg=12)
    torso(B, "white_panel", 1.0, 1.4, 0.15, 0.22, d=0.65)
    B.box("core", (0.1, 0.03, 0.1), (0, -0.15, 1.22), M("eye_violet"), outline=False)
    for k in range(3):
        B.box("rib%d" % k, (0.3 - k * 0.05, 0.05, 0.025), (0, -0.1, 1.1 - k * 0.05), M("gunmetal"))
    # Bras fins, lames violettes aux avant-bras (marionnette prête à frapper).
    for sx in (1, -1):
        sh = (0.23 * sx, 0, 1.33)
        el = (0.33 * sx, -0.05, 1.1)
        ha = (0.36 * sx, -0.2, 0.93) if sx > 0 else (0.28 * sx, -0.28, 1.18)
        arm(B, sx, sh, el, ha, ("white_panel", "white_panel", "gunmetal"), r=(0.055, 0.045), hand_r=0.055)
        B.sphere("joint%d" % sx, 0.06, el, M("gunmetal"))
        B.sphere("sjoint%d" % sx, 0.075, sh, M("gunmetal"))
        tip = (ha[0] + 0.05 * sx, ha[1] - 0.22, ha[2] - 0.12) if sx > 0 else (ha[0] - 0.05, ha[1] - 0.18, ha[2] + 0.22)
        B.tube("blade%d" % sx, [ha, tip], [0.035, 0.004], M("eye_violet"), seg=6)
        # Fils de marionnette qui montent hors du cadre.
        B.tube("string%d" % sx, [ha, (ha[0] * 1.2, ha[1] + 0.1, 2.6)], [0.006, 0.006], custom("string", "#d8d0e8", 0.0), seg=4, shadow=False)
    B.cyl("neck", 0.045, 0.05, 0.12, (0, 0, 1.44), M("gunmetal"), seg=10)
    B.sphere("head", 1.0, (0, 0.03, 1.6), M("gunmetal"), scale=(0.18, 0.18, 0.2))
    mask_face(B, rig, "mask", (0, -0.1, 1.6), 0.17, 0.21, "bone", "eye_violet", 0.07, 0.03, shape="skull")
    B.tube("crack", [(0.04, -0.21, 1.75), (0.06, -0.22, 1.66), (0.03, -0.215, 1.58)], [0.006] * 3, M("rubber"), seg=4, shadow=False)
    B.tube("string_h", [(0, 0.02, 1.8), (0.02, 0.05, 2.6)], [0.006, 0.006], custom("string", "#d8d0e8", 0.0), seg=4, shadow=False)
    B.box("crossbar", (0.6, 0.04, 0.04), (0.05, 0.05, 2.55), M("rubber"))
    rig.pts["top"] = (0, 0, 1.85)
    return rig.finish()


def space_brute(B) -> dict:
    rig = Rig(B)
    legs(B, ("navy", "rubber", "hazard"), hip_w=0.17, thigh=(0.14, 0.12), shin=(0.13, 0.11), boot="gunmetal", stance=0.12, bulk=1.15)
    for sx in (-1, 1):  # vérins de l'exosquelette
        B.cyl("piston%d" % sx, 0.035, 0.035, 0.6, (sx * 0.3, -0.05, 0.45), M("steel"), seg=8)
        B.box("thighplate%d" % sx, (0.2, 0.16, 0.3), (sx * 0.2, -0.08, 0.62), M("orange"), bevel=0.04)
    B.sphere("hips", 1.0, (0, 0, 0.82), M("gunmetal"), scale=(0.3, 0.22, 0.16))
    torso(B, "rubber", 0.9, 1.5, 0.3, 0.38, d=0.75)
    B.box("chestplate", (0.66, 0.26, 0.38), (0, -0.14, 1.25), M("orange"), bevel=0.07)
    B.box("hz", (0.5, 0.02, 0.06), (0, -0.28, 1.1), M("hazard", rim=0.0), outline=False)
    B.box("frame", (0.62, 0.22, 0.5), (0, 0.24, 1.25), M("gunmetal"), bevel=0.05)
    for sx in (-1, 1):
        B.cyl("exhaust%d" % sx, 0.06, 0.07, 0.35, (sx * 0.2, 0.33, 1.55), M("steel_dark"), seg=10)
        B.cyl("glow%d" % sx, 0.045, 0.045, 0.02, (sx * 0.2, 0.33, 1.73), M("plasma"), seg=10, outline=False)
    # Bras massifs, poings d'acier (coup au sol).
    for sx in (1, -1):
        sh = (0.42 * sx, 0, 1.42)
        el = (0.55 * sx, -0.05, 1.1)
        ha = (0.5 * sx, -0.16, 0.82)
        arm(B, sx, sh, el, ha, ("rubber", "orange", "steel_dark"), r=(0.12, 0.13), hand_r=0.16, pad=(0.2, "orange"))
        B.box("knuckle%d" % sx, (0.26, 0.12, 0.08), (ha[0], ha[1] - 0.12, ha[2] + 0.02), M("steel"), bevel=0.02)
    B.sphere("head", 1.0, (0, -0.02, 1.74), M("gunmetal"), scale=(0.2, 0.2, 0.2))
    mask_face(B, rig, "mask", (0, -0.17, 1.72), 0.2, 0.2, custom("gold_mask", "#d8a640"), "eye_cyan", 0.08, 0.02, shape="helm")
    B.box("crest", (0.06, 0.28, 0.12), (0, -0.02, 1.88), M("brass"), bevel=0.02)
    rig.pts["top"] = (0, 0, 1.95)
    return rig.finish()


def space_drone(B) -> dict:
    rig = Rig(B)
    z = 1.0
    B.sphere("shell", 0.36, (0, 0, z), M("gunmetal"), scale=(1, 1, 0.9), seg=20, rings=12)
    B.torus("band", 0.36, 0.045, (0, 0, z), M("gunmetal"), seg=24, rseg=6)
    mask_face(B, rig, "mask", (0, -0.27, z + 0.03), 0.26, 0.28, "mask", "eye_red", 0.09, 0.05, eye_r=0.035, shape="oval", depth=0.12)
    for k, sx in enumerate((-1, 1)):  # marques rouges du masque (kitsune de sécurité)
        B.tube("mark%d" % k, [(sx * 0.12, -0.355, z - 0.04), (sx * 0.17, -0.34, z - 0.1)], [0.012, 0.006], M("red"), seg=5, shadow=False)
    for sx in (-1, 1):
        B.box("fin%d" % sx, (0.28, 0.08, 0.18), (sx * 0.42, 0.05, z), M("steel_dark"), rot=(0, sx * 0.3, 0), bevel=0.02)
        B.cyl("thr%d" % sx, 0.07, 0.05, 0.12, (sx * 0.52, 0.05, z - 0.1), M("gunmetal"), seg=10)
        B.cyl("thrglow%d" % sx, 0.045, 0.045, 0.02, (sx * 0.52, 0.05, z - 0.17), M("core_cyan"), seg=10, outline=False)
    B.cyl("antenna", 0.012, 0.012, 0.25, (0.12, 0.05, z + 0.42), M("steel"), seg=6)
    B.sphere("antenna_tip", 0.025, (0.12, 0.05, z + 0.55), M("alarm_red"), outline=False)
    B.cyl("emitter", 0.07, 0.04, 0.16, (0, -0.08, z - 0.36), M("gunmetal"), seg=10)
    B.sphere("lens", 0.04, (0, -0.1, z - 0.45), M("eye_red"), outline=False)
    # Faisceau de sustentation (lueur) vers le sol.
    B.cyl("hover", 0.09, 0.02, 0.3, (0, 0, 0.42), custom("hover", "#7ae8ff", 0.0), seg=12, outline=False, shadow=False)
    rig.pts["top"] = (0, 0, z + 0.55)
    return rig.finish()


def space_reactor_colossus(B) -> dict:
    rig = Rig(B)
    legs(B, ("gunmetal", "steel_dark", "steel"), hip_w=0.26, thigh=(0.2, 0.17), shin=(0.19, 0.16), boot="gunmetal", stance=0.18,
         pelvis_z=1.05, bulk=1.25)
    B.sphere("hips", 1.0, (0, 0, 1.08), M("gunmetal"), scale=(0.42, 0.3, 0.2))
    torso(B, "steel_dark", 1.15, 2.15, 0.45, 0.6, d=0.7)
    # Cœur de réacteur dans la poitrine.
    B.cyl("core_ring", 0.24, 0.24, 0.14, (0, -0.36, 1.7), M("gunmetal"), rot=(math.pi / 2, 0, 0), seg=24)
    B.sphere("core", 0.18, (0, -0.42, 1.7), M("core_cyan"), scale=(1, 0.6, 1), outline=False)
    for k in range(6):
        a = k * math.pi / 3
        B.box("cplate%d" % k, (0.22, 0.12, 0.08), (math.cos(a) * 0.36, -0.32, 1.7 + math.sin(a) * 0.36), M("steel"),
              rot=(0, -a, 0), bevel=0.02)
    B.box("collar", (0.9, 0.5, 0.2), (0, 0.0, 2.12), M("gunmetal"), bevel=0.06)
    for sx in (-1, 1):  # tuyaux du dos vers les épaules
        B.tube("pipe%d" % sx, [(sx * 0.25, 0.3, 2.2), (sx * 0.45, 0.5, 2.5), (sx * 0.65, 0.3, 2.25)], [0.07, 0.07, 0.07], M("copper"))
        B.cyl("stack%d" % sx, 0.1, 0.12, 0.5, (sx * 0.3, 0.42, 2.35), M("steel_dark"), seg=12)
        B.cyl("stackglow%d" % sx, 0.07, 0.07, 0.02, (sx * 0.3, 0.42, 2.61), M("core_cyan"), seg=10, outline=False)
    for sx in (1, -1):
        sh = (0.68 * sx, 0, 2.0)
        el = (0.85 * sx, -0.1, 1.55)
        ha = (0.78 * sx, -0.3, 1.15)
        arm(B, sx, sh, el, ha, ("gunmetal", "steel", "steel_dark"), r=(0.17, 0.19), hand_r=0.24, pad=(0.32, "steel_dark"))
        B.torus("armglow%d" % sx, 0.2, 0.03, (el[0], el[1], el[2] - 0.12), M("core_cyan"), seg=20, rseg=5, outline=False)
        for k in range(3):
            B.box("claw%d%d" % (sx, k), (0.07, 0.07, 0.2), (ha[0] + (k - 1) * 0.1, ha[1] - 0.15, ha[2] - 0.2), M("steel"), bevel=0.02)
    B.sphere("head", 1.0, (0, -0.08, 2.35), M("gunmetal"), scale=(0.24, 0.24, 0.24))
    mask_face(B, rig, "mask", (0, -0.25, 2.33), 0.23, 0.25, custom("iron_mask", "#9aa6bc"), "eye_cyan", 0.09, 0.04, shape="angular",
              eye_r=0.035)
    B.tube("crest", [(0, -0.2, 2.5), (0, -0.05, 2.7), (0, 0.15, 2.75)], [0.07, 0.05, 0.01], M("brass"), seg=6)
    for sx in (-1, 1):
        B.tube("horn%d" % sx, [(sx * 0.18, -0.12, 2.5), (sx * 0.32, -0.1, 2.68), (sx * 0.36, -0.05, 2.85)], [0.05, 0.035, 0.005], M("brass"))
    rig.pts["top"] = (0, 0, 2.9)
    return rig.finish()


# Agrandissement (taille à l'écran visée / taille du modèle à 36 u/BU) : rendu à 2 px × k par unité.
SCALE_K = {"space_drone": 1.3, "space_soldier": 1.48, "space_android": 1.48, "space_brute": 1.85, "space_reactor_colossus": 1.85}

ENEMIES = {
    # kind : (fonction, cadre monde (l, h), cible z, contour, ombre au sol, débris, aura)
    "space_drone": (space_drone, (64, 80), 0.9, 3.5, 16.0, ["#e8e4dc", "#3a3e4e", "#ff3020"], "#ff3a28"),
    "space_soldier": (space_soldier, (70, 90), 1.0, 4.0, 19.0, ["#2e3a5e", "#c8d0dc", "#46c4f0"], "#60f0ff"),
    "space_android": (space_android, (70, 110), 1.2, 3.8, 17.0, ["#c4ccd8", "#e2d8c4", "#c070ff"], "#c070ff"),
    "space_brute": (space_brute, (100, 100), 1.0, 4.5, 30.0, ["#d8742c", "#2a2a32", "#d8a640"], "#ffb040"),
    "space_reactor_colossus": (space_reactor_colossus, (150, 150), 1.5, 5.5, 46.0, ["#4a5064", "#7af0ff", "#c8a040", "#5a6278"], "#60f0ff"),
}


def main() -> None:
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    meta_path = os.path.join(TMP, "enemies.json")
    meta = {}
    if os.path.exists(meta_path):
        with open(meta_path) as f:
            meta = json.load(f)
    for k, (fn, fr, tz, ol, shadow_r, debris, aura) in ENEMIES.items():
        if only and k not in only:
            continue
        kk = SCALE_K.get(k, 1.0)
        info = render_sprite(k, fn, fr, PXW * kk, os.path.join(OUT, k + ".png"), target_z=tz, outline_px=ol * kk, shadow=False,
                             feet_margin=3, samples=4)
        info["shadow"] = shadow_r * kk
        info["debris"] = debris
        info["aura"] = aura
        meta[k] = info
    os.makedirs(OUT, exist_ok=True)
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=1)
    write_kinds(meta)
    print("ENEMIES OK", list(meta))


NAMES = {"space_drone": "Drone de sécurité masqué", "space_soldier": "Soldat au masque de spectre",
         "space_android": "Androïde marionnette", "space_brute": "Brute en exosquelette",
         "space_reactor_colossus": "Colosse du réacteur (boss)"}
EYE_R = {"space_drone": 4.0, "space_soldier": 3.6, "space_android": 3.4, "space_brute": 4.2, "space_reactor_colossus": 5.4}


def _col(h: str) -> str:
    h = h.lstrip("#")
    return "Color(%.2f, %.2f, %.2f)" % tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def write_kinds(meta: dict) -> None:
    """Écrit scripts/biomes/space_station/enemy_kinds.gd (format EnemyVisual.KINDS)."""
    out = ["extends RefCounted",
           "## Visuels des ennemis de la Station Orbitale Kagami (format EnemyVisual.KINDS), chargés par",
           "## BiomeRegistry. Généré par art/blender/space_station/build_enemies.py : NE PAS ÉDITER.",
           "## PNG en vue 3/4 de face ; scale = 0,5 unité monde par px ; pieds/yeux en px du PNG.", "",
           'const DIR := "res://assets/sprites/space_station/enemies/"', "", "const KINDS := {"]
    for k in ENEMIES:
        if k not in meta:
            continue
        e = meta[k]
        W, H = e["size"]
        fx, fy = e["feet"]
        head = -((fy - e["top"][1]) * 0.5 + 6)
        out += ["\t# " + NAMES[k], '\t&"%s": {' % k, '\t\t"path": DIR + "%s.png",' % k,
                '\t\t"svg_size": Vector2(%d, %d), "feet": Vector2(%.1f, %.1f), "scale": 0.5,' % (W, H, fx, fy),
                '\t\t"head": Vector2(0, %d), "shadow": %.1f,' % (round(head), e["shadow"]),
                '\t\t"eyes": [Vector2(%.1f, %.1f), Vector2(%.1f, %.1f)], "eye_r": %.1f,' % (*e["eye0"], *e["eye1"], EYE_R[k]),
                '\t\t"aura": %s,' % _col(e["aura"]),
                '\t\t"debris": [%s],' % ", ".join(_col(c) for c in e["debris"]), "\t},"]
    out.append("}")
    with open(os.path.join(ROOT, "scripts", "biomes", "space_station", "enemy_kinds.gd"), "w") as f:
        f.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
