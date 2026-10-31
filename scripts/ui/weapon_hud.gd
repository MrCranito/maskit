class_name WeaponHud
extends Control
## HUD de combat compact (direction D), regroupé autour des sticks pour dégager la vue :
##   - autour du stick de visée (bas droite) :
##       · pastille de l'arme tenue (icône, munitions « 4 / 10 », nom, barre de rechargement) ;
##         toucher = arme suivante ;
##       · petits ronds en arc pour les autres armes tenues (toucher = prendre cette arme) et
##         l'équipement (grenade, mine, C4, drone : toucher = lancer vers la visée, charges « ×3 ») ;
##       · bouton Recharger (au-dessus à droite du stick), qui s'allume quand le chargeur est bas ;
##   - au-dessus du stick de déplacement (bas gauche) : emplacements rapides du sac (soins,
##     équipements glissés depuis l'inventaire ; toucher = utiliser ; vide = ouvre le sac) :
##     cases biseautées (QuickSlot) au liseré de rareté, quantité en badge, grisées quand
##     l'objet ne sert à rien (PV pleins), flash et rebond du chiffre à l'utilisation.
## Positions relatives aux positions de repos des sticks ([hud] cluster_*, quick_* de
## balance.cfg), recalées dans la zone sûre (HudSafeArea). Mise à jour sur signaux du joueur
## (weapons_changed, ammo_changed, gadget_changed, quick_used) et Inventory.changed ; seul le
## rechargement redessine à chaque image, le temps qu'il dure.
## Actions équivalentes à l'InputMap (reload, weapon_next, weapon_1..3, gadget, quick_1..n),
## donc reprises telles quelles par le clavier et, plus tard, la manette.

const SLOT_COUNT := 3
const PILL_SIZE := Vector2(156, 58)
const ROUND_R := 27.0
const RELOAD_R := 31.0

var player: Node2D = null
var pill: ActivePill = null
## Ronds des autres armes (dans l'ordre des emplacements, l'arme tenue exclue).
var other_rounds: Array[HudRound] = []
var gadget_round: HudRound = null
var reload_button: HudRound = null
## Emplacements rapides (nom historique : c'étaient des ronds).
var quick_rounds: Array[QuickSlot] = []
var _hint: Label = null
var _hint_tween: Tween = null
var _inv: Inventory = null
var _gadget: WeaponData = null
var _gadget_charges: int = 0
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
	_bind_inventory()
	EventBus.player_damaged.connect(func(_a: float, _hp: float, _max: float) -> void: _refresh_quick_usable())
	get_viewport().size_changed.connect(_place)
	_place()


func _build() -> void:
	pill = ActivePill.new()
	pill.tapped.connect(func(_i: int) -> void: _on_switch_pressed())
	add_child(pill)
	for i in SLOT_COUNT - 1:
		var r := HudRound.new()
		r.name = "OtherWeapon%d" % i
		r.kind = HudRound.KIND_WEAPON
		r.radius = ROUND_R
		r.tapped.connect(_on_round_tapped)
		add_child(r)
		other_rounds.append(r)
	gadget_round = HudRound.new()
	gadget_round.name = "GadgetRound"
	gadget_round.kind = HudRound.KIND_GADGET
	gadget_round.radius = ROUND_R
	gadget_round.tapped.connect(func(_i: int) -> void: _on_gadget_pressed())
	add_child(gadget_round)
	reload_button = HudRound.new()
	reload_button.name = "ReloadButton"
	reload_button.kind = HudRound.KIND_RELOAD
	reload_button.radius = RELOAD_R
	reload_button.key_hint = "R"
	reload_button.tapped.connect(func(_i: int) -> void: _on_reload_pressed())
	add_child(reload_button)
	_hint = InventoryStyle.label("", 15, Color.WHITE, 700, 5)
	_hint.name = "QuickHint"
	_hint.modulate.a = 0.0
	add_child(_hint)
	_rebuild_quick(2)
	# Filet de sécurité : rechargement lancé sans signal, sac remplacé (nouveau raid).
	_reload_poll = Timer.new()
	_reload_poll.wait_time = 0.15
	_reload_poll.timeout.connect(_poll)
	add_child(_reload_poll)
	_reload_poll.start()


func _rebuild_quick(n: int) -> void:
	if quick_rounds.size() == n:
		return
	for r: QuickSlot in quick_rounds:
		r.queue_free()
	quick_rounds.clear()
	for i in n:
		var r := QuickSlot.new()
		r.name = "Quick%d" % i
		r.index = i
		r.key_hint = str(4 + i)
		r.tapped.connect(_on_quick_tapped)
		add_child(r)
		quick_rounds.append(r)
	if is_inside_tree():
		_place()


# --- Placement -----------------------------------------------------------------------

## Rectangles écran de chaque élément pour un viewport `vp` et des marges sûres `safe`
## (gauche, haut, droite, bas). Logique pure (tests : tout tient à l'écran, rien ne se chevauche).
static func compute_layout(vp: Vector2, safe: Vector4, n_quick: int = 2) -> Dictionary:
	var stick_y := vp.y * Balance.get_float("joystick", "rest_y", 0.77)
	var right_c := Vector2(vp.x * Balance.get_float("joystick", "right_rest_x", 0.87), stick_y)
	var left_c := Vector2(vp.x * Balance.get_float("joystick", "left_rest_x", 0.13), stick_y)
	var area := Rect2(Vector2(safe.x, safe.y), vp - Vector2(safe.x + safe.z, safe.y + safe.w))
	var out := {}
	var pill_c := right_c + _vec("cluster_pill", Vector2(-205, 10))
	out["pill"] = _fit(Rect2(pill_c - PILL_SIZE * 0.5, PILL_SIZE), area)
	var offs: Array[Vector2] = [_vec("cluster_other_1", Vector2(-132, 82)), _vec("cluster_other_2", Vector2(-62, 122))]
	for i in SLOT_COUNT - 1:
		out["other%d" % i] = _fit(_circle(right_c + offs[i], ROUND_R), area)
	out["gadget"] = _fit(_circle(right_c + _vec("cluster_gadget", Vector2(-150, -66)), ROUND_R), area)
	out["reload"] = _fit(_circle(right_c + _vec("cluster_reload", Vector2(100, -118)), RELOAD_R), area)
	var q0 := _vec("quick_first", Vector2(-20, -150))
	var step := _vec("quick_step", Vector2(78, 14))
	var qs := quick_size()
	for i in n_quick:
		var qc := left_c + q0 + step * float(i)
		out["quick%d" % i] = _fit(Rect2(qc - Vector2(qs, qs) * 0.5, Vector2(qs, qs)), area)
	return out


## Côté d'un emplacement rapide (px viewport, [hud] quick_size).
static func quick_size() -> float:
	return Balance.get_float("hud", "quick_size", 66.0)


static func _vec(key: String, def: Vector2) -> Vector2:
	var v: Variant = Balance.get_value("hud", key, def)
	return v if v is Vector2 else def


static func _circle(c: Vector2, r: float) -> Rect2:
	return Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)


## Ramène `r` dans `area` (marges sûres).
static func _fit(r: Rect2, area: Rect2) -> Rect2:
	var p := r.position
	p.x = clampf(p.x, area.position.x, maxf(area.end.x - r.size.x, area.position.x))
	p.y = clampf(p.y, area.position.y, maxf(area.end.y - r.size.y, area.position.y))
	return Rect2(p, r.size)


func _place() -> void:
	if not is_inside_tree():
		return
	var lay := compute_layout(get_viewport_rect().size, HudSafeArea.margins(self), quick_rounds.size())
	_apply(pill, lay["pill"])
	for i in other_rounds.size():
		_apply(other_rounds[i], lay["other%d" % i])
	_apply(gadget_round, lay["gadget"])
	_apply(reload_button, lay["reload"])
	for i in quick_rounds.size():
		_apply(quick_rounds[i], lay["quick%d" % i])
	if not quick_rounds.is_empty():
		var q: Rect2 = lay["quick0"]
		_hint.position = Vector2(q.position.x, q.position.y - 30.0)


static func _apply(c: Control, r: Rect2) -> void:
	c.custom_minimum_size = r.size
	c.position = r.position
	c.size = r.size


# --- Joueur et sac ---------------------------------------------------------------------

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
	if p.has_signal(&"gadget_changed"):
		var n_args := _signal_args(p, &"gadget_changed")
		p.connect(&"gadget_changed", refresh_gadget.unbind(n_args) if n_args > 0 else refresh_gadget)
	if p.has_signal(&"quick_used"):
		p.connect(&"quick_used", _on_quick_used)
	if p.has_signal(&"reload_started"):
		p.connect(&"reload_started", _update_reload)
	_bind_inventory()
	_refresh_quick_usable()
	refresh()


func _bind_inventory() -> void:
	var inv: Inventory = GameState.raid_inventory
	if inv == _inv:
		return
	if _inv != null and _inv.changed.is_connected(refresh_quick):
		_inv.changed.disconnect(refresh_quick)
	_inv = inv
	if _inv != null:
		_inv.changed.connect(refresh_quick)
	refresh_quick()


## Relit les armes tenues, l'arme courante et les munitions (sur signal).
func refresh() -> void:
	_weapons = read_weapons(player)
	_current = 0
	if is_instance_valid(player) and player.get("current_slot") is int:
		_current = clampi(int(player.get("current_slot")), 0, SLOT_COUNT - 1)
	_read_ammo()
	var cur: WeaponData = _weapons[_current] if _current < _weapons.size() else null
	pill.set_state(cur, _ammo, _magazine, _current)
	var k := 0
	for i in SLOT_COUNT:
		if i == _current:
			continue
		if k < other_rounds.size():
			other_rounds[k].index = i
			other_rounds[k].set_weapon(_weapons[i] if i < _weapons.size() else null)
		k += 1
	_update_reload()
	refresh_gadget()


static func _signal_args(obj: Object, sig: StringName) -> int:
	for d: Dictionary in obj.get_signal_list():
		if StringName(d.get("name", "")) == sig:
			return (d.get("args", []) as Array).size()
	return 0


## Équipement tenu et charges restantes (API get_gadget / get_gadget_charges ; repli :
## GameState.raid_gadget avec toutes ses charges).
func refresh_gadget() -> void:
	_gadget = null
	_gadget_charges = 0
	if is_instance_valid(player) and player.has_method(&"get_gadget"):
		_gadget = player.call(&"get_gadget") as WeaponData
		if _gadget != null:
			_gadget_charges = int(player.call(&"get_gadget_charges")) if player.has_method(&"get_gadget_charges") else _gadget.charges
	elif GameState.get("raid_gadget") is WeaponData:
		_gadget = GameState.get("raid_gadget")
		_gadget_charges = _gadget.charges
	gadget_round.set_gadget(_gadget, _gadget_charges)


## Emplacements rapides (sur Inventory.changed).
func refresh_quick() -> void:
	if _inv == null:
		_rebuild_quick(0)
		return
	_rebuild_quick(_inv.quick_count())
	for i in quick_rounds.size():
		quick_rounds[i].set_item(_inv.quick_item(i), _inv.quick_amount(i))
	_refresh_quick_usable()


## Grise les emplacements dont l'objet ne sert à rien maintenant (redessin seulement si ça change).
func _refresh_quick_usable() -> void:
	for s: QuickSlot in quick_rounds:
		s.set_usable(quick_usable(s.item, s.count, player))


## Objet d'emplacement rapide utilisable maintenant : soin seulement si les PV ne sont pas pleins
## (et joueur en vie), équipement toujours (il s'équipe), rien sans exemplaire dans le sac.
static func quick_usable(it: ItemData, n: int, p: Node) -> bool:
	if it == null or n <= 0:
		return false
	if p == null or not is_instance_valid(p):
		return true
	if p.get("_alive") is bool and not bool(p.get("_alive")):
		return false
	if it.is_usable():
		var hp: Variant = p.get("hp")
		var max_hp: Variant = p.get("max_hp")
		if hp != null and max_hp != null:
			return float(hp) < float(max_hp)
	return true


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
	pill.set_ammo(ammo, magazine)
	_update_reload()


func _on_fired(_dir: Vector2 = Vector2.ZERO) -> void:
	if not (is_instance_valid(player) and player.has_signal(&"ammo_changed")):
		_read_ammo()
		pill.set_ammo(_ammo, _magazine)
	_update_reload()


func _poll() -> void:
	_bind_inventory()
	if not is_instance_valid(player):
		return
	# Faux joueurs / PV changés sans signal : simple comparaison, redessin seulement si ça change.
	_refresh_quick_usable()
	if _is_reloading() != is_processing():
		_update_reload()


func _is_reloading() -> bool:
	return is_instance_valid(player) and player.has_method(&"is_reloading") and bool(player.call(&"is_reloading"))


## Rechargement : _process actif seulement pendant qu'il dure. Bouton allumé si le chargeur est bas.
func _update_reload() -> void:
	var reloading := _is_reloading()
	set_process(reloading)
	var p := _reload_progress() if reloading else -1.0
	pill.set_reload(p)
	reload_button.set_progress(p)
	var low := _magazine > 0 and _ammo <= maxi(1, int(_magazine * Balance.get_float("hud", "reload_alert_ratio", 0.3)))
	reload_button.set_alert(low and not reloading)
	reload_button.set_enabled(_magazine > 0 and _ammo < _magazine and not reloading)


func _reload_progress() -> float:
	if is_instance_valid(player) and player.has_method(&"get_reload_progress"):
		return clampf(float(player.call(&"get_reload_progress")), 0.0, 1.0)
	return 0.0


func _process(_delta: float) -> void:
	if not _is_reloading():
		set_process(false)
		_read_ammo()
		pill.set_ammo(_ammo, _magazine)
		_update_reload()
		return
	var p := _reload_progress()
	pill.set_reload(p)
	reload_button.set_progress(p)


# --- Entrées -------------------------------------------------------------------------

func _on_round_tapped(i: int) -> void:
	if not is_instance_valid(player) or i == _current:
		return
	if i >= _weapons.size() or _weapons[i] == null:
		return
	if player.has_method(&"switch_to"):
		player.call(&"switch_to", i)
		ItemUse.play(self, &"click_soft")
		if not player.has_signal(&"weapons_changed"):
			refresh()


func _on_switch_pressed() -> void:
	if not is_instance_valid(player) or _count_weapons() <= 1:
		return
	if player.has_method(&"next_weapon"):
		player.call(&"next_weapon")
		ItemUse.play(self, &"click_soft")
		if not player.has_signal(&"weapons_changed"):
			refresh()


func _on_reload_pressed() -> void:
	if not is_instance_valid(player) or not player.has_method(&"reload"):
		return
	if _is_reloading() or (_magazine > 0 and _ammo >= _magazine):
		return
	player.call(&"reload")
	_update_reload()


func _on_gadget_pressed() -> void:
	if not is_instance_valid(player) or _gadget == null or _gadget_charges <= 0:
		return
	if player.has_method(&"use_gadget"):
		var dir: Variant = player.get("aim_direction")
		player.call(&"use_gadget", dir if dir is Vector2 else Vector2.RIGHT)
		ItemUse.play(self, &"click_soft")
		if not player.has_signal(&"gadget_changed"):
			refresh_gadget()


func _on_quick_tapped(i: int) -> void:
	if _inv == null or i >= _inv.quick_count():
		return
	if _inv.quick[i].is_empty():
		# Emplacement libre : le sac s'ouvre pour y glisser un objet.
		var ih := get_tree().get_first_node_in_group(&"inventory_hud")
		if ih != null and ih.has_method(&"toggle_inventory"):
			ih.call(&"toggle_inventory")
		return
	if is_instance_valid(player) and player.has_method(&"use_quick"):
		player.call(&"use_quick", i)
		if not player.has_signal(&"quick_used"):
			refresh_quick()
	else:
		_on_quick_used(i, ItemUse.use_quick(_inv, i, player))


func _on_quick_used(i: int, message: String) -> void:
	if i < quick_rounds.size():
		quick_rounds[i].flash(message.is_empty())
		# Temps de recharge circulaire si l'objet en a un (API optionnelle du joueur, en secondes).
		if message.is_empty() and is_instance_valid(player) and player.has_method(&"get_quick_cooldown"):
			quick_rounds[i].start_cooldown(float(player.call(&"get_quick_cooldown", i)))
	if message.is_empty():
		return
	show_hint(message)


## Message court au-dessus des emplacements rapides (refus d'utilisation).
func show_hint(text: String) -> void:
	_hint.text = text
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint.modulate.a = 1.0
	_hint_tween = create_tween()
	_hint_tween.tween_interval(1.6)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.3)


func get_hint_text() -> String:
	return _hint.text if _hint.modulate.a > 0.0 else ""


# =====================================================================================

## Élément tactile du HUD : touches lues dans _input (avant les sticks), souris réelle via _gui_input.
class HudButton extends Control:
	signal tapped(index: int)

	var index: int = 0
	var enabled: bool = true
	var _down: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func set_enabled(on: bool) -> void:
		if on == enabled:
			return
		enabled = on
		queue_redraw()

	func _hit(p: Vector2) -> bool:
		return get_global_rect().grow(6.0).has_point(p)

	func _input(event: InputEvent) -> void:
		if not is_visible_in_tree() or not (event is InputEventScreenTouch):
			return
		var t := event as InputEventScreenTouch
		if t.pressed and _hit(t.position):
			get_viewport().set_input_as_handled()
			press()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				accept_event()
				press()

	## Toucher (tests : simule l'appui).
	func press() -> void:
		_down = 1.0
		queue_redraw()
		tapped.emit(index)
		if is_inside_tree():
			get_tree().create_timer(0.1, true, false, true).timeout.connect(func() -> void:
				_down = 0.0
				queue_redraw())


## Pastille de l'arme tenue : fond violet à coin biseauté, liseré de rareté, icône, munitions, nom.
class ActivePill extends HudButton:
	var weapon: WeaponData = null
	var ammo: int = -1
	var magazine: int = 0
	var reload: float = -1.0

	func _init() -> void:
		super()
		name = "ActiveWeapon"

	func set_state(w: WeaponData, p_ammo: int, p_mag: int, slot: int) -> void:
		weapon = w
		ammo = p_ammo
		magazine = p_mag
		index = slot
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

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var rc: Color = weapon.get_rarity_color() if weapon != null else Color(1, 1, 1, 0.3)
		var bg := CutBox.make(Color(MenuKit.VIOLET, 0.92 if _down > 0.0 else 0.74), 12.0)
		bg.corners = CutBox.CUT_TOP_LEFT | CutBox.CUT_BOTTOM_RIGHT
		bg.accent_width = 4.0
		bg.accent_color = rc
		draw_style_box(bg, r)
		var text_font := LootVisuals.text_font(700)
		if weapon == null:
			draw_string(text_font, Vector2(14, size.y * 0.5 + 6), "Aucune arme", HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 15, Color(1, 1, 1, 0.7))
			return
		var icon_w := size.x * 0.46
		LootVisuals.draw_weapon(self, Rect2(Vector2(10, 6), Vector2(icon_w, size.y - 24)), weapon)
		# Nom (Space Grotesk, petit, sous l'icône).
		draw_string_outline(text_font, Vector2(10, size.y - 7), weapon.display_name, HORIZONTAL_ALIGNMENT_LEFT, icon_w + 6, 12, 4, MenuKit.NIGHT_DEEP)
		draw_string(text_font, Vector2(10, size.y - 7), weapon.display_name, HORIZONTAL_ALIGNMENT_LEFT, icon_w + 6, 12, Color.WHITE)
		var font: Font = MenuKit.display()
		var right := size.x - 10.0
		var base_y := size.y * 0.5 + 10.0
		if reload >= 0.0:
			var t := "RECHARGE"
			var tw := text_font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(text_font, Vector2(right - tw, base_y - 6.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
			var bar := Rect2(Vector2(right - 62.0, base_y + 2.0), Vector2(62.0, 5.0))
			draw_rect(bar, Color(MenuKit.NIGHT_DEEP, 0.7))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * reload, bar.size.y)), Color.WHITE)
			return
		if magazine <= 0:
			var inf := "∞"
			var iw := font.get_string_size(inf, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
			draw_string(font, Vector2(right - iw, base_y + 2.0), inf, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
			return
		var a := str(maxi(ammo, 0))
		var m := " / %d" % magazine
		var low := ammo <= maxi(1, int(magazine * 0.25))
		var mw := font.get_string_size(m, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var aw := font.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		var col := Color(1.0, 0.55, 0.6) if low else Color.WHITE
		draw_string_outline(font, Vector2(right - mw - aw, base_y + 2.0), a, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 5, MenuKit.NIGHT_DEEP)
		draw_string(font, Vector2(right - mw - aw, base_y + 2.0), a, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, col)
		draw_string(font, Vector2(right - mw, base_y + 2.0), m, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.7))


## Petit rond : autre arme, équipement ou rechargement.
class HudRound extends HudButton:
	const KIND_WEAPON := 0
	const KIND_GADGET := 1
	const KIND_RELOAD := 2

	var kind: int = KIND_WEAPON
	var radius: float = 27.0
	var weapon: WeaponData = null
	var count: int = 0
	var progress: float = -1.0
	var alert: bool = false
	## Touche clavier affichée sur PC (aucune sur écran tactile).
	var key_hint: String = ""
	var _flash_ok: float = 0.0
	var _flash_bad: float = 0.0

	func set_weapon(w: WeaponData) -> void:
		weapon = w
		key_hint = str(index + 1)
		queue_redraw()

	func set_gadget(w: WeaponData, charges: int) -> void:
		weapon = w
		count = charges
		key_hint = "G"
		set_enabled(w != null and charges > 0)
		queue_redraw()

	func set_progress(p: float) -> void:
		if is_equal_approx(p, progress):
			return
		progress = p
		queue_redraw()

	func set_alert(on: bool) -> void:
		if on == alert:
			return
		alert = on
		queue_redraw()

	## Retour visuel d'utilisation (vert = fait, rouge = refusé).
	func flash(ok: bool) -> void:
		if ok:
			_flash_ok = 1.0
		else:
			_flash_bad = 1.0
		queue_redraw()
		if is_inside_tree():
			get_tree().create_timer(0.25, true, false, true).timeout.connect(func() -> void:
				_flash_ok = 0.0
				_flash_bad = 0.0
				queue_redraw())

	func _hit(p: Vector2) -> bool:
		return get_global_rect().get_center().distance_to(p) <= radius + 7.0

	func _draw() -> void:
		var c := size * 0.5
		var r := radius * (0.92 if _down > 0.0 else 1.0)
		var empty := (kind == KIND_WEAPON or kind == KIND_GADGET) and weapon == null
		var fill := Color(MenuKit.NIGHT_DEEP, 0.45 if empty else 0.74)
		if _down > 0.0:
			fill = Color(MenuKit.VIOLET, 0.85)
		elif alert:
			fill = Color(MenuKit.VIOLET, 0.8)
		elif _flash_ok > 0.0:
			fill = Color(0.2, 0.55, 0.32, 0.9)
		elif _flash_bad > 0.0:
			fill = Color(0.6, 0.15, 0.2, 0.9)
		draw_circle(c, r, fill, true, -1.0, true)
		var ring := Color(1, 1, 1, 0.35)
		if kind == KIND_WEAPON and weapon != null:
			ring = weapon.get_rarity_color()
		elif alert:
			ring = MenuKit.GOLD
		if empty:
			# Pointillés : emplacement libre.
			for k in 16:
				var a0 := TAU * float(k) / 16.0
				draw_arc(c, r - 1.0, a0, a0 + TAU / 32.0, 3, Color(1, 1, 1, 0.4), 2.0, true)
		else:
			draw_arc(c, r - 1.0, 0.0, TAU, 40, Color(ring, 0.9 if enabled else 0.4), 2.0, true)
		var inner := Rect2(c - Vector2(r, r) * 0.62, Vector2(r, r) * 1.24)
		var a := 1.0 if enabled else 0.45
		match kind:
			KIND_WEAPON:
				if weapon != null:
					# Disque clair derrière l'icône : armes sombres lisibles sur le fond encre.
					draw_circle(c, r * 0.82, Color(1, 1, 1, 0.16), true, -1.0, true)
					LootVisuals.draw_weapon(self, Rect2(c - Vector2(r * 0.78, r * 0.52), Vector2(r * 1.56, r * 1.04)), weapon)
			KIND_GADGET:
				if weapon != null:
					LootVisuals.draw_weapon(self, inner, weapon, Color(1, 1, 1, a))
					_badge("×%d" % maxi(count, 0), count > 0)
				else:
					LootVisuals.draw_weapon_glyph(self, inner, &"frag", Color(1, 1, 1, 0.35))
			KIND_RELOAD:
				_draw_reload_icon(c, r, a)
		if not key_hint.is_empty() and not DisplayServer.is_touchscreen_available():
			var f := LootVisuals.text_font(700)
			draw_string_outline(f, Vector2(c.x - r * 0.95, c.y - r * 0.55), key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, MenuKit.NIGHT_DEEP)
			draw_string(f, Vector2(c.x - r * 0.95, c.y - r * 0.55), key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.75))

	func _badge(t: String, ok: bool) -> void:
		var f: Font = MenuKit.display()
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var at := Vector2(size.x * 0.5 + radius * 0.85 - w, size.y * 0.5 + radius * 0.95)
		draw_string_outline(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, MenuKit.NIGHT_DEEP)
		draw_string(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE if ok else Color(1.0, 0.55, 0.6))

	## Flèche circulaire (recharger) ; progression du rechargement en arc violet clair.
	func _draw_reload_icon(c: Vector2, r: float, a: float) -> void:
		var col := Color(1, 1, 1, a)
		var ar := r * 0.46
		draw_arc(c, ar, -PI * 0.2, PI * 1.45, 24, col, 3.5, true)
		var end := -PI * 0.2
		var tip := c + Vector2.from_angle(end) * ar
		var tangent := Vector2.from_angle(end - PI * 0.5)
		var normal := Vector2.from_angle(end)
		draw_colored_polygon(PackedVector2Array([tip + tangent * 8.0, tip - normal * 6.0, tip + normal * 6.0]), col)
		if progress >= 0.0:
			draw_arc(c, r - 3.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 40, MenuKit.GOLD, 4.0, true)


## Emplacement rapide : case biseautée (haut-gauche / bas-droit, comme la pastille d'arme), fond
## encre translucide, liseré à la couleur de rareté (doublé d'un trait fin net pour Épique et
## Légendaire), icône réduite une fois pour toutes à sa taille réelle à l'écran (nette, sans halo),
## quantité dans un badge Anton logé dans le coin bas-droit. Vide : case fantôme et petit « + ».
## Grisée quand l'objet ne sert à rien maintenant (PV pleins). Utilisation : flash, rebond du
## chiffre qui décrémente, temps de recharge circulaire si l'objet en a un. Dessin statique :
## redessiné seulement quand l'état change (et le temps d'une animation courte).
class QuickSlot extends HudButton:
	## Icônes réduites (clé : objet, taille en px écran, grisée) : une seule réduction par cas.
	static var _icon_cache: Dictionary = {}

	var item: ItemData = null
	var count: int = 0
	## Faux : l'objet ne sert à rien maintenant (soin à PV pleins, plus d'exemplaire).
	var usable: bool = true
	## Touche clavier affichée sur PC (aucune sur écran tactile).
	var key_hint: String = ""
	## Part restante du temps de recharge (0 = prêt).
	var cooldown: float = 0.0
	var _flash: float = 0.0
	var _flash_ok: bool = true
	var _bump: float = 0.0
	var _tw_flash: Tween = null
	var _tw_bump: Tween = null
	var _tw_cd: Tween = null

	func set_item(it: ItemData, n: int) -> void:
		var same := it != null and item != null and it.instance_key() == item.instance_key()
		if same and n == count:
			return
		var dropped := same and n < count
		item = it
		count = n
		if dropped:
			_tw_bump = _animate(_tw_bump, &"_bump", Balance.get_float("hud", "quick_bump_time", 0.3))
		queue_redraw()

	func set_usable(on: bool) -> void:
		if on == usable:
			return
		usable = on
		queue_redraw()

	## Retour visuel d'utilisation (violet = fait, rouge = refusé).
	func flash(ok: bool) -> void:
		_flash_ok = ok
		_tw_flash = _animate(_tw_flash, &"_flash", Balance.get_float("hud", "quick_flash_time", 0.35))

	## Temps de recharge circulaire (secondes), si l'objet en a un.
	func start_cooldown(seconds: float) -> void:
		if seconds > 0.0:
			_tw_cd = _animate(_tw_cd, &"cooldown", seconds)

	## Anime `prop` de 1 à 0 : redessin à chaque pas, le temps de l'animation seulement.
	func _animate(tw: Tween, prop: StringName, duration: float) -> Tween:
		if tw != null and tw.is_valid():
			tw.kill()
		if not is_inside_tree() or duration <= 0.0:
			set(prop, 0.0)
			queue_redraw()
			return null
		set(prop, 1.0)
		queue_redraw()
		var nt := create_tween()
		nt.tween_method(func(v: float) -> void:
			set(prop, v)
			queue_redraw(), 1.0, 0.0, duration)
		return nt

	func _hit(p: Vector2) -> bool:
		return get_global_rect().grow(Balance.get_float("hud", "quick_hit_grow", 5.0)).has_point(p)

	## Badge de quantité (coordonnées locales) pour une case de taille `sz` : coin bas-droit,
	## à l'intérieur du liseré (tests : ne déborde pas).
	static func badge_rect(sz: Vector2, n: int) -> Rect2:
		var fs := int(Balance.get_float("hud", "quick_badge_font", 16.0))
		var bw := Balance.get_float("hud", "quick_border", 2.0)
		var tw := MenuKit.display().get_string_size(_badge_text(n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var h := float(fs) + 6.0
		var w := minf(tw + 12.0, sz.x - bw * 2.0)
		return Rect2(sz - Vector2(w, h) - Vector2(bw, bw), Vector2(w, h))

	static func _badge_text(n: int) -> String:
		return "×%d" % maxi(n, 0)

	## Polygone de la case (biseaux haut-gauche et bas-droit).
	func _shape(r: Rect2, cut: float) -> PackedVector2Array:
		var c := minf(cut, minf(r.size.x, r.size.y) * 0.5)
		return PackedVector2Array([r.position + Vector2(0, c), r.position + Vector2(c, 0),
			Vector2(r.end.x, r.position.y), r.end - Vector2(0, c), r.end - Vector2(c, 0),
			Vector2(r.position.x, r.end.y)])

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var cut := Balance.get_float("hud", "quick_cut", 12.0)
		var bw := Balance.get_float("hud", "quick_border", 2.0)
		var ink := Color(MenuKit.NIGHT_PANEL, 1.0)
		var shape := _shape(r, cut)
		if item == null:
			_draw_empty(shape, ink)
			_draw_key()
			return
		var rc := LootDB.rarity_color(item.rarity)
		# Lueur nette Épique / Légendaire : second liseré fin à l'extérieur (pas de flou).
		if item.rarity >= ItemData.Rarity.EPIC and usable:
			var outer := _shape(r.grow(3.0), cut + 1.5)
			outer.append(outer[0])
			draw_polyline(outer, Color(rc, 0.5), 1.5, true)
		var fill := Color(ink.lerp(rc, 0.14 if usable else 0.0), Balance.get_float("hud", "quick_bg_alpha", 0.78))
		var border := Color(rc, 1.0 if usable else 0.35)
		if _down > 0.0:
			fill = Color(MenuKit.VIOLET, 0.85)
		if _flash > 0.0:
			var fc: Color = MenuKit.VIOLET_LIGHT if _flash_ok else MenuKit.BAD
			fill = fill.lerp(Color(fc, 0.9), _flash * 0.75)
			border = border.lerp(Color.WHITE, _flash)
		draw_colored_polygon(shape, fill)
		var loop := shape.duplicate()
		loop.append(shape[0])
		draw_polyline(loop, border, bw, true)
		# Icône centrée, réduite à sa taille réelle à l'écran.
		var pad := Balance.get_float("hud", "quick_icon_pad", 9.0)
		var box := r.grow(-pad)
		var tex := _icon(item, box.size, not usable)
		if tex != null:
			var ts := Vector2(tex.get_size())
			var ds := ts * minf(box.size.x / ts.x, box.size.y / ts.y)
			var mod := Color(LootVisuals.item_tint(item), 1.0)
			if not usable:
				mod = Color(1, 1, 1, Balance.get_float("hud", "quick_unusable_alpha", 0.5))
			draw_texture_rect(tex, Rect2(box.position + (box.size - ds) * 0.5, ds), false, mod)
		# Temps de recharge : secteur sombre qui se rétracte dans le sens horaire.
		if cooldown > 0.0:
			var c := size * 0.5
			var span := TAU * minf(cooldown, 0.999)
			var a0 := -PI * 0.5 + TAU - span
			var steps := maxi(3, int(48.0 * cooldown))
			var sector := PackedVector2Array([c])
			for k in steps + 1:
				sector.append(c + Vector2.from_angle(a0 + span * float(k) / float(steps)) * size.length())
			for poly: PackedVector2Array in Geometry2D.intersect_polygons(sector, shape):
				draw_colored_polygon(poly, Color(MenuKit.NIGHT_DEEP, 0.62))
		_draw_badge(cut)
		_draw_key()

	func _draw_empty(shape: PackedVector2Array, ink: Color) -> void:
		draw_colored_polygon(shape, Color(MenuKit.VIOLET, 0.6) if _down > 0.0 else Color(ink, 0.3))
		var loop := shape.duplicate()
		loop.append(shape[0])
		draw_polyline(loop, Color(1, 1, 1, 0.16), 1.0, true)
		var c := (size * 0.5).round()
		var h := roundf(size.x * 0.1)
		var col := Color(1, 1, 1, 0.5)
		draw_rect(Rect2(c - Vector2(h, 1), Vector2(h * 2.0, 2)), col)
		draw_rect(Rect2(c - Vector2(1, h), Vector2(2, h * 2.0)), col)

	## Quantité : badge encre (biseau bas-droit calé sur celui de la case), chiffre Anton blanc,
	## rebond quand il décrémente.
	func _draw_badge(cut: float) -> void:
		var br := badge_rect(size, count)
		var fs := int(Balance.get_float("hud", "quick_badge_font", 16.0))
		var font: Font = MenuKit.display()
		var s := 1.0 + (Balance.get_float("hud", "quick_bump_scale", 1.35) - 1.0) * _bump * _bump
		if s != 1.0:
			var pivot := br.get_center()
			draw_set_transform(pivot * (1.0 - s), 0.0, Vector2(s, s))
		var cb := minf(cut, br.size.y * 0.6)
		var poly := PackedVector2Array([br.position + Vector2(0, 4), br.position + Vector2(4, 0),
			Vector2(br.end.x, br.position.y), br.end - Vector2(0, cb), br.end - Vector2(cb, 0),
			Vector2(br.position.x, br.end.y)])
		draw_colored_polygon(poly, Color(MenuKit.NIGHT_DEEP, 0.92))
		var t := _badge_text(count)
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var asc := font.get_ascent(fs)
		var base := br.position.y + (br.size.y - asc - font.get_descent(fs)) * 0.5 + asc
		var col := Color.WHITE if usable else Color(1, 1, 1, 0.6)
		if count <= 0:
			col = MenuKit.BAD
		draw_string(font, Vector2(br.position.x + (br.size.x - tw) * 0.5 - cb * 0.15, base), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if s != 1.0:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_key() -> void:
		if key_hint.is_empty() or DisplayServer.is_touchscreen_available():
			return
		var f := LootVisuals.text_font(700)
		var w := f.get_string_size(key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, Vector2(size.x - 7.0 - w, 15.0), key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))

	## Rapport pixels écran / pixels viewport (étirement canvas_items) : l'icône est réduite à
	## sa taille réelle à l'écran.
	func _screen_scale() -> float:
		if not is_inside_tree():
			return 1.0
		var vp := get_viewport_rect().size
		return clampf(float(get_tree().root.size.y) / vp.y, 1.0, 4.0) if vp.y > 0.0 else 1.0

	## Icône de l'objet réduite (Lanczos, bords alpha corrigés) à la taille de `box` à l'écran ;
	## version grisée pour l'état « pas utilisable ». Calculée une fois, puis en cache.
	func _icon(it: ItemData, box: Vector2, grey: bool) -> Texture2D:
		var src := LootVisuals.item_icon(it)
		if src == null:
			return null
		var sc := _screen_scale()
		var px := Vector2i(maxi(roundi(box.x * sc), 1), maxi(roundi(box.y * sc), 1))
		var key := "%s|%d|%d|%s" % [it.id, px.x, px.y, grey]
		if _icon_cache.has(key):
			return _icon_cache[key]
		var tex: Texture2D = src
		var img := src.get_image()
		if img != null and not img.is_empty():
			img = img.duplicate() as Image
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			img.fix_alpha_edges()
			var fit := minf(float(px.x) / img.get_width(), float(px.y) / img.get_height())
			img.resize(maxi(roundi(img.get_width() * fit), 1), maxi(roundi(img.get_height() * fit), 1), Image.INTERPOLATE_LANCZOS)
			if grey:
				for y in img.get_height():
					for x in img.get_width():
						var c := img.get_pixel(x, y)
						var l := c.get_luminance()
						img.set_pixel(x, y, Color(l, l, l, c.a))
			tex = ImageTexture.create_from_image(img)
		_icon_cache[key] = tex
		return tex