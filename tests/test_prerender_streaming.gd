extends GutTest
## Chargement par morceaux du fond pré-rendu (PrerenderBackdrop) sous le serveur de rendu
## factice (--headless). Non-régression de « texture_storage.h:85 Parameter "t" is null » :
## le fil de chargement (load_threaded_request) et le fil principal créaient des textures en
## même temps dans le registre non protégé du rendu factice.


func after_each() -> void:
	PrerenderBackdrop.threaded_loading_override = -1


func _backdrop() -> PrerenderBackdrop:
	var seeds := PrerenderBackdrop.available_seeds(&"space_station")
	if seeds.is_empty():
		return null
	var b := PrerenderBackdrop.create(seeds[0], null, &"space_station")
	if b != null:
		add_child_autofree(b)
	return b


func test_rendu_factice_pas_de_chargement_en_fil() -> void:
	if DisplayServer.get_name() != "headless":
		pass_test("hors --headless : chargement en arrière-plan autorisé")
		return
	assert_false(PrerenderBackdrop.threaded_loading_safe(),
		"--headless (rendu factice) : aucune texture chargée hors du fil principal")


func test_chargement_synchrone_sans_requete_en_fil() -> void:
	PrerenderBackdrop.threaded_loading_override = 0
	var b := _backdrop()
	assert_not_null(b, "paquet de station présent")
	if b == null:
		return
	b.set_process(false)
	assert_eq(b.loaded_tile_count(), 0)
	b._stream()
	assert_gt(b.loaded_tile_count(), 0, "tuiles visibles chargées dès le premier passage")
	for t: Dictionary in b._tiles:
		assert_false(bool(t["pending"]), "aucune requête en arrière-plan en attente")
		assert_ne(ResourceLoader.load_threaded_get_status(String(t["file"])), ResourceLoader.THREAD_LOAD_IN_PROGRESS,
			"aucun chargement en fil lancé (%s)" % t["file"])
	# Caméra loin de la carte : les tuiles sont libérées puis rechargées au retour.
	var n := b.loaded_tile_count()
	var vp := b.get_viewport()
	var keep := vp.canvas_transform
	vp.canvas_transform = Transform2D(0.0, Vector2(-1.0e6, -1.0e6))
	b._stream()
	vp.canvas_transform = keep
	assert_eq(b.loaded_tile_count(), 0, "tuiles hors vue libérées")
	b._stream()
	assert_eq(b.loaded_tile_count(), n, "tuiles rechargées au retour")


## perf/fluidite : libération plus loin que le chargement (hystérésis). Une tuile chargée reste
## en mémoire tant que la vue n'est pas sortie de release_margin ; sinon un joueur qui longe la
## limite rechargeait (et renvoyait au GPU) la même tuile toutes les quelques secondes.
func test_hysteresis_entre_chargement_et_liberation() -> void:
	PrerenderBackdrop.threaded_loading_override = 0
	var b := _backdrop()
	if b == null:
		pass_test("pas de paquet de station")
		return
	b.set_process(false)
	assert_gt(b.release_margin, b.stream_margin, "marge de libération plus large que celle de chargement")
	b._stream()
	var n := b.loaded_tile_count()
	assert_gt(n, 0)
	# Tuile la plus à droite parmi les chargées : on décale la vue vers la gauche juste assez
	# pour qu'elle sorte de la marge de chargement sans sortir de celle de libération.
	var vp := b.get_viewport()
	var keep := vp.canvas_transform
	var inv := keep.affine_inverse()
	var screen := Rect2(inv * Vector2.ZERO, Vector2.ZERO).expand(inv * vp.get_visible_rect().size)
	var far_x := -INF
	for t: Dictionary in b._tiles:
		if t["sprite"] != null:
			far_x = maxf(far_x, (t["rect"] as Rect2).position.x)
	var gap := far_x - screen.end.x  # distance vue → bord gauche de cette tuile
	var shift := (b.stream_margin - gap) + (b.release_margin - b.stream_margin) * 0.5
	vp.canvas_transform = keep * Transform2D(0.0, Vector2(-shift, 0.0)).affine_inverse()
	b._stream()
	var still := 0
	for t: Dictionary in b._tiles:
		if t["sprite"] != null and is_equal_approx((t["rect"] as Rect2).position.x, far_x):
			still += 1
	vp.canvas_transform = keep
	assert_gt(still, 0, "tuile entre les deux marges : gardée (pas de rechargement en boucle)")
