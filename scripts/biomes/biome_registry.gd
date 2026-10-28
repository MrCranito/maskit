class_name BiomeRegistry
extends RefCounted
## Liste des biomes. Chaque biome fournit (chemins fixes, voir docs/CONVENTIONS.md) :
##   data/worlds/<world_id>.tres                 (WorldData, avec generator_path / builder_path)
##   scripts/biomes/<biome>/enemy_kinds.gd       (const KINDS : visuels d'ennemis, format EnemyVisual.KINDS)

const BIOMES: Array[Dictionary] = [
	{"biome": &"far_west", "world": "res://data/worlds/world_01_far_west.tres", "enemy_kinds": ""},
	{"biome": &"space_station", "world": "res://data/worlds/world_02_space_station.tres", "enemy_kinds": "res://scripts/biomes/space_station/enemy_kinds.gd"},
	{"biome": &"mall", "world": "res://data/worlds/world_03_mall.tres", "enemy_kinds": "res://scripts/biomes/mall/enemy_kinds.gd"},
	{"biome": &"underwater", "world": "res://data/worlds/world_04_underwater.tres", "enemy_kinds": "res://scripts/biomes/underwater/enemy_kinds.gd"},
]

static var _extra_kinds: Dictionary = {}
static var _loaded: bool = false


## Visuels d'ennemis déclarés par les biomes (kind → dictionnaire au format EnemyVisual.KINDS).
static func extra_enemy_kinds() -> Dictionary:
	if not _loaded:
		_loaded = true
		for b: Dictionary in BIOMES:
			var path: String = b["enemy_kinds"]
			if path != "" and ResourceLoader.exists(path):
				var scr: Script = load(path) as Script
				if scr != null:
					var k: Variant = scr.get_script_constant_map().get("KINDS", {})
					if k is Dictionary:
						_extra_kinds.merge(k as Dictionary)
	return _extra_kinds


static func world_path(biome: StringName) -> String:
	for b: Dictionary in BIOMES:
		if b["biome"] == biome:
			return b["world"]
	return ""
