"""Plan de village écrit à la main imitant la maquette (docs/reference/farwest_maquette_carte.png),
au format JSON de export_layout.gd. Sert à caler le rendu Blender (fw_scene.py) avant que le
générateur ne produise ses plans. Grille : 48 colonnes × 104 rangées (maquette vue à ~35°).
Usage : python3 maquette_layout.py <out.json>
"""
import json, sys, random

W, H = 48, 104
T = [[1] * W for _ in range(H)]          # tout en rue (STREET)
B = []
def bld(arch, rect, roof="tin_blue", stories=1, porch="S", door=None, name=""):
    x, y, w, h = rect
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            edge = xx in (x, x + w - 1) or yy in (y, y + h - 1)
            T[yy][xx] = 3 if edge else 2
    dx = door if door is not None else x + w // 2
    dc = [dx, y + h - 1] if porch != "N" else [dx, y]
    T[dc[1]][dc[0]] = 4
    B.append({"id": len(B), "arch": arch, "name": name or arch, "rect": [x, y, w, h],
              "doors": [{"cell": dc, "vertical": False, "outside": True}],
              "roof_style": roof, "stories": stories, "porch_side": porch})

# --- moitié nord (au-dessus de la voie ferrée) — relevé sur la maquette (grille 48 colonnes)
bld("store",   [21, 9, 10, 8], "tin_blue", 1, "S")
bld("house",   [9, 15, 7, 9], "tin_blue", 1, "S")
bld("house",   [15, 13, 6, 9], "plank", 1, "S")
bld("house",   [31, 13, 7, 10], "tin_blue", 1, "S")
bld("shack",   [22, 25, 7, 5], "tin_grey", 1, "S")
bld("house",   [33, 27, 5, 13], "tin_grey", 1, "S")
bld("saloon",  [38, 27, 7, 9], "red", 2, "S")
bld("shack",   [37, 36, 5, 4], "plank", 1, "S")
bld("house",   [6, 29, 6, 9], "shingle", 1, "S")
bld("house",   [12, 28, 5, 12], "plank", 1, "S")
bld("shack",   [3, 31, 3, 11], "tin_blue", 1, "E")
bld("stable",  [4, 40, 5, 18], "plank", 1, "E")
bld("shack",   [14, 43, 4, 6], "tin_blue", 1, "S")
bld("shack",   [11, 48, 5, 5], "plank", 1, "S")
bld("shack",   [11, 53, 5, 5], "tin_blue", 1, "S")
bld("hotel",   [34, 47, 7, 12], "tin_blue", 1, "S")
bld("shack",   [31, 49, 3, 7], "plank", 1, "W")
bld("ruin",    [16, 4, 4, 4], "plank", 1, "S")
# --- moitié sud
bld("sheriff", [9, 74, 11, 9], "tin_rust", 1, "S")
bld("house",   [26, 85, 6, 6], "tin_blue", 1, "S")
bld("shack",   [32, 85, 4, 5], "plank", 1, "S")
bld("ruin",    [42, 71, 5, 6], "plank", 1, "S")
bld("ruin",    [37, 80, 4, 6], "plank", 1, "S")
bld("ruin",    [16, 89, 3, 4], "plank", 1, "S")
decks = [[9, 43, 3, 15], [5, 25, 6, 3], [21, 17, 6, 2], [23, 86, 3, 12], [16, 16, 4, 6], [29, 40, 4, 4],
         [28, 51, 3, 6], [20, 74, 3, 7], [41, 37, 4, 4], [9, 83, 9, 3], [27, 91, 9, 4], [31, 23, 6, 3]]

fences = [
    [[8, 24], [8, 28], [16, 28]], [[17, 22], [21, 22], [21, 27]], [[29, 40], [33, 40], [33, 45]],
    [[18, 44], [22, 44], [22, 50]], [[41, 36], [46, 36], [46, 42]], [[27, 51], [27, 58]],
    [[19, 73], [19, 82], [23, 82]], [[25, 91], [25, 96]], [[36, 91], [36, 96]], [[2, 71], [2, 85]],
    [[20, 5], [32, 5]], [[8, 13], [8, 27]], [[8, 13], [15, 13]], [[30, 24], [31, 24]], [[38, 23], [38, 26]],
    [[2, 28], [2, 44]], [[17, 40], [17, 47]], [[30, 44], [42, 44], [42, 47]], [[30, 59], [41, 59]],
    [[8, 83], [8, 87], [21, 87], [21, 72]], [[25, 92], [36, 92]], [[39, 70], [46, 70]], [[36, 79], [36, 87]],
    [[1, 62], [1, 66]], [[19, 62], [19, 66]],
    [[19, 6], [31, 6], [31, 10]], [[19, 6], [19, 10]],
    [[37, 12], [41, 12], [41, 22]],
    [[6, 23], [6, 27], [15, 27]],
    [[12, 61], [15, 61]], [[18, 61], [21, 61]], [[24, 61], [27, 61]], [[31, 61], [34, 61]], [[38, 61], [41, 61]],
    [[1, 66], [1, 80]], [[1, 72], [6, 72]], [[1, 80], [6, 80]],
    [[46, 64], [46, 72]],
    [[9, 86], [17, 86], [17, 84]], [[20, 72], [20, 74]],
    [[38, 79], [45, 79], [45, 86]], [[38, 86], [41, 86]],
    [[26, 92], [26, 96], [35, 96], [35, 92]],
    [[19, 85], [19, 95]],
]
rocks = []
def rk(cells_rect, height):
    x, y, w, h = cells_rect
    cells = [[xx, yy] for yy in range(y, y + h) for xx in range(x, x + w)
             if ((xx - x - (w - 1) / 2) / (w / 2)) ** 2 + ((yy - y - (h - 1) / 2) / (h / 2)) ** 2 <= 1.15]
    rocks.append({"cells": cells, "height": height})
rk([21, 0, 9, 5], 2.2); rk([1, 13, 6, 8], 3.2); rk([40, 14, 4, 6], 2.2); rk([45, 18, 3, 5], 1.8)
rk([0, 52, 3, 6], 1.8); rk([0, 85, 8, 9], 3.4); rk([1, 95, 6, 7], 2.6); rk([9, 90, 7, 8], 3.2)
rk([41, 86, 7, 8], 3.4); rk([43, 94, 5, 6], 2.8); rk([33, 96, 6, 7], 2.6); rk([43, 100, 4, 4], 1.6); rk([36, 5, 4, 3], 1.2)

props = []
for d in []:
    pass
def p(kind, x, y, rot=0.0, size=(1, 1)):
    props.append({"kind": kind, "cell": [x, y], "rot": rot, "size": list(size)})
for (x, y, r, k) in [(26, 20, 0.3, "wagon"), (31, 34, 1.57, "cart"), (26, 47, 1.65, "cart"), (21, 52, 1.5, "cart"),
                     (45, 51, 1.2, "wagon"), (28, 77, 1.57, "wagon"), (33, 81, 1.57, "wagon"), (5, 100, 0.6, "wagon"),
                     (27, 56, 1.57, "covered_wagon"), (40, 76, 0.4, "cart"), (17, 87, 1.57, "mine_cart"), (22, 93, 1.57, "mine_cart"),
                     (13, 63, 0.0, "cart"), (38, 63, 0.1, "wagon"), (29, 31, 1.57, "cart"), (17, 32, 1.4, "wagon"), (8, 66, 1.57, "cart"),
                     (44, 57, 1.3, "wagon"), (27, 98, 0.3, "cart"), (35, 76, 1.57, "cart")]:
    p(k, x, y, r)
for (x, y) in [(23, 7), (27, 7), (17, 23), (16, 25), (29, 18), (36, 24), (35, 41), (14, 41), (17, 41), (22, 43), (9, 60), (17, 56),
               (30, 58), (41, 48), (21, 75), (37, 72), (38, 73), (2, 75), (4, 76), (28, 92), (34, 92), (13, 84), (24, 23), (19, 37),
               (42, 39), (44, 30), (29, 41), (19, 47), (19, 53), (8, 25), (3, 63), (44, 64), (16, 70), (29, 71), (31, 76), (24, 79),
               (36, 92), (30, 92), (12, 86), (42, 81), (45, 75), (2, 68), (6, 64)]:
    p(random.Random(x * 99 + y).choice(["barrel", "crate_stack", "barrel", "sacks", "crate_stack", "hay_bale"]), x, y)
for (x, y) in [(42, 22), (40, 30), (31, 25), (8, 37), (18, 47), (21, 63), (30, 63), (44, 62), (25, 70), (40, 72), (45, 80)]:
    p("water_trough" if (x % 3) == 0 else "hitching_post", x, y)
for (x, y) in [(9, 9), (2, 21), (2, 79), (45, 25), (44, 46), (3, 47), (30, 31), (47, 34), (15, 101), (24, 103), (45, 68), (38, 92)]:
    p("tree" if (x + y) % 3 else "joshua", x, y)
rng = random.Random(7)
for _ in range(70):
    x, y = rng.randrange(W), rng.randrange(H)
    if T[y][x] == 1:
        p(rng.choice(["cactus", "shrub", "shrub", "grass", "grass", "tumbleweed"]), x, y)

paths = set()
def road(a, b, wdt=2):
    (x0, y0), (x1, y1) = a, b
    for x in range(min(x0, x1), max(x0, x1) + 1):
        for k in range(wdt):
            paths.add((x, y0 + k))
    for y in range(min(y0, y1), max(y0, y1) + 1):
        for k in range(wdt):
            paths.add((x1 + k, y))
road((17, 24), (30, 24)); road((22, 18), (22, 60)); road((16, 38), (33, 38)); road((25, 42), (25, 64)); road((10, 70), (40, 70), 2)
road((28, 64), (28, 84)); road((12, 59), (40, 59)); road((24, 38), (24, 40)); road((20, 70), (20, 100), 3)
paths = [[x, y] for (x, y) in paths if 0 <= x < W and 0 <= y < H and T[y][x] == 1]

rails = [[x, 67] for x in range(W)]
mine_rails = [[22, y] for y in range(86, 101)]
train = [{"kind": "boxcar", "rect": [12, 66, 5, 3]}, {"kind": "boxcar_b", "rect": [17, 66, 4, 3]},
         {"kind": "boxcar_dark", "rect": [21, 66, 3, 3]}, {"kind": "tankcar", "rect": [24, 66, 6, 3]},
         {"kind": "tender", "rect": [30, 66, 4, 3]}, {"kind": "loco_rev", "rect": [34, 66, 5, 3]}]
landmarks = [{"kind": "windmill", "rect": [3, 6, 3, 3]}, {"kind": "water_tower", "rect": [40, 8, 4, 4]},
             {"kind": "well", "rect": [22, 38, 3, 3]}, {"kind": "windmill_small", "rect": [43, 42, 2, 2]}]
for lm in landmarks + train:
    x, y, w, h = lm["rect"]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            T[yy][xx] = 3
for (x, y, w, h) in decks:
    props.append({"kind": "deck", "cell": [x, y], "rot": 0.0, "size": [w, h]})
for c in mine_rails:
    props.append({"kind": "mine_rail", "cell": c, "rot": 0.0, "size": [1, 1]})
out = {"seed": 4242, "size": [W, H], "tile": 64, "tiles": ["".join(str(c) for c in r) for r in T],
       "buildings": B, "rooms": [], "doors": [], "paths": paths, "fences": fences, "rock_formations": rocks,
       "props": props, "rails": rails, "train": train, "landmarks": landmarks,
       "landmark_spawns": [], "prop_spawns": [], "decor_spawns": [], "container_spawns": [], "player_spawn": [24, 44]}
json.dump(out, open(sys.argv[1], "w"))
print("layout", W, H, len(B), "buildings", len(props), "props")
