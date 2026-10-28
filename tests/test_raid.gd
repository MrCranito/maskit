extends GutTest
## Tests de la scène de raid : assemblage avec les modules présents (replis sinon),
## placement du joueur, ennemis, changement d'étage avec conservation de l'état.

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const GENERATOR_PATH := "res://scripts/dungeon/dungeon_generator.gd"

var _raid: Raid = null
var _saved_debug: bool = false
# Isolation du profil : fin de raid = Profile.finish_* (qui sauvegarde).
var _saved_profile: Dictionary = {}
var _saved_sm_data: Dictionary = {}
var _save_existed: bool = false
var _save_text: String = ""


func before_each() -> void:
	_saved_debug = GameState.debug_enabled
	GameState.debug_enabled = false
	_saved_profile = Profile.to_dict()
	_saved_sm_data = (SaveManager.data as Dictionary).duplicate(true)
	_save_existed = FileAccess.file_exists(SaveManager.SAVE_PATH)
	_save_text = FileAccess.get_file_as_string(SaveManager.SAVE_PATH) if _save_existed else ""
	_raid = (load(RAID_SCENE) as PackedScene).instantiate() as Raid
	add_child_autofree(_raid)
	await wait_physics_frames(3)


func after_each() -> void:
	GameState.debug_enabled = _saved_debug
	get_tree().paused = false
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_sm_data
	if _save_existed:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_text)
	elif FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH))


func test_scene_instantiates_with_available_modules() -> void:
	assert_not_null(_raid, "La scène de raid s'instancie")
	assert_not_null(_raid.layout, "Un étage est chargé")
	assert_true(_raid.has_floor(0), "L'étage 0 existe")
	assert_not_null(_raid.world_root, "Le décor est construit (WorldBuilder ou secours)")
	assert_not_null(_raid.nav_region, "La navigation est cuite")
	assert_gt(_raid.nav_region.navigation_polygon.get_polygon_count(), 0, "Navigation non vide")
	assert_eq(_raid.get_doors().size(), _raid.layout.doors.size(), "Une porte par porte du layout")
	assert_eq(_raid.uses_generator, ResourceLoader.exists(GENERATOR_PATH) and _raid.world != null)


func test_player_on_spawn_cell() -> void:
	assert_true(is_instance_valid(_raid.player), "Le joueur existe")
	assert_eq(_raid.get_player_cell(), _raid.layout.player_spawn, "Joueur sur player_spawn")
	assert_false(_raid.get_banner_text().is_empty(), "Bandeau monde/étage renseigné")
	assert_eq(_raid.get_current_room_name(), _raid.layout.room_at(_raid.layout.player_spawn).name)


func test_enemies_exist_and_are_fog_hideable() -> void:
	var units := get_tree().get_nodes_in_group(&"enemy_units")
	assert_gt(units.size(), 0, "Des ennemis existent")
	assert_eq(_raid.get_alive_enemies().size(), _raid.layout.enemy_spawns.size(), "Un ennemi par point d'apparition")
	for e: Node2D in _raid.get_alive_enemies():
		assert_true(e.is_in_group(&"fog_hideable"), "%s dans fog_hideable" % e.name)


func test_unknown_enemy_kind_falls_back_to_grunt() -> void:
	var data: Resource = Raid.load_enemy_data(&"kind_qui_n_existe_pas")
	assert_not_null(data)
	assert_eq(data.get("kind"), &"masked_grunt")


func test_door_query_reflects_door_state() -> void:
	var closed: Node2D = null
	for d: Node2D in _raid.get_doors():
		if not d.call("is_open") and not d.call("is_locked"):
			closed = d
			break
	if closed == null:
		pending("Aucune porte fermée sur cet étage")
		return
	var cell: Vector2i = closed.get("cell")
	assert_false(_raid.is_door_cell_open(cell))
	closed.call("open")
	assert_true(_raid.is_door_cell_open(cell))


func test_unavailable_floor_shows_message() -> void:
	var missing: FloorLayout.Stairs = null
	for st: FloorLayout.Stairs in _raid.layout.stairs:
		if not _raid.has_floor(st.target_floor):
			missing = st
	if missing == null:
		pending("Tous les escaliers mènent à un étage existant")
		return
	var before := _raid.current_floor
	_raid._on_stairs_entered(missing)
	assert_eq(_raid.current_floor, before, "Pas de changement d'étage")
	assert_eq(_raid.get_toast_text(), "Étage non disponible")


func test_floor_change_preserves_state() -> void:
	var st: FloorLayout.Stairs = null
	for s: FloorLayout.Stairs in _raid.layout.stairs:
		if _raid.has_floor(s.target_floor):
			st = s
			break
	if st == null:
		pending("Générateur absent ou aucun escalier vers un étage existant : changement d'étage non testable")
		return
	var start_floor := _raid.current_floor
	# Altère l'état : un ennemi blessé, une porte ouverte.
	var enemies := _raid.get_alive_enemies()
	var wounded_pos := Vector2.ZERO
	if not enemies.is_empty():
		var e: Node2D = enemies[0]
		e.set("hp", float(e.get("max_hp")) * 0.5)
		wounded_pos = e.global_position
	var opened_cell := Vector2i(-1, -1)
	for d: Node2D in _raid.get_doors():
		if not d.call("is_open") and not d.call("is_locked"):
			d.call("open")
			opened_cell = d.get("cell")
			break
	var alive_before := enemies.size()

	assert_true(_raid.go_to_floor(st.target_floor, st.target_cell), "Changement d'étage")
	await wait_physics_frames(2)
	assert_eq(_raid.current_floor, st.target_floor)
	assert_ne(_raid.get_player_cell(), st.target_cell, "Joueur décalé hors de l'escalier")
	assert_true(_raid.floor_states.has(start_floor), "État de l'étage quitté sauvegardé")

	# Retour : trouver l'escalier qui ramène à l'étage de départ.
	var back: FloorLayout.Stairs = null
	for s: FloorLayout.Stairs in _raid.layout.stairs:
		if s.target_floor == start_floor:
			back = s
	assert_not_null(back, "Escalier de retour cohérent")
	if back == null:
		return
	assert_true(_raid.go_to_floor(start_floor, back.target_cell))
	await wait_physics_frames(2)
	assert_eq(_raid.get_alive_enemies().size(), alive_before, "Ennemis vivants conservés")
	if alive_before > 0:
		var found := false
		for e: Node2D in _raid.get_alive_enemies():
			if e.global_position.distance_to(wounded_pos) < 1.0:
				found = is_equal_approx(float(e.get("hp")), float(e.get("max_hp")) * 0.5)
		assert_true(found, "PV et position de l'ennemi blessé conservés")
	if opened_cell != Vector2i(-1, -1):
		assert_true(_raid.is_door_cell_open(opened_cell), "Porte ouverte conservée")


func test_capture_floor_state_counts() -> void:
	var s := _raid.capture_floor_state()
	assert_eq(s.get_enemy_count(), _raid.get_alive_enemies().size())
	assert_eq(s.doors.size(), _raid.get_doors().size())


## Mécanique de changement d'étage indépendante du générateur : on injecte un
## étage 1 synthétique (copie de la carte d'exemple, escalier de retour vers 0).
func test_floor_change_with_synthetic_floor() -> void:
	var upper := FloorLayout.make_sample()
	upper.floor_index = 1
	var st0: FloorLayout.Stairs = null
	for s: FloorLayout.Stairs in _raid.layout.stairs:
		st0 = s
		break
	if st0 == null:
		pending("Aucun escalier sur l'étage 0")
		return
	for s: FloorLayout.Stairs in upper.stairs:
		s.target_floor = _raid.current_floor
		s.target_cell = st0.cell
	var target := 99
	_raid.floors[target] = upper
	var alive_before := _raid.get_alive_enemies().size()
	_raid.get_alive_enemies()[0].set("hp", 1.0)
	var fog_before := PackedByteArray()
	if _raid.fog != null:
		fog_before = _raid.fog.call("get_state")
	assert_true(_raid.go_to_floor(target, upper.stairs[0].cell))
	await wait_physics_frames(2)
	assert_eq(_raid.current_floor, target)
	assert_eq(_raid.get_alive_enemies().size(), upper.enemy_spawns.size(), "Nouvel étage peuplé")
	assert_true(_raid.go_to_floor(0, st0.cell))
	await wait_physics_frames(2)
	assert_eq(_raid.get_alive_enemies().size(), alive_before, "Ennemis restaurés")
	var hp_one := _raid.get_alive_enemies().filter(func(e: Node2D) -> bool: return is_equal_approx(float(e.get("hp")), 1.0))
	assert_eq(hp_one.size(), 1, "PV restaurés")
	assert_eq(get_tree().get_nodes_in_group(&"player").size(), 1, "Un seul joueur")
	if _raid.fog != null:
		var fog_after: PackedByteArray = _raid.fog.call("get_state")
		var kept := true
		for i: int in fog_before.size():
			if fog_before[i] != 0 and fog_after[i] == 0:
				kept = false
				break
		assert_true(kept and fog_before.count(1) > 0, "Exploration du brouillard conservée")


# --- Extraction, mort, tourelles (refonte Exfil Rush) -----------------------------------

func test_extraction_canalisee_puis_ecran_de_fin() -> void:
	if _raid.layout.extraction_cells.is_empty():
		pending("Pas de case d'extraction sur cet étage")
		return
	assert_not_null(_raid._extraction_marker, "marqueur d'extraction au sol")
	var cell: Vector2i = _raid.layout.extraction_cells[0]
	_raid.place_player(cell)
	var t := Raid.extraction_channel_time()
	_raid._update_extraction(cell, t * 0.5)
	assert_true(_raid.is_extracting(), "canalisation en cours")
	assert_almost_eq(_raid.get_extraction_progress(), 0.5, 0.01)
	# Sortie de zone : interrompue.
	_raid._update_extraction(_raid.layout.player_spawn, 0.1)
	assert_false(_raid.is_extracting(), "interrompue hors zone")
	assert_eq(_raid.get_toast_text(), "Extraction interrompue")
	# Canalisation complète.
	_raid._update_extraction(cell, 0.01)
	_raid._update_extraction(cell, t + 0.1)
	assert_true(_raid.is_raid_over(), "raid terminé")
	assert_not_null(_raid.end_screen, "écran de fin affiché")
	assert_true(_raid.end_screen.success)
	assert_eq(_raid.end_screen.get_title_text(), "Extraction réussie")
	assert_false(Profile.raid_in_progress)
	assert_true(get_tree().paused, "jeu en pause derrière l'écran de fin")


func test_extraction_alerte_les_ennemis_proches() -> void:
	var enemies := _raid.get_alive_enemies()
	if enemies.is_empty():
		pending("Aucun ennemi")
		return
	var e: Node2D = enemies[0]
	assert_eq(_raid.alert_enemies_near(e.global_position, 50.0), _raid.get_alive_enemies().filter(
		func(o: Node2D) -> bool: return o.global_position.distance_to(e.global_position) <= 50.0).size())
	assert_gte(float(e.get("awareness")), 1.0, "ennemi alerté")


func test_mort_puis_ecran_de_fin_sans_rechargement() -> void:
	GameState.raid_inventory.add_item(LootDB.get_item(&"gold_nugget"), 2)
	_raid._finish_death()
	assert_true(_raid.is_raid_over())
	assert_not_null(_raid.end_screen)
	assert_false(_raid.end_screen.success)
	assert_eq(int(_raid.end_screen.summary.get("lost_items", 0)), 2, "butin perdu compté")
	assert_true(GameState.raid_inventory.is_empty(), "sac vidé")
	# Une seconde fin (extraction) est ignorée.
	_raid._finish_extraction()
	assert_false(_raid.end_screen.success)


func test_abandon_raid_equivaut_a_la_mort() -> void:
	var deaths := int(Profile.stats.get("deaths", 0))
	_raid.abandon_raid()
	assert_true(_raid.is_raid_over())
	assert_eq(int(Profile.stats.get("deaths", 0)), deaths + 1)
	assert_false(_raid.end_screen.success)


func test_modificateur_de_degats_sur_copies() -> void:
	var before: Array[WeaponData] = WeaponHud.read_weapons(_raid.player)
	if before.is_empty() or before[0] == null:
		pending("Joueur sans arme")
		return
	var src: WeaponData = before[0]
	var dmg := src.damage
	Raid.apply_weapon_damage_mult(_raid.player, 2.0)
	var after: Array[WeaponData] = WeaponHud.read_weapons(_raid.player)
	assert_almost_eq(after[0].damage, dmg * 2.0, 0.01, "dégâts doublés")
	assert_almost_eq(src.damage, dmg, 0.01, "ressource du catalogue intacte")


func test_tourelles_detruites_memorisees_dans_floor_state() -> void:
	var s := _raid.capture_floor_state()
	assert_eq(s.destroyed_turrets.size(), _raid.get_destroyed_turret_cells().size())
	_raid._on_turret_destroyed(Vector2i(3, 4))
	assert_true(_raid.capture_floor_state().destroyed_turrets.has(Vector2i(3, 4)))
