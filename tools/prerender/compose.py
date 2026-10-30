"""Découpe un rendu Blender (fw_scene.py) en paquet de carte pour le jeu.

Usage : python3 compose.py <render_dir> <pack_dir> [tile=1024] [quality=82]
Entrées : render_dir/full.png, b<id>_in.png, render.json [, mask.png, occ.png, layout.json]
Sorties : pack_dir/t_<col>_<row>.webp  (tuiles du fond, ≤ tile px)
          pack_dir/in_<id>.webp        (intérieur sans toit d'un bâtiment, alpha = masque emprise)
          pack_dir/o_<col>_<row>.png   (ids d'occultation par tuile, voir build_occluders)
          pack_dir/map.json            (géométrie : px/case, inclinaison, marge, tuiles, intérieurs,
                                        collision (rectangles monde), occluders)
Projection (render.json "projection": "ground_square", fw_scene.py) : caméra orthographique
  inclinée de tilt°, pixel_aspect_x = 1/cos(tilt) → le SOL (z = 0) se projette en
  px_x = (cx + margin) * ppc ; px_y = (cy + margin) * ppc        (carré, sans étirement)
  et un point à la hauteur z (cases) remonte de z * tan(tilt) * ppc px.
→ le jeu pose l'image à l'échelle 64/ppc : le sol tombe pile sur la grille.
  (Ancien format "projection" absent : px_y = (cy + margin) * ppc * cos(tilt), étirement Y.)
"""
import sys, json, math, os
from PIL import Image, ImageDraw, ImageFilter

src, dst = sys.argv[1], sys.argv[2]
TILE = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
Q = int(sys.argv[4]) if len(sys.argv) > 4 else 82
os.makedirs(dst, exist_ok=True)
info = json.load(open(os.path.join(src, "render.json")))
ppc, M = info["ppc"], info["margin"]
square = info.get("projection") == "ground_square"
cosT = 1.0 if square else math.cos(math.radians(info["tilt_deg"]))
tanT = math.tan(math.radians(info["tilt_deg"]))
full = Image.open(os.path.join(src, "full.png")).convert("RGB")
W, H = full.size
tiles = []
for r in range(0, H, TILE):
    for c in range(0, W, TILE):
        t = full.crop((c, r, min(c + TILE, W), min(r + TILE, H)))
        name = "t_%d_%d.webp" % (c // TILE, r // TILE)
        t.save(os.path.join(dst, name), quality=Q, method=6)
        tiles.append({"file": name, "px": [c, r, t.size[0], t.size[1]]})
interiors = []
for b in info["buildings"]:
    p = os.path.join(src, "b%d_in.png" % b["id"])
    if not os.path.exists(p):
        continue
    im = Image.open(p).convert("RGB")
    x0, y0, x1, y1 = b["px"]
    bx, by, bw, bh = b["rect"]
    # Masque : emprise au sol + hauteur projetée du toit (≤ 4,6 cases × tan) au nord (le toit
    # du rendu « full » y déborde), + auvent / perron au sud ; bord adouci.
    up = (4.6 * tanT) if square else 1.6
    gx0 = (bx + M) * ppc - x0 - 2
    gx1 = (bx + bw + M) * ppc - x0 + 2
    gy0 = (by - up + M) * ppc * cosT - y0
    gy1 = (by + bh + M + (1.25 if square else 0.0)) * ppc * cosT - y0 + 3
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rectangle([gx0, gy0, gx1, gy1], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.5))
    bb = (max(int(gx0) - 3, 0), max(int(gy0) - 3, 0), min(int(gx1) + 4, im.size[0]), min(int(gy1) + 4, im.size[1]))
    rgba = im.copy(); rgba.putalpha(mask)
    rgba = rgba.crop(bb)
    name = "in_%d.webp" % b["id"]
    rgba.save(os.path.join(dst, name), quality=Q, method=6)
    interiors.append({"id": b["id"], "file": name, "rect": b["rect"],
                      "px": [x0 + bb[0], y0 + bb[1], rgba.size[0], rgba.size[1]]})
# ---------------------------------------------------------------- collisions dérivées du masque
def build_collision():
    """Couche de collision « emprise rendue » : pixels du masque zénithal (mask.png, 4 px/case,
    fw_scene.py « mask ») couverts à ≥ 50 % (obstacle du plan R ou fouillis G) sur des cases
    PRATICABLES du plan (les cases murées ont déjà leur collision). Cases protégées (portes et leur
    abord, escaliers, apparition, extraction) jamais bloquées. Connexité vérifiée sur la
    grille fine (dégagement d'un pixel autour du centre du joueur) : une case praticable du plan qui
    deviendrait inaccessible fait retirer la collision de son voisinage. Rectangles fusionnés,
    unités monde (64 / case), repère du plan (case (0,0) en (0,0))."""
    import numpy as np
    mp = os.path.join(src, "mask.png")
    lp = os.path.join(src, "layout.json")
    if not (os.path.exists(mp) and os.path.exists(lp)):
        return None, {}
    L = json.load(open(lp))
    Wc, Hc = L["size"]
    K = 4
    m = np.asarray(Image.open(mp).convert("RGB"), dtype=np.uint8)
    m = m[M * K:(M + Hc) * K, M * K:(M + Wc) * K]
    solid = (np.maximum(m[:, :, 0], m[:, :, 1]) >= 128)
    tiles_ = np.array([[int(ch) for ch in row] for row in L["tiles"]], dtype=np.uint8)
    walk_c = np.isin(tiles_, [1, 2, 4, 5, 6])
    walk = np.repeat(np.repeat(walk_c, K, 0), K, 1)
    prot = np.zeros_like(walk_c)
    def protect(x, y, r=0):
        prot[max(y - r, 0):y + r + 1, max(x - r, 0):x + r + 1] = True
    for d in L.get("doors", []):
        x, y = d["cell"]
        protect(x, y, 1)
        if not d.get("vertical"):
            protect(x, y + 2, 0)
            protect(x, y - 2, 0)
    for st in L.get("stairs", []):
        protect(*st["cell"], 1)
    for c in L.get("extraction", []):
        protect(*c, 1)
    protect(*L["player_spawn"], 1)
    protp = np.repeat(np.repeat(prot, K, 0), K, 1)
    extra = solid & walk & ~protp
    def reach(block):
        free = walk & ~block
        ctr = free.copy()
        ctr[1:, :] &= free[:-1, :]; ctr[:-1, :] &= free[1:, :]
        ctr[:, 1:] &= free[:, :-1]; ctr[:, :-1] &= free[:, 1:]
        sx, sy = L["player_spawn"]
        seen = np.zeros_like(ctr)
        st_ = [(sy * K + K // 2, sx * K + K // 2)]
        if not ctr[st_[0]]:
            ctr[sy * K:(sy + 1) * K, sx * K:(sx + 1) * K] = free[sy * K:(sy + 1) * K, sx * K:(sx + 1) * K]
        while st_:
            y, x = st_.pop()
            if y < 0 or x < 0 or y >= ctr.shape[0] or x >= ctr.shape[1] or seen[y, x] or not ctr[y, x]:
                continue
            seen[y, x] = True
            st_ += [(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)]
        return seen.reshape(Hc, K, Wc, K).any(axis=(1, 3))
    base = reach(np.zeros_like(extra))
    fixed = 0
    freed = set()
    for it in range(60):
        r = reach(extra)
        # cases « obstacle » (couvertes à ≥ 50 %) : bloquées volontairement, pas à atteindre
        cov = extra.reshape(Hc, K, Wc, K).mean(axis=(1, 3))
        lost = base & ~r & walk_c & (cov < 0.5)
        if not lost.any():
            break
        for (y, x) in zip(*np.nonzero(lost)):
            extra[max(y - 1, 0) * K:(y + 2) * K, max(x - 1, 0) * K:(x + 2) * K] = False
            fixed += 1
            for yy in range(max(y - 1, 0), min(y + 2, Hc)):
                for xx in range(max(x - 1, 0), min(x + 2, Wc)):
                    freed.add((int(xx), int(yy)))
    # fusion en rectangles (segments par ligne prolongés vers le bas)
    used = np.zeros_like(extra)
    rects = []
    h_, w_ = extra.shape
    for y in range(h_):
        x = 0
        while x < w_:
            if used[y, x] or not extra[y, x]:
                x += 1
                continue
            x1 = x
            while x1 < w_ and extra[y, x1] and not used[y, x1]:
                x1 += 1
            y1 = y + 1
            while y1 < h_ and extra[y1, x:x1].all() and not used[y1, x:x1].any():
                y1 += 1
            used[y:y1, x:x1] = True
            s_ = 64 // K
            rects.append([x * s_, y * s_, (x1 - x) * s_, (y1 - y) * s_])
            x = x1
    # masque d'emprise copié dans le paquet (tests GUT : obstacles rendus = cases bloquantes)
    import shutil
    shutil.copy(mp, os.path.join(dst, "footprint.png"))
    stats = {"px": int(extra.sum()), "rects": len(rects), "unblocked_cells": fixed,
             "freed": sorted([list(c) for c in freed]),
             "cells": int(extra.reshape(Hc, K, Wc, K).any(axis=(1, 3)).sum())}
    return rects, stats


# ---------------------------------------------------------------- occultation (tranches triées en Y)
def build_occluders():
    """occ.png (fw_scene.py « occ », pixels alignés sur full.png) : R = rangée + 1 de la surface
    haute visible, G = bâtiment + 1. Par tuile du fond : image d'ids o_<c>_<r>.png (R, G ; sans perte)
    et liste des tranches [rangée, bâtiment, x, y, w, h] (px image, rectangle englobant). Le jeu
    dessine chaque tranche (pixels de la tuile du fond dont l'id correspond) triée en Y à la limite
    sud de sa rangée : un personnage plus au nord passe derrière."""
    import numpy as np
    op = os.path.join(src, "occ.png")
    if not os.path.exists(op):
        return None
    occ = np.asarray(Image.open(op).convert("RGB"), dtype=np.uint8)
    out = []
    for t in tiles:
        x0, y0, tw_, th_ = t["px"]
        sub = occ[y0:y0 + th_, x0:x0 + tw_]
        r = sub[:, :, 0].astype(np.int32)
        g = sub[:, :, 1].astype(np.int32)
        key = np.where(r > 0, r * 256 + g, -1)
        ks = np.unique(key)
        ks = ks[ks >= 0]
        if len(ks) == 0:
            continue
        idimg = np.zeros((th_, tw_, 3), dtype=np.uint8)
        idimg[:, :, 0] = np.where(r > 0, r, 0)
        idimg[:, :, 1] = np.where(r > 0, g, 0)
        name = "o_%s.png" % t["file"][2:-5]
        Image.fromarray(idimg, "RGB").save(os.path.join(dst, name), optimize=True)
        sl = []
        for k in ks:
            ys, xs = np.nonzero(key == k)
            if len(xs) < 6:
                continue
            sl.append([int(k // 256) - 1, int(k % 256) - 1, int(x0 + xs.min()), int(y0 + ys.min()),
                       int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)])
        out.append({"tile": t["file"], "ids": name, "slices": sl})
    return out


coll, cstats = build_collision()
occl = build_occluders()

meta = {"tiles_md5": info.get("tiles_md5", ""), "seed": info["seed"], "ppc": ppc, "tilt_deg": info["tilt_deg"], "margin": M,
        "projection": info.get("projection", "stretch_y"),
        "size": info["size"], "image_px": [W, H], "tiles": tiles, "interiors": interiors,
        "render_s": info["renders"]}
if coll is not None:
    meta["collision"] = coll
    meta["collision_stats"] = cstats
if occl is not None:
    meta["occluders"] = occl
# Patchs « sol seul » (passe gnd, compose_ground.py) : vrai sol derrière / sous chaque bâtiment.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compose_ground
grounds = compose_ground.build(src, dst, Q)
if grounds is not None:
    meta["grounds"] = grounds
json.dump(meta, open(os.path.join(dst, "map.json"), "w"), indent=1)
tot = sum(os.path.getsize(os.path.join(dst, f)) for f in os.listdir(dst))
print("PACK", dst, len(tiles), "tiles", len(interiors), "interiors", round(tot / 1e6, 2), "MB",
      "collision", cstats, "occluder tiles", len(occl or []))
