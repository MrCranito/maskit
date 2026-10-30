"""Icônes peintes des objets du sac (data/items/*.tres hors armes), en 3D « toon peint » : même
pipeline que build_currency.py (matériaux toon, contour Freestyle, lumière chaude en haut à
gauche), puis composition PIL : contour sombre extérieur (lisible à 40 px sur mobile) et lueur
à la couleur de rareté (forte pour Épique et Légendaire).

Usage (depuis la racine du projet, Python du système avec PIL) :
    python art/blender/build_item_icons.py                     # tout
    python art/blender/build_item_icons.py --only whisky,medkit
    BLENDER=".../blender.exe" python art/blender/build_item_icons.py

Sorties : assets/ui/items/<id>.png (192 x 192, transparent), lues en priorité par
LootVisuals.item_icon (repli sur l'icône SVG de l'objet si l'image manque).
Repère : z vers le haut, face vers -Y (caméra), lumière en haut à gauche.
"""
from __future__ import annotations

import math
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "ui", "items")
TMP = os.environ.get("RDM_TMP", os.path.join(tempfile.gettempdir(), "rdm_items"))
BLENDER = os.environ.get("BLENDER", "C:/Users/victo/AppData/Local/Programs/blender-5.2.3-windows-x64/blender.exe")
SIZE = 192
SS = 2

# Couleurs de rareté (Commun gris, Peu commun vert, Rare bleu, Épique violet, Légendaire orange).
RARITY = ["#b8bcc8", "#5fd46a", "#4aa6ff", "#b46bff", "#ffa23a"]
GLOW = [0.0, 0.25, 0.35, 0.75, 0.95]

# id : (constructeur, paramètres, rareté)
ITEMS = {
    "bandage": ("bandage", {}, 0),
    "black_powder": ("sack", {"col": "dark", "tie": "cream", "small": True}, 0),
    "canned_beans": ("can", {"label": "#c8402e", "band": "#e8c060"}, 0),
    "cavalry_medal": ("medal", {"ribbon": "#2f5fb0", "metal": "gold"}, 2),
    "dynamite": ("dynamite", {}, 1),
    "gold_bar": ("bar", {}, 3),
    "gold_nugget": ("nugget", {"col": "gold"}, 1),
    "key_bank_vault": ("key", {"metal": "gold", "bow": "ring"}, 3),
    "key_hotel_suite": ("key", {"metal": "brass", "bow": "tag"}, 3),
    "key_mall_jewelry": ("keycard", {"col": "#d84a8a"}, 3),
    "key_mall_offices": ("keycard", {"col": "#3a7ad8"}, 3),
    "key_mine_vault": ("key", {"metal": "iron", "bow": "ring"}, 3),
    "key_saloon_suite": ("key", {"metal": "brass", "bow": "heart"}, 3),
    "key_sheriff_armory": ("key", {"metal": "silver", "bow": "star"}, 3),
    "key_space_armory": ("keycard", {"col": "#e0782e", "space": True}, 3),
    "key_space_lab": ("keycard", {"col": "#3ac8b0", "space": True}, 3),
    "key_space_reactor": ("keycard", {"col": "#e0c02e", "space": True}, 3),
    "lasso": ("lasso", {}, 0),
    "leather_holster": ("holster", {}, 0),
    "lockpicks": ("lockpicks", {}, 1),
    "mall_batteries": ("batteries", {}, 0),
    "mall_canned_food": ("can", {"label": "#3a8a4a", "band": "#f0e0b0"}, 0),
    "mall_cash_bundle": ("cash", {}, 1),
    "mall_diamond_necklace": ("necklace", {"bead": "silver", "gem": True}, 4),
    "mall_energy_drink": ("can", {"label": "#30c0e8", "band": "#101820", "tall": True}, 0),
    "mall_first_aid": ("kit", {"col": "white", "cross": "red"}, 2),
    "mall_game_console": ("console", {}, 2),
    "mall_gift_card": ("card", {"col": "#e05a8a", "stripe": "#ffd060"}, 0),
    "mall_gold_ring": ("ring", {}, 2),
    "mall_headphones": ("headphones", {}, 1),
    "mall_luxury_watch": ("wristwatch", {}, 3),
    "mall_painkillers": ("pills", {}, 1),
    "mall_perfume": ("perfume", {}, 1),
    "mall_smartphone": ("phone", {}, 1),
    "mat_chemicals": ("flask", {"liquid": "#7ad84a"}, 1),
    "mat_cloth": ("cloth", {}, 0),
    "mat_gears": ("gears", {}, 0),
    "mat_scrap": ("scrap", {}, 0),
    "medkit": ("kit", {"col": "red", "cross": "white"}, 2),
    "money_bag": ("sack", {"col": "cloth", "tie": "leather", "dollar": True}, 2),
    "pearl_necklace": ("necklace", {"bead": "pearl", "gem": False}, 3),
    "playing_cards": ("cards", {}, 0),
    "pocket_watch": ("pocketwatch", {}, 2),
    "raw_diamond": ("diamond", {}, 4),
    "revolver_ammo": ("bullets", {"long": False}, 0),
    "rifle_ammo": ("bullets", {"long": True}, 1),
    "sheriff_badge": ("star_badge", {}, 2),
    "silver_dollars": ("coins", {"metal": "silver"}, 0),
    "snake_oil": ("bottle", {"glass": "#3e9a5a", "label": "#e8d8b0", "shape": "round"}, 2),
    "space_antimatter": ("vial", {"glow": "#ff4ad8"}, 4),
    "space_circuit": ("circuit", {}, 0),
    "space_data_chip": ("chip", {}, 1),
    "space_encrypted_core": ("core", {}, 3),
    "space_energy_cell": ("cell", {"glow": "#4ae0ff", "big": False}, 0),
    "space_fusion_cell": ("cell", {"glow": "#ff9a2a", "big": True}, 2),
    "space_iridium": ("nugget", {"col": "iridium"}, 2),
    "space_medigel": ("tube", {}, 0),
    "space_nanomeds": ("injector", {}, 2),
    "space_officer_badge": ("shield_badge", {}, 1),
    "space_plasma_cells": ("plasma", {}, 0),
    "space_ration": ("ration", {}, 0),
    "space_servo": ("servo", {}, 1),
    "space_star_map": ("starmap", {}, 2),
    "treasure_map": ("map", {}, 3),
    "wanted_poster": ("poster", {}, 1),
    "whisky": ("bottle", {"glass": "#b8702a", "label": "#e8d8b0", "shape": "square"}, 1),
}

try:
    import bpy  # noqa: F401
    IN_BLENDER = True
except ImportError:
    IN_BLENDER = False


# =============================================================================== Blender
if IN_BLENDER:
    sys.path.insert(0, HERE)
    import bmesh  # noqa: E402
    from mathutils import Vector  # noqa: E402

    import build_currency as CUR  # noqa: E402
    import build_props as P  # noqa: E402
    import rdm_common as C  # noqa: E402

    M = P.M
    R = math.radians

    def T(name, base, shadow, lit, rim=0.3, emit=0.0):
        return C.toon("it_" + name, base, shadow, lit, rim=rim, emit=emit)

    MAT = {
        "gold": lambda: T("gold", "#eeaa2a", "#9a501c", "#ffd860", 0.4),
        "brass": lambda: T("brass", "#c99a3a", "#6a4a20", "#f0cc70", 0.35),
        "silver": lambda: T("silver", "#b8c0cc", "#4a5068", "#f0f4ff", 0.4),
        "iron": lambda: T("iron", "#6a6e78", "#26283a", "#a0a6b4", 0.3),
        "steel": lambda: M("steel"),
        "leather": lambda: M("leather"),
        "cream": lambda: M("cloth_cream"),
        "paper": lambda: M("paper"),
        "red": lambda: T("red", "#c8302e", "#521428", "#f05a44"),
        "white": lambda: T("white", "#ece8e0", "#8a8aa6", "#ffffff"),
        "dark": lambda: T("dark", "#3a3640", "#14121c", "#5e5866"),
        "black": lambda: M("black"),
        "wood": lambda: T("wood", "#8a5a34", "#3a2228", "#b8804c"),
        "pearl": lambda: T("pearl", "#f2ece4", "#9a96b4", "#ffffff", 0.5),
        "cloth": lambda: T("cloth", "#c8b080", "#6a5a50", "#eedcaa"),
        "rope": lambda: T("rope", "#c8a060", "#6a4a34", "#ecca84"),
        "green_pcb": lambda: T("pcb", "#2e8a4a", "#103028", "#58c070"),
        "iridium": lambda: T("iridium", "#7a90b0", "#2a3050", "#c4d8f4", 0.45),
        "screen": lambda: T("screen", "#2a3a5a", "#101828", "#4a6a9a", 0.5),
    }

    def mat(key):
        if key.startswith("#"):
            return T("c" + key[1:], key, _shade(key, 0.4), _shade(key, 1.35))
        return MAT[key]()

    def glow_mat(hexc):
        return C.toon("it_glow" + hexc[1:], hexc, None, None, emit=1.0)

    def _shade(h, k):
        r, g, b = (int(h[i:i + 2], 16) for i in (1, 3, 5))
        f = lambda v: max(0, min(255, int(v * k + (40 * (k - 1) if k > 1 else 0))))  # noqa: E731
        return "#%02x%02x%02x" % (f(r), f(g), f(b))

    # ------------------------------------------------------------------ constructeurs
    def b_bandage(B, p):
        B.cyl("roll", 0.75, 0.75, 0.9, (0, 0, 0), mat("white"), rot=(R(90), 0, R(20)), seg=28)
        B.cyl("core", 0.28, 0.28, 0.92, (0, 0, 0), mat("cream"), rot=(R(90), 0, R(20)), seg=20)
        B.box("tail", (0.85, 0.05, 0.85), (0.55, -0.55, -0.45), mat("white"), rot=(R(10), R(-25), R(20)))
        B.box("stripe", (0.2, 0.06, 0.6), (0.65, -0.6, -0.4), mat("red"), rot=(R(10), R(-25), R(20)))

    def b_sack(B, p):
        k = 0.8 if p.get("small") else 1.0
        sack = C.bm_sphere(20, 14, 1.0 * k)
        for v in sack.verts:
            z = v.co.z
            v.co.x *= 1.0 - 0.25 * max(0.0, z / k)
            v.co.y *= 0.9 - 0.2 * max(0.0, z / k)
            v.co.z = z * (0.85 if z < 0 else 0.75)
        B.add("sack", sack, mat(p["col"]), sharp=80)
        B.cyl("neck", 0.32 * k, 0.45 * k, 0.45 * k, (0, 0, 0.85 * k), mat(p["col"]))
        B.torus("tie", 0.36 * k, 0.07, (0, 0, 0.78 * k), mat(p["tie"]), seg=20)
        if p.get("dollar"):
            t = C.text_mesh("dollar", "$", 1.0, mat("#2e7a3a"), extrude=0.06)
            t.rotation_euler = (R(90), 0, 0)
            t.location = (0, -0.95, -0.15)
            B.objs.append(t)

    def b_can(B, p):
        h = 1.9 if p.get("tall") else 1.4
        r = 0.6 if p.get("tall") else 0.75
        B.cyl("body", r, r, h, (0, 0, 0), mat(p["label"]), seg=28)
        for s in (1, -1):
            B.cyl("rim%d" % s, r * 1.03, r * 1.03, 0.1, (0, 0, s * h / 2), mat("silver"), seg=28)
        B.cyl("band", r * 1.01, r * 1.01, h * 0.28, (0, 0, 0), mat(p["band"]), seg=28)

    def b_medal(B, p):
        B.box("ribbon", (0.9, 0.08, 1.1), (0, 0, 0.75), mat(p["ribbon"]))
        B.box("stripe", (0.25, 0.09, 1.1), (0, 0, 0.75), mat("#e8d8b0"))
        CUR.coin(B, "disc", (0, -0.05, -0.45), 0.78, (R(90), 0, 0))

    def b_dynamite(B, p):
        for i, x in enumerate((-0.5, 0.0, 0.5)):
            B.cyl("stick%d" % i, 0.27, 0.27, 1.8, (x, -0.05 * i, 0), mat("red"), rot=(0, R(8), 0), seg=18)
        B.box("strap", (1.7, 0.62, 0.22), (0, 0, 0.1), mat("leather"))
        B.tube("fuse", [(0, 0, 0.9), (0.15, 0, 1.25), (0.45, 0, 1.4)], [0.05, 0.05, 0.04], mat("dark"))
        B.sphere("spark", 0.14, (0.5, -0.02, 1.42), glow_mat("#ffb040"))

    def b_bar(B, p):
        bm = bmesh.new()
        w, d, h, t = 1.6, 0.8, 0.55, 0.22
        pts = [(-w / 2, -d / 2, 0), (w / 2, -d / 2, 0), (w / 2, d / 2, 0), (-w / 2, d / 2, 0),
               (-w / 2 + t, -d / 2 + t, h), (w / 2 - t, -d / 2 + t, h), (w / 2 - t, d / 2 - t, h), (-w / 2 + t, d / 2 - t, h)]
        v = [bm.verts.new(q) for q in pts]
        for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            bm.faces.new([v[i] for i in f])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        C.bm_xform(bm, loc=(0, 0, -0.25), rot=(0, 0, R(-15)))
        bm2 = bm.copy()
        B.add("bar", bm, mat("gold"), sharp=20)
        C.bm_xform(bm2, loc=(0.25, 0.55, -0.55))
        B.add("bar2", bm2, mat("gold"), sharp=20)

    def b_nugget(B, p):
        import random
        rnd = random.Random(7)
        bm = C.bm_sphere(14, 10, 1.0)
        for v in bm.verts:
            v.co *= 0.75 + rnd.random() * 0.4
            v.co.z *= 0.75
        B.add("nugget", bm, mat(p["col"]), sharp=35)
        bm2 = C.bm_sphere(10, 8, 0.45)
        for v in bm2.verts:
            v.co *= 0.8 + rnd.random() * 0.4
        C.bm_xform(bm2, loc=(0.9, -0.4, -0.45))
        B.add("nugget2", bm2, mat(p["col"]), sharp=35)

    def b_key(B, p):
        m = mat(p["metal"])
        B.cyl("shaft", 0.11, 0.11, 2.0, (0.25, 0, -0.2), m, rot=(0, R(90), 0), seg=12)
        B.box("bit1", (0.12, 0.14, 0.45), (1.0, 0, -0.45), m)
        B.box("bit2", (0.12, 0.14, 0.3), (0.75, 0, -0.38), m)
        bow = p["bow"]
        if bow == "ring":
            B.torus("bow", 0.42, 0.12, (-0.95, 0, -0.2), m, rot=(R(90), 0, 0), seg=24)
        elif bow == "tag":
            B.torus("bow", 0.3, 0.1, (-0.85, 0, -0.2), m, rot=(R(90), 0, 0))
            B.box("tag", (0.7, 0.06, 0.9), (-1.25, -0.05, 0.45), mat("#b8302e"), rot=(0, R(-20), 0))
            B.torus("tagring", 0.2, 0.04, (-1.1, -0.05, 0.05), mat("brass"), rot=(R(90), 0, 0))
        elif bow == "heart":
            B.sphere("h1", 0.32, (-1.05, 0, 0.0), m, scale=(1, 0.35, 1))
            B.sphere("h2", 0.32, (-0.75, 0, 0.0), m, scale=(1, 0.35, 1))
            B.cyl("h3", 0.45, 0.05, 0.55, (-0.9, 0, -0.35), m, rot=(0, 0, 0), seg=4)
        else:
            star = CUR._star(0.6, 0.27, 0.0, n=5)
            bm = C.bm_loft([[(x, -0.08, y) for (x, y, _z) in star], [(x, 0.08, y) for (x, y, _z) in star]])
            C.bm_xform(bm, loc=(-0.95, 0, -0.2))
            B.add("bow", bm, m, sharp=20)

    def b_keycard(B, p):
        B.box("card", (1.8, 0.08, 1.15), (0, 0, 0), mat(p["col"]), rot=(R(-8), 0, R(-10)), bevel=0.08)
        B.box("chip", (0.4, 0.1, 0.32), (-0.45, -0.04, 0.12), mat("gold"), rot=(R(-8), 0, R(-10)), bevel=0.03)
        B.box("strip", (1.8, 0.1, 0.18), (0, 0.0, -0.32), mat("dark"), rot=(R(-8), 0, R(-10)))
        if p.get("space"):
            B.box("led", (0.22, 0.1, 0.22), (0.55, -0.05, 0.25), glow_mat("#9af4ff"), rot=(R(-8), 0, R(-10)))
        else:
            B.torus("hole", 0.12, 0.04, (0.7, -0.05, 0.35), mat("silver"), rot=(R(90), 0, 0))

    def b_lasso(B, p):
        for i in range(4):
            B.torus("coil%d" % i, 0.85 - 0.04 * i, 0.09, (0.02 * i, -0.06 * i, 0.05 * i), mat("rope"),
                    rot=(R(70), R(5 * i), 0), seg=28)
        B.tube("tail", [(0.8, -0.2, -0.1), (1.1, -0.4, -0.6), (0.9, -0.6, -1.0)], [0.09, 0.08, 0.07], mat("rope"))

    def b_holster(B, p):
        bm = C.bm_box(0.9, 0.35, 1.6, bevel=0.15, segs=3)
        for v in bm.verts:
            if v.co.z < 0:
                v.co.x *= 0.65 + 0.35 * (1 + v.co.z / 0.8)
        C.bm_xform(bm, rot=(0, R(-12), 0))
        B.add("holster", bm, mat("leather"), sharp=70)
        B.box("flap", (0.95, 0.4, 0.35), (0.05, -0.02, 0.7), mat("#5a3420"), rot=(0, R(-12), 0), bevel=0.06)
        B.cyl("stud", 0.08, 0.08, 0.06, (0.05, -0.23, 0.7), mat("silver"), rot=(R(90), 0, 0))
        B.box("butt", (0.4, 0.3, 0.5), (-0.1, 0, 1.05), mat("wood"), rot=(0, R(-30), 0), bevel=0.05)

    def b_lockpicks(B, p):
        B.box("pouch", (1.5, 0.15, 0.9), (0, 0.1, -0.35), mat("leather"), bevel=0.08)
        for i, a in enumerate((-25, -8, 10, 28)):
            B.cyl("pick%d" % i, 0.04, 0.03, 1.5, (-0.3 + 0.2 * i, 0, 0.45), mat("silver"), rot=(0, R(a), 0), seg=8)
            B.sphere("tip%d" % i, 0.08, (-0.3 + 0.2 * i - math.sin(R(a)) * 0.75, 0, 1.15), mat("silver"))

    def b_batteries(B, p):
        for i, x in enumerate((-0.45, 0.45)):
            B.cyl("bat%d" % i, 0.38, 0.38, 1.6, (x, 0, 0), mat("#d8a02e" if i else "#2e2e36"), seg=20)
            B.cyl("band%d" % i, 0.385, 0.385, 0.55, (x, 0, 0.45), mat("dark" if i else "#d8a02e"), seg=20)
            B.cyl("tip%d" % i, 0.12, 0.12, 0.12, (x, 0, 0.86), mat("silver"), seg=12)

    def b_cash(B, p):
        for i in range(4):
            B.box("bill%d" % i, (1.9, 0.9, 0.08), (0.03 * i, 0.02 * i, -0.3 + 0.09 * i), mat("#7aa86a"),
                  rot=(R(60), 0, R(-8 + 4 * i)))
        B.box("band", (0.35, 0.95, 0.5), (0, -0.05, -0.12), mat("#e8d080"), rot=(R(60), 0, R(4)))
        B.cyl("emb", 0.25, 0.25, 0.05, (0.55, -0.32, 0.05), mat("#3e7a3a"), rot=(R(-30), 0, 0))

    def b_necklace(B, p):
        n = 18
        for i in range(n):
            a = math.pi * 0.08 + math.pi * 0.84 * i / (n - 1)
            x, z = math.cos(a) * 1.0, -math.sin(a) * 0.95 + 0.5
            if p["bead"] == "pearl":
                B.sphere("b%d" % i, 0.15, (x, 0, z), mat("pearl"), seg=10, rings=7)
            else:
                B.torus("b%d" % i, 0.09, 0.03, (x, 0, z), mat("silver"), rot=(0, a, 0), seg=10, rseg=4)
        if p.get("gem"):
            CUR.gem(B, "pend", (0, -0.15, -0.65), 0.42, (R(80), 0, 0), "cyan")
        else:
            B.sphere("pend", 0.28, (0, 0, -0.55), mat("pearl"))

    def b_kit(B, p):
        B.box("case", (1.8, 0.8, 1.3), (0, 0, -0.1), mat(p["col"]), bevel=0.12)
        B.box("lid", (1.84, 0.84, 0.12), (0, 0, 0.4), mat("dark" if p["col"] == "white" else "#8a1e22"), bevel=0.04)
        B.torus("handle", 0.32, 0.07, (0, 0, 0.62), mat("dark"), rot=(R(90), 0, 0), seg=16)
        c = mat(p["cross"])
        B.box("cx", (0.7, 0.06, 0.22), (0, -0.42, -0.15), c)
        B.box("cz", (0.22, 0.06, 0.7), (0, -0.42, -0.15), c)

    def b_console(B, p):
        B.box("body", (2.0, 0.25, 1.05), (0, 0, 0), mat("#d8d8e4"), rot=(R(-10), 0, 0), bevel=0.25)
        B.box("screen", (0.95, 0.1, 0.65), (0, -0.12, 0.03), mat("screen"), rot=(R(-10), 0, 0), bevel=0.03)
        B.cyl("dpad", 0.18, 0.18, 0.08, (-0.72, -0.13, 0.0), mat("dark"), rot=(R(80), 0, 0), seg=4)
        for i, (x, z) in enumerate(((0.68, 0.1), (0.82, -0.05))):
            B.cyl("btn%d" % i, 0.08, 0.08, 0.08, (x, -0.13, z), mat("#d8402e" if i else "#3a7ad8"), rot=(R(80), 0, 0))

    def b_card(B, p):
        B.box("card", (1.8, 0.08, 1.15), (0, 0, 0), mat(p["col"]), rot=(R(-8), 0, R(10)), bevel=0.08)
        B.box("ribbon_v", (0.2, 0.1, 1.15), (0.35, 0, 0), mat(p["stripe"]), rot=(R(-8), 0, R(10)))
        B.box("ribbon_h", (1.8, 0.1, 0.2), (0, 0, 0.1), mat(p["stripe"]), rot=(R(-8), 0, R(10)))
        B.sphere("bow", 0.2, (0.35, -0.1, 0.12), mat(p["stripe"]), scale=(1.4, 0.6, 0.9))

    def b_ring(B, p):
        B.torus("band", 0.75, 0.13, (0, 0, -0.2), mat("gold"), rot=(R(75), 0, 0), seg=32)
        B.cyl("setting", 0.22, 0.3, 0.25, (0, 0.05, 0.62), mat("gold"), seg=12)
        CUR.gem(B, "stone", (0, 0.05, 0.92), 0.36, (0, 0, 0), "violet")

    def b_headphones(B, p):
        pts = [(math.cos(math.pi * i / 12) * 1.0, 0, math.sin(math.pi * i / 12) * 1.0 + 0.0) for i in range(13)]
        B.tube("arc", pts, [0.11] * 13, mat("dark"))
        for s in (1, -1):
            B.cyl("cup%d" % s, 0.42, 0.42, 0.35, (s * 1.0, 0, -0.2), mat("#d8402e"), rot=(0, R(90), 0), seg=20)
            B.cyl("pad%d" % s, 0.36, 0.36, 0.1, (s * 0.8, 0, -0.2), mat("dark"), rot=(0, R(90), 0), seg=20)

    def b_wristwatch(B, p):
        B.box("strap", (0.6, 0.12, 2.3), (0, 0.1, 0), mat("leather"), bevel=0.05)
        B.cyl("case", 0.62, 0.62, 0.25, (0, -0.05, 0), mat("gold"), rot=(R(90), 0, 0), seg=32)
        B.cyl("face", 0.5, 0.5, 0.06, (0, -0.18, 0), mat("white"), rot=(R(90), 0, 0), seg=32)
        B.box("hand1", (0.05, 0.03, 0.35), (0.05, -0.22, 0.12), mat("dark"), rot=(0, R(25), 0))
        B.box("hand2", (0.05, 0.03, 0.25), (-0.08, -0.22, 0.05), mat("dark"), rot=(0, R(-70), 0))
        B.cyl("crown", 0.08, 0.08, 0.15, (0.7, -0.05, 0), mat("gold"), rot=(0, R(90), 0))

    def b_pills(B, p):
        B.cyl("bottle", 0.6, 0.6, 1.3, (0, 0, -0.2), mat("#e8862e"), seg=24)
        B.cyl("cap", 0.66, 0.66, 0.38, (0, 0, 0.6), mat("white"), seg=24)
        B.cyl("label", 0.61, 0.61, 0.55, (0, 0, -0.25), mat("white"), seg=24)
        B.sphere("pill1", 0.2, (0.85, -0.5, -0.75), mat("white"), scale=(1.6, 1, 0.8))
        B.sphere("pill2", 0.2, (-0.8, -0.55, -0.8), mat("#e8862e"), scale=(1.6, 1, 0.8))

    def b_perfume(B, p):
        B.box("glass", (1.2, 0.7, 1.0), (0, 0, -0.3), mat("#e88ab8"), bevel=0.2, rot=(0, 0, R(10)))
        B.cyl("neck", 0.18, 0.18, 0.3, (0, 0, 0.35), mat("gold"))
        B.sphere("stopper", 0.32, (0, 0, 0.72), mat("#d86aa0"), scale=(1, 1, 1.2))
        B.tube("tube", [(0.15, 0, 0.4), (0.7, 0, 0.6), (1.0, 0, 0.3)], [0.04, 0.04, 0.04], mat("gold"))
        B.sphere("bulb", 0.22, (1.05, 0, 0.15), mat("#c84a7a"))

    def b_phone(B, p):
        B.box("body", (1.0, 0.12, 1.9), (0, 0, 0), mat("black"), rot=(R(-10), 0, R(-12)), bevel=0.12)
        B.box("screen", (0.85, 0.08, 1.6), (0, -0.04, 0.02), mat("screen"), rot=(R(-10), 0, R(-12)), bevel=0.05)
        B.box("glint", (0.12, 0.09, 1.2), (-0.2, -0.06, 0.05), mat("#6a8ac4"), rot=(R(-10), R(25), R(-12)))

    def b_flask(B, p):
        bm = C.bm_cyl(24, 0.85, 0.25, 1.3)
        C.bm_xform(bm, loc=(0, 0, -0.3))
        B.add("glass", bm, mat("#c8e8f0"), sharp=80)
        B.cyl("liquid", 0.78, 0.48, 0.6, (0, 0, -0.62), mat(p["liquid"]), seg=24)
        B.cyl("neck", 0.25, 0.25, 0.5, (0, 0, 0.55), mat("#c8e8f0"), seg=16)
        B.cyl("cork", 0.22, 0.2, 0.3, (0, 0, 0.9), mat("wood"))

    def b_cloth(B, p):
        for i, (x, c) in enumerate(((-0.55, "#c8303a"), (0.0, "cream"), (0.55, "#3a6ab0"))):
            B.cyl("roll%d" % i, 0.42, 0.42, 1.1, (x, -0.05 * i, -0.1 + 0.05 * i), mat(c), rot=(R(90), 0, R(15)), seg=20)

    def b_gears(B, p):
        for name, r, loc, n in (("g1", 0.85, (-0.25, 0, 0.1), 10), ("g2", 0.55, (0.85, -0.1, -0.55), 8)):
            B.cyl(name, r * 0.82, r * 0.82, 0.25, loc, mat("brass"), rot=(R(80), 0, 0), seg=24)
            B.cyl(name + "h", r * 0.25, r * 0.25, 0.3, loc, mat("dark"), rot=(R(80), 0, 0), seg=12)
            for k in range(n):
                a = 2 * math.pi * k / n
                B.box(name + "t%d" % k, (0.22, 0.25, 0.22), (loc[0] + math.cos(a) * r * 0.9, loc[1], loc[2] + math.sin(a) * r * 0.9),
                      mat("brass"), rot=(0, -a, 0))
        pts = [(-0.9 + 0.08 * i, -0.3, -0.9 + math.sin(i * 1.2) * 0.12 + 0.0) for i in range(12)]
        B.tube("spring", [(-1.0 + 0.1 * i, -0.4, -0.75 + 0.18 * math.sin(i * 1.6)) for i in range(12)], [0.05] * 12, mat("steel"))
        del pts

    def b_scrap(B, p):
        B.box("plate1", (1.4, 0.1, 0.9), (-0.2, 0, 0), mat("iron"), rot=(R(20), R(15), R(-10)))
        B.box("plate2", (1.0, 0.1, 0.7), (0.4, -0.2, -0.4), mat("#a8603a"), rot=(R(-15), R(-30), R(25)))
        B.cyl("bolt", 0.12, 0.12, 0.6, (0.6, -0.3, 0.3), mat("steel"), rot=(0, R(60), 0))
        B.cyl("pipe", 0.18, 0.18, 1.3, (-0.4, -0.35, -0.55), mat("steel"), rot=(0, R(80), R(20)), seg=14)

    def b_cards(B, p):
        for i, a in enumerate((-20, 0, 20)):
            B.box("card%d" % i, (0.9, 0.04, 1.3), (0.25 * (i - 1), -0.03 * i, 0), mat("white"), rot=(R(-10), R(a), 0), bevel=0.05)
        B.box("pip", (0.3, 0.06, 0.3), (0.25, -0.1, 0.1), mat("red"), rot=(R(-10), R(65), 0))
        B.box("back", (0.75, 0.05, 1.12), (-0.25, 0.04, 0.02), mat("#2e4a9a"), rot=(R(-10), R(-20), 0))

    def b_pocketwatch(B, p):
        B.cyl("case", 0.85, 0.85, 0.3, (0, 0, -0.1), mat("gold"), rot=(R(80), 0, 0), seg=36)
        B.cyl("face", 0.7, 0.7, 0.06, (0, -0.16, -0.1), mat("white"), rot=(R(80), 0, 0), seg=36)
        B.box("h1", (0.05, 0.03, 0.45), (0.06, -0.21, 0.05), mat("dark"), rot=(R(80), R(15), 0))
        B.box("h2", (0.05, 0.03, 0.3), (-0.1, -0.21, -0.12), mat("dark"), rot=(R(80), R(-60), 0))
        B.cyl("crown", 0.12, 0.12, 0.2, (0, 0, 0.85), mat("gold"))
        B.torus("bow", 0.22, 0.05, (0, 0, 1.05), mat("gold"), rot=(R(90), 0, 0))
        B.tube("chain", [(0.2, 0, 1.15), (0.8, -0.1, 1.0), (1.1, -0.2, 0.4)], [0.04] * 3, mat("gold"))

    def b_diamond(B, p):
        CUR.gem(B, "d", (0, 0, 0.1), 1.0, (R(15), R(-10), 0), "cyan")
        CUR.gem(B, "d2", (0.95, -0.4, -0.6), 0.35, (R(40), R(20), 0.5), "deep")

    def b_bullets(B, p):
        L = 1.7 if p["long"] else 1.1
        for i, x in enumerate((-0.55, 0.0, 0.55)):
            z = -0.08 * abs(i - 1)
            B.cyl("case%d" % i, 0.22, 0.22, L, (x, -0.05 * i, z), mat("brass"), seg=16)
            B.cyl("rim%d" % i, 0.25, 0.25, 0.08, (x, -0.05 * i, z - L / 2), mat("brass"), seg=16)
            B.cyl("tip%d" % i, 0.21, 0.04, 0.55 if p["long"] else 0.45, (x, -0.05 * i, z + L / 2 + 0.25), mat("#c87a4a"), seg=16)

    def b_star_badge(B, p):
        star = CUR._star(1.05, 0.55, 0.0, n=6)
        bm = C.bm_loft([[(x, -0.08, y) for (x, y, _z) in star], [(x, 0.08, y) for (x, y, _z) in star]])
        B.add("star", bm, mat("gold"), sharp=20)
        for k in range(6):
            a = math.pi / 2 + 2 * math.pi * k / 6
            B.sphere("ball%d" % k, 0.13, (math.cos(a) * 1.08, -0.05, math.sin(a) * 1.08), mat("gold"))
        B.cyl("center", 0.4, 0.4, 0.12, (0, -0.12, 0), mat("silver"), rot=(R(90), 0, 0), seg=24)

    def b_coins(B, p):
        for i in range(5):
            B.cyl("c%d" % i, 0.7, 0.7, 0.16, (0.03 * (i % 2), 0, -0.6 + 0.17 * i), mat(p["metal"]), seg=32)
        B.cyl("top", 0.55, 0.55, 0.14, (0.8, -0.35, -0.25), mat(p["metal"]), rot=(R(70), R(15), 0), seg=32)
        B.cyl("top_emb", 0.38, 0.38, 0.16, (0.8, -0.35, -0.25), mat("iron"), rot=(R(70), R(15), 0), seg=24)

    def b_bottle(B, p):
        g = mat(p["glass"])
        if p["shape"] == "square":
            B.box("body", (0.9, 0.9, 1.5), (0, 0, -0.35), g, bevel=0.15)
        else:
            B.sphere("body", 0.8, (0, 0, -0.4), g, scale=(1, 1, 1.05), seg=24, rings=14)
        B.cyl("neck", 0.22, 0.28, 0.75, (0, 0, 0.65), g, seg=16)
        B.cyl("cork", 0.2, 0.18, 0.28, (0, 0, 1.12), mat("wood"))
        B.box("label", (0.75, 0.1, 0.6), (0, -0.46 if p["shape"] == "square" else -0.78, -0.35), mat(p["label"]))
        B.box("glint", (0.08, 0.1, 0.7), (-0.25, -0.5 if p["shape"] == "square" else -0.75, -0.2), mat("#fff0d0"))

    def b_vial(B, p):
        B.cyl("glass", 0.45, 0.45, 1.6, (0, 0, -0.1), mat("#c8e8f0"), seg=24)
        B.cyl("liquid", 0.38, 0.38, 1.1, (0, 0, -0.35), glow_mat(p["glow"]), seg=24)
        for s in (1, -1):
            B.cyl("cap%d" % s, 0.52, 0.52, 0.28, (0, 0, s * 0.82 - 0.1), mat("steel"), seg=24)
        for k in range(3):
            B.torus("ring%d" % k, 0.62, 0.04, (0, 0, -0.5 + 0.4 * k), mat("steel"), rot=(R(10), 0, 0))

    def b_circuit(B, p):
        B.box("board", (1.9, 0.1, 1.3), (0, 0, 0), mat("green_pcb"), rot=(R(-30), 0, R(8)), bevel=0.03)
        B.box("chip", (0.6, 0.15, 0.45), (-0.2, -0.08, 0.1), mat("dark"), rot=(R(-30), 0, R(8)))
        B.box("chip2", (0.3, 0.15, 0.3), (0.55, -0.06, -0.2), mat("dark"), rot=(R(-30), 0, R(8)))
        for k in range(4):
            B.box("trace%d" % k, (1.5, 0.12, 0.04), (0, -0.04, -0.45 + 0.08 * k), mat("gold"), rot=(R(-30), 0, R(8)))

    def b_chip(B, p):
        B.box("chip", (1.2, 0.2, 1.2), (0, 0, 0), mat("dark"), rot=(R(-35), 0, R(20)), bevel=0.05)
        B.box("core", (0.55, 0.22, 0.55), (0, -0.04, 0.02), glow_mat("#4ad8ff"), rot=(R(-35), 0, R(20)))
        for k in range(5):
            for s in (1, -1):
                B.box("pin%d%d" % (k, s), (0.1, 0.08, 0.3), (-0.4 + 0.2 * k, 0.0, s * 0.72), mat("gold"), rot=(R(-35), 0, R(20)))

    def b_core(B, p):
        B.box("cube", (1.3, 1.3, 1.3), (0, 0, 0), mat("dark"), rot=(R(10), 0, R(35)), bevel=0.15)
        B.sphere("glow", 0.55, (0, -0.35, 0.05), glow_mat("#b46bff"))
        for k in range(4):
            B.box("seam%d" % k, (1.35, 1.35, 0.06), (0, 0, -0.4 + 0.27 * k), mat("#6a4ac8"), rot=(R(10), 0, R(35)))

    def b_cell(B, p):
        k = 1.25 if p["big"] else 1.0
        B.cyl("glass", 0.45 * k, 0.45 * k, 1.3 * k, (0, 0, 0), glow_mat(p["glow"]), rot=(0, R(15), 0), seg=20)
        for s in (1, -1):
            B.cyl("cap%d" % s, 0.52 * k, 0.52 * k, 0.32 * k, (s * 0.2 * k, 0, s * 0.72 * k), mat("steel"), rot=(0, R(15), 0), seg=20)
        B.cyl("pole", 0.15 * k, 0.15 * k, 0.2, (0.27 * k, 0, 1.0 * k), mat("gold"), rot=(0, R(15), 0))

    def b_tube(B, p):
        bm = C.bm_cyl(20, 0.5, 0.5, 1.6)
        for v in bm.verts:
            if v.co.z > 0.5:
                v.co.y *= 0.15
        C.bm_xform(bm, rot=(0, R(-60), 0))
        B.add("tube", bm, mat("white"), sharp=80)
        B.cyl("cap", 0.3, 0.3, 0.4, (-0.8, 0, -0.45), mat("#3ac8b0"), rot=(0, R(-60), 0))
        B.box("stripe", (0.6, 0.12, 0.25), (0.1, -0.45, 0.05), mat("#3ac8b0"), rot=(0, R(-60), 0))

    def b_injector(B, p):
        B.cyl("body", 0.32, 0.32, 1.6, (0, 0, 0), mat("white"), rot=(0, R(55), 0), seg=18)
        B.cyl("window", 0.33, 0.33, 0.7, (0.1, 0, 0.05), glow_mat("#5af08a"), rot=(0, R(55), 0), seg=18)
        B.cyl("plunger", 0.18, 0.18, 0.5, (-0.85, 0, -0.6), mat("#3a7ad8"), rot=(0, R(55), 0))
        B.cyl("needle", 0.04, 0.02, 0.6, (0.9, 0, 0.62), mat("steel"), rot=(0, R(55), 0))

    def b_shield_badge(B, p):
        pts = [(-0.8, 0.8), (0.8, 0.8), (0.8, 0.0), (0.0, -1.0), (-0.8, 0.0)]
        bm = C.bm_loft([[(x, -0.08, y) for x, y in pts], [(x, 0.08, y) for x, y in pts]])
        B.add("shield", bm, mat("silver"), sharp=20)
        for k in range(2):
            B.box("chev%d" % k, (0.9, 0.12, 0.14), (-0.22, -0.1, 0.25 - 0.32 * k), mat("#3a7ad8"), rot=(0, R(30), 0))
            B.box("chevb%d" % k, (0.9, 0.12, 0.14), (0.22, -0.1, 0.25 - 0.32 * k), mat("#3a7ad8"), rot=(0, R(-30), 0))

    def b_plasma(B, p):
        for i, x in enumerate((-0.6, 0.0, 0.6)):
            B.cyl("cell%d" % i, 0.25, 0.25, 1.1, (x, -0.05 * i, 0), glow_mat("#ff5aa8"), seg=16)
            for s in (1, -1):
                B.cyl("cap%d%d" % (i, s), 0.29, 0.29, 0.22, (x, -0.05 * i, s * 0.6), mat("steel"), seg=16)

    def b_ration(B, p):
        B.box("pack", (1.5, 0.45, 1.5), (0, 0, 0), mat("#a8b070"), rot=(0, 0, R(-12)), bevel=0.18)
        B.box("seal", (1.6, 0.5, 0.15), (0, 0, 0.72), mat("#80884e"), rot=(0, 0, R(-12)))
        B.box("label", (0.9, 0.48, 0.5), (0, -0.02, 0.05), mat("white"), rot=(0, 0, R(-12)))
        B.box("tag", (0.4, 0.5, 0.15), (0, -0.04, 0.05), mat("#d84a2e"), rot=(0, 0, R(-12)))

    def b_servo(B, p):
        B.box("body", (1.4, 0.8, 0.9), (0, 0, -0.2), mat("#3a4a6a"), bevel=0.08)
        B.cyl("shaft", 0.35, 0.35, 0.35, (0.35, 0, 0.4), mat("steel"), seg=20)
        B.box("arm", (1.1, 0.2, 0.15), (0.6, 0, 0.62), mat("white"), rot=(0, 0, R(25)), bevel=0.05)
        for k in range(3):
            B.tube("wire%d" % k, [(-0.7, 0.1 * k - 0.1, -0.3), (-1.0, 0.1 * k - 0.1, -0.6), (-0.9, 0.1 * k - 0.1, -0.95)],
                   [0.04] * 3, mat(("#d8402e", "#e8c02e", "dark")[k]))

    def b_starmap(B, p):
        B.box("tablet", (1.9, 0.12, 1.3), (0, 0, 0), mat("#202838"), rot=(R(-20), 0, R(6)), bevel=0.08)
        B.box("screen", (1.65, 0.1, 1.05), (0, -0.04, 0), mat("#16305a"), rot=(R(-20), 0, R(6)))
        import random
        rnd = random.Random(3)
        for k in range(9):
            B.sphere("star%d" % k, 0.05 + rnd.random() * 0.05, (-0.7 + rnd.random() * 1.4, -0.12, -0.4 + rnd.random() * 0.8),
                     glow_mat("#bfe8ff"), seg=8, rings=6)
        B.sphere("planet", 0.15, (0.4, -0.12, 0.15), glow_mat("#ff9a4a"))

    def b_paper(B, name, col, rot=(R(-12), 0, R(-6)), w=1.9, h=1.35):
        bm = C.bm_box(w, 0.04, h)
        for v in bm.verts:
            v.co.y += 0.08 * math.sin(v.co.x * 2.2)
        C.bm_xform(bm, rot=rot)
        B.add(name, bm, mat(col), sharp=80)

    def b_map(B, p):
        b_paper(B, "parch", "paper")
        B.cyl("roll", 0.14, 0.14, 1.45, (1.0, -0.05, 0.0), mat("paper"), rot=(R(-12), 0, R(-6)), seg=14)
        for k in range(5):
            B.box("dash%d" % k, (0.18, 0.06, 0.05), (-0.7 + 0.25 * k, -0.18, -0.35 + 0.12 * math.sin(k)), mat("#7a3a2a"), rot=(R(-12), 0, R(-6)))
        B.box("x1", (0.45, 0.06, 0.1), (0.45, -0.2, 0.2), mat("red"), rot=(R(-12), R(45), R(-6)))
        B.box("x2", (0.45, 0.06, 0.1), (0.45, -0.2, 0.2), mat("red"), rot=(R(-12), R(-45), R(-6)))

    def b_poster(B, p):
        b_paper(B, "paper", "paper", rot=(R(-10), 0, R(5)), w=1.3, h=1.8)
        B.box("frame", (0.8, 0.06, 0.7), (0, -0.12, 0.1), mat("#5a4030"), rot=(R(-10), 0, R(5)))
        B.sphere("face", 0.22, (0, -0.16, 0.12), mat("#c89a70"), scale=(1, 0.3, 1.1))
        B.box("hat", (0.5, 0.06, 0.12), (0, -0.18, 0.32), mat("dark"), rot=(R(-10), 0, R(5)))
        B.box("head", (1.0, 0.06, 0.16), (0, -0.12, 0.65), mat("#7a3a2a"), rot=(R(-10), 0, R(5)))
        B.box("reward", (0.9, 0.06, 0.12), (0, -0.12, -0.55), mat("#7a3a2a"), rot=(R(-10), 0, R(5)))
        B.cyl("nail", 0.07, 0.07, 0.1, (0, -0.14, 0.82), mat("iron"), rot=(R(80), 0, 0))

    BUILD = {k[2:]: v for k, v in dict(globals()).items() if k.startswith("b_") and callable(v)}

    def fit_camera(cam, objs, margin: float) -> None:
        bpy.context.view_layer.update()
        inv = cam.matrix_world.inverted()
        xs, ys = [], []
        for ob in objs:
            if ob.type != "MESH":
                continue
            mw = ob.matrix_world
            for v in ob.data.vertices:
                q = inv @ (mw @ v.co)
                xs.append(q.x)
                ys.append(q.y)
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        span = max(max(xs) - min(xs), max(ys) - min(ys))
        cam.location = cam.location + cam.matrix_world.to_3x3() @ Vector((cx, cy, 0.0))
        cam.data.ortho_scale = span * margin

    def render_item(name: str) -> None:
        kind, params, _r = ITEMS[name]
        C.reset_scene()
        C._mat_cache.clear() if hasattr(C, "_mat_cache") else None
        C.setup_render(SIZE * SS, samples=8, outline_px=2.0 * SS * SIZE / 256, inner_ratio=0.45)
        B = P.Builder()
        BUILD[kind](B, params)
        cam = C.ortho_camera(18.0, 4.0, target=(0, 0, 0), azim_deg=-8.0)
        fit_camera(cam, B.objs, 1.22)
        os.makedirs(TMP, exist_ok=True)
        C.render_to(os.path.join(TMP, name + "_big.png"))
        print("RENDER", name)

    def blender_main() -> None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
        names = argv[argv.index("--render") + 1].split(",") if "--render" in argv else list(ITEMS)
        for n in names:
            try:
                render_item(n)
            except Exception as e:  # noqa: BLE001
                print("FAIL", n, repr(e))


# =============================================================================== composition (PIL)
def _hex(h: str) -> tuple[int, int, int]:
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))  # type: ignore


def compose(name: str) -> None:
    from PIL import Image, ImageChops, ImageFilter
    src = os.path.join(TMP, name + "_big.png")
    if not os.path.exists(src):
        print("MANQUE", name)
        return
    rarity = ITEMS[name][2]
    big = Image.open(src).convert("RGBA")
    im = big.convert("RGBa").resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")
    a = im.getchannel("A")
    ring = a.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(0.8))
    out_l = Image.new("RGBA", im.size, (18, 10, 30, 0))
    out_l.putalpha(ring)
    res = out_l
    if GLOW[rarity] > 0.0:
        halo = a.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(10))
        halo = halo.point(lambda v: int(min(255, v * GLOW[rarity])))
        fade = Image.radial_gradient("L").resize(im.size, Image.BILINEAR).point(lambda v: max(0, 255 - int(v * 1.25)))
        halo = ImageChops.multiply(halo, fade)
        glow = Image.new("RGBA", im.size, (*_hex(RARITY[rarity]), 0))
        glow.putalpha(halo)
        res = Image.alpha_composite(glow, out_l)
    res = Image.alpha_composite(res, im)
    os.makedirs(OUT, exist_ok=True)
    res.save(os.path.join(OUT, name + ".png"), optimize=True)
    print("OK", name)


def main() -> None:
    args = sys.argv[1:]
    names = args[args.index("--only") + 1].split(",") if "--only" in args else list(ITEMS)
    if "--compose" not in args:
        env = dict(os.environ, RDM_TMP=TMP)
        subprocess.run([BLENDER, "--background", "--factory-startup", "--python", os.path.abspath(__file__), "--",
                        "--render", ",".join(names)], check=True, env=env)
    for n in names:
        compose(n)


if __name__ == "__main__":
    if IN_BLENDER:
        blender_main()
    else:
        main()
