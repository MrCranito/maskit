"""Bestiaire du Carnaval hanté (« Le parc maudit ») : modélisation 3D scriptée, rigs, animations,
rendus 8 directions, planches compactes (atlas rogné) + SpriteFrames + méta JSON.

Réutilise le pipeline générique du centre commercial (art/blender/bestiary/mall/build_mall_bestiary.py :
rig humanoïde à IK 2 os, rendu, empaquetage, méta), lui-même aligné sur le héros et les hors-la-loi
(art/blender/build_enemies.py, rdm_common.py) : caméra orthographique 3/4 à 48°, matériaux toon
peints, contour Freestyle, même densité de pixels et même échelle monde (WORLD_PER_PX).
Ambiance de la planche : fête foraine de nuit, néons violets et rouges (accents émissifs lisibles
sur mobile).

Usage (depuis la racine du projet ; rendus : passer par le verrou flock du projet) :
    flock /home/claude/.blender_render.lock python3 art/blender/bestiary/carnival/build_cv_bestiary.py
    ... --kinds cv_lost_clown,cv_circus_dog
    ... --preview s,se --anim idle:0,attack:3 --kinds cv_lost_clown     # aperçu (RDM_CV_TMP)
    ... --repack --kinds cv_lost_clown                                  # atlas + méta depuis les rendus
    ... --sheet                                                         # planche de présentation

Bestiaire (ids) :
    cv_lost_clown        Clown égaré : crâne chauve, touffes rousses, collerette tricolore, ballons orange et noir
    cv_acrobat           Acrobate sanguinaire : bouffon violet / rouge, masque blanc, perche à faucille
    cv_circus_dog        Chien de cirque : molosse-hyène gris, caparaçon orangé, épines, gueule béante
    cv_ghost_carousel    Manège fantôme : cheval de bois gris lavande, crinière sombre, sur sa barre dorée
    cv_penumbra          Pénombre : capuche pointue, yeux orangés, cape en lambeaux, longue lame, ballons
    cv_big_plush         Grosse peluche : ours brun-rouge possédé, collerette à pétales, cœur cousu
    cv_fairground_being  L'Être forain (élite) : haut-de-forme, redingote noire, gilet incandescent, canne
    cv_fire_clown        Le Clown de feu (élite) : chevelure de flammes, visage blanc, boule de feu
    cv_circus_king       Le Roi du cirque (boss) : couronne, triple collerette, sceptre, grande roue de feu

Aperçu d'évaluation (rendu ×2 conservé) : ... --hipreview s,se --anim idle:0 --kinds cv_acrobat

Animations (8 directions) : idle, run, attack, hit, death.
attack : images 0-2 = élan (l'image 2 est tenue pendant le télégraphe), 3 = coup / tir, 4-5 = retour.
death : la dernière image = cadavre au sol (réutilisée par le jeu).
"""
from __future__ import annotations

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "mall")))
import build_mall_bestiary as M  # noqa: E402

C = M.C
bpy = M.bpy
Vector = M.Vector
Euler = M.Euler
joint, qjoint, ik2, smooth, corpse_twist, DOWN = M.joint, M.qjoint, M.ik2, M.smooth, M.corpse_twist, M.DOWN

M.CAPT_DIR = os.path.join(M.ROOT, "docs", "bestiaire", "captures", "carnival")
M.TMP_DIR = os.environ.get("RDM_CV_TMP", "/tmp/rdm_cv_bestiary")
# Nuit de fête foraine : lumière rosée un peu chaude.
C.WARM = (1.07, 0.90, 1.00)

# ----------------------------------------------------------------------------- matériaux
RUFF = {"ruff_a": ("#f0d050", "#6a3a3a", "#fff2a0"), "ruff_b": ("#c8222e", "#4a0820", "#f04a4a")}

SPEC: dict[str, dict] = {
    "cv_lost_clown": {
        "name": "Clown égaré", "rig": "human", "frame": 192, "scale": 1.02, "head": 1.30, "leg": 0.78,
        "torso": (1.10, 1.00), "arm": 1.02, "arm_len": 1.10, "hunch": 0.36, "belly": 0.3, "fps_run": 11,
        "top_key": "costume", "sleeve_key": "jacket", "shoulder_key": "jacket", "hand_key": "glove",
        "mats": {
            "ruff_a": ("#eea43a", "#6a3018", "#ffd27a"),
            "ruff_b": ("#c0262a", "#46081a", "#f05040"),
            "ruff_c": ("#7a3a8a", "#240a36", "#a860c0"),
            "face": ("#ddd4d2", "#4e3e5e", "#f8f2f0"),
            "skin": ("#ddd4d2", "#4e3e5e", "#f8f2f0"),
            "nose": ("#e01a2a", "#5a0618", "#ff5a5a"),
            "lips": ("#7a0818", "#2a0208", "#b01a2a"),
            "makeup": ("#1a0e18", "#08040a", "#2e1a2a"),
            "hair": ("pat", [("#b8381e", "#440a14", "#e0602a"), ("#962a1a", "#360812", "#c84a22")], 9.0),
            "costume": ("pat", [("#c42a22", "#46081e", "#ee5a3a"), ("#e8862a", "#5a2410", "#ffb04a")], 3.0),
            "jacket": ("pat", [("#5e5258", "#1a1220", "#8a7c84"), ("#4a3e46", "#140c18", "#6e6068")], 6.0),
            "pants": ("pat", [("#463a40", "#140c14", "#6a5a62"), ("#3a2e36", "#100810", "#5a4a52")], 6.0),
            "shoe": ("#a01a22", "#3a0612", "#d83a3a"),
            "glove": ("#b02a26", "#3e0614", "#e04a3a"),
            "blood": ("#8a0a18", "#2e0208", "#c01a26"),
            "pompom": ("#f2eee6", "#7a7090", "#ffffff"),
            "eye_glow": "!#fff0c0",
            "balloon_a": ("#e8661c", "#5a1a08", "#ffa050"),
            "balloon_b": ("#2a2430", "#0a060e", "#6a5a78"),
            "string": ("#d8d0c8", "#5a5060", "#ffffff"),
        },
    },
    "cv_acrobat": {
        "name": "Acrobate sanguinaire", "rig": "human", "frame": 192, "scale": 1.04, "head": 1.20, "leg": 0.98,
        "torso": (0.82, 0.78), "arm": 0.80, "arm_len": 1.22, "hunch": 0.30, "fps_run": 16, "stride": 1.0,
        "top_key": "suit_b", "sleeve_key": "suit_a", "shoulder_key": "suit_a", "pants_key": "tights",
        "hand_key": "glove",
        "mats": {
            "suit_a": ("#5a1e4a", "#1e0618", "#8a3a72"),
            "suit_b": ("#e6d8c0", "#6a5468", "#fff6e6"),
            "tights": ("pat", [("#b8642c", "#4a1a14", "#e08a46"), ("#8a4220", "#30100c", "#b0602e")], 5.0),
            "tights_b": ("#4a1a40", "#160410", "#723262"),
            "hat_a": ("#6a2c96", "#200a36", "#9c58c8"),
            "hat_b": ("#b81e2c", "#40061a", "#ee4a4a"),
            "diamond": ("#b01a2a", "#3e0412", "#e03a40"),
            "mask": ("#e8e0d4", "#6a5a72", "#ffffff"),
            "skin": ("#e8e0d4", "#6a5a72", "#ffffff"),
            "makeup": ("#140a18", "#060208", "#2a1a30"),
            "lips": ("#b0101e", "#3a0210", "#e02a3a"),
            "glove": ("#2a1e30", "#0a060e", "#46364e"),
            "shoe": ("#3a1a30", "#0e040c", "#5a3050"),
            "bell": ("#e8b830", "#6a3a18", "#fff090"),
            "blade": ("#a8aec0", "#343a52", "#eef2fa"),
            "blood": ("#8a0a1c", "#300210", "#c01a2a"),
            "pole": ("#8a5a32", "#2a140c", "#b88050"),
            "eye_glow": "!#ff2a3a",
        },
    },
    "cv_circus_dog": {
        "name": "Chien de cirque", "rig": "quad", "frame": 192, "scale": 1.34, "fps_run": 17,
        "height": 0.52, "length": 0.70, "girth": (0.22, 0.22), "leg": (0.28, 0.29), "hip_x": 0.15,
        "neck_len": 0.18, "head_len": 0.30, "leg_r": 0.08, "jaw_idle": 0.75,
        "profile": [(0.00, 0.55, 0.60, 0.00), (0.12, 0.80, 0.82, 0.01), (0.35, 0.86, 0.90, 0.02), (0.60, 1.08, 1.10, 0.04),
                    (0.80, 1.22, 1.22, 0.06), (0.94, 1.08, 1.06, 0.06), (1.0, 0.62, 0.62, 0.05)],
        "mats": {
            "fur": ("pat", [("#857668", "#2a1e22", "#b0a090"), ("#64564c", "#1e1418", "#8a7a6c"),
                            ("#a06a42", "#2e1812", "#c88a52")], 9.0),
            "fur_dark": ("#46383a", "#140c10", "#665656"),
            "belly": ("#8a7a7e", "#2e2430", "#b0a0a4"),
            "muzzle": ("#9a8c84", "#2e2428", "#c4b6aa"),
            "gum": ("#b01e2a", "#3e0610", "#e04a4a"),
            "maw": ("#3a0610", "#120204", "#5a1018"),
            "armor": ("pat", [("#b0641e", "#3e1a0c", "#e0943e"), ("#7a3e16", "#2a1008", "#a8602a")], 12.0),
            "brass": ("#e0a83a", "#5a3218", "#ffe08a"),
            "spike": ("#c86a72", "#4a1a26", "#f09aa0"),
            "eye_glow": "!#ff8a1a",
        },
    },
    "cv_ghost_carousel": {
        "name": "Manège fantôme", "rig": "carousel", "frame": 224, "scale": 1.20, "fps_run": 10,
        "height": 0.80, "length": 0.84, "girth": (0.20, 0.24), "leg": (0.27, 0.27), "hip_x": 0.12, "leg_r": 0.062,
        "neck_len": 0.52, "head_len": 0.44,
        "mats": {
            "coat": ("pat", [("#aea2b8", "#3e3452", "#dcd2e6"), ("#9a8ea8", "#342a48", "#c8bcd6"),
                             ("#c4bacc", "#4a405e", "#ece4f4")], 5.0),
            "fur": ("pat", [("#aea2b8", "#3e3452", "#dcd2e6"), ("#9a8ea8", "#342a48", "#c8bcd6")], 5.0),
            "fur_dark": ("#8a7e98", "#2a2240", "#b0a4c0"),
            "belly": ("#aea2b8", "#3e3452", "#dcd2e6"),
            "muzzle": ("#7e7290", "#261e38", "#a498b4"),
            "swirl": ("#e2dcea", "#6a6080", "#ffffff"),
            "mane": ("pat", [("#4e4660", "#14101e", "#726a86"), ("#3a3248", "#0e0a16", "#5a5270")], 7.0),
            "saddle": ("#6a1a24", "#24060c", "#962a32"),
            "gold": ("#d89a3a", "#5a3018", "#ffd88a"),
            "ribbon": ("#d0461e", "#4a120a", "#ff7a3a"),
            "crack": ("#3a2e4a", "#100818", "#5a4a6a"),
            "socket": ("#1e1626", "#08040c", "#30243a"),
            "eye_glow": "!#ff9a3a",
            "neon": "!#ff8a2a",
            "neon_red": "!#ff5a2a",
            "gum": ("#4a3a5a", "#140a1e", "#6a5a7a"),
            "brass": ("#d89a3a", "#5a3018", "#ffd88a"),
        },
    },
    "cv_penumbra": {
        "name": "Pénombre", "rig": "human", "frame": 192, "scale": 1.08, "head": 1.02, "leg": 0.86,
        "torso": (1.18, 0.96), "arm": 0.92, "arm_len": 1.20, "hunch": 0.30, "fps_run": 16,
        "top_key": "cloak", "sleeve_key": "cloak", "hand_key": "claw_hand",
        "mats": {
            "cloak": ("pat", [("#3a2c3e", "#0c0610", "#5a4660"), ("#2c2232", "#08040c", "#46384e"),
                              ("#4a3036", "#120808", "#6a4a4e")], 6.0),
            "cloak_in": ("#160c1a", "#060208", "#2a1a30"),
            "face": ("#08060c", None, None),
            "skin": ("#2a2232", "#0a060e", "#443850"),
            "claw_hand": ("#2a2232", "#0a060e", "#443850"),
            "pants": ("#1e1622", "#08040a", "#342a3a"),
            "shoe": ("#1e1622", "#08040a", "#342a3a"),
            "blade": ("#6e7486", "#22263a", "#c0c6d6"),
            "blade_edge": "!#ff5a3a",
            "ember": "!#ff8a2a",
            "brass": ("#c88a3a", "#4a2a14", "#f0b860"),
            "eye_glow": "!#ff5a1a",
            "balloon_a": ("#d8642a", "#4a1a0a", "#ff9a5a"),
            "balloon_b": ("#a8202a", "#3a0610", "#e04a4a"),
            "string": ("#9890a0", "#3a3444", "#d0c8d8"),
            "wisp": "!#7a3aff",
        },
    },
    "cv_big_plush": {
        "name": "Grosse peluche", "rig": "human", "frame": 256, "scale": 1.46, "head": 1.66, "leg": 0.66,
        "torso": (1.50, 1.36), "arm": 1.62, "arm_len": 0.96, "hunch": 0.16, "belly": 0.9, "fps_run": 10,
        "stride": 0.55, "top_key": "fur", "sleeve_key": "fur", "pants_key": "fur", "hand_key": "fur",
        "shin_key": "fur",
        "mats": {
            "ruff_a": ("#c8955a", "#4a2a1a", "#ecc088"),
            "ruff_b": ("#9a4e26", "#36140a", "#c87040"),
            "fur": ("pat", [("#8e4a42", "#2e0e18", "#b8685a"), ("#743a36", "#260a14", "#9a5248"),
                            ("#a2584a", "#341220", "#c87a66")], 11.0),
            "skin": ("pat", [("#8e4a42", "#2e0e18", "#b8685a"), ("#743a36", "#260a14", "#9a5248")], 11.0),
            "cream": ("#d2b08e", "#6a4a46", "#f0d4b0"),
            "nose": ("#2a1418", "#0a0406", "#4a2a2e"),
            "button": ("#1a1418", "#06040a", "#3e343c"),
            "stitch": ("#2a1a26", "#0a0408", "#46303e"),
            "stuffing": ("#f4efe6", "#8a8098", "#ffffff"),
            "heart": ("#c01a2a", "#46061a", "#f04a4a"),
            "shoe": ("pat", [("#8e4a42", "#2e0e18", "#b8685a"), ("#743a36", "#260a14", "#9a5248")], 11.0),
            "eye_glow": "!#ffe8b0",
            "claw": ("#efe4d0", "#6a5a6a", "#ffffff"),
        },
    },
    "cv_fairground_being": {
        "name": "L'Être forain", "rig": "human", "frame": 224, "scale": 1.24, "head": 1.06, "leg": 0.92,
        "torso": (1.22, 1.02), "arm": 1.06, "arm_len": 1.12, "hunch": 0.14, "fps_run": 13,
        "top_key": "vest", "sleeve_key": "coat", "shoulder_key": "coat", "hand_key": "glove",
        "mats": {
            "skin": ("#5e5468", "#1a1226", "#8a7e94"),
            "coat": ("pat", [("#262028", "#08060a", "#463c48"), ("#1e1a22", "#060408", "#3a3240")], 5.0),
            "coat_in": ("#3a2a30", "#100a0c", "#5a4248"),
            "vest": ("pat", [("#c0461a", "#4a120a", "#f07a2a"), ("#8a2a12", "#320a06", "#c04a1a")], 6.0),
            "shirt": ("#d8c8b8", "#6a5a5a", "#fff0e0"),
            "gold": ("#e0aa3a", "#6a3a18", "#fff0a0"),
            "hat": ("#1a141e", "#060408", "#34283a"),
            "hat_band": "!#ff7a2a",
            "pants": ("pat", [("#2a2230", "#0a080e", "#463a50"), ("#3a2a40", "#0e0a14", "#58465e")], 9.0),
            "shoe": ("#1a141e", "#060408", "#34283a"),
            "glove": ("#2a2028", "#0a060a", "#463a44"),
            "cane": ("#2a1a14", "#0a0604", "#4a3226"),
            "eye_glow": "!#ffa030",
            "crack": "!#ff7a20",
            "lips": ("#2a0a12", "#0e0206", "#4a1a22"),
            "neon": "!#ff6a2a",
        },
    },
    "cv_fire_clown": {
        "name": "Le Clown de feu", "rig": "human", "frame": 224, "scale": 1.18, "head": 1.24, "leg": 0.82,
        "torso": (1.16, 1.04), "arm": 1.10, "arm_len": 1.08, "hunch": 0.30, "belly": 0.3, "fps_run": 12,
        "top_key": "costume", "sleeve_key": "costume", "hand_key": "glove",
        "mats": {
            "face": ("#e8ddd6", "#6a4a5a", "#ffffff"),
            "skin": ("#e8ddd6", "#6a4a5a", "#ffffff"),
            "soot": ("#1e1216", "#080406", "#3a2428"),
            "nose": ("#c8301a", "#4a0a10", "#ff6a3a"),
            "lips": ("#2a0a0e", "#0e0204", "#4a1418"),
            "costume": ("pat", [("#2e2024", "#0a0608", "#4e3a3e"), ("#3e2a26", "#100808", "#5e423a"),
                                ("#a0401a", "#3a1208", "#d06a2a")], 5.0),
            "pants": ("pat", [("#2a1a1e", "#0a0608", "#4a3034"), ("#3a2026", "#100608", "#5a3a3e")], 6.0),
            "shoe": ("#2a1a1e", "#0a0608", "#4a3034"),
            "glove": ("#2a1a1e", "#0a0608", "#4a3034"),
            "ruff_a": ("#e0782a", "#5a2410", "#ffb060"),
            "ruff_b": ("#3a2426", "#0e0608", "#5a3a3a"),
            "fire": "!#ff7a14",
            "fire_core": "!#ffe060",
            "fire_edge": "!#d8280c",
            "ember": "!#ff5a10",
            "eye_glow": "!#ffe040",
            "tooth": ("#f2e4c4", "#7a6a5a", "#ffffff"),
        },
    },
    "cv_circus_king": {
        "name": "Le Roi du cirque", "rig": "human", "frame": 384, "scale": 2.05, "head": 1.45, "leg": 0.82,
        "torso": (1.34, 1.14), "arm": 1.30, "arm_len": 1.10, "hunch": 0.10, "belly": 0.5, "fps_run": 10,
        "stride": 0.6, "cam_dz": 0.15, "out_scale": 0.72,
        "anims": {"idle": (4, 6, True), "run": (6, 10, True), "death": (6, 9, False)},
        "top_key": "robe", "sleeve_key": "robe", "hand_key": "glove",
        "mats": {
            "face": ("#ece4e4", "#6a5a78", "#ffffff"),
            "skin": ("#ece4e4", "#6a5a78", "#ffffff"),
            "nose": ("#c81a2a", "#4a0618", "#ff5a5a"),
            "lips": ("#5a0614", "#200208", "#8a1424"),
            "makeup": ("#1a1020", "#08040c", "#30203a"),
            "hair": ("pat", [("#b8b0c8", "#4a4060", "#e2dcf0"), ("#9a90b0", "#3a3050", "#c8c0dc")], 9.0),
            "robe": ("pat", [("#3a3044", "#100a16", "#5e5068"), ("#2e2636", "#0c0812", "#4c4058")], 5.0),
            "armor": ("#4a4252", "#141020", "#7a7084"),
            "cape_in": ("#6a0e1e", "#22040a", "#9a2030"),
            "ermine": ("#e6e0ec", "#6a6080", "#ffffff"),
            "spot": ("#16121a", "#060408", "#2a2430"),
            "gold": ("#e2ac3a", "#6a3a18", "#fff0a0"),
            "jewel": "!#ff2a3a",
            "ruff_a": ("#e8e2ee", "#6a6080", "#ffffff"),
            "ruff_b": ("#8a5ab0", "#2a1040", "#b888dc"),
            "ruff_c": ("#4a2a6a", "#160822", "#6e4a94"),
            "pants": ("pat", [("#2a2232", "#0a080e", "#463a50"), ("#221a2a", "#08060c", "#3a3044")], 6.0),
            "shoe": ("#2a2232", "#0a080e", "#463a50"),
            "glove": ("#3a3044", "#100a16", "#5e5068"),
            "orb": ("#1e1418", "#060204", "#4a2e34"),
            "orb_glow": "!#ff4a1a",
            "wheel": "!#ff3a2a",
            "wheel_b": "!#ff9a2a",
            "wheel_frame": ("#2a1a24", "#0a0608", "#4a3040"),
            "eye_glow": "!#ff2a1a",
            "tooth": ("#f2e8cc", "#7a6a7a", "#ffffff"),
        },
    },
}
KINDS = list(SPEC.keys())
CLASSICS = KINDS[:6]
ELITES = ["cv_fairground_being", "cv_fire_clown"]
BOSS = "cv_circus_king"


# =============================================================================== humanoïdes
class CvHuman(M.Human):
    """Humanoïde du carnaval : crochet après la pose (ballons, flammes), collerettes, ballons."""

    flames: list

    def pose(self, anim: str, i: int, n: int) -> None:
        getattr(self, "pose_" + anim)(i, n)
        self.after_pose(anim, i, n)

    def after_pose(self, anim: str, i: int, n: int) -> None:
        pass

    def rekey(self, prefix: str, key: str) -> None:
        for k, (ob, _key) in enumerate(self.parts):
            if ob.name.startswith(prefix):
                self.parts[k] = (ob, key)

    def ruff(self, parent, z: float, r: float, n: int = 14, keys=("ruff_a", "ruff_b"), size: float = 0.07,
             sy: float = 0.82, tilt: float = 0.0) -> None:
        """Collerette de clown : couronne de « fraises » aplaties, deux couleurs alternées."""
        for k in range(n):
            a = 2 * math.pi * k / n
            x, y = math.sin(a) * r, -math.cos(a) * r * sy
            zz = z + tilt * (-math.cos(a))
            self.part("ruff%d" % k, C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(x, y, zz),
                      rot=(0.5 * math.cos(a), 0.5 * math.sin(a), 0), scale=(size * 1.25, size * 1.25, size * 0.7)),
                      keys[k % len(keys)], parent)

    def balloons(self, keys=("balloon_a", "balloon_b"), side: str = "L", height: float = 0.78) -> None:
        """Ballons tenus à la main (`side`) : groupe « balloon », replacé sur la main à chaque pose."""
        sc = self.S["scale"]
        g = joint("w_balloon", self.j["root"], (0, 0, 0))
        self.balloon = g
        self.balloon_side = side
        offs = [(0.07, 0.02, height), (-0.12, 0.07, height - 0.10), (0.0, -0.10, height - 0.04)]
        for k, key in enumerate(keys):
            ox, oy, oz = [v * sc for v in offs[k]]
            ball = C.bm_sphere(16, 12, 1.0)
            for v in ball.verts:
                if v.co.z < 0:
                    v.co.x *= 1.0 + 0.35 * v.co.z
                    v.co.y *= 1.0 + 0.35 * v.co.z
            self.part("balloon%d" % k, C.bm_xform(ball, loc=(ox, oy, oz), scale=(0.12 * sc, 0.12 * sc, 0.15 * sc)),
                      key, g, grp="balloon")
            self.part("knot%d" % k, C.bm_xform(C.bm_cyl(8, 0.0, 0.025 * sc, 0.04 * sc), loc=(ox, oy, oz - 0.16 * sc)),
                      key, g, grp="balloon")
            self.part("string%d" % k, C.bm_tube([(0, 0, 0), (ox * 0.3 + 0.02, oy * 0.3, oz * 0.45),
                                                 (ox * 0.8, oy * 0.8, oz * 0.8), (ox, oy, oz - 0.17 * sc)],
                                                [0.006] * 4, seg=4), "string", g, grp="balloon", nofs=True)

    def follow_balloon(self, lift: float = 0.0, sway: float = 0.0, hide: bool = False) -> None:
        bpy.context.view_layer.update()
        fa = self.j["fa" + self.balloon_side]
        hw = fa.matrix_world @ Vector((0, 0, -self.ll))
        self.balloon.location = self.j["root"].matrix_world.inverted() @ hw + Vector((0, 0, lift))
        self.balloon.rotation_euler = (sway, 0.4 * sway, 0)
        self.show("balloon", not hide)

    def flame(self, parent, loc, size: float, name: str = "flame", lean=(0.0, 0.0), outer: str = "fire",
              inner: str = "fire_core", tall: float = 2.4, edge: str | None = None) -> None:
        """Flamme (cône émissif double, ou triple avec `edge`) ; vacille à chaque pose (after_pose → flicker)."""
        if not hasattr(self, "flames"):
            self.flames = []
        g = joint(name + "J", parent, loc)
        g.rotation_euler = (lean[0], lean[1], 0)
        layers = ((outer, 1.0), (inner, 0.55)) if edge is None else ((edge, 1.0), (outer, 0.72), (inner, 0.40))
        for key, k in layers:
            bm = C.bm_sphere(10, 8, 1.0)
            for v in bm.verts:
                if v.co.z > 0:
                    w = 1.0 - v.co.z
                    v.co.x *= 0.08 + 0.92 * w ** 1.4
                    v.co.y *= 0.08 + 0.92 * w ** 1.4
                    v.co.z *= tall
            self.part(name, C.bm_xform(bm, loc=(0, -0.01 * (1 - k), 0), scale=(size * k, size * k, size * k)),
                      key, g, nofs=True, grp="flames")
        self.flames.append((g, len(self.flames)))

    def flicker(self, seed: int) -> None:
        """Vacillement des flammes (mise à l'échelle autour de la base de chaque flamme)."""
        rnd = random.Random(seed)
        for g, _k in getattr(self, "flames", []):
            s = 0.85 + 0.3 * rnd.random()
            g.scale = (1.0 + 0.12 * (rnd.random() - 0.5), 1.0, s)

    def grin(self, head, key: str = "lips", w: float = 0.11, z: float = 0.11, y: float = -0.165, teeth: str = "tooth",
             curve: float = 0.04) -> None:
        pts = [(-w, y + 0.02, z + curve), (-w * 0.5, y, z), (w * 0.5, y, z), (w, y + 0.02, z + curve)]
        self.part("grin", C.bm_tube(C.bezier(*pts, 8), [0.016] * 8, seg=6, flat=0.6, up=(0, 1, 0)), key, head)
        for k in range(6):
            u = (k + 0.5) / 6
            x = -w * 0.7 + 1.4 * w * u
            self.part("tooth", C.bm_xform(C.bm_box(0.016, 0.012, 0.022), loc=(x, y - 0.006, z + 0.004 + curve * 0.6 * (2 * u - 1) ** 2)),
                      teeth, head, nofs=True)


# ------------------------------------------------------------------------------- clown égaré
class LostClown(CvHuman):
    def rest(self) -> None:
        super().rest()
        # tête relevée vers le joueur (visage lisible sous la caméra 3/4)
        self.j["head"].rotation_euler = (-0.42, 0, 0)

    def build_head(self, head) -> None:
        head.location = (0, -0.04, 0.05)
        self.skull(head, "face", jaw=0.06)
        # orbites creusées sombres, petites pupilles pâles
        for sx in (1, -1):
            self.part("socket", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0.066 * sx, -0.150, 0.232),
                      scale=(0.060, 0.03, 0.052), rot=(0, 0.35 * sx, 0)), "makeup", head, nofs=True)
            self.part("brow", C.bm_xform(C.bm_box(0.085, 0.03, 0.022, bevel=0.006), loc=(0.062 * sx, -0.158, 0.282),
                      rot=(0, -0.5 * sx, 0)), "makeup", head)
            # rides du front
        for k in range(2):
            self.part("wrinkle", C.bm_tube(C.bezier((-0.08, -0.150, 0.33 + 0.03 * k), (-0.03, -0.162, 0.32 + 0.03 * k),
                                                    (0.03, -0.162, 0.32 + 0.03 * k), (0.08, -0.150, 0.33 + 0.03 * k), 6),
                                           [0.005] * 6, seg=4), "makeup", head, nofs=True)
        self.eyes(head, "eye_glow", r=(0.022, 0.010, 0.020), brow=False, y=-0.172, x=0.068)
        # grande bouche béante sombre, sourire carnassier plein de dents
        self.part("mouthDark", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, -0.152, 0.105), scale=(0.13, 0.03, 0.055)),
                  "makeup", head, nofs=True)
        self.grin(head, w=0.135, z=0.095, curve=0.06)
        for k in range(7):
            u = (k + 0.5) / 7
            x = -0.10 + 0.20 * u
            self.part("toothL", C.bm_xform(C.bm_box(0.020, 0.012, 0.024), loc=(x, -0.166, 0.072 + 0.03 * (2 * u - 1) ** 2)),
                      "tooth", head, nofs=True)
        for sx in (1, -1):
            # grosses touffes de cheveux roux sur les côtés (crâne chauve)
            for k, (dx, dy, dz, r) in enumerate(((0.0, 0.04, 0.23, 0.072), (0.02, 0.09, 0.15, 0.066), (-0.03, 0.02, 0.30, 0.05),
                                                  (-0.02, 0.12, 0.26, 0.058))):
                self.part("hair", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=((0.19 + dx) * sx, dy, dz),
                          scale=(r * 1.25, r, r * 1.05)), "hair", head)
        self.part("nose", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.195, 0.175), scale=(0.05, 0.046, 0.048)),
                  "nose", head)

    def build_legs(self, pelvis) -> None:
        super().build_legs(pelvis)
        for side in ("L", "R"):
            self.part("bigShoe" + side, C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, -0.09, self.foot_z + 0.01),
                      scale=(0.10, 0.17, 0.065)), "shoe", self.j["knee" + side])

    def dress(self) -> None:
        sp = self.j["spine"]
        tw, td = self.TW, self.TD
        # grande collerette à trois couleurs, qui déborde sur les épaules
        self.ruff(sp, 0.37, 0.25 * tw, n=18, keys=("ruff_a", "ruff_b", "ruff_a", "ruff_c"), size=0.082, sy=0.86, tilt=0.12)
        self.ruff(sp, 0.41, 0.17 * tw, n=12, keys=("ruff_b", "ruff_a"), size=0.06, sy=0.86, tilt=0.12)
        # veste ouverte grise sur le gilet rayé
        coat = C.bm_loft([C.ellipse(0, 0.0, z, r1 * tw + 0.02, r2 * td + 0.02, 22)
                          for z, r1, r2 in ((0.0, 0.19, 0.145), (0.18, 0.205, 0.153), (0.34, 0.236, 0.162))],
                         cap_start=False, cap_end=False)
        for f in list(coat.faces):
            c = f.calc_center_median()
            if c.y < -0.06 * td and abs(c.x) < 0.12 * tw:
                coat.faces.remove(f)
        self.part("coat", coat, "jacket", sp, thick=0.014)
        for k in range(3):
            self.part("pompom", C.bm_xform(C.bm_sphere(10, 8, 0.03), loc=(0, -0.19 * td - 0.02 * self.BELLY, 0.30 - 0.10 * k)),
                      "pompom", sp)
        # éclaboussures de sang
        for k, (x, z, r) in enumerate(((0.06, 0.14, 0.04), (-0.05, 0.24, 0.03), (0.02, 0.05, 0.035))):
            self.part("blood", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(x, -0.19 * td - 0.01, z), scale=(r, 0.012, r * 1.4)),
                      "blood", sp, nofs=True)
        self.part("belt", C.bm_xform(C.bm_cyl(18, 0.22 * tw, 0.22 * tw, 0.05), loc=(0, 0, 0.05),
                  scale=(1, 0.76 * td / tw, 1)), "makeup", self.j["pelvis"])
        for side in ("L", "R"):
            self.part("cuff" + side, C.bm_xform(C.bm_torus(14, 6, 0.075 * self.AW, 0.022), loc=(0, 0, -0.15 * self.AL)),
                      "ruff_a", self.j["fa" + side])
            for k in range(3):
                x = (k - 1) * 0.03
                self.part("claw" + side, C.bm_tube([(x, -0.03, -self.ll - 0.04), (x * 1.3, -0.07, -self.ll - 0.11)],
                                                   [0.013, 0.0], seg=5), "tooth", self.j["fa" + side])
        self.balloons(side="L", height=0.70)
        self.muzzle_ref = ("handR", (0, 0, -self.ll))

    def arms_rest(self, b: float = 0.0) -> None:
        # bras tendus vers l'avant, griffes prêtes (la main gauche tient les ballons)
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.14, -0.26, -0.08 + 0.015 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.12, -0.30, -0.20 + 0.015 * b)), self.R_POLE)

    def arms_run(self, s: float) -> None:
        sh = self.shoulder
        self.arm_ik("L", sh["L"] + Vector((0.12, -0.10, -0.16 + 0.03 * s)), self.L_POLE)
        self.arm_ik("R", sh["R"] + Vector((-0.06, 0.22 * s - 0.06, -0.30 + 0.05 * abs(s))), self.R_POLE)

    def idle_extra(self, t: float) -> None:
        # accroupi, prêt à bondir ; la tête dodeline
        self.j["pelvis"].location.z -= 0.06
        self.legs((-0.30, -0.16, 0), (-0.22, 0.16, 0), 0.55, 0.45)
        self.j["neck"].rotation_euler = (-0.05, 0.0, 0.18 * math.sin(t * 0.5) + 0.12)

    def pose_attack(self, i: int, n: int) -> None:
        # griffe de la main droite : bras armé au-dessus de l'épaule (0-2), coup en travers (3), retour
        self.rest()
        j = self.j
        lean = (0.05, -0.08, -0.12, 0.42, 0.34, 0.12)[i]
        j["pelvis"].location.z = self.PZ - (0.0, 0.02, 0.03, 0.06, 0.05, 0.02)[i]
        self.spine_rot(lean, 0, (0.0, -0.25, -0.30, 0.35, 0.30, 0.05)[i])
        self.legs((-0.25, -0.08, 0), (0.25, 0.10, 0), 0.25, 0.30)
        sh = self.shoulder
        hr = [Vector((-0.10, -0.10, -0.20)), Vector((-0.18, 0.10, 0.22)), Vector((-0.20, 0.12, 0.28)),
              Vector((0.18, -0.42, -0.06)), Vector((0.24, -0.30, -0.20)), Vector((0.0, -0.22, -0.28))][i]
        self.arm_ik("R", sh["R"] + hr, Vector((-0.8, 0.3, 0.2)))
        self.arm_ik("L", sh["L"] + Vector((0.14, -0.10, -0.16)), self.L_POLE)
        j["neck"].rotation_euler = (-0.1 - 0.15 * (i >= 3), 0, 0.05)

    def after_pose(self, anim: str, i: int, n: int) -> None:
        if anim == "death":
            t = i / (n - 1)
            self.follow_balloon(lift=1.6 * t * t, sway=0.3 * t, hide=t > 0.55)
        elif anim == "hit":
            self.follow_balloon(sway=(0.35, 0.2, 0.08)[i])
        elif anim == "run":
            self.follow_balloon(lift=0.05, sway=-0.25 + 0.05 * math.sin(2 * math.pi * i / n))
        else:
            self.follow_balloon(sway=0.06 * math.sin(2 * math.pi * i / max(n, 1)))


# ------------------------------------------------------------------------------- acrobate sanguinaire
class Acrobat(CvHuman):
    def rest(self) -> None:
        super().rest()
        self.j["head"].rotation_euler = (-0.40, 0, 0)

    def build_head(self, head) -> None:
        head.location = (0, -0.03, 0.06)
        self.skull(head, "mask", sx=0.160, sy=0.165, sz=0.190, jaw=0.34)
        for sx in (1, -1):
            self.part("socket", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.062 * sx, -0.150, 0.225),
                      scale=(0.056, 0.03, 0.050), rot=(0, 0.3 * sx, 0)), "makeup", head, nofs=True)
            # larme peinte
            self.part("tear", C.bm_xform(C.bm_box(0.014, 0.01, 0.07), loc=(0.07 * sx, -0.160, 0.17)),
                      "makeup", head, nofs=True)
        self.eyes(head, "eye_glow", z=0.232, x=0.060, y=-0.170, r=(0.020, 0.010, 0.016), brow=False)
        self.part("mouthDark", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.150, 0.11), scale=(0.075, 0.025, 0.04)),
                  "makeup", head, nofs=True)
        self.grin(head, w=0.08, z=0.115, curve=0.04)
        # chapeau de bouffon : calotte, deux grandes cornes souples (violette / rouge), grelots dorés
        cap = C.bm_sphere(16, 10, 1.0)
        for v in cap.verts:
            if v.co.z < -0.1:
                v.co.z = -0.1
        self.part("cap", C.bm_xform(cap, loc=(0, 0.01, 0.27), scale=(0.185, 0.19, 0.15)), "hat_a", head)
        self.part("capBand", C.bm_xform(C.bm_torus(18, 6, 0.178, 0.022), loc=(0, 0.0, 0.26), scale=(1, 1.02, 1)),
                  "hat_b", head)
        for k, (ax, key) in enumerate(((1, "hat_a"), (-1, "hat_b"))):
            pts = C.bezier((0.06 * ax, 0.02, 0.36), (0.26 * ax, 0.0, 0.58), (0.46 * ax, 0.06, 0.48),
                           (0.46 * ax, 0.04, 0.26), 8)
            self.part("horn%d" % k, C.bm_tube(pts, [0.085, 0.08, 0.07, 0.06, 0.048, 0.035, 0.02, 0.008], seg=8), key, head)
            self.part("bell%d" % k, C.bm_xform(C.bm_sphere(10, 8, 0.045), loc=pts[-1]), "bell", head)

    def build_legs(self, pelvis) -> None:
        super().build_legs(pelvis)
        # arlequin : genouillères sombres, chaussons pointus
        for side in ("L", "R"):
            self.part("kneepad" + side, C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, -0.02, 0.0), scale=(0.10, 0.09, 0.08)),
                      "tights_b", self.j["knee" + side])
            self.part("toe" + side, C.bm_xform(C.bm_cyl(8, 0.05, 0.0, 0.14), loc=(0, -0.22, self.foot_z + 0.03),
                      rot=(math.pi / 2 + 0.4, 0, 0)), "shoe", self.j["knee" + side])

    def dress(self) -> None:
        sp = self.j["spine"]
        tw, td = self.TW, self.TD
        # losange rouge sur la poitrine, losanges sombres sur le ventre
        self.part("heart", C.bm_xform(C.bm_box(0.10, 0.012, 0.10), loc=(0.0, -0.160 * td - 0.01, 0.26), rot=(0, 0.785, 0)),
                  "diamond", sp, nofs=True)
        for k, (x, z) in enumerate(((0.07, 0.10), (-0.07, 0.10), (0.0, 0.03))):
            self.part("diamondS", C.bm_xform(C.bm_box(0.05, 0.01, 0.05), loc=(x * tw, -0.15 * td - 0.012, z), rot=(0, 0.785, 0)),
                      "suit_a", sp, nofs=True)
        # ceinture et bretelles sombres
        self.part("belt", C.bm_xform(C.bm_cyl(18, 0.20 * tw, 0.20 * tw, 0.05), loc=(0, 0, 0.02),
                  scale=(1, 0.76 * td / tw, 1)), "suit_a", sp)
        # collerette à pointes violette / rouge
        for k in range(10):
            a = 2 * math.pi * k / 10
            x, y = math.sin(a) * 0.15 * tw, -math.cos(a) * 0.13 * td
            self.part("collar", C.bm_xform(C.bm_cyl(6, 0.045, 0.0, 0.10), loc=(x * 1.25, y * 1.25, 0.40),
                      rot=(-math.cos(a) * 1.7, -math.sin(a) * 1.7, 0)), "hat_a" if k % 2 else "hat_b", sp)
        # longue perche à faucille (tenue à deux mains)
        fa = self.j["faR"]
        g = joint("w_sickle", fa, (0, 0, -self.ll))
        self.part("pole", C.bm_xform(C.bm_cyl(8, 0.02, 0.02, 1.10), loc=(0, -0.18, 0), rot=(math.pi / 2, 0, 0)),
                  "pole", g, grp="sickle")
        bl = C.bm_tube(C.bezier((0, -0.70, 0.0), (0, -0.80, 0.18), (0, -0.66, 0.34), (0, -0.48, 0.32), 8),
                       [0.035, 0.045, 0.042, 0.035, 0.026, 0.018, 0.01, 0.0], seg=6, flat=0.25, up=(1, 0, 0))
        self.part("sickle", bl, "blade", g, grp="sickle")
        self.part("bloodTip", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -0.76, 0.20), scale=(0.022, 0.03, 0.06)),
                  "blood", g, nofs=True, grp="sickle")
        self.sickle = g
        self.muzzle_ref = ("sickle", (0, -0.66, 0.34))

    def set_sickle(self, rot) -> None:
        self.sickle.rotation_euler = rot

    def grip_left(self, y: float = 0.30) -> None:
        """Main gauche sur la perche (repère de l'arme → repère de la colonne)."""
        bpy.context.view_layer.update()
        w = self.sickle.matrix_world @ Vector((0, y, 0))
        sp = self.j["spine"].matrix_world.inverted() @ w
        self.arm_ik("L", sp, self.L_POLE)

    def arms_rest(self, b: float = 0.0) -> None:
        s = self.shoulder
        self.arm_ik("R", s["R"] + Vector((-0.10, -0.24, -0.16 + 0.02 * b)), self.R_POLE)
        self.set_sickle((-1.05, 0, -0.55))
        self.grip_left(0.28)

    def arms_run(self, s: float) -> None:
        sh = self.shoulder
        for side, sx, k in (("L", 1, -1), ("R", -1, 1)):
            self.arm_ik(side, sh[side] + Vector((0.12 * sx, 0.18 + 0.10 * s * k, -0.26)),
                        self.L_POLE if sx > 0 else self.R_POLE)
        self.set_sickle((-1.6, 0, 0.2))

    def idle_extra(self, t: float) -> None:
        # garde basse d'acrobate : jambes écartées, genoux fléchis, balancement
        j = self.j
        j["pelvis"].location.z -= 0.10
        j["pelvis"].rotation_euler = (0, 0.05 * math.sin(t), 0.06 * math.sin(t))
        self.legs((-0.45, -0.40, 0), (0.25, 0.40, 0), 0.95, 0.55)
        j["neck"].rotation_euler = (-0.1, 0.12 * math.sin(t + 1), 0.15 * math.sin(t * 0.5))

    def pose_hit(self, i, n):
        super().pose_hit(i, n)
        self.set_sickle((-0.6, 0, 0.6))

    def pose_death(self, i, n):
        super().pose_death(i, n)
        self.set_sickle((0.4, 0, 1.2))

    def pose_attack(self, i: int, n: int) -> None:
        # salto : accroupi (0-2), en l'air faucille abattue (3), réception (4-5)
        self.rest()
        j = self.j
        crouch = (0.06, 0.14, 0.17, -0.16, 0.08, 0.03)[i]
        j["pelvis"].location.z = self.PZ - crouch
        j["pelvis"].location.y = (0.0, 0.02, 0.03, -0.30, -0.22, -0.06)[i]
        lean = (0.2, 0.42, 0.5, 0.75, 0.55, 0.25)[i]
        self.spine_rot(lean - self.HUNCH * 0.3, 0, (0.0, -0.2, -0.25, 0.2, 0.15, 0.0)[i])
        if i == 3:
            self.legs((-1.1, -0.1, 0), (-0.6, 0.1, 0), 1.9, 1.6)
        else:
            self.legs((-0.55 - crouch, -0.12, 0), (0.25, 0.12, 0), 0.4 + crouch * 4, 0.6 + crouch * 3)
        sh = self.shoulder
        hr = [Vector((-0.20, 0.10, 0.10)), Vector((-0.24, 0.20, 0.30)), Vector((-0.24, 0.20, 0.36)),
              Vector((0.06, -0.46, -0.10)), Vector((0.14, -0.34, -0.26)), Vector((-0.06, -0.20, -0.30))][i]
        self.arm_ik("R", sh["R"] + hr, Vector((-0.8, 0.3, 0.2)))
        self.arm_ik("L", sh["L"] + Vector((0.24, 0.10, 0.02 + 0.1 * (i == 3))), self.L_POLE)
        self.set_sickle([(-0.4, 0, 0.6), (0.6, 0, 0.5), (0.8, 0, 0.5), (-1.6, 0, 0.0), (-1.9, 0, -0.2), (-1.1, 0, 0.3)][i])


# ------------------------------------------------------------------------------- pénombre
class Penumbra(CvHuman):
    def rest(self) -> None:
        super().rest()
        self.j["head"].rotation_euler = (-0.30, 0, 0)

    def build_head(self, head) -> None:
        head.location = (0, -0.02, 0.03)
        self.skull(head, "skin")
        # visage : masque noir, yeux orangés
        self.part("faceShadow", C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, -0.10, 0.20),
                  scale=(0.150, 0.09, 0.17)), "face", head)
        self.eyes(head, "eye_glow", z=0.235, x=0.055, y=-0.186, r=(0.032, 0.012, 0.016), brow=False)
        # capuche pointue : pointe tirée vers le haut et l'arrière, bord du visage avancé
        hood = C.bm_sphere(24, 16, 1.0)
        for v in hood.verts:
            x, y, z = v.co
            if y < 0:
                z += 0.12 * (-y)
            if z > 0.3:
                k = (z - 0.3) / 0.7
                x *= 1.0 - 0.6 * k
                y = y * (1.0 - 0.5 * k) + 0.45 * k
                z += 0.28 * k * k
            v.co = Vector((x * 0.245, y * 0.24 + 0.03, z * 0.26 + 0.215))
        for f in list(hood.faces):
            c = f.calc_center_median()
            if c.y < -0.07 and c.z < 0.37 and abs(c.x) < 0.165:
                hood.faces.remove(f)
        for v in list(hood.verts):
            if not v.link_faces:
                hood.verts.remove(v)
        self.part("hood", hood, "cloak", head, thick=0.024)
        self.part("hoodRim", C.bm_xform(C.bm_torus(20, 6, 1.0, 0.10), loc=(0, -0.13, 0.215), rot=(math.pi / 2 - 0.25, 0, 0),
                  scale=(0.175, 0.20, 0.17)), "cloak_in", head)

    def dress(self) -> None:
        sp = self.j["spine"]
        pel = self.j["pelvis"]
        tw, td = self.TW, self.TD
        # mantelet large (épaules → taille) et jupe de cape en lambeaux (taille → mollets), ouverte devant
        mant = C.bm_loft([C.ellipse(0, 0.01, z, r1 * tw, r2 * td, 22)
                          for z, r1, r2 in ((0.04, 0.27, 0.21), (0.22, 0.30, 0.22), (0.38, 0.33, 0.22), (0.47, 0.19, 0.16))],
                         cap_start=False, cap_end=False)
        self.part("mantle", mant, "cloak", sp, thick=0.016)
        rnd = random.Random(5)
        secs = []
        for z, r in ((0.06, 0.27), (-0.12, 0.32), (-0.30, 0.37), (-0.50, 0.42)):
            secs.append(C.ellipse(0, 0.02, z, r * tw, r * 0.85 * td, 24))
        skirt = C.bm_loft(secs, cap_start=False, cap_end=False)
        for v in skirt.verts:
            if v.co.z < -0.4:
                a = math.atan2(v.co.y, v.co.x)
                v.co.z += 0.14 * (0.5 + 0.5 * math.sin(9 * a)) + 0.05 * rnd.random()
        for f in list(skirt.faces):
            c = f.calc_center_median()
            if c.y < -0.12 * td and abs(c.x) < 0.11 * tw and c.z < 0.0:
                skirt.faces.remove(f)
        self.part("skirt", skirt, "cloak", pel, thick=0.014)
        # sangles, boucles et braises orangées sur la poitrine
        self.part("strap", C.bm_tube([(0.20 * tw, -0.17 * td, 0.40), (0.0, -0.21 * td, 0.22), (-0.18 * tw, -0.18 * td, 0.04)],
                                     [0.02] * 3, seg=5, flat=0.4, up=(0, 1, 0)), "cloak_in", sp)
        for k, (x, z) in enumerate(((0.10, 0.32), (-0.02, 0.20), (-0.12, 0.10), (0.12, 0.10))):
            self.part("ember", C.bm_xform(C.bm_sphere(8, 6, 0.024), loc=(x * tw, -0.215 * td, z)), "ember", sp, nofs=True)
        self.part("buckle", C.bm_xform(C.bm_box(0.06, 0.02, 0.05), loc=(0.0, -0.215 * td, 0.21)), "brass", sp)
        # brume violette au ras du sol (sans contour)
        for k in range(6):
            a = 2 * math.pi * k / 6
            self.part("wisp", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.32 * math.sin(a), 0.30 * math.cos(a), -self.PZ + 0.04),
                      scale=(0.06, 0.045, 0.015)), "wisp", pel, nofs=True, grp="wisps")
        # longue lame droite (main droite), griffes (main gauche)
        fa = self.j["faR"]
        g = joint("w_blade", fa, (0, 0, -self.ll))
        bl = C.bm_tube([(0, -0.04, 0.0), (0, -0.30, -0.01), (0, -0.56, -0.03), (0, -0.70, -0.06)],
                       [0.04, 0.042, 0.036, 0.0], seg=6, flat=0.20, up=(1, 0, 0))
        self.part("blade", bl, "blade", g, grp="blade")
        self.part("edge", C.bm_tube([(0, -0.10, -0.03), (0, -0.40, -0.045), (0, -0.66, -0.07)],
                                    [0.010, 0.010, 0.0], seg=5), "blade_edge", g, nofs=True, grp="blade")
        self.part("guard", C.bm_xform(C.bm_box(0.12, 0.025, 0.03), loc=(0, -0.03, 0)), "brass", g, grp="blade")
        self.part("hilt", C.bm_xform(C.bm_cyl(8, 0.022, 0.022, 0.12), loc=(0, 0.04, 0), rot=(math.pi / 2, 0, 0)),
                  "cloak_in", g, grp="blade")
        self.blade = g
        for k in range(3):
            x = (k - 1) * 0.03
            self.part("clawL", C.bm_tube([(x, -0.02, -self.ll - 0.03), (x * 1.3, -0.06, -self.ll - 0.13)],
                                         [0.016, 0.0], seg=5), "blade", self.j["faL"])
        self.balloons(side="L", height=0.62)
        self.muzzle_ref = ("blade", (0, -0.70, -0.06))

    def set_blade(self, rot) -> None:
        self.blade.rotation_euler = rot

    def arms_rest(self, b: float = 0.0) -> None:
        # bras écartés, lame basse pointée vers l'extérieur
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.26, -0.16, -0.16 + 0.01 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.26, -0.18, -0.24 + 0.01 * b)), self.R_POLE)
        self.set_blade((1.1, 0.7, 0.0))

    def idle_extra(self, t: float) -> None:
        self.j["pelvis"].location.z -= 0.06
        self.legs((-0.30, -0.28, 0), (-0.25, 0.28, 0), 0.55, 0.50)

    def arms_run(self, s: float) -> None:
        sh = self.shoulder
        self.arm_ik("L", sh["L"] + Vector((0.12, 0.04 - 0.08 * s, -0.24)), self.L_POLE)
        self.arm_ik("R", sh["R"] + Vector((-0.14, 0.20 + 0.08 * s, -0.24)), self.R_POLE)
        self.set_blade((-1.7, 0, 0.3))

    def pose_hit(self, i, n):
        super().pose_hit(i, n)
        self.set_blade((-0.7, 0, 0.4))

    def pose_death(self, i, n):
        super().pose_death(i, n)
        self.set_blade((0.5, 0, 0.9))
        self.show("wisps", i < n - 2)

    def pose_attack(self, i: int, n: int) -> None:
        # surgit de l'ombre : ramassé (0-2), estoc fauchant (3), retour (4-5)
        self.rest()
        j = self.j
        crouch = (0.06, 0.12, 0.14, 0.04, 0.03, 0.01)[i]
        j["pelvis"].location.z = self.PZ - crouch
        j["pelvis"].location.y = (0.0, 0.02, 0.03, -0.20, -0.16, -0.04)[i]
        self.spine_rot((0.25, 0.4, 0.45, 0.6, 0.5, 0.3)[i] - self.HUNCH * 0.5, 0, (-0.2, -0.45, -0.5, 0.5, 0.6, 0.1)[i])
        stride = (0.2, 0.35, 0.4, 0.9, 0.8, 0.4)[i]
        self.legs((-stride * 0.6, -0.08, 0), (stride * 0.5, 0.10, 0), 0.3 + crouch * 2, 0.5 + crouch * 2)
        sh = self.shoulder
        hr = [Vector((-0.06, 0.06, -0.18)), Vector((-0.16, 0.20, -0.08)), Vector((-0.18, 0.22, -0.04)),
              Vector((0.28, -0.46, -0.08)), Vector((0.42, -0.30, -0.20)), Vector((0.10, -0.24, -0.26))][i]
        self.arm_ik("R", sh["R"] + hr, self.R_POLE)
        self.set_blade([(-0.6, 0, 1.4), (-0.4, 0, 2.2), (-0.4, 0, 2.3), (1.2, 0, 0.0), (1.1, 0, -0.5), (0.0, 0, 0.2)][i])
        self.arm_ik("L", sh["L"] + Vector((0.14, -0.14, -0.20)), self.L_POLE)

    def after_pose(self, anim: str, i: int, n: int) -> None:
        if anim == "death":
            t = i / (n - 1)
            self.follow_balloon(lift=1.4 * t * t, sway=0.3 * t, hide=t > 0.55)
        elif anim == "run":
            self.follow_balloon(lift=0.04, sway=-0.3)
        else:
            self.follow_balloon(sway=0.05 * math.sin(2 * math.pi * i / max(n, 1)))


# ------------------------------------------------------------------------------- grosse peluche
class BigPlush(CvHuman):
    def rest(self) -> None:
        super().rest()
        self.j["head"].rotation_euler = (-0.30, 0, 0.0)

    def build_head(self, head) -> None:
        self.skull(head, "fur", sx=0.20, sy=0.19, sz=0.19, jaw=0.0)
        for sx in (1, -1):
            self.part("ear", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0.15 * sx, 0.03, 0.365), scale=(0.075, 0.04, 0.072)),
                      "fur", head)
            self.part("earIn", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0.15 * sx, -0.005, 0.36), scale=(0.048, 0.02, 0.046)),
                      "cream", head)
        self.part("muzzle", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, -0.165, 0.15), scale=(0.095, 0.065, 0.07)),
                  "cream", head)
        self.part("nose", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.228, 0.175), scale=(0.035, 0.022, 0.026)),
                  "nose", head)
        # bouche cousue
        for k in range(5):
            x = -0.05 + 0.025 * k
            self.part("stitchM", C.bm_xform(C.bm_box(0.006, 0.01, 0.03), loc=(x, -0.222, 0.115 + 0.008 * abs(k - 2))),
                      "stitch", head, nofs=True)
        self.part("mouthLine", C.bm_tube([(-0.06, -0.218, 0.13), (0, -0.226, 0.115), (0.06, -0.218, 0.13)], [0.006] * 3,
                                         seg=4), "stitch", head, nofs=True)
        # yeux possédés (lueur pâle) sous des sourcils froncés, un bouton recousu sur la joue
        for sx in (1, -1):
            self.part("socket", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0.072 * sx, -0.165, 0.235), scale=(0.045, 0.02, 0.040)),
                      "nose", head, nofs=True)
            self.part("eye" + ("L" if sx > 0 else "R"), C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0.072 * sx, -0.178, 0.232),
                      scale=(0.030, 0.014, 0.026)), "eye_glow", head, nofs=True)
            self.part("brow", C.bm_xform(C.bm_box(0.09, 0.04, 0.03, bevel=0.01), loc=(0.07 * sx, -0.170, 0.285),
                      rot=(0, -0.45 * sx, 0)), "fur", head)
        self.part("button", C.bm_xform(C.bm_cyl(14, 0.026, 0.026, 0.02), loc=(0.13, -0.135, 0.14), rot=(math.pi / 2, 0, 0.5)),
                  "button", head)
        # couture déchirée sur le crâne, rembourrage qui dépasse
        for k in range(4):
            self.part("stitchH", C.bm_xform(C.bm_box(0.04, 0.008, 0.008), loc=(-0.08 + 0.01 * k, -0.06 + 0.05 * k, 0.37 - 0.01 * k),
                      rot=(0, 0, 0.6)), "stitch", head, nofs=True)
        self.part("stuffH", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(-0.12, 0.04, 0.33), scale=(0.05, 0.045, 0.04)),
                  "stuffing", head)

    def dress(self) -> None:
        sp = self.j["spine"]
        tw, td = self.TW, self.TD
        self.part("bellyPatch", C.bm_xform(C.bm_sphere(16, 12, 1.0), loc=(0, -0.16 * td - 0.04, 0.15),
                  scale=(0.17 * tw * 0.7, 0.06, 0.17)), "cream", sp)
        for k in range(5):
            self.part("stitchB", C.bm_xform(C.bm_box(0.05, 0.008, 0.008), loc=(0.02, -0.16 * td - 0.10, 0.06 + 0.045 * k),
                      rot=(0, 0.5 * (-1) ** k, 0)), "stitch", sp, nofs=True)
        # flanc décousu : rembourrage
        for k, (x, z, r) in enumerate(((0.21, 0.20, 0.05), (0.23, 0.26, 0.04), (0.20, 0.13, 0.035))):
            self.part("stuff", C.bm_xform(C.bm_sphere(10, 8, r), loc=(x * tw, -0.08, z)), "stuffing", sp)
        # collerette à pétales pointus (fauve / roux)
        for k in range(16):
            a = 2 * math.pi * k / 16
            x, y = math.sin(a) * 0.16 * tw, -math.cos(a) * 0.15 * td
            pet = C.bm_sphere(8, 6, 1.0)
            for v in pet.verts:
                if v.co.z > 0:
                    v.co.x *= 1.0 - 0.8 * v.co.z
                    v.co.z *= 1.6
            self.part("petal", C.bm_xform(pet, loc=(x * 1.05, y * 1.05, 0.44 - 0.03 * (-math.cos(a))),
                      rot=(-math.cos(a) * 1.25, -math.sin(a) * 1.25, 0), scale=(0.085, 0.03, 0.07)),
                      "ruff_a" if k % 2 else "ruff_b", sp)
        # cœur rouge cousu sur le ventre
        heart = C.bm_merge(C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0.035, 0, 0.02), scale=(0.045, 0.015, 0.04)),
                           C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(-0.035, 0, 0.02), scale=(0.045, 0.015, 0.04)),
                           C.bm_xform(C.bm_cyl(4, 0.075, 0.0, 0.09), loc=(0, 0, -0.03), rot=(math.pi, 0, math.pi / 4),
                                      scale=(1, 0.2, 1)))
        self.part("heart", C.bm_xform(heart, loc=(0, -0.16 * td - 0.105, 0.20)), "heart", sp)
        for side in ("L", "R"):
            fa = self.j["fa" + side]
            self.part("paw" + side, C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, 0, -self.ll),
                      scale=(0.10 * self.AW * 0.8, 0.095 * self.AW * 0.8, 0.10 * self.AW * 0.8)), "fur", fa)
            self.part("pad" + side, C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, -0.05, -self.ll - 0.03),
                      scale=(0.06, 0.03, 0.06)), "cream", fa)
            for k in range(3):
                x = (k - 1) * 0.04
                self.part("claw" + side, C.bm_tube([(x, -0.06, -self.ll - 0.05), (x * 1.2, -0.11, -self.ll - 0.12)],
                                                   [0.014, 0.0], seg=5), "claw", fa)
            self.part("footPad" + side, C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, -0.16, self.foot_z + 0.03),
                      scale=(0.07, 0.03, 0.06), rot=(0.3, 0, 0)), "cream", self.j["knee" + side])
        self.muzzle_ref = ("pawR", (0, 0, -self.ll))

    def build_legs(self, pelvis) -> None:
        super().build_legs(pelvis)
        for side in ("L", "R"):
            self.part("bigFoot" + side, C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, -0.07, self.foot_z + 0.03),
                      scale=(0.12, 0.17, 0.085)), "fur", self.j["knee" + side])

    def arms_rest(self, b: float = 0.0) -> None:
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.14, -0.10, -0.38 + 0.02 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.14, -0.10, -0.38 + 0.02 * b)), self.R_POLE)

    def arms_run(self, s: float) -> None:
        sh = self.shoulder
        for side, sx, k in (("L", 1, -1), ("R", -1, 1)):
            self.arm_ik(side, sh[side] + Vector((0.16 * sx, 0.16 * s * k - 0.10, -0.34)),
                        self.L_POLE if sx > 0 else self.R_POLE)

    def idle_extra(self, t: float) -> None:
        # tête qui dodeline comme un jouet
        self.j["neck"].rotation_euler = (-0.08, 0.10 * math.sin(t), 0.06 * math.sin(t * 0.5))

    def pose_run(self, i: int, n: int) -> None:
        super().pose_run(i, n)
        self.j["pelvis"].location.z -= 0.02
        self.j["pelvis"].rotation_euler.y = 0.10 * math.sin(2 * math.pi * i / n)

    def pose_attack(self, i: int, n: int) -> None:
        # bras levés (0-2), écrase des deux pattes (3), relève (4-5)
        self.rest()
        j = self.j
        crouch = (0.02, 0.0, -0.03, 0.14, 0.12, 0.05)[i]
        j["pelvis"].location.z = self.PZ - crouch
        self.spine_rot((-0.05, -0.22, -0.28, 0.50, 0.46, 0.18)[i], 0, 0)
        self.legs((-0.3, -0.14, 0), (0.25, 0.14, 0), 0.3 + crouch * 2, 0.35 + crouch * 2)
        sh = self.shoulder
        if i < 3:
            up = (0.28, 0.48, 0.54)[i]
            hl, hr = Vector((-0.06, 0.06, up)), Vector((0.06, 0.06, up))
        elif i < 5:
            hl, hr = Vector((-0.12, -0.36, -0.26)), Vector((0.12, -0.36, -0.26))
        else:
            hl, hr = Vector((0.06, -0.22, -0.34)), Vector((-0.06, -0.22, -0.34))
        self.arm_ik("L", sh["L"] + hl, Vector((0.9, 0.2, 0.1)))
        self.arm_ik("R", sh["R"] + hr, Vector((-0.9, 0.2, 0.1)))


# ------------------------------------------------------------------------------- l'Être forain (élite)
class FairgroundBeing(CvHuman):
    def rest(self) -> None:
        super().rest()
        self.j["head"].rotation_euler = (-0.36, 0, 0)

    def build_head(self, head) -> None:
        head.location = (0, -0.02, 0.03)
        self.skull(head, "skin", sx=0.165, sy=0.175, sz=0.195, jaw=0.45)
        self.eyes(head, "eye_glow", z=0.235, x=0.06, y=-0.158, r=(0.028, 0.012, 0.016), brow_key="hat", angle=0.6)
        for sx in (1, -1):
            self.part("cheek", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.10 * sx, -0.12, 0.17), scale=(0.035, 0.03, 0.05)),
                      "hat", head, nofs=True)
            # fissures incandescentes sur le visage
            self.part("crack", C.bm_tube([(0.03 * sx, -0.17, 0.30), (0.07 * sx, -0.165, 0.27), (0.06 * sx, -0.17, 0.20),
                                          (0.11 * sx, -0.145, 0.15), (0.10 * sx, -0.15, 0.09)], [0.007] * 5, seg=4),
                      "crack", head, nofs=True)
        self.grin(head, key="lips", w=0.085, z=0.115, teeth="tooth", curve=0.045)
        self.part("nose", C.bm_xform(C.bm_cyl(8, 0.025, 0.0, 0.07), loc=(0, -0.19, 0.19), rot=(1.35, 0, 0)), "skin", head)
        # haut-de-forme incliné, ruban rouge, plume de néon
        g = joint("hat", head, (0.02, 0.0, 0.34))
        g.rotation_euler = (-0.12, 0.18, 0)
        self.part("brim", C.bm_xform(C.bm_cyl(24, 0.23, 0.23, 0.025), loc=(0, 0, 0.0)), "hat", g)
        self.part("crown", C.bm_xform(C.bm_cyl(20, 0.15, 0.165, 0.34), loc=(0, 0, 0.18)), "hat", g)
        self.part("band", C.bm_xform(C.bm_cyl(20, 0.168, 0.168, 0.06), loc=(0, 0, 0.05)), "hat_band", g)
        self.part("buckle", C.bm_xform(C.bm_box(0.06, 0.02, 0.05), loc=(0, -0.17, 0.05)), "gold", g)
        self.part("hatTop", C.bm_xform(C.bm_cyl(20, 0.165, 0.165, 0.012), loc=(0, 0, 0.35)), "hat", g)

    def dress(self) -> None:
        sp = self.j["spine"]
        pel = self.j["pelvis"]
        tw, td = self.TW, self.TD
        # redingote ouverte (épaules → genoux), queue de pie fendue derrière
        coat = C.bm_loft([C.ellipse(0, 0.0, z, r1 * tw + 0.03, r2 * td + 0.03, 22)
                          for z, r1, r2 in ((0.0, 0.20, 0.155), (0.20, 0.215, 0.165), (0.36, 0.236, 0.162), (0.46, 0.17, 0.13))],
                         cap_start=False, cap_end=False)
        for f in list(coat.faces):
            c = f.calc_center_median()
            if c.y < -0.08 * td and abs(c.x) < 0.11 * tw:
                coat.faces.remove(f)
        self.part("coat", coat, "coat", sp, thick=0.016)
        tails = C.bm_loft([C.ellipse(0, 0.02, z, r * tw, r * 0.85 * td, 24)
                           for z, r in ((0.08, 0.235), (-0.16, 0.28), (-0.42, 0.32), (-0.62, 0.35))], cap_start=False, cap_end=False)
        for f in list(tails.faces):
            c = f.calc_center_median()
            if (c.y < -0.10 * td and abs(c.x) < 0.09 * tw) or (c.y > 0.0 and abs(c.x) < 0.03 and c.z < -0.12):
                tails.faces.remove(f)
        self.part("tails", tails, "coat", pel, thick=0.014)
        # haut col relevé
        col = C.bm_loft([C.ellipse(0, 0.02, z, r * tw, r * 0.9 * td, 20) for z, r in ((0.42, 0.17), (0.56, 0.20))],
                        cap_start=False, cap_end=False)
        for f in list(col.faces):
            if f.calc_center_median().y < -0.08:
                col.faces.remove(f)
        self.part("collar", col, "coat", sp, thick=0.016)
        for sx in (1, -1):
            # revers
            self.part("lapel", C.bm_tube([(0.10 * sx * tw, -0.17 * td, 0.42), (0.08 * sx * tw, -0.20 * td, 0.28),
                                          (0.10 * sx * tw, -0.19 * td, 0.12)], [0.03, 0.035, 0.02], seg=5, flat=0.3,
                                         up=(0, 1, 0)), "coat_in", sp)
        self.part("shirt", C.bm_xform(C.bm_box(0.10, 0.03, 0.12), loc=(0, -0.19 * td, 0.38)), "shirt", sp)
        self.part("cravat", C.bm_xform(C.bm_cyl(4, 0.045, 0.0, 0.10), loc=(0, -0.21 * td, 0.36), rot=(math.pi, 0, 0.785)),
                  "hat_band", sp)
        for k in range(3):
            self.part("button", C.bm_xform(C.bm_sphere(8, 6, 0.018), loc=(0.03, -0.20 * td, 0.26 - 0.07 * k)), "gold", sp)
        self.part("chain", C.bm_tube(C.bezier((0.03, -0.20 * td, 0.20), (0.07, -0.22 * td, 0.12), (0.12, -0.21 * td, 0.12),
                                              (0.15 * tw, -0.17 * td, 0.18), 6), [0.008] * 6, seg=4), "gold", sp)
        # canne à pommeau doré (main droite)
        fa = self.j["faR"]
        g = joint("w_cane", fa, (0, 0, -self.ll))
        self.part("cane", C.bm_xform(C.bm_cyl(8, 0.022, 0.018, 0.64), loc=(0, 0, -0.27)), "cane", g, grp="cane")
        self.part("knob", C.bm_xform(C.bm_sphere(12, 8, 0.055), loc=(0, 0, 0.07)), "gold", g, grp="cane")
        self.part("tip", C.bm_xform(C.bm_cyl(8, 0.022, 0.0, 0.06), loc=(0, 0, -0.62)), "gold", g, grp="cane")
        self.cane = g
        self.muzzle_ref = ("tip", (0, 0, -0.62))

    def set_cane(self, rot) -> None:
        self.cane.rotation_euler = rot

    def arms_rest(self, b: float = 0.0) -> None:
        # appuyé sur sa canne, main gauche dans le dos
        s = self.shoulder
        self.arm_ik("R", s["R"] + Vector((-0.10, -0.22, -0.32 + 0.01 * b)), self.R_POLE)
        self.arm_ik("L", s["L"] + Vector((-0.02, 0.18, -0.30)), self.L_POLE)
        self.set_cane((0.08, 0, 0))

    def arms_run(self, s: float) -> None:
        sh = self.shoulder
        self.arm_ik("R", sh["R"] + Vector((-0.10, -0.12 - 0.1 * s, -0.24)), self.R_POLE)
        self.arm_ik("L", sh["L"] + Vector((0.06, 0.14 * s, -0.30)), self.L_POLE)
        self.set_cane((-1.2, 0, 0))

    def idle_extra(self, t: float) -> None:
        self.j["neck"].rotation_euler = (-0.12, 0.0, 0.1 * math.sin(t * 0.5))

    def pose_hit(self, i, n):
        super().pose_hit(i, n)
        self.set_cane((-0.6, 0, 0.3))

    def pose_death(self, i, n):
        super().pose_death(i, n)
        self.set_cane((0.8, 0.2, 1.0))

    def pose_attack(self, i: int, n: int) -> None:
        # canne levée à deux mains (0-2), abattue (3), retour (4-5)
        self.rest()
        j = self.j
        j["pelvis"].location.z = self.PZ - (0.0, 0.01, 0.02, 0.06, 0.05, 0.02)[i]
        self.spine_rot((0.0, -0.18, -0.22, 0.45, 0.40, 0.12)[i], 0, (0.0, -0.25, -0.3, 0.2, 0.15, 0.0)[i])
        self.legs((-0.3, -0.10, 0), (0.3, 0.12, 0), 0.25, 0.32)
        sh = self.shoulder
        hr = [Vector((-0.08, -0.10, -0.16)), Vector((-0.10, 0.08, 0.30)), Vector((-0.10, 0.10, 0.36)),
              Vector((0.08, -0.44, -0.08)), Vector((0.10, -0.36, -0.22)), Vector((-0.04, -0.22, -0.28))][i]
        self.arm_ik("R", sh["R"] + hr, Vector((-0.8, 0.3, 0.2)))
        self.arm_ik("L", sh["L"] + Vector((0.10, -0.24, -0.20)) if i >= 3 else sh["L"] + Vector((0.12, -0.10, 0.10 * i)),
                    self.L_POLE)
        self.set_cane([(-0.8, 0, 0), (0.9, 0, 0), (1.1, 0, 0), (-1.6, 0, 0), (-1.8, 0, 0), (-0.9, 0, 0)][i])


# ------------------------------------------------------------------------------- le Clown de feu (élite)
class FireClown(CvHuman):
    def rest(self) -> None:
        super().rest()
        self.j["head"].rotation_euler = (-0.40, 0, 0)

    def build_head(self, head) -> None:
        head.location = (0, -0.03, 0.05)
        self.skull(head, "face", jaw=0.10)
        for sx in (1, -1):
            self.part("soot", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.066 * sx, -0.150, 0.230),
                      scale=(0.058, 0.03, 0.054), rot=(0, 0.35 * sx, 0)), "soot", head, nofs=True)
            self.part("brow", C.bm_xform(C.bm_box(0.085, 0.03, 0.022, bevel=0.006), loc=(0.062 * sx, -0.160, 0.285),
                      rot=(0, -0.5 * sx, 0)), "soot", head)
        self.eyes(head, "eye_glow", r=(0.022, 0.010, 0.020), brow=False, y=-0.172, x=0.068)
        self.part("nose", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.195, 0.175), scale=(0.045, 0.042, 0.044)),
                  "nose", head)
        self.part("mouthDark", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, -0.152, 0.105), scale=(0.13, 0.03, 0.055)),
                  "soot", head, nofs=True)
        self.grin(head, key="lips", w=0.135, z=0.095, curve=0.06)
        for k in range(7):
            u = (k + 0.5) / 7
            x = -0.10 + 0.20 * u
            self.part("toothL", C.bm_xform(C.bm_box(0.020, 0.012, 0.024), loc=(x, -0.166, 0.072 + 0.03 * (2 * u - 1) ** 2)),
                      "tooth", head, nofs=True)
        # chevelure de flammes : grande couronne de langues de feu (côtés et sommet)
        rnd = random.Random(11)
        k = 0
        for ring, (z, r, n, sz, lean) in enumerate(((0.30, 0.17, 8, 0.075, 0.6), (0.18, 0.20, 9, 0.08, 1.0), (0.38, 0.08, 5, 0.085, 0.3))):
            for q in range(n):
                a = math.pi * (0.0 + 2.0 * q / n) + 0.3 * ring
                x, y = math.sin(a) * r, math.cos(a) * r * 0.9 + 0.03
                if y < -0.10 and z < 0.35:
                    continue  # pas de flamme devant le visage
                key = ("fire_edge", "fire", "fire_core")[(k + ring) % 3] if ring < 2 else "fire_core"
                self.flame(head, (x, y, z), sz * (0.85 + 0.3 * rnd.random()), name="hairFire%d" % k,
                           lean=(lean * (y / max(r, 1e-3)) * 0.8, -lean * (x / max(r, 1e-3))), tall=3.4,
                           outer=key, inner="fire_core" if key != "fire_core" else "fire")
                k += 1

    def dress(self) -> None:
        sp = self.j["spine"]
        tw, td = self.TW, self.TD
        self.ruff(sp, 0.37, 0.24 * tw, n=16, size=0.08, sy=0.86, tilt=0.12)
        self.ruff(sp, 0.41, 0.16 * tw, n=12, keys=("ruff_b", "ruff_a"), size=0.06, sy=0.86, tilt=0.12)
        for k, (x, z) in enumerate(((0.0, 0.28), (0.06, 0.18), (-0.07, 0.12), (0.02, 0.05), (0.12, 0.30), (-0.13, 0.26))):
            self.part("ember", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(x * tw, -0.19 * td - 0.02, z), scale=(0.03, 0.01, 0.022)),
                      "ember", sp, nofs=True)
        self.part("belt", C.bm_xform(C.bm_cyl(18, 0.22 * tw, 0.22 * tw, 0.05), loc=(0, 0, 0.05),
                  scale=(1, 0.76 * td / tw, 1)), "soot", self.j["pelvis"])
        # mains en feu, flammes sur les épaules
        for side in ("L", "R"):
            fa = self.j["fa" + side]
            self.flame(fa, (0, 0, -self.ll - 0.02), 0.07, name="handFire" + side, lean=(math.pi, 0))
            self.flame(fa, (0, 0, -self.ll + 0.04), 0.06, name="handFire2" + side)
        for sx, side in ((1, "L"), (-1, "R")):
            self.flame(self.j["ua" + side], (0.03 * sx, 0, 0.06), 0.06, name="shoulderFire" + side)
        # boule de feu tenue (main droite) pendant l'élan
        fa = self.j["faR"]
        self.part("fireball", C.bm_xform(C.bm_sphere(14, 10, 0.13), loc=(0, -0.06, -self.ll - 0.10)), "fire_edge", fa,
                  nofs=True, grp="fireball")
        self.part("fireballMid", C.bm_xform(C.bm_sphere(14, 10, 0.10), loc=(0, -0.10, -self.ll - 0.10)), "fire", fa,
                  nofs=True, grp="fireball")
        self.part("fireballCore", C.bm_xform(C.bm_sphere(12, 8, 0.065), loc=(0, -0.15, -self.ll - 0.10)), "fire_core", fa,
                  nofs=True, grp="fireball")
        self.muzzle_ref = ("fireball", (0, -0.04, -self.ll - 0.06))

    def arms_rest(self, b: float = 0.0) -> None:
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.18, -0.20, -0.20 + 0.02 * b)), self.L_POLE)
        # boule de feu présentée dans la main droite, en avant
        self.arm_ik("R", s["R"] + Vector((-0.16, -0.30, -0.06 + 0.02 * b)), self.R_POLE)

    def idle_extra(self, t: float) -> None:
        self.j["neck"].rotation_euler = (-0.08, 0.0, 0.12 * math.sin(t))

    def pose_attack(self, i: int, n: int) -> None:
        # boule de feu : bras armé en arrière (0-2), lancer (3), suivi (4-5)
        self.rest()
        j = self.j
        j["pelvis"].location.z = self.PZ - (0.0, 0.02, 0.03, 0.04, 0.03, 0.01)[i]
        self.spine_rot((0.05, -0.08, -0.10, 0.35, 0.30, 0.10)[i], 0, (0.0, -0.45, -0.55, 0.45, 0.40, 0.05)[i])
        self.legs((-0.3, -0.10, 0), (0.3, 0.12, 0), 0.22, 0.30)
        sh = self.shoulder
        hr = [Vector((-0.12, -0.10, -0.10)), Vector((-0.22, 0.20, 0.16)), Vector((-0.24, 0.24, 0.20)),
              Vector((0.06, -0.48, 0.02)), Vector((0.10, -0.38, -0.14)), Vector((-0.08, -0.20, -0.24))][i]
        self.arm_ik("R", sh["R"] + hr, Vector((-0.8, 0.3, 0.2)))
        self.arm_ik("L", sh["L"] + Vector((0.16, -0.30 + 0.12 * (i >= 3), -0.06)), self.L_POLE)

    def after_pose(self, anim: str, i: int, n: int) -> None:
        self.flicker(i * 31 + len(anim) * 977 + int(self.dir_ang) * 7 + 1000)
        ball = (anim == "attack" and i <= 3) or anim in ("idle", "run", "hit")
        self.show("fireball", ball)
        if anim == "death" and i >= n - 2:
            for ob, _k in self.flames:
                ob.scale = (0.5, 0.5, 0.35)


# ------------------------------------------------------------------------------- le Roi du cirque (boss)
class CircusKing(CvHuman):
    def rest(self) -> None:
        super().rest()
        self.j["head"].rotation_euler = (-0.34, 0, 0)

    def build_head(self, head) -> None:
        head.location = (0, -0.03, 0.05)
        self.skull(head, "face", jaw=0.18)
        for sx in (1, -1):
            self.part("socket", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0.066 * sx, -0.150, 0.232),
                      scale=(0.058, 0.03, 0.05), rot=(0, 0.35 * sx, 0)), "makeup", head, nofs=True)
        self.eyes(head, "eye_glow", r=(0.026, 0.012, 0.020), brow_key="makeup", angle=0.6, y=-0.172, x=0.068)
        self.part("mouthDark", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, -0.152, 0.105), scale=(0.13, 0.03, 0.055)),
                  "makeup", head, nofs=True)
        for k in range(7):
            u = (k + 0.5) / 7
            x = -0.10 + 0.20 * u
            self.part("toothL", C.bm_xform(C.bm_box(0.020, 0.012, 0.024), loc=(x, -0.166, 0.072 + 0.03 * (2 * u - 1) ** 2)),
                      "tooth", head, nofs=True)
        for sx in (1, -1):
            self.part("paint", C.bm_xform(C.bm_box(0.05, 0.01, 0.11), loc=(0.065 * sx, -0.166, 0.232),
                      rot=(0, 0.785, 0)), "makeup", head, nofs=True)
            for k, (dy, dz, r) in enumerate(((0.04, 0.22, 0.075), (0.09, 0.15, 0.07), (0.0, 0.29, 0.06))):
                self.part("hair", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0.18 * sx, dy, dz), scale=(r * 1.3, r, r)),
                          "hair", head)
        self.part("nose", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.19, 0.175), scale=(0.05, 0.045, 0.048)),
                  "nose", head)
        self.grin(head, key="lips", w=0.12, z=0.10, curve=0.05)
        # couronne d'or à pointes, joyaux rouges
        crown = joint("crown", head, (0, 0.0, 0.33))
        crown.rotation_euler = (-0.1, 0.08, 0)
        self.part("crownBand", C.bm_xform(C.bm_cyl(22, 0.15, 0.16, 0.07), loc=(0, 0, 0.0)), "gold", crown)
        for k in range(8):
            a = 2 * math.pi * k / 8
            x, y = math.sin(a) * 0.15, -math.cos(a) * 0.15
            self.part("spike", C.bm_xform(C.bm_cyl(6, 0.035, 0.0, 0.13), loc=(x, y, 0.09), rot=(-0.2 * math.cos(a), 0.2 * math.sin(a), 0)),
                      "gold", crown)
            self.part("jewelS", C.bm_xform(C.bm_sphere(8, 6, 0.018), loc=(x * 1.05, y * 1.05, 0.155)), "jewel", crown, nofs=True)
        self.part("jewel", C.bm_xform(C.bm_sphere(10, 8, 0.03), loc=(0, -0.16, 0.0)), "jewel", crown, nofs=True)

    def dress(self) -> None:
        sp = self.j["spine"]
        pel = self.j["pelvis"]
        tw, td = self.TW, self.TD
        self.ruff(sp, 0.36, 0.27 * tw, n=20, keys=("ruff_c", "ruff_b"), size=0.085, sy=0.86, tilt=0.12)
        self.ruff(sp, 0.40, 0.21 * tw, n=16, keys=("ruff_a", "ruff_b"), size=0.075, sy=0.86, tilt=0.12)
        self.ruff(sp, 0.44, 0.15 * tw, n=12, keys=("ruff_a",), size=0.06, sy=0.86, tilt=0.10)
        # épaulières d'armure sombre bordées d'or, plastron
        for side, sx in (("L", 1), ("R", -1)):
            self.part("pauldron" + side, C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0.02 * sx, 0, 0.02),
                      scale=(0.15, 0.15, 0.10)), "armor", self.j["ua" + side])
            self.part("pauldronRim" + side, C.bm_xform(C.bm_torus(16, 5, 0.14, 0.016), loc=(0.02 * sx, 0, -0.02)),
                      "gold", self.j["ua" + side])
        self.part("plate", C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, -0.10 * td, 0.20), scale=(0.20 * tw, 0.10 * td, 0.16)),
                  "armor", sp)
        # longue robe (taille → chevilles)
        rob = C.bm_loft([C.ellipse(0, 0.0, z, r * tw, r * 0.85 * td, 22)
                         for z, r in ((0.08, 0.24), (-0.16, 0.27), (-0.38, 0.30))], cap_start=False, cap_end=False)
        for f in list(rob.faces):
            c = f.calc_center_median()
            if c.y < -0.10 * td and abs(c.x) < 0.07 * tw and c.z < -0.05:
                rob.faces.remove(f)
        self.part("robeSkirt", rob, "robe", pel, thick=0.016)
        self.part("hem", C.bm_xform(C.bm_torus(24, 6, 0.30 * tw, 0.025), loc=(0, 0, -0.37), scale=(1, 0.85 * td / tw, 1)),
                  "gold", pel)
        self.part("belt", C.bm_xform(C.bm_cyl(20, 0.25 * tw, 0.25 * tw, 0.07), loc=(0, 0, 0.08),
                  scale=(1, 0.85 * td / tw, 1)), "gold", pel)
        # cape royale : bord d'hermine sur les épaules, intérieur violet
        cape = C.bm_loft([C.ellipse(0, 0.04, z, r1 * tw, r2 * td, 24)
                          for z, r1, r2 in ((0.46, 0.20, 0.17), (0.30, 0.30, 0.25), (-0.10, 0.36, 0.30), (-0.62, 0.42, 0.36))],
                         cap_start=False, cap_end=False)
        for f in list(cape.faces):
            c = f.calc_center_median()
            if c.y < 0.0 and c.z < 0.36:
                cape.faces.remove(f)
        for v in list(cape.verts):
            if not v.link_faces:
                cape.verts.remove(v)
        self.part("cape", cape, "cape_in", sp, thick=0.02)
        self.part("ermine", C.bm_xform(C.bm_torus(24, 8, 0.24 * tw, 0.05), loc=(0, 0.02, 0.40), scale=(1, 0.85, 1)),
                  "ermine", sp)
        for k in range(8):
            a = 2 * math.pi * k / 8
            self.part("spot", C.bm_xform(C.bm_sphere(6, 4, 0.012), loc=(math.sin(a) * 0.24 * tw, 0.02 - math.cos(a) * 0.2, 0.44)),
                      "spot", sp, nofs=True)
        # médaillon et boutons d'or
        self.part("medal", C.bm_xform(C.bm_cyl(14, 0.05, 0.05, 0.02), loc=(0, -0.20 * td, 0.30), rot=(math.pi / 2, 0, 0)),
                  "gold", sp)
        self.part("medalJ", C.bm_xform(C.bm_sphere(8, 6, 0.022), loc=(0, -0.215 * td, 0.30)), "jewel", sp, nofs=True)
        # grande roue de néon dans le dos (auréole) : jante, rayons, nacelles lumineuses
        g = joint("wheel", sp, (0, 0.30 * td, 0.72))
        self.wheel = g
        rim = C.bm_torus(32, 6, 0.60, 0.028)
        self.part("rim", C.bm_xform(rim, rot=(math.pi / 2, 0, 0)), "wheel", g, nofs=True)
        self.part("rimFrame", C.bm_xform(C.bm_torus(32, 6, 0.53, 0.02), rot=(math.pi / 2, 0, 0)), "wheel_frame", g)
        for k in range(12):
            a = 2 * math.pi * k / 12
            x, z = math.cos(a) * 0.57, math.sin(a) * 0.57
            self.part("spoke", C.bm_tube([(0, 0, 0), (x, 0, z)], [0.012, 0.012], seg=4), "wheel_frame", g)
            self.part("bulb", C.bm_xform(C.bm_sphere(8, 6, 0.042), loc=(x * 1.07, 0, z * 1.07)),
                      "wheel_b" if k % 2 else "wheel", g, nofs=True)
        self.part("hub", C.bm_xform(C.bm_cyl(12, 0.06, 0.06, 0.05), rot=(math.pi / 2, 0, 0)), "gold", g)
        # sceptre (main droite) à orbe rougeoyante
        fa = self.j["faR"]
        sg = joint("w_scepter", fa, (0, 0, -self.ll))
        self.part("shaft", C.bm_xform(C.bm_cyl(10, 0.025, 0.022, 0.95), loc=(0, 0, 0.05)), "gold", sg, grp="scepter")
        self.part("ring", C.bm_xform(C.bm_torus(14, 6, 0.06, 0.016), loc=(0, 0, 0.50)), "gold", sg, grp="scepter")
        self.part("orb", C.bm_xform(C.bm_sphere(14, 10, 0.10), loc=(0, 0, 0.64)), "orb", sg, grp="scepter")
        self.part("orbGlow", C.bm_xform(C.bm_torus(16, 6, 0.10, 0.012), loc=(0, 0, 0.64)), "orb_glow", sg, nofs=True,
                  grp="scepter")
        self.part("orbTip", C.bm_xform(C.bm_cyl(8, 0.03, 0.0, 0.10), loc=(0, 0, 0.78)), "gold", sg, grp="scepter")
        self.part("orbCage", C.bm_xform(C.bm_torus(16, 6, 0.105, 0.014), loc=(0, 0, 0.64), rot=(math.pi / 2, 0, 0)), "gold", sg,
                  grp="scepter")
        self.part("butt", C.bm_xform(C.bm_sphere(10, 8, 0.04), loc=(0, 0, -0.43)), "gold", sg, grp="scepter")
        self.scepter = sg
        self.muzzle_ref = ("orb", (0, 0, 0.62))

    def set_scepter(self, rot) -> None:
        self.scepter.rotation_euler = rot

    def arms_rest(self, b: float = 0.0) -> None:
        s = self.shoulder
        self.arm_ik("R", s["R"] + Vector((-0.12, -0.18, -0.30 + 0.01 * b)), self.R_POLE)
        self.arm_ik("L", s["L"] + Vector((0.14, -0.14, -0.30 + 0.01 * b)), self.L_POLE)
        self.set_scepter((-0.15, 0, 0.1))

    def arms_run(self, s: float) -> None:
        sh = self.shoulder
        self.arm_ik("R", sh["R"] + Vector((-0.12, -0.14 - 0.06 * s, -0.26)), self.R_POLE)
        self.arm_ik("L", sh["L"] + Vector((0.12, 0.12 * s - 0.06, -0.30)), self.L_POLE)
        self.set_scepter((-0.5, 0, 0.1))

    def pose_hit(self, i, n):
        super().pose_hit(i, n)
        self.set_scepter((-0.6, 0, 0.3))

    def pose_death(self, i, n):
        super().pose_death(i, n)
        self.set_scepter((1.0, 0.2, 1.0))

    def pose_attack(self, i: int, n: int) -> None:
        # sceptre levé à deux mains (0-2), abattu au sol (3), relève (4-5)
        self.rest()
        j = self.j
        crouch = (0.02, 0.0, -0.02, 0.12, 0.10, 0.04)[i]
        j["pelvis"].location.z = self.PZ - crouch
        self.spine_rot((-0.05, -0.22, -0.26, 0.48, 0.42, 0.15)[i], 0, 0)
        self.legs((-0.3, -0.14, 0), (0.25, 0.14, 0), 0.3 + crouch * 2, 0.35 + crouch * 2)
        sh = self.shoulder
        if i < 3:
            up = (0.30, 0.52, 0.58)[i]
            hr, hl = Vector((0.06, 0.04, up)), Vector((-0.10, 0.04, up - 0.06))
        elif i < 5:
            hr, hl = Vector((0.10, -0.42, -0.20)), Vector((-0.12, -0.38, -0.22))
        else:
            hr, hl = Vector((-0.04, -0.24, -0.30)), Vector((0.08, -0.20, -0.32))
        self.arm_ik("R", sh["R"] + hr, Vector((-0.9, 0.2, 0.1)))
        self.arm_ik("L", sh["L"] + hl, Vector((0.9, 0.2, 0.1)))
        self.set_scepter([(0.3, 0, 0), (1.4, 0, 0), (1.6, 0, 0), (-1.5, 0, 0), (-1.6, 0, 0), (-0.6, 0, 0)][i])

    def after_pose(self, anim: str, i: int, n: int) -> None:
        # la grande roue tourne lentement
        self.wheel.rotation_euler = (0, 0.20 * i + (0.1 if anim == "run" else 0.0), 0)


# =============================================================================== quadrupèdes
class Quad(M.Rig):
    """Quadrupède : torse horizontal (loft), cou + tête + mâchoire, 4 pattes en IK 2 os, queue.
    Repère : regarde vers -Y, +X = sa gauche, Z vers le haut (comme les humanoïdes)."""

    def build(self) -> None:
        S = self.S
        j = self.j
        self.H = S["height"]
        self.L = S["length"]
        self.L1, self.L2 = S["leg"]
        self.RX, self.RZ = S["girth"]
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["body"] = body = joint("body", root, (0, 0, 0))
        body.scale = (S["scale"],) * 3
        j["torso"] = to = joint("torso", body, (0, 0, self.H))
        self.build_torso(to)
        j["neck"] = nk = joint("neck", to, (0, -self.L * 0.42, self.RZ * 0.55))
        j["head"] = hd = joint("head", nk, (0, -S["neck_len"] * 0.55, S["neck_len"] * 0.75))
        j["jaw"] = jw = joint("jaw", hd, (0, -0.06, -0.05))
        self.build_neck(to, nk)
        self.build_head(hd, jw)
        j["tail"] = tl = joint("tail", to, (0, self.L * 0.48, self.RZ * 0.45))
        self.build_tail(tl)
        self.legs_def = []
        hx = S["hip_x"]
        for front in (True, False):
            for side, sx in (("L", 1), ("R", -1)):
                y = (-1 if front else 1) * (self.L * 0.5 - 0.10)
                hip = Vector((hx * sx, y, -self.RZ * 0.35))
                name = ("F" if front else "H") + side
                u = qjoint("leg_u" + name, to, hip)
                lo = qjoint("leg_l" + name, to, (0, 0, 0))
                r0 = self.S.get("leg_r", 0.06)
                self.part("upper" + name, C.bm_tube([(0, 0, 0.04), (0, 0, -self.L1 * 0.5), (0, 0, -self.L1)],
                                                    [r0 * 1.5 if not front else r0 * 1.3, r0 * 1.15, r0 * 0.9], seg=10),
                          "fur", u)
                self.part("lower" + name, C.bm_tube([(0, 0, 0), (0, 0, -self.L2 * 0.6), (0, 0, -self.L2)],
                                                    [r0 * 0.85, r0 * 0.7, r0 * 0.75], seg=8), "fur_dark" if front else "fur", lo)
                self.build_foot(lo, name)
                self.legs_def.append({"name": name, "u": u, "l": lo, "hip": hip, "sx": sx, "front": front,
                                      "rest": Vector((hx * sx * 1.05, y, 0.0)),
                                      "phase": (0.0 if front else math.pi) + (0.35 if sx < 0 else 0.0)})
        self.dress()

    # -- géométrie -----------------------------------------------------------
    def torso_bm(self, keys=None):
        prof = [(0.00, 0.62, 0.70, 0.00), (0.10, 0.92, 0.94, 0.00), (0.30, 1.00, 1.00, 0.02), (0.55, 0.90, 0.86, 0.0),
                (0.78, 0.84, 0.82, -0.02), (0.94, 0.78, 0.76, -0.01), (1.0, 0.52, 0.52, 0.0)]
        prof = self.S.get("profile", prof)
        secs = []
        for u, kx, kz, dz in prof:
            secs.append(C.ellipse(0, dz, u * self.L, self.RX * kx, self.RZ * kz, 20))
        bm = C.bm_loft(secs)
        # loft le long de +Z → rotation : z (0..L) devient -y ; centré
        C.bm_xform(bm, loc=(0, self.L / 2, 0), rot=(math.pi / 2, 0, 0))
        return bm

    def build_torso(self, to) -> None:
        self.part("torsoM", self.torso_bm(), "fur", to)
        self.part("bellyM", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, -0.05, -self.RZ * 0.55),
                  scale=(self.RX * 0.75, self.L * 0.34, self.RZ * 0.4)), "belly", to)

    def build_neck(self, to, nk) -> None:
        hd = self.j["head"].location
        self.part("neckM", C.bm_tube([(0, 0.06, -0.04), (0, hd.y * 0.5, hd.z * 0.5), (0, hd.y, hd.z - 0.02)],
                                     [self.RZ * 0.75, self.RZ * 0.62, self.RZ * 0.5], seg=12), "fur", nk)

    def build_head(self, hd, jw) -> None:
        pass

    def build_tail(self, tl) -> None:
        pass

    def build_foot(self, lo, name: str) -> None:
        r0 = self.S.get("leg_r", 0.06)
        self.part("paw" + name, C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, -0.02, -self.L2),
                  scale=(r0 * 1.15, r0 * 1.45, r0 * 0.8)), "fur_dark", lo)

    def dress(self) -> None:
        pass

    # -- IK ------------------------------------------------------------------
    def place_legs(self, feet: dict) -> None:
        """Pieds en repère « body » (sol = z 0)."""
        bpy.context.view_layer.update()
        inv = self.j["torso"].matrix_basis.inverted()
        self.place_local({k: inv @ v for k, v in feet.items()})

    def place_local(self, feet: dict) -> None:
        """Pieds en repère du torse."""
        for Lg in self.legs_def:
            T = feet[Lg["name"]]
            S = Lg["hip"]
            pole = Vector((Lg["sx"] * 0.15, 1.0, 0.0 if Lg["front"] else 0.25))
            E, H = ik2(S, T, pole, self.L1, self.L2)
            Lg["u"].rotation_quaternion = DOWN.rotation_difference((E - S).normalized())
            Lg["l"].location = E
            Lg["l"].rotation_quaternion = DOWN.rotation_difference((H - E).normalized())

    def feet_rest(self) -> dict:
        return {Lg["name"]: Vector(Lg["rest"]) for Lg in self.legs_def}

    def rest(self) -> None:
        to = self.j["torso"]
        to.location = (0, 0, self.H)
        to.rotation_euler = (0, 0, 0)
        for k in ("neck", "head", "jaw", "tail", "body"):
            self.j[k].rotation_euler = (0, 0, 0)
        self.j["jaw"].rotation_euler = (self.S.get("jaw_idle", 0.12), 0, 0)
        self.j["body"].location = (0, 0, 0)

    # -- poses ---------------------------------------------------------------
    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        t = 2 * math.pi * i / n
        to = self.j["torso"]
        to.location.z = self.H - 0.01 * (1 + math.sin(t))
        to.scale = (1 + 0.015 * math.sin(t), 1, 1 + 0.02 * math.sin(t))
        self.j["neck"].rotation_euler = (0.05 * math.sin(t), 0, 0.12 * math.sin(t * 0.5))
        self.j["head"].rotation_euler = (0.06 * math.sin(t + 1), 0, 0)
        self.j["jaw"].rotation_euler = (0.12 + 0.18 * max(0.0, math.sin(t)), 0, 0)
        self.j["tail"].rotation_euler = (0.2, 0, 0.35 * math.sin(2 * t))
        self.place_legs(self.feet_rest())

    def pose_run(self, i: int, n: int) -> None:
        self.rest()
        p = 2 * math.pi * i / n
        to = self.j["torso"]
        to.scale = (1, 1, 1)
        to.location.z = self.H - 0.03 + 0.05 * abs(math.sin(p))
        to.rotation_euler = (0.10 * math.sin(p), 0, 0.04 * math.sin(p))
        self.j["neck"].rotation_euler = (-0.15 - 0.10 * math.sin(p), 0, 0)
        self.j["jaw"].rotation_euler = (0.35, 0, 0)
        self.j["tail"].rotation_euler = (-0.2 + 0.2 * math.sin(p), 0, 0.15 * math.sin(p))
        feet = {}
        stride = self.S.get("stride", 0.22)
        for Lg in self.legs_def:
            u = p + Lg["phase"]
            feet[Lg["name"]] = Vector(Lg["rest"]) + Vector((0, stride * math.cos(u), 0.16 * max(0.0, math.sin(u))))
        self.place_legs(feet)

    def pose_attack(self, i: int, n: int) -> None:
        # ramassé (0-2), bond gueule ouverte (3), morsure secouée (4), retour (5)
        self.rest()
        to = self.j["torso"]
        to.scale = (1, 1, 1)
        back = (0.04, 0.09, 0.10, -0.24, -0.20, -0.05)[i]
        low = (0.03, 0.07, 0.08, -0.04, 0.02, 0.01)[i]
        to.location = (0, back, self.H - low)
        to.rotation_euler = ((0.05, 0.12, 0.14, -0.12, 0.02, 0.0)[i], 0, (0.0, 0.0, 0.0, 0.0, 0.12, 0.0)[i])
        self.j["neck"].rotation_euler = ((-0.25, -0.35, -0.38, 0.15, 0.0, -0.1)[i], 0, (0, 0, 0, 0, -0.25, 0)[i])
        self.j["jaw"].rotation_euler = ((0.2, 0.3, 0.35, 0.85, 0.08, 0.2)[i], 0, 0)
        self.j["tail"].rotation_euler = (0.3, 0, 0.0)
        feet = self.feet_rest()
        if i == 3:
            for Lg in self.legs_def:
                if Lg["front"]:
                    feet[Lg["name"]] = Vector(Lg["rest"]) + Vector((0, -0.24, 0.10))
        self.place_legs(feet)

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        k = (1.0, 0.6, 0.25)[i]
        to = self.j["torso"]
        to.scale = (1, 1, 1)
        to.location = (0, 0.06 * k, self.H - 0.03 * k)
        to.rotation_euler = (0.12 * k, 0.08 * k, 0.1 * k)
        self.j["neck"].rotation_euler = (0.3 * k, 0, 0.2 * k)
        self.j["jaw"].rotation_euler = (0.5 * k, 0, 0)
        self.place_legs(self.feet_rest())

    def pose_death(self, i: int, n: int) -> None:
        # s'effondre sur le flanc ; dernière image = cadavre
        self.rest()
        t = i / (n - 1)
        e = smooth((t - 0.1) / 0.6)
        to = self.j["torso"]
        to.scale = (1, 1, 1)
        bounce = 0.0
        if t > 0.75:
            v = (t - 0.75) / 0.25
            bounce = 0.03 * math.sin(v * math.pi) * (1 - v)
        to.location = (0, 0, self.H * (1 - e) + (self.RX * 1.05) * e + 0.05 * math.sin(min(1.0, t * 2.5) * math.pi) * (1 - e) + bounce)
        to.rotation_euler = (0, (math.pi / 2 - 0.15) * e, 0.2 * e)
        self.j["neck"].rotation_euler = (0.25 * e - 0.3 * (1 - e) * (t < 0.3), 0, 0.3 * e)
        self.j["head"].rotation_euler = (0.2 * e, 0, 0)
        self.j["jaw"].rotation_euler = (0.25 + 0.2 * e, 0, 0)
        self.j["tail"].rotation_euler = (0.5 * e, 0, 0)
        if e < 0.05:
            self.place_legs(self.feet_rest())
            return
        # pattes molles, à peu près tendues dans le repère du torse
        loc = {}
        for Lg in self.legs_def:
            h = Lg["hip"]
            reach = (self.L1 + self.L2) * 0.88
            stiff = Vector((h.x * 1.6, h.y + (0.10 if Lg["front"] else 0.16) * (1 if Lg["front"] else -0.4), h.z - reach))
            bpy.context.view_layer.update()
            rest_l = self.j["torso"].matrix_basis.inverted() @ Vector(Lg["rest"])
            loc[Lg["name"]] = rest_l.lerp(stiff, e)
        self.place_local(loc)


class CircusDog(Quad):
    """Molosse-hyène de cirque : avant massif et bossu, caparaçon d'or sur les épaules, épines roses,
    gueule béante pleine de crocs, oreilles en cornes."""

    def pose(self, anim: str, i: int, n: int) -> None:
        super().pose(anim, i, n)
        # tête dressée, gueule tournée vers le joueur (lisible sous la caméra 3/4)
        if anim != "death":
            self.j["neck"].rotation_euler.x -= 0.30
            self.j["head"].rotation_euler.x -= 0.62
            self.j["tail"].rotation_euler.x -= 0.9

    def build_head(self, hd, jw) -> None:
        S = self.S
        hl = S["head_len"]
        sk = C.bm_sphere(16, 12, 1.0)
        for v in sk.verts:
            x, y, z = v.co
            v.co = Vector((x * 0.17, y * 0.16, z * 0.14 + 0.03))
        self.part("skull", sk, "fur", hd)
        self.part("snout", C.bm_tube([(0, -0.06, 0.02), (0, -hl * 0.55, 0.0), (0, -hl * 0.80, -0.01)], [0.115, 0.10, 0.075],
                                     seg=12, flat=0.80), "muzzle", hd)
        self.part("nose", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, -hl * 0.82, 0.02), scale=(0.045, 0.03, 0.032)),
                  "fur_dark", hd)
        self.part("gumU", C.bm_xform(C.bm_box(0.15, hl * 0.62, 0.035, bevel=0.012), loc=(0, -hl * 0.48, -0.05)), "gum", hd)
        # rangée de crocs du haut
        for k in range(7):
            u = k / 6
            x = 0.065 * math.cos(math.pi * u)
            y = -hl * (0.30 + 0.45 * math.sin(math.pi * u))
            L = 0.07 if k in (1, 5) else 0.045
            self.part("fangU", C.bm_xform(C.bm_cyl(6, 0.015, 0.0, L), loc=(x, y, -0.07 - L * 0.4), rot=(math.pi, 0, 0)),
                      "tooth", hd)
        for sx in (1, -1):
            self.part("eye", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.07 * sx, -0.13, 0.07), scale=(0.036, 0.016, 0.026)),
                      "eye_glow", hd, nofs=True)
            self.part("brow", C.bm_xform(C.bm_box(0.09, 0.045, 0.035, bevel=0.01), loc=(0.07 * sx, -0.12, 0.105),
                      rot=(0, -0.45 * sx, 0)), "fur_dark", hd)
            # oreilles en cornes recourbées
            pts = C.bezier((0.08 * sx, 0.02, 0.12), (0.12 * sx, 0.02, 0.24), (0.16 * sx, 0.06, 0.30), (0.12 * sx, 0.12, 0.34), 6)
            self.part("ear", C.bm_tube(pts, [0.045, 0.04, 0.032, 0.022, 0.012, 0.0], seg=6), "fur_dark", hd)
            self.part("cheek", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.13 * sx, -0.04, -0.01), scale=(0.06, 0.07, 0.07)),
                      "fur", hd)
        # gueule béante tournée vers l'avant : fond rouge sombre, gencives, crocs tout autour
        mz = Vector((0, -hl * 0.80, -0.075))
        self.part("maw", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=mz, scale=(0.080, 0.035, 0.085)), "maw", hd, nofs=True)
        self.part("mawRim", C.bm_xform(C.bm_torus(18, 6, 1.0, 0.16), loc=mz + Vector((0, -0.01, 0)), rot=(math.pi / 2, 0, 0),
                  scale=(0.083, 0.088, 0.08)), "gum", hd)
        for k in range(9):
            a = math.pi * (0.12 + 0.76 * k / 8)
            for top in (1, -1):
                x = 0.075 * math.cos(a)
                z = top * 0.072 * math.sin(a)
                L = 0.05 if k in (1, 7) else 0.032
                self.part("fangM", C.bm_xform(C.bm_cyl(6, 0.012, 0.0, L), loc=mz + Vector((x, -0.035, z)),
                          rot=(math.pi if top > 0 else 0.0, 0, 0)), "tooth", hd, nofs=True)
        # crête d'épines sur le crâne
        for k in range(3):
            self.part("crest", C.bm_xform(C.bm_cyl(5, 0.025, 0.0, 0.10 - 0.02 * k), loc=(0, 0.02 + 0.06 * k, 0.16 - 0.02 * k),
                      rot=(-0.4, 0, 0)), "spike", hd)
        # mâchoire inférieure béante
        self.part("jawM", C.bm_tube([(0, 0.0, -0.03), (0, -hl * 0.45, -0.04), (0, -hl * 0.68, -0.03)], [0.085, 0.07, 0.05],
                                    seg=10, flat=0.6), "muzzle", jw)
        self.part("gumL", C.bm_xform(C.bm_box(0.12, hl * 0.52, 0.025, bevel=0.008), loc=(0, -hl * 0.38, 0.015)), "gum", jw)
        self.part("tongue", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0, -hl * 0.36, 0.03), scale=(0.05, hl * 0.25, 0.015)),
                  "maw", jw)
        for k in range(5):
            u = k / 4
            x = 0.05 * math.cos(math.pi * u)
            y = -hl * (0.28 + 0.36 * math.sin(math.pi * u))
            self.part("fangL", C.bm_xform(C.bm_cyl(6, 0.013, 0.0, 0.05), loc=(x, y, 0.045)), "tooth", jw)
        self.muzzle_ref = ("fangU", (0.0, -hl * 0.80, -0.05))

    def build_torso(self, to) -> None:
        super().build_torso(to)
        L, RX, RZ = self.L, self.RX, self.RZ
        # bosse d'épaules massive, caparaçon d'or ouvragé (épaules + poitrail)
        self.part("hump", C.bm_xform(C.bm_sphere(16, 12, 1.0), loc=(0, -L * 0.24, RZ * 0.55), scale=(RX * 1.15, L * 0.26, RZ * 0.85)),
                  "fur", to)
        for sx in (1, -1):
            for k in range(3):
                self.part("pauldron", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(sx * RX * 0.92, -L * 0.36 + 0.07 * k, RZ * 0.55 - 0.05 * k),
                          scale=(0.07, 0.10, 0.11 - 0.015 * k), rot=(0, 0.7 * sx, 0)), "armor", to)
            self.part("stud", C.bm_xform(C.bm_sphere(8, 6, 0.028), loc=(sx * (RX * 1.0 + 0.09), -L * 0.30, RZ * 0.40)),
                      "brass", to)
        self.part("breastplate", C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, -L * 0.47, -RZ * 0.05), scale=(RX * 0.95, 0.07, RZ * 0.9)),
                  "armor", to)
        self.part("harness", C.bm_xform(C.bm_torus(18, 6, 1.0, 0.045), loc=(0, -L * 0.08, 0.01), rot=(math.pi / 2, 0, 0),
                  scale=(RX * 1.05, RZ * 1.05, 1)), "armor", to)
        # épines roses le long du dos, plus hautes sur la bosse
        for k in range(8):
            y = -L * 0.36 + L * 0.105 * k
            h = (0.16, 0.18, 0.16, 0.12, 0.10, 0.09, 0.08, 0.07)[k]
            zt = RZ * (1.25 if k < 3 else 0.95) + h * 0.35
            self.part("spine", C.bm_xform(C.bm_cyl(5, 0.035, 0.0, h), loc=(0, y, zt), rot=(0.55, 0, 0)), "spike", to)
        for sx in (1, -1):
            for k in range(3):
                self.part("sideSpike", C.bm_xform(C.bm_cyl(5, 0.03, 0.0, 0.12), loc=(sx * RX * 0.85, -L * 0.20 + 0.10 * k, RZ * 0.85),
                          rot=(0.4, 0.8 * sx, 0)), "spike", to)

    def build_neck(self, to, nk) -> None:
        super().build_neck(to, nk)
        hd = self.j["head"].location
        # collier à pointes de laiton
        c = Vector((0, hd.y * 0.4, hd.z * 0.4))
        self.part("collar", C.bm_xform(C.bm_torus(18, 6, self.RZ * 0.80, 0.02), loc=c, rot=(math.pi / 2 - 0.5, 0, 0)), "fur_dark", nk)
        for k in range(8):
            a = 2 * math.pi * k / 8
            off = Vector((math.cos(a) * self.RZ * 0.85, math.sin(a) * 0.04, math.sin(a) * self.RZ * 0.85))
            self.part("collarSpike", C.bm_xform(C.bm_cyl(5, 0.02, 0.0, 0.06), loc=c + off,
                      rot=(0, math.pi / 2 - a, 0)), "brass", nk)

    def build_foot(self, lo, name: str) -> None:
        r0 = self.S.get("leg_r", 0.06)
        self.part("paw" + name, C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, -0.03, -self.L2),
                  scale=(r0 * 1.35, r0 * 1.6, r0 * 0.85)), "fur_dark", lo)
        for k in range(3):
            x = (k - 1) * 0.035
            self.part("claw" + name, C.bm_xform(C.bm_cyl(5, 0.012, 0.0, 0.05), loc=(x, -0.03 - r0 * 1.5, -self.L2 - 0.01),
                      rot=(math.pi / 2 + 0.3, 0, 0)), "tooth", lo)

    def dress(self) -> None:
        # avant-bras massifs (pattes avant de colosse), griffes
        for Lg in self.legs_def:
            if Lg["front"]:
                self.part("forearm" + Lg["name"], C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.01, -self.L1 * 0.45),
                          scale=(0.11, 0.12, self.L1 * 0.62)), "fur", Lg["u"])
                self.part("bracer" + Lg["name"], C.bm_xform(C.bm_cyl(12, 0.085, 0.075, 0.10), loc=(0, 0, -self.L2 * 0.45)),
                          "armor", Lg["l"])

    def build_tail(self, tl) -> None:
        self.part("tailM", C.bm_tube(C.bezier((0, 0, 0), (0, 0.12, 0.10), (0, 0.24, 0.12), (0, 0.34, 0.06), 7),
                                     [0.045, 0.04, 0.035, 0.03, 0.025, 0.018, 0.0], seg=8), "fur_dark", tl)


class GhostCarousel(Quad):
    """Cheval de manège hanté : bois peint gris lavande craquelé, crinière sombre, rubans orangés ;
    glisse sur sa barre dorée (pied lumineux), pattes avant levées en galop de manège ; se cabre
    puis s'abat (piétinement de zone)."""

    POLE_TOP = 1.95

    def pose(self, anim: str, i: int, n: int) -> None:
        super().pose(anim, i, n)
        if anim != "death":
            # encolure arquée, tête haute et de trois quarts vers le joueur
            self.j["neck"].rotation_euler.x -= 0.30
            self.j["head"].rotation_euler.x -= 0.20

    def build_neck(self, to, nk) -> None:
        hd = self.j["head"].location
        self.part("neckM", C.bm_tube([(0, 0.08, -0.06), (0, hd.y * 0.45, hd.z * 0.55), (0, hd.y, hd.z - 0.02)],
                                     [self.RZ * 0.85, self.RZ * 0.62, self.RZ * 0.46], seg=12), "coat", nk)
        # crinière sombre ondulée, épaisse, le long de l'encolure
        a0, a1 = Vector((0, 0.08, -0.06)), Vector((0, hd.y, hd.z))
        dirv = (a1 - a0).normalized()
        back = Vector((0, -dirv.z, dirv.y)) if dirv.y < 0 else Vector((0, dirv.z, -dirv.y))
        if back.z < 0:
            back = -back
        for k in range(9):
            u = k / 8
            c = a0.lerp(a1, u) + back * (self.RZ * (0.85 - 0.40 * u) + 0.07)
            self.part("mane%d" % k, C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=c + Vector((0.03 * (-1) ** k, 0, 0)),
                      scale=(0.06, 0.09, 0.10 - 0.03 * u), rot=(0.5, 0.35 * (-1) ** k, 0)), "mane", nk)
        for k in range(3):
            u = 0.25 + 0.25 * k
            self.part("swirlN", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.0, hd.y * u - 0.16, hd.z * u - 0.10),
                      scale=(0.11, 0.03, 0.035), rot=(0.6, 0, 0)), "swirl", nk, nofs=True)

    def build_head(self, hd, jw) -> None:
        hl = self.S["head_len"]
        sk = C.bm_sphere(16, 12, 1.0)
        for v in sk.verts:
            x, y, z = v.co
            v.co = Vector((x * 0.135, y * 0.15, z * 0.14 + 0.03))
        hd.scale = (1.18, 1.18, 1.18)
        self.part("skull", sk, "coat", hd)
        self.part("snout", C.bm_tube([(0, -0.06, 0.02), (0, -hl * 0.5, -0.04), (0, -hl * 0.72, -0.09)], [0.12, 0.10, 0.085],
                                     seg=12, flat=0.8), "coat", hd)
        self.part("nostril", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -hl * 0.74, -0.08), scale=(0.065, 0.035, 0.045)),
                  "muzzle", hd)
        for sx in (1, -1):
            # orbites creuses, lueur orangée
            self.part("socket", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.09 * sx, -0.10, 0.07), scale=(0.035, 0.028, 0.03)),
                      "socket", hd, nofs=True)
            self.part("eye", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.10 * sx, -0.11, 0.07), scale=(0.016, 0.012, 0.014)),
                      "eye_glow", hd, nofs=True)
            self.part("ear", C.bm_xform(C.bm_cyl(5, 0.04, 0.0, 0.13), loc=(0.055 * sx, 0.04, 0.17), rot=(-0.15, 0.25 * sx, 0)),
                      "coat", hd)
            # bride dorée, rubans orangés qui pendent
            self.part("bridle", C.bm_xform(C.bm_torus(14, 5, 0.08, 0.013), loc=(0, -hl * 0.45, -0.03), rot=(math.pi / 2, 0, 0),
                      scale=(1.2, 1, 0.95)), "gold", hd)
            self.part("ribbon", C.bm_tube(C.bezier((0.10 * sx, -hl * 0.30, 0.0), (0.12 * sx, -hl * 0.30, -0.10),
                                                   (0.11 * sx, -hl * 0.22, -0.18), (0.12 * sx, -hl * 0.18, -0.26), 5),
                                          [0.022, 0.022, 0.02, 0.016, 0.01], seg=5, flat=0.35), "ribbon", hd)
            self.part("rosette", C.bm_xform(C.bm_sphere(10, 6, 0.035), loc=(0.10 * sx, -hl * 0.30, 0.01)), "ribbon", hd)
        # toupet de crinière sur le front
        self.part("forelock", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.0, -0.03, 0.15),
                  scale=(0.035, 0.05, 0.03), rot=(0.6, 0, 0)), "mane", hd)
        # crinière qui retombe derrière la tête, sur un côté (visible de dessus)
        for k in range(5):
            self.part("maneH", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(-0.07 - 0.015 * k, 0.07 + 0.05 * k, 0.12 - 0.06 * k),
                      scale=(0.045, 0.07, 0.07), rot=(0.5, -0.5, 0)), "mane", hd)
        self.part("jawM", C.bm_tube([(0, -0.02, -0.04), (0, -hl * 0.45, -0.07), (0, -hl * 0.6, -0.08)], [0.06, 0.05, 0.035],
                                    seg=8, flat=0.7), "coat", jw)
        self.part("gum", C.bm_xform(C.bm_box(0.07, hl * 0.4, 0.02), loc=(0, -hl * 0.38, -0.02)), "gum", jw)
        # fissures (bois peint craquelé)
        for sx in (1, -1):
            self.part("crack", C.bm_tube([(0.11 * sx, -0.04, 0.10), (0.10 * sx, -0.12, 0.04), (0.11 * sx, -0.18, 0.05)],
                                         [0.008] * 3, seg=4), "crack", hd, nofs=True)
        self.muzzle_ref = ("snout", (0, -hl * 0.72, -0.07))

    def build_torso(self, to) -> None:
        super().build_torso(to)
        L, RX, RZ = self.L, self.RX, self.RZ
        # petite selle sombre ourlée d'or, tapis ouvragé
        self.part("saddle", C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, 0.04, RZ * 0.86), scale=(RX * 0.85, 0.15, 0.06)),
                  "saddle", to)
        self.part("saddleTrim", C.bm_xform(C.bm_torus(18, 5, 1.0, 0.10), loc=(0, 0.04, RZ * 0.86), scale=(RX * 0.85, 0.15, 0.4)),
                  "gold", to)
        self.part("strap", C.bm_xform(C.bm_torus(18, 6, 1.0, 0.04), loc=(0, 0.04, 0.0), rot=(math.pi / 2, 0, 0),
                  scale=(RX * 1.03, RZ * 1.03, 1)), "saddle", to)
        # motifs peints (volutes claires) sur les flancs et la croupe
        for sx in (1, -1):
            for k, (y, z, r) in enumerate(((-0.20, 0.04, 0.09), (0.22, 0.05, 0.10), (0.32, -0.08, 0.06), (-0.02, -0.10, 0.06))):
                self.part("swirl", C.bm_xform(C.bm_torus(14, 5, r, 0.018), loc=(sx * RX * 0.99, y, z), rot=(0, math.pi / 2, 0),
                          scale=(1, 1, 0.8)), "swirl", to, nofs=True)
            self.part("medal", C.bm_xform(C.bm_cyl(10, 0.04, 0.04, 0.015), loc=(sx * RX * 0.99, -0.20, 0.02), rot=(0, math.pi / 2, 0)),
                      "ribbon", to, nofs=True)
        # poitrail doré, pendeloques
        self.part("breast", C.bm_xform(C.bm_torus(20, 5, 1.0, 0.03), loc=(0, -L * 0.30, 0.0), rot=(math.pi / 2, 0, 0),
                  scale=(RX * 1.03, RZ * 1.03, 1)), "gold", to)
        for k in range(3):
            self.part("jewel", C.bm_xform(C.bm_sphere(8, 6, 0.025), loc=(0, -L * 0.42 - 0.01, RZ * (0.3 - 0.3 * k))), "neon_red",
                      to, nofs=True)
        self.part("crackB", C.bm_tube([(RX * 0.98, -0.10, 0.05), (RX * 0.99, 0.0, -0.03), (RX * 0.97, 0.10, 0.02)], [0.008] * 3,
                                      seg=4), "crack", to, nofs=True)

    def build_tail(self, tl) -> None:
        for k in range(3):
            self.part("tailM%d" % k, C.bm_tube(C.bezier((0.02 * (k - 1), 0, 0), (0.03 * (k - 1), 0.12, 0.02), (0.04 * (k - 1), 0.22, -0.10),
                                                        (0.05 * (k - 1), 0.26, -0.30), 7),
                                               [0.05, 0.05, 0.045, 0.04, 0.03, 0.02, 0.0], seg=7), "mane", tl)

    def build_foot(self, lo, name: str) -> None:
        r0 = self.S.get("leg_r", 0.06)
        self.part("hoof" + name, C.bm_xform(C.bm_cyl(10, r0 * 1.0, r0 * 1.25, 0.08), loc=(0, 0, -self.L2 + 0.02)), "gold", lo)

    def dress(self) -> None:
        # barre dorée torsadée (traverse le cheval), pied lumineux, fleuron
        body = self.j["body"]
        g = joint("pole", body, (0, 0.02, 0))
        self.pole = g
        pts = [(0.0, 0.0, 0.05), (0.0, 0.0, self.POLE_TOP)]
        self.part("poleM", C.bm_tube(pts, [0.028, 0.028], seg=10), "gold", g)
        for k in range(14):
            z = 0.12 + (self.POLE_TOP - 0.2) * k / 13
            self.part("twist", C.bm_xform(C.bm_torus(10, 4, 0.03, 0.009), loc=(0, 0, z), rot=(0.5, 0, 0.6 * k)), "gold", g)
        self.part("finial", C.bm_xform(C.bm_sphere(12, 8, 0.055), loc=(0, 0, self.POLE_TOP + 0.03)), "gold", g)
        self.part("base", C.bm_xform(C.bm_cyl(24, 0.22, 0.26, 0.05), loc=(0, 0, 0.025)), "mane", g)
        self.part("baseRim", C.bm_xform(C.bm_torus(28, 5, 0.25, 0.012), loc=(0, 0, 0.05)), "gold", g)
        for k in range(10):
            a = 2 * math.pi * k / 10
            self.part("bulb", C.bm_xform(C.bm_sphere(8, 6, 0.024), loc=(0.235 * math.cos(a), 0.235 * math.sin(a), 0.06)),
                      "neon", g, nofs=True)
        for k in range(6):
            a = 2 * math.pi * k / 6 + 0.5
            self.part("ghost", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.36 * math.cos(a), 0.36 * math.sin(a), 0.02),
                      scale=(0.035, 0.035, 0.012)), "neon", g, nofs=True, grp="ghost")

    def rest(self) -> None:
        super().rest()
        self.pole.rotation_euler = (0, 0, 0)
        self.pole.location = (0, 0.02, 0)
        self.show("ghost", True)

    def carousel_legs(self, gallop: float = 0.0, kick: float = 0.0) -> None:
        """Pattes de cheval de bois : avant repliées, arrière tendues (repère du torse)."""
        loc = {}
        for Lg in self.legs_def:
            h = Lg["hip"]
            if Lg["front"]:
                fold = 0.5 + 0.25 * gallop * (1 if Lg["sx"] > 0 else -1)
                T = h + Vector((0, -0.08 - 0.22 * fold - 0.30 * kick, -0.42 + 0.18 * fold + 0.25 * kick))
            else:
                st = 0.5 - 0.2 * gallop * (1 if Lg["sx"] > 0 else -1)
                T = h + Vector((0, 0.20 + 0.20 * st, -0.42 + 0.06 * st))
            loc[Lg["name"]] = T
        self.place_local(loc)

    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        t = 2 * math.pi * i / n
        to = self.j["torso"]
        to.scale = (1, 1, 1)
        to.location.z = self.H + 0.07 * math.sin(t)
        to.rotation_euler = (-0.20 + 0.06 * math.sin(t + 0.8), 0, 0)
        self.j["neck"].rotation_euler = (-0.1 + 0.06 * math.sin(t), 0, 0.08 * math.sin(t * 0.5))
        self.j["jaw"].rotation_euler = (0.10 + 0.12 * max(0.0, math.sin(t)), 0, 0)
        self.j["tail"].rotation_euler = (0.1, 0, 0.15 * math.sin(t))
        self.carousel_legs(0.2 * math.sin(t), kick=0.35)

    def pose_run(self, i: int, n: int) -> None:
        # monte et descend sur sa barre en se balançant (mouvement de manège)
        self.rest()
        p = 2 * math.pi * i / n
        to = self.j["torso"]
        to.scale = (1, 1, 1)
        to.location.z = self.H + 0.13 * math.sin(p)
        to.rotation_euler = (0.16 * math.cos(p), 0, 0)
        self.j["neck"].rotation_euler = (-0.15 - 0.12 * math.cos(p), 0, 0)
        self.j["jaw"].rotation_euler = (0.2, 0, 0)
        self.j["tail"].rotation_euler = (0.25 * math.cos(p), 0, 0)
        self.pole.rotation_euler = (-0.06, 0, 0)
        self.carousel_legs(math.sin(p))

    def pose_attack(self, i: int, n: int) -> None:
        # se cabre en hennissant (0-2), retombe en piétinant (3), rebond (4-5)
        self.rest()
        to = self.j["torso"]
        to.scale = (1, 1, 1)
        rear = (0.25, 0.50, 0.58, -0.22, -0.12, 0.0)[i]
        to.location = (0, (0.02, 0.06, 0.07, -0.10, -0.06, 0.0)[i],
                       self.H + 0.22 * max(0.0, rear) - 0.30 * max(0.0, -rear))
        to.rotation_euler = (-rear, 0, 0)
        self.j["neck"].rotation_euler = ((-0.1, 0.2, 0.25, -0.35, -0.2, -0.1)[i], 0, 0)
        self.j["jaw"].rotation_euler = ((0.3, 0.6, 0.7, 0.4, 0.2, 0.1)[i], 0, 0)
        self.carousel_legs(0.0, kick=(0.4, 0.9, 1.0, -0.2, 0.0, 0.0)[i])
        if i in (3, 4):
            self.show("ghost", True)

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        k = (1.0, 0.6, 0.25)[i]
        to = self.j["torso"]
        to.scale = (1, 1, 1)
        to.location = (0, 0.05 * k, self.H - 0.05 * k)
        to.rotation_euler = (0.15 * k, 0.1 * k, 0.12 * k)
        self.j["neck"].rotation_euler = (0.3 * k, 0, 0.2 * k)
        self.carousel_legs(0.3 * k)

    def pose_death(self, i: int, n: int) -> None:
        # glisse le long de la barre et bascule au pied du manège, éteint
        self.rest()
        t = i / (n - 1)
        e = smooth(t / 0.75)
        to = self.j["torso"]
        to.scale = (1, 1, 1)
        drop = smooth(t / 0.45)
        tip = smooth((t - 0.35) / 0.5)
        to.location = (0.42 * tip, 0.05 * tip, self.H * (1 - drop) + 0.30 * drop * (1 - tip) + self.RX * 1.05 * tip)
        to.rotation_euler = (0.1 * tip, 1.42 * tip, 0.2 * tip)
        self.j["neck"].rotation_euler = (0.35 * e, 0, 0.3 * e)
        self.j["jaw"].rotation_euler = (0.35, 0, 0)
        self.carousel_legs(0.0)
        self.show("ghost", t < 0.6)


CLASSES = {
    "cv_lost_clown": LostClown, "cv_acrobat": Acrobat, "cv_circus_dog": CircusDog,
    "cv_ghost_carousel": GhostCarousel, "cv_penumbra": Penumbra, "cv_big_plush": BigPlush,
    "cv_fairground_being": FairgroundBeing, "cv_fire_clown": FireClown, "cv_circus_king": CircusKing,
}

M.SPEC.update(SPEC)
M.CLASSES.update(CLASSES)


# =============================================================================== planche
def presentation_sheet(kinds) -> None:
    """Planche de présentation (captures de PR) : idle 3/4 face + attaque + cadavre, à l'échelle du jeu,
    sur fond nuit violet, depuis les images déjà rendues (RDM_CV_TMP)."""
    from PIL import Image, ImageDraw, ImageFont
    fb = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    fr = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    if not os.path.exists(fb):  # macOS
        fb = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
        fr = "/System/Library/Fonts/Supplemental/Arial.ttf"
    title_f = ImageFont.truetype(fb, 30)
    name_f = ImageFont.truetype(fb, 17)
    sub_f = ImageFont.truetype(fr, 13)
    cols = 3
    cell_w, cell_h = 440, 330
    rows = (len(kinds) + cols - 1) // cols
    W, H = cols * cell_w + 40, rows * cell_h + 90
    sheet = Image.new("RGBA", (W, H), (20, 12, 34, 255))
    dr = ImageDraw.Draw(sheet)
    for y in range(H):
        c = int(12 + 18 * y / H)
        dr.line([(0, y), (W, y)], fill=(c + 10, c, c + 26, 255))
    dr.text((24, 20), "CARNAVAL HANTÉ — Le parc maudit", font=title_f, fill=(206, 110, 255, 255))
    tags = {k: "ÉLITE" for k in ELITES}
    tags[BOSS] = "BOSS"
    for idx, kind in enumerate(kinds):
        cx = 20 + (idx % cols) * cell_w
        cy = 80 + (idx // cols) * cell_h
        boss = kind == BOSS
        dr.rounded_rectangle([cx, cy, cx + cell_w - 12, cy + cell_h - 12], 14, fill=(22, 16, 40, 235),
                             outline=(235, 60, 80, 255) if boss else (176, 100, 240, 255), width=2)
        tmp = os.path.join(M.TMP_DIR, kind)
        F = M.out_frame(kind)
        n_death = M.anims_for(kind)["death"][0]
        shots = [("idle_se_0", "idle"), ("attack_sw_3", "attaque"), ("death_s_%d" % (n_death - 1), "cadavre")]
        if F > 256:
            shots = shots[:2]
        w = (cell_w - 32) // len(shots)
        k = min(1.0, (cell_h - 70) / F, 1.1 * w / F if F > 256 else 9.0)
        x = cx + 10
        for fname, label in shots:
            path = os.path.join(tmp, fname + ".png")
            if not os.path.exists(path):
                continue
            im = Image.open(path).convert("RGBA")
            if k < 1.0:
                im = im.resize((int(im.size[0] * k), int(im.size[1] * k)), Image.LANCZOS)
            sheet.alpha_composite(im, (x + (w - im.size[0]) // 2, cy + 46 + (cell_h - 110 - im.size[1]) // 2 + 10))
            dr.text((x + w // 2 - 20, cy + cell_h - 40), label, font=sub_f, fill=(200, 190, 215, 255))
            x += w
        dr.text((cx + 14, cy + 10), SPEC[kind]["name"].upper(), font=name_f, fill=(255, 255, 255, 255))
        if kind in tags:
            col = (255, 90, 90, 255) if tags[kind] == "BOSS" else (200, 120, 255, 255)
            dr.text((cx + cell_w - 90, cy + 10), tags[kind], font=name_f, fill=col)
        dr.text((cx + 14, cy + 30), kind, font=sub_f, fill=(160, 150, 185, 255))
    os.makedirs(M.CAPT_DIR, exist_ok=True)
    out = os.path.join(M.CAPT_DIR, "planche_modeles_carnival.png")
    sheet.convert("RGB").save(out)
    print("SHEET", out)


def hipreview(kinds, dirs, anims_spec) -> None:
    """Aperçu d'évaluation : garde le rendu ×2 (avant réduction) et l'image à la taille du jeu
    (RDM_CV_TMP/prev_<kind>_<anim>_<dir>_<i>{,_hi}.png)."""
    for kind in kinds:
        rig, cam = M.setup_scene(kind)
        F = M.out_frame(kind)
        for d in dirs:
            rig.j["root"].rotation_euler = (0, 0, math.radians(M.DIRS[d]))
            rig.dir_ang = M.DIRS[d]
            for a in anims_spec:
                an, i = a.split(":")
                n = M.anims_for(kind)[an][0]
                rig.pose(an, int(i), n)
                p = os.path.join(M.TMP_DIR, "prev_%s_%s_%s_%s" % (kind, an, d, i))
                C.render_to(p + "_hi.png")
                C.downscale(p + "_hi.png", p + ".png", (F, F))
        print("HIPREVIEW", kind)


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    kinds = args[args.index("--kinds") + 1].split(",") if "--kinds" in args else KINDS
    os.makedirs(M.TMP_DIR, exist_ok=True)
    if "--sheet" in args:
        presentation_sheet(kinds)
        return
    if "--repack" in args:
        for k in kinds:
            M.repack(k)
        return
    if "--hipreview" in args:
        dirs = args[args.index("--hipreview") + 1].split(",")
        anims = args[args.index("--anim") + 1].split(",") if "--anim" in args else ["idle:0"]
        hipreview(kinds, dirs, anims)
        return
    if "--preview" in args:
        dirs = args[args.index("--preview") + 1].split(",")
        anims = args[args.index("--anim") + 1].split(",") if "--anim" in args else ["idle:0"]
        M.preview(kinds, dirs, anims)
        return
    for k in kinds:
        M.build_kind(k)


if __name__ == "__main__":
    main()
