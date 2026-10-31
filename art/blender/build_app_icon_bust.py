"""Buste du héros pour l'icône d'application (art/icon/build_app_icon.py l'appelle).

Même modèle scripté et même pipeline toon (matériaux, contour) que les menus (build_menu_hero.py),
cadré serré sur le buste, fusil d'assaut du menu tenu en travers de la poitrine.

    blender -b -P <lanceur> -- art/blender/build_app_icon_bust.py <out.png> [skin]

Sortie : PNG RGBA 1024 x 1024 (fond transparent).
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import build_menu_hero as M  # noqa: E402

RES = 1024
ORTHO = 1.18        # hauteur visible (unités Blender) : tête + épaules + fusil
TARGET_Z = 1.24     # centre du cadre (au niveau du menton)
ELEV = 4.0          # caméra presque de face
TURN = 18.0         # 3/4 léger vers la droite
OUTLINE = 13.0      # contour épais : lisible une fois réduit à 48 px


def main() -> None:
    # sous Blender (--python), les arguments du script suivent « -- » ; via un lanceur, sys.argv est déjà nettoyé
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    out = os.path.abspath(args[0])
    sid = args[1] if len(args) > 1 else "default"
    hero, cam = M.setup((RES, RES), ORTHO, TARGET_Z, elev=ELEV, outline=OUTLINE)
    M.apply(hero, sid, rifle=True)
    M.pose_menu(hero, 0)
    hero.j["root"].rotation_euler = (0, 0, math.radians(TURN))
    hero.j["neck"].rotation_euler = (0.02, 0.0, 0.05)
    hero.j["head"].rotation_euler = (0.06, 0.0, 0.0)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    C.render_to(out)
    print("OUT", out)


if __name__ == "__main__":
    main()
