"""Bestiaire des Terres gelées (« Le désert de glace ») : modélisation 3D scriptée, rigs, animations,
rendus 8 directions, planches compactes (atlas rogné) + SpriteFrames + méta JSON.

Même pipeline que le héros et les autres bestiaires (art/blender/build_enemies.py,
art/blender/bestiary/mall/) : caméra orthographique 3/4 à 48°, matériaux toon peints, contour
Freestyle, même densité de pixels et même échelle monde (WORLD_PER_PX). Les grands gabarits (ours,
élites, boss) ont un cadre plus grand à la même densité de pixels. Rig humanoïde, araignée et
infrastructure de rendu reprises du bestiaire du centre commercial (copie autonome : aucun import
croisé entre mondes).

Ambiance de la planche : lumière froide et bleutée, glace bleue claire (reflets presque blancs,
ombres bleu nuit), lumières cyan émissives (yeux, cœurs, cristaux) très lisibles sur mobile.

Usage (depuis la racine du projet ; rendus : passer par le verrou flock du projet) :
    flock /home/claude/.blender_render.lock python3 art/blender/bestiary/frozen/build_frozen_bestiary.py
    ... --kinds ice_wolf,ice_bear                              # quelques kinds
    ... --preview s,se --anim idle:0,attack:3 --kinds ice_wolf # aperçu rapide (RDM_TMP)
    ... --repack --kinds ice_wolf                              # atlas + méta depuis les images rendues
    ... --sheet                                                # planche de présentation (captures)

Bestiaire (ids) :
    ice_wolf              Loup des glaces : loup bleu-gris, crête de cristaux de glace, yeux rouges
    ice_spider            Araignée polaire : araignée blindée blanche à tête de bête, yeux rouges
    ice_drone             Drone de froid : sphère blanche volante, grand œil cyan, pinces, pattes pendantes
    ice_bear              Ours des neiges muté : ours crème massif, blessures, cristaux sur le dos
    ice_elemental         Élémentaire de glace : colosse de blocs de glace, cœur cyan
    ice_hunter            Chasseur arctique : soldat en armure grise, lunettes orange, fusil cryogénique
    ice_glacier_guardian  Gardien des glaces (élite) : golem blindé bleu nuit, cristaux, visière cyan
    ice_eternal_mechanic  Mécanicien de l'Éternité (élite) : mécha laiton, œil cyan, canon-outil
    ice_titan             Le Titan de glace (boss) : colosse de glace, couronne de cristaux, noyau

Animations (8 directions) : idle, run, attack, hit, death.
attack : images 0-2 = élan (l'image 2 est tenue pendant le télégraphe), 3 = coup / tir, 4-5 = retour.
death : la dernière image = cadavre au sol (réutilisée par le jeu).

Sortie : assets/sprites/enemies/<kind>/<kind>_atlas.png, <kind>_frames.tres, <kind>_meta.json
"""
from __future__ import annotations

import json
import math
import os
import random
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "..")))
import rdm_common as C  # noqa: E402
import bpy  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "enemies")
CAPT_DIR = os.path.join(ROOT, "docs", "bestiaire", "captures", "frozen")
TMP_DIR = os.environ.get("RDM_TMP", "/tmp/rdm_frozen_bestiary")

SS = 2
ELEV = 48.0
BASE_FRAME = 192
CAM_TARGET_Z = 0.86
# Échelle monde : identique au héros et aux autres bestiaires (92,3 unités pour 160 px).
WORLD_PER_PX = 92.3 / 160.0

DIRS = {"e": 90.0, "se": 45.0, "s": 0.0, "sw": -45.0, "w": -90.0, "nw": -135.0, "n": 180.0, "ne": 135.0}
ANIMS_BASE = {
    "idle": (6, 7, True),
    "run": (8, 14, True),
    "attack": (6, 12, False),
    "hit": (3, 14, False),
    "death": (8, 12, False),
}

# Désert de glace : lumière froide, légèrement bleutée (au lieu du coucher de soleil).
C.WARM = (0.94, 1.00, 1.10)

# ----------------------------------------------------------------------------- matériaux
ICE = ("pat", [("#6cc8f4", "#1a3c96", "#d8f8ff"), ("#48a0e8", "#123282", "#a8e4ff"),
               ("#8edcf8", "#2250a8", "#eefcff")], 4.0)
ICE_DEEP = ("#3a78c8", "#0e2462", "#7ab8f0")
FROST = ("#e4f2ff", "#6a84c0", "#ffffff")
COMMON_MATS = {
    "eye": ("#0c1020", None, None),
    "metal": ("#8a94a8", "#26304e", "#d6e0f0"),
    "metal_dark": ("#32384a", "#0e1220", "#5a6278"),
    "nose": ("#141418", "#040406", "#3a3a44"),
    "teeth": ("#eef2f8", "#6a7898", "#ffffff"),
    "tongue": ("#b0384a", "#3a1022", "#e0606e"),
    "ice": ICE,
    "ice_deep": ICE_DEEP,
    "frost": FROST,
    "glow": "!#7ff4ff",
    "core": "!#c4faff",
    "joint": ("#262c40", "#080a16", "#454d66"),
    "strap": ("#2a2c36", "#0a0a10", "#484a58"),
}

SPEC: dict[str, dict] = {
    "ice_wolf": {
        "name": "Loup des glaces", "rig": "quad", "frame": 224, "scale": 1.42, "fps_run": 16,
        "withers": 0.64, "hips": 0.56, "length": 0.92, "chest": (0.19, 0.23), "rump": (0.15, 0.17),
        "neck": 0.22, "neck_r": 0.115, "head": 0.16, "snout": 0.19, "snout_r": 0.07,
        "leg_r": 0.056, "front_leg": (0.25, 0.22, 0.12), "hind_leg": (0.22, 0.21, 0.14),
        "ears": "pointed", "tail": "bushy", "teeth": True, "head_down": 0.15, "jaw_idle": 0.22,
        "crystals": "spine",
        "mats": {
            "fur": ("pat", [("#6f8cbc", "#1a2452", "#b8d4f4"), ("#5674a6", "#141c46", "#94b4e2"),
                            ("#8aa6d0", "#202c5c", "#d0e4fa")], 6.0),
            "fur_dark": ("#2e4474", "#0c1434", "#56709e"),
            "belly": ("#c8daf0", "#4a5a8a", "#f2f8ff"),
            "muzzle": ("#2a3450", "#0a0e20", "#46557a"),
            "eye_glow": "!#ff6a3a",
        },
    },
    "ice_spider": {
        "name": "Araignée polaire", "rig": "spider", "frame": 224, "scale": 1.24, "fps_run": 18,
        "legs": 4, "body_z": 0.42, "femur": 0.58, "tibia": 0.70, "spread": 0.84,
        "mats": {
            "carapace": ("pat", [("#a8b4c6", "#2a3458", "#e6eef8"), ("#8692a8", "#1e2648", "#c4cee0")], 5.0),
            "fur": ("#dfe6ee", "#4a5478", "#ffffff"),
            "leg": ("#aab4c6", "#2c3456", "#e4eaf4"),
            "leg_tip": ("#56627c", "#141a32", "#8892ae"),
            "glow": "!#8ef2ff",
            "glow_soft": "!#c8f8ff",
            "red_glow": "!#ff3a2e",
            "eye_glow": "!#ff3226",
            "fang": ("#eef2f8", "#6a7898", "#ffffff"),
        },
    },
    "ice_drone": {
        "name": "Drone de froid", "rig": "drone", "frame": 192, "scale": 1.38, "fps_run": 12, "hover": 0.80,
        "mats": {
            "shell": ("#d4dce8", "#36426a", "#ffffff"),
            "shell_dark": ("#4a5676", "#121a36", "#76829e"),
            "eye_glow": "!#36c4ff",
            "eye_core": "!#effdff",
            "light": "!#7ff4ff",
        },
    },
    "ice_bear": {
        "name": "Ours des neiges muté", "rig": "quad", "frame": 256, "scale": 1.72, "fps_run": 11, "heavy": 1.0,
        "withers": 0.70, "hips": 0.64, "length": 1.00, "chest": (0.27, 0.29), "rump": (0.25, 0.27),
        "neck": 0.16, "neck_r": 0.16, "head": 0.19, "snout": 0.15, "snout_r": 0.09,
        "leg_r": 0.088, "front_leg": (0.27, 0.22, 0.10), "hind_leg": (0.25, 0.20, 0.12),
        "ears": "round", "tail": "stub", "teeth": True, "head_down": 0.30, "jaw_idle": 0.28,
        "crystals": "hump", "wounds": True, "dark_snout": True,
        "mats": {
            "fur": ("pat", [("#e2d6c0", "#585878", "#fff8ea"), ("#c8b8a0", "#46446a", "#ece0c8"),
                            ("#d6c8b0", "#504e72", "#f6ecd8")], 5.0),
            "fur_dark": ("#a8987e", "#383656", "#cfc0a4"),
            "belly": ("#eee6d6", "#64647e", "#ffffff"),
            "muzzle": ("#3a3238", "#100c14", "#5a4e56"),
            "wound": ("#a01e2a", "#3a0618", "#d03a44"),
            "eye_glow": "!#ff5a3a",
        },
    },
    "ice_elemental": {
        "name": "Élémentaire de glace", "rig": "human", "frame": 256, "scale": 1.28, "head": 0.92, "leg": 0.78,
        "torso": (1.42, 1.16), "arm": 1.50, "arm_len": 1.14, "hunch": 0.26, "fps_run": 10, "stride": 0.6,
        "top_key": "ice",
        "mats": {
            "skin": "ice", "shirt": "ice", "pants": "ice_deep", "shoe": "ice_deep",
            "eye_glow": "!#8ff8ff",
        },
    },
    "ice_hunter": {
        "name": "Chasseur arctique", "rig": "human", "frame": 192, "scale": 1.05, "head": 1.12, "leg": 0.84,
        "torso": (1.14, 1.06), "arm": 1.12, "arm_len": 1.0, "hunch": 0.08, "fps_run": 15,
        "top_key": "suit", "sleeve_key": "suit", "hand_key": "glove",
        "mats": {
            "armor": ("#4a5468", "#10141e", "#7a86a0"),
            "armor_dark": ("#262b38", "#0a0c12", "#424a5e"),
            "suit": ("pat", [("#5a6480", "#161c32", "#8a96b4"), ("#4c5670", "#12182c", "#76829e")], 6.0),
            "pants": ("pat", [("#4c5670", "#12182c", "#76829e"), ("#424a62", "#0e1428", "#68748e")], 6.0),
            "shoe": ("#22252e", "#08080c", "#3e424e"),
            "glove": ("#2a2e38", "#0a0a10", "#484c58"),
            "fur": ("#d8d2c4", "#5c5a72", "#fffaf0"),
            "visor": "!#ff8a2a",
            "gun": ("#2c303c", "#0a0a12", "#525868"),
            "cryo": "!#5ff0ff",
            "skin": ("#c89a80", "#5a3e4e", "#ecc0a2"),
        },
    },
    "ice_glacier_guardian": {
        "name": "Gardien des glaces", "rig": "human", "frame": 288, "scale": 1.62, "head": 0.92, "leg": 0.78,
        "torso": (1.50, 1.22), "arm": 1.55, "arm_len": 1.12, "hunch": 0.16, "fps_run": 10, "stride": 0.55,
        "mats": {
            "armor": ("pat", [("#3c5888", "#0e1838", "#7294cc"), ("#334c7a", "#0c1430", "#6282bc")], 5.0),
            "armor_dark": ("#1c2846", "#070b1c", "#34446a"),
            "visor": "!#8ff6ff",
            "pants": "armor_dark", "shoe": "armor_dark", "skin": "armor", "shirt": "armor",
        },
    },
    "ice_eternal_mechanic": {
        "name": "Mécanicien de l'Éternité", "rig": "human", "frame": 256, "scale": 1.36, "head": 0.98, "leg": 0.80,
        "torso": (1.42, 1.22), "arm": 1.40, "arm_len": 1.06, "hunch": 0.12, "fps_run": 11, "stride": 0.6,
        "mats": {
            "armor": ("pat", [("#c48c3c", "#4a2a2e", "#f4c674"), ("#a8742e", "#3c2228", "#dca85a")], 5.0),
            "armor_dark": ("#3a3644", "#0e0a14", "#5e5a6c"),
            "visor": "!#5ee8ff",
            "gun": ("#2c2e3a", "#0a0a12", "#4e505e"),
            "spark": "!#ffb040",
            "pants": "armor_dark", "shoe": "armor_dark", "skin": "armor", "shirt": "armor",
        },
    },
    "ice_titan": {
        "name": "Le Titan de glace", "rig": "human", "frame": 384, "scale": 2.45, "head": 0.86, "leg": 0.80,
        "torso": (1.52, 1.20), "arm": 1.62, "arm_len": 1.16, "hunch": 0.22, "fps_run": 9, "stride": 0.5,
        "top_key": "ice", "out_scale": 0.72, "cam_dz": 0.0,
        "anims": {"idle": (4, 6, True), "run": (6, 9, True), "death": (6, 9, False)},
        "mats": {
            "skin": "ice", "shirt": "ice", "pants": "ice_deep", "shoe": "ice_deep",
            "eye_glow": "!#a8faff",
            "armor_dark": ("#22346a", "#0a1032", "#46609c"),
        },
    },
}
KINDS = list(SPEC.keys())
CLASSICS = KINDS[:6]


def frame_of(kind: str) -> int:
    """Cadre de rendu (px, densité du héros)."""
    return int(SPEC[kind].get("frame", BASE_FRAME))


def out_frame(kind: str) -> int:
    """Cadre stocké dans l'atlas : `out_scale` < 1 réduit la résolution des très grands gabarits
    (boss) pour garder l'atlas sous 8192 px (mobile) ; l'échelle monde est compensée dans la méta."""
    return int(round(frame_of(kind) * float(SPEC[kind].get("out_scale", 1.0)) / 4.0)) * 4


def out_k(kind: str) -> float:
    return out_frame(kind) / float(frame_of(kind))


def joint(name: str, parent, loc) -> bpy.types.Object:
    e = C.empty(name, loc, parent)
    e.rotation_mode = "XYZ"
    return e


def qjoint(name: str, parent, loc) -> bpy.types.Object:
    e = C.empty(name, loc, parent)
    e.rotation_mode = "QUATERNION"
    return e


def ik2(S: Vector, T: Vector, pole: Vector, l1: float, l2: float):
    """IK 2 os : renvoie (coude, extrémité) pour une épaule S, une cible T et un pôle."""
    d = T - S
    dist = min(max(d.length, 0.05), (l1 + l2) * 0.995)
    u = d.normalized() if d.length > 1e-6 else Vector((0, 0, -1))
    a = (l1 ** 2 + dist ** 2 - l2 ** 2) / (2 * dist)
    h = math.sqrt(max(l1 ** 2 - a * a, 0.0))
    p = pole - u * pole.dot(u)
    p = p.normalized() if p.length > 1e-5 else Vector((0, 1, 0))
    return S + u * a + p * h, S + u * dist


DOWN = Vector((0, 0, -1))


def corpse_twist(dir_ang_deg: float) -> float:
    best = None
    for target in (20.0, 160.0, -20.0, -160.0):
        tau = (target - (dir_ang_deg + 90.0) + 180.0) % 360.0 - 180.0
        if best is None or abs(tau) < abs(best):
            best = tau
    return math.radians(best)


def smooth(u: float) -> float:
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


# =============================================================================== base
class Rig:
    def __init__(self, kind: str) -> None:
        self.kind = kind
        self.S = SPEC[kind]
        self.dir_ang = 0.0
        self.j: dict[str, bpy.types.Object] = {}
        self.parts: list[tuple[bpy.types.Object, str]] = []
        self.grp: dict[str, list[bpy.types.Object]] = {}
        self.ph = C.toon("_ph_" + kind, "#ff00ff")
        self.rng = random.Random(7)
        self.muzzle_ref: tuple[str, tuple] | None = None
        self.build()
        self.apply_mats()

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
        spec.update(self.S["mats"])
        mats = {}
        for key, sp in spec.items():
            if isinstance(sp, str) and not sp.startswith("!"):
                sp = spec[sp]
            name = "%s_%s" % (self.kind, key)
            if isinstance(sp, str) and sp.startswith("!"):
                mats[key] = C.toon(name, sp[1:], emit=1.7)
            elif sp[0] == "pat":
                mats[key] = C.toon_pattern(name, sp[1], scale=sp[2], thresholds=(0.55, 0.62), rim=0.22)
            elif key in ("eye", "face"):
                mats[key] = C.toon(name, sp[0], sp[1], sp[2], rim=0.0, band=0.25)
            else:
                mats[key] = C.toon(name, sp[0], sp[1], sp[2], rim=0.26)
        fallback = next(iter(mats.values()))
        for ob, key in self.parts:
            ob.data.materials[0] = mats.get(key, fallback)

    def pose(self, anim: str, i: int, n: int) -> None:
        getattr(self, "pose_" + anim)(i, n)

    def muzzle_world(self) -> Vector:
        name, loc = self.muzzle_ref
        ob = bpy.data.objects[name]
        return ob.matrix_world @ Vector(loc)


# =============================================================================== humanoïdes
L_UP, L_LOW = 0.20, 0.225


class Human(Rig):
    """Humanoïde générique (proportions héroïques) : bassin, colonne, tête, jambes, bras en IK."""

    def build(self) -> None:
        S = self.S
        self.LEG = S["leg"]
        self.PZ = 0.80 - 0.77 * (1 - self.LEG)
        self.HS = S["head"]
        self.TW, self.TD = S["torso"]
        self.AW = S["arm"]
        self.AL = S.get("arm_len", 1.0)
        self.HUNCH = S.get("hunch", 0.0)
        self.BELLY = S.get("belly", 0.0)
        self.lu, self.ll = L_UP * self.AL, L_LOW * self.AL
        j = self.j
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["body"] = body = joint("body", root, (0, 0, 0))
        body.scale = (S["scale"],) * 3
        j["pelvis"] = pelvis = joint("pelvis", body, (0, 0, self.PZ))
        j["spine"] = spine = joint("spine", pelvis, (0, 0, 0.08))
        j["neck"] = neck = joint("neck", spine, (0, 0, 0.45))
        j["head"] = head = joint("head", neck, (0, 0, 0.0))
        head.scale = (self.HS,) * 3
        self.shoulder = {"L": Vector((0.245 * self.TW ** 0.6, 0.0, 0.33 + 0.03 * (self.TW - 1))),
                         "R": Vector((-0.245 * self.TW ** 0.6, 0.0, 0.33 + 0.03 * (self.TW - 1)))}
        self.build_legs(pelvis)
        self.build_torso(pelvis, spine)
        self.build_arms(spine)
        self.build_head(head)
        self.dress()

    # -- géométrie de base ---------------------------------------------------
    def build_legs(self, pelvis) -> None:
        j, LEG = self.j, self.LEG
        bw = 1.0 + 0.25 * (self.TW - 1.0)
        pants = self.S.get("pants_key", "pants")
        for side, sx in (("L", 1), ("R", -1)):
            hip = j["hip" + side] = joint("hip" + side, pelvis, (0.115 * sx * bw, 0, -0.02))
            knee = j["knee" + side] = joint("knee" + side, hip, (0, 0, -0.36 * LEG))
            self.part("thigh" + side, C.bm_xform(C.bm_cyl(12, 0.122 * bw, 0.098 * bw, 0.40),
                      loc=(0, 0, -0.17), scale=(1, 1, LEG)), pants, hip)
            self.part("shin" + side, C.bm_xform(C.bm_cyl(12, 0.098 * bw, 0.082 * bw, 0.30 * LEG),
                      loc=(0, 0, LEG * -0.15)), self.S.get("shin_key", pants), knee)
            fz = -0.345 + 0.41 * (1 - LEG)
            foot = C.bm_sphere(12, 8, 1.0)
            C.bm_xform(foot, loc=(0, -0.06, fz + 0.01), scale=(0.09 * bw, 0.15 * bw, 0.065))
            self.part("foot" + side, foot, "shoe", knee)
            self.foot_z = fz

    def build_torso(self, pelvis, spine) -> None:
        tw, td, belly = self.TW, self.TD, self.BELLY
        top = self.S.get("top_key", "shirt")
        self.part("hips", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, 0, -0.01),
                  scale=(0.22 * tw ** 0.8, 0.16 * td, 0.15)), self.S.get("pants_key", "pants"), pelvis)
        tz = [0.00, 0.15, 0.29, 0.38, 0.45]
        rx = [0.185, 0.200, 0.232, 0.222, 0.110]
        ry = [0.135, 0.145, 0.155, 0.142, 0.092]
        secs = []
        for k in range(5):
            bulge = belly * 0.06 * (1.0 if k in (0, 1) else 0.3 if k == 2 else 0.0)
            secs.append(C.ellipse(0, -bulge * 0.6, tz[k], rx[k] * tw + bulge * 0.4, ry[k] * td + bulge, 18))
        self.part("torso", C.bm_loft(secs), top, spine)
        if belly > 0.3:
            self.part("belly", C.bm_xform(C.bm_sphere(14, 9, 1.0), loc=(0, -0.10 * td, 0.08),
                      scale=(0.20 * tw, 0.13 * td, 0.17)), top, spine)

    def build_arms(self, spine) -> None:
        j = self.j
        aw, al = self.AW, self.AL
        sleeve = self.S.get("sleeve_key", "skin")
        for side, sx in (("L", 1), ("R", -1)):
            ua = j["ua" + side] = qjoint("ua" + side, spine, self.shoulder[side])
            fa = j["fa" + side] = qjoint("fa" + side, spine, (0, 0, 0))
            self.part("shoulder" + side, C.bm_xform(C.bm_sphere(12, 8, 0.105 * aw), loc=(0, 0, -0.01)),
                      self.S.get("shoulder_key", sleeve), ua)
            self.part("uarm" + side, C.bm_xform(C.bm_cyl(12, 0.094 * aw, 0.080 * aw, 0.20 * al),
                      loc=(0, 0, -0.10 * al)), sleeve, ua)
            self.part("farm" + side, C.bm_xform(C.bm_cyl(10, 0.080 * aw, 0.066 * aw, 0.17 * al),
                      loc=(0, 0, -0.08 * al)), self.S.get("farm_key", sleeve), fa)
            hand = C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, 0, -self.ll + 0.012),
                              scale=(0.078 * aw, 0.072 * aw, 0.085 * aw))
            self.part("hand" + side, hand, self.S.get("hand_key", "skin"), fa)

    def skull(self, head, key="skin", sx=0.180, sy=0.172, sz=0.190, jaw=0.22):
        sk = C.bm_sphere(22, 16, 1.0)
        for v in sk.verts:
            x, y, z = v.co
            if z < 0:
                x *= 1.0 + 0.04 * (-z) - jaw * (-z) ** 2
                y *= 1.0 - 0.06 * (-z)
            v.co = Vector((x * sx, y * sy, z * sz)) + Vector((0, 0, 0.200))
        return self.part("skull", sk, key, head)

    def eyes(self, head, key="eye_glow", z=0.232, x=0.065, y=-0.158, r=(0.030, 0.012, 0.024), brow=True,
             brow_key="eye", angle=0.38):
        for sx in (1, -1):
            self.part("eye", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(x * sx, y, z), scale=r),
                      key, head, nofs=True)
            if brow:
                self.part("brow", C.bm_xform(C.bm_box(0.08, 0.026, 0.026, bevel=0.006),
                          loc=(x * sx, y - 0.004, z + 0.048), rot=(0, -angle * sx, 0)), brow_key, head)

    def build_head(self, head) -> None:
        self.skull(head)
        self.eyes(head)
        self.part("nose", C.bm_xform(C.bm_sphere(10, 7, 1.0), loc=(0, -0.172, 0.180),
                  scale=(0.032, 0.03, 0.034)), "skin", head)

    def dress(self) -> None:
        pass

    # -- poses -------------------------------------------------------------
    def rest(self) -> None:
        for name, ob in self.j.items():
            if name in ("root",) or name.startswith(("ua", "fa", "w_")) or ob.rotation_mode != "XYZ":
                continue
            ob.rotation_euler = (0, 0, 0)
        self.j["body"].location = (0, 0, 0)
        self.j["pelvis"].location = (0, 0, self.PZ)
        self.j["head"].rotation_euler = (-0.18 + self.HUNCH * 0.6, 0, 0)
        for name in self.grp:
            self.show(name, True)

    def arm_ik(self, side: str, target: Vector, pole: Vector) -> None:
        S = self.j["ua" + side].location.copy()
        E, H = ik2(S, Vector(target), Vector(pole), self.lu, self.ll)
        ua, fa = self.j["ua" + side], self.j["fa" + side]
        ua.rotation_quaternion = DOWN.rotation_difference((E - S).normalized())
        fa.location = E
        fa.rotation_quaternion = DOWN.rotation_difference((H - E).normalized())

    def legs(self, hipL, hipR, kneeL, kneeR) -> None:
        j = self.j
        j["hipL"].rotation_euler = hipL
        j["hipR"].rotation_euler = hipR
        j["kneeL"].rotation_euler = (kneeL, 0, 0)
        j["kneeR"].rotation_euler = (kneeR, 0, 0)

    def spine_rot(self, x=0.0, y=0.0, z=0.0) -> None:
        self.j["spine"].rotation_euler = (x + self.HUNCH, y, z)
        self.j["neck"].rotation_euler = (-0.6 * self.HUNCH - 0.5 * x, -0.4 * y, -0.5 * z)

    R_POLE = Vector((-0.8, 0.4, -0.6))
    L_POLE = Vector((0.8, 0.5, -0.6))

    def arms_rest(self, b: float = 0.0) -> None:
        """Bras au repos (surchargé par les archétypes)."""
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.05, -0.04, -0.40 * self.AL + 0.01 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.05, -0.04, -0.40 * self.AL + 0.01 * b)), self.R_POLE)

    def arms_run(self, s: float) -> None:
        sh = self.shoulder
        for side, sx, k in (("L", 1, -1), ("R", -1, 1)):
            sw = Vector((0.06 * sx, 0.24 * s * k * self.AL - 0.05, -0.30 * self.AL + 0.07 * abs(s)))
            self.arm_ik(side, sh[side] + sw, self.L_POLE if sx > 0 else self.R_POLE)

    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        t = 2 * math.pi * i / n
        b = math.sin(t)
        sway = math.sin(t + 0.6)
        heavy = 1.0 + 0.6 * self.BELLY
        j["pelvis"].location.z = self.PZ - 0.012 * (1 - b) * 0.5 * heavy
        j["pelvis"].rotation_euler = (0, 0.012 * sway, 0.03 * sway)
        self.spine_rot(0.03 + 0.016 * b, -0.02 * sway, 0)
        j["spine"].scale = (1 + 0.012 * b, 1 + 0.012 * b, 1 + 0.014 * b)
        stance = 0.07 + 0.05 * (self.TW - 1.0)
        self.legs((0.03, -stance - 0.012 * sway, 0), (-0.03, stance - 0.012 * sway, 0), 0.07 + 0.1 * self.HUNCH,
                  0.09 + 0.1 * self.HUNCH)
        self.arms_rest(b)
        self.idle_extra(t)

    def idle_extra(self, t: float) -> None:
        pass

    def pose_run(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        p = 2 * math.pi * i / n
        s = math.sin(p)
        amp = self.S.get("stride", 0.85)
        PZ = self.PZ
        j["pelvis"].location.z = PZ - 0.045 + 0.060 * abs(math.sin(p + 0.35))
        j["pelvis"].rotation_euler = (0, 0, -0.16 * s)
        self.spine_rot(0.24, 0, 0.18 * s)
        self.legs((-amp * s - 0.15, 0, 0), (amp * s - 0.15, 0, 0),
                  0.20 + 1.35 * max(0.0, math.sin(p - 1.0)) ** 1.2,
                  0.20 + 1.35 * max(0.0, math.sin(p - 1.0 + math.pi)) ** 1.2)
        self.arms_run(s)
        self.run_extra(p)

    def run_extra(self, p: float) -> None:
        pass

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        k = (1.0, 0.6, 0.25)[i]
        j["pelvis"].location.z = self.PZ - 0.03 * k
        j["pelvis"].location.y = 0.04 * k
        self.spine_rot(-0.34 * k, 0, 0.12 * k)
        self.legs((0.12 * k, -0.10, 0), (-0.20 * k, 0.10, 0), 0.12 + 0.14 * k, 0.12)
        sh = self.shoulder
        self.arm_ik("L", sh["L"] + Vector((0.12, -0.06 - 0.08 * k, -0.30 + 0.10 * k)), self.L_POLE)
        self.arm_ik("R", sh["R"] + Vector((-0.12, -0.06 - 0.08 * k, -0.30 + 0.10 * k)), self.R_POLE)
        self.hit_extra(k)

    def hit_extra(self, k: float) -> None:
        pass

    def pose_death(self, i: int, n: int) -> None:
        """Chute sur le dos ; dernière image = cadavre au sol (pose stable, bras écartés)."""
        self.rest()
        j = self.j
        t = i / (n - 1)
        if t < 0.25:
            u = t / 0.25
            fall = 0.08 * u
            self.spine_rot(-0.45 * u - self.HUNCH * u, 0, 0.15 * u)
            self.legs((0.15 * u, -0.10, 0), (-0.25 * u, 0.12, 0), 0.25 * u, 0.15)
        else:
            u = min(1.0, (t - 0.25) / 0.55)
            e = smooth(u)
            bounce = 0.0
            if t > 0.8:
                v = (t - 0.8) / 0.2
                bounce = 0.06 * math.sin(v * math.pi) * (1 - v)
            fall = 0.08 + (math.pi / 2 - 0.08) * e - bounce
            self.spine_rot(-0.45 + 0.45 * e - self.HUNCH, 0, 0.15 - 0.10 * e)
            self.legs((0.15 + 0.35 * math.sin(u * math.pi), -0.12 - 0.08 * e, 0),
                      (-0.25 + 0.25 * e, 0.14 + 0.10 * e, 0),
                      0.25 + 0.7 * math.sin(u * math.pi) * (1 - 0.6 * e) + 0.35 * e, 0.15 - 0.05 * e)
        body = j["body"]
        k = fall / (math.pi / 2)
        tau = corpse_twist(self.dir_ang) * min(1.0, k * 1.2)
        body.rotation_euler = (-fall, 0, tau)
        sc = self.S["scale"]
        body.location = Euler((0, 0, tau)).to_matrix() @ Vector((0, -0.72 * sc * k, 0.16 * sc * k ** 2))
        arm_u = min(1.0, t / 0.6)
        sh = self.shoulder
        hl = sh["L"] + Vector((0.06 + 0.15 * arm_u, -0.05 + 0.10 * arm_u, -0.03 + 0.25 * arm_u))
        hr = sh["R"] + Vector((-0.10 - 0.15 * arm_u, -0.10 + 0.08 * arm_u, -0.07 + 0.30 * arm_u))
        self.arm_ik("L", hl, Vector((0.8, 0.2, -0.6)))
        self.arm_ik("R", hr, Vector((-0.8, 0.2, -0.6)))
        j["head"].rotation_euler = (-0.18 + 0.25 * min(1.0, t * 1.4), 0.0, 0.35 * min(1.0, t * 1.4))
        self.death_extra(t)

    def death_extra(self, t: float) -> None:
        pass

    def pose_attack(self, i: int, n: int) -> None:
        raise NotImplementedError


# ------------------------------------------------------------------------------- zombie


# =============================================================================== araignée (rig du centre commercial)
class Spider(Rig):
    """Araignée : céphalothorax + abdomen lumineux, 8 pattes en IK (2 os)."""

    def build(self) -> None:
        S = self.S
        j = self.j
        self.BZ = S["body_z"]
        self.L1, self.L2 = S["femur"], S["tibia"]
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["body"] = body = joint("body", root, (0, 0, 0))
        body.scale = (S["scale"],) * 3
        j["thorax"] = th = joint("thorax", body, (0, 0, self.BZ))
        j["abd"] = abd = joint("abd", th, (0, 0.16, 0.04))
        j["fangs"] = fangs = joint("fangs", th, (0, -0.24, -0.02))
        # céphalothorax
        self.part("thoraxM", C.bm_xform(C.bm_sphere(18, 12, 1.0), scale=(0.20, 0.24, 0.13)), "carapace", th)
        self.part("headM", C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, -0.20, 0.02), scale=(0.13, 0.11, 0.10)),
                  "carapace", th)
        # abdomen : grosse goutte, motif lumineux en chevrons
        ab = C.bm_sphere(20, 14, 1.0)
        for v in ab.verts:
            x, y, z = v.co
            k = 1.0 + 0.25 * y
            v.co = Vector((x * 0.30 * k, y * 0.38 + 0.30, z * 0.26 * k + 0.08))
        self.part("abdomen", ab, "carapace", abd)
        for k in range(4):
            y = 0.18 + 0.12 * k
            w = 0.20 - 0.03 * k
            self.part("chev%d" % k, C.bm_tube([(-w, y + 0.04, 0.26 - 0.02 * k), (0, y - 0.03, 0.33 - 0.03 * k),
                                               (w, y + 0.04, 0.26 - 0.02 * k)], [0.022, 0.026, 0.022], seg=6, flat=0.5),
                      "glow", abd, nofs=True)
        self.part("spot", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, 0.66, 0.16), scale=(0.07, 0.05, 0.06)),
                  "glow_soft", abd, nofs=True)
        for sx in (1, -1):
            for k in range(3):
                self.part("dot", C.bm_xform(C.bm_sphere(8, 6, 0.03), loc=(0.20 * sx - 0.03 * sx * k, 0.22 + 0.13 * k,
                          0.24 - 0.03 * k)), "glow", abd, nofs=True)
        # yeux (grappe rouge-rose)
        for (x, z, r) in ((0.045, 0.07, 0.030), (-0.045, 0.07, 0.030), (0.085, 0.05, 0.020), (-0.085, 0.05, 0.020),
                          (0.03, 0.105, 0.016), (-0.03, 0.105, 0.016)):
            self.part("eye", C.bm_xform(C.bm_sphere(10, 6, r), loc=(x, -0.29, z)), "eye_glow", th, nofs=True)
        # chélicères / crocs
        for sx in (1, -1):
            self.part("chel", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0.04 * sx, -0.04, -0.02),
                      scale=(0.045, 0.05, 0.06)), "carapace", fangs)
            self.part("fang", C.bm_tube([(0.04 * sx, -0.07, -0.05), (0.03 * sx, -0.10, -0.12), (0.0, -0.08, -0.17)],
                                        [0.022, 0.014, 0.0], seg=6), "fang", fangs)
        # pattes
        self.legs_def = []
        n = S["legs"]
        for side, sx in (("L", 1), ("R", -1)):
            for k in range(n):
                ang = math.radians(-55 + 110 * k / (n - 1))   # -55° (avant) .. +55° (arrière)
                hip = Vector((0.13 * sx, -0.14 + 0.09 * k, 0.0))
                spread = S["spread"] * (1.0 if k in (0, n - 1) else 0.92)
                rest = Vector((sx * math.cos(ang) * spread, math.sin(ang) * spread * 1.05 - 0.05, 0.0))
                name = "%s%d" % (side, k)
                u = qjoint("leg_u" + name, th, hip)
                lo = qjoint("leg_l" + name, th, (0, 0, 0))
                self.part("femur" + name, C.bm_tube([(0, 0, 0), (0, 0, -self.L1 * 0.5), (0, 0, -self.L1)],
                                                    [0.050, 0.046, 0.040], seg=8), "leg", u)
                self.part("knee" + name, C.bm_xform(C.bm_sphere(8, 6, 0.046), loc=(0, 0, 0)), "glow_soft", lo, nofs=True)
                self.part("tibia" + name, C.bm_tube([(0, 0, 0), (0, 0, -self.L2 * 0.55), (0, 0, -self.L2 * 0.9),
                                                     (0, 0, -self.L2)], [0.040, 0.032, 0.016, 0.0], seg=8), "leg_tip", lo)
                self.part("band" + name, C.bm_xform(C.bm_cyl(8, 0.036, 0.036, 0.03), loc=(0, 0, -self.L2 * 0.45)),
                          "glow", lo, nofs=True)
                self.legs_def.append({"name": name, "u": u, "l": lo, "hip": hip, "rest": rest, "sx": sx, "k": k,
                                      "phase": 0.0 if (k + (0 if sx > 0 else 1)) % 2 == 0 else math.pi})
        self.muzzle_ref = ("fang", (0.0, -0.08, -0.17))

    def place_legs(self, feet: dict, pole_up: float = 1.0) -> None:
        bpy.context.view_layer.update()
        th = self.j["thorax"]
        inv = th.matrix_basis.inverted()
        for L in self.legs_def:
            T = inv @ feet[L["name"]]
            S = L["hip"]
            pole = Vector((L["sx"] * 0.4, 0.0, pole_up))
            E, H = ik2(S, T, pole, self.L1, self.L2)
            L["u"].rotation_quaternion = DOWN.rotation_difference((E - S).normalized())
            L["l"].location = E
            L["l"].rotation_quaternion = DOWN.rotation_difference((H - E).normalized())

    def rest(self) -> None:
        th = self.j["thorax"]
        th.location = (0, 0, self.BZ)
        th.rotation_euler = (0, 0, 0)
        self.j["abd"].rotation_euler = (0, 0, 0)
        self.j["fangs"].rotation_euler = (0, 0, 0)
        self.j["body"].location = (0, 0, 0)
        self.j["body"].rotation_euler = (0, 0, 0)

    def feet_rest(self, lift: dict | None = None) -> dict:
        out = {}
        for L in self.legs_def:
            out[L["name"]] = Vector(L["rest"])
        return out

    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        t = 2 * math.pi * i / n
        th = self.j["thorax"]
        th.location.z = self.BZ - 0.015 * (1 + math.sin(t))
        self.j["abd"].rotation_euler = (0.06 * math.sin(t + 0.5), 0, 0.04 * math.sin(t))
        self.j["fangs"].rotation_euler = (0.15 * max(0.0, math.sin(t * 2)), 0, 0)
        feet = self.feet_rest()
        # une patte avant tâte le sol
        fl = feet["L0"]
        feet["L0"] = fl + Vector((0, -0.04 * math.sin(t), 0.08 * max(0.0, math.sin(t))))
        self.place_legs(feet)

    def pose_run(self, i: int, n: int) -> None:
        self.rest()
        p = 2 * math.pi * i / n
        th = self.j["thorax"]
        th.location.z = self.BZ - 0.03 + 0.02 * abs(math.sin(2 * p))
        th.rotation_euler = (0.05, 0, 0.05 * math.sin(p))
        self.j["abd"].rotation_euler = (0.08 * math.sin(2 * p), 0, -0.06 * math.sin(p))
        feet = {}
        stride = 0.16
        for L in self.legs_def:
            u = p + L["phase"]
            r = Vector(L["rest"])
            feet[L["name"]] = r + Vector((0, stride * math.cos(u), 0.12 * max(0.0, math.sin(u))))
        self.place_legs(feet)

    def pose_attack(self, i: int, n: int) -> None:
        # se cabre (0-2), pattes avant levées, plonge et mord (3), retombe (4-5)
        self.rest()
        th = self.j["thorax"]
        rear = (0.25, 0.50, 0.58, -0.18, -0.10, 0.05)[i]
        fw = (0.02, 0.06, 0.07, -0.22, -0.16, -0.04)[i]
        th.rotation_euler = (-rear, 0, 0)
        th.location = (0, fw, self.BZ + 0.10 * max(0.0, rear) - 0.06 * max(0.0, -rear))
        self.j["fangs"].rotation_euler = ((0.0, 0.2, 0.35, -0.5, -0.3, 0.0)[i], 0, 0)
        self.j["abd"].rotation_euler = (0.3 * rear, 0, 0)
        feet = self.feet_rest()
        for L in self.legs_def:
            if L["k"] <= 1:
                r = Vector(L["rest"])
                if i < 3:
                    feet[L["name"]] = r + Vector((0.0, -0.10 * L["k"] + 0.05, 0.30 + 0.20 * (L["k"] == 0)) ) * min(1.0, rear * 2)
                elif i == 3:
                    feet[L["name"]] = r + Vector((-0.10 * L["sx"], -0.24, 0.0))
                else:
                    feet[L["name"]] = r + Vector((-0.05 * L["sx"], -0.12, 0.0))
        self.place_legs(feet)

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        k = (1.0, 0.6, 0.25)[i]
        th = self.j["thorax"]
        th.location = (0, 0.06 * k, self.BZ - 0.06 * k)
        th.rotation_euler = (0.18 * k, 0, 0.1 * k)
        feet = self.feet_rest()
        self.place_legs(feet)

    def pose_death(self, i: int, n: int) -> None:
        # s'effondre, se retourne à moitié, pattes recroquevillées
        self.rest()
        t = i / (n - 1)
        e = smooth(t / 0.7)
        th = self.j["thorax"]
        th.location = (0, 0, self.BZ * (1 - 0.55 * e) + 0.08 * math.sin(min(1.0, t * 1.6) * math.pi) * (1 - e))
        th.rotation_euler = (0, 0.9 * e, 0.3 * e)
        self.j["abd"].rotation_euler = (-0.2 * e, 0, 0)
        self.j["fangs"].rotation_euler = (0.4 * e, 0, 0)
        feet = {}
        for L in self.legs_def:
            r = Vector(L["rest"])
            curl = Vector((r.x * 0.35, r.y * 0.35, 0.25 + 0.1 * L["k"] % 2))
            feet[L["name"]] = r.lerp(curl, e)
        self.place_legs(feet, pole_up=1.0)


# =============================================================================== boss


# =============================================================================== outils glace
def shard(length: float, r: float, sides: int = 5):
    """Cristal de glace : prisme effilé (base en z = 0, pointe en +Z)."""
    bm = C.bm_cyl(sides, r, 0.0, length)
    return C.bm_xform(bm, loc=(0, 0, length * 0.5))


def place_shard(rig: Rig, name: str, key: str, parent, base, direction, length: float, r: float,
                sides: int = 5, nofs: bool = False):
    """Cristal planté en `base`, orienté selon `direction` (repère du parent)."""
    import bmesh
    bm = shard(length, r, sides)
    q = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized())
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=q.to_matrix(), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(base), verts=bm.verts)
    return rig.part(name, bm, key, parent, smooth=False, nofs=nofs)


def crystal_cluster(rig: Rig, key: str, parent, base, up, n: int, length: float, r: float, seed: int,
                    spread: float = 0.45):
    rnd = random.Random(seed)
    up = Vector(up).normalized()
    side = up.cross(Vector((1, 0, 0)))
    if side.length < 1e-3:
        side = up.cross(Vector((0, 1, 0)))
    side.normalize()
    other = up.cross(side).normalized()
    for k in range(n):
        a = 2 * math.pi * k / max(n, 1) + rnd.uniform(-0.4, 0.4)
        tilt = spread * (0.4 + 0.6 * rnd.random()) if k > 0 else 0.1
        d = up + (side * math.cos(a) + other * math.sin(a)) * tilt
        L = length * (1.0 if k == 0 else rnd.uniform(0.45, 0.8))
        place_shard(rig, "crystal", key, parent, Vector(base) + (side * math.cos(a) + other * math.sin(a)) * r * 0.6 * float(k > 0),
                    d, L, r * (1.0 if k == 0 else 0.7))


# =============================================================================== quadrupèdes
class Quad(Rig):
    """Quadrupède (loup, ours) : torse rigide, cou + tête + mâchoire, 4 pattes à 3 segments, queue.
    Repère : l'animal regarde vers -Y, +X = sa gauche, Z vers le haut."""

    REST = {"F": (0.08, -0.12, 0.10), "H": (-0.30, 0.62, -0.38)}
    PHASE = {"FL": 0.0, "FR": 0.12, "HL": 0.52, "HR": 0.64}

    def build(self) -> None:
        A = self.A = self.S
        j = self.j
        L = A["length"]
        self.HM = (A["withers"] + A["hips"]) * 0.5
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["body"] = body = joint("body", root, (0, 0, 0))
        body.scale = (A["scale"],) * 3
        j["torso"] = torso = joint("torso", body, (0, 0, self.HM))
        self.build_torso(torso)
        zf = A["withers"] - self.HM
        j["neck"] = neck = joint("neck", torso, (0, -L * 0.42, zf - 0.02))
        nl = A["neck"]
        self.part("neckMesh", C.bm_tube([(0, 0.06, -0.02), (0, -nl * 0.45, nl * 0.30), (0, -nl * 0.85, nl * 0.52)],
                                        [A["neck_r"] * 1.25, A["neck_r"] * 1.05, A["neck_r"] * 0.85], seg=12),
                  "fur", neck)
        j["head"] = head = joint("head", neck, (0, -nl * 0.85, nl * 0.55))
        self.build_head(head)
        self.build_legs(torso)
        j["tail"] = tail = joint("tail", torso, (0, L * 0.47, A["hips"] - self.HM + 0.03))
        self.build_tail(tail)
        self.build_extra(torso)

    def torso_sections(self) -> list:
        A = self.A
        L = A["length"]
        secs = []
        n = 9
        for k in range(n):
            t = k / (n - 1)
            y = -L * 0.5 + L * t
            bulge = math.sin(math.pi * min(1.0, max(0.0, t * 1.04))) ** 0.45
            rx = (A["chest"][0] * (1 - t) + A["rump"][0] * t) * (0.55 + 0.45 * bulge)
            rz = (A["chest"][1] * (1 - t) + A["rump"][1] * t) * (0.55 + 0.45 * bulge)
            if 0.45 < t < 0.75:
                rz *= 0.90 if not A.get("heavy") else 0.97
            zc = (A["withers"] - self.HM) * (1 - t) + (A["hips"] - self.HM) * t - 0.03
            sec = []
            for i in range(16):
                a = 2 * math.pi * i / 16
                x, z = rx * math.cos(a), rz * math.sin(a)
                if z < 0:
                    z *= 0.85
                sec.append((x, y, zc + z))
            secs.append(sec)
        return secs

    def build_torso(self, torso) -> None:
        A = self.A
        L = A["length"]
        self.part("torsoMesh", C.bm_loft(self.torso_sections()), "fur", torso)
        belly = C.bm_sphere(14, 8, 1.0)
        C.bm_xform(belly, loc=(0, -L * 0.12, (A["withers"] + A["hips"]) * 0.5 - self.HM - A["chest"][1] * 0.62),
                   scale=(A["chest"][0] * 0.75, L * 0.30, A["chest"][1] * 0.32))
        self.part("belly", belly, "belly", torso)
        # touffes de fourrure plus sombres (lisibilité du volume)
        for sx in (1, -1):
            for k in range(3):
                y = -L * 0.30 + L * 0.25 * k
                self.part("tuft", C.bm_xform(C.bm_cyl(4, 0.035, 0.0, 0.10),
                          loc=(A["chest"][0] * 0.92 * sx, y, (A["withers"] - self.HM) - 0.02),
                          rot=(0.6, 0.9 * sx, 0)), "fur_dark", torso, smooth=False)

    def build_head(self, head) -> None:
        A, j = self.A, self.j
        hr = A["head"]
        sk = C.bm_sphere(16, 12, 1.0)
        C.bm_xform(sk, scale=(hr * 0.95, hr * 1.05, hr * 0.85))
        self.part("skull", sk, "fur", head)
        sl, sr = A["snout"], A["snout_r"]
        snout = C.bm_tube([(0, -hr * 0.55, -hr * 0.05), (0, -hr * 0.55 - sl * 0.6, -hr * 0.12),
                           (0, -hr * 0.55 - sl, -hr * 0.18)], [sr * 1.25, sr * 1.0, sr * 0.78], seg=12, flat=0.8)
        self.part("snout", snout, "muzzle" if A.get("dark_snout", False) else "fur", head)
        self.part("nose", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0, -hr * 0.55 - sl - 0.005, -hr * 0.13),
                  scale=(sr * 0.65, sr * 0.45, sr * 0.45)), "nose", head)
        j["jaw"] = jaw = joint("jaw", head, (0, -hr * 0.45, -hr * 0.40))
        jl = sl + hr * 0.10
        self.part("jawMesh", C.bm_tube([(0, 0.0, 0.0), (0, -jl * 0.6, -0.01), (0, -jl, 0.0)],
                                       [sr * 0.95, sr * 0.75, sr * 0.55], seg=10, flat=0.55), "muzzle", jaw)
        self.part("tongue", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -jl * 0.5, 0.02),
                  scale=(sr * 0.55, jl * 0.38, 0.012)), "tongue", jaw)
        for sx in (1, -1):
            self.part("fangU", C.bm_xform(C.bm_cyl(6, 0.016, 0.0, 0.06),
                      loc=(sr * 0.55 * sx, -hr * 0.55 - sl * 0.85, -hr * 0.32), rot=(math.pi, 0, 0)), "teeth", head,
                      nofs=True)
            self.part("fangL", C.bm_xform(C.bm_cyl(6, 0.013, 0.0, 0.045),
                      loc=(sr * 0.45 * sx, -jl * 0.82, 0.03)), "teeth", jaw, nofs=True)
            for k in range(3):
                self.part("tooth", C.bm_xform(C.bm_cyl(5, 0.009, 0.0, 0.028),
                          loc=(sr * 0.62 * sx, -hr * 0.55 - sl * (0.25 + 0.18 * k), -hr * 0.30),
                          rot=(math.pi, 0, 0)), "teeth", head, nofs=True)
            # yeux lumineux (gros, lisibles sur mobile)
            self.part("eye", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(hr * 0.48 * sx, -hr * 0.80, hr * 0.22),
                      scale=(0.030, 0.014, 0.020)), "eye_glow", head, nofs=True)
            self.part("brow", C.bm_xform(C.bm_box(0.06, 0.02, 0.018, bevel=0.005),
                      loc=(hr * 0.46 * sx, -hr * 0.82, hr * 0.37), rot=(0, -0.45 * sx, 0)), "fur_dark", head)
            if A.get("ears") == "round":
                ear = C.bm_sphere(10, 8, 1.0)
                C.bm_xform(ear, loc=(hr * 0.66 * sx, hr * 0.10, hr * 0.78), rot=(0.2, 0, 0.3 * sx),
                           scale=(0.06, 0.03, 0.06))
                self.part("ear", ear, "fur_dark", head)
            else:
                self.part("ear", C.bm_xform(C.bm_cyl(4, 0.055, 0.0, 0.15), loc=(hr * 0.55 * sx, hr * 0.05, hr * 0.92),
                          rot=(0.25, -0.25 * sx, 0), scale=(1.0, 0.45, 1.0)), "fur_dark", head, smooth=False)
        if A.get("crystals") == "spine":
            # petits cristaux sur le front
            for sx in (1, -1):
                place_shard(self, "browShard", "ice", head, (hr * 0.25 * sx, hr * 0.1, hr * 0.75),
                            (0.3 * sx, 0.6, 1.0), 0.09, 0.025)

    def build_legs(self, torso) -> None:
        A, j = self.A, self.j
        L = A["length"]
        lr = A["leg_r"]
        for end, (ya, za, segs) in (("F", (-L * 0.36, A["withers"] - self.HM - 0.06, A["front_leg"])),
                                    ("H", (L * 0.34, A["hips"] - self.HM - 0.02, A["hind_leg"]))):
            for side, sx in (("L", 1), ("R", -1)):
                w = (A["chest"][0] if end == "F" else A["rump"][0]) * 0.62
                n = end + side
                j0 = j["l0" + n] = joint("l0" + n, torso, (w * sx, ya, za))
                a, b, c = segs
                thick = 1.35 if end == "H" else 1.15
                self.part("upper" + n, C.bm_xform(C.bm_cyl(10, lr * thick * 1.25, lr * 1.0, a + 0.04),
                          loc=(0, 0, -a / 2)), "fur", j0)
                if end == "H":
                    self.part("thigh" + n, C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, 0.01, -a * 0.25),
                              scale=(lr * 1.7, lr * 2.3, a * 0.55)), "fur", j0)
                else:
                    self.part("shoulderM" + n, C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, 0, -a * 0.15),
                              scale=(lr * 1.5, lr * 1.9, a * 0.45)), "fur", j0)
                j1 = j["l1" + n] = joint("l1" + n, j0, (0, 0, -a))
                self.part("lower" + n, C.bm_xform(C.bm_cyl(10, lr * 0.95, lr * 0.80, b + 0.03), loc=(0, 0, -b / 2)),
                          "fur", j1)
                j2 = j["l2" + n] = joint("l2" + n, j1, (0, 0, -b))
                self.part("pastern" + n, C.bm_xform(C.bm_cyl(8, lr * 0.80, lr * 0.75, c + 0.02), loc=(0, 0, -c / 2)),
                          "fur_dark", j2)
                paw = C.bm_sphere(10, 6, 1.0)
                C.bm_xform(paw, loc=(0, -0.025, -c - 0.005), scale=(lr * 1.15, lr * 1.5, lr * 0.65))
                self.part("paw" + n, paw, "fur_dark", j2)
                for k in (-1, 0, 1):
                    self.part("claw", C.bm_xform(C.bm_cyl(5, 0.010, 0.0, 0.035),
                              loc=(lr * 0.55 * k, -0.025 - lr * 1.4, -c - 0.01), rot=(math.pi / 2 + 0.4, 0, 0)),
                              "teeth", j2, nofs=True)
        self.rest_legs()

    def build_tail(self, tail) -> None:
        t = self.A.get("tail")
        if t == "bushy":
            self.part("tailMesh", C.bm_tube([(0, 0, 0), (0, 0.10, -0.04), (0, 0.19, -0.12), (0, 0.25, -0.22)],
                                            [0.04, 0.06, 0.06, 0.02], seg=8), "fur", tail)
            self.part("tailTip", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, 0.24, -0.20), scale=(0.035, 0.05, 0.05)),
                      "belly", tail)
        else:
            self.part("tailMesh", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, 0.02, 0.0), scale=(0.07, 0.06, 0.06)),
                      "fur", tail)

    def build_extra(self, torso) -> None:
        A = self.A
        L = A["length"]
        top = (A["withers"] - self.HM) + A["chest"][1] * 0.80
        if A.get("crystals") == "spine":
            # crête de cristaux de glace du garrot à la croupe (la silhouette du loup de la planche)
            for k in range(7):
                t = k / 6
                y = -L * 0.44 + L * 0.80 * t
                z = top * (1 - t) + ((A["hips"] - self.HM) + A["rump"][1] * 0.80) * t
                h = (0.20 - 0.10 * t) * (1.15 if k in (1, 2) else 1.0)
                for sx in ((0,) if k % 2 == 0 else (1, -1)):
                    place_shard(self, "spineShard", "ice", torso, (0.035 * sx, y, z - 0.02),
                                (0.35 * sx, 0.55, 1.0), h, 0.045 if sx == 0 else 0.032)
            for sx in (1, -1):
                place_shard(self, "shoulderShard", "ice", torso, (A["chest"][0] * 0.85 * sx, -L * 0.32, top - 0.08),
                            (0.9 * sx, 0.2, 0.7), 0.13, 0.03)
        elif A.get("crystals") == "hump":
            for k, (x, y, s) in enumerate(((0.06, -0.30, 1.0), (-0.08, -0.22, 0.85), (0.0, -0.08, 0.7),
                                           (0.12, 0.05, 0.6), (-0.10, 0.18, 0.55))):
                crystal_cluster(self, "ice", torso, (x, y * L / 0.92, top - 0.03), (x * 2.0, 0.3, 1.0),
                                2, 0.20 * s, 0.05 * s, 11 + k)
        if A.get("wounds"):
            # entailles rouges sur le flanc et l'épaule (ours muté de la planche)
            for (sx, y, z, rz) in ((1, -0.18, 0.02, 0.5), (1, -0.10, -0.04, 0.4), (-1, 0.10, 0.04, -0.4)):
                self.part("wound", C.bm_xform(C.bm_box(0.012, 0.16, 0.025, bevel=0.005),
                          loc=(A["chest"][0] * 0.98 * sx, y * L, z), rot=(rz, 0, 0)), "wound", torso, nofs=True)

    # ------------------------------------------------------------------ poses
    def rest_legs(self) -> None:
        for end in ("F", "H"):
            for side in ("L", "R"):
                self.leg(end + side, 0.0, 0.0, 0.0)

    def leg(self, n: str, d0: float, d1: float, d2: float) -> None:
        r = self.REST[n[0]]
        self.j["l0" + n].rotation_euler = (r[0] + d0, 0, 0)
        self.j["l1" + n].rotation_euler = (r[1] + d1, 0, 0)
        self.j["l2" + n].rotation_euler = (r[2] + d2, 0, 0)

    def rest(self) -> None:
        j, A = self.j, self.A
        j["body"].location = (0, 0, 0)
        j["body"].rotation_euler = (0, 0, 0)
        j["torso"].location = (0, 0, self.HM)
        j["torso"].rotation_euler = (0, 0, 0)
        j["torso"].scale = (1, 1, 1)
        j["neck"].rotation_euler = (A.get("head_down", 0.0), 0, 0)
        j["head"].rotation_euler = (-A.get("head_down", 0.0) * 0.4, 0, 0)
        j["jaw"].rotation_euler = (A.get("jaw_idle", 0.0), 0, 0)
        j["tail"].rotation_euler = (0, 0, 0)
        self.rest_legs()

    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        j, A = self.j, self.A
        t = 2 * math.pi * i / n
        b = math.sin(t)
        j["torso"].location.z = self.HM - 0.008 * (1 - b)
        j["torso"].scale = (1 + 0.025 * b, 1.0, 1 + 0.025 * b)
        hd = A.get("head_down", 0.0)
        j["neck"].rotation_euler = (hd + 0.04 * b, 0, 0.12 * math.sin(t * 0.5 + 0.4))
        j["head"].rotation_euler = (-hd * 0.4 - 0.03 * b, 0, 0.10 * math.sin(t * 0.5))
        j["jaw"].rotation_euler = (A.get("jaw_idle", 0.0) + 0.06 * max(0.0, b), 0, 0)
        j["tail"].rotation_euler = (0.05 * b, 0, 0.30 * math.sin(t))
        self.leg("FL", -0.03, 0, 0.0)
        self.leg("HR", 0.05, 0.03, 0.0)

    def pose_run(self, i: int, n: int) -> None:
        self.rest()
        j, A = self.j, self.A
        p = i / n
        heavy = A.get("heavy", 0.0)
        amp = 0.75 - 0.25 * heavy
        for leg, ph in self.PHASE.items():
            a = 2 * math.pi * (p + ph)
            s, c = math.sin(a), math.cos(a)
            lift = max(0.0, c)
            if leg[0] == "F":
                self.leg(leg, -amp * s, 0.25 + 0.95 * lift, 0.25 * lift)
            else:
                self.leg(leg, -amp * 0.9 * s, 0.35 * lift, -0.55 * lift)
        a = 2 * math.pi * p
        j["torso"].location.z = self.HM + (0.035 - 0.015 * heavy) * math.sin(2 * a + 0.6) - 0.02
        j["torso"].rotation_euler = (0.07 * math.sin(a + 0.8), 0, 0.04 * heavy * math.sin(a))
        hd = A.get("head_down", 0.0)
        j["neck"].rotation_euler = (hd * 0.6 + 0.10 - 0.08 * math.sin(a + 0.8), 0, 0)
        j["head"].rotation_euler = (-0.05, 0, 0)
        j["jaw"].rotation_euler = (A.get("jaw_idle", 0.0) + 0.12, 0, 0)
        j["tail"].rotation_euler = (-0.35 + 0.15 * math.sin(a), 0, 0.1 * math.sin(a))

    def pose_attack(self, i: int, n: int) -> None:
        self.rest()
        j, A = self.j, self.A
        if A.get("heavy"):
            self.attack_heavy(i)
            return
        by = (0.03, 0.06, 0.07, -0.26, -0.24, -0.08)[i]
        bz = (-0.02, -0.05, -0.06, 0.02, -0.01, -0.01)[i]
        pitch = (0.04, 0.10, 0.12, -0.10, 0.04, 0.02)[i]
        sc = A["scale"]
        j["body"].location = (0, by * sc, 0)
        j["torso"].location.z = self.HM + bz
        j["torso"].rotation_euler = (pitch, 0, 0)
        hd = A.get("head_down", 0.0)
        j["neck"].rotation_euler = (hd + (0.15, 0.30, 0.32, -0.05, 0.10, 0.10)[i], 0, (0, 0, 0, 0, 0.22, 0)[i])
        j["head"].rotation_euler = ((-0.10, -0.20, -0.22, -0.15, 0.05, 0.0)[i], 0, (0, 0, 0, 0, -0.25, 0)[i])
        j["jaw"].rotation_euler = ((0.30, 0.45, 0.50, 0.85, 0.05, 0.20)[i], 0, 0)
        j["tail"].rotation_euler = ((-0.1, -0.25, -0.3, -0.5, -0.4, -0.2)[i], 0, 0)
        fr = (-0.05, 0.10, 0.12, -0.85, -0.55, -0.15)[i]
        hr = (0.0, 0.10, 0.12, 0.65, 0.40, 0.10)[i]
        crouch = (0.15, 0.30, 0.35, 0.0, 0.10, 0.10)[i]
        for side in ("L", "R"):
            self.leg("F" + side, fr, crouch * 1.2 + (0.4 if i == 3 else 0.0), 0.0)
            self.leg("H" + side, hr - crouch * 0.6, crouch * 1.3, -crouch * 0.8)

    def attack_heavy(self, i: int) -> None:
        """Ours : se dresse sur les pattes arrière (0-2), s'abat gueule ouverte et griffes (3), retombe."""
        j, A = self.j, self.A
        rear = (0.25, 0.55, 0.62, -0.10, -0.05, 0.10)[i]
        sc = A["scale"]
        j["torso"].rotation_euler = (-rear, 0, 0)
        j["torso"].location = (0, 0.10 * max(0.0, rear) - 0.12 * (i in (3, 4)), self.HM + 0.22 * max(0.0, rear))
        j["body"].location = (0, (0.0, 0.03, 0.04, -0.16, -0.14, -0.04)[i] * sc, 0)
        hd = A.get("head_down", 0.0)
        j["neck"].rotation_euler = (hd + (0.0, -0.10, -0.15, 0.25, 0.20, 0.05)[i], 0, 0)
        j["head"].rotation_euler = ((-0.10, -0.25, -0.30, 0.0, 0.05, 0.0)[i], 0, 0)
        j["jaw"].rotation_euler = ((0.4, 0.7, 0.85, 0.9, 0.3, 0.3)[i], 0, 0)
        for side in ("L", "R"):
            up = (0.35, 0.85, 1.0, -0.6, -0.4, 0.0)[i]
            self.leg("F" + side, -up, 0.5 * max(0.0, up) + (0.3 if i == 3 else 0.0), 0.2)
            self.leg("H" + side, rear * 0.9, 0.2 * rear, -0.3 * rear)

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        k = (1.0, 0.6, 0.25)[i]
        j["body"].location = (0, 0.05 * k, 0)
        j["torso"].rotation_euler = (-0.08 * k, 0, 0.06 * k)
        j["neck"].rotation_euler = (self.A.get("head_down", 0.0) - 0.35 * k, 0, 0.15 * k)
        j["jaw"].rotation_euler = (0.25 * k + 0.05, 0, 0)
        j["tail"].rotation_euler = (0.4 * k, 0, 0)
        for side in ("L", "R"):
            self.leg("F" + side, 0.15 * k, 0.1 * k, 0)
            self.leg("H" + side, -0.05 * k, 0.15 * k, -0.1 * k)

    def pose_death(self, i: int, n: int) -> None:
        """Chute sur le flanc ; dernière image = cadavre en travers de l'écran."""
        self.rest()
        j, A = self.j, self.A
        t = i / (n - 1)
        u = min(1.0, max(0.0, (t - 0.12) / 0.62))
        e = u * u * (3 - 2 * u)
        bounce = 0.0
        if t > 0.75:
            v = (t - 0.75) / 0.25
            bounce = 0.07 * math.sin(v * math.pi) * (1 - v)
        roll = (math.pi / 2 - 0.12) * e - bounce
        tau = corpse_twist(self.dir_ang) * min(1.0, e * 1.3)
        sc = A["scale"]
        j["body"].rotation_euler = (0, roll, tau)
        j["body"].location = (0, 0, A["chest"][0] * 0.85 * sc * math.sin(roll))
        j["torso"].location.z = self.HM - 0.05 * min(1.0, t * 4)
        j["neck"].rotation_euler = (A.get("head_down", 0.0) + 0.5 * e - 0.35 * (1 - e) * min(1.0, t * 5), 0, -0.25 * e)
        j["head"].rotation_euler = (0.2 * e, 0, 0)
        j["jaw"].rotation_euler = (0.35 * min(1.0, t * 3) * (1 - 0.4 * e), 0, 0)
        j["tail"].rotation_euler = (0.6 * e, 0, 0)
        for leg in ("FL", "FR", "HL", "HR"):
            up = leg[1] == "L"
            sp = (0.25 if up else -0.1) * e
            self.leg(leg, (-0.35 if leg[0] == "F" else 0.35) * e + sp, 0.3 * e * (1 if up else 0.4), 0.0)

    def muzzle_world(self) -> Vector:
        bpy.context.view_layer.update()
        hr, sl = self.A["head"], self.A["snout"]
        return self.j["head"].matrix_world @ Vector((0, -hr * 0.55 - sl, -hr * 0.2))


# =============================================================================== araignée polaire
class PolarSpider(Spider):
    """Araignée polaire : corps blindé blanc, tête de bête (museau, oreilles, crocs), yeux rouges,
    lueur rouge sous l'abdomen et lumières de givre cyan."""

    def build(self) -> None:
        super().build()
        self.j["abd"].scale = (0.72, 0.72, 0.72)
        th = self.j["thorax"]
        # tête de bête par-dessus la tête d'araignée
        sk = C.bm_sphere(16, 12, 1.0)
        C.bm_xform(sk, loc=(0, -0.27, 0.08), scale=(0.13, 0.13, 0.11))
        self.part("beastSkull", sk, "fur", th)
        self.part("beastSnout", C.bm_tube([(0, -0.34, 0.07), (0, -0.42, 0.04), (0, -0.48, 0.01)],
                                          [0.075, 0.06, 0.045], seg=10, flat=0.8), "fur", th)
        self.part("beastNose", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -0.49, 0.02), scale=(0.03, 0.02, 0.02)),
                  "leg_tip", th)
        for sx in (1, -1):
            self.part("beastEar", C.bm_xform(C.bm_cyl(4, 0.045, 0.0, 0.12), loc=(0.08 * sx, -0.22, 0.20),
                      rot=(0.2, -0.3 * sx, 0), scale=(1.0, 0.45, 1.0)), "carapace", th, smooth=False)
            self.part("beastEye", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.065 * sx, -0.37, 0.12),
                      scale=(0.03, 0.014, 0.02)), "eye_glow", th, nofs=True)
            self.part("beastFang", C.bm_xform(C.bm_cyl(6, 0.014, 0.0, 0.06), loc=(0.035 * sx, -0.45, -0.01),
                      rot=(math.pi, 0, 0)), "fang", th, nofs=True)
            # plaques de blindage dorsales
            for k in range(2):
                self.part("plate", C.bm_xform(C.bm_box(0.10, 0.10, 0.03, bevel=0.012),
                          loc=(0.09 * sx, -0.06 + 0.10 * k, 0.12), rot=(0.1, 0.35 * sx, 0)), "leg", th)
        # lueur rouge sous l'abdomen (planche) et piquants de givre
        abd = self.j["abd"]
        self.part("redGlow", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, 0.30, -0.10), scale=(0.12, 0.16, 0.05)),
                  "red_glow", abd, nofs=True)
        for k in range(4):
            place_shard(self, "abdShard", "ice", abd, (0.08 * (-1) ** k, 0.22 + 0.10 * k, 0.30 - 0.02 * k),
                        (0.4 * (-1) ** k, 0.5, 1.0), 0.10, 0.03)
        self.muzzle_ref = ("beastSnout", (0.0, -0.48, 0.0))

    def muzzle_world(self) -> Vector:
        return self.j["thorax"].matrix_world @ Vector((0.0, -0.50, -0.02))


# =============================================================================== drone
class Drone(Rig):
    """Drone de froid : sphère volante blindée, grand œil cyan, deux pinces, quatre pattes pendantes."""

    def build(self) -> None:
        S = self.S
        j = self.j
        self.HZ = S.get("hover", 0.95)
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["body"] = body = joint("body", root, (0, 0, 0))
        body.scale = (S["scale"],) * 3
        j["hov"] = hov = joint("hov", body, (0, 0, self.HZ))
        # coque
        shell = C.bm_sphere(22, 16, 1.0)
        C.bm_xform(shell, scale=(0.27, 0.27, 0.23))
        self.part("shell", shell, "shell", hov)
        self.part("band", C.bm_xform(C.bm_torus(24, 6, 0.27, 0.035), scale=(1.0, 1.0, 0.8)), "shell_dark", hov)
        self.part("cap", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, 0.02, 0.20), scale=(0.13, 0.13, 0.06)),
                  "shell_dark", hov)
        self.part("antenna", C.bm_xform(C.bm_cyl(6, 0.010, 0.006, 0.18), loc=(0.06, 0.06, 0.30)), "metal_dark", hov)
        self.part("antTip", C.bm_xform(C.bm_sphere(8, 6, 0.022), loc=(0.06, 0.06, 0.40)), "light", hov, nofs=True)
        self.part("under", C.bm_xform(C.bm_cyl(14, 0.12, 0.07, 0.10), loc=(0, 0, -0.22)), "shell_dark", hov)
        # œil : bague sombre + lentille cyan + point chaud
        self.part("eyeRing", C.bm_xform(C.bm_torus(20, 6, 0.125, 0.03), loc=(0, -0.235, 0.0),
                  rot=(math.pi / 2, 0, 0)), "shell_dark", hov)
        self.part("eyeLens", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, -0.24, 0.0), scale=(0.115, 0.06, 0.115)),
                  "eye_glow", hov, nofs=True, grp="eye")
        j["core"] = core = joint("core", hov, (0, -0.285, 0.0))
        self.part("eyeCore", C.bm_xform(C.bm_sphere(10, 8, 1.0), scale=(0.055, 0.025, 0.055)), "eye_core", core,
                  nofs=True, grp="eye")
        self.part("flare", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.03, 0), scale=(0.16, 0.05, 0.16)),
                  "eye_core", core, nofs=True, grp="flare")
        # propulseurs latéraux
        for sx in (1, -1):
            self.part("pod", C.bm_xform(C.bm_cyl(12, 0.06, 0.07, 0.14), loc=(0.29 * sx, 0.04, -0.02),
                      rot=(0, math.pi / 2, 0)), "shell_dark", hov)
            self.part("podGlow", C.bm_xform(C.bm_cyl(12, 0.045, 0.045, 0.02), loc=(0.29 * sx, 0.04, -0.10)),
                      "light", hov, nofs=True)
        # pinces supérieures (bras articulés)
        self.arms = []
        for side, sx in (("L", 1), ("R", -1)):
            a = j["arm" + side] = joint("arm" + side, hov, (0.18 * sx, 0.0, 0.14))
            self.part("armU" + side, C.bm_tube([(0, 0, 0), (0.10 * sx, -0.02, 0.14), (0.22 * sx, -0.08, 0.16)],
                                               [0.035, 0.03, 0.028], seg=8), "shell", a)
            c = j["claw" + side] = joint("claw" + side, a, (0.22 * sx, -0.08, 0.16))
            self.part("armL" + side, C.bm_tube([(0, 0, 0), (0.06 * sx, -0.10, -0.06), (0.04 * sx, -0.20, -0.16)],
                                               [0.028, 0.024, 0.02], seg=8), "shell_dark", c)
            for k in (1, -1):
                self.part("pincer", C.bm_tube([(0.04 * sx, -0.20, -0.16), (0.04 * sx + 0.04 * k, -0.27, -0.20),
                                               (0.04 * sx + 0.01 * k, -0.31, -0.25)], [0.016, 0.012, 0.0], seg=6),
                          "metal", c)
            self.part("armLight", C.bm_xform(C.bm_sphere(8, 6, 0.02), loc=(0.06 * sx, -0.10, -0.05)), "light", c,
                      nofs=True)
        # pattes pendantes
        self.legs_def = []
        for k, (x, y) in enumerate(((0.10, -0.10), (-0.10, -0.10), (0.11, 0.10), (-0.11, 0.10))):
            u = j["leg%d" % k] = joint("leg%d" % k, hov, (x, y, -0.20))
            self.part("legU%d" % k, C.bm_tube([(0, 0, 0), (x * 0.8, y * 0.5, -0.14)], [0.024, 0.02], seg=8),
                      "shell_dark", u)
            lo = j["legl%d" % k] = joint("legl%d" % k, u, (x * 0.8, y * 0.5, -0.14))
            self.part("legL%d" % k, C.bm_tube([(0, 0, 0), (x * 0.2, y * 0.2, -0.16), (0, 0, -0.30)],
                                              [0.02, 0.016, 0.0], seg=8), "metal", lo)
            self.part("legJoint%d" % k, C.bm_xform(C.bm_sphere(8, 6, 0.026)), "light", lo, nofs=True)
            self.legs_def.append((u, lo, x, y))
        self.muzzle_ref = ("eyeCore", (0, 0, 0))

    def muzzle_world(self) -> Vector:
        return self.j["core"].matrix_world @ Vector((0, -0.03, 0))

    def rest(self) -> None:
        j = self.j
        j["body"].location = (0, 0, 0)
        j["body"].rotation_euler = (0, 0, 0)
        j["hov"].location = (0, 0, self.HZ)
        j["hov"].rotation_euler = (0, 0, 0)
        j["core"].scale = (1, 1, 1)
        for side in ("L", "R"):
            j["arm" + side].rotation_euler = (0, 0, 0)
            j["claw" + side].rotation_euler = (0, 0, 0)
        for u, lo, x, y in self.legs_def:
            u.rotation_euler = (0, 0, 0)
            lo.rotation_euler = (0, 0, 0)
        self.show("eye", True)
        self.show("flare", False)

    def legs_swing(self, ax: float, ay: float, knee: float) -> None:
        for k, (u, lo, x, y) in enumerate(self.legs_def):
            u.rotation_euler = (ax, ay * (1 if x > 0 else -1), 0)
            lo.rotation_euler = (knee, 0, 0)

    def arms_open(self, o: float, fwd: float = 0.0) -> None:
        for side, sx in (("L", 1), ("R", -1)):
            self.j["arm" + side].rotation_euler = (fwd, -0.35 * o * sx, 0)
            self.j["claw" + side].rotation_euler = (0.3 * o, 0, 0)

    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        t = 2 * math.pi * i / n
        self.j["hov"].location.z = self.HZ + 0.03 * math.sin(t)
        self.j["hov"].rotation_euler = (0.03 * math.sin(t + 1.0), 0.04 * math.sin(t), 0)
        self.legs_swing(0.10 * math.sin(t + 0.6), 0.06 * math.sin(t), 0.25 + 0.1 * math.sin(t + 1.2))
        self.arms_open(0.15 + 0.15 * math.sin(t))

    def pose_run(self, i: int, n: int) -> None:
        self.rest()
        p = 2 * math.pi * i / n
        self.j["hov"].location.z = self.HZ + 0.02 * math.sin(2 * p)
        self.j["hov"].rotation_euler = (0.32, 0.05 * math.sin(p), 0)
        self.legs_swing(0.55 + 0.12 * math.sin(p), 0.05 * math.sin(p), 0.5 + 0.15 * math.sin(p + 1.0))
        self.arms_open(-0.1, 0.25)

    def pose_attack(self, i: int, n: int) -> None:
        # 0-2 : se cabre, pinces ouvertes, l'œil se charge ; 3 : décharge (éclat) ; 4-5 retour
        self.rest()
        back = (0.05, 0.14, 0.18, -0.10, -0.04, 0.0)[i]
        self.j["hov"].rotation_euler = (-back, 0, 0)
        self.j["hov"].location = (0, (0, 0.02, 0.03, 0.06, 0.03, 0.0)[i], self.HZ + 0.04 * (i < 3))
        k = (1.1, 1.3, 1.45, 1.0, 1.0, 1.0)[i]
        self.j["core"].scale = (k, k, k)
        self.arms_open((0.5, 0.9, 1.0, 0.6, 0.4, 0.2)[i], -0.2 * (i < 3))
        self.legs_swing(0.2 * (i < 3), 0.12, 0.35)
        self.show("flare", i == 3)

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        k = (1.0, 0.6, 0.25)[i]
        self.j["hov"].rotation_euler = (-0.25 * k, 0.3 * k, 0)
        self.j["hov"].location = (0, 0.05 * k, self.HZ + 0.03 * k)
        self.legs_swing(-0.3 * k, 0.15 * k, 0.5 * k)
        self.arms_open(0.6 * k)

    def pose_death(self, i: int, n: int) -> None:
        """Perd sa sustentation, bascule et s'écrase ; l'œil s'éteint (dernière image = carcasse au sol)."""
        self.rest()
        t = i / (n - 1)
        e = smooth(t / 0.7)
        sc = self.S["scale"]
        z = self.HZ * (1 - e) + 0.21 * e
        if t > 0.7:
            z += 0.04 * math.sin((t - 0.7) / 0.3 * math.pi)
        tau = corpse_twist(self.dir_ang) * e
        self.j["body"].rotation_euler = (0, 0, tau)
        self.j["hov"].location = (0, 0, z)
        self.j["hov"].rotation_euler = (0.5 * e, 1.1 * e, 0)
        self.legs_swing(1.1 * e, 0.6 * e, 0.9 * e)
        self.arms_open(1.0 * e, 0.4 * e)
        self.show("eye", t < 0.6)
        _ = sc


# =============================================================================== humanoïdes
class SlamMixin:
    """Bras et frappe au sol à deux poings (élémentaire, gardien, titan)."""

    def arms_rest(self, b: float = 0.0) -> None:
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.13, -0.10, -0.42 * self.AL + 0.02 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.13, -0.10, -0.42 * self.AL + 0.02 * b)), self.R_POLE)

    def arms_run(self, s: float) -> None:
        sh = self.shoulder
        for side, sx, k in (("L", 1, -1), ("R", -1, 1)):
            self.arm_ik(side, sh[side] + Vector((0.13 * sx, 0.18 * s * k - 0.08, -0.40 * self.AL)),
                        self.L_POLE if sx > 0 else self.R_POLE)

    def pose_run(self, i: int, n: int) -> None:
        Human.pose_run(self, i, n)
        self.j["pelvis"].location.z -= 0.03

    def pose_attack(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        crouch = (0.02, 0.0, -0.02, 0.16, 0.14, 0.06)[i]
        j["pelvis"].location.z = self.PZ - crouch
        lean = (-0.05, -0.22, -0.28, 0.55, 0.50, 0.20)[i]
        self.spine_rot(lean - self.HUNCH * 0.5, 0, 0)
        self.legs((-0.3, -0.14, 0), (0.25, 0.14, 0), 0.3 + crouch * 2, 0.35 + crouch * 2)
        sh = self.shoulder
        al = self.AL
        if i < 3:
            up = (0.30, 0.52, 0.58)[i] * al
            hl, hr = Vector((-0.08, 0.06, up)), Vector((0.08, 0.06, up))
        elif i < 5:
            hl, hr = Vector((-0.12, -0.36 * al, -0.30 * al)), Vector((0.12, -0.36 * al, -0.30 * al))
        else:
            hl, hr = Vector((0.04, -0.24, -0.36 * al)), Vector((-0.04, -0.24, -0.36 * al))
        self.arm_ik("L", sh["L"] + hl, Vector((0.9, 0.2, 0.1)))
        self.arm_ik("R", sh["R"] + hr, Vector((-0.9, 0.2, 0.1)))


class GunMixin:
    """Arme tenue à deux mains au bras droit (chasseur, mécanicien)."""

    def gun_aim(self, aim: float, recoil: float = 0.0) -> None:
        sh = self.shoulder
        low = sh["R"] + Vector((-0.06, -0.10, -0.36))
        up = sh["R"] + Vector((0.06, -0.42, -0.04))
        tgt = low.lerp(up, aim) + Vector((0, 0.07 * recoil, 0.04 * recoil))
        self.arm_ik("R", tgt, Vector((-0.9, 0.3, -0.3)))
        lo = sh["L"] + Vector((0.06, -0.06, -0.38))
        sup = sh["R"] + Vector((0.10, -0.30, -0.16)) + Vector((0, 0.05 * recoil, 0))
        self.arm_ik("L", lo.lerp(sup, aim), self.L_POLE)

    def arms_rest(self, b: float = 0.0) -> None:
        self.gun_aim(0.15 + 0.02 * b)

    def arms_run(self, s: float) -> None:
        self.gun_aim(0.3 + 0.05 * s)

    def pose_attack(self, i: int, n: int) -> None:
        self.rest()
        aim = (0.4, 0.9, 1.0, 1.0, 1.0, 0.85)[i]
        rc = (0, 0, 0, 1.0, 0.4, 0.0)[i]
        self.spine_rot(0.04 - 0.10 * rc, 0, 0.12)
        self.legs((0.05, -0.12, 0), (-0.10, 0.12, 0), 0.12, 0.18)
        self.gun_aim(aim, rc)

    def muzzle_world(self) -> Vector:
        return self.j["faR"].matrix_world @ Vector(self._muzzle_local)


class Elemental(SlamMixin, Human):
    """Élémentaire de glace : blocs de glace, cristaux aux épaules et au dos, cœur cyan, poings massifs."""

    CROWN = 5

    def build_head(self, head) -> None:
        sk = C.bm_sphere(14, 10, 1.0)
        rnd = random.Random(5)
        for v in sk.verts:
            k = 1.0 + 0.10 * rnd.random()
            v.co = Vector((v.co.x * 0.17 * k, v.co.y * 0.17 * k, v.co.z * 0.16 * k + 0.19))
        self.part("skull", sk, "ice", head, smooth=False)
        self.part("brow", C.bm_xform(C.bm_box(0.26, 0.08, 0.06, bevel=0.01), loc=(0, -0.13, 0.25), rot=(0.2, 0, 0)),
                  "ice_deep", head, smooth=False)
        self.part("jaw", C.bm_xform(C.bm_box(0.22, 0.12, 0.08, bevel=0.01), loc=(0, -0.09, 0.08)), "ice_deep", head,
                  smooth=False)
        self.eyes(head, "eye_glow", z=0.215, x=0.062, y=-0.165, r=(0.034, 0.012, 0.020), brow=False)
        for k in range(self.CROWN):
            a = (k - (self.CROWN - 1) / 2) * 0.45
            place_shard(self, "crown", "frost" if k % 2 else "ice", head, (0.12 * math.sin(a), 0.03, 0.30),
                        (math.sin(a) * 0.8, 0.35, 1.0), 0.20 - 0.04 * abs(a), 0.04)

    def build_torso(self, pelvis, spine) -> None:
        super().build_torso(pelvis, spine)
        tw, td = self.TW, self.TD
        # cœur lumineux au milieu de la poitrine
        self.part("coreHalo", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.20 * td, 0.27),
                  scale=(0.08, 0.04, 0.08)), "glow", spine, nofs=True)
        self.part("coreHot", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, -0.225 * td, 0.27),
                  scale=(0.045, 0.02, 0.045)), "core", spine, nofs=True)
        # plaques de glace (pectoraux taillés)
        for sx in (1, -1):
            self.part("plate", C.bm_xform(C.bm_box(0.17 * tw, 0.06, 0.14, bevel=0.01),
                      loc=(0.11 * sx * tw, -0.15 * td, 0.33), rot=(0.15, 0.25 * sx, 0.1 * sx)), "frost", spine,
                      smooth=False)
            crystal_cluster(self, "ice", spine, (0.20 * sx * tw, 0.04, 0.44), (0.9 * sx, 0.35, 1.0), 3, 0.30, 0.06,
                            21 + sx)
        # dos hérissé
        for k in range(4):
            place_shard(self, "backShard", "frost" if k % 2 else "ice", spine,
                        (0.07 * (-1) ** k, 0.13 * td, 0.18 + 0.08 * k), (0.4 * (-1) ** k, 1.0, 0.8), 0.22, 0.05)

    def dress(self) -> None:
        for side, sx in (("L", 1), ("R", -1)):
            fa = self.j["fa" + side]
            self.part("fist" + side, C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, 0, -self.ll),
                      scale=(0.11 * self.AW, 0.10 * self.AW, 0.10 * self.AW)), "ice", fa, smooth=False)
            place_shard(self, "armShard", "frost", fa, (0.05 * sx, 0.04, -0.08), (0.7 * sx, 0.5, 0.6), 0.16, 0.035)
            place_shard(self, "knuckle", "ice", fa, (0.0, -0.06, -self.ll - 0.03), (0.0, -0.6, -1.0), 0.10, 0.03)
            knee = self.j["knee" + side]
            place_shard(self, "kneeShard", "frost", knee, (0.05 * sx, -0.07, 0.0), (0.3 * sx, -0.8, 0.6), 0.12, 0.035)
        self.muzzle_ref = ("fistR", (0, 0, -self.ll))

    def muzzle_world(self) -> Vector:
        return self.j["faR"].matrix_world @ Vector((0, 0, -self.ll))


class Titan(Elemental):
    """Le Titan de glace : élémentaire colossal, couronne de grands cristaux, noyau arctique."""

    CROWN = 7

    def build_torso(self, pelvis, spine) -> None:
        super().build_torso(pelvis, spine)
        tw = self.TW
        # grandes flèches de glace sur les épaules et le dos (silhouette de la planche)
        for sx in (1, -1):
            place_shard(self, "spire", "frost", spine, (0.24 * sx * tw, 0.08, 0.40), (0.55 * sx, 0.5, 1.0), 0.55, 0.08)
            place_shard(self, "spire2", "ice", spine, (0.15 * sx * tw, 0.14, 0.36), (0.25 * sx, 0.8, 1.0), 0.42, 0.07)
        # ceinture d'énergie du noyau
        self.part("coreRing", C.bm_xform(C.bm_torus(20, 6, 0.10, 0.012), loc=(0, -0.21 * self.TD, 0.27),
                  rot=(math.pi / 2, 0, 0)), "glow", spine, nofs=True)


class Hunter(GunMixin, Human):
    """Chasseur arctique : armure grise, capuche fourrée, lunettes orange, fusil cryogénique."""

    def build_head(self, head) -> None:
        self.skull(head, "skin")
        hb = C.bm_sphere(20, 14, 1.0)
        for v in hb.verts:
            x, y, z = v.co
            if z < -0.25 and y < 0:
                z = -0.25
            v.co = Vector((x * 0.20, y * 0.20, z * 0.19 + 0.22))
        self.part("helmet", hb, "armor", head)
        self.part("mask", C.bm_xform(C.bm_box(0.24, 0.10, 0.11, bevel=0.03), loc=(0, -0.13, 0.10)), "armor_dark", head)
        for sx in (1, -1):
            self.part("filter", C.bm_xform(C.bm_cyl(10, 0.035, 0.035, 0.05), loc=(0.07 * sx, -0.19, 0.09),
                      rot=(math.pi / 2, 0, 0)), "metal_dark", head)
            self.part("goggle", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0.062 * sx, -0.17, 0.215),
                      scale=(0.050, 0.025, 0.036)), "visor", head, nofs=True)
            self.part("goggleRim", C.bm_xform(C.bm_torus(14, 4, 0.05, 0.012), loc=(0.062 * sx, -0.165, 0.215),
                      rot=(math.pi / 2, 0, 0), scale=(1.0, 0.75, 1.0)), "armor_dark", head)
        self.part("strapG", C.bm_xform(C.bm_cyl(20, 0.205, 0.205, 0.035), loc=(0, 0, 0.215)), "armor_dark", head)
        # capuche fourrée autour du cou
        self.part("furRing", C.bm_xform(C.bm_torus(18, 8, 0.15, 0.055), loc=(0, 0.01, 0.02), scale=(1.0, 0.9, 0.8)),
                  "fur", head)

    def build_torso(self, pelvis, spine) -> None:
        super().build_torso(pelvis, spine)
        tw, td = self.TW, self.TD
        self.part("vest", C.bm_xform(C.bm_box(0.42 * tw, 0.32 * td, 0.30, bevel=0.05), loc=(0, -0.01, 0.28)),
                  "armor", spine)
        for k in range(3):
            self.part("pouch", C.bm_xform(C.bm_box(0.08, 0.05, 0.08, bevel=0.012),
                      loc=(-0.10 + 0.10 * k, -0.18 * td, 0.18)), "armor_dark", spine)
        self.part("pack", C.bm_xform(C.bm_box(0.30 * tw, 0.14, 0.30, bevel=0.03), loc=(0, 0.20 * td, 0.30)),
                  "armor_dark", spine)
        self.part("tank", C.bm_xform(C.bm_cyl(14, 0.06, 0.06, 0.30), loc=(0.0, 0.29 * td, 0.32)), "metal", spine)
        self.part("tankGlow", C.bm_xform(C.bm_cyl(14, 0.062, 0.062, 0.08), loc=(0.0, 0.29 * td, 0.32)), "cryo", spine,
                  nofs=True)
        for sx in (1, -1):
            self.part("pad", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0.25 * sx * tw ** 0.6, 0, 0.40),
                      scale=(0.11, 0.12, 0.08)), "armor", spine)
        self.part("belt", C.bm_xform(C.bm_cyl(18, 0.20 * tw, 0.20 * tw, 0.05), loc=(0, 0, 0.02),
                  scale=(1, 0.8, 1)), "strap", spine)

    def build_arms(self, spine) -> None:
        super().build_arms(spine)
        fa = self.j["faR"]
        ll = self.ll
        self.part("rifle", C.bm_xform(C.bm_box(0.07, 0.10, 0.50, bevel=0.015), loc=(0, -0.02, -ll - 0.08)), "gun", fa)
        self.part("stock", C.bm_xform(C.bm_box(0.06, 0.12, 0.14, bevel=0.015), loc=(0, 0.0, -ll + 0.20)), "gun", fa)
        self.part("barrel", C.bm_xform(C.bm_cyl(10, 0.022, 0.022, 0.20), loc=(0, -0.04, -ll - 0.42)), "metal_dark", fa)
        self.part("muzzleRing", C.bm_xform(C.bm_cyl(10, 0.032, 0.032, 0.04), loc=(0, -0.04, -ll - 0.52)), "cryo", fa,
                  nofs=True)
        self.part("canister", C.bm_xform(C.bm_cyl(12, 0.04, 0.04, 0.16), loc=(0.0, -0.10, -ll - 0.14)), "cryo", fa,
                  nofs=True)
        self.part("scope", C.bm_xform(C.bm_cyl(10, 0.022, 0.022, 0.14), loc=(0, 0.06, -ll - 0.10)), "metal_dark", fa)
        self._muzzle_local = (0.0, -0.04, -ll - 0.56)
        self.muzzle_ref = ("rifle", (0, 0, 0))

    def pose_run(self, i: int, n: int) -> None:
        Human.pose_run(self, i, n)
        self.j["pelvis"].location.z -= 0.02


class Armored(Human):
    """Humanoïde blindé (gardien, mécanicien) : armure en plaques, visière / œil lumineux."""

    def build_head(self, head) -> None:
        hb = C.bm_sphere(20, 14, 1.0)
        for v in hb.verts:
            x, y, z = v.co
            v.co = Vector((x * 0.19, y * 0.19, z * 0.17 + 0.18))
        self.part("helmet", hb, "armor", head)
        self.part("visorFrame", C.bm_xform(C.bm_box(0.28, 0.06, 0.09, bevel=0.02), loc=(0, -0.15, 0.20)),
                  "armor_dark", head)
        self.part("visor", C.bm_xform(C.bm_box(0.22, 0.04, 0.035, bevel=0.01), loc=(0, -0.18, 0.205)), "visor",
                  head, nofs=True)
        self.part("jaw", C.bm_xform(C.bm_box(0.22, 0.12, 0.08, bevel=0.02), loc=(0, -0.08, 0.06)), "armor_dark", head)

    def build_torso(self, pelvis, spine) -> None:
        tw, td = self.TW, self.TD
        self.part("hips", C.bm_xform(C.bm_box(0.36 * tw, 0.26 * td, 0.16, bevel=0.04)), "armor_dark", pelvis)
        self.part("abdomen", C.bm_xform(C.bm_cyl(12, 0.13 * tw, 0.15 * tw, 0.16), loc=(0, 0, 0.08)), "joint", spine)
        chest = C.bm_box(0.46 * tw, 0.32 * td, 0.30, bevel=0.06, segs=3)
        for v in chest.verts:
            if v.co.z < 0:
                v.co.x *= 0.80
            if v.co.y < 0:
                v.co.y -= 0.03 * (1 - abs(v.co.x) / (0.23 * tw))
        self.part("chest", C.bm_xform(chest, loc=(0, -0.01, 0.30)), "armor", spine)
        self.part("collar", C.bm_xform(C.bm_cyl(14, 0.12, 0.11, 0.08), loc=(0, 0.0, 0.46)), "joint", spine)
        self.part("coreFrame", C.bm_xform(C.bm_cyl(16, 0.075, 0.075, 0.04), loc=(0, -0.18 * td, 0.30),
                  rot=(math.pi / 2, 0, 0)), "armor_dark", spine)
        self.part("core", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.20 * td, 0.30), scale=(0.055, 0.025, 0.055)),
                  "glow", spine, nofs=True)
        self.part("coreHot", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -0.215 * td, 0.30), scale=(0.025, 0.012, 0.025)),
                  "core", spine, nofs=True)

    def build_arms(self, spine) -> None:
        j = self.j
        aw, al = self.AW, self.AL
        for side, sx in (("L", 1), ("R", -1)):
            ua = j["ua" + side] = qjoint("ua" + side, spine, self.shoulder[side])
            fa = j["fa" + side] = qjoint("fa" + side, spine, (0, 0, 0))
            pad = C.bm_sphere(14, 10, 1.0)
            for v in pad.verts:
                if v.co.z < -0.3:
                    v.co.z = -0.3
            self.part("pauldron" + side, C.bm_xform(pad, loc=(0.03 * sx, 0, 0.02),
                      scale=(0.13 * aw, 0.13 * aw, 0.12 * aw)), "armor", ua)
            self.part("uarm" + side, C.bm_xform(C.bm_cyl(10, 0.06 * aw, 0.055 * aw, 0.20 * al),
                      loc=(0, 0, -0.10 * al)), "joint", ua)
            self.part("elbow" + side, C.bm_xform(C.bm_sphere(10, 8, 0.065 * aw)), "joint", fa)
            self.build_forearm(side, sx, fa)

    def build_forearm(self, side: str, sx: int, fa) -> None:
        aw, al = self.AW, self.AL
        self.part("farm" + side, C.bm_xform(C.bm_box(0.15 * aw, 0.15 * aw, 0.20 * al, bevel=0.03),
                  loc=(0, 0, -0.10 * al)), "armor", fa)
        self.part("fist" + side, C.bm_xform(C.bm_box(0.12 * aw, 0.11 * aw, 0.11 * aw, bevel=0.03),
                  loc=(0, 0, -self.ll)), "armor_dark", fa)

    def build_legs(self, pelvis) -> None:
        j, LEG = self.j, self.LEG
        bw = 1.0 + 0.25 * (self.TW - 1.0)
        for side, sx in (("L", 1), ("R", -1)):
            hip = j["hip" + side] = joint("hip" + side, pelvis, (0.12 * sx * bw, 0, -0.04))
            knee = j["knee" + side] = joint("knee" + side, hip, (0, 0, -0.36 * LEG))
            self.part("thigh" + side, C.bm_xform(C.bm_box(0.15 * bw, 0.16 * bw, 0.34 * LEG, bevel=0.03),
                      loc=(0, 0, -0.17 * LEG)), "armor", hip)
            self.part("kneeCap" + side, C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, -0.05, 0.0),
                      scale=(0.075, 0.06, 0.07)), "armor_dark", knee)
            self.part("shin" + side, C.bm_xform(C.bm_box(0.14 * bw, 0.16 * bw, 0.30 * LEG, bevel=0.03),
                      loc=(0, 0, -0.15 * LEG)), "armor", knee)
            fz = -0.345 + 0.41 * (1 - LEG)
            self.part("foot" + side, C.bm_xform(C.bm_box(0.16 * bw, 0.27 * bw, 0.09, bevel=0.03),
                      loc=(0, -0.05, fz + 0.03)), "armor_dark", knee)

    def muzzle_world(self) -> Vector:
        return self.j["faR"].matrix_world @ Vector((0, 0, -self.ll))


class Guardian(SlamMixin, Armored):
    """Gardien des glaces : golem blindé bleu nuit, couvert de cristaux, visière et cœur cyan."""

    def dress(self) -> None:
        sp = self.j["spine"]
        tw = self.TW
        for sx in (1, -1):
            crystal_cluster(self, "ice", self.j["ua" + ("L" if sx > 0 else "R")], (0.04 * sx, 0.0, 0.10),
                            (0.6 * sx, 0.2, 1.0), 4, 0.28, 0.055, 31 + sx)
            place_shard(self, "backSpire", "frost", sp, (0.10 * sx * tw, 0.18, 0.40), (0.3 * sx, 0.8, 1.0), 0.30, 0.06)
        for side, sx in (("L", 1), ("R", -1)):
            fa = self.j["fa" + side]
            place_shard(self, "fistShard", "ice", fa, (0.06 * sx, 0.0, -self.ll), (0.5 * sx, -0.3, -0.6), 0.14, 0.04)
            place_shard(self, "fistShard2", "frost", fa, (0.0, -0.06, -self.ll - 0.02), (0.0, -0.8, -0.6), 0.12, 0.035)
        self.part("helmShard", C.bm_xform(shard(0.16, 0.05), loc=(0, 0.02, 0.32)), "ice", self.j["head"], smooth=False)


class Mechanic(GunMixin, Armored):
    """Mécanicien de l'Éternité : mécha laiton, œil cyclope cyan, canon-outil au bras droit, clé à la main
    gauche, sac de réservoirs et antenne."""

    def build_head(self, head) -> None:
        hb = C.bm_sphere(20, 14, 1.0)
        for v in hb.verts:
            v.co = Vector((v.co.x * 0.20, v.co.y * 0.20, v.co.z * 0.17 + 0.18))
        self.part("dome", hb, "armor", head)
        self.part("eyeFrame", C.bm_xform(C.bm_cyl(16, 0.075, 0.075, 0.05), loc=(0, -0.17, 0.20),
                  rot=(math.pi / 2, 0, 0)), "armor_dark", head)
        self.part("eyeLens", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.20, 0.20), scale=(0.058, 0.025, 0.058)),
                  "visor", head, nofs=True)
        self.part("eyeHot", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -0.215, 0.20), scale=(0.026, 0.012, 0.026)),
                  "core", head, nofs=True)
        self.part("grill", C.bm_xform(C.bm_box(0.18, 0.10, 0.07, bevel=0.02), loc=(0, -0.10, 0.06)), "armor_dark", head)
        self.part("antenna", C.bm_xform(C.bm_cyl(6, 0.012, 0.008, 0.22), loc=(0.10, 0.04, 0.42)), "metal_dark", head)
        self.part("antTip", C.bm_xform(C.bm_sphere(8, 6, 0.025), loc=(0.10, 0.04, 0.54)), "spark", head, nofs=True)

    def build_forearm(self, side: str, sx: int, fa) -> None:
        aw, al = self.AW, self.AL
        if side == "R":
            self.part("gunBody", C.bm_xform(C.bm_box(0.15 * aw, 0.15 * aw, 0.28 * al, bevel=0.03),
                      loc=(0, 0, -0.13 * al)), "armor", fa)
            self.part("barrel", C.bm_xform(C.bm_cyl(12, 0.045, 0.04, 0.18), loc=(0, 0, -0.32 * al)), "gun", fa)
            self.part("barrelGlow", C.bm_xform(C.bm_cyl(12, 0.03, 0.03, 0.02), loc=(0, 0, -0.42 * al)), "visor", fa,
                      nofs=True)
            self.part("coil", C.bm_xform(C.bm_torus(14, 4, 0.06, 0.014), loc=(0, 0, -0.26 * al)), "spark", fa,
                      nofs=True)
            self._muzzle_local = (0.0, 0.0, -0.44 * al)
        else:
            super().build_forearm(side, sx, fa)
            # clé à molette géante
            self.part("wrench", C.bm_xform(C.bm_box(0.04, 0.04, 0.40), loc=(0, -0.04, -self.ll - 0.08)), "metal", fa)
            self.part("wrenchHead", C.bm_xform(C.bm_torus(12, 5, 0.06, 0.025), loc=(0, -0.04, -self.ll - 0.30),
                      rot=(0, math.pi / 2, 0)), "metal", fa)

    def dress(self) -> None:
        sp = self.j["spine"]
        tw, td = self.TW, self.TD
        self.part("pack", C.bm_xform(C.bm_box(0.36 * tw, 0.16, 0.30, bevel=0.03), loc=(0, 0.21 * td, 0.30)),
                  "armor_dark", sp)
        for sx in (1, -1):
            self.part("tank", C.bm_xform(C.bm_cyl(12, 0.055, 0.055, 0.30), loc=(0.10 * sx, 0.30 * td, 0.30)),
                      "metal", sp)
            self.part("tankGlow", C.bm_xform(C.bm_cyl(12, 0.057, 0.057, 0.05), loc=(0.10 * sx, 0.30 * td, 0.36)),
                      "glow", sp, nofs=True)
            self.part("pipe", C.bm_tube([(0.10 * sx, 0.30 * td, 0.46), (0.16 * sx, 0.18, 0.52), (0.22 * sx, 0.0, 0.46)],
                                        [0.018] * 3, seg=6), "joint", sp)
        for k in range(3):
            self.part("rivet", C.bm_xform(C.bm_sphere(6, 4, 0.016), loc=(-0.12 + 0.12 * k, -0.18 * td, 0.42)),
                      "metal", sp)

    def pose_run(self, i: int, n: int) -> None:
        Human.pose_run(self, i, n)
        self.j["pelvis"].location.z -= 0.03


CLASSES = {
    "ice_wolf": Quad, "ice_spider": PolarSpider, "ice_drone": Drone, "ice_bear": Quad, "ice_elemental": Elemental,
    "ice_hunter": Hunter, "ice_glacier_guardian": Guardian, "ice_eternal_mechanic": Mechanic, "ice_titan": Titan,
}


# =============================================================================== rendu
def anims_for(kind: str) -> dict:
    a = dict(ANIMS_BASE)
    r = SPEC[kind].get("fps_run")
    if r:
        a["run"] = (8, r, True)
    a.update(SPEC[kind].get("anims", {}))
    return a


def setup_scene(kind: str):
    C.reset_scene()
    F = frame_of(kind)
    C.setup_render((F * SS, F * SS), samples=4, outline_px=4.6)
    rig = CLASSES[kind](kind)
    ortho = 2.30 * F / 160.0
    tz = CAM_TARGET_Z * F / BASE_FRAME + SPEC[kind].get("cam_dz", 0.0)
    cam = C.ortho_camera(ELEV, ortho, target=(0, 0, tz))
    cam.data.sensor_fit = "VERTICAL"
    return rig, cam


def render_frame(path: str, F: int):
    big = path + ".big.png"
    C.render_to(big)
    im = C.downscale(big, path, (F, F))
    os.remove(big)
    return im


def pack(frames: dict, order: list, F: int) -> tuple:
    from PIL import Image
    items = []
    for key in order:
        im = frames[key]
        a = im.getchannel("A").point(lambda v: 255 if v > 3 else 0)
        bb = a.getbbox() or (0, 0, 1, 1)
        bb = (max(0, bb[0] - 1), max(0, bb[1] - 1), min(F, bb[2] + 1), min(F, bb[3] + 1))
        items.append((key, im.crop(bb), bb))
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
    path = os.path.join(OUT_DIR, kind, "%s_atlas.png.import" % kind)
    src = "res://assets/sprites/enemies/%s/%s_atlas.png" % (kind, kind)
    if os.path.exists(path):
        with open(path) as f:
            if "compress/mode=2" in f.read():
                return
    with open(path, "w") as f:
        f.write(IMPORT_TEMPLATE % src)


def write_tres(kind: str, anims: dict, regions: dict, meta: dict) -> None:
    F = out_frame(kind)
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
                lines.append("margin = Rect2(%d, %d, %d, %d)" % (ox, oy, F - w, F - h))
                lines.append("filter_clip = true")
                lines.append("")
            fr = ", ".join('{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % s for s in ids)
            out.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s_%s",\n"speed": %.1f\n}'
                       % (fr, "true" if loop else "false", anim, d, float(fps)))
    lines.append("[resource]")
    lines.append("animations = [%s]" % ", ".join(out))
    lines.append("metadata/enemy_meta = %s" % json.dumps(meta, ensure_ascii=False))
    with open(os.path.join(OUT_DIR, kind, "%s_frames.tres" % kind), "w") as f:
        f.write("\n".join(lines) + "\n")


def measure(im) -> tuple:
    return im.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()


def muzzle_px(rig: Rig, cam) -> list:
    bpy.context.view_layer.update()
    p = C.world_to_px(cam, rig.muzzle_world())
    k = out_k(rig.kind)
    return [round(p[0] / SS * k, 1), round(p[1] / SS * k, 1)]


def make_meta(kind: str, frames: dict, feet, muzzle: dict) -> dict:
    F = out_frame(kind)
    anims = anims_for(kind)
    bb = measure(frames[("idle", "s", 0)])
    corpse = {}
    for d in DIRS:
        cb = measure(frames[("death", d, anims["death"][0] - 1)])
        corpse[d] = [cb[0], cb[1], cb[2], cb[3]]
    return {
        "kind": kind,
        "name": SPEC[kind]["name"],
        "frame_size": [F, F],
        "feet_offset": [feet[0], feet[1]],
        "display_height": round(frame_of(kind) * WORLD_PER_PX, 1),
        "world_per_px": round(WORLD_PER_PX / out_k(kind), 6),
        "height_px": bb[3] - bb[1],
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
                 "dernière image est le cadavre au sol. muzzle_px = bout du canon / de la griffe (image attack 3).",
    }


def build_kind(kind: str) -> None:
    t0 = time.time()
    rig, cam = setup_scene(kind)
    F = frame_of(kind)
    anims = anims_for(kind)
    od = os.path.join(OUT_DIR, kind)
    os.makedirs(od, exist_ok=True)
    tmp = os.path.join(TMP_DIR, kind)
    os.makedirs(tmp, exist_ok=True)
    bpy.context.view_layer.update()
    feet = C.world_to_px(cam, (0, 0, 0))
    feet = (round(feet[0] / SS * out_k(kind)), round(feet[1] / SS * out_k(kind)))
    frames, order, muzzle = {}, [], {}
    for d, ang in DIRS.items():
        rig.j["root"].rotation_euler = (0, 0, math.radians(ang))
        rig.dir_ang = ang
        for anim, (n, _f, _l) in anims.items():
            for i in range(n):
                rig.pose(anim, i, n)
                p = os.path.join(tmp, "%s_%s_%d.png" % (anim, d, i))
                frames[(anim, d, i)] = render_frame(p, out_frame(kind))
                order.append((anim, d, i))
                if anim == "attack" and i == 3:
                    muzzle[d] = muzzle_px(rig, cam)
        print(kind, "DIR", d, "%.0fs" % (time.time() - t0), flush=True)
    atlas, regions = pack(frames, order, out_frame(kind))
    compact_png(atlas, os.path.join(od, "%s_atlas.png" % kind))
    write_import(kind)
    meta = make_meta(kind, frames, feet, muzzle)
    with open(os.path.join(od, "%s_meta.json" % kind), "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
        f.write("\n")
    write_tres(kind, anims, regions, meta)
    print("DONE", kind, "%.0fs" % (time.time() - t0), "atlas", atlas.size, flush=True)


def repack(kind: str) -> None:
    """Refait atlas + SpriteFrames + méta depuis les images déjà rendues (TMP_DIR/<kind>) : la scène
    est reconstruite sans rendu pour mesurer pieds et canon."""
    from PIL import Image
    rig, cam = setup_scene(kind)
    F = frame_of(kind)
    anims = anims_for(kind)
    od = os.path.join(OUT_DIR, kind)
    os.makedirs(od, exist_ok=True)
    tmp = os.path.join(TMP_DIR, kind)
    bpy.context.view_layer.update()
    feet = C.world_to_px(cam, (0, 0, 0))
    feet = (round(feet[0] / SS * out_k(kind)), round(feet[1] / SS * out_k(kind)))
    frames, order, muzzle = {}, [], {}
    for d, ang in DIRS.items():
        rig.j["root"].rotation_euler = (0, 0, math.radians(ang))
        rig.dir_ang = ang
        rig.pose("attack", 3, anims["attack"][0])
        muzzle[d] = muzzle_px(rig, cam)
        for anim, (n, _f, _l) in anims.items():
            for i in range(n):
                frames[(anim, d, i)] = Image.open(os.path.join(tmp, "%s_%s_%d.png" % (anim, d, i))).convert("RGBA")
                order.append((anim, d, i))
    atlas, regions = pack(frames, order, out_frame(kind))
    compact_png(atlas, os.path.join(od, "%s_atlas.png" % kind))
    meta = make_meta(kind, frames, feet, muzzle)
    with open(os.path.join(od, "%s_meta.json" % kind), "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
        f.write("\n")
    write_tres(kind, anims, regions, meta)
    write_import(kind)
    print("REPACK", kind, atlas.size)


def preview(kinds, dirs, anims_spec) -> None:
    from PIL import Image
    for kind in kinds:
        rig, cam = setup_scene(kind)
        F = frame_of(kind)
        tiles = []
        for d in dirs:
            rig.j["root"].rotation_euler = (0, 0, math.radians(DIRS[d]))
            rig.dir_ang = DIRS[d]
            for a in anims_spec:
                an, i = a.split(":")
                n = anims_for(kind)[an][0]
                rig.pose(an, int(i), n)
                p = os.path.join(TMP_DIR, "prev_%s_%s_%s_%s.png" % (kind, an, d, i))
                tiles.append(render_frame(p, F))
        sheet = Image.new("RGBA", (F * len(tiles), F), (60, 84, 120, 255))
        for k, t in enumerate(tiles):
            sheet.alpha_composite(t, (k * F, 0))
        out = os.path.join(TMP_DIR, "prev_%s.png" % kind)
        sheet.save(out)
        print("PREVIEW", out)


def presentation_sheet(kinds) -> None:
    """Planche de présentation (captures de PR) : idle 3/4 face + attaque + cadavre, à l'échelle du jeu,
    sur fond bleu glacier, depuis les images déjà rendues (TMP_DIR)."""
    from PIL import Image, ImageDraw, ImageFont
    fb = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    fr = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    title_f = ImageFont.truetype(fb, 30)
    name_f = ImageFont.truetype(fb, 17)
    sub_f = ImageFont.truetype(fr, 13)
    cols = 3
    cell_w, cell_h = 440, 330
    rows = (len(kinds) + cols - 1) // cols
    W, H = cols * cell_w + 40, rows * cell_h + 90
    sheet = Image.new("RGBA", (W, H), (10, 18, 34, 255))
    dr = ImageDraw.Draw(sheet)
    for y in range(H):
        c = int(12 + 22 * y / H)
        dr.line([(0, y), (W, y)], fill=(c - 4, c + 6, c + 26, 255))
    dr.text((24, 20), "LES TERRES GELÉES — Le désert de glace", font=title_f, fill=(140, 236, 255, 255))
    tags = {"ice_glacier_guardian": "ÉLITE", "ice_eternal_mechanic": "ÉLITE", "ice_titan": "BOSS"}
    for idx, kind in enumerate(kinds):
        cx = 20 + (idx % cols) * cell_w
        cy = 80 + (idx // cols) * cell_h
        dr.rounded_rectangle([cx, cy, cx + cell_w - 12, cy + cell_h - 12], 14, fill=(16, 30, 54, 235),
                             outline=(110, 210, 255, 255), width=2)
        tmp = os.path.join(TMP_DIR, kind)
        F = out_frame(kind)
        n_death = anims_for(kind)["death"][0]
        shots = [("idle_se_0", "idle"), ("attack_sw_3", "attaque"), ("death_s_%d" % (n_death - 1), "cadavre")]
        if F > 256:
            shots = shots[:2]
        w = (cell_w - 32) // len(shots)
        # échelle commune : 1 px de rendu = 1 px affiché ; le boss est réduit pour tenir dans la case
        k = min(1.0, (cell_h - 70) / F, 1.15 * w / F if F > 192 else 9.0)
        x = cx + 10
        for fname, label in shots:
            path = os.path.join(tmp, fname + ".png")
            if not os.path.exists(path):
                continue
            im = Image.open(path).convert("RGBA")
            if k < 1.0:
                im = im.resize((int(F * k), int(F * k)), Image.LANCZOS)
            sheet.alpha_composite(im, (x + (w - im.size[0]) // 2, cy + 46 + (cell_h - 110 - im.size[1]) // 2 + 10))
            dr.text((x + w // 2 - 20, cy + cell_h - 40), label, font=sub_f, fill=(190, 190, 210, 255))
            x += w
        nm = SPEC[kind]["name"].upper()
        dr.text((cx + 14, cy + 10), nm, font=name_f, fill=(255, 255, 255, 255))
        if kind in tags:
            col = (255, 110, 90, 255) if tags[kind] == "BOSS" else (200, 150, 255, 255)
            dr.text((cx + cell_w - 90, cy + 10), tags[kind], font=name_f, fill=col)
        dr.text((cx + 14, cy + 30), kind, font=sub_f, fill=(150, 150, 175, 255))
    os.makedirs(CAPT_DIR, exist_ok=True)
    out = os.path.join(CAPT_DIR, "planche_modeles_frozen.png")
    sheet.convert("RGB").save(out)
    print("SHEET", out)


def main() -> None:
    args = sys.argv[1:]
    kinds = args[args.index("--kinds") + 1].split(",") if "--kinds" in args else KINDS
    os.makedirs(TMP_DIR, exist_ok=True)
    if "--sheet" in args:
        presentation_sheet(kinds)
        return
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
