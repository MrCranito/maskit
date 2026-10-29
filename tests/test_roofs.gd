extends GutTest
## Toits accessibles par échelle (RoofWalk, Ladder) et cohérence du paquet pré-rendu
## (collisions « emprise rendue », occultation) — correctif « portes sur les toits / wagons ».

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const PACK_SEED := 642439

var _raid: Raid = null
var _saved_debug := false


class FakeEnemy extends Node:
	var data: EnemyData = null


func before_all() -> void:
	_saved_debug = GameState.debug_enabled
	GameState.debug_enabled = false


func after_all() -> void:
	GameState.debug_enabled = _saved_debug


func before_each() -> void:
	_raid = (load(RAID_SCENE) as PackedScene).instantiate() as Raid
	add_child_autofree(_raid)
	await wait_physics_frames(3)


func _player() -> Player:
	return _raid.player as Player


func _foot_and_top() -> Array:
	var foot: Ladder = null
	var top: Ladder = null
	for l: Ladder in _raid.roof_walk.ladders:
		if foot == null and not l.is_top:
			foot = l
	for l2: Ladder in _raid.roof_walk.ladders:
		if l2.is_top and l2.building_id() == foot.building_id():
			top = l2
	return [foot, top]


func _go_up() -> Array:
	var ft := _foot_and_top()
	var foot: Ladder = ft[0]
	_raid.place_player(foot.entry["cell"])
	await wait_physics_frames(2)
	assert_true(_raid.roof_walk.climb(foot, true, _player()), "montée lancée")
	_raid.roof_walk.finish_climb()
	await wait_physics_frames(3)
	return ft


# --- Logique pure ----------------------------------------------------------------------

func test_soustraction_de_rectangles() -> void:
	var parts := RoofWalk.subtract_rect(Rect2(0, 0, 100, 100), Rect2(20, 30, 40, 20))
	var area := 0.0
	for r in parts:
		area += r.get_area()
		assert_false(r.intersects(Rect2(20, 30, 40, 20)), "morceau hors découpe")
	assert_almost_eq(area, 100.0 * 100.0 - 40.0 * 20.0, 0.01, "aire conservée")
	assert_eq(RoofWalk.subtract_rect(Rect2(0, 0, 10, 10), Rect2(50, 50, 5, 5)).size(), 1, "sans recouvrement : inchangé")


func test_melee_ne_touche_pas_un_joueur_perche() -> void:
	var melee := FakeEnemy.new()
	melee.data = EnemyData.new()
	melee.data.attack_type = EnemyData.AttackType.MELEE
	var ranged := FakeEnemy.new()
	ranged.data = EnemyData.new()
	ranged.data.attack_type = EnemyData.AttackType.RANGED
	assert_false(Player.roof_hit_allowed(melee), "mêlée : pas de coup sur le toit")
	assert_true(Player.roof_hit_allowed(ranged), "tir : touche")
	assert_true(Player.roof_hit_allowed(null), "explosion / source inconnue : touche")
	melee.free()
	ranged.free()


# --- Échelles et toits en jeu ----------------------------------------------------------

func test_echelles_instanciees() -> void:
	assert_false(_raid.layout.ladders.is_empty(), "le village a des échelles")
	assert_not_null(_raid.roof_walk, "RoofWalk construit")
	assert_eq(_raid.roof_walk.ladders.size(), _raid.layout.ladders.size() * 2, "pied + sommet par échelle")
	for l: Ladder in _raid.roof_walk.ladders:
		var e := l.entry
		var b := _raid.layout.buildings[int(e["building_id"])]
		if l.is_top:
			assert_true(_raid.roof_walk.walk_rect(b.id).has_point(l.position), "sommet sur le toit")
		else:
			assert_eq(l.position, FloorLayout.cell_to_world(e["cell"]), "pied au centre de sa case")
			assert_eq((e["cell"] as Vector2i).y, b.rect.end.y, "pied au sud de la façade (visible)")


func test_monter_puis_descendre() -> void:
	var p := _player()
	var ft := _foot_and_top()
	var foot: Ladder = ft[0]
	var top: Ladder = ft[1]
	_raid.place_player(foot.entry["cell"])
	await wait_physics_frames(2)
	assert_true(foot.can_interact(), "pied proposé au sol")
	assert_false(top.can_interact(), "sommet non proposé au sol")
	assert_eq(InteractController.pick_target(p, [foot, top], 78.0), foot, "cible : pied de l'échelle")
	var z0 := p.z_index
	await _go_up()
	assert_true(p.is_on_roof(), "sur le toit")
	assert_eq(p.roof_building_id, foot.building_id())
	assert_eq(p.collision_layer, Player.LAYER_ROOF_PLAYER, "couche joueur perché")
	assert_eq(p.collision_mask, Player.MASK_ROOF_BOUNDS, "ne heurte que les bords du toit")
	assert_gt(p.z_index, 50, "dessiné au-dessus des toits")
	assert_lt(p.global_position.distance_to(top.position), 2.0, "arrivé au sommet")
	assert_true(top.can_interact(), "sommet proposé")
	assert_false(foot.can_interact(), "pied non proposé depuis le toit")
	assert_eq(InteractController.pick_target(p, [foot, top], 78.0), top, "seule la cible de toit")
	var fog: Node = _raid.fog
	if fog != null:
		assert_eq(fog.call("get_roof_rect"), _raid.layout.buildings[foot.building_id()].rect, "brouillard en mode toit")
	assert_true(_raid.roof_walk.climb(top, false, p), "descente lancée")
	_raid.roof_walk.finish_climb()
	await wait_physics_frames(2)
	assert_false(p.is_on_roof(), "revenu au sol")
	assert_eq(p.collision_layer, Player.LAYER_PLAYER)
	assert_eq(p.collision_mask, Player.MASK_WORLD | Player.MASK_ENEMIES)
	assert_eq(p.z_index, z0, "z restauré")
	assert_lt(p.global_position.distance_to(foot.position), 2.0, "au pied de l'échelle")
	if fog != null:
		assert_eq(fog.call("get_roof_rect"), Rect2i(), "brouillard normal")


func test_ne_sort_pas_de_l_emprise_du_toit() -> void:
	var ft: Array = await _go_up()
	var p := _player()
	var wr: Rect2 = _raid.roof_walk.walk_rect((ft[0] as Ladder).building_id())
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		for k in 12:
			p.move_and_collide(dir * 200.0)
		assert_true(wr.grow(Player.BODY_RADIUS + 2.0).has_point(p.global_position), "reste sur le toit (%s)" % dir)


func test_toit_ne_s_efface_pas_et_melee_ignoree() -> void:
	var ft: Array = await _go_up()
	var p := _player()
	await wait_seconds(0.3)
	for r: BuildingRoof in _raid.world_root.call("get_roofs"):
		assert_false(r.is_player_inside(), "aucun toit effacé (joueur au-dessus)")
	p.set("_invulnerable_left", 0.0)
	var hp := p.hp
	var melee := FakeEnemy.new()
	melee.data = EnemyData.new()
	melee.data.attack_type = EnemyData.AttackType.MELEE
	p.take_damage(10.0, melee)
	assert_eq(p.hp, hp, "la mêlée n'atteint pas le toit")
	var ranged := FakeEnemy.new()
	ranged.data = EnemyData.new()
	ranged.data.attack_type = EnemyData.AttackType.RANGED
	p.take_damage(10.0, ranged)
	assert_lt(p.hp, hp, "un tir atteint le joueur perché")
	melee.free()
	ranged.free()
	assert_not_null(ft[0])


func test_murs_du_batiment_fantomes() -> void:
	var ft: Array = await _go_up()
	await wait_physics_frames(3)
	var foot: Ladder = ft[0]
	var b := _raid.layout.buildings[foot.building_id()]
	var p := _player()
	var space := p.get_world_2d().direct_space_state
	var from := FloorLayout.cell_to_world(foot.entry["cell"] + Vector2i.DOWN)
	var q := PhysicsRayQueryParameters2D.create(from, p.global_position, 1)
	var hit := space.intersect_ray(q)
	var bw := Rect2(Vector2(b.rect.position) * 64.0, Vector2(b.rect.size) * 64.0)
	assert_true(hit.is_empty() or not bw.grow(-1.0).has_point(hit["position"]),
		"ligne de vue ennemie (couche world) non bloquée par le bâtiment sous le joueur")
	var q2 := PhysicsRayQueryParameters2D.create(from, p.global_position, 4)
	var hit2 := space.intersect_ray(q2)
	assert_false(hit2.is_empty(), "les murs restent infranchissables pour les ennemis (couche enemies)")
	_raid.roof_walk.exit_roof(p)
	await wait_physics_frames(3)
	var hit3 := space.intersect_ray(q)
	assert_false(hit3.is_empty(), "murs restaurés au retour au sol")


# --- Paquet pré-rendu ------------------------------------------------------------------

func _pack_meta() -> Dictionary:
	var f := FileAccess.open(PrerenderBackdrop.PACK_ROOT + str(PACK_SEED) + "/map.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f != null else {}


func _layout(seed_value: int) -> FloorLayout:
	var world: WorldData = load("res://data/worlds/world_01_far_west.tres")
	return DungeonGenerator.generate_floor(seed_value, world, 1, 0)


func test_paquet_correspond_au_plan() -> void:
	var m := _pack_meta()
	assert_false(m.is_empty(), "paquet présent")
	var L := _layout(PACK_SEED)
	assert_eq(String(m.get("tiles_md5", "")), PrerenderBackdrop.layout_md5(L), "empreinte du plan identique (le jeu utilise le paquet)")
	assert_true(m.has("collision"), "couche « emprise rendue »")
	assert_true(m.has("occluders"), "tranches d'occultation")
	assert_eq((m.get("ladders", []) as Array).size(), L.ladders.size(), "échelles rendues = échelles du plan")
	for e: Dictionary in m.get("occluders", []):
		assert_true(ResourceLoader.exists(PrerenderBackdrop.PACK_ROOT + str(PACK_SEED) + "/" + String(e["ids"])), "ids %s" % e["ids"])


## Obstacles rendus = cases bloquantes : chaque case praticable que le masque zénithal montre
## occupée (≥ 50 %) est couverte par la couche de collision (sauf cases rendues libres pour la
## connexité / abords protégés) ; chaque case murée d'obstacle (rocher, wagon, clôture) a un rendu.
func test_obstacles_rendus_egal_cases_bloquantes() -> void:
	var m := _pack_meta()
	var L := _layout(PACK_SEED)
	var tex := load(PrerenderBackdrop.PACK_ROOT + str(PACK_SEED) + "/footprint.png") as Texture2D
	assert_not_null(tex, "masque d'emprise dans le paquet")
	if tex == null:
		return
	var img := tex.get_image()
	img.decompress()
	var M := int(m["margin"])
	var cov := _collision_cov(m, L)
	var freed := {}
	for c: Array in (m.get("collision_stats", {}) as Dictionary).get("freed", []):
		freed[Vector2i(int(c[0]), int(c[1]))] = true
	var prot := _protected(L)
	var bad: Array = []
	for y in L.size.y:
		for x in L.size.x:
			var c := Vector2i(x, y)
			if not FloorLayout.is_walkable_tile(L.get_tile(c)) or freed.has(c) or prot.has(c):
				continue
			var mc := _mask_cov(img, c, M)
			if mc >= 0.5 and float(cov.get(c, 0.0)) < 0.4:
				bad.append(c)
	assert_eq(bad, [], "obstacle rendu sans collision")
	var empty: Array = []
	var cells := {}
	for rf: Dictionary in L.rock_formations:
		for c2: Vector2i in rf["cells"]:
			cells[c2] = true
	for t: Dictionary in L.train:
		for c3 in TownCells.of(t["rect"]):
			cells[c3] = true
	for fl: Array in L.fences:
		for c4: Vector2i in fl:
			cells[c4] = true
	for c5: Vector2i in cells:
		if _mask_cov(img, c5, M) <= 0.0:
			empty.append(c5)
	assert_lte(empty.size(), 2, "cases murées sans rien de rendu : %s" % [empty])


## Passages entre wagons et abords (portes, échelles, extraction) jamais couverts ; toutes les cases
## atteignables restent atteignables avec la couche de collision.
func test_collision_rendue_garde_les_passages() -> void:
	var m := _pack_meta()
	var L := _layout(PACK_SEED)
	var cov := _collision_cov(m, L)
	for c: Vector2i in _protected(L):
		assert_lt(float(cov.get(c, 0.0)), 0.01, "abord protégé %s libre" % c)
	for k in range(L.train.size() - 1):
		var ra: Rect2i = L.train[k]["rect"]
		var rb: Rect2i = L.train[k + 1]["rect"]
		for x in range(ra.end.x, rb.position.x):
			for y in range(ra.position.y, ra.end.y):
				assert_lt(float(cov.get(Vector2i(x, y), 0.0)), 0.3, "passage du train %s franchissable" % Vector2i(x, y))
	var base := _flood(L, {})
	var blocked := {}
	for c2: Vector2i in cov:
		if float(cov[c2]) >= 0.5:
			blocked[c2] = true
	var with := _flood(L, blocked)
	var lost: Array = []
	for c3: Vector2i in base:
		if not blocked.has(c3) and not with.has(c3):
			lost.append(c3)
	assert_eq(lost, [], "cases devenues inaccessibles")


## Abords jamais bloqués par la couche « emprise rendue » (mêmes règles que compose.py).
static func _protected(L: FloorLayout) -> Dictionary:
	var out := {}
	var around := func(c: Vector2i, r: int) -> void:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				out[c + Vector2i(dx, dy)] = true
	for d in L.doors:
		around.call(d.cell, 1)
		if not d.vertical:
			out[d.cell + Vector2i(0, 2)] = true
			out[d.cell + Vector2i(0, -2)] = true
	for st in L.stairs:
		around.call(st.cell, 1)
	for e: Dictionary in L.ladders:
		out[e["cell"]] = true
		out[(e["cell"] as Vector2i) + Vector2i.DOWN] = true
	for c: Vector2i in L.extraction_cells:
		around.call(c, 1)
	around.call(L.player_spawn, 1)
	return out


static func _mask_cov(img: Image, c: Vector2i, M: int) -> float:
	var n := 0
	for dy in 4:
		for dx in 4:
			var px := img.get_pixel((c.x + M) * 4 + dx, (c.y + M) * 4 + dy)
			if px.r > 0.5 or px.g > 0.5:
				n += 1
	return n / 16.0


## Fraction de chaque case couverte par les rectangles de collision du paquet.
static func _collision_cov(m: Dictionary, L: FloorLayout) -> Dictionary:
	var out := {}
	for r: Array in m.get("collision", []):
		var rr := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		for y in range(floori(rr.position.y / 64.0), ceili(rr.end.y / 64.0)):
			for x in range(floori(rr.position.x / 64.0), ceili(rr.end.x / 64.0)):
				var cr := Rect2(x * 64.0, y * 64.0, 64.0, 64.0).intersection(rr)
				out[Vector2i(x, y)] = float(out.get(Vector2i(x, y), 0.0)) + cr.get_area() / 4096.0
	return out


static func _flood(L: FloorLayout, blocked: Dictionary) -> Dictionary:
	var seen := {L.player_spawn: true}
	var st: Array[Vector2i] = [L.player_spawn]
	while not st.is_empty():
		var c: Vector2i = st.pop_back()
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := c + d
			if seen.has(n) or blocked.has(n) or not FloorLayout.is_walkable_tile(L.get_tile(n)):
				continue
			seen[n] = true
			st.append(n)
	return seen


class TownCells:
	static func of(r: Rect2i) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				out.append(Vector2i(x, y))
		return out
