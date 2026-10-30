"""Icônes de monnaie et illustrations des packs de gemmes en 3D « toon peint » (même pipeline,
mêmes matériaux toon, même contour Freestyle et même lumière chaude que build_props.py /
build_containers.py), pour les compteurs, la boutique et les écrans de fin.

Usage (depuis la racine du projet, avec le Python du système : PIL requis) :
    python art/blender/build_currency.py                    # tout
    python art/blender/build_currency.py --only gem,coin    # quelques images
    BLENDER=".../blender.exe" python art/blender/build_currency.py   # autre Blender que celui par défaut

Le script se relance lui-même dans Blender (--background) pour les rendus 3D (rdm_common : toon
en émission pure, Freestyle, rendu 2x), puis compose dans le Python du système (PIL) :
réduction prémultipliée, contour sombre extérieur (lisible à 24 px), lueur colorée, éclats.
Puis ouvrir l'éditeur Godot ou lancer `godot --headless --path . --import` pour les .import.

Sorties (PNG transparents) dans assets/ui/currency/ :
    gem.png, coin.png                       256 x 256  (compteurs, prix, pastilles)
    gems_pack_1.png ... gems_pack_4.png     512 x 512  (cartes et bandeau de l'onglet Gemmes)
      1 : une gemme et quelques éclats   2 : une poignée   3 : bourse ouverte   4 : coffre qui déborde
Lus par scripts/ui/menus/currency_art.gd (repli sur le dessin en code si une image manque).
Repère des modèles : z vers le haut, face vers -Y (caméra), lumière en haut à gauche.
"""
from __future__ import annotations

import math
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "ui", "currency")
TMP = os.environ.get("RDM_TMP", os.path.join(tempfile.gettempdir(), "rdm_currency"))
BLENDER = os.environ.get("BLENDER", "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe")
SS = 2

try:
    import bpy  # noqa: F401
    IN_BLENDER = True
except ImportError:
    IN_BLENDER = False

# nom : (taille finale px, élévation caméra °, azimut °, marge de cadrage, couleur de lueur, force de lueur,
#        rayon de lueur px, contour extérieur px, éclats [(x, y, taille) relatifs à la boîte de l'objet])
ITEMS = {
    "gem": (256, 9.0, 0.0, 1.30, "#5fe6ff", 0.80, 12, 7, [(0.30, 0.20, 0.30)]),
    "coin": (256, 8.0, 0.0, 1.30, "#ffc84a", 0.55, 12, 7, [(0.26, 0.20, 0.28)]),
    "gems_pack_1": (512, 18.0, 0.0, 1.30, "#5fe6ff", 0.55, 26, 6, [(0.36, 0.14, 0.16)]),
    "gems_pack_2": (512, 20.0, 0.0, 1.24, "#5fe6ff", 0.65, 28, 6, [(0.30, 0.16, 0.13), (0.74, 0.40, 0.09)]),
    "gems_pack_3": (512, 22.0, -12.0, 1.26, "#ffd36a", 0.60, 22, 6,
                    [(0.42, 0.10, 0.13), (0.78, 0.56, 0.09), (0.20, 0.70, 0.07)]),
    "gems_pack_4": (512, 26.0, -16.0, 1.22, "#ffd36a", 0.70, 24, 6,
                    [(0.36, 0.10, 0.14), (0.70, 0.22, 0.10), (0.16, 0.62, 0.08), (0.86, 0.72, 0.08)]),
}


# =============================================================================== Blender
if IN_BLENDER:
    sys.path.insert(0, HERE)
    import bmesh  # noqa: E402
    from mathutils import Vector  # noqa: E402

    import build_containers as BC  # noqa: E402
    import build_props as P  # noqa: E402
    import rdm_common as C  # noqa: E402

    M = P.M

    def gem_mat(kind: str = "cyan"):
        if kind == "deep":
            return C.toon("gem_deep", "#2a86e0", "#18287a", "#86d4ff", rim=0.45)
        if kind == "violet":
            return C.toon("gem_violet", "#9a66ff", "#3a1e8a", "#d2bcff", rim=0.45)
        return C.toon("gem_cyan", "#2cc6ea", "#1550a0", "#9cf2ff", rim=0.45)

    def gem_low_mat(kind: str = "cyan"):
        if kind == "deep":
            return C.toon("gem_deep_low", "#2470cc", "#141e66", "#6ab8f4", rim=0.3)
        if kind == "violet":
            return C.toon("gem_violet_low", "#7a4ae0", "#2a1270", "#b89cff", rim=0.3)
        return C.toon("gem_cyan_low", "#1fa6d8", "#12408a", "#7ae4fa", rim=0.3)

    def gold_face():
        return C.toon("coin_face", "#eeaa2a", "#9a501c", "#ffcf4e", rim=0.35)

    def gold_edge():
        return C.toon("coin_edge", "#c97e22", "#663018", "#f0b440", rim=0.25)

    def gold_emboss():
        return C.toon("coin_emboss", "#ffc83c", "#b0601e", "#ffe88a", rim=0.4)

    def hoard_mat():
        return C.toon_pattern("hoard", [("#eeaa2a", "#9a501c", "#ffcf4e"), ("#c97e22", "#663018", "#f0b440")],
                              scale=9.0, thresholds=(0.5,), rim=0.3)

    def _xform_verts(bm, loc, rot, scale):
        C.bm_xform(bm, loc=loc, rot=rot, scale=(scale, scale, scale))
        return bm

    # ------------------------------------------------------------------- gemme taillée
    def gem(B, name, loc=(0, 0, 0), scale=1.0, rot=(0, 0, 0), kind="cyan", n=8):
        """Gemme taillée (table, couronne à facettes triangulaires, rondiste, pavillon) ;
        girdle de rayon 1 à z = 0, table en haut, colette en bas (z ≈ -1)."""
        crown = bmesh.new()
        tz, tr, gz = 0.46, 0.54, 0.0
        g = [crown.verts.new((math.cos(2 * math.pi * i / n), math.sin(2 * math.pi * i / n), gz)) for i in range(n)]
        t = [crown.verts.new((tr * math.cos(2 * math.pi * (i + 0.5) / n), tr * math.sin(2 * math.pi * (i + 0.5) / n),
                              tz)) for i in range(n)]
        for i in range(n):
            j = (i + 1) % n
            crown.faces.new((g[i], g[j], t[i]))
            crown.faces.new((t[i - 1], g[i], t[i]))
        crown.faces.new(t)
        g2 = [crown.verts.new((v.co.x, v.co.y, -0.08)) for v in g]
        for i in range(n):
            j = (i + 1) % n
            crown.faces.new((g2[i], g2[j], g[j], g[i]))
        bmesh.ops.recalc_face_normals(crown, faces=crown.faces)
        _xform_verts(crown, (0, 0, 0), (0, 0, 0), 1.0)
        pav = bmesh.new()
        b = [pav.verts.new((math.cos(2 * math.pi * i / n), math.sin(2 * math.pi * i / n), -0.08)) for i in range(n)]
        m = [pav.verts.new((0.5 * math.cos(2 * math.pi * (i + 0.5) / n), 0.5 * math.sin(2 * math.pi * (i + 0.5) / n),
                            -0.68)) for i in range(n)]
        cu = pav.verts.new((0, 0, -1.22))
        for i in range(n):
            j = (i + 1) % n
            pav.faces.new((b[j], b[i], m[i]))
            pav.faces.new((b[i], m[i - 1], m[i]))
            pav.faces.new((m[i], m[i - 1], cu))
        bmesh.ops.recalc_face_normals(pav, faces=pav.faces)
        for bm in (crown, pav):
            C.bm_xform(bm, rot=(0, 0, math.pi / n * 0.5))
            C.bm_xform(bm, loc=loc, rot=rot, scale=(scale, scale, scale))
        a = B.add(name + "_crown", crown, gem_mat(kind), sharp=4.0)
        B.add(name + "_pav", pav, gem_low_mat(kind), sharp=4.0)
        return a

    # ------------------------------------------------------------------- pièce d'or
    def _star(r_out, r_in, z, n=5, rot=0.0):
        pts = []
        for k in range(2 * n):
            a = math.pi / 2 + rot + math.pi * k / n
            r = r_out if k % 2 == 0 else r_in
            pts.append((r * math.cos(a), r * math.sin(a), z))
        return pts

    def coin(B, name, loc=(0, 0, 0), scale=1.0, rot=(0, 0, 0), emblem=True, seg=40):
        """Pièce épaisse : tranche crénelée, liseré en relief, étoile en relief. Face +Z."""
        parts = []
        th = 0.24
        body = C.bm_cyl(seg, 1.0, 1.0, th)
        parts.append((body, gold_edge(), 30.0))
        for sgn in (1, -1):
            face = C.bm_cyl(seg, 0.86, 0.86, 0.02)
            C.bm_xform(face, loc=(0, 0, sgn * (th / 2 + 0.005)))
            parts.append((face, gold_face(), 30.0))
            rim = C.bm_torus(seg, 6, 0.9, 0.06)
            C.bm_xform(rim, loc=(0, 0, sgn * th / 2), scale=(1, 1, 0.9))
            parts.append((rim, gold_emboss(), 80.0))
        if emblem:
            secs = [_star(0.6, 0.25, th / 2 + 0.01), _star(0.52, 0.215, th / 2 + 0.1)]
            st = C.bm_loft(secs)
            parts.append((st, gold_emboss(), 20.0))
        # crénelage de la tranche
        for k in range(0, seg, 2):
            a = 2 * math.pi * (k + 0.5) / seg
            nb = C.bm_box(0.05, 0.035, th * 0.82)
            C.bm_xform(nb, loc=(math.cos(a) * 1.0, math.sin(a) * 1.0, 0), rot=(0, 0, a))
            parts.append((nb, gold_edge(), 30.0))
        first = None
        for k, (bm, mat, sharp) in enumerate(parts):
            C.bm_xform(bm, loc=loc, rot=rot, scale=(scale, scale, scale))
            ob = B.add("%s_%d" % (name, k), bm, mat, sharp=sharp, outline=k < 1 + 4 + (1 if emblem else 0))
            first = first or ob
        return first

    def coin_flat(B, name, loc, scale, tilt=(0.0, 0.0), spin=0.0):
        """Pièce posée presque à plat (tas, débordement)."""
        coin(B, name, loc=loc, scale=scale, rot=(tilt[0], tilt[1], spin), emblem=True, seg=28)

    # ------------------------------------------------------------------- compositions
    FACE_CAM = (math.radians(90), 0, 0)   # face +Z de la pièce vers la caméra (-Y)

    def i_gem(B):
        gem(B, "gem", scale=1.0, rot=(math.radians(4), 0, 0))

    def i_coin(B):
        coin(B, "coin", rot=(math.radians(90 - 6), 0, math.radians(-26)))

    def i_pack_1(B):
        gem(B, "big", (0, 0, 0.55), 1.0, (math.radians(6), math.radians(-8), 0))
        gem(B, "s1", (-1.05, -0.35, -0.42), 0.3, (math.radians(30), math.radians(40), 0.4), "deep")
        gem(B, "s2", (1.0, -0.5, -0.45), 0.24, (math.radians(-20), math.radians(-55), 1.1))
        gem(B, "s3", (0.55, -0.9, -0.6), 0.17, (math.radians(70), 0, 0.3))

    def i_pack_2(B):
        gem(B, "back", (0.1, 0.5, 0.75), 0.9, (math.radians(8), math.radians(-6), 0.2))
        gem(B, "left", (-0.95, 0.0, 0.3), 0.66, (math.radians(10), math.radians(24), 0.5), "deep")
        gem(B, "right", (0.98, -0.1, 0.32), 0.7, (math.radians(-6), math.radians(-22), 0.1))
        gem(B, "front", (-0.15, -0.75, -0.05), 0.55, (math.radians(-14), math.radians(10), 0.7))
        gem(B, "tiny1", (0.7, -1.0, -0.4), 0.28, (math.radians(50), math.radians(-30), 0.2), "deep")
        gem(B, "tiny2", (-1.1, -0.9, -0.42), 0.24, (math.radians(-40), math.radians(60), 0.9))

    def i_pack_3(B):
        # bourse de cuir ouverte qui déborde de gemmes, quelques pièces devant
        sack = C.bm_sphere(20, 14, 1.0)
        for v in sack.verts:
            z = v.co.z
            k = 1.0 - 0.18 * max(0.0, z)            # haut resserré
            v.co.x *= 1.05 * k
            v.co.y *= 0.95 * k
            v.co.z = z * 0.82 if z < 0 else z * 0.7
        C.bm_xform(sack, loc=(0, 0.1, 0.0))
        B.add("sack", sack, M("leather"), sharp=80)
        neck = [C.ellipse(0, 0.1, 0.5 + dz, 0.62 + f, 0.56 + f, n=16) for dz, f in ((0.0, 0.0), (0.22, 0.1), (0.36, 0.24))]
        B.add("neck", C.bm_loft(neck, cap_start=False, cap_end=False), M("leather"), sharp=80)
        B.torus("cord", 0.66, 0.06, (0, 0.1, 0.56), M("cloth_cream"), seg=24, rseg=6)
        B.tube("tie", [(0.55, -0.32, 0.56), (0.72, -0.62, 0.2), (0.62, -0.75, -0.15)], [0.05, 0.045, 0.04],
               M("cloth_cream"))
        # monticule de gemmes dans l'ouverture
        B.sphere("fill", 0.62, (0, 0.1, 0.78), gem_low_mat("deep"), scale=(1.15, 1.0, 0.45), seg=16, rings=8)
        for k, (x, y, z, s, kd) in enumerate(((0.0, 0.0, 1.25, 0.5, "cyan"), (-0.42, 0.05, 1.02, 0.36, "deep"),
                                              (0.45, 0.15, 1.05, 0.38, "cyan"), (-0.15, -0.35, 0.98, 0.3, "cyan"),
                                              (0.3, -0.3, 0.95, 0.26, "violet"))):
            gem(B, "g%d" % k, (x, y, z), s, (math.radians(10 + 9 * k), math.radians(-14 * (k % 3 - 1)), 0.4 * k), kd)
        # pièces et gemmes tombées devant
        coin_flat(B, "c1", (-1.0, -0.75, -0.62), 0.32, (math.radians(70), math.radians(10)), 0.3)
        coin_flat(B, "c2", (-0.62, -0.95, -0.72), 0.3, (math.radians(12), 0.0), 0.0)
        coin_flat(B, "c3", (1.05, -0.55, -0.66), 0.3, (math.radians(60), math.radians(-20)), -0.5)
        gem(B, "f1", (0.55, -1.0, -0.55), 0.3, (math.radians(-30), math.radians(40), 0.2))
        gem(B, "f2", (-1.25, -0.3, -0.52), 0.24, (math.radians(50), math.radians(-30), 0.8), "deep")

    def i_pack_4(B):
        # coffre ouvert (modèle des conteneurs), qui déborde d'or et de gemmes
        BC.c_chest(B, True)
        w, d, hb = 1.45, 0.82, 0.52
        B.sphere("hoard", 0.62, (0, -0.02, hb + 0.02), hoard_mat(), scale=(1.12, 0.62, 0.55), seg=18, rings=9)
        for k in range(11):   # pièces sur le tas
            a = k * 2.399
            r = 0.18 + 0.05 * (k % 4)
            coin_flat(B, "hc%d" % k, (math.cos(a) * r * 2.0, -0.05 + math.sin(a) * r * 0.9, hb + 0.27 - 0.03 * (k % 3)),
                      0.12, (math.radians(20 + 13 * (k % 4)), math.radians(-15 + 9 * (k % 3))), a)
        for k, (x, y, z, s, kd) in enumerate(((0.0, -0.05, 0.98, 0.3, "cyan"), (-0.42, 0.0, 0.88, 0.22, "violet"),
                                              (0.42, 0.02, 0.9, 0.24, "deep"), (-0.18, -0.22, 0.86, 0.18, "cyan"),
                                              (0.25, -0.24, 0.84, 0.16, "cyan"))):
            gem(B, "hg%d" % k, (x, y, z), s, (math.radians(8 + 11 * k), math.radians(-12 * (k % 3 - 1)), 0.5 * k), kd)
        # débordement devant le coffre
        for k, (x, y, z, s, tx) in enumerate(((-0.55, -0.62, 0.03, 0.14, 8), (-0.25, -0.72, 0.02, 0.13, 4),
                                              (0.05, -0.66, 0.05, 0.14, 70), (0.6, -0.6, 0.03, 0.13, 10),
                                              (0.85, -0.42, 0.02, 0.12, 6), (-0.85, -0.35, 0.02, 0.12, 12))):
            coin_flat(B, "fc%d" % k, (x, y, z), s, (math.radians(tx), math.radians(6 * (k % 3))), 0.7 * k)
        gem(B, "fg1", (0.32, -0.78, 0.14), 0.18, (math.radians(-20), math.radians(30), 0.4))
        gem(B, "fg2", (-0.7, -0.62, 0.12), 0.15, (math.radians(30), math.radians(-40), 1.0), "deep")
        # pièces en équilibre sur le bord avant
        coin_flat(B, "edge1", (-0.35, -d / 2 - 0.02, hb + 0.06), 0.13, (math.radians(75), 0.0), 0.1)
        coin_flat(B, "edge2", (0.48, -d / 2 - 0.0, hb + 0.05), 0.12, (math.radians(65), math.radians(10)), -0.2)

    BUILDERS = {"gem": i_gem, "coin": i_coin, "gems_pack_1": i_pack_1, "gems_pack_2": i_pack_2,
                "gems_pack_3": i_pack_3, "gems_pack_4": i_pack_4}

    def fit_camera(cam, objs, margin: float) -> None:
        """Recadre la caméra orthographique sur l'ensemble des objets (carré, centré)."""
        bpy.context.view_layer.update()
        inv = cam.matrix_world.inverted()
        xs, ys = [], []
        for ob in objs:
            if ob.type != "MESH":
                continue
            mw = ob.matrix_world
            for v in ob.data.vertices:
                p = inv @ (mw @ v.co)
                xs.append(p.x)
                ys.append(p.y)
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        span = max(max(xs) - min(xs), max(ys) - min(ys))
        cam.location = cam.location + cam.matrix_world.to_3x3() @ Vector((cx, cy, 0.0))
        cam.data.ortho_scale = span * margin

    def render_item(name: str) -> None:
        size, elev, azim, margin = ITEMS[name][:4]
        C.reset_scene()
        C.setup_render(size * SS, samples=8, outline_px=(2.2 if size <= 256 else 2.6) * SS * size / 256,
                       inner_ratio=0.45)
        B = P.Builder()
        BUILDERS[name](B)
        cam = C.ortho_camera(elev, 4.0, target=(0, 0, 0), azim_deg=azim)
        fit_camera(cam, B.objs, margin)
        os.makedirs(TMP, exist_ok=True)
        C.render_to(os.path.join(TMP, name + "_big.png"))
        print("RENDER", name)

    def blender_main() -> None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
        names = argv[argv.index("--render") + 1].split(",") if "--render" in argv else list(ITEMS)
        for n in names:
            render_item(n)


# =============================================================================== composition (PIL)
def _hex(h: str) -> tuple[int, int, int]:
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))  # type: ignore


def _sparkle(img, cx: float, cy: float, r: float) -> None:
    """Éclat à 4 branches (blanc chaud) + petit halo."""
    from PIL import Image, ImageDraw, ImageFilter
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    w = r * 0.16
    d.polygon([(cx, cy - r), (cx + w, cy - w), (cx + r, cy), (cx + w, cy + w), (cx, cy + r), (cx - w, cy + w),
               (cx - r, cy), (cx - w, cy - w)], fill=(255, 255, 248, 255))
    halo = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse((cx - r * 0.45, cy - r * 0.45, cx + r * 0.45, cy + r * 0.45), fill=(255, 255, 255, 200))
    halo = halo.filter(ImageFilter.GaussianBlur(max(1.0, r * 0.25)))
    img.alpha_composite(halo)
    img.alpha_composite(lay)


def compose(name: str) -> None:
    from PIL import Image, ImageChops, ImageFilter
    size, _e, _a, _m, glow_hex, glow_k, glow_r, outline, sparkles = ITEMS[name]
    big = Image.open(os.path.join(TMP, name + "_big.png")).convert("RGBA")
    im = big.convert("RGBa").resize((size, size), Image.LANCZOS).convert("RGBA")
    a = im.getchannel("A")
    # contour sombre extérieur : garde la silhouette lisible en tout petit (compteurs 24-32 px)
    ring = a.filter(ImageFilter.MaxFilter(outline | 1)).filter(ImageFilter.GaussianBlur(0.8))
    out_l = Image.new("RGBA", im.size, (18, 10, 30, 0))
    out_l.putalpha(ring)
    # lueur colorée
    halo = a.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(glow_r))
    halo = halo.point(lambda v: int(min(255, v * glow_k)))
    # atténuation radiale : la lueur s'éteint avant les bords de l'image (pas de carré visible)
    fade = Image.radial_gradient("L").resize(im.size, Image.BILINEAR).point(lambda v: max(0, 255 - int(v * 1.25)))
    halo = ImageChops.multiply(halo, fade)
    glow = Image.new("RGBA", im.size, (*_hex(glow_hex), 0))
    glow.putalpha(halo)
    res = Image.alpha_composite(glow, out_l)
    res = Image.alpha_composite(res, im)
    bb = a.getbbox() or (0, 0, size, size)
    bw, bh = bb[2] - bb[0], bb[3] - bb[1]
    for (sx, sy, sr) in sparkles:
        _sparkle(res, bb[0] + sx * bw, bb[1] + sy * bh, sr * min(bw, bh) * 0.5)
    os.makedirs(OUT, exist_ok=True)
    res.save(os.path.join(OUT, name + ".png"), optimize=True)
    print("OK", name, "->", os.path.join(OUT, name + ".png"))


def main() -> None:
    args = sys.argv[1:]
    names = args[args.index("--only") + 1].split(",") if "--only" in args else list(ITEMS)
    for n in names:
        if n not in ITEMS:
            raise SystemExit("inconnu : %s (choix : %s)" % (n, ", ".join(ITEMS)))
    if "--compose" not in args:
        env = dict(os.environ, RDM_TMP=TMP)
        subprocess.run([BLENDER, "--background", "--factory-startup", "--python", os.path.abspath(__file__), "--",
                        "--render", ",".join(names)], check=True, env=env)
    for n in names:
        compose(n)


if __name__ == "__main__":
    if IN_BLENDER:
        blender_main()
    else:
        main()
