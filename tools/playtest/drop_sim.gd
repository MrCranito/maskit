extends Node
## Volet 3 — taux de drop par simulation directe (LootRoller et LootManager RÉELS, sans jouer).
##   godot --headless --path . -s res://tools/playtest/drop_sim_main.gd -- --out=FICHIER.json [--n=100000]
## Sources : chaque table de conteneur (salle normale, puis salle au trésor), chaque cadavre
## d'ennemi (élites : contexte trésor, comme en jeu) et le butin au sol de chaque ennemi.
## Contexte de référence (Normal, rez-de-chaussée) : N tirages par source ; autres difficultés
## (0..4) et étages (-1, +1) : N / 10 tirages. Résultat : chance par fouille de chaque objet
## (au moins un exemplaire), répartition par rareté, nombre moyen d'objets, valeur moyenne.

const ENEMY_DIR := "res://data/enemies/"

var n_ref: int = 100000
var out_path: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.substr(6)
		elif a.begins_with("--n="):
			n_ref = int(a.substr(4))
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var res := {"n_ref": n_ref, "sources": {}}
	var sources: Dictionary = res["sources"]
	var contexts: Array = [[1, 0, n_ref]]
	for d in [0, 2, 3, 4]:
		contexts.append([d, 0, maxi(n_ref / 10, 1000)])
	for f in [-1, 1]:
		contexts.append([1, f, maxi(n_ref / 10, 1000)])
	for kind: String in LootDB.table_kinds():
		if kind.begins_with("enemy"):
			continue
		var table := LootDB.get_table(StringName(kind))
		if table == null:
			continue
		for room: StringName in [&"combat", &"super_loot"]:
			var src := ("tresor:" if room == &"super_loot" else "conteneur:") + kind
			sources[src] = {}
			for c: Array in contexts:
				sources[src][_ctx_key(c)] = _sim(func(rng: RandomNumberGenerator, d: int, f: int) -> Array:
					return LootRoller.roll(table, rng, LootRoller.Context.make(d, f, room)), c, hash([src]))
	for file: String in DirAccess.get_files_at(ENEMY_DIR):
		var path := ENEMY_DIR + file.trim_suffix(".remap")
		if not path.ends_with(".tres"):
			continue
		var data := load(path) as EnemyData
		if data == null:
			continue
		var biome := &"enemy"
		if String(data.kind).begins_with("ss_"):
			biome = &"enemy_space_station"
		elif String(data.kind).begins_with("mall_"):
			biome = &"enemy_mall"
		var keys: Array[StringName] = [&"key_bank_vault"]
		for part: String in ["corpse", "ground"]:
			var src2 := ("cadavre:" if part == "corpse" else "sol:") + String(data.kind)
			sources[src2] = {"elite": data.elite, "boss": data.boss}
			for c2: Array in contexts:
				sources[src2][_ctx_key(c2)] = _sim(func(rng: RandomNumberGenerator, d: int, f: int) -> Array:
					return LootManager.roll_enemy_loot(data, rng, d, f, keys, biome)[part], c2, hash([src2]))
	res["seconds"] = (Time.get_ticks_msec() - t0) / 1000.0
	var fo := FileAccess.open(out_path, FileAccess.WRITE)
	fo.store_string(JSON.stringify(res))
	fo.close()
	print("DROPSIM ok %.0f s" % res["seconds"])
	get_tree().quit(0)


static func _ctx_key(c: Array) -> String:
	return "d%d_f%d" % [int(c[0]), int(c[1])]


## Tire `c[2]` fois ; renvoie {n, empty, items_avg, value_avg, rarity: [5], per_item: {id: chance}}.
func _sim(roll: Callable, c: Array, salt: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([salt, c[0], c[1]])
	var n: int = c[2]
	var empty := 0
	var count := 0
	var value := 0.0
	var rar := [0, 0, 0, 0, 0]
	var per := {}
	for i in n:
		var entries: Array = roll.call(rng, int(c[0]), int(c[1]))
		if entries.is_empty():
			empty += 1
			continue
		for e: Dictionary in entries:
			var it := e["item"] as ItemData
			var k := int(e["count"])
			count += 1
			value += it.value * k
			rar[clampi(it.rarity, 0, 4)] += 1
			per[String(it.id)] = int(per.get(String(it.id), 0)) + 1
	var chance := {}
	for id: String in per:
		chance[id] = float(per[id]) / n
	return {"n": n, "empty": float(empty) / n, "items_avg": float(count) / n, "value_avg": value / n,
		"rarity": rar.map(func(x: int) -> float: return float(x) / n), "per_item": chance}
