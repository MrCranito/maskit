extends GutTest
## PV des boss par difficulté ([boss] hp_mult) et absence de régénération au retour
## ([boss] return_regen_ratio_per_sec). Playtest du 30/10 : 0 victoire sur 1080 combats de boss ;
## avec l'arsenal de départ, 3000 PV demandaient environ une minute de tir parfait, et un boss
## semé repartait à son point d'apparition en regagnant 25 % de ses PV par seconde.

const BALANCE := "res://data/balance.cfg"
const BOSSES: Array[StringName] = [&"fw_sheriff", &"ss_architect", &"mall_omnistore"]

var _world: Node2D
var _saved_player: Node2D
var _saved_difficulty: int
var _saved_world: String


class FakePlayer extends Node2D:
	func _ready() -> void:
		add_to_group(&"player")

	func is_alive() -> bool:
		return true

	func take_damage(_amount: float, _source: Node = null) -> void:
		pass


func before_each() -> void:
	_world = Node2D.new()
	add_child_autofree(_world)
	var p := FakePlayer.new()
	p.position = Vector2(9000, 9000)
	_world.add_child(p)
	_saved_player = GameState.player
	GameState.player = p
	_saved_difficulty = GameState.difficulty
	# Hors de tout monde : l'escalier [world_scaling] (test_world_scaling.gd) vaut 1.
	_saved_world = GameState.world_path
	GameState.world_path = ""


func after_each() -> void:
	GameState.player = _saved_player
	GameState.difficulty = _saved_difficulty
	GameState.world_path = _saved_world


func _cfg() -> ConfigFile:
	var c := ConfigFile.new()
	assert_eq(c.load(BALANCE), OK)
	return c


func _spawn(kind: StringName, difficulty: int) -> Enemy:
	GameState.difficulty = difficulty
	var d := (load("res://data/enemies/%s.tres" % kind) as EnemyData).duplicate() as EnemyData
	d.patrol_radius = 0.0
	var e := Enemy.spawn(d)
	_world.add_child(e)
	return e


func test_hp_mult_par_difficulte() -> void:
	var a: Array = _cfg().get_value("boss", "hp_mult", [])
	assert_eq(a.size(), 5, "une valeur par difficulté (Facile → Cauchemar)")
	for i in range(1, a.size()):
		assert_gt(float(a[i]), float(a[i - 1]), "progression strictement croissante")
	assert_lt(float(a[1]), 1.0, "Normal : boss allégés")
	assert_lte(float(a[4]), 1.0, "Cauchemar : jamais plus que les PV du .tres")


func test_pv_des_boss_mis_a_l_echelle() -> void:
	for kind: StringName in BOSSES:
		for diff in [0, 1, 4]:
			var e := _spawn(kind, diff)
			var base := e.data.max_hp
			assert_almost_eq(e.max_hp, base * Enemy.boss_hp_mult(diff), 0.01, "%s, difficulté %d" % [kind, diff])
			assert_almost_eq(e.hp, e.max_hp, 0.01, "%s : PV pleins à l'apparition" % kind)
			e.free()


func test_ennemis_ordinaires_inchanges() -> void:
	var e := _spawn(&"fw_buffalo", 1)
	assert_almost_eq(e.max_hp, e.data.max_hp, 0.01, "le multiplicateur ne touche que les boss")
	assert_almost_eq(e.boss_hp_scale(), 1.0, 0.0001)


func test_modificateur_de_carte_garde_l_echelle() -> void:
	var e := _spawn(&"fw_sheriff", 1)
	var base := (load("res://data/enemies/fw_sheriff.tres") as EnemyData).max_hp
	e.apply_modifiers(1.5, 1.0, 1.0, 1.0)
	assert_almost_eq(e.max_hp, base * 1.5 * Enemy.boss_hp_mult(1), 0.01, "carte × difficulté")


func test_boss_ne_se_soigne_pas_au_retour() -> void:
	var boss := _spawn(&"fw_sheriff", 1)
	var dog := _spawn(&"fw_buffalo", 1)
	assert_almost_eq(boss.return_regen_ratio_per_sec, 0.0, 0.0001, "boss : aucune régénération")
	assert_gt(dog.return_regen_ratio_per_sec, 0.0, "les autres ennemis se soignent toujours")
	await wait_physics_frames(2)
	boss.global_position += Vector2(400, 0)
	boss.hp = boss.max_hp * 0.5
	boss.state_machine.transition_to(Enemy.STATE_RETURN)
	await wait_physics_frames(30)
	assert_almost_eq(boss.hp, boss.max_hp * 0.5, 0.01, "un boss entamé le reste")
