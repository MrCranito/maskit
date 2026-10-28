#!/usr/bin/env python3
"""Générateur du catalogue d'armes d'Exfil Rush.

Produit, à partir des tableaux ci-dessous :
  - data/weapons/<id>.tres       (WeaponData)
  - data/items/wpn_<id>.tres     (ItemData type weapon, une par arme sauf le pistolet de départ)
  - les entrées d'armes des tables data/loot_tables/*.tres (poids par rareté et par palier de table)

Les valeurs d'équilibrage vivent dans les .tres générés (pas dans le code du jeu).
Relancer après modification :  python3 tools/gen_weapons.py
Le pistolet de départ (starter_pistol.tres) n'est jamais réécrit.
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEAPON_DIR = os.path.join(ROOT, "data", "weapons")
ITEM_DIR = os.path.join(ROOT, "data", "items")
TABLE_DIR = os.path.join(ROOT, "data", "loot_tables")

# sprite_id autorisés (liste FIGÉE du contrat, docs/CONVENTIONS.md).
SPRITE_IDS = {
    "starter_pistol", "pistol", "pistol_heavy", "revolver", "revolver_gold", "smg", "smg_compact",
    "shotgun", "shotgun_double", "rifle", "rifle_tactical", "sniper", "sniper_heavy", "lmg",
    "rocket_launcher", "grenade_launcher",
}

# --- Gain par rareté (0 Commun … 4 Légendaire) : net mais pas absurde ----------------
DAMAGE_MULT = [1.00, 1.14, 1.30, 1.48, 1.70]
EXPLOSION_MULT = [1.00, 1.12, 1.26, 1.42, 1.62]
FIRE_RATE_MULT = [1.00, 1.04, 1.08, 1.12, 1.16]
MAG_MULT = [1.00, 1.10, 1.20, 1.30, 1.45]
RELOAD_MULT = [1.00, 0.95, 0.90, 0.85, 0.80]
INACCURACY_MULT = [1.00, 0.90, 0.80, 0.70, 0.60]
RANGE_MULT = [1.00, 1.03, 1.06, 1.09, 1.12]
VALUE_MULT = [1.0, 2.2, 5.0, 11.0, 24.0]

# --- Base de chaque catégorie (arme Commune) ------------------------------------------
# color : couleur du projectile ; weight : encombrement (kg) de l'objet dans le sac.
CATEGORY_BASE = {
    "pistol": dict(damage=13, fire_rate=3.4, projectile_speed=950, range=560, magazine_size=12, reload_time=1.0,
                   inaccuracy_deg=2.0, automatic=False, recoil_px=4, shake_px=1.6, muzzle_flash_scale=0.8,
                   projectile_style="bullet", color=(1.0, 0.82, 0.4), value=40, weight=1.0),
    "revolver": dict(damage=22, fire_rate=2.0, projectile_speed=1050, range=620, magazine_size=6, reload_time=1.5,
                     inaccuracy_deg=1.2, automatic=False, recoil_px=7, shake_px=3.0, muzzle_flash_scale=1.1,
                     projectile_style="bullet", color=(1.0, 0.78, 0.35), value=55, weight=1.2),
    "smg": dict(damage=8, fire_rate=10.0, projectile_speed=900, range=480, magazine_size=30, reload_time=1.6,
                inaccuracy_deg=7.0, automatic=True, recoil_px=3, shake_px=1.2, muzzle_flash_scale=0.7,
                projectile_style="bullet", color=(1.0, 0.86, 0.5), value=70, weight=2.2),
    "shotgun": dict(damage=9, fire_rate=1.1, projectile_speed=820, range=340, magazine_size=6, reload_time=2.2,
                    inaccuracy_deg=3.0, projectile_count=7, spread_degrees=26.0, automatic=False, recoil_px=10,
                    shake_px=5.0, muzzle_flash_scale=1.4, projectile_style="pellet", color=(1.0, 0.7, 0.3),
                    value=75, weight=3.2),
    "rifle": dict(damage=14, fire_rate=6.5, projectile_speed=1150, range=680, magazine_size=30, reload_time=1.8,
                  inaccuracy_deg=3.0, automatic=True, recoil_px=4.5, shake_px=1.8, muzzle_flash_scale=1.0,
                  projectile_style="bullet", color=(1.0, 0.84, 0.45), value=90, weight=3.4),
    "sniper": dict(damage=70, fire_rate=0.8, projectile_speed=1900, range=1100, magazine_size=5, reload_time=2.4,
                   inaccuracy_deg=0.0, pierce=2, automatic=False, recoil_px=12, shake_px=5.0, muzzle_flash_scale=1.5,
                   move_speed_mult=0.92, projectile_style="tracer", color=(0.7, 0.95, 1.0), value=110, weight=4.5),
    "lmg": dict(damage=12, fire_rate=9.0, projectile_speed=1050, range=640, magazine_size=100, reload_time=3.6,
                inaccuracy_deg=5.0, automatic=True, recoil_px=4, shake_px=2.2, muzzle_flash_scale=1.1,
                move_speed_mult=0.85, projectile_style="bullet", color=(1.0, 0.75, 0.35), value=120, weight=7.0),
    "rocket_launcher": dict(damage=30, fire_rate=0.55, projectile_speed=520, range=820, magazine_size=1,
                            reload_time=2.6, inaccuracy_deg=0.5, automatic=False, recoil_px=14, shake_px=9.0,
                            muzzle_flash_scale=1.8, move_speed_mult=0.85, eject_shells=False,
                            explosion_radius=110, explosion_damage=90, projectile_style="rocket",
                            color=(1.0, 0.55, 0.2), value=140, weight=6.0),
    "grenade_launcher": dict(damage=10, fire_rate=1.0, projectile_speed=560, range=560, magazine_size=4,
                             reload_time=2.6, inaccuracy_deg=1.5, automatic=False, recoil_px=9, shake_px=5.0,
                             muzzle_flash_scale=1.3, move_speed_mult=0.92, eject_shells=False,
                             explosion_radius=90, explosion_damage=55, projectile_style="grenade",
                             color=(0.6, 1.0, 0.4), value=120, weight=4.5),
}

# --- Catalogue : (id, catégorie, rareté, nom, sprite_id, description, ajustements) ------
WEAPONS = [
    # Pistolets
    ("pistol_9mm", "pistol", 0, "Pistolet 9 mm", "pistol", "Fiable, léger, sans surprise. Le compagnon de tous les débuts.", {}),
    ("pistol_ranger", "pistol", 1, "Ranger compact", "pistol", "Détente sèche et chargeur allongé.", {}),
    ("pistol_hammer", "pistol", 2, "Calibre .45 « Marteau »", "pistol_heavy", "Chaque balle pèse son poids. Recul franc.", {"damage": 1.25, "fire_rate": 0.8, "recoil_px": 1.5}),
    ("pistol_viper", "pistol", 3, "Vipère", "pistol", "Tir en rafale rapide : on presse, elle crache.", {"automatic": True, "fire_rate": 1.6, "damage": 0.85}),
    ("pistol_golden_eagle", "pistol", 4, "Aigle d'or", "pistol_heavy", "Pistolet lourd plaqué or. Perce une première cible.", {"damage": 1.35, "fire_rate": 0.92, "pierce": 1, "recoil_px": 1.6}),
    # Revolvers
    ("revolver_frontier", "revolver", 0, "Revolver de la frontière", "revolver", "Six coups, crosse usée. L'Ouest en a vu des milliers.", {}),
    ("revolver_peacemaker", "revolver", 1, "Peacemaker", "revolver", "Le revolver qui a « pacifié » la frontière.", {}),
    ("revolver_navy", "revolver", 2, "Colt Navy", "revolver", "Canon long, tir précis à bonne distance.", {"range": 1.15, "inaccuracy_deg": 0.5}),
    ("revolver_judge", "revolver", 3, "Le Juge doré", "revolver_gold", "Revolver plaqué or. Chaque balle rend un verdict.", {"pierce": 1}),
    ("revolver_sixth_sense", "revolver", 4, "Sixième Sens", "revolver_gold", "On dit qu'il vise tout seul. Balles perforantes.", {"pierce": 2, "fire_rate": 1.15}),
    # Mitraillettes
    ("smg_pocket", "smg", 0, "Mitraillette de poche", "smg_compact", "Petite, bruyante, imprécise. Mais quel débit !", {}),
    ("smg_wasp", "smg", 1, "Guêpe", "smg_compact", "Cadence folle, piqûres légères.", {"fire_rate": 1.15, "damage": 0.9}),
    ("smg_tactical", "smg", 2, "Mitraillette tactique", "smg", "Crosse pliante et viseur reflex : plus stable.", {"inaccuracy_deg": 0.75}),
    ("smg_hornet", "smg", 3, "Frelon", "smg", "Chargeur double et balles chemisées.", {"magazine_size": 1.4}),
    # Fusils à pompe
    ("shotgun_pump", "shotgun", 0, "Fusil à pompe", "shotgun", "Un coup, une porte qui saute. À bout portant.", {}),
    ("shotgun_double", "shotgun", 1, "Double canon", "shotgun_double", "Deux cartouches, puis on recharge. Gros impact.", {"magazine_size_abs": 2, "fire_rate": 1.3, "projectile_count_abs": 8, "reload_time": 0.7}),
    ("shotgun_riot", "shotgun", 2, "Anti-émeute", "shotgun", "Semi-automatique, chargeur tambour.", {"fire_rate": 1.3, "magazine_size": 1.35}),
    ("shotgun_dragon", "shotgun", 3, "Souffle du dragon", "shotgun_double", "Cartouches incendiaires : un cône de braise.", {"projectile_count_abs": 9, "spread_degrees": 1.15, "color": (1.0, 0.45, 0.15), "affixes": ["burn"]}),
    ("shotgun_reaper", "shotgun", 4, "Faucheuse", "shotgun", "Automatique. Ne laisse rien debout dans la pièce.", {"automatic": True, "fire_rate": 1.5, "magazine_size": 1.3}),
    # Fusils d'assaut
    ("rifle_carbine", "rifle", 0, "Carabine", "rifle", "Fusil semi-automatique robuste et polyvalent.", {"automatic": False, "fire_rate": 0.6, "damage": 1.4}),
    ("rifle_assault", "rifle", 1, "Fusil d'assaut", "rifle", "Le standard : rafales maîtrisées, bonne portée.", {}),
    ("rifle_tactical", "rifle", 2, "Fusil tactique", "rifle_tactical", "Lunette holographique et rail : précis en rafale.", {"inaccuracy_deg": 0.7}),
    ("rifle_vanguard", "rifle", 3, "Avant-garde", "rifle_tactical", "Munitions perforantes : traverse une cible.", {"pierce": 1}),
    ("rifle_steel_storm", "rifle", 4, "Tempête d'acier", "rifle_tactical", "Cadence élevée, chargeur étendu, perforation.", {"pierce": 1, "fire_rate": 1.12, "magazine_size": 1.15}),
    # Snipers
    ("sniper_hunter", "sniper", 1, "Fusil de chasse à lunette", "sniper", "Verrou manuel, lunette x4. Un tir, un trophée.", {}),
    ("sniper_marksman", "sniper", 2, "Tireur d'élite", "sniper", "Semi-automatique : enchaîne les tirs précis.", {"fire_rate": 1.4, "damage": 0.85, "magazine_size_abs": 8}),
    ("sniper_golem_breaker", "sniper", 3, "Briseur de golems", "sniper_heavy", "Calibre .50. Traverse la pierre, et ce qu'il y a derrière.", {"damage": 1.3, "pierce": 1, "fire_rate": 0.8, "move_speed_mult": 0.9}),
    ("sniper_falcon_eye", "sniper", 4, "Œil du faucon", "sniper_heavy", "Le dernier tir que l'on n'entend jamais.", {"damage": 1.25, "pierce": 2}),
    # Mitrailleuses
    ("lmg_saw", "lmg", 2, "Mitrailleuse légère", "lmg", "Bande de 100 coups. On s'installe et on arrose.", {}),
    ("lmg_hacksaw", "lmg", 3, "Scie à métaux", "lmg", "Cadence infernale, le canon rougit.", {"fire_rate": 1.2}),
    ("lmg_deluge", "lmg", 4, "Le Déluge", "lmg", "150 coups perforants. Il pleut du plomb.", {"magazine_size_abs": 150, "pierce": 1, "fire_rate": 1.08}),
    # Bazookas
    ("rocket_bazooka", "rocket_launcher", 2, "Bazooka", "rocket_launcher", "Une roquette, un trou dans le mur… et dans la meute.", {}),
    ("rocket_infernal", "rocket_launcher", 3, "Tube infernal", "rocket_launcher", "Charge thermobarique : souffle plus large.", {"explosion_radius": 1.15, "affixes": ["burn"]}),
    ("rocket_apocalypse", "rocket_launcher", 4, "Apocalypse", "rocket_launcher", "Barillet de deux roquettes. Fin de la discussion.", {"magazine_size_abs": 2, "explosion_radius": 1.1}),
    # Lance-grenades
    ("grenade_thumper", "grenade_launcher", 1, "Lance-grenades", "grenade_launcher", "Grenades à rebond qui explosent en fin de course.", {}),
    ("grenade_mortar", "grenade_launcher", 2, "Mortier de poing", "grenade_launcher", "Six grenades à barillet.", {"magazine_size_abs": 6}),
    ("grenade_fireworks", "grenade_launcher", 3, "Bouquet final", "grenade_launcher", "Tir rapide et explosions en gerbe colorée.", {"fire_rate": 1.35, "color": (1.0, 0.4, 0.85)}),
]

# --- Tables de butin : poids d'une arme selon sa rareté et le palier de la table -------
TIER_WEIGHTS = {
    "rich": [1.0, 0.7, 0.4, 0.15, 0.04],       # coffres, coffres-forts, armureries
    "medium": [0.25, 0.15, 0.08, 0.025, 0.006],  # caisses, chariots, cadavres, casiers
    "enemy": [0.12, 0.06, 0.025, 0.006, 0.0012],  # sacoches d'ennemis (rare)
}
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
    b = dict(CATEGORY_BASE[cat])
    st = {
        "damage": b["damage"] * DAMAGE_MULT[rarity],
        "fire_rate": b["fire_rate"] * FIRE_RATE_MULT[rarity],
        "projectile_speed": b["projectile_speed"],
        "range": b["range"] * RANGE_MULT[rarity],
        "projectile_count": b.get("projectile_count", 1),
        "spread_degrees": b.get("spread_degrees", 0.0),
        "inaccuracy_deg": b["inaccuracy_deg"] * INACCURACY_MULT[rarity],
        "pierce": b.get("pierce", 0),
        "magazine_size": b["magazine_size"] * MAG_MULT[rarity],
        "reload_time": b["reload_time"] * RELOAD_MULT[rarity],
        "automatic": b["automatic"],
        "explosion_radius": b.get("explosion_radius", 0.0) * (1.0 + 0.06 * rarity),
        "explosion_damage": b.get("explosion_damage", 0.0) * EXPLOSION_MULT[rarity],
        "recoil_px": b["recoil_px"],
        "shake_px": b["shake_px"],
        "move_speed_mult": b.get("move_speed_mult", 1.0),
        "muzzle_flash_scale": b["muzzle_flash_scale"],
        "eject_shells": b.get("eject_shells", True),
        "projectile_style": b["projectile_style"],
        "color": b["color"],
        "affixes": [],
    }
    for k, v in adj.items():
        if k.endswith("_abs"):
            st[k[:-4]] = v
        elif isinstance(v, bool) or isinstance(v, (tuple, list)) or k in ("color", "affixes"):
            st[k] = v
        elif k in ("pierce",):
            st[k] = st[k] + v
        elif k == "move_speed_mult":
            st[k] = v
        else:
            st[k] = st[k] * v
    # Le chargeur d'un fusil à pompe double canon ne grossit pas avec la rareté (fixé par _abs).
    st["magazine_size"] = max(1, int(round(st["magazine_size"])))
    st["projectile_count"] = max(1, int(round(st["projectile_count"])))
    st["pierce"] = int(st["pierce"])
    st["damage"] = round(st["damage"], 1)
    st["explosion_damage"] = round(st["explosion_damage"], 1)
    st["explosion_radius"] = round(st["explosion_radius"], 1)
    st["fire_rate"] = round(st["fire_rate"], 2)
    st["reload_time"] = round(st["reload_time"], 2)
    st["range"] = round(st["range"])
    st["projectile_lifetime"] = round(st["range"] / st["projectile_speed"], 3)
    st["value"] = int(round(b["value"] * VALUE_MULT[rarity] / 5.0) * 5)
    st["weight"] = b["weight"]
    return st


def color_str(c) -> str:
    r, g, b = c
    return "Color(%s, %s, %s, 1)" % (fmt_float(r), fmt_float(g), fmt_float(b))


def weapon_tres(wid, cat, rarity, name, sprite, desc, st) -> str:
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
        'family = "firearm"',
        'category = &"%s"' % cat,
        "rarity = %d" % rarity,
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
        'sprite_id = &"%s"' % sprite,
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
        for (wid, _cat, rarity, *_rest) in WEAPONS:
            w = TIER_WEIGHTS[tier][rarity] * mult
            if w > 0.0:
                entries["wpn_" + wid] = round(w, 4)
    body = ",\n".join('&"%s": %s' % (k, fmt_float(entries[k]) if entries[k] >= 0.001 else repr(entries[k]))
                      for k in sorted(entries))
    text = text[: m.start()] + "entries = {\n" + body + "\n}" + text[m.end():]
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def main() -> int:
    ids = set()
    errors = 0
    for (wid, cat, rarity, name, sprite, desc, adj) in WEAPONS:
        if wid in ids or wid == "starter_pistol":
            print("! id en double ou réservé :", wid)
            errors += 1
        ids.add(wid)
        if sprite not in SPRITE_IDS:
            print("! sprite_id hors liste figée :", wid, sprite)
            errors += 1
        if cat not in CATEGORY_BASE:
            print("! catégorie inconnue :", wid, cat)
            errors += 1
    if errors:
        return 1
    for (wid, cat, rarity, name, sprite, desc, adj) in WEAPONS:
        st = build_stats(cat, rarity, adj)
        with open(os.path.join(WEAPON_DIR, wid + ".tres"), "w", encoding="utf-8") as f:
            f.write(weapon_tres(wid, cat, rarity, name, sprite, desc, st))
        with open(os.path.join(ITEM_DIR, "wpn_" + wid + ".tres"), "w", encoding="utf-8") as f:
            f.write(item_tres(wid, name, desc, rarity, st))
        dps = (st["damage"] * st["projectile_count"] + st["explosion_damage"]) * st["fire_rate"]
        print("%-22s %-17s %d  dmg %5.1f x%d  cad %5.2f  mag %3d  dps %6.1f  %5d $" % (
            wid, cat, rarity, st["damage"], st["projectile_count"], st["fire_rate"], st["magazine_size"], dps, st["value"]))
    for f in sorted(os.listdir(TABLE_DIR)):
        if f.endswith(".tres"):
            patch_table(os.path.join(TABLE_DIR, f), f[:-5])
    print("%d armes générées." % len(WEAPONS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
