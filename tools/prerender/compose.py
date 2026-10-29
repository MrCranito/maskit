"""Découpe un rendu Blender (fw_scene.py) en paquet de carte pour le jeu.

Usage : python3 compose.py <render_dir> <pack_dir> [tile=1024] [quality=82]
Entrées : render_dir/full.png, b<id>_in.png, render.json
Sorties : pack_dir/t_<col>_<row>.webp  (tuiles du fond, ≤ tile px)
          pack_dir/in_<id>.webp        (intérieur sans toit d'un bâtiment, alpha = masque emprise)
          pack_dir/map.json            (géométrie : px/case, inclinaison, marge, tuiles, intérieurs)
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
meta = {"tiles_md5": info.get("tiles_md5", ""), "seed": info["seed"], "ppc": ppc, "tilt_deg": info["tilt_deg"], "margin": M,
        "projection": info.get("projection", "stretch_y"),
        "size": info["size"], "image_px": [W, H], "tiles": tiles, "interiors": interiors,
        "render_s": info["renders"]}
json.dump(meta, open(os.path.join(dst, "map.json"), "w"), indent=1)
tot = sum(os.path.getsize(os.path.join(dst, f)) for f in os.listdir(dst))
print("PACK", dst, len(tiles), "tiles", len(interiors), "interiors", round(tot / 1e6, 2), "MB")
