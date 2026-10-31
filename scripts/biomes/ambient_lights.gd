class_name AmbientLights
extends Node2D
## Éclairage d'ambiance animé et peu coûteux d'un étage (station spatiale, parking du centre
## commercial) : aucune PointLight2D, uniquement des halos additifs (sprite radial « glow » de
## l'atlas des décors du biome, ou dégradé radial de repli), dessinés une seule fois par groupe et animés par `modulate` :
##   - flicker : néons défaillants (sortis de la couche statique des lueurs) qui grésillent ;
##   - blink   : voyants (petits points vifs sur les panneaux muraux) qui clignotent ;
##   - alarm   : gyrophares rouges discrets, pulsation lente.
## Brouillard de guerre : la couche est sous le brouillard (z < 80), donc assombrie hors vue ;
## en plus, chaque lumière animée n'est dessinée que si sa case est visible du joueur
## (FogOfWar.is_cell_visible, test espacé de [ambient_lights] fog_refresh s) : rien ne
## clignote dans le brouillard. Réglages : balance.cfg [ambient_lights].
## Lumières : [position monde, rayon px, couleur, intensité, (option) point testé au brouillard].

const GROUP_FLICKER := &"flicker"
const GROUP_BLINK := &"blink"
const GROUP_ALARM := &"alarm"

var fog_refresh: float = 0.2
var flicker_speed: float = 9.0
var flicker_min: float = 0.15
var blink_speed: float = 1.3
var blink_duty: float = 0.55
var alarm_speed: float = 2.2
var alarm_min: float = 0.25
var alpha: float = 0.38

var _groups: Dictionary = {}  ## nom → Group
var _tex: Texture2D = null
var _region: Rect2 = Rect2()
static var _fallback: Texture2D = null
var _fog: Node = null
var _fog_lookups: int = 0
var _refresh_left: float = 0.0
var _t: float = 0.0


## Groupe de lumières d'une même animation : un seul nœud, un seul _draw (sous-ensemble visible).
class Group extends Node2D:
	var tex: Texture2D = null
	var region: Rect2 = Rect2()
	var lights: Array = []
	var shown: PackedByteArray = PackedByteArray()
	var core_scale: float = 0.35
	var alpha: float = 0.38
	var all_visible: bool = true

	func set_shown(mask: PackedByteArray) -> bool:
		if mask == shown:
			return false
		shown = mask
		queue_redraw()
		return true

	func _draw() -> void:
		if tex == null:
			return
		var reg := region if region.has_area() else Rect2(Vector2.ZERO, tex.get_size())
		for i: int in lights.size():
			if not all_visible and (i >= shown.size() or shown[i] == 0):
				continue
			var l: Array = lights[i]
			var p: Vector2 = l[0]
			var rad: float = l[1]
			var col: Color = l[2]
			var k: float = float(l[3])
			draw_texture_rect_region(tex, Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0), reg,
				Color(col, alpha * k))
			var cr: float = rad * core_scale
			draw_texture_rect_region(tex, Rect2(p - Vector2(cr, cr), Vector2(cr, cr) * 2.0), reg,
				Color(col.lightened(0.45), minf(alpha * k * 1.2, 1.0)))


## Crée la couche. `flicker`, `blink`, `alarm` : listes de lumières [pos, rayon, couleur, intensité].
## `tex` / `region` : sprite radial du halo (null = dégradé radial de repli).
static func create(tex: Texture2D, region: Rect2, flicker: Array, blink: Array, alarm: Array) -> AmbientLights:
	var al := AmbientLights.new()
	al.name = "AmbientLights"
	al._load_cfg()
	if tex == null:
		tex = fallback_texture()
		region = Rect2()
	al._tex = tex
	al._region = region
	al._add_group(GROUP_FLICKER, flicker, 0.35)
	al._add_group(GROUP_BLINK, blink, 0.45)
	al._add_group(GROUP_ALARM, alarm, 0.3)
	return al


## Sépare `glows` ([pos, rayon, couleur, intensité]) : un sur `every` des lueurs de rayon compris
## dans [min_radius, max_radius] devient un néon défaillant (déterministe selon `seed_value`).
## Renvoie [lueurs statiques, néons défaillants].
static func split_flicker(glows: Array, every: int, min_radius: float, max_radius: float, seed_value: int) -> Array:
	var keep: Array = []
	var fl: Array = []
	var n: int = 0
	for g: Array in glows:
		var r: float = float(g[1])
		if every > 0 and r >= min_radius and r <= max_radius:
			n += 1
			if (n + seed_value) % every == 0:
				fl.append(g)
				continue
		keep.append(g)
	return [keep, fl]


## Voyants clignotants : un sur `every` des lueurs de panneaux muraux (rayon dans
## [min_radius, max_radius]) reçoit un petit point vif de rayon `led_radius`.
static func pick_leds(glows: Array, every: int, min_radius: float, max_radius: float, led_radius: float,
		seed_value: int) -> Array:
	var out: Array = []
	var n: int = 0
	for g: Array in glows:
		var r: float = float(g[1])
		if every <= 0 or r < min_radius or r > max_radius:
			continue
		n += 1
		if (n + seed_value) % every == 0:
			out.append([g[0] as Vector2 + Vector2(0.0, -6.0), led_radius, (g[2] as Color).lightened(0.2), 1.0])
	return out


func _load_cfg() -> void:
	fog_refresh = maxf(Balance.get_float("ambient_lights", "fog_refresh", 0.2), 0.05)
	flicker_speed = Balance.get_float("ambient_lights", "flicker_speed", 9.0)
	flicker_min = Balance.get_float("ambient_lights", "flicker_min", 0.15)
	blink_speed = Balance.get_float("ambient_lights", "blink_speed", 1.3)
	blink_duty = Balance.get_float("ambient_lights", "blink_duty", 0.55)
	alarm_speed = Balance.get_float("ambient_lights", "alarm_speed", 2.2)
	alarm_min = Balance.get_float("ambient_lights", "alarm_min", 0.25)
	alpha = Balance.get_float("ambient_lights", "alpha", 0.38)


func _add_group(group_name: StringName, lights: Array, core: float) -> void:
	if lights.is_empty():
		return
	var g := Group.new()
	g.name = String(group_name).capitalize()
	g.tex = _tex
	g.region = _region
	g.lights = lights
	g.core_scale = core
	g.alpha = alpha
	g.material = WorldProp.glow_material()
	g.z_as_relative = true
	add_child(g)
	_groups[group_name] = g


## Dégradé radial blanc (halo) quand le biome n'a pas de pièce « glow ».
static func fallback_texture() -> Texture2D:
	if _fallback == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_fallback = gt
	return _fallback


func _ready() -> void:
	set_process(not _groups.is_empty())


func get_group(group_name: StringName) -> Group:
	return _groups.get(group_name) as Group


func light_count() -> int:
	var n: int = 0
	for g: Group in _groups.values():
		n += g.lights.size()
	return n


## Facteur de grésillement d'un néon (0..1) au temps `t` : allumé la plupart du temps, avec de
## brèves chutes irrégulières. Logique pure (tests).
static func flicker_value(t: float, speed: float, floor_v: float) -> float:
	var a: float = sin(t * speed) + sin(t * speed * 2.37 + 1.3) * 0.7 + sin(t * speed * 0.41 + 4.1) * 0.9
	return floor_v if a > 1.55 else 1.0


## Voyant : marche/arrêt (rapport cyclique `duty`). Logique pure.
static func blink_value(t: float, speed: float, duty: float) -> float:
	return 1.0 if fposmod(t * speed, 1.0) < duty else 0.0


## Alarme : pulsation douce entre `floor_v` et 1. Logique pure.
static func alarm_value(t: float, speed: float, floor_v: float) -> float:
	return lerpf(floor_v, 1.0, maxf(sin(t * speed), 0.0))


func _process(delta: float) -> void:
	_t += delta
	var f: Group = _groups.get(GROUP_FLICKER) as Group
	if f != null:
		f.modulate.a = flicker_value(_t, flicker_speed, flicker_min)
	var b: Group = _groups.get(GROUP_BLINK) as Group
	if b != null:
		b.modulate.a = blink_value(_t, blink_speed, blink_duty)
	var a: Group = _groups.get(GROUP_ALARM) as Group
	if a != null:
		a.modulate.a = alarm_value(_t, alarm_speed, alarm_min)
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = fog_refresh
		_refresh_visibility()


## Brouillard : seules les lumières animées dont la case est visible sont dessinées.
func _refresh_visibility() -> void:
	if _fog == null or not is_instance_valid(_fog):
		_fog = _find_fog()
	for g: Group in _groups.values():
		if _fog == null:
			g.all_visible = true
			continue
		g.all_visible = false
		var mask := PackedByteArray()
		mask.resize(g.lights.size())
		for i: int in g.lights.size():
			var l: Array = g.lights[i]
			var probe: Vector2 = l[4] if l.size() > 4 else (l[0] as Vector2) + Vector2(0.0, 8.0)
			mask[i] = 1 if bool(_fog.call("is_cell_visible", FloorLayout.world_to_cell(probe))) else 0
		g.set_shown(mask)


## FogOfWar de l'étage (frère d'un ancêtre) ; abandon après quelques essais (pas de brouillard).
func _find_fog() -> Node:
	if _fog_lookups > 20:
		return null
	_fog_lookups += 1
	var n: Node = get_parent()
	while n != null:
		var f: Node = n.get_node_or_null(^"FogOfWar")
		if f != null and f.has_method("is_cell_visible"):
			return f
		n = n.get_parent()
	return null
