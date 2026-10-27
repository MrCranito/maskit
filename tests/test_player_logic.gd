extends GutTest
## Tests de la logique pure du joueur et du joystick.


func _make_target(pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.position = pos
	add_child_autofree(n)
	return n


func test_nearest_target_picks_closest_in_range() -> void:
	var a := _make_target(Vector2(300, 0))
	var b := _make_target(Vector2(100, 0))
	var _c := _make_target(Vector2(1000, 0))
	var t: Node2D = Player.select_nearest_target(Vector2.ZERO, [a, b, _c], 500.0)
	assert_eq(t, b, "la cible la plus proche doit être choisie")


func test_nearest_target_null_when_out_of_range() -> void:
	var a := _make_target(Vector2(600, 0))
	assert_null(Player.select_nearest_target(Vector2.ZERO, [a], 500.0))


func test_nearest_target_respects_line_of_sight() -> void:
	var near := _make_target(Vector2(50, 0))
	var far := _make_target(Vector2(200, 0))
	# Ligne de vue bloquée pour toute cible à moins de 100 px.
	var los := func(p: Vector2) -> bool: return p.x > 100.0
	assert_eq(Player.select_nearest_target(Vector2.ZERO, [near, far], 500.0, los), far)


func test_nearest_target_ignores_invalid_entries() -> void:
	var a := _make_target(Vector2(10, 0))
	assert_eq(Player.select_nearest_target(Vector2.ZERO, [null, "x", a], 500.0), a)


func test_joystick_dead_zone() -> void:
	assert_eq(VirtualJoystick.compute_output(Vector2(10, 0), 100.0, 0.15), Vector2.ZERO)


func test_joystick_full_tilt_is_unit_length() -> void:
	var out: Vector2 = VirtualJoystick.compute_output(Vector2(0, 250), 100.0, 0.15)
	assert_almost_eq(out.length(), 1.0, 0.001)
	assert_almost_eq(out.y, 1.0, 0.001)


func test_joystick_output_remapped_after_dead_zone() -> void:
	var out: Vector2 = VirtualJoystick.compute_output(Vector2(50, 0), 100.0, 0.0)
	assert_almost_eq(out.x, 0.5, 0.001)


func test_starter_bow_matches_balance() -> void:
	# Typage souple : sous GUT, le script de classe peut être rechargé et
	# l'assignation typée WeaponData échoue alors qu'il s'agit bien de la même ressource.
	var w: Resource = load("res://data/weapons/starter_bow.tres")
	assert_not_null(w)
	assert_eq(w.get_script().resource_path, "res://scripts/combat/weapon_data.gd")
	assert_eq(w.display_name, "Arc du novice")
	assert_almost_eq(w.damage, Balance.get_float("weapon_default", "damage", -1.0), 0.0001)
	assert_almost_eq(w.fire_rate, Balance.get_float("weapon_default", "fire_rate", -1.0), 0.0001)
	assert_almost_eq(w.range, Balance.get_float("weapon_default", "range", -1.0), 0.0001)
	assert_almost_eq(w.get_fire_interval(), 1.0 / w.fire_rate, 0.0001)
