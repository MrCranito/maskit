"""Bestiaire de la Station spatiale (« Les machines de l'espace ») : modélisation 3D scriptée,
rigs, animations et planches 8 directions, même pipeline que les hors-la-loi du Far West
(art/blender/build_enemies.py : caméra orthographique 3/4 à 48°, matériaux toon peints, contour
Freestyle, même densité de pixels et même échelle monde que le héros).

Usage (depuis la racine du projet ; rendu Blender TOUJOURS sous le verrou commun) :
    flock /home/claude/.blender_render.lock python3 art/blender/bestiary/space_station/build_ss_enemies.py
    ... --kinds ss_spectre,ss_detector                      # quelques kinds
    ... --preview s,se --anim idle:0,attack:3,death:7 [--kinds ss_alien]
    ... --repack [--kinds ...]                              # atlas + SpriteFrames depuis les images rendues
    ... --sheet                                             # planche de présentation (captures)

Bestiaire classique (planche docs/reference/bestiaire_classique.png, colonne STATION SPATIALE) :
    ss_security_droid   Droïde de sécurité : humanoïde blindé, œil rouge, fusil (rafales)
    ss_spectre          Spectre : drone sphérique volant à pattes pendantes, œil bleu (projectiles)
    ss_teleporter       Téléporteur : humanoïde maigre au cœur bleu lumineux, griffes
    ss_detector         Détecteur : araignée mécanique à gros œil rouge (alerte les autres)
    ss_station_guardian Gardien de station : gros robot lourd, yeux bleus, canons d'avant-bras
    ss_alien            Alien : créature violette à tentacules (invoque des petits)
    ss_alien_brood      petit alien invoqué (même modèle, gabarit réduit)
Élites et boss (planche bestiaire_elites_boss.png) :
    ss_drone_tieur      Le Drone Tieur : drone d'élite araignée à œil rouge, canons, vol stationnaire
    ss_atlas            Le Sécurité Atlas : robot de défense lourd, bouclier frontal, fusil lourd
    ss_architect        L'Architecte (boss) : énorme robot à œil rouge central, bras canons

Animations (8 directions) : idle, run, attack, hit, death.
attack : images 0-2 = élan (l'image 2 est tenue pendant le télégraphe), 3 = coup / tir, 4-5 = retour.
death : la dernière image = carcasse au sol (réutilisée par le jeu), lumières éteintes.

Sortie : assets/sprites/enemies/<kind>/<kind>_atlas.png, <kind>_frames.tres, <kind>_meta.json.
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "..")))
import rdm_common as C  # noqa: E402
import build_enemies as BE  # noqa: E402  (pack, SpriteFrames, import VRAM : pipeline commun)
import bpy  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

ROOT = BE.ROOT
OUT_DIR = BE.OUT_DIR
TMP_DIR = os.path.join(os.environ.get("RDM_TMP", "/tmp/rdm_enemy_frames"), "ss")
DIRS = BE.DIRS
ANIMS = dict(BE.ANIMS_BASE)
ELEV = BE.ELEV
DOWN = Vector((0, 0, -1))

# ----------------------------------------------------------------------------- matériaux
# (base, ombre, lumière) en hex ; "!#hex" = émissif (lumières, yeux) ; ("pat", [...], échelle) = usure.
SS_MATS = {
    "armor": ("pat", [("#283042", "#05070d", "#7484a4"), ("#222937", "#04060b", "#647492")], 7.0),
    "plate": ("#46516a", "#0b0f1a", "#a6b4d0"),
    "light": ("#b6c1d4", "#2a3248", "#f4f7fc"),
    "dark": ("#22252e", "#08090e", "#3e4250"),
    "joint": ("#15171d", "#050508", "#2e3139"),
    "metal": ("#8a8e98", "#2c2e3a", "#d8dae0"),
    "gun": ("#2a2d36", "#0a0b10", "#545866"),
    "hazard": ("#d89a2a", "#5a3a28", "#ffd060"),
    "eye_rim": ("#3a0c0c", "#120406", "#6a1a16"),
    "red": "!#ff3a22",
    "blue": "!#4ad4ff",
    "violet": "!#d070ff",
    "pink": "!#ffa8f6",
    "red_hot": "!#ffd8cc",
    "blue_hot": "!#eafcff",
    "pink_hot": "!#fff0fc",
    "off": ("#1c1e26", "#06070a", "#2c2f38"),
    "skin": ("pat", [("#6a3a8c", "#1e0e30", "#a466c8"), ("#5a2e7a", "#180a28", "#8e52b4")], 5.0),
    "skin_light": ("#b07ad0", "#40205a", "#e2b4f4"),
    "skin_dark": ("#34184a", "#100618", "#5a2e78"),
    "claw": ("#e8dcf0", "#5a4a70", "#ffffff"),
}
GLOW_KEYS = ("red", "blue", "violet", "pink", "red_hot", "blue_hot", "pink_hot")
HOT = {"red": "red_hot", "blue": "blue_hot", "violet": "pink_hot", "pink": "pink_hot"}
EMIT = 1.8


def J(name: str, parent, loc=(0, 0, 0), quat: bool = False) -> bpy.types.Object:
    e = C.empty(name, loc, parent)
    e.rotation_mode = "QUATERNION" if quat else "XYZ"
    return e


def smooth01(u: float) -> float:
    u = min(1.0, max(0.0, u))
    return u * u * (3 - 2 * u)


class Creature:
    """Base commune : pièces (mesh + clef de matériau), groupes affichables, IK à deux segments."""

    def __init__(self, kind: str, spec: dict) -> None:
        self.kind = kind
        self.S = spec
        self.dir_ang = 0.0
        self.j: dict[str, bpy.types.Object] = {}
        self.parts: list[tuple[bpy.types.Object, str]] = []
        self.grp: dict[str, list[bpy.types.Object]] = {}
        self.weapons: dict[str, bpy.types.Object] = {}
        self.ph = C.toon("_ph_" + kind, "#ff00ff")
        self.build()
        self.apply_mats()

    # ------------------------------------------------------------------ outils
    def part(self, name, bm, key, parent, smooth=True, grp=None, nofs=False, thick=0.0):
        """Pièce. Une clef lumineuse (red/blue/violet) crée aussi son double éteint (mort)."""
        glow = key in GLOW_KEYS
        if glow and key in HOT and (name.startswith("eye") or name == "core"):
            # point chaud quasi blanc au centre de la lueur (lisible sur mobile)
            hot = bm.copy()
            vs = [v.co.copy() for v in hot.verts]
            c = sum(vs, Vector()) / max(len(vs), 1)
            dy = (max(v.y for v in vs) - min(v.y for v in vs)) * 0.35
            for v in hot.verts:
                v.co = c + (v.co - c) * 0.5 - Vector((0, dy, 0))
            self.part(name + "Hot", hot, HOT[key], parent, smooth=smooth)
        if glow:
            twin = bm.copy()
        ob = C.mesh_obj(name, bm, self.ph, smooth=smooth, coll=C.nofs_collection() if (nofs or glow) else None)
        ob.parent = parent
        if thick > 0.0:
            C.solidify(ob, thick, 0.0)
        self.parts.append((ob, key))
        if grp:
            self.grp.setdefault(grp, []).append(ob)
        if glow:
            self.grp.setdefault("glow_on", []).append(ob)
            off = C.mesh_obj(name + "_off", twin, self.ph, smooth=smooth)
            off.parent = parent
            self.parts.append((off, "off"))
            self.grp.setdefault("glow_off", []).append(off)
        return ob

    def show(self, grp: str, on: bool) -> None:
        for ob in self.grp.get(grp, []):
            ob.hide_render = not on
            ob.hide_viewport = not on

    def lights(self, on: bool) -> None:
        self.show("glow_on", on)
        self.show("glow_off", not on)

    def apply_mats(self) -> None:
        spec = dict(SS_MATS)
        spec.update(self.S.get("mats", {}))
        mats = {}
        for key, sp in spec.items():
            name = "%s_%s" % (self.kind, key)
            if isinstance(sp, str) and sp.startswith("!"):
                mats[key] = C.toon(name, sp[1:], emit=EMIT)
            elif sp[0] == "pat":
                mats[key] = C.toon_pattern(name, sp[1], scale=sp[2], thresholds=(0.55,), rim=0.22)
            else:
                mats[key] = C.toon(name, sp[0], sp[1], sp[2], rim=0.32)
        for ob, key in self.parts:
            ob.data.materials[0] = mats.get(key, mats["armor"])

    def ik(self, up, lo, target, pole, L1: float, L2: float) -> Vector:
        """Deux segments (modélisés le long de -Z) : `up` et `lo` ont le même parent ; `target` et
        `pole` dans le repère de ce parent. Renvoie la position atteinte."""
        S = Vector(up.location)
        d = Vector(target) - S
        dist = min(max(d.length, 1e-3), (L1 + L2) * 0.995)
        u = d.normalized()
        a = (L1 * L1 + dist * dist - L2 * L2) / (2 * dist)
        h = math.sqrt(max(L1 * L1 - a * a, 0.0))
        p = Vector(pole)
        p = p - u * p.dot(u)
        p = p.normalized() if p.length > 1e-5 else Vector((0, 1, 0))
        E = S + u * a + p * h
        H = S + u * dist
        up.rotation_quaternion = DOWN.rotation_difference((E - S).normalized())
        lo.location = E
        lo.rotation_quaternion = DOWN.rotation_difference((H - E).normalized())
        return H

    def place(self, wname: str, loc, rot) -> None:
        g = self.weapons.get(wname)
        if g is not None:
            g.location = loc
            g.rotation_euler = rot

    def wpt(self, wname: str, local) -> Vector:
        g = self.weapons[wname]
        return Vector(g.location) + Euler(g.rotation_euler, "XYZ").to_matrix() @ Vector(local)

    def pose(self, anim: str, i: int, n: int) -> None:
        self.lit = True
        getattr(self, "pose_" + anim)(i, n)
        self.post_pose(anim, i, n)
        self.lights(self.lit)

    def post_pose(self, anim: str, i: int, n: int) -> None:
        pass

    def chain(self, name, parent, base, n, seg, r0, r1, key, ring="skin_light") -> list:
        """Chaîne de segments (tentacule) modélisés le long de -Z, chacun enfant du précédent."""
        out = []
        prev = parent
        for i in range(n):
            e = J("%s_%d" % (name, i), prev, base if i == 0 else (0, 0, -seg))
            ra = r0 + (r1 - r0) * i / n
            rb = r0 + (r1 - r0) * (i + 1) / n
            self.part("%s_s%d" % (name, i), C.bm_xform(C.bm_cyl(10, ra, rb, seg * 1.05), loc=(0, 0, -seg / 2)), key, e)
            if i % 2 == 1 and ring:
                self.part("%s_r%d" % (name, i), C.bm_xform(C.bm_torus(10, 4, ra, ra * 0.25)), ring, e)
            out.append(e)
            prev = e
        return out

    def corpse_fall(self, t: float, back: float = 0.72, lift: float = 0.16) -> float:
        """Bascule du corps entier (comme les hors-la-loi) : chute sur le dos avec vrille pour un
        cadavre couché en travers de l'écran. Renvoie l'avancement de la chute (0..1)."""
        if t < 0.25:
            fall = 0.08 * (t / 0.25)
        else:
            u = min(1.0, (t - 0.25) / 0.55)
            e = smooth01(u)
            bounce = 0.0
            if t > 0.8:
                v = (t - 0.8) / 0.2
                bounce = 0.06 * math.sin(v * math.pi) * (1 - v)
            fall = 0.08 + (math.pi / 2 - 0.08) * e - bounce
        k = fall / (math.pi / 2)
        tau = BE.corpse_twist(self.dir_ang) * min(1.0, k * 1.2)
        body = self.j["body"]
        body.rotation_euler = (-fall, 0, tau)
        sc = self.S.get("scale", 1.0)
        body.location = Euler((0, 0, tau)).to_matrix() @ Vector((0, -back * sc * k, lift * sc * k * k))
        return k


# ============================================================================= humanoïdes
class Mech(Creature):
    """Robot / humanoïde : jambes et bras en IK, torse blindé, tête selon le type."""

    def build(self) -> None:
        S = self.S
        j = self.j
        j["root"] = root = J("root", None)
        j["body"] = body = J("body", root)
        body.scale = (S["scale"],) * 3
        self.L1, self.L2 = S["leg"]
        self.HW = S["hip_w"]
        self.PZ = (self.L1 + self.L2) * 0.93 + S.get("foot_h", 0.07)
        j["pelvis"] = pelvis = J("pelvis", body, (0, 0, self.PZ))
        j["spine"] = spine = J("spine", pelvis, (0, 0, 0.08))
        j["neck"] = neck = J("neck", spine, (0, -S.get("neck_fwd", 0.0), S["torso"][2] + S.get("neck_up", 0.0)))
        j["head"] = head = J("head", neck)
        head.scale = (S.get("head_scale", 1.0),) * 3
        self.build_legs(body)
        self.build_pelvis(pelvis)
        self.build_torso(spine)
        self.build_arms(spine)
        getattr(self, "head_" + S["head"])(head)
        self.build_weapon(spine)

    # --- jambes ------------------------------------------------------------
    def build_legs(self, body) -> None:
        S, j = self.S, self.j
        lr = S.get("limb_r", 1.0)
        for side, sx in (("L", 1), ("R", -1)):
            th = j["th" + side] = J("th" + side, body, quat=True)
            sh = j["sh" + side] = J("sh" + side, body, quat=True)
            ft = j["ft" + side] = J("ft" + side, body)
            L1, L2 = self.L1, self.L2
            if S.get("organic"):
                self.part("thigh" + side, C.bm_xform(C.bm_cyl(12, 0.13 * lr, 0.085 * lr, L1 * 1.05), loc=(0, 0, -L1 / 2)),
                          "armor", th)
                self.part("knee" + side, C.bm_sphere(10, 7, 0.085 * lr), "plate", sh)
                self.part("shin" + side, C.bm_xform(C.bm_cyl(12, 0.08 * lr, 0.055 * lr, L2), loc=(0, 0, -L2 / 2)),
                          "plate", sh)
                self.part("spur" + side, C.bm_xform(C.bm_cyl(6, 0.03 * lr, 0.0, 0.16), loc=(0, 0.06, -0.02),
                          rot=(-2.4, 0, 0)), "claw", sh)
                self.part("foot" + side, C.bm_xform(C.bm_sphere(10, 7, 1.0), loc=(0, -0.04, 0.04),
                          scale=(0.09 * lr, 0.13 * lr, 0.05)), "plate", ft)
                for k in (-1, 0, 1):
                    self.part("toe" + side, C.bm_xform(C.bm_cyl(6, 0.025, 0.0, 0.13), loc=(0.045 * k, -0.17, 0.03),
                              rot=(math.pi / 2 + 0.2, 0.25 * k, 0)), "claw", ft)
                continue
            if S.get("thin"):
                self.part("thigh" + side, C.bm_xform(C.bm_cyl(10, 0.055 * lr, 0.045 * lr, L1), loc=(0, 0, -L1 / 2)),
                          "plate", th)
                self.part("thighPlate" + side, C.bm_xform(C.bm_box(0.07 * lr, 0.04, L1 * 0.6, bevel=0.012),
                          loc=(0, -0.045 * lr, -L1 * 0.45)), "armor", th)
                self.part("shin" + side, C.bm_xform(C.bm_cyl(10, 0.045 * lr, 0.035 * lr, L2), loc=(0, 0, -L2 / 2)),
                          "plate", sh)
                self.part("shinLight" + side, C.bm_xform(C.bm_box(0.02, 0.01, L2 * 0.45), loc=(0, -0.04 * lr, -L2 * 0.4)),
                          "blue", sh)
                self.part("knee" + side, C.bm_sphere(10, 7, 0.06 * lr), "joint", sh)
                foot = C.bm_xform(C.bm_box(0.08, 0.20, 0.05, bevel=0.015), loc=(0, -0.05, 0.025))
                self.part("foot" + side, foot, "dark", ft)
                for k in (-1, 0, 1):
                    self.part("toe" + side, C.bm_xform(C.bm_cyl(6, 0.018, 0.0, 0.09), loc=(0.03 * k, -0.18, 0.02),
                              rot=(math.pi / 2, 0, 0)), "light", ft)
                continue
            self.part("hipJ" + side, C.bm_sphere(10, 7, 0.085 * lr), "joint", th)
            thigh = C.bm_xform(C.bm_box(0.15 * lr, 0.17 * lr, L1 * 0.86, bevel=0.035), loc=(0, 0, -L1 * 0.48))
            self.part("thigh" + side, thigh, "armor", th)
            self.part("thighPlate" + side, C.bm_xform(C.bm_box(0.12 * lr, 0.05, L1 * 0.55, bevel=0.02),
                      loc=(0, -0.085 * lr, -L1 * 0.45)), "plate", th)
            self.part("knee" + side, C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.03, 0.0),
                      scale=(0.10 * lr, 0.10 * lr, 0.09 * lr)), "light", sh)
            shin = C.bm_cyl(10, 0.085 * lr, 0.10 * lr, L2 * 0.9)
            C.bm_xform(shin, loc=(0, 0, -L2 * 0.5), scale=(1, 1.15, 1))
            self.part("shin" + side, shin, "armor", sh)
            self.part("shinLight" + side, C.bm_xform(C.bm_box(0.03, 0.012, L2 * 0.4), loc=(0, -0.105 * lr, -L2 * 0.45)),
                      S.get("accent", "red"), sh)
            fw = 0.13 * lr
            foot = C.bm_box(fw, 0.27 * lr, 0.09, bevel=0.03)
            for v in foot.verts:
                if v.co.y < 0 and v.co.z > 0:
                    v.co.z -= 0.03
            C.bm_xform(foot, loc=(0, -0.05 * lr, 0.045))
            self.part("foot" + side, foot, "dark", ft)
            self.part("ankle" + side, C.bm_xform(C.bm_cyl(10, 0.07 * lr, 0.07 * lr, 0.06), loc=(0, 0.0, 0.10)),
                      "joint", ft)

    def build_pelvis(self, pelvis) -> None:
        S = self.S
        tw, td, _th = S["torso"]
        if S.get("organic"):
            self.part("pelvis", C.bm_xform(C.bm_sphere(14, 9, 1.0), loc=(0, 0.02, 0.03),
                      scale=(0.20 * tw, 0.16 * td, 0.15)), "armor", pelvis)
            return
        if S.get("thin"):
            self.part("pelvis", C.bm_xform(C.bm_sphere(12, 8, 1.0), scale=(0.13 * tw, 0.09 * td, 0.08)), "plate", pelvis)
            for k in range(4):
                self.part("vert", C.bm_xform(C.bm_cyl(8, 0.035, 0.035, 0.035), loc=(0, 0.01, 0.06 + 0.05 * k)),
                          "joint", pelvis)
            return
        self.part("pelvis", C.bm_xform(C.bm_box(0.36 * tw, 0.24 * td, 0.16, bevel=0.04), loc=(0, 0, 0.0)), "armor", pelvis)
        self.part("waist", C.bm_xform(C.bm_cyl(14, 0.13 * tw, 0.12 * tw, 0.14), loc=(0, 0, 0.12)), "joint", pelvis)
        self.part("codpiece", C.bm_xform(C.bm_box(0.14 * tw, 0.06, 0.12, bevel=0.02), loc=(0, -0.12 * td, -0.04)),
                  "plate", pelvis)
        for sx in (1, -1):
            self.part("tasset", C.bm_xform(C.bm_box(0.10 * tw, 0.18 * td, 0.16, bevel=0.025),
                      loc=(0.20 * tw * sx, -0.01, -0.06), rot=(0, 0.25 * sx, 0)), "plate", pelvis)

    def build_torso(self, spine) -> None:
        S = self.S
        tw, td, th = S["torso"]
        if S.get("organic"):
            self.build_alien_torso(spine, tw, td, th)
            return
        if S.get("orb"):
            self.build_orb(spine, tw, td, th)
            return
        if S.get("thin"):
            # cage thoracique étroite + cœur bleu lumineux
            secs = []
            for z, rx, ry in ((0.06, 0.10, 0.075), (0.18, 0.15, 0.10), (0.30, 0.19, 0.12), (0.40, 0.17, 0.10),
                              (th, 0.07, 0.06)):
                secs.append(C.ellipse(0, 0, z, rx * tw, ry * td, 14))
            self.part("ribcage", C.bm_loft(secs), "plate", spine)
            for k in range(3):
                z = 0.17 + 0.07 * k
                rib = C.bm_xform(C.bm_torus(18, 5, 1.0, 0.07), loc=(0, -0.01, z), scale=(0.165 * tw, 0.115 * td, 0.11))
                self.part("rib%d" % k, rib, "light", spine)
            for sx in (1, -1):
                pec = C.bm_box(0.14 * tw, 0.06, 0.12, bevel=0.025)
                C.bm_xform(pec, loc=(0.09 * tw * sx, -0.10 * td, 0.34), rot=(0.25, 0, -0.25 * sx))
                self.part("pec", pec, "armor", spine)
            self.part("coreRing", C.bm_xform(C.bm_torus(20, 6, 0.10, 0.026), loc=(0, -0.13 * td, 0.25),
                      rot=(math.pi / 2 - 0.45, 0, 0)), "metal", spine)
            self.part("coreGlow", C.bm_xform(C.bm_torus(22, 6, 0.145, 0.02), loc=(0, -0.125 * td, 0.25),
                      rot=(math.pi / 2 - 0.45, 0, 0)), "blue", spine)
            self.part("coreGlow2", C.bm_xform(C.bm_torus(22, 5, 0.175, 0.008), loc=(0, -0.115 * td, 0.25),
                      rot=(math.pi / 2 - 0.45, 0, 0)), "blue", spine)
            self.part("core", C.bm_xform(C.bm_sphere(16, 12, 1.0), loc=(0, -0.135 * td, 0.25),
                      scale=(0.10, 0.06, 0.10), rot=(-0.45, 0, 0)), "blue", spine)
            for k in range(4):
                a = k * math.pi / 2 + math.pi / 4
                self.part("coreVein", C.bm_xform(C.bm_box(0.012, 0.012, 0.10), loc=(0.15 * math.cos(a), -0.11 * td,
                          0.25 + 0.15 * math.sin(a)), rot=(0, -a + math.pi / 2, 0)), "blue", spine)
            return
        # torse blindé : plastron large, abdomen articulé, sac dorsal
        secs = []
        for z, rx, ry in ((0.02, 0.17, 0.13), (0.14, 0.20, 0.15), (0.28, 0.25, 0.17), (th - 0.06, 0.26, 0.16),
                          (th, 0.15, 0.11)):
            secs.append(C.ellipse(0, 0, z, rx * tw, ry * td, 18))
        self.part("torso", C.bm_loft(secs), "armor", spine)
        chest = C.bm_box(0.40 * tw, 0.12, 0.22, bevel=0.045)
        for v in chest.verts:
            if v.co.z < 0:
                v.co.x *= 0.78
        C.bm_xform(chest, loc=(0, -0.13 * td, th - 0.16))
        self.part("chest", chest, "plate", spine)
        for k in range(2):
            self.part("abs%d" % k, C.bm_xform(C.bm_box(0.20 * tw, 0.06, 0.06, bevel=0.015),
                      loc=(0, -0.13 * td, 0.07 + 0.075 * k)), "light", spine)
        self.part("chestLight", C.bm_xform(C.bm_box(0.12 * tw, 0.012, 0.025), loc=(0, -0.195 * td - 0.005, th - 0.18)),
                  S.get("accent", "red"), spine)
        self.part("backpack", C.bm_xform(C.bm_box(0.34 * tw, 0.14 * td, 0.30, bevel=0.04),
                  loc=(0, 0.17 * td, th - 0.20)), "dark", spine)
        for sx in (1, -1):
            self.part("vent", C.bm_xform(C.bm_cyl(10, 0.045, 0.05, 0.10), loc=(0.10 * tw * sx, 0.24 * td, th - 0.08)),
                      "gun", spine)
        self.part("collar", C.bm_xform(C.bm_cyl(14, 0.11 * tw, 0.09 * tw, 0.08), loc=(0, 0.0, th - 0.01)), "joint", spine)
        if S.get("heavy"):
            # blindage détaillé : grille de ventilation, plaques latérales, rivets, bandes lumineuses
            for k in range(3):
                self.part("grille%d" % k, C.bm_xform(C.bm_box(0.16 * tw, 0.015, 0.018), loc=(0, -0.19 * td - 0.012,
                          th - 0.10 - 0.035 * k)), "dark", spine)
            for sx in (1, -1):
                side = C.bm_box(0.07, 0.20 * td, 0.24, bevel=0.025)
                C.bm_xform(side, loc=(0.25 * tw * sx, -0.02, th - 0.30), rot=(0, 0.2 * sx, 0))
                self.part("sidePlate", side, "plate", spine)
                self.part("sideLight", C.bm_xform(C.bm_box(0.012, 0.012, 0.16), loc=(0.29 * tw * sx, -0.10 * td,
                          th - 0.30)), S.get("accent", "blue"), spine)
                for k in range(3):
                    self.part("rivet", C.bm_xform(C.bm_sphere(6, 4, 0.016), loc=(0.15 * tw * sx, -0.20 * td,
                              th - 0.08 - 0.06 * k)), "light", spine)
        if S.get("arch_core"):
            # cœur de réacteur rouge au plastron, ailerons dorsaux, antennes
            self.part("coreRing", C.bm_xform(C.bm_torus(22, 7, 0.10, 0.03), loc=(0, -0.20 * td, th - 0.20),
                      rot=(math.pi / 2 - 0.3, 0, 0)), "metal", spine)
            self.part("core", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, -0.205 * td, th - 0.20),
                      scale=(0.08, 0.04, 0.08), rot=(-0.3, 0, 0)), "red", spine)
            for sx in (1, -1):
                fin = C.bm_box(0.05, 0.30, 0.42, bevel=0.02)
                for v in fin.verts:
                    if v.co.z > 0:
                        v.co.y += 0.12
                C.bm_xform(fin, loc=(0.16 * tw * sx, 0.30 * td, th + 0.10), rot=(0.35, 0, 0.35 * sx))
                self.part("fin", fin, "armor", spine)
                self.part("finLight", C.bm_xform(C.bm_box(0.012, 0.20, 0.03), loc=(0.16 * tw * sx + 0.03 * sx,
                          0.30 * td, th + 0.22), rot=(0.35, 0, 0.35 * sx)), "red", spine)
        if S.get("guardian"):
            # carénage de cou haut + projecteurs d'épaule bleus
            self.part("cowl", C.bm_xform(C.bm_box(0.42 * tw, 0.16 * td, 0.14, bevel=0.05), loc=(0, 0.12 * td, th + 0.02)),
                      "armor", spine)
            for sx in (1, -1):
                self.part("pod", C.bm_xform(C.bm_box(0.12, 0.16, 0.10, bevel=0.03),
                          loc=(0.30 * tw * sx, 0.08, th + 0.10)), "gun", spine)
                self.part("podLight", C.bm_xform(C.bm_cyl(10, 0.035, 0.035, 0.02), loc=(0.30 * tw * sx, -0.005, th + 0.10),
                          rot=(math.pi / 2, 0, 0)), "blue", spine)

    def build_arms(self, spine) -> None:
        S, j = self.S, self.j
        tw = S["torso"][0]
        th = S["torso"][2]
        self.AU, self.AL = S["arm"]
        ar = S.get("arm_r", 1.0)
        for side, sx in (("L", 1), ("R", -1)):
            sho = Vector((S["shoulder_w"] * sx, 0.0, th - 0.07))
            ua = j["ua" + side] = J("ua" + side, spine, sho, quat=True)
            fa = j["fa" + side] = J("fa" + side, spine, quat=True)
            if S.get("organic"):
                self.part("shoulder" + side, C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0.02 * sx, 0, 0.02),
                          scale=(0.12 * ar, 0.11 * ar, 0.10 * ar)), "armor", ua)
                self.part("uarm" + side, C.bm_xform(C.bm_cyl(10, 0.07 * ar, 0.055 * ar, self.AU), loc=(0, 0, -self.AU / 2)),
                          "armor", ua)
                self.part("elbow" + side, C.bm_sphere(8, 6, 0.055 * ar), "plate", fa)
                self.part("farm" + side, C.bm_xform(C.bm_cyl(10, 0.05 * ar, 0.065 * ar, self.AL), loc=(0, 0, -self.AL / 2)),
                          "plate", fa)
                self.part("hand" + side, C.bm_xform(C.bm_sphere(10, 7, 1.0), loc=(0, 0, -self.AL),
                          scale=(0.075 * ar, 0.07 * ar, 0.06 * ar)), "plate", fa)
                for k in (-1, 0, 1):
                    cl = C.bm_xform(C.bm_cyl(6, 0.022 * ar, 0.0, 0.26), loc=(0.04 * k * ar, -0.03, -self.AL - 0.12),
                                    rot=(0.35, 0.22 * k, 0))
                    self.part("claw" + side, cl, "claw", fa)
                continue
            if S.get("thin"):
                pad = C.bm_sphere(12, 8, 1.0)
                C.bm_xform(pad, loc=(0.02 * sx, 0, 0.02), scale=(0.09 * ar, 0.085 * ar, 0.075 * ar))
                self.part("shoulder" + side, pad, "armor", ua)
                self.part("uarm" + side, C.bm_xform(C.bm_cyl(8, 0.045 * ar, 0.036 * ar, self.AU), loc=(0, 0, -self.AU / 2)),
                          "plate", ua)
                self.part("elbow" + side, C.bm_sphere(8, 6, 0.042 * ar), "joint", fa)
                self.part("farm" + side, C.bm_xform(C.bm_cyl(8, 0.04 * ar, 0.05 * ar, self.AL), loc=(0, 0, -self.AL / 2)),
                          "armor", fa)
                self.part("farmLight" + side, C.bm_xform(C.bm_box(0.015, 0.012, self.AL * 0.5),
                          loc=(0, -0.045 * ar, -self.AL * 0.55)), "blue", fa)
                # griffes : trois longues lames
                for k in (-1, 0, 1):
                    cl = C.bm_xform(C.bm_cyl(6, 0.016, 0.0, 0.20), loc=(0.028 * k, -0.03, -self.AL - 0.08),
                                    rot=(0.25, 0.18 * k, 0))
                    self.part("claw" + side, cl, "claw", fa)
                self.part("hand" + side, C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, 0, -self.AL),
                          scale=(0.055, 0.05, 0.05)), "dark", fa)
                continue
            pad = C.bm_sphere(14, 9, 1.0)
            for v in pad.verts:
                if v.co.z < -0.2:
                    v.co.z = -0.2 + (v.co.z + 0.2) * 0.3
            C.bm_xform(pad, loc=(0.03 * sx, 0, 0.02), scale=(0.15 * ar, 0.14 * ar, 0.12 * ar))
            self.part("pauldron" + side, pad, "plate", ua)
            self.part("pauldronTrim" + side, C.bm_xform(C.bm_box(0.10 * ar, 0.012, 0.03), loc=(0.04 * sx, -0.135 * ar, 0.0)),
                      S.get("accent", "red"), ua)
            self.part("uarm" + side, C.bm_xform(C.bm_cyl(10, 0.075 * ar, 0.065 * ar, self.AU), loc=(0, 0, -self.AU / 2)),
                      "armor", ua)
            self.part("elbow" + side, C.bm_sphere(10, 7, 0.065 * ar), "joint", fa)
            cannon = S.get("weapon") == "arm_cannons"
            fr = 0.085 * ar if cannon else 0.07 * ar
            self.part("farm" + side, C.bm_xform(C.bm_cyl(10, fr * 0.9, fr, self.AL), loc=(0, 0, -self.AL / 2)),
                      "plate", fa)
            if cannon:
                # canon d'avant-bras : tube large + bouche lumineuse bleue
                self.part("barrel" + side, C.bm_xform(C.bm_cyl(12, 0.06 * ar, 0.065 * ar, 0.20),
                          loc=(0, 0, -self.AL - 0.08)), "gun", fa)
                self.part("muzzle" + side, C.bm_xform(C.bm_cyl(12, 0.045 * ar, 0.045 * ar, 0.02),
                          loc=(0, 0, -self.AL - 0.185)), "blue", fa)
                self.part("muzzleRing" + side, C.bm_xform(C.bm_torus(14, 5, 0.06 * ar, 0.015), loc=(0, 0, -self.AL - 0.17)),
                          "metal", fa)
                if S.get("architect"):
                    # canon double : second tube et bouche rouge, gaine lumineuse
                    self.part("barrel2" + side, C.bm_xform(C.bm_cyl(12, 0.035 * ar, 0.04 * ar, 0.26),
                              loc=(0.06 * ar * (1 if side == "L" else -1), 0.03, -self.AL - 0.08)), "gun", fa)
                    self.part("muzzle2" + side, C.bm_xform(C.bm_cyl(10, 0.025 * ar, 0.025 * ar, 0.02),
                              loc=(0.06 * ar * (1 if side == "L" else -1), 0.03, -self.AL - 0.215)), "red", fa)
            else:
                self.part("hand" + side, C.bm_xform(C.bm_box(0.09 * ar, 0.08 * ar, 0.10 * ar, bevel=0.02),
                          loc=(0, 0, -self.AL - 0.02)), "dark", fa)

    # --- têtes ---------------------------------------------------------------
    def head_mono(self, head) -> None:
        """Casque rond, gros œil rouge central (droïde, Atlas)."""
        hm = C.bm_sphere(18, 12, 1.0)
        for v in hm.verts:
            x, y, z = v.co
            if z < -0.3:
                z = -0.3 + (z + 0.3) * 0.5
            v.co = Vector((x * 0.15, y * 0.15, z * 0.15 + 0.15))
        self.part("helmet", hm, "plate", head)
        self.part("faceplate", C.bm_xform(C.bm_box(0.20, 0.06, 0.12, bevel=0.025), loc=(0, -0.12, 0.13)), "dark", head)
        self.part("eyeRim", C.bm_xform(C.bm_torus(18, 6, 0.072, 0.018), loc=(0, -0.152, 0.175),
                  rot=(math.pi / 2 - 0.5, 0, 0)), "metal", head)
        self.part("eyeSocket", C.bm_xform(C.bm_cyl(16, 0.07, 0.07, 0.03), loc=(0, -0.145, 0.175),
                  rot=(math.pi / 2 - 0.5, 0, 0)), "eye_rim", head)
        self.part("eye", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, -0.162, 0.18), scale=(0.058, 0.026, 0.058),
                  rot=(-0.5, 0, 0)), "red", head, grp="eye")
        for sx in (1, -1):
            self.part("ear", C.bm_xform(C.bm_cyl(10, 0.045, 0.045, 0.05), loc=(0.15 * sx, 0, 0.15),
                      rot=(0, math.pi / 2, 0)), "armor", head)
        self.part("crest", C.bm_xform(C.bm_box(0.03, 0.18, 0.04, bevel=0.01), loc=(0, 0.0, 0.30)), "light", head)
        self.part("antenna", C.bm_xform(C.bm_cyl(6, 0.008, 0.004, 0.16), loc=(0.11, 0.06, 0.34)), "metal", head)

    def head_none(self, head) -> None:
        pass

    def head_alien(self, head) -> None:
        """Tête large et basse, gueule à crocs, sept yeux roses lumineux."""
        hd = C.bm_sphere(18, 12, 1.0)
        for v in hd.verts:
            x, y, z = v.co
            if y < 0 and z < 0:
                y *= 1.25
            v.co = Vector((x * 0.20, y * 0.18, z * 0.14 + 0.10))
        self.part("skull", hd, "plate", head)
        self.part("crest", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, 0.06, 0.20), scale=(0.08, 0.16, 0.06),
                  rot=(-0.4, 0, 0)), "plate", head)
        self.part("maw", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.16, 0.02), scale=(0.11, 0.05, 0.05)),
                  "dark", head)
        for sx in (1, -1):
            for k in range(3):
                self.part("fang", C.bm_xform(C.bm_cyl(6, 0.014, 0.0, 0.07), loc=(0.03 * sx + 0.03 * k * sx, -0.19, 0.0),
                          rot=(math.pi, 0, 0)), "claw", head)
            self.part("mandible", C.bm_xform(C.bm_cyl(6, 0.025, 0.0, 0.14), loc=(0.15 * sx, -0.12, -0.02),
                      rot=(2.0, 0, 0.5 * sx)), "claw", head)
        for k, (x, z, r) in enumerate(((0.0, 0.18, 0.04), (0.065, 0.16, 0.032), (-0.065, 0.16, 0.032),
                                       (0.12, 0.12, 0.026), (-0.12, 0.12, 0.026), (0.035, 0.22, 0.022),
                                       (-0.035, 0.22, 0.022))):
            self.part("eye%d" % k, C.bm_xform(C.bm_sphere(10, 7, r), loc=(x, -0.15 + abs(x) * 0.35, z)), "pink", head,
                      grp="eye")

    def build_alien_torso(self, spine, tw, td, th) -> None:
        """Torse massif voûté (alien) : bosse dorsale, plaques chitineuses, pustules et tentacules."""
        secs = []
        for z, rx, ry, cy in ((0.0, 0.17, 0.14, 0.0), (0.14, 0.22, 0.18, 0.01), (0.28, 0.27, 0.21, 0.03),
                              (th - 0.08, 0.28, 0.20, 0.05), (th, 0.16, 0.13, 0.05)):
            secs.append(C.ellipse(0, cy, z, rx * tw, ry * td, 20))
        self.part("torso", C.bm_loft(secs), "armor", spine)
        hump = C.bm_sphere(16, 10, 1.0)
        C.bm_xform(hump, loc=(0, 0.12 * td, th - 0.12), scale=(0.24 * tw, 0.16 * td, 0.18))
        self.part("hump", hump, "armor", spine)
        for k in range(3):
            plate = C.bm_sphere(14, 8, 1.0)
            for v in plate.verts:
                if v.co.y > 0:
                    v.co.y *= 0.2
            C.bm_xform(plate, loc=(0, -0.17 * td, 0.08 + 0.11 * k), scale=(0.15 * tw - 0.01 * k, 0.05, 0.05))
            self.part("belly%d" % k, plate, "light", spine)
        for k, (x, y, z) in enumerate(((0.12, 0.22, 0.42), (-0.10, 0.25, 0.36), (0.02, 0.27, 0.28), (0.20, 0.14, 0.30),
                                       (-0.20, 0.16, 0.44), (0.08, 0.20, 0.52))):
            self.part("pust%d" % k, C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(x * tw, y * td, z),
                      scale=(0.035, 0.035, 0.03)), "pink", spine)
        # tentacules dorsaux (4) : partent vers le haut et l'arrière, ondulent (post_pose)
        self.tentacles = []
        for c, (x, z, splay) in enumerate(((0.12, th - 0.04, 0.45), (-0.12, th - 0.04, -0.45),
                                           (0.20, th - 0.22, 0.85), (-0.20, th - 0.22, -0.85))):
            base_rot = (2.45, splay, 0.0)
            ch = self.chain("tent%d" % c, spine, Vector((x * tw, 0.16 * td, z)), 5, 0.13, 0.05, 0.015, "armor",
                            ring="pink")
            ch[0].rotation_euler = base_rot
            self.tentacles.append((base_rot, ch))

    def build_orb(self, spine, tw, td, th) -> None:
        """L'Architecte : torse-sphère massif portant un énorme œil rouge central, couronne d'antennes
        et ailerons dorsaux, anneaux lumineux rouges."""
        Rb = self.S.get("orb_r", 0.42)
        cz = th * 0.5 + 0.02
        self.part("orb", C.bm_xform(C.bm_sphere(30, 20, Rb), loc=(0, 0, cz)), "armor", spine)
        for k, (z, key) in enumerate(((-0.30, "plate"), (0.05, "dark"))):
            self.part("orbBand%d" % k, C.bm_xform(C.bm_torus(36, 8, 1.0, 0.06), loc=(0, 0, cz + z * Rb),
                      scale=(Rb * 1.02, Rb * 1.02, Rb)), key, spine)
        self.part("orbGlow", C.bm_xform(C.bm_torus(36, 6, 1.0, 0.02), loc=(0, 0, cz - 0.30 * Rb + 0.02),
                  scale=(Rb * 1.04, Rb * 1.04, Rb)), "red", spine)
        cap = C.bm_sphere(20, 12, 1.0)
        for v in cap.verts:
            if v.co.z < 0:
                v.co.z *= 0.2
        C.bm_xform(cap, loc=(0, 0.16 * Rb, cz + Rb * 0.70), scale=(Rb * 0.62, Rb * 0.55, Rb * 0.36))
        self.part("cap", cap, "plate", spine)
        for sx in (1, -1):
            cheek = C.bm_box(0.10, Rb * 0.5, Rb * 0.6, bevel=0.03)
            C.bm_xform(cheek, loc=(Rb * 0.80 * sx, -Rb * 0.40, cz - 0.02), rot=(0, 0, 0.6 * sx))
            self.part("cheek", cheek, "plate", spine)
            self.part("cheekLight", C.bm_xform(C.bm_box(0.014, Rb * 0.35, 0.03), loc=(Rb * 0.86 * sx, -Rb * 0.42,
                      cz + 0.05), rot=(0, 0, 0.6 * sx)), "red", spine)
            # antennes
            self.part("antenna", C.bm_xform(C.bm_cyl(8, 0.018, 0.008, 0.55), loc=(Rb * 0.35 * sx, 0.10, cz + Rb + 0.18),
                      rot=(-0.25, 0.3 * sx, 0)), "metal", spine)
            self.part("antTip", C.bm_xform(C.bm_sphere(8, 6, 0.035), loc=(Rb * 0.35 * sx + 0.08 * sx, 0.03,
                      cz + Rb + 0.44)), "red", spine)
            # ailerons dorsaux
            fin = C.bm_box(0.05, 0.36, 0.55, bevel=0.02)
            for v in fin.verts:
                if v.co.z > 0:
                    v.co.y += 0.18
            C.bm_xform(fin, loc=(Rb * 0.45 * sx, Rb * 0.85, cz + Rb * 0.45), rot=(0.4, 0, 0.30 * sx))
            self.part("fin", fin, "armor", spine)
            self.part("finLight", C.bm_xform(C.bm_box(0.014, 0.26, 0.03), loc=(Rb * 0.45 * sx + 0.03 * sx, Rb * 0.88,
                      cz + Rb * 0.62), rot=(0.4, 0, 0.30 * sx)), "red", spine)
        # œil central, tourné vers la caméra (haut de la face avant) : socle, anneau, lentille rouge
        er = Rb * 0.46
        el = 0.62
        ey, ez = -Rb * math.cos(el), cz + Rb * math.sin(el)
        nrm = Vector((0, -math.cos(el), math.sin(el)))
        tilt = math.pi / 2 - el
        def at(d):
            return (0, ey + nrm.y * d, ez + nrm.z * d)
        self.part("eyeSocket", C.bm_xform(C.bm_cyl(28, er, er, 0.06), loc=at(0.0), rot=(tilt, 0, 0)), "eye_rim", spine)
        self.part("eyeRing", C.bm_xform(C.bm_torus(32, 8, er * 1.06, 0.04), loc=at(0.02), rot=(tilt, 0, 0)),
                  "metal", spine)
        self.part("eyeGlowRing", C.bm_xform(C.bm_torus(32, 6, er * 0.82, 0.022), loc=at(0.035), rot=(tilt, 0, 0)),
                  "red", spine)
        self.part("eye", C.bm_xform(C.bm_sphere(20, 14, 1.0), loc=at(0.03), scale=(er * 0.64, er * 0.64, er * 0.25),
                  rot=(tilt, 0, 0)), "red", spine, grp="eye")
        # jupe sous la sphère
        self.part("skirt", C.bm_xform(C.bm_cyl(24, Rb * 0.55, Rb * 0.75, 0.14), loc=(0, 0, cz - Rb * 0.82)), "dark", spine)

    def head_thin(self, head) -> None:
        """Crâne allongé, deux petits yeux bleus (téléporteur)."""
        sk = C.bm_sphere(16, 12, 1.0)
        for v in sk.verts:
            x, y, z = v.co
            if y > 0:
                y *= 1.5
                z += 0.25 * y
            if z < 0:
                x *= 1.0 - 0.35 * (-z)
            v.co = Vector((x * 0.11, y * 0.12, z * 0.13 + 0.13))
        self.part("skull", sk, "plate", head)
        self.part("jaw", C.bm_xform(C.bm_box(0.12, 0.10, 0.05, bevel=0.015), loc=(0, -0.06, 0.03)), "dark", head)
        for sx in (1, -1):
            self.part("eye", C.bm_xform(C.bm_sphere(10, 7, 1.0), loc=(0.045 * sx, -0.108, 0.16),
                      scale=(0.036, 0.016, 0.022), rot=(-0.4, 0.3 * sx, 0)), "blue", head, grp="eye")
        self.part("cable", C.bm_tube(C.bezier((0, 0.10, 0.18), (0, 0.22, 0.16), (0, 0.20, 0.0), (0, 0.10, -0.08), 6),
                                     [0.015] * 6, seg=6), "joint", head)

    def head_guardian(self, head) -> None:
        """Petite tête enfoncée entre les épaules, deux yeux bleus (gardien)."""
        hb = C.bm_box(0.22, 0.20, 0.15, bevel=0.05)
        C.bm_xform(hb, loc=(0, -0.03, 0.06))
        self.part("helm", hb, "plate", head)
        self.part("visor", C.bm_xform(C.bm_box(0.19, 0.04, 0.06, bevel=0.015), loc=(0, -0.13, 0.07)), "dark", head)
        for sx in (1, -1):
            self.part("eye", C.bm_xform(C.bm_sphere(10, 7, 1.0), loc=(0.052 * sx, -0.152, 0.08),
                      scale=(0.042, 0.016, 0.028), rot=(-0.35, 0, 0)), "blue", head, grp="eye")
        self.part("crest", C.bm_xform(C.bm_box(0.05, 0.16, 0.05, bevel=0.015), loc=(0, -0.02, 0.15)), "light", head)

    def head_architect(self, head) -> None:
        """Tête-dôme blindée avec un énorme œil rouge central (boss)."""
        dm = C.bm_sphere(22, 14, 1.0)
        for v in dm.verts:
            x, y, z = v.co
            if z < -0.4:
                z = -0.4 + (z + 0.4) * 0.3
            v.co = Vector((x * 0.24, y * 0.22, z * 0.20 + 0.16))
        self.part("dome", dm, "armor", head)
        self.part("brow", C.bm_xform(C.bm_box(0.36, 0.10, 0.06, bevel=0.025), loc=(0, -0.17, 0.27), rot=(0.3, 0, 0)),
                  "plate", head)
        self.part("eyeRim", C.bm_xform(C.bm_torus(22, 8, 0.10, 0.03), loc=(0, -0.205, 0.16), rot=(math.pi / 2, 0, 0)),
                  "metal", head)
        self.part("eyeSocket", C.bm_xform(C.bm_cyl(20, 0.11, 0.11, 0.04), loc=(0, -0.19, 0.16), rot=(math.pi / 2, 0, 0)),
                  "eye_rim", head)
        self.part("eye", C.bm_xform(C.bm_sphere(18, 12, 1.0), loc=(0, -0.215, 0.16), scale=(0.08, 0.035, 0.08)),
                  "red", head, grp="eye")
        for sx in (1, -1):
            self.part("cheek", C.bm_xform(C.bm_box(0.08, 0.14, 0.12, bevel=0.03), loc=(0.18 * sx, -0.08, 0.06),
                      rot=(0, 0, 0.3 * sx)), "plate", head)
            self.part("sideLight", C.bm_xform(C.bm_box(0.012, 0.06, 0.02), loc=(0.225 * sx, -0.08, 0.10)), "red", head)

    # --- armes ---------------------------------------------------------------
    def build_weapon(self, spine) -> None:
        w = self.S.get("weapon")
        if w in ("rifle", "heavy_rifle"):
            heavy = w == "heavy_rifle"
            g = J("w_rifle", spine)
            self.weapons["rifle"] = g
            k = 1.25 if heavy else 1.0
            self.part("receiver", C.bm_xform(C.bm_box(0.08 * k, 0.30 * k, 0.12 * k, bevel=0.02), loc=(0, -0.05, 0.02)),
                      "gun", g)
            self.part("barrel", C.bm_xform(C.bm_cyl(10, 0.024 * k, 0.024 * k, 0.34 * k), loc=(0, -0.36 * k, 0.04),
                      rot=(math.pi / 2, 0, 0)), "metal", g)
            self.part("shroud", C.bm_xform(C.bm_box(0.07 * k, 0.20 * k, 0.07 * k, bevel=0.015), loc=(0, -0.26 * k, 0.04)),
                      "plate", g)
            self.part("mag", C.bm_xform(C.bm_box(0.05 * k, 0.07 * k, 0.14 * k, bevel=0.01), loc=(0, -0.04, -0.09),
                      rot=(0.2, 0, 0)), "dark", g)
            self.part("stock", C.bm_xform(C.bm_box(0.06 * k, 0.18 * k, 0.10 * k, bevel=0.02), loc=(0, 0.17 * k, 0.0)),
                      "gun", g)
            self.part("gunLight", C.bm_xform(C.bm_box(0.012, 0.16 * k, 0.018), loc=(0.042 * k, -0.10, 0.04)),
                      self.S.get("accent", "red"), g)
            self.part("tip", C.bm_xform(C.bm_cyl(10, 0.016 * k, 0.016 * k, 0.012), loc=(0, -0.53 * k, 0.04),
                      rot=(math.pi / 2, 0, 0)), self.S.get("accent", "red"), g)
            self.muzzle_local = ("w_rifle", (0, -0.56 * k, 0.04))
        if self.S.get("shield"):
            g = J("w_shield", spine)
            self.weapons["shield"] = g
            sh = C.bm_box(0.08, 0.44, 0.60, bevel=0.04)
            for v in sh.verts:
                v.co.x += 0.06 * (v.co.y / 0.22) ** 2 * -1
            self.part("shieldPlate", C.bm_xform(sh, rot=(0, 0, math.pi / 2)), "plate", g)
            self.part("shieldRim", C.bm_xform(C.bm_box(0.40, 0.03, 0.04, bevel=0.01), loc=(0, -0.05, 0.27)), "light", g)
            self.part("shieldGlow", C.bm_xform(C.bm_box(0.30, 0.012, 0.035), loc=(0, -0.055, 0.12)), "blue", g)
            self.part("shieldGlow2", C.bm_xform(C.bm_box(0.30, 0.012, 0.035), loc=(0, -0.055, -0.06)), "blue", g)
            self.part("shieldEmblem", C.bm_xform(C.bm_cyl(14, 0.07, 0.07, 0.015), loc=(0, -0.055, 0.03),
                      rot=(math.pi / 2, 0, 0)), "light", g)
        if self.S.get("weapon") == "arm_cannons":
            self.muzzle_local = ("faR", (0, 0, -self.AL - 0.20))
        if self.S.get("weapon") == "claws":
            self.muzzle_local = ("faR", (0, 0, -self.AL - 0.18))

    # ------------------------------------------------------------------ poses
    def hunch(self) -> float:
        return self.S.get("hunch", 0.30 if self.S.get("thin") else 0.04)

    def post_pose(self, anim: str, i: int, n: int) -> None:
        """Tentacules dorsaux (alien) : ondulation selon l'animation, inertes à la mort."""
        if not getattr(self, "tentacles", None):
            return
        ph = 2 * math.pi * i / max(n, 1)
        amp = {"idle": 0.22, "run": 0.45, "attack": 0.6, "hit": 0.4, "death": 0.0}.get(anim, 0.3)
        limp = (i / max(n - 1, 1)) if anim == "death" else 0.0
        for c, (base_rot, chain) in enumerate(self.tentacles):
            for k, e in enumerate(chain):
                if k == 0:
                    e.rotation_euler = (base_rot[0] - 0.9 * limp, base_rot[1], base_rot[2])
                else:
                    e.rotation_euler = (0.32 * (1 - limp) + amp * math.sin(ph + k * 0.9 + c * 1.7), 0,
                                        0.25 * amp * math.cos(ph + c))

    def rest(self) -> None:
        j = self.j
        for name in ("pelvis", "spine", "neck", "head"):
            j[name].rotation_euler = (0, 0, 0)
        j["body"].location = (0, 0, 0)
        j["body"].rotation_euler = (0, 0, 0)
        j["pelvis"].location = (0, 0, self.PZ)
        j["head"].rotation_euler = (-0.12 if not self.hunch() > 0.2 else 0.05, 0, 0)
        for g in self.grp:
            if g not in ("glow_on", "glow_off"):
                self.show(g, True)

    def feet(self, fl, fr, pitch_l=0.0, pitch_r=0.0) -> None:
        """Pieds aux cibles (repère du corps, au sol z = 0) ; hanches suivant le bassin."""
        j = self.j
        pz = j["pelvis"].location
        hw = self.HW
        pole = Vector((0, -1, 0.2))
        for side, sx, tgt, pit in (("L", 1, fl, pitch_l), ("R", -1, fr, pitch_r)):
            hip = Vector((pz.x + hw * sx, pz.y, pz.z - 0.05))
            j["th" + side].location = hip
            fz = self.S.get("foot_h", 0.07)
            t = Vector(tgt) + Vector((0, 0, fz))
            H = self.ik(j["th" + side], j["sh" + side], t, pole, self.L1, self.L2)
            j["ft" + side].location = H - Vector((0, 0, fz))
            j["ft" + side].rotation_euler = (pit, 0, 0)

    def stance(self, w=1.0, dy=0.0) -> tuple:
        hw = self.HW * 1.15 * w
        return (Vector((hw, -0.04 + dy, 0)), Vector((-hw, 0.04 - dy, 0)))

    def hold(self, aim: float = 0.0, dz: float = 0.0, recoil: float = 0.0, side_recoil: float = 0.0) -> None:
        """Bras selon l'arme ; aim 0 (repos) .. 1 (en joue)."""
        S = self.S
        w = S.get("weapon")
        tw = S["torso"][0]
        th = S["torso"][2]
        Rp, Lp = Vector((-0.8, 0.5, -0.6)), Vector((0.8, 0.5, -0.6))
        reach = self.AU + self.AL
        if w in ("rifle", "heavy_rifle"):
            k = 1.25 if w == "heavy_rifle" else 1.0
            rest_loc = Vector((-0.10 * tw, -0.26 * tw, th - 0.34 + dz))
            aim_loc = Vector((-0.08 * tw, -0.30 * tw, th - 0.12))
            loc = rest_loc.lerp(aim_loc, aim) + Vector((0, 0.06 * recoil, 0.02 * recoil))
            rot = (0.45 * (1 - aim) - 0.25 * recoil, 0.0, 0.45 * (1 - aim))
            self.place("rifle", loc, rot)
            grip = self.wpt("rifle", (0, 0.04, -0.06))
            fore = self.wpt("rifle", (0, -0.24 * k, -0.02))
            self.ik(self.j["uaR"], self.j["faR"], grip + Vector((0, 0, self.AL * 0.0)), Rp, self.AU, self.AL)
            self.ik(self.j["uaL"], self.j["faL"], fore, Lp, self.AU, self.AL)
            if S.get("shield"):
                # bouclier porté devant à gauche, le fusil calé sur le bord
                self.place("shield", Vector((0.22 * tw, -0.36 * tw - 0.08 * aim, th - 0.42)), (0.0, 0.0, -0.35 + 0.2 * aim))
        elif w == "arm_cannons":
            for side, sx, rc in (("R", -1, recoil), ("L", 1, side_recoil)):
                low = Vector((0.30 * tw * sx, -0.20, th - 0.32 - reach * 0.55 + dz))
                up = Vector((0.24 * tw * sx, -reach * 0.92, th - 0.22))
                tgt = low.lerp(up, aim) + Vector((0, 0.10 * rc, 0.03 * rc))
                self.ik(self.j["ua" + side], self.j["fa" + side], tgt, Rp if side == "R" else Lp, self.AU, self.AL)
        elif w == "claws":
            for side, sx in (("R", -1), ("L", 1)):
                low = Vector((0.22 * sx, -0.10, th - reach * 0.85 + dz))
                up = Vector((0.20 * sx, -reach * 0.75, th - 0.30))
                self.ik(self.j["ua" + side], self.j["fa" + side], low.lerp(up, aim), Rp if side == "R" else Lp,
                        self.AU, self.AL)

    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        t = 2 * math.pi * i / n
        b, sway = math.sin(t), math.sin(t + 0.6)
        hu = self.hunch()
        j["pelvis"].location.z = self.PZ - 0.012 * (1 - b) * 0.5 - (0.06 if hu > 0.2 else 0.0)
        j["pelvis"].rotation_euler = (0, 0.012 * sway, 0.03 * sway)
        j["spine"].rotation_euler = (hu + 0.016 * b, -0.02 * sway, 0)
        j["neck"].rotation_euler = (-hu * 0.85 - 0.016 * b, 0.04 * sway, 0.03 * sway)
        fl, fr = self.stance(1.1 if self.S.get("heavy") else 1.0)
        self.feet(fl, fr)
        self.hold(aim=0.15 if self.S.get("weapon") != "claws" else 0.25, dz=0.012 * b)

    def pose_run(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        p = 2 * math.pi * i / n
        s = math.sin(p)
        heavy = self.S.get("heavy")
        A = 0.20 if heavy else 0.30
        lift = 0.10 if heavy else 0.16
        j["pelvis"].location.z = self.PZ - 0.06 + 0.05 * abs(math.sin(p + 0.35))
        j["pelvis"].rotation_euler = (0, 0, -0.12 * s)
        lean = self.hunch() + 0.12 if self.hunch() > 0.2 else (0.12 if heavy else 0.22)
        j["spine"].rotation_euler = (lean, 0, 0.14 * s)
        j["neck"].rotation_euler = (-lean * 0.8, 0, -0.10 * s)
        hw = self.HW * 1.05
        fl = Vector((hw, -A * math.sin(p), lift * max(0.0, math.cos(p))))
        fr = Vector((-hw, -A * math.sin(p + math.pi), lift * max(0.0, math.cos(p + math.pi))))
        self.feet(fl, fr, pitch_l=0.4 * max(0.0, math.cos(p)), pitch_r=0.4 * max(0.0, -math.cos(p)))
        if self.S.get("weapon") == "claws":
            # bras en arrière, griffes prêtes
            th = self.S["torso"][2]
            for side, sx, ph in (("R", -1, 0.0), ("L", 1, math.pi)):
                tgt = Vector((0.24 * sx, 0.16 + 0.14 * math.sin(p + ph), th - 0.42))
                self.ik(self.j["ua" + side], self.j["fa" + side], tgt, Vector((0.8 * sx, 0.5, -0.6)), self.AU, self.AL)
        else:
            self.hold(aim=0.1, dz=0.02 * math.cos(p))

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        k = (1.0, 0.6, 0.25)[i]
        j["pelvis"].location.z = self.PZ - 0.03 * k
        j["pelvis"].location.y = 0.05 * k
        j["spine"].rotation_euler = (-0.30 * k + (0.8 * self.hunch() if self.hunch() > 0.2 else 0.0), 0, 0.12 * k)
        j["neck"].rotation_euler = (-0.30 * k, 0, -0.14 * k)
        fl, fr = self.stance(1.0, dy=-0.05 * k)
        self.feet(fl, fr)
        self.hold(aim=0.2 * k, dz=0.06 * k)

    def pose_death(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        t = i / (n - 1)
        k = self.corpse_fall(t, back=0.66 if not self.S.get("heavy") else 0.60)
        j["spine"].rotation_euler = (-0.35 * (1 - k) - 0.05, 0, 0.12 * (1 - k))
        j["neck"].rotation_euler = (-0.3 * (1 - k), 0, 0.35 * min(1.0, t * 1.4))
        # jambes : pliées pendant la chute, une reste fléchie au sol
        hw = self.HW * 1.2
        knee = math.sin(min(1.0, t * 1.2) * math.pi) * 0.25
        self.feet(Vector((hw, -0.02 - 0.20 * k, knee * 0.8)), Vector((-hw * 1.1, 0.02 + 0.05 * k, 0.0)))
        # bras écartés au sol
        th = self.S["torso"][2]
        arm_u = min(1.0, t / 0.6)
        reach = self.AU + self.AL
        hl = Vector((0.28 + 0.2 * arm_u, -0.05 + 0.05 * arm_u, th - reach * (0.8 - 0.6 * arm_u)))
        hr = Vector((-0.30 - 0.2 * arm_u, -0.08 + 0.05 * arm_u, th - reach * (0.75 - 0.55 * arm_u)))
        self.ik(j["uaL"], j["faL"], hl, Vector((0.8, 0.2, -0.6)), self.AU, self.AL)
        self.ik(j["uaR"], j["faR"], hr, Vector((-0.8, 0.2, -0.6)), self.AU, self.AL)
        if "rifle" in self.weapons:
            self.place("rifle", hr + Vector((0.05, -0.15 * arm_u, -0.04)), (0.2 + 1.2 * arm_u, 0.0, 0.9 * arm_u))
        if "shield" in self.weapons:
            self.place("shield", hl + Vector((0.08, -0.05, 0.0)), (0.3 + 1.0 * arm_u, 0.0, -0.4))
        if i >= n - 3:
            self.lit = False

    def pose_attack(self, i: int, n: int) -> None:
        w = self.S.get("weapon")
        self.rest()
        j = self.j
        if w in ("rifle", "heavy_rifle"):
            aim = (0.4, 0.95, 1.0, 1.0, 1.0, 0.9)[i]
            rc = (0, 0, 0, 1.0, 0.5, 0.1)[i]
            j["spine"].rotation_euler = (0.05 - 0.10 * rc, 0, 0.08)
            j["neck"].rotation_euler = (-0.04, 0, 0.06)
            j["pelvis"].location.y = 0.03 * rc
            fl, fr = self.stance(1.15, dy=0.06)
            self.feet(fl, fr)
            self.hold(aim=aim, recoil=rc)
        elif w == "arm_cannons":
            aim = (0.4, 0.9, 1.0, 1.0, 1.0, 0.8)[i]
            rr = (0, 0, 0, 1.0, 0.3, 0.0)[i]
            rl = (0, 0, 0, 0.6, 1.0, 0.2)[i]
            j["spine"].rotation_euler = (0.08 - 0.10 * max(rr, rl), 0, 0)
            j["pelvis"].location.y = 0.04 * max(rr, rl)
            j["pelvis"].location.z = self.PZ - 0.04
            fl, fr = self.stance(1.25, dy=0.08)
            self.feet(fl, fr)
            self.hold(aim=aim, recoil=rr, side_recoil=rl)
        elif w == "claws":
            # bond + double entaille
            crouch = (0.06, 0.12, 0.14, 0.04, 0.02, 0.02)[i]
            j["pelvis"].location.z = self.PZ - crouch
            j["pelvis"].location.y = (0.0, 0.03, 0.04, -0.14, -0.16, -0.06)[i]
            lean = (0.4, 0.6, 0.65, 0.75, 0.6, 0.45)[i]
            twist = (-0.2, -0.45, -0.5, 0.5, 0.6, 0.15)[i]
            j["spine"].rotation_euler = (lean, 0, twist)
            j["neck"].rotation_euler = (-lean * 0.8, 0, -twist * 0.5)
            st = (0.10, 0.18, 0.2, 0.34, 0.30, 0.16)[i]
            self.feet(Vector((self.HW, -st, 0)), Vector((-self.HW, st * 0.6, 0)))
            th = self.S["torso"][2]
            reach = self.AU + self.AL
            hr = [Vector((-0.30, 0.10, th - 0.2)), Vector((-0.38, 0.22, th - 0.05)), Vector((-0.40, 0.24, th - 0.02)),
                  Vector((0.10, -reach * 0.9, th - 0.25)), Vector((0.28, -reach * 0.6, th - 0.45)),
                  Vector((-0.15, -0.30, th - 0.40))][i]
            hl = [Vector((0.30, 0.05, th - 0.25)), Vector((0.36, 0.15, th - 0.1)), Vector((0.38, 0.16, th - 0.08)),
                  Vector((0.30, 0.10, th - 0.30)), Vector((-0.05, -reach * 0.85, th - 0.20)),
                  Vector((0.18, -0.30, th - 0.40))][i]
            self.ik(j["uaR"], j["faR"], hr, Vector((-0.8, 0.5, -0.4)), self.AU, self.AL)
            self.ik(j["uaL"], j["faL"], hl, Vector((0.8, 0.5, -0.4)), self.AU, self.AL)

    def muzzle_world(self) -> Vector:
        name, loc = self.muzzle_local
        ob = self.weapons.get("rifle") if name == "w_rifle" else self.j[name]
        return ob.matrix_world @ Vector(loc)


# ============================================================================= drone volant
class Spectre(Creature):
    """Sphère blindée qui vole, œil bleu central, six pattes articulées pendantes."""

    def build(self) -> None:
        S, j = self.S, self.j
        j["root"] = root = J("root", None)
        j["body"] = body = J("body", root)
        body.scale = (S["scale"],) * 3
        self.HZ = S.get("hover", 0.78)
        self.R = S.get("radius", 0.22)
        j["core"] = core = J("core", body, (0, 0, self.HZ))
        R = self.R
        shell = C.bm_sphere(22, 14, R)
        self.part("shell", shell, "armor", core)
        for k, z in enumerate((-0.35, 0.05)):
            band = C.bm_xform(C.bm_torus(26, 6, 1.0, 0.06), loc=(0, 0, z * R), scale=(R * 1.02, R * 1.02, R))
            self.part("band%d" % k, band, "light" if k else "plate", core)
        self.part("cap", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, 0, R * 0.92), scale=(R * 0.45, R * 0.45, R * 0.18)),
                  "plate", core)
        self.part("antenna", C.bm_xform(C.bm_cyl(6, 0.01, 0.004, 0.16), loc=(R * 0.25, R * 0.2, R * 1.1)), "metal", core)
        self.part("antTip", C.bm_xform(C.bm_sphere(8, 6, 0.018), loc=(R * 0.25, R * 0.2, R * 1.1 + 0.08)), "blue", core)
        # œil : grand anneau sombre + lentille bleue
        self.part("eyeRim", C.bm_xform(C.bm_torus(20, 8, R * 0.42, R * 0.10), loc=(0, -R * 0.90, R * 0.02),
                  rot=(math.pi / 2, 0, 0)), "metal", core)
        self.part("eyeSocket", C.bm_xform(C.bm_cyl(18, R * 0.40, R * 0.40, 0.03), loc=(0, -R * 0.93, R * 0.02),
                  rot=(math.pi / 2, 0, 0)), "dark", core)
        self.part("eye", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, -R * 0.98, R * 0.02),
                  scale=(R * 0.26, R * 0.10, R * 0.26)), S.get("eye", "blue"), core, grp="eye")
        for sx in (1, -1):
            self.part("thruster", C.bm_xform(C.bm_cyl(12, R * 0.22, R * 0.28, R * 0.35), loc=(sx * R * 0.98, 0.0, -R * 0.1),
                      rot=(0, math.pi / 2, 0)), "gun", core)
            self.part("thrGlow", C.bm_xform(C.bm_cyl(12, R * 0.16, R * 0.16, 0.01), loc=(sx * R * 1.16, 0.0, -R * 0.1),
                      rot=(0, math.pi / 2, 0)), "blue", core)
        # pattes : 6 chaînes (hanche → coude → pointe)
        self.legs = []
        nl = S.get("legs", 6)
        for k in range(nl):
            a = 2 * math.pi * (k + 0.5) / nl
            hip = Vector((math.sin(a) * R * 0.75, -math.cos(a) * R * 0.75, -R * 0.55))
            up = J("lu%d" % k, core, hip, quat=True)
            lo = J("ll%d" % k, core, quat=True)
            L1, L2 = S.get("leg", (0.30, 0.40))
            self.part("ljoint%d" % k, C.bm_sphere(8, 6, 0.03), "joint", up)
            self.part("lup%d" % k, C.bm_xform(C.bm_cyl(8, 0.03, 0.022, L1), loc=(0, 0, -L1 / 2)), "plate", up)
            self.part("lknee%d" % k, C.bm_sphere(8, 6, 0.03), "joint", lo)
            self.part("llo%d" % k, C.bm_xform(C.bm_cyl(8, 0.022, 0.005, L2), loc=(0, 0, -L2 / 2)), "light", lo)
            self.legs.append((a, up, lo, L1, L2, hip))
        self.muzzle_obj = core
        self.muzzle_loc = (0, -R * 1.05, R * 0.02)

    def rest(self) -> None:
        j = self.j
        j["body"].location = (0, 0, 0)
        j["body"].rotation_euler = (0, 0, 0)
        j["core"].location = (0, 0, self.HZ)
        j["core"].rotation_euler = (0, 0, 0)

    def set_legs(self, spread: float, drop: float, wave: float = 0.0, trail: float = 0.0, phase: float = 0.0) -> None:
        """Pointes des pattes : écartées (spread), pendantes (drop), ondulation et traînée arrière."""
        for k, (a, up, lo, L1, L2, hip) in enumerate(self.legs):
            w = wave * math.sin(phase + k * 1.1)
            out = Vector((math.sin(a), -math.cos(a), 0))
            tip = hip + out * (spread + 0.05 * w) + Vector((0, trail, -drop + 0.06 * w))
            pole = out * 1.0 + Vector((0, 0, 0.8))
            self.ik(up, lo, tip, pole, L1, L2)

    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        t = 2 * math.pi * i / n
        self.j["core"].location.z = self.HZ + 0.04 * math.sin(t)
        self.j["core"].rotation_euler = (0.05 * math.sin(t + 1), 0.04 * math.cos(t), 0)
        self.set_legs(0.20, 0.42, wave=1.0, phase=t)

    def pose_run(self, i: int, n: int) -> None:
        self.rest()
        t = 2 * math.pi * i / n
        self.j["core"].location.z = self.HZ + 0.03 * math.sin(2 * t)
        self.j["core"].rotation_euler = (0.32, 0.06 * math.sin(t), 0)
        self.set_legs(0.14, 0.36, wave=1.4, trail=0.22, phase=2 * t)

    def pose_attack(self, i: int, n: int) -> None:
        self.rest()
        c = self.j["core"]
        pull = (0.05, 0.10, 0.12, -0.06, -0.02, 0.03)[i]
        c.location.y = pull
        c.location.z = self.HZ + (0.02, 0.05, 0.06, 0.0, 0.02, 0.03)[i]
        c.rotation_euler = (-0.15 + 0.3 * (i == 3), 0, 0)
        self.set_legs((0.24, 0.32, 0.34, 0.26, 0.24, 0.22)[i], (0.40, 0.32, 0.30, 0.40, 0.42, 0.42)[i], wave=0.4,
                      phase=i)

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        k = (1.0, 0.6, 0.25)[i]
        c = self.j["core"]
        c.location.y = 0.08 * k
        c.location.z = self.HZ - 0.06 * k
        c.rotation_euler = (-0.35 * k, 0.25 * k, 0)
        self.set_legs(0.28 * k + 0.18, 0.40, wave=1.0, phase=i * 2)

    def pose_death(self, i: int, n: int) -> None:
        self.rest()
        t = i / (n - 1)
        c = self.j["core"]
        e = smooth01(t / 0.7)
        bounce = 0.05 * math.sin(min(1.0, max(0.0, (t - 0.7) / 0.3)) * math.pi) if t > 0.7 else 0.0
        c.location.z = self.HZ + (self.R * 0.75 - self.HZ) * e + bounce
        c.location.y = 0.08 * e
        c.rotation_euler = (-0.9 * e, 0.6 * e, 0.4 * e)
        self.set_legs(0.20 + 0.25 * e, max(0.05, 0.42 - 0.40 * e) + 0.0, wave=0.6 * (1 - e), phase=i)
        if i >= n - 3:
            self.lit = False

    def muzzle_world(self) -> Vector:
        return self.muzzle_obj.matrix_world @ Vector(self.muzzle_loc)


# ============================================================================= araignée
class Spider(Creature):
    """Araignée mécanique : corps bas, tête à gros œil rouge, huit pattes IK au sol.
    `flying` : version drone d'élite (vol stationnaire, pattes repliées, canons)."""

    def build(self) -> None:
        S, j = self.S, self.j
        j["root"] = root = J("root", None)
        j["body"] = body = J("body", root)
        body.scale = (S["scale"],) * 3
        self.BZ = S.get("body_z", 0.34)
        j["torso"] = tor = J("torso", body, (0, 0, self.BZ))
        fly = S.get("flying")
        # abdomen arrière + thorax + tête avant
        ab = C.bm_sphere(18, 12, 1.0)
        C.bm_xform(ab, loc=(0, 0.20, 0.06), scale=(0.22, 0.26, 0.17))
        self.part("abdomen", ab, "armor", tor)
        for k in range(3):
            self.part("abRib%d" % k, C.bm_xform(C.bm_torus(20, 5, 1.0, 0.05), loc=(0, 0.12 + 0.08 * k, 0.07),
                      rot=(math.pi / 2, 0, 0), scale=(0.205 - 0.03 * k * k, 0.16 - 0.025 * k * k, 1.0)), "plate", tor)
        self.part("abLight", C.bm_xform(C.bm_box(0.05, 0.14, 0.012), loc=(0, 0.24, 0.235)), "red", tor)
        th = C.bm_sphere(16, 10, 1.0)
        C.bm_xform(th, loc=(0, -0.04, 0.04), scale=(0.19, 0.17, 0.12))
        self.part("thorax", th, "plate", tor)
        j["headJ"] = hj = J("headJ", tor, (0, -0.17, 0.05))
        hd = C.bm_sphere(18, 12, 1.0)
        C.bm_xform(hd, loc=(0, -0.06, 0.02), scale=(0.15, 0.13, 0.12))
        self.part("head", hd, "armor", hj)
        self.part("eyeRim", C.bm_xform(C.bm_torus(18, 6, 0.075, 0.022), loc=(0, -0.175, 0.04), rot=(math.pi / 2, 0, 0)),
                  "metal", hj)
        self.part("eyeSocket", C.bm_xform(C.bm_cyl(16, 0.07, 0.07, 0.03), loc=(0, -0.165, 0.04), rot=(math.pi / 2, 0, 0)),
                  "eye_rim", hj)
        self.part("eye", C.bm_xform(C.bm_sphere(14, 10, 1.0), loc=(0, -0.185, 0.04), scale=(0.055, 0.025, 0.055)),
                  "red", hj, grp="eye")
        for sx in (1, -1):
            self.part("subEye", C.bm_xform(C.bm_sphere(8, 6, 0.018), loc=(0.085 * sx, -0.15, 0.10)), "red", hj)
            # mandibules
            self.part("mandible", C.bm_xform(C.bm_cyl(6, 0.02, 0.004, 0.10), loc=(0.05 * sx, -0.16, -0.06),
                      rot=(1.9, 0, 0.3 * sx)), "light", hj)
        if fly:
            for sx in (1, -1):
                self.part("rotorArm", C.bm_xform(C.bm_box(0.30, 0.05, 0.03, bevel=0.01), loc=(0.26 * sx, 0.06, 0.16)),
                          "gun", tor)
                self.part("rotor", C.bm_xform(C.bm_cyl(18, 0.12, 0.12, 0.015), loc=(0.42 * sx, 0.06, 0.19)), "dark", tor)
                self.part("rotorGlow", C.bm_xform(C.bm_torus(18, 5, 0.12, 0.012), loc=(0.42 * sx, 0.06, 0.20)), "red", tor)
                g = J("gun%s" % ("L" if sx > 0 else "R"), tor, (0.16 * sx, -0.12, -0.07))
                self.part("gunBody", C.bm_xform(C.bm_box(0.07, 0.20, 0.07, bevel=0.015), loc=(0, -0.06, 0)), "gun", g)
                self.part("gunBarrel", C.bm_xform(C.bm_cyl(10, 0.02, 0.02, 0.16), loc=(0, -0.22, 0.0),
                          rot=(math.pi / 2, 0, 0)), "metal", g)
                self.part("gunTip", C.bm_xform(C.bm_cyl(10, 0.014, 0.014, 0.01), loc=(0, -0.30, 0.0),
                          rot=(math.pi / 2, 0, 0)), "red", g)
                self.weapons["gun%s" % ("L" if sx > 0 else "R")] = g
        # pattes
        self.legs = []
        L1, L2 = S.get("leg", (0.30, 0.42))
        for k, (ax, ay) in enumerate(((0.14, -0.14), (0.17, -0.04), (0.17, 0.06), (0.14, 0.16))):
            for sx in (1, -1):
                hip = Vector((ax * sx, ay, 0.02))
                up = J("lu%d%d" % (k, sx), tor, hip, quat=True)
                lo = J("ll%d%d" % (k, sx), tor, quat=True)
                self.part("lhip", C.bm_sphere(8, 6, 0.04), "joint", up)
                fem = C.bm_xform(C.bm_box(0.05, 0.06, L1, bevel=0.015), loc=(0, 0, -L1 / 2))
                self.part("lfem", fem, "plate", up)
                self.part("lknee", C.bm_sphere(8, 6, 0.035), "joint", lo)
                self.part("ltib", C.bm_xform(C.bm_cyl(8, 0.028, 0.006, L2), loc=(0, 0, -L2 / 2)), "armor", lo)
                ang = math.atan2(ay + 0.02, ax) if sx > 0 else math.atan2(ay + 0.02, -ax)
                self.legs.append((k, sx, hip, up, lo, L1, L2, ang))
        self.muzzle_loc = (0, -0.20, 0.04)

    def rest(self) -> None:
        j = self.j
        j["body"].location = (0, 0, 0)
        j["body"].rotation_euler = (0, 0, 0)
        j["torso"].location = (0, 0, self.BZ)
        j["torso"].rotation_euler = (0, 0, 0)
        j["headJ"].rotation_euler = (0, 0, 0)

    def set_legs(self, reach: float = 0.50, lift=None, shift=None, curl: float = 0.0, hang=None) -> None:
        """Pointes au sol (repère du corps) : rayon `reach` autour de la hanche ; lift[k] lève la
        patte, shift[k] l'avance (gait) ; curl replie les pattes sous le corps (mort, vol)."""
        tor = self.j["torso"]
        tz = tor.location.z
        trot = Euler(tor.rotation_euler, "XYZ").to_matrix()
        tinv = trot.inverted()
        for idx, (k, sx, hip, up, lo, L1, L2, ang) in enumerate(self.legs):
            dirv = Vector((math.cos(ang), math.sin(ang), 0))
            r = reach * (1.0 - 0.55 * curl)
            tip_w = Vector((hip.x, hip.y, 0)) + dirv * r
            if shift is not None:
                tip_w.y += shift[idx]
            z = 0.0 if lift is None else lift[idx]
            # repère du torse (le torse peut être incliné / soulevé)
            if hang is not None:
                z = tz - hang + (0.0 if lift is None else lift[idx])
            tip = tinv @ (Vector((tip_w.x, tip_w.y, z + curl * (tz - 0.05))) - Vector(tor.location))
            pole = Vector((dirv.x * 0.3, dirv.y * 0.3, 1.0))
            self.ik(up, lo, tip, pole, L1, L2)

    def gait(self, p: float, amp: float, h: float) -> tuple:
        lift, shift = [], []
        for idx, (k, sx, *_r) in enumerate(self.legs):
            grp = (k + (0 if sx > 0 else 1)) % 2
            ph = p + grp * math.pi
            shift.append(-amp * math.sin(ph))
            lift.append(h * max(0.0, math.cos(ph)))
        return lift, shift

    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        t = 2 * math.pi * i / n
        j = self.j
        if self.S.get("flying"):
            j["torso"].location.z = self.BZ + 0.04 * math.sin(t)
            j["torso"].rotation_euler = (0.04 * math.sin(t + 1), 0.03 * math.cos(t), 0)
            self.set_legs(0.30, lift=[0.03 * math.sin(t + k) for k in range(8)], hang=0.34)
            return
        j["torso"].location.z = self.BZ + 0.012 * math.sin(t)
        j["headJ"].rotation_euler = (0.04 * math.sin(t), 0, 0.12 * math.sin(t * 0.5))
        self.set_legs(0.50)

    def pose_run(self, i: int, n: int) -> None:
        self.rest()
        p = 2 * math.pi * i / n
        j = self.j
        if self.S.get("flying"):
            j["torso"].location.z = self.BZ + 0.03 * math.sin(2 * p)
            j["torso"].rotation_euler = (0.25, 0.05 * math.sin(p), 0)
            self.set_legs(0.24, shift=[0.14] * 8, hang=0.30)
            return
        j["torso"].location.z = self.BZ + 0.02 * abs(math.sin(2 * p))
        j["torso"].rotation_euler = (0.06, 0, 0.05 * math.sin(p))
        lift, shift = self.gait(p, 0.13, 0.12)
        self.set_legs(0.48, lift=lift, shift=shift)

    def pose_attack(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        if self.S.get("flying"):
            rc = (0, 0, 0, 1.0, 0.5, 0.1)[i]
            j["torso"].location.y = 0.05 * rc
            j["torso"].location.z = self.BZ + (0.0, 0.03, 0.04, 0.02, 0.02, 0.0)[i]
            j["torso"].rotation_euler = (-0.08 - 0.10 * rc, 0, 0)
            for g in ("gunL", "gunR"):
                self.weapons[g].location.y = -0.12 + 0.06 * rc
            self.set_legs(0.32, hang=0.34)
            return
        # se cabre (pattes avant levées), œil qui flashe, décharge
        rear = (0.15, 0.32, 0.36, 0.20, 0.12, 0.05)[i]
        j["torso"].rotation_euler = (-rear, 0, 0)
        j["torso"].location.z = self.BZ + 0.10 * rear
        j["headJ"].rotation_euler = (-0.1 * rear, 0, 0)
        lift = []
        for (k, sx, *_r) in self.legs:
            lift.append(0.30 * rear / 0.36 if k == 0 else 0.0)
        self.set_legs(0.48, lift=lift)

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        k = (1.0, 0.6, 0.25)[i]
        j = self.j
        j["torso"].location.y = 0.06 * k
        j["torso"].location.z = self.BZ - 0.05 * k + (0.0 if not self.S.get("flying") else 0.0)
        j["torso"].rotation_euler = (0.15 * k, 0.15 * k, 0)
        if self.S.get("flying"):
            self.set_legs(0.34, hang=0.32)
        else:
            self.set_legs(0.52 + 0.04 * k)

    def pose_death(self, i: int, n: int) -> None:
        self.rest()
        t = i / (n - 1)
        e = smooth01(t / 0.75)
        j = self.j
        j["torso"].location.z = self.BZ + (0.12 - self.BZ) * e
        j["torso"].rotation_euler = (0.25 * e, -0.45 * e, 0.3 * e)
        if self.S.get("flying"):
            self.set_legs(0.30 + 0.15 * e, hang=0.34 * (1 - e) + 0.0 * e, curl=0.6 * e)
        else:
            self.set_legs(0.50, curl=e)
        if i >= n - 3:
            self.lit = False

    def muzzle_world(self) -> Vector:
        if self.S.get("flying"):
            return self.weapons["gunR"].matrix_world @ Vector((0, -0.31, 0))
        return self.j["headJ"].matrix_world @ Vector(self.muzzle_loc)


# ============================================================================= alien
class Alien(Creature):
    """Créature violette : corps bombé, tête à plusieurs yeux, six tentacules-jambes et deux
    bras-tentacules griffus."""

    def build(self) -> None:
        S, j = self.S, self.j
        j["root"] = root = J("root", None)
        j["body"] = body = J("body", root)
        body.scale = (S["scale"],) * 3
        self.BZ = 0.52
        j["torso"] = tor = J("torso", body, (0, 0, self.BZ))
        bl = C.bm_sphere(20, 14, 1.0)
        for v in bl.verts:
            x, y, z = v.co
            if z > 0:
                y -= 0.25 * z * z
            v.co = Vector((x * 0.30, y * 0.30 + 0.04, z * 0.30))
        self.part("mantle", bl, "skin", tor)
        # pustules lumineuses sur le dos
        for k, (x, y, z) in enumerate(((0.12, 0.14, 0.20), (-0.10, 0.18, 0.17), (0.0, 0.24, 0.08), (0.18, 0.06, 0.10),
                                       (-0.17, 0.08, 0.12))):
            self.part("pust%d" % k, C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(x, y, z),
                      scale=(0.035, 0.035, 0.03)), "violet", tor)
        # plaques chitineuses
        for k in range(3):
            plate = C.bm_sphere(14, 8, 1.0)
            for v in plate.verts:
                if v.co.z < 0:
                    v.co.z *= 0.2
            C.bm_xform(plate, loc=(0, 0.06 + 0.07 * k, 0.24 - 0.05 * k), rot=(-0.5 - 0.3 * k, 0, 0),
                       scale=(0.20 - 0.03 * k, 0.10, 0.06))
            self.part("plate%d" % k, plate, "skin_dark", tor)
        j["headJ"] = hj = J("headJ", tor, (0, -0.25, 0.20))
        hd = C.bm_sphere(18, 12, 1.0)
        for v in hd.verts:
            x, y, z = v.co
            if y < 0 and z < 0:
                y *= 1.3
            v.co = Vector((x * 0.19, y * 0.18, z * 0.16))
        self.part("head", hd, "skin", hj)
        self.part("maw", C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, -0.15, -0.05), scale=(0.09, 0.04, 0.05)),
                  "skin_dark", hj)
        for sx in (1, -1):
            for k in range(2):
                self.part("fang", C.bm_xform(C.bm_cyl(6, 0.012, 0.0, 0.06), loc=(0.03 * sx + 0.025 * k * sx, -0.17, -0.07),
                          rot=(math.pi, 0, 0)), "claw", hj)
        for k, (x, z, r) in enumerate(((0.0, 0.08, 0.042), (0.075, 0.05, 0.032), (-0.075, 0.05, 0.032),
                                       (0.12, 0.0, 0.022), (-0.12, 0.0, 0.022))):
            self.part("eye%d" % k, C.bm_xform(C.bm_sphere(10, 7, r), loc=(x, -0.15 + abs(x) * 0.3, z)), "pink", hj,
                      grp="eye")
        # tentacules-jambes : 6 chaînes de 4 segments
        self.tent = []
        for k in range(6):
            a = math.radians(-150 + 60 * k + 30)
            base = Vector((math.cos(a) * 0.20, math.sin(a) * 0.18 + 0.04, -0.12))
            chain = self._chain("t%d" % k, tor, base, 4, S.get("tent_len", 0.17), 0.065, 0.02, "skin")
            self.tent.append((a, chain))
        # bras-tentacules griffus
        self.arms = {}
        for side, sx in (("L", 1), ("R", -1)):
            base = Vector((0.20 * sx, -0.14, 0.08))
            chain = self._chain("a" + side, tor, base, 4, 0.13, 0.05, 0.022, "skin")
            tip = chain[-1]
            for k in (-1, 0, 1):
                self.part("aclaw" + side, C.bm_xform(C.bm_cyl(6, 0.016, 0.0, 0.12), loc=(0.02 * k, 0.0, -0.17),
                          rot=(0.0, 0.25 * k, 0)), "claw", tip)
            self.arms[side] = chain
        self.muzzle_obj = self.arms["R"][-1]

    def _chain(self, name, parent, base, n, seg, r0, r1, key) -> list:
        out = []
        prev = parent
        for i in range(n):
            e = J("%s_%d" % (name, i), prev, base if i == 0 else (0, 0, -seg))
            ra = r0 + (r1 - r0) * i / n
            rb = r0 + (r1 - r0) * (i + 1) / n
            self.part("%s_s%d" % (name, i), C.bm_xform(C.bm_cyl(10, ra, rb, seg * 1.05), loc=(0, 0, -seg / 2)), key, e)
            if i % 2 == 1:
                self.part("%s_r%d" % (name, i), C.bm_xform(C.bm_torus(10, 4, ra, ra * 0.25), loc=(0, 0, 0)), "skin_light", e)
            out.append(e)
            prev = e
        return out

    def rest(self) -> None:
        j = self.j
        j["body"].location = (0, 0, 0)
        j["body"].rotation_euler = (0, 0, 0)
        j["torso"].location = (0, 0, self.BZ)
        j["torso"].rotation_euler = (0, 0, 0)
        j["headJ"].rotation_euler = (0, 0, 0)

    def set_tentacles(self, spread: float, bend: float, wave: float, phase: float, flat: float = 0.0) -> None:
        """Chaque tentacule part vers l'extérieur (spread), se courbe vers le sol (bend) et ondule."""
        for k, (a, chain) in enumerate(self.tent):
            for i, e in enumerate(chain):
                w = wave * math.sin(phase + k * 1.3 + i * 0.9)
                # base : penchée vers l'extérieur (direction a) ; segments suivants : courbure
                # vers le sol (positif = vers l'intérieur / le bas), à plat à la mort.
                if i == 0:
                    e.rotation_euler = (0, -(spread + w * 0.3), a)
                else:
                    e.rotation_euler = (0, bend * (1 - flat) * 0.45 - 0.30 * flat + w * 0.4, 0)

    def set_arms(self, raise_: float, reach: float, wave: float, phase: float, curl: float = 0.6) -> None:
        for side, sx in (("L", 1), ("R", -1)):
            chain = self.arms[side]
            for i, e in enumerate(chain):
                w = wave * math.sin(phase + i * 1.1 + (0 if sx > 0 else 2.0))
                if i == 0:
                    e.rotation_euler = (-(raise_ + w * 0.2) * 1.2 - reach * 0.9, 0.35 * sx * (1 - reach), 0)
                else:
                    e.rotation_euler = (curl * (1 - reach) * 0.5 + w * 0.3, 0, 0)

    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        t = 2 * math.pi * i / n
        self.j["torso"].location.z = self.BZ + 0.025 * math.sin(t)
        self.j["torso"].rotation_euler = (0.06 * math.sin(t), 0, 0.05 * math.sin(t * 0.5 + 1))
        self.j["headJ"].rotation_euler = (0.08 * math.sin(t + 1), 0, 0.10 * math.sin(t * 0.5))
        self.set_tentacles(0.95, 1.0, 0.25, t)
        self.set_arms(0.2, 0.0, 0.4, t)

    def pose_run(self, i: int, n: int) -> None:
        self.rest()
        p = 2 * math.pi * i / n
        self.j["torso"].location.z = self.BZ - 0.03 + 0.05 * abs(math.sin(p))
        self.j["torso"].location.y = 0.0
        self.j["torso"].rotation_euler = (0.30, 0, 0.08 * math.sin(p))
        self.j["headJ"].rotation_euler = (-0.25, 0, 0)
        self.set_tentacles(0.85, 1.1, 0.75, 2 * p)
        self.set_arms(-0.3, 0.0, 0.7, p)

    def pose_attack(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        rear = (0.2, 0.5, 0.55, -0.1, 0.0, 0.1)[i]
        j["torso"].rotation_euler = (-rear * 0.6 + (0.35 if i in (3, 4) else 0.0), 0, 0)
        j["torso"].location.z = self.BZ + 0.08 * max(rear, 0)
        j["torso"].location.y = (0.0, 0.04, 0.05, -0.12, -0.10, -0.04)[i]
        j["headJ"].rotation_euler = (-0.3 * rear, 0, 0)
        self.set_tentacles(0.95, 1.0, 0.3, i)
        reach = (0.0, 0.0, 0.0, 1.0, 0.8, 0.3)[i]
        self.set_arms((0.3, 1.1, 1.2, 0.2, 0.0, 0.2)[i], reach, 0.2, i)

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        k = (1.0, 0.6, 0.25)[i]
        j = self.j
        j["torso"].location.y = 0.07 * k
        j["torso"].location.z = self.BZ - 0.05 * k
        j["torso"].rotation_euler = (-0.30 * k, 0.15 * k, 0)
        j["headJ"].rotation_euler = (-0.25 * k, 0, 0.2 * k)
        self.set_tentacles(1.05, 1.0, 0.5, i * 2)
        self.set_arms(0.6 * k, 0.0, 0.5, i)

    def pose_death(self, i: int, n: int) -> None:
        self.rest()
        t = i / (n - 1)
        e = smooth01(t / 0.75)
        j = self.j
        j["torso"].location.z = self.BZ + (0.16 - self.BZ) * e
        j["torso"].rotation_euler = (0.2 * e, -0.7 * e, 0.3 * e)
        j["headJ"].rotation_euler = (0.4 * e, 0, 0.3 * e)
        self.set_tentacles(0.95 + 0.6 * e, 1.0, 0.3 * (1 - e), i, flat=e)
        self.set_arms(0.2 - 0.6 * e, 0.6 * e, 0.3 * (1 - e), i, curl=0.6 - 0.5 * e)
        if i >= n - 2:
            self.lit = False

    def muzzle_world(self) -> Vector:
        return self.muzzle_obj.matrix_world @ Vector((0, 0, -0.2))


# ----------------------------------------------------------------------------- spécifications
SPECS: dict[str, dict] = {
    "ss_security_droid": {
        "cls": Mech, "name": "Droïde de sécurité", "frame": 192, "cam_z": 1.02,
        "scale": 1.22, "leg": (0.34, 0.34), "hip_w": 0.12, "torso": (1.0, 1.0, 0.50), "shoulder_w": 0.27,
        "arm": (0.22, 0.23), "head": "mono", "head_scale": 1.45, "weapon": "rifle", "accent": "red",
    },
    "ss_spectre": {
        "cls": Spectre, "name": "Spectre", "frame": 192, "cam_z": 1.05,
        "scale": 1.30, "hover": 1.02, "radius": 0.25, "leg": (0.32, 0.50), "eye": "blue",
    },
    "ss_teleporter": {
        "cls": Mech, "name": "Téléporteur", "frame": 192, "cam_z": 1.04,
        "scale": 1.22, "leg": (0.40, 0.40), "hip_w": 0.09, "torso": (1.0, 1.0, 0.46), "shoulder_w": 0.21,
        "arm": (0.27, 0.28), "head": "thin", "weapon": "claws", "thin": True, "accent": "blue", "head_scale": 1.25,
        "limb_r": 1.5, "arm_r": 1.5,
    },
    "ss_detector": {
        "cls": Spider, "name": "Détecteur", "frame": 192, "cam_z": 0.52,
        "scale": 1.45, "body_z": 0.34, "leg": (0.30, 0.42),
    },
    "ss_station_guardian": {
        "cls": Mech, "name": "Gardien de station", "frame": 256, "cam_z": 1.30,
        "scale": 1.62, "leg": (0.32, 0.32), "hip_w": 0.16, "torso": (1.40, 1.25, 0.52), "shoulder_w": 0.40,
        "arm": (0.24, 0.26), "arm_r": 1.45, "limb_r": 1.35, "head": "guardian", "head_scale": 1.35, "weapon": "arm_cannons",
        "neck_up": 0.05, "neck_fwd": 0.06,
        "heavy": True, "guardian": True, "accent": "blue",
    },
    "ss_alien": {
        "cls": Mech, "name": "Alien", "frame": 256, "cam_z": 1.15,
        "scale": 1.40, "leg": (0.34, 0.34), "hip_w": 0.15, "torso": (1.45, 1.30, 0.58), "shoulder_w": 0.36,
        "arm": (0.30, 0.32), "arm_r": 1.7, "limb_r": 1.6, "head": "alien", "head_scale": 1.25, "weapon": "claws",
        "organic": True, "hunch": 0.42, "accent": "pink", "neck_fwd": 0.10, "neck_up": -0.04,
        "mats": {
            "armor": ("pat", [("#6a3a8c", "#1a0a2c", "#b070d8"), ("#58307a", "#140826", "#9a5cc4")], 5.0),
            "plate": ("#3c1c58", "#0e0418", "#7240a0"),
            "light": ("#c48ae0", "#4a2468", "#f2d0ff"),
            "dark": ("#1c0a26", "#080210", "#3a1850"),
        },
    },
    "ss_alien_brood": {
        "cls": Alien, "name": "Larve d'alien", "frame": 160, "cam_z": 0.45,
        "scale": 0.80, "tent_len": 0.17,
    },
    # --- Élites et boss (étape 2) ---
    "ss_drone_tieur": {
        "cls": Spider, "name": "Le Drone Tieur", "frame": 224, "cam_z": 0.80,
        "scale": 1.35, "body_z": 0.78, "leg": (0.26, 0.36), "flying": True,
    },
    "ss_atlas": {
        "cls": Mech, "name": "Le Sécurité Atlas", "frame": 256, "cam_z": 1.12,
        "scale": 1.36, "leg": (0.34, 0.34), "hip_w": 0.15, "torso": (1.30, 1.20, 0.54), "shoulder_w": 0.38,
        "arm": (0.24, 0.26), "arm_r": 1.35, "limb_r": 1.3, "head": "guardian", "head_scale": 1.35,
        "weapon": "heavy_rifle", "shield": True, "heavy": True, "accent": "blue", "neck_up": 0.05, "neck_fwd": 0.05,
    },
    "ss_architect": {
        # Rendu à demi-densité (px_scale 0,5) : modèle énorme dans un cadre raisonnable (atlas < 4096 px),
        # affiché deux fois plus grand en jeu (display_height).
        "cls": Mech, "name": "L'Architecte", "frame": 320, "cam_z": 2.55, "px_scale": 0.5,
        "scale": 2.85, "leg": (0.34, 0.34), "hip_w": 0.18, "torso": (1.6, 1.4, 0.72), "shoulder_w": 0.50,
        "arm": (0.30, 0.34), "arm_r": 1.75, "limb_r": 1.6, "head": "none", "orb": True, "orb_r": 0.46,
        "weapon": "arm_cannons", "heavy": True, "architect": True, "accent": "red",
    },
}
CLASSIC = ["ss_security_droid", "ss_spectre", "ss_teleporter", "ss_detector", "ss_station_guardian", "ss_alien",
           "ss_alien_brood"]
ELITES_BOSS = ["ss_drone_tieur", "ss_atlas", "ss_architect"]
KINDS = CLASSIC + ELITES_BOSS


# ----------------------------------------------------------------------------- rendu
def setup_scene(kind: str):
    sp = SPECS[kind]
    frame = sp["frame"]
    BE.FRAME = frame
    C.reset_scene()
    C.setup_render((frame * BE.SS, frame * BE.SS), samples=4, outline_px=4.6)
    o = sp["cls"](kind, sp)
    cam = C.ortho_camera(ELEV, 2.30 * frame / 160.0 / sp.get("px_scale", 1.0), target=(0, 0, sp["cam_z"]))
    cam.data.sensor_fit = "VERTICAL"
    return o, cam


def render_frame(path: str, frame: int):
    big = path + ".big.png"
    C.render_to(big)
    im = C.downscale(big, path, (frame, frame))
    os.remove(big)
    return im


def px(cam, co) -> list:
    p = C.world_to_px(cam, co)
    return [round(p[0] / BE.SS, 1), round(p[1] / BE.SS, 1)]


def write_meta(kind: str, frames: dict, muzzle: dict, feet) -> dict:
    frame = SPECS[kind]["frame"]
    bb = BE.measure(frames[("idle", "s", 0)])
    corpse = {}
    for d in DIRS:
        cb = BE.measure(frames[("death", d, ANIMS["death"][0] - 1)])
        corpse[d] = [cb[0], cb[1], cb[2], cb[3]]
    meta = {
        "kind": kind,
        "name": SPECS[kind]["name"],
        "frame_size": [frame, frame],
        "feet_offset": [feet[0], feet[1]],
        "display_height": round(frame * BE.WORLD_PER_PX / SPECS[kind].get("px_scale", 1.0), 1),
        "world_per_px": BE.WORLD_PER_PX / SPECS[kind].get("px_scale", 1.0),
        "height_px": bb[3] - bb[1],
        "head_px": bb[1],
        "fps": {a: f for a, (_n, f, _l) in ANIMS.items()},
        "frames": {a: n for a, (n, _f, _l) in ANIMS.items()},
        "loop": {a: l for a, (_n, _f, l) in ANIMS.items()},
        "directions": list(DIRS.keys()),
        "attack_hold_frame": 2,
        "attack_strike_frame": 3,
        "muzzle_px": muzzle,
        "corpse_bbox_px": corpse,
        "atlas": "res://assets/sprites/enemies/%s/%s_atlas.png" % (kind, kind),
        "notes": "Bestiaire Station spatiale (art/blender/bestiary/space_station/build_ss_enemies.py). "
                 "display_height = hauteur du cadre en unités monde ; feet_offset = pieds (px). attack : 0-2 élan "
                 "(2 tenue pendant le télégraphe), 3 coup/tir, 4-5 retour. death : dernière image = carcasse.",
    }
    od = os.path.join(OUT_DIR, kind)
    with open(os.path.join(od, "%s_meta.json" % kind), "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
        f.write("\n")
    return meta


def build_kind(kind: str) -> None:
    t0 = time.time()
    o, cam = setup_scene(kind)
    frame = SPECS[kind]["frame"]
    od = os.path.join(OUT_DIR, kind)
    tmp = os.path.join(TMP_DIR, kind)
    os.makedirs(od, exist_ok=True)
    os.makedirs(tmp, exist_ok=True)
    bpy.context.view_layer.update()
    f0 = C.world_to_px(cam, (0, 0, 0))
    feet = (round(f0[0] / BE.SS), round(f0[1] / BE.SS))
    frames, order, muzzle = {}, [], {}
    for d, ang in DIRS.items():
        o.j["root"].rotation_euler = (0, 0, math.radians(ang))
        o.dir_ang = ang
        for anim, (n, _f, _l) in ANIMS.items():
            for i in range(n):
                o.pose(anim, i, n)
                p = os.path.join(tmp, "%s_%s_%d.png" % (anim, d, i))
                frames[(anim, d, i)] = render_frame(p, frame)
                order.append((anim, d, i))
                if anim == "attack" and i == 3:
                    bpy.context.view_layer.update()
                    muzzle[d] = px(cam, o.muzzle_world())
        print(kind, "DIR", d, "%.0fs" % (time.time() - t0), flush=True)
    BE.FRAME = frame
    atlas, regions = BE.pack(frames, order)
    BE.compact_png(atlas, os.path.join(od, "%s_atlas.png" % kind))
    BE.write_import(kind)
    meta = write_meta(kind, frames, muzzle, feet)
    BE.write_tres(kind, ANIMS, regions, meta)
    print("DONE", kind, "%.0fs" % (time.time() - t0), "atlas", atlas.size, flush=True)


def repack(kind: str) -> None:
    from PIL import Image
    frame = SPECS[kind]["frame"]
    BE.FRAME = frame
    tmp = os.path.join(TMP_DIR, kind)
    frames, order = {}, []
    for d in DIRS:
        for anim, (n, _f, _l) in ANIMS.items():
            for i in range(n):
                frames[(anim, d, i)] = Image.open(os.path.join(tmp, "%s_%s_%d.png" % (anim, d, i))).convert("RGBA")
                order.append((anim, d, i))
    atlas, regions = BE.pack(frames, order)
    od = os.path.join(OUT_DIR, kind)
    BE.compact_png(atlas, os.path.join(od, "%s_atlas.png" % kind))
    with open(os.path.join(od, "%s_meta.json" % kind)) as f:
        meta = json.load(f)
    BE.write_tres(kind, ANIMS, regions, meta)
    BE.write_import(kind)
    print("REPACK", kind, atlas.size)


def preview(kinds, dirs, anims_spec) -> None:
    from PIL import Image
    for kind in kinds:
        o, cam = setup_scene(kind)
        frame = SPECS[kind]["frame"]
        tiles = []
        for d in dirs:
            o.j["root"].rotation_euler = (0, 0, math.radians(DIRS[d]))
            o.dir_ang = DIRS[d]
            for a in anims_spec:
                an, i = a.split(":")
                o.pose(an, int(i), ANIMS[an][0])
                p = os.path.join(TMP_DIR, "prev_%s_%s_%s_%s.png" % (kind, an, d, i))
                tiles.append(render_frame(p, frame))
        sheet = Image.new("RGBA", (frame * len(tiles), frame), (40, 52, 74, 255))
        for k, t in enumerate(tiles):
            sheet.alpha_composite(t, (k * frame, 0))
        out = os.path.join(TMP_DIR, "prev_%s.png" % kind)
        sheet.save(out)
        print("PREVIEW", out)


def sheet(kinds, out_path: str) -> None:
    """Planche de présentation (captures de la PR) depuis les images déjà rendues : pour chaque
    kind, idle (s), course (se), attaque (sw, image 3) et carcasse, sur fond bleu nuit."""
    from PIL import Image, ImageDraw, ImageFont
    cell = 200
    cols = 4
    pad = 34
    W = cols * cell + 220
    H = len(kinds) * (cell + 10) + pad + 20
    im = Image.new("RGBA", (W, H), (18, 26, 46, 255))
    dr = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
        small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
    except OSError:
        font = small = ImageFont.load_default()
    dr.text((14, 8), "STATION SPATIALE — les machines de l'espace", fill=(235, 240, 250), font=font)
    picks = [("idle", "s", 0, "repos"), ("run", "se", 2, "course"), ("attack", "sw", 3, "attaque"),
             ("death", "e", 7, "carcasse")]
    for r, kind in enumerate(kinds):
        y = pad + r * (cell + 10)
        dr.rounded_rectangle((8, y, W - 8, y + cell), 12, fill=(26, 36, 60, 255), outline=(90, 110, 150, 255))
        dr.text((18, y + 12), SPECS[kind]["name"], fill=(255, 255, 255), font=font)
        dr.text((18, y + 38), kind, fill=(170, 180, 200), font=small)
        for c, (an, d, i, lab) in enumerate(picks):
            p = os.path.join(TMP_DIR, kind, "%s_%s_%d.png" % (an, d, i))
            if not os.path.exists(p):
                continue
            t = Image.open(p).convert("RGBA")
            s = min(1.0, (cell - 24) / t.size[0])
            t = t.resize((int(t.size[0] * s), int(t.size[1] * s)), Image.LANCZOS)
            x0 = 210 + c * cell + (cell - t.size[0]) // 2
            im.alpha_composite(t, (x0, y + (cell - t.size[1]) // 2))
            dr.text((210 + c * cell + 8, y + cell - 20), lab, fill=(170, 180, 200), font=small)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    im.convert("RGB").save(out_path)
    print("SHEET", out_path)


def main() -> None:
    args = sys.argv[1:]
    kinds = args[args.index("--kinds") + 1].split(",") if "--kinds" in args else CLASSIC
    os.makedirs(TMP_DIR, exist_ok=True)
    if "--sheet" in args:
        out = args[args.index("--out") + 1] if "--out" in args else os.path.join(
            ROOT, "docs", "bestiaire", "captures", "space_station", "planche_modeles.png")
        sheet(kinds, out)
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
