"""Bestiaire Far West : quadrupèdes (Maraudeur = hyène/coyote, Chien de garde ; élite : le Buffle).
Rig propre (joints vides) : torse rigide, cou + tête + mâchoire, 4 pattes à 3 segments, queue.
Repère : l'animal regarde vers -Y, +X = sa gauche, Z vers le haut (comme les humanoïdes).

Animations (mêmes noms que les humanoïdes, lues par EnemyArt) :
    idle   respiration, regard, queue ;
    run    galop rassemblé (pattes avant puis arrière décalées) ;
    attack 0-2 ramassé (2 tenue pendant le télégraphe), 3 bond gueule ouverte / coup de tête,
           4 morsure (mâchoire fermée, secousse), 5 retour ;
    hit    recul, tête relevée ;
    death  chute sur le flanc ; la dernière image = cadavre (en travers de l'écran).
"""
from __future__ import annotations

import math

import fw_sheet as S  # noqa: F401  (chemins + rdm_common)
from fw_sheet import C, bpy
from fw_humans import corpse_twist, joint
from mathutils import Vector

ANIMS = {
    "idle": (6, 7, True),
    "run": (8, 16, True),
    "attack": (6, 12, False),
    "hit": (3, 14, False),
    "death": (8, 12, False),
}

# Gabarits. Longueurs en unités Blender (héros ≈ 1,6 de haut).
ARCH: dict[str, dict] = {
    "fw_marauder": {
        "name": "Maraudeur", "scale": 1.42,
        "withers": 0.64, "hips": 0.50, "length": 0.90,
        "chest": (0.20, 0.23), "rump": (0.15, 0.16),
        "neck": 0.22, "neck_r": 0.12, "head": 0.17, "snout": 0.17, "snout_r": 0.075,
        "leg_r": 0.058, "front_leg": (0.25, 0.22, 0.12), "hind_leg": (0.21, 0.20, 0.13),
        "ears": "round", "mane": True, "tail": "bushy", "collar": None, "teeth": True,
        "head_down": 0.25, "jaw_idle": 0.18,
        "mats": {
            "fur": ("pat", [("#a8683c", "#3e2028", "#d0905a"), ("#5a3020", "#20101a", "#7a4630")], 7.0),
            "fur_dark": ("#3e2418", "#140a10", "#5e3a26"),
            "belly": ("#c8955e", "#5a3a36", "#e8b47c"),
            "muzzle": ("#2e1c16", "#0c0608", "#4a3024"),
        },
    },
    "fw_guard_dog": {
        "name": "Chien de garde", "scale": 1.30,
        "withers": 0.60, "hips": 0.56, "length": 0.84,
        "chest": (0.18, 0.22), "rump": (0.14, 0.16),
        "neck": 0.20, "neck_r": 0.11, "head": 0.155, "snout": 0.18, "snout_r": 0.07,
        "leg_r": 0.054, "front_leg": (0.24, 0.22, 0.12), "hind_leg": (0.22, 0.21, 0.14),
        "ears": "pointed", "mane": False, "tail": "thin", "collar": "spiked", "harness": True,
        "teeth": True, "head_down": 0.0, "jaw_idle": 0.08,
        "mats": {
            "fur": ("pat", [("#5a3a28", "#1c1018", "#7e5438"), ("#3a2620", "#120a10", "#5a3e30")], 5.0),
            "fur_dark": ("#2a1c18", "#0c0608", "#463026"),
            "belly": ("#9a6a40", "#40242a", "#c08a56"),
            "muzzle": ("#1e1412", "#060404", "#3a2a22"),
        },
    },
}

COMMON_MATS = {
    "eye": "!#ffb040",
    "nose": ("#141012", "#040304", "#3a3236"),
    "teeth": ("#f0e8d8", "#7a7088", "#ffffff"),
    "tongue": ("#b03a40", "#40121e", "#e06064"),
    "leather": ("#4a2a1c", "#180a0e", "#70442c"),
    "brass": ("#c09040", "#5a3828", "#f0d080"),
    "metal": ("#8a8c92", "#2c2e3a", "#d8dae0"),
    "horn": ("#d8c8a0", "#5a4a48", "#fff4d0"),
    "red": ("#c0261e", "#4a0c1a", "#ec4a34"),
}


class Beast:
    frame = 192
    outline_px = 4.6

    def __init__(self, kind: str, spec: dict | None = None) -> None:
        self.kind = kind
        self.A = spec if spec is not None else ARCH[kind]
        self.name = self.A["name"]
        self.dir_ang = 0.0
        self.j: dict[str, bpy.types.Object] = {}
        self.parts: list[tuple[bpy.types.Object, str]] = []
        self.ph = C.toon("_ph_" + kind, "#ff00ff")
        self.frame = self.A.get("frame", 224)
        A = self.A
        self.HM = (A["withers"] + A["hips"]) * 0.5
        self.cam_z = A.get("cam_z", 0.62 * A["scale"])
        self.build()
        self.apply_mats()

    def anims(self) -> dict:
        return dict(ANIMS)

    def part(self, name, bm, key, parent, smooth=True, nofs=False, thick=0.0):
        ob = C.mesh_obj(name, bm, self.ph, smooth=smooth, coll=C.nofs_collection() if nofs else None)
        ob.parent = parent
        if thick > 0.0:
            C.solidify(ob, thick, 0.0)
        self.parts.append((ob, key))
        return ob

    def apply_mats(self) -> None:
        spec = dict(COMMON_MATS)
        spec.update(self.A["mats"])
        mats = {}
        for key, sp in spec.items():
            name = "%s_%s" % (self.kind, key)
            if isinstance(sp, str) and sp.startswith("!"):
                mats[key] = C.toon(name, sp[1:], emit=1.8)
            elif sp[0] == "pat":
                mats[key] = C.toon_pattern(name, sp[1], scale=sp[2], thresholds=(0.55,), rim=0.22)
            else:
                mats[key] = C.toon(name, sp[0], sp[1], sp[2], rim=0.24)
        for ob, key in self.parts:
            ob.data.materials[0] = mats.get(key, mats["fur"])

    # ------------------------------------------------------------------ construction
    def build(self) -> None:
        A, j = self.A, self.j
        L = A["length"]
        j["root"] = root = joint("root", None, (0, 0, 0))
        j["body"] = body = joint("body", root, (0, 0, 0))
        body.scale = (A["scale"],) * 3
        j["torso"] = torso = joint("torso", body, (0, 0, self.HM))
        self.build_torso(torso)
        # cou -> tête -> mâchoire
        zf = A["withers"] - self.HM
        j["neck"] = neck = joint("neck", torso, (0, -L * 0.42, zf - 0.02))
        nl = A["neck"]
        self.part("neckMesh", C.bm_tube([(0, 0.06, -0.02), (0, -nl * 0.45, nl * 0.30), (0, -nl * 0.85, nl * 0.52)],
                                        [A["neck_r"] * 1.25, A["neck_r"] * 1.05, A["neck_r"] * 0.85], seg=12),
                  "fur", neck)
        j["head"] = head = joint("head", neck, (0, -nl * 0.85, nl * 0.55))
        self.build_head(head)
        self.build_legs(torso)
        # queue
        j["tail"] = tail = joint("tail", torso, (0, L * 0.47, A["hips"] - self.HM + 0.03))
        self.build_tail(tail)
        self.build_extra()

    def build_extra(self) -> None:
        """Accessoires propres (buffle : bosse, cornes) : à surcharger."""

    def torso_sections(self) -> list:
        A = self.A
        L = A["length"]
        secs = []
        n = 9
        for k in range(n):
            t = k / (n - 1)  # 0 = poitrail, 1 = croupe
            y = -L * 0.5 + L * t
            # profil : poitrail arrondi, taille fine, croupe
            bulge = math.sin(math.pi * min(1.0, max(0.0, t * 1.04))) ** 0.45
            rx = (A["chest"][0] * (1 - t) + A["rump"][0] * t) * (0.55 + 0.45 * bulge)
            rz = (A["chest"][1] * (1 - t) + A["rump"][1] * t) * (0.55 + 0.45 * bulge)
            if 0.45 < t < 0.75:
                rz *= 0.90
            zc = (A["withers"] - self.HM) * (1 - t) + (A["hips"] - self.HM) * t - 0.03
            sec = []
            for i in range(16):
                a = 2 * math.pi * i / 16
                x, z = rx * math.cos(a), rz * math.sin(a)
                if z < 0:
                    z *= 0.85  # ventre un peu plat
                sec.append((x, y, zc + z))
            secs.append(sec)
        return secs

    def build_torso(self, torso) -> None:
        A = self.A
        secs = self.torso_sections()
        self.part("torsoMesh", C.bm_loft(secs), "fur", torso)
        # ventre clair
        L = A["length"]
        belly = C.bm_sphere(14, 8, 1.0)
        C.bm_xform(belly, loc=(0, -L * 0.12, (A["withers"] + A["hips"]) * 0.5 - self.HM - A["chest"][1] * 0.62),
                   scale=(A["chest"][0] * 0.75, L * 0.30, A["chest"][1] * 0.32))
        self.part("belly", belly, "belly", torso)
        if A.get("mane"):
            # crinière sombre en dents de scie, du crâne au milieu du dos
            for k in range(9):
                t = k / 8
                y = -L * 0.48 + L * 0.55 * t
                z = (A["withers"] - self.HM) + A["chest"][1] * 0.85 - 0.04 * t
                h = 0.14 - 0.06 * t
                self.part("mane", C.bm_xform(C.bm_cyl(5, 0.06, 0.0, h), loc=(0, y, z + h * 0.4),
                          rot=(0.5, 0, 0), scale=(0.6, 1.0, 1.0)), "fur_dark", torso, smooth=False)
            # rayures / taches plus sombres sur la croupe
            for sx in (1, -1):
                for k in range(3):
                    y = L * (0.05 + 0.12 * k)
                    self.part("stripe", C.bm_xform(C.bm_box(0.012, 0.035, 0.12),
                              loc=(A["rump"][0] * 0.98 * sx, y, (A["hips"] - self.HM) + 0.02),
                              rot=(0.3, 0, 0)), "fur_dark", torso)
        if A.get("harness"):
            for yy in (-L * 0.30, -L * 0.05):
                zc = (A["withers"] - self.HM) - 0.03
                pts = [(math.cos(2 * math.pi * k / 24) * A["chest"][0] * 1.0, yy,
                        zc + math.sin(2 * math.pi * k / 24) * A["chest"][1] * 0.92) for k in range(25)]
                self.part("harness", C.bm_tube(pts, [0.022] * 25, seg=6, flat=0.5, up=(0, 1, 0)), "leather", torso)
            self.part("harnessBack", C.bm_xform(C.bm_box(0.06, L * 0.30, 0.03, bevel=0.01),
                      loc=(0, -L * 0.18, A["withers"] - self.HM + A["chest"][1] * 0.95)), "leather", torso)
            self.part("harnessRing", C.bm_xform(C.bm_torus(12, 4, 0.035, 0.01),
                      loc=(0, -L * 0.18, A["withers"] - self.HM + A["chest"][1] * 1.02), rot=(math.pi / 2, 0, 0)),
                      "brass", torso)

    def build_head(self, head) -> None:
        A, j = self.A, self.j
        hr = A["head"]
        sk = C.bm_sphere(16, 12, 1.0)
        C.bm_xform(sk, loc=(0, 0, 0), scale=(hr * 0.95, hr * 1.05, hr * 0.85))
        self.part("skull", sk, "fur", head)
        sl, sr = A["snout"], A["snout_r"]
        # museau (dessus) : cône effilé vers l'avant
        snout = C.bm_tube([(0, -hr * 0.55, -hr * 0.05), (0, -hr * 0.55 - sl * 0.6, -hr * 0.12),
                           (0, -hr * 0.55 - sl, -hr * 0.18)], [sr * 1.25, sr * 1.0, sr * 0.78], seg=12, flat=0.8)
        self.part("snout", snout, "muzzle" if A.get("dark_snout", True) else "fur", head)
        self.part("nose", C.bm_xform(C.bm_sphere(10, 6, 1.0), loc=(0, -hr * 0.55 - sl - 0.005, -hr * 0.13),
                  scale=(sr * 0.65, sr * 0.45, sr * 0.45)), "nose", head)
        # mâchoire inférieure (articulée)
        j["jaw"] = jaw = joint("jaw", head, (0, -hr * 0.45, -hr * 0.40))
        jl = sl + hr * 0.10
        self.part("jawMesh", C.bm_tube([(0, 0.0, 0.0), (0, -jl * 0.6, -0.01), (0, -jl, 0.0)],
                                       [sr * 0.95, sr * 0.75, sr * 0.55], seg=10, flat=0.55), "muzzle", jaw)
        if A.get("teeth"):
            self.part("tongue", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, -jl * 0.5, 0.02),
                      scale=(sr * 0.55, jl * 0.38, 0.012)), "tongue", jaw)
            for sx in (1, -1):
                # crocs du haut (dans la tête) et du bas (mâchoire)
                self.part("fangU", C.bm_xform(C.bm_cyl(6, 0.014, 0.0, 0.05),
                          loc=(sr * 0.55 * sx, -hr * 0.55 - sl * 0.85, -hr * 0.32), rot=(math.pi, 0, 0)), "teeth", head,
                          nofs=True)
                self.part("fangL", C.bm_xform(C.bm_cyl(6, 0.012, 0.0, 0.04),
                          loc=(sr * 0.45 * sx, -jl * 0.82, 0.03)), "teeth", jaw, nofs=True)
                for k in range(3):
                    self.part("tooth", C.bm_xform(C.bm_cyl(5, 0.008, 0.0, 0.025),
                              loc=(sr * 0.62 * sx, -hr * 0.55 - sl * (0.25 + 0.18 * k), -hr * 0.30),
                              rot=(math.pi, 0, 0)), "teeth", head, nofs=True)
        for sx in (1, -1):
            self.part("eye", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(hr * 0.48 * sx, -hr * 0.78, hr * 0.22),
                      scale=(0.022, 0.012, 0.016)), "eye", head, nofs=True)
            self.part("brow", C.bm_xform(C.bm_box(0.05, 0.02, 0.016, bevel=0.005),
                      loc=(hr * 0.46 * sx, -hr * 0.80, hr * 0.36), rot=(0, -0.45 * sx, 0)), "fur_dark", head)
            ears = A.get("ears")
            if ears == "round":
                ear = C.bm_sphere(10, 8, 1.0)
                C.bm_xform(ear, loc=(hr * 0.62 * sx, hr * 0.10, hr * 0.80), rot=(0.2, 0, 0.3 * sx),
                           scale=(0.065, 0.025, 0.075))
                self.part("ear", ear, "fur_dark", head)
            elif ears == "pointed":
                self.part("ear", C.bm_xform(C.bm_cyl(4, 0.05, 0.0, 0.13), loc=(hr * 0.55 * sx, hr * 0.05, hr * 0.92),
                          rot=(0.25, -0.25 * sx, 0), scale=(1.0, 0.45, 1.0)), "fur_dark", head, smooth=False)
        if A.get("collar") == "spiked":
            neck = self.j["neck"]
            nr = A["neck_r"] * 1.12
            nl = A["neck"]
            col = C.bm_cyl(18, nr + 0.018, nr + 0.018, 0.06)
            C.bm_xform(col, loc=(0, -nl * 0.45, nl * 0.30), rot=(-0.95, 0, 0))
            self.part("collar", col, "leather", neck)
            for k in range(8):
                a = 2 * math.pi * k / 8
                d = Vector((math.cos(a), 0, math.sin(a)))
                rot_d = Vector((d.x, d.z * math.sin(0.95), d.z * math.cos(0.95)))
                base = Vector((0, -nl * 0.45, nl * 0.30)) + rot_d * (nr + 0.02)
                spike = C.bm_cyl(6, 0.016, 0.0, 0.06)
                q = Vector((0, 0, 1)).rotation_difference(rot_d)
                C.bm_xform(spike, loc=(0, 0, 0.03))
                import bmesh
                bmesh.ops.rotate(spike, cent=(0, 0, 0), matrix=q.to_matrix(), verts=spike.verts)
                bmesh.ops.translate(spike, vec=base, verts=spike.verts)
                self.part("spike", spike, "metal", neck, smooth=False, nofs=True)

    def build_legs(self, torso) -> None:
        A, j = self.A, self.j
        L = A["length"]
        lr = A["leg_r"]
        for end, (ya, za, segs, key) in (("F", (-L * 0.36, A["withers"] - self.HM - 0.06, A["front_leg"], "fur")),
                                         ("H", (L * 0.34, A["hips"] - self.HM - 0.02, A["hind_leg"], "fur"))):
            for side, sx in (("L", 1), ("R", -1)):
                w = (A["chest"][0] if end == "F" else A["rump"][0]) * 0.62
                n = end + side
                j0 = j["l0" + n] = joint("l0" + n, torso, (w * sx, ya, za))
                a, b, c = segs
                thick = 1.35 if end == "H" else 1.15
                self.part("upper" + n, C.bm_xform(C.bm_cyl(10, lr * thick * 1.25, lr * 1.0, a + 0.04),
                          loc=(0, 0, -a / 2)), key, j0)
                if end == "H":  # cuisse musclée
                    self.part("thigh" + n, C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, 0.01, -a * 0.25),
                              scale=(lr * 1.7, lr * 2.3, a * 0.55)), key, j0)
                else:
                    self.part("shoulderM" + n, C.bm_xform(C.bm_sphere(10, 8, 1.0), loc=(0, 0, -a * 0.15),
                              scale=(lr * 1.5, lr * 1.9, a * 0.45)), key, j0)
                j1 = j["l1" + n] = joint("l1" + n, j0, (0, 0, -a))
                self.part("lower" + n, C.bm_xform(C.bm_cyl(10, lr * 0.95, lr * 0.75, b + 0.03), loc=(0, 0, -b / 2)),
                          "fur_dark" if A.get("dark_legs") else key, j1)
                j2 = j["l2" + n] = joint("l2" + n, j1, (0, 0, -b))
                self.part("pastern" + n, C.bm_xform(C.bm_cyl(8, lr * 0.75, lr * 0.70, c + 0.02), loc=(0, 0, -c / 2)),
                          "fur_dark", j2)
                if A.get("hooves"):
                    self.part("hoof" + n, C.bm_xform(C.bm_cyl(10, lr * 0.95, lr * 1.10, 0.06), loc=(0, -0.01, -c - 0.01)),
                              "horn" if A.get("pale_hooves") else "nose", j2)
                else:
                    paw = C.bm_sphere(10, 6, 1.0)
                    C.bm_xform(paw, loc=(0, -0.025, -c - 0.005), scale=(lr * 1.05, lr * 1.45, lr * 0.65))
                    self.part("paw" + n, paw, "fur_dark", j2)
        self.rest_legs()

    def build_tail(self, tail) -> None:
        A = self.A
        t = A.get("tail")
        if t == "bushy":
            self.part("tailMesh", C.bm_tube([(0, 0, 0), (0, 0.10, -0.06), (0, 0.18, -0.16), (0, 0.22, -0.26)],
                                            [0.035, 0.05, 0.055, 0.02], seg=8), "fur_dark", tail)
        elif t == "thin":
            self.part("tailMesh", C.bm_tube([(0, 0, 0), (0, 0.10, 0.04), (0, 0.20, 0.06), (0, 0.28, 0.03)],
                                            [0.028, 0.024, 0.018, 0.006], seg=8), "fur", tail)
        elif t == "tuft":
            self.part("tailMesh", C.bm_tube([(0, 0, 0), (0, 0.06, -0.10), (0, 0.08, -0.24)],
                                            [0.022, 0.018, 0.012], seg=8), "fur_dark", tail)
            self.part("tailTuft", C.bm_xform(C.bm_sphere(8, 6, 1.0), loc=(0, 0.085, -0.29), scale=(0.035, 0.035, 0.07)),
                      "fur_dark", tail)

    # ------------------------------------------------------------------ poses
    REST = {"F": (0.08, -0.12, 0.10), "H": (-0.30, 0.62, -0.38)}

    def rest_legs(self) -> None:
        for end in ("F", "H"):
            for side in ("L", "R"):
                self.leg(end + side, 0.0, 0.0, 0.0)

    def leg(self, n: str, d0: float, d1: float, d2: float) -> None:
        r = self.REST[n[0]]
        self.j["l0" + n].rotation_euler = (r[0] + d0, 0, 0)
        self.j["l1" + n].rotation_euler = (r[1] + d1, 0, 0)
        self.j["l2" + n].rotation_euler = (r[2] + d2, 0, 0)

    def rest(self) -> None:
        j = self.j
        j["body"].location = (0, 0, 0)
        j["body"].rotation_euler = (0, 0, 0)
        j["torso"].location = (0, 0, self.HM)
        j["torso"].rotation_euler = (0, 0, 0)
        j["torso"].scale = (1, 1, 1)
        j["neck"].rotation_euler = (self.A.get("head_down", 0.0), 0, 0)
        j["head"].rotation_euler = (-self.A.get("head_down", 0.0) * 0.4, 0, 0)
        j["jaw"].rotation_euler = (self.A.get("jaw_idle", 0.0), 0, 0)
        j["tail"].rotation_euler = (0, 0, 0)
        self.rest_legs()

    def pose_idle(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        t = 2 * math.pi * i / n
        b = math.sin(t)
        j["torso"].location.z = self.HM - 0.008 * (1 - b)
        j["torso"].scale = (1 + 0.025 * b, 1.0, 1 + 0.025 * b)
        hd = self.A.get("head_down", 0.0)
        j["neck"].rotation_euler = (hd + 0.04 * b, 0, 0.12 * math.sin(t * 0.5 + 0.4))
        j["head"].rotation_euler = (-hd * 0.4 - 0.03 * b, 0, 0.10 * math.sin(t * 0.5))
        j["jaw"].rotation_euler = (self.A.get("jaw_idle", 0.0) + 0.06 * max(0.0, b), 0, 0)
        j["tail"].rotation_euler = (0.05 * b, 0, 0.30 * math.sin(t))
        self.leg("FL", -0.03, 0, 0.0)
        self.leg("HR", 0.05, 0.03, 0.0)

    PHASE = {"FL": 0.0, "FR": 0.12, "HL": 0.52, "HR": 0.64}

    def pose_run(self, i: int, n: int) -> None:
        self.rest()
        j, A = self.j, self.A
        p = i / n
        heavy = A.get("heavy", 0.0)
        amp = 0.75 - 0.25 * heavy
        for leg, ph in self.PHASE.items():
            a = 2 * math.pi * (p + ph)
            s, c = math.sin(a), math.cos(a)
            lift = max(0.0, c)
            if leg[0] == "F":
                self.leg(leg, -amp * s, 0.25 + 0.95 * lift, 0.25 * lift)
            else:
                self.leg(leg, -amp * 0.9 * s, 0.35 * lift, -0.55 * lift)
        a = 2 * math.pi * p
        j["torso"].location.z = self.HM + (0.035 - 0.015 * heavy) * math.sin(2 * a + 0.6) - 0.02
        j["torso"].rotation_euler = (0.07 * math.sin(a + 0.8), 0, 0)
        hd = A.get("head_down", 0.0)
        j["neck"].rotation_euler = (hd * 0.6 + 0.10 - 0.08 * math.sin(a + 0.8), 0, 0)
        j["head"].rotation_euler = (-0.05, 0, 0)
        j["jaw"].rotation_euler = (A.get("jaw_idle", 0.0) + 0.12, 0, 0)
        j["tail"].rotation_euler = (-0.35 + 0.15 * math.sin(a), 0, 0.1 * math.sin(a))

    def pose_attack(self, i: int, n: int) -> None:
        self.rest()
        j, A = self.j, self.A
        # 0-2 ramassé (2 = tenue), 3 bond gueule ouverte, 4 morsure + secousse, 5 retour
        by = (0.03, 0.06, 0.07, -0.26, -0.24, -0.08)[i]
        bz = (-0.02, -0.05, -0.06, 0.02, -0.01, -0.01)[i]
        pitch = (0.04, 0.10, 0.12, -0.10, 0.04, 0.02)[i]
        sc = A["scale"]
        j["body"].location = (0, by * sc, 0)
        j["torso"].location.z = self.HM + bz
        j["torso"].rotation_euler = (pitch, 0, 0)
        hd = A.get("head_down", 0.0)
        j["neck"].rotation_euler = (hd + (0.15, 0.30, 0.32, -0.05, 0.10, 0.10)[i], 0,
                                    (0, 0, 0, 0, 0.22, 0)[i])
        j["head"].rotation_euler = ((-0.10, -0.20, -0.22, -0.15, 0.05, 0.0)[i], 0, (0, 0, 0, 0, -0.25, 0)[i])
        j["jaw"].rotation_euler = ((0.30, 0.45, 0.50, 0.85, 0.05, 0.20)[i], 0, 0)
        j["tail"].rotation_euler = ((-0.1, -0.25, -0.3, -0.5, -0.4, -0.2)[i], 0, 0)
        fr = (-0.05, 0.10, 0.12, -0.85, -0.55, -0.15)[i]
        hr = (0.0, 0.10, 0.12, 0.65, 0.40, 0.10)[i]
        crouch = (0.15, 0.30, 0.35, 0.0, 0.10, 0.10)[i]
        for side in ("L", "R"):
            self.leg("F" + side, fr, crouch * 1.2 + (0.4 if i == 3 else 0.0), 0.0)
            self.leg("H" + side, hr - crouch * 0.6, crouch * 1.3, -crouch * 0.8)

    def pose_hit(self, i: int, n: int) -> None:
        self.rest()
        j = self.j
        k = (1.0, 0.6, 0.25)[i]
        j["body"].location = (0, 0.05 * k, 0)
        j["torso"].rotation_euler = (-0.08 * k, 0, 0.06 * k)
        j["neck"].rotation_euler = (self.A.get("head_down", 0.0) - 0.35 * k, 0, 0.15 * k)
        j["jaw"].rotation_euler = (0.25 * k + 0.05, 0, 0)
        j["tail"].rotation_euler = (0.4 * k, 0, 0)
        for side in ("L", "R"):
            self.leg("F" + side, 0.15 * k, 0.1 * k, 0)
            self.leg("H" + side, -0.05 * k, 0.15 * k, -0.1 * k)

    def pose_death(self, i: int, n: int) -> None:
        """Chute sur le flanc, pattes molles ; dernière image = cadavre en travers de l'écran."""
        self.rest()
        j, A = self.j, self.A
        t = i / (n - 1)
        u = min(1.0, max(0.0, (t - 0.12) / 0.62))
        e = u * u * (3 - 2 * u)
        bounce = 0.0
        if t > 0.75:
            v = (t - 0.75) / 0.25
            bounce = 0.07 * math.sin(v * math.pi) * (1 - v)
        roll = (math.pi / 2 - 0.12) * e - bounce
        tau = corpse_twist(self.dir_ang) * min(1.0, e * 1.3)
        side_sign = 1.0
        sc = A["scale"]
        j["body"].rotation_euler = (0, side_sign * roll, tau)
        j["body"].location = (0, 0, A["chest"][0] * 0.85 * sc * math.sin(roll))
        j["torso"].location.z = self.HM - 0.05 * min(1.0, t * 4)
        j["neck"].rotation_euler = (A.get("head_down", 0.0) + 0.5 * e - 0.35 * (1 - e) * min(1.0, t * 5), 0,
                                    -0.25 * e)
        j["head"].rotation_euler = (0.2 * e, 0, 0)
        j["jaw"].rotation_euler = (0.35 * min(1.0, t * 3) * (1 - 0.4 * e), 0, 0)
        j["tail"].rotation_euler = (0.6 * e, 0, 0)
        for leg in ("FL", "FR", "HL", "HR"):
            up = leg[1] == "L"
            sp = (0.25 if up else -0.1) * e
            self.leg(leg, (-0.35 if leg[0] == "F" else 0.35) * e + sp, 0.3 * e * (1 if up else 0.4), 0.0)

    def pose(self, anim: str, i: int, n: int) -> None:
        getattr(self, "pose_" + anim)(i, n)

    def muzzle_world(self) -> Vector:
        bpy.context.view_layer.update()
        hr, sl = self.A["head"], self.A["snout"]
        return self.j["head"].matrix_world @ Vector((0, -hr * 0.55 - sl, -hr * 0.2))


def make(kind: str) -> Beast:
    return Beast(kind)
