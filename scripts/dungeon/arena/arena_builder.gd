class_name ArenaBuilder
extends Node2D
## Décor de l'« Arène de test » (direction D) : sol encre quadrillé très lisible (une ligne par
## case, une ligne violette toutes les [test_arena] grid_major cases), murs et couverts en blocs
## encre à arête violette, collisions sur la couche monde. Même contrat que FallbackBuilder /
## WorldBuilder (build(layout, world) -> Node2D, get_doors(), get_stairs_areas(), stairs_entered).

signal stairs_entered(stairs: FloorLayout.Stairs)

const LAYER_WORLD := 1

var layout: FloorLayout = null


static func build(p_layout: FloorLayout, _world: Resource = null) -> ArenaBuilder:
	var root := ArenaBuilder.new()
	root.name = "ArenaWorld"
	root.layout = p_layout
	root._build()
	return root


func get_doors() -> Array[Node2D]:
	return [] as Array[Node2D]


func get_stairs_areas() -> Array[Area2D]:
	return [] as Array[Area2D]


func _build() -> void:
	var ground := ArenaGround.new()
	ground.name = "Ground"
	ground.layout = layout
	ground.major = maxi(int(Balance.get_value("test_arena", "grid_major", 4)), 1)
	ground.z_index = 0
	add_child(ground)
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	for r: Rect2i in FallbackBuilder.merge_cells(layout, FallbackBuilder.is_solid_tile):
		var wr := FallbackBuilder.cell_rect_world(r)
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = wr.size
		cs.shape = shape
		cs.position = wr.get_center()
		body.add_child(cs)


## Sol et blocs, dessinés une fois (palette MenuKit : encre, violet).
class ArenaGround extends Node2D:
	var layout: FloorLayout = null
	var major: int = 4

	func _draw() -> void:
		if layout == null:
			return
		var ts := float(FloorLayout.TILE_SIZE)
		var full := Rect2(Vector2.ZERO, Vector2(layout.size) * ts)
		draw_rect(full, Color(0.075, 0.08, 0.13))
		# Quadrillage : une ligne fine par case, une ligne violette toutes les `major` cases.
		for x: int in layout.size.x + 1:
			var strong := x % major == 0
			draw_line(Vector2(x * ts, 0), Vector2(x * ts, full.size.y),
				Color(MenuKit.VIOLET, 0.5) if strong else Color(1, 1, 1, 0.07), 2.0 if strong else 1.0)
		for y: int in layout.size.y + 1:
			var strong := y % major == 0
			draw_line(Vector2(0, y * ts), Vector2(full.size.x, y * ts),
				Color(MenuKit.VIOLET, 0.5) if strong else Color(1, 1, 1, 0.07), 2.0 if strong else 1.0)
		# Murs et couverts : bloc encre, face avant plus sombre, arête violette.
		for r: Rect2i in FallbackBuilder.merge_cells(layout, FallbackBuilder.is_solid_tile):
			var wr := FallbackBuilder.cell_rect_world(r)
			draw_rect(wr, Color(0.03, 0.035, 0.06))
			var face := Rect2(Vector2(wr.position.x, wr.end.y - ts * 0.28), Vector2(wr.size.x, ts * 0.28))
			draw_rect(face, Color(0.015, 0.016, 0.03))
			draw_rect(wr.grow(-1.0), Color(MenuKit.VIOLET, 0.85), false, 2.0)
