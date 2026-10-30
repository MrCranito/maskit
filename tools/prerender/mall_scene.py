"""Scène Blender complète du rez-de-chaussée des Galeries Lumière (centre commercial abandonné
façon maquette docs/reference/cartes.png, colonne « Centre commercial abandonné »), construite
depuis le layout JSON exporté par tools/prerender/export_layout.gd (4e argument :
res://data/worlds/world_03_mall.tres), rendue en Cycles. Même pipeline, mêmes passes et même
projection que fw_scene.py / ss_scene.py.

Usage (bpy en module) :
  python3 mall_scene.py <layout.json> <out_dir> [ppc=24] [samples=16] [passes=full,int] [margin=4]
Passes : full (par morceaux, reprise possible) ; int (patch « sans toit » par boutique fermée :
         plafond et haut de la façade sud masqués) ; mask (emprise au sol, vue zénithale) ; occ
         (ids d'occultation) ; crop:x0;x1;y0;y1 ; view:x0;x1;y0;y1;tilt;ppc
Sorties : full.png, b<id>_in.png, mask.png, occ.png, render.json, layout.json (pour compose.py).

PROJECTION (identique à fw_scene.py) : caméra orthographique inclinée de TILT (38°) vers le nord,
  pixel_aspect_x = 1/cos(TILT) ; px = (cx + M) * ppc ; py = (cy + M) * ppc - z * tan(TILT) * ppc.
Repère Blender : 1 unité = 1 case. X = colonne, Y = -rangée, Z = hauteur.

Contenu, DE NUIT : grand bâtiment rectangulaire, ceinture de boutiques (vitrines, néons rose /
rouge / cyan / vert, rayons, comptoirs, mobilier), galeries au carrelage poli, atrium bordé de
jardinières avec fontaine, îlots de boutiques à plafond (climatiseurs, enseignes), escalators
doubles, salle d'arcade, café à enseigne « CAFÉ », hall d'entrée vitré, parking extérieur (bitume,
places marquées, grand « P », terre-pleins plantés, lampadaires, voitures abandonnées), rues
alentour (cases VOID, hors jeu). Éclairage : plafonniers chauds, néons, lampadaires, lune bleutée.
Les blocs génériques (NT, MB, frame, grade, render_chunked, render_mask, render_occ) sont repris
de fw_scene.py.
"""
import sys, json, math, random, time, os
import bpy, bmesh
from mathutils import Vector, Matrix, Euler, noise as mnoise

A = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]  # blender -b --python … -- args
LAYOUT = json.load(open(A[0]))
OUT = A[1]
PPC = int(A[2]) if len(A) > 2 else 24
SAMPLES = int(A[3]) if len(A) > 3 else 16
PASSES = (A[4] if len(A) > 4 else "full").split(",")
MARGIN = int(A[5]) if len(A) > 5 else 4
os.makedirs(OUT, exist_ok=True)

TILT_DEG = float(os.environ.get("MALL_TILT", "38"))
TILT = math.radians(TILT_DEG)
W, H = LAYOUT["size"]
TILES = LAYOUT["tiles"]
SEED = int(LAYOUT.get("seed", 1))
RNG = random.Random(SEED)
C = LAYOUT.get("contract", {})


def tile(x, y):
    if x < 0 or y < 0 or x >= W or y >= H:
        return 0
    return int(TILES[y][x])


def walk(x, y):
    return tile(x, y) in (1, 2, 4, 5, 6)


def Y(r):
    """Rangée (vers le bas) → Y Blender."""
    return -r


bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
COLS = {}


def coll(name):
    if name not in COLS:
        c = bpy.data.collections.new(name)
        scene.collection.children.link(c)
        COLS[name] = c
    return COLS[name]


MATS = {}


class NT:
    """Petite surcouche pour écrire des shaders en Python."""

    def __init__(self, name):
        self.m = bpy.data.materials.new(name)
        self.m.use_nodes = True
        self.t = self.m.node_tree
        for n in list(self.t.nodes):
            self.t.nodes.remove(n)
        self.out = self.n("ShaderNodeOutputMaterial")
        self.b = self.n("ShaderNodeBsdfPrincipled")
        self.l(self.b.outputs[0], self.out.inputs["Surface"])
        MATS[name] = self.m

    def n(self, kind):
        return self.t.nodes.new(kind)

    def l(self, a, b):
        self.t.links.new(a, b)

    def _in(self, sock, v):
        if isinstance(v, (int, float)):
            sock.default_value = v
        elif isinstance(v, tuple):
            sock.default_value = (*v, 1.0) if len(v) == 3 else v
        else:
            self.l(v, sock)

    def uv(self):
        return self.n("ShaderNodeTexCoord").outputs["UV"]

    def obj(self):
        return self.n("ShaderNodeTexCoord").outputs["Object"]

    def sep(self, v):
        s = self.n("ShaderNodeSeparateXYZ")
        self.l(v, s.inputs[0])
        return s.outputs[0], s.outputs[1], s.outputs[2]

    def comb(self, x, y, z=0.0):
        c = self.n("ShaderNodeCombineXYZ")
        for i, v in enumerate((x, y, z)):
            self._in(c.inputs[i], v)
        return c.outputs[0]

    def m_(self, op, a, b=None, clamp=False):
        m = self.n("ShaderNodeMath")
        m.operation = op
        m.use_clamp = clamp
        self._in(m.inputs[0], a)
        if b is not None:
            self._in(m.inputs[1], b)
        return m.outputs[0]

    def add(self, a, b): return self.m_("ADD", a, b)
    def mul(self, a, b): return self.m_("MULTIPLY", a, b)
    def sub(self, a, b): return self.m_("SUBTRACT", a, b)

    def vmul(self, v, s):
        m = self.n("ShaderNodeVectorMath")
        m.operation = "MULTIPLY"
        self._in(m.inputs[0], v)
        m.inputs[1].default_value = s if isinstance(s, tuple) else (s, s, s)
        return m.outputs[0]

    def smooth(self, v, a, b, c=0.0, d=1.0):
        r = self.n("ShaderNodeMapRange")
        r.interpolation_type = "SMOOTHSTEP"
        self._in(r.inputs["Value"], v)
        r.inputs["From Min"].default_value = a
        r.inputs["From Max"].default_value = b
        r.inputs["To Min"].default_value = c
        r.inputs["To Max"].default_value = d
        return r.outputs[0]

    def noise(self, v, scale, detail=4.0, rough=0.55, dim="3D", col=False):
        n = self.n("ShaderNodeTexNoise")
        n.noise_dimensions = dim
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        self.l(v, n.inputs["Vector"])
        return n.outputs["Color" if col else "Fac"]

    def white(self, v):
        n = self.n("ShaderNodeTexWhiteNoise")
        n.noise_dimensions = "3D"
        self.l(v, n.inputs["Vector"])
        return n.outputs["Value"]

    def voronoi(self, v, scale, out="Distance"):
        n = self.n("ShaderNodeTexVoronoi")
        n.inputs["Scale"].default_value = scale
        self.l(v, n.inputs["Vector"])
        return n.outputs[out]

    def mix(self, fac, a, b, blend="MIX"):
        m = self.n("ShaderNodeMix")
        m.data_type = "RGBA"
        m.blend_type = blend
        self._in(m.inputs[0], fac)
        self._in(m.inputs[6], a)
        self._in(m.inputs[7], b)
        return m.outputs[2]

    def ramp(self, fac, cols):
        r = self.n("ShaderNodeValToRGB")
        cr = r.color_ramp
        for i, (p, c) in enumerate(cols):
            e = cr.elements[i] if i < 2 else cr.elements.new(p)
            e.position = p
            e.color = (*c, 1.0)
        self.l(fac, r.inputs[0])
        return r.outputs[0]

    def bump(self, h, strength, dist=0.02, normal=None):
        b = self.n("ShaderNodeBump")
        b.inputs["Strength"].default_value = strength
        b.inputs["Distance"].default_value = dist
        self.l(h, b.inputs["Height"])
        if normal is not None:
            self.l(normal, b.inputs["Normal"])
        return b.outputs[0]

    def zpos(self):
        _, _, z = self.sep(self.obj())
        return z

    def ao(self, dist=0.6):
        a = self.n("ShaderNodeAmbientOcclusion")
        a.inputs["Distance"].default_value = dist
        a.samples = 8
        return a.outputs["AO"]

    def done(self, col, rough=0.85, normal=None, metal=0.0, rough_sock=None):
        self.l(col, self.b.inputs["Base Color"]) if not isinstance(col, tuple) else self._in(self.b.inputs["Base Color"], col)
        if rough_sock is not None:
            self.l(rough_sock, self.b.inputs["Roughness"])
        else:
            self.b.inputs["Roughness"].default_value = rough
        self.b.inputs["Metallic"].default_value = metal
        if normal is not None:
            self.l(normal, self.b.inputs["Normal"])
        return self.m

    def boards(self, u, v, pw, L, gap=0.05):
        """Lames : u travers (largeur pw), v long (longueur L). Renvoie (aléa/lame, joint 0..1, grain)."""
        iu = self.m_("FLOOR", self.m_("DIVIDE", u, pw))
        r0 = self.white(self.comb(iu, 3.1, 0.0))
        vv = self.add(self.m_("DIVIDE", v, L), self.mul(r0, 7.0))
        iv = self.m_("FLOOR", vv)
        r = self.white(self.comb(iu, iv, 1.7))
        fu = self.m_("FRACT", self.m_("DIVIDE", u, pw))
        g = gap / pw
        j1 = self.sub(1.0, self.mul(self.smooth(fu, 0.0, g), self.smooth(fu, 1.0, 1.0 - g)))
        fv = self.m_("FRACT", vv)
        j2 = self.sub(1.0, self.smooth(fv, 0.0, 0.02))
        joint = self.m_("MAXIMUM", j1, self.mul(j2, 0.8))
        grain = self.noise(self.comb(self.mul(u, 2.0), self.mul(v, 0.12), self.mul(r, 9.0)), 30.0, 5, 0.6)
        return r, joint, grain



# ======================================================================= matériaux de la station
def mat_simple(name, c, rough=0.6, metal=0.0, var=0.25, scale=4.0, c2=None, bump=0.15, emit=None):
    s = NT(name)
    n = s.noise(s.obj(), scale, 5, 0.6)
    col = s.mix(s.mul(n, var * 2), c, c2 if c2 else tuple(x * 0.6 for x in c))
    s.done(col, rough, s.bump(n, bump, 0.02), metal)
    if emit:
        s.b.inputs["Emission Color"].default_value = (*emit[0], 1)
        s.b.inputs["Emission Strength"].default_value = emit[1]
    return s.m


def mat_emit(name, c, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value = (*c, 1)
    e.inputs[1].default_value = strength
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs[0], o.inputs[0])
    MATS[name] = m
    return m


def mat_panels(name, base, dark, pw=1.0, ph=0.5, seam=0.025, var=0.12, rough=0.45, metal=0.55, grime=0.35,
               stripe=None, rivets=False):
    """Panneaux métalliques en UV monde (u horizontal, v vertical / au sol x, y) : joints sombres,
    teinte par panneau, salissures, rayures légères. stripe = (couleur, v0, v1) bande peinte."""
    s = NT(name)
    uvv = s.uv()
    u, v, _ = s.sep(uvv)
    fu = s.m_("FRACT", s.m_("DIVIDE", u, pw))
    fv = s.m_("FRACT", s.m_("DIVIDE", v, ph))
    iu = s.m_("FLOOR", s.m_("DIVIDE", u, pw))
    iv = s.m_("FLOOR", s.m_("DIVIDE", v, ph))
    r = s.white(s.comb(iu, iv, 2.3))
    gu = seam / pw
    gv = seam / ph
    ju = s.sub(1.0, s.mul(s.smooth(fu, 0.0, gu), s.smooth(fu, 1.0, 1.0 - gu)))
    jv = s.sub(1.0, s.mul(s.smooth(fv, 0.0, gv), s.smooth(fv, 1.0, 1.0 - gv)))
    joint = s.m_("MAXIMUM", ju, jv)
    col = s.mix(s.mul(r, var * 2.0), base, tuple(min(1.0, x * 1.25) for x in base))
    n = s.noise(s.obj(), 3.0, 5, 0.6)
    col = s.mix(s.smooth(n, 0.45, 0.8, 0.0, grime), col, tuple(x * 0.55 for x in base))
    if stripe:
        sc, v0, v1 = stripe
        band = s.mul(s.smooth(v, v0 - 0.01, v0), s.sub(1.0, s.smooth(v, v1, v1 + 0.01)))
        col = s.mix(band, col, sc)
    col = s.mix(s.mul(joint, 0.85), col, dark)
    sc_ = s.noise(s.comb(s.mul(u, 40.0), s.mul(v, 2.0), 0.0), 8.0, 3, 0.5)
    h = s.add(s.mul(joint, -1.0), s.mul(sc_, 0.05))
    if rivets:
        rv = s.voronoi(s.comb(s.mul(u, 1.0 / pw * 6.0), s.mul(v, 1.0 / ph * 3.0), 0.0), 1.0)
        h = s.add(h, s.mul(s.smooth(rv, 0.12, 0.05), 0.4))
    rgh = s.add(rough, s.mul(s.sub(r, 0.5), 0.2))
    s.done(col, normal=s.bump(h, 0.35, 0.02), metal=metal, rough_sock=rgh)
    return s.m


def mat_floor(name, base, dark, cell=1.0, sub=2, var=0.10, rough=0.5, metal=0.35, grate=False, lines=None, wear=0.4):
    """Sol en grandes plaques (cell) subdivisées (sub) ; grate=True : caillebotis (lames fines) ;
    lines = (couleur, largeur) liserés peints le long des joints principaux."""
    s = NT(name)
    o = s.obj()
    u, v, _ = s.sep(s.uv())
    big_u = s.m_("FRACT", s.m_("DIVIDE", u, cell))
    big_v = s.m_("FRACT", s.m_("DIVIDE", v, cell))
    q = cell / sub
    fu = s.m_("FRACT", s.m_("DIVIDE", u, q))
    fv = s.m_("FRACT", s.m_("DIVIDE", v, q))
    iu = s.m_("FLOOR", s.m_("DIVIDE", u, q))
    iv = s.m_("FLOOR", s.m_("DIVIDE", v, q))
    r = s.white(s.comb(iu, iv, 7.7))
    g = 0.03 / q
    ju = s.sub(1.0, s.mul(s.smooth(fu, 0.0, g), s.smooth(fu, 1.0, 1.0 - g)))
    jv = s.sub(1.0, s.mul(s.smooth(fv, 0.0, g), s.smooth(fv, 1.0, 1.0 - g)))
    joint = s.m_("MAXIMUM", ju, jv)
    gb = 0.05 / cell
    bu = s.sub(1.0, s.mul(s.smooth(big_u, 0.0, gb), s.smooth(big_u, 1.0, 1.0 - gb)))
    bv = s.sub(1.0, s.mul(s.smooth(big_v, 0.0, gb), s.smooth(big_v, 1.0, 1.0 - gb)))
    bigj = s.m_("MAXIMUM", bu, bv)
    col = s.mix(s.mul(r, var * 2.0), base, tuple(min(1.0, x * 1.25) for x in base))
    # teinte par plaque (légèrement bleutée / chaude) et usure : salissures larges + fines
    r2 = s.white(s.comb(iu, iv, 3.3))
    col = s.mix(s.mul(s.smooth(r2, 0.6, 1.0), 0.5), col, (base[0] * 0.85, base[1] * 0.95, base[2] * 1.15))
    col = s.mix(s.mul(s.smooth(r2, 0.4, 0.0), 0.4), col, (base[0] * 1.12, base[1] * 1.02, base[2] * 0.9))
    n = s.noise(o, 1.6, 6, 0.62)
    n2 = s.noise(o, 7.0, 8, 0.7)
    col = s.mix(s.smooth(n, 0.5, 0.85, 0.0, wear), col, tuple(x * 0.55 for x in base))
    col = s.mix(s.smooth(n2, 0.55, 0.75, 0.0, wear * 0.6), col, tuple(x * 0.7 for x in base))
    # rayures (bruit étiré) plus claires
    scr = s.noise(s.comb(s.mul(u, 3.0), s.mul(v, 90.0), s.mul(r, 5.0)), 4.0, 2, 0.5)
    col = s.mix(s.smooth(scr, 0.72, 0.8, 0.0, 0.35), col, tuple(min(1.0, x * 1.5) for x in base))
    # rivets aux coins des sous-plaques
    du = s.m_("MINIMUM", fu, s.sub(1.0, fu))
    dv = s.m_("MINIMUM", fv, s.sub(1.0, fv))
    rv = s.m_("SQRT", s.add(s.mul(s.sub(du, 0.09), s.sub(du, 0.09)), s.mul(s.sub(dv, 0.09), s.sub(dv, 0.09))))
    bolt = s.smooth(rv, 0.035, 0.015)
    col = s.mix(s.mul(bolt, 0.8), col, tuple(x * 0.45 for x in base))
    # biseau clair en bord de plaque (lecture « relief » sous la lumière)
    edge = s.mul(s.sub(1.0, joint), s.m_("MAXIMUM", s.sub(1.0, s.smooth(fu, g, g * 3.0)), s.sub(1.0, s.smooth(fv, g, g * 3.0))))
    col = s.mix(s.mul(edge, 0.35), col, tuple(min(1.0, x * 1.6) for x in base))
    h = s.add(s.mul(joint, -0.6), s.mul(bolt, 0.25))
    if grate:
        sl = s.m_("FRACT", s.m_("DIVIDE", s.add(u, s.mul(iv, 0.0)), 0.1))
        slot = s.mul(s.smooth(sl, 0.25, 0.35), s.sub(1.0, s.smooth(sl, 0.65, 0.75)))
        col = s.mix(s.mul(slot, 0.8), col, (0.02, 0.025, 0.035))
        h = s.add(h, s.mul(slot, -0.5))
    col = s.mix(s.mul(joint, 0.7), col, dark)
    col = s.mix(s.mul(bigj, 0.9), col, tuple(x * 0.6 for x in dark))
    if lines:
        lc, lw = lines
        e = lw / cell
        lu = s.mul(s.smooth(big_u, gb, gb + 0.01), s.sub(1.0, s.smooth(big_u, gb + e, gb + e + 0.01)))
        col = s.mix(lu, col, lc)
    sc_ = s.noise(s.comb(s.mul(u, 60.0), s.mul(v, 3.0), 0.0), 6.0, 3, 0.5)
    h = s.add(h, s.mul(sc_, 0.04))
    s.done(col, normal=s.bump(h, 0.3, 0.02), metal=metal, rough_sock=s.add(rough, s.mul(n, 0.2)))
    return s.m


def mat_hazard(name, c1=(0.85, 0.62, 0.08), c2=(0.03, 0.03, 0.035), w=0.25):
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    t = s.m_("FRACT", s.m_("DIVIDE", s.add(u, v), w * 2))
    k = s.smooth(t, 0.48, 0.52)
    n = s.noise(s.obj(), 5.0, 4, 0.6)
    col = s.mix(k, c1, c2)
    col = s.mix(s.smooth(n, 0.55, 0.85, 0.0, 0.5), col, (0.1, 0.09, 0.07))
    return s.done(col, 0.55, s.bump(n, 0.1, 0.02), 0.2)


def mat_decal(name, c, alpha=0.85, scale=3.0):
    """Décalque au sol à bord irrégulier (UV 0..1 du quad) : brûlures, taches d'huile."""
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    du = s.sub(u, 0.5)
    dv = s.sub(v, 0.5)
    d = s.m_("SQRT", s.add(s.mul(du, du), s.mul(dv, dv)))
    n = s.noise(s.obj(), scale, 5, 0.6)
    m = s.sub(1.0, s.smooth(s.add(d, s.mul(n, 0.35)), 0.25, 0.5))
    s.done(c, 0.9)
    s.l(s.mul(m, alpha), s.b.inputs["Alpha"])
    return s.m


def mat_screen(name, c, strength=3.0):
    """Écran : lignes lumineuses (texte / courbes) sur fond sombre émissif."""
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    ln = s.m_("FRACT", s.mul(v, 22.0))
    rows = s.smooth(ln, 0.3, 0.5)
    w_ = s.white(s.comb(s.m_("FLOOR", s.mul(v, 22.0)), s.m_("FLOOR", s.mul(u, 6.0)), 1.0))
    on = s.m_("GREATER_THAN", w_, 0.45)
    k = s.add(0.25, s.mul(s.mul(rows, on), 0.9))
    s.done((0.02, 0.03, 0.04), 0.2)
    em = s.mix(k, (0.0, 0.0, 0.0), c)
    s.l(em, s.b.inputs["Emission Color"])
    s.b.inputs["Emission Strength"].default_value = strength
    return s.m


def mat_sign(name, c, strength=1.5):
    """Bandeau d'enseigne : caisson sombre, lettres lumineuses en blocs (lecture « enseigne »
    de loin, sans texte réel), quelques lettres éteintes."""
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    w_ = s.white(s.comb(s.m_("FLOOR", s.mul(u, 3.3)), s.m_("FLOOR", s.mul(v, 3.3)), 2.0))
    fu = s.m_("FRACT", s.mul(u, 3.3))
    fv = s.m_("FRACT", s.mul(v, 3.3))
    inner = s.mul(s.mul(s.smooth(fu, 0.12, 0.2), s.sub(1.0, s.smooth(fu, 0.8, 0.88))),
                  s.mul(s.smooth(fv, 0.12, 0.2), s.sub(1.0, s.smooth(fv, 0.8, 0.88))))
    on = s.mul(s.m_("GREATER_THAN", w_, 0.22), inner)
    s.done((0.03, 0.03, 0.035), 0.3)
    em = s.mix(s.add(0.12, s.mul(on, 0.88)), (0.0, 0.0, 0.0), c)
    s.l(em, s.b.inputs["Emission Color"])
    s.b.inputs["Emission Strength"].default_value = strength
    return s.m


def mat_glass(name, tint=(0.45, 0.7, 0.95), alpha=0.28):
    """Verre du dôme : transparent teinté + reflet (rapide, pas de réfraction)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    tr.inputs[0].default_value = (*tint, 1)
    gl = nt.nodes.new("ShaderNodeBsdfGlossy")
    gl.inputs[0].default_value = (0.75, 0.85, 1.0, 1)
    gl.inputs[1].default_value = 0.08
    fr = nt.nodes.new("ShaderNodeLayerWeight")
    fr.inputs[0].default_value = 0.35
    mx = nt.nodes.new("ShaderNodeMath")
    mx.operation = "ADD"
    mx.use_clamp = True
    mx.inputs[1].default_value = alpha
    nt.links.new(fr.outputs["Facing"], mx.inputs[0])
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(mx.outputs[0], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(gl.outputs[0], mix.inputs[2])
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(mix.outputs[0], o.inputs[0])
    MATS[name] = m
    return m


def mat_asphalt(name, base=(0.07, 0.075, 0.085)):
    """Bitume du parking / de la rue : grain, taches d'huile, flaques brillantes, fissures."""
    s = NT(name)
    o = s.obj()
    n = s.noise(o, 25.0, 6, 0.7)
    n2 = s.noise(o, 0.8, 4, 0.6)
    cr = s.voronoi(s.vmul(o, 0.7), 1.0, "Distance")
    col = s.mix(s.mul(n, 0.6), base, tuple(x * 1.6 for x in base))
    col = s.mix(s.smooth(n2, 0.55, 0.75, 0.0, 0.5), col, tuple(x * 0.6 for x in base))
    wet = s.smooth(n2, 0.62, 0.7)
    rough = s.sub(0.85, s.mul(wet, 0.75))
    h = s.add(s.mul(n, 0.3), s.mul(s.smooth(cr, 0.03, 0.0), -0.6))
    s.done(col, normal=s.bump(h, 0.3, 0.02), metal=0.0, rough_sock=rough)
    return s.m


def mat_tiles(name, c1, c2, size=1.0, rough=0.22, grout=(0.12, 0.11, 0.11)):
    """Carrelage poli des galeries (grands carreaux, damier léger, joints, reflets, saleté)."""
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    iu = s.m_("FLOOR", s.m_("DIVIDE", u, size))
    iv = s.m_("FLOOR", s.m_("DIVIDE", v, size))
    fu = s.m_("FRACT", s.m_("DIVIDE", u, size))
    fv = s.m_("FRACT", s.m_("DIVIDE", v, size))
    chk = s.m_("MODULO", s.add(iu, iv), 2.0)
    r = s.white(s.comb(iu, iv, 1.3))
    col = s.mix(chk, c1, c2)
    col = s.mix(s.mul(r, 0.25), col, tuple(x * 0.8 for x in c1))
    g = 0.035 / size
    ju = s.sub(1.0, s.mul(s.smooth(fu, 0.0, g), s.smooth(fu, 1.0, 1.0 - g)))
    jv = s.sub(1.0, s.mul(s.smooth(fv, 0.0, g), s.smooth(fv, 1.0, 1.0 - g)))
    joint = s.m_("MAXIMUM", ju, jv)
    n = s.noise(s.obj(), 1.2, 6, 0.65)
    col = s.mix(s.smooth(n, 0.5, 0.8, 0.0, 0.55), col, tuple(x * 0.45 for x in c1))
    col = s.mix(joint, col, grout)
    rg = s.add(rough, s.mul(s.smooth(n, 0.45, 0.8), 0.45))
    s.done(col, normal=s.bump(s.mul(joint, -1.0), 0.25, 0.02), metal=0.0, rough_sock=rg)
    return s.m


def mat_plaster(name, c, rough=0.75):
    s = NT(name)
    n = s.noise(s.obj(), 6.0, 5, 0.6)
    n2 = s.noise(s.obj(), 1.0, 3, 0.5)
    col = s.mix(s.mul(n, 0.4), c, tuple(x * 0.82 for x in c))
    u, v, _ = s.sep(s.uv())
    stain = s.smooth(s.add(n2, s.mul(v, -0.3)), 0.55, 0.8, 0.0, 0.45)
    col = s.mix(stain, col, tuple(x * 0.55 for x in c))
    return s.done(col, rough, s.bump(n, 0.08, 0.02), 0.0)


def mat_wood(name, c):
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    r, joint, grain = s.boards(u, v, 0.18, 1.6, 0.02)
    col = s.mix(s.mul(grain, 0.5), c, tuple(x * 0.7 for x in c))
    col = s.mix(s.mul(r, 0.3), col, tuple(x * 1.2 for x in c))
    col = s.mix(joint, col, tuple(x * 0.4 for x in c))
    return s.done(col, 0.5, s.bump(s.mul(joint, -1.0), 0.2, 0.02), 0.0)


def mat_water(name):
    """Eau du bassin, de nuit : bleu profond, lueur des projecteurs immergés (plus claire au
    centre des cellules d'ondes), vaguelettes brillantes."""
    s = NT(name)
    o = s.obj()
    n = s.noise(o, 6.0, 4, 0.5)
    w = s.voronoi(s.vmul(o, 3.0), 1.0)
    s.done((0.01, 0.05, 0.09), 0.04, s.bump(s.add(n, s.mul(w, 0.5)), 0.2, 0.02), 0.0)
    n2 = s.noise(o, 1.5, 3, 0.5)
    em = s.mix(s.add(s.mul(s.smooth(w, 0.1, 0.9), 0.35), s.mul(n2, 0.65)), (0.04, 0.38, 0.7), (0.015, 0.1, 0.26))
    s.l(em, s.b.inputs["Emission Color"])
    s.b.inputs["Emission Strength"].default_value = 0.6
    return s.m


def mat_lines(name, c=(0.85, 0.85, 0.8)):
    """Peinture au sol (marquage du parking) usée."""
    s = NT(name)
    n = s.noise(s.obj(), 12.0, 4, 0.6)
    col = s.mix(s.smooth(n, 0.55, 0.75, 0.0, 0.7), c, (0.12, 0.12, 0.13))
    return s.done(col, 0.7)


def mat_stars(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value = (0.01, 0.012, 0.025, 1)
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs[0], o.inputs[0])
    MATS[name] = m
    return m


NEON = {"white": (1.0, 0.92, 0.8), "warm": (1.0, 0.68, 0.36), "pink": (1.0, 0.1, 0.55), "red": (1.0, 0.06, 0.06),
        "cyan": (0.1, 0.85, 1.0), "green": (0.2, 1.0, 0.4), "violet": (0.55, 0.18, 1.0), "orange": (1.0, 0.45, 0.08)}
# maquette : néons surtout violets / roses / rouges, quelques cyan
SHOP_NEONS = ["pink", "violet", "red", "cyan", "pink", "violet", "orange", "green"]
NEON_E = float(os.environ.get("MALL_NEON", "3.2"))
CAR_COLORS = [(0.62, 0.08, 0.06), (0.75, 0.72, 0.62), (0.12, 0.25, 0.5), (0.15, 0.16, 0.17), (0.75, 0.55, 0.12)]


def mat_stone(name, c1, c2, size=2.0, rough=0.28, grout=(0.16, 0.14, 0.13), crack=0.6, grime=0.65, tint=None):
    """Dalles de pierre polie des galeries (maquette : gris-beige, usées) : dalle par dalle teinte
    et éclat variables, joints sombres, fissures (bords de Voronoï déformés), grandes salissures
    brun-noir, flaques / zones cirées plus brillantes (reflets des plafonniers et des néons)."""
    s = NT(name)
    o = s.obj()
    u, v, _ = s.sep(s.uv())
    iu = s.m_("FLOOR", s.m_("DIVIDE", u, size))
    iv = s.m_("FLOOR", s.m_("DIVIDE", v, size))
    fu = s.m_("FRACT", s.m_("DIVIDE", u, size))
    fv = s.m_("FRACT", s.m_("DIVIDE", v, size))
    r = s.white(s.comb(iu, iv, 1.3))
    r2 = s.white(s.comb(iu, iv, 5.9))
    col = s.mix(r, c1, c2)
    if tint:
        col = s.mix(s.smooth(r2, 0.75, 1.0), col, tint)
    # veinage fin de la pierre
    vein = s.noise(s.comb(s.mul(u, 1.5), s.mul(v, 0.6), s.mul(r, 11.0)), 3.5, 6, 0.65)
    col = s.mix(s.mul(s.smooth(vein, 0.48, 0.62), 0.25), col, tuple(min(1.0, x * 1.18) for x in c1))
    g = 0.03 / size
    ju = s.sub(1.0, s.mul(s.smooth(fu, 0.0, g), s.smooth(fu, 1.0, 1.0 - g)))
    jv = s.sub(1.0, s.mul(s.smooth(fv, 0.0, g), s.smooth(fv, 1.0, 1.0 - g)))
    joint = s.m_("MAXIMUM", ju, jv)
    # salissures : grandes taches + crasse fine, plus fortes près des joints
    n = s.noise(o, 0.55, 6, 0.68)
    n2 = s.noise(o, 3.2, 8, 0.72)
    dirt = s.add(s.smooth(n, 0.5, 0.78, 0.0, grime), s.smooth(n2, 0.58, 0.8, 0.0, grime * 0.45))
    col = s.mix(s.m_("MINIMUM", dirt, 0.9), col, (c2[0] * 0.38, c2[1] * 0.34, c2[2] * 0.32))
    # fissures
    wv = s.n("ShaderNodeVectorMath")
    wv.operation = "ADD"
    s.l(s.vmul(o, 0.42), wv.inputs[0])
    s.l(s.vmul(s.noise(o, 1.4, 3, 0.5, col=True), 0.35), wv.inputs[1])
    vo = s.n("ShaderNodeTexVoronoi")
    vo.feature = "DISTANCE_TO_EDGE"
    vo.inputs["Scale"].default_value = 1.0
    s.l(wv.outputs[0], vo.inputs["Vector"])
    cr = s.mul(s.smooth(vo.outputs["Distance"], 0.02, 0.0), s.smooth(s.noise(o, 0.7, 2, 0.5), 0.56, 0.7, 0.0, crack))
    col = s.mix(cr, col, (0.05, 0.045, 0.04))
    col = s.mix(s.mul(joint, 0.85), col, grout)
    # zones cirées / humides (plus lisses) et zones ternes
    wet = s.smooth(s.noise(o, 0.35, 3, 0.5), 0.58, 0.68)
    rg = s.add(s.sub(rough, s.mul(wet, rough * 0.7)), s.add(s.mul(dirt, 0.4), s.mul(r2, 0.1)))
    h = s.add(s.mul(joint, -1.0), s.mul(cr, -0.8))
    s.done(col, normal=s.bump(h, 0.3, 0.02), metal=0.0, rough_sock=rg)
    return s.m


def mat_carpet_arcade(name):
    """Moquette d'arcade (fond bleu nuit, confettis et zigzags fluo) usée."""
    s = NT(name)
    o = s.obj()
    u, v, _ = s.sep(s.uv())
    base = (0.03, 0.025, 0.08)
    w1 = s.voronoi(s.comb(s.mul(u, 3.0), s.mul(v, 3.0), 0.0), 1.0, "Color")
    w = s.voronoi(s.comb(s.mul(u, 3.0), s.mul(v, 3.0), 0.0), 1.0)
    dots = s.smooth(w, 0.16, 0.1)
    col = s.mix(dots, base, w1)
    col = s.mix(s.mul(dots, 0.5), col, (0.9, 0.15, 0.7))
    zz = s.m_("SINE", s.add(s.mul(u, 9.0), s.mul(s.m_("SINE", s.mul(v, 9.0)), 1.5)))
    band = s.smooth(s.m_("ABSOLUTE", zz), 0.08, 0.0)
    col = s.mix(s.mul(band, 0.8), col, (0.15, 0.75, 0.95))
    n = s.noise(o, 1.0, 5, 0.6)
    col = s.mix(s.smooth(n, 0.5, 0.8, 0.0, 0.6), col, (0.02, 0.02, 0.03))
    return s.done(col, 0.95)


def mat_roof_gravel(name, c=(0.36, 0.33, 0.31)):
    """Toit plat en gravillons (grain fin, coulures sombres, mousses)."""
    s = NT(name)
    o = s.obj()
    g = s.noise(o, 60.0, 3, 0.6)
    n = s.noise(o, 1.2, 5, 0.6)
    col = s.mix(s.mul(g, 0.8), tuple(x * 0.7 for x in c), tuple(min(1.0, x * 1.3) for x in c))
    col = s.mix(s.smooth(n, 0.5, 0.75, 0.0, 0.5), col, (0.08, 0.075, 0.07))
    return s.done(col, 0.95, s.bump(g, 0.25, 0.02), 0.0)


def build_materials():
    mat_stone("tiles_gal", (0.5, 0.45, 0.41), (0.41, 0.37, 0.34), 2.0, 0.3, (0.13, 0.115, 0.11),
              tint=(0.44, 0.42, 0.42))
    mat_stone("tiles_shop", (0.46, 0.43, 0.41), (0.4, 0.37, 0.36), 1.0, 0.4, (0.2, 0.18, 0.17), crack=0.35, grime=0.5)
    mat_stone("tiles_dark", (0.17, 0.165, 0.19), (0.13, 0.125, 0.15), 1.0, 0.22, (0.06, 0.06, 0.07), crack=0.3, grime=0.4)
    mat_stone("tiles_white", (0.6, 0.6, 0.58), (0.54, 0.54, 0.53), 1.0, 0.22, (0.3, 0.29, 0.28), crack=0.3, grime=0.45)
    mat_wood("wood_floor", (0.3, 0.19, 0.11))
    mat_wood("wood_light", (0.5, 0.34, 0.2))
    mat_floor("concrete", (0.3, 0.29, 0.29), (0.12, 0.12, 0.12), cell=2.0, sub=1, var=0.2, rough=0.8, metal=0.0, wear=0.6)
    mat_simple("carpet_red", (0.3, 0.05, 0.07), 0.95, 0.0, 0.3, 30.0, c2=(0.16, 0.02, 0.04))
    mat_carpet_arcade("carpet_blue")
    mat_asphalt("asphalt", (0.13, 0.13, 0.15))
    mat_asphalt("street", (0.05, 0.055, 0.065))
    mat_simple("sidewalk", (0.22, 0.21, 0.21), 0.85, 0.0, 0.3, 3.0)
    mat_lines("paint_white")
    mat_lines("paint_yellow", (0.85, 0.65, 0.12))
    mat_plaster("plaster", (0.5, 0.42, 0.37))
    mat_plaster("plaster_pink", (0.5, 0.36, 0.36))
    mat_plaster("plaster_dark", (0.24, 0.21, 0.22))
    mat_panels("ext_wall", (0.4, 0.33, 0.3), (0.17, 0.13, 0.12), pw=2.0, ph=0.6, metal=0.0, rough=0.8, var=0.08)
    mat_panels("wall_top", (0.6, 0.57, 0.54), (0.42, 0.4, 0.38), pw=2.0, ph=2.0, seam=0.012, metal=0.0, rough=0.7, var=0.05, grime=0.35)
    mat_roof_gravel("roof_gravel")
    mat_panels("roof_metal", (0.38, 0.38, 0.4), (0.15, 0.15, 0.16), pw=0.3, ph=4.0, metal=0.5, rough=0.4, var=0.05)
    mat_hazard("hazard")
    mat_simple("metal", (0.6, 0.6, 0.62), 0.3, 0.8, 0.12)
    mat_simple("metal_dark", (0.1, 0.1, 0.11), 0.4, 0.6, 0.2)
    mat_simple("metal_mid", (0.32, 0.32, 0.34), 0.4, 0.6, 0.2)
    mat_simple("chrome", (0.8, 0.8, 0.82), 0.12, 1.0, 0.05)
    mat_simple("rubber", (0.03, 0.03, 0.035), 0.8, 0.0, 0.1)
    mat_simple("white", (0.78, 0.76, 0.72), 0.5, 0.0, 0.08)
    mat_simple("cream", (0.75, 0.66, 0.52), 0.6, 0.0, 0.1)
    mat_simple("plant", (0.1, 0.32, 0.1), 0.8, 0.0, 0.35, 8.0, c2=(0.04, 0.16, 0.05))
    mat_simple("plant_dark", (0.05, 0.18, 0.06), 0.85, 0.0, 0.35, 8.0)
    mat_simple("soil", (0.1, 0.07, 0.05), 0.95)
    mat_simple("trunk", (0.2, 0.13, 0.08), 0.9)
    mat_simple("planter", (0.42, 0.36, 0.33), 0.8, 0.0, 0.15)
    mat_simple("cardboard", (0.55, 0.4, 0.22), 0.9, 0.0, 0.25)
    mat_simple("fabric_a", (0.5, 0.12, 0.2), 0.9, 0.0, 0.3, 6.0)
    mat_simple("fabric_b", (0.14, 0.3, 0.5), 0.9, 0.0, 0.3, 6.0)
    mat_simple("fabric_c", (0.6, 0.55, 0.4), 0.9, 0.0, 0.3, 6.0)
    mat_simple("toy_a", (0.9, 0.2, 0.15), 0.5)
    mat_simple("toy_b", (0.2, 0.5, 0.95), 0.5)
    mat_simple("toy_c", (0.95, 0.8, 0.15), 0.5)
    mat_simple("debris", (0.3, 0.28, 0.27), 0.9, 0.0, 0.4)
    mat_simple("paper", (0.72, 0.7, 0.64), 0.8, 0.0, 0.15, 12.0)
    mat_wood("crate", (0.52, 0.36, 0.16))
    mat_hazard("awning_a", (0.75, 0.12, 0.2), (0.85, 0.8, 0.72), 0.12)
    mat_hazard("awning_b", (0.2, 0.45, 0.6), (0.85, 0.8, 0.72), 0.12)
    mat_simple("ceiling_tile", (0.55, 0.53, 0.5), 0.9, 0.0, 0.3, 9.0)
    mat_simple("shard", (0.6, 0.75, 0.8), 0.05, 0.3, 0.1)
    mat_simple("stone", (0.42, 0.38, 0.35), 0.6, 0.0, 0.25, 5.0, c2=(0.3, 0.27, 0.25))
    mat_simple("stone_dark", (0.2, 0.19, 0.2), 0.5, 0.0, 0.25, 5.0)
    mat_simple("bronze", (0.45, 0.3, 0.14), 0.35, 0.9, 0.2, 6.0, c2=(0.18, 0.22, 0.14))
    mat_simple("flower_a", (0.85, 0.2, 0.45), 0.7)
    mat_simple("flower_b", (0.95, 0.75, 0.2), 0.7)
    mat_simple("leaf", (0.12, 0.36, 0.1), 0.7, 0.0, 0.4, 10.0, c2=(0.05, 0.2, 0.05))
    mat_simple("leaf_dry", (0.35, 0.32, 0.12), 0.8, 0.0, 0.4, 10.0)
    mat_simple("doorway", (0.02, 0.02, 0.025), 0.9, var=0.1)
    mat_simple("shutter", (0.42, 0.42, 0.44), 0.5, 0.6, 0.1)
    for i, c in enumerate(CAR_COLORS):
        mat_simple("car_%d" % i, c, 0.25, 0.6, 0.1)
    mat_glass("glass", (0.55, 0.7, 0.75), 0.18)
    mat_glass("glass_dark", (0.2, 0.3, 0.35), 0.35)
    mat_water("water")
    mat_emit("spray", (0.5, 0.8, 1.0), 0.6)
    mat_decal("puddle", (0.1, 0.12, 0.17), 0.45)
    mat_decal("stain", (0.12, 0.08, 0.06), 0.35)
    mat_stars("_sky")
    for k, c in NEON.items():
        # néons : couleur pure et intensité modérée (AgX blanchit les fortes intensités : le
        # bandeau doit rester rose / violet / cyan, la lueur vient du « bloom » de grade())
        mat_emit("neon_" + k, c, NEON_E)
        mat_emit("lamp_" + k, c, 2.2)
    for k, c in NEON.items():
        mat_sign("sign_" + k, c, 1.6)
    mat_screen("screen_cyan", (0.2, 0.8, 1.0), 2.5)
    mat_screen("screen_pink", (1.0, 0.3, 0.7), 2.5)
    mat_screen("screen_green", (0.25, 1.0, 0.45), 2.2)
    mat_screen("skylight", (1.0, 0.7, 0.4), 0.8)
    mat_emit("lamp_dim", (1.0, 0.95, 0.85), 1.0)
    mat_emit("window_warm", (1.0, 0.7, 0.4), 1.1)
    mat_emit("headlight", (1.0, 0.95, 0.8), 4.0)
    mat_emit("taillight", (1.0, 0.1, 0.05), 3.0)
class _Face:
    __slots__ = ("mb", "i")

    def __init__(self, mb, i):
        self.mb, self.i = mb, i

    @property
    def material_index(self):
        return self.mb.F[self.i][1]

    @material_index.setter
    def material_index(self, v):
        self.mb.F[self.i][1] = v


class _BM:
    """Compatibilité : mb.bm.verts.new(co) → index ; mb.bm.faces.new(idx) → face."""

    def __init__(self, mb):
        self.mb = mb
        self.verts = self
        self.faces = _Faces(mb)

    def new(self, co):
        self.mb.V.append(tuple(co))
        return len(self.mb.V) - 1

    def free(self):
        pass


class _Faces:
    def __init__(self, mb):
        self.mb = mb

    def new(self, idx):
        self.mb.F.append([tuple(idx), 0])
        return _Face(self.mb, len(self.mb.F) - 1)

    def __len__(self):
        return len(self.mb.F)


_ICO = {}


def _ico(sub):
    if sub not in _ICO:
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
        vs = [tuple(v.co) for v in bm.verts]
        fs = [tuple(v.index for v in f.verts) for f in bm.faces]
        bm.free()
        _ICO[sub] = (vs, fs)
    return _ICO[sub]


class MB:
    """Accumulateur de maillage (listes Python → from_pydata en une fois : coût linéaire),
    index de matériau par face, UV « boîte » en unités monde (u horizontal, v vertical sur les
    murs ; x, y au sol) sauf UV explicites."""

    def __init__(self):
        self.V = []
        self.F = []
        self.mats = []
        self.uvf = {}
        self.bm = _BM(self)

    def mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def v(self, co):
        self.V.append(tuple(co))
        return len(self.V) - 1

    def _add(self, verts, faces, mat):
        base = len(self.V)
        self.V.extend(verts)
        m = self.mi(mat)
        for f in faces:
            self.F.append([tuple(base + i for i in f), m])
        return base

    def offset(self, dx, dy, dz, start=0):
        for i in range(start, len(self.V)):
            x, y, z = self.V[i]
            self.V[i] = (x + dx, y + dy, z + dz)

    def box(self, x0, y0, z0, x1, y1, z1, mat, rot=0.0, piv=None, tilt=None):
        hx, hy, hz = (x1 - x0) / 2, (y1 - y0) / 2, (z1 - z0) / 2
        cx, cy, cz = (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
        loc = [Vector((sx * hx, sy * hy, sz * hz)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        if tilt:
            R = Matrix.Rotation(tilt[1], 3, tilt[0])
            loc = [R @ p for p in loc]
        if rot:
            p = piv if piv else (cx, cy)
            R = Matrix.Rotation(rot, 3, "Z")
            off = Vector((cx - p[0], cy - p[1], cz))
            loc = [R @ (q + off) + Vector((p[0], p[1], 0)) for q in loc]
        else:
            loc = [q + Vector((cx, cy, cz)) for q in loc]
        # index : (sx, sy, sz) → 4*ix + 2*iy + iz
        faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        self._add([tuple(q) for q in loc], faces, mat)

    def _tube(self, M, t, r1, r2, depth, seg, cap, mat):
        verts = []
        for (z, r) in ((-depth / 2, r1), (depth / 2, r2)):
            for j in range(seg):
                a = j / seg * math.tau
                verts.append(tuple(M @ Vector((math.cos(a) * r, math.sin(a) * r, z)) + t))
        faces = [(j, (j + 1) % seg, seg + (j + 1) % seg, seg + j) for j in range(seg)]
        if cap:
            faces.append(tuple(reversed(range(seg))))
            faces.append(tuple(range(seg, 2 * seg)))
        self._add(verts, faces, mat)

    def cyl(self, cx, cy, z0, z1, r, mat, seg=12, r2=None, axis="Z", rot=0.0, cap=True):
        """axis Z : de z0 à z1 au point (cx, cy). axis X/Y : cylindre couché centré (cx, cy, z0) de longueur z1."""
        M = Matrix.Identity(3)
        if axis == "X":
            M = Matrix.Rotation(math.pi / 2, 3, "Y")
        elif axis == "Y":
            M = Matrix.Rotation(math.pi / 2, 3, "X")
        if rot:
            M = Matrix.Rotation(rot, 3, "Z") @ M
        depth = abs(z1 - z0) if axis == "Z" else z1
        t = Vector((cx, cy, (z0 + z1) / 2 if axis == "Z" else z0))
        self._tube(M, t, r, r if r2 is None else r2, depth, seg, cap, mat)

    def seg(self, p0, p1, r, mat, sides=6, r2=None):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        Lg = d.length
        if Lg < 1e-5:
            return
        M = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
        self._tube(M, (p0 + p1) / 2, r, r if r2 is None else r2, Lg, sides, True, mat)

    def sphere(self, cx, cy, cz, r, mat, sub=2, sx=1.0, sy=1.0, sz=1.0, jitter=0.0, nscale=0.0, rng=None):
        vs0, fs = _ico(sub)
        off = Vector((rng.uniform(0, 100), rng.uniform(0, 100), 0)) if rng else Vector((0, 0, 0))
        out = []
        for (x, y, z) in vs0:
            k = 1.0
            if jitter and rng:
                k += rng.uniform(-jitter, jitter)
            if nscale:
                k += mnoise.noise(Vector((x, y, z)) * nscale + off) * 0.35
            out.append((x * r * k * sx + cx, y * r * k * sy + cy, z * r * k * sz + cz))
        self._add(out, fs, mat)

    def poly(self, pts, mat, uvs=None):
        base = len(self.V)
        self.V.extend(tuple(p) for p in pts)
        self.F.append([tuple(range(base, base + len(pts))), self.mi(mat)])
        if uvs:
            self.uvf[len(self.F) - 1] = uvs

    def quad_uv(self, a, b, c, d, mat, along, slope_len, u0=0.0):
        """Quad de toit a-b (bas, le long du faîtage) c-d (haut) : u = le long, v = pente."""
        La = (Vector(b) - Vector(a)).length
        return self.poly([a, b, c, d], mat, [(u0, 0), (u0 + La, 0), (u0 + La, slope_len), (u0, slope_len)])

    def to_object(self, name, collection, smooth=False, recalc=True):
        import numpy as np
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.V, [], [f[0] for f in self.F])
        me.polygons.foreach_set("material_index", [f[1] for f in self.F])
        me.update()
        if recalc and len(self.F):
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.to_mesh(me)
            bm.free()
        nl = len(me.loops)
        if nl:
            uvl = me.uv_layers.new(name="UVMap")
            co = np.zeros(len(me.vertices) * 3)
            me.vertices.foreach_get("co", co)
            co = co.reshape(-1, 3)
            lv = np.zeros(nl, dtype=np.int64)
            me.loops.foreach_get("vertex_index", lv)
            np_ = len(me.polygons)
            pn = np.zeros(np_ * 3)
            me.polygons.foreach_get("normal", pn)
            pn = np.abs(pn.reshape(-1, 3))
            ls = np.zeros(np_, dtype=np.int64)
            me.polygons.foreach_get("loop_start", ls)
            lt = np.zeros(np_, dtype=np.int64)
            me.polygons.foreach_get("loop_total", lt)
            lp = np.repeat(np.arange(np_), lt)
            n = pn[lp]
            c = co[lv]
            top = (n[:, 2] >= n[:, 0]) & (n[:, 2] >= n[:, 1])
            sidex = (~top) & (n[:, 0] >= n[:, 1])
            u = np.where(top, c[:, 0], np.where(sidex, c[:, 1], c[:, 0]))
            v = np.where(top, c[:, 1], c[:, 2])
            uv = np.stack([u, v], 1)
            # UV explicites (index de face conservé par from_pydata)
            for fi, uvs in self.uvf.items():
                s0 = ls[fi]
                for k, q in enumerate(uvs):
                    uv[s0 + k] = q
            uvl.data.foreach_set("uv", uv.reshape(-1))
        for m in self.mats:
            me.materials.append(MATS[m])
        if smooth:
            me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
        ob = bpy.data.objects.new(name, me)
        coll(collection).objects.link(ob)
        return ob


def fit_xy(mb, start, x0, x1, y0, y1, margin=0.04, zlo=0.12, zcut=1.0):
    """Ramène l'emprise AU SOL (sommets zlo < z < zcut) des sommets ajoutés depuis `start` dans le
    rectangle [x0,x1]×[y0,y1] (Blender) : échelle uniforme en XY (≤ 1) + translation. Garantit que
    l'objet rendu ne déborde pas de ses cases bloquantes (cohérence rendu ↔ collisions)."""
    pts = [mb.V[i] for i in range(start, len(mb.V)) if zlo < mb.V[i][2] < zcut]
    if not pts:
        return
    bx0, bx1 = min(p[0] for p in pts), max(p[0] for p in pts)
    by0, by1 = min(p[1] for p in pts), max(p[1] for p in pts)
    ax0, ax1, ay0, ay1 = min(x0, x1) + margin, max(x0, x1) - margin, min(y0, y1) + margin, max(y0, y1) - margin
    k = min(1.0, (ax1 - ax0) / max(bx1 - bx0, 1e-6), (ay1 - ay0) / max(by1 - by0, 1e-6))
    cx, cy = (bx0 + bx1) / 2, (by0 + by1) / 2
    hx, hy = (bx1 - bx0) / 2 * k, (by1 - by0) / 2 * k
    tx = min(max(cx, ax0 + hx), ax1 - hx)
    ty = min(max(cy, ay0 + hy), ay1 - hy)
    for i in range(start, len(mb.V)):
        x, y, z = mb.V[i]
        mb.V[i] = (tx + (x - cx) * k, ty + (y - cy) * k, z)


def cells_fit(mb, start, rect, margin=0.04, zlo=0.12, zcut=1.0):
    """fit_xy sur un rectangle de cases [x, y, w, h] (y = rangée du haut)."""
    x, y, w, h = rect
    fit_xy(mb, start, x, x + w, Y(y + h), Y(y), margin, zlo, zcut)



# ======================================================================= analyse du layout
ROOMS = LAYOUT.get("rooms", [])
ROOM_BY_ID = {r["id"]: r for r in ROOMS}
MODS = C.get("modules", [])
MOD_BY_ROOM = {m["room"]: m for m in MODS}
BLD = {b["id"]: b for b in LAYOUT.get("buildings", [])}
DOOR_CELLS = {tuple(d["cell"]): d for d in LAYOUT.get("doors", [])}
STAIRS = {tuple(s["cell"]): s for s in LAYOUT.get("stairs", [])}
EXTRACT = set(tuple(c) for c in LAYOUT.get("extraction", []))
PARK = C.get("parking", [1, 106, 64, 16])
HALLR = C.get("hall", [24, 97, 18, 9])
ATR = C.get("atrium", [22, 41, 22, 26])

CELL_ROOM = {}
_area = {}
for r in ROOMS:
    x, y, w, h = r["rect"]
    a = w * h
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if a < _area.get((xx, yy), 1 << 30):
                _area[(xx, yy)] = a
                CELL_ROOM[(xx, yy)] = r["id"]


def role_of(rid):
    r = ROOM_BY_ID.get(rid)
    return r["tags"][0] if r and r.get("tags") else "gallery"


def mod_of(rid):
    return MOD_BY_ROOM.get(rid)


# Boutique (module) de chaque case de son emprise (murs compris), bâtiment (boutique à toit)
CELL_MOD = {}
for m in MODS:
    x, y, w, h = m["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            CELL_MOD.setdefault((xx, yy), m)
CELL_BLD = {}
for b in LAYOUT.get("buildings", []):
    x, y, w, h = b["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            CELL_BLD.setdefault((xx, yy), b["id"])
ESC_CELLS = set()
for e in C.get("escalators", []):
    x, y, w, h = e["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            ESC_CELLS.add((xx, yy))
TREE_CELLS = set()
for t in C.get("trees", []):
    x, y, w, h = t
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            TREE_CELLS.add((xx, yy))
PLANTER_CELLS = set()
ax, ay, aw, ah = ATR
for yy in range(ay, ay + ah):
    for xx in range(ax, ax + aw):
        if (xx in (ax, ax + aw - 1) or yy in (ay, ay + ah - 1)) and tile(xx, yy) == 3:
            PLANTER_CELLS.add((xx, yy))
GAME_CELLS = set()
for key in ("container_spawns", "hiding_spot_spawns", "prop_spawns"):
    for sp in LAYOUT.get(key, []):
        sx, sy = sp.get("size", [1, 1])
        x0 = sp["cell"][0] - (sx - 1) // 2
        for yy in range(sp["cell"][1] - sy + 1, sp["cell"][1] + 1):
            for xx in range(x0, x0 + sx):
                GAME_CELLS.add((xx, yy))
for d in DOOR_CELLS:
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            GAME_CELLS.add((d[0] + dx, d[1] + dy))


def neon_of(m):
    if m is None:
        return "warm"
    if m["role"] == "shop_cafe":
        return "pink"
    if m["role"] == "arcade":
        return "violet"
    if m["role"] == "shop_jewelry":
        return "warm"
    return SHOP_NEONS[(int(m.get("neon", 0)) + m["room"]) % len(SHOP_NEONS)]


def in_parking(x, y):
    px, py, pw, ph = PARK
    return px <= x < px + pw and py <= y < py + ph


H_SHOP = 1.35        # cloisons entre boutiques / murs intérieurs (vus en coupe)
H_EXT = 1.6          # murs extérieurs du bâtiment
H_ROOF = 1.8         # boutiques à plafond (toit)
H_CUT = 0.7          # haut du mur sud masqué en passe int
H_FRONT = 0.4        # allège des vitrines
H_DOOR = 1.0


def floor_mat(rid, cell):
    role = role_of(rid)
    m = mod_of(rid)
    if in_parking(*cell):
        return "asphalt"
    if role in ("gallery", "atrium", "entrance"):
        return "tiles_gal"
    if m is None:
        return "tiles_gal"
    a = m.get("arch", "")
    if role in ("service", "stockroom"):
        return "concrete"
    if role == "arcade":
        return "carpet_blue"
    if role == "cinema_lobby":
        return "carpet_red"
    if a in ("books", "cafe", "shoes", "jewelry"):
        return "wood_floor"
    if a in ("pharmacy", "perfume", "supermarket"):
        return "tiles_white"
    if a in ("electronics", "phones", "toys"):
        return "tiles_dark"
    return "tiles_shop"


# ======================================================================= sol (et rues hors jeu)
def build_floors():
    mbs = {}
    for y in range(H):
        for x in range(W):
            t = tile(x, y)
            if t not in (1, 2, 4, 5, 6):
                continue
            rid = CELL_ROOM.get((x, y), -1)
            mat = floor_mat(rid, (x, y))
            bid = CELL_BLD.get((x, y), -1)
            key = ("floor_%d" % bid) if bid >= 0 else "ground"
            mb = mbs.setdefault(key, MB())
            mb.poly([(x, Y(y + 1), 0.0), (x + 1, Y(y + 1), 0.0), (x + 1, Y(y), 0.0), (x, Y(y), 0.0)], mat,
                    [(x, Y(y + 1)), (x + 1, Y(y + 1)), (x + 1, Y(y)), (x, Y(y))])
    for key, mb in mbs.items():
        mb.to_object(key, "world")
    # rues et trottoirs autour du bâtiment (hors jeu), sous le niveau du sol
    st = MB()
    m = 12
    st.poly([(-m, Y(H + m), -0.05), (W + m, Y(H + m), -0.05), (W + m, Y(-m), -0.05), (-m, Y(-m), -0.05)], "street",
            [(-m, Y(H + m)), (W + m, Y(H + m)), (W + m, Y(-m)), (-m, Y(-m))])
    # trottoir autour du bâtiment
    st.box(-1.2, Y(PARK[1]), -0.05, W + 1.2, Y(0.0), -0.006, "sidewalk")
    # lignes de la rue (pointillés jaunes)
    for xx in range(-10, W + 10, 3):
        st.box(xx, Y(-3.05), -0.04, xx + 1.4, Y(-2.95), -0.03, "paint_yellow")
    for yy in range(-8, H + 8, 3):
        for xx in (-3.0, W + 3.0):
            st.box(xx - 0.05, Y(yy + 1.4), -0.04, xx + 0.05, Y(yy), -0.03, "paint_yellow")
    st.to_object("_street", "world")
    # marquages du parking : places, flèches, grand « P », bordures
    mk = MB()
    px, py, pw, ph = PARK
    lanes = [(px + 1, 20.5), (23.5, 42.5), (45.5, px + pw - 1)]
    for (x0, x1) in lanes:
        for row_y in (py + 3.0, py + ph - 3.5):
            xx = x0
            while xx < x1 - 0.5:
                mk.box(xx - 0.04, Y(row_y + 2.6), 0.0, xx + 0.04, Y(row_y), 0.006, "paint_white")
                xx += 2.5
            mk.box(x0, Y(row_y + 0.04), 0.0, x1, Y(row_y - 0.04), 0.006, "paint_white") if row_y > py + 5 else None
    for xx in (21.0, 45.0):
        for yy in range(py + 2, py + ph - 1, 2):
            mk.box(xx + 0.95, Y(yy + 1.0), 0.0, xx + 1.05, Y(yy), 0.006, "paint_yellow")
    # grand P dans un carré
    cx, cy = 33.0, py + ph - 6.0
    mk.box(cx - 2.0, Y(cy + 2.0), 0.0, cx + 2.0, Y(cy + 1.85), 0.007, "paint_white")
    mk.box(cx - 2.0, Y(cy - 1.85), 0.0, cx + 2.0, Y(cy - 2.0), 0.007, "paint_white")
    mk.box(cx - 2.0, Y(cy + 2.0), 0.0, cx - 1.85, Y(cy - 2.0), 0.007, "paint_white")
    mk.box(cx + 1.85, Y(cy + 2.0), 0.0, cx + 2.0, Y(cy - 2.0), 0.007, "paint_white")
    P_SIGNS.append((cx, Y(cy), 3.6))
    # passage piéton devant l'entrée
    for k in range(9):
        xx = 28.2 + k * 1.05
        mk.box(xx, Y(py + 2.4), 0.0, xx + 0.55, Y(py + 0.4), 0.006, "paint_white")
    # cadre doré du tapis d'entrée et sortie d'extraction
    for (ex, ey) in EXTRACT:
        mk.box(ex + 0.06, Y(ey + 0.94), 0.0, ex + 0.94, Y(ey + 0.06), 0.01, "hazard")
    for (sx, sy), stt in STAIRS.items():
        mk.box(sx - 1.0, Y(sy + 1.0), 0.0, sx + 2.0, Y(sy), 0.012, "metal_mid")
        mk.box(sx - 0.9, Y(sy + 0.95), 0.0, sx + 1.9, Y(sy + 0.85), 0.016, "paint_yellow")
    mk.to_object("ground_marks", "world")
    for i, (px_, py_, sz) in enumerate(P_SIGNS):
        ob = sign_text("_psign%d" % i, "P", px_, py_, 0.0, sz, "paint_white")
        ob.scale = (1.0, 1.0, 0.12)


P_SIGNS = []


# ======================================================================= murs, vitrines, portes
SIDES = (("S", 0, 1), ("N", 0, -1), ("E", 1, 0), ("W", -1, 0))
DOOR_GLOWS = []
FRONT_GLOWS = []


def face(mb, x, y, side, z0, z1, mat):
    X0, X1 = x, x + 1
    YN, YS = Y(y), Y(y + 1)
    if side == "S":
        pts = [(X0, YS, z0), (X1, YS, z0), (X1, YS, z1), (X0, YS, z1)]
        u0, u1 = X0, X1
    elif side == "N":
        pts = [(X1, YN, z0), (X0, YN, z0), (X0, YN, z1), (X1, YN, z1)]
        u0, u1 = -X1, -X0
    elif side == "E":
        pts = [(X1, YS, z0), (X1, YN, z0), (X1, YN, z1), (X1, YS, z1)]
        u0, u1 = YS, YN
    else:
        pts = [(X0, YN, z0), (X0, YS, z0), (X0, YS, z1), (X0, YN, z1)]
        u0, u1 = -YN, -YS
    mb.poly(pts, mat, [(u0, z0), (u1, z0), (u1, z1), (u0, z1)])


def is_ext(x, y):
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if tile(x + dx, y + dy) == 0 or in_parking(x + dx, y + dy):
                return True
    return False


def wall_kind(x, y):
    """'ext' (mur extérieur), 'front' (vitrine : boutique d'un côté, galerie de l'autre), 'roof'
    (boutique à plafond), 'shop' (cloison), 'planter', 'esc', 'tree'."""
    if (x, y) in ESC_CELLS:
        return "esc"
    if (x, y) in PLANTER_CELLS:
        return "planter"
    if (x, y) in TREE_CELLS:
        return "tree"
    if is_ext(x, y):
        return "ext"
    gal = False
    shop = False
    for sd, dx, dy in SIDES:
        t = tile(x + dx, y + dy)
        if t in (1, 5, 6) or (t == 4 and False):
            gal = True
        if t == 2:
            shop = True
    b = CELL_BLD.get((x, y))
    if b is not None:
        return "roof"
    if gal and shop:
        return "front"
    return "shop"


def wall_h(x, y):
    k = wall_kind(x, y)
    return {"ext": H_EXT, "roof": H_ROOF, "front": H_SHOP, "shop": H_SHOP, "planter": 0.45, "esc": 0.0, "tree": 0.35}[k]


def build_walls():
    mbs = {}
    glass = MB()
    neon = MB()
    fac = MB()

    def target(x, y, upper=False):
        b = CELL_BLD.get((x, y))
        if b is None:
            return mbs.setdefault("hullwalls", MB())
        return mbs.setdefault(("front_%d" if upper else "walls_%d") % b, MB())

    for y in range(H):
        for x in range(W):
            if tile(x, y) != 3:
                continue
            k = wall_kind(x, y)
            if k in ("esc", "planter", "tree"):
                continue
            h = wall_h(x, y)
            b = CELL_BLD.get((x, y))
            south_row = b is not None and y == BLD[b]["rect"][1] + BLD[b]["rect"][3] - 1
            m = CELL_MOD.get((x, y))
            wmat = "ext_wall" if k == "ext" else ("plaster_pink" if (m and m["room"] % 3 == 0) else "plaster")
            # vitrine : allège + vitrage + neon au-dessus, côté galerie
            if k == "front":
                # devanture : allège métallique à chant chromé, vitrage, bandeau d'enseigne
                # (panneau lumineux de la couleur du néon pour une boutique sur deux)
                tg = target(x, y)
                gs = [sd for sd, dx, dy in SIDES if tile(x + dx, y + dy) in (1, 5, 6)]
                vert = bool(gs) and all(sd in ("E", "W") for sd in gs)

                def strip(mb_, z0, z1, ins, mat, e0=0.0, e1=1.0):
                    if vert:   # mur nord-sud : bande le long de Y
                        mb_.box(x + ins, Y(y + e1), z0, x + 1 - ins, Y(y + e0), z1, mat)
                    else:
                        mb_.box(x + e0, Y(y + 1) + ins, z0, x + e1, Y(y) - ins, z1, mat)
                strip(tg, 0.0, H_FRONT - 0.05, 0.18, "metal_mid")
                strip(tg, H_FRONT - 0.05, H_FRONT, 0.16, "chrome")
                strip(glass, H_FRONT, h - 0.15, 0.42, "glass", 0.02, 0.98)
                signm = ("sign_" + neon_of(m)) if (m and m["room"] % 2 == 0) else "metal_dark"
                strip(tg, h - 0.15, h, 0.3, signm)
                if (x * 5 + y) % 4 == 0:
                    strip(tg, H_FRONT, h - 0.15, 0.32, "metal_dark", 0.0, 0.06)
                for (px_, py_) in ((x, y), (x + 0.92, y)):
                    pass
                for sd, dx, dy in SIDES:
                    if tile(x + dx, y + dy) in (1, 5, 6):
                        col = neon_of(m)
                        if (x + y) % 4 == 0:
                            FRONT_GLOWS.append((x + 0.5 + dx * 0.9, Y(y + 0.5 + dy * 0.9), col))
                        if sd == "S":
                            neon.box(x, Y(y + 1) - 0.03, h - 0.12, x + 1, Y(y + 1), h - 0.05, "neon_" + col)
                        elif sd == "N":
                            neon.box(x, Y(y), h - 0.12, x + 1, Y(y) + 0.03, h - 0.05, "neon_" + col)
                        elif sd == "E":
                            neon.box(x + 1, Y(y + 1), h - 0.12, x + 1.03, Y(y), h - 0.05, "neon_" + col)
                        else:
                            neon.box(x - 0.03, Y(y + 1), h - 0.12, x, Y(y), h - 0.05, "neon_" + col)
                continue
            for side, dx, dy in SIDES:
                nx, ny = x + dx, y + dy
                nt_ = tile(nx, ny)
                if nt_ == 3 and wall_kind(nx, ny) not in ("esc", "planter", "tree", "front"):
                    nh = wall_h(nx, ny)
                    if nh >= h - 1e-3:
                        continue
                    z0 = nh
                elif nt_ == 0:
                    z0 = -0.05
                else:
                    z0 = 0.0
                mat = "ext_wall" if (nt_ == 0 or in_parking(nx, ny)) else wmat
                if side == "S" and in_parking(nx, ny) and nt_ != 3:
                    # façade sur le parking : vitrines éclairées, bandeau néon, auvent
                    fy = Y(y + 1)
                    if (x * 7 + 3) % 5 < 3:
                        fac.box(x + 0.08, fy - 0.025, 0.25, x + 0.92, fy, 1.15, "window_warm" if (x * 13) % 7 < 5 else "glass_dark")
                    fac.box(x, fy - 0.04, h - 0.22, x + 1, fy, h - 0.12, "neon_" + ("pink" if (x // 6) % 2 else "cyan"))
                if south_row and h > H_CUT:
                    if z0 < H_CUT:
                        face(target(x, y), x, y, side, z0, H_CUT, mat)
                    face(target(x, y, True), x, y, side, max(z0, H_CUT), h, mat)
                else:
                    face(target(x, y), x, y, side, z0, h, mat)
            tg2 = target(x, y, south_row)
            tg2.poly([(x, Y(y + 1), h), (x + 1, Y(y + 1), h), (x + 1, Y(y), h), (x, Y(y), h)],
                     "roof_gravel" if k == "ext" else "wall_top", [(x, Y(y + 1)), (x + 1, Y(y + 1)), (x + 1, Y(y)), (x, Y(y))])
            if south_row:
                target(x, y).poly([(x, Y(y + 1), H_CUT), (x + 1, Y(y + 1), H_CUT), (x + 1, Y(y), H_CUT), (x, Y(y), H_CUT)], "metal_dark")
            # liseré néon sur les façades de boutique côté galerie (boutiques à plafond)
            if k == "roof":
                for sd, dx, dy in SIDES:
                    if tile(x + dx, y + dy) in (1, 5, 6):
                        col = neon_of(m)
                        if sd == "S":
                            neon.box(x, Y(y + 1) - 0.03, 0.95, x + 1, Y(y + 1), 1.03, "neon_" + col)
                        elif sd == "E":
                            neon.box(x + 1, Y(y + 1), 0.95, x + 1.03, Y(y), 1.03, "neon_" + col)
                        elif sd == "W":
                            neon.box(x - 0.03, Y(y + 1), 0.95, x, Y(y), 1.03, "neon_" + col)
    # portes : rideau métallique relevé (encadrement + linteau) ; le jeu dessine le battant
    for (dx_, dy_), d in DOOR_CELLS.items():
        bid = CELL_BLD.get((dx_, dy_))
        hh = H_ROOF if bid is not None else H_SHOP
        south = bid is not None and dy_ == BLD[bid]["rect"][1] + BLD[bid]["rect"][3] - 1
        tg = mbs.setdefault(("front_%d" % bid) if south else (("walls_%d" % bid) if bid is not None else "hullwalls"), MB())
        X0, X1, YN, YS = dx_, dx_ + 1, Y(dy_), Y(dy_ + 1)
        locked = d.get("state", 1) == 2
        if not d["vertical"]:
            tg.box(X0, YS + 0.3, H_DOOR, X1, YN - 0.3, hh, "shutter")
            for ex in (X0, X1 - 0.08):
                tg.box(ex, YS + 0.25, 0.0, ex + 0.08, YN - 0.25, H_DOOR + 0.05, "metal_dark")
        else:
            tg.box(X0 + 0.3, YS, H_DOOR, X1 - 0.3, YN, hh, "shutter")
            for ey in (YS, YN - 0.08):
                tg.box(X0 + 0.25, ey, 0.0, X1 - 0.25, ey + 0.08, H_DOOR + 0.05, "metal_dark")
        mbs.setdefault("ground_door", MB()).box(X0 + 0.05, YS + 0.05, 0.0, X1 - 0.05, YN - 0.05, 0.012, "metal_mid")
        m = CELL_MOD.get((dx_, dy_))
        col = "red" if locked else neon_of(m)
        DOOR_GLOWS.append((dx_ + 0.5, Y(dy_) - 0.5, col))
    for k, mb in mbs.items():
        mb.to_object(k, "world")
    glass.to_object("_glass", "world")
    neon.to_object("_neon", "world")
    fac.to_object("_facade", "world")


# ======================================================================= plafonds des boutiques fermées
def roof_shop(mb, b, rng):
    """Plafond / toit plat d'une boutique fermée : gravillons, rebord, climatiseurs, gaines,
    trappes, et l'enseigne néon côté galerie."""
    x, y, w, h = b["rect"]
    z = H_ROOF
    X0, X1, YN, YS = x - 0.04, x + w + 0.04, Y(y) + 0.04, Y(y + h) - 0.04
    mb.box(X0, YS, z, X1, YN, z + 0.1, "roof_gravel")
    for (a0, a1, b0, b1) in ((X0, X1, YS, YS + 0.15), (X0, X1, YN - 0.15, YN), (X0, X0 + 0.15, YS, YN), (X1 - 0.15, X1, YS, YN)):
        mb.box(a0, b0, z + 0.1, a1, b1, z + 0.25, "wall_top")
    zt = z + 0.1
    for k in range(rng.randint(1, 3)):
        cx = x + rng.uniform(1.2, w - 1.2)
        cy = y + rng.uniform(1.2, h - 1.2)
        mb.box(cx - 0.6, Y(cy + 0.45), zt, cx + 0.6, Y(cy - 0.45), zt + 0.45, "metal_mid")
        mb.cyl(cx + 0.25, Y(cy), zt + 0.45, zt + 0.48, 0.3, "metal_dark", 14)
        mb.box(cx - 0.55, Y(cy + 0.4), zt + 0.45, cx - 0.1, Y(cy - 0.4), zt + 0.47, "roof_metal")
    for k in range(rng.randint(1, 2)):
        vx = x + rng.uniform(0.8, w - 0.8)
        vy = y + rng.uniform(0.8, h - 0.8)
        mb.cyl(vx, Y(vy), zt, zt + 0.3, 0.18, "metal", 10)
        mb.cyl(vx, Y(vy), zt + 0.3, zt + 0.36, 0.26, "metal_mid", 10)
    mb.seg((x + 0.5, Y(y + 0.5), zt + 0.12), (x + w - 0.5, Y(y + 0.5), zt + 0.12), 0.1, "metal_mid", 8)
    # verrières (lueur chaude de l'intérieur) et bandes de joints du toit
    for k in range(max(1, (w * h) // 40)):
        sx_ = x + rng.uniform(1.0, max(1.1, w - 3.0))
        sy_ = y + rng.uniform(1.0, max(1.1, h - 2.5))
        mb.box(sx_, Y(sy_ + 1.4), zt, sx_ + 2.0, Y(sy_), zt + 0.12, "metal_dark")
        for q in range(3):
            mb.box(sx_ + 0.08 + q * 0.64, Y(sy_ + 1.32), zt + 0.12, sx_ + 0.64 + q * 0.64, Y(sy_ + 0.08), zt + 0.14, "skylight")
    for xx in range(x + 2, x + w - 1, 3):
        mb.box(xx, Y(y + h - 0.3), zt, xx + 0.05, Y(y + 0.3), zt + 0.02, "wall_top")
    if rng.random() < 0.6:
        tx = x + rng.uniform(0.8, w - 1.8)
        ty = y + rng.uniform(0.8, h - 1.8)
        mb.box(tx, Y(ty + 0.9), zt, tx + 0.9, Y(ty), zt + 0.06, "metal_dark")


def sign_text(mb_obj_name, text, x, y, z, size, mat, rot_x=0.0):
    """Enseigne en lettres (objet texte Blender converti en maillage)."""
    cu = bpy.data.curves.new(mb_obj_name, "FONT")
    cu.body = text
    cu.size = size
    cu.extrude = 0.03
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    tmp = bpy.data.objects.new(mb_obj_name + "_c", cu)
    coll("world").objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp)
    ob = bpy.data.objects.new(mb_obj_name, me)
    ob.location = (x, y, z)
    ob.rotation_euler = (rot_x, 0, 0)
    coll("world").objects.link(ob)
    me.materials.clear()
    me.materials.append(MATS[mat])
    return ob


def build_roofs():
    for b in LAYOUT.get("buildings", []):
        bid = b["id"]
        rng = random.Random(bid * 7919 + SEED)
        mb = MB()
        roof_shop(mb, b, rng)
        mb.to_object("roof_%d" % bid, "roofs")
    # enseignes : café (« CAFÉ »), arcade, cinéma, bijouterie, supérette (textes néon)
    n = 0
    for m in MODS:
        x, y, w, h = m["rect"]
        fx, fy = m.get("facade", [0, 0])
        role = m["role"]
        txt = {"shop_cafe": "CAFÉ", "arcade": "ARCADE", "cinema_lobby": "CINÉMA", "shop_jewelry": "BIJOUX",
               "supermarket": "MARKET"}.get(role)
        if not txt:
            continue
        col = "neon_" + neon_of(m)
        zz = (H_ROOF if m["roof"] else H_SHOP) + 0.12
        bid_ = CELL_BLD.get((x + w // 2, y + h // 2))
        sname = ("_sb%d_%d" % (bid_, n)) if bid_ is not None else ("_sign%d" % n)
        if fy == 1:       # façade au sud (rangée nord, cinéma)
            sign_text(sname, txt, x + w / 2, Y(y + h) + 0.15, zz, 0.75, col, math.radians(70))
        elif fy == -1:    # façade au nord (rangée sud) : enseigne posée sur le mur nord, lisible
            sign_text(sname, txt, x + w / 2, Y(y) - 0.2, zz, 0.75, col, math.radians(70))
        else:
            sx = x + (w + 0.15 if fx == 1 else -0.15)
            ob = sign_text(sname, txt, sx, Y(y + h / 2), zz, 0.6, col, math.radians(70))
            ob.rotation_euler = (math.radians(70), 0, math.radians(90 if fx == 1 else -90))
        n += 1


# ======================================================================= escalators, jardinières, arbres
PT_LIGHTS = []


def build_escalators():
    mb = MB()
    glass_e = MB()
    for e in C.get("escalators", []):
        x, y, w, h = e["rect"]
        # rampe : marches montant du pied (sud) vers le nord, garde-corps vitrés, mains courantes
        ztop = 1.7
        X0, X1 = x + 0.12, x + w - 0.12
        n = int(h * 3)
        for k in range(n):
            f0 = k / n
            yy0 = y + h - f0 * h
            zz = f0 * ztop
            mb.box(X0 + 0.25, Y(yy0), max(0.0, zz - 0.15), X1 - 0.25, Y(yy0 - h / n), zz + 0.02, "metal_mid" if k % 2 else "metal_dark")
        # flancs (caissons) et mains courantes noires
        for (sx0, sx1) in ((X0, X0 + 0.25), (X1 - 0.25, X1)):
            for k in range(12):
                f0 = k / 12
                f1 = (k + 1) / 12
                ya, yb = y + h - f0 * h, y + h - f1 * h
                mb.poly([(sx0, Y(ya), 0.0), (sx0, Y(yb), 0.0), (sx0, Y(yb), f1 * ztop + 0.35), (sx0, Y(ya), f0 * ztop + 0.35)], "chrome")
                mb.poly([(sx1, Y(yb), 0.0), (sx1, Y(ya), 0.0), (sx1, Y(ya), f0 * ztop + 0.35), (sx1, Y(yb), f1 * ztop + 0.35)], "chrome")
                mb.poly([(sx0, Y(ya), f0 * ztop + 0.35), (sx0, Y(yb), f1 * ztop + 0.35), (sx1, Y(yb), f1 * ztop + 0.35), (sx1, Y(ya), f0 * ztop + 0.35)], "metal_dark")
            mb.seg(((sx0 + sx1) / 2, Y(y + h), 0.75), ((sx0 + sx1) / 2, Y(y), ztop + 0.75), 0.05, "rubber", 6)
            # garde-corps vitré entre caisson et main courante
            gx = (sx0 + sx1) / 2
            glass_e.poly([(gx, Y(y + h), 0.35), (gx, Y(y), ztop + 0.35), (gx, Y(y), ztop + 0.72), (gx, Y(y + h), 0.72)], "glass")
            # balise lumineuse au pied (maquette : points blancs au bas des escalators)
            mb.box(sx0 + 0.04, Y(y + h) - 0.02, 0.3, sx1 - 0.04, Y(y + h) + 0.1, 0.36, "lamp_dim")
            PT_LIGHTS.append((gx, Y(y + h) - 0.3, 0.6, NEON["white"], 0.12))
        # palier haut (plateforme) et caisson du moteur
        mb.box(x, Y(y + 0.6), 0.0, x + w, Y(y), ztop + 0.05, "metal_dark")
        mb.box(x + 0.1, Y(y + h), 0.0, x + w - 0.1, Y(y + h - 0.5), 0.05, "chrome")
    mb.to_object("hullwalls_esc", "world")
    glass_e.to_object("_esc_glass", "world")


def bush(mb, x, y, z, r, rng, flowers=0.0, dry=0.0):
    """Massif touffu : boules de feuillage déformées (bruit), verts variés, fleurs éventuelles."""
    for k in range(rng.randint(4, 6)):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0, r * 0.55)
        rr = rng.uniform(r * 0.45, r * 0.75)
        m = "leaf_dry" if rng.random() < dry else rng.choice(["plant", "plant_dark", "leaf"])
        mb.sphere(x + math.cos(a) * d, y + math.sin(a) * d, z + rr * 0.55, rr, m, 2, sz=0.75, nscale=2.5, rng=rng)
    for k in range(int(flowers * 6)):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0, r * 0.7)
        mb.sphere(x + math.cos(a) * d, y + math.sin(a) * d, z + r * 0.9, 0.05, rng.choice(["flower_a", "flower_b"]), 1)


def palm(mb, x, y, z0, z1, R, rng, fronds=9):
    """Palmier en pot : stipe annelé, palmes en lanières retombantes (bandes de triangles)."""
    mb.cyl(x, y, z0, z1, 0.06, "trunk", 8, r2=0.045)
    for k in range(4):
        zz = z0 + (z1 - z0) * (k + 0.5) / 4
        mb.cyl(x, y, zz - 0.02, zz + 0.02, 0.075, "trunk", 8)
    off = rng.uniform(0, math.tau)
    for j in range(fronds):
        a = off + j / fronds * math.tau + rng.uniform(-0.15, 0.15)
        L_ = R * rng.uniform(0.8, 1.1)
        droop = rng.uniform(0.35, 0.6)
        ca, sa = math.cos(a), math.sin(a)
        nseg = 5
        pts = []
        for i in range(nseg + 1):
            f = i / nseg
            d = f * L_
            zz = z1 + 0.08 + f * 0.25 - (f ** 2) * droop
            w = 0.16 * math.sin(math.pi * min(1.0, f * 1.1 + 0.05))
            pts.append(((x + ca * d, y + sa * d, zz), w))
        for i in range(nseg):
            (p0, w0), (p1, w1) = pts[i], pts[i + 1]
            nx, ny = -sa, ca
            a0 = (p0[0] + nx * w0, p0[1] + ny * w0, p0[2] - w0 * 0.3)
            b0 = (p0[0] - nx * w0, p0[1] - ny * w0, p0[2] - w0 * 0.3)
            a1 = (p1[0] + nx * w1, p1[1] + ny * w1, p1[2] - w1 * 0.3)
            b1 = (p1[0] - nx * w1, p1[1] - ny * w1, p1[2] - w1 * 0.3)
            m = "leaf" if j % 3 else "plant"
            mb.poly([p0, a0, a1, p1], m)
            mb.poly([p0, p1, b1, b0], m)


def build_planters():
    """Jardinières de l'atrium (cases mur) et terre-pleins plantés du parking, arbres et
    lampadaires."""
    mb = MB()
    veg = MB()
    lamps = []
    for (x, y) in sorted(PLANTER_CELLS):
        # jardinière continue de l'atrium : muret de pierre, terre, massifs touffus, palmiers
        mb.box(x, Y(y + 1.0), 0.0, x + 1.0, Y(y), 0.42, "stone")
        mb.box(x + 0.08, Y(y + 0.92), 0.42, x + 0.92, Y(y + 0.08), 0.44, "soil")
        rng = random.Random(x * 31 + y * 7)
        bush(veg, x + 0.5, Y(y + 0.5), 0.44, rng.uniform(0.38, 0.5), rng, flowers=0.5 if rng.random() < 0.3 else 0.0, dry=0.15)
        if rng.random() < 0.18:
            palm(veg, x + 0.5, Y(y + 0.5), 0.44, rng.uniform(1.3, 1.7), rng.uniform(0.8, 1.0), rng)
    for (x, y) in sorted(TREE_CELLS):
        mb.box(x + 0.0, Y(y + 1.0), 0.0, x + 1.0, Y(y), 0.25, "sidewalk")
        mb.box(x + 0.05, Y(y + 0.95), 0.25, x + 0.95, Y(y + 0.05), 0.27, "soil")
    for t in C.get("trees", []):
        x, y, w, h = t
        rng = random.Random(x * 13 + y)
        k = 0
        for yy in range(y + 1, y + h, 3):
            cx, cy = x + w / 2, yy + 0.5
            veg.cyl(cx, Y(cy), 0.25, 1.6, 0.09, "trunk", 8)
            for j in range(5):
                veg.sphere(cx + rng.uniform(-0.5, 0.5), Y(cy + rng.uniform(-0.5, 0.5)), rng.uniform(1.5, 2.1), rng.uniform(0.55, 0.85),
                           rng.choice(["plant", "plant_dark"]), 2)
            if k % 2 == 0:
                lamps.append((cx, cy + 1.5))
            k += 1
    # lampadaires du pourtour du parking (hors cases jouables : sur la bordure sud et les côtés)
    px_, py_, pw_, ph_ = PARK
    for xx in range(px_ + 4, px_ + pw_ - 2, 10):
        lamps.append((xx + 0.5, py_ + ph_ + 0.5))
    for yy in (py_ + 3, py_ + ph_ - 4):
        lamps.append((px_ - 0.5, yy + 0.5))
        lamps.append((px_ + pw_ + 0.5, yy + 0.5))
    for (lx, ly) in lamps:
        mb.cyl(lx, Y(ly), 0.25, 2.4, 0.05, "metal_dark", 8)
        mb.box(lx - 0.6, Y(ly) - 0.06, 2.35, lx + 0.6, Y(ly) + 0.06, 2.42, "metal_dark")
        for sx in (-0.55, 0.55):
            mb.box(lx + sx - 0.12, Y(ly) - 0.1, 2.28, lx + sx + 0.12, Y(ly) + 0.1, 2.35, "lamp_warm")
            LAMPS.append((lx + sx, Y(ly), 2.2))
    mb.to_object("hullwalls_planters", "world")
    veg.to_object("_veg", "world", smooth=True)


LAMPS = []
import zlib

# ======================================================================= décors (prop_spawns)
# Emprise des grands décors (= mall_populator.gd BIG) : l'export ne donne que size = 1×1.
BIG = {"fountain": (7, 5), "car_wreck": (2, 1), "store_shelf": (2, 1), "cinema_seats": (2, 1)}


def _rect_of_spawn(s):
    sx, sy = s.get("size", [1, 1])
    if [sx, sy] == [1, 1] and s.get("kind") in BIG:
        sx, sy = BIG[s["kind"]]
    x0 = s["cell"][0] - (sx - 1) // 2
    return [x0, s["cell"][1] - sy + 1, sx, sy]


def _cells_of(rect):
    x, y, w, h = rect
    return [(xx, yy) for yy in range(y, y + h) for xx in range(x, x + w)]


class Local:
    """Repère local d'un décor adossé : u le long du mur (centré), v depuis le mur (0) vers la
    salle, z vers le haut. Rotations multiples de 90°."""

    def __init__(self, rect, back):
        x, y, w, h = rect
        self.x0, self.x1, self.y0, self.y1 = x, x + w, y, y + h
        self.back = back
        self.A, self.D = (w, h) if back in ("N", "S") else (h, w)

    def p(self, u, v):
        cx = (self.x0 + self.x1) / 2
        cy = (self.y0 + self.y1) / 2
        b = self.back
        if b == "N":
            return cx + u, Y(self.y0 + v)
        if b == "S":
            return cx - u, Y(self.y1 - v)
        if b == "W":
            return self.x0 + v, Y(cy - u)
        return self.x1 - v, Y(cy + u)

    def box(self, mb, u0, v0, z0, u1, v1, z1, mat):
        ax, ay = self.p(u0, v0)
        bx, by = self.p(u1, v1)
        mb.box(min(ax, bx), min(ay, by), z0, max(ax, bx), max(ay, by), z1, mat)

    def cyl(self, mb, u, v, z0, z1, r, mat, seg=14):
        x, y = self.p(u, v)
        mb.cyl(x, y, z0, z1, r, mat, seg)

    def sph(self, mb, u, v, z, r, mat, sub=1):
        x, y = self.p(u, v)
        mb.sphere(x, y, z, r, mat, sub)


def back_side(rect):
    x, y, w, h = rect
    score = {"N": 0, "S": 0, "E": 0, "W": 0}
    for xx in range(x, x + w):
        score["N"] += tile(xx, y - 1) == 3
        score["S"] += tile(xx, y + h) == 3
    for yy in range(y, y + h):
        score["W"] += tile(x - 1, yy) == 3
        score["E"] += tile(x + w, yy) == 3
    best = max(score, key=lambda k: (score[k], {"N": 3, "W": 2, "E": 1, "S": 0}[k]))
    return best if score[best] > 0 else "N"


GOODS = ["fabric_a", "fabric_b", "fabric_c", "toy_a", "toy_b", "toy_c", "cardboard", "white"]


def shelf(mb, L, a, d, rng, h=1.0, goods=None):
    goods = goods or GOODS
    L.box(mb, -a, 0.03, 0.0, a, d, 0.08, "metal_mid")
    L.box(mb, -a, 0.03, 0.08, a, 0.1, h, "metal_mid")
    for z in (0.3, 0.6, 0.9):
        if z >= h:
            break
        L.box(mb, -a, 0.03, z, a, d, z + 0.03, "metal")
        uu = -a + 0.05
        while uu < a - 0.12:
            ww = rng.uniform(0.1, 0.25)
            L.box(mb, uu, 0.1, z + 0.03, min(a - 0.03, uu + ww), d - 0.05, z + rng.uniform(0.1, 0.22), rng.choice(goods))
            uu += ww + 0.03


def car(mb, L, rng, color=None):
    """Voiture abandonnée vue de dessus (berline) : caisse, vitres sombres, phares."""
    a = L.A / 2 - 0.05
    d = L.D
    mat = color or "car_%d" % rng.randint(0, len(CAR_COLORS) - 1)
    w = min(d - 0.1, 1.15)
    vc = d / 2
    hw = w / 2

    def P(u, dv, z):
        x, y = L.p(u, vc + dv)
        return (x, y, z)
    # roues (sous la caisse, dépassent un peu)
    for uu in (-a * 0.62, a * 0.62):
        for sv in (-1, 1):
            x, y = L.p(uu, vc + sv * (hw - 0.08))
            ax_ = "Y" if L.back in ("N", "S") else "X"
            mb.cyl(x, y, 0.17, 0.18, 0.17, "rubber", 12, axis=ax_)
    # caisse : sections le long de la voiture (chanfrein haut, bouts arrondis, capot plus bas)
    secs = []
    nsec = 9
    for i in range(nsec):
        f = i / (nsec - 1)
        u = -a + f * 2 * a
        e = 1.0 - (abs(f - 0.5) * 2) ** 6
        k = 0.86 + 0.14 * e
        zt = 0.44 + 0.06 * e - (0.04 if f > 0.75 else 0.0)
        secs.append([P(u, -hw * k, 0.13), P(u, -hw * k, zt - 0.1), P(u, -hw * k + 0.07, zt), P(u, hw * k - 0.07, zt),
                     P(u, hw * k, zt - 0.1), P(u, hw * k, 0.13)])
    for i in range(nsec - 1):
        A_, B_ = secs[i], secs[i + 1]
        for j in range(len(A_) - 1):
            mb.poly([A_[j], B_[j], B_[j + 1], A_[j + 1]], mat)
    for S_ in (secs[0], secs[-1]):
        mb.poly(S_, mat)
    # habitacle : base (c0..c1) et toit plus court, vitres teintées, toit couleur caisse
    c0, c1 = -a * 0.5, a * 0.42
    hb, ht, zb, zt = hw * 0.86 - 0.06, hw * 0.86 - 0.18, 0.48, 0.82
    r0, r1 = c0 + 0.22, c1 - 0.38
    B = [P(c0, -hb, zb), P(c1, -hb, zb), P(c1, hb, zb), P(c0, hb, zb)]
    T = [P(r0, -ht, zt), P(r1, -ht, zt), P(r1, ht, zt), P(r0, ht, zt)]
    mb.poly(T, mat)
    mb.poly([B[1], B[2], T[2], T[1]], "glass_dark")    # pare-brise
    mb.poly([B[3], B[0], T[0], T[3]], "glass_dark")    # lunette arrière
    mb.poly([B[0], B[1], T[1], T[0]], "glass_dark")
    mb.poly([B[2], B[3], T[3], T[2]], "glass_dark")
    # montants et liseré de toit
    L.box(mb, r0 + 0.05, vc - 0.02, zt, r1 - 0.05, vc + 0.02, zt + 0.006, mat)
    # phares, feux, pare-chocs
    for sv in (-1, 1):
        vv = vc + sv * (hw * 0.86 - 0.16)
        L.box(mb, a - 0.05, vv - 0.1, 0.33, a + 0.015, vv + 0.1, 0.42, "headlight" if rng.random() < 0.3 else "white")
        L.box(mb, -a - 0.015, vv - 0.1, 0.33, -a + 0.04, vv + 0.1, 0.42, "taillight")
    for uu in (a - 0.02, -a - 0.02):
        L.box(mb, uu - 0.02, vc - hw * 0.8, 0.15, uu + 0.04, vc + hw * 0.8, 0.24, "metal_mid")
    # rétroviseurs
    for sv in (-1, 1):
        L.box(mb, c1 - 0.08, vc + sv * hb - 0.04, 0.5, c1, vc + sv * (hb + 0.1), 0.56, mat)


def prop(mb, kind, L, rng):
    A, D = L.A, L.D
    a = A / 2 - 0.05
    d = D - 0.06
    k = kind
    if k == "fountain":
        # grand bassin ovale (emprise 5 × 3) : margelle, eau, vasque centrale à deux étages
        # (maquette : bassin carré de pierre, fontaine ronde à vasques au centre, eau bleu nuit)
        cx, cv = 0.0, D / 2
        x0, y0 = L.p(cx, cv)
        ha, hd = A / 2 - 0.06, D / 2 - 0.06
        t = 0.22
        for (a0, a1, b0, b1) in ((-ha, ha, -hd, -hd + t), (-ha, ha, hd - t, hd), (-ha, -ha + t, -hd, hd), (ha - t, ha, -hd, hd)):
            mb.box(x0 + a0, y0 + b0, 0.0, x0 + a1, y0 + b1, 0.4, "stone")
            mb.box(x0 + a0 - 0.03, y0 + b0 - 0.03, 0.4, x0 + a1 + 0.03, y0 + b1 + 0.03, 0.46, "stone_dark")
        for (sx_, sy_) in ((-ha, -hd), (ha, -hd), (-ha, hd), (ha, hd)):
            mb.box(x0 + sx_ - 0.16, y0 + sy_ - 0.16, 0.0, x0 + sx_ + 0.16, y0 + sy_ + 0.16, 0.6, "stone_dark")
            mb.sphere(x0 + sx_, y0 + sy_, 0.68, 0.1, "bronze", 1)
        mb.box(x0 - ha + t, y0 - hd + t, 0.0, x0 + ha - t, y0 + hd - t, 0.05, "stone_dark")
        mb.box(x0 - ha + t, y0 - hd + t, 0.05, x0 + ha - t, y0 + hd - t, 0.3, "water")
        r = hd - 0.45
        mb.cyl(x0, y0, 0.0, 0.48, r, "stone", 32)
        mb.cyl(x0, y0, 0.48, 0.52, r + 0.05, "stone_dark", 32)
        mb.cyl(x0, y0, 0.3, 0.5, r - 0.1, "water", 32)
        mb.cyl(x0, y0, 0.5, 0.95, 0.16, "stone", 12)
        mb.cyl(x0, y0, 0.95, 1.05, r * 0.5, "stone", 24, r2=r * 0.58)
        mb.cyl(x0, y0, 1.0, 1.07, r * 0.5, "water", 24)
        mb.cyl(x0, y0, 1.05, 1.35, 0.08, "bronze", 10)
        mb.sphere(x0, y0, 1.42, 0.12, "bronze", 2)
        # jets (gouttes émissives pâles)
        for j in range(8):
            a_ = j / 8 * math.tau
            mb.seg((x0 + math.cos(a_) * 0.15, y0 + math.sin(a_) * 0.15, 1.3),
                   (x0 + math.cos(a_) * r * 0.55, y0 + math.sin(a_) * r * 0.55, 1.08), 0.012, "spray", 4)
        for j in range(12):
            a_ = j / 12 * math.tau
            mb.seg((x0 + math.cos(a_) * r * 0.55, y0 + math.sin(a_) * r * 0.55, 1.0),
                   (x0 + math.cos(a_) * (r - 0.15), y0 + math.sin(a_) * (r - 0.15), 0.52), 0.012, "spray", 4)
    elif k in ("planter", "palm_pot"):
        rr = min(A, D) / 2 - 0.12
        L.cyl(mb, 0.0, D / 2, 0.0, 0.42, rr, "planter", 16)
        L.cyl(mb, 0.0, D / 2, 0.42, 0.47, rr + 0.03, "stone_dark", 16)
        L.cyl(mb, 0.0, D / 2, 0.45, 0.48, rr - 0.04, "soil", 16)
        x0, y0 = L.p(0.0, D / 2)
        if k == "palm_pot":
            palm(mb, x0, y0, 0.47, 1.3, 0.6, rng, 8)
        else:
            bush(mb, x0, y0, 0.46, rr * 0.95, rng, flowers=0.4 if rng.random() < 0.4 else 0.0)
    elif k == "bench":
        # banc de galerie : piètement métallique, assise et dossier à lattes
        dd = min(d, 0.62)
        for uu in (-a + 0.12, a - 0.16):
            L.box(mb, uu, 0.16, 0.0, uu + 0.05, dd - 0.04, 0.3, "metal_dark")
            L.box(mb, uu, 0.12, 0.0, uu + 0.05, 0.2, 0.62, "metal_dark")
        for j in range(4):
            v0_ = 0.2 + j * (dd - 0.24) / 4
            L.box(mb, -a + 0.04, v0_, 0.3, a - 0.04, v0_ + (dd - 0.24) / 4 - 0.025, 0.34, "wood_light")
        for j in range(2):
            L.box(mb, -a + 0.04, 0.12, 0.42 + j * 0.12, a - 0.04, 0.18, 0.51 + j * 0.12, "wood_light")
    elif k == "mall_sofa":
        L.box(mb, -a, 0.15, 0.0, a, min(d, 0.6), 0.3, "fabric_a")
        L.box(mb, -a, 0.1, 0.3, a, 0.24, 0.62, "fabric_a")
        for uu in (-a, a - 0.12):
            L.box(mb, uu, 0.12, 0.3, uu + 0.12, min(d, 0.6), 0.45, "fabric_a")
        L.box(mb, -a + 0.15, 0.26, 0.3, -0.02, min(d, 0.6) - 0.03, 0.36, "fabric_c")
        L.box(mb, 0.02, 0.26, 0.3, a - 0.15, min(d, 0.6) - 0.03, 0.36, "fabric_c")
    elif k == "mannequin":
        L.cyl(mb, 0.0, D / 2, 0.0, 0.05, 0.22, "metal_dark", 10)
        L.cyl(mb, 0.0, D / 2, 0.05, 0.75, 0.1, rng.choice(["fabric_a", "fabric_b", "fabric_c"]), 10)
        L.sph(mb, 0.0, D / 2, 0.85, 0.1, "white", 1)
    elif k in ("clothes_rack", "shoe_rack"):
        L.box(mb, -a, D / 2 - 0.04, 0.0, a, D / 2 + 0.04, 0.95, "chrome")
        uu = -a + 0.05
        while uu < a - 0.08:
            L.box(mb, uu, D / 2 - 0.22, 0.25, uu + 0.07, D / 2 + 0.22, 0.9, rng.choice(["fabric_a", "fabric_b", "fabric_c", "white"]))
            uu += 0.1
    elif k in ("store_shelf", "gondola", "medicine_shelf", "stock_rack", "bookshelf"):
        goods = ["white", "cardboard", "toy_b"] if k == "medicine_shelf" else (["wood_floor", "fabric_b", "fabric_a", "cream"] if k == "bookshelf" else None)
        shelf(mb, L, a, min(d, 0.55), rng, 1.05, goods)
    elif k == "display_table":
        # table de présentation : plateau bois clair, piètement, marchandise posée (pliée, boîtes)
        dd = min(d, 0.8)
        L.box(mb, -a, 0.1, 0.5, a, dd, 0.56, "wood_light")
        for (uu, vv) in ((-a + 0.04, 0.14), (a - 0.1, 0.14), (-a + 0.04, dd - 0.1), (a - 0.1, dd - 0.1)):
            L.box(mb, uu, vv, 0.0, uu + 0.06, vv + 0.06, 0.5, "metal_dark")
        uu = -a + 0.08
        while uu < a - 0.2:
            ww = rng.uniform(0.18, 0.3)
            for vv in (0.16, dd / 2 + 0.03):
                if rng.random() < 0.75:
                    L.box(mb, uu, vv, 0.56, uu + ww - 0.04, vv + dd / 2 - 0.15, 0.56 + rng.uniform(0.04, 0.12),
                          rng.choice(["fabric_a", "fabric_b", "fabric_c", "white", "cardboard", "toy_b"]))
            uu += ww
    elif k in ("checkout", "food_counter", "glass_case"):
        dd = min(d, 0.6)
        L.box(mb, -a, 0.1, 0.0, a, dd, 0.55, "wood_floor" if k != "glass_case" else "metal_dark")
        L.box(mb, -a - 0.02, 0.08, 0.55, a + 0.02, dd + 0.02, 0.6, "stone_dark" if k != "glass_case" else "chrome")
        if k == "glass_case":
            L.box(mb, -a + 0.05, 0.15, 0.6, a - 0.05, dd - 0.05, 0.85, "glass")
            L.box(mb, -a + 0.06, 0.16, 0.6, a - 0.06, dd - 0.06, 0.62, "fabric_a")
            for j in range(5):
                L.sph(mb, rng.uniform(-a + 0.1, a - 0.1), rng.uniform(0.22, dd - 0.12), 0.65, 0.04, rng.choice(["lamp_warm", "chrome", "lamp_white"]), 1)
        elif k == "checkout":
            L.box(mb, -0.3, 0.15, 0.6, 0.05, 0.38, 0.62, "metal_dark")
            L.box(mb, 0.12, 0.15, 0.6, 0.4, 0.32, 0.78, "screen_cyan")
            L.box(mb, -a + 0.05, dd - 0.15, 0.6, -0.4, dd - 0.02, 0.63, "rubber")
        else:
            for j in range(3):
                L.cyl(mb, -a + 0.25 + j * (2 * a - 0.5) / 2, 0.35, 0.6, 0.66, 0.1, rng.choice(["white", "metal", "cream"]), 10)
    elif k == "food_table":
        L.cyl(mb, 0.0, D / 2, 0.0, 0.42, 0.05, "metal_dark", 8)
        L.cyl(mb, 0.0, D / 2, 0.42, 0.45, min(A, D) / 2 - 0.15, "white", 16)
        for j in range(3):
            ang = j / 3 * math.tau
            x0, y0 = L.p(0.0, D / 2)
            mb.cyl(x0 + math.cos(ang) * 0.36, y0 + math.sin(ang) * 0.36, 0.0, 0.28, 0.1, rng.choice(["fabric_a", "metal_mid"]), 8)
    elif k == "cinema_seats":
        uu = -a + 0.2
        while uu < a - 0.1:
            L.box(mb, uu - 0.17, 0.25, 0.0, uu + 0.17, 0.65, 0.3, "carpet_red")
            L.box(mb, uu - 0.17, 0.2, 0.3, uu + 0.17, 0.32, 0.65, "carpet_red")
            uu += 0.4
    elif k in ("popcorn_machine", "arcade_cabinet", "tv_wall", "generator", "ac_unit", "filing_cabinet"):
        hgt = {"popcorn_machine": 1.0, "arcade_cabinet": 1.1, "tv_wall": 1.1, "generator": 0.75, "ac_unit": 0.7, "filing_cabinet": 0.95}[k]
        mat = {"popcorn_machine": "toy_a", "arcade_cabinet": rng.choice(["metal_dark", "toy_b", "car_0"]), "tv_wall": "metal_dark",
               "generator": "toy_c", "ac_unit": "metal_mid", "filing_cabinet": "metal_mid"}[k]
        dep = min(d, 0.6)
        if k == "arcade_cabinet":
            # borne d'arcade : caisse noire, flancs peints, fronton lumineux, écran incliné,
            # tableau de commande (joystick, boutons)
            aa = min(a, 0.42)
            art = rng.choice(["toy_b", "car_0", "toy_a", "fabric_b"])
            L.box(mb, -aa, 0.05, 0.0, aa, dep - 0.18, hgt, "metal_dark")
            L.box(mb, -aa, dep - 0.18, 0.0, aa, dep, 0.72, "metal_dark")
            for su in (-aa - 0.015, aa - 0.02):
                L.box(mb, su, 0.05, 0.05, su + 0.035, dep, hgt - 0.05, art)
            L.box(mb, -aa + 0.04, dep - 0.2, 0.86, aa - 0.04, dep - 0.17, hgt - 0.03, rng.choice(["lamp_violet", "lamp_cyan", "lamp_pink"]))
            L.box(mb, -aa + 0.06, dep - 0.19, 0.74, aa - 0.06, dep - 0.08, 0.86, rng.choice(["screen_cyan", "screen_pink", "screen_green"]))
            L.box(mb, -aa + 0.02, dep - 0.08, 0.72, aa - 0.02, dep + 0.02, 0.76, "metal_mid")
            L.cyl(mb, -0.12, dep - 0.03, 0.76, 0.84, 0.015, "metal", 6)
            L.sph(mb, -0.12, dep - 0.03, 0.85, 0.03, "toy_a", 1)
            for (bu, bm) in ((0.04, "toy_a"), (0.11, "toy_c"), (0.18, "toy_b")):
                L.cyl(mb, bu, dep - 0.03, 0.76, 0.78, 0.022, bm, 8)
        else:
            L.box(mb, -a, 0.05, 0.0, a, dep, hgt, mat)
        if k == "arcade_cabinet":
            pass
        elif k == "tv_wall":
            uu = -a + 0.05
            while uu < a - 0.2:
                L.box(mb, uu, dep, 0.4, uu + 0.32, dep + 0.01, 0.62, rng.choice(["screen_cyan", "screen_pink", "screen_green"]))
                L.box(mb, uu, dep, 0.7, uu + 0.32, dep + 0.01, 0.92, rng.choice(["screen_cyan", "screen_pink"]))
                uu += 0.36
        elif k == "popcorn_machine":
            L.box(mb, -a + 0.08, 0.1, 0.55, a - 0.08, dep - 0.05, 0.95, "glass")
            L.box(mb, -a + 0.1, 0.12, 0.55, a - 0.1, dep - 0.08, 0.7, "toy_c")
    elif k in ("desk", "office_desk"):
        L.box(mb, -a, 0.1, 0.42, a, min(d, 0.9), 0.48, "wood_light")
        for (uu, vv) in ((-a + 0.05, 0.12), (a - 0.1, 0.12)):
            L.box(mb, uu, vv, 0.0, uu + 0.05, min(d, 0.9) - 0.02, 0.42, "metal_dark")
        L.box(mb, -0.2, 0.15, 0.48, 0.2, 0.2, 0.75, "screen_cyan")
    elif k == "toy_pile":
        for j in range(8):
            L.box(mb, rng.uniform(-a, a - 0.2), rng.uniform(0.1, d - 0.25), 0.0, 0, 0, 0, "toy_a") if False else None
            uu = rng.uniform(-a + 0.1, a - 0.2)
            vv = rng.uniform(0.1, max(0.15, d - 0.3))
            s_ = rng.uniform(0.12, 0.28)
            L.box(mb, uu, vv, 0.0, uu + s_, vv + s_, s_ * rng.uniform(0.6, 1.2), rng.choice(["toy_a", "toy_b", "toy_c"]))
    elif k == "car_wreck":
        car(mb, L, rng)
    elif k == "traffic_cone":
        L.cyl(mb, 0.0, D / 2, 0.0, 0.03, 0.2, "toy_a", 8)
        x0, y0 = L.p(0.0, D / 2)
        mb.cyl(x0, y0, 0.03, 0.45, 0.13, "toy_a", 10, r2=0.03)
    elif k == "trash_bin":
        L.cyl(mb, 0.0, D / 2, 0.0, 0.55, 0.2, "metal_mid", 12)
        L.cyl(mb, 0.0, D / 2, 0.55, 0.58, 0.22, "metal_dark", 12)
    elif k == "mall_map":
        L.box(mb, -0.35, 0.1, 0.0, 0.35, 0.25, 1.0, "metal_dark")
        L.box(mb, -0.3, 0.25, 0.35, 0.3, 0.26, 0.95, "screen_cyan")
    elif k == "neon_sign":
        L.box(mb, -a, 0.05, 0.85, a, 0.12, 1.05, rng.choice(["neon_pink", "neon_cyan", "neon_red", "neon_green"]))
        L.box(mb, -0.04, 0.05, 0.0, 0.04, 0.12, 0.85, "metal_dark")
    elif k == "tray_cart":
        L.box(mb, -a + 0.1, 0.15, 0.3, a - 0.1, d - 0.1, 0.33, "chrome")
        L.box(mb, -a + 0.1, 0.15, 0.7, a - 0.1, d - 0.1, 0.73, "chrome")
    elif k == "junk":
        # tas de mobilier abandonné (maquette : amas ocre dans les galeries) : caisses, cartons,
        # table renversée, chaise, sac
        for j in range(rng.randint(3, 5)):
            s_ = rng.uniform(0.28, 0.45)
            uu = rng.uniform(-a + s_ / 2, a - s_ / 2)
            vv = rng.uniform(0.08, max(0.1, d - s_ - 0.02))
            hh = s_ * rng.uniform(0.6, 1.0)
            z0 = 0.0 if j < 2 or rng.random() < 0.5 else rng.uniform(0.2, 0.3)
            x0_, y0_ = L.p(uu, vv + s_ / 2)
            mb.box(x0_ - s_ / 2, y0_ - s_ / 2, z0, x0_ + s_ / 2, y0_ + s_ / 2, z0 + hh,
                   rng.choice(["cardboard", "cardboard", "wood_light", "crate", "fabric_c"]), rot=rng.uniform(-0.5, 0.5))
        if rng.random() < 0.6:
            x0_, y0_ = L.p(rng.uniform(-0.2, 0.2), D / 2)
            mb.box(x0_ - 0.4, y0_ - 0.3, 0.0, x0_ + 0.4, y0_ + 0.3, 0.05, "wood_light", rot=rng.uniform(0, math.pi),
                   tilt=("X", rng.uniform(0.5, 0.9)))
    elif k == "kiosk":
        # kiosque / présentoir : comptoir, marchandise, petit auvent rayé
        dd = min(d, 0.8)
        L.box(mb, -a + 0.05, 0.12, 0.0, a - 0.05, dd, 0.5, "wood_floor")
        L.box(mb, -a, 0.1, 0.5, a, dd + 0.02, 0.55, "stone_dark")
        uu = -a + 0.1
        while uu < a - 0.15:
            L.box(mb, uu, 0.2, 0.55, uu + 0.12, dd - 0.1, 0.55 + rng.uniform(0.05, 0.15), rng.choice(GOODS))
            uu += 0.16
        L.box(mb, -a - 0.02, 0.05, 1.05, a + 0.02, dd + 0.05, 1.1, rng.choice(["awning_a", "awning_b"]))
        for uu in (-a + 0.03, a - 0.07):
            L.box(mb, uu, 0.14, 0.55, uu + 0.04, 0.18, 1.05, "metal_dark")
    elif k == "cafe":
        # table ronde et chaises (une renversée)
        x0_, y0_ = L.p(0.0, D / 2)
        mb.cyl(x0_, y0_, 0.0, 0.03, 0.18, "metal_dark", 10)
        mb.cyl(x0_, y0_, 0.03, 0.45, 0.035, "metal_dark", 8)
        mb.cyl(x0_, y0_, 0.45, 0.48, 0.3, rng.choice(["white", "wood_light", "stone_dark"]), 18)
        for j in range(rng.randint(2, 3)):
            ang = rng.uniform(0, math.tau)
            cx_, cy_ = x0_ + math.cos(ang) * 0.36, y0_ + math.sin(ang) * 0.36
            if j == 0 and rng.random() < 0.5:
                mb.box(cx_ - 0.13, cy_ - 0.13, 0.0, cx_ + 0.13, cy_ + 0.13, 0.05, "fabric_a", rot=ang)
            else:
                mb.box(cx_ - 0.12, cy_ - 0.12, 0.26, cx_ + 0.12, cy_ + 0.12, 0.3, rng.choice(["fabric_a", "metal_mid", "fabric_b"]), rot=ang)
                for (ox, oy) in ((-0.09, -0.09), (0.09, -0.09), (-0.09, 0.09), (0.09, 0.09)):
                    mb.box(cx_ + ox - 0.015, cy_ + oy - 0.015, 0.0, cx_ + ox + 0.015, cy_ + oy + 0.015, 0.26, "metal_dark")
    elif k in ("puddle", "debris", "roof_vent"):
        pass   # traités en décalques non bloquants (build_floor_details)
    else:
        L.box(mb, -a * 0.8, 0.1, 0.0, a * 0.8, min(d, 0.6), 0.5, "cardboard")


def build_props():
    groups = {}
    for p in LAYOUT.get("prop_spawns", []):
        rect = _rect_of_spawn(p)
        bid = CELL_BLD.get((rect[0], rect[1]))
        name = ("furn_%d" % bid) if bid is not None else "props"
        if p["kind"] in ("puddle", "debris", "roof_vent"):
            continue
        mb = groups.setdefault(name, MB())
        rng = random.Random(zlib.crc32(("%d,%d,%s" % (p["cell"][0], p["cell"][1], p["kind"])).encode()))
        back = back_side(rect) if p["kind"] not in ("fountain", "food_table", "car_wreck", "planter", "palm_pot", "traffic_cone", "trash_bin") else "N"
        if p["kind"] == "car_wreck":
            # la voiture déborde un peu de son emprise 2 × 1 (le pourtour est libre par construction)
            x_, y_, w_, h_ = rect
            Lc = Local([x_ - 0.25, y_ - 0.3, w_ + 0.5, h_ + 0.6], "N")
            prop(mb, "car_wreck", Lc, rng)
            continue
        Lc = Local(rect, back)
        st = len(mb.V)
        prop(mb, p["kind"], Lc, rng)
        cells_fit(mb, st, rect, margin=0.05)
    for name, mb in groups.items():
        mb.to_object(name, "world")


def decal(mb, cx, cy, s, mat):
    mb.poly([(cx - s / 2, Y(cy + s / 2), 0.004), (cx + s / 2, Y(cy + s / 2), 0.004), (cx + s / 2, Y(cy - s / 2), 0.004),
             (cx - s / 2, Y(cy - s / 2), 0.004)], mat, [(0, 0), (1, 0), (1, 1), (0, 1)])


def debris_pile(mb, cx, cy, rng, rad):
    """Petit tas de débris NON bloquant (z < 0,12), objets tournés au hasard : dalles de faux
    plafond tombées, planches, cartons aplatis, papiers, éclats de verre, canette, chaise couchée."""
    n = rng.randint(3, 7)
    for j in range(n):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0, rad)
        x, y = cx + math.cos(a) * d, cy + math.sin(a) * d
        rot = rng.uniform(0, math.pi)
        k = rng.random()
        if k < 0.22:      # dalle de faux plafond
            s_ = rng.uniform(0.28, 0.42)
            mb.box(x - s_ / 2, Y(y) - s_ / 2, 0.0, x + s_ / 2, Y(y) + s_ / 2, 0.025, "ceiling_tile", rot=rot,
                   tilt=("X", rng.uniform(-0.12, 0.12)))
        elif k < 0.42:    # planche
            L_ = rng.uniform(0.35, 0.7)
            mb.box(x - L_ / 2, Y(y) - 0.04, 0.0, x + L_ / 2, Y(y) + 0.04, 0.04, rng.choice(["wood_light", "wood_floor"]), rot=rot)
        elif k < 0.58:    # carton aplati
            mb.box(x - 0.17, Y(y) - 0.13, 0.0, x + 0.17, Y(y) + 0.13, 0.02, "cardboard", rot=rot)
        elif k < 0.72:    # papiers
            mb.box(x - 0.1, Y(y) - 0.14, 0.0, x + 0.1, Y(y) + 0.14, 0.005, "paper", rot=rot)
        elif k < 0.84:    # éclats de verre
            for q in range(4):
                sx = x + rng.uniform(-0.15, 0.15)
                sy = Y(y) + rng.uniform(-0.15, 0.15)
                s_ = rng.uniform(0.03, 0.07)
                mb.box(sx - s_, sy - s_ * 0.6, 0.0, sx + s_, sy + s_ * 0.6, 0.006, "shard", rot=rng.uniform(0, math.pi))
        elif k < 0.92:    # canette / gobelet couché
            mb.cyl(x, Y(y), 0.04, 0.12, 0.035, rng.choice(["toy_a", "metal", "white"]), 8, axis="X", rot=rot)
        else:             # chaise couchée (pieds vers le haut, très basse)
            mb.box(x - 0.18, Y(y) - 0.18, 0.0, x + 0.18, Y(y) + 0.18, 0.04, rng.choice(["metal_mid", "fabric_a", "wood_light"]), rot=rot)
            for (ox, oy) in ((-0.14, -0.14), (0.14, -0.14), (-0.14, 0.14), (0.14, 0.14)):
                c_, s__ = math.cos(rot), math.sin(rot)
                px_, py_ = x + ox * c_ - oy * s__, Y(y) + ox * s__ + oy * c_
                mb.box(px_ - 0.02, py_ - 0.02, 0.04, px_ + 0.02, py_ + 0.02, 0.11, "metal_dark")


def build_floor_details():
    """Détails non bloquants : flaques, débris, papiers, taches, feuilles mortes (z < 0,05)."""
    det = MB()
    for p in LAYOUT.get("prop_spawns", []):
        if p["kind"] not in ("puddle", "debris"):
            continue
        x, y = p["cell"]
        rng = random.Random(x * 7 + y * 131)
        if p["kind"] == "puddle":
            decal(det, x + 0.5, y + 0.5, rng.uniform(1.0, 1.8), "puddle")
        else:
            debris_pile(det, x + 0.5, y + 0.5, rng, 0.45)
    for y in range(H):
        for x in range(W):
            if not walk(x, y) or (x, y) in GAME_CELLS:
                continue
            rng = random.Random(x * 7349 + y * 1663 + SEED * 3)
            r_ = rng.random()
            park = in_parking(x, y)
            if r_ < 0.05:
                decal(det, x + rng.uniform(0.2, 0.8), y + rng.uniform(0.2, 0.8), rng.uniform(0.8, 2.2), "stain")
            elif r_ < 0.09 and not park:
                # feuilles de papier éparses
                for j in range(rng.randint(2, 5)):
                    s_ = rng.uniform(0.14, 0.26)
                    cx_, cy_ = x + rng.uniform(0.15, 0.85), y + rng.uniform(0.15, 0.85)
                    det.box(cx_ - s_ / 2, Y(cy_) - s_ * 0.7, 0.0, cx_ + s_ / 2, Y(cy_), 0.004 + j * 0.001,
                            rng.choice(["paper", "paper", "cream"]), rot=rng.uniform(0, math.pi))
            elif r_ < 0.16 and not park and tile(x, y) in (1, 2):
                # tas de débris bas, non bloquant (< 0,12) : la galerie « pillée » de la maquette
                debris_pile(det, x + rng.uniform(0.35, 0.65), y + rng.uniform(0.35, 0.65), rng, rng.uniform(0.3, 0.5))
            elif r_ < 0.11 and park:
                decal(det, x + 0.5, y + 0.5, rng.uniform(1.0, 2.2), "puddle")
    # socle carrelé sombre autour de la fontaine (plat, non bloquant)
    for p in LAYOUT.get("prop_spawns", []):
        if p["kind"] == "fountain":
            x, y = p["cell"]
            fw_, fh_ = BIG["fountain"]
            x0, y0, x1, y1 = x - (fw_ - 1) // 2 - 1.5, y - fh_ - 0.5, x + fw_ - (fw_ - 1) // 2 + 1.5, y + 2.5
            det.box(x0, Y(y1), 0.0, x1, Y(y0), 0.02, "stone_dark")
            det.box(x0 + 0.2, Y(y1 - 0.2), 0.02, x1 - 0.2, Y(y0 + 0.2), 0.025, "tiles_dark")
    det.to_object("_floordet", "world")


# Fouillis adossé (rendu seulement ; compose.py en fait des collisions sans couper de passage)
CLUTTER = {
    "shop_clothes": ["rack", "boxes"], "shop_electronics": ["boxes", "shelf"], "shop_pharmacy": ["shelf", "boxes"],
    "shop_toys": ["toys", "boxes"], "shop_shoes": ["shelf", "boxes"], "shop_perfume": ["shelf"], "shop_books": ["shelf", "shelf"],
    "shop_sports": ["rack", "boxes"], "shop_cafe": ["plant", "boxes"], "supermarket": ["shelf", "boxes"],
    "stockroom": ["boxes", "boxes", "shelf"], "service": ["boxes", "boxes"], "arcade": ["arcade"], "cinema_lobby": ["plant"],
    "shop_jewelry": ["case"], "gallery": ["plant", "bench", "bin", "junk", "junk", "kiosk", "cafe"],
    "atrium": ["bench", "plant", "cafe"], "entrance": ["plant", "bench"],
}
CLUTTER_P = {"gallery": 0.14, "atrium": 0.06, "entrance": 0.05}
# îlots libres (pas adossés) dans les grandes galeries : tas de mobilier, kiosques, tables de café
FREE_P = {"gallery": 0.028, "atrium": 0.014}
FREE_SHOP_P = 0.03
FREE_KINDS = ["junk", "junk", "cafe", "kiosk", "plant"]
CLUTTER_CELLS = []


def _keeps_ring(c, blocked):
    ring = [(c[0] + dx, c[1] + dy) for dx, dy in ((-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0))]
    free = [q for q in ring if walk(*q) and q not in blocked]
    if not free:
        return True
    fs = set(free)
    seen = {free[0]}
    st = [free[0]]
    while st:
        q = st.pop()
        for dd in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (q[0] + dd[0], q[1] + dd[1])
            if n in fs and n not in seen:
                seen.add(n)
                st.append(n)
    return len(seen) == len(fs)


def build_clutter():
    protect = set(GAME_CELLS)
    for (x, y) in list(STAIRS) + list(EXTRACT):
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                protect.add((x + dx, y + dy))
    px, py = LAYOUT["player_spawn"]
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            protect.add((px + dx, py + dy))
    blocked = set()
    for key in ("prop_spawns", "container_spawns", "hiding_spot_spawns"):
        for sp in LAYOUT.get(key, []):
            for q in _cells_of(_rect_of_spawn(sp)):
                blocked.add(q)
    mb = MB()
    for y in range(H):
        for x in range(W):
            if tile(x, y) not in (1, 2) or (x, y) in protect or in_parking(x, y):
                continue
            rid = CELL_ROOM.get((x, y), -1)
            role = role_of(rid)
            kinds = CLUTTER.get(role, [])
            if not kinds:
                continue
            walls = [sd for sd, dx, dy in SIDES if tile(x + dx, y + dy) == 3 and wall_kind(x + dx, y + dy) not in ("esc", "planter")]
            rng = random.Random(x * 9176 + y * 131 + SEED * 7)
            free_ = False
            if not walls:
                # îlot libre : loin des murs (2 cases), sans autre obstacle autour
                if rng.random() > FREE_P.get(role, FREE_SHOP_P if role.startswith("shop_") or role == "supermarket" else 0.0):
                    continue
                near = any(tile(x + dx, y + dy) != 1 and tile(x + dx, y + dy) != 2 or (x + dx, y + dy) in blocked
                           for dy in range(-2, 3) for dx in range(-2, 3))
                if near:
                    continue
                free_ = True
                kinds = FREE_KINDS if role in FREE_P else ["junk", "boxes"]
            elif len(walls) > 2:
                continue
            elif rng.random() > CLUTTER_P.get(role, 0.45):
                continue
            if not _keeps_ring((x, y), blocked):
                continue
            blocked.add((x, y))
            back = "N" if free_ else ("N" if "N" in walls else walls[0])
            Lc = Local([x, y, 1, 1], back)
            st = len(mb.V)
            kk = rng.choice(kinds)
            if kk == "rack":
                prop(mb, "clothes_rack", Lc, rng)
            elif kk == "shelf":
                prop(mb, "store_shelf", Lc, rng)
            elif kk == "boxes":
                for j in range(rng.randint(1, 3)):
                    s_ = rng.uniform(0.3, 0.5)
                    uu = rng.uniform(-0.2, 0.2)
                    Lc.box(mb, uu - s_ / 2, 0.08 + j * 0.05, j * 0.3, uu + s_ / 2, 0.08 + s_, j * 0.3 + s_ * 0.7, "cardboard")
            elif kk == "toys":
                prop(mb, "toy_pile", Lc, rng)
            elif kk == "arcade":
                prop(mb, "arcade_cabinet", Lc, rng)
            elif kk == "plant":
                prop(mb, "palm_pot", Lc, rng)
            elif kk == "bench":
                prop(mb, "bench", Lc, rng)
            elif kk == "bin":
                prop(mb, "trash_bin", Lc, rng)
            elif kk == "case":
                prop(mb, "glass_case", Lc, rng)
            elif kk in ("junk", "kiosk", "cafe"):
                prop(mb, kk, Lc, rng)
            cells_fit(mb, st, [x, y, 1, 1], margin=0.06)
            CLUTTER_CELLS.append((x, y))
    mb.to_object("clutter", "world")


def build_street_cars():
    mb = MB()
    for c in C.get("street_cars", []):
        x, y = c["pos"]
        rng = random.Random(int(x * 100 + y))
        rot = c.get("rot", 0.0)
        Lc = Local([x - 1.0, y - 0.55, 2, 1], "N") if abs(math.sin(math.radians(rot))) < 0.5 else Local([x - 0.55, y - 1.0, 1, 2], "W")
        car(mb, Lc, rng, "car_%d" % c.get("color", 0))
    # camionnette aux quais de livraison (extraction)
    for m in MODS:
        if m.get("arch") == "dock":
            x, y, w, h = m["rect"]
            Lc = Local([x + 2, y - 3, 3, 2] if y > 1 else [x + 2, -3, 3, 2], "N")
            car(mb, Lc, random.Random(x), "car_1")
    mb.to_object("_cars", "world")


# ======================================================================= lumières
def build_lights():
    n = 0
    for r in ROOMS:
        rid = r["id"]
        x, y, w, h = r["rect"]
        role = role_of(rid)
        if role == "parking":
            continue
        m = mod_of(rid)
        lrng = random.Random(rid * 31 + SEED)
        if role in ("gallery", "atrium", "entrance"):
            step = GAL_STEP
            col = (1.0, 0.72, 0.45)
            k = GAL_K
        elif role == "arcade":
            step = 3.6
            col = None    # alterné violet / rose / cyan
            k = 0.7
        else:
            step = 5.0
            col = NEON[neon_of(m)] if lrng.random() < 0.22 else (1.0, 0.8, 0.58)
            k = 0.0 if lrng.random() < 0.15 else 0.8   # quelques boutiques éteintes (zones sombres)
        if k <= 0.0:
            continue
        roofed = CELL_BLD.get((x + w // 2, y + h // 2)) is not None
        z = 1.5 if roofed else LIGHT_Z
        nx = max(1, int(round(w / step)))
        ny = max(1, int(round(h / step)))
        for i in range(nx):
            for j in range(ny):
                px = x + (i + 0.5) * w / nx + lrng.uniform(-0.6, 0.6)
                py = y + (j + 0.5) * h / ny + lrng.uniform(-0.6, 0.6)
                if not walk(int(px), int(py)) or (int(px), int(py)) in ESC_CELLS:
                    continue
                if CELL_ROOM.get((int(px), int(py))) != rid:
                    continue   # (galerie englobante : pas de plafonnier de galerie dans une boutique)
                if lrng.random() < 0.2 and role == "gallery":
                    continue
                L_ = bpy.data.lights.new("l%d" % n, "AREA")
                L_.shape = "DISK"
                L_.size = LIGHT_SIZE * (0.7 if role in ("gallery", "atrium", "entrance") else 0.6)
                L_.color = col if col is not None else NEON[("violet", "pink", "cyan", "violet")[(i + j * 3) % 4]]
                L_.energy = LIGHT_E * k * lrng.uniform(0.45, 1.3)
                o = bpy.data.objects.new("l%d" % n, L_)
                o.location = (px, Y(py), z)
                scene.collection.objects.link(o)
                n += 1
    for (gx, gy, gc) in DOOR_GLOWS:
        L_ = bpy.data.lights.new("d%d" % n, "POINT")
        L_.color = NEON[gc]
        L_.energy = LIGHT_E * NEON_GLOW
        L_.shadow_soft_size = 0.2
        o = bpy.data.objects.new("d%d" % n, L_)
        o.location = (gx, gy, 1.0)
        scene.collection.objects.link(o)
        n += 1
    for (gx, gy, gz, gc, ge) in PT_LIGHTS:
        L_ = bpy.data.lights.new("e%d" % n, "POINT")
        L_.color = gc
        L_.energy = LIGHT_E * ge
        L_.shadow_soft_size = 0.15
        o = bpy.data.objects.new("e%d" % n, L_)
        o.location = (gx, gy, gz)
        scene.collection.objects.link(o)
        n += 1
    # lueurs colorées des bandeaux néon des vitrines sur le carrelage de la galerie
    for (gx, gy, gc) in FRONT_GLOWS:
        L_ = bpy.data.lights.new("g%d" % n, "POINT")
        L_.color = NEON[gc]
        L_.energy = LIGHT_E * NEON_GLOW * 0.6
        L_.shadow_soft_size = 0.4
        o = bpy.data.objects.new("g%d" % n, L_)
        o.location = (gx, gy, 1.15)
        scene.collection.objects.link(o)
        n += 1
    for (lx, ly, lz) in LAMPS:
        L_ = bpy.data.lights.new("p%d" % n, "SPOT")
        L_.color = (1.0, 0.72, 0.42)
        L_.energy = LIGHT_E * 1.6
        L_.spot_size = math.radians(120)
        L_.spot_blend = 0.6
        L_.shadow_soft_size = 0.3
        o = bpy.data.objects.new("p%d" % n, L_)
        o.location = (lx, ly, lz)
        scene.collection.objects.link(o)
        n += 1
    # (les plafonniers ne sont plus dessinés au sol : la vue est « sous le plafond »)
    # lueur bleutée de la fontaine
    for p in LAYOUT.get("prop_spawns", []):
        if p["kind"] == "fountain":
            x, y = p["cell"]
            L_ = bpy.data.lights.new("fnt", "POINT")
            L_.color = (0.4, 0.75, 1.0)
            L_.energy = LIGHT_E * 1.5
            o = bpy.data.objects.new("fnt", L_)
            o.location = (x + 0.5, Y(y - 0.5), 1.2)
            scene.collection.objects.link(o)
    print("  lights", n, flush=True)


FIX = []


LIGHT_E = float(os.environ.get("MALL_LIGHT", "75"))
LIGHT_Z = float(os.environ.get("MALL_LIGHT_Z", "2.1"))
LIGHT_SIZE = float(os.environ.get("MALL_LIGHT_SIZE", "2.6"))
GAL_STEP = float(os.environ.get("MALL_GAL_STEP", "4.2"))
GAL_K = float(os.environ.get("MALL_GAL_K", "0.68"))
NEON_GLOW = float(os.environ.get("MALL_NEON_GLOW", "0.4"))


def build_world():
    build_floors()
    build_walls()
    build_roofs()
    build_escalators()
    build_planters()
    build_props()
    build_clutter()
    build_floor_details()
    build_street_cars()
    build_lights()


# ======================================================================= rendu
EXPOSURE = float(os.environ.get("MALL_EXPOSURE", "-0.3"))
SUN_E = float(os.environ.get("MALL_MOON", "0.8"))
SKY = float(os.environ.get("MALL_SKY", "0.15"))
SAT = float(os.environ.get("MALL_SAT", "1.15"))
CON = float(os.environ.get("MALL_CON", "1.24"))
LIFT = float(os.environ.get("MALL_LIFT", "6"))


def setup_render():
    sc = scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    # CYCLES_DEVICE=METAL / CUDA / OPTIX : rendu GPU (tools/prerender/mac_env.sh), CPU par défaut
    gpu = os.environ.get("CYCLES_DEVICE", "CPU")
    if gpu != "CPU":
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = gpu
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == gpu
        sc.cycles.device = "GPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 2
    sc.cycles.glossy_bounces = 2
    sc.cycles.transmission_bounces = 1
    sc.cycles.transparent_max_bounces = 6
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.05
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "AgX"
    try:
        sc.view_settings.look = "AgX - Punchy"
    except Exception:
        pass
    sc.view_settings.exposure = EXPOSURE
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.3, 0.26, 0.5, 1)    # crépuscule violacé (ambiance de la maquette)
    bg.inputs[1].default_value = SKY
    moon = bpy.data.lights.new("moon", "SUN")
    moon.energy = SUN_E
    moon.color = (0.62, 0.6, 1.0)
    moon.angle = math.radians(1.0)
    so = bpy.data.objects.new("moon", moon)
    sc.collection.objects.link(so)
    d = Vector((0.35, -0.45, -0.82)).normalized()
    so.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.sensor_fit = "HORIZONTAL"
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    co.rotation_euler = Euler((TILT, 0, 0))
    cam.clip_start = 0.1
    cam.clip_end = 900
    return co
def frame(co, x0, x1, y0, y1, tilt=None, ppc=None):
    """Cadre la zone de SOL [x0,x1]×[y0,y1] (cases, y vers le bas) : sol carré, ppc px/case."""
    tilt = TILT if tilt is None else tilt
    ppc = PPC if ppc is None else ppc
    co.rotation_euler = Euler((tilt, 0, 0))
    up = Vector((0, math.cos(tilt), math.sin(tilt)))
    fwd = Vector((0, math.sin(tilt), -math.cos(tilt)))
    pw = int(round((x1 - x0) * ppc))
    ph = int(round((y1 - y0) * ppc))
    vc = -(y0 + y1) / 2 * math.cos(tilt)
    co.location = Vector(((x0 + x1) / 2, 0, 0)) + up * vc - fwd * 250.0
    scene.render.resolution_x = pw
    scene.render.resolution_y = ph
    scene.render.resolution_percentage = 100
    scene.render.pixel_aspect_x = 1.0 / math.cos(tilt)
    scene.render.pixel_aspect_y = 1.0
    co.data.ortho_scale = (x1 - x0)
    global PPC_CUR
    PPC_CUR = ppc
    return pw, ph


def grade(path):
    """Étalonnage final (PIL) : saturation + contraste légers, réglables (FW_SAT, FW_CON)."""
    from PIL import Image, ImageEnhance
    im = Image.open(path).convert("RGB")
    im = ImageEnhance.Color(im).enhance(SAT)
    im = ImageEnhance.Contrast(im).enhance(CON)
    # clarté (contraste local) : lecture « peinte » plus nette, utile sur mobile
    from PIL import ImageFilter
    im = im.filter(ImageFilter.UnsharpMask(radius=max(2, int(PPC_CUR * 0.3)), percent=30, threshold=2))
    # relève des noirs (ombres brun-bleu lisibles comme la maquette, pas noires)
    lut = [int(LIFT + v * (255 - LIFT) / 255) for v in range(256)]
    im = im.point(lut * 3)
    im.save(path)


def vignette(path, k=0.22):
    """Vignettage doux (seulement pour les vues de présentation, pas les tuiles du jeu)."""
    from PIL import Image, ImageDraw, ImageFilter, ImageChops
    im = Image.open(path).convert("RGB")
    w, h = im.size
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).ellipse([-w * 0.25, -h * 0.12, w * 1.25, h * 1.12], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(min(w, h) * 0.12))
    dark = Image.eval(im, lambda v: int(v * (1 - k)))
    im = Image.composite(im, dark, m)
    im.save(path)


PPC_CUR = 16


def render(path, do_grade=True):
    scene.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    if do_grade:
        grade(path)
    return time.time() - t


def render_chunked(path, chunk=1024, ov=24, grade_=True):
    """Rendu par morceaux (bordure + recadrage, recouvrement ov px) puis assemblage : mémoire
    bornée (2 cœurs, 7 Go)."""
    from PIL import Image
    pw, ph = scene.render.resolution_x, scene.render.resolution_y
    canvas = Image.new("RGB", (pw, ph))
    scene.render.use_border = True
    scene.render.use_crop_to_border = True
    tmp = os.path.join(OUT, "_chunk.png")
    # Reprise : chaque morceau est gardé dans _chunks_<nom>/ ; une relance (process interrompu)
    # ne refait que les morceaux manquants.
    cdir = os.path.join(OUT, "_chunks_" + os.path.splitext(os.path.basename(path))[0])
    os.makedirs(cdir, exist_ok=True)
    dt = 0.0
    for y0 in range(0, ph, chunk):
        for x0 in range(0, pw, chunk):
            x1, y1 = min(x0 + chunk, pw), min(y0 + chunk, ph)
            cp = os.path.join(cdir, "c_%d_%d.png" % (x0, y0))
            if not os.path.exists(cp):
                ex0, ey0, ex1, ey1 = max(x0 - ov, 0), max(y0 - ov, 0), min(x1 + ov, pw), min(y1 + ov, ph)
                scene.render.border_min_x, scene.render.border_max_x = ex0 / pw, ex1 / pw
                scene.render.border_min_y, scene.render.border_max_y = 1 - ey1 / ph, 1 - ey0 / ph
                dt += render(tmp, grade_)
                im = Image.open(tmp).convert("RGB")
                im.crop((x0 - ex0, y0 - ey0, x0 - ex0 + (x1 - x0), y0 - ey0 + (y1 - y0))).save(cp + ".tmp.png")
                os.replace(cp + ".tmp.png", cp)
            canvas.paste(Image.open(cp).convert("RGB"), (x0, y0))
            print("  chunk", x0, y0, round(dt, 1), flush=True)
    scene.render.use_border = False
    canvas.save(path)
    os.remove(tmp)
    return dt


def render_mask(path, ppc=4, zmin=0.16, zmax=1.0, ss=4):
    """Emprise au sol RÉELLE des objets solides, vue zénithale (projection orthographique
    verticale), même cadrage au sol que « full » : px = (cx + M) * ppc, py = (cy + M) * ppc.
    Seule la tranche zmin < z < zmax compte (ce qui gêne un personnage : pas les toits, auvents,
    linteaux, ni les planches au sol). Rastérisation directe des triangles (numpy + PIL) : chaque
    triangle est découpé à la tranche puis projeté ; un triangle vertical (mur) se projette en
    segment, dessiné d'un pixel (sur-échantillonnage ss). Résultat RGB 8 bits, couverture par
    pixel : R = obstacle adossé au plan, G = fouillis décoratif, B = autre (info)."""
    import numpy as np
    from PIL import Image, ImageDraw
    tw, th = W + 2 * MARGIN, H + 2 * MARGIN
    q = ppc * ss
    layers = {c: Image.new("L", (tw * q, th * q), 0) for c in "RGB"}
    draws = {c: ImageDraw.Draw(im) for c, im in layers.items()}
    t = time.time()
    ntri = 0
    for o in bpy.data.objects:
        if o.type != "MESH" or o.hide_render:
            continue
        cl = mask_class(o.name)
        if cl is None:
            continue
        ch = "R" if cl[0] else ("G" if cl[1] else "B")
        dr = draws[ch]
        me = o.data
        me.calc_loop_triangles()
        nv = len(me.vertices)
        if nv == 0 or len(me.loop_triangles) == 0:
            continue
        co = np.zeros(nv * 3)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        mw = np.array(o.matrix_world)
        co = co @ mw[:3, :3].T + mw[:3, 3]
        tri = np.zeros(len(me.loop_triangles) * 3, dtype=np.int64)
        me.loop_triangles.foreach_get("vertices", tri)
        P = co[tri.reshape(-1, 3)]                      # (n, 3, 3)
        z = P[:, :, 2]
        keep = ~((z.max(1) <= zmin) | (z.min(1) >= zmax))
        P = P[keep]
        inside = (P[:, :, 2].min(1) >= zmin) & (P[:, :, 2].max(1) <= zmax)
        # pixels : x = (X + M) * q ; y = (-Y + M) * q
        def px(pt):
            return ((pt[0] + MARGIN) * q, (-pt[1] + MARGIN) * q)
        for k in range(len(P)):
            tr = P[k]
            if inside[k]:
                pts = [px(tr[0]), px(tr[1]), px(tr[2])]
            else:
                poly = [tuple(v) for v in tr]
                for (zc, keep_above) in ((zmin, True), (zmax, False)):
                    out = []
                    n = len(poly)
                    for i in range(n):
                        a, b_ = poly[i], poly[(i + 1) % n]
                        ina = a[2] >= zc if keep_above else a[2] <= zc
                        inb = b_[2] >= zc if keep_above else b_[2] <= zc
                        if ina:
                            out.append(a)
                        if ina != inb:
                            tt = (zc - a[2]) / (b_[2] - a[2])
                            out.append((a[0] + (b_[0] - a[0]) * tt, a[1] + (b_[1] - a[1]) * tt, zc))
                    poly = out
                    if not poly:
                        break
                if len(poly) < 2:
                    continue
                pts = [px(v) for v in poly]
            dr.polygon(pts, fill=255, outline=255)
            ntri += 1
    out = []
    for c in "RGB":
        a = np.asarray(layers[c], dtype=np.float32) / 255.0
        a = a.reshape(th * ppc, ss, tw * ppc, ss).mean(axis=(1, 3))
        out.append((a * 255.0 + 0.5).astype(np.uint8))
    Image.fromarray(np.stack(out, -1), "RGB").save(path)
    dt = time.time() - t
    print("  mask triangles", ntri, flush=True)
    return dt


def render_occ(path, zmin=0.3):
    """Passe d'ids d'occultation, MÊME caméra et cadrage que « full » (pixels alignés) :
    pour chaque pixel, la surface visible donne
      R = rangée + 1 du point de la surface (floor(-y), 1..254) si sa hauteur z > zmin et que
          l'objet peut masquer un personnage (sinon 0 = sol / non occultant) ;
      G = id + 1 du bâtiment auquel appartient la surface (0 = aucun).
    compose.py en tire, par tuile, des « tranches » (rangée, bâtiment) que le jeu trie en Y avec
    les personnages : un personnage plus au nord qu'une surface haute passe DERRIÈRE (wagon,
    rocher, maison), au lieu d'être dessiné par-dessus (« marcher sur le wagon »).
    Cycles émissif, 1 échantillon, filtre ponctuel, sortie brute (vue Raw), PNG 8 bits."""
    sc = scene
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        cap = 0.0 if o.name.startswith(OCC_SKIP) else 1.0
        bid = 0
        for pre in ("walls_", "front_", "roof_", "awning_", "porch_", "floor_", "furn_", "ruin_"):
            if o.name.startswith(pre):
                try:
                    bid = int(o.name[len(pre):]) + 1
                except ValueError:
                    bid = 0
        o.pass_index = bid
        o.color = (cap, 0.0, 0.0, 1.0)
    mat = bpy.data.materials.get("_occ_emit")
    if mat is None:
        mat = bpy.data.materials.new("_occ_emit")
        mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        oi = nt.nodes.new("ShaderNodeObjectInfo")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Position"], sep.inputs[0])
        sepc = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(oi.outputs["Color"], sepc.inputs[0])

        def math_(op, a, b=None, v=None):
            n = nt.nodes.new("ShaderNodeMath")
            n.operation = op
            for i, x in enumerate((a, b)):
                if x is None:
                    continue
                if isinstance(x, (int, float)):
                    n.inputs[i].default_value = x
                else:
                    nt.links.new(x, n.inputs[i])
            return n.outputs[0]
        row = math_("FLOOR", math_("MULTIPLY", sep.outputs["Y"], -1.0))
        code = math_("MINIMUM", math_("MAXIMUM", math_("ADD", row, 1.0), 0.0), 254.0)
        # rangées hors carte au nord (< 0) : non occultant
        code = math_("MULTIPLY", code, math_("GREATER_THAN", row, -0.5))
        high = math_("GREATER_THAN", sep.outputs["Z"], zmin)
        r = math_("DIVIDE", math_("MULTIPLY", math_("MULTIPLY", code, high), sepc.outputs[0]), 255.0)
        g = math_("DIVIDE", oi.outputs["Object Index"], 255.0)
        comb = nt.nodes.new("ShaderNodeCombineColor")
        nt.links.new(r, comb.inputs[0])
        nt.links.new(g, comb.inputs[1])
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(comb.outputs[0], em.inputs["Color"])
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(em.outputs[0], out.inputs["Surface"])
    vl = sc.view_layers[0]
    saved = {"engine": sc.render.engine, "samples": sc.cycles.samples, "den": sc.cycles.use_denoising,
             "vt": sc.view_settings.view_transform, "look": sc.view_settings.look, "exp": sc.view_settings.exposure,
             "world": sc.world, "dither": sc.render.dither_intensity, "fw": sc.cycles.filter_width}
    hidden = []
    for o in bpy.data.objects:
        if o.type == "LIGHT" and not o.hide_render:
            o.hide_render = True
            hidden.append(o)
    vl.material_override = mat
    wm = bpy.data.worlds.get("_mask_w") or bpy.data.worlds.new("_mask_w")
    wm.use_nodes = True
    wm.node_tree.nodes["Background"].inputs[1].default_value = 0.0
    sc.world = wm
    sc.cycles.samples = 1
    sc.cycles.use_denoising = False
    sc.cycles.use_adaptive_sampling = False
    sc.cycles.filter_width = 0.01
    sc.view_settings.view_transform = "Raw"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    sc.render.dither_intensity = 0.0
    dt = render_chunked(path, grade_=False)
    vl.material_override = None
    for o in hidden:
        o.hide_render = False
    sc.cycles.samples = saved["samples"]
    sc.cycles.use_denoising = saved["den"]
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.filter_width = saved["fw"]
    sc.view_settings.view_transform = saved["vt"]
    sc.view_settings.look = saved["look"]
    sc.view_settings.exposure = saved["exp"]
    sc.world = saved["world"]
    sc.render.dither_intensity = saved["dither"]
    return dt



# ======================================================================= étalonnage (remplace grade de fw_scene)
BLOOM = float(os.environ.get("MALL_BLOOM", "0.55"))


def grade(path):
    """Étalonnage final (PIL) : saturation, contraste, clarté, relève des noirs + halo lumineux
    (« bloom ») autour des néons, écrans et hublots, comme les lueurs de la maquette."""
    from PIL import Image, ImageEnhance, ImageFilter, ImageChops
    im = Image.open(path).convert("RGB")
    if BLOOM > 0:
        hi = im.point(lambda v: max(0, v - 228) * 8)
        r1 = max(2, int(PPC_CUR * 0.25))
        b1 = hi.filter(ImageFilter.GaussianBlur(r1))
        b2 = hi.filter(ImageFilter.GaussianBlur(r1 * 4))
        glow = ImageChops.add(b1.point(lambda v: int(v * BLOOM)), b2.point(lambda v: int(v * BLOOM * 0.8)))
        im = ImageChops.add(im, glow)
    im = ImageEnhance.Color(im).enhance(SAT)
    im = ImageEnhance.Contrast(im).enhance(CON)
    im = im.filter(ImageFilter.UnsharpMask(radius=max(2, int(PPC_CUR * 0.3)), percent=30, threshold=2))
    lut = [int(LIFT + v * (255 - LIFT) / 255) for v in range(256)]
    im = im.point(lut * 3)
    im.save(path)


# ======================================================================= masque d'emprise : classes
# R = obstacle adossé au plan (murs, décors du plan), G = mobilier des modules, B = divers (info).
MASK_SOLID = ("walls_", "front_", "hullwalls", "props")
MASK_DECOR = ("furn_", "clutter")
MASK_SKIP = ("ground", "floor_", "roof_", "cut_", "_", "skirt", "hullwin")


def mask_class(name):
    if name.startswith(MASK_SKIP):
        return None
    if name.startswith(MASK_SOLID):
        return (1.0, 0.0, 0.0)
    if name.startswith(MASK_DECOR):
        return (0.0, 1.0, 0.0)
    return (0.0, 0.0, 1.0)


OCC_SKIP = ("ground", "floor_", "cut_", "_", "skirt")


def set_mode(mode):
    vl = scene.view_layers[0]
    for lc in vl.layer_collection.children:
        if lc.name == "roofs":
            lc.exclude = (mode == "int")


if __name__ == "__main__":
    t0 = time.time()
    build_materials()
    build_world()
    coll("roofs")
    cam = setup_render()
    t_build = time.time() - t0
    print("BUILD", round(t_build, 1), "s", flush=True)
    import hashlib
    info = {"tiles_md5": hashlib.md5("".join(TILES).encode()).hexdigest(), "seed": SEED, "ppc": PPC, "tilt_deg": TILT_DEG,
            "projection": "ground_square", "margin": MARGIN, "biome": "mall",
            "size": [W, H], "samples": SAMPLES, "build_s": round(t_build, 1), "renders": {}, "buildings": []}
    scene.render.use_persistent_data = True
    if "mask" in PASSES:
        dt = render_mask(os.path.join(OUT, "mask.png"))
        info["renders"]["mask"] = {"ppc": 4, "s": round(dt, 1)}
        print("MASK", round(dt, 1), "s", flush=True)
    if "full" in PASSES:
        pw, ph = frame(cam, -MARGIN, W + MARGIN, -MARGIN, H + MARGIN)
        dt = render_chunked(os.path.join(OUT, "full.png"))
        info["renders"]["full"] = {"px": [pw, ph], "s": round(dt, 1)}
        print("FULL", pw, ph, round(dt, 1), "s", flush=True)
    if "occ" in PASSES:
        pw, ph = frame(cam, -MARGIN, W + MARGIN, -MARGIN, H + MARGIN)
        dt = render_occ(os.path.join(OUT, "occ.png"))
        info["renders"]["occ"] = {"px": [pw, ph], "s": round(dt, 1)}
        print("OCC", round(dt, 1), "s", flush=True)
    for p_ in PASSES:
        if p_.startswith("crop:"):
            a_ = [float(v) for v in p_[5:].split(";")]
            frame(cam, *a_)
            dt = render(os.path.join(OUT, "crop_%d_%d.png" % (a_[0], a_[2])))
            print("CROP", round(dt, 1), "s", flush=True)
        if p_.startswith("view:"):
            a_ = [float(v) for v in p_[5:].split(";")]
            frame(cam, a_[0], a_[1], a_[2], a_[3], math.radians(a_[4]), int(a_[5]))
            dt = render(os.path.join(OUT, "view_%d_%d.png" % (a_[0], a_[2])))
            print("VIEW", round(dt, 1), "s", flush=True)
    if "int" in PASSES:
        # Intérieurs : par module fermé, SEULS son toit et le haut de son mur sud (front_) sont
        # masqués. Même caméra que « full », rendu par bordure (emprise + hauteur projetée).
        pw, ph = frame(cam, -MARGIN, W + MARGIN, -MARGIN, H + MARGIN)
        scene.render.use_border = True
        scene.render.use_crop_to_border = True
        tb = 0.0
        tW, tH = W + 2 * MARGIN, H + 2 * MARGIN
        up = int(math.ceil(4.6 * math.tan(TILT)))
        only = os.environ.get("MALL_INT_ONLY", "")
        for b in LAYOUT["buildings"]:
            bid = b["id"]
            x, y, w, h = b["rect"]
            reg = [x - 1, x + w + 1, y - up, y + h + 2]
            u0 = (reg[0] + MARGIN) / tW
            u1 = (reg[1] + MARGIN) / tW
            v0 = 1.0 - (reg[3] + MARGIN) / tH
            v1 = 1.0 - (reg[2] + MARGIN) / tH
            entry = {"id": bid, "rect": b["rect"],
                     "px": [int(round(max(u0, 0) * pw)), int(round((1 - min(v1, 1)) * ph)),
                            int(round(min(u1, 1) * pw)), int(round((1 - max(v0, 0)) * ph))]}
            info["buildings"].append(entry)
            outp = os.path.join(OUT, "b%d_in.png" % bid)
            if os.path.exists(outp) or (only and str(bid) not in only.split(";")):
                continue
            objs_off = [o for o in bpy.data.objects if o.name in ("roof_%d" % bid, "front_%d" % bid) or o.name.startswith("_sb%d_" % bid)]
            for o in objs_off:
                o.hide_render = True
            scene.render.border_min_x, scene.render.border_max_x = max(u0, 0), min(u1, 1)
            scene.render.border_min_y, scene.render.border_max_y = max(v0, 0), min(v1, 1)
            tb += render(outp + ".tmp.png")
            os.replace(outp + ".tmp.png", outp)
            for o in objs_off:
                o.hide_render = False
            print("  int", bid, round(tb, 1), flush=True)
        scene.render.use_border = False
        info["renders"]["interiors_s"] = round(tb, 1)
        print("INT", round(tb, 1), "s", flush=True)
    old = {}
    rp = os.path.join(OUT, "render.json")
    if os.path.exists(rp):
        try:
            old = json.load(open(rp))
        except Exception:
            old = {}
    if old.get("tiles_md5") == info["tiles_md5"]:
        for k_, v_ in old.get("renders", {}).items():
            info["renders"].setdefault(k_, v_)
        if not info["buildings"]:
            info["buildings"] = old.get("buildings", [])
    json.dump(info, open(rp, "w"), indent=1)
    json.dump(LAYOUT, open(os.path.join(OUT, "layout.json"), "w"))   # pour compose.py (collisions)
    print("DONE total", round(time.time() - t0, 1), "s", flush=True)
