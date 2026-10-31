"""Armes HD : pistolets et revolvers.

Glock 18 (Rare), Desert Eagle (Épique), SIG P320 (Légendaire), Colt Single Action Army (Commun),
S&W Model 29 (Rare), Colt Python (Épique). Silhouettes d'après les proportions réelles (longueur,
hauteur, longueur de canon), mêmes unités que les modèles d'origine (build_weapons.py) :
~0,0045 unité par mm pour les pistolets, ~0,0038 pour les revolvers.
Repère : X = canon vers la droite, Z = haut, côté visible = -Y (côté droit de l'arme).
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import build_weapons as BW  # noqa: E402
import weapon_paint as WP  # noqa: E402
from weapons_hd_kit import (box, cyl_x, cyl_y, grooves, prism, rail, rivets, rounded,  # noqa: E402
                            sphere, tube)

curve2d = BW.curve2d


# --------------------------------------------------------------------------- outils communs

def _extra(m):
    """Matériaux propres à la famille (plaquettes de crosse, acier jaspé, inserts)."""
    P = WP.paint
    m.setdefault("walnut", P("walnut", "#7c4220", "#2c1210", "#b8743e", wood=1.0, gloss=0.35, wear=0.25,
                             grain=0.04, edge="#d89a5c"))
    m.setdefault("walnut_check", P("walnut_check", "#6a3618", "#240e0c", "#a0602e", wood=0.5, gloss=0.2,
                                   grain=0.4, grain_scale=170.0))
    m.setdefault("case", P("case", "#5e5650", "#16141e", "#a49a8c", metal=0.7, wear=0.4, grain=0.05,
                           alt="#4a5a86", alt_scale=12.0, alt_cut=0.6))
    m.setdefault("silver_dark", P("silver_dark", "#6e717c", "#22243a", "#a4a8b4", metal=0.7, grain=0.03))
    m.setdefault("rubber_grip", P("rubber_grip", "#26262b", "#08080d", "#46464f", grain=0.3, grain_scale=150.0,
                                  rim=0.2))
    return m


def _gp(o, ang):
    """Repère incliné d'une poignée : u = vers l'arrière, v = vers le bas le long de la poignée."""
    a = math.radians(ang)
    ca, sa = math.cos(a), math.sin(a)

    def f(u, v):
        return (o[0] - u * ca - v * sa, o[1] + u * sa - v * ca)
    return f


def ftube(name, pts, r, mat, wy, seg=10):
    """Tube d'un chemin dans le plan XZ, de largeur wy en Y (pontets, détentes plates)."""
    p3 = [(p[0], 0.0, p[1]) if len(p) == 2 else p for p in pts]
    return C.mesh_obj(name, C.bm_tube(p3, [r] * len(p3), seg=seg, flat=wy / r, up=(0, -1, 0)), mat)


def screw(x, z, y, r, mat, slot):
    """Vis à tête fendue sur le flanc visible."""
    cyl_y("screw", r, 0.01, (x, y, z), mat, seg=14)
    box("slot", (r * 1.7, 0.004, r * 0.32), (x, y - 0.005, z), slot, rot=(0, 0.6, 0), bevel=0.0)


def _cylinder(m, cx, cz, r, L, mat, flute_mat, flute_len=0.62, n=6):
    """Barillet d'axe X : chanfreins, six cannelures, crans d'arrêt, chambres et bouts de balles."""
    x0, x1 = cx - L / 2, cx + L / 2
    rounded(cyl_x("cylinder", r, r, L - 0.02, (cx, 0, cz), mat, seg=36), 0.006, 2)
    cyl_x("cylF", r, r * 0.86, 0.012, (x1 - 0.004, 0, cz), mat, seg=36)
    cyl_x("cylB", r * 0.9, r, 0.012, (x0 + 0.004, 0, cz), mat, seg=36)
    fl = L * flute_len
    fx = cx + L * 0.06
    for k in range(n):
        a = math.pi / 6 + k * 2 * math.pi / n           # cannelures entre les chambres
        nrm = (0.0, -math.cos(a), math.sin(a))
        rr = r - 0.004
        w = 0.024
        pts = [(fx - fl / 2 + fl * t, nrm[1] * rr, cz + nrm[2] * rr) for t in (0, 0.06, 0.18, 0.5, 0.82, 0.94, 1)]
        rad = [w * 0.35, w * 0.8, w, w, w, w * 0.8, w * 0.35]
        C.mesh_obj("flute", C.bm_tube(pts, rad, seg=12, flat=0.32, up=nrm), flute_mat)
        # cran d'arrêt (entre deux cannelures, vers l'arrière)
        b = a + math.pi / 6
        box("notch", (0.03, 0.012, 0.014), (x0 + 0.03, -math.cos(b) * r, cz + math.sin(b) * r), m["bore"],
            rot=(math.pi / 2 - b, 0, 0), bevel=0.0)
    # chambres (face avant) : bouches sombres et pointes des balles
    for k in range(n):
        a = math.pi / 2 + k * 2 * math.pi / n
        y, z = -math.cos(a) * r * 0.56, cz + math.sin(a) * r * 0.56
        cyl_x("chamber", r * 0.24, r * 0.24, 0.006, (x1 + 0.002, y, z), m["bore"], seg=14)
        sphere("bullet", r * 0.17, (x1 - 0.004, y, z), m["brass"], scale=(0.7, 1, 1), seg=10)
    return x0, x1


def _hammer(m, mat, dz, depth):
    """Chien de revolver : tête qui dépasse du pont, large crête quadrillée tirée vers l'arrière."""
    pts = [(-0.014, 0.17), (-0.01, 0.245), (-0.028, 0.278), (-0.07, 0.302), (-0.115, 0.311), (-0.145, 0.3),
           (-0.142, 0.278), (-0.105, 0.262), (-0.085, 0.245), (-0.075, 0.17)]
    rounded(prism("hammer", [(x, z + dz) for (x, z) in pts], depth, mat), 0.008, 2)
    rounded(prism("hammerCheck", [(x, z + dz) for (x, z) in ((-0.075, 0.3), (-0.115, 0.309), (-0.138, 0.3),
                                                             (-0.132, 0.292), (-0.112, 0.298), (-0.078, 0.29))],
                  depth + 0.006, m["polymer_tex"]), 0.003, 1)
    cyl_y("hammerPin", 0.012, depth + 0.004, (-0.045, 0, 0.2 + dz), m["steel"], seg=12)


def _barrel_end(m, x, z, r, mat):
    """Bouche : couronne et âme sombre."""
    cyl_x("crown", r, r * 0.9, 0.012, (x - 0.004, 0, z), mat)
    cyl_x("bore", r * 0.48, r * 0.48, 0.008, (x + 0.002, 0, z), m["bore"], seg=14)


# --------------------------------------------------------------------------- Glock 18 (Rare)
# Glock 17/18 : 202 × 139 mm, canon 114 mm. Culasse parallélépipédique à nez droit, rainures arrière,
# capot de chambre carré visible sur le dessus ; carcasse polymère, rail à une fente, pontet carré
# à crochet, poignée très inclinée (~20°) à trois creux de doigts ; sélecteur de tir à l'arrière de la
# culasse ; chargeur long de 33 coups qui dépasse sous la poignée.

def pistol_glock18(m):
    m = _extra(m)
    back, front = -0.15, 0.71
    zb, zt = 0.102, 0.238
    hz = (zb + zt) / 2
    sy = -0.059                                           # flanc visible de la culasse
    rounded(prism("slide", [(back, zb), (front - 0.02, zb), (front, zb + 0.02), (front, zt - 0.03),
                            (front - 0.035, zt), (back + 0.015, zt), (back, zt - 0.015)], 0.116, m["gunmetal"]),
            0.012, 2)
    box("slideCut", (front - back - 0.06, 0.12, 0.006), ((front + back) / 2, 0, zb + 0.022), m["bore"], bevel=0.0)
    grooves(back + 0.03, 9, 0.021, (0.009, 0.12, 0.096), hz + 0.008, m["bore"])
    # éjection : fenêtre, capot de chambre carré, extracteur, marquage
    box("port", (0.18, 0.012, 0.056), (0.37, sy + 0.003, zt - 0.03), m["bore"], bevel=0.0)
    rounded(box("hood", (0.12, 0.03, 0.04), (0.33, sy - 0.004, zt - 0.03), m["steel"], bevel=0.004), 0.005, 2)
    box("hoodTop", (0.17, 0.05, 0.012), (0.365, -0.03, zt - 0.004), m["steel"], bevel=0.003)
    box("hoodMark", (0.05, 0.004, 0.01), (0.33, sy - 0.02, zt - 0.03), m["dark"], bevel=0.0)
    box("extractor", (0.085, 0.008, 0.018), (0.235, sy - 0.003, zt - 0.03), m["steel"], bevel=0.003)
    box("slideMark", (0.16, 0.003, 0.016), (0.55, sy - 0.001, hz - 0.01), m["dark"], bevel=0.0)
    # sélecteur de tir (Glock 18) : pivot et levier bronze dans les rainures
    cyl_y("selPivot", 0.02, 0.014, (back + 0.12, sy - 0.005, hz + 0.02), m["bronze"], seg=16)
    rounded(prism("selLever", [(back + 0.105, hz + 0.02), (back + 0.135, hz + 0.02), (back + 0.13, hz - 0.04),
                               (back + 0.11, hz - 0.04)], 0.012, m["bronze"], y=sy - 0.008), 0.004, 2)
    # visée : guidon à point, hausse en U à points blancs
    box("sightF", (0.026, 0.026, 0.024), (front - 0.045, 0, zt + 0.012), m["dark"], bevel=0.004)
    sphere("dotF", 0.007, (front - 0.045, -0.014, zt + 0.016), m["white"], seg=8)
    rounded(prism("sightB", [(back + 0.02, zt), (back + 0.08, zt), (back + 0.07, zt + 0.03), (back + 0.025, zt + 0.03)],
                  0.07, m["dark"]), 0.004, 2)
    sphere("dotB", 0.007, (back + 0.05, -0.036, zt + 0.02), m["white"], seg=8)
    # bouche du canon et logement du ressort récupérateur sur la face avant
    cyl_x("barrel", 0.03, 0.03, 0.012, (front + 0.004, 0, hz + 0.022), m["steel"])
    cyl_x("bore", 0.016, 0.016, 0.006, (front + 0.011, 0, hz + 0.022), m["bore"], seg=14)
    cyl_x("guide", 0.016, 0.016, 0.01, (front + 0.002, 0, zb + 0.004), m["bore"], seg=12)
    # carcasse polymère : cache-poussière, rail à une fente
    rounded(prism("frame", [(back + 0.01, zb), (front - 0.06, zb), (front - 0.06, 0.05), (front - 0.085, 0.03),
                            (0.32, 0.03), (0.06, 0.03), (back + 0.02, 0.06)], 0.11, m["polymer"]), 0.01, 2)
    rounded(box("rail", (0.17, 0.104, 0.024), (0.555, 0, 0.034), m["polymer"], bevel=0.004), 0.004, 2)
    box("railSlot", (0.022, 0.108, 0.02), (0.56, 0, 0.032), m["bore"], bevel=0.0)
    box("frameLogo", (0.07, 0.004, 0.02), (0.43, -0.056, 0.07), m["polymer_tex"], bevel=0.0)
    # pontet carré à crochet, détente à sécurité, arrêtoir de culasse, levier de démontage, goupilles
    ftube("guard", [(0.33, 0.04), (0.335, -0.035), (0.33, -0.072), (0.305, -0.088), (0.20, -0.09),
                    (0.11, -0.086), (0.075, -0.055), (0.065, -0.02)], 0.012, m["polymer"], 0.075)
    box("guardHook", (0.024, 0.07, 0.02), (0.338, 0, -0.082), m["polymer"], bevel=0.006)
    ftube("trigger", [(0.205, 0.035), (0.212, 0.0), (0.205, -0.03), (0.188, -0.055)], 0.011, m["polymer"], 0.03)
    box("trigSafety", (0.006, 0.034, 0.05), (0.208, 0, -0.012), m["steel"], rot=(0, 0.25, 0), bevel=0.002)
    rounded(box("slideStop", (0.11, 0.01, 0.014), (0.13, -0.058, 0.09), m["dark"], bevel=0.003), 0.003, 2)
    box("stopTab", (0.03, 0.012, 0.024), (0.18, -0.06, 0.085), m["dark"], bevel=0.004)
    box("takedown", (0.04, 0.01, 0.012), (0.27, -0.058, 0.092), m["steel"], bevel=0.003)
    for (x, z) in ((0.30, 0.065), (0.17, 0.055), (-0.06, 0.07)):
        cyl_y("pin", 0.009, 0.114, (x, 0, z), m["steel"], seg=12)
    # poignée inclinée à creux de doigts, bec de queue de castor, panneaux granités
    g = _gp((0.08, 0.035), 20.0)
    W, H = 0.21, 0.40
    front_pts = [(0.0, 0.0), (0.0, 0.07), (-0.012, 0.12), (0.006, 0.168), (-0.013, 0.215), (0.006, 0.262),
                 (-0.011, 0.305), (0.0, 0.35), (0.004, H)]
    back_pts = [(W + 0.006, H), (W + 0.004, 0.26), (W - 0.004, 0.14), (W - 0.02, 0.05)]
    prof = [g(u, v) for (u, v) in front_pts] + [g(u, v) for (u, v) in back_pts]
    prof += [(back - 0.025, 0.072), (back - 0.03, 0.09), (back - 0.005, zb), (0.12, zb - 0.02)]
    rounded(prism("grip", prof, 0.122, m["polymer"]), 0.02, 3)
    rounded(prism("stipple", [g(0.035, 0.07), g(W - 0.03, 0.07), g(W - 0.024, H - 0.035), g(0.03, H - 0.035)],
                  0.13, m["polymer_tex"]), 0.006, 2)
    rx, rz = g(0.0, 0.035)
    box("magRelease", (0.024, 0.13, 0.03), (rx + 0.004, 0, rz), m["dark"], bevel=0.005)
    # chargeur long 33 coups : corps polymère, trous témoins, semelle bronze
    mp = [g(0.03, H - 0.02), g(W - 0.035, H - 0.02), g(W - 0.035, H + 0.27), g(0.03, H + 0.27)]
    rounded(prism("mag", mp, 0.1, m["polymer"]), 0.012, 2)
    for k in range(5):
        x, z = g(W - 0.07, H + 0.05 + k * 0.045)
        cyl_y("witness", 0.009, 0.104, (x, 0, z), m["bore"], seg=10)
    rounded(prism("magBase", [g(0.015, H + 0.26), g(W - 0.02, H + 0.26), g(W - 0.02, H + 0.30), g(0.015, H + 0.30)],
                  0.112, m["bronze"]), 0.01, 2)
    gx, gz = g(W * 0.5, 0.17)
    return {"grip": (gx, 0, gz), "muzzle": (front + 0.012, 0, hz + 0.022)}


# --------------------------------------------------------------------------- Desert Eagle (Épique)
# IMI Desert Eagle Mark XIX 6" : 273 × 159 mm, canon 152 mm. Silhouette massive et plate : canon fixe à
# section triangulaire (pan incliné bien visible) qui court jusqu'à la bouche avec rail sur le dessus,
# culasse haute à l'arrière, chien extérieur ajouré, gros pontet carré à crochet, poignée droite.

def pistol_deagle(m):
    m = _extra(m)
    back = -0.22
    zb, zt = 0.10, 0.29
    xs = 0.37                                             # avant de la culasse
    xm = 0.85                                             # bouche
    bz, br = 0.168, 0.056                                 # axe du canon, rayon de la partie ronde
    # canon fixe : section ronde dessous, prisme triangulaire dessus (loft constant)
    sec = []
    for k in range(9):
        a = math.radians(-180 + 22.5 * k)
        sec.append((br * math.cos(a), bz + br * math.sin(a)))
    sec += [(0.053, bz + 0.035), (0.026, zt - 0.006), (-0.026, zt - 0.006), (-0.053, bz + 0.035)]
    sec = [(y, z) for (y, z) in sec]
    secs = [[(x, y, z) for (y, z) in sec] for x in (0.30, xm - 0.02)]
    rounded(C.mesh_obj("barrel", C.bm_loft(secs), m["silver"], smooth=False), 0.006, 2)
    # nez du canon chanfreiné
    nose = [[(xm - 0.02, y, z) for (y, z) in sec], [(xm, y * 0.9, bz + (z - bz) * 0.88) for (y, z) in sec]]
    C.mesh_obj("barrelNose", C.bm_loft(nose), m["silver"], smooth=False)
    _barrel_end(m, xm + 0.002, bz, 0.034, m["silver"])
    box("barrelLine", (xm - xs - 0.02, 0.004, 0.006), ((xm + xs) / 2, -0.056, bz + 0.035), m["dark"], bevel=0.0)
    box("barrelText", (0.2, 0.004, 0.014), (0.58, -0.057, bz + 0.005), m["gold"], bevel=0.0)
    rail(m, 0.42, 0.78, zt, depth=0.05, mat="silver_dark")
    box("sightF", (0.03, 0.03, 0.05), (xm - 0.04, 0, zt + 0.035), m["dark"], bevel=0.004)
    sphere("dotF", 0.008, (xm - 0.04, -0.016, zt + 0.045), m["white"], seg=8)
    # culasse : profil haut, avant biseauté, rainures, levier de sûreté, fenêtre d'éjection et verrou
    rounded(prism("slide", [(back, zb), (xs - 0.04, zb), (xs, zb + 0.04), (xs, zt - 0.02), (xs - 0.02, zt),
                            (back + 0.02, zt), (back, zt - 0.025)], 0.13, m["engraved"]), 0.012, 2)
    grooves(back + 0.035, 9, 0.022, (0.01, 0.134, 0.12), zb + 0.09, m["bore"])
    box("slideLine", (xs - back - 0.04, 0.134, 0.008), ((xs + back) / 2, 0, zb + 0.02), m["gold"], bevel=0.0)
    box("port", (0.19, 0.012, 0.07), (0.17, -0.062, zt - 0.045), m["bore"], bevel=0.0)
    rounded(cyl_x("bolt", 0.03, 0.03, 0.16, (0.17, -0.045, zt - 0.045), m["steel"], seg=16), 0.004, 2)
    for k in range(3):
        box("boltLug", (0.012, 0.01, 0.05), (0.12 + k * 0.04, -0.074, zt - 0.045), m["dark"], bevel=0.0)
    cyl_y("safetyPivot", 0.028, 0.018, (back + 0.07, -0.07, zt - 0.05), m["gold"], seg=18)
    rounded(prism("safety", [(back + 0.06, zt - 0.03), (back + 0.16, zt - 0.06), (back + 0.15, zt - 0.08),
                             (back + 0.06, zt - 0.07)], 0.012, m["gold"], y=-0.074), 0.004, 2)
    rounded(prism("sightB", [(back + 0.03, zt), (back + 0.10, zt), (back + 0.09, zt + 0.035), (back + 0.035, zt + 0.035)],
                  0.08, m["dark"]), 0.004, 2)
    sphere("dotB", 0.007, (back + 0.065, -0.041, zt + 0.022), m["white"], seg=8)
    # chien ajouré
    rounded(prism("hammer", [(back + 0.01, 0.17), (back + 0.01, 0.25), (back - 0.03, 0.29), (back - 0.075, 0.285),
                             (back - 0.08, 0.255), (back - 0.04, 0.2)], 0.05, m["steel"]), 0.008, 2)
    cyl_y("hammerHole", 0.014, 0.054, (back - 0.04, 0, 0.255), m["bore"], seg=14)
    # carcasse : cache-poussière carré sous le canon, levier de démontage, arrêtoir, goupilles
    rounded(prism("frame", [(back + 0.01, zb), (0.52, zb), (0.52, 0.055), (0.495, 0.025), (0.06, 0.025),
                            (back + 0.03, 0.05)], 0.122, m["silver"]), 0.012, 2)
    box("frameLine", (0.3, 0.126, 0.006), (0.36, 0, 0.06), m["bore"], bevel=0.0)
    rounded(box("takedown", (0.05, 0.012, 0.03), (0.42, -0.066, 0.075), m["gold"], bevel=0.005), 0.004, 2)
    rounded(box("slideStop", (0.13, 0.012, 0.018), (0.12, -0.066, 0.085), m["dark"], bevel=0.004), 0.003, 2)
    box("stopTab", (0.035, 0.014, 0.03), (0.06, -0.068, 0.08), m["dark"], bevel=0.004)
    for (x, z) in ((0.3, 0.07), (0.2, 0.055), (-0.10, 0.07)):
        cyl_y("pin", 0.01, 0.126, (x, 0, z), m["gold"], seg=12)
    # pontet carré à crochet, détente dorée
    ftube("guard", [(0.36, 0.035), (0.365, -0.04), (0.36, -0.085), (0.335, -0.102), (0.21, -0.106),
                    (0.11, -0.1), (0.07, -0.06), (0.06, -0.02)], 0.014, m["silver"], 0.085)
    box("guardHook", (0.026, 0.08, 0.024), (0.368, 0, -0.098), m["silver"], bevel=0.006)
    grooves(0.25, 5, 0.02, (0.008, 0.088, 0.03), -0.104, m["dark"])
    ftube("trigger", [(0.215, 0.03), (0.224, -0.01), (0.215, -0.045), (0.195, -0.07)], 0.012, m["gold"], 0.03)
    # poignée : carcasse acier, plaquette bois enveloppante à médaillon, talon du chargeur
    g = _gp((0.06, 0.03), 14.0)
    W, H = 0.23, 0.37
    prof = [g(0, 0), g(-0.004, 0.2), g(0.0, H), g(W, H), g(W + 0.004, 0.2), g(W - 0.01, 0.06)]
    prof += [(back - 0.04, 0.07), (back - 0.05, 0.095), (back + 0.01, zb), (0.12, zb - 0.02)]
    rounded(prism("grip", prof, 0.12, m["silver"]), 0.016, 3)
    rounded(prism("gripPanel", [g(0.025, 0.04), g(W - 0.025, 0.04), g(W - 0.02, H - 0.03), g(0.02, H - 0.03)],
                  0.136, m["walnut"]), 0.02, 3)
    rounded(prism("gripCheck", [g(0.05, 0.12), g(W - 0.05, 0.12), g(W - 0.045, H - 0.06), g(0.045, H - 0.06)],
                  0.14, m["walnut_check"]), 0.006, 2)
    mx, mz = g(W * 0.5, 0.075)
    sphere("medal", 0.03, (mx, -0.07, mz), m["gold"], scale=(1, 0.3, 1), seg=14)
    screw(*g(W * 0.5, H - 0.04), -0.07, 0.012, m["gold"], m["dark"])
    rounded(prism("magBase", [g(-0.005, H - 0.005), g(W + 0.005, H - 0.005), g(W + 0.008, H + 0.035),
                              g(-0.002, H + 0.035)], 0.128, m["steel"]), 0.012, 2)
    gx, gz = g(W * 0.5, 0.18)
    return {"grip": (gx, 0, gz), "muzzle": (xm + 0.006, 0, bz)}


# --------------------------------------------------------------------------- SIG P320 (Légendaire)
# SIG Sauer P320 / M17 : 203 × 140 mm, canon 120 mm. Culasse haute aux arêtes supérieures fortement
# chanfreinées, nez arrondi qui plonge vers le bas, rainures avant et arrière, hausse SIGLITE en
# queue d'aronde ; carcasse à rail trois fentes, pontet arrondi sans crochet, poignée ~18°.
# Finition noire à éclats d'or, commandes et canon dorés.

def pistol_p320(m):
    m = _extra(m)
    back, front = -0.17, 0.73
    zb, zt = 0.104, 0.25
    hz = (zb + zt) / 2
    sy = -0.06
    rounded(prism("slide", [(back, zb), (front - 0.07, zb), (front - 0.02, zb + 0.022), (front, zb + 0.055),
                            (front, zt - 0.05), (front - 0.02, zt - 0.018), (front - 0.06, zt), (back + 0.02, zt),
                            (back, zt - 0.02)], 0.12, m["legend"]), 0.016, 3)
    # chanfreins supérieurs : bande plus sombre le long du haut de la culasse
    box("chamfer", (front - back - 0.09, 0.124, 0.014), ((front + back) / 2 - 0.02, 0, zt - 0.02),
        m["legend_flat"], bevel=0.004)
    box("goldLine", (front - back - 0.08, 0.124, 0.007), ((front + back) / 2 - 0.02, 0, zb + 0.018), m["gold"],
        bevel=0.0)
    grooves(back + 0.03, 8, 0.022, (0.01, 0.124, 0.09), hz + 0.004, m["bore"], rot=(0, -0.12, 0))
    grooves(front - 0.2, 5, 0.022, (0.01, 0.124, 0.07), hz - 0.004, m["bore"], rot=(0, -0.12, 0))
    box("port", (0.19, 0.012, 0.058), (0.36, sy + 0.002, zt - 0.034), m["bore"], bevel=0.0)
    rounded(box("hood", (0.12, 0.03, 0.042), (0.325, sy - 0.004, zt - 0.034), m["gold"], bevel=0.004), 0.005, 2)
    box("hoodTop", (0.18, 0.05, 0.012), (0.36, -0.03, zt - 0.004), m["gold"], bevel=0.003)
    box("extractor", (0.09, 0.008, 0.018), (0.22, sy - 0.003, zt - 0.032), m["gold"], bevel=0.003)
    box("slideMark", (0.13, 0.003, 0.014), (0.52, sy - 0.002, hz - 0.012), m["gold"], bevel=0.0)
    # visée SIGLITE : guidon à point, hausse en queue d'aronde à deux points
    box("sightF", (0.026, 0.028, 0.026), (front - 0.07, 0, zt + 0.012), m["legend_flat"], bevel=0.004)
    sphere("dotF", 0.008, (front - 0.07, -0.015, zt + 0.017), m["gold"], seg=8)
    rounded(prism("sightB", [(back + 0.03, zt), (back + 0.11, zt), (back + 0.1, zt + 0.032), (back + 0.045, zt + 0.034)],
                  0.08, m["legend_flat"]), 0.004, 2)
    sphere("dotB", 0.007, (back + 0.07, -0.041, zt + 0.02), m["white"], seg=8)
    # bouche du canon dorée
    cyl_x("barrel", 0.032, 0.032, 0.014, (front + 0.004, 0, hz + 0.018), m["gold"])
    cyl_x("bore", 0.017, 0.017, 0.006, (front + 0.012, 0, hz + 0.018), m["bore"], seg=14)
    # carcasse : cache-poussière haut à rail, levier de démontage et arrêtoir dorés
    rounded(prism("frame", [(back + 0.01, zb), (front - 0.06, zb), (front - 0.06, 0.045), (front - 0.09, 0.025),
                            (0.06, 0.025), (back + 0.02, 0.055)], 0.112, m["legend_flat"]), 0.012, 2)
    rail(m, 0.47, front - 0.08, 0.02, depth=0.1, mat="legend_flat")
    rounded(box("takedown", (0.05, 0.012, 0.026), (0.28, -0.06, 0.088), m["gold"], bevel=0.004), 0.004, 2)
    rounded(box("slideStop", (0.15, 0.012, 0.016), (0.12, -0.06, 0.09), m["gold"], bevel=0.004), 0.003, 2)
    box("stopTab", (0.035, 0.014, 0.03), (0.06, -0.062, 0.085), m["gold"], bevel=0.004)
    cyl_y("pin", 0.01, 0.116, (0.22, 0, 0.06), m["gold"], seg=12)
    # pontet arrondi, détente plate dorée
    ftube("guard", [(0.335, 0.035), (0.34, -0.03), (0.325, -0.075), (0.29, -0.092), (0.18, -0.094),
                    (0.1, -0.088), (0.07, -0.055), (0.062, -0.02)], 0.013, m["legend_flat"], 0.075)
    ftube("trigger", [(0.205, 0.03), (0.212, -0.005), (0.208, -0.04), (0.195, -0.06)], 0.011, m["gold"], 0.03)
    # poignée : bec de queue de castor, panneaux granités, filet doré, semelle dorée
    g = _gp((0.07, 0.03), 18.0)
    W, H = 0.22, 0.39
    prof = [g(0, 0), g(-0.006, 0.12), g(-0.008, 0.25), g(0.0, H), g(W + 0.006, H), g(W + 0.006, 0.22),
            g(W - 0.004, 0.08)]
    prof += [(back - 0.035, 0.07), (back - 0.045, 0.092), (back + 0.0, zb), (0.12, zb - 0.02)]
    rounded(prism("grip", prof, 0.124, m["legend_flat"]), 0.022, 3)
    rounded(prism("stipple", [g(0.03, 0.08), g(W - 0.03, 0.08), g(W - 0.026, H - 0.04), g(0.026, H - 0.04)],
                  0.132, m["polymer_tex"]), 0.006, 2)
    rounded(prism("gripLine", [g(0.03, 0.06), g(W - 0.03, 0.06), g(W - 0.03, 0.068), g(0.03, 0.068)],
                  0.134, m["gold"]), 0.002, 1)
    box("magRelease", (0.026, 0.13, 0.03), (g(0.0, 0.03)[0] + 0.004, 0, g(0.0, 0.03)[1]), m["gold"], bevel=0.005)
    rounded(prism("magBase", [g(-0.004, H - 0.005), g(W + 0.008, H - 0.005), g(W + 0.01, H + 0.03),
                              g(0.0, H + 0.03)], 0.122, m["gold"]), 0.01, 2)
    gx, gz = g(W * 0.5, 0.17)
    return {"grip": (gx, 0, gz), "muzzle": (front + 0.016, 0, hz + 0.018)}


# --------------------------------------------------------------------------- Colt SAA (Commun)
# Colt Single Action Army 4¾" : 260 × ~130 mm. Canon fin et rond, logement de tige d'éjection tubulaire
# sous le canon côté droit (bouton près de la bouche), axe du barillet qui dépasse à l'avant, portière de
# chargement derrière le barillet, trois vis alignées sur la carcasse, chien à longue crête, petit pontet
# rond, crosse « manche de charrue » très courbée en noyer.

def revolver_peacemaker(m):
    m = _extra(m)
    cx, cz, r, L = 0.10, 0.14, 0.082, 0.165
    bz = cz + r * 0.56                                    # axe du canon = chambre du haut
    xf = 0.215                                            # avant de la carcasse
    xm = 0.69                                             # bouche
    fy = -0.062
    x0, x1 = _cylinder(m, cx, cz, r, L, m["blued"], m["dark"], flute_len=0.7)
    # carcasse : bouclier arrière arrondi, pont supérieur, dessous, avant de carcasse
    rounded(prism("frameBack", [(-0.04, 0.242), (x0 + 0.004, 0.242), (x0 + 0.004, 0.04), (-0.005, 0.02),
                                (-0.06, 0.02), (-0.075, 0.12), (-0.065, 0.2)], 0.125, m["blued"]), 0.012, 2)
    cyl_x("shield", r * 0.98, r * 0.98, 0.016, (x0 - 0.006, 0, cz), m["blued"], seg=32)
    rounded(box("topStrap", (xf - x0 + 0.01, 0.07, 0.024), ((xf + x0) / 2, 0, 0.23), m["blued"], bevel=0.004), 0.004, 2)
    box("sightGroove", (xf - x0, 0.012, 0.004), ((xf + x0) / 2, 0, 0.243), m["bore"], bevel=0.0)
    rounded(prism("frameLow", [(x0, 0.06), (xf + 0.01, 0.06), (xf + 0.01, 0.045), (xf - 0.03, 0.025), (x0, 0.025)],
                  0.1, m["blued"]), 0.008, 2)
    rounded(prism("frameFront", [(x1 + 0.005, 0.242), (xf + 0.01, 0.242), (xf + 0.012, 0.05), (x1 + 0.005, 0.03)],
                  0.11, m["blued"]), 0.01, 2)
    # axe du barillet, vis de verrouillage, portière, trois vis de carcasse
    cyl_x("basePin", 0.012, 0.012, 0.06, (xf + 0.03, 0, cz), m["steel"], seg=12)
    cyl_x("basePinHead", 0.02, 0.02, 0.018, (xf + 0.06, 0, cz), m["steel"], seg=14)
    screw(xf - 0.005, 0.105, fy, 0.011, m["steel"], m["bore"])
    rounded(prism("gate", [(x0 - 0.03, 0.08), (x0 + 0.004, 0.08), (x0 + 0.004, 0.165), (x0 - 0.02, 0.165)], 0.012,
                  m["case"], y=fy - 0.002), 0.004, 2)
    for (x, z) in ((-0.035, 0.165), (-0.02, 0.075), (0.005, 0.045)):
        screw(x, z, fy - 0.002, 0.01, m["steel"], m["bore"])
    # canon rond et guidon en demi-lune
    cyl_x("barrel", 0.034, 0.031, xm - xf, ((xm + xf) / 2, 0, bz), m["blued"], seg=24)
    cyl_x("barrelCollar", 0.038, 0.038, 0.02, (xf + 0.008, 0, bz), m["blued"], seg=24)
    _barrel_end(m, xm + 0.002, bz, 0.031, m["blued"])
    prism("sightF", [(xm - 0.05, bz + 0.026), (xm - 0.008, bz + 0.026), (xm - 0.012, bz + 0.05),
                     (xm - 0.03, bz + 0.052)], 0.012, m["blued"])
    # logement de tige d'éjection (côté droit) : tube, fente, bouton, vis
    ey, ez, er = -0.026, cz - 0.002, 0.022
    rounded(cyl_x("ejHousing", er, er, xm - 0.07 - xf, ((xm - 0.07 + xf) / 2, ey, ez), m["blued"], seg=18), 0.004, 2)
    cyl_x("ejNose", er, er * 0.7, 0.018, (xm - 0.061, ey, ez), m["blued"], seg=18)
    box("ejSlot", (0.28, 0.008, 0.008), (xf + 0.19, ey - er + 0.001, ez), m["bore"], bevel=0.0)
    cyl_y("ejButton", 0.017, 0.022, (xm - 0.12, ey - er - 0.004, ez), m["steel"], seg=16)
    cyl_x("ejRod", 0.009, 0.009, 0.04, (xf + 0.01, ey, ez), m["steel"], seg=10)
    screw(xm - 0.09, ez + 0.024, ey - 0.012, 0.008, m["steel"], m["bore"])
    # chien à longue crête quadrillée
    _hammer(m, m["case"], -0.012, 0.08)
    # pontet rond, détente fine
    ftube("guard", [(0.06, 0.03), (0.07, -0.02), (0.05, -0.07), (0.0, -0.082), (-0.035, -0.06), (-0.04, -0.025)],
          0.011, m["blued"], 0.05)
    ftube("trigger", [(0.012, 0.03), (0.022, 0.0), (0.015, -0.03), (-0.002, -0.05)], 0.009, m["case"], 0.024)
    # crosse « manche de charrue » : cadre acier et plaquette noyer
    gpts = curve2d(((0.0, 0.03), (-0.04, -0.06), (-0.09, -0.15), (-0.115, -0.205)),
                   ((-0.115, -0.205), (-0.135, -0.24), (-0.225, -0.245), (-0.262, -0.215)),
                   ((-0.262, -0.215), (-0.27, -0.1), (-0.19, 0.06), (-0.105, 0.17)),
                   (-0.07, 0.205), (-0.04, 0.12), n=8)
    rounded(prism("gripFrame", gpts, 0.11, m["blued"]), 0.014, 3)
    panel = curve2d(((-0.035, -0.005), (-0.065, -0.07), (-0.105, -0.15), (-0.125, -0.19)),
                    ((-0.125, -0.19), (-0.145, -0.222), (-0.215, -0.226), (-0.244, -0.2)),
                    ((-0.244, -0.2), (-0.25, -0.1), (-0.18, 0.04), (-0.1, 0.13)),
                    (-0.065, 0.08), n=8)
    rounded(prism("gripPanel", panel, 0.132, m["walnut"]), 0.02, 3)
    screw(-0.155, -0.07, -0.066, 0.012, m["steel"], m["bore"])
    return {"grip": (-0.15, 0, -0.08), "muzzle": (xm + 0.008, 0, bz)}


# --------------------------------------------------------------------------- S&W Model 29 (Rare)
# Smith & Wesson Model 29 8⅜" : ~350 × 150 mm. Long canon effilé à bande pleine, guidon à rampe avec insert
# rouge, carénage d'éjecteur court sous la base du canon, hausse réglable sur le pont, plaque latérale
# vissée côté droit, chien et détente « target » jaspés, crosse bois target quadrillée à médaillon.

def revolver_model29(m):
    m = _extra(m)
    cx, cz, r, L = 0.10, 0.14, 0.086, 0.17
    bz = cz + r * 0.58
    xf = 0.215
    xm = 1.02
    fy = -0.064
    x0, x1 = _cylinder(m, cx, cz, r, L, m["gunmetal"], m["dark"], flute_len=0.55)
    # carcasse N : bouclier, pont supérieur, avant, dessous, plaque latérale
    rounded(prism("frameBack", [(-0.05, 0.252), (x0 + 0.004, 0.252), (x0 + 0.004, 0.04), (-0.005, 0.02),
                                (-0.07, 0.03), (-0.08, 0.13), (-0.07, 0.21)], 0.13, m["gunmetal"]), 0.012, 2)
    cyl_x("shield", r * 0.96, r * 0.96, 0.016, (x0 - 0.006, 0, cz), m["gunmetal"], seg=32)
    rounded(box("topStrap", (xf - x0 + 0.01, 0.08, 0.03), ((xf + x0) / 2, 0, 0.24), m["gunmetal"], bevel=0.005),
            0.004, 2)
    rounded(prism("frameLow", [(x0, 0.055), (xf + 0.01, 0.055), (xf + 0.01, 0.04), (xf - 0.03, 0.02), (x0, 0.02)],
                  0.11, m["gunmetal"]), 0.008, 2)
    rounded(prism("frameFront", [(x1 + 0.004, 0.255), (xf + 0.012, 0.255), (xf + 0.012, 0.05), (x1 + 0.004, 0.03)],
                  0.12, m["gunmetal"]), 0.01, 2)
    rounded(prism("sideplate", [(-0.065, 0.2), (x0 - 0.012, 0.215), (x0 - 0.012, 0.05), (-0.02, 0.03), (-0.06, 0.05)],
                  0.134, m["gunmetal"]), 0.006, 2)
    for (x, z) in ((-0.045, 0.18), (-0.04, 0.07), (x0 - 0.03, 0.2)):
        screw(x, z, fy - 0.004, 0.0095, m["steel"], m["bore"])
    box("yoke", (0.035, 0.012, 0.06), (x1 + 0.0, fy + 0.002, 0.07), m["gunmetal"], bevel=0.004)
    # hausse réglable sur le pont
    rounded(prism("sightR", [(-0.055, 0.252), (0.06, 0.252), (0.055, 0.268), (-0.02, 0.272), (-0.05, 0.29),
                             (-0.06, 0.28)], 0.06, m["dark"]), 0.004, 2)
    cyl_y("sightScrew", 0.008, 0.064, (-0.02, 0, 0.274), m["steel"], seg=10)
    # long canon effilé à bande pleine, guidon à rampe rouge
    cyl_x("barrel", 0.038, 0.032, xm - xf, ((xm + xf) / 2, 0, bz), m["gunmetal"], seg=24)
    rounded(prism("rib", [(xf, bz + 0.024), (xm, bz + 0.02), (xm, bz + 0.042), (xf, bz + 0.048)], 0.03,
                  m["gunmetal"]), 0.004, 2)
    box("ribLine", (xm - xf - 0.02, 0.032, 0.004), ((xm + xf) / 2, 0, bz + 0.042), m["bore"], bevel=0.0)
    _barrel_end(m, xm + 0.002, bz, 0.032, m["gunmetal"])
    rounded(prism("sightF", [(xm - 0.1, bz + 0.042), (xm - 0.008, bz + 0.042), (xm - 0.008, bz + 0.095),
                             (xm - 0.03, bz + 0.095)], 0.02, m["gunmetal"]), 0.004, 2)
    prism("sightRed", [(xm - 0.034, bz + 0.065), (xm - 0.012, bz + 0.065), (xm - 0.012, bz + 0.09),
                       (xm - 0.028, bz + 0.09)], 0.024, m["red"])
    box("barrelText", (0.24, 0.004, 0.012), (0.55, -0.034, bz - 0.002), m["dark"], bevel=0.0)
    # carénage court de la tige d'éjection
    rounded(prism("shroud", [(xf - 0.005, bz - 0.01), (0.5, bz - 0.01), (0.5, cz - 0.03), (0.47, cz - 0.05),
                             (xf - 0.005, cz - 0.05)], 0.07, m["gunmetal"]), 0.018, 3)
    cyl_x("ejTip", 0.016, 0.016, 0.016, (0.505, 0, cz - 0.022), m["steel"], seg=12)
    # chien et détente « target » jaspés
    _hammer(m, m["steel"], 0.0, 0.09)
    ftube("guard", [(0.08, 0.025), (0.088, -0.03), (0.065, -0.082), (0.01, -0.094), (-0.03, -0.07),
                    (-0.04, -0.03)], 0.012, m["gunmetal"], 0.055)
    ftube("trigger", [(0.03, 0.025), (0.04, -0.01), (0.032, -0.045), (0.01, -0.065)], 0.012, m["case"], 0.04)
    grooves(0.02, 3, 0.012, (0.004, 0.044, 0.02), -0.02, m["bore"], rot=(0, 0.4, 0))
    # crosse target bois : remplit l'arrière du pontet, quadrillage, médaillon
    gpts = curve2d(((-0.03, 0.03), (-0.04, -0.03), (-0.075, -0.06), (-0.085, -0.12)),
                   ((-0.085, -0.12), (-0.095, -0.18), (-0.11, -0.23), (-0.125, -0.262)),
                   ((-0.125, -0.262), (-0.15, -0.285), (-0.245, -0.28), (-0.275, -0.245)),
                   ((-0.275, -0.245), (-0.27, -0.12), (-0.2, 0.03), (-0.1, 0.15)),
                   (-0.075, 0.2), (-0.05, 0.1), n=8)
    rounded(prism("grip", gpts, 0.15, m["walnut"]), 0.024, 3)
    rounded(prism("gripCheck", [(-0.11, -0.05), (-0.2, -0.04), (-0.245, -0.22), (-0.14, -0.235)], 0.156,
                  m["walnut_check"]), 0.008, 2)
    sphere("medal", 0.02, (-0.12, -0.077, 0.03), m["silver"], scale=(1, 0.3, 1), seg=14)
    return {"grip": (-0.17, 0, -0.10), "muzzle": (xm + 0.008, 0, bz)}


# --------------------------------------------------------------------------- Colt Python (Épique)
# Colt Python 6" : ~292 × 140 mm. Bande ventilée sur toute la longueur (fenêtres ajourées), tenon plein
# sous le canon jusqu'à la bouche, guidon à rampe rouge, hausse Accro, finition nickelée gravée, crosse
# target en noyer à médaillon doré.

def revolver_python(m):
    m = _extra(m)
    cx, cz, r, L = 0.10, 0.14, 0.084, 0.17
    bz = cz + r * 0.58
    xf = 0.215
    xm = 0.80
    fy = -0.062
    x0, x1 = _cylinder(m, cx, cz, r, L, m["silver"], m["silver_dark"], flute_len=0.62)
    # carcasse gravée
    rounded(prism("frameBack", [(-0.05, 0.25), (x0 + 0.004, 0.25), (x0 + 0.004, 0.04), (-0.005, 0.02),
                                (-0.07, 0.03), (-0.08, 0.13), (-0.07, 0.21)], 0.128, m["engraved"]), 0.012, 2)
    cyl_x("shield", r * 0.97, r * 0.97, 0.016, (x0 - 0.006, 0, cz), m["engraved"], seg=32)
    rounded(box("topStrap", (xf - x0 + 0.01, 0.076, 0.03), ((xf + x0) / 2, 0, 0.238), m["engraved"], bevel=0.005),
            0.004, 2)
    rounded(prism("frameLow", [(x0, 0.055), (xf + 0.01, 0.055), (xf + 0.01, 0.04), (xf - 0.03, 0.02), (x0, 0.02)],
                  0.11, m["engraved"]), 0.008, 2)
    rounded(prism("frameFront", [(x1 + 0.004, 0.253), (xf + 0.012, 0.253), (xf + 0.012, 0.05), (x1 + 0.004, 0.03)],
                  0.12, m["engraved"]), 0.01, 2)
    for (x, z) in ((-0.04, 0.17), (-0.035, 0.07)):
        screw(x, z, fy - 0.004, 0.0095, m["gold"], m["bore"])
    box("goldLine", (xf - x0, 0.08, 0.006), ((xf + x0) / 2, 0, 0.225), m["gold"], bevel=0.0)
    # hausse Accro
    rounded(prism("sightR", [(-0.05, 0.25), (0.05, 0.25), (0.045, 0.266), (-0.02, 0.27), (-0.045, 0.288),
                             (-0.055, 0.278)], 0.06, m["silver_dark"]), 0.004, 2)
    # canon, bande ventilée (montants et fenêtres), tenon plein jusqu'à la bouche
    cyl_x("barrel", 0.036, 0.036, xm - xf, ((xm + xf) / 2, 0, bz), m["silver"], seg=24)
    _barrel_end(m, xm + 0.002, bz, 0.034, m["silver"])
    rt = bz + 0.075                                       # dessus de la bande
    rounded(box("rib", (xm - xf, 0.042, 0.016), ((xm + xf) / 2, 0, rt - 0.008), m["silver"], bevel=0.004), 0.003, 2)
    box("ribTop", (xm - xf - 0.02, 0.044, 0.003), ((xm + xf) / 2, 0, rt), m["silver_dark"], bevel=0.0)
    nv = 7
    span = (xm - 0.06) - (xf + 0.01)
    step = span / nv
    for k in range(nv + 1):
        xx = xf + 0.01 + k * step
        rounded(box("ribPost", (0.026, 0.036, rt - bz - 0.03), (xx, 0, (bz + 0.02 + rt - 0.012) / 2 + 0.004),
                    m["silver"], bevel=0.003), 0.003, 2)
    box("ribBase", (xm - xf, 0.03, 0.012), ((xm + xf) / 2, 0, bz + 0.032), m["silver"], bevel=0.003)
    rounded(prism("underlug", [(xf - 0.005, bz - 0.01), (xm, bz - 0.01), (xm, cz - 0.02), (xm - 0.025, cz - 0.045),
                               (xm - 0.06, cz - 0.05), (xf - 0.005, cz - 0.05)], 0.072, m["silver"]), 0.018, 3)
    box("lugText", (0.22, 0.004, 0.012), (0.48, -0.037, cz - 0.022), m["gold"], bevel=0.0)
    box("barrelLine", (xm - xf - 0.04, 0.074, 0.005), ((xm + xf) / 2, 0, bz - 0.032), m["gold"], bevel=0.0)
    rounded(prism("sightF", [(xm - 0.1, rt), (xm - 0.01, rt), (xm - 0.012, rt + 0.04), (xm - 0.03, rt + 0.04)],
                  0.022, m["silver"]), 0.004, 2)
    prism("sightRed", [(xm - 0.036, rt + 0.018), (xm - 0.014, rt + 0.018), (xm - 0.016, rt + 0.036),
                       (xm - 0.03, rt + 0.036)], 0.026, m["red"])
    # chien et détente
    _hammer(m, m["silver"], -0.004, 0.085)
    ftube("guard", [(0.08, 0.025), (0.088, -0.03), (0.065, -0.08), (0.01, -0.092), (-0.03, -0.068),
                    (-0.04, -0.03)], 0.012, m["engraved"], 0.055)
    ftube("trigger", [(0.03, 0.025), (0.04, -0.01), (0.032, -0.045), (0.01, -0.065)], 0.011, m["gold"], 0.034)
    # crosse target noyer à médaillon doré
    gpts = curve2d(((-0.03, 0.03), (-0.04, -0.03), (-0.075, -0.06), (-0.085, -0.12)),
                   ((-0.085, -0.12), (-0.095, -0.18), (-0.11, -0.23), (-0.125, -0.262)),
                   ((-0.125, -0.262), (-0.15, -0.285), (-0.245, -0.28), (-0.275, -0.245)),
                   ((-0.275, -0.245), (-0.27, -0.12), (-0.2, 0.03), (-0.1, 0.15)),
                   (-0.075, 0.2), (-0.05, 0.1), n=8)
    rounded(prism("grip", gpts, 0.15, m["walnut"]), 0.024, 3)
    rounded(prism("gripCheck", [(-0.11, -0.06), (-0.2, -0.05), (-0.245, -0.22), (-0.14, -0.235)], 0.156,
                  m["walnut_check"]), 0.008, 2)
    sphere("medal", 0.026, (-0.125, -0.077, 0.02), m["gold"], scale=(1, 0.3, 1.15), seg=14)
    return {"grip": (-0.17, 0, -0.10), "muzzle": (xm + 0.008, 0, bz)}


WEAPONS = {"pistol_glock18": pistol_glock18, "pistol_deagle": pistol_deagle, "pistol_p320": pistol_p320,
           "revolver_peacemaker": revolver_peacemaker, "revolver_model29": revolver_model29,
           "revolver_python": revolver_python}
