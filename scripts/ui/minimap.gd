class_name MiniMap
extends Control
## Mini-carte (haut droite, sous le sac/pause, dans la zone sûre) :
##   - carte autour du joueur : version réduite de l'image du paquet pré-rendu
##     (assets/prerender/<biome>/<seed>/minimap.webp, ~18 px par case, mipmaps), sinon plan
##     vectoriel de l'étage (MinimapPlan : aplats, murs en traits nets) ;
##   - seules les cases explorées sont visibles : la mémoire d'exploration de FogOfWar
##     (texture partagée, mise à jour par le brouillard quand une case est découverte) est
##     lissée par assets/shaders/minimap_fog.gdshader (bords doux et irréguliers, liseré) ;
##   - cadre direction D (CutBox, coins coupés, liseré violet), léger vignettage ;
##   - position et orientation (visée) du joueur, au centre ;
##   - zones d'extraction toujours affichées avec leur minuteur (orange avant fermeture, grise
##     et barrée une fois fermée, zone d'urgence cachée tant qu'elle est éteinte) ; si la plus
##     proche zone OUVERTE sort du cadre, flèche au bord vers elle (distance · temps restant) ;
##   - toucher / clic (ou touche M) = carte plein écran (jeu en pause), zoomable et déplaçable
##     (voir FullMapOverlay) ; bouton ×, toucher hors du panneau, M ou Échap pour fermer.
## Performance : rafraîchie par un Timer ([minimap] refresh_interval ≈ 0,1 s), sans allocation :
## on déplace un nœud (transformations), on ne redessine pas. La brume ne coûte rien côté CPU :
## la texture d'exploration appartient à FogOfWar, qui ne la met à jour que sur découverte de
## cases ; le plan vectoriel est calculé une fois par étage et dessiné une fois. Repli (pas de
## texture de brouillard, ex. tests sans rendu) : relecture des cases autour du joueur, texture
## mise à jour seulement si une case change ; durée mesurée dans last_fog_update_usec.

signal full_map_toggled(open: bool)

const NIGHT := Color(0.024, 0.027, 0.05)
const BORDER := Color(1.0, 1.0, 1.0, 0.4)
const EXTRACT := Color(0.718, 0.608, 1.0)
const TS := float(FloorLayout.TILE_SIZE)
const FOG_SHADER: Shader = preload("res://assets/shaders/minimap_fog.gdshader")
const VIGNETTE_SHADER: Shader = preload("res://assets/shaders/minimap_vignette.gdshader")
## Uniformes de minimap_fog.gdshader réglés depuis balance.cfg [minimap] (clé fog_<nom>).
const FOG_PARAMS: Array[String] = ["fog_color", "mist_color", "mist_amount", "rim_color", "rim_px",
	"rim_offset", "threshold", "edge_soft", "edge_px", "noise_amp", "noise_cells"]
## Marge de brume autour de la grille (cases) : le bord de la carte reste sous la brume.
const FOG_MARGIN_CELLS := 48

static var _fog_material: ShaderMaterial = null

var raid: Node = null
var layout: FloorLayout = null
var fog: Node = null
var player: Node2D = null
## Rectangle monde couvert par l'image de fond.
var bg_world_rect: Rect2 = Rect2()
var bg_texture: Texture2D = null
var view: MapView = null
var full_map: FullMapOverlay = null

## Plan vectoriel de l'étage (étages sans image pré-rendue), sinon null.
var plan_geometry: MinimapPlan.Geometry = null
## Durée de la dernière mise à jour de la brume (µs) et cases relues (0 avec la texture partagée).
var last_fog_update_usec: int = 0
var last_fog_cells_scanned: int = 0
## Image de repli (sans texture FogOfWar) ; null quand la texture du brouillard est partagée.
var _fog_img: Image = null
var _fog_tex: Texture2D = null
var _zone_centers: PackedVector2Array = PackedVector2Array()
var _timer: Timer = null
var _arrow: EdgeArrow = null
var _arrow_label: Label = null
var _last_dist: int = -1
var _last_arrow_text: String = ""
## Zones d'extraction (ExtractionZone) alignées sur _zone_centers ; vide = cases seules.
var _zones: Array[Node2D] = []
var _scan_radius: int = 12
var _box: float = 168.0
## Raisons d'effacement en cours (fouille, inventaire) : mini-carte invisible et sans saisie.
var _obscured: Dictionary = {}
var _fade: Tween = null


static func create(p_raid: Node) -> MiniMap:
	var m := MiniMap.new()
	m.raid = p_raid
	return m


func _ready() -> void:
	name = "MiniMap"
	_box = Balance.get_float("minimap", "size", 168.0)
	custom_minimum_size = Vector2(_box, _box)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	view = MapView.new()
	view.vignette = Balance.get_float("minimap", "vignette_strength", 0.55)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	_arrow = EdgeArrow.new()
	_arrow.visible = false
	add_child(_arrow)
	_arrow_label = Label.new()
	_arrow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow_label.label_settings = LootVisuals.label_settings(LootVisuals.text_font(900), 13, EXTRACT.lightened(0.3), 4)
	_arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrow_label.size = Vector2(56, 18)
	_arrow_label.visible = false
	add_child(_arrow_label)
	_timer = Timer.new()
	_timer.wait_time = Balance.get_float("minimap", "refresh_interval", 0.1)
	_timer.timeout.connect(_tick)
	add_child(_timer)
	get_viewport().size_changed.connect(place)
	EventBus.floor_changed.connect(func(_i: int) -> void: rebuild.call_deferred())
	place()
	rebuild()


## En haut à droite, sous le bouton sac / pause, dans la zone sûre.
func place() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var m := HudSafeArea.margins(self)
	var top := m.y + Balance.get_float("minimap", "top_offset", 90.0)
	position = Vector2(vp.x - m.z - _box, top)
	size = Vector2(_box, _box)


# --- Construction (au chargement d'un étage) ----------------------------------------

func rebuild() -> void:
	if raid == null or not is_instance_valid(raid):
		return
	layout = raid.get("layout") as FloorLayout
	fog = raid.get("fog") as Node
	player = raid.get("player") as Node2D
	if layout == null:
		visible = false
		return
	visible = true
	_build_background()
	_build_fog_mask()
	_zone_centers.clear()
	_zones.clear()
	var zones: Variant = raid.get("extraction_zones")
	if zones is Array:
		for z: Variant in zones:
			if z is Node2D and is_instance_valid(z):
				_zone_centers.append((z as Node2D).global_position)
				_zones.append(z as Node2D)
	if _zone_centers.is_empty():
		for c: Vector2i in layout.extraction_cells:
			_zone_centers.append(FloorLayout.cell_to_world(c))
	var fv: Variant = fog.get("view_radius") if fog != null else null
	_scan_radius = (int(fv) if fv != null else 10) + 2
	var view_cells := Balance.get_float("minimap", "view_cells", 24.0)
	view.setup(bg_texture, bg_world_rect, _fog_tex, Vector2(layout.size), _zone_centers, TS * view_cells / _box, plan_geometry)
	view.set_zone_states(zone_states())
	if full_map != null and is_instance_valid(full_map):
		full_map.close()
	_tick()
	_timer.start()


## Fond : image réduite du paquet pré-rendu (étage 0) ou plan vectoriel de l'étage.
func _build_background() -> void:
	bg_texture = null
	plan_geometry = null
	var pr: Variant = raid.get("prerender")
	if pr is PrerenderBackdrop and is_instance_valid(pr):
		var b := pr as PrerenderBackdrop
		var path := b.pack_dir + "minimap.webp"
		if ResourceLoader.exists(path):
			bg_texture = load(path) as Texture2D
			var ip: Array = b.meta.get("image_px", [0, 0])
			bg_world_rect = Rect2(b.origin, Vector2(float(ip[0]), float(ip[1])) * b.px_scale)
	if bg_texture == null:
		bg_world_rect = Rect2(Vector2.ZERO, Vector2(layout.size) * TS)
		plan_geometry = MinimapPlan.Geometry.build(layout)


## Fond vectoriel en place (étage sans image pré-rendue).
func has_vector_plan() -> bool:
	return plan_geometry != null


## Masque d'exploration : la texture de FogOfWar (partagée, 1 texel par case) ; repli : image
## locale relue en entier une seule fois par étage (pas de brouillard → tout découvert).
func _build_fog_mask() -> void:
	_fog_img = null
	_fog_tex = null
	if fog != null and fog.has_method("get_explored_texture"):
		_fog_tex = fog.call("get_explored_texture") as Texture2D
	if _fog_tex != null:
		return
	_fog_img = Image.create(maxi(layout.size.x, 1), maxi(layout.size.y, 1), false, Image.FORMAT_L8)
	_fog_img.fill(Color(0, 0, 0))
	if fog != null and fog.has_method("is_cell_explored"):
		for y in layout.size.y:
			for x in layout.size.x:
				if bool(fog.call("is_cell_explored", Vector2i(x, y))):
					_fog_img.set_pixel(x, y, Color(1, 1, 1))
	else:
		_fog_img.fill(Color(1, 1, 1))
	_fog_tex = ImageTexture.create_from_image(_fog_img)


## Brume partagée par la mini-carte et la carte plein écran (réglages [minimap] fog_*).
static func fog_material() -> ShaderMaterial:
	if _fog_material == null:
		_fog_material = ShaderMaterial.new()
		_fog_material.shader = FOG_SHADER
		for k: String in FOG_PARAMS:
			var v: Variant = Balance.get_value("minimap", "fog_" + k if not k.begins_with("fog_") else k, null)
			if v != null:
				_fog_material.set_shader_parameter(StringName(k), v)
	return _fog_material


## Vrai si la brume lit directement la texture d'exploration de FogOfWar (aucune copie).
func uses_shared_fog_texture() -> bool:
	return _fog_img == null and _fog_tex != null


# --- Mise à jour espacée ---------------------------------------------------------------

func _tick() -> void:
	if not is_instance_valid(player):
		player = raid.get("player") as Node2D if raid != null and is_instance_valid(raid) else null
		if player == null:
			return
	var pos := player.global_position
	_update_fog(pos)
	view.follow(pos, _aim_angle())
	var states := zone_states()
	view.set_zone_states(states)
	_update_arrow(pos, states)
	if full_map != null and is_instance_valid(full_map) and full_map.visible:
		full_map.view.set_player(pos, _aim_angle())
		full_map.view.set_zone_states(states)


## État affiché de chaque zone : {"state": ExtractionZone.State, "text": minuteur}.
func zone_states() -> Array:
	var out: Array = []
	var clock: Variant = raid.get("raid_clock") if raid != null and is_instance_valid(raid) else null
	var t := float(clock) if clock != null else 0.0
	for i in _zone_centers.size():
		var z: ExtractionZone = _zones[i] as ExtractionZone if i < _zones.size() else null
		if z == null or not is_instance_valid(z):
			out.append({"state": ExtractionZone.State.OPEN, "text": ""})
			continue
		var txt := ""
		if z.state == ExtractionZone.State.CLOSED:
			txt = ""
		elif z.closes_at != INF:
			txt = ExtractionZone.format_time(z.closes_at - t)
		elif z.emergency:
			txt = "!"
		out.append({"state": z.state, "text": txt})
	return out


func _aim_angle() -> float:
	var d: Variant = player.get("aim_direction")
	return (d as Vector2).angle() if d is Vector2 and (d as Vector2) != Vector2.ZERO else 0.0


## Texture partagée : rien à faire (FogOfWar la met à jour sur découverte). Repli : relit les
## cases autour du joueur ; met à jour la texture seulement si une case change.
func _update_fog(pos: Vector2) -> void:
	last_fog_cells_scanned = 0
	if fog == null or not is_instance_valid(fog) or _fog_img == null:
		last_fog_update_usec = 0
		return
	var t0 := Time.get_ticks_usec()
	var pc := FloorLayout.world_to_cell(pos)
	var changed := false
	var x0 := maxi(pc.x - _scan_radius, 0)
	var x1 := mini(pc.x + _scan_radius, layout.size.x - 1)
	var y0 := maxi(pc.y - _scan_radius, 0)
	var y1 := mini(pc.y + _scan_radius, layout.size.y - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if _fog_img.get_pixel(x, y).r < 0.5 and bool(fog.call("is_cell_explored", Vector2i(x, y))):
				_fog_img.set_pixel(x, y, Color(1, 1, 1))
				changed = true
	last_fog_cells_scanned = (x1 - x0 + 1) * (y1 - y0 + 1)
	if changed:
		(_fog_tex as ImageTexture).update(_fog_img)
	last_fog_update_usec = Time.get_ticks_usec() - t0


## Flèche au bord vers l'extraction la plus proche quand elle sort du cadre.
func _update_arrow(pos: Vector2, states: Array = []) -> void:
	var best := -1
	var best_d := INF
	for i in _zone_centers.size():
		if i < states.size() and int(states[i]["state"]) >= ExtractionZone.State.CLOSED:
			continue
		var d := pos.distance_squared_to(_zone_centers[i])
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		_arrow.visible = false
		_arrow_label.visible = false
		return
	var local := view.world_to_local(_zone_centers[best])
	var half := _box * 0.5
	var inner := half - 14.0
	var rel := local - Vector2(half, half)
	if absf(rel.x) <= inner and absf(rel.y) <= inner:
		_arrow.visible = false
		_arrow_label.visible = false
		return
	var k := inner / maxf(absf(rel.x), absf(rel.y))
	var edge := Vector2(half, half) + rel * k
	_arrow.visible = true
	_arrow.position = edge
	_arrow.rotation = rel.angle()
	var meters := int(round(sqrt(best_d) / TS * Balance.get_float("minimap", "meters_per_cell", 2.0)))
	var tt := String(states[best]["text"]) if best < states.size() else ""
	var at := "%d m · %s" % [meters, tt] if tt != "" and tt != "!" else "%d m" % meters
	if meters != _last_dist or at != _last_arrow_text:
		_last_dist = meters
		_last_arrow_text = at
		_arrow_label.text = at
	_arrow_label.visible = true
	var lp := edge - rel.normalized() * 26.0 - _arrow_label.size * 0.5
	_arrow_label.position = lp.clamp(Vector2(2, 2), Vector2(_box, _box) - _arrow_label.size - Vector2(2, 2))


# --- Carte plein écran -----------------------------------------------------------------

func toggle_full_map() -> void:
	if full_map != null and is_instance_valid(full_map) and full_map.visible:
		full_map.close()
	else:
		open_full_map()


func open_full_map() -> void:
	if layout == null or is_obscured():
		return
	if full_map == null or not is_instance_valid(full_map):
		full_map = FullMapOverlay.new()
		full_map.closed.connect(func() -> void: full_map_toggled.emit(false))
		get_parent().add_child(full_map)
		# Juste au-dessus de la mini-carte, sous la couche de butin (inventaire au-dessus).
		get_parent().move_child(full_map, get_index() + 1)
	full_map.open_with(self)
	full_map_toggled.emit(true)


## Efface (fondu) la mini-carte tant qu'une fenêtre de butin / l'inventaire est ouvert ;
## l'inventaire ferme aussi la carte plein écran.
func set_obscured(reason: StringName, on: bool) -> void:
	if on:
		_obscured[reason] = true
		if reason == &"inventory" and is_full_map_open():
			full_map.close()
	else:
		_obscured.erase(reason)
	var target := 0.0 if is_obscured() else 1.0
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if not is_inside_tree():
		modulate.a = target
		return
	_fade = create_tween()
	_fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade.tween_property(self, "modulate:a", target, 0.15)


func is_obscured() -> bool:
	return not _obscured.is_empty()


func is_full_map_open() -> bool:
	return full_map != null and is_instance_valid(full_map) and full_map.visible


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or is_full_map_open() or is_obscured():
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		if get_global_rect().has_point((event as InputEventScreenTouch).position):
			get_viewport().set_input_as_handled()
			open_full_map()


func _gui_input(event: InputEvent) -> void:
	if is_obscured():
		return
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			toggle_full_map()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).physical_keycode == KEY_M:
		get_viewport().set_input_as_handled()
		toggle_full_map()


## Nombre de cases explorées connues de la mini-carte (tests / debug).
func explored_count() -> int:
	var n := 0
	if _fog_img == null:
		if fog == null or not is_instance_valid(fog) or layout == null:
			return 0
		for y in layout.size.y:
			for x in layout.size.x:
				if bool(fog.call("is_cell_explored", Vector2i(x, y))):
					n += 1
		return n
	for y in _fog_img.get_height():
		for x in _fog_img.get_width():
			if _fog_img.get_pixel(x, y).r > 0.5:
				n += 1
	return n


func is_arrow_visible() -> bool:
	return _arrow.visible


func get_arrow_text() -> String:
	return _arrow_label.text if _arrow_label.visible else ""


# =====================================================================================

## Vue de carte (fond + brume d'exploration + extractions + joueur), découpée par un masque
## à coins coupés (CutBox). Le contenu est en coordonnées monde dans `content`
## (échelle = px / px monde). Par-dessus : vignettage (shader statique) puis cadre.
class MapView extends Control:
	const CUT := 18.0
	var mask: Panel = null
	var content: Node2D = null
	var frame: Control = null
	var vignette_rect: ColorRect = null
	var player_mark: PlayerMark = null
	var plan: MinimapPlan = null
	var px_per_world: float = 0.1
	## Force du vignettage (0 = aucun), à régler avant l'entrée dans l'arbre.
	var vignette: float = 0.0
	var _icons: Array[Node2D] = []
	var _fit_rect: Rect2 = Rect2()

	func _ready() -> void:
		mask = Panel.new()
		mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mask.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		# maquette Hud : encre, coins haut droit et bas gauche coupés
		var st := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.96), CUT, Color(0, 0, 0, 0), 0.0, 0.0, 0.0)
		st.corners = CutBox.CUT_TOP_RIGHT | CutBox.CUT_BOTTOM_LEFT
		mask.add_theme_stylebox_override("panel", st)
		add_child(mask)
		content = Node2D.new()
		mask.add_child(content)
		if vignette > 0.0:
			vignette_rect = ColorRect.new()
			vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var vm := ShaderMaterial.new()
			vm.shader = MiniMap.VIGNETTE_SHADER
			vm.set_shader_parameter(&"strength", vignette)
			vm.set_shader_parameter(&"ink", MenuKit.NIGHT_DEEP)
			vm.set_shader_parameter(&"start", Balance.get_float("minimap", "vignette_start", 0.55))
			vignette_rect.material = vm
			mask.add_child(vignette_rect)
		frame = Control.new()
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.draw.connect(_draw_frame)
		add_child(frame)
		resized.connect(func() -> void:
			frame.queue_redraw()
			if _fit_rect.has_area():
				fit(_fit_rect))

	## Cadre : contour fin anti-crénelé (couvre aussi le bord du masque) + biseaux soulignés de
	## violet (accent direction D). Redessiné seulement au redimensionnement.
	func _draw_frame() -> void:
		var fs := CutBox.new()
		fs.cut = CUT
		fs.corners = CutBox.CUT_TOP_RIGHT | CutBox.CUT_BOTTOM_LEFT
		var r := Rect2(Vector2.ZERO, frame.size).grow(-0.5)
		var pts := fs.points(r)
		var loop := pts.duplicate()
		loop.append(pts[0])
		frame.draw_polyline(loop, Color(MenuKit.NIGHT_DEEP, 0.9), 3.0, true)
		frame.draw_polyline(loop, Color(1, 1, 1, Balance.get_float("minimap", "frame_alpha", 0.32)), 1.25, true)
		var acc := Color(MenuKit.GOLD, 0.95)
		var tr := Vector2(r.end.x, r.position.y)
		var bl := Vector2(r.position.x, r.end.y)
		frame.draw_line(tr - Vector2(CUT, 0), tr + Vector2(0, CUT), acc, 2.0, true)
		frame.draw_line(bl + Vector2(CUT, 0), bl - Vector2(0, CUT), acc, 2.0, true)

	## (Re)construit le contenu. world_per_px = px monde par px écran. Sans image de fond,
	## `plan_geom` (plan vectoriel) la remplace.
	func setup(bg: Texture2D, bg_rect: Rect2, fog_tex: Texture2D, grid: Vector2, zones: PackedVector2Array, world_per_px: float,
			plan_geom: MinimapPlan.Geometry = null) -> void:
		for c: Node in content.get_children():
			content.remove_child(c)
			c.queue_free()
		_icons.clear()
		plan = null
		px_per_world = 1.0 / maxf(world_per_px, 0.001)
		content.scale = Vector2(px_per_world, px_per_world)
		if bg == null and plan_geom != null:
			plan = MinimapPlan.create(plan_geom)
			content.add_child(plan)
		if bg != null:
			# Fond découpé à la grille du plan (les marges du rendu restent hors carte).
			var grid_rect := Rect2(Vector2.ZERO, grid * TS).intersection(bg_rect)
			var k := bg.get_size() / bg_rect.size
			var s := Sprite2D.new()
			s.texture = bg
			s.centered = false
			s.region_enabled = true
			s.region_rect = Rect2((grid_rect.position - bg_rect.position) * k, grid_rect.size * k)
			s.position = grid_rect.position
			s.scale = Vector2.ONE / k
			s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			content.add_child(s)
		if fog_tex != null:
			# Masque d'exploration lissé par le shader ; le sprite déborde de FOG_MARGIN_CELLS
			# autour de la grille (hors grille = non exploré) pour que le bord reste sous la brume.
			var f := Sprite2D.new()
			f.name = "Fog"
			f.texture = fog_tex
			f.centered = false
			var k := Vector2(TS, TS) * grid / fog_tex.get_size()
			var m := Vector2(FOG_MARGIN_CELLS, FOG_MARGIN_CELLS) * fog_tex.get_size() / grid
			f.region_enabled = true
			f.region_rect = Rect2(-m, fog_tex.get_size() + m * 2.0)
			f.position = -m * k
			f.scale = k
			f.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			f.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			f.material = MiniMap.fog_material()
			content.add_child(f)
		for z: Vector2 in zones:
			var ic := ExtractIcon.new()
			ic.position = z
			ic.scale = Vector2.ONE / px_per_world
			content.add_child(ic)
			_icons.append(ic)
		player_mark = PlayerMark.new()
		player_mark.scale = Vector2.ONE / px_per_world
		content.add_child(player_mark)

	## Centre la vue sur `pos` (mini-carte).
	func follow(pos: Vector2, angle: float) -> void:
		content.position = size * 0.5 - pos * px_per_world
		set_player(pos, angle)

	## Cadre fixe : toute la zone `rect` (monde) tient dans la vue (carte plein écran).
	func fit(rect: Rect2) -> void:
		_fit_rect = rect
		var k := minf(size.x / maxf(rect.size.x, 1.0), size.y / maxf(rect.size.y, 1.0))
		px_per_world = k
		content.scale = Vector2(k, k)
		content.position = size * 0.5 - rect.get_center() * k
		for ic: Node2D in _icons:
			ic.scale = Vector2.ONE / k * 1.25
		if player_mark != null:
			player_mark.scale = Vector2.ONE / k * 1.25

	## Cadrage zoomable (carte plein écran) : échelle et position de `z` ; les icônes gardent
	## une taille écran constante (`icon_scale`), la brume suit la carte.
	func apply_zoom(z: MapZoom, icon_scale: float = 1.25) -> void:
		px_per_world = z.scale
		content.scale = Vector2(z.scale, z.scale)
		content.position = z.offset
		var s := Vector2.ONE / z.scale * icon_scale
		for ic: Node2D in _icons:
			ic.scale = s
		if player_mark != null:
			player_mark.scale = s

	func set_player(pos: Vector2, angle: float) -> void:
		if player_mark != null:
			player_mark.position = pos
			player_mark.rotation = angle

	## État des icônes d'extraction (minuteur, fermée, cachée), dans l'ordre de setup.
	func set_zone_states(states: Array) -> void:
		for i in mini(states.size(), _icons.size()):
			var ic := _icons[i] as ExtractIcon
			if ic != null:
				ic.set_state(int(states[i]["state"]), String(states[i]["text"]))

	func world_to_local(p: Vector2) -> Vector2:
		return content.position + p * px_per_world


## Polygone plein au bord anti-crénelé (contour fin de même couleur).
static func draw_aa_polygon(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	ci.draw_colored_polygon(pts, col)
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, col, 1.0, true)


## Joueur : flèche blanche cerclée (pointe vers la visée), tracés anti-crénelés.
class PlayerMark extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2(0, 1.0), 10.5, Color(0, 0, 0, 0.35), true, -1.0, true)
		draw_circle(Vector2.ZERO, 9.0, Color(0.05, 0.07, 0.13, 0.9), true, -1.0, true)
		MiniMap.draw_aa_polygon(self, PackedVector2Array([Vector2(10, 0), Vector2(-6, -7), Vector2(-2, 0), Vector2(-6, 7)]), Color(1, 0.96, 0.9))
		draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 40, Color(1.0, 0.8, 0.4), 1.75, true)


## Icône d'extraction (pastille verte + pictogramme de sortie).
## Minuteur sous l'icône ; orange avant fermeture ; grise et barrée une fois fermée ; cachée
## tant que la zone (d'urgence) est éteinte.
class ExtractIcon extends Node2D:
	var state: int = 0
	var text: String = ""

	func set_state(st: int, t: String) -> void:
		if st == state and t == text:
			return
		state = st
		text = t
		visible = st != ExtractionZone.State.DORMANT
		queue_redraw()

	func _draw() -> void:
		var closed := state == ExtractionZone.State.CLOSED
		var col := EXTRACT
		if closed:
			col = Color(0.55, 0.56, 0.62)
		elif state == ExtractionZone.State.CLOSING or text == "!":
			col = ExtractionZone.COL_WARN
		draw_circle(Vector2(0, 1.5), 11.0, Color(0, 0, 0, 0.4), true, -1.0, true)
		draw_circle(Vector2.ZERO, 10.0, Color(0.04, 0.05, 0.09, 0.95) if closed else Color(0.04, 0.12, 0.09, 0.95), true, -1.0, true)
		draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 40, col, 2.5, true)
		ExtractionZone.draw_exit_glyph(self, Vector2.ZERO, 6.0, col.lightened(0.3))
		if closed:
			draw_line(Vector2(-8, -8), Vector2(8, 8), Color(0.85, 0.3, 0.28), 2.5, true)
			draw_line(Vector2(-8, 8), Vector2(8, -8), Color(0.85, 0.3, 0.28), 2.5, true)
		if text != "" and text != "!":
			var font := LootVisuals.text_font(800)
			var fs := 11
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_rect(Rect2(-w * 0.5 - 3.0, 12.0, w + 6.0, 13.0), Color(0.024, 0.027, 0.05, 0.85))
			draw_string(font, Vector2(-w * 0.5, 22.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lightened(0.2))


## Flèche de bord vers l'extraction la plus proche (pointe vers +X, tournée par `rotation`).
class EdgeArrow extends Node2D:
	func _draw() -> void:
		MiniMap.draw_aa_polygon(self, PackedVector2Array([Vector2(10, 0), Vector2(-7, -9), Vector2(-3, 0), Vector2(-7, 9)]), Color(0.02, 0.05, 0.04, 0.8))
		MiniMap.draw_aa_polygon(self, PackedVector2Array([Vector2(8, 0), Vector2(-6, -7), Vector2(-2, 0), Vector2(-6, 7)]), EXTRACT)


## Carte plein écran : voile, panneau bleu nuit, carte zoomable (carte entière à l'ouverture),
## légende. Jeu en pause ([minimap] full_map_time_scale = 0 → pause ; sinon ralenti).
## Gestes : pincer = zoom centré sur les doigts, glisser = déplacer (inertie légère), double-tap
## = recentrer sur le joueur ; boutons + / − / recentrer ; PC : molette (zoom sous le curseur)
## et clic-glisser (touchers émulés depuis la souris). Fermer : bouton ×, toucher hors du
## panneau, M ou Échap. Cadrage calculé par MapZoom (bornes, conversions écran ↔ carte).
class FullMapOverlay extends Control:
	signal closed

	var view: MapView = null
	var zoom: MapZoom = MapZoom.new()
	var zoom_in_button: Button = null
	var zoom_out_button: Button = null
	var recenter_button: Button = null
	var close_button: Button = null
	var _title: Label = null
	var _paused_by_me: bool = false
	var _saved_scale: float = 1.0
	var _panel: PanelContainer = null
	var _icon_scale: float = 1.25
	## Doigts posés sur la carte : index → position (px locaux de la vue).
	var _touches: Dictionary = {}
	var _press_pos: Vector2 = Vector2.ZERO
	var _drag_moved: bool = false
	var _last_drag_us: int = 0
	var _velocity: Vector2 = Vector2.ZERO
	var _pinch_d0: float = 1.0
	var _pinch_s0: float = 1.0
	var _pinch_anchor: Vector2 = Vector2.ZERO
	var _last_tap_us: int = -1000000000
	var _last_tap_pos: Vector2 = Vector2.ZERO
	## Toucher commencé sur le voile (hors panneau) : ferme au relâcher s'il y reste.
	var _dim_touch: int = -1

	func _ready() -> void:
		name = "FullMap"
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		visible = false
		var dim := ColorRect.new()
		dim.color = Color(0.02, 0.03, 0.07, 0.7)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		_panel = PanelContainer.new()
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_theme_stylebox_override("panel", InventoryStyle.panel(20, 14))
		add_child(_panel)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 8)
		_panel.add_child(v)
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_theme_constant_override("separation", 14)
		v.add_child(head)
		_title = InventoryStyle.title("Carte", 26)
		head.add_child(_title)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(sp)
		var legend := HBoxContainer.new()
		legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
		legend.add_theme_constant_override("separation", 6)
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(24, 24)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.draw.connect(func() -> void:
			ic.draw_circle(Vector2(12, 12), 10.0, Color(0.04, 0.12, 0.09, 0.95))
			ic.draw_arc(Vector2(12, 12), 10.0, 0.0, TAU, 28, EXTRACT, 2.5, true)
			ExtractionZone.draw_exit_glyph(ic, Vector2(12, 12), 6.0, EXTRACT.lightened(0.3)))
		legend.add_child(ic)
		var ll := InventoryStyle.label("Extraction", 16, EXTRACT.lightened(0.2), 800)
		ll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(ll)
		head.add_child(legend)
		var hint_text := "Pincez pour zoomer" if OS.has_feature("mobile") else "Molette pour zoomer"
		var hint := InventoryStyle.label(hint_text, 14, InventoryStyle.TEXT_SECONDARY, 700)
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(hint)
		close_button = _icon_button(&"close", "Fermer", 44.0)
		close_button.pressed.connect(close)
		head.add_child(close_button)
		view = MapView.new()
		view.vignette = Balance.get_float("minimap", "full_map_vignette_strength", 0.3)
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(view)
		# Boutons de zoom en bas à droite, au-dessus de la carte.
		var tools := VBoxContainer.new()
		tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tools.add_theme_constant_override("separation", 8)
		tools.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		tools.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		tools.grow_vertical = Control.GROW_DIRECTION_BEGIN
		tools.offset_right = -12.0
		tools.offset_bottom = -12.0
		view.add_child(tools)
		zoom_in_button = _icon_button(&"plus", "Zoomer", 52.0)
		zoom_in_button.pressed.connect(func() -> void: zoom_step(Balance.get_float("minimap", "full_map_zoom_step", 1.5)))
		tools.add_child(zoom_in_button)
		zoom_out_button = _icon_button(&"minus", "Dézoomer", 52.0)
		zoom_out_button.pressed.connect(func() -> void: zoom_step(1.0 / Balance.get_float("minimap", "full_map_zoom_step", 1.5)))
		tools.add_child(zoom_out_button)
		recenter_button = _icon_button(&"recenter", "Recentrer sur le joueur", 52.0)
		recenter_button.pressed.connect(recenter)
		tools.add_child(recenter_button)
		view.resized.connect(func() -> void:
			if visible:
				zoom.resize(view.size)
				_apply_zoom())

	## Petit bouton carré direction D (encre translucide, coins coupés), pictogramme dessiné.
	func _icon_button(kind: StringName, tip: String, px: float) -> Button:
		var b := MenuKit.button("", MenuKit.Style.GHOST, 18, Vector2(px, px))
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = tip
		b.draw.connect(func() -> void: _draw_icon(b, kind))
		return b

	static func _draw_icon(b: Button, kind: StringName) -> void:
		var c := b.size * 0.5
		var col := Color(1, 1, 1, 0.35 if b.disabled else 0.95)
		var r := minf(b.size.x, b.size.y) * 0.2
		match kind:
			&"plus":
				b.draw_line(c - Vector2(r, 0), c + Vector2(r, 0), col, 3.0, true)
				b.draw_line(c - Vector2(0, r), c + Vector2(0, r), col, 3.0, true)
			&"minus":
				b.draw_line(c - Vector2(r, 0), c + Vector2(r, 0), col, 3.0, true)
			&"close":
				b.draw_line(c - Vector2(r, r), c + Vector2(r, r), col, 2.5, true)
				b.draw_line(c + Vector2(-r, r), c + Vector2(r, -r), col, 2.5, true)
			&"recenter":
				var acc := Color(MenuKit.GOLD, col.a)
				b.draw_arc(c, r * 0.85, 0.0, TAU, 28, acc, 2.5, true)
				for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
					b.draw_line(c + d * r * 0.85, c + d * r * 1.35, acc, 2.5, true)
				b.draw_circle(c, 2.5, acc)

	func open_with(mm: MiniMap) -> void:
		var vp := get_viewport_rect().size
		var m := HudSafeArea.margins(self)
		var avail := vp - Vector2(m.x + m.z, m.y + m.w) - Vector2(40, 40)
		var world := Rect2(Vector2.ZERO, Vector2(mm.layout.size) * TS)
		var head_h := 46.0
		var k := minf(avail.x / world.size.x, (avail.y - head_h) / world.size.y)
		var map_size := (world.size * k).floor()
		map_size.x = maxf(map_size.x, 420.0)
		view.custom_minimum_size = map_size
		_panel.position = Vector2.ZERO
		_panel.reset_size()
		_title.text = String(mm.raid.call("get_banner_text")) if mm.raid.has_method("get_banner_text") else "Carte"
		visible = true
		await get_tree().process_frame
		_panel.reset_size()
		_panel.position = ((vp - _panel.size) * 0.5).floor()
		view.setup(mm.bg_texture, mm.bg_world_rect, mm._fog_tex, Vector2(mm.layout.size), mm._zone_centers, 1.0, mm.plan_geometry)
		view.set_zone_states(mm.zone_states())
		_reset_gestures()
		_icon_scale = Balance.get_float("minimap", "full_map_icon_scale", 1.25)
		zoom.setup(view.size, world, Balance.get_float("minimap", "full_map_zoom_max", 4.0))
		_apply_zoom()
		if is_instance_valid(mm.player):
			view.set_player(mm.player.global_position, mm._aim_angle())
		_apply_pause(true)

	func close() -> void:
		if not visible:
			return
		visible = false
		_reset_gestures()
		_apply_pause(false)
		closed.emit()

	func _apply_pause(on: bool) -> void:
		if not is_inside_tree():
			return
		var ts := Balance.get_float("minimap", "full_map_time_scale", 0.0)
		if on:
			if ts <= 0.0:
				_paused_by_me = not get_tree().paused
				get_tree().paused = true
			else:
				_saved_scale = Engine.time_scale
				Engine.time_scale = ts
		else:
			if _paused_by_me:
				get_tree().paused = false
				_paused_by_me = false
			elif ts > 0.0:
				Engine.time_scale = _saved_scale

	func _exit_tree() -> void:
		if visible:
			_apply_pause(false)

	## Les clics souris sur la carte passent par les touchers émulés (_input) : ici on les
	## consomme seulement pour qu'ils n'atteignent pas le jeu.
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			accept_event()

	# --- Zoom et déplacement ---------------------------------------------------------

	func _apply_zoom() -> void:
		view.apply_zoom(zoom, _icon_scale)
		if zoom_in_button != null:
			zoom_in_button.disabled = zoom.is_max_zoom()
			zoom_out_button.disabled = zoom.is_min_zoom()
			zoom_in_button.queue_redraw()
			zoom_out_button.queue_redraw()

	func _reset_gestures() -> void:
		_touches.clear()
		_velocity = Vector2.ZERO
		_drag_moved = false
		_dim_touch = -1
		_last_tap_us = -1000000000

	## Zoom par pas (boutons), centré sur le milieu de la vue.
	func zoom_step(factor: float) -> void:
		_velocity = Vector2.ZERO
		zoom.zoom_at(zoom.view_size * 0.5, factor)
		_apply_zoom()

	## Position monde du joueur sur la carte.
	func player_position() -> Vector2:
		return view.player_mark.position if view != null and view.player_mark != null else zoom.world.get_center()

	## Centre sur le joueur ; si la carte est entière, zoome d'abord ([minimap] full_map_recenter_zoom).
	func recenter() -> void:
		_velocity = Vector2.ZERO
		if zoom.is_min_zoom():
			zoom.set_scale_at(zoom.view_size * 0.5, zoom.min_scale() * Balance.get_float("minimap", "full_map_recenter_zoom", 2.5))
		zoom.center_on(player_position())
		_apply_zoom()

	## Inertie du glisser (temps réel : la carte met le jeu en pause ou le ralentit).
	func _process(delta: float) -> void:
		if not visible or _velocity == Vector2.ZERO or not _touches.is_empty():
			return
		var dt := delta / maxf(Engine.time_scale, 0.01)
		var want := _velocity * dt
		var got := zoom.pan(want)
		# Bord de la carte atteint : l'axe s'arrête.
		if absf(got.x) < absf(want.x) * 0.5:
			_velocity.x = 0.0
		if absf(got.y) < absf(want.y) * 0.5:
			_velocity.y = 0.0
		_velocity *= exp(-Balance.get_float("minimap", "full_map_inertia_damping", 6.0) * dt)
		if _velocity.length() < 10.0:
			_velocity = Vector2.ZERO
		_apply_zoom()

	func _to_view(global_pos: Vector2) -> Vector2:
		return global_pos - view.get_global_rect().position

	func _on_button(global_pos: Vector2) -> bool:
		for b: Button in [zoom_in_button, zoom_out_button, recenter_button, close_button]:
			if b != null and b.is_visible_in_tree() and b.get_global_rect().has_point(global_pos):
				return true
		return false

	func _start_pinch() -> void:
		var k: Array = _touches.keys()
		var a: Vector2 = _touches[k[0]]
		var b: Vector2 = _touches[k[1]]
		_pinch_d0 = maxf(a.distance_to(b), 1.0)
		_pinch_s0 = zoom.scale
		_pinch_anchor = zoom.screen_to_world((a + b) * 0.5)

	func _on_touch(t: InputEventScreenTouch) -> void:
		var gp := t.position
		if t.pressed:
			if _on_button(gp):
				return  # laissé au bouton (souris émulée)
			get_viewport().set_input_as_handled()
			if not _panel.get_global_rect().has_point(gp):
				_dim_touch = t.index
				return
			if not view.get_global_rect().has_point(gp):
				return
			var lp := _to_view(gp)
			_touches[t.index] = lp
			_velocity = Vector2.ZERO
			if _touches.size() == 1:
				_drag_moved = false
				_press_pos = lp
				_last_drag_us = Time.get_ticks_usec()
			else:
				_drag_moved = true  # plus de tap après un pincement
				_start_pinch()
			return
		if t.index == _dim_touch:
			_dim_touch = -1
			get_viewport().set_input_as_handled()
			if not t.canceled and not _panel.get_global_rect().has_point(gp):
				close()
			return
		if not _touches.has(t.index):
			return
		get_viewport().set_input_as_handled()
		var was_single := _touches.size() == 1
		_touches.erase(t.index)
		if was_single:
			if t.canceled:
				_velocity = Vector2.ZERO
			elif not _drag_moved:
				_on_tap(_to_view(gp))
			elif Time.get_ticks_usec() - _last_drag_us > 90000:
				_velocity = Vector2.ZERO  # doigt immobile avant de relâcher : pas d'inertie
		elif _touches.size() >= 2:
			_start_pinch()
		else:
			_velocity = Vector2.ZERO  # fin du pincement : le doigt restant glisse sans saut

	func _on_drag(d: InputEventScreenDrag) -> void:
		if not _touches.has(d.index):
			return
		get_viewport().set_input_as_handled()
		var lp := _to_view(d.position)
		var prev: Vector2 = _touches[d.index]
		_touches[d.index] = lp
		if _touches.size() >= 2:
			var k: Array = _touches.keys()
			var a: Vector2 = _touches[k[0]]
			var b: Vector2 = _touches[k[1]]
			zoom.pinch(_pinch_anchor, (a + b) * 0.5, _pinch_s0 * maxf(a.distance_to(b), 1.0) / _pinch_d0)
			_apply_zoom()
			return
		if not _drag_moved:
			if lp.distance_to(_press_pos) < Balance.get_float("minimap", "full_map_tap_slop", 14.0):
				return
			_drag_moved = true
		var delta := lp - prev
		zoom.pan(delta)
		var now := Time.get_ticks_usec()
		var dt := maxf(float(now - _last_drag_us) / 1000000.0, 0.001)
		_last_drag_us = now
		_velocity = _velocity.lerp(delta / dt, 0.4)
		_apply_zoom()

	## Toucher bref sur la carte : deux de suite, proches = double-tap → recentrer.
	func _on_tap(lp: Vector2) -> void:
		var now := Time.get_ticks_usec()
		var win := int(Balance.get_float("minimap", "full_map_double_tap_time", 0.32) * 1000000.0)
		var slop := Balance.get_float("minimap", "full_map_tap_slop", 14.0) * 3.0
		if now - _last_tap_us <= win and lp.distance_to(_last_tap_pos) <= slop:
			_last_tap_us = -1000000000
			recenter()
		else:
			_last_tap_us = now
			_last_tap_pos = lp

	func _input(event: InputEvent) -> void:
		if not visible:
			return
		if event is InputEventScreenTouch:
			_on_touch(event as InputEventScreenTouch)
		elif event is InputEventScreenDrag:
			_on_drag(event as InputEventScreenDrag)
		elif event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if not mb.pressed or mb.device == InputEvent.DEVICE_ID_EMULATION \
					or not view.get_global_rect().has_point(mb.position):
				return
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				get_viewport().set_input_as_handled()
				var step := Balance.get_float("minimap", "full_map_wheel_step", 1.15)
				var f := pow(step, mb.factor if mb.factor > 0.0 else 1.0)
				_velocity = Vector2.ZERO
				zoom.zoom_at(_to_view(mb.position), f if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / f)
				_apply_zoom()
		elif event is InputEventMagnifyGesture:
			var mg := event as InputEventMagnifyGesture
			if view.get_global_rect().has_point(mg.position):
				get_viewport().set_input_as_handled()
				zoom.zoom_at(_to_view(mg.position), mg.factor)
				_apply_zoom()
		elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
			var k := (event as InputEventKey).physical_keycode
			if k == KEY_M or k == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				close()
