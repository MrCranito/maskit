extends GutTest
## Réglages appliqués d'après le playtest automatique du 30/10 (docs/playtest, PR #13) :
##  - salle du boss allégée ([generator] enemy_room_mult boss 1.0 → 0.3) et escorte réduite
##    ([boss] elite_boss_escorts 2 → 1) : le bot mourait de l'escorte et de la salle avant
##    d'avoir touché le boss ;
##  - difficulté Normal adoucie (enemy_density, cooldown_mult, spread_mult) : 0 % d'extraction
##    en Normal, ce qui bloquait la 2e carte.
## Ces tests fixent les valeurs et leurs effets sur le peuplement ; s'ils cassent, c'est que
## l'équilibrage a changé : mettre le test à jour en même temps que balance.cfg.

const Pop := preload("res://scripts/dungeon/gen/populator.gd")
const MallPop := preload("res://scripts/biomes/mall/mall_populator.gd")
const SsPop := preload("res://scripts/biomes/space_station/ss_populator.gd")
const BALANCE := "res://data/balance.cfg"
const NORMAL := 1


func _cfg() -> ConfigFile:
	var c := ConfigFile.new()
	assert_eq(c.load(BALANCE), OK)
	return c


func _room(type: StringName, size: Vector2i) -> FloorLayout.Room:
	var l := FloorLayout.new(Vector2i(40, 40))
	return l.add_room(Rect2i(Vector2i(1, 1), size), false, type, "salle")


func _guards(c: ConfigFile, difficulty: int) -> int:
	var bonus: Array = c.get_value("generator", "guards_bonus", [0, 0, 1, 1, 2])
	return int(c.get_value("generator", "guards_min", 2)) + int(bonus[difficulty])


# --- Salle du boss et escorte -------------------------------------------------------

func test_boss_escort_is_one_elite() -> void:
	assert_eq(int(_cfg().get_value("boss", "elite_boss_escorts", -1)), 1, "une seule élite d'escorte")


func test_boss_room_population_light() -> void:
	var c := _cfg()
	var gen: Dictionary = c.get_value("generator", "enemy_room_mult", {})
	assert_almost_eq(float(gen.get("boss", -1.0)), 0.3, 0.0001, "[generator] boss (Far West, centre commercial)")
	assert_lt(float(gen["boss"]), float(gen["combat"]), "salle du boss moins peuplée qu'une salle de combat")
	# Le centre commercial n'a pas de clé propre : il lit [generator].
	assert_false(c.has_section_key("mall", "enemy_room_mult"), "le centre commercial suit [generator]")
	# La Station garde sa propre valeur (réacteur, déjà allégé), jamais plus peuplée.
	var ss: Dictionary = c.get_value("space_station", "enemy_room_mult", {})
	assert_lte(float(ss.get("boss", 99.0)), float(gen["boss"]), "Station : salle du boss pas plus peuplée")


## Salle de boss de 20×20 en Normal au rez-de-chaussée, sans aléa : 400 × 0,024 × 0,3 = 2,88
## → 2 ennemis de salle + 2 gardes (dont l'escorte). Avant : 400 × 0,028 × 1,0 = 11,2 → plafonné à 11.
func test_boss_room_enemy_count_normal() -> void:
	var c := _cfg()
	var boss := _room(&"boss", Vector2i(20, 20))
	var combat := _room(&"combat", Vector2i(20, 20))
	var guards := _guards(c, NORMAL)
	assert_eq(guards, 2)
	assert_eq(Pop.enemy_count(boss, 0, NORMAL, 0.0), 4, "Far West : 2 gardes + 2 ennemis de salle")
	assert_eq(MallPop.enemy_count(boss, 0, NORMAL, 0.0), 4, "centre commercial : idem")
	assert_lte(SsPop.enemy_count(boss, 0, NORMAL, 0.0), 4, "Station : pas plus")
	assert_lt(Pop.enemy_count(boss, 0, NORMAL, 0.0), Pop.enemy_count(combat, 0, NORMAL, 0.0),
		"la salle du boss n'est plus une salle de combat avec un boss en plus")


func test_boss_room_keeps_one_elite_escort() -> void:
	var elites: Array[StringName] = []
	for f: String in DirAccess.get_files_at("res://data/enemies/"):
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var d := load("res://data/enemies/" + file) as EnemyData
		if d != null and d.elite and not d.boss:
			elites.append(d.kind)
	if elites.is_empty():
		pass_test("aucune élite déclarée")
		return
	var w := WorldData.new()
	w.boss_kind = &"the_boss"
	w.elite_kinds = elites
	w.enemy_roster = {&"combat": {&"grunt_a": 1.0}}
	var l := FloorLayout.new(Vector2i(30, 20))
	l.floor_index = 0
	var room := l.add_room(Rect2i(0, 0, 20, 20), false, &"boss", "arène")
	for i in 4:
		l.add_spawn(l.enemy_spawns, Vector2i(2 + i, 2), &"the_boss" if i == 0 else &"grunt_a", room.id)
	BestiaryRules.apply({0: l}, w, 42)
	var n := 0
	for sp: FloorLayout.Spawn in l.enemy_spawns:
		n += 1 if elites.has(sp.kind) else 0
	assert_eq(n, 1, "une seule élite autour du boss")


# --- Difficulté Normal --------------------------------------------------------------

func test_normal_difficulty_values() -> void:
	var c := _cfg()
	var dens: Array = c.get_value("generator", "enemy_density", [])
	var cd: Array = c.get_value("enemy_difficulty", "cooldown_mult", [])
	var sp: Array = c.get_value("enemy_difficulty", "spread_mult", [])
	assert_eq(dens.size(), 5)
	assert_eq(cd.size(), 5)
	assert_eq(sp.size(), 5)
	assert_almost_eq(float(dens[NORMAL]), 0.024, 0.0001, "densité Normal")
	assert_almost_eq(float(cd[NORMAL]), 1.0, 0.0001, "cadence Normal neutre")
	assert_almost_eq(float(sp[NORMAL]), 1.0, 0.0001, "précision Normal neutre")
	# Ce que lisent vraiment les ennemis (Enemy._diff_at) et les générateurs.
	assert_almost_eq(Enemy._diff_at("cooldown_mult", NORMAL, [0.0]), 1.0, 0.0001)
	assert_almost_eq(Enemy._diff_at("spread_mult", NORMAL, [0.0]), 1.0, 0.0001)


## La progression reste monotone : Facile < Normal < Difficile < Expert < Cauchemar.
func test_difficulty_progression_monotonic() -> void:
	var c := _cfg()
	var dens: Array = c.get_value("generator", "enemy_density", [])
	var cd: Array = c.get_value("enemy_difficulty", "cooldown_mult", [])
	var sp: Array = c.get_value("enemy_difficulty", "spread_mult", [])
	for i in range(1, 5):
		assert_gt(float(dens[i]), float(dens[i - 1]), "densité croissante (%d)" % i)
		assert_lt(float(cd[i]), float(cd[i - 1]), "recharge des tirs décroissante (%d)" % i)
		assert_lt(float(sp[i]), float(sp[i - 1]), "dispersion décroissante (%d)" % i)
