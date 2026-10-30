class_name InventoryBagButton
extends Control
## Bouton « sac » (haut droite) : ouvre l'écran d'inventaire. Affiche le nombre
## de cases occupées / la capacité, pastille dorée qui pulse brièvement quand un
## objet entre. Redessiné uniquement sur Inventory.changed.

signal pressed

const SIZE := Vector2(68, 68)

var inventory: Inventory = null
var _icon: Texture2D = null
var _down: bool = false
var _pulse: Tween = null


func _ready() -> void:
	name = "BagButton"
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	_icon = LootVisuals.load_icon("res://assets/third_party/icons/item_backpack.svg")
	bind(GameState.raid_inventory)


func bind(inv: Inventory) -> void:
	if inventory != null and inventory.changed.is_connected(queue_redraw):
		inventory.changed.disconnect(queue_redraw)
		inventory.item_added.disconnect(_on_added)
	inventory = inv
	if inventory != null:
		inventory.changed.connect(queue_redraw)
		inventory.item_added.connect(_on_added)
	queue_redraw()


func _on_added(_it: ItemData, _n: int) -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	scale = Vector2.ONE
	_pulse = create_tween()
	_pulse.tween_property(self, "scale", Vector2(1.15, 1.15), 0.08)
	_pulse.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)


## Touches lues dans _input (avant les joysticks) ; souris réelle via _gui_input.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		var local := get_global_transform_with_canvas().affine_inverse() * (event as InputEventScreenTouch).position
		if Rect2(Vector2.ZERO, size).grow(8.0).has_point(local):
			get_viewport().set_input_as_handled()
			_fire()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			accept_event()
			_fire()


func _fire() -> void:
	_down = true
	queue_redraw()
	pressed.emit()
	get_tree().create_timer(0.1, true, false, true).timeout.connect(func() -> void:
		_down = false
		queue_redraw())


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# maquette Hud : encre translucide, coin haut gauche coupé, sans contour
	var st := CutBox.make(Color(MenuKit.VIOLET, 0.8) if _down else Color(MenuKit.NIGHT_DEEP, 0.72), size.x * 0.2,
		Color(0, 0, 0, 0), 0.0, 0.0, 0.0)
	st.corners = CutBox.CUT_TOP_LEFT
	draw_style_box(st, r)
	if _icon != null:
		var isz := size.x * 0.56
		draw_texture_rect(_icon, Rect2(Vector2((size.x - isz) * 0.5, size.y * 0.1), Vector2(isz, isz)), false, Color(1.0, 0.93, 0.8))
	if inventory != null:
		var font := LootVisuals.text_font(800)
		var txt := "%d/%d" % [inventory.used_slots(), inventory.capacity()]
		var fs := 14
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2((size.x - w) * 0.5, size.y - 7.0)
		draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, InventoryStyle.NIGHT_BLUE_DEEP)
		draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MenuKit.GOLD if inventory.used_slots() > 0 else Color(1, 1, 1, 0.7))
