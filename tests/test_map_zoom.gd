extends GutTest
## Cadrage de la carte plein écran (MapZoom) : bornes du zoom, conversions écran ↔ carte,
## déplacement borné, pincement centré, recentrage.

const VIEW := Vector2(1000, 500)
const WORLD := Rect2(0, 0, 16000, 8000)


func _zoom(max_factor: float = 4.0) -> MapZoom:
	var z := MapZoom.new()
	z.setup(VIEW, WORLD, max_factor)
	return z


func test_zoom_min_carte_entiere_visible() -> void:
	var z := _zoom()
	assert_almost_eq(z.scale, 500.0 / 8000.0, 0.0001, "ajustée sur l'axe limitant")
	assert_true(z.is_min_zoom())
	var tl := z.world_to_screen(WORLD.position)
	var br := z.world_to_screen(WORLD.end)
	assert_true(tl.x >= -0.01 and tl.y >= -0.01 and br.x <= VIEW.x + 0.01 and br.y <= VIEW.y + 0.01,
		"carte entière dans la vue (%s → %s)" % [tl, br])
	assert_almost_eq(z.world_to_screen(WORLD.get_center()).x, VIEW.x * 0.5, 0.01, "centrée")


func test_bornes_du_zoom() -> void:
	var z := _zoom(4.0)
	z.zoom_at(VIEW * 0.5, 0.2)
	assert_almost_eq(z.scale, z.min_scale(), 0.00001, "pas plus petit que la carte entière")
	for i in 30:
		z.zoom_at(VIEW * 0.5, 1.5)
	assert_almost_eq(z.scale, z.min_scale() * 4.0, 0.00001, "zoom max = min × facteur")
	assert_true(z.is_max_zoom())
	z.setup(VIEW, WORLD, 0.5)
	assert_almost_eq(z.max_scale(), z.min_scale(), 0.00001, "facteur < 1 ramené à 1")


func test_conversion_ecran_carte_aller_retour() -> void:
	var z := _zoom()
	z.zoom_at(Vector2(300, 200), 3.0)
	z.pan(Vector2(-120, 45))
	for p: Vector2 in [Vector2(0, 0), Vector2(123.5, 456.25), VIEW, Vector2(999, 1)]:
		var w := z.screen_to_world(p)
		assert_almost_eq(z.world_to_screen(w).distance_to(p), 0.0, 0.001, "écran → carte → écran (%s)" % p)
	var wp := Vector2(1500, 2500)
	assert_almost_eq(z.screen_to_world(z.world_to_screen(wp)).distance_to(wp), 0.0, 0.001)


func test_zoom_garde_le_point_sous_le_curseur() -> void:
	var z := _zoom()
	z.zoom_at(VIEW * 0.5, 2.0)  # assez zoomé pour que le point ne soit pas borné
	var cursor := Vector2(600, 260)
	var under := z.screen_to_world(cursor)
	z.zoom_at(cursor, 1.3)
	assert_almost_eq(z.world_to_screen(under).distance_to(cursor), 0.0, 0.01, "point fixe sous le curseur")


func test_deplacement_borne_aux_limites() -> void:
	var z := _zoom()
	var moved := z.pan(Vector2(5000, 5000))
	assert_eq(moved, Vector2.ZERO, "carte entière : rien à déplacer")
	z.zoom_at(VIEW * 0.5, 4.0)
	z.pan(Vector2(1.0e6, 1.0e6))
	assert_almost_eq(z.world_to_screen(WORLD.position).x, 0.0, 0.01, "bord gauche collé, pas au-delà")
	assert_almost_eq(z.world_to_screen(WORLD.position).y, 0.0, 0.01, "bord haut collé")
	z.pan(Vector2(-1.0e6, -1.0e6))
	assert_almost_eq(z.world_to_screen(WORLD.end).x, VIEW.x, 0.01, "bord droit collé")
	assert_almost_eq(z.world_to_screen(WORLD.end).y, VIEW.y, 0.01, "bord bas collé")


func test_axe_plus_petit_que_la_vue_reste_centre() -> void:
	var narrow := Rect2(0, 0, 4000, 8000)
	var z := MapZoom.new()
	z.setup(VIEW, narrow, 4.0)
	z.zoom_at(VIEW * 0.5, 1.5)  # largeur carte = 4000 × 0,094 = 375 px < 1000
	z.pan(Vector2(400, 0))
	var cx := (z.world_to_screen(narrow.position).x + z.world_to_screen(narrow.end).x) * 0.5
	assert_almost_eq(cx, VIEW.x * 0.5, 0.01, "carte centrée horizontalement")


func test_pincement_centre_sur_les_doigts() -> void:
	var z := _zoom()
	z.zoom_at(VIEW * 0.5, 2.0)
	var mid := Vector2(520, 240)
	var anchor := z.screen_to_world(mid)
	var s0 := z.scale
	z.pinch(anchor, mid, s0 * 1.6)
	assert_almost_eq(z.scale, s0 * 1.6, 0.00001)
	assert_almost_eq(z.world_to_screen(anchor).distance_to(mid), 0.0, 0.01, "point pincé reste sous les doigts")
	z.pinch(anchor, mid + Vector2(-30, 10), s0 * 1.6)
	assert_almost_eq(z.world_to_screen(anchor).distance_to(mid + Vector2(-30, 10)), 0.0, 0.01, "suit le milieu des doigts")
	z.pinch(anchor, mid, 1.0e9)
	assert_almost_eq(z.scale, z.max_scale(), 0.00001, "pincement borné")


func test_recentrage() -> void:
	var z := _zoom()
	z.zoom_at(VIEW * 0.5, 3.0)
	var p := Vector2(8100, 4300)
	z.center_on(p)
	assert_almost_eq(z.center_world().distance_to(p), 0.0, 0.01, "joueur au centre")
	z.center_on(Vector2(10, 10))
	assert_almost_eq(z.world_to_screen(WORLD.position).y, 0.0, 0.01,
		"près du bord haut : recentrage borné, pas de vide hors carte")


func test_redimensionnement_garde_le_centre() -> void:
	var z := _zoom()
	z.zoom_at(VIEW * 0.5, 3.0)
	z.center_on(Vector2(8000, 4000))
	var f := z.zoom_factor()
	z.resize(Vector2(800, 600))
	assert_almost_eq(z.zoom_factor(), f, 0.0001)
	assert_almost_eq(z.center_world().distance_to(Vector2(8000, 4000)), 0.0, 0.01)
