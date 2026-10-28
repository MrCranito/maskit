extends GutTest
## Tests des cachettes : entrer / sortir, set_hidden appelé, tremblement, choix de la
## cible d'interaction, placement par le générateur (jamais sur un passage d'une case).


class FakePlayer extends Node2D:
	signal hidden_changed(hidden: bool, spot: Node)
	var is_hid := false
	var spot: Node = null
	var calls: Array = []

	func is_hidden() -> bool:
		return is_hid

	func get_hide_spot() -> Node:
		return spot

	func set_hidden(on: bool, s: Node = null) -> void:
		calls.append([on, s])
		if on == is_hid:
			return
		is_hid = on
		spot = s if on else null
		hidden_changed.emit(on, s)


func _spot(kind: StringName = &"barrel", pos: Vector2 = Vector2(200, 200)) -> HidingSpot:
	var h := HidingSpot.create(kind, pos)
	add_child_autofree(h)
	return h


func _player(pos: Vector2 = Vector2(200, 240)) -> FakePlayer:
	var p := FakePlayer.new()
	p.add_to_group(&"player")
	p.position = pos
	add_child_autofree(p)
	return p


func test_groupes_et_libelle() -> void:
	var h := _spot()
	assert_true(h.is_in_group(&"hiding_spots"))
	assert_true(h.is_in_group(&"interactables"))
	assert_eq(h.get_interact_label(), "Se cacher")
	assert_false(h.is_processing(), "pas de _process")


func test_entrer_puis_sortir() -> void:
	var h := _spot()
	var p := _player()
	h.interact(p)
	assert_eq(p.calls.size(), 1)
	assert_eq(p.calls[0], [true, h], "set_hidden(true, cachette)")
	assert_true(h.is_occupied())
	assert_eq(h.get_interact_label(), "Sortir")
	assert_true(h.is_shaking(), "la cachette tremble")
	assert_false(p.visible, "sprite du joueur masqué")
	assert_true(h.get_node("HiddenEye").visible, "œil barré affiché")
	h.interact(p)
	assert_eq(p.calls[-1][0], false, "set_hidden(false)")
	assert_false(h.is_occupied())
	assert_false(h.is_shaking())
	assert_true(p.visible)
	assert_false(h.get_node("HiddenEye").visible)


func test_sortie_par_le_joueur_libere_la_cachette() -> void:
	var h := _spot()
	var p := _player()
	h.interact(p)
	p.set_hidden(false)  # stick poussé, ennemi qui le déloge…
	assert_false(h.is_occupied())
	assert_true(p.visible)
	assert_eq(h.get_interact_label(), "Se cacher")


func test_cachette_occupee_refuse_un_autre() -> void:
	var h := _spot()
	var p := _player()
	var p2 := _player()
	h.interact(p)
	h.interact(p2)
	assert_eq(p2.calls.size(), 0)
	assert_eq(h.occupant, p)


func test_avec_le_vrai_joueur() -> void:
	var saved: Variant = GameState.player
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	var p := scene.instantiate() as Node2D
	p.position = Vector2(300, 340)
	add_child_autofree(p)
	await wait_physics_frames(1)
	if not p.has_method("set_hidden"):
		pending("Player.set_hidden absent (travail de l'agent contrôles)")
		return
	var h := _spot(&"wardrobe", Vector2(300, 300))
	h.interact(p)
	assert_true(bool(p.call("is_hidden")))
	assert_false(p.visible)
	h.interact(p)
	assert_false(bool(p.call("is_hidden")))
	assert_true(p.visible)
	# Le joueur s'est enregistré dans GameState (player_spawned) : on restaure.
	GameState.player = saved if is_instance_valid(saved) else null


func test_cible_la_plus_proche_et_caché() -> void:
	var p := _player(Vector2(0, 0))
	var near := _spot(&"barrel", Vector2(40, 0))
	var far := _spot(&"haystack", Vector2(70, 0))
	var c := LootContainer.create(&"crate", Vector2(-200, 0))
	add_child_autofree(c)
	var cands: Array = [far, near, c]
	assert_eq(InteractController.pick_target(p, cands, 78.0), near)
	c.position = Vector2(10, 0)
	assert_eq(InteractController.pick_target(p, cands, 78.0), c, "conteneur plus proche")
	c.position = Vector2(-500, 0)
	near.position = Vector2(500, 0)
	far.position = Vector2(500, 0)
	assert_null(InteractController.pick_target(p, cands, 78.0), "rien à portée")
	far.interact(p)
	assert_eq(InteractController.pick_target(p, cands, 78.0), far, "caché : seule sa cachette (Sortir)")


func test_controleur_emet_interact_target_changed() -> void:
	var p := _player(Vector2(1000, 1000))
	var saved: Variant = GameState.player
	GameState.player = p
	var h := _spot(&"barrel", Vector2(1000, 1040))
	var ctl := InteractController.new()
	add_child_autofree(ctl)
	watch_signals(EventBus)
	ctl.refresh()
	assert_signal_emitted_with_parameters(EventBus, "interact_target_changed", [h])
	ctl.press()
	assert_true(p.is_hid, "press → entre dans la cachette")
	ctl.release()
	GameState.player = saved if is_instance_valid(saved) else null


func test_generateur_place_des_cachettes_sans_couper_les_passages() -> void:
	var world := load("res://data/worlds/world_01_far_west.tres") as WorldData
	var floors: Array = DungeonGenerator.generate_run(4242, world, 1)
	var total := 0
	for f: FloorLayout in floors:
		total += f.hiding_spot_spawns.size()
		var blocked := {}
		for l: Array in [f.prop_spawns, f.container_spawns, f.hiding_spot_spawns]:
			for s: FloorLayout.Spawn in l:
				assert_false(blocked.has(s.cell), "case unique %s" % s.cell)
				blocked[s.cell] = true
		for s2: FloorLayout.Spawn in f.hiding_spot_spawns:
			assert_true(HidingSpot.DEFS.has(s2.kind), "kind connu %s" % s2.kind)
			var t := f.get_tile(s2.cell)
			assert_true(t == FloorLayout.Tile.FLOOR or t == FloorLayout.Tile.STREET)
			assert_ne(s2.cell, f.player_spawn)
		# Bloquer les cachettes ne rend aucune case inaccessible (depuis chaque
		# composante : spawn joueur et arrivées d'escaliers).
		var others := {}
		for l2: Array in [f.prop_spawns, f.container_spawns]:
			for s4: FloorLayout.Spawn in l2:
				others[s4.cell] = true
		var starts: Array[Vector2i] = [f.player_spawn]
		for st: FloorLayout.Stairs in f.stairs:
			starts.append(st.cell)
		for st2: Vector2i in starts:
			var before := _flood(f, st2, others)
			var after := _flood(f, st2, blocked)
			for cell: Vector2i in before:
				if not blocked.has(cell):
					assert_true(after.has(cell), "case %s toujours accessible" % cell)
	assert_gte(total, 3, "quelques cachettes par run")


func test_layout_retrocompatible() -> void:
	var L := FloorLayout.make_sample()
	assert_eq(L.hiding_spot_spawns.size(), 0, "champ présent, vide par défaut")


static func _flood(f: FloorLayout, start: Vector2i, blocked: Dictionary) -> Dictionary:
	var seen := {start: true}
	var q: Array[Vector2i] = [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := c + d
			if seen.has(n) or blocked.has(n) or not FloorLayout.is_walkable_tile(f.get_tile(n)):
				continue
			seen[n] = true
			q.append(n)
	return seen
