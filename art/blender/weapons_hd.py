"""Armes HD : modèles détaillés et matériaux peints (weapon_paint.py), rendus en double résolution.

Usage (depuis la racine du projet, environnement tools/prerender/mac_env.sh) :
    python3 art/blender/weapons_hd.py                         # toutes les armes HD
    python3 art/blender/weapons_hd.py pistol_p9 rifle_aug     # quelques-unes
    python3 art/blender/weapons_hd.py --compare out.png [ids] # planche avant (origin/main) / après

Mêmes sorties et mêmes repères que build_weapons.py (qui reste la référence des armes non refaites) :
- assets/sprites/weapons/<id>.png + .json : arme tenue, 3/4 plongeant, canon vers la droite. Deux fois
  plus de pixels par unité (PX_PER_UNIT 88) et échelle moitié (0.225) : même taille en jeu, image nette ;
- assets/ui/weapons/<id>.png + .json : icône de profil 512 × 256 (grip, muzzle, size).
Repère : X = canon, Z = haut, Y = profondeur (côté visible = -Y).
Rareté visible sur l'arme : Commun polymère et acier noir mat, Rare acier patiné, Épique bois et
gravures, Légendaire noir à éclats d'or.
"""
from __future__ import annotations

import json
import math
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import weapon_paint as WP  # noqa: E402
import build_weapons as BW  # noqa: E402
from weapons_hd_kit import mats  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

ROOT = BW.ROOT
OUT = BW.OUT
OUT_ICON = BW.OUT_ICON
TMP = os.environ.get("RDM_TMP", "/tmp/rdm_weapons_hd")
SS = 3
PX_PER_UNIT = 88.0
HELD_SCALE = BW.HELD_SCALE * BW.PX_PER_UNIT / PX_PER_UNIT   # même taille en jeu
ICON_SIZE = (512, 256)
SAMPLES = 48
OUTLINE_HELD = 2.0
OUTLINE_ICON = 3.4
INNER_RATIO = 0.28


# Familles : chaque module weapons_hd_<famille>.py expose WEAPONS = {id: fonction de modèle}.
FAMILIES = ["weapons_hd_base", "weapons_hd_pistols", "weapons_hd_smg", "weapons_hd_p90", "weapons_hd_rifles",
            "weapons_hd_heavy", "weapons_hd_launchers", "weapons_hd_gadgets"]
HD: dict = {}
for _fam in FAMILIES:
    if os.path.exists(os.path.join(os.path.dirname(os.path.abspath(__file__)), _fam + ".py")):
        HD.update(__import__(_fam).WEAPONS)


# --------------------------------------------------------------------------- skins d'armes

def _skin_mats(over, base_fn):
    """Jeu de matériaux de l'arme (base_fn) avec certaines clés remplacées (over() -> {clé: matériau})."""
    def f():
        m = base_fn()
        m.update(over())
        return m
    return f


def _tiger():
    import build_weapon_skins as BWS
    stripes = BWS.mask_bands(24.0, 0.5, warp=0.35, axis="X", tilt=0.45)
    tiger = WP.paint("skT_tiger", "#f08a1e", "#6a2c12", "#ffc46a", gloss=0.3, wear=0.2, grain=0.03,
                     layers=[("#1a120e", stripes)])
    return {"wood": tiger, "wood_dark": tiger, "bakelite": tiger,
            "blued": WP.paint("skT_black", "#28231f", "#0a0808", "#544a40", metal=0.5, wear=0.5)}


def _flames():
    import build_weapon_skins as BWS
    red = BWS.mask_flames(-0.6, tongues=13.0, depth=0.42)
    yellow = BWS.mask_flames(-0.1, tongues=13.0, depth=0.42)
    fl = WP.paint("skF_flames", "#1c181e", "#060408", "#443c48", gloss=0.35, wear=0.25,
                  layers=[("#e0281a", red), ("#ffc02a", yellow)])
    return {"legend": fl, "legend_flat": fl,
            "gold": WP.paint("skF_gold", "#ffc02a", "#8a4a1a", "#fff2a0", metal=1.0, wear=0.3)}


# --- Skins générés depuis data/skins/<id>.tres (couleurs + motif) ---------------------------------

# Matériaux jamais recouverts par un skin : âme du canon, verre, points, laiton, LED, chargeur fumé.
SKIN_KEEP = {"bore", "white", "glass", "brass", "smoke", "led", "led_b", "led_g", "rubber"}
# Petites pièces métalliques : teintées de la couleur secondaire, sans motif.
SKIN_METAL = {"steel", "dark"}


def _tres_skin(skin_id: str) -> dict:
    """Champs utiles d'un SkinData (.tres) : weapon_id, pattern, couleurs en hex."""
    import re
    path = os.path.join(ROOT, "data", "skins", skin_id + ".tres")
    txt = open(path, encoding="utf-8").read()
    out = {"weapon_id": re.search(r'weapon_id = &"([^"]+)"', txt).group(1),
           "pattern": re.search(r'pattern = &"([^"]*)"', txt).group(1)}
    for key in ("color_primary", "color_secondary", "color_accent"):
        r, g, b = (float(v) for v in re.search(key + r" = Color\(([^,]+), ([^,]+), ([^,]+),", txt).groups())
        out[key] = "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))
    return out


def _mask_digital(scale, threshold, offset=(0, 0, 0)):
    """Camouflage numérique : bruit échantillonné sur une grille (pixels carrés)."""
    import build_weapon_skins as BWS

    def f(nt, co):
        mul = nt.nodes.new("ShaderNodeVectorMath")
        mul.operation = "MULTIPLY"
        mul.inputs[1].default_value = (scale, scale, scale)
        nt.links.new(co, mul.inputs[0])
        fl = nt.nodes.new("ShaderNodeVectorMath")
        fl.operation = "FLOOR"
        nt.links.new(mul.outputs[0], fl.inputs[0])
        dv = nt.nodes.new("ShaderNodeVectorMath")
        dv.operation = "DIVIDE"
        dv.inputs[1].default_value = (scale, scale, scale)
        nt.links.new(fl.outputs[0], dv.inputs[0])
        return BWS._math(nt, "GREATER_THAN", BWS._noise(nt, dv.outputs[0], 5.0, 2.0, offset), threshold)
    return f


def _mask_checker(scale):
    """Tissage carbone : damier fin."""
    def f(nt, co):
        ch = nt.nodes.new("ShaderNodeTexChecker")
        ch.inputs["Scale"].default_value = scale
        nt.links.new(co, ch.inputs["Vector"])
        return ch.outputs["Fac"]
    return f


def _auto_skin(skin_id: str):
    """Matériaux d'un skin d'après son SkinData : motif sur les pièces principales de l'arme."""
    import build_weapon_skins as BWS
    d = _tres_skin(skin_id)
    p, s2, a = d["color_primary"], d["color_secondary"], d["color_accent"]
    pat = d["pattern"]
    name = "sk_" + skin_id

    def build():
        return _skin_materials(name, pat, p, s2, a)

    def over():
        import weapons_hd_kit as KIT
        main, metal = build()
        return {k: (metal if k in SKIN_METAL else main) for k in KIT.mats() if k not in SKIN_KEEP}
    return d["weapon_id"], over


def _skin_materials(name, pat, p, s2, a):
    """(matériau principal à motif, matériau des petites pièces métalliques) d'un skin."""
    import build_weapon_skins as BWS
    if pat == "camo":
        main = WP.paint(name, p, wear=0.3, grain=0.06, layers=[(s2, BWS.mask_noise(4.5, 0.55)),
                                                              (a, BWS.mask_noise(6.0, 0.62, (3.1, 1.7, 0.4)))])
    elif pat == "digital":
        main = WP.paint(name, p, wear=0.25, grain=0.04, layers=[(s2, _mask_digital(22.0, 0.52)),
                                                               (a, _mask_digital(22.0, 0.6, (5.2, 2.1, 1.3)))])
    elif pat == "stripes":
        main = WP.paint(name, p, gloss=0.35, wear=0.3, layers=[(s2, BWS.mask_bands(9.0, 0.22, axis="X", tilt=0.7)),
                                                              (a, BWS.mask_bands(9.0, 0.05, axis="X", tilt=0.7,
                                                                                 phase=0.5))])
    elif pat == "carbon":
        # Tissage fin et peu contrasté : couleur secondaire mêlée à 35 % de la primaire.
        def mixhex(h1, h2, t):
            c1 = [int(h1[i:i + 2], 16) for i in (1, 3, 5)]
            c2 = [int(h2[i:i + 2], 16) for i in (1, 3, 5)]
            return "#%02x%02x%02x" % tuple(round(x + (y - x) * t) for x, y in zip(c1, c2))
        main = WP.paint(name, s2, gloss=0.5, wear=0.35, edge=a, layers=[(mixhex(s2, p, 0.35), _mask_checker(260.0))])
    elif pat == "neon":
        main = WP.paint(name, s2, gloss=0.5, wear=0.2, edge=a, layers=[(p, BWS.mask_bands(7.0, 0.07, axis="X",
                                                                                          tilt=0.9)),
                                                                     (a, BWS.mask_bands(7.0, 0.035, axis="X",
                                                                                        tilt=-0.9, phase=1.3))])
    elif pat == "gold":
        main = WP.paint(name, p, s2, a, metal=1.0, wear=0.4, grain=0.03, edge=a)
    elif pat == "rust":
        main = WP.paint(name, s2, metal=0.4, wear=0.4, grain=0.1, layers=[(p, BWS.mask_noise(5.0, 0.5)),
                                                                         (a, BWS.mask_noise(9.0, 0.66, (2.2, 0.3, 4.1)))])
    else:
        main = WP.paint(name, p, wear=0.3)
    metal = WP.paint(name + "_metal", s2, metal=0.6, wear=0.4)
    if pat == "gold":
        metal = WP.paint(name + "_metal", a, s2, "#ffffff", metal=1.0, wear=0.3)
    return main, metal


SKINS = {"wsk_ak47_tiger": ("rifle_ak47", _tiger), "wsk_aug_flames": ("rifle_aug", _flames)}


def skin_ids() -> list[str]:
    """Tous les skins d'armes du jeu (data/skins/wsk_*.tres)."""
    d = os.path.join(ROOT, "data", "skins")
    return sorted(f[:-5] for f in os.listdir(d) if f.startswith("wsk_") and f.endswith(".tres"))


def skin_entry(skin_id: str):
    """(arme, fonction d'override) : skin fait main (SKINS) sinon généré depuis le .tres."""
    if skin_id in SKINS:
        return SKINS[skin_id]
    wid, over = _auto_skin(skin_id)
    return wid, over
OUT_SKIN_HELD = os.path.join(OUT, "skins")
OUT_SKIN_ICON = os.path.join(OUT_ICON, "skins")


# --------------------------------------------------------------------------- rendu

def _render(wid, build, elev, size, outline, pad_px, azim=0.0, ppu=PX_PER_UNIT):
    C.reset_scene()
    WP.reset()
    info = build(mats())
    pts = BW._points()
    cam = C.ortho_camera(elev, 10.0, target=(0, 0, 0), azim_deg=azim)
    bpy.context.view_layer.update()
    u, v = BW._cam_uv(cam, pts)
    cu, cv = (u.min() + u.max()) / 2, (v.min() + v.max()) / 2
    w_u, h_u = u.max() - u.min(), v.max() - v.min()
    if size is None:
        W = int(math.ceil((w_u * ppu + 2 * pad_px) / 4.0) * 4)
        H = int(math.ceil((h_u * ppu + 2 * pad_px) / 4.0) * 4)
        ortho = W / ppu
    else:
        W, H = size
        ortho = max(w_u / (W - 2 * pad_px) * W, h_u / (H - 2 * pad_px) * W)
    cam.location = cam.location + cam.matrix_world.to_3x3() @ Vector((cu, cv, 0))
    cam.data.ortho_scale = ortho
    cam.data.sensor_fit = "HORIZONTAL"
    C.setup_render((W * SS, H * SS), samples=SAMPLES, outline_px=outline * SS, inner_ratio=INNER_RATIO)
    bpy.context.scene.camera = cam
    os.makedirs(TMP, exist_ok=True)
    big = os.path.join(TMP, wid + "_big.png")
    C.render_to(big)
    return big, cam, info, (W, H)


def _px(cam, co):
    g = C.world_to_px(cam, co)
    return [round(g[0] / SS, 1), round(g[1] / SS, 1)]


def render_skin(skin_id: str) -> None:
    """Skin d'arme : même modèle et même cadrage que l'arme (grip/muzzle du JSON de l'arme valables)."""
    wid, over = skin_entry(skin_id)
    global mats
    base = mats
    mats = _skin_mats(over, base)
    if skin_id not in SKINS:
        # Skin généré : tout matériau de l'arme hors petites pièces techniques prend le motif.
        d = _tres_skin(skin_id)
        name = "sk_" + skin_id

        def _hook(mat_name):
            if mat_name in SKIN_KEEP or mat_name.startswith("sk"):
                return None
            main, metal = _skin_materials(name, d["pattern"], d["color_primary"], d["color_secondary"],
                                          d["color_accent"])
            return metal if mat_name in SKIN_METAL else main
        WP.hook = _hook
    try:
        big, _cam, _info, (W, H) = _render(skin_id, HD[wid], BW.HELD_ELEV, None, OUTLINE_HELD, 6)
        C.downscale(big, os.path.join(OUT_SKIN_HELD, skin_id + ".png"), (W, H))
        big, _cam, _info, (W2, H2) = _render(skin_id + "_icon", HD[wid], BW.ICON_ELEV, ICON_SIZE, OUTLINE_ICON, 20,
                                             azim=BW.ICON_AZIM)
        C.downscale(big, os.path.join(OUT_SKIN_ICON, skin_id + ".png"), (W2, H2))
    finally:
        mats = base
        WP.hook = None
    print("SKIN", skin_id, (W, H), (W2, H2), flush=True)


# Rareté des rendus (JSON) : celle de build_weapons, plus les gadgets qu'il ne modélisait pas.
RARITY = dict(BW.RARITY, gadget_decoy=0)
GADGET_HELD_PX = 96.0                                 # gadget tenu : largeur fixe (px), 2 × l'ancienne
GADGET_SCALE = BW.GADGET_SCALE * 48.0 / GADGET_HELD_PX  # même taille en jeu
WORLD_SIZE = BW.WORLD_SIZE


def render_item(wid: str) -> None:
    fn = HD[wid]
    gadget = wid.startswith("gadget_")
    ppu = PX_PER_UNIT
    if gadget:
        # Gadget tenu : largeur fixe à l'écran, quelle que soit sa taille en unités.
        C.reset_scene()
        WP.reset()
        fn(mats())
        u, _v = BW._cam_uv(C.ortho_camera(BW.HELD_ELEV, 10.0), BW._points())
        ppu = GADGET_HELD_PX / max(u.max() - u.min(), 1e-3)
    big, cam, info, (W, H) = _render(wid, fn, BW.HELD_ELEV, None, OUTLINE_HELD, 6, ppu=ppu)
    C.downscale(big, os.path.join(OUT, wid + ".png"), (W, H))
    meta = {"grip": [round(x) for x in _px(cam, info["grip"])],
            "muzzle": [round(x) for x in _px(cam, info["muzzle"])],
            "scale": round(GADGET_SCALE if gadget else HELD_SCALE, 4), "size": [W, H], "rarity": RARITY[wid]}
    with open(os.path.join(OUT, wid + ".json"), "w", newline="\n") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    elev, azim = (22.0, -25.0) if gadget else (BW.ICON_ELEV, BW.ICON_AZIM)
    big, cam, info, (W, H) = _render(wid, fn, elev, ICON_SIZE, OUTLINE_ICON, 20, azim=azim)
    C.downscale(big, os.path.join(OUT_ICON, wid + ".png"), (W, H))
    if not gadget:
        imeta = {"grip": _px(cam, info["grip"]), "muzzle": _px(cam, info["muzzle"]), "size": [W, H]}
        with open(os.path.join(OUT_ICON, wid + ".json"), "w", newline="\n") as f:
            json.dump(imeta, f, indent=2)
            f.write("\n")
    if gadget:
        # Objet au sol / en vol, vu du dessus (64 × 64) ; drone : deux images, hélices décalées.
        frames = [("_world", fn)]
        if wid == "gadget_drone":
            frames = [("_world", lambda mm: fn(mm, 0.0)), ("_world_b", lambda mm: fn(mm, math.pi / 2))]
        for suffix, f2 in frames:
            el, az = (70.0, 0.0) if wid == "gadget_drone" else (62.0, -20.0)
            big, _c, _i, _s = _render(wid + suffix, f2, el, (WORLD_SIZE, WORLD_SIZE), 1.4, 3, azim=az)
            C.downscale(big, os.path.join(OUT, wid + suffix + ".png"), (WORLD_SIZE, WORLD_SIZE))
    print("HD", wid, meta, flush=True)


def compare(out: str, ids: list[str]) -> None:
    """Planche avant (git COMPARE_REF, origin/main par défaut) / après : icône et arme tenue, sur fond de rareté."""
    from io import BytesIO
    from PIL import Image, ImageDraw

    def old(path):
        rel = os.path.relpath(path, ROOT)
        ref = os.environ.get("COMPARE_REF", "origin/main")
        data = subprocess.run(["git", "-C", ROOT, "show", ref + ":" + rel], capture_output=True).stdout
        return Image.open(BytesIO(data)).convert("RGBA") if data else None

    cw, ch = 560, 330
    sheet = Image.new("RGBA", (cw * 2 + 30, ch * len(ids) + 50), (16, 18, 30, 255))
    dr = ImageDraw.Draw(sheet)
    dr.text((20, 14), "AVANT", fill=(220, 220, 230, 255))
    dr.text((cw + 30, 14), "APRES", fill=(220, 220, 230, 255))
    for r, wid in enumerate(ids):
        y = 40 + r * ch
        col = BW.RARITY_COL[RARITY[wid]]
        for c, get in enumerate((old, lambda p: Image.open(p).convert("RGBA"))):
            x = 10 + c * (cw + 10)
            dr.rounded_rectangle((x, y, x + cw, y + ch - 10), 10, outline=col, width=2,
                                 fill=(col[0] // 7 + 16, col[1] // 7 + 18, col[2] // 7 + 30, 255))
            ic = get(os.path.join(OUT_ICON, wid + ".png"))
            if ic is not None:
                ic.thumbnail((512, 200))
                sheet.alpha_composite(ic, (x + (cw - ic.width) // 2, y + 8))
            held = get(os.path.join(OUT, wid + ".png"))
            if held is not None:
                # Arme tenue à sa taille en jeu (échelle du JSON) × 2 pour la voir.
                meta_scale = BW.HELD_SCALE if c == 0 else HELD_SCALE
                k = meta_scale / BW.HELD_SCALE * 2.0
                held = held.resize((max(1, int(held.width * k)), max(1, int(held.height * k))), Image.LANCZOS)
                sheet.alpha_composite(held, (x + 14, y + ch - 20 - held.height))
            dr.text((x + cw - 160, y + ch - 30), wid, fill=(240, 240, 240, 255))
    sheet.save(out)
    print("COMPARE", out, flush=True)


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ids = [a for a in args if a in HD]
    if "--skins" in args:
        # Seulement les skins (de toutes les armes HD, ou des skins nommés).
        for sid in [a for a in args if a.startswith("wsk_")] or skin_ids():
            if _tres_skin(sid)["weapon_id"] in HD:
                render_skin(sid)
        return
    if "--compare" in args:
        compare(args[args.index("--compare") + 1], ids or list(HD))
        return
    for wid in (ids or list(HD)):
        render_item(wid)
    # Replis par catégorie (<category>.png/.json) = copies du modèle commun de chaque catégorie.
    BW.write_category_fallbacks()
    # Skins des armes rendues (même taille d'image que l'arme : grip/muzzle partagés).
    if "--no-skins" not in args:
        for sid in skin_ids():
            if _tres_skin(sid)["weapon_id"] in (ids or list(HD)):
                render_skin(sid)


if __name__ == "__main__":
    main()
