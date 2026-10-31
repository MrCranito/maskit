"""Gadgets HD : grenade à fragmentation (Mk 2 « ananas »), fumigène (M18), mine (bouclier rond),
C4 (pains M112 sanglés et minuterie), drone (quadrirotor), leurre (balise radio).
Rendus par weapons_hd.render_item comme les anciens gadgets : sprite tenu à taille fixe, icône 3/4,
objet vu du dessus 64 × 64 (« _world », deux images pour le drone : hélices décalées).
Repère : Z = haut ; le gadget est centré sur l'origine, grip = (0, 0, 0).
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import weapon_paint as WP  # noqa: E402
from weapons_hd_kit import box, cyl_x, rounded, sphere  # noqa: E402


def cyl_z(name, r1, r2, h, loc, mat, seg=28):
    return C.mesh_obj(name, C.bm_xform(C.bm_cyl(seg, r1, r2, h), loc=loc), mat)


def torus(name, R, r, loc, mat, rot=(0, 0, 0), seg=28):
    return C.mesh_obj(name, C.bm_xform(C.bm_torus(seg, 8, R, r), loc=loc, rot=rot), mat)


def _spoon(m, x, top, bottom, r_body):
    """Cuillère (levier) de grenade le long du corps, côté +X, et goupille à anneau."""
    pts = C.bezier((0.04, 0, top), (0.18, 0, top + 0.03), (r_body + 0.03, 0, top - 0.16), (r_body + 0.01, 0, bottom), 8)
    C.mesh_obj("spoon", C.bm_tube(pts, [0.032] * 8, seg=8, flat=0.35, up=(0, 1, 0)), m["dark"])
    torus("ring", 0.085, 0.012, (-0.13, -0.06, top), m["steel"], rot=(1.2, 0, 0.3))
    C.mesh_obj("pin", C.bm_tube([(-0.06, -0.03, top), (0.04, -0.01, top)], [0.008, 0.008], seg=6), m["steel"])


def gadget_frag(m):
    olive = WP.paint("frag_olive", "#6c7046", "#22261c", "#9aa06c", wear=0.5, grain=0.08, edge="#c8c6a0")
    body = C.bm_sphere(24, 16, 1.0)
    C.bm_xform(body, scale=(0.30, 0.30, 0.36))
    C.mesh_obj("body", body, olive)
    # Quadrillage « ananas » : 6 rainures horizontales et 8 méridiennes en creux sombre.
    for k in range(6):
        z = -0.27 + k * 0.105
        r = 0.30 * math.sqrt(max(0.0, 1 - (z / 0.36) ** 2)) + 0.006
        torus("groove", r, 0.012, (0, 0, z), m["olive_dark"])
    for k in range(8):
        a = k * math.pi / 4
        pts = [(0.304 * math.cos(a) * math.sin(t), 0.304 * math.sin(a) * math.sin(t), 0.364 * math.cos(t))
               for t in (0.45 + 0.28 * i for i in range(9))]
        C.mesh_obj("meridian", C.bm_tube(pts, [0.011] * 9, seg=6), m["olive_dark"])
    cyl_z("neck", 0.095, 0.085, 0.12, (0, 0, 0.40), m["brass"])
    cyl_z("fuze", 0.11, 0.11, 0.07, (0, 0, 0.48), m["dark"])
    _spoon(m, 0.0, 0.50, 0.04, 0.30)
    return {"grip": (0.0, 0, 0.0), "muzzle": (0.32, 0, 0.10)}


def gadget_smoke(m):
    green = WP.paint("smoke_green", "#5a6244", "#1c2018", "#868e64", wear=0.45, grain=0.06)
    yellow = WP.paint("smoke_yellow", "#d8b030", "#5a4020", "#ffe070", wear=0.2)
    cyl_z("body", 0.20, 0.20, 0.70, (0, 0, 0.0), green)
    cyl_z("bandY", 0.204, 0.204, 0.07, (0, 0, 0.22), yellow)
    cyl_z("bandR", 0.204, 0.204, 0.045, (0, 0, -0.27), m["red"])
    # Inscription au pochoir (bandes claires) et évents du dessus.
    for k in range(3):
        box("stencil", (0.10 - k * 0.02, 0.01, 0.022), (0.0, -0.2, 0.08 - k * 0.05), m["cream"], bevel=0.0)
    cyl_z("top", 0.13, 0.18, 0.07, (0, 0, 0.385), m["steel"])
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        cyl_z("vent", 0.02, 0.02, 0.02, (0.09 * math.cos(a), 0.09 * math.sin(a), 0.42), m["bore"], seg=10)
    cyl_z("fuze", 0.08, 0.08, 0.08, (0, 0, 0.46), m["dark"])
    _spoon(m, 0.0, 0.48, -0.10, 0.20)
    return {"grip": (0.0, 0, 0.0), "muzzle": (0.24, 0, 0.10)}


def gadget_mine(m):
    cyl_z("body", 0.40, 0.43, 0.20, (0, 0, 0.0), m["olive"], seg=36)
    cyl_z("rim", 0.44, 0.44, 0.03, (0, 0, -0.09), m["olive_dark"], seg=36)
    cyl_z("lid", 0.33, 0.38, 0.06, (0, 0, 0.13), m["bronze"], seg=36)
    for k in range(16):
        a = k * math.pi / 8
        box("rib", (0.22, 0.022, 0.022), (0.22 * math.cos(a), 0.22 * math.sin(a), 0.165), m["dark"],
            rot=(0, 0, a), bevel=0.004)
    cyl_z("fuze", 0.08, 0.10, 0.08, (0, 0, 0.20), m["dark"])
    cyl_z("prong", 0.022, 0.03, 0.08, (0, 0, 0.27), m["steel"], seg=12)
    sphere("ledM", 0.022, (0.16, -0.16, 0.20), m["led"], seg=8)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        sphere("bolt", 0.02, (0.405 * math.cos(a), 0.405 * math.sin(a), 0.03), m["steel"], seg=8)
    C.mesh_obj("handle", C.bm_tube(C.bezier((0.30, 0, 0.11), (0.44, 0, 0.30), (0.18, 0, 0.38), (0.10, 0, 0.25), 8),
                                   [0.022] * 8, seg=8), m["dark"])
    return {"grip": (0.0, 0, 0.0), "muzzle": (0.42, 0, 0.0)}


def gadget_c4(m):
    putty = WP.paint("c4_wrap", "#5e6448", "#1e2218", "#8a9068", grain=0.1, wear=0.3)
    for k, y in enumerate((-0.11, 0.11)):
        rounded(box("block", (0.80, 0.21, 0.28), (0, y, 0.0), putty, bevel=0.0), 0.03, 3)
    box("label", (0.40, 0.01, 0.13), (0.0, -0.217, 0.0), m["cream"], bevel=0.0)
    for k in range(3):
        box("labelTxt", (0.30 - k * 0.06, 0.012, 0.016), (-0.02, -0.219, 0.04 - k * 0.035), m["dark"], bevel=0.0)
    for x in (-0.28, 0.28):
        box("strap", (0.07, 0.45, 0.31), (x, 0, 0.0), m["legend_flat"], bevel=0.008)
        box("buckle", (0.09, 0.02, 0.07), (x, -0.228, 0.05), m["steel"], bevel=0.006)
    rounded(box("timer", (0.30, 0.22, 0.09), (0.0, 0.0, 0.19), m["dark"], bevel=0.0), 0.015, 2)
    box("screen", (0.18, 0.11, 0.012), (-0.02, -0.02, 0.236), m["led"], bevel=0.0)
    for k in range(3):
        box("key", (0.03, 0.03, 0.012), (0.10, -0.06 + k * 0.045, 0.236), m["steel"], bevel=0.004)
    sphere("antenna", 0.018, (0.14, 0.08, 0.30), m["led_g"], seg=8)
    C.mesh_obj("ant", C.bm_tube([(0.14, 0.08, 0.23), (0.14, 0.08, 0.30)], [0.008, 0.008], seg=6), m["dark"])
    for k, (x, col) in enumerate(((-0.30, "red"), (0.30, "led_b"))):
        box("cap", (0.06, 0.06, 0.08), (x, 0.10, 0.19), m["red"] if col == "red" else m["dark"], bevel=0.008)
    C.mesh_obj("wire", C.bm_tube(C.bezier((0.12, 0.05, 0.20), (0.20, -0.10, 0.30), (0.28, -0.05, 0.28),
                                          (0.30, 0.10, 0.23), 8), [0.013] * 8, seg=6), m["red"])
    C.mesh_obj("wire2", C.bm_tube(C.bezier((-0.12, 0.05, 0.20), (-0.20, -0.10, 0.30), (-0.28, -0.05, 0.28),
                                           (-0.30, 0.10, 0.23), 8), [0.013] * 8, seg=6), m["gold"])
    return {"grip": (0.0, 0, 0.0), "muzzle": (0.40, 0, 0.0)}


def gadget_drone(m, rotor_phase: float = 0.0):
    shell_m = WP.paint("drone_shell", "#2a3c70", "#0a1028", "#6a8ad0", gloss=0.5, wear=0.2, grain=0.03)
    blade_m = WP.paint("drone_blade", "#c8ccd8", "#5a5e78", "#ffffff", gloss=0.3, ao=0.0, grain=0.0)
    shell = C.bm_sphere(28, 16, 1.0)
    C.bm_xform(shell, scale=(0.28, 0.24, 0.12))
    C.mesh_obj("shell", shell, shell_m)
    rounded(box("bottom", (0.38, 0.30, 0.07), (0, 0, -0.08), m["legend_flat"], bevel=0.0), 0.02, 2)
    box("battery", (0.20, 0.14, 0.04), (-0.06, 0, 0.11), m["dark"], bevel=0.008)
    cyl_x("gimbal", 0.06, 0.06, 0.06, (0.24, 0, -0.11), m["dark"])
    cyl_x("cam", 0.05, 0.05, 0.08, (0.29, 0, -0.11), m["legend_flat"])
    cyl_x("camLens", 0.036, 0.036, 0.01, (0.335, 0, -0.11), m["glass"])
    sphere("ledF", 0.025, (0.22, 0, 0.08), m["led_b"], seg=8)
    sphere("ledB", 0.02, (-0.24, 0, 0.06), m["led"], seg=8)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        x, y = 0.55 * math.cos(a), 0.55 * math.sin(a)
        C.mesh_obj("arm", C.bm_tube([(0.12 * math.cos(a), 0.12 * math.sin(a), 0.0), (x, y, 0.02)], [0.034, 0.026],
                                    seg=8), m["legend_flat"])
        cyl_z("motor", 0.05, 0.05, 0.09, (x, y, 0.05), m["dark"], seg=20)
        cyl_z("motorCap", 0.03, 0.03, 0.03, (x, y, 0.105), m["steel"], seg=16)
        torus("guard", 0.25, 0.013, (x, y, 0.06), m["steel"], seg=40)
        for b in range(2):
            ang = rotor_phase + a * 1.7 + b * math.pi
            box("blade", (0.22, 0.045, 0.008), (x + 0.11 * math.cos(ang), y + 0.11 * math.sin(ang), 0.115), blade_m,
                rot=(0, 0.12, ang), bevel=0.0)
    for sx in (-1, 1):
        C.mesh_obj("skid", C.bm_tube([(0.15, 0.12 * sx, -0.10), (0.15, 0.16 * sx, -0.22), (-0.15, 0.16 * sx, -0.22),
                                      (-0.15, 0.12 * sx, -0.10)], [0.013] * 4, seg=6), m["dark"])
    return {"grip": (-0.10, 0, -0.10), "muzzle": (0.30, 0, -0.10)}


def gadget_decoy(m):
    """Leurre : balise radio (boîtier, haut-parleur, antenne, LED) qui attire les ennemis."""
    case_m = WP.paint("decoy_case", "#8a5a34", "#2e1a16", "#c08a58", wear=0.4, grain=0.06)
    rounded(box("case", (0.46, 0.22, 0.34), (0, 0, 0.0), case_m, bevel=0.0), 0.04, 3)
    cyl_x("speakerRim", 0.12, 0.12, 0.012, (0, 0, 0), m["dark"])
    C.mesh_obj("speaker", C.bm_xform(C.bm_cyl(28, 0.11, 0.11, 0.02), loc=(-0.06, -0.112, 0.0),
                                     rot=(math.pi / 2, 0, 0)), m["dark"])
    for k in range(4):
        torus("cone", 0.03 + k * 0.022, 0.006, (-0.06, -0.124, 0.0), m["steel"], rot=(math.pi / 2, 0, 0), seg=24)
    box("dial", (0.06, 0.02, 0.06), (0.14, -0.115, 0.08), m["steel"], bevel=0.008)
    box("dial2", (0.06, 0.02, 0.06), (0.14, -0.115, -0.04), m["steel"], bevel=0.008)
    sphere("led", 0.022, (0.14, -0.11, 0.14), m["led"], seg=8)
    C.mesh_obj("antenna", C.bm_tube([(0.16, 0.0, 0.17), (0.18, 0.0, 0.48)], [0.012, 0.007], seg=6), m["dark"])
    sphere("antTip", 0.02, (0.18, 0.0, 0.49), m["led"], seg=8)
    C.mesh_obj("handle", C.bm_tube(C.bezier((-0.16, 0, 0.17), (-0.14, 0, 0.27), (0.04, 0, 0.27), (0.06, 0, 0.17), 8),
                                   [0.02] * 8, seg=8), m["dark"])
    return {"grip": (0.0, 0, 0.0), "muzzle": (0.25, 0, 0.0)}


WEAPONS = {"gadget_frag": gadget_frag, "gadget_smoke": gadget_smoke, "gadget_mine": gadget_mine,
           "gadget_c4": gadget_c4, "gadget_drone": gadget_drone, "gadget_decoy": gadget_decoy}
