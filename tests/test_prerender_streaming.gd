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
