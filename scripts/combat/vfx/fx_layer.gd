class_name FxLayer
extends Node2D
## Couche de particules CPU « maison », poolée et dessinée en lot (un seul nœud, un seul
## _draw pour toutes les particules) :
##   - capacité fixe, tableaux Packed pré-alloués : aucune allocation par frame ;
##   - _process et redessin UNIQUEMENT tant qu'au moins une particule vit, puis arrêt
##     complet (set_process(false)) — aucun coût au repos ;
##   - quand la couche est pleine, la plus ancienne particule est recyclée.
## Coordonnées monde (le nœud reste à l'origine). Les particules « à hauteur » (douilles,
## débris, gouttes) simulent une hauteur z au-dessus du sol avec gravité et rebonds.

enum Kind { NONE, SPARK, DEBRIS, SMOKE, FLASH, RING, SHELL, TRACER, DUST, SCORCH, TEXT, FIRE, DROPLET, STREAK }

## Frottement (1/s) par type.
const DRAG: PackedFloat32Array = [0.0, 7.0, 1.5, 2.2, 0.0, 0.0, 1.0, 0.0, 4.0, 0.0, 2.5, 3.0, 2.0, 0.0]

var capacity: int = 0
var gravity: float = 900.0
var bounce: float = 0.38

var _kind: PackedByteArray = PackedByteArray()
var _pos: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()
var _z: PackedFloat32Array = PackedFloat32Array()
var _vz: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _max_life: PackedFloat32Array = PackedFloat32Array()
var _size: PackedFloat32Array = PackedFloat32Array()
var _size_end: PackedFloat32Array = PackedFloat32Array()
var _rot: PackedFloat32Array = PackedFloat32Array()
var _spin: PackedFloat32Array = PackedFloat32Array()
var _col: PackedColorArray = PackedColorArray()
var _text: PackedStringArray = PackedStringArray()
var _cursor: int = 0
var _alive: int = 0
var _font: Font = null


func setup(cap: int) -> void:
	capacity = maxi(cap, 8)
	_kind.resize(capacity)
	_kind.fill(Kind.NONE)
	_pos.resize(capacity)
	_vel.resize(capacity)
	_z.resize(capacity)
	_vz.resize(capacity)
	_life.resize(capacity)
	_life.fill(0.0)
	_max_life.resize(capacity)
	_size.resize(capacity)
	_size_end.resize(capacity)
	_rot.resize(capacity)
	_spin.resize(capacity)
	_col.resize(capacity)
	_text.resize(capacity)
	_cursor = 0
	_alive = 0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(false)


func get_alive_count() -> int:
	return _alive


## Ajoute une particule ; renvoie son index. `vel` = point d'arrivée pour TRACER.
func emit(kind: int, pos: Vector2, vel: Vector2, life: float, size: float, size_end: float,
		color: Color, z: float = 0.0, vz: float = 0.0, rot: float = 0.0, spin: float = 0.0) -> int:
	if capacity <= 0:
		setup(128)
	var i: int = _cursor
	_cursor = (_cursor + 1) % capacity
	if _life[i] <= 0.0:
		_alive += 1
	_kind[i] = kind
	_pos[i] = pos
	_vel[i] = vel
	_z[i] = z
	_vz[i] = vz
	_life[i] = maxf(life, 0.01)
	_max_life[i] = maxf(life, 0.01)
	_size[i] = size
	_size_end[i] = size_end
	_rot[i] = rot
	_spin[i] = spin
	_col[i] = color
	if not is_processing():
		set_process(true)
	return i


func emit_text(pos: Vector2, text: String, color: Color, size: float, life: float, rise: float) -> int:
	var i: int = emit(Kind.TEXT, pos, Vector2(randf_range(-12.0, 12.0), -rise), life, size, size, color)
	_text[i] = text
	return i


## Met à jour le texte d'une particule TEXT encore vivante (cumul de dégâts). false sinon.
func refresh_text(i: int, text: String, life: float, size: float) -> bool:
	if i < 0 or i >= capacity or _life[i] <= 0.0 or _kind[i] != Kind.TEXT:
		return false
	_text[i] = text
	_life[i] = maxf(_life[i], life * 0.8)
	_size[i] = size
	_size_end[i] = size
	return true


## Vide la couche (changement d'étage, tests).
func clear() -> void:
	_life.fill(0.0)
	_kind.fill(Kind.NONE)
	_alive = 0
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	var alive: int = 0
	for i: int in capacity:
		if _life[i] <= 0.0:
			continue
		var l: float = _life[i] - delta
		if l <= 0.0:
			_life[i] = 0.0
			_kind[i] = Kind.NONE
			continue
		_life[i] = l
		alive += 1
		var k: int = _kind[i]
		if k == Kind.TRACER or k == Kind.RING or k == Kind.FLASH or k == Kind.SCORCH:
			continue
		var v: Vector2 = _vel[i]
		var drag: float = DRAG[k]
		if drag > 0.0:
			v *= exp(-drag * delta)
		if k == Kind.SHELL or k == Kind.DEBRIS or k == Kind.DROPLET:
			var vz: float = _vz[i] - gravity * delta
			var z: float = _z[i] + vz * delta
			if z <= 0.0:
				z = 0.0
				if vz < -60.0:
					vz = -vz * bounce
					v *= 0.55
					_spin[i] *= 0.5
				else:
					vz = 0.0
					v *= exp(-10.0 * delta)
					_spin[i] *= exp(-10.0 * delta)
			_z[i] = z
			_vz[i] = vz
		_vel[i] = v
		_pos[i] += v * delta
		_rot[i] += _spin[i] * delta
	_alive = alive
	queue_redraw()
	if alive == 0:
		set_process(false)


func _draw() -> void:
	if _alive <= 0:
		return
	for i: int in capacity:
		if _life[i] <= 0.0:
			continue
		var t: float = 1.0 - _life[i] / _max_life[i]
		var c: Color = _col[i]
		var p: Vector2 = _pos[i]
		var s: float = lerpf(_size[i], _size_end[i], t)
		match _kind[i]:
			Kind.SPARK:
				var v: Vector2 = _vel[i]
				c.a *= 1.0 - t
				draw_line(p, p - v * 0.035, c, s, true)
			Kind.STREAK:
				c.a *= 1.0 - t * t
				draw_line(p, p - _vel[i] * 0.02, c, s, true)
			Kind.DEBRIS:
				c.a *= clampf(_life[i] / 0.35, 0.0, 1.0)
				draw_set_transform(p + Vector2(0.0, -_z[i]), _rot[i], Vector2.ONE)
				draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), c)
				draw_set_transform(Vector2.ZERO)
			Kind.SMOKE, Kind.DUST:
				c.a *= (1.0 - t) * minf(t * 6.0 + 0.3, 1.0)
				draw_circle(p, s, c, true, -1.0, true)
			Kind.FIRE:
				var fc: Color = c.lerp(Color(0.85, 0.25, 0.1, c.a), clampf(t * 1.4, 0.0, 1.0))
				fc.a *= 1.0 - t * t
				draw_circle(p, s, fc, true, -1.0, true)
			Kind.FLASH:
				c.a *= (1.0 - t) * (1.0 - t)
				draw_circle(p, s, c, true, -1.0, true)
			Kind.RING:
				c.a *= 1.0 - t
				draw_arc(p, s, 0.0, TAU, 40, c, maxf(_rot[i] * (1.0 - t), 1.0), true)
			Kind.SHELL:
				c.a *= clampf(_life[i] / 0.3, 0.0, 1.0)
				draw_set_transform(p + Vector2(0.0, -_z[i]), _rot[i], Vector2.ONE)
				draw_rect(Rect2(-s * 0.5 - 0.6, -s * 0.22 - 0.6, s + 1.2, s * 0.44 + 1.2), Color(0.15, 0.1, 0.05, c.a * 0.8))
				draw_rect(Rect2(-s * 0.5, -s * 0.22, s, s * 0.44), c)
				draw_set_transform(Vector2.ZERO)
			Kind.TRACER:
				var a: float = (1.0 - t)
				draw_line(p, _vel[i], Color(c, c.a * a * 0.35), s * 3.0, true)
				draw_line(p, _vel[i], Color(c.lightened(0.6), c.a * a), s, true)
			Kind.SCORCH:
				c.a *= clampf(_life[i] / 1.5, 0.0, 1.0)
				draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
				draw_circle(Vector2.ZERO, s, c, true, -1.0, true)
				draw_circle(Vector2.ZERO, s * 0.6, Color(c, c.a * 0.8), true, -1.0, true)
				draw_set_transform(Vector2.ZERO)
			Kind.DROPLET:
				c.a *= clampf(_life[i] / 0.25, 0.0, 1.0)
				draw_circle(p + Vector2(0.0, -_z[i]), s, c, true, -1.0, true)
			Kind.TEXT:
				if _font == null:
					_font = ThemeDB.fallback_font
				c.a *= clampf((1.0 - t) * 2.5, 0.0, 1.0)
				var fs: int = int(s * (1.0 + 0.35 * maxf(0.0, 1.0 - t * 6.0)))
				var outline := Color(0.07, 0.1, 0.18, c.a)
				draw_string_outline(_font, p + Vector2(-20.0, 0.0), _text[i], HORIZONTAL_ALIGNMENT_CENTER, 40.0, fs, 5, outline)
				draw_string(_font, p + Vector2(-20.0, 0.0), _text[i], HORIZONTAL_ALIGNMENT_CENTER, 40.0, fs, c)
