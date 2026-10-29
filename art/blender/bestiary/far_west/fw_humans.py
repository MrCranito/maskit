"""Bestiaire Far West : humanoïdes (bandit, pillard, tireur d'élite, robuste ; élites et boss).
Modèle scripté dérivé du hors-la-loi de référence (art/blender/build_enemies.py) : mêmes
proportions héroïques, mêmes matériaux toon, même rig (joints vides + IK des bras à 2 segments).

Repère du modèle : le personnage regarde vers -Y (vers la caméra pour la direction « s »),
+X = sa gauche, Z vers le haut. Armes : groupes parentés à la colonne, placés par `place()`,
les mains suivent par IK.
"""
from __future__ import annotations

import math
import random

import fw_sheet as S
from fw_sheet import C, bpy
from mathutils import Euler, Vector

L_UP, L_LOW = 0.20, 0.225
SHOULDER = {"L": Vector((0.245, 0.0, 0.33)), "R": Vector((-0.245, 0.0, 0.33))}
R_POLE, L_POLE = Vector((-0.8, 0.4, -0.6)), Vector((0.8, 0.5, -0.6))

ANIMS_BASE = {
    "idle": (6, 7, True),
    "run": (8, 14, True),
    "attack": (6, 12, False),
    "hit": (3, 14, False),
    "death": (8, 12, False),
}

COMMON_MATS = {
    "skin": ("#c88c64", "#6e4048", "#eeb48a"),
    "eye": ("#1a1418", None, None),
    "brow": ("#2a1c18", None, None),
    "metal": ("#8a8c92", "#2c2e3a", "#d8dae0"),
    "metal_dark": ("#3a3a40", "#121218", "#64646c"),
    "wood": ("#7a4a2a", "#30182a", "#a8703e"),
    "brass": ("#c09040", "#5a3828", "#f0d080"),
    "lens": ("#5a8ab0", "#1e2a4a", "#a8d0f0"),
    "belt": ("#2a1e18", "#0c0808", "#4a3428"),
    "strap": ("#4a3424", "#1a0e10", "#6a4c34"),
    "shell": ("#d0a040", "#5a3a28", "#f8d478"),
    "bandana": ("#c0261e", "#4a0c1a", "#ec4a34"),
    "glow": "!#ff6a2a",
}

# Archétypes. Clés : scale, head, leg, torso (largeur, profondeur), arm, belly, hat, face,
# kerchief (foulard noué au cou), coat, vest, bandolier, weapon, armor, bracers, mats.
ARCH: dict[str, dict] = {
    "fw_bandit": {
        "name": "Bandit", "scale": 1.0, "head": 1.40, "leg": 0.82,
        "torso": (0.94, 0.94), "arm": 0.95, "belly": 0.0,
        "hat": "cowboy_low", "face": "bandana", "kerchief": False, "coat": None, "vest": True,
        "bandolier": "cartridges", "weapon": "rifle",
        "mats": {
            "shirt": ("pat", [("#cdbb98", "#6a5a66", "#efdcb4"), ("#a89676", "#4c4250", "#c8b48e")], 9.0),
            "pants": ("pat", [("#5a4636", "#221a24", "#7e6248"), ("#4a3a2e", "#1a1420", "#6a5440")], 8.0),
            "vest": ("pat", [("#7a4428", "#2a1420", "#a0603c"), ("#603620", "#20101a", "#86502e")], 10.0),
            "hat": ("#6a4a30", "#22141a", "#94704a"),
            "hatband": ("#2a1a14", "#0c0606", "#4a3226"),
            "boot": ("#3e2a1e", "#140c12", "#604230"),
        },
    },
    "fw_raider": {
        "name": "Pillard", "scale": 1.07, "head": 1.36, "leg": 0.80,
        "torso": (1.10, 1.04), "arm": 1.12, "belly": 0.35,
        "hat": "cowboy_low", "face": "beard", "kerchief": True, "coat": None, "vest": True,
        "bandolier": "cartridges", "weapon": "axe", "bracers": True, "bare_arms": True,
        "mats": {
            "shirt": ("pat", [("#8e5a3a", "#3a1c22", "#b47a52"), ("#7a4c30", "#2e161c", "#9a6844")], 8.0),
            "pants": ("pat", [("#4a3e30", "#1a1416", "#6a5a46"), ("#3c3228", "#141012", "#584a3a")], 7.0),
            "vest": ("pat", [("#4a2c1c", "#1a0c10", "#6e4428"), ("#3c2416", "#14080c", "#5a3820")], 9.0),
            "hat": ("#4a3424", "#180e12", "#6e5038"),
            "hatband": ("#b82a22", "#46101c", "#e04a38"),
            "beard": ("#4a2a18", "#180a0c", "#6a4026"),
            "boot": ("#2e2018", "#0e0808", "#4e3828"),
            "axehead": ("#7a7c84", "#262834", "#c8cad2"),
        },
    },
    "fw_sharpshooter": {
        "name": "Tireur d'élite", "scale": 0.98, "head": 1.40, "leg": 0.84,
        "torso": (0.90, 0.90), "arm": 0.92, "belly": 0.0,
        "hat": "wide", "face": "scarf", "kerchief": False, "coat": "duster", "vest": False,
        "bandolier": "cartridges", "weapon": "sniper", "idle_kneel": True,
        "mats": {
            "shirt": ("#7a7466", "#2e2c32", "#a49c88"),
            "pants": ("#4a3e30", "#1a1416", "#6a5a46"),
            "coat": ("pat", [("#9a7c52", "#3e302e", "#c4a272"), ("#806646", "#322628", "#a88a60")], 5.0),
            "hat": ("#5a4636", "#1e1418", "#80664e"),
            "hatband": ("#2a1e18", "#0c0808", "#4a3428"),
            "bandana": ("#6a5a4a", "#241c1e", "#8e7c66"),
            "boot": ("#3a2a1e", "#120c0e", "#5a4230"),
        },
    },
    "fw_bruiser": {
        "name": "Robuste", "scale": 1.20, "head": 1.28, "leg": 0.78,
        "torso": (1.40, 1.26), "arm": 1.34, "belly": 1.0,
        "hat": "kettle", "face": "beard", "kerchief": False, "coat": None, "vest": False,
        "bandolier": None, "weapon": "shield_mace", "armor": True, "bracers": True,
        "mats": {
            "shirt": ("pat", [("#6a3a28", "#28121a", "#8e543a"), ("#5a3022", "#200e16", "#7a4632")], 7.0),
            "pants": ("pat", [("#4a4034", "#1a1618", "#6a5c4a"), ("#3a3228", "#141014", "#564a3c")], 7.0),
            "plate": ("pat", [("#8a8478", "#2c2a36", "#c8c0b0"), ("#7a5a42", "#2c1c22", "#a07a58")], 3.0),
            "rivet": ("#c8b890", "#4a4038", "#fff0c8"),
            "hat": ("#6a6660", "#22222c", "#a8a49a"),
            "hatband": ("#3a2a1e", "#120c0c", "#5a4230"),
            "beard": ("#3a2418", "#140a0c", "#5a3a26"),
            "boot": ("#2e2018", "#0e0808", "#4e3828"),
            "shieldwood": ("pat", [("#6a4428", "#261420", "#8e5e38"), ("#5a3a22", "#1e1018", "#7a5030")], 6.0),
        },
    },
    # --- élite : Le Déserteur (bandit d'élite : rafales, esquive, renforts) ---
    "fw_deserter": {
        "name": "Le Déserteur", "scale": 1.12, "head": 1.36, "leg": 0.84,
        "torso": (1.02, 0.98), "arm": 1.02, "belly": 0.0,
        "hat": "cowboy_tall", "face": "bandana", "kerchief": True, "coat": "duster", "vest": True,
        "bandolier": "cartridges", "weapon": "burst_rifle", "bracers": True, "run_lean": 0.06,
        "mats": {
            "shirt": ("pat", [("#5a4a3a", "#201820", "#7e6852"), ("#4a3c30", "#18121a", "#6a5644")], 8.0),
            "pants": ("pat", [("#3a3028", "#120e12", "#56483a"), ("#2e2620", "#0e0a0e", "#4a3c30")], 7.0),
            "vest": ("#2a1e18", "#0c0808", "#4a3428"),
            "coat": ("pat", [("#6a4430", "#26141a", "#94644a"), ("#58382a", "#1e1016", "#7a523c")], 5.0),
            "hat": ("#2e221c", "#0e0a0c", "#4e3c30"),
            "hatband": ("#c09040", "#5a3828", "#f0d080"),
            "bandana": ("#d02a20", "#4c0c18", "#f85a40"),
            "boot": ("#1e1614", "#080606", "#3a2c26"),
        },
    },
}


def joint(name: str, parent, loc) -> bpy.types.Object:
    e = C.empty(name, loc, parent)
    e.rotation_mode = "XYZ"
    return e


def arc_strip(r, a0, a1, z0, z1, n=14, cy=0.0, flare=0.0, sx=1.0):
    secs = []
    for i in range(n):
        a = a0 + (a1 - a0) * i / (n - 1)
        s, c = math.sin(a), -math.cos(a)
        rb = r + flare
        secs.append([(rb * s * sx, cy + rb * c, z0), (r * s * sx, cy + r * c, z1)])
    return C.bm_loft(secs, closed=False)


def brim(r_in, r_out, curl=0.0, n=36, front_dip=0.0, z=0.0, sy=1.0):
    secs = []
    for k in range(4):
        t = k / 3
        r = r_in + (r_out - r_in) * t
        row = []
        for i in range(n):
            a = 2 * math.pi * i / n
            x, y = r * math.sin(a), -r * math.cos(a) * sy
            side = abs(math.sin(a))
            zz = z + curl * (t ** 2) * side ** 2 - front_dip * t * max(0.0, math.cos(a)) ** 2 \
                - front_dip * 0.6 * t * max(0.0, -math.cos(a)) ** 2
            row.append((x, y, zz))
        secs.append(row)
    return C.bm_loft(secs, cap_start=False, cap_end=False)


def corpse_twist(dir_ang_deg: float) -> float:
    """Vrille (rad) pendant la chute : cadavre couché en travers de l'écran (±20°)."""
    best = None
    for target in (20.0, 160.0, -20.0, -160.0):
        tau = (target - (dir_ang_deg + 90.0) + 180.0) % 360.0 - 180.0
        if best is None or abs(tau) < abs(best):
            best = tau
    return math.radians(best)


class Human:
    frame = 192
    outline_px = 4.6

    def __init__(self, kind: str, spec: dict | None = None) -> None:
        self.kind = kind
        self.A = spec if spec is not None else ARCH[kind]
        self.name = self.A["name"]
        self.dir_ang = 0.0
        self.j: dict[str, bpy.types.Object] = {}
        self.parts: list[tuple[bpy.types.Object, str]] = []
        self.grp: dict[str, list[bpy.types.Object]] = {}
        self.ph = C.toon("_ph_" + kind, "#ff00ff")
        self.rng = random.Random(11)
        self.LEG = self.A["leg"]
        self.PZ = 0.80 - 0.77 * (1 - self.LEG)
        self.HS = self.A["head"]
        self.TW, self.TD = self.A["torso"]
        self.weapons: dict[str, bpy.types.Object] = {}
        self.frame = self.A.get("frame", 192)
        self.cam_z = 0.86 + (0.14 if self.A["scale"] > 1.1 else 0.0) + self.A.get("cam_dz", 0.0)
        self.build()
        self.apply_mats()

    def anims(self) -> dict:
        return dict(ANIMS_BASE)

    # ------------------------------------------------------------------ outils
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
        spec.update(self.A["mats"])
        mats = {}
        for key, sp in spec.items():
            name = "%s_%s" % (self.kind, key)
            if isinstance(sp, str) and sp.startswith("!"):
                mats[key] = C.toon(name, sp[1:], emit=1.6)
            elif sp[0] == "pat":
                mats[key] = C.toon_pattern(name, sp[1], scale=sp[2], thresholds=(0.55,), rim=0.22)
            elif key in ("eye", "brow"):
                mats[key] = C.toon(name, sp[0], sp[1], sp[2], rim=0.0, band=0.25)
            else:
                mats[key] = C.toon(name, sp[0], sp[1], sp[2], rim=0.24)
        for ob, key in self.parts:
            ob.data.materials[0] = mats.get(key, mats.get("shirt"))

    # ------------------------------------------------------------------ construction
    def build(self) -> None:
        j = self.j
        A = self.A
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["body"] = body = joint("body", root, (0, 0, 0))
        body.scale = (A["scale"],) * 3
        j["pelvis"] = pelvis = joint("pelvis", body, (0, 0, self.PZ))
        j["spine"] = spine = joint("spine", pelvis, (0, 0, 0.08))
        j["neck"] = neck = joint("neck", spine, (0, 0, 0.45))
        j["head"] = head = joint("head", neck, (0, 0, 0.0))
        head.scale = (self.HS,) * 3
        self.build_legs(pelvis)
        self.build_torso(pelvis, spine)
        self.build_arms(spine)
        self.build_head(head)
        self.build_hat(head)
        self.build_weapons(spine)
        self.build_extra()

    def build_extra(self) -> None:
        """Accessoires propres (élites, boss) : à surcharger."""

    def build_legs(self, pelvis) -> None:
        j, LEG = self.j, self.LEG
        bw = 1.0 + 0.12 * self.A["belly"]
        for side, sx in (("L", 1), ("R", -1)):
            hip = j["hip" + side] = joint("hip" + side, pelvis, (0.115 * sx * bw, 0, -0.02))
            knee = j["knee" + side] = joint("knee" + side, hip, (0, 0, -0.36 * LEG))
            self.part("thigh" + side, C.bm_xform(C.bm_cyl(12, 0.118 * bw, 0.098 * bw, 0.38),
                      loc=(0, 0, -0.17), scale=(1, 1, LEG)), "pants", hip)
            self.part("shin" + side, C.bm_xform(C.bm_cyl(12, 0.096 * bw, 0.086 * bw, 0.22 * LEG),
                      loc=(0, 0, LEG * -0.10)), "pants", knee)
            self.part("bootShaft" + side, C.bm_xform(C.bm_cyl(12, 0.104, 0.112, 0.24 * LEG),
                      loc=(0, 0, LEG * -0.25)), "boot", knee)
            fz = -0.345 + 0.41 * (1 - LEG)
            foot = C.bm_sphere(12, 8, 1.0)
            C.bm_xform(foot, loc=(0, -0.07, fz + 0.005), scale=(0.085, 0.16, 0.06))
            self.part("foot" + side, foot, "boot", knee)
            self.part("heel" + side, C.bm_xform(C.bm_box(0.08, 0.06, 0.06, bevel=0.01),
                      loc=(0, 0.05, fz - 0.02)), "boot", knee)
            self.part("spur" + side, C.bm_xform(C.bm_torus(10, 4, 0.03, 0.008),
                      loc=(0.0, 0.10, fz + 0.01), rot=(0, math.pi / 2, 0)), "metal", knee)
            if self.A.get("armor"):
                # genouillère + jambière de tôle
                self.part("kneePlate" + side, C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0, -0.07, 0.0),
                          scale=(0.085, 0.05, 0.08)), "plate", knee)
                self.part("greave" + side, C.bm_xform(arc_strip(0.115, -1.1, 1.1, -0.28 * LEG, -0.05, n=8),
                          scale=(1, 1, 1)), "plate", knee, thick=0.012)

    def build_torso(self, pelvis, spine) -> None:
        A = self.A
        tw, td, belly = self.TW, self.TD, A["belly"]
        self.part("hips", C.bm_xform(C.bm_sphere(14, 8, 1.0), loc=(0, 0, -0.01),
                  scale=(0.215 * tw, 0.16 * td, 0.15)), "pants", pelvis)
        self.part("belt", C.bm_xform(C.bm_cyl(18, 0.218 * tw, 0.218 * tw, 0.055), loc=(0, 0, 0.05),
                  scale=(1, 0.76 * td / tw, 1)), "belt", pelvis)
        self.part("buckle", C.bm_xform(C.bm_box(0.075, 0.03, 0.05, bevel=0.01),
                  loc=(0, -0.168 * td, 0.05)), "brass", pelvis)
        tz = [0.00, 0.15, 0.29, 0.38, 0.45]
        rx = [0.185, 0.200, 0.226, 0.212, 0.110]
        ry = [0.135, 0.145, 0.152, 0.140, 0.092]
        secs = []
        for k in range(5):
            bulge = belly * 0.06 * (1.0 if k in (0, 1) else 0.3 if k == 2 else 0.0)
            secs.append(C.ellipse(0, -bulge * 0.6, tz[k], rx[k] * tw + bulge * 0.4, ry[k] * td + bulge, 16))
        self.part("torso", C.bm_loft(secs), "shirt", spine)
        if belly > 0.5:
            self.part("belly", C.bm_xform(C.bm_sphere(14, 9, 1.0), loc=(0, -0.10 * td, 0.08),
                      scale=(0.20 * tw, 0.13 * td, 0.17)), "shirt", spine)
        self.part("collar", C.bm_xform(C.bm_cyl(12, 0.10, 0.09, 0.08), loc=(0, 0.0, 0.46)), "shirt", spine)
        if A.get("kerchief") or A["face"] == "scarf":
            self.part("neckerchief", C.bm_xform(C.bm_torus(16, 6, 0.10, 0.045), loc=(0, 0, 0.45),
                      scale=(1.05, 1.0, 0.8)), "bandana", spine)
            tri = C.bm_tube([(0, -0.10, 0.45), (0, -0.15, 0.36), (0, -0.155, 0.29)], [0.08, 0.055, 0.01],
                            seg=6, flat=0.35, up=(0, 1, 0))
            self.part("kerchiefTip", tri, "bandana", spine)
        if A["vest"]:
            vs = []
            for k, (z, r1, r2) in enumerate(((0.02, 0.198, 0.150), (0.20, 0.216, 0.160), (0.36, 0.226, 0.156))):
                vs.append(C.ellipse(0, 0.0, z, r1 * tw + 0.012, r2 * td + 0.012 + (0.03 * belly if k == 0 else 0), 18))
            vest = C.bm_loft(vs, cap_start=False, cap_end=False)
            for f in list(vest.faces):
                c = f.calc_center_median()
                if c.y < -0.12 * td and abs(c.x) < 0.07 * tw:
                    vest.faces.remove(f)
            self.part("vest", vest, "vest", spine, thick=0.012)
            self.part("vestPocket", C.bm_xform(C.bm_box(0.06, 0.02, 0.05, bevel=0.008),
                      loc=(0.11 * tw, -0.165 * td, 0.27)), "vest", spine)
        bd = A.get("bandolier")
        if bd:
            pts = []
            for i in range(25):
                a = 2 * math.pi * i / 24
                pts.append((math.sin(a) * 0.235 * tw, -math.cos(a) * 0.175 * td, 0.24 + 0.17 * math.sin(a)))
            self.part("bandolier", C.bm_tube(pts, [0.026] * 25, seg=5, flat=0.45, up=(0, 0, 1)), "belt", spine)
            for i in range(-4, 5):
                a = i * 0.16
                x, y = math.sin(a) * 0.245 * tw, -math.cos(a) * 0.185 * td
                z = 0.24 + 0.17 * math.sin(a)
                self.part("cart", C.bm_xform(C.bm_cyl(8, 0.011, 0.011, 0.06), loc=(x, y - 0.012, z),
                          rot=(0, 0.95, 0)), "shell", spine)
        if A.get("armor"):
            # plastron de tôle rivetée (demi-coque avant) + plaques de ventre
            ps = []
            for z, r1, r2 in ((0.10, 0.215, 0.165), (0.24, 0.236, 0.172), (0.38, 0.226, 0.160), (0.46, 0.14, 0.11)):
                ps.append(C.ellipse(0, 0.0, z, r1 * tw + 0.02, r2 * td + 0.03 + (0.05 * belly if z < 0.2 else 0), 20))
            plate = C.bm_loft(ps, cap_start=False, cap_end=False)
            for f in list(plate.faces):
                if f.calc_center_median().y > 0.02:
                    plate.faces.remove(f)
            for v in list(plate.verts):
                if not v.link_faces:
                    plate.verts.remove(v)
            self.part("chestPlate", plate, "plate", spine, thick=0.02)
            for k in range(3):
                z = 0.13 + 0.11 * k
                for sx in (1, -1):
                    self.part("rivet", C.bm_xform(C.bm_sphere(6, 4, 0.016),
                              loc=(0.16 * tw * sx, -(0.17 + 0.03 * (2 - k) * belly) * td - 0.03, z)), "rivet", spine)
            # sangles croisées dans le dos
            for sx in (1, -1):
                st = C.bm_tube(C.bezier((0.20 * tw * sx, -0.05, 0.42), (0.10 * sx, 0.20 * td, 0.40),
                                        (-0.10 * sx, 0.21 * td, 0.15), (-0.20 * tw * sx, 0.0, 0.08), 7),
                               [0.022] * 7, seg=5, flat=0.4, up=(0, 1, 0))
                self.part("backStrap", st, "strap", spine)
            # tassettes (plaques sur les hanches)
            for sx in (1, -1):
                self.part("tasset", C.bm_xform(C.bm_box(0.15, 0.03, 0.15, bevel=0.012),
                          loc=(0.14 * tw * sx, -0.15 * td, -0.06), rot=(0.25, 0.25 * sx, 0)), "plate", pelvis)
        coat = A["coat"]
        if coat:
            cs = []
            for z, r1, r2 in ((0.04, 0.205, 0.158), (0.20, 0.222, 0.168), (0.34, 0.236, 0.166), (0.42, 0.20, 0.14)):
                cs.append(C.ellipse(0, 0.0, z, r1 * tw + 0.02, r2 * td + 0.02 + (0.04 * belly if z < 0.1 else 0), 20))
            cbm = C.bm_loft(cs, cap_start=False, cap_end=False)
            for f in list(cbm.faces):
                c = f.calc_center_median()
                if c.y < -0.10 * td and abs(c.x) < 0.10 * tw:
                    cbm.faces.remove(f)
            self.part("coatTop", cbm, "coat", spine, thick=0.014)
            self.part("coatCollar", arc_strip(0.15, 0.7, 2 * math.pi - 0.7, 0.40, 0.50, n=14, flare=0.03),
                      "coat", spine, thick=0.012)
            length = 0.50 if coat == "duster" else 0.30
            skirt = arc_strip(0.235 * tw + 0.02, 0.55, 2 * math.pi - 0.55, -length, 0.10, n=22, flare=0.10)
            C.bm_xform(skirt, scale=(1, 0.80 * td / tw + 0.05 * belly, 1))
            self.part("coatSkirt", skirt, "coat", pelvis, thick=0.014)

    def build_arms(self, spine) -> None:
        j = self.j
        aw = self.A["arm"]
        sleeve = "coat" if self.A["coat"] == "duster" else "shirt"
        fore = "skin" if self.A.get("bare_arms") else sleeve
        for side, sx in (("L", 1), ("R", -1)):
            ua = j["ua" + side] = C.empty("ua" + side, SHOULDER[side] * Vector((self.TW ** 0.5, 1, 1)), spine)
            ua.rotation_mode = "QUATERNION"
            fa = j["fa" + side] = C.empty("fa" + side, (0, 0, 0), spine)
            fa.rotation_mode = "QUATERNION"
            self.part("shoulder" + side, C.bm_xform(C.bm_sphere(12, 8, 0.10 * aw), loc=(0, 0, -0.01)), sleeve, ua)
            self.part("uarm" + side, C.bm_xform(C.bm_cyl(12, 0.092 * aw, 0.080 * aw, 0.19), loc=(0, 0, -0.10)),
                      sleeve, ua)
            self.part("farm" + side, C.bm_xform(C.bm_cyl(10, 0.078 * aw, 0.066 * aw, 0.15), loc=(0, 0, -0.07)),
                      fore, fa)
            cuff = "strap" if self.A.get("bracers") else ("belt" if self.A["coat"] else "skin")
            self.part("cuff" + side, C.bm_xform(C.bm_cyl(10, 0.074 * aw, 0.084 * aw, 0.09 if self.A.get("bracers")
                                                          else 0.06), loc=(0, 0, -0.14)), cuff, fa)
            hand = C.bm_xform(C.bm_sphere(12, 8, 1.0), loc=(0, 0, -L_LOW + 0.012),
                              scale=(0.078 * aw, 0.072 * aw, 0.085 * aw))
            self.part("hand" + side, hand, "skin", fa)
            if self.A.get("armor"):
                pa = C.bm_sphere(14, 8, 1.0)
                for v in pa.verts:
                    if v.co.z < -0.1:
                        v.co.z = -0.1
                C.bm_xform(pa, loc=(0.02 * sx, 0, 0.02), scale=(0.15 * aw, 0.14 * aw, 0.12 * aw))
                self.part("pauldron" + side, pa, "plate", ua)
                self.part("pauldronRim" + side, C.bm_xform(C.bm_torus(14, 5, 0.135 * aw, 0.014),
                          loc=(0.02 * sx, 0, 0.005)), "rivet", ua)

    def build_head(self, head) -> None:
        face = self.A["face"]
        sk = C.bm_sphere(22, 16, 1.0)
        for v in sk.verts:
            x, y, z = v.co
            if z < 0:
                x *= 1.0 + 0.04 * (-z) - 0.22 * (-z) ** 2
                y *= 1.0 - 0.06 * (-z)
            v.co = Vector((x * 0.180, y * 0.172, z * 0.190)) + Vector((0, 0, 0.200))
        self.part("skull", sk, "skin", head)
        self.part("nose", C.bm_xform(C.bm_sphere(10, 7, 1.0), loc=(0, -0.172, 0.180),
                  scale=(0.032, 0.03, 0.034)), "skin", head)
        for sx in (1, -1):
            self.part("ear", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0.178 * sx, 0.0, 0.19),
                      scale=(0.025, 0.04, 0.05)), "skin", head)
            self.part("eye", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0.065 * sx, -0.158, 0.232),
                      scale=(0.028, 0.012, 0.034)), "eye", head, nofs=True)
            self.part("brow", C.bm_xform(C.bm_box(0.075, 0.022, 0.022, bevel=0.006), loc=(0.066 * sx, -0.160, 0.282),
                      rot=(0, -0.38 * sx, 0)), "brow", head)
        if face in ("bandana", "scarf"):
            bd = C.bm_sphere(22, 14, 1.0)
            for v in bd.verts:
                x, y, z = v.co
                v.co = Vector((x * 0.188, y * 0.182, z * 0.196 + 0.200))
            zmax, ymax = (0.205, 0.06) if face == "bandana" else (0.19, 0.10)
            for f in list(bd.faces):
                c = f.calc_center_median()
                if c.z > zmax or c.y > ymax:
                    bd.faces.remove(f)
            for v in list(bd.verts):
                if not v.link_faces:
                    bd.verts.remove(v)
            self.part("faceCloth", bd, "bandana", head, thick=0.01)
            if face == "bandana":
                tri = C.bm_tube([(0, -0.17, 0.12), (0, -0.19, 0.04), (0, -0.17, -0.03)], [0.09, 0.06, 0.006],
                                seg=6, flat=0.25, up=(0, 1, 0))
                self.part("bandanaTip", tri, "bandana", head)
                self.part("bandanaKnot", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, 0.175, 0.20),
                          scale=(0.04, 0.03, 0.03)), "bandana", head)
                for sx in (1, -1):
                    self.part("bandanaTail", C.bm_tube([(0.02 * sx, 0.18, 0.20), (0.05 * sx, 0.23, 0.14),
                                                        (0.07 * sx, 0.25, 0.08)], [0.03, 0.025, 0.01], seg=5,
                                                       flat=0.35, up=(1, 0, 0)), "bandana", head)
        elif face == "beard":
            bd = C.bm_sphere(18, 12, 1.0)
            for v in bd.verts:
                x, y, z = v.co
                if z > 0.1:
                    z = 0.1 + (z - 0.1) * 0.3
                v.co = Vector((x * 0.16, y * 0.13 - 0.06, z * 0.12 + 0.09))
            self.part("beard", bd, "beard", head)
            self.part("mustache", C.bm_tube(C.bezier((-0.09, -0.15, 0.13), (-0.04, -0.19, 0.17),
                                                     (0.04, -0.19, 0.17), (0.09, -0.15, 0.13), 7),
                                            [0.012, 0.025, 0.03, 0.03, 0.03, 0.025, 0.012], seg=6, flat=0.6),
                      "beard", head)
        elif face == "mustache":
            self.part("mustache", C.bm_tube(C.bezier((-0.13, -0.13, 0.10), (-0.06, -0.20, 0.17),
                                                     (0.06, -0.20, 0.17), (0.13, -0.13, 0.10), 9),
                                            [0.008, 0.02, 0.03, 0.034, 0.034, 0.034, 0.03, 0.02, 0.008], seg=6,
                                            flat=0.6), "beard", head)
        elif face == "stubble":
            self.part("mustache", C.bm_tube(C.bezier((-0.07, -0.16, 0.14), (-0.03, -0.185, 0.155),
                                                     (0.03, -0.185, 0.155), (0.07, -0.16, 0.14), 5),
                                            [0.01, 0.02, 0.02, 0.02, 0.01], seg=5, flat=0.6), "brow", head)

    def build_hat(self, head) -> None:
        h = self.A["hat"]
        hz = 0.33
        if h in ("cowboy_low", "cowboy_tall", "wide", "boss"):
            crown_h = {"cowboy_low": 0.13, "cowboy_tall": 0.20, "wide": 0.15, "boss": 0.20}[h]
            r_out = {"cowboy_low": 0.32, "cowboy_tall": 0.33, "wide": 0.37, "boss": 0.40}[h]
            curl = {"cowboy_low": 0.07, "cowboy_tall": 0.08, "wide": 0.04, "boss": 0.11}[h]
            secs = []
            for k in range(6):
                t = k / 5
                rx = 0.175 - 0.035 * t ** 2
                ry = 0.160 - 0.040 * t ** 2
                pts = []
                for i in range(20):
                    a = 2 * math.pi * i / 20
                    x, y = rx * math.sin(a), -ry * math.cos(a)
                    z = hz + crown_h * t
                    if t > 0.75:
                        z -= 0.04 * (1 - abs(math.sin(a))) * (t - 0.75) * 4
                    pts.append((x, y, z))
                secs.append(pts)
            self.part("crown", C.bm_loft(secs), "hat", head)
            band = C.bm_loft([C.ellipse(0, 0, hz + 0.005, 0.178, 0.163, 20),
                              C.ellipse(0, 0, hz + 0.04, 0.176, 0.161, 20)], cap_start=False, cap_end=False)
            self.part("hatband", band, "hatband", head, thick=0.008)
            self.part("brim", brim(0.15, r_out, curl=curl, front_dip=0.03, z=hz, sy=0.95), "hat", head, thick=0.018)
        elif h == "kettle":
            # casque de tôle bosselé à large bord plat (silhouette lisible du Robuste)
            dm = C.bm_sphere(18, 10, 1.0)
            for v in dm.verts:
                if v.co.z < 0:
                    v.co.z = 0
            C.bm_xform(dm, loc=(0, 0.0, hz - 0.03), scale=(0.19, 0.18, 0.19))
            self.part("crown", dm, "hat", head)
            self.part("crest", C.bm_xform(C.bm_box(0.03, 0.30, 0.04, bevel=0.01), loc=(0, 0.0, hz + 0.15)),
                      "hat", head)
            self.part("brim", brim(0.17, 0.30, curl=-0.05, z=hz - 0.03, sy=0.95), "hat", head, thick=0.016)
            self.part("hatband", C.bm_loft([C.ellipse(0, 0, hz - 0.03, 0.192, 0.182, 20),
                                            C.ellipse(0, 0, hz + 0.01, 0.19, 0.18, 20)],
                                           cap_start=False, cap_end=False), "rivet", head, thick=0.008)

    # --- armes -------------------------------------------------------------
    def gun_group(self, name: str, parent) -> bpy.types.Object:
        g = joint("w_" + name, parent, (0, 0, 0))
        self.weapons[name] = g
        return g

    def build_long_gun(self, spine, length: float, scope: bool, receiver: str = "brass", drum: bool = False) -> None:
        g = self.gun_group("long", spine)
        self.part("barrel", C.bm_xform(C.bm_cyl(10, 0.017, 0.017, length), loc=(0, -0.10 - length / 2, 0.035),
                  rot=(math.pi / 2, 0, 0)), "metal_dark", g, grp="long")
        self.part("tube", C.bm_xform(C.bm_cyl(10, 0.014, 0.014, length * 0.8), loc=(0, -0.08 - length * 0.4, 0.005),
                  rot=(math.pi / 2, 0, 0)), "metal_dark", g, grp="long")
        self.part("fore", C.bm_xform(C.bm_box(0.05, 0.24, 0.05, bevel=0.012), loc=(0, -0.21, 0.0)), "wood", g,
                  grp="long")
        self.part("receiver", C.bm_xform(C.bm_box(0.055, 0.14, 0.075, bevel=0.012), loc=(0, -0.02, 0.02)),
                  receiver, g, grp="long")
        self.part("lever", C.bm_xform(C.bm_torus(10, 4, 0.04, 0.008), loc=(0, 0.02, -0.05),
                  rot=(0, math.pi / 2, 0), scale=(1, 1.4, 1)), "metal_dark", g, grp="long")
        stock = C.bm_box(0.05, 0.30, 0.09, bevel=0.02)
        for v in stock.verts:
            if v.co.y > 0:
                v.co.z = v.co.z * 1.4 - 0.025
        self.part("stock", C.bm_xform(stock, loc=(0, 0.20, -0.02)), "wood", g, grp="long")
        if scope:
            self.part("scope", C.bm_xform(C.bm_cyl(12, 0.030, 0.024, 0.36), loc=(0, -0.10, 0.11),
                      rot=(math.pi / 2, 0, 0)), "metal_dark", g, grp="long")
            for yy in (-0.27, 0.07):
                self.part("scopeRing", C.bm_xform(C.bm_cyl(12, 0.036, 0.036, 0.04), loc=(0, yy, 0.11),
                          rot=(math.pi / 2, 0, 0)), "brass", g, grp="long")
            self.part("scopeLens", C.bm_xform(C.bm_cyl(12, 0.028, 0.028, 0.01), loc=(0, -0.285, 0.11),
                      rot=(math.pi / 2, 0, 0)), "lens", g, grp="long", nofs=True)
            for yy in (-0.12, 0.0):
                self.part("scopeMount", C.bm_xform(C.bm_box(0.02, 0.03, 0.06), loc=(0, yy, 0.07)), "metal_dark", g,
                          grp="long")
        if drum:
            self.part("drum", C.bm_xform(C.bm_cyl(16, 0.075, 0.075, 0.05), loc=(0, -0.10, -0.09),
                      rot=(0, math.pi / 2, 0)), "metal_dark", g, grp="long")
            self.part("grip2", C.bm_xform(C.bm_box(0.04, 0.05, 0.10, bevel=0.012), loc=(0, -0.30, -0.06),
                      rot=(0.3, 0, 0)), "wood", g, grp="long")

    def build_weapons(self, spine) -> None:
        w = self.A["weapon"]
        if w == "rifle":
            self.build_long_gun(spine, 0.58, scope=False)
        elif w == "sniper":
            self.build_long_gun(spine, 0.86, scope=True, receiver="metal_dark")
        elif w == "burst_rifle":
            self.build_long_gun(spine, 0.50, scope=False, receiver="metal_dark", drum=True)
        elif w == "axe":
            g = self.gun_group("axe", spine)
            # manche le long de +Z (main droite à l'origine, main gauche plus bas)
            self.part("haft", C.bm_xform(C.bm_cyl(10, 0.026, 0.022, 0.86), loc=(0, 0, 0.22)), "wood", g, grp="axe")
            self.part("pommel", C.bm_xform(C.bm_sphere(8, 6, 0.035), loc=(0, 0, -0.21)), "metal_dark", g, grp="axe")
            for z in (0.0, -0.14):
                self.part("wrap", C.bm_xform(C.bm_cyl(10, 0.031, 0.031, 0.06), loc=(0, 0, z)), "strap", g, grp="axe")
            # fer : grande lame en croissant vers l'avant (-Y), pointe à l'arrière
            blade = C.bm_box(0.024, 0.34, 0.42, bevel=0.006)
            for v in blade.verts:
                y = v.co.y
                k = min(1.0, max(0.0, (y + 0.17) / 0.34))  # 0 = avant (tranchant), 1 = arrière
                v.co.z *= 0.45 + 0.55 * (1 - k) ** 0.8 if k > 0 else 1.0
                v.co.x *= 0.35 + 0.65 * k
            self.part("blade", C.bm_xform(blade, loc=(0, -0.20, 0.56)), "axehead", g, grp="axe")
            self.part("edge", C.bm_xform(C.bm_box(0.014, 0.035, 0.42, bevel=0.004), loc=(0, -0.37, 0.56)),
                      "metal", g, grp="axe")
            self.part("socket", C.bm_xform(C.bm_box(0.06, 0.07, 0.12, bevel=0.012), loc=(0, 0.0, 0.56)),
                      "metal_dark", g, grp="axe")
            self.part("spike", C.bm_xform(C.bm_cyl(8, 0.035, 0.0, 0.16), loc=(0, 0.11, 0.56),
                      rot=(-math.pi / 2, 0, 0)), "axehead", g, grp="axe")
            self.part("topSpike", C.bm_xform(C.bm_cyl(8, 0.025, 0.0, 0.10), loc=(0, 0, 0.67)), "axehead", g, grp="axe")
        elif w == "shield_mace":
            g = self.gun_group("mace", spine)
            self.part("haft", C.bm_xform(C.bm_cyl(10, 0.028, 0.024, 0.56), loc=(0, 0, 0.18)), "wood", g, grp="mace")
            self.part("wrap", C.bm_xform(C.bm_cyl(10, 0.033, 0.033, 0.10), loc=(0, 0, 0.0)), "strap", g, grp="mace")
            head = C.bm_cyl(8, 0.085, 0.085, 0.20)
            C.bm_xform(head, loc=(0, 0, 0.50))
            self.part("maceHead", head, "metal_dark", g, grp="mace", smooth=False)
            for k in range(8):
                a = k * math.pi / 4
                self.part("flange", C.bm_xform(C.bm_box(0.02, 0.07, 0.18, bevel=0.005),
                          loc=(0.09 * math.cos(a), 0.09 * math.sin(a), 0.50), rot=(0, 0, a + math.pi / 2)),
                          "plate", g, grp="mace")
            self.part("maceTip", C.bm_xform(C.bm_cyl(8, 0.04, 0.0, 0.08), loc=(0, 0, 0.64)), "metal", g, grp="mace")
            # bouclier : grande plaque rectangulaire bombée, planches + bandes de tôle rivetées
            sg = self.gun_group("shield", spine)
            W, H = 0.50, 0.66
            sec = []
            for k in range(9):
                t = k / 8 - 0.5
                x = W * t
                y = -0.06 * (1 - (2 * t) ** 2)
                sec.append([(x, y, -H / 2), (x, y, 0.0), (x, y, H / 2)])
            secs = [[sec[k][r] for k in range(9)] for r in range(3)]
            sh = C.bm_loft(secs, closed=False)
            self.part("shieldBoard", sh, "shieldwood", sg, thick=0.04)
            for z in (-H * 0.36, 0.0, H * 0.36):
                band = []
                for k in range(9):
                    t = k / 8 - 0.5
                    band.append([(W * t * 1.02, -0.06 * (1 - (2 * t) ** 2) - 0.03, z - 0.045),
                                 (W * t * 1.02, -0.06 * (1 - (2 * t) ** 2) - 0.03, z + 0.045)])
                bb = C.bm_loft([[b[0] for b in band], [b[1] for b in band]], closed=False)
                self.part("shieldBand", bb, "plate", sg, thick=0.012)
                for k in (1, 4, 7):
                    t = k / 8 - 0.5
                    self.part("shieldRivet", C.bm_xform(C.bm_sphere(6, 4, 0.018),
                              loc=(W * t, -0.06 * (1 - (2 * t) ** 2) - 0.045, z)), "rivet", sg)
            self.part("shieldBoss", C.bm_xform(C.bm_sphere(12, 6, 1.0), loc=(0, -0.09, 0.0),
                      scale=(0.08, 0.05, 0.08)), "metal", sg)
            self.part("shieldRim", C.bm_xform(C.bm_box(W + 0.04, 0.05, 0.035, bevel=0.01), loc=(0, -0.01, H / 2)),
                      "plate", sg)
            self.part("shieldRim", C.bm_xform(C.bm_box(W + 0.04, 0.05, 0.035, bevel=0.01), loc=(0, -0.01, -H / 2)),
                      "plate", sg)

    # ------------------------------------------------------------------ poses
    def rest(self) -> None:
        for name, ob in self.j.items():
            if name in ("root",) or name.startswith(("ua", "fa", "w_")):
                continue
            ob.rotation_euler = (0, 0, 0)
        self.j["body"].location = (0, 0, 0)
        self.j["body"].rotation_euler = (0, 0, 0)
        self.j["pelvis"].location = (0, 0, self.PZ)
        self.j["head"].rotation_euler = (-0.18, 0, 0)
        self.j["neck"].location = (0, 0, 0.45)
        for name in self.grp:
            self.show(name, True)

    def arm_ik(self, side: str, target: Vector, pole: Vector) -> None:
        S0 = self.j["ua" + side].location.copy()
        d = target - S0
        dist = min(max(d.length, 0.05), (L_UP + L_LOW) * 0.995)
        u = d.normalized()
        a = (L_UP ** 2 + dist ** 2 - L_LOW ** 2) / (2 * dist)
        h = math.sqrt(max(L_UP ** 2 - a * a, 0.0))
        p = pole - u * pole.dot(u)
        p = p.normalized() if p.length > 1e-5 else Vector((0, 1, 0))
        E = S0 + u * a + p * h
        H = S0 + u * dist
        down = Vector((0, 0, -1))
        ua, fa = self.j["ua" + side], self.j["fa" + side]
        ua.rotation_quaternion = down.rotation_difference((E - S0).normalized())
        fa.location = E
        fa.rotation_quaternion = down.rotation_difference((H - E).normalized())

    def place(self, wname: str, loc, rot) -> None:
        g = self.weapons.get(wname)
        if g is not None:
            g.location = loc
            g.rotation_euler = rot

    def wpt(self, wname: str, local) -> Vector:
        g = self.weapons[wname]
        return Vector(g.location) + Euler(g.rotation_euler, "XYZ").to_matrix() @ Vector(local)

    def legs(self, hipL, hipR, kneeL, kneeR) -> None:
        j = self.j
        j["hipL"].rotation_euler = hipL
        j["hipR"].rotation_euler = hipR
        j["kneeL"].rotation_euler = (kneeL, 0, 0)
        j["kneeR"].rotation_euler = (kneeR, 0, 0)

    def kneel(self, k: float) -> None:
        """Genou droit à terre (tireur d'élite) ; k = 0 debout .. 1 agenouillé."""
        self.j["pelvis"].location.z = self.PZ - 0.30 * k * self.LEG
        self.legs((-1.25 * k, -0.06, 0), (0.30 * k, 0.08, 0), 1.35 * k, 1.55 * k + 0.05)

    def hold(self, aim: float = 0.0, dz: float = 0.0, recoil: float = 0.0, swing_l: float | None = None) -> None:
        w = self.A["weapon"]
        if w in ("rifle", "sniper", "burst_rifle"):
            rest_loc = Vector((-0.06, -0.24, 0.10 + dz))
            aim_loc = Vector((-0.07, -0.26, 0.36))
            loc = rest_loc.lerp(aim_loc, aim) + Vector((0, 0.07 * recoil, 0.03 * recoil))
            rot = (0.55 * (1 - aim) - 0.35 * recoil, 0.0, 0.55 * (1 - aim))
            self.place("long", loc, rot)
            grip = self.wpt("long", (0, 0.08, -0.05))
            fore = self.wpt("long", (0, -0.22 if w != "burst_rifle" else -0.30, -0.04))
            if swing_l is not None:
                fore = fore + Vector((0, 0.06 * swing_l, 0))
            self.arm_ik("R", grip, R_POLE)
            self.arm_ik("L", fore, L_POLE)
        elif w == "axe":
            # en travers du corps, fer au-dessus de l'épaule gauche
            loc = Vector((-0.12, -0.22, 0.10 + dz))
            self.place("axe", loc, (-0.25, 0.75, 0.15))
            self.arm_ik("R", loc, R_POLE)
            self.arm_ik("L", self.wpt("axe", (0, 0, 0.20)), L_POLE)
        elif w == "shield_mace":
            self.hold_shield(Vector((0.17, -0.30, 0.16 + dz)), (0.0, 0.0, -0.30))
            mloc = Vector((-0.24, -0.14, 0.10 + dz))
            self.place("mace", mloc, (2.3, 0.35, 0))
            self.arm_ik("R", mloc, R_POLE)

    def hold_shield(self, hand: Vector, rot) -> None:
        self.place("shield", hand + Vector((0, -0.05, 0.06)), rot)
        self.arm_ik("L", hand, Vector((1.0, 0.2, -0.4)))

    # --- idle / run / hit / death ---------------------------------------
    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        t = 2 * math.pi * i / n
        b = math.sin(t)
        sway = math.sin(t + 0.6)
        heavy = 1.0 + 0.6 * self.A["belly"]
        j["pelvis"].location.z = self.PZ - 0.012 * (1 - b) * 0.5 * heavy
        j["pelvis"].rotation_euler = (0, 0.012 * sway, 0.03 * sway)
        j["spine"].rotation_euler = (0.03 + 0.016 * b, -0.02 * sway, 0)
        j["spine"].scale = (1 + 0.01 * b, 1 + 0.01 * b, 1 + 0.012 * b)
        j["neck"].rotation_euler = (-0.04 - 0.016 * b, 0.03 * sway, 0.03 * sway)
        stance = 0.10 if self.A["belly"] > 0.3 else 0.07
        self.legs((0.03, -stance - 0.012 * sway, 0), (-0.03, stance - 0.012 * sway, 0), 0.07, 0.09)
        if self.A.get("idle_kneel"):
            self.kneel(1.0)
            j["pelvis"].location.z -= 0.006 * b
            j["spine"].rotation_euler = (0.16 + 0.016 * b, 0, 0.05 * sway)
            self.hold(aim=0.35, dz=0.008 * b)
            return
        self.hold(aim=0.0, dz=0.012 * b)

    def pose_run(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        p = 2 * math.pi * i / n
        s = math.sin(p)
        amp = 0.85 if self.A["belly"] < 0.5 else 0.65
        j["pelvis"].location.z = self.PZ - 0.045 + 0.060 * abs(math.sin(p + 0.35))
        j["pelvis"].rotation_euler = (0, 0, -0.16 * s)
        j["spine"].rotation_euler = (0.24 + self.A.get("run_lean", 0.0), 0, 0.18 * s)
        j["neck"].rotation_euler = (-0.22, 0, -0.12 * s)
        self.legs((-amp * s - 0.15, 0, 0), (amp * s - 0.15, 0, 0),
                  0.20 + 1.35 * max(0.0, math.sin(p - 1.0)) ** 1.2,
                  0.20 + 1.35 * max(0.0, math.sin(p - 1.0 + math.pi)) ** 1.2)
        self.hold(aim=0.0, dz=0.02 * math.cos(p))
        if self.A["weapon"] == "axe":
            # fer brandi en courant (agressif)
            loc = Vector((-0.10, -0.18, 0.22 + 0.03 * math.cos(p)))
            self.place("axe", loc, (-0.55, 0.55, 0.1))
            self.arm_ik("R", loc, R_POLE)
            self.arm_ik("L", self.wpt("axe", (0, 0, -0.14)), L_POLE)

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        k = (1.0, 0.6, 0.25)[i]
        j["pelvis"].location.z = self.PZ - 0.03 * k
        j["pelvis"].location.y = 0.04 * k
        j["spine"].rotation_euler = (-0.34 * k, 0, 0.12 * k)
        j["neck"].rotation_euler = (-0.34 * k, 0, -0.14 * k)
        self.legs((0.12 * k, -0.10, 0), (-0.20 * k, 0.10, 0), 0.12 + 0.14 * k, 0.12)
        self.hold(aim=0.2 * k, dz=0.06 * k)

    def pose_death(self, i: int, n: int) -> None:
        """Chute sur le dos ; dernière image = cadavre au sol."""
        self.rest()
        j = self.j
        t = i / (n - 1)
        if t < 0.25:
            u = t / 0.25
            fall = 0.08 * u
            j["spine"].rotation_euler = (-0.45 * u, 0, 0.15 * u)
            j["neck"].rotation_euler = (-0.5 * u, 0, -0.1 * u)
            self.legs((0.15 * u, -0.10, 0), (-0.25 * u, 0.12, 0), 0.25 * u, 0.15)
        else:
            u = min(1.0, (t - 0.25) / 0.55)
            e = u * u * (3 - 2 * u)
            bounce = 0.0
            if t > 0.8:
                v = (t - 0.8) / 0.2
                bounce = 0.06 * math.sin(v * math.pi) * (1 - v)
            fall = 0.08 + (math.pi / 2 - 0.08) * e - bounce
            j["spine"].rotation_euler = (-0.45 + 0.45 * e, 0, 0.15 - 0.10 * e)
            j["neck"].rotation_euler = (-0.5 + 0.35 * e, 0, -0.1 + 0.4 * e)
            self.legs((0.15 + 0.35 * math.sin(u * math.pi), -0.12 - 0.08 * e, 0),
                      (-0.25 + 0.25 * e, 0.14 + 0.10 * e, 0),
                      0.25 + 0.7 * math.sin(u * math.pi) * (1 - 0.6 * e) + 0.35 * e, 0.15 - 0.05 * e)
        body = j["body"]
        k = fall / (math.pi / 2)
        tau = corpse_twist(self.dir_ang) * min(1.0, k * 1.2)
        body.rotation_euler = (-fall, 0, tau)
        sc = self.A["scale"]
        body.location = Euler((0, 0, tau)).to_matrix() @ Vector((0, -0.72 * sc * k, 0.16 * sc * k ** 2))
        arm_u = min(1.0, t / 0.6)
        hl = Vector((0.30, -0.05 + 0.25 * arm_u, 0.30 + 0.25 * arm_u))
        hr = Vector((-0.34, -0.10 + 0.20 * arm_u, 0.26 + 0.30 * arm_u))
        self.arm_ik("L", hl, Vector((0.8, 0.2, -0.6)))
        self.arm_ik("R", hr, Vector((-0.8, 0.2, -0.6)))
        self.drop_weapons(hl, hr, arm_u)
        j["head"].rotation_euler = (-0.18 + 0.25 * min(1.0, t * 1.4), 0.0, 0.35 * min(1.0, t * 1.4))

    def drop_weapons(self, hl: Vector, hr: Vector, u: float) -> None:
        w = self.A["weapon"]
        if w in ("rifle", "sniper", "burst_rifle"):
            self.place("long", hr + Vector((0.05, -0.18 * u, -0.05)), (0.2 + 1.2 * u, 0.0, 0.9 * u))
        elif w == "axe":
            self.place("axe", hr + Vector((0.0, 0.0, -0.02)), (0.3 + 1.0 * u, 0.0, 0.4 * u))
        elif w == "shield_mace":
            self.place("mace", hr, (0.4 + 1.0 * u, 0.0, 0.6 * u))
            self.place("shield", hl + Vector((0.12 * u, 0.05, 0.0)), (0.1 + 1.2 * u, 0.0, -0.3))

    # --- attaques ----------------------------------------------------------
    def pose_attack(self, i: int, n: int) -> None:
        getattr(self, "atk_" + self.A["weapon"])(i)

    def _aim_body(self, lean: float = 0.0, twist: float = 0.0) -> None:
        j = self.j
        j["spine"].rotation_euler = (0.06 + lean, 0, twist)
        j["neck"].rotation_euler = (-0.08 - lean, 0, -twist * 0.6)
        self.legs((0.05, -0.12, 0), (-0.10, 0.12, 0), 0.12, 0.18)

    def atk_rifle(self, i: int) -> None:
        self.rest()
        aim = (0.4, 0.95, 1.0, 1.0, 0.95, 0.85)[i]
        rc = (0, 0, 0, 0.8, 0.2, 0.0)[i]
        self._aim_body(lean=0.05 - 0.12 * rc, twist=0.08)
        self.j["neck"].rotation_euler = (-0.02, 0, 0.12)
        self.hold(aim=aim, recoil=rc, swing_l=(0, 0, 0, 0, 1.0, 0.4)[i])

    def atk_burst_rifle(self, i: int) -> None:
        self.rest()
        aim = (0.5, 0.95, 1.0, 1.0, 1.0, 0.9)[i]
        rc = (0, 0, 0, 0.6, 0.5, 0.1)[i]
        self._aim_body(lean=0.10 - 0.10 * rc, twist=0.05)
        self.j["neck"].rotation_euler = (-0.04, 0, 0.10)
        self.hold(aim=aim, recoil=rc)

    def atk_sniper(self, i: int) -> None:
        self.rest()
        kn = (0.6, 1.0, 1.0, 1.0, 1.0, 1.0)[i]
        aim = (0.5, 0.95, 1.0, 1.0, 0.95, 0.8)[i]
        rc = (0, 0, 0, 1.0, 0.3, 0.0)[i]
        self.kneel(kn)
        j = self.j
        j["spine"].rotation_euler = (0.12 - 0.15 * rc, 0, 0.10)
        j["neck"].rotation_euler = (-0.02, 0, 0.14)
        self.hold(aim=aim, recoil=rc, swing_l=(0, 0, 0, 0, 1.0, 0.3)[i])

    def atk_axe(self, i: int) -> None:
        self.rest()
        j = self.j
        crouch = (0.04, 0.07, 0.08, 0.10, 0.08, 0.03)[i]
        j["pelvis"].location.z = self.PZ - crouch
        lean = (0.0, -0.18, -0.22, 0.50, 0.55, 0.2)[i]
        j["spine"].rotation_euler = (lean, 0, (0.1, 0.15, 0.15, -0.1, -0.1, 0.0)[i])
        j["neck"].rotation_euler = (-lean * 0.7, 0, 0)
        stride = (0.2, 0.3, 0.35, 0.8, 0.8, 0.4)[i]
        self.legs((-stride * 0.6, -0.08, 0), (stride * 0.5, 0.10, 0), 0.25 + crouch * 2, 0.4 + crouch * 2)
        grip = [Vector((-0.08, -0.16, 0.34)), Vector((-0.02, 0.02, 0.58)), Vector((-0.02, 0.04, 0.60)),
                Vector((0.0, -0.33, 0.26)), Vector((0.0, -0.30, 0.10)), Vector((-0.10, -0.24, 0.14))][i]
        rot = [(-0.5, 0.3, 0), (-1.7, 0.05, 0), (-1.95, 0.05, 0), (1.35, 0, 0), (1.85, 0, 0), (0.2, 0.5, 0.1)][i]
        self.place("axe", grip, rot)
        self.arm_ik("R", grip, R_POLE)
        self.arm_ik("L", self.wpt("axe", (0, 0, -0.14)), L_POLE)

    def atk_shield_mace(self, i: int) -> None:
        self.rest()
        j = self.j
        lean = (0.05, -0.10, -0.12, 0.40, 0.45, 0.15)[i]
        twist = (0.0, -0.35, -0.40, 0.35, 0.40, 0.1)[i]
        j["spine"].rotation_euler = (lean, 0, twist)
        j["neck"].rotation_euler = (-lean * 0.7, 0, -twist * 0.5)
        stride = (0.2, 0.3, 0.3, 0.7, 0.7, 0.3)[i]
        self.legs((-stride * 0.6, -0.10, 0), (stride * 0.5, 0.12, 0), 0.25, 0.35)
        self.hold_shield(Vector((0.16, -0.32, 0.18)), (0.0, 0.0, -0.25 - 0.2 * max(0.0, twist)))
        grip = [Vector((-0.24, -0.06, 0.22)), Vector((-0.20, 0.10, 0.58)), Vector((-0.20, 0.12, 0.60)),
                Vector((-0.06, -0.36, 0.26)), Vector((-0.02, -0.32, 0.08)), Vector((-0.20, -0.14, 0.12))][i]
        rot = [(-0.6, -0.2, 0), (-1.8, -0.2, 0), (-2.0, -0.2, 0), (1.3, -0.1, 0), (1.8, -0.1, 0), (-0.2, -0.2, 0)][i]
        self.place("mace", grip, rot)
        self.arm_ik("R", grip, R_POLE)

    def pose(self, anim: str, i: int, n: int) -> None:
        getattr(self, "pose_" + anim)(i, n)

    # --- canon / lame (méta muzzle_px) ------------------------------------
    def muzzle_world(self) -> Vector:
        bpy.context.view_layer.update()
        w = self.A["weapon"]
        if w in ("rifle", "sniper", "burst_rifle"):
            ln = {"rifle": 0.58, "sniper": 0.86, "burst_rifle": 0.50}[w]
            g, loc = self.weapons["long"], (0, -0.10 - ln, 0.035)
        elif w == "axe":
            g, loc = self.weapons["axe"], (0, -0.37, 0.56)
        elif w == "shield_mace":
            g, loc = self.weapons["mace"], (0, 0, 0.55)
        else:
            g, loc = self.j["head"], (0, -0.2, 0.2)
        return g.matrix_world @ Vector(loc)


def make(kind: str) -> Human:
    return Human(kind)
