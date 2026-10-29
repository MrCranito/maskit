class_name MiniMap
extends Control
## Mini-carte (haut droite, sous le sac/pause, dans la zone sûre) :
##   - carte autour du joueur : version réduite de l'image du paquet pré-rendu
##     (assets/prerender/<biome>/<seed>/minimap.webp, sinon rendu simplifié des cases) ;
##   - seules les cases explorées sont visibles (masque issu de FogOfWar.is_cell_explored),
##     le reste sous une brume bleu nuit aux bords doux ;
##   - position et orientation (visée) du joueur, au centre ;
##   - zones d'extraction toujours affichées (icône verte) ; si la plus proche sort du cadre,
##     flèche au bord vers elle avec sa distance ;
##   - toucher / clic (ou touche M) = carte plein écran (jeu en pause), re-toucher pour fermer.
## Performance : rafraîchie par un Timer ([minimap] refresh_interval ≈ 0,1 s), sans allocation :
## on déplace un nœud (transformations), on ne redessine pas ; le masque d'exploration n'est
## relu qu'autour du joueur et la texture n'est mise à jour que si une case change.

signal full_map_toggled(open: bool)

const NIGHT := Color(0.071, 0.102, 0.18)
const BORDER := Color(0.85, 0.88, 0.95, 0.85)
const EXTRACT := Color(0.3, 1.0, 0.62)
const TS := float(FloorLayout.TILE_SIZE)
const FOG_SHADER_CODE := """
shader_type canvas_item;
uniform vec4 fog_color : source_color = vec4(0.05, 0.07, 0.13, 0.97);
void fragment() {
	float e = texture(TEXTURE, UV).r;
	e = smoothstep(0.15, 0.85, e);
	COLOR = vec4(fog_color.rgb, fog_color.a * (1.0 - e));
}
"""

static var _fog_shader: Shader = null

var raid: Node = null
var layout: FloorLayout = null
var fog: Node = null
var player: Node2D = null
## Rectangle monde couvert par l'image de fond.
var bg_world_rect: Rect2 = Rect2()
var bg_texture: Texture2D = null
var view: MapView = null
var full_map: FullMapOverlay = null

var _fog_img: Image = null
var _fog_tex: ImageTexture = null
var _zone_centers: PackedVector2Array = PackedVector2Array()
var _timer: Timer = null
var _arrow: EdgeArrow = null
var _arrow_label: Label = null
var _last_dist: int = -1
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
	var zones: Variant = raid.get("extraction_zones")
	if zones is Array:
		for z: Variant in zones:
			if z is Node2D and is_instance_valid(z):
				_zone_centers.append((z as Node2D).global_position)
	if _zone_centers.is_empty():
		for c: Vector2i in layout.extraction_cells:
			_zone_centers.append(FloorLayout.cell_to_world(c))
	var fv: Variant = fog.get("view_radius") if fog != null else null
	_scan_radius = (int(fv) if fv != null else 10) + 2
	var view_cells := Balance.get_float("minimap", "view_cells", 24.0)
	view.setup(bg_texture, bg_world_rect, _fog_tex, Vector2(layout.size), _zone_centers, TS * view_cells / _box)
	if full_map != null and is_instance_valid(full_map):
		full_map.close()
	_tick()
	_timer.start()


## Fond : image réduite du paquet pré-rendu (étage 0 Far West) ou cases simplifiées.
func _build_background() -> void:
	bg_texture = null
	var pr: Variant = raid.get("prerender")
	if pr is PrerenderBackdrop and is_instance_valid(pr):
		var b := pr as PrerenderBackdrop
		var path := b.pack_dir + "minimap.webp"
		if ResourceLoader.exists(path):
			bg_texture = load(path) as Texture2D
			var ip: Array = b.meta.get("image_px", [0, 0])
			bg_world_rect = Rect2(b.origin, Vector2(float(ip[0]), float(ip[1])) * b.px_scale)
	if bg_texture == null:
		bg_texture = tile_texture(layout)
		bg_world_rect = Rect2(Vector2.ZERO, Vector2(layout.size) * TS)


## Rendu simplifié des cases (4 px par case), pour les biomes sans paquet pré-rendu.
static func tile_texture(l: FloorLayout, cpx: int = 4) -> ImageTexture:
	var img := Image.create(l.size.x * cpx, l.size.y * cpx, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.08, 0.1, 0.14, 1.0))
	for y in l.size.y:
		for x in l.size.x:
			var c := tile_color(l.get_tile(Vector2i(x, y)))
			if c.a > 0.0:
				img.fill_rect(Rect2i(x * cpx, y * cpx, cpx, cpx), c)
	return ImageTexture.create_from_image(img)


static func tile_color(t: int) -> Color:
	match t:
		FloorLayout.Tile.STREET:
			return Color(0.74, 0.6, 0.42)
		FloorLayout.Tile.FLOOR:
			return Color(0.52, 0.38, 0.27)
		FloorLayout.Tile.WALL:
			return Color(0.22, 0.18, 0.16)
		FloorLayout.Tile.DOOR:
			return Color(0.85, 0.65, 0.32)
		FloorLayout.Tile.STAIRS_UP, FloorLayout.Tile.STAIRS_DOWN:
			return Color(0.55, 0.8, 1.0)
	return Color(0, 0, 0, 0)


## Masque d'exploration (1 px par case, L8), relu en entier une seule fois par étage.
func _build_fog_mask() -> void:
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


static func fog_shader() -> Shader:
	if _fog_shader == null:
		_fog_shader = Shader.new()
		_fog_shader.code = FOG_SHADER_CODE
	return _fog_shader


# --- Mise à jour espacée ---------------------------------------------------------------

func _tick() -> void:
	if not is_instance_valid(player):
		player = raid.get("player") as Node2D if raid != null and is_instance_valid(raid) else null
		if player == null:
			return
	var pos := player.global_position
	_update_fog(pos)
	view.follow(pos, _aim_angle())
	_update_arrow(pos)
	if full_map != null and is_instance_valid(full_map) and full_map.visible:
		full_map.view.set_player(pos, _aim_angle())


func _aim_angle() -> float:
	var d: Variant = player.get("aim_direction")
	return (d as Vector2).angle() if d is Vector2 and (d as Vector2) != Vector2.ZERO else 0.0


## Relit les cases autour du joueur ; met à jour la texture seulement si une case change.
func _update_fog(pos: Vector2) -> void:
	if fog == null or not is_instance_valid(fog) or _fog_img == null:
		return
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
	if changed:
		_fog_tex.update(_fog_img)


## Flèche au bord vers l'extraction la plus proche quand elle sort du cadre.
func _update_arrow(pos: Vector2) -> void:
	var best := -1
	var best_d := INF
	for i in _zone_centers.size():
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
	if meters != _last_dist:
		_last_dist = meters
		_arrow_label.text = "%d m" % meters
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
		return 0
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
## arrondi. Le contenu est en coordonnées monde dans `content` (échelle = px / px monde).
class MapView extends Control:
	var mask: Panel = null
	var content: Node2D = null
	var frame: Panel = null
	var player_mark: PlayerMark = null
	var px_per_world: float = 0.1
	var _icons: Array[Node2D] = []
	var _fit_rect: Rect2 = Rect2()

	func _ready() -> void:
		mask = Panel.new()
		mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mask.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.05, 0.07, 0.13, 0.96)
		st.set_corner_radius_all(18)
		st.anti_aliasing = true
		mask.add_theme_stylebox_override("panel", st)
		add_child(mask)
		content = Node2D.new()
		mask.add_child(content)
		frame = Panel.new()
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fs := StyleBoxFlat.new()
		fs.draw_center = false
		fs.border_color = BORDER
		fs.set_border_width_all(2)
		fs.set_corner_radius_all(18)
		fs.shadow_color = Color(0, 0, 0, 0.35)
		fs.shadow_size = 6
		fs.anti_aliasing = true
		frame.add_theme_stylebox_override("panel", fs)
		add_child(frame)
		resized.connect(func() -> void:
			if _fit_rect.has_area():
				fit(_fit_rect))

	## (Re)construit le contenu. world_per_px = px monde par px écran.
	func setup(bg: Texture2D, bg_rect: Rect2, fog_tex: Texture2D, grid: Vector2, zones: PackedVector2Array, world_per_px: float) -> void:
		for c: Node in content.get_children():
			content.remove_child(c)
			c.queue_free()
		_icons.clear()
		px_per_world = 1.0 / maxf(world_per_px, 0.001)
		content.scale = Vector2(px_per_world, px_per_world)
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
			var f := Sprite2D.new()
			f.texture = fog_tex
			f.centered = false
			f.scale = Vector2(TS, TS) * grid / fog_tex.get_size()
			f.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			var mat := ShaderMaterial.new()
			mat.shader = MiniMap.fog_shader()
			f.material = mat
			# La brume déborde d'une case au-delà de la grille.
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

	func set_player(pos: Vector2, angle: float) -> void:
		if player_mark != null:
			player_mark.position = pos
			player_mark.rotation = angle

	func world_to_local(p: Vector2) -> Vector2:
		return content.position + p * px_per_world


## Joueur : flèche blanche cerclée (pointe vers la visée).
class PlayerMark extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 9.0, Color(0.05, 0.07, 0.13, 0.85))
		draw_colored_polygon(PackedVector2Array([Vector2(10, 0), Vector2(-6, -7), Vector2(-2, 0), Vector2(-6, 7)]), Color(1, 0.95, 0.85))
		draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 24, Color(1.0, 0.8, 0.4), 1.5, true)


## Icône d'extraction (pastille verte + pictogramme de sortie).
class ExtractIcon extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2(0, 1.5), 11.0, Color(0, 0, 0, 0.4))
		draw_circle(Vector2.ZERO, 10.0, Color(0.04, 0.12, 0.09, 0.95))
		draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 28, EXTRACT, 2.5, true)
		ExtractionZone.draw_exit_glyph(self, Vector2.ZERO, 6.0, EXTRACT.lightened(0.3))


## Flèche de bord vers l'extraction la plus proche (pointe vers +X, tournée par `rotation`).
class EdgeArrow extends Node2D:
	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(10, 0), Vector2(-7, -9), Vector2(-3, 0), Vector2(-7, 9)]), Color(0.02, 0.05, 0.04, 0.8))
		draw_colored_polygon(PackedVector2Array([Vector2(8, 0), Vector2(-6, -7), Vector2(-2, 0), Vector2(-6, 7)]), EXTRACT)


## Carte plein écran : voile, panneau bleu nuit, carte entière ajustée, légende. Jeu en
## pause ([minimap] full_map_time_scale = 0 → pause ; sinon ralenti). Toucher = fermer.
class FullMapOverlay extends Control:
	signal closed

	var view: MapView = null
	var _title: Label = null
	var _paused_by_me: bool = false
	var _saved_scale: float = 1.0
	var _panel: PanelContainer = null

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
		var hint := InventoryStyle.label("Touchez pour fermer", 14, InventoryStyle.TEXT_SECONDARY, 700)
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(hint)
		view = MapView.new()
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(view)

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
		view.setup(mm.bg_texture, mm.bg_world_rect, mm._fog_tex, Vector2(mm.layout.size), mm._zone_centers, 1.0)
		view.fit(world)
		if is_instance_valid(mm.player):
			view.set_player(mm.player.global_position, mm._aim_angle())
		_apply_pause(true)

	func close() -> void:
		if not visible:
			return
		visible = false
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

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			accept_event()
			close()

	func _input(event: InputEvent) -> void:
		if not visible:
			return
		if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			get_viewport().set_input_as_handled()
			close()
		elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
			var k := (event as InputEventKey).physical_keycode
			if k == KEY_M or k == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				close()
