"""Ennemis masqués de la station sous-marine (3D toon, même caméra et même échelle que le héros).

Usage (depuis la racine du projet) :
    python3 art/blender/underwater/uw_enemies.py                 # tout
    python3 art/blender/underwater/uw_enemies.py --only uw_diver

Sorties :
  assets/sprites/underwater/enemies/<kind>.png  (vue 3/4 de face tournée vers la droite ;
      EnemyVisual retourne le sprite pour regarder à gauche)
  scripts/biomes/underwater/enemy_kinds.gd       (const KINDS au format EnemyVisual.KINDS :
      path, svg_size = taille du PNG, feet, scale, head, shadow, eyes, eye_r, debris, aura)

Chaque personnage est rendu en grand, recadré puis réduit dans un cadre en puissance de 2 ;
l'échelle (unités monde par px) est calculée pour que la hauteur visible corresponde à
TARGET_H (héros ≈ 64 unités monde).
"""
from __future__ import annotations

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..")))
import uw_props as P  # noqa: E402
import rdm_common as C  # noqa: E402
import build_props as BP  # noqa: E402
import bpy  # noqa: E402

ROOT = P.ROOT
OUT = os.path.join(ROOT, "assets", "sprites", "underwater", "enemies")
KINDS_GD = os.path.join(ROOT, "scripts", "biomes", "underwater", "enemy_kinds.gd")
TMP = os.path.join(P.TMP, "enemies")
ELEV = 48.0
RENDER = 512            # rendu intermédiaire (px), puis réduction
TURN = math.radians(22)  # 3/4 : le personnage regarde un peu vers la droite

PAL = {
    "wetsuit": ("#25343e", "#0c1422", "#3e5866"),
    "wet_trim": ("#e0782e", "#4a2228", "#ffa458"),
    "porcelain": ("#efe8dc", "#8c90ae", "#fffaf2"),
    "mask_red": ("#c8242c", "#4a0e22", "#ec4a3e"),
    "coat": ("#d6dcd2", "#6e7a90", "#f6faf0"),
    "coat_stain": ("#7aa850", "#24402c", "#a8d670"),
    "shell": ("#f0c8b0", "#8a5a6a", "#fff0e0"),
    "shell_rib": ("#d89078", "#6a3444", "#f8b498"),
    "mutant_skin": ("#8a5aa0", "#2e1a44", "#b884c8"),
    "brass": ("#c89a40", "#5a3a30", "#f8d880"),
    "heavy_suit": ("#5a6670", "#1c2234", "#8a98a0"),
    "rubber": ("#2c3038", "#101420", "#4c5260"),
    "iron_mask": ("#4a4e58", "#16182a", "#7c808c"),
    "eel": ("#2e5a5a", "#0c2030", "#4a8a84"),
    "eel_belly": ("#b8c890", "#4a5a5a", "#e0f0b0"),
    "bone": ("#ece2cc", "#8a8aa2", "#fffaf0"),
    "coral_rock": ("#8a7a78", "#2a2638", "#b8a8a0"),
    "coral_pink": ("#e8686e", "#5a2440", "#ff9a90"),
    "coral_orange": ("#f09048", "#6a3434", "#ffc070"),
    "coral_purple": ("#a85ab4", "#3a1a4a", "#d890e0"),
    "steel": ("#8a98a4", "#2c3448", "#c8d6dc"),
    "tank": ("#e2b232", "#6a4a34", "#ffe286"),
}
BP.PAL.update(PAL)
GLOWS = {"eye_cyan": "#5af4ff", "eye_green": "#8aff5a", "eye_orange": "#ffae3a", "eye_red": "#ff3a2a",
         "acid": "#7aff6a", "biolum": "#5affe0"}


def M(key: str, rim: float = 0.3):
    if key in GLOWS:
        return C.toon(key, GLOWS[key], emit=1.8)
    return P.M(key, rim)


class Char:
    """Collecte les objets d'un personnage + points remarquables (monde)."""

    def __init__(self) -> None:
        self.B = P.Builder()
        self.eyes: list[tuple[float, float, float]] = []
        self.head_top = 2.4

    def __getattr__(self, k):
        return getattr(self.B, k)


# ----------------------------------------------------------------------------- humanoïde de base

def humanoid(ch: Char, suit: str, trim: str, boots: str, glove: str, bulk: float = 1.0, hunch: float = 0.0,
             arm_r_fwd: float = 0.5, arm_l_fwd: float = 0.2) -> dict:
    """Corps héroïque (≈ proportions du héros). Renvoie les points utiles (mains, cou, épaules)."""
    B = ch.B
    hip_z = 0.86
    sh_z = 1.48 - hunch * 0.12
    sh_x = 0.31 * bulk
    for sx in (1, -1):
        hx = 0.13 * bulk * sx
        B.tube("thigh%d" % sx, [(hx, 0, hip_z), (hx * 1.05, -0.03, 0.47)], [0.12 * bulk, 0.1 * bulk], M(suit), seg=10)
        B.tube("shin%d" % sx, [(hx * 1.05, -0.03, 0.47), (hx * 1.1, 0.0, 0.12)], [0.1 * bulk, 0.085 * bulk], M(suit), seg=10)
        B.sphere("knee%d" % sx, 0.085 * bulk, (hx * 1.05, -0.07, 0.47), M(trim), seg=10, rings=6)
        B.box("boot%d" % sx, (0.17 * bulk, 0.3, 0.16), (hx * 1.1, -0.06, 0.08), M(boots), bevel=0.04)
    torso = C.bm_loft([
        C.ellipse(0, 0, hip_z - 0.05, 0.2 * bulk, 0.15 * bulk, 14),
        C.ellipse(0, 0.01 + hunch * 0.05, hip_z + 0.2, 0.22 * bulk, 0.16 * bulk, 14),
        C.ellipse(0, 0.02 + hunch * 0.12, sh_z - 0.15, 0.27 * bulk, 0.18 * bulk, 14),
        C.ellipse(0, 0.03 + hunch * 0.18, sh_z, 0.23 * bulk, 0.16 * bulk, 14),
        C.ellipse(0, 0.03 + hunch * 0.2, sh_z + 0.08, 0.12, 0.1, 14),
    ])
    B.add("torso", torso, M(suit), sharp=80)
    B.tube("belt", [(x, 0, hip_z + 0.02) for x in (-0.22 * bulk, 0.0, 0.22 * bulk)], [0.05] * 3, M(trim), seg=8)
    hands = {}
    for sx, fwd in ((1, arm_r_fwd), (-1, arm_l_fwd)):
        s = (sx * sh_x, 0.02 + hunch * 0.15, sh_z - 0.03)
        e = (sx * (sh_x + 0.06), -0.12 - fwd * 0.25, sh_z - 0.38)
        h = (sx * (sh_x + 0.02), -0.2 - fwd * 0.45, sh_z - 0.68 + fwd * 0.12)
        B.sphere("shoulder%d" % sx, 0.13 * bulk, s, M(trim), seg=12, rings=8)
        B.tube("uarm%d" % sx, [s, e], [0.09 * bulk, 0.08 * bulk], M(suit), seg=10)
        B.tube("farm%d" % sx, [e, h], [0.08 * bulk, 0.075 * bulk], M(suit), seg=10)
        B.sphere("hand%d" % sx, 0.085 * bulk, h, M(glove), seg=10, rings=7)
        hands[sx] = h
    neck = (0, 0.03 + hunch * 0.22, sh_z + 0.1)
    return {"hand_r": hands[1], "hand_l": hands[-1], "neck": neck, "sh_z": sh_z}


def eye_slits(ch: Char, cx: float, cy: float, cz: float, sep: float, w: float, h: float, mat: str, tilt: float = 0.25) -> None:
    for sx in (1, -1):
        e = C.bm_sphere(10, 6, 1.0)
        C.bm_xform(e, loc=(cx + sx * sep, cy, cz), rot=(0, sx * tilt, 0), scale=(w, 0.03, h))
        ch.B.add("eye%d" % sx, e, M(mat), sharp=80, shadow=False, outline=False)
        ch.eyes.append((cx + sx * sep, cy - 0.02, cz))


def pitch_pt(local, center, a: float):
    """Point `local` (relatif au centre du masque) tourné de `a` autour de X puis translaté."""
    x, y, z = local
    c, sn = math.cos(a), math.sin(a)
    return (center[0] + x, center[1] + y * c - z * sn, center[2] + y * sn + z * c)


def eyes_at(ch: Char, pts, w: float, h: float, mat: str, tilt: float, a: float) -> None:
    for i, p in enumerate(pts):
        sx = 1 if p[0] >= pts[0][0] and i == 0 else -1
        e = C.bm_sphere(10, 6, 1.0)
        C.bm_xform(e, loc=p, rot=(a, sx * tilt, 0), scale=(w, 0.03, h))
        ch.B.add("eye%d" % i, e, M(mat), sharp=80, shadow=False, outline=False)
        ch.eyes.append((p[0], p[1] - 0.02, p[2]))


# ----------------------------------------------------------------------------- personnages

def e_diver(ch: Char) -> None:
    """Plongeur masqué : combinaison sombre à liserés orange, bouteille jaune, masque de porcelaine
    en tête de requin, fusil-harpon."""
    k = humanoid(ch, "wetsuit", "wet_trim", "rubber", "rubber", 1.12, 0.0, arm_r_fwd=0.9, arm_l_fwd=0.6)
    B = ch.B
    sh = k["sh_z"]
    B.cyl("tank", 0.13, 0.13, 0.62, (0, 0.24, sh - 0.25), M("tank"), seg=14)
    B.sphere("tankdome", 0.13, (0, 0.24, sh + 0.06), M("tank"), seg=12, rings=6)
    B.tube("hose", C.bezier((0.0, 0.24, sh + 0.15), (0.18, 0.2, sh + 0.35), (0.22, 0.0, sh + 0.35), (0.12, -0.18, sh + 0.32), 6),
           [0.03] * 6, M("rubber"), seg=5)
    # Tête : cagoule + masque de requin (porcelaine, museau pointu, marques rouges), tourné
    # vers la caméra (pitch) pour rester lisible en plongée.
    hz = sh + 0.42
    A = -0.5
    B.sphere("hood", 0.3, (0, 0.05, hz), M("wetsuit"), scale=(1.0, 1.0, 1.05), seg=16, rings=10)
    mc = (0, -0.1, hz)
    mask = C.bm_sphere(18, 12, 1.0)
    for v in mask.verts:
        x, y, z = v.co
        if y < 0:
            y *= 1.0 + 0.8 * max(0.0, -y) * math.exp(-x * x * 6)
        if y > 0:
            y *= 0.3
        if z < 0:
            x *= 1.0 - 0.4 * (-z)
        v.co = (x * 0.28, y * 0.24, z * 0.3)
    C.bm_xform(mask, loc=mc, rot=(A, 0, 0))
    B.add("mask", mask, M("porcelain", 0.25), sharp=80)
    for sx in (1, -1):
        B.tube("gill%d" % sx, [pitch_pt((sx * 0.13, -0.25, -0.1), mc, A), pitch_pt((sx * 0.2, -0.18, -0.16), mc, A)],
               [0.016, 0.012], M("mask_red"), seg=4, shadow=False)
    B.tube("finmark", [pitch_pt((0, -0.43, 0.02), mc, A), pitch_pt((0, -0.27, 0.22), mc, A)], [0.025, 0.015], M("mask_red"), seg=4, shadow=False)
    B.tube("dorsal", [(0, 0.0, hz + 0.24), (0, 0.15, hz + 0.5), (0, 0.27, hz + 0.36)], [0.07, 0.025, 0.005], M("porcelain"), seg=6)
    eyes_at(ch, [pitch_pt((0.11, -0.3, 0.06), mc, A), pitch_pt((-0.11, -0.3, 0.06), mc, A)], 0.075, 0.03, "eye_cyan", 0.35, A)
    ch.head_top = hz + 0.45
    # Fusil-harpon tenu à deux mains, pointé vers l'avant-droite.
    hr = k["hand_r"]
    hl = k["hand_l"]
    a = (hl[0] - 0.05, hl[1] + 0.1, hl[2] + 0.02)
    b = (hr[0] + 0.32, hr[1] - 0.2, hr[2] + 0.1)
    B.tube("gun", [a, b], [0.06, 0.05], M("steel"), seg=8)
    B.box("stock", (0.1, 0.12, 0.08), a, M("wet_trim"))
    tip = (b[0] + 0.2, b[1] - 0.1, b[2] + 0.04)
    B.tube("spear", [b, tip], [0.025, 0.02], M("steel"), seg=5)
    B.tube("barb", [tip, (tip[0] + 0.12, tip[1] - 0.05, tip[2] + 0.02)], [0.055, 0.0], M("porcelain"), seg=6)
    B.box("grip", (0.05, 0.08, 0.16), (hr[0], hr[1], hr[2] - 0.06), M("rubber"))
    # Palmes au dos.
    for sx in (1, -1):
        B.box("fin%d" % sx, (0.1, 0.03, 0.45), (sx * 0.08, 0.36, sh - 0.25), M("wet_trim"), rot=(0.2, sx * 0.1, 0))


def e_mutant(ch: Char) -> None:
    """Scientifique muté au masque de coquillage : blouse tachée, bras tentaculaire, réservoir d'acide."""
    k = humanoid(ch, "coat", "coat_stain", "rubber", "mutant_skin", 0.95, hunch=1.0, arm_r_fwd=0.8, arm_l_fwd=0.1)
    B = ch.B
    sh = k["sh_z"]
    # Pan de blouse.
    coat = C.bm_loft([C.ellipse(0, 0.02, z, rx, ry, 14) for z, rx, ry in ((0.95, 0.24, 0.18), (0.6, 0.27, 0.2), (0.35, 0.29, 0.22))],
                     cap_start=False, cap_end=False)
    B.add("coat_tail", coat, M("coat"), sharp=80)
    for k2 in range(5):
        B.sphere("stain%d" % k2, 0.05, (-0.15 + k2 * 0.07, -0.19, 0.5 + (k2 % 2) * 0.25), M("coat_stain"), scale=(1, 0.3, 1.4), outline=False, shadow=False)
    # Bras gauche : tentacule violacé qui pend jusqu'au sol, ventouses.
    hl = k["hand_l"]
    pts = C.bezier((-0.32, 0.0, sh - 0.1), (-0.5, -0.2, sh - 0.6), (-0.42, -0.4, 0.25), (-0.2, -0.45, 0.12), 9)
    B.tube("tentacle", pts, [0.11, 0.1, 0.09, 0.08, 0.07, 0.06, 0.05, 0.035, 0.015], M("mutant_skin"), seg=10)
    for i in (2, 4, 6):
        p = pts[i]
        B.sphere("sucker%d" % i, 0.03, (p[0] + 0.05, p[1] - 0.06, p[2]), M("shell"), outline=False, shadow=False)
    # Réservoir d'acide au dos + lance tenue en main droite (jet d'acide).
    B.cyl("acidtank", 0.15, 0.15, 0.55, (0.0, 0.3, sh - 0.2), M("acid"), seg=14)
    B.cyl("acidcap", 0.16, 0.16, 0.06, (0.0, 0.3, sh + 0.08), M("steel"), seg=14)
    hr = k["hand_r"]
    B.tube("acidhose", C.bezier((0.05, 0.3, sh + 0.1), (0.35, 0.3, sh), (0.4, 0.0, hr[2] + 0.1), hr, 7), [0.03] * 7, M("rubber"), seg=5)
    nz = (hr[0] + 0.28, hr[1] - 0.22, hr[2] + 0.1)
    B.tube("nozzle", [hr, nz], [0.04, 0.03], M("steel"), seg=8)
    B.sphere("drip", 0.05, nz, M("acid"), outline=False)
    # Tête : masque de coquille Saint-Jacques (côtes en éventail), yeux verts.
    hz = sh + 0.36
    B.sphere("head", 0.22, (0, 0.08, hz), M("mutant_skin"), seg=14, rings=9)
    for i in range(9):
        a = math.radians(-60 + i * 15)
        p0 = (0, -0.16, hz - 0.2)
        p1 = (math.sin(a) * 0.3, -0.22 - 0.03 * math.cos(a), hz - 0.2 + math.cos(a) * 0.42)
        B.add("rib%d" % i, C.bm_tube([p0, ((p0[0] + p1[0]) / 2, -0.25, (p0[2] + p1[2]) / 2), p1], [0.02, 0.065, 0.06], seg=8, flat=0.5),
              M("shell" if i % 2 else "shell_rib"), sharp=80)
    B.box("hinge", (0.18, 0.06, 0.07), (0, -0.17, hz - 0.22), M("shell_rib"), bevel=0.02)
    eye_slits(ch, 0, -0.29, hz + 0.02, 0.08, 0.045, 0.03, "eye_green", 0.0)
    ch.head_top = hz + 0.3


def e_heavy(ch: Char) -> None:
    """Garde en scaphandre lourd : armure de laiton et d'acier, casque rond à visière-masque de fer,
    ancre-masse."""
    k = humanoid(ch, "heavy_suit", "brass", "steel", "brass", 1.45, 0.0, arm_r_fwd=0.4, arm_l_fwd=0.3)
    B = ch.B
    sh = k["sh_z"]
    B.cyl("chestplate", 0.38, 0.36, 0.35, (0, -0.02, sh - 0.22), M("brass"), seg=18)
    for sx in (1, -1):
        B.sphere("pauldron%d" % sx, 0.22, (sx * 0.45, 0.02, sh - 0.02), M("brass"), scale=(1, 1, 0.8), seg=14, rings=8)
        for z in (0.25, 0.6):
            B.torus("legband%d%.1f" % (sx, z), 0.15, 0.03, (sx * 0.2, -0.02, z), M("brass"), seg=14, rseg=5)
    # Casque rond de scaphandrier, hublot avant = masque de fer à fente rougeoyante.
    hz = sh + 0.42
    B.cyl("collar", 0.3, 0.3, 0.12, (0, 0, sh + 0.12), M("brass"), seg=18)
    B.sphere("helmet", 0.36, (0, 0.02, hz), M("brass"), seg=20, rings=14)
    plate = C.bm_sphere(16, 10, 1.0)
    for v in plate.verts:
        x, y, z = v.co
        if y > 0:
            y *= 0.2
        v.co = (x * 0.25, y * 0.12, z * 0.27)
    C.bm_xform(plate, loc=(0, -0.32, hz))
    B.add("facemask", plate, M("iron_mask"), sharp=80)
    B.torus("faceframe", 0.26, 0.03, (0, -0.32, hz), M("brass"), rot=(math.pi / 2, 0, 0), seg=18, rseg=5)
    for a in range(6):
        ang = a * math.pi / 3
        B.sphere("bolt%d" % a, 0.03, (math.cos(ang) * 0.26, -0.35, hz + math.sin(ang) * 0.26), M("steel"), outline=False)
    eye_slits(ch, 0, -0.45, hz + 0.04, 0.09, 0.075, 0.022, "eye_orange", 0.15)
    for sx in (1, -1):
        B.cyl("sideport%d" % sx, 0.1, 0.1, 0.06, (sx * 0.34, -0.05, hz), M("rubber"), rot=(0, math.pi / 2, 0), seg=12)
    B.tube("airhose", C.bezier((0.2, 0.3, hz), (0.4, 0.5, hz - 0.2), (0.45, 0.5, sh - 0.5), (0.3, 0.35, sh - 0.6), 6), [0.05] * 6, M("rubber"), seg=6)
    ch.head_top = hz + 0.38
    # Ancre-masse dans la main droite.
    hr = k["hand_r"]
    top = (hr[0] + 0.15, hr[1] - 0.1, hr[2] + 0.55)
    bot = (hr[0] + 0.05, hr[1] - 0.05, hr[2] - 0.55)
    B.tube("shaft", [top, bot], [0.05, 0.05], M("iron_mask"), seg=8)
    B.torus("ring", 0.1, 0.03, (top[0], top[1], top[2] + 0.08), M("iron_mask"), rot=(math.pi / 2, 0, 0), seg=12)
    arm = C.bezier((bot[0] - 0.35, bot[1], bot[2] + 0.25), (bot[0] - 0.2, bot[1], bot[2] - 0.08), (bot[0] + 0.2, bot[1], bot[2] - 0.08), (bot[0] + 0.35, bot[1], bot[2] + 0.25), 7)
    B.tube("flukes", arm, [0.07] * 7, M("iron_mask"), seg=8)
    for p in (arm[0], arm[-1]):
        B.sphere("fluketip%.2f" % p[0], 0.08, p, M("iron_mask"), scale=(1, 0.6, 1.3))


def e_eel(ch: Char) -> None:
    """Anguille masquée : corps en S dressé, nageoire dorsale, masque d'os aux marques rouges,
    taches bioluminescentes."""
    B = ch.B
    pts = C.bezier((-0.55, 0.45, 0.12), (0.7, 0.4, 0.05), (0.6, -0.3, 0.1), (-0.15, -0.1, 0.35), 10)
    pts += C.bezier((-0.15, -0.1, 0.35), (-0.6, 0.05, 0.6), (-0.3, -0.05, 1.1), (0.05, -0.15, 1.3), 8)[1:]
    n = len(pts)
    radii = [0.03 + 0.16 * math.sin(math.pi * min(1.0, (i + 2) / (n + 1))) for i in range(n)]
    radii[-1] = 0.16
    B.tube("body", pts, radii, M("eel"), seg=14)
    for i in range(3, n - 2, 2):
        p = pts[i]
        B.sphere("spot%d" % i, 0.04, (p[0], p[1] - radii[i] * 0.8, p[2] + 0.04), M("biolum"), outline=False, shadow=False)
    fin = [(p[0], p[1] + 0.02, p[2] + radii[i] + 0.08) for i, p in enumerate(pts) if 2 <= i <= n - 3]
    B.add("dorsal", C.bm_tube(fin, [0.03] * len(fin), seg=6, flat=0.4), M("coral_orange"), sharp=80)
    head = pts[-1]
    B.sphere("head", 0.2, (head[0] + 0.05, head[1] - 0.05, head[2] + 0.05), M("eel"), scale=(1.1, 1.3, 0.9), seg=16, rings=10)
    # Mâchoire ouverte et crocs.
    B.sphere("jaw", 0.12, (head[0] + 0.1, head[1] - 0.22, head[2] - 0.1), M("eel_belly"), scale=(1.0, 1.4, 0.5), seg=12, rings=8)
    for k in range(4):
        B.tube("fang%d" % k, [(head[0] + 0.02 + k * 0.05, head[1] - 0.3, head[2] - 0.02), (head[0] + 0.02 + k * 0.05, head[1] - 0.31, head[2] - 0.1)],
               [0.018, 0.0], M("bone"), seg=4, shadow=False)
    # Masque d'os (demi-masque frontal) avec marques rouges.
    mask = C.bm_sphere(16, 10, 1.0)
    for v in mask.verts:
        x, y, z = v.co
        if y > 0:
            y *= 0.25
        if z < -0.2:
            z = -0.2 + (z + 0.2) * 0.3
        v.co = (x * 0.22, y * 0.16, z * 0.2)
    hx, hy, hz = head[0] + 0.06, head[1] - 0.2, head[2] + 0.12
    C.bm_xform(mask, loc=(hx, hy, hz))
    B.add("mask", mask, M("bone", 0.25), sharp=80)
    B.tube("mark", [(hx - 0.02, hy - 0.16, hz + 0.18), (hx + 0.02, hy - 0.17, hz - 0.02)], [0.02, 0.01], M("mask_red"), seg=4, shadow=False)
    for sx in (1, -1):
        B.tube("horn%d" % sx, C.bezier((hx + sx * 0.12, hy + 0.05, hz + 0.1), (hx + sx * 0.22, hy + 0.1, hz + 0.25),
                                        (hx + sx * 0.25, hy + 0.2, hz + 0.35), (hx + sx * 0.3, hy + 0.3, hz + 0.38), 5),
               [0.035, 0.03, 0.02, 0.012, 0.0], M("bone"), seg=6)
    eye_slits(ch, hx, hy - 0.15, hz + 0.03, 0.08, 0.05, 0.022, "eye_red", 0.4)
    ch.head_top = hz + 0.4


def e_guardian(ch: Char) -> None:
    """Gardien des Profondeurs : colosse de roche et de corail, bras énormes, coraux sur les épaules,
    grand masque de pierre ancien aux yeux turquoise."""
    B = ch.B
    rock = "coral_rock"
    for sx in (1, -1):
        B.sphere("leg%d" % sx, 0.32, (sx * 0.38, 0.02, 0.38), M(rock), scale=(1.0, 1.0, 1.3), seg=14, rings=9)
        B.sphere("foot%d" % sx, 0.3, (sx * 0.42, -0.12, 0.14), M(rock), scale=(1.2, 1.3, 0.55), seg=14, rings=8)
    torso = C.bm_loft([C.ellipse(0, 0.05, z, rx, ry, 16) for z, rx, ry in
                       ((0.65, 0.5, 0.38), (1.0, 0.7, 0.48), (1.45, 0.86, 0.55), (1.85, 0.8, 0.5), (2.05, 0.45, 0.36))])
    B.add("torso", torso, M(rock), sharp=80)
    for i, (x, z) in enumerate(((-0.3, 1.2), (0.25, 1.0), (0.4, 1.55), (-0.45, 1.6), (0.0, 1.35))):
        B.sphere("plate%d" % i, 0.2, (x, -0.42, z), M(rock), scale=(1.3, 0.5, 1.0), seg=10, rings=6)
    for i in range(14):
        a = i * 2.4
        x, z = math.cos(a) * 0.55, 0.9 + (i % 7) * 0.15
        B.cyl("barn%d" % i, 0.05, 0.025, 0.07, (x, -0.38 + abs(x) * 0.15, z), M("bone"), rot=(math.pi / 2, 0, 0), seg=8)
    # Bras massifs, poings de roche.
    for sx in (1, -1):
        s = (sx * 0.85, 0.05, 1.75)
        e = (sx * 1.05, -0.15, 1.15)
        h = (sx * 0.95, -0.35, 0.55)
        B.sphere("shoulder%d" % sx, 0.38, s, M(rock), seg=14, rings=9)
        B.tube("uarm%d" % sx, [s, e], [0.28, 0.24], M(rock), seg=12)
        B.tube("farm%d" % sx, [e, h], [0.26, 0.3], M(rock), seg=12)
        B.sphere("fist%d" % sx, 0.34, h, M(rock), scale=(1.0, 1.0, 0.9), seg=14, rings=9)
        # Coraux qui poussent sur les épaules.
        n0 = len(B.objs)
        P._coral(B, "sc%d" % sx, sx * 0.85, 0.1, ["coral_pink", "coral_orange"][sx > 0], 5, 0.75, 11 + sx)
        for ob in B.objs[n0:]:
            ob.location.z += 1.95
    B.sphere("brain", 0.25, (-0.3, 0.25, 2.05), M("coral_purple"), scale=(1.2, 1, 0.7), seg=12, rings=8)
    # Tête : grand masque de pierre ancien (front large, menton pointu), yeux turquoise, cornes de corail.
    hz = 2.25
    B.sphere("head", 0.36, (0, 0.05, hz), M(rock), seg=16, rings=10)
    A = -0.45
    mc = (0, -0.26, hz)
    mask = C.bm_sphere(20, 14, 1.0)
    for v in mask.verts:
        x, y, z = v.co
        if z < 0:
            x *= 1.0 - 0.55 * (-z) ** 1.2
            z *= 1.25
        if y > 0:
            y *= 0.3
        v.co = (x * 0.5, y * 0.26, z * 0.5)
    C.bm_xform(mask, loc=mc, rot=(A, 0, 0))
    B.add("mask", mask, M("bone", 0.25), sharp=80)
    for sx in (1, -1):
        B.tube("mark%d" % sx, [pitch_pt((sx * 0.15, -0.26, 0.36), mc, A), pitch_pt((sx * 0.25, -0.24, 0.1), mc, A), pitch_pt((sx * 0.17, -0.22, -0.3), mc, A)],
               [0.035, 0.03, 0.012], M("coral_orange"), seg=5, shadow=False)
        B.tube("crown%d" % sx, C.bezier((sx * 0.3, -0.1, hz + 0.35), (sx * 0.4, -0.05, hz + 0.65), (sx * 0.55, 0.05, hz + 0.8), (sx * 0.68, 0.1, hz + 1.0), 6),
               [0.09, 0.08, 0.06, 0.045, 0.03, 0.0], M("coral_pink"), seg=8)
    eyes_at(ch, [pitch_pt((0.17, -0.27, 0.1), mc, A), pitch_pt((-0.17, -0.27, 0.1), mc, A)], 0.1, 0.05, "eye_cyan", 0.3, A)
    ch.head_top = hz + 0.95


# kind -> (fonction, cadre px, hauteur visible voulue (monde), ombre (monde), aura, débris, nom)
ENEMIES = {
    "uw_diver": (e_diver, 128, 60.0, 17.0, (0.3, 0.92, 1.0), ["#25343e", "#efe8dc", "#e0782e"]),
    "uw_mutant": (e_mutant, 128, 58.0, 18.0, (0.55, 1.0, 0.35), ["#d6dcd2", "#8a5aa0", "#f0c8b0"]),
    "uw_heavy": (e_heavy, 128, 70.0, 28.0, (1.0, 0.6, 0.18), ["#c89a40", "#5a6670", "#4a4e58"]),
    "uw_eel": (e_eel, 128, 50.0, 22.0, (1.0, 0.25, 0.2), ["#2e5a5a", "#ece2cc", "#5affe0"]),
    "uw_guardian": (e_guardian, 256, 118.0, 48.0, (0.35, 0.95, 1.0), ["#8a7a78", "#e8686e", "#f09048", "#ece2cc"]),
}


def _hex(h: str) -> tuple[float, float, float]:
    h = h.lstrip("#")
    return tuple(round(int(h[i:i + 2], 16) / 255.0, 3) for i in (0, 2, 4))  # type: ignore


def _scene(kind: str, res: int, ortho: float, outline: float):
    fn = ENEMIES[kind][0]
    C.reset_scene()
    C.setup_render((res, res), samples=4, outline_px=outline, inner_ratio=0.45)
    ch = Char()
    fn(ch)
    for ob in ch.B.objs:
        ob.rotation_euler = (0, 0, TURN)
    bpy.context.view_layer.update()
    cam = C.ortho_camera(ELEV, ortho, target=(0, 0, ch.head_top * 0.45), dist=30.0)
    return ch, cam


def render_enemy(kind: str) -> dict:
    from PIL import Image
    fn, frame, target_h, shadow_r, aura, debris = ENEMIES[kind]
    os.makedirs(TMP, exist_ok=True)
    big = os.path.join(TMP, kind + ".big.png")
    # Passe 1 (basse résolution) : emprise du personnage -> cadrage serré de la passe 2.
    ortho = 5.0 if kind == "uw_guardian" else 3.6
    ch, cam = _scene(kind, 192, ortho, 2.0)
    C.render_to(big)
    im = Image.open(big).convert("RGBA")
    bb = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    f1 = C.world_to_px(cam, (0, 0, 0))
    ext = max(96 - bb[0], bb[2] - 96, 96 - bb[1], bb[3] - 96, abs(f1[1] - 96)) + 4
    ortho = ortho * (2 * ext) / 192.0
    res = frame * 2
    ch, cam = _scene(kind, res, ortho, 4.5)
    rot = __import__("mathutils").Matrix.Rotation(TURN, 4, "Z")
    C.render_to(big)
    im = Image.open(big).convert("RGBA")
    feet = C.world_to_px(cam, (0, 0, 0))
    eyes = [C.world_to_px(cam, tuple(rot @ __import__("mathutils").Vector(e))) for e in ch.eyes]
    bb = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    # Hauteur visible (px rendu) : du haut du sprite jusqu'aux pieds.
    vis_h = feet[1] - bb[1]
    # Mise à l'échelle : le sprite (largeur bb, hauteur jusqu'au bas) doit tenir dans le cadre.
    pad = 3
    need_w = (bb[2] - bb[0]) + pad * 2
    need_h = max(bb[3], feet[1]) - bb[1] + pad * 2
    k = min(frame / need_w, frame / need_h)
    small = im.resize((max(1, int(round(im.width * k))), max(1, int(round(im.height * k)))), Image.LANCZOS)
    pm = im.convert("RGBa").resize(small.size, Image.LANCZOS).convert("RGBA")
    out = Image.new("RGBA", (frame, frame), (0, 0, 0, 0))
    fx_s, fy_s = feet[0] * k, feet[1] * k
    bottom_s = max(bb[3], feet[1]) * k
    ox = (frame - (bb[2] - bb[0]) * k) / 2 - bb[0] * k
    oy = frame - pad - bottom_s
    out.alpha_composite(pm, (int(round(ox)), int(round(oy))))
    out = BP._paint(out)
    os.makedirs(OUT, exist_ok=True)
    out.save(os.path.join(OUT, kind + ".png"), optimize=True)
    os.remove(big)
    feet_px = (round(fx_s + round(ox), 1), round(fy_s + round(oy), 1))
    vis_px = vis_h * k
    scale = target_h / vis_px
    eyes_px = [(round(e[0] * k + round(ox), 1), round(e[1] * k + round(oy), 1)) for e in eyes]
    info = {
        "path": "res://assets/sprites/underwater/enemies/%s.png" % kind,
        "size": frame, "feet": feet_px, "scale": round(scale, 4),
        "head": -round(target_h + 6.0, 1), "shadow": shadow_r, "eyes": eyes_px,
        "eye_r": 3.6 if kind == "uw_guardian" else 2.3,
        "aura": aura, "debris": [_hex(d) for d in debris],
    }
    print("ENEMY", kind, json.dumps(info), flush=True)
    return info


def write_kinds(infos: dict) -> None:
    lines = [
        "extends RefCounted",
        "## Visuels des ennemis de la station sous-marine (format EnemyVisual.KINDS), chargés par",
        "## BiomeRegistry. Généré par art/blender/underwater/uw_enemies.py : NE PAS ÉDITER à la main.",
        "## Sprites PNG rendus sous Blender : svg_size = taille du PNG, scale = unités monde par px.",
        "",
        "const KINDS: Dictionary = {",
    ]
    for kind, d in infos.items():
        eyes = ", ".join("Vector2(%s, %s)" % tuple(e) for e in d["eyes"])
        deb = ", ".join("Color(%s, %s, %s)" % tuple(c) for c in d["debris"])
        lines += [
            '\t&"%s": {' % kind,
            '\t\t"path": "%s",' % d["path"],
            '\t\t"svg_size": Vector2(%d, %d), "feet": Vector2(%s, %s), "scale": %s,' % (d["size"], d["size"], d["feet"][0], d["feet"][1], d["scale"]),
            '\t\t"head": Vector2(0, %s), "shadow": %s,' % (d["head"], d["shadow"]),
            '\t\t"eyes": [%s], "eye_r": %s,' % (eyes, d["eye_r"]),
            '\t\t"aura": Color(%s, %s, %s),' % tuple(d["aura"]),
            '\t\t"debris": [%s],' % deb,
            "\t},",
        ]
    lines.append("}")
    with open(KINDS_GD, "w") as f:
        f.write("\n".join(lines) + "\n")


def main() -> None:
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    infos = {}
    cache = os.path.join(TMP, "kinds.json")
    if os.path.exists(cache):
        with open(cache) as f:
            infos = json.load(f)
    for kind in ENEMIES:
        if only and kind not in only:
            continue
        infos[kind] = render_enemy(kind)
    os.makedirs(TMP, exist_ok=True)
    with open(cache, "w") as f:
        json.dump(infos, f)
    write_kinds({k: infos[k] for k in ENEMIES if k in infos})


if __name__ == "__main__":
    main()
