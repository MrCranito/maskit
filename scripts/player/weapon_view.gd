class_name WeaponView
extends Node2D
## Arme tenue par le joueur (purement visuelle). Enfant du pivot de main (tourné vers la
## visée, retourné verticalement quand on vise à gauche).
##   - Sprite : assets/sprites/weapons/<sprite_id>.png + .json (grip, muzzle, scale ; canon
##     vers la droite), sinon <category>.png, sinon silhouette dessinée en code par catégorie.
##   - Skin d'arme : WeaponSkin.apply(item, Profile.get_weapon_skin(category)) (skin propre à l'arme
##     prioritaire) ; `use_skin_ids` : skins imposés (id d'arme → id de skin), pour une arme qui
##     n'est pas la nôtre (coéquipier) — les skins du profil local ne s'appliquent alors jamais.
##   - `icon_mode` : image de l'icône Blender (assets/ui/weapons/<id>.png + .json grip/muzzle), plus
##     grande et vue presque de profil, pour tenir l'arme en grand dans les menus (LobbyHero) ;
##     échelle 1 = 1 px d'icône (le parent la met à l'échelle, voir held_span).
##   - Recul par catégorie (profil [player_fx] cat_<category>) : recul le long du canon,
##     relevé du canon, vibration continue (mitrailleuse).
##   - Éclair de bouche par catégorie (étoile, cône, long, souffle arrière, bouffée), visible
##     1 à 2 images, dessiné une fois par changement d'arme (aucun redessin par tir).
##   - Rechargement : arme basculée vers le bas + petit à-coup d'insertion en fin de cycle.
##   - Changement d'arme : l'arme descend puis remonte (échange du visuel au point bas).
## Par frame : uniquement des affectations de propriétés.

const WEAPON_SPRITE_DIR := "res://assets/sprites/weapons/"
const WEAPON_ICON_DIR := "res://assets/ui/weapons/"

## Profils de ressenti par défaut (repli si [player_fx] cat_<category> est absent).
const DEFAULT_PROFILES: Dictionary = {
	&"pistol": {"rot_deg": 9.0, "recover": 0.1, "body_px": 1.0, "flash": "star", "flash_frames": 1,
		"zoom_kick": 0.0, "vibrate_px": 0.0, "smoke": 0.0, "shell_delay": 0.0, "sfx": "pistol_shot_light", "mag_drop": true},
	&"revolver": {"rot_deg": 16.0, "recover": 0.16, "body_px": 1.5, "flash": "star", "flash_frames": 2,
		"zoom_kick": 0.005, "vibrate_px": 0.0, "smoke": 0.5, "shell_delay": -1.0, "sfx": "revolver_shot", "mag_drop": false},
	&"smg": {"rot_deg": 4.0, "recover": 0.06, "body_px": 0.6, "flash": "star", "flash_frames": 1,
		"zoom_kick": 0.0, "vibrate_px": 1.0, "smoke": 0.0, "shell_delay": 0.0, "sfx": "pistol_shot_light", "mag_drop": true},
	&"shotgun": {"rot_deg": 20.0, "recover": 0.26, "body_px": 4.0, "flash": "cone", "flash_frames": 2,
		"zoom_kick": 0.015, "vibrate_px": 0.0, "smoke": 1.0, "shell_delay": 0.22, "sfx": "shotgun_blast", "mag_drop": false},
	&"rifle": {"rot_deg": 5.0, "recover": 0.08, "body_px": 1.0, "flash": "star", "flash_frames": 1,
		"zoom_kick": 0.0, "vibrate_px": 0.6, "smoke": 0.0, "shell_delay": 0.0, "sfx": "rifle_shot", "mag_drop": true},
	&"sniper": {"rot_deg": 24.0, "recover": 0.4, "body_px": 5.0, "flash": "long", "flash_frames": 2,
		"zoom_kick": 0.03, "vibrate_px": 0.0, "smoke": 1.0, "shell_delay": 0.35, "sfx": "rifle_shot", "mag_drop": true},
	&"lmg": {"rot_deg": 3.0, "recover": 0.07, "body_px": 1.2, "flash": "star", "flash_frames": 1,
		"zoom_kick": 0.0, "vibrate_px": 2.2, "smoke": 0.0, "shell_delay": 0.0, "sfx": "rifle_shot", "mag_drop": true},
	&"rocket_launcher": {"rot_deg": 10.0, "recover": 0.45, "body_px": 9.0, "flash": "backblast", "flash_frames": 2,
		"zoom_kick": 0.04, "vibrate_px": 0.0, "smoke": 1.6, "shell_delay": -1.0, "sfx": "gun_shot_alt", "mag_drop": false},
	&"gadget": {"rot_deg": 0.0, "recover": 0.2, "body_px": -3.0, "flash": "none", "flash_frames": 1,
		"zoom_kick": 0.0, "vibrate_px": 0.0, "smoke": 0.0, "shell_delay": -1.0, "sfx": "blade_swing", "mag_drop": false},
	&"grenade_launcher": {"rot_deg": 14.0, "recover": 0.3, "body_px": 4.0, "flash": "puff", "flash_frames": 2,
		"zoom_kick": 0.015, "vibrate_px": 0.0, "smoke": 1.0, "shell_delay": -1.0, "sfx": "gun_shot_alt", "mag_drop": false},
}

const COL_FLASH_OUT := Color(1.0, 0.6, 0.16, 0.9)
const COL_FLASH_MID := Color(1.0, 0.85, 0.35, 0.95)
const COL_FLASH_IN := Color(1.0, 0.98, 0.85, 1.0)

var weapon: WeaponData = null
var profile: Dictionary = {}
## Icône Blender au lieu du sprite tenu (menus) : à fixer avant set_weapon.
var icon_mode: bool = false
## Skins imposés (coéquipier) : String(id d'arme) → String(id de skin) ; voir set_skin_ids.
var use_skin_ids: bool = false
var skin_ids: Dictionary = {}
## Bout du canon et arrière de l'arme dans le repère de la main (px monde).
var muzzle_local: Vector2 = Vector2(22.0, -3.0)
var rear_local: Vector2 = Vector2(-6.0, 0.0)

var _holder: Node2D = null
var _item: CanvasItem = null
var _flash: Node2D = null
var _flash_shape: String = "star"
var _flash_scale: float = 1.0
var _flash_frames_left: int = 0
var _kick: float = 0.0
var _kick_time: float = 0.1
var _vibrate: float = 0.0
var _switch_t: float = 0.0
var _switch_time: float = 0.25
var _pending_weapon: WeaponData = null
var _pending_valid: bool = false
var _reload_amount: float = 0.0
var _reload_progress: float = -1.0
var _slam: float = 0.0
var _slam_done: bool = false
var _sprite_cache: Dictionary = {}


func _init() -> void:
	name = "WeaponView"
	_holder = Node2D.new()
	_holder.name = "Holder"
	add_child(_holder)
	_flash = Node2D.new()
	_flash.name = "MuzzleFlash"
	_flash.visible = false
	_flash.draw.connect(_draw_flash)


func _ready() -> void:
	_switch_time = Balance.get_float("player_fx", "switch_anim_time", 0.25)


## Profil de ressenti d'une catégorie ([player_fx] cat_<category>, complété par le défaut).
static func profile_for(category: StringName) -> Dictionary:
	var base: Dictionary = (DEFAULT_PROFILES.get(category, DEFAULT_PROFILES[&"pistol"]) as Dictionary).duplicate()
	var cfg: Variant = Balance.get_value("player_fx", "cat_" + String(category), {})
	if cfg is Dictionary:
		base.merge(cfg as Dictionary, true)
	return base


## Change d'arme : immédiat si `animate` est faux, sinon descente → échange → remontée.
func set_weapon(w: WeaponData, animate: bool) -> void:
	if not animate or weapon == null or not is_inside_tree():
		_apply_weapon(w)
		_switch_t = 0.0
		return
	_pending_weapon = w
	_pending_valid = true
	_switch_t = maxf(_switch_time, 0.01)


func is_switching() -> bool:
	return _switch_t > 0.0


func _apply_weapon(w: WeaponData) -> void:
	weapon = w
	_pending_valid = false
	_pending_weapon = null
	profile = profile_for(w.category if w != null else WeaponData.CAT_PISTOL)
	_kick_time = maxf(float(profile.get("recover", 0.1)), 0.02)
	if _item != null:
		# Libération immédiate (hors arbre, aucun appel en cours dessus) : pas d'orphelin.
		_item.get_parent().remove_child(_item)
		_item.free()
		_item = null
	if _flash.get_parent() == null:
		# Hors du holder : l'éclair reste dans l'axe du tir malgré le relevé du canon.
		add_child(_flash)
	if w == null:
		return
	var tex_info: Dictionary = _find_sprite(w, WEAPON_ICON_DIR) if icon_mode else {}
	if tex_info.is_empty():
		tex_info = _find_sprite(w)
	if not tex_info.is_empty():
		var tex: Texture2D = tex_info["tex"]
		var meta: Dictionary = tex_info["meta"]
		var tsize := Vector2(tex.get_size())
		var grip: Vector2 = _vec2_from(meta.get("grip"), Vector2(tsize.x * 0.2, tsize.y * 0.6))
		var muzzle: Vector2 = _vec2_from(meta.get("muzzle"), Vector2(tsize.x, tsize.y * 0.3))
		var sc: float = float(meta.get("scale", 26.0 / maxf(tsize.x, 1.0)))
		if icon_mode:
			sc = 1.0  # le parent normalise la taille (held_span / muzzle_local)
		var spr := Sprite2D.new()
		spr.name = "WeaponSprite"
		spr.texture = tex
		spr.centered = false
		spr.offset = -grip
		spr.scale = Vector2(sc, sc)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if icon_mode else CanvasItem.TEXTURE_FILTER_LINEAR
		_item = spr
		muzzle_local = (muzzle - grip) * sc
		rear_local = Vector2(-grip.x * sc, 0.0)
	else:
		var drawn := Node2D.new()
		drawn.name = "WeaponDrawn"
		var cat: StringName = w.category
		drawn.draw.connect(func() -> void: draw_weapon_shape(drawn, cat))
		_item = drawn
		muzzle_local = shape_muzzle(cat)
		rear_local = shape_rear(cat)
	_holder.add_child(_item)
	_apply_skin()
	_flash_shape = String(profile.get("flash", "star"))
	_flash_scale = maxf(w.muzzle_flash_scale, 0.1)
	_flash.position = Vector2.ZERO
	_flash.z_index = 1
	_flash.queue_redraw()


func _weapon_skin(category: StringName) -> SkinData:
	var prof: Node = get_node_or_null(^"/root/Profile") if is_inside_tree() else null
	if prof != null and prof.has_method("get_weapon_skin"):
		return prof.call("get_weapon_skin", category) as SkinData
	return null


## Skins imposés (coéquipier : id d'arme → id de skin) ; l'arme affichée est rhabillée tout de suite.
func set_skin_ids(ids: Dictionary) -> void:
	use_skin_ids = true
	skin_ids = ids.duplicate()
	_apply_skin()


## Skin de l'arme affichée : imposé (use_skin_ids), sinon celui du profil local.
func _apply_skin() -> void:
	if _item == null or weapon == null:
		return
	if use_skin_ids:
		WeaponSkin.apply(_item, forced_skin_for(weapon, skin_ids), weapon.id, false)
	else:
		WeaponSkin.apply(_item, _weapon_skin(weapon.category))


## Logique pure : skin imposé pour cette arme (null si aucun, inconnu ou fait pour une autre arme).
static func forced_skin_for(w: WeaponData, ids: Dictionary) -> SkinData:
	if w == null:
		return null
	var sid := str(ids.get(String(w.id), ""))
	if sid.is_empty():
		return null
	var s := SkinData.get_skin(StringName(sid))
	return s if s != null and s.kind == SkinData.KIND_WEAPON and s.applies_to(w.category, w.id) else null


## Id de skin affiché sur l'arme (« » si aucun) — debug et tests.
func get_skin_id() -> String:
	return str(_item.get_meta(WeaponSkin.META_SKIN, "")) if _item != null else ""


## Rectangle de l'image de l'arme dans le repère de ce nœud (hors recul) ; silhouette dessinée :
## boîte approximative (arrière → bout du canon).
func get_item_rect() -> Rect2:
	if _item is Sprite2D:
		var spr := _item as Sprite2D
		var ts := Vector2(spr.texture.get_size()) if spr.texture != null else Vector2.ZERO
		return Rect2(spr.offset * spr.scale, ts * spr.scale)
	if _item != null:
		return Rect2(Vector2(rear_local.x, -12.0), Vector2(muzzle_local.x - rear_local.x, 24.0))
	return Rect2()


## Image affichée (null : silhouette dessinée) — debug et tests.
func get_texture() -> Texture2D:
	return (_item as Sprite2D).texture if _item is Sprite2D else null


## Texture + métadonnées dans `dir` : <sprite_id>, puis <category>, puis l'id sans préfixe starter_.
func _find_sprite(w: WeaponData, dir: String = WEAPON_SPRITE_DIR) -> Dictionary:
	for cand: String in sprite_candidates(w):
		var key := dir + cand
		if _sprite_cache.has(key):
			var cached: Dictionary = _sprite_cache[key]
			if not cached.is_empty():
				return cached
			continue
		var info := load_sprite(dir, cand)
		_sprite_cache[key] = info
		if not info.is_empty():
			return info
	return {}


static func sprite_candidates(w: WeaponData) -> Array[String]:
	var cands: Array[String] = []
	for c: String in [String(w.get_sprite_id()), String(w.category), String(w.id).trim_prefix("starter_")]:
		if not c.is_empty() and not cands.has(c):
			cands.append(c)
	return cands


## {tex, meta} de <dir><name>.png + .json, {} si absent.
static func load_sprite(dir: String, sprite_name: String) -> Dictionary:
	var png: String = dir + sprite_name + ".png"
	if not ResourceLoader.exists(png):
		return {}
	var tex := load(png) as Texture2D
	return {"tex": tex, "meta": _read_json(dir + sprite_name + ".json")} if tex != null else {}


## Longueur poignée → bout du canon de l'arme EN JEU (unités monde : sprite tenu × son échelle,
## sinon silhouette dessinée). Sert à garder les proportions de l'arme quand on l'affiche en grand.
static func held_span(w: WeaponData) -> float:
	if w == null:
		return 0.0
	for cand: String in sprite_candidates(w):
		var info := load_sprite(WEAPON_SPRITE_DIR, cand)
		if info.is_empty():
			continue
		var tex: Texture2D = info["tex"]
		var meta: Dictionary = info["meta"]
		var tsize := Vector2(tex.get_size())
		var grip: Vector2 = _vec2_from(meta.get("grip"), Vector2(tsize.x * 0.2, tsize.y * 0.6))
		var muzzle: Vector2 = _vec2_from(meta.get("muzzle"), Vector2(tsize.x, tsize.y * 0.3))
		return (muzzle - grip).length() * float(meta.get("scale", 26.0 / maxf(tsize.x, 1.0)))
	return shape_muzzle(w.category).length()


# --- Événements -------------------------------------------------------------------

## Tir : recul (le profil de la catégorie fixe la forme, l'arme fixe l'amplitude).
func on_fired() -> void:
	_kick = 1.0
	_vibrate = 1.0
	# +1 : le tir a lieu en physique, avant le _process de la même image (qui décrémente).
	_flash_frames_left = maxi(int(profile.get("flash_frames", 1)), 1) + 1
	_flash.visible = true
	var s: float = randf_range(0.85, 1.15)
	_flash.scale = Vector2(s, randf_range(0.85, 1.15) * (1.0 if randf() < 0.5 else -1.0))


## Progression du rechargement (0..1), < 0 = pas de rechargement.
func set_reload(progress: float) -> void:
	if progress >= 0.0 and _reload_progress < 0.0:
		_slam_done = false
	if progress >= 0.85 and not _slam_done and _reload_progress >= 0.0:
		_slam_done = true
		_slam = 1.0
	_reload_progress = progress


# --- Animation (appelée par PlayerVisual._process) ------------------------------

func animate(delta: float) -> void:
	if _flash_frames_left > 0:
		_flash_frames_left -= 1
		if _flash_frames_left <= 0:
			_flash.visible = false
	_kick = maxf(_kick - delta / _kick_time, 0.0)
	_vibrate = maxf(_vibrate - delta * 6.0, 0.0)
	_slam = maxf(_slam - delta * 8.0, 0.0)
	var want_reload: float = 1.0 if _reload_progress >= 0.0 and _reload_progress < 0.92 else 0.0
	_reload_amount = move_toward(_reload_amount, want_reload, delta * 7.0)

	var sw: float = 0.0
	if _switch_t > 0.0:
		_switch_t = maxf(_switch_t - delta, 0.0)
		var half: float = _switch_time * 0.5
		if _pending_valid and _switch_t <= half:
			_apply_weapon(_pending_weapon)
		# 0 → 1 (point bas) → 0.
		sw = 1.0 - absf(_switch_t - half) / maxf(half, 0.001)
		sw = clampf(sw, 0.0, 1.0)

	var k: float = _kick * _kick
	var recoil_px: float = weapon.recoil_px if weapon != null else 4.0
	var rot_deg: float = float(profile.get("rot_deg", 8.0))
	var vib_px: float = float(profile.get("vibrate_px", 0.0)) * _vibrate
	var pos := Vector2(-recoil_px * k, 0.0)
	if vib_px > 0.0:
		pos += Vector2(randf_range(-vib_px, vib_px), randf_range(-vib_px, vib_px) * 0.6)
	var rot: float = -deg_to_rad(rot_deg) * k
	# Rechargement : canon basculé vers le bas, arme rapprochée ; à-coup d'insertion.
	rot += deg_to_rad(38.0) * _reload_amount - deg_to_rad(10.0) * _slam
	pos += Vector2(-3.0, 3.0) * _reload_amount
	# Changement d'arme : l'arme plonge hors du cadre de la main.
	rot += deg_to_rad(70.0) * sw
	pos += Vector2(-6.0, 10.0) * sw
	_holder.position = pos
	_holder.rotation = rot
	var a: float = 1.0 - sw * 0.6
	if not is_equal_approx(_holder.modulate.a, a):
		_holder.modulate.a = a


## Bout du canon dans le repère du pivot de main, recul compris (pour la fumée).
func get_muzzle_in_pivot() -> Vector2:
	return _holder.transform * muzzle_local


# --- Dessins (une fois par arme) --------------------------------------------------

func _draw_flash() -> void:
	var c: Node2D = _flash
	var m: Vector2 = muzzle_local
	var s: float = _flash_scale
	match _flash_shape:
		"none":
			return
		"cone":
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -4) * s, m + Vector2(26, -13) * s,
				m + Vector2(34, 0) * s, m + Vector2(26, 13) * s, m + Vector2(0, 4) * s]), Color(COL_FLASH_OUT, 0.75))
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -3) * s, m + Vector2(20, -7) * s,
				m + Vector2(26, 0) * s, m + Vector2(20, 7) * s, m + Vector2(0, 3) * s]), COL_FLASH_MID)
			c.draw_circle(m + Vector2(5, 0) * s, 5.0 * s, COL_FLASH_IN, true, -1.0, true)
		"long":
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -5) * s, m + Vector2(10, -3) * s,
				m + Vector2(44, 0) * s, m + Vector2(10, 3) * s, m + Vector2(0, 5) * s]), COL_FLASH_OUT)
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(2, -9) * s, m + Vector2(6, 0) * s,
				m + Vector2(2, 9) * s, m + Vector2(-1, 0) * s]), Color(COL_FLASH_OUT, 0.7))
			c.draw_line(m, m + Vector2(30, 0) * s, COL_FLASH_IN, 2.5 * s, true)
			c.draw_circle(m + Vector2(4, 0) * s, 4.5 * s, COL_FLASH_IN, true, -1.0, true)
		"backblast":
			c.draw_circle(m + Vector2(6, 0) * s, 9.0 * s, Color(COL_FLASH_OUT, 0.7), true, -1.0, true)
			c.draw_circle(m + Vector2(4, 0) * s, 5.0 * s, COL_FLASH_IN, true, -1.0, true)
			var r: Vector2 = rear_local
			c.draw_colored_polygon(PackedVector2Array([r + Vector2(0, -5) * s, r + Vector2(-30, -16) * s,
				r + Vector2(-40, 0) * s, r + Vector2(-30, 16) * s, r + Vector2(0, 5) * s]), Color(COL_FLASH_OUT, 0.8))
			c.draw_colored_polygon(PackedVector2Array([r + Vector2(0, -3) * s, r + Vector2(-20, -7) * s,
				r + Vector2(-26, 0) * s, r + Vector2(-20, 7) * s, r + Vector2(0, 3) * s]), COL_FLASH_MID)
		"puff":
			c.draw_circle(m + Vector2(7, 0) * s, 9.0 * s, Color(COL_FLASH_OUT, 0.55), true, -1.0, true)
			c.draw_circle(m + Vector2(12, -4) * s, 5.0 * s, Color(COL_FLASH_MID, 0.8), true, -1.0, true)
			c.draw_circle(m + Vector2(12, 4) * s, 5.0 * s, Color(COL_FLASH_MID, 0.8), true, -1.0, true)
			c.draw_circle(m + Vector2(4, 0) * s, 4.0 * s, COL_FLASH_IN, true, -1.0, true)
		_:
			# Étoile à 4 branches (la longue vers l'avant) + coeur.
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -7) * s, m + Vector2(5, -2.5) * s,
				m + Vector2(19, 0) * s, m + Vector2(5, 2.5) * s, m + Vector2(0, 7) * s, m + Vector2(2.5, 0) * s]), COL_FLASH_OUT)
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(1, -3.5) * s, m + Vector2(4, -1) * s,
				m + Vector2(12, 0) * s, m + Vector2(4, 1) * s, m + Vector2(1, 3.5) * s]), COL_FLASH_MID)
			c.draw_circle(m + Vector2(3, 0) * s, 3.6 * s, COL_FLASH_IN, true, -1.0, true)


## Bout du canon de la silhouette dessinée (poignée à l'origine).
static func shape_muzzle(cat: StringName) -> Vector2:
	match cat:
		&"revolver": return Vector2(24, -4)
		&"smg": return Vector2(25, -3.5)
		&"shotgun": return Vector2(36, -3)
		&"rifle": return Vector2(34, -3.5)
		&"sniper": return Vector2(46, -3.5)
		&"lmg": return Vector2(38, -3.5)
		&"rocket_launcher": return Vector2(30, -5)
		&"grenade_launcher": return Vector2(28, -4)
	return Vector2(19, -4)


static func shape_rear(cat: StringName) -> Vector2:
	match cat:
		&"rocket_launcher": return Vector2(-22, -5)
		&"shotgun", &"rifle", &"sniper", &"lmg": return Vector2(-14, -2)
	return Vector2(-4, -2)


## Silhouette de repli par catégorie (canon vers +X, poignée à l'origine, ≈ 20–50 px).
static func draw_weapon_shape(c: CanvasItem, cat: StringName) -> void:
	var dark := Color(0.12, 0.13, 0.16)
	var steel := Color(0.5, 0.53, 0.6)
	var black := Color(0.2, 0.21, 0.25)
	var wood := Color(0.48, 0.28, 0.13)
	var olive := Color(0.33, 0.38, 0.27)
	var hi := Color(0.85, 0.87, 0.92)
	match cat:
		&"revolver":
			c.draw_colored_polygon(PackedVector2Array([Vector2(-3, -4), Vector2(4, -4), Vector2(2, 6), Vector2(-5, 7)]), wood)
			c.draw_rect(Rect2(1, -7, 9, 6), steel)
			c.draw_circle(Vector2(7, -4), 3.6, Color(0.42, 0.44, 0.5), true, -1.0, true)
			c.draw_rect(Rect2(9, -5.5, 15, 3), steel)
			c.draw_line(Vector2(9, -5.5), Vector2(24, -5.5), hi, 1.0)
			c.draw_rect(Rect2(1, -7, 23, 6), dark, false, 1.0)
		&"smg":
			c.draw_rect(Rect2(-3, -2, 5, 8), black)
			c.draw_rect(Rect2(-4, -7, 22, 6), black)
			c.draw_rect(Rect2(6, -1, 4, 9), dark)
			c.draw_rect(Rect2(18, -5, 7, 3), steel)
			c.draw_line(Vector2(-4, -7), Vector2(18, -7), Color(0.45, 0.47, 0.52), 1.0)
			c.draw_rect(Rect2(-4, -7, 29, 6), dark, false, 1.0)
		&"shotgun":
			c.draw_colored_polygon(PackedVector2Array([Vector2(-16, -5), Vector2(-2, -6), Vector2(-1, 0), Vector2(-15, 3)]), wood)
			c.draw_rect(Rect2(-2, -7, 12, 6), black)
			c.draw_rect(Rect2(10, -6, 26, 3), steel)
			c.draw_rect(Rect2(12, -3, 16, 3.5), wood)
			c.draw_line(Vector2(10, -6), Vector2(36, -6), hi, 1.0)
			c.draw_rect(Rect2(-2, -7, 38, 7.5), dark, false, 1.0)
		&"rifle":
			c.draw_colored_polygon(PackedVector2Array([Vector2(-14, -6), Vector2(-2, -6), Vector2(-2, 0), Vector2(-13, 2)]), black)
			c.draw_rect(Rect2(-2, -8, 22, 7), black)
			c.draw_colored_polygon(PackedVector2Array([Vector2(6, -1), Vector2(11, -1), Vector2(13, 8), Vector2(8, 8)]), dark)
			c.draw_rect(Rect2(20, -6, 14, 3), steel)
			c.draw_rect(Rect2(4, -11, 8, 3), dark)
			c.draw_line(Vector2(-2, -8), Vector2(20, -8), Color(0.45, 0.47, 0.52), 1.0)
			c.draw_rect(Rect2(-2, -8, 36, 7), dark, false, 1.0)
		&"sniper":
			c.draw_colored_polygon(PackedVector2Array([Vector2(-16, -6), Vector2(-2, -6), Vector2(-2, 0), Vector2(-15, 3)]), olive)
			c.draw_rect(Rect2(-2, -8, 20, 7), olive)
			c.draw_rect(Rect2(18, -5.5, 28, 2.6), steel)
			c.draw_rect(Rect2(2, -13, 14, 4), dark)
			c.draw_circle(Vector2(16, -11), 2.6, Color(0.35, 0.75, 1.0), true, -1.0, true)
			c.draw_rect(Rect2(6, -1, 4, 6), dark)
			c.draw_line(Vector2(18, -5.5), Vector2(46, -5.5), hi, 1.0)
			c.draw_rect(Rect2(-2, -8, 20, 7), dark, false, 1.0)
		&"lmg":
			c.draw_colored_polygon(PackedVector2Array([Vector2(-14, -6), Vector2(-2, -7), Vector2(-2, 0), Vector2(-13, 2)]), black)
			c.draw_rect(Rect2(-2, -9, 24, 9), black)
			c.draw_rect(Rect2(4, 0, 11, 9), olive)
			c.draw_rect(Rect2(22, -6.5, 16, 4), steel)
			c.draw_line(Vector2(30, -3), Vector2(26, 6), dark, 1.5)
			c.draw_line(Vector2(30, -3), Vector2(34, 6), dark, 1.5)
			c.draw_rect(Rect2(-2, -9, 40, 9), dark, false, 1.0)
		&"rocket_launcher":
			c.draw_rect(Rect2(-22, -10, 50, 10), olive)
			c.draw_rect(Rect2(-24, -11, 5, 12), dark)
			c.draw_rect(Rect2(26, -11, 5, 12), dark)
			c.draw_rect(Rect2(0, 0, 4, 7), dark)
			c.draw_rect(Rect2(6, -15, 8, 5), dark)
			c.draw_circle(Vector2(31, -5), 3.0, Color(0.85, 0.25, 0.15), true, -1.0, true)
			c.draw_line(Vector2(-22, -10), Vector2(26, -10), Color(0.55, 0.62, 0.45), 1.0)
			c.draw_rect(Rect2(-22, -10, 48, 10), dark, false, 1.0)
		&"grenade_launcher":
			c.draw_colored_polygon(PackedVector2Array([Vector2(-12, -6), Vector2(-2, -6), Vector2(-2, 0), Vector2(-11, 2)]), black)
			c.draw_rect(Rect2(-2, -8, 8, 8), black)
			c.draw_circle(Vector2(10, -4), 7.0, olive, true, -1.0, true)
			c.draw_arc(Vector2(10, -4), 7.0, 0.0, TAU, 16, dark, 1.0, true)
			c.draw_rect(Rect2(16, -7.5, 12, 7), steel)
			c.draw_rect(Rect2(16, -7.5, 12, 7), dark, false, 1.0)
		_:
			# Pistolet compact.
			c.draw_colored_polygon(PackedVector2Array([Vector2(-2, -3), Vector2(4, -3), Vector2(2, 6), Vector2(-4, 6)]), black)
			c.draw_rect(Rect2(-3, -7, 22, 5), steel)
			c.draw_line(Vector2(-3, -7), Vector2(19, -7), hi, 1.0)
			c.draw_arc(Vector2(4, -1), 2.4, 0.0, PI, 8, dark, 1.2, true)
			c.draw_rect(Rect2(-3, -7, 22, 5), dark, false, 1.0)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _vec2_from(v: Variant, fallback: Vector2) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	if v is Dictionary and (v as Dictionary).has("x"):
		return Vector2(float(v["x"]), float(v.get("y", 0.0)))
	return fallback
