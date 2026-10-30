extends GutTest
## Non-régression du cycle de vie d'un raid (signalements APK de Victor, 30/10) :
## - les cadavres / le butin au sol / l'état des conteneurs d'une partie ne doivent pas
##   réapparaître dans la partie suivante (Station Kagami jonchée de hors-la-loi du Far West) ;
## - la mort du joueur (dégâts réels, ennemis autour) affiche bien l'écran de fin en solo.

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"

var _raids: Array[Raid] = []
var _saved_debug: bool = false
var _saved_map: Resource = null
var _saved_world: String = ""
var _saved_seed: int = 0
var _saved_diff: int = 1
var _saved_profile: Dictionary = {}
var _saved_sm_data: Dictionary = {}
var _save_existed: bool = false
var _save_text: String = ""


func before_each() -> void:
	_saved_debug = GameState.debug_enabled
	GameState.debug_enabled = false
	_saved_map = GameState.current_map
	_saved_world = GameState.world_path
	_saved_seed = GameState.run_seed
	_saved_diff = GameState.difficulty
	_saved_profile = Profile.to_dict()
	_saved_sm_data = (SaveManager.data as Dictionary).duplicate(true)
	_save_existed = FileAccess.file_exists(SaveManager.SAVE_PATH)
	_save_text = FileAccess.get_file_as_string(SaveManager.SAVE_PATH) if _save_existed else ""
	NetHooks.reset()


func after_each() -> void:
	for r: Raid in _raids:
		if is_instance_valid(r):
			r.free()
	_raids.clear()
	get_tree().paused = false
	GameState.debug_enabled = _saved_debug
	GameState.current_map = _saved_map
	GameState.world_path = _saved_world
	GameState.run_seed = _saved_seed
	GameState.difficulty = _saved_diff
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_sm_data
	if _save_existed:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_text)
	elif FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH))


func _start(card_id: StringName, seed_value: int) -> Raid:
	var card := MapCard.find(card_id)
	assert_not_null(card, "carte %s" % card_id)
	GameState.set_current_map(card, false)
	GameState.run_seed = seed_value
	var r := (load(RAID_SCENE) as PackedScene).instantiate() as Raid
	_raids.append(r)
	add_child(r)
	await wait_physics_frames(3)
	return r


func _end(r: Raid) -> void:
	_raids.erase(r)
	if is_instance_valid(r):
		r.free()
	await wait_process_frames(2)


static func _count_nodes(root: Node, script_class: Variant) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if is_instance_of(x, script_class):
			n += 1
		stack.append_array(x.get_children())
	return n


static func _first_enemy(r: Raid) -> Enemy:
	for e: Node in r.get_tree().get_nodes_in_group(Enemy.GROUP_ENEMIES):
		if e is Enemy and r.is_ancestor_of(e) and (e as Enemy).is_alive():
			return e as Enemy
	return null


# --- Cadavres d'une partie à l'autre ---------------------------------------------------------

func test_cadavres_de_la_partie_precedente_non_restaures() -> void:
	# Partie 1 (Dust Creek) : un ennemi tué laisse un cadavre persistant à l'étage 0.
	var r1: Raid = await _start(&"perm_dust_creek", 4242)
	var e := _first_enemy(r1)
	assert_not_null(e, "un ennemi dans la partie 1")
	if e == null:
		return
	e.take_damage(1.0e9, null)
	e.finalize_death()
	await wait_process_frames(2)
	assert_eq(_count_nodes(r1, EnemyCorpse), 1, "cadavre posé dans la partie 1")
	assert_false((LootManager.corpse_records.get(0, []) as Array).is_empty(), "cadavre mémorisé (étage 0)")
	r1.abandon_raid()
	await _end(r1)
	# Partie 2 (autre carte) : aucun cadavre ne doit exister avant le premier kill.
	var r2: Raid = await _start(&"perm_station_kagami", 777)
	assert_eq(_count_nodes(r2, EnemyCorpse), 0, "aucun cadavre de la partie précédente")
	assert_eq(LootManager.get_corpse_count(), 0)


func test_butin_au_sol_et_conteneurs_de_la_partie_precedente_oublies() -> void:
	var item := LootDB.get_item(&"gold_nugget")
	assert_not_null(item)
	# État laissé par une partie précédente (étage 0).
	LootManager.ground_records[0] = [{"id": 99, "item": item, "count": 3, "pos": Vector2(64, 64)}]
	LootManager.corpse_records[0] = [{"id": 98, "enemy_kind": &"fw_raider", "pos": Vector2(96, 96),
		"pose": {}, "name": "Ancien cadavre", "preset": [], "persist_key": "corpse:0:98"}]
	LootManager.container_states["stale_key"] = {"state": 2, "entries": []}
	var r: Raid = await _start(&"perm_dust_creek", 4243)
	assert_eq(_count_nodes(r, EnemyCorpse), 0, "cadavre fantôme non recréé")
	var stale := 0
	for g: Node in get_tree().get_nodes_in_group(GroundLoot.GROUP):
		if r.is_ancestor_of(g) and (g as GroundLoot).loot_id == 99:
			stale += 1
	assert_eq(stale, 0, "butin au sol de la partie précédente non recréé (pas de duplication)")
	assert_false(LootManager.container_states.has("stale_key"), "états de conteneurs oubliés")


# --- Mort du joueur → écran de fin -------------------------------------------------------------

func test_mort_par_degats_affiche_l_ecran_de_fin() -> void:
	var r: Raid = await _start(&"perm_dust_creek", 4244)
	var p := r.player as Player
	assert_not_null(p)
	assert_false(NetHooks.active, "solo")
	# Un ennemi collé au joueur (comme sur la capture de la place du puits).
	var e := _first_enemy(r)
	if e != null:
		e.global_position = p.global_position + Vector2(40, 0)
	p.take_damage(p.hp + 1000.0, e)
	assert_false(p.is_alive(), "joueur mort")
	assert_eq(p.hp, 0.0)
	assert_null(r.end_screen, "écran de fin après le délai")
	var delay := Balance.get_float("raid", "death_screen_delay", 2.0)
	# L'écran de fin met l'arbre en pause (les attentes GUT ne s'écouleraient plus) : on attend
	# image par image (process_frame est émis même en pause), puis on relance l'arbre.
	var deadline := Time.get_ticks_msec() + int((delay + 1.5) * 1000.0)
	while r.end_screen == null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	get_tree().paused = false
	assert_true(r.is_raid_over(), "raid terminé")
	assert_not_null(r.end_screen, "écran de fin affiché après la mort")
	if r.end_screen != null:
		assert_false(r.end_screen.success)
