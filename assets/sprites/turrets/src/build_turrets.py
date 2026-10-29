"""Tourelles murales (4 biomes x 3 types) en 3D « toon peint », même pipeline que les autres sprites
(art/blender/rdm_common.py : caméra orthographique plongée 48°, matériaux toon, contour Freestyle,
1 BU Blender = 36 unités monde, 2 px par unité monde).

Usage (depuis la racine du projet) :
    python3 assets/sprites/turrets/src/build_turrets.py                 # tout
    python3 assets/sprites/turrets/src/build_turrets.py far_west_burst  # une seule tourelle

Sorties dans assets/sprites/turrets/ :
  <biome>_<type>_base.png  : socle, 4 vignettes BASE_FRAME (ordre ORIENT : down, right, left, up = normale
                             du mur vers la salle, en coordonnées écran du jeu)
  <biome>_<type>_head.png  : tête, HEAD_FRAMES vignettes HEAD_FRAME en grille HEAD_COLS colonnes ;
                             vignette k = canon orienté à l'angle écran k * 360 / HEAD_FRAMES (0 = droite,
                             sens horaire, y vers le bas comme dans Godot)
  <biome>_<type>_wreck.png : épave noircie, 4 vignettes comme le socle (tête affaissée comprise)
  <biome>_<type>.json      : métadonnées (ancre au sol, pivot de la tête, bouche du canon par vignette)

Repère Blender : origine = point du mur au ras du sol (limite mur / salle), le mur est en +Y, la
salle en -Y (vers la caméra) pour l'orientation « down ». Les autres orientations tournent autour de Z.
"""
from __future__ import annotations

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "art", "blender"))
import rdm_common as C  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

OUT = os.path.abspath(os.path.join(HERE, ".."))
TMP = os.path.join(os.environ.get("RDM_TMP", "/tmp/rdm_decor"), "turrets")

ELEV = 48.0
PX_PER_BU = 88.0          # résolution du rendu (px par BU)
# Unités monde par BU dans le jeu : 45 (décor : 36) -> tourelles ~25 % plus grosses, lisibles sur mobile.
WORLD_PER_BU = 45.0
SS = 2                    # sur-échantillonnage
HEAD_FRAME = 192
HEAD_FRAMES = 32
HEAD_COLS = 8
BASE_FRAME = (192, 192)
# Normale du mur (vers la salle) -> rotation Z du modèle (le modèle « down » pointe vers -Y Blender).
ORIENT = [("down", 0.0), ("right", 90.0), ("left", -90.0), ("up", 180.0)]
# Hauteur du pivot de la tête (BU) : ~30 unités monde au-dessus du sol à l'écran.
PIVOT_Z = 1.22
ARM = 0.36                # saillie du bras (BU) depuis le mur

# ----------------------------------------------------------------------------- palettes par biome
# (base, ombre, lumière) hex sRGB. "glow" = couleur émissive (lentille, voyants).
BIOMES = {
    "far_west": {
        "plate": ("#6e4630", "#2e1e2a", "#9a6440"),      # planche sombre
        "arm": ("#3a3a48", "#16162a", "#6a6c80"),        # fer forgé
        "housing": ("#b07a4c", "#5a3a3a", "#e0a868"),    # bois
        "metal": ("#3a3a48", "#16162a", "#6a6c80"),
        "accent": ("#d0a040", "#6a4a3a", "#ffe08a"),     # laiton
        "barrel": ("#4a4a58", "#1a1a2c", "#8a8ea0"),
        "glow": "#ff3a20",
    },
    "space_station": {
        "plate": ("#4a5064", "#181c34", "#626c86"),
        "arm": ("#3a3e4e", "#12142a", "#4c5468"),
        "housing": ("#c4ccd8", "#6a7698", "#e2e8f2"),
        "metal": ("#4a5064", "#181c34", "#626c86"),
        "accent": ("#e8b830", "#6a4a30", "#ffe070"),
        "barrel": ("#3a3e4e", "#12142a", "#5c6478"),
        "glow": "#5ce6ff",
    },
    "mall": {
        "plate": ("#7a7e88", "#2e3046", "#a8acb8"),
        "arm": ("#4a4c56", "#1a1a2a", "#70747e"),
        "housing": ("#d8d4c8", "#7a7488", "#f4f0e4"),
        "metal": ("#3a3c44", "#141420", "#5c5e68"),
        "accent": ("#e8b830", "#6a4a30", "#ffe070"),
        "barrel": ("#2e2e36", "#0e0e1a", "#56566a"),
        "glow": "#ff3030",
    },
}
CHAR = ("#2c2428", "#120e18", "#4a3c3a")     # épave noircie
EMBER = "#ff6a20"

TYPES = ("burst", "cannon", "laser")

_mats: dict[str, object] = {}
_cur_biome = ""
_wreck = False


def M(key: str):
    """Matériau du biome courant (ou matériau calciné pour l'épave)."""
    name = ("wreck_" if _wreck else _cur_biome + "_") + key
    if name in _mats and name in bpy.data.materials:
        return _mats[name]
    pal = BIOMES[_cur_biome]
    if key == "glow":
        m = C.toon(name, EMBER if _wreck else pal["glow"], emit=1.0 if _wreck else 1.4)
    elif _wreck:
        b, s, l = CHAR
        if key in ("accent", "housing"):
            b, s, l = "#3a2e2c", "#141018", "#5a4840"
        m = C.toon(name, b, s, l, rim=0.12)
    else:
        b, s, l = pal[key]
        m = C.toon(name, b, s, l, rim=0.28)
    _mats[name] = m
    return m


class Parts:
    def __init__(self, parent=None):
        self.objs = []
        self.parent = parent

    def add(self, name, bm, mat, smooth=True):
        ob = C.mesh_obj(name, bm, mat, smooth=smooth, parent=self.parent)
        self.objs.append(ob)
        return ob

    def box(self, name, size, loc, mat, rot=(0, 0, 0), bevel=0.0):
        bm = C.bm_box(*size, bevel=bevel, segs=1)
        C.bm_xform(bm, loc=loc, rot=rot)
        return self.add(name, bm, mat, smooth=False)

    def cyl(self, name, r1, r2, depth, loc, mat, rot=(0, 0, 0), seg=14):
        bm = C.bm_cyl(seg, r1, r2, depth)
        C.bm_xform(bm, loc=loc, rot=rot)
        return self.add(name, bm, mat)

    def sphere(self, name, r, loc, mat, scale=(1, 1, 1), seg=14, rings=9):
        bm = C.bm_sphere(seg, rings, r)
        C.bm_xform(bm, loc=loc, scale=scale)
        return self.add(name, bm, mat)


ROT_X = (0.0, math.pi / 2, 0.0)   # cylindre couché le long de X


# ----------------------------------------------------------------------------- socles

def build_mount(P: Parts, biome: str, wall_face: bool = True) -> None:
    """Socle. wall_face=True (mur HAUT, vu de face en 3/4) : platine verticale fixée au mur (plan
    y = 0), bras vers la salle (-Y). False (murs gauche/droite/bas, vus de dessus) : embase posée
    sur le dessus du mur (y > 0) et fût vertical qui porte la tête au-dessus de l'arête."""
    z = PIVOT_Z
    if not wall_face:
        _build_pedestal(P, biome)
    elif biome == "far_west":
        # Planche de fond + ferrures + console en fer forgé
        for i, dx in enumerate((-0.17, 0.0, 0.17)):
            P.box("plank%d" % i, (0.16, 0.07, 0.78), (dx, -0.035, z - 0.12), M("plate"), bevel=0.012)
        for i, dz in enumerate((z + 0.12, z - 0.38)):
            P.box("strap%d" % i, (0.56, 0.085, 0.06), (0, -0.045, dz), M("arm"))
        P.box("arm", (0.12, ARM, 0.08), (0, -ARM / 2 - 0.06, z - 0.16), M("arm"))
        P.box("brace", (0.07, 0.07, 0.5), (0, -0.2, z - 0.36), M("arm"), rot=(math.radians(-38), 0, 0))
    elif biome == "space_station":
        P.box("plate", (0.6, 0.08, 0.7), (0, -0.04, z - 0.12), M("plate"), bevel=0.04)
        P.box("panel", (0.42, 0.04, 0.46), (0, -0.09, z - 0.12), M("housing"), bevel=0.02)
        P.box("strip", (0.32, 0.03, 0.04), (0, -0.115, z - 0.38), M("glow"))
        P.box("arm", (0.18, ARM, 0.12), (0, -ARM / 2 - 0.08, z - 0.16), M("arm"), bevel=0.02)
    elif biome == "mall":
        P.box("plate", (0.56, 0.07, 0.62), (0, -0.035, z - 0.12), M("plate"), bevel=0.03)
        for i in range(4):
            P.box("haz%d" % i, (0.09, 0.075, 0.14), (-0.2 + i * 0.13, -0.045, z - 0.38), M("accent"),
                  rot=(0, math.radians(30), 0))
        P.box("arm", (0.14, ARM, 0.1), (0, -ARM / 2 - 0.07, z - 0.16), M("arm"), bevel=0.015)
        P.cyl("cam_box", 0.05, 0.05, 0.1, (0.2, -0.1, z + 0.1), M("glow"), rot=(math.pi / 2, 0, 0), seg=10)
    # Couronne d'orientation sous la tête
    P.cyl("ring", 0.2, 0.17, 0.1, (0, -ARM - 0.04, z - 0.15), M("metal"), seg=20)


def _build_pedestal(P: Parts, biome: str) -> None:
    """Embase sur le dessus du mur + fût + console jusque sous la tête."""
    z = PIVOT_Z
    hy = -ARM - 0.04                      # aplomb de la tête (dans la salle)
    if biome == "far_west":
        P.box("foot", (0.5, 0.42, 0.08), (0, 0.16, 0.04), M("plate"), bevel=0.015)
        P.box("post", (0.12, 0.12, z - 0.2), (0, 0.06, (z - 0.2) / 2), M("plate"), bevel=0.01)
        P.box("strap", (0.16, 0.16, 0.05), (0, 0.06, 0.5), M("arm"))
        P.box("arm", (0.1, 0.06 - hy, 0.08), (0, (0.06 + hy) / 2, z - 0.24), M("arm"))
        P.box("brace", (0.06, 0.06, 0.42), (0, -0.12, z - 0.42), M("arm"), rot=(math.radians(-40), 0, 0))
    else:
        P.box("foot", (0.46, 0.4, 0.08), (0, 0.15, 0.04), M("plate"), bevel=0.02)
        P.box("post", (0.14, 0.14, z - 0.2), (0, 0.06, (z - 0.2) / 2), M("arm"), bevel=0.02)
        P.box("arm", (0.14, 0.06 - hy, 0.1), (0, (0.06 + hy) / 2, z - 0.24), M("arm"), bevel=0.02)
        P.box("lamp", (0.03, 0.03, 0.18), (0.075, 0.06, 0.5), M("glow" if biome == "space_station" else "accent"))


# ----------------------------------------------------------------------------- têtes (canon vers +X)

def build_head(P: Parts, biome: str, kind: str) -> float:
    """Construit la tête autour de l'origine (pivot). Renvoie la longueur du canon (x de la bouche)."""
    fw = biome == "far_west"
    if kind == "burst":
        P.box("housing", (0.4, 0.34, 0.26), (0.0, 0, 0.0), M("housing"), bevel=0.04)
        P.box("top", (0.26, 0.24, 0.06), (-0.02, 0, 0.15), M("metal"), bevel=0.02)
        n = 6 if fw else 2
        L = 0.62
        for i in range(n):
            if n == 2:
                y, zz = (-0.07 if i == 0 else 0.07), 0.0
            else:
                a = 2 * math.pi * i / n
                y, zz = 0.06 * math.cos(a), 0.06 * math.sin(a)
            P.cyl("barrel%d" % i, 0.028, 0.028, L, (0.2 + L / 2, y, zz), M("barrel"), rot=ROT_X, seg=8)
        P.cyl("muzzle_ring", 0.11 if fw else 0.05, 0.11 if fw else 0.05, 0.05, (0.2 + L - 0.04, 0, 0),
              M("accent"), rot=ROT_X, seg=14)
        if n == 2:
            P.cyl("muzzle_ring2", 0.05, 0.05, 0.05, (0.2 + L - 0.04, 0.07, 0), M("accent"), rot=ROT_X, seg=12)
            P.cyl("muzzle_ring1", 0.05, 0.05, 0.05, (0.2 + L - 0.04, -0.07, 0), M("accent"), rot=ROT_X, seg=12)
        P.box("drum", (0.18, 0.12, 0.18), (-0.04, -0.23, -0.02), M("accent"), bevel=0.02)
        if fw:
            P.cyl("crank", 0.025, 0.025, 0.18, (-0.1, 0.24, 0.0), M("metal"), rot=(math.pi / 2, 0, 0), seg=8)
        else:
            P.box("light", (0.04, 0.2, 0.03), (0.21, 0, 0.12), M("glow"))
        return 0.2 + L
    if kind == "cannon":
        P.box("cradle", (0.4, 0.4, 0.2), (-0.04, 0, -0.08), M("metal"), bevel=0.03)
        P.sphere("breech", 0.2, (-0.12, 0, 0.04), M("housing"), seg=16, rings=10)
        L = 0.62
        P.cyl("barrel", 0.15, 0.115, L, (0.0 + L / 2, 0, 0.04), M("housing" if fw else "barrel"), rot=ROT_X, seg=18)
        P.cyl("band1", 0.16, 0.16, 0.05, (0.12, 0, 0.04), M("accent"), rot=ROT_X, seg=18)
        P.cyl("muzzle", 0.145, 0.16, 0.08, (L - 0.02, 0, 0.04), M("accent"), rot=ROT_X, seg=18)
        if not fw:
            P.cyl("coil", 0.13, 0.13, 0.08, (0.32, 0, 0.04), M("glow"), rot=ROT_X, seg=16)
        return L + 0.02
    # laser : corps fin, long canon, lunette, lentille lumineuse
    P.box("body", (0.38, 0.22, 0.2), (0.0, 0, 0.0), M("housing"), bevel=0.03)
    L = 0.78
    P.cyl("barrel", 0.04, 0.035, L, (0.16 + L / 2, 0, 0.0), M("barrel"), rot=ROT_X, seg=10)
    P.cyl("scope", 0.055, 0.055, 0.34, (0.04, 0, 0.16), M("metal" if not fw else "accent"), rot=ROT_X, seg=12)
    P.cyl("lens_s", 0.045, 0.045, 0.02, (0.215, 0, 0.16), M("glow"), rot=ROT_X, seg=12)
    P.cyl("tip", 0.06, 0.06, 0.05, (0.16 + L - 0.02, 0, 0.0), M("accent"), rot=ROT_X, seg=12)
    P.cyl("lens", 0.035, 0.035, 0.02, (0.16 + L + 0.005, 0, 0.0), M("glow"), rot=ROT_X, seg=12)
    return 0.16 + L


# ----------------------------------------------------------------------------- rendu

def _render(path: str, size: tuple[int, int], target, outline: float = 4.0) -> object:
    C.setup_render((size[0] * SS, size[1] * SS), samples=3, outline_px=outline, inner_ratio=0.45)
    cam = C.ortho_camera(ELEV, max(size) / PX_PER_BU, target=target, dist=30.0)
    C.render_to(path)
    return cam


def _proj(cam, co) -> list[float]:
    p = C.world_to_px(cam, co)
    return [round(p[0] / SS, 1), round(p[1] / SS, 1)]


def build_one(biome: str, kind: str) -> None:
    global _cur_biome, _wreck
    from PIL import Image
    _cur_biome = biome
    os.makedirs(TMP, exist_ok=True)
    name = "%s_%s" % (biome, kind)
    big = os.path.join(TMP, name + ".big.png")
    meta = {"head_frame": HEAD_FRAME, "head_frames": HEAD_FRAMES, "head_cols": HEAD_COLS,
            "base_frame": list(BASE_FRAME), "orient": [o[0] for o in ORIENT],
            "world_per_px": round(WORLD_PER_BU / PX_PER_BU, 4), "arm_world": round((ARM + 0.04) * WORLD_PER_BU, 1),
            "anchor": [], "pivot": [], "front": [], "muzzle": [], "barrel_world": 0.0}
    pivot = Vector((0, -ARM - 0.04, PIVOT_Z))

    # --- Tête : HEAD_FRAMES rotations, caméra centrée sur le pivot
    sheet = Image.new("RGBA", (HEAD_FRAME * HEAD_COLS, HEAD_FRAME * (HEAD_FRAMES // HEAD_COLS)), (0, 0, 0, 0))
    for k in range(HEAD_FRAMES):
        _wreck = False
        C.reset_scene()
        _mats.clear()
        root = C.empty("head", (0, 0, 0))
        P = Parts(root)
        L = build_head(P, biome, kind)
        # Vignette k = canon à l'angle ÉCRAN th (y vers le bas). Le sol est raccourci de sin(48°)
        # verticalement : angle monde Blender a tel que la projection du canon tombe sur th.
        th = 2 * math.pi * k / HEAD_FRAMES
        a = math.atan2(-math.sin(th) / math.sin(math.radians(ELEV)), math.cos(th))
        root.rotation_euler = (0, 0, a)
        cam = _render(big, (HEAD_FRAME, HEAD_FRAME), (0, 0, 0), outline=4.0)
        im = C.downscale(big, None, (HEAD_FRAME, HEAD_FRAME))
        im = FP_paint(im)
        sheet.alpha_composite(im, ((k % HEAD_COLS) * HEAD_FRAME, (k // HEAD_COLS) * HEAD_FRAME))
        bpy.context.view_layer.update()
        tip = Vector((L * math.cos(a), L * math.sin(a), 0.0))
        meta["muzzle"].append(_proj(cam, tip))
        if k == 0:
            meta["head_pivot"] = _proj(cam, (0, 0, 0))
            meta["barrel_world"] = round(L * WORLD_PER_BU, 1)
    sheet.save(os.path.join(OUT, name + "_head.png"))

    # --- Socle et épave : 4 orientations
    for wreck in (False, True):
        _wreck = wreck
        strip = Image.new("RGBA", (BASE_FRAME[0] * 4, BASE_FRAME[1]), (0, 0, 0, 0))
        for i, (oname, rz) in enumerate(ORIENT):
            C.reset_scene()
            _mats.clear()
            root = C.empty("mount", (0, 0, 0))
            P = Parts(root)
            build_mount(P, biome, wall_face=(oname == "down"))
            if wreck:
                # Tête affaissée vers le sol, légèrement de travers, + quelques braises
                hroot = C.empty("head", tuple(pivot + Vector((0, 0, -0.1))), parent=root)
                build_head(Parts(hroot), biome, kind)
                hroot.rotation_euler = (math.radians(14), math.radians(42), math.radians(-90 + 18))
                for j, (ex, ez) in enumerate(((0.12, PIVOT_Z - 0.1), (-0.15, PIVOT_Z - 0.32), (0.05, PIVOT_Z + 0.05))):
                    C.mesh_obj("ember%d" % j, C.bm_xform(C.bm_sphere(8, 5, 0.035), loc=(ex, -0.12, ez)),
                               M("glow"), parent=root)
            root.rotation_euler = (0, 0, math.radians(rz))
            target = (0, -0.1, PIVOT_Z * 0.6)
            cam = _render(big, BASE_FRAME, target, outline=4.5)
            im = FP_paint(C.downscale(big, None, BASE_FRAME))
            strip.alpha_composite(im, (i * BASE_FRAME[0], 0))
            if not wreck:
                bpy.context.view_layer.update()
                rot = root.matrix_world
                meta["anchor"].append(_proj(cam, (0, 0, 0)))
                meta["pivot"].append(_proj(cam, rot @ pivot))
                meta["front"].append(_proj(cam, rot @ Vector((pivot.x, pivot.y, 0.0))))
        strip.save(os.path.join(OUT, name + ("_wreck.png" if wreck else "_base.png")))
    if os.path.exists(big):
        os.remove(big)
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(meta, f, indent=1)
    print("TURRET", name, flush=True)


def FP_paint(im):
    """Léger grain « peint » (comme build_props._paint), alpha intact."""
    import numpy as np
    from PIL import Image
    a = np.asarray(im).astype(np.float32)
    h, w = a.shape[:2]
    rng = np.random.default_rng(h * 31 + w)
    lo = rng.standard_normal((h // 6 + 2, w // 6 + 2)).astype(np.float32)
    lo = np.asarray(Image.fromarray(lo).resize((w, h), Image.BICUBIC))
    fine = rng.standard_normal((h, w)).astype(np.float32)
    k = 1.0 + lo[..., None] * 0.03 + fine[..., None] * 0.015
    a[..., :3] = np.clip(a[..., :3] * k, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def main() -> None:
    only = sys.argv[1:]
    for b in BIOMES:
        for t in TYPES:
            if only and ("%s_%s" % (b, t)) not in only:
                continue
            build_one(b, t)


if __name__ == "__main__":
    main()
