class_name InventorySlot
extends Control
## Case d'inventaire (grande zone tactile) : icône, bordure de rareté, quantité, pastilles
## d'affixes. Redessinée seulement quand son contenu ou la sélection change.
## Glisser-déposer (souris, ou doigt via l'émulation souris du toucher) : une case pleine se
## glisse ({"from": "bag", "index": i}) ; une case accepte ce que `accepts` autorise et émet
## `dropped` (l'écran d'inventaire décide quoi faire).

signal clicked(index: int)
signal dropped(index: int, data: Dictionary)

var index: int = 0
var item: ItemData = null
var count: int = 0
var selected: bool = false
## Glisser-déposer actif (écran d'inventaire).
var draggable: bool = false
## Filtre des dépôts acceptés (données du glisser → bool) ; vide = rien.
var accepts: Callable = Callable()
var _drop_hover: bool = false


func _init(p_index: int = 0, p_size: float = 92.0) -> void:
	index = p_index
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func set_content(p_item: ItemData, p_count: int, p_selected: bool) -> void:
	if p_item == item and p_count == count and p_selected == selected:
		return
	item = p_item
	count = p_count
	selected = p_selected
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(index)
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if not draggable or item == null:
		return null
	set_drag_preview(make_preview(item, count, size.x))
	return {"from": "bag", "index": index, "item": item}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var ok: bool = data is Dictionary and accepts.is_valid() and bool(accepts.call(data))
	if ok != _drop_hover:
		_drop_hover = ok
		queue_redraw()
	return ok


func _drop_data(_at: Vector2, data: Variant) -> void:
	_drop_hover = false
	queue_redraw()
	dropped.emit(index, data as Dictionary)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		if _drop_hover:
			_drop_hover = false
			queue_redraw()


## Aperçu suivant le doigt pendant le glisser (case translucide, légèrement agrandie).
static func make_preview(p_item: ItemData, p_count: int, side: float) -> Control:
	var holder := Control.new()
	var tile := Control.new()
	tile.size = Vector2(side, side) * 1.08
	tile.position = -tile.size * 0.5
	tile.modulate.a = 0.85
	tile.draw.connect(func() -> void:
		InventoryStyle.draw_item_tile(tile, Rect2(Vector2.ZERO, tile.size), p_item, p_count, true, LootVisuals.text_font(800)))
	holder.add_child(tile)
	return holder


func _draw() -> void:
	InventoryStyle.draw_item_tile(self, Rect2(Vector2.ZERO, size), item, count, selected, LootVisuals.text_font(800))
	if _drop_hover:
		var hl := CutBox.make(Color(MenuKit.VIOLET, 0.25), 6.0, MenuKit.GOLD, 2.0)
		draw_style_box(hl, Rect2(Vector2.ZERO, size))
