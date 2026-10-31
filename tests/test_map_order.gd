extends GutTest
## Choix de la carte : les cartes sont rangées par difficulté croissante, puis dans l'ordre des
## mondes (Far West, Station, Galeries, Carnaval, Terres gelées, Pyramides), en colonnes de 2
## vignettes de gauche à droite ; l'arène de test du mode dev reste en dernier.

const WORLD_CARDS: Array[String] = ["perm_pyramides_egypte", "perm_carnaval_hante", "perm_dust_creek",
	"perm_terres_gelees", "perm_station_kagami", "perm_galeries_lumiere"]
const EXPECTED: Array[String] = ["perm_dust_creek", "perm_station_kagami", "perm_galeries_lumiere",
	"perm_carnaval_hante", "perm_terres_gelees", "perm_pyramides_egypte"]


func _entries(ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ids:
		var c := load("res://data/maps/%s.tres" % id) as MapCard
		out.append({"card": c, "category": c.category, "starts_at": 0, "ends_at": 0})
	return out


func _ids(list: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in list:
		out.append(String((e["card"] as MapCard).id))
	return out


func test_mondes_dans_l_ordre_de_difficulte() -> void:
	var sorted := MapSelect.sorted_by_difficulty(_entries(WORLD_CARDS))
	assert_eq(_ids(sorted), EXPECTED)
	var last := -1
	for e: Dictionary in sorted:
		var d: int = (e["card"] as MapCard).difficulty
		assert_gte(d, last, "difficulté croissante")
		last = d


func test_arene_de_test_en_dernier() -> void:
	var list := _entries(WORLD_CARDS)
	var arena := MapCard.new()
	arena.id = &"dev_test_arena"
	arena.difficulty = 0
	list.push_front({"card": arena, "category": arena.category, "starts_at": 0, "ends_at": 0})
	var sorted := MapSelect.sorted_by_difficulty(list)
	assert_eq(String((sorted[-1]["card"] as MapCard).id), "dev_test_arena")


func test_colonnes_de_deux_par_difficulte() -> void:
	var ms := (load(MenuKit.MAP_SELECT_SCENE) as PackedScene).instantiate() as MapSelect
	ms.next_scene = ""
	add_child_autofree(ms)
	await wait_frames(2)
	ms.entries = _entries(WORLD_CARDS)
	ms.next_event = {}
	ms.current_filter = &""
	ms.set_filter(&"permanent")
	await wait_frames(2)
	var ids: Array[String] = []
	for t: MapTile in ms.tiles:
		ids.append(String((t.entry["card"] as MapCard).id))
	assert_eq(ids, EXPECTED, "vignettes créées dans l'ordre de difficulté")
	# Colonnes de 2 : la vignette i est dans la colonne i / 2, rangée i % 2.
	for i: int in ms.tiles.size():
		var t: MapTile = ms.tiles[i]
		assert_eq(t.get_index(), i % MapSelect.ROWS, "%s : rangée %d" % [ids[i], i % MapSelect.ROWS])
		assert_eq(t.get_parent().get_index(), i / MapSelect.ROWS, "%s : colonne %d" % [ids[i], i / MapSelect.ROWS])
