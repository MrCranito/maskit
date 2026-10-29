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
    "chest": (0.27, 0.33), "rump": (0.20, 0.24),
    "neck": 0.16, "neck_r": 0.17, "head": 0.21, "snout": 0.13, "snout_r": 0.10,
    "leg_r": 0.075, "front_leg": (0.30, 0.26, 0.14), "hind_leg": (0.26, 0.24, 0.16),
    "ears": "round", "mane": False, "tail": "tuft", "collar": None, "teeth": False,
    "head_down": 0.35, "jaw_idle": 0.0, "hooves": True, "dark_legs": True, "heavy": 1.0,
    "dark_snout": True,
    "mats": {
        "fur": ("pat", [("#6a4430", "#24121a", "#8e6044"), ("#583826", "#1c0e14", "#74503a")], 6.0),
        "fur_dark": ("#2e1e18", "#0c0608", "#4a3426"),
        "belly": ("#7a5238", "#2e1a1e", "#9a6c4a"),
        "muzzle": ("#2a1c18", "#0a0606", "#44302a"),
        "plate": ("pat", [("#8a8478", "#2c2a36", "#c8c0b0"), ("#7a5a42", "#2c1c22", "#a07a58")], 3.0),
        "rivet": ("#c8b890", "#4a4038", "#fff0c8"),
        "eye": "!#ff5a20",
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
    "name": "Le Shérif Sable-Fou", "scale": 1.30, "head": 1.32, "leg": 0.84, "frame": 320, "cam_dz": 0.40,
    "torso": (1.14, 1.06), "arm": 1.10, "belly": 0.3,
    "hat": "boss", "face": "mustache", "kerchief": True, "coat": "duster", "vest": True,
    "bandolier": "cartridges", "weapon": "sheriff", "bracers": True,
    "mats": {
        "shirt": ("#3a2e2a", "#100c10", "#5a4a42"),
        "pants": ("pat", [("#3a3028", "#120e12", "#56483a"), ("#2e2620", "#0e0a0e", "#4a3c30")], 7.0),
        "vest": ("#1e1816", "#080606", "#3a302a"),
        "coat": ("pat", [("#4a3a30", "#16101a", "#6e584a"), ("#3c2e26", "#120c12", "#5a4638")], 5.0),
        "cape": ("pat", [("#b82420", "#420a18", "#e2402e"), ("#9a1c1a", "#360814", "#c4342a")], 4.0),
        "hat": ("#3a2a20", "#100a0c", "#5e4636"),
        "hatband": ("#d8a840", "#6a4430", "#ffe490"),
        "beard": ("#c8c0b0", "#5a5258", "#f0ece4"),
        "bandana": ("#b82420", "#420a18", "#e2402e"),
        "boot": ("#1e1614", "#080606", "#3a2c26"),
        "gold": ("#d8a840", "#6a4430", "#ffe490"),
        "mech": ("#5a5a62", "#1a1a24", "#9a9aa4"),
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
                  scale=(A["chest"][0] * 1.05, L * 0.30, 0.24)), "fur_dark", torso)
        self.part("shag", C.bm_xform(C.bm_sphere(16, 10, 1.0), loc=(0, -L * 0.40, zw - 0.02),
                  scale=(A["chest"][0] * 1.18, L * 0.22, A["chest"][1] * 1.1)), "fur_dark", torso)
        for k in range(10):
            a = -1.2 + 2.4 * k / 9
            self.part("tuftFur", C.bm_xform(C.bm_cyl(5, 0.06, 0.0, 0.16),
                      loc=(math.sin(a) * A["chest"][0] * 1.15, -L * 0.42, zw - 0.02 + math.cos(a) * A["chest"][1] * 0.6),
                      rot=(math.pi * 0.85, 0, a * 0.6)), "fur_dark", torso, smooth=False)
        # plaques de tôle rivetées sur le dos (bête de guerre des bandits)
        for k in range(3):
            y = -L * 0.10 + L * 0.17 * k
            t = (y + L * 0.5) / L
            zc = (A["withers"] - self.HM) * (1 - t) + (A["hips"] - self.HM) * t - 0.03
            rx = (A["chest"][0] * (1 - t) + A["rump"][0] * t) * 1.08
            rz = (A["chest"][1] * (1 - t) + A["rump"][1] * t) * 1.02
            band = arc_strip(1.0, math.pi - 1.15, math.pi + 1.15, -0.08, 0.08, n=12)
            C.bm_xform(band, rot=(math.pi / 2, 0, 0))
            C.bm_xform(band, loc=(0, y, zc), scale=(rx, 1.0, rz))
            self.part("plate", band, "plate", torso, thick=0.025)
            for sx in (1, -1):
                self.part("rivet", C.bm_xform(C.bm_sphere(6, 4, 0.028),
                          loc=(rx * 0.55 * sx, y, zc + rz * 0.86)), "rivet", torso)
        # tête : cornes recourbées (vers l'extérieur puis le haut), front laineux, barbe
        hr = A["head"]
        for sx in (1, -1):
            pts = C.bezier((hr * 0.55 * sx, -hr * 0.05, hr * 0.55), (hr * 2.0 * sx, 0.0, hr * 0.40),
                           (hr * 2.5 * sx, -hr * 0.5, hr * 1.3), (hr * 1.9 * sx, -hr * 0.8, hr * 1.9), 8)
            self.part("horn", C.bm_tube(pts, [0.09, 0.085, 0.075, 0.065, 0.05, 0.036, 0.02, 0.004], seg=10),
                      "horn", head)
        self.part("brow", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, -hr * 0.25, hr * 0.62),
                  scale=(hr * 1.05, hr * 0.75, hr * 0.55)), "fur_dark", head)
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
        return self.j["head"].matrix_world @ Vector((hr * 1.9, -hr * 0.8, hr * 1.9))


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
