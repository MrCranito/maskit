"""Héros du menu principal de RaidersGo : pose « lobby » (idle 3/4, fusil en main), rendue
pour chaque skin depuis le modèle scripté de build_hero.py (même matériaux toon, même contour).

Usage (depuis la racine du projet) :
    python3 art/blender/build_menu_hero.py                      # tous les skins
    python3 art/blender/build_menu_hero.py --skins default,gign # certains skins
    python3 art/blender/build_menu_hero.py --test               # une image de test (scratch)
    python3 art/blender/build_menu_hero.py --bust <out.png> [skin]  # buste (icône d'application)
    python3 art/blender/build_menu_hero.py --hero-shot <out.png> [skin] # pied, contre-plongée (splash)

Sorties : assets/ui/menu/hero/<skin>.png (pose fixe haute résolution FRAME_W x FRAME_H, ≥ 800 px
          de héros : net sur un écran Retina 2532 x 1170 / 2778 x 1284 où il fait ~45 % de la hauteur)
          assets/ui/menu/hero/hero_menu.json (taille du cadre, pieds, hauteur du héros).
L'idle (respiration, balancement) est procédurale, dans le jeu (scripts/ui/menus/lobby_hero.gd) :
fluide à 60 fps, une seule texture par skin.
Caméra orthographique basse (ELEV degrés) : le héros est vu presque de face, légèrement de
3/4 (tourné vers la droite de l'écran, vers le bouton Jouer).
"""
from __future__ import annotations

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import build_hero as H  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "ui", "menu", "hero")
TMP = os.environ.get("RDM_TMP", "/tmp/rdm_menu_hero")

FRAME_W, FRAME_H = 720, 900   # cadre final (px), une pose par skin
N_FRAMES = 8                  # (pose_menu : cycle de référence ; seule l'image 0 est rendue)
SS = 2
OUTLINE = 11.0                # contour à la résolution de rendu (FRAME x SS)
ELEV = 9.0                    # plongée de la caméra (degrés) : presque de face
TURN = 24.0                   # rotation du héros (degrés) vers la droite de l'écran
ORTHO_H = 2.12
TARGET_Z = 0.93


def menu_rifle(hero: H.Hero) -> None:
    """Fusil d'assaut plus détaillé que l'aperçu boutique (même emplacement, mêmes clefs de
    matériau) : tenu en travers du buste, canon vers le bas à gauche (position « prêt »)."""
    sp = hero.j["spine"]
    g = C.empty("menuRifle", (0, 0, 0), sp)
    hero.j_menu_rifle = g
    blk, drk, acc = "helmet_acc", "strap", "pouch"
    parts = [
        (C.bm_box(0.085, 0.42, 0.12, bevel=0.014), (0, 0.02, 0.0), blk),        # boîtier
        (C.bm_box(0.075, 0.30, 0.095, bevel=0.012), (0, -0.33, 0.005), drk),    # garde-main
        (C.bm_cyl(10, 0.022, 0.022, 0.26), (0, -0.60, 0.01), drk),              # canon
        (C.bm_cyl(10, 0.034, 0.030, 0.07), (0, -0.74, 0.01), blk),              # cache-flamme
        (C.bm_box(0.06, 0.075, 0.21, bevel=0.012), (0, -0.07, -0.15), drk),     # chargeur
        (C.bm_box(0.05, 0.06, 0.14, bevel=0.01), (0, 0.13, -0.11), blk),        # poignée
        (C.bm_box(0.07, 0.30, 0.10, bevel=0.016), (0, 0.38, -0.04), blk),       # crosse
        (C.bm_box(0.06, 0.16, 0.055, bevel=0.008), (0, -0.02, 0.10), acc),      # lunette (corps)
        (C.bm_cyl(10, 0.032, 0.032, 0.05), (0, -0.11, 0.105), drk),             # lunette (avant)
        (C.bm_box(0.05, 0.36, 0.025, bevel=0.004), (0, -0.12, 0.068), drk),     # rail
    ]
    for k, (bm, loc, key) in enumerate(parts):
        if k in (2, 3, 8):   # cylindres : axe Z -> axe Y (le long du fusil)
            C.bm_xform(bm, rot=(math.pi / 2, 0, 0))
        hero.part("mrifle", C.bm_xform(bm, loc=loc), key, g, acc="menu_rifle")
    g.rotation_euler = (0.62, 0.0, 0.72)
    g.scale = (0.9, 0.9, 0.9)
    g.location = H.HAND_R + Vector((0.03, -0.05, 0.08))


def setup(res: tuple[int, int], ortho: float, target_z: float, elev: float = ELEV, outline: float = 5.0):
    C.reset_scene()
    C.setup_render(res, samples=4, outline_px=outline)
    hero = H.Hero()
    menu_rifle(hero)
    cam = C.ortho_camera(elev, ortho, target=(0, 0, target_z))
    cam.data.sensor_fit = "VERTICAL"
    return hero, cam


def apply(hero: H.Hero, sid: str) -> None:
    hero.shop = False
    hero.apply_skin(sid)
    for ob in hero.acc.get("menu_rifle", []):
        ob.hide_render = False
        ob.hide_viewport = False


def pose_menu(hero: H.Hero, i: int) -> None:
    """Idle du lobby : respiration, léger balancement, tête qui suit (cycle de N_FRAMES)."""
    hero.pose_idle(i % H.ANIMS["idle"][0])
    j = hero.j
    t = 2 * math.pi * i / N_FRAMES
    j["root"].rotation_euler = (0, 0, math.radians(TURN))
    # pieds un peu écartés, appui sur la jambe arrière
    j["hipL"].rotation_euler = (0.02, -0.16, 0.0)
    j["hipR"].rotation_euler = (-0.03, 0.12, 0.0)
    j["spine"].rotation_euler.z += -0.10
    j["neck"].rotation_euler = (-0.02 + 0.02 * math.sin(t), 0.0, 0.12 + 0.03 * math.sin(t + 1.0))
    # caméra basse : tête moins relevée qu'en jeu (lunettes sur le visage, pas au-dessus)
    j["head"].rotation_euler = (0.10, 0.0, 0.0)


def render(path_big: str, path: str, size: tuple[int, int]) -> None:
    C.render_to(path_big)
    C.downscale(path_big, path, size)


def main() -> None:
    args = sys.argv[1:]
    os.makedirs(TMP, exist_ok=True)
    if "--bust" in args or "--hero-shot" in args:
        bust = "--bust" in args
        k = args.index("--bust" if bust else "--hero-shot")
        out = args[k + 1]
        sid = args[k + 2] if len(args) > k + 2 and not args[k + 2].startswith("--") else "default"
        if bust:
            hero, cam = setup((1024, 1024), 1.55, 1.12, elev=6.0, outline=11.0)
        else:
            hero, cam = setup((1100, 1400), 2.25, 0.98, elev=-4.0, outline=9.0)
        apply(hero, sid)
        pose_menu(hero, 0)
        if bust:
            hero.j["root"].rotation_euler = (0, 0, math.radians(14))
            hero.j["neck"].rotation_euler = (0.02, 0.0, 0.06)
        C.render_to(out)
        print("OUT", out)
        return
    if "--test" in args:
        hero, cam = setup((FRAME_W * SS, FRAME_H * SS), ORTHO_H, TARGET_Z, outline=OUTLINE)
        sid = args[args.index("--test") + 1] if len(args) > args.index("--test") + 1 else "default"
        apply(hero, sid)
        pose_menu(hero, 0)
        p = os.path.join(TMP, "test_%s.png" % sid)
        render(p + ".big.png", p, (FRAME_W, FRAME_H))
        print("TEST", p)
        return
    skins = args[args.index("--skins") + 1].split(",") if "--skins" in args else list(H.SKINS)
    os.makedirs(OUT, exist_ok=True)
    hero, cam = setup((FRAME_W * SS, FRAME_H * SS), ORTHO_H, TARGET_Z, outline=OUTLINE)
    bpy.context.view_layer.update()
    feet = C.world_to_px(cam, (0, 0, 0))
    feet = [round(feet[0] / SS), round(feet[1] / SS)]
    top = C.world_to_px(cam, (0, 0, 1.0))
    unit_px = round((feet[1] - top[1] / SS), 1)
    from PIL import Image
    for sid in skins:
        apply(hero, sid)
        pose_menu(hero, 0)
        p = os.path.join(TMP, "%s_pose.png" % sid)
        render(p + ".big.png", p, (FRAME_W, FRAME_H))
        im = Image.open(p).convert("RGBA")
        im.putalpha(im.getchannel("A").point(lambda v: 0 if v < 4 else v))
        im.save(os.path.join(OUT, "%s.png" % sid), optimize=True)
        print("SKIN", sid, flush=True)
    ref = os.path.join(OUT, "default.png")
    hero_px = 0
    if os.path.exists(ref):
        bb = Image.open(ref).getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
        hero_px = bb[3] - bb[1] if bb else 0
    meta = {
        "hero_px": hero_px,
        "frame_size": [FRAME_W, FRAME_H], "frames": 1,
        "feet": feet, "unit_px": unit_px,
        "notes": "<skin>.png : pose fixe (idle procédurale dans lobby_hero.gd). feet = pieds (px depuis le "
                 "coin haut-gauche du cadre). unit_px = hauteur en px d'une unité Blender du modèle. hero_px = "
                 "hauteur visible du héros (skin par défaut) : elle correspond à une case de la carte.",
    }
    with open(os.path.join(OUT, "hero_menu.json"), "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    main()
