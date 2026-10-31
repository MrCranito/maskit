extends GutTest
## Tests de la logique pure du joueur (double stick, plus de tir automatique).


# --- Joystick : sortie --------------------------------------------------------

func test_joystick_dead_zone() -> void:
	assert_eq(TouchJoystick.compute_output(Vector2(10, 0), 100.0, 0.15), Vector2.ZERO)


func test_joystick_full_tilt_is_unit_length() -> void:
	var out: Vector2 = TouchJoystick.compute_output(Vector2(0, 250), 100.0, 0.15)
	assert_almost_eq(out.length(), 1.0, 0.001)
	assert_almost_eq(out.y, 1.0, 0.001)


func test_joystick_output_remapped_after_dead_zone() -> void:
	var out: Vector2 = TouchJoystick.compute_output(Vector2(50, 0), 100.0, 0.0)
	assert_almost_eq(out.x, 0.5, 0.001)
	# Juste après la zone morte, la sortie repart de 0 (pas de saut).
	var just: Vector2 = TouchJoystick.compute_output(Vector2(31, 0), 100.0, 0.3)
	assert_lt(just.length(), 0.05)


func test_joystick_zero_radius_is_safe() -> void:
	assert_eq(TouchJoystick.compute_output(Vector2(10, 0), 0.0, 0.1), Vector2.ZERO)


# --- Directions 8 voies -------------------------------------------------------

func test_dir8_cardinals_and_diagonals() -> void:
	assert_eq(Player.dir8_name(Vector2.RIGHT), "e")
	assert_eq(Player.dir8_name(Vector2.DOWN), "s")
	assert_eq(Player.dir8_name(Vector2.LEFT), "w")
	assert_eq(Player.dir8_name(Vector2.UP), "n")
	assert_eq(Player.dir8_name(Vector2(1, 1)), "se")
	assert_eq(Player.dir8_name(Vector2(-1, 1)), "sw")
	assert_eq(Player.dir8_name(Vector2(-1, -1)), "nw")
	assert_eq(Player.dir8_name(Vector2(1, -1)), "ne")


func test_dir8_boundaries() -> void:
	# 20° sous l'horizontale → toujours « e » ; 25° → « se » (secteurs de 45°).
	assert_eq(Player.dir8_name(Vector2.RIGHT.rotated(deg_to_rad(20))), "e")
	assert_eq(Player.dir8_name(Vector2.RIGHT.rotated(deg_to_rad(25))), "se")
	assert_eq(Player.dir8_name(Vector2.RIGHT.rotated(deg_to_rad(-170))), "w")


func test_dir8_hysteresis_keeps_previous() -> void:
	var a := Vector2.RIGHT.rotated(deg_to_rad(25))  # juste dans « se »
	assert_eq(Player.dir8_index(a, 0, deg_to_rad(7.0)), 0, "hystérésis : reste « e »")
	assert_eq(Player.dir8_index(a, 0, 0.0), 1, "sans hystérésis : « se »")
	var far := Vector2.RIGHT.rotated(deg_to_rad(40))
	assert_eq(Player.dir8_index(far, 0, deg_to_rad(7.0)), 1, "au-delà de l'hystérésis : change")


func test_dir8_zero_vector_keeps_previous() -> void:
	assert_eq(Player.dir8_index(Vector2.ZERO, 5), 5)
	assert_eq(Player.dir8_index(Vector2.ZERO), 0)


func test_dir8_names_match_anims() -> void:
	for i: int in 8:
		assert_eq(String(Player.RUN_ANIMS[i]), "run_" + Player.DIR8_NAMES[i])
		assert_eq(String(Player.IDLE_ANIMS[i]), "idle_" + Player.DIR8_NAMES[i])


# --- Déplacement --------------------------------------------------------------

func _run_velocity(input: Vector2, frames: int, start: Vector2 = Vector2.ZERO) -> Vector2:
	var v := start
	for i: int in frames:
		v = Player.step_velocity(v, input, 250.0, 2400.0, 3200.0, 18.0, 1.8, 1.0 / 60.0)
	return v


func test_velocity_reaches_max_quickly() -> void:
	var v := _run_velocity(Vector2.RIGHT, 12)  # 0,2 s
	assert_almost_eq(v.length(), 250.0, 1.0, "vitesse max atteinte en < 0,2 s")
	var early := _run_velocity(Vector2.RIGHT, 2)
	assert_gt(early.length(), 60.0, "démarrage réactif")
	assert_lt(early.length(), 250.0, "mais progressif")


func test_velocity_diagonal_constant_speed() -> void:
	var v := _run_velocity(Vector2(1, 1).normalized(), 30)
	assert_almost_eq(v.length(), 250.0, 1.0)
	# Entrée clavier diagonale non normalisée : limitée à 1.
	var v2 := _run_velocity(Vector2(1, 1), 30)
	assert_almost_eq(v2.length(), 250.0, 1.0)


func test_velocity_stops_without_sliding() -> void:
	var v := _run_velocity(Vector2.ZERO, 8, Vector2(250, 0))  # 0,13 s
	assert_eq(v, Vector2.ZERO, "arrêt net (pas de glisse excessive)")


func test_velocity_partial_stick_slower() -> void:
	var v := _run_velocity(Vector2(0.5, 0), 30)
	assert_almost_eq(v.length(), 125.0, 1.0)


# --- Bruit --------------------------------------------------------------------

func test_noise_idle_walk_fire() -> void:
	assert_eq(Player.compute_noise(0.0, 0.0, 0.35), 0.0, "immobile : silence")
	assert_almost_eq(Player.compute_noise(1.0, 0.0, 0.35), 0.35, 0.001, "marche")
	assert_almost_eq(Player.compute_noise(0.5, 0.0, 0.35), 0.175, 0.001, "marche lente")
	assert_eq(Player.compute_noise(1.0, 1.0, 0.35), 1.0, "juste après un tir")
	assert_almost_eq(Player.compute_noise(0.0, 0.5, 0.35), 0.5, 0.001, "décroissance du tir")


# --- Main / canon -------------------------------------------------------------

func test_hand_offset_follows_aim() -> void:
	var r := Player.hand_offset(Vector2.RIGHT, 24.0, 10.0)
	var l := Player.hand_offset(Vector2.LEFT, 24.0, 10.0)
	assert_gt(r.x, 0.0)
	assert_lt(l.x, 0.0)
	assert_almost_eq(r.y, -24.0, 0.001)


# --- Arme de départ -----------------------------------------------------------

func test_default_weapon_is_starter_pistol() -> void:
	var w: Resource = Player.load_default_weapon()
	assert_eq(String(w.id), String(WeaponCatalog.STARTER_ID))


func test_initial_weapons_fallback_to_starter() -> void:
	var saved: Array[WeaponData] = GameState.raid_weapons.duplicate()
	GameState.raid_weapons.clear()
	var list: Array[WeaponData] = Player.initial_weapons()
	assert_eq(list.size(), 1)
	assert_eq(String(list[0].id), String(WeaponCatalog.STARTER_ID))
	GameState.raid_weapons = saved


# --- Emplacements d'armes (WeaponLoadout, logique pure) ---------------------------

func _w(id: String, mag: int = 5, reload_time: float = 1.0, rate: float = 4.0) -> WeaponData:
	var w := WeaponData.new()
	w.id = StringName(id)
	w.magazine_size = mag
	w.reload_time = reload_time
	w.fire_rate = rate
	return w


func _loadout(list: Array) -> WeaponLoadout:
	var l := WeaponLoadout.new(3)
	l.set_weapons(list)
	return l


func test_loadout_fills_slots_full_magazines() -> void:
	var l := _loadout([_w("a", 5), _w("b", 8)])
	assert_eq(l.size(), 3)
	assert_eq(l.current, 0)
	assert_eq(l.get_ammo(), 5)
	assert_null(l.get_weapons()[2], "emplacement vide = null")
	assert_eq(l.weapon_count(), 2)


func test_loadout_switch_keeps_ammo_per_slot() -> void:
	var l := _loadout([_w("a", 5), _w("b", 8)])
	l.consume_shot()
	l.consume_shot()
	assert_eq(l.get_ammo(), 3)
	assert_true(l.switch_to(1))
	assert_eq(l.get_ammo(), 8)
	assert_true(l.switch_to(0))
	assert_eq(l.get_ammo(), 3, "munitions conservées par emplacement")


func test_loadout_switch_refuses_empty_or_invalid() -> void:
	var l := _loadout([_w("a"), null, _w("c")])
	assert_false(l.switch_to(1), "emplacement vide")
	assert_false(l.switch_to(0), "déjà sélectionné")
	assert_false(l.switch_to(7), "hors bornes")
	assert_eq(l.cycle_slot(1), 2, "suivant : saute l'emplacement vide")
	assert_eq(l.cycle_slot(-1), 2, "précédent : boucle")
	var solo := _loadout([_w("a")])
	assert_eq(solo.cycle_slot(1), -1, "une seule arme : pas de suivant")


func test_loadout_cadence() -> void:
	var l := _loadout([_w("a", 10, 1.0, 4.0)])
	assert_true(l.can_fire())
	l.consume_shot()
	assert_false(l.can_fire(), "délai de cadence")
	l.tick(0.2)
	assert_false(l.can_fire())
	l.tick(0.06)
	assert_true(l.can_fire(), "1 / 4 tirs/s = 0,25 s")


func test_loadout_reload_cycle() -> void:
	var l := _loadout([_w("a", 2, 1.0)])
	l.consume_shot()
	l.tick(1.0)
	l.consume_shot()
	assert_eq(l.get_ammo(), 0)
	assert_true(l.needs_reload())
	assert_false(l.can_fire(), "chargeur vide")
	assert_true(l.start_reload())
	assert_false(l.start_reload(), "déjà en cours")
	assert_true(l.is_reloading())
	assert_false(l.tick(0.5))
	assert_almost_eq(l.reload_progress(), 0.5, 0.001)
	assert_false(l.can_fire(), "pas de tir pendant le rechargement")
	assert_true(l.tick(0.6), "rechargement terminé")
	assert_eq(l.get_ammo(), 2)
	assert_false(l.is_reloading())


func test_loadout_reload_refused_when_full_or_unlimited() -> void:
	var l := _loadout([_w("a", 5), _w("inf", 0)])
	assert_false(l.start_reload(), "chargeur plein")
	l.switch_to(1)
	assert_eq(l.get_ammo(), -1, "chargeur 0 = illimité")
	for i: int in 50:
		l.consume_shot()
	assert_true(l.has_ammo())
	assert_false(l.start_reload())


func test_loadout_switch_cancels_reload() -> void:
	var l := _loadout([_w("a", 2, 1.0), _w("b", 3)])
	l.consume_shot()
	assert_true(l.start_reload())
	l.tick(0.5)
	assert_true(l.switch_to(1))
	assert_false(l.is_reloading(), "changement d'arme = rechargement annulé")
	l.switch_to(0)
	assert_eq(l.get_ammo(), 1, "munitions non rechargées")


func test_loadout_equip_into_current_returns_old() -> void:
	var a := _w("a", 5)
	var b := _w("b", 7)
	var l := _loadout([a])
	l.consume_shot()
	var old: WeaponData = l.equip_into_current(b)
	assert_eq(old, a, "renvoie l'arme remplacée")
	assert_eq(l.current_weapon(), b)
	assert_eq(l.get_ammo(), 7, "nouvelle arme chargée")
	l.switch_to(1)  # vide : refusé
	assert_eq(l.current, 0)
	var l2 := WeaponLoadout.new(3)
	assert_null(l2.equip_into_current(a), "emplacement vide → null")


func test_loadout_carried_ids() -> void:
	var l := _loadout([_w("a"), null, _w("c")])
	var ids: Array[StringName] = l.carried_ids()
	assert_eq(ids.size(), 2)
	assert_eq(ids[0], &"a")
	assert_eq(ids[1], &"c")


func test_spread_direction_fan_and_inaccuracy() -> void:
	var first := Player.spread_direction(Vector2.RIGHT, 0, 5, 40.0, 0.0)
	var last := Player.spread_direction(Vector2.RIGHT, 4, 5, 40.0, 0.0)
	var mid := Player.spread_direction(Vector2.RIGHT, 2, 5, 40.0, 0.0)
	# Motif réparti : chaque plomb reste près de sa place (± pellet_jitter × écart de 10°).
	var tol := Balance.get_float("player", "pellet_jitter", 0.3) * 10.0 + 0.01
	assert_almost_eq(rad_to_deg(first.angle()), -20.0, tol)
	assert_almost_eq(rad_to_deg(last.angle()), 20.0, tol)
	assert_almost_eq(rad_to_deg(mid.angle()), 0.0, tol)
	for i: int in 30:
		var d := Player.spread_direction(Vector2.RIGHT, 0, 1, 0.0, 3.0)
		assert_lt(absf(rad_to_deg(d.angle())), 3.0001, "imprécision bornée")


func test_gerbe_reguliere_sans_amas() -> void:
	# 8 plombs sur 18° : jamais deux plombs voisins inversés ni collés (écart > 40 % du pas).
	var gap := 18.0 / 7.0
	for n: int in 50:
		var prev := -INF
		for i: int in 8:
			var a := rad_to_deg(Player.pellet_direction(Vector2.RIGHT, i, 8, 18.0).angle())
			assert_gt(a - prev, gap * 0.39, "plomb %d bien réparti" % i)
			prev = a


func test_imprecision_centree() -> void:
	# Loi triangulaire : écart moyen ≈ 1/3 du cône (uniforme : 1/2), jamais au-delà.
	var sum := 0.0
	for n: int in 2000:
		var o := absf(rad_to_deg(Player.spread_offset(6.0)))
		assert_lte(o, 6.0001)
		sum += o
	assert_lt(sum / 2000.0, 6.0 * 0.42, "la plupart des balles partent près du centre")


# --- Explosion ------------------------------------------------------------------

func test_explosion_falloff_decreases() -> void:
	var c := Explosion.falloff_damage(0.0, 100.0, 80.0, 0.25)
	var m := Explosion.falloff_damage(50.0, 100.0, 80.0, 0.25)
	var e := Explosion.falloff_damage(100.0, 100.0, 80.0, 0.25)
	assert_almost_eq(c, 80.0, 0.001, "plein dégât au centre")
	assert_almost_eq(e, 20.0, 0.001, "min_frac au bord")
	assert_gt(c, m)
	assert_gt(m, e)
	assert_eq(Explosion.falloff_damage(101.0, 100.0, 80.0), 0.0, "hors rayon")
	assert_eq(Explosion.falloff_damage(10.0, 0.0, 80.0), 0.0, "rayon nul")


# --- Animations de la planche ------------------------------------------------------

func test_discover_anims_groups_and_fills_directions() -> void:
	var names := PackedStringArray(["idle_e", "idle_s", "idle_w", "idle_n", "run_e", "run_se", "run_s",
		"run_sw", "run_w", "run_nw", "run_n", "run_ne", "hit_s", "notes"])
	var a: Dictionary = PlayerVisual.discover_anims(names)
	assert_true(a.has(&"idle"))
	assert_true(a.has(&"run"))
	assert_true(a.has(&"hit"))
	assert_false(a.has(&"notes"))
	assert_eq((a[&"run"] as Array).size(), 8)
	assert_eq((a[&"run"] as Array)[1], &"run_se")
	# idle_se manquant → direction voisine disponible.
	var se: String = String((a[&"idle"] as Array)[1])
	assert_true(se == "idle_e" or se == "idle_s", "repli voisin : %s" % se)
	assert_eq((a[&"hit"] as Array)[0], &"hit_s", "une seule direction : utilisée partout")


func test_weapon_profiles_for_all_categories() -> void:
	for cat: StringName in WeaponData.CATEGORIES:
		var p: Dictionary = WeaponView.profile_for(cat)
		assert_true(p.has("rot_deg") and p.has("flash"), "profil complet pour %s" % cat)
	assert_gt(float(WeaponView.profile_for(WeaponData.CAT_SNIPER)["rot_deg"]),
		float(WeaponView.profile_for(WeaponData.CAT_PISTOL)["rot_deg"]), "sniper : recul plus fort")
	assert_gt(float(WeaponView.profile_for(WeaponData.CAT_ROCKET)["body_px"]),
		float(WeaponView.profile_for(WeaponData.CAT_PISTOL)["body_px"]), "bazooka : recul du corps")
