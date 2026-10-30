"""Scène Blender complète du rez-de-chaussée du Carnaval hanté (parc d'attractions maudit façon
maquette docs/reference/cartes_2.png, colonne de gauche), construite depuis le layout JSON exporté
par tools/prerender/export_layout.gd (4e argument : res://data/worlds/world_04_haunted_carnival.tres),
rendue en Cycles. Même pipeline, mêmes passes et même projection que fw_scene.py / mall_scene.py.

Usage (bpy en module) :
  python3 hc_scene.py <layout.json> <out_dir> [ppc=24] [samples=16] [passes=full,int] [margin=6]
Passes : full (par morceaux, reprise possible) ; int (patch « sans toit » par bâtiment à toit :
         chapiteau, stands à auvent, tentes, roulottes, kiosques) ; mask (emprise au sol, vue
         zénithale) ; occ (ids d'occultation) ; crop:x0;x1;y0;y1 ; view:x0;x1;y0;y1;tilt;ppc
Sorties : full.png, b<id>_in.png, mask.png, occ.png, render.json, layout.json (pour compose.py).

PROJECTION (identique à fw_scene.py) : caméra orthographique inclinée de TILT (38°) vers le nord,
  pixel_aspect_x = 1/cos(TILT) ; px = (cx + M) * ppc ; py = (cy + M) * ppc - z * tan(TILT) * ppc.
Repère Blender : 1 unité = 1 case. X = colonne, Y = -rangée, Z = hauteur.

Contenu, DE NUIT (dominantes violet / magenta, touches rouge et or) : allées de terre et de pavés
jonchées de débris, GRANDE ROUE lumineuse au nord-ouest, MONTAGNES RUSSES (rails rouges sur
pylônes) qui encadrent le parc dans la marge et traversent la cour nord-est, CHAPITEAU ovale
rayé rouge / blanc (piste de cirque violette, gradins, mât, projecteurs violets), MANÈGES
(chaises volantes, tasses, carrousel), STANDS à auvent rayé, ROULOTTES, TENTES, kiosques,
PORTAIL d'entrée à tête de clown lumineuse, guirlandes d'ampoules et lampadaires, arbres morts et
forêt de sapins sombres autour (hors jeu). Les blocs génériques (NT, MB, frame, grade,
render_chunked, render_mask, render_occ) sont repris de fw_scene.py / mall_scene.py.
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
MARGIN = int(A[5]) if len(A) > 5 else 6
os.makedirs(OUT, exist_ok=True)

TILT_DEG = float(os.environ.get("HC_TILT", "38"))
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
    s = NT(name)
    n = s.noise(s.obj(), 6.0, 4, 0.5)
    s.done((0.03, 0.12, 0.16), 0.05, s.bump(n, 0.15, 0.02), 0.0)
    s.b.inputs["Emission Color"].default_value = (0.1, 0.5, 0.6, 1)
    s.b.inputs["Emission Strength"].default_value = 0.4
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




BLOOM = float(os.environ.get("HC_BLOOM", "0.7"))


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


# ======================================================================= matériaux du carnaval
NEON = {"warm": (1.0, 0.72, 0.42), "pink": (1.0, 0.25, 0.7), "magenta": (1.0, 0.15, 0.85), "red": (1.0, 0.12, 0.1),
        "violet": (0.6, 0.3, 1.0), "gold": (1.0, 0.8, 0.3), "white": (1.0, 0.92, 0.8), "cyan": (0.3, 0.9, 1.0), "green": (0.4, 1.0, 0.45)}
CANVAS = [(0.62, 0.08, 0.1), (0.75, 0.42, 0.08), (0.42, 0.12, 0.55), (0.1, 0.35, 0.5)]


def mat_stripes(name, c1, c2, w=0.5, rough=0.8, dirt=0.4):
    """Toile rayée (UV monde : u le long) : bandes c1 / c2 de largeur w, salissures, trame."""
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    t = s.m_("FRACT", s.m_("DIVIDE", u, w * 2))
    k = s.smooth(t, 0.48, 0.52)
    n = s.noise(s.obj(), 3.0, 5, 0.6)
    weave = s.noise(s.obj(), 60.0, 2, 0.5)
    col = s.mix(k, c1, c2)
    col = s.mix(s.smooth(n, 0.5, 0.85, 0.0, dirt), col, tuple(x * 0.45 for x in c1))
    col = s.mix(s.mul(weave, 0.15), col, tuple(x * 0.8 for x in c2))
    return s.done(col, rough, s.bump(n, 0.1, 0.03), 0.0)


def mat_dirt(name, base=(0.13, 0.09, 0.13), light=(0.24, 0.18, 0.22)):
    """Terre battue des allées : grain, flaques, traces, débris sombres."""
    s = NT(name)
    o = s.obj()
    n = s.noise(o, 14.0, 6, 0.7)
    n2 = s.noise(o, 0.9, 4, 0.6)
    n3 = s.noise(o, 4.0, 4, 0.6)
    col = s.mix(s.mul(n, 0.7), base, light)
    col = s.mix(s.smooth(n2, 0.55, 0.78, 0.0, 0.55), col, tuple(x * 0.6 for x in base))
    col = s.mix(s.smooth(n3, 0.7, 0.9, 0.0, 0.5), col, tuple(x * 0.4 for x in base))
    wet = s.smooth(n2, 0.66, 0.74)
    rough = s.sub(0.9, s.mul(wet, 0.75))
    s.done(col, normal=s.bump(s.mul(n, 0.5), 0.35, 0.02), metal=0.0, rough_sock=rough)
    return s.m


def mat_pavers(name, c1=(0.22, 0.21, 0.26), c2=(0.11, 0.105, 0.14), scale=2.2):
    """Pavés de la place et du parvis : petits carreaux irréguliers, joints sombres, mousse."""
    s = NT(name)
    o = s.obj()
    cell = s.voronoi(s.vmul(o, scale), 1.0, "Distance")
    col_ = s.voronoi(s.vmul(o, scale), 1.0, "Color")
    r = s.sep(col_)[0]
    joint = s.smooth(cell, 0.05, 0.12)
    n = s.noise(o, 1.0, 4, 0.6)
    col = s.mix(s.mul(r, 0.5), c1, c2)
    col = s.mix(s.smooth(n, 0.55, 0.8, 0.0, 0.5), col, (0.14, 0.2, 0.16))
    col = s.mix(s.sub(1.0, joint), (0.1, 0.08, 0.12), col)
    rg = s.add(0.55, s.mul(s.smooth(n, 0.6, 0.9), 0.35))
    s.done(col, normal=s.bump(joint, 0.4, 0.02), metal=0.0, rough_sock=rg)
    return s.m


def mat_grass(name, base=(0.1, 0.16, 0.11)):
    s = NT(name)
    o = s.obj()
    n = s.noise(o, 8.0, 6, 0.7)
    n2 = s.noise(o, 0.6, 3, 0.5)
    col = s.mix(s.mul(n, 0.8), base, tuple(x * 2.0 for x in base))
    col = s.mix(s.smooth(n2, 0.5, 0.8, 0.0, 0.6), col, (0.12, 0.09, 0.12))
    return s.done(col, 0.95, s.bump(n, 0.3, 0.03), 0.0)


def mat_bulbs(name, c, strength=6.0, pitch=0.35):
    """Guirlande : ampoules émissives régulières (UV u) sur fil sombre."""
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    t = s.m_("FRACT", s.m_("DIVIDE", u, pitch))
    k = s.smooth(s.m_("ABSOLUTE", s.sub(t, 0.5)), 0.2, 0.1)
    s.done((0.05, 0.04, 0.05), 0.6)
    s.l(s.mix(k, (0.0, 0.0, 0.0), c), s.b.inputs["Emission Color"])
    s.b.inputs["Emission Strength"].default_value = strength
    return s.m


def mat_clown_face(name):
    """Tête de clown : peau blanche émissive, joues roses, variations."""
    s = NT(name)
    n = s.noise(s.obj(), 4.0, 4, 0.5)
    col = s.mix(s.mul(n, 0.4), (0.62, 0.36, 0.85), (0.4, 0.18, 0.62))
    s.done(col, 0.5)
    s.b.inputs["Emission Color"].default_value = (0.6, 0.3, 1.0, 1)
    s.b.inputs["Emission Strength"].default_value = 0.22
    return s.m


def build_materials():
    mat_dirt("dirt", (0.1, 0.095, 0.12), (0.21, 0.19, 0.23))
    mat_dirt("dirt_dark", (0.12, 0.1, 0.13), (0.22, 0.18, 0.22))
    mat_pavers("pavers", (0.25, 0.23, 0.28), (0.11, 0.105, 0.14))
    mat_pavers("pavers_lot", (0.27, 0.25, 0.3), (0.12, 0.11, 0.15))
    mat_pavers("flags", (0.42, 0.35, 0.36), (0.13, 0.11, 0.14), 0.75)
    mat_simple("stone_ochre", (0.62, 0.42, 0.3), 0.85, 0.0, 0.35)
    mat_grass("grass")
    mat_grass("forest_floor", (0.1, 0.13, 0.14))
    mat_wood("plank", (0.42, 0.26, 0.24))
    mat_wood("plank_dark", (0.22, 0.13, 0.14))
    mat_wood("plank_painted", (0.55, 0.18, 0.3))
    mat_wood("floor_wood", (0.36, 0.22, 0.2))
    mat_plaster("canvas_white", (0.85, 0.78, 0.74), 0.85)
    mat_plaster("canvas_red", (0.6, 0.08, 0.1), 0.85)
    mat_plaster("canvas_purple", (0.36, 0.12, 0.5), 0.85)
    for i, c in enumerate(CANVAS):
        mat_stripes("stripes_%d" % i, c, (0.86, 0.8, 0.76), 0.5)
        mat_stripes("stripes_fine_%d" % i, c, (0.86, 0.8, 0.76), 0.25)
    mat_stripes("stripes_tent", (0.62, 0.08, 0.1), (0.86, 0.8, 0.76), 0.9, dirt=0.5)
    mat_stripes("stripes_purple", (0.4, 0.1, 0.55), (0.86, 0.75, 0.85), 0.6)
    mat_panels("brick", (0.36, 0.17, 0.15), (0.12, 0.07, 0.07), 0.55, 0.22, 0.02, 0.18, 0.85, 0.0, 0.45)
    mat_panels("brick_dark", (0.22, 0.12, 0.13), (0.08, 0.05, 0.06), 0.55, 0.22, 0.02, 0.18, 0.85, 0.0, 0.5)
    mat_wood("boards_dark", (0.2, 0.12, 0.12))
    mat_panels("roof_rust", (0.3, 0.14, 0.1), (0.1, 0.05, 0.05), 0.45, 3.0, 0.03, 0.25, 0.7, 0.2, 0.55)
    mat_panels("roof_tin", (0.2, 0.17, 0.22), (0.08, 0.07, 0.1), 0.45, 3.0, 0.03, 0.2, 0.5, 0.5, 0.5)
    mat_simple("metal_dark", (0.08, 0.08, 0.1), 0.45, 0.7, 0.2)
    mat_simple("metal_mid", (0.3, 0.3, 0.34), 0.45, 0.6, 0.2)
    mat_simple("iron_red", (0.55, 0.08, 0.08), 0.45, 0.5, 0.3)
    mat_simple("rail_red", (0.7, 0.1, 0.1), 0.35, 0.6, 0.2)
    mat_simple("rust", (0.35, 0.16, 0.08), 0.8, 0.3, 0.4)
    mat_simple("gold", (0.9, 0.65, 0.2), 0.3, 0.9, 0.2)
    mat_simple("brass", (0.6, 0.45, 0.15), 0.35, 0.8, 0.2)
    mat_simple("stone", (0.3, 0.28, 0.34), 0.85, 0.0, 0.35)
    mat_simple("stone_dark", (0.16, 0.14, 0.2), 0.9, 0.0, 0.35)
    mat_simple("piste", (0.3, 0.14, 0.4), 0.7, 0.0, 0.3)
    mat_simple("piste_ring", (0.72, 0.12, 0.16), 0.6, 0.0, 0.2)
    mat_simple("sawdust", (0.5, 0.4, 0.28), 0.95, 0.0, 0.4)
    mat_simple("seat_red", (0.6, 0.1, 0.14), 0.6, 0.0, 0.2)
    mat_simple("seat_blue", (0.1, 0.25, 0.55), 0.6, 0.0, 0.2)
    mat_simple("seat_yellow", (0.85, 0.65, 0.15), 0.6, 0.0, 0.2)
    mat_simple("seat_teal", (0.1, 0.5, 0.5), 0.6, 0.0, 0.2)
    mat_simple("plush", (0.75, 0.5, 0.3), 0.95, 0.0, 0.35)
    mat_simple("plush_pink", (0.85, 0.4, 0.6), 0.95, 0.0, 0.35)
    mat_simple("cloth_purple", (0.28, 0.1, 0.4), 0.9, 0.0, 0.3)
    mat_simple("trunk", (0.14, 0.09, 0.1), 0.9, 0.0, 0.4, 2.0)
    mat_simple("pine", (0.14, 0.26, 0.22), 0.95, 0.0, 0.5, 3.0)
    mat_simple("pine_dark", (0.09, 0.17, 0.16), 0.95, 0.0, 0.5, 3.0)
    mat_simple("debris", (0.2, 0.16, 0.18), 0.9, 0.0, 0.5)
    mat_simple("paper", (0.42, 0.38, 0.4), 0.9, 0.0, 0.3)
    mat_simple("water", (0.05, 0.15, 0.2), 0.05, 0.0, 0.1)
    mat_simple("mirror", (0.6, 0.7, 0.85), 0.03, 0.9, 0.05)
    mat_simple("balloon_r", (0.8, 0.1, 0.15), 0.25, 0.0, 0.1)
    mat_simple("balloon_p", (0.6, 0.15, 0.7), 0.25, 0.0, 0.1)
    mat_simple("balloon_y", (0.9, 0.7, 0.1), 0.25, 0.0, 0.1)
    mat_simple("skin", (0.9, 0.7, 0.6), 0.6, 0.0, 0.2)
    mat_simple("hair_red", (0.75, 0.1, 0.1), 0.9, 0.0, 0.3)
    mat_simple("hair_violet", (0.42, 0.1, 0.7), 0.9, 0.0, 0.3)
    mat_clown_face("clown_face")
    mat_glass("glass", (0.5, 0.4, 0.7), 0.3)
    mat_glass("glass_dark", (0.2, 0.15, 0.3), 0.6)
    for k, c in NEON.items():
        mat_emit("neon_" + k, c, 7.0)
        mat_emit("lamp_" + k, c, 3.5)
        mat_bulbs("bulbs_" + k, c, 7.0)
    mat_emit("bulb_dim", (0.6, 0.4, 0.3), 1.0)
    mat_emit("spot_violet", (0.5, 0.2, 1.0), 2.0)
    mat_emit("eyes", (1.0, 0.15, 0.1), 12.0)
    mat_emit("eyes_glow", (0.75, 1.0, 0.25), 14.0)
    mat_emit("sky_dark", (0.004, 0.003, 0.01), 1.0)
    mat_lines("paint_white", (0.7, 0.68, 0.7))
    mat_hazard("hazard")
    mat_stars("stars")


# ======================================================================= analyse du layout
ROOMS = LAYOUT.get("rooms", [])
ROOM_BY_ID = {r["id"]: r for r in ROOMS}
MODS = C.get("modules", [])
MOD_BY_ROOM = {m["room"]: m for m in MODS}
MOD_BY_BLD = {m["building"]: m for m in MODS if m.get("building", -1) >= 0}
BLD = {b["id"]: b for b in LAYOUT.get("buildings", [])}
DOOR_CELLS = {tuple(d["cell"]): d for d in LAYOUT.get("doors", [])}
EXTRACT = set(tuple(c) for c in LAYOUT.get("extraction", []))
TENT = C.get("tent", {"rect": [24, 35, 25, 19], "c": [36.5, 44.5], "r": [11.5, 8.5]})
TC = Vector((TENT["c"][0], Y(TENT["c"][1])))
TR = (TENT["r"][0], TENT["r"][1])
PLAZA = C.get("plaza", [18, 30, 36, 30])
LOT = C.get("lot", [22, 111, 28, 14])
GATE = C.get("gate", [18, 109, 36, 2])
GATE_OPEN = C.get("gate_open", [33, 109, 6, 2])
PLAZA_E = C.get("plaza_e", {"c": [36.5, 47.0], "r": [25.0, 19.5]})
PATHS = C.get("paths", [])
YARDS = C.get("yards", [])
RIDES = C.get("rides", [])
COASTER = C.get("coaster", [])
COASTER_IN = C.get("coaster_in", [])


def tent_d(x, y):
    dx = (x + 0.5 - TENT["c"][0]) / TR[0]
    dy = (y + 0.5 - TENT["c"][1]) / TR[1]
    return dx * dx + dy * dy


def in_rect(r, x, y):
    return r[0] <= x < r[0] + r[2] and r[1] <= y < r[1] + r[3]


CELL_ROOM = {}
_area = {}
for r in ROOMS:
    x, y, w, h = r["rect"]
    a = w * h
    big = r.get("tags") and r["tags"][0] == "big_top"
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if big and tent_d(xx, yy) > 1.0:
                continue
            if big or a < _area.get((xx, yy), 1 << 30):
                _area[(xx, yy)] = 0 if big else a
                CELL_ROOM[(xx, yy)] = r["id"]


def role_of(rid):
    r = ROOM_BY_ID.get(rid)
    return r["tags"][0] if r and r.get("tags") else "alley"


CELL_MOD = {}
for m in MODS:
    x, y, w, h = m["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if m.get("ellipse") and tent_d(xx, yy) > 1.0:
                continue
            CELL_MOD.setdefault((xx, yy), m)
CELL_BLD = {}
for b in LAYOUT.get("buildings", []):
    x, y, w, h = b["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if b["arch"] == "big_top" and tent_d(xx, yy) > 1.0:
                continue
            CELL_BLD.setdefault((xx, yy), b["id"])
RIDE_CELLS = {}
for rd in RIDES:
    cx, cy = rd["c"]
    rr = rd["r"]
    for yy in range(int(cy - rr) - 1, int(cy + rr) + 2):
        for xx in range(int(cx - rr) - 1, int(cx + rr) + 2):
            if math.hypot(xx + 0.5 - cx, yy + 0.5 - cy) <= rr:
                RIDE_CELLS[(xx, yy)] = rd["kind"]
COASTER_CELLS = set()
for i in range(len(COASTER_IN) - 1):
    a, b = COASTER_IN[i], COASTER_IN[i + 1]
    n = max(abs(b[0] - a[0]), abs(b[1] - a[1]))
    for k in range(int(n) + 1):
        t = k / max(n, 1)
        COASTER_CELLS.add((int(a[0] + (b[0] - a[0]) * t), int(a[1] + (b[1] - a[1]) * t)))
GATE_CELLS = set((x, y) for y in range(GATE[1], GATE[1] + GATE[3]) for x in range(GATE[0], GATE[0] + GATE[2]))
GAME_CELLS = set()
ENC_CELLS = set(tuple(c) for c in C.get("enclosure", []))
ENC_R = tuple(C.get("enc_r", [21.5, 16.5]))
SPOTS = []           # projecteurs (x, y_blender, z, cible (x, y, z), couleur, énergie)


def enc_d(x, y):
    dx = (x + 0.5 - TENT["c"][0]) / ENC_R[0]
    dy = (y + 0.5 - TENT["c"][1]) / ENC_R[1]
    return dx * dx + dy * dy
BIG = {"hc_bumper_car": (2, 1), "hc_food_cart": (2, 1), "hc_cage": (2, 1), "hc_bleachers": (3, 1), "hc_ring_barrier": (2, 1), "hc_shooting_counter": (2, 1)}
for key in ("container_spawns", "hiding_spot_spawns", "prop_spawns"):
    for sp in LAYOUT.get(key, []):
        sx, sy = sp.get("size", [1, 1])
        if [sx, sy] == [1, 1] and sp.get("kind") in BIG:
            sx, sy = BIG[sp["kind"]]
        x0 = sp["cell"][0] - (sx - 1) // 2
        for yy in range(sp["cell"][1] - sy + 1, sp["cell"][1] + 1):
            for xx in range(x0, x0 + sx):
                GAME_CELLS.add((xx, yy))
for d in DOOR_CELLS:
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            GAME_CELLS.add((d[0] + dx, d[1] + dy))

H_STAND = 1.6        # murs des stands (comptoir + poteaux)
H_WALL = 2.0         # murs pleins (roulottes, tentes, kiosques)
H_FENCE = 1.2        # palissade du parc
H_CUT = 0.8          # haut du mur sud masqué en passe int
H_DOOR = 1.0
LAMPS = []           # (x, y_blender, z, couleur, énergie)
GLOWS = []           # lumières ponctuelles (x, y, z, couleur, énergie)


def canvas_of(m):
    return int(m.get("color", 0)) % len(CANVAS) if m else 0


# ======================================================================= sol
def floor_mat(rid, cell):
    role = role_of(rid)
    x, y = cell
    if tile(x, y) == 1:
        if role == "plaza" and enc_d(x, y) < 1.0:
            return "flags"
        if role in ("plaza", "entrance", "avenue"):
            return "pavers_lot" if role == "entrance" else "pavers"
        # herbe rase le long des palissades des cours et des allées (herbes folles)
        if (tile(x - 1, y) == 3 or tile(x + 1, y) == 3 or tile(x, y - 1) == 3 or tile(x, y + 1) == 3) and (x * 7 + y * 13) % 3 == 0:
            return "grass"
        return "dirt"
    if role == "big_top":
        return "sawdust"
    if role.startswith("caravan") or role == "ticket_booth":
        return "floor_wood"
    if role.startswith("tent"):
        return "dirt_dark"
    if role == "service_yard":
        return "dirt_dark"
    return "plank"


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
    # sol hors jeu : herbe sombre / sous-bois sous tout, légèrement enfoncé
    st = MB()
    m = 14
    st.poly([(-m, Y(H + m), -0.05), (W + m, Y(H + m), -0.05), (W + m, Y(-m), -0.05), (-m, Y(-m), -0.05)], "forest_floor",
            [(-m, Y(H + m)), (W + m, Y(H + m)), (W + m, Y(-m)), (-m, Y(-m))])
    # herbe entre allées et palissade (cases VOID intérieures murées : rien ; cases hors grille)
    st.to_object("_outside", "world")
    # piste du chapiteau : disque de sciure + anneau rouge + étoile ; marquages du parvis
    mk = MB()
    cx, cy = TC.x, TC.y
    seg = 40
    for k in range(seg):
        a0 = k / seg * math.tau
        a1 = (k + 1) / seg * math.tau
        r0, r1 = 0.62, 0.72
        mk.poly([(cx + math.cos(a0) * TR[0] * r0, cy + math.sin(a0) * TR[1] * r0, 0.012),
                 (cx + math.cos(a1) * TR[0] * r0, cy + math.sin(a1) * TR[1] * r0, 0.012),
                 (cx + math.cos(a1) * TR[0] * r1, cy + math.sin(a1) * TR[1] * r1, 0.012),
                 (cx + math.cos(a0) * TR[0] * r1, cy + math.sin(a0) * TR[1] * r1, 0.012)], "piste_ring")
        mk.poly([(cx, cy, 0.01), (cx + math.cos(a0) * TR[0] * r0, cy + math.sin(a0) * TR[1] * r0, 0.01),
                 (cx + math.cos(a1) * TR[0] * r0, cy + math.sin(a1) * TR[1] * r0, 0.01)], "piste")
    for k in range(5):
        a = k / 5 * math.tau + math.pi / 2
        b = a + math.tau * 2 / 5
        mk.poly([(cx + math.cos(a) * 2.2, cy + math.sin(a) * 1.7, 0.014), (cx + math.cos(b) * 2.2, cy + math.sin(b) * 1.7, 0.014),
                 (cx, cy, 0.014)], "gold")
    for (ex, ey) in EXTRACT:
        mk.box(ex + 0.06, Y(ey + 0.94), 0.0, ex + 0.94, Y(ey + 0.06), 0.01, "hazard")
    # passage piéton / tapis du portail
    gx, gy, gw, gh = GATE_OPEN
    for k in range(gw * 2):
        mk.box(gx + k * 0.5 + 0.05, Y(gy + gh + 1.8), 0.0, gx + k * 0.5 + 0.3, Y(gy + gh + 0.2), 0.006, "paint_white")
    mk.to_object("ground_marks", "world")


# ======================================================================= murs, palissades, portails
SIDES = (("S", 0, 1), ("N", 0, -1), ("E", 1, 0), ("W", -1, 0))


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


def wall_kind(x, y):
    """'ride' (disque de manège), 'coaster' (pylône), 'gate' (portail), 'tent' (anneau du
    chapiteau), 'bld' (bâtiment à toit), 'stand' (stand ouvert), 'exit' (cour de sortie),
    'fence' (palissade du parc)."""
    if (x, y) in RIDE_CELLS:
        return "ride"
    if (x, y) in COASTER_CELLS:
        return "coaster"
    if (x, y) in GATE_CELLS:
        return "gate"
    if (x, y) in ENC_CELLS:
        return "enclosure"
    m = CELL_MOD.get((x, y))
    if m is not None:
        if m.get("ellipse"):
            return "tent"
        if m["roof"]:
            return "bld"
        return "exit" if m["slot"] == "exit" else "stand"
    return "fence"


def wall_h(x, y):
    k = wall_kind(x, y)
    m = CELL_MOD.get((x, y))
    if m is not None and m["slot"] == "hall":
        return H_WALL + 0.4
    return {"ride": 0.0, "coaster": 0.0, "gate": 0.0, "tent": 0.0, "enclosure": 0.0, "bld": H_WALL, "stand": H_STAND, "exit": H_FENCE, "fence": H_FENCE}[k]


def build_walls():
    mbs = {}
    lights = MB()

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
            if k in ("ride", "coaster", "gate", "tent", "enclosure"):
                continue
            h = wall_h(x, y)
            b = CELL_BLD.get((x, y))
            m = CELL_MOD.get((x, y))
            south_row = b is not None and y == BLD[b]["rect"][1] + BLD[b]["rect"][3] - 1
            if k == "fence" or k == "exit":
                # palissade : planches verticales, lisses, guirlande d'ampoules au sommet
                tg = target(x, y)
                broken = (x * 13 + y * 7) % 11 == 0
                hh_ = h * (0.55 if broken else 1.0)
                tg.box(x, Y(y + 1) + 0.3, 0.0, x + 1, Y(y) - 0.3, hh_, "plank_dark" if (x + y) % 3 else "plank_painted")
                tg.box(x, Y(y + 1) + 0.26, hh_ - 0.08, x + 1, Y(y) - 0.26, hh_, "plank")
                if broken:
                    tg.box(x + 0.1, Y(y + 1) + 0.28, hh_, x + 0.3, Y(y) - 0.28, h + 0.1, "plank_dark", rot=0.35)
                if (x * 7 + y * 3) % 4 == 0:
                    tg.box(x + 0.4, Y(y + 1) + 0.25, 0.0, x + 0.6, Y(y) - 0.25, h + 0.25, "plank_dark")
                if k == "fence" and (x * 5 + y * 11) % 9 == 0:
                    rng_t = random.Random(x * 31 + y)
                    tg.cyl(x + 0.5, Y(y + 0.5), 0.0, 2.4, 0.16, "trunk", 7, r2=0.08)
                    for j in range(4):
                        a = j / 4 * math.tau + rng_t.random()
                        z0 = 1.3 + j * 0.25
                        tg.seg((x + 0.5, Y(y + 0.5), z0), (x + 0.5 + math.cos(a) * 1.1, Y(y + 0.5) + math.sin(a) * 1.1, z0 + 1.1), 0.06, "trunk", 5, r2=0.02)
                # ampoules seulement sur les faces donnant sur une allée
                for sd, dx, dy in SIDES:
                    if walk(x + dx, y + dy) and (x + y) % 2 == 0:
                        lights.sphere(x + 0.5 + dx * 0.36, Y(y + 0.5) - dy * 0.36, h + 0.05, 0.09, "neon_warm" if (x // 3 + y) % 2 else "neon_magenta", 1)
                continue
            if k == "stand" and m["slot"] == "hall":
                k = "bld"
            if k == "stand":
                # stand ouvert : comptoir bas devant (côté façade), poteaux, cloisons de planches
                fx, fy = m.get("facade", [0, 1])
                is_front = (fy == 1 and y == m["rect"][1] + m["rect"][3] - 1) or (fy == -1 and y == m["rect"][1]) \
                    or (fx == 1 and x == m["rect"][0] + m["rect"][2] - 1) or (fx == -1 and x == m["rect"][0])
                tg = target(x, y)
                if is_front and (x, y) not in DOOR_CELLS:
                    tg.box(x, Y(y + 1) + 0.2, 0.0, x + 1, Y(y) - 0.2, 0.8, "plank_painted")
                    tg.box(x - 0.02, Y(y + 1) + 0.15, 0.78, x + 1.02, Y(y) - 0.15, 0.86, "plank")
                    tg.box(x + 0.42, Y(y + 1) + 0.4, 0.0, x + 0.58, Y(y) - 0.4, 2.6, "plank_dark")
                else:
                    for side, dx, dy in SIDES:
                        nt_ = tile(x + dx, y + dy)
                        if nt_ == 3:
                            continue
                        face(tg, x, y, side, 0.0, h, "plank_painted" if (x + y) % 2 else "plank")
                    tg.poly([(x, Y(y + 1), h), (x + 1, Y(y + 1), h), (x + 1, Y(y), h), (x, Y(y), h)], "plank_dark")
                    tg.box(x + 0.42, Y(y + 1) + 0.4, h, x + 0.58, Y(y) - 0.4, 2.6, "plank_dark")
                continue
            # bâtiment à toit : roulotte (bois peint), tente (toile), kiosque (bois rayé)
            arch = BLD[b]["arch"] if b is not None else (m["arch"] if m is not None else "")
            if arch in ("hangar", "workshop", "museum", "arcade"):
                wmat = "brick" if m["room"] % 2 == 0 else "brick_dark"
            elif arch in ("mirrors", "freaks", "theatre"):
                wmat = "canvas_red" if (x + y) % 2 == 0 else "canvas_white"
            elif arch == "ticket_booth":
                wmat = "stripes_fine_0"
            else:
                wmat = "plank_painted" if (x // 2 + y) % 2 == 0 else "plank"
            for side, dx, dy in SIDES:
                nx, ny = x + dx, y + dy
                nt_ = tile(nx, ny)
                if nt_ == 3 and wall_kind(nx, ny) not in ("ride", "coaster", "gate", "tent", "enclosure"):
                    nh = wall_h(nx, ny)
                    if nh >= h - 1e-3:
                        continue
                    z0 = nh
                elif nt_ == 0:
                    z0 = -0.05
                else:
                    z0 = 0.0
                if south_row and h > H_CUT:
                    if z0 < H_CUT:
                        face(target(x, y), x, y, side, z0, H_CUT, wmat)
                    face(target(x, y, True), x, y, side, max(z0, H_CUT), h, wmat)
                else:
                    face(target(x, y), x, y, side, z0, h, wmat)
                # fenêtre ronde éclairée sur la façade sud des roulottes
                if side == "S" and arch in ("caravan", "director_caravan") and nt_ != 3 and x % 2 == 1:
                    target(x, y, south_row).cyl(x + 0.5, Y(y + 1) - 0.02, 0.85, 0.9, 0.2, "lamp_warm" if arch == "caravan" else "neon_violet", 12, axis="Y")
            tg2 = target(x, y, south_row)
            tg2.poly([(x, Y(y + 1), h), (x + 1, Y(y + 1), h), (x + 1, Y(y), h), (x, Y(y), h)], "plank_dark")
            if south_row:
                target(x, y).poly([(x, Y(y + 1), H_CUT), (x + 1, Y(y + 1), H_CUT), (x + 1, Y(y), H_CUT), (x, Y(y), H_CUT)], "metal_dark")
    # portes : encadrement + linteau (le jeu dessine le battant) ; lanterne au-dessus
    for (dx_, dy_), d in DOOR_CELLS.items():
        bid = CELL_BLD.get((dx_, dy_))
        m = CELL_MOD.get((dx_, dy_))
        hh = H_WALL if bid is not None else H_STAND
        south = bid is not None and dy_ == BLD[bid]["rect"][1] + BLD[bid]["rect"][3] - 1
        tg = mbs.setdefault(("front_%d" % bid) if south else (("walls_%d" % bid) if bid is not None else "hullwalls"), MB())
        X0, X1, YN, YS = dx_, dx_ + 1, Y(dy_), Y(dy_ + 1)
        locked = d.get("state", 1) == 2
        if m is not None and m.get("ellipse"):
            continue   # entrées du chapiteau : traitées par build_big_top
        if not d["vertical"]:
            tg.box(X0, YS + 0.3, H_DOOR, X1, YN - 0.3, hh, "plank_dark")
            for ex in (X0, X1 - 0.1):
                tg.box(ex, YS + 0.25, 0.0, ex + 0.1, YN - 0.25, H_DOOR + 0.05, "plank_dark")
        else:
            tg.box(X0 + 0.3, YS, H_DOOR, X1 - 0.3, YN, hh, "plank_dark")
            for ey in (YS, YN - 0.1):
                tg.box(X0 + 0.25, ey, 0.0, X1 - 0.25, ey + 0.1, H_DOOR + 0.05, "plank_dark")
        mbs.setdefault("ground_door", MB()).box(X0 + 0.05, YS + 0.05, 0.0, X1 - 0.05, YN - 0.05, 0.012, "plank")
        col = "red" if locked else ("cyan" if (dx_ * 3 + dy_) % 9 == 0 else ("green" if (dx_ + dy_ * 5) % 11 == 0 else "warm"))
        lights.sphere(dx_ + 0.5, Y(dy_) - 0.5, hh + 0.15, 0.1, "lamp_" + col, 1)
        GLOWS.append((dx_ + 0.5, Y(dy_) - 0.5, hh + 0.2, NEON[col], 0.4))
    for k, mb in mbs.items():
        mb.to_object(k, "world")
    lights.to_object("_wall_lights", "world")


# ======================================================================= toits (auvents, roulottes, tentes)
def roof_stand(mb, b, m, rng):
    """Auvent rayé incliné (haut au fond, bas vers la façade) sur poteaux, frise festonnée."""
    x, y, w, h = b["rect"]
    ci = canvas_of(m)
    fx, fy = m.get("facade", [0, 1])
    z_back, z_front = 3.1, 2.5
    X0, X1, YN, YS = x - 0.15, x + w + 0.15, Y(y) + 0.15, Y(y + h) - 0.15
    if fy == 1:      # façade au sud : haut au nord
        mb.poly([(X0, YS, z_front), (X1, YS, z_front), (X1, YN, z_back), (X0, YN, z_back)], "stripes_%d" % ci,
                [(X0, 0), (X1, 0), (X1, h), (X0, h)])
    elif fy == -1:
        mb.poly([(X0, YS, z_back), (X1, YS, z_back), (X1, YN, z_front), (X0, YN, z_front)], "stripes_%d" % ci,
                [(X0, 0), (X1, 0), (X1, h), (X0, h)])
    elif fx == 1:
        mb.poly([(X0, YS, z_back), (X1, YS, z_front), (X1, YN, z_front), (X0, YN, z_back)], "stripes_%d" % ci,
                [(YS, 0), (YS, w), (YN, w), (YN, 0)])
    else:
        mb.poly([(X0, YS, z_front), (X1, YS, z_back), (X1, YN, z_back), (X0, YN, z_front)], "stripes_%d" % ci,
                [(YS, w), (YS, 0), (YN, 0), (YN, w)])
    # dessous (face visible de l'intérieur) non nécessaire ; frise festonnée sur le bord bas
    if fy == 1:
        pts = [(X0 + k * 0.5, YS, z_front - 0.12) for k in range(int((X1 - X0) / 0.5) + 1)]
        for p in pts:
            mb.sphere(p[0], p[1] - 0.02, p[2], 0.14, "stripes_fine_%d" % ci, 1)
    # lambeaux de toile qui pendent (auvent déchiré) et lampions sous l'auvent
    if rng.random() < 0.6:
        for k in range(rng.randint(2, 4)):
            fx0 = x + rng.uniform(0.3, w - 0.8)
            yy = YS if fy == 1 else (YN if fy == -1 else Y(y + rng.uniform(1, h - 1)))
            mb.poly([(fx0, yy - 0.02, z_front - 0.1), (fx0 + 0.45, yy - 0.02, z_front - 0.1), (fx0 + 0.2, yy - 0.06, z_front - rng.uniform(0.5, 0.9))],
                     "stripes_fine_%d" % ci)
    for k in range(int(w)):
        mb.sphere(x + 0.5 + k, (YS if fy == 1 else YN) - 0.05, z_front - 0.25, 0.09, "lamp_warm" if (k + int(x)) % 3 else "lamp_magenta", 1)
    # fanion
    mb.cyl(x + w / 2, Y(y + 0.6), z_back, z_back + 0.9, 0.04, "metal_dark", 6)
    mb.poly([(x + w / 2, Y(y + 0.6), z_back + 0.9), (x + w / 2 + 0.7, Y(y + 0.6), z_back + 0.75), (x + w / 2, Y(y + 0.6), z_back + 0.6)], "canvas_red")


def roof_caravan(mb, b, m, rng):
    """Toit bombé de roulotte : arches en bois peint, lanterneau, cheminée."""
    x, y, w, h = b["rect"]
    ci = canvas_of(m)
    z = H_WALL
    n = 10
    X0, X1 = x - 0.08, x + w + 0.08
    for k in range(n):
        f0, f1 = k / n, (k + 1) / n
        y0, y1 = Y(y) + 0.08 - (h + 0.16) * f0, Y(y) + 0.08 - (h + 0.16) * f1
        z0 = z + math.sin(f0 * math.pi) * 0.85
        z1 = z + math.sin(f1 * math.pi) * 0.85
        mb.poly([(X0, y0, z0), (X1, y0, z0), (X1, y1, z1), (X0, y1, z1)], "stripes_%d" % ci if k % 2 else "plank_painted",
                [(X0, k), (X1, k), (X1, k + 1), (X0, k + 1)])
    mb.cyl(x + w - 0.8, Y(y + 1.0), z + 0.4, z + 1.1, 0.12, "metal_dark", 8)
    mb.box(x + 0.8, Y(y + h / 2 + 0.5), z + 0.45, x + w - 0.8, Y(y + h / 2 - 0.5), z + 0.6, "glass_dark")
    mb.box(x - 0.1, Y(y + h) - 0.1, z - 0.1, x + w + 0.1, Y(y + h) + 0.05, z + 0.05, "gold")
    mb.box(x - 0.1, Y(y) - 0.05, z - 0.1, x + w + 0.1, Y(y) + 0.1, z + 0.05, "gold")
    # roues à rayons (dans l'épaisseur des murs latéraux), timon, marchepied devant la porte
    for sx in (x + 0.12, x + w - 0.12):
        for wy in (y + 1.3, y + h - 1.3):
            mb.cyl(sx, Y(wy), 0.55, 0.12, 0.55, "plank_dark", 14, axis="X")
            mb.cyl(sx + (0.03 if sx > x + w / 2 else -0.03), Y(wy), 0.55, 0.13, 0.12, "gold", 8, axis="X")
            for k in range(6):
                a_ = k / 6 * math.pi
                mb.seg((sx, Y(wy) + math.cos(a_) * 0.5, 0.55 + math.sin(a_) * 0.5), (sx, Y(wy) - math.cos(a_) * 0.5, 0.55 - math.sin(a_) * 0.5), 0.025, "plank", 4)
    for (dx_, dy_), d in DOOR_CELLS.items():
        if CELL_BLD.get((dx_, dy_)) != b["id"]:
            continue
        # marchepied de trois marches, lanterne suspendue à la porte
        sx_, sy_ = (0, 1) if not d["vertical"] else ((1 if dx_ >= x + w - 1 else -1), 0)
        if not d["vertical"]:
            sy_ = 1 if dy_ >= y + h - 1 else -1
        for j in range(3):
            o_ = 1.0 + j * 0.25
            px, py = dx_ + 0.5 + sx_ * (o_ - 0.5), dy_ + 0.5 + sy_ * (o_ - 0.5)
            mb.box(px - 0.4, Y(py + 0.14), 0.0, px + 0.4, Y(py - 0.14), 0.36 - j * 0.11, "plank")
        lx, ly = dx_ + 0.5 + sx_ * 0.62 + (0.45 if sy_ else 0), dy_ + 0.5 + sy_ * 0.62 + (0.45 if sx_ else 0)
        mb.seg((lx, Y(ly), H_DOOR + 0.9), (lx, Y(ly), H_DOOR + 0.55), 0.015, "metal_dark", 3)
        mb.sphere(lx, Y(ly), H_DOOR + 0.42, 0.13, "lamp_warm", 1, 1.0, 1.0, 1.3)
        LAMPS.append((lx, Y(ly) - 0.2, H_DOOR + 0.4, NEON["warm"], 0.45))
    # timon (côté nord) et coffre à outils sous la caisse
    mb.seg((x + w / 2 - 0.3, Y(y) + 0.05, 0.4), (x + w / 2, Y(y) + 1.4, 0.15), 0.05, "plank_dark", 5)
    mb.seg((x + w / 2 + 0.3, Y(y) + 0.05, 0.4), (x + w / 2, Y(y) + 1.4, 0.15), 0.05, "plank_dark", 5)
    mb.cyl(x + w / 2, Y(y) + 1.45, 0.15, 0.06, 0.4, "metal_dark", 6, axis="X")


def roof_tent(mb, b, m, rng, cone="stripes_tent"):
    """Tente ronde : cône de toile rayée sur le cercle inscrit, mât, fanion, ampoules."""
    x, y, w, h = b["rect"]
    cx, cy = x + w / 2, Y(y + h / 2)
    rx, ry = w / 2 + 0.2, h / 2 + 0.2
    z0, z1 = H_WALL - 0.05, H_WALL + 2.2
    seg = 28
    for k in range(seg):
        a0 = k / seg * math.tau
        a1 = (k + 1) / seg * math.tau
        mb.poly([(cx + math.cos(a0) * rx, cy + math.sin(a0) * ry, z0), (cx + math.cos(a1) * rx, cy + math.sin(a1) * ry, z0), (cx, cy, z1)],
                cone, [(k * 1.0, 0), (k * 1.0 + 1.0, 0), (k * 1.0 + 0.5, 3.0)])
        mb.sphere(cx + math.cos(a0) * rx, cy + math.sin(a0) * ry, z0 + 0.1, 0.09, "lamp_warm" if k % 2 else "lamp_pink", 1)
    # pan de toile qui retombe (bord)
    for k in range(seg):
        a0 = k / seg * math.tau
        a1 = (k + 1) / seg * math.tau
        mb.poly([(cx + math.cos(a0) * rx, cy + math.sin(a0) * ry, z0 - 0.35), (cx + math.cos(a1) * rx, cy + math.sin(a1) * ry, z0 - 0.35),
                 (cx + math.cos(a1) * rx, cy + math.sin(a1) * ry, z0), (cx + math.cos(a0) * rx, cy + math.sin(a0) * ry, z0)], "canvas_red" if k % 2 else "canvas_white")
    mb.cyl(cx, cy, z1 - 0.2, z1 + 0.9, 0.06, "metal_dark", 6)
    mb.poly([(cx, cy, z1 + 0.9), (cx + 0.8, cy, z1 + 0.7), (cx, cy, z1 + 0.5)], "canvas_red")
    mb.sphere(cx, cy, z1 + 0.95, 0.12, "gold", 1)


def roof_hall(mb, b, m, rng):
    """Toit à deux pentes en tôle ondulée (nervures) ou rouillée, larges avant-toits, bandeau,
    lucarnes éclairées, trou de tôle arrachée, cheminée de brique, fronton d'enseigne lumineux
    côté façade et fenêtres chaudes sur le mur sud."""
    x, y, w, h = b["rect"]
    z = H_WALL + 0.4
    zt = z + 1.5
    ov = 0.45
    X0, X1, YN, YS = x - ov, x + w + ov, Y(y) + 0.2, Y(y + h) - 0.2
    ze = z - ov * (zt - z) / (w / 2)
    cx = x + w / 2
    rm = "roof_rust" if m.get("color", 0) % 2 else "roof_tin"
    mb.poly([(X0, YS, ze), (cx, YS, zt), (cx, YN, zt), (X0, YN, ze)], rm, [(0, 0), (w / 2, 0), (w / 2, h), (0, h)])
    mb.poly([(cx, YS, zt), (X1, YS, ze), (X1, YN, ze), (cx, YN, zt)], rm, [(0, 0), (w / 2, 0), (w / 2, h), (0, h)])
    # nervures de tôle ondulée
    yy = YS + 0.25
    while yy < YN - 0.1:
        for (ex, ez) in ((X0, ze), (X1, ze)):
            mb.seg((ex, yy, ez + 0.03), (cx, yy, zt + 0.03), 0.022, "metal_mid" if rm == "roof_tin" else "rust", 4)
        yy += 0.42
    # faîtage, bandeaux de rive peints
    mb.box(cx - 0.1, YS - 0.06, zt - 0.05, cx + 0.1, YN + 0.06, zt + 0.1, "metal_dark")
    for (ex, ez) in ((X0, ze), (X1, ze)):
        mb.box(ex - 0.05, YS - 0.05, ez - 0.22, ex + 0.05, YN + 0.05, ez + 0.02, "plank_painted")
    mb.poly([(X0, YS - 0.02, ze), (cx, YS - 0.02, zt), (X1, YS - 0.02, ze)], "plank_dark")
    # lucarnes éclairées (chaudes) le long des pentes
    for k in range(max(1, int(h / 3))):
        ly = YN - 1.3 - k * 3.0
        for side in (-1, 1):
            if rng.random() < 0.35:
                continue
            lx = cx + side * w * 0.22
            lz = zt - (zt - z) * 0.44
            mb.box(lx - 0.42, ly - 0.38, lz - 0.05, lx + 0.42, ly + 0.38, lz + 0.32, "plank_dark")
            mb.box(lx - 0.3, ly - 0.39, lz + 0.02, lx + 0.3, ly - 0.3, lz + 0.26, "lamp_warm" if rng.random() < 0.8 else "lamp_magenta")
            mb.box(lx - 0.3, ly + 0.3, lz + 0.02, lx + 0.3, ly + 0.39, lz + 0.26, "lamp_warm")
    # tôle arrachée : trou sombre et deux planches en travers
    if rng.random() < 0.6:
        side = rng.choice((-1, 1))
        hx = cx + side * w * 0.3
        hy = YS + rng.uniform(1.0, max(1.2, h - 1.5))
        hz = (ze + zt) / 2 - 0.15
        mb.box(hx - 0.55, hy - 0.45, hz, hx + 0.55, hy + 0.45, hz + 0.06, "metal_dark", rot=rng.uniform(-0.3, 0.3))
        for j in range(2):
            mb.box(hx - 0.7, hy - 0.08 + j * 0.3, hz + 0.08, hx + 0.7, hy + 0.08 + j * 0.3, hz + 0.14, "plank", rot=rng.uniform(-0.5, 0.5))
    # cheminée de brique à chapeau
    chx, chy = x + w - 1.2, Y(y + 1.3)
    mb.box(chx - 0.32, chy - 0.32, zt - 0.8, chx + 0.32, chy + 0.32, zt + 0.9, "brick_dark")
    mb.box(chx - 0.4, chy - 0.4, zt + 0.9, chx + 0.4, chy + 0.4, zt + 1.0, "stone_dark")
    # fronton d'enseigne (face caméra) avec cadre d'ampoules ; texte posé par build_roofs
    fx, fy = m.get("facade", [0, 1])
    if fy == 1:
        bx0, bx1 = x + 0.6, x + w - 0.6
        by = Y(y + h) - 0.0
        mb.box(bx0, by + 0.15, z - 0.4, bx1, by + 0.25, z + 0.95, "plank_painted")
        mb.box(bx0 - 0.08, by + 0.13, z + 0.95, bx1 + 0.08, by + 0.27, z + 1.05, "gold")
        n = int((bx1 - bx0) / 0.4)
        for k in range(n + 1):
            bxk = bx0 + (bx1 - bx0) * k / max(n, 1)
            mb.sphere(bxk, by + 0.1, z + 1.0, 0.06, "lamp_gold" if k % 2 else "lamp_magenta", 1)
            mb.sphere(bxk, by + 0.1, z - 0.38, 0.06, "lamp_gold" if k % 2 else "lamp_magenta", 1)
        GLOWS.append((x + w / 2, by - 0.8, z + 0.5, NEON["gold"], 0.6))
    # fenêtres chaudes sur le mur sud (hors portes)
    for xx in range(int(x) + 1, int(x + w) - 1, 2):
        if (xx, y + h - 1) in DOOR_CELLS:
            continue
        mb.box(xx + 0.2, Y(y + h) - 0.04, 1.0, xx + 0.8, Y(y + h) + 0.0, 1.55, "plank_dark")
        mb.box(xx + 0.27, Y(y + h) - 0.06, 1.06, xx + 0.73, Y(y + h) - 0.02, 1.49, "lamp_warm" if rng.random() < 0.75 else "glass_dark")


def roof_kiosk(mb, b, m, rng):
    x, y, w, h = b["rect"]
    cx, cy = x + w / 2, Y(y + h / 2)
    z0, z1 = H_WALL, H_WALL + 1.1
    X0, X1, YN, YS = x - 0.2, x + w + 0.2, Y(y) + 0.2, Y(y + h) - 0.2
    for (p0, p1) in (((X0, YS), (X1, YS)), ((X1, YS), (X1, YN)), ((X1, YN), (X0, YN)), ((X0, YN), (X0, YS))):
        mb.poly([(p0[0], p0[1], z0), (p1[0], p1[1], z0), (cx, cy, z1)], "stripes_%d" % canvas_of(m), [(0, 0), (w, 0), (w / 2, 2)])
    mb.sphere(cx, cy, z1 + 0.1, 0.18, "gold", 1)
    for k in range(int((X1 - X0) / 0.5)):
        mb.sphere(X0 + k * 0.5 + 0.25, YS - 0.02, z0 - 0.05, 0.08, "lamp_warm", 1)


def build_roofs():
    for b in LAYOUT.get("buildings", []):
        bid = b["id"]
        if b["arch"] == "big_top":
            continue
        rng = random.Random(bid * 7919 + SEED)
        m = MOD_BY_BLD.get(bid, {})
        mb = MB()
        arch = b["arch"]
        if arch in ("hangar", "workshop", "museum", "arcade"):
            roof_hall(mb, b, m, rng)
        elif arch in ("caravan", "director_caravan"):
            roof_caravan(mb, b, m, rng)
        elif arch in ("mirrors", "freaks", "theatre"):
            roof_tent(mb, b, m, rng, "stripes_purple" if arch == "mirrors" else "stripes_tent")
        elif arch == "ticket_booth":
            roof_kiosk(mb, b, m, rng)
        else:
            roof_stand(mb, b, m, rng)
        mb.to_object("roof_%d" % bid, "roofs")
    # enseignes des stands / tentes (texte doré sur la façade)
    n = 0
    for m in MODS:
        if m["slot"] not in ("stand", "tent", "kiosk", "caravan", "hall"):
            continue
        x, y, w, h = m["rect"]
        txt = {"stand_shooting": "TIR", "stand_candy": "BONBONS", "stand_ducks": "CANARDS", "stand_prizes": "LOTS",
               "stand_fortune": "VOYANCE", "stand_popcorn": "POP-CORN", "stand_hammer": "TAPE-FORT", "stand_souvenirs": "SOUVENIRS",
               "tent_mirrors": "MIROIRS", "tent_freaks": "MONSTRES", "tent_theatre": "THÉÂTRE", "ticket_booth": "BILLETS",
               "caravan_director": "DIRECTEUR", "hall_hangar": "HANGAR", "hall_workshop": "ATELIER", "hall_museum": "HORREURS",
               "hall_arcade": "JEUX"}.get(m["role"])
        if not txt:
            continue
        fx, fy = m.get("facade", [0, 1])
        zz = (H_WALL if m["roof"] else H_STAND) + (0.95 if m["slot"] == "stand" else 0.3)
        if m["slot"] == "hall":
            zz = H_WALL + 0.7
        size = 0.5 if m["slot"] == "stand" else 0.6
        if fy == 1:
            sign_text("_sign%d" % n, txt, x + w / 2, Y(y + h) + 0.12, zz, size, "neon_gold", math.radians(70))
        elif fy == -1:
            sign_text("_sign%d" % n, txt, x + w / 2, Y(y) - 0.2, zz, size, "neon_gold", math.radians(70))
        else:
            sx = x + (w + 0.12 if fx == 1 else -0.12)
            ob = sign_text("_sign%d" % n, txt, sx, Y(y + h / 2), zz, size, "neon_gold", math.radians(70))
            ob.rotation_euler = (math.radians(70), 0, math.radians(90 if fx == 1 else -90))
        n += 1


# ======================================================================= chapiteau (salle du boss)
def build_big_top():
    b = None
    for bb in LAYOUT.get("buildings", []):
        if bb["arch"] == "big_top":
            b = bb
    if b is None:
        return
    bid = b["id"]
    cx, cy = TC.x, TC.y
    rx, ry = TR[0] + 0.3, TR[1] + 0.3
    walls = MB()
    seg = 56
    # paroi de toile rayée (anneau), ouverte aux portes
    door_angles = []
    for (dx_, dy_), d in DOOR_CELLS.items():
        if CELL_BLD.get((dx_, dy_)) == bid:
            door_angles.append(math.atan2((Y(dy_ + 0.5) - cy) / ry, (dx_ + 0.5 - cx) / rx))
    for k in range(seg):
        a0 = k / seg * math.tau
        a1 = (k + 1) / seg * math.tau
        am = (a0 + a1) / 2
        near_door = any(abs((am - da + math.pi) % math.tau - math.pi) < 0.1 for da in door_angles)
        p0 = (cx + math.cos(a0) * rx, cy + math.sin(a0) * ry)
        p1 = (cx + math.cos(a1) * rx, cy + math.sin(a1) * ry)
        if near_door:
            # linteau au-dessus de l'entrée + lanterne
            walls.poly([(p0[0], p0[1], H_DOOR + 0.2), (p1[0], p1[1], H_DOOR + 0.2), (p1[0], p1[1], H_WALL), (p0[0], p0[1], H_WALL)], "canvas_red")
            continue
        walls.poly([(p0[0], p0[1], 0.0), (p1[0], p1[1], 0.0), (p1[0], p1[1], H_WALL), (p0[0], p0[1], H_WALL)],
                   "stone" if k % 3 else "stone_dark", [(k, 0), (k + 1, 0), (k + 1, H_WALL), (k, H_WALL)])
        # merlons et torches violettes au sommet de l'enceinte
        if k % 2 == 0:
            walls.box(min(p0[0], p1[0]), min(p0[1], p1[1]), H_WALL, max(p0[0], p1[0]) + 0.02, max(p0[1], p1[1]) + 0.02, H_WALL + 0.3, "stone_dark")
        if k % 7 == 0:
            walls.sphere(p0[0], p0[1], H_WALL + 0.5, 0.14, "neon_violet", 1)
            GLOWS.append((p0[0], p0[1], H_WALL + 0.6, NEON["violet"], 0.5))
    # gradins intérieurs (anneau de 3 marches) sur les cases FLOOR périphériques de la piste
    for k in range(seg):
        a0 = k / seg * math.tau
        a1 = (k + 1) / seg * math.tau
        for st in range(4):
            r0 = 0.97 - st * 0.07
            r1 = r0 - 0.07
            z = 0.9 - st * 0.22
            q = [(cx + math.cos(a0) * TR[0] * r0, cy + math.sin(a0) * TR[1] * r0), (cx + math.cos(a1) * TR[0] * r0, cy + math.sin(a1) * TR[1] * r0),
                 (cx + math.cos(a1) * TR[0] * r1, cy + math.sin(a1) * TR[1] * r1), (cx + math.cos(a0) * TR[0] * r1, cy + math.sin(a0) * TR[1] * r1)]
            am = (a0 + a1) / 2
            if any(abs((am - da + math.pi) % math.tau - math.pi) < 0.13 for da in door_angles):
                continue
            walls.poly([(q[0][0], q[0][1], z), (q[1][0], q[1][1], z), (q[2][0], q[2][1], z), (q[3][0], q[3][1], z)], "seat_red" if (k + st) % 2 else "stone")
            walls.poly([(q[3][0], q[3][1], z), (q[2][0], q[2][1], z), (q[2][0], q[2][1], z - 0.22), (q[3][0], q[3][1], z - 0.22)], "stone_dark")
    # escalier d'accès au sud (marches basses de pierre, non bloquantes) et torchères
    for da in door_angles:
        if abs(da + math.pi / 2) > 0.3:
            continue
        sx = cx + math.cos(da) * rx
        for k in range(8):
            yy = cy + math.sin(da) * (ry + 0.2) - k * 0.5
            walls.box(sx - 2.4 - k * 0.2, yy - 0.5, 0.0, sx + 2.4 + k * 0.2, yy, 0.14 - k * 0.015, "stone_ochre" if k % 2 else "stone")
            walls.box(sx - 2.4 - k * 0.2, yy - 0.06, 0.14 - k * 0.015, sx + 2.4 + k * 0.2, yy, 0.15 - k * 0.015, "stone_dark")
        # rampes basses de part et d'autre de l'escalier, lampions
        bal = MB()
        for sgn in (-1, 1):
            for k in range(8):
                yy = cy + math.sin(da) * (ry + 0.2) - k * 0.5
                bx = sx + sgn * (2.55 + k * 0.2)
                bal.box(bx - 0.14, yy - 0.5, 0.0, bx + 0.14, yy, 0.55, "stone_ochre")
                if k % 2 == 0:
                    bal.sphere(bx, yy - 0.25, 0.68, 0.1, "lamp_warm" if k % 4 else "lamp_magenta", 1)
        bal.to_object("_bt_stairs", "world")
        for sx2 in (sx - 3.0, sx + 3.0):
            walls.cyl(sx2, cy + math.sin(da) * (ry + 0.6), 0.0, 1.6, 0.12, "stone_dark", 8)
            walls.sphere(sx2, cy + math.sin(da) * (ry + 0.6), 1.75, 0.18, "neon_violet", 1)
            GLOWS.append((sx2, cy + math.sin(da) * (ry + 0.6), 1.8, NEON["violet"], 1.0))
    walls.to_object("walls_%d" % bid, "world")
    # mât central, projecteurs violets sur poutres, cordes
    inner = MB()
    inner.cyl(cx, cy, 0.0, 5.2, 0.14, "metal_dark", 10)
    for k in range(6):
        a = k / 6 * math.tau + 0.3
        px, py = cx + math.cos(a) * TR[0] * 0.55, cy + math.sin(a) * TR[1] * 0.55
        inner.seg((cx, cy, 4.6), (px, py, 2.6), 0.04, "metal_dark", 5)
        inner.box(px - 0.18, py - 0.18, 2.4, px + 0.18, py + 0.18, 2.75, "metal_dark")
        inner.sphere(px, py, 2.38, 0.14, "spot_violet", 1)
        GLOWS.append((px, py, 2.3, NEON["violet"], 1.6))
    inner.to_object("_bigtop_inner", "world")
    # toit : ANNEAU de toile rayée (centre ouvert sur la piste violette, comme la maquette) :
    # pente du bord extérieur (z0) vers une couronne intérieure (z1) tenue par des mâts dorés,
    # ampoules magenta / or sur les deux couronnes, fanions.
    roof = MB()
    z0, z1 = H_WALL + 0.3, H_WALL + 2.4
    ri = 0.62
    for k in range(seg):
        a0 = k / seg * math.tau
        a1 = (k + 1) / seg * math.tau
        p0 = (cx + math.cos(a0) * rx, cy + math.sin(a0) * ry)
        p1 = (cx + math.cos(a1) * rx, cy + math.sin(a1) * ry)
        q0 = (cx + math.cos(a0) * rx * ri, cy + math.sin(a0) * ry * ri)
        q1 = (cx + math.cos(a1) * rx * ri, cy + math.sin(a1) * ry * ri)
        roof.poly([(p0[0], p0[1], z0), (p1[0], p1[1], z0), (q1[0], q1[1], z1), (q0[0], q0[1], z1)], "canvas_red" if k % 2 else "canvas_white")
        roof.sphere(p0[0], p0[1], z0 + 0.12, 0.12, "lamp_warm" if k % 2 else "lamp_magenta", 1)
        roof.sphere(q0[0], q0[1], z1 + 0.12, 0.1, "lamp_gold" if k % 2 else "lamp_magenta", 1)
        roof.poly([(p0[0], p0[1], z0 - 0.45), (p1[0], p1[1], z0 - 0.45), (p1[0], p1[1], z0), (p0[0], p0[1], z0)], "canvas_white" if k % 2 else "canvas_red")
        # couronne intérieure : garde-corps + rideau court
        roof.poly([(q0[0], q0[1], z1), (q1[0], q1[1], z1), (q1[0], q1[1], z1 + 0.5), (q0[0], q0[1], z1 + 0.5)], "cloth_purple")
    for k in range(8):
        a = k / 8 * math.tau
        px, py = cx + math.cos(a) * rx * ri, cy + math.sin(a) * ry * ri
        roof.cyl(px, py, 0.0, z1 + 1.6, 0.1, "gold", 8)
        roof.poly([(px, py, z1 + 1.6), (px + 0.7, py, z1 + 1.4), (px, py, z1 + 1.15)], "canvas_red" if k % 2 else "cloth_purple")
        roof.sphere(px, py, z1 + 1.65, 0.12, "gold", 1)
    # guirlandes entre les mâts intérieurs
    for k in range(8):
        a0 = k / 8 * math.tau
        a1 = (k + 1) / 8 * math.tau
        n = 8
        for j in range(1, n):
            t = j / n
            am = a0 + (a1 - a0) * t
            roof.sphere(cx + math.cos(am) * rx * ri * 0.98, cy + math.sin(am) * ry * ri * 0.98, z1 + 1.3 - 0.35 * math.sin(t * math.pi), 0.07, "lamp_gold", 1)
    roof.to_object("roof_%d" % bid, "roofs")
    GLOWS.append((cx, cy, 2.2, NEON["violet"], 6.0))
    GLOWS.append((cx, cy, 0.8, NEON["magenta"], 2.5))
    LAMPS.append((cx, cy, 6.0, NEON["violet"], 6.0))
    build_enclosure()


def build_enclosure():
    """Enceinte de pierre ocre basse autour du chapiteau : mur à chaperon, créneaux, piliers à
    torchères, niches en arcade éclairées côté extérieur, gradins (deux marches) côté intérieur,
    projecteurs sur les piliers des diagonales braqués sur le chapiteau."""
    if not ENC_CELLS:
        return
    w = MB()
    dec = MB()
    hw = 1.35
    cxp, cyp = TENT["c"]
    pil = []
    for (x, y) in sorted(ENC_CELLS):
        w.box(x, Y(y + 1), 0.0, x + 1, Y(y), hw, "stone_ochre")
        w.box(x - 0.06, Y(y + 1) - 0.06, hw, x + 1.06, Y(y) + 0.06, hw + 0.12, "stone")
        if (x + y) % 2 == 0:
            w.box(x + 0.25, Y(y + 0.75), hw + 0.1, x + 0.75, Y(y + 0.25), hw + 0.34, "stone_ochre")
        for sd, dx, dy in SIDES:
            nx, ny = x + dx, y + dy
            if not walk(nx, ny):
                continue
            outer = enc_d(nx, ny) > enc_d(x, y)
            # face extérieure : niche en arcade (fond sombre, petite flamme chaude)
            if outer:
                ox_, oy_ = x + 0.5 + dx * 0.52, Y(y + 0.5) - dy * 0.52
                ax = abs(dy) > 0
                if ax:
                    dec.box(ox_ - 0.28, oy_ - 0.02, 0.12, ox_ + 0.28, oy_ + 0.02, 0.72, "metal_dark")
                    dec.cyl(ox_, oy_, 0.72, 0.04, 0.28, "metal_dark", 10, axis="Y")
                else:
                    dec.box(ox_ - 0.02, oy_ - 0.28, 0.12, ox_ + 0.02, oy_ + 0.28, 0.72, "metal_dark")
                    dec.cyl(ox_, oy_, 0.72, 0.04, 0.28, "metal_dark", 10, axis="X")
                dec.sphere(ox_, oy_, 0.4, 0.07, "lamp_warm", 1)
            # face intérieure : gradins de pierre (deux marches basses, non bloquantes)
            if not outer:
                for st, (d0, d1, z) in enumerate(((0.0, 0.45, 0.13), (0.45, 0.9, 0.07))):
                    if dy != 0:
                        y0_ = Y(y + 0.5) - dy * (0.5 + d0)
                        y1_ = Y(y + 0.5) - dy * (0.5 + d1)
                        dec.box(x, min(y0_, y1_), 0.0, x + 1, max(y0_, y1_), z, "seat_red" if (x + st) % 3 == 0 else "stone")
                    else:
                        x0_ = x + 0.5 + dx * (0.5 + d0)
                        x1_ = x + 0.5 + dx * (0.5 + d1)
                        dec.box(min(x0_, x1_), Y(y + 1), 0.0, max(x0_, x1_), Y(y), z, "seat_red" if (y + st) % 3 == 0 else "stone")
        # piliers à torchère
        if (x * 5 + y * 3) % 6 == 0:
            pil.append((x, y))
    for (x, y) in pil:
        w.box(x + 0.05, Y(y + 0.95), 0.0, x + 0.95, Y(y + 0.05), hw + 0.75, "stone")
        w.box(x - 0.02, Y(y + 1.02), hw + 0.75, x + 1.02, Y(y - 0.02), hw + 0.88, "stone_dark")
        dec.cyl(x + 0.5, Y(y + 0.5), hw + 0.88, hw + 1.05, 0.22, "brass", 8, r2=0.3)
        col = "violet" if (x + y) % 3 else "magenta"
        dec.sphere(x + 0.5, Y(y + 0.5), hw + 1.18, 0.16, "neon_" + col, 1, 1.0, 1.0, 1.5)
        GLOWS.append((x + 0.5, Y(y + 0.5), hw + 1.5, NEON[col], 0.7))
    # projecteurs : 4 mâts sur les diagonales, têtes braquées sur le chapiteau
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2 + 0.22
        best = None
        for (x, y) in ENC_CELLS:
            vx, vy = x + 0.5 - cxp, y + 0.5 - cyp
            da = abs((math.atan2(vy, vx) - a + math.pi) % math.tau - math.pi)
            if best is None or da < best[0]:
                best = (da, x, y)
        if best is None:
            continue
        _, x, y = best
        px, py = x + 0.5, Y(y + 0.5)
        w.cyl(px, py, 0.0, 4.6, 0.12, "metal_dark", 8)
        for j in range(5):
            z = 0.8 + j * 0.8
            w.seg((px - 0.25, py, z), (px + 0.25, py, z + 0.4), 0.03, "metal_dark", 4)
        tgt = Vector((TC.x + (px - TC.x) * 0.35, TC.y + (py - TC.y) * 0.35, H_WALL + 1.5))
        d = (tgt - Vector((px, py, 4.7))).normalized()
        hx, hy, hz = px + d.x * 0.35, py + d.y * 0.35, 4.7 + d.z * 0.35
        dec.seg((px, py, 4.7), (hx, hy, hz), 0.28, "metal_dark", 10, r2=0.36)
        dec.sphere(hx + d.x * 0.18, hy + d.y * 0.18, hz + d.z * 0.18, 0.3, "neon_violet" if k % 2 else "neon_cyan", 1, 1.0, 1.0, 1.0)
        SPOTS.append((px, py, 4.9, (tgt.x, tgt.y, tgt.z), NEON["violet"] if k % 2 else NEON["cyan"], 900.0))
    w.to_object("walls_enclosure", "world")
    dec.to_object("_enclosure_dec", "world")


# ======================================================================= grande roue et manèges
def build_rides():
    for rd in RIDES:
        kind = rd["kind"]
        cx, cy = rd["c"][0], Y(rd["c"][1])
        r = rd["r"]
        mb = MB()
        rng = random.Random(int(cx * 7 + cy * 13) + SEED)
        # plateau + clôture
        mb.cyl(cx, cy, 0.0, 0.25, r - 0.05, "stone", 32)
        mb.cyl(cx, cy, 0.25, 0.3, r - 0.1, "plank_dark", 32)
        nf = int(r * 6)
        for k in range(nf):
            a = k / nf * math.tau
            px, py = cx + math.cos(a) * (r - 0.12), cy + math.sin(a) * (r - 0.12)
            mb.cyl(px, py, 0.25, 0.95, 0.04, "metal_mid", 6)
            a2 = (k + 1) / nf * math.tau
            mb.seg((px, py, 0.9), (cx + math.cos(a2) * (r - 0.12), cy + math.sin(a2) * (r - 0.12), 0.9), 0.03, "metal_mid", 4)
            if k % 2 == 0:
                mb.sphere(px, py, 1.0, 0.07, "lamp_warm", 1)
        if kind == "ferris_wheel":
            _ferris(mb, cx, cy, r, rng)
        elif kind == "carousel":
            _carousel(mb, cx, cy, r, rng)
        elif kind == "swing_ride":
            _swing(mb, cx, cy, r, rng)
        else:
            _teacups(mb, cx, cy, r, rng)
        mb.to_object("props_ride_%s" % kind, "world")


def _ferris(mb, cx, cy, r, rng):
    """Grande roue : plan incliné de WHEEL_TILT vers la caméra (lecture « de face » comme sur la
    maquette), deux chevalets rouges, moyeu doré, 16 rayons, double jante, 16 nacelles colorées,
    ampoules magenta / or sur rayons et jante."""
    R = r * 1.15
    zc = R + 1.0
    tilt = math.radians(float(os.environ.get("HC_WHEEL_TILT", "48")))
    # repère de la roue : u = X, v = (0, -sin t, cos t) incliné vers le sud (caméra)
    vy, vz = math.sin(tilt), math.cos(tilt)

    def P(a, rr, off=0.0):
        return (cx + math.cos(a) * rr, cy + off + math.sin(a) * rr * vy, zc + math.sin(a) * rr * vz)
    for off in (-0.8, 0.8):
        mb.seg((cx - R * 0.8, cy + off, 0.25), (cx, cy + off * 0.5, zc), 0.13, "iron_red", 6)
        mb.seg((cx + R * 0.8, cy + off, 0.25), (cx, cy + off * 0.5, zc), 0.13, "iron_red", 6)
        mb.seg((cx - R * 0.8, cy + off, 0.25), (cx + R * 0.8, cy + off, 0.25), 0.1, "iron_red", 6)
        mb.seg((cx - R * 0.4, cy + off, 0.25), (cx + R * 0.4, cy + off * 0.5, zc * 0.55), 0.06, "metal_mid", 5)
        mb.seg((cx + R * 0.4, cy + off, 0.25), (cx - R * 0.4, cy + off * 0.5, zc * 0.55), 0.06, "metal_mid", 5)
    mb.sphere(cx, cy, zc, 0.5, "metal_dark", 2)
    mb.sphere(cx, cy - 0.45, zc + 0.2, 0.3, "neon_gold", 1)
    n = 16
    for off in (-0.4, 0.4):
        for k in range(n):
            a = k / n * math.tau
            a2 = (k + 1) / n * math.tau
            mb.seg((cx, cy + off, zc), P(a, R, off), 0.045, "metal_mid", 4)
            mb.seg(P(a, R, off), P(a2, R, off), 0.08, "iron_red", 5)
            mb.seg(P(a, R * 0.55, off), P(a2, R * 0.55, off), 0.035, "metal_mid", 4)
            for j in range(1, 6):
                t = j / 6
                p = P(a, R * t, off)
                mb.sphere(p[0], p[1], p[2], 0.11, "neon_magenta" if k % 2 else "neon_gold", 1)
            for j in range(4):
                am = a + (a2 - a) * j / 4
                p = P(am, R + 0.1, off)
                mb.sphere(p[0], p[1], p[2], 0.1, "neon_warm" if j % 2 else "neon_pink", 1)
    cols = ["seat_red", "seat_blue", "seat_yellow", "seat_teal", "plush_pink", "cloth_purple"]
    for k in range(n):
        a = k / n * math.tau + math.pi / n
        p = P(a, R)
        mb.seg((p[0], p[1] - 0.4, p[2]), (p[0], p[1] + 0.4, p[2]), 0.035, "metal_mid", 4)
        mb.box(p[0] - 0.38, p[1] - 0.34, p[2] - 0.85, p[0] + 0.38, p[1] + 0.34, p[2] - 0.25, cols[k % 6])
        mb.box(p[0] - 0.4, p[1] - 0.36, p[2] - 0.25, p[0] + 0.4, p[1] + 0.36, p[2] - 0.15, "metal_dark")
        mb.sphere(p[0], p[1] - 0.36, p[2] - 0.2, 0.07, "lamp_warm", 1)
    GLOWS.append((cx, cy - 2.0, zc, NEON["magenta"], 10.0))
    GLOWS.append((cx, cy - 1.0, zc * 0.4, NEON["gold"], 3.0))
    LAMPS.append((cx, cy - 3.0, zc + 2.0, NEON["pink"], 6.0))


def _carousel(mb, cx, cy, r, rng):
    R = r - 0.7
    mb.cyl(cx, cy, 0.3, 0.6, R + 0.3, "plank_painted", 28)
    mb.cyl(cx, cy, 0.6, 0.66, R + 0.35, "gold", 28)
    mb.cyl(cx, cy, 0.6, 3.6, 0.3, "gold", 12)
    # toit conique rayé + ampoules
    seg = 24
    z0, z1 = 3.2, 5.0
    for k in range(seg):
        a0 = k / seg * math.tau
        a1 = (k + 1) / seg * math.tau
        mb.poly([(cx + math.cos(a0) * (R + 0.5), cy + math.sin(a0) * (R + 0.5), z0), (cx + math.cos(a1) * (R + 0.5), cy + math.sin(a1) * (R + 0.5), z0), (cx, cy, z1)],
                "canvas_red" if k % 2 else "canvas_white")
        mb.sphere(cx + math.cos(a0) * (R + 0.5), cy + math.sin(a0) * (R + 0.5), z0 - 0.08, 0.09, "lamp_gold" if k % 2 else "lamp_pink", 1)
        mb.poly([(cx + math.cos(a0) * (R + 0.5), cy + math.sin(a0) * (R + 0.5), z0 - 0.3), (cx + math.cos(a1) * (R + 0.5), cy + math.sin(a1) * (R + 0.5), z0 - 0.3),
                 (cx + math.cos(a1) * (R + 0.5), cy + math.sin(a1) * (R + 0.5), z0), (cx + math.cos(a0) * (R + 0.5), cy + math.sin(a0) * (R + 0.5), z0)], "gold" if k % 2 else "canvas_red")
    mb.sphere(cx, cy, z1 + 0.1, 0.2, "gold", 1)
    # chevaux (corps + tête) sur barres dorées
    cols = ["canvas_white", "seat_red", "seat_blue", "seat_yellow", "plush_pink", "seat_teal"]
    for k in range(10):
        a = k / 10 * math.tau
        rr = R * (0.55 if k % 2 else 0.85)
        px, py = cx + math.cos(a) * rr, cy + math.sin(a) * rr
        zh = 1.0 + 0.3 * (k % 3)
        mb.cyl(px, py, 0.66, 2.6, 0.03, "gold", 6)
        mb.box(px - 0.42, py - 0.16, zh, px + 0.42, py + 0.16, zh + 0.32, cols[k % 6], rot=a + math.pi / 2)
        mb.box(px + math.cos(a + math.pi / 2) * 0.45 - 0.14, py + math.sin(a + math.pi / 2) * 0.45 - 0.14, zh + 0.25,
               px + math.cos(a + math.pi / 2) * 0.45 + 0.14, py + math.sin(a + math.pi / 2) * 0.45 + 0.14, zh + 0.62, cols[k % 6])
        for j in range(4):
            mb.cyl(px + (-0.3 + 0.2 * j), py + (0.1 if j % 2 else -0.1), 0.66, zh, 0.03, "metal_dark", 5)
    GLOWS.append((cx, cy, 2.0, NEON["gold"], 2.5))


def _swing(mb, cx, cy, r, rng):
    mb.cyl(cx, cy, 0.3, 5.2, 0.35, "iron_red", 12)
    for k in range(3):
        z = 1.2 + k * 1.4
        mb.cyl(cx, cy, z, z + 0.12, 0.6, "gold", 12)
    top_r = r - 0.6
    seg = 20
    for k in range(seg):
        a0 = k / seg * math.tau
        a1 = (k + 1) / seg * math.tau
        mb.poly([(cx + math.cos(a0) * top_r, cy + math.sin(a0) * top_r, 5.0), (cx + math.cos(a1) * top_r, cy + math.sin(a1) * top_r, 5.0), (cx, cy, 6.3)],
                "canvas_white" if k % 2 else "canvas_purple")
        mb.sphere(cx + math.cos(a0) * top_r, cy + math.sin(a0) * top_r, 4.95, 0.09, "lamp_pink" if k % 2 else "lamp_warm", 1)
    mb.cyl(cx, cy, 4.8, 5.0, top_r + 0.1, "gold", 24)
    cols = ["seat_red", "seat_blue", "seat_yellow", "seat_teal"]
    for k in range(14):
        a = k / 14 * math.tau
        ox, oy = math.cos(a), math.sin(a)
        tx, ty = cx + ox * top_r, cy + oy * top_r
        sx, sy = cx + ox * (top_r + 1.0), cy + oy * (top_r + 1.0)
        zs = 3.0 + 0.6 * math.sin(k * 1.3)
        mb.seg((tx, ty, 4.9), (sx, sy, zs + 0.3), 0.02, "metal_mid", 4)
        mb.box(sx - 0.22, sy - 0.22, zs, sx + 0.22, sy + 0.22, zs + 0.22, cols[k % 4], rot=a)
        mb.box(sx + ox * 0.0 - 0.22, sy - 0.22, zs + 0.22, sx + 0.22, sy + 0.22, zs + 0.55, "metal_dark", rot=a)
    GLOWS.append((cx, cy, 4.2, NEON["pink"], 3.0))


def _teacups(mb, cx, cy, r, rng):
    R = r - 0.7
    mb.cyl(cx, cy, 0.3, 0.55, R + 0.2, "stripes_purple", 28)
    cols = ["seat_red", "seat_blue", "seat_yellow", "seat_teal", "plush_pink", "canvas_white"]
    for k in range(6):
        a = k / 6 * math.tau
        px, py = cx + math.cos(a) * R * 0.62, cy + math.sin(a) * R * 0.62
        mb.cyl(px, py, 0.55, 0.65, 1.0, "metal_dark", 16)
        mb.cyl(px, py, 0.65, 1.45, 0.85, cols[k], 16, r2=1.0)
        mb.cyl(px, py, 1.45, 1.5, 1.02, "gold", 16)
        mb.cyl(px, py, 0.9, 1.3, 0.14, "gold", 8)
        # anse
        mb.seg((px + math.cos(a) * 0.95, py + math.sin(a) * 0.95, 0.9), (px + math.cos(a) * 1.35, py + math.sin(a) * 1.35, 1.2), 0.07, cols[k], 6)
        mb.seg((px + math.cos(a) * 1.35, py + math.sin(a) * 1.35, 1.2), (px + math.cos(a) * 1.0, py + math.sin(a) * 1.0, 1.45), 0.07, cols[k], 6)
    mb.cyl(cx, cy, 0.55, 2.4, 0.3, "gold", 10)
    seg = 18
    for k in range(seg):
        a0 = k / seg * math.tau
        a1 = (k + 1) / seg * math.tau
        mb.poly([(cx + math.cos(a0) * (R + 0.4), cy + math.sin(a0) * (R + 0.4), 2.3), (cx + math.cos(a1) * (R + 0.4), cy + math.sin(a1) * (R + 0.4), 2.3), (cx, cy, 3.4)],
                "canvas_white" if k % 2 else "canvas_purple")
        mb.sphere(cx + math.cos(a0) * (R + 0.4), cy + math.sin(a0) * (R + 0.4), 2.25, 0.09, "lamp_magenta" if k % 2 else "lamp_warm", 1)
    GLOWS.append((cx, cy, 1.8, NEON["magenta"], 2.5))


# ======================================================================= montagnes russes
def _catmull(pts, n_per=10, closed=False):
    out = []
    P = [Vector(p) for p in pts]
    m = len(P)
    rng_ = range(m) if closed else range(m - 1)
    for i in rng_:
        p0 = P[(i - 1) % m] if closed or i > 0 else P[i]
        p1 = P[i]
        p2 = P[(i + 1) % m]
        p3 = P[(i + 2) % m] if closed or i + 2 < m else P[(i + 1) % m]
        for k in range(n_per):
            t = k / n_per
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    if not closed:
        out.append(P[-1])
    return out


def _support_ok(x, y):
    """Pylône autorisé : hors du parc, ou sur une case murée / vide (jamais sur une allée)."""
    cx, cy = int(math.floor(x)), int(math.floor(-y))
    if cx < 0 or cy < 0 or cx >= W or cy >= H:
        return True
    return tile(cx, cy) in (0, 3)


def _track(mb, pts, zfun, gauge=0.55, sup_every=3):
    """Voie : deux rails rouges + traverses + poutres de soutien rouges jusqu'au sol (seulement sur
    les cases non praticables : cohérence rendu / collisions)."""
    prev = None
    for i, p in enumerate(pts):
        z = zfun(i, len(pts))
        q = Vector((p.x, p.y, z))
        if prev is not None:
            d = (q - prev)
            if d.length < 1e-4:
                continue
            side = Vector((-d.y, d.x, 0)).normalized() * gauge
            mb.seg(tuple(prev + side), tuple(q + side), 0.13, "rail_red", 6)
            mb.seg(tuple(prev - side), tuple(q - side), 0.13, "rail_red", 6)
            mb.seg(tuple(prev - Vector((0, 0, 0.28))), tuple(q - Vector((0, 0, 0.28))), 0.1, "iron_red", 5)
            if i % 2 == 0:
                mb.seg(tuple(q + side * 1.2), tuple(q - side * 1.2), 0.03, "metal_dark", 4)
            if i % sup_every == 0 and z > 0.3 and _support_ok(q.x, q.y):
                for s in (1, -1):
                    base = q + side * s * 1.1
                    mb.seg((base.x, base.y, -0.05), (q.x + side.x * s, q.y + side.y * s, z - 0.25), 0.09, "iron_red", 5)
                    mb.seg((base.x, base.y, -0.05), (q.x - side.x * s, q.y - side.y * s, z - 0.25), 0.04, "metal_dark", 4)
                mb.seg((q.x + side.x * 1.1, q.y + side.y * 1.1, -0.05), (q.x - side.x * 1.1, q.y - side.y * 1.1, -0.05), 0.08, "iron_red", 5)
                mb.seg((q.x + side.x, q.y + side.y, z - 0.25), (q.x - side.x, q.y - side.y, z - 0.25), 0.07, "iron_red", 5)
                if i % (sup_every * 2) == 0:
                    mb.seg((q.x + side.x * 0.8, q.y + side.y * 0.8, z * 0.5), (q.x - side.x * 0.8, q.y - side.y * 0.8, z * 0.5), 0.04, "iron_red", 4)
                    mb.seg((q.x + side.x * 0.8, q.y + side.y * 0.8, -0.05), (q.x - side.x * 0.8, q.y - side.y * 0.8, z * 0.5), 0.03, "metal_dark", 4)
            if i % 3 == 0:
                mb.sphere(q.x, q.y, z + 0.12, 0.06, "lamp_warm" if i % 6 else "lamp_red", 1)
        prev = q


def build_coaster():
    mb = MB()
    if COASTER:
        # Boucle principale : marge ouest / nord puis plongée À TRAVERS le parc (coin nord-est,
        # bande est, cour sud-est) avant de ressortir au sud-est.
        # Grande boucle fermée : marge ouest → nord → plongée dans le coin nord-est (pylônes) → au-dessus
        # de la place (côté est) et de l'allée des manèges → cour sud-est → marge est → sud → retour.
        # Grande boucle fermée qui TRAVERSE le parc : marge ouest → nord au-dessus de la grande roue
        # → plongée dans la cour nord-est (pylônes) → au-dessus du flanc est de la place et des
        # roulottes → sud-est → sous le parvis → remontée par le sud-ouest.
        route_g = [(-5.0, 70.0), (-6.0, 40.0), (-3.0, 18.0), (4.0, 3.0), (16.0, -4.0), (30.0, -2.0), (40.0, 0.0),
                   (44.0, 4.0)] + [(p[0], p[1]) for p in COASTER_IN] + \
                  [(50.0, 29.0), (60.0, 31.0), (69.0, 36.0), (71.0, 48.0), (64.0, 56.0), (70.0, 66.0), (72.0, 80.0),
                   (70.0, 98.0), (64.0, 104.0), (58.0, 112.0), (54.0, 124.0), (40.0, 130.0), (24.0, 129.0), (14.0, 120.0),
                   (6.0, 106.0), (1.0, 96.0), (-4.0, 84.0)]
        route = [(p[0], Y(p[1]), 0) for p in route_g]
        pts = _catmull(route, 8, closed=True)
        pts.append(pts[0])
        n = len(pts)

        def zf(i, n_):
            t = i / n_
            return 3.2 + 2.4 * (0.5 + 0.5 * math.sin(t * math.tau * 5.0 + 0.7)) + 3.0 * max(0.0, math.sin(t * math.tau * 2.0 + 2.2)) ** 3
        _track(mb, pts, zf)
        # trains rouges (3 wagons) à deux endroits
        for i0 in (int(n * 0.22), int(n * 0.48), int(n * 0.8)):
            for k in range(3):
                j = min(i0 + k * 3, n - 1)
                p = pts[j]
                z = zf(j, n)
                d = (pts[min(j + 1, n - 1)] - pts[max(j - 1, 0)])
                a = math.atan2(d.y, d.x)
                mb.box(p.x - 0.65, p.y - 0.38, z + 0.05, p.x + 0.65, p.y + 0.38, z + 0.55, "seat_red" if k else "iron_red", rot=a)
                mb.box(p.x - 0.5, p.y - 0.3, z + 0.55, p.x + 0.5, p.y + 0.3, z + 0.62, "metal_dark", rot=a)
                mb.sphere(p.x, p.y, z + 0.65, 0.1, "lamp_warm", 1)
    mb.to_object("props_coaster", "world")


# ======================================================================= portail à la tête de clown
def build_gate():
    mb = MB()
    gx, gy, gw, gh = GATE
    ox, oy, ow, oh = GATE_OPEN
    y0, y1 = Y(gy + gh), Y(gy)
    # murs du portail (pierre sombre), bandeau doré
    for seg_ in ((gx, ox), (ox + ow, gx + gw)):
        a, b = seg_
        mb.box(a, y0, 0.0, b, y1, 1.6, "stone_dark")
        mb.box(a, y0 - 0.05, 1.5, b, y1 + 0.05, 1.7, "stone")
        for xx in range(a, b, 2):
            mb.sphere(xx + 0.5, y0 - 0.1, 1.75, 0.08, "lamp_gold", 1)
    # deux tours de part et d'autre du passage
    for tx in (ox - 0.3, ox + ow + 0.3):
        mb.cyl(tx, (y0 + y1) / 2, 0.0, 4.4, 1.1, "stone", 14)
        mb.cyl(tx, (y0 + y1) / 2, 4.4, 4.55, 1.25, "gold", 14)
        seg = 12
        for k in range(seg):
            a0 = k / seg * math.tau
            a1 = (k + 1) / seg * math.tau
            mb.poly([(tx + math.cos(a0) * 1.3, (y0 + y1) / 2 + math.sin(a0) * 1.3, 4.55), (tx + math.cos(a1) * 1.3, (y0 + y1) / 2 + math.sin(a1) * 1.3, 4.55), (tx, (y0 + y1) / 2, 6.6)],
                    "canvas_red" if k % 2 else "canvas_white")
        mb.sphere(tx, (y0 + y1) / 2, 6.65, 0.18, "gold", 1)
        for z in (1.2, 2.4):
            mb.cyl(tx, y0 - 0.02, z, z + 0.4, 0.2, "lamp_warm", 10, axis="Y")
    # arche au-dessus du passage + panneau « CARNAVAL »
    mb.box(ox - 0.5, y0 + 0.2, 3.0, ox + ow + 0.5, y1 - 0.2, 3.5, "stone")
    mb.box(ox - 0.6, y0 - 0.05, 3.5, ox + ow + 0.6, y1 + 0.05, 4.6, "cloth_purple")
    mb.box(ox - 0.6, y0 - 0.08, 3.5, ox + ow + 0.6, y0 - 0.02, 3.62, "gold")
    mb.box(ox - 0.6, y0 - 0.08, 4.5, ox + ow + 0.6, y0 - 0.02, 4.62, "gold")
    for k in range(int(ow * 2) + 3):
        mb.sphere(ox - 0.5 + k * 0.5, y0 - 0.1, 4.65, 0.08, "lamp_gold" if k % 2 else "lamp_magenta", 1)
    sign_text("_sign_gate", "CARNAVAL", ox + ow / 2, y0 - 0.12, 4.05, 0.7, "neon_gold", math.radians(80))
    # Tête de clown monumentale et sculptée au-dessus de l'arche, visage tourné vers la caméra
    # (vecteurs avant f / haut u inclinés de TILT) : crâne, pommettes, arcades menaçantes, orbites
    # violettes et yeux rouges lumineux, nez, bouche béante (lèvres rouges, dents pointues), touffes
    # de cheveux rouges, collerette, chapeau pointu à pompon.
    S = float(os.environ.get("HC_CLOWN_S", "2.0"))
    cx, cz = ox + ow / 2, 4.4 + 2.0 * S
    cy = (y0 + y1) / 2 - 0.4
    ct, st_ = math.cos(TILT), math.sin(TILT)
    f = Vector((0.0, -ct, st_))
    u = Vector((0.0, st_, ct))

    def hp(dx, d, h):
        return (cx + dx * S, cy + (f.y * d + u.y * h) * S, cz + (f.z * d + u.z * h) * S)

    def sph(dx, d, h, r, mat, sx=1.0, sy=1.0, sz=1.0, sub=2):
        q = hp(dx, d, h)
        mb.sphere(q[0], q[1], q[2], r * S, mat, sub, sx, sy, sz)

    # arche de pierre à ampoules derrière la tête (plan vertical tourné vers la caméra)
    RA = 4.5
    na = 26
    for k in range(na):
        a0 = math.pi * k / na
        a1 = math.pi * (k + 1) / na
        p0 = hp(math.cos(a0) * RA, -0.9, -1.6 + math.sin(a0) * RA)
        p1 = hp(math.cos(a1) * RA, -0.9, -1.6 + math.sin(a1) * RA)
        mb.seg(p0, p1, 0.3 * S, "stone_ochre" if k % 2 else "stone", 8)
        q0 = hp(math.cos(a0) * (RA + 0.32), -0.7, -1.6 + math.sin(a0) * (RA + 0.32))
        mb.sphere(q0[0], q0[1], q0[2], 0.07 * S, "lamp_gold" if k % 2 else "lamp_magenta", 1)
        q1 = hp(math.cos(a0) * (RA - 0.3), -0.7, -1.6 + math.sin(a0) * (RA - 0.3))
        mb.sphere(q1[0], q1[1], q1[2], 0.055 * S, "lamp_violet", 1)
    sph(0, 0, 0.2, 2.9, "clown_face", 1.0, 0.85, 1.08, 3)             # crâne
    sph(0, 0.9, -1.2, 2.2, "clown_face", 1.08, 0.8, 0.75, 3)          # mâchoire
    for s_ in (-1, 1):
        sph(s_ * 1.5, 2.25, -0.5, 0.7, "balloon_r", 1.0, 0.6, 0.8)    # pommettes
        sph(s_ * 1.05, 2.35, 0.8, 0.62, "cloth_purple", 1.25, 0.55, 0.95)  # orbites
        sph(s_ * 1.0, 2.62, 0.72, 0.26, "eyes_glow", 1.0, 1.0, 1.25, 1)  # yeux lumineux
        sph(s_ * 1.0, 2.82, 0.72, 0.1, "metal_dark", 1.0, 1.0, 1.4, 1)   # pupilles fendues
        sph(s_ * 1.05, 2.5, 1.45, 0.5, "metal_dark", 1.5, 0.45, 0.35)    # arcades froncées
        q0, q1 = hp(s_ * 0.35, 2.75, 1.25), hp(s_ * 1.75, 2.35, 1.85)
        mb.seg(q0, q1, 0.13 * S, "metal_dark", 6)                         # sourcils en V
        for j in range(7):                                                # touffes violettes
            a_ = j / 6 * 1.9 - 0.45
            sph(s_ * (2.5 + 0.45 * math.cos(a_)), 0.2 - 0.3 * j / 6, 0.3 + 1.9 * math.sin(a_), 0.9 - 0.06 * j,
                "hair_violet" if j % 2 == 0 else "balloon_p", 1.0, 0.9, 0.9)
        GLOWS.append(hp(s_ * 1.0, 3.6, 0.72) + (NEON["green"], 1.6))
    sph(0, 2.85, -0.05, 0.62, "balloon_r", 1.0, 1.0, 1.0)              # nez
    sph(0, 2.75, -1.65, 1.0, "metal_dark", 2.05, 0.6, 0.65)              # bouche béante
    sph(0, 2.95, -1.5, 0.6, "neon_magenta", 2.8, 0.35, 0.5, 1)        # lueur au fond de la gorge
    for k in range(13):                                                # lèvres (grand sourire)
        t = k / 12
        a_ = math.pi * (0.1 + 0.8 * t)
        q0 = hp(-2.05 + 4.1 * t, 3.05, -0.95 - 0.35 * math.sin(a_) + 0.35 * (2 * t - 1) ** 2)
        q1 = hp(-2.05 + 4.1 * (k + 1) / 12, 3.05, -0.95 - 0.35 * math.sin(math.pi * (0.1 + 0.8 * (k + 1) / 12)) + 0.35 * (2 * (k + 1) / 12 - 1) ** 2)
        if k < 12:
            mb.seg(q0, q1, 0.17 * S, "balloon_r", 6)
        q2 = hp(-1.85 + 3.7 * t, 3.00, -2.3 + 0.15 * math.sin(a_))
        if k < 12:
            q3 = hp(-1.85 + 3.7 * (k + 1) / 12, 3.00, -2.3 + 0.15 * math.sin(math.pi * (0.1 + 0.8 * (k + 1) / 12)))
            mb.seg(q2, q3, 0.14 * S, "balloon_r", 6)
        if 1 <= k <= 11:                                                  # dents pointues
            top = hp(-2.0 + 4.0 * t, 3.12, -1.05 - 0.33 * math.sin(a_) + 0.3 * (2 * t - 1) ** 2)
            tip = hp(-2.0 + 4.0 * t, 3.16, -1.5 - 0.3 * math.sin(a_))
            mb.seg(top, tip, 0.13 * S, "canvas_white", 5, r2=0.0)
            bot = hp(-1.8 + 3.6 * t, 3.08, -2.2 + 0.12 * math.sin(a_))
            tip2 = hp(-1.8 + 3.6 * t, 3.10, -1.82 + 0.12 * math.sin(a_))
            mb.seg(bot, tip2, 0.11 * S, "canvas_white", 5, r2=0.0)
    for k in range(22):                                                   # collerette violette / rose
        a_ = k / 22 * math.tau
        q = hp(math.cos(a_) * 2.7, 0.6 + math.sin(a_) * 1.0, -2.6)
        mb.sphere(q[0], q[1], q[2], 0.58 * S, "cloth_purple" if k % 2 else "plush_pink", 1, 1.0, 1.0, 0.6)
    q = hp(0, -0.4, 3.0)
    mb.cyl(q[0], q[1], q[2] - 0.3 * S, q[2] + 1.9 * S, 1.05 * S, "stripes_purple", 14, r2=0.1 * S)   # chapeau
    mb.sphere(q[0], q[1], q[2] + 2.0 * S, 0.32 * S, "balloon_r", 2)
    for s_ in (-1, 1):
        mb.seg((cx + s_ * 0.8 * S, cy, 4.2), hp(s_ * 1.1, 0, -2.0), 0.3 * S, "stone", 8)   # cou / support
    # lampions de papier entre l'arche et les tours
    for s_ in (-1, 1):
        a_ = hp(s_ * RA, -0.7, -1.4)
        b_ = (ox + ow / 2 + s_ * (ow / 2 + 0.3), (y0 + y1) / 2 - 1.2, 4.6)
        for j in range(1, 6):
            t = j / 6
            px = a_[0] + (b_[0] - a_[0]) * t
            py = a_[1] + (b_[1] - a_[1]) * t
            pz = a_[2] + (b_[2] - a_[2]) * t - 0.8 * math.sin(t * math.pi)
            mb.sphere(px, py, pz, 0.26, "lamp_red" if j % 2 else "lamp_warm", 1, 1.0, 1.0, 1.3)
    # Escalier du portail (marches basses, non bloquantes) et lampions le long des murs.
    for k in range(6):
        yy = gy + gh + k * 0.55
        mb.box(ox - 0.6 - k * 0.35, Y(yy + 0.55), 0.0, ox + ow + 0.6 + k * 0.35, Y(yy), 0.12 - k * 0.025, "stone" if k % 2 else "stone_dark")
    for seg_ in ((gx, ox - 1.5), (ox + ow + 1.5, gx + gw)):
        a, b = seg_
        n = int((b - a) / 1.2)
        for k in range(n + 1):
            lx = a + (b - a) * k / max(n, 1)
            z = 2.6 - 0.35 * math.sin(k / max(n, 1) * math.pi * 3)
            mb.sphere(lx, y0 - 0.25, z, 0.22, "lamp_warm" if k % 3 else "lamp_red", 1, 1.0, 1.0, 1.35)
            mb.cyl(lx, y0 - 0.25, z + 0.28, z + 0.38, 0.1, "metal_dark", 6)
        GLOWS.append(((a + b) / 2, y0 - 0.8, 2.2, NEON["warm"], 1.2))
    mb.to_object("props_gate", "world")
    LAMPS.append((cx, cy - 4.0 * S, cz, NEON["violet"], 14.0))
    LAMPS.append((cx, cy - 3.0 * S, cz - 2.0 * S, NEON["magenta"], 10.0))
    GLOWS.append((cx, cy - 2.0, cz - 2.5, NEON["magenta"], 4.0))
    GLOWS.append((ox + ow / 2, y0 - 0.5, 2.2, NEON["gold"], 1.5))


# ======================================================================= décors (prop_spawns)
def _rect_of_spawn(s):
    sx, sy = s.get("size", [1, 1])
    if [sx, sy] == [1, 1] and s.get("kind") in BIG:
        sx, sy = BIG[s["kind"]]
    x0 = s["cell"][0] - (sx - 1) // 2
    return [x0, s["cell"][1] - sy + 1, sx, sy]


def prop(mb, kind, cx, cy, rect, rng):
    """Décor par kind, centré (cx, cy) Blender, emprise rect (cases)."""
    x, y, w, h = rect
    k = kind.replace("hc_", "")
    if k == "lamp_post":
        mb.cyl(cx, cy, 0.0, 0.25, 0.18, "stone_dark", 8)
        mb.cyl(cx, cy, 0.25, 2.6, 0.05, "metal_dark", 8)
        mb.seg((cx, cy, 2.6), (cx + 0.45, cy, 2.5), 0.04, "metal_dark", 6)
        mb.box(cx + 0.3, cy - 0.16, 2.2, cx + 0.62, cy + 0.16, 2.5, "lamp_warm" if rng.random() < 0.8 else "bulb_dim")
        LAMPS.append((cx + 0.45, cy, 2.3, NEON["warm"] if rng.random() < 0.75 else NEON["magenta"], 5.0))
    elif k == "debris":
        for j in range(rng.randint(3, 6)):
            mb.box(cx + rng.uniform(-0.4, 0.3), cy + rng.uniform(-0.4, 0.3), 0.0, cx + rng.uniform(0.0, 0.45), cy + rng.uniform(0.0, 0.45), rng.uniform(0.04, 0.12),
                   rng.choice(["debris", "paper", "plank_dark", "canvas_red"]), rot=rng.uniform(0, 3))
    elif k == "balloon_bunch":
        mb.cyl(cx, cy, 0.0, 1.0, 0.03, "metal_dark", 5)
        for j in range(5):
            a = j / 5 * math.tau
            mb.seg((cx, cy, 1.0), (cx + math.cos(a) * 0.3, cy + math.sin(a) * 0.3, 1.5 + 0.1 * j), 0.01, "metal_dark", 3)
            mb.sphere(cx + math.cos(a) * 0.3, cy + math.sin(a) * 0.3, 1.65 + 0.1 * j, 0.2, rng.choice(["balloon_r", "balloon_p", "balloon_y"]), 2)
    elif k == "barrier":
        mb.box(cx - 0.85, cy - 0.08, 0.5, cx + 0.85, cy + 0.08, 0.62, "stripes_fine_0")
        mb.box(cx - 0.85, cy - 0.08, 0.25, cx + 0.85, cy + 0.08, 0.33, "stripes_fine_0")
        for sx in (-0.8, 0.8):
            mb.box(cx + sx - 0.05, cy - 0.3, 0.0, cx + sx + 0.05, cy + 0.3, 0.05, "metal_dark")
            mb.cyl(cx + sx, cy, 0.0, 0.7, 0.04, "metal_dark", 6)
    elif k == "trash_bin":
        mb.cyl(cx, cy, 0.0, 0.7, 0.26, "metal_mid", 10)
        mb.cyl(cx, cy, 0.7, 0.76, 0.3, "metal_dark", 10)
        mb.box(cx - 0.3, cy - 0.5, 0.0, cx + 0.1, cy - 0.3, 0.12, "paper", rot=0.5)
    elif k == "food_cart":
        mb.box(cx - 0.9, cy - 0.4, 0.3, cx + 0.9, cy + 0.4, 1.1, "plank_painted")
        mb.box(cx - 0.95, cy - 0.45, 1.1, cx + 0.95, cy + 0.45, 1.16, "plank")
        mb.poly([(cx - 1.05, cy - 0.55, 1.9), (cx + 1.05, cy - 0.55, 1.9), (cx + 1.05, cy + 0.55, 2.15), (cx - 1.05, cy + 0.55, 2.15)], "stripes_fine_%d" % rng.randint(0, 3),
                [(0, 0), (2.1, 0), (2.1, 1), (0, 1)])
        for sx in (-0.95, 0.95):
            mb.cyl(cx + sx, cy - 0.5, 1.1, 1.95, 0.03, "metal_dark", 5)
            mb.cyl(cx + sx, cy + 0.5, 1.1, 2.15, 0.03, "metal_dark", 5)
        for sx in (-0.6, 0.6):
            mb.cyl(cx + sx, cy - 0.45, 0.25, 0.1, 0.25, "metal_dark", 10, axis="Y")
        mb.box(cx - 0.5, cy - 0.46, 0.55, cx + 0.5, cy - 0.4, 0.95, "glass")
        mb.sphere(cx, cy, 1.5, 0.1, "lamp_warm", 1)
        GLOWS.append((cx, cy - 0.6, 1.5, NEON["warm"], 0.6))
    elif k == "dead_tree":
        mb.cyl(cx, cy, 0.0, 1.8, 0.14, "trunk", 7, r2=0.08)
        for j in range(5):
            a = j / 5 * math.tau + rng.random()
            z0 = 1.0 + j * 0.2
            mb.seg((cx, cy, z0), (cx + math.cos(a) * 0.9, cy + math.sin(a) * 0.9, z0 + 0.9), 0.05, "trunk", 5, r2=0.02)
            mb.seg((cx + math.cos(a) * 0.9, cy + math.sin(a) * 0.9, z0 + 0.9), (cx + math.cos(a + 0.5) * 1.3, cy + math.sin(a + 0.5) * 1.3, z0 + 1.4), 0.025, "trunk", 4, r2=0.01)
    elif k == "sign_post":
        mb.cyl(cx, cy, 0.0, 2.0, 0.05, "plank_dark", 6)
        for j in range(3):
            mb.box(cx - 0.05, cy - 0.06, 1.2 + j * 0.28, cx + 0.5 + 0.15 * j, cy + 0.06, 1.4 + j * 0.28, ["seat_yellow", "seat_red", "seat_teal"][j], rot=rng.uniform(-0.4, 0.4), piv=(cx, cy))
    elif k == "bench":
        mb.box(cx - 0.85, cy - 0.25, 0.4, cx + 0.85, cy + 0.25, 0.48, "plank")
        mb.box(cx - 0.85, cy + 0.2, 0.48, cx + 0.85, cy + 0.3, 0.9, "plank")
        for sx in (-0.7, 0.7):
            mb.box(cx + sx - 0.05, cy - 0.25, 0.0, cx + sx + 0.05, cy + 0.3, 0.42, "metal_dark")
    elif k == "bumper_car":
        col = rng.choice(["seat_red", "seat_blue", "seat_yellow", "seat_teal"])
        mb.cyl(cx, cy, 0.0, 0.35, 0.55, "metal_dark", 12, r2=0.75)
        mb.cyl(cx, cy, 0.35, 0.7, 0.72, col, 12, r2=0.6)
        mb.box(cx - 0.3, cy - 0.3, 0.7, cx + 0.3, cy + 0.2, 0.95, "metal_dark")
        mb.cyl(cx + 0.2, cy + 0.2, 0.7, 2.0, 0.03, "metal_dark", 5)
    elif k == "shooting_counter":
        mb.box(cx - 1.0, cy - 0.3, 0.0, cx + 1.0, cy + 0.3, 0.85, "plank_painted")
        mb.box(cx - 1.05, cy - 0.35, 0.85, cx + 1.05, cy + 0.35, 0.92, "plank")
        for j in range(4):
            mb.box(cx - 0.8 + j * 0.5, cy - 0.1, 0.92, cx - 0.5 + j * 0.5, cy + 0.05, 0.98, "metal_dark", rot=0.2)
        for j in range(6):
            mb.cyl(cx - 0.75 + j * 0.3, cy + 0.9, 0.0, 0.5 + 0.2 * (j % 2), 0.08, rng.choice(["seat_red", "seat_yellow", "canvas_white"]), 8)
    elif k == "prize_shelf":
        mb.box(cx - 0.6, cy - 0.15, 0.0, cx + 0.6, cy + 0.25, 1.9, "plank")
        for z in (0.5, 1.0, 1.5):
            mb.box(cx - 0.62, cy - 0.3, z, cx + 0.62, cy + 0.25, z + 0.04, "plank_dark")
            for j in range(4):
                mb.sphere(cx - 0.45 + j * 0.3, cy - 0.05, z + 0.2, 0.14, rng.choice(["plush", "plush_pink", "seat_yellow", "seat_teal"]), 1)
    elif k == "candy_machine":
        mb.box(cx - 0.35, cy - 0.35, 0.0, cx + 0.35, cy + 0.35, 0.9, "plush_pink")
        mb.cyl(cx, cy, 0.9, 1.5, 0.4, "glass", 14)
        mb.sphere(cx, cy, 1.2, 0.3, "plush_pink", 2)
        mb.cyl(cx, cy, 1.5, 1.58, 0.42, "metal_mid", 14)
        GLOWS.append((cx, cy, 1.2, NEON["pink"], 0.5))
    elif k == "duck_pool":
        mb.box(cx - 0.7, cy - 0.55, 0.0, cx + 0.7, cy + 0.55, 0.35, "seat_blue")
        mb.box(cx - 0.62, cy - 0.47, 0.34, cx + 0.62, cy + 0.47, 0.36, "water")
        for j in range(5):
            mb.sphere(cx + rng.uniform(-0.5, 0.5), cy + rng.uniform(-0.35, 0.35), 0.42, 0.09, "seat_yellow", 1)
    elif k == "plush_pile":
        for j in range(6):
            mb.sphere(cx + rng.uniform(-0.3, 0.3), cy + rng.uniform(-0.3, 0.3), 0.15 + 0.12 * (j // 3), rng.uniform(0.15, 0.25), rng.choice(["plush", "plush_pink", "seat_yellow"]), 2)
    elif k == "crystal_table":
        mb.cyl(cx, cy, 0.0, 0.7, 0.45, "cloth_purple", 12)
        mb.cyl(cx, cy, 0.7, 0.76, 0.5, "cloth_purple", 12)
        mb.sphere(cx, cy, 1.0, 0.22, "neon_violet", 2)
        GLOWS.append((cx, cy, 1.0, NEON["violet"], 1.0))
    elif k == "hammer_tower":
        mb.box(cx - 0.3, cy - 0.3, 0.0, cx + 0.3, cy + 0.3, 0.3, "plank_dark")
        mb.box(cx - 0.12, cy - 0.12, 0.3, cx + 0.12, cy + 0.12, 3.2, "stripes_fine_0")
        mb.sphere(cx, cy, 3.35, 0.2, "lamp_red", 1)
        mb.box(cx - 0.35, cy - 0.3, 0.3, cx + 0.35, cy + 0.3, 0.4, "seat_red")
    elif k == "mirror":
        mb.box(cx - 0.45, cy - 0.06, 0.0, cx + 0.45, cy + 0.06, 1.8, "gold")
        mb.box(cx - 0.38, cy - 0.08, 0.1, cx + 0.38, cy - 0.06, 1.7, "mirror")
    elif k == "cage":
        mb.box(cx - 1.0, cy - 0.5, 0.0, cx + 1.0, cy + 0.5, 0.12, "metal_dark")
        for j in range(9):
            for sy in (-0.45, 0.45):
                mb.cyl(cx - 0.9 + j * 0.225, cy + sy, 0.12, 1.3, 0.02, "metal_mid", 4)
        mb.box(cx - 1.0, cy - 0.5, 1.3, cx + 1.0, cy + 0.5, 1.4, "metal_dark")
        mb.sphere(cx, cy, 0.5, 0.35, "plush", 2, 1.3, 0.8, 1.0)
    elif k == "puppet_stage":
        mb.box(cx - 0.9, cy - 0.3, 0.0, cx + 0.9, cy + 0.3, 0.8, "plank_painted")
        mb.box(cx - 0.95, cy - 0.3, 0.8, cx + 0.95, cy + 0.3, 2.0, "canvas_red")
        mb.box(cx - 0.6, cy - 0.32, 1.0, cx + 0.6, cy - 0.28, 1.7, "metal_dark")
        mb.box(cx - 0.95, cy - 0.34, 1.9, cx + 0.95, cy + 0.3, 2.1, "gold")
    elif k == "bunk":
        mb.box(cx - 0.8, cy - 0.4, 0.0, cx + 0.8, cy + 0.4, 0.45, "plank_dark")
        mb.box(cx - 0.75, cy - 0.35, 0.45, cx + 0.75, cy + 0.35, 0.6, "canvas_white")
        mb.box(cx - 0.3, cy - 0.35, 0.55, cx + 0.75, cy + 0.35, 0.72, "cloth_purple")
    elif k == "trunk":
        mb.box(cx - 0.5, cy - 0.3, 0.0, cx + 0.5, cy + 0.3, 0.55, "plank_painted")
        mb.box(cx - 0.52, cy - 0.32, 0.5, cx + 0.52, cy + 0.32, 0.6, "gold")
    elif k == "crate_stack":
        mb.box(cx - 0.45, cy - 0.4, 0.0, cx + 0.45, cy + 0.4, 0.6, "plank")
        mb.box(cx - 0.35, cy - 0.3, 0.6, cx + 0.3, cy + 0.3, 1.1, "plank_dark", rot=0.2)
    elif k == "bleachers":
        for j in range(3):
            mb.box(cx - 1.4, cy - 0.45 + j * 0.3, j * 0.25, cx + 1.4, cy + 0.45, j * 0.25 + 0.25, "seat_red" if j % 2 else "plank")
    elif k == "ring_barrier":
        mb.box(cx - 1.0, cy - 0.12, 0.0, cx + 1.0, cy + 0.12, 0.45, "piste_ring")
        mb.box(cx - 1.02, cy - 0.14, 0.45, cx + 1.02, cy + 0.14, 0.52, "gold")
    else:
        mb.box(cx - 0.3, cy - 0.3, 0.0, cx + 0.3, cy + 0.3, 0.5, "debris")


def build_props():
    outs = {}
    for s in LAYOUT.get("prop_spawns", []):
        rect = _rect_of_spawn(s)
        x, y, w, h = rect
        cx, cy = x + w / 2, Y(y + h / 2)
        rng = random.Random(x * 131 + y * 7 + SEED)
        bid = CELL_BLD.get((s["cell"][0], s["cell"][1]))
        key = ("furn_%d" % bid) if bid is not None else "props"
        mb = outs.setdefault(key, MB())
        start = len(mb.V)
        prop(mb, s["kind"], cx, cy, rect, rng)
        if s["kind"] not in ("hc_debris", "hc_dead_tree", "hc_balloon_bunch", "hc_lamp_post"):
            cells_fit(mb, start, rect, 0.03, 0.12, 1.0)
    for k, mb in outs.items():
        mb.to_object(k, "world")
    # conteneurs et cachettes : socles discrets (le jeu dessine le sprite)
    cb = MB()
    for key in ("container_spawns", "hiding_spot_spawns"):
        for s in LAYOUT.get(key, []):
            x, y = s["cell"]
            cb.box(x + 0.1, Y(y + 0.9), 0.0, x + 0.9, Y(y + 0.1), 0.01, "dirt_dark")
    cb.to_object("_sockets", "world")


# ======================================================================= guirlandes, hors jeu, forêt
CONFETTI = ["balloon_r", "balloon_p", "balloon_y", "lamp_cyan", "plush_pink", "canvas_white"]


def build_outskirts():
    mb = MB()
    veg = MB()
    rng = random.Random(SEED * 3 + 11)
    # guirlandes d'ampoules EN TRAVERS des allées sinueuses (d'un mur / toit à l'autre, tous les
    # ~4,5 cases), mâts posés sur les cases non praticables les plus proches de chaque bord.
    cols4 = ["lamp_warm", "lamp_magenta", "lamp_gold", "lamp_violet", "lamp_warm", "lamp_cyan"]

    def pole_at(px_, py_, nx_, ny_, hw):
        d = hw
        while d < hw + 3.0:
            qx, qy = px_ + nx_ * d, py_ + ny_ * d
            if not walk(int(math.floor(qx)), int(math.floor(qy))):
                return qx, qy
            d += 0.5
        return px_ + nx_ * (hw + 3.0), py_ + ny_ * (hw + 3.0)

    def garland(a_, b_, za, zb, sag, n, k0=0):
        for j in range(n + 1):
            t = j / n
            z = za + (zb - za) * t - sag * math.sin(t * math.pi)
            mb.sphere(a_[0] + (b_[0] - a_[0]) * t, a_[1] + (b_[1] - a_[1]) * t, z, 0.075, cols4[(j + k0) % len(cols4)], 1)
            if j < n:
                t2 = (j + 1) / n
                z2 = za + (zb - za) * t2 - sag * math.sin(t2 * math.pi)
                mb.seg((a_[0] + (b_[0] - a_[0]) * t, a_[1] + (b_[1] - a_[1]) * t, z + 0.05),
                       (a_[0] + (b_[0] - a_[0]) * t2, a_[1] + (b_[1] - a_[1]) * t2, z2 + 0.05), 0.012, "metal_dark", 3)

    gk = 0
    for pth in PATHS:
        pts = [Vector((p_[0], p_[1])) for p_ in pth["pts"]]
        hw = float(pth["w"]) / 2.0
        acc = 0.0
        for i in range(len(pts) - 1):
            a_, b_ = pts[i], pts[i + 1]
            L_ = (b_ - a_).length
            if L_ < 1e-3:
                continue
            tdir = (b_ - a_) / L_
            nrm = Vector((-tdir.y, tdir.x))
            d = 2.0 - acc
            while d < L_:
                c_ = a_ + tdir * d
                p1 = pole_at(c_.x, c_.y, nrm.x, nrm.y, hw)
                p2 = pole_at(c_.x, c_.y, -nrm.x, -nrm.y, hw)
                for (qx, qy) in (p1, p2):
                    mb.cyl(qx, Y(qy), 0.0, 3.0, 0.05, "metal_dark", 6)
                    mb.sphere(qx, Y(qy), 3.05, 0.09, "lamp_warm", 1)
                n = max(6, int(((p1[0] - p2[0]) ** 2 + (p1[1] - p2[1]) ** 2) ** 0.5 * 2.2))
                garland((p1[0], Y(p1[1])), (p2[0], Y(p2[1])), 3.0, 3.0, 0.6, n, gk)
                GLOWS.append((c_.x, Y(c_.y), 2.2, NEON["warm"] if gk % 3 else NEON["magenta"], 0.8))
                gk += 1
                d += 4.5
            acc = (acc + L_) % 4.5
    # guirlandes en étoile : du sommet de la couronne du chapiteau aux mâts du bord de la place
    pcx, pcy = PLAZA_E["c"]
    prx, pry = PLAZA_E["r"]
    for k in range(16):
        a_ = k / 16 * math.tau + 0.1
        ex, ey = pcx + math.cos(a_) * prx * 0.93, pcy + math.sin(a_) * pry * 0.93
        mb.cyl(ex, Y(ey), 0.0, 3.4, 0.06, "metal_dark", 6)
        mb.sphere(ex, Y(ey), 3.45, 0.1, "lamp_gold", 1)
        tx_ = TC.x + math.cos(a_) * (TR[0] + 0.3) * 0.62
        ty_ = TC.y - math.sin(a_) * (TR[1] + 0.3) * 0.62
        garland((tx_, ty_), (ex, Y(ey)), H_WALL + 3.6, 3.4, 0.9, 20, k)
        GLOWS.append(((tx_ + ex) / 2, (ty_ + Y(ey)) / 2, 2.6, NEON["magenta"] if k % 2 else NEON["violet"], 0.7))
    # arbres morts et sapins sombres hors jeu, lampadaires éteints, rochers
    for (tx, ty, sc) in C.get("trees", []):
        if rng.random() < 0.35:
            veg.cyl(tx, Y(ty), -0.05, 2.0 * sc, 0.12, "trunk", 6, r2=0.06)
            for j in range(4):
                a = j / 4 * math.tau + rng.random()
                veg.seg((tx, Y(ty), 1.2 * sc), (tx + math.cos(a) * 1.0, Y(ty) + math.sin(a) * 1.0, 2.1 * sc), 0.05, "trunk", 4, r2=0.02)
        else:
            veg.cyl(tx, Y(ty), -0.05, 0.8, 0.1, "trunk", 5)
            for j in range(3):
                z0 = 0.5 + j * 0.9 * sc
                veg.cyl(tx, Y(ty), z0, z0 + 1.3 * sc, 1.2 * sc - j * 0.3, "pine" if (int(tx) + j) % 2 else "pine_dark", 8, r2=0.05)
    # forêt dense en bordure extérieure (bande de sapins)
    for i in range(420):
        side = rng.randint(0, 3)
        near = rng.random() ** 1.6   # beaucoup d'arbres collés à la palissade (bord irrégulier)
        if side == 0:
            tx, ty = rng.uniform(-12, W + 12), -1.5 - near * 11
        elif side == 1:
            tx, ty = -1.5 - near * 11, rng.uniform(-6, H + 6)
        elif side == 2:
            tx, ty = W + 1.5 + near * 11, rng.uniform(-6, H + 6)
        else:
            tx, ty = rng.uniform(-12, W + 12), GATE[1] + 0.5 + rng.uniform(0, 14)
            if LOT[0] - 1.5 < tx < LOT[0] + LOT[2] + 1.5:
                continue
        sc = rng.uniform(0.7, 1.3)
        veg.cyl(tx, Y(ty), -0.05, 0.6, 0.1, "trunk", 5)
        for j in range(3):
            z0 = 0.4 + j * 0.9 * sc
            veg.cyl(tx, Y(ty), z0, z0 + 1.3 * sc, 1.1 * sc - j * 0.3, "pine" if (i + j) % 2 else "pine_dark", 7, r2=0.05)
    mb.to_object("_strings", "world")
    veg.to_object("_veg", "world")
    # fouillis au sol des allées : papiers, débris, flaques (non bloquant)
    cl = MB()
    rng2 = random.Random(SEED + 99)
    for y in range(H):
        for x in range(W):
            if tile(x, y) != 1 or (x, y) in GAME_CELLS:
                continue
            u = rng2.random()
            if u < 0.015:
                cl.cyl(x + 0.5, Y(y + 0.5), 0.0, 0.006, rng2.uniform(0.35, 0.6), "water", 10)
            elif u < 0.055:
                cl.box(x + rng2.uniform(0.2, 0.5), Y(y + rng2.uniform(0.5, 0.8)), 0.0, x + rng2.uniform(0.5, 0.8), Y(y + rng2.uniform(0.2, 0.5)), 0.008, "paper", rot=rng2.uniform(0, 3))
            elif u < 0.09:
                cl.box(x + 0.3, Y(y + 0.7), 0.0, x + 0.7, Y(y + 0.3), 0.03, "debris", rot=rng2.uniform(0, 3))
            elif u < 0.105:
                cl.sphere(x + 0.5, Y(y + 0.5), 0.02, 0.18, rng2.choice(["balloon_r", "balloon_p"]), 1, 1.0, 1.0, 0.3)
            role = role_of(CELL_ROOM.get((x, y), -1))
            # confettis (place, allée centrale, parvis)
            nconf = 3 if role in ("plaza", "avenue", "entrance") else 1
            for _ in range(nconf):
                if rng2.random() < 0.6:
                    qx, qy = x + rng2.random(), y + rng2.random()
                    cl.box(qx, Y(qy + 0.07), 0.0, qx + 0.07, Y(qy), 0.006, rng2.choice(CONFETTI), rot=rng2.uniform(0, 3))
            # encombrement contre les murs / palissades : caisses, barils, poubelles renversées,
            # bancs, peluches abandonnées, barrières, herbes folles (non bloquant, bord de case)
            nb = [(dx, dy) for (_, dx, dy) in SIDES if not walk(x + dx, y + dy)]
            if not nb:
                continue
            dx, dy = nb[0]
            ex, ey = x + 0.5 + dx * 0.28, y + 0.5 + dy * 0.28
            v = rng2.random()
            if v < 0.07:
                r_ = rng2.uniform(-0.4, 0.4)
                cl.box(ex - 0.27, Y(ey + 0.27), 0.0, ex + 0.27, Y(ey - 0.27), 0.5, "plank", rot=r_)
                cl.box(ex - 0.29, Y(ey + 0.05), 0.2, ex + 0.29, Y(ey - 0.05), 0.3, "plank_dark", rot=r_)
                if rng2.random() < 0.5:
                    cl.box(ex - 0.18, Y(ey + 0.18), 0.5, ex + 0.18, Y(ey - 0.18), 0.82, "plank", rot=r_ + 0.4)
            elif v < 0.12:
                cl.cyl(ex, Y(ey), 0.0, 0.62, 0.24, rng2.choice(["iron_red", "metal_mid", "rust"]), 10)
                cl.cyl(ex, Y(ey), 0.62, 0.64, 0.25, "metal_dark", 10)
            elif v < 0.16:
                cl.cyl(ex, Y(ey), 0.2, 0.55, 0.2, "metal_mid", 10, axis="X", rot=rng2.uniform(0, 3))
                for _ in range(4):
                    cl.box(ex + rng2.uniform(-0.5, 0.5), Y(ey + rng2.uniform(-0.5, 0.5)), 0.0, ex + rng2.uniform(-0.5, 0.5) + 0.12, Y(ey + rng2.uniform(-0.5, 0.5)) + 0.1, 0.02, "paper", rot=rng2.uniform(0, 3))
            elif v < 0.19 and role in ("plaza", "avenue", "alley"):
                hor = dy != 0
                if hor:
                    cl.box(x + 0.1, Y(ey + 0.16), 0.32, x + 0.9, Y(ey - 0.16), 0.38, "plank")
                    for lx in (x + 0.18, x + 0.82):
                        cl.box(lx - 0.04, Y(ey + 0.14), 0.0, lx + 0.04, Y(ey - 0.14), 0.32, "metal_dark")
                else:
                    cl.box(ex - 0.16, Y(y + 0.9), 0.32, ex + 0.16, Y(y + 0.1), 0.38, "plank")
                    for ly in (y + 0.18, y + 0.82):
                        cl.box(ex - 0.14, Y(ly + 0.04), 0.0, ex + 0.14, Y(ly - 0.04), 0.32, "metal_dark")
            elif v < 0.22:
                pm = rng2.choice(["plush", "plush_pink", "balloon_p"])
                cl.sphere(ex, Y(ey), 0.18, 0.2, pm, 1, 1.0, 0.9, 0.9)
                cl.sphere(ex + 0.05, Y(ey) + 0.12, 0.38, 0.13, pm, 1)
                cl.sphere(ex - 0.06, Y(ey) + 0.16, 0.5, 0.05, pm, 1)
                cl.sphere(ex + 0.16, Y(ey) + 0.16, 0.5, 0.05, pm, 1)
            elif v < 0.25:
                hor = dy != 0
                x0_, x1_ = (x + 0.05, x + 0.95) if hor else (ex - 0.06, ex + 0.06)
                y0_, y1_ = (ey - 0.06, ey + 0.06) if hor else (y + 0.05, y + 0.95)
                cl.box(x0_, Y(y1_), 0.42, x1_, Y(y0_), 0.6, "stripes_tent")
                for (px, py) in (((x + 0.15, ey), (x + 0.85, ey)) if hor else ((ex, y + 0.15), (ex, y + 0.85))):
                    cl.seg((px - 0.12, Y(py), 0.0), (px, Y(py), 0.55), 0.03, "plank_dark", 4)
                    cl.seg((px + 0.12, Y(py), 0.0), (px, Y(py), 0.55), 0.03, "plank_dark", 4)
            elif v < 0.42:
                for _ in range(rng2.randint(3, 6)):
                    gx_, gy_ = ex + rng2.uniform(-0.25, 0.25), ey + rng2.uniform(-0.25, 0.25)
                    cl.seg((gx_, Y(gy_), 0.0), (gx_ + rng2.uniform(-0.12, 0.12), Y(gy_) + rng2.uniform(-0.12, 0.12), rng2.uniform(0.15, 0.4)), 0.025, "pine", 3, r2=0.0)
    cl.to_object("_litter", "world")




# ======================================================================= bosquets dans les enclos vides
def build_groves():
    """Cases VOID enfermées dans le parc (entre allées et cours) : terrain vague des forains —
    herbe, arbres morts, carcasses de manège, caisses, roulotte abandonnée, feux de camp éteints."""
    gx0, gy0, gx1, gy1 = 1, 8, W - 1, GATE[1]
    cells = [(x, y) for y in range(gy0, gy1) for x in range(gx0, gx1) if tile(x, y) == 0]
    if not cells:
        return
    mb = MB()
    rng = random.Random(SEED * 7 + 3)
    for (x, y) in cells:
        mb.poly([(x, Y(y + 1), 0.0), (x + 1, Y(y + 1), 0.0), (x + 1, Y(y), 0.0), (x, Y(y), 0.0)], "grass",
                [(x, Y(y + 1)), (x + 1, Y(y + 1)), (x + 1, Y(y)), (x, Y(y))])
    cs = set(cells)
    for (x, y) in cells:
        u = rng.random()
        cx, cy = x + rng.uniform(0.3, 0.7), Y(y + rng.uniform(0.3, 0.7))
        if u < 0.16:
            mb.cyl(cx, cy, 0.0, rng.uniform(1.8, 2.8), 0.15, "trunk", 7, r2=0.07)
            for j in range(4):
                a = j / 4 * math.tau + rng.random()
                z0 = 1.2 + j * 0.3
                mb.seg((cx, cy, z0), (cx + math.cos(a) * 1.0, cy + math.sin(a) * 1.0, z0 + 1.0), 0.055, "trunk", 5, r2=0.02)
        elif u < 0.26:
            sc = rng.uniform(0.6, 1.0)
            for j in range(3):
                z0 = 0.3 + j * 0.8 * sc
                mb.cyl(cx, cy, z0, z0 + 1.1 * sc, 0.9 * sc - j * 0.25, "pine" if j % 2 else "pine_dark", 7, r2=0.05)
        elif u < 0.3:
            col = rng.choice(["seat_red", "seat_blue", "seat_yellow", "seat_teal"])
            mb.cyl(cx, cy, 0.0, 0.5, 0.6, col, 10, r2=0.5)
            mb.box(cx - 0.3, cy - 0.3, 0.5, cx + 0.3, cy + 0.2, 0.7, "metal_dark", rot=rng.uniform(0, 3))
        elif u < 0.33:
            mb.box(cx - 0.45, cy - 0.4, 0.0, cx + 0.45, cy + 0.4, 0.6, "plank", rot=rng.uniform(0, 3))
        elif u < 0.35:
            mb.cyl(cx, cy, 0.0, 0.6, 0.3, "rust", 10)
        elif u < 0.38:
            # cheval de carrousel renversé
            mb.box(cx - 0.45, cy - 0.15, 0.1, cx + 0.45, cy + 0.15, 0.4, "canvas_white", rot=rng.uniform(0, 3))
            mb.cyl(cx, cy, 0.0, 0.08, 0.04, "gold", 5)
        elif u < 0.5:
            mb.box(cx - 0.2, cy - 0.2, 0.0, cx + 0.2, cy + 0.2, 0.06, "debris", rot=rng.uniform(0, 3))
    # fouillis serré contre les façades arrière : caisses empilées, tonneaux, planches cassées,
    # bâches, ballons crevés (cases hors jeu collées aux murs des bâtiments)
    for (x, y) in cells:
        near = None
        for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if CELL_MOD.get((x + dx, y + dy)) is not None:
                near = (dx, dy)
        if near is None or rng.random() > 0.45:
            continue
        cx, cy = x + 0.5 + near[0] * 0.2, Y(y + 0.5 + near[1] * 0.2)
        u = rng.random()
        if u < 0.35:
            for j in range(rng.randint(1, 3)):
                sz_ = rng.uniform(0.35, 0.5)
                mb.box(cx - sz_, cy - sz_, j * 0.62, cx + sz_, cy + sz_, j * 0.62 + 0.6, "plank" if j % 2 else "plank_dark", rot=rng.uniform(0, 0.6))
        elif u < 0.6:
            for j in range(rng.randint(1, 2)):
                ox_ = rng.uniform(-0.25, 0.25)
                mb.cyl(cx + ox_, cy + rng.uniform(-0.25, 0.25), 0.0, 0.8, 0.28, "plank_dark" if j else "rust", 10)
                mb.cyl(cx + ox_, cy, 0.3, 0.36, 0.3, "metal_dark", 10)
        elif u < 0.8:
            for j in range(3):
                mb.box(cx - 0.45, cy - 0.06, 0.02 + j * 0.06, cx + 0.45, cy + 0.06, 0.06 + j * 0.06, "plank", rot=rng.uniform(0, 3))
        else:
            mb.poly([(cx - 0.45, cy - 0.4, 0.03), (cx + 0.5, cy - 0.35, 0.05), (cx + 0.4, cy + 0.45, 0.02), (cx - 0.5, cy + 0.4, 0.04)],
                    rng.choice(["canvas_red", "cloth_purple", "canvas_white"]))
    # quelques roulottes abandonnées dans les grands enclos
    rects = []
    for (x, y) in cells:
        if all((x + i, y + j) in cs for i in range(4) for j in range(3)) and rng.random() < 0.02:
            if all(abs(x - rx) > 5 or abs(y - ry) > 4 for (rx, ry) in rects):
                rects.append((x, y))
    for (x, y) in rects:
        X0, X1, YN, YS = x + 0.3, x + 3.7, Y(y + 0.3), Y(y + 2.7)
        mb.box(X0, YS, 0.3, X1, YN, 1.6, "plank_painted")
        for k in range(8):
            f0, f1 = k / 8, (k + 1) / 8
            mb.poly([(X0 - 0.1, YN - (YN - YS) * f0, 1.6 + math.sin(f0 * math.pi) * 0.4), (X1 + 0.1, YN - (YN - YS) * f0, 1.6 + math.sin(f0 * math.pi) * 0.4),
                     (X1 + 0.1, YN - (YN - YS) * f1, 1.6 + math.sin(f1 * math.pi) * 0.4), (X0 - 0.1, YN - (YN - YS) * f1, 1.6 + math.sin(f1 * math.pi) * 0.4)], "rust" if k % 3 else "plank_dark")
        for sx in (X0 + 0.5, X1 - 0.5):
            mb.cyl(sx, YS + 0.1, 0.3, 0.25, 0.3, "metal_dark", 10, axis="Y")
        mb.box(X0 + 0.9, YS - 0.03, 0.7, X1 - 0.9, YS, 1.2, "glass_dark")
        # feu de camp éteint devant
        mb.cyl(x + 2.0, Y(y + 3.6), 0.0, 0.12, 0.4, "debris", 8)
        for k in range(5):
            a = k / 5 * math.tau
            mb.cyl(x + 2.0 + math.cos(a) * 0.4, Y(y + 3.6) + math.sin(a) * 0.4, 0.0, 0.15, 0.1, "stone", 6)
    mb.to_object("props_grove", "world")


# ======================================================================= lumières
LIGHT_E = float(os.environ.get("HC_LIGHT", "100"))
WASH = float(os.environ.get("HC_WASH", "0.5"))  # nappes diffuses (place, cours, allées)


def build_lights():
    n = 0
    for (lx, ly, lz, col, k) in LAMPS:
        L_ = bpy.data.lights.new("p%d" % n, "POINT")
        L_.color = col
        L_.energy = LIGHT_E * k
        L_.shadow_soft_size = 0.4
        o = bpy.data.objects.new("p%d" % n, L_)
        o.location = (lx, ly, lz)
        scene.collection.objects.link(o)
        n += 1
    for (gx, gy, gz, col, k) in GLOWS:
        L_ = bpy.data.lights.new("g%d" % n, "POINT")
        L_.color = col
        L_.energy = LIGHT_E * k
        L_.shadow_soft_size = 0.6
        o = bpy.data.objects.new("g%d" % n, L_)
        o.location = (gx, gy, gz)
        scene.collection.objects.link(o)
        n += 1
    # plafonniers des bâtiments à toit (lumière chaude ou violette)
    for b in LAYOUT.get("buildings", []):
        x, y, w, h = b["rect"]
        if b["arch"] == "big_top":
            continue
        lrng = random.Random(b["id"] * 31 + SEED)
        col = NEON["violet"] if b["arch"] in ("mirrors", "director_caravan") else (NEON["warm"] if lrng.random() < 0.8 else NEON["pink"])
        L_ = bpy.data.lights.new("l%d" % n, "AREA")
        L_.shape = "DISK"
        L_.size = 1.8
        L_.color = col
        L_.energy = LIGHT_E * (0.5 if lrng.random() < 0.85 else 0.0)
        o = bpy.data.objects.new("l%d" % n, L_)
        o.location = (x + w / 2, Y(y + h / 2), 1.2)
        scene.collection.objects.link(o)
        n += 1
    # intérieurs chauds visibles des bâtiments sans toit (stands et halls vus en coupe)
    for m in MODS:
        if m["roof"] or m["slot"] not in ("stand", "hall"):
            continue
        x, y, w, h = m["rect"]
        L_ = bpy.data.lights.new("o%d" % m["room"], "AREA")
        L_.shape = "DISK"
        L_.size = max(1.5, min(w, h) * 0.6)
        L_.color = NEON["warm"]
        L_.energy = LIGHT_E * (0.9 if m["slot"] == "hall" else 0.45)
        o = bpy.data.objects.new("o%d" % m["room"], L_)
        o.location = (x + w / 2, Y(y + h / 2), 2.2)
        scene.collection.objects.link(o)
        n += 1
    # halo magenta diffus sur la place (ambiance de la maquette)
    L_ = bpy.data.lights.new("plaza", "AREA")
    L_.shape = "DISK"
    L_.size = 12.0
    L_.color = NEON["magenta"]
    L_.energy = LIGHT_E * 2.2 * WASH
    o = bpy.data.objects.new("plaza", L_)
    o.location = (TC.x, TC.y, 7.0)
    scene.collection.objects.link(o)
    # nappes violettes au-dessus de l'allée centrale et du parvis (guirlandes / néons de la maquette)
    k = 0
    for pth in PATHS:
        for i, p_ in enumerate(pth["pts"]):
            if i % 2 == 1 and pth["role"] != "avenue":
                continue
            L2 = bpy.data.lights.new("ave%d" % k, "AREA")
            L2.shape = "DISK"
            L2.size = 4.0
            L2.color = NEON["violet"] if k % 3 == 0 else (NEON["magenta"] if k % 3 == 1 else NEON["warm"])
            L2.energy = LIGHT_E * 0.7 * WASH
            o2 = bpy.data.objects.new("ave%d" % k, L2)
            o2.location = (p_[0], Y(p_[1]), 4.5)
            scene.collection.objects.link(o2)
            k += 1
    for yd in YARDS:
        L5 = bpy.data.lights.new("yd%d" % k, "AREA")
        L5.shape = "DISK"
        L5.size = 7.0
        L5.color = NEON["magenta"] if k % 2 else NEON["violet"]
        L5.energy = LIGHT_E * 1.0 * WASH
        o5 = bpy.data.objects.new("yd%d" % k, L5)
        o5.location = (yd["c"][0], Y(yd["c"][1]), 6.0)
        scene.collection.objects.link(o5)
        k += 1
    L3 = bpy.data.lights.new("lot", "AREA")
    L3.shape = "DISK"
    L3.size = 12.0
    L3.color = NEON["magenta"]
    L3.energy = LIGHT_E * 2.0 * (0.5 + WASH)
    o3 = bpy.data.objects.new("lot", L3)
    o3.location = (LOT[0] + LOT[2] / 2, Y(LOT[1] + LOT[3] / 2), 6.0)
    scene.collection.objects.link(o3)
    for (sx_, sy_, sz_, tg_, col_, e_) in SPOTS:
        Ls = bpy.data.lights.new("spot%d" % n, "SPOT")
        Ls.color = col_
        Ls.energy = e_ * LIGHT_E / 100.0
        Ls.spot_size = math.radians(38)
        Ls.spot_blend = 0.6
        Ls.shadow_soft_size = 0.3
        os_ = bpy.data.objects.new("spot%d" % n, Ls)
        os_.location = (sx_, sy_, sz_)
        dv = Vector(tg_) - Vector((sx_, sy_, sz_))
        os_.rotation_euler = dv.to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(os_)
        n += 1
    print("  lights", n + 1, flush=True)


def build_world():
    build_floors()
    build_walls()
    build_roofs()
    build_big_top()
    build_rides()
    build_coaster()
    build_gate()
    build_props()
    build_groves()
    build_outskirts()
    build_lights()


# ======================================================================= rendu
EXPOSURE = float(os.environ.get("HC_EXPOSURE", "0.15"))
SUN_E = float(os.environ.get("HC_MOON", "1.6"))
SKY = float(os.environ.get("HC_SKY", "0.22"))
SAT = float(os.environ.get("HC_SAT", "1.3"))
CON = float(os.environ.get("HC_CON", "1.15"))
LIFT = float(os.environ.get("HC_LIFT", "10"))


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
    bg.inputs[0].default_value = (0.14, 0.12, 0.4, 1)    # nuit violette (ambiance de la maquette)
    bg.inputs[1].default_value = SKY
    moon = bpy.data.lights.new("moon", "SUN")
    moon.energy = SUN_E
    moon.color = (0.45, 0.55, 1.0)
    moon.angle = math.radians(1.5)
    so = bpy.data.objects.new("moon", moon)
    sc.collection.objects.link(so)
    d = Vector((0.3, -0.4, -0.85)).normalized()
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


MASK_SOLID = ("walls_", "front_", "hullwalls", "props")
MASK_DECOR = ("furn_", "clutter")
MASK_SKIP = ("ground", "floor_", "roof_", "cut_", "_", "skirt")
OCC_SKIP = ("ground", "floor_", "cut_", "_", "skirt")


def mask_class(name):
    if name.startswith(MASK_SKIP):
        return None
    if name.startswith(MASK_SOLID):
        return (1.0, 0.0, 0.0)
    if name.startswith(MASK_DECOR):
        return (0.0, 1.0, 0.0)
    return (0.0, 0.0, 1.0)


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
            "projection": "ground_square", "margin": MARGIN, "biome": "haunted_carnival",
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
        # Intérieurs : par bâtiment à toit, SEULS son toit et le haut de son mur sud (front_) sont
        # masqués (chapiteau : toit seul, la paroi est basse). Même caméra que « full ».
        pw, ph = frame(cam, -MARGIN, W + MARGIN, -MARGIN, H + MARGIN)
        scene.render.use_border = True
        scene.render.use_crop_to_border = True
        tb = 0.0
        tW, tH = W + 2 * MARGIN, H + 2 * MARGIN
        up = int(math.ceil(6.8 * math.tan(TILT)))
        only = os.environ.get("HC_INT_ONLY", "")
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
            objs_off = [o for o in bpy.data.objects if o.name in ("roof_%d" % bid, "front_%d" % bid)]
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
