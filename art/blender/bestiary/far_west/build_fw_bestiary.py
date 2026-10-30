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


NAMES = {"fw_bandit": "Bandit", "fw_raider": "Pillard", "fw_sharpshooter": "Tireur d'élite",
         "fw_marauder": "Maraudeur", "fw_bruiser": "Robuste", "fw_guard_dog": "Chien de garde",
         "fw_deserter": "Le Déserteur (élite)", "fw_buffalo": "Le Buffle (élite)",
         "fw_sheriff": "Le Shérif Sable-Fou (boss)"}


def board(path: str, kinds: list) -> None:
    """Planche de présentation : par modèle, idle (s), course (se), attaque (sw), cadavre (e)
    [+ charge à cheval pour le shérif], à la même échelle (densité de pixels du jeu)."""
    from PIL import Image, ImageDraw, ImageFont
    fac = factories()
    rows = []
    for k in kinds:
        specs = [("s", "idle:0"), ("se", "run:2"), ("sw", "attack:3"), ("e", "death:7")]
        if k == "fw_sheriff":
            specs.insert(3, ("e", "charge:2"))
        tiles = []
        for d, spec in specs:
            p = S.preview(k, fac[k], [d], [spec], out=os.path.join(S.TMP_DIR, "board_%s_%s_%s.png" % (k, d, spec[0])))
            tiles.append(Image.open(p).convert("RGBA"))
        rows.append((k, tiles))
    cell = 220
    W = 250 + cell * 5
    img = Image.new("RGBA", (W, cell * len(rows) + 20), (18, 26, 46, 255))
    dr = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 20)
        small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
    except OSError:
        font = small = ImageFont.load_default()
    for r, (k, tiles) in enumerate(rows):
        y = 10 + r * cell
        dr.rounded_rectangle((8, y + 4, W - 8, y + cell - 4), 14, fill=(26, 36, 60, 255), outline=(120, 140, 180, 255))
        dr.text((22, y + cell // 2 - 22), NAMES.get(k, k), fill=(255, 255, 255, 255), font=font)
        dr.text((22, y + cell // 2 + 6), k, fill=(190, 196, 210, 255), font=small)
        for c, t in enumerate(tiles):
            bg = Image.new("RGBA", (cell - 16, cell - 16), (216, 170, 120, 255))
            # même échelle pour tous : on recadre le cadre (192/224/288/320 px) autour des pieds
            s = t.size[0]
            crop = t.crop(((s - 288) // 2, (s - 288) // 2, (s + 288) // 2, (s + 288) // 2)) if s >= 288 else t
            if s < 288:
                pad = Image.new("RGBA", (288, 288), (0, 0, 0, 0))
                pad.alpha_composite(t, ((288 - s) // 2, (288 - s) // 2 + (288 - s) // 4))
                crop = pad
            crop = crop.resize((cell - 16, cell - 16), Image.LANCZOS)
            bg.alpha_composite(crop)
            img.paste(bg, (240 + c * cell, y + 8))
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    img.convert("RGB").save(path)
    print("BOARD", path)


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
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
