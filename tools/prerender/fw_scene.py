"""Scène Blender complète d'un étage 0 Far West (village façon maquette
docs/reference/farwest_maquette_carte.png), construite depuis le layout JSON exporté par
export_layout.gd (ou tools/prerender/maquette_layout.py), rendue en Cycles.

Usage (bpy en module) :
  python3 fw_scene.py <layout.json> <out_dir> [ppc=24] [samples=16] [passes=full,int] [margin=4]
Passes : full (carte entière, par morceaux, reprise possible : _chunks_full/) ; int (patch « sans
         toit » par bâtiment) ; mask (emprise au sol réelle, vue zénithale, 4 px/case → mask.png,
         voir render_mask) ; occ (ids d'occultation par pixel, même caméra que full → occ.png, voir
         render_occ) ; crop:x0;x1;y0;y1 (zone en cases → crop.png) ;
         view:x0;x1;y0;y1;tilt;ppc (vue libre → view.png)
Sorties : full.png, b<id>_in.png, mask.png, occ.png, render.json (géométrie) et
          layout.json (copie du plan) pour compose.py.
Cohérence rendu ↔ collisions (correctif « zones interdites ») : rochers rognés à leurs cases
(slab clamp), props / repères / wagons ramenés dans leur emprise (fit_xy), fouillis tenant dans
une case libre sans couper de passage.

PROJECTION (documentée, vérifiée par test) :
  caméra orthographique inclinée de TILT (35°) vers le nord, pixel_aspect_x = 1/cos(TILT),
  sensor_fit horizontal. Résultat : un point (cx, cy, z) en cases (z = hauteur, 1 case = 64 u)
  tombe au pixel
      px = (cx + M) * ppc ;  py = (cy + M) * ppc - z * tan(TILT) * ppc
  → le SOL (z = 0) est exactement sur la grille (ppc px par case, carré) ; les volumes
  « dépassent » vers le haut de z·tan(TILT) cases. Le jeu n'a qu'à poser l'image à l'échelle
  64/ppc (aucun étirement).
Repère Blender : 1 unité = 1 case. X = colonne, Y = -rangée, Z = hauteur.
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

TILT_DEG = float(os.environ.get("FW_TILT", "38"))
TILT = math.radians(TILT_DEG)
W, H = LAYOUT["size"]
TILES = LAYOUT["tiles"]
SEED = int(LAYOUT.get("seed", 1))
RNG = random.Random(SEED)
STORY = 2.0          # hauteur d'un niveau (cases)


def tile(x, y):
    if x < 0 or y < 0 or x >= W or y >= H:
        return 0
    return int(TILES[y][x])


def Y(r):
    """Rangée (vers le bas) → Y Blender."""
    return -r


# ======================================================================= normalisation layout
def _rect_of_spawn(s):
    sx, sy = s.get("size", [1, 1])
    x0 = s["cell"][0] - (sx - 1) // 2
    return [x0, s["cell"][1] - sy + 1, sx, sy]


def normalize():
    """Complète les champs du contrat (paths, fences, rock_formations, props, rails, train,
    landmarks) à partir des anciens champs (landmark_spawns, prop_spawns, decor_spawns) quand
    le générateur ne les fournit pas encore."""
    L = LAYOUT
    lms = L.get("landmark_spawns", [])
    if not L.get("rock_formations"):
        rf = []
        for s in lms:
            k = s["kind"]
            if k.startswith("lm_rock") or k == "lm_mesa":
                x, y, w, h = _rect_of_spawn(s)
                cells = [[xx, yy] for yy in range(y, y + h) for xx in range(x, x + w)]
                hh = {"lm_rock_a": 1.0, "lm_rock_b": 1.3, "lm_rock_c": 1.7, "lm_rock_d": 2.2, "lm_rock_e": 1.6, "lm_mesa": 2.6}.get(k, 1.4)
                rf.append({"cells": cells, "height": hh})
        L["rock_formations"] = rf
    if not L.get("train"):
        tr = []
        m = {"lm_loco": "loco", "lm_tender": "tender", "lm_boxcar": "boxcar", "lm_boxcar_b": "boxcar_b",
             "lm_tankcar": "tankcar", "lm_flatcar": "flatcar", "lm_caboose": "caboose"}
        for s in lms:
            if s["kind"] in m:
                tr.append({"kind": m[s["kind"]], "rect": _rect_of_spawn(s)})
        L["train"] = tr
    if not L.get("landmarks"):
        lm = []
        m = {"lm_windmill": "windmill", "prop_water_tower": "water_tower", "lm_well": "well"}
        for s in lms:
            if s["kind"] in m:
                lm.append({"kind": m[s["kind"]], "rect": _rect_of_spawn(s)})
        L["landmarks"] = lm
    if not L.get("rails"):
        L["rails"] = [[s["cell"][0], s["cell"][1]] for s in L.get("decor_spawns", [])
                      if s["kind"] in ("decal_rail", "prop_rail_track")]
    if not L.get("props"):
        L["props"] = [{"kind": s["kind"], "cell": s["cell"], "rot": s.get("rot", 0.0), "size": s.get("size", [1, 1]),
                       "off": s.get("off", [0, 0])} for s in L.get("prop_spawns", [])]
    if "paths" not in L:
        # Rues : cases STREET à ≥ 2 cases de tout bâtiment ? Heuristique : cases STREET
        # bordées de bâtiments dans un rayon de 6 cases (rues entre bâtiments).
        near = set()
        for b in L["buildings"]:
            x, y, w, h = b["rect"]
            for yy in range(y - 4, y + h + 4):
                for xx in range(x - 4, x + w + 4):
                    near.add((xx, yy))
        L["paths"] = [[x, y] for (x, y) in near if tile(x, y) == 1]
    L.setdefault("fences", [])
    for b in L["buildings"]:
        b.setdefault("roof_style", "")
        b.setdefault("stories", 2 if b.get("arch") in ("saloon", "hotel") else 1)
        if not b.get("porch_side"):
            side = "S"
            x, y, w, h = b["rect"]
            for d in b.get("doors", []):
                if d.get("outside"):
                    cx, cy = d["cell"]
                    if d.get("vertical"):
                        side = "W" if cx == x else "E"
                    else:
                        side = "N" if cy == y else "S"
                    break
            b["porch_side"] = side


normalize()


def balance_roofs():
    """Palette de la maquette : tôle gris-bleu dominante (~60 %), rouge rare (≤ 15 %, saloon
    d'abord), rouille / bardeaux / planches en appoint. Le style du générateur est respecté
    tant que ces proportions le permettent (seed → résultat stable)."""
    bl = [b for b in LAYOUT["buildings"] if b.get("arch") != "ruin"]
    n = len(bl)
    if n < 4:
        return
    rng = random.Random(SEED * 7 + 3)
    reds = [b for b in bl if b.get("roof_style") == "red"]
    reds.sort(key=lambda b: (b.get("arch") != "saloon", -b["rect"][2] * b["rect"][3]))
    for b in reds[max(1, int(n * 0.15)):]:
        b["roof_style"] = "tin_blue" if rng.random() < 0.6 else "tin_grey"
    rust = [b for b in bl if b.get("roof_style") == "tin_rust"]
    for b in rust[max(1, int(n * 0.1)):]:
        b["roof_style"] = rng.choice(["tin_blue", "tin_grey", "plank"])
    blue = sum(1 for b in bl if b.get("roof_style") in ("tin_blue", "tin_grey", ""))
    others = [b for b in bl if b.get("roof_style") in ("shingle", "plank")]
    rng.shuffle(others)
    while blue < n * 0.55 and others:
        others.pop()["roof_style"] = "tin_blue"
        blue += 1


balance_roofs()

# ======================================================================= scène / collections
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
COLS = {}


def coll(name):
    if name not in COLS:
        c = bpy.data.collections.new(name)
        scene.collection.children.link(c)
        COLS[name] = c
    return COLS[name]


# ======================================================================= nœuds utilitaires
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


# ======================================================================= matériaux
def mat_wood_boards(name, cols, pw=0.16, L=2.2, gap=0.035, dirt=True, vertical=True, rough=0.88, bump=0.6, wear=0.4):
    """Bardage / plancher en lames. vertical=True : lames verticales (u = horizontal UV)."""
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    if not vertical:
        u, v = v, u
    r, joint, grain = s.boards(u, v, pw, L, gap)
    col = s.ramp(r, cols)
    col = s.mix(s.mul(s.sub(grain, 0.35), 0.9), col, (0.06, 0.045, 0.035))
    # usure : délavé gris par endroits
    wn = s.noise(s.obj(), 1.3, 5, 0.6)
    col = s.mix(s.mul(s.smooth(wn, 0.45, 0.75), wear), col, (0.33, 0.31, 0.29))
    col = s.mix(s.mul(joint, 0.85), col, (0.03, 0.02, 0.015))
    if dirt:
        z = s.zpos()
        d = s.mul(s.smooth(z, 0.55, 0.0), s.add(0.45, s.mul(s.noise(s.obj(), 4.0, 3), 0.6)))
        col = s.mix(s.m_("MINIMUM", d, 0.85), col, (0.36, 0.24, 0.15))
    h = s.add(s.mul(joint, -1.0), s.mul(grain, 0.25))
    return s.done(col, rough, s.bump(h, bump, 0.02))


def mat_tin(name, base, base2, rust=0.3, sheet=0.9, paint_loss=0.0):
    """Tôle ondulée : u = travers des ondes (UV), v = sens de la pente."""
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    per = 0.3
    wave = s.m_("SINE", s.mul(u, 2 * math.pi / per))
    isheet = s.m_("FLOOR", s.m_("DIVIDE", u, sheet))
    r = s.white(s.comb(isheet, s.m_("FLOOR", s.m_("DIVIDE", v, 2.4)), 0.3))
    col = s.mix(r, base, base2)
    # rouille : taches + coulures dans le sens de la pente
    n1 = s.noise(s.obj(), 1.1, 8, 0.65)
    streak = s.noise(s.comb(s.mul(u, 6.0), s.mul(v, 0.5), 0.0), 3.0, 4, 0.6)
    rm = s.smooth(s.add(s.mul(n1, 0.8), s.mul(streak, 0.35)), 0.78 - rust * 0.35, 0.95 - rust * 0.3)
    rcol = s.mix(s.noise(s.obj(), 7.0, 3), (0.24, 0.09, 0.035), (0.40, 0.18, 0.07))
    col = s.mix(rm, col, rcol)
    if paint_loss > 0:
        pl = s.smooth(s.noise(s.obj(), 2.2, 6), 0.62 - paint_loss * 0.2, 0.7 - paint_loss * 0.2)
        col = s.mix(pl, col, (0.27, 0.26, 0.25))
    # raccords de tôles + saleté dans les creux
    fu = s.m_("FRACT", s.m_("DIVIDE", u, sheet))
    seam = s.sub(1.0, s.smooth(fu, 0.0, 0.03))
    col = s.mix(s.mul(seam, 0.7), col, (0.04, 0.04, 0.045))
    col = s.mix(s.mul(s.smooth(wave, 0.3, -1.0), 0.55), col, (0.03, 0.03, 0.035))
    col = s.mix(s.mul(s.smooth(wave, 0.6, 1.0), 0.15), col, (0.30, 0.32, 0.36))
    # rivets / lignes horizontales de recouvrement
    fv = s.m_("FRACT", s.m_("DIVIDE", v, 2.4))
    ov = s.sub(1.0, s.smooth(fv, 0.0, 0.025))
    col = s.mix(s.mul(ov, 0.6), col, (0.05, 0.05, 0.05))
    h = s.add(s.mul(wave, 0.5), s.mul(seam, -0.5))
    rough = s.add(0.42, s.mul(rm, 0.5))
    s.b.inputs["Specular IOR Level"].default_value = 0.25
    return s.done(col, normal=s.bump(h, 0.9, 0.025), metal=0.05, rough_sock=s.add(rough, 0.3))


def mat_shingle(name, cols):
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    rowh = 0.16
    iv = s.m_("FLOOR", s.m_("DIVIDE", v, rowh))
    off = s.mul(s.m_("MODULO", iv, 2.0), 0.5)
    uu = s.add(s.m_("DIVIDE", u, 0.2), off)
    iu = s.m_("FLOOR", uu)
    r = s.white(s.comb(iu, iv, 0.0))
    col = s.ramp(r, cols)
    fu = s.m_("FRACT", uu)
    fv = s.m_("FRACT", s.m_("DIVIDE", v, rowh))
    j = s.m_("MAXIMUM", s.sub(1.0, s.mul(s.smooth(fu, 0.0, 0.08), s.smooth(fu, 1.0, 0.92))), s.smooth(fv, 0.75, 1.0))
    col = s.mix(s.mul(j, 0.8), col, (0.03, 0.025, 0.02))
    moss = s.smooth(s.noise(s.obj(), 1.5, 6), 0.55, 0.75)
    col = s.mix(s.mul(moss, 0.5), col, (0.30, 0.29, 0.27))
    return s.done(col, 0.9, s.bump(s.add(s.mul(j, -1.0), s.mul(fv, 0.4)), 0.8, 0.02))


def mat_rock(name="rock"):
    """Grès stratifié : bandes horizontales (Z) déformées, dessus poussiéreux, fissures."""
    s = NT(name)
    o = s.obj()
    x, yy, z = s.sep(o)
    warp = s.mul(s.noise(o, 0.9, 3), 0.55)
    zb = s.add(z, warp)
    band = s.m_("SINE", s.mul(zb, 2 * math.pi / 0.6))
    fine = s.m_("SINE", s.mul(zb, 2 * math.pi / 0.09))
    n = s.noise(o, 2.5, 6, 0.6)
    t = s.add(s.add(s.mul(band, 0.28), s.mul(fine, 0.08)), s.mul(n, 0.6))
    groove = s.smooth(fine, 0.75, 1.0)
    col = s.ramp(t, [(0.15, (0.17, 0.09, 0.045)), (0.45, (0.36, 0.21, 0.11)), (0.7, (0.52, 0.35, 0.21)), (0.95, (0.64, 0.48, 0.33))])
    geo = s.n("ShaderNodeNewGeometry")
    _, _, nz = s.sep(geo.outputs["Normal"])
    top = s.smooth(nz, 0.55, 0.9)
    col = s.mix(s.mul(top, 0.3), col, (0.66, 0.46, 0.28))
    bv = s.noise(o, 0.35, 2)
    col = s.mix(s.mul(s.smooth(bv, 0.4, 0.65), 0.35), col, (0.40, 0.20, 0.09))
    col = s.mix(s.mul(groove, 0.35), col, (0.16, 0.07, 0.035))
    cr = s.voronoi(s.comb(x, yy, s.mul(z, 3.0)), 3.5, "Distance")
    crack = s.smooth(cr, 0.09, 0.0)
    col = s.mix(s.mul(crack, 0.7), col, (0.09, 0.04, 0.03))
    ao = s.n("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.5
    ao.samples = 6
    crev = s.smooth(ao.outputs["AO"], 0.97, 0.5)
    col = s.mix(s.mul(crev, 0.9), col, (0.07, 0.03, 0.02))
    h = s.add(s.add(s.mul(fine, 0.15), s.mul(s.noise(o, 6.0, 8), 0.7)), s.mul(crack, -0.6))
    return s.done(col, 0.95, s.bump(h, 1.0, 0.09))


def mat_simple(name, c, rough=0.75, metal=0.0, var=0.3, scale=4.0, c2=None, bump=0.2, emit=None):
    s = NT(name)
    n = s.noise(s.obj(), scale, 5, 0.6)
    col = s.mix(s.mul(n, var * 2), c, c2 if c2 else tuple(x * 0.5 for x in c))
    s.done(col, rough, s.bump(n, bump, 0.02), metal)
    if emit:
        s.b.inputs["Emission Color"].default_value = (*emit[0], 1)
        s.b.inputs["Emission Strength"].default_value = emit[1]
    return s.m


def mat_foliage(name, c1, c2):
    s = NT(name)
    o = s.obj()
    n = s.noise(o, 18.0, 4, 0.7)
    v = s.voronoi(o, 25.0, "Distance")
    col = s.mix(n, c1, c2)
    col = s.mix(s.smooth(v, 0.15, 0.0), col, tuple(x * 0.35 for x in c1))
    s.b.inputs["Subsurface Weight"].default_value = 0.0
    return s.done(col, 0.85, s.bump(s.add(n, v), 0.8, 0.03))


def mat_stone_blocks(name, c):
    s = NT(name)
    u, v, _ = s.sep(s.uv())
    br = s.n("ShaderNodeTexBrick")
    br.inputs["Scale"].default_value = 1.0
    br.inputs["Brick Width"].default_value = 0.42
    br.inputs["Row Height"].default_value = 0.2
    br.inputs["Mortar Size"].default_value = 0.025
    br.inputs["Color1"].default_value = (*c, 1)
    br.inputs["Color2"].default_value = (*[x * 0.7 for x in c], 1)
    br.inputs["Mortar"].default_value = (0.08, 0.06, 0.05, 1)
    s.l(s.comb(u, v, 0.0), br.inputs["Vector"])
    n = s.noise(s.obj(), 8.0, 5)
    col = s.mix(s.mul(n, 0.4), br.outputs["Color"], (0.15, 0.11, 0.08))
    return s.done(col, 0.9, s.bump(s.add(s.mul(br.outputs["Fac"], -1.0), s.mul(n, 0.3)), 0.8, 0.03))


def mat_ground(mask_path, ext):
    """Sol : sable ocre désaturé, variations à grande échelle, chemins de terre battue (masque
    image R), abords des rochers (G), cours piétinées (B), ornières (A)."""
    s = NT("ground")
    o = s.obj()
    img = bpy.data.images.load(os.path.abspath(mask_path))
    img.pack()
    img.colorspace_settings.name = "Non-Color"
    img.alpha_mode = "CHANNEL_PACKED"   # sinon R/G/B prémultipliés par A (ornières) → masques nuls
    tx = s.n("ShaderNodeTexImage")
    tx.image = img
    tx.interpolation = "Cubic"
    tx.extension = "EXTEND"
    # UV du masque calculées depuis la position objet (indépendant de l'orientation de la face)
    ox_, oy_, _ = s.sep(o)
    u_ = s.m_("DIVIDE", s.sub(ox_, float(ext[0])), float(ext[1] - ext[0]))
    v_ = s.m_("DIVIDE", s.sub(oy_, float(-ext[3])), float(ext[3] - ext[2]))
    s.l(s.comb(u_, v_, 0.0), tx.inputs[0])
    mr, mg, mb_ = s.sep(tx.outputs["Color"])
    ma = tx.outputs["Alpha"]
    big = s.noise(o, 0.045, 3, 0.5)
    mid = s.noise(o, 0.28, 5, 0.55)
    t = s.add(s.mul(big, 0.65), s.mul(mid, 0.35))
    col = s.ramp(t, [(0.30, (0.66, 0.40, 0.14)), (0.5, (0.80, 0.53, 0.22)), (0.72, (0.88, 0.64, 0.33))])
    # taches plus grises / plus rouges
    p2 = s.noise(o, 0.16, 4)
    col = s.mix(s.mul(s.smooth(p2, 0.58, 0.72), 0.3), col, (0.52, 0.34, 0.19))
    col = s.mix(s.mul(s.smooth(p2, 0.36, 0.26), 0.35), col, (0.50, 0.26, 0.14))
    # chemins : plus sombres, plus lisses, bords irréguliers
    en = s.noise(o, 1.4, 4)
    path = s.smooth(s.add(mr, s.mul(s.sub(en, 0.5), 0.5)), 0.25, 0.65)
    pcol = s.mix(s.noise(o, 0.8, 4), (0.74, 0.52, 0.31), (0.84, 0.62, 0.40))
    col = s.mix(s.mul(path, 0.9), col, pcol)
    # bord de chemin : liseré plus sombre (terre tassée)
    edge_p = s.mul(s.smooth(path, 0.15, 0.45), s.smooth(path, 0.75, 0.45))
    col = s.mix(s.mul(edge_p, 0.3), col, (0.46, 0.28, 0.13))
    # ornières (A) : deux lignes sombres
    rut = s.smooth(ma, 0.2, 0.8)
    col = s.mix(s.mul(rut, 0.6), col, (0.30, 0.18, 0.09))
    # cour piétinée (B) : un peu plus sombre et grise
    yard = s.smooth(s.add(mb_, s.mul(s.sub(en, 0.5), 0.4)), 0.2, 0.8)
    col = s.mix(s.mul(yard, 0.6), col, (0.40, 0.26, 0.15))
    # abords rocheux (G) : rouge-brun, gravier
    rk = s.smooth(s.add(mg, s.mul(s.sub(en, 0.5), 0.5)), 0.15, 0.7)
    col = s.mix(s.mul(rk, 0.6), col, (0.44, 0.24, 0.12))
    # détail moyen : plaques craquelées sombres / claires (lecture « peinte » de la maquette)
    md = s.noise(o, 2.2, 6, 0.65)
    col = s.mix(s.mul(s.smooth(md, 0.48, 0.7), 0.75), col, (0.38, 0.22, 0.10))
    md2 = s.noise(o, 6.0, 5, 0.7)
    col = s.mix(s.mul(s.smooth(md2, 0.55, 0.8), 0.35), col, (0.34, 0.20, 0.10))
    col = s.mix(s.mul(s.smooth(md, 0.44, 0.3), 0.45), col, (0.74, 0.55, 0.36))
    crk = s.voronoi(s.vmul(o, (1.0, 1.0, 1.0)), 1.6, "Distance")
    # cailloux sombres + grains clairs
    vo = s.voronoi(o, 9.0, "Distance")
    peb = s.mul(s.smooth(vo, 0.12, 0.05), s.smooth(s.noise(o, 2.0, 2), 0.45, 0.6))
    col = s.mix(s.mul(peb, 0.7), col, (0.25, 0.15, 0.10))
    vo2 = s.voronoi(o, 22.0, "Distance")
    peb2 = s.smooth(vo2, 0.08, 0.03)
    col = s.mix(s.mul(peb2, 0.25), col, (0.72, 0.56, 0.38))
    # fines craquelures (sol sec)
    ck = s.voronoi(o, 3.5, "Distance")
    v2 = s.n("ShaderNodeTexVoronoi")
    v2.feature = "DISTANCE_TO_EDGE"
    v2.inputs["Scale"].default_value = 3.0
    s.l(s.add(o, s.vmul(s.noise(o, 3.0, 2, col=True), 0.3)) if False else o, v2.inputs["Vector"])
    edge = s.smooth(v2.outputs["Distance"], 0.035, 0.0)
    crk_m = s.mul(edge, s.mul(s.smooth(s.noise(o, 0.5, 3), 0.45, 0.65), s.sub(1.0, path)))
    col = s.mix(s.mul(crk_m, 0.22), col, (0.36, 0.20, 0.09))
    # hors chemins : terrain plus sombre et plus texturé (comme la maquette)
    offp = s.sub(1.0, path)
    rough_t = s.noise(o, 1.1, 6, 0.7)
    col = s.mix(s.mul(offp, s.mul(s.smooth(rough_t, 0.45, 0.65), 0.45)), col, (0.48, 0.29, 0.13))
    # grandes plages claires / foncées (balayage)
    lg = s.noise(s.vmul(o, (1.0, 2.2, 1.0)), 0.35, 4, 0.55)
    col = s.mix(s.mul(s.smooth(lg, 0.56, 0.7), 0.4), col, (0.52, 0.31, 0.14))
    col = s.mix(s.mul(s.smooth(lg, 0.42, 0.3), 0.35), col, (0.90, 0.66, 0.40))
    # mouchetures fines (lecture peinte)
    sp = s.noise(o, 18.0, 3, 0.7)
    col = s.mix(s.mul(s.smooth(sp, 0.64, 0.74), 0.15), col, (0.40, 0.24, 0.12))
    col = s.mix(s.mul(s.smooth(sp, 0.36, 0.28), 0.25), col, (0.92, 0.70, 0.45))
    # assombrissement de contact (AO) au pied des murs, rochers, objets
    gao = s.n("ShaderNodeAmbientOcclusion")
    gao.inputs["Distance"].default_value = 1.2
    gao.samples = 8
    col = s.mix(s.mul(s.smooth(gao.outputs["AO"], 1.0, 0.3), 0.75), col, (0.20, 0.11, 0.06))
    # relief : ondulations de vent, petites dunes, grain ; atténué sur les chemins
    wv = s.n("ShaderNodeTexWave")
    wv.inputs["Scale"].default_value = 1.6
    wv.inputs["Distortion"].default_value = 8.0
    wv.inputs["Detail"].default_value = 3
    mp = s.n("ShaderNodeMapping")
    mp.inputs["Rotation"].default_value = (0, 0, 0.6)
    s.l(o, mp.inputs[0])
    s.l(mp.outputs[0], wv.inputs["Vector"])
    flat = s.sub(1.0, s.mul(path, 0.8))
    h = s.add(s.mul(s.mul(wv.outputs["Fac"], s.noise(o, 0.2, 3)), 0.5), s.mul(s.noise(o, 40.0, 2), 0.25))
    h = s.add(s.mul(h, flat), s.mul(peb, 0.9))
    h = s.add(h, s.mul(rut, -0.8))
    h = s.add(h, s.mul(s.noise(o, 0.12, 2), 3.0))
    return s.done(col, 0.97, s.bump(h, 0.35, 0.04))


def build_materials():
    # bardages (lames verticales, usées)
    mat_wood_boards("siding_brown", [(0.0, (0.16, 0.105, 0.07)), (0.5, (0.24, 0.16, 0.10)), (1.0, (0.30, 0.21, 0.14))])
    mat_wood_boards("siding_grey", [(0.0, (0.18, 0.16, 0.14)), (0.5, (0.27, 0.24, 0.21)), (1.0, (0.34, 0.30, 0.26))])
    mat_wood_boards("siding_red", [(0.0, (0.17, 0.05, 0.035)), (0.5, (0.26, 0.08, 0.05)), (1.0, (0.33, 0.13, 0.08))], wear=0.55)
    mat_wood_boards("siding_teal", [(0.0, (0.07, 0.13, 0.13)), (0.5, (0.11, 0.19, 0.19)), (1.0, (0.16, 0.24, 0.23))], wear=0.55)
    mat_wood_boards("siding_h", [(0.0, (0.17, 0.12, 0.08)), (0.5, (0.25, 0.18, 0.12)), (1.0, (0.31, 0.24, 0.17))], pw=0.14, vertical=False, L=3.0)
    mat_wood_boards("siding_cream", [(0.0, (0.36, 0.30, 0.22)), (0.5, (0.46, 0.39, 0.29)), (1.0, (0.52, 0.45, 0.34))], pw=0.13, vertical=False, L=3.0, wear=0.5)
    # planchers, terrasses, toits en planches, bois divers
    mat_wood_boards("floor", [(0.0, (0.17, 0.10, 0.06)), (0.5, (0.25, 0.15, 0.09)), (1.0, (0.31, 0.20, 0.12))], pw=0.17, L=1.8, dirt=False, vertical=False, wear=0.2)
    mat_wood_boards("deck", [(0.0, (0.20, 0.15, 0.10)), (0.5, (0.32, 0.24, 0.17)), (1.0, (0.42, 0.33, 0.24))], pw=0.24, L=1.6, gap=0.045, dirt=False, wear=0.5)
    mat_wood_boards("roof_planks", [(0.0, (0.07, 0.055, 0.045)), (0.5, (0.13, 0.10, 0.08)), (1.0, (0.19, 0.15, 0.12))], pw=0.3, L=1.8, gap=0.05, dirt=False, wear=0.6, bump=0.9)
    mat_wood_boards("wood", [(0.0, (0.18, 0.11, 0.065)), (0.5, (0.26, 0.17, 0.10)), (1.0, (0.33, 0.22, 0.14))], pw=0.12, L=1.0, dirt=False, wear=0.3)
    mat_wood_boards("wood_grey", [(0.0, (0.20, 0.17, 0.14)), (0.5, (0.29, 0.25, 0.21)), (1.0, (0.36, 0.32, 0.27))], pw=0.12, L=1.0, dirt=False, wear=0.5)
    mat_wood_boards("crate", [(0.0, (0.28, 0.18, 0.10)), (0.5, (0.38, 0.26, 0.15)), (1.0, (0.45, 0.32, 0.19))], pw=0.1, L=0.6, dirt=False, vertical=False, wear=0.2)
    mat_simple("wood_dark", (0.075, 0.05, 0.035), 0.85, var=0.35, scale=9.0)
    mat_simple("trim", (0.14, 0.10, 0.07), 0.8, var=0.3, scale=6.0)
    mat_simple("trim_white", (0.42, 0.40, 0.36), 0.8, var=0.35, scale=6.0)
    mat_simple("glass", (0.012, 0.014, 0.02), 0.15, var=0.5, scale=3.0, c2=(0.05, 0.06, 0.08))
    mat_simple("window_lit", (0.6, 0.35, 0.15), 0.5, emit=((1.0, 0.55, 0.22), 1.6))
    mat_simple("doorway", (0.02, 0.015, 0.012), 0.9, var=0.2)
    mat_simple("sign", (0.30, 0.25, 0.17), 0.85, var=0.4, scale=8.0)
    mat_simple("sign_red", (0.25, 0.05, 0.035), 0.85, var=0.4, scale=8.0)
    # toitures
    mat_tin("tin_blue", (0.055, 0.063, 0.085), (0.085, 0.095, 0.12), rust=0.3)
    mat_tin("tin_grey", (0.055, 0.055, 0.06), (0.09, 0.088, 0.09), rust=0.45)
    mat_tin("tin_rust", (0.085, 0.05, 0.035), (0.12, 0.075, 0.05), rust=0.55)
    mat_tin("tin_red", (0.14, 0.035, 0.03), (0.19, 0.055, 0.045), rust=0.5)
    mat_tin("tin_dark", (0.10, 0.10, 0.11), (0.15, 0.15, 0.16), rust=0.3)
    mat_shingle("shingle", [(0.0, (0.08, 0.065, 0.055)), (0.5, (0.13, 0.10, 0.08)), (1.0, (0.18, 0.14, 0.11))])
    mat_shingle("shingle_red", [(0.0, (0.15, 0.05, 0.035)), (0.5, (0.22, 0.07, 0.05)), (1.0, (0.28, 0.11, 0.07))])
    # minéral, végétal, divers
    mat_rock()
    mat_stone_blocks("stone_blocks", (0.42, 0.40, 0.38))
    mat_stone_blocks("brick", (0.30, 0.11, 0.06))
    mat_simple("stone", (0.40, 0.36, 0.33), 0.9, var=0.4, scale=6.0, bump=0.5)
    mat_simple("gravel", (0.20, 0.16, 0.13), 0.95, var=0.6, scale=40.0, c2=(0.33, 0.27, 0.22), bump=1.0)
    mat_simple("pebble", (0.30, 0.19, 0.12), 0.9, var=0.5, scale=10)
    mat_simple("iron", (0.06, 0.06, 0.065), 0.5, metal=0.7, var=0.3)
    mat_simple("rust_iron", (0.16, 0.08, 0.04), 0.7, metal=0.4, var=0.5, scale=8, c2=(0.06, 0.05, 0.05))
    mat_simple("steel", (0.30, 0.28, 0.27), 0.35, metal=0.9, var=0.2)
    mat_simple("boiler", (0.10, 0.10, 0.11), 0.38, metal=0.65, var=0.35, c2=(0.05, 0.05, 0.055))
    mat_simple("brass", (0.45, 0.30, 0.10), 0.35, metal=0.9)
    mat_simple("red_paint", (0.20, 0.045, 0.03), 0.75, var=0.4)
    mat_wood_boards("car_red", [(0.0, (0.17, 0.05, 0.035)), (0.5, (0.23, 0.07, 0.05)), (1.0, (0.28, 0.10, 0.07))], pw=0.14, L=3.0, dirt=False, wear=0.35)
    mat_wood_boards("car_brown", [(0.0, (0.15, 0.08, 0.05)), (0.5, (0.21, 0.12, 0.08)), (1.0, (0.26, 0.16, 0.10))], pw=0.14, L=3.0, dirt=False, wear=0.35)
    mat_simple("canvas", (0.30, 0.29, 0.26), 0.9, var=0.4, scale=5.0)
    mat_simple("cloth_red", (0.30, 0.05, 0.04), 0.9)
    mat_simple("sack", (0.42, 0.34, 0.22), 0.95, var=0.35, scale=9.0)
    mat_simple("hay", (0.52, 0.40, 0.18), 0.95, var=0.5, scale=25.0, bump=0.8)
    mat_simple("water", (0.02, 0.035, 0.04), 0.08, var=0.2)
    mat_simple("rug", (0.24, 0.06, 0.04), 0.95, var=0.4, scale=14)
    mat_foliage("foliage", (0.05, 0.09, 0.03), (0.12, 0.17, 0.05))
    mat_foliage("foliage2", (0.09, 0.11, 0.04), (0.17, 0.17, 0.07))
    mat_foliage("sage", (0.14, 0.15, 0.09), (0.22, 0.22, 0.14))
    mat_foliage("cactus", (0.06, 0.11, 0.05), (0.10, 0.16, 0.07))
    mat_foliage("dry", (0.42, 0.32, 0.16), (0.58, 0.46, 0.26))
    mat_simple("bark", (0.10, 0.075, 0.055), 0.9, var=0.4, scale=14.0, bump=0.6)
    mat_simple("deadwood", (0.30, 0.26, 0.22), 0.9, var=0.4, scale=14.0, bump=0.6)


# ======================================================================= géométrie
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
bld_cells = {}
for b in LAYOUT["buildings"]:
    x, y, w, h = b["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            bld_cells[(xx, yy)] = b
path_set = set(tuple(c) for c in LAYOUT.get("paths", []))
# cases réservées aux objets du jeu (conteneurs, cachettes, portes) : pas de fouillis décoratif
game_cells = set()
for key in ("container_spawns", "hiding_spot_spawns"):
    for sp in LAYOUT.get(key, []):
        x0_, y0_, w_, h_ = (sp["cell"][0] - (sp.get("size", [1, 1])[0] - 1) // 2, sp["cell"][1] - sp.get("size", [1, 1])[1] + 1,
                            sp.get("size", [1, 1])[0], sp.get("size", [1, 1])[1])
        for yy in range(y0_ - 1, y0_ + h_ + 1):
            for xx in range(x0_ - 1, x0_ + w_ + 1):
                game_cells.add((xx, yy))
for d in LAYOUT.get("doors", []):
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            game_cells.add((d["cell"][0] + dx, d["cell"][1] + dy))
rail_set = set(tuple(c) for c in LAYOUT.get("rails", []))
occupied = set(bld_cells)
for lm in LAYOUT["landmarks"] + LAYOUT["train"]:
    x, y, w, h = lm["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            occupied.add((xx, yy))
rock_cells = set()
for rf in LAYOUT["rock_formations"]:
    for c in rf["cells"]:
        rock_cells.add(tuple(c))
occupied |= rock_cells

ROOF_W = {"tin_blue": 46, "tin_grey": 16, "tin_rust": 12, "shingle": 10, "plank": 10, "red": 6}
SIDINGS = ["siding_brown", "siding_brown", "siding_grey", "siding_grey", "siding_h", "siding_red", "siding_teal", "siding_cream"]
ARCH_SIDING = {"saloon": "siding_red", "hotel": "siding_cream", "bank": "siding_h", "sheriff": "siding_grey",
               "store": "siding_brown", "church": "siding_cream", "stable": "siding_grey", "mine": "siding_grey"}
FALSE_FRONT = {"saloon", "hotel", "bank", "store", "sheriff"}


def roof_mat(style):
    return {"tin_blue": "tin_blue", "tin_grey": "tin_grey", "tin_rust": "tin_rust", "shingle": "shingle",
            "plank": "roof_planks", "red": "tin_red"}.get(style, "tin_blue")


def pick_roof(rng):
    tot = sum(ROOF_W.values())
    r = rng.uniform(0, tot)
    for k, v in ROOF_W.items():
        r -= v
        if r <= 0:
            return k
    return "tin_blue"


# ======================================================================= bâtiments
def gable(mb, x0, y0, x1, y1, z, mat, ridge_x, rise, ov=0.22, gable_mat="siding_brown", rng=None, th=0.07, ov_s=None):
    """Toit à deux pans sur le rectangle [x0,x1]×[y0,y1] (coordonnées Blender), égout à z.
    ov_s : débord côté sud (y0) ; 0 quand une fausse façade est collée au sud."""
    X0, X1, Y0, Y1 = x0 - ov, x1 + ov, y0 - (ov if ov_s is None else ov_s), y1 + ov
    top = z + rise
    if ridge_x:
        ym = (y0 + y1) / 2
        half = (Y1 - Y0) / 2
        sl = math.hypot(half, rise + ov * rise / max(half - ov, 0.1))
        zl = z - ov * rise / max((y1 - y0) / 2, 0.1)
        # pans (dessus + sous-face + chant)
        for (ya, sgn) in ((Y0, -1), (Y1, 1)):
            a, b_, c, d = (X0, ya, zl + th), (X1, ya, zl + th), (X1, ym, top + th), (X0, ym, top + th)
            if sgn > 0:
                a, b_, c, d = b_, a, d, c
            mb.quad_uv(a, b_, c, d, mat, None, sl)
            mb.poly([(X0, ya, zl), (X0, ym, top), (X1, ym, top), (X1, ya, zl)][::(-sgn)], "wood_dark")
            mb.poly([(X0, ya, zl), (X1, ya, zl), (X1, ya, zl + th), (X0, ya, zl + th)][::sgn], "trim")
        for xe, sg in ((x0, -1), (x1, 1)):
            mb.poly([(xe, y0, z), (xe, y1, z), (xe, ym, top)][::(-sg)], gable_mat)
            # bandeau de rive
            mb.box(xe + sg * ov - 0.04, Y0, zl, xe + sg * ov + 0.04, ym, top + th, "trim", tilt=None) if False else None
        mb.box(X0, ym - 0.07, top - 0.02, X1, ym + 0.07, top + th + 0.06, "tin_dark" if mat.startswith("tin") else "trim")
        return top
    else:
        xm = (x0 + x1) / 2
        half = (X1 - X0) / 2
        sl = math.hypot(half, rise)
        zl = z - ov * rise / max((x1 - x0) / 2, 0.1)
        for (xa, sgn) in ((X0, -1), (X1, 1)):
            a, b_, c, d = (xa, Y1, zl + th), (xa, Y0, zl + th), (xm, Y0, top + th), (xm, Y1, top + th)
            if sgn > 0:
                a, b_, c, d = b_, a, d, c
            mb.quad_uv(a, b_, c, d, mat, None, sl)
            mb.poly([(xa, Y0, zl), (xm, Y0, top), (xm, Y1, top), (xa, Y1, zl)][::sgn], "wood_dark")
            mb.poly([(xa, Y0, zl), (xa, Y1, zl), (xa, Y1, zl + th), (xa, Y0, zl + th)][::(-sgn)], "trim")
        for ye, sg in ((y0, -1), (y1, 1)):
            mb.poly([(x0, ye, z), (x1, ye, z), (xm, ye, top)][::sg], gable_mat)
        mb.box(xm - 0.07, Y0, top - 0.02, xm + 0.07, Y1, top + th + 0.06, "tin_dark" if mat.startswith("tin") else "trim")
        return top


def shed(mb, x0, y0, x1, y1, z_hi, z_lo, mat, low_side, ov=0.15, th=0.06):
    """Toit en appentis : pente vers low_side (N/S/E/W)."""
    X0, X1, Y0, Y1 = x0 - ov, x1 + ov, y0 - ov, y1 + ov
    if low_side in ("S", "N"):
        yl, yh = (Y0, Y1) if low_side == "S" else (Y1, Y0)
        sl = math.hypot(Y1 - Y0, z_hi - z_lo)
        pts = [(X0, yl, z_lo + th), (X1, yl, z_lo + th), (X1, yh, z_hi + th), (X0, yh, z_hi + th)]
        if low_side == "N":
            pts = [pts[1], pts[0], pts[3], pts[2]]
        mb.quad_uv(*pts, mat, None, sl)
        mb.poly([(X0, yl, z_lo), (X0, yh, z_hi), (X1, yh, z_hi), (X1, yl, z_lo)][::(1 if low_side == "N" else -1)], "wood_dark")
        mb.poly([(X0, yl, z_lo), (X1, yl, z_lo), (X1, yl, z_lo + th), (X0, yl, z_lo + th)][::(1 if low_side == "S" else -1)], "trim")
    else:
        xl, xh = (X0, X1) if low_side == "W" else (X1, X0)
        sl = math.hypot(X1 - X0, z_hi - z_lo)
        pts = [(xl, Y1, z_lo + th), (xl, Y0, z_lo + th), (xh, Y0, z_hi + th), (xh, Y1, z_hi + th)]
        if low_side == "E":
            pts = [pts[1], pts[0], pts[3], pts[2]]
        mb.quad_uv(*pts, mat, None, sl)
        mb.poly([(xl, Y0, z_lo), (xh, Y0, z_hi), (xh, Y1, z_hi), (xl, Y1, z_lo)][::(1 if low_side == "W" else -1)], "wood_dark")


def window(mb, axis, pos, along, z0, z1, wdt, sgn, rng, frame="trim", shutters=None, lit=False, boarded=False):
    """Fenêtre sur un mur. axis 'x' : mur le long de X à y=pos, normale sgn·Y ; 'y' : mur le long de Y."""
    d = 0.03 * sgn
    a0, a1 = along - wdt / 2, along + wdt / 2
    gm = "window_lit" if lit else "glass"

    def B(u0, u1, za, zb, e0, e1, m):
        if axis == "x":
            mb.box(u0, pos + min(e0, e1), za, u1, pos + max(e0, e1), zb, m)
        else:
            mb.box(pos + min(e0, e1), u0, za, pos + max(e0, e1), u1, zb, m)
    B(a0, a1, z0, z1, 0, d, gm)
    fw = 0.06
    B(a0 - fw, a1 + fw, z1, z1 + fw * 1.5, 0, d * 2.5, frame)
    B(a0 - fw * 1.5, a1 + fw * 1.5, z0 - fw * 1.3, z0, 0, d * 3.5, frame)
    B(a0 - fw, a0, z0, z1, 0, d * 2.5, frame)
    B(a1, a1 + fw, z0, z1, 0, d * 2.5, frame)
    B((a0 + a1) / 2 - 0.015, (a0 + a1) / 2 + 0.015, z0, z1, 0, d * 1.5, frame)
    B(a0, a1, (z0 + z1) / 2 - 0.015, a1, (z0 + z1) / 2 + 0.015, 0, d * 1.5, frame) if False else B(a0, a1, (z0 + z1) / 2 - 0.015, (z0 + z1) / 2 + 0.015, 0, d * 1.5, frame)
    if shutters:
        sw = wdt / 2
        B(a0 - fw - sw, a0 - fw, z0, z1, 0, d * 2, shutters)
        if rng.random() < 0.75:
            B(a1 + fw, a1 + fw + sw, z0, z1, 0, d * 2, shutters)
    if boarded:
        for i in range(2):
            zc = z0 + (z1 - z0) * (0.3 + 0.4 * i)
            B(a0 - 0.05, a1 + 0.05, zc - 0.04, zc + 0.04, d, d * 4, "wood_grey")


def build_ruin(b, rng):
    """Bâtiment en ruine / enclos de planches sans toit (murs partiels, débris)."""
    x, y, w, h = b["rect"]
    mb = MB()
    sid = rng.choice(["siding_grey", "siding_brown", "wood_grey"])
    mb.box(x + 0.05, Y(y + h) + 0.05, 0.0, x + w - 0.05, Y(y) - 0.05, 0.03, "floor")
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if tile(xx, yy) != 3:
                continue
            hgt = rng.uniform(0.5, 1.5) if rng.random() < 0.8 else rng.uniform(0.15, 0.4)
            e = 0.12
            x0_, x1_ = xx + (0.44 if xx not in (x, x + w - 1) or yy in (y, y + h - 1) else (0.0 if xx == x else 0.58)), 0
            # mur fin centré sur le bord extérieur
            if yy in (y, y + h - 1):
                yc = Y(yy) - (0.12 if yy == y else 0.88)
                mb.box(xx, yc - e, 0, xx + 1, yc + e, hgt, sid)
            else:
                xc = xx + (0.12 if xx == x else 0.88)
                mb.box(xc - e, Y(yy + 1), 0, xc + e, Y(yy), hgt, sid)
    for k in range(rng.randint(3, 7)):
        px, py = rng.uniform(x + 0.8, x + w - 0.8), rng.uniform(y + 0.8, y + h - 0.8)
        mb.box(px - 0.6, Y(py) - 0.06, 0.03, px + 0.6, Y(py) + 0.06, 0.07, "wood_grey", rot=rng.uniform(0, 3.14))
    for k in range(rng.randint(1, 3)):
        clutter_cluster(mb, rng.uniform(x + 1, x + w - 1), Y(rng.uniform(y + 1, y + h - 1)), rng, rng.randint(2, 4))
    mb.to_object("ruin_%d" % b["id"], "world")


def build_building(b):
    x, y, w, h = b["rect"]
    arch = b.get("arch", "house")
    rng = random.Random(b["id"] * 7919 + SEED * 31)
    if arch == "ruin":
        build_ruin(b, rng)
        return 0, 0
    style = b.get("roof_style") or pick_roof(rng)
    rmat = roof_mat(style)
    stories = int(b.get("stories", 1))
    side = b.get("porch_side", "S") or "S"
    sid = ARCH_SIDING.get(arch) or rng.choice(SIDINGS)
    H1 = stories * STORY + rng.uniform(-0.05, 0.12)
    t = 0.42                     # épaisseur visuelle des murs (dans la case mur)
    X0, X1 = x, x + w
    YN, YS = Y(y), Y(y + h)      # YN > YS
    walls = MB()        # murs pleins (passe normale)
    cut = MB()          # murs coupés (passe intérieur) : versions basses des murs sud
    tall = MB()         # éléments masqués à l'intérieur : mur sud, fausse façade, auvent (collection roofs)
    floor = MB()
    floor.box(X0 + 0.02, YS + 0.02, 0.0, X1 - 0.02, YN - 0.02, 0.03, "floor")
    # soubassement (pierre) léger
    door_cells = set()
    for d in b.get("doors", []):
        door_cells.add(tuple(d["cell"]))
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if tile(xx, yy) == 4:
                door_cells.add((xx, yy))
    DOOR_H = 1.2

    def wall_run(target, x0_, y0_, x1_, y1_, z1, horiz, cells):
        """Mur avec trous de porte : cells = liste des cases (ordonnée) que couvre le mur."""
        # segments contigus sans porte
        segs = []
        cur = None
        for i, c in enumerate(cells):
            isdoor = c in door_cells
            if not isdoor:
                if cur is None:
                    cur = [i, i]
                else:
                    cur[1] = i
            else:
                if cur:
                    segs.append(cur)
                cur = None
                # linteau + encadrement + ouverture sombre
                if horiz:
                    cx0 = c[0]
                    target.box(cx0, y0_, DOOR_H, cx0 + 1, y1_, z1, sid)
                    target.box(cx0 + 0.12, y0_ + 0.05, 0.0, cx0 + 0.88, y1_ - 0.05, DOOR_H, "doorway")
                    for ex in (cx0 + 0.04, cx0 + 0.88):
                        target.box(ex, y0_ - 0.04, 0.0, ex + 0.08, y1_ + 0.04, DOOR_H + 0.08, "trim")
                    target.box(cx0 + 0.04, y0_ - 0.04, DOOR_H, cx0 + 0.96, y1_ + 0.04, DOOR_H + 0.1, "trim")
                else:
                    cy0 = Y(c[1] + 1)
                    target.box(x0_, cy0, DOOR_H, x1_, cy0 + 1, z1, sid)
                    target.box(x0_ + 0.05, cy0 + 0.12, 0.0, x1_ - 0.05, cy0 + 0.88, DOOR_H, "doorway")
                    target.box(x0_ - 0.04, cy0 + 0.04, DOOR_H, x1_ + 0.04, cy0 + 0.96, DOOR_H + 0.1, "trim")
        if cur:
            segs.append(cur)
        for (i0, i1) in segs:
            if horiz:
                a, bb = max(cells[i0][0], x0_), min(cells[i1][0] + 1, x1_)
                target.box(a, y0_, 0.0, bb, y1_, z1, sid)
            else:
                a, bb = Y(cells[i1][1] + 1), Y(cells[i0][1])
                a, bb = max(a, y0_), min(bb, y1_)
                target.box(x0_, a, 0.0, x1_, bb, z1, sid)

    south = [(xx, y + h - 1) for xx in range(x, x + w)]
    north = [(xx, y) for xx in range(x, x + w)]
    west = [(x, yy) for yy in range(y, y + h)]
    east = [(x + w - 1, yy) for yy in range(y, y + h)]
    wall_run(walls, X0, YN - t, X1, YN, H1, True, north)
    wall_run(walls, X0, YS + 0.001, X0 + t, YN, H1, False, west)
    wall_run(walls, X1 - t, YS + 0.001, X1, YN, H1, False, east)
    wall_run(tall, X0, YS, X1, YS + t, H1, True, south)
    # mur sud coupé (intérieur) : muret
    for xx in range(x, x + w):
        if (xx, y + h - 1) not in door_cells:
            cut.box(xx, YS, 0.0, xx + 1, YS + t, 0.32, sid)
    cut.box(X0, YS - 0.02, 0.32, X1, YS + t + 0.02, 0.38, "trim")
    # cloisons intérieures
    for yy in range(y + 1, y + h - 1):
        for xx in range(x + 1, x + w - 1):
            if tile(xx, yy) == 3:
                walls.box(xx + 0.1, Y(yy + 1) + 0.1, 0.0, xx + 0.9, Y(yy) - 0.1, H1 * 0.98, "siding_h")
    # plinthes / angles
    for (cx_, cy_) in ((X0, YS), (X1, YS), (X0, YN), (X1, YN)):
        tgt = tall if cy_ == YS else walls
        tgt.box(cx_ - 0.07, cy_ - 0.07, 0.0, cx_ + 0.07, cy_ + 0.07, H1 + 0.02, "trim")
    # bandeau d'étage
    if stories > 1:
        tall.box(X0 - 0.03, YS - 0.06, STORY - 0.05, X1 + 0.03, YS + 0.02, STORY + 0.05, "trim")
        walls.box(X0 - 0.06, YS, STORY - 0.05, X0 + 0.02, YN, STORY + 0.05, "trim")
        walls.box(X1 - 0.02, YS, STORY - 0.05, X1 + 0.06, YN, STORY + 0.05, "trim")
    # fenêtres
    shut = rng.choice([None, None, "trim", "wood_grey", "sign_red", "siding_teal"])
    frame = rng.choice(["trim", "trim", "trim_white", "wood_grey"])
    for st in range(stories):
        z0 = st * STORY + 0.55
        z1 = z0 + 0.55
        # sud (façade, visible) — dans `tall`
        xs = [xx for xx in range(x + 1, x + w - 1) if (xx, y + h - 1) not in door_cells and (xx - 1, y + h - 1) not in door_cells and (xx + 1, y + h - 1) not in door_cells]
        step = 2 if w > 5 else 3
        for i, xx in enumerate(xs[::step]):
            window(tall, "x", YS, xx + 0.5, z0, z1, 0.5, -1, rng, frame, shut, lit=rng.random() < 0.12, boarded=rng.random() < 0.12)
        # est / ouest
        for (xp, sg, run) in ((X0, -1, west), (X1, 1, east)):
            ys_ = [c[1] for c in run[1:-1] if c not in door_cells]
            for yy in ys_[1::3]:
                if rng.random() < 0.7:
                    window(walls, "y", xp, Y(yy) - 0.5, z0, z1, 0.45, sg, rng, frame, None, lit=rng.random() < 0.1)
    # ---------------- toiture (collection roofs)
    roof = MB()
    gm = sid
    annex = None
    if w >= 6 and h >= 4 and rng.random() < 0.5:
        annex = ("E" if rng.random() < 0.5 else "W", min(2 + (w >= 8), w // 3))
    elif h >= 7 and w >= 4 and rng.random() < 0.45:
        annex = ("N", min(2 + (h >= 9), h // 3))
    mx0, mx1, my0, my1 = X0, X1, YS, YN
    if annex:
        s_, k = annex
        if s_ == "E":
            mx1 = X1 - k
        elif s_ == "W":
            mx0 = X0 + k
        else:
            my1 = YN - k
    mw, mh = mx1 - mx0, my1 - my0
    # Maquette : faîtage majoritairement nord-sud (pans est/ouest, l'un au soleil, l'autre à
    # l'ombre) ; est-ouest seulement pour les bâtiments nettement plus larges que profonds.
    if mw >= mh * 1.5:
        ridge_x = rng.random() < 0.75
    else:
        ridge_x = rng.random() < 0.15
    span = mh if ridge_x else mw
    rise = min(0.32 * span + 0.15, 1.7)
    if style in ("plank", "shingle"):
        rise *= 1.1
    has_ff = side == "S" and (arch in FALSE_FRONT or rng.random() < 0.28)
    top = gable(roof, mx0, my0, mx1, my1, H1, rmat, ridge_x, rise, 0.24, gm, rng, ov_s=(-0.02 if has_ff else None))
    # pignons/annexes
    if annex:
        s_, k = annex
        sec_mat = rmat if rng.random() < 0.45 else rng.choice(["roof_planks", "tin_grey", "tin_rust", "tin_blue"])
        zh = H1 - 0.05
        zl = H1 - 0.45 - 0.08 * k
        if s_ == "E":
            shed(roof, mx1, YS, X1, YN, zh, zl, sec_mat, "E")
        elif s_ == "W":
            shed(roof, X0, YS, mx0, YN, zh, zl, sec_mat, "W")
        else:
            shed(roof, X0, my1, X1, YN, zh, zl, sec_mat, "N")
    # rapiéçages, trous, cheminées, tuyaux
    for _ in range(rng.randint(1, 4)):
        px = rng.uniform(mx0 + 0.4, mx1 - 1.4)
        py = rng.uniform(my0 + 0.3, my1 - 1.2)
        pm = rng.choice(["tin_rust", "tin_grey", "roof_planks", "tin_blue"])
        if ridge_x:
            ym = (my0 + my1) / 2
            on_s = py < ym
            zz = lambda yv: H1 + rise * (1 - abs(yv - ym) / ((my1 - my0) / 2)) + 0.09
            pl, ph_ = (py, min(py + rng.uniform(0.5, 1.0), ym - 0.05)) if on_s else (max(py, ym + 0.05), py + rng.uniform(0.5, 1.0))
            if ph_ - pl < 0.2:
                continue
            pw_ = rng.uniform(0.6, 1.3)
            roof.poly([(px, pl, zz(pl)), (px + pw_, pl, zz(pl)), (px + pw_, ph_, zz(ph_)), (px, ph_, zz(ph_))][::(1 if on_s else -1)], pm,
                      [(0, 0), (pw_, 0), (pw_, ph_ - pl), (0, ph_ - pl)][::(1 if on_s else -1)])
        else:
            xm_ = (mx0 + mx1) / 2
            hw = (mx1 - mx0) / 2
            zx = lambda xv: H1 + rise * (1 - abs(xv - xm_) / hw) + 0.09
            pw_ = rng.uniform(0.5, 1.0)
            ln = rng.uniform(0.7, 1.6)
            on_w = px + pw_ / 2 < xm_
            xa_, xb_ = (px, min(px + pw_, xm_ - 0.05)) if on_w else (max(px, xm_ + 0.05), px + pw_)
            if xb_ - xa_ < 0.2:
                continue
            pts_ = [(xa_, py, zx(xa_)), (xb_, py, zx(xb_)), (xb_, py + ln, zx(xb_)), (xa_, py + ln, zx(xa_))]
            roof.poly(pts_ if True else pts_[::-1], pm, [(0, 0), (0, xb_ - xa_), (ln, xb_ - xa_), (ln, 0)])
    if rng.random() < 0.75:
        cxp = rng.uniform(mx0 + 0.6, mx1 - 0.6)
        cyp = rng.uniform(my0 + 0.4, my1 - 0.4)
        if rng.random() < 0.55:
            roof.cyl(cxp, cyp, H1, top + 0.55, 0.07, "iron", 8)
            roof.cyl(cxp, cyp, top + 0.55, top + 0.68, 0.12, "iron", 8, r2=0.02)
        else:
            roof.box(cxp - 0.2, cyp - 0.2, H1, cxp + 0.2, cyp + 0.2, top + 0.45, "brick")
            roof.box(cxp - 0.24, cyp - 0.24, top + 0.45, cxp + 0.24, cyp + 0.24, top + 0.53, "stone")
    # ---------------- fausse façade + enseigne (côté sud uniquement : visible caméra)
    ff_top = None
    if has_ff:
        ff_top = top + rng.uniform(0.25, 0.6)
        fx0, fx1 = (X0, X1) if not annex or annex[0] == "N" else (mx0, mx1)
        tall.box(fx0 - 0.04, YS, H1 - 0.05, fx1 + 0.04, YS + 0.16, ff_top, sid)
        tall.box(fx0 - 0.1, YS - 0.08, ff_top, fx1 + 0.1, YS + 0.22, ff_top + 0.1, "trim")
        tall.box(fx0 - 0.06, YS - 0.05, ff_top - 0.18, fx1 + 0.06, YS + 0.01, ff_top - 0.12, "trim")
        if rng.random() < 0.5:
            mxf = (fx0 + fx1) / 2
            tall.box(mxf - 0.5, YS, ff_top, mxf + 0.5, YS + 0.16, ff_top + 0.3, sid)
            tall.box(mxf - 0.56, YS - 0.06, ff_top + 0.3, mxf + 0.56, YS + 0.2, ff_top + 0.38, "trim")
        # contrefiches derrière
        sw = min((fx1 - fx0) * 0.62, 4.5)
        mxf = (fx0 + fx1) / 2
        sm = rng.choice(["sign", "sign", "sign_red", "trim_white"])
        tall.box(mxf - sw / 2, YS - 0.05, H1 + 0.15, mxf + sw / 2, YS, ff_top - 0.28, sm)
        tall.box(mxf - sw / 2 - 0.05, YS - 0.08, H1 + 0.1, mxf + sw / 2 + 0.05, YS - 0.03, H1 + 0.16, "trim")
        tall.box(mxf - sw / 2 - 0.05, YS - 0.08, ff_top - 0.3, mxf + sw / 2 + 0.05, YS - 0.03, ff_top - 0.24, "trim")
        # « lettres » : traits sombres génériques
        n_l = max(3, int(sw / 0.35))
        for i in range(n_l):
            lx = mxf - sw / 2 + 0.2 + i * (sw - 0.4) / max(n_l - 1, 1)
            if rng.random() < 0.85:
                tall.box(lx - 0.07, YS - 0.07, H1 + 0.3, lx + 0.07, YS - 0.045, ff_top - 0.45,
                         "trim_white" if sm != "trim_white" else "trim")
    # ---------------- porche / véranda
    porch = MB()
    aw = MB()
    pdepth = 1.0
    if side == "S" and (arch != "shack" or rng.random() < 0.5):
        xa, xb = X0 + (0.0 if rng.random() < 0.6 else 0.5), X1 - (0.0 if rng.random() < 0.6 else 0.5)
        ya, yb = YS - pdepth, YS
        porch.box(xa, ya, 0.0, xb, yb, 0.14, "deck")
        porch.box(xa, ya - 0.02, 0.0, xb, ya + 0.06, 0.12, "trim")
        z_hi = min(H1 - 0.05, STORY * 0.98)
        z_lo = z_hi - 0.32
        n = max(2, int((xb - xa) / 1.8) + 1)
        for i in range(n):
            px = xa + 0.1 + (xb - xa - 0.2) * i / (n - 1)
            porch.box(px - 0.055, ya + 0.04, 0.14, px + 0.055, ya + 0.15, z_lo, "wood")
        if rng.random() < 0.5:
            for (r0, r1) in ((xa + 0.1, xa + (xb - xa) * 0.35), (xb - (xb - xa) * 0.35, xb - 0.1)):
                porch.box(r0, ya + 0.07, 0.6, r1, ya + 0.12, 0.66, "wood_grey")
        am = rng.choice(["tin_grey", "roof_planks", "tin_rust", rmat]) if arch != "saloon" else "roof_planks"
        shed(aw, xa - 0.05, ya - 0.05, xb + 0.05, yb, z_hi, z_lo, am, "S", ov=0.05)
        if stories > 1 and rng.random() < 0.7:
            # balcon
            for i in range(int((xb - xa) / 0.25)):
                bx = xa + 0.1 + i * 0.25
                aw.box(bx - 0.02, ya + 0.05, z_hi + 0.05, bx + 0.02, ya + 0.09, z_hi + 0.5, "trim")
            aw.box(xa, ya + 0.04, z_hi + 0.48, xb, ya + 0.12, z_hi + 0.55, "trim")
    elif side in ("E", "W") and rng.random() < 0.7:
        xa, xb = (X1, X1 + pdepth) if side == "E" else (X0 - pdepth, X0)
        porch.box(xa, YS + 0.3, 0.0, xb, YN - 0.3, 0.12, "deck")
        z_hi = min(H1 - 0.1, STORY)
        shed(aw, xa, YS + 0.3, xb, YN - 0.3, z_hi, z_hi - 0.3, rng.choice(["tin_grey", "roof_planks"]), side, ov=0.05)
        for yy_ in (YS + 0.4, YN - 0.4):
            px = xb - 0.1 if side == "E" else xa + 0.1
            porch.box(px - 0.05, yy_ - 0.05, 0.12, px + 0.05, yy_ + 0.05, z_hi - 0.3, "wood")
    elif side == "S":
        # perron simple
        for d in door_cells:
            if d[1] == y + h - 1:
                porch.box(d[0] + 0.05, YS - 0.45, 0.0, d[0] + 0.95, YS, 0.12, "deck")
    # ---------------- objets
    ob = walls.to_object("walls_%d" % b["id"], "world")
    floor.to_object("floor_%d" % b["id"], "world")
    porch.to_object("porch_%d" % b["id"], "world")
    for mbx, nm in ((roof, "roof"), (tall, "front"), (aw, "awning")):
        if mbx.F:
            mbx.to_object("%s_%d" % (nm, b["id"]), "roofs")
    co_ = cut.to_object("cut_%d" % b["id"], "world")
    co_.hide_render = True
    return H1, top


def build_interior_furniture(b, rng):
    """Mobilier simple (si le layout ne fournit pas de props intérieurs)."""
    x, y, w, h = b["rect"]
    mb = MB()
    has = any(bld_cells.get((p["cell"][0], p["cell"][1])) is b for p in LAYOUT["props"])
    if has or b.get("arch") == "ruin":
        return
    if w >= 5 and h >= 5 and rng.random() < 0.7:
        cx, cy = x + w / 2, Y(y + h / 2)
        mb.box(cx - 0.9, cy - 0.6, 0.03, cx + 0.9, cy + 0.6, 0.04, "rug")
        prop(mb, "table_chairs", cx, cy, 1, 1, rng)
    for i in range(rng.randint(1, 3)):
        xx = rng.uniform(x + 1.2, x + w - 1.2)
        prop(mb, rng.choice(["shelf", "barrel", "crate_stack", "dresser"]), xx, Y(y) - 0.85, 1, 1, rng)
    mb.to_object("furn_%d" % b["id"], "world")


# ======================================================================= rochers
def cellset_ray(S, x, y, ang, maxd=8.0, step=0.04):
    """Distance (cases) depuis (x, y) (repère Blender) jusqu'à la sortie de l'ensemble de cases S
    dans la direction `ang`."""
    dx, dy = math.cos(ang), math.sin(ang)
    d = 0.0
    while d < maxd:
        px, py = x + dx * d, y + dy * d
        if (int(math.floor(px)), int(math.floor(-py))) not in S:
            return d
        d += step
    return maxd


def slab(mb, cx, cy, z, rx, ry, h, rng, rot=0.0, seg=22, clamp=None, inset=0.06):
    """Bloc de grès arrondi : profil latéral bombé + dessus en dôme bosselé (grille polaire).
    clamp : ensemble de cases (x, rangée) ; le contour est alors rogné pour rester dans ces cases
    (à `inset` près) : l'emprise rendue = les cases bloquantes du plan."""
    ph = [rng.uniform(0, 50) for _ in range(3)]
    rad = []
    for j in range(seg):
        a = j / seg * math.tau
        k = 1.0 + 0.26 * mnoise.noise(Vector((math.cos(a) * 0.9 + ph[0], math.sin(a) * 0.9 + ph[1], z * 0.5))) \
            + 0.10 * mnoise.noise(Vector((math.cos(a) * 2.5 + ph[1], math.sin(a) * 2.5, z * 2))) \
            + 0.04 * mnoise.noise(Vector((math.cos(a) * 7 + ph[0], math.sin(a) * 7, z * 4)))
        rad.append(k)
    cr, sr = math.cos(rot), math.sin(rot)
    lim = None
    if clamp is not None:
        lim = []
        for j in range(seg):
            a = j / seg * math.tau
            lx, ly = math.cos(a) * rx * rad[j], math.sin(a) * ry * rad[j]
            ang = math.atan2(lx * sr + ly * cr, lx * cr - ly * sr)
            lim.append(max(cellset_ray(clamp, cx, cy, ang) - inset, 0.05))
    tilt = (rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12))
    # (hauteur relative, facteur de rayon) : flanc bombé puis dôme
    prof = [(0.0, 0.9), (0.12, 0.99), (0.5, 1.0), (0.82, 0.97), (0.94, 0.88), (1.0, 0.7), (1.04, 0.4), (1.06, 0.12)]
    rings = []
    for (fz, fk) in prof:
        ring = []
        for j in range(seg):
            a = j / seg * math.tau
            lx, ly = math.cos(a) * rx * rad[j] * fk, math.sin(a) * ry * rad[j] * fk
            bump = 0.0
            if fz > 0.8:
                bump = 0.12 * h * mnoise.noise(Vector((lx * 1.3 + ph[2], ly * 1.3, z)))
            zz = z + h * fz + bump + (lx * tilt[0] + ly * tilt[1]) * (fz > 0.5)
            wx, wy = lx * cr - ly * sr, lx * sr + ly * cr
            if lim is not None:
                rr_ = math.hypot(wx, wy)
                if rr_ > lim[j]:
                    wx, wy = wx * lim[j] / rr_, wy * lim[j] / rr_
            ring.append(mb.v((cx + wx, cy + wy, zz)))
        rings.append(ring)
    mi = mb.mi("rock")
    for r0, r1 in zip(rings, rings[1:]):
        for j in range(seg):
            j2 = (j + 1) % seg
            mb.F.append([(r0[j], r0[j2], r1[j2], r1[j]), mi])
    c = mb.v((cx, cy, z + h * 1.09))
    for j in range(seg):
        mb.F.append([(rings[-1][j], rings[-1][(j + 1) % seg], c), mi])
    mb.F.append([tuple(reversed(rings[0])), mi])


def rock_formation(mb, cells, height, rng):
    """Formation de grès façon maquette : colonnes de galettes stratifiées empilées (strates
    bien lisibles), de hauteurs variées. Les colonnes COUVRENT toutes les cases de la formation
    (couverture gloutonne depuis les cases les plus profondes) et leur contour est rogné aux cases
    (slab clamp) : l'emprise rendue correspond exactement aux cases murées du plan."""
    S = set(tuple(c) for c in cells)
    xs = [c[0] + 0.5 for c in cells]
    ys = [c[1] + 0.5 for c in cells]
    cx, cyr = sum(xs) / len(xs), sum(ys) / len(ys)
    rmax = max(math.hypot(x - cx, y - cyr) for x, y in zip(xs, ys)) + 0.5
    cy = -cyr
    # profondeur (distance au bord, en cases) de chaque case
    N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
    depth = {}
    queue = []
    for c in sorted(S):
        if any((c[0] + dx, c[1] + dy) not in S for dx, dy in N4):
            depth[c] = 0
            queue.append(c)
    i = 0
    while i < len(queue):
        c = queue[i]
        i += 1
        for dx, dy in N4:
            n = (c[0] + dx, c[1] + dy)
            if n in S and n not in depth:
                depth[n] = depth[c] + 1
                queue.append(n)
    dmax = max(depth.values()) if depth else 0
    order = sorted(S, key=lambda c: (-depth[c], rng.random()))
    uncovered = set(S)
    top_z = 0.0
    ncol = 0
    for c in order:
        if c not in uncovered:
            continue
        if ncol >= 40:
            break
        px, py = c[0] + 0.5 + rng.uniform(-0.15, 0.15), c[1] + 0.5 + rng.uniform(-0.15, 0.15)
        r = min(depth[c] + 1.0, 4.2)
        first = ncol == 0
        ncol += 1
        k_h = 1.0 if first else (0.45 + 0.5 * min(1.0, (depth[c] + 1.0) / (dmax + 1.0)))
        hcol = height * rng.uniform(0.88, 1.12) * k_h
        z = 0.0
        rx, ry = r * rng.uniform(1.0, 1.35), r * rng.uniform(0.9, 1.1)
        ox, oy = 0.0, 0.0
        while z < hcol:
            hh = rng.uniform(0.5, 0.8)
            slab(mb, px + ox, -py + oy, z, rx, ry, hh, rng, rng.uniform(0, math.pi), 40, clamp=S,
                 inset=rng.uniform(0.04, 0.12))
            z += hh * 0.9
            k = rng.uniform(0.9, 1.0) if z < hcol * 0.75 else rng.uniform(0.7, 0.85)
            rx *= k
            ry *= k * rng.uniform(0.97, 1.03)
            ox += rng.uniform(-0.12, 0.12)
            oy += rng.uniform(-0.12, 0.12)
            if rx < 0.3:
                break
        top_z = max(top_z, z)
        for q in list(uncovered):
            if math.hypot(q[0] + 0.5 - px, q[1] + 0.5 - py) <= r * 0.8 + 0.25:
                uncovered.discard(q)
    # éboulis : cailloux plats (sous le plan de coupe du masque, non bloquants)
    for _ in range(int(6 + rmax * 5)):
        a = rng.uniform(0, math.tau)
        rr = rmax * rng.uniform(0.9, 1.4)
        r = rng.uniform(0.04, 0.13)
        mb.sphere(cx + math.cos(a) * rr, cy + math.sin(a) * rr, r * 0.15, r, "rock", sub=1, sx=1.2, sz=0.5, jitter=0.25, rng=rng)
    prof = [rmax] * 24
    return (cx, cy, [(cx, cy, top_z, 1.0)], prof, rmax)


def scree(mb, cells, height, rng):
    """Éboulis : amas de blocs bas posés sur l'emprise (cases murs)."""
    S = set(tuple(c) for c in cells)
    for (cx, cy) in cells:
        for k in range(rng.randint(1, 2)):
            px, py = cx + rng.uniform(0.3, 0.7), cy + rng.uniform(0.3, 0.7)
            r = rng.uniform(0.38, 0.6)
            z = 0.0
            for j in range(rng.randint(1, 2)):
                hh = rng.uniform(0.25, 0.45) * height
                slab(mb, px, -py, z, r * rng.uniform(1.0, 1.3), r, hh, rng, rng.uniform(0, 3), 18, clamp=S, inset=0.05)
                z += hh * 0.85
                r *= 0.75
    for _ in range(len(cells) * 2):
        c = rng.choice(cells)
        mb.sphere(c[0] + rng.uniform(-0.3, 1.3), -(c[1] + rng.uniform(-0.3, 1.3)), 0.02, rng.uniform(0.04, 0.12), "rock", sub=1,
                  sx=1.2, sz=0.5, jitter=0.25, rng=rng)


# ======================================================================= végétation
def shrub(mb, x, y, s, rng, mat=None):
    mat = mat or rng.choice(["foliage", "foliage2", "sage", "sage", "dry"])
    for i in range(rng.randint(4, 8)):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0, 0.22) * s
        r = rng.uniform(0.12, 0.22) * s
        mb.sphere(x + math.cos(a) * d, y + math.sin(a) * d, r * 0.7 + rng.uniform(0, 0.1) * s, r, mat, sub=1, sz=0.8, jitter=0.35, rng=rng)


def grass(mb, x, y, s, rng):
    m = rng.choice(["dry", "dry", "dry", "sage"])
    mb.sphere(x, y, 0.02, 0.1 * s, m, sub=1, sz=0.5, jitter=0.3, rng=rng)
    for i in range(rng.randint(9, 16)):
        a = rng.uniform(0, math.tau)
        L = rng.uniform(0.2, 0.38) * s
        lean = rng.uniform(0.3, 0.8)
        mb.seg((x + math.cos(a) * 0.04, y + math.sin(a) * 0.04, 0), (x + math.cos(a) * L * lean, y + math.sin(a) * L * lean, L * 0.8), 0.03 * s, m, 3, r2=0.004)


def tree(mb, x, y, s, rng, kind="tree"):
    if kind == "dead":
        p0 = Vector((x, y, 0))
        p1 = Vector((x + rng.uniform(-0.1, 0.1), y + rng.uniform(-0.1, 0.1), 1.0 * s))
        mb.seg(p0, p1, 0.06 * s, "deadwood", 6, r2=0.04 * s)
        for i in range(rng.randint(3, 5)):
            a = rng.uniform(0, math.tau)
            q0 = p0.lerp(p1, rng.uniform(0.5, 1.0))
            q1 = q0 + Vector((math.cos(a) * 0.5 * s, math.sin(a) * 0.5 * s, rng.uniform(0.2, 0.5) * s))
            mb.seg(q0, q1, 0.03 * s, "deadwood", 5, r2=0.008)
            q2 = q1 + Vector((math.cos(a + 0.6) * 0.25 * s, math.sin(a + 0.6) * 0.25 * s, 0.15 * s))
            mb.seg(q1, q2, 0.012 * s, "deadwood", 4, r2=0.004)
        return
    if kind == "agave":
        # agave / yucca touffu (rosette de feuilles), vert sombre — sommets des mesas
        for k in range(26):
            a = rng.uniform(0, math.tau)
            el = rng.uniform(0.15, 1.2)
            L = rng.uniform(0.45, 0.7) * s
            mb.seg((x, y, 0.05), (x + math.cos(a) * math.cos(el) * L, y + math.sin(a) * math.cos(el) * L, 0.05 + math.sin(el) * L),
                   0.06 * s, "foliage", 3, r2=0.006)
        return
    if kind == "joshua":
        p0 = Vector((x, y, 0))
        p1 = Vector((x, y, 0.9 * s))
        mb.seg(p0, p1, 0.09 * s, "bark", 7, r2=0.07 * s)
        for i in range(rng.randint(3, 5)):
            a = rng.uniform(0, math.tau)
            q1 = p1 + Vector((math.cos(a) * 0.45 * s, math.sin(a) * 0.45 * s, rng.uniform(0.25, 0.6) * s))
            mb.seg(p1, q1, 0.06 * s, "bark", 6, r2=0.045 * s)
            for k in range(14):
                b2 = rng.uniform(0, math.tau)
                el = rng.uniform(-0.3, 1.2)
                L = rng.uniform(0.15, 0.28) * s
                mb.seg(q1, q1 + Vector((math.cos(b2) * math.cos(el) * L, math.sin(b2) * math.cos(el) * L, math.sin(el) * L)),
                       0.022 * s, "foliage2", 3, r2=0.003)
        return
    # arbuste/arbre du désert (mesquite) : tronc + houppier en boules
    p0 = Vector((x, y, 0))
    p1 = Vector((x + rng.uniform(-0.15, 0.15), y + rng.uniform(-0.15, 0.15), 0.7 * s))
    mb.seg(p0, p1, 0.07 * s, "bark", 6, r2=0.05 * s)
    for i in range(rng.randint(5, 8)):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.1, 0.5) * s
        mb.sphere(p1.x + math.cos(a) * d, p1.y + math.sin(a) * d, p1.z + rng.uniform(0.0, 0.4) * s, rng.uniform(0.22, 0.36) * s,
                  rng.choice(["foliage", "foliage2"]), sub=2, sz=0.75, nscale=2.0, rng=rng)


def cactus(mb, x, y, s, rng):
    h = rng.uniform(0.8, 1.4) * s
    mb.cyl(x, y, 0, h, 0.09 * s, "cactus", 10)
    mb.sphere(x, y, h, 0.09 * s, "cactus", sub=1)
    for sg in (-1, 1):
        if rng.random() < 0.75:
            z = rng.uniform(0.3, 0.55) * h
            a = rng.uniform(0, math.pi) if False else (0.0 if sg > 0 else math.pi) + rng.uniform(-0.6, 0.6)
            dx, dy = math.cos(a) * 0.24 * s, math.sin(a) * 0.24 * s
            mb.seg((x, y, z), (x + dx, y + dy, z), 0.06 * s, "cactus", 8)
            top = z + rng.uniform(0.25, 0.45) * h
            mb.cyl(x + dx, y + dy, z, top, 0.06 * s, "cactus", 8)
            mb.sphere(x + dx, y + dy, top, 0.06 * s, "cactus", sub=1)


# ======================================================================= props
def barrel(mb, x, y, rng, s=1.0):
    r = 0.2 * s
    h = 0.52 * s
    mb.cyl(x, y, 0, h * 0.5, r, "wood", 12, r2=r * 1.12)
    mb.cyl(x, y, h * 0.5, h, r * 1.12, "wood", 12, r2=r)
    for z in (0.08, h * 0.5 - 0.02, h - 0.1):
        mb.cyl(x, y, z * 1, z + 0.035, r * (1.13 if 0.15 < z < h - 0.15 else 1.04), "iron", 12)
    mb.cyl(x, y, h, h + 0.01, r * 0.92, "wood_dark", 12)


def crate(mb, x, y, s, rng, z=0.0, rot=0.0):
    e = 0.04
    h = s
    mb.box(x - s / 2, y - s / 2, z, x + s / 2, y + s / 2, z + h, "crate", rot=rot, piv=(x, y))
    for (a, b_) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        mb.box(x + a * s / 2 - e, y + b_ * s / 2 - e, z, x + a * s / 2 + e, y + b_ * s / 2 + e, z + h, "wood_dark", rot=rot, piv=(x, y))
    for zz in (z, z + h - e * 1.5):
        mb.box(x - s / 2 - 0.01, y - s / 2 - 0.01, zz, x + s / 2 + 0.01, y + s / 2 + 0.01, zz + e * 1.5, "wood", rot=rot, piv=(x, y))


def wheel(mb, x, y, z, r, axis, mat="wood_dark", rot=0.0):
    """Roue (disque vertical) dont l'essieu suit l'axe Y local tourné de rot."""
    mb.cyl(x, y, z, 0.07, r, mat, 16, axis="Y", rot=rot)
    mb.cyl(x, y, z, 0.12, r * 0.25, "iron", 10, axis="Y", rot=rot)
    for k in range(4):
        a = k * math.pi / 4
        d = Vector((math.cos(a) * r * 0.9, 0, math.sin(a) * r * 0.9))
        d.rotate(Matrix.Rotation(rot, 3, "Z"))
        mb.seg((x - d.x, y - d.y, z - d.z), (x + d.x, y + d.y, z + d.z), 0.025, mat, 4)


def local(x, y, rot, lx, ly):
    c, s = math.cos(rot), math.sin(rot)
    return x + lx * c - ly * s, y + lx * s + ly * c


def wagon(mb, x, y, rot, rng, covered=True):
    L, Wd = 2.3, 0.95
    mb.box(x - L / 2, y - Wd / 2, 0.42, x + L / 2, y + Wd / 2, 0.52, "wood", rot=rot, piv=(x, y))
    for sg in (-1, 1):
        mb.box(x - L / 2, y + sg * Wd / 2 - 0.04, 0.52, x + L / 2, y + sg * Wd / 2 + 0.04, 0.82, "wood_grey", rot=rot, piv=(x, y))
    for sg in (-1, 1):
        mb.box(x + sg * L / 2 - 0.04, y - Wd / 2, 0.52, x + sg * L / 2 + 0.04, y + Wd / 2, 0.8, "wood_grey", rot=rot, piv=(x, y))
    for (lx, r) in ((-0.75, 0.42), (0.75, 0.33)):
        for sg in (-1, 1):
            px, py = local(x, y, rot, lx, sg * (Wd / 2 + 0.06))
            wheel(mb, px, py, r, r, "Y", rot=rot)
    # timon
    a = local(x, y, rot, L / 2, 0)
    b_ = local(x, y, rot, L / 2 + 1.1, 0)
    mb.seg((a[0], a[1], 0.4), (b_[0], b_[1], 0.15), 0.035, "wood_dark", 5)
    if covered:
        # bâche : demi-cylindre le long de l'axe
        n = 10
        R = Wd / 2 + 0.06
        zc = 0.82
        rings = []
        for lx in (-L / 2 + 0.05, L / 2 - 0.05):
            ring = []
            for j in range(n + 1):
                a_ = math.pi * j / n
                px, py = local(x, y, rot, lx, math.cos(a_) * R)
                ring.append(mb.bm.verts.new((px, py, zc + math.sin(a_) * R * 1.15)))
            rings.append(ring)
        mi = mb.mi("canvas")
        for j in range(n):
            f = mb.bm.faces.new((rings[0][j], rings[0][j + 1], rings[1][j + 1], rings[1][j]))
            f.material_index = mi
        for k in (0, 1):
            f = mb.bm.faces.new(rings[k] if k else list(reversed(rings[k])))
            f.material_index = mi
        for lx in (-0.6, 0.0, 0.6):
            pts = []
            for j in range(n + 1):
                a_ = math.pi * j / n
                px, py = local(x, y, rot, lx, math.cos(a_) * (R + 0.02))
                pts.append((px, py, zc + math.sin(a_) * (R + 0.02) * 1.15))
            for j in range(n):
                mb.seg(pts[j], pts[j + 1], 0.02, "wood_dark", 3)
    else:
        # chargement : tonneaux, caisses, sacs, bâche froissée
        for i in range(rng.randint(3, 6)):
            lx = rng.uniform(-0.85, 0.75)
            px, py = local(x, y, rot, lx, rng.uniform(-0.25, 0.25))
            r = rng.random()
            if r < 0.3:
                mb.cyl(px, py, 0.52, 0.9, 0.16, "wood", 10)
                mb.cyl(px, py, 0.6, 0.63, 0.165, "iron", 10)
            elif r < 0.6:
                crate(mb, px, py, rng.uniform(0.26, 0.36), rng, 0.52, rot + rng.uniform(-0.3, 0.3))
            elif r < 0.85:
                mb.sphere(px, py, 0.62, 0.17, "sack", sub=2, sx=1.3, sz=0.6, jitter=0.12, rng=rng)
            else:
                mb.sphere(px, py, 0.6, 0.35, "canvas", sub=2, sx=1.4, sy=1.0, sz=0.35, nscale=1.5, rng=rng)


def mine_cart(mb, x, y, rot, rng):
    mb.box(x - 0.45, y - 0.32, 0.18, x + 0.45, y + 0.32, 0.62, "rust_iron", rot=rot, piv=(x, y))
    mb.box(x - 0.38, y - 0.25, 0.5, x + 0.38, y + 0.25, 0.64, "stone", rot=rot, piv=(x, y))
    for lx in (-0.28, 0.28):
        for sg in (-1, 1):
            px, py = local(x, y, rot, lx, sg * 0.34)
            wheel(mb, px, py, 0.13, 0.13, "Y", "iron", rot=rot)


def fence_line(mb, pts, rng, style=None):
    """Clôture de planches (style « plank », palissade comme la maquette) ou à lisses (« rail »)."""
    style = style or ("plank" if rng.random() < 0.65 else "rail")
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        p0 = Vector((x0 + 0.5, Y(y0) - 0.5, 0))
        p1 = Vector((x1 + 0.5, Y(y1) - 0.5, 0))
        L = (p1 - p0).length
        if L < 1e-3:
            continue
        d = (p1 - p0) / L
        nrm = Vector((-d.y, d.x, 0))
        n = max(1, int(round(L / 1.2)))
        posts = [p0.lerp(p1, k / n) for k in range(n + 1)]
        hgt = rng.uniform(0.95, 1.15) if style == "plank" else rng.uniform(0.85, 1.0)
        for k, p in enumerate(posts):
            mb.box(p.x - 0.07, p.y - 0.07, 0, p.x + 0.07, p.y + 0.07, hgt + 0.08, "wood_dark")
        if style == "plank":
            m = int(L / 0.2)
            t = 0.0
            while t < L - 0.05:
                bw = rng.uniform(0.14, 0.22)
                if rng.random() < 0.06:
                    t += bw
                    continue
                c = p0 + d * (t + bw / 2)
                hh = hgt * rng.uniform(0.85, 1.0) if rng.random() > 0.08 else hgt * rng.uniform(0.3, 0.6)
                ang = math.atan2(d.y, d.x)
                mb.box(c.x - bw / 2 + 0.01, c.y - 0.025, 0.0, c.x + bw / 2 - 0.01, c.y + 0.025, hh, "wood_grey", rot=ang, piv=(c.x, c.y))
                t += bw
            for zr in (0.25, hgt - 0.2):
                q0, q1 = p0 + nrm * 0.05, p1 + nrm * 0.05
                mb.seg((q0.x, q0.y, zr), (q1.x, q1.y, zr), 0.04, "wood_dark", 4)
        else:
            for k in range(n):
                p, q = posts[k], posts[k + 1]
                for zr in (0.3, 0.6, 0.85):
                    if rng.random() < 0.88:
                        mb.seg((p.x, p.y, zr), (q.x, q.y, zr + rng.uniform(-0.05, 0.05)), 0.055, "wood_grey", 4)


def prop(mb, k, x, y, sw, sh, rng, rot=0.0):
    if k == "deck":
        # plancher / trottoir de planches (cell = coin haut-gauche, size = emprise)
        x0, y0 = x - 0.5, y + 0.5
        mb.box(x0, y0 - sh, 0.0, x0 + sw, y0, 0.12, "deck")
        for i in range(int(sw) + 1):
            mb.box(x0 + i - 0.05 if i else x0, y0 - sh, 0.0, x0 + i + 0.05 if i < sw else x0 + sw, y0, 0.13, "trim") if i in (0, int(sw)) else None
        return
    if k == "mine_rail":
        for i in range(3):
            py = y + 0.5 - 0.17 - i * 0.33
            mb.box(x - 0.55, py - 0.06, 0.0, x + 0.55, py + 0.06, 0.07, "wood_dark")
        for sg in (-1, 1):
            mb.box(x + sg * 0.36 - 0.035, y - 0.5, 0.07, x + sg * 0.36 + 0.035, y + 0.5, 0.13, "steel")
        return
    if k == "cactus":
        cactus(mb, x, y, rng.uniform(0.7, 1.1), rng)
    elif k in ("shrub",):
        shrub(mb, x, y, rng.uniform(0.9, 1.6), rng)
    elif k == "tumbleweed":
        mb.sphere(x, y, 0.16, 0.18, "dry", sub=2, jitter=0.3, rng=rng)
    elif k == "grass":
        for i in range(rng.randint(1, 3)):
            grass(mb, x + rng.uniform(-0.3, 0.3), y + rng.uniform(-0.3, 0.3), rng.uniform(0.8, 1.3), rng)
    elif k == "tree":
        tree(mb, x, y, rng.uniform(1.0, 1.5), rng, rng.choice(["tree", "tree", "dead"]))
    elif k == "joshua":
        tree(mb, x, y, rng.uniform(1.1, 1.5), rng, "joshua")
    elif k == "dead_tree":
        tree(mb, x, y, rng.uniform(1.0, 1.4), rng, "dead")
    elif k == "barrel":
        n = rng.randint(1, 3)
        for i in range(n):
            barrel(mb, x + rng.uniform(-0.3, 0.3), y + rng.uniform(-0.3, 0.3), rng)
    elif k == "crate_stack":
        crate(mb, x - 0.15, y, 0.42, rng, 0.0, rng.uniform(-0.2, 0.2))
        if rng.random() < 0.8:
            crate(mb, x + 0.3, y + 0.05, 0.36, rng, 0.0, rng.uniform(-0.3, 0.3))
        if rng.random() < 0.6:
            crate(mb, x - 0.12, y + 0.02, 0.34, rng, 0.42, rng.uniform(-0.3, 0.3))
        if rng.random() < 0.5:
            barrel(mb, x + 0.25, y - 0.4, rng)
    elif k == "hay_bale":
        for i in range(rng.randint(1, 3)):
            rr = rng.uniform(-0.3, 0.3)
            mb.box(x - 0.36, y - 0.2 + i * 0.42, 0, x + 0.36, y + 0.2 + i * 0.42, 0.34, "hay", rot=rr, piv=(x, y))
    elif k == "sacks":
        for i in range(rng.randint(2, 5)):
            mb.sphere(x + rng.uniform(-0.3, 0.3), y + rng.uniform(-0.25, 0.25), 0.12, 0.17, "sack", sub=2, sx=1.2, sz=0.7, jitter=0.12, rng=rng)
    elif k in ("hitching_post",):
        for sg in (-1, 1):
            mb.box(x + sg * 0.55 - 0.05, y - 0.05, 0, x + sg * 0.55 + 0.05, y + 0.05, 0.75, "wood_grey")
        mb.box(x - 0.65, y - 0.04, 0.62, x + 0.65, y + 0.04, 0.7, "wood_grey")
    elif k == "fence":
        fence_line(mb, [(x - 0.5 - 0.5, -y - 0.5), (x + 0.5 - 0.5, -y - 0.5)], rng)
    elif k == "lantern":
        mb.cyl(x, y, 0, 1.3, 0.035, "wood_dark", 6)
        mb.box(x - 0.08, y - 0.08, 1.3, x + 0.08, y + 0.08, 1.48, "window_lit")
    elif k == "wagon_wheel":
        wheel(mb, x, y, 0.36, 0.36, "Y", rot=rng.uniform(0, math.pi))
    elif k == "water_trough":
        mb.box(x - 0.55, y - 0.2, 0, x + 0.55, y + 0.2, 0.34, "wood", rot=rot, piv=(x, y))
        mb.box(x - 0.48, y - 0.13, 0.27, x + 0.48, y + 0.13, 0.3, "water", rot=rot, piv=(x, y))
    elif k in ("bench", "pew"):
        Lb = 0.9 if k == "bench" else 1.5
        mb.box(x - Lb / 2, y - 0.12, 0.25, x + Lb / 2, y + 0.12, 0.31, "wood")
        mb.box(x - Lb / 2, y + 0.1, 0.31, x + Lb / 2, y + 0.14, 0.62, "wood_dark")
    elif k in ("cart", "wagon", "covered_wagon", "stagecoach"):
        st = len(mb.V)
        wagon(mb, x, y, rot, rng, covered=(k != "cart"))
        scale_verts(mb, st, (x, y, 0.0), (1.4, 1.4, 1.4))
    elif k == "mine_cart":
        mine_cart(mb, x, y, rot, rng)
    elif k == "bed":
        mb.box(x - 0.35, y - 0.6, 0, x + 0.35, y + 0.6, 0.35, "wood_dark")
        mb.box(x - 0.3, y - 0.55, 0.35, x + 0.3, y + 0.5, 0.42, "canvas")
        mb.box(x - 0.3, y + 0.1, 0.42, x + 0.3, y + 0.5, 0.45, "cloth_red")
    elif k in ("table_chairs", "poker_table", "dining_table", "desk"):
        r = 0.42
        if k in ("dining_table", "desk"):
            mb.box(x - 0.6, y - 0.32, 0.42, x + 0.6, y + 0.32, 0.48, "wood")
        else:
            mb.cyl(x, y, 0.42, 0.48, r, "wood", 14)
        mb.cyl(x, y, 0, 0.42, 0.05, "wood_dark", 6)
        for i in range(4):
            a = i * math.pi / 2 + 0.4
            cx_, cy_ = x + math.cos(a) * (r + 0.18), y + math.sin(a) * (r + 0.18)
            mb.box(cx_ - 0.11, cy_ - 0.11, 0.24, cx_ + 0.11, cy_ + 0.11, 0.29, "wood_dark")
    elif k in ("saloon_bar", "counter"):
        Lb = max(sw, 2) * 0.95
        mb.box(x - Lb / 2, y - 0.22, 0, x + Lb / 2, y + 0.22, 0.65, "wood_dark")
        mb.box(x - Lb / 2 - 0.05, y - 0.27, 0.65, x + Lb / 2 + 0.05, y + 0.27, 0.7, "wood")
    elif k in ("shelf", "bookcase", "bottle_shelf", "gun_rack", "tool_rack", "dresser", "wardrobe"):
        mb.box(x - 0.42, y - 0.17, 0, x + 0.42, y + 0.17, 0.95, "wood_dark")
        for z in (0.3, 0.6):
            mb.box(x - 0.38, y - 0.18, z, x + 0.38, y - 0.16, z + 0.05, "wood")
    elif k in ("piano", "stove", "safe", "altar", "washstand", "nightstand", "candelabra", "bucket", "settee",
               "stage", "support_beam", "ore_pile"):
        m = {"stove": "iron", "safe": "iron", "ore_pile": "stone", "altar": "canvas"}.get(k, "wood_dark")
        s = 0.3 if k not in ("piano", "settee", "altar") else 0.5
        if k == "stage":
            mb.box(x - sw / 2, y - sh / 2, 0, x + sw / 2, y + sh / 2, 0.2, "deck")
        elif k == "stove":
            mb.box(x - 0.25, y - 0.2, 0, x + 0.25, y + 0.2, 0.5, "iron")
            mb.cyl(x, y + 0.1, 0.5, 1.6, 0.05, "iron", 8)
        else:
            mb.box(x - s, y - 0.2, 0, x + s, y + 0.2, 0.5, m)


def clutter_cluster(mb, X, Yb, rng, n=None, spread=(0.6, 0.45), wagons=True):
    """Grappe de fouillis (3–7 objets serrés) autour de (X, Yb). spread = demi-étendue (x, y) des
    positions ; wagons=False : pas de charrette (trop grande pour une case)."""
    n = n or rng.randint(3, 7)
    for i in range(n):
        x = X + rng.uniform(-spread[0], spread[0])
        y = Yb + rng.uniform(-spread[1], spread[1])
        r = rng.random()
        if r < 0.24:
            barrel(mb, x, y, rng, rng.uniform(0.85, 1.05))
        elif r < 0.5:
            crate(mb, x, y, rng.uniform(0.3, 0.46), rng, 0.0, rng.uniform(-0.4, 0.4))
            if rng.random() < 0.35:
                crate(mb, x, y, 0.3, rng, 0.42, rng.uniform(-0.4, 0.4))
        elif r < 0.62:
            for k in range(rng.randint(2, 4)):
                mb.box(x - 0.5, y - 0.05, 0.02 * k, x + 0.5, y + 0.05, 0.02 * k + 0.035, "wood_grey", rot=rng.uniform(0, 3.14),
                       piv=(x + rng.uniform(-0.2, 0.2), y + rng.uniform(-0.2, 0.2)))
        elif r < 0.72:
            prop(mb, "sacks", x, y, 1, 1, rng)
        elif r < 0.8:
            mb.box(x - 0.36, y - 0.2, 0, x + 0.36, y + 0.2, 0.32, "hay", rot=rng.uniform(-0.5, 0.5), piv=(x, y))
        elif r < 0.86:
            mb.cyl(x, y, 0.0, 0.06, 0.36, "wood_dark", 14)
        elif r < 0.9:
            mb.box(x - 0.15, y - 0.15, 0, x + 0.15, y + 0.15, 0.08, "rust_iron", rot=rng.uniform(0, 3))
        elif r < 0.915 and n >= 4 and wagons:
            st = len(mb.V)
            wagon(mb, x, y, rng.uniform(0, math.pi), rng, covered=False)
            scale_verts(mb, st, (x, y, 0.0), (1.3, 1.3, 1.3))
        elif r < 0.95:
            # établi
            mb.box(x - 0.36, y - 0.22, 0.5, x + 0.36, y + 0.22, 0.56, "wood")
            for (a_, b2) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
                mb.box(x + a_ * 0.3 - 0.03, y + b2 * 0.16 - 0.03, 0, x + a_ * 0.3 + 0.03, y + b2 * 0.16 + 0.03, 0.5, "wood_dark")
        else:
            shrub(mb, x, y, 0.9, rng)


def build_clutter():
    """Grappes de fouillis le long des bâtiments et dans les cours (caisses, tonneaux, planches,
    sacs, foin, roues, bric-à-brac) comme sur la maquette.
    Cohérence rendu ↔ collisions : chaque grappe tient dans UNE case de rue (le masque d'emprise la
    rend bloquante en jeu, cf. compose.py), jamais sur un chemin, un porche, une voie, les abords
    d'une porte / d'un conteneur, et seulement si bloquer cette case garde le sable
    libre d'un seul tenant autour (même test d'anneau que le générateur). Pas de charrette."""
    mb = MB()
    rng = random.Random(SEED * 31 + 7)
    blocked = set()
    for yy in range(-1, H + 1):
        for xx in range(-1, W + 1):
            if tile(xx, yy) not in (1, 2, 4, 5, 6):
                blocked.add((xx, yy))
    for key in ("prop_spawns", "container_spawns", "hiding_spot_spawns"):
        for sp in LAYOUT.get(key, []):
            x0_, y0_, w_, h_ = _rect_of_spawn(sp)
            for yy in range(y0_, y0_ + h_):
                for xx in range(x0_, x0_ + w_):
                    blocked.add((xx, yy))
    porch_rows = set()
    for b in LAYOUT["buildings"]:
        x, y, w, h = b["rect"]
        for xx in range(x - 1, x + w + 1):
            porch_rows.add((xx, y + h))
    ring8 = ((-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0))

    def ok(c):
        if tile(*c) != 1 or c in blocked or c in occupied or c in rail_set or c in game_cells or c in path_set \
                or c in porch_rows:
            return False
        free = [(c[0] + dx, c[1] + dy) not in blocked for dx, dy in ring8]
        if not any(free):
            return False
        return sum(1 for k in range(8) if free[k] and not free[k - 1]) <= 1

    placed = []
    for b in LAYOUT["buildings"]:
        x, y, w, h = b["rect"]
        cand = []
        for xx in range(x, x + w):
            cand += [(xx, y - 1), (xx, y + h + 1)]
        for yy in range(y, y + h):
            cand += [(x - 1, yy), (x + w, yy)]
        rng.shuffle(cand)
        used = 0
        for c in cand:
            if used >= max(3, int((w + h) * 0.6)):
                break
            if not ok(c) or any(abs(c[0] - u[0]) + abs(c[1] - u[1]) < 2 for u in placed):
                continue
            blocked.add(c)
            placed.append(c)
            used += 1
            clutter_cluster(mb, c[0] + 0.5, Y(c[1]) - 0.5, rng, rng.randint(2, 4), spread=(0.16, 0.14), wagons=False)
    # grappes libres dans les cours (cases non-chemin proches des bâtiments)
    for (cx_, cy_), b in list(bld_cells.items())[::6]:
        for _ in range(2):
            c = (cx_ + rng.randint(-4, 4), cy_ + rng.randint(-4, 4))
            if not ok(c) or any(abs(c[0] - u[0]) + abs(c[1] - u[1]) < 2 for u in placed):
                continue
            blocked.add(c)
            placed.append(c)
            clutter_cluster(mb, c[0] + 0.5, Y(c[1]) - 0.5, rng, rng.randint(2, 3), spread=(0.16, 0.14), wagons=False)
    mb.to_object("clutter", "world")
    global CLUTTER_CELLS
    CLUTTER_CELLS = sorted(placed)


CLUTTER_CELLS = []


# ======================================================================= repères (éolienne, château d'eau, puits)
VEG_PROPS = ("shrub", "tumbleweed", "grass", "tree", "joshua", "dead_tree")


def windmill(mb, cx, cy, s=1.0, trough=True):
    Ht = 4.6 * s
    b0, b1 = 0.75 * s, 0.18 * s
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for (a, b_) in corners:
        mb.seg((cx + a * b0, cy + b_ * b0, 0), (cx + a * b1, cy + b_ * b1, Ht), 0.06 * s, "wood_dark", 5)
    nb = 5
    for i in range(nb):
        z0, z1 = Ht * i / nb, Ht * (i + 1) / nb
        r0 = b0 + (b1 - b0) * i / nb
        r1 = b0 + (b1 - b0) * (i + 1) / nb
        for k in range(4):
            (a0, c0), (a1, c1) = corners[k], corners[(k + 1) % 4]
            mb.seg((cx + a0 * r0, cy + c0 * r0, z0), (cx + a1 * r1, cy + c1 * r1, z1), 0.03 * s, "wood_dark", 4)
            mb.seg((cx + a1 * r0, cy + c1 * r0, z0), (cx + a0 * r1, cy + c0 * r1, z1), 0.03 * s, "wood_dark", 4)
            mb.seg((cx + a0 * r1, cy + c0 * r1, z1), (cx + a1 * r1, cy + c1 * r1, z1), 0.035 * s, "wood_dark", 4)
    mb.box(cx - 0.3 * s, cy - 0.3 * s, Ht, cx + 0.3 * s, cy + 0.3 * s, Ht + 0.06, "wood_grey")
    # rotor : plan face au sud, incliné vers la caméra
    hub = Vector((cx, cy - 0.35 * s, Ht + 0.35 * s))
    tilt = math.radians(62)
    nrm = Vector((0, -math.cos(tilt), math.sin(tilt)))
    u = Vector((1, 0, 0))
    v = nrm.cross(u).normalized() * -1
    mb.seg(hub, hub - nrm * 0.25, 0.08 * s, "iron", 8)
    R = 1.35 * s
    for i in range(18):
        a = i / 18 * math.tau
        d = u * math.cos(a) + v * math.sin(a)
        dp = u * math.cos(a + 0.5 * math.pi) + v * math.sin(a + 0.5 * math.pi)
        p0 = hub + d * 0.3 * s
        p1 = hub + d * R
        q0 = p0 + dp * 0.12 * s + nrm * 0.02
        q1 = p1 + dp * 0.34 * s + nrm * 0.08
        mb.poly([tuple(p0), tuple(p1), tuple(q1), tuple(q0)], "tin_dark")
        mb.poly([tuple(q0), tuple(q1), tuple(p1), tuple(p0)], "tin_dark")
        if i % 3 == 0:
            mb.seg(hub, p1, 0.015 * s, "iron", 3)
    mb.seg(hub + Vector((0, 0, 0)), hub + Vector((0, 1.8 * s, 0.05)), 0.03 * s, "iron", 4)
    tv = hub + Vector((0, 1.8 * s, 0.05))
    mb.poly([tuple(tv + Vector((0, -0.6 * s, -0.35 * s))), tuple(tv + Vector((0, 0.15 * s, -0.4 * s))),
             tuple(tv + Vector((0, 0.15 * s, 0.4 * s))), tuple(tv + Vector((0, -0.6 * s, 0.35 * s)))], "tin_red")
    mb.poly([tuple(tv + Vector((0, -0.6 * s, 0.35 * s))), tuple(tv + Vector((0, 0.15 * s, 0.4 * s))),
             tuple(tv + Vector((0, 0.15 * s, -0.4 * s))), tuple(tv + Vector((0, -0.6 * s, -0.35 * s)))], "tin_red")
    if not trough:
        return
    # bac + tuyau au pied
    mb.cyl(cx + 0.9 * s, cy - 0.6 * s, 0, 0.45, 0.55 * s, "wood", 16)
    mb.cyl(cx + 0.9 * s, cy - 0.6 * s, 0.38, 0.42, 0.5 * s, "water", 16)
    mb.seg((cx, cy, 0.2), (cx + 0.9 * s, cy - 0.6 * s, 0.4), 0.03, "iron", 4)


def water_tower(mb, cx, cy, s=1.0):
    Hl = 3.2 * s
    b0, b1 = 0.95 * s, 0.75 * s
    legs = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for (a, b_) in legs:
        mb.seg((cx + a * b0, cy + b_ * b0, 0), (cx + a * b1, cy + b_ * b1, Hl), 0.09 * s, "wood_dark", 6)
    for lvl in range(3):
        z0, z1 = Hl * lvl / 3, Hl * (lvl + 1) / 3
        r0 = b0 + (b1 - b0) * lvl / 3
        r1 = b0 + (b1 - b0) * (lvl + 1) / 3
        for k in range(4):
            (a0, c0), (a1, c1) = legs[k], legs[(k + 1) % 4]
            mb.seg((cx + a0 * r0, cy + c0 * r0, z0 + 0.1), (cx + a1 * r1, cy + c1 * r1, z1), 0.035 * s, "wood_dark", 4)
            mb.seg((cx + a1 * r0, cy + c1 * r0, z0 + 0.1), (cx + a0 * r1, cy + c0 * r1, z1), 0.035 * s, "wood_dark", 4)
            mb.seg((cx + a0 * r1, cy + c0 * r1, z1), (cx + a1 * r1, cy + c1 * r1, z1), 0.04 * s, "wood_dark", 4)
    mb.box(cx - 1.05 * s, cy - 1.05 * s, Hl, cx + 1.05 * s, cy + 1.05 * s, Hl + 0.1, "deck")
    for k in range(4):
        (a0, c0), (a1, c1) = legs[k], legs[(k + 1) % 4]
        mb.seg((cx + a0 * 1.02 * s, cy + c0 * 1.02 * s, Hl + 0.45), (cx + a1 * 1.02 * s, cy + c1 * 1.02 * s, Hl + 0.45), 0.025, "wood_dark", 4)
    R = 0.88 * s
    th = 1.6 * s
    mb.cyl(cx, cy, Hl + 0.1, Hl + 0.1 + th, R, "car_brown", 24)
    for z in (0.25, 0.75, 1.2):
        mb.cyl(cx, cy, Hl + 0.1 + z * s, Hl + 0.14 + z * s, R + 0.02, "iron", 24)
    mb.cyl(cx, cy, Hl + 0.1 + th, Hl + 0.1 + th + 0.55 * s, R + 0.12, "tin_dark", 24, r2=0.08)
    mb.seg((cx + R * 0.7, cy - R * 0.5, Hl + 0.4), (cx + R * 1.6, cy - R * 0.5, Hl - 0.6), 0.06, "iron", 6)


def well(mb, cx, cy, s=1.0):
    R = 0.85 * s
    mb.cyl(cx, cy, 0, 0.8, R, "stone_blocks", 24)
    mb.cyl(cx, cy, 0.8, 0.9, R + 0.06, "stone", 24)
    mb.cyl(cx, cy, 0.5, 0.86, R - 0.16, "doorway", 20)
    mb.cyl(cx, cy, 0.52, 0.55, R - 0.2, "water", 20)
    for k in range(14):
        a = k / 14 * math.tau
        mb.box(cx + math.cos(a) * R * 1.25 - 0.18, cy + math.sin(a) * R * 1.25 - 0.13, 0, cx + math.cos(a) * R * 1.25 + 0.18, cy + math.sin(a) * R * 1.25 + 0.13, 0.05, "stone", rot=a)
    mb.seg((cx + R * 0.2, cy + R * 0.2, 0.6), (cx + R * 0.35, cy + R * 0.4, 2.0), 0.05, "wood_dark", 6)
    mb.seg((cx + R * 0.35, cy + R * 0.4, 2.0), (cx - R * 0.1, cy, 1.6), 0.03, "wood_dark", 5)
    mb.cyl(cx + R * 0.9, cy - R * 0.9, 0, 0.3, 0.15, "wood", 10)


# ======================================================================= voie ferrée et train
TRAIN_S = 1.75


def scale_verts(mb, start, c, k):
    cx, cy, cz = c
    for i in range(start, len(mb.V)):
        x, y, z = mb.V[i]
        mb.V[i] = (x if cx is None else cx + (x - cx) * k[0], cy + (y - cy) * k[1], cz + (z - cz) * k[2])


def rail_runs(cells):
    """Regroupe les cases de voie en segments horizontaux / verticaux (≥ 2 cases)."""
    S = set(tuple(c) for c in cells)
    runs = []
    seen_h = set()
    for (x, y) in sorted(S):
        if (x, y) in seen_h or (x - 1, y) in S:
            continue
        x2 = x
        while (x2 + 1, y) in S:
            x2 += 1
        if x2 - x >= 2:
            runs.append(("h", x, x2 + 1, y))
            for k in range(x, x2 + 1):
                seen_h.add((k, y))
    for (x, y) in sorted(S, key=lambda c: (c[0], c[1])):
        if (x, y) in seen_h or (x, y - 1) in S and (x, y - 1) not in seen_h:
            continue
        y2 = y
        while (x, y2 + 1) in S and (x, y2 + 1) not in seen_h:
            y2 += 1
        if y2 - y >= 2:
            runs.append(("v", y, y2 + 1, x))
    return runs


def build_rails():
    mb = MB()
    lines = LAYOUT.get("rail_lines") or []
    runs = []
    if lines:
        # Polylignes du générateur : axe = points + width/2 ; « spur » = voie étroite (mine).
        for ln in lines:
            pts = ln["points"]
            wdt = int(ln.get("width", 2))
            for a_, b_ in zip(pts, pts[1:]):
                if a_[1] == b_[1]:
                    x0_, x1_ = min(a_[0], b_[0]), max(a_[0], b_[0]) + 1
                    runs.append(("h", x0_, x1_, a_[1] + wdt / 2.0 - 0.5, ln.get("kind", "main")))
                else:
                    y0_, y1_ = min(a_[1], b_[1]), max(a_[1], b_[1]) + 1
                    runs.append(("v", y0_, y1_, a_[0] + wdt / 2.0 - 0.5, ln.get("kind", "main")))
    else:
        runs = [r + ("main",) for r in rail_runs(LAYOUT["rails"])]
    for r in runs:
        if r[4] == "spur":
            if r[0] == "v":
                for yy in range(r[1], r[2]):
                    prop(mb, "mine_rail", r[3] + 0.5, Y(yy) - 0.5, 1, 1, RNG)
            else:
                for xx in range(r[1], r[2]):
                    st = len(mb.V)
                    prop(mb, "mine_rail", xx + 0.5, Y(r[3]) - 0.5, 1, 1, RNG)
                    for i in range(st, len(mb.V)):
                        x_, y_, z_ = mb.V[i]
                        cx_, cy_ = xx + 0.5, Y(r[3]) - 0.5
                        mb.V[i] = (cx_ - (y_ - cy_), cy_ + (x_ - cx_), z_)
            continue
        r = r[:4]
        if r[0] == "h":
            _, a, b_, row = r
            yc = Y(row) - 0.5
            mb.box(a, yc - 2.15, -0.05, b_, yc + 2.15, 0.06, "gravel")
            n = int((b_ - a) / 0.42)
            for i in range(n):
                px = a + 0.21 + i * 0.42
                mb.box(px - 0.13, yc - 1.75, 0.06, px + 0.13, yc + 1.75, 0.15, "wood_dark", rot=RNG.uniform(-0.03, 0.03))
            for sg in (-1, 1):
                mb.box(a, yc + sg * 1.26 - 0.07, 0.15, b_, yc + sg * 1.26 + 0.07, 0.29, "steel")
        else:
            _, a, b_, col = r
            xc = col + 0.5
            mb.box(xc - 1.2, Y(b_), -0.05, xc + 1.2, Y(a), 0.06, "gravel")
            n = int((b_ - a) / 0.42)
            for i in range(n):
                py = Y(a) - 0.21 - i * 0.42
                mb.box(xc - 0.95, py - 0.1, 0.06, xc + 0.95, py + 0.1, 0.14, "wood_dark")
            for sg in (-1, 1):
                mb.box(xc + sg * 0.55 - 0.05, Y(b_), 0.14, xc + sg * 0.55 + 0.05, Y(a), 0.24, "steel")
    mb.to_object("rails", "world")


def bogie(mb, x, yc):
    for dx in (-0.35, 0.35):
        for sg in (-1, 1):
            wheel(mb, x + dx, yc + sg * 0.72, 0.3, 0.3, "Y", "iron", rot=0.0)
    mb.box(x - 0.6, yc - 0.8, 0.28, x + 0.6, yc + 0.8, 0.42, "iron")


def train_car(mb, kind, rect, rng):
    x, y, w, h = rect
    yc = Y(y) - h / 2
    xa, xb = x + 0.15, x + w - 0.15
    Wd = 1.6
    mb.box(xa, yc - Wd / 2, 0.55, xb, yc + Wd / 2, 0.7, "iron")
    for bx in (xa + 0.8, xb - 0.8):
        bogie(mb, bx, yc)
    mb.box(xa - 0.12, yc - 0.08, 0.5, xa, yc + 0.08, 0.62, "iron")
    if kind.startswith("loco"):
        rev = kind.endswith("_rev")
        cab0, cab1 = (xa, xa + 1.4) if rev else (xb - 1.4, xb)
        bo0, bo1 = (xa + 1.4, xb) if rev else (xa, xb - 1.4)
        front = bo1 if rev else bo0
        Lb = bo1 - bo0
        mb.cyl(bo0 + Lb / 2, yc, 1.25, Lb, 0.6, "boiler", 20, axis="X")
        mb.cyl((bo0 + bo1) / 2 - Lb / 2, yc, 1.25, 0.0, 0.0, "boiler", 3) if False else None
        # anneaux, dôme, cheminée
        for k in range(4):
            px = bo0 + Lb * (0.15 + 0.23 * k)
            mb.cyl(px, yc, 1.25, 0.06, 0.62, "brass" if k == 1 else "iron", 20, axis="X")
        sx = front - 0.5 if rev else front + 0.5
        mb.cyl(sx, yc, 1.7, 2.6, 0.2, "boiler", 14, r2=0.34)
        mb.cyl((bo0 + bo1) / 2, yc, 1.75, 2.05, 0.24, "brass", 14)
        mb.cyl(front + (-0.05 if rev else 0.05), yc, 1.25, 0.1, 0.62, "iron", 20, axis="X")
        mb.cyl(front + (0.0 if rev else -0.0), yc, 1.3, 1.45, 0.14, "window_lit", 10)
        # chasse-pierres
        cx_ = front + (0.35 if rev else -0.35)
        mb.box(min(cx_, front), yc - 0.6, 0.15, max(cx_, front), yc + 0.6, 0.55, "red_paint")
        # roues motrices rouges
        for k in range(3):
            px = bo0 + 0.6 + k * (Lb - 1.0) / 2
            for sg in (-1, 1):
                wheel(mb, px, yc + sg * 0.76, 0.48, 0.48, "Y", "red_paint")
        # cabine
        mb.box(cab0, yc - 0.82, 0.7, cab1, yc + 0.82, 2.3, "boiler")
        mb.box(cab0 - 0.1, yc - 0.95, 2.3, cab1 + 0.1, yc + 0.95, 2.42, "tin_dark")
        for sg in (-1, 1):
            mb.box(cab0 + 0.25, yc + sg * 0.83 - 0.02, 1.55, cab1 - 0.25, yc + sg * 0.83 + 0.02, 2.05, "glass")
    elif kind == "tender":
        mb.box(xa, yc - 0.8, 0.7, xb, yc + 0.8, 1.75, "boiler")
        mb.box(xa + 0.15, yc - 0.65, 1.7, xb - 0.15, yc + 0.65, 1.8, "iron")
        mb.box(xa, yc - 0.85, 1.65, xb, yc + 0.85, 1.75, "iron")
    elif kind == "tankcar":
        mb.cyl((xa + xb) / 2, yc, 1.4, xb - xa - 0.3, 0.75, "boiler", 22, axis="X")
        for px in (xa + 0.3, (xa + xb) / 2, xb - 0.3):
            mb.cyl(px - 0.04, yc, 1.4, 0.08, 0.77, "iron", 22, axis="X")
        mb.cyl((xa + xb) / 2, yc, 2.1, 2.35, 0.25, "iron", 12)
    elif kind == "flatcar":
        mb.box(xa, yc - 0.85, 0.7, xb, yc + 0.85, 0.82, "deck")
        for i in range(rng.randint(2, 3)):
            crate(mb, xa + 0.6 + i * 1.0, yc + rng.uniform(-0.3, 0.3), 0.6, rng, 0.82)
    else:
        mat = {"boxcar": "car_red", "boxcar_b": "car_brown", "boxcar_dark": "tin_dark", "caboose": "car_red"}.get(kind, "car_red")
        top = 2.35
        mb.box(xa, yc - 0.85, 0.7, xb, yc + 0.85, top, mat)
        # toit arrondi + passerelle
        n = 8
        rings = []
        for px in (xa - 0.08, xb + 0.08):
            ring = []
            for j in range(n + 1):
                a = math.pi * j / n
                ring.append(mb.bm.verts.new((px, yc + math.cos(a) * 0.95, top + math.sin(a) * 0.22)))
            rings.append(ring)
        mi = mb.mi("tin_rust" if kind != "boxcar_dark" else "tin_dark")
        for j in range(n):
            f = mb.bm.faces.new((rings[0][j], rings[0][j + 1], rings[1][j + 1], rings[1][j]))
            f.material_index = mi
        mb.box(xa, yc - 0.12, top + 0.2, xb, yc + 0.12, top + 0.25, "wood_grey")
        # portes coulissantes + cadres
        mxc = (xa + xb) / 2
        for sg in (-1, 1):
            mb.box(mxc - 0.55, yc + sg * 0.85 - 0.03, 0.75, mxc + 0.55, yc + sg * 0.85 + 0.03, top - 0.15, "wood_dark" if mat != "tin_dark" else "iron")
            for px in (xa + 0.05, xb - 0.05):
                mb.box(px - 0.04, yc + sg * 0.86 - 0.03, 0.7, px + 0.04, yc + sg * 0.86 + 0.03, top, "iron")
        if kind == "caboose":
            mb.box(mxc - 0.5, yc - 0.45, top + 0.15, mxc + 0.5, yc + 0.45, top + 0.7, mat)
            mb.box(mxc - 0.55, yc - 0.5, top + 0.7, mxc + 0.55, yc + 0.5, top + 0.76, "tin_grey")


# ======================================================================= sol + masques
def build_ground_mask(path, ext, ppx=16):
    from PIL import Image, ImageDraw, ImageFilter
    x0, x1, y0, y1 = ext
    Wp, Hp = int((x1 - x0) * ppx), int((y1 - y0) * ppx)
    def P(cx, cy):
        return ((cx - x0) * ppx, (cy - y0) * ppx)
    R = Image.new("L", (Wp, Hp), 0)
    dr = ImageDraw.Draw(R)
    for (cx, cy) in path_set:
        a = P(cx - 0.15, cy - 0.15)
        b_ = P(cx + 1.15, cy + 1.15)
        dr.rectangle([a, b_], fill=255)
    R = R.filter(ImageFilter.GaussianBlur(ppx * 0.8))
    G = Image.new("L", (Wp, Hp), 0)
    dg = ImageDraw.Draw(G)
    for (cx, cy) in rock_cells:
        dg.ellipse([P(cx - 1.2, cy - 1.2), P(cx + 2.2, cy + 2.2)], fill=255)
    G = G.filter(ImageFilter.GaussianBlur(ppx * 1.3))
    Bm = Image.new("L", (Wp, Hp), 0)
    db = ImageDraw.Draw(Bm)
    for b in LAYOUT["buildings"]:
        x, y, w, h = b["rect"]
        db.rectangle([P(x - 2.0, y - 1.5), P(x + w + 2.0, y + h + 2.5)], fill=210)
    for p in LAYOUT["props"]:
        if p["kind"] in ("barrel", "crate_stack", "hay_bale", "sacks", "water_trough", "hitching_post", "cart", "wagon", "covered_wagon"):
            cx, cy = p["cell"]
            db.ellipse([P(cx - 0.9, cy - 0.9), P(cx + 1.9, cy + 1.9)], fill=200)
    for lm in LAYOUT["landmarks"]:
        x, y, w, h = lm["rect"]
        db.ellipse([P(x - 1.5, y - 1.5), P(x + w + 1.5, y + h + 1.5)], fill=200)
    Bm = Bm.filter(ImageFilter.GaussianBlur(ppx * 1.0))
    # ornières : deux traces parallèles le long des chemins (lignes sinueuses)
    Am = Image.new("L", (Wp, Hp), 0)
    da = ImageDraw.Draw(Am)
    rng = random.Random(SEED + 5)
    rows = {}
    cols = {}
    for (cx, cy) in path_set:
        rows.setdefault(cy, []).append(cx)
        cols.setdefault(cx, []).append(cy)
    for cy, xs in rows.items():
        if len(xs) >= 5 and rng.random() < 0.6 and (cy + 1) in rows and len(rows[cy + 1]) >= 5:
            xs = sorted(xs)
            for off in (0.55, 1.45):
                pts = [P(xx, cy + off + 0.12 * math.sin(xx * 0.7 + cy)) for xx in range(xs[0], xs[-1] + 1)]
                da.line(pts, fill=255, width=max(1, int(ppx * 0.12)))
    for cx, ys in cols.items():
        if len(ys) >= 5 and rng.random() < 0.6 and (cx + 1) in cols and len(cols[cx + 1]) >= 5:
            ys = sorted(ys)
            for off in (0.55, 1.45):
                pts = [P(cx + off + 0.12 * math.sin(yy * 0.7 + cx), yy) for yy in range(ys[0], ys[-1] + 1)]
                da.line(pts, fill=255, width=max(1, int(ppx * 0.12)))
    Am = Am.filter(ImageFilter.GaussianBlur(ppx * 0.08))
    img = Image.merge("RGBA", (R, G, Bm, Am))
    img = img.transpose(Image.FLIP_TOP_BOTTOM)   # v = 0 en bas (y Blender min)
    img.save(path)


def build_ground():
    M = MARGIN + 2
    ext = (-M, W + M, -M, H + M)
    mask = os.path.join(OUT, "_ground_mask.png")
    build_ground_mask(mask, ext)
    mat_ground(mask, ext)
    mb = MB()
    f = mb.poly([(ext[0], Y(ext[3]), 0), (ext[1], Y(ext[3]), 0), (ext[1], Y(ext[2]), 0), (ext[0], Y(ext[2]), 0)], "ground",
                [(0, 0), (1, 0), (1, 1), (0, 1)])
    mb.to_object("ground", "world")
    # éparpillement : cailloux, herbes sèches, buissons ; densité plus forte hors chemins
    sc = MB()
    rng = random.Random(SEED + 11)
    n = int((W + 2 * MARGIN) * (H + 2 * MARGIN) * 0.9)
    for _ in range(n):
        x = rng.uniform(-MARGIN, W + MARGIN)
        y = rng.uniform(-MARGIN, H + MARGIN)
        c = (int(math.floor(x)), int(math.floor(y)))
        if c in occupied or tile(*c) in (2, 4, 5, 6) or c in rail_set:
            continue
        onpath = c in path_set
        r = rng.random()
        if r < 0.45:
            if rng.random() < 0.18:
                sc.sphere(x, Y(y), 0.0, rng.uniform(0.06, 0.14), rng.choice(["pebble", "rock", "stone"]), sub=1, sz=0.5, jitter=0.35, rng=rng)
        elif onpath:
            continue
        elif r < 0.64:
            if rng.random() < 0.4:
                grass(sc, x, Y(y), rng.uniform(0.6, 1.1), rng)
        elif r < 0.9:
            shrub(sc, x, Y(y), rng.uniform(0.6, 1.2), rng, rng.choice(["foliage", "foliage2", "foliage2", "sage", "dry"]))
        elif r < 0.93:
            cactus(sc, x, Y(y), rng.uniform(0.5, 0.8), rng)
        elif r < 0.95:
            for i in range(rng.randint(1, 3)):
                sc.box(x - 0.35, Y(y) - 0.04, 0, x + 0.35, Y(y) + 0.04, 0.03, "wood_grey", rot=rng.uniform(0, 3.14),
                       piv=(x + rng.uniform(-0.2, 0.2), Y(y)))
    # marges hors carte : rochers + végétation (décor pur)
    rk = MB()
    for yy in range(-MARGIN - 2, H + MARGIN + 2, 3):
        for xx in range(-MARGIN - 2, W + MARGIN + 2, 3):
            if -1 <= xx <= W and -1 <= yy <= H:
                continue
            hv = rng.random()
            if hv < 0.3:
                cells = [[xx + i, yy + j] for i in range(rng.randint(2, 4)) for j in range(rng.randint(2, 3))]
                rock_formation(rk, cells, rng.uniform(0.8, 2.0), rng)
            elif hv < 0.55:
                shrub(sc, xx + rng.uniform(0, 3), Y(yy) - rng.uniform(0, 3), rng.uniform(0.8, 1.3), rng)
    sc.to_object("scatter", "world")
    rk.to_object("rocks_margin", "world")


# ======================================================================= construction
def build_world():
    for b in LAYOUT["buildings"]:
        build_building(b)
        build_interior_furniture(b, random.Random(b["id"] + SEED))
    # rochers + végétation associée
    rk = MB()
    veg = MB()
    for i, rf in enumerate(LAYOUT["rock_formations"]):
        rng = random.Random(SEED * 13 + i)
        if rf.get("kind") == "scree":
            scree(rk, rf["cells"], float(rf.get("height", 1.0)), rng)
            continue
        cx, cy, tops, prof, rmax = rock_formation(rk, rf["cells"], float(rf.get("height", 1.6)), rng)
        tx, ty, tz, tk = tops[-1]
        if rmax > 1.6 and rng.random() < 0.6:
            shrub(veg, tx + rng.uniform(-0.3, 0.3), ty + rng.uniform(-0.3, 0.3), 2.2, rng, "foliage")
        # buissons/arbres au pied
        for k in range(rng.randint(1, 4)):
            a = rng.uniform(0, math.tau)
            j = int(a / math.tau * len(prof)) % len(prof)
            rr = prof[j] * 1.15 + 0.3
            px, py = cx + math.cos(a) * rr, cy + math.sin(a) * rr
            if rng.random() < 0.3:
                tree(veg, px, py, rng.uniform(1.0, 1.4), rng, rng.choice(["tree", "joshua", "dead"]))
            else:
                shrub(veg, px, py, rng.uniform(0.9, 1.5), rng)
    rk.to_object("rocks", "world")
    # buissons au sommet : remontés à la hauteur du sommet
    veg_top = MB()
    for i, rf in enumerate(LAYOUT["rock_formations"]):
        rng = random.Random(SEED * 17 + i)
        if float(rf.get("height", 1.6)) >= 2.0 and rng.random() < 0.8:
            xs = [c[0] + 0.5 for c in rf["cells"]]
            ys = [c[1] + 0.5 for c in rf["cells"]]
            cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
            sh = MB()
            for k_ in range(rng.randint(5, 8)):
                a_ = rng.uniform(0, math.tau)
                d_ = rng.uniform(0, 0.45)
                sh.sphere(math.cos(a_) * d_ * 1.4, math.sin(a_) * d_ * 1.4, rng.uniform(0.15, 0.45), rng.uniform(0.38, 0.55), "foliage", sub=2,
                          sz=0.8, nscale=2.5, rng=rng)
            tree(sh, 0, 0, 1.3, rng, "agave")
            sh.offset(cx, -cy, float(rf["height"]) * 1.02)
            o = sh.to_object("topbush_%d" % i, "world")
    # props : obstacles ramenés dans leur emprise (cases du spawn) ; végétation à part (traversable
    # en jeu, hors masque d'emprise)
    pm = MB()
    pv = MB()
    for p in LAYOUT["props"]:
        rng = random.Random(hash((p["cell"][0], p["cell"][1], p["kind"])) & 0xffffff)
        off = p.get("off", [0, 0])
        x = p["cell"][0] + 0.5 + off[0] / 64.0
        y = Y(p["cell"][1]) - 0.5 - off[1] / 64.0
        sz = p.get("size", [1, 1])
        if p["kind"] in VEG_PROPS:
            prop(pv, p["kind"], x, y, sz[0], sz[1], rng, float(p.get("rot", 0.0)))
            continue
        st = len(pm.V)
        prop(pm, p["kind"], x, y, sz[0], sz[1], rng, float(p.get("rot", 0.0)))
        cells_fit(pm, st, _rect_of_spawn(p))
    pm.to_object("props", "world")
    pv.to_object("veg_props", "world")
    # clôtures
    fm = MB()
    for i, fl in enumerate(LAYOUT["fences"]):
        fence_line(fm, [tuple(c) for c in fl], random.Random(SEED + 100 + i))
    fm.to_object("fences", "world")
    # repères
    lm = MB()
    for l in LAYOUT["landmarks"]:
        x, y, w, h = l["rect"]
        cx, cy = x + w / 2, Y(y) - h / 2
        k = l["kind"]
        st = len(lm.V)
        if k == "windmill":
            windmill(lm, cx, cy, 1.55, trough=False)
        elif k == "windmill_small":
            windmill(lm, cx, cy, 1.0, trough=False)
        elif k == "water_tower":
            water_tower(lm, cx, cy, max(w, h) / 2.2)
        elif k == "well":
            well(lm, cx, cy, 1.4)
        # éolienne / château d'eau : pieds en tubes (sommets seulement en bas et en haut) → zlo bas ;
        # puits : la couronne de pavés plats (z < 0,06) reste hors emprise.
        cells_fit(lm, st, l["rect"], zlo=0.12 if k == "well" else -1.0)
    lm.to_object("landmarks", "world")
    build_clutter()
    build_rails()
    tm = MB()
    for i, c in enumerate(LAYOUT["train"]):
        st = len(tm.V)
        train_car(tm, c["kind"], c["rect"], random.Random(i + SEED))
        x, y, w, h = c["rect"]
        yc = Y(y) - h / 2
        ks = min(TRAIN_S, h * 1.0 / 1.6)
        scale_verts(tm, st, (None, yc, 0.0), (1.0, ks, 1.15))
        cells_fit(tm, st, c["rect"], margin=0.02)
    tm.to_object("train", "world")
    build_ground()


# ======================================================================= lumière, caméra, rendu
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
    sc.cycles.glossy_bounces = 1
    sc.cycles.transmission_bounces = 0
    sc.cycles.transparent_max_bounces = 2
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
    bg.inputs[0].default_value = (0.28, 0.32, 0.58, 1)
    bg.inputs[1].default_value = SKY
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = SUN_E
    sun.color = (1.0, 0.66, 0.40)
    sun.angle = math.radians(2.5)
    so = bpy.data.objects.new("sun", sun)
    sc.collection.objects.link(so)
    # soleil au nord-est, assez bas : ombres longues vers le bas-gauche (sud-ouest), comme la maquette
    d = Vector((-0.80, -0.35, -0.62)).normalized()
    so.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.sensor_fit = "HORIZONTAL"
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    co.rotation_euler = Euler((TILT, 0, 0))
    cam.clip_start = 0.1
    cam.clip_end = 600
    return co


EXPOSURE = float(os.environ.get("FW_EXPOSURE", "0.55"))
SUN_E = float(os.environ.get("FW_SUN", "6.5"))
SKY = float(os.environ.get("FW_SKY", "1.0"))
SAT = float(os.environ.get("FW_SAT", "1.32"))
CON = float(os.environ.get("FW_CON", "1.08"))
LIFT = float(os.environ.get("FW_LIFT", "22"))


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


def set_mode(mode):
    """'full' : tout ; 'int' : toits/façades sud/auvents exclus, murets coupés visibles."""
    vl = scene.view_layers[0]
    for lc in vl.layer_collection.children:
        if lc.name == "roofs":
            lc.exclude = (mode == "int")
        elif lc.name == "cutaway":
            lc.exclude = (mode != "int")


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


# ======================================================================= masque d'emprise (zénithal)
# Classes d'objets du masque : R = obstacle adossé au layout (murs, rochers, train, clôtures,
# repères, props du layout), G = fouillis décoratif (clutter, mobilier), B = végétation / divers.
MASK_SOLID = ("walls_", "front_", "ruin_", "rocks", "train", "fences", "landmarks", "props")
MASK_DECOR = ("clutter", "furn_")
MASK_SKIP = ("ground", "scatter", "rails", "floor_", "porch_", "cut_", "roof_", "awning_", "rocks_margin", "topbush_",
             "veg_props", "_")


def mask_class(name):
    if name.startswith(MASK_SKIP):
        return None
    if name.startswith(MASK_SOLID):
        return (1.0, 0.0, 0.0)
    if name.startswith(MASK_DECOR):
        return (0.0, 1.0, 0.0)
    return (0.0, 0.0, 1.0)


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


# ======================================================================= occultation (ids par pixel)
# Objets qui n'occultent jamais un personnage (sol, rails, porches / auvents : on passe dessous ;
# floor/cut : invisibles depuis la caméra « full »).
OCC_SKIP = ("ground", "rails", "porch_", "awning_", "floor_", "cut_", "_")


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


if __name__ == "__main__":
    t0 = time.time()
    build_materials()
    build_world()
    coll("roofs")
    cam = setup_render()
    t_build = time.time() - t0
    print("BUILD", round(t_build, 1), "s", flush=True)
    import hashlib
    info = {"tiles_md5": hashlib.md5("".join(TILES).encode()).hexdigest(), "seed": SEED, "ppc": PPC, "tilt_deg": TILT_DEG, "projection": "ground_square", "margin": MARGIN,
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
        # Intérieurs : par bâtiment, SEULS son toit / sa façade sud / son auvent sont masqués et
        # son muret coupé affiché (les voisins restent intacts). Même caméra que « full », rendu
        # par bordure (rectangle couvrant l'emprise + la hauteur projetée du toit).
        pw, ph = frame(cam, -MARGIN, W + MARGIN, -MARGIN, H + MARGIN)
        scene.render.use_border = True
        scene.render.use_crop_to_border = True
        tb = 0.0
        tW, tH = W + 2 * MARGIN, H + 2 * MARGIN
        up = int(math.ceil(4.6 * math.tan(TILT)))
        for b in LAYOUT["buildings"]:
            if b.get("arch") == "ruin":
                continue
            bid = b["id"]
            objs_off = [o for o in bpy.data.objects if o.name in ("roof_%d" % bid, "front_%d" % bid, "awning_%d" % bid)]
            objs_on = [o for o in bpy.data.objects if o.name == "cut_%d" % bid]
            for o in objs_off:
                o.hide_render = True
            for o in objs_on:
                o.hide_render = False
            x, y, w, h = b["rect"]
            reg = [x - 1, x + w + 1, y - up, y + h + 2]
            u0 = (reg[0] + MARGIN) / tW
            u1 = (reg[1] + MARGIN) / tW
            v0 = 1.0 - (reg[3] + MARGIN) / tH
            v1 = 1.0 - (reg[2] + MARGIN) / tH
            scene.render.border_min_x, scene.render.border_max_x = max(u0, 0), min(u1, 1)
            scene.render.border_min_y, scene.render.border_max_y = max(v0, 0), min(v1, 1)
            tb += render(os.path.join(OUT, "b%d_in.png" % bid))
            for o in objs_off:
                o.hide_render = False
            for o in objs_on:
                o.hide_render = True
            info["buildings"].append({"id": bid, "rect": b["rect"],
                                      "px": [int(round(max(u0, 0) * pw)), int(round((1 - min(v1, 1)) * ph)),
                                             int(round(min(u1, 1) * pw)), int(round((1 - max(v0, 0)) * ph))]})
            print("  int", bid, round(tb, 1), flush=True)
        scene.render.use_border = False
        info["renders"]["interiors_s"] = round(tb, 1)
        print("INT", round(tb, 1), "s", flush=True)
    info["clutter_cells"] = [list(c) for c in CLUTTER_CELLS]
    json.dump(info, open(os.path.join(OUT, "render.json"), "w"), indent=1)
    json.dump(LAYOUT, open(os.path.join(OUT, "layout.json"), "w"))   # pour compose.py (collisions)
    print("DONE total", round(time.time() - t0, 1), "s", flush=True)
