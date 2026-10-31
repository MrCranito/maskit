class_name PlayerVisual
extends Node2D
## Rendu du joueur (aucune logique de jeu). Enfant du joueur, construit en code :
##   Shadow (z -3, dessin unique) · AimMarker (z -2, dessin unique, tourné)
##   Body root (inclinaison, écrasement/étirement, recul du corps)
##     → Body (AnimatedSprite2D des planches du skin, sinon SVG, sinon silhouette dessinée)
##   WeaponPivot (main, z ±1, hors du corps : ni écrasé ni incliné avec lui, il suit seulement
##     son rebond) → WeaponView (sprite d'arme, recul, éclair)
##   HpBar (redessinée quand les PV changent) · ReloadRing (redessiné par pas de 1/32)
## Planches : HeroSkin.frames_for/meta_for/material_for(HeroSkin.current()). Les anims sont
## découvertes à la lecture (« <base>_<dir8> ») : idle et run obligatoires ; backpedal,
## strafe, walk, hit utilisés s'ils existent (sinon : run joué à l'envers en recul, flash +
## écrasement au coup reçu).
## Par frame : affectations de propriétés uniquement (aucune allocation, aucun redessin).

const DIR8_NAMES: Array[String] = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const SVG_IDLE := "res://assets/sprites/hero/hero_kitsune.svg"
const SVG_WALK: Array[String] = ["res://assets/sprites/hero/hero_kitsune_walk_1.svg",
	"res://assets/sprites/hero/hero_kitsune_walk_2.svg"]
const HIT_FLASH_SHADER_PATH := "res://assets/shaders/hit_flash.gdshader"
## Hauteur du héros de repli (SVG / silhouette) en unités monde.
const FALLBACK_HEIGHT := 54.0

const COL_SHADOW := Color(0.07, 0.1, 0.25, 0.45)
const COL_AIM := Color(1.0, 0.25, 0.15)

var player: Player = null
var weapon_view: WeaponView = null
var hand_height: float = 24.0
var hand_radius: float = 10.0
var body_height: float = FALLBACK_HEIGHT
var facing_index: int = 0
## Base d'animation jouée (idle, run, backpedal…) — debug et tests.
var current_base: StringName = &""
var uses_sheets: bool = false

var _shadow: Node2D = null
var _aim_marker: Node2D = null
var _aim_marker_rot: Node2D = null
## Cône de dispersion : deux traits de part et d'autre de la flèche de visée, tournés de
## ±imprécision effective (rotation seulement, dessinés une fois).
var _cone_l: Node2D = null
var _cone_r: Node2D = null
var _cone_deg: float = -1.0
var _root: Node2D = null
var _body: Node2D = null
var _anim: AnimatedSprite2D = null
var _svg: Sprite2D = null
var _svg_tex: Array[Texture2D] = []
var _weapon_pivot: Node2D = null
var _hp_bar: Node2D = null
var _reload_ring: Node2D = null
## Équipement montré dans la main libre pendant un lancer / une pose.
var _gadget_hand: Node2D = null
var _gadget_hand_left: float = 0.0
var _gadget_tex: Texture2D = null
var _gadget_kind: StringName = &""
var _flash_mat: ShaderMaterial = null
var _skin_mat: Material = null

## base → Array[StringName] (8 directions, repli sur la direction disponible la plus proche).
var _anims: Dictionary = {}
var _current_anim: StringName = &""
var _step_frames: PackedInt32Array = PackedInt32Array([0, 4])
var _base_scale: float = 1.0
var _svg_frame: int = -1
var _walk_phase: float = 0.0
var _breath: float = 0.0

# États animés.
var _was_moving: bool = false
var _sq: float = 0.0
var _sq_v: float = 0.0
var _body_kick: float = 0.0
var _body_kick_px: float = 0.0
var _hit_t: float = 0.0
var _hit_lock: float = 0.0
var _flash_left: float = 0.0
var _last_flash: float = -1.0
var _last_alpha: float = -1.0
var _weapon_behind: bool = false
var _turn_ref: Vector2 = Vector2.ZERO
var _turn_sample: float = 0.0
var _turn_cooldown: float = 0.0
var _reload_step: int = -1
var _reload_progress: float = -1.0
var _lean: float = 0.0
## Tenue de l'arme : angle affiché (lissé vers la visée, ou vers la marche sans visée), sens du
## retournement gauche/droite et passage derrière le corps, avec hystérésis (aucun saut).
var _weapon_angle: float = 0.0
var _weapon_flip: float = 1.0
var _weapon_turn_aim: float = 30.0
var _weapon_turn_move: float = 12.0
var _weapon_flip_dead: float = 0.18
var _corpse_alpha: float = 0.9
var _weapon_behind_in: float = -0.42
var _weapon_behind_out: float = -0.26

# Réglages ([player_visual] + [player_fx]).
var _tilt_rad: float = 0.09
var _bounce_px: float = 3.0
var _squash_walk: float = 0.06
var _stride_px: float = 34.0
var _dir_hysteresis: float = 0.12
var _anim_speed_min: float = 0.55
var _anim_speed_max: float = 1.35
var _lean_speed: float = 10.0
var _start_stretch: float = 0.08
var _stop_squash: float = 0.1
var _spring_k: float = 260.0
var _spring_c: float = 16.0
var _backpedal_dot: float = -0.35
var _footstep_dust: bool = true
var _turn_dust: bool = true
var _turn_dot: float = 0.1
var _hit_squash: float = 0.12
var _hit_flash_time: float = 0.12


func setup(p: Player) -> void:
	player = p
	name = "PlayerVisual"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_load_balance()
	_shadow = _make_drawn(self, "Shadow", -3, _draw_shadow)
	_aim_marker = Node2D.new()
	_aim_marker.name = "AimMarker"
	_aim_marker.z_index = -2
	_aim_marker.scale = Vector2(1.0, 0.6)  # perspective : flèche écrasée au sol
	add_child(_aim_marker)
	_aim_marker_rot = _make_drawn(_aim_marker, "Arrow", 0, _draw_aim_marker)
	_cone_l = _make_drawn(_aim_marker_rot, "ConeL", 0, _draw_cone_edge.bind(0))
	_cone_r = _make_drawn(_aim_marker_rot, "ConeR", 0, _draw_cone_edge.bind(1))

	_root = Node2D.new()
	_root.name = "Body"
	add_child(_root)
	if ResourceLoader.exists(HIT_FLASH_SHADER_PATH):
		_flash_mat = ShaderMaterial.new()
		_flash_mat.shader = load(HIT_FLASH_SHADER_PATH) as Shader
	if not _build_sheets():
		_build_fallback_body()
	_weapon_pivot = Node2D.new()
	_weapon_pivot.name = "WeaponPivot"
	add_child(_weapon_pivot)
	weapon_view = WeaponView.new()
	_weapon_pivot.add_child(weapon_view)

	_hp_bar = _make_drawn(self, "HpBar", 2, _draw_hp_bar)
	_hp_bar.position = Vector2(0.0, -body_height - 9.0)
	_reload_ring = _make_drawn(self, "ReloadRing", 3, _draw_reload_ring)
	_reload_ring.position = Vector2(0.0, -body_height - 24.0)
	_reload_ring.visible = false
	update_facing(true)


func _load_balance() -> void:
	_tilt_rad = deg_to_rad(Balance.get_float("player_visual", "tilt_deg", 5.0))
	_bounce_px = Balance.get_float("player_visual", "bounce_px", 3.0)
	_squash_walk = Balance.get_float("player_visual", "squash", 0.06)
	_stride_px = Balance.get_float("player_visual", "stride_px", 34.0)
	_dir_hysteresis = deg_to_rad(Balance.get_float("player_visual", "dir_hysteresis_deg", 7.0))
	hand_height = Balance.get_float("player_visual", "hand_height", 24.0)
	hand_radius = Balance.get_float("player_visual", "hand_radius", 10.0)
	_anim_speed_min = Balance.get_float("player_fx", "anim_speed_min", 0.55)
	_anim_speed_max = Balance.get_float("player_fx", "anim_speed_max", 1.35)
	_lean_speed = Balance.get_float("player_fx", "lean_speed", 10.0)
	_start_stretch = Balance.get_float("player_fx", "start_stretch", 0.08)
	_stop_squash = Balance.get_float("player_fx", "stop_squash", 0.1)
	_spring_k = Balance.get_float("player_fx", "squash_spring_k", 260.0)
	_spring_c = Balance.get_float("player_fx", "squash_spring_damping", 16.0)
	_backpedal_dot = Balance.get_float("player_fx", "backpedal_dot", -0.35)
	_footstep_dust = bool(Balance.get_value("player_visual", "dust_enabled", true)) \
		and bool(Balance.get_value("player_fx", "footstep_dust", true))
	_turn_dust = bool(Balance.get_value("player_fx", "turn_dust", true))
	_turn_dot = Balance.get_float("player_fx", "turn_dust_dot", 0.1)
	_hit_squash = Balance.get_float("player_fx", "hit_squash", 0.12)
	_hit_flash_time = Balance.get_float("player", "hit_flash_duration", 0.12)
	_weapon_turn_aim = Balance.get_float("player_visual", "weapon_turn_speed_aim", 30.0)
	_weapon_turn_move = Balance.get_float("player_visual", "weapon_turn_speed_move", 12.0)
	_weapon_flip_dead = Balance.get_float("player_visual", "weapon_flip_deadzone", 0.18)
	_corpse_alpha = Balance.get_float("death", "corpse_alpha", 0.9)
	_weapon_behind_in = Balance.get_float("player_visual", "weapon_behind_enter", -0.42)
	_weapon_behind_out = Balance.get_float("player_visual", "weapon_behind_exit", -0.26)


func _make_drawn(parent: Node, node_name: String, z: int, drawer: Callable) -> Node2D:
	var n := Node2D.new()
	n.name = node_name
	n.z_index = z
	n.draw.connect(drawer)
	parent.add_child(n)
	return n


# --- Construction du corps ----------------------------------------------------------

## Planches du skin courant. false si absentes ou sans idle.
func _build_sheets() -> bool:
	var skin: SkinData = HeroSkin.current()
	var frames: SpriteFrames = HeroSkin.frames_for(skin)
	if frames == null:
		return false
	_anims = discover_anims(frames.get_animation_names())
	if not _anims.has(&"idle"):
		push_warning("PlayerVisual : planche sans anim idle_<dir>, repli.")
		_anims.clear()
		return false
	var meta: Dictionary = HeroSkin.meta_for(skin)
	var first_anim: StringName = (_anims[&"idle"] as Array)[0]
	var first: Texture2D = frames.get_frame_texture(first_anim, 0)
	var fs: Vector2 = Vector2(first.get_size()) if first != null else Vector2(128, 128)
	fs = WeaponView._vec2_from(meta.get("frame_size"), fs)
	var feet: Vector2 = WeaponView._vec2_from(meta.get("feet_offset"), Vector2(fs.x * 0.5, fs.y))
	var display_h: float = float(meta.get("display_height", FALLBACK_HEIGHT * 1.6))
	_anim = AnimatedSprite2D.new()
	_anim.name = "HeroSprite"
	_anim.sprite_frames = frames
	# Format de l'artiste : centered + offset = -(feet_offset - frame_size / 2).
	_anim.centered = true
	_anim.offset = -(feet - fs * 0.5)
	_anim.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_base_scale = display_h / maxf(fs.y, 1.0)
	_anim.scale = Vector2.ONE * _base_scale
	_skin_mat = HeroSkin.material_for(skin)
	_anim.material = _skin_mat if _skin_mat != null else _flash_mat
	body_height = float(meta.get("hero_height_px", feet.y * 0.85)) * _base_scale
	hand_height = float(meta["hand_height"]) if meta.has("hand_height") else body_height * 0.45
	# Images de pose du pied (poussière de pas) : meta « step_frames », sinon 0 et n/2.
	var steps: Variant = meta.get("step_frames")
	if steps is Array and not (steps as Array).is_empty():
		_step_frames = PackedInt32Array(steps as Array)
	elif _anims.has(&"run"):
		var n: int = frames.get_frame_count((_anims[&"run"] as Array)[0])
		_step_frames = PackedInt32Array([0, maxi(n / 2, 1)])
	_anim.frame_changed.connect(_on_frame_changed)
	_root.add_child(_anim)
	_body = _anim
	uses_sheets = true
	return true


## Logique pure : regroupe les anims « <base>_<dir> » par base ; chaque base a 8 entrées
## (direction manquante → direction disponible la plus proche).
static func discover_anims(names: PackedStringArray) -> Dictionary:
	var found: Dictionary = {}
	for n: String in names:
		var cut: int = n.rfind("_")
		if cut <= 0:
			continue
		var dir: int = DIR8_NAMES.find(n.substr(cut + 1))
		if dir < 0:
			continue
		var base := StringName(n.substr(0, cut))
		if not found.has(base):
			found[base] = [-1, -1, -1, -1, -1, -1, -1, -1]
		(found[base] as Array)[dir] = dir
	var out: Dictionary = {}
	for base: StringName in found:
		var have: Array = found[base]
		var list: Array[StringName] = []
		for i: int in 8:
			var best: int = -1
			for d: int in 5:  # 0, ±1, ±2, ±3, 4 crans
				for sgn: int in [1, -1]:
					var j: int = wrapi(i + d * sgn, 0, 8)
					if int(have[j]) >= 0:
						best = j
						break
				if best >= 0:
					break
			list.append(StringName("%s_%s" % [base, DIR8_NAMES[best]]))
		out[base] = list
	return out


func has_anim(base: StringName) -> bool:
	return _anims.has(base)


func _build_fallback_body() -> void:
	uses_sheets = false
	if ResourceLoader.exists(SVG_IDLE):
		_svg_tex.append(load(SVG_IDLE) as Texture2D)
		for p: String in SVG_WALK:
			if ResourceLoader.exists(p):
				_svg_tex.append(load(p) as Texture2D)
	if not _svg_tex.is_empty() and _svg_tex[0] != null:
		_svg = Sprite2D.new()
		_svg.name = "HeroSprite"
		_svg.texture = _svg_tex[0]
		_svg.centered = true
		_svg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var tex_h: float = float(_svg_tex[0].get_height())
		_base_scale = FALLBACK_HEIGHT / tex_h
		_svg.offset = Vector2(0.0, -tex_h * 0.5 + tex_h * 3.0 / 200.0)
		_svg.scale = Vector2.ONE * _base_scale
		_svg.material = _flash_mat
		_root.add_child(_svg)
		_body = _svg
	else:
		# Silhouette dessinée (aucun asset) : personnage simple, gilet + tête.
		var drawn := Node2D.new()
		drawn.name = "HeroDrawn"
		drawn.draw.connect(_draw_placeholder_hero.bind(drawn))
		drawn.material = _flash_mat
		_root.add_child(drawn)
		_body = drawn
	body_height = FALLBACK_HEIGHT


# --- Événements (appelés par le joueur) ---------------------------------------------

func set_weapon(w: WeaponData, animate: bool) -> void:
	weapon_view.set_weapon(w, animate)


func on_fired(_dir: Vector2) -> void:
	weapon_view.on_fired()
	_body_kick = 1.0
	_body_kick_px = float(weapon_view.profile.get("body_px", 1.0))


## Lancer / pose d'équipement : élan du corps + l'objet apparaît dans la main libre.
func on_throw(_dir: Vector2, g: WeaponData = null) -> void:
	_body_kick = 1.0
	_body_kick_px = -3.0
	_sq_v -= 2.0
	if g == null:
		return
	if _gadget_hand == null:
		_gadget_hand = Node2D.new()
		_gadget_hand.name = "GadgetHand"
		_gadget_hand.z_index = 2
		_gadget_hand.draw.connect(_draw_gadget_hand)
		_root.add_child(_gadget_hand)
	if g.gadget_kind != _gadget_kind:
		_gadget_kind = g.gadget_kind
		var p: String = WeaponView.WEAPON_SPRITE_DIR + String(g.id) + ".png"
		_gadget_tex = load(p) as Texture2D if ResourceLoader.exists(p) else null
		_gadget_hand.queue_redraw()
	var aim: Vector2 = player.aim_direction
	_gadget_hand.position = Player.hand_offset(-aim, hand_height + 6.0, hand_radius)
	_gadget_hand.visible = true
	_gadget_hand_left = 0.3


func _draw_gadget_hand() -> void:
	if _gadget_tex != null:
		var sz := Vector2(_gadget_tex.get_size())
		var sc: float = 16.0 / maxf(sz.y, 1.0)
		_gadget_hand.draw_set_transform(Vector2.ZERO, 0.0, Vector2(sc, sc))
		_gadget_hand.draw_texture(_gadget_tex, -sz * 0.5)
		return
	GadgetDevice.draw_gadget_shape(_gadget_hand, _gadget_kind)


func on_hit() -> void:
	_flash_left = _hit_flash_time
	_hit_t = 1.0
	_sq += _hit_squash
	if has_anim(&"hit") and _anim != null:
		var a: StringName = (_anims[&"hit"] as Array)[facing_index]
		var fps: float = _anim.sprite_frames.get_animation_speed(a)
		_hit_lock = float(_anim.sprite_frames.get_frame_count(a)) / maxf(fps, 1.0)
		_current_anim = a
		current_base = &"hit"
		_anim.speed_scale = 1.0
		_anim.play(a)


## Progression du rechargement (0..1), < 0 = aucun.
func set_reload(progress: float) -> void:
	_reload_progress = progress
	weapon_view.set_reload(progress)
	var on: bool = progress >= 0.0 and player != null and player.is_alive() and not player.is_hidden()
	if _reload_ring.visible != on:
		_reload_ring.visible = on
	var step: int = int(progress * 32.0) if on else -1
	if step != _reload_step:
		_reload_step = step
		_reload_ring.queue_redraw()


func refresh_state() -> void:
	var hidden: bool = player.is_hidden()
	_shadow.visible = not hidden
	_hp_bar.visible = not hidden and player.is_alive()
	_hp_bar.queue_redraw()
	set_reload(_reload_progress)
	update_facing(true)


func hp_dirty() -> void:
	if _hp_bar != null:
		_hp_bar.queue_redraw()


# --- Animation --------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null:
		return
	var alive: bool = player.is_alive()
	var hidden: bool = player.is_hidden()
	var moving: bool = alive and not hidden and player.is_moving()
	var vel: Vector2 = player.velocity
	var ref_speed: float = maxf(player.get_effective_speed(), 1.0)
	var speed: float = vel.length()
	var ratio: float = speed / ref_speed

	update_facing(false, delta)

	# Écrasement / étirement : impulsion au démarrage (étiré) et à l'arrêt (tassé), ressort amorti.
	if moving != _was_moving:
		_was_moving = moving
		_sq_v += (-_start_stretch if moving else _stop_squash) * 22.0
		if not moving and alive and not hidden and _footstep_dust:
			_footstep(Vector2.ZERO, 1.2)
	_sq_v += (-_spring_k * _sq - _spring_c * _sq_v) * delta
	_sq += _sq_v * delta
	_sq = clampf(_sq, -0.25, 0.25)

	# Inclinaison dans le sens du mouvement (lissée).
	var want_lean: float = clampf(vel.x / ref_speed, -1.0, 1.0) * _tilt_rad if moving else 0.0
	_lean = lerpf(_lean, want_lean, 1.0 - exp(-_lean_speed * delta))

	_body_kick = maxf(_body_kick - delta / 0.14, 0.0)
	_hit_t = maxf(_hit_t - delta / 0.2, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	_hit_lock = maxf(_hit_lock - delta, 0.0)
	_turn_cooldown = maxf(_turn_cooldown - delta, 0.0)

	var bob: float = 0.0
	if _anim != null:
		_animate_sheets(moving, vel, ratio)
	else:
		bob = _animate_fallback(delta, moving, speed, ratio)

	var bk: float = _body_kick * _body_kick
	var aim: Vector2 = player.aim_direction
	_root.position = Vector2(0.0, bob) - aim * _body_kick_px * bk - aim * 2.0 * _hit_t
	_root.rotation = _lean
	_root.scale = Vector2(1.0 + _sq, 1.0 - _sq)
	# L'arme suit le rebond et le recul du corps, sans son écrasement (qui la déformerait).
	_weapon_pivot.position = Player.hand_offset(Vector2.from_angle(_weapon_angle), hand_height, hand_radius) + _root.position
	_shadow.scale = Vector2(1.0 + _sq * 0.5 - bob * 0.01, 1.0)

	weapon_view.animate(delta)
	if _gadget_hand_left > 0.0:
		_gadget_hand_left -= delta
		if _gadget_hand_left <= 0.0:
			_gadget_hand.visible = false

	if moving and _turn_dust:
		_check_turn(delta, vel, ratio)

	# Flash blanc (shader) + clignotement d'invulnérabilité : seulement si la valeur change.
	var fa: float = clampf(_flash_left / maxf(_hit_flash_time, 0.001), 0.0, 1.0)
	if fa != _last_flash:
		_last_flash = fa
		if _body.material == _flash_mat and _flash_mat != null:
			_flash_mat.set_shader_parameter("flash_amount", fa)
		else:
			_body.self_modulate = Color(1.0 + fa * 2.0, 1.0 + fa * 2.0, 1.0 + fa * 2.0)
	var alpha: float = 1.0
	if not alive:
		alpha = _corpse_alpha  # cadavre bien visible (séquence de mort : DeathOverlay)
	elif hidden:
		alpha = player.hidden_alpha
	elif player.is_invulnerable() and _flash_left <= 0.0:
		alpha = 0.45 if int(player.get_invulnerable_left() * 20.0) % 2 == 0 else 1.0
	if alpha != _last_alpha:
		_last_alpha = alpha
		_root.modulate.a = alpha
		_weapon_pivot.modulate.a = alpha


func _animate_sheets(moving: bool, vel: Vector2, ratio: float) -> void:
	if _hit_lock > 0.0:
		return
	var base: StringName = &"idle"
	var reverse: bool = false
	var dir_index: int = facing_index
	if moving:
		base = &"run"
		if _anims.has(&"walk") and ratio < 0.5:
			base = &"walk"
		if player.is_aiming() and vel.length_squared() > 1.0:
			var d: float = vel.normalized().dot(player.aim_direction)
			if d < _backpedal_dot:
				if _anims.has(&"backpedal"):
					base = &"backpedal"
				else:
					reverse = true  # course jouée à l'envers face à la visée
			elif absf(d) < 0.4 and _anims.has(&"strafe"):
				base = &"strafe"
	if not _anims.has(base):
		base = &"idle"
	var anim: StringName = (_anims[base] as Array)[dir_index]
	if anim != _current_anim:
		_current_anim = anim
		current_base = base
		_anim.play(anim)
	var sc: float = 1.0
	if moving:
		sc = clampf(ratio, _anim_speed_min, _anim_speed_max)
		if reverse:
			sc = -sc
	if absf(_anim.speed_scale - sc) > 0.02:
		_anim.speed_scale = sc


func _animate_fallback(delta: float, moving: bool, speed: float, ratio: float) -> float:
	var y: float = 0.0
	if moving:
		var prev: float = _walk_phase
		_walk_phase += speed * delta / maxf(_stride_px, 1.0) * PI
		var s: float = absf(sin(_walk_phase))
		y = -s * _bounce_px * clampf(ratio, 0.3, 1.0)
		_sq += (1.0 - s) * _squash_walk * ratio * 0.15
		if _footstep_dust and floori(prev / PI) != floori(_walk_phase / PI):
			_footstep(Vector2.ZERO, 1.0)
		_set_svg_frame(1 if fmod(_walk_phase, TAU) < PI else 2)
		current_base = &"run"
	else:
		_walk_phase = 0.0
		_breath += delta
		_sq += sin(_breath * 2.6) * 0.0006
		_set_svg_frame(0)
		current_base = &"idle"
	if _svg != null:
		var face_left: bool = facing_index >= 3 and facing_index <= 5
		if _svg.flip_h != face_left:
			_svg.flip_h = face_left
	return y


func _set_svg_frame(frame: int) -> void:
	if _svg == null or frame == _svg_frame:
		return
	_svg_frame = frame
	var idx: int = frame if frame < _svg_tex.size() else 0
	_svg.texture = _svg_tex[idx]


func _on_frame_changed() -> void:
	if not _footstep_dust or _anim == null:
		return
	if current_base != &"run" and current_base != &"backpedal" and current_base != &"walk" and current_base != &"strafe":
		return
	if _step_frames.has(_anim.frame):
		_footstep(Vector2.ZERO, 1.0)


## Petite bouffée de poussière aux pieds (dans CombatFx, poolée).
func _footstep(extra_vel: Vector2, size_mult: float) -> void:
	var fx := CombatFx.get_or_create(get_tree())
	if fx == null:
		return
	if fx.is_low() and randf() < 0.5:
		return
	var v: Vector2 = -player.velocity * 0.12 + extra_vel
	fx.dust_puff(player.global_position + Vector2(randf_range(-5.0, 5.0), -1.0), v + Vector2(0.0, -8.0),
		3.5 * size_mult, 0.5)


## Virage brusque à pleine vitesse : traînée de poussière (limitée par un délai).
func _check_turn(delta: float, vel: Vector2, ratio: float) -> void:
	_turn_sample -= delta
	if _turn_sample > 0.0:
		return
	_turn_sample = 0.08
	var dir: Vector2 = vel.normalized()
	if _turn_ref != Vector2.ZERO and ratio > 0.55 and _turn_cooldown <= 0.0 and dir.dot(_turn_ref) < _turn_dot:
		_turn_cooldown = 0.25
		var fx := CombatFx.get_or_create(get_tree())
		if fx != null:
			for i: int in fx.count(4, 2):
				fx.dust_puff(player.global_position + _turn_ref * float(i) * -5.0 + Vector2(0.0, -1.0),
					_turn_ref * randf_range(40.0, 90.0) + Vector2(0.0, -10.0), 4.0 + float(i), 0.5)
	_turn_ref = dir


## Orientation 8 voies (visée si on vise, sinon mouvement) + arme tenue.
## Arme : vers la visée quand on vise ; sinon dans le sens de la marche (même référence que le
## corps, la vitesse réelle, pour qu'arme et corps tournent ensemble) ; à l'arrêt, elle garde sa
## direction. L'angle affiché rejoint la cible en douceur (rapide en visée, plus doux en marche),
## le retournement gauche/droite et le passage derrière le corps ont une hystérésis.
## `force` : tout est recalé immédiatement (apparition, sortie de cachette).
func update_facing(force: bool, delta: float = 0.0) -> void:
	var aim: Vector2 = player.aim_direction
	var aiming: bool = player.is_aiming()
	var moving: bool = player.is_moving()
	var facing_vec: Vector2 = aim
	if not aiming and moving:
		facing_vec = player.velocity
	facing_index = Player.dir8_index(facing_vec, -1 if force else facing_index, _dir_hysteresis)
	var want: Vector2 = aim
	if not aiming:
		want = player.velocity if moving and player.velocity.length_squared() > 1.0 else Vector2.from_angle(_weapon_angle)
		if force:
			want = aim
	var target: float = want.angle()
	if force or delta <= 0.0:
		_weapon_angle = target
	else:
		_weapon_angle = smooth_angle(_weapon_angle, target, _weapon_turn_aim if aiming else _weapon_turn_move, delta)
	var dir: Vector2 = Vector2.from_angle(_weapon_angle)
	_weapon_pivot.rotation = _weapon_angle
	_weapon_flip = flip_sign(0.0 if force else _weapon_flip, dir.x, _weapon_flip_dead)
	if _weapon_pivot.scale.y != _weapon_flip:
		_weapon_pivot.scale = Vector2(1.0, _weapon_flip)
	if force:
		_weapon_pivot.position = Player.hand_offset(dir, hand_height, hand_radius)
	# Visée vers le haut : l'arme passe derrière le corps (hystérésis : pas de clignotement).
	var behind: bool = dir.y < (_weapon_behind_out if _weapon_behind and not force else _weapon_behind_in)
	if force or behind != _weapon_behind:
		_weapon_behind = behind
		_weapon_pivot.z_index = -1 if behind else 1
	var show: bool = player.is_alive() and not player.is_hidden()
	if _weapon_pivot.visible != show:
		_weapon_pivot.visible = show
	_aim_marker_rot.rotation = aim.angle()
	if _aim_marker.visible != show:
		_aim_marker.visible = show
	_update_cone()


## Logique pure : angle `cur` rapproché de `target` (approche exponentielle, chemin le plus court).
static func smooth_angle(cur: float, target: float, rate: float, delta: float) -> float:
	if rate <= 0.0:
		return target
	return wrapf(lerp_angle(cur, target, 1.0 - exp(-rate * delta)), -PI, PI)


## Logique pure : sens du retournement vertical de l'arme (1 = canon à droite, -1 = à gauche).
## `prev` = 0 : aucun historique. Bascule seulement au-delà de ±`dead` (composante x de la direction).
static func flip_sign(prev: float, x: float, dead: float) -> float:
	if prev == 0.0:
		return -1.0 if x < 0.0 else 1.0
	if prev > 0.0 and x < -dead:
		return -1.0
	if prev < 0.0 and x > dead:
		return 1.0
	return prev


## Écarte les traits du cône selon l'imprécision effective (pas de redessin, seuil 0,25°).
func _update_cone() -> void:
	if _cone_l == null or not player.has_method(&"get_current_spread"):
		return
	var deg: float = minf(float(player.call(&"get_current_spread")) * Balance.get_float("player", "spread_cone_visual_mult", 1.6),
		Balance.get_float("player", "spread_cone_visual_max", 28.0))
	if absf(deg - _cone_deg) < 0.25:
		return
	_cone_deg = deg
	var show: bool = deg >= 0.5
	_cone_l.visible = show
	_cone_r.visible = show
	_cone_l.rotation = -deg_to_rad(deg)
	_cone_r.rotation = deg_to_rad(deg)


## Bout du canon (relatif aux pieds) pour une visée `dir` — calcul logique, sans recul.
func muzzle_offset(dir: Vector2) -> Vector2:
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var flip: float = -1.0 if d.x < 0.0 else 1.0
	var m: Vector2 = weapon_view.muzzle_local
	return Player.hand_offset(d, hand_height, hand_radius) + Vector2(m.x, m.y * flip).rotated(d.angle())


## Angle affiché de l'arme (radians, lissé) — debug et tests.
func get_weapon_angle() -> float:
	return _weapon_angle


## Sens du retournement de l'arme (1 = canon à droite, -1 = à gauche) — debug et tests.
func get_weapon_flip() -> float:
	return _weapon_flip


## Position de la main (pivot), relative aux pieds.
func hand_position() -> Vector2:
	return _weapon_pivot.position


# --- Dessins (une fois ou sur changement) -------------------------------------------

func _draw_shadow() -> void:
	_shadow.draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.42))
	_shadow.draw_circle(Vector2.ZERO, 17.0, COL_SHADOW)
	_shadow.draw_circle(Vector2.ZERO, 12.0, Color(COL_SHADOW, COL_SHADOW.a * 0.6))


func _draw_cone_edge(_side: int) -> void:
	var c: Node2D = _cone_l if _side == 0 else _cone_r
	c.draw_line(Vector2(26, 0), Vector2(44, 0), Color(COL_AIM, 0.18), 5.0, true)
	c.draw_line(Vector2(27, 0), Vector2(43, 0), Color(COL_AIM, 0.75), 2.0, true)


func _draw_aim_marker() -> void:
	var c: Node2D = _aim_marker_rot
	c.draw_colored_polygon(PackedVector2Array([Vector2(34, 0), Vector2(22, -10), Vector2(22, 10)]), Color(COL_AIM, 0.3))
	c.draw_colored_polygon(PackedVector2Array([Vector2(31, 0), Vector2(23, -6), Vector2(23, 6)]), COL_AIM)


func _draw_hp_bar() -> void:
	if player == null or player.is_hidden():
		return
	var c: Node2D = _hp_bar
	var w: float = 40.0
	var h: float = 5.0
	var top_left := Vector2(-w * 0.5, 0.0)
	var ratio: float = clampf(player.hp / maxf(player.max_hp, 1.0), 0.0, 1.0)
	c.draw_rect(Rect2(top_left - Vector2(1.5, 1.5), Vector2(w + 3, h + 3)), Color(0.07, 0.1, 0.18, 0.9))
	c.draw_rect(Rect2(top_left, Vector2(w, h)), Color(0.25, 0.05, 0.07))
	var hp_col: Color = Color(0.35, 0.9, 0.35).lerp(Color(0.95, 0.2, 0.15), 1.0 - ratio)
	c.draw_rect(Rect2(top_left, Vector2(w * ratio, h)), hp_col)


func _draw_reload_ring() -> void:
	if _reload_step < 0:
		return
	var c: Node2D = _reload_ring
	var p: float = float(_reload_step) / 32.0
	c.draw_circle(Vector2.ZERO, 11.0, Color(0.07, 0.1, 0.18, 0.75), true, -1.0, true)
	c.draw_arc(Vector2.ZERO, 8.5, 0.0, TAU, 32, Color(1, 1, 1, 0.18), 3.0, true)
	if p > 0.0:
		c.draw_arc(Vector2.ZERO, 8.5, -PI * 0.5, -PI * 0.5 + TAU * p, 32, Color(1.0, 0.82, 0.3), 3.0, true)
	# Petite cartouche au centre.
	c.draw_rect(Rect2(-1.5, -4.0, 3.0, 7.0), Color(1.0, 0.82, 0.3, 0.9))


## Personnage simple de repli (aucune planche) : jambes, gilet tactique, tête, sac.
func _draw_placeholder_hero(c: Node2D) -> void:
	var skin := Color(0.93, 0.76, 0.6)
	var vest := Color(0.27, 0.33, 0.25)
	var dark := Color(0.1, 0.12, 0.16)
	c.draw_rect(Rect2(-8, -16, 6, 16), Color(0.22, 0.24, 0.3))
	c.draw_rect(Rect2(2, -16, 6, 16), Color(0.22, 0.24, 0.3))
	c.draw_rect(Rect2(-13, -38, 7, 18), Color(0.45, 0.32, 0.2))
	c.draw_rect(Rect2(-10, -40, 20, 26), vest)
	c.draw_rect(Rect2(-10, -40, 20, 26), dark, false, 1.5)
	c.draw_circle(Vector2(0, -47), 8.0, skin, true, -1.0, true)
	c.draw_arc(Vector2(0, -47), 8.0, 0.0, TAU, 20, dark, 1.5, true)
	c.draw_rect(Rect2(-8, -55, 16, 5), Color(0.3, 0.22, 0.15))
