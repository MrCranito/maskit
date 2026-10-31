class_name HcLights
extends RefCounted
## Éclairage du Carnaval hanté (logique pure) : lumières calculées depuis le plan de l'étage
## (lampadaires, allées, stands, manèges, place, portail), pour AmbientLights. Le rendu
## pré-calculé est une nuit très sombre et ses lueurs 2D sont masquées : sans ces halos,
## l'étage était presque noir.
##   - steady  : lumières fixes (flaques de lampadaires, guirlandes, portes et intérieurs des
##               stands, lueur des manèges, place, portail du clown) ;
##   - flicker : un lampadaire sur `lamp_flicker_every` grésille (ambiance hantée) ;
##   - blink   : ampoules de la grande roue et des manèges, en alternance.
## Lumière : [position monde, rayon px, couleur, intensité]. Réglages : [haunted_carnival] lights_*.

const TS := float(FloorLayout.TILE_SIZE)
const LAMP := &"hc_lamp_post"
const GARLAND_COLORS: Array[Color] = [Color(1.0, 0.78, 0.4), Color(1.0, 0.35, 0.75), Color(0.45, 0.85, 1.0), Color(0.75, 1.0, 0.45)]


static func f(key: String, def: float) -> float:
	return Balance.get_float("haunted_carnival", "lights_" + key, def)


static func c(key: String, def: Color) -> Color:
	var v: Variant = Balance.get_value("haunted_carnival", "lights_" + key, def)
	return v if v is Color else def


static func _l(p: Vector2, r: float, col: Color, k: float) -> Array:
	return [p, r, col, k]


## {"steady": Array, "flicker": Array, "blink": Array}.
static func compute(L: FloorLayout) -> Dictionary:
	var steady: Array = []
	var flicker: Array = []
	var blink: Array = []
	if L == null:
		return {"steady": steady, "flicker": flicker, "blink": blink}
	var ct: Dictionary = L.get_meta(&"render_contract", {})
	# Lampadaires : flaque au sol + tête lumineuse ; un sur N grésille.
	var lamp_col := c("lamp_color", Color(1.0, 0.8, 0.52))
	var every := int(f("lamp_flicker_every", 5.0))
	var n := 0
	for sp: FloorLayout.Spawn in L.prop_spawns:
		if sp.kind != LAMP:
			continue
		n += 1
		var base := FloorLayout.cell_to_world(sp.cell) + Vector2(0.0, TS * 0.25) + sp.offset
		var pool := _l(base, f("lamp_pool_radius", 230.0), lamp_col, f("lamp_pool", 1.05))
		var head := _l(base + Vector2(0.0, f("lamp_head_offset", -150.0)), f("lamp_head_radius", 48.0),
			lamp_col.lightened(0.2), f("lamp_head", 1.5))
		if every > 0 and n % every == 0:
			flicker.append(pool)
			flicker.append(head)
		else:
			steady.append(pool)
			steady.append(head)
	# Allées : voile lumineux large et guirlandes d'ampoules colorées le long du tracé.
	var wash_step := maxf(f("path_wash_step", 7.0), 1.0)
	var bulb_step := maxf(f("garland_step", 3.0), 1.0)
	var wash_col := c("path_wash_color", Color(0.95, 0.72, 0.95))
	var bi := 0
	for pth: Dictionary in ct.get("paths", []):
		var pts: Array = pth.get("pts", [])
		var half := float(pth.get("w", 3.0)) * 0.5
		for seg in range(pts.size() - 1):
			var a: Vector2 = pts[seg]
			var b: Vector2 = pts[seg + 1]
			var len_cells := a.distance_to(b)
			var dir := (b - a).normalized()
			var side := dir.orthogonal()
			var t := 0.0
			while t <= len_cells:
				var p := a + dir * t
				if fmod(t, wash_step) < bulb_step:
					steady.append(_l(p * TS, f("path_wash_radius", 260.0), wash_col, f("path_wash", 0.6)))
				# Guirlande : ampoules en zigzag d'un bord à l'autre de l'allée.
				var s := (half - 0.3) * (1.0 if bi % 2 == 0 else -1.0)
				steady.append(_l((p + side * s) * TS, f("garland_radius", 52.0),
					GARLAND_COLORS[bi % GARLAND_COLORS.size()], f("garland", 1.8)))
				bi += 1
				t += bulb_step
	# Place centrale (autour du chapiteau) et cours des manèges : voile doux.
	var plaza_col := c("plaza_color", Color(1.0, 0.7, 0.85))
	for y0: Dictionary in ct.get("yards", []):
		var yc: Vector2 = y0.get("c", Vector2.ZERO)
		var yr: Vector2 = y0.get("r", Vector2.ONE)
		steady.append(_l(yc * TS, minf(yr.x, yr.y) * TS * 0.9, plaza_col, f("yard", 0.7)))
	var pe: Dictionary = ct.get("plaza_e", {})
	if not pe.is_empty():
		var pc: Vector2 = pe["c"]
		var pr: Vector2 = pe["r"]
		for k in 8:
			var a2 := TAU * float(k) / 8.0
			steady.append(_l((pc + Vector2(cos(a2) * pr.x, sin(a2) * pr.y) * 0.78) * TS, f("plaza_radius", 300.0),
				plaza_col, f("plaza", 0.55)))
	# Manèges : lueur centrale + couronne d'ampoules qui clignotent.
	var ride_col := c("ride_color", Color(1.0, 0.5, 0.85))
	for rd: Dictionary in ct.get("rides", []):
		var rc: Vector2 = rd["c"]
		var rr := float(rd["r"])
		steady.append(_l(rc * TS, rr * TS * 1.5, ride_col, f("ride", 1.1)))
		var nb := int(f("ride_bulbs", 14.0))
		for k2 in nb:
			var a3 := TAU * float(k2) / float(maxi(nb, 1))
			var col := GARLAND_COLORS[k2 % GARLAND_COLORS.size()]
			var bulb := _l((rc + Vector2(cos(a3), sin(a3)) * rr) * TS, f("ride_bulb_radius", 46.0), col, f("ride_bulb", 2.0))
			if k2 % 2 == 0:
				blink.append(bulb)
			else:
				steady.append(bulb)
	# Stands, roulottes, halls : lueur chaude aux portes et dans chaque intérieur.
	var warm := c("stand_color", Color(1.0, 0.72, 0.42))
	for d: FloorLayout.Door in L.doors:
		steady.append(_l(FloorLayout.cell_to_world(d.cell), f("door_radius", 120.0), warm, f("door", 1.3)))
	for m: Dictionary in ct.get("modules", []):
		var r: Rect2i = m.get("rect", Rect2i())
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		var rad := minf(r.size.x, r.size.y) * TS * 0.55
		steady.append(_l((Vector2(r.position) + Vector2(r.size) * 0.5) * TS, clampf(rad, 120.0, 420.0), warm, f("interior", 0.9)))
	# Portail du clown.
	var go: Variant = ct.get("gate_open", null)
	if go is Rect2i:
		var gr := go as Rect2i
		steady.append(_l(Vector2(gr.position.x + gr.size.x * 0.5, gr.position.y) * TS, f("gate_radius", 320.0),
			c("gate_color", Color(1.0, 0.4, 0.8)), f("gate", 1.6)))
	return {"steady": steady, "flicker": flicker, "blink": blink}
