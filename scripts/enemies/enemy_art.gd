class_name EnemyArt
extends RefCounted
## Planches 3D pré-rendues des ennemis (art/blender/build_enemies.py) :
##   assets/sprites/enemies/<kind>/<kind>_frames.tres (SpriteFrames, animations <anim>_<dir>)
##   assets/sprites/enemies/<kind>/<kind>_meta.json   (cadre, pieds, échelle, fps, canon, cadavre)
## Atlas rogné : les AtlasTexture ont une marge qui restaure le cadre complet (frame_size).
## Tout est mis en cache au premier accès (une seule lecture disque par kind et par partie).

const DIR := "res://assets/sprites/enemies/"
## Ordre = angle / 45° (0 = est, sens horaire à l'écran : y vers le bas).
const DIR_NAMES: Array[String] = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]

static var _cache: Dictionary = {}


## Vrai si le kind a des planches 3D.
static func has_sheet(kind: StringName) -> bool:
	return not entry(kind).is_empty()


## {"frames": SpriteFrames, "meta": Dictionary, "scale": float, "feet": Vector2, "frame": Vector2}
## ou {} si le kind n'a pas de planches.
static func entry(kind: StringName) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var out := {}
	var base := DIR + String(kind) + "/" + String(kind)
	var frames_path := base + "_frames.tres"
	var meta_path := base + "_meta.json"
	if ResourceLoader.exists(frames_path):
		var frames := load(frames_path) as SpriteFrames
		# Méta embarquée dans la ressource (exports : les .json n'y sont pas), sinon le .json.
		var meta: Variant = frames.get_meta(&"enemy_meta", null) if frames != null else null
		if not (meta is Dictionary) and FileAccess.file_exists(meta_path):
			meta = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if frames != null and meta is Dictionary:
			var m: Dictionary = meta
			var fs := _vec(m.get("frame_size"), Vector2(192, 192))
			out = {
				"frames": frames,
				"meta": m,
				"frame": fs,
				"feet": _vec(m.get("feet_offset"), Vector2(fs.x * 0.5, fs.y * 0.8)),
				"scale": float(m.get("display_height", fs.y)) / maxf(fs.y, 1.0),
			}
	_cache[kind] = out
	return out


static func _vec(v: Variant, def: Vector2) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return def


## Index de direction (0..7) le plus proche d'un vecteur (repère écran).
static func dir_index(v: Vector2) -> int:
	if v.length_squared() < 0.0001:
		return 2
	return wrapi(roundi(v.angle() / (PI * 0.25)), 0, 8)


static func dir_name(v: Vector2) -> String:
	return DIR_NAMES[dir_index(v)]


## Index de direction avec hystérésis : ne change que si l'écart dépasse 22,5° + `margin_deg`.
static func dir_index_sticky(v: Vector2, current: int, margin_deg: float = 9.0) -> int:
	if v.length_squared() < 0.0001 or current < 0:
		return dir_index(v) if current < 0 else current
	var cur_angle := float(current) * PI * 0.25
	if absf(angle_difference(cur_angle, v.angle())) <= deg_to_rad(22.5 + margin_deg):
		return current
	return dir_index(v)


## Nombre d'images d'une animation (meta), 1 si inconnue.
static func frame_count(kind: StringName, anim: String) -> int:
	var e := entry(kind)
	if e.is_empty():
		return 1
	return int((e["meta"] as Dictionary).get("frames", {}).get(anim, 1))


static func fps(kind: StringName, anim: String) -> float:
	var e := entry(kind)
	if e.is_empty():
		return 10.0
	return float((e["meta"] as Dictionary).get("fps", {}).get(anim, 10.0))


static func has_anim(kind: StringName, anim: String) -> bool:
	var e := entry(kind)
	return not e.is_empty() and (e["frames"] as SpriteFrames).has_animation(anim + "_e")


## Texture du cadavre (dernière image de la mort) pour une direction.
static func corpse_texture(kind: StringName, dir: String) -> Texture2D:
	var e := entry(kind)
	if e.is_empty():
		return null
	var sf: SpriteFrames = e["frames"]
	var an := "death_" + dir
	if not sf.has_animation(an):
		return null
	return sf.get_frame_texture(an, sf.get_frame_count(an) - 1)


## Bout du canon (repère local de l'ennemi, pieds = origine) pour une direction, sinon Vector2.INF.
static func muzzle_local(kind: StringName, dir: String) -> Vector2:
	var e := entry(kind)
	if e.is_empty():
		return Vector2.INF
	var mz: Variant = (e["meta"] as Dictionary).get("muzzle_px", {}).get(dir)
	if not (mz is Array):
		return Vector2.INF
	return (_vec(mz, Vector2.ZERO) - (e["feet"] as Vector2)) * float(e["scale"])


## Hauteur (unités monde) du haut de la tête au-dessus des pieds.
static func head_height(kind: StringName) -> float:
	var e := entry(kind)
	if e.is_empty():
		return 60.0
	var m: Dictionary = e["meta"]
	return ((e["feet"] as Vector2).y - float(m.get("head_px", 40.0))) * float(e["scale"])


static func clear_cache() -> void:
	_cache.clear()
