class_name Ladder
extends Node2D
## Point d'interaction d'une échelle vers un toit (FloorLayout.ladders) : un nœud au PIED
## (case de rue au sud de la façade, « Monter ») et un au SOMMET (bord sud du toit, « Descendre »),
## groupe `interactables` (InteractController : bouton d'action / touche E).
## L'action est déléguée à RoofWalk (animation, état « sur le toit »). En rendu pré-calculé
## l'échelle est dans l'image (fw_scene.py) ; en rendu 2D le nœud du pied la dessine (placeholder).

const WOOD := Color(0.52, 0.36, 0.22)
const WOOD_DARK := Color(0.3, 0.2, 0.13)
const OUTLINE := Color(0.09, 0.05, 0.08)

var roof_walk: Node = null
## Entrée de FloorLayout.ladders : {cell, building_id, top_cell}.
var entry: Dictionary = {}
var is_top: bool = false
var reach: float = 26.0
## Dessin de l'échelle (rendu 2D seulement) : du pied à `draw_to` (monde).
var draw_ladder: bool = false
var draw_to: Vector2 = Vector2.ZERO


static func make(walk: Node, e: Dictionary, top: bool, pos: Vector2, p_reach: float) -> Ladder:
	var l := Ladder.new()
	l.roof_walk = walk
	l.entry = e
	l.is_top = top
	l.reach = p_reach
	l.position = pos
	l.name = "Ladder_%d_%s" % [int(e.get("building_id", -1)), "top" if top else "foot"]
	return l


func _ready() -> void:
	add_to_group(&"interactables")
	add_to_group(&"ladders")
	if draw_ladder:
		z_index = 51
		z_as_relative = false
		queue_redraw()


func building_id() -> int:
	return int(entry.get("building_id", -1))


func _player(p: Node = null) -> Node:
	if p != null:
		return p
	return get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null


## Pied : joueur au sol ; sommet : joueur sur CE toit. Jamais pendant une montée.
func can_interact() -> bool:
	var p := _player()
	if p == null or roof_walk == null or bool(roof_walk.call("is_busy")):
		return false
	var on := int(p.get("roof_building_id")) if p.get("roof_building_id") != null else -1
	return on == building_id() if is_top else on < 0


## Cible proposée seulement au joueur perché (InteractController).
func is_roof_target() -> bool:
	return is_top


func get_interact_label() -> String:
	return "Descendre" if is_top else "Monter sur le toit"


func get_interact_reach() -> float:
	return reach


func interact(p: Node) -> void:
	if roof_walk != null and can_interact():
		roof_walk.call("climb", self, not is_top, p)


func _draw() -> void:
	if not draw_ladder:
		return
	var d := draw_to - position
	var n := d.normalized().orthogonal()
	for sg: float in [-1.0, 1.0]:
		draw_line(n * 11.0 * sg, d + n * 10.0 * sg, OUTLINE, 6.0)
		draw_line(n * 11.0 * sg, d + n * 10.0 * sg, WOOD_DARK, 3.5)
	var steps := int(d.length() / 14.0)
	for k in range(1, steps + 1):
		var c := d * (float(k) / float(steps + 1))
		draw_line(c - n * 10.0, c + n * 10.0, WOOD, 3.0)
