"""Outils communs du biome Station Orbitale (Blender 5.x en module) : palette sci-fi, matériaux
toon à reflet froid, constructeur de pièces (repris du pipeline Far West) et rendu d'un sprite isolé.

Même caméra que le héros et les décors Far West : orthographique, plongée 48°, 1 BU = 36 unités
monde, contour Freestyle, ombre portée bleu nuit (2e rendu de la géométrie cisaillée au sol).
Différence de ton : lumière froide (cyan/blanc) au lieu du couchant ; les émissifs (écrans, néons,
alarmes, cœur du réacteur) restent purs pour être lisibles sous le brouillard.
"""
from __future__ import annotations

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import rdm_common as C  # noqa: E402
import bpy  # noqa: E402
import importlib.util  # noqa: E402


def _load(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# Pipeline Far West (Builder, rendu de pièce, grain peint) chargé par chemin (noms de fichiers identiques).
FP = _load("fw_build_props", os.path.join(os.path.dirname(HERE), "build_props.py"))

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TMP = os.path.join(os.environ.get("RDM_TMP", "/tmp/rdm_decor"), "space_station")
ELEV = 48.0
WORLD_PER_BU = 36.0

# (base, ombre, lumière) en hex sRGB ; None = dérivé.
PAL = {
    "steel": ("#8a94a8", "#2c3250", "#a8b4c8"),
    "steel_dark": ("#4a5064", "#181c34", "#626c86"),
    "gunmetal": ("#3a3e4e", "#12142a", "#4c5468"),
    "white_panel": ("#c4ccd8", "#6a7698", "#e2e8f2"),
    "hazard": ("#e8b830", "#6a4a30", "#ffe070"),
    "orange": ("#d8742c", "#5a2a2a", "#ffa858"),
    "red": ("#c02a2e", "#4a1028", "#ee4a44"),
    "navy": ("#2e3a5e", "#10142e", "#4c5e8c"),
    "teal": ("#3a8a96", "#123044", "#6ac4d0"),
    "olive": ("#6a7444", "#262c30", "#9aa466"),
    "rubber": ("#2a2a32", "#0c0c18", "#4a4a58"),
    "cloth_grey": ("#7a8090", "#2a2e48", "#a8b0c4"),
    "cloth_blue": ("#40588c", "#141c3c", "#6a88c0"),
    "mattress": ("#aab2c0", "#525c7c", "#ccd4e2"),
    "plant": ("#4e9a48", "#183a3a", "#8ad070"),
    "plant_dark": ("#2e6a3a", "#0e2a2e", "#58a058"),
    "soil": ("#4a3a34", "#1a1424", "#6a5448"),
    "copper": ("#b8703c", "#4a2a2e", "#f0a060"),
    "brass": ("#c8a040", "#5a4030", "#ffe08a"),
    "glass_dark": ("#28344e", "#0c1024", "#5a74a0"),
    "skin_pale": ("#c8c0c8", "#6a6488", "#f0e8f0"),
    "mask": ("#ece6dc", "#8a8cac", "#ffffff"),
    "bone": ("#e2d8c4", "#7e7a98", "#fff8ea"),
}
# Émissifs : couleur hex, intensité.
EMIT = {
    "screen_cyan": ("#46c4f0", 1.3),
    "screen_amber": ("#ffb040", 1.5),
    "screen_green": ("#60f090", 1.4),
    "neon_white": ("#e8fbff", 1.6),
    "alarm_red": ("#ff3828", 1.8),
    "core_cyan": ("#7af0ff", 2.2),
    "core_blue": ("#3a9cff", 1.6),
    "grow_purple": ("#d070ff", 1.6),
    "liquid_green": ("#58f0b0", 1.2),
    "liquid_cyan": ("#58d8f0", 1.2),
    "holo": ("#7ae8ff", 1.3),
    "led_green": ("#60ff80", 2.0),
    "led_amber": ("#ffc040", 2.0),
    "eye_red": ("#ff3020", 2.0),
    "eye_cyan": ("#60f0ff", 2.0),
    "eye_violet": ("#c070ff", 2.0),
    "eye_gold": ("#ffc840", 2.0),
    "plasma": ("#ff6a2a", 2.0),
}

def reset() -> None:
    C.reset_scene()


def toon(name: str, base: str, shadow: str | None, lit: str | None, rim: float = 0.22) -> bpy.types.Material:
    """Matériau toon (cf. rdm_common.toon) avec liseré FROID (cyan) au lieu du liseré chaud."""
    key = "ss_" + name
    m = C.toon(key, base, shadow, lit, rim=0.0)
    if rim > 0.0 and m.get("ss_rim") is None:
        m["ss_rim"] = 1
        nt = m.node_tree
        em = [n for n in nt.nodes if n.type == "EMISSION"][0]
        src = em.inputs["Color"].links[0].from_socket
        geo = [n for n in nt.nodes if n.type == "NEW_GEOMETRY"][0]
        lw = nt.nodes.new("ShaderNodeLayerWeight")
        lw.inputs["Blend"].default_value = 0.35
        rr = nt.nodes.new("ShaderNodeValToRGB")
        rr.color_ramp.interpolation = "CONSTANT"
        rr.color_ramp.elements[0].color = (0, 0, 0, 1)
        rr.color_ramp.elements[1].position = 0.68
        rr.color_ramp.elements[1].color = (rim * 0.55, rim * 0.85, rim, 1)
        nt.links.new(lw.outputs["Facing"], rr.inputs["Factor"])
        dot = nt.nodes.new("ShaderNodeVectorMath")
        dot.operation = "DOT_PRODUCT"
        nt.links.new(geo.outputs["Normal"], dot.inputs[0])
        dot.inputs[1].default_value = C.LIGHT_DIR
        side = nt.nodes.new("ShaderNodeMath")
        side.operation = "GREATER_THAN"
        side.inputs[1].default_value = 0.1
        nt.links.new(dot.outputs["Value"], side.inputs[0])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MIX"
        nt.links.new(side.outputs[0], mix.inputs["Factor"])
        mix.inputs["A"].default_value = (0, 0, 0, 1)
        nt.links.new(rr.outputs["Color"], mix.inputs["B"])
        add = nt.nodes.new("ShaderNodeMix")
        add.data_type = "RGBA"
        add.blend_type = "ADD"
        add.inputs["Factor"].default_value = 1.0
        nt.links.new(src, add.inputs["A"])
        nt.links.new(mix.outputs["Result"], add.inputs["B"])
        nt.links.new(add.outputs["Result"], em.inputs["Color"])
    return m


def M(key: str, rim: float = 0.22) -> bpy.types.Material:
    if key in EMIT:
        col, k = EMIT[key]
        return C.toon("ss_e_" + key, col, emit=k)
    b, s, l = PAL[key]
    return toon(key, b, s, l, rim)


def custom(name: str, base: str, rim: float = 0.2) -> bpy.types.Material:
    """Matériau toon d'une couleur libre (ombre/lumière dérivées)."""
    return toon(name, base, None, None, rim)


Builder = FP.Builder


def set_pieces_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)
    FP.PIECES = path


def render_sprite(name: str, build_fn, frame_world: tuple[float, float], px_per_world: float, out_path: str,
                  target_z: float = 1.0, outline_px: float = 4.0, shadow: bool = True, feet_margin: int = 4,
                  samples: int = 3, extra_objs=None, anchor_bottom: bool = False, pow2: bool = True) -> dict:
    """Rendu d'un sprite isolé (conteneur, cachette, ennemi) : objet + ombre bleu nuit, recadré
    avec les pieds centrés horizontalement et `feet_margin` px sous le point d'appui.
    Renvoie {size, feet, eyes?}."""
    from PIL import Image, ImageFilter
    reset()
    ss = 2
    wpx, hpx = int(frame_world[0] * px_per_world), int(frame_world[1] * px_per_world)
    C.setup_render((wpx * ss, hpx * ss), samples=samples, outline_px=outline_px, inner_ratio=0.45)
    B = Builder()
    info_extra = build_fn(B) or {}
    px_per_bu = px_per_world * WORLD_PER_BU
    cam = C.ortho_camera(ELEV, max(wpx, hpx) / px_per_bu, target=(0, 0, target_z), dist=30.0)
    bpy.context.view_layer.update()
    feet = C.world_to_px(cam, (0, 0, 0))
    feet = (feet[0] / ss, feet[1] / ss)
    pts = {}
    for k, co in info_extra.items():
        p = C.world_to_px(cam, co)
        pts[k] = (p[0] / ss, p[1] / ss)
    tmp = os.path.join(TMP, "sprites")
    os.makedirs(tmp, exist_ok=True)
    big = os.path.join(tmp, name + ".big.png")
    C.render_to(big)
    obj = C.downscale(big, None, (wpx, hpx))
    comp = Image.new("RGBA", (wpx, hpx), (0, 0, 0, 0))
    if shadow:
        for ob in B.objs:
            ob.hide_render = True
        FP._shadow_objects(B)
        bpy.context.scene.render.use_freestyle = False
        C.render_to(big)
        sh = C.downscale(big, None, (wpx, hpx)).getchannel("A").filter(ImageFilter.GaussianBlur(1.4))
        layer = Image.new("RGBA", (wpx, hpx), FP.SHADOW_RGBA[:3] + (0,))
        layer.putalpha(sh.point(lambda a: a * FP.SHADOW_RGBA[3] // 255))
        comp = Image.alpha_composite(comp, layer)
    comp = Image.alpha_composite(comp, FP._paint(obj))
    os.remove(big)
    bb = comp.getchannel("A").point(lambda a: 255 if a > 6 else 0).getbbox()
    if bb is None:
        raise RuntimeError("sprite vide : " + name)
    # Recadrage : pieds au centre horizontal, `feet_margin` px sous les pieds.
    half = int(math.ceil(max(feet[0] - bb[0], bb[2] - feet[0]))) + 2
    left = int(round(feet[0])) - half
    right = int(round(feet[0])) + half
    top = max(bb[1] - 2, 0)
    bottom = int(round(feet[1])) + feet_margin
    bottom = bb[3] + feet_margin if anchor_bottom else max(bottom, bb[3] + 1)
    W, H = right - left, bottom - top
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(comp.crop((max(left, 0), top, min(right, wpx), min(bottom, hpx))), (max(-left, 0), 0))
    if pow2:
        # Puissances de 2 (compression VRAM mobile) : marge centrée en largeur, en haut en hauteur
        # (le bas et le centre horizontal, qui servent d'ancrage, ne bougent pas).
        W2, H2 = 1, 1
        while W2 < W:
            W2 *= 2
        while H2 < H:
            H2 *= 2
        padl, padt = (W2 - W) // 2, H2 - H
        big_out = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
        big_out.paste(out, (padl, padt))
        out = big_out
        left -= padl
        top -= padt
        W, H = W2, H2
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    out.save(out_path, optimize=True)
    res = {"size": [W, H], "feet": [round(feet[0] - left, 1), round(feet[1] - top, 1)]}
    for k, p in pts.items():
        res[k] = [round(p[0] - left, 1), round(p[1] - top, 1)]
    print("SPRITE", name, res, flush=True)
    return res


def write_json(path: str, data: dict) -> None:
    with open(path, "w") as f:
        json.dump(data, f, indent=1)


def rgb01(h: str):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def bevel_box(B, name, size, loc, mat, bevel=0.03, rot=(0, 0, 0), **kw):
    return B.box(name, size, loc, mat, rot=rot, bevel=bevel, **kw)


def ring_of(B, name, R, r, loc, mat, rot=(0, 0, 0), **kw):
    return B.torus(name, R, r, loc, mat, rot=rot, **kw)


def hazard_band(B, name, w, loc, h=0.08, d=0.02, n=8, rot=(0, 0, 0)):
    """Bande jaune et noire (pavés alternés) sur une face avant (-Y)."""
    x0 = loc[0] - w / 2
    step = w / n
    for i in range(n):
        B.box("%s%d" % (name, i), (step * 0.98, d, h), (x0 + (i + 0.5) * step, loc[1], loc[2]),
              M("hazard" if i % 2 == 0 else "rubber", rim=0.0), shadow=False, outline=False)


__all__ = ["C", "FP", "M", "custom", "Builder", "reset", "render_sprite", "set_pieces_dir", "TMP", "ROOT",
           "write_json", "math", "bevel_box", "hazard_band", "EMIT", "PAL"]
