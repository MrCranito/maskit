"""Soldat d'Exfil Rush (planche docs/reference/personnages_skins.jpg) : modélisation 3D scriptée,
rendus 8 directions, 9 skins.

Usage (depuis la racine du projet) :
    python3 art/blender/build_hero.py                          # tout : 9 skins, planches, .tres, meta
    python3 art/blender/build_hero.py --skins default,gign     # seulement certains skins
    python3 art/blender/build_hero.py --preview s,e --anim idle:0,run:3 [--skins cyber]
    python3 art/blender/build_hero.py --shop [--skins ...]     # seulement les aperçus boutique
    python3 art/blender/build_hero.py --compact                # recompresse les planches existantes
    python3 art/blender/build_hero.py --blend                  # sauve seulement art/blender/hero.blend

Personnage chibi militaire : très gros casque tactique (rails, casque audio, lunettes), cagoule,
gilet porte-plaques avec poches, genouillères, rangers, gants ; mains jointes devant (prise à deux
mains : l'arme est dessinée par le jeu au point « main »). Pièces rigides parentées à des
articulations (empties), jambes en cinématique directe, bras en IK à deux segments.
Un seul jeu de poses : chaque pose est rendue une fois par skin (échange de matériaux et
d'accessoires). Le personnage regarde -Y ; caméra orthographique depuis -Y, plongée ELEV degrés.
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
from mathutils import Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DEFAULT = os.path.join(ROOT, "assets", "sprites", "hero3d")
OUT_SKINS = os.path.join(OUT_DEFAULT, "skins")
TMP_DIR = os.environ.get("RDM_TMP", "/tmp/rdm_hero_frames")

FRAME_W, FRAME_H = 128, 160   # cadre final (px)
SHOP_W, SHOP_H = 256, 320     # aperçu boutique (preview.png), de face
SS = 2                        # sur-échantillonnage du rendu
ELEV = 48.0                   # plongée caméra (degrés)
ORTHO_H = 2.30                # hauteur visible (unités Blender) du cadre
CAM_TARGET_Z = 1.10
HEAD_SCALE = 1.56
HEAD_PITCH = -0.20            # tête relevée vers la caméra (visage lisible en plongée)
LEG = 0.74                    # facteur de longueur des jambes (silhouette trapue)
PZ = 0.80 - 0.77 * (1 - LEG)  # hauteur du bassin au repos (pieds au sol)
HERO_WORLD_HEIGHT = 64.0      # hauteur visible du héros en unités monde

# Animations : nombre d'images, fps, boucle.
ANIMS = {
    "idle": (8, 8, True),
    "run": (12, 18, True),
    "backpedal": (10, 14, True),
    "strafe_l": (10, 15, True),
    "strafe_r": (10, 15, True),
    "hit": (3, 12, False),
}
# Directions : angle de rotation du personnage autour de Z (0 = face caméra = "s").
DIRS = {"e": 90.0, "se": 45.0, "s": 0.0, "sw": -45.0, "w": -90.0, "nw": -135.0, "n": 180.0, "ne": 135.0}

# Bras (IK) : longueurs des segments, épaules (repère de la colonne).
L_UP, L_LOW = 0.20, 0.225
SHOULDER = {"L": Vector((0.245, 0.0, 0.33)), "R": Vector((-0.245, 0.0, 0.33))}
# Mains au repos (prise à deux mains, devant le ventre, côté droit) — repère colonne.
HAND_R = Vector((-0.06, -0.33, 0.17))
HAND_L = Vector((0.04, -0.30, 0.20))

# ----------------------------------------------------------------------------- matériaux / skins
# Spécification d'un matériau : (base, ombre, lumière) en hex (None = calculée),
# "!#hex" = émissif (néon, lentilles), ("pat", [couleurs], échelle) = motif (camouflage, éclats).
MULTICAM = ("pat", [("#8e7c5a", "#3a3030", "#b8a47a"), ("#655438", "#262026", "#867050"),
                    ("#76784e", "#2a2c2c", "#9a9c6e")], 7.0)
BASE_MATS = {
    "helmet": ("#2a2c33", "#0b0c18", "#4c4e5a"),
    "helmet_acc": ("#3c3a36", "#121220", "#625e56"),
    "headset": ("#5e5a46", "#1e1c1e", "#8a8464"),
    "goggles": ("#1c1c20", "#08080e", "#3a3a42"),
    "lens": ("#d89a34", "#5a2c18", "#ffe6a0"),
    "mask": ("#24252c", "#0a0a14", "#42434c"),
    "bone": ("#e2ded2", "#86869e", "#ffffff"),
    "socket": ("#121216", None, None),
    "uniform": MULTICAM,
    "vest": ("#2a2c30", "#0c0c16", "#484a50"),
    "pouch": ("#33353a", "#101018", "#53555c"),
    "strap": ("#1c1d22", "#08080e", "#35363e"),
    "pad": ("#222328", "#09090f", "#404148"),
    "forearm": ("#c69872", "#78505e", "#ecc29a"),
    "glove": ("#1d1d22", "#08080e", "#3a3a42"),
    "boot": ("#7a6044", "#2c1e26", "#a4825c"),
    "sole": ("#222226", "#0a0a12", "#3a3a40"),
    "belt": ("#2a2a2e", "#0c0c16", "#46464c"),
    "patch": ("#b8302a", "#4a1024", "#e05040"),
    "text": ("#f2f2f2", "#9a9ab0", "#ffffff"),
    "flag_b": ("#2a46b0", None, None),
    "flag_w": ("#f0f0f0", None, None),
    "flag_r": ("#d02a2a", None, None),
    "gold": ("#d8a840", "#6a4430", "#ffe490"),
    "red": ("#a82226", "#3e0c1c", "#da4a3a"),
    "shemagh": ("#d4c6a4", "#7a7088", "#f4e8c8"),
    "ghillie": ("pat", [("#4e6a2a", "#18241a", "#7a9a3a"), ("#33461e", "#0e1814", "#56702c"),
                        ("#6e7a34", "#222a1c", "#9aa84a")], 14.0),
    "glow": "!#38f0ff",
    "glow2": "!#c040ff",
}
# Accessoires optionnels (visibles seulement si listés par le skin).
OPTIONAL = {"helmet", "goggles", "headset", "skull", "gign", "flag", "patch", "ghillie", "samurai",
            "cyber", "scorpion", "shemagh", "hood"}

SKINS = {
    "default": {
        "name": "Soldat standard", "rarity": 0, "price": 0,
        "desc": "Un équipement polyvalent pour toutes les situations. Idéal pour commencer l'aventure.",
        "mats": {},
        "acc": {"helmet", "goggles", "headset", "patch"},
        "colors": ("#2a2c33", "#8e7c5a", "#c48a2c"),
    },
    "gign": {
        "name": "GIGN", "rarity": 2, "price": 250,
        "desc": "Unité d'élite de la gendarmerie : tenue bleu nuit intégrale et gilet marqué GIGN.",
        "mats": {
            "helmet": ("#1e2a48", "#080c1e", "#3e5488"),
            "helmet_acc": ("#20242e", "#080a14", "#3a404e"),
            "headset": ("#1c1e26", "#08080e", "#363a46"),
            "lens": ("#22324a", "#0a0e1e", "#5a7aa0"),
            "mask": ("#181a22", "#06060e", "#30323c"),
            "uniform": ("#1c2234", "#080a18", "#36405c"),
            "vest": ("#161a26", "#06080e", "#2c3244"),
            "pouch": ("#1c2030", "#080a14", "#343a50"),
            "pad": ("#14161e", "#06060c", "#2c2e38"),
            "forearm": ("#1c2234", "#080a18", "#36405c"),
            "boot": ("#16161c", "#06060c", "#2e2e36"),
            "belt": ("#14161e", "#06060c", "#2c2e38"),
        },
        "acc": {"helmet", "goggles", "headset", "gign", "flag"},
        "colors": ("#1e2a48", "#161a26", "#f2f2f2"),
    },
    "fantome": {
        "name": "Fantôme", "rarity": 2, "price": 250,
        "desc": "Cagoule tête de mort et casque audio : une silhouette qu'on ne voit qu'une fois.",
        "mats": {
            "headset": ("#1c1d22", "#08080e", "#383a42"),
            "mask": ("#1a1b20", "#06060c", "#33343c"),
            "uniform": ("#1e1f24", "#08080e", "#3a3b42"),
            "vest": ("#17181c", "#06060a", "#2e2f36"),
            "pouch": ("#202126", "#08080e", "#3c3d44"),
            "forearm": ("#1e1f24", "#08080e", "#3a3b42"),
            "boot": ("#18181c", "#06060a", "#303036"),
            "patch": ("#5a5c64", "#1c1e28", "#8a8c96"),
        },
        "acc": {"hood", "headset", "skull", "patch"},
        "colors": ("#1e1f24", "#e2ded2", "#5a5c64"),
    },
    "sas": {
        "name": "SAS", "rarity": 3, "price": 500,
        "desc": "Casque sable, cagoule à mâchoire de crâne et camouflage désert des forces spéciales.",
        "mats": {
            "helmet": ("#9e8a62", "#3e3230", "#c8b282"),
            "helmet_acc": ("#3a3630", "#121218", "#5c564c"),
            "headset": ("#4a4a3a", "#18181a", "#6e6e56"),
            "bone": ("#b8b4aa", "#5e5e72", "#dedad0"),
            "mask": ("#4a4844", "#18181e", "#6c6a64"),
            "uniform": ("pat", [("#a8946c", "#463a36", "#d0bc8c"), ("#7e6a48", "#30282a", "#a28a62"),
                                ("#c4b48c", "#5a5050", "#e8d8ac")], 7.0),
            "forearm": ("#a8946c", "#463a36", "#d0bc8c"),
            "boot": ("#8a7050", "#33262a", "#b09068"),
        },
        "acc": {"helmet", "headset", "skull", "patch"},
        "colors": ("#9e8a62", "#2a2c30", "#b8b4aa"),
    },
    "desert": {
        "name": "Desert", "rarity": 3, "price": 500,
        "desc": "Casque sable, lunettes bleutées et chèche : taillé pour les tempêtes de sable.",
        "mats": {
            "helmet": ("#c8b48a", "#5e5046", "#ecdcb2"),
            "helmet_acc": ("#7a6a50", "#2c2428", "#a08c6a"),
            "headset": ("#8e7c5a", "#3a3030", "#b8a47a"),
            "lens": ("#3a78c0", "#14244a", "#8ac4f0"),
            "uniform": ("pat", [("#c8b48c", "#5e5048", "#ecdcb0"), ("#a89070", "#463a36", "#ccb48e"),
                                ("#d8c8a4", "#6a6060", "#f8ecc8")], 6.0),
            "vest": ("#a8946e", "#463a36", "#ccb68c"),
            "pouch": ("#9a8664", "#3e3434", "#bea67e"),
            "forearm": ("#c8b48c", "#5e5048", "#ecdcb0"),
            "pad": ("#8a7a5c", "#342a2a", "#ae9a74"),
            "boot": ("#a88c64", "#463630", "#ceae80"),
        },
        "acc": {"helmet", "goggles", "headset", "shemagh", "patch"},
        "colors": ("#c8b48a", "#a8946e", "#3a78c0"),
    },
    "forest": {
        "name": "Forest", "rarity": 3, "price": 500,
        "desc": "Tenue ghillie touffue : on ne voit qu'un buisson… armé.",
        "mats": {
            "uniform": ("pat", [("#4a5a2c", "#16201a", "#6e8240"), ("#2e3a1e", "#0c1410", "#4a5a2e"),
                                ("#6a6a3a", "#22241e", "#8e8e50")], 9.0),
            "forearm": ("#3a4a24", "#121c14", "#5a6c36"),
            "vest": ("#3a4424", "#121a14", "#566236"),
            "pouch": ("#46502c", "#161e16", "#646e3e"),
            "mask": ("#1e221a", "#080a0a", "#363c2e"),
            "lens": ("#1e2226", "#08080e", "#4a5664"),
            "glove": ("#2a3020", "#0c100c", "#444c34"),
            "pad": ("#2a3020", "#0c100c", "#444c34"),
            "boot": ("#3a3226", "#121010", "#5a4c3a"),
        },
        "acc": {"goggles", "ghillie"},
        "colors": ("#4e6a2a", "#33461e", "#6e7a34"),
    },
    "spetsnaz": {
        "name": "Spetsnaz", "rarity": 4, "price": 1000,
        "desc": "Armure de samouraï rouge laqué et casque à cornes dorées : la légende du front.",
        "mats": {
            "helmet": ("#9a1e22", "#360a18", "#d23e36"),
            "helmet_acc": ("#2a1a1c", "#0c0608", "#4a2e30"),
            "lens": ("#e0302a", "#4a0a14", "#ff8a6a"),
            "mask": ("#3a2a2a", "#120a0e", "#5a4444"),
            "bone": ("#3a2e2e", "#120a0e", "#5c4a4a"),
            "uniform": ("#8a1e22", "#300a16", "#b8382e"),
            "vest": ("#2a1c1e", "#0c0608", "#463032"),
            "pouch": ("#7a1a1e", "#2a0812", "#a43028"),
            "forearm": ("#8a1e22", "#300a16", "#b8382e"),
            "pad": ("#24181a", "#0a0606", "#40302e"),
            "boot": ("#1e1618", "#080406", "#3a2c2e"),
        },
        "acc": {"helmet", "goggles", "samurai"},
        "colors": ("#9a1e22", "#d8a840", "#2a1c1e"),
    },
    "cyber": {
        "name": "Cyber", "rarity": 4, "price": 1000,
        "desc": "Armure noire parcourue de néons violets et cyan, visière lumineuse.",
        "mats": {
            "helmet": ("#1a1828", "#08060e", "#34304a"),
            "helmet_acc": ("#22203a", "#0a0818", "#3c3858"),
            "headset": ("#1e1c30", "#08060e", "#38345a"),
            "mask": ("#141220", "#06040a", "#2a2840"),
            "uniform": ("#1c1a2a", "#08060e", "#36324c"),
            "vest": ("#161422", "#06040a", "#2e2a44"),
            "pouch": ("#201e32", "#08060e", "#3a3656"),
            "forearm": ("#1c1a2a", "#08060e", "#36324c"),
            "pad": ("#2a1e44", "#0c0818", "#4a3870"),
            "glove": ("#18161e", "#06040a", "#302c3a"),
            "boot": ("#18161e", "#06040a", "#302c3a"),
            "belt": ("#18161e", "#06040a", "#302c3a"),
        },
        "acc": {"helmet", "headset", "cyber"},
        "colors": ("#1a1828", "#c040ff", "#38f0ff"),
    },
    "scorpion": {
        "name": "Scorpion", "rarity": 4, "price": 1000,
        "desc": "Noir et or : masque doré, plaques gravées. Le dard frappe toujours en dernier.",
        "mats": {
            "helmet": ("#1a1a1e", "#06060a", "#36363e"),
            "helmet_acc": ("#d8a840", "#6a4430", "#ffe490"),
            "headset": ("#1e1e22", "#08080e", "#3a3a42"),
            "uniform": ("#1c1c20", "#08080c", "#38383e"),
            "vest": ("pat", [("#1c1c20", "#08080c", "#38383e"), ("#c8962e", "#5a3a28", "#f4d47a")], 9.0),
            "pouch": ("#202024", "#08080c", "#3c3c42"),
            "forearm": ("#1c1c20", "#08080c", "#38383e"),
            "pad": ("#d0a03a", "#644030", "#ffe08a"),
            "boot": ("#18181c", "#06060a", "#323238"),
            "patch": ("#d0a03a", "#644030", "#ffe08a"),
            "glow": "!#ffb030",
        },
        "acc": {"helmet", "headset", "scorpion", "patch"},
        "colors": ("#1a1a1e", "#d8a840", "#1c1c20"),
    },
}


def joint(name: str, parent, loc) -> bpy.types.Object:
    e = C.empty(name, loc, parent)
    e.rotation_mode = "XYZ"
    return e


def arc_strip(r: float, a0: float, a1: float, z0: float, z1: float, n: int = 14,
              cy: float = 0.0, flare: float = 0.0) -> bmesh.types.BMesh:
    """Bande courbe (portion de cylindre vertical) d'angle a0..a1 (0 = devant, -Y), z0 bas -> z1 haut.
    flare > 0 : le bas s'écarte (jupe, couvre-nuque)."""
    secs = []
    for i in range(n):
        a = a0 + (a1 - a0) * i / (n - 1)
        sx, sy = math.sin(a), -math.cos(a)
        rb = r + flare
        secs.append([(rb * sx, cy + rb * sy, z0), (r * sx, cy + r * sy, z1)])
    return C.bm_loft(secs, closed=False)


class Hero:
    def __init__(self) -> None:
        self.j: dict[str, bpy.types.Object] = {}
        self.parts: list[tuple[bpy.types.Object, str]] = []      # (objet, clef de matériau)
        self.acc: dict[str, list[bpy.types.Object]] = {}          # accessoire -> objets
        self.ph = C.toon("_placeholder", "#ff00ff")
        self.rng = random.Random(7)
        self.shop = False
        self.build()

    # ------------------------------------------------------------------ construction
    def part(self, name, bm, key, parent, smooth=True, acc: str | None = None, nofs=False,
             thick: float = 0.0):
        ob = C.mesh_obj(name, bm, self.ph, smooth=smooth, coll=C.nofs_collection() if nofs else None)
        ob.parent = parent
        if thick > 0.0:
            C.solidify(ob, thick, 0.0)
        self.parts.append((ob, key))
        if acc:
            self.acc.setdefault(acc, []).append(ob)
        return ob

    def decal(self, target, poly, key, name, lift=0.003, subdiv=3, acc=None):
        ob = C.decal(target, poly, self.ph, name, lift=lift, subdiv=subdiv, coll=C.nofs_collection())
        if ob is not None:
            self.parts.append((ob, key))
            if acc:
                self.acc.setdefault(acc, []).append(ob)
        else:
            print("decal manquée :", name)
        return ob

    def text(self, body, size, key, parent, loc, acc):
        ob = C.text_mesh("txt_" + body, body, size, self.ph, coll=C.nofs_collection())
        ob.parent = parent
        ob.location = loc
        ob.rotation_euler = (math.pi / 2, 0, 0)
        self.parts.append((ob, key))
        self.acc.setdefault(acc, []).append(ob)

    def build(self) -> None:
        j = self.j
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["pelvis"] = pelvis = joint("pelvis", root, (0, 0, PZ))
        j["spine"] = spine = joint("spine", pelvis, (0, 0, 0.08))
        j["neck"] = neck = joint("neck", spine, (0, 0, 0.45))
        j["head"] = head = joint("head", neck, (0, 0, 0.0))
        head.scale = (HEAD_SCALE,) * 3
        self.build_legs(pelvis)
        self.build_torso(pelvis, spine)
        self.build_back(spine)
        self.build_arms(spine)
        self.build_head(head, spine)
        self.build_ghillie()
        self.build_shop_rifle()

    # --- jambes -----------------------------------------------------------
    def build_legs(self, pelvis) -> None:
        j = self.j
        for side, sx in (("L", 1), ("R", -1)):
            hip = j["hip" + side] = joint("hip" + side, pelvis, (0.115 * sx, 0, -0.02))
            knee = j["knee" + side] = joint("knee" + side, hip, (0, 0, -0.36 * LEG))
            self.part("thigh" + side, C.bm_xform(C.bm_cyl(12, 0.122, 0.104, 0.38),
                      loc=(0, 0, -0.17), scale=(1, 1, LEG)), "uniform", hip)
            self.part("cargo" + side, C.bm_xform(C.bm_box(0.05, 0.13, 0.12, bevel=0.015),
                      loc=(0.11 * sx, -0.005, -0.19 * LEG)), "uniform", hip)
            if sx < 0:   # holster de cuisse (côté droit)
                self.part("holster", C.bm_xform(C.bm_box(0.07, 0.13, 0.16, bevel=0.02),
                          loc=(-0.13, -0.01, -0.14 * LEG)), "vest", hip)
                self.part("holsterStrap", C.bm_xform(C.bm_cyl(12, 0.126, 0.126, 0.025),
                          loc=(0, 0, -0.20 * LEG)), "strap", hip)
            self.part("shin" + side, C.bm_xform(C.bm_cyl(12, 0.104, 0.094, 0.22 * LEG),
                      loc=(0, 0, LEG * -0.10)), "uniform", knee)
            # genouillère massive
            kp = C.bm_sphere(14, 9, 1.0)
            C.bm_xform(kp, loc=(0, -0.075, -0.015), scale=(0.105, 0.065, 0.10))
            self.part("kneepad" + side, kp, "pad", knee)
            self.part("kneeStrap" + side, C.bm_xform(C.bm_cyl(12, 0.108, 0.108, 0.025),
                      loc=(0, 0, -0.06)), "strap", knee)
            # ranger
            self.part("bootShaft" + side, C.bm_xform(C.bm_cyl(12, 0.100, 0.108, 0.17 * LEG + 0.03),
                      loc=(0, 0, LEG * -0.27)), "boot", knee)
            foot = C.bm_xform(C.bm_box(0.18, 0.28, 0.11, bevel=0.045), loc=(0, -0.06, -0.345 + 0.41 * (1 - LEG)))
            self.part("foot" + side, foot, "boot", knee)
            sole = C.bm_xform(C.bm_box(0.19, 0.29, 0.04, bevel=0.012), loc=(0, -0.06, -0.39 + 0.41 * (1 - LEG)))
            self.part("sole" + side, sole, "sole", knee)
            # néons (cyber)
            self.part("neonShin" + side, C.bm_xform(C.bm_box(0.02, 0.012, 0.14 * LEG), loc=(0.0, -0.104, -0.14 * LEG)),
                      "glow", knee, acc="cyber", nofs=True)
            self.part("neonThigh" + side, C.bm_xform(C.bm_box(0.012, 0.02, 0.22 * LEG),
                      loc=(0.124 * sx, 0, -0.17 * LEG)), "glow2", hip, acc="cyber", nofs=True)
            self.part("neonKnee" + side, C.bm_xform(C.bm_torus(16, 5, 0.075, 0.009), loc=(0, -0.12, -0.015),
                      rot=(math.pi / 2, 0, 0)), "glow", knee, acc="cyber", nofs=True)
            # samouraï : plaques de cuisse (haidate)
            self.part("haidate" + side, C.bm_xform(arc_strip(0.135, -1.0 * sx - 0.3 * sx, 0.6 * sx, -0.20, 0.0, n=8, flare=0.02),
                      scale=(1, 1, LEG)), "red", hip, acc="samurai", thick=0.012, smooth=False)

    # --- torse ------------------------------------------------------------
    def build_torso(self, pelvis, spine) -> None:
        self.part("hips", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, 0, -0.01),
                  scale=(0.225, 0.165, 0.15)), "uniform", pelvis)
        self.part("belt", C.bm_xform(C.bm_cyl(16, 0.226, 0.226, 0.06), loc=(0, 0, 0.05),
                  scale=(1, 0.78, 1)), "belt", pelvis)
        self.part("buckle", C.bm_xform(C.bm_box(0.08, 0.03, 0.05, bevel=0.01),
                  loc=(0, -0.178, 0.05)), "helmet_acc", pelvis)
        for k, x in enumerate((-0.16, 0.16)):
            self.part("beltPouch%d" % k, C.bm_xform(C.bm_box(0.08, 0.07, 0.10, bevel=0.018),
                      loc=(x, -0.12, 0.02)), "pouch", pelvis)
        # torse (uniforme)
        torso = C.bm_loft([
            C.ellipse(0, 0, 0.00, 0.190, 0.140, 14),
            C.ellipse(0, 0.005, 0.15, 0.205, 0.150, 14),
            C.ellipse(0, 0.010, 0.29, 0.232, 0.158, 14),
            C.ellipse(0, 0.012, 0.38, 0.215, 0.145, 14),
            C.ellipse(0, 0.012, 0.45, 0.110, 0.095, 14),
        ])
        self.part("torso", torso, "uniform", spine)
        # gilet porte-plaques : ceinture abdominale + plaques avant/arrière + bretelles
        cumm = C.bm_loft([C.ellipse(0, 0.004, 0.04, 0.218, 0.168, 16),
                          C.ellipse(0, 0.008, 0.22, 0.236, 0.178, 16)], cap_start=False, cap_end=False)
        self.part("cummerbund", cumm, "vest", spine, thick=0.012)
        self.part("plateF", C.bm_xform(C.bm_box(0.36, 0.07, 0.30, bevel=0.03), loc=(0, -0.150, 0.25),
                  rot=(0.06, 0, 0)), "vest", spine)
        self.part("plateB", C.bm_xform(C.bm_box(0.36, 0.07, 0.31, bevel=0.03), loc=(0, 0.150, 0.25)),
                  "vest", spine)
        for sx in (1, -1):
            st = C.bm_tube(C.bezier((0.12 * sx, -0.16, 0.38), (0.15 * sx, -0.12, 0.47),
                                    (0.15 * sx, 0.10, 0.47), (0.12 * sx, 0.16, 0.38), 6),
                           [0.042] * 6, seg=6, flat=0.45, up=(0, 0, 1))
            self.part("vestStrap", st, "vest", spine)
        # poches chargeurs (3) + poche admin + radio
        for k, x in enumerate((-0.11, 0.0, 0.11)):
            self.part("mag%d" % k, C.bm_xform(C.bm_box(0.095, 0.06, 0.13, bevel=0.018),
                      loc=(x, -0.198, 0.14)), "pouch", spine)
            self.part("magFlap%d" % k, C.bm_xform(C.bm_box(0.10, 0.066, 0.03, bevel=0.008),
                      loc=(x, -0.200, 0.205)), "vest", spine)
        self.part("admin", C.bm_xform(C.bm_box(0.22, 0.04, 0.09, bevel=0.012), loc=(0, -0.192, 0.30),
                  rot=(0.06, 0, 0)), "pouch", spine)
        self.part("radio", C.bm_xform(C.bm_box(0.07, 0.06, 0.12, bevel=0.015), loc=(0.17, -0.16, 0.30)),
                  "pouch", spine)
        self.part("antenna", C.bm_tube([(0.17, -0.16, 0.36), (0.18, -0.15, 0.46), (0.19, -0.13, 0.52)],
                                       [0.012, 0.010, 0.006], seg=5), "strap", spine)
        # cou : col / cagoule
        self.part("gaiter", C.bm_xform(C.bm_cyl(12, 0.10, 0.09, 0.10), loc=(0, 0.005, 0.46)), "mask", spine)
        # GIGN : lettrage blanc sur la plaque avant
        self.text("GIGN", 0.10, "text", spine, (0, -0.214, 0.372), "gign")
        # cyber : bandes néon sur le gilet
        for sx in (1, -1):
            self.part("neonVest", C.bm_xform(C.bm_box(0.014, 0.014, 0.26), loc=(0.15 * sx, -0.188, 0.24),
                      rot=(0.06, 0, 0)), "glow" if sx > 0 else "glow2", spine, acc="cyber", nofs=True)
        self.part("neonBelt", C.bm_xform(C.bm_torus(20, 5, 0.228, 0.010), loc=(0, 0, 0.05),
                  scale=(1, 0.79, 1)), "glow2", pelvis, acc="cyber", nofs=True)
        self.part("neonChest", C.bm_xform(C.bm_box(0.20, 0.014, 0.016), loc=(0, -0.196, 0.345)),
                  "glow", spine, acc="cyber", nofs=True)
        # scorpion : plaque de poitrine dorée
        self.part("goldPlate", C.bm_xform(C.bm_box(0.20, 0.03, 0.08, bevel=0.015), loc=(0, -0.198, 0.32),
                  rot=(0.06, 0, 0)), "gold", spine, acc="scorpion")
        for sx in (1, -1):
            self.part("goldTrim", C.bm_xform(C.bm_box(0.02, 0.03, 0.26), loc=(0.18 * sx, -0.186, 0.24),
                      rot=(0.06, 0, 0)), "gold", spine, acc="scorpion")
        # samouraï : jupe de plaques (kusazuri) à la ceinture
        for k, a in enumerate((-1.9, -0.95, 0.0, 0.95, 1.9)):
            pl = arc_strip(0.235, a - 0.40, a + 0.40, -0.20, 0.03, n=5, flare=0.05)
            C.bm_xform(pl, scale=(1, 0.82, 1))
            self.part("kusazuri%d" % k, pl, "red", pelvis, acc="samurai", thick=0.014, smooth=False)
            for zz in (-0.06, -0.14):
                band = arc_strip(0.243 + 0.05 * (0.03 - zz) / 0.23, a - 0.38, a + 0.38, zz - 0.008, zz + 0.008, n=5)
                C.bm_xform(band, scale=(1, 0.82, 1))
                self.part("kusaLace", band, "gold", pelvis, acc="samurai", thick=0.006, smooth=False)
        # chèche (desert)
        self.part("shemagh", C.bm_xform(C.bm_torus(18, 8, 0.12, 0.06), loc=(0, 0.0, 0.43),
                  scale=(1.05, 1.0, 0.8)), "shemagh", spine, acc="shemagh")
        self.part("shemaghTail", C.bm_tube(C.bezier((0.06, -0.12, 0.42), (0.09, -0.18, 0.37),
                                                    (0.10, -0.20, 0.30), (0.08, -0.21, 0.25), 5),
                                           [0.055, 0.058, 0.055, 0.05, 0.035], seg=6, flat=0.4),
                  "shemagh", spine, acc="shemagh")

    def build_back(self, spine) -> None:
        j = self.j
        pk = j["pack"] = joint("pack", spine, (0, 0.19, 0.28))
        # poche d'hydratation / radio dorsale
        self.part("hydra", C.bm_xform(C.bm_box(0.22, 0.08, 0.24, bevel=0.035, segs=3), loc=(0, 0.02, -0.02)),
                  "pouch", pk)
        self.part("hydraFlap", C.bm_xform(C.bm_box(0.23, 0.09, 0.05, bevel=0.02), loc=(0, 0.02, 0.10)),
                  "vest", pk)
        self.part("neonBack", C.bm_xform(C.bm_box(0.16, 0.014, 0.018), loc=(0, 0.065, -0.02)),
                  "glow2", pk, acc="cyber", nofs=True)

    # --- bras -------------------------------------------------------------
    def build_arms(self, spine) -> None:
        j = self.j
        for side, sx in (("L", 1), ("R", -1)):
            ua = j["ua" + side] = C.empty("ua" + side, SHOULDER[side], spine)
            ua.rotation_mode = "QUATERNION"
            fa = j["fa" + side] = C.empty("fa" + side, (0, 0, 0), spine)
            fa.rotation_mode = "QUATERNION"
            self.part("shoulder" + side, C.bm_xform(C.bm_sphere(12, 8, 0.108), loc=(0, 0, -0.01)),
                      "uniform", ua)
            self.part("uarm" + side, C.bm_xform(C.bm_cyl(12, 0.100, 0.088, 0.19), loc=(0, 0, -0.10)),
                      "uniform", ua)
            # écusson d'épaule (côté extérieur)
            self.part("patch" + side, C.bm_xform(C.bm_box(0.014, 0.075, 0.075, bevel=0.01),
                      loc=(0.092 * sx, -0.005, -0.075)), "patch", ua, acc="patch" if sx > 0 else None)
            if sx > 0:
                for k, key in enumerate(("flag_b", "flag_w", "flag_r")):
                    self.part("flag%d" % k, C.bm_xform(C.bm_box(0.014, 0.025, 0.06),
                              loc=(0.094, 0.025 - k * 0.025, -0.075)), key, ua, acc="flag", smooth=False)
            self.part("elbow" + side, C.bm_xform(C.bm_sphere(10, 7, 1.0), scale=(0.072, 0.075, 0.068)), "pad", fa)
            self.part("farm" + side, C.bm_xform(C.bm_cyl(10, 0.080, 0.070, 0.16), loc=(0, 0, -0.08)),
                      "forearm", fa)
            self.part("gcuff" + side, C.bm_xform(C.bm_cyl(10, 0.068, 0.074, 0.05), loc=(0, 0, -0.165)),
                      "glove", fa)
            hand = C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, 0, -L_LOW + 0.012), scale=(0.085, 0.078, 0.090))
            self.part("hand" + side, hand, "glove", fa)
            self.part("neonArm" + side, C.bm_xform(C.bm_torus(14, 5, 0.066, 0.010), loc=(0, 0, -0.12)),
                      "glow", fa, acc="cyber", nofs=True)
            self.part("neonUarm" + side, C.bm_xform(C.bm_torus(14, 5, 0.087, 0.010), loc=(0, 0, -0.14)),
                      "glow2", ua, acc="cyber", nofs=True)
            # samouraï : sode (plaques d'épaule)
            sode = arc_strip(0.115, 0.6 * sx + 0.9 * sx - 1.0 * sx, 0.6 * sx + 0.9 * sx + 1.0 * sx, -0.20, 0.03, n=8, flare=0.05)
            self.part("sode" + side, sode, "red", ua, acc="samurai", thick=0.016, smooth=False)
            for zz in (-0.05, -0.12):
                band = arc_strip(0.118 + 0.05 * (0.03 - zz) / 0.23, 0.5 * sx, 2.5 * sx, zz - 0.008, zz + 0.008, n=8)
                self.part("sodeLace", band, "gold", ua, acc="samurai", thick=0.006, smooth=False)
            # scorpion : épaulière dorée
            pad = C.bm_sphere(14, 9, 1.0)
            for v in pad.verts:
                if v.co.z < -0.2:
                    v.co.z = -0.2 + (v.co.z + 0.2) * 0.2
            self.part("goldPad" + side, C.bm_xform(pad, loc=(0.02 * sx, 0.0, 0.0), rot=(0, 0.35 * sx, 0),
                      scale=(0.12, 0.12, 0.08)), "gold", ua, acc="scorpion")

    # --- tête -------------------------------------------------------------
    def build_head(self, head, spine) -> None:
        # tête / cagoule
        sk = C.bm_sphere(22, 16, 1.0)
        for v in sk.verts:
            x, y, z = v.co
            if z < 0:
                x *= 1.0 + 0.04 * (-z) - 0.20 * (-z) ** 2
                y *= 1.0 - 0.08 * (-z)
            v.co = Vector((x * 0.188, y * 0.180, z * 0.198 + 0.0)) + Vector((0, 0, 0.205))
        skull = self.part("skull", sk, "mask", head)
        self.part("nose", C.bm_xform(C.bm_sphere(10, 7, 1.0), loc=(0, -0.176, 0.175),
                  scale=(0.030, 0.026, 0.028)), "mask", head)
        # tête de mort (Fantôme, SAS) : décalques sur la cagoule
        bone = [(0.150 * math.cos(a), 0.215 + (0.120 if math.sin(a) > 0 else 0.150) * math.sin(a)
                 * (1.0 if math.sin(a) > 0 else (1.0 - 0.25 * abs(math.cos(a)))))
                for a in (2 * math.pi * i / 20 for i in range(20))]
        self.decal(skull, bone, "bone", "skullFace", lift=0.003, acc="skull")
        for sx in (1, -1):
            eye = [(0.064 * sx + 0.046 * math.cos(a), 0.240 + 0.040 * math.sin(a))
                   for a in (2 * math.pi * i / 14 for i in range(14))]
            self.decal(skull, eye, "socket", "skullEye", lift=0.006, acc="skull")
        self.decal(skull, [(0.0, 0.200), (0.022, 0.160), (-0.022, 0.160)], "socket", "skullNose",
                   lift=0.006, subdiv=2, acc="skull")
        self.decal(skull, [(-0.075, 0.122), (0.075, 0.122), (0.075, 0.112), (-0.075, 0.112)], "socket",
                   "skullMouth", lift=0.006, subdiv=2, acc="skull")
        for k in range(-3, 4):
            x = k * 0.022
            self.decal(skull, [(x - 0.004, 0.142), (x + 0.004, 0.142), (x + 0.004, 0.092), (x - 0.004, 0.092)],
                       "socket", "skullTooth", lift=0.006, subdiv=1, acc="skull")

        # casque tactique (très gros) : coque coupée devant au-dessus des lunettes
        R = 0.232
        HZ = 0.245

        def cut(y: float) -> float:
            """Hauteur du bord du casque selon la position avant/arrière (au-dessus des lunettes devant)."""
            f = max(0.0, min(1.0, -y / R))
            return 0.352 * f ** 1.1 + 0.175 * (1 - f ** 1.1)
        hm = C.bm_sphere(28, 18, 1.0)
        for v in hm.verts:
            x, y, z = v.co * R
            z = HZ + z * 0.92
            v.co = Vector((x * 1.03, y * 1.02 + 0.010, max(z, cut(y))))
        self.part("helmet", hm, "helmet", head, acc="helmet")
        rim = []
        for i in range(40):
            a = 2 * math.pi * i / 40
            x, y = R * 1.03 * math.sin(a), -R * 1.02 * math.cos(a) + 0.010
            rim.append((x, y, cut(y - 0.010) + 0.004))
        rim.append(rim[0])
        self.part("helmetRim", C.bm_tube(rim, [0.017] * len(rim), seg=6), "helmet_acc", head, acc="helmet")
        for sx in (1, -1):
            self.part("rail", C.bm_xform(C.bm_box(0.03, 0.22, 0.04, bevel=0.008), loc=(0.236 * sx, 0.0, 0.25),
                      rot=(0.25, 0, 0)), "helmet_acc", head, acc="helmet")
        self.part("nvgMount", C.bm_xform(C.bm_box(0.10, 0.05, 0.075, bevel=0.012), loc=(0, -0.205, 0.405),
                  rot=(-0.7, 0, 0)), "helmet_acc", head, acc="helmet")
        self.part("velcro", C.bm_xform(C.bm_box(0.12, 0.10, 0.03, bevel=0.01), loc=(0, 0.02, 0.475),
                  rot=(-0.2, 0, 0)), "helmet_acc", head, acc="helmet")
        # cagoule / capuche (Fantôme)
        hood = C.bm_sphere(20, 14, 1.0)
        for v in hood.verts:
            x, y, z = v.co
            if y < -0.2 and z < 0.55:
                y = -0.2 + (y + 0.2) * 0.15
            v.co = Vector((x * 0.205, y * 0.198 + 0.012, z * 0.215 + 0.22))
        self.part("hood", hood, "mask", head, acc="hood")

        # casque audio
        for sx in (1, -1):
            cup = C.bm_cyl(16, 0.082, 0.076, 0.07)
            C.bm_xform(cup, loc=(0.222 * sx, 0.015, 0.205), rot=(0, math.pi / 2, 0))
            self.part("cup", cup, "headset", head, acc="headset")
            ring = C.bm_torus(16, 5, 0.062, 0.012)
            C.bm_xform(ring, loc=(0.258 * sx, 0.015, 0.205), rot=(0, math.pi / 2, 0))
            self.part("cupRing", ring, "helmet_acc", head, acc="headset")
            ringn = C.bm_torus(16, 5, 0.062, 0.012)
            C.bm_xform(ringn, loc=(0.262 * sx, 0.015, 0.205), rot=(0, math.pi / 2, 0))
            self.part("cupNeon", ringn, "glow", head, acc="cyber", nofs=True)
        band = C.bm_tube([(0.235 * math.cos(a), 0.03, 0.205 + 0.30 * math.sin(a))
                          for a in (math.pi * i / 12 for i in range(13))], [0.02] * 13, seg=6, up=(0, 1, 0))
        self.part("hpBand", band, "headset", head, acc="hood")
        self.part("mic", C.bm_tube(C.bezier((0.23, -0.01, 0.17), (0.22, -0.10, 0.12), (0.14, -0.17, 0.10),
                                             (0.07, -0.19, 0.11), 5), [0.012] * 5, seg=5), "strap", head,
                  acc="headset")

        # lunettes de protection : bande courbe + écran
        gfr = arc_strip(0.200, -1.32, 1.32, 0.200, 0.350, n=18, cy=-0.006)
        self.part("gogFrame", gfr, "goggles", head, acc="goggles", thick=0.02, smooth=True)
        lens = arc_strip(0.218, -1.12, 1.12, 0.212, 0.338, n=18, cy=-0.006)
        self.part("lens", lens, "lens", head, acc="goggles", thick=0.006, smooth=True)
        self.part("gogStrap", C.bm_xform(C.bm_torus(24, 5, 0.196, 0.016), loc=(0, 0.0, 0.275)),
                  "strap", head, acc="goggles")

        # cyber : visière en V lumineuse + yeux
        vz = 0.255
        self.part("visor", C.bm_tube([(-0.15, -0.150, vz + 0.06), (-0.05, -0.200, vz), (0.0, -0.205, vz - 0.02),
                                      (0.05, -0.200, vz), (0.15, -0.150, vz + 0.06)], [0.020] * 5, seg=6,
                                     flat=0.6, up=(0, 1, 0)), "glow", head, acc="cyber", nofs=True)
        self.part("visorPlate", arc_strip(0.198, -1.1, 1.1, 0.16, 0.33, n=16), "helmet", head,
                  acc="cyber", thick=0.02)
        self.part("helmNeon", C.bm_tube([(0.0, -0.21, 0.36), (0.0, -0.18, 0.44), (0.0, -0.08, 0.50),
                                         (0.0, 0.06, 0.50)], [0.012] * 4, seg=5), "glow2", head,
                  acc="cyber", nofs=True)

        # scorpion : masque doré + crête dorée
        gm = C.bm_sphere(20, 14, 1.0)
        for v in gm.verts:
            x, y, z = v.co
            if y > -0.15:
                y = -0.15 + (y + 0.15) * 0.08
            v.co = Vector((x * 0.198, y * 0.200 - 0.006, z * 0.150 + 0.195))
        gmask = self.part("goldMask", gm, "gold", head, acc="scorpion")
        for sx in (1, -1):
            slit = [(0.018 * sx, 0.268), (0.145 * sx, 0.292), (0.135 * sx, 0.218), (0.022 * sx, 0.200)]
            if sx < 0:
                slit.reverse()
            self.decal(gmask, slit, "socket", "goldSlit", lift=0.004, subdiv=2, acc="scorpion")
        self.decal(gmask, [(-0.006, 0.20), (0.006, 0.20), (0.004, 0.08), (-0.004, 0.08)], "socket",
                   "goldLine", lift=0.004, subdiv=1, acc="scorpion")
        self.part("goldCrest", C.bm_tube([(0.0, -0.20, 0.33), (0.0, -0.17, 0.43), (0.0, -0.07, 0.49),
                                          (0.0, 0.08, 0.49), (0.0, 0.18, 0.42)], [0.022] * 5, seg=6, flat=0.6,
                                         up=(1, 0, 0)), "gold", head, acc="scorpion")

        # samouraï : couvre-nuque (shikoro), maedate dorée en croissant
        for k, zz in enumerate((0.20, 0.15, 0.10)):
            sh = arc_strip(0.238 + 0.022 * k, 1.25, 2 * math.pi - 1.25, zz - 0.06, zz, n=16, flare=0.025, cy=0.01)
            self.part("shikoro%d" % k, sh, "helmet", head, acc="samurai", thick=0.016, smooth=False)
        pts = []
        for i in range(13):
            t = math.pi + math.pi * i / 12
            pts.append((0.26 * math.cos(t), -0.235 - 0.02 * abs(math.cos(t)), 0.36 + 0.30 * (1 + math.sin(t)) ** 1.0))
        rr = [0.012 + 0.03 * math.sin(math.pi * i / 12) ** 0.7 for i in range(13)]
        rr[0] = rr[-1] = 0.004
        self.part("maedate", C.bm_tube(pts, rr, seg=8, flat=0.35, up=(0, 1, 0)), "gold", head, acc="samurai")
        self.part("maedateBase", C.bm_xform(C.bm_cyl(12, 0.04, 0.04, 0.025), loc=(0, -0.235, 0.36),
                  rot=(math.pi / 2, 0, 0)), "gold", head, acc="samurai")
        # menpo (masque de visage) : mâchoire sombre sous les lunettes
        mp = C.bm_sphere(18, 12, 1.0)
        for v in mp.verts:
            x, y, z = v.co
            if y > -0.2:
                y = -0.2 + (y + 0.2) * 0.1
            if z > 0.3:
                z = 0.3
            v.co = Vector((x * 0.19, y * 0.20 - 0.01, z * 0.11 + 0.13))
        mpo = self.part("menpo", mp, "bone", head, acc="samurai")
        for k in range(-2, 3):
            x = k * 0.03
            self.decal(mpo, [(x - 0.005, 0.15), (x + 0.005, 0.15), (x + 0.005, 0.09), (x - 0.005, 0.09)],
                       "red", "menpoTooth", lift=0.004, subdiv=1, acc="samurai")

    # --- ghillie (Forest) ---------------------------------------------------
    def build_ghillie(self) -> None:
        """Touffes de lanières feuillues sur la tête, le buste, les bras et les jambes (un maillage par membre)."""
        j = self.j
        rng = self.rng
        specs = [
            # (articulation, centre, rayons ellipsoïde, nombre, longueur)
            ("head", (0, 0.01, 0.24), (0.23, 0.22, 0.24), 120, 0.11),
            ("spine", (0, 0.0, 0.25), (0.25, 0.20, 0.22), 90, 0.12),
            ("pelvis", (0, 0.0, -0.02), (0.24, 0.18, 0.10), 30, 0.10),
            ("hipL", (0, 0, -0.14), (0.13, 0.13, 0.12), 22, 0.09),
            ("hipR", (0, 0, -0.14), (0.13, 0.13, 0.12), 22, 0.09),
            ("kneeL", (0, 0, -0.07), (0.11, 0.11, 0.07), 14, 0.07),
            ("kneeR", (0, 0, -0.07), (0.11, 0.11, 0.07), 14, 0.07),
            ("uaL", (0, 0, -0.08), (0.10, 0.10, 0.09), 14, 0.08),
            ("uaR", (0, 0, -0.08), (0.10, 0.10, 0.09), 14, 0.08),
        ]
        for name, c, r, n, ln in specs:
            bms = []
            if name == "head":
                hood = C.bm_sphere(18, 12, 1.0)
                C.bm_xform(hood, loc=(0, 0.015, 0.235), scale=(0.222, 0.212, 0.232))
                for v in hood.verts:
                    if v.co.y < -0.12 and 0.12 < v.co.z < 0.31 and abs(v.co.x) < 0.14:
                        v.co.y = -0.12 + (v.co.y + 0.12) * 0.1
                bms.append(hood)
            for _ in range(n):
                u = rng.uniform(-1, 1)
                th = rng.uniform(0, 2 * math.pi)
                s = math.sqrt(1 - u * u)
                d = Vector((s * math.cos(th), s * math.sin(th), u))
                if name == "head" and d.y < -0.45 and -0.6 < d.z < 0.45 and abs(d.x) < 0.65:
                    continue   # laisse le visage dégagé
                p = Vector(c) + Vector((d.x * r[0], d.y * r[1], d.z * r[2]))
                out = Vector((d.x, d.y, max(d.z, -0.2))).normalized()
                L = ln * rng.uniform(0.7, 1.3)
                tip = p + out * L * 0.6 + Vector((0, 0, -L * 0.7))
                mid = p + out * L * 0.5 + Vector((0, 0, -L * 0.15))
                w = rng.uniform(0.018, 0.03)
                bms.append(C.bm_tube([tuple(p), tuple(mid), tuple(tip)], [w, w * 0.9, 0.004], seg=4,
                                     flat=0.35, up=tuple(out)))
            bm = C.bm_merge(*bms)
            self.part("ghillie_" + name, bm, "ghillie", j[name], acc="ghillie")

    def build_shop_rifle(self) -> None:
        """Fusil d'assaut tenu à deux mains, pour l'aperçu boutique uniquement (comme la planche)."""
        sp = self.j["spine"]
        g = C.empty("shopRifle", (0, 0, 0), sp)
        self.j_rifle = g
        blk, drk = "helmet_acc", "strap"
        parts = [
            (C.bm_box(0.09, 0.62, 0.11, bevel=0.012), (0, 0.0, 0.0), blk),       # boîtier + garde-main
            (C.bm_box(0.06, 0.30, 0.06, bevel=0.008), (0, -0.44, 0.01), drk),    # canon
            (C.bm_box(0.06, 0.07, 0.20, bevel=0.01), (0, -0.06, -0.13), drk),   # chargeur
            (C.bm_box(0.07, 0.28, 0.12, bevel=0.012), (0, 0.42, -0.03), blk),   # crosse
            (C.bm_box(0.05, 0.22, 0.04, bevel=0.006), (0, -0.05, 0.08), drk),   # rail / viseur
        ]
        for bm, loc, key in parts:
            self.part("rifle", C.bm_xform(bm, loc=loc), key, g, acc="shop_rifle")
        g.rotation_euler = (0.35, 0, 0.55)
        g.location = HAND_R + Vector((0.04, -0.03, 0.06))

    # ------------------------------------------------------------------ skins
    def apply_skin(self, sid: str) -> None:
        sk = SKINS[sid]
        spec = dict(BASE_MATS)
        spec.update(sk["mats"])
        mats = {}
        for key, sp in spec.items():
            name = "%s_%s" % (sid, key)
            if isinstance(sp, str) and sp.startswith("!"):
                mats[key] = C.toon(name, sp[1:], emit=1.0)
            elif sp[0] == "pat":
                mats[key] = C.toon_pattern(name, sp[1], scale=sp[2], thresholds=(0.50, 0.58), rim=0.28)
            elif key in ("socket", "flag_b", "flag_w", "flag_r", "text"):
                mats[key] = C.toon(name, sp[0], sp[1], sp[2], rim=0.0, band=0.25)
            else:
                mats[key] = C.toon(name, sp[0], sp[1], sp[2], rim=0.30)
        for ob, key in self.parts:
            ob.data.materials[0] = mats[key]
        visible = set(sk["acc"]) | ({"shop_rifle"} if self.shop else set())
        for acc, obs in self.acc.items():
            on = acc in visible
            for ob in obs:
                ob.hide_render = not on
                ob.hide_viewport = not on

    # ------------------------------------------------------------------ poses
    def rest(self) -> None:
        for name, ob in self.j.items():
            if name in ("root",) or name.startswith(("ua", "fa")):
                continue
            ob.rotation_euler = (0, 0, 0)
            ob.scale = (HEAD_SCALE,) * 3 if name == "head" else (1, 1, 1)
        self.j["pelvis"].location = (0, 0, PZ)
        self.j["head"].rotation_euler = (HEAD_PITCH, 0, 0)
        self.j["neck"].location = (0, 0, 0.45)
        self.j["pack"].location = (0, 0.19, 0.28)

    def arm_ik(self, side: str, target: Vector, pole: Vector) -> None:
        """IK 2 segments dans le repère de la colonne : place bras et avant-bras."""
        S = SHOULDER[side]
        d = target - S
        dist = min(d.length, (L_UP + L_LOW) * 0.995)
        u = d.normalized()
        a = (L_UP ** 2 + dist ** 2 - L_LOW ** 2) / (2 * dist)
        h = math.sqrt(max(L_UP ** 2 - a * a, 0.0))
        p = pole - u * pole.dot(u)
        p = p.normalized() if p.length > 1e-5 else Vector((0, 1, 0))
        E = S + u * a + p * h
        H = S + u * dist
        down = Vector((0, 0, -1))
        ua, fa = self.j["ua" + side], self.j["fa" + side]
        ua.location = S
        ua.rotation_quaternion = down.rotation_difference((E - S).normalized())
        fa.location = E
        fa.rotation_quaternion = down.rotation_difference((H - E).normalized())

    def arms_hold(self, dz: float = 0.0, dy: float = 0.0, dx: float = 0.0, left: Vector | None = None) -> None:
        off = Vector((dx, dy, dz))
        self.arm_ik("R", HAND_R + off, Vector((-0.8, 0.4, -0.6)))
        self.arm_ik("L", (left if left is not None else HAND_L + off), Vector((0.8, 0.5, -0.6)))

    def legs(self, hipL, hipR, kneeL, kneeR) -> None:
        j = self.j
        j["hipL"].rotation_euler = hipL
        j["hipR"].rotation_euler = hipR
        j["kneeL"].rotation_euler = (kneeL, 0, 0)
        j["kneeR"].rotation_euler = (kneeR, 0, 0)

    def pose(self, anim: str, i: int) -> None:
        getattr(self, "pose_" + anim)(i)

    def pose_idle(self, i: int) -> None:
        self.rest()
        j = self.j
        n = ANIMS["idle"][0]
        t = 2 * math.pi * i / n
        b = math.sin(t)
        sway = math.sin(t + 0.6)
        j["pelvis"].location.z = PZ - 0.010 * (1 - b) * 0.5
        j["pelvis"].rotation_euler = (0, 0.012 * sway, 0.02 * sway)
        j["spine"].rotation_euler = (0.04 + 0.014 * b, -0.015 * sway, 0)
        j["spine"].scale = (1 + 0.008 * b, 1 + 0.008 * b, 1 + 0.010 * b)
        j["neck"].rotation_euler = (-0.05 - 0.014 * b, 0.02 * sway, 0.03 * sway)
        j["pack"].rotation_euler = (0.02 * b, 0, 0)
        self.legs((0.04, -0.07 - 0.012 * sway, 0), (-0.04, 0.07 - 0.012 * sway, 0), 0.06, 0.08)
        self.arms_hold(dz=0.012 * b)

    def pose_run(self, i: int) -> None:
        self.rest()
        j = self.j
        n = ANIMS["run"][0]
        p = 2 * math.pi * i / n
        s = math.sin(p)
        c = math.cos(p)
        # rebond : bas aux contacts (2 par cycle), haut en suspension
        j["pelvis"].location.z = PZ - 0.045 + 0.060 * abs(math.sin(p + 0.35))
        j["pelvis"].rotation_euler = (0, 0, -0.16 * s)
        j["spine"].rotation_euler = (0.26, 0, 0.20 * s)
        j["neck"].rotation_euler = (-0.24, 0, -0.14 * s)
        j["pack"].rotation_euler = (0.08 * abs(math.cos(p + 0.35)), 0, 0)
        # jambes : grande foulée, genou arrière très plié (talon remonté)
        self.legs((-0.95 * s - 0.15, 0, 0), (0.95 * s - 0.15, 0, 0),
                  0.20 + 1.45 * max(0.0, math.sin(p - 1.0)) ** 1.2,
                  0.20 + 1.45 * max(0.0, math.sin(p - 1.0 + math.pi)) ** 1.2)
        # bras droit tient l'arme (suit le buste), bras gauche balance (opposé à la jambe gauche)
        self.arm_ik("R", HAND_R + Vector((0.0, 0.0, 0.015 * c)), Vector((-0.8, 0.4, -0.6)))
        sw = Vector((0.20, 0.30 * s - 0.02, 0.06 - 0.10 * abs(s) + 0.05 * max(0.0, -s)))
        self.arm_ik("L", SHOULDER["L"] + Vector((0.02, 0, -0.33)) + sw * 0.9 + Vector((-0.08, -0.08 * max(0, -s), 0.12 * max(0.0, -s))),
                    Vector((0.4, 0.9, -0.2)))

    def pose_backpedal(self, i: int) -> None:
        self.rest()
        j = self.j
        n = ANIMS["backpedal"][0]
        p = -2 * math.pi * i / n          # cycle joué à l'envers
        s = math.sin(p)
        j["pelvis"].location.z = PZ - 0.03 + 0.035 * abs(math.sin(p - 0.3))
        j["pelvis"].rotation_euler = (0, 0, -0.08 * s)
        j["spine"].rotation_euler = (-0.08, 0, 0.08 * s)
        j["neck"].rotation_euler = (0.04, 0, -0.06 * s)
        j["pack"].rotation_euler = (-0.04 * abs(s), 0, 0)
        self.legs((-0.55 * s - 0.05, 0, 0), (0.55 * s - 0.05, 0, 0),
                  0.18 + 0.85 * max(0.0, math.sin(p + 1.2)),
                  0.18 + 0.85 * max(0.0, math.sin(p + 1.2 + math.pi)))
        self.arms_hold(dz=0.012 * abs(s))

    def _strafe(self, i: int, sgn: float) -> None:
        """Pas chassés latéraux. sgn = +1 : vers la gauche du personnage (+X local)."""
        self.rest()
        j = self.j
        n = ANIMS["strafe_l"][0]
        p = 2 * math.pi * i / n
        s = math.sin(p)
        j["pelvis"].location.z = PZ - 0.025 + 0.035 * abs(math.sin(p))
        j["pelvis"].location.x = 0.025 * sgn * math.sin(p - 0.5)
        j["pelvis"].rotation_euler = (0, -0.06 * sgn, 0.05 * s)
        j["spine"].rotation_euler = (0.08, -0.07 * sgn, 0)
        j["neck"].rotation_euler = (-0.06, 0.08 * sgn, 0)
        j["pack"].rotation_euler = (0, 0.05 * sgn * abs(s), 0)
        # ciseaux latéraux : les jambes s'écartent puis se rejoignent, genou levé sur la jambe en l'air
        spread = 0.30 * (0.5 + 0.5 * math.cos(p))
        lead = 0.12 * s
        self.legs((-0.10 * s, -(spread + 0.05) + lead * sgn, 0), (0.10 * s, (spread + 0.05) + lead * sgn, 0),
                  0.12 + 0.55 * max(0.0, math.sin(p)), 0.12 + 0.55 * max(0.0, -math.sin(p)))
        self.arms_hold(dz=0.012 * abs(s), dx=0.012 * sgn * s)

    def pose_strafe_l(self, i: int) -> None:
        self._strafe(i, 1.0)

    def pose_strafe_r(self, i: int) -> None:
        self._strafe(i, -1.0)

    def pose_hit(self, i: int) -> None:
        self.rest()
        j = self.j
        k = (1.0, 0.65, 0.25)[i]
        j["pelvis"].location.z = PZ - 0.02 * k
        j["pelvis"].location.y = 0.03 * k
        j["spine"].rotation_euler = (-0.30 * k, 0, 0.10 * k)
        j["neck"].rotation_euler = (-0.30 * k, 0, -0.12 * k)
        j["pack"].rotation_euler = (-0.10 * k, 0, 0)
        self.legs((0.10 * k, -0.10, 0), (-0.18 * k, 0.10, 0), 0.10 + 0.12 * k, 0.12)
        self.arms_hold(dz=0.06 * k, dy=0.06 * k, left=HAND_L + Vector((0.10 * k, 0.04 * k, 0.12 * k)))


# ----------------------------------------------------------------------------- rendu

def setup_scene():
    C.reset_scene()
    C.setup_render((FRAME_W * SS, FRAME_H * SS), samples=4, outline_px=5.0)
    hero = Hero()
    cam = C.ortho_camera(ELEV, ORTHO_H, target=(0, 0, CAM_TARGET_Z))
    cam.data.sensor_fit = "VERTICAL"
    return hero, cam


def render_frame(path: str) -> None:
    big = path + ".big.png"
    C.render_to(big)
    C.downscale(big, path, (FRAME_W, FRAME_H))
    os.remove(big)


def out_dir(sid: str) -> str:
    return OUT_DEFAULT if sid == "default" else os.path.join(OUT_SKINS, sid)


def res_dir(sid: str) -> str:
    rel = os.path.relpath(out_dir(sid), ROOT).replace(os.sep, "/")
    return "res://" + rel + "/"


def assemble(sid: str, frames: dict) -> None:
    """Planches : une par animation (lignes = directions, colonnes = images)."""
    from PIL import Image
    od = out_dir(sid)
    for anim, (n, _fps, _loop) in ANIMS.items():
        sheet = Image.new("RGBA", (FRAME_W * n, FRAME_H * len(DIRS)), (0, 0, 0, 0))
        for r, d in enumerate(DIRS):
            for c in range(n):
                sheet.paste(Image.open(frames[(anim, d, c)]), (c * FRAME_W, r * FRAME_H))
        # alpha nettoyé : pixels quasi transparents -> 0 (meilleure compression)
        a = sheet.getchannel("A").point(lambda v: 0 if v < 4 else v)
        sheet.putalpha(a)
        blank = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
        sheet = Image.composite(sheet, blank, a.point(lambda v: 255 if v else 0))
        compact_png(sheet, os.path.join(od, "hero_%s.png" % anim))


def render_shop(hero: "Hero", cam, sids) -> None:
    """Aperçu boutique en pied, de face (preview.png, SHOP_W x SHOP_H), légèrement de 3/4 comme la planche."""
    sc = bpy.context.scene
    old = (sc.render.resolution_x, sc.render.resolution_y, cam.data.ortho_scale, cam.location.copy())
    sc.render.resolution_x, sc.render.resolution_y = SHOP_W * SS, SHOP_H * SS
    cam.data.ortho_scale = ORTHO_H * 0.78
    cam.location.z -= 0.14
    hero.j["root"].rotation_euler = (0, 0, math.radians(-14))
    hero.pose_idle(0)
    hero.shop = True
    for sid in sids:
        hero.apply_skin(sid)
        os.makedirs(out_dir(sid), exist_ok=True)
        big = os.path.join(TMP_DIR, "shop_%s.png" % sid)
        C.render_to(big)
        C.downscale(big, os.path.join(out_dir(sid), "preview.png"), (SHOP_W, SHOP_H))
    hero.shop = False
    sc.render.resolution_x, sc.render.resolution_y, cam.data.ortho_scale = old[0], old[1], old[2]
    cam.location = old[3]


def compact_png(img, path: str) -> None:
    """PNG indexé 256 couleurs avec alpha (rendu toon en aplats : différence invisible, ~5x plus léger)."""
    from PIL import Image
    q = img.convert("RGBA").quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    q.save(path, optimize=True)


def write_tres(sid: str) -> None:
    rd = res_dir(sid)
    total = sum(n for n, _f, _l in ANIMS.values()) * len(DIRS)
    lines = ['[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (1 + len(ANIMS) + total), ""]
    for k, anim in enumerate(ANIMS):
        lines.append('[ext_resource type="Texture2D" path="%shero_%s.png" id="%d_%s"]' % (rd, anim, k + 1, anim))
    lines.append("")
    anims = []
    for k, (anim, (n, fps, loop)) in enumerate(ANIMS.items()):
        tex = "%d_%s" % (k + 1, anim)
        for r, d in enumerate(DIRS):
            ids = []
            for c in range(n):
                sid_ = "A_%s_%s_%d" % (anim, d, c)
                ids.append(sid_)
                lines.append('[sub_resource type="AtlasTexture" id="%s"]' % sid_)
                lines.append('atlas = ExtResource("%s")' % tex)
                lines.append("region = Rect2(%d, %d, %d, %d)" % (c * FRAME_W, r * FRAME_H, FRAME_W, FRAME_H))
                lines.append("")
            fr = ", ".join('{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % s for s in ids)
            anims.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s_%s",\n"speed": %.1f\n}'
                         % (fr, "true" if loop else "false", anim, d, float(fps)))
    lines.append("[resource]")
    lines.append("animations = [%s]" % ", ".join(anims))
    with open(os.path.join(out_dir(sid), "hero_frames.tres"), "w") as f:
        f.write("\n".join(lines) + "\n")


def write_meta(sid: str, feet, hero_px: int, hands: dict) -> None:
    rd = res_dir(sid)
    scale = None
    disp = round(HERO_WORLD_HEIGHT * FRAME_H / hero_px, 1)
    scale = disp / FRAME_H
    # main (côté droit, pose idle 0, face est) : hauteur au-dessus des pieds en unités monde
    hx, hy = hands["e"]
    hand_height = round((feet[1] - hy) * scale, 1)
    meta = {
        "frame_size": [FRAME_W, FRAME_H],
        "feet_offset": [feet[0], feet[1]],
        "display_height": disp,
        "fps": {a: f for a, (_n, f, _l) in ANIMS.items()},
        "directions": list(DIRS.keys()),
        "frames": {a: n for a, (n, _f, _l) in ANIMS.items()},
        "loop": {a: l for a, (_n, _f, l) in ANIMS.items()},
        "hero_height_px": hero_px,
        "hand_height": hand_height,
        "hand_px": {d: [round(v[0], 1), round(v[1], 1)] for d, v in hands.items()},
        "sheets": {a: "%shero_%s.png" % (rd, a) for a in ANIMS},
        "skin": sid,
        "notes": "display_height = hauteur du cadre entier (frame_size.y px) en unités monde : "
                 "scale = display_height / frame_size.y. feet_offset = point des pieds (px depuis le "
                 "coin haut-gauche du cadre) -> offset = -(feet_offset - frame_size/2) si centered. "
                 "hand_height (unités monde) = hauteur de la main droite au-dessus des pieds ; hand_px = "
                 "position de la main droite (px dans le cadre) par direction, pose idle 0. "
                 "Animations : idle, run (course vers l'avant), backpedal (recule en regardant devant), "
                 "strafe_l / strafe_r (pas chassés vers la gauche / la droite du personnage), hit (non bouclée).",
    }
    with open(os.path.join(out_dir(sid), "hero_meta.json"), "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
        f.write("\n")


def hand_pixels(hero: Hero, cam) -> dict:
    """Position écran (px du cadre final) de la main droite, pose idle 0, pour chaque direction."""
    out = {}
    hero.pose_idle(0)
    for d, ang in DIRS.items():
        hero.j["root"].rotation_euler = (0, 0, math.radians(ang))
        bpy.context.view_layer.update()
        hw = hero.j["faR"].matrix_world @ Vector((0, 0, -L_LOW + 0.01))
        px = C.world_to_px(cam, hw)
        out[d] = (px[0] / SS, px[1] / SS)
    return out


def measure_height(path: str) -> int:
    from PIL import Image
    im = Image.open(path)
    bb = im.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
    return bb[3] - bb[1]


def write_skin_tres(sid: str) -> None:
    sk = SKINS[sid]
    rd = res_dir(sid)

    def col(h: str) -> str:
        h = h.lstrip("#")
        r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
        return "Color(%.3f, %.3f, %.3f, 1)" % (r, g, b)
    p, s, a = sk["colors"]
    txt = """[gd_resource type="Resource" script_class="SkinData" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/cosmetics/skin_data.gd" id="1_skin"]
[ext_resource type="Texture2D" path="%spreview.png" id="2_prev"]

[resource]
script = ExtResource("1_skin")
id = &"char_%s"
display_name = "%s"
description = "%s"
kind = &"character"
rarity = %d
price_gems = %d
sprite_dir = "%s"
color_primary = %s
color_secondary = %s
color_accent = %s
glow = %.1f
preview = ExtResource("2_prev")
""" % (rd, sid, sk["name"], sk["desc"], sk["rarity"], sk["price"], rd.rstrip("/"),
       col(p), col(s), col(a), 0.6 if sk["rarity"] >= 4 else (0.3 if sk["rarity"] == 3 else 0.0))
    d = os.path.join(ROOT, "data", "skins")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "char_%s.tres" % sid), "w") as f:
        f.write(txt)


def main() -> None:
    args = sys.argv[1:]
    if "--compact" in args:   # recompresse les planches existantes sans re-rendre
        from PIL import Image
        for sid in SKINS:
            for anim in ANIMS:
                p = os.path.join(out_dir(sid), "hero_%s.png" % anim)
                compact_png(Image.open(p), p)
        return
    skins = args[args.index("--skins") + 1].split(",") if "--skins" in args else list(SKINS)
    os.makedirs(TMP_DIR, exist_ok=True)
    hero, cam = setup_scene()
    bpy.context.view_layer.update()
    feet = C.world_to_px(cam, (0, 0, 0))
    feet = (round(feet[0] / SS), round(feet[1] / SS))
    if "--blend" in args:
        hero.apply_skin(skins[0])
        hero.pose_idle(0)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(os.path.dirname(__file__), "hero.blend"))
        return
    if "--shop" in args:
        render_shop(hero, cam, skins)
        return
    if "--preview" in args:
        dirs = args[args.index("--preview") + 1].split(",")
        anims = args[args.index("--anim") + 1].split(",") if "--anim" in args else ["idle:0"]
        for d in dirs:
            hero.j["root"].rotation_euler = (0, 0, math.radians(DIRS[d]))
            for a in anims:
                an, i = a.split(":")
                hero.pose(an, int(i))
                for sid in skins:
                    hero.apply_skin(sid)
                    p = os.path.join(TMP_DIR, "prev_%s_%s_%s_%s.png" % (sid, an, d, i))
                    render_frame(p)
                    print("PREVIEW", p)
        print("FEET", feet, "HANDS", hand_pixels(hero, cam))
        return
    t0 = time.time()
    frames: dict = {sid: {} for sid in skins}
    for d, ang in DIRS.items():
        hero.j["root"].rotation_euler = (0, 0, math.radians(ang))
        for anim, (n, _f, _l) in ANIMS.items():
            for i in range(n):
                hero.pose(anim, i)
                for sid in skins:
                    hero.apply_skin(sid)
                    p = os.path.join(TMP_DIR, "%s_%s_%s_%d.png" % (sid, anim, d, i))
                    render_frame(p)
                    frames[sid][(anim, d, i)] = p
        print("DIR", d, "%.0fs" % (time.time() - t0), flush=True)
    hands = hand_pixels(hero, cam)
    for sid in skins:
        os.makedirs(out_dir(sid), exist_ok=True)
        assemble(sid, frames[sid])
        write_tres(sid)
        hero_px = measure_height(frames[sid][("idle", "s", 0)])
        if sid != "default" and os.path.exists(os.path.join(OUT_DEFAULT, "hero_meta.json")):
            # même échelle que le skin par défaut (accessoires de tête non comptés)
            with open(os.path.join(OUT_DEFAULT, "hero_meta.json")) as f:
                hero_px = int(json.load(f).get("hero_height_px", hero_px))
        write_meta(sid, feet, hero_px, hands)
        write_skin_tres(sid)
    render_shop(hero, cam, skins)
    hero.apply_skin("default")
    hero.pose_idle(0)
    hero.j["root"].rotation_euler = (0, 0, 0)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(os.path.dirname(__file__), "hero.blend"))
    print("DONE in %.0fs, feet=%s" % (time.time() - t0, feet))


if __name__ == "__main__":
    main()
