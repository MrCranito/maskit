"""Armes HD — lance-grenades et lance-roquettes : M79 (Commun), China Lake (Rare), M32 (Épique),
RPG-7 (Rare), M202 FLASH (Épique), FGM-148 Javelin (Légendaire).

Références de silhouette (profil) :
- M79 : arme à bascule type « fusil scié », canon de 40 mm court et gros (36 cm sur 73 cm), devant
  en bois sous le canon, hausse à cadre repliable sur le canon, verrou de bascule sur le dessus de la
  carcasse, crosse bois et plaque de couche caoutchouc (Wikipédia « M79 grenade launcher »).
- China Lake : lance-grenades à pompe, gros canon au-dessus d'un tube magasin, devant de pompe, crosse
  de fusil de chasse, hausse à échelle.
- M32 (Milkor MGL) : barillet à 6 coups, canon aligné sur la chambre haute, carcasse ouverte avec
  rail, gros viseur réflexe, poignée avant verticale, crosse rétractable.
- RPG-7 : tube d'acier de 95 cm, manchon pare-chaleur en bois au milieu, évasement arrière à bord
  roulé, poignée pistolet à détente à l'avant et poignée arrière bois, lunette PGO-7 sur le côté
  gauche, roquette PG-7V (ogive conique, corps renflé, tube stabilisateur à ailettes) dépassant à
  l'avant (Wikipédia « RPG-7 », Australian War Memorial C286388).
- M202 FLASH : caisson rectangulaire de quatre tubes de 66 mm (68,6 cm fermé), couvercles avant et
  arrière, poignée pistolet, viseur réflexe à gauche, poignée de transport (Wikipédia « M202 FLASH »).
- FGM-148 Javelin : tube de lancement de 1,2 m (Ø 127 mm) à gros embouts amortisseurs, unité de
  commande et de visée (CLU) amovible fixée sur le côté, deux poignées, oculaire caoutchouc, gros
  objectif de vision nocturne, bloc batterie/refroidissement sous le tube (Wikipédia « FGM-148 Javelin »).
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


# --------------------------------------------------------------------------- briques locales

def screw(x, z, y, mat, slot, r=0.012):
    """Vis à tête fendue vue de côté."""
    sphere("screw", r, (x, y, z), mat, scale=(1, 0.5, 1), seg=10)
    box("slot", (r * 1.8, 0.004, r * 0.35), (x, y - r * 0.45, z), slot, rot=(0, 0.6, 0), bevel=0.0)


def ring_x(name, r, w, x, z, mat, y=0.0, seg=32):
    return cyl_x(name, r, r, w, (x, y, z), mat, seg=seg)


def bands_x(x0, x1, n, r, w, z, mat, y=0.0, seg=32):
    for k in range(n):
        ring_x("band", r, w, x0 + (x1 - x0) * (k + 0.5) / n, z, mat, y=y, seg=seg)


def stencil(x0, z, y, mat, n=6, h=0.016, step=0.03, seed=1):
    """Marquage pochoir : petits traits clairs de longueurs variées (texte illisible à cette taille)."""
    for k in range(n):
        w = 0.012 + ((seed * 7 + k * 5) % 4) * 0.006
        box("mark", (w, 0.004, h), (x0 + k * step, y, z), mat, bevel=0.0)


def lpaint():
    """Matériaux propres aux lanceurs (ajoutés à mats())."""
    P = WP.paint
    return {
        "alu": P("l_alu", "#3e4048", "#11121c", "#7a7e8c", metal=0.55, wear=0.5, grain=0.04, edge="#a8acba"),
        "fibre": P("l_fibre", "#6a4024", "#24120e", "#9a6438", grain=0.25, grain_scale=160.0, wear=0.2),
        "warhead": P("l_warhead", "#8a2a22", "#30101a", "#c8543e", gloss=0.25, wear=0.35, grain=0.05),
        "od": P("l_od", "#4e5636", "#181c14", "#7a8456", wear=0.4, grain=0.07),
        "od_light": P("l_od_light", "#6a7148", "#22261a", "#9aa070", wear=0.35, grain=0.06),
        "yellow": P("l_yellow", "#d8b22c", "#5c3e18", "#ffe070", wear=0.25),
        "stencil": P("l_stencil", "#e8e2c8", "#8a8676", "#ffffff", ao=0.1, grain=0.0, rim=0.0),
        "checker": P("l_checker", "#6e3c1e", "#2a1214", "#9a5c34", grain=0.5, grain_scale=260.0, wear=0.1),
        "leather": P("l_leather", "#5a3a22", "#1e100c", "#8a5a36", grain=0.15, grain_scale=120.0, wear=0.3),
    }


# --------------------------------------------------------------------------- M79 (Commun)

def gl_m79(m):
    m = {**m, **lpaint()}
    bz, br = 0.24, 0.10
    # Canon de 40 mm en aluminium : bague de bouche, rayures visibles, tête de grenade au fond de l'âme.
    cyl_x("barrel", br, br, 0.74, (0.50, 0, bz), m["alu"], seg=40)
    ring_x("breechRing", br + 0.008, 0.04, 0.15, bz, m["blued"])
    ring_x("muzzleRing", br + 0.006, 0.035, 0.855, bz, m["blued"])
    cyl_x("bore", 0.078, 0.078, 0.012, (0.872, 0, bz), m["bore"], seg=32)
    for k in range(6):
        a = k * math.pi / 3
        box("rifling", (0.014, 0.012, 0.016), (0.874, 0.074 * math.cos(a), bz + 0.074 * math.sin(a)), m["dark"],
            rot=(a, 0, 0), bevel=0.0)
    cyl_x("roundNose", 0.05, 0.02, 0.04, (0.86, 0, bz), m["olive"], seg=16)
    # Guidon (lame sur embase) près de la bouche.
    box("fsBase", (0.07, 0.05, 0.03), (0.80, 0, bz + br + 0.008), m["blued"], bevel=0.006)
    prism("fsBlade", [(0.78, bz + br + 0.02), (0.82, bz + br + 0.02), (0.815, bz + br + 0.085),
                      (0.795, bz + br + 0.085)], 0.014, m["blued"])
    # Hausse à cadre relevée : embase, deux montants gradués, traverses, curseur à œilleton.
    box("leafBase", (0.13, 0.11, 0.035), (0.28, 0, bz + br + 0.01), m["blued"], bevel=0.006)
    cyl_y("leafHinge", 0.02, 0.12, (0.24, 0, bz + br + 0.03), m["steel"])
    for yy in (-0.042, 0.042):
        tube("leafSide", [(0.24, yy, bz + br + 0.03), (0.30, yy, bz + br + 0.30)], 0.011, m["blued"], seg=8)
    for t in (0.0, 1.0):
        tube("leafCross", [(0.24 + 0.06 * t, -0.044, bz + br + 0.03 + 0.27 * t),
                           (0.24 + 0.06 * t, 0.044, bz + br + 0.03 + 0.27 * t)], 0.011, m["blued"], seg=8)
    for k in range(1, 8):
        t = k / 8.0
        box("leafTick", (0.006, 0.004, 0.003), (0.24 + 0.06 * t - 0.012, -0.054, bz + br + 0.03 + 0.27 * t),
            m["white"], bevel=0.0)
    box("leafSlider", (0.04, 0.11, 0.035), (0.275, 0, bz + br + 0.19), m["steel"], rot=(0, -0.22, 0),
        bevel=0.005)
    cyl_y("peep", 0.012, 0.114, (0.275, 0, bz + br + 0.19), m["bore"])
    # Carcasse : bloc d'acier bleui, axe de bascule, verrou sur le dessus, sûreté, vis.
    rounded(prism("receiver", [(-0.20, 0.33), (0.13, 0.33), (0.14, 0.30), (0.14, 0.13), (0.10, 0.09),
                               (-0.12, 0.09), (-0.20, 0.13)], 0.15, m["blued"]), 0.012, 2)
    box("recLine", (0.30, 0.004, 0.008), (-0.03, -0.077, 0.15), m["dark"], bevel=0.0)
    cyl_y("hinge", 0.03, 0.16, (0.10, 0, 0.13), m["steel"])
    cyl_y("hingeC", 0.018, 0.166, (0.10, 0, 0.13), m["dark"])
    rounded(prism("latch", [(-0.14, 0.33), (-0.02, 0.33), (-0.04, 0.37), (-0.12, 0.38), (-0.16, 0.36)], 0.06,
                  m["steel"]), 0.008, 2)
    grooves(-0.12, 4, 0.022, (0.008, 0.064, 0.02), 0.365, m["dark"])
    box("safety", (0.06, 0.035, 0.02), (-0.24, 0, 0.325), m["steel"], bevel=0.005)
    for (x, z) in ((-0.15, 0.27), (0.06, 0.27), (-0.15, 0.15)):
        screw(x, z, -0.078, m["steel"], m["bore"])
    # Pontet large (gants) et détente.
    tube("guard", [(0.08, 0, 0.10), (0.07, 0, -0.02), (-0.06, 0, -0.04), (-0.17, 0, 0.0), (-0.20, 0, 0.09)],
         0.016, m["blued"], seg=8)
    tube("trigger", [(-0.02, 0, 0.10), (-0.005, 0, 0.05), (-0.025, 0, 0.0)], 0.014, m["dark"], seg=8)
    # Devant bois sous le canon, avec vis et quadrillage.
    rounded(prism("forend", [(0.13, 0.20), (0.58, 0.20), (0.62, 0.17), (0.58, 0.115), (0.18, 0.10),
                             (0.13, 0.13)], 0.16, m["wood"]), 0.03, 3)
    rounded(prism("checker", [(0.26, 0.185), (0.46, 0.185), (0.45, 0.125), (0.27, 0.12)], 0.164,
                  m["checker"]), 0.006, 2)
    screw(0.50, 0.155, -0.082, m["steel"], m["bore"])
    # Battant de bretelle sous le canon et sous la crosse.
    box("swivelBase", (0.05, 0.04, 0.03), (0.66, 0, bz - br - 0.01), m["blued"], bevel=0.005)
    tube("swivel", [(0.64, 0, bz - br - 0.02), (0.64, 0, bz - br - 0.07), (0.69, 0, bz - br - 0.07),
                    (0.69, 0, bz - br - 0.02)], 0.008, m["steel"], seg=8)
    # Crosse bois (poignée semi-pistolet), plaque de couche caoutchouc striée.
    prof = BW.curve2d((-0.19, 0.32), ((-0.19, 0.32), (-0.45, 0.31), (-0.70, 0.29), (-0.90, 0.28)),
                      (-0.90, -0.12), ((-0.90, -0.12), (-0.70, -0.06), (-0.52, 0.0), (-0.44, -0.03)),
                      ((-0.44, -0.03), (-0.36, 0.0), (-0.30, 0.13), (-0.19, 0.13)), n=8)
    rounded(prism("stock", prof, 0.14, m["wood"]), 0.035, 3)
    box("stockInlay", (0.30, 0.144, 0.006), (-0.62, 0, 0.215), m["wood_dark"], bevel=0.0)
    rounded(prism("butt", [(-0.90, 0.29), (-0.96, 0.30), (-0.97, -0.15), (-0.90, -0.14)], 0.15, m["rubber"]),
            0.015, 2)
    for z in (0.22, 0.12, 0.02, -0.08):
        box("buttLine", (0.066, 0.154, 0.006), (-0.935, 0, z), m["bore"], bevel=0.0)
    rivets([(-0.905, 0.24), (-0.905, -0.09)], 0.011, m["steel"], -0.074)
    box("swivelB", (0.04, 0.04, 0.03), (-0.72, 0, -0.085), m["blued"], rot=(0, -0.25, 0), bevel=0.005)
    tube("swivel2", [(-0.74, 0, -0.10), (-0.74, 0, -0.15), (-0.69, 0, -0.14), (-0.69, 0, -0.09)], 0.008,
         m["steel"], seg=8)
    return {"grip": (-0.32, 0, 0.04), "muzzle": (0.88, 0, bz)}


# --------------------------------------------------------------------------- China Lake (Rare)

def gl_china_lake(m):
    m = {**m, **lpaint()}
    bz, mz = 0.29, 0.12
    # Carcasse en acier patiné : fenêtre d'éjection (grenade en laiton visible), sûreté, arrêtoir, vis.
    rounded(prism("receiver", [(-0.20, 0.38), (0.36, 0.38), (0.40, 0.34), (0.40, 0.05), (0.32, 0.03),
                               (-0.12, 0.03), (-0.20, 0.10)], 0.17, m["gunmetal"]), 0.015, 2)
    box("recLine", (0.56, 0.004, 0.008), (0.10, -0.087, 0.30), m["dark"], bevel=0.0)
    rounded(box("port", (0.24, 0.012, 0.11), (0.16, -0.085, 0.24), m["bore"], bevel=0.0), 0.01, 2)
    cyl_x("shell", 0.045, 0.045, 0.16, (0.15, -0.07, 0.24), m["brass"], seg=16)
    cyl_x("shellNose", 0.045, 0.028, 0.06, (0.26, -0.07, 0.24), m["olive"], seg=16)
    ring_x("shellRim", 0.05, 0.012, 0.07, 0.24, m["brass"], y=-0.07, seg=16)
    box("elevator", (0.10, 0.012, 0.03), (0.16, -0.084, 0.175), m["steel"], bevel=0.004)
    box("boltRel", (0.05, 0.016, 0.03), (0.30, -0.09, 0.12), m["dark"], bevel=0.005)
    cyl_y("safety", 0.02, 0.19, (-0.13, 0, 0.12), m["dark"])
    for (x, z) in ((-0.12, 0.30), (0.33, 0.08), (-0.05, 0.08)):
        screw(x, z, -0.088, m["steel"], m["bore"])
    stencil(-0.02, 0.33, -0.088, m["stencil"], n=5, h=0.012, step=0.026, seed=3)
    # Hausse à échelle (repliée vers l'avant) sur le dessus de la carcasse.
    box("ladBase", (0.10, 0.09, 0.03), (0.30, 0, 0.395), m["dark"], bevel=0.005)
    prism("ladder", [(0.26, 0.40), (0.56, 0.42), (0.56, 0.445), (0.28, 0.43)], 0.07, m["dark"])
    for k in range(5):
        box("ladStep", (0.008, 0.074, 0.008), (0.32 + k * 0.05, 0, 0.43 + k * 0.003), m["steel"], bevel=0.0)
    # Canon de 40 mm (bague, âme rayée) au-dessus du tube magasin.
    cyl_x("barrel", 0.078, 0.078, 0.98, (0.89, 0, bz), m["blued"], seg=36)
    ring_x("muzzle", 0.086, 0.05, 1.355, bz, m["gunmetal"])
    cyl_x("bore", 0.06, 0.06, 0.012, (1.382, 0, bz), m["bore"], seg=28)
    cyl_x("rnose", 0.04, 0.015, 0.03, (1.37, 0, bz), m["olive"], seg=12)
    box("fsBase", (0.07, 0.05, 0.03), (1.30, 0, bz + 0.088), m["gunmetal"], bevel=0.006)
    prism("fsBlade", [(1.285, bz + 0.10), (1.315, bz + 0.10), (1.31, bz + 0.16), (1.29, bz + 0.16)], 0.014,
          m["dark"])
    # Tube magasin, bouchon, collier reliant canon et magasin.
    cyl_x("magTube", 0.068, 0.068, 0.80, (0.79, 0, mz), m["gunmetal"], seg=32)
    ring_x("magCap", 0.074, 0.05, 1.205, mz, m["dark"])
    cyl_x("capNub", 0.03, 0.03, 0.02, (1.24, 0, mz), m["steel"], seg=12)
    rounded(prism("band", [(1.11, bz + 0.07), (1.17, bz + 0.07), (1.17, mz - 0.07), (1.11, mz - 0.07)], 0.15,
                  m["dark"]), 0.01, 2)
    screw(1.14, (bz + mz) / 2, -0.078, m["steel"], m["bore"])
    tube("swivel", [(1.12, 0, mz - 0.07), (1.12, 0, mz - 0.12), (1.16, 0, mz - 0.12), (1.16, 0, mz - 0.07)],
         0.008, m["steel"], seg=8)
    # Devant de pompe en bois strié (bronze aux extrémités), barres d'action.
    rounded(cyl_x("pump", 0.10, 0.10, 0.40, (0.82, 0, mz), m["wood"], seg=32), 0.01, 2)
    for k in range(8):
        ring_x("pumpGroove", 0.103, 0.014, 0.67 + k * 0.042, mz, m["wood_dark"])
    ring_x("pumpCapB", 0.104, 0.03, 0.605, mz, m["bronze"])
    ring_x("pumpCapF", 0.104, 0.03, 1.035, mz, m["bronze"])
    box("actionBar", (0.22, 0.012, 0.02), (0.50, -0.07, mz + 0.03), m["steel"], bevel=0.0)
    # Pontet, détente.
    tube("guard", [(0.14, 0, 0.04), (0.12, 0, -0.08), (-0.02, 0, -0.10), (-0.10, 0, -0.05), (-0.12, 0, 0.04)],
         0.016, m["gunmetal"], seg=8)
    tube("trigger", [(0.04, 0, 0.04), (0.055, 0, -0.01), (0.035, 0, -0.06)], 0.014, m["dark"], seg=8)
    # Crosse de chasse bois veiné, plaque de couche, battant.
    prof = BW.curve2d((-0.19, 0.37), ((-0.19, 0.37), (-0.45, 0.35), (-0.75, 0.32), (-0.98, 0.31)),
                      (-0.98, -0.15), ((-0.98, -0.15), (-0.70, -0.08), (-0.46, -0.0), (-0.38, 0.0)),
                      ((-0.38, 0.0), (-0.30, 0.05), (-0.24, 0.08), (-0.19, 0.11)), n=8)
    rounded(prism("stock", prof, 0.14, m["wood"]), 0.035, 3)
    for k in range(4):
        box("gripChk", (0.004, 0.144, 0.10), (-0.36 + k * 0.03, 0, 0.12), m["wood_dark"], rot=(0, 0.45, 0),
            bevel=0.0)
    rounded(prism("butt", [(-0.98, 0.32), (-1.03, 0.33), (-1.04, -0.17), (-0.98, -0.16)], 0.15, m["rubber"]),
            0.015, 2)
    for z in (0.24, 0.12, 0.0, -0.10):
        box("buttLine", (0.056, 0.154, 0.006), (-1.01, 0, z), m["bore"], bevel=0.0)
    rivets([(-0.985, 0.27), (-0.985, -0.11)], 0.011, m["steel"], -0.074)
    tube("swivel2", [(-0.78, 0, -0.08), (-0.78, 0, -0.13), (-0.73, 0, -0.12), (-0.73, 0, -0.07)], 0.008,
         m["steel"], seg=8)
    return {"grip": (-0.34, 0, 0.06), "muzzle": (1.385, 0, bz)}


# --------------------------------------------------------------------------- M32 MGL (Épique)

def gl_m32(m):
    m = {**m, **lpaint()}
    cx, cz, r, L = 0.25, 0.10, 0.19, 0.40
    bz = cz + 0.12
    # Carcasse : bloc arrière (poignée), longeron supérieur, plaque avant, longerons de liaison.
    rounded(prism("rear", [(-0.18, 0.34), (0.05, 0.34), (0.05, -0.05), (-0.02, -0.08), (-0.18, -0.04)], 0.16,
                  m["tan"]), 0.02, 3)
    rounded(prism("topStrap", [(-0.18, 0.40), (0.62, 0.40), (0.64, 0.36), (0.62, 0.33), (-0.18, 0.33)], 0.10,
                  m["tan"]), 0.012, 2)
    rail(m, -0.16, 0.62, 0.415, 0.08, mat="dark")
    rounded(prism("frontPlate", [(cx + L / 2 + 0.01, 0.36), (cx + L / 2 + 0.07, 0.36),
                                 (cx + L / 2 + 0.07, -0.08), (cx + L / 2 + 0.01, -0.08)], 0.17, m["tan"]),
            0.015, 2)
    for (x, z) in ((-0.12, 0.28), (0.00, 0.28), (cx + L / 2 + 0.04, 0.30), (cx + L / 2 + 0.04, -0.04),
                   (-0.12, 0.0)):
        screw(x, z, -0.086, m["silver"], m["bore"], r=0.013)
    stencil(-0.15, 0.20, -0.084, m["stencil"], n=4, h=0.012, step=0.03, seed=2)
    # Axe et barillet cannelé à six chambres (couronne arrière gravée), culots de grenades en laiton.
    cyl_x("axis", 0.03, 0.03, L + 0.16, (cx, 0, cz), m["silver"], seg=12)
    cyl_x("cylCore", r * 0.78, r * 0.78, L - 0.02, (cx, 0, cz), m["olive_dark"], seg=48)
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        yy, zz = -0.118 * math.cos(a), cz + 0.118 * math.sin(a)
        rounded(cyl_x("chamber", 0.072, 0.072, L - 0.04, (cx, yy, zz), m["olive_dark"], seg=28), 0.01, 2)
    ring_x("cylRear", r + 0.004, 0.035, cx - L / 2 + 0.018, cz, m["engraved"], seg=48)
    ring_x("cylFront", r + 0.004, 0.03, cx + L / 2 - 0.015, cz, m["engraved"], seg=48)
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        yy, zz = -0.115 * math.cos(a), cz + 0.115 * math.sin(a)
        if yy < 0.02:
            cyl_x("nose", 0.05, 0.028, 0.035, (cx + L / 2 + 0.01, yy * 0.9, zz), m["brass"], seg=14)
    # Canon rayé (40 mm) sur la chambre haute, garde-main à rails, bouche.
    cyl_x("barrel", 0.072, 0.072, 0.40, (0.70, 0, bz), m["dark"], seg=36)
    rounded(prism("handguard", [(0.52, bz + 0.10), (0.90, bz + 0.10), (0.92, bz + 0.08), (0.92, bz - 0.09),
                                (0.52, bz - 0.09)], 0.16, m["tan"]), 0.012, 2)
    for k in range(4):
        rounded(box("vent", (0.05, 0.006, 0.028), (0.60 + k * 0.08, -0.08, bz + 0.005), m["bore"], bevel=0.0),
                0.012, 2)
    rail(m, 0.52, 0.90, bz + 0.112, 0.07, mat="dark")
    rail(m, 0.56, 0.90, bz - 0.10, 0.07, mat="dark")
    ring_x("muzzle", 0.08, 0.05, 0.95, bz, m["silver"])
    cyl_x("bore", 0.058, 0.058, 0.012, (0.976, 0, bz), m["bore"], seg=28)
    # Viseur réflexe M2 : boîtier, molettes, vitre teintée.
    rounded(prism("opticBase", [(-0.02, 0.43), (0.24, 0.43), (0.24, 0.47), (-0.02, 0.47)], 0.08, m["dark"]),
            0.006, 2)
    rounded(prism("optic", [(-0.02, 0.47), (0.22, 0.47), (0.26, 0.52), (0.26, 0.62), (0.0, 0.62),
                            (-0.04, 0.58)], 0.11, m["olive_dark"]), 0.015, 3)
    box("optWin", (0.008, 0.08, 0.08), (0.262, 0, 0.56), m["glass"], bevel=0.0)
    cyl_y("knob", 0.03, 0.13, (0.08, 0, 0.55), m["dark"])
    cyl_y("knob2", 0.022, 0.13, (0.17, 0, 0.59), m["dark"])
    box("optLabel", (0.08, 0.004, 0.02), (0.06, -0.057, 0.50), m["stencil"], bevel=0.0)
    # Poignée avant verticale, poignée pistolet, pontet, détente.
    rounded(prism("vgrip", [(0.66, bz - 0.11), (0.78, bz - 0.11), (0.77, -0.18), (0.74, -0.21), (0.67, -0.21),
                            (0.65, -0.18)], 0.10, m["olive_dark"]), 0.025, 3)
    for k in range(4):
        box("vgRib", (0.11, 0.104, 0.008), (0.715, 0, 0.0 - k * 0.045), m["bore"], bevel=0.0)
    rounded(BW.grip("grip", -0.02, -0.04, m["olive_dark"], h=0.32, w=0.13, slant=0.22), 0.025, 3)
    prism("gripTex", [(-0.05, -0.08), (-0.13, -0.08), (-0.19, -0.33), (-0.11, -0.33)], 0.135, m["polymer_tex"])
    tube("guard", [(0.05, 0, -0.06), (0.04, 0, -0.17), (-0.06, 0, -0.18), (-0.08, 0, -0.07)], 0.015, m["tan"],
         seg=8)
    tube("trigger", [(-0.005, 0, -0.06), (0.008, 0, -0.10), (-0.01, 0, -0.14)], 0.013, m["silver"], seg=8)
    # Crosse rétractable : tube, crosse beige, plaque de couche, attache de sangle.
    cyl_x("stockTube", 0.04, 0.04, 0.40, (-0.36, 0, 0.24), m["silver"], seg=16)
    for k in range(5):
        ring_x("notch", 0.042, 0.008, -0.34 + k * 0.05, 0.24, m["dark"], seg=16)
    rounded(prism("stock", [(-0.48, 0.34), (-0.48, 0.16), (-0.62, 0.08), (-0.84, 0.04), (-0.84, 0.36),
                            (-0.62, 0.36)], 0.13, m["tan"]), 0.03, 3)
    box("stockCut", (0.14, 0.134, 0.06), (-0.68, 0, 0.22), m["bore"], bevel=0.02)
    rounded(box("butt", (0.05, 0.14, 0.34), (-0.865, 0, 0.20), m["rubber"]), 0.012, 2)
    for z in (0.30, 0.20, 0.10):
        box("buttLine", (0.054, 0.144, 0.006), (-0.865, 0, z), m["bore"], bevel=0.0)
    box("lever", (0.06, 0.02, 0.025), (-0.52, -0.075, 0.12), m["silver"], bevel=0.005)
    return {"grip": (-0.12, 0, -0.20), "muzzle": (0.98, 0, bz)}


# --------------------------------------------------------------------------- RPG-7 (Rare)

def rocket_rpg7(m):
    m = {**m, **lpaint()}
    tz, tr = 0.20, 0.06
    # Tube d'acier, évasement arrière (venturi) à bord roulé.
    cyl_x("tube", tr, tr, 1.34, (0.15, 0, tz), m["gunmetal"], seg=32)
    cyl_x("bell", tr + 0.004, 0.125, 0.26, (-0.67, 0, tz), m["gunmetal"], seg=40)
    ring_x("bellRim", 0.13, 0.022, -0.80, tz, m["steel"], seg=40)
    cyl_x("bellIn", 0.108, 0.108, 0.01, (-0.81, 0, tz), m["bore"], seg=32)
    ring_x("bellCollar", tr + 0.016, 0.04, -0.50, tz, m["dark"])
    # Manchon pare-chaleur bois (deux demi-coquilles, colliers et vis), section centrale.
    rounded(cyl_x("woodSleeve", 0.092, 0.092, 0.56, (-0.14, 0, tz), m["wood"], seg=36), 0.01, 2)
    box("woodSplit", (0.56, 0.188, 0.006), (-0.14, 0, tz), m["wood_dark"], bevel=0.0)
    for x in (-0.42, 0.14):
        ring_x("sleeveBand", 0.098, 0.03, x, tz, m["dark"])
        screw(x, tz - 0.06, -0.08, m["steel"], m["bore"], r=0.01)
    for x in (-0.30, -0.14, 0.02):
        screw(x, tz + 0.04, -0.088, m["steel"], m["bore"], r=0.009)
    # Avant du tube : collier, embouchure.
    ring_x("muzzleCollar", tr + 0.012, 0.04, 0.80, tz, m["dark"])
    # Organes de visée de secours : guidon avant, hausse rabattable.
    box("fsBase", (0.05, 0.04, 0.05), (0.74, 0, tz + tr + 0.02), m["dark"], bevel=0.006)
    box("fsPost", (0.012, 0.012, 0.06), (0.74, 0, tz + tr + 0.07), m["dark"], bevel=0.0)
    box("rsBase", (0.06, 0.05, 0.04), (0.30, 0, tz + tr + 0.015), m["dark"], bevel=0.006)
    prism("rsLeaf", [(0.28, tz + tr + 0.03), (0.32, tz + tr + 0.03), (0.33, tz + tr + 0.10),
                     (0.29, tz + tr + 0.10)], 0.03, m["dark"])
    # Lunette PGO-7 sur son support (côté gauche, dépasse au-dessus) : corps, oculaire, bonnette.
    sy = 0.06
    rounded(prism("scopeMount", [(0.36, tz + 0.02), (0.50, tz + 0.02), (0.50, tz + 0.12), (0.36, tz + 0.12)],
                  0.04, m["dark"], y=sy), 0.006, 2)
    zs = tz + 0.17
    rounded(prism("scopeBody", [(0.32, zs - 0.05), (0.54, zs - 0.05), (0.56, zs - 0.03), (0.56, zs + 0.04),
                                (0.54, zs + 0.055), (0.32, zs + 0.055)], 0.09, m["olive_dark"], y=sy), 0.012,
            2)
    cyl_x("scopeObj", 0.042, 0.048, 0.08, (0.59, sy, zs + 0.005), m["olive_dark"], seg=24)
    cyl_x("scopeLens", 0.04, 0.04, 0.006, (0.633, sy, zs + 0.005), m["glass"], seg=24)
    cyl_x("scopeEye", 0.036, 0.036, 0.10, (0.27, sy, zs), m["olive_dark"], seg=24)
    cyl_x("eyeCup", 0.036, 0.05, 0.08, (0.18, sy, zs), m["rubber"], seg=24)
    cyl_y("scopeKnob", 0.025, 0.13, (0.44, sy, zs + 0.01), m["dark"])
    cyl_y("scopeKnob2", 0.018, 0.12, (0.38, sy, zs + 0.06), m["dark"])
    # Poignée pistolet de détente (avant, plaquettes quadrillées) et poignée arrière bois.
    rounded(box("trigHouse", (0.20, 0.07, 0.07), (0.30, 0, tz - tr - 0.02), m["gunmetal"], bevel=0.01), 0.008,
            2)
    rounded(BW.grip("grip", 0.32, tz - tr - 0.04, m["bakelite"], h=0.30, w=0.11, slant=0.18), 0.02, 3)
    for k in range(4):
        box("gripChk", (0.10, 0.104, 0.006), (0.26 - k * 0.016, 0, tz - tr - 0.10 - k * 0.05), m["wood_dark"],
            bevel=0.0)
    tube("guard", [(0.40, 0, tz - tr - 0.05), (0.40, 0, tz - tr - 0.15), (0.32, 0, tz - tr - 0.17),
                   (0.30, 0, tz - tr - 0.06)], 0.012, m["gunmetal"], seg=8)
    tube("trigger", [(0.355, 0, tz - tr - 0.05), (0.365, 0, tz - tr - 0.09), (0.35, 0, tz - tr - 0.12)],
         0.011, m["dark"], seg=8)
    cyl_y("hammer", 0.022, 0.05, (0.19, 0, tz - tr - 0.02), m["steel"])
    rounded(BW.grip("grip2", -0.02, tz - 0.08, m["wood"], h=0.24, w=0.10, slant=0.10), 0.02, 3)
    box("grip2Clamp", (0.13, 0.08, 0.03), (-0.06, 0, tz - 0.085), m["dark"], bevel=0.006)
    tube("sling", [(-0.30, 0, tz - 0.09), (-0.30, 0, tz - 0.14), (-0.25, 0, tz - 0.14), (-0.25, 0, tz - 0.09)],
         0.008, m["steel"], seg=8)
    # Roquette PG-7V : tube stabilisateur à ailettes repliées, corps renflé, ogive conique, fusée.
    cyl_x("stab", 0.034, 0.034, 0.22, (0.94, 0, tz), m["steel"], seg=16)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        box("fin", (0.18, 0.004, 0.02), (0.93, -0.036 * math.cos(a), tz + 0.036 * math.sin(a)), m["dark"],
            rot=(math.pi - a, 0, 0), bevel=0.0)
    cyl_x("motor", 0.04, 0.05, 0.08, (1.08, 0, tz), m["olive"], seg=24)
    cyl_x("head1", 0.05, 0.11, 0.10, (1.16, 0, tz), m["warhead"], seg=40)
    cyl_x("head2", 0.11, 0.105, 0.14, (1.28, 0, tz), m["warhead"], seg=40)
    ring_x("headBand", 0.112, 0.016, 1.22, tz, m["yellow"], seg=40)
    cyl_x("cone", 0.105, 0.03, 0.28, (1.49, 0, tz), m["olive"], seg=40)
    stencil(1.24, tz + 0.04, -0.105, m["stencil"], n=3, h=0.012, step=0.03, seed=5)
    cyl_x("fuze", 0.03, 0.016, 0.07, (1.665, 0, tz), m["brass"], seg=16)
    sphere("fuzeTip", 0.017, (1.70, 0, tz), m["brass"], seg=12)
    return {"grip": (0.25, 0, tz - tr - 0.20), "muzzle": (1.71, 0, tz)}


# --------------------------------------------------------------------------- M202 FLASH (Épique)

def rocket_m202(m):
    m = {**m, **lpaint()}
    x0, x1, z0, z1 = -0.60, 1.18, 0.06, 0.42
    zc, d = (z0 + z1) / 2, 0.19
    # Caisson à quatre tubes : panneau latéral embouti, nervures, rivets, plaques signalétiques.
    rounded(box("clip", (x1 - x0, d * 2, z1 - z0), ((x0 + x1) / 2, 0, zc), m["tan"], bevel=0.02), 0.01, 2)
    for x in (-0.40, 0.10, 0.62, 1.00):
        rounded(box("rib", (0.06, d * 2 + 0.012, z1 - z0 + 0.012), (x, 0, zc), m["olive_dark"], bevel=0.01),
                0.006, 2)
    box("panelGroove", (x1 - x0 - 0.10, 0.006, 0.008), ((x0 + x1) / 2, -d - 0.002, zc), m["olive_dark"],
        bevel=0.0)
    rivets([(x, z) for x in (-0.40, 0.10, 0.62, 1.00) for z in (z0 + 0.04, z1 - 0.04)], 0.011, m["silver"],
           -d - 0.008)
    box("dataPlate", (0.22, 0.006, 0.10), (0.36, -d - 0.004, zc + 0.04), m["engraved"], bevel=0.004)
    for k in range(3):
        box("dataLine", (0.17, 0.004, 0.008), (0.36, -d - 0.008, zc + 0.07 - k * 0.025), m["bore"], bevel=0.0)
    stencil(-0.30, zc + 0.05, -d - 0.004, m["stencil"], n=7, h=0.018, step=0.04, seed=4)
    stencil(-0.30, zc - 0.01, -d - 0.004, m["stencil"], n=5, h=0.014, step=0.04, seed=8)
    box("yellowBand", (0.05, d * 2 + 0.004, z1 - z0 + 0.004), (0.84, 0, zc), m["yellow"], bevel=0.004)
    # Bouches des quatre tubes à l'avant (roquettes visibles), couvercle avant relevé.
    for (yy, zz) in ((-0.09, zc - 0.09), (-0.09, zc + 0.09), (0.09, zc - 0.09), (0.09, zc + 0.09)):
        ring_x("tubeMouth", 0.082, 0.08, x1 + 0.03, zz, m["olive_dark"], y=yy, seg=28)
        ring_x("tubeLip", 0.086, 0.015, x1 + 0.065, zz, m["silver"], y=yy, seg=28)
        cyl_x("mouthBore", 0.068, 0.068, 0.01, (x1 + 0.074, yy, zz), m["bore"], seg=24)
        cyl_x("rocketNose", 0.05, 0.012, 0.07, (x1 + 0.05, yy, zz), m["silver"], seg=16)
        ring_x("tubeRear", 0.08, 0.04, x0 - 0.01, zz, m["olive_dark"], y=yy, seg=28)
    box("frontFrame", (0.03, d * 2 + 0.01, z1 - z0 + 0.01), (x1 - 0.005, 0, zc), m["olive_dark"], bevel=0.006)
    cyl_y("coverHinge", 0.018, d * 2 + 0.02, (x1 + 0.0, 0, z1 + 0.005), m["silver"])
    rounded(box("rearCover", (0.03, d * 2 + 0.01, z1 - z0 + 0.01), (x0 - 0.04, 0, zc), m["olive_dark"],
                bevel=0.01), 0.008, 2)
    box("rearLatch", (0.05, 0.03, 0.06), (x0 - 0.03, -d - 0.012, zc), m["silver"], bevel=0.006)
    # Poignée de transport sur le dessus.
    tube("carry", [(0.00, 0, z1), (0.04, 0, z1 + 0.10), (0.44, 0, z1 + 0.10), (0.48, 0, z1)], 0.018,
         m["olive_dark"], seg=10)
    for x in (0.0, 0.48):
        box("carryFoot", (0.06, 0.06, 0.02), (x, 0, z1 + 0.008), m["silver"], bevel=0.005)
    # Viseur réflexe rabattable côté gauche du tireur (dépasse au-dessus), cadre et vitre.
    sy = d + 0.03
    box("sightArm", (0.04, 0.03, 0.16), (0.70, sy, z1 + 0.02), m["olive_dark"], bevel=0.006)
    rounded(box("sightHead", (0.16, 0.06, 0.12), (0.70, sy, z1 + 0.14), m["olive_dark"], bevel=0.012), 0.008, 2)
    box("sightGlass", (0.008, 0.05, 0.08), (0.785, sy, z1 + 0.145), m["glass"], bevel=0.0)
    box("sightRet", (0.006, 0.054, 0.012), (0.788, sy, z1 + 0.145), m["led"], bevel=0.0)
    # Poignée pistolet, pontet, détente, boîtier de mise à feu, appui d'épaule.
    rounded(box("fireHouse", (0.30, 0.10, 0.07), (0.05, 0, z0 - 0.03), m["olive_dark"], bevel=0.012), 0.008, 2)
    cyl_y("fireSel", 0.03, 0.12, (-0.04, 0, z0 - 0.03), m["silver"])
    box("fireSelPtr", (0.05, 0.005, 0.01), (-0.04, -0.062, z0 - 0.02), m["bore"], rot=(0, 0.6, 0), bevel=0.0)
    rounded(BW.grip("grip", 0.12, z0 - 0.06, m["olive_dark"], h=0.30, w=0.12, slant=0.16), 0.022, 3)
    prism("gripTex", [(0.09, z0 - 0.10), (0.02, z0 - 0.10), (-0.02, z0 - 0.34), (0.05, z0 - 0.34)], 0.124,
          m["polymer_tex"])
    tube("guard", [(0.20, 0, z0 - 0.06), (0.20, 0, z0 - 0.18), (0.10, 0, z0 - 0.20), (0.11, 0, z0 - 0.07)],
         0.013, m["silver"], seg=8)
    tube("trigger", [(0.155, 0, z0 - 0.065), (0.165, 0, z0 - 0.11), (0.15, 0, z0 - 0.15)], 0.012, m["dark"],
         seg=8)
    rounded(prism("shoulder", [(-0.56, z0), (-0.36, z0), (-0.40, z0 - 0.08), (-0.58, z0 - 0.12),
                               (-0.62, z0 - 0.06)], 0.14, m["rubber"]), 0.02, 3)
    tube("strap", [(-0.50, -d - 0.006, z1 - 0.01), (-0.50, -d - 0.006, z0 + 0.02)], 0.012, m["canvas"], seg=6)
    return {"grip": (0.04, 0, z0 - 0.22), "muzzle": (x1 + 0.08, 0, zc)}


# --------------------------------------------------------------------------- FGM-148 Javelin (Légendaire)

def rocket_javelin(m):
    m = {**m, **lpaint()}
    tz, tr = 0.24, 0.13
    # Tube de lancement vert olive, embouts amortisseurs noirs nervurés, filets dorés, marquages.
    cyl_x("tube", tr, tr, 1.66, (0.30, 0, tz), m["olive_dark"], seg=48)
    for (x, s) in ((-0.62, -1), (1.22, 1)):
        cyl_x("endCap", 0.185, 0.185, 0.20, (x, 0, tz), m["legend_flat"], seg=48)
        ring_x("capRib", 0.19, 0.03, x, tz, m["rubber"], seg=48)
        cyl_x("capCham", 0.185, 0.15, 0.04, (x + s * 0.12, 0, tz), m["legend_flat"], seg=48)
        ring_x("capLip", 0.15, 0.02, x + s * 0.15, tz, m["legend"], seg=48)
        ring_x("capGold", 0.188, 0.012, x - s * 0.1, tz, m["gold"], seg=48)
    cyl_x("frontFace", 0.12, 0.12, 0.01, (1.375, 0, tz), m["legend_flat"], seg=32)
    cyl_x("seekerDome", 0.08, 0.02, 0.025, (1.385, 0, tz), m["glass"], seg=24)
    for x in (0.10, 0.62, 0.98):
        ring_x("goldBand", tr + 0.004, 0.025, x, tz, m["gold"], seg=48)
    box("yellowStripe", (0.30, 0.008, 0.024), (0.80, -tr + 0.012, tz + 0.06), m["yellow"], bevel=0.0)
    stencil(0.68, tz + 0.01, -tr - 0.002, m["stencil"], n=8, h=0.018, step=0.032, seed=6)
    stencil(0.68, tz - 0.03, -tr - 0.002, m["stencil"], n=6, h=0.014, step=0.032, seed=9)
    # Sangle de transport le long du tube.
    tube("strap", [(-0.50, -0.06, tz + tr - 0.004), (-0.30, -0.075, tz + tr - 0.0), (0.60, -0.075, tz + tr - 0.0),
                   (1.08, -0.06, tz + tr - 0.004)], 0.014, m["canvas"], seg=6)
    for x in (-0.50, 1.08):
        box("strapLoop", (0.05, 0.03, 0.04), (x, -0.06, tz + tr), m["gold"], bevel=0.006)
    # Bloc batterie / refroidissement (BCU) sous le tube avant.
    rounded(cyl_x("bcu", 0.055, 0.055, 0.26, (0.48, -0.02, tz - tr - 0.03), m["legend_flat"], seg=24), 0.008, 2)
    ring_x("bcuCap", 0.06, 0.03, 0.62, tz - tr - 0.03, m["gold"], y=-0.02, seg=24)
    # Unité de commande et de visée (CLU) fixée sur le côté du tube, à l'arrière.
    cy = -tr - 0.07
    x0, x1, zb, zt = -0.30, 0.26, tz - 0.10, tz + 0.20
    rounded(prism("cluHinge", [(-0.20, tz - 0.06), (0.16, tz - 0.06), (0.16, tz + 0.06), (-0.20, tz + 0.06)], 0.10,
                  m["legend_flat"], y=-tr + 0.02), 0.01, 2)
    rounded(prism("clu", [(x0, zb + 0.02), (x0 + 0.03, zb), (x1 - 0.05, zb), (x1, zb + 0.05), (x1, zt - 0.03),
                          (x1 - 0.04, zt), (x0 + 0.04, zt), (x0, zt - 0.04)], 0.14, m["legend"], y=cy), 0.025, 3)
    box("cluSeam", (x1 - x0 - 0.02, 0.006, 0.01), ((x0 + x1) / 2, cy - 0.071, tz + 0.06), m["gold"], bevel=0.0)
    for k in range(5):
        box("cluFin", (0.012, 0.006, 0.07), (-0.20 + k * 0.03, cy - 0.072, tz + 0.12), m["legend_flat"],
            bevel=0.0)
    rivets([(x0 + 0.04, zb + 0.04), (x1 - 0.04, zb + 0.04), (x0 + 0.04, zt - 0.04), (x1 - 0.06, zt - 0.04)],
           0.011, m["gold"], cy - 0.072)
    # Objectifs avant (gros : vision nocturne, petit : jour), oculaire arrière caoutchouc.
    cyl_x("nvsHousing", 0.08, 0.08, 0.10, (x1 + 0.04, cy, tz + 0.10), m["legend_flat"], seg=32)
    ring_x("nvsRing", 0.084, 0.02, x1 + 0.08, tz + 0.10, m["gold"], y=cy, seg=32)
    cyl_x("nvsLens", 0.068, 0.068, 0.008, (x1 + 0.092, cy, tz + 0.10), m["glass"], seg=32)
    cyl_x("daySight", 0.035, 0.035, 0.06, (x1 + 0.02, cy, tz - 0.04), m["legend_flat"], seg=24)
    cyl_x("dayLens", 0.028, 0.028, 0.006, (x1 + 0.052, cy, tz - 0.04), m["glass"], seg=24)
    cyl_x("eyepiece", 0.045, 0.045, 0.08, (x0 - 0.04, cy, tz + 0.12), m["legend_flat"], seg=24)
    cyl_x("eyeCup", 0.045, 0.065, 0.08, (x0 - 0.11, cy, tz + 0.12), m["rubber"], seg=24)
    # Commandes : boutons, voyants, interrupteur.
    for k, mat in enumerate(("led_g", "led", "gold")):
        sphere("btn", 0.014, (0.0 + k * 0.05, cy - 0.072, tz - 0.05), m[mat], scale=(1, 0.5, 1), seg=10)
    box("switch", (0.05, 0.02, 0.025), (0.16, cy, zt + 0.01), m["gold"], bevel=0.005)
    # Poignées de type manche (gauche et droite) sous le CLU, détentes dorées.
    for (gx, mat) in ((-0.20, "legend_flat"), (0.16, "legend_flat")):
        rounded(prism("handle", [(gx - 0.05, zb), (gx + 0.05, zb), (gx + 0.03, zb - 0.24), (gx - 0.02, zb - 0.26),
                                 (gx - 0.06, zb - 0.22)], 0.08, m[mat], y=cy), 0.022, 3)
        for k in range(3):
            box("hRib", (0.09, 0.084, 0.006), (gx - 0.008, cy, zb - 0.07 - k * 0.05), m["rubber"], bevel=0.0)
        tube("hTrig", [(gx + 0.05, cy, zb - 0.02), (gx + 0.065, cy, zb - 0.06), (gx + 0.05, cy, zb - 0.09)], 0.011,
             m["gold"], seg=8)
    return {"grip": (-0.20, cy, zb - 0.14), "muzzle": (1.40, 0, tz)}


WEAPONS = {"gl_m79": gl_m79, "gl_china_lake": gl_china_lake, "gl_m32": gl_m32,
           "rocket_rpg7": rocket_rpg7, "rocket_m202": rocket_m202, "rocket_javelin": rocket_javelin}
