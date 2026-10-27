class_name DebugWorldDraw
extends Node2D
## Calque de dessin debug placé dans le MONDE (coordonnées globales).
## Visible uniquement quand le debug est actif (F3, via EventBus.debug_toggled).
##
## Extensible : tout système peut enregistrer sa propre fonction de dessin.
##   var dbg := DebugWorldDraw.find(get_tree())
##   if dbg: dbg.register_drawer(_draw_debug)       # func _draw_debug(canvas: DebugWorldDraw) -> void
## Le callable reçoit ce nœud et dessine avec ses méthodes draw_* en coordonnées
## globales (ce nœud reste à l'origine du monde). Les drawers dont l'objet a été
## libéré sont retirés automatiquement.

const GROUP := &"debug_world_draw"

const COLOR_RANGE := Color(1.0, 0.85, 0.3, 0.9)
const COLOR_TARGET := Color(1.0, 0.3, 0.2, 0.95)
const COLOR_ENEMY_HITBOX := Color(1.0, 0.25, 0.25, 0.8)
const COLOR_PLAYER_HITBOX := Color(0.3, 0.9, 1.0, 0.8)

var _drawers: Array[Callable] = []


## Renvoie le premier DebugWorldDraw de l'arbre, ou null.
static func find(tree: SceneTree) -> DebugWorldDraw:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as DebugWorldDraw


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 100
	top_level = true
	global_transform = Transform2D.IDENTITY
	EventBus.debug_toggled.connect(_on_debug_toggled)
	# Dessins de base de la phase 1.
	register_drawer(_draw_player_range)
	register_drawer(_draw_player_target)
	register_drawer(_draw_hitboxes)
	_on_debug_toggled(GameState.debug_enabled)


## Ajoute une fonction de dessin. Signature : func(canvas: DebugWorldDraw) -> void.
func register_drawer(drawer: Callable) -> void:
	if drawer.is_valid() and not _drawers.has(drawer):
		_drawers.append(drawer)


func unregister_drawer(drawer: Callable) -> void:
	_drawers.erase(drawer)


func get_drawer_count() -> int:
	return _drawers.size()


func _on_debug_toggled(enabled: bool) -> void:
	visible = enabled
	set_process(enabled)
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	for drawer: Callable in _drawers.duplicate():
		if not drawer.is_valid():
			_drawers.erase(drawer)
			continue
		drawer.call(self)
		draw_set_transform_matrix(Transform2D.IDENTITY)


# --- Dessins de base ---------------------------------------------------------

func _get_player() -> Node2D:
	var p: Node2D = GameState.player
	if is_instance_valid(p):
		return p
	return get_tree().get_first_node_in_group(&"player") as Node2D


func _draw_player_range(canvas: DebugWorldDraw) -> void:
	var player := _get_player()
	if player == null:
		return
	var weapon: Variant = player.get("weapon")
	if weapon is Resource and (weapon as Resource).get("range") != null:
		var r: float = float((weapon as Resource).get("range"))
		canvas.draw_arc(player.global_position, r, 0.0, TAU, 96, COLOR_RANGE, 2.0, true)
		canvas.draw_circle(player.global_position, r, Color(COLOR_RANGE, 0.05))


func _draw_player_target(canvas: DebugWorldDraw) -> void:
	var player := _get_player()
	if player == null:
		return
	var target: Variant = player.get("current_target")
	if target is Node2D and is_instance_valid(target):
		var t := target as Node2D
		canvas.draw_line(player.global_position, t.global_position, COLOR_TARGET, 3.0, true)
		canvas.draw_arc(t.global_position, 34.0, 0.0, TAU, 32, COLOR_TARGET, 3.0, true)


func _draw_hitboxes(canvas: DebugWorldDraw) -> void:
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
		if enemy is CollisionObject2D:
			draw_collision_shapes(canvas, enemy as CollisionObject2D, COLOR_ENEMY_HITBOX)
	var player := _get_player()
	if player is CollisionObject2D:
		draw_collision_shapes(canvas, player as CollisionObject2D, COLOR_PLAYER_HITBOX)


## Utilitaire public : dessine les CollisionShape2D directs d'un objet.
static func draw_collision_shapes(canvas: DebugWorldDraw, body: CollisionObject2D, color: Color) -> void:
	for child: Node in body.get_children():
		var cs := child as CollisionShape2D
		if cs == null or cs.shape == null or cs.disabled:
			continue
		canvas.draw_set_transform_matrix(canvas.get_global_transform().affine_inverse() * cs.get_global_transform())
		cs.shape.draw(canvas.get_canvas_item(), color)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
