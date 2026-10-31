"""Bestiaire des Pyramides d'Égypte (« Le royaume des morts ») : modélisation 3D scriptée, rigs,
animations, rendus 8 directions, planches compactes (atlas rogné) + SpriteFrames + méta JSON.

Même pipeline que les hors-la-loi (art/blender/build_enemies.py), le héros et les bestiaires déjà
faits (centre commercial) : caméra orthographique 3/4 à 48°, matériaux toon peints, contour
Freestyle, même densité de pixels et même échelle monde (WORLD_PER_PX). Les grands gabarits (momie,
élites, boss) ont un cadre plus grand à la même densité de pixels.

Ambiance de la planche : soleil du désert (lumière chaude rasante du projet), os, bandelettes, or et
bronze, sable ocre ; accents émissifs (yeux, disques solaires) lisibles sur mobile.

Usage (depuis la racine du projet ; rendus : passer par le verrou flock du projet) :
    source tools/prerender/mac_env.sh   # macOS : python3 = Blender, verrous BLENDER_LOCK / GODOT_LOCK
    flock "$BLENDER_LOCK" python3 art/blender/bestiary/egypt/build_eg_bestiary.py
    ... --kinds eg_skeleton,eg_scarab
    ... --preview s,se --anim idle:0,attack:3 --kinds eg_skeleton     # aperçu rapide (RDM_TMP)
    ... --preview s,se --elev 12 --kinds eg_skeleton                  # aperçu de face (comparaison planche)
    ... --repack --kinds eg_skeleton                                    # atlas + méta depuis les images
    ... --sheet                                                         # planche de présentation

Bestiaire (ids) :
    eg_skeleton        Squelette rôdeur : squelette au khopesh, pagne en lambeaux, yeux ambrés
    eg_scarab          Scarabée géant : carapace bleu nuit cerclée d'or, mandibules, 6 pattes
    eg_lizard          Lézard des sables : lézard ocre à crête rouge, long corps souple
    eg_archer          Archer sable : squelette archer, coiffe rayée, arc et carquois
    eg_mummy           Momie étouffée : momie massive en bandelettes, yeux brûlants
    eg_viper           Vipère des sables : cobra géant dressé, capuchon ocellé
    eg_shadow_warrior  Guerrier de l'ombre (élite) : guerrier à tête de chacal, khopesh, or
    eg_sun_priest      Prêtre du soleil (élite) : prêtre momifié, bâton au disque solaire
    eg_pharaoh         Le Pharaon éternel (boss) : pharaon momifié géant, némès, sceptre

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
import bmesh  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "enemies")
CAPT_DIR = os.path.join(ROOT, "docs", "bestiaire", "captures", "egypt")
TMP_DIR = os.environ.get("RDM_TMP", "/tmp/rdm_eg_bestiary")

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

# Soleil du désert : lumière chaude du projet (C.WARM inchangé).

# ----------------------------------------------------------------------------- matériaux
COMMON_MATS = {
    "eye": ("#140c10", None, None),
    "socket": ("#1a0e0c", "#0a0406", "#2a1814"),
    "bone": ("pat", [("#e6d6b0", "#6a5470", "#fff4d4"), ("#cdb88a", "#5a4660", "#ecdcb2")], 6.0),
    "tooth": ("#efe4c4", "#7a6e80", "#ffffff"),
    "gold": ("pat", [("#e2b040", "#6a3a1c", "#ffe48a"), ("#c8922c", "#5a3018", "#f2c860")], 7.0),
    "bronze": ("#b07a32", "#3e2418", "#e8b462"),
    "lapis": ("#2448a0", "#0c1440", "#4a7ad8"),
    "strap": ("#5a3a24", "#1a0e0c", "#8a603c"),
    "linen": ("pat", [("#cdb88c", "#5e4652", "#efdcb0"), ("#a89068", "#4a3444", "#cab088")], 5.0),
    "wrap": ("pat", [("#d8c8a2", "#6a5660", "#f6e8c4"), ("#b8a27c", "#54424e", "#d8c49c"),
                     ("#9c8462", "#463440", "#bca480")], 4.0),
    "wrap_dark": ("#8a7254", "#3a2834", "#ae9670"),
    "wood": ("#6a4022", "#24120e", "#9a6438"),
    "red": ("#b02a26", "#40081a", "#e05040"),
}

SPEC: dict[str, dict] = {
    "eg_skeleton": {
        "name": "Squelette rôdeur", "rig": "human", "frame": 192, "scale": 0.92, "head": 0.90, "leg": 1.0,
        "torso": (1.16, 0.92), "arm": 0.62, "arm_len": 1.30, "hunch": 0.34, "fps_run": 13,
        "mats": {"eye_glow": "!#ffb030", "pants": "linen", "shoe": "bone",
                 "bone": ("pat", [("#e2b878", "#5a3424", "#fadca0"), ("#c8965a", "#4a2a1e", "#ecc080"),
                                  ("#a87442", "#3e2018", "#cc9c62")], 5.0),
                 "rag": ("pat", [("#5e3e28", "#1e1010", "#86603e"), ("#4a301e", "#160a0a", "#6e4c30")], 4.0)},
    },
    "eg_scarab": {
        "name": "Scarabée géant", "rig": "scarab", "frame": 192, "scale": 1.18, "fps_run": 16,
        "body_z": 0.28, "femur": 0.25, "tibia": 0.30, "spread": 0.46,
        # carapace bleu-vert nuit très sombre, liserés d'or, gueule béante rougeoyante (planche)
        "mats": {
            "shell": ("pat", [("#0a1e30", "#020408", "#1e4e6c"), ("#081828", "#020306", "#184460"),
                              ("#0a2628", "#02080a", "#1c5a5a")], 5.0),
            "shell_dark": ("#121820", "#040508", "#2c3846"),
            "leg": ("#1e1c24", "#060508", "#3e3a48"),
            "mouth": "!#ff6a20",
            "eye_glow": "!#ffcc40",
            "mandible": ("#3e2c22", "#120a08", "#6a4a36"),
        },
    },
    "eg_lizard": {
        "name": "Lézard des sables", "rig": "lizard", "frame": 192, "scale": 1.20, "fps_run": 18,
        # lézard massif ocre aux écailles brunes, couronne d'épines, taches rouge brique, gueule rouge
        "mats": {
            "scales": ("pat", [("#c48a44", "#4a2414", "#ecb466"), ("#9a6230", "#381a0e", "#c48848"),
                               ("#d8a052", "#5a2c16", "#f6ca78")], 7.0),
            "mark": ("pat", [("#8a4a22", "#2c1006", "#b4683a"), ("#74401c", "#240c04", "#9a5a30")], 6.0),
            "belly": ("#e2bc84", "#6e4a36", "#f8e0aa"),
            "frill": ("#d8b47a", "#5a3a28", "#f6dca4"),
            "spike": ("#ead6a8", "#6a5040", "#fff4d6"),
            "eye_glow": "!#ffd030",
            "mouth": ("#a8202a", "#3a0610", "#d84040"),
        },
    },
    "eg_archer": {
        "name": "Archer sable", "rig": "human", "frame": 192, "scale": 0.92, "head": 0.90, "leg": 1.0,
        "torso": (1.12, 0.90), "arm": 0.62, "arm_len": 1.26, "hunch": 0.14, "fps_run": 12,
        "mats": {"eye_glow": "!#ffb030", "pants": "linen", "shoe": "bone", "string": ("#efe4c8", "#7a6e70", "#ffffff"),
                 "bone": ("pat", [("#e2b878", "#5a3424", "#fadca0"), ("#c8965a", "#4a2a1e", "#ecc080"),
                                  ("#a87442", "#3e2018", "#cc9c62")], 5.0),
                 "rag": ("pat", [("#5e3e28", "#1e1010", "#86603e"), ("#4a301e", "#160a0a", "#6e4c30")], 4.0),
                 "fletch": ("#c4342a", "#4a0c1a", "#ff6c4c")},
    },
    "eg_mummy": {
        "name": "Momie étouffée", "rig": "human", "frame": 224, "scale": 1.12, "head": 0.86, "leg": 0.92,
        "torso": (1.30, 1.10), "arm": 1.02, "arm_len": 1.30, "hunch": 0.50, "fps_run": 9,
        "top_key": "wrap", "pants_key": "wrap", "sleeve_key": "wrap", "hand_key": "wrap",
        # lin souillé brun-gris (planche), bandes sombres, visage décharné visible
        "mats": {"eye_glow": "!#ffa020", "shoe": "wrap_dark",
                 "wrap": ("pat", [("#b49272", "#3e2a26", "#d8b88e"), ("#927054", "#33221e", "#b4906c"),
                                  ("#72563f", "#281a16", "#927258")], 4.0),
                 "wrap_dark": ("#54443a", "#1c1414", "#76604e"),
                 "flesh": ("#6a4e3a", "#22140e", "#8e6c50")},
    },
    "eg_viper": {
        "name": "Vipère des sables", "rig": "viper", "frame": 192, "scale": 1.30, "fps_run": 14,
        # brun-ocre à larges bandes sombres, ventre crème, gueule rougeoyante (planche)
        "mats": {
            "scales": ("pat", [("#a8743c", "#3a1e10", "#d49c58"), ("#8a5a2c", "#2e160c", "#b47c42"),
                               ("#b8844a", "#42220e", "#e2ac68")], 7.0),
            "band": ("pat", [("#3e2616", "#120806", "#62402a"), ("#30200f", "#0e0604", "#523420")], 6.0),
            "belly": ("#e2c08a", "#6e4c38", "#fae4b0"),
            "hood_mark": ("#2e1c10", "#100604", "#4e3220"),
            "eye_glow": "!#ffb020",
            "mouth": "!#ff5a24",
            "tongue": ("#c02838", "#4a0814", "#f05060"),
        },
    },
    "eg_shadow_warrior": {
        "name": "Guerrier de l'ombre", "rig": "human", "frame": 224, "scale": 1.20, "head": 0.94, "leg": 0.94,
        "torso": (1.34, 1.08), "arm": 1.22, "arm_len": 1.18, "hunch": 0.12, "fps_run": 15,
        "top_key": "fur", "pants_key": "fur", "sleeve_key": "fur", "hand_key": "fur",
        # chacal noir bleuté, armure d'écailles acier bleu, yeux bleu pâle, masse-sceptre (planche)
        "mats": {
            "fur": ("pat", [("#20223a", "#06060e", "#4a5078"), ("#181a2c", "#04040a", "#3a4062")], 5.0),
            "eye_glow": "!#a8e4ff",
            "shoe": "strap",
            "kilt": ("pat", [("#262c48", "#080a16", "#46507a"), ("#1e2238", "#06080e", "#3a4266")], 4.0),
            "steel": ("pat", [("#4a5a7a", "#141a2a", "#8aa0c4"), ("#3a4864", "#10141e", "#6e86ac")], 9.0),
        },
    },
    "eg_sun_priest": {
        "name": "Prêtre du soleil", "rig": "human", "frame": 224, "scale": 1.12, "head": 0.92, "leg": 0.94,
        "torso": (1.18, 1.02), "arm": 1.02, "arm_len": 1.15, "hunch": 0.10, "fps_run": 11, "stride": 0.45,
        "top_key": "robe", "pants_key": "robe", "sleeve_key": "robe", "hand_key": "wrap_dark", "shoulder_key": "mantle",
        # prêtre momifié encapuchonné : robe brun-ocre brodée d'or, visage décharné, bâton au soleil enflammé
        "mats": {
            "robe": ("pat", [("#8a5a2e", "#2c160c", "#b67e44"), ("#a06a36", "#341c10", "#cc9450"),
                             ("#74481f", "#24120a", "#9c6a38")], 5.0),
            "mantle": ("pat", [("#c08a3a", "#4a2810", "#eab860"), ("#a87430", "#3e200c", "#d4a050")], 8.0),
            "wrap": ("pat", [("#9a7a5a", "#30201c", "#c09c74"), ("#7a5e44", "#281a16", "#9e7e5e")], 4.0),
            "wrap_dark": ("#5e4634", "#1e1410", "#806048"),
            "flesh": ("#8a6644", "#2e1a10", "#b08a60"),
            "eye_glow": "!#ffd040",
            "shoe": "gold",
            "sun": "!#ff8a20",
            "sun_core": "!#fff2a0",
        },
    },
    "eg_pharaoh": {
        "name": "Le Pharaon éternel", "rig": "human", "frame": 448, "scale": 2.40, "head": 0.96, "leg": 0.94,
        "torso": (1.50, 1.15), "arm": 1.34, "arm_len": 1.12, "hunch": 0.04, "fps_run": 10, "cam_dz": 0.0,
        "out_scale": 0.62, "anims": {"idle": (4, 6, True), "run": (6, 10, True), "death": (6, 9, False)},
        "top_key": "armor", "pants_key": "wrap_dark", "sleeve_key": "armor", "hand_key": "gold", "shoulder_key": "gold",
        # colosse cuirassé d'or, némès rayé or et noir, masque d'or, deux sceptres ouvragés (planche)
        "mats": {
            "eye_glow": "!#fff0a0",
            "shoe": "gold",
            "armor": ("pat", [("#d2a038", "#4a2a10", "#ffdc80"), ("#b08028", "#3e220c", "#e8b85a"),
                              ("#946a22", "#321a0a", "#c8983c")], 6.0),
            "nemes_dark": ("#1e1a22", "#08060a", "#3e3644"),
            "wrap_dark": ("#3a2c22", "#120c0a", "#5a4634"),
            "cape": ("pat", [("#2a1a14", "#0a0606", "#4e3426"), ("#22140e", "#080404", "#42281c")], 4.0),
            "halo": "!#ffc04a",
            "sun": "!#ffaa30",
            "sun_core": "!#fff2a0",
            "curse": "!#5affc8",
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
        self.parts2: list[tuple[bpy.types.Object, str]] = []   # 2e emplacement de matériau (bandes, taches)
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
        for ob, key in self.parts2:
            ob.data.materials.append(mats.get(key, fallback))

    def second_mat(self, ob, key: str) -> None:
        """Ajoute un 2e matériau à un objet (faces choisies par material_index)."""
        self.parts2.append((ob, key))

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

# =============================================================================== outils Égypte
def remesh(ob, bm, mat_fn=None) -> None:
    """Remplace la géométrie d'un objet (corps souples refaits à chaque pose : lézard, vipère).
    mat_fn(indice de face) -> indice de matériau (bandes, taches) ; None = un seul matériau."""
    if mat_fn is not None:
        bm.faces.ensure_lookup_table()
        for f in bm.faces:
            f.material_index = mat_fn(f.index)
    bm.to_mesh(ob.data)
    bm.free()
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.data.update()


def ring(rx: float, ry: float, tube: float, seg: int = 24):
    """Anneau (bandelette, bracelet, côte) d'axe Z, rayons rx / ry, section `tube`."""
    bm = C.bm_torus(seg, 6, 1.0, tube / max(rx, 1e-4))
    return C.bm_xform(bm, scale=(rx, ry, max(rx, 1e-4)))


def khopesh(rig, parent, name: str, k: float = 1.0, key: str = "bronze", edge: str = "gold") -> None:
    """Khopesh (épée-faucille) le long de -Y local : poignée, lame droite puis crochet."""
    rig.part(name + "Grip", C.bm_xform(C.bm_cyl(8, 0.020 * k, 0.022 * k, 0.12 * k), loc=(0, -0.0, 0),
             rot=(math.pi / 2, 0, 0)), "strap", parent)
    rig.part(name + "Pommel", C.bm_xform(C.bm_sphere(8, 6, 0.026 * k), loc=(0, 0.065 * k, 0)), edge, parent)
    rig.part(name + "Guard", C.bm_xform(C.bm_box(0.05 * k, 0.025 * k, 0.07 * k, bevel=0.008), loc=(0, -0.07 * k, 0)),
             edge, parent)
    path = [(0, -0.07 * k, 0), (0, -0.20 * k, 0.0), (0, -0.30 * k, 0.035 * k), (0, -0.39 * k, 0.01 * k),
            (0, -0.42 * k, -0.07 * k), (0, -0.37 * k, -0.13 * k)]
    rig.part(name, C.bm_tube(path, [0.026 * k, 0.036 * k, 0.050 * k, 0.055 * k, 0.044 * k, 0.0], seg=10,
                             flat=0.3, up=(1, 0, 0)), key, parent)
    rig.muzzle_ref = (name, (0, -0.42 * k, -0.06 * k))


def mace_staff(rig, parent, name: str, k: float = 1.0) -> None:
    """Masse-sceptre d'ombre le long de -Y local : longue hampe sombre, tête ajourée à pointes."""
    rig.part(name + "Pole", C.bm_xform(C.bm_cyl(8, 0.022 * k, 0.026 * k, 0.95 * k), loc=(0, -0.20 * k, 0),
             rot=(math.pi / 2, 0, 0)), "fur", parent)
    for y in (0.24, -0.10, -0.62):
        rig.part(name + "Ring", C.bm_xform(ring(0.030 * k, 0.030 * k, 0.010 * k), loc=(0, y * k, 0), rot=(math.pi / 2, 0, 0)),
                 "gold", parent)
    rig.part(name + "Head", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, -0.74 * k, 0), scale=(0.07 * k, 0.10 * k, 0.07 * k)),
             "steel", parent)
    for a in range(6):
        ang = 2 * math.pi * a / 6
        d = Vector((math.cos(ang), 0, math.sin(ang)))
        rig.part(name + "Spike", C.bm_xform(C.bm_cyl(5, 0.022 * k, 0.0, 0.09 * k), loc=tuple(Vector((0, -0.74 * k, 0)) + d * 0.08 * k),
                 rot=(0, math.atan2(d.x, d.z), 0)), "gold", parent)
    rig.part(name + "Tip", C.bm_xform(C.bm_cyl(6, 0.02 * k, 0.0, 0.10 * k), loc=(0, -0.88 * k, 0), rot=(math.pi / 2, 0, 0)),
             "gold", parent)
    rig.muzzle_ref = (name + "Head", (0, -0.74 * k, 0))


def staff_dir(rot) -> Vector:
    return Euler(rot).to_matrix() @ Vector((0, 0, 1))


# =============================================================================== humanoïdes d'Égypte
class EgHuman(Human):
    """Humanoïde + armes tenues : une arme est un joint enfant de la colonne, placé à la main
    (résultat de l'IK) à chaque pose, avec une rotation exprimée dans le repère de la colonne."""

    def build(self) -> None:
        self.hand = {"L": Vector((0, 0, 0)), "R": Vector((0, 0, 0))}
        self.weap: dict[str, list] = {}
        super().build()

    def arm_ik(self, side: str, target: Vector, pole: Vector) -> None:
        S = self.j["ua" + side].location.copy()
        E, H = ik2(S, Vector(target), Vector(pole), self.lu, self.ll)
        ua, fa = self.j["ua" + side], self.j["fa" + side]
        ua.rotation_quaternion = DOWN.rotation_difference((E - S).normalized())
        fa.location = E
        fa.rotation_quaternion = DOWN.rotation_difference((H - E).normalized())
        self.hand[side] = H

    def weapon(self, name: str, side: str | None, rot=(0, 0, 0)):
        j = joint("w_" + name, self.j["spine"], (0, 0, 0))
        self.weap[name] = [j, side, rot, Vector((0, 0, 0))]
        return j

    def wrot(self, name: str, rot, off=(0, 0, 0)) -> None:
        self.weap[name][2] = rot
        self.weap[name][3] = Vector(off)

    def pose(self, anim: str, i: int, n: int) -> None:
        super().pose(anim, i, n)
        for name, (j, side, rot, off) in self.weap.items():
            if side:
                j.location = self.hand[side] + off
            j.rotation_euler = rot

    def wraps(self, parent, pts, key="wrap_dark", tube=0.012) -> None:
        """Bandelettes : anneaux inclinés (x, y, z, rx, ry, inclinaison)."""
        for k, (x, y, z, rx, ry, tilt) in enumerate(pts):
            self.part("wrapRing", C.bm_xform(ring(rx, ry, tube), loc=(x, y, z), rot=(tilt, 0.25 * tilt, 0)), key, parent)

    def limb_wraps(self, key="wrap_dark") -> None:
        aw, al, LEG = self.AW, self.AL, self.LEG
        for side, sx in (("L", 1), ("R", -1)):
            for k, z in enumerate((-0.06, -0.14)):
                self.part("uaw", C.bm_xform(ring(0.095 * aw, 0.09 * aw, 0.010), loc=(0, 0, z * al),
                          rot=(0.3 * (1 if k else -1), 0, 0)), key, self.j["ua" + side])
            for k, z in enumerate((-0.05, -0.12)):
                self.part("faw", C.bm_xform(ring(0.08 * aw, 0.075 * aw, 0.009), loc=(0, 0, z * al),
                          rot=(0.35 * (1 if k else -1), 0, 0)), key, self.j["fa" + side])
            for k, z in enumerate((-0.10, -0.24)):
                self.part("thw", C.bm_xform(ring(0.12, 0.115, 0.011), loc=(0, 0, z * LEG),
                          rot=(0.3 * (1 if k else -1), 0, 0)), key, self.j["hip" + side])
            for k, z in enumerate((-0.08, -0.20)):
                self.part("shw", C.bm_xform(ring(0.098, 0.094, 0.010), loc=(0, 0, z * LEG),
                          rot=(0.3 * (1 if k else -1), 0, 0)), key, self.j["knee" + side])


# ------------------------------------------------------------------------------- squelette rôdeur
class Skeleton(EgHuman):
    """Squelette : os épais (lisibles sur mobile), cage thoracique sur fond sombre, khopesh."""

    def build_legs(self, pelvis) -> None:
        j, LEG = self.j, self.LEG
        fz = -0.345 + 0.41 * (1 - LEG)
        for side, sx in (("L", 1), ("R", -1)):
            hip = j["hip" + side] = joint("hip" + side, pelvis, (0.10 * sx, 0, -0.03))
            knee = j["knee" + side] = joint("knee" + side, hip, (0, 0, -0.36 * LEG))
            self.part("femur" + side, C.bm_tube([(0, 0, 0.0), (0, 0, -0.18 * LEG), (0, 0, -0.35 * LEG)],
                                                [0.066, 0.050, 0.062], seg=8), "bone", hip)
            self.part("fhead" + side, C.bm_sphere(10, 6, 0.070), "bone", hip)
            self.part("kneecap" + side, C.bm_xform(C.bm_sphere(10, 6, 0.066), loc=(0, -0.016, 0)), "bone", knee)
            self.part("tibia" + side, C.bm_tube([(0, 0, 0), (0, 0, fz * 0.5), (0, 0, fz + 0.05)], [0.056, 0.042, 0.052],
                                                seg=8), "bone", knee)
            self.part("foot" + side, C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0, -0.05, fz + 0.022),
                      scale=(0.06, 0.12, 0.032)), "bone", knee)
            for t in (-1, 0, 1):
                self.part("toe" + side, C.bm_tube([(0.025 * t, -0.13, fz + 0.02), (0.03 * t, -0.19, fz + 0.012)],
                                                  [0.014, 0.010], seg=5), "bone", knee)
        self.foot_z = fz

    def build_torso(self, pelvis, spine) -> None:
        tw, td = self.TW, self.TD
        self.part("pelvisBone", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, 0.01, -0.01), scale=(0.17, 0.10, 0.08)),
                  "bone", pelvis)
        for k in range(6):
            self.part("vert%d" % k, C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, 0.05, 0.02 + 0.075 * k),
                      scale=(0.040, 0.036, 0.030)), "bone", spine)
        # fond sombre : fait ressortir les côtes
        self.part("chestDark", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, 0.01, 0.27),
                  scale=(0.14 * tw, 0.10 * td, 0.15)), "socket", spine)
        for k, (z, rx, ry) in enumerate(((0.13, 0.125, 0.098), (0.185, 0.155, 0.112), (0.24, 0.172, 0.122),
                                         (0.295, 0.182, 0.126), (0.35, 0.176, 0.120), (0.40, 0.150, 0.104))):
            self.part("rib%d" % k, C.bm_xform(ring(rx * tw, ry * td, 0.021), loc=(0, 0.0, z), rot=(0.30, 0, 0)),
                      "bone", spine)
        self.part("sternum", C.bm_xform(C.bm_box(0.036, 0.025, 0.24, bevel=0.01), loc=(0, -0.12 * td, 0.29),
                  rot=(-0.1, 0, 0)), "bone", spine)
        for sx in (1, -1):
            self.part("clav", C.bm_tube([(0.02 * sx, -0.10 * td, 0.41), (0.12 * sx * tw, -0.05, 0.43),
                                         (0.20 * sx * tw ** 0.6, 0.0, 0.40)], [0.030, 0.026, 0.032], seg=6), "bone", spine)
        # bassin osseux (ailes iliaques), pagne sombre en lambeaux, ceinture de cuir
        for sx in (1, -1):
            self.part("ilium", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.09 * sx, 0.0, 0.03), scale=(0.07, 0.05, 0.06),
                      rot=(0, 0.5 * sx, 0)), "bone", pelvis)
        self.part("hipWrap", C.bm_xform(ring(0.15, 0.105, 0.028), loc=(0, 0.0, 0.02)), "rag", pelvis)
        for k, (x, y, ln) in enumerate(((-0.05, -0.11, 0.24), (0.06, -0.10, 0.19), (0.0, 0.10, 0.22), (0.12, 0.0, 0.15))):
            self.part("rag%d" % k, C.bm_tube([(x, y, 0.0), (x * 1.1, y * 1.12, -ln * 0.5), (x * 1.2 + 0.01, y * 1.1, -ln)],
                                             [0.045, 0.036, 0.004], seg=5, flat=0.25, up=(0, 1, 0) if abs(y) > 0.05 else (1, 0, 0)),
                      "rag", pelvis)
        self.part("belt", C.bm_xform(ring(0.155, 0.11, 0.016), loc=(0, 0, 0.055)), "strap", pelvis)

    def build_arms(self, spine) -> None:
        j = self.j
        al = self.AL
        for side, sx in (("L", 1), ("R", -1)):
            ua = j["ua" + side] = qjoint("ua" + side, spine, self.shoulder[side])
            fa = j["fa" + side] = qjoint("fa" + side, spine, (0, 0, 0))
            self.part("shoulder" + side, C.bm_sphere(10, 6, 0.068), "bone", ua)
            self.part("uarm" + side, C.bm_tube([(0, 0, 0), (0, 0, -0.10 * al), (0, 0, -0.20 * al)],
                                               [0.050, 0.038, 0.048], seg=8), "bone", ua)
            self.part("elbow" + side, C.bm_sphere(8, 6, 0.046), "bone", fa)
            self.part("farm" + side, C.bm_tube([(0, 0, 0), (0, 0, -self.ll * 0.5), (0, 0, -self.ll + 0.03)],
                                               [0.040, 0.032, 0.040], seg=8), "bone", fa)
            self.part("hand" + side, C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0, 0, -self.ll + 0.005),
                      scale=(0.058, 0.050, 0.056)), "bone", fa)
            for t in (-1, 0, 1):
                self.part("finger" + side, C.bm_tube([(0.018 * t, -0.01, -self.ll - 0.02),
                                                      (0.02 * t, -0.03, -self.ll - 0.07)], [0.011, 0.008], seg=5),
                          "bone", fa)

    def build_head(self, head) -> None:
        self.skull(head, "bone", sx=0.175, sy=0.18, sz=0.18, jaw=0.32)
        for sx in (1, -1):
            self.part("socket", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0.070 * sx, -0.150, 0.212),
                      scale=(0.050, 0.040, 0.056)), "socket", head)
            self.part("pupil", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.064 * sx, -0.180, 0.208),
                      scale=(0.020, 0.010, 0.018)), "eye_glow", head, nofs=True)
            self.part("cheek", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.11 * sx, -0.130, 0.150),
                      scale=(0.040, 0.040, 0.030)), "bone", head)
        self.part("noseHole", C.bm_xform(C.bm_cyl(3, 0.030, 0.0, 0.05), loc=(0, -0.172, 0.152),
                  rot=(math.pi / 2, 0, math.pi)), "socket", head, nofs=True)
        self.part("jaw", C.bm_xform(C.bm_box(0.21, 0.16, 0.06, bevel=0.024), loc=(0, -0.075, 0.050)), "bone", head)
        self.part("mouthDark", C.bm_xform(C.bm_box(0.16, 0.02, 0.040), loc=(0, -0.140, 0.098)), "socket", head, nofs=True)
        for k in range(6):
            x = -0.0625 + 0.025 * k
            self.part("teethU", C.bm_xform(C.bm_box(0.020, 0.012, 0.030, bevel=0.004), loc=(x, -0.158, 0.110)),
                      "tooth", head)
            self.part("teethD", C.bm_xform(C.bm_box(0.020, 0.012, 0.026, bevel=0.004), loc=(x, -0.142, 0.083)),
                      "tooth", head)

    def dress(self) -> None:
        # deux lames (khopesh de bronze terni), une par main, comme sur la planche
        w = self.weapon("khopesh", "R", (0.9, 0, 0))
        khopesh(self, w, "khopesh", 1.25, key="bronze", edge="strap")
        w2 = self.weapon("khopeshL", "L", (0.9, 0, 0))
        khopesh(self, w2, "khopeshL", 1.15, key="bronze", edge="strap")
        self.muzzle_ref = ("khopesh", (0, -0.42 * 1.25, -0.06 * 1.25))
        self.part("armband", C.bm_xform(ring(0.042, 0.042, 0.012), loc=(0, 0, -0.06)), "rag", self.j["uaL"])

    def wrot(self, name: str, rot, off=(0, 0, 0)) -> None:
        super().wrot(name, rot, off)
        if name == "khopesh" and "khopeshL" in self.weap:
            super().wrot("khopeshL", (rot[0], -rot[1], -rot[2]), off)

    def arms_rest(self, b: float = 0.0) -> None:
        # bras longs pendants, écartés, lames prêtes (posture voûtée de la planche)
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.16, -0.16, -0.40 + 0.012 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.16, -0.18, -0.38 + 0.012 * b)), self.R_POLE)
        self.wrot("khopesh", (1.1, 0, -0.35))

    def idle_extra(self, t: float) -> None:
        # accroupi, jambes écartées, prêt à bondir ; la tête balaie la salle (cherche les intrus)
        b = math.sin(t)
        self.j["pelvis"].location.z = self.PZ - 0.085 - 0.01 * b
        self.legs((-0.50, -0.20, 0.55), (-0.46, 0.20, -0.55), 0.95 + 0.03 * b, 0.90 + 0.03 * b)
        self.j["neck"].rotation_euler = (-0.25, 0.0, 0.25 * math.sin(t * 0.5))

    def run_extra(self, p: float) -> None:
        self.wrot("khopesh", (0.5, 0, -0.2))

    def hit_extra(self, k: float) -> None:
        self.wrot("khopesh", (0.2, 0, -0.4))

    def death_extra(self, t: float) -> None:
        self.wrot("khopesh", (1.3, 0.6 * t, -0.6))

    def pose_attack(self, i: int, n: int) -> None:
        # khopesh levé (0-2), coup de taille en diagonale (3), suivi (4), retour (5)
        self.rest()
        j = self.j
        lean = (0.0, -0.12, -0.16, 0.42, 0.40, 0.15)[i]
        twist = (-0.15, -0.35, -0.40, 0.30, 0.40, 0.1)[i]
        j["pelvis"].location.z = self.PZ - (0.0, 0.01, 0.02, 0.06, 0.05, 0.02)[i]
        self.spine_rot(lean, 0, twist)
        stride = (0.15, 0.25, 0.3, 0.7, 0.65, 0.3)[i]
        self.legs((-stride * 0.6, -0.08, 0), (stride * 0.5, 0.10, 0), 0.2 + 0.1 * stride, 0.35 + 0.2 * stride)
        sh = self.shoulder
        hand = [Vector((-0.08, 0.04, 0.10)), Vector((-0.10, 0.12, 0.34)), Vector((-0.10, 0.14, 0.38)),
                Vector((0.10, -0.40, -0.06)), Vector((0.18, -0.26, -0.26)), Vector((-0.02, -0.22, -0.24))][i]
        self.arm_ik("R", sh["R"] + hand, Vector((-0.8, 0.5, -0.2)))
        self.wrot("khopesh", [(-1.2, 0, -0.2), (-2.1, 0, -0.1), (-2.3, 0, -0.1), (0.5, 0, 0.5), (1.2, 0, 0.6),
                              (0.9, 0, 0.0)][i])
        self.arm_ik("L", sh["L"] + [Vector((0.08, -0.16, -0.22)), Vector((0.10, -0.24, -0.12)),
                                    Vector((0.10, -0.26, -0.10)), Vector((0.12, 0.06, -0.26)),
                                    Vector((0.10, 0.08, -0.28)), Vector((0.06, -0.08, -0.30))][i], self.L_POLE)


# ------------------------------------------------------------------------------- archer sable
class Archer(Skeleton):
    BOW_H = 0.62

    def build_head(self, head) -> None:
        super().build_head(head)
        # crâne nu (la planche ne montre aucune coiffe)

    def dress(self) -> None:
        sp = self.j["spine"]
        # carquois dans le dos, flèches à empennage rouge
        q = joint("w_quiver", sp, (-0.06, 0.16, 0.24))
        q.rotation_euler = (-0.25, 0.35, 0)
        self.part("quiverBody", C.bm_cyl(10, 0.055, 0.045, 0.34), "strap", q)
        self.part("quiverRim", C.bm_xform(ring(0.058, 0.058, 0.012), loc=(0, 0, 0.17)), "gold", q)
        for k in range(4):
            x, y = 0.02 * math.cos(k * 1.7), 0.02 * math.sin(k * 1.7)
            self.part("qArrow", C.bm_xform(C.bm_cyl(5, 0.006, 0.006, 0.12), loc=(x, y, 0.22)), "wood", q)
            self.part("qFletch", C.bm_xform(C.bm_box(0.008, 0.03, 0.05), loc=(x, y, 0.27)), "fletch", q)
        self.part("quiverStrap", C.bm_tube(C.bezier((0.16, 0.10, 0.44), (0.12, -0.14, 0.40), (-0.06, -0.15, 0.20),
                                                    (-0.16, 0.0, 0.06), 6), [0.016] * 6, seg=5, flat=0.4), "strap", sp)
        # arc tenu à la main gauche (corde refaite à chaque pose)
        w = self.weapon("bow", "L", (0, 0, 0))
        h = self.BOW_H
        limb = [(0, 0.10, h), (0, 0.04, h * 0.86), (0, -0.04, h * 0.55), (0, -0.03, h * 0.18), (0, -0.02, 0.0),
                (0, -0.03, -h * 0.18), (0, -0.04, -h * 0.55), (0, 0.04, -h * 0.86), (0, 0.10, -h)]
        self.part("eg_bow", C.bm_tube(limb, [0.016, 0.024, 0.032, 0.040, 0.044, 0.040, 0.032, 0.024, 0.016], seg=8),
                  "wood", w)
        for z in (h, -h, 0.0):
            self.part("bowTip", C.bm_xform(C.bm_sphere(8, 6, 0.030 if z else 0.050), loc=(0, 0.10 if z else -0.02, z)),
                      "bronze", w)
        self.bow_string = self.part("bowString", C.bm_tube([(0, 0.10, h), (0, 0.10, 0), (0, 0.10, -h)],
                                                           [0.007] * 3, seg=4), "string", w)
        self.part("arrowShaft", C.bm_xform(C.bm_cyl(6, 0.010, 0.010, 0.50), loc=(0, -0.06, 0.0), rot=(math.pi / 2, 0, 0)),
                  "wood", w, grp="arrow")
        self.part("arrowHead", C.bm_xform(C.bm_cyl(6, 0.022, 0.0, 0.06), loc=(0, -0.33, 0.0), rot=(math.pi / 2, 0, 0)),
                  "gold", w, grp="arrow")
        self.part("arrowFletch", C.bm_xform(C.bm_box(0.008, 0.08, 0.05), loc=(0, 0.15, 0.0)), "fletch", w, grp="arrow")
        self.arrow_rest = [ob.location.copy() for ob in self.grp["arrow"]]
        self.muzzle_ref = ("eg_bow", (0, -0.20, 0.0))

    def set_draw(self, d: float, arrow: bool) -> None:
        h = self.BOW_H
        remesh(self.bow_string, C.bm_tube([(0, 0.10, h), (0, 0.10 + d, 0), (0, 0.10, -h)], [0.007] * 3, seg=4))
        self.show("arrow", arrow)
        for ob, base in zip(self.grp["arrow"], self.arrow_rest):
            ob.location = base + Vector((0, d, 0))

    def arms_rest(self, b: float = 0.0) -> None:
        # aux aguets : arc levé devant lui, flèche encochée, à demi bandé (planche)
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.24, -0.30, -0.08 + 0.01 * b)), Vector((0.9, 0.3, -0.3)))
        rot = (0.0, -0.25, -0.65)
        self.wrot("bow", rot)
        draw = 0.14
        self.set_draw(draw, True)
        nock = self.hand["L"] + Euler(rot).to_matrix() @ Vector((0, 0.10 + draw, 0))
        self.arm_ik("R", nock + Vector((0, 0.03, 0)), Vector((-0.9, 0.4, -0.1)))

    def idle_extra(self, t: float) -> None:
        # campé jambes écartées, buste tourné vers la cible
        self.spine_rot(0.06, 0, 0.18)
        self.j["pelvis"].location.z = self.PZ - 0.05
        self.legs((-0.30, -0.24, 0.35), (-0.26, 0.24, -0.35), 0.55, 0.50)
        self.j["neck"].rotation_euler = (-0.05, 0.0, -0.10 + 0.06 * math.sin(t))

    def run_extra(self, p: float) -> None:
        self.wrot("bow", (0.25, 0, 0.1))
        self.set_draw(0.0, False)

    def hit_extra(self, k: float) -> None:
        self.wrot("bow", (0.3, 0, 0.2))
        self.set_draw(0.0, False)

    def death_extra(self, t: float) -> None:
        self.wrot("bow", (0.6 + 0.8 * t, 0.0, 0.5))
        self.set_draw(0.0, False)

    def pose_attack(self, i: int, n: int) -> None:
        # bande l'arc (0-2, tenu), décoche (3), retour (4-5)
        self.rest()
        j = self.j
        self.spine_rot((0.02, 0.0, -0.02, -0.04, 0.0, 0.02)[i], 0, (-0.10, -0.22, -0.25, -0.20, -0.12, -0.05)[i])
        self.legs((-0.25, -0.12, 0), (0.22, 0.12, 0), 0.12, 0.18)
        sh = self.shoulder
        up = (0.0, 0.10, 0.12, 0.12, 0.08, 0.0)[i]
        bow = sh["L"] + Vector((-0.10, -0.42, -0.04 + up)) if i in (1, 2, 3, 4) else sh["L"] + Vector((-0.02, -0.30, -0.18))
        self.arm_ik("L", bow, Vector((0.9, 0.3, -0.3)))
        rot = (0.0, 0.0, 0.0) if i in (1, 2, 3, 4) else (0.25, 0, 0.1)
        self.wrot("bow", rot)
        draw = (0.05, 0.20, 0.27, 0.0, 0.0, 0.0)[i]
        self.set_draw(draw, i < 3)
        nock = self.hand["L"] + Euler(rot).to_matrix() @ Vector((0, 0.10 + draw, 0))
        if i < 3:
            self.arm_ik("R", nock + Vector((0, 0.03, 0)), Vector((-0.9, 0.4, -0.1)))
        else:
            self.arm_ik("R", sh["R"] + Vector((-0.12, 0.10 if i == 3 else 0.0, -0.10 - 0.08 * (i - 3))), self.R_POLE)


# ------------------------------------------------------------------------------- momie étouffée
class Mummy(EgHuman):
    def build_head(self, head) -> None:
        self.skull(head, "wrap", sx=0.165, sy=0.175, sz=0.20, jaw=0.10)
        # visage décharné entre les bandelettes : orbites creuses, yeux brûlants, bouche béante
        self.part("face", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, -0.118, 0.175), scale=(0.115, 0.07, 0.115)),
                  "flesh", head)
        for sx in (1, -1):
            self.part("socket", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0.055 * sx, -0.172, 0.218),
                      scale=(0.040, 0.025, 0.030)), "socket", head)
            self.part("cheekHollow", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.07 * sx, -0.165, 0.15),
                      scale=(0.022, 0.015, 0.035)), "socket", head)
        self.eyes(head, "eye_glow", z=0.218, x=0.055, y=-0.190, r=(0.020, 0.010, 0.014), brow=False)
        self.part("nose", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -0.188, 0.180), scale=(0.022, 0.02, 0.03)),
                  "flesh", head)
        self.part("mouthGap", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0, -0.172, 0.112), scale=(0.055, 0.02, 0.034)),
                  "socket", head, nofs=True)
        for k in range(4):
            self.part("toothM", C.bm_xform(C.bm_box(0.016, 0.01, 0.02), loc=(-0.027 + 0.018 * k, -0.186, 0.132)),
                      "tooth", head, nofs=True)
        # bandelettes de la tête : front, joues, menton (le visage reste visible au milieu)
        self.wraps(head, [(0, 0.0, 0.33, 0.150, 0.158, 0.25), (0, 0.0, 0.285, 0.168, 0.175, -0.2),
                          (0, 0.01, 0.24, 0.17, 0.165, 0.5), (0, 0.0, 0.07, 0.13, 0.14, -0.35)], tube=0.016)

    def dress(self) -> None:
        sp, pel = self.j["spine"], self.j["pelvis"]
        tw, td = self.TW, self.TD
        self.wraps(sp, [(0, 0, 0.02, 0.20 * tw, 0.145 * td, 0.25), (0, 0, 0.09, 0.215 * tw, 0.155 * td, -0.35),
                        (0, 0, 0.16, 0.228 * tw, 0.162 * td, 0.3), (0, 0, 0.23, 0.240 * tw, 0.166 * td, -0.4),
                        (0, 0, 0.30, 0.245 * tw, 0.165 * td, 0.35), (0, 0, 0.37, 0.232 * tw, 0.155 * td, -0.3),
                        (0, 0, 0.42, 0.18 * tw, 0.13 * td, 0.4)], tube=0.016)
        self.wraps(pel, [(0, 0, 0.0, 0.23 * tw ** 0.8, 0.17 * td, 0.2)], tube=0.014)
        self.limb_wraps()
        # dos voûté : bosse des trapèzes bandée, épaules remontées
        self.part("hump", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, 0.06, 0.40), scale=(0.20 * tw, 0.13 * td, 0.11)),
                  "wrap", sp)
        self.wraps(sp, [(0, 0.06, 0.42, 0.17 * tw, 0.11 * td, 0.9)], tube=0.015)
        # bandelettes pendantes (bras, taille)
        for side, sx in (("L", 1), ("R", -1)):
            fa = self.j["fa" + side]
            self.part("strip" + side, C.bm_tube([(0.03 * sx, 0.03, -0.06), (0.05 * sx, 0.06, -0.14), (0.05 * sx, 0.10, -0.24)],
                                                [0.03, 0.026, 0.004], seg=5, flat=0.25, up=(1, 0, 0)), "wrap", fa)
        for k, x in enumerate((0.14, -0.10, 0.02)):
            self.part("waistStrip", C.bm_tube([(x * tw, -0.14 * td, 0.0), (x * tw * 1.1, -0.15 * td, -0.12),
                                               (x * tw * 1.2 + 0.03, -0.13 * td, -0.24 - 0.04 * k)],
                                              [0.035, 0.03, 0.005], seg=5, flat=0.25, up=(0, 1, 0)), "wrap", pel)
        # amulette (scarabée d'or) et collier
        self.part("amulet", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, -0.175 * td, 0.30), scale=(0.035, 0.02, 0.045)),
                  "bronze", sp)
        self.part("amuletCord", C.bm_xform(ring(0.13 * tw, 0.12 * td, 0.008), loc=(0, -0.02, 0.38), rot=(0.5, 0, 0)),
                  "strap", sp)
        # griffes sèches au bout des mains bandées
        for side in ("L", "R"):
            fa = self.j["fa" + side]
            for t in (-1, 0, 1):
                self.part("claw" + side, C.bm_tube([(0.03 * t, -0.02, -self.ll - 0.03), (0.035 * t, -0.05, -self.ll - 0.09)],
                                                   [0.016, 0.006], seg=5), "flesh", fa)
        self.muzzle_ref = ("handR", (0, 0, -self.ll))

    def arms_rest(self, b: float = 0.0) -> None:
        # bras lourds pendants, un peu en avant, écartés (planche)
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.22, -0.24, -0.34 + 0.015 * b)), Vector((1.0, 0.3, -0.1)))
        self.arm_ik("R", s["R"] + Vector((-0.20, -0.28, -0.30 + 0.02 * b)), Vector((-1.0, 0.3, -0.1)))

    def idle_extra(self, t: float) -> None:
        self.j["pelvis"].location.z = self.PZ - 0.05
        self.legs((-0.30, -0.16, 0.3), (-0.26, 0.16, -0.3), 0.55, 0.50)
        self.j["neck"].rotation_euler = (-0.55, 0.0, 0.10 + 0.05 * math.sin(t))
        self.j["head"].rotation_euler = (-0.30, 0.0, 0.0)

    def pose_run(self, i: int, n: int) -> None:
        # marche lourde et traînante, bras tendus
        self.rest()
        j = self.j
        p = 2 * math.pi * i / n
        s = math.sin(p)
        j["pelvis"].location.z = self.PZ - 0.03 + 0.03 * abs(math.sin(p + 0.35))
        j["pelvis"].rotation_euler = (0, 0.05 * s, -0.10 * s)
        self.spine_rot(0.14, 0.06 * s, 0.10 * s)
        self.legs((-0.45 * s - 0.08, 0, 0.04), (0.42 * s - 0.08, 0, -0.04),
                  0.16 + 0.7 * max(0.0, math.sin(p - 1.0)) ** 1.2,
                  0.20 + 0.6 * max(0.0, math.sin(p - 1.0 + math.pi)) ** 1.2)
        sh = self.shoulder
        self.arm_ik("L", sh["L"] + Vector((0.02, -0.38, -0.06 + 0.03 * s)), self.L_POLE)
        self.arm_ik("R", sh["R"] + Vector((-0.02, -0.38, -0.04 - 0.03 * s)), self.R_POLE)
        j["neck"].rotation_euler = (-0.05, 0.0, 0.2)

    def pose_attack(self, i: int, n: int) -> None:
        # lève les deux bras (0-2), abat les poings joints (3), se redresse (4-5)
        self.rest()
        j = self.j
        crouch = (0.02, 0.0, -0.02, 0.12, 0.10, 0.04)[i]
        j["pelvis"].location.z = self.PZ - crouch
        lean = (-0.05, -0.20, -0.26, 0.50, 0.46, 0.18)[i]
        self.spine_rot(lean - self.HUNCH * 0.5, 0, 0)
        self.legs((-0.3, -0.12, 0), (0.25, 0.12, 0), 0.3 + crouch * 2, 0.35 + crouch * 2)
        sh = self.shoulder
        if i < 3:
            up = (0.24, 0.46, 0.52)[i]
            hl, hr = Vector((-0.12, -0.02, up)), Vector((0.12, -0.02, up))
        elif i < 5:
            hl, hr = Vector((-0.16, -0.42, -0.22)), Vector((0.16, -0.42, -0.22))
        else:
            hl, hr = Vector((0.0, -0.30, -0.30)), Vector((0.0, -0.30, -0.30))
        self.arm_ik("L", sh["L"] + hl, Vector((0.9, 0.2, 0.1)))
        self.arm_ik("R", sh["R"] + hr, Vector((-0.9, 0.2, 0.1)))


# ------------------------------------------------------------------------------- guerrier de l'ombre (élite)
class Jackal(EgHuman):
    def build_head(self, head) -> None:
        self.skull(head, "fur", sx=0.16, sy=0.17, sz=0.17, jaw=0.2)
        # museau de chacal, mâchoire, truffe
        self.part("snout", C.bm_tube([(0, -0.08, 0.19), (0, -0.21, 0.165), (0, -0.33, 0.13), (0, -0.39, 0.112)],
                                     [0.088, 0.064, 0.042, 0.022], seg=10, flat=0.85), "fur", head)
        self.part("jawJ", C.bm_tube([(0, -0.08, 0.12), (0, -0.20, 0.11), (0, -0.30, 0.10)], [0.06, 0.042, 0.02],
                                    seg=8, flat=0.6), "fur", head)
        self.part("nose", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -0.39, 0.125), scale=(0.025, 0.02, 0.018)),
                  "socket", head)
        for sx in (1, -1):
            self.part("ear", C.bm_tube([(0.075 * sx, 0.02, 0.30), (0.095 * sx, 0.03, 0.46), (0.11 * sx, 0.05, 0.64)],
                                       [0.060, 0.044, 0.0], seg=8, flat=0.35, up=(0, 1, 0)), "fur", head)
            self.part("earIn", C.bm_tube([(0.076 * sx, 0.0, 0.32), (0.094 * sx, 0.012, 0.46), (0.106 * sx, 0.03, 0.59)],
                                         [0.036, 0.026, 0.0], seg=6, flat=0.25, up=(0, 1, 0)), "lapis", head)
            self.part("eyeJ", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.062 * sx, -0.150, 0.225),
                      scale=(0.030, 0.012, 0.016), rot=(0, 0.35 * sx, 0)), "eye_glow", head, nofs=True)
            # pans de la coiffe (or et lapis)
            self.part("lappet", C.bm_xform(C.bm_box(0.05, 0.10, 0.22, bevel=0.015), loc=(0.15 * sx, 0.06, 0.12),
                      rot=(0.15, 0, 0)), "fur", head)
        self.part("headband", C.bm_xform(ring(0.163, 0.17, 0.016), loc=(0, 0.0, 0.27), rot=(0.12, 0, 0)), "gold", head)

    def dress(self) -> None:
        sp, pel = self.j["spine"], self.j["pelvis"]
        tw, td = self.TW, self.TD
        # collier ousekh (or et lapis)
        for k, (r, key) in enumerate(((0.22, "gold"), (0.19, "lapis"), (0.16, "gold"))):
            self.part("usekh%d" % k, C.bm_xform(ring(r * tw ** 0.7, r * 0.8 * td, 0.026), loc=(0, -0.01, 0.43 - 0.012 * k),
                      rot=(0.3, 0, 0), scale=(1, 1, 0.55)), key, sp)
        for sx in (1, -1):
            self.part("pec", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0.10 * sx * tw, -0.12 * td, 0.30),
                      scale=(0.11 * tw, 0.06 * td, 0.08)), "steel", sp)
            self.part("pauldron", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0.0, 0.0, 0.0), scale=(0.12, 0.12, 0.08)),
                      "steel", self.j["ua" + ("L" if sx > 0 else "R")])
            self.part("pauldronRim", C.bm_xform(ring(0.11, 0.11, 0.012), loc=(0, 0, -0.03)), "gold",
                      self.j["ua" + ("L" if sx > 0 else "R")])
        # cuirasse d'écailles (ventre)
        self.part("scaleMail", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, -0.03, 0.15), scale=(0.21 * tw, 0.15 * td, 0.16)),
                  "steel", sp)
        # pagne (chendjit) blanc et devanteau d'or, ceinture
        secs = [C.ellipse(0, 0.0, z, rx, ry, 20) for z, rx, ry in ((0.07, 0.21, 0.16), (-0.10, 0.24, 0.19),
                                                                    (-0.26, 0.27, 0.21))]
        self.part("kilt", C.bm_loft(secs, cap_start=False, cap_end=False), "kilt", pel, thick=0.012)
        self.part("apron", C.bm_xform(C.bm_box(0.10, 0.02, 0.28, bevel=0.01), loc=(0, -0.205, -0.10), rot=(0.08, 0, 0)),
                  "steel", pel)
        self.part("kiltHem", C.bm_xform(ring(0.27, 0.21, 0.012), loc=(0, 0, -0.255)), "gold", pel)
        self.part("belt", C.bm_xform(ring(0.215, 0.165, 0.026), loc=(0, 0, 0.07)), "gold", pel)
        for side in ("L", "R"):
            self.part("bracer" + side, C.bm_xform(C.bm_cyl(12, 0.082 * self.AW, 0.075 * self.AW, 0.10),
                      loc=(0, 0, -0.12 * self.AL)), "gold", self.j["fa" + side])
            self.part("armRing" + side, C.bm_xform(ring(0.098 * self.AW, 0.095 * self.AW, 0.014), loc=(0, 0, -0.05)),
                      "gold", self.j["ua" + side])
        w = self.weapon("khopesh", "R", (0.9, 0, 0))
        mace_staff(self, w, "maceW", 1.2)

    def arms_rest(self, b: float = 0.0) -> None:
        s = self.shoulder
        # masse-sceptre tenue droite devant l'épaule, poing gauche serré (planche)
        self.arm_ik("L", s["L"] + Vector((0.12, -0.10, -0.34 + 0.01 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.10, -0.24, -0.20 + 0.01 * b)), self.R_POLE)
        self.wrot("khopesh", (-1.45, 0, -0.12), (0, 0, 0.0))

    def idle_extra(self, t: float) -> None:
        self.j["pelvis"].location.z = self.PZ - 0.04
        self.legs((-0.26, -0.18, 0.25), (-0.18, 0.18, -0.25), 0.45, 0.38)

    def run_extra(self, p: float) -> None:
        self.wrot("khopesh", (-0.2, 0, -0.5))

    def hit_extra(self, k: float) -> None:
        self.wrot("khopesh", (0.2, 0, -0.5))

    def death_extra(self, t: float) -> None:
        self.wrot("khopesh", (1.3, 0.6 * t, -0.6))

    def pose_attack(self, i: int, n: int) -> None:
        # armé sur le côté (0-2), balayage horizontal au khopesh (3), suivi (4), retour (5)
        self.rest()
        j = self.j
        crouch = (0.03, 0.07, 0.08, 0.05, 0.03, 0.01)[i]
        j["pelvis"].location.z = self.PZ - crouch
        self.spine_rot((0.12, 0.20, 0.22, 0.38, 0.32, 0.12)[i], 0, (-0.35, -0.60, -0.65, 0.55, 0.70, 0.15)[i])
        stride = (0.25, 0.4, 0.45, 0.85, 0.8, 0.4)[i]
        self.legs((-stride * 0.6, -0.10, 0), (stride * 0.5, 0.12, 0), 0.25 + crouch * 2, 0.45 + crouch * 2)
        sh = self.shoulder
        hand = [Vector((-0.18, 0.08, -0.05)), Vector((-0.26, 0.18, 0.04)), Vector((-0.28, 0.20, 0.05)),
                Vector((0.28, -0.40, -0.06)), Vector((0.38, -0.12, -0.14)), Vector((0.0, -0.24, -0.22))][i]
        self.arm_ik("R", sh["R"] + hand, Vector((-0.6, 0.6, -0.4)))
        self.wrot("khopesh", [(0.1, 0, -1.6), (0.15, 0, -2.3), (0.15, 0, -2.4), (0.25, 0, 0.6), (0.3, 0, 1.3),
                              (0.5, 0, 0.0)][i])
        self.arm_ik("L", sh["L"] + [Vector((0.10, -0.22, -0.18)), Vector((0.12, -0.30, -0.08)),
                                    Vector((0.12, -0.32, -0.06)), Vector((0.14, 0.10, -0.24)),
                                    Vector((0.10, 0.12, -0.26)), Vector((0.08, -0.10, -0.30))][i], self.L_POLE)


# ------------------------------------------------------------------------------- prêtre du soleil (élite)
def flame_staff(rig, parent, name: str, length: float, k: float = 1.0) -> None:
    """Bâton d'or (axe +Z local) couronné d'un soleil enflammé : disque ardent, rayons-flammes, griffes d'or."""
    rig.part(name + "Pole", C.bm_xform(C.bm_cyl(8, 0.022 * k, 0.020 * k, length), loc=(0, 0, length * 0.5 - 0.45 * k)),
             "gold", parent)
    top = length - 0.45 * k
    for z in (0.0, -0.3, top - 0.05):
        rig.part(name + "Ring", C.bm_xform(ring(0.03 * k, 0.03 * k, 0.010 * k), loc=(0, 0, z)), "bronze", parent)
    c = Vector((0, 0, top + 0.14 * k))
    for sx in (1, -1):
        rig.part(name + "Claw", C.bm_tube([(0.02 * sx * k, 0, top), (0.12 * sx * k, 0, top + 0.06 * k),
                                           (0.13 * sx * k, 0, top + 0.20 * k), (0.07 * sx * k, 0, top + 0.27 * k)],
                                          [0.020 * k, 0.018 * k, 0.014 * k, 0.0], seg=6), "gold", parent)
    rig.part(name, C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=tuple(c), scale=(0.085 * k, 0.05 * k, 0.085 * k)),
             "sun", parent, nofs=True)
    rig.part(name + "Core", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=tuple(c + Vector((0, -0.03 * k, 0))),
             scale=(0.05 * k, 0.03 * k, 0.05 * k)), "sun_core", parent, nofs=True)
    for a in range(10):
        ang = 2 * math.pi * a / 10 + 0.2
        d = Vector((math.cos(ang), 0, math.sin(ang)))
        ln = (0.13 if a % 2 else 0.20) * k
        p0 = c + d * 0.07 * k
        p1 = c + d * (0.07 * k + ln * 0.55) + Vector((0, 0, 0.03 * k))
        p2 = c + d * (0.07 * k + ln) + Vector((0, 0, 0.07 * k))
        rig.part(name + "Flame", C.bm_tube([tuple(p0), tuple(p1), tuple(p2)], [0.032 * k, 0.020 * k, 0.0], seg=6,
                                           flat=0.5, up=(0, 1, 0)), "sun", parent, nofs=True)
    rig.muzzle_ref = (name, (0, -0.05 * k, top + 0.14 * k))


def sun_staff(rig, parent, name: str, length: float, k: float = 1.0) -> None:
    """Bâton d'or (axe +Z local, prise à l'origine) surmonté d'un disque solaire entre deux cornes."""
    rig.part(name + "Pole", C.bm_xform(C.bm_cyl(8, 0.022 * k, 0.020 * k, length), loc=(0, 0, length * 0.5 - 0.45 * k)),
             "gold", parent)
    top = length - 0.45 * k
    rig.part(name + "Knob", C.bm_xform(C.bm_sphere(8, 6, 0.034 * k), loc=(0, 0, top)), "gold", parent)
    for sx in (1, -1):
        rig.part(name + "Horn", C.bm_tube([(0.02 * sx * k, 0, top), (0.13 * sx * k, 0, top + 0.06 * k),
                                           (0.14 * sx * k, 0, top + 0.18 * k), (0.06 * sx * k, 0, top + 0.27 * k)],
                                          [0.022 * k, 0.020 * k, 0.016 * k, 0.0], seg=6), "gold", parent)
    rig.part(name, C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, 0, top + 0.13 * k), scale=(0.10 * k, 0.05 * k, 0.10 * k)),
             "sun", parent, nofs=True)
    rig.part(name + "Core", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, -0.03 * k, top + 0.13 * k),
             scale=(0.055 * k, 0.03 * k, 0.055 * k)), "sun_core", parent, nofs=True)
    rig.muzzle_ref = (name, (0, -0.05 * k, top + 0.13 * k))


class Priest(EgHuman):
    def build_head(self, head) -> None:
        # visage de momie décharné (orbites, yeux de braise, bouche), sous une capuche profonde
        self.skull(head, "wrap", sx=0.16, sy=0.17, sz=0.19, jaw=0.14)
        self.part("face", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, -0.115, 0.17), scale=(0.11, 0.07, 0.115)),
                  "flesh", head)
        for sx in (1, -1):
            self.part("socket", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0.052 * sx, -0.168, 0.214),
                      scale=(0.036, 0.022, 0.026)), "socket", head)
        self.eyes(head, "eye_glow", z=0.214, x=0.052, y=-0.186, r=(0.018, 0.009, 0.012), brow=False)
        self.part("mouthGap", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0, -0.168, 0.11), scale=(0.045, 0.02, 0.022)),
                  "socket", head, nofs=True)
        self.wraps(head, [(0, 0.0, 0.07, 0.13, 0.14, -0.3), (0, 0.0, 0.29, 0.155, 0.165, 0.3)], tube=0.014)
        # capuche : coque drapée jusqu'aux épaules, ouverte devant sur le visage
        hood = C.bm_sphere(24, 16, 1.0)
        kill = [v for v in hood.verts if v.co.y < -0.42 and -0.62 < v.co.z < 0.62]
        bmesh.ops.delete(hood, geom=kill, context="VERTS")
        for v in hood.verts:
            x, y, z = v.co
            f = 1.0 + 0.55 * max(0.0, -z) ** 1.5
            v.co = Vector((x * 0.215 * f, y * 0.225 * f + 0.03, z * 0.30 + 0.22 - 0.10 * max(0.0, -z) ** 2))
        self.hood = self.part("hood", hood, "robe", head)
        C.solidify(self.hood, 0.025, 0.0)

    def dress(self) -> None:
        sp, pel = self.j["spine"], self.j["pelvis"]
        tw, td = self.TW, self.TD
        # longue robe (cache presque les jambes) et ceinture rouge
        bot = -self.PZ + 0.06
        secs = [C.ellipse(0, 0.0, z, rx, ry, 22) for z, rx, ry in ((0.08, 0.22, 0.17), (-0.12, 0.25, 0.20),
                                                                    (-0.36, 0.27, 0.22), (bot, 0.29, 0.24))]
        self.part("robeSkirt", C.bm_loft(secs, cap_start=False, cap_end=False), "robe", pel, thick=0.014)
        self.part("hem", C.bm_xform(ring(0.29, 0.24, 0.016), loc=(0, 0, bot + 0.03)), "gold", pel)
        self.part("hem2", C.bm_xform(ring(0.275, 0.228, 0.010), loc=(0, 0, bot + 0.10)), "mantle", pel)
        self.part("midBand", C.bm_xform(ring(0.255, 0.205, 0.012), loc=(0, 0, -0.20)), "gold", pel)
        for sx in (1, -1):
            self.part("trim", C.bm_tube([(0.12 * sx, -0.17, 0.06), (0.14 * sx, -0.21, -0.20), (0.155 * sx, -0.235, bot + 0.04)],
                                        [0.014, 0.014, 0.014], seg=5), "gold", pel)
        self.part("sash", C.bm_xform(ring(0.225, 0.172, 0.026), loc=(0, 0, 0.07)), "gold", pel)
        # pan brodé devant (étole d'or) et mantelet sur les épaules
        self.part("stole", C.bm_xform(C.bm_box(0.12, 0.02, 0.62, bevel=0.01), loc=(0, -0.20, -0.20), rot=(0.06, 0, 0)),
                  "mantle", pel)
        self.part("mantleM", C.bm_xform(C.bm_sphere(18, 10, 1.0), loc=(0, 0.0, 0.38), scale=(0.27 * tw, 0.19 * td, 0.12)),
                  "mantle", sp)
        self.part("mantleRim", C.bm_xform(ring(0.27 * tw, 0.19 * td, 0.014, 28), loc=(0, 0, 0.33)), "gold", sp)
        self.part("pectoral", C.bm_xform(C.bm_box(0.11, 0.03, 0.11, bevel=0.02), loc=(0, -0.19 * td, 0.32)), "gold", sp)
        for k, (r, key) in enumerate(((0.20, "gold"), (0.17, "lapis"), (0.145, "gold"))):
            self.part("usekh%d" % k, C.bm_xform(ring(r * tw ** 0.7, r * 0.8 * td, 0.020), loc=(0, -0.02, 0.43 - 0.012 * k),
                      rot=(0.3, 0, 0), scale=(1, 1, 0.55)), key, sp)
        self.part("pectGem", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -0.21 * td, 0.32), scale=(0.03, 0.012, 0.03)),
                  "sun", sp, nofs=True)
        w = self.weapon("staff", "R", (0, 0, 0))
        flame_staff(self, w, "sunStaff", 1.45)
        # globe de lumière dans la main gauche (sort de soutien), visible à l'attaque
        g = self.weapon("orb", "L", (0, 0, 0))
        self.part("orb", C.bm_sphere(12, 8, 0.07), "sun", g, nofs=True, grp="orb")
        self.part("orbCore", C.bm_xform(C.bm_sphere(10, 8, 0.04), loc=(0, -0.02, 0)), "sun_core", g, nofs=True, grp="orb")

    def rest(self) -> None:
        super().rest()
        self.show("orb", False)

    def arms_rest(self, b: float = 0.0) -> None:
        s = self.shoulder
        # bâton tenu bien droit à droite, main gauche tendue paume ouverte (planche)
        self.arm_ik("L", s["L"] + Vector((0.14, -0.34, -0.06 + 0.01 * b)), Vector((0.9, 0.2, -0.5)))
        self.arm_ik("R", s["R"] + Vector((-0.16, -0.14, -0.20 + 0.01 * b)), self.R_POLE)
        self.wrot("staff", (0.05, 0, 0))

    def idle_extra(self, t: float) -> None:
        # flamme solaire au creux de la main tendue (magie de soutien)
        self.show("orb", True)
        self.wrot("orb", (0, 0, 0), (0, -0.04, 0.07))

    def run_extra(self, p: float) -> None:
        self.wrot("staff", (0.35, 0, 0))

    def hit_extra(self, k: float) -> None:
        self.wrot("staff", (-0.25, 0, 0.1))

    def death_extra(self, t: float) -> None:
        self.wrot("staff", (0.2 + 1.2 * t, 0, 0.4))

    def pose_attack(self, i: int, n: int) -> None:
        # lève le bâton et la main gauche (0-2 : le disque s'embrase), projette la lumière (3), retour
        self.rest()
        self.show("orb", 1 <= i <= 3)
        self.spine_rot((0.0, -0.10, -0.14, 0.22, 0.16, 0.04)[i], 0, (0.0, -0.10, -0.12, 0.10, 0.06, 0.0)[i])
        self.legs((-0.18, -0.10, 0), (0.15, 0.10, 0), 0.12, 0.16)
        sh = self.shoulder
        hr = [Vector((-0.10, -0.18, -0.16)), Vector((-0.08, -0.14, 0.12)), Vector((-0.08, -0.14, 0.18)),
              Vector((-0.04, -0.40, 0.04)), Vector((-0.06, -0.34, -0.04)), Vector((-0.10, -0.20, -0.18))][i]
        self.arm_ik("R", sh["R"] + hr, self.R_POLE)
        self.wrot("staff", [(0.0, 0, 0), (-0.15, 0, 0), (-0.2, 0, 0), (0.75, 0, 0), (0.55, 0, 0), (0.15, 0, 0)][i])
        hl = [Vector((0.06, -0.16, -0.30)), Vector((0.12, -0.22, 0.04)), Vector((0.14, -0.24, 0.10)),
              Vector((0.06, -0.42, 0.06)), Vector((0.08, -0.36, -0.04)), Vector((0.06, -0.20, -0.26))][i]
        self.arm_ik("L", sh["L"] + hl, Vector((0.9, 0.3, -0.4)))
        self.wrot("orb", (0, 0, 0), (0, -0.07, 0.02))


# ------------------------------------------------------------------------------- le Pharaon éternel (boss)
class Pharaoh(EgHuman):
    def build_head(self, head) -> None:
        # masque funéraire d'or, yeux brûlants, fard lapis
        self.skull(head, "gold", sx=0.17, sy=0.172, sz=0.19, jaw=0.18)
        self.eyes(head, "eye_glow", z=0.222, x=0.06, y=-0.166, r=(0.030, 0.012, 0.018), brow=True, brow_key="lapis",
                  angle=0.12)
        for sx in (1, -1):
            self.part("kohl", C.bm_xform(C.bm_box(0.05, 0.01, 0.012), loc=(0.10 * sx, -0.158, 0.212), rot=(0, 0.25 * sx, 0)),
                      "lapis", head)
        self.part("nose", C.bm_xform(C.bm_sphere(10, 7, 1.0), loc=(0, -0.172, 0.180), scale=(0.028, 0.03, 0.036)),
                  "gold", head)
        self.part("lips", C.bm_xform(C.bm_box(0.06, 0.02, 0.016, bevel=0.006), loc=(0, -0.162, 0.125)), "red", head)
        # barbe postiche
        self.part("beard", C.bm_xform(C.bm_cyl(10, 0.030, 0.038, 0.16), loc=(0, -0.13, 0.02), rot=(-0.25, 0, 0)), "lapis", head)
        for k in range(3):
            self.part("beardBand", C.bm_xform(ring(0.034 + 0.002 * k, 0.034 + 0.002 * k, 0.008), loc=(0, -0.136 + 0.012 * k, 0.07 - 0.045 * k),
                      rot=(-0.25, 0, 0)), "gold", head)
        # némès rayé : calotte, pans sur la poitrine, queue
        cap = C.bm_sphere(22, 14, 1.0)
        for v in cap.verts:
            x, y, z = v.co
            z = max(z, -0.3)
            v.co = Vector((x * 0.235 * (1.0 + 0.35 * max(0.0, -z)), y * 0.20 + 0.045, z * 0.18 + 0.30))
        self.part("nemes", cap, "nemes_dark", head)
        for k, z in enumerate((0.20, 0.26, 0.32, 0.38, 0.43)):
            n = (z - 0.30) / 0.18
            c = math.sqrt(max(0.0, 1.0 - n * n))
            rx = 0.235 * c * (1.0 + 0.35 * max(0.0, -n)) + 0.006
            self.part("nemesStripe", C.bm_xform(ring(rx, 0.20 * c + 0.006, 0.016), loc=(0, 0.045, z)), "gold", head)
        self.part("nemesBand", C.bm_xform(C.bm_box(0.36, 0.03, 0.04, bevel=0.01), loc=(0, -0.172, 0.29)), "gold", head)
        for sx in (1, -1):
            lap = C.bm_box(0.10, 0.06, 0.40, bevel=0.015)
            for v in lap.verts:
                if v.co.z < 0:
                    v.co.x *= 1.35
            self.part("lappet", C.bm_xform(lap, loc=(0.22 * sx, -0.03, 0.04), rot=(0.08, 0, -0.08 * sx)), "nemes_dark", head)
            for k in range(4):
                self.part("lapStripe", C.bm_xform(C.bm_box(0.14, 0.066, 0.03), loc=(0.22 * sx, -0.03, 0.16 - 0.085 * k),
                          rot=(0.08, 0, -0.08 * sx)), "gold", head)
        self.part("nemesTail", C.bm_tube([(0, 0.18, 0.22), (0, 0.24, 0.10), (0, 0.24, -0.06)], [0.07, 0.05, 0.03], seg=8),
                  "gold", head)
        # uræus (cobra dressé sur le front)
        self.part("uraeus", C.bm_tube([(0, -0.17, 0.30), (0, -0.20, 0.36), (0, -0.215, 0.42), (0, -0.20, 0.45)],
                                      [0.018, 0.022, 0.02, 0.012], seg=6), "gold", head)
        self.part("uraeusHood", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0, -0.21, 0.405), scale=(0.04, 0.012, 0.045)),
                  "lapis", head)
        self.part("uraeusEye", C.bm_xform(C.bm_sphere(6, 4, 0.012), loc=(0, -0.225, 0.43)), "eye_glow", head, nofs=True)

    def dress(self) -> None:
        sp, pel = self.j["spine"], self.j["pelvis"]
        tw, td = self.TW, self.TD
        self.limb_wraps("wrap_dark")
        # plaques segmentées de la cuirasse (ventre)
        for k, z in enumerate((0.04, 0.11, 0.18)):
            self.part("abRing", C.bm_xform(ring((0.205 + 0.01 * k) * tw, (0.148 + 0.006 * k) * td, 0.014), loc=(0, 0, z)),
                      "wrap_dark", sp)
        # plastron et collier ousekh à rangs
        self.part("chestPlate", C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, -0.05, 0.30), scale=(0.235 * tw, 0.13 * td, 0.12)),
                  "gold", sp)
        for k, (r, key) in enumerate(((0.31, "gold"), (0.27, "lapis"), (0.23, "gold"), (0.19, "lapis"), (0.16, "red"))):
            self.part("usekh%d" % k, C.bm_xform(ring(r * tw ** 0.7, r * 0.8 * td, 0.032), loc=(0, -0.02, 0.44 - 0.014 * k),
                      rot=(0.32, 0, 0), scale=(1, 1, 0.55)), key, sp)
        self.part("pectoral", C.bm_xform(C.bm_box(0.12, 0.03, 0.09, bevel=0.015), loc=(0, -0.18 * td, 0.27)), "gold", sp)
        self.part("pectoralGem", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0, -0.20 * td, 0.27), scale=(0.035, 0.015, 0.035)),
                  "curse", sp, nofs=True)
        for sx in (1, -1):
            self.part("pauldron", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0.02 * sx, 0.0, 0.02), scale=(0.12, 0.12, 0.08)),
                      "gold", self.j["ua" + ("L" if sx > 0 else "R")])
        # cape lapis (dos), pagne d'or plissé, ceinture
        cape = C.bm_loft([C.ellipse(0, 0.0, z, rx, ry, 20)[1:10] for z, rx, ry in
                          ((0.44, 0.22 * tw, 0.16 * td), (0.10, 0.30 * tw, 0.24 * td), (-0.30, 0.36 * tw, 0.30 * td),
                           (-self.PZ + 0.14, 0.40 * tw, 0.34 * td))], closed=False)
        self.part("cape", cape, "cape", sp, thick=0.02)
        secs = [C.ellipse(0, 0.0, z, rx, ry, 22) for z, rx, ry in ((0.07, 0.22, 0.165), (-0.12, 0.27, 0.21),
                                                                    (-0.32, 0.31, 0.25))]
        self.part("kilt", C.bm_loft(secs, cap_start=False, cap_end=False), "gold", pel, thick=0.012)
        for k in range(5):
            self.part("kiltLine", C.bm_xform(C.bm_box(0.012, 0.012, 0.30), loc=(-0.10 + 0.05 * k, -0.25, -0.13),
                      rot=(0.18, 0, 0)), "lapis", pel)
        self.part("belt", C.bm_xform(ring(0.225, 0.17, 0.03), loc=(0, 0, 0.07)), "lapis", pel)
        for side in ("L", "R"):
            self.part("bracer" + side, C.bm_xform(C.bm_cyl(12, 0.085 * self.AW, 0.078 * self.AW, 0.11),
                      loc=(0, 0, -0.12 * self.AL)), "gold", self.j["fa" + side])
        w = self.weapon("staff", "R", (0, 0, 0))
        sun_staff(self, w, "pharaohStaff", 1.55, k=1.45)
        w2 = self.weapon("staffL", "L", (0, 0, 0))
        sun_staff(self, w2, "pharaohStaffL", 1.50, k=1.35)
        self.muzzle_ref = ("pharaohStaff", (0, -0.05 * 1.45, 1.55 - 0.45 * 1.45 + 0.13 * 1.45))

    def wrot(self, name: str, rot, off=(0, 0, 0)) -> None:
        super().wrot(name, rot, off)
        if name == "staff" and "staffL" in self.weap:
            super().wrot("staffL", (rot[0], -rot[1], -rot[2]), off)

    def arms_rest(self, b: float = 0.0) -> None:
        s = self.shoulder
        # deux sceptres plantés de part et d'autre, bras écartés (planche)
        self.arm_ik("L", s["L"] + Vector((0.16, -0.14, -0.22 + 0.01 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.16, -0.14, -0.22 + 0.01 * b)), self.R_POLE)
        self.wrot("staff", (0.0, 0, 0))

    def run_extra(self, p: float) -> None:
        self.wrot("staff", (0.30, 0, 0))

    def hit_extra(self, k: float) -> None:
        self.wrot("staff", (-0.25, 0, 0.1))

    def death_extra(self, t: float) -> None:
        self.wrot("staff", (0.2 + 1.2 * t, 0, 0.4))

    def pose_run(self, i: int, n: int) -> None:
        self.S["stride"] = 0.55
        super().pose_run(i, n)

    def pose_attack(self, i: int, n: int) -> None:
        # lève le sceptre à deux mains (0-2), l'abat devant lui (3 : frappe de zone), se redresse (4-5)
        self.rest()
        j = self.j
        crouch = (0.0, -0.01, -0.02, 0.12, 0.10, 0.03)[i]
        j["pelvis"].location.z = self.PZ - crouch
        self.spine_rot((-0.04, -0.20, -0.24, 0.42, 0.36, 0.10)[i], 0, 0)
        self.legs((-0.28, -0.12, 0), (0.24, 0.12, 0), 0.2 + crouch * 2, 0.3 + crouch * 2)
        sh = self.shoulder
        hr = [Vector((0.06, -0.24, -0.06)), Vector((0.10, -0.04, 0.34)), Vector((0.10, -0.02, 0.40)),
              Vector((0.12, -0.44, -0.10)), Vector((0.12, -0.42, -0.14)), Vector((0.0, -0.26, -0.16))][i]
        rot = [(0.1, 0, 0), (-0.6, 0, 0), (-0.75, 0, 0), (0.95, 0, 0), (0.9, 0, 0), (0.3, 0, 0)][i]
        self.arm_ik("R", sh["R"] + hr, Vector((-0.9, 0.3, 0.0)))
        # les deux sceptres se lèvent et s'abattent ensemble (frappe de zone)
        self.arm_ik("L", sh["L"] + Vector((-hr.x, hr.y, hr.z)), Vector((0.9, 0.3, 0.0)))
        self.wrot("staff", rot)


# =============================================================================== scarabée géant
class Scarab(Rig):
    """Scarabée : élytres bleu nuit cerclées d'or, pronotum, tête cornue, mandibles, 6 pattes en IK."""

    def build(self) -> None:
        S = self.S
        j = self.j
        self.BZ = S["body_z"]
        self.L1, self.L2 = S["femur"], S["tibia"]
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["body"] = body = joint("body", root, (0, 0, 0))
        body.scale = (S["scale"],) * 3
        j["thorax"] = th = joint("thorax", body, (0, 0, self.BZ))
        j["head"] = hd = joint("head", th, (0, -0.36, 0.0))
        # élytres (dôme fendu au milieu), bande d'or à l'équateur
        el = C.bm_sphere(22, 14, 1.0)
        for v in el.verts:
            x, y, z = v.co
            z = max(z, -0.35)
            v.co = Vector((x * 0.30 * (1 - 0.15 * y), y * 0.36 + 0.10, z * 0.22 + 0.05))
        self.part("elytra", el, "shell", th)
        self.part("elytraSplit", C.bm_xform(C.bm_box(0.018, 0.60, 0.04), loc=(0, 0.12, 0.26)), "shell_dark", th)
        self.part("elytraRim", C.bm_xform(ring(0.30, 0.36, 0.024, 32), loc=(0, 0.10, 0.03)), "gold", th)
        for sx in (1, -1):
            # nervures d'or le long des élytres (suivent le dôme)
            for xr in (0.10, 0.20):
                pts, rr = [], []
                for k in range(7):
                    yy = -0.20 + 0.075 * k
                    yn = (yy - 0.10) / 0.36
                    xn = xr / (0.30 * (1 - 0.15 * yn))
                    zz = 0.22 * math.sqrt(max(0.0, 1 - xn * xn - yn * yn)) + 0.05
                    pts.append((xr * sx, yy, zz + 0.006))
                    rr.append(0.012 if 0 < k < 6 else 0.004)
                self.part("rib", C.bm_tube(pts, rr, seg=5), "gold", th)
        self.part("belly", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, 0.06, -0.06), scale=(0.24, 0.34, 0.10)),
                  "shell_dark", th)
        # pronotum (plaque avant) cerclé d'or
        pr = C.bm_sphere(18, 10, 1.0)
        for v in pr.verts:
            x, y, z = v.co
            v.co = Vector((x * 0.24, y * 0.15 - 0.24, max(z, -0.3) * 0.15 + 0.06))
        self.part("pronotum", pr, "shell", th)
        self.part("pronotumRim", C.bm_xform(ring(0.24, 0.15, 0.02, 28), loc=(0, -0.24, 0.035)), "gold", th)
        # tête : corne, mandibles, gueule rougeoyante, yeux
        hd.scale = (1.5, 1.5, 1.5)
        self.part("headM", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, -0.06, 0.02), scale=(0.15, 0.11, 0.10)),
                  "shell", hd)
        self.part("headRim", C.bm_xform(ring(0.14, 0.10, 0.012, 24), loc=(0, -0.07, 0.04), rot=(0.5, 0, 0)), "gold", hd)
        # deux cornes recourbées vers le haut (planche)
        for sx in (1, -1):
            self.part("horn", C.bm_tube([(0.05 * sx, -0.08, 0.08), (0.08 * sx, -0.12, 0.20), (0.07 * sx, -0.08, 0.34),
                                         (0.03 * sx, 0.02, 0.42)], [0.030, 0.024, 0.016, 0.0], seg=8), "leg", hd)
        # gueule béante : intérieur rougeoyant, crocs
        self.part("mouthDark", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.150, -0.025), scale=(0.10, 0.05, 0.075)),
                  "socket", hd)
        self.part("mouthGlow", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.168, -0.025), scale=(0.07, 0.04, 0.05)),
                  "mouth", hd, nofs=True)
        for k in range(5):
            x = -0.07 + 0.035 * k
            self.part("fangS", C.bm_xform(C.bm_cyl(4, 0.014, 0.0, 0.05), loc=(x, -0.19, 0.035), rot=(math.pi, 0, 0)),
                      "tooth", hd, nofs=True)
            self.part("fangS", C.bm_xform(C.bm_cyl(4, 0.012, 0.0, 0.04), loc=(x * 0.9, -0.19, -0.072)), "tooth", hd, nofs=True)
        self.mand = {}
        for side, sx in (("L", 1), ("R", -1)):
            m = self.mand[side] = joint("mand" + side, hd, (0.07 * sx, -0.12, -0.03))
            self.part("mandible" + side, C.bm_tube([(0, 0, 0), (0.04 * sx, -0.08, 0.0), (0.01 * sx, -0.16, 0.0),
                                                    (-0.05 * sx, -0.19, 0.0)], [0.036, 0.030, 0.018, 0.0], seg=6,
                                                   flat=0.6), "mandible", m)
            self.part("eye" + side, C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.11 * sx, -0.07, 0.03),
                      scale=(0.022, 0.026, 0.022)), "eye_glow", hd, nofs=True)
            self.part("antenna" + side, C.bm_tube([(0.06 * sx, -0.12, 0.05), (0.12 * sx, -0.20, 0.12),
                                                   (0.16 * sx, -0.22, 0.16)], [0.010, 0.008, 0.02], seg=5), "leg", hd)
        # 6 pattes épineuses (3 par côté)
        self.legs_def = []
        for side, sx in (("L", 1), ("R", -1)):
            for k in range(3):
                ang = math.radians((-42, 2, 42)[k])
                hip = Vector((0.15 * sx, -0.20 + 0.16 * k, -0.04))
                spread = S["spread"]
                rest = Vector((sx * math.cos(ang) * spread, math.sin(ang) * spread * 1.15 - 0.06 + 0.06 * k, 0.0))
                name = "%s%d" % (side, k)
                u = qjoint("leg_u" + name, th, hip)
                lo = qjoint("leg_l" + name, th, (0, 0, 0))
                self.part("femur" + name, C.bm_tube([(0, 0, 0), (0, 0, -self.L1 * 0.5), (0, 0, -self.L1)],
                                                    [0.066, 0.074, 0.056], seg=8), "leg", u)
                self.part("knee" + name, C.bm_xform(ring(0.050, 0.050, 0.012, 12), loc=(0, 0, -0.03)), "gold", lo)
                self.part("tibia" + name, C.bm_tube([(0, 0, 0), (0, 0, -self.L2 * 0.6), (0, 0, -self.L2)],
                                                    [0.056, 0.044, 0.016], seg=8), "leg", lo)
                for s2 in (0.3, 0.6):
                    self.part("spine" + name, C.bm_xform(C.bm_cyl(5, 0.010, 0.0, 0.05), loc=(0.02 * sx, 0, -self.L2 * s2),
                              rot=(0, 1.2 * sx, 0)), "gold", lo)
                self.legs_def.append({"name": name, "u": u, "l": lo, "hip": hip, "rest": rest, "sx": sx, "k": k,
                                      "phase": 0.0 if (k + (0 if sx > 0 else 1)) % 2 == 0 else math.pi})
        self.muzzle_ref = ("horn", (0, -0.16, 0.12))

    def place_legs(self, feet: dict, local: bool = False) -> None:
        bpy.context.view_layer.update()
        th = self.j["thorax"]
        inv = th.matrix_basis.inverted()
        for L in self.legs_def:
            T = feet[L["name"]] if local else inv @ feet[L["name"]]
            S = L["hip"]
            E, H = ik2(S, T, Vector((L["sx"] * 0.5, 0.0, 1.0)), self.L1, self.L2)
            L["u"].rotation_quaternion = DOWN.rotation_difference((E - S).normalized())
            L["l"].location = E
            L["l"].rotation_quaternion = DOWN.rotation_difference((H - E).normalized())

    def set_mand(self, a: float) -> None:
        self.mand["L"].rotation_euler = (0, 0, -a)
        self.mand["R"].rotation_euler = (0, 0, a)

    def rest(self) -> None:
        th = self.j["thorax"]
        th.location = (0, 0, self.BZ)
        th.rotation_euler = (0, 0, 0)
        self.j["head"].rotation_euler = (0, 0, 0)
        self.j["body"].location = (0, 0, 0)
        self.set_mand(0.0)

    def feet_rest(self) -> dict:
        return {L["name"]: Vector(L["rest"]) for L in self.legs_def}

    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        t = 2 * math.pi * i / n
        th = self.j["thorax"]
        th.location.z = self.BZ - 0.012 * (1 + math.sin(t))
        th.rotation_euler = (0.02 * math.sin(t), 0, 0)
        self.j["head"].rotation_euler = (0.06 * math.sin(t + 1), 0, 0.08 * math.sin(t * 0.5))
        self.set_mand(0.25 * max(0.0, math.sin(t * 2)))
        self.place_legs(self.feet_rest())

    def pose_run(self, i: int, n: int) -> None:
        self.rest()
        p = 2 * math.pi * i / n
        th = self.j["thorax"]
        th.location.z = self.BZ - 0.02 + 0.02 * abs(math.sin(2 * p))
        th.rotation_euler = (0.06, 0, 0.04 * math.sin(p))
        self.set_mand(0.15)
        feet = {}
        for L in self.legs_def:
            u = p + L["phase"]
            feet[L["name"]] = Vector(L["rest"]) + Vector((0, 0.15 * math.cos(u), 0.10 * max(0.0, math.sin(u))))
        self.place_legs(feet)

    def pose_attack(self, i: int, n: int) -> None:
        # recule et baisse la tête, mandibles ouvertes (0-2), charge / pince (3), retour (4-5)
        self.rest()
        th = self.j["thorax"]
        back = (0.04, 0.09, 0.10, -0.24, -0.18, -0.05)[i]
        pitch = (0.05, 0.12, 0.14, -0.10, -0.06, 0.0)[i]
        th.location = (0, back, self.BZ - 0.03 * (i in (1, 2)))
        th.rotation_euler = (pitch, 0, 0)
        self.j["head"].rotation_euler = ((0.15, 0.30, 0.34, -0.25, -0.15, 0.0)[i], 0, 0)
        self.set_mand((0.3, 0.6, 0.7, -0.2, 0.0, 0.1)[i])
        feet = self.feet_rest()
        for L in self.legs_def:
            if i >= 3 and L["k"] == 0:
                feet[L["name"]] = feet[L["name"]] + Vector((0, -0.16, 0.0))
        self.place_legs(feet)

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        k = (1.0, 0.6, 0.25)[i]
        th = self.j["thorax"]
        th.location = (0, 0.06 * k, self.BZ - 0.04 * k)
        th.rotation_euler = (0.16 * k, 0.08 * k, 0.1 * k)
        self.set_mand(0.5 * k)
        self.place_legs(self.feet_rest())

    def pose_death(self, i: int, n: int) -> None:
        # bascule sur le dos, pattes repliées vers le ciel
        self.rest()
        t = i / (n - 1)
        e = smooth(t / 0.75)
        th = self.j["thorax"]
        th.rotation_euler = (0, math.pi * e, 0.25 * e)
        th.location = (0.10 * math.sin(e * math.pi), 0, self.BZ + 0.18 * math.sin(e * math.pi) - 0.06 * e)
        self.set_mand(0.4 * e)
        bpy.context.view_layer.update()
        if e < 0.5:
            self.place_legs(self.feet_rest())
        else:
            feet = {}
            w = (e - 0.5) * 2.0
            for L in self.legs_def:
                r = Vector(L["rest"])
                curl = Vector((r.x * 0.45, r.y * 0.5 + 0.03 * L["k"], -0.10 - 0.05 * (L["k"] % 2)))
                base = th.matrix_basis.inverted() @ r
                feet[L["name"]] = base.lerp(curl, w)
            self.place_legs(feet, local=True)


# =============================================================================== lézard des sables
class Lizard(Rig):
    """Lézard : corps + queue en un seul tube refait à chaque pose le long d'une colonne souple,
    tête articulée (mâchoire), collerette rouge, épines dorsales, 4 pattes écartées en IK."""
    NSP = 16
    L1, L2 = 0.17, 0.17

    def build(self) -> None:
        S = self.S
        j = self.j
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["body"] = body = joint("body", root, (0, 0, 0))
        body.scale = (S["scale"],) * 3
        j["rig"] = rg = joint("rig", body, (0, 0, 0))
        self.trunk = self.part("trunk", C.bm_sphere(8, 6, 0.1), "scales", rg)
        self.second_mat(self.trunk, "mark")
        self.belly = self.part("bellyStrip", C.bm_sphere(8, 6, 0.1), "belly", rg)
        hd = j["head"] = qjoint("head", rg, (0, 0, 0))
        hd.scale = (1.85, 1.85, 1.85)
        sk = C.bm_sphere(14, 10, 1.0)
        for v in sk.verts:   # crâne anguleux : large aux tempes, plat dessus
            v.co.x *= 1.0 + 0.30 * max(0.0, v.co.y)
            v.co.z = min(v.co.z, 0.75)
        self.part("skullL", C.bm_xform(sk, loc=(0, -0.08, 0.03), scale=(0.12, 0.14, 0.085)), "scales", hd)
        self.part("snoutL", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.20, 0.02), scale=(0.085, 0.11, 0.055)),
                  "scales", hd)
        self.part("crest", C.bm_tube([(0, -0.24, 0.07), (0, -0.14, 0.11), (0, -0.04, 0.12), (0, 0.04, 0.10)],
                                     [0.012, 0.022, 0.026, 0.012], seg=6, flat=0.6, up=(1, 0, 0)), "mark", hd)
        for sx in (1, -1):
            self.part("jawMuscle", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0.10 * sx, -0.04, 0.0), scale=(0.05, 0.07, 0.06)),
                      "scales", hd)
        jw = j["jaw"] = joint("jaw", hd, (0, -0.02, -0.03))
        self.part("jawL", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.13, -0.025), scale=(0.075, 0.145, 0.045)), "scales", jw)
        self.part("mouthIn", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0, -0.12, 0.004), scale=(0.058, 0.12, 0.02)),
                  "mouth", jw, nofs=True)
        for k in range(4):
            for sx in (1, -1):
                self.part("toothL", C.bm_xform(C.bm_cyl(4, 0.008, 0.0, 0.03), loc=(0.045 * sx, -0.08 - 0.05 * k, 0.02),
                          rot=(math.pi, 0, 0)), "spike", jw)
        for sx in (1, -1):
            self.part("eyeL", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.085 * sx, -0.12, 0.075), scale=(0.016, 0.02, 0.014)),
                      "eye_glow", hd, nofs=True)
            self.part("brow", C.bm_tube([(0.05 * sx, -0.17, 0.07), (0.085 * sx, -0.11, 0.105), (0.10 * sx, -0.03, 0.11)],
                                        [0.018, 0.026, 0.012], seg=6), "mark", hd)
            self.part("browSpike", C.bm_xform(C.bm_cyl(5, 0.020, 0.0, 0.08), loc=(0.10 * sx, -0.02, 0.12),
                      rot=(-1.1, 0.5 * sx, 0)), "spike", hd)
            self.part("cheekSpike", C.bm_xform(C.bm_cyl(5, 0.018, 0.0, 0.07), loc=(0.11 * sx, -0.04, 0.0),
                      rot=(-1.4, 1.0 * sx, 0)), "spike", hd)
            self.part("nostril", C.bm_xform(C.bm_sphere(6, 4, 1.0), loc=(0.03 * sx, -0.30, 0.055), scale=(0.012, 0.01, 0.008)),
                      "socket", hd, nofs=True)
            for k in range(4):
                self.part("toothU", C.bm_xform(C.bm_cyl(4, 0.009, 0.0, 0.032), loc=(0.055 * sx, -0.12 - 0.045 * k, -0.025),
                          rot=(math.pi, 0, 0)), "spike", hd)
            # couronne d'épines pointées vers l'arrière (planche)
            for k in range(4):
                a = 0.25 + 0.35 * k
                base = Vector((0.05 * sx * math.cos(a * 0.5), -0.02 + 0.03 * k, 0.07))
                tip = base + Vector((0.11 * sx * math.cos(a), 0.12 + 0.03 * k, 0.13 + 0.06 * math.sin(a)))
                self.part("frill", C.bm_tube([tuple(base), tuple(base.lerp(tip, 0.5)), tuple(tip)], [0.028, 0.018, 0.0],
                                             seg=6), "frill", hd)
        # épines dorsales (placées à chaque pose)
        self.spikes = []
        for k in range(7):
            sj = qjoint("spk%d" % k, rg, (0, 0, 0))
            h = 0.14 - 0.012 * k
            self.part("spike%d" % k, C.bm_xform(C.bm_cyl(6, 0.034, 0.0, h), loc=(0, 0.02, h * 0.45), rot=(0.45, 0, 0)),
                      "spike", sj)
            self.spikes.append(sj)
        # pattes
        self.legs_def = []
        for side, sx in (("L", 1), ("R", -1)):
            for k, uu in enumerate((0.20, 0.46)):
                name = "%s%d" % (side, k)
                u = qjoint("leg_u" + name, rg, (0, 0, 0))
                lo = qjoint("leg_l" + name, rg, (0, 0, 0))
                self.part("haunch" + name, C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, 0, -0.03), scale=(0.11, 0.11, 0.10)),
                          "scales", u)
                self.part("thighL" + name, C.bm_tube([(0, 0, 0), (0, 0, -self.L1 * 0.5), (0, 0, -self.L1)],
                                                     [0.100, 0.085, 0.062], seg=8), "scales", u)
                self.part("shinL" + name, C.bm_tube([(0, 0, 0), (0, 0, -self.L2)], [0.064, 0.046], seg=8), "scales", lo)
                self.part("footL" + name, C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -0.03, -self.L2), scale=(0.07, 0.08, 0.026)),
                          "scales", lo)
                for t in (-1, 0, 1):
                    self.part("clawL" + name, C.bm_tube([(0.025 * t, -0.07, -self.L2), (0.035 * t, -0.11, -self.L2 - 0.012)],
                                                        [0.010, 0.0], seg=4), "spike", lo)
                self.legs_def.append({"name": name, "u": u, "l": lo, "uu": uu, "sx": sx, "k": k})
        self.muzzle_ref = ("snoutL", (0, -0.28, 0.0))
        self.prm = {}

    # -- colonne ------------------------------------------------------------
    @staticmethod
    def radius(u: float) -> float:
        pts = ((0.0, 0.15), (0.08, 0.215), (0.18, 0.26), (0.30, 0.26), (0.42, 0.205), (0.54, 0.135),
               (0.75, 0.065), (1.0, 0.0))
        for (a, ra), (b, rb) in zip(pts, pts[1:]):
            if u <= b:
                return ra + (rb - ra) * (u - a) / (b - a)
        return 0.0

    def spine(self, u: float) -> Vector:
        P = self.prm
        y = -0.40 + 1.40 * u + P.get("shift", 0.0)
        z = 0.30 - 0.24 * smooth((u - 0.38) / 0.62) + 0.06 * max(0.0, 0.3 - u) / 0.3 \
            + P.get("lift", 0.0) * max(0.0, 0.25 - u) * 4.0
        w = 0.3 + 1.2 * u
        x = P.get("amp", 0.0) * math.sin(P.get("ph", 0.0) - 6.0 * u) * w + P.get("curl", 0.0) * u * u
        return Vector((x, y, z))

    def build_pose(self) -> None:
        N = self.NSP
        us = [k / (N - 1) for k in range(N)]
        pts = [self.spine(u) for u in us]
        rad = [self.radius(u) for u in us]
        roll = self.prm.get("roll", 0.0)
        # taches rouge brique sur les flancs (planche) : anneaux 3 à 8, faces latérales
        mark = lambda fi: 1 if fi < (N - 1) * 12 and 1 <= fi // 12 <= 12 and (fi // 12) % 2 == 0 \
            and (fi % 12) < 7 else 0
        remesh(self.trunk, C.bm_tube([tuple(p) for p in pts], rad, seg=12, flat=0.78), mark)
        remesh(self.belly, C.bm_tube([tuple(p - Vector((0, 0, r * 0.45))) for p, r in zip(pts, rad)],
                                     [r * 0.78 for r in rad], seg=10, flat=0.5))
        hd = self.j["head"]
        p0, p1 = self.spine(0.0), self.spine(0.04)
        fwd = (p0 - p1).normalized()
        hd.location = p0 + fwd * 0.02
        q = Vector((0, -1, 0)).rotation_difference(fwd)
        hd.rotation_quaternion = q @ Euler((self.prm.get("pitch", 0.0), 0, self.prm.get("yaw", 0.0))).to_quaternion()
        self.j["jaw"].rotation_euler = (self.prm.get("jaw", 0.0), 0, 0)
        for k, sj in enumerate(self.spikes):
            u = 0.06 + 0.075 * k
            p, pn = self.spine(u), self.spine(u + 0.02)
            sj.location = p + Vector((0, 0, self.radius(u) * 0.74))
            sj.rotation_quaternion = Vector((0, -1, 0)).rotation_difference((p - pn).normalized())
        self.j["rig"].rotation_euler = (0, roll, 0)

    def place_legs(self, offs: dict) -> None:
        """offs : nom → (avance y, levée z) du pied par rapport à sa position de repos."""
        for L in self.legs_def:
            p = self.spine(L["uu"])
            S = p + Vector((L["sx"] * self.radius(L["uu"]) * 0.8, 0, -0.03))
            dy, dz = offs.get(L["name"], (0.0, 0.0))
            splay = self.prm.get("splay", 1.0)
            T = Vector((p.x + L["sx"] * 0.33 * splay, p.y + dy + (-0.05 if L["k"] == 0 else 0.07), dz))
            E, H = ik2(S, T, Vector((L["sx"] * 1.0, 0, 0.9)), self.L1, self.L2)
            L["u"].location = S
            L["u"].rotation_quaternion = DOWN.rotation_difference((E - S).normalized())
            L["l"].location = E
            L["l"].rotation_quaternion = DOWN.rotation_difference((H - E).normalized())

    def pose(self, anim: str, i: int, n: int) -> None:
        self.prm = {}
        getattr(self, "pose_" + anim)(i, n)
        self.build_pose()

    def pose_idle(self, i: int, n: int) -> None:
        t = 2 * math.pi * i / n
        # avant-train dressé, tête haute, gueule ouverte (planche)
        self.prm.update(amp=0.025, ph=t * 0.5, lift=0.16 + 0.02 * math.sin(t), jaw=0.30 + 0.06 * math.sin(t),
                        pitch=-0.22, yaw=0.12 * math.sin(t * 0.5))
        self.place_legs({})

    def pose_run(self, i: int, n: int) -> None:
        p = 2 * math.pi * i / n
        self.prm.update(amp=0.06, ph=p, lift=0.02, jaw=0.1)
        offs = {}
        for L in self.legs_def:
            ph = p + (0.0 if (L["k"] + (0 if L["sx"] > 0 else 1)) % 2 == 0 else math.pi)
            offs[L["name"]] = (0.14 * math.cos(ph), 0.07 * max(0.0, math.sin(ph)))
        self.place_legs(offs)

    def pose_attack(self, i: int, n: int) -> None:
        # se ramasse, tête levée gueule ouverte (0-2), bondit et mord (3), retombe (4-5)
        self.prm.update(shift=(0.04, 0.08, 0.09, -0.20, -0.14, -0.04)[i],
                        lift=(0.05, 0.12, 0.14, -0.02, 0.0, 0.03)[i],
                        pitch=(-0.1, -0.35, -0.4, 0.25, 0.15, 0.0)[i], jaw=(0.2, 0.6, 0.7, 0.05, 0.2, 0.1)[i],
                        amp=0.04, ph=(0.0, 0.5, 0.6, 1.4, 1.6, 2.0)[i])
        dy = (0.0, 0.02, 0.03, -0.10, -0.08, -0.02)[i]
        self.place_legs({L["name"]: (dy if L["k"] == 0 else -dy * 0.5, 0.0) for L in self.legs_def})

    def pose_hit(self, i: int, n: int) -> None:
        k = (1.0, 0.6, 0.25)[i]
        self.prm.update(shift=0.06 * k, lift=0.06 * k, pitch=-0.3 * k, jaw=0.4 * k, curl=0.12 * k, amp=0.02)
        self.place_legs({})

    def pose_death(self, i: int, n: int) -> None:
        # roule sur le flanc, queue recourbée, pattes en l'air
        t = i / (n - 1)
        e = smooth(t / 0.7)
        self.prm.update(roll=1.75 * e, curl=0.35 * e, lift=0.05 * (1 - e), jaw=0.5 * e, pitch=-0.2 * e,
                        splay=1.0 - 0.3 * e)
        self.j["body"].location = (0, 0, 0.10 * math.sin(min(1.0, t * 1.5) * math.pi) * (1 - e) + 0.06 * e)
        self.place_legs({L["name"]: (0.0, 0.12 * e) for L in self.legs_def})

    def rest(self) -> None:
        self.j["body"].location = (0, 0, 0)


# =============================================================================== vipère des sables
class Viper(Rig):
    """Cobra géant : anneaux enroulés au sol, cou dressé, capuchon ocellé, tête à crochets.
    Le corps est un tube refait à chaque pose (chemin : queue → anneaux → cou → tête)."""
    NC, NR = 30, 16

    def build(self) -> None:
        S = self.S
        j = self.j
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["body"] = body = joint("body", root, (0, 0, 0))
        body.scale = (S["scale"],) * 3
        self.trunk = self.part("trunk", C.bm_sphere(8, 6, 0.1), "scales", body)
        self.second_mat(self.trunk, "band")
        self.bellyS = self.part("bellyStrip", C.bm_sphere(8, 6, 0.1), "belly", body)
        hood = j["hood"] = qjoint("hood", body, (0, 0, 0))
        hb = C.bm_sphere(18, 12, 1.0)
        for v in hb.verts:
            x, y, z = v.co
            v.co = Vector((x * 0.15 * (1.0 - 0.35 * max(0.0, z)), y * 0.075 + 0.03, z * 0.21 - 0.07))
        self.part("hoodM", hb, "scales", hood)
        hd = j["head"] = qjoint("head", body, (0, 0, 0))
        hd.scale = (1.65, 1.65, 1.65)
        sk = C.bm_sphere(14, 10, 1.0)
        for v in sk.verts:   # tête triangulaire : large aux joues, effilée au museau
            v.co.x *= 1.0 + 0.45 * max(0.0, v.co.y)
        self.part("skullV", C.bm_xform(sk, loc=(0, -0.07, 0.02), scale=(0.085, 0.12, 0.055)), "scales", hd)
        self.part("mouthUp", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0, -0.10, -0.018), scale=(0.055, 0.095, 0.012)),
                  "mouth", hd, nofs=True)
        self.part("snoutV", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, -0.16, 0.012), scale=(0.055, 0.06, 0.04)),
                  "scales", hd)
        jw = j["jaw"] = joint("jaw", hd, (0, -0.0, -0.02))
        self.part("jawV", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.10, -0.01), scale=(0.065, 0.11, 0.022)), "belly", jw)
        self.part("mouthV", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0, -0.10, 0.008), scale=(0.05, 0.09, 0.01)),
                  "mouth", jw, nofs=True)
        for sx in (1, -1):
            self.part("fang", C.bm_xform(C.bm_cyl(5, 0.014, 0.0, 0.07), loc=(0.032 * sx, -0.16, -0.04), rot=(math.pi - 0.2, 0, 0)),
                      "tooth", hd)
            self.part("eyeV", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.062 * sx, -0.10, 0.05), scale=(0.022, 0.026, 0.018)),
                      "eye_glow", hd, nofs=True)
            self.part("browV", C.bm_xform(C.bm_tube([(0.035 * sx, -0.14, 0.05), (0.06 * sx, -0.10, 0.068), (0.07 * sx, -0.05, 0.062)],
                                                    [0.008, 0.016, 0.010], seg=6), ), "band", hd)
        self.tongue = self.part("tongue", C.bm_tube([(0, -0.18, 0.0), (0, -0.26, -0.01), (0.02, -0.30, -0.01)],
                                                    [0.008, 0.007, 0.0], seg=4), "tongue", jw, grp="tongue")
        self.part("tongue2", C.bm_tube([(0, -0.26, -0.01), (-0.02, -0.30, -0.01)], [0.007, 0.0], seg=4), "tongue", jw,
                  grp="tongue")
        self.muzzle_ref = ("snoutV", (0, -0.21, 0.0))
        self.prm = {}

    def path(self) -> tuple:
        """Points et rayons du corps (queue → tête)."""
        P = self.prm
        pts, rad = [], []
        lay = P.get("lay", 0.0)     # 0 = anneaux, 1 = allongé (course)
        ph = P.get("ph", 0.0)
        NC = self.NC
        for k in range(NC):
            u = k / (NC - 1)
            a = -math.pi / 2 + 2 * math.pi * 1.45 * (1 - u)
            r = 0.05 + 0.25 * u
            coil = Vector((r * math.cos(a), 0.10 + r * math.sin(a), 0.075))
            slither = Vector((0.11 * math.sin(ph + 7.0 * (1 - u)) * (1 - u * 0.5), 0.95 - 1.10 * u, 0.065))
            pts.append(coil.lerp(slither, lay) + Vector((P.get("sway", 0.0) * u * 0.3, 0, 0)))
            rad.append(0.02 + 0.085 * min(1.0, u * 1.8) ** 0.7)
        # cou dressé : de la sortie des anneaux à la tête
        base = pts[-1]
        top = Vector(P.get("top", (0.0, -0.06, 0.70)))
        top.x += P.get("sway", 0.0)
        sk = P.get("s_curve", 1.0)
        c1 = base + Vector((0.20 * sk, -0.24, 0.22))
        c2 = Vector((top.x * 0.5 - 0.20 * sk, top.y + 0.34, top.z * 0.78))
        fall = P.get("fall", 0.0)
        for k in range(1, self.NR + 1):
            u = k / self.NR
            pt = Vector(C.bezier(base, c1, c2, top, self.NR + 1)[k])
            flat = Vector((base.x + 0.25 * math.sin(u * 2.5) * fall, base.y - 0.55 * u, 0.07))
            pts.append(pt.lerp(flat, fall))
            rad.append(0.12 - 0.032 * u)
        return pts, rad

    def build_pose(self) -> None:
        pts, rad = self.path()
        nring = len(pts) - 1
        # bandes sombres en travers du dos (2 anneaux sur 5), le ventre reste clair
        band = lambda fi: 1 if fi < nring * 12 and (fi // 12) % 4 == 0 and (fi % 12) < 7 else 0
        remesh(self.trunk, C.bm_tube([tuple(p) for p in pts], rad, seg=12, flat=0.92), band)
        nc = self.NC
        # ventre : sous les anneaux, devant le cou dressé (écailles ventrales crème face au joueur)
        bel = []
        for k, (p, r) in enumerate(zip(pts, rad)):
            w = smooth((k - nc + 2) / 5.0)
            bel.append(p + Vector((0, 0, -r * 0.35)).lerp(Vector((0, -r * 0.50, -r * 0.05)), w))
        remesh(self.bellyS, C.bm_tube([tuple(p) for p in bel], [r * 0.8 for r in rad], seg=10, flat=0.6))
        top, prev = pts[-1], pts[-3]
        fwd = Vector(self.prm.get("look", (0, -1, -0.25))).normalized()
        q = Vector((0, -1, 0)).rotation_difference(fwd)
        hd = self.j["head"]
        hd.location = top + fwd * 0.03
        hd.rotation_quaternion = q @ Euler((0, self.prm.get("tilt", 0.0), 0)).to_quaternion()
        self.j["jaw"].rotation_euler = (self.prm.get("jaw", 0.0), 0, 0)
        hood = self.j["hood"]
        neck = pts[-4]
        up = (top - pts[-6]).normalized()
        hood.location = neck + Vector((0, 0.02, 0))
        hood.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(up) @ Euler((0, 0, 0)).to_quaternion()
        hood.scale = (self.prm.get("hood", 1.0),) * 3
        self.show("tongue", self.prm.get("tongue", False))

    def pose(self, anim: str, i: int, n: int) -> None:
        self.prm = {}
        getattr(self, "pose_" + anim)(i, n)
        self.build_pose()

    def pose_idle(self, i: int, n: int) -> None:
        t = 2 * math.pi * i / n
        # dressé haut, gueule entrouverte rougeoyante, prêt à frapper (planche)
        self.prm.update(sway=0.05 * math.sin(t), top=(0.0, -0.04, 0.86 + 0.02 * math.sin(t * 2)),
                        jaw=0.55 + 0.08 * math.sin(t), tongue=False, look=(0.0, -1, -0.05))

    def pose_run(self, i: int, n: int) -> None:
        p = 2 * math.pi * i / n
        self.prm.update(lay=1.0, ph=p, top=(0.04 * math.sin(p), -0.38, 0.40), look=(0, -1, -0.35), hood=0.85,
                        tongue=i % 4 == 0)

    def pose_attack(self, i: int, n: int) -> None:
        # se rétracte, gueule béante (0-2), frappe en avant, crochets sortis (3), revient (4-5)
        tops = [(0.0, 0.0, 0.72), (0.0, 0.08, 0.78), (0.0, 0.10, 0.80), (0.0, -0.50, 0.32), (0.0, -0.40, 0.40),
                (0.0, -0.14, 0.62)]
        looks = [(0, -1, -0.2), (0, -1, -0.1), (0, -1, -0.05), (0, -1, -0.55), (0, -1, -0.45), (0, -1, -0.3)]
        self.prm.update(top=tops[i], look=looks[i], jaw=(0.3, 0.7, 0.8, 0.9, 0.4, 0.1)[i],
                        hood=(1.05, 1.15, 1.18, 1.1, 1.05, 1.0)[i])

    def pose_hit(self, i: int, n: int) -> None:
        k = (1.0, 0.6, 0.25)[i]
        self.prm.update(top=(0.06 * k, 0.06 + 0.06 * k, 0.66 - 0.06 * k), look=(0.2 * k, -1, 0.1 * k), jaw=0.4 * k,
                        sway=0.06 * k)

    def pose_death(self, i: int, n: int) -> None:
        t = i / (n - 1)
        e = smooth(t / 0.7)
        self.prm.update(fall=e, top=(0.0, -0.06, 0.70), look=(0.3 * e, -1, -0.3 + 0.2 * e), jaw=0.6 * e,
                        tilt=1.3 * e, hood=1.0 - 0.2 * e)

    def rest(self) -> None:
        pass


CLASSES = {
    "eg_skeleton": Skeleton, "eg_scarab": Scarab, "eg_lizard": Lizard, "eg_archer": Archer, "eg_mummy": Mummy,
    "eg_viper": Viper, "eg_shadow_warrior": Jackal, "eg_sun_priest": Priest, "eg_pharaoh": Pharaoh,
}


# =============================================================================== rendu
def anims_for(kind: str) -> dict:
    a = dict(ANIMS_BASE)
    r = SPEC[kind].get("fps_run")
    if r:
        a["run"] = (8, r, True)
    a.update(SPEC[kind].get("anims", {}))
    return a


def setup_scene(kind: str, elev: float = ELEV):
    C.reset_scene()
    F = frame_of(kind)
    C.setup_render((F * SS, F * SS), samples=4, outline_px=4.6)
    rig = CLASSES[kind](kind)
    ortho = 2.30 * F / 160.0
    tz = CAM_TARGET_Z * F / BASE_FRAME + SPEC[kind].get("cam_dz", 0.0)
    cam = C.ortho_camera(elev, ortho, target=(0, 0, tz))
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


def preview(kinds, dirs, anims_spec, elev: float = ELEV) -> None:
    from PIL import Image
    for kind in kinds:
        rig, cam = setup_scene(kind, elev)
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
        out = os.path.join(TMP_DIR, "prev_%s%s.png" % (kind, "" if elev == ELEV else "_e%d" % elev))
        sheet.save(out)
        print("PREVIEW", out)


def presentation_sheet(kinds) -> None:
    """Planche de présentation (captures de PR) : idle 3/4 face + attaque + cadavre, à l'échelle du jeu,
    sur fond nuit violet, depuis les images déjà rendues (TMP_DIR)."""
    from PIL import Image, ImageDraw, ImageFont
    def font(*cands):
        return next((c for c in cands if os.path.exists(c)), cands[0])
    fb = font("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/System/Library/Fonts/Supplemental/Arial Bold.ttf")
    fr = font("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf")
    title_f = ImageFont.truetype(fb, 30)
    name_f = ImageFont.truetype(fb, 17)
    sub_f = ImageFont.truetype(fr, 13)
    cols = 3
    cell_w, cell_h = 440, 330
    rows = (len(kinds) + cols - 1) // cols
    W, H = cols * cell_w + 40, rows * cell_h + 90
    sheet = Image.new("RGBA", (W, H), (34, 22, 16, 255))
    dr = ImageDraw.Draw(sheet)
    for y in range(H):
        c = y / H
        dr.line([(0, y), (W, y)], fill=(int(70 - 40 * c), int(42 - 24 * c), int(30 - 12 * c), 255))
    dr.text((24, 20), "LES PYRAMIDES D'ÉGYPTE — Le royaume des morts", font=title_f, fill=(255, 196, 90, 255))
    tags = {"eg_shadow_warrior": "ÉLITE", "eg_sun_priest": "ÉLITE", "eg_pharaoh": "BOSS"}
    for idx, kind in enumerate(kinds):
        cx = 20 + (idx % cols) * cell_w
        cy = 80 + (idx // cols) * cell_h
        dr.rounded_rectangle([cx, cy, cx + cell_w - 12, cy + cell_h - 12], 14, fill=(26, 20, 22, 235),
                             outline=(214, 160, 70, 255), width=2)
        tmp = os.path.join(TMP_DIR, kind)
        F = out_frame(kind)
        n_death = anims_for(kind)["death"][0]
        shots = [("idle_se_0", "idle"), ("attack_sw_3", "attaque"), ("death_s_%d" % (n_death - 1), "cadavre")]
        if F > 256:
            # boss : idle + attaque à l'échelle réelle du jeu, à côté d'un squelette rôdeur (même facteur)
            kr = (cell_h - 70) / float(frame_of(kind))
            x = cx + 6
            sk = os.path.join(TMP_DIR, "eg_skeleton", "idle_se_0.png")
            if os.path.exists(sk):
                im = Image.open(sk).convert("RGBA")
                n = int(BASE_FRAME * kr)
                im = im.resize((n, n), Image.LANCZOS)
                sheet.alpha_composite(im, (x, cy + cell_h - 46 - n + int(n * 0.12)))
                dr.text((x + 2, cy + cell_h - 40), "squelette (échelle)", font=sub_f, fill=(190, 190, 210, 255))
                x += n - 10
            for fname, label in shots[:2]:
                path = os.path.join(tmp, fname + ".png")
                if not os.path.exists(path):
                    continue
                im = Image.open(path).convert("RGBA")
                n = int(frame_of(kind) * kr)
                im = im.resize((n, n), Image.LANCZOS)
                sheet.alpha_composite(im, (x - 30, cy + 40))
                dr.text((x + n // 2 - 40, cy + cell_h - 40), label, font=sub_f, fill=(190, 190, 210, 255))
                x += n - 90
            shots = []
        w = (cell_w - 32) // max(len(shots), 1)
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
    out = os.path.join(CAPT_DIR, "planche_modeles_egypt.png")
    sheet.convert("RGB").save(out)
    print("SHEET", out)


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
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
        elev = float(args[args.index("--elev") + 1]) if "--elev" in args else ELEV
        preview(kinds, dirs, anims, elev)
        return
    for k in kinds:
        build_kind(k)


if __name__ == "__main__":
    main()
