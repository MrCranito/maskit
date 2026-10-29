"""Bestiaire Far West : rendu des planches 8 directions (même pipeline que le héros et
art/blender/build_enemies.py : caméra orthographique 3/4 à 48°, matériaux toon peints, contour
Freestyle, même densité de pixels et même échelle en unités monde).

Un « modèle » (fw_humans.Human, fw_beasts.Beast) expose :
    model.j["root"]              joint racine (rotation Z = direction)
    model.dir_ang                angle courant (degrés)
    model.pose(anim, i, n)       pose l'image i/n de l'animation
    model.muzzle_world()         point (monde) du canon / de la gueule à l'image d'attaque 3
    model.anims()                {anim: (images, fps, boucle)}
    model.frame                  taille du cadre (px, carré)
    model.cam_z                  hauteur visée par la caméra (unités Blender)
    model.name                   nom affiché (méta)

Sortie : assets/sprites/enemies/<kind>/<kind>_atlas.png, <kind>_frames.tres, <kind>_meta.json
(format lu par scripts/enemies/enemy_art.gd).
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
BLENDER_DIR = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, BLENDER_DIR)
import rdm_common as C  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(BLENDER_DIR, "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "enemies")
TMP_DIR = os.environ.get("RDM_TMP", "/tmp/rdm_fw_bestiary")

SS = 2
ELEV = 48.0
# Densité du héros : 160 px pour ORTHO 2.30 ; échelle monde : 92.3 unités pour 160 px.
PX_PER_UNIT = 160.0 / 2.30
WORLD_PER_PX = 92.3 / 160.0
DIRS = {"e": 90.0, "se": 45.0, "s": 0.0, "sw": -45.0, "w": -90.0, "nw": -135.0, "n": 180.0, "ne": 135.0}


def setup_camera(frame: int, cam_z: float, outline_px: float = 4.6):
    C.setup_render((frame * SS, frame * SS), samples=4, outline_px=outline_px)
    cam = C.ortho_camera(ELEV, frame / PX_PER_UNIT, target=(0, 0, cam_z))
    cam.data.sensor_fit = "VERTICAL"
    return cam


def render_frame(path: str, frame: int):
    big = path + ".big.png"
    C.render_to(big)
    im = C.downscale(big, path, (frame, frame))
    os.remove(big)
    return im


def to_px(cam, co) -> list:
    bpy.context.view_layer.update()
    p = C.world_to_px(cam, co)
    return [round(p[0] / SS, 1), round(p[1] / SS, 1)]


def pack(frames: dict, order: list, frame: int) -> tuple:
    """Images rognées empaquetées en étagères (positions alignées sur 4 px, marge 4 px)."""
    from PIL import Image
    items = []
    for key in order:
        im = frames[key]
        a = im.getchannel("A").point(lambda v: 255 if v > 3 else 0)
        bb = a.getbbox() or (0, 0, 1, 1)
        bb = (max(0, bb[0] - 1), max(0, bb[1] - 1), min(frame, bb[2] + 1), min(frame, bb[3] + 1))
        items.append((key, im.crop(bb), bb))
    width = 2048
    srt = sorted(items, key=lambda it: -it[1].size[1])
    x = y = shelf = 0
    pos = {}
    for key, crop, _bb in srt:
        w, h = crop.size
        if x + w > width:
            x = 0
            y += (shelf + 4 + 3) // 4 * 4
            shelf = 0
        pos[key] = (x, y)
        x += (w + 4 + 3) // 4 * 4
        shelf = max(shelf, h)
    height = (y + shelf + 3) // 4 * 4
    atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    regions = {}
    for key, crop, bb in items:
        px, py = pos[key]
        atlas.paste(crop, (px, py))
        regions[key] = (px, py, crop.size[0], crop.size[1], bb[0], bb[1])
    return atlas, regions


def compact_png(img, path: str) -> None:
    from PIL import Image
    a = img.getchannel("A").point(lambda v: 0 if v < 4 else v)
    img.putalpha(a)
    q = img.convert("RGBA").quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    q.save(path, optimize=True)


IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="%s"

[params]

compress/mode=2
compress/high_quality=true
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def write_import(kind: str) -> None:
    """Compression VRAM (ASTC/BPTC) ; écrit seulement si absent (Godot complète uid et chemins)."""
    path = os.path.join(OUT_DIR, kind, "%s_atlas.png.import" % kind)
    if os.path.exists(path):
        with open(path) as f:
            if "compress/mode=2" in f.read():
                return
    with open(path, "w") as f:
        f.write(IMPORT_TEMPLATE % ("res://assets/sprites/enemies/%s/%s_atlas.png" % (kind, kind)))


def write_tres(kind: str, anims: dict, regions: dict, frame: int, meta: dict) -> None:
    rd = "res://assets/sprites/enemies/%s/" % kind
    total = sum(n for n, _f, _l in anims.values()) * len(DIRS)
    lines = ['[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (2 + total), "",
             '[ext_resource type="Texture2D" path="%s%s_atlas.png" id="1_atlas"]' % (rd, kind), ""]
    out = []
    for anim, (n, fps, loop) in anims.items():
        for d in DIRS:
            ids = []
            for c in range(n):
                sid = "A_%s_%s_%d" % (anim, d, c)
                x, y, w, h, ox, oy = regions[(anim, d, c)]
                ids.append(sid)
                lines.append('[sub_resource type="AtlasTexture" id="%s"]' % sid)
                lines.append('atlas = ExtResource("1_atlas")')
                lines.append("region = Rect2(%d, %d, %d, %d)" % (x, y, w, h))
                lines.append("margin = Rect2(%d, %d, %d, %d)" % (ox, oy, frame - w, frame - h))
                lines.append("filter_clip = true")
                lines.append("")
            fr = ", ".join('{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % s for s in ids)
            out.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s_%s",\n"speed": %.1f\n}'
                       % (fr, "true" if loop else "false", anim, d, float(fps)))
    lines.append("[resource]")
    lines.append("animations = [%s]" % ", ".join(out))
    lines.append("metadata/enemy_meta = %s" % json.dumps(meta, ensure_ascii=False))
    with open(os.path.join(OUT_DIR, kind, "%s_frames.tres" % kind), "w") as f:
        f.write("\n".join(lines) + "\n")


def measure(im) -> tuple:
    return im.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()


def set_dir(model, d: str) -> None:
    model.dir_ang = DIRS[d]
    model.j["root"].rotation_euler = (0, 0, math.radians(DIRS[d]))


def build_kind(kind: str, make_model) -> None:
    """Rend toutes les animations dans les 8 directions et écrit atlas + SpriteFrames + méta."""
    t0 = time.time()
    C.reset_scene()
    model = make_model(kind)
    frame = model.frame
    cam = setup_camera(frame, model.cam_z, model.outline_px)
    anims = model.anims()
    od = os.path.join(OUT_DIR, kind)
    os.makedirs(od, exist_ok=True)
    tmp = os.path.join(TMP_DIR, kind)
    os.makedirs(tmp, exist_ok=True)
    feet = C.world_to_px(cam, (0, 0, 0))
    feet = (round(feet[0] / SS), round(feet[1] / SS))
    frames, order, muzzle = {}, [], {}
    for d in DIRS:
        set_dir(model, d)
        for anim, (n, _f, _l) in anims.items():
            for i in range(n):
                model.pose(anim, i, n)
                frames[(anim, d, i)] = render_frame(os.path.join(tmp, "%s_%s_%d.png" % (anim, d, i)), frame)
                order.append((anim, d, i))
                if anim == "attack" and i == 3:
                    muzzle[d] = to_px(cam, model.muzzle_world())
        print(kind, "DIR", d, "%.0fs" % (time.time() - t0), flush=True)
    atlas, regions = pack(frames, order, frame)
    compact_png(atlas, os.path.join(od, "%s_atlas.png" % kind))
    write_import(kind)
    bb = measure(frames[("idle", "s", 0)])
    corpse = {}
    for d in DIRS:
        cb = measure(frames[("death", d, anims["death"][0] - 1)])
        corpse[d] = [cb[0], cb[1], cb[2], cb[3]]
    meta = {
        "kind": kind,
        "name": model.name,
        "frame_size": [frame, frame],
        "feet_offset": [feet[0], feet[1]],
        "display_height": round(frame * WORLD_PER_PX, 1),
        "world_per_px": WORLD_PER_PX,
        "height_px": bb[3] - bb[1],
        "head_px": bb[1],
        "fps": {a: f for a, (_n, f, _l) in anims.items()},
        "frames": {a: n for a, (n, _f, _l) in anims.items()},
        "loop": {a: lp for a, (_n, _f, lp) in anims.items()},
        "directions": list(DIRS.keys()),
        "attack_hold_frame": 2,
        "attack_strike_frame": 3,
        "muzzle_px": muzzle,
        "corpse_bbox_px": corpse,
        "atlas": "res://assets/sprites/enemies/%s/%s_atlas.png" % (kind, kind),
        "source": "art/blender/bestiary/far_west/build_fw_bestiary.py",
        "notes": "display_height = hauteur du cadre (frame_size.y px) en unités monde ; scale = "
                 "display_height / frame_size.y. feet_offset = pieds (px depuis le coin haut-gauche du cadre). "
                 "attack : 0-2 élan (2 tenue pendant le télégraphe), 3 coup/tir, 4-5 retour. death : la "
                 "dernière image est le cadavre au sol. muzzle_px = bout du canon / de la gueule (image attack 3).",
    }
    with open(os.path.join(od, "%s_meta.json" % kind), "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
        f.write("\n")
    write_tres(kind, anims, regions, frame, meta)
    print("DONE", kind, "%.0fs" % (time.time() - t0), "atlas", atlas.size, flush=True)


def preview(kind: str, make_model, dirs: list, anims_spec: list, out: str | None = None) -> str:
    """Bande d'images (fond sable) pour vérifier un modèle sans tout rendre."""
    from PIL import Image
    C.reset_scene()
    model = make_model(kind)
    frame = model.frame
    setup_camera(frame, model.cam_z, model.outline_px)
    tiles = []
    for d in dirs:
        set_dir(model, d)
        for a in anims_spec:
            an, i = a.split(":")
            n = model.anims()[an][0]
            model.pose(an, int(i), n)
            tiles.append(render_frame(os.path.join(TMP_DIR, "prev_%s_%s_%s_%s.png" % (kind, an, d, i)), frame))
    sheet = Image.new("RGBA", (frame * len(tiles), frame), (216, 170, 120, 255))
    for k, t in enumerate(tiles):
        sheet.alpha_composite(t, (k * frame, 0))
    out = out or os.path.join(TMP_DIR, "prev_%s.png" % kind)
    sheet.save(out)
    print("PREVIEW", out, flush=True)
    return out
