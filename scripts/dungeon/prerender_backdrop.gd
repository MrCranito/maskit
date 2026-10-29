class_name PrerenderBackdrop
extends Node2D
## (Test B, prototype) Fond pré-calculé d'un étage 0 Far West : la carte entière rendue
## d'un bloc dans Blender/Cycles (tools/prerender/fw_scene.py → compose.py), découpée en
## tuiles ≤ 1024 px (res://assets/prerender/far_west/<seed>/map.json).
## - Tuiles chargées par morceaux : seules celles proches de la caméra sont en mémoire
##   (chargement en arrière-plan via ResourceLoader.load_threaded_request, libération au loin).
## - Rendu incliné (caméra ortho à tilt°). Projection « ground_square » (fw_scene.py, test R) :
##   pixel_aspect_x = 1/cos(tilt) au rendu → le SOL (z = 0) est carré, ppc px par case ; l'image
##   est posée à l'échelle 64/ppc sans étirement et le sol tombe exactement sur la grille
##   (collisions inchangées). Un point à la hauteur z (cases) apparaît z·tan(tilt) cases plus
##   haut : seules les parties hautes (toits, façades, rochers) « dépassent » vers le nord.
##   Ancien format (sans "projection") : image étirée de 1/cos(tilt) en Y.
## - Intérieurs : patch « sans toit » par bâtiment, affiché en fondu quand le toit 2D du
##   WorldBuilder (BuildingRoof, rendu invisible) détecte le joueur dedans.
## Le WorldBuilder reste la source des collisions, portes, escaliers, toits (logique),
## brouillard ; ses visuels sol/murs/décors/toits sont masqués (hide_builder_visuals).

const PACK_ROOT := "res://assets/prerender/far_west/"
const TS := float(FloorLayout.TILE_SIZE)

var meta: Dictionary = {}
var pack_dir := ""
var px_scale := Vector2.ONE           ## px image → monde
var origin := Vector2.ZERO            ## position monde du pixel (0, 0)
var stream_margin := 900.0            ## marge (monde) autour de la vue pour charger
var _tiles: Array[Dictionary] = []    ## {file, rect (monde), sprite, pending}
var _interiors: Array[Dictionary] = []  ## {sprite, roof}


## Graines pré-rendues disponibles (dossiers contenant map.json).
static func available_seeds() -> PackedInt32Array:
	var out := PackedInt32Array()
	var d := DirAccess.open(PACK_ROOT)
	if d == null:
		return out
	for n in d.get_directories():
		if n.is_valid_int() and ResourceLoader.exists(PACK_ROOT + n + "/map.json") or FileAccess.file_exists(PACK_ROOT + n + "/map.json"):
			out.append(int(n))
	return out


## Tire une carte pré-rendue au hasard (0 si aucune).
static func pick_seed(rng_seed: int) -> int:
	var seeds := available_seeds()
	if seeds.is_empty():
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	return seeds[rng.randi_range(0, seeds.size() - 1)]


## Empreinte du plan (md5 des rangées de tuiles, comme fw_scene.py) : un paquet rendu pour
## un autre plan (générateur modifié depuis le rendu) est refusé → rendu 2D habituel.
static func layout_md5(L: FloorLayout) -> String:
	var s := ""
	for y in L.size.y:
		for x in L.size.x:
			s += str(L.get_tile(Vector2i(x, y)))
	return s.md5_text()


static func create(map_seed: int, layout: FloorLayout = null) -> PrerenderBackdrop:
	var dir := PACK_ROOT + str(map_seed) + "/"
	var f := FileAccess.open(dir + "map.json", FileAccess.READ)
	if f == null:
		return null
	var m: Variant = JSON.parse_string(f.get_as_text())
	if not (m is Dictionary):
		return null
	var want := String((m as Dictionary).get("tiles_md5", ""))
	if layout != null and want != "" and want != layout_md5(layout):
		push_warning("PrerenderBackdrop: paquet %d rendu pour un autre plan, ignoré." % map_seed)
		return null
	var b := PrerenderBackdrop.new()
	b.name = "PrerenderBackdrop"
	b.meta = m
	b.pack_dir = dir
	b._setup()
	return b


func _setup() -> void:
	z_index = 0
	z_as_relative = false
	var ppc := float(meta["ppc"])
	var cos_t := cos(deg_to_rad(float(meta["tilt_deg"])))
	if String(meta.get("projection", "")) == "ground_square":
		cos_t = 1.0
	var mg := float(meta["margin"])
	px_scale = Vector2(TS / ppc, TS / (ppc * cos_t))
	origin = Vector2(-mg, -mg) * TS
	for t: Dictionary in meta["tiles"]:
		var p: Array = t["px"]
		var r := Rect2(origin + Vector2(p[0], p[1]) * px_scale, Vector2(p[2], p[3]) * px_scale)
		_tiles.append({"file": pack_dir + String(t["file"]), "rect": r, "sprite": null, "pending": false})


## Masque les visuels du WorldBuilder (le rendu pré-calculé les remplace) et branche les
## patchs d'intérieur sur ses toits. Collisions, portes, escaliers, lueurs : inchangés.
func attach_to(builder: Node2D) -> void:
	for n: Node in builder.get_children():
		var nm := String(n.name)
		# Noms dupliqués renommés par Godot (« @Prop_barrel@12 ») : on teste contains().
		if nm in ["Ground", "PorchDecks", "FloorDetails", "Outskirts"] or nm.contains("Porch_") \
				or nm.contains("Prop_") or nm.contains("Landmark_"):
			(n as CanvasItem).visible = false
		elif nm == "Walls":
			for c: Node in n.get_children():
				if c is CanvasItem and not (c is StaticBody2D):
					(c as CanvasItem).visible = false
		elif nm == "AmbientTint":
			(n as CanvasModulate).color = Color.WHITE
	if builder.has_method("get_props"):
		for pr: Node in builder.call("get_props"):
			(pr as CanvasItem).visible = false
	var roofs: Array = builder.call("get_roofs") if builder.has_method("get_roofs") else []
	var by_id := {}
	for r: Node2D in roofs:
		# Le toit 2D ne dessine plus rien mais garde sa logique (joueur dedans → fondu).
		r.self_modulate.a = 0.0
		for c: Node in r.get_children():
			(c as CanvasItem).visible = false
		var id := int(String(r.name).split("_")[1])
		by_id[id] = r
	var holder := Node2D.new()
	holder.name = "Interiors"
	add_child(holder)
	for e: Dictionary in meta["interiors"]:
		var tex := load(pack_dir + String(e["file"])) as Texture2D
		if tex == null:
			continue
		var p: Array = e["px"]
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.position = origin + Vector2(p[0], p[1]) * px_scale
		s.scale = px_scale
		s.modulate.a = 0.0
		s.visible = false
		holder.add_child(s)
		_interiors.append({"sprite": s, "roof": by_id.get(int(e["id"]))})
	add_to_group(&"prerender_backdrop")


func _process(_delta: float) -> void:
	_stream()
	for e: Dictionary in _interiors:
		var roof: Node2D = e["roof"]
		var s: Sprite2D = e["sprite"]
		if roof == null or not is_instance_valid(roof):
			continue
		# Toit à 1 → intérieur caché ; toit au minimum (hidden_alpha) → intérieur visible.
		var ha := float(roof.get("hidden_alpha"))
		var k := clampf((1.0 - roof.modulate.a) / maxf(1.0 - ha, 0.01), 0.0, 1.0)
		s.modulate.a = k
		s.visible = k > 0.001


## Chargement par morceaux : tuiles qui recoupent la vue (+ marge) chargées en arrière-plan,
## les autres libérées.
func _stream() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var inv := vp.get_canvas_transform().affine_inverse()
	var view := Rect2(inv * Vector2.ZERO, Vector2.ZERO).expand(inv * vp.get_visible_rect().size).grow(stream_margin)
	for t: Dictionary in _tiles:
		var want := view.intersects(t["rect"])
		var spr: Sprite2D = t["sprite"]
		if want and spr == null:
			if not t["pending"]:
				ResourceLoader.load_threaded_request(t["file"])
				t["pending"] = true
			elif ResourceLoader.load_threaded_get_status(t["file"]) == ResourceLoader.THREAD_LOAD_LOADED:
				_make_sprite(t, ResourceLoader.load_threaded_get(t["file"]) as Texture2D)
		elif not want and spr != null:
			spr.queue_free()
			t["sprite"] = null
			t["pending"] = false


func _make_sprite(t: Dictionary, tex: Texture2D) -> void:
	t["pending"] = false
	if tex == null:
		return
	var r: Rect2 = t["rect"]
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.position = r.position
	s.scale = px_scale
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(s)
	move_child(s, 0)
	t["sprite"] = s


## Charge immédiatement (synchrone) toutes les tuiles visibles : premier affichage, captures.
func preload_visible() -> void:
	var vp := get_viewport()
	var inv := vp.get_canvas_transform().affine_inverse()
	var view := Rect2(inv * Vector2.ZERO, Vector2.ZERO).expand(inv * vp.get_visible_rect().size).grow(stream_margin)
	for t: Dictionary in _tiles:
		if t["sprite"] == null and view.intersects(t["rect"]):
			_make_sprite(t, load(t["file"]) as Texture2D)


func loaded_tile_count() -> int:
	var n := 0
	for t: Dictionary in _tiles:
		if t["sprite"] != null:
			n += 1
	return n
