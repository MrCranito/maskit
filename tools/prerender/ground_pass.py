"""Passe « sol seul » commune aux scènes pré-rendues (fw_scene.py, ss_scene.py, mall_scene.py).

Pour chaque bâtiment, rend la zone de l'image que ses surfaces hautes recouvrent (pixels de occ.png
dont G = id + 1 et R > 0, voir render_occ) AVEC ce bâtiment masqué (murs, toit, façade, auvent,
mobilier ; le plancher reste) : on obtient le vrai sol (ou plancher) caché derrière / sous lui.
Même caméra et cadrage que « full » (pixels alignés), même étalonnage. Sorties :
  <out>/g<id>.png   (rectangle englobant, recadré)
  <out>/grounds.json  [{id, px: [x0, y0, x1, y1]}]  (px image, x1/y1 exclus)
compose_ground.py en tire les patchs gr_<id>.webp du paquet (alpha = surfaces hautes du bâtiment).
Le jeu (PrerenderBackdrop) affiche le patch sous le bâtiment estompé quand une unité visible
passe derrière ou sous lui. Reprise : un g<id>.png déjà rendu est conservé.
"""
import json
import os


def building_boxes(occ_path, pad=8):
    """{id: (x0, y0, x1, y1)} : rectangle englobant (px image, + pad) des surfaces hautes de
    chaque bâtiment dans occ.png."""
    import numpy as np
    from PIL import Image
    occ = np.asarray(Image.open(occ_path).convert("RGB"), dtype=np.uint8)
    h, w = occ.shape[:2]
    g = occ[:, :, 1].astype(np.int32)
    hi = occ[:, :, 0] > 0
    out = {}
    for code in np.unique(g[hi]):
        if code <= 0:
            continue
        ys, xs = np.nonzero(hi & (g == code))
        if len(xs) < 6:
            continue
        out[int(code) - 1] = (max(int(xs.min()) - pad, 0), max(int(ys.min()) - pad, 0),
                              min(int(xs.max()) + 1 + pad, w), min(int(ys.max()) + 1 + pad, h))
    return out


def render_ground(bpy, scene, out_dir, hide_for, render_fn, only=""):
    """Passe « sol seul » (voir en-tête). `hide_for(bid)` → objets à masquer pour ce bâtiment ;
    `render_fn(path)` → rendu étalonné comme « full ». La caméra doit être cadrée comme « full »
    (frame(...)) et occ.png déjà rendu. Renvoie la durée totale (s)."""
    import time
    occ_path = os.path.join(out_dir, "occ.png")
    if not os.path.exists(occ_path):
        raise SystemExit("ground: occ.png manquant (passe occ d'abord)")
    pw, ph = scene.render.resolution_x, scene.render.resolution_y
    boxes = building_boxes(occ_path)
    scene.render.use_border = True
    scene.render.use_crop_to_border = True
    entries = []
    t = 0.0
    for bid in sorted(boxes):
        x0, y0, x1, y1 = boxes[bid]
        entries.append({"id": bid, "px": [x0, y0, x1, y1]})
        outp = os.path.join(out_dir, "g%d.png" % bid)
        if os.path.exists(outp) or (only and str(bid) not in only.split(";")):
            continue
        objs = hide_for(bid)
        saved = [(o, o.hide_render) for o in objs]
        for o in objs:
            o.hide_render = True
        scene.render.border_min_x, scene.render.border_max_x = x0 / pw, x1 / pw
        scene.render.border_min_y, scene.render.border_max_y = 1.0 - y1 / ph, 1.0 - y0 / ph
        t0 = time.time()
        render_fn(outp + ".tmp.png")
        os.replace(outp + ".tmp.png", outp)
        t += time.time() - t0
        for o, h in saved:
            o.hide_render = h
        print("  ground", bid, [o.name for o in objs], round(t, 1), flush=True)
    scene.render.use_border = False
    json.dump(entries, open(os.path.join(out_dir, "grounds.json"), "w"), indent=1)
    return t
