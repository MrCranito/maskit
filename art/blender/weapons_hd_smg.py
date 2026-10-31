"""Armes HD : mitraillettes MP5 (Commun), KRISS Vector (Rare), Uzi (Légendaire).

Repère : X = canon vers la droite, Z = haut, côté visible = -Y. Dimensions proches de build_weapons.py.
Références de silhouette (profil gauche) :
- HK MP5A3 : boîtier tubulaire embouti, tube d'armement prolongé jusqu'au guidon encapuchonné, levier
  d'armement à 45° en haut à gauche au-dessus du garde-main fin, tambour dioptrique à l'arrière, chargeur
  acier légèrement courbe, carcasse polymère (poignée + pontet), crosse rétractable à deux bras.
- KRISS Vector : haut plat à rail pleine longueur, gros boîtier inférieur anguleux dont l'avant descend en
  biais jusqu'au puits de chargeur (placé devant le pontet), chargeur droit type Glock, poignée AR,
  grand pontet, crosse squelette repliable, hausse et guidon rabattables.
- IMI Uzi : boîtier rectangulaire en tôle à rainures embouties, couvercle avec bouton d'armement sur le
  dessus, guidon et hausse à oreilles, écrou de canon moleté, chargeur dans la poignée (sûreté de
  poignée à l'arrière, sélecteur en haut), crosse métallique repliée sous le boîtier.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import build_weapons as BW  # noqa: E402
from weapons_hd_kit import (box, cyl_x, cyl_y, grooves, prism, rail, rivets, rounded,  # noqa: E402
                            sphere, tube)


def _curved_mag(name, top, bot, w, t, mat, bend=0.06, n=10):
    """Chargeur : loft de sections (x avant/arrière) le long d'une courbe de Bézier (haut -> bas)."""
    (x0, z0), (x1, z1) = top, bot
    pts = C.bezier((x0, 0, z0), (x0, 0, z0 + (z1 - z0) * 0.4), (x1 - bend, 0, z0 + (z1 - z0) * 0.75),
                   (x1, 0, z1), n)
    secs = [[(x, -t / 2, z), (x + w, -t / 2, z), (x + w, t / 2, z), (x, t / 2, z)] for (x, _y, z) in pts]
    return C.mesh_obj(name, C.bm_loft(secs), mat, smooth=False), pts


# --------------------------------------------------------------------------- HK MP5A3 (Commun)

def smg_mp5(m):
    bz = 0.20                      # axe du canon
    # Boîtier : tube embouti (dessus arrondi) + flancs plats, bourrelet de soudure, cannelure latérale.
    cyl_x("rcvTop", 0.078, 0.078, 0.86, (0.17, 0, 0.235), m["blued"], seg=28)
    rounded(box("rcvLow", (0.86, 0.13, 0.12), (0.17, 0, 0.175), m["blued"], bevel=0.008), 0.006, 2)
    box("rcvFlute", (0.62, 0.136, 0.016), (0.20, 0, 0.165), m["dark"], bevel=0.0)
    box("rcvSeam", (0.86, 0.134, 0.008), (0.17, 0, 0.118), m["steel"], bevel=0.0)
    # Tube d'armement prolongé jusqu'au guidon, fente et levier d'armement à 45° (côté visible).
    cyl_x("cockTube", 0.05, 0.05, 0.48, (0.84, 0, 0.255), m["blued"], seg=24)
    cyl_x("cockCollar", 0.064, 0.056, 0.05, (0.61, 0, 0.25), m["blued"], seg=24)
    box("cockSlot", (0.30, 0.012, 0.018), (0.86, -0.048, 0.262), m["bore"], bevel=0.0)
    box("cockNotch", (0.02, 0.012, 0.04), (0.715, -0.048, 0.275), m["bore"], bevel=0.0)
    tube("cockLever", [(0.80, -0.05, 0.27), (0.83, -0.075, 0.31), (0.86, -0.085, 0.35)], 0.014, m["steel"], seg=8)
    sphere("cockKnob", 0.026, (0.87, -0.086, 0.36), m["dark"], scale=(1.4, 0.9, 1.0), seg=12)
    # Guidon : bloc sur canon + capuchon annulaire ; canon fileté à 3 tenons.
    rounded(box("fsBlock", (0.09, 0.10, 0.16), (1.03, 0, 0.245), m["blued"]), 0.01, 2)
    cyl_x("fsHood", 0.052, 0.052, 0.05, (1.035, 0, 0.36), m["blued"], seg=24)
    cyl_x("fsHoodIn", 0.036, 0.036, 0.052, (1.035, 0, 0.36), m["bore"], seg=20)
    box("fsPost", (0.012, 0.012, 0.05), (1.035, 0, 0.34), m["dark"], bevel=0.0)
    box("fsStem", (0.05, 0.06, 0.05), (1.035, 0, 0.31), m["blued"], bevel=0.004)
    cyl_x("barrel", 0.03, 0.03, 0.66, (0.90, 0, bz), m["steel"])
    cyl_x("lugRing", 0.042, 0.042, 0.045, (1.10, 0, bz), m["blued"], seg=20)
    for dz in (0.034, -0.034):
        box("lug", (0.035, 0.03, 0.02), (1.10, 0, bz + dz), m["blued"], bevel=0.003)
    cyl_x("thread", 0.026, 0.026, 0.10, (1.175, 0, bz), m["steel"])
    grooves(1.135, 6, 0.016, (0.006, 0.056, 0.056), bz, m["dark"])
    cyl_x("crown", 0.03, 0.028, 0.03, (1.235, 0, bz), m["steel"])
    cyl_x("muzzleBore", 0.015, 0.015, 0.01, (1.25, 0, bz), m["bore"])
    # Garde-main fin (slimline) effilé vers l'avant, quadrillé, goupille.
    rounded(prism("handguard", [(0.60, 0.215), (0.98, 0.215), (0.98, 0.15), (0.95, 0.11), (0.66, 0.085),
                                (0.60, 0.10)], 0.13, m["polymer"]), 0.025, 3)
    prism("hgTex", [(0.66, 0.19), (0.93, 0.19), (0.93, 0.13), (0.68, 0.11)], 0.134, m["polymer_tex"])
    cyl_y("hgPin", 0.012, 0.14, (0.63, 0, 0.17), m["steel"])
    # Tambour dioptrique arrière et rail à griffes.
    rounded(box("rsBase", (0.12, 0.08, 0.05), (-0.17, 0, 0.32), m["blued"]), 0.006, 2)
    cyl_y("rsDrum", 0.05, 0.09, (-0.17, 0, 0.37), m["blued"], seg=24)
    cyl_y("rsHub", 0.02, 0.095, (-0.17, 0, 0.37), m["steel"], seg=12)
    for dx, dz in ((0.0, 0.05), (0.05, 0.0), (0.0, -0.05), (-0.05, 0.0)):
        sphere("rsHole", 0.009, (-0.17 + dx * 0.78, -0.047, 0.37 + dz * 0.78), m["bore"], seg=8)
    for xx in (0.0, 0.30):
        box("claw", (0.06, 0.05, 0.03), (xx, 0, 0.318), m["dark"], bevel=0.005)
    # Puits de chargeur, bouton et levier de chargeur, chargeur acier courbe à nervures.
    rounded(box("magwell", (0.20, 0.135, 0.07), (0.425, 0, 0.09), m["blued"]), 0.008, 2)
    box("magPaddle", (0.05, 0.10, 0.025), (0.30, 0, 0.05), m["dark"], bevel=0.004)
    cyl_y("magBtn", 0.02, 0.145, (0.335, 0, 0.09), m["dark"])
    mag, pts = _curved_mag("mag", (0.34, 0.07), (0.50, -0.43), 0.15, 0.09, m["blued"], bend=0.09)
    rounded(mag, 0.012, 2)
    for k in (2, 4, 6, 8):
        x, _y, z = pts[k]
        box("magRib", (0.11, 0.096, 0.012), (x + 0.075, 0, z), m["steel"], bevel=0.003)
    xb, _y, zb = pts[-1]
    rounded(box("magBase", (0.17, 0.10, 0.03), (xb + 0.075, 0, zb - 0.01), m["dark"]), 0.006, 2)
    rivets([(pts[3][0] + 0.03, pts[3][2] - 0.04)], 0.01, m["steel"], -0.046)
    # Carcasse polymère : boîtier de détente, pontet moulé, poignée ergonomique, sélecteur SEF.
    rounded(prism("lower", [(-0.24, 0.115), (0.32, 0.115), (0.32, 0.05), (0.18, 0.03), (-0.02, 0.03),
                            (-0.20, 0.06), (-0.24, 0.09)], 0.12, m["polymer"]), 0.015, 2)
    tube("guard", [(0.30, 0, 0.05), (0.29, 0, -0.05), (0.21, 0, -0.08), (0.10, 0, -0.07), (0.07, 0, -0.03)],
         0.02, m["polymer"], seg=10)
    tube("trigger", [(0.17, 0, 0.05), (0.185, 0, 0.0), (0.17, 0, -0.04)], 0.013, m["dark"])
    rounded(prism("grip", [(0.10, 0.04), (-0.04, 0.04), (-0.13, -0.33), (-0.06, -0.37), (0.02, -0.33),
                           (0.03, -0.12), (0.08, -0.06)], 0.13, m["polymer"]), 0.03, 3)
    grooves(-0.10, 4, 0.055, (0.012, 0.136, 0.022), -0.08, m["polymer_tex"], rot=(0, 0.22, 0))
    rounded(box("selector", (0.09, 0.012, 0.02), (-0.08, -0.068, 0.085), m["steel"], rot=(0, 0.45, 0),
                bevel=0.004), 0.004, 2)
    cyl_y("selHub", 0.022, 0.13, (-0.11, 0, 0.07), m["dark"])
    for k, (dx, dz) in enumerate(((-0.05, 0.10), (-0.065, 0.065), (-0.06, 0.03))):
        sphere("selMark", 0.007, (-0.11 + dx + 0.04, -0.064, dz + 0.0), m["white"], seg=8)
    for xx in (-0.19, 0.26):
        cyl_y("pushPin", 0.015, 0.14, (xx, 0, 0.085), m["steel"])
    # Embout arrière, crosse rétractable à deux bras, plaque de couche caoutchouc.
    rounded(box("endCap", (0.07, 0.14, 0.20), (-0.29, 0, 0.21), m["polymer"]), 0.015, 2)
    cyl_y("capPin", 0.014, 0.15, (-0.29, 0, 0.17), m["steel"])
    for zz in (0.27, 0.14):
        cyl_x("strut", 0.018, 0.018, 0.46, (-0.55, -0.045, zz), m["steel"], seg=12)
        cyl_x("strutB", 0.018, 0.018, 0.46, (-0.55, 0.045, zz), m["steel"], seg=12)
    box("strutLatch", (0.06, 0.11, 0.03), (-0.36, 0, 0.27), m["dark"], bevel=0.005)
    rounded(prism("buttFrame", [(-0.74, 0.31), (-0.80, 0.31), (-0.82, -0.02), (-0.76, -0.02), (-0.74, 0.10)],
                  0.13, m["dark"]), 0.012, 2)
    rounded(box("buttPad", (0.04, 0.14, 0.35), (-0.835, 0, 0.145), m["rubber"]), 0.012, 2)
    grooves(-0.835, 1, 0.0, (0.046, 0.146, 0.01), 0.24, m["bore"])
    grooves(-0.835, 1, 0.0, (0.046, 0.146, 0.01), 0.05, m["bore"])
    return {"grip": (-0.04, 0, -0.14), "muzzle": (1.25, 0, bz)}


# --------------------------------------------------------------------------- KRISS Vector (Rare)

def smg_vector(m):
    bz = 0.17
    # Boîtier supérieur plat, rail pleine longueur, fenêtre, hausse et guidon rabattables.
    rounded(box("upper", (1.04, 0.15, 0.15), (0.30, 0, 0.305), m["gunmetal"]), 0.02, 3)
    box("upperSeam", (1.04, 0.154, 0.008), (0.30, 0, 0.232), m["dark"], bevel=0.0)
    rail(m, -0.20, 0.80, 0.393, 0.09, mat="dark")
    rounded(prism("rsFold", [(-0.18, 0.41), (-0.06, 0.41), (-0.07, 0.47), (-0.16, 0.50), (-0.18, 0.47)], 0.07,
                  m["dark"]), 0.01, 2)
    cyl_y("rsAperture", 0.016, 0.075, (-0.13, 0, 0.465), m["bore"], seg=12)
    rounded(prism("fsFold", [(0.70, 0.41), (0.79, 0.41), (0.79, 0.44), (0.76, 0.51), (0.72, 0.51)], 0.07,
                  m["dark"]), 0.01, 2)
    box("fsPost", (0.012, 0.012, 0.05), (0.74, 0, 0.53), m["dark"], bevel=0.0)
    # Gros boîtier inférieur anguleux (logement Super V) : nez carré, face avant en biais jusqu'au puits de
    # chargeur placé devant le pontet.
    low = rounded(prism("lower", [(-0.22, 0.235), (0.86, 0.235), (0.86, 0.09), (0.78, 0.07), (0.52, -0.22),
                                  (0.26, -0.22), (0.24, -0.04), (0.08, 0.05), (-0.22, 0.10)], 0.16,
                         m["gunmetal"]), 0.02, 3)
    low.name = "lower"
    # Panneau en creux qui suit le biais, filets bronze parallèles à la face avant.
    rounded(prism("panel", [(0.30, 0.20), (0.74, 0.20), (0.74, 0.12), (0.50, -0.15), (0.30, -0.15)], 0.166,
                  m["dark"]), 0.01, 2)
    for k in range(2):
        d = 0.035 * k
        tube("bevelLine", [(0.70 - d, -0.084, 0.11), (0.47 - d, -0.084, -0.13)], 0.007, m["bronze"], seg=6)
    box("seamLow", (0.30, 0.17, 0.008), (0.38, 0, -0.15), m["bronze"], bevel=0.0)
    box("chHandle", (0.20, 0.014, 0.022), (0.66, -0.083, 0.215), m["bore"], bevel=0.0)
    rounded(box("chKnob", (0.05, 0.05, 0.045), (0.73, -0.10, 0.215), m["bronze"]), 0.01, 2)
    rivets([(-0.16, 0.16), (0.12, 0.16), (0.36, 0.06), (0.80, 0.16)], 0.016, m["steel"], -0.08)
    # Rail inférieur court sous l'avant.
    box("railLow", (0.10, 0.08, 0.03), (0.81, 0, 0.07), m["dark"], bevel=0.004)
    for k in range(2):
        box("railLowT", (0.026, 0.084, 0.02), (0.785 + k * 0.05, 0, 0.048), m["dark"], bevel=0.003)
    # Canon court, cache-flamme à fentes.
    cyl_x("barrel", 0.032, 0.032, 0.20, (0.95, 0, bz), m["steel"])
    cyl_x("brakeBody", 0.046, 0.046, 0.14, (1.10, 0, bz), m["dark"], seg=24)
    for k in range(3):
        box("brakeSlot", (0.024, 0.02, 0.06), (1.07 + k * 0.035, -0.04, bz + 0.0), m["bore"], bevel=0.0)
    cyl_x("muzzleBore", 0.02, 0.02, 0.01, (1.172, 0, bz), m["bore"])
    # Chargeur droit type Glock, talon à semelle.
    rounded(prism("magwellLip", [(0.23, -0.18), (0.51, -0.18), (0.51, -0.23), (0.23, -0.23)], 0.17,
                  m["gunmetal"]), 0.012, 2)
    rounded(prism("mag", [(0.27, -0.22), (0.46, -0.22), (0.47, -0.66), (0.28, -0.66)], 0.10, m["polymer"]),
            0.015, 2)
    rounded(box("magBase", (0.22, 0.12, 0.045), (0.375, 0, -0.68), m["dark"]), 0.012, 2)
    for k in range(3):
        sphere("magHole", 0.012, (0.30, -0.051, -0.32 - k * 0.1), m["white"], seg=8)
    # Grand pontet, détente, sélecteur, poignée AR texturée.
    tube("guard", [(0.23, 0, -0.04), (0.23, 0, -0.14), (0.04, 0, -0.14), (0.0, 0, -0.08)], 0.022,
         m["gunmetal"], seg=10)
    tube("trigger", [(0.13, 0, 0.06), (0.145, 0, 0.0), (0.13, 0, -0.05)], 0.013, m["dark"])
    rounded(BW.grip("grip", 0.06, 0.08, m["polymer"], h=0.40, w=0.15, t=0.13, slant=0.25), 0.03, 3)
    prism("gripTex", [(0.03, 0.0), (-0.07, 0.0), (-0.15, -0.30), (-0.05, -0.30)], 0.136, m["polymer_tex"])
    rounded(box("selector", (0.08, 0.012, 0.024), (-0.07, -0.088, 0.17), m["bronze"], rot=(0, 0.3, 0)),
            0.004, 2)
    cyl_y("selHub", 0.02, 0.17, (-0.10, 0, 0.16), m["dark"])
    # Adaptateur et crosse squelette repliable.
    rounded(box("hinge", (0.06, 0.13, 0.18), (-0.25, 0, 0.27), m["dark"]), 0.012, 2)
    cyl_y("hingePin", 0.02, 0.15, (-0.25, 0, 0.21), m["steel"])
    cyl_x("bufTube", 0.05, 0.05, 0.24, (-0.40, 0, 0.30), m["dark"], seg=20)
    # Crosse squelette : barre haute, barre oblique, plaque de couche.
    for path in ([(-0.46, 0, 0.33), (-0.79, 0, 0.35)], [(-0.48, 0, 0.27), (-0.62, 0, 0.13), (-0.79, 0, -0.02)],
                 [(-0.50, 0, 0.33), (-0.50, 0, 0.26)]):
        C.mesh_obj("stockBar", C.bm_tube(path, [0.032] * len(path), seg=8, flat=1.6, up=(0, 1, 0)), m["polymer"])
    rounded(box("stockPlate", (0.06, 0.11, 0.42), (-0.77, 0, 0.17), m["polymer"]), 0.02, 2)
    rounded(box("buttPad", (0.04, 0.12, 0.46), (-0.815, 0, 0.16), m["rubber"]), 0.012, 2)
    return {"grip": (-0.06, 0, -0.14), "muzzle": (1.175, 0, bz)}


# --------------------------------------------------------------------------- IMI Uzi (Légendaire)

def smg_uzi(m):
    bz = 0.19
    # Boîtier rectangulaire en tôle, rainures embouties, couvercle supérieur, filets dorés.
    rounded(box("receiver", (0.82, 0.15, 0.22), (0.15, 0, 0.19), m["legend_flat"]), 0.014, 2)
    for zz in (0.235, 0.165):
        box("press", (0.66, 0.156, 0.026), (0.12, 0, zz), m["legend_flat"], bevel=0.006)
        box("pressSh", (0.66, 0.157, 0.006), (0.12, 0, zz - 0.016), m["bore"], bevel=0.0)
    box("goldLine", (0.82, 0.158, 0.01), (0.15, 0, 0.088), m["gold"], bevel=0.0)
    rounded(prism("cover", [(-0.27, 0.30), (0.57, 0.30), (0.57, 0.325), (0.54, 0.34), (-0.24, 0.34),
                            (-0.27, 0.325)], 0.14, m["legend"]), 0.008, 2)
    box("coverSlot", (0.36, 0.03, 0.012), (0.24, 0, 0.343), m["bore"], bevel=0.0)
    rounded(box("cockKnob", (0.06, 0.06, 0.05), (0.36, 0, 0.36), m["gold"]), 0.012, 2)
    grooves(0.34, 4, 0.013, (0.005, 0.064, 0.054), 0.36, m["bore"])
    rounded(box("latch", (0.05, 0.11, 0.04), (-0.27, 0, 0.30), m["gold"]), 0.008, 2)
    # Hausse et guidon à oreilles de protection.
    for xx, h in ((-0.18, 0.06), (0.48, 0.075)):
        box("sightBase", (0.07, 0.11, 0.02), (xx, 0, 0.35), m["legend_flat"], bevel=0.004)
        for yy in (-0.042, 0.042):
            box("ear", (0.05, 0.016, h), (xx, yy, 0.36 + h / 2), m["legend_flat"], bevel=0.004)
        box("post", (0.014, 0.014, h * 0.8), (xx, 0, 0.36 + h * 0.4), m["gold"], bevel=0.0)
    # Écrou de canon moleté doré, canon court.
    cyl_x("nut", 0.075, 0.075, 0.07, (0.60, 0, bz), m["gold"], seg=28)
    grooves(0.572, 8, 0.008, (0.003, 0.156, 0.15), bz, m["legend_flat"])
    cyl_x("barrel", 0.034, 0.034, 0.16, (0.71, 0, bz), m["legend_flat"])
    cyl_x("crown", 0.04, 0.036, 0.03, (0.785, 0, bz), m["gold"])
    cyl_x("muzzleBore", 0.018, 0.018, 0.01, (0.80, 0, bz), m["bore"])
    # Poignée (chargeur dedans) : panneaux texturés, sûreté de poignée, sélecteur, bouton de chargeur.
    gx, gz, gh, sl = 0.20, 0.08, 0.40, 0.10
    rounded(BW.grip("grip", gx, gz, m["legend"], h=gh, w=0.18, t=0.14, slant=sl), 0.025, 3)
    prism("panel", [(gx - 0.03, gz - 0.06), (gx - 0.15, gz - 0.06), (gx - 0.15 - 0.28 * sl, gz - 0.34),
                    (gx - 0.03 - 0.28 * sl, gz - 0.34)], 0.146, m["polymer_tex"])
    cyl_y("panelScrew", 0.016, 0.15, (gx - 0.09 - 0.12 * sl, 0, gz - 0.18), m["gold"])
    rounded(prism("gripSafety", [(gx - 0.18, gz - 0.02), (gx - 0.20, gz - 0.02), (gx - 0.23, gz - 0.22),
                                 (gx - 0.21, gz - 0.22)], 0.10, m["gold"]), 0.006, 2)
    rounded(box("selector", (0.07, 0.012, 0.024), (gx - 0.13, -0.08, gz + 0.03), m["gold"], rot=(0, -0.4, 0)),
            0.004, 2)
    cyl_y("selHub", 0.018, 0.158, (gx - 0.10, 0, gz + 0.02), m["legend_flat"])
    sphere("selDot", 0.008, (gx - 0.17, -0.078, gz + 0.06), m["white"], seg=8)
    box("magBtn", (0.04, 0.012, 0.05), (gx - 0.06 - 0.36 * sl, -0.074, gz - 0.36), m["gold"], bevel=0.004)
    # Chargeur droit qui dépasse sous la poignée, talon doré.
    mx = gx - 0.16 - gh * sl
    rounded(prism("mag", [(mx, gz - gh + 0.02), (mx + 0.13, gz - gh + 0.02), (mx + 0.13 - 0.02, gz - gh - 0.17),
                          (mx - 0.02, gz - gh - 0.17)], 0.09, m["legend_flat"]), 0.01, 2)
    rounded(box("magBase", (0.17, 0.11, 0.035), (mx + 0.055, 0, gz - gh - 0.185), m["gold"]), 0.008, 2)
    # Grand pontet, détente dorée.
    tube("guard", [(gx + 0.0, 0, gz - 0.02), (gx + 0.01, 0, gz - 0.13), (gx + 0.12, 0, gz - 0.16),
                   (gx + 0.19, 0, gz - 0.12), (gx + 0.21, 0, gz + 0.01)], 0.02, m["legend_flat"], seg=10)
    tube("trigger", [(gx + 0.08, 0, gz), (gx + 0.095, 0, gz - 0.05), (gx + 0.08, 0, gz - 0.09)], 0.013,
         m["gold"])
    # Crosse métallique repliée sous le boîtier : bras latéral, charnière, plaque de couche à l'avant.
    cyl_y("hinge", 0.032, 0.19, (-0.24, 0, 0.09), m["gold"])
    tube("strut", [(-0.24, -0.088, 0.09), (0.10, -0.088, 0.07), (0.48, -0.088, 0.05)], 0.018, m["gold"],
         seg=8)
    tube("strutB", [(-0.24, 0.088, 0.09), (0.48, 0.088, 0.05)], 0.02, m["legend_flat"], seg=8)
    rounded(prism("buttPlate", [(0.46, 0.09), (0.56, 0.09), (0.57, -0.08), (0.52, -0.11), (0.47, -0.09)], 0.17,
                  m["legend_flat"]), 0.015, 2)
    box("buttTrim", (0.012, 0.176, 0.17), (0.565, 0, 0.0), m["gold"], rot=(0, 0.04, 0), bevel=0.0)
    rivets([(-0.20, 0.20), (0.40, 0.20), (0.40, 0.12), (-0.20, 0.12)], 0.012, m["gold"], -0.077)
    return {"grip": (0.08, 0, -0.14), "muzzle": (0.80, 0, bz)}


WEAPONS = {"smg_mp5": smg_mp5, "smg_vector": smg_vector, "smg_uzi": smg_uzi}
