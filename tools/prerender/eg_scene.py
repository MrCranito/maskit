"""Scène Blender complète de la surface des Pyramides d'Égypte (complexe de temples façon maquette
docs/reference/cartes_2.png, colonne de droite), construite depuis le layout JSON exporté par
tools/prerender/export_layout.gd (4e argument : res://data/worlds/world_06_egypt_pyramids.tres),
rendue en Cycles. Même pipeline, mêmes passes et même projection que fw_scene.py / mall_scene.py.

Usage (bpy en module) :
  python3 eg_scene.py <layout.json> <out_dir> [ppc=24] [samples=16] [passes=full,int] [margin=6]
Passes : full (par morceaux, reprise possible) ; int (patch « sans toit » par chambre à toit :
         toit et haut de la façade sud masqués) ; mask (emprise au sol, vue zénithale) ; occ
         (ids d'occultation) ; crop:x0;x1;y0;y1 ; view:x0;x1;y0;y1;tilt;ppc
Sorties : full.png, b<id>_in.png, mask.png, occ.png, render.json, layout.json (pour compose.py).

PROJECTION (identique à fw_scene.py) : caméra orthographique inclinée de TILT (38°) vers le nord,
  pixel_aspect_x = 1/cos(TILT) ; px = (cx + M) * ppc ; py = (cy + M) * ppc - z * tan(TILT) * ppc.
Repère Blender : 1 unité = 1 case. X = colonne, Y = -rangée, Z = hauteur.

Contenu, AU COUCHANT : sable à perte de vue (dunes, ondulations), grand temple carré à enceinte
de grès (galerie à colonnes lotiformes, chambres d'angle à toit, cour intérieure, SANCTUAIRE doré
au cœur, pylônes de la porte sud), quatre temples d'angle à cour (chambres funéraires, toits
plats ensablés, frises de hiéroglyphes), salle hypostyle, avenue dallée des sphinx (deux colosses
assis), pyramides (grandes aux coins, petites au milieu des côtés, entrée sombre), obélisques,
palmiers, rochers, ruines ensablées, oasis, campement. Éclairage : soleil bas doré, torches et
braseros (lumières chaudes), ciel ambré. Les blocs génériques (NT, MB, frame, render_chunked,
render_mask, render_occ) sont repris de mall_scene.py / fw_scene.py.
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

TILT_DEG = float(os.environ.get("EG_TILT", "38"))
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

    def vfloor(self, v):
        m = self.n("ShaderNodeVectorMath")
        m.operation = "FLOOR"
        self._in(m.inputs[0], v)
        return m.outputs[0]

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




# ======================================================================= matériaux
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


def mat_sand(name, base=(0.78, 0.6, 0.34)):
    """Sable du désert : grandes plages claires / sombres, rides de vent fines (sinus gauchi, relief
    par bump : la lumière rasante les dessine), traînées de vent, grain et gravillons sombres et
    clairs, cailloux. Relief fort mais teinte peu modulée (lecture d'ensemble calme)."""
    s = NT(name)
    o = s.obj()
    ox_, oy_, _ = s.sep(o)
    big = s.noise(o, 0.12, 4, 0.55)
    mid = s.noise(o, 0.55, 5, 0.6)
    warp = s.noise(s.vmul(o, 0.25), 1.0, 3, 0.5)
    # rides : période ~0.45 case, orientation gauchie, amplitude modulée par plages
    wv = s.m_("SINE", s.add(s.mul(s.add(oy_, s.mul(ox_, 0.35)), 17.0), s.mul(warp, 22.0)))
    ripple = s.add(0.5, s.mul(wv, 0.5))
    ripple = s.mul(s.m_("POWER", ripple, 1.6), float(os.environ.get("EG_RIPPLE", "1.0")))
    rbig = s.smooth(s.noise(s.vmul(o, 0.35), 1.0, 2, 0.5), 0.3, 0.7)
    ramp_ = s.add(0.1, s.mul(rbig, 0.6))
    # traînées de vent (bruit étiré)
    streak = s.noise(s.comb(s.mul(ox_, 0.6), s.mul(oy_, 3.0), 0.0), 1.2, 4, 0.6)
    grain = s.noise(o, 70.0, 3, 0.7)
    speck = s.white(s.vfloor(s.vmul(o, 22.0)))
    col = s.mix(s.mul(s.smooth(ripple, 0.2, 0.8), s.mul(ramp_, 0.2)), tuple(x * 0.93 for x in base), tuple(min(1.0, x * 1.05) for x in base))
    col = s.mix(s.mul(grain, 0.3), col, tuple(x * 0.86 for x in base))
    col = s.mix(s.smooth(big, 0.52, 0.78, 0.0, 0.6), col, tuple(x * 0.74 for x in base))
    col = s.mix(s.smooth(mid, 0.58, 0.75, 0.0, 0.4), col, tuple(x * 0.82 for x in base))
    col = s.mix(s.smooth(big, 0.45, 0.2, 0.0, 0.5), col, (min(1.0, base[0] * 1.12), base[1] * 1.04, base[2] * 0.88))
    col = s.mix(s.smooth(streak, 0.55, 0.72, 0.0, 0.35), col, (base[0] * 0.8, base[1] * 0.7, base[2] * 0.6))
    # gravillons (points sombres / clairs)
    col = s.mix(s.smooth(speck, 0.93, 0.96, 0.0, 0.7), col, tuple(x * 0.5 for x in base))
    col = s.mix(s.smooth(speck, 0.06, 0.03, 0.0, 0.5), col, tuple(min(1.0, x * 1.2) for x in base))
    # cailloux
    peb = s.voronoi(s.vmul(o, 2.6), 1.0)
    pebw = s.white(s.vfloor(s.vmul(o, 2.6)))
    col = s.mix(s.mul(s.smooth(peb, 0.16, 0.08), s.smooth(pebw, 0.7, 0.75)), col, tuple(x * 0.45 for x in base))
    col = s.mix(s.mul(s.smooth(peb, 0.12, 0.05), s.smooth(pebw, 0.3, 0.25)), col, tuple(min(1.0, x * 1.25) for x in base))
    h = s.add(s.mul(ripple, s.mul(ramp_, 0.35)), s.add(s.mul(grain, 0.12), s.mul(mid, 0.4)))
    s.done(col, normal=s.bump(h, 0.5, 0.06), metal=0.0, rough_sock=s.add(0.9, s.mul(grain, 0.1)))
    return s.m


def mat_ashlar(name, base, dark, pw=1.0, ph=0.5, var=0.12, rough=0.8, grime=0.3, frieze=None, footsand=True):
    """Appareil de blocs de grès (UV monde : u horizontal, v vertical) : joints sombres, teinte par
    bloc, érosion, sable incrusté en bas ; frieze = (couleur, v0, v1) bande de hiéroglyphes."""
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    iv = s.m_("FLOOR", s.m_("DIVIDE", v, ph))
    stag = s.mul(s.m_("MODULO", iv, 2.0), pw * 0.5)
    uu = s.add(u, stag)
    fu = s.m_("FRACT", s.m_("DIVIDE", uu, pw))
    fv = s.m_("FRACT", s.m_("DIVIDE", v, ph))
    iu = s.m_("FLOOR", s.m_("DIVIDE", uu, pw))
    r = s.white(s.comb(iu, iv, 2.3))
    gu = 0.03 / pw
    gv = 0.03 / ph
    ju = s.sub(1.0, s.mul(s.smooth(fu, 0.0, gu), s.smooth(fu, 1.0, 1.0 - gu)))
    jv = s.sub(1.0, s.mul(s.smooth(fv, 0.0, gv), s.smooth(fv, 1.0, 1.0 - gv)))
    joint = s.m_("MAXIMUM", ju, jv)
    col = s.mix(s.mul(r, var * 2.0), base, tuple(min(1.0, x * 1.2) for x in base))
    n = s.noise(s.obj(), 3.0, 5, 0.6)
    col = s.mix(s.smooth(n, 0.5, 0.85, 0.0, grime), col, tuple(x * 0.6 for x in base))
    # sable incrusté au pied du mur
    # (faces verticales seulement : sur une arase, v = Y monde < 0 → tout serait « ensablé »)
    if footsand:
        sandk = s.sub(1.0, s.smooth(v, 0.05, 0.4))
        col = s.mix(s.mul(sandk, 0.6), col, (0.8, 0.64, 0.4))
    if frieze:
        fc, v0, v1 = frieze
        band = s.mul(s.smooth(v, v0 - 0.01, v0), s.sub(1.0, s.smooth(v, v1, v1 + 0.01)))
        # glyphes : cellules de Voronoi en petits motifs sombres sur fond doré
        gl = s.voronoi(s.comb(s.mul(u, 6.0), s.mul(v, 6.0), 0.0), 1.0)
        glyph = s.smooth(gl, 0.18, 0.1)
        fcol = s.mix(s.mul(glyph, 0.8), fc, (0.2, 0.12, 0.06))
        col = s.mix(band, col, fcol)
    col = s.mix(s.mul(joint, 0.45), col, dark)
    sc_ = s.noise(s.comb(s.mul(u, 30.0), s.mul(v, 3.0), 0.0), 8.0, 3, 0.5)
    h = s.add(s.mul(joint, -1.0), s.mul(sc_, 0.08))
    s.done(col, normal=s.bump(h, 0.4, 0.02), metal=0.0, rough_sock=s.add(rough, s.mul(s.sub(r, 0.5), 0.15)))
    return s.m


def mat_slabs(name, c1, c2, size=1.0, rough=0.75, grout=(0.3, 0.2, 0.12), sand=0.45):
    """Dallage de grès (grandes dalles irrégulières) : joints, teinte par dalle, sable soufflé."""
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    iu = s.m_("FLOOR", s.m_("DIVIDE", u, size))
    iv = s.m_("FLOOR", s.m_("DIVIDE", v, size))
    stag = s.mul(s.m_("MODULO", iv, 2.0), size * 0.5)
    uu = s.add(u, stag)
    iu = s.m_("FLOOR", s.m_("DIVIDE", uu, size))
    fu = s.m_("FRACT", s.m_("DIVIDE", uu, size))
    fv = s.m_("FRACT", s.m_("DIVIDE", v, size))
    r = s.white(s.comb(iu, iv, 1.3))
    col = s.mix(s.mul(r, 0.9), c1, c2)
    g = 0.04 / size
    ju = s.sub(1.0, s.mul(s.smooth(fu, 0.0, g), s.smooth(fu, 1.0, 1.0 - g)))
    jv = s.sub(1.0, s.mul(s.smooth(fv, 0.0, g), s.smooth(fv, 1.0, 1.0 - g)))
    joint = s.m_("MAXIMUM", ju, jv)
    n = s.noise(s.obj(), 0.9, 6, 0.65)
    n2 = s.noise(s.obj(), 14.0, 4, 0.6)
    col = s.mix(s.smooth(n, 0.5, 0.85, 0.0, sand), col, (0.82, 0.66, 0.42))
    col = s.mix(s.mul(n2, 0.2), col, tuple(x * 0.85 for x in c1))
    col = s.mix(s.mul(joint, 0.6), col, grout)
    rg = s.add(rough, s.mul(s.smooth(n, 0.45, 0.8), 0.2))
    s.done(col, normal=s.bump(s.add(s.mul(joint, -1.0), s.mul(n2, 0.1)), 0.3, 0.02), metal=0.0, rough_sock=rg)
    return s.m


def mat_pyramid(name, base=(0.8, 0.62, 0.36)):
    """Pierre des pyramides : assises fines horizontales (en z), blocs décalés, revêtement usé par
    plaques, érosion, sable soufflé dans les joints et au pied (relief par bump)."""
    s = NT(name)
    o = s.obj()
    x, y, z = s.sep(o)
    RH = 0.2
    row = s.m_("FLOOR", s.m_("DIVIDE", z, RH))
    fz = s.m_("FRACT", s.m_("DIVIDE", z, RH))
    lat = s.add(x, s.mul(y, 0.7))
    stag = s.mul(s.white(s.comb(row, 3.1, 0.0)), 0.8)
    fl = s.m_("FRACT", s.m_("DIVIDE", s.add(lat, stag), 0.8))
    r = s.white(s.comb(row, s.m_("FLOOR", s.m_("DIVIDE", s.add(lat, stag), 0.8)), 1.0))
    jz = s.sub(1.0, s.mul(s.smooth(fz, 0.0, 0.16), s.smooth(fz, 1.0, 0.84)))
    jl = s.sub(1.0, s.mul(s.smooth(fl, 0.0, 0.06), s.smooth(fl, 1.0, 0.94)))
    joint = s.m_("MAXIMUM", jz, s.mul(jl, 0.7))
    col = s.mix(r, tuple(v * 0.8 for v in base), tuple(min(1.0, v * 1.12) for v in base))
    # plaques de revêtement arraché (zones plus sombres et plus rugueuses)
    pl = s.noise(o, 0.35, 4, 0.55)
    patch = s.smooth(pl, 0.56, 0.66)
    n = s.noise(o, 2.2, 6, 0.62)
    col = s.mix(s.smooth(n, 0.5, 0.82, 0.0, 0.45), col, tuple(v * 0.72 for v in base))
    col = s.mix(s.mul(patch, 0.7), col, tuple(v * 0.68 for v in base))
    # coulures verticales (érosion) et taches claires de calcaire
    drip = s.noise(s.comb(s.mul(lat, 3.0), s.mul(z, 0.25), 0.0), 2.0, 4, 0.6)
    col = s.mix(s.smooth(drip, 0.6, 0.75, 0.0, 0.35), col, tuple(v * 0.75 for v in base))
    col = s.mix(s.smooth(drip, 0.32, 0.22, 0.0, 0.3), col, tuple(min(1.0, v * 1.18) for v in base))
    col = s.mix(s.sub(1.0, s.smooth(z, 0.0, 1.6)), col, (0.82, 0.64, 0.4))
    col = s.mix(s.mul(joint, s.add(0.45, s.mul(patch, 0.35))), col, tuple(v * 0.42 for v in base))
    grain = s.noise(o, 40.0, 3, 0.6)
    h = s.add(s.add(s.mul(joint, -1.0), s.mul(n, 0.35)), s.add(s.mul(patch, -0.5), s.mul(grain, 0.12)))
    s.done(col, normal=s.bump(h, 0.7, 0.04), metal=0.0, rough_sock=s.add(0.82, s.mul(grain, 0.12)))
    return s.m


def mat_gold(name, c=(1.0, 0.72, 0.22)):
    s = NT(name)
    n = s.noise(s.obj(), 8.0, 4, 0.5)
    col = s.mix(s.mul(n, 0.4), c, (0.6, 0.38, 0.1))
    s.done(col, normal=s.bump(n, 0.1, 0.02), metal=0.9, rough_sock=s.add(0.28, s.mul(n, 0.2)))
    s.b.inputs["Emission Color"].default_value = (1.0, 0.7, 0.25, 1)
    s.b.inputs["Emission Strength"].default_value = 0.12
    return s.m


def mat_water(name):
    s = NT(name)
    n = s.noise(s.obj(), 5.0, 4, 0.5)
    s.done((0.08, 0.3, 0.3), 0.05, s.bump(n, 0.2, 0.02), 0.0)
    s.b.inputs["Emission Color"].default_value = (0.2, 0.55, 0.5, 1)
    s.b.inputs["Emission Strength"].default_value = 0.25
    return s.m


def mat_decal(name, c, alpha=0.85, scale=3.0):
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


def mat_sky(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value = (0.5, 0.3, 0.14, 1)
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs[0], o.inputs[0])
    MATS[name] = m
    return m


SAND = (0.86, 0.64, 0.37)
STONE = (0.5, 0.37, 0.25)
STONE_DARK = (0.17, 0.13, 0.1)


def build_materials():
    mat_sand("sand", SAND)
    mat_sand("sand_dark", (0.5, 0.35, 0.18))
    mat_slabs("slabs", (0.36, 0.29, 0.23), (0.3, 0.24, 0.19), 1.0, grout=(0.14, 0.11, 0.09), sand=0.18)
    mat_slabs("slabs_big", (0.42, 0.33, 0.25), (0.35, 0.27, 0.2), 2.0, grout=(0.2, 0.15, 0.11), sand=0.22)
    mat_slabs("slabs_sandy", (0.62, 0.5, 0.36), (0.55, 0.44, 0.32), 1.0, grout=(0.3, 0.22, 0.14), sand=0.7)
    mat_slabs("slabs_dark", (0.33, 0.26, 0.2), (0.27, 0.21, 0.16), 1.0, grout=(0.1, 0.08, 0.07), sand=0.15)
    mat_slabs("slabs_sanct", (0.38, 0.28, 0.2), (0.32, 0.23, 0.16), 1.0, grout=(0.12, 0.08, 0.05), sand=0.12)
    mat_slabs("slabs_gold", (0.7, 0.54, 0.3), (0.58, 0.44, 0.24), 0.5, grout=(0.3, 0.2, 0.08), sand=0.1)
    mat_ashlar("wall", (0.44, 0.32, 0.21), STONE_DARK, pw=1.0, ph=0.45, var=0.2, grime=0.7)
    mat_ashlar("wall_ext", (0.56, 0.42, 0.28), STONE_DARK, pw=1.2, ph=0.5, var=0.2, grime=0.7)
    mat_ashlar("wall_frieze", STONE, STONE_DARK, pw=1.0, ph=0.45, frieze=((0.95, 0.75, 0.3), 0.85, 1.15))
    mat_ashlar("wall_sanct", (0.34, 0.25, 0.17), STONE_DARK, pw=0.8, ph=0.4, grime=0.7, frieze=((1.0, 0.8, 0.32), 0.7, 1.2), footsand=False)
    mat_ashlar("wall_top", (0.42, 0.3, 0.19), STONE_DARK, pw=0.9, ph=0.65, var=0.26, grime=0.85, footsand=False)
    mat_decal("sand_drift", (0.8, 0.65, 0.44), 0.75, 2.0)
    mat_decal("sand_shade", (0.52, 0.38, 0.22), 0.5, 1.2)
    mat_slabs("roof_slab", (0.36, 0.26, 0.17), (0.3, 0.21, 0.14), 1.0, grout=(0.12, 0.09, 0.07), sand=0.6)
    mat_simple("crack", (0.18, 0.11, 0.06), 0.9, 0.0, 0.1)
    mat_simple("granite", (0.4, 0.31, 0.22), 0.75, 0.0, 0.25, 5.0, c2=(0.22, 0.16, 0.1))
    mat_ashlar("statue", (0.6, 0.45, 0.29), STONE_DARK, pw=0.9, ph=0.35, var=0.1, grime=0.55, footsand=False)
    mat_simple("granite_lit", (0.56, 0.42, 0.28), 0.75, 0.0, 0.3, 4.0, c2=(0.3, 0.21, 0.13))
    mat_pyramid("pyramid", (0.8, 0.58, 0.36))
    mat_pyramid("pyramid_dark", (0.66, 0.47, 0.29))
    mat_simple("pyramid_cap", (0.86, 0.72, 0.5), 0.6, 0.0, 0.2, 6.0)
    mat_simple("basalt", (0.16, 0.14, 0.14), 0.6, 0.0, 0.2)
    mat_simple("stone_lit", (0.64, 0.54, 0.42), 0.7, 0.0, 0.2)
    mat_simple("limestone", (0.68, 0.6, 0.44), 0.7, 0.0, 0.15)
    mat_simple("clay", (0.62, 0.34, 0.18), 0.75, 0.0, 0.25)
    mat_simple("clay_dark", (0.4, 0.2, 0.1), 0.8, 0.0, 0.2)
    mat_simple("wood", (0.42, 0.26, 0.13), 0.7, 0.0, 0.3)
    mat_simple("wood_dark", (0.24, 0.14, 0.07), 0.75, 0.0, 0.3)
    mat_simple("linen", (0.86, 0.78, 0.58), 0.9, 0.0, 0.2)
    mat_simple("linen_red", (0.62, 0.16, 0.12), 0.9, 0.0, 0.25)
    mat_simple("lapis", (0.1, 0.18, 0.55), 0.4, 0.0, 0.25)
    mat_simple("turquoise", (0.14, 0.55, 0.5), 0.4, 0.0, 0.2)
    mat_simple("bronze", (0.5, 0.32, 0.14), 0.4, 0.7, 0.15)
    mat_simple("bone", (0.85, 0.8, 0.68), 0.7, 0.0, 0.15)
    mat_simple("palm_leaf", (0.24, 0.42, 0.12), 0.7, 0.0, 0.4, 9.0, c2=(0.09, 0.22, 0.06))
    mat_simple("palm_leaf2", (0.36, 0.46, 0.14), 0.7, 0.0, 0.4, 9.0, c2=(0.14, 0.26, 0.07))
    mat_simple("palm_trunk", (0.4, 0.26, 0.14), 0.9, 0.0, 0.3, 6.0)
    mat_simple("rock", (0.44, 0.33, 0.21), 0.9, 0.0, 0.35, 3.0, c2=(0.2, 0.14, 0.08))
    mat_simple("rock_dark", (0.36, 0.26, 0.16), 0.9, 0.0, 0.35, 3.0)
    mat_simple("doorway", (0.03, 0.02, 0.015), 0.9, var=0.1)
    mat_simple("coal", (0.08, 0.04, 0.02), 0.8, var=0.3, emit=((1.0, 0.3, 0.05), 1.2))
    mat_gold("gold")
    mat_gold("gold_dark", (0.75, 0.52, 0.16))
    mat_water("water")
    mat_decal("stain", (0.3, 0.2, 0.1), 0.35)
    mat_decal("scorch", (0.08, 0.05, 0.03), 0.5)
    mat_sky("_sky")
    mat_emit("flame", (1.0, 0.33, 0.05), 2.2)
    mat_emit("flame_core", (1.0, 0.5, 0.14), 3.0)
    mat_emit("ember", (1.0, 0.35, 0.08), 4.0)
    mat_emit("gold_glow", (1.0, 0.5, 0.1), 2.2)
    mat_simple("plaque", (0.2, 0.09, 0.05), 0.5, 0.0, 0.2)
    mat_simple("carpet_red", (0.32, 0.09, 0.05), 0.95, 0.0, 0.35, 14.0, c2=(0.18, 0.05, 0.03))
    mat_simple("carpet_blue", (0.08, 0.11, 0.26), 0.95, 0.0, 0.35, 14.0, c2=(0.05, 0.06, 0.14))

# ======================================================================= analyse du layout
ROOMS = LAYOUT.get("rooms", [])
ROOM_BY_ID = {r["id"]: r for r in ROOMS}
MODS = C.get("modules", [])
MOD_BY_ROOM = {m["room"]: m for m in MODS}
BLD = {b["id"]: b for b in LAYOUT.get("buildings", [])}
DOOR_CELLS = {tuple(d["cell"]): d for d in LAYOUT.get("doors", [])}
EXTRACT = set(tuple(c) for c in LAYOUT.get("extraction", []))
ENCL = C.get("enclosure", [22, 30, 28, 28])
INNER = C.get("inner", [27, 35, 18, 18])
SANCT = C.get("sanctuary", [30, 38, 12, 12])
PYLONS = C.get("pylons", [])
GATEHOUSE = C.get("gatehouse", [31, 51, 10, 8])
COURTS = C.get("courts", [])
GATE_RECTS = C.get("gate_rects", [])
STAIRS_R = C.get("stairs", [31, 66, 10, 4])
PATHS = C.get("paths", [])
HYPO = C.get("hypostyle", [32, 13, 8, 7])
AVENUE = C.get("avenue", [30, 59, 12, 28])
COLUMNS = set(tuple(c) for c in C.get("columns", []))
TORCHES = [tuple(t) for t in C.get("torches", [])]
LANDMARKS = LAYOUT.get("landmarks", [])

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
    return r["tags"][0] if r and r.get("tags") else "desert"


def role_at(x, y):
    return role_of(CELL_ROOM.get((x, y), -1))


CELL_BLD = {}
for b in LAYOUT.get("buildings", []):
    x, y, w, h = b["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            CELL_BLD.setdefault((xx, yy), b["id"])
LM_CELLS = {}
for lm in LANDMARKS:
    x, y, w, h = lm["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            LM_CELLS[(xx, yy)] = lm["kind"]
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


def in_rect(x, y, r):
    return r[0] <= x < r[0] + r[2] and r[1] <= y < r[1] + r[3]


def on_border(x, y, r):
    return in_rect(x, y, r) and (x == r[0] or y == r[1] or x == r[0] + r[2] - 1 or y == r[1] + r[3] - 1)


H_EXT = 2.0          # murs extérieurs (donnant sur le sable) : épais, à corniche
H_PYLON = 3.4
H_ROOF = 1.7         # chambres à toit
H_SANCT = 0.9
H_INNER = 1.45       # mur intérieur, cloisons sans toit
H_CUT = 0.7          # haut du mur sud masqué en passe int
H_DOOR = 1.05


def wall_kind(x, y):
    if (x, y) in COLUMNS:
        return "column"
    if (x, y) in LM_CELLS:
        return "lm"
    if in_rect(x, y, GATEHOUSE):
        return "pylon"
    if in_rect(x, y, SANCT):
        return "sanct"
    if EXT_CELLS.get((x, y)):
        return "ext"
    if (x, y) in CELL_BLD:
        return "roof"
    return "inner"


# Murs extérieurs : cases murées voisines (8) du sable (hors repères, colonnes, bord de carte).
EXT_CELLS = {}
for _y in range(1, H - 1):
    for _x in range(1, W - 1):
        if tile(_x, _y) != 3 or (_x, _y) in LM_CELLS or (_x, _y) in COLUMNS:
            continue
        for _dy in (-1, 0, 1):
            for _dx in (-1, 0, 1):
                if tile(_x + _dx, _y + _dy) == 1 and (_x + _dx, _y + _dy) not in LM_CELLS:
                    EXT_CELLS[(_x, _y)] = True


_WH = {}


def wall_h(x, y):
    """Hauteur d'arase. Murs « ext » / « inner » en ruine : sommet érodé irrégulier (gradins de
    blocs manquants), brèches basses ; jamais sous 0.7 (le mur reste bloquant et lisible)."""
    v = _WH.get((x, y))
    if v is not None:
        return v
    k = wall_kind(x, y)
    h = {"column": 1.9, "lm": 0.0, "pylon": H_PYLON, "sanct": H_SANCT, "roof": H_ROOF, "ext": H_EXT, "inner": H_INNER}[k]
    if k in ("ext", "inner") and (x, y) not in DOOR_NEAR:
        hr = random.Random(x * 92821 + y * 68917 + SEED * 7)
        # bruit lent le long des murs (zones plus ruinées) + bruit par case
        zone = math.sin(x * 0.37 + SEED * 0.1) * math.cos(y * 0.29 - SEED * 0.07)
        r = hr.random()
        if r < 0.03 + 0.05 * max(0.0, zone):
            h = max(0.7, h * hr.uniform(0.45, 0.6))          # brèche
        elif r < 0.18 + 0.12 * zone:
            h = h - hr.choice((0.12, 0.2, 0.3, 0.42))        # blocs manquants
    _WH[(x, y)] = h
    return h


# cases murées voisines d'une porte : arase intacte (linteaux, chambranles)
DOOR_NEAR = set()
for (_dx, _dy) in DOOR_CELLS:
    for _ox in (-1, 0, 1):
        for _oy in (-1, 0, 1):
            DOOR_NEAR.add((_dx + _ox, _dy + _oy))


# ======================================================================= sol
def paving_of(x, y):
    """Matière du sol d'une case praticable."""
    t = tile(x, y)
    role = role_at(x, y)
    if t == 2:
        rid = CELL_ROOM.get((x, y), -1)
        if role == "sanctuary":
            return "slabs_sanct"
        if role in ("tomb", "treasury", "embalming"):
            return "slabs_dark"
        return "slabs"
    if role in ("hypostyle",):
        return "slabs"
    if role in ("gallery", "inner_court", "avenue", "court", "gate"):
        return "slabs_big"
    return None


def build_floors():
    sand = MB()
    m = MARGIN + 4
    sand.poly([(-m, Y(H + m), -0.02), (W + m, Y(H + m), -0.02), (W + m, Y(-m), -0.02), (-m, Y(-m), -0.02)], "sand",
              [(-m, Y(H + m)), (W + m, Y(H + m)), (W + m, Y(-m)), (-m, Y(-m))])
    sand.to_object("sand", "world")
    mbs = {}
    for y in range(H):
        for x in range(W):
            if not walk(x, y):
                continue
            mat = paving_of(x, y)
            if mat is None:
                continue
            bid = CELL_BLD.get((x, y), -1)
            key = ("floor_%d" % bid) if bid >= 0 else "paving"
            mb = mbs.setdefault(key, MB())
            mb.poly([(x, Y(y + 1), 0.0), (x + 1, Y(y + 1), 0.0), (x + 1, Y(y), 0.0), (x, Y(y), 0.0)], mat,
                    [(x, Y(y + 1)), (x + 1, Y(y + 1)), (x + 1, Y(y)), (x, Y(y))])
    for key, mb in mbs.items():
        mb.to_object(key, "world")
    # Dunes molles hors carte et sur les bords (sphères aplaties de sable), extraction (cadre doré)
    dn = MB()
    rng = random.Random(SEED * 5 + 1)
    for k in range(60):
        side = rng.randint(0, 3)
        if side == 0:
            cx, cy = rng.uniform(-m, W + m), rng.uniform(-m, -1.5)
        elif side == 1:
            cx, cy = rng.uniform(-m, W + m), rng.uniform(H + 1.5, H + m)
        elif side == 2:
            cx, cy = rng.uniform(-m, -1.5), rng.uniform(-m, H + m)
        else:
            cx, cy = rng.uniform(W + 1.5, W + m), rng.uniform(-m, H + m)
        r_ = rng.uniform(2.0, 5.0)
        dn.sphere(cx, Y(cy), -r_ * 0.2, r_ * 1.3, "sand", 4, 1.6, 1.0, 0.26, nscale=0.35, rng=rng)
    dn.to_object("_dunes", "world", smooth=True)
    mk = MB()
    for (ex, ey) in EXTRACT:
        mk.box(ex + 0.06, Y(ey + 0.94), 0.0, ex + 0.94, Y(ey + 0.06), 0.012, "gold_dark")
        mk.box(ex + 0.14, Y(ey + 0.86), 0.0, ex + 0.86, Y(ey + 0.14), 0.016, "slabs_dark")
    mk.to_object("ground_marks", "world")


# ======================================================================= murs
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


def wall_mat(x, y, side, nx, ny):
    k = wall_kind(x, y)
    if k == "sanct":
        return "wall_sanct"
    if k == "pylon":
        return "wall_frieze"
    if k == "roof":
        # façade (côté espace ouvert) avec frise ; intérieur uni
        if tile(nx, ny) in (1, 4) or (tile(nx, ny) == 2 and CELL_BLD.get((nx, ny)) != CELL_BLD.get((x, y))):
            return "wall_frieze"
        return "wall"
    if k == "ext":
        return "wall_ext"
    return "wall"


def build_walls():
    mbs = {}

    def target(x, y, upper=False):
        b = CELL_BLD.get((x, y))
        if b is None:
            return mbs.setdefault("hullwalls", MB())
        return mbs.setdefault(("front_%d" if upper else "walls_%d") % b, MB())

    for y in range(H):
        for x in range(W):
            if tile(x, y) != 3 or x == 0 or y == 0 or x == W - 1 or y == H - 1:
                continue
            k = wall_kind(x, y)
            if k in ("column", "lm"):
                continue
            h = wall_h(x, y)
            b = CELL_BLD.get((x, y))
            south_row = b is not None and y == BLD[b]["rect"][1] + BLD[b]["rect"][3] - 1
            for side, dx, dy in SIDES:
                nx, ny = x + dx, y + dy
                nt_ = tile(nx, ny)
                if nt_ == 3 and wall_kind(nx, ny) not in ("column", "lm"):
                    nh = wall_h(nx, ny)
                    if nh >= h - 1e-3:
                        continue
                    z0 = nh
                elif nt_ == 0:
                    z0 = -0.05
                else:
                    z0 = -0.02
                mat = wall_mat(x, y, side, nx, ny)
                if south_row and h > H_CUT:
                    if z0 < H_CUT:
                        face(target(x, y), x, y, side, z0, H_CUT, mat)
                    face(target(x, y, True), x, y, side, max(z0, H_CUT), h, mat)
                else:
                    face(target(x, y), x, y, side, z0, h, mat)
            tg2 = target(x, y, south_row)
            if south_row:
                target(x, y).poly([(x, Y(y + 1), H_CUT), (x + 1, Y(y + 1), H_CUT), (x + 1, Y(y), H_CUT), (x, Y(y), H_CUT)], "wall_top")
            if k in ("ext", "pylon", "sanct"):
                # Corniche : dalle de couronnement (seule surface au sommet : pas de faces
                # coplanaires → pas d'acné d'ombre), débord sur les côtés libres.
                lip = {}
                for sd, dx, dy in SIDES:
                    nk = wall_kind(x + dx, y + dy) if tile(x + dx, y + dy) == 3 else ""
                    lip[sd] = 0.0 if (nk in ("ext", "pylon", "sanct") and abs(wall_h(x + dx, y + dy) - h) < 1e-3) else 0.07
                tg2.box(x - lip["W"], Y(y + 1) - lip["S"], h - 0.16, x + 1 + lip["E"], Y(y) + lip["N"], h + 0.05,
                        "wall_top" if k in ("ext", "pylon") else "granite")
            else:
                tg2.poly([(x, Y(y + 1), h), (x + 1, Y(y + 1), h), (x + 1, Y(y), h), (x, Y(y), h)], "wall_top",
                         [(x, Y(y + 1)), (x + 1, Y(y + 1)), (x + 1, Y(y)), (x, Y(y))])
                # sommet érodé : blocs déchaussés / gravats sur l'arase (lecture « ruine » de la planche)
                hr = random.Random(x * 7919 + y * 104729 + SEED)
                if hr.random() < 0.04:
                    for _q in range(hr.randint(1, 2)):
                        bx = x + hr.uniform(0.05, 0.6)
                        by = y + hr.uniform(0.05, 0.6)
                        sz = hr.uniform(0.18, 0.38)
                        tg2.box(bx, Y(by + sz), h + 0.004, bx + sz, Y(by), h + hr.uniform(0.06, 0.18),
                                hr.choice(("wall", "wall_ext", "granite")), rot=hr.uniform(-0.4, 0.4))
    # piliers engagés aux angles saillants des murs extérieurs (débord + sommet plus haut)
    pil = mbs.setdefault("hullwalls", MB())
    for (x, y) in EXT_CELLS:
        if wall_kind(x, y) != "ext" or (x, y) in DOOR_NEAR or CELL_BLD.get((x, y)) is not None:
            continue
        wn = {sd: tile(x + dx, y + dy) == 3 for sd, dx, dy in SIDES}
        corner = (wn["N"] != wn["S"]) and (wn["E"] != wn["W"])
        if not corner:
            continue
        o = 0.1
        hp_ = H_EXT + 0.32
        pil.box(x - (o if not wn["W"] else 0.0), Y(y + 1) - (o if not wn["S"] else 0.0), -0.02,
                x + 1 + (o if not wn["E"] else 0.0), Y(y) + (o if not wn["N"] else 0.0), hp_, "wall_ext")
        pil.box(x - 0.16, Y(y + 1) - 0.16, hp_, x + 1.16, Y(y) + 0.16, hp_ + 0.14, "wall_top")
    # blocs tombés au pied des murs érodés (sur le sable / dallage, bas : ne bloquent pas)
    fb = mbs.setdefault("_fallen", MB())
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if tile(x, y) != 3 or wall_kind(x, y) not in ("ext", "inner"):
                continue
            base = H_EXT if wall_kind(x, y) == "ext" else H_INNER
            loss = base - wall_h(x, y)
            if loss < 0.15:
                continue
            hr = random.Random(x * 31 + y * 1777 + SEED)
            for sd, dx, dy in SIDES:
                nx, ny = x + dx, y + dy
                if tile(nx, ny) not in (1, 2) or hr.random() > 0.25:
                    continue
                for _q in range(hr.randint(1, 3 if loss > 0.4 else 2)):
                    sz = hr.uniform(0.16, 0.3)
                    bx = nx + 0.5 - dx * 0.5 * 0 + (hr.uniform(-0.45, 0.45) if dx == 0 else -dx * hr.uniform(0.1, 0.4))
                    by = ny + 0.5 + (hr.uniform(-0.45, 0.45) if dy == 0 else -dy * hr.uniform(0.1, 0.4))
                    fb.box(bx - sz / 2, Y(by + sz * 0.35), 0.0, bx + sz / 2, Y(by - sz * 0.35), hr.uniform(0.07, 0.13),
                           hr.choice(("wall", "wall_ext", "wall_top")), rot=hr.uniform(-0.6, 0.6))
    # pylônes : faces inclinées (talus) — un prisme par bloc de pylône
    for p in PYLONS:
        x, y, w, h = p
        mb = mbs.setdefault("hullwalls", MB())
        # oriflamme rouge et cartouche doré plaqués sur la face sud du pylône
        mb.box(x + w / 2 - 0.4, Y(y + h) - 0.06, 0.8, x + w / 2 + 0.4, Y(y + h) + 0.02, H_PYLON - 0.4, "linen_red")
        mb.box(x + w / 2 - 0.5, Y(y + h) - 0.08, H_PYLON - 0.4, x + w / 2 + 0.5, Y(y + h) + 0.02, H_PYLON - 0.15, "gold_dark")
    # linteau monumental au-dessus du couloir de la porte-pylône (haut : ne bloque pas)
    gx, gy, gw, gh = GATEHOUSE
    hm = mbs.setdefault("hullwalls", MB())
    for yy in (gy + 0.15, gy + gh - 0.85):
        hm.box(gx + 3.8, Y(yy + 0.7), H_PYLON - 0.9, gx + 6.2, Y(yy), H_PYLON - 0.1, "wall_frieze")
    # portes : encadrement de grès, linteau, ouverture sombre (le jeu dessine le battant)
    for (dx_, dy_), d in DOOR_CELLS.items():
        bid = CELL_BLD.get((dx_, dy_))
        hh = wall_h(dx_, dy_) if tile(dx_, dy_) == 3 else (wall_h(dx_ - 1, dy_) if d["vertical"] else wall_h(dx_, dy_ - 1))
        if hh <= 0.0:
            hh = H_INNER
        south = bid is not None and dy_ == BLD[bid]["rect"][1] + BLD[bid]["rect"][3] - 1
        tg = mbs.setdefault(("front_%d" % bid) if south else (("walls_%d" % bid) if bid is not None else "hullwalls"), MB())
        tl = mbs.setdefault(("walls_%d" % bid) if bid is not None else "hullwalls", MB())
        X0, X1, YN, YS = dx_, dx_ + 1, Y(dy_), Y(dy_ + 1)
        locked = d.get("state", 1) == 2
        if not d["vertical"]:
            tl.box(X0, YS + 0.3, 0.0, X1, YN - 0.3, H_DOOR, "doorway")
            tg.box(X0, YS + 0.25, H_DOOR, X1, YN - 0.25, hh, "wall")
            tg.box(X0 - 0.06, YS + 0.2, H_DOOR - 0.02, X1 + 0.06, YN - 0.2, H_DOOR + 0.13, "stone_lit")
            for ex in (X0, X1 - 0.12):
                tl.box(ex, YS + 0.2, 0.0, ex + 0.12, YN - 0.2, H_DOOR + 0.05, "stone_lit")
        else:
            tl.box(X0 + 0.3, YS, 0.0, X1 - 0.3, YN, H_DOOR, "doorway")
            tg.box(X0 + 0.25, YS, H_DOOR, X1 - 0.25, YN, hh, "wall")
            tg.box(X0 + 0.2, YS - 0.06, H_DOOR - 0.02, X1 - 0.2, YN + 0.06, H_DOOR + 0.13, "stone_lit")
            for ey in (YS, YN - 0.12):
                tl.box(X0 + 0.2, ey, 0.0, X1 - 0.2, ey + 0.12, H_DOOR + 0.05, "stone_lit")
        mbs.setdefault("ground_door", MB()).box(X0 + 0.05, YS + 0.05, 0.0, X1 - 0.05, YN - 0.05, 0.012, "slabs_dark")
        if locked:
            mbs.setdefault("ground_door", MB()).box(X0 + 0.3, YS + 0.3, 0.0, X1 - 0.3, YN - 0.3, 0.02, "gold")
    for k, mb in mbs.items():
        mb.to_object(k, "world")


# ======================================================================= colonnes, torches
def column(mb, x, y, h, r=0.36, mat="stone_lit"):
    cx, cy = x + 0.5, Y(y) - 0.5
    mb.cyl(cx, cy, 0.0, 0.12, r + 0.12, "wall_top", 10)
    mb.cyl(cx, cy, 0.12, h - 0.3, r, mat, 12)
    for k in range(5):
        a = k / 5 * math.tau
        mb.cyl(cx + math.cos(a) * r * 0.75, cy + math.sin(a) * r * 0.75, 0.2, h - 0.35, r * 0.3, mat, 6)
    mb.cyl(cx, cy, h - 0.3, h - 0.05, r * 0.9, "gold_dark", 12, r2=r + 0.18)
    mb.box(cx - r - 0.2, cy - r - 0.2, h - 0.05, cx + r + 0.2, cy + r + 0.2, h + 0.06, "wall_top")


def build_columns():
    mb = MB()
    for (x, y) in sorted(COLUMNS):
        h = 1.6 if CELL_BLD.get((x, y)) is None else H_ROOF - 0.1
        column(mb, x, y, h)
    mb.to_object("props_columns", "world")


TORCH_LIGHTS = []


def extra_torches():
    """Torches supplémentaires : galerie de l'enceinte (faces intérieures tous les 4 cases),
    cours des temples (angles), salle hypostyle."""
    out = []
    for (cx_, cy_, cw_, ch_) in COURTS:
        for xx in range(cx_ + 3, cx_ + cw_ - 3, 6):
            out.append((xx, cy_))
    # une torche par chambre (coin nord-ouest du sol)
    for m in MODS:
        ix, iy, iw, ih = m["inner"]
        if m["role"] in ("sanctuary", "hypostyle"):
            continue
        if iw * ih >= 8:
            out.append((ix, iy))
    return [c for c in out if walk(*c) and c not in GAME_CELLS]


def build_torches():
    mb = MB()
    for (tx, ty) in TORCHES + extra_torches():
        # adossée au mur voisin s'il y en a un, sinon sur un mât
        wall = None
        for sd, dx, dy in SIDES:
            if tile(tx + dx, ty + dy) == 3:
                wall = (sd, dx, dy)
                break
        cx, cy = tx + 0.5, Y(ty) - 0.5
        if wall:
            sd, dx, dy = wall
            cx, cy = tx + 0.5 + dx * 0.38, Y(ty) - 0.5 - dy * 0.38
            z = 1.0
            mb.box(cx - 0.08, cy - 0.08, z - 0.1, cx + 0.08, cy + 0.08, z, "bronze")
        else:
            z = 1.4
            mb.cyl(cx, cy, 0.0, z, 0.05, "wood_dark", 8)
            mb.cyl(cx, cy, 0.0, 0.08, 0.18, "bronze", 10)
        mb.cyl(cx, cy, z, z + 0.22, 0.13, "bronze", 10, r2=0.09)
        mb.sphere(cx, cy, z + 0.45, 0.24, "flame", 1, 1.0, 1.0, 1.6)
        mb.sphere(cx, cy, z + 0.42, 0.13, "flame_core", 1, 1.0, 1.0, 1.5)
        TORCH_LIGHTS.append((cx, cy, z + 0.6))
    mb.to_object("_torches", "world")


# ======================================================================= toits
def roof_chamber(mb, b, rng):
    x, y, w, h = b["rect"]
    sanct = b.get("arch") == "sanctuary"
    z = H_SANCT if sanct else H_ROOF
    X0, X1, YN, YS = x - 0.04, x + w + 0.04, Y(y) + 0.04, Y(y + h) - 0.04
    mb.box(X0, YS, z, X1, YN, z + 0.1, "roof_slab" if not sanct else "slabs_gold")
    if False:
        # toit de dalles-poutres de grès posées en travers (joints sombres), quelques-unes
        # fendues ou déchaussées : lecture « ruine » proche de la planche
        along_x = w < h
        L0, L1 = (y, y + h) if along_x else (x, x + w)
        pos = L0 + 0.15
        while pos < L1 - 0.2:
            bw_ = min(rng.uniform(0.6, 0.95), L1 - 0.15 - pos)
            ztop = z + 0.1 + rng.uniform(0.08, 0.16)
            mat_ = rng.choice(("roof_slab", "roof_slab", "wall_top"))
            if rng.random() < 0.1:
                pos += bw_ + 0.1
                continue
            if along_x:
                mb.box(X0 + 0.05, Y(pos + bw_), z + 0.09, X1 - 0.05, Y(pos), ztop, mat_, rot=rng.uniform(-0.02, 0.02))
            else:
                mb.box(pos, YS + 0.05, z + 0.09, pos + bw_, YN - 0.05, ztop, mat_, rot=rng.uniform(-0.02, 0.02))
            pos += bw_ + 0.1
    for (a0, a1, b0, b1) in ((X0, X1, YS, YS + 0.2), (X0, X1, YN - 0.2, YN), (X0, X0 + 0.2, YS + 0.2, YN - 0.2), (X1 - 0.2, X1, YS + 0.2, YN - 0.2)):
        mb.box(a0, b0, z + 0.1, a1, b1, z + 0.26, "gold_dark" if sanct else "wall_top")
    zt = z + 0.1
    # sable soufflé (dunes plates), trappe, jarres
    for k in range(rng.randint(2, 5)):
        cx = x + rng.uniform(0.8, w - 0.8)
        cy = y + rng.uniform(0.8, h - 0.8)
        r_ = rng.uniform(0.5, 1.1)
        mb.poly([(cx - r_, Y(cy + r_), zt + 0.005), (cx + r_, Y(cy + r_), zt + 0.005), (cx + r_, Y(cy - r_), zt + 0.005), (cx - r_, Y(cy - r_), zt + 0.005)], "sand_drift",
                [(0, 0), (1, 0), (1, 1), (0, 1)])
    if sanct:
        cx, cy = x + w / 2, y + h / 2
        # gradins (temple à degrés) puis disque solaire d'or
        for i, (ins, hz) in enumerate(((1.2, 0.5), (2.4, 0.5), (3.6, 0.4))):
            mb.box(x + ins, Y(y + h - ins), zt + i * 0.5, x + w - ins, Y(y + ins), zt + i * 0.5 + hz, "wall_sanct" if i < 2 else "granite")
            mb.box(x + ins - 0.06, Y(y + h - ins) - 0.06, zt + i * 0.5 + hz - 0.1, x + w - ins + 0.06, Y(y + ins) + 0.06, zt + i * 0.5 + hz - 0.02, "gold_dark")
        # torches aux 4 angles du premier gradin
        for (tx, ty) in ((x + 1.6, y + 1.6), (x + w - 1.6, y + 1.6), (x + 1.6, y + h - 1.6), (x + w - 1.6, y + h - 1.6)):
            mb.cyl(tx, Y(ty), zt + 0.5, zt + 1.3, 0.06, "bronze", 6)
            mb.sphere(tx, Y(ty), zt + 1.5, 0.22, "flame", 1, 1.0, 1.0, 1.5)
            TORCH_LIGHTS.append((tx, Y(ty), zt + 1.7))
        zt += 1.4
        # ankh d'or couché au sommet (lueur), disque solaire
        mb.box(cx - 0.18, Y(cy + 1.0), zt, cx + 0.18, Y(cy - 0.9), zt + 0.14, "gold")
        mb.box(cx - 0.9, Y(cy + 0.35), zt, cx + 0.9, Y(cy + 0.05), zt + 0.14, "gold")
        mb.cyl(cx, Y(cy - 1.3), zt, zt + 0.14, 0.45, "gold", 16)
        mb.cyl(cx, Y(cy - 1.3), zt, zt + 0.15, 0.22, "granite", 16)
        TORCH_LIGHTS.append((cx, Y(cy), zt + 0.8))
        return
    if w >= 4 and h >= 3 and rng.random() < 0.7:
        tx = x + rng.uniform(0.8, w - 1.6)
        ty = y + rng.uniform(0.8, h - 1.6)
        mb.box(tx, Y(ty + 0.8), zt, tx + 0.8, Y(ty), zt + 0.05, "wood_dark")
    for k in range(rng.randint(0, 2)):
        jx = x + rng.uniform(0.5, w - 0.5)
        jy = y + rng.uniform(0.5, h - 0.5)
        mb.cyl(jx, Y(jy), zt, zt + 0.4, 0.2, "clay", 10, r2=0.26)


def build_roofs():
    for b in LAYOUT.get("buildings", []):
        bid = b["id"]
        rng = random.Random(bid * 7919 + SEED)
        mb = MB()
        roof_chamber(mb, b, rng)
        mb.to_object("roof_%d" % bid, "roofs")


# ======================================================================= grands repères
def lm_pyramid(mb, rect, rng, big):
    x, y, w, h = rect
    # Les pyramides débordent seulement vers les bords de la carte (marge rendue, hors jeu) :
    # jamais sur le sable praticable (collisions par emprise cohérentes avec le plan).
    ex = 4 if big else 2
    if x <= 2:
        x -= ex
        w += ex
    elif x + w >= W - 2:
        w += ex
    if y <= 2:
        y -= ex
        h += ex
    elif y + h >= H - 2:
        h += ex
    cx, cy = x + w / 2, Y(y + h / 2)
    hp = min(w, h) * (0.55 if big else 0.62)
    # Faces lisses (revêtement de calcaire usé, assises fines dans la matière) : la lumière rasante
    # sépare nettement face éclairée (est) et face à l'ombre (ouest), comme la planche.
    ztop = hp * 0.94
    tw = w * 0.03 + 0.2
    bl, br = (x, Y(y + h), 0.0), (x + w, Y(y + h), 0.0)
    tl, tr = (x, Y(y), 0.0), (x + w, Y(y), 0.0)
    q = [(cx - tw, cy - tw, ztop), (cx + tw, cy - tw, ztop), (cx + tw, cy + tw, ztop), (cx - tw, cy + tw, ztop)]
    # arêtes légèrement émoussées : chaque face = trapèze base → sommet tronqué
    mb.poly([bl, br, q[1], q[0]], "pyramid")
    mb.poly([br, tr, q[2], q[1]], "pyramid")
    mb.poly([tr, tl, q[3], q[2]], "pyramid")
    mb.poly([tl, bl, q[0], q[3]], "pyramid")
    ap = (cx, cy, ztop + tw * 1.3)
    for i in range(4):
        mb.poly([q[i], q[(i + 1) % 4], ap], "pyramid_cap")
    # revêtement arraché par plaques (blocs saillants en gradins sur les arêtes basses)
    for k2 in range(rng.randint(10, 16)):
        t = rng.uniform(0.04, 0.55)
        side = rng.randint(0, 3)
        ins = t * w * 0.5
        zz = t * ztop
        sz = rng.uniform(0.35, 0.9)
        u = rng.uniform(0.15, 0.85)
        if side == 0:
            px_, py_ = x + ins + u * (w - 2 * ins), Y(y + h) + ins
        elif side == 1:
            px_, py_ = x + w - ins, Y(y + h) + ins + u * (h - 2 * ins)
        elif side == 2:
            px_, py_ = x + ins + u * (w - 2 * ins), Y(y) - ins
        else:
            px_, py_ = x + ins, Y(y + h) + ins + u * (h - 2 * ins)
        mb.box(px_ - sz / 2, py_ - sz / 2, zz - sz * 0.6, px_ + sz / 2, py_ + sz / 2, zz + sz * 0.25, "pyramid_dark", rot=rng.uniform(-0.2, 0.2))
    # entrée sombre au sud, sur la face (niche + linteau de granit)
    t0 = 0.16 if big else 0.12
    yf = Y(y + h) + t0 * h * 0.5
    zf = t0 * ztop
    mb.box(cx - 0.6, yf - 0.3, zf - 0.6, cx + 0.6, yf + 0.5, zf + 0.9, "doorway")
    mb.box(cx - 0.85, yf - 0.4, zf + 0.9, cx + 0.85, yf + 0.5, zf + 1.2, "granite")
    for sx in (-0.75, 0.6):
        mb.box(cx + sx, yf - 0.4, zf - 0.6, cx + sx + 0.15, yf + 0.5, zf + 0.95, "granite")
    # blocs éboulés au pied
    for k2 in range(rng.randint(4, 8)):
        bx = x + rng.uniform(0.2, w - 0.6)
        by = y + h + rng.uniform(-0.9, -0.5)
        s = rng.uniform(0.2, 0.45)
        mb.box(bx, Y(by + s), 0.0, bx + s, Y(by), s * 0.7, "pyramid", rot=rng.uniform(0, 1))


def lm_sphinx(mb, rect, rng):
    """Colosse assis (pharaon au némès) face au sud sur un socle à degrés, comme la planche :
    trône à frise de hiéroglyphes, jambes verticales, mains sur les genoux, buste droit, tête
    coiffée du némès rayé or / lapis, barbe postiche, uræus."""
    x, y, w, h = rect
    cx = x + w / 2
    yS, yN = Y(y + h), Y(y)
    G, GL = "granite", "statue"
    # socle à deux degrés
    mb.box(x + 0.02, yS + 0.02, 0.0, x + w - 0.02, yN - 0.02, 0.55, "wall_ext")
    mb.box(x + 0.02, yS + 0.02, 0.55, x + w - 0.02, yN - 0.02, 0.62, "wall_top")
    mb.box(x + 0.45, yS + 0.45, 0.62, x + w - 0.45, yN - 0.45, 0.95, "wall_ext")
    mb.box(x + 0.4, yS + 0.4, 0.95, x + w - 0.4, yN - 0.4, 1.02, "wall_top")
    z0 = 1.02
    s_ = 1.4
    def B(a, b, c, d, e, f, m):
        mb.box(cx + a * s_, yS + b * s_, z0 + c * s_, cx + d * s_, yS + e * s_, z0 + f * s_, m)
    # trône (bloc + dossier) à frise
    B(-1.75, 3.3, 0.0, 1.75, 6.6, 2.0, "wall_frieze")
    B(-1.8, 3.25, 1.95, 1.8, 6.65, 2.08, "gold_dark")
    B(-1.45, 5.6, 2.0, 1.45, 6.6, 4.6, "wall_frieze")
    # pieds, tibias, cuisses
    for sx in (-1.0, 1.0):
        B(sx * 0.82 - 0.45, 0.45, 0.0, sx * 0.82 + 0.45, 1.55, 0.32, GL)
        B(sx * 0.78 - 0.4, 1.1, 0.0, sx * 0.78 + 0.4, 1.9, 2.05, GL)
        B(sx * 0.78 - 0.45, 1.1, 1.75, sx * 0.78 + 0.45, 4.2, 2.45, GL)
    # pagne plissé (shendyt) entre les cuisses
    B(-0.36, 1.6, 0.9, 0.36, 3.6, 2.35, "gold_dark")
    for k in range(-2, 3):
        B(k * 0.14 - 0.03, 1.55, 1.0, k * 0.14 + 0.03, 1.62, 2.3, "lapis")
    # buste (taille fine, épaules larges)
    B(-0.85, 3.6, 2.4, 0.85, 4.9, 3.6, GL)
    B(-1.15, 3.7, 3.5, 1.15, 5.0, 4.75, GL)
    # collier ousekh
    B(-1.0, 3.62, 4.25, 1.0, 3.75, 4.6, "gold")
    B(-0.9, 3.6, 4.0, 0.9, 3.7, 4.25, "lapis")
    # bras : épaule → coude → main sur le genou
    for sx in (-1.0, 1.0):
        mb.seg((cx + sx * 1.3 * s_, yS + 4.4 * s_, z0 + 4.5 * s_), (cx + sx * 1.32 * s_, yS + 4.1 * s_, z0 + 2.9 * s_), 0.3 * s_, GL, 8)
        mb.seg((cx + sx * 1.32 * s_, yS + 4.1 * s_, z0 + 2.9 * s_), (cx + sx * 0.9 * s_, yS + 2.0 * s_, z0 + 2.55 * s_), 0.27 * s_, GL, 8)
        mb.sphere(cx + sx * 0.88 * s_, yS + 1.85 * s_, z0 + 2.55 * s_, 0.3 * s_, GL, 1, 1.0, 1.2, 0.6)
    # tête, némès rayé, retombées sur la poitrine, barbe, uræus
    hz = z0 + 5.35 * s_
    hy = yS + 4.3 * s_
    mb.sphere(cx, hy, hz, 0.55 * s_, GL, 2, 0.9, 0.9, 1.1)
    B(-0.85, 4.05, 5.3, 0.85, 5.1, 6.0, "gold_dark")
    mb.box(cx - 0.62 * s_, yS + 3.98 * s_, hz + 0.05, cx + 0.62 * s_, yS + 4.6 * s_, hz + 0.95 * s_, GL)
    for k in range(-3, 4):
        B(k * 0.24 - 0.05, 4.0, 5.95, k * 0.24 + 0.05, 5.15, 6.06, "lapis")
    for sx in (-1.0, 1.0):
        B(sx * 0.72 - 0.2, 3.85, 4.2, sx * 0.72 + 0.2, 4.4, 5.6, "gold_dark")
        for j in range(4):
            B(sx * 0.72 - 0.21, 3.83, 4.3 + j * 0.34, sx * 0.72 + 0.21, 4.42, 4.42 + j * 0.34, "lapis")
    B(-0.13, 3.75, 4.55, 0.13, 3.98, 5.05, G)
    B(-0.08, 3.9, 6.0, 0.08, 4.15, 6.35, "gold")
    # sable accumulé au pied du socle, blocs tombés
    for k in range(rng.randint(3, 6)):
        bx = x + rng.uniform(-0.3, w + 0.3)
        by = y + h + rng.uniform(-0.2, 0.6)
        sz = rng.uniform(0.18, 0.4)
        mb.box(bx, Y(by + sz), 0.0, bx + sz, Y(by), sz * 0.6, rng.choice(("wall_ext", "statue")), rot=rng.uniform(0, 1))


def lm_obelisk(mb, rect, rng):
    x, y, w, h = rect
    cx, cy = x + w / 2, Y(y + h / 2)
    hh = 4.2
    mb.box(cx - 0.45, cy - 0.45, 0.0, cx + 0.45, cy + 0.45, 0.3, "wall_ext")
    base = len(mb.V)
    pts = [(cx - 0.28, cy - 0.28, 0.3), (cx + 0.28, cy - 0.28, 0.3), (cx + 0.28, cy + 0.28, 0.3), (cx - 0.28, cy + 0.28, 0.3)]
    top = [(cx - 0.17, cy - 0.17, hh), (cx + 0.17, cy - 0.17, hh), (cx + 0.17, cy + 0.17, hh), (cx - 0.17, cy + 0.17, hh)]
    for i in range(4):
        mb.poly([pts[i], pts[(i + 1) % 4], top[(i + 1) % 4], top[i]], "wall_frieze",
                [(0, 0.3), (0.56, 0.3), (0.56, hh), (0, hh)])
    mb.poly([top[0], top[1], (cx, cy, hh + 0.45)], "gold")
    mb.poly([top[1], top[2], (cx, cy, hh + 0.45)], "gold")
    mb.poly([top[2], top[3], (cx, cy, hh + 0.45)], "gold_dark")
    mb.poly([top[3], top[0], (cx, cy, hh + 0.45)], "gold_dark")
    del base


def lm_palm(mb, rect, rng):
    """Palmier dattier : stipe annelé incliné, couronne dense de palmes en rubans pliés en V
    (deux pans : la lumière rasante éclaire l'un, l'autre reste à l'ombre), régimes de dattes."""
    x, y, w, h = rect
    cx, cy = x + w / 2 + rng.uniform(-0.15, 0.15), Y(y + h / 2) + rng.uniform(-0.15, 0.15)
    la = rng.uniform(0, math.tau)
    lean = rng.uniform(0.2, 0.7)
    hh = rng.uniform(4.0, 5.6)
    prev = (cx, cy, 0.0)
    for k in range(7):
        f = (k + 1) / 7
        p = (cx + math.cos(la) * lean * f * f, cy + math.sin(la) * lean * f * f, hh * f)
        mb.seg(prev, p, 0.19 * (1 - 0.35 * f), "palm_trunk", 7)
        prev = p
    top = prev
    nf = rng.randint(13, 17)
    for k in range(nf):
        a = k / nf * math.tau + rng.uniform(-0.18, 0.18)
        upper = k % 2 == 0
        L_ = rng.uniform(2.6, 3.5) * (0.8 if upper else 1.0)
        rise = 0.55 if upper else 0.25
        droop = 0.9 if upper else 1.4
        ca, sa = math.cos(a), math.sin(a)
        nx_, ny_ = -sa, ca
        prevc = None
        NS = 6
        for j in range(NS + 1):
            t = j / NS
            px_ = top[0] + ca * L_ * t
            py_ = top[1] + sa * L_ * t
            pz_ = top[2] + rise * math.sin(t * math.pi * 0.8) - droop * t * t
            wd = 0.5 * math.sin(min(1.0, t * 1.15 + 0.08) * math.pi) * (0.9 if upper else 1.0) + 0.02
            c = (px_, py_, pz_)
            w0 = wd * 0.35
            l_ = (px_ + nx_ * w0, py_ + ny_ * w0, pz_ - w0 * 0.4)
            r_ = (px_ - nx_ * w0, py_ - ny_ * w0, pz_ - w0 * 0.4)
            mat_ = "palm_leaf" if (k + j) % 3 else "palm_leaf2"
            if prevc is not None:
                pc, pl_, pr_ = prevc
                mb.poly([pc, c, l_, pl_], mat_)
                mb.poly([pr_, r_, c, pc], mat_)
                # folioles : dents triangulaires de part et d'autre (silhouette plumeuse)
                for q in (0.0, 0.5):
                    bx_ = pc[0] + (c[0] - pc[0]) * q
                    by_ = pc[1] + (c[1] - pc[1]) * q
                    bz_ = pc[2] + (c[2] - pc[2]) * q
                    fl_ = wd * 1.25
                    for sg in (1.0, -1.0):
                        tip = (bx_ + sg * nx_ * fl_ + ca * fl_ * 0.45, by_ + sg * ny_ * fl_ + sa * fl_ * 0.45, bz_ - fl_ * 0.55)
                        b2 = (bx_ + ca * L_ / NS * 0.45, by_ + sa * L_ / NS * 0.45, bz_ - 0.02)
                        mb.poly([(bx_, by_, bz_), b2, tip], "palm_leaf" if sg > 0 else "palm_leaf2")
            prevc = (c, l_, r_)
    for k in range(4):
        mb.sphere(top[0] + rng.uniform(-0.25, 0.25), top[1] + rng.uniform(-0.25, 0.25), top[2] - 0.25, 0.14, "clay_dark", 1)


def lm_rock(mb, rect, rng, small=False):
    x, y, w, h = rect
    n = 2 if small else rng.randint(3, 5)
    for k in range(n):
        cx = x + rng.uniform(0.3, max(0.31, w - 0.3))
        cy = y + rng.uniform(0.3, max(0.31, h - 0.3))
        r = rng.uniform(0.35, 0.6) if small else rng.uniform(0.6, 1.1)
        mb.sphere(cx, Y(cy), r * 0.3, r, rng.choice(["rock", "rock_dark"]), 3, 1.0, 0.9, 0.75, jitter=0.04, nscale=0.9, rng=rng)
    st = 0
    del st


def lm_ruin(mb, rect, rng):
    x, y, w, h = rect
    # murs brisés à demi ensablés + tronçons de colonnes
    for k in range(rng.randint(2, 4)):
        wx = x + rng.uniform(0.0, w - 1.0)
        wy = y + rng.uniform(0.0, h - 0.5)
        L_ = rng.uniform(0.8, 1.6)
        hz = rng.uniform(0.4, 1.1)
        if rng.random() < 0.5:
            mb.box(wx, Y(wy + 0.35), -0.1, wx + L_, Y(wy), hz, "wall_ext")
        else:
            mb.box(wx, Y(wy + L_), -0.1, wx + 0.35, Y(wy), hz, "wall_ext")
    for k in range(rng.randint(1, 3)):
        cx = x + rng.uniform(0.4, w - 0.4)
        cy = y + rng.uniform(0.4, h - 0.4)
        mb.cyl(cx, Y(cy), 0.0, rng.uniform(0.3, 0.9), 0.25, "stone_lit", 10)
    mb.sphere(x + w / 2, Y(y + h / 2), -0.2, max(w, h) * 0.7, "sand", 3, 1.2, 1.0, 0.3)


def lm_dune(mb, rect, rng):
    x, y, w, h = rect
    mb.sphere(x + w / 2, Y(y + h / 2), -0.5 * w * 0.12, w * 0.9, "sand", 3, 1.0, h / w * 1.1, 0.16, nscale=0.35, rng=rng)


def build_landmarks():
    for i, lm in enumerate(LANDMARKS):
        kind = lm["kind"]
        rect = lm["rect"]
        rng = random.Random(i * 331 + SEED)
        mb = MB()
        if kind == "pyramid_big":
            lm_pyramid(mb, rect, rng, True)
        elif kind == "pyramid_small":
            lm_pyramid(mb, rect, rng, False)
        elif kind == "sphinx":
            lm_sphinx(mb, rect, rng)
        elif kind == "obelisk":
            lm_obelisk(mb, rect, rng)
        elif kind == "palm":
            lm_palm(mb, rect, rng)
        elif kind == "rock":
            lm_rock(mb, rect, rng)
        elif kind == "rock_small":
            lm_rock(mb, rect, rng, True)
        elif kind == "ruin":
            lm_ruin(mb, rect, rng)
        elif kind == "dune":
            lm_dune(mb, rect, rng)
        else:
            lm_rock(mb, rect, rng)
        mb.to_object("lm_%s_%d" % (kind, i), "world", smooth=(kind == "dune"))
    # marge rendue hors jeu : amas de rochers et palmiers (bords chargés comme la planche)
    mg = MB()
    rng = random.Random(SEED * 17 + 3)
    for k in range(130):
        side = rng.randint(0, 3)
        if side == 0:
            cx, cy = rng.uniform(-MARGIN, W + MARGIN), rng.uniform(-MARGIN + 0.5, -0.6)
        elif side == 1:
            cx, cy = rng.uniform(-MARGIN, W + MARGIN), rng.uniform(H + 0.6, H + MARGIN - 0.5)
        elif side == 2:
            cx, cy = rng.uniform(-MARGIN + 0.5, -0.6), rng.uniform(-MARGIN, H + MARGIN)
        else:
            cx, cy = rng.uniform(W + 0.6, W + MARGIN - 0.5), rng.uniform(-MARGIN, H + MARGIN)
        q = rng.random()
        if q < 0.28:
            lm_palm(mg, [cx - 0.5, cy - 0.5, 1, 1], rng)
        elif q < 0.42:
            lm_ruin(mg, [cx - 1.2, cy - 1.0, 2.4, 2.0], rng)
        else:
            lm_rock(mg, [cx - 1.0, cy - 1.0, 2.0, 2.0], rng, rng.random() < 0.4)
    mg.to_object("_margin", "world")


# ======================================================================= décors (prop_spawns)
BIG = {"eg_sarcophagus_big": (2, 1), "eg_offering_table": (2, 1), "eg_tent": (2, 2)}


def _rect_of_spawn(s):
    sx, sy = s.get("size", [1, 1])
    if [sx, sy] == [1, 1] and s.get("kind") in BIG:
        sx, sy = BIG[s["kind"]]
    x0 = s["cell"][0] - (sx - 1) // 2
    return [x0, s["cell"][1] - sy + 1, sx, sy]


class Local:
    """Repère local d'un décor adossé : u le long du mur (centré), v depuis le mur (0) vers la
    salle, z vers le haut."""

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

    def cyl(self, mb, u, v, z0, z1, r, mat, seg=12, r2=None):
        x, y = self.p(u, v)
        mb.cyl(x, y, z0, z1, r, mat, seg, r2=r2)

    def sph(self, mb, u, v, z, r, mat, sub=1, sz=1.0):
        x, y = self.p(u, v)
        mb.sphere(x, y, z, r, mat, sub, 1.0, 1.0, sz)


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


def prop(mb, kind, L, rng):
    A, D = L.A, L.D
    a = A / 2 - 0.06
    d = D - 0.08
    k = kind
    if k == "eg_brazier":
        for j in range(3):
            an = j / 3 * math.tau + 0.3
            u, v = math.cos(an) * 0.22, D / 2 + math.sin(an) * 0.22
            L.cyl(mb, u, v, 0.0, 0.7, 0.035, "bronze", 6)
        L.cyl(mb, 0.0, D / 2, 0.65, 0.95, 0.2, "bronze", 12, r2=0.32)
        L.cyl(mb, 0.0, D / 2, 0.93, 0.98, 0.26, "coal", 10)
        L.sph(mb, 0.0, D / 2, 1.15, 0.2, "flame", 1, 1.6)
        L.sph(mb, 0.0, D / 2, 1.12, 0.1, "flame_core", 1, 1.5)
        x, y = L.p(0.0, D / 2)
        TORCH_LIGHTS.append((x, y, 1.4))
    elif k == "eg_statue":
        L.box(mb, -0.35, 0.05, 0.0, 0.35, 0.75, 0.25, "wall_top")
        L.box(mb, -0.22, 0.12, 0.25, 0.22, 0.6, 1.05, "basalt")
        L.box(mb, -0.25, 0.4, 0.25, 0.25, 0.72, 0.65, "basalt")
        L.sph(mb, 0.0, 0.36, 1.25, 0.19, "basalt", 1, 1.1)
        L.box(mb, -0.24, 0.1, 0.95, 0.24, 0.62, 1.05, "gold")
        for su in (-0.1, 0.1):
            L.box(mb, su - 0.035, 0.3, 1.4, su + 0.035, 0.4, 1.7, "basalt")
    elif k == "eg_canopic_jars":
        L.box(mb, -a, 0.05, 0.0, a, 0.45, 0.06, "wall_top")
        for j, u in enumerate((-0.36, -0.12, 0.12, 0.36)):
            L.cyl(mb, u, 0.25, 0.06, 0.42, 0.1, "limestone", 8)
            L.sph(mb, u, 0.25, 0.5, 0.11, ["clay", "basalt", "bone", "limestone"][j], 1)
    elif k == "eg_sarcophagus_big":
        L.box(mb, -a, 0.1, 0.0, a, d, 0.65, "wall_ext")
        L.box(mb, -a + 0.1, 0.18, 0.65, a - 0.1, d - 0.08, 0.95, "gold")
        L.box(mb, -a + 0.1, 0.18, 0.9, -a + 0.75, d - 0.08, 1.05, "lapis")
        L.sph(mb, -a + 0.45, D / 2, 1.05, 0.2, "gold_dark", 1, 0.8)
        for j in range(3):
            L.box(mb, 0.0 + j * 0.3, 0.15, 0.95, 0.08 + j * 0.3, d - 0.05, 1.0, "lapis")
    elif k == "eg_offering_table":
        L.box(mb, -a, 0.1, 0.7, a, d, 0.82, "limestone")
        for su in (-a + 0.25, a - 0.25):
            L.box(mb, su - 0.15, 0.25, 0.0, su + 0.15, d - 0.15, 0.7, "wall_ext")
        L.sph(mb, -0.35, D / 2, 0.92, 0.1, "linen_red", 1)
        L.cyl(mb, 0.3, D / 2 + 0.1, 0.82, 1.1, 0.1, "clay", 8)
        L.box(mb, 0.55, D / 2 - 0.2, 0.82, 0.8, D / 2, 0.9, "gold")
        L.cyl(mb, 0.0, D / 2 - 0.2, 0.82, 1.1, 0.035, "linen", 6)
        L.sph(mb, 0.0, D / 2 - 0.2, 1.18, 0.06, "flame", 1, 1.6)
    elif k == "eg_embalming_table":
        L.box(mb, -a, 0.15, 0.62, a, d, 0.72, "basalt")
        for su in (-a + 0.2, a - 0.2):
            L.box(mb, su - 0.1, 0.3, 0.0, su + 0.1, d - 0.15, 0.62, "basalt")
        L.cyl(mb, -0.6, D / 2, 0.88, 0.0, 0.17, "linen", 10)
        mb.V[-1]  # no-op
        x0, y0 = L.p(-a + 0.2, D / 2)
        x1, y1 = L.p(a - 0.2, D / 2)
        mb.seg((x0, y0, 0.9), (x1, y1, 0.9), 0.17, "linen", 10)
        L.sph(mb, -a + 0.15, D / 2, 0.9, 0.17, "linen", 1)
    elif k == "eg_weapon_rack":
        L.box(mb, -a, 0.05, 0.0, a, 0.2, 0.1, "wood_dark")
        for su in (-a + 0.08, a - 0.08):
            L.box(mb, su - 0.04, 0.08, 0.0, su + 0.04, 0.18, 1.1, "wood")
        L.box(mb, -a, 0.08, 1.0, a, 0.18, 1.08, "wood_dark")
        for j in range(4):
            u = -a + 0.2 + j * (A - 0.4) / 3
            L.cyl(mb, u, 0.12, 0.05, 1.5, 0.025, "wood", 6)
            L.box(mb, u - 0.03, 0.1, 1.5, u + 0.03, 0.14, 1.7, "bronze")
        L.box(mb, 0.1, 0.03, 0.3, 0.6, 0.08, 0.9, "bronze")
    elif k == "eg_bench":
        L.box(mb, -a, 0.1, 0.38, a, 0.55, 0.5, "stone_lit")
        for su in (-a + 0.15, a - 0.15):
            L.box(mb, su - 0.1, 0.12, 0.0, su + 0.1, 0.52, 0.38, "wall_ext")
        L.box(mb, -0.3, 0.12, 0.5, 0.3, 0.5, 0.58, "linen_red")
    elif k == "eg_scroll_shelf":
        L.box(mb, -a, 0.03, 0.0, a, 0.08, 1.5, "wood_dark")
        for su in (-a, a - 0.05):
            L.box(mb, su, 0.03, 0.0, su + 0.05, 0.5, 1.5, "wood")
        for z in (0.1, 0.55, 1.0, 1.45):
            L.box(mb, -a, 0.03, z, a, 0.5, z + 0.05, "wood")
            if z < 1.4:
                u = -a + 0.08
                while u < a - 0.12:
                    L.cyl(mb, u, 0.27, z + 0.11, 0.0, 0.0, "linen", 6)
                    x0, y0 = L.p(u, 0.08)
                    x1, y1 = L.p(u, 0.46)
                    mb.seg((x0, y0, z + 0.11), (x1, y1, z + 0.11), 0.055, rng.choice(["linen", "clay", "linen_red"]), 6)
                    u += 0.14
    elif k == "eg_cactus":
        x, y = L.p(0.0, D / 2)
        mb.cyl(x, y, 0.0, 1.3, 0.14, "palm_leaf", 8)
        for j in range(2):
            an = j * math.pi + 0.4
            mb.seg((x + math.cos(an) * 0.14, y + math.sin(an) * 0.14, 0.55 + j * 0.2), (x + math.cos(an) * 0.4, y + math.sin(an) * 0.4, 0.65 + j * 0.2), 0.08, "palm_leaf", 6)
            mb.seg((x + math.cos(an) * 0.4, y + math.sin(an) * 0.4, 0.65 + j * 0.2), (x + math.cos(an) * 0.4, y + math.sin(an) * 0.4, 1.05 + j * 0.2), 0.08, "palm_leaf", 6)
    elif k == "eg_tent":
        w_, d_ = A - 0.3, D - 0.5
        x0, y0 = L.p(-w_ / 2, 0.15)
        x1, y1 = L.p(w_ / 2, 0.15 + d_)
        xa, xb = min(x0, x1), max(x0, x1)
        ya, yb = min(y0, y1), max(y0, y1)
        cx, cy = (xa + xb) / 2, (ya + yb) / 2
        hz = 1.5
        mat = rng.choice(["linen", "linen_red"])
        mb.poly([(xa, ya, 0.0), (xb, ya, 0.0), (cx + 0.3, cy, hz), (cx - 0.3, cy, hz)], mat)
        mb.poly([(xb, yb, 0.0), (xa, yb, 0.0), (cx - 0.3, cy, hz), (cx + 0.3, cy, hz)], mat)
        mb.poly([(xb, ya, 0.0), (xb, yb, 0.0), (cx + 0.3, cy, hz)], mat)
        mb.poly([(xa, yb, 0.0), (xa, ya, 0.0), (cx - 0.3, cy, hz)], mat)
        mb.cyl(cx, cy, 0.0, hz + 0.3, 0.05, "wood", 6)
        mb.box(xa - 0.1, yb - 0.5, 0.0, xa + 0.4, yb, 0.4, "clay")
        mb.cyl(xb - 0.3, ya + 0.3, 0.0, 0.4, 0.17, "clay", 8, r2=0.22)
    elif k == "eg_rubble":
        for j in range(rng.randint(4, 7)):
            s = rng.uniform(0.1, 0.28)
            L.box(mb, rng.uniform(-a + 0.1, a - 0.1), rng.uniform(0.1, d - 0.1), 0.0, 0, 0, 0, "wall_ext") if False else None
            x, y = L.p(rng.uniform(-a + 0.15, a - 0.15), rng.uniform(0.15, d - 0.15))
            mb.box(x - s / 2, y - s / 2, 0.0, x + s / 2, y + s / 2, s * 0.6, rng.choice(["wall_ext", "stone_lit", "rock"]), rot=rng.uniform(0, 1.5))
    elif k == "eg_spikes":
        x, y = L.p(0.0, D / 2)
        mb.box(x - 0.45, y - 0.45, 0.0, x + 0.45, y + 0.45, 0.02, "basalt")
        for i in range(3):
            for j in range(3):
                mb.cyl(x - 0.3 + i * 0.3, y - 0.3 + j * 0.3, 0.02, 0.5, 0.05, "bronze", 6, r2=0.0)
    elif k == "eg_bones":
        x, y = L.p(0.0, D / 2)
        mb.sphere(x - 0.25, y, 0.12, 0.14, "bone", 1, 1.1, 1.0, 0.9)
        for j in range(4):
            mb.seg((x + j * 0.12, y - 0.2, 0.03), (x + j * 0.12 + 0.03, y + 0.2, 0.03), 0.025, "bone", 5)
        mb.seg((x + 0.1, y - 0.35, 0.04), (x + 0.6, y - 0.2, 0.04), 0.04, "bone", 6)
    else:
        L.box(mb, -a, 0.1, 0.0, a, d, 0.5, "wall_ext")


def build_props():
    mb = MB()
    flat = MB()
    for s in LAYOUT.get("prop_spawns", []):
        kind = s["kind"]
        rect = _rect_of_spawn(s)
        back = back_side(rect)
        x, y = s["cell"]
        rng = random.Random(x * 7349 + y * 1663 + SEED)
        L = Local(rect, back)
        tgt = flat if kind in ("eg_spikes", "eg_bones", "eg_rubble") else mb
        st = len(tgt.V)
        prop(tgt, kind, L, rng)
        cells_fit(tgt, st, rect, margin=0.05)
    mb.to_object("props", "world")
    flat.to_object("_flat", "world")


# ======================================================================= détails au sol, oasis, campement
_DECAL_N = [0]


def decal(mb, cx, cy, r, mat):
    # hauteur légèrement différente par décalque : jamais deux surfaces coplanaires superposées
    _DECAL_N[0] += 1
    z = 0.003 + (_DECAL_N[0] % 37) * 0.0004
    mb.poly([(cx - r, Y(cy + r), z), (cx + r, Y(cy + r), z), (cx + r, Y(cy - r), z), (cx - r, Y(cy - r), z)], mat,
            [(0, 0), (1, 0), (1, 1), (0, 1)])


PATH_DONE = set()


def build_details():
    det = MB()
    rng = random.Random(SEED * 11)
    for y in range(H):
        for x in range(W):
            if not walk(x, y) or (x, y) in GAME_CELLS:
                continue
            role = role_at(x, y)
            r_ = rng.random()
            if tile(x, y) == 2 and r_ < 0.15:
                decal(det, x + rng.uniform(0.3, 0.7), y + rng.uniform(0.3, 0.7), rng.uniform(0.5, 1.2), "stain")
            elif tile(x, y) == 1 and r_ < 0.5:
                # pierres, tessons, blocs à demi ensablés, tambours de colonnes, touffes sèches
                kx, ky = x + rng.uniform(0.15, 0.85), y + rng.uniform(0.15, 0.85)
                q = rng.random()
                if q < 0.5:
                    for j in range(rng.randint(1, 4)):
                        s = rng.uniform(0.06, 0.2)
                        jx, jy = kx + rng.uniform(-0.3, 0.3), ky + rng.uniform(-0.3, 0.3)
                        det.sphere(jx, Y(jy), 0.0, s, rng.choice(["rock", "rock_dark", "stone_lit", "clay"]), 1, 1.0, 0.85, 0.6, jitter=0.03, rng=rng)
                elif q < 0.6:
                    sz = rng.uniform(0.3, 0.6)
                    det.box(kx - sz / 2, Y(ky + sz * 0.4), -0.08, kx + sz / 2, Y(ky - sz * 0.4), sz * 0.45, rng.choice(["wall_ext", "wall_top", "granite"]), rot=rng.uniform(0, 1.5), tilt=("X", rng.uniform(-0.25, 0.25)))
                elif q < 0.68:
                    # tronçon de colonne arasé (tambour bas)
                    det.cyl(kx, Y(ky), -0.02, rng.uniform(0.18, 0.34), rng.uniform(0.22, 0.3), rng.choice(("stone_lit", "wall_ext")), 12)
                elif q < 0.78:
                    det.seg((kx - 0.35, Y(ky), 0.2), (kx + 0.35, Y(ky + rng.uniform(-0.3, 0.3)), 0.2), 0.24, rng.choice(["stone_lit", "wall_ext"]), 10)
                elif q < 0.88:
                    # touffe d'arbustes secs / verts (boules irrégulières)
                    for j in range(rng.randint(2, 4)):
                        det.sphere(kx + rng.uniform(-0.2, 0.2), Y(ky + rng.uniform(-0.2, 0.2)), 0.05, rng.uniform(0.12, 0.22),
                                   rng.choice(("palm_leaf", "palm_leaf2", "palm_trunk")), 1, 1.0, 1.0, 0.7, jitter=0.25, rng=rng)
                elif q < 0.93:
                    for j in range(rng.randint(3, 6)):
                        a_ = rng.uniform(0, math.tau)
                        det.seg((kx, Y(ky), 0.0), (kx + math.cos(a_) * 0.3, Y(ky) + math.sin(a_) * 0.3, rng.uniform(0.15, 0.3)), 0.03, rng.choice(["palm_trunk", "palm_leaf2"]), 4)
                else:
                    det.sphere(kx, Y(ky), 0.0, rng.uniform(0.12, 0.2), "clay", 2, 1.0, 1.0, 1.1)
                    det.box(kx + 0.15, Y(ky + 0.1), 0.0, kx + 0.3, Y(ky), 0.05, "clay_dark", rot=rng.uniform(0, 1))
            elif tile(x, y) == 2 and role in ("tomb", "scribe", "offering", "treasury") and r_ < 0.18:
                # tapis / nattes colorés dans les chambres
                det.box(x + 0.12, Y(y + 0.88), 0.003 + rng.random() * 0.004, x + 0.88, Y(y + 0.12), 0.012, rng.choice(["linen_red", "linen", "clay_dark"]))
            elif role in ("inner_court", "court", "avenue", "gate", "hypostyle") and r_ < 0.14:
                # sable soufflé sur le dallage (plaque plate) ou fissure
                if r_ < 0.05:
                    decal(det, x + rng.uniform(0.3, 0.7), y + rng.uniform(0.3, 0.7), rng.uniform(0.4, 0.9), "sand_drift")
                else:
                    kx, ky = x + rng.uniform(0.1, 0.5), y + rng.uniform(0.2, 0.8)
                    det.box(kx, Y(ky + 0.04), 0.0, kx + rng.uniform(0.3, 0.6), Y(ky), 0.006, "crack", rot=rng.uniform(-0.6, 0.6))
    # petit mobilier des chambres contre les murs (bas : ne bloque pas) : jarres, vases, or
    for y in range(H):
        for x in range(W):
            if tile(x, y) != 2 or (x, y) in GAME_CELLS:
                continue
            role = role_at(x, y)
            if role in ("inner_court", "court", "hypostyle", "gate", "sanctuary"):
                continue
            nwall = [(dx, dy) for _, dx, dy in SIDES if tile(x + dx, y + dy) == 3]
            if not nwall or rng.random() > (0.72 if role in ("treasury", "tomb", "offering") else 0.45):
                continue
            dx, dy = nwall[0]
            bx, by = x + 0.5 + dx * 0.3, y + 0.5 + dy * 0.3
            for j in range(rng.randint(1, 3)):
                qx, qy = bx + rng.uniform(-0.3, 0.3), by + rng.uniform(-0.3, 0.3)
                if role in ("treasury", "tomb") and rng.random() < 0.55:
                    det.sphere(qx, Y(qy), 0.0, rng.uniform(0.1, 0.16), "gold", 1, 1.3, 1.0, 0.75)
                elif role == "scribe" and rng.random() < 0.5:
                    det.seg((qx - 0.15, Y(qy), 0.05), (qx + 0.15, Y(qy), 0.05), 0.045, "linen", 6)
                else:
                    r_ = rng.uniform(0.07, 0.1)
                    det.cyl(qx, Y(qy), 0.0, 0.13, r_, rng.choice(["clay", "clay_dark", "limestone"]), 8, r2=r_ * 0.6)
    # sable : plaques plus sombres (sable tassé), dalles ensablées éparses
    for k in range(160):
        cx, cy = rng.uniform(1, W - 1), rng.uniform(1, H - 1)
        if not walk(int(cx), int(cy)) or tile(int(cx), int(cy)) != 1:
            continue
        decal(det, cx, cy, rng.uniform(1.2, 3.0), "sand_shade")
    # débris ensablés : grappes de blocs de grès cassés, tronçons de colonnes couchés (bas, non
    # bloquants), éclats de poterie et pierres
    for k in range(200):
        cx, cy = rng.uniform(2, W - 2), rng.uniform(2, H - 2)
        if tile(int(cx), int(cy)) != 1 or paving_of(int(cx), int(cy)) is not None or (int(cx), int(cy)) in GAME_CELLS:
            continue
        for j in range(rng.randint(3, 7)):
            qx, qy = cx + rng.uniform(-1.2, 1.2), cy + rng.uniform(-1.2, 1.2)
            if tile(int(qx), int(qy)) != 1 or (int(qx), int(qy)) in GAME_CELLS:
                continue
            r2 = rng.random()
            if r2 < 0.25:
                ln = rng.uniform(0.6, 1.2)
                a_ = rng.uniform(0, math.pi)
                det.seg((qx, Y(qy), 0.07), (qx + math.cos(a_) * ln, Y(qy) + math.sin(a_) * ln, 0.07), 0.08, "stone_lit", 8)
            elif r2 < 0.7:
                s_ = rng.uniform(0.1, 0.26)
                det.sphere(qx, Y(qy), -0.02, s_, rng.choice(["wall_ext", "rock", "stone_lit"]), 1, 1.2, 1.0, 0.55, jitter=0.12, rng=rng)
            else:
                det.sphere(qx, Y(qy), 0.0, rng.uniform(0.06, 0.14), rng.choice(["rock", "rock_dark", "clay"]), 1, 1.0, 1.0, 0.7)
        decal(det, cx, cy, rng.uniform(1.0, 2.0), "sand_shade")
    for k in range(50):
        cx, cy = rng.uniform(1, W - 1), rng.uniform(1, H - 1)
        if not walk(int(cx), int(cy)) or tile(int(cx), int(cy)) != 1 or (int(cx), int(cy)) in GAME_CELLS:
            continue
        s_ = rng.uniform(0.35, 0.8)
        det.box(cx - s_ / 2, Y(cy + s_ / 2), -0.01, cx + s_ / 2, Y(cy - s_ / 2), rng.uniform(0.02, 0.08), rng.choice(["wall_top", "slabs_big", "stone_lit"]), rot=rng.uniform(0, 1.5))
    # chemins pavés (2 cases) des portails vers l'avenue
    for (a_, b_) in PATHS:
        ax_, ay_ = a_
        bx_, by_ = b_
        n = int(max(abs(bx_ - ax_), abs(by_ - ay_))) + 1
        for i in range(n + 1):
            f = i / max(n, 1)
            qx, qy = ax_ + (bx_ - ax_) * f + 0.5, ay_ + (by_ - ay_) * f + 0.5
            for k in range(3):
                ox, oy = rng.uniform(-1.0, 1.0), rng.uniform(-0.5, 0.5)
                c_ = (int(qx + ox), int(qy + oy))
                if tile(*c_) != 1 or paving_of(*c_) is not None or c_ in PATH_DONE:
                    continue
                PATH_DONE.add(c_)
                det.box(qx + ox - 0.4, Y(qy + oy + 0.4), -0.01, qx + ox + 0.4, Y(qy + oy - 0.4), rng.uniform(0.012, 0.03), rng.choice(["slabs_big", "wall_top"]), rot=rng.uniform(-0.15, 0.15))
    # cour à piliers du grand temple : bandeau de dalles sombres et filet d'or autour du sanctuaire
    sx_, sy_, sw_, sh_ = SANCT
    for (ins, mat_, z_) in ((-1.0, "slabs_dark", 0.006), (-1.55, "gold_dark", 0.009), (-1.7, "slabs_dark", 0.007)):
        x0_, y0_, x1_, y1_ = sx_ + ins, sy_ + ins, sx_ + sw_ - ins, sy_ + sh_ - ins
        for (a0, b0, a1, b1) in ((x0_, y0_, x1_, y0_ + 0.12), (x0_, y1_ - 0.12, x1_, y1_), (x0_, y0_, x0_ + 0.12, y1_), (x1_ - 0.12, y0_, x1_, y1_)):
            det.box(a0, Y(b1), 0.0, a1, Y(b0), z_, mat_)
    # sanctuaire à ciel ouvert (planche) : carrés concentriques de dalles sombres filetés d'or,
    # dais central à l'ankh d'or lumineux, 4 torches sur hampes aux points cardinaux
    scx, scy = sx_ + sw_ / 2, sy_ + sh_ / 2
    for (hw, mat_, z_) in ((4.1, "slabs_dark", 0.005), (3.95, "gold_dark", 0.008), (3.75, "slabs_dark", 0.006),
                           (2.6, "gold_dark", 0.009), (2.45, "slabs_dark", 0.007)):
        x0_, y0_, x1_, y1_ = scx - hw, scy - hw, scx + hw, scy + hw
        tk = 0.15
        for (a0, b0, a1, b1) in ((x0_, y0_, x1_, y0_ + tk), (x0_, y1_ - tk, x1_, y1_), (x0_, y0_, x0_ + tk, y1_), (x1_ - tk, y0_, x1_, y1_)):
            det.box(a0, Y(b1), 0.0, a1, Y(b0), z_, mat_)
    det.box(scx - 1.7, Y(scy + 1.7), 0.0, scx + 1.7, Y(scy - 1.7), 0.1, "slabs_dark")
    det.box(scx - 1.35, Y(scy + 1.35), 0.1, scx + 1.35, Y(scy - 1.35), 0.2, "granite")
    det.box(scx - 1.2, Y(scy + 1.2), 0.2, scx + 1.2, Y(scy - 1.2), 0.215, "gold_glow")
    det.box(scx - 1.05, Y(scy + 1.05), 0.2, scx + 1.05, Y(scy - 1.05), 0.222, "plaque")
    # ankh : boucle (anneau), traverse, hampe
    for k in range(16):
        a0 = k / 16 * math.tau
        a1 = (k + 1) / 16 * math.tau
        for rr, r2 in ((0.36, 0.22),):
            det.poly([(scx + math.cos(a0) * r2, Y(scy - 0.45) + math.sin(a0) * r2 * 1.25, 0.24),
                      (scx + math.cos(a1) * r2, Y(scy - 0.45) + math.sin(a1) * r2 * 1.25, 0.24),
                      (scx + math.cos(a1) * rr, Y(scy - 0.45) + math.sin(a1) * rr * 1.25, 0.24),
                      (scx + math.cos(a0) * rr, Y(scy - 0.45) + math.sin(a0) * rr * 1.25, 0.24)], "gold_glow")
    det.box(scx - 0.55, Y(scy + 0.08), 0.222, scx + 0.55, Y(scy - 0.08), 0.24, "gold_glow")
    det.box(scx - 0.08, Y(scy + 0.9), 0.222, scx + 0.08, Y(scy - 0.02), 0.24, "gold_glow")
    for (tx, ty) in ((scx, scy - 2.9), (scx, scy + 2.9), (scx - 2.9, scy), (scx + 2.9, scy)):
        det.cyl(tx, Y(ty), 0.0, 0.1, 0.22, "bronze", 10)
        det.cyl(tx, Y(ty), 0.1, 1.15, 0.05, "bronze", 8)
        det.cyl(tx, Y(ty), 1.15, 1.35, 0.17, "bronze", 10, r2=0.1)
        det.sphere(tx, Y(ty), 1.52, 0.2, "flame", 1, 1.0, 1.0, 1.5)
        det.sphere(tx, Y(ty), 1.5, 0.11, "flame_core", 1, 1.0, 1.0, 1.4)
        TORCH_LIGHTS.append((tx, Y(ty), 1.75, 0.35))
    TORCH_LIGHTS.append((scx, Y(scy), 0.6, 0.25))
    # escalier monumental entre les sphinx (marches basses, non bloquantes) et balustrades
    stx, sty, stw, sth = STAIRS_R
    for i in range(sth * 2):
        yy0 = sty + sth - (i + 1) * 0.5
        det.box(stx, Y(yy0 + 0.5), 0.0, stx + stw, Y(yy0), 0.015 + i * 0.015, "slabs_big" if i % 2 == 0 else "wall_top")
    for bx in (stx - 0.05, stx + stw - 0.3):
        det.box(bx, Y(sty + sth), 0.0, bx + 0.35, Y(sty - 0.5), 0.14, "wall_ext")
    # portail de bois entre les sphinx (poteaux sur les socles, linteau haut : ne bloque pas)
    if len(LANDMARKS) >= 2:
        sph = [lm for lm in LANDMARKS if lm["kind"] == "sphinx"]
        if len(sph) == 2:
            (ax, ay, aw, ah), (bx, by, bw, bh) = sph[0]["rect"], sph[1]["rect"]
            gy = ay + ah - 1
            px0, px1 = ax + aw - 0.5, bx + 0.5
            for px in (px0, px1):
                det.cyl(px, Y(gy + 0.5), 0.0, 3.0, 0.14, "wood_dark", 8)
                det.box(px - 0.2, Y(gy + 0.7), 2.8, px + 0.2, Y(gy + 0.3), 3.2, "gold_dark")
            det.box(px0, Y(gy + 0.62), 2.6, px1, Y(gy + 0.38), 2.85, "wood_dark")
            for k in range(1, 8):
                fx = px0 + (px1 - px0) * k / 8
                det.box(fx - 0.03, Y(gy + 0.55), 1.6, fx + 0.03, Y(gy + 0.45), 2.6, "wood", )
    # avenue : bande centrale de dalles sombres + dalles brisées
    ax, ay, aw, ah = AVENUE
    det.box(ax + aw / 2 - 1.5, Y(ay + ah - 1), 0.0, ax + aw / 2 + 1.5, Y(ay), 0.006, "slabs_dark")
    # oasis : mare peu profonde, roseaux
    op = C.get("oasis_pool")
    if op:
        x, y, w, h = op
        det.sphere(x + w / 2, Y(y + h / 2), -0.1, max(w, h) * 0.6, "sand_dark", 1, 1.0, h / w if w else 1.0, 0.25)
        det.cyl(x + w / 2, Y(y + h / 2), -0.03, 0.01, min(w, h) * 0.45, "water", 24)
        prng = random.Random(SEED)
        for k in range(14):
            an = k / 14 * math.tau
            rx = x + w / 2 + math.cos(an) * min(w, h) * 0.5
            ry = Y(y + h / 2) + math.sin(an) * min(w, h) * 0.5
            det.seg((rx, ry, 0.0), (rx + prng.uniform(-0.1, 0.1), ry + prng.uniform(-0.1, 0.1), prng.uniform(0.5, 0.9)), 0.03, "palm_leaf", 4)
    # --- intérieurs meublés (décor non bloquant, adossé aux murs) ---
    fur = MB()
    frng = random.Random(SEED * 13 + 7)
    FURN_ROLES = ("tomb", "treasury", "offering", "statue_hall", "embalming", "guard_hall", "scribe", "trap_hall")
    for r in ROOMS:
        role = (r.get("tags") or ["desert"])[0]
        if role not in FURN_ROLES:
            continue
        rx, ry, rw, rh = r["rect"]
        # dallage à motifs au centre (bordure dorée, champ sombre, losange lapis)
        iw, ih = rw - 2, rh - 2
        if iw >= 3 and ih >= 3 and role in ("tomb", "treasury", "offering", "statue_hall"):
            cx, cy = rx + rw / 2, ry + rh / 2
            hw, hh = min(iw, 5) / 2 - 0.3, min(ih, 5) / 2 - 0.3
            fur.box(cx - hw, Y(cy + hh), -0.01, cx + hw, Y(cy - hh), 0.007, "gold_dark")
            fur.box(cx - hw + 0.14, Y(cy + hh - 0.14), 0.0, cx + hw - 0.14, Y(cy - hh + 0.14), 0.0095, "slabs_dark")
            fur.box(cx - 0.45, Y(cy + 0.45), 0.0, cx + 0.45, Y(cy - 0.45), 0.012, "lapis" if role != "treasury" else "gold", rot=0.785)
        for yy in range(ry, ry + rh):
            for xx in range(rx, rx + rw):
                if tile(xx, yy) != 2 or (xx, yy) in GAME_CELLS:
                    continue
                nw_ = [(dx, dy) for _, dx, dy in SIDES if tile(xx + dx, yy + dy) == 3]
                if not nw_ or frng.random() > 0.3:
                    continue
                dx, dy = nw_[0]
                qx, qy = xx + 0.5 + dx * 0.28, yy + 0.5 + dy * 0.28
                q = frng.random()
                if role in ("statue_hall", "tomb") and q < 0.35:
                    # statue assise adossée (socle, siège, corps, tête au némès)
                    fur.box(qx - 0.3, Y(qy + 0.3), 0.0, qx + 0.3, Y(qy - 0.3), 0.16, "granite")
                    fur.box(qx - 0.22, Y(qy + 0.22), 0.16, qx + 0.22, Y(qy - 0.22), 0.62, "granite_lit")
                    fur.box(qx - 0.24 - dx * 0.0, Y(qy + 0.24), 0.16, qx + 0.24, Y(qy - 0.24), 0.36, "granite")
                    fur.sphere(qx, Y(qy), 0.8, 0.16, "granite_lit", 2)
                    fur.sphere(qx + dx * 0.05, Y(qy + dy * 0.05), 0.84, 0.2, "gold_dark", 2, 1.15, 1.0, 0.8)
                elif role in ("treasury", "tomb", "offering") and q < 0.7:
                    # coffre doré ou vase d'or
                    if frng.random() < 0.5:
                        fur.box(qx - 0.2, Y(qy + 0.13), 0.0, qx + 0.2, Y(qy - 0.13), 0.2, "gold_dark", rot=0.0)
                        fur.box(qx - 0.21, Y(qy + 0.14), 0.2, qx + 0.21, Y(qy - 0.14), 0.25, "gold")
                    else:
                        fur.cyl(qx, Y(qy), 0.0, 0.32, 0.11, "gold", 10, r2=0.07)
                        fur.sphere(qx, Y(qy), 0.14, 0.12, "gold", 2)
                elif q < 0.85:
                    # brasero de bronze (braises)
                    fur.cyl(qx, Y(qy), 0.0, 0.28, 0.05, "bronze", 8)
                    fur.cyl(qx, Y(qy), 0.28, 0.36, 0.16, "bronze", 10, r2=0.2)
                    fur.cyl(qx, Y(qy), 0.34, 0.37, 0.15, "coal", 10)
                else:
                    # colonne engagée
                    fur.cyl(qx, Y(qy), 0.0, 1.0, 0.14, "stone_lit", 10)
                    fur.cyl(qx, Y(qy), 1.0, 1.08, 0.2, "wall_top", 10)
    fur.to_object("_furniture", "world")
    # sable qui entre par les portes (langues de sable de part et d'autre du seuil)
    for (dx_, dy_) in DOOR_CELLS:
        for ox, oy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            c_ = (dx_ + ox, dy_ + oy)
            if tile(*c_) in (1, 2) and rng.random() < 0.8:
                decal(det, c_[0] + 0.5 - ox * 0.2, c_[1] + 0.5 - oy * 0.2, rng.uniform(0.45, 0.7), "sand_drift")
    # parvis : dallage ancien à demi ensablé autour des bâtiments (dalles disjointes, fissurées)
    prng = random.Random(SEED * 19 + 5)
    for y in range(4, H - 4):
        for x in range(2, W - 2):
            c_ = (x, y)
            if tile(x, y) != 1 or paving_of(x, y) is not None or c_ in GAME_CELLS or c_ in PATH_DONE or c_ in LM_CELLS:
                continue
            d = 9
            for oy in range(-3, 4):
                for ox in range(-3, 4):
                    if tile(x + ox, y + oy) == 3:
                        d = min(d, max(abs(ox), abs(oy)))
            if d > 3 or prng.random() > (0.42 - d * 0.1):
                continue
            for qx, qy in ((x + 0.25, y + 0.25), (x + 0.75, y + 0.75)) if prng.random() < 0.35 else ((x + 0.5, y + 0.5),):
                sz = 0.46 if qx != x + 0.5 else prng.uniform(0.82, 0.95)
                det.box(qx - sz / 2, Y(qy + sz / 2), -0.01, qx + sz / 2, Y(qy - sz / 2), prng.uniform(0.008, 0.026),
                        prng.choice(("slabs_sandy", "slabs_sandy", "slabs_big")), rot=prng.uniform(-0.08, 0.08))
            if prng.random() < 0.3:
                decal(det, x + prng.uniform(0.2, 0.8), y + prng.uniform(0.2, 0.8), prng.uniform(0.4, 0.8), "sand_drift")
    # micro-détail du sable : ossements, jarres brisées, traces de pas
    for k in range(140):
        cx, cy = rng.uniform(1, W - 1), rng.uniform(1, H - 1)
        c_ = (int(cx), int(cy))
        if tile(*c_) != 1 or paving_of(*c_) is not None or c_ in GAME_CELLS:
            continue
        q = rng.random()
        if q < 0.35:
            for j in range(rng.randint(2, 4)):
                a_ = rng.uniform(0, math.pi)
                ln = rng.uniform(0.18, 0.35)
                px_, py_ = cx + rng.uniform(-0.3, 0.3), cy + rng.uniform(-0.3, 0.3)
                det.seg((px_, Y(py_), 0.03), (px_ + math.cos(a_) * ln, Y(py_) + math.sin(a_) * ln, 0.03), 0.025, "bone", 5)
            if rng.random() < 0.5:
                det.sphere(cx, Y(cy), 0.05, 0.07, "bone", 2, 1.0, 1.2, 0.8)
        elif q < 0.6:
            det.cyl(cx, Y(cy), 0.0, 0.12, 0.09, rng.choice(["clay", "clay_dark"]), 8, r2=0.06)
            for j in range(3):
                det.box(cx + rng.uniform(-0.3, 0.3), Y(cy + rng.uniform(-0.3, 0.3)), 0.0, cx + rng.uniform(0.32, 0.4), Y(cy + rng.uniform(-0.3, -0.25)), 0.02, "clay", rot=rng.uniform(0, 3))
        else:
            # traces de pas : petites empreintes alternées le long d'une marche aléatoire
            a_ = rng.uniform(0, math.tau)
            px_, py_ = cx, cy
            for j in range(rng.randint(8, 16)):
                a_ += rng.uniform(-0.25, 0.25)
                px_ += math.cos(a_) * 0.32
                py_ += math.sin(a_) * 0.32
                if tile(int(px_), int(py_)) != 1:
                    break
                sd = 0.07 if j % 2 else -0.07
                decal(det, px_ - math.sin(a_) * sd, py_ + math.cos(a_) * sd, 0.065, "sand_shade")
    det.to_object("_floordet", "world")


# ======================================================================= lumières
FIX = []
LIGHT_E = float(os.environ.get("EG_LIGHT", "170"))


def build_lights():
    n = 0
    for t_ in TORCH_LIGHTS:
        lx, ly, lz = t_[:3]
        L_ = bpy.data.lights.new("t%d" % n, "POINT")
        L_.color = (1.0, 0.5, 0.16)
        L_.energy = LIGHT_E * (t_[3] if len(t_) > 3 else 1.0)
        L_.shadow_soft_size = 0.25
        o = bpy.data.objects.new("t%d" % n, L_)
        o.location = (lx, ly, lz)
        scene.collection.objects.link(o)
        n += 1
    # cours : lueur orange des braseros (2 lampes par cour)
    for (cx_, cy_, cw_, ch_) in COURTS:
        for fx in (0.3, 0.7):
            L_ = bpy.data.lights.new("g%d" % n, "POINT")
            L_.color = (1.0, 0.5, 0.18)
            L_.energy = LIGHT_E * 0.25 * min(2.0, max(1.0, cw_ * ch_ / 60.0))
            L_.shadow_soft_size = 0.6
            o = bpy.data.objects.new("g%d" % n, L_)
            o.location = (cx_ + cw_ * fx, Y(cy_ + ch_ * 0.5), 2.4)
            scene.collection.objects.link(o)
            n += 1
    # chambres à toit : lampe chaude au plafond (intérieurs lisibles dans la passe int)
    for b in LAYOUT.get("buildings", []):
        x, y, w, h = b["rect"]
        L_ = bpy.data.lights.new("c%d" % n, "AREA")
        L_.shape = "DISK"
        L_.size = 1.6
        L_.color = (1.0, 0.7, 0.4)
        L_.energy = LIGHT_E * 0.45 * (w * h / 20.0)
        o = bpy.data.objects.new("c%d" % n, L_)
        o.location = (x + w / 2, Y(y + h / 2), (H_SANCT if b.get("arch") == "sanctuary" else H_ROOF) - 0.2)
        scene.collection.objects.link(o)
        n += 1
    print("  lights", n, flush=True)


def build_furnish():
    """Mobilier des chambres (décor bas, non bloquant, objet « _furnish » ignoré par le masque
    d'emprise) le long des murs selon le rôle : sarcophages peints, coffres à ferrures d'or,
    étagères de jarres et rouleaux, tables d'offrandes garnies, râteliers de lances et boucliers,
    statuettes, tas d'or ; tapis et pavements peints au centre ; plaque emblème au centre des cours."""
    fm = MB()
    rng = random.Random(SEED * 29 + 7)
    for m in MODS:
        if m.get("open") or m["role"] in ("sanctuary", "inner_court", "hypostyle", "court"):
            continue
        ix, iy, iw, ih = m["inner"]
        role = m["role"]
        # tapis / pavement peint au centre
        if iw >= 3 and ih >= 3 and rng.random() < 0.45:
            cx, cy = ix + iw / 2, iy + ih / 2
            hw, hh = min(iw, 5) * 0.26, min(ih, 5) * 0.26
            cm = rng.choice(("carpet_red", "carpet_blue", "clay_dark"))
            fm.box(cx - hw - 0.08, Y(cy + hh + 0.08), 0.002, cx + hw + 0.08, Y(cy - hh - 0.08), 0.008, "gold_dark")
            fm.box(cx - hw, Y(cy + hh), 0.003, cx + hw, Y(cy - hh), 0.011, cm)
            fm.box(cx - hw * 0.45, Y(cy + hh * 0.45), 0.004, cx + hw * 0.45, Y(cy - hh * 0.45), 0.014, "gold_dark" if cm != "clay_dark" else "linen")
        for yy in range(iy, iy + ih):
            for xx in range(ix, ix + iw):
                if (xx, yy) in GAME_CELLS or tile(xx, yy) != 2:
                    continue
                nw = [(dx, dy) for _, dx, dy in SIDES if tile(xx + dx, yy + dy) == 3]
                if not nw or rng.random() > 0.6:
                    continue
                dx, dy = nw[0]
                # repère local : u le long du mur, v vers l'intérieur
                bx, by = xx + 0.5 + dx * 0.32, yy + 0.5 + dy * 0.32
                horiz = dy != 0
                def bb(u0, v0, u1, v1, z0, z1, mat):
                    if horiz:
                        fm.box(bx + u0, Y(by - dy * v0), z0, bx + u1, Y(by - dy * v1), z1, mat)
                    else:
                        fm.box(bx - dx * v0, Y(by + u0), z0, bx - dx * v1, Y(by + u1), z1, mat)
                q = rng.random()
                if role in ("tomb", "embalming") and q < 0.35:
                    # sarcophage peint couché le long du mur
                    bb(-0.42, -0.14, 0.42, 0.18, 0.0, 0.28, "clay_dark")
                    bb(-0.4, -0.12, 0.4, 0.16, 0.28, 0.36, "gold")
                    bb(-0.3, -0.08, 0.22, 0.12, 0.36, 0.38, "lapis")
                elif role in ("treasury", "tomb", "offering") and q < 0.6:
                    # coffre à ferrures d'or + pièces
                    bb(-0.24, -0.15, 0.24, 0.15, 0.0, 0.28, "wood")
                    bb(-0.26, -0.17, 0.26, 0.17, 0.26, 0.32, "gold_dark")
                    for k in range(rng.randint(2, 5)):
                        fm.sphere(bx + rng.uniform(-0.35, 0.35), Y(by + rng.uniform(-0.35, 0.35)), 0.0, rng.uniform(0.05, 0.09), "gold", 1, 1.3, 1.3, 0.5)
                elif role in ("scribe", "offering", "embalming") and q < 0.8:
                    # étagère basse de jarres / rouleaux
                    bb(-0.42, -0.1, 0.42, 0.12, 0.0, 0.5, "wood_dark")
                    bb(-0.4, -0.1, 0.4, 0.1, 0.22, 0.26, "wood")
                    for k in range(4):
                        u = -0.3 + k * 0.2
                        if horiz:
                            px_, py_ = bx + u, by
                        else:
                            px_, py_ = bx, by + u
                        fm.cyl(px_, Y(py_), 0.26, 0.42, 0.06, rng.choice(("clay", "limestone", "linen", "turquoise")), 8, r2=0.04)
                elif role in ("guard_hall", "trap_hall", "statue_hall") and q < 0.45:
                    # râtelier de lances + bouclier
                    bb(-0.4, -0.06, 0.4, 0.06, 0.0, 0.12, "wood_dark")
                    for k in range(4):
                        u = -0.3 + k * 0.2
                        if horiz:
                            px_, py_ = bx + u, by
                        else:
                            px_, py_ = bx, by + u
                        fm.cyl(px_, Y(py_), 0.0, 0.62, 0.025, "wood", 5)
                        fm.cyl(px_, Y(py_), 0.62, 0.72, 0.04, "bronze", 5, r2=0.0)
                    bb(-0.15, 0.1, 0.15, 0.16, 0.05, 0.4, "lapis")
                elif role == "statue_hall" and q < 0.8:
                    # statuette d'Anubis assise sur socle
                    bb(-0.2, -0.16, 0.2, 0.16, 0.0, 0.18, "wall_top")
                    fm.sphere(bx, Y(by), 0.34, 0.13, "basalt", 1, 1.0, 1.0, 1.3)
                    fm.sphere(bx, Y(by), 0.55, 0.08, "basalt", 1, 0.9, 1.3, 1.0)
                    fm.box(bx - 0.08, Y(by + 0.04), 0.5, bx + 0.08, Y(by - 0.04), 0.6, "gold")
                else:
                    # jarres et vases groupés
                    for k in range(rng.randint(1, 3)):
                        qx, qy = bx + rng.uniform(-0.28, 0.28), by + rng.uniform(-0.28, 0.28)
                        r_ = rng.uniform(0.08, 0.13)
                        fm.cyl(qx, Y(qy), 0.0, r_ * 2.2, r_, rng.choice(("clay", "clay_dark", "limestone")), 8, r2=r_ * 0.55)
    # plaque emblème au centre des cours des temples (disque solaire ailé stylisé)
    for (cx_, cy_, cw_, ch_) in COURTS[1:]:
        cx, cy = cx_ + cw_ / 2, cy_ + ch_ / 2
        if (int(cx), int(cy)) in GAME_CELLS:
            continue
        hw = min(cw_, ch_) * 0.28
        fm.box(cx - hw, Y(cy + hw), 0.0, cx + hw, Y(cy - hw), 0.05, "slabs_dark")
        fm.box(cx - hw + 0.1, Y(cy + hw - 0.1), 0.05, cx + hw - 0.1, Y(cy - hw + 0.1), 0.06, "gold_dark")
        fm.box(cx - hw + 0.2, Y(cy + hw - 0.2), 0.06, cx + hw - 0.2, Y(cy - hw + 0.2), 0.07, "plaque")
        fm.cyl(cx, Y(cy), 0.07, 0.085, hw * 0.35, "gold_glow", 16)
        fm.box(cx - hw * 0.8, Y(cy + 0.08), 0.07, cx + hw * 0.8, Y(cy - 0.08), 0.08, "gold")
    fm.to_object("_furnish", "world")


def build_world():
    build_floors()
    build_walls()
    build_columns()
    build_torches()
    build_roofs()
    build_landmarks()
    build_props()
    build_details()
    build_furnish()
    build_lights()


# ======================================================================= rendu
EXPOSURE = float(os.environ.get("EG_EXPOSURE", "-0.95"))
SUN_E = float(os.environ.get("EG_SUN", "6.5"))
SKY = float(os.environ.get("EG_SKY", "0.45"))
SAT = float(os.environ.get("EG_SAT", "0.94"))
CON = float(os.environ.get("EG_CON", "1.28"))
LIFT = float(os.environ.get("EG_LIFT", "5"))
BLOOM = float(os.environ.get("EG_BLOOM", "0.8"))


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
    bg.inputs[0].default_value = (0.62, 0.6, 0.85, 1)    # ciel du couchant mauve-bleuté : ombres bleutées
    bg.inputs[1].default_value = SKY
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = SUN_E
    sun.color = (1.0, 0.7, 0.4)
    sun.angle = math.radians(2.0)
    so = bpy.data.objects.new("sun", sun)
    sc.collection.objects.link(so)
    # soleil bas à l'est (planche) : faces est des pyramides très éclairées, faces sud en lumière
    # rasante, faces ouest à l'ombre ; longues ombres portées vers l'ouest (EG_SUN_X/Y/Z)
    d = Vector((float(os.environ.get("EG_SUN_X", "-0.85")), float(os.environ.get("EG_SUN_Y", "-0.05")), float(os.environ.get("EG_SUN_Z", "-0.55")))).normalized()
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


def grade(path):
    """Étalonnage final (PIL) : halo doux des torches, saturation, contraste, clarté, relève des
    noirs (ombres brun chaud lisibles comme la maquette)."""
    from PIL import Image, ImageEnhance, ImageFilter, ImageChops
    im = Image.open(path).convert("RGB")
    if BLOOM > 0:
        hi = im.point(lambda v: max(0, v - 232) * 9)
        r1 = max(2, int(PPC_CUR * 0.25))
        b1 = hi.filter(ImageFilter.GaussianBlur(r1))
        b2 = hi.filter(ImageFilter.GaussianBlur(r1 * 4))
        glow = ImageChops.add(b1.point(lambda v: int(v * BLOOM)), b2.point(lambda v: int(v * BLOOM * 0.8)))
        im = ImageChops.add(im, glow)
    # teinte dorée du couchant (rouge/vert un peu relevés, bleu baissé)
    r_, g_, b_ = im.split()
    r_ = r_.point(lambda v: min(255, int(v * 1.03 + 3)))
    b_ = b_.point(lambda v: int(v * 0.9))
    im = Image.merge("RGB", (r_, g_, b_))
    im = ImageEnhance.Color(im).enhance(SAT)
    im = ImageEnhance.Contrast(im).enhance(CON)
    im = im.filter(ImageFilter.UnsharpMask(radius=max(2, int(PPC_CUR * 0.3)), percent=30, threshold=2))
    lut = [int(LIFT + v * (255 - LIFT) / 255) for v in range(256)]
    im = im.point(lut * 3)
    im.save(path)


PPC_CUR = 16


# ======================================================================= masque d'emprise : classes
# R = obstacle adossé au plan (murs, colonnes, décors, grands repères), G = fouillis, B = divers.
MASK_SOLID = ("walls_", "front_", "hullwalls", "props", "lm_")
MASK_DECOR = ("clutter",)
MASK_SKIP = ("ground", "floor_", "roof_", "cut_", "_", "sand", "paving")


def mask_class(name):
    if name.startswith(MASK_SKIP):
        return None
    if name.startswith(MASK_SOLID):
        return (1.0, 0.0, 0.0)
    if name.startswith(MASK_DECOR):
        return (0.0, 1.0, 0.0)
    return (0.0, 0.0, 1.0)


OCC_SKIP = ("ground", "floor_", "cut_", "_", "sand", "paving")


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
            "projection": "ground_square", "margin": MARGIN, "biome": "egypt_pyramids",
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
        # Intérieurs : par chambre à toit, SEULS son toit et le haut de son mur sud (front_) sont
        # masqués. Même caméra que « full », rendu par bordure (emprise + hauteur projetée).
        pw, ph = frame(cam, -MARGIN, W + MARGIN, -MARGIN, H + MARGIN)
        scene.render.use_border = True
        scene.render.use_crop_to_border = True
        tb = 0.0
        tW, tH = W + 2 * MARGIN, H + 2 * MARGIN
        up = int(math.ceil(4.6 * math.tan(TILT)))
        only = os.environ.get("EG_INT_ONLY", "")
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
