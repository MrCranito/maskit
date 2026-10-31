"""Trappe d'extraction d'urgence en 3D « toon peint » (même pipeline, même angle et mêmes
matériaux que les conteneurs de build_containers.py), FERMÉE et OUVERTE, + icône de la clef de
trappe.

Modèle (référence : trappe d'extraction de la planche, sans hélicoptère, tout en vert) :
dalle de béton, cadre à bandes de danger vert et noir, trappe métallique à deux battants
(ouverte : échelle qui descend dans le puits), feux verts aux coins, panneau lumineux à deux
chevrons verts pointés vers la trappe, encadré de deux lanternes vertes.

Usage (depuis la racine du projet ; Pillow absent du Python de Blender → PRERENDER_PYPATH) :
    PRERENDER_PYPATH=<site-packages avec PIL> blender -b --factory-startup \
        --python tools/prerender/blender_run.py -- art/blender/build_hatch.py

Sorties : assets/sprites/extraction/hatch.png, hatch_open.png, hatch_key_icon.png
          + hatch.json : { "hatch" / "hatch_open" / "hatch_key_icon" : {feet: [x, y], size: [w, h]} } (px).
Échelle : 2 px par unité monde ; ExtractionZone.HatchSprite affiche ces images à l'échelle 0,5 et
place le point d'appui (feet = centre de la trappe) sur le centre de la zone (bloc 2×2 cases).
Repère : (0, 0, 0) = centre de la trappe au sol, face avant vers -Y, z vers le haut.
"""
from __future__ import annotations

import json
import math
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_props as P  # noqa: E402
import rdm_common as C  # noqa: E402

M = P.M
Builder = P.Builder
ROOT = P.ROOT
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "extraction")
TMP = os.environ.get("RDM_TMP", "/tmp/rdm_hatch")

# Vert de l'extraction (ExtractionZone.COL ≈ #4dff9e) : peinture, lueurs.
GREEN = "#3fe08a"


def concrete():
    return C.toon("hatch_concrete", "#8e8a86", "#3c3c54", "#c4bcb0", rim=0.25)


def green_paint():
    return C.toon("hatch_green", GREEN, "#145a4a", "#9cffc4", rim=0.3)


def stripe_black():
    return C.toon("hatch_black", "#1e2026", "#0c0c18", "#3a3c46", rim=0.2)


def steel():
    return C.toon("hatch_steel", "#6e7486", "#262838", "#b4bccc", rim=0.3)


def steel_dark():
    return C.toon("hatch_steel_dark", "#3e4250", "#141624", "#6a7080", rim=0.25)


def pit():
    return C.toon("hatch_pit", "#0e1014", "#04040a", "#1c1e24", rim=0.0)


def glow_green(k: float = 1.6):
    return C.toon("hatch_glow%.1f" % k, "#6dffb0", emit=k)


# ----------------------------------------------------------------------------- pièces

HALF_IN = 1.05      # demi-côté de l'ouverture (BU) : 2,1 BU ≈ 76 unités monde
FRAME_W = 0.42      # largeur du cadre à bandes
SLAB = 2.05         # demi-côté de la dalle


def _slab(B: Builder) -> None:
    B.box("slab", (SLAB * 2, SLAB * 2, 0.1), (0, 0, 0.05), concrete(), bevel=0.03)
    # Joints de dalle (plaques de béton).
    for k in (-1, 1):
        B.box("joint_x%d" % k, (SLAB * 2 - 0.1, 0.035, 0.012), (0, k * (HALF_IN + FRAME_W + 0.28), 0.104), stripe_black(), shadow=False)
        B.box("joint_y%d" % k, (0.035, SLAB * 2 - 0.1, 0.012), (k * (HALF_IN + FRAME_W + 0.28), 0, 0.104), stripe_black(), shadow=False)


def _hazard_frame(B: Builder) -> None:
    """Cadre carré en bandes vert / noir (en biais) autour de l'ouverture."""
    z = 0.13
    outer = HALF_IN + FRAME_W
    n = 7
    seg = (outer * 2) / n
    for side in range(4):
        for i in range(n):
            t = -outer + seg * (i + 0.5)
            mat = green_paint() if (i + side) % 2 == 0 else stripe_black()
            if side in (0, 1):     # bas / haut : bande le long de X
                y = (-1 if side == 0 else 1) * (HALF_IN + FRAME_W / 2)
                B.box("hz%d_%d" % (side, i), (seg, FRAME_W, 0.06), (t, y, z), mat, bevel=0.005)
            else:                  # gauche / droite : bande le long de Y (coins exclus)
                if i == 0 or i == n - 1:
                    continue
                x = (-1 if side == 2 else 1) * (HALF_IN + FRAME_W / 2)
                B.box("hz%d_%d" % (side, i), (FRAME_W, seg, 0.06), (x, t, z), mat, bevel=0.005)
    # Rebord métallique intérieur.
    for k in (-1, 1):
        B.box("rim_x%d" % k, (HALF_IN * 2 + 0.12, 0.08, 0.1), (0, k * (HALF_IN + 0.02), 0.14), steel_dark())
        B.box("rim_y%d" % k, (0.08, HALF_IN * 2 + 0.12, 0.1), (k * (HALF_IN + 0.02), 0, 0.14), steel_dark())
    # Feux verts aux quatre coins.
    for sx in (-1, 1):
        for sy in (-1, 1):
            c = (sx * (outer + 0.12), sy * (outer + 0.12))
            B.cyl("lampbase%d%d" % (sx, sy), 0.11, 0.12, 0.08, (c[0], c[1], 0.14), steel_dark(), seg=10)
            B.sphere("lamp%d%d" % (sx, sy), 0.08, (c[0], c[1], 0.21), glow_green(1.8), seg=10, rings=6, shadow=False)


def _pit_and_ladder(B: Builder) -> None:
    """Puits (faux relief : fond sombre, parois en dégradé) et échelle qui y plonge."""
    B.box("pit", (HALF_IN * 2, HALF_IN * 2, 0.04), (0, 0, 0.1), pit(), shadow=False)
    # Parois intérieures (bande plus claire en haut de chaque bord : profondeur).
    for k in (-1, 1):
        B.box("wall_y%d" % k, (HALF_IN * 2, 0.16, 0.02), (0, k * (HALF_IN - 0.08), 0.125), steel_dark(), shadow=False)
        B.box("wall_x%d" % k, (0.16, HALF_IN * 2 - 0.32, 0.02), (k * (HALF_IN - 0.08), 0, 0.125), steel_dark(), shadow=False)
    # Lueur verte au fond du puits (sortie), au centre.
    B.box("pit_glow", (HALF_IN * 0.9, HALF_IN * 0.7, 0.01), (0, 0.15, 0.122), glow_green(0.45), shadow=False)
    # Échelle : montants qui partent du bord avant et filent vers le fond, barreaux de plus en
    # plus serrés et sombres (perspective).
    for sx in (-0.3, 0.3):
        B.box("rail%.2f" % sx, (0.07, HALF_IN * 1.7, 0.05), (sx, -0.05, 0.14), P.M("rust"), shadow=False)
        B.box("hook%.2f" % sx, (0.07, 0.22, 0.12), (sx, -HALF_IN - 0.02, 0.2), P.M("rust"), shadow=False)
    y = -HALF_IN + 0.2
    gap = 0.3
    for k in range(6):
        B.box("rung%d" % k, (0.6, 0.05, 0.04), (0, y, 0.15), P.M("iron" if k < 3 else "iron_dark"), shadow=False)
        y += gap
        gap *= 0.85


def _door(B: Builder, name: str, sx: int, opened: bool) -> None:
    """Battant (moitié gauche ou droite), charnière sur le bord extérieur ; ouvert : relevé."""
    w = HALF_IN
    d = HALF_IN * 2
    th = 0.07
    ang = math.radians(108) * sx if opened else 0.0
    hinge = (sx * HALF_IN, 0.0, 0.17)
    # Plaque + raidisseurs + poignée, définis par rapport à la charnière puis tournés autour de Y.
    parts = [
        ("plate", (w - 0.02, d - 0.04, th), (-sx * (w / 2), 0, 0), steel()),
        ("rib0", (w - 0.2, 0.08, 0.05), (-sx * (w / 2), -d * 0.28, th / 2 + 0.02), steel_dark()),
        ("rib1", (w - 0.2, 0.08, 0.05), (-sx * (w / 2), d * 0.28, th / 2 + 0.02), steel_dark()),
        ("stripe", (0.1, d - 0.2, 0.02), (-sx * (w - 0.12), 0, th / 2 + 0.01), green_paint()),
        ("handle", (0.08, 0.36, 0.06), (-sx * (w - 0.24), 0, th / 2 + 0.05), green_paint()),
    ]
    for pn, size, off, mat in parts:
        bm = C.bm_box(*size, bevel=0.01, segs=1)
        C.bm_xform(bm, loc=off)
        C.bm_xform(bm, loc=hinge, rot=(0, ang, 0))
        B.add("%s_%s" % (name, pn), bm, mat)
    for k in (-1, 1):
        B.cyl("%s_hinge%d" % (name, k), 0.05, 0.05, 0.26, (hinge[0], k * d * 0.3, hinge[2]), steel_dark(), rot=(math.pi / 2, 0, 0), seg=8)


def _sign(B: Builder) -> None:
    """Panneau lumineux à deux chevrons verts vers la trappe, encadré de deux lanternes."""
    y = SLAB - 0.35
    z0 = 0.55
    w, h = 1.7, 1.45
    for sx in (-1, 1):
        B.box("post%d" % sx, (0.12, 0.12, z0 + h), (sx * (w / 2 - 0.08), y, (z0 + h) / 2), steel_dark(), shadow=False)
    B.box("panel_frame", (w, 0.16, h), (0, y, z0 + h / 2), steel_dark(), bevel=0.02, shadow=False)
    B.box("panel_face", (w - 0.16, 0.04, h - 0.16), (0, y - 0.09, z0 + h / 2), stripe_black(), shadow=False)
    B.box("panel_glow", (w - 0.12, 0.02, h - 0.12), (0, y - 0.07, z0 + h / 2), glow_green(0.25), shadow=False)
    # Deux chevrons (V) pointés vers le bas, émissifs.
    for k, zc in enumerate((z0 + h * 0.66, z0 + h * 0.36)):
        for sx in (-1, 1):
            B.box("chev%d_%d" % (k, sx), (0.62, 0.05, 0.14), (sx * 0.24, y - 0.13, zc), glow_green(2.0),
                  rot=(0, math.radians(-32) * sx, 0), shadow=False)
    # Lanternes vertes sur potences.
    for sx in (-1, 1):
        lx = sx * (w / 2 + 0.38)
        B.box("arm%d" % sx, (0.4, 0.06, 0.06), (sx * (w / 2 + 0.2), y, z0 + h - 0.15), steel_dark(), shadow=False)
        B.cyl("lroof%d" % sx, 0.03, 0.17, 0.13, (lx, y, z0 + h - 0.2), P.M("iron"), seg=8, shadow=False)
        B.cyl("lglass%d" % sx, 0.12, 0.12, 0.3, (lx, y, z0 + h - 0.42), glow_green(1.7), seg=8, shadow=False)
        B.cyl("lbot%d" % sx, 0.14, 0.12, 0.05, (lx, y, z0 + h - 0.59), P.M("iron"), seg=8, shadow=False)


def build_hatch(B: Builder, opened: bool) -> None:
    _slab(B)
    _hazard_frame(B)
    if opened:
        _pit_and_ladder(B)
    _door(B, "doorL", -1, opened)
    _door(B, "doorR", 1, opened)
    _sign(B)


def build_key(B: Builder) -> None:
    """Clef de trappe : grosse clef d'acier à anneau, panneton, plaque verte à chevron."""
    # Posée à plat (vue presque de dessus) : anneau vert, tige et panneton d'acier.
    B.torus("bow", 0.26, 0.08, (-0.45, 0, 0.08), green_paint(), seg=28, rseg=8)
    B.cyl("bow_glow", 0.1, 0.1, 0.03, (-0.45, 0, 0.1), glow_green(1.6), seg=16, shadow=False)
    B.cyl("shaft", 0.07, 0.07, 0.8, (0.05, 0, 0.08), steel(), rot=(0, math.pi / 2, 0), seg=10)
    B.box("collar", (0.08, 0.2, 0.2), (-0.14, 0, 0.08), green_paint())
    for i, (x, hy) in enumerate(((0.3, 0.2), (0.42, 0.14))):
        B.box("bit%d" % i, (0.08, hy, 0.08), (x, -hy / 2 - 0.04, 0.08), steel())


# Nom → (fonction, cadre monde (l, h), hauteur visée BU, options render_piece)
PIECES = {
    "hatch": (lambda B: build_hatch(B, False), (210, 230), 0.9, {}),
    "hatch_open": (lambda B: build_hatch(B, True), (210, 230), 0.9, {}),
    "hatch_key_icon": (build_key, (52, 52), 0.0, {"shadow": False, "elev": 80.0, "outline_px": 3.0}),
}


def main() -> None:
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    P.PIECES = TMP
    os.makedirs(TMP, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    meta_path = os.path.join(OUT_DIR, "hatch.json")
    meta = {}
    if os.path.exists(meta_path):
        with open(meta_path) as f:
            meta = json.load(f)
    for name, (fn, frame, tz, opts) in PIECES.items():
        if only and name not in only:
            continue
        info = P.render_piece(name, fn, frame, target_z=tz, **opts)
        shutil.copy(os.path.join(TMP, name + ".png"), os.path.join(OUT_DIR, name + ".png"))
        meta[name] = {"feet": info["feet"], "size": info["size"]}
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=1, sort_keys=True)
    print("OK", len(meta), "images ->", OUT_DIR)


if __name__ == "__main__":
    main()
