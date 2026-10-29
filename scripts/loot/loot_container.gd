class_name LootContainer
extends Node2D
## Conteneur fouillable (caisse, tonneau, coffre, placard, armoire, chariot,
## diligence, cadavre, coffre-fort, sacoche d'ennemi).
## Groupes : containers, fog_hideable, interactables. Origine = point d'appui au sol.
##
## Cycle : CLOSED --interact (maintenu)--> SEARCHING (cercle de progression, ~1,2 s,
## interrompu si le joueur bouge, est touché ou relâche) --> OPENED (contenu tiré,
## fenêtre de butin via EventBus.container_opened) --> EMPTIED quand tout est pris.
## Performance : _process actif uniquement pendant la fouille ; dessin statique sinon.

signal opened(container: LootContainer, entries: Array)
signal emptied(container: LootContainer)
signal search_cancelled(container: LootContainer)

enum State { CLOSED, SEARCHING, OPENED, EMPTIED }

const SPRITES_DIR := "res://assets/sprites/far_west/containers/"
const LAYER_WORLD := 1
const GROUP := &"containers"
const OUTLINE := Color(0.12, 0.07, 0.09)
const SHADOW_COLOR := Color(0.07, 0.1, 0.25, 0.4)

## kind → définition. scale : unités SVG → monde ; block : collision au sol (px) ;
## reach : portée d'interaction en plus ; shadow : demi-largeur de l'ombre ; foot : marge SVG.
const DEFS := {
	&"crate": {"name": "Caisse", "scale": 0.55, "block": Vector2(44, 16), "reach": 0.0, "shadow": 26.0, "foot": 4.0},
	&"barrel": {"name": "Tonneau", "scale": 0.55, "block": Vector2(30, 14), "reach": 0.0, "shadow": 18.0, "foot": 4.0},
	&"chest": {"name": "Coffre", "scale": 0.55, "block": Vector2(52, 18), "reach": 4.0, "shadow": 32.0, "foot": 4.0},
	&"cupboard": {"name": "Placard", "scale": 0.55, "block": Vector2(54, 16), "reach": 4.0, "shadow": 30.0, "foot": 2.0},
	&"wardrobe": {"name": "Armoire", "scale": 0.55, "block": Vector2(44, 14), "reach": 4.0, "shadow": 26.0, "foot": 2.0},
	&"wagon": {"name": "Chariot", "scale": 0.6, "block": Vector2(90, 24), "reach": 26.0, "shadow": 56.0, "foot": 4.0},
	&"stagecoach": {"name": "Diligence", "scale": 0.6, "block": Vector2(96, 26), "reach": 28.0, "shadow": 60.0, "foot": 4.0},
	&"corpse": {"name": "Hors-la-loi abattu", "scale": 0.55, "block": Vector2.ZERO, "reach": 12.0, "shadow": 0.0, "foot": 14.0},
	&"safe": {"name": "Coffre-fort", "scale": 0.55, "block": Vector2(44, 18), "reach": 4.0, "shadow": 26.0, "foot": 2.0},
	&"drop": {"name": "Sacoche", "scale": 0.0, "block": Vector2.ZERO, "reach": 6.0, "shadow": 12.0, "foot": 0.0},
}

static var _tex_cache: Dictionary = {}

var kind: StringName = &"crate"
var cell: Vector2i = Vector2i.ZERO
var floor_index: int = 0
var room_type: StringName = &"combat"
var difficulty: int = 1
var loot_seed: int = 0
## Contenu restant : Array de {"item": ItemData, "count": int}.
var entries: Array[Dictionary] = []
var state: int = State.CLOSED
## Contenu imposé (sacoches d'ennemis, tests) : utilisé à l'ouverture au lieu du tirage.
var preset_entries: Array[Dictionary] = []
var has_preset: bool = false
## Clef de persistance (LootManager) : "étage:x:y". Vide = non persistant.
var persist_key: String = ""

var search_time: float = 1.2
var search_hold: bool = true
var move_tolerance: float = 10.0

var _def: Dictionary = {}
var _sprite: Sprite2D = null
var _ring: Node2D = null
var _search_t: float = 0.0
var _searcher: Node2D = null
var _search_origin: Vector2 = Vector2.ZERO
var _glow_color: Color = Color(0, 0, 0, 0)


static func create(p_kind: StringName, pos: Vector2) -> LootContainer:
	var c := LootContainer.new()
	c.kind = p_kind if is_known_kind(p_kind) else &"crate"
	c.name = "Container_%s" % String(c.kind)
	c.position = pos
	return c


static func is_known_kind(k: StringName) -> bool:
	return DEFS.has(k) or not BiomeRegistry.container_def(k).is_empty()


## Définition du conteneur : Far West (DEFS), puis biomes (BiomeRegistry), sinon caisse.
static func def_for(k: StringName) -> Dictionary:
	if DEFS.has(k):
		return DEFS[k]
	var d: Dictionary = BiomeRegistry.container_def(k)
	return d if not d.is_empty() else DEFS[&"crate"]


static func get_texture(k: StringName, open: bool) -> Texture2D:
	var key := "%s_%s_%s" % [BiomeAssets.containers_dir, k, open]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var path := BiomeAssets.find_sprite(String(k) + ("_open" if open else ""), SPRITES_DIR)
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_tex_cache[key] = tex
	return tex


func _init() -> void:
	add_to_group(GROUP)
	add_to_group(&"fog_hideable")
	add_to_group(&"interactables")


func _ready() -> void:
	_def = def_for(kind)
	z_index = 10
	var table := LootDB.get_table(kind)
	var default_time := LootDB.getf("search_time", 1.2)
	search_time = LootDB.getf("drop_search_time", 0.4) if kind == &"drop" else (table.get_search_time(default_time) if table != null else default_time)
	search_hold = bool(LootDB.cfg().get_value(LootDB.SECTION, "search_hold", true))
	move_tolerance = LootDB.getf("search_move_tolerance", 10.0)
	_build()
	set_process(false)


func _build() -> void:
	var tex := get_texture(kind, state >= State.OPENED)
	var sc: float = float(_def.get("scale", 0.55))
	if tex != null and sc > 0.0:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		_sprite.texture = tex
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_sprite.scale = Vector2.ONE * sc
		_sprite.offset = Vector2(0.0, -tex.get_height() * 0.5 + float(_def.get("foot", 0.0)))
		add_child(_sprite)
	var block: Vector2 = _def.get("block", Vector2.ZERO)
	if block != Vector2.ZERO:
		var body := StaticBody2D.new()
		body.name = "Body"
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = block
		cs.shape = rect
		cs.position = Vector2(0.0, -block.y * 0.5)
		body.add_child(cs)
		add_child(body)
	_ring = Node2D.new()
	_ring.name = "SearchRing"
	_ring.z_as_relative = false
	_ring.z_index = 60
	_ring.position = Vector2(0.0, -get_visual_height() - 22.0)
	_ring.visible = false
	_ring.draw.connect(_draw_ring)
	add_child(_ring)
	_refresh_visual()


# --- Interface d'interaction ----------------------------------------------------

func get_display_name() -> String:
	return String(_def.get("name", "Conteneur"))


func can_interact() -> bool:
	return state != State.EMPTIED


func get_interact_label() -> String:
	match state:
		State.CLOSED, State.SEARCHING:
			return "Fouiller"
		State.OPENED:
			return "Ouvrir"
	return ""


## Icône du bouton d'action (chemin res://).
func get_interact_icon() -> String:
	return "search" if state <= State.SEARCHING else "open"


## Distance d'interaction supplémentaire (gros conteneurs).
func get_interact_reach() -> float:
	return float(_def.get("reach", 0.0))


func get_visual_height() -> float:
	if _sprite != null and _sprite.texture != null:
		return _sprite.texture.get_height() * _sprite.scale.y - float(_def.get("foot", 0.0)) * _sprite.scale.y
	return 24.0


## Appui sur « action » : lance la fouille, ou rouvre la fenêtre de butin.
func interact(player: Node) -> void:
	if NetHooks.active and not NetHooks.container_can_use(self):
		return  # Coop : le coéquipier fouille déjà ce conteneur.
	match state:
		State.CLOSED:
			start_search(player as Node2D)
		State.OPENED:
			_announce_open()


## Relâchement du bouton : interrompt la fouille si elle doit être maintenue.
func release_interact(_player: Node = null) -> void:
	if state == State.SEARCHING and search_hold:
		cancel_search()


func is_searching() -> bool:
	return state == State.SEARCHING


func get_search_ratio() -> float:
	return clampf(_search_t / maxf(search_time, 0.01), 0.0, 1.0)


func start_search(player: Node2D) -> void:
	if state != State.CLOSED:
		return
	state = State.SEARCHING
	_search_t = 0.0
	_searcher = player
	_search_origin = player.global_position if player != null else global_position
	if not EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.connect(_on_player_damaged)
	_ring.visible = true
	_ring.queue_redraw()
	set_process(true)
	_play(&"container_search")


func cancel_search() -> void:
	if state != State.SEARCHING:
		return
	_stop_search()
	state = State.CLOSED
	EventBus.search_progress.emit(self, 0.0)
	search_cancelled.emit(self)


func _stop_search() -> void:
	set_process(false)
	_ring.visible = false
	_searcher = null
	if EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.disconnect(_on_player_damaged)


func _on_player_damaged(_a: float, _hp: float, _max: float) -> void:
	cancel_search()


func _process(delta: float) -> void:
	if state != State.SEARCHING:
		set_process(false)
		return
	if _searcher != null and is_instance_valid(_searcher):
		var moved := _searcher.global_position.distance_to(_search_origin) > move_tolerance
		var hidden := _searcher.has_method("is_hidden") and bool(_searcher.call("is_hidden"))
		if moved or hidden:
			cancel_search()
			return
	_search_t += delta
	_ring.queue_redraw()
	EventBus.search_progress.emit(self, get_search_ratio())
	if _search_t >= search_time:
		_finish_search()


## Termine la fouille immédiatement (tests, debug).
func force_open() -> void:
	if state == State.CLOSED:
		state = State.SEARCHING
	if state == State.SEARCHING:
		_finish_search()


func _finish_search() -> void:
	_stop_search()
	if has_preset:
		entries = preset_entries.duplicate()
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = loot_seed
		var ctx := LootRoller.Context.make(difficulty, floor_index, room_type)
		entries = LootRoller.roll(LootDB.get_table(kind), rng, ctx)
	state = State.OPENED
	_play(&"container_open")
	if LootRoller.best_rarity(entries) >= ItemData.Rarity.EPIC:
		_play(&"rare_reveal")
	if entries.is_empty():
		_set_emptied()
	else:
		_refresh_visual()
		_save_state()
		_play_reveal()
	if NetHooks.active:
		NetHooks.container_opened(self)
	_announce_open()


## Effet d'ouverture : faisceau de la meilleure rareté + objets qui jaillissent (ChestReveal) et
## petit rebond du conteneur.
func _play_reveal() -> void:
	if not is_inside_tree() or not bool(LootDB.cfg().get_value(LootDB.SECTION, "reveal_enabled", true)):
		return
	add_child(ChestReveal.create(entries, get_visual_height()))
	if _sprite != null:
		var base := _sprite.scale
		var tw := _sprite.create_tween()
		tw.tween_property(_sprite, "scale", base * Vector2(1.12, 0.88), 0.06)
		tw.tween_property(_sprite, "scale", base, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _announce_open() -> void:
	opened.emit(self, entries)
	EventBus.container_opened.emit(self, entries)


# --- Butin ------------------------------------------------------------------------

## Prend `count` unités (toutes si -1) de l'entrée `index` vers `inv`.
## Renvoie le nombre réellement pris (0 si l'inventaire est plein).
func take(index: int, inv: Inventory, count: int = -1) -> int:
	if state != State.OPENED or index < 0 or index >= entries.size() or inv == null:
		return 0
	var e: Dictionary = entries[index]
	var it: ItemData = e["item"]
	var want := int(e["count"]) if count < 0 else mini(count, int(e["count"]))
	var got := inv.add_item(it, want)
	if got <= 0:
		return 0
	e["count"] = int(e["count"]) - got
	if int(e["count"]) <= 0:
		entries.remove_at(index)
	EventBus.item_picked_up.emit(it, got)
	if NetHooks.active:
		NetHooks.container_taken(self, it.id, got)
	if it.is_key():
		_play(&"key_pickup")
	elif it.id == &"silver_dollars" or it.id == &"gold_nugget":
		_play(&"coin_pickup")
	else:
		_play(&"item_pickup")
	if entries.is_empty():
		_set_emptied()
	else:
		_refresh_visual()
		_save_state()
	return got


## Prend tout ce qui rentre. Renvoie le nombre d'unités prises.
func take_all(inv: Inventory) -> int:
	var total := 0
	var i := 0
	while i < entries.size() and state == State.OPENED:
		var before := entries.size()
		var got := take(i, inv)
		total += got
		if entries.size() == before:
			i += 1
	return total


func is_emptied() -> bool:
	return state == State.EMPTIED


func _set_emptied() -> void:
	entries.clear()
	state = State.EMPTIED
	_refresh_visual()
	_save_state()
	emptied.emit(self)
	if kind == &"drop":
		queue_free()


## Coop : le coéquipier a ouvert ce conteneur. Même tirage (seed du conteneur, contenu imposé),
## sans fenêtre ni son.
func net_open_silently() -> void:
	if state >= State.OPENED:
		return
	if state == State.SEARCHING:
		_stop_search()
	if has_preset:
		entries = preset_entries.duplicate()
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = loot_seed
		entries = LootRoller.roll(LootDB.get_table(kind), rng, LootRoller.Context.make(difficulty, floor_index, room_type))
	state = State.OPENED
	if entries.is_empty():
		_set_emptied()
	else:
		_refresh_visual()
		_save_state()


## Coop : le coéquipier a pris `count` × `item_id`.
func net_remove(item_id: StringName, count: int) -> void:
	if state == State.CLOSED or state == State.SEARCHING:
		net_open_silently()
	if state != State.OPENED:
		return
	for i: int in entries.size():
		var it: ItemData = entries[i]["item"]
		if it != null and it.id == item_id:
			entries[i]["count"] = int(entries[i]["count"]) - count
			if int(entries[i]["count"]) <= 0:
				entries.remove_at(i)
			break
	if entries.is_empty():
		_set_emptied()
	else:
		_refresh_visual()
		_save_state()


## Restaure un état sauvegardé (changement d'étage).
func restore(saved: Dictionary) -> void:
	state = int(saved.get("state", State.CLOSED))
	entries.clear()
	for e: Dictionary in saved.get("entries", []):
		entries.append({"item": e["item"], "count": int(e["count"])})
	if state == State.SEARCHING:
		state = State.CLOSED
	if is_inside_tree():
		_refresh_visual()


func _save_state() -> void:
	if persist_key.is_empty():
		return
	var lm := _autoload(&"LootManager")
	if lm != null and lm.has_method("save_container_state"):
		lm.call("save_container_state", persist_key, state, entries)


# --- Visuel -----------------------------------------------------------------------

func _refresh_visual() -> void:
	if _sprite != null:
		var tex := get_texture(kind, state >= State.OPENED)
		if tex != null:
			_sprite.texture = tex
		_sprite.modulate = Color(0.78, 0.74, 0.78) if state == State.EMPTIED else Color.WHITE
	var best := LootRoller.best_rarity(entries) if state == State.OPENED else -1
	_glow_color = LootDB.rarity_color(best) if best >= LootDB.geti("glow_min_rarity", 2) else Color(0, 0, 0, 0)
	queue_redraw()


func get_glow_color() -> Color:
	return _glow_color


func _draw() -> void:
	var r: float = float(_def.get("shadow", 16.0))
	if r > 0.0:
		draw_set_transform(Vector2(r * 0.35, 3.0), 0.0, Vector2(1.0, 0.32))
		draw_circle(Vector2.ZERO, r, SHADOW_COLOR)
		draw_circle(Vector2.ZERO, r * 0.7, Color(SHADOW_COLOR, SHADOW_COLOR.a * 0.5))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _glow_color.a > 0.0:
		# Lueur de rareté au sol (Épique/Légendaire plus forte), dessinée une fois.
		var gw := maxf(r, 22.0) * 1.25
		draw_set_transform(Vector2(0.0, -2.0), 0.0, Vector2(1.0, 0.42))
		for k in 4:
			var f := 1.0 - k * 0.22
			draw_circle(Vector2.ZERO, gw * f, Color(_glow_color, 0.10 + k * 0.05))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if kind == &"drop":
		_draw_bag()


## Sacoche d'ennemi (dessin vectoriel, pas de SVG).
func _draw_bag() -> void:
	var c := Vector2(0, -12)
	var pts := PackedVector2Array([c + Vector2(-12, 10), c + Vector2(-14, -2), c + Vector2(-7, -10),
		c + Vector2(7, -10), c + Vector2(14, -2), c + Vector2(12, 10)])
	draw_colored_polygon(pts, Color(0.62, 0.42, 0.26))
	pts.append(pts[0])
	draw_polyline(pts, OUTLINE, 2.0, true)
	draw_line(c + Vector2(-7, -10), c + Vector2(-2, -15), OUTLINE, 2.0, true)
	draw_line(c + Vector2(7, -10), c + Vector2(2, -15), OUTLINE, 2.0, true)
	draw_rect(Rect2(c + Vector2(-8, -6), Vector2(16, 4)), Color(0.85, 0.66, 0.3))


## Anneau de fouille (maquette « Fouille », direction D) : disque encre, piste sombre, progression
## violet clair, loupe blanche au centre.
func _draw_ring() -> void:
	var rad := 18.0
	_ring.draw_circle(Vector2.ZERO, rad + 6.0, Color(MenuKit.NIGHT_DEEP, 0.85))
	_ring.draw_arc(Vector2.ZERO, rad, 0.0, TAU, 40, Color(1, 1, 1, 0.14), 5.0, true)
	var t := get_search_ratio()
	if t > 0.0:
		_ring.draw_arc(Vector2.ZERO, rad, -PI * 0.5, -PI * 0.5 + TAU * t, 40, MenuKit.VIOLET_LIGHT, 5.0, true)
	_ring.draw_arc(Vector2(-2, -2), 6.0, 0.0, TAU, 20, Color.WHITE, 2.4, true)
	_ring.draw_line(Vector2(2.5, 2.5), Vector2(8, 8), Color.WHITE, 3.0, true)


# --- Utilitaires ------------------------------------------------------------------

func _play(sfx: StringName) -> void:
	var am := _autoload(&"AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", sfx, global_position)


func _autoload(n: StringName) -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null(NodePath(String(n)))
