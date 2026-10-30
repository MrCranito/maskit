#!/usr/bin/env python3
"""Objets et tables de butin des Terres gelées (préfixe fl_).

Usage : python3 tools/dev/gen_frozen_lands_loot.py
Produit data/items/fl_*.tres, data/items/fl_key_*.tres et data/loot_tables/fl_*.tres +
enemy_frozen_lands.tres. Les entrées d'armes (wpn_*) sont copiées d'une table existante du même
palier (cargo_crate = medium, armory_chest = rich, enemy_space_station = enemy) afin de rester
alignées sur tools/gen_weapons.py ; relancer tools/cap_drop_rates.py ensuite.
"""
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ITEMS = os.path.join(ROOT, "data", "items")
TABLES = os.path.join(ROOT, "data", "loot_tables")
ICON = "res://assets/third_party/icons/%s.svg"

# id, nom, description, icône, teinte, rareté, type, stack, valeur, poids, drop_min, drop_max, soin
ITEM_DEFS = [
    ("fl_ration", "Ration arctique", "Pemmican et biscuits durs comme la glace. Petit soin.", "loot_bag", "0.85,0.8,0.6", 0, "consumable", 6, 8, 0.3, 1, 3, 10.0),
    ("fl_thermos", "Thermos de café brûlant", "Encore chaud après toutes ces années. Soin moyen.", "item_health_potion", "0.9,0.5,0.3", 0, "consumable", 4, 20, 0.4, 1, 2, 25.0),
    ("fl_antifreeze_serum", "Sérum antigel", "Injection expérimentale du labo cryo. Gros soin.", "item_health_potion", "0.45,0.9,1.0", 2, "consumable", 3, 70, 0.3, 1, 1, 60.0),
    ("fl_flare", "Fusée de détresse", "Éclaire un instant la tempête. Se revend aux secours.", "alert_hazard", "1.0,0.3,0.2", 0, "valuable", 8, 12, 0.1, 1, 3, 0.0),
    ("fl_dog_tags", "Plaques militaires", "Identité d'un soldat que la glace n'a pas rendu.", "rarity_star", "0.75,0.8,0.85", 1, "valuable", 10, 40, 0.05, 1, 2, 0.0),
    ("fl_fuel_can", "Jerrican de kérosène", "Carburant d'hélicoptère, précieux sur le continent.", "container_barrel", "0.8,0.25,0.2", 1, "valuable", 4, 55, 0.8, 1, 2, 0.0),
    ("fl_core_sample", "Carotte de glace", "Échantillon de forage étiqueté d'un sigle inconnu.", "rarity_gem", "0.6,0.85,1.0", 1, "valuable", 6, 48, 0.4, 1, 2, 0.0),
    ("fl_blue_crystal", "Cristal bleu", "Fragment lumineux prélevé dans le laboratoire. Il bourdonne.", "rarity_gem", "0.35,0.8,1.0", 2, "valuable", 4, 140, 0.3, 1, 1, 0.0),
    ("fl_research_disk", "Disque de recherche", "Données chiffrées du programme enfoui sous la base.", "item_map", "0.7,0.9,1.0", 2, "valuable", 3, 160, 0.05, 1, 1, 0.0),
    ("fl_officer_watch", "Montre du commandant", "Mécanisme suisse, encore à l'heure. Très recherchée.", "stat_stopwatch", "0.95,0.85,0.4", 3, "valuable", 1, 520, 0.05, 1, 1, 0.0),
    ("fl_crystal_heart", "Cœur de cristal", "Le noyau intact d'un grand cristal. Il émet une lumière froide.", "rarity_gem", "0.5,0.95,1.0", 4, "valuable", 1, 1500, 0.6, 1, 1, 0.0),
    ("fl_steel_plate", "Tôle blindée", "Matériau : plaque d'acier de bunker.", "stat_armor", "0.6,0.65,0.7", 0, "material", 10, 6, 0.6, 1, 3, 0.0),
    ("fl_cryo_fluid", "Fluide cryogénique", "Matériau : réfrigérant des cuves.", "ammo_powder", "0.5,0.85,1.0", 1, "material", 8, 18, 0.3, 1, 2, 0.0),
    ("fl_key_lab", "Badge du laboratoire cryogénique", "Carte d'un chercheur. Ouvre le labo cryogénique scellé du bloc nord.", "key_basic", "0.45,0.9,1.0", 3, "key", 1, 280, 0.1, 1, 1, 0.0),
    ("fl_key_bunker", "Clef de l'armurerie", "Clef lourde du bunker-armurerie de l'aile. Ne pas perdre.", "key_skeleton", "1.0,0.7,0.3", 3, "key", 1, 300, 0.1, 1, 1, 0.0),
]

ITEM_TPL = """[gd_resource type="Resource" script_class="ItemData" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/loot/item_data.gd" id="1_item"]
[ext_resource type="Texture2D" path="{icon}" id="2_icon"]

[resource]
script = ExtResource("1_item")
id = &"{id}"
display_name = "{name}"
description = "{desc}"
icon = ExtResource("2_icon")
tint = Color({tint},1)
rarity = {rarity}
type = &"{type}"
stack_max = {stack}
value = {value}
weight = {weight}
drop_min = {dmin}
drop_max = {dmax}
heal_amount = {heal}
"""

COMMON = {"mat_scrap": 5, "mat_chemicals": 1.5, "black_powder": 2, "bandage": 3}
# kind, nom, rolls, vide, temps, entrées propres, table modèle pour les armes
TABLE_DEFS = [
    ("fl_supply_crate", "Caisse militaire", (1, 3), 0.1, 1.4,
     {"fl_ration": 5, "fl_thermos": 2, "fl_flare": 3, "fl_fuel_can": 1.5, "fl_steel_plate": 4, "fl_dog_tags": 1, "rifle_ammo": 3}, "cargo_crate"),
    ("fl_ammo_box", "Caisse de munitions", (1, 3), 0.05, 1.2,
     {"fl_flare": 2, "fl_steel_plate": 2, "black_powder": 4, "rifle_ammo": 5, "revolver_ammo": 5, "fl_dog_tags": 0.8}, "armory_chest"),
    ("fl_fuel_drum", "Baril de carburant", (1, 2), 0.2, 1.0,
     {"fl_fuel_can": 5, "fl_flare": 2, "mat_chemicals": 2, "fl_steel_plate": 1}, "locker"),
    ("fl_footlocker", "Casier de soldat", (1, 2), 0.15, 1.0,
     {"fl_ration": 3, "fl_thermos": 2, "fl_dog_tags": 3, "fl_flare": 1, "bandage": 3, "fl_officer_watch": 0.15}, "locker"),
    ("fl_cryo_pod", "Cuve cryogénique", (1, 2), 0.2, 1.6,
     {"fl_antifreeze_serum": 3, "fl_cryo_fluid": 4, "fl_core_sample": 2, "fl_blue_crystal": 1, "fl_research_disk": 0.6}, "cryo_pod"),
    ("fl_sample_case", "Mallette d'échantillons", (1, 2), 0.1, 1.2,
     {"fl_core_sample": 5, "fl_blue_crystal": 2, "fl_research_disk": 1.2, "fl_cryo_fluid": 2, "fl_antifreeze_serum": 1, "fl_crystal_heart": 0.04}, "cryo_pod"),
    ("fl_sled", "Traîneau de ravitaillement", (1, 3), 0.1, 1.5,
     {"fl_ration": 6, "fl_thermos": 2, "fl_fuel_can": 3, "fl_steel_plate": 2, "fl_flare": 2}, "cargo_crate"),
    ("fl_frozen_corpse", "Soldat gelé", (1, 2), 0.15, 1.0,
     {"fl_dog_tags": 5, "fl_ration": 2, "bandage": 2, "fl_flare": 1, "fl_officer_watch": 0.1, "revolver_ammo": 2}, "corpse"),
    ("enemy_frozen_lands", "Butin d'ennemi (Terres gelées)", (1, 1), 0.0, 1.0,
     {"fl_ration": 4, "fl_flare": 3, "fl_dog_tags": 2, "fl_steel_plate": 3, "fl_cryo_fluid": 2, "fl_core_sample": 1.5, "fl_blue_crystal": 0.5, "bandage": 3}, "enemy_space_station"),
]

TABLE_TPL = """[gd_resource type="Resource" script_class="LootTable" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/loot/loot_table.gd" id="1_table"]

[resource]
script = ExtResource("1_table")
kind = &"{kind}"
display_name = "{name}"
rolls_min = {rmin}
rolls_max = {rmax}
empty_chance = {empty}
search_time = {time}
entries = {{
{entries}
}}
"""
ENTRY_RE = re.compile(r'&"([^"]+)":\s*([0-9.eE+-]+)')


def weapons_of(kind):
    text = open(os.path.join(TABLES, kind + ".tres"), encoding="utf-8").read()
    out = {}
    for m in ENTRY_RE.finditer(text):
        if m.group(1).startswith("wpn_"):
            out[m.group(1)] = m.group(2)
    return out


def fmt(v):
    if isinstance(v, str):
        return v
    if float(v).is_integer():
        return str(int(v))
    return repr(float(v))


def main():
    existing = {f[:-5] for f in os.listdir(ITEMS) if f.endswith(".tres")}
    for (iid, name, desc, icon, tint, rar, typ, stack, val, wt, dmin, dmax, heal) in ITEM_DEFS:
        open(os.path.join(ITEMS, iid + ".tres"), "w", encoding="utf-8").write(ITEM_TPL.format(
            icon=ICON % icon, id=iid, name=name, desc=desc, tint=tint, rarity=rar, type=typ, stack=stack,
            value=val, weight=wt, dmin=dmin, dmax=dmax, heal=heal))
    for (kind, name, rolls, empty, time, own, model) in TABLE_DEFS:
        entries = dict(own)
        for k, v in entries.items():
            if not (k.startswith("fl_") or k in existing):
                print("  ! objet inconnu", k)
        entries.update(weapons_of(model))
        body = ",\n".join('&"%s": %s' % (k, fmt(entries[k])) for k in sorted(entries))
        open(os.path.join(TABLES, kind + ".tres"), "w", encoding="utf-8").write(TABLE_TPL.format(
            kind=kind, name=name, rmin=rolls[0], rmax=rolls[1], empty=empty, time=time, entries=body))
    print("objets", len(ITEM_DEFS), "tables", len(TABLE_DEFS))


if __name__ == "__main__":
    main()
