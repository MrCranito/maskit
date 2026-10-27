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

func test_starter_revolver_matches_balance() -> void:
	# Typage souple : sous GUT, le script de classe peut être rechargé.
	var w: Resource = load("res://data/weapons/starter_revolver.tres")
	assert_not_null(w)
	assert_eq(w.get_script().resource_path, "res://scripts/combat/weapon_data.gd")
	assert_eq(String(w.id), "starter_revolver")
	assert_almost_eq(w.damage, Balance.get_float("weapon_default", "damage", -1.0), 0.0001)
	assert_almost_eq(w.fire_rate, Balance.get_float("weapon_default", "fire_rate", -1.0), 0.0001)
	assert_almost_eq(w.range, Balance.get_float("weapon_default", "range", -1.0), 0.0001)
	assert_almost_eq(w.get_fire_interval(), 1.0 / w.fire_rate, 0.0001)
	# Portée effective du projectile cohérente avec la portée annoncée.
	assert_almost_eq(w.projectile_speed * w.projectile_lifetime, w.range, w.range * 0.1)


func test_default_weapon_is_revolver() -> void:
	var w: Resource = Player.load_default_weapon()
	assert_eq(String(w.id), "starter_revolver")
