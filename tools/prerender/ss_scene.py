"""Scène Blender complète du pont 0 de la Station Orbitale (station en croix façon maquette
docs/reference/cartes.png, colonne « Station spatiale »), construite depuis le layout JSON exporté
par tools/prerender/export_layout.gd (4e argument : res://data/worlds/world_02_space_station.tres),
rendue en Cycles. Même pipeline, mêmes passes et même projection que fw_scene.py (Far West).

Usage (bpy en module) :
  python3 ss_scene.py <layout.json> <out_dir> [ppc=24] [samples=16] [passes=full,int] [margin=4]
Passes : full (carte entière, par morceaux, reprise possible : _chunks_full/) ; int (patch « sans
         toit » par module fermé : toit, dôme, tube, haut du mur sud masqués) ; mask (emprise au
         sol réelle, vue zénithale, 4 px/case → mask.png) ; occ (ids d'occultation par pixel,
         même caméra que full → occ.png) ; crop:x0;x1;y0;y1 ; view:x0;x1;y0;y1;tilt;ppc
Sorties : full.png, b<id>_in.png, mask.png, occ.png, render.json, layout.json (pour compose.py).

PROJECTION (identique à fw_scene.py) : caméra orthographique inclinée de TILT (38°) vers le nord,
  pixel_aspect_x = 1/cos(TILT) ; un point (cx, cy, z) en cases tombe au pixel
      px = (cx + M) * ppc ;  py = (cy + M) * ppc - z * tan(TILT) * ppc
  → le SOL (z = 0) est exactement sur la grille. Le jeu pose l'image à l'échelle 64/ppc.
Repère Blender : 1 unité = 1 case. X = colonne, Y = -rangée, Z = hauteur.

Contenu : sols en plaques / grilles par rôle de salle, murs à panneaux (faces intérieures claires
à liserés lumineux, coque extérieure sombre à hublots), jupes de machinerie sous la coque,
modules fermés à toit (plaques, radiateurs, antennes, bouches d'aération) effacés à l'intérieur
(passe int), centre de contrôle sous dôme vitré nervuré (consoles en anneau), cylindres-réacteurs
et tubes de liaison, hangar à bandes de danger, décors (consoles, écrans, caisses, couchettes,
labos, câbles…), néons colorés (blanc froid, cyan, rouge d'alerte, orange). Fond : espace étoilé,
la Terre (océans, continents, nuages, terminateur, atmosphère), panneaux solaires et antenne
parabolique dans le vide (non franchissable : cases VOID). Soleil blanc dur.
Les blocs génériques (NT, MB, frame, grade, render_chunked, render_mask, render_occ) sont repris
de fw_scene.py (mêmes conventions, mêmes formats de sortie que compose.py attend).
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

TILT_DEG = float(os.environ.get("SS_TILT", "38"))
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


# ======================================================================= nœuds utilitaires (repris de fw_scene.py)
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


def mat_planet(name, R):
    """Terre (disque posé à plat, ombrage sphérique calculé : pas d'ombre de la station) :
    océans, continents, nuages, terminateur, liseré d'atmosphère. Objet : disque de rayon 1.08·R."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    N = lambda k: nt.nodes.new(k)

    def mth(op, a, b=None, clamp=False):
        n = N("ShaderNodeMath")
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

    def vec(x, y, z):
        c = N("ShaderNodeCombineXYZ")
        for i, q in enumerate((x, y, z)):
            if isinstance(q, (int, float)):
                c.inputs[i].default_value = q
            else:
                nt.links.new(q, c.inputs[i])
        return c.outputs[0]

    def mixc(f, a, b):
        mm = N("ShaderNodeMix")
        mm.data_type = "RGBA"
        if isinstance(f, (int, float)):
            mm.inputs[0].default_value = f
        else:
            nt.links.new(f, mm.inputs[0])
        for i, c in ((6, a), (7, b)):
            if isinstance(c, tuple):
                mm.inputs[i].default_value = (*c, 1)
            else:
                nt.links.new(c, mm.inputs[i])
        return mm.outputs[2]

    def sstep(x, a, b):
        r = N("ShaderNodeMapRange")
        r.interpolation_type = "SMOOTHSTEP"
        nt.links.new(x, r.inputs["Value"])
        r.inputs["From Min"].default_value = a
        r.inputs["From Max"].default_value = b
        return r.outputs[0]

    def noise(v, sc, det=6.0, rough=0.6):
        n = N("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = sc
        n.inputs["Detail"].default_value = det
        n.inputs["Roughness"].default_value = rough
        nt.links.new(v, n.inputs["Vector"])
        return n.outputs["Fac"]

    tc = N("ShaderNodeTexCoord")
    sp = N("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sp.inputs[0])
    x = mth("DIVIDE", sp.outputs[0], 1.0)
    y = mth("DIVIDE", sp.outputs[1], 1.0)
    r2 = mth("ADD", mth("MULTIPLY", x, x), mth("MULTIPLY", y, y))
    inside = mth("LESS_THAN", r2, 1.0)
    nz = mth("SQRT", mth("MAXIMUM", mth("SUBTRACT", 1.0, r2), 0.0))
    n3 = vec(x, y, nz)
    # Lumière : soleil au nord-est, un peu vers la caméra (croissant éclairé en haut à droite)
    L = Vector([float(v) for v in os.environ.get("SS_EARTH_L", "1.0,0.12,0.02").split(",")]).normalized()
    dp = N("ShaderNodeVectorMath")
    dp.operation = "DOT_PRODUCT"
    nt.links.new(n3, dp.inputs[0])
    dp.inputs[1].default_value = tuple(L)
    lit = sstep(dp.outputs["Value"], -0.05, 0.42)
    # Continents / océans (bruit sur la sphère), nuages
    vs = N("ShaderNodeVectorMath")
    vs.operation = "SCALE"
    nt.links.new(n3, vs.inputs[0])
    vs.inputs["Scale"].default_value = 1.0
    land = sstep(noise(vs.outputs[0], 1.6, 8.0, 0.62), 0.52, 0.56)
    det = noise(vs.outputs[0], 7.0, 6.0, 0.6)
    ocean = mixc(det, (0.012, 0.05, 0.2), (0.02, 0.1, 0.3))
    terr = mixc(det, (0.1, 0.16, 0.1), (0.3, 0.3, 0.24))
    surf = mixc(land, ocean, terr)
    cl1 = noise(vs.outputs[0], 3.2, 10.0, 0.66)
    clouds = sstep(cl1, 0.5, 0.66)
    surf = mixc(mth("MULTIPLY", clouds, 0.9), surf, (0.85, 0.88, 0.92))
    night = mixc(mth("MULTIPLY", det, 0.6), (0.004, 0.008, 0.022), (0.01, 0.02, 0.05))
    day = mixc(lit, night, surf)
    # Liseré d'atmosphère (bord du disque côté éclairé) + halo extérieur
    rim = mth("POWER", mth("SUBTRACT", 1.0, nz), 3.0)
    atm = mth("MULTIPLY", rim, mth("ADD", mth("MULTIPLY", lit, 1.4), 0.08))
    col = mixc(mth("MINIMUM", atm, 1.0), day, (0.35, 0.65, 1.0))
    rr = mth("SQRT", r2)
    halo = mth("MULTIPLY", mth("EXPONENT", mth("MULTIPLY", mth("SUBTRACT", rr, 1.0), -28.0)),
               mth("ADD", mth("MULTIPLY", sstep(mth("ADD", mth("MULTIPLY", x, 0.62), mth("MULTIPLY", y, 0.62)), -0.6, 0.6), 1.0), 0.05))
    halo = mth("MULTIPLY", halo, mth("SUBTRACT", 1.0, inside))
    em = N("ShaderNodeEmission")
    colf = mixc(inside, (0.0, 0.0, 0.0), col)
    colf = mixc(mth("MINIMUM", halo, 1.0), colf, (0.3, 0.6, 1.0))
    nt.links.new(colf, em.inputs[0])
    em.inputs[1].default_value = float(os.environ.get("SS_PLANET", "1.0"))
    tr = N("ShaderNodeBsdfTransparent")
    alpha = mth("MAXIMUM", inside, mth("MINIMUM", mth("MULTIPLY", halo, 1.5), 1.0))
    mix = N("ShaderNodeMixShader")
    nt.links.new(alpha, mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    o = N("ShaderNodeOutputMaterial")
    nt.links.new(mix.outputs[0], o.inputs[0])
    MATS[name] = m
    return m


def mat_stars(name):
    """Fond étoilé : points (Voronoï) d'intensités variées + voile bleu-violet très léger."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    em = nt.nodes.new("ShaderNodeEmission")
    add_ = None
    cols = []
    for sc, th, k in ((0.9, 0.04, 5.0), (2.6, 0.06, 2.0), (6.0, 0.07, 0.9)):
        vo = nt.nodes.new("ShaderNodeTexVoronoi")
        vo.inputs["Scale"].default_value = sc
        nt.links.new(tc.outputs["Object"], vo.inputs["Vector"])
        mr = nt.nodes.new("ShaderNodeMapRange")
        nt.links.new(vo.outputs["Distance"], mr.inputs["Value"])
        mr.inputs["From Min"].default_value = th
        mr.inputs["From Max"].default_value = 0.0
        mr.inputs["To Min"].default_value = 0.0
        mr.inputs["To Max"].default_value = k
        wn = nt.nodes.new("ShaderNodeTexWhiteNoise")
        nt.links.new(vo.outputs["Position"], wn.inputs["Vector"])
        mm = nt.nodes.new("ShaderNodeMath")
        mm.operation = "MULTIPLY"
        nt.links.new(mr.outputs[0], mm.inputs[0])
        pw = nt.nodes.new("ShaderNodeMath")
        pw.operation = "POWER"
        nt.links.new(wn.outputs["Value"], pw.inputs[0])
        pw.inputs[1].default_value = 3.0
        nt.links.new(pw.outputs[0], mm.inputs[1])
        cols.append(mm.outputs[0])
    s1 = nt.nodes.new("ShaderNodeMath")
    s1.operation = "ADD"
    nt.links.new(cols[0], s1.inputs[0])
    nt.links.new(cols[1], s1.inputs[1])
    s2 = nt.nodes.new("ShaderNodeMath")
    s2.operation = "ADD"
    nt.links.new(s1.outputs[0], s2.inputs[0])
    nt.links.new(cols[2], s2.inputs[1])
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 0.012
    nz.inputs["Detail"].default_value = 4
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    rp = nt.nodes.new("ShaderNodeValToRGB")
    rp.color_ramp.elements[0].position = 0.45
    rp.color_ramp.elements[0].color = (0.004, 0.006, 0.016, 1)
    rp.color_ramp.elements[1].position = 0.8
    rp.color_ramp.elements[1].color = (0.03, 0.03, 0.08, 1)
    nt.links.new(nz.outputs["Fac"], rp.inputs[0])
    mx = nt.nodes.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    mx.blend_type = "ADD"
    mx.inputs[0].default_value = 1.0
    nt.links.new(rp.outputs[0], mx.inputs[6])
    cm = nt.nodes.new("ShaderNodeCombineColor")
    nt.links.new(s2.outputs[0], cm.inputs[0])
    nt.links.new(s2.outputs[0], cm.inputs[1])
    nt.links.new(s2.outputs[0], cm.inputs[2])
    nt.links.new(cm.outputs[0], mx.inputs[7])
    nt.links.new(mx.outputs[2], em.inputs[0])
    em.inputs[1].default_value = 1.0
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], o.inputs[0])
    MATS[name] = m
    return m


# Couleurs de néons
NEON = {"white": (0.85, 0.93, 1.0), "cyan": (0.25, 0.85, 1.0), "red": (1.0, 0.12, 0.08),
        "orange": (1.0, 0.5, 0.12), "green": (0.3, 1.0, 0.5), "blue": (0.3, 0.5, 1.0)}


def build_materials():
    mat_panels("wall_in", (0.44, 0.48, 0.55), (0.12, 0.14, 0.17), pw=1.0, ph=0.42, metal=0.3, rough=0.42,
               stripe=((0.2, 0.23, 0.28), 0.0, 0.1))
    mat_panels("wall_top", (0.6, 0.63, 0.68), (0.22, 0.24, 0.27), pw=1.0, ph=1.0, metal=0.3, rough=0.45, var=0.05)
    mat_panels("hull_out", (0.22, 0.26, 0.33), (0.06, 0.07, 0.1), pw=0.8, ph=0.36, metal=0.5, rough=0.4, rivets=True,
               stripe=((0.11, 0.13, 0.17), 0.0, 0.18))
    mat_panels("hull_dark", (0.14, 0.16, 0.2), (0.04, 0.045, 0.06), pw=0.6, ph=0.6, metal=0.6, rough=0.45)
    mat_panels("roof_plate", (0.3, 0.33, 0.39), (0.09, 0.1, 0.12), pw=1.2, ph=0.9, metal=0.45, rough=0.38, rivets=True, var=0.18)
    mat_panels("roof_dark", (0.15, 0.17, 0.21), (0.05, 0.06, 0.07), pw=0.6, ph=0.6, metal=0.5, rough=0.4)
    mat_panels("radiator", (0.62, 0.64, 0.66), (0.2, 0.2, 0.22), pw=0.12, ph=4.0, metal=0.7, rough=0.3, var=0.04)
    mat_panels("reactor_shell", (0.32, 0.35, 0.41), (0.09, 0.1, 0.13), pw=0.9, ph=0.5, metal=0.6, rough=0.36, rivets=True)
    mat_floor("floor_corr", (0.32, 0.32, 0.33), (0.08, 0.08, 0.085), cell=2.0, sub=2, var=0.35, rough=0.45, wear=0.5)
    mat_floor("floor_deck", (0.25, 0.26, 0.28), (0.06, 0.065, 0.07), cell=2.0, sub=2, var=0.35, rough=0.5)
    mat_floor("floor_lab", (0.38, 0.41, 0.44), (0.13, 0.14, 0.16), cell=1.0, sub=2, var=0.2, rough=0.3, metal=0.1, wear=0.25)
    mat_floor("floor_ind", (0.3, 0.32, 0.35), (0.09, 0.1, 0.11), cell=1.0, sub=1, rough=0.55, grate=True, wear=0.5)
    mat_floor("floor_hangar", (0.26, 0.28, 0.31), (0.08, 0.08, 0.1), cell=2.0, sub=4, rough=0.5, wear=0.55)
    mat_floor("floor_cc", (0.22, 0.25, 0.31), (0.07, 0.08, 0.11), cell=1.0, sub=2, rough=0.35, metal=0.5)
    mat_floor("floor_quarters", (0.26, 0.26, 0.29), (0.07, 0.07, 0.08), cell=1.0, sub=2, var=0.3, rough=0.55, metal=0.2)
    mat_floor("floor_dmg", (0.33, 0.34, 0.36), (0.07, 0.07, 0.08), cell=1.0, sub=2, rough=0.6, wear=0.9)
    mat_hazard("hazard")
    mat_simple("metal", (0.55, 0.58, 0.62), 0.35, 0.8, 0.15)
    mat_simple("metal_dark", (0.13, 0.14, 0.17), 0.45, 0.7, 0.2)
    mat_simple("metal_mid", (0.32, 0.34, 0.39), 0.4, 0.7, 0.2)
    mat_simple("rubber", (0.04, 0.04, 0.05), 0.8, 0.0, 0.1)
    mat_simple("white_panel", (0.78, 0.8, 0.82), 0.35, 0.2, 0.08)
    mat_simple("crate_orange", (0.78, 0.36, 0.08), 0.6, 0.1, 0.25)
    mat_simple("crate_yellow", (0.8, 0.6, 0.12), 0.6, 0.1, 0.25)
    mat_simple("crate_grey", (0.42, 0.45, 0.48), 0.6, 0.3, 0.2)
    mat_simple("crate_teal", (0.14, 0.34, 0.38), 0.6, 0.2, 0.2)
    mat_simple("mattress", (0.16, 0.22, 0.34), 0.9, 0.0, 0.15)
    mat_simple("sheet", (0.82, 0.84, 0.86), 0.9, 0.0, 0.08)
    mat_simple("plant", (0.12, 0.42, 0.14), 0.8, 0.0, 0.35, c2=(0.05, 0.2, 0.06))
    mat_simple("soil", (0.12, 0.08, 0.05), 0.9)
    mat_simple("cable", (0.05, 0.05, 0.06), 0.6, 0.0, 0.1)
    mat_simple("cable_red", (0.5, 0.06, 0.05), 0.6)
    mat_simple("cable_yellow", (0.75, 0.55, 0.08), 0.6)
    mat_simple("fuel_red", (0.62, 0.1, 0.07), 0.5, 0.3)
    mat_simple("doorway", (0.02, 0.025, 0.035), 0.9, var=0.1)
    mat_decal("scorch", (0.025, 0.02, 0.018), 0.9)
    mat_decal("oil", (0.04, 0.035, 0.03), 0.6)
    mat_simple("fluid", (0.05, 0.4, 0.2), 0.1, emit=((0.15, 1.0, 0.45), 2.5))
    mat_simple("core", (0.2, 0.5, 1.0), 0.1, emit=((0.35, 0.75, 1.0), 9.0))
    mat_glass("glass")
    mat_glass("glass_tank", (0.6, 0.9, 0.8), 0.22)
    mat_solar("solar")
    mat_stars("_stars")
    for k, c in NEON.items():
        mat_emit("neon_" + k, c, 7.0)
        mat_emit("lamp_" + k, c, 3.0)
    mat_screen("screen_cyan", (0.2, 0.8, 1.0), 3.0)
    mat_screen("screen_green", (0.25, 1.0, 0.45), 2.6)
    mat_screen("screen_orange", (1.0, 0.55, 0.15), 2.6)
    mat_screen("screen_red", (1.0, 0.15, 0.1), 2.6)
    mat_emit("window", (0.65, 0.8, 1.0), 2.2)
    mat_emit("window_warm", (1.0, 0.8, 0.55), 2.0)
    mat_emit("holo", (0.25, 0.8, 1.0), 2.5)
    mat_emit("engine", (0.4, 0.7, 1.0), 6.0)

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



# ======================================================================= analyse du layout
ROOMS = LAYOUT.get("rooms", [])
ROOM_BY_ID = {r["id"]: r for r in ROOMS}
MODS = C.get("modules", [])
MOD_BY_ROOM = {m["room"]: m for m in MODS}
CORR_BY_ROOM = {c["room"]: c for c in C.get("corridors", [])}
BLD = {b["id"]: b for b in LAYOUT.get("buildings", [])}
LOWG = set(tuple(c) for c in LAYOUT.get("low_gravity", []))
DOOR_CELLS = {tuple(d["cell"]): d for d in LAYOUT.get("doors", [])}
STAIRS = {tuple(s["cell"]): s for s in LAYOUT.get("stairs", [])}
EXTRACT = set(tuple(c) for c in LAYOUT.get("extraction", []))

# salle de chaque case (la plus petite qui la contient, comme FloorLayout.room_at)
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
    return r["tags"][0] if r and r.get("tags") else "corridor"


def mod_of(rid):
    return MOD_BY_ROOM.get(rid)


# bâtiment (module à toit) de chaque case de son emprise
CELL_BLD = {}
for b in LAYOUT.get("buildings", []):
    x, y, w, h = b["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            CELL_BLD.setdefault((xx, yy), b["id"])
ROUND = {}       # bâtiment → (cx, cy, r) pour les modules ronds
for m in MODS:
    if m.get("round") and m["building"] >= 0:
        ROUND[m["building"]] = m["round"]
TUBE_BLD = {t["building"]: t for t in C.get("tubes", [])}
TUBE_WALLS = set()
for t in C.get("tubes", []):
    for (qx, qy, qw, qh) in t["squares"]:
        for yy in range(qy - 2, qy + qh + 2):
            for xx in range(qx - 2, qx + qw + 2):
                if tile(xx, yy) == 3:
                    TUBE_WALLS.add((xx, yy))
REACTOR_CELLS = set()
for m in MODS:
    if m.get("round") and m.get("arch") == "ss_reactor":
        bx, by, bw, bh = m["rect"]
        for yy in range(by, by + bh):
            for xx in range(bx, bx + bw):
                REACTOR_CELLS.add((xx, yy))
# cases occupées par les objets du jeu (conteneurs, cachettes, portes) : pas de fouillis
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

H_OPEN = 1.3         # murs des zones ouvertes (vues en coupe, comme la maquette)
H_HULL = 1.7         # murs de coque (bord extérieur)
H_ROOF = 1.9         # murs des modules à toit
H_CUT = 0.7          # hauteur du mur sud dans la passe « int »
H_DOOR = 0.95        # linteau des portes


def floor_mat(rid, cell):
    role = role_of(rid)
    m = mod_of(rid)
    if cell in LOWG or (m and m.get("damaged")):
        return "floor_dmg"
    if role in ("hangar", "pod_bay", "airlock"):
        return "floor_hangar"
    if role in ("corridor", "hall"):
        return "floor_corr"
    if role in ("tube",):
        return "floor_ind"
    if role in ("lab", "lab_vault", "infirmary", "hydroponics"):
        return "floor_lab"
    if role in ("reactor_pod", "workshop", "cargo_hold", "storage", "server_room", "closet", "armory"):
        return "floor_ind" if role in ("reactor_pod", "server_room") else "floor_deck"
    if role == "control_center":
        return "floor_cc"
    if role in ("quarters", "mess_hall"):
        return "floor_quarters"
    return "floor_deck"


def light_of(rid):
    """Couleur et force des néons d'une salle."""
    role = role_of(rid)
    m = mod_of(rid) or {}
    slot = m.get("slot", "")
    if m.get("damaged"):
        return "red", 0.8
    if slot.startswith("red_") or role in ("armory", "lab_vault"):
        return "red", 1.0
    if role in ("hangar",):
        return "white", 1.4
    if role in ("pod_bay", "airlock"):
        return "white", 1.1
    if role in ("corridor", "hall", "tube"):
        return "white", 0.9
    if role in ("lab", "infirmary", "hydroponics", "control_center", "server_room"):
        return "cyan", 1.0
    if role in ("workshop", "cargo_hold", "storage", "closet", "reactor_pod"):
        return "orange", 0.9
    return "white", 0.9


# ======================================================================= sols
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
            X0, X1 = x, x + 1
            YN, YS = Y(y), Y(y + 1)
            mb.poly([(X0, YS, 0.0), (X1, YS, 0.0), (X1, YN, 0.0), (X0, YN, 0.0)], mat,
                    [(X0, YS), (X1, YS), (X1, YN), (X0, YN)])
    # marquages : bandes de danger du hangar et des sas, bande centrale de la coursive,
    # pastilles d'extraction, plateformes d'ascenseur
    mk = MB()
    for r in ROOMS:
        role = r["tags"][0] if r.get("tags") else ""
        x, y, w, h = r["rect"]
        if role in ("hangar",):
            # cadre de danger + grande trappe centrale
            for (a0, a1, b0, b1) in ((x + 0.3, x + w - 0.3, y + 0.3, y + 0.62), (x + 0.3, x + w - 0.3, y + h - 0.62, y + h - 0.3)):
                mk.box(a0, Y(b1), 0.0, a1, Y(b0), 0.012, "hazard")
            cx, cy = x + w / 2, y + h / 2 + 0.8
            mk.box(cx - 3.2, Y(cy + 1.9), 0.0, cx + 3.2, Y(cy - 1.9), 0.01, "metal_dark")
            for (a0, a1, b0, b1) in ((cx - 3.2, cx + 3.2, cy - 1.9, cy - 1.6), (cx - 3.2, cx + 3.2, cy + 1.6, cy + 1.9),
                                     (cx - 3.2, cx - 2.9, cy - 1.9, cy + 1.9), (cx + 2.9, cx + 3.2, cy - 1.9, cy + 1.9)):
                mk.box(a0, Y(b1), 0.0, a1, Y(b0), 0.016, "hazard")
        if role in ("corridor",) and "v" in r.get("tags", []):
            cx = x + w / 2
            mk.box(cx - 0.08, Y(y + h), 0.0, cx + 0.08, Y(y), 0.008, "metal_dark")
            for k in range(int(h)):
                if (k % 3) == 0:
                    mk.box(cx - 0.35, Y(y + k + 0.55), 0.0, cx + 0.35, Y(y + k + 0.45), 0.01, "cable_yellow")
        if role in ("hall",):
            mk.box(x + 0.2, Y(y + h - 0.2), 0.0, x + w - 0.2, Y(y + h - 0.32), 0.008, "cable_yellow")
            mk.box(x + 0.2, Y(y + 0.32), 0.0, x + w - 0.2, Y(y + 0.2), 0.008, "cable_yellow")
    for (ex, ey) in EXTRACT:
        mk.box(ex + 0.06, Y(ey + 0.94), 0.0, ex + 0.94, Y(ey + 0.06), 0.012, "hazard")
    for (sx, sy), st in STAIRS.items():
        mk.cyl(sx + 0.5, Y(sy) - 0.5, 0.0, 0.04, 0.46, "metal", 24)
        mk.cyl(sx + 0.5, Y(sy) - 0.5, 0.0, 0.05, 0.36, "neon_cyan" if st["up"] else "neon_orange", 24)
        mk.cyl(sx + 0.5, Y(sy) - 0.5, 0.0, 0.06, 0.3, "metal_dark", 24)
    mk.to_object("ground_marks", "world")
    for key, mb in mbs.items():
        mb.to_object(key, "world")


# ======================================================================= murs
def wall_h(x, y):
    if tile(x, y) != 3:
        return 0.0
    if (x, y) in TUBE_WALLS and (x, y) not in REACTOR_CELLS:
        return 0.35
    b = CELL_BLD.get((x, y))
    if b is not None and BLD[b]["arch"] in ("ss_module", "ss_lift"):
        return H_ROOF
    if b is not None and BLD[b]["arch"] == "ss_reactor":
        return 1.0
    if b is not None and BLD[b]["arch"] == "ss_dome":
        return 0.9
    if b is not None and BLD[b]["arch"] == "ss_tube":
        return 0.9
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if tile(x + dx, y + dy) == 0:
                return H_HULL
    return H_OPEN


def face(mb, x, y, side, z0, z1, mat):
    """Face verticale du côté `side` (N, S, E, W) de la case mur (x, y), de z0 à z1."""
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


def build_walls():
    """Murs case par case : faces intérieures (panneaux clairs, liseré lumineux) côté salle,
    coque sombre côté vide, chapeau ; murs des modules à toit dans walls_<id> (le haut du mur
    sud dans front_<id>, masqué par la passe int). Encadrements des portes."""
    mbs = {}
    trims = {}

    def target(x, y, upper_south=False):
        b = CELL_BLD.get((x, y))
        if b is None:
            return mbs.setdefault("hullwalls", MB())
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
    CH = 0.6     # chanfrein des angles extérieurs de la coque (silhouette octogonale des modules)
    for y in range(H):
        for x in range(W):
            if tile(x, y) != 3 or (x, y) in round_cells:
                continue
            h = wall_h(x, y)
            b = CELL_BLD.get((x, y))
            south_row = b is not None and BLD[b]["arch"] in ("ss_module", "ss_lift") and y == BLD[b]["rect"][1] + BLD[b]["rect"][3] - 1
            X0, X1 = x, x + 1
            YN, YS = Y(y), Y(y + 1)
            # angle extérieur : vide sur deux côtés orthogonaux (et en diagonale), murs ailleurs
            vs = {sd: tile(x + dx, y + dy) == 0 for sd, dx, dy in SIDES}
            corner = None
            if b is None and (x, y) not in TUBE_WALLS:
                for (s1, s2, cx_, cy_) in (("S", "W", X0, YS), ("S", "E", X1, YS), ("N", "W", X0, YN), ("N", "E", X1, YN)):
                    o1 = {"S": "N", "N": "S"}[s1]
                    o2 = {"W": "E", "E": "W"}[s2]
                    if vs[s1] and vs[s2] and not vs[o1] and not vs[o2]:
                        corner = (s1, s2, cx_, cy_)
            for side, dx, dy in SIDES:
                nx, ny = x + dx, y + dy
                nt_ = tile(nx, ny)
                if nt_ == 3:
                    nh = wall_h(nx, ny) if (nx, ny) not in round_cells else 1.0
                    if nh >= h - 1e-3:
                        continue
                    z0 = nh
                    mat = "wall_in"
                elif nt_ == 0:
                    z0 = -0.25
                    mat = "hull_out"
                else:
                    z0 = 0.0
                    mat = "wall_in"
                if (x, y) in TUBE_WALLS:
                    mat = "hull_dark"
                if corner and side in (corner[0], corner[1]):
                    continue
                if south_row and h > H_CUT:
                    # mur sud d'un module à toit : bas toujours visible, haut masqué en passe int
                    if z0 < H_CUT:
                        face(target(x, y), x, y, side, z0, H_CUT, mat)
                    face(target(x, y, True), x, y, side, max(z0, H_CUT), h, mat)
                else:
                    face(target(x, y), x, y, side, z0, h, mat)
            if corner:
                s1, s2, cx_, cy_ = corner
                sy_ = 1.0 if s1 == "S" else -1.0
                sx_ = 1.0 if s2 == "W" else -1.0
                pa = (cx_ + sx_ * CH, cy_)            # sur le bord s1
                pb = (cx_, cy_ + sy_ * CH)            # sur le bord s2
                ea = (cx_ + sx_ * 1.0, cy_)
                eb = (cx_, cy_ + sy_ * 1.0)
                far = (cx_ + sx_ * 1.0, cy_ + sy_ * 1.0)
                tg = target(x, y)
                z0 = -0.25
                tg.poly([(pa[0], pa[1], z0), (pb[0], pb[1], z0), (pb[0], pb[1], h), (pa[0], pa[1], h)], "hull_out",
                        [(0, z0), (CH * 1.41, z0), (CH * 1.41, h), (0, h)])
                tg.poly([(pa[0], pa[1], z0), (ea[0], ea[1], z0), (ea[0], ea[1], h), (pa[0], pa[1], h)], "hull_out",
                        [(0, z0), (1 - CH, z0), (1 - CH, h), (0, h)])
                tg.poly([(pb[0], pb[1], z0), (eb[0], eb[1], z0), (eb[0], eb[1], h), (pb[0], pb[1], h)], "hull_out",
                        [(0, z0), (1 - CH, z0), (1 - CH, h), (0, h)])
                tg.poly([(pa[0], pa[1], h), (ea[0], ea[1], h), (far[0], far[1], h), (eb[0], eb[1], h), (pb[0], pb[1], h)], "wall_top")
                continue
            # chapeau (au niveau du toit pour le mur sud d'un module à toit : passe int → bas)
            if south_row:
                tgt = target(x, y, True)
                tgt.poly([(X0, YS, h), (X1, YS, h), (X1, YN, h), (X0, YN, h)], "wall_top", [(X0, YS), (X1, YS), (X1, YN), (X0, YN)])
                low = target(x, y)
                low.poly([(X0, YS, H_CUT), (X1, YS, H_CUT), (X1, YN, H_CUT), (X0, YN, H_CUT)], "metal_dark",
                         [(X0, YS), (X1, YS), (X1, YN), (X0, YN)])
            elif (x, y) in TUBE_WALLS:
                target(x, y).poly([(X0, YS, h), (X1, YS, h), (X1, YN, h), (X0, YN, h)], "hull_dark",
                                  [(X0, YS), (X1, YS), (X1, YN), (X0, YN)])
            else:
                target(x, y).poly([(X0, YS, h), (X1, YS, h), (X1, YN, h), (X0, YN, h)], "wall_top",
                                  [(X0, YS), (X1, YS), (X1, YN), (X0, YN)])
                # liseré clair du bord supérieur côté salle (contour net, comme la maquette)
                for side, dx, dy in SIDES:
                    if not walk(x + dx, y + dy):
                        continue
                    rim = trims.setdefault("_rims", MB())
                    if side == "S":
                        rim.box(X0, YS, h, X1, YS + 0.07, h + 0.03, "metal")
                    elif side == "N":
                        rim.box(X0, YN - 0.07, h, X1, YN, h + 0.03, "metal")
                    elif side == "E":
                        rim.box(X1 - 0.07, YS, h, X1, YN, h + 0.03, "metal")
                    else:
                        rim.box(X0, YS, h, X0 + 0.07, YN, h + 0.03, "metal")
    # liserés lumineux au pied des murs intérieurs (couleur de la salle), écrans muraux
    for y in range(H):
        for x in range(W):
            if not walk(x, y) or (x, y) in DOOR_CELLS:
                continue
            rid = CELL_ROOM.get((x, y), -1)
            col, k = light_of(rid)
            for side, dx, dy in SIDES:
                wx, wy = x + dx, y + dy
                if tile(wx, wy) != 3 or (wx, wy) in round_cells or (wx, wy) in DOOR_CELLS:
                    continue
                h = wall_h(wx, wy)
                tb = trims.setdefault("_lights", MB())
                # bande lumineuse haute (sous le chapeau) côté salle ; basse dans les modules à
                # toit (reste visible quand le haut du mur sud est masqué)
                wb = CELL_BLD.get((wx, wy))
                zt = min(h, H_OPEN) - 0.16
                if wb is not None and BLD[wb]["arch"] in ("ss_module", "ss_lift"):
                    zt = H_CUT - 0.2
                if side == "N":     # mur au nord de la case : face sud du mur (visible)
                    tb.box(x + 0.08, Y(y) - 0.02, zt, x + 0.92, Y(y) + 0.0, zt + 0.06, "neon_" + col)
                    tb.box(x, Y(y) - 0.03, 0.0, x + 1, Y(y), 0.08, "metal_dark")
                    zmax = min(h, H_OPEN) - 0.22 if not (wb is not None and BLD[wb]["arch"] in ("ss_module", "ss_lift")) else H_CUT - 0.25
                    r_ = RNG.random()
                    if (x, y) in GAME_CELLS:
                        pass
                    elif r_ < 0.14:
                        scr = RNG.choice(["screen_cyan", "screen_green", "screen_orange", "screen_cyan"])
                        tb.box(x + 0.14, Y(y) - 0.05, 0.3, x + 0.86, Y(y) + 0.0, min(0.78, zmax), "metal_dark")
                        tb.box(x + 0.18, Y(y) - 0.06, 0.34, x + 0.82, Y(y) - 0.05, min(0.74, zmax - 0.04), scr)
                    elif r_ < 0.26:
                        tb.box(x + 0.12, Y(y) - 0.07, 0.15, x + 0.88, Y(y) + 0.0, min(0.7, zmax), "metal_mid")
                        for j in range(4):
                            zz = 0.22 + j * 0.11
                            if zz + 0.04 < min(0.7, zmax):
                                tb.box(x + 0.2, Y(y) - 0.075, zz, x + 0.8, Y(y) - 0.07, zz + 0.04, "metal_dark")
                    elif r_ < 0.36:
                        for px_ in (0.3, 0.6):
                            tb.cyl(x + px_, Y(y) - 0.08, 0.0, zmax, 0.05, RNG.choice(["metal", "cable_yellow", "cable_red"]), 8)
                    elif r_ < 0.44:
                        tb.box(x + 0.35, Y(y) - 0.04, zmax - 0.3, x + 0.65, Y(y) + 0.0, zmax - 0.05, "neon_white")
                elif side == "S":
                    tb.box(x + 0.08, Y(y + 1), zt, x + 0.92, Y(y + 1) + 0.02, zt + 0.06, "neon_" + col)
                elif side == "E":
                    tb.box(x + 0.98, Y(y + 1) + 0.08, zt, x + 1.0, Y(y) - 0.08, zt + 0.06, "neon_" + col)
                else:
                    tb.box(x + 0.0, Y(y + 1) + 0.08, zt, x + 0.02, Y(y) - 0.08, zt + 0.06, "neon_" + col)
    # portes : linteau, montants, seuil sombre (le jeu dessine le battant coulissant)
    for (dx_, dy_), d in DOOR_CELLS.items():
        bid = CELL_BLD.get((dx_, dy_))
        hh = max(wall_h(dx_ - 1, dy_) if d["vertical"] is False else wall_h(dx_, dy_ - 1), H_OPEN)
        if bid is not None and BLD[bid]["arch"] in ("ss_module", "ss_lift"):
            hh = H_ROOF
        south = bid is not None and BLD[bid]["arch"] in ("ss_module", "ss_lift") and dy_ == BLD[bid]["rect"][1] + BLD[bid]["rect"][3] - 1
        tg = mbs.setdefault(("front_%d" % bid) if south else (("walls_%d" % bid) if bid is not None else "hullwalls"), MB())
        X0, X1, YN, YS = dx_, dx_ + 1, Y(dy_), Y(dy_ + 1)
        locked = d.get("state", 1) == 2
        if not d["vertical"]:
            tg.box(X0, YS, H_DOOR, X1, YN, hh, "wall_in")
            for ex in (X0, X1 - 0.1):
                tg.box(ex, YS - 0.03, 0.0, ex + 0.1, YN + 0.03, H_DOOR + 0.05, "hazard" if not locked else "neon_red")
            tg.box(X0, YS - 0.03, H_DOOR, X1, YN + 0.03, H_DOOR + 0.08, "metal_dark")
        else:
            tg.box(X0, YS, H_DOOR, X1, YN, hh, "wall_in")
            for ey in (YS, YN - 0.1):
                tg.box(X0 - 0.03, ey, 0.0, X1 + 0.03, ey + 0.1, H_DOOR + 0.05, "hazard" if not locked else "neon_red")
            tg.box(X0 - 0.03, YS, H_DOOR, X1 + 0.03, YN, H_DOOR + 0.08, "metal_dark")
        mbs.setdefault("ground_door", MB()).box(X0 + 0.05, YS + 0.05, 0.0, X1 - 0.05, YN - 0.05, 0.015, "doorway")
        # voyant coloré au-dessus de la porte (rouge = verrouillée / alerte, cyan sinon)
        rng_d = random.Random(dx_ * 97 + dy_ * 13 + SEED)
        dcol = "red" if locked or rng_d.random() < 0.35 else rng_d.choice(["cyan", "cyan", "white"])
        gl = mbs.setdefault("_doorlights", MB())
        if not d["vertical"]:
            gl.box(X0 + 0.25, YS - 0.04, hh - 0.18, X1 - 0.25, YS, hh - 0.08, "neon_" + dcol)
            gl.box(X0 + 0.25, YN, hh - 0.18, X1 - 0.25, YN + 0.04, hh - 0.08, "neon_" + dcol)
        else:
            gl.box(X0 - 0.04, YS + 0.25, hh - 0.18, X0, YN - 0.25, hh - 0.08, "neon_" + dcol)
            gl.box(X1, YS + 0.25, hh - 0.18, X1 + 0.04, YN - 0.25, hh - 0.08, "neon_" + dcol)
        DOOR_GLOWS.append((dx_ + 0.5, Y(dy_) - 0.5, dcol))
    for k, mb in mbs.items():
        mb.to_object(k, "world")
    for k, mb in trims.items():
        mb.to_object(k, "world")


# ======================================================================= coque extérieure
def build_hull():
    """Jupes de machinerie sous la coque (côté sud, visibles en vue inclinée), hublots et
    panneaux lumineux sur les faces sud de la coque, nervures."""
    sk = MB()
    win = MB()
    skip = REACTOR_CELLS | TUBE_WALLS
    for y in range(H):
        for x in range(W):
            if tile(x, y) != 3 or (x, y) in skip:
                continue
            if tile(x, y + 1) == 0:
                # face sud exposée au vide : jupe sous le pont + nervures + hublots
                r = random.Random(x * 131 + y * 7 + SEED)
                d = 0.75 + 0.45 * mnoise.noise(Vector((x * 0.21, y * 0.3, 0.0)))
                sk.box(x - 0.01, Y(y + 1) - d, -1.6 - r.uniform(0, 0.8), x + 1.01, Y(y + 1) + 0.02, -0.02, "hull_dark")
                sk.box(x + 0.1, Y(y + 1) - d - 0.05, -1.2, x + 0.9, Y(y + 1) - d + 0.15, -0.3, "hull_out")
                if r.random() < 0.5:
                    sk.cyl(x + 0.5, Y(y + 1) - d * 0.7, -0.9, 1.0, r.uniform(0.18, 0.32), "metal_mid", 10, axis="X")
                if r.random() < 0.12:
                    sk.box(x + 0.3, Y(y + 1) - d - 0.02, -0.6, x + 0.7, Y(y + 1) - d + 0.0, -0.35, "neon_cyan")
                if x % 2 == 0:
                    sk.box(x + 0.42, Y(y + 1) - 0.08, -0.25, x + 0.58, Y(y + 1) + 0.01, wall_h(x, y) - 0.05, "metal_dark")
                if r.random() < 0.55:
                    win.box(x + 0.18, Y(y + 1) - 0.015, 0.35, x + 0.82, Y(y + 1) + 0.0, 0.95,
                            "window" if r.random() < 0.6 else "neon_cyan")
                elif x % 4 == 1:
                    win.box(x + 0.4, Y(y + 1) - 0.015, 0.1, x + 0.6, Y(y + 1) + 0.0, 1.0, "neon_white")
            for side, dx, dy in (("E", 1, 0), ("W", -1, 0), ("N", 0, -1)):
                if tile(x + dx, y + dy) != 0:
                    continue
                r = random.Random(x * 17 + y * 911 + SEED + dx)
                if side in ("E", "W") and y % 3 == 0:
                    ox = x + (1.0 if dx > 0 else 0.0)
                    sk.box(ox - 0.08 if dx < 0 else ox, Y(y + 1), -0.7, ox + 0.08 if dx > 0 else ox, Y(y), wall_h(x, y) - 0.1, "metal_dark")
                if side in ("E", "W") and r.random() < 0.25:
                    ox = x + (1.0 if dx > 0 else 0.0)
                    win.box(ox - 0.012 if dx < 0 else ox, Y(y + 1) + 0.2, 0.45, ox + 0.012 if dx > 0 else ox, Y(y) - 0.2, 0.8, "window")
    # rebord de coque (cases vides voisines d'un mur) : liseré sombre épais, comme la maquette
    for y in range(H):
        for x in range(W):
            if tile(x, y) != 0:
                continue
            for side, dx, dy in SIDES:
                if tile(x + dx, y + dy) != 3 or (x + dx, y + dy) in skip:
                    continue
                e = 0.32
                if side == "S":      # mur au sud de la case vide : rebord sur la frange sud
                    sk.box(x, Y(y + 1), -0.5, x + 1, Y(y + 1) + e, 0.55, "hull_dark")
                elif side == "N":
                    sk.box(x, Y(y) - e, -0.5, x + 1, Y(y), 0.55, "hull_dark")
                elif side == "E":
                    sk.box(x + 1 - e, Y(y + 1), -0.5, x + 1, Y(y), 0.55, "hull_dark")
                else:
                    sk.box(x, Y(y + 1), -0.5, x + e, Y(y), 0.55, "hull_dark")
    sk.to_object("skirt", "world")
    win.to_object("hullwin", "world")


# ======================================================================= modules à toit
def roof_rect(mb, b, rng):
    """Toit plat de module : plaque sombre à panneaux en relief, rebord, banc de radiateurs,
    réservoirs couchés, bouches d'aération, conduites, bande de danger, antenne et balises."""
    x, y, w, h = b["rect"]
    z = H_ROOF
    X0, X1, YN, YS = x - 0.04, x + w + 0.04, Y(y) + 0.04, Y(y + h) - 0.04
    mb.box(X0, YS, z, X1, YN, z + 0.12, "roof_dark")
    for (a0, a1, b0, b1) in ((X0, X1, YS, YS + 0.14), (X0, X1, YN - 0.14, YN), (X0, X0 + 0.14, YS, YN), (X1 - 0.14, X1, YS, YN)):
        mb.box(a0, b0, z + 0.12, a1, b1, z + 0.24, "metal_mid")
    zt = z + 0.12
    horiz = w >= h
    # panneaux en relief (2 à 4)
    np_ = rng.randint(2, 4)
    for k in range(np_):
        if horiz:
            u0 = x + 0.35 + k * (w - 0.7) / np_
            u1 = u0 + (w - 0.7) / np_ - 0.12
            mb.box(u0, Y(y + h - 0.35), zt, u1, Y(y + 0.35), zt + 0.05, "roof_plate")
        else:
            v0 = y + 0.35 + k * (h - 0.7) / np_
            v1 = v0 + (h - 0.7) / np_ - 0.12
            mb.box(x + 0.35, Y(v1), zt, x + w - 0.35, Y(v0), zt + 0.05, "roof_plate")
    zt2 = zt + 0.05
    # banc de radiateurs (lames claires) sur 40-60 % du toit
    f = rng.uniform(0.4, 0.6)
    if horiz:
        rx0, rx1 = x + 0.5, x + 0.5 + (w - 1.0) * f
        nb = int((h - 1.0) / 0.26)
        for k in range(nb):
            yy = y + 0.5 + k * 0.26
            mb.box(rx0, Y(yy + 0.13), zt2, rx1, Y(yy), zt2 + 0.16, "radiator")
        free_x0 = rx1 + 0.3
    else:
        ry0, ry1 = y + 0.5, y + 0.5 + (h - 1.0) * f
        nb = int((w - 1.0) / 0.26)
        for k in range(nb):
            xx = x + 0.5 + k * 0.26
            mb.box(xx, Y(ry1), zt2, xx + 0.13, Y(ry0), zt2 + 0.16, "radiator")
        free_x0 = x + 0.6
    # réservoir couché
    if rng.random() < 0.7:
        if horiz:
            cx_ = min(x + w - 1.0, free_x0 + 0.8)
            mb.seg((cx_, Y(y + 0.9), zt2 + 0.35), (cx_, Y(y + h - 0.9), zt2 + 0.35), 0.33, "white_panel", 14)
            for t_ in (0.25, 0.5, 0.75):
                yy = y + 0.9 + (h - 1.8) * t_
                mb.seg((cx_, Y(yy - 0.04), zt2 + 0.35), (cx_, Y(yy + 0.04), zt2 + 0.35), 0.35, "metal_dark", 14)
        else:
            cy_ = y + h - 1.2
            mb.seg((x + 0.9, Y(cy_), zt2 + 0.35), (x + w - 0.9, Y(cy_), zt2 + 0.35), 0.33, "white_panel", 14)
    # bouches d'aération (grilles + ventilateurs)
    for k in range(rng.randint(2, 3)):
        vx = rng.uniform(max(free_x0, x + 0.8), x + w - 0.8) if horiz else x + rng.uniform(0.8, w - 0.8)
        vy = y + rng.uniform(0.8, h - 0.8) if horiz else y + rng.uniform(h * 0.62, h - 0.7)
        if rng.random() < 0.5:
            mb.cyl(vx, Y(vy), zt2, zt2 + 0.2, 0.3, "metal_mid", 16)
            mb.cyl(vx, Y(vy), zt2 + 0.2, zt2 + 0.22, 0.25, "metal_dark", 16)
        else:
            mb.box(vx - 0.35, Y(vy) - 0.25, zt2, vx + 0.35, Y(vy) + 0.25, zt2 + 0.14, "metal_mid")
            for j in range(4):
                mb.box(vx - 0.3, Y(vy) - 0.2 + j * 0.12, zt2 + 0.14, vx + 0.3, Y(vy) - 0.15 + j * 0.12, zt2 + 0.16, "metal_dark")
    # conduite le long d'un bord + bande de danger
    mb.seg((x + 0.3, Y(y + 0.32), zt2 + 0.08), (x + w - 0.3, Y(y + 0.32), zt2 + 0.08), 0.07, "cable_yellow", 6)
    if rng.random() < 0.6:
        mb.box(x + 0.3, Y(y + h - 0.32), zt2, x + w - 0.3, Y(y + h - 0.52), zt2 + 0.02, "hazard")
    # antenne + balises
    if rng.random() < 0.7:
        ax = x + rng.uniform(0.8, w - 0.8)
        ay = y + rng.uniform(0.6, h * 0.5)
        mb.cyl(ax, Y(ay), zt2, zt2 + rng.uniform(0.9, 1.5), 0.04, "metal", 6)
        mb.sphere(ax, Y(ay), zt2 + 0.05, 0.12, "neon_red", 1)
    for (bx, by) in ((x + 0.3, y + 0.3), (x + w - 0.3, y + h - 0.3), (x + w - 0.3, y + 0.3)):
        mb.sphere(bx, Y(by), zt + 0.2, 0.07, rng.choice(["neon_red", "neon_green", "neon_cyan"]), 1)


def build_roofs():
    for b in LAYOUT.get("buildings", []):
        bid = b["id"]
        arch = b["arch"]
        rng = random.Random(bid * 7919 + SEED)
        mb = MB()
        if arch in ("ss_module", "ss_lift"):
            roof_rect(mb, b, rng)
        elif arch == "ss_dome":
            build_dome(b, mb, rng)
        elif arch == "ss_reactor":
            build_reactor(b, mb, rng)
        elif arch == "ss_tube":
            build_tube(b, mb, rng)
        mb.to_object("roof_%d" % bid, "roofs")


def openings_mask(cx, cy, r, ang, spread=0.06):
    """True si l'angle `ang` (radians) tombe dans une ouverture de la salle ronde : une case
    marchable au-delà du rayon (échantillons à r+0,3 / +0,6 / +0,9, angle ± spread)."""
    for da in (-spread, 0.0, spread):
        for dr in (0.3, 0.6, 0.9):
            px = cx + math.cos(ang + da) * (r + dr)
            py = cy - math.sin(ang + da) * (r + dr)
            if walk(int(math.floor(px)), int(math.floor(py))):
                return True
    return False


def build_dome(b, roof, rng):
    """Centre de contrôle : mur annulaire bas à ouvertures, socle des angles (machinerie), dôme
    vitré nervuré (toit), anneau de consoles intérieur."""
    bid = b["id"]
    rcx, rcy, r = ROUND[bid]
    cx, cy = rcx, -rcy
    walls = MB()
    front = MB()
    seg = 96
    z1 = 0.9
    for i in range(seg):
        a0 = i / seg * math.tau
        a1 = (i + 1) / seg * math.tau
        if openings_mask(rcx, rcy, r, (a0 + a1) / 2):
            continue
        ring_wall_seg(walls, front, cx, cy, r + 0.05, r + 0.75, a0, a1, 0.45, z1, "hull_out")
    # socle des coins (cases mur du rectangle hors anneau) : plinthe continue + bancs de consoles
    x, y, w, h = b["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if tile(xx, yy) != 3:
                continue
            d = math.hypot(xx + 0.5 - rcx, yy + 0.5 - rcy)
            if d < r + 0.6:
                continue
            walls.box(xx, Y(yy + 1), 0.0, xx + 1, Y(yy), 0.42, "wall_top")
    for k in range(24):
        a = (k + 0.5) / 24 * math.tau
        px_, py_ = rcx + math.cos(a) * (r + 1.6), rcy - math.sin(a) * (r + 1.6)
        if tile(int(px_), int(py_)) != 3 or openings_mask(rcx, rcy, r, a):
            continue
        X_, Y_ = px_, -py_
        walls.box(X_ - 0.32, Y_ - 0.32, 0.42, X_ + 0.32, Y_ + 0.32, 0.74, "metal_dark")
        walls.box(X_ - 0.26, Y_ - 0.26, 0.74, X_ + 0.26, Y_ + 0.26, 0.76, rng.choice(["screen_cyan", "screen_green", "screen_cyan", "screen_orange"]))
    # anneau lumineux au sol
    for i in range(seg):
        a0 = i / seg * math.tau
        a1 = (i + 1) / seg * math.tau
        rr0, rr1 = r - 0.35, r - 0.22
        walls.poly([(cx + math.cos(a0) * rr0, cy + math.sin(a0) * rr0, 0.012), (cx + math.cos(a1) * rr0, cy + math.sin(a1) * rr0, 0.012),
                    (cx + math.cos(a1) * rr1, cy + math.sin(a1) * rr1, 0.012), (cx + math.cos(a0) * rr1, cy + math.sin(a0) * rr1, 0.012)], "neon_cyan")
    for i in range(3):
        rr = r * (0.3 + 0.2 * i)
        for k in range(seg):
            a0 = k / seg * math.tau
            a1 = (k + 1) / seg * math.tau
            walls.poly([(cx + math.cos(a0) * rr, cy + math.sin(a0) * rr, 0.006), (cx + math.cos(a1) * rr, cy + math.sin(a1) * rr, 0.006),
                        (cx + math.cos(a1) * (rr + 0.05), cy + math.sin(a1) * (rr + 0.05), 0.006),
                        (cx + math.cos(a0) * (rr + 0.05), cy + math.sin(a0) * (rr + 0.05), 0.006)], "metal")
    walls.to_object("walls_%d" % bid, "world")
    front.to_object("front_%d" % bid, "roofs")
    # dôme vitré : calotte (hémisphère aplati) + nervures radiales + anneaux
    R = r + 0.55
    hz = 2.2
    nseg, nring = 48, 10
    rows = []
    for j in range(nring + 1):
        t = j / nring * (math.pi / 2)
        rows.append((math.cos(t) * R, z1 + math.sin(t) * hz))
    for j in range(nring):
        (ra, za), (rb, zb) = rows[j], rows[j + 1]
        for i in range(nseg):
            a0 = i / nseg * math.tau
            a1 = (i + 1) / nseg * math.tau
            roof.poly([(cx + math.cos(a0) * ra, cy + math.sin(a0) * ra, za), (cx + math.cos(a1) * ra, cy + math.sin(a1) * ra, za),
                       (cx + math.cos(a1) * rb, cy + math.sin(a1) * rb, zb), (cx + math.cos(a0) * rb, cy + math.sin(a0) * rb, zb)], "glass")
    for i in range(12):
        a = i / 12 * math.tau + 0.13
        for j in range(nring):
            (ra, za), (rb, zb) = rows[j], rows[j + 1]
            roof.seg((cx + math.cos(a) * ra, cy + math.sin(a) * ra, za), (cx + math.cos(a) * rb, cy + math.sin(a) * rb, zb), 0.07, "metal_mid", 6)
    for j in (0, 3, 6):
        ra, za = rows[j]
        for i in range(nseg):
            a0 = i / nseg * math.tau
            a1 = (i + 1) / nseg * math.tau
            roof.seg((cx + math.cos(a0) * ra, cy + math.sin(a0) * ra, za), (cx + math.cos(a1) * ra, cy + math.sin(a1) * ra, za), 0.06, "metal_mid", 5)
    roof.cyl(cx, cy, z1 + hz - 0.05, z1 + hz + 0.18, 0.7, "metal_mid", 24)
    roof.cyl(cx, cy, z1 + hz + 0.18, z1 + hz + 0.22, 0.45, "neon_cyan", 24)


def ring_wall_seg(mb_low, mb_high, cx, cy, r0, r1, a0, a1, z_cut, z_top, mat, z_from=0.0):
    south = math.sin((a0 + a1) / 2) < 0
    P = [(cx + math.cos(a) * r0, cy + math.sin(a) * r0, cx + math.cos(a) * r1, cy + math.sin(a) * r1) for a in (a0, a1)]

    def quad(mb, z0, z1, cap=True):
        (ax0, ay0, ax1, ay1), (bx0, by0, bx1, by1) = P
        mb.poly([(ax1, ay1, z0), (bx1, by1, z0), (bx1, by1, z1), (ax1, ay1, z1)], mat,
                [(a0 * r1, z0), (a1 * r1, z0), (a1 * r1, z1), (a0 * r1, z1)])
        mb.poly([(bx0, by0, z0), (ax0, ay0, z0), (ax0, ay0, z1), (bx0, by0, z1)], "wall_in",
                [(a1 * r0, z0), (a0 * r0, z0), (a0 * r0, z1), (a1 * r0, z1)])
        if cap:
            mb.poly([(ax0, ay0, z1), (ax1, ay1, z1), (bx1, by1, z1), (bx0, by0, z1)], "wall_top",
                    [(a0 * r0, 0), (a0 * r1, 0), (a1 * r1, 1), (a1 * r0, 1)])
    if south and z_top > z_cut and z_from < z_cut:
        quad(mb_low, z_from, z_cut)
        quad(mb_high, z_cut, z_top)
    elif south and z_from >= z_cut:
        quad(mb_high, z_from, z_top)
    else:
        quad(mb_low, z_from, z_top)


def build_reactor(b, roof, rng):
    """Cylindre-réacteur : coque cylindrique haute (bas du mur toujours, haut du côté sud et
    calotte dans le toit), nervures, hublots ; à l'intérieur le cœur (décor reactor_core)."""
    bid = b["id"]
    rcx, rcy, r = ROUND[bid]
    cx, cy = rcx, -rcy
    walls = MB()
    front = MB()
    seg = 72
    ztop = 3.3
    for i in range(seg):
        a0 = i / seg * math.tau
        a1 = (i + 1) / seg * math.tau
        if openings_mask(rcx, rcy, r, (a0 + a1) / 2):
            # ouverture (tube) : linteau au-dessus de la porte
            ring_wall_seg(front, front, cx, cy, r + 0.05, r + 0.85, a0, a1, 1.1, ztop, "reactor_shell", z_from=1.1)
            continue
        ring_wall_seg(walls, front, cx, cy, r + 0.05, r + 0.85, a0, a1, 0.8, 1.05, "reactor_shell")
        # haut de la coque : moitié nord → walls (reste visible en int, comme un mur du fond)
        if math.sin((a0 + a1) / 2) >= 0:
            ring_wall_seg(walls, walls, cx, cy, r + 0.05, r + 0.85, a0, a1, 1.05, ztop, "reactor_shell")
        else:
            ring_wall_seg(front, front, cx, cy, r + 0.05, r + 0.85, a0, a1, 1.05, ztop, "reactor_shell")
    # socle des coins
    x, y, w, h = b["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if tile(xx, yy) != 3:
                continue
            continue
    # nervures et hublots de la coque (dans front pour la moitié sud)
    for i in range(16):
        a = i / 16 * math.tau
        if openings_mask(rcx, rcy, r, a) or openings_mask(rcx, rcy, r, a + 0.12) or openings_mask(rcx, rcy, r, a - 0.12):
            continue
        tgt = front if math.sin(a) < 0 else walls
        tgt.box(cx + math.cos(a) * (r + 0.85) - 0.09, cy + math.sin(a) * (r + 0.85) - 0.09, -0.5,
                cx + math.cos(a) * (r + 0.85) + 0.09, cy + math.sin(a) * (r + 0.85) + 0.09, ztop + 0.05, "metal_dark")
        if not openings_mask(rcx, rcy, r, a + math.pi / 16):
            a2 = a + math.pi / 16
            for (z0, z1) in ((1.3, 1.75), (2.25, 2.7)):
                tgt2 = front if math.sin(a2) < 0 else walls
                tgt2.box(cx + math.cos(a2) * (r + 0.88) - 0.18, cy + math.sin(a2) * (r + 0.88) - 0.18, z0,
                         cx + math.cos(a2) * (r + 0.88) + 0.18, cy + math.sin(a2) * (r + 0.88) + 0.18, z1,
                         "window" if (i + int(z0)) % 3 else "neon_cyan")
    for zz in (0.95, 2.0):
        for i in range(seg):
            a0 = i / seg * math.tau
            a1 = (i + 1) / seg * math.tau
            if zz < 1.0 and openings_mask(rcx, rcy, r, (a0 + a1) / 2):
                continue
            tgt = front if math.sin((a0 + a1) / 2) < 0 else walls
            tgt.seg((cx + math.cos(a0) * (r + 0.9), cy + math.sin(a0) * (r + 0.9), zz),
                    (cx + math.cos(a1) * (r + 0.9), cy + math.sin(a1) * (r + 0.9), zz), 0.06, "metal_mid", 5)
    walls.to_object("walls_%d" % bid, "world")
    front.to_object("front_%d" % bid, "roofs")
    # calotte : couronne plate + anneau lumineux + gradins concentriques chargés de machinerie
    # (caissons, conduites radiales, trappes), hublot central sur le cœur bleu, mât et balises
    R = r + 0.9
    roof.cyl(cx, cy, ztop, ztop + 0.18, R, "reactor_shell", 64)
    for i in range(48):
        a0 = i / 48 * math.tau
        a1 = (i + 1) / 48 * math.tau
        ra, rb = R * 0.9, R * 0.95
        roof.poly([(cx + math.cos(a0) * ra, cy + math.sin(a0) * ra, ztop + 0.19), (cx + math.cos(a1) * ra, cy + math.sin(a1) * ra, ztop + 0.19),
                   (cx + math.cos(a1) * rb, cy + math.sin(a1) * rb, ztop + 0.19), (cx + math.cos(a0) * rb, cy + math.sin(a0) * rb, ztop + 0.19)], "neon_cyan")
    tiers = [(0.86, 0.18, 0.36), (0.66, 0.36, 0.58), (0.44, 0.58, 0.8)]
    for (k, z0, z1) in tiers:
        roof.cyl(cx, cy, ztop + z0, ztop + z1, R * k, "reactor_shell" if k < 0.8 else "roof_dark", 48)
    # caissons et conduites sur la première couronne
    for i in range(10):
        a = i / 10 * math.tau + rng.uniform(-0.1, 0.1)
        d = R * 0.76
        px, py = cx + math.cos(a) * d, cy + math.sin(a) * d
        if i % 3 == 0:
            roof.cyl(px, py, ztop + 0.36, ztop + 0.7, 0.48, rng.choice(["white_panel", "metal_mid"]), 16)
            roof.cyl(px, py, ztop + 0.7, ztop + 0.72, 0.38, "metal_dark", 16)
        else:
            roof.box(px - 0.5, py - 0.38, ztop + 0.36, px + 0.5, py + 0.38, ztop + 0.68, rng.choice(["metal_mid", "hull_dark", "white_panel"]))
            roof.box(px - 0.32, py - 0.18, ztop + 0.68, px + 0.32, py + 0.18, ztop + 0.7, rng.choice(["neon_orange", "screen_cyan", "metal_dark"]))
    for i in range(8):
        a = (i + 0.5) / 8 * math.tau
        roof.seg((cx + math.cos(a) * R * 0.42, cy + math.sin(a) * R * 0.42, ztop + 0.62), (cx + math.cos(a) * R * 0.86, cy + math.sin(a) * R * 0.86, ztop + 0.42),
                 0.07, rng.choice(["metal", "cable_yellow", "metal"]), 6)
    # hublot central : cœur bleu sous un verre nervuré
    roof.cyl(cx, cy, ztop + 0.8, ztop + 0.84, R * 0.34, "core", 32)
    roof.cyl(cx, cy, ztop + 0.84, ztop + 0.86, R * 0.36, "glass", 32)
    for i in range(6):
        a = i / 6 * math.tau
        roof.seg((cx, cy, ztop + 0.87), (cx + math.cos(a) * R * 0.35, cy + math.sin(a) * R * 0.35, ztop + 0.87), 0.05, "metal_mid", 5)
    roof.cyl(cx, cy, ztop + 0.86, ztop + 1.0, 0.35, "metal_mid", 16)
    roof.cyl(cx + R * 0.5, cy + R * 0.3, ztop + 0.58, ztop + 1.8, 0.05, "metal", 6)
    roof.sphere(cx + R * 0.5, cy + R * 0.3, ztop + 1.82, 0.1, "neon_red", 1)


def build_tube(b, roof, rng):
    """Tube de liaison : cylindre couché le long de la diagonale (toit), anneaux nervurés."""
    t = TUBE_BLD[b["id"]]
    (fx, fy), (tx, ty) = t["from"], t["to"]
    # prolonge jusqu'au mur de la salle rouge (porte) et jusqu'à la coque du réacteur
    dxv, dyv = tx - fx, ty - fy
    Lg = math.hypot(dxv, dyv)
    ux, uy = dxv / Lg, dyv / Lg
    p0 = (fx - ux * 0.6, -(fy - uy * 0.6), 0.9)
    p1 = (tx + ux * 0.6, -(ty + uy * 0.6), 0.9)
    roof.seg(p0, p1, 2.1, "reactor_shell", 32)
    n = max(2, int((Lg + 1.2) / 1.6))
    for k in range(n + 1):
        f = k / max(n, 1)
        px = p0[0] + (p1[0] - p0[0]) * f
        py = p0[1] + (p1[1] - p0[1]) * f
        q0 = (px - ux * 0.08, py + uy * 0.08, 0.9)
        q1 = (px + ux * 0.08, py - uy * 0.08, 0.9)
        roof.seg(q0, q1, 2.18, "metal_mid", 32)
    for k in range(3):
        f = (k + 0.5) / 3
        px = p0[0] + (p1[0] - p0[0]) * f
        py = p0[1] + (p1[1] - p0[1]) * f
        roof.box(px - 0.25, py - 0.25, 2.65, px + 0.25, py + 0.25, 2.8, "window")

# ======================================================================= décors (prop_spawns)
def _rect_of_spawn(s):
    sx, sy = s.get("size", [1, 1])
    x0 = s["cell"][0] - (sx - 1) // 2
    return [x0, s["cell"][1] - sy + 1, sx, sy]


def _cells_of(rect):
    x, y, w, h = rect
    return [(xx, yy) for yy in range(y, y + h) for xx in range(x, x + w)]


class Local:
    """Repère local d'un décor adossé : u le long du mur (centré), v depuis le mur (0) vers la
    salle, z vers le haut. Rotations multiples de 90° → boîtes alignées."""

    def __init__(self, rect, back):
        x, y, w, h = rect
        self.x0, self.x1, self.y0, self.y1 = x, x + w, y, y + h     # cases (y vers le bas)
        self.back = back
        if back in ("N", "S"):
            self.A, self.D = w, h
        else:
            self.A, self.D = h, w

    def p(self, u, v):
        """(u, v) → (X, Yblender)."""
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
        """Cylindre couché le long de u."""
        ax, ay = self.p(u0, v)
        bx, by = self.p(u1, v)
        mb.seg((ax, ay, z), (bx, by, z), r, mat, seg)

    def sph(self, mb, u, v, z, r, mat, sub=1):
        x, y = self.p(u, v)
        mb.sphere(x, y, z, r, mat, sub)


def back_side(rect):
    """Côté du mur le plus proche (adossement) : N, S, E ou W ; N par défaut (face caméra)."""
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


CRATES = ["crate_orange", "crate_yellow", "crate_grey", "crate_teal", "crate_orange", "crate_grey"]


def crate(mb, L, u, v, s, z, rng, mat=None):
    """Caisse de fret : corps peint, cadre métallique aux arêtes, sangle, couvercle, étiquette."""
    mat = mat or rng.choice(CRATES)
    hgt = s * rng.uniform(0.7, 0.9)
    L.box(mb, u - s / 2, v, z, u + s / 2, v + s, z + hgt, mat)
    e = max(0.03, s * 0.07)
    for (a0, b0) in ((u - s / 2, v), (u + s / 2 - e, v), (u - s / 2, v + s - e), (u + s / 2 - e, v + s - e)):
        L.box(mb, a0 - 0.005, b0 - 0.005, z, a0 + e + 0.005, b0 + e + 0.005, z + hgt + 0.005, "metal_dark")
    for (a0, b0, a1, b1) in ((u - s / 2, v, u + s / 2, v + e), (u - s / 2, v + s - e, u + s / 2, v + s),
                             (u - s / 2, v, u - s / 2 + e, v + s), (u + s / 2 - e, v, u + s / 2, v + s)):
        L.box(mb, a0 - 0.005, b0 - 0.005, z + hgt - e, a1 + 0.005, b1 + 0.005, z + hgt + 0.012, "metal_dark")
    L.box(mb, u - s / 2 - 0.01, v + s * 0.45, z, u + s / 2 + 0.01, v + s * 0.55, z + hgt + 0.012, "metal_mid")
    if rng.random() < 0.5:
        L.box(mb, u - s * 0.2, v + s + 0.001, z + hgt * 0.35, u + s * 0.2, v + s + 0.012, z + hgt * 0.65,
              rng.choice(["hazard", "white_panel", "screen_orange"]))


def prop(mb, kind, L, rng):
    A, D = L.A, L.D
    a = A / 2 - 0.06
    d = D - 0.08
    k = kind
    if k in ("console", "desk_station"):
        L.box(mb, -a, 0.05, 0.0, a, min(d, 0.62), 0.5, "metal_mid")
        L.box(mb, -a, 0.05, 0.5, a, min(d, 0.62), 0.56, "metal_dark")
        L.box(mb, -a + 0.06, 0.1, 0.56, a - 0.06, min(d, 0.55), 0.58, rng.choice(["screen_cyan", "screen_green", "screen_cyan", "screen_orange"]))
        n = max(1, int(A / 0.7))
        for i in range(n):
            u = -a + (i + 0.5) * (2 * a / n)
            L.box(mb, u - 0.26, 0.05, 0.58, u + 0.26, 0.12, 0.98, "metal_dark")
            L.box(mb, u - 0.22, 0.12, 0.62, u + 0.22, 0.13, 0.94, rng.choice(["screen_cyan", "screen_cyan", "screen_green", "screen_red"]))
        if k == "desk_station" and D > 1.2:
            L.cyl(mb, 0.0, min(d, 1.3), 0.0, 0.45, 0.22, "metal_dark", 10)
    elif k == "server_rack":
        L.box(mb, -a, 0.03, 0.0, a, d * 0.9, 1.05, "metal_dark")
        for j in range(6):
            z = 0.12 + j * 0.15
            L.box(mb, -a + 0.06, d * 0.9, z, a - 0.06, d * 0.9 + 0.01, z + 0.03, rng.choice(["neon_green", "neon_cyan", "neon_blue", "metal_mid"]))
    elif k in ("bunk_bed",):
        L.box(mb, -a, 0.02, 0.0, a, d, 0.12, "metal_dark")
        L.box(mb, -a + 0.03, 0.05, 0.12, a - 0.03, d - 0.03, 0.26, "mattress")
        L.box(mb, -a + 0.06, 0.08, 0.26, -a + 0.3, d - 0.08, 0.32, "sheet")
        for (pu, pv) in ((-a, 0.02), (a - 0.06, 0.02), (-a, d - 0.06), (a - 0.06, d - 0.06)):
            L.box(mb, pu, pv, 0.0, pu + 0.06, pv + 0.06, 0.95, "metal")
        L.box(mb, -a, 0.02, 0.62, a, d, 0.7, "metal_dark")
        L.box(mb, -a + 0.03, 0.05, 0.7, a - 0.03, d - 0.03, 0.82, "mattress")
    elif k in ("med_bed", "bio_bed"):
        L.box(mb, -a, 0.05, 0.0, a, d, 0.35, "white_panel")
        L.box(mb, -a + 0.04, 0.08, 0.35, a - 0.04, d - 0.04, 0.45, "sheet")
        L.box(mb, -a + 0.05, 0.08, 0.45, -a + 0.35, d - 0.08, 0.52, "sheet")
        L.cyl(mb, a - 0.12, 0.12, 0.0, 0.95, 0.03, "metal", 6)
        L.box(mb, a - 0.3, 0.1, 0.8, a, 0.16, 1.0, "screen_green")
        if k == "bio_bed":
            L.box(mb, -a, 0.05, 0.45, a, d, 0.9, "glass_tank")
    elif k in ("mess_table", "crew_table"):
        L.box(mb, -a + 0.1, 0.2, 0.4, a - 0.1, d - 0.2, 0.46, "crate_grey")
        L.box(mb, -a + 0.2, d / 2 - 0.08, 0.46, a - 0.2, d / 2 + 0.08, 0.47, "metal_dark")
        L.box(mb, -0.12, d / 2 - 0.12, 0.0, 0.12, d / 2 + 0.12, 0.4, "metal_dark")
        L.box(mb, -a + 0.15, 0.02, 0.0, a - 0.15, 0.2, 0.26, "metal_mid")
        L.box(mb, -a + 0.15, d - 0.2, 0.0, a - 0.15, d, 0.26, "metal_mid")
        for i in range(int(A)):
            u = -a + 0.4 + i * (2 * a - 0.8) / max(int(A) - 1, 1)
            L.box(mb, u - 0.12, d / 2 - 0.3, 0.46, u + 0.12, d / 2 - 0.1, 0.48, "metal")
    elif k == "lab_bench":
        L.box(mb, -a, 0.03, 0.0, a, min(d, 0.6), 0.48, "white_panel")
        L.box(mb, -a, 0.03, 0.48, a, min(d, 0.6), 0.52, "metal_dark")
        for i in range(3):
            u = -a + 0.2 + i * (2 * a - 0.4) / 2
            L.cyl(mb, u, 0.3, 0.52, 0.7, 0.06, "fluid" if i % 2 == 0 else "glass_tank", 8)
        L.box(mb, -0.25, 0.04, 0.52, 0.25, 0.1, 0.85, "screen_cyan")
    elif k == "specimen_tank":
        r = min(A, D) / 2 - 0.08
        L.cyl(mb, 0.0, D / 2, 0.0, 0.12, r, "metal_mid", 16)
        L.cyl(mb, 0.0, D / 2, 0.12, 0.95, r * 0.8, "fluid", 16)
        L.cyl(mb, 0.0, D / 2, 0.12, 0.95, r * 0.9, "glass_tank", 16)
        L.cyl(mb, 0.0, D / 2, 0.95, 1.05, r, "metal_mid", 16)
    elif k in ("cargo_stack", "crate_pallet"):
        if k == "crate_pallet":
            L.box(mb, -a, 0.04, 0.0, a, d, 0.08, "crate_yellow")
            z0 = 0.08
        else:
            z0 = 0.0
        n = max(1, int(round(A)))
        for i in range(n):
            u = -a + (i + 0.5) * (2 * a / n)
            s = min(2 * a / n, d) * rng.uniform(0.8, 0.95)
            crate(mb, L, u, 0.06, s, z0, rng)
            if rng.random() < 0.55:
                crate(mb, L, u + rng.uniform(-0.05, 0.05), 0.1, s * 0.85, z0 + s * 0.87, rng)
    elif k == "pipe_cluster":
        n = rng.randint(3, 5)
        for i in range(n):
            u = -a + (i + 0.5) * (2 * a / n)
            L.cyl(mb, u, 0.15 + (i % 2) * 0.15, 0.0, 1.1, rng.uniform(0.07, 0.12), rng.choice(["metal", "metal_mid", "cable_yellow"]), 10)
        L.box(mb, -a, 0.05, 0.6, a, 0.35, 0.7, "metal_dark")
        L.cyl(mb, 0.0, 0.42, 0.45, 0.5, 0.12, "cable_red", 10)
    elif k == "reactor_core":
        cx_, cy_ = 0.0, D / 2
        r = min(A, D) / 2 - 0.05
        L.cyl(mb, cx_, cy_, 0.0, 0.18, r, "metal_dark", 24)
        L.cyl(mb, cx_, cy_, 0.18, 1.5, r * 0.55, "core", 24)
        for z in (0.35, 0.75, 1.15):
            L.cyl(mb, cx_, cy_, z, z + 0.08, r * 0.75, "metal_mid", 24)
        L.cyl(mb, cx_, cy_, 1.5, 1.65, r * 0.7, "metal_dark", 24)
    elif k == "holo_table":
        L.cyl(mb, 0.0, D / 2, 0.0, 0.42, min(A, D) / 2 - 0.08, "metal_dark", 20)
        L.cyl(mb, 0.0, D / 2, 0.42, 0.45, min(A, D) / 2 - 0.12, "holo", 20)
        L.sph(mb, 0.0, D / 2, 0.75, 0.22, "holo", 2)
    elif k in ("captain_chair", "ss_chair"):
        L.cyl(mb, 0.0, D / 2, 0.0, 0.3, 0.06, "metal_dark", 8)
        L.box(mb, -0.25, D / 2 - 0.22, 0.3, 0.25, D / 2 + 0.22, 0.4, "mattress" if k == "captain_chair" else "metal_mid")
        L.box(mb, -0.25, D / 2 - 0.3, 0.4, 0.25, D / 2 - 0.2, 0.85, "mattress" if k == "captain_chair" else "metal_mid")
    elif k == "weapon_rack":
        L.box(mb, -a, 0.02, 0.0, a, 0.25, 1.05, "metal_dark")
        n = max(2, int(A / 0.35))
        for i in range(n):
            u = -a + (i + 0.5) * (2 * a / n)
            L.box(mb, u - 0.05, 0.25, 0.15, u + 0.05, 0.33, 0.95, "rubber")
        L.box(mb, -a, 0.24, 1.0, a, 0.27, 1.03, "neon_red")
    elif k in ("plant_bed", "ss_planter"):
        L.box(mb, -a, 0.05, 0.0, a, d, 0.32, "white_panel")
        L.box(mb, -a + 0.05, 0.1, 0.32, a - 0.05, d - 0.05, 0.34, "soil")
        n = max(2, int(A * 2.5))
        for i in range(n):
            u = rng.uniform(-a + 0.15, a - 0.15)
            v = rng.uniform(0.2, d - 0.15)
            L.sph(mb, u, v, 0.42, rng.uniform(0.12, 0.22), "plant", 1)
        L.box(mb, -a, 0.05, 0.9, a, 0.12, 0.94, "lamp_white")
    elif k == "vending_machine":
        L.box(mb, -a, 0.03, 0.0, a, min(d, 0.7), 1.1, "metal_mid")
        L.box(mb, -a + 0.08, min(d, 0.7), 0.35, a - 0.08, min(d, 0.7) + 0.01, 1.0, rng.choice(["screen_cyan", "screen_orange", "window_warm"]))
    elif k == "coolant_tank":
        r = min(A, D) / 2 - 0.08
        L.cyl(mb, 0.0, D / 2, 0.0, 1.05, r, "white_panel", 18)
        for z in (0.2, 0.55, 0.9):
            L.cyl(mb, 0.0, D / 2, z, z + 0.05, r + 0.02, "metal_dark", 18)
        L.cyl(mb, 0.0, D / 2, 1.05, 1.1, r * 0.4, "neon_cyan", 12)
    elif k == "power_node":
        L.box(mb, -a, 0.03, 0.0, a, min(d, 0.6), 0.85, "hull_dark")
        for j in range(3):
            L.box(mb, -a + 0.08, min(d, 0.6), 0.15 + j * 0.22, a - 0.08, min(d, 0.6) + 0.01, 0.2 + j * 0.22, "neon_orange")
        L.box(mb, -a + 0.05, 0.05, 0.85, a - 0.05, 0.5, 0.88, "hazard")
    elif k == "escape_pod":
        r = min(D, 1.0) / 2 - 0.06
        L.hcyl(mb, -a + r, a - r, r + 0.05, r + 0.05, r, "white_panel", 16)
        L.sph(mb, -a + r, r + 0.05, r + 0.05, r, "white_panel", 2)
        L.sph(mb, a - r, r + 0.05, r + 0.05, r, "white_panel", 2)
        L.box(mb, -0.25, r * 2, r * 0.9, 0.25, r * 2 + 0.06, r * 1.6, "window")
        L.box(mb, -a + 0.1, r + 0.04, r * 2, a - 0.1, r + 0.06, r * 2 + 0.06, "hazard")
    elif k == "floor_cables":
        for i in range(3):
            c = rng.choice(["cable", "cable_red", "cable_yellow"])
            u0 = rng.uniform(-a, a)
            u1 = rng.uniform(-a, a)
            ax, ay = L.p(u0, 0.1)
            bx, by = L.p(u1, d)
            mb.seg((ax, ay, 0.03), (bx, by, 0.03), 0.03, c, 5)
    elif k == "warning_beacon":
        L.cyl(mb, 0.0, 0.25, 0.0, 0.7, 0.06, "metal_dark", 8)
        L.box(mb, -0.15, 0.12, 0.0, 0.15, 0.38, 0.06, "hazard")
        L.sph(mb, 0.0, 0.25, 0.78, 0.1, "neon_orange", 1)
    elif k == "shuttle":
        shuttle(mb, L, rng)
    elif k == "workbench":
        L.box(mb, -a, 0.03, 0.45, a, min(d, 0.65), 0.52, "metal_mid")
        for pu in (-a + 0.05, a - 0.1):
            L.box(mb, pu, 0.05, 0.0, pu + 0.05, min(d, 0.6), 0.45, "metal_dark")
        L.box(mb, -a, 0.02, 0.52, a, 0.08, 1.0, "metal_dark")
        for i in range(4):
            u = rng.uniform(-a + 0.1, a - 0.2)
            L.box(mb, u, 0.15, 0.52, u + rng.uniform(0.08, 0.25), 0.15 + rng.uniform(0.05, 0.2), 0.52 + rng.uniform(0.03, 0.12), rng.choice(["cable_red", "metal", "crate_orange"]))
    elif k == "fuel_drums":
        n = max(2, int(A * 2))
        for i in range(n):
            u = -a + 0.2 + i * (2 * a - 0.4) / max(n - 1, 1)
            v = rng.uniform(0.2, max(0.25, d - 0.25))
            L.cyl(mb, u, v, 0.0, 0.6, 0.18, rng.choice(["fuel_red", "crate_yellow", "crate_teal"]), 12)
            L.cyl(mb, u, v, 0.6, 0.62, 0.14, "metal_dark", 12)
    elif k in ("locker_bank", "med_cabinet_wall", "tool_wall", "supply_shelf"):
        dep = min(d, 0.45)
        mat = {"locker_bank": "metal_mid", "med_cabinet_wall": "white_panel", "tool_wall": "metal_dark", "supply_shelf": "metal_dark"}[k]
        L.box(mb, -a, 0.02, 0.0, a, dep, 1.05, mat)
        if k == "locker_bank":
            n = max(2, int(A / 0.38))
            for i in range(n):
                u = -a + i * (2 * a / n)
                L.box(mb, u + 0.01, dep, 0.05, u + 2 * a / n - 0.01, dep + 0.01, 1.0, "crate_grey" if i % 2 else "metal_mid")
        elif k == "med_cabinet_wall":
            L.box(mb, -0.08, dep, 0.65, 0.08, dep + 0.01, 0.95, "neon_red")
            L.box(mb, -0.2, dep, 0.74, 0.2, dep + 0.01, 0.86, "neon_red")
        elif k == "supply_shelf":
            for z in (0.3, 0.65, 0.98):
                L.box(mb, -a, 0.02, z, a, dep, z + 0.03, "metal_mid")
                for i in range(int(A * 2)):
                    u = -a + 0.1 + i * 0.5
                    if u < a - 0.2:
                        L.box(mb, u, 0.05, z + 0.03, u + 0.3, dep - 0.05, z + 0.22, rng.choice(CRATES))
        else:
            for i in range(5):
                u = rng.uniform(-a + 0.1, a - 0.2)
                L.box(mb, u, dep, 0.4, u + 0.06, dep + 0.04, 0.8, rng.choice(["cable_red", "metal", "cable_yellow"]))
    else:
        crate(mb, L, 0.0, 0.08, min(A, D) * 0.8, 0.0, rng)


def shuttle(mb, L, rng):
    """Navette du hangar (empreinte 5×3) : fuselage blanc, cockpit vitré, ailes, réacteurs."""
    a = L.A / 2 - 0.1
    d = L.D
    vc = d / 2
    L.box(mb, -a + 0.4, vc - 0.7, 0.15, a - 0.6, vc + 0.7, 0.95, "white_panel")
    L.box(mb, -a + 0.4, vc - 0.55, 0.95, a - 1.0, vc + 0.55, 1.15, "white_panel")
    L.box(mb, a - 0.6, vc - 0.5, 0.25, a, vc + 0.5, 0.8, "white_panel")
    L.box(mb, a - 0.95, vc - 0.45, 0.8, a - 0.25, vc + 0.45, 1.02, "window")
    L.box(mb, -a + 0.8, 0.05, 0.3, a - 1.6, vc - 0.7, 0.42, "metal_mid")
    L.box(mb, -a + 0.8, vc + 0.7, 0.3, a - 1.6, d - 0.05, 0.42, "metal_mid")
    for vv in (vc - 0.35, vc + 0.35):
        L.hcyl(mb, -a, -a + 0.5, vv, 0.55, 0.25, "metal_dark", 12)
        L.hcyl(mb, -a - 0.02, -a + 0.05, vv, 0.55, 0.2, "engine", 12)
    L.box(mb, -a + 1.0, vc - 0.72, 0.6, a - 1.2, vc - 0.7, 0.68, "hazard")
    for (u, v) in ((-a + 0.9, 0.3), (a - 1.0, 0.3), (-a + 0.9, d - 0.3), (a - 1.0, d - 0.3)):
        L.cyl(mb, u, v, 0.0, 0.3, 0.06, "metal_dark", 6)


def build_props():
    groups = {}
    for p in LAYOUT.get("prop_spawns", []):
        rect = _rect_of_spawn(p)
        bid = None
        for (cx_, cy_) in [(rect[0], rect[1])]:
            bid = CELL_BLD.get((cx_, cy_))
        name = ("furn_%d" % bid) if bid is not None else "props"
        mb = groups.setdefault(name, MB())
        rng = random.Random(hash((p["cell"][0], p["cell"][1], p["kind"])) & 0xffffff)
        back = back_side(rect) if p["kind"] not in ("shuttle", "reactor_core", "holo_table", "mess_table", "crew_table") else "N"
        if p["kind"] == "shuttle":
            back = "N"
        Lc = Local(rect, back)
        st = len(mb.V)
        prop(mb, p["kind"], Lc, rng)
        cells_fit(mb, st, rect, margin=0.05)
    for name, mb in groups.items():
        mb.to_object(name, "world")


# Fouillis par rôle (rendu seulement ; compose.py en fait des collisions « emprise rendue » en
# gardant tous les passages) : petits objets adossés aux murs, dans une case libre.
CLUTTER = {
    "storage": ["crates", "crates", "drums", "shelf"], "cargo_hold": ["crates", "crates", "crates", "drums"],
    "workshop": ["bench", "crates", "toolbox", "drums"], "quarters": ["locker", "locker", "cabinet", "crates"],
    "mess_hall": ["cabinet", "crates", "vending"], "lab": ["cabinet", "console", "tank"], "infirmary": ["cabinet", "console"],
    "server_room": ["rack", "rack", "console"], "hydroponics": ["planter", "planter", "crates"], "closet": ["crates", "locker"],
    "hangar": ["crates", "crates", "drums"], "pod_bay": ["locker", "crates"], "airlock": ["locker", "crates"],
    "reactor_pod": ["pipes", "drums", "console"], "control_center": [], "hall": ["crates", "crates", "drums"],
    "lab_vault": ["tank", "cabinet"], "armory": ["locker", "crates"], "elevator": [], "corridor": ["crates", "pipes"],
}
CLUTTER_P = {"corridor": 0.06, "hall": 0.12, "hangar": 0.2}
CLUTTER_CELLS = []


def clutter_item(mb, kind, L, rng):
    a = L.A / 2 - 0.1
    if kind == "crates":
        s = rng.uniform(0.55, 0.78)
        crate(mb, L, rng.uniform(-0.05, 0.05), 0.06, s, 0.0, rng)
        if rng.random() < 0.5:
            crate(mb, L, rng.uniform(-0.06, 0.06), 0.1, s * 0.8, s * 0.86, rng)
    elif kind == "drums":
        for i in range(rng.randint(1, 2)):
            L.cyl(mb, rng.uniform(-0.2, 0.2), rng.uniform(0.25, 0.5), 0.0, 0.62, 0.2, rng.choice(["fuel_red", "crate_yellow", "crate_teal"]), 12)
    elif kind == "locker":
        L.box(mb, -a, 0.03, 0.0, a, 0.42, 1.0, rng.choice(["metal_mid", "crate_grey", "crate_teal"]))
        L.box(mb, -0.02, 0.42, 0.1, 0.02, 0.43, 0.95, "metal_dark")
        L.box(mb, -a + 0.1, 0.42, 0.8, -a + 0.3, 0.43, 0.88, "neon_green")
    elif kind == "cabinet":
        L.box(mb, -a, 0.03, 0.0, a, 0.45, 0.72, rng.choice(["white_panel", "metal_mid"]))
        L.box(mb, -a, 0.03, 0.72, a, 0.45, 0.76, "metal_dark")
        if rng.random() < 0.5:
            L.box(mb, -0.2, 0.1, 0.76, 0.2, 0.18, 1.0, rng.choice(["screen_cyan", "screen_green"]))
    elif kind == "console":
        prop(mb, "console", L, rng)
    elif kind == "rack":
        prop(mb, "server_rack", L, rng)
    elif kind == "vending":
        prop(mb, "vending_machine", L, rng)
    elif kind == "tank":
        prop(mb, "specimen_tank", L, rng)
    elif kind == "planter":
        prop(mb, "plant_bed", L, rng)
    elif kind == "bench":
        prop(mb, "workbench", L, rng)
    elif kind == "toolbox":
        L.box(mb, -0.3, 0.1, 0.0, 0.3, 0.45, 0.3, "fuel_red")
        L.box(mb, -0.2, 0.2, 0.3, 0.2, 0.35, 0.36, "metal_dark")
    elif kind == "shelf":
        prop(mb, "supply_shelf", L, rng)
    elif kind == "pipes":
        prop(mb, "pipe_cluster", L, rng)


def _keeps_ring(c, blocked):
    """Poser un obstacle en c garde connexes les cases praticables libres de l'anneau 3×3
    (même règle que le peuplement) : pas de cul-de-sac créé par le fouillis."""
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
            for q in [tuple(c) for c in [[x_, y_] for x_, y_ in _cells_of(_rect_of_spawn(sp))]]:
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
    mb = MB()
    for y in range(H):
        for x in range(W):
            if tile(x, y) != 2 or (x, y) in protect or (x, y) in LOWG:
                continue
            rid = CELL_ROOM.get((x, y), -1)
            role = role_of(rid)
            kinds = CLUTTER.get(role, [])
            if not kinds:
                continue
            walls = [sd for sd, dx, dy in SIDES if tile(x + dx, y + dy) == 3]
            if not walls or len(walls) > 2:
                continue
            rng = random.Random(x * 9176 + y * 131 + SEED * 7)
            if rng.random() > CLUTTER_P.get(role, 0.6):
                continue
            if not _keeps_ring((x, y), blocked):
                continue
            blocked.add((x, y))
            back = "N" if "N" in walls else walls[0]
            Lc = Local([x, y, 1, 1], back)
            st = len(mb.V)
            clutter_item(mb, rng.choice(kinds), Lc, rng)
            cells_fit(mb, st, [x, y, 1, 1], margin=0.06)
            CLUTTER_CELLS.append((x, y))
    # groupes de caisses / fûts au milieu des places (hors axe de la coursive et des ouvertures)
    for r in ROOMS:
        if role_of(r["id"]) != "hall":
            continue
        x, y, w, h = r["rect"]
        rng = random.Random(r["id"] * 977 + SEED)
        n = max(2, int(w * h / 45))
        tries = 0
        placed = 0
        while placed < n and tries < 200:
            tries += 1
            cx = rng.randint(x + 1, x + w - 3)
            cy = rng.randint(y + 1, y + h - 3)
            cells = [(cx, cy), (cx + 1, cy), (cx, cy + 1), (cx + 1, cy + 1)]
            if any(28 <= c[0] <= 35 for c in cells):
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
                clutter_item(mb, "crates" if k < 0.75 else "drums", Lc, rng)
                cells_fit(mb, st, [qx, qy, 1, 1], margin=0.06)
                CLUTTER_CELLS.append((qx, qy))
            placed += 1
    mb.to_object("clutter", "world")


def decal(mb, cx, cy, s, mat):
    mb.poly([(cx - s / 2, Y(cy + s / 2), 0.004), (cx + s / 2, Y(cy + s / 2), 0.004), (cx + s / 2, Y(cy - s / 2), 0.004),
             (cx - s / 2, Y(cy - s / 2), 0.004)], mat, [(0, 0), (1, 0), (1, 1), (0, 1)])


def build_floor_details():
    """Détails au sol non bloquants (z < 0,05) : câbles, taches, grilles d'aération, papiers ;
    débris flottants et brûlures dans les modules endommagés (au-dessus de 1 case : hors emprise)."""
    det = MB()
    deb = MB()
    for sp in LAYOUT.get("decor_spawns", []):
        x, y = sp["cell"]
        off = sp.get("off", [0, 0])
        cx, cy = x + 0.5 + off[0] / 64.0, y + 0.5 + off[1] / 64.0
        rng = random.Random(x * 31 + y * 977 + SEED)
        k = sp["kind"]
        s = 0.25 + 0.2 * rng.random()
        if "cable" in k:
            det.seg((cx - 0.4, Y(cy - 0.2), 0.02), (cx + 0.4, Y(cy + 0.15), 0.02), 0.025, rng.choice(["cable", "cable_red", "cable_yellow"]), 5)
        elif "oil" in k or "stain" in k or "scorch" in k:
            decal(det, cx, cy, s * 1.6, "oil")
        else:
            det.box(cx - s * 0.5, Y(cy + s * 0.35), 0.0, cx + s * 0.5, Y(cy - s * 0.35), 0.006, rng.choice(["metal_dark", "white_panel", "crate_grey"]))
    for y in range(H):
        for x in range(W):
            if not walk(x, y) or (x, y) in GAME_CELLS:
                continue
            rng = random.Random(x * 7349 + y * 1663 + SEED * 3)
            rid = CELL_ROOM.get((x, y), -1)
            role = role_of(rid)
            if (x, y) in LOWG:
                if rng.random() < 0.12:
                    decal(det, x + rng.uniform(0.3, 0.7), y + rng.uniform(0.3, 0.7), rng.uniform(0.8, 1.8), "scorch")
                if rng.random() < 0.22:
                    zz = rng.uniform(1.05, 1.5)
                    sx, sy, sz = rng.uniform(0.08, 0.3), rng.uniform(0.08, 0.3), rng.uniform(0.05, 0.2)
                    deb.box(x + 0.5 - sx, Y(y + 0.5) - sy, zz, x + 0.5 + sx, Y(y + 0.5) + sy, zz + sz,
                            rng.choice(["metal_mid", "crate_orange", "white_panel", "metal_dark"]))
                if rng.random() < 0.05:
                    deb.sphere(x + rng.random(), Y(y + rng.random()), rng.uniform(1.05, 1.3), 0.035, "neon_orange", 1)
            elif role in ("corridor", "hall") and rng.random() < 0.04:
                det.seg((x + 0.1, Y(y + rng.random()), 0.02), (x + 0.9, Y(y + rng.random()), 0.02), 0.025,
                        rng.choice(["cable", "cable_red", "cable_yellow"]), 5)
            elif rng.random() < 0.035:
                # trappe de visite (bord jaune) ou grille d'aération au sol
                if rng.random() < 0.5:
                    det.box(x + 0.18, Y(y + 0.82), 0.0, x + 0.82, Y(y + 0.18), 0.008, "cable_yellow")
                    det.box(x + 0.24, Y(y + 0.76), 0.0, x + 0.76, Y(y + 0.24), 0.012, "metal_dark")
                else:
                    det.box(x + 0.15, Y(y + 0.7), 0.0, x + 0.85, Y(y + 0.3), 0.008, "metal_dark")
                    for j in range(4):
                        det.box(x + 0.2, Y(y + 0.36 + j * 0.09) - 0.02, 0.008, x + 0.8, Y(y + 0.36 + j * 0.09) + 0.02, 0.011, "rubber")
            if role == "hall" and (abs(x + 0.5 - 29.7) < 0.5 or abs(x + 0.5 - 34.3) < 0.5) and y % 2 == 0:
                det.box(x + 0.35, Y(y + 0.95), 0.0, x + 0.65, Y(y + 0.05), 0.009, "cable_yellow")
    det.to_object("_floordet", "world")
    deb.to_object("_debris", "world")


# ======================================================================= hors jeu : espace, Terre, décors
def build_space():
    tanT = math.tan(TILT)
    # fond étoilé (plan émissif très bas) couvrant tout le cadre
    z = -150.0
    sh = -z * tanT
    sp = MB()
    x0, x1 = -MARGIN - 30, W + MARGIN + 30
    r0, r1 = -MARGIN - 30, H + MARGIN + 30
    sp.poly([(x0, sh - r1, z), (x1, sh - r1, z), (x1, sh - r0, z), (x0, sh - r0, z)], "_stars",
            [(x0, sh - r1), (x1, sh - r1), (x1, sh - r0), (x0, sh - r0)])
    sp.to_object("_space", "world")
    # la Terre : disque à plat (rendu sphérique dans le shader), centre et rayon en cases écran
    ex, ey, er = [float(v) for v in os.environ.get("SS_EARTH", "35,39,41.5").split(",")]
    zE = -60.0
    mat_planet("_planet_mat", er)
    pm = MB()
    seg = 128
    k = 1.12
    pts = [(math.cos(i / seg * math.tau) * k, math.sin(i / seg * math.tau) * k, 0.0) for i in range(seg)]
    pm.poly(pts, "_planet_mat")
    ob = pm.to_object("_planet", "world")
    ob.scale = (er, er, 1.0)
    ob.location = (ex, -ey - zE * tanT, zE)


def truss(mb, p0, p1, r=0.06, mat="metal_mid", step=0.8):
    """Poutre treillis entre deux points (deux longerons + entretoises)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    Lg = d.length
    if Lg < 1e-3:
        return
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 1e-4:
        side = Vector((1, 0, 0))
    side = side.normalized() * 0.22
    a0, a1, b0, b1 = p0 + side, p1 + side, p0 - side, p1 - side
    mb.seg(a0, a1, r, mat, 6)
    mb.seg(b0, b1, r, mat, 6)
    n = max(1, int(Lg / step))
    for i in range(n + 1):
        f = i / n
        mb.seg(a0 + (a1 - a0) * f, b0 + (b1 - b0) * min(1.0, f + 0.5 / n), r * 0.6, mat, 4)


def solar_panel(mb, cx, cy, z, w, h, rot):
    """Panneau solaire plat (w × h cases) tourné de rot (degrés) autour de Z."""
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))

    def P(u, v, zz):
        return (cx + u * c - v * s, cy + u * s + v * c, zz)
    mb.poly([P(-w / 2, -h / 2, z), P(w / 2, -h / 2, z), P(w / 2, h / 2, z), P(-w / 2, h / 2, z)], "solar",
            [(0, 0), (w, 0), (w, h), (0, h)])
    mb.poly([P(-w / 2, h / 2, z - 0.06), P(w / 2, h / 2, z - 0.06), P(w / 2, -h / 2, z - 0.06), P(-w / 2, -h / 2, z - 0.06)], "metal_dark")
    for (u0, v0, u1, v1) in ((-w / 2, -h / 2, w / 2, -h / 2), (-w / 2, h / 2, w / 2, h / 2), (-w / 2, -h / 2, -w / 2, h / 2), (w / 2, -h / 2, w / 2, h / 2)):
        mb.seg(P(u0, v0, z), P(u1, v1, z), 0.05, "metal", 4)


def build_decor():
    """Antenne parabolique, panneaux solaires, mâts, navettes amarrées aux sas d'extraction :
    tout dans le vide (cases VOID), donc hors jeu."""
    mb = MB()
    for d in C.get("decor", []):
        k = d["kind"]
        px, py = d["pos"]
        sz = float(d.get("size", 4))
        rot = float(d.get("rot", 0.0))
        X, Yb = px, Y(py)
        if k == "dish":
            # pylône + bras vers la coque + parabole inclinée
            mb.cyl(X, Yb, -1.0, 2.2, 0.35, "metal_mid", 12)
            truss(mb, (X, Yb, 1.0), (X + 1.5, Y(4.6), 0.8))
            R = sz * 0.42
            ob_start = len(mb.V)
            mb.sphere(0, 0, 0, R, "white_panel", 3, 1.0, 1.0, 0.32)
            # garde la moitié basse (bol) : écrase les sommets supérieurs
            for i in range(ob_start, len(mb.V)):
                x_, y_, z_ = mb.V[i]
                if z_ > 0:
                    z_ = z_ * 0.15
                mb.V[i] = (x_, y_, z_)
            M = Matrix.Rotation(math.radians(35), 3, "X") @ Matrix.Rotation(math.radians(rot), 3, "Z")
            for i in range(ob_start, len(mb.V)):
                v = M @ Vector(mb.V[i])
                mb.V[i] = (v.x + X, v.y + Yb, v.z + 3.4)
            mb.seg((X, Yb, 3.4), (X - 0.3, Yb + 0.8, 5.3), 0.07, "metal", 6)
            mb.sphere(X - 0.3, Yb + 0.8, 5.35, 0.22, "metal_mid", 1)
            mb.cyl(X, Yb, 2.2, 3.2, 0.55, "metal_dark", 12)
        elif k == "solar_array":
            c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
            truss(mb, (X - c * sz * 0.5, Yb - s * sz * 0.5, 1.2), (X + c * sz * 0.5, Yb + s * sz * 0.5, 1.2), 0.08)
            truss(mb, (X - c * sz * 0.5, Yb - s * sz * 0.5, 1.2), (43.8, Y(8.0), 0.9), 0.07)
            for i in (-0.36, -0.12, 0.12, 0.36):
                for j in (-1, 1):
                    solar_panel(mb, X + c * sz * i - s * j * 2.4, Yb + s * sz * i + c * j * 2.4, 1.25, sz * 0.22, 4.2, rot)
        elif k == "solar_wing":
            hx = 10.5 if px < W / 2 else W - 10.5
            truss(mb, (X, Yb, 0.6), (hx, Yb, 0.6), 0.08)
            for j in (-1, 0, 1):
                solar_panel(mb, X, Yb + j * sz * 0.34, 0.65, 4.6, sz * 0.31, rot)
        elif k == "antenna":
            mb.cyl(X, Yb, 0.0, 2.6, 0.06, "metal", 6)
            for zz in (0.9, 1.6, 2.2):
                mb.box(X - 0.5, Yb - 0.03, zz, X + 0.5, Yb + 0.03, zz + 0.04, "metal")
            mb.sphere(X, Yb, 2.65, 0.1, "neon_red", 1)
    # navettes amarrées aux sas d'extraction
    for m in MODS:
        if m["role"] != "pod_bay":
            continue
        x, y, w, h = m["rect"]
        if m["slot"] == "sas_n":
            Lc = Local([x + w // 2 - 3, y - 4, 6, 4], "S")
        elif m["slot"] == "sas_w":
            Lc = Local([x - 4, y + h // 2 - 2, 4, 5], "E")
        else:
            Lc = Local([x + w, y + h // 2 - 2, 4, 5], "W")
        st = len(mb.V)
        shuttle(mb, Lc, random.Random(x + y))
        for i in range(st, len(mb.V)):
            x_, y_, z_ = mb.V[i]
            mb.V[i] = (x_, y_, z_ - 0.35)
    mb.to_object("_decor", "world")


# ======================================================================= lumières
def build_lights():
    n = 0
    for r in ROOMS:
        rid = r["id"]
        x, y, w, h = r["rect"]
        col, k = light_of(rid)
        bid = CELL_BLD.get((x + w // 2, y + h // 2))
        roofed = bid is not None
        z = 1.35 if roofed else 1.05
        role = role_of(rid)
        step = 7.5 if role in ("hall", "corridor") else 5.5
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
                c_ = NEON[col] if role not in ("hall", "corridor") else lrng.choice([(1.0, 0.78, 0.52), (1.0, 0.78, 0.52), (0.8, 0.9, 1.0)])
                L_.color = c_
                L_.energy = LIGHT_E * k * (1.0 + 0.15 * (w * h / (nx * ny)) / 16.0) * lrng.uniform(0.7, 1.2)
                L_.shape = "DISK"
                L_.size = 2.4 if role in ("hall", "corridor") else 1.8
                o = bpy.data.objects.new("l%d" % n, L_)
                o.location = (px, Y(py), z)
                scene.collection.objects.link(o)
                n += 1
    for (gx, gy, gc) in DOOR_GLOWS:
        L_ = bpy.data.lights.new("d%d" % n, "POINT")
        L_.color = NEON[gc]
        L_.energy = LIGHT_E * 0.25
        L_.shadow_soft_size = 0.2
        o = bpy.data.objects.new("d%d" % n, L_)
        o.location = (gx, gy, 0.9)
        scene.collection.objects.link(o)
        n += 1
    # cœurs de réacteur, dôme
    for m in MODS:
        if m.get("round") and m["role"] == "reactor_pod":
            cx, cy, rr = m["round"]
            L_ = bpy.data.lights.new("core%d" % n, "POINT")
            L_.color = (0.4, 0.7, 1.0)
            L_.energy = LIGHT_E * 3.0
            o = bpy.data.objects.new("core%d" % n, L_)
            o.location = (cx, Y(cy), 1.2)
            scene.collection.objects.link(o)
            n += 1
    print("  lights", n, flush=True)


LIGHT_E = float(os.environ.get("SS_LIGHT", "85"))


def build_world():
    build_floors()
    build_walls()
    build_hull()
    build_roofs()
    build_props()
    build_clutter()
    build_floor_details()
    build_space()
    build_decor()
    build_lights()


# ======================================================================= rendu
EXPOSURE = float(os.environ.get("SS_EXPOSURE", "-0.4"))
SUN_E = float(os.environ.get("SS_SUN", "1.5"))
SKY = float(os.environ.get("SS_SKY", "0.25"))
SAT = float(os.environ.get("SS_SAT", "1.18"))
CON = float(os.environ.get("SS_CON", "1.15"))
LIFT = float(os.environ.get("SS_LIFT", "4"))


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
    bg.inputs[0].default_value = (0.09, 0.11, 0.17, 1)
    bg.inputs[1].default_value = SKY
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = SUN_E
    sun.color = (1.0, 0.98, 0.95)
    sun.angle = math.radians(0.6)
    so = bpy.data.objects.new("sun", sun)
    sc.collection.objects.link(so)
    # soleil au nord-est, assez haut : ombres nettes vers le sud-ouest, faces sud à l'ombre
    d = Vector((-0.42, -0.5, -0.76)).normalized()
    so.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    # « lumière de Terre » : contre-jour bleuté venant du sud (planète sous la station), éclaire
    # les faces sud des modules (visibles depuis la caméra) comme sur la maquette
    es = bpy.data.lights.new("earthshine", "SUN")
    es.energy = float(os.environ.get("SS_EARTHSHINE", "1.4"))
    es.color = (0.45, 0.62, 1.0)
    es.angle = math.radians(8.0)
    eo = bpy.data.objects.new("earthshine", es)
    sc.collection.objects.link(eo)
    d2 = Vector((0.15, 0.8, -0.58)).normalized()
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
BLOOM = float(os.environ.get("SS_BLOOM", "0.55"))


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
            "projection": "ground_square", "margin": MARGIN, "biome": "space_station",
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
    if "gnd" in PASSES:
        # Sol seul (ground_pass.py) : murs, haut du mur sud et toit du module masqués à leur tour.
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import ground_pass
        frame(cam, -MARGIN, W + MARGIN, -MARGIN, H + MARGIN)

        def _gnd_hide(bid):
            names = {"%s_%d" % (p, bid) for p in ("walls", "roof", "front")}
            return [o for o in bpy.data.objects if o.name in names]
        dt = ground_pass.render_ground(bpy, scene, OUT, _gnd_hide, render, os.environ.get("GND_ONLY", ""))
        info["renders"]["ground_s"] = round(dt, 1)
        print("GND", round(dt, 1), "s", flush=True)
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
        only = os.environ.get("SS_INT_ONLY", "")
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
