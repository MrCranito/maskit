class_name EnemyVisual
extends Node2D
## Composant visuel d'un ennemi (aucune logique de jeu).
## Enfant de l'ennemi ; l'origine de ce nœud = pieds de l'ennemi au sol.
##
## Deux modes :
##  - « planches » (Far West, art/blender/build_enemies.py) : AnimatedSprite2D piloté à la main
##    (idle / run / attack / hit / death × 8 directions, cf. EnemyArt) ; la dernière image de la
##    mort est le cadavre au sol ;
##  - « sprite » (autres biomes, SVG/PNG de KINDS ou BiomeRegistry) : sprite unique animé en code
##    (balancement, écrasement) ; la mort fait basculer le corps au sol (plus de dissolution).
##
## Télégraphes (calque _fx, redessiné seulement quand quelque chose s'anime) :
##  « ! » d'alerte, cri (bulle de texte), lueur rouge d'élan, cône d'éventail, anneau de zone,
##  ligne de visée rouge (tireur), cercle au sol (dynamite), éclair de bouche, étoiles d'étourdissement.

signal death_finished

# --- Réglages visuels (pas de l'équilibrage) ---------------------------------

const SHADER := preload("res://assets/shaders/enemy_flash.gdshader")
const DEFAULT_KIND := &"masked_grunt"
const DEFAULT_AURA := Color(1.0, 0.36, 0.14)
const AURA_SPRITE_TINT := 0.12

const SHADOW_COLOR := Color(0.06, 0.08, 0.2, 0.42)
const SHADOW_FLATTEN := 0.36
## Ombre portée longue (lumière rasante du couchant, vers la droite-bas comme le décor).
const CAST_SHADOW_COLOR := Color(0.06, 0.08, 0.22, 0.22)
const CAST_SHADOW_OFFSET := Vector2(0.55, 0.12)
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
const ALERT_ABOVE_BAR := 26.0
const ALERT_FILL := Color(1.0, 0.78, 0.16)
const ALERT_FILL_LIGHT := Color(1.0, 0.95, 0.6)

const SHOUT_DURATION := 1.1
const SHOUT_BG := Color(0.07, 0.10, 0.18, 0.88)
const SHOUT_TEXT := Color(1.0, 0.95, 0.85)

const WINDUP_COLOR := Color(1.0, 0.18, 0.1)
const WINDUP_SHAKE := 1.6
const WINDUP_HOLD := 0.12

const DEATH_DURATION := 0.55
const STUN_COLOR := Color(1.0, 0.9, 0.35)
const MUZZLE_DURATION := 0.07
const AIM_LINE_COLOR := Color(1.0, 0.12, 0.08)
const MARKER_COLOR := Color(1.0, 0.3, 0.12)

const EYE_GLOW_PULSE := 3.0
const EYE_REDRAW_INTERVAL := 0.066

## Données par kind (mode sprite). Coordonnées "eyes"/"feet" en pixels SVG.
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
	# --- Monde 1 : Far West. Repli SVG si les planches 3D (EnemyArt) sont absentes. ---
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
	&"rifleman": {
		"path": "res://assets/sprites/enemies/gunslinger.svg",
		"svg_size": Vector2(110, 130), "feet": Vector2(55, 126), "scale": 0.45,
		"head": Vector2(0, -57), "shadow": 19.0,
		"eyes": [Vector2(49, 33.4), Vector2(61, 33.4)], "eye_r": 2.4,
		"aura": Color(1.0, 0.3, 0.2),
		"debris": [Color(0.6, 0.5, 0.36), Color(0.95, 0.92, 0.86), Color(0.17, 0.15, 0.22)],
	},
	&"dynamiter": {
		"path": "res://assets/sprites/enemies/outlaw_knife.svg",
		"svg_size": Vector2(100, 124), "feet": Vector2(50, 120), "scale": 0.45,
		"head": Vector2(0, -56), "shadow": 17.0,
		"eyes": [Vector2(44, 32.3), Vector2(56, 32.3)], "eye_r": 2.4,
		"aura": Color(1.0, 0.45, 0.1),
		"debris": [Color(0.8, 0.16, 0.12), Color(0.95, 0.92, 0.86), Color(0.3, 0.36, 0.45)],
	},
	&"gang_boss": {
		"path": "res://assets/sprites/enemies/shotgun_brute.svg",
		"svg_size": Vector2(130, 136), "feet": Vector2(65, 132), "scale": 0.6,
		"head": Vector2(0, -78), "shadow": 30.0,
		"eyes": [Vector2(57.5, 37.2), Vector2(72.5, 37.2)], "eye_r": 2.8,
		"aura": Color(1.0, 0.75, 0.2),
		"debris": [Color(0.75, 0.12, 0.1), Color(0.1, 0.08, 0.08), Color(0.85, 0.66, 0.25)],
	},
}

const CONE_FILL := Color(1.0, 0.25, 0.1, 0.10)
const CONE_EDGE := Color(1.0, 0.35, 0.12)
const SLAM_DURATION := 0.45
const SLAM_COLOR := Color(1.0, 0.62, 0.22)

## Shader des planches : flash blanc, teinte rouge d'élan, assombrissement (indépendant des UV,
## donc compatible avec l'atlas rogné).
const SHEET_SHADER_CODE := """
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float windup : hint_range(0.0, 1.0) = 0.0;
uniform vec4 windup_color : source_color = vec4(1.0, 0.18, 0.1, 1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	float k = windup * 0.42;
	c.rgb = mix(c.rgb, c.rgb * windup_color.rgb * 1.5 + windup_color.rgb * 0.12, k);
	c.rgb += windup_color.rgb * k * (0.15 + lum * 0.4);
	c.rgb = mix(c.rgb, vec3(1.0), flash);
	COLOR = c * COLOR;
}
"""
static var _sheet_shader: Shader = null

var kind: StringName = &""
## Vrai si le kind utilise les planches 3D (EnemyArt).
var uses_sheet: bool = false

var _data: Dictionary = {}
var _body: Node2D = null
var _sprite: Sprite2D = null
var _anim: AnimatedSprite2D = null
var _overlay: Node2D = null
var _fx: Node2D = null
var _mat: ShaderMaterial = null
var _sheet_mat: ShaderMaterial = null

var _aura: Color = DEFAULT_AURA
var _facing: float = 1.0
var _facing_target: float = 1.0
var _facing_vec: Vector2 = Vector2.DOWN
var _dir: int = 2
var _moving: bool = false
var _time: float = 0.0
var _flash_left: float = 0.0
var _alert_t: float = -1.0
var _windup_t: float = -1.0
var _windup_duration: float = 0.0
var _dying: bool = false
var _dead: bool = false
var _death_t: float = 0.0
var _death_side: float = 1.0
var _aura_custom: bool = false
var _area_radius: float = 0.0
var _cone_deg: float = 0.0
var _cone_len: float = 0.0
var _aim: Vector2 = Vector2.RIGHT
var _slam_t: float = -1.0
var _slam_radius: float = 0.0
var _eye_redraw_left: float = 0.0
var _fx_dirty_frames: int = 0
# Planches : animation courante pilotée à la main.
var _anim_name: String = "idle"
var _anim_t: float = 0.0
var _anim_frames: int = 1
var _anim_fps: float = 8.0
var _anim_loop: bool = true
var _anim_hold: int = -1
var _anim_lock: float = 0.0
var _shown_key: String = ""
var _shown_frame: int = -1
var _speed_scale: float = 1.0
# Télégraphes / effets supplémentaires.
var _shout_text: String = ""
var _shout_t: float = -1.0
var _aim_line_t: float = -1.0
var _aim_line_total: float = 0.0
var _aim_line_len: float = 0.0
var _aim_locked: bool = false
var _marker_pos: Vector2 = Vector2.ZERO
var _marker_r: float = 0.0
var _marker_t: float = -1.0
var _marker_total: float = 0.0
var _muzzle_t: float = -1.0
var _muzzle_dir: Vector2 = Vector2.RIGHT
var _muzzle_big: bool = false
var _stun_t: float = -1.0
var _kick: Vector2 = Vector2.ZERO
var _elite: bool = false
var _font: Font = null
var _stun_total: float = 0.5
var _throw_anim: bool = false


func _ready() -> void:
	_build()
	if kind == &"":
		setup(DEFAULT_KIND)


# --- API publique ------------------------------------------------------------

## Charge le sprite/les planches du kind, règle échelle et ombre. Réinitialise tous les effets
## (utilisable pour faire « revivre » le visuel après play_death).
func setup(new_kind: StringName) -> void:
	_build()
	var extra: Dictionary = BiomeRegistry.extra_enemy_kinds()
	var sheet := EnemyArt.entry(new_kind)
	uses_sheet = not sheet.is_empty()
	if not uses_sheet and not KINDS.has(new_kind) and not extra.has(new_kind):
		push_warning("EnemyVisual : kind inconnu « %s », repli sur %s" % [new_kind, DEFAULT_KIND])
		new_kind = DEFAULT_KIND
	kind = new_kind
	_reset_effects()
	if uses_sheet:
		_setup_sheet(sheet)
	else:
		_setup_sprite(KINDS[kind] if KINDS.has(kind) else extra[kind])
	queue_redraw()


func _setup_sprite(d: Dictionary) -> void:
	_data = d
	_sprite.visible = true
	_anim.visible = false
	var tex: Texture2D = load(_data["path"]) as Texture2D
	_sprite.texture = tex
	var svg_size: Vector2 = _data["svg_size"]
	var feet: Vector2 = _data["feet"]
	var tex_per_svg: float = (tex.get_size().x / svg_size.x) if tex != null else 1.0
	_sprite.centered = false
	_sprite.offset = -feet * tex_per_svg
	var s: float = float(_data["scale"]) / tex_per_svg
	_sprite.scale = Vector2(s, s)
	_sprite.modulate = Color.WHITE
	_mat.set_shader_parameter("dissolve", 0.0)
	_mat.set_shader_parameter("flash", 0.0)
	_mat.set_shader_parameter("windup", 0.0)
	var aura: Color = _aura if _aura_custom else (_data.get("aura", DEFAULT_AURA) as Color)
	_apply_aura(aura)


func _setup_sheet(e: Dictionary) -> void:
	var meta: Dictionary = e["meta"]
	var sc: float = float(e["scale"])
	var feet: Vector2 = e["feet"]
	var fs: Vector2 = e["frame"]
	var head_y: float = -EnemyArt.head_height(kind)
	_data = {
		"head": Vector2(0, head_y - 4.0),
		"shadow": clampf(float(meta.get("height_px", 100)) * sc * 0.26, 14.0, 34.0),
		"eyes": [], "eye_r": 0.0,
		"debris": [Color(0.5, 0.3, 0.2)],
	}
	_sprite.visible = false
	_anim.visible = true
	_anim.sprite_frames = e["frames"]
	_anim.centered = true
	_anim.offset = -(feet - fs * 0.5)
	_anim.scale = Vector2(sc, sc)
	_anim.modulate = Color.WHITE
	_sheet_mat.set_shader_parameter("flash", 0.0)
	_sheet_mat.set_shader_parameter("windup", 0.0)
	_shown_key = ""
	_play_loop("idle")
	_refresh_sheet_frame(true)


func _reset_effects() -> void:
	_dying = false
	_dead = false
	_death_t = 0.0
	_flash_left = 0.0
	_alert_t = -1.0
	_windup_t = -1.0
	_slam_t = -1.0
	_shout_t = -1.0
	_aim_line_t = -1.0
	_marker_t = -1.0
	_muzzle_t = -1.0
	_stun_t = -1.0
	_kick = Vector2.ZERO
	_area_radius = 0.0
	_cone_deg = 0.0
	_cone_len = 0.0
	_anim_lock = 0.0
	_anim_hold = -1
	_body.position = Vector2.ZERO
	_body.rotation = 0.0
	_body.scale = Vector2.ONE
	_body.modulate = Color.WHITE


func set_facing(dir: Vector2) -> void:
	if dir.length_squared() < 0.0001:
		return
	_facing_vec = dir.normalized()
	if absf(dir.x) > 0.05:
		_facing_target = signf(dir.x)
	if uses_sheet and not _dying and not _dead:
		var nd := EnemyArt.dir_index_sticky(_facing_vec, _dir)
		if nd != _dir:
			_dir = nd
			_refresh_sheet_frame(true)


func set_moving(moving: bool) -> void:
	if moving == _moving:
		return
	_moving = moving
	if uses_sheet and _anim_lock <= 0.0 and not _dying and not _dead:
		_play_loop("run" if moving else "idle")


## Vitesse de lecture (course plus rapide = foulées plus rapides).
func set_speed_scale(s: float) -> void:
	_speed_scale = clampf(s, 0.4, 2.0)


func flash_hit() -> void:
	if _dying or _dead:
		return
	_flash_left = FLASH_DURATION


## Réaction au coup : flash + courte animation de recul (planches) ou écrasement (sprite).
func play_hit() -> void:
	if _dying or _dead:
		return
	flash_hit()
	if uses_sheet and _windup_t < 0.0 and _anim_lock <= 0.0:
		_play_once("hit", 0.22)


func play_alert() -> void:
	if _dying or _dead:
		return
	_alert_t = 0.0


## Cri bref au-dessus de la tête (« Il est là ! »).
func play_shout(text: String) -> void:
	if _dying or _dead or text.is_empty():
		return
	_shout_text = text
	_shout_t = 0.0


## Télégraphe : lueur rouge qui monte sur `duration` secondes + tremblement ; planches : élan
## (images 0-2 de l'attaque, l'image d'élan est tenue jusqu'au coup).
func play_attack_windup(duration: float) -> void:
	if _dying or _dead:
		return
	_windup_duration = maxf(duration, 0.05)
	_windup_t = 0.0
	if uses_sheet:
		var hold := _meta_i("attack_hold_frame", 2)
		_play_once(_attack_anim(), duration + 0.4, hold)
		# Élan joué sur min(durée, 0,3 s) puis tenu.
		_anim_fps = float(hold + 1) / clampf(duration, 0.08, 0.3)


## Coup / tir : fin du télégraphe, images de frappe (3-5) ; éclair de bouche si `muzzle`.
func play_strike(dir: Vector2 = Vector2.ZERO, muzzle: bool = false, big: bool = false) -> void:
	if _dying or _dead:
		return
	_windup_t = -1.0
	_aim_line_t = -1.0
	_set_windup_param(0.0)
	if dir.length_squared() > 0.0001:
		_aim = dir.normalized()
	if muzzle:
		_muzzle_t = 0.0
		_muzzle_dir = _aim
		_muzzle_big = big
		_kick = -_aim * (5.0 if big else 3.0)
	if uses_sheet:
		var strike := _meta_i("attack_strike_frame", 3)
		var an := _attack_anim()
		var n := EnemyArt.frame_count(kind, an)
		_anim_name = an
		_anim_frames = n
		_anim_loop = false
		_anim_hold = -1
		_anim_fps = EnemyArt.fps(kind, an)
		_anim_t = float(strike) / maxf(_anim_fps, 1.0)
		_anim_lock = float(n - strike) / maxf(_anim_fps, 1.0)
		_refresh_sheet_frame(true)
	_fx_dirty_frames = 2


## Mort : planches = chute au sol (la dernière image reste) ; sprite = bascule sur le côté.
## `death_finished` à la fin, le visuel reste affiché (le jeu le remplace par un cadavre).
func play_death() -> void:
	if _dying or _dead:
		return
	_dying = true
	_death_t = 0.0
	_alert_t = -1.0
	_windup_t = -1.0
	_shout_t = -1.0
	_aim_line_t = -1.0
	_marker_t = -1.0
	_stun_t = -1.0
	_set_windup_param(0.0)
	_death_side = -1.0 if _facing_target > 0.0 else 1.0
	if uses_sheet:
		_play_once("death", 99.0)
	_fx_dirty_frames = 2


## Étourdi : petites étoiles au-dessus de la tête pendant `duration` s.
func play_stun(duration: float) -> void:
	if _dying or _dead:
		return
	_stun_t = 0.0
	_stun_total = maxf(duration, 0.05)
	if uses_sheet:
		_play_once("hit", duration)



## Ligne de visée rouge (tireur embusqué) pendant `duration` s, longueur `length` (monde).
func show_aim_line(duration: float, length: float) -> void:
	if _dying or _dead:
		return
	_aim_line_t = 0.0
	_aim_line_total = maxf(duration, 0.05)
	_aim_line_len = length
	_aim_locked = false


## La visée se fige (dernier instant pour esquiver) : la ligne clignote.
func lock_aim_line() -> void:
	_aim_locked = true


## Cercle au sol à `local_pos` (repère de l'ennemi) de rayon `radius` pendant `duration` s.
func show_ground_marker(local_pos: Vector2, radius: float, duration: float) -> void:
	if _dying or _dead:
		return
	_marker_pos = local_pos
	_marker_r = radius
	_marker_t = 0.0
	_marker_total = maxf(duration, 0.05)


func set_marker_position(local_pos: Vector2) -> void:
	_marker_pos = local_pos


func hide_telegraphs() -> void:
	_windup_t = -1.0
	_aim_line_t = -1.0
	_marker_t = -1.0
	_set_windup_param(0.0)
	_fx_dirty_frames = 2


func set_aura(color: Color) -> void:
	_aura_custom = true
	_apply_aura(color)


func set_elite(on: bool) -> void:
	_elite = on
	queue_redraw()


func set_attack_area(radius: float) -> void:
	_area_radius = maxf(radius, 0.0)


func set_attack_cone(spread_deg: float, length: float) -> void:
	_cone_deg = maxf(spread_deg, 0.0)
	_cone_len = maxf(length, 0.0)


func set_aim_direction(dir: Vector2) -> void:
	if dir.length_squared() > 0.0001:
		_aim = dir.normalized()


func play_ground_slam(radius: float) -> void:
	if _dying or _dead:
		return
	_slam_radius = maxf(radius, 1.0)
	_slam_t = 0.0
	if uses_sheet:
		play_strike(_aim, false)


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


## Bout du canon (repère local) pour la direction de visée courante.
func get_muzzle_offset(dir: Vector2) -> Vector2:
	if uses_sheet:
		var m := EnemyArt.muzzle_local(kind, EnemyArt.dir_name(dir))
		if m != Vector2.INF:
			return m
	return Vector2(0, get_head_offset().y * 0.45) + dir.normalized() * 22.0


func is_dying() -> bool:
	return _dying


func is_dead_pose() -> bool:
	return _dead


## Cadavre : {texture, offset (centré), scale, rotation, flip, modulate} reproduisant la pose finale.
func get_corpse_info() -> Dictionary:
	if uses_sheet:
		var tex := EnemyArt.corpse_texture(kind, EnemyArt.DIR_NAMES[_dir])
		return {"texture": tex, "offset": _anim.offset, "scale": _anim.scale, "rotation": 0.0,
			"centered": true, "pivot": Vector2.ZERO}
	return {"texture": _sprite.texture, "offset": _sprite.offset, "scale": _sprite.scale * Vector2(_facing_sign(), 1.0),
		"rotation": _death_side * PI * 0.5, "centered": false, "pivot": Vector2(0, -4),
		"tint": Color(0.86, 0.8, 0.78)}


func _facing_sign() -> float:
	return 1.0 if _facing >= 0.0 else -1.0


# --- Construction ------------------------------------------------------------

func _build() -> void:
	if _body != null:
		return
	if _font == null:
		_font = ThemeDB.fallback_font
	_body = Node2D.new()
	_body.name = "Body"
	add_child(_body)
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_sprite.material = _mat
	_body.add_child(_sprite)
	_anim = AnimatedSprite2D.new()
	_anim.name = "Anim"
	_anim.visible = false
	if _sheet_shader == null:
		_sheet_shader = Shader.new()
		_sheet_shader.code = SHEET_SHADER_CODE
	_sheet_mat = ShaderMaterial.new()
	_sheet_mat.shader = _sheet_shader
	_anim.material = _sheet_mat
	_body.add_child(_anim)
	_overlay = Node2D.new()
	_overlay.name = "EyesGlow"
	_sprite.add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	_fx = Node2D.new()
	_fx.name = "Fx"
	_fx.z_index = 10
	add_child(_fx)
	_fx.draw.connect(_draw_fx)


# --- Planches ------------------------------------------------------------------

func _meta_i(key: String, def: int) -> int:
	var e := EnemyArt.entry(kind)
	return int((e["meta"] as Dictionary).get(key, def)) if not e.is_empty() else def


func _attack_anim() -> String:
	return "throw" if _throw_anim else "attack"


## Lance une animation de « throw » si elle existe (chef de bande), sinon attack.
func use_throw_anim(on: bool) -> void:
	_throw_anim = on and EnemyArt.has_anim(kind, "throw")



func _play_loop(an: String) -> void:
	_anim_name = an
	_anim_frames = EnemyArt.frame_count(kind, an)
	_anim_fps = EnemyArt.fps(kind, an)
	_anim_loop = true
	_anim_hold = -1
	_anim_t = randf() * float(_anim_frames) / maxf(_anim_fps, 1.0) if an == "idle" else 0.0
	_refresh_sheet_frame(true)


## Animation non bouclée ; `lock` = durée pendant laquelle idle/run ne la remplacent pas ;
## `hold` = image tenue (élan).
func _play_once(an: String, lock: float, hold: int = -1) -> void:
	if an == "attack" and _throw_anim:
		an = "throw"
	_anim_name = an
	_anim_frames = EnemyArt.frame_count(kind, an)
	_anim_fps = EnemyArt.fps(kind, an)
	_anim_loop = false
	_anim_hold = hold
	_anim_t = 0.0
	_anim_lock = lock
	_refresh_sheet_frame(true)


func _refresh_sheet_frame(force: bool = false) -> void:
	if not uses_sheet or _anim.sprite_frames == null:
		return
	var key := _anim_name + "_" + EnemyArt.DIR_NAMES[_dir]
	var f := int(_anim_t * _anim_fps)
	if _anim_loop:
		f = f % maxi(_anim_frames, 1)
	else:
		f = mini(f, _anim_frames - 1)
		if _anim_hold >= 0:
			f = mini(f, _anim_hold)
	if key != _shown_key:
		if not _anim.sprite_frames.has_animation(key):
			return
		_shown_key = key
		_anim.animation = key
		_shown_frame = -1
	if f != _shown_frame or force:
		_shown_frame = f
		_anim.frame = f


func _update_sheet(delta: float) -> void:
	_anim_t += delta * (_speed_scale if _anim_loop and _anim_name == "run" else 1.0)
	if _anim_lock > 0.0 and not _dying:
		_anim_lock -= delta
		if _anim_lock <= 0.0 or (not _anim_loop and _anim_hold < 0
				and _anim_t * _anim_fps >= float(_anim_frames) + 0.5):
			_anim_lock = 0.0
			_play_loop("run" if _moving else "idle")
	_refresh_sheet_frame()


# --- Animation ---------------------------------------------------------------

func _set_windup_param(w: float) -> void:
	if uses_sheet:
		_sheet_mat.set_shader_parameter("windup", w)
	else:
		_mat.set_shader_parameter("windup", w)


func _set_flash_param(f: float) -> void:
	if uses_sheet:
		_sheet_mat.set_shader_parameter("flash", f)
	else:
		_mat.set_shader_parameter("flash", f)


func _process(delta: float) -> void:
	if _body == null:
		return
	if _dead:
		set_process(false)
		return
	# Caché (brouillard) et sans effet en cours : rien à animer ni à redessiner.
	if not _dying and not is_visible_in_tree():
		if _windup_t >= 0.0 or _alert_t >= 0.0 or _slam_t >= 0.0 or _flash_left > 0.0 or _shout_t >= 0.0:
			_windup_t = -1.0
			_alert_t = -1.0
			_slam_t = -1.0
			_shout_t = -1.0
			_flash_left = 0.0
			_set_windup_param(0.0)
			_set_flash_param(0.0)
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
		_set_flash_param(clampf(_flash_left / FLASH_DURATION, 0.0, 1.0) * 0.85)

	var shake := Vector2.ZERO
	if _windup_t >= 0.0:
		_windup_t += delta
		var w := clampf(_windup_t / _windup_duration, 0.0, 1.0)
		if _windup_t > _windup_duration + WINDUP_HOLD:
			_windup_t = -1.0
			w = 0.0
		_set_windup_param(w)
		shake = Vector2(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5)) * WINDUP_SHAKE * w
		breath += w * 0.03
		_fx_dirty_frames = 2
	_kick = _kick.move_toward(Vector2.ZERO, delta * 60.0)

	if _alert_t >= 0.0:
		_alert_t += delta
		if _alert_t > ALERT_DURATION:
			_alert_t = -1.0
	if _shout_t >= 0.0:
		_shout_t += delta
		if _shout_t > SHOUT_DURATION:
			_shout_t = -1.0
	if _slam_t >= 0.0:
		_slam_t += delta
		if _slam_t > SLAM_DURATION:
			_slam_t = -1.0
	if _aim_line_t >= 0.0:
		_aim_line_t += delta
		if _aim_line_t > _aim_line_total + 0.15:
			_aim_line_t = -1.0
	if _marker_t >= 0.0:
		_marker_t += delta
		if _marker_t > _marker_total:
			_marker_t = -1.0
	if _muzzle_t >= 0.0:
		_muzzle_t += delta
		if _muzzle_t > MUZZLE_DURATION:
			_muzzle_t = -1.0
	if _stun_t >= 0.0:
		_stun_t += delta
		if _stun_t > _stun_total:
			_stun_t = -1.0

	if uses_sheet:
		_update_sheet(delta)
		if _dying:
			_death_t += delta
			var dur := float(_anim_frames) / maxf(_anim_fps, 1.0)
			if _death_t >= dur:
				_finish_death()
				return
		_body.position = shake + _kick
		_body.rotation = 0.0
		var s := 1.0 + squash * 0.5
		_body.scale = Vector2(s, 1.0 - squash * 0.5)
	else:
		var sx := (1.0 + squash - breath * 0.5) * (_facing if absf(_facing) > 0.05 else 0.05)
		var sy := 1.0 - squash + breath
		if _dying:
			_death_t += delta
			var d := clampf(_death_t / DEATH_DURATION, 0.0, 1.0)
			var e := ease(d, 0.45)
			# Bascule sur le côté (pivot aux pieds), petit rebond, assombrissement.
			_body.rotation = _death_side * PI * 0.5 * e
			_body.position = Vector2(0, -4.0 * sin(d * PI) * (1.0 - d)) + Vector2(0, -4.0 * e)
			_body.scale = Vector2(_facing_sign(), 1.0)
			_sprite.modulate = Color.WHITE.lerp(Color(0.86, 0.8, 0.78), d)
			if _death_t >= DEATH_DURATION:
				_finish_death()
				return
		else:
			_body.position = Vector2(0, bob) + shake + _kick
			_body.rotation = tilt
			_body.scale = Vector2(sx, sy)
		_eye_redraw_left -= delta
		if _eye_redraw_left <= 0.0 or _windup_t >= 0.0:
			_eye_redraw_left = EYE_REDRAW_INTERVAL
			_overlay.queue_redraw()
	if _alert_t >= 0.0 or _windup_t >= 0.0 or _slam_t >= 0.0 or _shout_t >= 0.0 or _aim_line_t >= 0.0 \
			or _marker_t >= 0.0 or _muzzle_t >= 0.0 or _stun_t >= 0.0:
		_fx_dirty_frames = 2
	if _fx_dirty_frames > 0:
		_fx_dirty_frames -= 1
		_fx.queue_redraw()


func _finish_death() -> void:
	_dying = false
	_dead = true
	_fx.queue_redraw()
	queue_redraw()
	death_finished.emit()


# --- Dessin ------------------------------------------------------------------

func _draw() -> void:
	if _data.is_empty() or _dead or _dying:
		return
	var r: float = _data["shadow"]
	# Ombre portée longue (lumière rasante), puis ombre de contact.
	draw_set_transform(Vector2(r * CAST_SHADOW_OFFSET.x, 2.0 + r * CAST_SHADOW_OFFSET.y), -0.12,
		Vector2(1.9, SHADOW_FLATTEN * 0.9))
	draw_circle(Vector2.ZERO, r, CAST_SHADOW_COLOR)
	draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, SHADOW_FLATTEN))
	draw_circle(Vector2.ZERO, r, SHADOW_COLOR)
	draw_circle(Vector2.ZERO, r * 0.7, Color(SHADOW_COLOR, SHADOW_COLOR.a * 0.6))
	if _elite:
		draw_arc(Vector2.ZERO, r * 1.25, 0.0, TAU, 40, Color(1.0, 0.75, 0.25, 0.75), 3.0, true)
	draw_set_transform(Vector2.ZERO)


## Yeux lumineux teintés par l'aura (coordonnées texture du sprite, mode sprite seulement).
func _draw_overlay() -> void:
	if uses_sheet or _data.is_empty() or _sprite.texture == null or _dying or _dead:
		return
	var eyes: Array = _data.get("eyes", [])
	if eyes.is_empty():
		return
	var svg_size: Vector2 = _data["svg_size"]
	var k: float = _sprite.texture.get_size().x / svg_size.x
	var off := _sprite.offset
	var r: float = float(_data["eye_r"]) * k
	var pulse := 0.85 + 0.15 * sin(_time * EYE_GLOW_PULSE)
	var col := _aura
	if _windup_t >= 0.0:
		var w := clampf(_windup_t / _windup_duration, 0.0, 1.0)
		col = _aura.lerp(WINDUP_COLOR, w)
		pulse += w * 0.6
	for e: Vector2 in eyes:
		var p := off + e * k
		_overlay.draw_circle(p, r * 2.6 * pulse, Color(col, 0.16))
		_overlay.draw_circle(p, r * 1.6, Color(col, 0.45))
		_overlay.draw_circle(p, r * 0.95, Color(col.lerp(Color.WHITE, 0.25), 0.95))
		_overlay.draw_circle(p, r * 0.42, Color(1.0, 0.97, 0.88))


func _draw_fx() -> void:
	if _dead:
		return
	if _marker_t >= 0.0:
		_draw_marker()
	if _windup_t >= 0.0 and _windup_duration > 0.0:
		var w := clampf(_windup_t / _windup_duration, 0.0, 1.0)
		_draw_special_telegraph(w)
		var r: float = float(_data.get("shadow", 20.0)) * (1.0 + 0.25 * w)
		_fx.draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, SHADOW_FLATTEN))
		_fx.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(WINDUP_COLOR, 0.25 + 0.55 * w), 3.0 + 3.0 * w, true)
		_fx.draw_set_transform(Vector2.ZERO)
	if _aim_line_t >= 0.0:
		_draw_aim_line()
	if _slam_t >= 0.0:
		_draw_slam()
	if _muzzle_t >= 0.0:
		_draw_muzzle()
	if _alert_t >= 0.0:
		_draw_alert()
	if _shout_t >= 0.0:
		_draw_shout()
	if _stun_t >= 0.0:
		_draw_stun()


## Cône d'éventail ou anneau de zone qui se remplit pendant le télégraphe.
func _draw_special_telegraph(w: float) -> void:
	if _cone_deg > 0.0 and _cone_len > 0.0:
		var half := deg_to_rad(_cone_deg) * 0.5
		var a0 := _aim.angle()
		var steps := 14
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


## Ligne de visée : fine et pâle au début, épaisse et rouge vif à la fin ; clignote une fois figée.
func _draw_aim_line() -> void:
	var w := clampf(_aim_line_t / _aim_line_total, 0.0, 1.0)
	var start := get_muzzle_offset(_aim)
	var end := start + _aim * _aim_line_len
	var a := 0.25 + 0.6 * w
	if _aim_locked and int(_aim_line_t * 20.0) % 2 == 0:
		a = 1.0
	_fx.draw_line(start, end, Color(AIM_LINE_COLOR, a * 0.35), 5.0 + 3.0 * w, true)
	_fx.draw_line(start, end, Color(AIM_LINE_COLOR.lerp(Color(1, 0.8, 0.7), 0.3), a), 1.6 + 1.2 * w, true)
	_fx.draw_circle(end, 4.0 + 3.0 * w, Color(AIM_LINE_COLOR, a * 0.8))


## Cercle au sol (zone d'impact d'un explosif) qui se remplit jusqu'à l'impact.
func _draw_marker() -> void:
	var w := clampf(_marker_t / _marker_total, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_marker_t * 18.0)
	_fx.draw_circle(_marker_pos, _marker_r, Color(MARKER_COLOR, 0.08 + 0.06 * w))
	_fx.draw_circle(_marker_pos, _marker_r * w, Color(MARKER_COLOR, 0.12 + 0.1 * w))
	_fx.draw_arc(_marker_pos, _marker_r, 0.0, TAU, 48, Color(MARKER_COLOR, 0.55 + 0.4 * pulse), 2.5, true)


func _draw_muzzle() -> void:
	var t := clampf(_muzzle_t / MUZZLE_DURATION, 0.0, 1.0)
	var p := get_muzzle_offset(_muzzle_dir)
	var k := (1.6 if _muzzle_big else 1.0) * (1.0 - t * 0.5)
	var d := _muzzle_dir
	var side := Vector2(-d.y, d.x)
	var tip := p + d * 20.0 * k
	_fx.draw_circle(p, 9.0 * k, Color(1.0, 0.7, 0.25, 0.55 * (1.0 - t)))
	_fx.draw_colored_polygon(PackedVector2Array([p + side * 6.0 * k, tip, p - side * 6.0 * k]),
		Color(1.0, 0.85, 0.4, 0.95 * (1.0 - t)))
	_fx.draw_circle(p, 4.0 * k, Color(1.0, 0.98, 0.85, 1.0 - t))


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
	var base := get_head_offset() + Vector2(0, -ALERT_ABOVE_BAR - ALERT_HEIGHT * 0.5 - (1.0 - a) * 6.0)
	_fx.draw_set_transform(base, 0.0, Vector2(pop, pop))
	var bar := PackedVector2Array([Vector2(-5.5, -14), Vector2(5.5, -14), Vector2(3, 4), Vector2(-3, 4)])
	var outline := Color(OUTLINE, a)
	var big := PackedVector2Array([Vector2(-8, -16.5), Vector2(8, -16.5), Vector2(5, 6.5), Vector2(-5, 6.5)])
	_fx.draw_colored_polygon(big, outline)
	_fx.draw_circle(Vector2(0, 11), 6.2, outline)
	_fx.draw_colored_polygon(bar, Color(ALERT_FILL, a))
	_fx.draw_circle(Vector2(0, 11), 3.8, Color(ALERT_FILL, a))
	_fx.draw_colored_polygon(PackedVector2Array([Vector2(-4, -12.5), Vector2(-0.5, -12.5), Vector2(-1.5, -3), Vector2(-3.2, -3)]), Color(ALERT_FILL_LIGHT, a))
	_fx.draw_set_transform(Vector2.ZERO)


## Bulle de cri (texte court) décalée à côté de la tête.
func _draw_shout() -> void:
	if _font == null:
		return
	var t := _shout_t
	var a := 1.0 if t < SHOUT_DURATION * 0.7 else 1.0 - (t - SHOUT_DURATION * 0.7) / (SHOUT_DURATION * 0.3)
	var pop := minf(1.0, t / 0.1)
	var size := 15
	var w := _font.get_string_size(_shout_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var base := get_head_offset() + Vector2(14.0, -10.0 - 6.0 * t)
	var rect := Rect2(base + Vector2(-4, -size - 1), Vector2(w + 8, size + 7))
	_fx.draw_set_transform(base, 0.0, Vector2(pop, pop))
	rect.position -= base
	_fx.draw_rect(rect, Color(SHOUT_BG, SHOUT_BG.a * a))
	_fx.draw_colored_polygon(PackedVector2Array([rect.position + Vector2(2, rect.size.y),
		rect.position + Vector2(12, rect.size.y), rect.position + Vector2(-4, rect.size.y + 7)]), Color(SHOUT_BG, SHOUT_BG.a * a))
	_fx.draw_string(_font, Vector2(0, 0), _shout_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(SHOUT_TEXT, a))
	_fx.draw_set_transform(Vector2.ZERO)


func _draw_stun() -> void:
	var c := get_head_offset() + Vector2(0, 6)
	for i: int in 3:
		var ang := _stun_t * 7.0 + TAU * float(i) / 3.0
		var p := c + Vector2(cos(ang) * 14.0, sin(ang) * 5.0)
		_fx.draw_circle(p, 3.2, Color(OUTLINE, 0.8))
		_fx.draw_circle(p, 2.2, STUN_COLOR)
