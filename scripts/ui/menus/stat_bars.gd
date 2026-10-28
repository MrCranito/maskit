class_name StatBars
extends VBoxContainer
## Barres de stats d'une arme (dégâts, cadence, portée, chargeur, DPS) ou d'un équipement
## (dégâts, rayon, durée, charges), normalisées sur le maximum du catalogue (calculé une fois).
## Les lignes sont reconstruites seulement quand on passe d'arme à équipement ; changement animé.

const WEAPON_STATS: Array[Array] = [
	["damage", "Dégâts"], ["fire_rate", "Cadence"], ["range", "Portée"],
	["magazine", "Chargeur"], ["dps", "DPS"],
]
const GADGET_STATS: Array[Array] = [
	["blast", "Dégâts"], ["radius", "Rayon"], ["duration", "Durée"], ["charges", "Charges"],
]
## Compatibilité.
const STATS: Array[Array] = WEAPON_STATS

var bars: Dictionary = {}     ## clé → Panel (remplissage)
var values: Dictionary = {}   ## clé → Label
var _mode: int = -1           ## 0 arme, 1 équipement

static var _max: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build(0)


func _build(mode: int) -> void:
	if mode == _mode:
		return
	_mode = mode
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	bars.clear()
	values.clear()
	for s: Array in (GADGET_STATS if mode == 1 else WEAPON_STATS):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var l := MenuKit.label(String(s[1]), 15, MenuKit.TEXT_DIM, MenuKit.nunito(800))
		l.custom_minimum_size = Vector2(78, 0)
		row.add_child(l)
		var track := Panel.new()
		track.custom_minimum_size = Vector2(0, 14)
		track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ts := StyleBoxFlat.new()
		ts.bg_color = Color(1, 1, 1, 0.1)
		ts.set_corner_radius_all(6)
		track.add_theme_stylebox_override("panel", ts)
		row.add_child(track)
		var fill := Panel.new()
		var fs := StyleBoxFlat.new()
		fs.bg_color = MenuKit.GOLD
		fs.set_corner_radius_all(7)
		fill.add_theme_stylebox_override("panel", fs)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.anchor_bottom = 1.0
		fill.anchor_right = 0.0
		track.add_child(fill)
		var v := MenuKit.label("", 15, MenuKit.TEXT, MenuKit.nunito(900))
		v.custom_minimum_size = Vector2(52, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(v)
		bars[s[0]] = fill
		values[s[0]] = v


static func stat_value(w: WeaponData, key: String) -> float:
	match key:
		"damage":
			return w.damage * maxi(w.projectile_count, 1) + w.explosion_damage
		"fire_rate":
			return w.fire_rate
		"range":
			return w.range
		"magazine":
			return float(w.magazine_size) if w.magazine_size > 0 else 60.0
		"dps":
			return w.get_dps()
		"blast":
			return maxf(w.explosion_damage, w.damage)
		"radius":
			return maxf(w.effect_radius, w.explosion_radius)
		"duration":
			return w.effect_duration
		"charges":
			return float(w.charges)
	return 0.0


static func stat_max(key: String) -> float:
	if _max.is_empty():
		var floors := {"damage": 40.0, "fire_rate": 8.0, "range": 900.0, "magazine": 40.0, "dps": 150.0,
			"blast": 100.0, "radius": 200.0, "duration": 10.0, "charges": 3.0}
		for k: String in floors:
			_max[k] = floors[k]
		for w: WeaponData in WeaponCatalog.all():
			for k: String in floors:
				var gadget_key: bool = k in ["blast", "radius", "duration", "charges"]
				if gadget_key == w.is_gadget():
					_max[k] = maxf(float(_max[k]), stat_value(w, k))
	return float(_max.get(key, 1.0))


static func format_value(w: WeaponData, key: String) -> String:
	match key:
		"fire_rate":
			return ("%.1f/s" % w.fire_rate).replace(".", ",")
		"range", "radius":
			return str(roundi(stat_value(w, key) / 10.0))
		"magazine":
			return "∞" if w.magazine_size <= 0 else str(w.magazine_size)
		"duration":
			return ("%.0f s" % w.effect_duration) if w.effect_duration > 0.0 else "-"
	return str(roundi(stat_value(w, key)))


func show_weapon(w: WeaponData, color: Color = MenuKit.GOLD) -> void:
	_build(1 if w != null and w.is_gadget() else 0)
	for key: Variant in bars:
		var fill: Panel = bars[key]
		var f: float = 0.0
		if w != null:
			f = clampf(stat_value(w, key) / stat_max(key), 0.04, 1.0)
		(values[key] as Label).text = format_value(w, key) if w != null else "-"
		(fill.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = color
		fill.offset_right = 0.0
		if is_inside_tree():
			create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
				.tween_property(fill, "anchor_right", f, 0.25).from(0.0)
		else:
			fill.anchor_right = f
