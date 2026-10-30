class_name AffixStatus
extends Node2D
## Statuts infligés par les affixes d'armes (phase 8) à une cible du groupe `damageable` :
##  - brûlure : dégâts par tics ([affixes] status_tick) pendant la durée ; un nouveau coup
##    rafraîchit la durée et garde le plus fort des deux débits ;
##  - gel : ralentissement. La cible l'applique elle-même si elle expose `affix_slow_mult`
##    (Enemy : vitesse × affix_slow_mult) ; un nouveau coup rafraîchit la durée et garde le plus fort.
## Un seul nœud enfant par cible (« AffixStatus »), créé au premier coup, qui ne tourne que tant
## qu'un statut est actif (set_physics_process(false) ensuite) ; marqueur au sol redessiné
## seulement quand l'état change.

const NODE_NAME := &"AffixStatus"

var burn_dps: float = 0.0
var burn_left: float = 0.0
var slow: float = 0.0
var slow_left: float = 0.0
var source: Node = null
var burn_color: Color = Color(1, 0.45, 0.15)
var freeze_color: Color = Color(0.45, 0.85, 1.0)
## Dégâts de brûlure infligés depuis la création (tests, debug).
var burn_dealt: float = 0.0
var _tick: float = 0.5
var _tick_left: float = 0.0
var _marker: bool = true
var _drawn_state: int = -1


static func of(target: Node, create: bool = true) -> AffixStatus:
	if target == null or not is_instance_valid(target):
		return null
	var s := target.get_node_or_null(NodePath(String(NODE_NAME))) as AffixStatus
	if s == null and create:
		s = AffixStatus.new()
		s.name = NODE_NAME
		target.add_child(s)
	return s


## Brûlure : `total` dégâts répartis sur `duration` s.
static func apply_burn(target: Node, total: float, duration: float, from: Node, color: Color = Color(1, 0.45, 0.15)) -> AffixStatus:
	if total <= 0.0 or duration <= 0.0 or not _alive(target):
		return null
	var s := of(target)
	s.burn_dps = maxf(s.burn_dps if s.burn_left > 0.0 else 0.0, total / duration)
	s.burn_left = maxf(s.burn_left, duration)
	s.source = from
	s.burn_color = color
	if s._tick_left <= 0.0:
		s._tick_left = s._tick
	s._wake()
	return s


## Gel : vitesse × (1 − strength) pendant `duration` s.
static func apply_slow(target: Node, strength: float, duration: float, color: Color = Color(0.45, 0.85, 1.0)) -> AffixStatus:
	if strength <= 0.0 or duration <= 0.0 or not _alive(target):
		return null
	var s := of(target)
	s.slow = clampf(maxf(s.slow if s.slow_left > 0.0 else 0.0, strength), 0.0, 0.95)
	s.slow_left = maxf(s.slow_left, duration)
	s.freeze_color = color
	s._apply_slow_mult()
	s._wake()
	return s


static func _alive(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return not target.has_method("is_alive") or bool(target.call("is_alive"))


func _init() -> void:
	_tick = maxf(Balance.get_float("affixes", "status_tick", 0.5), 0.05)
	_marker = bool(Balance.get_value("affixes", "status_marker", true))
	z_index = -1
	set_physics_process(false)


func is_burning() -> bool:
	return burn_left > 0.0


func is_slowed() -> bool:
	return slow_left > 0.0


func _wake() -> void:
	set_physics_process(true)
	_redraw_if_changed()


func _physics_process(delta: float) -> void:
	advance(delta)


## Avance le temps (appelé par _physics_process ; public pour les tests).
func advance(delta: float) -> void:
	var target := get_parent()
	if not _alive(target):
		_clear()
		return
	if burn_left > 0.0:
		var step := minf(delta, burn_left)
		burn_left -= step
		_tick_left -= step
		while _tick_left <= 0.0 and burn_dps > 0.0:
			_tick_left += _tick
			_deal(target, burn_dps * _tick)
			if not _alive(target):
				_clear()
				return
		if burn_left <= 0.0:
			burn_left = 0.0
			burn_dps = 0.0
			_tick_left = 0.0
	if slow_left > 0.0:
		slow_left -= delta
		if slow_left <= 0.0:
			slow_left = 0.0
			slow = 0.0
			_apply_slow_mult()
	if burn_left <= 0.0 and slow_left <= 0.0:
		set_physics_process(false)
	_redraw_if_changed()


func _deal(target: Node, amount: float) -> void:
	if amount <= 0.0 or not target.has_method("take_damage"):
		return
	burn_dealt += amount
	target.call("take_damage", amount, source if is_instance_valid(source) else null)


func _apply_slow_mult() -> void:
	var t := get_parent()
	if t != null and &"affix_slow_mult" in t:
		t.set(&"affix_slow_mult", 1.0 - slow if slow_left > 0.0 else 1.0)


func _clear() -> void:
	burn_left = 0.0
	burn_dps = 0.0
	slow_left = 0.0
	slow = 0.0
	_apply_slow_mult()
	set_physics_process(false)
	_redraw_if_changed()


func _redraw_if_changed() -> void:
	var st := (1 if burn_left > 0.0 else 0) | (2 if slow_left > 0.0 else 0)
	if st != _drawn_state:
		_drawn_state = st
		queue_redraw()


func _draw() -> void:
	if not _marker or _drawn_state <= 0:
		return
	# Anneau au sol (ellipse) à la couleur du statut : orange = brûlure, cyan = gel.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	if _drawn_state & 2:
		draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 28, Color(freeze_color, 0.85), 3.0, true)
	if _drawn_state & 1:
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 24, Color(burn_color, 0.9), 3.0, true)
