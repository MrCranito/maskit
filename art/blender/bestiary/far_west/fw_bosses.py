"""Bestiaire Far West : élite « Le Buffle » (bête colossale cuirassée) et boss « Le Shérif
Sable-Fou » (cape rouge, chapeau, bras mécanique-canon, revolver ; à cheval pour sa charge).

Le shérif a une animation de plus, « charge » (8 images, boucle) : monté sur son cheval au galop,
jouée par EnemyVisual.set_run_anim("charge") pendant la compétence fw_sheriff_charge.
"""
from __future__ import annotations

import math

import fw_beasts as B
import fw_humans as H
from fw_sheet import C, bpy
from fw_humans import L_POLE, R_POLE, arc_strip
from mathutils import Euler, Vector

KINDS = ["fw_buffalo", "fw_sheriff"]

BUFFALO = {
    "name": "Le Buffle", "scale": 1.85, "frame": 288, "cam_z": 1.0,
    "withers": 0.86, "hips": 0.70, "length": 1.10,
    "chest": (0.31, 0.35), "rump": (0.23, 0.26),
    "neck": 0.16, "neck_r": 0.17, "head": 0.21, "snout": 0.13, "snout_r": 0.10,
    "leg_r": 0.092, "front_leg": (0.30, 0.26, 0.14), "hind_leg": (0.26, 0.24, 0.16),
    "ears": "round", "mane": False, "tail": "tuft", "collar": None, "teeth": False,
    "head_down": 0.35, "jaw_idle": 0.0, "hooves": True, "dark_legs": True, "heavy": 1.0,
    "dark_snout": True,
    # planche : cuir gris-noir, grandes plaques de bronze rouillé couvrant le dos et les épaules,
    # cornes brun clair recourbées vers l'avant, tête basse
    "mats": {
        "fur": ("pat", [("#585050", "#1a161c", "#80746e"), ("#423a3a", "#121014", "#625856")], 7.0),
        "fur_dark": ("#2e2828", "#0c0a0c", "#4e4646"),
        "belly": ("#4a3e38", "#16101a", "#6a5a50"),
        "muzzle": ("#2a2222", "#0a0606", "#463a38"),
        "plate": ("pat", [("#a0602e", "#3e1c1a", "#d08a48"), ("#5a4a3e", "#1e1618", "#806a58")], 3.0),
        "plate2": ("pat", [("#5a524c", "#1c1a1e", "#867c74"), ("#8a5a32", "#30181a", "#b47a48")], 3.5),
        "rivet": ("#d8b878", "#5a4030", "#fff0c0"),
        "horn": ("#b48a5a", "#4a3028", "#e0b880"),
        "eye": "!#ffa030",
    },
}

HORSE = {
    "name": "Cheval du shérif", "scale": 1.8,
    "withers": 1.00, "hips": 0.98, "length": 1.15,
    "chest": (0.19, 0.24), "rump": (0.19, 0.24),
    "neck": 0.46, "neck_r": 0.11, "head": 0.12, "snout": 0.24, "snout_r": 0.075,
    "leg_r": 0.050, "front_leg": (0.36, 0.34, 0.20), "hind_leg": (0.34, 0.32, 0.24),
    "ears": "pointed", "mane": False, "tail": "horse", "collar": None, "teeth": False,
    "head_down": -0.35, "jaw_idle": 0.0, "hooves": True, "dark_legs": True, "dark_snout": True,
    "mats": {
        "fur": ("pat", [("#8a5232", "#2e1418", "#b8744a"), ("#74432a", "#261014", "#9a6240")], 6.0),
        "fur_dark": ("#1e1412", "#060304", "#3a2a24"),
        "belly": ("#9a6644", "#361c1e", "#c08a5e"),
        "muzzle": ("#3a2a24", "#100a0a", "#5a4438"),
        "eye": "!#ff4a1a",
    },
}

SHERIFF = {
    "name": "Le Shérif Sable-Fou", "scale": 1.30, "head": 1.22, "leg": 0.84, "frame": 320, "cam_dz": 0.40,
    "torso": (1.18, 1.08), "arm": 1.12, "belly": 0.2,
    # planche : chapeau de cuir fauve, visage de métal sombre aux yeux bleus luisants, cape-poncho rouge
    # en lambeaux, armure de métal sombre, ceinturon à boucle de laiton, bras-canon mécanique
    "hat": "boss", "face": "robot", "kerchief": True, "coat": None, "vest": False, "armor": True,
    "brim_r": 0.31,
    "bandolier": None, "weapon": "sheriff", "bracers": True, "idle_crouch": 0.35,
    "mats": {
        "plate": ("pat", [("#4e4c50", "#16161c", "#7a7880"), ("#5a4a40", "#1c1416", "#806a5a")], 3.0),
        "rivet": ("#b89a60", "#4a3828", "#f0d090"),
        "shirt": ("#3a2e2a", "#100c10", "#5a4a42"),
        "pants": ("pat", [("#3a3028", "#120e12", "#56483a"), ("#2e2620", "#0e0a0e", "#4a3c30")], 7.0),
        "vest": ("#1e1816", "#080606", "#3a302a"),
        "coat": ("pat", [("#4a3a30", "#16101a", "#6e584a"), ("#3c2e26", "#120c12", "#5a4638")], 5.0),
        "cape": ("pat", [("#a01e1c", "#3a0812", "#cc3a2c"), ("#7e1616", "#2c060e", "#a42a24")], 4.0),
        "hat": ("#8a5a30", "#2e1818", "#b88048"),
        "hatband": ("#2a1c14", "#0a0606", "#4a3426"),
        "beard": ("#c8c0b0", "#5a5258", "#f0ece4"),
        "bandana": ("#a01e1c", "#3a0812", "#cc3a2c"),
        "boot": ("#1e1614", "#080606", "#3a2c26"),
        "gold": ("#d8a840", "#6a4430", "#ffe490"),
        "mech": ("#4a4a52", "#14141c", "#80808a"),
        "glow": "!#ff7a2a",
        "saddle": ("#5a3420", "#1e0e10", "#80502e"),
        "blanket": ("pat", [("#b82420", "#420a18", "#e2402e"), ("#ece2cc", "#7a7088", "#ffffff")], 5.0),
    },
}


# ============================================================================ Le Buffle
class Buffalo(B.Beast):
    def build_extra(self) -> None:
        A, j = self.A, self.j
        L = A["length"]
        torso, head = j["torso"], j["head"]
        zw = A["withers"] - self.HM
        # bosse + toison sombre sur l'avant (garrot, cou, poitrail)
        self.part("hump", C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, -L * 0.28, zw + 0.12),
                  scale=(A["chest"][0] * 1.05, L * 0.30, 0.24)), "fur", torso)
        self.part("shag", C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, -L * 0.40, zw - 0.02),
                  scale=(A["chest"][0] * 1.18, L * 0.22, A["chest"][1] * 1.1)), "fur", torso)
        for k in range(10):
            a = -1.2 + 2.4 * k / 9
            self.part("tuftFur", C.bm_xform(C.bm_cyl(5, 0.06, 0.0, 0.16),
                      loc=(math.sin(a) * A["chest"][0] * 1.15, -L * 0.42, zw - 0.02 + math.cos(a) * A["chest"][1] * 0.6),
                      rot=(math.pi * 0.85, 0, a * 0.6)), "fur_dark", torso, smooth=False)
        # plaques de tôle rivetées sur le dos (bête de guerre des bandits)
        for k in range(6):
            y = -L * 0.30 + L * 0.13 * k
            t = (y + L * 0.5) / L
            zc = (A["withers"] - self.HM) * (1 - t) + (A["hips"] - self.HM) * t - 0.03
            rx = (A["chest"][0] * (1 - t) + A["rump"][0] * t) * (1.16 if k else 1.20)
            rz = (A["chest"][1] * (1 - t) + A["rump"][1] * t) * (1.08 if k else 1.22)
            if k == 0:
                zc += 0.06
            band = arc_strip(1.0, math.pi - 1.35, math.pi + 1.35, -0.075, 0.075, n=14)
            C.bm_xform(band, rot=(math.pi / 2, 0, 0))
            C.bm_xform(band, loc=(0, y, zc), scale=(rx, 1.0, rz), rot=(0.12, 0, 0))
            self.part("plate", band, "plate" if k % 2 == 0 else "plate2", torso, thick=0.03)
            for sx in (1, -1):
                for a in (0.5, 1.0):
                    self.part("rivet", C.bm_xform(C.bm_sphere(6, 4, 0.026),
                              loc=(rx * math.sin(a) * sx * 1.02, y - 0.05, zc + rz * math.cos(a) * 1.02)), "rivet", torso)
        # arête dorsale de plaques sombres + panneaux rouille sur les flancs (carapace de la planche)
        for k in range(7):
            t = 0.12 + 0.11 * k
            y = -L * 0.5 + L * t
            zc = (A["withers"] - self.HM) * (1 - t) + (A["hips"] - self.HM) * t - 0.03
            rz = (A["chest"][1] * (1 - t) + A["rump"][1] * t) * 1.14 + (0.10 if k < 2 else 0.0)
            self.part("ridge", C.bm_xform(C.bm_box(0.12, 0.13, 0.05, bevel=0.015), loc=(0, y, zc + rz),
                      rot=(0.15, 0, 0)), "plate2", torso)
        for sx in (1, -1):
            for k in range(3):
                t = 0.30 + 0.20 * k
                y = -L * 0.5 + L * t
                zc = (A["withers"] - self.HM) * (1 - t) + (A["hips"] - self.HM) * t - 0.03
                rx = (A["chest"][0] * (1 - t) + A["rump"][0] * t) * 1.22
                self.part("flankPanel", C.bm_xform(C.bm_box(0.03, 0.17, 0.15, bevel=0.012),
                          loc=(rx * sx, y, zc + 0.04), rot=(0, 0.35 * sx, 0)), "plate", torso)
        # épaulières de bronze sur les épaules avant
        for sx in (1, -1):
            sp = C.bm_sphere(14, 8, 1.0)
            for v in sp.verts:
                if v.co.x * sx < -0.2:
                    v.co.x = -0.2 * sx
            C.bm_xform(sp, loc=(A["chest"][0] * 0.85 * sx, -L * 0.36, zw - 0.10),
                       scale=(0.13, 0.20, 0.20))
            self.part("shoulderPlate", sp, "plate", torso)
        # tête : cornes recourbées (vers l'extérieur puis le haut), front laineux, barbe
        hr = A["head"]
        for sx in (1, -1):
            pts = C.bezier((hr * 0.55 * sx, -hr * 0.05, hr * 0.55), (hr * 1.9 * sx, 0.1, hr * 0.30),
                           (hr * 2.3 * sx, -hr * 1.0, hr * 0.9), (hr * 1.5 * sx, -hr * 1.5, hr * 1.5), 8)
            self.part("horn", C.bm_tube(pts, [0.10, 0.095, 0.085, 0.07, 0.055, 0.04, 0.022, 0.004], seg=10),
                      "horn", head)
            self.part("hornBase", C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(hr * 0.75 * sx, -hr * 0.05, hr * 0.52),
                      scale=(0.10, 0.10, 0.09)), "fur_dark", head)
        self.part("brow", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, -hr * 0.25, hr * 0.62),
                  scale=(hr * 1.05, hr * 0.75, hr * 0.55)), "fur", head)
        self.part("beard", C.bm_xform(C.bm_cyl(10, 0.09, 0.02, 0.22), loc=(0, -hr * 0.8, -hr * 0.85),
                  rot=(0.2, 0, 0)), "fur_dark", head)
        self.part("noseRing", C.bm_xform(C.bm_torus(14, 5, 0.045, 0.012), loc=(0, -hr * 0.55 - A["snout"] - 0.02,
                  -hr * 0.42), rot=(0, math.pi / 2, 0)), "brass", head)

    def pose_attack(self, i: int, n: int) -> None:
        """Coup de corne : tête baissée, sabot qui gratte, puis balayage vers le haut."""
        self.rest()
        j, A = self.j, self.A
        sc = A["scale"]
        by = (0.02, 0.05, 0.06, -0.16, -0.14, -0.05)[i]
        j["body"].location = (0, by * sc, 0)
        j["torso"].location.z = self.HM + (-0.02, -0.05, -0.06, 0.02, 0.0, -0.01)[i]
        j["torso"].rotation_euler = ((0.04, 0.10, 0.12, -0.10, -0.04, 0.02)[i], 0, 0)
        j["neck"].rotation_euler = (A["head_down"] + (0.25, 0.45, 0.50, -0.55, -0.40, 0.10)[i], 0,
                                    (0.0, 0.0, 0.0, 0.25, 0.3, 0.0)[i])
        j["head"].rotation_euler = ((0.15, 0.30, 0.32, -0.45, -0.35, 0.0)[i], 0, 0)
        j["tail"].rotation_euler = ((-0.2, -0.5, -0.6, -0.9, -0.6, -0.2)[i], 0, 0)
        paw = (0.0, -0.45, 0.2, 0.0, 0.0, 0.0)[i]
        self.leg("FL", -0.1 + paw, 0.3 + abs(paw) * 1.2, 0.2 * abs(paw))
        self.leg("FR", (-0.05, 0.1, 0.12, -0.6, -0.45, -0.1)[i], (0.2, 0.3, 0.35, 0.1, 0.1, 0.1)[i], 0)
        for side in ("L", "R"):
            self.leg("H" + side, (0.0, 0.1, 0.12, 0.5, 0.35, 0.05)[i], (0.2, 0.35, 0.4, 0.0, 0.1, 0.1)[i], -0.2)

    def muzzle_world(self) -> Vector:
        bpy.context.view_layer.update()
        hr = self.A["head"]
        return self.j["head"].matrix_world @ Vector((hr * 1.5, -hr * 1.5, hr * 1.5))


# ============================================================================ Le Shérif
class Horse(B.Beast):
    def build_tail(self, tail) -> None:
        self.part("tailMesh", C.bm_tube([(0, 0, 0), (0, 0.10, -0.08), (0, 0.18, -0.30), (0, 0.20, -0.55)],
                                        [0.05, 0.07, 0.06, 0.015], seg=8, flat=0.6), "fur_dark", tail)

    def build_extra(self) -> None:
        A, j = self.A, self.j
        L = A["length"]
        neck, torso = j["neck"], j["torso"]
        nl = A["neck"]
        # crinière (le long du cou)
        self.part("mane", C.bm_tube([(0, 0.06, A["neck_r"] * 0.9), (0, -nl * 0.45, nl * 0.30 + A["neck_r"] * 0.9),
                                     (0, -nl * 0.85, nl * 0.55 + A["neck_r"] * 0.7)], [0.05, 0.06, 0.04], seg=8,
                                    flat=0.45, up=(1, 0, 0)), "fur_dark", neck)
        zw = A["withers"] - self.HM
        # selle + couverture rouge et blanche
        self.part("blanket", C.bm_xform(arc_strip(A["chest"][0] * 1.05, -1.55, 1.55, -0.20, 0.20, n=14),
                  loc=(0, -L * 0.05, zw + A["chest"][1] * 0.70), rot=(math.pi / 2, 0, 0)), "blanket", torso, thick=0.02)
        self.part("saddle", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, -L * 0.05, zw + A["chest"][1] * 0.98),
                  scale=(0.15, 0.20, 0.06)), "saddle", torso)
        self.part("horn", C.bm_xform(C.bm_cyl(8, 0.025, 0.035, 0.10), loc=(0, -L * 0.05 - 0.17,
                  zw + A["chest"][1] * 1.05)), "saddle", torso)
        for sx in (1, -1):
            self.part("stirrup", C.bm_xform(C.bm_torus(10, 4, 0.04, 0.01), loc=(0.22 * sx, -L * 0.05, zw - 0.15),
                      rot=(0, math.pi / 2, 0)), "metal", torso)
        # bride
        head = j["head"]
        hr = A["head"]
        self.part("bridle", C.bm_xform(C.bm_torus(14, 4, A["snout_r"] * 1.12, 0.014),
                  loc=(0, -hr * 0.55 - A["snout"] * 0.5, -hr * 0.12), rot=(math.pi / 2, 0, 0)), "saddle", head)

    def saddle_world_z(self) -> float:
        A = self.A
        return (A["withers"] + A["chest"][1] * 0.98 + 0.05) * A["scale"]


class Sheriff(H.Human):
    def __init__(self, kind: str) -> None:
        super().__init__(kind, SHERIFF)
        self.mounted = False

    def anims(self) -> dict:
        a = dict(H.ANIMS_BASE)
        a["charge"] = (8, 16, True)
        return a

    def apply_mats(self) -> None:
        super().apply_mats()

    def build_extra(self) -> None:
        j = self.j
        spine = j["spine"]
        tw = self.TW
        # cape rouge en lambeaux, nouée aux épaules, jusqu'aux mollets
        cape = arc_strip(0.25 * tw + 0.05, math.pi - 1.35, math.pi + 1.35, -0.62, 0.44, n=18, flare=0.20)
        for v in cape.verts:
            if v.co.z < -0.5:
                k = round((math.atan2(v.co.x, -v.co.y) + math.pi) * 4.0)
                v.co.z += 0.10 * (k % 2)
        self.part("cape", cape, "cape", spine, thick=0.016)
        j["cape"] = spine
        self.part("capeCollar", C.bm_xform(C.bm_torus(18, 6, 0.15, 0.05), loc=(0, 0.02, 0.44), scale=(1.1, 1.0, 0.7)),
                  "cape", spine)
        # poncho rouge en lambeaux sur les épaules (ouvert devant, bord déchiqueté)
        pon = arc_strip(0.19, 0.50, 2 * math.pi - 0.50, 0.14, 0.47, n=28, flare=0.27)
        for v in pon.verts:
            if v.co.z < 0.3:
                k = round((math.atan2(v.co.x, -v.co.y) + math.pi) * 5.0)
                v.co.z += (0.0, 0.07, 0.02, 0.10, 0.04)[k % 5]
        C.bm_xform(pon, scale=(tw * 1.05, self.TD, 1.0))
        self.part("poncho", pon, "cape", spine, thick=0.016)
        for sx in (1, -1):
            self.part("clasp", C.bm_xform(C.bm_cyl(10, 0.03, 0.03, 0.015), loc=(0.12 * sx, -0.13, 0.42),
                      rot=(1.3, 0, 0)), "gold", spine)
        # étoile de shérif (ternie) sur le gilet
        star = C.bm_cyl(5, 0.05, 0.05, 0.012)
        C.bm_xform(star, loc=(0.11 * tw, -0.175 * self.TD, 0.30), rot=(1.45, 0, 0))
        self.part("star", star, "gold", spine, smooth=False)
        # bras gauche mécanique : canon le long de l'avant-bras (la main est remplacée)
        fa = j["faL"]
        for ob, key in list(self.parts):
            if ob.name.startswith(("handL", "cuffL", "farmL")):
                ob.hide_render = True
        self.part("mechFore", C.bm_xform(C.bm_cyl(14, 0.095, 0.11, 0.26), loc=(0, 0, -0.10)), "mech", fa)
        self.part("cannon", C.bm_xform(C.bm_cyl(14, 0.09, 0.08, 0.40), loc=(0, 0, -0.38)), "metal_dark", fa)
        self.part("cannonBore", C.bm_xform(C.bm_cyl(12, 0.055, 0.055, 0.02), loc=(0, 0, -0.585)), "glow", fa, nofs=True)
        for z in (-0.02, -0.22, -0.50):
            self.part("cannonRing", C.bm_xform(C.bm_cyl(14, 0.12, 0.12, 0.04), loc=(0, 0, z)), "brass", fa)
        self.part("pipe", C.bm_tube([(0.07, 0.03, 0.02), (0.10, 0.06, -0.12), (0.08, 0.05, -0.30)],
                                    [0.018, 0.018, 0.018], seg=6), "brass", fa)
        self.part("mechShoulder", C.bm_xform(C.bm_sphere(12, 8, 0.13), loc=(0.01, 0, 0.0)), "mech", j["uaL"])
        for k in range(4):
            a = k * math.pi / 2
            self.part("bolt", C.bm_xform(C.bm_sphere(6, 4, 0.022), loc=(0.13 * math.cos(a) * 0.9, 0.13 * math.sin(a) * 0.9,
                      0.03)), "brass", j["uaL"])
        # cheval (montré seulement pendant la charge)
        self.horse = Horse("fw_sheriff_horse", HORSE)
        self.horse.j["root"].parent = j["root"]
        self.horse_parts = [ob for ob, _k in self.horse.parts]
        self.show_horse(False)

    def show_horse(self, on: bool) -> None:
        for ob in getattr(self, "horse_parts", []):
            ob.hide_render = not on
            ob.hide_viewport = not on

    def build_weapons(self, spine) -> None:
        g = self.gun_group("gunR", spine)
        for part, bm, key in (
            ("barrel", C.bm_xform(C.bm_cyl(10, 0.022, 0.022, 0.26), loc=(0, -0.16, 0.04), rot=(math.pi / 2, 0, 0)), "metal"),
            ("cyl", C.bm_xform(C.bm_cyl(10, 0.04, 0.04, 0.08), loc=(0, -0.02, 0.035), rot=(math.pi / 2, 0, 0)), "gold"),
            ("frame", C.bm_xform(C.bm_box(0.034, 0.11, 0.055, bevel=0.008), loc=(0, -0.03, 0.03)), "gold"),
            ("grip", C.bm_xform(C.bm_box(0.038, 0.055, 0.12, bevel=0.012), loc=(0, 0.03, -0.03), rot=(-0.45, 0, 0)), "wood"),
        ):
            self.part(part, bm, key, g, grp="gunR")
        self.part("holster", C.bm_xform(C.bm_box(0.07, 0.11, 0.18, bevel=0.02), loc=(-0.22 * self.TW, -0.02, -0.06),
                  rot=(0.15, 0, 0)), "belt", self.j["pelvis"])

    def hold(self, aim: float = 0.0, dz: float = 0.0, recoil: float = 0.0, swing_l: float | None = None,
             cannon: float | None = None, recoil_c: float = 0.0) -> None:
        low = Vector((-0.17, -0.14, 0.02 + dz))
        up = Vector((-0.10, -0.46, 0.22 + dz))
        hand = low.lerp(up, aim) + Vector((0, 0.06 * recoil, 0.08 * recoil))
        self.place("gunR", hand, (1.1 * (1 - aim) - 0.6 * recoil, 0, -0.05))
        self.arm_ik("R", hand, R_POLE)
        c = aim if cannon is None else cannon
        lo = Vector((0.20, -0.10, -0.02 + dz))
        hi = Vector((0.14, -0.42, 0.26 + dz))
        self.arm_ik("L", lo.lerp(hi, c) + Vector((0, 0.08 * recoil_c, 0.05 * recoil_c)), L_POLE)

    def pose_idle(self, i: int, n: int) -> None:
        """Garde : visage relevé (yeux bleus visibles sous le chapeau), bras-canon pointé devant."""
        super().pose_idle(i, n)
        b = math.sin(2 * math.pi * i / n)
        self.j["head"].rotation_euler = (-0.42, 0, 0.0)
        self.hold(aim=0.0, dz=0.012 * b, cannon=0.55)

    def pose_attack(self, i: int, n: int) -> None:
        """Tir de revolver + coup de canon (le canon part une image après le revolver)."""
        self.rest()
        aim = (0.4, 0.9, 1.0, 1.0, 1.0, 0.9)[i]
        rr = (0, 0, 0, 1.0, 0.4, 0.1)[i]
        rc = (0, 0, 0, 0.2, 1.0, 0.3)[i]
        self._aim_body(lean=0.05, twist=0.08)
        self.hold(aim=aim, recoil=rr, cannon=(0.3, 0.8, 1.0, 1.0, 1.0, 0.8)[i], recoil_c=rc)

    def drop_weapons(self, hl: Vector, hr: Vector, u: float) -> None:
        self.place("gunR", hr, (0.6, 0.0, 0.6 * u))

    def rest(self) -> None:
        super().rest()
        self.show_horse(False)

    def pose_charge(self, i: int, n: int) -> None:
        """À cheval, au galop : le shérif penché en avant, revolver pointé."""
        self.rest()
        self.show_horse(True)
        hz = self.horse
        hz.pose_run(i, n)
        j = self.j
        sc = self.A["scale"]
        p = 2 * math.pi * i / n
        bob = hz.j["torso"].location.z - hz.HM
        seat = hz.saddle_world_z() + bob * hz.A["scale"]
        j["body"].location = (0, -0.06 * hz.A["scale"], seat - self.PZ * sc + 0.02)
        # jambes à califourchon
        self.legs((-1.25, -0.45, 0), (-1.25, 0.45, 0), 1.45, 1.45)
        j["spine"].rotation_euler = (0.32 + 0.04 * math.sin(p), 0, 0)
        j["neck"].rotation_euler = (-0.30, 0, 0)
        self.hold(aim=1.0, cannon=0.35)

    def muzzle_world(self) -> Vector:
        bpy.context.view_layer.update()
        return self.weapons["gunR"].matrix_world @ Vector((0, -0.30, 0.04))


def make(kind: str):
    if kind == "fw_buffalo":
        return Buffalo(kind, BUFFALO)
    if kind == "fw_sheriff":
        return Sheriff(kind)
    raise KeyError(kind)
