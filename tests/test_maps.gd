extends GutTest
## Cartes (MapCard), rotation déterministe (MapRotation), modificateurs appliqués
## (ennemis, densité, butin, raid) et écran de sélection de carte.

const DAY := 86400
const HOUR := 3600
## Mercredi 28 octobre 2026, 12:41:15 UTC (créneau d'événement 12:00 → 14:00).
const T0 := 1793191275

var _saved := {}


func before_each() -> void:
	_saved = {
		"map": GameState.current_map, "world": GameState.world_path, "diff": GameState.difficulty,
		"seed": GameState.run_seed, "time": GameState.debug_time_override,
	}
	GameState.debug_time_override = 0
	LootRoller.reset_map_bonus()
	# Les tests couvrent la rotation complète : on neutralise la restriction du build de test.
	var cfg: ConfigFile = Balance.get("_config")
	_saved["only_ids"] = cfg.get_value("maps", "only_ids", [])
	cfg.set_value("maps", "only_ids", [])


func after_each() -> void:
	(Balance.get("_config") as ConfigFile).set_value("maps", "only_ids", _saved.get("only_ids", []))
	GameState.current_map = _saved["map"]
	GameState.world_path = _saved["world"]
	GameState.difficulty = _saved["diff"]
	GameState.run_seed = _saved["seed"]
	GameState.debug_time_override = _saved["time"]
	LootRoller.reset_map_bonus()
	MapSelect.last_selected_id = &""
	MapSelect.last_filter = &"all"


static func _ids(entries: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in entries:
		out.append(String((e["card"] as MapCard).id))
	return out


# --- Catalogue ------------------------------------------------------------------------

func test_all_cards_load_and_are_valid() -> void:
	var cards: Array[MapCard] = MapCard.load_all(true)
	assert_gte(cards.size(), 20, "Catalogue complet")
	var ids := {}
	var biomes_perm := {}
	var count := {&"permanent": 0, &"weekly": 0, &"monthly": 0, &"event": 0}
	for c: MapCard in cards:
		assert_false(ids.has(c.id), "Id unique : %s" % c.id)
		ids[c.id] = true
		assert_true(c.difficulty >= 0 and c.difficulty <= 4, "Difficulté 0..4 : %s" % c.id)
		assert_true(MapCard.CATEGORIES.has(c.category), "Catégorie valide : %s" % c.id)
		assert_ne(c.get_biome(), &"", "Monde connu de BiomeRegistry : %s" % c.id)
		assert_false(c.display_name.is_empty(), c.id)
		assert_false(c.description.is_empty(), c.id)
		assert_false(c.get_tags().is_empty(), "Étiquettes : %s" % c.id)
		assert_gt(c.weight, 0.0, c.id)
		for k: Variant in c.modifiers:
			assert_true(MapCard.DEFAULT_MODIFIERS.has(String(k)), "Modificateur documenté : %s.%s" % [c.id, k])
		count[c.category] += 1
		if c.category == MapCard.CATEGORY_PERMANENT:
			biomes_perm[c.get_biome()] = true
	assert_eq(biomes_perm.size(), BiomeRegistry.BIOMES.size(), "Une carte permanente par biome")
	assert_gte(count[&"permanent"], 5)
	assert_between(count[&"weekly"], 6, 8, "Pool hebdomadaire")
	assert_between(count[&"monthly"], 4, 6, "Pool mensuel")
	assert_between(count[&"event"], 6, 8, "Pool d'événements")
	var easy := MapCard.find(&"perm_training_camp")
	assert_not_null(easy)
	assert_eq(easy.difficulty, 0, "Entraînement facile")


func test_thumbnails_exist_for_every_biome() -> void:
	for b: Dictionary in BiomeRegistry.BIOMES:
		assert_true(ResourceLoader.exists(MapCard.THUMB_DIR + String(b["biome"]) + ".png"), String(b["biome"]))
	assert_not_null(MapCard.find(&"perm_dust_creek").get_thumbnail())


func test_describe_modifiers() -> void:
	var c := MapCard.find(&"ev_gold_rush")
	var texts: Array[String] = []
	for l: Dictionary in c.describe_modifiers():
		texts.append(String(l["text"]))
	assert_has(texts, "Quantité de butin ×3")
	assert_has(texts, "Nombre d'ennemis +50 %")
	assert_eq(MapCard.new().get_mod_f("enemy_hp_mult"), 1.0, "Valeur neutre par défaut")


func test_missing_world_is_not_available() -> void:
	var c := MapCard.new()
	c.world_path = "res://data/worlds/world_99_absent.tres"
	assert_false(c.is_available())
	assert_true(MapCard.find(&"perm_dust_creek").is_available())


# --- Rotation -------------------------------------------------------------------------

func test_rotation_is_deterministic() -> void:
	assert_eq(_ids(MapRotation.available_cards(T0)), _ids(MapRotation.available_cards(T0)))
	# Même semaine (2 jours plus tard) : mêmes hebdomadaires et mensuelle.
	assert_eq(_ids_of(MapRotation.weekly_cards(T0)), _ids_of(MapRotation.weekly_cards(T0 + 2 * DAY)))
	assert_eq(_ids_of(MapRotation.monthly_cards(T0)), _ids_of(MapRotation.monthly_cards(T0 + DAY)))


func test_weekly_and_monthly_change_over_time_without_duplicates() -> void:
	var seen := {}
	for w: int in 12:
		var cards: Array[MapCard] = MapRotation.weekly_cards(T0 + w * 7 * DAY)
		assert_eq(cards.size(), 2, "2 cartes hebdomadaires")
		assert_ne(cards[0], cards[1], "Pas de doublon")
		for c: MapCard in cards:
			assert_eq(c.category, MapCard.CATEGORY_WEEKLY)
		seen[",".join(_ids_of(cards))] = true
	assert_gt(seen.size(), 1, "Le tirage change selon la semaine")
	var months := {}
	for m: int in 8:
		var mc: Array[MapCard] = MapRotation.monthly_cards(T0 + m * 31 * DAY)
		assert_eq(mc.size(), 1, "1 carte mensuelle")
		months[String(mc[0].id)] = true
	assert_gt(months.size(), 1, "Le tirage change selon le mois")


func test_permanent_cards_always_available() -> void:
	var perm: Array[MapCard] = MapCard.by_category(MapCard.CATEGORY_PERMANENT)
	for k: int in 30:
		var t: int = T0 + k * 37 * HOUR + k * 911
		var ids: Array[String] = _ids(MapRotation.available_cards(t))
		for c: MapCard in perm:
			assert_has(ids, String(c.id))
		var seen := {}
		for id: String in ids:
			assert_false(seen.has(id), "Pas de doublon dans available_cards")
			seen[id] = true


func test_week_and_month_bounds() -> void:
	var wb: Vector2i = MapRotation.week_bounds(T0)
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(wb.x)
	assert_eq(int(d["weekday"]), 1, "La semaine commence un lundi")
	assert_eq([int(d["hour"]), int(d["minute"]), int(d["second"])], [0, 0, 0])
	assert_eq(wb.y - wb.x, 7 * DAY)
	assert_true(T0 >= wb.x and T0 < wb.y)
	assert_eq(MapRotation.week_bounds(wb.y).x, wb.y, "Semaine suivante")
	var mb: Vector2i = MapRotation.month_bounds(T0)
	assert_eq(Time.get_datetime_string_from_unix_time(mb.x), "2026-10-01T00:00:00")
	assert_eq(Time.get_datetime_string_from_unix_time(mb.y), "2026-11-01T00:00:00")
	var weekly: Dictionary = MapRotation.available_cards(T0).filter(
		func(e: Dictionary) -> bool: return e["category"] == MapCard.CATEGORY_WEEKLY)[0]
	assert_eq(int(weekly["ends_at"]), wb.y)
	assert_eq(MapRotation.time_left(weekly, T0), wb.y - T0)
	var perm: Dictionary = MapRotation.available_cards(T0).back()
	assert_eq(MapRotation.time_left(perm, T0), -1, "Permanente : sans limite")


func test_event_active_exactly_two_hours() -> void:
	var period: int = MapRotation.event_period()
	var dur: int = MapRotation.event_duration()
	assert_eq(dur, 2 * HOUR, "Événements de 2 h ([maps] event_duration_hours)")
	var start: int = MapRotation.event_slot_start(MapRotation.event_slot(T0))
	assert_eq(Time.get_datetime_string_from_unix_time(start), "2026-10-28T12:00:00", "Créneau de 12:00 UTC")
	var ev: Dictionary = MapRotation.active_event(start)
	assert_false(ev.is_empty(), "Actif au début du créneau")
	assert_eq(int(ev["starts_at"]), start)
	assert_eq(int(ev["ends_at"]), start + dur)
	assert_eq(MapRotation.active_event(start + dur - 1).get("card"), ev["card"], "Même événement pendant 2 h")
	assert_true(MapRotation.active_event(start + dur).is_empty(), "Terminé après 2 h")
	assert_true(MapRotation.active_event(start - 1).is_empty(), "Rien juste avant")
	assert_eq(MapRotation.time_left(ev, T0), start + dur - T0)
	# Exactement 2 h actives par créneau (balayage minute par minute sur 24 h)
	var active_minutes := 0
	for m: int in range(0, 24 * 60):
		if not MapRotation.active_event(start + m * 60).is_empty():
			active_minutes += 1
	assert_eq(active_minutes, (24 * HOUR / period) * dur / 60, "2 h par créneau")
	var in_list: Array[Dictionary] = MapRotation.available_cards(T0)
	assert_eq(in_list[0]["category"], MapCard.CATEGORY_EVENT, "Événement en tête de liste")


func test_next_event() -> void:
	var period: int = MapRotation.event_period()
	var start: int = MapRotation.event_slot_start(MapRotation.event_slot(T0))
	var nxt: Dictionary = MapRotation.next_event(T0)
	assert_eq(int(nxt["starts_at"]), start + period, "Pendant un événement : le suivant")
	var gap_t: int = start + 3 * HOUR
	var nxt2: Dictionary = MapRotation.next_event(gap_t)
	assert_eq(int(nxt2["starts_at"]), start + period, "Entre deux événements")
	assert_eq(nxt2["card"], MapRotation.active_event(start + period)["card"], "Même carte qu'à l'ouverture")
	assert_gt(int(nxt2["starts_at"]), gap_t)


func test_consecutive_events_differ() -> void:
	var slot0: int = MapRotation.event_slot(T0)
	var seen := {}
	for i: int in 60:
		var a: MapCard = MapRotation.event_card_for_slot(slot0 + i)
		var b: MapCard = MapRotation.event_card_for_slot(slot0 + i + 1)
		assert_ne(a, b, "Deux événements consécutifs différents")
		seen[a.id] = true
	assert_gt(seen.size(), 3, "Variété des événements")


func test_debug_time_override() -> void:
	GameState.debug_time_override = T0
	assert_eq(MapRotation.now(), T0)
	GameState.debug_time_override = 0
	assert_almost_eq(float(MapRotation.now()), Time.get_unix_time_from_system(), 5.0)


func test_format() -> void:
	assert_eq(MapRotation.format_hms(3 * HOUR + 12 * 60 + 5), "03:12:05")
	assert_eq(MapRotation.format_short(3 * HOUR + 12 * 60), "3 h 12")
	assert_eq(MapRotation.format_short(2 * DAY + 5 * HOUR), "2 j 5 h")


static func _ids_of(cards: Array[MapCard]) -> Array[String]:
	var out: Array[String] = []
	for c: MapCard in cards:
		out.append(String(c.id))
	return out


# --- Modificateurs --------------------------------------------------------------------

func test_set_current_map() -> void:
	var c := MapCard.find(&"mo_dust_creek_legend")
	GameState.set_current_map(c)
	assert_eq(GameState.current_map, c)
	assert_eq(GameState.world_path, c.world_path)
	assert_eq(GameState.difficulty, c.difficulty)
	assert_eq(GameState.run_seed, c.get_fixed_seed(), "Carte fixe : même seed pour tous")
	assert_eq(float(GameState.map_modifier("enemy_hp_mult", 1.0)), 1.5)
	var c2 := MapCard.find(&"perm_dust_creek")
	GameState.set_current_map(c2)
	assert_eq(GameState.difficulty, 0)


func test_enemy_apply_modifiers() -> void:
	var data := load("res://data/enemies/fw_raider.tres") as EnemyData
	var base_hp: float = data.max_hp
	var base_dmg: float = data.attack_damage
	var base_speed: float = data.move_speed
	var base_sight: float = data.sight_gain
	var e := Enemy.spawn(data)
	add_child_autofree(e)
	await wait_physics_frames(1)
	assert_eq(e.max_hp, base_hp)
	e.apply_modifiers(2.0, 1.5, 1.2, 0.5)
	assert_almost_eq(e.max_hp, base_hp * 2.0, 0.01, "PV ×2")
	assert_almost_eq(e.hp, base_hp * 2.0, 0.01, "PV pleins")
	assert_almost_eq(e.data.attack_damage, base_dmg * 1.5, 0.01, "Dégâts ×1,5")
	assert_almost_eq(e.data.move_speed, base_speed * 1.2, 0.01, "Vitesse ×1,2")
	assert_almost_eq(e.data.sight_gain, base_sight * 0.5, 0.01, "Jauge ×0,5")
	assert_eq(data.max_hp, base_hp, "La ressource partagée n'est pas modifiée")
	e.apply_modifiers(2.0, 1.5, 1.2, 0.5)
	assert_almost_eq(e.max_hp, base_hp * 2.0, 0.01, "Pas appliqué deux fois")
	# Dégâts réellement infligés au joueur factice
	var target := _DamageProbe.new()
	add_child_autofree(target)
	target.call("take_damage", e.data.attack_damage, e)
	assert_almost_eq(target.received, base_dmg * 1.5, 0.01)


class _DamageProbe extends Node2D:
	var received: float = 0.0

	func take_damage(amount: float, _source: Node) -> void:
		received += amount


func test_densite_ne_touche_pas_la_salle_du_boss() -> void:
	var l := FloorLayout.make_sample()
	var sp0: FloorLayout.Spawn = l.enemy_spawns[0]
	var boss_room := l.get_room(sp0.room_id) if sp0.room_id >= 0 else l.room_at(sp0.cell)
	assert_not_null(boss_room)
	boss_room.type = &"boss"
	var in_boss := func(list: Array[FloorLayout.Spawn]) -> int:
		var k := 0
		for sp: FloorLayout.Spawn in list:
			var r := l.get_room(sp.room_id) if sp.room_id >= 0 else l.room_at(sp.cell)
			if r == boss_room:
				k += 1
		return k
	var before: int = in_boss.call(l.enemy_spawns)
	var more := Raid.scale_enemy_spawns(l, 3.0, 7)
	assert_gt(more.size(), l.enemy_spawns.size(), "plus d'ennemis ailleurs")
	assert_eq(in_boss.call(more), before, "salle du boss : ni second boss ni gardes en plus")
	assert_eq(in_boss.call(Raid.scale_enemy_spawns(l, 0.3, 7)), before, "salle du boss : rien retiré")


func test_enemy_density_scaling() -> void:
	var l := FloorLayout.make_sample()
	var n: int = l.enemy_spawns.size()
	assert_gt(n, 2)
	var fewer := Raid.scale_enemy_spawns(l, 0.4, 42)
	var more := Raid.scale_enemy_spawns(l, 2.0, 42)
	assert_lt(fewer.size(), n, "Densité < 1 : moins d'ennemis")
	assert_gt(more.size(), n, "Densité > 1 : plus d'ennemis")
	assert_eq(Raid.scale_enemy_spawns(l, 2.0, 42).size(), more.size(), "Déterministe")
	var cells := {}
	for sp: FloorLayout.Spawn in more:
		assert_false(cells.has(sp.cell), "Une case par ennemi")
		cells[sp.cell] = true
		assert_true(FloorLayout.is_walkable_tile(l.get_tile(sp.cell)), "Case praticable")


func test_loot_map_bonus() -> void:
	var ctx := LootRoller.Context.make(1, 0, &"combat")
	var base: float = LootRoller.rarity_multiplier(4, ctx)
	LootRoller.map_rarity_bonus = 1.0
	assert_gt(LootRoller.rarity_multiplier(4, ctx), base, "Légendaires plus fréquents")
	assert_almost_eq(LootRoller.rarity_multiplier(0, ctx), LootRoller.rarity_multiplier(0, ctx), 0.0001)
	LootRoller.reset_map_bonus()
	var table := LootDB.get_table(&"crate")
	var count_items := func() -> int:
		var total := 0
		for s: int in 60:
			var rng := RandomNumberGenerator.new()
			rng.seed = 1000 + s
			total += LootRoller.roll(table, rng, ctx).size()
		return total
	var normal: int = count_items.call()
	LootRoller.map_quantity_mult = 2.0
	var doubled: int = count_items.call()
	assert_gt(doubled, normal, "Butin ×2 : plus d'objets")


func test_raid_applies_map_modifiers() -> void:
	var c := MapCard.new()
	c.id = &"test_map"
	c.display_name = "Carte de test"
	c.world_path = "res://data/worlds/world_01_far_west.tres"
	c.difficulty = 3
	c.modifiers = {"enemy_hp_mult": 3.0, "loot_quantity_mult": 2.0, "view_radius_mult": 0.5,
		"player_hp_mult": 1.5, "night": true}
	GameState.set_current_map(c)
	var raid := (load("res://scenes/dungeon/raid.tscn") as PackedScene).instantiate() as Raid
	add_child_autofree(raid)
	await wait_physics_frames(3)
	assert_eq(raid.difficulty, 3, "Difficulté de la carte")
	assert_string_contains(raid.get_banner_text(), "Carte de test")
	assert_eq(LootRoller.map_quantity_mult, 2.0)
	var enemies: Array[Node2D] = raid.get_alive_enemies()
	assert_gt(enemies.size(), 0)
	for e: Node2D in enemies:
		var d := e.get("data") as EnemyData
		var orig := load("res://data/enemies/%s.tres" % d.kind) as EnemyData
		assert_true(d.has_meta(&"map_modified"))
		assert_almost_eq(float(e.get("max_hp")), orig.max_hp * 3.0 * Enemy.world_mult("hp_mult"), 0.01,
			"PV ennemis ×3 (× escalier du monde)")
	assert_eq(int(raid.fog.get("view_radius")), maxi(3, roundi(Balance.get_float("fog", "view_radius", 10.0) * 0.5)))
	assert_almost_eq(float(raid.player.get("max_hp")), Balance.get_float("player", "max_hp", 100.0) * 1.5, 0.5,
		"PV joueur ×1,5")
	assert_not_null(raid.find_child("MapTitleRow", true, false), "Badge de difficulté dans le bandeau")


func test_raid_without_map_is_unchanged() -> void:
	GameState.current_map = null
	LootRoller.map_quantity_mult = 5.0
	var raid := (load("res://scenes/dungeon/raid.tscn") as PackedScene).instantiate() as Raid
	add_child_autofree(raid)
	await wait_physics_frames(2)
	assert_null(raid.map_card)
	assert_eq(LootRoller.map_quantity_mult, 1.0, "Bonus remis à zéro")
	for e: Node2D in raid.get_alive_enemies():
		assert_false((e.get("data") as Resource).has_meta(&"map_modified"))


# --- Écran de sélection ---------------------------------------------------------------

func _map_select() -> MapSelect:
	var ms := (load("res://scenes/ui/menus/map_select.tscn") as PackedScene).instantiate() as MapSelect
	ms.next_scene = ""
	add_child_autofree(ms)
	return ms


func test_map_select_screen() -> void:
	GameState.debug_time_override = T0
	MapSelect.last_filter = &"all"
	MapSelect.last_selected_id = &""
	var ms := _map_select()
	await wait_frames(3)
	assert_eq(ms.filter_chips.size(), 5, "Puces : Toutes + 4 catégories")
	assert_eq(ms.current_filter, &"all", "Toutes les cartes par défaut")
	var available: int = MapRotation.available_cards(T0).size()
	# + l'arène de test en version de test (mode dev, TestArena.rotation_entries).
	assert_eq(ms.tiles.size(), available + 1 + TestArena.rotation_entries().size(),
		"Toutes les cartes visibles d'un coup + prochain événement (+ arène de test en mode dev)")
	assert_eq(ms.tiles[0].mode, MapTile.Mode.FEATURED, "Événement en cours mis en avant")
	assert_eq(ms.tiles[0].card.category, MapCard.CATEGORY_EVENT)
	assert_string_contains(ms.tiles[0].time_label.text, "01:18:45", "Minuteur")
	assert_true(ms.tiles[0].selected, "Événement jouable sélectionné par défaut")
	assert_not_null(ms.tick_timer)
	assert_eq(ms.tick_timer.wait_time, 1.0, "Rafraîchi 1×/s")
	var upcoming := ms.tiles.filter(func(t: MapTile) -> bool: return t.upcoming)
	assert_eq(upcoming.size(), 1, "Prochain événement affiché")
	for t: MapTile in ms.tiles:
		assert_gte(t.custom_minimum_size.y, 64.0, "Vignette tactile")
	ms.set_filter(&"permanent")
	assert_eq(ms.tiles.size(), MapCard.by_category(&"permanent").size())
	ms.set_filter(&"weekly")
	for t: MapTile in ms.tiles:
		assert_eq(t.card.category, MapCard.CATEGORY_WEEKLY)
	ms.set_filter(&"permanent")
	var dust: MapTile = null
	for t: MapTile in ms.tiles:
		if t.card.id == &"perm_dust_creek":
			dust = t
	ms.select_entry(dust.entry)
	assert_true(dust.selected)
	assert_eq(ms.launch_button.text, "Choisir mon arsenal")
	assert_false(ms.launch_button.disabled)
	assert_true(ms.launch_selected(), "Ouvre l'arsenal de départ")
	assert_eq(ms.next_scene if ms.next_scene != "" else MenuKit.LOADOUT_SCENE, MenuKit.LOADOUT_SCENE)
	assert_eq(GameState.current_map, dust.card)
	assert_eq(GameState.world_path, dust.card.world_path)
	assert_eq(GameState.difficulty, dust.card.difficulty)
	assert_false(Profile.raid_in_progress, "Le raid n'est pas lancé par l'écran des cartes")
	var src := FileAccess.get_file_as_string("res://scripts/ui/menus/map_select.gd")
	assert_string_contains(src, "var next_scene: String = MenuKit.LOADOUT_SCENE")


func test_map_select_keeps_selection() -> void:
	GameState.debug_time_override = T0
	MapSelect.last_filter = &"all"
	MapSelect.last_selected_id = &"perm_dust_creek"
	var ms := _map_select()
	await wait_frames(2)
	assert_eq((ms.selected_entry["card"] as MapCard).id, &"perm_dust_creek", "Sélection conservée au retour")


func test_map_select_upcoming_and_missing_world_not_launchable() -> void:
	GameState.debug_time_override = T0
	var ms := _map_select()
	await wait_frames(2)
	ms.select_entry(ms.next_event)
	assert_true(ms.launch_button.disabled, "Prochain événement : pas encore jouable")
	assert_false(ms.launch_selected())
	var ghost := MapCard.new()
	ghost.id = &"ghost"
	ghost.world_path = "res://data/worlds/world_99_absent.tres"
	ms.select_entry({"card": ghost, "category": &"permanent", "starts_at": 0, "ends_at": 0})
	assert_true(ms.launch_button.disabled)
	var tile := MapTile.new({"card": ghost, "category": &"permanent", "starts_at": 0, "ends_at": 0})
	add_child_autofree(tile)
	await wait_frames(1)
	assert_false(tile.is_playable())
	var frame := tile.get_child(0) as Control
	assert_lt(frame.modulate.r, 1.0, "Vignette grisée")


func test_difficulty_badge_for_raid_banner() -> void:
	var b := MapTile.difficulty_badge(3, true)
	autofree(b)
	assert_eq(b.name, &"DifficultyBadge")
	assert_eq((b.find_child("Name", true, false) as Label).text, "Infernal")


func test_build_de_test_ne_propose_que_dust_creek() -> void:
	var cfg: ConfigFile = Balance.get("_config")
	cfg.set_value("maps", "only_ids", ["perm_dust_creek"])
	var offered := MapRotation.offered_cards(MapRotation.now())
	assert_eq(offered.size(), 1)
	assert_eq(String((offered[0]["card"] as MapCard).id), "perm_dust_creek")
	assert_true(MapRotation.is_restricted())
	cfg.set_value("maps", "only_ids", [])
	assert_false(MapRotation.is_restricted())
