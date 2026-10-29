class_name BestiaryRules
extends RefCounted
## Règles du bestiaire appliquées à TOUT le raid juste après la génération des étages
## (Raid._generate_floors), quel que soit le générateur du monde :
##  - **un seul boss par raid** : parmi les apparitions du boss du monde (WorldData.boss_kind),
##    seule celle de l'étage le plus dangereux (|floor_index| le plus grand) est gardée ; les
##    autres deviennent des élites ;
##  - **élites du monde** (WorldData.elite_kinds, 2 par monde) : escorte du boss, gardes des
##    salles au trésor, et rares élites dans les salles de combat des étages profonds.
## Tirages déterministes (seed du raid) : même seed → mêmes ennemis. Réglages : balance.cfg [boss].

const SECTION := "boss"
const DATA_DIR := "res://data/enemies/"


## Applique les règles. `floors` : floor_index → FloorLayout. Renvoie un résumé (tests, debug F3).
static func apply(floors: Dictionary, world: WorldData, run_seed: int) -> Dictionary:
	var summary := {"boss_floor": null, "boss_removed": 0, "elites": 0}
	if world == null or floors.is_empty():
		return summary
	var elites := _valid_elites(world)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, "bestiary_rules"])
	var keys: Array = floors.keys()
	keys.sort()
	# 1) Un seul boss : étage le plus dangereux (|index| max ; à égalité, le sous-sol).
	var boss_floor: Variant = null
	if world.boss_kind != &"":
		for fi: Variant in keys:
			var l: FloorLayout = floors[fi]
			if not _has_kind(l, world.boss_kind):
				continue
			if boss_floor == null or absi(int(fi)) > absi(int(boss_floor)) \
					or (absi(int(fi)) == absi(int(boss_floor)) and int(fi) < int(boss_floor)):
				boss_floor = fi
	summary["boss_floor"] = boss_floor
	var kept_boss := false
	for fi2: Variant in keys:
		var l2: FloorLayout = floors[fi2]
		for sp: FloorLayout.Spawn in l2.enemy_spawns:
			if sp.kind != world.boss_kind or world.boss_kind == &"":
				continue
			if not kept_boss and fi2 == boss_floor:
				kept_boss = true
				continue
			sp.kind = _pick(elites, rng, _roster_pick(world, rng, sp.kind))
			summary["boss_removed"] = int(summary["boss_removed"]) + 1
	if elites.is_empty():
		return summary
	# 2) Élites : escorte du boss, gardes des salles au trésor, rares en combat.
	var escorts := int(Balance.get_value(SECTION, "elite_boss_escorts", 2))
	var guards := int(Balance.get_value(SECTION, "elite_super_loot_guards", 1))
	var chances: Array = Balance.get_value(SECTION, "elite_combat_chance", [0.0, 0.04, 0.08]) as Array
	for fi3: Variant in keys:
		var l3: FloorLayout = floors[fi3]
		var per_room := {}
		var depth := absi(int(fi3))
		var chance := float(chances[mini(depth, chances.size() - 1)]) if not chances.is_empty() else 0.0
		for sp3: FloorLayout.Spawn in l3.enemy_spawns:
			if sp3.kind == world.boss_kind or elites.has(sp3.kind):
				continue
			var room := l3.get_room(sp3.room_id) if sp3.room_id >= 0 else l3.room_at(sp3.cell)
			var rtype: StringName = room.type if room != null else &""
			var rid: int = room.id if room != null else -1
			var used: int = int(per_room.get(rid, 0))
			var make := false
			if rtype == FloorLayout.ROOM_BOSS:
				make = used < escorts
			elif rtype == FloorLayout.ROOM_SUPER_LOOT:
				make = used < guards
			elif rtype == &"combat":
				make = rng.randf() < chance
			if make:
				per_room[rid] = used + 1
				sp3.kind = elites[(used + int(fi3)) % elites.size()] if rtype != &"combat" else _pick(elites, rng, sp3.kind)
				summary["elites"] = int(summary["elites"]) + 1
	return summary


## Élites du monde dont la donnée existe.
static func _valid_elites(world: WorldData) -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in world.elite_kinds:
		if ResourceLoader.exists(DATA_DIR + String(k) + ".tres"):
			out.append(k)
	return out


static func _has_kind(l: FloorLayout, kind: StringName) -> bool:
	for sp: FloorLayout.Spawn in l.enemy_spawns:
		if sp.kind == kind:
			return true
	return false


## Ennemi classique du roster « combat » (repli quand le monde n'a pas d'élites).
static func _roster_pick(world: WorldData, rng: RandomNumberGenerator, fallback: StringName) -> StringName:
	var w := {}
	var roster := world.get_roster(&"combat")
	for k: Variant in roster:
		var kk := StringName(str(k))
		if kk != world.boss_kind and float(roster[k]) > 0.0:
			w[kk] = float(roster[k])
	return LootRoller.pick_weighted(w, rng) if not w.is_empty() else fallback


static func _pick(list: Array[StringName], rng: RandomNumberGenerator, fallback: StringName) -> StringName:
	if list.is_empty():
		return fallback
	return list[rng.randi_range(0, list.size() - 1)]
