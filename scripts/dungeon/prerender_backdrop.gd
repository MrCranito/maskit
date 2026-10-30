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
## - (Correctif zones interdites) map.json « collision » : rectangles (monde) dérivés du masque
##   d'emprise zénithal du rendu (compose.py) sur les cases praticables du plan : un seul
##   StaticBody2D (couche world) ; raid.gd les ajoute aux obstacles de la navigation.
## - (Occultation) map.json « occluders » : par tuile, image d'ids (o_*.png) + tranches
##   [rangée, bâtiment, x, y, w, h] ; chaque tranche = Sprite2D (région de la tuile du fond,
##   shader prerender_occluder) triée en Y à la limite sud de sa rangée avec les personnages
##   (z 10) : derrière un wagon / rocher / maison, le personnage est masqué. Tranches d'un
##   bâtiment effacées avec son toit (joueur dedans) ; tranche devant le joueur semi-transparente.
## - (Correctif bâtiments qui masquent) Quand le joueur, un allié ou un ennemi VISIBLE (pas
##   caché par le brouillard) passe derrière un volume haut, tout le bâtiment (ou la tranche de
##   décor) passe en fondu doux à [prerender] occluder_fade_alpha : ce qui est derrière (unités,
##   tirs, effets) reste lisible. Test espacé (10 Hz) indexé par rangée, fondu par image
##   seulement pendant la transition. Le fond pré-rendu ne contient pas le sol sous la partie
##   haute du bâtiment : on voit les unités à travers, pas le sol.

const PACK_ROOT := "res://assets/prerender/far_west/"
## (Ajout générique, station) Paquets par biome : res://assets/prerender/<biome>/<seed>/.
const PACK_BASE := "res://assets/prerender/"
const TS := float(FloorLayout.TILE_SIZE)

var meta: Dictionary = {}
var pack_dir := ""
var px_scale := Vector2.ONE           ## px image → monde
var origin := Vector2.ZERO            ## position monde du pixel (0, 0)
var stream_margin := 900.0            ## marge (monde) autour de la vue pour charger
var _tiles: Array[Dictionary] = []    ## {file, rect (monde), sprite, pending}
var _interiors: Array[Dictionary] = []  ## {sprite, roof}
const OCC_SHADER: Shader = preload("res://assets/shaders/prerender_occluder.gdshader")
var collision_body: StaticBody2D = null
var _occ_by_tile: Dictionary = {}       ## fichier de tuile → {ids, slices}
var _occ_holder: Node2D = null
var _roof_by_id: Dictionary = {}
var _occ_alpha_player := 0.55
var _occ_interval := 0.1
var _occ_left := 0.0
var _occ_enabled := true
var _player: Node2D = null
## Fondu « unité derrière » (voir en-tête) : réglages [prerender] occluder_fade_*.
var _fade_enabled := true
var _fade_alpha := 0.3
var _fade_duration := 0.25
var _fade_radius := 28.0
var _fade_height := 88.0
var _fade_enemies := true
var _fade: Dictionary = {}          ## clé de groupe → opacité courante (1 = opaque)
var _fade_target: Dictionary = {}   ## clé de groupe → opacité visée
var _rows: Dictionary = {}          ## rangée → tranches chargées
var _by_key: Dictionary = {}        ## clé de groupe → tranches chargées
var _rows_up := 0                   ## dépassement maximal d'une tranche vers le nord (rangées)
var _index_dirty := true
var _slice_serial := 0


## Dossier des paquets d'un biome (far_west → PACK_ROOT).
static func pack_root(biome: StringName = &"far_west") -> String:
	return PACK_BASE + String(biome) + "/"


## Graines pré-rendues disponibles (dossiers contenant map.json).
static func available_seeds(biome: StringName = &"far_west") -> PackedInt32Array:
	var out := PackedInt32Array()
	var root := pack_root(biome)
	var d := DirAccess.open(root)
	if d == null:
		return out
	for n in d.get_directories():
		if n.is_valid_int() and ResourceLoader.exists(root + n + "/map.json") or FileAccess.file_exists(root + n + "/map.json"):
			out.append(int(n))
	out.sort()
	return out


## true si le biome a au moins un paquet pré-rendu.
static func has_packs(biome: StringName) -> bool:
	return not available_seeds(biome).is_empty()


## Tire une carte pré-rendue au hasard (0 si aucune).
static func pick_seed(rng_seed: int, biome: StringName = &"far_west") -> int:
	var seeds := available_seeds(biome)
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


static func create(map_seed: int, layout: FloorLayout = null, biome: StringName = &"far_west") -> PrerenderBackdrop:
	var dir := pack_root(biome) + str(map_seed) + "/"
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
	# Les tranches d'occultation (enfants) se trient en Y avec les personnages.
	y_sort_enabled = true
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
		_tiles.append({"file": pack_dir + String(t["file"]), "rect": r, "sprite": null, "pending": false,
			"px": p, "slices": []})
	_occ_enabled = bool(_bal("occluders", true))
	_occ_alpha_player = float(_bal("occluder_player_alpha", 0.55))
	_occ_interval = float(_bal("occluder_check_interval", 0.1))
	_fade_enabled = bool(_bal("occluder_fade", true))
	_fade_alpha = clampf(float(_bal("occluder_fade_alpha", 0.3)), 0.0, 1.0)
	_fade_duration = maxf(float(_bal("occluder_fade_duration", 0.25)), 0.0)
	_fade_radius = float(_bal("occluder_fade_radius", 28.0))
	_fade_height = float(_bal("occluder_fade_height", 88.0))
	_fade_enemies = bool(_bal("occluder_fade_enemies", true))
	for e: Dictionary in meta.get("occluders", []):
		_occ_by_tile[pack_dir + String(e["tile"])] = e


func _bal(key: String, def: Variant) -> Variant:
	var b: Node = Engine.get_main_loop().root.get_node_or_null(^"/root/Balance") if Engine.get_main_loop() is SceneTree else null
	return b.call(&"get_value", "prerender", key, def) if b != null else def


## tan(inclinaison) de la caméra du rendu (une hauteur z cases remonte de z·tan cases à l'écran).
func tan_tilt() -> float:
	return tan(deg_to_rad(float(meta.get("tilt_deg", 38.0))))


## Rectangles (monde) de la couche « emprise rendue » (vide si le paquet n'en a pas).
func collision_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not bool(_bal("collision", true)):
		return out
	for r: Array in meta.get("collision", []):
		out.append(Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
	return out


## Un seul corps statique (couche world) pour toute la couche « emprise rendue ».
func _build_collision() -> void:
	var rects := collision_rects()
	if rects.is_empty():
		return
	collision_body = StaticBody2D.new()
	collision_body.name = "RenderedFootprint"
	collision_body.collision_layer = 1
	collision_body.collision_mask = 0
	for r in rects:
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = r.size
		cs.shape = sh
		cs.position = r.get_center()
		collision_body.add_child(cs)
	add_child(collision_body)


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
	# (Ajout générique) Constructeur de biome : masque ses propres visuels remplacés par le rendu.
	if builder.has_method("prerender_hide"):
		builder.call("prerender_hide")
	var roofs: Array = builder.call("get_roofs") if builder.has_method("get_roofs") else []
	var by_id := {}
	for r: Node2D in roofs:
		# Le toit 2D ne dessine plus rien mais garde sa logique (joueur dedans → fondu).
		r.self_modulate.a = 0.0
		for c: Node in r.get_children():
			(c as CanvasItem).visible = false
		var id := int(String(r.name).split("_")[1])
		by_id[id] = r
	_roof_by_id = by_id
	_build_collision()
	ensure_occluder_holder()
	var holder := Node2D.new()
	holder.name = "Interiors"
	holder.z_index = 1  # au-dessus des tuiles (z 0) malgré le tri en Y du fond
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


## Parent des tranches d'occultation (trié en Y avec les personnages, z 10).
func ensure_occluder_holder() -> void:
	if _occ_holder != null:
		return
	_occ_holder = Node2D.new()
	_occ_holder.name = "Occluders"
	_occ_holder.y_sort_enabled = true
	_occ_holder.z_index = 10
	add_child(_occ_holder)


func _process(delta: float) -> void:
	_stream()
	_update_player_feet()
	_occ_left -= delta
	if _occ_left <= 0.0:
		_occ_left = _occ_interval
		_update_occluders()
	_step_fades(delta)
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


## Forçage pour les tests (-1 : automatique, 0 : synchrone, 1 : en arrière-plan).
static var threaded_loading_override := -1


## Chargement en arrière-plan sans risque ? Non sous le serveur de rendu factice (--headless :
## bot de playtest, tests, serveur) : son registre de textures (RendererDummy::TextureStorage)
## n'est pas protégé contre les accès concurrents. Une texture créée par le fil de chargement
## pendant que le fil principal en crée une autre corrompt le registre → « texture_storage.h:85
## Parameter "t" is null » (texture_2d_initialize) et RID perdus. Les vrais moteurs de rendu
## (Forward+, Mobile, Compatibility) sont protégés : on garde le fil de chargement en jeu.
static func threaded_loading_safe() -> bool:
	if threaded_loading_override >= 0:
		return threaded_loading_override == 1
	return DisplayServer.get_name() != "headless"


## Chargement par morceaux : tuiles qui recoupent la vue (+ marge) chargées en arrière-plan
## (synchrone sous le rendu factice, voir threaded_loading_safe), les autres libérées.
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
			if not threaded_loading_safe() and not t["pending"]:
				# Serveur de rendu factice : chargement synchrone (voir threaded_loading_safe).
				_make_sprite(t, load(t["file"]) as Texture2D)
			elif not t["pending"]:
				ResourceLoader.load_threaded_request(t["file"])
				t["pending"] = true
			elif ResourceLoader.load_threaded_get_status(t["file"]) == ResourceLoader.THREAD_LOAD_LOADED:
				_make_sprite(t, ResourceLoader.load_threaded_get(t["file"]) as Texture2D)
		elif not want and spr != null:
			spr.queue_free()
			t["sprite"] = null
			t["pending"] = false
			for sl: Dictionary in t["slices"]:
				(sl["sprite"] as Node).queue_free()
				var k: int = sl["key"]
				if k < 0:  # tranche de décor isolée : son état de fondu disparaît avec elle
					_fade.erase(k)
					_fade_target.erase(k)
			if not (t["slices"] as Array).is_empty():
				_index_dirty = true
			t["slices"] = []


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
	_make_slices(t, tex)


## Tranches d'occultation d'une tuile chargée (voir en-tête).
func _make_slices(t: Dictionary, tex: Texture2D) -> void:
	if not _occ_enabled or _occ_holder == null or not _occ_by_tile.has(t["file"]):
		return
	var e: Dictionary = _occ_by_tile[t["file"]]
	var ids := load(pack_dir + String(e["ids"])) as Texture2D
	if ids == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = OCC_SHADER
	mat.set_shader_parameter(&"id_tex", ids)
	mat.set_shader_parameter(&"player_alpha", _occ_alpha_player)
	t["mat"] = mat
	var p: Array = t["px"]
	for sl: Array in e["slices"]:
		var row := int(sl[0])
		var bid := int(sl[1])
		var tl := origin + Vector2(float(sl[2]), float(sl[3])) * px_scale
		var sort_y := float(row + 1) * TS
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.centered = false
		sp.region_enabled = true
		sp.region_rect = Rect2(float(sl[2]) - float(p[0]), float(sl[3]) - float(p[1]), float(sl[4]), float(sl[5]))
		sp.position = Vector2(tl.x, sort_y)
		sp.offset = Vector2(0.0, (tl.y - sort_y) / px_scale.y)
		sp.scale = px_scale
		sp.material = mat
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sp.modulate = Color(float(row + 1) / 255.0, float(bid + 1) / 255.0, 1.0, 1.0)
		_occ_holder.add_child(sp)
		# Groupe de fondu : tout le bâtiment (id ≥ 0), sinon la tranche de décor seule (clé < 0).
		_slice_serial += 1
		var key := bid if bid >= 0 else -_slice_serial
		(t["slices"] as Array).append({"sprite": sp, "bid": bid, "row": row, "key": key, "roof_a": 1.0,
			"rect": Rect2(tl, Vector2(float(sl[4]), float(sl[5])) * px_scale), "sort_y": sort_y})
	_index_dirty = true


## Opacité des tranches : bâtiment dont le toit s'efface (joueur dedans) → tranches effacées.
## Silhouette du joueur derrière une tranche : gérée par le shader (pieds du joueur passés à
## chaque matériau de tuile).
func _update_occluders() -> void:
	if _occ_holder == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node2D
	if _index_dirty:
		_rebuild_index()
	_update_fade_targets()
	for t: Dictionary in _tiles:
		for sl: Dictionary in t["slices"]:
			var a := 1.0
			var bid: int = sl["bid"]
			if bid >= 0:
				var roof: Node2D = _roof_by_id.get(bid)
				if roof != null and is_instance_valid(roof):
					var ha := float(roof.get("hidden_alpha"))
					a = 1.0 - clampf((1.0 - roof.modulate.a) / maxf(1.0 - ha, 0.01), 0.0, 1.0)
			sl["roof_a"] = a
			_apply_slice(sl)


## Opacité finale d'une tranche : toit (joueur dedans) × fondu « unité derrière ».
func _apply_slice(sl: Dictionary) -> void:
	var a: float = float(sl["roof_a"]) * float(_fade.get(sl["key"], 1.0))
	var sp: Sprite2D = sl["sprite"]
	if absf(sp.modulate.b - a) > 0.005:
		sp.modulate.b = a
	sp.visible = a > 0.01


## Index des tranches chargées par rangée et par groupe de fondu (après chargement/libération).
func _rebuild_index() -> void:
	_index_dirty = false
	_rows.clear()
	_by_key.clear()
	_rows_up = 0
	for t: Dictionary in _tiles:
		for sl: Dictionary in t["slices"]:
			(_rows.get_or_add(int(sl["row"]), []) as Array).append(sl)
			(_by_key.get_or_add(sl["key"], []) as Array).append(sl)
			var r: Rect2 = sl["rect"]
			_rows_up = maxi(_rows_up, ceili((float(sl["sort_y"]) - r.position.y) / TS))
	for k: Variant in _by_key:
		if not _fade.has(k):
			_fade[k] = 1.0


## Pieds des unités à dévoiler : joueur(s), alliés coop et ennemis visibles (un ennemi caché
## par le brouillard est invisible → ignoré : le fondu ne trahit pas sa présence).
func _reveal_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var groups: Array[StringName] = [&"player", NetHooks.GROUP_AVATAR]
	if _fade_enemies:
		groups.append(&"enemies")
	for g in groups:
		for n: Node in get_tree().get_nodes_in_group(g):
			var u := n as Node2D
			if u != null and u.is_visible_in_tree():
				pts.append(u.global_position)
	return pts


## Groupes (bâtiment ou tranche de décor) dont une tranche triée au sud des pieds d'une unité
## recouvre son corps → opacité visée occluder_fade_alpha, sinon 1.
func _update_fade_targets() -> void:
	for k: Variant in _fade_target:
		_fade_target[k] = 1.0
	if not _fade_enabled or _rows.is_empty():
		return
	for f: Vector2 in _reveal_points():
		var body := Rect2(f.x - _fade_radius, f.y - _fade_height, _fade_radius * 2.0, _fade_height)
		var frow := floori(f.y / TS)
		for row in range(frow, frow + _rows_up + 1):
			var arr: Variant = _rows.get(row)
			if arr == null:
				continue
			for sl: Dictionary in arr:
				if float(sl["sort_y"]) > f.y and (sl["rect"] as Rect2).intersects(body):
					_fade_target[sl["key"]] = _fade_alpha


## Fondu doux vers l'opacité visée : seuls les groupes en transition sont recalculés.
func _step_fades(delta: float) -> void:
	if _fade_target.is_empty():
		return
	var rate := (1.0 - _fade_alpha) / _fade_duration if _fade_duration > 0.0 else INF
	for k: Variant in _fade_target:
		var cur: float = _fade.get(k, 1.0)
		var goal: float = _fade_target[k]
		if is_equal_approx(cur, goal):
			continue
		cur = goal if is_inf(rate) else move_toward(cur, goal, rate * delta)
		_fade[k] = cur
		var arr: Variant = _by_key.get(k)
		if arr != null:
			for sl: Dictionary in arr:
				if is_instance_valid(sl["sprite"]):
					_apply_slice(sl)


## Opacité de fondu courante d'un bâtiment (id) ou d'un groupe (tests, debug).
func fade_of(key: int) -> float:
	return float(_fade.get(key, 1.0))


## Tranches chargées (tests, captures).
func loaded_slices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in _tiles:
		for sl: Dictionary in t["slices"]:
			out.append(sl)
	return out


## Pieds du joueur → matériaux des tuiles (silhouette lisible derrière une tranche), chaque image.
func _update_player_feet() -> void:
	if _occ_holder == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node2D
	var feet := Vector2(-100000.0, -100000.0)
	if _player != null:
		feet = _player.global_position
	for t: Dictionary in _tiles:
		if t.get("mat") is ShaderMaterial and not (t["slices"] as Array).is_empty():
			(t["mat"] as ShaderMaterial).set_shader_parameter(&"player_feet", feet)


func slice_count() -> int:
	var n := 0
	for t: Dictionary in _tiles:
		n += (t["slices"] as Array).size()
	return n


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
