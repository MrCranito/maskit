class_name LowGravity
extends RefCounted
## Zones de gravité faible (station spatiale) : `FloorLayout.low_gravity_cells`
## (Dictionary Vector2i → true) du layout courant, lu sur la scène courante (le raid,
## propriété `layout`) de façon robuste (absent = aucune zone). Logique pure + accès.


## Layout courant (FloorLayout ou null).
static func current_layout(tree: SceneTree) -> Object:
	if tree == null or tree.current_scene == null:
		return null
	var scene: Node = tree.current_scene
	if not ("layout" in scene):
		return null
	var l: Variant = scene.get("layout")
	return l as Object if l is Object else null


## Cases de gravité faible du layout (dictionnaire vide si absent).
static func cells_of(layout: Object) -> Dictionary:
	if layout == null or not ("low_gravity_cells" in layout):
		return {}
	var c: Variant = layout.get("low_gravity_cells")
	return c if c is Dictionary else {}


## Logique pure : la position monde `pos` est-elle dans une case de `cells` ?
static func is_in(cells: Dictionary, pos: Vector2) -> bool:
	if cells.is_empty():
		return false
	return cells.has(FloorLayout.world_to_cell(pos))


static func is_at(tree: SceneTree, pos: Vector2) -> bool:
	return is_in(cells_of(current_layout(tree)), pos)
