"""Bestiaire du centre commercial abandonné (« Les égarés de la nuit ») : modélisation 3D scriptée,
rigs, animations, rendus 8 directions, planches compactes (atlas rogné) + SpriteFrames + méta JSON.

Même pipeline que les hors-la-loi (art/blender/build_enemies.py) et que le héros : caméra
orthographique 3/4 à 48°, matériaux toon peints, contour Freestyle, même densité de pixels et même
échelle monde (WORLD_PER_PX). Les grands gabarits (gros brute, boss) ont un cadre plus grand à la
même densité de pixels.

Ambiance de la planche : nuit, néons violets et rouges (accents émissifs lisibles sur mobile).

Usage (depuis la racine du projet ; rendus : passer par le verrou flock du projet) :
    python3 art/blender/bestiary/mall/build_mall_bestiary.py                    # tous
    python3 art/blender/bestiary/mall/build_mall_bestiary.py --kinds mall_zombie,mall_brute
    python3 art/blender/bestiary/mall/build_mall_bestiary.py --preview s,se --anim idle:0,attack:3 --kinds mall_zombie
    python3 art/blender/bestiary/mall/build_mall_bestiary.py --repack --kinds mall_zombie
    python3 art/blender/bestiary/mall/build_mall_bestiary.py --sheet            # planche de présentation

Bestiaire (ids) :
    mall_zombie        Zombie : client en lambeaux, bras tendus, lent
    mall_flayer        Écorcheur : créature décharnée, lames rouges aux avant-bras, bondit
    mall_security_bot  Sécurité robot : robot blindé bleu nuit, visière rouge, canon au bras
    mall_clone         Clone : silhouette à capuche (sac et couteau, comme un pillard), yeux violets
    mall_brute         Gros brute : énorme mutant, poings de béton, frappe au sol
    mall_night_spider  Nuit blanche : araignée violette lumineuse
    mall_violent       Le Violent (élite) : mutant musclé rouge, griffes, tatouages néon
    mall_store_warden  Le Gardien de magasin (élite) : robot rouge et blanc, fusil, bouclier
    mall_omnistore     L'Omnistore (boss) : masse de chair, pattes, écrans, gueule pleine de dents

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
CAPT_DIR = os.path.join(ROOT, "docs", "bestiaire", "captures", "mall")
TMP_DIR = os.environ.get("RDM_TMP", "/tmp/rdm_mall_bestiary")

SS = 2
ELEV = 48.0
BASE_FRAME = 192
CAM_TARGET_Z = 0.86
# Échelle monde : identique au héros et aux hors-la-loi (92,3 unités pour 160 px).
WORLD_PER_PX = 92.3 / 160.0

DIRS = {"e": 90.0, "se": 45.0, "s": 0.0, "sw": -45.0, "w": -90.0, "nw": -135.0, "n": 180.0, "ne": 135.0}
ANIMS_BASE = {
    "idle": (6, 7, True),
    "run": (8, 14, True),
    "attack": (6, 12, False),
    "hit": (3, 14, False),
    "death": (8, 12, False),
}

# Nuit : lumière un peu plus froide et rosée que le coucher de soleil du Far West.
C.WARM = (1.04, 0.90, 1.02)

# ----------------------------------------------------------------------------- matériaux
COMMON_MATS = {
    "eye": ("#140c18", None, None),
    "metal": ("#7a7e92", "#24263e", "#c8ccdc"),
    "metal_dark": ("#34343e", "#101018", "#5c5c6a"),
    "bone": ("#ddd0b4", "#6a5a6e", "#fff4dc"),
    "tooth": ("#efe6cc", "#7a6e80", "#ffffff"),
    "strap": ("#2c2228", "#0c080e", "#4a3a40"),
    "jeans": ("pat", [("#34466a", "#10162e", "#52689a"), ("#2c3a58", "#0c1226", "#465a86")], 7.0),
}

SPEC: dict[str, dict] = {
    "mall_zombie": {
        "name": "Zombie", "rig": "human", "frame": 192, "scale": 1.0, "head": 1.16, "leg": 0.80,
        "torso": (0.98, 0.92), "arm": 0.90, "arm_len": 1.08, "hunch": 0.30, "fps_run": 9, "top_key": "skin",
        "mats": {
            "skin": ("pat", [("#6a7064", "#1e1c36", "#8e9682"), ("#5e4858", "#1a1028", "#7e6274"),
                             ("#76705e", "#262036", "#9a9078")], 5.0),
            "wound": ("#6e1424", "#2a0618", "#9a2232"),
            "mouth": ("#2a0814", "#100208", "#4a1222"),
            "shirt": ("pat", [("#4e4a60", "#16142c", "#6c6888"), ("#3e3a50", "#100e24", "#5a5672")], 6.0),
            "pants": "jeans",
            "shoe": ("#3a3032", "#100c14", "#5a4c4e"),
            "eye_glow": "!#f0f0a0",
            "hair": ("#2a2226", "#0c080c", "#46383c"),
        },
    },
    "mall_flayer": {
        "name": "Écorcheur", "rig": "human", "frame": 192, "scale": 1.04, "head": 0.98, "leg": 0.86,
        "torso": (0.86, 0.80), "arm": 0.76, "arm_len": 1.22, "hunch": 0.42, "fps_run": 16, "top_key": "skin",
        "mats": {
            "skin": ("pat", [("#a4462e", "#3a0e24", "#d8704c"), ("#7e2e28", "#2a0a1e", "#ac4c3c"),
                             ("#c06a4a", "#44162a", "#e8946a")], 7.0),
            "sinew": ("#6a1c22", "#22061a", "#9a3036"),
            "pants": ("#2e2430", "#0c0812", "#4a3c4a"),
            "shoe": ("#2e2430", "#0c0812", "#4a3c4a"),
            "blade": ("#3a2a30", "#0e0810", "#6a4a52"),
            "blade_edge": "!#ff2a3a",
            "eye_glow": "!#ffc040",
        },
    },
    "mall_security_bot": {
        "name": "Sécurité robot", "rig": "human", "frame": 192, "scale": 1.08, "head": 1.10, "leg": 0.82,
        "torso": (1.22, 1.10), "arm": 1.22, "arm_len": 1.0, "hunch": 0.04, "fps_run": 12,
        "mats": {
            "armor": ("#3e4862", "#121630", "#6e7ea4"),
            "armor_dark": ("#262a3c", "#0a0c1a", "#44485e"),
            "joint": ("#1c1e2a", "#08080e", "#383a4a"),
            "visor": "!#ff2434",
            "light_red": "!#ff3a2a",
            "gun": ("#2a2c36", "#0a0a12", "#4e505e"),
            "pants": ("#262a3c", "#0a0c1a", "#44485e"),
            "shoe": ("#1c1e2a", "#08080e", "#383a4a"),
            "stripe": ("#c8ccd8", "#4a4e6a", "#ffffff"),
        },
    },
    "mall_clone": {
        "name": "Clone", "rig": "human", "frame": 192, "scale": 1.0, "head": 1.24, "leg": 0.82,
        "torso": (0.96, 0.94), "arm": 0.92, "arm_len": 1.0, "hunch": 0.10, "fps_run": 15,
        "sleeve_key": "jacket", "shoulder_key": "jacket",
        "mats": {
            "hoodie": ("pat", [("#34324a", "#0e0c20", "#56547a"), ("#2a2840", "#0a0818", "#46446a")], 6.0),
            "jacket": ("#3c3c54", "#10102a", "#62628a"),
            "shirt": ("#8a1e2e", "#320818", "#c03040"),
            "pants": "jeans",
            "shoe": ("#262230", "#0a0810", "#443e52"),
            "face": ("#0c0a14", None, None),
            "eye_glow": "!#d27aff",
            "pack": ("#3e3a32", "#12100e", "#625a4c"),
            "skin": ("#6a5a6a", "#241a30", "#8a7888"),
            "blade": ("#9aa0b4", "#30344a", "#e4e8f4"),
            "smoke": "!#9a4aff",
        },
    },
    "mall_brute": {
        "name": "Gros brute", "rig": "human", "frame": 256, "scale": 1.42, "head": 1.22, "leg": 0.74,
        "torso": (1.62, 1.34), "arm": 1.70, "arm_len": 1.16, "hunch": 0.24, "belly": 0.6, "fps_run": 10, "top_key": "skin",
        "mats": {
            "skin": ("pat", [("#7e6c70", "#20142e", "#a28e8e"), ("#6a5660", "#1a1028", "#8a747e"),
                             ("#76646e", "#1e1230", "#988290")], 4.0),
            "vein": ("#6a2a5a", "#260a2a", "#9a4a86"),
            "pants": ("pat", [("#3a3044", "#100c1c", "#5e5070"), ("#30283a", "#0c0816", "#4c4060")], 6.0),
            "shoe": ("#2a2228", "#0a080c", "#463a40"),
            "bracer": ("#5e626e", "#1c1e2c", "#9a9eae"),
            "chain": ("#8a8c98", "#2a2c3e", "#d0d2dc"),
            "eye_glow": "!#ff4a3a",
            "wound": ("#8e1a2c", "#36081e", "#c02a3a"),
            "metal": ("#6a6e7e", "#1e2032", "#a8acbc"),
        },
    },
    "mall_night_spider": {
        "name": "Nuit blanche", "rig": "spider", "frame": 192, "scale": 1.22, "fps_run": 18,
        "legs": 4, "body_z": 0.40, "femur": 0.56, "tibia": 0.66, "spread": 0.80,
        "mats": {
            "carapace": ("pat", [("#4a2a72", "#140a2a", "#7a52b0"), ("#3a2060", "#100822", "#62409a")], 5.0),
            "leg": ("#4a2e72", "#140a2a", "#7e5ab4"),
            "leg_tip": ("#2e1c4a", "#0c061c", "#5e3e8e"),
            "glow": "!#c35cff",
            "glow_soft": "!#8a3aff",
            "eye_glow": "!#ff3a7a",
            "fang": ("#d8c8e0", "#5a4a6a", "#ffffff"),
        },
    },
    "mall_violent": {
        "name": "Le Violent", "rig": "human", "frame": 224, "scale": 1.22, "head": 1.08, "leg": 0.80,
        "torso": (1.36, 1.10), "arm": 1.36, "arm_len": 1.18, "hunch": 0.36, "fps_run": 15, "top_key": "skin",
        "mats": {
            "skin": ("pat", [("#9a4036", "#2e0a1e", "#c2604c"), ("#7e3030", "#26081a", "#a24840"),
                             ("#a84c44", "#34102a", "#cc6e5e")], 5.0),
            "vein": ("#6a1a3a", "#22061a", "#9a2e52"),
            "tattoo": "!#ff4ad2",
            "pants": ("#2a2030", "#0a0610", "#463650"),
            "shoe": ("#2a2030", "#0a0610", "#463650"),
            "strap": ("#3a2a22", "#0e0808", "#5a4436"),
            "claw": ("#e8dcc4", "#6a5a6e", "#ffffff"),
            "eye_glow": "!#ffd040",
            "metal": ("#7a7e92", "#24263e", "#c8ccdc"),
        },
    },
    "mall_store_warden": {
        "name": "Le Gardien de magasin", "rig": "human", "frame": 224, "scale": 1.18, "head": 1.10, "leg": 0.84,
        "torso": (1.28, 1.08), "arm": 1.18, "arm_len": 1.02, "hunch": 0.02, "fps_run": 12,
        "mats": {
            "armor": ("#c41e2c", "#4a0820", "#ee4a4a"),
            "armor_dark": ("#22222c", "#08080e", "#40404e"),
            "white": ("#e8e6ee", "#7a7894", "#ffffff"),
            "joint": ("#1a1a22", "#06060a", "#34343e"),
            "visor": "!#ff2a2a",
            "light_red": "!#ff3a2a",
            "gun": ("#2a2c36", "#0a0a12", "#4e505e"),
            "pants": ("#22222c", "#08080e", "#40404e"),
            "shoe": ("#1a1a22", "#06060a", "#34343e"),
            "stripe": ("#e8e6ee", "#7a7894", "#ffffff"),
            "shield": "!#ff5a6a",
        },
    },
    "mall_omnistore": {
        "name": "L'Omnistore", "rig": "boss", "frame": 384, "scale": 1.5, "fps_run": 12, "cam_dz": 0.25,
        "out_scale": 0.72, "anims": {"idle": (4, 6, True), "run": (6, 10, True), "death": (6, 9, False)},
        "mats": {
            "flesh": ("pat", [("#7e1e3e", "#2a0626", "#b23a62"), ("#561a4e", "#1a0626", "#80306e"),
                              ("#962a46", "#30082a", "#c84a6a")], 3.5),
            "flesh_dark": ("#3e0e2e", "#14041a", "#5e1e46"),
            "leg": ("pat", [("#2c2232", "#0a0610", "#504058"), ("#3a1a30", "#10060e", "#5e2a4a")], 4.0),
            "claw": ("#d8c8d4", "#5a4a62", "#ffffff"),
            "tooth": ("#f2e8cc", "#7a6a7a", "#ffffff"),
            "maw": "!#ff2e56",
            "gum": ("#a01c3a", "#3a0620", "#d03a5a"),
            "frame_tv": ("#1c1a24", "#06060a", "#3a3646"),
            "screen": "!#d892ff",
            "screen2": "!#ffffff",
            "screen3": "!#ff5aa8",
            "neon": "!#ff3ad0",
            "eye_glow": "!#ffe060",
            "cable": ("#1e1a22", "#06040a", "#3a3442"),
            "tag": ("#e8e2d0", "#7a7488", "#ffffff"),
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
class Zombie(Human):
    def build_head(self, head) -> None:
        self.skull(head, "skin", jaw=0.12)
        self.eyes(head, "eye_glow", r=(0.028, 0.010, 0.020), brow_key="hair", angle=0.1)
        self.part("nose", C.bm_xform(C.bm_sphere(10, 7, 1.0), loc=(0, -0.170, 0.175),
                  scale=(0.03, 0.03, 0.03)), "skin", head)
        # mâchoire pendante, bouche sombre
        self.part("mouth", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.150, 0.095),
                  scale=(0.045, 0.025, 0.028)), "mouth", head, nofs=True)
        for sx in (1, -1):
            self.part("ear", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.178 * sx, 0.0, 0.19),
                      scale=(0.025, 0.04, 0.05)), "skin", head)

    def dress(self) -> None:
        sp = self.j["spine"]
        pel = self.j["pelvis"]
        tw, td = self.TW, self.TD
        # chemise déchirée : lambeaux sur le torse (ventre et côtes visibles devant)
        sh = []
        for z, r1, r2 in ((0.10, 0.205, 0.150), (0.24, 0.236, 0.160), (0.40, 0.232, 0.150)):
            sh.append(C.ellipse(0, 0.0, z, r1 * tw + 0.012, r2 * td + 0.012, 20))
        shirt = C.bm_loft(sh, cap_start=False, cap_end=False)
        for f in list(shirt.faces):
            c = f.calc_center_median()
            if c.y < -0.08 * td and abs(c.x) < 0.13 * tw and c.z < 0.34:
                shirt.faces.remove(f)
        self.part("shirt", shirt, "shirt", sp, thick=0.012)
        # lambeaux pendants
        for k, (x, z) in enumerate(((0.16, 0.10), (-0.18, 0.12), (0.08, 0.08), (-0.10, 0.06))):
            sx = 1 if x > 0 else -1
            self.part("rag%d" % k, C.bm_tube([(x * tw, -0.12 * td, z), (x * tw * 1.05, -0.14 * td, z - 0.08),
                                              (x * tw * 1.1 + 0.02 * sx, -0.13 * td, z - 0.16)],
                                             [0.035, 0.03, 0.006], seg=6, flat=0.3, up=(0, 1, 0)), "shirt", sp)
        # côtes et plaies
        for k in range(3):
            self.part("rib", C.bm_xform(C.bm_box(0.13, 0.014, 0.014, bevel=0.004),
                      loc=(0.03, -0.152 * td, 0.20 + 0.045 * k), rot=(0, 0.15, 0)), "bone", sp)
        self.part("wound1", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(-0.07, -0.150 * td, 0.12),
                  scale=(0.05, 0.02, 0.06)), "wound", sp, nofs=True)
        self.part("wound2", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.15 * tw, -0.10, 0.30),
                  scale=(0.04, 0.03, 0.05)), "wound", sp, nofs=True)
        # ceinture et jean déchiré
        self.part("belt", C.bm_xform(C.bm_cyl(18, 0.222 * tw, 0.222 * tw, 0.05), loc=(0, 0, 0.05),
                  scale=(1, 0.74 * td / tw, 1)), "strap", pel)
        for side in ("L", "R"):
            self.part("rip", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -0.09, -0.02),
                      scale=(0.05, 0.02, 0.06)), "skin", self.j["knee" + side], nofs=True)

    def arms_rest(self, b: float = 0.0) -> None:
        # bras ballants, un peu en avant, une main tendue
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.04, -0.18, -0.30 + 0.015 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.02, -0.30, -0.16 + 0.02 * b)), self.R_POLE)

    def idle_extra(self, t: float) -> None:
        self.j["neck"].rotation_euler = (-0.1, 0.0, 0.22 + 0.05 * math.sin(t))

    def pose_run(self, i: int, n: int) -> None:
        # démarche traînante : boiterie, bras tendus vers l'avant
        self.rest()
        j = self.j
        p = 2 * math.pi * i / n
        s = math.sin(p)
        j["pelvis"].location.z = self.PZ - 0.03 + 0.035 * abs(math.sin(p + 0.35)) - 0.02 * max(0, -s)
        j["pelvis"].rotation_euler = (0, 0.06 * s, -0.12 * s)
        self.spine_rot(0.16, 0.08 * s, 0.10 * s)
        self.legs((-0.5 * s - 0.10, 0, 0.05), (0.45 * s - 0.10, 0, -0.05),
                  0.18 + 0.8 * max(0.0, math.sin(p - 1.0)) ** 1.2,
                  0.25 + 0.55 * max(0.0, math.sin(p - 1.0 + math.pi)) ** 1.2)
        sh = self.shoulder
        self.arm_ik("L", sh["L"] + Vector((0.02, -0.36, -0.06 + 0.03 * s)), self.L_POLE)
        self.arm_ik("R", sh["R"] + Vector((-0.02, -0.38, -0.02 - 0.03 * s)), self.R_POLE)
        j["neck"].rotation_euler = (-0.05, 0.0, 0.25)

    def pose_attack(self, i: int, n: int) -> None:
        # agrippe à deux mains puis mord / griffe vers le bas
        self.rest()
        j = self.j
        lean = (0.05, -0.12, -0.16, 0.45, 0.35, 0.12)[i]
        j["pelvis"].location.z = self.PZ - (0.0, 0.02, 0.03, 0.06, 0.05, 0.02)[i]
        self.spine_rot(lean, 0, (0.0, -0.1, -0.12, 0.1, 0.08, 0.0)[i])
        self.legs((-0.25, -0.08, 0), (0.25, 0.10, 0), 0.25, 0.30)
        sh = self.shoulder
        up = (0.0, 0.22, 0.26, -0.05, -0.12, 0.0)[i]
        fw = (-0.30, -0.24, -0.20, -0.44, -0.40, -0.32)[i]
        self.arm_ik("L", sh["L"] + Vector((0.06 - 0.06 * (i == 3), fw, -0.10 + up)), self.L_POLE)
        self.arm_ik("R", sh["R"] + Vector((-0.06 + 0.06 * (i == 3), fw, -0.10 + up)), self.R_POLE)
        j["neck"].rotation_euler = (-0.1 - 0.2 * (i >= 3), 0, 0.1)
        self.muzzle_ref = ("handR", (0, 0, -self.ll))


# ------------------------------------------------------------------------------- écorcheur
class Flayer(Human):
    def build_head(self, head) -> None:
        # crâne allongé, mâchoire saillante, sans peau
        self.skull(head, "skin", sx=0.160, sy=0.190, sz=0.175, jaw=0.05)
        self.eyes(head, "eye_glow", z=0.235, x=0.06, y=-0.165, r=(0.03, 0.012, 0.016), brow_key="sinew", angle=0.5)
        self.part("jaw", C.bm_xform(C.bm_box(0.15, 0.12, 0.07, bevel=0.025), loc=(0, -0.11, 0.08)), "sinew", head)
        for k in range(5):
            x = -0.05 + 0.025 * k
            self.part("tooth", C.bm_xform(C.bm_cyl(5, 0.010, 0.0, 0.04), loc=(x, -0.17, 0.11),
                      rot=(math.pi, 0, 0)), "bone", head, nofs=True)
        for sx in (1, -1):
            self.part("cheek", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.11 * sx, -0.12, 0.16),
                      scale=(0.04, 0.05, 0.05)), "bone", head)

    def dress(self) -> None:
        sp = self.j["spine"]
        tw, td = self.TW, self.TD
        # muscles et tendons apparents
        for sx in (1, -1):
            self.part("pec", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0.09 * sx * tw, -0.12 * td, 0.32),
                      scale=(0.10, 0.06, 0.07)), "skin", sp)
            for k in range(3):
                self.part("tendon", C.bm_tube(C.bezier((0.05 * sx, -0.14 * td, 0.24 - 0.07 * k),
                                                       (0.12 * sx, -0.15 * td, 0.23 - 0.07 * k),
                                                       (0.16 * sx * tw, -0.11 * td, 0.22 - 0.07 * k),
                                                       (0.19 * sx * tw, -0.04, 0.21 - 0.07 * k), 5),
                                              [0.012] * 5, seg=5), "sinew", sp)
        # colonne vertébrale saillante (épines)
        for k in range(6):
            self.part("spike", C.bm_xform(C.bm_cyl(6, 0.022, 0.0, 0.08), loc=(0, 0.14 * td, 0.06 + 0.07 * k),
                      rot=(-1.2, 0, 0)), "bone", sp)
        self.part("loin", C.bm_xform(C.bm_cyl(14, 0.21 * tw, 0.20 * tw, 0.10), loc=(0, 0, -0.03),
                  scale=(1, 0.78, 1)), "pants", self.j["pelvis"])
        # lames rouges aux avant-bras (le long de l'avant-bras puis au-delà de la main)
        for side, sx in (("L", 1), ("R", -1)):
            fa = self.j["fa" + side]
            pts = [(0.0, -0.03, -0.05), (0.02 * sx, -0.06, -self.ll - 0.06), (0.04 * sx, -0.10, -self.ll - 0.22),
                   (0.03 * sx, -0.18, -self.ll - 0.36)]
            self.part("blade" + side, C.bm_tube(pts, [0.05, 0.065, 0.05, 0.0], seg=8, flat=0.32, up=(1, 0, 0)),
                      "blade", fa, grp="blades")
            self.part("edge" + side, C.bm_tube([(x, y - 0.035, z) for (x, y, z) in pts[1:]], [0.030, 0.028, 0.0],
                      seg=6, flat=0.6, up=(1, 0, 0)), "blade_edge", fa, nofs=True, grp="blades")
        self.muzzle_ref = ("edgeR", (0.03 * -1, -0.20, -self.ll - 0.36))

    def arms_rest(self, b: float = 0.0) -> None:
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.14, -0.14, -0.30 + 0.02 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.14, -0.14, -0.30 + 0.02 * b)), self.R_POLE)

    def arms_run(self, s: float) -> None:
        sh = self.shoulder
        # bras tirés vers l'arrière, lames traînantes
        for side, sx, k in (("L", 1, -1), ("R", -1, 1)):
            self.arm_ik(side, sh[side] + Vector((0.12 * sx, 0.16 + 0.12 * s * k, -0.30)),
                        self.L_POLE if sx > 0 else self.R_POLE)

    def pose_attack(self, i: int, n: int) -> None:
        # accroupi (0-2) puis bond et double entaille (3), retombée (4-5)
        self.rest()
        j = self.j
        crouch = (0.06, 0.13, 0.15, 0.0, 0.04, 0.02)[i]
        rise = (0.0, 0.0, 0.0, 0.10, 0.02, 0.0)[i]
        fw = (0.0, 0.02, 0.03, -0.25, -0.18, -0.06)[i]
        j["pelvis"].location.z = self.PZ - crouch + rise
        j["pelvis"].location.y = fw
        lean = (0.15, 0.30, 0.34, 0.45, 0.50, 0.25)[i]
        self.spine_rot(lean - self.HUNCH * 0.3, 0, 0)
        self.legs((-0.5 * (i < 3) - 0.1, -0.1, 0), (0.3 * (i < 3) + 0.4 * (i >= 3), 0.1, 0),
                  0.4 + crouch * 4, 0.6 + crouch * 3)
        sh = self.shoulder
        if i < 3:
            hl, hr = Vector((0.22, 0.16, 0.06)), Vector((-0.22, 0.16, 0.06))
        elif i == 3:
            hl, hr = Vector((0.06, -0.36, -0.10)), Vector((-0.06, -0.36, -0.10))
        else:
            hl, hr = Vector((-0.04, -0.30, -0.26)), Vector((0.04, -0.30, -0.26))
        self.arm_ik("L", sh["L"] + hl, self.L_POLE)
        self.arm_ik("R", sh["R"] + hr, self.R_POLE)


# ------------------------------------------------------------------------------- robot de sécurité
class SecBot(Human):
    ARMOR = "armor"

    def build_head(self, head) -> None:
        A = self.ARMOR
        hb = C.bm_sphere(20, 14, 1.0)
        for v in hb.verts:
            x, y, z = v.co
            v.co = Vector((x * 0.19, y * 0.19, z * 0.18 + 0.20))
        self.part("helmet", hb, A, head)
        # visière : bandeau en V, émissive
        vis = C.bm_box(0.26, 0.05, 0.06, bevel=0.015)
        for v in vis.verts:
            v.co.y -= 0.12 * (v.co.x ** 2) * 6
        self.part("visorFrame", C.bm_xform(C.bm_box(0.30, 0.06, 0.10, bevel=0.02), loc=(0, -0.15, 0.20)),
                  "armor_dark", head)
        self.part("visor", C.bm_xform(vis, loc=(0, -0.185, 0.205)), "visor", head, nofs=True)
        self.part("jaw", C.bm_xform(C.bm_box(0.20, 0.10, 0.08, bevel=0.02), loc=(0, -0.10, 0.08)), "armor_dark", head)
        for sx in (1, -1):
            self.part("earCap", C.bm_xform(C.bm_cyl(12, 0.05, 0.05, 0.04), loc=(0.19 * sx, 0, 0.19),
                      rot=(0, math.pi / 2, 0)), "joint", head)
        self.part("crest", C.bm_xform(C.bm_box(0.04, 0.26, 0.05, bevel=0.012), loc=(0, 0.0, 0.38)), "armor_dark", head)

    def build_torso(self, pelvis, spine) -> None:
        A = self.ARMOR
        tw, td = self.TW, self.TD
        self.part("hips", C.bm_xform(C.bm_box(0.36 * tw, 0.26 * td, 0.16, bevel=0.04), loc=(0, 0, 0.0)),
                  "armor_dark", pelvis)
        self.part("abdomen", C.bm_xform(C.bm_cyl(12, 0.13 * tw, 0.15 * tw, 0.16), loc=(0, 0, 0.08)), "joint", spine)
        chest = C.bm_box(0.44 * tw, 0.30 * td, 0.28, bevel=0.06, segs=3)
        for v in chest.verts:
            if v.co.z < 0:
                v.co.x *= 0.80
            if v.co.y < 0:
                v.co.y -= 0.03 * (1 - abs(v.co.x) / (0.22 * tw))
        self.part("chest", C.bm_xform(chest, loc=(0, -0.01, 0.30)), A, spine)
        self.part("chestPlate", C.bm_xform(C.bm_box(0.22 * tw, 0.04, 0.14, bevel=0.02), loc=(0, -0.17 * td, 0.30)),
                  "armor_dark", spine)
        self.part("badge", C.bm_xform(C.bm_box(0.06, 0.02, 0.05, bevel=0.01), loc=(0.07 * tw, -0.19 * td, 0.34)),
                  "light_red", spine, nofs=True)
        self.part("collar", C.bm_xform(C.bm_cyl(14, 0.11, 0.10, 0.08), loc=(0, 0.0, 0.46)), "joint", spine)
        self.part("backpack", C.bm_xform(C.bm_box(0.30 * tw, 0.12, 0.24, bevel=0.03), loc=(0, 0.17 * td, 0.30)),
                  "armor_dark", spine)
        for sx in (1, -1):
            self.part("vent", C.bm_xform(C.bm_cyl(10, 0.035, 0.035, 0.10), loc=(0.08 * sx, 0.25 * td, 0.38),
                      rot=(math.pi / 2, 0, 0)), "joint", spine)

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
                      scale=(0.13 * aw, 0.13 * aw, 0.12 * aw)), self.ARMOR, ua)
            self.part("uarm" + side, C.bm_xform(C.bm_cyl(10, 0.06 * aw, 0.055 * aw, 0.20 * al),
                      loc=(0, 0, -0.10 * al)), "joint", ua)
            self.part("elbow" + side, C.bm_xform(C.bm_sphere(10, 8, 0.065 * aw), loc=(0, 0, 0)), "joint", fa)
            if side == "R":
                # canon intégré à l'avant-bras droit
                self.part("gunBody", C.bm_xform(C.bm_box(0.13 * aw, 0.13 * aw, 0.26 * al, bevel=0.025),
                          loc=(0, 0, -0.12 * al)), "gun", fa)
                for k, (dx, dy) in enumerate(((0.025, 0.025), (-0.025, 0.025), (0.025, -0.025), (-0.025, -0.025))):
                    self.part("barrel", C.bm_xform(C.bm_cyl(8, 0.018, 0.018, 0.14), loc=(dx, dy, -0.31 * al)),
                              "metal_dark", fa)
                self.part("gunLight", C.bm_xform(C.bm_box(0.02, 0.10, 0.03), loc=(0.068 * aw, 0, -0.10 * al)),
                          "light_red", fa, nofs=True)
                self.muzzle_ref = ("barrel", (0, 0, 0))
                self._muzzle_local = (0.0, 0.0, -0.39 * al)
            else:
                self.part("farm" + side, C.bm_xform(C.bm_cyl(10, 0.085 * aw, 0.075 * aw, 0.18 * al),
                          loc=(0, 0, -0.09 * al)), self.ARMOR, fa)
                self.part("hand" + side, C.bm_xform(C.bm_box(0.08 * aw, 0.07 * aw, 0.08 * aw, bevel=0.02),
                          loc=(0, 0, -self.ll + 0.01)), "joint", fa)

    def build_legs(self, pelvis) -> None:
        j, LEG = self.j, self.LEG
        bw = 1.0 + 0.25 * (self.TW - 1.0)
        for side, sx in (("L", 1), ("R", -1)):
            hip = j["hip" + side] = joint("hip" + side, pelvis, (0.12 * sx * bw, 0, -0.04))
            knee = j["knee" + side] = joint("knee" + side, hip, (0, 0, -0.36 * LEG))
            self.part("thigh" + side, C.bm_xform(C.bm_box(0.15 * bw, 0.16 * bw, 0.34 * LEG, bevel=0.03),
                      loc=(0, 0, -0.17 * LEG)), self.ARMOR, hip)
            self.part("kneeCap" + side, C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, -0.05, 0.0),
                      scale=(0.075, 0.06, 0.07)), "armor_dark", knee)
            self.part("shin" + side, C.bm_xform(C.bm_box(0.13 * bw, 0.15 * bw, 0.30 * LEG, bevel=0.03),
                      loc=(0, 0, -0.15 * LEG)), self.ARMOR, knee)
            fz = -0.345 + 0.41 * (1 - LEG)
            self.part("foot" + side, C.bm_xform(C.bm_box(0.15 * bw, 0.26 * bw, 0.09, bevel=0.03),
                      loc=(0, -0.05, fz + 0.03)), "armor_dark", knee)

    def dress(self) -> None:
        # bande blanche « SECURITY » sur le torse (lisible) et lumières dorsales
        sp = self.j["spine"]
        self.part("stripe", C.bm_xform(C.bm_box(0.42 * self.TW, 0.02, 0.03, bevel=0.005),
                  loc=(0, -0.172 * self.TD, 0.20)), "stripe", sp)
        for sx in (1, -1):
            self.part("backLight", C.bm_xform(C.bm_sphere(8, 6, 0.025), loc=(0.11 * sx * self.TW, 0.24 * self.TD, 0.42)),
                      "light_red", sp, nofs=True)

    def gun_aim(self, aim: float, recoil: float = 0.0) -> None:
        sh = self.shoulder
        low = sh["R"] + Vector((-0.06, -0.10, -0.36))
        up = sh["R"] + Vector((0.06, -0.42, -0.04))
        tgt = low.lerp(up, aim) + Vector((0, 0.07 * recoil, 0.04 * recoil))
        self.arm_ik("R", tgt, Vector((-0.9, 0.3, -0.3)))
        # main gauche : soutient le canon quand il vise
        lo = sh["L"] + Vector((0.06, -0.06, -0.38))
        sup = sh["R"] + Vector((0.10, -0.28, -0.16)) + Vector((0, 0.05 * recoil, 0))
        self.arm_ik("L", lo.lerp(sup, aim), self.L_POLE)

    def arms_rest(self, b: float = 0.0) -> None:
        self.gun_aim(0.15)

    def arms_run(self, s: float) -> None:
        self.gun_aim(0.25 + 0.05 * s)

    def pose_run(self, i: int, n: int) -> None:
        super().pose_run(i, n)
        self.j["pelvis"].location.z -= 0.02

    def pose_attack(self, i: int, n: int) -> None:
        self.rest()
        aim = (0.4, 0.9, 1.0, 1.0, 1.0, 0.85)[i]
        rc = (0, 0, 0, 1.0, 0.4, 0.0)[i]
        self.spine_rot(0.04 - 0.10 * rc, 0, 0.12)
        self.legs((0.05, -0.12, 0), (-0.10, 0.12, 0), 0.12, 0.18)
        self.gun_aim(aim, rc)

    def muzzle_world(self) -> Vector:
        fa = self.j["faR"]
        return fa.matrix_world @ Vector(self._muzzle_local)


# ------------------------------------------------------------------------------- clone
class Clone(Human):
    def build_head(self, head) -> None:
        # visage dans l'ombre de la capuche : seuls les yeux violets brillent
        self.skull(head, "skin")
        self.part("faceShadow", C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, -0.10, 0.19),
                  scale=(0.15, 0.08, 0.16)), "face", head)
        self.eyes(head, "eye_glow", z=0.215, x=0.055, y=-0.182, r=(0.028, 0.012, 0.016), brow=False)
        hood = C.bm_sphere(22, 14, 1.0)
        for v in hood.verts:
            x, y, z = v.co
            if y < 0:
                z += 0.12 * (-y)
            v.co = Vector((x * 0.225, y * 0.215 + 0.02, z * 0.235 + 0.215))
        for f in list(hood.faces):
            c = f.calc_center_median()
            if c.y < -0.08 and c.z < 0.36 and abs(c.x) < 0.17:
                hood.faces.remove(f)
        for v in list(hood.verts):
            if not v.link_faces:
                hood.verts.remove(v)
        self.part("hood", hood, "hoodie", head, thick=0.02)
        self.part("hoodRim", C.bm_xform(C.bm_torus(20, 6, 0.17, 0.022), loc=(0, -0.14, 0.24),
                  rot=(math.pi / 2 + 0.25, 0, 0), scale=(1.0, 1.15, 1)), "hoodie", head)

    def dress(self) -> None:
        sp = self.j["spine"]
        tw, td = self.TW, self.TD
        # veste ouverte sur un t-shirt rouge
        cs = []
        for z, r1, r2 in ((-0.02, 0.212, 0.160), (0.20, 0.232, 0.170), (0.36, 0.240, 0.165), (0.44, 0.19, 0.14)):
            cs.append(C.ellipse(0, 0.0, z, r1 * tw + 0.02, r2 * td + 0.02, 20))
        cbm = C.bm_loft(cs, cap_start=False, cap_end=False)
        for f in list(cbm.faces):
            c = f.calc_center_median()
            if c.y < -0.10 * td and abs(c.x) < 0.09 * tw:
                cbm.faces.remove(f)
        self.part("jacket", cbm, "jacket", sp, thick=0.016)
        for sx in (1, -1):
            self.part("zip", C.bm_xform(C.bm_box(0.012, 0.012, 0.42), loc=(0.085 * sx * tw, -0.19 * td, 0.20)),
                      "metal_dark", sp)
        # sac à dos (comme un pillard) et sangles
        self.part("pack", C.bm_xform(C.bm_box(0.30 * tw, 0.16, 0.32, bevel=0.05), loc=(0, 0.24 * td, 0.26)),
                  "pack", sp)
        self.part("packFlap", C.bm_xform(C.bm_box(0.28 * tw, 0.06, 0.12, bevel=0.03), loc=(0, 0.31 * td, 0.38)),
                  "pack", sp)
        for sx in (1, -1):
            self.part("packStrap", C.bm_tube(C.bezier((0.10 * sx, 0.15 * td, 0.44), (0.12 * sx, -0.10, 0.48),
                                                      (0.13 * sx, -0.19 * td, 0.32), (0.12 * sx, -0.17 * td, 0.12), 6),
                                             [0.02] * 6, seg=5, flat=0.4), "strap", sp)
        # couteau (main droite)
        fa = self.j["faR"]
        g = joint("w_knife", fa, (0, 0, -self.ll))
        blade = C.bm_box(0.012, 0.26, 0.05, bevel=0.004)
        for v in blade.verts:
            if v.co.y < -0.08:
                v.co.z *= max(0.1, 1.0 - (-v.co.y - 0.08) / 0.06)
        self.part("blade", C.bm_xform(blade, loc=(0, -0.17, 0.0)), "blade", g, grp="knife")
        self.part("handle", C.bm_xform(C.bm_cyl(8, 0.022, 0.024, 0.10), loc=(0, 0.0, 0), rot=(math.pi / 2, 0, 0)),
                  "strap", g, grp="knife")
        self.knife = g
        self.muzzle_ref = ("blade", (0, -0.30, 0))
        # traînée d'illusion (fumée violette) au bas de la veste, sans contour
        for k in range(5):
            a = -0.6 + 0.3 * k
            self.part("wisp", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.24 * math.sin(a) * tw, 0.10 + 0.08 * math.cos(a), -0.02),
                      scale=(0.04, 0.03, 0.02)), "smoke", sp, nofs=True)

    def set_knife(self, rot) -> None:
        self.knife.rotation_euler = rot

    def arms_rest(self, b: float = 0.0) -> None:
        # mains dans les poches de la veste, la droite tient le couteau bas
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((-0.02, -0.10, -0.40 + 0.01 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((0.0, -0.12, -0.38 + 0.01 * b)), self.R_POLE)
        self.set_knife((-1.2, 0, 0.2))

    def arms_run(self, s: float) -> None:
        super().arms_run(s)
        self.set_knife((-0.9, 0, 0.3))

    def pose_hit(self, i, n):
        super().pose_hit(i, n)
        self.set_knife((-0.6, 0, 0.3))

    def pose_death(self, i, n):
        super().pose_death(i, n)
        self.set_knife((0.6, 0, 0.8))

    def pose_attack(self, i: int, n: int) -> None:
        # surgit : élan accroupi, coup d'estoc, retour
        self.rest()
        j = self.j
        crouch = (0.04, 0.09, 0.11, 0.05, 0.03, 0.01)[i]
        j["pelvis"].location.z = self.PZ - crouch
        lean = (0.15, 0.32, 0.36, 0.55, 0.45, 0.2)[i]
        twist = (-0.2, -0.45, -0.5, 0.45, 0.6, 0.15)[i]
        self.spine_rot(lean, 0, twist)
        stride = (0.2, 0.35, 0.4, 0.9, 0.8, 0.4)[i]
        self.legs((-stride * 0.6, -0.08, 0), (stride * 0.5, 0.10, 0), 0.25 + crouch * 2, 0.5 + crouch * 2)
        sh = self.shoulder
        hand = [Vector((-0.03, 0.06, -0.20)), Vector((-0.10, 0.20, -0.18)), Vector((-0.11, 0.22, -0.16)),
                Vector((0.30, -0.44, -0.10)), Vector((0.44, -0.30, -0.22)), Vector((0.12, -0.26, -0.24))][i]
        self.arm_ik("R", sh["R"] + hand, self.R_POLE)
        self.set_knife([(-0.4, 0, 1.6), (-0.5, 0, 2.3), (-0.5, 0, 2.4), (1.4, 0, 0.0), (1.3, 0, -0.4), (0.2, 0, 0.2)][i])
        self.arm_ik("L", sh["L"] + [Vector((-0.04, -0.25, -0.12)), Vector((0.0, -0.32, -0.08)), Vector((0.0, -0.32, -0.07)),
                                    Vector((0.0, 0.05, -0.22)), Vector((-0.02, 0.10, -0.24)), Vector((-0.06, -0.18, -0.20))][i],
                    self.L_POLE)


# ------------------------------------------------------------------------------- gros brute
class Brute(Human):
    def build_head(self, head) -> None:
        # petite tête enfoncée dans les épaules, front bas, mâchoire énorme
        self.skull(head, "skin", sx=0.19, sy=0.18, sz=0.17, jaw=-0.25)
        self.eyes(head, "eye_glow", z=0.215, x=0.06, y=-0.165, r=(0.026, 0.012, 0.016), brow_key="skin", angle=0.45)
        self.part("browRidge", C.bm_xform(C.bm_box(0.24, 0.06, 0.05, bevel=0.02), loc=(0, -0.15, 0.26)), "skin", head)
        self.part("jaw", C.bm_xform(C.bm_box(0.26, 0.16, 0.10, bevel=0.04), loc=(0, -0.08, 0.06)), "skin", head)
        for sx in (1, -1):
            self.part("tusk", C.bm_xform(C.bm_cyl(6, 0.016, 0.0, 0.06), loc=(0.07 * sx, -0.16, 0.12)), "bone", head)
            self.part("lump", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.10 * sx, 0.04, 0.33),
                      scale=(0.06, 0.06, 0.04)), "skin", head)
        self.part("scar", C.bm_xform(C.bm_box(0.012, 0.01, 0.10), loc=(0.05, -0.17, 0.22), rot=(0, 0.4, 0)),
                  "wound", head, nofs=True)

    def build_torso(self, pelvis, spine) -> None:
        super().build_torso(pelvis, spine)
        tw, td = self.TW, self.TD
        # trapèzes énormes et pectoraux
        for sx in (1, -1):
            self.part("trap", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0.12 * sx * tw, 0.03, 0.43),
                      scale=(0.14 * tw, 0.12, 0.10)), "skin", spine)
            self.part("pec", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0.10 * sx * tw, -0.10 * td, 0.32),
                      scale=(0.12 * tw, 0.07 * td, 0.09)), "skin", spine)
            self.part("vein", C.bm_tube(C.bezier((0.04 * sx, -0.17 * td, 0.12), (0.10 * sx, -0.18 * td, 0.18),
                                                 (0.15 * sx * tw, -0.14 * td, 0.26), (0.20 * sx * tw, -0.10, 0.36), 6),
                                        [0.012] * 6, seg=5), "vein", spine)
        for k in range(2):
            for sx in (1, -1):
                self.part("abs", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.05 * sx, -0.19 * td, 0.10 + 0.08 * k),
                          scale=(0.045, 0.03, 0.035)), "skin", spine)

    def dress(self) -> None:
        pel = self.j["pelvis"]
        tw, td = self.TW, self.TD
        self.part("belt", C.bm_xform(C.bm_cyl(18, 0.23 * tw ** 0.8, 0.23 * tw ** 0.8, 0.06), loc=(0, 0, 0.06),
                  scale=(1, 0.76 * td / tw ** 0.8, 1)), "strap", pel)
        # chaîne en bandoulière
        sp = self.j["spine"]
        for k in range(14):
            a = 2 * math.pi * k / 14
            x, y = math.sin(a) * 0.24 * tw, -math.cos(a) * 0.18 * td
            z = 0.22 + 0.16 * math.sin(a)
            self.part("link", C.bm_xform(C.bm_torus(8, 4, 0.025, 0.008), loc=(x, y, z), rot=(0, 1.2, a)), "chain", sp)
        # bracelets de métal et poings de béton
        for side in ("L", "R"):
            fa = self.j["fa" + side]
            self.part("bracer" + side, C.bm_xform(C.bm_cyl(12, 0.085 * self.AW, 0.085 * self.AW, 0.09),
                      loc=(0, 0, -0.13 * self.AL)), "bracer", fa)
            self.part("fist" + side, C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, 0, -self.ll),
                      scale=(0.10 * self.AW, 0.09 * self.AW, 0.09 * self.AW)), "skin", fa)
        # épaulière de métal riveté (gauche) et sangle
        self.part("pad", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0.03, 0.0, 0.05), scale=(0.15, 0.14, 0.10)),
                  "metal", self.j["uaL"])
        for k in range(4):
            a = -0.9 + 0.6 * k
            self.part("rivet", C.bm_xform(C.bm_sphere(6, 4, 0.016), loc=(0.03 + 0.13 * math.sin(a), -0.12 * math.cos(a), 0.10)),
                      "chain", self.j["uaL"])
        self.muzzle_ref = ("fistR", (0, 0, -self.ll))

    def arms_rest(self, b: float = 0.0) -> None:
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.12, -0.10, -0.42 + 0.02 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.12, -0.10, -0.42 + 0.02 * b)), self.R_POLE)

    def arms_run(self, s: float) -> None:
        sh = self.shoulder
        for side, sx, k in (("L", 1, -1), ("R", -1, 1)):
            self.arm_ik(side, sh[side] + Vector((0.12 * sx, 0.18 * s * k - 0.08, -0.40)),
                        self.L_POLE if sx > 0 else self.R_POLE)

    def pose_run(self, i: int, n: int) -> None:
        self.S["stride"] = 0.6
        super().pose_run(i, n)
        self.j["pelvis"].location.z -= 0.03

    def pose_attack(self, i: int, n: int) -> None:
        # bras levés (0-2), frappe au sol à deux poings (3), relève (4-5)
        self.rest()
        j = self.j
        crouch = (0.02, 0.0, -0.02, 0.16, 0.14, 0.06)[i]
        j["pelvis"].location.z = self.PZ - crouch
        lean = (-0.05, -0.22, -0.28, 0.55, 0.50, 0.20)[i]
        self.spine_rot(lean - self.HUNCH * 0.5, 0, 0)
        self.legs((-0.3, -0.14, 0), (0.25, 0.14, 0), 0.3 + crouch * 2, 0.35 + crouch * 2)
        sh = self.shoulder
        if i < 3:
            up = (0.30, 0.52, 0.58)[i]
            hl, hr = Vector((-0.08, 0.06, up)), Vector((0.08, 0.06, up))
        elif i < 5:
            hl, hr = Vector((-0.12, -0.36, -0.30)), Vector((0.12, -0.36, -0.30))
        else:
            hl, hr = Vector((0.04, -0.24, -0.36)), Vector((-0.04, -0.24, -0.36))
        self.arm_ik("L", sh["L"] + hl, Vector((0.9, 0.2, 0.1)))
        self.arm_ik("R", sh["R"] + hr, Vector((-0.9, 0.2, 0.1)))


# ------------------------------------------------------------------------------- le Violent (élite)
class Violent(Brute):
    def build_head(self, head) -> None:
        self.skull(head, "skin", sx=0.17, sy=0.18, sz=0.18, jaw=-0.15)
        self.eyes(head, "eye_glow", z=0.22, x=0.06, y=-0.168, r=(0.03, 0.012, 0.018), brow_key="vein", angle=0.5)
        self.part("jaw", C.bm_xform(C.bm_box(0.22, 0.14, 0.09, bevel=0.035), loc=(0, -0.09, 0.07)), "skin", head)
        self.part("mouth", C.bm_xform(C.bm_box(0.15, 0.02, 0.04, bevel=0.01), loc=(0, -0.165, 0.10)), "vein", head,
                  nofs=True)
        for k in range(6):
            x = -0.06 + 0.024 * k
            self.part("tooth", C.bm_xform(C.bm_cyl(5, 0.010, 0.0, 0.035), loc=(x, -0.172, 0.13),
                      rot=(math.pi, 0, 0)), "claw", head, nofs=True)
        for sx in (1, -1):
            self.part("tattooHead", C.bm_xform(C.bm_box(0.012, 0.01, 0.12), loc=(0.11 * sx, -0.13, 0.30),
                      rot=(0.5, 0, 0.5 * sx)), "tattoo", head, nofs=True)

    def dress(self) -> None:
        pel = self.j["pelvis"]
        sp = self.j["spine"]
        tw, td = self.TW, self.TD
        self.part("belt", C.bm_xform(C.bm_cyl(18, 0.23 * tw ** 0.8, 0.23 * tw ** 0.8, 0.06), loc=(0, 0, 0.06),
                  scale=(1, 0.76 * td / tw ** 0.8, 1)), "strap", pel)
        # sangles croisées, plaque d'épaule, tatouages néon roses
        for sx in (1, -1):
            pts = []
            for k in range(9):
                a = -math.pi * 0.5 + math.pi * k / 8
                pts.append((sx * (0.22 * tw * math.sin(a)), -0.19 * td * math.cos(a) * 0.95, 0.24 + 0.17 * sx * math.sin(a)))
            self.part("strap", C.bm_tube(pts, [0.022] * 9, seg=5, flat=0.4), "strap", sp)
        self.part("pad", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0.02, 0.0, 0.06), scale=(0.14, 0.13, 0.09)),
                  "metal", self.j["uaL"])
        for k in range(4):
            self.part("tattoo", C.bm_xform(C.bm_box(0.10, 0.008, 0.012), loc=(-0.10 * tw, -0.178 * td, 0.12 + 0.06 * k),
                      rot=(0, 0.3 * (-1) ** k, 0)), "tattoo", sp, nofs=True)
        # griffes acérées (3 par main)
        for side, sx in (("L", 1), ("R", -1)):
            fa = self.j["fa" + side]
            self.part("fist" + side, C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, 0, -self.ll),
                      scale=(0.09 * self.AW, 0.08 * self.AW, 0.09 * self.AW)), "skin", fa)
            for k in range(3):
                x = (k - 1) * 0.04
                self.part("claw" + side, C.bm_tube([(x, -0.03, -self.ll - 0.04), (x * 1.3, -0.10, -self.ll - 0.18),
                                                    (x * 1.4, -0.24, -self.ll - 0.28)], [0.032, 0.022, 0.0], seg=6),
                          "claw", fa)
        self.muzzle_ref = ("clawR", (0, -0.24, -self.ll - 0.28))

    def pose_attack(self, i: int, n: int) -> None:
        # griffes acérées : bras armé en arrière (0-2), ruée et double griffure (3), suivi (4-5)
        self.rest()
        j = self.j
        crouch = (0.04, 0.10, 0.12, 0.02, 0.04, 0.02)[i]
        j["pelvis"].location.z = self.PZ - crouch
        j["pelvis"].location.y = (0.0, 0.02, 0.03, -0.18, -0.14, -0.04)[i]
        twist = (-0.25, -0.5, -0.55, 0.5, 0.6, 0.15)[i]
        self.spine_rot((0.15, 0.25, 0.28, 0.45, 0.45, 0.2)[i] - self.HUNCH * 0.4, 0, twist)
        self.legs((-0.45, -0.1, 0), (0.35, 0.1, 0), 0.35 + crouch * 3, 0.5 + crouch * 2)
        sh = self.shoulder
        hr = [Vector((-0.20, 0.14, 0.10)), Vector((-0.28, 0.24, 0.18)), Vector((-0.30, 0.26, 0.20)),
              Vector((0.22, -0.40, -0.08)), Vector((0.34, -0.26, -0.22)), Vector((0.0, -0.22, -0.30))][i]
        hl = [Vector((0.16, -0.20, -0.10)), Vector((0.18, -0.26, -0.04)), Vector((0.18, -0.28, -0.02)),
              Vector((0.10, 0.10, -0.20)), Vector((-0.12, -0.36, -0.06)), Vector((0.06, -0.18, -0.28))][i]
        self.arm_ik("R", sh["R"] + hr, self.R_POLE)
        self.arm_ik("L", sh["L"] + hl, self.L_POLE)


# ------------------------------------------------------------------------------- le Gardien de magasin (élite)
class Warden(SecBot):
    ARMOR = "armor"

    def build_head(self, head) -> None:
        # casque rouge et blanc, visière rouge, crête blanche
        hb = C.bm_sphere(20, 14, 1.0)
        for v in hb.verts:
            x, y, z = v.co
            v.co = Vector((x * 0.18, y * 0.19, z * 0.20 + 0.21))
        self.part("helmet", hb, "armor", head)
        self.part("helmetStripe", C.bm_xform(C.bm_box(0.07, 0.36, 0.06, bevel=0.02), loc=(0, 0.0, 0.39)), "white", head)
        self.part("face", C.bm_xform(C.bm_box(0.26, 0.08, 0.20, bevel=0.03), loc=(0, -0.14, 0.17)), "white", head)
        self.part("visor", C.bm_xform(C.bm_box(0.24, 0.03, 0.05, bevel=0.012), loc=(0, -0.185, 0.22)), "visor", head,
                  nofs=True)
        self.part("mouthGrill", C.bm_xform(C.bm_box(0.12, 0.03, 0.06, bevel=0.01), loc=(0, -0.182, 0.10)),
                  "armor_dark", head)
        for sx in (1, -1):
            self.part("earCap", C.bm_xform(C.bm_cyl(12, 0.05, 0.05, 0.04), loc=(0.18 * sx, 0, 0.20),
                      rot=(0, math.pi / 2, 0)), "joint", head)

    def dress(self) -> None:
        sp = self.j["spine"]
        tw, td = self.TW, self.TD
        self.part("chestWhite", C.bm_xform(C.bm_box(0.30 * tw, 0.04, 0.10, bevel=0.02), loc=(0, -0.175 * td, 0.38)),
                  "white", sp)
        self.part("logo", C.bm_xform(C.bm_box(0.16, 0.02, 0.04, bevel=0.008), loc=(0, -0.19 * td, 0.38)), "armor_dark",
                  sp)
        for sx in (1, -1):
            self.part("backLight", C.bm_xform(C.bm_sphere(8, 6, 0.025), loc=(0.11 * sx * tw, 0.24 * td, 0.42)),
                      "light_red", sp, nofs=True)
            self.part("shoulderStripe", C.bm_xform(C.bm_box(0.04, 0.20, 0.03), loc=(0.03 * sx, 0, 0.13)), "white",
                      self.j["ua" + ("L" if sx > 0 else "R")])

    def build_arms(self, spine) -> None:
        # bras robotiques ; fusil de précision tenu à deux mains (groupe w_rifle)
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
            self.part("elbow" + side, C.bm_xform(C.bm_sphere(10, 8, 0.065 * aw), loc=(0, 0, 0)), "joint", fa)
            self.part("farm" + side, C.bm_xform(C.bm_cyl(10, 0.085 * aw, 0.075 * aw, 0.18 * al),
                      loc=(0, 0, -0.09 * al)), "white", fa)
            self.part("hand" + side, C.bm_xform(C.bm_box(0.08 * aw, 0.07 * aw, 0.08 * aw, bevel=0.02),
                      loc=(0, 0, -self.ll + 0.01)), "joint", fa)
        g = self.rifle = joint("w_rifle", spine, (0, 0, 0))
        self.part("rBarrel", C.bm_xform(C.bm_cyl(10, 0.02, 0.02, 0.62), loc=(0, -0.42, 0.04), rot=(math.pi / 2, 0, 0)),
                  "metal_dark", g)
        self.part("rBody", C.bm_xform(C.bm_box(0.08, 0.36, 0.10, bevel=0.02), loc=(0, -0.08, 0.02)), "gun", g)
        self.part("rScope", C.bm_xform(C.bm_cyl(10, 0.03, 0.03, 0.18), loc=(0, -0.06, 0.10), rot=(math.pi / 2, 0, 0)),
                  "armor", g)
        self.part("rLight", C.bm_xform(C.bm_box(0.085, 0.10, 0.02), loc=(0, -0.20, -0.03)), "light_red", g, nofs=True)
        self.part("rStock", C.bm_xform(C.bm_box(0.06, 0.20, 0.10, bevel=0.02), loc=(0, 0.18, -0.01)), "armor", g)
        self._muzzle_local = (0.0, -0.74, 0.04)

    def gun_aim(self, aim: float, recoil: float = 0.0) -> None:
        rest_loc = Vector((-0.08, -0.22, 0.12))
        aim_loc = Vector((-0.08, -0.26, 0.38))
        loc = rest_loc.lerp(aim_loc, aim) + Vector((0, 0.07 * recoil, 0.03 * recoil))
        self.rifle.location = loc
        self.rifle.rotation_euler = (0.6 * (1 - aim) - 0.25 * recoil, 0.0, 0.5 * (1 - aim))
        mw = Matrix.Translation(loc) @ Euler(self.rifle.rotation_euler, "XYZ").to_matrix().to_4x4()
        grip = (mw @ Vector((0, 0.06, -0.05))).to_3d()
        fore = (mw @ Vector((0, -0.24, -0.03))).to_3d()
        self.arm_ik("R", grip, self.R_POLE)
        self.arm_ik("L", fore, self.L_POLE)

    def pose_death(self, i, n):
        super().pose_death(i, n)
        t = i / (n - 1)
        hr = self.j["faR"].location
        self.rifle.location = Vector(hr) + Vector((0.05, -0.1 * t, 0.0))
        self.rifle.rotation_euler = (0.3 + 1.0 * t, 0.0, 0.9 * t)

    def pose_hit(self, i, n):
        super().pose_hit(i, n)
        self.gun_aim(0.1)

    def muzzle_world(self) -> Vector:
        return self.rifle.matrix_world @ Vector(self._muzzle_local)


# =============================================================================== araignée
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
class Omnistore(Rig):
    """L'Omnistore : masse de chair à gueule dentée, écrans au dos, 6 pattes, néons.
    Modélisé à l'échelle 1 puis agrandi par `scale` (≈ 3 fois la hauteur du héros)."""

    BZ = 1.05
    L1, L2 = 0.95, 1.20

    def build(self) -> None:
        j = self.j
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["body"] = body = joint("body", root, (0, 0, 0))
        body.scale = (self.S["scale"],) * 3
        j["torso"] = to = joint("torso", body, (0, 0, self.BZ))
        j["head"] = hd = joint("head", to, (0, -0.46, 0.16))
        hd.scale = (1.3,) * 3
        j["jaw"] = jw = joint("jaw", hd, (0, 0.02, -0.06))
        j["tvs"] = tv = joint("tvs", to, (0, 0.22, 0.78))
        tv.scale = (1.35,) * 3
        # masse de chair : corps bossu
        bm = C.bm_sphere(26, 18, 1.0)
        rnd = random.Random(3)
        for v in bm.verts:
            x, y, z = v.co
            lump = 1.0 + 0.06 * math.sin(5 * x + 3 * y) * math.cos(4 * z) + 0.03 * rnd.random()
            v.co = Vector((x * 0.62 * lump, y * 0.70 * lump + 0.12, z * 0.52 * lump + 0.10 * (1 - y)))
        self.part("mass", bm, "flesh", to)
        for k in range(7):
            a = rnd.uniform(0, 2 * math.pi)
            p = Vector((0.52 * math.cos(a), 0.12 + 0.55 * math.sin(a), rnd.uniform(-0.05, 0.38)))
            self.part("bulb", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=p, scale=(0.16, 0.16, 0.13)), "flesh", to)
        # côtes / plaques osseuses sur le dos
        for k in range(5):
            self.part("ridge", C.bm_xform(C.bm_cyl(8, 0.05, 0.0, 0.22), loc=(0.25 * (-1) ** k, 0.05 + 0.12 * k, 0.48),
                      rot=(-0.5, 0.4 * (-1) ** k, 0)), "claw", to)
        # néons (tubes roses) enroulés sur la masse
        for k, (z, r, a0, a1) in enumerate(((0.05, 0.64, -2.2, 0.9), (0.28, 0.56, -0.6, 2.4))):
            pts = []
            for s in range(12):
                a = a0 + (a1 - a0) * s / 11
                pts.append((r * math.cos(a), 0.12 + r * 1.1 * math.sin(a), z + 0.06 * math.sin(3 * a)))
            self.part("neon%d" % k, C.bm_tube(pts, [0.025] * 12, seg=6), "neon", to, nofs=True)
        # tête / gueule : mâchoire supérieure + inférieure, dents, intérieur lumineux
        up = C.bm_sphere(20, 12, 1.0)
        for v in up.verts:
            x, y, z = v.co
            if z < 0:
                z *= 0.25
            v.co = Vector((x * 0.42, y * 0.34 - 0.05, z * 0.26 + 0.05))
        self.part("upper", up, "flesh", hd)
        self.part("maw", C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, -0.10, -0.06), scale=(0.34, 0.22, 0.16)),
                  "maw", hd, nofs=True)
        lo = C.bm_sphere(20, 12, 1.0)
        for v in lo.verts:
            x, y, z = v.co
            if z > 0:
                z *= 0.25
            v.co = Vector((x * 0.38, y * 0.32 - 0.10, z * 0.20 - 0.02))
        self.part("lower", lo, "flesh_dark", jw)
        self.part("gumU", C.bm_xform(C.bm_torus(24, 6, 0.30, 0.035), loc=(0, -0.12, 0.0), scale=(1.12, 0.95, 1)),
                  "gum", hd)
        for k in range(13):
            a = -2.6 + 2.0 * k / 12 - 0.2
            x, y = 0.33 * math.cos(a) * 1.1, -0.12 + 0.29 * math.sin(a)
            if y > -0.05:
                continue
            ln = 0.14 + 0.06 * (k % 2)
            self.part("toothU", C.bm_xform(C.bm_cyl(6, 0.028, 0.0, ln), loc=(x, y, -0.02 - ln / 2),
                      rot=(math.pi, 0, 0)), "tooth", hd)
            self.part("toothL", C.bm_xform(C.bm_cyl(6, 0.024, 0.0, ln * 0.8), loc=(x * 0.92, y + 0.02, 0.0 + ln * 0.4)),
                      "tooth", jw)
        # yeux multiples au-dessus de la gueule
        for (x, z, r) in ((0.14, 0.20, 0.05), (-0.14, 0.20, 0.05), (0.27, 0.13, 0.035), (-0.27, 0.13, 0.035),
                          (0.0, 0.26, 0.04)):
            self.part("eye", C.bm_xform(C.bm_sphere(10, 8, r), loc=(x, -0.30, z)), "eye_glow", hd, nofs=True)
        # écrans de télévision (3), câbles
        self.screens = []
        for k, (x, y, z, rz, rx, s, key) in enumerate(((0.0, 0.0, 0.18, 0.0, -0.25, 1.0, "screen"),
                                                       (0.42, 0.10, 0.02, -0.5, -0.2, 0.8, "screen3"),
                                                       (-0.40, 0.14, 0.06, 0.55, -0.15, 0.85, "screen2"))):
            g = joint("tv%d" % k, tv, (x, y, z))
            g.rotation_euler = (rx, 0, rz)
            self.part("tvBox%d" % k, C.bm_xform(C.bm_box(0.40 * s, 0.26 * s, 0.30 * s, bevel=0.03)), "frame_tv", g)
            self.part("tvScr%d" % k, C.bm_xform(C.bm_box(0.32 * s, 0.02, 0.22 * s, bevel=0.01), loc=(0, -0.135 * s, 0.0)),
                      key, g, nofs=True, grp="screens")
            # « bruit » et symbole d'étoile (motif sombre) sur l'écran
            self.part("tvStar%d" % k, C.bm_xform(C.bm_box(0.10 * s, 0.01, 0.10 * s), loc=(0, -0.15 * s, 0.0),
                      rot=(0, math.pi / 4, 0)), "frame_tv", g, nofs=True, grp="screens")
            self.part("tvDead%d" % k, C.bm_xform(C.bm_box(0.32 * s, 0.02, 0.22 * s, bevel=0.01), loc=(0, -0.134 * s, 0.0)),
                      "frame_tv", g, grp="dead_screens")
            self.part("cable%d" % k, C.bm_tube(C.bezier((0, 0.12 * s, -0.12 * s), (0, 0.25, -0.30),
                                                         (-x * 0.3, 0.1, -0.45), (-x * 0.5, 0.0, -0.55), 6),
                                                [0.03] * 6, seg=6), "cable", g)
            self.screens.append(g)
        # étiquette de prix accrochée (« SALE ») : petit carton blanc
        self.part("tag", C.bm_xform(C.bm_box(0.16, 0.01, 0.10, bevel=0.01), loc=(0.55, -0.20, -0.15), rot=(0.2, 0, 0.3)),
                  "tag", to)
        # pattes (6) : fémur et tibia, griffe
        self.legs_def = []
        for side, sx in (("L", 1), ("R", -1)):
            for k in range(3):
                ang = math.radians(-50 + 50 * k)
                hip = Vector((0.45 * sx, -0.20 + 0.32 * k, -0.05))
                rest = Vector((sx * (0.55 + 1.00 * math.cos(ang)), 0.15 + 1.1 * math.sin(ang), 0.0))
                name = "%s%d" % (side, k)
                u = qjoint("leg_u" + name, to, hip)
                lo2 = qjoint("leg_l" + name, to, (0, 0, 0))
                self.part("femur" + name, C.bm_tube([(0, 0, 0), (0, 0, -self.L1 * 0.5), (0, 0, -self.L1)],
                                                    [0.13, 0.11, 0.09], seg=10), "leg", u)
                self.part("spikeF" + name, C.bm_xform(C.bm_cyl(6, 0.035, 0.0, 0.14), loc=(0.06 * sx, 0, -self.L1 * 0.4),
                          rot=(0, 1.2 * sx, 0)), "claw", u)
                self.part("kneeJ" + name, C.bm_xform(C.bm_sphere(10, 8, 0.085)), "flesh_dark", lo2)
                self.part("tibia" + name, C.bm_tube([(0, 0, 0), (0, 0, -self.L2 * 0.6), (0, 0, -self.L2 * 0.88)],
                                                    [0.10, 0.075, 0.05], seg=10), "leg", lo2)
                self.part("claw" + name, C.bm_xform(C.bm_cyl(8, 0.045, 0.0, self.L2 * 0.14), loc=(0, 0, -self.L2 * 0.94),
                          rot=(math.pi, 0, 0)), "claw", lo2)
                self.legs_def.append({"name": name, "u": u, "l": lo2, "hip": hip, "rest": rest, "sx": sx, "k": k,
                                      "phase": 0.0 if (k + (0 if sx > 0 else 1)) % 2 == 0 else math.pi})
        # deux bras-faux avant (griffes) partant sous la gueule
        self.arms = []
        for sx in (1, -1):
            a = joint("scythe%d" % (sx > 0), to, (0.30 * sx, -0.42, -0.12))
            self.part("scy", C.bm_tube(C.bezier((0, 0, 0), (0.10 * sx, -0.25, 0.25), (0.15 * sx, -0.55, 0.10),
                                                (0.08 * sx, -0.70, -0.20), 8),
                                       [0.07, 0.065, 0.055, 0.045, 0.035, 0.025, 0.012, 0.0], seg=8), "leg", a)
            self.part("scyTip", C.bm_tube(C.bezier((0.08 * sx, -0.66, -0.12), (0.06 * sx, -0.75, -0.25),
                                                   (0.03 * sx, -0.72, -0.40), (0.0, -0.62, -0.48), 6),
                                          [0.035, 0.03, 0.025, 0.018, 0.01, 0.0], seg=6), "claw", a)
            self.arms.append((a, sx))
        self.muzzle_ref = ("maw", (0, -0.30, -0.06))

    def place_legs(self, feet: dict) -> None:
        bpy.context.view_layer.update()
        to = self.j["torso"]
        inv = to.matrix_basis.inverted()
        for L in self.legs_def:
            T = inv @ feet[L["name"]]
            S = L["hip"]
            pole = Vector((L["sx"] * 0.6, 0.0, 1.0))
            E, H = ik2(S, T, pole, self.L1, self.L2)
            L["u"].rotation_quaternion = DOWN.rotation_difference((E - S).normalized())
            L["l"].location = E
            L["l"].rotation_quaternion = DOWN.rotation_difference((H - E).normalized())

    def set_arms(self, raise_: float, swing: float = 0.0) -> None:
        for a, sx in self.arms:
            a.rotation_euler = (raise_, 0.0, -0.25 * sx + swing * sx)

    def rest(self) -> None:
        to = self.j["torso"]
        to.location = (0, 0, self.BZ)
        to.rotation_euler = (0, 0, 0)
        self.j["head"].rotation_euler = (0, 0, 0)
        self.j["jaw"].rotation_euler = (0.15, 0, 0)
        self.j["tvs"].rotation_euler = (0, 0, 0)
        self.j["body"].location = (0, 0, 0)
        self.j["body"].rotation_euler = (0, 0, 0)
        self.show("screens", True)
        self.show("dead_screens", False)
        self.set_arms(0.0)

    def feet_rest(self) -> dict:
        return {L["name"]: Vector(L["rest"]) for L in self.legs_def}

    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        t = 2 * math.pi * i / n
        to = self.j["torso"]
        to.location.z = self.BZ - 0.03 * (1 + math.sin(t))
        to.rotation_euler = (0.03 * math.sin(t), 0, 0.03 * math.sin(t + 1))
        self.j["jaw"].rotation_euler = (0.20 + 0.12 * max(0.0, math.sin(t)), 0, 0)
        self.j["tvs"].rotation_euler = (0.04 * math.sin(t + 0.8), 0, 0.05 * math.sin(t))
        self.set_arms(0.08 * math.sin(t), 0.05 * math.sin(t + 1))
        self.place_legs(self.feet_rest())

    def pose_run(self, i: int, n: int) -> None:
        self.rest()
        p = 2 * math.pi * i / n
        to = self.j["torso"]
        to.location.z = self.BZ - 0.05 + 0.04 * abs(math.sin(2 * p))
        to.rotation_euler = (0.08, 0.04 * math.sin(p), 0.05 * math.sin(p))
        self.j["jaw"].rotation_euler = (0.25, 0, 0)
        self.j["tvs"].rotation_euler = (0.06 * math.sin(2 * p), 0, 0)
        self.set_arms(0.15 + 0.1 * math.sin(p), 0.1 * math.sin(p))
        feet = {}
        for L in self.legs_def:
            u = p + L["phase"]
            feet[L["name"]] = Vector(L["rest"]) + Vector((0, 0.32 * math.cos(u), 0.28 * max(0.0, math.sin(u))))
        self.place_legs(feet)

    def pose_attack(self, i: int, n: int) -> None:
        # se cabre, gueule béante, faux levées (0-2) ; s'abat (3) ; retour (4-5)
        self.rest()
        to = self.j["torso"]
        rear = (0.15, 0.32, 0.38, -0.20, -0.12, 0.0)[i]
        to.rotation_euler = (-rear, 0, 0)
        to.location = (0, (0.04, 0.08, 0.10, -0.30, -0.22, -0.05)[i], self.BZ + 0.25 * max(0.0, rear) - 0.20 * max(0.0, -rear))
        self.j["jaw"].rotation_euler = ((0.4, 0.7, 0.85, 0.9, 0.5, 0.25)[i], 0, 0)
        self.set_arms((-0.6, -1.1, -1.25, 0.6, 0.4, 0.0)[i], (0.1, 0.2, 0.25, -0.1, -0.05, 0.0)[i])
        self.j["tvs"].rotation_euler = (0.1 * rear, 0, 0)
        feet = self.feet_rest()
        if i == 3 or i == 4:
            for L in self.legs_def:
                if L["k"] == 0:
                    feet[L["name"]] = Vector(L["rest"]) + Vector((-0.15 * L["sx"], -0.35, 0))
        self.place_legs(feet)

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        k = (1.0, 0.6, 0.25)[i]
        to = self.j["torso"]
        to.location = (0, 0.10 * k, self.BZ - 0.08 * k)
        to.rotation_euler = (0.15 * k, 0, 0.08 * k)
        self.j["jaw"].rotation_euler = (0.6 * k + 0.15, 0, 0)
        self.set_arms(0.4 * k)
        self.place_legs(self.feet_rest())

    def pose_death(self, i: int, n: int) -> None:
        # rugit, s'effondre, pattes repliées, écrans éteints
        self.rest()
        t = i / (n - 1)
        e = smooth((t - 0.15) / 0.65)
        to = self.j["torso"]
        to.location = (0, -0.1 * e, self.BZ * (1 - 0.62 * e) + 0.12 * math.sin(min(1.0, t * 3) * math.pi) * (1 - e))
        to.rotation_euler = (0.25 * e - 0.2 * (1 - e) * (t < 0.2), 0.25 * e, 0.1 * e)
        self.j["jaw"].rotation_euler = (0.9 - 0.5 * e, 0, 0)
        self.j["tvs"].rotation_euler = (0.5 * e, 0.3 * e, 0)
        self.set_arms(0.9 * e - 0.6 * (1 - e), 0.3 * e)
        if t > 0.6:
            self.show("screens", False)
            self.show("dead_screens", True)
        feet = {}
        for L in self.legs_def:
            r = Vector(L["rest"])
            out = Vector((r.x * 1.12, r.y * 1.12, 0.0))
            feet[L["name"]] = r.lerp(out, e)
        self.place_legs(feet)


CLASSES = {
    "mall_zombie": Zombie, "mall_flayer": Flayer, "mall_security_bot": SecBot, "mall_clone": Clone,
    "mall_brute": Brute, "mall_night_spider": Spider, "mall_violent": Violent, "mall_store_warden": Warden,
    "mall_omnistore": Omnistore,
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
        sheet = Image.new("RGBA", (F * len(tiles), F), (52, 40, 70, 255))
        for k, t in enumerate(tiles):
            sheet.alpha_composite(t, (k * F, 0))
        out = os.path.join(TMP_DIR, "prev_%s.png" % kind)
        sheet.save(out)
        print("PREVIEW", out)


def presentation_sheet(kinds) -> None:
    """Planche de présentation (captures de PR) : idle 3/4 face + attaque + cadavre, à l'échelle du jeu,
    sur fond nuit violet, depuis les images déjà rendues (TMP_DIR)."""
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
    sheet = Image.new("RGBA", (W, H), (20, 14, 34, 255))
    dr = ImageDraw.Draw(sheet)
    for y in range(H):
        c = int(14 + 18 * y / H)
        dr.line([(0, y), (W, y)], fill=(c + 6, c, c + 22, 255))
    dr.text((24, 20), "CENTRE COMMERCIAL ABANDONNÉ — Les égarés de la nuit", font=title_f, fill=(236, 120, 255, 255))
    tags = {"mall_violent": "ÉLITE", "mall_store_warden": "ÉLITE", "mall_omnistore": "BOSS"}
    for idx, kind in enumerate(kinds):
        cx = 20 + (idx % cols) * cell_w
        cy = 80 + (idx // cols) * cell_h
        dr.rounded_rectangle([cx, cy, cx + cell_w - 12, cy + cell_h - 12], 14, fill=(18, 26, 46, 235),
                             outline=(176, 110, 230, 255), width=2)
        tmp = os.path.join(TMP_DIR, kind)
        F = out_frame(kind)
        n_death = anims_for(kind)["death"][0]
        shots = [("idle_se_0", "idle"), ("attack_sw_3", "attaque"), ("death_s_%d" % (n_death - 1), "cadavre")]
        if F > 256:
            shots = shots[:2]
        w = (cell_w - 32) // len(shots)
        # échelle commune : 1 px de rendu = 1 px affiché ; le boss est réduit pour tenir dans la case
        k = min(1.0, (cell_h - 70) / F, 1.1 * w / F if F > 256 else 9.0)
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
            col = (255, 160, 60, 255) if tags[kind] == "BOSS" else (200, 120, 255, 255)
            dr.text((cx + cell_w - 90, cy + 10), tags[kind], font=name_f, fill=col)
        dr.text((cx + 14, cy + 30), kind, font=sub_f, fill=(150, 150, 175, 255))
    os.makedirs(CAPT_DIR, exist_ok=True)
    out = os.path.join(CAPT_DIR, "planche_modeles_mall.png")
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
