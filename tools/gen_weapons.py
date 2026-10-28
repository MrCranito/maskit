#!/usr/bin/env python3
"""Générateur du catalogue d'armes d'Exfil Rush.

Produit, à partir des tableaux ci-dessous :
  - data/weapons/<id>.tres       (WeaponData)
  - data/items/wpn_<id>.tres     (ItemData type weapon, une par arme sauf le pistolet de départ)
  - les entrées d'armes des tables data/loot_tables/*.tres (poids par rareté et par palier de table)

Les valeurs d'équilibrage vivent dans les .tres générés (pas dans le code du jeu).
Relancer après modification :  python3 tools/gen_weapons.py
Catalogue = la planche docs/reference/arsenal.jpg (18 armes + 5 équipements). Le script
remplace tout : les .tres d'armes absents du tableau et leurs objets wpn_* sont supprimés.
Le pistolet de départ (pistol_p9) n'a pas d'objet wpn_ (LootDB.weapon_item le crée au besoin).
Javelin : guidage = affixe « homing » (champ `affixes`, interprété par le projectile/joueur).
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEAPON_DIR = os.path.join(ROOT, "data", "weapons")
ITEM_DIR = os.path.join(ROOT, "data", "items")
TABLE_DIR = os.path.join(ROOT, "data", "loot_tables")

# --- Catalogue = EXACTEMENT la planche docs/reference/arsenal.jpg (contrat « Refonte n°2 »).
# sprite_id = id. Stats explicites par arme (pas de multiplicateur caché) : la rareté apporte un
# gain net au sein d'une catégorie (DPS, chargeur, rechargement, précision).
# Champs omis = valeurs par défaut de CATEGORY_DEFAULTS.
CATEGORY_DEFAULTS = {
    "pistol": dict(projectile_speed=950, range=560, inaccuracy_deg=2.0, automatic=False, recoil_px=4,
                   shake_px=1.6, muzzle_flash_scale=0.8, projectile_style="bullet", color=(1.0, 0.82, 0.4), weight=1.0),
    "smg": dict(projectile_speed=900, range=480, inaccuracy_deg=6.0, automatic=True, recoil_px=3, shake_px=1.2,
                muzzle_flash_scale=0.7, projectile_style="bullet", color=(1.0, 0.86, 0.5), weight=2.2),
    "rifle": dict(projectile_speed=1150, range=680, inaccuracy_deg=3.0, automatic=True, recoil_px=4.5, shake_px=1.8,
                  muzzle_flash_scale=1.0, projectile_style="bullet", color=(1.0, 0.84, 0.45), weight=3.4),
    "sniper": dict(projectile_speed=1900, range=1100, inaccuracy_deg=0.0, pierce=1, automatic=False, recoil_px=12,
                   shake_px=5.0, muzzle_flash_scale=1.5, move_speed_mult=0.92, projectile_style="tracer",
                   color=(0.7, 0.95, 1.0), weight=4.5),
    "rocket_launcher": dict(projectile_speed=520, range=820, inaccuracy_deg=0.5, automatic=False, recoil_px=14,
                            shake_px=9.0, muzzle_flash_scale=1.8, move_speed_mult=0.85, eject_shells=False,
                            projectile_style="rocket", color=(1.0, 0.55, 0.2), weight=6.0),
    "gadget": dict(projectile_speed=520, range=420, inaccuracy_deg=0.0, automatic=False, recoil_px=0, shake_px=0,
                   muzzle_flash_scale=0.0, eject_shells=False, projectile_style="grenade", color=(0.6, 1.0, 0.4),
                   weight=0.6, magazine_size=1, reload_time=0.0, fire_rate=1.0, damage=0.0),
}

# (id, catégorie, rareté, nom, description, stats)
WEAPONS = [
    # Pistolets
    ("pistol_p9", "pistol", 0, "P9", "Petit pistolet de départ : léger, fiable, sans surprise.",
     dict(damage=12, fire_rate=3.2, magazine_size=10, reload_time=1.0, value=20)),
    ("pistol_glock18", "pistol", 2, "Glock 18", "Sélecteur en rafale : une pluie de 9 mm en automatique.",
     dict(damage=11, fire_rate=9.0, magazine_size=19, reload_time=1.2, automatic=True, inaccuracy_deg=5.0, recoil_px=3, value=260)),
    ("pistol_deagle", "pistol", 3, "Desert Eagle", "Gros calibre .50 : chaque balle compte, le recul aussi.",
     dict(damage=46, fire_rate=2.0, magazine_size=7, reload_time=1.4, inaccuracy_deg=1.5, pierce=1, recoil_px=9,
          shake_px=3.5, muzzle_flash_scale=1.3, projectile_speed=1100, value=620)),
    ("pistol_p320", "pistol", 4, "P320", "Le pistolet des pros : précis, rapide, chargeur généreux.",
     dict(damage=30, fire_rate=4.6, magazine_size=17, reload_time=0.9, inaccuracy_deg=0.8, pierce=1, range=620, value=1300)),
    # Mitraillettes
    ("smg_mp5", "smg", 0, "MP5", "La mitraillette équilibrée par excellence.",
     dict(damage=8, fire_rate=10.0, magazine_size=30, reload_time=1.6, value=70)),
    ("smg_vector", "smg", 2, "Vector", "Cadence énorme : vide son chargeur en un clin d'œil.",
     dict(damage=8, fire_rate=18.0, magazine_size=25, reload_time=1.4, inaccuracy_deg=6.5, recoil_px=2.5, value=300)),
    ("smg_p90", "smg", 3, "P90", "Chargeur de 50 coups sur le dessus : on arrose longtemps.",
     dict(damage=10.5, fire_rate=14.0, magazine_size=50, reload_time=1.9, inaccuracy_deg=4.5, value=650)),
    ("smg_uzi", "smg", 4, "Uzi", "Légende compacte : cadence folle, balles perforantes.",
     dict(damage=12.5, fire_rate=16.0, magazine_size=40, reload_time=1.2, inaccuracy_deg=4.0, pierce=1, value=1400)),
    # Fusils d'assaut
    ("rifle_ak47", "rifle", 0, "AK-47", "Gros dégâts, gros recul : il faut le tenir.",
     dict(damage=17, fire_rate=6.0, magazine_size=30, reload_time=2.0, inaccuracy_deg=4.5, recoil_px=6, shake_px=2.4, value=90)),
    ("rifle_m4a1", "rifle", 2, "M4A1", "Précis et maniable : la rafale reste groupée.",
     dict(damage=16, fire_rate=8.0, magazine_size=30, reload_time=1.6, inaccuracy_deg=1.5, recoil_px=3.5, range=720, value=420)),
    ("rifle_scarh", "rifle", 3, "SCAR-H", "Calibre lourd 7,62 : traverse une première cible.",
     dict(damage=26, fire_rate=6.0, magazine_size=20, reload_time=1.9, inaccuracy_deg=2.5, pierce=1, recoil_px=6.5,
          shake_px=2.8, move_speed_mult=0.95, range=760, value=880)),
    ("rifle_aug", "rifle", 4, "AUG", "Bullpup légendaire : cadence, précision et perforation.",
     dict(damage=24, fire_rate=9.0, magazine_size=42, reload_time=1.5, inaccuracy_deg=1.2, pierce=1, range=780, value=1900)),
    # Fusils de sniper
    ("sniper_m24", "sniper", 0, "M24", "Fusil à verrou : un tir, un rechargement de culasse.",
     dict(damage=75, fire_rate=0.75, magazine_size=5, reload_time=2.6, value=110)),
    ("sniper_ax50", "sniper", 2, "AX-50", "Calibre .50 à verrou : coupe la meute en deux.",
     dict(damage=125, fire_rate=0.7, magazine_size=5, reload_time=2.8, pierce=2, recoil_px=14, shake_px=6, value=520)),
    ("sniper_m82", "sniper", 3, "Barrett M82", "Semi-automatique .50 : perforation massive, cadence soutenue.",
     dict(damage=120, fire_rate=1.3, magazine_size=10, reload_time=2.6, pierce=3, recoil_px=13, shake_px=6.5,
          move_speed_mult=0.88, value=1150)),
    # Lance-roquettes
    ("rocket_rpg7", "rocket_launcher", 2, "RPG-7", "Une roquette, une explosion. Rechargement après chaque tir.",
     dict(damage=35, fire_rate=0.6, magazine_size=1, reload_time=2.4, explosion_radius=120, explosion_damage=110, value=600)),
    ("rocket_m202", "rocket_launcher", 3, "M202", "Quatre tubes : quatre roquettes tirées coup sur coup.",
     dict(damage=30, fire_rate=2.4, magazine_size=4, reload_time=3.4, explosion_radius=100, explosion_damage=80,
          inaccuracy_deg=2.5, value=1300)),
    ("rocket_javelin", "rocket_launcher", 4, "Javelin", "Missile guidé léger : file vers l'ennemi le plus proche du viseur.",
     dict(damage=45, fire_rate=0.9, magazine_size=1, reload_time=2.0, explosion_radius=110, explosion_damage=150,
          projectile_speed=600, range=1000, move_speed_mult=0.9, affixes=["homing"], value=2600)),
    # Autres (équipement : emplacement gadget)
    ("gadget_frag", "gadget", 0, "Grenade frag", "Lancée en cloche, explose après une courte mèche.",
     dict(gadget_kind="frag", charges=3, throw_range=420, fuse_time=1.6, explosion_radius=120, explosion_damage=95,
          effect_radius=120, projectile_style="grenade", value=60)),
    ("gadget_smoke", "gadget", 2, "Grenade fumigène", "Un nuage épais qui aveugle ennemis et tourelles.",
     dict(gadget_kind="smoke", charges=2, throw_range=440, fuse_time=0.8, effect_radius=170, effect_duration=8.0,
          projectile_style="grenade", color=(0.85, 0.88, 0.95), value=280)),
    ("gadget_mine", "gadget", 3, "Mine", "Posée au sol, s'arme puis explose au passage d'un ennemi.",
     dict(gadget_kind="mine", charges=2, throw_range=60, fuse_time=1.2, effect_radius=70, explosion_radius=140,
          explosion_damage=160, effect_duration=120.0, projectile_style="grenade", color=(1.0, 0.35, 0.25), value=640)),
    ("gadget_c4", "gadget", 4, "C4", "Posé où tu veux, déclenché à distance : la pièce entière saute.",
     dict(gadget_kind="c4", charges=1, throw_range=80, fuse_time=0.0, explosion_radius=210, explosion_damage=320,
          effect_radius=210, projectile_style="grenade", color=(1.0, 0.25, 0.2), value=1500)),
    ("gadget_drone", "gadget", 4, "Drone", "Allié volant qui te suit et mitraille l'ennemi le plus proche.",
     dict(gadget_kind="drone", charges=1, throw_range=0, fuse_time=0.0, effect_radius=420, effect_duration=25.0,
          damage=9, fire_rate=5.0, projectile_speed=900, projectile_style="bullet", color=(0.5, 0.9, 1.0),
          weight=1.5, value=1600)),
]
STARTER_ID = "pistol_p9"

# --- Tables de butin : poids d'une arme selon sa rareté et le palier de la table -------
TIER_WEIGHTS = {
    "rich": [1.0, 0.7, 0.4, 0.15, 0.04],         # coffres, coffres-forts, armureries
    "medium": [0.25, 0.15, 0.08, 0.025, 0.006],  # caisses, chariots, cadavres, casiers
    "enemy": [0.12, 0.06, 0.025, 0.006, 0.0012], # sacoches d'ennemis (rare)
}
# Équipement : plutôt caisses militaires / coffres (multiplicateur appliqué aux gadgets).
GADGET_MULT = {"rich": 1.6, "medium": 0.5, "enemy": 0.6}
MILITARY_TABLES = {"crate", "wagon", "cargo_crate", "armory_chest", "locker", "uw_locker", "uw_crate", "safe", "chest"}
TABLE_TIERS = {
    # Far West
    "chest": ("rich", 1.0), "safe": ("rich", 1.2), "stagecoach": ("medium", 1.5),
    "crate": ("medium", 1.0), "wagon": ("medium", 1.2), "corpse": ("medium", 1.3), "wardrobe": ("medium", 0.8),
    "enemy": ("enemy", 1.0),
    # Station spatiale
    "armory_chest": ("rich", 1.6), "cargo_crate": ("medium", 1.0), "locker": ("medium", 1.0),
    "cryo_pod": ("medium", 0.6), "enemy_space_station": ("enemy", 1.0),
    # Centre commercial
    "mall_jewel_safe": ("rich", 0.8), "mall_stock_box": ("medium", 0.8), "mall_corpse": ("medium", 1.3),
    "enemy_mall": ("enemy", 1.0),
    # Station sous-marine
    "uw_sample_chest": ("rich", 0.8), "uw_locker": ("medium", 1.2), "uw_crate": ("medium", 1.0),
    "uw_diver_corpse": ("medium", 1.3), "enemy_underwater": ("enemy", 1.0),
}
# Objets retirés de toutes les tables (masques, anciennes armes sans weapon_id).
REMOVED_ITEMS = {"mask_fox", "mask_iron", "mask_robber", "mask_skull", "space_cracked_mask",
                 "winchester", "colt_revolver", "golden_revolver", "bowie_knife"}

INT_FIELDS = {"magazine_size", "projectile_count", "pierce"}


def fmt_float(v: float) -> str:
    v = round(float(v), 3)
    s = ("%.3f" % v).rstrip("0").rstrip(".")
    return s + ".0" if "." not in s else s


def build_stats(cat: str, rarity: int, adj: dict) -> dict:
    st = {"projectile_count": 1, "spread_degrees": 0.0, "pierce": 0, "explosion_radius": 0.0,
          "explosion_damage": 0.0, "move_speed_mult": 1.0, "eject_shells": True, "affixes": [],
          "gadget_kind": "", "charges": 0, "throw_range": 0.0, "fuse_time": 0.0, "effect_radius": 0.0,
          "effect_duration": 0.0}
    st.update(CATEGORY_DEFAULTS[cat])
    st.update(adj)
    st["slot"] = "gadget" if cat == "gadget" else "weapon"
    st["projectile_lifetime"] = round(float(st["range"]) / max(float(st["projectile_speed"]), 1.0), 3)
    return st


def color_str(c) -> str:
    r, g, b = c
    return "Color(%s, %s, %s, 1)" % (fmt_float(r), fmt_float(g), fmt_float(b))


def weapon_tres(wid, cat, rarity, name, desc, st) -> str:
    aff = ", ".join('&"%s"' % a for a in st["affixes"])
    lines = [
        '[gd_resource type="Resource" script_class="WeaponData" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/combat/weapon_data.gd" id="1_wdata"]',
        "",
        "[resource]",
        'script = ExtResource("1_wdata")',
        'id = &"%s"' % wid,
        'display_name = "%s"' % name.replace('"', '\\"'),
        'description = "%s"' % desc.replace('"', '\\"'),
        'family = "%s"' % ("gadget" if st["slot"] == "gadget" else "firearm"),
        'category = &"%s"' % cat,
        "rarity = %d" % rarity,
        'slot = &"%s"' % st["slot"],
        'gadget_kind = &"%s"' % st["gadget_kind"],
        "charges = %d" % st["charges"],
        "throw_range = %s" % fmt_float(st["throw_range"]),
        "fuse_time = %s" % fmt_float(st["fuse_time"]),
        "effect_radius = %s" % fmt_float(st["effect_radius"]),
        "effect_duration = %s" % fmt_float(st["effect_duration"]),
        "damage = %s" % fmt_float(st["damage"]),
        "fire_rate = %s" % fmt_float(st["fire_rate"]),
        "projectile_speed = %s" % fmt_float(st["projectile_speed"]),
        "range = %s" % fmt_float(st["range"]),
        "projectile_lifetime = %s" % fmt_float(st["projectile_lifetime"]),
        "projectile_count = %d" % st["projectile_count"],
        "spread_degrees = %s" % fmt_float(st["spread_degrees"]),
        "inaccuracy_deg = %s" % fmt_float(st["inaccuracy_deg"]),
        "pierce = %d" % st["pierce"],
        "projectile_color = %s" % color_str(st["color"]),
        'projectile_style = &"%s"' % st["projectile_style"],
        "affixes = Array[StringName]([%s])" % aff,
        "magazine_size = %d" % st["magazine_size"],
        "reload_time = %s" % fmt_float(st["reload_time"]),
        "automatic = %s" % ("true" if st["automatic"] else "false"),
        "explosion_radius = %s" % fmt_float(st["explosion_radius"]),
        "explosion_damage = %s" % fmt_float(st["explosion_damage"]),
        "recoil_px = %s" % fmt_float(st["recoil_px"]),
        "shake_px = %s" % fmt_float(st["shake_px"]),
        "move_speed_mult = %s" % fmt_float(st["move_speed_mult"]),
        "muzzle_flash_scale = %s" % fmt_float(st["muzzle_flash_scale"]),
        "eject_shells = %s" % ("true" if st["eject_shells"] else "false"),
        'sprite_id = &"%s"' % wid,
        "value = %d" % st["value"],
        "",
    ]
    return "\n".join(lines)


def item_tres(wid, name, desc, rarity, st) -> str:
    lines = [
        '[gd_resource type="Resource" script_class="ItemData" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/loot/item_data.gd" id="1_item"]',
        "",
        "[resource]",
        'script = ExtResource("1_item")',
        'id = &"wpn_%s"' % wid,
        'display_name = "%s"' % name.replace('"', '\\"'),
        'description = "%s"' % desc.replace('"', '\\"'),
        "tint = Color(1, 1, 1, 1)",
        "rarity = %d" % rarity,
        'type = &"weapon"',
        "stack_max = 1",
        "value = %d" % st["value"],
        "weight = %s" % fmt_float(st["weight"]),
        "drop_min = 1",
        "drop_max = 1",
        "heal_amount = 0.0",
        'weapon_id = &"%s"' % wid,
        "",
    ]
    return "\n".join(lines)


ENTRY_RE = re.compile(r'^&"([^"]+)":\s*([0-9.eE+-]+),?\s*$')


def patch_table(path: str, kind: str) -> None:
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"entries = \{\n(.*?)\n\}", text, re.S)
    if m is None:
        print("  ! table sans entries :", path)
        return
    entries: dict[str, float] = {}
    for line in m.group(1).splitlines():
        mm = ENTRY_RE.match(line.strip())
        if mm:
            entries[mm.group(1)] = float(mm.group(2))
    for k in list(entries):
        if k in REMOVED_ITEMS or k.startswith("wpn_") or "mask" in k:
            del entries[k]
    if kind in TABLE_TIERS:
        tier, mult = TABLE_TIERS[kind]
        for (wid, cat, rarity, *_rest) in WEAPONS:
            if wid == STARTER_ID:
                continue
            w = TIER_WEIGHTS[tier][rarity] * mult
            if cat == "gadget":
                w *= GADGET_MULT[tier] * (1.5 if kind in MILITARY_TABLES else 1.0)
            if w > 0.0:
                entries["wpn_" + wid] = round(w, 4)
    body = ",\n".join('&"%s": %s' % (k, fmt_float(entries[k]) if entries[k] >= 0.001 else repr(entries[k]))
                      for k in sorted(entries))
    text = text[: m.start()] + "entries = {\n" + body + "\n}" + text[m.end():]
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


OLD_WEAPON_DIR_KEEP = set()


def main() -> int:
    ids = [w[0] for w in WEAPONS]
    if len(set(ids)) != len(ids) or STARTER_ID not in ids:
        print("! ids en double ou arme de départ absente")
        return 1
    for (wid, cat, *_r) in WEAPONS:
        if cat not in CATEGORY_DEFAULTS:
            print("! catégorie inconnue :", wid, cat)
            return 1
    # Catalogue remplacé en entier : anciennes armes et anciens objets wpn_* supprimés.
    for f in os.listdir(WEAPON_DIR):
        if f.endswith(".tres") and f[:-5] not in ids:
            os.remove(os.path.join(WEAPON_DIR, f))
            print("  - supprimé data/weapons/" + f)
    for f in os.listdir(ITEM_DIR):
        if f.startswith("wpn_") and f.endswith(".tres") and f[4:-5] not in ids:
            os.remove(os.path.join(ITEM_DIR, f))
    for (wid, cat, rarity, name, desc, adj) in WEAPONS:
        st = build_stats(cat, rarity, adj)
        with open(os.path.join(WEAPON_DIR, wid + ".tres"), "w", encoding="utf-8") as f:
            f.write(weapon_tres(wid, cat, rarity, name, desc, st))
        item_path = os.path.join(ITEM_DIR, "wpn_" + wid + ".tres")
        if wid == STARTER_ID:
            if os.path.exists(item_path):
                os.remove(item_path)
        else:
            with open(item_path, "w", encoding="utf-8") as f:
                f.write(item_tres(wid, name, desc, rarity, st))
        dps = (st["damage"] * st["projectile_count"] + st["explosion_damage"]) * st["fire_rate"]
        print("%-16s %-16s %d  dmg %5.1f  cad %5.2f  mag %3d  dps %6.1f  %5d $" % (
            wid, cat, rarity, st["damage"], st["fire_rate"], st["magazine_size"], dps, st["value"]))
    for f in sorted(os.listdir(TABLE_DIR)):
        if f.endswith(".tres"):
            patch_table(os.path.join(TABLE_DIR, f), f[:-5])
    print("%d entrées générées." % len(WEAPONS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
