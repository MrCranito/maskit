"""Scène Blender complète de la surface des Terres gelées (base militaire abandonnée en croix sur
un plateau de glace façon maquette docs/reference/cartes_2.png, colonne du milieu), construite
depuis le layout JSON exporté par tools/prerender/export_layout.gd (4e argument :
res://data/worlds/world_05_frozen_lands.tres), rendue en Cycles. Même pipeline, mêmes passes et
même projection que fw_scene.py / ss_scene.py / mall_scene.py.

Usage (bpy en module) :
  python3 fl_scene.py <layout.json> <out_dir> [ppc=24] [samples=16] [passes=full,int] [margin=4]
Passes : full (par morceaux, reprise possible : _chunks_full/) ; int (patch « sans toit » par
         bunker fermé : toit et haut du mur sud masqués) ; mask (emprise au sol réelle, vue
         zénithale, 4 px/case → mask.png) ; occ (ids d'occultation, même caméra que full) ;
         crop:x0;x1;y0;y1 ; view:x0;x1;y0;y1;tilt;ppc
Sorties : full.png, b<id>_in.png, mask.png, occ.png, render.json, layout.json (pour compose.py).

PROJECTION (identique à fw_scene.py) : caméra orthographique inclinée de TILT (38°) vers le nord,
  pixel_aspect_x = 1/cos(TILT) ; px = (cx + M) * ppc ; py = (cy + M) * ppc - z * tan(TILT) * ppc.
Repère Blender : 1 unité = 1 case. X = colonne, Y = -rangée, Z = hauteur.

Contenu : plateau de glace (neige bosselée, congères, crevasses bleutées, falaise de glace au bord)
posé sur une mer noire parsemée de banquise et d'icebergs ; base militaire : murs de béton gris
clair et plaques d'acier, bunkers à toit plat (grilles, antennes, radars, caissons, lampes rouges
d'alerte), laboratoires et baraquements ouverts vus en coupe (cuves cryogéniques cyan, paillasses,
lits, consoles), hangars (hélicoptère, autoneige), passerelles grillagées, cour intérieure ;
au centre le LABORATOIRE CIRCULAIRE aux grands cristaux de glace bleus lumineux (salle du boss,
anneau de consoles, plafond bas en verrière), tourelles de garde hexagonales aux angles sud,
dômes d'observation blancs, HÉLIPORT avec « H » peint, ponton d'évacuation, rampe d'accès ;
hors jeu : navire brise-glace échoué au nord-est, épave de bateau au sud-est. Lumière froide
blanc-bleu (ciel couvert), lampes cyan et rouges, lueur bleue des cristaux.
Les blocs génériques (NT, MB, frame, grade, render_chunked, render_mask, render_occ) sont repris
de ss_scene.py / fw_scene.py (mêmes formats de sortie que compose.py attend).
"""
import sys, json, math, random, time, os
import bpy, bmesh
from mathutils import Vector, Matrix, Euler, noise as mnoise

A = sys.argv[1:]
LAYOUT = json.load(open(A[0]))
OUT = A[1]
PPC = int(A[2]) if len(A) > 2 else 24
SAMPLES = int(A[3]) if len(A) > 3 else 16
PASSES = (A[4] if len(A) > 4 else "full").split(",")
MARGIN = int(A[5]) if len(A) > 5 else 4
os.makedirs(OUT, exist_ok=True)

TILT_DEG = float(os.environ.get("FL_TILT", "38"))
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


def mat_solar(name):
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    fu = s.m_("FRACT", s.mul(u, 3.0))
    fv = s.m_("FRACT", s.mul(v, 3.0))
    gu = s.sub(1.0, s.mul(s.smooth(fu, 0.0, 0.06), s.smooth(fu, 1.0, 0.94)))
    gv = s.sub(1.0, s.mul(s.smooth(fv, 0.0, 0.06), s.smooth(fv, 1.0, 0.94)))
    j = s.m_("MAXIMUM", gu, gv)
    n = s.noise(s.obj(), 2.0, 3, 0.5)
    col = s.mix(s.mul(n, 0.6), (0.03, 0.07, 0.22), (0.06, 0.14, 0.38))
    col = s.mix(j, col, (0.55, 0.6, 0.68))
    return s.done(col, 0.18, None, 0.6)



# ======================================================================= maillages (repris de fw_scene.py)
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



# ======================================================================= matériaux des Terres gelées
def mat_snow(name, base=(0.88, 0.93, 1.0)):
    """Neige : bosses larges + grain fin, ombres bleutées dans les creux, scintillement discret."""
    s = NT(name)
    o = s.obj()
    n1 = s.noise(o, 0.35, 3, 0.5)
    n2 = s.noise(o, 2.2, 5, 0.6)
    n3 = s.noise(o, 14.0, 2, 0.5)
    col = s.mix(s.smooth(n1, 0.3, 0.75, 0.0, 0.45), base, (0.6, 0.72, 0.9))
    col = s.mix(s.mul(n2, 0.3), col, (0.92, 0.96, 1.0))
    col = s.mix(s.smooth(s.noise(o, 0.12, 2, 0.5), 0.4, 0.75, 0.0, 0.35), col, (0.62, 0.72, 0.88))
    h = s.add(s.add(s.mul(n1, 1.0), s.mul(n2, 0.35)), s.mul(n3, 0.05))
    rgh = s.add(0.55, s.mul(n3, 0.3))
    s.done(col, normal=s.bump(h, 0.9, 0.08), rough_sock=rgh)
    s.b.inputs["Subsurface Weight"].default_value = 0.2
    s.b.inputs["Subsurface Radius"].default_value = (0.3, 0.5, 0.8)
    return s.m


def mat_ice(name, base=(0.4, 0.68, 0.92), dark=(0.08, 0.22, 0.5)):
    """Glace bleue (falaises, icebergs, crevasses) : stries, transparence simulée par émission."""
    s = NT(name)
    o = s.obj()
    _, _, z = s.sep(o)
    n = s.noise(o, 3.0, 4, 0.55)
    st = s.noise(s.comb(s.mul(s.sep(o)[0], 0.3), s.mul(z, 6.0), 0.0), 8.0, 3, 0.5)
    col = s.mix(s.mul(n, 0.6), base, dark)
    col = s.mix(s.smooth(st, 0.6, 0.8, 0.0, 0.5), col, (0.8, 0.92, 1.0))
    col = s.mix(s.smooth(z, 0.6, 1.2), col, (0.9, 0.95, 1.0))
    s.done(col, 0.15, s.bump(s.add(n, s.mul(st, 0.3)), 0.5, 0.05))
    s.b.inputs["Emission Color"].default_value = (*dark, 1)
    s.b.inputs["Emission Strength"].default_value = 0.35
    return s.m


def mat_sea(name):
    """Eau noire : très sombre, reflets bleus, houle légère."""
    s = NT(name)
    o = s.obj()
    n = s.noise(o, 0.5, 5, 0.6)
    n2 = s.noise(o, 3.0, 4, 0.5)
    col = s.mix(s.mul(n, 0.7), (0.012, 0.035, 0.1), (0.035, 0.09, 0.2))
    col = s.mix(s.smooth(n2, 0.6, 0.75, 0.0, 0.55), col, (0.14, 0.3, 0.5))
    s.done(col, 0.04, s.bump(s.add(n, s.mul(n2, 0.5)), 0.5, 0.05), 0.0)
    s.b.inputs["Specular IOR Level"].default_value = 1.0
    return s.m


def mat_concrete(name, base=(0.55, 0.58, 0.64), dark=(0.2, 0.22, 0.26), pw=2.0, ph=1.0, stripe=None):
    """Béton coulé : grands panneaux, coulures, éclats, givre sur les arêtes hautes."""
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    o = s.obj()
    fu = s.m_("FRACT", s.m_("DIVIDE", u, pw))
    fv = s.m_("FRACT", s.m_("DIVIDE", v, ph))
    iu = s.m_("FLOOR", s.m_("DIVIDE", u, pw))
    iv = s.m_("FLOOR", s.m_("DIVIDE", v, ph))
    r = s.white(s.comb(iu, iv, 5.1))
    g = 0.02
    ju = s.sub(1.0, s.mul(s.smooth(fu, 0.0, g / pw), s.smooth(fu, 1.0, 1.0 - g / pw)))
    jv = s.sub(1.0, s.mul(s.smooth(fv, 0.0, g / ph), s.smooth(fv, 1.0, 1.0 - g / ph)))
    joint = s.m_("MAXIMUM", ju, jv)
    col = s.mix(s.mul(r, 0.25), base, tuple(min(1.0, x * 1.15) for x in base))
    n = s.noise(o, 2.5, 6, 0.65)
    stains = s.noise(s.comb(s.mul(u, 0.7), s.mul(v, 6.0), 0.0), 3.0, 4, 0.6)
    col = s.mix(s.smooth(n, 0.5, 0.85, 0.0, 0.45), col, tuple(x * 0.6 for x in base))
    col = s.mix(s.smooth(stains, 0.6, 0.85, 0.0, 0.5), col, tuple(x * 0.7 for x in base))
    if stripe:
        sc, v0, v1 = stripe
        band = s.mul(s.smooth(v, v0 - 0.01, v0), s.sub(1.0, s.smooth(v, v1, v1 + 0.01)))
        col = s.mix(band, col, sc)
    col = s.mix(s.mul(joint, 0.9), col, dark)
    chips = s.voronoi(s.vmul(o, 6.0), 1.0)
    chip = s.smooth(chips, 0.1, 0.04)
    col = s.mix(s.mul(chip, 0.6), col, tuple(x * 0.75 for x in base))
    h = s.add(s.mul(joint, -1.0), s.add(s.mul(n, 0.12), s.mul(chip, -0.4)))
    s.done(col, normal=s.bump(h, 0.4, 0.02), metal=0.0, rough_sock=s.add(0.8, s.mul(n, 0.15)))
    return s.m


def mat_metal_plate(name, base=(0.4, 0.45, 0.52), dark=(0.1, 0.12, 0.15), pw=1.0, ph=0.5):
    return mat_panels(name, base, dark, pw=pw, ph=ph, metal=0.6, rough=0.42, rivets=True, var=0.15, grime=0.4)


def mat_crystal(name, c=(0.2, 0.62, 1.0), strength=1.6):
    """Cristal de glace lumineux : cœur émissif, facettes, veines plus claires."""
    s = NT(name)
    o = s.obj()
    n = s.noise(o, 3.0, 4, 0.5)
    _, _, z = s.sep(o)
    col = s.mix(s.mul(n, 0.6), c, (0.6, 0.9, 1.0))
    s.done(col, 0.1, None, 0.0)
    em = s.mix(s.smooth(z, 0.0, 2.5, 0.2, 1.0), (0.05, 0.2, 0.45), c)
    s.l(em, s.b.inputs["Emission Color"])
    s.b.inputs["Emission Strength"].default_value = strength
    return s.m


def mat_grating(name):
    """Caillebotis de passerelle : lames fines sur fond sombre."""
    return mat_floor(name, (0.34, 0.37, 0.41), (0.08, 0.09, 0.1), cell=1.0, sub=1, rough=0.55, grate=True, wear=0.5)


def mat_helipad(name):
    """Dalle d'héliport : béton sombre strié, peinture usée (le « H » est un objet à part)."""
    return mat_floor(name, (0.18, 0.2, 0.23), (0.06, 0.06, 0.07), cell=2.0, sub=2, var=0.2, rough=0.7, metal=0.0, wear=0.6)


def mat_paint(name, c, wear=0.6):
    s = NT(name)
    n = s.noise(s.obj(), 10.0, 4, 0.6)
    col = s.mix(s.smooth(n, 0.5, 0.75, 0.0, wear), c, tuple(x * 0.35 for x in c))
    return s.done(col, 0.7)


def mat_sky_world():
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    return w


NEON = {"warm": (1.0, 0.78, 0.5), "white": (0.85, 0.93, 1.0), "cyan": (0.3, 0.85, 1.0), "red": (1.0, 0.12, 0.08),
        "orange": (1.0, 0.5, 0.12), "green": (0.3, 1.0, 0.5), "blue": (0.3, 0.5, 1.0), "amber": (1.0, 0.75, 0.3)}


def build_materials():
    mat_snow("snow")
    mat_snow("snow_dirty", (0.72, 0.76, 0.82))
    mat_ice("ice")
    mat_ice("ice_dark", (0.2, 0.42, 0.7), (0.05, 0.14, 0.3))
    mat_ice("iceberg", (0.6, 0.8, 0.95), (0.25, 0.45, 0.7))
    mat_sea("sea")
    mat_concrete("concrete", (0.42, 0.45, 0.5), (0.14, 0.15, 0.18), stripe=((0.26, 0.28, 0.31), 0.0, 0.12))
    mat_concrete("concrete_in", (0.55, 0.58, 0.64), (0.2, 0.22, 0.26), pw=1.5, ph=0.8)
    mat_concrete("concrete_top", (0.38, 0.41, 0.46), (0.15, 0.16, 0.19), pw=2.0, ph=2.0)
    mat_concrete("concrete_dark", (0.28, 0.3, 0.35), (0.09, 0.1, 0.12))
    mat_metal_plate("steel_plate")
    mat_metal_plate("steel_dark", (0.2, 0.23, 0.27), (0.05, 0.06, 0.07), pw=0.6, ph=0.6)
    mat_metal_plate("roof_plate", (0.33, 0.36, 0.4), (0.09, 0.1, 0.12), pw=1.2, ph=0.9)
    mat_panels("hull_ship", (0.12, 0.13, 0.15), (0.04, 0.04, 0.05), pw=1.5, ph=0.6, metal=0.55, rough=0.5, rivets=True,
               stripe=((0.6, 0.12, 0.1), 0.3, 0.9))
    mat_panels("hull_white", (0.78, 0.8, 0.82), (0.3, 0.32, 0.35), pw=1.0, ph=0.6, metal=0.3, rough=0.5, grime=0.5)
    mat_panels("radiator", (0.62, 0.64, 0.66), (0.2, 0.2, 0.22), pw=0.12, ph=4.0, metal=0.7, rough=0.3, var=0.04)
    mat_grating("grating")
    mat_floor("floor_in", (0.28, 0.3, 0.34), (0.08, 0.09, 0.11), cell=2.0, sub=2, var=0.35, rough=0.6, metal=0.1, wear=0.6)
    mat_floor("floor_lab", (0.46, 0.52, 0.6), (0.14, 0.16, 0.2), cell=1.0, sub=2, var=0.2, rough=0.3, metal=0.1, wear=0.4)
    mat_floor("floor_hangar", (0.3, 0.32, 0.35), (0.08, 0.08, 0.1), cell=2.0, sub=4, rough=0.6, wear=0.6)
    mat_floor("floor_yard", (0.4, 0.43, 0.48), (0.12, 0.13, 0.15), cell=2.0, sub=2, var=0.2, rough=0.75, metal=0.0, wear=0.7)
    mat_floor("floor_boss", (0.16, 0.22, 0.32), (0.05, 0.07, 0.12), cell=1.0, sub=2, rough=0.35, metal=0.4)
    mat_helipad("helipad")

    mat_hazard("hazard")
    mat_hazard("hazard_red", (0.75, 0.1, 0.08), (0.9, 0.92, 0.95), w=0.3)
    mat_paint("paint_yellow", (0.95, 0.6, 0.1), 0.4)
    mat_paint("paint_white", (0.85, 0.88, 0.9))
    mat_paint("paint_red", (0.7, 0.12, 0.1))
    mat_simple("metal", (0.55, 0.58, 0.62), 0.35, 0.8, 0.15)
    mat_simple("metal_dark", (0.13, 0.14, 0.17), 0.45, 0.7, 0.2)
    mat_simple("metal_mid", (0.32, 0.34, 0.39), 0.4, 0.7, 0.2)
    mat_simple("rubber", (0.04, 0.04, 0.05), 0.8, 0.0, 0.1)
    mat_simple("white_panel", (0.8, 0.82, 0.85), 0.35, 0.2, 0.08)
    mat_simple("olive", (0.3, 0.34, 0.22), 0.7, 0.0, 0.25)
    mat_simple("olive_dark", (0.18, 0.2, 0.13), 0.7, 0.0, 0.2)
    mat_simple("canvas", (0.45, 0.42, 0.32), 0.9, 0.0, 0.2)
    mat_simple("crate_grey", (0.42, 0.45, 0.48), 0.6, 0.3, 0.2)
    mat_simple("crate_red", (0.75, 0.12, 0.08), 0.55, 0.1, 0.25)
    mat_simple("drum_red", (0.8, 0.1, 0.06), 0.45, 0.3)
    mat_simple("drum_grey", (0.4, 0.42, 0.45), 0.5, 0.4)
    mat_simple("sandbag", (0.5, 0.46, 0.36), 0.95, 0.0, 0.3)
    mat_simple("mattress", (0.3, 0.36, 0.3), 0.9, 0.0, 0.15)
    mat_simple("sheet", (0.82, 0.84, 0.86), 0.9, 0.0, 0.08)
    mat_simple("wood", (0.42, 0.32, 0.22), 0.8, 0.0, 0.3)
    mat_simple("cable", (0.05, 0.05, 0.06), 0.6, 0.0, 0.1)
    mat_simple("cable_red", (0.5, 0.06, 0.05), 0.6)
    mat_simple("cable_yellow", (0.75, 0.55, 0.08), 0.6)
    mat_simple("doorway", (0.02, 0.025, 0.035), 0.9, var=0.1)
    mat_simple("rust", (0.45, 0.22, 0.12), 0.8, 0.2, 0.4)
    mat_simple("fluid", (0.2, 0.6, 0.8), 0.1, emit=((0.3, 0.8, 1.0), 2.0))
    mat_crystal("crystal")
    mat_crystal("crystal_dim", (0.25, 0.6, 0.9), 1.0)
    mat_decal("scorch", (0.025, 0.02, 0.018), 0.9)
    mat_decal("oil", (0.04, 0.035, 0.03), 0.6)
    mat_decal("ice_patch", (0.6, 0.8, 0.95), 0.55, 2.0)
    mat_glass("glass")
    mat_glass("glass_tank", (0.5, 0.85, 0.95), 0.25)
    for k, c in NEON.items():
        mat_emit("neon_" + k, c, 7.0)
        mat_emit("lamp_" + k, c, 3.0)
    mat_screen("screen_cyan", (0.2, 0.8, 1.0), 3.0)
    mat_screen("screen_green", (0.25, 1.0, 0.45), 2.6)
    mat_screen("screen_orange", (1.0, 0.55, 0.15), 2.6)
    mat_screen("screen_red", (1.0, 0.15, 0.1), 2.6)
    mat_emit("window", (0.9, 0.8, 0.55), 2.2)
    mat_emit("window_cold", (0.65, 0.85, 1.0), 2.0)
    mat_emit("sky_white", (0.9, 0.95, 1.0), 1.0)


# ======================================================================= analyse du layout
ROOMS = LAYOUT.get("rooms", [])
ROOM_BY_ID = {r["id"]: r for r in ROOMS}
MODS = C.get("modules", [])
MOD_BY_ROOM = {m["room"]: m for m in MODS}
BLD = {b["id"]: b for b in LAYOUT.get("buildings", [])}
DOOR_CELLS = {tuple(d["cell"]): d for d in LAYOUT.get("doors", [])}
STAIRS = {tuple(s["cell"]): s for s in LAYOUT.get("stairs", [])}
EXTRACT = set(tuple(c) for c in LAYOUT.get("extraction", []))
LAB = C.get("lab", [W / 2, H / 2, 8.5])
SPINE = C.get("spine", [36, 4])
HELI = C.get("heliport", [5, 12, 13, 13])
DOCK = C.get("dock", [W - 17, 93, 12, 8])
EXTR = int(C.get("extractions", 2))
BRIDGE = C.get("bridge", None)

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
    return r["tags"][0] if r and r.get("tags") else "snow"


def mod_of(rid):
    return MOD_BY_ROOM.get(rid)


CELL_BLD = {}
for b in LAYOUT.get("buildings", []):
    x, y, w, h = b["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            CELL_BLD.setdefault((xx, yy), b["id"])
ROUND = {}
for m in MODS:
    if m.get("round") and m["building"] >= 0:
        ROUND[m["building"]] = m["round"]
LAB_ROUND = None
for m in MODS:
    if m.get("round") and m["role"] == "crystal_lab":
        LAB_ROUND = m
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

LAMP_POS = []
FLOOD_POS = []
H_OPEN = 1.25        # murs des modules ouverts (vus en coupe)
H_ROOF = 1.9         # murs des bunkers à toit
H_CUT = 0.7          # hauteur du mur sud dans la passe « int »
H_DOOR = 0.95
H_CLIFF = 1.1        # falaise de glace (bord du plateau) au-dessus de la neige
SEA_Z = -2.2         # niveau de la mer sous le plateau
H_PARAPET = 0.55     # murets de la cour et des passerelles


def is_cliff(x, y):
    """Mur de bord de plateau : voisin (8) d'une case d'eau."""
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if tile(x + dx, y + dy) == 0:
                return True
    return False


def floor_mat(rid, cell):
    role = role_of(rid)
    if role in ("walkway",):
        return "grating"
    if role in ("yard", "gate", "ramp"):
        return "floor_yard"
    if role in ("hangar", "garage"):
        return "floor_hangar"
    if role in ("lab", "cryo_vault", "infirmary", "observatory"):
        return "floor_lab"
    if role == "crystal_lab":
        return "floor_boss"
    return "floor_in"


def light_of(rid):
    role = role_of(rid)
    if role in ("armory", "cryo_vault", "guard_tower"):
        return "red", 1.0
    if role in ("lab", "infirmary", "observatory", "radio", "command"):
        return "cyan", 1.0
    if role in ("crystal_lab",):
        return "blue", 0.6
    if role in ("barracks", "mess_hall", "closet", "command", "storage", "workshop", "bunker", "hangar", "garage", "generator"):
        return "warm", 2.4
    return "white", 0.8


# ======================================================================= terrain : mer, plateau, falaises
def build_terrain():
    tanT = math.tan(TILT)
    # mer : plan noir sous tout le cadre (décalé pour couvrir la projection inclinée)
    sea = MB()
    x0, x1 = -MARGIN - 20, W + MARGIN + 20
    r0, r1 = -MARGIN - 30, H + MARGIN + 30
    sh = -SEA_Z * tanT
    sea.poly([(x0, Y(r1) - sh, SEA_Z), (x1, Y(r1) - sh, SEA_Z), (x1, Y(r0) + sh, SEA_Z), (x0, Y(r0) + sh, SEA_Z)], "sea",
             [(x0, Y(r1)), (x1, Y(r1)), (x1, Y(r0)), (x0, Y(r0))])
    sea.to_object("_sea", "world")
    # plaques de banquise dérivante dans l'eau (hors plateau)
    ice = MB()
    rng = random.Random(SEED * 3 + 7)
    for k in range(160):
        px = rng.uniform(-MARGIN, W + MARGIN)
        py = rng.uniform(-MARGIN, H + MARGIN)
        cx, cy = int(px), int(py)
        near = False
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                if tile(cx + dx, cy + dy) != 0:
                    near = True
        if near:
            continue
        n = rng.randint(5, 8)
        rr = rng.uniform(0.8, 2.6)
        pts = []
        for i in range(n):
            a = i / n * math.tau
            rad = rr * rng.uniform(0.6, 1.0)
            pts.append((px + math.cos(a) * rad, Y(py) + math.sin(a) * rad))
        z0 = SEA_Z - 0.3
        z1 = SEA_Z + rng.uniform(0.08, 0.25)
        st = len(ice.V)
        ice.poly([(x_, y_, z1) for (x_, y_) in pts], "snow_dirty")
        for i in range(n):
            a_, b_ = pts[i], pts[(i + 1) % n]
            ice.poly([(a_[0], a_[1], z0), (b_[0], b_[1], z0), (b_[0], b_[1], z1), (a_[0], a_[1], z1)], "ice")
    ice.to_object("_floes", "world")
    # plateau : une face de neige par case praticable extérieure (STREET) + falaise au bord
    snow = MB()
    cliff = MB()
    rng2 = random.Random(SEED * 11 + 3)
    for y in range(H):
        for x in range(W):
            t = tile(x, y)
            if t == 1:
                X0, X1, YN, YS = x, x + 1, Y(y), Y(y + 1)
                snow.poly([(X0, YS, 0.0), (X1, YS, 0.0), (X1, YN, 0.0), (X0, YN, 0.0)], "snow",
                          [(X0, YS), (X1, YS), (X1, YN), (X0, YN)])
    snow.to_object("ground_snow", "world")
    # falaise : murs de bord (tile 3 voisins d'eau) → bloc de glace du niveau de la mer jusqu'à
    # H_CLIFF, chapeau de neige ; faces vers l'eau en glace bleue striée.
    for y in range(H):
        for x in range(W):
            if tile(x, y) != 3 or not is_cliff(x, y):
                continue
            X0, X1, YN, YS = x, x + 1, Y(y), Y(y + 1)
            h = H_CLIFF + 0.7 * mnoise.noise(Vector((x * 0.45, y * 0.45, 0.0)))
            cliff.poly([(X0, YS, h), (X1, YS, h), (X1, YN, h), (X0, YN, h)], "snow", [(X0, YS), (X1, YS), (X1, YN), (X0, YN)])
            for side, dx, dy in (("S", 0, 1), ("N", 0, -1), ("E", 1, 0), ("W", -1, 0)):
                nt_ = tile(x + dx, y + dy)
                if nt_ == 3 and is_cliff(x + dx, y + dy):
                    continue
                if nt_ == 0:
                    z0 = SEA_Z - 0.6
                    mat = "ice"
                    # surplomb irrégulier
                    ov = 0.3 + 0.5 * rng2.random()
                else:
                    z0 = 0.0
                    mat = "snow_dirty"
                    ov = 0.0
                if side == "S":
                    pts = [(X0, YS - ov, z0), (X1, YS - ov, z0), (X1, YS, h), (X0, YS, h)]
                elif side == "N":
                    pts = [(X1, YN + ov, z0), (X0, YN + ov, z0), (X0, YN, h), (X1, YN, h)]
                elif side == "E":
                    pts = [(X1 + ov, YS, z0), (X1 + ov, YN, z0), (X1, YN, h), (X1, YS, h)]
                else:
                    pts = [(X0 - ov, YN, z0), (X0 - ov, YS, z0), (X0, YS, h), (X0, YN, h)]
                cliff.poly(pts, mat, [(0, z0), (1, z0), (1, h), (0, h)])
    cliff.to_object("cliff", "world")
    # congères (bosses de neige) et crevasses (contrat decor) sur le plateau
    dr = MB()
    for d in C.get("decor", []):
        if d["kind"] == "crevasse":
            px, py = d["pos"]
            sz = float(d["size"])
            rot = math.radians(float(d.get("rot", 0.0)))
            c, s = math.cos(rot), math.sin(rot)
            w_ = 0.7
            pts = []
            for (u, v) in ((-sz / 2, -w_), (sz / 2, -w_ * 0.6), (sz / 2, w_ * 0.6), (-sz / 2, w_)):
                pts.append((px + u * c - v * s, Y(py) + u * s + v * c))
            dr.poly([(a, b, 0.006) for (a, b) in pts], "ice_dark")
            dr.poly([(px + (a - px) * 1.25, Y(py) + (b - Y(py)) * 1.25, 0.004) for (a, b) in pts], "ice")
            dr.poly([(pts[0][0], pts[0][1], -0.9), (pts[1][0], pts[1][1], -0.9), (pts[1][0], pts[1][1], 0.0), (pts[0][0], pts[0][1], 0.0)], "ice_dark")
    rng3 = random.Random(SEED * 5 + 1)
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            if tile(x, y) != 1 or (x, y) in GAME_CELLS or (HELI[0] <= x < HELI[0] + HELI[2] and HELI[1] <= y < HELI[1] + HELI[3]) or (DOCK[0] <= x < DOCK[0] + DOCK[2] and DOCK[1] <= y < DOCK[1] + DOCK[3]):
                continue
            near_wall = any(tile(x + dx, y + dy) == 3 for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2))
            if rng3.random() > (0.16 if near_wall else 0.05):
                continue
            # pas sur les cases du jeu voisines (anneau 3×3 libre)
            if any(tile(x + dx, y + dy) != 1 for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                continue
            dr.sphere(x + 0.5 + rng3.uniform(-0.3, 0.3), Y(y) - 0.5 + rng3.uniform(-0.3, 0.3), -0.12, rng3.uniform(0.6, 1.4), "snow", 2,
                      rng3.uniform(1.0, 2.0), rng3.uniform(0.8, 1.4), rng3.uniform(0.2, 0.36), nscale=0.8, rng=rng3)
    dr.to_object("_drifts", "world")


# ======================================================================= sols intérieurs et marquages
def build_floors():
    mbs = {}
    for y in range(H):
        for x in range(W):
            t = tile(x, y)
            if t not in (2, 4, 5, 6):
                continue
            rid = CELL_ROOM.get((x, y), -1)
            mat = floor_mat(rid, (x, y))
            bid = CELL_BLD.get((x, y), -1)
            key = ("floor_%d" % bid) if bid >= 0 else "ground"
            mb = mbs.setdefault(key, MB())
            X0, X1, YN, YS = x, x + 1, Y(y), Y(y + 1)
            mb.poly([(X0, YS, 0.0), (X1, YS, 0.0), (X1, YN, 0.0), (X0, YN, 0.0)], mat,
                    [(X0, YS), (X1, YS), (X1, YN), (X0, YN)])
    mk = MB()
    # passerelles : rails latéraux surélevés, traverses
    for r in ROOMS:
        role = r["tags"][0] if r.get("tags") else ""
        x, y, w, h = r["rect"]
        if role == "walkway":
            vert = h >= w
            if vert:
                for ex in (x + 0.06, x + w - 0.12):
                    mk.box(ex, Y(y + h), 0.0, ex + 0.06, Y(y), 0.06, "metal_dark")
                for k in range(0, h, 2):
                    mk.box(x + 0.1, Y(y + k + 0.55), 0.0, x + w - 0.1, Y(y + k + 0.45), 0.02, "metal_mid")
                # galerie couverte : poteaux + arceaux + lampes (arceaux fins, le sol reste visible)
                for k in range(1, h, 3):
                    for ex in (x - 0.02, x + w - 0.08):
                        mk.box(ex, Y(y + k + 0.55), 0.0, ex + 0.1, Y(y + k + 0.45), 1.5, "steel_dark")
                    mk.box(x - 0.02, Y(y + k + 0.56), 1.5, x + w + 0.08, Y(y + k + 0.44), 1.6, "steel_dark")
                    mk.box(x + w / 2 - 0.25, Y(y + k + 0.54), 1.42, x + w / 2 + 0.25, Y(y + k + 0.46), 1.5, "lamp_warm")
                for ex in (x - 0.02, x + w - 0.08):
                    mk.box(ex, Y(y + h), 1.5, ex + 0.1, Y(y), 1.58, "steel_dark")
            else:
                for ey in (y + 0.06, y + h - 0.12):
                    mk.box(x, Y(ey + 0.06), 0.0, x + w, Y(ey), 0.06, "metal_dark")
                for k in range(0, w, 2):
                    mk.box(x + k + 0.45, Y(y + h - 0.1), 0.0, x + k + 0.55, Y(y + 0.1), 0.02, "metal_mid")
                for k in range(1, w, 3):
                    for ey in (y - 0.02, y + h - 0.08):
                        mk.box(x + k + 0.45, Y(ey + 0.1), 0.0, x + k + 0.55, Y(ey), 1.5, "steel_dark")
                    mk.box(x + k + 0.44, Y(y + h + 0.08), 1.5, x + k + 0.56, Y(y - 0.02), 1.6, "steel_dark")
                    mk.box(x + k + 0.46, Y(y + h / 2 + 0.25), 1.42, x + k + 0.54, Y(y + h / 2 - 0.25), 1.5, "lamp_warm")
                for ey in (y - 0.02, y + h - 0.08):
                    mk.box(x, Y(ey + 0.1), 1.5, x + w, Y(ey), 1.58, "steel_dark")
            # pont d'accès : pilotis dans l'eau, tablier en caillebotis, bouées rouges
            if BRIDGE and y >= BRIDGE[1]:
                for k in range(0, h, 2):
                    for ex in (x - 0.3, x + w + 0.3):
                        mk.cyl(ex, Y(y + k + 0.5), SEA_Z - 0.5, 0.0, 0.14, "rust", 8)
                    mk.box(x - 0.4, Y(y + k + 0.6), -0.15, x + w + 0.4, Y(y + k + 0.4), -0.02, "steel_dark")
                for k in range(0, h, 4):
                    mk.sphere(x - 0.3, Y(y + k + 1.5), 0.75, 0.1, "neon_red", 1)
                    mk.sphere(x + w + 0.3, Y(y + k + 1.5), 0.75, 0.1, "neon_red", 1)
        if role in ("hangar", "garage"):
            for (a0, a1, b0, b1) in ((x + 0.3, x + w - 0.3, y + 0.3, y + 0.6), (x + 0.3, x + w - 0.3, y + h - 0.6, y + h - 0.3)):
                mk.box(a0, Y(b1), 0.0, a1, Y(b0), 0.012, "hazard")
        if role == "yard":
            # marquages au sol : bandes jaunes le long des bords, cercle central autour du labo
            mk.box(x + 0.2, Y(y + h - 0.2), 0.0, x + w - 0.2, Y(y + h - 0.32), 0.008, "paint_yellow")
            mk.box(x + 0.2, Y(y + 0.32), 0.0, x + w - 0.2, Y(y + 0.2), 0.008, "paint_yellow")
    # héliport : dalle + cercle + « H »
    hx, hy, hw, hh = HELI
    cx, cy = hx + hw / 2, hy + hh / 2
    mk.box(hx + 0.4, Y(hy + hh - 0.4), 0.0, hx + hw - 0.4, Y(hy + 0.4), 0.06, "helipad")
    R = min(hw, hh) * 0.36
    seg = 64
    for i in range(seg):
        a0, a1 = i / seg * math.tau, (i + 1) / seg * math.tau
        mk.poly([(cx + math.cos(a0) * R, Y(cy) + math.sin(a0) * R, 0.065), (cx + math.cos(a1) * R, Y(cy) + math.sin(a1) * R, 0.065),
                 (cx + math.cos(a1) * (R + 0.25), Y(cy) + math.sin(a1) * (R + 0.25), 0.065), (cx + math.cos(a0) * (R + 0.25), Y(cy) + math.sin(a0) * (R + 0.25), 0.065)], "paint_yellow")
    hs = R * 0.62
    mk.box(cx - hs, Y(cy) - hs, 0.065, cx - hs + 0.28, Y(cy) + hs, 0.07, "paint_yellow")
    mk.box(cx + hs - 0.28, Y(cy) - hs, 0.065, cx + hs, Y(cy) + hs, 0.07, "paint_yellow")
    mk.box(cx - hs, Y(cy) - 0.14, 0.065, cx + hs, Y(cy) + 0.14, 0.07, "paint_yellow")
    # bordure de l'héliport : rambarde basse et lampes
    for (a0, a1, b0, b1) in ((hx + 0.4, hx + hw - 0.4, hy + 0.4, hy + 0.5), (hx + 0.4, hx + hw - 0.4, hy + hh - 0.5, hy + hh - 0.4),
                             (hx + 0.4, hx + 0.5, hy + 0.4, hy + hh - 0.4), (hx + hw - 0.5, hx + hw - 0.4, hy + 0.4, hy + hh - 0.4)):
        mk.box(a0, Y(b1), 0.06, a1, Y(b0), 0.1, "hazard")
    for (lx, ly) in ((hx + 0.6, hy + 0.6), (hx + hw - 0.6, hy + 0.6), (hx + 0.6, hy + hh - 0.6), (hx + hw - 0.6, hy + hh - 0.6)):
        mk.sphere(lx, Y(ly), 0.16, 0.1, "neon_red" if (lx + ly) % 2 < 1 else "neon_amber", 1)
    # ponton d'évacuation : planches de bois sur pilotis vers l'eau, bouée, lampes
    dx_, dy_, dw_, dh_ = DOCK
    for k in range(dw_ * 3):
        mk.box(dx_ + k / 3.0 + 0.02, Y(dy_ + dh_), 0.0, dx_ + (k + 1) / 3.0 - 0.02, Y(dy_), 0.05, "wood")
    for k in range(4):
        mk.box(dx_ + 0.3 + k * (dw_ - 0.6) / 3 - 0.08, Y(dy_ + dh_ - 0.3) - 0.08, 0.05, dx_ + 0.3 + k * (dw_ - 0.6) / 3 + 0.08, Y(dy_ + dh_ - 0.3) + 0.08, 0.9, "wood")
        mk.box(dx_ + 0.3 + k * (dw_ - 0.6) / 3 - 0.08, Y(dy_ + 0.3) - 0.08, 0.05, dx_ + 0.3 + k * (dw_ - 0.6) / 3 + 0.08, Y(dy_ + 0.3) + 0.08, 0.9, "wood")
    mk.box(dx_ + 0.3, Y(dy_ + dh_ - 0.3) - 0.03, 0.85, dx_ + dw_ - 0.3, Y(dy_ + dh_ - 0.3) + 0.03, 0.92, "wood")
    mk.box(dx_ + 0.3, Y(dy_ + 0.3) - 0.03, 0.85, dx_ + dw_ - 0.3, Y(dy_ + 0.3) + 0.03, 0.92, "wood")
    for r in ROOMS:
        if (r["tags"][0] if r.get("tags") else "") != "yard":
            continue
        x, y, w, h = r["rect"]
        for (lx, ly) in ((x + 1.5, y + 1.5), (x + w - 1.5, y + 1.5), (x + 1.5, y + h - 1.5), (x + w - 1.5, y + h - 1.5)):
            if (int(lx), int(ly)) in GAME_CELLS:
                continue
            mk.cyl(lx, Y(ly), 0.0, 2.2, 0.06, "metal_dark", 6)
            mk.box(lx - 0.25, Y(ly) - 0.1, 2.2, lx + 0.25, Y(ly) + 0.1, 2.35, "metal_dark")
            mk.box(lx - 0.2, Y(ly) - 0.08, 2.17, lx + 0.2, Y(ly) + 0.08, 2.2, "lamp_warm")
            LAMP_POS.append((lx, Y(ly), 2.1))
    for (ex, ey) in EXTRACT:
        mk.box(ex + 0.1, Y(ey + 0.9), 0.07, ex + 0.9, Y(ey + 0.1), 0.085, "hazard")
        mk.box(ex + 0.2, Y(ey + 0.8), 0.085, ex + 0.8, Y(ey + 0.2), 0.09, "paint_white")
    for (sx, sy), st in STAIRS.items():
        mk.cyl(sx + 0.5, Y(sy) - 0.5, 0.0, 0.04, 0.46, "metal", 24)
        mk.cyl(sx + 0.5, Y(sy) - 0.5, 0.0, 0.05, 0.36, "neon_cyan", 24)
    mk.to_object("ground_marks", "world")
    for key, mb in mbs.items():
        mb.to_object(key, "world")


# ======================================================================= murs
def wall_h(x, y):
    if tile(x, y) != 3:
        return 0.0
    if is_cliff(x, y):
        return H_CLIFF
    b = CELL_BLD.get((x, y))
    if b is not None and BLD[b]["arch"] in ("fl_bunker", "fl_hangar"):
        return H_ROOF
    if b is not None and BLD[b]["arch"] == "fl_tower":
        return 1.0
    if b is not None and BLD[b]["arch"] == "fl_dome":
        return 0.9
    if b is not None and BLD[b]["arch"] == "fl_lab":
        return 1.0
    # murets des passerelles / cour / rampe : bas (vus en coupe) ; modules ouverts : H_OPEN
    rs = set()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        if walk(x + dx, y + dy):
            rs.add(role_of(CELL_ROOM.get((x + dx, y + dy), -1)))
    if rs and rs <= {"walkway", "yard", "gate", "ramp", "snow", "heliport", "dock", "crystal_lab"}:
        return H_PARAPET
    return H_OPEN


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


SIDES = (("S", 0, 1), ("N", 0, -1), ("E", 1, 0), ("W", -1, 0))
DOOR_GLOWS = []
ALARM_POS = []


def build_walls():
    """Murs case par case : béton clair côté salle, béton sombre / plaques d'acier côté extérieur,
    chapeau enneigé ; murs des bunkers dans walls_<id> (haut du mur sud dans front_<id>, masqué par
    la passe int). Encadrements des portes, lampes d'alerte rouges sur les murs extérieurs."""
    mbs = {}
    trims = {}

    def target(x, y, upper_south=False):
        b = CELL_BLD.get((x, y))
        if b is None:
            return mbs.setdefault("basewalls", MB())
        if upper_south:
            return mbs.setdefault("front_%d" % b, MB())
        return mbs.setdefault("walls_%d" % b, MB())

    round_cells = set()
    for bid, (rcx, rcy, rr) in ROUND.items():
        bx, by, bw, bh = BLD[bid]["rect"]
        for yy in range(by, by + bh):
            for xx in range(bx, bx + bw):
                if tile(xx, yy) == 3:
                    round_cells.add((xx, yy))
    if LAB_ROUND:
        bx, by, bw, bh = LAB_ROUND["rect"]
        rcx, rcy, rr = LAB_ROUND["round"]
        for yy in range(by, by + bh):
            for xx in range(bx, bx + bw):
                if tile(xx, yy) == 3 and math.hypot(xx + 0.5 - rcx, yy + 0.5 - rcy) < rr + 1.6:
                    round_cells.add((xx, yy))
    rngw = random.Random(SEED * 17)
    for y in range(H):
        for x in range(W):
            if tile(x, y) != 3 or (x, y) in round_cells or is_cliff(x, y):
                continue
            h = wall_h(x, y)
            b = CELL_BLD.get((x, y))
            roofed = b is not None and BLD[b]["arch"] in ("fl_bunker", "fl_hangar")
            south_row = roofed and y == BLD[b]["rect"][1] + BLD[b]["rect"][3] - 1
            X0, X1 = x, x + 1
            YN, YS = Y(y), Y(y + 1)
            for side, dx, dy in SIDES:
                nx, ny = x + dx, y + dy
                nt_ = tile(nx, ny)
                if nt_ == 3:
                    nh = wall_h(nx, ny) if (nx, ny) not in round_cells else 1.0
                    if nh >= h - 1e-3:
                        continue
                    z0 = nh
                    mat = "concrete"
                elif nt_ == 0:
                    z0 = -0.3
                    mat = "concrete_dark"
                else:
                    z0 = 0.0
                    nrole = role_of(CELL_ROOM.get((nx, ny), -1))
                    inside = nrole not in ("snow", "heliport", "dock")
                    mat = "concrete_in" if inside and b is not None else ("concrete" if inside else "concrete_dark")
                    if h <= H_PARAPET + 1e-3:
                        mat = "concrete"
                if south_row and h > H_CUT:
                    if z0 < H_CUT:
                        face(target(x, y), x, y, side, z0, H_CUT, mat)
                    face(target(x, y, True), x, y, side, max(z0, H_CUT), h, mat)
                else:
                    face(target(x, y), x, y, side, z0, h, mat)
            if roofed and south_row and tile(x, y + 1) in (1, 2) and rngw.random() < 0.3 and (x, y + 1) not in DOOR_CELLS and (x, y) not in DOOR_CELLS:
                wn = trims.setdefault("_winlights", MB())
                wn.box(X0 + 0.25, YS - 0.03, 0.4, X1 - 0.25, YS, 0.62, "window_cold" if rngw.random() < 0.7 else "screen_cyan")
            # chapeau : béton enneigé (snow) sur les murs bas, plaque sur les bunkers
            cap = "snow" if h <= H_PARAPET + 1e-3 else "concrete_top"
            if south_row:
                target(x, y, True).poly([(X0, YS, h), (X1, YS, h), (X1, YN, h), (X0, YN, h)], cap, [(X0, YS), (X1, YS), (X1, YN), (X0, YN)])
                target(x, y).poly([(X0, YS, H_CUT), (X1, YS, H_CUT), (X1, YN, H_CUT), (X0, YN, H_CUT)], "concrete_dark",
                                  [(X0, YS), (X1, YS), (X1, YN), (X0, YN)])
            else:
                target(x, y).poly([(X0, YS, h), (X1, YS, h), (X1, YN, h), (X0, YN, h)], cap, [(X0, YS), (X1, YS), (X1, YN), (X0, YN)])
            # lampes d'alerte rouges / plaques d'acier sur les murs extérieurs hauts
            if h >= H_OPEN and not roofed and rngw.random() < 0.14 and tile(x, y + 1) in (1, 2):
                lp = trims.setdefault("_lamps", MB())
                lp.box(X0 + 0.38, YS - 0.06, h + 0.05, X1 - 0.38, YS + 0.0, h + 0.25, "metal_dark")
                lp.sphere(x + 0.5, YS - 0.06, h + 0.3, 0.11, "neon_red", 1)
                ALARM_POS.append((x + 0.5, YS - 0.1, h + 0.3))
    # liserés lumineux et équipements muraux dans les salles intérieures
    for y in range(H):
        for x in range(W):
            if tile(x, y) != 2 or (x, y) in DOOR_CELLS:
                continue
            rid = CELL_ROOM.get((x, y), -1)
            role = role_of(rid)
            if role in ("yard", "walkway", "gate", "ramp", "crystal_lab"):
                continue
            col, k = light_of(rid)
            for side, dx, dy in SIDES:
                wx, wy = x + dx, y + dy
                if tile(wx, wy) != 3 or (wx, wy) in round_cells or (wx, wy) in DOOR_CELLS:
                    continue
                h = wall_h(wx, wy)
                tb = trims.setdefault("_lights", MB())
                wb = CELL_BLD.get((wx, wy))
                roofed = wb is not None and BLD[wb]["arch"] in ("fl_bunker", "fl_hangar")
                zt = H_CUT - 0.2 if roofed else min(h, H_OPEN) - 0.16
                if side == "N":
                    tb.box(x + 0.1, Y(y) - 0.02, zt, x + 0.9, Y(y) + 0.0, zt + 0.05, "lamp_" + col)
                    zmax = H_CUT - 0.25 if roofed else min(h, H_OPEN) - 0.22
                    r_ = RNG.random()
                    if (x, y) in GAME_CELLS:
                        pass
                    elif r_ < 0.1:
                        scr = RNG.choice(["screen_cyan", "screen_green", "screen_orange"])
                        tb.box(x + 0.14, Y(y) - 0.05, 0.3, x + 0.86, Y(y) + 0.0, min(0.78, zmax), "metal_dark")
                        tb.box(x + 0.18, Y(y) - 0.06, 0.34, x + 0.82, Y(y) - 0.05, min(0.74, zmax - 0.04), scr)
                    elif r_ < 0.2:
                        tb.box(x + 0.12, Y(y) - 0.07, 0.15, x + 0.88, Y(y) + 0.0, min(0.7, zmax), "steel_dark")
                        for j in range(4):
                            zz = 0.22 + j * 0.11
                            if zz + 0.04 < min(0.7, zmax):
                                tb.box(x + 0.2, Y(y) - 0.075, zz, x + 0.8, Y(y) - 0.07, zz + 0.04, "metal_dark")
                    elif r_ < 0.28:
                        for px_ in (0.3, 0.6):
                            tb.cyl(x + px_, Y(y) - 0.08, 0.0, zmax, 0.05, RNG.choice(["metal", "cable_yellow", "rust"]), 8)
                    elif r_ < 0.5 and col == "warm":
                        tb.box(x + 0.2, Y(y) - 0.03, 0.45, x + 0.8, Y(y) + 0.0, 0.8, "window")
                        tb.box(x + 0.18, Y(y) - 0.035, 0.43, x + 0.82, Y(y) - 0.03, 0.47, "steel_dark")
                    elif r_ < 0.6:
                        tb.box(x + 0.3, Y(y) - 0.03, zmax - 0.3, x + 0.7, Y(y) + 0.0, zmax - 0.1, "paint_red")
                        tb.box(x + 0.35, Y(y) - 0.035, zmax - 0.26, x + 0.65, Y(y) - 0.03, zmax - 0.14, "paint_white")
    # portes : linteau, montants, seuil, voyant
    for (dx_, dy_), d in DOOR_CELLS.items():
        bid = CELL_BLD.get((dx_, dy_))
        hh = max(wall_h(dx_ - 1, dy_) if d["vertical"] is False else wall_h(dx_, dy_ - 1), H_OPEN)
        roofed = bid is not None and BLD[bid]["arch"] in ("fl_bunker", "fl_hangar")
        if roofed:
            hh = H_ROOF
        south = roofed and dy_ == BLD[bid]["rect"][1] + BLD[bid]["rect"][3] - 1
        tg = mbs.setdefault(("front_%d" % bid) if south else (("walls_%d" % bid) if bid is not None else "basewalls"), MB())
        X0, X1, YN, YS = dx_, dx_ + 1, Y(dy_), Y(dy_ + 1)
        locked = d.get("state", 1) == 2
        if not d["vertical"]:
            tg.box(X0, YS, H_DOOR, X1, YN, hh, "concrete")
            for ex in (X0, X1 - 0.12):
                tg.box(ex, YS - 0.03, 0.0, ex + 0.12, YN + 0.03, H_DOOR + 0.05, "steel_dark" if not locked else "hazard_red")
            tg.box(X0, YS - 0.03, H_DOOR, X1, YN + 0.03, H_DOOR + 0.1, "steel_plate")
        else:
            tg.box(X0, YS, H_DOOR, X1, YN, hh, "concrete")
            for ey in (YS, YN - 0.12):
                tg.box(X0 - 0.03, ey, 0.0, X1 + 0.03, ey + 0.12, H_DOOR + 0.05, "steel_dark" if not locked else "hazard_red")
            tg.box(X0 - 0.03, YS, H_DOOR, X1 + 0.03, YN, H_DOOR + 0.1, "steel_plate")
        mbs.setdefault("ground_door", MB()).box(X0 + 0.05, YS + 0.05, 0.0, X1 - 0.05, YN - 0.05, 0.015, "doorway")
        rng_d = random.Random(dx_ * 97 + dy_ * 13 + SEED)
        dcol = "red" if locked or rng_d.random() < 0.3 else rng_d.choice(["cyan", "amber", "white"])
        gl = mbs.setdefault("_doorlights", MB())
        if not d["vertical"]:
            gl.box(X0 + 0.3, YS - 0.04, hh - 0.2, X1 - 0.3, YS, hh - 0.1, "neon_" + dcol)
        else:
            gl.box(X0 - 0.04, YS + 0.3, hh - 0.2, X0, YN - 0.3, hh - 0.1, "neon_" + dcol)
        DOOR_GLOWS.append((dx_ + 0.5, Y(dy_) - 0.5, dcol))
    for k, mb in mbs.items():
        mb.to_object(k, "world")
    for k, mb in trims.items():
        mb.to_object(k, "world")


# ======================================================================= toits des bunkers, tourelles, dômes
def roof_bunker(mb, b, rng):
    """Toit plat de bunker : dalle de béton enneigée, acrotère, grilles d'aération, antennes,
    radar, caissons, cheminée, lampe rouge, plaques d'acier."""
    x, y, w, h = b["rect"]
    z = H_ROOF
    X0, X1, YN, YS = x - 0.04, x + w + 0.04, Y(y) + 0.04, Y(y + h) - 0.04
    mb.box(X0, YS, z, X1, YN, z + 0.1, "concrete_top")
    mb.box(X0 + 0.3, YS + 0.3, z + 0.1, X1 - 0.3, YN - 0.3, z + 0.13, "roof_plate")
    mb.box(X0 + 0.5, YS + 0.5, z + 0.13, X0 + (X1 - X0) * rng.uniform(0.3, 0.5), YN - 0.5, z + 0.15, "snow")
    for (a0, a1, b0, b1) in ((X0, X1, YS, YS + 0.18), (X0, X1, YN - 0.18, YN), (X0, X0 + 0.18, YS, YN), (X1 - 0.18, X1, YS, YN)):
        mb.box(a0, b0, z + 0.1, a1, b1, z + 0.3, "concrete")
        mb.box(a0, b0, z + 0.3, a1, b1, z + 0.34, "snow")
    zt = z + 0.13
    horiz = w >= h
    arch = b["arch"]
    for k in range(1, int(w)):
        mb.box(X0 + k - 0.02, YS + 0.3, zt, X0 + k + 0.02, YN - 0.3, zt + 0.015, "metal_dark")
    for k in range(1, int(h)):
        mb.box(X0 + 0.3, YN - k - 0.02, zt, X1 - 0.3, YN - k + 0.02, zt + 0.015, "metal_dark")
    for k in range(rng.randint(2, 4)):
        sx, sy = rng.uniform(0.8, 1.8), rng.uniform(0.6, 1.4)
        px, py = x + rng.uniform(0.6, w - 0.6), y + rng.uniform(0.6, h - 0.6)
        mb.sphere(px, Y(py), zt - 0.1, 1.0, "snow", 1, sx, sy, 0.18)
    # grilles d'aération (2-4)
    for k in range(rng.randint(2, 4)):
        vx = x + rng.uniform(0.9, w - 0.9)
        vy = y + rng.uniform(0.9, h - 0.9)
        if rng.random() < 0.5:
            mb.box(vx - 0.4, Y(vy) - 0.28, zt, vx + 0.4, Y(vy) + 0.28, zt + 0.16, "metal_mid")
            for j in range(5):
                mb.box(vx - 0.34, Y(vy) - 0.22 + j * 0.11, zt + 0.16, vx + 0.34, Y(vy) - 0.18 + j * 0.11, zt + 0.18, "metal_dark")
        else:
            mb.cyl(vx, Y(vy), zt, zt + 0.35, 0.22, "metal_mid", 12)
            mb.cyl(vx, Y(vy), zt + 0.35, zt + 0.45, 0.3, "metal_dark", 12)
    # radiateurs / plaques (hangar : grande trappe)
    mb.box(x + 0.4, Y(y + 1.3), zt, x + w - 0.4, Y(y + 0.35), zt + 0.06, "snow")
    if arch == "fl_hangar":
        # toit de hangar : voûte basse en tôle nervurée enneigée
        for k in range(int(w) - 1):
            u0 = x + 0.5 + k
            mb.box(u0, Y(y + h - 0.5), zt, u0 + 0.5, Y(y + 0.5), zt + 0.3 + 0.25 * math.sin(math.pi * (k + 0.5) / (w - 1)), "roof_plate")
            mb.box(u0 + 0.5, Y(y + h - 0.5), zt, u0 + 1.0, Y(y + 0.5), zt + 0.3 + 0.25 * math.sin(math.pi * (k + 1.0) / (w - 1)), "steel_dark")
        for k in range(int(w) - 1):
            if rng.random() < 0.5:
                mb.box(x + 0.55 + k, Y(y + h - 0.6), zt + 0.3 + 0.25 * math.sin(math.pi * (k + 0.5) / (w - 1)), x + 0.95 + k, Y(y + 0.6), zt + 0.34 + 0.25 * math.sin(math.pi * (k + 0.5) / (w - 1)), "snow")
        mb.box(x + 0.8, Y(y + h - 0.8), zt, x + w - 0.8, Y(y + 0.8), zt + 0.04, "roof_plate")
        mb.box(x + 1.5, Y(y + h - 1.6), zt + 0.04, x + w - 1.5, Y(y + 1.6), zt + 0.08, "steel_dark")
        mb.box(x + 1.5, Y(y + h / 2 + 0.05), zt + 0.08, x + w - 1.5, Y(y + h / 2 - 0.05), zt + 0.1, "hazard")
        mb.box(x + w / 2 - 0.05, Y(y + h - 1.6), zt + 0.08, x + w / 2 + 0.05, Y(y + 1.6), zt + 0.1, "hazard")
        for k in range(1, int(w - 1.6)):
            mb.box(x + 0.8 + k, Y(y + h - 0.8), zt + 0.04, x + 0.82 + k, Y(y + 0.8), zt + 0.06, "metal_dark")
        mb.box(x + 0.8, Y(y + h - 0.9), zt, x + w - 0.8, Y(y + h - 1.1), zt + 0.02, "hazard")
    else:
        f = rng.uniform(0.3, 0.5)
        if horiz:
            rx0, rx1 = x + 0.6, x + 0.6 + (w - 1.2) * f
            nb = int((h - 1.4) / 0.26)
            for k in range(nb):
                yy = y + 0.7 + k * 0.26
                mb.box(rx0, Y(yy + 0.13), zt, rx1, Y(yy), zt + 0.14, "radiator")
        else:
            ry0, ry1 = y + 0.6, y + 0.6 + (h - 1.2) * f
            nb = int((w - 1.4) / 0.26)
            for k in range(nb):
                xx = x + 0.7 + k * 0.26
                mb.box(xx, Y(ry1), zt, xx + 0.13, Y(ry0), zt + 0.14, "radiator")
    # antenne / radar / cheminée
    r_ = rng.random()
    ax = x + rng.uniform(0.9, w - 0.9)
    ay = y + rng.uniform(0.7, h * 0.5)
    if r_ < 0.4:
        mb.cyl(ax, Y(ay), zt, zt + rng.uniform(1.4, 2.2), 0.05, "metal", 6)
        for zz in (0.5, 0.9, 1.3):
            mb.box(ax - 0.35, Y(ay) - 0.03, zt + zz, ax + 0.35, Y(ay) + 0.03, zt + zz + 0.04, "metal")
        mb.sphere(ax, Y(ay), zt + 2.25, 0.09, "neon_red", 1)
    elif r_ < 0.7:
        mb.cyl(ax, Y(ay), zt, zt + 0.6, 0.12, "metal_mid", 8)
        st = len(mb.V)
        mb.sphere(0, 0, 0, 0.75, "white_panel", 3, 1.0, 1.0, 0.3)
        for i in range(st, len(mb.V)):
            x_, y_, z_ = mb.V[i]
            if z_ > 0:
                z_ *= 0.1
            v = Matrix.Rotation(math.radians(40), 3, "X") @ Vector((x_, y_, z_))
            mb.V[i] = (v.x + ax, v.y + Y(ay), v.z + zt + 0.9)
    else:
        mb.cyl(ax, Y(ay), zt, zt + 0.7, 0.16, "rust", 10)
        mb.cyl(ax, Y(ay), zt + 0.7, zt + 0.78, 0.22, "metal_dark", 10)
    # caissons et fûts
    for k in range(rng.randint(1, 3)):
        bx = x + rng.uniform(0.8, w - 0.8)
        by = y + rng.uniform(h * 0.5, h - 0.7)
        if rng.random() < 0.6:
            mb.box(bx - 0.35, Y(by) - 0.25, zt, bx + 0.35, Y(by) + 0.25, zt + 0.4, rng.choice(["crate_grey", "olive", "steel_plate"]))
        else:
            mb.cyl(bx, Y(by), zt, zt + 0.5, 0.2, rng.choice(["drum_red", "drum_grey"]), 12)
    # tuyauterie le long du bord ouest et congères contre les équipements
    mb.seg((x + 0.4, Y(y + 0.6), zt + 0.12), (x + 0.4, Y(y + h - 0.6), zt + 0.12), 0.08, rng.choice(["metal", "rust", "cable_yellow"]), 6)
    mb.seg((x + 0.55, Y(y + 0.6), zt + 0.12), (x + 0.55, Y(y + h - 0.6), zt + 0.12), 0.05, "metal_mid", 6)
    for k in range(rng.randint(2, 4)):
        sx_, sy_ = x + rng.uniform(0.8, w - 0.8), y + rng.uniform(0.8, h - 0.8)
        mb.sphere(sx_, Y(sy_), zt - 0.05, rng.uniform(0.5, 1.1), "snow", 1, rng.uniform(1.2, 2.0), rng.uniform(0.8, 1.2), 0.12)
    # projecteur sur mât (angle nord-ouest du toit) orienté vers la cour
    if rng.random() < 0.8:
        px_, py_ = x + 0.7, y + 0.7
        FLOOD_POS.append((px_, Y(py_) + 0.3, zt + 1.2, rng.choice([-1.0, 1.0])))
        mb.cyl(px_, Y(py_), zt, zt + 1.1, 0.05, "metal", 6)
        mb.box(px_ - 0.18, Y(py_) - 0.12, zt + 1.05, px_ + 0.18, Y(py_) + 0.12, zt + 1.3, "metal_dark")
        mb.box(px_ - 0.15, Y(py_) - 0.16, zt + 1.08, px_ + 0.15, Y(py_) - 0.12, zt + 1.27, "neon_white")
    # lampe rouge d'alerte au coin + bande de danger
    mb.cyl(x + w - 0.45, Y(y + 0.45), zt, zt + 0.45, 0.04, "metal", 6)
    mb.sphere(x + w - 0.45, Y(y + 0.45), zt + 0.5, 0.1, "neon_red", 1)
    ALARM_POS.append((x + w - 0.45, Y(y + 0.45), zt + 0.5))
    if rng.random() < 0.5:
        mb.box(x + 0.4, Y(y + h - 0.4), zt, x + w - 0.4, Y(y + h - 0.6), zt + 0.02, "hazard")


def openings_mask(cx, cy, r, ang, spread=0.06):
    for da in (-spread, 0.0, spread):
        for dr in (0.3, 0.6, 0.9):
            px = cx + math.cos(ang + da) * (r + dr)
            py = cy - math.sin(ang + da) * (r + dr)
            if walk(int(math.floor(px)), int(math.floor(py))):
                return True
    return False


def ring_wall_seg(mb_low, mb_high, cx, cy, r0, r1, a0, a1, z_cut, z_top, mat, z_from=0.0, mat_in="concrete_in"):
    south = math.sin((a0 + a1) / 2) < 0
    P = [(cx + math.cos(a) * r0, cy + math.sin(a) * r0, cx + math.cos(a) * r1, cy + math.sin(a) * r1) for a in (a0, a1)]

    def quad(mb, z0, z1, cap=True):
        (ax0, ay0, ax1, ay1), (bx0, by0, bx1, by1) = P
        mb.poly([(ax1, ay1, z0), (bx1, by1, z0), (bx1, by1, z1), (ax1, ay1, z1)], mat,
                [(a0 * r1, z0), (a1 * r1, z0), (a1 * r1, z1), (a0 * r1, z1)])
        mb.poly([(bx0, by0, z0), (ax0, ay0, z0), (ax0, ay0, z1), (bx0, by0, z1)], mat_in,
                [(a1 * r0, z0), (a0 * r0, z0), (a0 * r0, z1), (a1 * r0, z1)])
        if cap:
            mb.poly([(ax0, ay0, z1), (ax1, ay1, z1), (bx1, by1, z1), (bx0, by0, z1)], "snow",
                    [(a0 * r0, 0), (a0 * r1, 0), (a1 * r1, 1), (a1 * r0, 1)])
    if south and z_top > z_cut and z_from < z_cut:
        quad(mb_low, z_from, z_cut)
        quad(mb_high, z_cut, z_top)
    elif south and z_from >= z_cut:
        quad(mb_high, z_from, z_top)
    else:
        quad(mb_low, z_from, z_top)


def build_tower(b, roof, rng):
    """Poste de garde hexagonal : socle de béton, parapet crénelé, toit en plaques avec lampe
    rouge, meurtrières, sacs de sable."""
    bid = b["id"]
    rcx, rcy, r = ROUND[bid]
    cx, cy = rcx, -rcy
    walls = MB()
    front = MB()
    seg = 6
    rot = math.pi / 6
    z1 = 1.3
    for i in range(seg):
        a0 = i / seg * math.tau + rot
        a1 = (i + 1) / seg * math.tau + rot
        if openings_mask(rcx, rcy, r, (a0 + a1) / 2, 0.12):
            # porte : linteau
            ring_wall_seg(front, front, cx, cy, r + 0.05, r + 0.8, a0, a1, H_DOOR + 0.05, z1, "concrete", z_from=H_DOOR + 0.05)
            continue
        ring_wall_seg(walls, front, cx, cy, r + 0.05, r + 0.8, a0, a1, H_CUT, z1, "concrete")
        # meurtrière
        am = (a0 + a1) / 2
        tgt = front if math.sin(am) < 0 else walls
        tgt.box(cx + math.cos(am) * (r + 0.42) - 0.12, cy + math.sin(am) * (r + 0.42) - 0.12, 0.75,
                cx + math.cos(am) * (r + 0.42) + 0.12, cy + math.sin(am) * (r + 0.42) + 0.12, 0.95, "doorway")
    x, y, w, h = b["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if tile(xx, yy) != 3:
                continue
            if math.hypot(xx + 0.5 - rcx, yy + 0.5 - rcy) < r + 0.7:
                continue
            walls.box(xx, Y(yy + 1), 0.0, xx + 1, Y(yy), 0.3, "concrete")
            walls.box(xx, Y(yy + 1), 0.3, xx + 1, Y(yy), 0.33, "snow")
    walls.to_object("walls_%d" % bid, "world")
    front.to_object("front_%d" % bid, "roofs")
    # toit hexagonal en plaques, parapet, lampe, antenne, sacs de sable
    R = r + 0.9
    pts = [(cx + math.cos(i / seg * math.tau + rot) * R, cy + math.sin(i / seg * math.tau + rot) * R) for i in range(seg)]
    roof.poly([(px, py, z1) for (px, py) in pts], "roof_plate")
    roof.poly([(px, py, z1 + 0.06) for (px, py) in [(cx + (px - cx) * 0.85, cy + (py - cy) * 0.85) for (px, py) in pts]], "snow")
    for i in range(seg):
        a_, b_ = pts[i], pts[(i + 1) % seg]
        roof.poly([(a_[0], a_[1], z1), (b_[0], b_[1], z1), (b_[0], b_[1], z1 + 0.35), (a_[0], a_[1], z1 + 0.35)], "concrete")
        for k in range(3):
            f0 = k / 3 + 0.05
            f1 = k / 3 + 0.25
            roof.box(min(a_[0] + (b_[0] - a_[0]) * f0, a_[0] + (b_[0] - a_[0]) * f1) - 0.05, min(a_[1] + (b_[1] - a_[1]) * f0, a_[1] + (b_[1] - a_[1]) * f1) - 0.05, z1 + 0.35,
                     max(a_[0] + (b_[0] - a_[0]) * f0, a_[0] + (b_[0] - a_[0]) * f1) + 0.05, max(a_[1] + (b_[1] - a_[1]) * f0, a_[1] + (b_[1] - a_[1]) * f1) + 0.05, z1 + 0.55, "concrete")
    roof.sphere(cx, cy, z1 - 0.05, R * 0.7, "snow", 2, 1.0, 1.0, 0.14, nscale=0.6, rng=rng)
    for i in range(seg):
        a_ = pts[i]
        roof.sphere(a_[0] * 0.92 + cx * 0.08, a_[1] * 0.92 + cy * 0.08, z1 + 0.6, 0.1, "neon_red" if i % 2 else "neon_cyan", 1)
        ALARM_POS.append((a_[0] * 0.92 + cx * 0.08, a_[1] * 0.92 + cy * 0.08, z1 + 0.65))
    roof.cyl(cx, cy, z1, z1 + 0.5, 0.2, "metal_mid", 8)
    roof.cyl(cx, cy, z1 + 0.5, z1 + 1.6, 0.04, "metal", 6)
    roof.sphere(cx, cy, z1 + 1.65, 0.12, "neon_red", 1)
    ALARM_POS.append((cx, cy, z1 + 1.65))
    for k in range(3):
        a = rng.uniform(0, math.tau)
        roof.sphere(cx + math.cos(a) * R * 0.5, cy + math.sin(a) * R * 0.5, z1 + 0.12, 0.25, "sandbag", 1, 1.4, 1.0, 0.5)


def build_dome(b, roof, rng):
    """Dôme d'observation : socle rond de béton, calotte blanche à bandes, lucarne, antennes."""
    bid = b["id"]
    rcx, rcy, r = ROUND[bid]
    cx, cy = rcx, -rcy
    walls = MB()
    front = MB()
    seg = 48
    z1 = 0.9
    for i in range(seg):
        a0 = i / seg * math.tau
        a1 = (i + 1) / seg * math.tau
        if openings_mask(rcx, rcy, r, (a0 + a1) / 2):
            ring_wall_seg(front, front, cx, cy, r + 0.05, r + 0.7, a0, a1, H_DOOR + 0.05, z1, "concrete", z_from=H_DOOR + 0.05)
            continue
        ring_wall_seg(walls, front, cx, cy, r + 0.05, r + 0.7, a0, a1, 0.45, z1, "concrete")
    x, y, w, h = b["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if tile(xx, yy) != 3 or math.hypot(xx + 0.5 - rcx, yy + 0.5 - rcy) < r + 0.6:
                continue
            walls.box(xx, Y(yy + 1), 0.0, xx + 1, Y(yy), 0.3, "concrete")
            walls.box(xx, Y(yy + 1), 0.3, xx + 1, Y(yy), 0.33, "snow")
    walls.to_object("walls_%d" % bid, "world")
    front.to_object("front_%d" % bid, "roofs")
    R = r + 0.75
    hz = R * 0.95
    nseg, nring = 40, 10
    rows = []
    for j in range(nring + 1):
        t = j / nring * (math.pi / 2)
        rows.append((math.cos(t) * R, z1 + math.sin(t) * hz))
    for j in range(nring):
        (ra, za), (rb, zb) = rows[j], rows[j + 1]
        for i in range(nseg):
            a0 = i / nseg * math.tau
            a1 = (i + 1) / nseg * math.tau
            mat = "hull_white" if (i // 5) % 2 == 0 or j < 2 else "white_panel"
            roof.poly([(cx + math.cos(a0) * ra, cy + math.sin(a0) * ra, za), (cx + math.cos(a1) * ra, cy + math.sin(a1) * ra, za),
                       (cx + math.cos(a1) * rb, cy + math.sin(a1) * rb, zb), (cx + math.cos(a0) * rb, cy + math.sin(a0) * rb, zb)], mat)
    for i in range(8):
        a = i / 8 * math.tau + 0.2
        for j in range(nring):
            (ra, za), (rb, zb) = rows[j], rows[j + 1]
            roof.seg((cx + math.cos(a) * ra, cy + math.sin(a) * ra, za), (cx + math.cos(a) * rb, cy + math.sin(a) * rb, zb), 0.05, "metal_mid", 5)
    # lucarne (fente) côté sud et antenne
    roof.box(cx - 0.35, cy - R * 0.98, z1 + hz * 0.3, cx + 0.35, cy - R * 0.6, z1 + hz * 0.55, "window_cold")
    roof.cyl(cx, cy, z1 + hz, z1 + hz + 1.0, 0.04, "metal", 6)
    roof.sphere(cx, cy, z1 + hz + 1.05, 0.08, "neon_red", 1)
    roof.cyl(cx + R * 0.5, cy + R * 0.4, z1 + hz * 0.75, z1 + hz * 0.75 + 0.6, 0.05, "metal", 6)


def build_lab_ring():
    """Laboratoire central des cristaux (salle du boss, ouverte) : mur annulaire bas en béton sombre
    à ouvertures sur les 4 axes, bancs de consoles en anneau, grands cristaux bleus (4 autour + un
    cœur central posé par prop_spawns), colonnes et poutres d'une verrière brisée (sans toit :
    salle du boss toujours visible), anneau lumineux au sol."""
    if not LAB_ROUND:
        return
    rcx, rcy, r = LAB_ROUND["round"]
    cx, cy = rcx, -rcy
    mb = MB()
    seg = 96
    z1 = 1.6
    for i in range(seg):
        a0 = i / seg * math.tau
        a1 = (i + 1) / seg * math.tau
        if openings_mask(rcx, rcy, r, (a0 + a1) / 2):
            continue
        ring_wall_seg(mb, mb, cx, cy, r + 0.05, r + 0.75, a0, a1, 0.45, z1, "concrete_dark", mat_in="concrete_dark")
        if i % 6 == 2:
            am = (a0 + a1) / 2
            mb.box(cx + math.cos(am) * (r + 0.4) - 0.2, cy + math.sin(am) * (r + 0.4) - 0.2, 0.9, cx + math.cos(am) * (r + 0.4) + 0.2, cy + math.sin(am) * (r + 0.4) + 0.2, 1.3, "window_cold")
    x, y, w, h = LAB_ROUND["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if tile(xx, yy) != 3:
                continue
            d = math.hypot(xx + 0.5 - rcx, yy + 0.5 - rcy)
            if d < r + 0.6 or d > r + 1.6:
                continue
            mb.box(xx, Y(yy + 1), 0.0, xx + 1, Y(yy), 0.42, "concrete_dark")
            mb.box(xx, Y(yy + 1), 0.42, xx + 1, Y(yy), 0.45, "snow")
    # consoles en anneau (hors ouvertures)
    rng = random.Random(SEED * 23)
    for k in range(32):
        a = (k + 0.5) / 32 * math.tau
        if openings_mask(rcx, rcy, r, a, 0.14):
            continue
        px_, py_ = cx + math.cos(a) * (r - 0.55), cy + math.sin(a) * (r - 0.55)
        mb.box(px_ - 0.32, py_ - 0.32, 0.0, px_ + 0.32, py_ + 0.32, 0.55, "metal_dark")
        mb.box(px_ - 0.26, py_ - 0.26, 0.55, px_ + 0.26, py_ + 0.26, 0.57, rng.choice(["screen_cyan", "screen_cyan", "screen_green", "screen_red"]))
    # anneaux lumineux au sol
    for (rr0, rr1, mat) in ((r - 0.3, r - 0.18, "neon_cyan"), (r * 0.45, r * 0.45 + 0.06, "metal"), (r * 0.7, r * 0.7 + 0.06, "metal")):
        for i in range(seg):
            a0 = i / seg * math.tau
            a1 = (i + 1) / seg * math.tau
            mb.poly([(cx + math.cos(a0) * rr0, cy + math.sin(a0) * rr0, 0.012), (cx + math.cos(a1) * rr0, cy + math.sin(a1) * rr0, 0.012),
                     (cx + math.cos(a1) * rr1, cy + math.sin(a1) * rr1, 0.012), (cx + math.cos(a0) * rr1, cy + math.sin(a0) * rr1, 0.012)], mat)
    # cristaux périphériques : 4 grappes entre les ouvertures (diagonales)
    for k in range(4):
        a = (k + 0.5) / 4 * math.tau
        px_, py_ = cx + math.cos(a) * r * 0.62, cy + math.sin(a) * r * 0.62
        crystal_cluster(mb, px_, py_, rng, 1.9 + rng.uniform(0.0, 0.5), "crystal")
    for k in range(8):
        a = (k + 0.5) / 8 * math.tau + 0.2
        if openings_mask(rcx, rcy, r, a, 0.2):
            continue
        crystal_cluster(mb, cx + math.cos(a) * r * 0.85, cy + math.sin(a) * r * 0.85, rng, 0.8 + rng.uniform(0.0, 0.4), "crystal_dim")
    # colonnes de la verrière (brisée) : piliers + poutres radiales inclinées, verre manquant
    for k in range(8):
        a = (k + 0.5) / 8 * math.tau
        if openings_mask(rcx, rcy, r, a, 0.16):
            continue
        px_, py_ = cx + math.cos(a) * (r + 0.4), cy + math.sin(a) * (r + 0.4)
        mb.box(px_ - 0.14, py_ - 0.14, 0.0, px_ + 0.14, py_ + 0.14, 2.6, "steel_dark")
        mb.seg((px_, py_, 2.6), (cx + math.cos(a) * r * 0.25, cy + math.sin(a) * r * 0.25, 3.4), 0.07, "metal_mid", 6)
        if k % 2 == 0:
            mb.box(px_ - 0.2, py_ - 0.03, 2.3, px_ + 0.2, py_ + 0.03, 2.55, "lamp_cyan")
    mb.to_object("lab_ring", "world")


def crystal_cluster(mb, px, py, rng, k=1.0, mat="crystal"):
    """Grappe de cristaux : 3 à 5 prismes hexagonaux inclinés de hauteurs variées."""
    n = rng.randint(3, 5)
    for i in range(n):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.0, 0.45) * k
        hgt = rng.uniform(0.9, 2.4) * k if i > 0 else 2.6 * k
        rad = rng.uniform(0.14, 0.3) * k if i > 0 else 0.36 * k
        tilt = rng.uniform(0.0, 0.35) if i > 0 else 0.05
        ta = rng.uniform(0, math.tau)
        base = Vector((px + math.cos(a) * d, py + math.sin(a) * d, -0.1))
        dirv = Vector((math.cos(ta) * math.sin(tilt), math.sin(ta) * math.sin(tilt), math.cos(tilt)))
        tip = base + dirv * hgt
        mb.seg(tuple(base), tuple(base + dirv * hgt * 0.8), rad, mat, 6, r2=rad * 0.85)
        mb.seg(tuple(base + dirv * hgt * 0.8), tuple(tip), rad * 0.85, mat, 6, r2=0.02)


def build_roofs():
    for b in LAYOUT.get("buildings", []):
        bid = b["id"]
        arch = b["arch"]
        rng = random.Random(bid * 7919 + SEED)
        mb = MB()
        if arch in ("fl_bunker", "fl_hangar"):
            roof_bunker(mb, b, rng)
        elif arch == "fl_tower":
            build_tower(b, mb, rng)
        elif arch == "fl_dome":
            build_dome(b, mb, rng)
        mb.to_object("roof_%d" % bid, "roofs")


# ======================================================================= décors (prop_spawns)
def _rect_of_spawn(s):
    sx, sy = s.get("size", [1, 1])
    x0 = s["cell"][0] - (sx - 1) // 2
    return [x0, s["cell"][1] - sy + 1, sx, sy]


def _cells_of(rect):
    x, y, w, h = rect
    return [(xx, yy) for yy in range(y, y + h) for xx in range(x, x + w)]


class Local:
    def __init__(self, rect, back):
        x, y, w, h = rect
        self.x0, self.x1, self.y0, self.y1 = x, x + w, y, y + h
        self.back = back
        if back in ("N", "S"):
            self.A, self.D = w, h
        else:
            self.A, self.D = h, w

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

    def hcyl(self, mb, u0, u1, v, z, r, mat, seg=14):
        ax, ay = self.p(u0, v)
        bx, by = self.p(u1, v)
        mb.seg((ax, ay, z), (bx, by, z), r, mat, seg)

    def sph(self, mb, u, v, z, r, mat, sub=1, sx=1.0, sy=1.0, sz=1.0):
        x, y = self.p(u, v)
        mb.sphere(x, y, z, r, mat, sub, sx, sy, sz)


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


CRATES = ["olive", "crate_red", "crate_grey", "crate_red", "olive_dark", "crate_red"]


def crate(mb, L, u, v, s, z, rng, mat=None):
    mat = mat or rng.choice(CRATES)
    hgt = s * rng.uniform(0.65, 0.85)
    L.box(mb, u - s / 2, v, z, u + s / 2, v + s, z + hgt, mat)
    e = max(0.03, s * 0.08)
    for (a0, b0) in ((u - s / 2, v), (u + s / 2 - e, v), (u - s / 2, v + s - e), (u + s / 2 - e, v + s - e)):
        L.box(mb, a0 - 0.005, b0 - 0.005, z, a0 + e + 0.005, b0 + e + 0.005, z + hgt + 0.005, "metal_dark")
    L.box(mb, u - s / 2 - 0.01, v + s * 0.45, z, u + s / 2 + 0.01, v + s * 0.55, z + hgt + 0.012, "metal_mid")
    if rng.random() < 0.5:
        L.box(mb, u - s * 0.2, v + s + 0.001, z + hgt * 0.35, u + s * 0.2, v + s + 0.012, z + hgt * 0.65, rng.choice(["hazard", "white_panel", "paint_red"]))
    # neige sur le dessus
    L.box(mb, u - s / 2 + 0.05, v + 0.05, z + hgt + 0.012, u + s / 2 - 0.05, v + s - 0.05, z + hgt + 0.035, "snow")


def prop(mb, kind, L, rng):
    A, D = L.A, L.D
    a = A / 2 - 0.06
    d = D - 0.08
    k = kind
    if k == "fl_console":
        L.box(mb, -a, 0.05, 0.0, a, min(d, 0.62), 0.5, "metal_mid")
        L.box(mb, -a, 0.05, 0.5, a, min(d, 0.62), 0.56, "metal_dark")
        n = max(1, int(A / 0.7))
        for i in range(n):
            u = -a + (i + 0.5) * (2 * a / n)
            L.box(mb, u - 0.26, 0.05, 0.56, u + 0.26, 0.12, 0.96, "metal_dark")
            L.box(mb, u - 0.22, 0.12, 0.6, u + 0.22, 0.13, 0.92, rng.choice(["screen_cyan", "screen_cyan", "screen_green", "screen_red"]))
    elif k == "fl_radio_rack":
        L.box(mb, -a, 0.03, 0.0, a, d * 0.9, 1.1, "metal_dark")
        for j in range(6):
            z = 0.12 + j * 0.15
            L.box(mb, -a + 0.06, d * 0.9, z, a - 0.06, d * 0.9 + 0.01, z + 0.03, rng.choice(["neon_green", "neon_amber", "metal_mid"]))
        L.cyl(mb, 0.0, 0.2, 1.1, 1.9, 0.03, "metal", 6)
    elif k == "fl_bunk":
        L.box(mb, -a, 0.02, 0.0, a, d, 0.12, "metal_dark")
        L.box(mb, -a + 0.03, 0.05, 0.12, a - 0.03, d - 0.03, 0.26, "mattress")
        L.box(mb, -a + 0.06, 0.08, 0.26, -a + 0.3, d - 0.08, 0.32, "sheet")
        for (pu, pv) in ((-a, 0.02), (a - 0.06, 0.02), (-a, d - 0.06), (a - 0.06, d - 0.06)):
            L.box(mb, pu, pv, 0.0, pu + 0.06, pv + 0.06, 0.95, "metal")
        L.box(mb, -a, 0.02, 0.62, a, d, 0.7, "metal_dark")
        L.box(mb, -a + 0.03, 0.05, 0.7, a - 0.03, d - 0.03, 0.82, "mattress")
    elif k == "fl_med_bed":
        L.box(mb, -a, 0.05, 0.0, a, d, 0.35, "white_panel")
        L.box(mb, -a + 0.04, 0.08, 0.35, a - 0.04, d - 0.04, 0.45, "sheet")
        L.cyl(mb, a - 0.12, 0.12, 0.0, 0.95, 0.03, "metal", 6)
        L.box(mb, a - 0.3, 0.1, 0.8, a, 0.16, 1.0, "screen_green")
    elif k in ("fl_table", "fl_map_table"):
        L.box(mb, -a + 0.1, 0.2, 0.42, a - 0.1, d - 0.2, 0.48, "wood" if k == "fl_table" else "metal_mid")
        if k == "fl_map_table":
            L.box(mb, -a + 0.2, 0.3, 0.48, a - 0.2, d - 0.3, 0.49, "screen_cyan")
        for (pu, pv) in ((-a + 0.15, 0.25), (a - 0.2, 0.25), (-a + 0.15, d - 0.3), (a - 0.2, d - 0.3)):
            L.box(mb, pu, pv, 0.0, pu + 0.06, pv + 0.06, 0.42, "metal_dark")
        if k == "fl_table":
            L.box(mb, -a + 0.15, 0.02, 0.0, a - 0.15, 0.18, 0.26, "wood")
            L.box(mb, -a + 0.15, d - 0.18, 0.0, a - 0.15, d, 0.26, "wood")
    elif k == "fl_lab_bench":
        L.box(mb, -a, 0.03, 0.0, a, min(d, 0.6), 0.48, "white_panel")
        L.box(mb, -a, 0.03, 0.48, a, min(d, 0.6), 0.52, "metal_dark")
        for i in range(3):
            u = -a + 0.2 + i * (2 * a - 0.4) / 2
            L.cyl(mb, u, 0.3, 0.52, 0.7, 0.06, "fluid" if i % 2 == 0 else "glass_tank", 8)
        L.box(mb, -0.25, 0.04, 0.52, 0.25, 0.1, 0.85, "screen_cyan")
    elif k == "fl_cryo_tank":
        r = min(A, D) / 2 - 0.08
        L.cyl(mb, 0.0, D / 2, 0.0, 0.12, r, "metal_mid", 16)
        L.cyl(mb, 0.0, D / 2, 0.12, 0.95, r * 0.8, "fluid", 16)
        L.cyl(mb, 0.0, D / 2, 0.12, 0.95, r * 0.9, "glass_tank", 16)
        L.cyl(mb, 0.0, D / 2, 0.95, 1.05, r, "metal_mid", 16)
        L.box(mb, -0.08, D / 2 - r - 0.02, 0.4, 0.08, D / 2 - r, 0.6, "screen_cyan")
    elif k == "fl_crate_stack":
        n = max(1, int(round(A)))
        for i in range(n):
            u = -a + (i + 0.5) * (2 * a / n)
            s = min(2 * a / n, d) * rng.uniform(0.8, 0.95)
            crate(mb, L, u, 0.06, s, 0.0, rng)
            if rng.random() < 0.55:
                crate(mb, L, u + rng.uniform(-0.05, 0.05), 0.1, s * 0.85, s * 0.8, rng)
    elif k == "fl_barrels":
        n = max(2, int(A * 2))
        for i in range(n):
            u = -a + 0.2 + i * (2 * a - 0.4) / max(n - 1, 1)
            v = rng.uniform(0.2, max(0.25, d - 0.25))
            L.cyl(mb, u, v, 0.0, 0.62, 0.19, rng.choice(["drum_red", "drum_red", "drum_red", "drum_grey"]), 12)
            L.cyl(mb, u, v, 0.62, 0.64, 0.15, "metal_dark", 12)
            L.cyl(mb, u, v, 0.64, 0.68, 0.14, "snow", 12)
    elif k == "fl_sandbags":
        n = max(3, int(A * 3))
        for i in range(n):
            u = -a + 0.15 + i * (2 * a - 0.3) / max(n - 1, 1)
            for j in range(2):
                L.sph(mb, u + (0.08 if j else 0.0), 0.2 + j * 0.02, 0.1 + j * 0.2, 0.2, "sandbag", 1, 1.3, 1.0, 0.55)
    elif k == "fl_weapon_rack":
        L.box(mb, -a, 0.02, 0.0, a, 0.25, 1.05, "metal_dark")
        n = max(2, int(A / 0.35))
        for i in range(n):
            u = -a + (i + 0.5) * (2 * a / n)
            L.box(mb, u - 0.05, 0.25, 0.15, u + 0.05, 0.33, 0.95, "rubber")
        L.box(mb, -a, 0.24, 1.0, a, 0.27, 1.03, "neon_red")
    elif k == "fl_generator":
        L.box(mb, -a, 0.05, 0.0, a, d, 0.75, "olive")
        L.box(mb, -a + 0.1, 0.1, 0.75, a - 0.1, d - 0.1, 0.8, "metal_dark")
        L.cyl(mb, a - 0.25, d * 0.5, 0.8, 1.3, 0.08, "rust", 8)
        L.box(mb, -a + 0.1, 0.02, 0.2, -a + 0.6, 0.05, 0.6, "hazard")
        L.box(mb, -0.1, 0.02, 0.35, 0.1, 0.05, 0.5, "screen_orange")
    elif k == "fl_pipes":
        n = rng.randint(3, 5)
        for i in range(n):
            u = -a + (i + 0.5) * (2 * a / n)
            L.cyl(mb, u, 0.15 + (i % 2) * 0.15, 0.0, 1.1, rng.uniform(0.07, 0.12), rng.choice(["metal", "metal_mid", "rust"]), 10)
        L.box(mb, -a, 0.05, 0.6, a, 0.35, 0.7, "metal_dark")
    elif k == "fl_workbench":
        L.box(mb, -a, 0.03, 0.45, a, min(d, 0.65), 0.52, "wood")
        for pu in (-a + 0.05, a - 0.1):
            L.box(mb, pu, 0.05, 0.0, pu + 0.05, min(d, 0.6), 0.45, "metal_dark")
        L.box(mb, -a, 0.02, 0.52, a, 0.08, 1.0, "metal_dark")
        for i in range(4):
            u = rng.uniform(-a + 0.1, a - 0.2)
            L.box(mb, u, 0.15, 0.52, u + rng.uniform(0.08, 0.25), 0.15 + rng.uniform(0.05, 0.2), 0.52 + rng.uniform(0.03, 0.12), rng.choice(["cable_red", "metal", "crate_red"]))
    elif k == "fl_tool_cart":
        L.box(mb, -0.3, 0.1, 0.1, 0.3, 0.6, 0.6, "crate_red")
        for (u, v) in ((-0.25, 0.15), (0.25, 0.15), (-0.25, 0.55), (0.25, 0.55)):
            L.cyl(mb, u, v, 0.0, 0.1, 0.06, "rubber", 8)
        L.box(mb, -0.3, 0.1, 0.6, 0.3, 0.6, 0.63, "metal_dark")
    elif k == "fl_stove":
        L.cyl(mb, 0.0, 0.3, 0.0, 0.6, 0.22, "metal_dark", 12)
        L.cyl(mb, 0.0, 0.3, 0.6, 1.4, 0.06, "rust", 8)
        L.box(mb, -0.12, 0.1, 0.2, 0.12, 0.12, 0.35, "neon_orange")
    elif k == "fl_telescope":
        L.cyl(mb, 0.0, D / 2, 0.0, 0.9, 0.12, "metal_mid", 10)
        mb.seg((L.p(0.0, D / 2)[0], L.p(0.0, D / 2)[1], 0.9), (L.p(0.0, D / 2 - 0.5)[0], L.p(0.0, D / 2 - 0.5)[1], 1.5), 0.14, "white_panel", 12)
        L.box(mb, -0.3, D / 2 - 0.3, 0.0, 0.3, D / 2 + 0.3, 0.08, "metal_dark")
    elif k == "fl_antenna":
        L.box(mb, -0.3, D / 2 - 0.3, 0.0, 0.3, D / 2 + 0.3, 0.2, "concrete")
        L.cyl(mb, 0.0, D / 2, 0.2, 3.2, 0.06, "metal", 6)
        for zz in (1.2, 1.9, 2.6):
            L.box(mb, -0.5, D / 2 - 0.03, zz, 0.5, D / 2 + 0.03, zz + 0.04, "metal")
        L.sph(mb, 0.0, D / 2, 3.25, 0.1, "neon_red", 1)
    elif k == "fl_helicopter":
        helicopter(mb, L, rng)
    elif k == "fl_snowcat":
        snowcat(mb, L, rng)
    elif k == "fl_crystal_core":
        cx_, cy_ = L.p(0.0, D / 2)
        mb.cyl(cx_, cy_, 0.0, 0.25, min(A, D) / 2 - 0.1, "metal_dark", 24)
        mb.cyl(cx_, cy_, 0.25, 0.3, min(A, D) / 2 - 0.2, "neon_cyan", 24)
        crystal_cluster(mb, cx_, cy_, rng, 2.8, "crystal")
    else:
        crate(mb, L, 0.0, 0.08, min(A, D) * 0.8, 0.0, rng)


def helicopter(mb, L, rng):
    """Hélicoptère de transport (empreinte 5×3) : fuselage vert, verrière, rotor, patins."""
    a = L.A / 2 - 0.1
    d = L.D
    vc = d / 2
    L.box(mb, -a + 0.3, vc - 0.6, 0.35, a - 1.2, vc + 0.6, 1.3, "olive")
    L.box(mb, -a + 0.3, vc - 0.45, 1.3, a - 1.6, vc + 0.45, 1.5, "olive_dark")
    L.box(mb, a - 1.2, vc - 0.5, 0.45, a - 0.3, vc + 0.5, 1.15, "olive")
    L.box(mb, a - 0.9, vc - 0.42, 0.8, a - 0.35, vc + 0.42, 1.3, "window_cold")
    L.box(mb, -a - 0.2, vc - 0.15, 0.8, -a + 0.4, vc + 0.15, 1.05, "olive")
    L.box(mb, -a - 0.25, vc - 0.05, 0.9, -a - 0.1, vc + 0.05, 1.6, "olive_dark")
    L.box(mb, -a - 0.3, vc - 0.45, 1.5, -a - 0.1, vc + 0.45, 1.55, "metal_dark")
    L.cyl(mb, 0.0, vc, 1.5, 1.75, 0.12, "metal_dark", 10)
    for i in range(4):
        ang = i / 4 * math.tau + 0.4
        ux, uy = L.p(0.0, vc)
        mb.seg((ux, uy, 1.75), (ux + math.cos(ang) * 2.6, uy + math.sin(ang) * 2.6, 1.72), 0.05, "metal_dark", 4)
    for vv in (vc - 0.55, vc + 0.55):
        L.hcyl(mb, -a + 0.4, a - 0.5, vv, 0.12, 0.05, "metal_mid", 8)
        for uu in (-a + 0.8, a - 1.0):
            L.box(mb, uu - 0.03, vv - 0.03, 0.12, uu + 0.03, vv + 0.03, 0.4, "metal_mid")
    L.box(mb, -a + 0.5, vc - 0.62, 0.6, a - 1.5, vc - 0.6, 1.0, "doorway")
    L.box(mb, -a + 0.5, vc + 0.6, 0.6, a - 1.5, vc + 0.62, 1.0, "doorway")
    L.box(mb, -a + 0.35, vc - 0.5, 1.5, a - 1.3, vc + 0.5, 1.53, "snow")


def snowcat(mb, L, rng):
    """Autoneige rouge à chenilles (empreinte 3×2)."""
    a = L.A / 2 - 0.1
    d = L.D
    vc = d / 2
    for vv in (vc - 0.55, vc + 0.55):
        L.box(mb, -a, vv - 0.22, 0.0, a, vv + 0.22, 0.45, "rubber")
        L.box(mb, -a + 0.1, vv - 0.26, 0.1, a - 0.1, vv + 0.26, 0.35, "metal_dark")
    L.box(mb, -a + 0.2, vc - 0.5, 0.45, a - 0.2, vc + 0.5, 0.8, "crate_red")
    L.box(mb, -a + 0.3, vc - 0.45, 0.8, a - 1.0, vc + 0.45, 1.35, "crate_red")
    L.box(mb, -a + 0.35, vc - 0.4, 0.95, -a + 0.38, vc + 0.4, 1.3, "window_cold")
    L.box(mb, a - 1.0, vc - 0.4, 0.8, a - 0.25, vc + 0.4, 1.0, "olive")
    L.box(mb, -a + 0.1, vc - 0.5, 0.5, -a + 0.2, vc + 0.5, 0.75, "hazard")
    L.sph(mb, -a + 0.1, vc, 1.4, 0.08, "neon_amber", 1)
    L.box(mb, -a + 0.3, vc - 0.4, 1.35, a - 1.0, vc + 0.4, 1.38, "snow")


def build_props():
    groups = {}
    for p in LAYOUT.get("prop_spawns", []):
        rect = _rect_of_spawn(p)
        bid = CELL_BLD.get((rect[0], rect[1]))
        name = ("furn_%d" % bid) if bid is not None else "props"
        mb = groups.setdefault(name, MB())
        rng = random.Random(hash((p["cell"][0], p["cell"][1], p["kind"])) & 0xffffff)
        back = back_side(rect) if p["kind"] not in ("fl_helicopter", "fl_snowcat", "fl_crystal_core", "fl_table", "fl_map_table", "fl_antenna", "fl_telescope") else "N"
        Lc = Local(rect, back)
        st = len(mb.V)
        prop(mb, p["kind"], Lc, rng)
        cells_fit(mb, st, rect, margin=0.05)
    for name, mb in groups.items():
        mb.to_object(name, "world")


# ======================================================================= fouillis et détails au sol
CLUTTER = {
    "storage": ["crates", "crates", "drums", "shelf"], "bunker": ["crates", "drums", "sandbags"],
    "workshop": ["bench", "crates", "toolbox", "drums"], "barracks": ["locker", "locker", "crates", "stove"],
    "mess_hall": ["crates", "stove", "locker"], "lab": ["cabinet", "console", "tank"], "infirmary": ["cabinet", "console"],
    "radio": ["rack", "rack", "console"], "command": ["console", "locker", "crates"], "closet": ["crates", "locker"],
    "hangar": ["crates", "crates", "drums", "toolbox"], "garage": ["drums", "crates", "toolbox"],
    "generator": ["drums", "pipes", "toolbox"], "armory": ["locker", "crates"], "cryo_vault": ["tank", "cabinet"],
    "guard_tower": ["sandbags", "crates"], "observatory": ["console", "locker"],
    "yard": ["crates", "crates", "drums", "sandbags"], "walkway": ["crates", "drums"], "ramp": ["sandbags", "drums"],
    "gate": ["sandbags"], "heliport": ["drums", "crates"], "dock": ["crates", "drums"], "snow": ["crates", "drums", "sled"],
    "crystal_lab": [],
}
CLUTTER_P = {"walkway": 0.12, "yard": 0.18, "snow": 0.02, "heliport": 0.1, "dock": 0.25, "ramp": 0.35, "gate": 0.35}
CLUTTER_CELLS = []


def clutter_item(mb, kind, L, rng):
    a = L.A / 2 - 0.1
    if kind == "crates":
        s = rng.uniform(0.55, 0.78)
        crate(mb, L, rng.uniform(-0.05, 0.05), 0.06, s, 0.0, rng)
        if rng.random() < 0.5:
            crate(mb, L, rng.uniform(-0.06, 0.06), 0.1, s * 0.8, s * 0.8, rng)
    elif kind == "drums":
        for i in range(rng.randint(1, 2)):
            L.cyl(mb, rng.uniform(-0.2, 0.2), rng.uniform(0.25, 0.5), 0.0, 0.62, 0.19, rng.choice(["drum_red", "drum_red", "drum_grey"]), 12)
    elif kind == "locker":
        L.box(mb, -a, 0.03, 0.0, a, 0.42, 1.0, rng.choice(["metal_mid", "olive", "crate_grey"]))
        L.box(mb, -0.02, 0.42, 0.1, 0.02, 0.43, 0.95, "metal_dark")
    elif kind == "cabinet":
        L.box(mb, -a, 0.03, 0.0, a, 0.45, 0.72, rng.choice(["white_panel", "metal_mid"]))
        L.box(mb, -a, 0.03, 0.72, a, 0.45, 0.76, "metal_dark")
    elif kind == "console":
        prop(mb, "fl_console", L, rng)
    elif kind == "rack":
        prop(mb, "fl_radio_rack", L, rng)
    elif kind == "tank":
        prop(mb, "fl_cryo_tank", L, rng)
    elif kind == "bench":
        prop(mb, "fl_workbench", L, rng)
    elif kind == "stove":
        prop(mb, "fl_stove", L, rng)
    elif kind == "sandbags":
        prop(mb, "fl_sandbags", L, rng)
    elif kind == "pipes":
        prop(mb, "fl_pipes", L, rng)
    elif kind == "toolbox":
        L.box(mb, -0.3, 0.1, 0.0, 0.3, 0.45, 0.3, "crate_red")
        L.box(mb, -0.2, 0.2, 0.3, 0.2, 0.35, 0.36, "metal_dark")
    elif kind == "shelf":
        L.box(mb, -a, 0.02, 0.0, a, 0.45, 1.05, "metal_dark")
        for z in (0.3, 0.65, 0.98):
            L.box(mb, -a, 0.02, z, a, 0.45, z + 0.03, "metal_mid")
            for i in range(int(L.A * 2)):
                u = -a + 0.1 + i * 0.5
                if u < a - 0.2:
                    L.box(mb, u, 0.05, z + 0.03, u + 0.3, 0.4, z + 0.22, rng.choice(CRATES))
    elif kind == "table":
        L.box(mb, -a + 0.05, 0.15, 0.42, a - 0.05, 0.85, 0.47, "wood")
        for (pu, pv) in ((-a + 0.1, 0.2), (a - 0.15, 0.2), (-a + 0.1, 0.75), (a - 0.15, 0.75)):
            L.box(mb, pu, pv, 0.0, pu + 0.05, pv + 0.05, 0.42, "metal_dark")
        L.box(mb, -0.15, 0.35, 0.47, 0.15, 0.6, 0.55, rng.choice(["paint_white", "crate_red", "screen_cyan"]))
    elif kind == "sled":
        L.box(mb, -0.4, 0.1, 0.05, 0.4, 0.5, 0.1, "wood")
        L.box(mb, -0.3, 0.15, 0.1, 0.3, 0.45, 0.4, "canvas")


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
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (q[0] + d[0], q[1] + d[1])
            if n in fs and n not in seen:
                seen.add(n)
                st.append(n)
    return len(seen) == len(fs)


def build_clutter():
    protect = set(GAME_CELLS)
    blocked = set()
    for key in ("prop_spawns", "container_spawns", "hiding_spot_spawns"):
        for sp in LAYOUT.get(key, []):
            for q in _cells_of(_rect_of_spawn(sp)):
                blocked.add(q)
    for (x, y) in list(STAIRS) + list(EXTRACT):
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                protect.add((x + dx, y + dy))
    px, py = LAYOUT["player_spawn"]
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            protect.add((px + dx, py + dy))
    for e in LAYOUT.get("enemy_spawns", []):
        protect.add(tuple(e["cell"]))
    # héliport : la dalle et le H restent dégagés
    hx, hy, hw, hh = HELI
    for yy in range(hy + 1, hy + hh - 1):
        for xx in range(hx + 1, hx + hw - 1):
            protect.add((xx, yy))
    mb = MB()
    for y in range(H):
        for x in range(W):
            if tile(x, y) not in (1, 2) or (x, y) in protect:
                continue
            rid = CELL_ROOM.get((x, y), -1)
            role = role_of(rid)
            kinds = CLUTTER.get(role, [])
            if not kinds:
                continue
            walls = [sd for sd, dx, dy in SIDES if tile(x + dx, y + dy) == 3]
            if role == "snow":
                walls = walls or ["N"]
            island = False
            if not walls and role in ("barracks", "mess_hall", "lab", "infirmary", "command", "workshop", "storage", "bunker", "radio", "hangar", "garage"):
                # îlot au milieu de la salle (tables, cuves, caisses) : 1 case sur 6, anneau libre
                island = (x * 7 + y * 3 + SEED) % 6 == 0
                if island:
                    walls = ["N"]
            if not walls or len(walls) > 2:
                continue
            rng = random.Random(x * 9176 + y * 131 + SEED * 7)
            if rng.random() > CLUTTER_P.get(role, 0.85):
                continue
            if not _keeps_ring((x, y), blocked):
                continue
            blocked.add((x, y))
            back = "N" if "N" in walls else walls[0]
            Lc = Local([x, y, 1, 1], back)
            st = len(mb.V)
            ik = rng.choice(["crates", "drums", "table", "tank"] if island else kinds)
            clutter_item(mb, ik, Lc, rng)
            cells_fit(mb, st, [x, y, 1, 1], margin=0.06)
            CLUTTER_CELLS.append((x, y))
    # groupes de caisses / fûts au milieu de la cour (hors axes)
    for r in ROOMS:
        if role_of(r["id"]) != "yard":
            continue
        x, y, w, h = r["rect"]
        rng = random.Random(r["id"] * 977 + SEED)
        n = max(3, int(w * h / 40))
        tries = 0
        placed = 0
        while placed < n and tries < 300:
            tries += 1
            cx = rng.randint(x + 1, x + w - 3)
            cy = rng.randint(y + 1, y + h - 3)
            cells = [(cx, cy), (cx + 1, cy), (cx, cy + 1), (cx + 1, cy + 1)]
            if any(SPINE[0] - 1 <= c[0] <= SPINE[0] + SPINE[1] for c in cells):
                continue
            if any(tile(*c) != 2 or c in protect or CELL_ROOM.get(c) != r["id"] for c in cells):
                continue
            ring = [(cx + dx, cy + dy) for dx in range(-1, 3) for dy in range(-1, 3)]
            if any(tile(*c) != 2 or c in CLUTTER_CELLS or c in blocked for c in ring):
                continue
            for c in cells:
                blocked.add(c)
            k = rng.random()
            for (qx, qy) in cells:
                if rng.random() < 0.25:
                    continue
                Lc = Local([qx, qy, 1, 1], "N")
                st = len(mb.V)
                clutter_item(mb, "crates" if k < 0.6 else ("drums" if k < 0.85 else "sandbags"), Lc, rng)
                cells_fit(mb, st, [qx, qy, 1, 1], margin=0.06)
                CLUTTER_CELLS.append((qx, qy))
            placed += 1
    mb.to_object("clutter", "world")


def decal(mb, cx, cy, s, mat):
    mb.poly([(cx - s / 2, Y(cy + s / 2), 0.004), (cx + s / 2, Y(cy + s / 2), 0.004), (cx + s / 2, Y(cy - s / 2), 0.004),
             (cx - s / 2, Y(cy - s / 2), 0.004)], mat, [(0, 0), (1, 0), (1, 1), (0, 1)])


def build_floor_details():
    det = MB()
    for sp in LAYOUT.get("decor_spawns", []):
        x, y = sp["cell"]
        cx, cy = x + 0.5, y + 0.5
        decal(det, cx, cy, 0.5, "oil")
    for y in range(H):
        for x in range(W):
            if not walk(x, y) or (x, y) in GAME_CELLS:
                continue
            rng = random.Random(x * 7349 + y * 1663 + SEED * 3)
            rid = CELL_ROOM.get((x, y), -1)
            role = role_of(rid)
            t = tile(x, y)
            if t == 1:
                # plaques de glace et traces sur la neige
                if rng.random() < 0.05:
                    decal(det, x + rng.uniform(0.3, 0.7), y + rng.uniform(0.3, 0.7), rng.uniform(0.8, 1.6), "ice_patch")
                continue
            if role in ("yard", "walkway", "gate", "ramp"):
                if rng.random() < 0.04:
                    decal(det, x + rng.uniform(0.3, 0.7), y + rng.uniform(0.3, 0.7), rng.uniform(0.8, 1.4), "ice_patch")
                elif rng.random() < 0.03:
                    det.seg((x + 0.1, Y(y + rng.random()), 0.02), (x + 0.9, Y(y + rng.random()), 0.02), 0.025, rng.choice(["cable", "cable_red", "cable_yellow"]), 5)
            elif rng.random() < 0.035:
                if rng.random() < 0.5:
                    decal(det, x + 0.5, y + 0.5, rng.uniform(0.6, 1.2), "oil")
                else:
                    det.box(x + 0.15, Y(y + 0.7), 0.0, x + 0.85, Y(y + 0.3), 0.008, "metal_dark")
                    for j in range(4):
                        det.box(x + 0.2, Y(y + 0.36 + j * 0.09) - 0.02, 0.008, x + 0.8, Y(y + 0.36 + j * 0.09) + 0.02, 0.011, "rubber")
    det.to_object("_floordet", "world")


# ======================================================================= hors jeu : navire, épave, icebergs
def ship(mb, X, Yb, size, rot):
    """Brise-glace échoué, pris dans la banquise : coque rouge et noire gîtée, superstructure
    blanche, cheminée, mâts, grue ; banquise fracturée autour."""
    Lg = size
    Wd = size * 0.3
    c, s = math.cos(rot), math.sin(rot)
    roll = math.radians(9.0)

    def P(u, v, z):
        # gîte : le pont penche vers v positif
        zz = z + v * math.tan(roll)
        return (X + u * c - v * s, Yb + u * s + v * c, zz)
    base = SEA_Z + 0.9
    # coque : sections (polygones) étagées
    hull_pts = []
    n = 14
    for i in range(n + 1):
        t = i / n
        u = -Lg / 2 + t * Lg
        hw = Wd / 2 * (1.0 - (abs(t - 0.45) / 0.55) ** 2.4) + 0.05
        hull_pts.append((u, hw))
    for (z0, z1, mat, k0, k1) in ((base - 1.2, base + 0.8, "hull_ship", 0.85, 1.0), (base + 0.8, base + 1.8, "hull_white", 1.0, 1.02)):
        for i in range(n):
            (u0, w0), (u1, w1) = hull_pts[i], hull_pts[i + 1]
            for sg in (1, -1):
                mb.poly([P(u0, sg * w0 * k0, z0), P(u1, sg * w1 * k0, z0), P(u1, sg * w1 * k1, z1), P(u0, sg * w0 * k1, z1)][::sg], mat,
                        [(u0, z0), (u1, z0), (u1, z1), (u0, z1)])
    mb.poly([P(u, w * 1.02, base + 1.8) for (u, w) in hull_pts] + [P(u, -w * 1.02, base + 1.8) for (u, w) in hull_pts[::-1]], "steel_dark")
    mb.poly([P(u, w * 0.92, base + 1.85) for (u, w) in hull_pts[1:-1]] + [P(u, -w * 0.92, base + 1.85) for (u, w) in hull_pts[1:-1][::-1]], "snow")
    # bastingage
    for i in range(n):
        (u0, w0), (u1, w1) = hull_pts[i], hull_pts[i + 1]
        for sg in (1, -1):
            mb.seg(P(u0, sg * w0, base + 1.8), P(u1, sg * w1, base + 1.8), 0.03, "metal", 4)
    # superstructure (arrière, u > 0) et passerelle
    mb.box(0, 0, 0, 1, 1, 1, "hull_white")  # placeholder remplacé ci-dessous (évite liste vide)
    mb.V = mb.V[:-8]
    mb.F = mb.F[:-6]
    def boxP(u0, v0, z0, u1, v1, z1, mat):
        pts = [P(u0, v0, z0), P(u1, v0, z0), P(u1, v1, z0), P(u0, v1, z0), P(u0, v0, z1), P(u1, v0, z1), P(u1, v1, z1), P(u0, v1, z1)]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        mb._add(pts, faces, mat)
    boxP(Lg * 0.05, -Wd * 0.36, base + 1.85, Lg * 0.38, Wd * 0.36, base + 2.9, "hull_white")
    boxP(Lg * 0.12, -Wd * 0.3, base + 2.9, Lg * 0.3, Wd * 0.3, base + 3.7, "hull_white")
    boxP(Lg * 0.14, -Wd * 0.32, base + 3.2, Lg * 0.29, Wd * 0.32, base + 3.45, "window_cold")
    boxP(Lg * 0.29, -Wd * 0.14, base + 2.9, Lg * 0.37, Wd * 0.14, base + 4.6, "crate_red")
    boxP(Lg * 0.29, -Wd * 0.15, base + 4.3, Lg * 0.37, Wd * 0.15, base + 4.75, "metal_dark")
    for sg in (1, -1):
        boxP(Lg * 0.08, sg * Wd * 0.4, base + 1.9, Lg * 0.2, sg * Wd * 0.52, base + 2.3, "crate_red")
        boxP(Lg * 0.08, sg * Wd * 0.4, base + 2.3, Lg * 0.2, sg * Wd * 0.52, base + 2.36, "snow")
    mb.seg(P(Lg * 0.4, 0, base + 1.85), P(Lg * 0.4, 0, base + 3.6), 0.05, "metal", 6)
    mb.seg(P(Lg * 0.4, -0.5, base + 3.2), P(Lg * 0.4, 0.5, base + 3.2), 0.03, "metal", 4)
    boxP(Lg * 0.1, -Wd * 0.25, base + 3.7, Lg * 0.28, Wd * 0.25, base + 3.78, "snow")
    # mât avant, grue, antennes
    mb.seg(P(-Lg * 0.2, 0, base + 1.85), P(-Lg * 0.2, 0, base + 5.0), 0.06, "metal", 6)
    mb.seg(P(-Lg * 0.2, -0.6, base + 3.9), P(-Lg * 0.2, 0.6, base + 3.9), 0.03, "metal", 4)
    mb.seg(P(-Lg * 0.05, Wd * 0.2, base + 1.85), P(-Lg * 0.05, Wd * 0.2, base + 3.6), 0.08, "hull_ship", 6)
    mb.seg(P(-Lg * 0.05, Wd * 0.2, base + 3.6), P(-Lg * 0.22, -Wd * 0.4, base + 2.8), 0.05, "hull_ship", 5)
    mb.seg(P(Lg * 0.22, 0, base + 3.7), P(Lg * 0.22, 0, base + 5.4), 0.04, "metal", 6)
    mb.sphere(*P(Lg * 0.22, 0, base + 5.45), 0.1, "neon_red", 1)
    mb.sphere(*P(-Lg * 0.2, 0, base + 5.05), 0.08, "neon_red", 1)
    # ancre / chaîne, hublots
    for i in range(6):
        u = -Lg * 0.35 + i * Lg * 0.1
        for sg in (1, -1):
            mb.sphere(*P(u, sg * (Wd / 2 * (1.0 - (abs((u + Lg / 2) / Lg - 0.45) / 0.55) ** 2.4) + 0.06), base + 1.3), 0.07, "window", 1)
    # banquise fracturée autour de la coque (plaques épaisses surélevées, pressées contre la coque)
    rng = random.Random(SEED * 31)
    for k in range(26):
        a = rng.uniform(0, math.tau)
        dd = rng.uniform(Wd * 0.6, Lg * 0.55)
        u = math.cos(a) * dd * (Lg / Wd) * 0.35
        v = math.sin(a) * dd
        if abs(u) < Lg * 0.5 and abs(v) < Wd * 0.55:
            continue
        pts = []
        m_ = rng.randint(5, 7)
        rr = rng.uniform(1.0, 2.4)
        for i in range(m_):
            aa = i / m_ * math.tau
            pts.append((u + math.cos(aa) * rr * rng.uniform(0.6, 1.0), v + math.sin(aa) * rr * rng.uniform(0.6, 1.0)))
        z1 = SEA_Z + rng.uniform(0.3, 1.0)
        tl = rng.uniform(-0.15, 0.15)
        top = [(X + pu * c - pv * s, Yb + pu * s + pv * c, z1 + pv * tl) for (pu, pv) in pts]
        mb.poly(top, "snow")
        for i in range(m_):
            a_, b_ = top[i], top[(i + 1) % m_]
            mb.poly([(a_[0], a_[1], SEA_Z - 0.4), (b_[0], b_[1], SEA_Z - 0.4), (b_[0], b_[1], b_[2]), (a_[0], a_[1], a_[2])], "ice")


def wreck(mb, X, Yb, size, rot):
    """Épave de bateau de pêche à demi coulée, gîte forte, cabine et mât brisé."""
    c, s = math.cos(rot), math.sin(rot)
    roll = math.radians(28.0)

    def P(u, v, z):
        return (X + u * c - v * s, Yb + u * s + v * c, z + v * math.tan(roll) - 0.3)
    Lg, Wd = size, size * 0.34
    base = SEA_Z + 0.1
    n = 8
    pts = []
    for i in range(n + 1):
        t = i / n
        u = -Lg / 2 + t * Lg
        hw = Wd / 2 * (1.0 - (abs(t - 0.5) / 0.55) ** 2.2) + 0.03
        pts.append((u, hw))
    for i in range(n):
        (u0, w0), (u1, w1) = pts[i], pts[i + 1]
        for sg in (1, -1):
            mb.poly([P(u0, sg * w0, base - 0.5), P(u1, sg * w1, base - 0.5), P(u1, sg * w1 * 1.1, base + 0.7), P(u0, sg * w0 * 1.1, base + 0.7)][::sg], "rust",
                    [(u0, 0), (u1, 0), (u1, 1), (u0, 1)])
    mb.poly([P(u, w * 1.1, base + 0.7) for (u, w) in pts] + [P(u, -w * 1.1, base + 0.7) for (u, w) in pts[::-1]], "wood")
    def boxP(u0, v0, z0, u1, v1, z1, mat):
        p = [P(u0, v0, z0), P(u1, v0, z0), P(u1, v1, z0), P(u0, v1, z0), P(u0, v0, z1), P(u1, v0, z1), P(u1, v1, z1), P(u0, v1, z1)]
        mb._add(p, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], mat)
    boxP(Lg * 0.05, -Wd * 0.3, base + 0.7, Lg * 0.35, Wd * 0.3, base + 1.5, "hull_white")
    boxP(Lg * 0.08, -Wd * 0.32, base + 1.0, Lg * 0.32, Wd * 0.32, base + 1.3, "doorway")
    mb.seg(P(-Lg * 0.15, 0, base + 0.7), P(-Lg * 0.25, 0.4, base + 2.0), 0.05, "wood", 5)
    boxP(-Lg * 0.3, -Wd * 0.25, base + 0.7, -Lg * 0.1, Wd * 0.25, base + 0.75, "snow")


def iceberg(mb, X, Yb, size, rot, rng):
    """Iceberg : masse de glace irrégulière (sphère bruitée aplatie) + calotte de neige."""
    st = len(mb.V)
    mb.sphere(X, Yb, SEA_Z - size * 0.15, size * 0.55, "iceberg", 3, 1.4, 1.0, 0.9, jitter=0.2, nscale=1.6, rng=rng)
    M = Matrix.Rotation(math.radians(rot), 3, "Z")
    for i in range(st, len(mb.V)):
        v = M @ (Vector(mb.V[i]) - Vector((X, Yb, 0))) + Vector((X, Yb, 0))
        mb.V[i] = (v.x, v.y, v.z)
    mb.sphere(X, Yb, SEA_Z + size * 0.32, size * 0.4, "snow", 2, 1.3, 1.0, 0.35, jitter=0.15, rng=rng)


def build_decor():
    mb = MB()
    rng = random.Random(SEED * 41)
    for d in C.get("decor", []):
        k = d["kind"]
        px, py = d["pos"]
        sz = float(d.get("size", 4))
        rot = math.radians(float(d.get("rot", 0.0)))
        X, Yb = px, Y(py)
        if k == "ship":
            ship(mb, X, Yb, sz * 1.25, rot)
        elif k == "wreck":
            wreck(mb, X, Yb, sz, rot)
        elif k == "iceberg":
            iceberg(mb, X, Yb, sz, float(d.get("rot", 0.0)), rng)
    # plateau : petits piquets / balises le long de la passerelle d'accès sud (hors jeu : cases STREET
    # déjà prises par le fouillis ?) → rien de bloquant : lampes sur les murets uniquement.
    # blocs de glace pressés contre la falaise (bord du plateau irrégulier)
    rng2 = random.Random(SEED * 43)
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            if tile(x, y) != 3 or not is_cliff(x, y) or rng2.random() > 0.22:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if tile(x + dx, y + dy) == 0:
                    bx, by = x + 0.5 + dx * rng2.uniform(0.9, 1.8), Y(y) - 0.5 - dy * rng2.uniform(0.9, 1.8)
                    mb.sphere(bx, by, SEA_Z + rng2.uniform(0.3, 0.9), rng2.uniform(0.8, 1.6), "iceberg", 2, rng2.uniform(1.0, 1.8), rng2.uniform(0.8, 1.4), rng2.uniform(0.5, 0.9), jitter=0.25, nscale=1.5, rng=rng2)
                    break
    mb.to_object("_decor", "world")


# ======================================================================= lumières
LIGHT_E = float(os.environ.get("FL_LIGHT", "28"))


def build_lights():
    n = 0
    for r in ROOMS:
        rid = r["id"]
        x, y, w, h = r["rect"]
        role = role_of(rid)
        if role in ("snow", "heliport", "dock"):
            continue
        col, k = light_of(rid)
        bid = CELL_BLD.get((x + w // 2, y + h // 2))
        roofed = bid is not None and BLD[bid]["arch"] in ("fl_bunker", "fl_hangar")
        z = 1.35 if roofed else 1.1
        step = 7.0 if role in ("yard", "walkway") else 5.0
        nx = max(1, int(round(w / step)))
        ny = max(1, int(round(h / step)))
        lrng = random.Random(rid * 31 + SEED)
        for i in range(nx):
            for j in range(ny):
                px = x + (i + 0.5) * w / nx + lrng.uniform(-0.8, 0.8)
                py = y + (j + 0.5) * h / ny + lrng.uniform(-0.8, 0.8)
                if not walk(int(px), int(py)):
                    continue
                L_ = bpy.data.lights.new("l%d" % n, "AREA")
                c_ = NEON[col] if role not in ("yard", "walkway") else (0.8, 0.9, 1.0)
                L_.color = c_
                L_.energy = LIGHT_E * k * (0.5 if role in ("yard", "walkway") else 1.0) * lrng.uniform(0.7, 1.2)
                L_.shape = "DISK"
                L_.size = 2.5 if role in ("yard", "walkway") else 2.2
                o = bpy.data.objects.new("l%d" % n, L_)
                o.location = (px, Y(py), z)
                scene.collection.objects.link(o)
                n += 1
    for (gx, gy, gc) in DOOR_GLOWS:
        L_ = bpy.data.lights.new("d%d" % n, "POINT")
        L_.color = NEON[gc]
        L_.energy = LIGHT_E * 0.2
        L_.shadow_soft_size = 0.2
        o = bpy.data.objects.new("d%d" % n, L_)
        o.location = (gx, gy, 0.9)
        scene.collection.objects.link(o)
        n += 1
    for (lx, ly, lz) in LAMP_POS:
        L_ = bpy.data.lights.new("lp%d" % n, "POINT")
        L_.color = NEON["warm"]
        L_.energy = LIGHT_E * 4.0
        L_.shadow_soft_size = 0.5
        o = bpy.data.objects.new("lp%d" % n, L_)
        o.location = (lx, ly, lz)
        scene.collection.objects.link(o)
        n += 1
    for (fx, fy, fz, sd) in FLOOD_POS:
        L_ = bpy.data.lights.new("fl%d" % n, "SPOT")
        L_.color = (0.95, 0.97, 1.0)
        L_.energy = LIGHT_E * 40.0
        L_.spot_size = math.radians(70.0)
        L_.spot_blend = 0.6
        L_.shadow_soft_size = 0.5
        o = bpy.data.objects.new("fl%d" % n, L_)
        o.location = (fx, fy, fz)
        d_ = Vector((sd * 0.6, 0.5, -1.0)).normalized()
        o.rotation_euler = d_.to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(o)
        n += 1
    for (ax, ay, az) in ALARM_POS:
        L_ = bpy.data.lights.new("a%d" % n, "POINT")
        L_.color = NEON["red"]
        L_.energy = LIGHT_E * 0.35
        L_.shadow_soft_size = 0.3
        o = bpy.data.objects.new("a%d" % n, L_)
        o.location = (ax, ay, az)
        scene.collection.objects.link(o)
        n += 1
    # cristaux du laboratoire : grosse lumière bleue au centre + 4 périphériques
    if LAB_ROUND:
        rcx, rcy, r = LAB_ROUND["round"]
        for (k, (ox, oy)) in enumerate([(0, 0)] + [(math.cos((i + 0.5) / 4 * math.tau) * r * 0.62, math.sin((i + 0.5) / 4 * math.tau) * r * 0.62) for i in range(4)]):
            L_ = bpy.data.lights.new("cr%d" % n, "POINT")
            L_.color = (0.4, 0.75, 1.0)
            L_.energy = LIGHT_E * (4.0 if k == 0 else 1.5)
            L_.shadow_soft_size = 0.6
            o = bpy.data.objects.new("cr%d" % n, L_)
            o.location = (rcx + ox, -rcy + oy, 1.6)
            scene.collection.objects.link(o)
            n += 1
    print("  lights", n, flush=True)


def build_world():
    build_terrain()
    build_floors()
    build_walls()
    build_lab_ring()
    build_roofs()
    build_props()
    build_clutter()
    build_floor_details()
    build_decor()
    build_lights()


# ======================================================================= rendu
EXPOSURE = float(os.environ.get("FL_EXPOSURE", "0.15"))
SUN_E = float(os.environ.get("FL_SUN", "4.0"))
SKY = float(os.environ.get("FL_SKY", "0.55"))
SAT = float(os.environ.get("FL_SAT", "1.2"))
CON = float(os.environ.get("FL_CON", "1.25"))
LIFT = float(os.environ.get("FL_LIFT", "8"))


def setup_render():
    sc = scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 2
    sc.cycles.glossy_bounces = 1
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
    # ciel couvert blanc-bleu : lumière d'ambiance froide et douce
    bg.inputs[0].default_value = (0.4, 0.55, 0.85, 1)
    bg.inputs[1].default_value = SKY
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = SUN_E
    sun.color = (0.9, 0.95, 1.0)
    sun.angle = math.radians(2.5)
    so = bpy.data.objects.new("sun", sun)
    sc.collection.objects.link(so)
    # soleil bas au nord-ouest, voilé : ombres longues et douces vers le sud-est
    d = Vector((0.5, -0.6, -0.42)).normalized()
    so.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    # contre-jour bleu depuis le sud (réflexion de la glace)
    es = bpy.data.lights.new("icelight", "SUN")
    es.energy = float(os.environ.get("FL_ICELIGHT", "0.35"))
    es.color = (0.5, 0.7, 1.0)
    es.angle = math.radians(10.0)
    eo = bpy.data.objects.new("icelight", es)
    sc.collection.objects.link(eo)
    d2 = Vector((0.1, 0.8, -0.55)).normalized()
    eo.rotation_euler = d2.to_track_quat("-Z", "Y").to_euler()
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

# ======================================================================= cadrage, étalonnage, rendu par morceaux (repris de fw_scene.py)
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
    # FL_CHUNK_LIMIT : nombre maximal de morceaux rendus dans ce processus (rendu fragmenté : le
    # verrou Blender est rendu entre deux lots ; relancer jusqu'à ce que tous existent).
    limit = int(os.environ.get("FL_CHUNK_LIMIT", "0"))
    done_now = 0
    for y0 in range(0, ph, chunk):
        for x0 in range(0, pw, chunk):
            x1, y1 = min(x0 + chunk, pw), min(y0 + chunk, ph)
            cp = os.path.join(cdir, "c_%d_%d.png" % (x0, y0))
            if not os.path.exists(cp):
                if limit and done_now >= limit:
                    print("CHUNK_LIMIT reached", flush=True)
                    sys.exit(3)
                done_now += 1
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
# ======================================================================= masque d'emprise zénithal (repris de fw_scene.py)
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
# ======================================================================= occultation : ids par pixel (repris de fw_scene.py)
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
BLOOM = float(os.environ.get("FL_BLOOM", "0.55"))


def grade(path):
    """Étalonnage final (PIL) : saturation, contraste, clarté, relève des noirs + halo lumineux
    (« bloom ») autour des néons, écrans et hublots, comme les lueurs de la maquette."""
    from PIL import Image, ImageEnhance, ImageFilter, ImageChops
    im = Image.open(path).convert("RGB")
    if BLOOM > 0:
        hi = im.point(lambda v: max(0, v - 200) * 4)
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
MASK_SOLID = ("walls_", "front_", "basewalls", "props", "lab_ring", "cliff")
MASK_DECOR = ("furn_", "clutter")
MASK_SKIP = ("ground", "floor_", "roof_", "cut_", "_")


def mask_class(name):
    if name.startswith(MASK_SKIP):
        return None
    if name.startswith(MASK_SOLID):
        return (1.0, 0.0, 0.0)
    if name.startswith(MASK_DECOR):
        return (0.0, 1.0, 0.0)
    return (0.0, 0.0, 1.0)


OCC_SKIP = ("ground", "floor_", "cut_", "_")


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
            "projection": "ground_square", "margin": MARGIN, "biome": "frozen_lands",
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
        only = os.environ.get("FL_INT_ONLY", "")
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
            lim_ = int(os.environ.get("FL_CHUNK_LIMIT", "0"))
            if lim_ and int(info["renders"].get("_int_now", 0)) >= max(lim_ // 2, 2):
                print("CHUNK_LIMIT reached (int)", flush=True)
                sys.exit(3)
            info["renders"]["_int_now"] = int(info["renders"].get("_int_now", 0)) + 1
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
