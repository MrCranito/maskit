"""Héros kitsune (Les Royaumes des Masques) : modélisation 3D scriptée + rendus 8 directions.

Usage (depuis la racine du projet) :
    python3 art/blender/build_hero.py                 # tout : rendus + planches + .tres + meta
    python3 art/blender/build_hero.py --preview s,se  # quelques images de contrôle (scratch)
    python3 art/blender/build_hero.py --blend         # sauve seulement art/blender/hero.blend

Le personnage est construit en pièces rigides parentées à des « articulations » (empties),
animées par transformations (idle : respiration ; run : cycle de 8 images). L'écharpe et les
mèches sont régénérées à chaque image (forme procédurale qui ondule).
Le personnage regarde -Y ; la caméra orthographique regarde depuis -Y, plongée ELEV degrés.
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "hero3d")
TMP_DIR = os.environ.get("RDM_TMP", "/tmp/rdm_hero_frames")

FRAME = 160                 # taille du cadre final (px)
SS = 2                      # sur-échantillonnage du rendu (rendu 320 puis réduction)
ELEV = 48.0                 # plongée caméra (degrés)
ORTHO = 2.30                # largeur visible (unités Blender) pour le cadre
CAM_TARGET_Z = 1.10
HEAD_SCALE = 1.22
HERO_WORLD_HEIGHT = 64.0      # hauteur visible voulue du héros en unités monde (~70 px au zoom 1.1)
IDLE_N = 6
CLOSE = False
RUN_N = 8
FPS = {"idle": 8, "run": 12}
# Directions : angle de rotation du personnage autour de Z (0 = face caméra = "s").
DIRS = {"e": 90.0, "se": 45.0, "s": 0.0, "sw": -45.0, "w": -90.0, "nw": -135.0, "n": 180.0, "ne": 135.0}

# ----------------------------------------------------------------------------- palette
PAL = {
    "mask": ("#f4ede2", "#9a9ab8", "#fffaf2"),
    "mask_red": ("#c8202a", None, "#e0303a"),
    "eye_hole": ("#2a0c12", None, None),
    "hood": ("#a3202a", "#4a1030", "#d0383a"),
    "hair": ("#7a1622", "#3a0c22", "#a8262e"),
    "horn": ("#d02a2c", "#5a1028", "#ff5a48"),
    "feather": ("#d9d4d2", "#6a6c90", "#ffffff"),
    "scarf": ("#c0222c", "#521030", "#ec4a3e"),
    "armor": ("#4a4a5c", "#1c1e38", "#7a7488"),
    "leather": ("#3b2a2a", "#161226", "#5e4236"),
    "cloth": ("#34303e", "#14142a", "#524858"),
    "trim": ("#c0242c", "#4e0e26", "#e8423e"),
    "cream": ("#e8dcc2", "#8a8aa6", "#fff6e0"),
    "gold": ("#d6a640", "#6a4a3a", "#ffe08a"),
    "boot": ("#3a2a26", "#120e20", "#5e4238"),
}


def M(key: str, rim: float = 0.30):
    b, s, l = PAL[key]
    return C.toon(key, b, s, l, rim=rim)


def joint(name: str, parent, loc) -> bpy.types.Object:
    e = C.empty(name, loc, parent)
    e.rotation_mode = "XYZ"
    return e


class Hero:
    def __init__(self) -> None:
        self.j: dict[str, bpy.types.Object] = {}
        self.dyn: list[bpy.types.Object] = []
        self.build()

    # ------------------------------------------------------------------ construction
    def part(self, name, bm, mat, parent, smooth=True):
        ob = C.mesh_obj(name, bm, mat, smooth=smooth)
        ob.parent = parent
        return ob

    def build(self) -> None:
        j = self.j
        nofs = C.nofs_collection()
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["pelvis"] = pelvis = joint("pelvis", root, (0, 0, 0.80))
        j["spine"] = spine = joint("spine", pelvis, (0, 0, 0.08))
        j["neck"] = neck = joint("neck", spine, (0, 0, 0.47))
        j["head"] = head = joint("head", neck, (0, 0, 0.0))
        head.scale = (HEAD_SCALE,) * 3

        # --- jambes ---------------------------------------------------------
        for side, sx in (("L", 1), ("R", -1)):
            hip = j["hip" + side] = joint("hip" + side, pelvis, (0.115 * sx, 0, -0.02))
            knee = j["knee" + side] = joint("knee" + side, hip, (0, 0, -0.36))
            self.part("thigh" + side, C.bm_xform(C.bm_cyl(10, 0.095, 0.080, 0.36),
                      loc=(0, 0, -0.18)), M("cloth"), hip)
            # genouillère
            self.part("kneepad" + side, C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0, -0.045, 0.0),
                      scale=(0.075, 0.05, 0.07)), M("armor"), knee)
            # botte : tige + revers rouge + pied
            self.part("shin" + side, C.bm_xform(C.bm_cyl(10, 0.100, 0.078, 0.30),
                      loc=(0, 0, -0.20)), M("boot"), knee)
            self.part("cuff" + side, C.bm_xform(C.bm_cyl(10, 0.082, 0.098, 0.05),
                      loc=(0, 0, -0.07)), M("trim"), knee)
            foot = C.bm_xform(C.bm_box(0.15, 0.25, 0.10, bevel=0.035), loc=(0, -0.055, -0.355))
            self.part("foot" + side, foot, M("boot"), knee)

        # --- bassin, ceinture, sash, tabard -------------------------------
        self.part("hips", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, 0, -0.02),
                  scale=(0.20, 0.15, 0.13)), M("cloth"), pelvis)
        self.part("sash", C.bm_xform(C.bm_cyl(14, 0.205, 0.19, 0.12), loc=(0, 0, 0.06),
                  scale=(1, 0.80, 1)), M("trim"), pelvis)
        self.part("belt", C.bm_xform(C.bm_cyl(14, 0.212, 0.212, 0.04), loc=(0, 0, 0.03),
                  scale=(1, 0.80, 1)), M("leather"), pelvis)
        self.part("buckle", C.bm_xform(C.bm_box(0.075, 0.03, 0.06, bevel=0.01),
                  loc=(0, -0.172, 0.03)), M("gold"), pelvis)
        # pan de sash qui pend sur la hanche
        sash_tail = C.bm_tube(C.bezier((0.13, -0.13, 0.04), (0.17, -0.15, -0.06),
                                       (0.17, -0.15, -0.16), (0.15, -0.13, -0.26), 5),
                              [0.05, 0.05, 0.048, 0.045, 0.04], seg=6, flat=0.30)
        self.part("sash_tail", sash_tail, M("trim"), pelvis)
        # tabard crème (devant) : articulé pour suivre les jambes
        tf = j["tabF"] = joint("tabF", pelvis, (0, -0.135, 0.0))
        tab = C.bm_loft([
            [(-0.115, -0.010, 0.0), (0.115, -0.010, 0.0), (0.115, 0.012, 0.0), (-0.115, 0.012, 0.0)],
            [(-0.135, -0.040, -0.22), (0.135, -0.040, -0.22), (0.135, -0.018, -0.22), (-0.135, -0.018, -0.22)],
            [(-0.145, -0.060, -0.40), (0.145, -0.060, -0.40), (0.145, -0.038, -0.40), (-0.145, -0.038, -0.40)],
        ])
        self.tabF = self.part("tabardF", tab, M("cream"), tf, smooth=False)
        # motifs rouges du tabard : bordure basse + chevron + losange (décalques plats)
        self.tabard_pattern(tf)
        tb = j["tabB"] = joint("tabB", pelvis, (0, 0.13, 0.0))
        tabb = C.bm_loft([
            [(-0.13, -0.012, 0.0), (0.13, -0.012, 0.0), (0.13, 0.010, 0.0), (-0.13, 0.010, 0.0)],
            [(-0.15, 0.030, -0.34), (0.15, 0.030, -0.34), (0.15, 0.052, -0.34), (-0.15, 0.052, -0.34)],
        ])
        self.part("tabardB", tabb, M("hood"), tb, smooth=False)
        # tassettes latérales sombres
        for side, sx in (("L", 1), ("R", -1)):
            ts = j["tas" + side] = joint("tas" + side, pelvis, (0.17 * sx, -0.02, 0.0))
            tas = C.bm_xform(C.bm_box(0.05, 0.17, 0.22, bevel=0.02), loc=(0.012 * sx, 0, -0.11),
                             rot=(0, 0.20 * sx, 0))
            self.part("tasset" + side, tas, M("armor"), ts)

        # --- torse --------------------------------------------------------
        torso = C.bm_loft([
            C.ellipse(0, 0, 0.00, 0.175, 0.135, 12),
            C.ellipse(0, 0.005, 0.15, 0.195, 0.145, 12),
            C.ellipse(0, 0.010, 0.29, 0.225, 0.155, 12),
            C.ellipse(0, 0.015, 0.39, 0.200, 0.140, 12),
            C.ellipse(0, 0.015, 0.45, 0.110, 0.095, 12),
        ])
        self.part("torso", torso, M("cloth"), spine)
        # plastron crème + liseré rouge (bande sous la poitrine)
        self.part("chest", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, -0.085, 0.27),
                  scale=(0.165, 0.085, 0.12)), M("cream"), spine)
        self.part("chestband", C.bm_xform(C.bm_cyl(14, 0.20, 0.205, 0.045), loc=(0, 0.004, 0.155),
                  scale=(1, 0.76, 1)), M("trim"), spine)
        self.part("strap", C.bm_xform(C.bm_box(0.055, 0.03, 0.40, bevel=0.01), loc=(0.02, -0.15, 0.22),
                  rot=(0.0, 0.62, 0.0)), M("leather"), spine)
        # col / capeline rouge (écharpe enroulée)
        self.part("cowl", C.bm_xform(C.bm_cyl(16, 0.26, 0.14, 0.17), loc=(0, 0.015, 0.40),
                  scale=(1, 0.86, 1)), M("scarf"), spine)
        collar = C.bm_xform(C.bm_torus(18, 8, 0.14, 0.06), loc=(0, 0.02, 0.45), scale=(1, 0.92, 1))
        self.part("collar", collar, M("scarf"), spine)
        # pan d'écharpe qui tombe devant sur l'épaule gauche (repère : x+)
        drape = C.bm_tube(C.bezier((0.12, -0.13, 0.44), (0.17, -0.18, 0.36),
                                   (0.19, -0.19, 0.22), (0.19, -0.16, 0.06), 6),
                          [0.075, 0.08, 0.085, 0.085, 0.08, 0.07], seg=8, flat=0.35)
        self.part("drape", drape, M("scarf"), spine)

        # --- bras ----------------------------------------------------------
        for side, sx in (("L", 1), ("R", -1)):
            sh = j["sh" + side] = joint("sh" + side, spine, (0.255 * sx, 0.0, 0.34))
            el = j["el" + side] = joint("el" + side, sh, (0, 0, -0.22))
            self.part("uarm" + side, C.bm_xform(C.bm_cyl(10, 0.075, 0.064, 0.24),
                      loc=(0, 0, -0.10)), M("cloth"), sh)
            # spalière : coque arrondie + liseré rouge
            pad = C.bm_sphere(16, 10, 1.0)
            for v in pad.verts:
                if v.co.z < -0.15:
                    v.co.z = -0.15 + (v.co.z + 0.15) * 0.15
            pad = C.bm_xform(pad, loc=(0.045 * sx, 0, -0.01), rot=(0, 0.35 * sx, 0),
                             scale=(0.14, 0.135, 0.11))
            self.part("pad" + side, pad, M("armor"), sh)
            rim = C.bm_xform(C.bm_torus(16, 6, 0.122, 0.022), loc=(0.045 * sx, 0, -0.035),
                             rot=(0, 0.30 * sx, 0), scale=(1, 1.02, 1))
            self.part("padrim" + side, rim, M("trim"), sh)
            self.part("elbow" + side, C.bm_xform(C.bm_sphere(8, 6, 0.062), loc=(0, 0.01, 0)),
                      M("armor"), el)
            self.part("gaunt" + side, C.bm_xform(C.bm_cyl(10, 0.058, 0.080, 0.18), loc=(0, 0, -0.10)),
                      M("armor"), el)
            self.part("gcuff" + side, C.bm_xform(C.bm_cyl(10, 0.084, 0.084, 0.035), loc=(0, 0, -0.18)),
                      M("trim"), el)
            hand = C.bm_xform(C.bm_sphere(10, 7, 1.0), loc=(0, -0.005, -0.245), scale=(0.062, 0.070, 0.075))
            self.part("hand" + side, hand, M("leather"), el)

        # --- tête ------------------------------------------------------------
        # cheveux rouge sombre (masse arrière) + capuche/cowl rouge basse qui retombe sur la nuque
        hair = C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, 0.07, 0.25), scale=(0.215, 0.21, 0.225))
        self.part("hairmass", hair, M("hair"), head)
        hood = C.bm_loft([
            C.ellipse(0, 0.10, 0.02, 0.215, 0.17, 14),
            C.ellipse(0, 0.12, 0.16, 0.235, 0.20, 14),
            C.ellipse(0, 0.12, 0.30, 0.235, 0.21, 14),
            C.ellipse(0, 0.11, 0.41, 0.20, 0.18, 14),
            C.ellipse(0, 0.10, 0.48, 0.12, 0.11, 14),
        ])
        # ouvre l'avant : écrase les points avant de la capuche vers l'arrière
        for v in hood.verts:
            # ouverture du visage en bas/devant ; le haut de la capuche avance au-dessus du front
            if v.co.y < 0.06:
                if v.co.z < 0.40:
                    v.co.y = 0.06 + (v.co.y - 0.06) * 0.25
                else:
                    v.co.y -= 0.03
        self.part("hood", hood, M("hood"), head)
        self.mask = self.build_mask(head)
        self.mask_details(nofs)
        # deux grandes cornes/oreilles rouges dressées + une petite, plumes claires latérales
        horns = [
            ((0.09, 0.05, 0.40), (0.12, 0.03, 0.55), (0.15, 0.06, 0.66), (0.20, 0.12, 0.75), 0.090),
            ((0.17, 0.09, 0.34), (0.23, 0.10, 0.41), (0.27, 0.13, 0.45), (0.30, 0.17, 0.47), 0.045),
        ]
        for sx in (1, -1):
            for (a, b, c, d, r) in horns:
                pts = C.bezier((a[0] * sx, a[1], a[2]), (b[0] * sx, b[1], b[2]),
                               (c[0] * sx, c[1], c[2]), (d[0] * sx, d[1], d[2]), 7)
                rr = [r * (1.0 - 0.97 * (i / 6) ** 1.1) for i in range(7)]
                self.part("horn", C.bm_tube(pts, rr, seg=8, flat=0.38, up=(0, 1, 0)), M("horn"), head)
            pts = C.bezier((0.19 * sx, 0.10, 0.30), (0.28 * sx, 0.13, 0.33),
                           (0.35 * sx, 0.17, 0.37), (0.41 * sx, 0.21, 0.42), 6)
            rr = [0.030, 0.036, 0.034, 0.026, 0.016, 0.003]
            self.part("feather", C.bm_tube(pts, rr, seg=6, flat=0.30, up=(0, 0, 1)), M("feather"), head)

    def tabard_pattern(self, tf) -> None:
        nofs = C.nofs_collection()
        red = M("trim", rim=0.0)

        def quad(pts):
            # pts en (x, z) sur le plan avant du tabard (y interpolé sur la pente)
            out = []
            for (x, z) in pts:
                y = -0.010 + (-0.050) * (-z / 0.40) - 0.006
                out.append((x, y, z))
            bm = bmesh_new_poly(out)
            ob = C.mesh_obj("tabmotif", bm, red, smooth=False, coll=nofs)
            ob.parent = tf
            return ob
        quad([(-0.140, -0.33), (0.140, -0.33), (0.145, -0.39), (-0.145, -0.39)])
        quad([(-0.10, -0.12), (0.0, -0.20), (0.10, -0.12), (0.10, -0.08), (0.0, -0.16), (-0.10, -0.08)])
        quad([(0.0, -0.21), (0.04, -0.255), (0.0, -0.30), (-0.04, -0.255)])

    def build_mask(self, head) -> bpy.types.Object:
        """Masque kitsune : ellipsoïde allongé, menton pointu, museau marqué."""
        bm = C.bm_sphere(20, 16, 1.0)
        for v in bm.verts:
            x, y, z = v.co
            if z < 0.0:
                k = -z  # 0..1
                x *= 1.0 - 0.80 * k ** 1.1      # menton qui s'affine en pointe
                z *= 1.0 + 1.25 * k ** 1.4      # et s'allonge
                y *= 1.0 - 0.45 * k
            else:
                x *= 1.0 - 0.18 * z ** 2        # front légèrement resserré
                z *= 0.82
            # museau : avant central poussé vers l'avant
            if y < 0.0:
                front = max(0.0, -y)
                ridge = math.exp(-(x * x) / 0.08)
                y -= 0.30 * front * ridge * (0.4 + 0.6 * max(0.0, -z))
            # coque : dos très aplati (le masque est posé sur le visage)
            if y > 0.0:
                y *= 0.35
            v.co = Vector((x * 0.190, y * 0.17, z * 0.200))
        bmesh_translate(bm, (0, -0.115, 0.255))
        ob = C.mesh_obj("mask", bm, M("mask", rim=0.25), smooth=True)
        ob.parent = head
        return ob

    def mask_details(self, nofs) -> None:
        mk = self.mask
        red = M("mask_red")
        hole = M("eye_hole")
        glow = C.toon("eye_glow", "#ff2a1c", emit=1.6)
        # yeux en amande inclinés (vers le haut à l'extérieur)
        for sx in (1, -1):
            def eye(cx, cz, w, h, tilt):
                pts = []
                for i in range(12):
                    a = 2 * math.pi * i / 12
                    x = math.cos(a) * w
                    z = math.sin(a) * h * (1.0 if math.sin(a) > 0 else 0.75)
                    pts.append((cx * sx + x * math.cos(tilt) * sx - z * math.sin(tilt) * sx,
                                cz + x * math.sin(tilt) + z * math.cos(tilt)))
                return pts
            C.decal(mk, eye(0.080, 0.250, 0.090, 0.054, 0.42), red, "eyeRim", lift=0.002, coll=nofs)
            C.decal(mk, eye(0.079, 0.249, 0.074, 0.040, 0.42), hole, "eyeHole", lift=0.004, coll=nofs)
            C.decal(mk, eye(0.081, 0.249, 0.060, 0.030, 0.42), glow, "eyeGlow", lift=0.006, coll=nofs)
            # marques de joue : deux traits obliques
            for k, (cz, ln) in enumerate(((0.165, 0.070), (0.120, 0.055))):
                x0, x1 = 0.060, 0.060 + ln
                pts = [(x0 * sx, cz + 0.010), (x1 * sx, cz + 0.045), (x1 * sx, cz + 0.022), (x0 * sx, cz - 0.010)]
                if sx < 0:
                    pts.reverse()
                C.decal(mk, pts, red, "cheek%d" % k, lift=0.003, coll=nofs, subdiv=2)
        # marque du front : losange allongé + trait
        C.decal(mk, [(0.0, 0.395), (0.026, 0.345), (0.0, 0.305), (-0.026, 0.345)], red, "brow", coll=nofs)
        # bout du museau rouge et trait de bouche
        C.decal(mk, [(0.0, 0.040), (0.020, 0.010), (0.0, -0.060), (-0.020, 0.010)], red, "nose", coll=nofs)

    # ------------------------------------------------------------------ éléments dynamiques
    def clear_dyn(self) -> None:
        for ob in self.dyn:
            me = ob.data
            bpy.data.objects.remove(ob)
            bpy.data.meshes.remove(me)
        self.dyn = []

    def build_scarf(self, t: float, flow: float, amp: float) -> None:
        """Deux longs pans d'écharpe partant de la nuque. flow 0 = pend, 1 = flotte à l'horizontale."""
        spine = self.j["spine"]
        for k, (sx, ln, ph) in enumerate(((0.07, 0.62, 0.0), (-0.08, 0.50, 1.7))):
            n = 9
            pts, rr = [], []
            for i in range(n):
                s = i / (n - 1)
                ang = (0.15 + 1.25 * flow) * s ** 0.9  # 0 = vers le bas, pi/2 = vers l'arrière
                L = ln * s
                y = 0.15 + L * math.sin(ang) * 0.95
                z = 0.44 - L * math.cos(ang)
                wv = math.sin(t * 2 * math.pi + ph - s * 4.2) * amp * s
                x = sx + s * sx * 0.5 + wv
                z += math.sin(t * 2 * math.pi + ph - s * 4.2 + 1.2) * amp * 0.5 * s
                pts.append((x, y, z))
                rr.append(0.075 + 0.02 * math.sin(s * math.pi) - 0.03 * s)
            bm = C.bm_tube(pts, rr, seg=8, flat=0.22, up=(1, 0, 0))
            ob = C.mesh_obj("scarfTail%d" % k, bm, M("scarf"))
            ob.parent = spine
            self.dyn.append(ob)
        # mèches de cheveux sur les côtés
        head = self.j["head"]
        for sx in (1, -1):
            for k, (dx, ln) in enumerate(((0.0, 0.30), (0.04, 0.24))):
                sway = math.sin(t * 2 * math.pi + k) * 0.02 * (1 + amp * 6)
                pts = C.bezier((0.18 * sx, 0.12 + dx, 0.30), (0.25 * sx, 0.16 + dx, 0.14),
                               ((0.27 + 0.03 * flow) * sx, 0.20 + dx + 0.10 * flow, 0.02),
                               ((0.25 + 0.05 * flow) * sx + sway, 0.22 + dx + 0.22 * flow, 0.30 - ln - 0.02 * k + 0.12 * flow), 6)
                rr = [0.06, 0.058, 0.05, 0.04, 0.025, 0.006]
                ob = C.mesh_obj("hair", C.bm_tube(pts, rr, seg=7, flat=0.5), M("hair"))
                ob.parent = head
                self.dyn.append(ob)

    # ------------------------------------------------------------------ poses
    def rest(self) -> None:
        for name, ob in self.j.items():
            if name == "root":
                continue
            ob.rotation_euler = (0, 0, 0)
            ob.scale = (HEAD_SCALE,) * 3 if name == "head" else (1, 1, 1)
        self.j["pelvis"].location = (0, 0, 0.80)
        self.j["neck"].location = (0, 0, 0.47)

    def pose_idle(self, i: int) -> None:
        self.rest()
        j = self.j
        t = i / IDLE_N
        b = math.sin(t * 2 * math.pi)
        j["pelvis"].location.z = 0.80 - 0.008 * (1 - b) * 0.5
        j["spine"].rotation_euler = (0.03 + 0.012 * b, 0, 0)
        j["spine"].scale = (1 + 0.006 * b, 1 + 0.006 * b, 1 + 0.010 * b)
        j["neck"].rotation_euler = (-0.04 - 0.012 * b, 0, 0)
        j["head"].rotation_euler = (0.02 * b, 0, 0)
        # jambes légèrement écartées
        j["hipL"].rotation_euler = (0.04, -0.08, 0)
        j["hipR"].rotation_euler = (-0.06, 0.08, 0)
        j["kneeL"].rotation_euler = (0.06, 0, 0)
        j["kneeR"].rotation_euler = (0.10, 0, 0)
        # bras gauche le long du corps, bras droit (main libre) tendu vers l'avant
        j["shL"].rotation_euler = (0.06 + 0.02 * b, -0.22 - 0.02 * b, 0)
        j["elL"].rotation_euler = (-0.25, 0, 0)
        j["shR"].rotation_euler = (-0.55 - 0.02 * b, 0.20, 0.0)
        j["elR"].rotation_euler = (-0.75, 0, 0.0)
        j["tasL"].rotation_euler = (0, -0.04, 0)
        j["tasR"].rotation_euler = (0, 0.04, 0)
        self.clear_dyn()
        self.build_scarf(t, flow=0.18, amp=0.035)

    def pose_run(self, i: int) -> None:
        self.rest()
        j = self.j
        p = 2 * math.pi * i / RUN_N
        s = math.sin(p)
        # rebond : bas au contact (p = 0, pi), haut à mi-foulée
        j["pelvis"].location.z = 0.77 + 0.05 * abs(math.sin(p + math.pi / 2)) ** 0.8 * 0 + 0.045 * abs(s)
        j["pelvis"].rotation_euler = (0, 0, -0.10 * s)
        j["spine"].rotation_euler = (0.16, 0, 0.16 * s)
        j["neck"].rotation_euler = (-0.14, 0, -0.10 * s)
        # jambes
        j["hipL"].rotation_euler = (-0.75 * s - 0.10, 0, 0)
        j["hipR"].rotation_euler = (0.75 * s - 0.10, 0, 0)
        j["kneeL"].rotation_euler = (0.25 + 1.05 * max(0.0, math.sin(p - 0.9)), 0, 0)
        j["kneeR"].rotation_euler = (0.25 + 1.05 * max(0.0, math.sin(p - 0.9 + math.pi)), 0, 0)
        # bras opposés aux jambes ; bras droit reste devant (main libre / visée)
        j["shL"].rotation_euler = (0.85 * s, -0.25, 0)
        j["elL"].rotation_euler = (-0.75 - 0.35 * max(0.0, -s), 0, 0)
        j["shR"].rotation_euler = (-0.75 - 0.25 * s, 0.25, 0)
        j["elR"].rotation_euler = (-0.75, 0, 0)
        # tabard et tassettes suivent les cuisses
        j["tabF"].rotation_euler = (-0.12 - 0.18 * abs(s), 0, 0.10 * s)
        j["tabB"].rotation_euler = (0.55 + 0.15 * abs(s), 0, 0)
        j["tasL"].rotation_euler = (-0.5 * s * 0.6, -0.08, 0)
        j["tasR"].rotation_euler = (0.5 * s * 0.6, 0.08, 0)
        self.clear_dyn()
        self.build_scarf(i / RUN_N * 2.0, flow=0.85, amp=0.07)


def bmesh_new_poly(pts):
    import bmesh
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in pts]
    bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    return bm


def bmesh_translate(bm, d) -> None:
    for v in bm.verts:
        v.co += Vector(d)


# ----------------------------------------------------------------------------- rendu

def setup_scene():
    C.reset_scene()
    C.setup_render(FRAME * SS, samples=4, outline_px=5.5)
    hero = Hero()
    cam = C.ortho_camera(ELEV, ORTHO, target=(0, 0, CAM_TARGET_Z))
    return hero, cam


def render_frame(hero: Hero, cam, direction: str, anim: str, i: int, path: str) -> None:
    hero.j["root"].rotation_euler = (0, 0, math.radians(DIRS[direction]))
    if anim == "idle":
        hero.pose_idle(i)
    else:
        hero.pose_run(i)
    big = path + ".big.png"
    if CLOSE:
        C.render_to(path)
        return
    C.render_to(big)
    C.downscale(big, path, (FRAME, FRAME))
    os.remove(big)


def assemble(frames: dict[tuple[str, str], list[str]]) -> dict:
    """Planches : une par animation (lignes = directions, colonnes = images)."""
    from PIL import Image
    sheets = {}
    for anim, n in (("idle", IDLE_N), ("run", RUN_N)):
        sheet = Image.new("RGBA", (FRAME * n, FRAME * len(DIRS)), (0, 0, 0, 0))
        for r, d in enumerate(DIRS):
            for c, p in enumerate(frames[(anim, d)]):
                sheet.paste(Image.open(p), (c * FRAME, r * FRAME))
        out = os.path.join(OUT_DIR, "hero_%s.png" % anim)
        # alpha nettoyé : pixels quasi transparents -> 0 (meilleure compression)
        px = sheet.load()
        for y in range(sheet.height):
            for x in range(sheet.width):
                if px[x, y][3] < 3:
                    px[x, y] = (0, 0, 0, 0)
        sheet.save(out, optimize=True)
        sheets[anim] = n
    return sheets


def write_tres() -> None:
    lines = ['[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (2 + len(DIRS) * (IDLE_N + RUN_N)), ""]
    lines.append('[ext_resource type="Texture2D" path="res://assets/sprites/hero3d/hero_idle.png" id="1_idle"]')
    lines.append('[ext_resource type="Texture2D" path="res://assets/sprites/hero3d/hero_run.png" id="2_run"]')
    lines.append("")
    anims = []
    for anim, n, tex in (("idle", IDLE_N, "1_idle"), ("run", RUN_N, "2_run")):
        for r, d in enumerate(DIRS):
            ids = []
            for c in range(n):
                sid = "A_%s_%s_%d" % (anim, d, c)
                ids.append(sid)
                lines.append('[sub_resource type="AtlasTexture" id="%s"]' % sid)
                lines.append('atlas = ExtResource("%s")' % tex)
                lines.append("region = Rect2(%d, %d, %d, %d)" % (c * FRAME, r * FRAME, FRAME, FRAME))
                lines.append("")
            fr = ", ".join('{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % s for s in ids)
            anims.append('{\n"frames": [%s],\n"loop": true,\n"name": &"%s_%s",\n"speed": %.1f\n}'
                         % (fr, anim, d, float(FPS[anim])))
    lines.append("[resource]")
    lines.append("animations = [%s]" % ", ".join(anims))
    with open(os.path.join(OUT_DIR, "hero_frames.tres"), "w") as f:
        f.write("\n".join(lines) + "\n")


def main() -> None:
    args = sys.argv[1:]
    os.makedirs(TMP_DIR, exist_ok=True)
    hero, cam = setup_scene()
    feet = C.world_to_px(cam, (0, 0, 0))
    feet = (round(feet[0] / SS), round(feet[1] / SS))
    if "--blend" in args:
        hero.pose_idle(0)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(os.path.dirname(__file__), "hero.blend"))
        return
    if "--close" in args:
        global CLOSE
        CLOSE = True
        cam.data.ortho_scale = 1.1
        cam.location.z += 0.55
        C.bpy.context.scene.render.resolution_x = 480
        C.bpy.context.scene.render.resolution_y = 480
    if "--preview" in args:
        dirs = args[args.index("--preview") + 1].split(",")
        anims = args[args.index("--anim") + 1].split(",") if "--anim" in args else ["idle:0"]
        for d in dirs:
            for a in anims:
                an, i = a.split(":")
                p = os.path.join(TMP_DIR, "%s_%s_%s_%s.png" % ("close" if CLOSE else "prev", an, d, i))
                render_frame(hero, cam, d, an, int(i), p)
                print("PREVIEW", p)
        print("FEET", feet)
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    t0 = time.time()
    frames: dict[tuple[str, str], list[str]] = {}
    for d in DIRS:
        for anim, n in (("idle", IDLE_N), ("run", RUN_N)):
            lst = []
            for i in range(n):
                p = os.path.join(TMP_DIR, "%s_%s_%d.png" % (anim, d, i))
                render_frame(hero, cam, d, anim, i, p)
                lst.append(p)
            frames[(anim, d)] = lst
        print("DIR", d, "%.0fs" % (time.time() - t0), flush=True)
    assemble(frames)
    write_tres()
    hero_px = measure_height(frames)
    # display_height : hauteur du CADRE complet en unités monde (scale = display_height / frame_size.y),
    # calculée pour que le héros visible fasse ~54 unités monde (~70 px à l'écran au zoom 1.3).
    disp = round(HERO_WORLD_HEIGHT * FRAME / hero_px, 1)
    meta = {
        "frame_size": [FRAME, FRAME],
        "feet_offset": [feet[0], feet[1]],
        "display_height": disp,
        "fps": {"idle": FPS["idle"], "run": FPS["run"]},
        "directions": list(DIRS.keys()),
        "frames": {"idle": IDLE_N, "run": RUN_N},
        "hero_height_px": hero_px,
        "sheets": {"idle": "res://assets/sprites/hero3d/hero_idle.png",
                   "run": "res://assets/sprites/hero3d/hero_run.png"},
        "notes": "display_height = hauteur du cadre entier (frame_size.y px) en unités monde : "
                 "scale = display_height / frame_size.y. feet_offset = point des pieds (px depuis le "
                 "coin haut-gauche du cadre) -> offset = -(feet_offset - frame_size/2) si centered.",
    }
    with open(os.path.join(OUT_DIR, "hero_meta.json"), "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
        f.write("\n")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(os.path.dirname(__file__), "hero.blend"))
    print("DONE in %.0fs, feet=%s, hero_px=%d" % (time.time() - t0, feet, hero_px))


def measure_height(frames) -> int:
    """Hauteur visible du héros (px) en idle face caméra (sans les cornes : boîte alpha)."""
    from PIL import Image
    im = Image.open(frames[("idle", "s")][0])
    bb = im.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
    return bb[3] - bb[1]


if __name__ == "__main__":
    main()
