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
    cv_lost_clown        Clown égaré : animateur possédé, collerette, ballons rouge et noir
    cv_acrobat           Acrobate sanguinaire : arlequin longiligne, chapeau à grelots, faucille
    cv_circus_dog        Chien de cirque : molosse griffu à collerette de clown (quadrupède)
    cv_ghost_carousel    Manège fantôme : cheval de bois hanté sur sa barre dorée (quadrupède)
    cv_penumbra          Pénombre : silhouette encapuchonnée, yeux rouges, lame courbe, ballons
    cv_big_plush         Grosse peluche : ours en peluche géant possédé, coutures, rembourrage
    cv_fairground_being  L'Être forain (élite) : maître de piste au haut-de-forme, canne dorée
    cv_fire_clown        Le Clown de feu (élite) : clown en flammes, boules de feu
    cv_circus_king       Le Roi du cirque (boss) : clown géant couronné, sceptre, grande roue de néon

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
        "name": "Clown égaré", "rig": "human", "frame": 192, "scale": 1.02, "head": 1.22, "leg": 0.80,
        "torso": (1.06, 1.00), "arm": 0.98, "arm_len": 1.06, "hunch": 0.18, "belly": 0.4, "fps_run": 11,
        "top_key": "costume", "hand_key": "glove",
        "mats": dict(RUFF, **{
            "face": ("#d6ccd0", "#4a3a5e", "#f4eef0"),
            "skin": ("#d6ccd0", "#4a3a5e", "#f4eef0"),
            "nose": ("#e01a2a", "#5a0618", "#ff5a5a"),
            "lips": ("#a80c22", "#3a0212", "#e02a3a"),
            "makeup": ("#1a1020", "#08040c", "#30203a"),
            "hair": ("pat", [("#e2401c", "#5a0e1a", "#ff7a3a"), ("#c02a1a", "#4a0a18", "#ee5a2a")], 9.0),
            "costume": ("pat", [("#c4202c", "#46081e", "#ee4a4a"), ("#e8dcc8", "#6a5a74", "#ffffff")], 3.0),
            "pants": ("pat", [("#4a2a6a", "#160a2a", "#74489e"), ("#3a1e58", "#100620", "#5e3a88")], 6.0),
            "shoe": ("#d0202a", "#4a0618", "#ff4a4a"),
            "glove": ("#efe8e0", "#6a6078", "#ffffff"),
            "pompom": ("#f2eee6", "#7a7090", "#ffffff"),
            "eye_glow": "!#ffd23a",
            "balloon_a": ("#e01c2c", "#5a0418", "#ff6a6a"),
            "balloon_b": ("#26202e", "#0a060e", "#5a4a6a"),
            "string": ("#d8d0c8", "#5a5060", "#ffffff"),
        }),
    },
    "cv_acrobat": {
        "name": "Acrobate sanguinaire", "rig": "human", "frame": 192, "scale": 1.04, "head": 1.04, "leg": 0.96,
        "torso": (0.80, 0.78), "arm": 0.78, "arm_len": 1.20, "hunch": 0.22, "fps_run": 16, "stride": 1.0,
        "top_key": "suit_a", "sleeve_key": "suit_b", "pants_key": "suit_a", "hand_key": "glove",
        "mats": {
            "suit_a": ("#c01e2c", "#40061c", "#ee4a4a"),
            "suit_b": ("#e6dcc4", "#6a5a74", "#ffffff"),
            "diamond": ("#221628", "#08040c", "#3e2a48"),
            "mask": ("#efe6da", "#6e5e7a", "#ffffff"),
            "skin": ("#efe6da", "#6e5e7a", "#ffffff"),
            "makeup": ("#140a18", "#060208", "#2a1a30"),
            "lips": ("#b0101e", "#3a0210", "#e02a3a"),
            "glove": ("#2a1e30", "#0a060e", "#46364e"),
            "shoe": ("#2a1e30", "#0a060e", "#46364e"),
            "bell": ("#e8b830", "#6a3a18", "#fff090"),
            "blade": ("#a8aec0", "#343a52", "#eef2fa"),
            "blood": ("#8a0a1c", "#300210", "#c01a2a"),
            "pole": ("#3a2420", "#100808", "#5e3e32"),
            "eye_glow": "!#ff2a3a",
        },
    },
    "cv_circus_dog": {
        "name": "Chien de cirque", "rig": "quad", "frame": 192, "scale": 1.34, "fps_run": 17,
        "height": 0.50, "length": 0.78, "girth": (0.19, 0.20), "leg": (0.27, 0.29), "hip_x": 0.13,
        "neck_len": 0.20, "head_len": 0.34,
        "mats": dict(RUFF, **{
            "fur": ("pat", [("#7a4a30", "#22101e", "#a8683e"), ("#4e2e22", "#180a14", "#70442e"),
                            ("#94582e", "#2a1220", "#c07a40")], 6.0),
            "fur_dark": ("#2e1c1c", "#0c0608", "#4a3028"),
            "belly": ("#b88a5e", "#4a2a30", "#dcae78"),
            "muzzle": ("#2a1a1a", "#0a0406", "#46302a"),
            "gum": ("#9a1a2e", "#360614", "#cc3a4a"),
            "brass": ("#d6a03a", "#5a3218", "#ffe08a"),
            "eye_glow": "!#ff3a2a",
            "hat": ("#6a2aa0", "#1e0a36", "#9e5ad8"),
            "hat_band": "!#ff4ad0",
        }),
    },
    "cv_ghost_carousel": {
        "name": "Manège fantôme", "rig": "carousel", "frame": 224, "scale": 1.20, "fps_run": 10,
        "height": 0.78, "length": 0.86, "girth": (0.19, 0.22), "leg": (0.27, 0.27), "hip_x": 0.12,
        "neck_len": 0.34, "head_len": 0.40,
        "mats": {
            "coat": ("pat", [("#d8d0e8", "#5a4a7a", "#ffffff"), ("#c4b8dc", "#4a3a6e", "#eee8ff")], 4.0),
            "fur": ("pat", [("#d8d0e8", "#5a4a7a", "#ffffff"), ("#c4b8dc", "#4a3a6e", "#eee8ff")], 4.0),
            "fur_dark": ("#8a7ea8", "#2a2048", "#b4a8d4"),
            "belly": ("#d8d0e8", "#5a4a7a", "#ffffff"),
            "muzzle": ("#b8aed0", "#3e3260", "#dcd4f0"),
            "mane": ("pat", [("#7a3ab0", "#220a40", "#b070ee"), ("#4a2a7a", "#140a2a", "#7a4ab0")], 7.0),
            "saddle": ("#b01a30", "#3e0418", "#e84050"),
            "gold": ("#e0aa3a", "#6a3a18", "#fff0a0"),
            "crack": ("#3a2a50", "#100820", "#5a4a70"),
            "eye_glow": "!#d070ff",
            "neon": "!#b04aff",
            "neon_red": "!#ff3a5a",
            "gum": ("#6a3a7a", "#200a2a", "#9a5aaa"),
            "brass": ("#e0aa3a", "#6a3a18", "#fff0a0"),
        },
    },
    "cv_penumbra": {
        "name": "Pénombre", "rig": "human", "frame": 192, "scale": 1.08, "head": 1.14, "leg": 0.86,
        "torso": (0.98, 0.92), "arm": 0.86, "arm_len": 1.16, "hunch": 0.34, "fps_run": 16,
        "top_key": "cloak", "sleeve_key": "cloak", "hand_key": "claw_hand",
        "mats": {
            "cloak": ("pat", [("#262234", "#08060e", "#423c58"), ("#1c1828", "#06040a", "#36304a")], 5.0),
            "cloak_in": ("#120c18", "#040206", "#241a2c"),
            "face": ("#06040a", None, None),
            "skin": ("#2a2232", "#0a060e", "#443850"),
            "claw_hand": ("#2a2232", "#0a060e", "#443850"),
            "pants": ("#16121e", "#060408", "#2a2434"),
            "shoe": ("#16121e", "#060408", "#2a2434"),
            "blade": ("#7e8496", "#262a3c", "#d0d6e6"),
            "blade_edge": "!#ff3a4a",
            "eye_glow": "!#ff2a2a",
            "balloon_a": ("#a01022", "#3a0212", "#e0303a"),
            "balloon_b": ("#7a0a1a", "#2a020c", "#b0202e"),
            "string": ("#9890a0", "#3a3444", "#d0c8d8"),
            "wisp": "!#7a3aff",
        },
    },
    "cv_big_plush": {
        "name": "Grosse peluche", "rig": "human", "frame": 256, "scale": 1.46, "head": 1.62, "leg": 0.66,
        "torso": (1.50, 1.36), "arm": 1.62, "arm_len": 0.96, "hunch": 0.12, "belly": 0.9, "fps_run": 10,
        "stride": 0.55, "top_key": "fur", "sleeve_key": "fur", "pants_key": "fur", "hand_key": "fur",
        "shin_key": "fur",
        "mats": dict(RUFF, **{
            "fur": ("pat", [("#b0706c", "#3a1428", "#d8968a"), ("#9a5a5c", "#301024", "#c27c78"),
                            ("#bc7a72", "#421830", "#e2a092")], 9.0),
            "skin": ("pat", [("#b0706c", "#3a1428", "#d8968a"), ("#9a5a5c", "#301024", "#c27c78")], 9.0),
            "cream": ("#ead2b6", "#7a5a6a", "#fff0dc"),
            "nose": ("#2a1418", "#0a0406", "#4a2a2e"),
            "button": ("#1a1418", "#06040a", "#3e343c"),
            "stitch": ("#2a1a26", "#0a0408", "#46303e"),
            "stuffing": ("#f4efe6", "#8a8098", "#ffffff"),
            "shoe": ("pat", [("#b0706c", "#3a1428", "#d8968a"), ("#9a5a5c", "#301024", "#c27c78")], 9.0),
            "eye_glow": "!#ff2030",
            "claw": ("#efe4d0", "#6a5a6a", "#ffffff"),
        }),
    },
    "cv_fairground_being": {
        "name": "L'Être forain", "rig": "human", "frame": 224, "scale": 1.24, "head": 1.02, "leg": 0.92,
        "torso": (1.16, 1.00), "arm": 1.04, "arm_len": 1.12, "hunch": 0.10, "fps_run": 13,
        "top_key": "vest", "sleeve_key": "coat", "shoulder_key": "coat", "hand_key": "glove",
        "mats": {
            "skin": ("#7a8092", "#22243c", "#a6aabc"),
            "coat": ("pat", [("#2c1e36", "#0a0610", "#4a3658"), ("#241830", "#08040c", "#3e2c4c")], 5.0),
            "coat_in": ("#7a0e22", "#2a0210", "#b0203a"),
            "vest": ("#9a1828", "#36061a", "#d03040"),
            "shirt": ("#e6e0d8", "#6a6478", "#ffffff"),
            "gold": ("#e0aa3a", "#6a3a18", "#fff0a0"),
            "hat": ("#1a141e", "#060408", "#34283a"),
            "hat_band": ("#b81a2c", "#40061a", "#ee3a48"),
            "pants": ("pat", [("#2a2230", "#0a080e", "#463a50"), ("#3a2a40", "#0e0a14", "#58465e")], 9.0),
            "shoe": ("#1a141e", "#060408", "#34283a"),
            "glove": ("#e8e2da", "#6a6478", "#ffffff"),
            "cane": ("#2a1a14", "#0a0604", "#4a3226"),
            "eye_glow": "!#ff3a2a",
            "lips": ("#3a0a18", "#120206", "#5a1a2a"),
            "neon": "!#ff4a3a",
        },
    },
    "cv_fire_clown": {
        "name": "Le Clown de feu", "rig": "human", "frame": 224, "scale": 1.18, "head": 1.18, "leg": 0.82,
        "torso": (1.16, 1.04), "arm": 1.10, "arm_len": 1.06, "hunch": 0.14, "belly": 0.3, "fps_run": 12,
        "top_key": "costume", "hand_key": "glove",
        "mats": {
            "face": ("#e8dcd2", "#6a4a5a", "#ffffff"),
            "skin": ("#e8dcd2", "#6a4a5a", "#ffffff"),
            "soot": ("#1e1216", "#080406", "#3a2428"),
            "nose": ("#e0301a", "#5a0a10", "#ff7a3a"),
            "lips": ("#2a0a0e", "#0e0204", "#4a1418"),
            "costume": ("pat", [("#2a1a1e", "#0a0608", "#4a3034"), ("#e0601a", "#5a1a10", "#ff9a3a")], 3.0),
            "pants": ("pat", [("#2a1a1e", "#0a0608", "#4a3034"), ("#3a2026", "#100608", "#5a3a3e")], 6.0),
            "shoe": ("#2a1a1e", "#0a0608", "#4a3034"),
            "glove": ("#2a1a1e", "#0a0608", "#4a3034"),
            "ruff_a": ("#f08a20", "#6a2a10", "#ffc060"),
            "ruff_b": ("#1e1216", "#080406", "#3a2428"),
            "fire": "!#ff6a12",
            "fire_core": "!#ffe060",
            "ember": "!#ff3a10",
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
            "face": ("#efe8e4", "#6a5a78", "#ffffff"),
            "skin": ("#efe8e4", "#6a5a78", "#ffffff"),
            "nose": ("#e01a2a", "#5a0618", "#ff5a5a"),
            "lips": ("#9a0a20", "#340210", "#d02a3a"),
            "makeup": ("#1a1020", "#08040c", "#30203a"),
            "hair": ("pat", [("#e0301c", "#5a0e1a", "#ff6a3a"), ("#b0201a", "#400818", "#e04a2a")], 9.0),
            "robe": ("pat", [("#8e1430", "#300414", "#c42a4a"), ("#6a1040", "#22041a", "#9a2a64")], 4.0),
            "cape_in": ("#3a1060", "#10041e", "#6a2aa0"),
            "ermine": ("#f2eee8", "#7a7090", "#ffffff"),
            "spot": ("#16121a", "#060408", "#2a2430"),
            "gold": ("#e2ac3a", "#6a3a18", "#fff0a0"),
            "jewel": "!#ff2a4a",
            "ruff_a": ("#f2eee8", "#7a7090", "#ffffff"),
            "ruff_b": ("#c8222e", "#4a0820", "#f04a4a"),
            "pants": ("pat", [("#3a1050", "#10041a", "#5e2a80"), ("#2a0c3a", "#0c0414", "#4a2066")], 6.0),
            "shoe": ("#c8222e", "#4a0820", "#f04a4a"),
            "glove": ("#efe8e4", "#6a6078", "#ffffff"),
            "orb": "!#ff2a5a",
            "wheel": "!#ff3050",
            "wheel_b": "!#c060ff",
            "wheel_frame": ("#2a1a30", "#0a060e", "#4a3656"),
            "eye_glow": "!#ffe040",
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
                      keys[k % 2], parent)

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
              inner: str = "fire_core") -> None:
        """Flamme (cône émissif double) ; vacille à chaque pose (after_pose → flicker)."""
        if not hasattr(self, "flames"):
            self.flames = []
        g = joint(name + "J", parent, loc)
        g.rotation_euler = (lean[0], lean[1], 0)
        for key, k in ((outer, 1.0), (inner, 0.55)):
            bm = C.bm_sphere(10, 8, 1.0)
            for v in bm.verts:
                if v.co.z > 0:
                    w = 1.0 - v.co.z
                    v.co.x *= 0.15 + 0.85 * w
                    v.co.y *= 0.15 + 0.85 * w
                    v.co.z *= 2.4
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
    def build_head(self, head) -> None:
        self.skull(head, "face", jaw=0.10)
        self.eyes(head, "eye_glow", r=(0.034, 0.014, 0.028), brow_key="makeup", angle=0.6)
        for sx in (1, -1):
            # maquillage en losange autour des yeux
            self.part("paint", C.bm_xform(C.bm_box(0.075, 0.01, 0.13), loc=(0.066 * sx, -0.163, 0.232),
                      rot=(0, 0.785, 0)), "makeup", head, nofs=True)
        # bouche béante sombre derrière le sourire
        self.part("mouthDark", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.158, 0.115), scale=(0.10, 0.02, 0.04)),
                  "makeup", head, nofs=True)
        for sx in (1, -1):
            # touffes de cheveux rouges sur les côtés (crâne chauve)
            for k, (dy, dz, r) in enumerate(((0.04, 0.24, 0.07), (0.08, 0.17, 0.065), (-0.01, 0.30, 0.055))):
                self.part("hair", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0.175 * sx, dy, dz),
                          scale=(r * 1.2, r, r)), "hair", head)
        self.part("nose", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.19, 0.175), scale=(0.048, 0.044, 0.046)),
                  "nose", head)
        self.grin(head, w=0.115, z=0.10, curve=0.05)

    def build_legs(self, pelvis) -> None:
        super().build_legs(pelvis)
        for side in ("L", "R"):
            self.part("bigShoe" + side, C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, -0.11, self.foot_z + 0.02),
                      scale=(0.11, 0.21, 0.075)), "shoe", self.j["knee" + side])

    def dress(self) -> None:
        sp = self.j["spine"]
        tw, td = self.TW, self.TD
        self.ruff(sp, 0.44, 0.17 * tw, n=14, size=0.068, tilt=0.03)
        for k in range(3):
            self.part("pompom", C.bm_xform(C.bm_sphere(10, 8, 0.035), loc=(0, -0.19 * td - 0.02 * self.BELLY, 0.30 - 0.11 * k)),
                      "pompom", sp)
        self.part("belt", C.bm_xform(C.bm_cyl(18, 0.22 * tw, 0.22 * tw, 0.05), loc=(0, 0, 0.05),
                  scale=(1, 0.76 * td / tw, 1)), "makeup", self.j["pelvis"])
        for side in ("L", "R"):
            self.part("cuff" + side, C.bm_xform(C.bm_torus(14, 6, 0.07 * self.AW, 0.02), loc=(0, 0, -0.16 * self.AL)),
                      "ruff_a", self.j["fa" + side])
        self.balloons(side="L")
        self.muzzle_ref = ("handR", (0, 0, -self.ll))

    def arms_rest(self, b: float = 0.0) -> None:
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.12, -0.12, -0.18 + 0.015 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.06, -0.20, -0.30 + 0.015 * b)), self.R_POLE)

    def arms_run(self, s: float) -> None:
        sh = self.shoulder
        self.arm_ik("L", sh["L"] + Vector((0.12, -0.10, -0.16 + 0.03 * s)), self.L_POLE)
        self.arm_ik("R", sh["R"] + Vector((-0.06, 0.22 * s - 0.06, -0.30 + 0.05 * abs(s))), self.R_POLE)

    def idle_extra(self, t: float) -> None:
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
    def build_head(self, head) -> None:
        self.skull(head, "mask", sx=0.165, sy=0.165, sz=0.185, jaw=0.30)
        for sx in (1, -1):
            self.part("socket", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.062 * sx, -0.150, 0.232),
                      scale=(0.042, 0.02, 0.036)), "makeup", head, nofs=True)
            # larme peinte
            self.part("tear", C.bm_xform(C.bm_box(0.012, 0.01, 0.06), loc=(0.07 * sx, -0.160, 0.175)),
                      "makeup", head, nofs=True)
        self.eyes(head, "eye_glow", z=0.232, x=0.062, y=-0.168, r=(0.022, 0.010, 0.016), brow=False)
        self.grin(head, w=0.075, z=0.12, curve=0.035)
        # chapeau à grelots : trois cornes souples bicolores, grelots dorés
        cap = C.bm_sphere(16, 10, 1.0)
        for v in cap.verts:
            if v.co.z < -0.1:
                v.co.z = -0.1
        self.part("cap", C.bm_xform(cap, loc=(0, 0.01, 0.27), scale=(0.19, 0.19, 0.15)), "suit_a", head)
        for k, (ax, ay, key) in enumerate(((1, 0.0, "suit_a"), (-1, 0.0, "suit_b"), (0, 1, "suit_a"))):
            if ay:
                pts = C.bezier((0, 0.06, 0.36), (0, 0.18, 0.50), (0, 0.34, 0.46), (0, 0.38, 0.30), 7)
            else:
                pts = C.bezier((0.06 * ax, 0, 0.36), (0.20 * ax, -0.02, 0.50), (0.36 * ax, -0.02, 0.44),
                               (0.40 * ax, -0.04, 0.28), 7)
            self.part("horn%d" % k, C.bm_tube(pts, [0.075, 0.07, 0.06, 0.05, 0.035, 0.02, 0.008], seg=8), key, head)
            self.part("bell%d" % k, C.bm_xform(C.bm_sphere(10, 8, 0.04), loc=pts[-1]), "bell", head)

    def build_legs(self, pelvis) -> None:
        super().build_legs(pelvis)
        # arlequin : jambes bicolores croisées
        self.rekey("thighR", "suit_b")
        self.rekey("shinL", "suit_b")

    def dress(self) -> None:
        sp = self.j["spine"]
        tw, td = self.TW, self.TD
        # moitié droite du torse crème, losanges sombres
        half = C.bm_loft([C.ellipse(0, 0, z, r1 * tw + 0.006, r2 * td + 0.006, 20)
                          for z, r1, r2 in ((0.02, 0.188, 0.138), (0.16, 0.203, 0.148), (0.30, 0.234, 0.157), (0.40, 0.222, 0.142))],
                         cap_start=False, cap_end=False)
        for f in list(half.faces):
            if f.calc_center_median().x > 0.0:
                half.faces.remove(f)
        self.part("half", half, "suit_b", sp, thick=0.006)
        for k, (x, z) in enumerate(((0.07, 0.30), (-0.06, 0.20), (0.07, 0.10), (-0.06, 0.36))):
            self.part("diamond", C.bm_xform(C.bm_box(0.06, 0.01, 0.06), loc=(x * tw, -0.165 * td, z), rot=(0, 0.785, 0)),
                      "diamond", sp, nofs=True)
        # collerette à pointes
        for k in range(10):
            a = 2 * math.pi * k / 10
            x, y = math.sin(a) * 0.15 * tw, -math.cos(a) * 0.13 * td
            self.part("collar", C.bm_xform(C.bm_cyl(6, 0.045, 0.0, 0.10), loc=(x * 1.2, y * 1.2, 0.44),
                      rot=(-math.cos(a) * 1.3, -math.sin(a) * 1.3, 0)), "suit_a" if k % 2 else "suit_b", sp)
        # faucille au bout d'un manche (main droite)
        fa = self.j["faR"]
        g = joint("w_sickle", fa, (0, 0, -self.ll))
        self.part("pole", C.bm_xform(C.bm_cyl(8, 0.018, 0.018, 0.62), loc=(0, -0.10, 0), rot=(math.pi / 2, 0, 0)),
                  "pole", g, grp="sickle")
        bl = C.bm_tube(C.bezier((0, -0.40, 0.0), (0, -0.48, 0.16), (0, -0.36, 0.30), (0, -0.20, 0.30), 8),
                       [0.035, 0.04, 0.038, 0.032, 0.025, 0.018, 0.01, 0.0], seg=6, flat=0.25, up=(1, 0, 0))
        self.part("sickle", bl, "blade", g, grp="sickle")
        self.part("bloodTip", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -0.42, 0.20), scale=(0.02, 0.03, 0.05)),
                  "blood", g, nofs=True, grp="sickle")
        self.sickle = g
        self.muzzle_ref = ("sickle", (0, -0.36, 0.30))

    def set_sickle(self, rot) -> None:
        self.sickle.rotation_euler = rot

    def arms_rest(self, b: float = 0.0) -> None:
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.16, -0.10, -0.26 + 0.02 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.12, -0.16, -0.30 + 0.02 * b)), self.R_POLE)
        self.set_sickle((-0.9, 0, 0.4))

    def arms_run(self, s: float) -> None:
        sh = self.shoulder
        for side, sx, k in (("L", 1, -1), ("R", -1, 1)):
            self.arm_ik(side, sh[side] + Vector((0.12 * sx, 0.18 + 0.10 * s * k, -0.26)),
                        self.L_POLE if sx > 0 else self.R_POLE)
        self.set_sickle((-1.6, 0, 0.2))

    def idle_extra(self, t: float) -> None:
        # balancement d'équilibriste sur la pointe des pieds
        self.j["pelvis"].rotation_euler = (0, 0.05 * math.sin(t), 0.06 * math.sin(t))
        self.j["neck"].rotation_euler = (-0.1, 0.12 * math.sin(t + 1), 0.15 * math.sin(t * 0.5))

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
    def build_head(self, head) -> None:
        self.skull(head, "skin")
        self.part("faceShadow", C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, -0.10, 0.19),
                  scale=(0.155, 0.085, 0.165)), "face", head)
        self.eyes(head, "eye_glow", z=0.215, x=0.055, y=-0.184, r=(0.030, 0.012, 0.014), brow=False)
        hood = C.bm_sphere(22, 14, 1.0)
        for v in hood.verts:
            x, y, z = v.co
            if y < 0:
                z += 0.16 * (-y)
            if z > 0.6:
                y += 0.25 * (z - 0.6)
            v.co = Vector((x * 0.235, y * 0.23 + 0.03, z * 0.25 + 0.215))
        for f in list(hood.faces):
            c = f.calc_center_median()
            if c.y < -0.08 and c.z < 0.36 and abs(c.x) < 0.17:
                hood.faces.remove(f)
        for v in list(hood.verts):
            if not v.link_faces:
                hood.verts.remove(v)
        self.part("hood", hood, "cloak", head, thick=0.022)

    def dress(self) -> None:
        sp = self.j["spine"]
        pel = self.j["pelvis"]
        tw, td = self.TW, self.TD
        # mantelet (épaules → taille) et jupe de cape en lambeaux (taille → mollets), ouverte devant
        mant = C.bm_loft([C.ellipse(0, 0.01, z, r1 * tw, r2 * td, 22)
                          for z, r1, r2 in ((0.04, 0.25, 0.20), (0.22, 0.27, 0.21), (0.38, 0.28, 0.20), (0.47, 0.17, 0.15))],
                         cap_start=False, cap_end=False)
        self.part("mantle", mant, "cloak", sp, thick=0.016)
        rnd = random.Random(5)
        secs = []
        for z, r in ((0.06, 0.25), (-0.12, 0.29), (-0.30, 0.33), (-0.48, 0.37)):
            secs.append(C.ellipse(0, 0.02, z, r * tw, r * 0.85 * td, 22))
        skirt = C.bm_loft(secs, cap_start=False, cap_end=False)
        for v in skirt.verts:
            if v.co.z < -0.4:
                a = math.atan2(v.co.y, v.co.x)
                v.co.z += 0.10 * (0.5 + 0.5 * math.sin(7 * a)) + 0.04 * rnd.random()
        for f in list(skirt.faces):
            c = f.calc_center_median()
            if c.y < -0.12 * td and abs(c.x) < 0.10 * tw and c.z < 0.0:
                skirt.faces.remove(f)
        self.part("skirt", skirt, "cloak", pel, thick=0.014)
        # brume violette au ras du sol (sans contour)
        for k in range(6):
            a = 2 * math.pi * k / 6
            self.part("wisp", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.32 * math.sin(a), 0.30 * math.cos(a), -self.PZ + 0.04),
                      scale=(0.07, 0.05, 0.02)), "wisp", pel, nofs=True, grp="wisps")
        # lame courbe (main droite), griffes (main gauche)
        fa = self.j["faR"]
        g = joint("w_blade", fa, (0, 0, -self.ll))
        bl = C.bm_tube(C.bezier((0, 0.02, 0.0), (0, -0.20, 0.02), (0, -0.40, -0.04), (0, -0.52, -0.16), 8),
                       [0.035, 0.05, 0.055, 0.05, 0.042, 0.03, 0.016, 0.0], seg=6, flat=0.22, up=(1, 0, 0))
        self.part("blade", bl, "blade", g, grp="blade")
        self.part("edge", C.bm_tube(C.bezier((0, -0.18, -0.03), (0, -0.34, -0.05), (0, -0.46, -0.10), (0, -0.52, -0.17), 6),
                                    [0.012] * 5 + [0.0], seg=5), "blade_edge", g, nofs=True, grp="blade")
        self.part("hilt", C.bm_xform(C.bm_cyl(8, 0.022, 0.022, 0.10), loc=(0, 0.04, 0), rot=(math.pi / 2, 0, 0)),
                  "cloak_in", g, grp="blade")
        self.blade = g
        for k in range(3):
            x = (k - 1) * 0.03
            self.part("clawL", C.bm_tube([(x, -0.02, -self.ll - 0.03), (x * 1.3, -0.06, -self.ll - 0.11)],
                                         [0.016, 0.0], seg=5), "blade", self.j["faL"])
        self.balloons(side="L", height=0.70)
        self.muzzle_ref = ("blade", (0, -0.52, -0.16))

    def set_blade(self, rot) -> None:
        self.blade.rotation_euler = rot

    def arms_rest(self, b: float = 0.0) -> None:
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.10, -0.12, -0.28 + 0.01 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.10, -0.16, -0.34 + 0.01 * b)), self.R_POLE)
        self.set_blade((-1.1, 0, 0.3))

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
        # œil-bouton (gauche) et œil possédé (droit)
        self.part("button", C.bm_xform(C.bm_cyl(14, 0.034, 0.034, 0.02), loc=(0.07, -0.172, 0.235), rot=(math.pi / 2, 0, 0)),
                  "button", head)
        for dx, dz in ((0.01, 0.01), (-0.01, 0.01), (0.01, -0.01), (-0.01, -0.01)):
            self.part("hole", C.bm_xform(C.bm_sphere(6, 4, 0.006), loc=(0.07 + dx, -0.184, 0.235 + dz)), "stitch", head,
                      nofs=True)
        self.part("eyeR", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(-0.07, -0.170, 0.235), scale=(0.038, 0.016, 0.038)),
                  "eye_glow", head, nofs=True)
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
        self.ruff(sp, 0.47, 0.155 * tw, n=16, size=0.065, tilt=0.02)
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
    def build_head(self, head) -> None:
        self.skull(head, "skin", sx=0.165, sy=0.175, sz=0.195, jaw=0.45)
        self.eyes(head, "eye_glow", z=0.235, x=0.06, y=-0.158, r=(0.028, 0.012, 0.016), brow_key="hat", angle=0.6)
        for sx in (1, -1):
            self.part("cheek", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.10 * sx, -0.12, 0.17), scale=(0.035, 0.03, 0.05)),
                      "hat", head, nofs=True)
        self.grin(head, key="lips", w=0.085, z=0.115, teeth="tooth", curve=0.045)
        self.part("nose", C.bm_xform(C.bm_cyl(8, 0.025, 0.0, 0.07), loc=(0, -0.19, 0.19), rot=(1.35, 0, 0)), "skin", head)
        # haut-de-forme incliné, ruban rouge, plume de néon
        g = joint("hat", head, (0.02, 0.0, 0.34))
        g.rotation_euler = (-0.12, 0.18, 0)
        self.part("brim", C.bm_xform(C.bm_cyl(24, 0.27, 0.27, 0.025), loc=(0, 0, 0.0)), "hat", g)
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
        tails = C.bm_loft([C.ellipse(0, 0.02, z, r * tw, r * 0.85 * td, 22)
                           for z, r in ((0.08, 0.235), (-0.16, 0.27), (-0.42, 0.30))], cap_start=False, cap_end=False)
        for f in list(tails.faces):
            c = f.calc_center_median()
            if c.y < -0.06 * td or (c.y > 0.0 and abs(c.x) < 0.03 and c.z < -0.12):
                tails.faces.remove(f)
        self.part("tails", tails, "coat", pel, thick=0.014)
        for sx in (1, -1):
            # revers rouges
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
    def build_head(self, head) -> None:
        self.skull(head, "face", jaw=0.12)
        self.eyes(head, "eye_glow", r=(0.03, 0.012, 0.024), brow_key="soot", angle=0.6)
        for sx in (1, -1):
            self.part("soot", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.066 * sx, -0.158, 0.225),
                      scale=(0.05, 0.02, 0.06)), "soot", head, nofs=True)
        self.part("nose", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.19, 0.175), scale=(0.05, 0.045, 0.048)),
                  "nose", head)
        self.grin(head, key="lips", w=0.12, z=0.10, curve=0.05)
        # chevelure de flammes
        for k, (x, y, z, s, lx) in enumerate(((0.0, 0.02, 0.36, 0.11, 0.0), (0.12, 0.0, 0.30, 0.09, -0.4),
                                              (-0.12, 0.0, 0.30, 0.09, 0.4), (0.07, 0.10, 0.33, 0.08, -0.2),
                                              (-0.07, 0.10, 0.33, 0.08, 0.2), (0.17, 0.05, 0.22, 0.07, -0.7),
                                              (-0.17, 0.05, 0.22, 0.07, 0.7))):
            self.flame(head, (x, y, z), s, name="hairFire%d" % k, lean=(0.25, lx))

    def dress(self) -> None:
        sp = self.j["spine"]
        tw, td = self.TW, self.TD
        self.ruff(sp, 0.44, 0.17 * tw, n=14, size=0.07, tilt=0.03)
        for k in range(3):
            self.part("ember", C.bm_xform(C.bm_sphere(8, 6, 0.03), loc=(0, -0.19 * td - 0.02, 0.30 - 0.1 * k)), "ember", sp,
                      nofs=True)
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
        self.part("fireball", C.bm_xform(C.bm_sphere(14, 10, 0.09), loc=(0, -0.04, -self.ll - 0.06)), "fire", fa,
                  nofs=True, grp="fireball")
        self.part("fireballCore", C.bm_xform(C.bm_sphere(12, 8, 0.055), loc=(0, -0.06, -self.ll - 0.06)), "fire_core", fa,
                  nofs=True, grp="fireball")
        self.muzzle_ref = ("fireball", (0, -0.04, -self.ll - 0.06))

    def arms_rest(self, b: float = 0.0) -> None:
        s = self.shoulder
        self.arm_ik("L", s["L"] + Vector((0.14, -0.14, -0.24 + 0.02 * b)), self.L_POLE)
        self.arm_ik("R", s["R"] + Vector((-0.14, -0.14, -0.24 + 0.02 * b)), self.R_POLE)

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
        ball = anim == "attack" and i <= 3
        self.show("fireball", ball)
        if anim == "death" and i >= n - 2:
            for ob, _k in self.flames:
                ob.scale = (0.5, 0.5, 0.35)


# ------------------------------------------------------------------------------- le Roi du cirque (boss)
class CircusKing(CvHuman):
    def build_head(self, head) -> None:
        self.skull(head, "face", jaw=0.18)
        self.eyes(head, "eye_glow", r=(0.028, 0.012, 0.022), brow_key="makeup", angle=0.6)
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
        self.ruff(sp, 0.45, 0.17 * tw, n=18, size=0.075, tilt=0.03)
        # longue robe (taille → chevilles)
        rob = C.bm_loft([C.ellipse(0, 0.0, z, r * tw, r * 0.85 * td, 22)
                         for z, r in ((0.08, 0.24), (-0.20, 0.28), (-0.50, 0.33), (-0.68, 0.35))], cap_start=False, cap_end=True)
        self.part("robeSkirt", rob, "robe", pel, thick=0.016)
        self.part("hem", C.bm_xform(C.bm_torus(24, 6, 0.345 * tw, 0.03), loc=(0, 0, -0.67), scale=(1, 0.85 * td / tw, 1)),
                  "gold", pel)
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
        self.part("orb", C.bm_xform(C.bm_sphere(14, 10, 0.085), loc=(0, 0, 0.62)), "orb", sg, nofs=True, grp="scepter")
        self.part("orbCage", C.bm_xform(C.bm_torus(16, 6, 0.09, 0.012), loc=(0, 0, 0.62), rot=(math.pi / 2, 0, 0)), "gold", sg,
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
    def build_head(self, hd, jw) -> None:
        S = self.S
        hl = S["head_len"]
        sk = C.bm_sphere(16, 12, 1.0)
        for v in sk.verts:
            x, y, z = v.co
            v.co = Vector((x * 0.155, y * 0.15, z * 0.13 + 0.02))
        self.part("skull", sk, "fur", hd)
        self.part("snout", C.bm_tube([(0, -0.06, 0.0), (0, -hl * 0.55, -0.01), (0, -hl * 0.78, -0.02)], [0.10, 0.085, 0.065],
                                     seg=12, flat=0.85), "muzzle", hd)
        self.part("nose", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, -hl * 0.80, 0.0), scale=(0.035, 0.025, 0.028)),
                  "fur_dark", hd)
        self.part("gumU", C.bm_xform(C.bm_box(0.10, hl * 0.6, 0.03, bevel=0.012), loc=(0, -hl * 0.48, -0.05)), "gum", hd)
        for sx in (1, -1):
            self.part("fangU", C.bm_xform(C.bm_cyl(6, 0.014, 0.0, 0.06), loc=(0.035 * sx, -hl * 0.68, -0.085),
                      rot=(math.pi, 0, 0)), "tooth", hd)
            self.part("eye", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.06 * sx, -0.10, 0.06), scale=(0.026, 0.014, 0.018)),
                      "eye_glow", hd, nofs=True)
            self.part("brow", C.bm_xform(C.bm_box(0.06, 0.03, 0.02), loc=(0.06 * sx, -0.10, 0.085), rot=(0, -0.45 * sx, 0)),
                      "fur_dark", hd)
            ear = C.bm_cyl(4, 0.05, 0.0, 0.13)
            self.part("ear", C.bm_xform(ear, loc=(0.075 * sx, 0.02, 0.14), rot=(-0.3, 0.35 * sx, 0), scale=(1, 0.5, 1)),
                      "fur_dark", hd)
        # mâchoire inférieure
        self.part("jawM", C.bm_tube([(0, 0.0, -0.02), (0, -hl * 0.45, -0.03), (0, -hl * 0.66, -0.02)], [0.06, 0.05, 0.035],
                                    seg=10, flat=0.6), "muzzle", jw)
        self.part("gumL", C.bm_xform(C.bm_box(0.08, hl * 0.5, 0.02, bevel=0.008), loc=(0, -hl * 0.38, 0.01)), "gum", jw)
        for sx in (1, -1):
            self.part("fangL", C.bm_xform(C.bm_cyl(6, 0.012, 0.0, 0.05), loc=(0.03 * sx, -hl * 0.58, 0.03)), "tooth", jw)
        # petit chapeau de cirque incliné
        hat = joint("hat", hd, (0.04, 0.02, 0.13))
        hat.rotation_euler = (-0.2, 0.35, 0)
        self.part("hatCone", C.bm_xform(C.bm_cyl(14, 0.06, 0.0, 0.14), loc=(0, 0, 0.07)), "hat", hat)
        self.part("hatBand", C.bm_xform(C.bm_torus(14, 6, 0.055, 0.012), loc=(0, 0, 0.015)), "hat_band", hat, nofs=True)
        self.part("hatPom", C.bm_xform(C.bm_sphere(8, 6, 0.025), loc=(0, 0, 0.145)), "ruff_a", hat)
        self.muzzle_ref = ("fangU", (0.0, -hl * 0.78, -0.05))

    def build_torso(self, to) -> None:
        super().build_torso(to)
        # crinière hérissée et épines le long du dos
        for k in range(7):
            y = -self.L * 0.36 + self.L * 0.11 * k
            h = 0.12 - 0.012 * k
            self.part("spine", C.bm_xform(C.bm_cyl(5, 0.035, 0.0, h), loc=(0, y, self.RZ * 0.92 + h * 0.4),
                      rot=(0.45, 0, 0)), "fur_dark", to)
        for sx in (1, -1):
            for k in range(3):
                self.part("mane", C.bm_xform(C.bm_cyl(5, 0.04, 0.0, 0.12), loc=(sx * self.RX * 0.75, -self.L * 0.34 + 0.07 * k,
                          self.RZ * 0.5), rot=(0.6, 0.9 * sx, 0)), "fur_dark", to)
        # harnais doré
        self.part("harness", C.bm_xform(C.bm_torus(18, 6, 1.0, 0.06), loc=(0, -self.L * 0.18, 0), rot=(math.pi / 2, 0, 0),
                  scale=(self.RX * 1.02, self.RZ * 1.02, 1)), "brass", to)

    def build_neck(self, to, nk) -> None:
        super().build_neck(to, nk)
        hd = self.j["head"].location
        # collerette de clown autour du cou
        for k in range(12):
            a = 2 * math.pi * k / 12
            c = Vector((0, hd.y * 0.35, hd.z * 0.35))
            off = Vector((math.cos(a) * self.RZ * 0.85, math.sin(a) * 0.05, math.sin(a) * self.RZ * 0.85))
            self.part("ruff%d" % k, C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=c + off, rot=(0.6, 0, a),
                      scale=(0.045, 0.03, 0.045)), "ruff_a" if k % 2 else "ruff_b", nk)

    def build_tail(self, tl) -> None:
        self.part("tailM", C.bm_tube(C.bezier((0, 0, 0), (0, 0.12, 0.10), (0, 0.24, 0.12), (0, 0.34, 0.06), 7),
                                     [0.045, 0.04, 0.035, 0.03, 0.025, 0.018, 0.0], seg=8), "fur_dark", tl)


class GhostCarousel(Quad):
    """Cheval de manège hanté : glisse sur sa barre dorée (pied lumineux), pattes figées en galop
    de manège ; se cabre puis s'abat (piétinement de zone)."""

    POLE_TOP = 1.95

    def build_head(self, hd, jw) -> None:
        hl = self.S["head_len"]
        sk = C.bm_sphere(16, 12, 1.0)
        for v in sk.verts:
            x, y, z = v.co
            v.co = Vector((x * 0.11, y * 0.13, z * 0.12 + 0.03))
        self.part("skull", sk, "coat", hd)
        self.part("snout", C.bm_tube([(0, -0.06, 0.02), (0, -hl * 0.5, -0.03), (0, -hl * 0.72, -0.07)], [0.10, 0.085, 0.07],
                                     seg=12, flat=0.8), "coat", hd)
        self.part("nostril", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -hl * 0.74, -0.06), scale=(0.06, 0.03, 0.04)),
                  "muzzle", hd)
        for sx in (1, -1):
            self.part("eye", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.085 * sx, -0.10, 0.07), scale=(0.024, 0.016, 0.022)),
                      "eye_glow", hd, nofs=True)
            self.part("ear", C.bm_xform(C.bm_cyl(5, 0.035, 0.0, 0.11), loc=(0.05 * sx, 0.04, 0.16), rot=(-0.2, 0.2 * sx, 0)),
                      "coat", hd)
            # bride dorée
            self.part("bridle", C.bm_xform(C.bm_torus(14, 5, 0.075, 0.012), loc=(0, -hl * 0.45, -0.02), rot=(math.pi / 2, 0, 0),
                      scale=(1.15, 1, 0.95)), "gold", hd)
        self.part("jawM", C.bm_tube([(0, -0.02, -0.03), (0, -hl * 0.45, -0.05), (0, -hl * 0.6, -0.04)], [0.06, 0.05, 0.035],
                                    seg=8, flat=0.7), "coat", jw)
        self.part("gum", C.bm_xform(C.bm_box(0.07, hl * 0.4, 0.02), loc=(0, -hl * 0.38, -0.01)), "gum", jw)
        # fissures (bois peint craquelé)
        self.part("crack", C.bm_tube([(0.10, -0.04, 0.10), (0.09, -0.12, 0.04), (0.10, -0.18, 0.05)], [0.008] * 3, seg=4),
                  "crack", hd, nofs=True)
        self.muzzle_ref = ("snout", (0, -hl * 0.72, -0.07))

    def build_torso(self, to) -> None:
        super().build_torso(to)
        L, RX, RZ = self.L, self.RX, self.RZ
        # selle rouge à franges d'or, tapis
        self.part("saddle", C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, 0.02, RZ * 0.80), scale=(RX * 0.95, 0.20, 0.07)),
                  "saddle", to)
        self.part("blanket", C.bm_xform(C.bm_box(RX * 2.15, 0.36, 0.20, bevel=0.03), loc=(0, 0.02, RZ * 0.35)), "saddle", to)
        self.part("trim", C.bm_xform(C.bm_box(RX * 2.2, 0.38, 0.03), loc=(0, 0.02, RZ * 0.25)), "gold", to)
        # rubans dorés et motifs peints sur le poitrail
        self.part("breast", C.bm_xform(C.bm_torus(20, 5, 1.0, 0.03), loc=(0, -L * 0.30, 0.0), rot=(math.pi / 2, 0, 0),
                  scale=(RX * 1.03, RZ * 1.03, 1)), "gold", to)
        for k in range(3):
            self.part("jewel", C.bm_xform(C.bm_sphere(8, 6, 0.025), loc=(0, -L * 0.42 - 0.01, RZ * (0.3 - 0.3 * k))), "neon_red",
                      to, nofs=True)
        # crinière ondulée (violette)
        for k in range(8):
            u = k / 7
            y = -L * 0.40 - 0.24 * u
            z = RZ * 0.9 + 0.30 * u
            self.part("mane%d" % k, C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.03 * (-1) ** k, y + 0.02, z + 0.03),
                      scale=(0.05, 0.08, 0.06), rot=(0.4, 0.3 * (-1) ** k, 0)), "mane", to)
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
        self.part("base", C.bm_xform(C.bm_cyl(24, 0.30, 0.34, 0.06), loc=(0, 0, 0.03)), "gold", g)
        self.part("baseNeon", C.bm_xform(C.bm_torus(28, 6, 0.36, 0.02), loc=(0, 0, 0.04)), "neon", g, nofs=True)
        for k in range(6):
            a = 2 * math.pi * k / 6
            self.part("ghost", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.40 * math.cos(a), 0.40 * math.sin(a), 0.03),
                      scale=(0.07, 0.07, 0.02)), "neon", g, nofs=True, grp="ghost")

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
        to.rotation_euler = (0.06 * math.sin(t + 0.8), 0, 0)
        self.j["neck"].rotation_euler = (-0.1 + 0.06 * math.sin(t), 0, 0.08 * math.sin(t * 0.5))
        self.j["jaw"].rotation_euler = (0.10 + 0.12 * max(0.0, math.sin(t)), 0, 0)
        self.j["tail"].rotation_euler = (0.1, 0, 0.15 * math.sin(t))
        self.carousel_legs(0.2 * math.sin(t))

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


def main() -> None:
    args = sys.argv[1:]
    kinds = args[args.index("--kinds") + 1].split(",") if "--kinds" in args else KINDS
    os.makedirs(M.TMP_DIR, exist_ok=True)
    if "--sheet" in args:
        presentation_sheet(kinds)
        return
    if "--repack" in args:
        for k in kinds:
            M.repack(k)
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
