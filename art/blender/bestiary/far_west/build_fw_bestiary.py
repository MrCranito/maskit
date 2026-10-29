"""Bestiaire Far West (refonte) : modèles Blender scriptés -> planches 8 directions.

Usage (depuis la racine du projet, rendus sous verrou : 2 cœurs pour 3 agents) :
    flock /home/claude/.blender_render.lock python3 art/blender/bestiary/far_west/build_fw_bestiary.py
    ... --kinds fw_bandit,fw_raider            # quelques kinds
    ... --preview s,se --anim idle:0,attack:3  # bande d'aperçu (RDM_TMP)
    ... --board docs/bestiaire/captures/far_west/modeles.png   # planche de présentation

Kinds (planches docs/reference/bestiaire_classique.png et bestiaire_elites_boss.png) :
    classiques : fw_bandit, fw_raider (Pillard), fw_sharpshooter (Tireur d'élite),
                 fw_marauder (Maraudeur, hyène), fw_bruiser (Robuste), fw_guard_dog (Chien de garde)
    élites     : fw_deserter (Le Déserteur), fw_buffalo (Le Buffle)
    boss       : fw_sheriff (Le Shérif Sable-Fou)
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fw_sheet as S  # noqa: E402
import fw_humans as H  # noqa: E402

try:
    import fw_beasts as B  # noqa: E402
except ImportError:  # pendant le développement
    B = None


def factories() -> dict:
    out = {k: H.make for k in H.ARCH}
    if B is not None:
        out.update({k: B.make for k in B.ARCH})
    try:
        import fw_bosses as BS  # noqa: E402
        out.update({k: BS.make for k in BS.KINDS})
    except ImportError:
        pass
    return out


ORDER = ["fw_bandit", "fw_raider", "fw_sharpshooter", "fw_marauder", "fw_bruiser", "fw_guard_dog",
         "fw_deserter", "fw_buffalo", "fw_sheriff"]


def board(path: str, kinds: list) -> None:
    """Planche de présentation : chaque modèle (idle s, run se, attaque 3 se, cadavre) sur fond sable."""
    from PIL import Image, ImageDraw
    fac = factories()
    rows = []
    for k in kinds:
        tiles = []
        for d, spec in (("s", "idle:0"), ("se", "run:2"), ("sw", "attack:3"), ("e", "death:7")):
            p = S.preview(k, fac[k], [d], [spec], out=os.path.join(S.TMP_DIR, "board_%s_%s.png" % (k, d)))
            tiles.append(Image.open(p).convert("RGBA"))
        rows.append((k, tiles))
    cell = 200
    W = 220 + cell * 4
    img = Image.new("RGBA", (W, cell * len(rows) + 20), (26, 30, 46, 255))
    dr = ImageDraw.Draw(img)
    for r, (k, tiles) in enumerate(rows):
        y = 10 + r * cell
        dr.rounded_rectangle((8, y + 4, W - 8, y + cell - 4), 12, fill=(18, 26, 46, 255), outline=(90, 110, 150, 255))
        name = fac[k](k).name if False else k
        dr.text((20, y + cell // 2 - 6), name, fill=(240, 240, 240, 255))
        for c, t in enumerate(tiles):
            bg = Image.new("RGBA", t.size, (216, 170, 120, 255))
            bg.alpha_composite(t)
            bg = bg.resize((cell - 12, cell - 12), Image.LANCZOS)
            img.paste(bg, (214 + c * cell, y + 6))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("BOARD", path)


def main() -> None:
    args = sys.argv[1:]
    fac = factories()
    kinds = args[args.index("--kinds") + 1].split(",") if "--kinds" in args else [k for k in ORDER if k in fac]
    os.makedirs(S.TMP_DIR, exist_ok=True)
    if "--preview" in args:
        dirs = args[args.index("--preview") + 1].split(",")
        anims = args[args.index("--anim") + 1].split(",") if "--anim" in args else ["idle:0"]
        for k in kinds:
            S.preview(k, fac[k], dirs, anims)
        return
    if "--board" in args:
        board(args[args.index("--board") + 1], kinds)
        return
    for k in kinds:
        S.build_kind(k, fac[k])


if __name__ == "__main__":
    main()
