"""Skins d'armes « premium » rendus sous Blender (textures dédiées, prioritaires sur le shader).

Usage (depuis la racine du projet) :
    python3 art/blender/build_weapon_skins.py                      # tous les skins de SKINS
    python3 art/blender/build_weapon_skins.py wsk_deagle_gold      # un seul

Sorties (mêmes dimensions que les images d'origine : grip/muzzle du JSON de l'arme valables) :
- assets/sprites/weapons/skins/<skin_id>.png : arme tenue (3/4 plongeant, canon vers la droite) ;
- assets/ui/weapons/skins/<skin_id>.png : icône de profil 256x128.
Le jeu (WeaponSkin.apply) choisit ces textures si elles existent, sinon recolore par shader.
Principe : on reconstruit l'arme de build_weapons.py avec un jeu de matériaux remplacé
(or massif, néon, tigre, flammes, camouflage), même caméra, même contour.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdm_common as C  # noqa: E402
import build_weapons as BW  # noqa: E402
import bpy  # noqa: E402

ROOT = BW.ROOT
OUT_HELD = os.path.join(ROOT, "assets", "sprites", "weapons", "skins")
OUT_ICON = os.path.join(ROOT, "assets", "ui", "weapons", "skins")
BASE_MATS = BW.mats   # jeu de matériaux d'origine (BW.mats est remplacé pendant un rendu)


# --------------------------------------------------------------------------- matériaux à masque

def _ramp(nt, remap, base, shadow, lit, band=0.5):
    sh, mid, b, li = C._ramp_colors(base, shadow, lit)
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    els[0].position = 0.0
    els[0].color = (*sh, 1.0)
    els[1].position = band - 0.08
    els[1].color = (*mid, 1.0)
    els.new(band + 0.06).color = (*b, 1.0)
    els.new(band + 0.30).color = (*li, 1.0)
    nt.links.new(remap.outputs["Result"], ramp.inputs["Factor"])
    return ramp.outputs["Color"]


def toon_masked(name, base_spec, layers, rim=0.35):
    """Matériau toon (émission pure, rampe 4 tons) avec des couches superposées : chaque couche =
    (spec, masque) ; spec = (base, ombre, lumière) hex, ou ("emit", hex, force) pour un néon ;
    masque = fonction(nt, coord) -> prise Float 0/1 en coordonnées objet."""
    if name in C._mat_cache:
        return C._mat_cache[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs[0], out.inputs[0])
    m.diffuse_color = (*C.hexcol(base_spec[0]), 1.0)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(geo.outputs["Normal"], dot.inputs[0])
    dot.inputs[1].default_value = C.LIGHT_DIR
    remap = nt.nodes.new("ShaderNodeMapRange")
    remap.inputs["From Min"].default_value = -1.0
    remap.inputs["From Max"].default_value = 1.0
    nt.links.new(dot.outputs["Value"], remap.inputs["Value"])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    col = _ramp(nt, remap, *base_spec)
    for spec, mask in layers:
        if spec[0] == "emit":
            rgb = nt.nodes.new("ShaderNodeRGB")
            c = C.hexcol(spec[1])
            rgb.outputs[0].default_value = (c[0] * spec[2], c[1] * spec[2], c[2] * spec[2], 1.0)
            layer = rgb.outputs[0]
        else:
            layer = _ramp(nt, remap, *spec)
        mx = nt.nodes.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        nt.links.new(mask(nt, tc.outputs["Object"]), mx.inputs["Factor"])
        nt.links.new(col, mx.inputs["A"])
        nt.links.new(layer, mx.inputs["B"])
        col = mx.outputs["Result"]
    if rim > 0.0:
        lw = nt.nodes.new("ShaderNodeLayerWeight")
        lw.inputs["Blend"].default_value = 0.35
        rr = nt.nodes.new("ShaderNodeValToRGB")
        rr.color_ramp.interpolation = "CONSTANT"
        rr.color_ramp.elements[0].color = (0, 0, 0, 1)
        rr.color_ramp.elements[1].position = 0.66
        rr.color_ramp.elements[1].color = (rim, rim * 0.6, rim * 0.4, 1)
        nt.links.new(lw.outputs["Facing"], rr.inputs["Factor"])
        add = nt.nodes.new("ShaderNodeMix")
        add.data_type = "RGBA"
        add.blend_type = "ADD"
        add.inputs["Factor"].default_value = 1.0
        nt.links.new(col, add.inputs["A"])
        nt.links.new(rr.outputs["Color"], add.inputs["B"])
        col = add.outputs["Result"]
    nt.links.new(col, em.inputs["Color"])
    em.inputs["Strength"].default_value = 1.0
    C._mat_cache[name] = m
    return m


def _math(nt, op, a, b=None):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    for i, v in enumerate((a, b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def _sep(nt, co):
    s = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(co, s.inputs[0])
    return s.outputs


def _noise(nt, co, scale, detail=2.0, offset=(0, 0, 0)):
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Location"].default_value = offset
    nt.links.new(co, mp.inputs["Vector"])
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.noise_dimensions = "3D"
    nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = detail
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    return nz.outputs["Fac"]


def mask_bands(freq, width, warp=0.0, axis="X", phase=0.0, tilt=0.0):
    """Bandes perpendiculaires à l'axe (rayures de tigre, filets néon) : |sin| > 1 - width."""
    def f(nt, co):
        x = _sep(nt, co)[{"X": 0, "Y": 1, "Z": 2}[axis]]
        z = _sep(nt, co)[2]
        v = _math(nt, "ADD", x, _math(nt, "MULTIPLY", z, tilt))
        if warp > 0.0:
            v = _math(nt, "ADD", v, _math(nt, "MULTIPLY", _noise(nt, co, 3.2, 2.0, (4.1, 2.2, 0.7)), warp))
        s = _math(nt, "SINE", _math(nt, "ADD", _math(nt, "MULTIPLY", v, freq), phase))
        return _math(nt, "GREATER_THAN", s, 1.0 - width)
    return f


def mask_flames(threshold, tongues=7.0, depth=0.35):
    """Flammes « hot rod » : la zone x > seuil, avec des langues pointues vers l'arrière (selon z)."""
    def f(nt, co):
        sx = _sep(nt, co)
        saw = _math(nt, "PINGPONG", _math(nt, "MULTIPLY", sx[2], tongues), 1.0)      # 0..1 triangle
        n = _noise(nt, co, 4.0, 2.0, (1.3, 7.7, 3.1))
        edge = _math(nt, "ADD", threshold, _math(nt, "MULTIPLY", saw, depth))
        edge = _math(nt, "ADD", edge, _math(nt, "MULTIPLY", n, 0.12))
        return _math(nt, "GREATER_THAN", sx[0], edge)
    return f


def mask_noise(scale, threshold, offset=(0, 0, 0)):
    def f(nt, co):
        return _math(nt, "GREATER_THAN", _noise(nt, co, scale, 2.0, offset), threshold)
    return f


# --------------------------------------------------------------------------- jeux de matériaux

BODY_KEYS = ["black", "dark", "worn", "gunmetal", "legend", "navy", "tan", "olive", "olive_dark",
             "engraved", "silver", "steel", "bronze", "brass", "khaki", "cream", "putty"]
WOOD_KEYS = ["wood", "wood_dark", "wood_grip"]


def mats_gold():
    m = BASE_MATS()
    gold = C.toon("skG_gold", "#e8b440", "#7a4818", "#fff4c4", rim=0.7)
    gold_dk = C.toon("skG_golddk", "#b8842a", "#4e2c12", "#f6d47a", rim=0.6)
    grip = C.toon("skG_grip", "#2a2228", "#0c0810", "#4a3c40", rim=0.3)
    for k in BODY_KEYS:
        m[k] = gold
    for k in ("dark", "steel"):
        m[k] = gold_dk
    for k in WOOD_KEYS + ["rubber"]:
        m[k] = grip
    m["gold"] = C.toon("skG_pale", "#fff0b8", "#a07030", "#ffffff", rim=0.6)
    return m


def mats_neon():
    m = BASE_MATS()
    base = ("#1e1a2a", "#07050e", "#3c3450")
    purple = mask_bands(28.0, 0.05, axis="X", tilt=0.9)
    cyan = mask_bands(17.0, 0.04, axis="X", phase=1.7, tilt=-0.6)
    body = toon_masked("skN_body", base, [(("emit", "#c040ff", 1.6), purple), (("emit", "#38f0ff", 1.5), cyan)])
    acc = toon_masked("skN_acc", base, [(("emit", "#38f0ff", 1.5), mask_bands(30.0, 0.05, axis="Z"))])
    for k in BODY_KEYS:
        m[k] = body
    for k in ("black", "rubber") + tuple(WOOD_KEYS):
        m[k] = acc
    m["dark"] = C.toon("skN_dark", "#2a2638", "#0a0812", "#4a4460", rim=0.4)
    m["bronze"] = C.toon("skN_glow", "#c040ff", emit=1.8)
    m["gold"] = C.toon("skN_glow2", "#38f0ff", emit=1.6)
    return m


def mats_tiger():
    m = BASE_MATS()
    fur = ("#f08a1e", "#6a2c12", "#ffc46a")
    stripes = mask_bands(24.0, 0.5, warp=0.35, axis="X", tilt=0.45)
    tiger = toon_masked("skT_tiger", fur, [(("#1a120e", "#060406", "#3a2a20"), stripes)])
    for k in WOOD_KEYS:
        m[k] = tiger
    m["black"] = C.toon("skT_black", "#26221e", "#0a0808", "#4a4238", rim=0.32)
    return m


def mats_flames():
    m = BASE_MATS()
    base = ("#1a161c", "#060408", "#3a343e")
    red = mask_flames(-0.6, tongues=13.0, depth=0.42)
    yellow = mask_flames(-0.1, tongues=13.0, depth=0.42)
    fl = toon_masked("skF_flames", base, [(("#e0281a", "#6a0c10", "#ff6a3a"), red),
                                          (("#ffc02a", "#b0481a", "#fff2a0"), yellow)])
    for k in BODY_KEYS:
        m[k] = fl
    m["black"] = C.toon("skF_black", "#1e1a20", "#08060a", "#3e3842", rim=0.3)
    m["gold"] = C.toon("skF_gold", "#ffc02a", "#8a4a1a", "#fff2a0", rim=0.5)
    return m


def mats_desert():
    m = BASE_MATS()
    camo = C.toon_pattern("skD_camo", [("#c8aa78", "#6a5440", "#ecd8aa"), ("#8a6a44", "#3e2e26", "#b89060"),
                                       ("#5a4232", "#241a18", "#7e604a")], 4.5, thresholds=(0.5, 0.62), rim=0.3)
    for k in ("black", "worn", "gunmetal", "legend", "navy"):
        m[k] = camo
    m["dark"] = C.toon("skD_dark", "#4a3e34", "#1a1414", "#6e5e4e", rim=0.3)
    return m


SKINS = {
    "wsk_deagle_gold": ("pistol_deagle", mats_gold),
    "wsk_vector_neon": ("smg_vector", mats_neon),
    "wsk_ak47_tiger": ("rifle_ak47", mats_tiger),
    "wsk_aug_flames": ("rifle_aug", mats_flames),
    "wsk_mp5_desert": ("smg_mp5", mats_desert),
}


def render_skin(skin_id: str) -> None:
    wid, matfn = SKINS[skin_id]
    fn = BW.WEAPONS[wid]
    orig_mats = BW.mats
    BW.mats = lambda: matfn()   # _render() appelle build(mats()) : on remplace le jeu de matériaux
    try:
        os.makedirs(OUT_HELD, exist_ok=True)
        os.makedirs(OUT_ICON, exist_ok=True)
        big, _cam, _info, (W, H) = BW._render(skin_id, fn, BW.HELD_ELEV, None, 1.3, 3, ppu=BW.PX_PER_UNIT)
        C.downscale(big, os.path.join(OUT_HELD, skin_id + ".png"), (W, H))
        big, _c, _i, (W2, H2) = BW._render(skin_id + "_icon", fn, BW.ICON_ELEV, BW.ICON_SIZE, 2.2, 10, azim=BW.ICON_AZIM)
        C.downscale(big, os.path.join(OUT_ICON, skin_id + ".png"), (W2, H2))
    finally:
        BW.mats = orig_mats
    print("SKIN", skin_id, wid, (W, H), (W2, H2), flush=True)


def main() -> None:
    for sid in (sys.argv[1:] or list(SKINS)):
        render_skin(sid)


if __name__ == "__main__":
    main()
