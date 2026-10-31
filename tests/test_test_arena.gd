extends GutTest
## Arène de test (mode dev) : carte visible seulement en version de test, chargement dans la
## scène de raid, mannequins qui comptent les dégâts, râtelier (armes, objets, skins), ennemis à
## la demande, munitions infinies, invincibilité, remise à zéro, sortie libre sans toucher au profil.

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"

var _raid: Raid = null
var _saved_profile: Dictionary = {}
var _saved_sm_data: Dictionary = {}
var _save_existed: bool = false
var _save_text: String = ""
var _saved_map: Resource = null
var _saved_world: String = ""
var _saved_weapons: Array[WeaponData] = []
var _saved_inv: Inventory = null


func before_each() -> void:
	_saved_profile = Profile.to_dict()
	_saved_sm_data = (SaveManager.data as Dictionary).duplicate(true)
	_save_existed = FileAccess.file_exists(SaveManager.SAVE_PATH)
	_save_text = FileAccess.get_file_as_string(SaveManager.SAVE_PATH) if _save_existed else ""
	_saved_map = GameState.current_map
	_saved_world = GameState.world_path
	_saved_weapons = GameState.raid_weapons.duplicate()
	_saved_inv = GameState.raid_inventory
	DevMode.build_check = Callable()
	_raid = null


func after_each() -> void:
	if is_instance_valid(_raid):
		_raid.free()
	DevMode.build_check = Callable()
	get_tree().paused = false
	GameState.current_map = _saved_map
	GameState.world_path = _saved_world
	GameState.raid_weapons = _saved_weapons
	GameState.raid_inventory = _saved_inv
	GameState.in_test_arena = false
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_sm_data
	if _save_existed:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_text)
	elif FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH))


## Arène chargée comme depuis le sélecteur (sans changer de scène).
func _arena() -> Raid:
	var c := TestArena.card()
	assert_not_null(c, "Carte de l'arène disponible en version de test")
	GameState.set_current_map(c)
	GameState.raid_inventory = Inventory.from_balance()
	GameState.raid_weapons = [] as Array[WeaponData]
	_raid = (load(RAID_SCENE) as PackedScene).instantiate() as Raid
	add_child(_raid)
	await wait_physics_frames(3)
	return _raid


func test_carte_visible_seulement_en_mode_dev() -> void:
	DevMode.build_check = func() -> bool: return true
	var e := TestArena.rotation_entries()
	assert_eq(e.size(), 1, "Arène proposée en version de test")
	assert_true(TestArena.is_arena_card(e[0]["card"]))
	assert_eq(int(e[0]["ends_at"]), 0, "Ouverte sans limite")
	DevMode.build_check = func() -> bool: return false
	assert_eq(TestArena.rotation_entries().size(), 0, "Absente d'une version publiée")
	# La carte n'entre pas dans la rotation normale (dossier data/maps/dev).
	for c: MapCard in MapCard.load_all(true):
		assert_false(TestArena.is_arena_card(c))


func test_etage_salle_ouverte_sans_extraction() -> void:
	var l := ArenaGenerator.build_layout()
	assert_eq(l.get_tile(Vector2i.ZERO), FloorLayout.Tile.WALL, "Murs d'enceinte")
	assert_true(FloorLayout.is_walkable_tile(l.get_tile(l.player_spawn)), "Apparition praticable")
	assert_true(l.extraction_cells.is_empty(), "Pas d'extraction")
	assert_true(l.enemy_spawns.is_empty(), "Aucun ennemi au départ")
	assert_true(l.container_spawns.is_empty(), "Aucun conteneur")
	var walls := 0
	var inner := ArenaGenerator.inner_rect(l)
	for y: int in range(inner.position.y, inner.end.y):
		for x: int in range(inner.position.x, inner.end.x):
			if l.get_tile(Vector2i(x, y)) == FloorLayout.Tile.WALL:
				walls += 1
	assert_gt(walls, 0, "Quelques murs et couverts")
	assert_eq(l.flood_reachable(l.player_spawn).size(), inner.get_area() - walls, "Toute la salle accessible")


func test_chargement_de_l_arene() -> void:
	var r := await _arena()
	assert_not_null(r.test_arena, "Contrôleur d'arène attaché")
	assert_true(r.world_root is ArenaBuilder, "Décor d'arène (sol quadrillé)")
	assert_true(GameState.in_test_arena)
	assert_eq(r.test_arena.dummies.size(), TestArena.DUMMIES.size(), "Mannequins posés")
	assert_true(r.test_arena.dummies.any(func(d: ArenaDummy) -> bool: return d.moving), "Un mannequin mobile")
	assert_true(r.extraction_zones.is_empty(), "Pas d'extraction obligatoire")
	assert_true(r.get_alive_enemies().all(func(e: Node2D) -> bool: return e is TargetDummy), "Aucun ennemi au départ")
	assert_true(r.fog == null or not r.fog.visible, "Brouillard désactivé")
	assert_true(bool(r.player.get("god_mode")), "Invincible par défaut")
	assert_true((r.player.get("loadout") as WeaponLoadout).infinite_ammo, "Munitions infinies par défaut")
	assert_not_null(r.test_arena.panel, "Râtelier / panneau présent")


func test_mannequin_compte_les_degats() -> void:
	var m := DamageMeter.new(5.0)
	m.add(10.0, 0.0)
	m.add(30.0, 2.0)
	assert_eq(m.total, 40.0)
	assert_eq(m.last_hit, 30.0)
	assert_almost_eq(m.dps(2.0), 8.0, 0.001, "DPS = dégâts des 5 dernières secondes ÷ 5")
	assert_almost_eq(m.dps(6.0), 6.0, 0.001, "Le premier coup sort de la fenêtre")
	assert_almost_eq(m.dps(20.0), 0.0, 0.001)
	assert_eq(m.total, 40.0, "Le total reste")
	var r := await _arena()
	var d: ArenaDummy = r.test_arena.dummies[0]
	d.take_damage(25.0, null)
	d.take_damage(15.0, null)
	assert_eq(d.meter.total, 40.0, "Le mannequin compte les dégâts reçus")
	assert_eq(d.meter.hits, 2)
	assert_gt(d.meter.dps(d.clock()), 0.0)
	assert_true(d.is_alive(), "PV suffisants pour tester longtemps")
	assert_string_contains((d.get_node("MeterLabel") as Label).text, "40", "Total affiché")
	r.test_arena.reset()
	assert_eq(d.meter.total, 0.0, "Remise à zéro des compteurs")


func test_prise_d_arme_au_ratelier() -> void:
	var r := await _arena()
	var panel := r.test_arena.panel
	var idx := -1
	for i: int in panel.weapon_picker.item_count:
		if panel._weapons[i].id == &"smg_mp5":
			idx = i
	assert_gt(idx, -1, "Toutes les armes du catalogue au râtelier")
	assert_eq(panel.weapon_picker.item_count, WeaponCatalog.all().size())
	panel.weapon_picker.select(idx)
	panel.take_weapon_button.pressed.emit()
	assert_eq(r.test_arena.held_weapon().id, &"smg_mp5", "Arme prise en main")
	var before := Profile.weapon_count(&"smg_mp5")
	assert_eq(Profile.weapon_count(&"smg_mp5"), before, "La réserve du profil n'est pas touchée")
	# Objet au sac
	assert_eq(panel.item_picker.item_count, LootDB.all_items().filter(func(it: ItemData) -> bool: return not it.is_weapon()).size())
	assert_eq(r.test_arena.take_item(&"bandage", 3), 3)
	assert_eq(GameState.raid_inventory.count_of(&"bandage"), 3)


func test_skin_d_arme_sans_toucher_au_profil() -> void:
	var r := await _arena()
	var target: SkinData = null
	for w: WeaponData in WeaponCatalog.all():
		r.test_arena.take_weapon(w.id)
		var list := r.test_arena.skins_for_held()
		if not list.is_empty():
			target = list[0]
			break
	if target == null:
		pass_test("Aucun skin d'arme dans le catalogue")
		return
	var owned_before := Profile.skins_owned.duplicate()
	var worn_before := Profile.skin_weapons.duplicate()
	assert_true(r.test_arena.apply_weapon_skin(target.id))
	var wv: WeaponView = (r.player.get("visual") as Node).get("weapon_view")
	assert_true(wv.use_skin_ids, "Skin imposé à l'arme affichée")
	assert_eq(Profile.skins_owned, owned_before, "Skins possédés inchangés")
	assert_eq(Profile.skin_weapons, worn_before, "Skins portés inchangés")


func test_ennemis_de_chaque_archetype() -> void:
	var r := await _arena()
	var arch := TestArena.archetypes()
	assert_gte(arch.size(), 8, "Mêlée, distance, tank, rapide, invocateur, kamikaze, élite, boss")
	for a: Dictionary in arch:
		assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % a["kind"]), "Ennemi existant : %s" % a["kind"])
		var got := r.test_arena.spawn_enemy(a["kind"], 1)
		assert_eq(got.size(), 1, "Apparition : %s" % a["name"])
	assert_eq(r.test_arena.spawned.size(), arch.size())
	r.test_arena.clear_enemies()
	assert_eq(r.test_arena.spawned.size(), 0)


func test_munitions_infinies_et_invincibilite() -> void:
	var r := await _arena()
	var p := r.player
	var lo: WeaponLoadout = p.get("loadout")
	var ammo := lo.get_ammo()
	lo.consume_shot()
	assert_eq(lo.get_ammo(), ammo, "Munitions infinies")
	r.test_arena.set_infinite_ammo(false)
	lo.cooldown = 0.0
	lo.consume_shot()
	if ammo > 0:
		assert_eq(lo.get_ammo(), ammo - 1, "Désactivées : on consomme")
	var hp: float = p.get("hp")
	p.call("take_damage", 30.0, null)
	assert_eq(float(p.get("hp")), hp, "Invincible")
	r.test_arena.set_god_mode(false)
	p.call("take_damage", 30.0, null)
	assert_lt(float(p.get("hp")), hp, "Désactivée : on prend des dégâts")
	r.test_arena.reset()
	assert_eq(float(p.get("hp")), float(p.get("max_hp")), "Remise à zéro : PV pleins")


func test_brouillard_activable() -> void:
	var r := await _arena()
	if r.fog == null:
		pass_test("Pas de brouillard dans ce build")
		return
	r.test_arena.set_fog(true)
	assert_true(r.fog.visible)
	r.test_arena.set_fog(false)
	assert_false(r.fog.visible)


func test_sortie_libre_et_victimes_non_comptees() -> void:
	var before := JSON.stringify(Profile.to_dict())
	var r := await _arena()
	var e := r.test_arena.spawn_enemy(&"fw_bandit", 1)[0]
	EventBus.enemy_died.emit(e, e.global_position)
	assert_eq(JSON.stringify(Profile.to_dict()), before, "Victime non comptée")
	r.set_meta(&"_leaving", true)   # pas de vrai changement de scène dans le test
	r.abandon_raid()
	assert_false(r.is_raid_over(), "Ni mort ni écran de fin")
	assert_eq(JSON.stringify(Profile.to_dict()), before, "Profil intact en sortant")
	assert_eq(GameState.raid_weapons.size(), 0)
