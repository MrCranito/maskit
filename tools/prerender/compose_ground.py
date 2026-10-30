"""Patchs « sol seul » du paquet de carte (passe gnd, voir ground_pass.py).

Usage : python3 compose_ground.py <render_dir> <pack_dir> [quality=82]
  → ajoute / remplace pack_dir/gr_<id>.webp et la clé « grounds » de pack_dir/map.json, sans
    toucher au reste du paquet (tuiles, intérieurs, collisions, occultation).
compose.py appelle aussi build() quand render_dir contient grounds.json.
Entrées : render_dir/grounds.json, g<id>.png (rendu « sol seul » du rectangle px), occ.png.
Alpha du patch = surfaces hautes du bâtiment dans occ.png (R > 0 et G = id + 1), dilatées de
2 px et adoucies : le patch remplace exactement ce que le bâtiment recouvre.
"""
import json
import os
import sys


def build(src, dst, q=82):
    import numpy as np
    from PIL import Image, ImageFilter
    gp = os.path.join(src, "grounds.json")
    op = os.path.join(src, "occ.png")
    if not (os.path.exists(gp) and os.path.exists(op)):
        return None
    occ = np.asarray(Image.open(op).convert("RGB"), dtype=np.uint8)
    out = []
    for e in json.load(open(gp)):
        bid = int(e["id"])
        x0, y0, x1, y1 = e["px"]
        p = os.path.join(src, "g%d.png" % bid)
        if not os.path.exists(p):
            print("  ground %d : g%d.png manquant" % (bid, bid))
            continue
        im = Image.open(p).convert("RGB")
        w, h = x1 - x0, y1 - y0
        if im.size != (w, h):
            print("  ground %d : taille %s au lieu de %s, recadrée" % (bid, im.size, (w, h)))
            fixed = Image.new("RGB", (w, h))
            fixed.paste(im, (0, 0))
            im = fixed
        sub = occ[y0:y1, x0:x1]
        m = ((sub[:, :, 0] > 0) & (sub[:, :, 1].astype(np.int32) == bid + 1)).astype(np.uint8) * 255
        mask = Image.fromarray(m, "L").filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.2))
        bb = mask.getbbox()
        if bb is None:
            continue
        rgba = im.copy()
        rgba.putalpha(mask)
        rgba = rgba.crop(bb)
        name = "gr_%d.webp" % bid
        rgba.save(os.path.join(dst, name), quality=q, method=6)
        out.append({"id": bid, "file": name, "px": [x0 + bb[0], y0 + bb[1], rgba.size[0], rgba.size[1]]})
    return out


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    q = int(sys.argv[3]) if len(sys.argv) > 3 else 82
    mp = os.path.join(dst, "map.json")
    meta = json.load(open(mp))
    info = json.load(open(os.path.join(src, "render.json")))
    if info.get("tiles_md5") and meta.get("tiles_md5") and info["tiles_md5"] != meta["tiles_md5"]:
        raise SystemExit("compose_ground : rendu d'un autre plan que le paquet (tiles_md5)")
    g = build(src, dst, q)
    if g is None:
        raise SystemExit("compose_ground : grounds.json ou occ.png manquant")
    meta["grounds"] = g
    json.dump(meta, open(mp, "w", newline="\n"), indent=1)
    print("GROUNDS", dst, len(g), "patchs", round(sum(os.path.getsize(os.path.join(dst, e["file"])) for e in g) / 1e6, 2), "MB")
