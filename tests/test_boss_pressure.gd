extends GutTest
## Pression autour du boss (PR fix/pression-boss), d'après la passe boss du bot : 0 victoire sur
## 60 combats après la PR #36, le bot mourait de l'escorte et des gardes avant le boss.
##  - escorte d'élite par difficulté ([boss] elite_boss_escorts, tableau ; un nombre seul vaut
##    pour toutes les difficultés) ;
##  - gardes de la salle du boss réglés à part des salles au trésor
##    ([generator] boss_guards_min / boss_guards_bonus, valeurs inchangées).
## S'ils cassent, l'équilibrage a changé : mettre le test à jour en même temps que balance.cfg.

const Pop := preload("res://scripts/dungeon/gen/populator.gd")
const MallPop := preload("res://scripts/biomes/mall/mall_populator.gd")
const SsPop := preload("res://scripts/biomes/space_station/ss_populator.gd")
const BALANCE := "res://data/balance.cfg"
const NORMAL := 1
const HARD := 2


func _cfg() -> ConfigFile:
	var c := ConfigFile.new()
	assert_eq(c.load(BALANCE), OK)
	return c


func _room(type: StringName, size: Vector2i) -> FloorLayout.Room:
	var l := FloorLayout.new(Vector2i(40, 40))
	return l.add_room(Rect2i(Vector2i(1, 1), size), false, type, "salle")


func _elites() -> Array[StringName]:
	var out: Array[StringName] = []
	for f: String in DirAccess.get_files_at("res://data/enemies/"):
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var d := load("res://data/enemies/" + file) as EnemyData
		if d != null and d.elite and not d.boss:
			out.append(d.kind)
	return out


## Arène de 20×20 : le boss + 4 ennemis ordinaires ; renvoie le nombre d'élites après les règles.
func _escort_after_rules(difficulty: int) -> int:
	var elites := _elites()
	var w := WorldData.new()
	w.boss_kind = &"the_boss"
	w.elite_kinds = elites
	w.enemy_roster = {&"combat": {&"grunt_a": 1.0}}
	var l := FloorLayout.new(Vector2i(30, 20))
	l.floor_index = 0
	var room := l.add_room(Rect2i(0, 0, 20, 20), false, &"boss", "arène")
	for i in 5:
		l.add_spawn(l.enemy_spawns, Vector2i(2 + i, 2), &"the_boss" if i == 0 else &"grunt_a", room.id)
	BestiaryRules.apply({0: l}, w, 42, difficulty)
	var n := 0
	for sp: FloorLayout.Spawn in l.enemy_spawns:
		n += 1 if elites.has(sp.kind) else 0
	return n


# --- Escorte d'élite par difficulté --------------------------------------------------

func test_escort_values_per_difficulty() -> void:
	var v: Variant = _cfg().get_value("boss", "elite_boss_escorts", null)
	assert_true(v is Array, "elite_boss_escorts est un tableau par difficulté")
	assert_eq(v, [0, 1, 1, 1, 2], "Facile : pas d'élite ; Normal à Expert : 1 ; Cauchemar : 2")
	for i in 5:
		assert_eq(BestiaryRules.boss_escorts(i), int((v as Array)[i]), "lecture difficulté %d" % i)
	for i2 in range(1, 5):
		assert_gte(BestiaryRules.boss_escorts(i2), BestiaryRules.boss_escorts(i2 - 1), "escorte croissante (%d)" % i2)
	assert_lt(BestiaryRules.boss_escorts(0), BestiaryRules.boss_escorts(NORMAL), "Facile plus léger que Normal")


func test_escort_scalar_still_accepted() -> void:
	var saved: Variant = Balance.get_value("boss", "elite_boss_escorts", null)
	Balance._config.set_value("boss", "elite_boss_escorts", 2)
	var a := BestiaryRules.boss_escorts(0)
	var b := BestiaryRules.boss_escorts(4)
	Balance._config.set_value("boss", "elite_boss_escorts", saved)
	assert_eq(a, 2, "valeur unique : la même pour toutes les difficultés")
	assert_eq(b, 2)
	assert_eq(BestiaryRules.boss_escorts(99), BestiaryRules.boss_escorts(4), "indice borné")


func test_escort_applied_by_difficulty() -> void:
	if _elites().is_empty():
		pass_test("aucune élite déclarée")
		return
	assert_eq(_escort_after_rules(0), 0, "Facile : pas d'élite autour du boss")
	assert_eq(_escort_after_rules(NORMAL), 1, "Normal : une élite d'escorte")
	assert_eq(_escort_after_rules(HARD), 1, "Difficile : une élite d'escorte")
	assert_eq(_escort_after_rules(4), 2, "Cauchemar : deux élites")


# --- Gardes de la salle du boss ------------------------------------------------------

func test_boss_guard_values() -> void:
	var c := _cfg()
	assert_eq(int(c.get_value("generator", "boss_guards_min", -1)), 2)
	assert_eq(c.get_value("generator", "boss_guards_bonus", []), [0, 0, 1, 1, 2])
	# Les salles au trésor gardent leurs réglages.
	assert_eq(int(c.get_value("generator", "guards_min", -1)), 2)
	assert_eq(c.get_value("generator", "guards_bonus", []), [0, 0, 1, 1, 2])


## Salle de 20×20 au rez-de-chaussée, sans aléa. Normal : 400 × 0,024 × 0,3 = 2,88 → 2 ennemis de
## salle + 2 gardes. Difficile : 400 × 0,036 × 0,3 = 4,32 → 4 + 3 gardes.
func test_boss_room_counts() -> void:
	var boss := _room(&"boss", Vector2i(20, 20))
	assert_eq(Pop.enemy_count(boss, 0, NORMAL, 0.0), 4, "Far West, Normal")
	assert_eq(MallPop.enemy_count(boss, 0, NORMAL, 0.0), 4, "centre commercial, Normal")
	assert_lte(SsPop.enemy_count(boss, 0, NORMAL, 0.0), 4, "Station, Normal : pas plus")
	assert_eq(Pop.enemy_count(boss, 0, HARD, 0.0), 7, "Far West, Difficile")
	assert_gt(Pop.enemy_count(boss, 0, HARD, 0.0), Pop.enemy_count(boss, 0, NORMAL, 0.0), "Difficile plus peuplé")


func test_super_loot_guards_unchanged() -> void:
	var sl := _room(&"super_loot", Vector2i(10, 10))
	# 100 × 0,024 × 1,0 = 2,4 → 2 + 2 gardes.
	assert_eq(Pop.enemy_count(sl, 0, NORMAL, 0.0), 4, "salle au trésor, Normal : 2 gardes")
	assert_eq(MallPop.enemy_count(sl, 0, NORMAL, 0.0), 4)
