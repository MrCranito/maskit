class_name EnemyVisual
extends Node2D
## Composant visuel d'un ennemi (aucune logique de jeu).
## Enfant de l'ennemi ; l'origine de ce nœud = pieds de l'ennemi au sol.
##
## Choix technique pour la lueur des yeux : les fentes des masques sont
## dessinées dans les SVG avec un petit reflet blanc ; la lueur colorée
## (teintée par set_aura) est DESSINÉE EN CODE par-dessus le sprite, à des
## positions exprimées en coordonnées SVG par kind (clé "eyes" de KINDS).
## set_aura agit donc sur : la couleur des yeux lumineux, une très légère
## teinte du sprite (shader), le bord des éclats de dissolution à la mort.

signal death_finished

# --- Réglages visuels (pas de l'équilibrage) ---------------------------------

const SHADER := preload("res://assets/shaders/enemy_flash.gdshader")
const DEFAULT_KIND := &"masked_grunt"
## Couleur d'aura par défaut (yeux rouge orangé, comme le golem de la planche).
const DEFAULT_AURA := Color(1.0, 0.36, 0.14)
## Force de la teinte d'aura appliquée au sprite (0 = aucune).
const AURA_SPRITE_TINT := 0.12

const SHADOW_COLOR := Color(0.06, 0.08, 0.2, 0.42)
const SHADOW_FLATTEN := 0.36
const OUTLINE := Color(0.08, 0.06, 0.11)

const FLASH_DURATION := 0.13
const HIT_SQUASH := 0.08

const WALK_FREQ := 11.0
const WALK_BOB := 2.6
const WALK_TILT := 0.07
const BREATH_FREQ := 2.2
const BREATH_AMOUNT := 0.022
const FACING_TURN_SPEED := 14.0

const ALERT_DURATION := 0.9
const ALERT_POP_TIME := 0.16
const ALERT_HEIGHT := 22.0
## Décalage (px) du « ! » au-dessus de la tête : laisse la place à la barre de vie.
const ALERT_ABOVE_BAR := 30.0
const ALERT_FILL := Color(1.0, 0.78, 0.16)
const ALERT_FILL_LIGHT := Color(1.0, 0.95, 0.6)

const WINDUP_COLOR := Color(1.0, 0.18, 0.1)
const WINDUP_SHAKE := 1.6
const WINDUP_HOLD := 0.12

const DEATH_DURATION := 0.85
const DEATH_SINK := 10.0
const DEATH_CHUNKS := 12
const DEATH_SMOKE := 7
const DEATH_GRAVITY := 380.0

const EYE_GLOW_PULSE := 3.0
## Intervalle (s) de redessin de la lueur des yeux hors télégraphe (performance).
const EYE_REDRAW_INTERVAL := 0.066

## Données par kind. Coordonnées "eyes"/"feet" en pixels SVG.
##  path : sprite ; svg_size : taille du SVG ; feet : point d'ancrage au sol ;
##  scale : px monde par px SVG (≈ tailles écran de CONVENTIONS.md, zoom 1.3) ;
##  head : offset (monde) au-dessus de la tête pour barre de vie et « ! » ;
##  shadow : rayon de l'ombre au sol (monde) ; eyes : centres des yeux ;
##  eye_r : rayon d'un œil (px SVG) ; debris : couleurs des éclats de mort.
const KINDS: Dictionary = {
	&"golem": {
		"path": "res://assets/sprites/enemies/golem.svg",
		"svg_size": Vector2(170, 150), "feet": Vector2(85, 146), "scale": 0.69,
		"head": Vector2(0, -100), "shadow": 44.0,
		"eyes": [Vector2(78.5, 55), Vector2(91.5, 55)], "eye_r": 3.0,
		"debris": [Color(0.66, 0.58, 0.5), Color(0.45, 0.4, 0.42), Color(0.8, 0.7, 0.56)],
	},
	&"masked_grunt": {
		"path": "res://assets/sprites/enemies/masked_grunt.svg",
		"svg_size": Vector2(100, 120), "feet": Vector2(50, 116), "scale": 0.55,
		"head": Vector2(0, -66), "shadow": 20.0,
		"eyes": [Vector2(44, 37.3), Vector2(56, 37.3)], "eye_r": 2.6,
		"debris": [Color(0.2, 0.21, 0.3), Color(0.93, 0.9, 0.84), Color(0.35, 0.14, 0.22)],
	},
	&"masked_archer": {
		"path": "res://assets/sprites/enemies/masked_archer.svg",
		"svg_size": Vector2(100, 124), "feet": Vector2(50, 120), "scale": 0.5,
		"head": Vector2(0, -66), "shadow": 18.0,
		"eyes": [Vector2(46, 35), Vector2(54, 35)], "eye_r": 2.4,
		"debris": [Color(0.18, 0.22, 0.3), Color(0.93, 0.9, 0.84), Color(0.4, 0.3, 0.26)],
	},
	&"masked_brute": {
		"path": "res://assets/sprites/enemies/masked_brute.svg",
		"svg_size": Vector2(130, 136), "feet": Vector2(65, 132), "scale": 0.58,
		"head": Vector2(0, -80), "shadow": 30.0,
		"eyes": [Vector2(58, 39.3), Vector2(72, 39.3)], "eye_r": 2.8,
		"debris": [Color(0.22, 0.23, 0.32), Color(0.93, 0.9, 0.84), Color(0.5, 0.52, 0.62)],
	},
	# --- Monde 1 : Far West (hors-la-loi masqués) ---
	# "aura" (optionnel) : couleur d'aura par défaut du kind (remplacée par set_aura).
	&"outlaw_knife": {
		"path": "res://assets/sprites/enemies/outlaw_knife.svg",
		"svg_size": Vector2(100, 124), "feet": Vector2(50, 120), "scale": 0.45,
		"head": Vector2(0, -56), "shadow": 17.0,
		"eyes": [Vector2(44, 32.3), Vector2(56, 32.3)], "eye_r": 2.4,
		"aura": Color(1.0, 0.24, 0.16),
		"debris": [Color(0.48, 0.08, 0.13), Color(0.95, 0.92, 0.86), Color(0.47, 0.29, 0.17)],
	},
	&"gunslinger": {
		"path": "res://assets/sprites/enemies/gunslinger.svg",
		"svg_size": Vector2(110, 130), "feet": Vector2(55, 126), "scale": 0.45,
		"head": Vector2(0, -57), "shadow": 19.0,
		"eyes": [Vector2(49, 33.4), Vector2(61, 33.4)], "eye_r": 2.4,
		"aura": Color(1.0, 0.78, 0.22),
		"debris": [Color(0.43, 0.34, 0.27), Color(0.95, 0.92, 0.86), Color(0.17, 0.15, 0.22)],
	},
	&"shotgun_brute": {
		"path": "res://assets/sprites/enemies/shotgun_brute.svg",
		"svg_size": Vector2(130, 136), "feet": Vector2(65, 132), "scale": 0.54,
		"head": Vector2(0, -70), "shadow": 29.0,
		"eyes": [Vector2(57.5, 37.2), Vector2(72.5, 37.2)], "eye_r": 2.8,
		"aura": Color(1.0, 0.5, 0.14),
		"debris": [Color(0.54, 0.23, 0.15), Color(0.93, 0.9, 0.84), Color(0.89, 0.75, 0.48)],
	},
	&"sandstone_colossus": {
		"path": "res://assets/sprites/enemies/sandstone_colossus.svg",
		"svg_size": Vector2(180, 160), "feet": Vector2(90, 156), "scale": 0.6,
		"head": Vector2(0, -94), "shadow": 46.0,
		"eyes": [Vector2(82, 55.5), Vector2(98, 55.5)], "eye_r": 3.2,
		"aura": Color(1.0, 0.56, 0.16),
		"debris": [Color(0.82, 0.48, 0.29), Color(0.6, 0.27, 0.22), Color(0.94, 0.66, 0.42), Color(0.95, 0.92, 0.86)],
	},
}

## Télégraphe de cône (tir en éventail) et de zone (coup au sol).
const CONE_FILL := Color(1.0, 0.25, 0.1, 0.10)
const CONE_EDGE := Color(1.0, 0.35, 0.12)
const SLAM_DURATION := 0.45
const SLAM_COLOR := Color(1.0, 0.62, 0.22)

var kind: StringName = &""

var _data: Dictionary = {}
var _body: Node2D = null
var _sprite: Sprite2D = null
var _overlay: Node2D = null
var _fx: Node2D = null
var _mat: ShaderMaterial = null

var _aura: Color = DEFAULT_AURA
var _facing: float = 1.0
var _facing_target: float = 1.0
var _moving: bool = false
var _time: float = 0.0
var _flash_left: float = 0.0
var _alert_t: float = -1.0
var _windup_t: float = -1.0
var _windup_duration: float = 0.0
var _dying: bool = false
var _death_t: float = 0.0
var _particles: Array[Dictionary] = []
## Vrai si set_aura a été appelé explicitement (sinon aura par défaut du kind).
var _aura_custom: bool = false
## Télégraphes optionnels (0 = aucun) ; _aim en coordonnées non retournées.
var _area_radius: float = 0.0
var _cone_deg: float = 0.0
var _cone_len: float = 0.0
var _aim: Vector2 = Vector2.RIGHT
var _slam_t: float = -1.0
var _slam_radius: float = 0.0
var _eye_redraw_left: float = 0.0
## Frames de redessin restantes pour le calque d'effets (efface le dernier état).
var _fx_dirty_frames: int = 0


func _ready() -> void:
	_build()
	if kind == &"":
		setup(DEFAULT_KIND)


# --- API publique ------------------------------------------------------------

## Charge le sprite du kind, règle échelle et ombre. Réinitialise aussi tous les
## effets (utilisable pour faire « revivre » le visuel après play_death).
func setup(new_kind: StringName) -> void:
	_build()
	if not KINDS.has(new_kind):
		push_warning("EnemyVisual : kind inconnu « %s », repli sur %s" % [new_kind, DEFAULT_KIND])
		new_kind = DEFAULT_KIND
	kind = new_kind
	_data = KINDS[kind]
	var tex: Texture2D = load(_data["path"]) as Texture2D
	_sprite.texture = tex
	var svg_size: Vector2 = _data["svg_size"]
	var feet: Vector2 = _data["feet"]
	# Facteur texture/SVG (dépend de svg/scale à l'import).
	var tex_per_svg: float = (tex.get_size().x / svg_size.x) if tex != null else 1.0
	_sprite.centered = false
	_sprite.offset = -feet * tex_per_svg
	var s: float = float(_data["scale"]) / tex_per_svg
	_sprite.scale = Vector2(s, s)
	# Réinitialisation des effets.
	_dying = false
	_death_t = 0.0
	_particles.clear()
	_flash_left = 0.0
	_alert_t = -1.0
	_windup_t = -1.0
	_body.position = Vector2.ZERO
	_body.rotation = 0.0
	_sprite.modulate = Color.WHITE
	_mat.set_shader_parameter("dissolve", 0.0)
	_mat.set_shader_parameter("flash", 0.0)
	_mat.set_shader_parameter("windup", 0.0)
	_slam_t = -1.0
	_area_radius = 0.0
	_cone_deg = 0.0
	_cone_len = 0.0
	var aura: Color = _aura if _aura_custom else (_data.get("aura", DEFAULT_AURA) as Color)
	_apply_aura(aura)
	queue_redraw()


func set_facing(dir: Vector2) -> void:
	if absf(dir.x) > 0.05:
		_facing_target = signf(dir.x)


func set_moving(moving: bool) -> void:
	_moving = moving


func flash_hit() -> void:
	if _dying:
		return
	_flash_left = FLASH_DURATION


func play_alert() -> void:
	if _dying:
		return
	_alert_t = 0.0


## Télégraphe : lueur rouge qui monte sur `duration` secondes + tremblement.
func play_attack_windup(duration: float) -> void:
	if _dying:
		return
	_windup_duration = maxf(duration, 0.05)
	_windup_t = 0.0


## Dissolution en éclats + fumée, puis `death_finished` (durée DEATH_DURATION).
func play_death() -> void:
	if _dying:
		return
	_dying = true
	_death_t = 0.0
	_alert_t = -1.0
	_windup_t = -1.0
	_mat.set_shader_parameter("windup", 0.0)
	_spawn_death_particles()


## Teinte de masque par royaume : yeux lumineux, légère teinte du sprite,
## bord de dissolution.
func set_aura(color: Color) -> void:
	_aura_custom = true
	_apply_aura(color)


## Télégraphe de coup de zone : anneau au sol de `radius` (monde) pendant le windup.
func set_attack_area(radius: float) -> void:
	_area_radius = maxf(radius, 0.0)


## Télégraphe de tir en éventail : cône d'ouverture `spread_deg` et de longueur `length`.
func set_attack_cone(spread_deg: float, length: float) -> void:
	_cone_deg = maxf(spread_deg, 0.0)
	_cone_len = maxf(length, 0.0)


## Direction de visée (pour orienter le cône de télégraphe).
func set_aim_direction(dir: Vector2) -> void:
	if dir.length_squared() > 0.0001:
		_aim = dir.normalized()


## Onde de choc au sol (coup de zone) : anneau qui s'étend jusqu'à `radius`.
func play_ground_slam(radius: float) -> void:
	if _dying:
		return
	_slam_radius = maxf(radius, 1.0)
	_slam_t = 0.0


func _apply_aura(color: Color) -> void:
	_aura = color
	if _mat != null:
		_mat.set_shader_parameter("aura_tint", Color(color.r, color.g, color.b, AURA_SPRITE_TINT))
		_mat.set_shader_parameter("dissolve_edge", color.lerp(Color(1, 0.9, 0.7), 0.35))
	if _overlay != null:
		_overlay.queue_redraw()


## Point (local, relatif aux pieds) juste au-dessus de la tête.
func get_head_offset() -> Vector2:
	if _data.is_empty():
		return Vector2(0, -70)
	return _data["head"]


func is_dying() -> bool:
	return _dying


# --- Construction ------------------------------------------------------------

func _build() -> void:
	if _body != null:
		return
	_body = Node2D.new()
	_body.name = "Body"
	add_child(_body)
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_sprite.material = _mat
	_body.add_child(_sprite)
	# Overlay en coordonnées texture (enfant du sprite) : yeux lumineux.
	_overlay = Node2D.new()
	_overlay.name = "EyesGlow"
	_sprite.add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	# Effets non retournés : « ! », éclats, fumée.
	_fx = Node2D.new()
	_fx.name = "Fx"
	_fx.z_index = 10
	add_child(_fx)
	_fx.draw.connect(_draw_fx)


# --- Animation ---------------------------------------------------------------

func _process(delta: float) -> void:
	if _body == null:
		return
	# Caché (brouillard) et sans effet en cours : rien à animer ni à redessiner.
	if not _dying and not is_visible_in_tree():
		if _windup_t >= 0.0 or _alert_t >= 0.0 or _slam_t >= 0.0 or _flash_left > 0.0:
			_windup_t = -1.0
			_alert_t = -1.0
			_slam_t = -1.0
			_flash_left = 0.0
			_mat.set_shader_parameter("windup", 0.0)
			_mat.set_shader_parameter("flash", 0.0)
		return
	_time += delta
	_facing = move_toward(_facing, _facing_target, delta * FACING_TURN_SPEED)

	var bob := 0.0
	var tilt := 0.0
	var breath := sin(_time * BREATH_FREQ) * BREATH_AMOUNT
	if _moving and not _dying:
		var ph := _time * WALK_FREQ
		bob = -absf(sin(ph)) * WALK_BOB
		tilt = sin(ph) * WALK_TILT
		breath *= 0.3

	var squash := 0.0
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		squash = (_flash_left / FLASH_DURATION) * HIT_SQUASH
		_mat.set_shader_parameter("flash", clampf(_flash_left / FLASH_DURATION, 0.0, 1.0) * 0.85)

	var shake := Vector2.ZERO
	if _windup_t >= 0.0:
		_windup_t += delta
		var w := clampf(_windup_t / _windup_duration, 0.0, 1.0)
		if _windup_t > _windup_duration + WINDUP_HOLD:
			_windup_t = -1.0
			w = 0.0
		_mat.set_shader_parameter("windup", w)
		shake = Vector2(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5)) * WINDUP_SHAKE * w
		breath += w * 0.03
		_fx_dirty_frames = 2

	if _alert_t >= 0.0:
		_alert_t += delta
		if _alert_t > ALERT_DURATION:
			_alert_t = -1.0

	if _slam_t >= 0.0:
		_slam_t += delta
		if _slam_t > SLAM_DURATION:
			_slam_t = -1.0

	var sx := (1.0 + squash - breath * 0.5) * (_facing if absf(_facing) > 0.05 else 0.05)
	var sy := 1.0 - squash + breath
	if _dying:
		_death_t += delta
		var d := clampf(_death_t / DEATH_DURATION, 0.0, 1.0)
		_mat.set_shader_parameter("dissolve", d)
		_body.position = Vector2(0, DEATH_SINK * d * d)
		_body.rotation = 0.0
		_body.scale = Vector2(sx * (1.0 + 0.08 * d), sy * (1.0 - 0.12 * d))
		_update_particles(delta)
		if _death_t >= DEATH_DURATION:
			_dying = false
			_death_t = 0.0
			_sprite.modulate.a = 0.0
			_particles.clear()
			_fx.queue_redraw()
			queue_redraw()
			death_finished.emit()
			return
		queue_redraw()
	else:
		_body.position = Vector2(0, bob) + shake
		_body.rotation = tilt
		_body.scale = Vector2(sx, sy)

	# Lueur des yeux : pulsation lente, redessinée ~15 fois/s (pas à chaque frame).
	_eye_redraw_left -= delta
	if _eye_redraw_left <= 0.0 or _windup_t >= 0.0:
		_eye_redraw_left = EYE_REDRAW_INTERVAL
		_overlay.queue_redraw()
	# Effets (« ! », télégraphes, éclats) : redessin seulement s'il y a quelque chose à animer.
	if _alert_t >= 0.0 or _windup_t >= 0.0 or _slam_t >= 0.0 or not _particles.is_empty():
		_fx_dirty_frames = 2
	if _fx_dirty_frames > 0:
		_fx_dirty_frames -= 1
		_fx.queue_redraw()


# --- Dessin ------------------------------------------------------------------

func _draw() -> void:
	if _data.is_empty():
		return
	var r: float = _data["shadow"]
	var a := 1.0
	if _dying:
		a = 1.0 - clampf(_death_t / DEATH_DURATION, 0.0, 1.0)
	elif _sprite != null and _sprite.modulate.a <= 0.0:
		a = 0.0
	if a <= 0.0:
		return
	draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, SHADOW_FLATTEN))
	draw_circle(Vector2.ZERO, r, Color(SHADOW_COLOR, SHADOW_COLOR.a * a))
	draw_circle(Vector2.ZERO, r * 0.7, Color(SHADOW_COLOR, SHADOW_COLOR.a * 0.6 * a))
	draw_set_transform(Vector2.ZERO)


## Yeux lumineux teintés par l'aura (coordonnées texture du sprite).
func _draw_overlay() -> void:
	if _data.is_empty() or _sprite.texture == null or _sprite.modulate.a <= 0.0:
		return
	var svg_size: Vector2 = _data["svg_size"]
	var k: float = _sprite.texture.get_size().x / svg_size.x
	var off := _sprite.offset
	var r: float = float(_data["eye_r"]) * k
	var fade := 1.0
	if _dying:
		fade = 1.0 - clampf(_death_t / (DEATH_DURATION * 0.5), 0.0, 1.0)
	var pulse := 0.85 + 0.15 * sin(_time * EYE_GLOW_PULSE)
	var col := _aura
	if _windup_t >= 0.0:
		var w := clampf(_windup_t / _windup_duration, 0.0, 1.0)
		col = _aura.lerp(WINDUP_COLOR, w)
		pulse += w * 0.6
	for e: Vector2 in _data["eyes"]:
		var p := off + e * k
		_overlay.draw_circle(p, r * 2.6 * pulse, Color(col, 0.16 * fade))
		_overlay.draw_circle(p, r * 1.6, Color(col, 0.45 * fade))
		_overlay.draw_circle(p, r * 0.95, Color(col.lerp(Color.WHITE, 0.25), 0.95 * fade))
		_overlay.draw_circle(p, r * 0.42, Color(1.0, 0.97, 0.88, fade))


func _draw_fx() -> void:
	if _alert_t >= 0.0:
		_draw_alert()
	if _windup_t >= 0.0 and _windup_duration > 0.0:
		_draw_special_telegraph(clampf(_windup_t / _windup_duration, 0.0, 1.0))
	if _slam_t >= 0.0:
		_draw_slam()
	if _windup_t >= 0.0 and _windup_duration > 0.0:
		var w := clampf(_windup_t / _windup_duration, 0.0, 1.0)
		var r: float = float(_data.get("shadow", 20.0)) * (1.0 + 0.25 * w)
		_fx.draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, SHADOW_FLATTEN))
		_fx.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(WINDUP_COLOR, 0.25 + 0.55 * w), 3.0 + 3.0 * w, true)
		_fx.draw_set_transform(Vector2.ZERO)
	for p: Dictionary in _particles:
		var life: float = p["life"]
		var age: float = p["age"]
		if age < 0.0:
			continue
		var t := clampf(age / life, 0.0, 1.0)
		var pos: Vector2 = p["pos"]
		if p["smoke"]:
			var rr: float = float(p["size"]) * (0.6 + t * 1.2)
			_fx.draw_circle(pos, rr, Color(0.08, 0.09, 0.18, 0.55 * (1.0 - t)))
			_fx.draw_circle(pos + Vector2(-rr * 0.25, -rr * 0.25), rr * 0.55, Color(0.2, 0.2, 0.32, 0.35 * (1.0 - t)))
		else:
			var sz: float = float(p["size"]) * (1.0 - 0.4 * t)
			var rot: float = p["rot"]
			var pts := PackedVector2Array()
			for i: int in 5:
				var ang := rot + TAU * float(i) / 5.0
				var rad := sz * (0.75 + 0.25 * float((i * 7) % 3) / 2.0)
				pts.append(pos + Vector2(cos(ang), sin(ang)) * rad)
			var c: Color = p["color"]
			c.a = 1.0 - t * t
			_fx.draw_colored_polygon(pts, c)
			var closed := pts.duplicate()
			closed.append(pts[0])
			_fx.draw_polyline(closed, Color(OUTLINE, c.a), 1.6, true)
			_fx.draw_line(pts[0], pts[1], Color(_aura.lerp(Color.WHITE, 0.5), c.a * 0.8), 1.2, true)


## Cône d'éventail ou anneau de zone qui se remplit pendant le télégraphe.
func _draw_special_telegraph(w: float) -> void:
	if _cone_deg > 0.0 and _cone_len > 0.0:
		var half := deg_to_rad(_cone_deg) * 0.5
		var a0 := _aim.angle()
		var steps := 18
		var pts := PackedVector2Array([Vector2.ZERO])
		var fill_pts := PackedVector2Array([Vector2.ZERO])
		for i: int in steps + 1:
			var ang := a0 - half + 2.0 * half * float(i) / float(steps)
			pts.append(Vector2.from_angle(ang) * _cone_len)
			fill_pts.append(Vector2.from_angle(ang) * _cone_len * w)
		_fx.draw_colored_polygon(pts, Color(CONE_FILL, CONE_FILL.a * (0.6 + 0.6 * w)))
		_fx.draw_colored_polygon(fill_pts, Color(CONE_EDGE, 0.18 + 0.2 * w))
		var edge := pts.duplicate()
		edge.append(Vector2.ZERO)
		_fx.draw_polyline(edge, Color(CONE_EDGE, 0.45 + 0.5 * w), 2.0 + 1.5 * w, true)
	if _area_radius > 0.0:
		_fx.draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, SHADOW_FLATTEN * 1.4))
		_fx.draw_circle(Vector2.ZERO, _area_radius, Color(CONE_FILL, CONE_FILL.a * (0.6 + 0.8 * w)))
		_fx.draw_circle(Vector2.ZERO, _area_radius * w, Color(CONE_EDGE, 0.16 + 0.22 * w))
		_fx.draw_arc(Vector2.ZERO, _area_radius, 0.0, TAU, 56, Color(CONE_EDGE, 0.5 + 0.5 * w), 2.5 + 2.0 * w, true)
		_fx.draw_set_transform(Vector2.ZERO)


func _draw_slam() -> void:
	var t := clampf(_slam_t / SLAM_DURATION, 0.0, 1.0)
	var r := _slam_radius * ease(t, 0.35)
	var a := 1.0 - t
	_fx.draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, SHADOW_FLATTEN * 1.4))
	_fx.draw_circle(Vector2.ZERO, r, Color(SLAM_COLOR, 0.22 * a))
	_fx.draw_arc(Vector2.ZERO, r, 0.0, TAU, 56, Color(SLAM_COLOR.lerp(Color.WHITE, 0.4), 0.9 * a), 6.0 * a + 1.5, true)
	_fx.draw_arc(Vector2.ZERO, r * 0.75, 0.0, TAU, 48, Color(SLAM_COLOR, 0.5 * a), 3.0, true)
	_fx.draw_set_transform(Vector2.ZERO)


func _draw_alert() -> void:
	var t := _alert_t
	var pop := 1.0
	if t < ALERT_POP_TIME:
		pop = ease(t / ALERT_POP_TIME, 0.4) * 1.35
	elif t < ALERT_POP_TIME * 2.0:
		pop = lerpf(1.35, 1.0, (t - ALERT_POP_TIME) / ALERT_POP_TIME)
	var a := 1.0
	var fade_start := ALERT_DURATION * 0.65
	if t > fade_start:
		a = 1.0 - (t - fade_start) / (ALERT_DURATION - fade_start)
	# Au-dessus de la barre de vie, à la place de la jauge de reconnaissance (qui s'efface).
	var base := get_head_offset() + Vector2(0, -ALERT_ABOVE_BAR - ALERT_HEIGHT * 0.5 - (1.0 - a) * 6.0)
	_fx.draw_set_transform(base, 0.0, Vector2(pop, pop))
	# Bâton biseauté.
	var bar := PackedVector2Array([Vector2(-5.5, -14), Vector2(5.5, -14), Vector2(3, 4), Vector2(-3, 4)])
	var outline := Color(OUTLINE, a)
	var big := PackedVector2Array([Vector2(-8, -16.5), Vector2(8, -16.5), Vector2(5, 6.5), Vector2(-5, 6.5)])
	_fx.draw_colored_polygon(big, outline)
	_fx.draw_circle(Vector2(0, 11), 6.2, outline)
	_fx.draw_colored_polygon(bar, Color(ALERT_FILL, a))
	_fx.draw_circle(Vector2(0, 11), 3.8, Color(ALERT_FILL, a))
	# Reflet chaud du haut.
	_fx.draw_colored_polygon(PackedVector2Array([Vector2(-4, -12.5), Vector2(-0.5, -12.5), Vector2(-1.5, -3), Vector2(-3.2, -3)]), Color(ALERT_FILL_LIGHT, a))
	_fx.draw_set_transform(Vector2.ZERO)


# --- Particules de mort ------------------------------------------------------

func _spawn_death_particles() -> void:
	_particles.clear()
	var h: float = absf(get_head_offset().y)
	var w: float = float(_data.get("shadow", 20.0))
	var colors: Array = _data.get("debris", [Color.GRAY])
	for i: int in DEATH_CHUNKS:
		var start := Vector2(randf_range(-w * 0.6, w * 0.6), -randf_range(h * 0.15, h * 0.8))
		_particles.append({
			"smoke": false,
			"pos": start,
			"vel": Vector2(randf_range(-90.0, 90.0), randf_range(-160.0, -40.0)),
			"size": randf_range(3.5, 6.5) * (h / 70.0),
			"rot": randf() * TAU,
			"spin": randf_range(-8.0, 8.0),
			"color": colors[i % colors.size()],
			"age": -randf_range(0.0, DEATH_DURATION * 0.4),
			"life": randf_range(0.45, 0.6),
			"floor": randf_range(-2.0, 6.0),
		})
	for i: int in DEATH_SMOKE:
		_particles.append({
			"smoke": true,
			"pos": Vector2(randf_range(-w * 0.7, w * 0.7), -randf_range(0.0, h * 0.6)),
			"vel": Vector2(randf_range(-15.0, 15.0), randf_range(-40.0, -15.0)),
			"size": randf_range(6.0, 10.0) * (h / 70.0),
			"rot": 0.0, "spin": 0.0, "color": Color.BLACK,
			"age": -randf_range(0.0, DEATH_DURATION * 0.3),
			"life": randf_range(0.5, 0.6),
			"floor": 0.0,
		})


func _update_particles(delta: float) -> void:
	for p: Dictionary in _particles:
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) < 0.0:
			continue
		var vel: Vector2 = p["vel"]
		var pos: Vector2 = p["pos"]
		if not p["smoke"]:
			vel.y += DEATH_GRAVITY * delta
			pos += vel * delta
			if pos.y > float(p["floor"]):
				pos.y = float(p["floor"])
				vel = Vector2(vel.x * 0.5, -vel.y * 0.25)
			p["rot"] = float(p["rot"]) + float(p["spin"]) * delta
		else:
			pos += vel * delta
		p["vel"] = vel
		p["pos"] = pos
