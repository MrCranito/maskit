extends GutTest
## Escalier de difficulté par monde ([world_scaling] dans balance.cfg) : multiplicateurs de PV et de
## dégâts appliqués à tous les ennemis du monde de la carte (Enemy.world_mult).

const BALANCE := "res://data/balance.cfg"
const WORLDS_DIR := "res://data/worlds/"

var _saved_world: String


func before_each() -> void:
	_saved_world = GameState.world_path


func after_each() -> void:
	GameState.world_path = _saved_world


func _table(key: String) -> Dictionary:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(BALANCE), OK)
	var v: Variant = cfg.get_value("world_scaling", key, {})
	assert_true(v is Dictionary, "[world_scaling] %s est un dictionnaire" % key)
	return v if v is Dictionary else {}


func test_chaque_monde_a_sa_marche() -> void:
	for key: String in ["hp_mult", "damage_mult", "boss_hp_mult", "boss_damage_mult", "enemy_density_mult"]:
		var t := _table(key)
		for f: String in DirAccess.get_files_at(WORLDS_DIR):
			if f.ends_with(".tres"):
				assert_true(t.has(f.get_basename()), "%s : %s présent" % [key, f.get_basename()])
		for id: Variant in t:
			assert_true(ResourceLoader.exists(WORLDS_DIR + str(id) + ".tres"), "%s : monde %s existe" % [key, id])
			assert_between(float(t[id]), 0.3, 3.0, "%s : %s raisonnable" % [key, id])


func test_monde_inconnu_vaut_un() -> void:
	assert_almost_eq(Enemy.world_mult("hp_mult", "monde_inexistant"), 1.0, 0.0001)
	GameState.world_path = ""
	assert_almost_eq(Enemy.world_mult("damage_mult"), 1.0, 0.0001)


func test_ennemi_du_monde_mis_a_l_echelle() -> void:
	var t := _table("hp_mult")
	var d := _table("damage_mult")
	for id: Variant in t:
		GameState.world_path = WORLDS_DIR + str(id) + ".tres"
		var data := load("res://data/enemies/fw_bandit.tres") as EnemyData
		var e := Enemy.new()
		e.data = data
		add_child_autofree(e)
		assert_almost_eq(e.max_hp, data.max_hp * float(t[id]), 0.01, "PV : %s" % id)
		assert_almost_eq(e.diff_damage_mult, Enemy._diff_at("damage_mult", GameState.difficulty, [1.0]) * float(d[id]),
			0.0001, "dégâts : %s" % id)


func test_boss_suit_sa_propre_courbe() -> void:
	var t := _table("boss_hp_mult")
	var d := _table("boss_damage_mult")
	var data := load("res://data/enemies/fw_sheriff.tres") as EnemyData
	for id: Variant in t:
		GameState.world_path = WORLDS_DIR + str(id) + ".tres"
		var e := Enemy.new()
		e.data = data
		add_child_autofree(e)
		assert_almost_eq(e.max_hp, data.max_hp * e.boss_hp_scale() * float(t[id]), 0.01, "PV du boss : %s" % id)
		assert_almost_eq(e.diff_damage_mult, Enemy._diff_at("damage_mult", GameState.difficulty, [1.0]) * float(d[id]),
			0.0001, "dégâts du boss : %s" % id)


func test_escorte_de_l_arene_suit_la_courbe_du_boss() -> void:
	var t := _table("boss_hp_mult")
	var data := load("res://data/enemies/fw_bandit.tres") as EnemyData
	for id: Variant in t:
		GameState.world_path = WORLDS_DIR + str(id) + ".tres"
		var e := Enemy.new()
		e.data = data
		e.set_meta(Enemy.META_BOSS_ARENA, true)
		add_child_autofree(e)
		assert_almost_eq(e.max_hp, data.max_hp * float(t[id]), 0.01, "garde de l'arène : %s" % id)
