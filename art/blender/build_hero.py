"""Héros d'Exfil Rush (sans masque) : modélisation 3D scriptée + rendus 8 directions, multi-skins.

Usage (depuis la racine du projet) :
    python3 art/blender/build_hero.py                          # tout : 5 skins, planches, .tres, meta
    python3 art/blender/build_hero.py --skins default,neon     # seulement certains skins
    python3 art/blender/build_hero.py --preview s,e --anim idle:0,run:3 [--skins neon]
    python3 art/blender/build_hero.py --compact                # recompresse les planches existantes
    python3 art/blender/build_hero.py --blend                  # sauve seulement art/blender/hero.blend

Personnage chibi-héroïque : visage cartoon, casquette à l'envers, t-shirt, gilet tactique,
pantalon cargo, rangers, gants, petit sac à dos. Les pièces sont rigides, parentées à des
articulations (empties). Jambes en cinématique directe, bras en IK à deux segments (les mains
tiennent l'arme, dessinée par le jeu au point « main »).
Un seul jeu de poses : chaque pose est rendue une fois par skin (échange de matériaux et
d'accessoires), ce qui garde le temps de rendu raisonnable.
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
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DEFAULT = os.path.join(ROOT, "assets", "sprites", "hero3d")
OUT_SKINS = os.path.join(OUT_DEFAULT, "skins")
TMP_DIR = os.environ.get("RDM_TMP", "/tmp/rdm_hero_frames")

FRAME_W, FRAME_H = 128, 160   # cadre final (px) ; même échelle px/unité que l'ancien héros 160x160
SS = 2                        # sur-échantillonnage du rendu
ELEV = 48.0                   # plongée caméra (degrés)
ORTHO_H = 2.30                # hauteur visible (unités Blender) du cadre
CAM_TARGET_Z = 1.10
HEAD_SCALE = 1.48
HEAD_PITCH = -0.22          # tête relevée vers la caméra (visage lisible en plongée)
LEG = 0.80                  # facteur de longueur des jambes (chibi)
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
L_UP, L_LOW = 0.21, 0.235
SHOULDER = {"L": Vector((0.225, 0.0, 0.335)), "R": Vector((-0.225, 0.0, 0.335))}
# Mains au repos (prise à deux mains, devant le ventre, légèrement côté droit) — repère colonne.
HAND_R = Vector((-0.05, -0.31, 0.19))
HAND_L = Vector((0.035, -0.27, 0.21))

# ----------------------------------------------------------------------------- skins
# Chaque skin : couleurs (base, ombre, lumière ; None = calculée) par clef, accessoires visibles.
# Clef suffixée « ! » dans la valeur = matériau émissif (néon, lentilles).
BASE_PAL = {
    "skin": ("#f2b48c", "#b06c74", "#ffd8b4"),
    "hair": ("#5e3822", "#2a1424", "#8a5632"),
    "cap": ("#c8342c", "#561432", "#ee5a44"),
    "capb": ("#2e2c36", "#121226", "#4e4a58"),
    "tee": ("#e9e3d6", "#8e8aa8", "#fffaf0"),
    "vest": ("#62703e", "#26302e", "#8a9a56"),
    "vestd": ("#4c5832", "#1c2228", "#6c7a46"),
    "strap": ("#38362e", "#14141e", "#56524a"),
    "pants": ("#3f4b68", "#1a1e3a", "#5e6c8e"),
    "pocket": ("#35405c", "#161a34", "#4e5a7a"),
    "boot": ("#5c3c26", "#221424", "#84583a"),
    "sole": ("#26222a", "#0e0c16", "#3e3842"),
    "glove": ("#2e2c32", "#101020", "#4c4852"),
    "pack": ("#8c6a40", "#3a2428", "#b88c56"),
    "packd": ("#6a4c2e", "#2a1824", "#8e6840"),
    "roll": ("#3e6e8c", "#1a2a4a", "#5a96b4"),
    "belt": ("#3a2a22", "#160e1a", "#5a4234"),
    "metal": ("#b8b4a8", "#4a4a62", "#f0ece0"),
    "eye": ("#2a1a18", None, None),
    "white": ("#ffffff", None, None),
    "mouth": ("#7a2a2a", None, None),
    "brow": ("#4a2a1a", None, None),
    "acc1": ("#c8a060", "#5a3a30", "#f0cc88"),
    "acc2": ("#3a3a44", "#141420", "#5a5a66"),
    "glow": ("#ffffff!", None, None),
    "glow2": ("#ffffff!", None, None),
}

SKINS = {
    "default": {
        "name": "Recrue", "rarity": 0, "price": 0,
        "desc": "La tenue de départ : casquette rouge, gilet olive et sac de route.",
        "pal": {},
        "acc": {"cap"},
        "colors": ("#c8342c", "#62703e", "#3f4b68"),
    },
    "desert": {
        "name": "Désert", "rarity": 1, "price": 150,
        "desc": "Bandeau, lunettes de protection et chèche : prêt pour les tempêtes de sable.",
        "pal": {
            "hair": ("#3a2416", "#1a0e18", "#5a3a22"),
            "tee": ("#d6c29a", "#7e7488", "#f4e4bc"),
            "vest": ("#a8844e", "#4a3430", "#d0a86a"),
            "vestd": ("#8c6c40", "#3a2828", "#ac8a52"),
            "pants": ("#6e5c44", "#2c2230", "#927a5c"),
            "pocket": ("#5e4e3a", "#241c28", "#7c684e"),
            "boot": ("#9a744a", "#3e2a2a", "#c09662"),
            "pack": ("#b09468", "#4a3a36", "#d6b886"),
            "packd": ("#8a7050", "#3a2c2c", "#ac8e66"),
            "roll": ("#7a6a4a", "#30282a", "#9e8a62"),
            "acc1": ("#d8cbb0", "#7a6e80", "#fff4dc"),   # chèche / bandeau
            "acc2": ("#3c3a36", "#141420", "#5c5850"),   # monture des lunettes
            "glow": ("#ffb050!", None, None),            # verres ambrés
        },
        "acc": {"headband", "goggles", "shemagh"},
        "colors": ("#a8844e", "#d8cbb0", "#6e5c44"),
    },
    "night": {
        "name": "Nuit tactique", "rarity": 2, "price": 250,
        "desc": "Bonnet noir et jumelles de vision nocturne. Invisible… sauf les lentilles.",
        "pal": {
            "hair": ("#1c1a20", "#08080e", "#34303a"),
            "tee": ("#3c4252", "#161a2c", "#5a6274"),
            "vest": ("#25292f", "#0c0e18", "#3e444e"),
            "vestd": ("#1c1f25", "#08090f", "#30343c"),
            "strap": ("#1a1c20", "#06060c", "#30323a"),
            "pants": ("#2c303a", "#0e1020", "#464c5a"),
            "pocket": ("#24272f", "#0a0c18", "#3a3e48"),
            "boot": ("#1e1e24", "#08080e", "#36363e"),
            "glove": ("#18181c", "#06060c", "#2e2e34"),
            "pack": ("#2e323a", "#0e1020", "#4a505a"),
            "packd": ("#22252c", "#0a0c16", "#383c44"),
            "roll": ("#3a4a3e", "#141e1e", "#566a5a"),
            "belt": ("#1a1a1e", "#06060c", "#303036"),
            "acc1": ("#22242c", "#0a0a14", "#3a3c46"),   # bonnet
            "acc2": ("#3a3e46", "#121420", "#5a606a"),   # jumelles
            "glow": ("#48ff7a!", None, None),
        },
        "acc": {"beanie", "nvg"},
        "colors": ("#25292f", "#3c4252", "#48ff7a"),
    },
    "neon": {
        "name": "Néon", "rarity": 3, "price": 400,
        "desc": "Casque audio, bandes lumineuses et semelles fluo : la nuit t'appartient.",
        "pal": {
            "hair": ("#3ad8f0", "#1a5078", "#a0f4ff"),
            "cap": ("#e02c9a", "#4a0c50", "#ff6cc4"),
            "capb": ("#1e1a2e", "#0a0818", "#36304a"),
            "tee": ("#2a2440", "#100c24", "#443c60"),
            "vest": ("#2e2248", "#100a24", "#4a3a6c"),
            "vestd": ("#241a3a", "#0c081c", "#3a2c56"),
            "strap": ("#1a1428", "#08060e", "#2e2640"),
            "pants": ("#1e1a30", "#0a0818", "#36304e"),
            "pocket": ("#18142a", "#080614", "#2c2644"),
            "boot": ("#f0f0f8", "#7e7ea6", "#ffffff"),
            "glove": ("#1a1628", "#08060e", "#302a42"),
            "pack": ("#2a2242", "#0e0a22", "#463a66"),
            "packd": ("#201a34", "#0a0818", "#382e52"),
            "roll": ("#e02c9a", "#4a0c50", "#ff6cc4"),
            "acc2": ("#22203a", "#0a0818", "#3a3656"),   # casque audio
            "glow": ("#38f0ff!", None, None),
            "glow2": ("#ff44c8!", None, None),
            "sole": ("#38f0ff!", None, None),
        },
        "acc": {"cap", "headphones", "neon"},
        "colors": ("#2e2248", "#38f0ff", "#ff44c8"),
    },
    "gold": {
        "name": "Légende dorée", "rarity": 4, "price": 800,
        "desc": "Épaulières en or, médaillon et casquette dorée : la tenue des légendes de l'extraction.",
        "pal": {
            "hair": ("#6a4024", "#2a1420", "#94603a"),
            "cap": ("#e0b040", "#7a4a2c", "#fff0a0"),
            "capb": ("#f4efe2", "#9894b0", "#ffffff"),
            "tee": ("#2a2a36", "#0e0e1e", "#44444e"),
            "vest": ("#f2ecdc", "#9a96b2", "#ffffff"),
            "vestd": ("#e0b040", "#7a4a2c", "#fff0a0"),
            "strap": ("#c89a3a", "#6a3e2a", "#f0d070"),
            "pants": ("#26262e", "#0c0c18", "#40404a"),
            "pocket": ("#1e1e26", "#0a0a14", "#36363e"),
            "boot": ("#e0b040", "#7a4a2c", "#fff0a0"),
            "sole": ("#f2ecdc", "#9a96b2", "#ffffff"),
            "glove": ("#f2ecdc", "#9a96b2", "#ffffff"),
            "pack": ("#f2ecdc", "#9a96b2", "#ffffff"),
            "packd": ("#e0b040", "#7a4a2c", "#fff0a0"),
            "roll": ("#b02a30", "#4a0e28", "#e04a44"),
            "belt": ("#e0b040", "#7a4a2c", "#fff0a0"),
            "acc1": ("#e8b840", "#7a4a2c", "#fff4b0"),   # épaulières, médaillon
            "glow": ("#fff0a0!", None, None),
        },
        "acc": {"cap", "pauldrons", "medal"},
        "colors": ("#e0b040", "#f2ecdc", "#26262e"),
    },
}


def joint(name: str, parent, loc) -> bpy.types.Object:
    e = C.empty(name, loc, parent)
    e.rotation_mode = "XYZ"
    return e


def poly_bm(pts) -> bmesh.types.BMesh:
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in pts]
    bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    return bm


class Hero:
    def __init__(self) -> None:
        self.j: dict[str, bpy.types.Object] = {}
        self.parts: list[tuple[bpy.types.Object, str]] = []      # (objet, clef de matériau)
        self.acc: dict[str, list[bpy.types.Object]] = {}          # accessoire -> objets
        self.ph = C.toon("_placeholder", "#ff00ff")
        self.build()

    # ------------------------------------------------------------------ construction
    def part(self, name, bm, key, parent, smooth=True, acc: str | None = None, nofs=False):
        ob = C.mesh_obj(name, bm, self.ph, smooth=smooth, coll=C.nofs_collection() if nofs else None)
        ob.parent = parent
        self.parts.append((ob, key))
        if acc:
            self.acc.setdefault(acc, []).append(ob)
        return ob

    def decal(self, target, poly, key, name, lift=0.003, subdiv=3):
        ob = C.decal(target, poly, self.ph, name, lift=lift, subdiv=subdiv, coll=C.nofs_collection())
        if ob is not None:
            self.parts.append((ob, key))
        return ob

    def build(self) -> None:
        j = self.j
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["pelvis"] = pelvis = joint("pelvis", root, (0, 0, PZ))
        j["spine"] = spine = joint("spine", pelvis, (0, 0, 0.08))
        j["neck"] = neck = joint("neck", spine, (0, 0, 0.47))
        j["head"] = head = joint("head", neck, (0, 0, 0.0))
        head.scale = (HEAD_SCALE,) * 3
        self.build_legs(pelvis)
        self.build_torso(pelvis, spine)
        self.build_pack(spine)
        self.build_arms(spine)
        self.build_head(head, spine)

    def build_legs(self, pelvis) -> None:
        j = self.j
        for side, sx in (("L", 1), ("R", -1)):
            hip = j["hip" + side] = joint("hip" + side, pelvis, (0.110 * sx, 0, -0.02))
            knee = j["knee" + side] = joint("knee" + side, hip, (0, 0, -0.36 * LEG))
            self.part("thigh" + side, C.bm_xform(C.bm_cyl(12, 0.108, 0.092, 0.38),
                      loc=(0, 0, -0.17), scale=(1, 1, LEG)), "pants", hip)
            # poche cargo sur la cuisse (côté extérieur)
            self.part("cargo" + side, C.bm_xform(C.bm_box(0.05, 0.13, 0.13, bevel=0.015),
                      loc=(0.095 * sx, -0.005, -0.20 * LEG)), "pocket", hip)
            self.part("shin" + side, C.bm_xform(C.bm_cyl(12, 0.092, 0.082, 0.22 * LEG),
                      loc=(0, 0, LEG * -0.10)), "pants", knee)
            # ranger : tige, revers, pied, semelle
            self.part("bootShaft" + side, C.bm_xform(C.bm_cyl(12, 0.090, 0.098, 0.16 * LEG),
                      loc=(0, 0, LEG * -0.27)), "boot", knee)
            self.part("bootCuff" + side, C.bm_xform(C.bm_cyl(12, 0.096, 0.096, 0.03),
                      loc=(0, 0, LEG * -0.19)), "boot", knee)
            foot = C.bm_xform(C.bm_box(0.16, 0.26, 0.10, bevel=0.04), loc=(0, -0.055, -0.345 + 0.41 * (1 - LEG)))
            self.part("foot" + side, foot, "boot", knee)
            sole = C.bm_xform(C.bm_box(0.17, 0.27, 0.035, bevel=0.012), loc=(0, -0.055, -0.39 + 0.41 * (1 - LEG)))
            self.part("sole" + side, sole, "sole", knee)

    def build_torso(self, pelvis, spine) -> None:
        # bassin + ceinture
        self.part("hips", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, 0, -0.01),
                  scale=(0.205, 0.155, 0.14)), "pants", pelvis)
        self.part("belt", C.bm_xform(C.bm_cyl(16, 0.208, 0.208, 0.05), loc=(0, 0, 0.05),
                  scale=(1, 0.78, 1)), "belt", pelvis)
        self.part("buckle", C.bm_xform(C.bm_box(0.07, 0.03, 0.05, bevel=0.01),
                  loc=(0, -0.165, 0.05)), "metal", pelvis)
        # t-shirt (torse)
        torso = C.bm_loft([
            C.ellipse(0, 0, 0.00, 0.172, 0.130, 14),
            C.ellipse(0, 0.005, 0.15, 0.190, 0.140, 14),
            C.ellipse(0, 0.010, 0.29, 0.218, 0.150, 14),
            C.ellipse(0, 0.012, 0.39, 0.200, 0.138, 14),
            C.ellipse(0, 0.012, 0.46, 0.105, 0.090, 14),
        ])
        self.part("torso", torso, "tee", spine)
        self.part("collar", C.bm_xform(C.bm_torus(16, 6, 0.085, 0.022), loc=(0, 0.01, 0.455),
                  scale=(1, 0.92, 1)), "tee", spine)
        # gilet tactique (ouvert en haut, laisse voir le t-shirt aux épaules)
        vest = C.bm_loft([
            C.ellipse(0, 0.0, 0.02, 0.190, 0.148, 16),
            C.ellipse(0, 0.006, 0.15, 0.208, 0.158, 16),
            C.ellipse(0, 0.010, 0.29, 0.234, 0.168, 16),
            C.ellipse(0, 0.012, 0.385, 0.210, 0.154, 16),
        ], cap_start=False, cap_end=False)
        self.part("vest", vest, "vest", spine)
        # bretelles du gilet sur les épaules
        for sx in (1, -1):
            st = C.bm_tube(C.bezier((0.12 * sx, -0.14, 0.37), (0.15 * sx, -0.10, 0.47),
                                    (0.15 * sx, 0.08, 0.47), (0.12 * sx, 0.14, 0.37), 6),
                           [0.035] * 6, seg=6, flat=0.45, up=(0, 0, 1))
            self.part("vestStrap", st, "vest", spine)
        # poches ventrales + poche radio
        for k, x in enumerate((-0.095, 0.0, 0.095)):
            self.part("pouch%d" % k, C.bm_xform(C.bm_box(0.078, 0.05, 0.10, bevel=0.016),
                      loc=(x, -0.172, 0.10)), "vestd", spine)
            self.part("flap%d" % k, C.bm_xform(C.bm_box(0.082, 0.054, 0.025, bevel=0.008),
                      loc=(x, -0.176, 0.15)), "vest", spine)
        self.part("radio", C.bm_xform(C.bm_box(0.07, 0.05, 0.09, bevel=0.015),
                  loc=(0.10, -0.19, 0.28)), "vestd", spine)
        # bretelles du sac (devant)
        for sx in (1, -1):
            st = C.bm_tube(C.bezier((0.10 * sx, 0.16, 0.40), (0.12 * sx, 0.02, 0.50),
                                    (0.14 * sx, -0.17, 0.42), (0.14 * sx, -0.19, 0.24), 7),
                           [0.026] * 7, seg=6, flat=0.40, up=(0, 0, 1))
            self.part("packStrap", st, "strap", spine)
        # bande néon (skin néon)
        self.part("neonBand", C.bm_xform(C.bm_torus(20, 5, 0.215, 0.012), loc=(0, 0.008, 0.215),
                  scale=(1, 0.76, 1)), "glow", spine, acc="neon", nofs=True)
        self.part("neonBelt", C.bm_xform(C.bm_torus(20, 5, 0.211, 0.010), loc=(0, 0, 0.05),
                  scale=(1, 0.80, 1)), "glow2", pelvis, acc="neon", nofs=True)
        # épaulières dorées + médaillon (skin or)
        for sx in (1, -1):
            pad = C.bm_sphere(14, 9, 1.0)
            for v in pad.verts:
                if v.co.z < -0.2:
                    v.co.z = -0.2 + (v.co.z + 0.2) * 0.2
            self.part("pauldron", C.bm_xform(pad, loc=(0.24 * sx, 0.0, 0.37), rot=(0, 0.45 * sx, 0),
                      scale=(0.12, 0.12, 0.085)), "acc1", spine, acc="pauldrons")
        self.part("chain", C.bm_xform(C.bm_torus(18, 5, 0.12, 0.012), loc=(0, -0.03, 0.40),
                  rot=(0.55, 0, 0)), "acc1", spine, acc="medal")
        self.part("medal", C.bm_xform(C.bm_cyl(14, 0.045, 0.045, 0.02), loc=(0, -0.175, 0.31),
                  rot=(1.35, 0, 0)), "acc1", spine, acc="medal")
        # chèche autour du cou (skin désert)
        self.part("shemagh", C.bm_xform(C.bm_torus(18, 8, 0.12, 0.055), loc=(0, 0.0, 0.44),
                  scale=(1, 0.95, 0.8)), "acc1", spine, acc="shemagh")
        self.part("shemaghTail", C.bm_tube(C.bezier((0.05, -0.12, 0.43), (0.08, -0.17, 0.38),
                                                    (0.09, -0.18, 0.32), (0.07, -0.18, 0.27), 5),
                                           [0.05, 0.052, 0.05, 0.045, 0.03], seg=6, flat=0.4),
                  "acc1", spine, acc="shemagh")

    def build_pack(self, spine) -> None:
        j = self.j
        pk = j["pack"] = joint("pack", spine, (0, 0.17, 0.30))
        self.part("pack", C.bm_xform(C.bm_box(0.31, 0.16, 0.32, bevel=0.05, segs=3),
                  loc=(0, 0.06, -0.04)), "pack", pk)
        self.part("packFlap", C.bm_xform(C.bm_box(0.32, 0.17, 0.08, bevel=0.03),
                  loc=(0, 0.065, 0.10)), "packd", pk)
        self.part("packPocket", C.bm_xform(C.bm_box(0.20, 0.06, 0.13, bevel=0.025),
                  loc=(0, 0.15, -0.09)), "packd", pk)
        # tapis de sol roulé sur le dessus (lisible vu de haut)
        roll = C.bm_cyl(14, 0.065, 0.065, 0.36)
        C.bm_xform(roll, loc=(0, 0.07, 0.19), rot=(0, math.pi / 2, 0))
        self.part("packRoll", roll, "roll", pk)
        for sx in (1, -1):
            self.part("rollStrap", C.bm_xform(C.bm_cyl(12, 0.069, 0.069, 0.025), loc=(0.11 * sx, 0.07, 0.19),
                      rot=(0, math.pi / 2, 0)), "strap", pk)
        self.part("neonPack", C.bm_xform(C.bm_box(0.24, 0.02, 0.025), loc=(0, 0.185, -0.02)),
                  "glow", pk, acc="neon", nofs=True)

    def build_arms(self, spine) -> None:
        j = self.j
        for side, sx in (("L", 1), ("R", -1)):
            ua = j["ua" + side] = C.empty("ua" + side, SHOULDER[side], spine)
            ua.rotation_mode = "QUATERNION"
            fa = j["fa" + side] = C.empty("fa" + side, (0, 0, 0), spine)
            fa.rotation_mode = "QUATERNION"
            # bras : manche courte, bras nu, coude
            self.part("shoulder" + side, C.bm_xform(C.bm_sphere(12, 8, 0.085), loc=(0, 0, -0.01)),
                      "tee", ua)
            self.part("sleeve" + side, C.bm_xform(C.bm_cyl(12, 0.086, 0.078, 0.12), loc=(0, 0, -0.05)),
                      "tee", ua)
            self.part("uarm" + side, C.bm_xform(C.bm_cyl(10, 0.060, 0.054, 0.16), loc=(0, 0, -0.13)),
                      "skin", ua)
            self.part("elbow" + side, C.bm_sphere(10, 7, 0.054), "skin", fa)
            self.part("farm" + side, C.bm_xform(C.bm_cyl(10, 0.052, 0.048, 0.16), loc=(0, 0, -0.08)),
                      "skin", fa)
            self.part("gcuff" + side, C.bm_xform(C.bm_cyl(10, 0.060, 0.064, 0.05), loc=(0, 0, -0.165)),
                      "glove", fa)
            hand = C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, 0, -L_LOW + 0.01), scale=(0.064, 0.060, 0.072))
            self.part("hand" + side, hand, "glove", fa)

    def build_head(self, head, spine) -> None:
        self.part("neck", C.bm_xform(C.bm_cyl(10, 0.065, 0.07, 0.10), loc=(0, 0.01, 0.46)), "skin", spine)
        # crâne : sphère un peu large aux joues (visage rond)
        sk = C.bm_sphere(22, 16, 1.0)
        for v in sk.verts:
            x, y, z = v.co
            if z < 0:
                x *= 1.0 + 0.06 * (-z) - 0.22 * (-z) ** 2
                y *= 1.0 - 0.10 * (-z)
            v.co = Vector((x * 0.198, y * 0.186, z * 0.205))
        for v in sk.verts:
            v.co += Vector((0, 0, 0.215))
        skull = self.part("skull", sk, "skin", head)
        for sx in (1, -1):
            self.part("ear", C.bm_xform(C.bm_sphere(10, 7, 1.0), loc=(0.192 * sx, 0.015, 0.20),
                      scale=(0.030, 0.042, 0.050)), "skin", head)
        self.part("nose", C.bm_xform(C.bm_sphere(10, 7, 1.0), loc=(0, -0.186, 0.165),
                  scale=(0.030, 0.024, 0.026)), "skin", head)
        # visage (décalques) : grands yeux, reflets, sourcils, sourire
        for sx in (1, -1):
            ex, ez = 0.078 * sx, 0.200
            eye = [(ex + 0.040 * math.cos(a), ez + 0.056 * math.sin(a))
                   for a in (2 * math.pi * i / 14 for i in range(14))]
            self.decal(skull, eye, "eye", "eye", lift=0.003)
            hl = [(ex + 0.012 * sx * 0 + 0.010 + 0.012 * math.cos(a), ez + 0.020 + 0.014 * math.sin(a))
                  for a in (2 * math.pi * i / 10 for i in range(10))]
            self.decal(skull, hl, "white", "eyeHL", lift=0.005, subdiv=2)
            bw = [(0.035 * sx, 0.272), (0.112 * sx, 0.285), (0.115 * sx, 0.262), (0.037 * sx, 0.252)]
            if sx < 0:
                bw.reverse()
            self.decal(skull, bw, "brow", "brow", lift=0.004, subdiv=2)
        mouth = []
        for i in range(9):
            t = i / 8
            a = math.pi * (1.15 + 0.7 * t)
            mouth.append((0.048 * math.cos(a), 0.118 + 0.030 * math.sin(a) + 0.030))
        for i in range(8, -1, -1):
            t = i / 8
            a = math.pi * (1.15 + 0.7 * t)
            mouth.append((0.040 * math.cos(a), 0.118 + 0.020 * math.sin(a) + 0.034))
        self.decal(skull, mouth, "mouth", "mouth", lift=0.004, subdiv=2)
        # cheveux : masse arrière + mèches sous la casquette
        hm = C.bm_sphere(18, 12, 1.0)
        for v in hm.verts:
            x, y, z = v.co
            v.co = Vector((x * 0.204, y * 0.194 + 0.022, z * 0.185 + 0.235))
            # dégage le visage : l'avant bas rentre dans le crâne
            if v.co.y < -0.06 and v.co.z < 0.31:
                v.co.y = -0.06 + (v.co.y + 0.06) * 0.2
        self.part("hair", hm, "hair", head)
        for k, (x, ln, ang) in enumerate(((-0.08, 0.075, -0.35), (-0.015, 0.085, 0.05),
                                          (0.05, 0.075, 0.40), (0.11, 0.06, 0.6))):
            p0 = (x, -0.15, 0.345)
            p3 = (x + ln * math.sin(ang) * 0.6, -0.20, 0.345 - ln)
            pts = C.bezier(p0, (x, -0.19, 0.345), (p3[0], -0.215, 0.32 - ln * 0.5), p3, 5)
            self.part("bang", C.bm_tube(pts, [0.045, 0.045, 0.035, 0.022, 0.004], seg=6, flat=0.5,
                                        up=(0, 1, 0)), "hair", head)
        # épis sur le dessus (visibles sans casquette)
        for k, (x, y) in enumerate(((-0.06, -0.02), (0.05, 0.0), (0.0, 0.08), (-0.10, 0.10), (0.10, 0.09))):
            pts = C.bezier((x, y, 0.36), (x * 1.2, y + 0.03, 0.40), (x * 1.5, y + 0.07, 0.42),
                           (x * 1.8, y + 0.11, 0.425), 4)
            self.part("spike", C.bm_tube(pts, [0.075, 0.055, 0.03, 0.004], seg=6), "hair", head,
                      acc="spikes")

        # casquette à l'envers
        dome = C.bm_sphere(20, 12, 1.0)
        for v in dome.verts:
            if v.co.z < -0.05:
                v.co.z = -0.05
        C.bm_xform(dome, loc=(0, 0.012, 0.27), rot=(-0.20, 0, 0), scale=(0.222, 0.214, 0.180))
        self.part("capDome", dome, "cap", head, acc="cap")
        self.part("capButton", C.bm_xform(C.bm_sphere(8, 6, 0.022), loc=(0, 0.04, 0.435)), "capb",
                  head, acc="cap")
        brim = C.bm_loft([
            [(-0.13, 0.17, 0.0), (0.13, 0.17, 0.0), (0.13, 0.17, 0.022), (-0.13, 0.17, 0.022)],
            [(-0.14, 0.30, -0.035), (0.14, 0.30, -0.035), (0.14, 0.30, -0.013), (-0.14, 0.30, -0.013)],
            [(-0.10, 0.36, -0.055), (0.10, 0.36, -0.055), (0.10, 0.36, -0.035), (-0.10, 0.36, -0.035)],
        ])
        C.bm_xform(brim, loc=(0, 0, 0.25))
        self.part("capBrim", brim, "capb", head, smooth=False, acc="cap")
        # ouverture de réglage à l'avant (bandeau sombre)
        self.part("capStrap", C.bm_xform(C.bm_box(0.11, 0.03, 0.035, bevel=0.01), loc=(0, -0.19, 0.30),
                  rot=(-0.4, 0, 0)), "capb", head, acc="cap")

        # bandeau + lunettes (désert)
        self.part("headband", C.bm_xform(C.bm_torus(22, 7, 0.200, 0.026), loc=(0, 0.01, 0.295),
                  rot=(-0.15, 0, 0), scale=(1, 0.97, 1)), "acc1", head, acc="headband")
        for k, sx in enumerate((1, -1)):
            tail = C.bm_tube(C.bezier((0.02 * sx, 0.20, 0.30), (0.06 * sx, 0.27, 0.27),
                                      (0.09 * sx, 0.30, 0.20), (0.11 * sx, 0.31, 0.13), 5),
                             [0.03, 0.032, 0.03, 0.026, 0.02], seg=6, flat=0.4)
            self.part("bandTail", tail, "acc1", head, acc="headband")
        for sx in (1, -1):
            lens = C.bm_cyl(14, 0.050, 0.046, 0.04)
            C.bm_xform(lens, loc=(0.07 * sx, -0.165, 0.34), rot=(math.pi / 2 - 0.65, 0, 0))
            self.part("goggleRim", lens, "acc2", head, acc="goggles")
            gl = C.bm_cyl(14, 0.036, 0.036, 0.01)
            C.bm_xform(gl, loc=(0.07 * sx, -0.185, 0.355), rot=(math.pi / 2 - 0.65, 0, 0))
            self.part("goggleLens", gl, "glow", head, acc="goggles", nofs=True)

        # bonnet + jumelles de vision nocturne (nuit)
        bn = C.bm_sphere(20, 12, 1.0)
        for v in bn.verts:
            if v.co.z < -0.15:
                v.co.z = -0.15
        C.bm_xform(bn, loc=(0, 0.02, 0.29), rot=(-0.25, 0, 0), scale=(0.218, 0.212, 0.19))
        self.part("beanie", bn, "acc1", head, acc="beanie")
        self.part("beanieCuff", C.bm_xform(C.bm_torus(22, 7, 0.205, 0.035), loc=(0, 0.03, 0.27),
                  rot=(-0.25, 0, 0)), "acc1", head, acc="beanie")
        self.part("nvgMount", C.bm_xform(C.bm_box(0.08, 0.05, 0.06, bevel=0.012), loc=(0, -0.19, 0.36),
                  rot=(-0.4, 0, 0)), "acc2", head, acc="nvg")
        for sx in (1, -1):
            tb = C.bm_cyl(12, 0.032, 0.036, 0.10)
            C.bm_xform(tb, loc=(0.045 * sx, -0.23, 0.39), rot=(math.pi / 2 - 0.9, 0, 0))
            self.part("nvgTube", tb, "acc2", head, acc="nvg")
            ln = C.bm_cyl(12, 0.026, 0.026, 0.01)
            C.bm_xform(ln, loc=(0.045 * sx, -0.27, 0.42), rot=(math.pi / 2 - 0.9, 0, 0))
            self.part("nvgLens", ln, "glow", head, acc="nvg", nofs=True)

        # casque audio (néon)
        band = C.bm_tube([(0.20 * math.cos(a), 0.02, 0.22 + 0.27 * math.sin(a))
                          for a in (math.pi * i / 10 for i in range(11))], [0.022] * 11, seg=6,
                         up=(0, 1, 0))
        self.part("hpBand", band, "acc2", head, acc="headphones")
        for sx in (1, -1):
            cup = C.bm_cyl(14, 0.07, 0.07, 0.05)
            C.bm_xform(cup, loc=(0.205 * sx, 0.02, 0.20), rot=(0, math.pi / 2, 0))
            self.part("hpCup", cup, "acc2", head, acc="headphones")
            ring = C.bm_torus(14, 5, 0.05, 0.012)
            C.bm_xform(ring, loc=(0.235 * sx, 0.02, 0.20), rot=(0, math.pi / 2, 0))
            self.part("hpRing", ring, "glow2", head, acc="headphones", nofs=True)

    # ------------------------------------------------------------------ skins
    def apply_skin(self, sid: str) -> None:
        sk = SKINS[sid]
        pal = dict(BASE_PAL)
        pal.update(sk["pal"])
        mats = {}
        for key, (b, s, li) in pal.items():
            name = "%s_%s" % (sid, key)
            if b.endswith("!"):
                mats[key] = C.toon(name, b[:-1], emit=1.0)
            elif key in ("eye", "white", "mouth", "brow"):
                mats[key] = C.toon(name, b, s, li, rim=0.0, band=0.2)
            else:
                mats[key] = C.toon(name, b, s, li, rim=0.30 if key != "skin" else 0.22)
        for ob, key in self.parts:
            ob.data.materials[0] = mats[key]
        visible = sk["acc"]
        for acc, obs in self.acc.items():
            on = acc in visible or (acc == "spikes" and not ({"cap", "beanie"} & visible))
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
        self.j["neck"].location = (0, 0, 0.47)
        self.j["pack"].location = (0, 0.17, 0.30)

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
    Image.open(frames[("idle", "s", 0)]).save(os.path.join(od, "preview.png"), optimize=True)


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
       col(p), col(s), col(a), 0.6 if sk["rarity"] >= 3 else 0.0)
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
    hero.apply_skin("default")
    hero.pose_idle(0)
    hero.j["root"].rotation_euler = (0, 0, 0)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(os.path.dirname(__file__), "hero.blend"))
    print("DONE in %.0fs, feet=%s" % (time.time() - t0, feet))


if __name__ == "__main__":
    main()
