"""Matériaux « peints » des armes HD (art/blender/weapons_hd.py), plus riches que le toon de
rdm_common, sans toucher aux autres rendus du projet (ennemis, héros, décors).

Toujours de l'émission pure sous Cycles (aucune vraie lumière, aucun rebond) ; la couleur est
calculée dans le shader :
- ombrage dégradé (rampe à transitions douces) entre ombre bleu nuit, base et lumière chaude,
  même direction de lumière que le reste du jeu (rdm_common.LIGHT_DIR) ;
- occlusion ambiante (nœud AO) : creux, jonctions, intérieur des fentes assombris ;
- arêtes usées : nœud Bevel (normale arrondie) comparé à la normale réelle, éclaircit les bords
  (métal qui brille, polymère qui blanchit) ;
- reflet spéculaire en bande nette (métal, verre, vernis) ;
- grain : bruit (polymère, acier) ou veinage (bois, onde le long de X) ;
- liseré chaud côté lumière, comme le toon.
Beaucoup plus d'échantillons que le toon (AO et Bevel sont échantillonnés) : rendus petits, ça reste rapide.
"""
from __future__ import annotations

import bpy

import rdm_common as C

_cache: dict[str, bpy.types.Material] = {}
## Rendu d'un skin : hook(nom) -> matériau qui remplace celui demandé (None = matériau normal).
## Couvre aussi les matériaux créés directement par les modèles (noyer, marine doré du P90…).
hook = None


def _node(nt, kind, **inputs):
    n = nt.nodes.new(kind)
    for k, v in inputs.items():
        n.inputs[k].default_value = v
    return n


def _math(nt, op, a, b=None, clamp=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    n.use_clamp = clamp
    for i, x in enumerate((a, b)):
        if x is None:
            continue
        if isinstance(x, (int, float)):
            n.inputs[i].default_value = x
        else:
            nt.links.new(x, n.inputs[i])
    return n.outputs[0]


def _mix(nt, fac, a, b, blend="MIX"):
    n = nt.nodes.new("ShaderNodeMix")
    n.data_type = "RGBA"
    n.blend_type = blend
    for sock, x in (("Factor", fac), ("A", a), ("B", b)):
        if isinstance(x, (int, float)):
            n.inputs[sock].default_value = x
        elif isinstance(x, tuple):
            n.inputs[sock].default_value = (*x[:3], 1.0)
        else:
            nt.links.new(x, n.inputs[sock])
    return n.outputs["Result"]


def _vdot(nt, a, b):
    n = nt.nodes.new("ShaderNodeVectorMath")
    n.operation = "DOT_PRODUCT"
    for i, x in enumerate((a, b)):
        if isinstance(x, tuple):
            n.inputs[i].default_value = x
        else:
            nt.links.new(x, n.inputs[i])
    return n.outputs["Value"]


def paint(name: str, base: str, shadow: str | None = None, lit: str | None = None, *,
          metal: float = 0.0, wear: float = 0.0, gloss: float = 0.0, grain: float = 0.05,
          grain_scale: float = 60.0, wood: float = 0.0, ao: float = 0.55, rim: float = 0.28,
          edge: str | None = None, emit: float = 0.0, soft: float = 0.10, alt: str | None = None,
          alt_scale: float = 10.0, alt_cut: float = 0.62, grad: float = 0.32,
          layers: list | None = None) -> bpy.types.Material:
    """Matériau peint.
    base/shadow/lit : hex sRGB (ombre et lumière déduites si absentes, comme C.toon).
    metal : 0..1, reflet spéculaire et arêtes brillantes ; wear : 0..1, usure des arêtes ;
    gloss : reflet sans métal (vernis, verre) ; grain : variation du bruit (0..0.2) ;
    wood : 0..1, veinage le long de X ; ao : force de l'occlusion ; soft : largeur des transitions
    d'ombrage ; edge : couleur des arêtes usées (défaut : lumière) ; emit > 0 : émission pure ;
    alt : 2e couleur en taches (camouflage, éclats d'or) au-delà du seuil alt_cut d'un bruit ;
    grad : dégradé de lumière en diagonale sur toute l'arme (plus clair en haut à l'arrière, côté
    lumière) : donne du volume aux grandes faces plates vues de profil ;
    layers : motifs de skin superposés, [(hex, masque)] où masque(nt, coord objet) -> prise 0/1
    (build_weapon_skins.mask_bands, mask_flames…)."""
    if hook is not None:
        r = hook(name)
        if r is not None:
            return r
    if name in _cache:
        return _cache[name]
    m = bpy.data.materials.new("hd_" + name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs[0], out.inputs[0])
    b = C.hexcol(base)
    m.diffuse_color = (*b, 1.0)
    if emit > 0.0:
        em.inputs["Color"].default_value = (*b, 1.0)
        em.inputs["Strength"].default_value = emit
        _cache[name] = m
        return m
    sh, mid, _b, li = C._ramp_colors(base, shadow, lit)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    # Normale arrondie (arêtes) : sert à l'ombrage (bords qui accrochent la lumière) et à l'usure.
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = 0.022
    nrm = bev.outputs["Normal"]
    # Ombrage : dot(N, L) -> rampe douce 4 tons.
    ndl = _vdot(nt, nrm, tuple(C.LIGHT_DIR))
    remap = _node(nt, "ShaderNodeMapRange", **{"From Min": -1.0, "From Max": 1.0})
    nt.links.new(ndl, remap.inputs["Value"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "EASE"
    els = ramp.color_ramp.elements
    els[0].position = 0.18
    els[0].color = (*sh, 1.0)
    els[1].position = 0.44
    els[1].color = (*mid, 1.0)
    e = els.new(0.52 + soft)
    e.color = (*b, 1.0)
    e = els.new(min(0.98, 0.80 + soft))
    e.color = (*li, 1.0)
    nt.links.new(remap.outputs["Result"], ramp.inputs["Factor"])
    col = ramp.outputs["Color"]
    # Taches d'une 2e couleur (camouflage, éclats d'or du Légendaire).
    if alt:
        ash, amid, ab, ali = C._ramp_colors(alt, None, None)
        ramp2 = nt.nodes.new("ShaderNodeValToRGB")
        ramp2.color_ramp.interpolation = "EASE"
        e2 = ramp2.color_ramp.elements
        e2[0].position = 0.18
        e2[0].color = (*ash, 1.0)
        e2[1].position = 0.44
        e2[1].color = (*amid, 1.0)
        x = e2.new(0.52 + soft)
        x.color = (*ab, 1.0)
        x = e2.new(min(0.98, 0.80 + soft))
        x.color = (*ali, 1.0)
        nt.links.new(remap.outputs["Result"], ramp2.inputs["Factor"])
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nz = _node(nt, "ShaderNodeTexNoise", Scale=alt_scale, Detail=4.0, Roughness=0.6)
        nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        cut = nt.nodes.new("ShaderNodeValToRGB")
        cut.color_ramp.interpolation = "CONSTANT"
        cut.color_ramp.elements[0].color = (0, 0, 0, 1)
        cut.color_ramp.elements[1].position = alt_cut
        cut.color_ramp.elements[1].color = (1, 1, 1, 1)
        nt.links.new(nz.outputs["Fac"], cut.inputs["Factor"])
        col = _mix(nt, cut.outputs["Color"], col, ramp2.outputs["Color"])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    # Motifs de skin (rayures, flammes…) : chaque couche a sa propre rampe d'ombrage.
    for (lhex, mask_fn) in (layers or []):
        lsh, lmid, lb, lli = C._ramp_colors(lhex, None, None)
        lr = nt.nodes.new("ShaderNodeValToRGB")
        lr.color_ramp.interpolation = "EASE"
        le = lr.color_ramp.elements
        le[0].position = 0.18
        le[0].color = (*lsh, 1.0)
        le[1].position = 0.44
        le[1].color = (*lmid, 1.0)
        x = le.new(0.52 + soft)
        x.color = (*lb, 1.0)
        x = le.new(min(0.98, 0.80 + soft))
        x.color = (*lli, 1.0)
        nt.links.new(remap.outputs["Result"], lr.inputs["Factor"])
        col = _mix(nt, mask_fn(nt, tc.outputs["Object"]), col, lr.outputs["Color"])
    # Veinage du bois (ondes le long de X, déformées) ou grain (bruit fin).
    if wood > 0.0:
        wave = _node(nt, "ShaderNodeTexWave", Scale=3.2, Distortion=5.0, Detail=3.0)
        wave.wave_type = "BANDS"
        wave.bands_direction = "Z"
        nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
        wr = nt.nodes.new("ShaderNodeValToRGB")
        wr.color_ramp.elements[0].color = (1.0 - 0.35 * wood,) * 3 + (1,)
        wr.color_ramp.elements[1].color = (1, 1, 1, 1)
        nt.links.new(wave.outputs["Fac"], wr.inputs["Factor"])
        col = _mix(nt, 1.0, col, wr.outputs["Color"], blend="MULTIPLY")
    if grain > 0.0:
        nz = _node(nt, "ShaderNodeTexNoise", Scale=grain_scale, Detail=6.0, Roughness=0.65)
        nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        gr = _node(nt, "ShaderNodeMapRange", **{"To Min": 1.0 - grain, "To Max": 1.0 + grain * 0.6})
        nt.links.new(nz.outputs["Fac"], gr.inputs["Value"])
        g3 = nt.nodes.new("ShaderNodeCombineXYZ")
        for k in range(3):
            nt.links.new(gr.outputs["Result"], g3.inputs[k])
        col = _mix(nt, 1.0, col, g3.outputs[0], blend="MULTIPLY")
    # Arêtes : 1 - dot(N arrondie, N réelle) -> masque des bords, éclaircis (usure / brillance).
    if wear > 0.0 or metal > 0.0:
        ed = _vdot(nt, nrm, geo.outputs["Normal"])
        mask = _math(nt, "SUBTRACT", 1.0, ed)
        mask = _math(nt, "MULTIPLY", mask, 14.0, clamp=True)
        mask = _math(nt, "MULTIPLY", mask, max(wear, metal * 0.7), clamp=True)
        ec = C.hexcol(edge) if edge else tuple(min(1.0, v * 1.15) for v in li)
        col = _mix(nt, mask, col, ec)
    # Dégradé diagonal (position monde) : haut-arrière éclairé, bas-avant dans l'ombre.
    if grad > 0.0:
        gp = _vdot(nt, geo.outputs["Position"], (-0.3, 0.0, 1.0))
        gm = _node(nt, "ShaderNodeMapRange", **{"From Min": -0.55, "From Max": 0.55,
                                                  "To Min": 1.0 - grad, "To Max": 1.0 + grad * 0.55})
        nt.links.new(gp, gm.inputs["Value"])
        g3 = nt.nodes.new("ShaderNodeCombineXYZ")
        for k in range(3):
            nt.links.new(gm.outputs["Result"], g3.inputs[k])
        col = _mix(nt, 1.0, col, g3.outputs[0], blend="MULTIPLY")
    # Occlusion ambiante : creux et jonctions.
    if ao > 0.0:
        aon = nt.nodes.new("ShaderNodeAmbientOcclusion")
        aon.samples = 12
        aon.inputs["Distance"].default_value = 0.09
        aof = _node(nt, "ShaderNodeMapRange", **{"To Min": 1.0 - ao, "To Max": 1.0})
        nt.links.new(aon.outputs["AO"], aof.inputs["Value"])
        a3 = nt.nodes.new("ShaderNodeCombineXYZ")
        for k in range(3):
            nt.links.new(aof.outputs["Result"], a3.inputs[k])
        col = _mix(nt, 1.0, col, a3.outputs[0], blend="MULTIPLY")
    # Reflet : demi-vecteur entre lumière et caméra, bande nette.
    if metal > 0.0 or gloss > 0.0:
        hv = nt.nodes.new("ShaderNodeVectorMath")
        hv.operation = "ADD"
        hv.inputs[0].default_value = tuple(C.LIGHT_DIR)
        nt.links.new(geo.outputs["Incoming"], hv.inputs[1])
        hn = nt.nodes.new("ShaderNodeVectorMath")
        hn.operation = "NORMALIZE"
        nt.links.new(hv.outputs[0], hn.inputs[0])
        ndh = _vdot(nt, nrm, hn.outputs[0])
        sp = nt.nodes.new("ShaderNodeValToRGB")
        sp.color_ramp.interpolation = "EASE"
        sp.color_ramp.elements[0].position = 0.86
        sp.color_ramp.elements[0].color = (0, 0, 0, 1)
        sp.color_ramp.elements[1].position = 0.95
        s = max(metal, gloss)
        tint = tuple(min(1.0, v * 1.3) for v in li) if metal > 0.0 else (1.0, 0.97, 0.9)
        sp.color_ramp.elements[1].color = (tint[0] * s, tint[1] * s, tint[2] * s, 1)
        nt.links.new(ndh, sp.inputs["Factor"])
        col = _mix(nt, 1.0, col, sp.outputs["Color"], blend="ADD")
    # Liseré chaud côté lumière.
    if rim > 0.0:
        lw = _node(nt, "ShaderNodeLayerWeight", Blend=0.3)
        rr = nt.nodes.new("ShaderNodeValToRGB")
        rr.color_ramp.interpolation = "EASE"
        rr.color_ramp.elements[0].position = 0.55
        rr.color_ramp.elements[0].color = (0, 0, 0, 1)
        rr.color_ramp.elements[1].position = 0.8
        rr.color_ramp.elements[1].color = (rim, rim * 0.62, rim * 0.42, 1)
        nt.links.new(lw.outputs["Facing"], rr.inputs["Factor"])
        side = _math(nt, "GREATER_THAN", ndl, 0.05)
        rim_c = _mix(nt, side, (0, 0, 0), rr.outputs["Color"])
        col = _mix(nt, 1.0, col, rim_c, blend="ADD")
    nt.links.new(col, em.inputs["Color"])
    em.inputs["Strength"].default_value = 1.0
    _cache[name] = m
    return m


def reset() -> None:
    _cache.clear()
