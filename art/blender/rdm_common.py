"""Outils communs (Blender 5.x, bpy en module) pour les rendus « toon peint » du projet.

Principe du rendu :
- Matériaux « toon » en émission pure (Cycles) : la couleur est calculée à partir de
  dot(normale, direction de lumière) -> rampe constante 4 tons (ombre bleu nuit, ton moyen,
  base, lumière chaude de coucher de soleil), + liseré (rim) chaud côté lumière.
  Aucun calcul de lumière réel : très peu d'échantillons, aucun bruit, pas de débruitage.
- Contour sombre net : Freestyle (silhouette, bords, plis, frontières de matériaux).
- Rendu en 2x puis réduction prémultipliée (Lanczos) pour des contours propres en petit.
"""
from __future__ import annotations

import math

import bpy  # noqa: I001  (bpy doit être importé avant bmesh)
import bmesh
from mathutils import Matrix, Vector

# Direction VERS la lumière (monde). Caméra regardant vers +Y : lumière en haut à gauche de l'écran.
LIGHT_DIR = Vector((-0.62, -0.38, 0.69)).normalized()
NIGHT = (0.07, 0.09, 0.26)          # teinte des ombres (bleu nuit, linéaire)
WARM = (1.12, 0.98, 0.84)           # teinte de la lumière (coucher de soleil)
OUTLINE = (0.05, 0.03, 0.05)

_mat_cache: dict[str, bpy.types.Material] = {}


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mat_cache.clear()


def srgb_to_lin(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h: str) -> tuple[float, float, float]:
    h = h.lstrip("#")
    return tuple(srgb_to_lin(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))  # type: ignore


def _mix(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def _mul(a, b):
    return tuple(a[i] * b[i] for i in range(3))


def toon(name: str, base: str, shadow: str | None = None, lit: str | None = None,
         rim: float = 0.30, emit: float = 0.0, band: float = 0.50, grad: float = 0.0,
         grad_z: tuple[float, float] = (0.0, 1.6)) -> bpy.types.Material:
    """Matériau toon. base/shadow/lit en hex sRGB. emit > 0 => émissif pur (yeux, lueurs)."""
    if name in _mat_cache:
        return _mat_cache[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs[0], out.inputs[0])
    b = hexcol(base)
    m.diffuse_color = (*b, 1.0)
    if emit > 0.0:
        em.inputs["Color"].default_value = (*b, 1.0)
        em.inputs["Strength"].default_value = emit
        _mat_cache[name] = m
        return m
    sh = hexcol(shadow) if shadow else _mul(_mix(b, NIGHT, 0.40), (0.55, 0.62, 1.0))
    li = hexcol(lit) if lit else tuple(min(1.0, v) for v in _mul(b, WARM))
    mid = _mix(sh, b, 0.65)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(geo.outputs["Normal"], dot.inputs[0])
    dot.inputs[1].default_value = LIGHT_DIR
    remap = nt.nodes.new("ShaderNodeMapRange")
    remap.inputs["From Min"].default_value = -1.0
    remap.inputs["From Max"].default_value = 1.0
    nt.links.new(dot.outputs["Value"], remap.inputs["Value"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    els[0].position = 0.0
    els[0].color = (*sh, 1.0)
    els[1].position = band - 0.08
    els[1].color = (*mid, 1.0)
    e3 = els.new(band + 0.06)
    e3.color = (*b, 1.0)
    e4 = els.new(band + 0.30)
    e4.color = (*li, 1.0)
    nt.links.new(remap.outputs["Result"], ramp.inputs["Factor"])
    col = ramp.outputs["Color"]
    if grad > 0.0:
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Position"], sep.inputs[0])
        g = nt.nodes.new("ShaderNodeMapRange")
        g.inputs["From Min"].default_value = grad_z[0]
        g.inputs["From Max"].default_value = grad_z[1]
        g.inputs["To Min"].default_value = 1.0 - grad
        g.inputs["To Max"].default_value = 1.0
        nt.links.new(sep.outputs["Z"], g.inputs["Value"])
        cmb = nt.nodes.new("ShaderNodeCombineXYZ")
        for k in range(3):
            nt.links.new(g.outputs["Result"], cmb.inputs[k])
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(col, mul.inputs["A"])
        nt.links.new(cmb.outputs[0], mul.inputs["B"])
        col = mul.outputs["Result"]
    if rim > 0.0:
        lw = nt.nodes.new("ShaderNodeLayerWeight")
        lw.inputs["Blend"].default_value = 0.35
        rr = nt.nodes.new("ShaderNodeValToRGB")
        rr.color_ramp.interpolation = "CONSTANT"
        rr.color_ramp.elements[0].color = (0, 0, 0, 1)
        rr.color_ramp.elements[1].position = 0.66
        rr.color_ramp.elements[1].color = (rim, rim * 0.60, rim * 0.40, 1)
        nt.links.new(lw.outputs["Facing"], rr.inputs["Factor"])
        side = nt.nodes.new("ShaderNodeMath")
        side.operation = "GREATER_THAN"
        side.inputs[1].default_value = 0.10
        nt.links.new(dot.outputs["Value"], side.inputs[0])
        mrim = nt.nodes.new("ShaderNodeMix")
        mrim.data_type = "RGBA"
        mrim.blend_type = "MIX"
        nt.links.new(side.outputs[0], mrim.inputs["Factor"])
        mrim.inputs["A"].default_value = (0, 0, 0, 1)
        nt.links.new(rr.outputs["Color"], mrim.inputs["B"])
        add = nt.nodes.new("ShaderNodeMix")
        add.data_type = "RGBA"
        add.blend_type = "ADD"
        add.inputs["Factor"].default_value = 1.0
        nt.links.new(col, add.inputs["A"])
        nt.links.new(mrim.outputs["Result"], add.inputs["B"])
        col = add.outputs["Result"]
    nt.links.new(col, em.inputs["Color"])
    em.inputs["Strength"].default_value = 1.0
    _mat_cache[name] = m
    return m


# --------------------------------------------------------------------------- géométrie

def _link(obj: bpy.types.Object, coll: bpy.types.Collection | None = None) -> bpy.types.Object:
    (coll or bpy.context.scene.collection).objects.link(obj)
    return obj


def mesh_obj(name: str, bm: bmesh.types.BMesh, mat, smooth: bool = True,
             parent=None, coll=None) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    mats = mat if isinstance(mat, (list, tuple)) else [mat]
    for mm in mats:
        me.materials.append(mm)
    ob = bpy.data.objects.new(name, me)
    _link(ob, coll)
    if parent is not None:
        ob.parent = parent
    return ob


def empty(name: str, loc=(0, 0, 0), parent=None) -> bpy.types.Object:
    e = bpy.data.objects.new(name, None)
    _link(e)
    if parent is not None:
        e.parent = parent
    e.location = loc
    return e


def bm_sphere(seg: int = 12, rings: int = 8, r: float = 1.0) -> bmesh.types.BMesh:
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    return bm


def bm_cyl(seg: int, r1: float, r2: float, depth: float, cap: bool = True) -> bmesh.types.BMesh:
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=seg,
                          radius1=r1, radius2=r2, depth=depth)
    return bm


def bm_box(sx: float, sy: float, sz: float, bevel: float = 0.0, segs: int = 2) -> bmesh.types.BMesh:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((sx, sy, sz)), verts=bm.verts)
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segs,
                        affect="EDGES", profile=0.5)
    return bm


def bm_torus(seg: int, rseg: int, R: float, r: float) -> bmesh.types.BMesh:
    bm = bmesh.new()
    rows = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        row = []
        for j in range(rseg):
            b = 2 * math.pi * j / rseg
            rr = R + r * math.cos(b)
            row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), r * math.sin(b))))
        rows.append(row)
    for i in range(seg):
        for j in range(rseg):
            a, b = rows[i], rows[(i + 1) % seg]
            bm.faces.new((a[j], b[j], b[(j + 1) % rseg], a[(j + 1) % rseg]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def bm_xform(bm, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    m = (Matrix.Translation(Vector(loc))
         @ Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y")
         @ Matrix.Rotation(rot[0], 4, "X")
         @ Matrix.Diagonal((*scale, 1.0)))
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return bm


def bm_merge(*bms: bmesh.types.BMesh) -> bmesh.types.BMesh:
    """Fusionne plusieurs bmesh (les sources sont libérées)."""
    out = bmesh.new()
    for b in bms:
        me = bpy.data.meshes.new("_tmp")
        b.to_mesh(me)
        b.free()
        out.from_mesh(me)
        bpy.data.meshes.remove(me)
    return out


def bm_loft(sections: list[list[tuple[float, float, float]]], cap_start=True, cap_end=True,
            closed=True) -> bmesh.types.BMesh:
    """Surface entre des sections (listes de points de même taille)."""
    bm = bmesh.new()
    rows = [[bm.verts.new(p) for p in sec] for sec in sections]
    n = len(sections[0])
    for a, b in zip(rows, rows[1:]):
        rng = range(n) if closed else range(n - 1)
        for i in rng:
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if closed:
        if cap_start:
            bm.faces.new(list(reversed(rows[0])))
        if cap_end:
            bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def ellipse(cx, cy, cz, rx, ry, n=10, rot=0.0):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x, y = rx * math.cos(a), ry * math.sin(a)
        c, s = math.cos(rot), math.sin(rot)
        pts.append((cx + x * c - y * s, cy + x * s + y * c, cz))
    return pts


def bm_tube(path: list[tuple[float, float, float]], radii: list[float], seg: int = 8,
            flat: float = 1.0, up=(0, 0, 1), twist: float = 0.0) -> bmesh.types.BMesh:
    """Tube effilé le long d'un chemin. flat < 1 aplatit la section (plume, mèche, ruban)."""
    P = [Vector(p) for p in path]
    n = len(P)
    secs = []
    upv = Vector(up)
    for i in range(n):
        t = (P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized()
        side = t.cross(upv)
        if side.length < 1e-4:
            side = t.cross(Vector((1, 0, 0)))
        side.normalize()
        nrm = side.cross(t).normalized()
        tw = twist * i / max(1, n - 1)
        side, nrm = (side * math.cos(tw) + nrm * math.sin(tw),
                     -side * math.sin(tw) + nrm * math.cos(tw))
        r = radii[i]
        sec = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            sec.append(tuple(P[i] + side * (math.cos(a) * r) + nrm * (math.sin(a) * r * flat)))
        secs.append(sec)
    bm = bm_loft(secs, cap_start=radii[0] > 1e-4, cap_end=radii[-1] > 1e-4)
    return bm


def bezier(p0, p1, p2, p3, n):
    P = [Vector(p) for p in (p0, p1, p2, p3)]
    out = []
    for i in range(n):
        t = i / (n - 1)
        u = 1 - t
        out.append(tuple(P[0] * u ** 3 + P[1] * 3 * u * u * t + P[2] * 3 * u * t * t + P[3] * t ** 3))
    return out


def solidify(ob: bpy.types.Object, thick: float, offset: float = 0.0) -> None:
    md = ob.modifiers.new("solid", "SOLIDIFY")
    md.thickness = thick
    md.offset = offset


def subsurf(ob: bpy.types.Object, levels: int = 1) -> None:
    md = ob.modifiers.new("sub", "SUBSURF")
    md.levels = levels
    md.render_levels = levels


def decal(target: bpy.types.Object, poly2d: list[tuple[float, float]], mat, name: str,
          lift: float = 0.003, subdiv: int = 3, coll=None) -> bpy.types.Object | None:
    """Projette un polygone 2D (x, z dans le repère local de `target`) sur sa face avant (-Y).
    Le mesh obtenu est enfant de `target` (coordonnées locales identiques)."""
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    d = Vector((0, 1, 0))

    def proj(x: float, z: float):
        ok, loc, nor, _ = target.ray_cast(Vector((x, -5.0, z)), d, depsgraph=deps)
        if not ok:
            return None
        return loc + nor * lift

    cx = sum(p[0] for p in poly2d) / len(poly2d)
    cz = sum(p[1] for p in poly2d) / len(poly2d)
    c = proj(cx, cz)
    if c is None:
        return None
    bm = bmesh.new()
    vc = bm.verts.new(c)
    prev = None
    for k in range(1, subdiv + 1):
        t = k / subdiv
        vs = []
        for (x, z) in poly2d:
            p = proj(cx + (x - cx) * t, cz + (z - cz) * t)
            if p is None:
                bm.free()
                return None
            vs.append(bm.verts.new(p))
        n = len(vs)
        for i in range(n):
            j = (i + 1) % n
            if prev is None:
                bm.faces.new((vc, vs[i], vs[j]))
            else:
                bm.faces.new((prev[i], vs[i], vs[j], prev[j]))
        prev = vs
    ob = mesh_obj(name, bm, mat, smooth=True, coll=coll)
    ob.parent = target
    ob.matrix_parent_inverse = Matrix()
    ob.location = (0, 0, 0)
    return ob


# --------------------------------------------------------------------------- rendu

def setup_render(res: int | tuple[int, int], samples: int = 6, outline_px: float = 3.0,
                 freestyle: bool = True, crease: float = 120.0,
                 inner_ratio: float = 0.5, use_crease: bool = False) -> bpy.types.Scene:
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.cycles.use_adaptive_sampling = False
    sc.cycles.max_bounces = 0
    sc.cycles.transparent_max_bounces = 8
    sc.cycles.pixel_filter_type = "BLACKMAN_HARRIS"
    sc.cycles.filter_width = 1.3
    sc.render.threads_mode = "FIXED"
    sc.render.threads = 2
    if isinstance(res, int):
        res = (res, res)
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.use_freestyle = freestyle
    nofs = nofs_collection()
    if freestyle:
        sc.render.line_thickness_mode = "ABSOLUTE"
        vl = sc.view_layers[0]
        vl.use_freestyle = True
        fs = vl.freestyle_settings
        fs.crease_angle = math.radians(crease)
        while len(fs.linesets):
            fs.linesets.remove(fs.linesets[0])
        # 1) traits intérieurs fins (silhouettes internes, bords)  2) contour extérieur épais
        for name, ext, px in (("inner", False, outline_px * inner_ratio), ("outer", True, outline_px)):
            ls = fs.linesets.new(name)
            ls.select_by_visibility = True
            ls.visibility = "VISIBLE"
            ls.select_by_edge_types = True
            ls.select_silhouette = not ext
            ls.select_border = not ext
            ls.select_crease = (not ext) and use_crease
            ls.select_material_boundary = False
            ls.select_external_contour = ext
            ls.select_by_collection = True
            ls.collection_negation = "EXCLUSIVE"
            ls.collection = nofs
            lst = bpy.data.linestyles.new("ls_" + name)
            ls.linestyle = lst
            lst.color = OUTLINE
            lst.thickness = px
            lst.thickness_position = "CENTER"
            lst.caps = "ROUND"
            lst.chaining = "PLAIN"
            lst.use_same_object = not ext
    return sc


def nofs_collection() -> bpy.types.Collection:
    """Collection d'objets SANS contour Freestyle (décalques, lueurs)."""
    c = bpy.data.collections.get("nofs")
    if c is None:
        c = bpy.data.collections.new("nofs")
        bpy.context.scene.collection.children.link(c)
    return c


def ortho_camera(elev_deg: float, ortho_scale: float, target=(0, 0, 0), dist: float = 20.0,
                 azim_deg: float = 0.0) -> bpy.types.Object:
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_scale
    cam_data.clip_start = 0.1
    cam_data.clip_end = 100.0
    cam = bpy.data.objects.new("cam", cam_data)
    _link(cam)
    e = math.radians(elev_deg)
    a = math.radians(azim_deg)
    t = Vector(target)
    off = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
    cam.location = t + off
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def render_to(path: str) -> None:
    sc = bpy.context.scene
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def world_to_px(cam, co) -> tuple[float, float]:
    from bpy_extras.object_utils import world_to_camera_view
    sc = bpy.context.scene
    bpy.context.view_layer.update()
    v = world_to_camera_view(sc, cam, Vector(co))
    return (v.x * sc.render.resolution_x, (1.0 - v.y) * sc.render.resolution_y)


def downscale(src: str, dst: str | None, size: tuple[int, int]):
    """Réduction prémultipliée (évite les franges en bord d'alpha). Renvoie l'image PIL."""
    from PIL import Image
    im = Image.open(src).convert("RGBA")
    pm = im.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
    if dst:
        pm.save(dst)
    return pm


def _ramp_colors(base: str, shadow: str | None, lit: str | None):
    b = hexcol(base)
    sh = hexcol(shadow) if shadow else _mul(_mix(b, NIGHT, 0.40), (0.55, 0.62, 1.0))
    li = hexcol(lit) if lit else tuple(min(1.0, v) for v in _mul(b, WARM))
    return sh, _mix(sh, b, 0.65), b, li


def toon_pattern(name: str, colors: list, scale: float = 6.0, thresholds=(0.52, 0.60),
                 rim: float = 0.30, band: float = 0.50, detail: float = 2.0,
                 coords: str = "Object") -> bpy.types.Material:
    """Matériau toon à motif (camouflage, éclats d'or, usure) : 2 ou 3 couleurs (hex ou
    (base, ombre, lumière)) réparties par un bruit en coordonnées objet, chacune avec sa rampe
    toon 4 tons. thresholds = seuils du bruit pour la 2e puis la 3e couleur."""
    if name in _mat_cache:
        return _mat_cache[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs[0], out.inputs[0])
    specs = [(c, None, None) if isinstance(c, str) else tuple(c) for c in colors]
    m.diffuse_color = (*hexcol(specs[0][0]), 1.0)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(geo.outputs["Normal"], dot.inputs[0])
    dot.inputs[1].default_value = LIGHT_DIR
    remap = nt.nodes.new("ShaderNodeMapRange")
    remap.inputs["From Min"].default_value = -1.0
    remap.inputs["From Max"].default_value = 1.0
    nt.links.new(dot.outputs["Value"], remap.inputs["Value"])
    ramps = []
    for spec in specs:
        sh, mid, b, li = _ramp_colors(*spec)
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
        ramps.append(ramp.outputs["Color"])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    col = ramps[0]
    for k in range(1, len(ramps)):
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.noise_dimensions = "3D"
        nz.inputs["Scale"].default_value = scale * (1.0 + 0.37 * (k - 1))
        nz.inputs["Detail"].default_value = detail
        nz.inputs["Roughness"].default_value = 0.55
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Location"].default_value = (17.3 * k, 5.1 * k, 9.7 * k)
        nt.links.new(tc.outputs[coords], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
        gt = nt.nodes.new("ShaderNodeMath")
        gt.operation = "GREATER_THAN"
        gt.inputs[1].default_value = thresholds[min(k - 1, len(thresholds) - 1)]
        nt.links.new(nz.outputs["Fac"], gt.inputs[0])
        mx = nt.nodes.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        nt.links.new(gt.outputs[0], mx.inputs["Factor"])
        nt.links.new(col, mx.inputs["A"])
        nt.links.new(ramps[k], mx.inputs["B"])
        col = mx.outputs["Result"]
    if rim > 0.0:
        lw = nt.nodes.new("ShaderNodeLayerWeight")
        lw.inputs["Blend"].default_value = 0.35
        rr = nt.nodes.new("ShaderNodeValToRGB")
        rr.color_ramp.interpolation = "CONSTANT"
        rr.color_ramp.elements[0].color = (0, 0, 0, 1)
        rr.color_ramp.elements[1].position = 0.66
        rr.color_ramp.elements[1].color = (rim, rim * 0.60, rim * 0.40, 1)
        nt.links.new(lw.outputs["Facing"], rr.inputs["Factor"])
        side = nt.nodes.new("ShaderNodeMath")
        side.operation = "GREATER_THAN"
        side.inputs[1].default_value = 0.10
        nt.links.new(dot.outputs["Value"], side.inputs[0])
        mrim = nt.nodes.new("ShaderNodeMix")
        mrim.data_type = "RGBA"
        nt.links.new(side.outputs[0], mrim.inputs["Factor"])
        mrim.inputs["A"].default_value = (0, 0, 0, 1)
        nt.links.new(rr.outputs["Color"], mrim.inputs["B"])
        add = nt.nodes.new("ShaderNodeMix")
        add.data_type = "RGBA"
        add.blend_type = "ADD"
        add.inputs["Factor"].default_value = 1.0
        nt.links.new(col, add.inputs["A"])
        nt.links.new(mrim.outputs["Result"], add.inputs["B"])
        col = add.outputs["Result"]
    nt.links.new(col, em.inputs["Color"])
    em.inputs["Strength"].default_value = 1.0
    _mat_cache[name] = m
    return m


def text_mesh(name: str, body: str, size: float, mat, extrude: float = 0.0,
              coll=None) -> bpy.types.Object:
    """Texte converti en maillage (police par défaut de Blender), centré, dans le plan XY."""
    cu = bpy.data.curves.new(name + "_cu", type="FONT")
    cu.body = body
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = extrude
    tmp = bpy.data.objects.new(name + "_tmp", cu)
    bpy.context.scene.collection.objects.link(tmp)
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(deps))
    bpy.data.objects.remove(tmp)
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    _link(ob, coll)
    return ob
