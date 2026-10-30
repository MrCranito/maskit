"""Hors-la-loi du Far West (ennemis d'Exfil Rush) : modélisation 3D scriptée, rendus 8 directions,
planches compactes (atlas rogné) + SpriteFrames + méta JSON, même pipeline que le héros
(art/blender/build_hero.py : caméra orthographique 3/4 à 48°, matériaux toon peints, contour
Freestyle, même échelle en unités monde).

Usage (depuis la racine du projet) :
    python3 art/blender/build_enemies.py                         # les 6 archétypes
    python3 art/blender/build_enemies.py --kinds rifleman,gang_boss
    python3 art/blender/build_enemies.py --preview s,e --anim idle:0,death:7 [--kinds gunslinger]
    python3 art/blender/build_enemies.py --sheet                 # planche de présentation (captures)

Archétypes (silhouettes très différentes, accents rouges/noirs lisibles sur le sable) :
    outlaw_knife  bandit au couteau : fin, foulard rouge sur le visage, petit chapeau, gilet de cuir
    gunslinger    pistolero : long cache-poussière noir, chapeau haut, deux revolvers
    shotgun_brute brute : massif, ventre, barbe, chapeau melon, cache-poussière fauve, fusil à pompe
    rifleman      tireur embusqué : chapeau très large, cartouchière, carabine, longue-vue au flanc
    dynamiter     dynamiteur : casquette de mineur + lunettes, bretelles, bâtons de dynamite rouges
    gang_boss     chef de bande (élite) : plus grand, poncho rouge à motifs, chapeau noir et or

Animations (8 directions) : idle, run, attack, hit, death (+ throw pour le chef).
attack : images 0-2 = élan (l'image 2 est tenue pendant le télégraphe), 3 = coup / tir, 4-5 = retour.
death : chute sur le dos, la dernière image = cadavre au sol (réutilisée par le jeu).

Sortie (par archétype) : assets/sprites/enemies/<kind>/
    <kind>_atlas.png   images rognées, empaquetées (AtlasTexture.margin restaure le cadre)
    <kind>_frames.tres SpriteFrames : animations <anim>_<dir>
    <kind>_meta.json   frame_size, feet_offset, display_height, fps, frames, head, muzzle, etc.
"""
from __future__ import annotations

import json
import math
import os
import random
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "enemies")
TMP_DIR = os.environ.get("RDM_TMP", "/tmp/rdm_enemy_frames")

# Même densité de pixels que le héros (128x160 px pour ORTHO 2.30) : cadre carré plus grand
# pour la chute au sol et les grands gabarits (brute, chef).
FRAME = 192
SS = 2
ELEV = 48.0
ORTHO_H = 2.30 * FRAME / 160.0
CAM_TARGET_Z = 0.86
HERO_PX_PER_UNIT = 160.0 / 2.30
# Échelle monde : identique au héros (hero_meta.json display_height 92.3 pour 160 px).
WORLD_PER_PX = 92.3 / 160.0

L_UP, L_LOW = 0.20, 0.225
SHOULDER = {"L": Vector((0.245, 0.0, 0.33)), "R": Vector((-0.245, 0.0, 0.33))}

DIRS = {"e": 90.0, "se": 45.0, "s": 0.0, "sw": -45.0, "w": -90.0, "nw": -135.0, "n": 180.0, "ne": 135.0}
# (nombre d'images, fps, boucle)
ANIMS_BASE = {
    "idle": (6, 7, True),
    "run": (8, 14, True),
    "attack": (6, 12, False),
    "hit": (3, 14, False),
    "death": (8, 12, False),
}

# ----------------------------------------------------------------------------- matériaux
# (base, ombre, lumière) en hex ; ("pat", [...], échelle) = usure / motif ; "!#hex" = émissif.
COMMON_MATS = {
    "skin": ("#c88c64", "#6e4048", "#eeb48a"),
    "eye": ("#1a1418", None, None),
    "brow": ("#2a1c18", None, None),
    "metal": ("#8a8c92", "#2c2e3a", "#d8dae0"),
    "metal_dark": ("#3a3a40", "#121218", "#64646c"),
    "wood": ("#7a4a2a", "#30182a", "#a8703e"),
    "brass": ("#c09040", "#5a3828", "#f0d080"),
    "spark": "!#ffd060",
    "fuse": ("#3a2a20", None, None),
    "lens": ("#5a8ab0", "#1e2a4a", "#a8d0f0"),
}

# Les anciens hors-la-loi (outlaw_knife, gunslinger, shotgun_brute, rifleman, dynamiter, gang_boss)
# ont été retirés : le bestiaire du Far West est rendu par art/blender/bestiary/far_west/
# (build_fw_bestiary.py). Ce module reste la bibliothèque commune du pipeline (pack, SpriteFrames,
# import VRAM, corpse_twist, classe Outlaw) utilisée par les autres bestiaires.
ARCH: dict[str, dict] = {}
KINDS = list(ARCH.keys())


def joint(name: str, parent, loc) -> bpy.types.Object:
    e = C.empty(name, loc, parent)
    e.rotation_mode = "XYZ"
    return e


def arc_strip(r, a0, a1, z0, z1, n=14, cy=0.0, flare=0.0, sx=1.0):
    secs = []
    for i in range(n):
        a = a0 + (a1 - a0) * i / (n - 1)
        s, c = math.sin(a), -math.cos(a)
        rb = r + flare
        secs.append([(rb * s * sx, cy + rb * c, z0), (r * s * sx, cy + r * c, z1)])
    return C.bm_loft(secs, closed=False)


def brim(r_in, r_out, curl=0.0, n=36, front_dip=0.0, z=0.0, sy=1.0):
    """Bord de chapeau : anneau avec les côtés relevés (curl) et l'avant légèrement baissé."""
    secs = []
    for k in range(4):
        t = k / 3
        r = r_in + (r_out - r_in) * t
        row = []
        for i in range(n):
            a = 2 * math.pi * i / n
            x, y = r * math.sin(a), -r * math.cos(a) * sy
            side = abs(math.sin(a))
            zz = z + curl * (t ** 2) * side ** 2 - front_dip * t * max(0.0, math.cos(a)) ** 2 \
                - front_dip * 0.6 * t * max(0.0, -math.cos(a)) ** 2
            row.append((x, y, zz))
        secs.append(row)
    return C.bm_loft(secs, cap_start=False, cap_end=False)


def corpse_twist(dir_ang_deg: float) -> float:
    """Vrille (rad) à appliquer pendant la chute pour que l'axe pieds→tête du cadavre soit proche
    de l'horizontale de l'écran (±20°), avec la plus petite rotation possible."""
    best = None
    for target in (20.0, 160.0, -20.0, -160.0):
        tau = (target - (dir_ang_deg + 90.0) + 180.0) % 360.0 - 180.0
        if best is None or abs(tau) < abs(best):
            best = tau
    return math.radians(best)


class Outlaw:
    def __init__(self, kind: str) -> None:
        self.kind = kind
        self.dir_ang = 0.0
        self.A = ARCH[kind]
        self.j: dict[str, bpy.types.Object] = {}
        self.parts: list[tuple[bpy.types.Object, str]] = []
        self.grp: dict[str, list[bpy.types.Object]] = {}
        self.ph = C.toon("_ph_" + kind, "#ff00ff")
        self.rng = random.Random(11)
        self.LEG = self.A["leg"]
        self.PZ = 0.80 - 0.77 * (1 - self.LEG)
        self.HS = self.A["head"]
        self.TW, self.TD = self.A["torso"]
        self.weapons: dict[str, bpy.types.Object] = {}
        self.build()
        self.apply_mats()

    # ------------------------------------------------------------------ outils
    def part(self, name, bm, key, parent, smooth=True, grp=None, nofs=False, thick=0.0):
        ob = C.mesh_obj(name, bm, self.ph, smooth=smooth, coll=C.nofs_collection() if nofs else None)
        ob.parent = parent
        if thick > 0.0:
            C.solidify(ob, thick, 0.0)
        self.parts.append((ob, key))
        if grp:
            self.grp.setdefault(grp, []).append(ob)
        return ob

    def show(self, grp: str, on: bool) -> None:
        for ob in self.grp.get(grp, []):
            ob.hide_render = not on
            ob.hide_viewport = not on

    def apply_mats(self) -> None:
        spec = dict(COMMON_MATS)
        spec.update(self.A["mats"])
        mats = {}
        for key, sp in spec.items():
            name = "%s_%s" % (self.kind, key)
            if isinstance(sp, str) and sp.startswith("!"):
                mats[key] = C.toon(name, sp[1:], emit=1.6)
            elif sp[0] == "pat":
                mats[key] = C.toon_pattern(name, sp[1], scale=sp[2], thresholds=(0.55,), rim=0.22)
            elif key in ("eye", "brow", "fuse"):
                mats[key] = C.toon(name, sp[0], sp[1], sp[2], rim=0.0, band=0.25)
            else:
                mats[key] = C.toon(name, sp[0], sp[1], sp[2], rim=0.24)
        for ob, key in self.parts:
            ob.data.materials[0] = mats.get(key, mats.get("shirt"))

    # ------------------------------------------------------------------ construction
    def build(self) -> None:
        j = self.j
        A = self.A
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["body"] = body = joint("body", root, (0, 0, 0))
        body.scale = (A["scale"],) * 3
        j["pelvis"] = pelvis = joint("pelvis", body, (0, 0, self.PZ))
        j["spine"] = spine = joint("spine", pelvis, (0, 0, 0.08))
        j["neck"] = neck = joint("neck", spine, (0, 0, 0.45))
        j["head"] = head = joint("head", neck, (0, 0, 0.0))
        head.scale = (self.HS,) * 3
        self.build_legs(pelvis)
        self.build_torso(pelvis, spine)
        self.build_arms(spine)
        self.build_head(head)
        self.build_hat(head)
        self.build_weapons(spine)

    def build_legs(self, pelvis) -> None:
        j, LEG = self.j, self.LEG
        bw = 1.0 + 0.12 * self.A["belly"]
        for side, sx in (("L", 1), ("R", -1)):
            hip = j["hip" + side] = joint("hip" + side, pelvis, (0.115 * sx * bw, 0, -0.02))
            knee = j["knee" + side] = joint("knee" + side, hip, (0, 0, -0.36 * LEG))
            self.part("thigh" + side, C.bm_xform(C.bm_cyl(12, 0.118 * bw, 0.098 * bw, 0.38),
                      loc=(0, 0, -0.17), scale=(1, 1, LEG)), "pants", hip)
            self.part("shin" + side, C.bm_xform(C.bm_cyl(12, 0.096 * bw, 0.086 * bw, 0.22 * LEG),
                      loc=(0, 0, LEG * -0.10)), "pants", knee)
            # botte de cow-boy : tige haute, talon, bout pointu, éperon
            self.part("bootShaft" + side, C.bm_xform(C.bm_cyl(12, 0.104, 0.112, 0.24 * LEG),
                      loc=(0, 0, LEG * -0.25)), "boot", knee)
            fz = -0.345 + 0.41 * (1 - LEG)
            foot = C.bm_sphere(12, 8, 1.0)
            C.bm_xform(foot, loc=(0, -0.07, fz + 0.005), scale=(0.085, 0.16, 0.06))
            self.part("foot" + side, foot, "boot", knee)
            self.part("heel" + side, C.bm_xform(C.bm_box(0.08, 0.06, 0.06, bevel=0.01),
                      loc=(0, 0.05, fz - 0.02)), "boot", knee)
            self.part("spur" + side, C.bm_xform(C.bm_torus(10, 4, 0.03, 0.008),
                      loc=(0.0, 0.10, fz + 0.01), rot=(0, math.pi / 2, 0)), "metal", knee)

    def build_torso(self, pelvis, spine) -> None:
        A = self.A
        tw, td, belly = self.TW, self.TD, A["belly"]
        self.part("hips", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, 0, -0.01),
                  scale=(0.215 * tw, 0.16 * td, 0.15)), "pants", pelvis)
        self.part("belt", C.bm_xform(C.bm_cyl(18, 0.218 * tw, 0.218 * tw, 0.055), loc=(0, 0, 0.05),
                  scale=(1, 0.76 * td / tw, 1)), "belt", pelvis)
        self.part("buckle", C.bm_xform(C.bm_box(0.075, 0.03, 0.05, bevel=0.01),
                  loc=(0, -0.168 * td, 0.05)), "brass", pelvis)
        # holster côté droit (et gauche si deux armes)
        sides = [-1] + ([1] if A.get("offhand") == "revolver" else [])
        if A["weapon"] in ("revolver", "revolver_gold"):
            for sx in sides:
                self.part("holster", C.bm_xform(C.bm_box(0.06, 0.10, 0.17, bevel=0.02),
                          loc=(0.21 * tw * sx, -0.02, -0.06), rot=(0.15, 0, 0)), "belt", pelvis)
        # torse
        tz = [0.00, 0.15, 0.29, 0.38, 0.45]
        rx = [0.185, 0.200, 0.226, 0.212, 0.110]
        ry = [0.135, 0.145, 0.152, 0.140, 0.092]
        secs = []
        for k in range(5):
            bulge = belly * 0.06 * (1.0 if k in (0, 1) else 0.3 if k == 2 else 0.0)
            secs.append(C.ellipse(0, -bulge * 0.6, tz[k], rx[k] * tw + bulge * 0.4, ry[k] * td + bulge, 16))
        self.part("torso", C.bm_loft(secs), "shirt", spine)
        if belly > 0.5:
            self.part("belly", C.bm_xform(C.bm_sphere(14, 9, 1.0), loc=(0, -0.10 * td, 0.08),
                      scale=(0.20 * tw, 0.13 * td, 0.17)), "shirt", spine)
        self.part("collar", C.bm_xform(C.bm_cyl(12, 0.10, 0.09, 0.08), loc=(0, 0.0, 0.46)), "shirt", spine)
        # foulard noué au cou (sous le visage)
        if A["face"] in ("bandana_neck", "scarf"):
            self.part("neckerchief", C.bm_xform(C.bm_torus(16, 6, 0.10, 0.045), loc=(0, 0, 0.45),
                      scale=(1.05, 1.0, 0.8)), "bandana", spine)
            tri = C.bm_tube([(0, -0.10, 0.45), (0, -0.14, 0.37), (0, -0.145, 0.31)], [0.07, 0.05, 0.01],
                            seg=6, flat=0.35, up=(0, 1, 0))
            self.part("kerchiefTip", tri, "bandana", spine)
        # gilet ouvert
        if A["vest"]:
            vs = []
            for k, (z, r1, r2) in enumerate(((0.02, 0.198, 0.150), (0.20, 0.216, 0.160), (0.36, 0.226, 0.156))):
                vs.append(C.ellipse(0, 0.0, z, r1 * tw + 0.012, r2 * td + 0.012 + (0.02 * belly if k == 0 else 0), 18))
            vest = C.bm_loft(vs, cap_start=False, cap_end=False)
            # ouverture devant : on supprime les faces dont le centre est très à l'avant
            for f in list(vest.faces):
                c = f.calc_center_median()
                if c.y < -0.12 * td and abs(c.x) < 0.07 * tw:
                    vest.faces.remove(f)
            self.part("vest", vest, "vest", spine, thick=0.012)
            self.part("vestPocket", C.bm_xform(C.bm_box(0.06, 0.02, 0.05, bevel=0.008),
                      loc=(0.11 * tw, -0.165 * td, 0.27)), "vest", spine)
            self.part("watchChain", C.bm_tube(C.bezier((0.09 * tw, -0.17 * td, 0.20), (0.04, -0.19 * td, 0.16),
                                                       (-0.02, -0.19 * td, 0.16), (-0.08 * tw, -0.17 * td, 0.20), 6),
                                              [0.007] * 6, seg=5), "brass", spine)
        # bretelles (dynamiteur)
        if A.get("suspenders"):
            for sx in (1, -1):
                st = C.bm_tube(C.bezier((0.10 * sx, -0.15 * td, 0.02), (0.12 * sx, -0.17 * td, 0.30),
                                        (0.12 * sx, 0.0, 0.50), (0.10 * sx, 0.15 * td, 0.02), 7),
                               [0.022] * 7, seg=5, flat=0.4, up=(0, 0, 1))
                self.part("suspender", st, "strap", spine)
        # écharpe / ceinture d'étoffe rouge (bandit)
        if self.kind == "outlaw_knife":
            self.part("sash", C.bm_xform(C.bm_cyl(18, 0.224 * tw, 0.226 * tw, 0.07), loc=(0, 0, 0.11),
                      scale=(1, 0.78 * td / tw, 1)), "sash", pelvis)
            self.part("sashTail", C.bm_tube(C.bezier((0.17, -0.10, 0.10), (0.21, -0.09, 0.02),
                                                     (0.22, -0.07, -0.07), (0.20, -0.05, -0.15), 5),
                                            [0.04, 0.04, 0.035, 0.03, 0.02], seg=6, flat=0.35), "sash", pelvis)
        # cartouchière en bandoulière
        bd = A.get("bandolier")
        if bd:
            pts = []
            for i in range(25):
                a = 2 * math.pi * i / 24
                pts.append((math.sin(a) * 0.235 * tw, -math.cos(a) * 0.175 * td, 0.24 + 0.17 * math.sin(a)))
            self.part("bandolier", C.bm_tube(pts, [0.026] * 25, seg=5, flat=0.45, up=(0, 0, 1)),
                      "belt", spine)
            for i in range(-4, 5):
                a = i * 0.16
                x, y = math.sin(a) * 0.245 * tw, -math.cos(a) * 0.185 * td
                z = 0.24 + 0.17 * math.sin(a)
                if bd == "dynamite":
                    if i % 2:
                        continue
                    self.part("dstick", C.bm_xform(C.bm_cyl(10, 0.026, 0.026, 0.14), loc=(x, y - 0.01, z),
                              rot=(0, 0.7, 0)), "stick", spine)
                else:
                    self.part("cart", C.bm_xform(C.bm_cyl(8, 0.011, 0.011, 0.06), loc=(x, y - 0.012, z),
                              rot=(0, 0.95, 0)), "shell", spine)
        # cache-poussière (manteau long) : veste + jupe ouverte devant
        coat = A["coat"]
        if coat:
            cs = []
            for z, r1, r2 in ((0.04, 0.205, 0.158), (0.20, 0.222, 0.168), (0.34, 0.236, 0.166), (0.42, 0.20, 0.14)):
                cs.append(C.ellipse(0, 0.0, z, r1 * tw + 0.02, r2 * td + 0.02 + (0.04 * belly if z < 0.1 else 0), 20))
            cbm = C.bm_loft(cs, cap_start=False, cap_end=False)
            for f in list(cbm.faces):
                c = f.calc_center_median()
                if c.y < -0.10 * td and abs(c.x) < 0.10 * tw:
                    cbm.faces.remove(f)
            self.part("coatTop", cbm, "coat", spine, thick=0.014)
            # col relevé
            self.part("coatCollar", arc_strip(0.15, 0.7, 2 * math.pi - 0.7, 0.40, 0.50, n=14, flare=0.03),
                      "coat", spine, thick=0.012)
            length = 0.50 if coat == "duster" else 0.30
            skirt = arc_strip(0.235 * tw + 0.02, 0.55, 2 * math.pi - 0.55, -length, 0.10, n=22, flare=0.10,
                              sx=1.0)
            C.bm_xform(skirt, scale=(1, 0.80 * td / tw + 0.05 * belly, 1))
            self.part("coatSkirt", skirt, "coat", pelvis, thick=0.014)
            for sx in (1, -1):
                self.part("coatPocket", C.bm_xform(C.bm_box(0.012, 0.09, 0.08, bevel=0.006),
                          loc=(0.25 * tw * sx + 0.03 * sx, -0.06, -0.06), rot=(0, 0.25 * sx, 0)), "coat", pelvis)
        # poncho (chef)
        if A["poncho"]:
            ps = [C.ellipse(0, 0.0, 0.47, 0.115, 0.10, 24),
                  C.ellipse(0, 0.0, 0.39, 0.30 * tw, 0.22 * td, 24),
                  C.ellipse(0, 0.0, 0.24, 0.40 * tw, 0.28 * td, 24),
                  C.ellipse(0, -0.01, 0.04, 0.44 * tw, 0.31 * td, 24)]
            self.part("poncho", C.bm_loft(ps, cap_start=False, cap_end=False), "poncho", spine, thick=0.018)
            for k, (z, r1, r2, key) in enumerate(((0.13, 0.425, 0.298, "poncho_w"), (0.10, 0.43, 0.302, "poncho_k"),
                                                 (0.07, 0.435, 0.306, "poncho_w"))):
                band = C.bm_loft([C.ellipse(0, -0.005, z - 0.012, r1 * tw + 0.004, r2 * td + 0.004, 24),
                                  C.ellipse(0, -0.005, z + 0.012, r1 * tw - 0.004, r2 * td, 24)],
                                 cap_start=False, cap_end=False)
                self.part("ponchoBand%d" % k, band, key, spine, nofs=True)
            # franges en zigzag (dents) au bas du poncho
            for i in range(28):
                a = 2 * math.pi * i / 28
                x, y = math.sin(a) * 0.44 * tw, -math.cos(a) * 0.31 * td - 0.01
                self.part("fringe", C.bm_xform(C.bm_cyl(4, 0.03, 0.0, 0.07), loc=(x, y, 0.005),
                          rot=(math.pi, 0, 0)), "poncho", spine, smooth=False)

    def build_arms(self, spine) -> None:
        j = self.j
        aw = self.A["arm"]
        sleeve = "coat" if self.A["coat"] == "duster" else "shirt"
        for side, sx in (("L", 1), ("R", -1)):
            ua = j["ua" + side] = C.empty("ua" + side, SHOULDER[side] * Vector((self.TW ** 0.5, 1, 1)), spine)
            ua.rotation_mode = "QUATERNION"
            fa = j["fa" + side] = C.empty("fa" + side, (0, 0, 0), spine)
            fa.rotation_mode = "QUATERNION"
            self.part("shoulder" + side, C.bm_xform(C.bm_sphere(12, 8, 0.10 * aw), loc=(0, 0, -0.01)),
                      sleeve, ua)
            self.part("uarm" + side, C.bm_xform(C.bm_cyl(12, 0.092 * aw, 0.080 * aw, 0.19), loc=(0, 0, -0.10)),
                      sleeve, ua)
            self.part("farm" + side, C.bm_xform(C.bm_cyl(10, 0.078 * aw, 0.066 * aw, 0.15), loc=(0, 0, -0.07)),
                      sleeve, fa)
            # manchette / gant de cuir
            self.part("cuff" + side, C.bm_xform(C.bm_cyl(10, 0.072 * aw, 0.080 * aw, 0.06), loc=(0, 0, -0.15)),
                      "belt" if self.kind in ("gunslinger", "gang_boss", "rifleman") else "skin", fa)
            hand = C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, 0, -L_LOW + 0.012),
                              scale=(0.078 * aw, 0.072 * aw, 0.085 * aw))
            self.part("hand" + side, hand, "skin", fa)
        if self.A["poncho"]:
            pass

    def build_head(self, head) -> None:
        face = self.A["face"]
        sk = C.bm_sphere(22, 16, 1.0)
        for v in sk.verts:
            x, y, z = v.co
            if z < 0:
                x *= 1.0 + 0.04 * (-z) - 0.22 * (-z) ** 2
                y *= 1.0 - 0.06 * (-z)
            v.co = Vector((x * 0.180, y * 0.172, z * 0.190)) + Vector((0, 0, 0.200))
        self.part("skull", sk, "skin", head)
        self.part("nose", C.bm_xform(C.bm_sphere(10, 7, 1.0), loc=(0, -0.172, 0.180),
                  scale=(0.032, 0.03, 0.034)), "skin", head)
        for sx in (1, -1):
            self.part("ear", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.178 * sx, 0.0, 0.19),
                      scale=(0.025, 0.04, 0.05)), "skin", head)
            # yeux : petites fentes sombres, sourcils froncés (lisibles de loin)
            self.part("eye", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.065 * sx, -0.158, 0.232),
                      scale=(0.028, 0.012, 0.034)), "eye", head, nofs=True)
            self.part("brow", C.bm_xform(C.bm_box(0.075, 0.022, 0.022, bevel=0.006), loc=(0.066 * sx, -0.160, 0.282),
                      rot=(0, -0.38 * sx, 0)), "brow", head)
        if face == "bandana":
            bd = C.bm_sphere(22, 14, 1.0)
            keep = []
            for v in bd.verts:
                x, y, z = v.co
                v.co = Vector((x * 0.188, y * 0.182, z * 0.196 + 0.200))
            for f in list(bd.faces):
                c = f.calc_center_median()
                if c.z > 0.205 or c.y > 0.06:
                    bd.faces.remove(f)
            for v in list(bd.verts):
                if not v.link_faces:
                    bd.verts.remove(v)
            self.part("bandanaFace", bd, "bandana", head, thick=0.01)
            tri = C.bm_tube([(0, -0.17, 0.12), (0, -0.19, 0.04), (0, -0.17, -0.02)], [0.09, 0.06, 0.006],
                            seg=6, flat=0.25, up=(0, 1, 0))
            self.part("bandanaTip", tri, "bandana", head)
            self.part("bandanaKnot", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, 0.175, 0.20),
                      scale=(0.04, 0.03, 0.03)), "bandana", head)
        elif face == "beard":
            bd = C.bm_sphere(18, 12, 1.0)
            for v in bd.verts:
                x, y, z = v.co
                if z > 0.1:
                    z = 0.1 + (z - 0.1) * 0.3
                v.co = Vector((x * 0.16, y * 0.13 - 0.06, z * 0.12 + 0.09))
            self.part("beard", bd, "beard", head)
            self.part("mustache", C.bm_tube(C.bezier((-0.09, -0.15, 0.13), (-0.04, -0.19, 0.17),
                                                     (0.04, -0.19, 0.17), (0.09, -0.15, 0.13), 7),
                                            [0.012, 0.025, 0.03, 0.03, 0.03, 0.025, 0.012], seg=6, flat=0.6),
                      "beard", head)
        elif face == "mustache":
            self.part("mustache", C.bm_tube(C.bezier((-0.13, -0.13, 0.10), (-0.06, -0.20, 0.17),
                                                     (0.06, -0.20, 0.17), (0.13, -0.13, 0.10), 9),
                                            [0.008, 0.02, 0.03, 0.034, 0.034, 0.034, 0.03, 0.02, 0.008], seg=6,
                                            flat=0.6), "beard", head)
            self.part("goatee", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -0.15, 0.06),
                      scale=(0.035, 0.03, 0.05)), "beard", head)
            for sx in (1, -1):
                self.part("scar", C.bm_xform(C.bm_box(0.008, 0.01, 0.07), loc=(0.07 * sx, -0.163, 0.20),
                          rot=(0, 0.3, 0)), "brow", head, nofs=True) if sx > 0 else None
        elif face == "stubble":
            bd = C.bm_sphere(18, 12, 1.0)
            for v in bd.verts:
                x, y, z = v.co
                v.co = Vector((x * 0.172, y * 0.165 + 0.004, z * 0.10 + 0.115))
            for f in list(bd.faces):
                if f.calc_center_median().z > 0.15:
                    bd.faces.remove(f)
            for v in list(bd.verts):
                if not v.link_faces:
                    bd.verts.remove(v)
            self.part("stubble", bd, "brow", head, nofs=True)
            self.part("mustache", C.bm_tube(C.bezier((-0.07, -0.16, 0.14), (-0.03, -0.185, 0.155),
                                                     (0.03, -0.185, 0.155), (0.07, -0.16, 0.14), 5),
                                            [0.01, 0.02, 0.02, 0.02, 0.01], seg=5, flat=0.6), "brow", head)
        elif face == "scarf":
            # foulard remonté jusqu'au nez (gris) : comme bandana, couleur différente
            bd = C.bm_sphere(22, 14, 1.0)
            for v in bd.verts:
                x, y, z = v.co
                v.co = Vector((x * 0.188, y * 0.182, z * 0.196 + 0.200))
            for f in list(bd.faces):
                c = f.calc_center_median()
                if c.z > 0.19 or c.y > 0.10:
                    bd.faces.remove(f)
            for v in list(bd.verts):
                if not v.link_faces:
                    bd.verts.remove(v)
            self.part("scarfFace", bd, "bandana", head, thick=0.012)
        elif face == "bandana_neck":
            self.part("mustache", C.bm_tube(C.bezier((-0.08, -0.155, 0.13), (-0.03, -0.185, 0.155),
                                                     (0.03, -0.185, 0.155), (0.08, -0.155, 0.13), 5),
                                            [0.01, 0.022, 0.024, 0.022, 0.01], seg=5, flat=0.6), "brow", head)
        if self.kind == "dynamiter":
            # lunettes de mineur relevées sur la casquette
            for sx in (1, -1):
                self.part("goggleRim", C.bm_xform(C.bm_cyl(14, 0.045, 0.045, 0.03), loc=(0.055 * sx, -0.17, 0.34),
                          rot=(1.2, 0, 0)), "goggle", head)
                self.part("goggleLens", C.bm_xform(C.bm_cyl(14, 0.034, 0.034, 0.012), loc=(0.055 * sx, -0.186, 0.345),
                          rot=(1.2, 0, 0)), "lens", head)

    def build_hat(self, head) -> None:
        h = self.A["hat"]
        hz = 0.33
        if h in ("cowboy_low", "cowboy_tall", "wide", "boss"):
            crown_h = {"cowboy_low": 0.12, "cowboy_tall": 0.20, "wide": 0.15, "boss": 0.20}[h]
            r_out = {"cowboy_low": 0.31, "cowboy_tall": 0.33, "wide": 0.44, "boss": 0.38}[h]
            curl = {"cowboy_low": 0.06, "cowboy_tall": 0.08, "wide": 0.03, "boss": 0.10}[h]
            secs = []
            for k in range(6):
                t = k / 5
                rx = 0.175 - 0.035 * t ** 2
                ry = 0.160 - 0.040 * t ** 2
                pts = []
                for i in range(20):
                    a = 2 * math.pi * i / 20
                    x, y = rx * math.sin(a), -ry * math.cos(a)
                    z = hz + crown_h * t
                    if t > 0.75:   # pli du dessus (« pinch »)
                        z -= 0.04 * (1 - abs(math.sin(a))) * (t - 0.75) * 4
                    pts.append((x, y, z))
                secs.append(pts)
            crown = C.bm_loft(secs)
            self.part("crown", crown, "hat", head)
            band = C.bm_loft([C.ellipse(0, 0, hz + 0.005, 0.178, 0.163, 20),
                              C.ellipse(0, 0, hz + 0.04, 0.176, 0.161, 20)], cap_start=False, cap_end=False)
            self.part("hatband", band, "hatband", head, thick=0.008)
            self.part("brim", brim(0.15, r_out, curl=curl, front_dip=0.03, z=hz, sy=0.95), "hat", head,
                      thick=0.018)
            if h == "boss":
                for sx in (1, -1):
                    self.part("concho", C.bm_xform(C.bm_cyl(10, 0.02, 0.02, 0.01), loc=(0.12 * sx, -0.11, hz + 0.022),
                              rot=(1.2, 0, 0.6 * sx)), "gold", head)
        elif h == "derby":
            dm = C.bm_sphere(18, 10, 1.0)
            for v in dm.verts:
                if v.co.z < 0:
                    v.co.z = 0
            C.bm_xform(dm, loc=(0, 0.0, hz - 0.01), scale=(0.17, 0.16, 0.17))
            self.part("crown", dm, "hat", head)
            self.part("hatband", C.bm_loft([C.ellipse(0, 0, hz - 0.005, 0.172, 0.162, 20),
                                            C.ellipse(0, 0, hz + 0.03, 0.170, 0.160, 20)],
                                           cap_start=False, cap_end=False), "hatband", head, thick=0.008)
            self.part("brim", brim(0.15, 0.23, curl=0.05, z=hz - 0.01, sy=0.95), "hat", head, thick=0.016)
        elif h == "miner":
            cap = C.bm_sphere(18, 10, 1.0)
            for v in cap.verts:
                if v.co.z < 0:
                    v.co.z = 0
            C.bm_xform(cap, loc=(0, 0.01, hz - 0.03), scale=(0.19, 0.185, 0.13))
            self.part("crown", cap, "hat", head)
            vis = brim(0.15, 0.25, curl=0.0, z=hz - 0.03, sy=1.0)
            for f in list(vis.faces):
                if f.calc_center_median().y > -0.12:
                    vis.faces.remove(f)
            self.part("brim", vis, "hat", head, thick=0.016)
            self.part("hatband", C.bm_loft([C.ellipse(0, 0.01, hz - 0.03, 0.192, 0.187, 20),
                                            C.ellipse(0, 0.01, hz - 0.005, 0.19, 0.185, 20)],
                                           cap_start=False, cap_end=False), "goggle", head, thick=0.008)

    # --- armes -------------------------------------------------------------
    def gun_group(self, name: str, parent) -> bpy.types.Object:
        g = joint("w_" + name, parent, (0, 0, 0))
        self.weapons[name] = g
        return g

    def build_weapons(self, spine) -> None:
        A = self.A
        w = A["weapon"]
        if w == "knife":
            g = self.gun_group("knife", spine)
            blade = C.bm_box(0.012, 0.30, 0.055, bevel=0.004)
            for v in blade.verts:
                if v.co.y < -0.10:
                    v.co.z += (v.co.y + 0.10) * 0.18 if v.co.z > 0 else 0
                    v.co.z *= 1.0 - min(1.0, (-v.co.y - 0.10) / 0.06) * 0.8 if v.co.y < -0.13 else 1.0
            self.part("blade", C.bm_xform(blade, loc=(0, -0.20, 0.0)), "metal", g, grp="knife")
            self.part("guard", C.bm_xform(C.bm_box(0.03, 0.02, 0.10, bevel=0.005), loc=(0, -0.05, 0)), "brass", g,
                      grp="knife")
            self.part("handle", C.bm_xform(C.bm_cyl(8, 0.022, 0.024, 0.11), loc=(0, 0.01, 0), rot=(math.pi / 2, 0, 0)),
                      "wood", g, grp="knife")
            # second couteau à la ceinture
            self.part("sheath", C.bm_xform(C.bm_box(0.035, 0.05, 0.16, bevel=0.01), loc=(0.20, 0.05, -0.08),
                      rot=(0.2, 0.3, 0)), "belt", self.j["pelvis"])
        if w in ("revolver", "revolver_gold"):
            for side in (["R", "L"] if A.get("offhand") == "revolver" else ["R"]):
                g = self.gun_group("gun" + side, spine)
                body_key = "gold" if w == "revolver_gold" else "metal_dark"
                self.part("barrel", C.bm_xform(C.bm_cyl(10, 0.018, 0.018, 0.20), loc=(0, -0.13, 0.04),
                          rot=(math.pi / 2, 0, 0)), "metal", g, grp="gun" + side)
                self.part("cyl", C.bm_xform(C.bm_cyl(10, 0.034, 0.034, 0.07), loc=(0, -0.02, 0.035),
                          rot=(math.pi / 2, 0, 0)), body_key, g, grp="gun" + side)
                self.part("frame", C.bm_xform(C.bm_box(0.03, 0.10, 0.05, bevel=0.008), loc=(0, -0.03, 0.03)),
                          body_key, g, grp="gun" + side)
                self.part("grip", C.bm_xform(C.bm_box(0.034, 0.05, 0.11, bevel=0.012), loc=(0, 0.03, -0.03),
                          rot=(-0.45, 0, 0)), "wood", g, grp="gun" + side)
        if w == "shotgun":
            g = self.gun_group("long", spine)
            for sx in (1, -1):
                self.part("barrel", C.bm_xform(C.bm_cyl(10, 0.024, 0.024, 0.62), loc=(0.024 * sx, -0.33, 0.03),
                          rot=(math.pi / 2, 0, 0)), "metal_dark", g, grp="long")
            self.part("pump", C.bm_xform(C.bm_box(0.07, 0.16, 0.055, bevel=0.015), loc=(0, -0.24, -0.01)), "wood", g,
                      grp="long")
            self.part("receiver", C.bm_xform(C.bm_box(0.07, 0.14, 0.08, bevel=0.012), loc=(0, -0.02, 0.02)),
                      "metal_dark", g, grp="long")
            stock = C.bm_box(0.06, 0.30, 0.10, bevel=0.02)
            for v in stock.verts:
                if v.co.y > 0:
                    v.co.z = v.co.z * 1.5 - 0.03
            self.part("stock", C.bm_xform(stock, loc=(0, 0.20, -0.02)), "wood", g, grp="long")
        if w == "carbine":
            g = self.gun_group("long", spine)
            self.part("barrel", C.bm_xform(C.bm_cyl(10, 0.017, 0.017, 0.62), loc=(0, -0.40, 0.035),
                      rot=(math.pi / 2, 0, 0)), "metal_dark", g, grp="long")
            self.part("tube", C.bm_xform(C.bm_cyl(10, 0.014, 0.014, 0.50), loc=(0, -0.34, 0.005),
                      rot=(math.pi / 2, 0, 0)), "metal_dark", g, grp="long")
            self.part("fore", C.bm_xform(C.bm_box(0.05, 0.22, 0.05, bevel=0.012), loc=(0, -0.20, 0.0)), "wood", g,
                      grp="long")
            self.part("receiver", C.bm_xform(C.bm_box(0.055, 0.14, 0.075, bevel=0.012), loc=(0, -0.02, 0.02)),
                      "brass", g, grp="long")
            self.part("lever", C.bm_xform(C.bm_torus(10, 4, 0.04, 0.008), loc=(0, 0.02, -0.05),
                      rot=(0, math.pi / 2, 0), scale=(1, 1.4, 1)), "metal_dark", g, grp="long")
            stock = C.bm_box(0.05, 0.30, 0.09, bevel=0.02)
            for v in stock.verts:
                if v.co.y > 0:
                    v.co.z = v.co.z * 1.4 - 0.025
            self.part("stock", C.bm_xform(stock, loc=(0, 0.20, -0.02)), "wood", g, grp="long")
            # longue-vue en laiton à la ceinture
            self.part("spyglass", C.bm_xform(C.bm_cyl(12, 0.032, 0.026, 0.26), loc=(-0.21, 0.02, -0.02),
                      rot=(0.2, 0.15, 0)), "brass", self.j["pelvis"])
            self.part("spyglassBand", C.bm_xform(C.bm_cyl(12, 0.036, 0.036, 0.03), loc=(-0.21, 0.0, 0.08),
                      rot=(0.2, 0.15, 0)), "metal_dark", self.j["pelvis"])
        if w == "dynamite" or self.kind == "gang_boss":
            g = self.gun_group("stick", spine)
            self.part("stick", C.bm_xform(C.bm_cyl(10, 0.03, 0.03, 0.18), loc=(0, 0, 0.05)), "stick", g, grp="stick")
            self.part("fuse", C.bm_tube([(0, 0, 0.14), (0.01, 0.0, 0.18), (0.03, 0.0, 0.20)], [0.006] * 3, seg=4),
                      "fuse", g, grp="stick")
            self.part("spark", C.bm_xform(C.bm_sphere(8, 6, 0.028), loc=(0.03, 0.0, 0.205)), "spark", g, grp="stick",
                      nofs=True)
            for k in range(5):
                a = k * 2 * math.pi / 5
                self.part("sparkRay", C.bm_xform(C.bm_box(0.008, 0.008, 0.06), loc=(0.03 + 0.035 * math.cos(a), 0,
                          0.205 + 0.035 * math.sin(a)), rot=(0, -a + math.pi / 2, 0)), "spark", g, grp="stick",
                          nofs=True)

    # ------------------------------------------------------------------ poses
    def rest(self) -> None:
        for name, ob in self.j.items():
            if name in ("root",) or name.startswith(("ua", "fa", "w_")):
                continue
            ob.rotation_euler = (0, 0, 0)
        self.j["body"].location = (0, 0, 0)
        self.j["body"].rotation_euler = (0, 0, 0)
        self.j["pelvis"].location = (0, 0, self.PZ)
        self.j["head"].rotation_euler = (-0.18, 0, 0)
        self.j["neck"].location = (0, 0, 0.45)
        for name in self.grp:
            self.show(name, True)

    def arm_ik(self, side: str, target: Vector, pole: Vector) -> None:
        S = self.j["ua" + side].location.copy()
        d = target - S
        dist = min(max(d.length, 0.05), (L_UP + L_LOW) * 0.995)
        u = d.normalized()
        a = (L_UP ** 2 + dist ** 2 - L_LOW ** 2) / (2 * dist)
        h = math.sqrt(max(L_UP ** 2 - a * a, 0.0))
        p = pole - u * pole.dot(u)
        p = p.normalized() if p.length > 1e-5 else Vector((0, 1, 0))
        E = S + u * a + p * h
        H = S + u * dist
        down = Vector((0, 0, -1))
        ua, fa = self.j["ua" + side], self.j["fa" + side]
        ua.rotation_quaternion = down.rotation_difference((E - S).normalized())
        fa.location = E
        fa.rotation_quaternion = down.rotation_difference((H - E).normalized())

    def place(self, wname: str, loc, rot) -> None:
        g = self.weapons.get(wname)
        if g is not None:
            g.location = loc
            g.rotation_euler = rot

    def wpt(self, wname: str, local) -> Vector:
        g = self.weapons[wname]
        return Vector(g.location) + Euler(g.rotation_euler, "XYZ").to_matrix() @ Vector(local)

    def legs(self, hipL, hipR, kneeL, kneeR) -> None:
        j = self.j
        j["hipL"].rotation_euler = hipL
        j["hipR"].rotation_euler = hipR
        j["kneeL"].rotation_euler = (kneeL, 0, 0)
        j["kneeR"].rotation_euler = (kneeR, 0, 0)

    # Tenue de l'arme selon l'archétype : aim = 0 (repos) .. 1 (en joue). dz/dy = petits décalages.
    def hold(self, aim: float = 0.0, dz: float = 0.0, dy: float = 0.0, recoil: float = 0.0,
             recoil_l: float = 0.0, swing_l: float | None = None) -> None:
        w = self.A["weapon"]
        R = Vector((-0.8, 0.4, -0.6))
        Lp = Vector((0.8, 0.5, -0.6))
        if w == "knife":
            # couteau tenu bas, lame vers l'avant ; main gauche en garde
            hand = Vector((-0.16, -0.24 - 0.10 * aim, 0.06 + 0.12 * aim + dz))
            self.place("knife", hand, (-0.3 + 0.3 * aim, 0, 0.25))
            self.arm_ik("R", hand, R)
            self.arm_ik("L", Vector((0.15, -0.22, 0.16 + dz)) if swing_l is None else
                        Vector((0.20, -0.05 + 0.30 * swing_l, 0.05)), Lp)
        elif w in ("revolver", "revolver_gold"):
            dual = self.A.get("offhand") == "revolver"
            for side, sx, rc in (("R", -1, recoil), ("L", 1, recoil_l)):
                if side == "L" and not dual:
                    continue
                low = Vector((0.17 * sx, -0.14, 0.02 + dz))
                up = Vector((0.10 * sx, -0.46, 0.20 + dz))
                hand = low.lerp(up, aim) + Vector((0, 0.06 * rc, 0.08 * rc))
                pitch = 1.1 * (1 - aim) - 0.6 * rc
                self.place("gun" + side, hand, (pitch, 0, 0.05 * sx))
                self.arm_ik(side, hand, R if side == "R" else Lp)
            if not dual:
                if self.kind == "gang_boss" and swing_l is not None:
                    # « fan the hammer » : la main gauche balaie le chien
                    hl = Vector((0.0, -0.42 + 0.05 * swing_l, 0.24 + 0.06 * swing_l))
                    self.arm_ik("L", hl, Lp)
                else:
                    self.arm_ik("L", Vector((0.18, -0.06, 0.04 + dz)) if aim < 0.5 else
                                Vector((0.02, -0.38 * aim, 0.24)), Lp)
        elif w in ("shotgun", "carbine"):
            rest_loc = Vector((-0.06, -0.24, 0.10 + dz))
            aim_loc = Vector((-0.07, -0.26, 0.36))
            loc = rest_loc.lerp(aim_loc, aim) + Vector((0, 0.07 * recoil, 0.03 * recoil))
            rot = (0.55 * (1 - aim) - 0.35 * recoil, 0.0, 0.55 * (1 - aim))
            self.place("long", loc, rot)
            grip = self.wpt("long", (0, 0.08, -0.05))
            fore = self.wpt("long", (0, -0.24 if self.A["weapon"] == "shotgun" else -0.20, -0.03))
            if swing_l is not None:   # pompe / levier : main gauche ou droite décalée
                fore = fore + Vector((0, 0.06 * swing_l, 0))
            self.arm_ik("R", grip, R)
            self.arm_ik("L", fore, Lp)
        elif w == "dynamite":
            hand = Vector((-0.18, -0.20, 0.10 + dz))
            self.place("stick", hand + Vector((0, 0, -0.02)), (0.2, 0, 0))
            self.arm_ik("R", hand, R)
            self.arm_ik("L", Vector((0.17, -0.10, 0.05 + dz)), Lp)
        if self.kind == "gang_boss":
            self.show("stick", False)

    # --- idle -----------------------------------------------------------
    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        t = 2 * math.pi * i / n
        b = math.sin(t)
        sway = math.sin(t + 0.6)
        heavy = 1.0 + 0.6 * self.A["belly"]
        j["pelvis"].location.z = self.PZ - 0.012 * (1 - b) * 0.5 * heavy
        j["pelvis"].rotation_euler = (0, 0.012 * sway, 0.03 * sway)
        j["spine"].rotation_euler = (0.03 + 0.016 * b, -0.02 * sway, 0)
        j["spine"].scale = (1 + 0.01 * b, 1 + 0.01 * b, 1 + 0.012 * b)
        j["neck"].rotation_euler = (-0.04 - 0.016 * b, 0.03 * sway, 0.03 * sway)
        stance = 0.10 if self.kind in ("shotgun_brute", "gang_boss") else 0.07
        self.legs((0.03, -stance - 0.012 * sway, 0), (-0.03, stance - 0.012 * sway, 0), 0.07, 0.09)
        self.hold(aim=0.0, dz=0.012 * b)

    def pose_run(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        p = 2 * math.pi * i / n
        s = math.sin(p)
        amp = 0.85 if self.A["belly"] < 0.5 else 0.65
        PZ = self.PZ
        j["pelvis"].location.z = PZ - 0.045 + 0.060 * abs(math.sin(p + 0.35))
        j["pelvis"].rotation_euler = (0, 0, -0.16 * s)
        j["spine"].rotation_euler = (0.24, 0, 0.18 * s)
        j["neck"].rotation_euler = (-0.22, 0, -0.12 * s)
        self.legs((-amp * s - 0.15, 0, 0), (amp * s - 0.15, 0, 0),
                  0.20 + 1.35 * max(0.0, math.sin(p - 1.0)) ** 1.2,
                  0.20 + 1.35 * max(0.0, math.sin(p - 1.0 + math.pi)) ** 1.2)
        self.hold(aim=0.0, dz=0.02 * math.cos(p), swing_l=s if self.A["weapon"] == "knife" else None)
        if self.A["weapon"] == "dynamite" or (self.A["weapon"] == "revolver" and self.A.get("offhand") is None):
            sw = Vector((0.20, 0.28 * s - 0.02, 0.06 - 0.10 * abs(s)))
            self.arm_ik("L", self.j["uaL"].location + Vector((0.02, 0, -0.33)) + sw * 0.9, Vector((0.4, 0.9, -0.2)))

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        k = (1.0, 0.6, 0.25)[i]
        j["pelvis"].location.z = self.PZ - 0.03 * k
        j["pelvis"].location.y = 0.04 * k
        j["spine"].rotation_euler = (-0.34 * k, 0, 0.12 * k)
        j["neck"].rotation_euler = (-0.34 * k, 0, -0.14 * k)
        self.legs((0.12 * k, -0.10, 0), (-0.20 * k, 0.10, 0), 0.12 + 0.14 * k, 0.12)
        self.hold(aim=0.2 * k, dz=0.06 * k)

    def pose_death(self, i: int, n: int) -> None:
        """Chute sur le dos ; dernière image = cadavre au sol (pose stable, bras écartés)."""
        self.rest()
        j = self.j
        t = i / (n - 1)
        # 0..0.25 : coup reçu (recul), 0.25..0.8 : chute, 0.8..1 : rebond et immobilité
        if t < 0.25:
            u = t / 0.25
            fall = 0.08 * u
            j["spine"].rotation_euler = (-0.45 * u, 0, 0.15 * u)
            j["neck"].rotation_euler = (-0.5 * u, 0, -0.1 * u)
            self.legs((0.15 * u, -0.10, 0), (-0.25 * u, 0.12, 0), 0.25 * u, 0.15)
        else:
            u = min(1.0, (t - 0.25) / 0.55)
            e = u * u * (3 - 2 * u)
            bounce = 0.0
            if t > 0.8:
                v = (t - 0.8) / 0.2
                bounce = 0.06 * math.sin(v * math.pi) * (1 - v)
            fall = 0.08 + (math.pi / 2 - 0.08) * e - bounce
            j["spine"].rotation_euler = (-0.45 + 0.45 * e, 0, 0.15 - 0.10 * e)
            j["neck"].rotation_euler = (-0.5 + 0.35 * e, 0, -0.1 + 0.4 * e)
            # jambes : les genoux plient pendant la chute puis une jambe reste pliée
            self.legs((0.15 + 0.35 * math.sin(u * math.pi), -0.12 - 0.08 * e, 0),
                      (-0.25 + 0.25 * e, 0.14 + 0.10 * e, 0),
                      0.25 + 0.7 * math.sin(u * math.pi) * (1 - 0.6 * e) + 0.35 * e, 0.15 - 0.05 * e)
        # bascule du corps entier autour des pieds, glissé vers l'avant pour centrer le cadavre
        body = j["body"]
        k = fall / (math.pi / 2)
        # vrille pendant la chute : le cadavre finit couché en travers de l'écran (lisible),
        # jamais dans l'axe de la caméra (il ressemblerait à un personnage debout)
        tau = corpse_twist(self.dir_ang) * min(1.0, k * 1.2)
        body.rotation_euler = (-fall, 0, tau)
        sc = self.A["scale"]
        body.location = Euler((0, 0, tau)).to_matrix() @ Vector((0, -0.72 * sc * k, 0.16 * sc * k ** 2))
        # bras projetés en arrière puis écartés au sol
        arm_u = min(1.0, t / 0.6)
        hl = Vector((0.30, -0.05 + 0.25 * arm_u, 0.30 + 0.25 * arm_u))
        hr = Vector((-0.34, -0.10 + 0.20 * arm_u, 0.26 + 0.30 * arm_u))
        self.arm_ik("L", hl, Vector((0.8, 0.2, -0.6)))
        self.arm_ik("R", hr, Vector((-0.8, 0.2, -0.6)))
        w = self.A["weapon"]
        # l'arme tombe à côté de la main droite (même repère colonne)
        for name in list(self.weapons):
            if name in ("gunR", "gunL", "knife", "long", "stick"):
                pass
        if w in ("shotgun", "carbine"):
            self.place("long", hr + Vector((0.05, -0.18 * arm_u, -0.05)), (0.2 + 1.2 * arm_u, 0.0, 0.9 * arm_u))
        elif w == "knife":
            self.place("knife", hr, (0.4 * arm_u, 0.0, 0.8 * arm_u))
        elif w in ("revolver", "revolver_gold"):
            self.place("gunR", hr, (0.6, 0.0, 0.6 * arm_u))
            if "gunL" in self.weapons:
                self.place("gunL", hl, (0.6, 0.0, -0.6 * arm_u))
        if w == "dynamite" or self.kind == "gang_boss":
            self.place("stick", hr + Vector((0.0, 0.0, -0.03)), (1.4 * arm_u, 0, 0))
            self.show("stick", w == "dynamite" and i < 4)
        j["head"].rotation_euler = (-0.18 + 0.25 * min(1.0, t * 1.4), 0.0, 0.35 * min(1.0, t * 1.4))

    # --- attaques ----------------------------------------------------------
    def pose_attack(self, i: int, n: int) -> None:
        getattr(self, "atk_" + self.A["weapon"].replace("revolver_gold", "boss"))(i)

    def _aim_body(self, lean: float = 0.0, twist: float = 0.0) -> None:
        j = self.j
        j["spine"].rotation_euler = (0.06 + lean, 0, twist)
        j["neck"].rotation_euler = (-0.08 - lean, 0, -twist * 0.6)
        stance = 0.12
        self.legs((0.05, -stance, 0), (-0.10, stance, 0), 0.12, 0.18)

    def atk_knife(self, i: int) -> None:
        self.rest()
        j = self.j
        R, Lp = Vector((-0.8, 0.4, -0.6)), Vector((0.8, 0.5, -0.6))
        # 0-2 élan (accroupi, bras armé en arrière), 3 ruée + entaille, 4 suivi, 5 retour
        crouch = (0.04, 0.09, 0.11, 0.05, 0.03, 0.01)[i]
        j["pelvis"].location.z = self.PZ - crouch
        lean = (0.15, 0.32, 0.36, 0.55, 0.45, 0.2)[i]
        twist = (-0.2, -0.45, -0.5, 0.45, 0.6, 0.15)[i]
        j["spine"].rotation_euler = (lean, 0, twist)
        j["neck"].rotation_euler = (-lean * 0.8, 0, -twist * 0.5)
        stride = (0.2, 0.35, 0.4, 0.9, 0.8, 0.4)[i]
        self.legs((-stride * 0.6, -0.08, 0), (stride * 0.5, 0.10, 0), 0.25 + crouch * 2, 0.5 + crouch * 2)
        hand = [Vector((-0.26, 0.06, 0.14)), Vector((-0.34, 0.20, 0.16)), Vector((-0.35, 0.22, 0.17)),
                Vector((0.08, -0.42, 0.22)), Vector((0.22, -0.30, 0.10)), Vector((-0.12, -0.26, 0.10))][i]
        rot = [(-0.4, 0, 1.6), (-0.5, 0, 2.3), (-0.5, 0, 2.4), (0.1, 0, -0.9), (0.3, 0, -1.4), (-0.3, 0, 0.2)][i]
        self.place("knife", hand, rot)
        self.arm_ik("R", hand, R)
        self.arm_ik("L", [Vector((0.20, -0.25, 0.22)), Vector((0.24, -0.32, 0.26)), Vector((0.24, -0.32, 0.27)),
                          Vector((0.25, 0.05, 0.12)), Vector((0.22, 0.10, 0.10)), Vector((0.16, -0.18, 0.14))][i], Lp)

    def atk_revolver(self, i: int) -> None:
        self.rest()
        aim = (0.4, 0.9, 1.0, 1.0, 1.0, 0.9)[i]
        rr = (0, 0, 0, 1.0, 0.3, 0)[i]
        rl = (0, 0, 0, 0.0, 1.0, 0.2)[i]
        self._aim_body(lean=0.04, twist=0.0)
        self.hold(aim=aim, recoil=rr, recoil_l=rl)

    def atk_boss(self, i: int) -> None:
        self.rest()
        aim = (0.4, 0.9, 1.0, 1.0, 1.0, 0.9)[i]
        rr = (0, 0, 0, 1.0, 0.8, 0.1)[i]
        sw = (None, None, 0.0, 1.0, -0.5, None)[i]
        self._aim_body(lean=0.05, twist=0.1)
        self.hold(aim=aim, recoil=rr, swing_l=sw)

    def atk_shotgun(self, i: int) -> None:
        self.rest()
        aim = (0.5, 0.95, 1.0, 1.0, 0.95, 0.8)[i]
        rc = (0, 0, 0, 1.0, 0.4, 0.1)[i]
        j = self.j
        self._aim_body(lean=0.08 - 0.22 * rc, twist=0.05)
        j["pelvis"].location.y = 0.05 * rc
        self.hold(aim=aim, recoil=rc, swing_l=(0, 0, 0, 0, 1.0, 0.4)[i])

    def atk_carbine(self, i: int) -> None:
        self.rest()
        aim = (0.4, 0.95, 1.0, 1.0, 0.95, 0.85)[i]
        rc = (0, 0, 0, 0.8, 0.2, 0.0)[i]
        self._aim_body(lean=0.05 - 0.12 * rc, twist=0.08)
        self.j["neck"].rotation_euler = (-0.02, 0, 0.12)   # joue contre la crosse
        self.hold(aim=aim, recoil=rc)

    def atk_dynamite(self, i: int) -> None:
        self.rest()
        j = self.j
        R, Lp = Vector((-0.8, 0.4, -0.6)), Vector((0.8, 0.5, -0.6))
        twist = (-0.2, -0.55, -0.6, 0.5, 0.6, 0.2)[i]
        lean = (0.05, -0.12, -0.14, 0.35, 0.35, 0.12)[i]
        j["spine"].rotation_euler = (lean, 0, twist)
        j["neck"].rotation_euler = (-lean, 0, -twist * 0.5)
        self.legs((-0.25, -0.10, 0), (0.30, 0.12, 0), 0.2, 0.35)
        hand = [Vector((-0.24, -0.10, 0.30)), Vector((-0.24, 0.24, 0.56)), Vector((-0.24, 0.26, 0.58)),
                Vector((-0.08, -0.40, 0.48)), Vector((0.10, -0.38, 0.10)), Vector((-0.16, -0.22, 0.10))][i]
        self.place("stick", hand + Vector((0, 0, 0.0)), [(0.2, 0, 0), (-0.8, 0, 0), (-0.9, 0, 0), (1.2, 0, 0),
                                                         (1.6, 0, 0), (0.3, 0, 0)][i])
        self.show("stick", i <= 3 or i == 5)
        self.arm_ik("R", hand, R)
        self.arm_ik("L", [Vector((0.22, -0.20, 0.20)), Vector((0.28, -0.35, 0.36)), Vector((0.28, -0.36, 0.37)),
                          Vector((0.25, 0.08, 0.12)), Vector((0.22, 0.10, 0.10)), Vector((0.17, -0.10, 0.06))][i], Lp)

    def pose_throw(self, i: int, n: int) -> None:
        """Chef : lancer de dynamite de la main gauche, revolver dans la droite."""
        self.rest()
        j = self.j
        Lp = Vector((0.8, 0.5, -0.6))
        self.hold(aim=0.0)
        twist = (0.2, 0.55, 0.6, -0.5, -0.6, -0.2)[i]
        lean = (0.05, -0.12, -0.14, 0.35, 0.35, 0.12)[i]
        j["spine"].rotation_euler = (lean, 0, twist)
        j["neck"].rotation_euler = (-lean, 0, -twist * 0.5)
        self.legs((0.30, -0.12, 0), (-0.25, 0.10, 0), 0.35, 0.2)
        hand = [Vector((0.24, -0.10, 0.30)), Vector((0.24, 0.24, 0.56)), Vector((0.24, 0.26, 0.58)),
                Vector((0.08, -0.40, 0.48)), Vector((-0.10, -0.38, 0.10)), Vector((0.16, -0.22, 0.10))][i]
        self.place("stick", hand, [(0.2, 0, 0), (-0.8, 0, 0), (-0.9, 0, 0), (1.2, 0, 0), (1.6, 0, 0), (0.3, 0, 0)][i])
        self.show("stick", i <= 3)
        self.arm_ik("L", hand, Lp)

    def pose(self, anim: str, i: int, n: int) -> None:
        getattr(self, "pose_" + anim)(i, n)


# ----------------------------------------------------------------------------- rendu

def anims_for(kind: str) -> dict:
    a = dict(ANIMS_BASE)
    if kind == "gang_boss":
        a["throw"] = (6, 12, False)
    return a


def setup_scene(kind: str):
    C.reset_scene()
    C.setup_render((FRAME * SS, FRAME * SS), samples=4, outline_px=4.6)
    o = Outlaw(kind)
    # Grands gabarits : cadrage remonté pour que le chapeau ne sorte jamais du cadre (coup reçu).
    cam = C.ortho_camera(ELEV, ORTHO_H, target=(0, 0, CAM_TARGET_Z + (0.14 if ARCH[kind]["scale"] > 1.1 else 0.0)))
    cam.data.sensor_fit = "VERTICAL"
    return o, cam


def render_frame(path: str):
    big = path + ".big.png"
    C.render_to(big)
    im = C.downscale(big, path, (FRAME, FRAME))
    os.remove(big)
    return im


def point_px(o: Outlaw, cam, ob_name: str, local=(0, 0, 0)) -> tuple[float, float]:
    bpy.context.view_layer.update()
    ob = bpy.data.objects[ob_name]
    p = C.world_to_px(cam, ob.matrix_world @ Vector(local))
    return (round(p[0] / SS, 1), round(p[1] / SS, 1))


def pack(frames: dict, order: list) -> tuple:
    """Empaquette les images rognées (étagères, hauteur décroissante). Renvoie (atlas, régions)."""
    from PIL import Image
    items = []
    for key in order:
        im = frames[key]
        a = im.getchannel("A").point(lambda v: 255 if v > 3 else 0)
        bb = a.getbbox() or (0, 0, 1, 1)
        bb = (max(0, bb[0] - 1), max(0, bb[1] - 1), min(FRAME, bb[2] + 1), min(FRAME, bb[3] + 1))
        items.append((key, im.crop(bb), bb))
    # Positions alignées sur 4 px + marge de 4 px : chaque image occupe ses propres blocs 4x4
    # de compression VRAM (ASTC/BPTC), sans bavure d'une image voisine.
    width = 2048
    srt = sorted(items, key=lambda it: -it[1].size[1])
    x = y = shelf = 0
    pos = {}
    for key, crop, bb in srt:
        w, h = crop.size
        if x + w > width:
            x = 0
            y += (shelf + 4 + 3) // 4 * 4
            shelf = 0
        pos[key] = (x, y)
        x += (w + 4 + 3) // 4 * 4
        shelf = max(shelf, h)
    height = (y + shelf + 3) // 4 * 4
    atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    regions = {}
    for key, crop, bb in items:
        px, py = pos[key]
        atlas.paste(crop, (px, py))
        regions[key] = (px, py, crop.size[0], crop.size[1], bb[0], bb[1])
    return atlas, regions


def compact_png(img, path: str) -> None:
    from PIL import Image
    a = img.getchannel("A").point(lambda v: 0 if v < 4 else v)
    img.putalpha(a)
    q = img.convert("RGBA").quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    q.save(path, optimize=True)


IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="%s"

[params]

compress/mode=2
compress/high_quality=true
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def write_import(kind: str) -> None:
    """Import Godot en compression VRAM (ASTC 4x4 sur mobile, BPTC sur PC) : ~4x moins de mémoire
    vidéo que le RGBA brut, pour 6 archétypes chargés en même temps. Le fichier .import n'est
    écrit que s'il n'existe pas encore (Godot y ajoute ensuite uid et chemins)."""
    path = os.path.join(OUT_DIR, kind, "%s_atlas.png.import" % kind)
    src = "res://assets/sprites/enemies/%s/%s_atlas.png" % (kind, kind)
    if os.path.exists(path):
        with open(path) as f:
            if "compress/mode=2" in f.read():
                return
    with open(path, "w") as f:
        f.write(IMPORT_TEMPLATE % src)


def repack(kind: str) -> None:
    """Refait atlas + SpriteFrames depuis les images déjà rendues (TMP_DIR/<kind>), sans Blender."""
    from PIL import Image
    anims = anims_for(kind)
    tmp = os.path.join(TMP_DIR, kind)
    frames, order = {}, []
    for d in DIRS:
        for anim, (n, _f, _l) in anims.items():
            for i in range(n):
                frames[(anim, d, i)] = Image.open(os.path.join(tmp, "%s_%s_%d.png" % (anim, d, i))).convert("RGBA")
                order.append((anim, d, i))
    atlas, regions = pack(frames, order)
    compact_png(atlas, os.path.join(OUT_DIR, kind, "%s_atlas.png" % kind))
    with open(os.path.join(OUT_DIR, kind, "%s_meta.json" % kind)) as f:
        meta = json.load(f)
    write_tres(kind, anims, regions, meta)
    write_import(kind)
    print("REPACK", kind, atlas.size)


def write_tres(kind: str, anims: dict, regions: dict, meta: dict | None = None) -> None:
    """SpriteFrames ; la méta (même contenu que <kind>_meta.json) est aussi enregistrée dans la
    ressource (metadata/enemy_meta) : les .json ne sont pas inclus dans les exports."""
    rd = "res://assets/sprites/enemies/%s/" % kind
    total = sum(n for n, _f, _l in anims.values()) * len(DIRS)
    lines = ['[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (2 + total), "",
             '[ext_resource type="Texture2D" path="%s%s_atlas.png" id="1_atlas"]' % (rd, kind), ""]
    out = []
    for anim, (n, fps, loop) in anims.items():
        for d in DIRS:
            ids = []
            for c in range(n):
                sid = "A_%s_%s_%d" % (anim, d, c)
                x, y, w, h, ox, oy = regions[(anim, d, c)]
                ids.append(sid)
                lines.append('[sub_resource type="AtlasTexture" id="%s"]' % sid)
                lines.append('atlas = ExtResource("1_atlas")')
                lines.append("region = Rect2(%d, %d, %d, %d)" % (x, y, w, h))
                lines.append("margin = Rect2(%d, %d, %d, %d)" % (ox, oy, FRAME - w, FRAME - h))
                lines.append("filter_clip = true")
                lines.append("")
            fr = ", ".join('{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % s for s in ids)
            out.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s_%s",\n"speed": %.1f\n}'
                       % (fr, "true" if loop else "false", anim, d, float(fps)))
    lines.append("[resource]")
    lines.append("animations = [%s]" % ", ".join(out))
    if meta:
        lines.append("metadata/enemy_meta = %s" % json.dumps(meta, ensure_ascii=False))
    with open(os.path.join(OUT_DIR, kind, "%s_frames.tres" % kind), "w") as f:
        f.write("\n".join(lines) + "\n")


def measure(im) -> tuple:
    bb = im.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
    return bb


def build_kind(kind: str) -> None:
    t0 = time.time()
    o, cam = setup_scene(kind)
    anims = anims_for(kind)
    od = os.path.join(OUT_DIR, kind)
    os.makedirs(od, exist_ok=True)
    tmp = os.path.join(TMP_DIR, kind)
    os.makedirs(tmp, exist_ok=True)
    bpy.context.view_layer.update()
    feet = C.world_to_px(cam, (0, 0, 0))
    feet = (round(feet[0] / SS), round(feet[1] / SS))
    frames = {}
    order = []
    muzzle = {}
    head_px = None
    for d, ang in DIRS.items():
        o.j["root"].rotation_euler = (0, 0, math.radians(ang))
        o.dir_ang = ang
        for anim, (n, _f, _l) in anims.items():
            for i in range(n):
                o.pose(anim, i, n)
                p = os.path.join(tmp, "%s_%s_%d.png" % (anim, d, i))
                frames[(anim, d, i)] = render_frame(p)
                order.append((anim, d, i))
                if anim == "attack" and i == 3:
                    muzzle[d] = muzzle_px(o, cam)
        print(kind, "DIR", d, "%.0fs" % (time.time() - t0), flush=True)
    atlas, regions = pack(frames, order)
    compact_png(atlas, os.path.join(od, "%s_atlas.png" % kind))
    write_import(kind)
    bb = measure(frames[("idle", "s", 0)])
    height_px = bb[3] - bb[1]
    corpse = {}
    for d in DIRS:
        cb = measure(frames[("death", d, anims["death"][0] - 1)])
        corpse[d] = [cb[0], cb[1], cb[2], cb[3]]
    meta = {
        "kind": kind,
        "name": ARCH[kind]["name"],
        "frame_size": [FRAME, FRAME],
        "feet_offset": [feet[0], feet[1]],
        "display_height": round(FRAME * WORLD_PER_PX, 1),
        "world_per_px": WORLD_PER_PX,
        "height_px": height_px,
        "head_px": bb[1],
        "fps": {a: f for a, (_n, f, _l) in anims.items()},
        "frames": {a: n for a, (n, _f, _l) in anims.items()},
        "loop": {a: l for a, (_n, _f, l) in anims.items()},
        "directions": list(DIRS.keys()),
        "attack_hold_frame": 2,
        "attack_strike_frame": 3,
        "muzzle_px": muzzle,
        "corpse_bbox_px": corpse,
        "atlas": "res://assets/sprites/enemies/%s/%s_atlas.png" % (kind, kind),
        "notes": "display_height = hauteur du cadre (frame_size.y px) en unités monde ; scale = "
                 "display_height / frame_size.y. feet_offset = pieds (px depuis le coin haut-gauche du cadre). "
                 "attack : 0-2 élan (2 tenue pendant le télégraphe), 3 coup/tir, 4-5 retour. death : la "
                 "dernière image est le cadavre au sol. muzzle_px = bout du canon / de la lame (image attack 3).",
    }
    with open(os.path.join(od, "%s_meta.json" % kind), "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
        f.write("\n")
    write_tres(kind, anims, regions, meta)
    print("DONE", kind, "%.0fs" % (time.time() - t0), "atlas", atlas.size, flush=True)


def muzzle_px(o: Outlaw, cam) -> list:
    bpy.context.view_layer.update()
    w = o.A["weapon"]
    if w == "knife":
        g, loc = o.weapons["knife"], (0, -0.34, 0)
    elif w in ("shotgun", "carbine"):
        g, loc = o.weapons["long"], (0, -0.66 if w == "shotgun" else -0.72, 0.03)
    elif w == "dynamite":
        g, loc = o.weapons["stick"], (0, 0, 0.1)
    else:
        g, loc = o.weapons["gunR"], (0, -0.24, 0.04)
    p = C.world_to_px(cam, g.matrix_world @ Vector(loc))
    return [round(p[0] / SS, 1), round(p[1] / SS, 1)]


def preview(kinds, dirs, anims_spec) -> None:
    from PIL import Image
    for kind in kinds:
        o, cam = setup_scene(kind)
        tiles = []
        for d in dirs:
            o.j["root"].rotation_euler = (0, 0, math.radians(DIRS[d]))
            o.dir_ang = DIRS[d]
            for a in anims_spec:
                an, i = a.split(":")
                n = anims_for(kind)[an][0]
                o.pose(an, int(i), n)
                p = os.path.join(TMP_DIR, "prev_%s_%s_%s_%s.png" % (kind, an, d, i))
                tiles.append(render_frame(p))
        sheet = Image.new("RGBA", (FRAME * len(tiles), FRAME), (216, 170, 120, 255))
        for k, t in enumerate(tiles):
            sheet.alpha_composite(t, (k * FRAME, 0))
        out = os.path.join(TMP_DIR, "prev_%s.png" % kind)
        sheet.save(out)
        print("PREVIEW", out)


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    kinds = args[args.index("--kinds") + 1].split(",") if "--kinds" in args else KINDS
    os.makedirs(TMP_DIR, exist_ok=True)
    if "--repack" in args:
        for k in kinds:
            repack(k)
        return
    if "--preview" in args:
        dirs = args[args.index("--preview") + 1].split(",")
        anims = args[args.index("--anim") + 1].split(",") if "--anim" in args else ["idle:0"]
        preview(kinds, dirs, anims)
        return
    for k in kinds:
        build_kind(k)


if __name__ == "__main__":
    main()
