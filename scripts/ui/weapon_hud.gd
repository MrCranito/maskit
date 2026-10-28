class_name WeaponHud
extends Control
## HUD des armes tenues (paysage 1280×720) :
##   - 3 emplacements en bas au centre, entre les deux sticks : icône de l'arme, liseré de
##     rareté, touche (1, 2, 3) ; l'emplacement courant est plus grand, cerclé d'or, avec
##     les munitions « 7 / 10 » et un anneau de rechargement ;
##   - bouton tactile « changer d'arme » à gauche du stick de visée (sous le bouton action,
##     loin du sac) ;
##   - toucher un emplacement = player.switch_to(i).
## Mise à jour sur signaux du joueur (weapons_changed, ammo_changed, fired). Rien n'est
## redessiné à chaque frame : seul un emplacement en cours de rechargement l'est, le temps
## du rechargement. API joueur interrogée via has_method/has_signal (contrat Exfil Rush).

const SLOT_COUNT := 3
const CURRENT_SIZE := Vector2(176, 88)
const OTHER_SIZE := Vector2(118, 66)
const GAP := 10.0
const BOTTOM_MARGIN := 14.0
const SWITCH_RADIUS := 40.0

var player: Node2D = null
var slots: Array[WeaponSlotView] = []
var switch_button: WeaponSwitchButton = null
var _row: HBoxContainer = null
var _weapons: Array[WeaponData] = []
var _current: int = 0
var _ammo: int = -1
var _magazine: int = 0
var _reload_poll: Timer = null


func _ready() -> void:
	name = "WeaponHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	_build()
	EventBus.player_spawned.connect(bind_player)
	if is_instance_valid(GameState.player):
		bind_player(GameState.player)
	get_viewport().size_changed.connect(_place)
	_place()


func _build() -> void:
	_row = HBoxContainer.new()
	_row.name = "WeaponSlots"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", int(GAP))
	add_child(_row)
	for i in SLOT_COUNT:
		var s := WeaponSlotView.new()
		s.index = i
		s.size_flags_vertical = Control.SIZE_SHRINK_END
		s.tapped.connect(_on_slot_tapped)
		_row.add_child(s)
		slots.append(s)
	switch_button = WeaponSwitchButton.new()
	switch_button.radius = SWITCH_RADIUS
	switch_button.tapped.connect(_on_switch_pressed)
	add_child(switch_button)
	# Filet de sécurité : détecte un rechargement lancé sans signal (touche R, chargeur vide).
	_reload_poll = Timer.new()
	_reload_poll.wait_time = 0.15
	_reload_poll.timeout.connect(_poll_reload)
	add_child(_reload_poll)


## Bas centre pour les emplacements ; bouton de changement à gauche du stick droit.
func _place() -> void:
	var vp := get_viewport_rect().size
	var total_w := CURRENT_SIZE.x + OTHER_SIZE.x * (SLOT_COUNT - 1) + GAP * (SLOT_COUNT - 1)
	_row.size = Vector2(total_w, CURRENT_SIZE.y)
	_row.position = Vector2((vp.x - total_w) * 0.5, vp.y - BOTTOM_MARGIN - CURRENT_SIZE.y)
	var rest := Vector2(vp.x * Balance.get_float("joystick", "right_rest_x", 0.87),
		vp.y * Balance.get_float("joystick", "rest_y", 0.77))
	var stick_r := Balance.get_float("joystick", "radius", 90.0)
	var c := rest + Vector2(-stick_r - SWITCH_RADIUS - 34.0, -stick_r * 0.55)
	switch_button.position = c - switch_button.size * 0.5


# --- Joueur ----------------------------------------------------------------------

func bind_player(p: Node2D) -> void:
	if p == player or not is_instance_valid(p):
		return
	player = p
	if p.has_signal(&"weapons_changed"):
		p.connect(&"weapons_changed", refresh)
	if p.has_signal(&"ammo_changed"):
		p.connect(&"ammo_changed", _on_ammo_changed)
	if p.has_signal(&"fired"):
		p.connect(&"fired", _on_fired)
	_reload_poll.start()
	refresh()


## Relit les armes tenues, l'emplacement courant et les munitions (sur signal).
func refresh() -> void:
	_weapons = read_weapons(player)
	_current = 0
	if is_instance_valid(player) and player.get("current_slot") is int:
		_current = clampi(int(player.get("current_slot")), 0, SLOT_COUNT - 1)
	_read_ammo()
	for i in slots.size():
		var w: WeaponData = _weapons[i] if i < _weapons.size() else null
		slots[i].set_state(w, i == _current, _ammo if i == _current else -1, _magazine if i == _current else 0)
	switch_button.set_enabled(_count_weapons() > 1)
	_update_reload()


## Armes tenues du joueur (API get_weapons, repli : player.weapon seule).
static func read_weapons(p: Node) -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	if p == null or not is_instance_valid(p):
		return out
	if p.has_method(&"get_weapons"):
		var list: Variant = p.call(&"get_weapons")
		if list is Array:
			for w: Variant in list:
				out.append(w as WeaponData)
			return out
	var single: Variant = p.get("weapon")
	if single is WeaponData:
		out.append(single)
	return out


func _count_weapons() -> int:
	var n := 0
	for w: WeaponData in _weapons:
		if w != null:
			n += 1
	return n


func _read_ammo() -> void:
	var w: WeaponData = _weapons[_current] if _current < _weapons.size() else null
	_magazine = w.magazine_size if w != null else 0
	_ammo = int(player.call(&"get_ammo")) if is_instance_valid(player) and player.has_method(&"get_ammo") else _magazine


func _on_ammo_changed(ammo: int, magazine: int) -> void:
	_ammo = ammo
	_magazine = magazine
	if _current < slots.size():
		slots[_current].set_ammo(ammo, magazine)
	_update_reload()


func _on_fired(_dir: Vector2 = Vector2.ZERO) -> void:
	if not (is_instance_valid(player) and player.has_signal(&"ammo_changed")):
		_read_ammo()
		if _current < slots.size():
			slots[_current].set_ammo(_ammo, _magazine)


func _poll_reload() -> void:
	if not is_instance_valid(player):
		_reload_poll.stop()
		return
	var reloading := _is_reloading()
	if reloading != is_processing():
		_update_reload()


func _is_reloading() -> bool:
	return is_instance_valid(player) and player.has_method(&"is_reloading") and bool(player.call(&"is_reloading"))


## Anneau de rechargement : _process actif seulement pendant le rechargement.
func _update_reload() -> void:
	var reloading := _is_reloading()
	set_process(reloading)
	if _current < slots.size():
		slots[_current].set_reload(_reload_progress() if reloading else -1.0)


func _reload_progress() -> float:
	if is_instance_valid(player) and player.has_method(&"get_reload_progress"):
		return clampf(float(player.call(&"get_reload_progress")), 0.0, 1.0)
	return 0.0


func _process(_delta: float) -> void:
	if not _is_reloading():
		set_process(false)
		_read_ammo()
		if _current < slots.size():
			slots[_current].set_ammo(_ammo, _magazine)
			slots[_current].set_reload(-1.0)
		return
	if _current < slots.size():
		slots[_current].set_reload(_reload_progress())


# --- Entrées ---------------------------------------------------------------------

func _on_slot_tapped(i: int) -> void:
	if not is_instance_valid(player) or i == _current:
		return
	if i >= _weapons.size() or _weapons[i] == null:
		return
	if player.has_method(&"switch_to"):
		player.call(&"switch_to", i)
		_play(&"click_soft")
		if not player.has_signal(&"weapons_changed"):
			refresh()


func _on_switch_pressed() -> void:
	if not is_instance_valid(player):
		return
	if player.has_method(&"next_weapon"):
		player.call(&"next_weapon")
		_play(&"click_soft")
		if not player.has_signal(&"weapons_changed"):
			refresh()


func _play(sfx: StringName) -> void:
	var am := get_tree().root.get_node_or_null(^"AudioManager") if is_inside_tree() else null
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", sfx)


# =====================================================================================

## Emplacement d'arme : dessin statique, redessiné quand son contenu change.
class WeaponSlotView extends Control:
	signal tapped(index: int)

	var index: int = 0
	var weapon: WeaponData = null
	var current: bool = false
	var ammo: int = -1
	var magazine: int = 0
	var reload: float = -1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = OTHER_SIZE

	func set_state(w: WeaponData, is_current: bool, p_ammo: int, p_mag: int) -> void:
		weapon = w
		current = is_current
		ammo = p_ammo
		magazine = p_mag
		custom_minimum_size = CURRENT_SIZE if current else OTHER_SIZE
		queue_redraw()

	func set_ammo(p_ammo: int, p_mag: int) -> void:
		if p_ammo == ammo and p_mag == magazine:
			return
		ammo = p_ammo
		magazine = p_mag
		queue_redraw()

	func set_reload(progress: float) -> void:
		if is_equal_approx(progress, reload):
			return
		reload = progress
		queue_redraw()

	func _input(event: InputEvent) -> void:
		if not is_visible_in_tree() or not (event is InputEventScreenTouch):
			return
		var t := event as InputEventScreenTouch
		if t.pressed and get_global_rect().grow(4.0).has_point(t.position):
			get_viewport().set_input_as_handled()
			tapped.emit(index)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				accept_event()
				tapped.emit(index)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var font := LootVisuals.text_font(800)
		var rc: Color = weapon.get_rarity_color() if weapon != null else Color(InventoryStyle.BORDER_LIGHT, 0.3)
		# Lueur Épique / Légendaire.
		if weapon != null and weapon.rarity >= WeaponData.Rarity.EPIQUE:
			for k in 2:
				var g := StyleBoxFlat.new()
				g.bg_color = Color(rc, 0.12 + 0.06 * k)
				g.set_corner_radius_all(16 + (2 - k) * 2)
				g.anti_aliasing = true
				draw_style_box(g, r.grow(float(2 - k) * 2.5))
		var bg := StyleBoxFlat.new()
		bg.bg_color = InventoryStyle.NIGHT_BLUE.lerp(rc, 0.14) if weapon != null else Color(InventoryStyle.NIGHT_BLUE, 0.55)
		bg.border_color = InventoryStyle.GOLD if current else Color(rc, 0.9 if weapon != null else 0.4)
		bg.set_border_width_all(3 if current else 2)
		bg.set_corner_radius_all(14)
		bg.anti_aliasing = true
		bg.shadow_color = Color(0, 0, 0, 0.35)
		bg.shadow_size = 5 if current else 3
		draw_style_box(bg, r)
		# Touche / numéro d'emplacement.
		var num := str(index + 1)
		draw_string_outline(font, Vector2(9, 19), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, InventoryStyle.NIGHT_BLUE_DEEP)
		draw_string(font, Vector2(9, 19), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, InventoryStyle.GOLD if current else InventoryStyle.TEXT_SECONDARY)
		if weapon == null:
			var t := "vide"
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(font, Vector2((size.x - tw) * 0.5, size.y * 0.5 + 5.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(InventoryStyle.TEXT_SECONDARY, 0.55))
			return
		# Liseré de rareté en bas.
		var strip := StyleBoxFlat.new()
		strip.bg_color = Color(rc, 0.9)
		strip.corner_radius_bottom_left = 11
		strip.corner_radius_bottom_right = 11
		draw_style_box(strip, Rect2(Vector2(3, size.y - 7), Vector2(size.x - 6, 4)))
		if current:
			LootVisuals.draw_weapon(self, Rect2(Vector2(14, 8), Vector2(size.x * 0.58, size.y - 34)), weapon)
			_draw_ammo(font)
			var name_fs := 13
			draw_string_outline(font, Vector2(10, size.y - 13), weapon.display_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, name_fs, 4, InventoryStyle.NIGHT_BLUE_DEEP)
			draw_string(font, Vector2(10, size.y - 13), weapon.display_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, name_fs, rc.lightened(0.3))
		else:
			LootVisuals.draw_weapon(self, Rect2(Vector2(14, 10), Vector2(size.x - 24, size.y - 22)), weapon, Color(1, 1, 1, 0.85))

	func _draw_ammo(font: Font) -> void:
		var right := size.x - 10.0
		var center_y := 30.0
		if reload >= 0.0:
			# Anneau de rechargement.
			var c := Vector2(right - 22.0, center_y)
			draw_arc(c, 18.0, 0.0, TAU, 40, Color(InventoryStyle.NIGHT_BLUE_DEEP, 0.9), 6.0, true)
			draw_arc(c, 18.0, -PI * 0.5, -PI * 0.5 + TAU * reload, 40, InventoryStyle.GOLD, 6.0, true)
			var rt := "R"
			var rw := font.get_string_size(rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(font, c + Vector2(-rw * 0.5, 6.0), rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, InventoryStyle.GOLD)
			return
		if magazine <= 0:
			var inf := "∞"
			var iw := font.get_string_size(inf, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			draw_string(font, Vector2(right - iw, center_y + 9.0), inf, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, InventoryStyle.TEXT)
			return
		var a := str(maxi(ammo, 0))
		var m := "/ %d" % magazine
		var low := ammo <= maxi(1, int(magazine * 0.25))
		var big := 26
		var small := 14
		var mw := font.get_string_size(m, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		var aw := font.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
		var col := InventoryStyle.DANGER.lightened(0.2) if low else Color.WHITE
		var ax := right - aw
		draw_string_outline(font, Vector2(ax, center_y + 4.0), a, HORIZONTAL_ALIGNMENT_LEFT, -1, big, 5, InventoryStyle.NIGHT_BLUE_DEEP)
		draw_string(font, Vector2(ax, center_y + 4.0), a, HORIZONTAL_ALIGNMENT_LEFT, -1, big, col)
		draw_string(font, Vector2(right - mw, center_y + 22.0), m, HORIZONTAL_ALIGNMENT_LEFT, -1, small, InventoryStyle.TEXT_SECONDARY)


## Bouton rond « changer d'arme » (deux flèches en cycle).
class WeaponSwitchButton extends Control:
	signal tapped

	var radius: float = 40.0
	var enabled: bool = true
	var _down: bool = false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(radius * 2.0 + 6.0, radius * 2.0 + 6.0)
		size = custom_minimum_size

	func set_enabled(on: bool) -> void:
		if on == enabled:
			return
		enabled = on
		queue_redraw()

	func _hit(p: Vector2) -> bool:
		return get_global_rect().get_center().distance_to(p) <= radius + 8.0

	func _input(event: InputEvent) -> void:
		if not is_visible_in_tree() or not (event is InputEventScreenTouch):
			return
		var t := event as InputEventScreenTouch
		if t.pressed and _hit(t.position):
			get_viewport().set_input_as_handled()
			_fire()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _hit(mb.global_position):
				accept_event()
				_fire()

	func _fire() -> void:
		if not enabled:
			return
		_down = true
		queue_redraw()
		tapped.emit()
		get_tree().create_timer(0.1, true, false, true).timeout.connect(func() -> void:
			_down = false
			queue_redraw())

	func _draw() -> void:
		var c := size * 0.5
		var r := radius * (0.93 if _down else 1.0)
		var a := 1.0 if enabled else 0.45
		draw_circle(c + Vector2(0, 3), r + 2.0, Color(0.02, 0.03, 0.07, 0.4 * a))
		draw_circle(c, r, Color(InventoryStyle.NIGHT_BLUE_LIGHT if _down else InventoryStyle.NIGHT_BLUE, 0.94 * a))
		draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(InventoryStyle.BORDER_LIGHT, 0.85 * a), 1.5, true)
		draw_arc(c, r - 5.0, 0.0, TAU, 48, Color(InventoryStyle.GOLD, 0.5 * a), 2.0, true)
		# Deux flèches courbes (cycle).
		var col := Color(InventoryStyle.GOLD.lightened(0.15), a)
		var ar := r * 0.42
		for k in 2:
			var start := -PI * 0.15 + PI * k
			var end := start + PI * 0.75
			draw_arc(c, ar, start, end, 18, col, 4.0, true)
			var tip := c + Vector2.from_angle(end) * ar
			var tangent := Vector2.from_angle(end + PI * 0.5)
			var normal := Vector2.from_angle(end)
			draw_colored_polygon(PackedVector2Array([
				tip + tangent * 8.0, tip - normal * 6.5, tip + normal * 6.5]), col)
		var font := LootVisuals.text_font(800)
		var t := "Arme"
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string_outline(font, Vector2(c.x - tw * 0.5, size.y + 12.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, InventoryStyle.NIGHT_BLUE_DEEP)
		draw_string(font, Vector2(c.x - tw * 0.5, size.y + 12.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(Color.WHITE, a))
