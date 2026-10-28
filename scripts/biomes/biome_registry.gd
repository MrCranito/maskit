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

## Scripts déclarant des conteneurs (constante CONTAINER_DEFS ou DEFS) et des cachettes
## (HIDING_DEFS ou HIDE_DEFS) au format LootContainer.DEFS / HidingSpot.DEFS.
const DEF_SCRIPTS: Array[String] = [
	"res://scripts/biomes/space_station/space_station_builder.gd",
	"res://scripts/biomes/mall/mall_builder.gd",
	"res://scripts/biomes/underwater/container_defs.gd",
]
## Valeurs par défaut des champs absents d'une définition de biome.
const DEF_DEFAULTS := {"scale": 0.55, "block": Vector2.ZERO, "reach": 4.0, "shadow": 0.0, "foot": 4.0}

static var _extra_kinds: Dictionary = {}
static var _loaded: bool = false
static var _container_defs: Dictionary = {}
static var _hiding_defs: Dictionary = {}
static var _defs_loaded: bool = false


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


## Définition d'un conteneur déclaré par un biome (vide si inconnu).
static func container_def(kind: StringName) -> Dictionary:
	_load_defs()
	return _container_defs.get(kind, {})


## Définition d'une cachette déclarée par un biome (vide si inconnue).
static func hiding_def(kind: StringName) -> Dictionary:
	_load_defs()
	return _hiding_defs.get(kind, {})


static func _load_defs() -> void:
	if _defs_loaded:
		return
	_defs_loaded = true
	for path: String in DEF_SCRIPTS:
		if not ResourceLoader.exists(path):
			continue
		var scr: Script = load(path) as Script
		if scr == null:
			continue
		var consts: Dictionary = scr.get_script_constant_map()
		for key: String in ["CONTAINER_DEFS", "DEFS"]:
			if consts.get(key) is Dictionary:
				_merge_defs(_container_defs, consts[key])
				break
		for key: String in ["HIDING_DEFS", "HIDE_DEFS"]:
			if consts.get(key) is Dictionary:
				_merge_defs(_hiding_defs, consts[key])
				break


static func _merge_defs(into: Dictionary, src: Dictionary) -> void:
	for k: Variant in src:
		var d: Dictionary = DEF_DEFAULTS.duplicate()
		d.merge(src[k] as Dictionary, true)
		into[StringName(str(k))] = d


## Table de butin des ennemis du biome courant (data/loot_tables/enemy_<biome>.tres), sinon « enemy ».
static func enemy_table_kind(biome: StringName) -> StringName:
	var k := StringName("enemy_" + String(biome))
	return k if biome != &"" and ResourceLoader.exists("res://data/loot_tables/%s.tres" % k) else &"enemy"
