class_name InventorySlot
extends Control
## Case d'inventaire (grande zone tactile) : icône, bordure de rareté, quantité.
## Redessinée seulement quand son contenu ou la sélection change.

signal clicked(index: int)

var index: int = 0
var item: ItemData = null
var count: int = 0
var selected: bool = false


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


func _draw() -> void:
	InventoryStyle.draw_item_tile(self, Rect2(Vector2.ZERO, size), item, count, selected, LootVisuals.text_font(800))
